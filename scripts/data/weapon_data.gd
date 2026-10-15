class_name WeaponData
extends Resource
## Weapon tuning and visuals. Instances live in res://data/weapons/.

@export var display_name: String = ""
@export var player_texture: Texture2D
@export var icon: Texture2D
@export var sprite_offset: Vector2 = Vector2.ZERO
@export var muzzle_offset: Vector2 = Vector2.ZERO
@export var fire_interval: float = 0.2
@export var damage: int = 1
@export var pellets: int = 1
@export var spread_deg: float = 0.0
@export var bullet_speed: float = 1200.0
@export var bullet_lifetime: float = 0.7
@export var knockback: float = 100.0
@export var shake: float = 0.1
@export var sfx: StringName = &""
