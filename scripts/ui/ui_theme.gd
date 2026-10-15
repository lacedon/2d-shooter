class_name UiTheme
## Shared cartoon UI theme, built once in code and cached.
## Apply with `theme = UiTheme.get_theme()` on each UI root Control.

const FONT := preload("res://assets/fonts/kenney_future.ttf")
const BUTTON_NORMAL := preload("res://assets/sprites/ui/button_normal.png")
const BUTTON_FOCUS := preload("res://assets/sprites/ui/button_focus.png")
const BUTTON_PRESSED := preload("res://assets/sprites/ui/button_pressed.png")

const TITLE_FONT_SIZE := 56
const DARK_TEXT := Color(0.2, 0.15, 0.05)

static var _theme: Theme


static func get_theme() -> Theme:
	if _theme == null:
		_theme = _build()
	return _theme


## Large title font for headline labels.
static func make_title(label: Label) -> void:
	label.add_theme_font_size_override(&"font_size", TITLE_FONT_SIZE)


## Focus-move and click sounds for a menu button.
static func wire_button_sfx(button: BaseButton) -> void:
	button.focus_entered.connect(Sfx.play.bind(&"ui_move"))
	button.pressed.connect(Sfx.play.bind(&"ui_click"))


static func _button_box(tex: Texture2D, modulate: Color = Color.WHITE) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	sb.texture_margin_left = 12.0
	sb.texture_margin_right = 12.0
	sb.texture_margin_top = 12.0
	sb.texture_margin_bottom = 16.0
	sb.content_margin_left = 16.0
	sb.content_margin_right = 16.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	sb.modulate_color = modulate
	return sb


static func _build() -> Theme:
	var t := Theme.new()
	t.default_font = FONT
	t.default_font_size = 22

	t.set_stylebox(&"normal", &"Button", _button_box(BUTTON_NORMAL))
	t.set_stylebox(&"hover", &"Button", _button_box(BUTTON_FOCUS))
	t.set_stylebox(&"focus", &"Button", _button_box(BUTTON_FOCUS))
	t.set_stylebox(&"pressed", &"Button", _button_box(BUTTON_PRESSED))
	t.set_stylebox(&"hover_pressed", &"Button", _button_box(BUTTON_PRESSED))
	t.set_stylebox(&"disabled", &"Button", _button_box(BUTTON_NORMAL, Color(0.6, 0.6, 0.6, 1.0)))
	t.set_color(&"font_color", &"Button", Color.WHITE)
	t.set_color(&"font_pressed_color", &"Button", Color.WHITE)
	t.set_color(&"font_focus_color", &"Button", DARK_TEXT)
	t.set_color(&"font_hover_color", &"Button", DARK_TEXT)
	t.set_color(&"font_hover_pressed_color", &"Button", DARK_TEXT)
	t.set_color(&"font_disabled_color", &"Button", Color(1, 1, 1, 0.5))

	t.set_color(&"font_outline_color", &"Label", Color.BLACK)
	t.set_constant(&"outline_size", &"Label", 6)

	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.1, 0.12, 0.18, 0.92)
	panel.set_corner_radius_all(12)
	panel.content_margin_left = 24.0
	panel.content_margin_right = 24.0
	panel.content_margin_top = 24.0
	panel.content_margin_bottom = 24.0
	t.set_stylebox(&"panel", &"PanelContainer", panel)
	return t
