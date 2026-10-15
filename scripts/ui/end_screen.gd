class_name EndScreen
extends CanvasLayer
## Win/lose overlay shown by Game._end() while the tree is paused.

const INPUT_GUARD := 0.6  # seconds before buttons accept input (see plan R9)

@onready var _root: Control = $Root
@onready var _title: Label = $Root/Center/Panel/VBox/Title
@onready var _stats: Label = $Root/Center/Panel/VBox/Stats
@onready var _restart: Button = $Root/Center/Panel/VBox/RestartButton
@onready var _menu: Button = $Root/Center/Panel/VBox/MenuButton


func _ready() -> void:
	_root.theme = UiTheme.get_theme()
	UiTheme.make_title(_title)
	visible = false
	UiTheme.wire_button_sfx(_restart)
	UiTheme.wire_button_sfx(_menu)
	_restart.pressed.connect(func() -> void: (get_parent() as Game).restart())
	_menu.pressed.connect(func() -> void: (get_parent() as Game).to_menu())


func show_result(won: bool, kills: int, time: float) -> void:
	_title.text = "YOU WIN!" if won else "YOU DIED"
	var secs := int(time)
	var mins := floori(secs / 60.0)
	_stats.text = "Kills: %d   Time: %d:%02d" % [kills, mins, secs % 60]
	visible = true
	_restart.disabled = true
	_menu.disabled = true
	await get_tree().create_timer(INPUT_GUARD, true).timeout
	_restart.disabled = false
	_menu.disabled = false
	_restart.grab_focus()
