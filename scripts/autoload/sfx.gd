extends Node
## Global non-positional SFX. One polyphonic AudioStreamPlayer per sound,
## each with an AudioStreamRandomizer for pitch variation.

const SOUNDS := {
	&"pistol": preload("res://assets/audio/sfx/pistol.ogg"),
	&"machine_gun": preload("res://assets/audio/sfx/machine_gun.ogg"),
	&"shotgun": preload("res://assets/audio/sfx/shotgun.ogg"),
	&"dash": preload("res://assets/audio/sfx/dash.ogg"),
	&"spawner_boom": preload("res://assets/audio/sfx/spawner_boom.ogg"),
	&"zombie_die": preload("res://assets/audio/sfx/zombie_die.ogg"),
	&"robot_hit": preload("res://assets/audio/sfx/robot_hit.ogg"),
	&"robot_die": preload("res://assets/audio/sfx/robot_die.ogg"),
	&"spawner_hit": preload("res://assets/audio/sfx/spawner_hit.ogg"),
	&"player_hurt": preload("res://assets/audio/sfx/player_hurt.ogg"),
	&"ui_click": preload("res://assets/audio/sfx/ui_click.ogg"),
	&"ui_move": preload("res://assets/audio/sfx/ui_move.ogg"),
	&"weapon_switch": preload("res://assets/audio/sfx/weapon_switch.ogg"),
}

var _players: Dictionary[StringName, AudioStreamPlayer] = {}
var _warned: Dictionary[StringName, bool] = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for key: StringName in SOUNDS:
		var randomizer := AudioStreamRandomizer.new()
		randomizer.add_stream(-1, SOUNDS[key] as AudioStream)
		randomizer.random_pitch = 1.12
		var player := AudioStreamPlayer.new()
		player.name = String(key)
		player.stream = randomizer
		player.max_polyphony = 8 if key == &"machine_gun" else 6
		player.bus = &"Master"
		add_child(player)
		_players[key] = player


func play(sound: StringName) -> void:
	var player: AudioStreamPlayer = _players.get(sound)
	if player == null:
		if not _warned.has(sound):
			_warned[sound] = true
			push_warning("Sfx: unknown sound '%s'" % sound)
		return
	player.play()


## Stops every sound. Used before quitting: playbacks still active at shutdown
## are reported as leaked resources, so callers stop, wait briefly, then quit.
func stop_all() -> void:
	for player: AudioStreamPlayer in _players.values():
		player.stop()


## Stops all sounds, lets the audio thread release the playbacks, then quits.
func quit_cleanly(exit_code: int = 0) -> void:
	stop_all()
	await get_tree().create_timer(0.15, true, false, true).timeout
	get_tree().quit(exit_code)
