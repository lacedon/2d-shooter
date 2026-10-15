class_name EnemyStats
extends Resource
## Enemy type definition. Instances live in res://data/enemies/.

@export var kind: StringName = &""
@export var texture: Texture2D
@export var max_hp: int = 1
@export var speed: float = 150.0
@export var accel: float = 8.0   ## velocity lerp rate per second
@export var contact_damage: int = 1
@export var knockback_scale: float = 1.0
@export var hit_sfx: StringName = &""
@export var death_sfx: StringName = &""
@export var puff_tint: Color = Color.WHITE
@export var puff_scale: float = 1.0
