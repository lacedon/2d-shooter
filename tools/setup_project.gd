extends SceneTree
## One-off, idempotent project configuration tool.
## Run with: $GODOT --headless --path . -s res://tools/setup_project.gd
## Writes input map, physics layer names, autoloads, main scene and window settings.
## Do NOT run while the editor is open (it would overwrite project.godot on save).


func _init() -> void:
	_setup_input()
	_setup_misc()
	var err := ProjectSettings.save()
	if err != OK:
		push_error("setup_project: ProjectSettings.save() failed with %d" % err)
	else:
		print("setup_project: project.godot updated")
	quit()


# --- Event helpers (every event gets device = -1, i.e. all devices) ---------

func _key(physical: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.device = -1
	e.physical_keycode = physical
	e.keycode = KEY_NONE
	return e


func _mouse(button: MouseButton) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.device = -1
	e.button_index = button
	return e


func _joy_button(button: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.device = -1
	e.button_index = button
	return e


func _joy_axis(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.device = -1
	e.axis = axis
	e.axis_value = value
	return e


func _action(action_name: String, deadzone: float, events: Array) -> void:
	ProjectSettings.set_setting("input/" + action_name, {"deadzone": deadzone, "events": events})


func _append_joy_button(action_name: String, button: JoyButton) -> void:
	var current: Dictionary = ProjectSettings.get_setting("input/" + action_name, {})
	var deadzone: float = current.get("deadzone", 0.5)
	var events: Array = (current.get("events", []) as Array).duplicate()
	for ev: Variant in events:
		var jb := ev as InputEventJoypadButton
		if jb != null and jb.button_index == button:
			return  # already present (idempotent)
	events.append(_joy_button(button))
	ProjectSettings.set_setting("input/" + action_name, {"deadzone": deadzone, "events": events})


# --- Settings ----------------------------------------------------------------

func _setup_input() -> void:
	_action("move_left", 0.25, [_key(KEY_A), _key(KEY_LEFT), _joy_axis(JOY_AXIS_LEFT_X, -1.0)])
	_action("move_right", 0.25, [_key(KEY_D), _key(KEY_RIGHT), _joy_axis(JOY_AXIS_LEFT_X, 1.0)])
	_action("move_up", 0.25, [_key(KEY_W), _key(KEY_UP), _joy_axis(JOY_AXIS_LEFT_Y, -1.0)])
	_action("move_down", 0.25, [_key(KEY_S), _key(KEY_DOWN), _joy_axis(JOY_AXIS_LEFT_Y, 1.0)])
	_action("aim_left", 0.25, [_joy_axis(JOY_AXIS_RIGHT_X, -1.0)])
	_action("aim_right", 0.25, [_joy_axis(JOY_AXIS_RIGHT_X, 1.0)])
	_action("aim_up", 0.25, [_joy_axis(JOY_AXIS_RIGHT_Y, -1.0)])
	_action("aim_down", 0.25, [_joy_axis(JOY_AXIS_RIGHT_Y, 1.0)])
	_action("shoot", 0.3, [_mouse(MOUSE_BUTTON_LEFT), _joy_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)])
	_action("dash", 0.3, [_key(KEY_SPACE), _key(KEY_SHIFT), _joy_button(JOY_BUTTON_A),
			_joy_axis(JOY_AXIS_TRIGGER_LEFT, 1.0)])
	_action("weapon_1", 0.5, [_key(KEY_1)])
	_action("weapon_2", 0.5, [_key(KEY_2)])
	_action("weapon_3", 0.5, [_key(KEY_3)])
	_action("weapon_next", 0.5, [_key(KEY_E), _mouse(MOUSE_BUTTON_WHEEL_DOWN),
			_joy_button(JOY_BUTTON_RIGHT_SHOULDER)])
	_action("weapon_prev", 0.5, [_key(KEY_Q), _mouse(MOUSE_BUTTON_WHEEL_UP),
			_joy_button(JOY_BUTTON_LEFT_SHOULDER)])
	_action("pause", 0.5, [_key(KEY_ESCAPE), _joy_button(JOY_BUTTON_START)])
	_append_joy_button("ui_accept", JOY_BUTTON_A)
	_append_joy_button("ui_cancel", JOY_BUTTON_B)


func _setup_misc() -> void:
	ProjectSettings.set_setting("application/run/main_scene", "res://scenes/ui/main_menu.tscn")
	ProjectSettings.set_setting("display/window/size/viewport_width", 1280)
	ProjectSettings.set_setting("display/window/size/viewport_height", 720)
	ProjectSettings.set_setting("rendering/environment/defaults/default_clear_color",
			Color(0.12, 0.12, 0.14, 1))
	ProjectSettings.set_setting("layer_names/2d_physics/layer_1", "world")
	ProjectSettings.set_setting("layer_names/2d_physics/layer_2", "player")
	ProjectSettings.set_setting("layer_names/2d_physics/layer_3", "enemies")
	ProjectSettings.set_setting("layer_names/2d_physics/layer_4", "spawners")
	ProjectSettings.set_setting("layer_names/2d_physics/layer_5", "player_bullets")
	# McpInteractionServer stays first: it already exists, new keys are appended after it.
	ProjectSettings.set_setting("autoload/Events", "*res://scripts/autoload/events.gd")
	ProjectSettings.set_setting("autoload/Settings", "*res://scripts/autoload/settings.gd")
	ProjectSettings.set_setting("autoload/Sfx", "*res://scripts/autoload/sfx.gd")
