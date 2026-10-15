extends Node
## Persistent user settings (ConfigFile at user://settings.cfg).

const PATH := "user://settings.cfg"

var master_volume: float = 0.8
var fullscreen: bool = false
var vsync: bool = true


func _ready() -> void:
	load_settings()
	apply()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	master_volume = clampf(float(cfg.get_value("audio", "master_volume", master_volume)), 0.0, 1.0)
	fullscreen = bool(cfg.get_value("video", "fullscreen", fullscreen))
	vsync = bool(cfg.get_value("video", "vsync", vsync))


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master_volume", master_volume)
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("video", "vsync", vsync)
	var err := cfg.save(PATH)
	if err != OK:
		push_error("Settings: failed to save %s (error %d)" % [PATH, err])


func apply() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(master_volume, 0.0001)))
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(
				DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_vsync_mode(
				DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)


func set_master_volume(v: float) -> void:
	master_volume = clampf(v, 0.0, 1.0)
	apply()


func set_fullscreen(b: bool) -> void:
	fullscreen = b
	apply()


func set_vsync(b: bool) -> void:
	vsync = b
	apply()
