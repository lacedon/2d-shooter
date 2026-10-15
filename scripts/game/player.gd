class_name Player
extends CharacterBody2D
## Top-down player: 8-way movement, mouse/right-stick aim, dash, 3 weapons.
## Enum FSM (NORMAL / DASH / DEAD). The body never rotates; Pivot does.

enum State { NORMAL, DASH, DEAD }

const SPEED := 300.0
const ACCEL := 2400.0
const DASH_SPEED := 950.0
const DASH_TIME := 0.14
const DASH_COOLDOWN := 0.45
const MAX_HP := 10
const HIT_IFRAMES := 0.7
const DASH_BUFFER := 0.12

const WEAPONS: Array[WeaponData] = [
	preload("res://data/weapons/pistol.tres"),
	preload("res://data/weapons/machine_gun.tres"),
	preload("res://data/weapons/shotgun.tres"),
]

var bullet_pool: BulletPool                 ## injected by Game
var aim_direction: Vector2 = Vector2.RIGHT  ## read-only by convention
var using_gamepad: bool = false
var hp: int = MAX_HP

var _state: State = State.NORMAL
var _weapon: WeaponData
var _weapon_index: int = -1
var _fire_cd: float = 0.0
var _dash_cd: float = 0.0
var _iframes: float = 0.0
var _dash_buffer: float = 0.0
var _flash_t: float = 0.0
var _muzzle_t: float = 0.0
var _dash_t: float = 0.0
var _dash_dir: Vector2 = Vector2.RIGHT

@onready var _pivot: Node2D = $Pivot
@onready var _sprite: Sprite2D = $Pivot/Sprite
@onready var _muzzle: Marker2D = $Pivot/Muzzle
@onready var _flash: Sprite2D = $Pivot/Muzzle/Flash
@onready var _hurtbox: Area2D = $Hurtbox
@onready var _shape: CollisionShape2D = $Shape


func _ready() -> void:
	hp = MAX_HP
	equip(0)
	Events.player_health_changed.emit(hp, MAX_HP)


## Re-emits HP and weapon so late subscribers (HUD) get the current state.
func broadcast_state() -> void:
	Events.player_health_changed.emit(hp, MAX_HP)
	Events.weapon_changed.emit(_weapon_index, _weapon)


func is_dead() -> bool:
	return _state == State.DEAD


func _input(event: InputEvent) -> void:
	# Device detection by event type only (4.7 changed keyboard/mouse device ids).
	if event is InputEventJoypadButton:
		using_gamepad = true
	elif event is InputEventJoypadMotion:
		if absf((event as InputEventJoypadMotion).axis_value) > 0.4:
			using_gamepad = true
	elif event is InputEventMouseMotion:
		if (event as InputEventMouseMotion).relative.length_squared() > 4.0:
			using_gamepad = false
	elif event is InputEventMouseButton or event is InputEventKey:
		using_gamepad = false


func _unhandled_input(event: InputEvent) -> void:
	if _state == State.DEAD:
		return
	if event.is_action_pressed(&"dash"):
		# Every trigger (LT) motion event past the deadzone counts as "pressed";
		# only the initial press may buffer a dash, or holding LT re-dashes.
		if not event is InputEventJoypadMotion or Input.is_action_just_pressed(&"dash"):
			_dash_buffer = DASH_BUFFER
	elif event.is_action_pressed(&"weapon_1"):
		equip(0)
	elif event.is_action_pressed(&"weapon_2"):
		equip(1)
	elif event.is_action_pressed(&"weapon_3"):
		equip(2)
	elif event.is_action_pressed(&"weapon_next"):
		equip(posmod(_weapon_index + 1, WEAPONS.size()))
	elif event.is_action_pressed(&"weapon_prev"):
		equip(posmod(_weapon_index - 1, WEAPONS.size()))


func _physics_process(delta: float) -> void:
	_fire_cd -= delta
	_dash_cd -= delta
	_iframes -= delta
	_dash_buffer -= delta
	_flash_t -= delta
	_muzzle_t -= delta

	if _state == State.DEAD:
		return

	var move := Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")

	# Aim
	if using_gamepad:
		var stick := Input.get_vector(&"aim_left", &"aim_right", &"aim_up", &"aim_down")
		if stick != Vector2.ZERO:
			aim_direction = stick.normalized()
		elif move != Vector2.ZERO:
			aim_direction = move.normalized()
	else:
		var v := get_global_mouse_position() - global_position
		if v.length_squared() > 16.0:
			aim_direction = v.normalized()
	_pivot.rotation = aim_direction.angle()

	# State
	match _state:
		State.NORMAL:
			if _dash_buffer > 0.0 and _dash_cd <= 0.0:
				_dash_dir = move.normalized() if move != Vector2.ZERO else aim_direction
				_state = State.DASH
				_dash_t = DASH_TIME
				_dash_cd = DASH_COOLDOWN
				_iframes = maxf(_iframes, DASH_TIME + 0.05)
				_dash_buffer = 0.0
				Sfx.play(&"dash")
				Events.bullet_impact.emit(global_position)  # dash dust
			else:
				velocity = velocity.move_toward(move * SPEED, ACCEL * delta)
		State.DASH:
			velocity = _dash_dir * DASH_SPEED
			_dash_t -= delta
			if _dash_t <= 0.0:
				_state = State.NORMAL
				velocity = _dash_dir * SPEED
		_:
			pass

	move_and_slide()

	# Shooting (allowed while dashing)
	if Input.is_action_pressed(&"shoot") and _fire_cd <= 0.0:
		_fire()
		_fire_cd = _weapon.fire_interval

	# Contact damage (allocates, but at most once per i-frame window)
	if _iframes <= 0.0 and _hurtbox.has_overlapping_bodies():
		var dmg := 0
		for body: Node2D in _hurtbox.get_overlapping_bodies():
			if body is Enemy:
				dmg = maxi(dmg, (body as Enemy).get_contact_damage())
		if dmg > 0:
			take_damage(dmg)

	# Visuals
	_sprite.self_modulate = Color(1, 0.35, 0.35) if _flash_t > 0.0 else Color.WHITE
	var flicker := _iframes > 0.0 and _state != State.DASH and int(_iframes * 16.0) % 2 == 0
	_sprite.modulate.a = 0.5 if flicker else 1.0
	_flash.visible = _muzzle_t > 0.0


func _fire() -> void:
	if bullet_pool == null:
		return
	var w := _weapon
	var base := aim_direction.angle()
	var origin := _muzzle.global_position
	var half := w.spread_deg * 0.5
	for i in w.pellets:
		var off: float
		if w.pellets > 1:
			off = deg_to_rad(lerpf(-half, half, float(i) / float(w.pellets - 1)) + randf_range(-2.0, 2.0))
		else:
			off = deg_to_rad(randf_range(-half, half))
		bullet_pool.fire(origin, Vector2.from_angle(base + off), w)
	_muzzle_t = 0.05
	Sfx.play(w.sfx)
	Events.shake_requested.emit(w.shake)


func equip(i: int) -> void:
	if i == _weapon_index or i < 0 or i >= WEAPONS.size():
		return
	var initial := _weapon == null
	var w := WEAPONS[i]
	_weapon = w
	_weapon_index = i
	_sprite.texture = w.player_texture
	_sprite.offset = w.sprite_offset
	_muzzle.position = w.muzzle_offset
	_fire_cd = minf(_fire_cd, 0.1)
	Events.weapon_changed.emit(i, w)
	if not initial:
		Sfx.play(&"weapon_switch")


func take_damage(amount: int) -> void:
	if _state == State.DEAD or _iframes > 0.0:
		return
	hp = maxi(hp - amount, 0)
	_iframes = HIT_IFRAMES
	_flash_t = 0.12
	Sfx.play(&"player_hurt")
	Events.shake_requested.emit(0.4)
	Events.player_health_changed.emit(hp, MAX_HP)
	if hp == 0:
		_state = State.DEAD
		velocity = Vector2.ZERO
		_pivot.visible = false
		_shape.set_deferred(&"disabled", true)
		Events.bullet_impact.emit(global_position)  # death puff
		Events.player_died.emit()
