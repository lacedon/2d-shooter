extends Control
## Main menu (main scene): Start / Options / Exit.

const GAME_SCENE := "res://scenes/game/game.tscn"

@onready var _title: Label = $Center/VBox/Title
@onready var _start: Button = $Center/VBox/StartButton
@onready var _options: Button = $Center/VBox/OptionsButton
@onready var _exit: Button = $Center/VBox/ExitButton
@onready var _options_menu: OptionsMenu = $OptionsMenu


func _ready() -> void:
	theme = UiTheme.get_theme()
	UiTheme.make_title(_title)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for b: Button in [_start, _options, _exit]:
		UiTheme.wire_button_sfx(b)
	_start.pressed.connect(_on_start_pressed)
	_options.pressed.connect(_on_options_pressed)
	_exit.pressed.connect(_on_exit_pressed)
	_options_menu.closed.connect(_on_options_closed)
	_start.grab_focus.call_deferred()


## The overlay doesn't hide these buttons, so keyboard/gamepad focus would
## otherwise wander from the options panel onto them (e.g. Exit).
func _set_buttons_focusable(on: bool) -> void:
	for b: Button in [_start, _options, _exit]:
		b.focus_mode = Control.FOCUS_ALL if on else Control.FOCUS_NONE


func _on_options_pressed() -> void:
	_set_buttons_focusable(false)
	_options_menu.open()


func _on_options_closed() -> void:
	_set_buttons_focusable(true)
	_options.grab_focus()


func _on_start_pressed() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)


func _on_exit_pressed() -> void:
	_exit.disabled = true
	Sfx.quit_cleanly()
