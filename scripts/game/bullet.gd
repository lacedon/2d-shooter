class_name Bullet
extends Area2D
## Pooled player bullet. Moved by BulletPool; hits via body_entered.

var velocity: Vector2 = Vector2.ZERO
var life: float = 0.0
var damage: int = 1
var knockback: float = 0.0
var active_index: int = -1
var pool: BulletPool


func _on_body_entered(body: Node2D) -> void:
	if active_index < 0:
		return  # already spent this frame
	var impulse := velocity.normalized() * knockback
	if body is Enemy:
		var e := body as Enemy
		if e.active_index < 0:
			return  # killed earlier this physics step (release is deferred): pass through
		e.take_damage(damage, impulse)
	elif body is Spawner:
		(body as Spawner).take_damage(damage, impulse)
	elif body.has_method(&"take_damage"):
		body.call(&"take_damage", damage, impulse)
	else:
		Events.bullet_impact.emit(global_position)  # wall hit
	pool.release(self)
