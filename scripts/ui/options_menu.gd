class_name OptionsMenu
extends Control
## Options overlay: master volume, fullscreen, vsync. Saves on Back.

signal closed

@onready var _title: Label = $Center/Panel/VBox/Title
@onready var _slider: HSlider = $Center/Panel/VBox/VolumeRow/VolumeSlider
@onready var _value: Label = $Center/Panel/VBox/VolumeRow/VolumeValue
@onready var _fullscreen: CheckButton = $Center/Panel/VBox/FullscreenCheck
@onready var _vsync: CheckButton = $Center/Panel/VBox/VsyncCheck
@onready var _back: Button = $Center/Panel/VBox/BackButton


func _ready() -> void:
	theme = UiTheme.get_theme()
	UiTheme.make_title(_title)
	UiTheme.wire_button_sfx(_back)
	_fullscreen.focus_entered.connect(Sfx.play.bind(&"ui_move"))
	_vsync.focus_entered.connect(Sfx.play.bind(&"ui_move"))
	_slider.focus_entered.connect(Sfx.play.bind(&"ui_move"))
	_slider.value_changed.connect(_on_volume_changed)
	_fullscreen.toggled.connect(_on_fullscreen_toggled)
	_vsync.toggled.connect(_on_vsync_toggled)
	_back.pressed.connect(_on_back)


func open() -> void:
	# set_value_no_signal / set_pressed_no_signal: don't re-apply while syncing UI.
	_slider.set_value_no_signal(Settings.master_volume)
	_update_volume_label(Settings.master_volume)
	_fullscreen.set_pressed_no_signal(Settings.fullscreen)
	_vsync.set_pressed_no_signal(Settings.vsync)
	show()
	_slider.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_cancel"):
		_on_back()
		get_viewport().set_input_as_handled()


func _on_volume_changed(v: float) -> void:
	Settings.set_master_volume(v)
	_update_volume_label(v)


func _update_volume_label(v: float) -> void:
	_value.text = "%d%%" % roundi(v * 100.0)


func _on_fullscreen_toggled(on: bool) -> void:
	Sfx.play(&"ui_click")
	Settings.set_fullscreen(on)


func _on_vsync_toggled(on: bool) -> void:
	Sfx.play(&"ui_click")
	Settings.set_vsync(on)


func _on_back() -> void:
	Settings.save_settings()
	hide()
	closed.emit()
