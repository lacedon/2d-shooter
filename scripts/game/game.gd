class_name Game
extends Node2D
## Game scene root: builds the level, injects dependencies, tracks win/lose.

const SPAWNER_SCENE := preload("res://scenes/game/spawner.tscn")
const SMOKE_TEST := preload("res://scripts/debug/smoke_test.gd")
const MAIN_MENU := "res://scenes/ui/main_menu.tscn"
const END_DELAY := 1.0

var kills: int = 0
var spawners_total: int = 0
var spawners_left: int = 0
var elapsed: float = 0.0
var _ended: bool = false

@onready var player: Player = $World/Player
@onready var enemy_manager: EnemyManager = $World/EnemyManager
@onready var bullet_pool: BulletPool = $World/BulletPool
@onready var _level: LevelBuilder = $World/Level
@onready var _spawners: Node2D = $World/Spawners
@onready var _crosshair: Crosshair = $World/Crosshair
@onready var _camera: CameraShake = $World/Player/Camera
@onready var _pause_menu: PauseMenu = $PauseMenu
@onready var _end_screen: EndScreen = $EndScreen


func _ready() -> void:
	var info: LevelBuilder.LevelInfo = _level.build(LevelMap.MAP)

	player.global_position = info.player_start
	player.bullet_pool = bullet_pool
	_camera.set_bounds(info.bounds)
	_crosshair.player = player

	enemy_manager.setup(player, info.flow_field)

	for cell: Vector2i in info.spawner_cells:
		var s := SPAWNER_SCENE.instantiate() as Spawner
		s.position = LevelBuilder.cell_center(cell)
		_spawners.add_child(s)
		s.setup(enemy_manager, info.flow_field)
	spawners_total = info.spawner_cells.size()
	spawners_left = spawners_total

	Events.enemy_killed.connect(_on_enemy_killed)
	Events.spawner_destroyed.connect(_on_spawner_destroyed)
	Events.player_died.connect(_on_player_died)

	# HUD (a child) is already connected; the Player emitted before it was, so re-broadcast.
	Events.spawners_changed.emit(spawners_left, spawners_total)
	Events.kills_changed.emit(kills)
	player.broadcast_state()

	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN

	if "--smoke" in OS.get_cmdline_user_args():
		add_child(SMOKE_TEST.new())


func _process(delta: float) -> void:
	if not _ended:
		elapsed += delta


func is_ended() -> bool:
	return _ended


func restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func to_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(MAIN_MENU)


func _on_enemy_killed(_pos: Vector2, _stats: EnemyStats) -> void:
	kills += 1
	Events.kills_changed.emit(kills)


func _on_spawner_destroyed(_pos: Vector2) -> void:
	spawners_left -= 1
	Events.spawners_changed.emit(spawners_left, spawners_total)
	if spawners_left <= 0:
		_end(true, END_DELAY)


func _on_player_died() -> void:
	_end(false, END_DELAY)


func _end(won: bool, delay: float) -> void:
	if _ended:
		return
	_ended = true
	await get_tree().create_timer(delay).timeout
	get_tree().paused = true
	_pause_menu.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_end_screen.show_result(won, kills, elapsed)
