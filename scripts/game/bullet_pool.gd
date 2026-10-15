class_name BulletPool
extends Node2D
## Owns all player bullets: fixed pool + swap-remove active list.

@export var bullet_scene: PackedScene
@export var pool_size: int = 256

var _pool: NodePool
var _active: Array[Bullet] = []


func _ready() -> void:
	_pool = NodePool.new(bullet_scene, pool_size, self, func(n: Node) -> void:
		var b := n as Bullet
		b.pool = self
		b.body_entered.connect(b._on_body_entered))


func fire(pos: Vector2, dir: Vector2, w: WeaponData) -> void:
	var b := _pool.acquire() as Bullet
	if b == null:
		return  # pool exhausted: silently skip
	b.global_position = pos
	b.rotation = dir.angle()
	b.velocity = dir * w.bullet_speed
	b.life = w.bullet_lifetime
	b.damage = w.damage
	b.knockback = w.knockback
	b.visible = true
	b.process_mode = Node.PROCESS_MODE_INHERIT
	_add_active(b)


func active_count() -> int:
	return _active.size()


func free_count() -> int:
	return _pool.free_count()


func _physics_process(delta: float) -> void:
	var i := _active.size() - 1
	while i >= 0:
		var b := _active[i]
		b.position += b.velocity * delta
		b.life -= delta
		if b.life <= 0.0:
			release(b)
		i -= 1


func release(b: Bullet) -> void:
	if b.active_index < 0:
		return
	_remove_active(b)
	b.visible = false
	_finish_release.call_deferred(b)


func _finish_release(b: Bullet) -> void:
	_pool.release(b)


func _add_active(b: Bullet) -> void:
	b.active_index = _active.size()
	_active.append(b)


func _remove_active(b: Bullet) -> void:
	var last: Bullet = _active.pop_back()
	if last != b:
		_active[b.active_index] = last
		last.active_index = b.active_index
	b.active_index = -1
