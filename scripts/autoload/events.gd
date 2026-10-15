extends Node
## Global typed signal hub. Gameplay emits, HUD/FX/Camera/Game subscribe.

@warning_ignore_start("unused_signal")
signal player_health_changed(current: int, maximum: int)
signal player_died
signal weapon_changed(index: int, weapon: WeaponData)
signal enemy_killed(position: Vector2, stats: EnemyStats)
signal spawner_destroyed(position: Vector2)
signal spawners_changed(remaining: int, total: int)
signal kills_changed(kills: int)
signal bullet_impact(position: Vector2)
signal shake_requested(strength: float)   # strength in trauma units 0..1
@warning_ignore_restore("unused_signal")
