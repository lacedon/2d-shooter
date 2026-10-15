extends Node
## Headless smoke test, added by Game when run with `-- --smoke`.
## Teleports the player near spawners, holds fire, cycles weapons, then
## destroys every spawner and expects the game to end within 6 s.

var _t: float = 0.0
var _next_switch: float = 1.0
var _idx: int = 0
var _reported: bool = false
var _spawners_killed: bool = false
var _done: bool = false
var _game: Game


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_game = get_parent() as Game
	if _game == null:
		push_error("SMOKE FAIL: parent is not Game")
		get_tree().quit(1)
		return
	_game.player.global_position = Vector2(19 * 64 + 32 + 300, 29 * 64 + 32)
	# Aim left (toward the bottom-middle spawner) with the virtual right stick so
	# bullets actually hit enemies; headless has no meaningful mouse position.
	_game.player.using_gamepad = true
	Input.action_press(&"aim_left")
	Input.action_press(&"shoot")
	print("SMOKE start")


func _process(delta: float) -> void:
	if _done:
		return
	_t += delta
	if _t >= _next_switch:
		_next_switch += 1.0
		_idx = (_idx + 1) % 3
		_game.player.equip(_idx)
	if not _reported and _t >= 2.5:
		_reported = true
		var alive := _game.enemy_manager.alive_count()
		print("SMOKE enemies=%d bullets_free=%d kills=%d hp=%d" % [
				alive, _game.bullet_pool.free_count(), _game.kills, _game.player.hp])
		if alive == 0:
			push_error("SMOKE FAIL: no enemies spawned")
	if not _spawners_killed and _t >= 3.5:
		_spawners_killed = true
		for n: Node in get_tree().get_nodes_in_group(&"spawners"):
			(n as Spawner).take_damage(999, Vector2.ZERO)
	if _t >= 6.0:
		_done = true
		Input.action_release(&"shoot")
		Input.action_release(&"aim_left")
		if _game.is_ended():
			print("SMOKE OK kills=%d" % _game.kills)
			Sfx.quit_cleanly(0)
		else:
			push_error("SMOKE FAIL: game did not end")
			Sfx.quit_cleanly(1)
