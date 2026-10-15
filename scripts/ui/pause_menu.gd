class_name PauseMenu
extends CanvasLayer
## Pause overlay (process_mode ALWAYS). Toggled by the `pause` action.

@onready var _root: Control = $Root
@onready var _title: Label = $Root/Center/Panel/VBox/Title
@onready var _resume: Button = $Root/Center/Panel/VBox/ResumeButton
@onready var _restart: Button = $Root/Center/Panel/VBox/RestartButton
@onready var _menu: Button = $Root/Center/Panel/VBox/MenuButton


func _ready() -> void:
	_root.theme = UiTheme.get_theme()
	UiTheme.make_title(_title)
	visible = false
	for b: Button in [_resume, _restart, _menu]:
		UiTheme.wire_button_sfx(b)
	_resume.pressed.connect(toggle)
	_restart.pressed.connect(func() -> void: _game().restart())
	_menu.pressed.connect(func() -> void: _game().to_menu())


func _game() -> Game:
	return get_parent() as Game


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause"):
		var game := _game()
		if game != null and game.is_ended():
			return
		toggle()
		get_viewport().set_input_as_handled()
	elif visible and event.is_action_pressed(&"ui_cancel"):
		toggle()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	var tree := get_tree()
	tree.paused = not tree.paused
	visible = tree.paused
	if tree.paused:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_resume.grab_focus()
	else:
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
