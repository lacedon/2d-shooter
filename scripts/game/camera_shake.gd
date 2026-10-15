class_name CameraShake
extends Camera2D
## Trauma-based screen shake (offset scales with trauma^2).

const MAX_OFFSET := 14.0
const DECAY := 2.2

var trauma: float = 0.0


func _ready() -> void:
	Events.shake_requested.connect(add_trauma)


func add_trauma(amount: float) -> void:
	trauma = minf(trauma + amount, 1.0)


func _process(delta: float) -> void:
	if trauma <= 0.0:
		if offset != Vector2.ZERO:
			offset = Vector2.ZERO
		return
	trauma = maxf(trauma - DECAY * delta, 0.0)
	var s := trauma * trauma
	offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * MAX_OFFSET * s


func set_bounds(r: Rect2) -> void:
	limit_left = int(r.position.x)
	limit_top = int(r.position.y)
	limit_right = int(r.end.x)
	limit_bottom = int(r.end.y)
	reset_smoothing.call_deferred()  # don't glide in from the origin after the player is placed
