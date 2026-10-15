class_name EnemyManager
extends Node2D
## Owns the enemy pool and the active list; steps every active enemy from
## one _physics_process and keeps the shared FlowField pointed at the player.

const RECOMPUTE_INTERVAL := 0.15

@export var enemy_scene: PackedScene
@export var pool_size: int = 160
@export var max_alive: int = 140

var player: Player
var field: FlowField

var _pool: NodePool
var _active: Array[Enemy] = []
var _recompute_cd: float = 0.0


func _ready() -> void:
	_pool = NodePool.new(enemy_scene, pool_size, self, func(n: Node) -> void:
		(n as Enemy).manager = self)


func setup(p: Player, f: FlowField) -> void:
	player = p
	field = f
	field.update(player.global_position)


func alive_count() -> int:
	return _active.size()


func player_position() -> Vector2:
	return player.global_position if player != null else Vector2.ZERO


func is_player_alive() -> bool:
	return player != null and not player.is_dead()


func spawn(stats: EnemyStats, pos: Vector2, home: Spawner) -> Enemy:
	if _active.size() >= max_alive:
		return null
	var e := _pool.acquire() as Enemy
	if e == null:
		return null
	e.activate(stats, pos, home)
	_add_active(e)
	return e


func release(e: Enemy) -> void:
	if e.active_index < 0:
		return
	_remove_active(e)
	e.visible = false
	_finish_release.call_deferred(e)


func _finish_release(e: Enemy) -> void:
	_pool.release(e)


func _physics_process(delta: float) -> void:
	if player == null:
		return
	_recompute_cd -= delta
	if _recompute_cd <= 0.0 and not player.is_dead():
		if field.update(player.global_position):
			_recompute_cd = RECOMPUTE_INTERVAL
	var pp := player.global_position
	var i := _active.size() - 1
	while i >= 0:
		_active[i].step(delta, pp, field)
		i -= 1


func _add_active(e: Enemy) -> void:
	e.active_index = _active.size()
	_active.append(e)


func _remove_active(e: Enemy) -> void:
	var last: Enemy = _active.pop_back()
	if last != e:
		_active[e.active_index] = last
		last.active_index = e.active_index
	e.active_index = -1
