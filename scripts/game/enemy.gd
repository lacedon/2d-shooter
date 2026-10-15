class_name Enemy
extends CharacterBody2D
## Pooled enemy (zombie or robot, defined by EnemyStats).
## Stepped by EnemyManager; has no _physics_process of its own.

const DIRECT_CHASE_DIST_SQ := 9216.0   # 96 px: steer straight at the player
const KNOCK_DECAY := 1800.0
const TURN_RATE := 12.0

var stats: EnemyStats
var hp: int = 1
var active_index: int = -1
var home: Spawner          ## may be freed; check is_instance_valid
var manager: EnemyManager  ## injected by EnemyManager pool

var _speed: float = 0.0
var _knock: Vector2 = Vector2.ZERO
var _flash_t: float = 0.0

@onready var _sprite: Sprite2D = $Sprite


func _ready() -> void:
	set_physics_process(false)


func activate(s: EnemyStats, pos: Vector2, home_spawner: Spawner) -> void:
	stats = s
	hp = s.max_hp
	_speed = s.speed * randf_range(0.9, 1.1)
	_knock = Vector2.ZERO
	velocity = Vector2.ZERO
	_flash_t = 0.0
	_sprite.texture = s.texture
	_sprite.self_modulate = Color.WHITE
	global_position = pos
	rotation = randf() * TAU
	home = home_spawner
	visible = true
	process_mode = Node.PROCESS_MODE_INHERIT


func step(delta: float, player_pos: Vector2, field: FlowField) -> void:
	var to_p := player_pos - global_position
	var dir: Vector2
	if to_p.length_squared() < DIRECT_CHASE_DIST_SQ:
		dir = to_p.normalized()
	else:
		dir = field.get_direction(global_position)
		if dir == Vector2.ZERO:
			dir = to_p.normalized()
	velocity = velocity.lerp(dir * _speed, minf(stats.accel * delta, 1.0)) + _knock
	_knock = _knock.move_toward(Vector2.ZERO, KNOCK_DECAY * delta)
	move_and_slide()
	if velocity.length_squared() > 1.0:
		rotation = lerp_angle(rotation, velocity.angle(), minf(TURN_RATE * delta, 1.0))
	if _flash_t > 0.0:
		_flash_t -= delta
		if _flash_t <= 0.0:
			_sprite.self_modulate = Color.WHITE


func take_damage(amount: int, impulse: Vector2) -> void:
	if active_index < 0:
		return
	hp -= amount
	if hp <= 0:
		die()
		return
	_knock += impulse * stats.knockback_scale
	_flash_t = 0.08
	_sprite.self_modulate = Color(4, 4, 4)  # bright hit flash, no material needed
	if stats.hit_sfx != &"":
		Sfx.play(stats.hit_sfx)
	Events.bullet_impact.emit(global_position)


func die() -> void:
	Events.enemy_killed.emit(global_position, stats)
	if stats.death_sfx != &"":
		Sfx.play(stats.death_sfx)
	if is_instance_valid(home):
		home.on_enemy_died()
	home = null
	manager.release(self)


func get_contact_damage() -> int:
	# Dead-but-not-yet-released enemies (deferred release) deal no damage.
	return stats.contact_damage if stats != null and active_index >= 0 else 0
