class_name Spawner
extends StaticBody2D
## Destructible enemy spawner. Blocks its flow-field cell while alive and
## spawns bursts while the player is within activation_radius.

@export var zombie_stats: EnemyStats
@export var robot_stats: EnemyStats
@export var max_hp: int = 12
@export var interval: float = 1.1
@export var burst: int = 2
@export var robot_chance: float = 0.25
@export var own_cap: int = 30
@export var activation_radius: float = 1100.0

const SPAWN_RING := 60.0  # stays inside the guaranteed 3x3 floor clearance
const BASE_SCALE := Vector2(1.1, 1.1)
const SQUASH_SCALE := Vector2(1.25, 0.9)

var hp: int = 12
var _alive: int = 0
var _t: float = 0.0
var _manager: EnemyManager
var _field: FlowField
var _cell: Vector2i = Vector2i(-1, -1)
var _flash_t: float = 0.0
var _dead: bool = false

@onready var _sprite: Sprite2D = $Sprite


func setup(manager: EnemyManager, field: FlowField) -> void:
	_manager = manager
	_field = field
	_cell = field.world_to_cell(global_position)
	field.set_blocked(_cell, true)
	hp = max_hp
	_t = randf() * interval  # desync spawners


func _physics_process(delta: float) -> void:
	if _manager == null:
		return
	if _flash_t > 0.0:
		_flash_t -= delta
		if _flash_t <= 0.0:
			_sprite.self_modulate = Color.WHITE
	if _sprite.scale != BASE_SCALE:
		_sprite.scale = _sprite.scale.lerp(BASE_SCALE, minf(10.0 * delta, 1.0))

	_t -= delta
	if _t > 0.0:
		return
	_t = interval

	if not _manager.is_player_alive():
		return
	if global_position.distance_squared_to(_manager.player_position()) > activation_radius * activation_radius:
		return

	var spawned := false
	for k in burst:
		if _alive >= own_cap:
			break
		var s := robot_stats if randf() < robot_chance else zombie_stats
		var pos := global_position + Vector2.from_angle(randf() * TAU) * SPAWN_RING
		if _manager.spawn(s, pos, self) != null:
			_alive += 1
			spawned = true
	if spawned:
		_sprite.scale = SQUASH_SCALE


func on_enemy_died() -> void:
	_alive = maxi(_alive - 1, 0)


func take_damage(amount: int, _impulse: Vector2) -> void:
	if _dead:
		return
	hp -= amount
	_flash_t = 0.08
	_sprite.self_modulate = Color(3, 3, 3)
	Sfx.play(&"spawner_hit")
	Events.bullet_impact.emit(global_position)
	var broken := clampf(1.0 - float(hp) / float(max_hp), 0.0, 1.0)
	var g := lerpf(1.0, 0.45, broken)
	_sprite.modulate = Color(1, g, g, 1)  # reddens as it breaks
	if hp <= 0:
		_die()


func _die() -> void:
	_dead = true
	if _field != null:
		_field.set_blocked(_cell, false)
	Sfx.play(&"spawner_boom")
	Events.shake_requested.emit(0.6)
	Events.spawner_destroyed.emit(global_position)
	queue_free()  # already deferred; safe inside physics callbacks
