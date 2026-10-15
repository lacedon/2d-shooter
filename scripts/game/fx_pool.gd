class_name FxPool
extends Node2D
## Pooled AnimatedSprite2D puffs/explosions sharing one SpriteFrames.

@export var pool_size: int = 96

const PUFF_FRAMES: Array[Texture2D] = [
	preload("res://assets/sprites/fx/puff_1.png"),
	preload("res://assets/sprites/fx/puff_2.png"),
	preload("res://assets/sprites/fx/puff_3.png"),
	preload("res://assets/sprites/fx/puff_4.png"),
	preload("res://assets/sprites/fx/puff_5.png"),
]
const BOOM_FRAMES: Array[Texture2D] = [
	preload("res://assets/sprites/fx/boom_1.png"),
	preload("res://assets/sprites/fx/boom_2.png"),
	preload("res://assets/sprites/fx/boom_3.png"),
	preload("res://assets/sprites/fx/boom_4.png"),
	preload("res://assets/sprites/fx/boom_5.png"),
]

var _free: Array[AnimatedSprite2D] = []


func _ready() -> void:
	var frames := SpriteFrames.new()
	_add_anim(frames, &"puff", PUFF_FRAMES, 20.0)
	_add_anim(frames, &"boom", BOOM_FRAMES, 14.0)
	if frames.has_animation(&"default"):
		frames.remove_animation(&"default")
	for i in pool_size:
		var n := AnimatedSprite2D.new()
		n.sprite_frames = frames
		n.visible = false
		n.animation_finished.connect(_release.bind(n))
		add_child(n)
		_free.append(n)
	Events.enemy_killed.connect(_on_enemy_killed)
	Events.spawner_destroyed.connect(_on_spawner_destroyed)
	Events.bullet_impact.connect(_on_bullet_impact)


func spawn(anim: StringName, pos: Vector2, scale_f: float, tint: Color) -> void:
	if _free.is_empty():
		return
	var n: AnimatedSprite2D = _free.pop_back()
	n.position = pos
	n.scale = Vector2.ONE * scale_f
	n.modulate = tint
	n.rotation = randf() * TAU
	n.visible = true
	n.play(anim)


func _release(n: AnimatedSprite2D) -> void:
	n.visible = false
	n.stop()
	_free.append(n)


func _add_anim(frames: SpriteFrames, anim: StringName, textures: Array[Texture2D], fps: float) -> void:
	frames.add_animation(anim)
	frames.set_animation_speed(anim, fps)
	frames.set_animation_loop(anim, false)
	for t: Texture2D in textures:
		frames.add_frame(anim, t)


func _on_enemy_killed(pos: Vector2, stats: EnemyStats) -> void:
	spawn(&"puff", pos, stats.puff_scale, stats.puff_tint)


func _on_spawner_destroyed(pos: Vector2) -> void:
	spawn(&"boom", pos, 2.0, Color.WHITE)


func _on_bullet_impact(pos: Vector2) -> void:
	spawn(&"puff", pos, 0.3, Color.WHITE)
