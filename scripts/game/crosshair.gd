class_name Crosshair
extends Sprite2D
## World-space crosshair: follows the mouse, or sits ahead of the player on gamepad.

const GAMEPAD_DISTANCE := 170.0

var player: Player  ## injected by Game


func _process(_delta: float) -> void:
	if player == null:
		return
	if player.using_gamepad:
		global_position = player.global_position + player.aim_direction * GAMEPAD_DISTANCE
	else:
		global_position = get_global_mouse_position()
	visible = not player.is_dead()
