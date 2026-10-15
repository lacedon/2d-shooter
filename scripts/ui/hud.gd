extends CanvasLayer
## In-game HUD. Purely event-driven: text is formatted only when values change.

const INACTIVE_SLOT := Color(1, 1, 1, 0.35)

@onready var _root: Control = $Root
@onready var _hp_label: Label = $Root/TopLeft/VBox/HpRow/HpLabel
@onready var _hp_bar: ProgressBar = $Root/TopLeft/VBox/HpRow/HpBar
@onready var _slots: Array[TextureRect] = [
	$Root/TopLeft/VBox/Weapons/Slot1,
	$Root/TopLeft/VBox/Weapons/Slot2,
	$Root/TopLeft/VBox/Weapons/Slot3,
]
@onready var _weapon_name: Label = $Root/TopLeft/VBox/Weapons/WeaponName
@onready var _spawners_label: Label = $Root/TopRight/VBox/SpawnersLabel
@onready var _kills_label: Label = $Root/TopRight/VBox/KillsLabel


func _ready() -> void:
	_root.theme = UiTheme.get_theme()
	Events.player_health_changed.connect(_on_player_health_changed)
	Events.weapon_changed.connect(_on_weapon_changed)
	Events.spawners_changed.connect(_on_spawners_changed)
	Events.kills_changed.connect(_on_kills_changed)


func _on_player_health_changed(current: int, maximum: int) -> void:
	_hp_label.text = "HP %d/%d" % [current, maximum]
	_hp_bar.max_value = maximum
	_hp_bar.value = current


func _on_weapon_changed(index: int, weapon: WeaponData) -> void:
	for i in _slots.size():
		_slots[i].modulate = Color.WHITE if i == index else INACTIVE_SLOT
	_weapon_name.text = weapon.display_name if weapon != null else ""


func _on_spawners_changed(remaining: int, total: int) -> void:
	_spawners_label.text = "Spawners: %d/%d" % [remaining, total]


func _on_kills_changed(kills: int) -> void:
	_kills_label.text = "Kills: %d" % kills
