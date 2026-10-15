# Top-down shooter prototype: implementation plan

Date: 2026-10-14 · Engine: Godot 4.7.2-stable (verified via `--version`) · Language: **GDScript only, statically typed**

Executor: `godot-game-dev`. Follow this document literally. Where it says "decision", don't revisit it. Where a number is a tuning value, use it as given; it can be adjusted later.

---

## 0. Key decisions (summary)

| Topic | Decision | Rejected alternative and why |
|---|---|---|
| Level authoring | **ASCII map string in GDScript → built at runtime** into two `TileMapLayer`s by `LevelBuilder`. The **TileSet is also built in code** (one single-tile `TileSetAtlasSource` per PNG, with a full-square collision polygon on the wall source). | A hand-authored `.tres` TileSet and a painted `.tscn` tilemap: the binary `tile_map_data` and the sub-resource layout are impossible to hand-write reliably without the editor. Separate `StaticBody2D` walls: hundreds of nodes, and no 4.5+ quadrant collision merging. |
| Enemy navigation | **One shared grid flow field** (BFS from the player's cell over the same ASCII grid), recomputed only when the player changes cell (throttled to ≥0.15 s). Per-cell direction is computed **lazily** on first query. Each enemy then does an O(1) lookup plus `move_and_slide()` for wall sliding. Within 96 px of the player, enemies steer directly at the player. | `NavigationAgent2D` per enemy: one path query per agent, plus avoidance, is too expensive for 150 agents. Plain steer-to-player: enemies get stuck behind walls between rooms. |
| Enemy update | `EnemyManager` owns the pool and the active list. It calls `enemy.step()` from its own `_physics_process`. Enemies have `_physics_process` off. | Per-enemy `_physics_process`: works, but it scatters state and makes pooled enable/disable harder. |
| Enemy↔enemy collision | **None** (enemy mask = world + spawners). Small per-enemy speed jitter hides stacking. Spatial-hash separation is an optional stretch task (T11). | Enemies colliding with each other jams doorways, and the cost of `move_and_slide` grows sharply. |
| Bullets | Pooled `Area2D` (monitoring on, monitorable off), moved by `BulletPool._physics_process`, hit detection through `body_entered` (connected once at creation). | Per-bullet raycast queries: each `intersect_ray` allocates a Dictionary. |
| Pools | Generic `NodePool` (free-list stack, O(1) acquire/release) + swap-remove active arrays. **Release is always deferred** (see §9 R3). | The skill's linear-scan pool: O(n) acquire. |
| Damage contract | Duck-typed `take_damage(amount: int, from_dir: Vector2) -> void` on `Enemy` and `Spawner`. Bullets call it if `body.has_method(&"take_damage")`. | Separate Hitbox/Hurtbox component nodes on every enemy: two extra nodes per enemy, not worth it here. |
| Player ← enemy damage | A single `Hurtbox` Area2D on the player (mask = enemies). When i-frames expire, the player checks `has_overlapping_bodies()`. | A hitbox Area2D on every enemy: 150 extra areas. |
| Enemy type B | **Robot = slow brute** (3 HP, 2 contact damage, half knockback). It doesn't shoot. | A ranged robot: needs an enemy-bullet pool, a second bullet layer and dodge tuning. Listed as a follow-up. |
| Weapons | 3 `WeaponData` `.tres` resources: Pistol, Machine Gun, Shotgun (5 pellets, uses the `_silencer` long-barrel sprite). All fire while the button is held, rate-limited by `fire_interval`. | — |
| Cross-system comms | `Events` autoload (typed signals). HUD, FxPool, Camera and Game subscribe. Gameplay calls `Sfx.play()` directly. | Direct node references across subtrees. |
| Dependencies inside the game scene | `game.gd` injects references in code (`player.bullet_pool = …`, `enemy_manager.setup(...)`, `spawner.setup(...)`). | Exported NodePaths wired in hand-written `.tscn`: fragile. |
| project.godot edits | A **one-off headless tool script** `tools/setup_project.gd` writes input map, layer names, autoloads, main scene and window settings with `ProjectSettings.set_setting()` + `save()`. | Hand-typing `Object(InputEventKey, …)` blobs: very error-prone. |
| UI theme | Built in code (`UiTheme.get_theme()` static, cached), applied to each menu/HUD root `Control`. | A hand-written Theme `.tres` with StyleBoxTexture sub-resources. |
| FX | Pooled `AnimatedSprite2D` puffs/explosions sharing **one `SpriteFrames` built in code**. Hit flash uses `self_modulate` + a countdown (no Tweens per enemy). Camera shake uses trauma. | GPUParticles2D per death: heavier, and a material per instance. |

---

## 1. File and folder layout

```
res://
├── project.godot                      (modified by tools/setup_project.gd)
├── icon.svg
├── assets/
│   ├── licenses/                      (Kenney CC0 license copies, see §6)
│   ├── fonts/kenney_future.ttf
│   ├── sprites/
│   │   ├── characters/  player_gun.png player_machine.png player_silencer.png zombie.png robot.png
│   │   ├── weapons/     icon_pistol.png icon_machine_gun.png icon_shotgun.png
│   │   ├── tiles/       floor_a.png floor_b.png wall.png spawner.png
│   │   ├── fx/          bullet.png muzzle_flash.png puff_1..5.png boom_1..5.png
│   │   └── ui/          crosshair.png button_normal.png button_focus.png button_pressed.png
│   └── audio/sfx/       *.ogg (see §6)
├── data/
│   ├── weapons/   pistol.tres  machine_gun.tres  shotgun.tres
│   └── enemies/   zombie.tres  robot.tres
├── scenes/
│   ├── ui/        main_menu.tscn  options_menu.tscn
│   └── game/      game.tscn  player.tscn  enemy.tscn  spawner.tscn  bullet.tscn
│                  hud.tscn  pause_menu.tscn  end_screen.tscn
├── scripts/
│   ├── mcp_interaction_server.gd      (existing: DO NOT TOUCH)
│   ├── autoload/  events.gd  settings.gd  sfx.gd
│   ├── core/      node_pool.gd  physics_layers.gd
│   ├── data/      weapon_data.gd  enemy_stats.gd
│   ├── level/     level_map.gd  level_builder.gd  flow_field.gd
│   ├── game/      game.gd  player.gd  camera_shake.gd  crosshair.gd
│   │              enemy.gd  enemy_manager.gd  spawner.gd
│   │              bullet.gd  bullet_pool.gd  fx_pool.gd
│   ├── ui/        ui_theme.gd  main_menu.gd  options_menu.gd  hud.gd  pause_menu.gd  end_screen.gd
│   └── debug/     smoke_test.gd
└── tools/
    └── setup_project.gd               (one-off, `extends SceneTree`, run headless)
```

`assets/sprites/hero/` already exists and is empty (untracked). Leave it alone.

---

## 2. project.godot changes (via `tools/setup_project.gd`)

### 2.1 How the tool works

`tools/setup_project.gd` is `extends SceneTree`. All work happens in `_init()`, which ends with `ProjectSettings.save()` and `quit()`. Run it with:

```sh
$GODOT --headless --path . -s res://tools/setup_project.gd
```

Rules (verified on 4.7.2):

- **Every InputEvent must get `device = -1`** (all devices). In 4.7, `InputEventKey.new()` defaults to `device = 16` (keyboard) and joypad events default to `device = 0`. Saving those as-is binds the action to one specific device.
- Key events: set `physical_keycode` (keyboard-layout independent), leave `keycode = 0`.
- Action value format: `ProjectSettings.set_setting("input/<name>", {"deadzone": <float>, "events": [<InputEvent>...]})`.
- For `ui_accept` / `ui_cancel`: read the existing default with `ProjectSettings.get_setting("input/ui_accept")`, **append** the joypad event, and write it back. Overriding replaces the defaults, and in 4.7 `ui_accept` has no joypad binding by default (it has Enter, Kp Enter, Space). The default `ui_up/down/left/right` already include D-pad and left stick, so don't touch them.
- The tool must be idempotent: build each action from scratch on every run.
- Afterwards, run `git diff project.godot`. Check that `config_version=5`, `config/features=PackedStringArray("4.7", "Forward Plus")`, the `McpInteractionServer` autoload, `[physics] 3d/physics_engine` and `[rendering]` lines are all still present.

### 2.2 Input actions (exact)

Constants: `JOY_AXIS_LEFT_X=0, LEFT_Y=1, RIGHT_X=2, RIGHT_Y=3, TRIGGER_LEFT=4, TRIGGER_RIGHT=5`; `JOY_BUTTON_A=0, B=1, START=6, LEFT_SHOULDER=9, RIGHT_SHOULDER=10`; `MOUSE_BUTTON_LEFT=1, WHEEL_UP=4, WHEEL_DOWN=5`.

| Action | Deadzone | Keyboard / mouse | Gamepad |
|---|---|---|---|
| `move_left` | 0.25 | KEY_A, KEY_LEFT | JoypadMotion axis 0, value -1.0 |
| `move_right` | 0.25 | KEY_D, KEY_RIGHT | axis 0, +1.0 |
| `move_up` | 0.25 | KEY_W, KEY_UP | axis 1, -1.0 |
| `move_down` | 0.25 | KEY_S, KEY_DOWN | axis 1, +1.0 |
| `aim_left` | 0.25 | — | axis 2, -1.0 |
| `aim_right` | 0.25 | — | axis 2, +1.0 |
| `aim_up` | 0.25 | — | axis 3, -1.0 |
| `aim_down` | 0.25 | — | axis 3, +1.0 |
| `shoot` | 0.3 | MouseButton LEFT | axis 5 (RT), +1.0 |
| `dash` | 0.3 | KEY_SPACE, KEY_SHIFT | JoypadButton 0 (A), axis 4 (LT) +1.0 |
| `weapon_1` | 0.5 | KEY_1 | — |
| `weapon_2` | 0.5 | KEY_2 | — |
| `weapon_3` | 0.5 | KEY_3 | — |
| `weapon_next` | 0.5 | KEY_E, MouseButton WHEEL_DOWN | JoypadButton 10 (RB) |
| `weapon_prev` | 0.5 | KEY_Q, MouseButton WHEEL_UP | JoypadButton 9 (LB) |
| `pause` | 0.5 | KEY_ESCAPE | JoypadButton 6 (Start) |
| `ui_accept` (append) | keep | (keep defaults) | JoypadButton 0 (A) |
| `ui_cancel` (append) | keep | (keep defaults) | JoypadButton 1 (B) |

No conflicts: RB/LB cycle weapons, A/LT dash, RT shoots. Space is in both `dash` and `ui_accept`. That's fine because gameplay and menus are never active at the same time; see §9 R9 for the end-screen guard.

### 2.3 Other settings (set in the same tool)

| Key | Value |
|---|---|
| `application/run/main_scene` | `"res://scenes/ui/main_menu.tscn"` |
| `display/window/size/viewport_width` | `1280` |
| `display/window/size/viewport_height` | `720` |
| `display/window/stretch/mode` / `aspect` | already `canvas_items` / `expand`, leave as is |
| `rendering/environment/defaults/default_clear_color` | `Color(0.12, 0.12, 0.14, 1)` |
| `layer_names/2d_physics/layer_1` | `"world"` |
| `layer_names/2d_physics/layer_2` | `"player"` |
| `layer_names/2d_physics/layer_3` | `"enemies"` |
| `layer_names/2d_physics/layer_4` | `"spawners"` |
| `layer_names/2d_physics/layer_5` | `"player_bullets"` |
| `autoload/Events` | `"*res://scripts/autoload/events.gd"` |
| `autoload/Settings` | `"*res://scripts/autoload/settings.gd"` |
| `autoload/Sfx` | `"*res://scripts/autoload/sfx.gd"` |

Keep `McpInteractionServer` as the first autoload. The autoload scripts must already exist (and parse) before the tool runs; see the task order.

### 2.4 Collision matrix (bit values used in `.tscn` and `PhysicsLayers`)

| Object | layer (value) | mask (value) |
|---|---|---|
| Wall tiles (TileSet physics layer 0) | world (1) | 0 |
| Player body | player (2) | world + spawners (1+8 = **9**) |
| Player Hurtbox (Area2D, monitorable=false) | none (0) | enemies (**4**) |
| Enemy body | enemies (4) | world + spawners (**9**) |
| Spawner body | spawners (8) | 0 |
| Bullet (Area2D, monitorable=false) | player_bullets (16) | world + enemies + spawners (1+4+8 = **13**) |

`scripts/core/physics_layers.gd`: `class_name PhysicsLayers`, `const WORLD := 1, PLAYER := 2, ENEMIES := 4, SPAWNERS := 8, PLAYER_BULLETS := 16`, with a comment that these must match `layer_names` in project.godot. Only `LevelBuilder` (TileSet in code) uses these constants. Scenes set layer and mask values directly in the `.tscn`.

---

## 3. Scenes (node trees and key properties)

Format notes for hand-written `.tscn` (verified 4.7 output): the header is `[gd_scene format=3]`. Omit `load_steps`, `uid=`, and `unique_id=`; Godot accepts files without them and adds them when the editor re-saves. Use `[ext_resource type="..." path="res://..." id="1_x"]` and `[sub_resource type="CircleShape2D" id="shape_1"]`. Enum properties are written as ints. As an alternative, the MCP godot tools (`mcp__godot__create_scene`, `add_node`, `save_scene`) can author scenes. Either way, verify by loading headless.

### 3.1 `scenes/game/player.tscn`
```
Player (CharacterBody2D)  script=player.gd  collision_layer=2 collision_mask=9  motion_mode=1 (floating)
├── Shape (CollisionShape2D)  shape=CircleShape2D(radius=16)
├── Pivot (Node2D)                       ← rotation = aim angle (body itself never rotates)
│   ├── Sprite (Sprite2D) texture=player_gun.png  offset=Vector2(7.5, 0)
│   └── Muzzle (Marker2D) position=Vector2(34, 10)
│       └── Flash (Sprite2D) texture=muzzle_flash.png rotation=1.5708 offset=Vector2(0, -14) visible=false
├── Hurtbox (Area2D) collision_layer=0 collision_mask=4 monitorable=false
│   └── Shape (CollisionShape2D) shape=CircleShape2D(radius=20)
└── Camera (Camera2D) script=camera_shake.gd position_smoothing_enabled=true position_smoothing_speed=8.0
```
The Kenney characters face +X. The head (rotation center) sits about 17 px from the sprite's left edge, so `Sprite.offset.x = texture_width/2 - 17`.

### 3.2 `scenes/game/enemy.tscn` (one scene for both types; the type comes from `EnemyStats`)
```
Enemy (CharacterBody2D) script=enemy.gd collision_layer=4 collision_mask=9 motion_mode=1 max_slides=2
├── Sprite (Sprite2D)            (texture assigned at activate)
└── Shape (CollisionShape2D) shape=CircleShape2D(radius=15)
```

### 3.3 `scenes/game/bullet.tscn`
```
Bullet (Area2D) script=bullet.gd collision_layer=16 collision_mask=13 monitorable=false
├── Sprite (Sprite2D) texture=bullet.png rotation=1.5708 scale=Vector2(1.5, 1.5)
└── Shape (CollisionShape2D) shape=RectangleShape2D(size=Vector2(22, 8))
```
The Area2D root rotates to the travel direction. Never rotate or scale the CollisionShape2D node itself.

### 3.4 `scenes/game/spawner.tscn`
```
Spawner (StaticBody2D) script=spawner.gd collision_layer=8 collision_mask=0  groups=["spawners"]
│   exports: zombie_stats=ExtResource(data/enemies/zombie.tres) robot_stats=ExtResource(data/enemies/robot.tres)
├── Sprite (Sprite2D) texture=spawner.png scale=Vector2(1.1, 1.1)
└── Shape (CollisionShape2D) shape=RectangleShape2D(size=Vector2(56, 56))
```

### 3.5 `scenes/game/game.tscn`
```
Game (Node2D) script=game.gd
├── World (Node2D)                                  (tree order = draw order)
│   ├── Level (Node2D) script=level_builder.gd
│   │   ├── Floor (TileMapLayer) collision_enabled=false
│   │   └── Walls (TileMapLayer)
│   ├── Spawners (Node2D)                           (spawners instanced here at runtime)
│   ├── EnemyManager (Node2D) script=enemy_manager.gd  enemy_scene=ExtResource(enemy.tscn)
│   ├── Player (instance of player.tscn)
│   ├── BulletPool (Node2D) script=bullet_pool.gd  bullet_scene=ExtResource(bullet.tscn)
│   ├── FxPool (Node2D) script=fx_pool.gd
│   └── Crosshair (Sprite2D) script=crosshair.gd texture=crosshair.png scale=Vector2(0.5,0.5) z_index=100
├── HUD (instance of hud.tscn)
├── PauseMenu (instance of pause_menu.tscn)
└── EndScreen (instance of end_screen.tscn)
```

### 3.6 `scenes/game/hud.tscn`
```
HUD (CanvasLayer) layer=1 script=hud.gd
└── Root (Control) anchors full rect, mouse_filter=2 (ignore)
    ├── TopLeft (MarginContainer) anchor preset top-left, margins 16
    │   └── VBox (VBoxContainer)
    │       ├── HpRow (HBoxContainer)
    │       │   ├── HpLabel (Label) "HP 10/10"
    │       │   └── HpBar (ProgressBar) custom_minimum_size=Vector2(200, 20) show_percentage=false
    │       └── Weapons (HBoxContainer)
    │           ├── Slot1 (TextureRect) texture=icon_pistol.png  expand_mode=1 stretch_mode=5 (keep aspect centered) custom_minimum_size=Vector2(56,40)
    │           ├── Slot2 (TextureRect) texture=icon_machine_gun.png (same props)
    │           ├── Slot3 (TextureRect) texture=icon_shotgun.png (same props)
    │           └── WeaponName (Label)
    └── TopRight (MarginContainer) anchor preset top-right (anchor_left=1, anchor_right=1, grow_horizontal=0), margins 16
        └── VBox (VBoxContainer) alignment end
            ├── SpawnersLabel (Label) "Spawners: 4/4" horizontal_alignment=2
            └── KillsLabel (Label) "Kills: 0" horizontal_alignment=2
```
Every Control in the HUD has `mouse_filter = 2`.

### 3.7 `scenes/game/pause_menu.tscn`
```
PauseMenu (CanvasLayer) layer=2 process_mode=3 (always) visible=false script=pause_menu.gd
└── Root (Control) full rect
    ├── Dim (ColorRect) full rect color=Color(0,0,0,0.55)
    └── Center (CenterContainer) full rect
        └── Panel (PanelContainer)
            └── VBox (VBoxContainer) separation=12
                ├── Title (Label) "PAUSED"
                ├── ResumeButton (Button) "Resume"  custom_minimum_size=Vector2(280, 56)
                ├── RestartButton (Button) "Restart" (same size)
                └── MenuButton (Button) "Main Menu" (same size)
```

### 3.8 `scenes/game/end_screen.tscn`
The structure matches PauseMenu: `layer=3`, `process_mode=3`, `visible=false`, script `end_screen.gd`. VBox children: `Title` (Label), `Stats` (Label), `RestartButton` "Restart", `MenuButton` "Main Menu".

### 3.9 `scenes/ui/main_menu.tscn` (main scene)
```
MainMenu (Control) full rect script=main_menu.gd
├── Background (TextureRect) full rect texture=floor_a.png expand_mode=1 stretch_mode=1 (tile)
├── Dim (ColorRect) full rect color=Color(0,0,0,0.25)
├── Center (CenterContainer) full rect
│   └── VBox (VBoxContainer) separation=16
│       ├── Title (Label) "TOP-DOWN SHOOTER" horizontal_alignment=1
│       ├── StartButton (Button) "Start Game" custom_minimum_size=Vector2(320, 64)
│       ├── OptionsButton (Button) "Options"  (same size)
│       └── ExitButton (Button) "Exit"        (same size)
└── OptionsMenu (instance of options_menu.tscn) visible=false
```

### 3.10 `scenes/ui/options_menu.tscn`
```
OptionsMenu (Control) full rect script=options_menu.gd
├── Dim (ColorRect) full rect color=Color(0,0,0,0.6)
└── Center (CenterContainer) full rect
    └── Panel (PanelContainer)
        └── VBox (VBoxContainer) separation=14
            ├── Title (Label) "Options"
            ├── VolumeRow (HBoxContainer)
            │   ├── VolumeText (Label) "Master Volume"
            │   ├── VolumeSlider (HSlider) min_value=0 max_value=1 step=0.05 custom_minimum_size=Vector2(260, 32)
            │   └── VolumeValue (Label) "80%" custom_minimum_size=Vector2(64,0)
            ├── FullscreenCheck (CheckButton) "Fullscreen"
            ├── VsyncCheck (CheckButton) "VSync"
            └── BackButton (Button) "Back" custom_minimum_size=Vector2(280, 56)
```

---

## 4. Scripts (responsibilities, API, algorithms)

General rules: static typing everywhere. Use `&"..."` StringNames for actions and signals in hot paths. No Array, Dictionary or String allocation inside `_physics_process` / `step()`. Preload scenes and resources at class scope with `const X := preload(...)`. In 4.7, an override of a method with a typed return must return a value.

### 4.1 Autoloads

**`events.gd`** (`extends Node`). Signals only:
```gdscript
signal player_health_changed(current: int, maximum: int)
signal player_died
signal weapon_changed(index: int, weapon: WeaponData)
signal enemy_killed(position: Vector2, stats: EnemyStats)
signal spawner_destroyed(position: Vector2)
signal spawners_changed(remaining: int, total: int)
signal kills_changed(kills: int)
signal bullet_impact(position: Vector2)
signal shake_requested(strength: float)   # strength in trauma units 0..1
```

**`settings.gd`** (`extends Node`). Persists to ConfigFile `user://settings.cfg` (per the save-load skill).
- Vars: `master_volume: float = 0.8`, `fullscreen: bool = false`, `vsync: bool = true`.
- `_ready()`: `load_settings()` then `apply()`.
- `load_settings()`: `cfg.load(PATH)`. If it returns non-OK, keep the defaults. Keys: `[audio] master_volume`, `[video] fullscreen`, `[video] vsync`.
- `save_settings()`: write the same keys and `cfg.save(PATH)`.
- `apply()`: `AudioServer.set_bus_volume_db(0, linear_to_db(maxf(master_volume, 0.0001)))`. Then, **only if `DisplayServer.get_name() != "headless"`**: `DisplayServer.window_set_mode(WINDOW_MODE_FULLSCREEN if fullscreen else WINDOW_MODE_WINDOWED)` and `DisplayServer.window_set_vsync_mode(VSYNC_ENABLED if vsync else VSYNC_DISABLED)`.
- Setters `set_master_volume(v)`, `set_fullscreen(b)`, `set_vsync(b)` assign the value and call `apply()`. They don't save; the options menu saves on Back.

**`sfx.gd`** (`extends Node`, `process_mode = PROCESS_MODE_ALWAYS` set in `_ready`).
- `const SOUNDS := { &"pistol": preload(...), ... }` (see §6 for the names).
- `_ready()`: for each entry, create an `AudioStreamPlayer` with `stream = AudioStreamRandomizer` (`add_stream(-1, s)`, `random_pitch = 1.12`), `max_polyphony = 6` (8 for `&"machine_gun"`), `bus = &"Master"`, and add it as a child. Store it in `_players: Dictionary[StringName, AudioStreamPlayer]`.
- `play(name: StringName) -> void`: look up the player and call `play()`. An unknown name triggers `push_warning` once.

### 4.2 Core

**`node_pool.gd`**: `class_name NodePool extends RefCounted`.
```gdscript
var _free: Array[Node] = []
func _init(scene: PackedScene, count: int, parent: Node, on_create: Callable = Callable()) -> void
    # instantiate count nodes; for each: on_create.call(n) if valid; parent.add_child(n);
    # n.process_mode = Node.PROCESS_MODE_DISABLED; n.visible = false (CanvasItem); _free.append(n)
func acquire() -> Node      # return _free.pop_back() or null if empty (caller handles null; no growth)
func release(n: Node) -> void  # n.process_mode = DISABLED; n.visible = false; _free.append(n)
func free_count() -> int
```
`process_mode = DISABLED` on a CollisionObject2D removes it from the physics space (default `disable_mode = REMOVE`), so a pooled node costs nothing. `release()` must only be called from a deferred call (see the swap-remove pattern below).

**Active-list swap-remove pattern** (used by EnemyManager and BulletPool). Each pooled object has `var active_index: int = -1`.
```gdscript
func _add_active(o) -> void: o.active_index = _active.size(); _active.append(o)
func _remove_active(o) -> void:
    var last = _active.pop_back()
    if last != o: _active[o.active_index] = last; last.active_index = o.active_index
    o.active_index = -1
```

**Deferred release pattern** (mandatory). Bullets and enemies die inside physics signal callbacks (`body_entered`), where changing physics state is blocked.
```gdscript
func release(o) -> void:            # called by bullet/enemy when it dies
    if o.active_index < 0: return  # already released this frame
    _remove_active(o)               # immediate: stop stepping it, ignore further hits
    o.visible = false
    _finish_release.call_deferred(o)
func _finish_release(o) -> void:
    _pool.release(o)                # DISABLED + back into the free list only now
```
The free list receives the node only in the deferred step. This prevents a release-then-reacquire race in the same frame, where a deferred DISABLE would otherwise hit a freshly activated node.

### 4.3 Data resources

**`weapon_data.gd`**: `class_name WeaponData extends Resource`. Exports: `display_name: String`, `player_texture: Texture2D`, `icon: Texture2D`, `sprite_offset: Vector2`, `muzzle_offset: Vector2`, `fire_interval: float`, `damage: int`, `pellets: int`, `spread_deg: float`, `bullet_speed: float`, `bullet_lifetime: float`, `knockback: float`, `shake: float`, `sfx: StringName`.

| file | name | texture | sprite_offset | muzzle_offset | interval | dmg | pellets | spread | speed | life | knockback | shake | sfx |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| pistol.tres | Pistol | player_gun.png | (7.5,0) | (34,10) | 0.18 | 1 | 1 | 3 | 1300 | 0.7 | 120 | 0.12 | &"pistol" |
| machine_gun.tres | Machine Gun | player_machine.png | (7.5,0) | (34,10) | 0.07 | 1 | 1 | 9 | 1500 | 0.6 | 60 | 0.07 | &"machine_gun" |
| shotgun.tres | Shotgun | player_silencer.png | (10,0) | (39,10) | 0.55 | 1 | 5 | 30 | 1150 | 0.35 | 260 | 0.35 | &"shotgun" |

Icons: `icon_pistol.png`, `icon_machine_gun.png`, `icon_shotgun.png`.

**`enemy_stats.gd`**: `class_name EnemyStats extends Resource`. Exports: `kind: StringName`, `texture: Texture2D`, `max_hp: int`, `speed: float`, `accel: float` (velocity lerp rate per second), `contact_damage: int`, `knockback_scale: float`, `hit_sfx: StringName`, `death_sfx: StringName`, `puff_tint: Color`, `puff_scale: float`.

| file | kind | texture | hp | speed | accel | contact | knockback_scale | hit_sfx | death_sfx | puff_tint | puff_scale |
|---|---|---|---|---|---|---|---|---|---|---|---|
| zombie.tres | &"zombie" | zombie.png | 1 | 190 | 10 | 1 | 1.0 | &"" | &"zombie_die" | Color(0.75,1,0.6,1) | 0.9 |
| robot.tres | &"robot" | robot.png | 3 | 115 | 6 | 2 | 0.5 | &"robot_hit" | &"robot_die" | Color(0.8,0.9,1,1) | 1.25 |

`.tres` format (verified 4.7):
```
[gd_resource type="Resource" script_class="WeaponData" format=3]

[ext_resource type="Script" path="res://scripts/data/weapon_data.gd" id="1_s"]
[ext_resource type="Texture2D" path="res://assets/sprites/characters/player_gun.png" id="2_t"]

[resource]
script = ExtResource("1_s")
display_name = "Pistol"
sfx = &"pistol"
...
```

### 4.4 Level

**`level_map.gd`**: `class_name LevelMap`. Holds `const TILE_SIZE := 64` and `const MAP := """ ... """`, containing exactly the 48×33 map below (validated: rectangular, every floor cell reachable from P, every S has a 3×3 floor clearance). Legend: `#` wall, `.` floor, `P` player start (floor), `S` spawner (floor), space = void (unused here; treat as blocked, no tile).
```
################################################
#..............#...............#...............#
#..............#...............#...............#
#..............#..........##...#...............#
#..............#..........##...........S.......#
#....P.........................................#
#..............................#....#..........#
#..............#...............#....#..........#
#..............#...............#....#..........#
#..............#...............#...............#
#..............#...............#...............#
######..##############..################..######
#..............#...............#...............#
#..............#...............#...............#
#..............#...............#...............#
#..............#......##.......................#
#.....................##.......................#
#..............................#.....##........#
#....##........#...............#.....##........#
#....##........#...............#...............#
#..............#...............#...............#
#..............########...######...........S...#
#..............#...............#...............#
#..............#...............#...............#
#........##....#...............#...............#
#........##....#...............#...............#
#..............#.........................##....#
#.........................###............##....#
#......S.......................#...............#
#..............#...S...........#...............#
#..............#...............#...............#
#..............#...............#...............#
################################################
```
That's 7 rooms with 2–3-tile doorways and 4 spawners (NE room, bottom-left room, east room, bottom-middle room). The player starts in the quiet NW room. The world is 3072×2112 px. Parse by splitting on `"\n"`, dropping empty lines, and asserting that all rows have equal length (`push_error` otherwise).

**`level_builder.gd`**: `class_name LevelBuilder extends Node2D`.
- `const` preloads: `floor_a.png`, `floor_b.png`, `wall.png`.
- `func build(map_text: String) -> LevelInfo`. `LevelInfo` is an inner `class LevelInfo extends RefCounted` with `player_start: Vector2`, `spawner_cells: Array[Vector2i]`, `flow_field: FlowField`, `bounds: Rect2`.
- `_make_tile_set() -> TileSet`. **Order matters**:
  1. `ts := TileSet.new(); ts.tile_size = Vector2i(64,64)`
  2. `ts.add_physics_layer(); ts.set_physics_layer_collision_layer(0, PhysicsLayers.WORLD); ts.set_physics_layer_collision_mask(0, 0)`
  3. For each texture (source ids 0=floor_a, 1=floor_b, 2=wall): `src := TileSetAtlasSource.new(); src.texture = tex; src.texture_region_size = Vector2i(64,64); src.create_tile(Vector2i.ZERO); ts.add_source(src, id)`
  4. **After** `add_source`, for the wall only: `var td := src.get_tile_data(Vector2i.ZERO, 0); td.add_collision_polygon(0); td.set_collision_polygon_points(0, 0, PackedVector2Array([Vector2(-32,-32), Vector2(32,-32), Vector2(32,32), Vector2(-32,32)]))`. Polygon points are relative to the tile center. This sequence was verified headless on 4.7.2.
- Assign the same TileSet to `$Floor` and `$Walls`. For each cell: `#` → `$Walls.set_cell(cell, 2, Vector2i.ZERO)`. `.`, `P` and `S` → `$Floor.set_cell(cell, 1 if (x*7 + y*13) % 5 == 0 else 0, Vector2i.ZERO)`. `P` sets `player_start = cell_center`. `S` appends to `spawner_cells`.
- `cell_center(c) = Vector2(c) * 64 + Vector2(32, 32)`.
- Build `walkable: PackedByteArray` (1 for floor/P/S, 0 otherwise), create `FlowField.new(w, h, 64, walkable)`. Then `bounds = Rect2(0, 0, w*64, h*64)`.

**`flow_field.gd`**: `class_name FlowField extends RefCounted`.
```gdscript
var width: int; var height: int; var tile: int
var _walkable: PackedByteArray            # 1 = walkable; spawner cells set to 0 while alive
var _dist: PackedInt32Array               # -1 = unreachable
var _queue: PackedInt32Array              # preallocated size w*h, used as ring/linear queue
var _dirs: PackedVector2Array             # lazy per-cell direction cache
var _dir_stamp: PackedInt32Array          # cell's _dirs valid iff _dir_stamp[i] == _stamp
var _stamp: int = 0
var target_cell: Vector2i = Vector2i(-1, -1)

func world_to_cell(p: Vector2) -> Vector2i: return Vector2i(floori(p.x / tile), floori(p.y / tile))
func set_blocked(cell: Vector2i, blocked: bool) -> void   # then force recompute: target_cell = Vector2i(-1,-1)
func update(target_world: Vector2) -> bool                 # returns true if recomputed
func get_direction(world_pos: Vector2) -> Vector2          # ZERO if unknown/unreachable/out of bounds
```
`update()` algorithm (no allocations):
1. `c := world_to_cell(target_world)`. If `c == target_cell` or c is out of bounds or not walkable, return false.
2. `_dist.fill(-1)`; set `_dist[ci] = 0`; push ci; head/tail ints.
3. Run BFS with 4 neighbours (x±1, y±1) over walkable cells, setting `_dist[n] = _dist[cur] + 1`.
4. `_stamp += 1` (invalidates all cached directions in O(1)); `target_cell = c`; return true.

`get_direction()` algorithm, lazy per cell:
1. `i := idx(cell)`. If out of bounds or `_dist[i] < 0`, return `Vector2.ZERO`. If `_dir_stamp[i] == _stamp`, return `_dirs[i]`.
2. Scan the 8 neighbours. Skip a diagonal unless **both** adjacent orthogonals are walkable (no corner cutting). Pick the neighbour with the smallest `_dist >= 0` that is smaller than `_dist[i]`.
3. `_dirs[i] = Vector2(dx, dy).normalized()` (precompute the 8 normalized vectors as consts), or ZERO at the target cell. Set `_dir_stamp[i] = _stamp` and return.

Cost: the BFS over ≈1300 cells runs at most about 6×/s. Direction work is bounded by the number of distinct occupied cells.

### 4.5 Player (`player.gd`, `class_name Player extends CharacterBody2D`)

Enum FSM (3 states, per the state-machine skill): `enum State { NORMAL, DASH, DEAD }`.

Constants/tuning: `SPEED 300`, `ACCEL 2400` (`velocity.move_toward(target, ACCEL*delta)`), `DASH_SPEED 950`, `DASH_TIME 0.14`, `DASH_COOLDOWN 0.45`, `MAX_HP 10`, `HIT_IFRAMES 0.7`, `DASH_BUFFER 0.12`.

`const WEAPONS: Array[WeaponData] = [preload(pistol), preload(machine_gun), preload(shotgun)]`. If the typed const array literal fails to parse, use a plain `var` initialized in `_ready`.

Public API:
- `var bullet_pool: BulletPool` (injected)
- `var aim_direction: Vector2 = Vector2.RIGHT` (read-only by convention)
- `var using_gamepad: bool = false`
- `var hp: int`
- `func equip(index: int) -> void`
- `func take_damage(amount: int) -> void`
- `func is_dead() -> bool`

Behaviour:
- `_ready()`: `hp = MAX_HP`; `equip(0)`; `Events.player_health_changed.emit(hp, MAX_HP)`.
- `_input(event)`: device detection only.
  - `InputEventJoypadButton`, or `InputEventJoypadMotion` with `absf(axis_value) > 0.4` → `using_gamepad = true`.
  - `InputEventMouseMotion` with `relative.length_squared() > 4`, `InputEventMouseButton`, or `InputEventKey` → `false`.
  - Use event types only; never compare `event.device` (4.7 changed keyboard/mouse IDs).
- `_unhandled_input(event)`: `dash` pressed → `_dash_buffer = DASH_BUFFER`; `weapon_1/2/3` → `equip(0/1/2)`; `weapon_next/prev` → `equip(posmod(_weapon_index ± 1, 3))`. Ignore all of these when DEAD.
- `_physics_process(delta)`:
  1. Timers: `_fire_cd`, `_dash_cd`, `_iframes`, `_dash_buffer`, `_flash_t`, `_muzzle_t` all decrease by `delta`.
  2. `move := Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")`.
  3. Aim:
     - If `using_gamepad`: `stick := Input.get_vector(&"aim_left", &"aim_right", &"aim_up", &"aim_down")`. If `stick != ZERO`, `aim_direction = stick.normalized()`; otherwise, if `move != ZERO`, `aim_direction = move.normalized()`.
     - Otherwise: `v := get_global_mouse_position() - global_position`; if `v.length_squared() > 16`, `aim_direction = v.normalized()`.
     - Then `$Pivot.rotation = aim_direction.angle()`.
  4. State:
     - NORMAL: if `_dash_buffer > 0 and _dash_cd <= 0`, start the dash: `_dash_dir = move.normalized() if move != ZERO else aim_direction`, `_state = DASH`, `_dash_t = DASH_TIME`, `_dash_cd = DASH_COOLDOWN`, `_iframes = maxf(_iframes, DASH_TIME + 0.05)`, `_dash_buffer = 0`, `Sfx.play(&"dash")`, `Events.bullet_impact.emit(global_position)` (reuses the small puff as dash dust). Otherwise `velocity = velocity.move_toward(move * SPEED, ACCEL * delta)`.
     - DASH: `velocity = _dash_dir * DASH_SPEED`; `_dash_t -= delta`; when it reaches ≤0, `_state = NORMAL` and `velocity = _dash_dir * SPEED`.
     - DEAD: return early.
  5. `move_and_slide()`.
  6. Shooting (also allowed while dashing): if `Input.is_action_pressed(&"shoot") and _fire_cd <= 0.0`, call `_fire()` and set `_fire_cd = _weapon.fire_interval`.
  7. Contact damage: if `_iframes <= 0 and $Hurtbox.has_overlapping_bodies()`, find the max `contact_damage` among `$Hurtbox.get_overlapping_bodies()` (this allocates, but only runs at most once per i-frame window) and call `take_damage(max)`.
  8. Visuals: `$Pivot/Sprite.self_modulate = Color(1, 0.35, 0.35) if _flash_t > 0 else Color.WHITE`; flicker alpha 0.5 while `_iframes > 0` (and not dashing); `$Pivot/Muzzle/Flash.visible = _muzzle_t > 0`.
- `_fire()`:
  - `var w := _weapon`, `var base := aim_direction.angle()`.
  - For each pellet `i` in `range(w.pellets)`: `off = deg_to_rad(lerpf(-w.spread_deg/2, w.spread_deg/2, float(i)/(w.pellets-1)) + randf_range(-2, 2))` if `pellets > 1`, else `deg_to_rad(randf_range(-w.spread_deg/2, w.spread_deg/2))`. Then `bullet_pool.fire($Pivot/Muzzle.global_position, Vector2.from_angle(base + off), w)`.
  - Then `_muzzle_t = 0.05`, `Sfx.play(w.sfx)`, `Events.shake_requested.emit(w.shake)`.
- `equip(i)`:
  - If `i == _weapon_index`, return early (except on the first call).
  - Set `_weapon` and `_weapon_index`; `$Pivot/Sprite.texture = w.player_texture`; `.offset = w.sprite_offset`; `$Pivot/Muzzle.position = w.muzzle_offset`; `_fire_cd = minf(_fire_cd, 0.1)`.
  - Emit `Events.weapon_changed.emit(i, w)`; play `Sfx.play(&"weapon_switch")` (skip the sound on the initial equip).
- `take_damage(n)`:
  - If DEAD or `_iframes > 0`, return.
  - `hp = maxi(hp - n, 0)`, `_iframes = HIT_IFRAMES`, `_flash_t = 0.12`, `Sfx.play(&"player_hurt")`, `Events.shake_requested.emit(0.4)`, `Events.player_health_changed.emit(hp, MAX_HP)`.
  - If `hp == 0`: `_state = DEAD`, `velocity = ZERO`, `$Pivot.visible = false`, `$Shape.set_deferred(&"disabled", true)`, `Events.bullet_impact.emit(global_position)` (death puff), `Events.player_died.emit()`.

**`camera_shake.gd`** (`extends Camera2D`):
- Vars: `trauma: float`. Constants: `MAX_OFFSET 14.0`, `DECAY 2.2`.
- `_ready`: connect `Events.shake_requested` → `add_trauma`.
- `add_trauma(a)`: `trauma = minf(trauma + a, 1.0)`.
- `_process(delta)`: `trauma = maxf(trauma - DECAY*delta, 0)`; `var s := trauma * trauma`; `offset = Vector2(randf_range(-1,1), randf_range(-1,1)) * MAX_OFFSET * s`.
- `set_bounds(r: Rect2)`: assign `limit_left/top/right/bottom`.

**`crosshair.gd`** (`extends Sprite2D`):
- `var player: Player` (injected).
- `_process`: if `player.using_gamepad`, `global_position = player.global_position + player.aim_direction * 170`; otherwise `global_position = get_global_mouse_position()`.
- `visible = not player.is_dead()`.

### 4.6 Bullets

**`bullet.gd`** (`class_name Bullet extends Area2D`):
- Vars: `velocity: Vector2`, `life: float`, `damage: int`, `knockback: float`, `active_index: int = -1`, `pool: BulletPool`.
- `_on_body_entered(body: Node2D)`:
  - If `active_index < 0`, return (already spent).
  - If `body.has_method(&"take_damage")`: `body.take_damage(damage, velocity.normalized() * knockback)`. Note: the second argument carries knockback as a vector; see §4.7.
  - Otherwise: `Events.bullet_impact.emit(global_position)` (wall hit).
  - Then `pool.release(self)`.

**`bullet_pool.gd`** (`class_name BulletPool extends Node2D`):
- `@export var bullet_scene: PackedScene`, `@export var pool_size: int = 256`.
- `_ready`: `_pool = NodePool.new(bullet_scene, pool_size, self, func(b): b.pool = self; b.body_entered.connect(b._on_body_entered))`.
- `fire(pos: Vector2, dir: Vector2, w: WeaponData) -> void`:
  - `b := _pool.acquire()`; if null, return (pool exhausted, silently skip).
  - Set `b.global_position = pos`, `b.rotation = dir.angle()`, `b.velocity = dir * w.bullet_speed`, `b.life = w.bullet_lifetime`, `b.damage = w.damage`, `b.knockback = w.knockback`, `b.visible = true`, `b.process_mode = PROCESS_MODE_INHERIT`.
  - `_add_active(b)`.
- `_physics_process(delta)`: iterate `_active` backwards: `b.position += b.velocity * delta`; `b.life -= delta`; if `b.life <= 0`, `release(b)`.
- `release(b)` / `_finish_release(b)`: as in the §4.2 pattern.

### 4.7 Enemies

**Knockback/damage contract:** `take_damage(amount: int, impulse: Vector2) -> void`. `impulse` is a velocity kick in px/s (`Vector2.ZERO` allowed).

**`enemy.gd`** (`class_name Enemy extends CharacterBody2D`):
- Vars: `stats: EnemyStats`, `hp: int`, `active_index := -1`, `home: Spawner` (may be freed; check `is_instance_valid`), `manager: EnemyManager`, `_speed: float`, `_knock: Vector2`, `_flash_t: float`.
- `activate(s: EnemyStats, pos: Vector2, home_spawner: Spawner) -> void`:
  - `stats = s`, `hp = s.max_hp`, `_speed = s.speed * randf_range(0.9, 1.1)`, `_knock = ZERO`, `velocity = ZERO`, `_flash_t = 0`, `$Sprite.texture = s.texture`, `$Sprite.self_modulate = WHITE`, `global_position = pos`, `rotation = randf() * TAU`, `home = home_spawner`, `visible = true`, `process_mode = PROCESS_MODE_INHERIT`.
  - Keep `set_physics_process(false)`; it's set once in `_ready`.
- `step(delta: float, player_pos: Vector2, field: FlowField) -> void`:
  ```gdscript
  var to_p := player_pos - global_position
  var dir: Vector2
  if to_p.length_squared() < 9216.0:          # 96 px
      dir = to_p.normalized()
  else:
      dir = field.get_direction(global_position)
      if dir == Vector2.ZERO: dir = to_p.normalized()
  velocity = velocity.lerp(dir * _speed, minf(stats.accel * delta, 1.0)) + _knock
  _knock = _knock.move_toward(Vector2.ZERO, 1800.0 * delta)
  move_and_slide()
  if velocity.length_squared() > 1.0: rotation = lerp_angle(rotation, velocity.angle(), minf(12.0 * delta, 1.0))
  if _flash_t > 0.0:
      _flash_t -= delta
      if _flash_t <= 0.0: $Sprite.self_modulate = Color.WHITE
  ```
  Cache `$Sprite` in an `@onready var _sprite: Sprite2D`.
- `take_damage(amount, impulse)`:
  - If `active_index < 0`, return. Then `hp -= amount`.
  - If `hp <= 0`, call `die()` and return.
  - Otherwise: `_knock += impulse * stats.knockback_scale`, `_flash_t = 0.08`, `_sprite.self_modulate = Color(4, 4, 4)` (bright hit flash), `Sfx.play(stats.hit_sfx)` if non-empty, `Events.bullet_impact.emit(global_position)`.
- `die()`: `Events.enemy_killed.emit(global_position, stats)`; `Sfx.play(stats.death_sfx)`; `if is_instance_valid(home): home.on_enemy_died()`; `manager.release(self)`.
- `get_contact_damage() -> int`: return `stats.contact_damage`. The Player reads it as `body.get_contact_damage()`. Guard with `body is Enemy`.

**`enemy_manager.gd`** (`class_name EnemyManager extends Node2D`):
- `@export var enemy_scene: PackedScene`, `@export var pool_size: int = 160`, `@export var max_alive: int = 140`.
- Vars: `player: Player`, `field: FlowField`, `_active: Array[Enemy]`, `_recompute_cd: float`.
- `setup(p: Player, f: FlowField) -> void`.
- `alive_count() -> int`: return `_active.size()`.
- `player_position() -> Vector2`.
- `spawn(stats: EnemyStats, pos: Vector2, home: Spawner) -> Enemy`: if `_active.size() >= max_alive`, return null. Then `e := _pool.acquire()`; if null, return null. Otherwise `e.activate(...)`, `_add_active(e)`, return e.
- `release(e)` / `_finish_release(e)`: the §4.2 pattern.
- `_physics_process(delta)`:
  1. If `player == null`, return.
  2. `_recompute_cd -= delta`; if `_recompute_cd <= 0 and not player.is_dead()` and `field.update(player.global_position)` returns true, set `_recompute_cd = 0.15`.
  3. `var pp := player.global_position`; iterate `_active` backwards calling `e.step(delta, pp, field)`.
- `_ready`: the pool's create callback sets `e.manager = self`.

### 4.8 Spawner (`spawner.gd`, `class_name Spawner extends StaticBody2D`)

- Exports: `zombie_stats: EnemyStats`, `robot_stats: EnemyStats`, `max_hp := 12`, `interval := 1.1`, `burst := 2`, `robot_chance := 0.25`, `own_cap := 30`, `activation_radius := 1100.0`.
- Vars: `hp`, `_alive := 0`, `_t: float`, `_manager: EnemyManager`, `_field: FlowField`, `_cell: Vector2i`, `_flash_t`, `_dead := false`.
- `setup(manager, field) -> void`: store both, `_cell = field.world_to_cell(global_position)`, `field.set_blocked(_cell, true)`, `hp = max_hp`, `_t = randf() * interval` (desync spawners).
- `_physics_process(delta)`:
  1. Handle the flash countdown.
  2. `_t -= delta`; if `_t > 0`, return. Set `_t = interval`.
  3. Return if the player is dead or `global_position.distance_squared_to(_manager.player_position()) > activation_radius²`.
  4. `for k in burst:` stop when `_alive >= own_cap`. Otherwise: `var s := robot_stats if randf() < robot_chance else zombie_stats`; `var pos := global_position + Vector2.from_angle(randf() * TAU) * 60.0` (it stays inside the guaranteed 3×3 floor clearance). If `_manager.spawn(s, pos, self) != null`, do `_alive += 1`.
  5. Spawn squash: `$Sprite.scale = Vector2(1.25, 0.9)`, eased back in the flash countdown (or a short Tween; spawners are few, so tweens are fine here).
- `on_enemy_died()`: `_alive -= 1`.
- `take_damage(amount, _impulse)`:
  - If `_dead`, return. Then `hp -= amount`, `_flash_t = 0.08`, `$Sprite.self_modulate = Color(3, 3, 3)`, `Sfx.play(&"spawner_hit")`, `Events.bullet_impact.emit(global_position)`.
  - Damage tint: base modulate `Color(1, lerp(1, 0.45, 1 - hp/max_hp), same, 1)` (reddens as it breaks).
  - If `hp <= 0`, call `_die()`.
- `_die()`: `_dead = true`, `_field.set_blocked(_cell, false)`, `Sfx.play(&"spawner_boom")`, `Events.shake_requested.emit(0.6)`, `Events.spawner_destroyed.emit(global_position)`, `queue_free()`. `queue_free` is already deferred, so it's safe inside a physics callback.

### 4.9 FX (`fx_pool.gd`, `class_name FxPool extends Node2D`)

- `@export var pool_size := 96`.
- `_ready`:
  - Build one shared `SpriteFrames`: `add_animation(&"puff")` with `puff_1..5.png`, speed 20, loop false; `add_animation(&"boom")` with `boom_1..5.png`, speed 14, loop false. Remove the default animation (`remove_animation(&"default")`).
  - Create `pool_size` `AnimatedSprite2D` nodes in code (no scene). Each gets `sprite_frames = shared` and `animation_finished.connect(_release.bind(node))`, and goes into a free-list `Array[AnimatedSprite2D]` (or use `NodePool` with a tiny scene-less variant; inline code is fine here).
- `spawn(anim: StringName, pos: Vector2, scale_f: float, tint: Color) -> void`:
  - Pop from the free list; if empty, return.
  - Set position, `scale = Vector2.ONE * scale_f`, `modulate = tint`, `rotation = randf() * TAU`, `visible = true`, `play(anim)`.
- `_release(n)`: `n.visible = false`, `n.stop()`, push it back. These are not physics objects, so no deferral is needed.
- Subscriptions in `_ready`:
  - `Events.enemy_killed` → `spawn(&"puff", pos, stats.puff_scale, stats.puff_tint)`
  - `Events.spawner_destroyed` → `spawn(&"boom", pos, 2.0, WHITE)`
  - `Events.bullet_impact` → `spawn(&"puff", pos, 0.3, WHITE)`

### 4.10 Game flow (`game.gd`, `class_name Game extends Node2D`)

- Constants: `const SPAWNER_SCENE := preload("res://scenes/game/spawner.tscn")`, `const MAIN_MENU := "res://scenes/ui/main_menu.tscn"`.
- Vars: `kills := 0`, `spawners_total := 0`, `spawners_left := 0`, `elapsed := 0.0`, `_ended := false`.
- `_ready()`:
  1. `var info := $World/Level.build(LevelMap.MAP)`.
  2. `player.global_position = info.player_start`; `player.bullet_pool = $World/BulletPool`; `$World/Player/Camera.set_bounds(info.bounds)`; `$World/Crosshair.player = player`.
  3. `$World/EnemyManager.setup(player, info.flow_field)`.
  4. For each cell in `info.spawner_cells`: instantiate `SPAWNER_SCENE`, set `s.position = cell * 64 + (32, 32)`, `$World/Spawners.add_child(s)`, `s.setup(enemy_manager, info.flow_field)`.
  5. `spawners_total = spawners_left = info.spawner_cells.size()`.
  6. Connect `Events.enemy_killed`, `Events.spawner_destroyed`, `Events.player_died`.
  7. Emit initial values: `Events.spawners_changed.emit(...)`, `Events.kills_changed.emit(0)`. The HUD is already connected because child `_ready` runs first.
  8. `Input.mouse_mode = Input.MOUSE_MODE_HIDDEN`.
  9. If `"--smoke" in OS.get_cmdline_user_args()`: `add_child(preload("res://scripts/debug/smoke_test.gd").new())`.
- `_process(delta)`: if not `_ended`, `elapsed += delta`.
- `_on_enemy_killed(_p, _s)`: `kills += 1`; `Events.kills_changed.emit(kills)`.
- `_on_spawner_destroyed(_p)`: `spawners_left -= 1`; emit `spawners_changed`; if `spawners_left == 0`, call `_end(true, 1.0)`.
- `_on_player_died()`: `_end(false, 1.0)`.
- `_end(won, delay)`: if `_ended`, return. Set `_ended = true`, `await get_tree().create_timer(delay).timeout`, `get_tree().paused = true`, `Input.mouse_mode = VISIBLE`, `$EndScreen.show_result(won, kills, elapsed)`.
- `is_ended() -> bool`.
- `restart()`: `get_tree().paused = false`; `get_tree().reload_current_scene()`.
- `to_menu()`: `get_tree().paused = false`; `get_tree().change_scene_to_file(MAIN_MENU)`.

### 4.11 UI scripts

**`ui_theme.gd`**: `class_name UiTheme`, with `static var _theme: Theme` and `static func get_theme() -> Theme` (built once).
- `default_font = preload(kenney_future.ttf)`, `default_font_size = 22`.
- Button styleboxes are `StyleBoxTexture`, with `texture_margin_left/right = 12`, `top = 12`, `bottom = 16`, and `content_margin` 16 horizontal / 8 vertical:
  - `normal` = button_normal.png
  - `hover` = button_focus.png
  - `focus` = button_focus.png (must be visible for gamepad navigation)
  - `pressed` = button_pressed.png
  - `disabled` = button_normal.png with modulate 0.6
- Button font colors: `font_color` white; `font_focus_color` / `font_hover_color` `Color(0.2, 0.15, 0.05)` (dark on yellow).
- Label: `font_outline_color` black, `outline_size = 6`.
- `PanelContainer` panel: `StyleBoxFlat`, bg `Color(0.1,0.12,0.18,0.92)`, corner radius 12, content margins 24.
- Apply it in each UI root's `_ready`: `theme = UiTheme.get_theme()`. For the CanvasLayer scenes, apply it to `Root`. Title labels override the font size to 56 via `add_theme_font_size_override`.

**`main_menu.gd`**:
- `_ready`: apply the theme; `Input.mouse_mode = VISIBLE`; connect the button `pressed` signals; `$OptionsMenu.closed.connect(func(): $Center/VBox/OptionsButton.grab_focus())`; `$Center/VBox/StartButton.grab_focus.call_deferred()`.
- Start → `get_tree().change_scene_to_file("res://scenes/game/game.tscn")`.
- Options → `$OptionsMenu.open()`.
- Exit → `get_tree().quit()`.
- Each button also connects `focus_entered` → `Sfx.play(&"ui_move")`, and `pressed` → `Sfx.play(&"ui_click")`.

**`options_menu.gd`** (`signal closed`):
- `open()`: set the slider, check states and label from `Settings`; `show()`; `$…/VolumeSlider.grab_focus()`.
- Slider `value_changed` → `Settings.set_master_volume(v)` and update the label to `"%d%%" % roundi(v*100)`.
- `FullscreenCheck.toggled` → `Settings.set_fullscreen`; `VsyncCheck.toggled` → `Settings.set_vsync`.
- Back → `Settings.save_settings()`; `hide()`; `closed.emit()`.
- `_unhandled_input`: if visible and `event.is_action_pressed(&"ui_cancel")`, run Back and `get_viewport().set_input_as_handled()`.

**`hud.gd`**:
- `_ready`: apply the theme to `Root`; connect `Events.player_health_changed`, `weapon_changed`, `spawners_changed` and `kills_changed`.
- Health: set `HpLabel.text = "HP %d/%d"`, `HpBar.max_value/value`.
- Weapon: `Slot{1..3}.modulate = WHITE if i == index else Color(1,1,1,0.35)`; `WeaponName.text = w.display_name`.
- Spawners: `"Spawners: %d/%d"`. Kills: `"Kills: %d"`.
- String formatting happens only on events, never per frame.

**`pause_menu.gd`**:
- `_unhandled_input(event)`: on `&"pause"`, if `owner`/parent `Game.is_ended()`, do nothing; otherwise `toggle()`. Then `set_input_as_handled()`. The game reference is `get_parent() as Game`.
- `toggle()`: `get_tree().paused = not paused`; `visible = paused`. When paused: `Input.mouse_mode = VISIBLE` and `ResumeButton.grab_focus()`. Otherwise: `HIDDEN`.
- `ui_cancel` while visible → resume.
- Buttons: Resume → `toggle()`; Restart → `game.restart()`; Main Menu → `game.to_menu()`.

**`end_screen.gd`**:
- `show_result(won, kills, time)`:
  - `Title.text = "YOU WIN!" if won else "YOU DIED"`; `Stats.text = "Kills: %d   Time: %d:%02d"`; `visible = true`.
  - Set both buttons `disabled = true`, `await get_tree().create_timer(0.6, true).timeout` (process_always = true because the tree is paused), re-enable them, then `RestartButton.grab_focus()`.
- Buttons → `game.restart()` / `game.to_menu()`.

### 4.12 Smoke test (`scripts/debug/smoke_test.gd`, `extends Node`)

- `_ready`: `process_mode = PROCESS_MODE_ALWAYS`. Get `game := get_parent() as Game`. Teleport the player to the bottom-middle spawner area: `player.global_position = Vector2(19*64+32 + 300, 29*64+32)`, so spawners activate. Then `Input.action_press(&"shoot")`.
- `_process(delta)` timeline (`t += delta`):
  - Every 1.0 s: `player.equip((idx+1) % 3)`.
  - At t=2.5: print `"SMOKE enemies=%d bullets_free=%d"` and `push_error` if `enemy_manager.alive_count() == 0`.
  - At t=3.5: call `s.take_damage(999, Vector2.ZERO)` on every node in group `&"spawners"`.
  - At t=6.0: if `game.is_ended()`, print `"SMOKE OK kills=%d"`; otherwise `push_error("SMOKE FAIL: game did not end")`. Then `Input.action_release(&"shoot")` and `get_tree().quit()`.

---

## 5. Signal and data flow (summary)

```
Input ─► Player ──fire()──► BulletPool ─► Bullet.body_entered ─► target.take_damage(dmg, impulse)
                                                             └─► (wall) Events.bullet_impact
Enemy.take_damage ─► die() ─► Events.enemy_killed ─► Game(kills) ─► Events.kills_changed ─► HUD
                           └► Spawner.on_enemy_died()           └► FxPool puff
                           └► EnemyManager.release (deferred)
Spawner.take_damage ─► _die() ─► FlowField.set_blocked(false); Events.spawner_destroyed ─► Game ─► spawners_changed ─► HUD
                                                                                    └► FxPool boom, Camera shake
Player.Hurtbox overlap ─► Player.take_damage ─► Events.player_health_changed ─► HUD
                                             └► Events.player_died ─► Game._end(false) ─► EndScreen
EnemyManager._physics_process ─► FlowField.update(player) ─► enemy.step() ×N
Events.shake_requested ◄── Player._fire / take_damage, Spawner._die     ──► camera_shake.gd
```

---

## 6. Asset copy list

`K="$HOME/Downloads/Kenney Game Assets All-in-1 3.7.0"`, `TS="$K/2D assets/Topdown Shooter/PNG"`, `TT="$K/2D assets/Topdown Tanks Remastered/PNG/Default size"`, `UI="$K/UI assets/UI Pack"`, `SF="$K/Audio/Sci-Fi Sounds/Audio"`, `IM="$K/Audio/Impact Sounds/Audio"`. Destination root: `/Users/lacedon/Documents/side-projects/2d-shooter/assets`. Use `cp` with quoted paths. Tile ids were checked visually: `tile_NN` maps to tilesheet cell `(NN-1) % 27, (NN-1) / 27`.

| Source | Destination (`res://assets/...`) | Use |
|---|---|---|
| `$TS/Man Blue/manBlue_gun.png` | `sprites/characters/player_gun.png` | player, pistol |
| `$TS/Man Blue/manBlue_machine.png` | `sprites/characters/player_machine.png` | player, MG |
| `$TS/Man Blue/manBlue_silencer.png` | `sprites/characters/player_silencer.png` | player, shotgun |
| `$TS/Zombie 1/zoimbie1_hold.png` (sic) | `sprites/characters/zombie.png` | enemy A |
| `$TS/Robot 1/robot1_hold.png` | `sprites/characters/robot.png` | enemy B |
| `$TS/weapon_gun.png` | `sprites/weapons/icon_pistol.png` | HUD |
| `$TS/weapon_machine.png` | `sprites/weapons/icon_machine_gun.png` | HUD |
| `$TS/weapon_silencer.png` | `sprites/weapons/icon_shotgun.png` | HUD |
| `$TS/Tiles/tile_07.png` | `sprites/tiles/floor_a.png` | concrete floor |
| `$TS/Tiles/tile_08.png` | `sprites/tiles/floor_b.png` | floor variant |
| `$TS/Tiles/tile_69.png` | `sprites/tiles/wall.png` | red-brick wall |
| `$TS/Tiles/tile_129.png` | `sprites/tiles/spawner.png` | wooden crate = spawner |
| `$TT/bulletSand1_outline.png` | `sprites/fx/bullet.png` | bullet (points up) |
| `$TT/shotOrange.png` | `sprites/fx/muzzle_flash.png` | muzzle flash (points up) |
| `$TT/explosionSmoke1.png` … `explosionSmoke5.png` | `sprites/fx/puff_1.png` … `puff_5.png` | death puff / impact |
| `$TT/explosion1.png` … `explosion5.png` | `sprites/fx/boom_1.png` … `boom_5.png` | spawner explosion |
| `$K/2D assets/Crosshair Pack/PNG/Outline/crosshair-007.png` | `sprites/ui/crosshair.png` | crosshair |
| `$UI/PNG/Blue/Default/button_rectangle_depth_flat.png` | `sprites/ui/button_normal.png` | button |
| `$UI/PNG/Yellow/Default/button_rectangle_depth_flat.png` | `sprites/ui/button_focus.png` | hover/focus |
| `$UI/PNG/Blue/Default/button_rectangle_flat.png` | `sprites/ui/button_pressed.png` | pressed |
| `$UI/Font/Kenney Future.ttf` | `fonts/kenney_future.ttf` | UI font |
| `$SF/laserSmall_000.ogg` | `audio/sfx/pistol.ogg` | `&"pistol"` |
| `$SF/laserSmall_002.ogg` | `audio/sfx/machine_gun.ogg` | `&"machine_gun"` |
| `$SF/laserLarge_000.ogg` | `audio/sfx/shotgun.ogg` | `&"shotgun"` |
| `$SF/forceField_000.ogg` | `audio/sfx/dash.ogg` | `&"dash"` |
| `$SF/explosionCrunch_000.ogg` | `audio/sfx/spawner_boom.ogg` | `&"spawner_boom"` |
| `$IM/impactPunch_medium_000.ogg` | `audio/sfx/zombie_die.ogg` | `&"zombie_die"` |
| `$IM/impactMetal_light_000.ogg` | `audio/sfx/robot_hit.ogg` | `&"robot_hit"` |
| `$IM/impactMetal_heavy_000.ogg` | `audio/sfx/robot_die.ogg` | `&"robot_die"` |
| `$IM/impactPlank_medium_000.ogg` | `audio/sfx/spawner_hit.ogg` | `&"spawner_hit"` |
| `$IM/impactPunch_heavy_000.ogg` | `audio/sfx/player_hurt.ogg` | `&"player_hurt"` |
| `$UI/Sounds/click-a.ogg` | `audio/sfx/ui_click.ogg` | `&"ui_click"` |
| `$UI/Sounds/tap-a.ogg` | `audio/sfx/ui_move.ogg` | `&"ui_move"` |
| `$UI/Sounds/switch-a.ogg` | `audio/sfx/weapon_switch.ogg` | `&"weapon_switch"` |

Licenses (all CC0), copied to `assets/licenses/`:

| Source | Destination |
|---|---|
| `$K/2D assets/Topdown Shooter/License.txt` | `licenses/kenney_topdown_shooter.txt` |
| `$K/2D assets/Topdown Tanks Remastered/License.txt` | `licenses/kenney_topdown_tanks_remastered.txt` |
| `$K/2D assets/Crosshair Pack/License.txt` | `licenses/kenney_crosshair_pack.txt` |
| `$UI/License.txt` | `licenses/kenney_ui_pack.txt` |
| `$K/Audio/Sci-Fi Sounds/License.txt` | `licenses/kenney_scifi_sounds.txt` |
| `$K/Audio/Impact Sounds/License.txt` | `licenses/kenney_impact_sounds.txt` |

Also add `assets/licenses/CREDITS.md`, one line: "Art, audio and fonts by Kenney (www.kenney.nl), CC0." (This is a project credits file, not a report.)

Import settings: keep the defaults (Lossless 2D, linear filter, fine for this cartoon art). `.ogg` imports with loop=false by default, which is correct for SFX.

---

## 7. Ordered task list with verification

`GODOT=/Applications/Godot.app/Contents/MacOS/Godot`; run everything from the repo root with `--path .`. **After each task**, run the import and the check commands below, then **grep the output for `SCRIPT ERROR|Parse Error|ERROR:`**; the result must be empty, except for the known-harmless "ObjectDB instances leaked" lines on `-s` tool runs.

Common verification commands:
```sh
$GODOT --headless --path . --import 2>&1 | grep -E "ERROR|SCRIPT" ; true        # refreshes class_name cache + imports
for f in <scripts of this task>; do $GODOT --headless --path . --check-only --script "$f" 2>&1 | grep -E "ERROR|error" ; done
```

**T1 Assets.** Create the folders and copy the §6 files with exact renames, plus the licenses and CREDITS.md. Verify: `--import`, then `ls assets/**/*.import | wc -l` should equal the number of copied image, font and audio files (42: 28 PNG + 1 TTF + 13 OGG). No errors.

**T2 Core + autoload + data scripts.** Write `physics_layers.gd`, `node_pool.gd`, `events.gd`, `settings.gd`, `sfx.gd`, `weapon_data.gd`, `enemy_stats.gd`. Verify: `--import`, then `--check-only` each file.

**T3 project.godot.** Write `tools/setup_project.gd` (§2), run it with `-s`, and review `git diff project.godot` against the §2.1 checklist. Verify: `$GODOT --headless --path . --quit-after 10 2>&1` shows no errors (main scene missing is OK at this point; if the warning is noisy, run T3 after T9 instead).

**T4 Data resources.** Write the 3 weapon and 2 enemy `.tres` files (§4.3). Verify with a one-liner tool: `$GODOT --headless --path . -s` on a temporary script in the scratchpad (not in the repo) that `load()`s each `.tres` and prints `display_name`/`kind`. Alternatively, rely on T10.

**T5 Level.** Write `level_map.gd`, `flow_field.gd` and `level_builder.gd`. Verify with `--check-only`. Then run a temporary scratch tool script that instantiates `LevelBuilder` with two TileMapLayer children, calls `build(LevelMap.MAP)`, and prints `player_start`, `spawner_cells.size()` (expect 4), `walls.get_used_cells().size()` and `floor.get_used_cells().size()` (expect 1296). It then calls `flow_field.update(player_start)` and asserts that `get_direction()` at each spawner cell's neighbour is non-zero.

**T6 Player, camera, crosshair, bullets, FX.** Write `player.gd`, `camera_shake.gd`, `crosshair.gd`, `bullet.gd`, `bullet_pool.gd`, `fx_pool.gd`, plus `player.tscn` and `bullet.tscn`. Verify with `--check-only`, then load the scenes headless (scratch script: `load(...).instantiate()` then `free()`).

**T7 Enemies + spawner.** Write `enemy.gd`, `enemy_manager.gd`, `spawner.gd`, plus `enemy.tscn` and `spawner.tscn`. Verify as in T6.

**T8 Game scene + HUD + pause + end.** Write `game.gd`, `hud.gd`, `pause_menu.gd`, `end_screen.gd`, `ui_theme.gd`, and their `.tscn` files. Verify:
```sh
$GODOT --headless --path . --quit-after 300 res://scenes/game/game.tscn 2>&1 | grep -E "ERROR|SCRIPT" ; true
```

**T9 Main menu + options.** Write `main_menu.gd`, `options_menu.gd` and their `.tscn` files. Verify: `$GODOT --headless --path . --quit-after 120 2>&1 | grep -E "ERROR|SCRIPT"` (runs the main scene). Also check that `user://settings.cfg` round-trips: a scratch script sets values, saves, reloads and prints them.

**T10 Smoke test.** Write `smoke_test.gd`. Run:
```sh
$GODOT --headless --path . --quit-after 3000 res://scenes/game/game.tscn -- --smoke 2>&1 | grep -E "SMOKE|ERROR|SCRIPT"
```
Expected: a `SMOKE enemies=N` line with N > 0, then `SMOKE OK kills=K`, and no `ERROR`/`SCRIPT ERROR` lines.

**T11 (stretch, optional) Enemy separation.** In `EnemyManager`, add a uniform spatial hash: 64-px cells, a preallocated `PackedInt32Array` with head/next linked lists rebuilt each tick, and a ≤8-neighbour push. Only do this if stacking looks bad in the visual check.

**T12 Manual visual check (user/editor).** Open the editor, play, and check:
- keyboard and gamepad movement, aim, dash and the 3 weapons
- the crosshair
- spawners activate when the player approaches
- the win/lose screens
- menu focus navigation with arrows, D-pad and A/B
- options persist across restarts

**T13 Docs.** Update the CLAUDE.md "Project" section with the architecture summary (§0 table condensed), the smoke-test command and the setup-tool command. Commit `.uid` files generated next to scripts.

---

## 8. Tuning reference

| Thing | Value |
|---|---|
| Player speed / accel | 300 px/s / 2400 px/s² |
| Dash | 950 px/s for 0.14 s, cooldown 0.45 s, i-frames for its duration |
| Player HP / hit i-frames | 10 / 0.7 s |
| Zombie | 1 HP, 190 px/s (±10%), contact 1 |
| Robot | 3 HP, 115 px/s, contact 2, knockback ×0.5 |
| Spawner | 12 HP, every 1.1 s spawns burst 2, 25% robot, own cap 30, active within 1100 px |
| Global enemy cap / pool | 140 / 160 |
| Bullet pool / FX pool | 256 / 96 |
| Flow field recompute | when the player changes cell, at most every 0.15 s |
| Camera | zoom 1.0, smoothing 8, shake max 14 px, decay 2.2/s |

---

## 9. Risks and gotchas (Godot 4.7)

- **R1 Input device IDs.** In 4.7, keyboard and mouse events use device 16/32, and new joypad events default to 0. The setup tool must set `device = -1` on every event. Gameplay code must detect the device by event type, never by `event.device == 0`.
- **R2 `ui_accept` has no joypad A in the 4.7 defaults** (verified). Append A to `ui_accept` and B to `ui_cancel`, keeping the existing events.
- **R3 Physics state inside signal callbacks.** Toggling `process_mode`, `monitoring` or `disabled` on collision objects inside `body_entered` errors ("Function blocked during in/out signal" / "Can't change this state while flushing queries"). Always defer: `set_deferred` / `call_deferred`, plus the deferred-free-list pattern (§4.2) to avoid the reacquire race.
- **R4 `.tscn`/`.tres` hand-authoring.** 4.7 writes `[gd_scene format=3]` with no `load_steps` and adds `unique_id=` on nodes and `uid=` on resources. Omit all three when writing by hand; Godot accepts that. Never invent `uid://` strings, because a wrong uid breaks the reference even when the path is right. Enum values go in as ints. Sub-resource ids must be unique per file. Load every new scene headless right after writing it.
- **R5 `.uid` sidecar files.** After `--import`, 4.x creates `foo.gd.uid` next to scripts. Commit them, never edit them, and keep them next to their scripts when moving files.
- **R6 Class-name cache.** `--check-only` and the `-s` tools resolve `class_name` through `.godot/global_script_class_cache.cfg`. Run `--headless --import` after adding or renaming class_name scripts, or you'll get false "Identifier not declared" errors.
- **R7 TileSet in code.** Add the physics layer **before** `add_source`, and add collision polygons **after** `add_source`; otherwise `add_collision_polygon(0)` has no layer 0. Collision polygon points are tile-center-relative. 4.5+ merges tile collision per physics quadrant, so enemies slide along walls cleanly. If seams appear between linear-filtered tiles, set `texture_filter = TEXTURE_FILTER_NEAREST` on the two TileMapLayers.
- **R8 Floating motion mode.** Top-down `CharacterBody2D`s must use `motion_mode = MOTION_MODE_FLOATING` (1). Otherwise walls get "floor" semantics and sliding misbehaves.
- **R9 Space in both `dash` and `ui_accept`.** A player mashing Space or A at death would instantly press Restart. The end screen disables its buttons for 0.6 s (§4.11).
- **R10 Pause.** Overlays need `process_mode = ALWAYS`. Timers created while paused need `create_timer(t, true)`. Set `paused = false` before `reload_current_scene()` / `change_scene_to_file()`.
- **R11 Headless.** Guard `DisplayServer.window_set_mode/vsync` behind `DisplayServer.get_name() != "headless"`. `Input.mouse_mode` calls are harmless.
- **R12 Typed override returns (4.7).** An override of a typed-return method must return a value, or it's a parse error.
- **R13 ProjectSettings.save() rewrites project.godot.** Review the diff, and make sure `McpInteractionServer` and the existing `[physics]`/`[rendering]` keys survive. Don't run the tool while the editor is open, because the editor overwrites project.godot on its next save.
- **R14 Bullet tunnelling.** At 1500 px/s and 60 Hz, a bullet moves 25 px per tick. The 22 px-long bullet shape plus the 30 px enemy diameter keeps hits reliable. Don't raise bullet speed above about 1800 without lengthening the shape.
- **R15 Hit-flash colors above 1.** `self_modulate = Color(4,4,4)` brightens the sprite toward white. It needs no shader or material, so batching isn't broken.
- **R16 Draw calls.** All enemies of one type share a texture and have no material, so they batch. Don't give enemies unique `ShaderMaterial`s.

---

## 10. Out of scope / follow-ups

- Ranged robot variant (enemy bullet pool on a new `enemy_bullets` layer).
- Enemy separation (T11).
- Action rebinding UI.
- Music.
- Gamepad rumble on hit (`Input.start_joy_vibration`).
- Multiple levels.

---

## Deviations (implementation notes, 2026-10-14)

Recorded by the implementer. Everything else follows the plan as written. All §6 assets existed, so nothing was substituted.

- **`--check-only` ignores autoloads.** In 4.7, `--check-only --script` doesn't register autoload singletons, so any script that uses `Events`/`Sfx`/`Settings` reports a false "Identifier not found". Those scripts were verified instead by loading them in `-s` tool runs (autoloads are created there), by headless scene runs, and by the godot MCP `validate_scripts` tool (all 29 scripts valid). Related gotcha: a `-s` tool script that statically references project `class_name`s that depend on autoloads fails to compile, so scratch tools use untyped access.
- **macOS has no `timeout`.** Verification used a `perl -e 'alarm …; exec …'` wrapper. No project change.
- **`setup_project.gd` writes untyped arrays.** A typed `Array[InputEvent]` serializes as `Array[InputEvent]([...])`, which differs from the editor's format. The tool now passes plain arrays. It is idempotent: two consecutive runs produce identical files.
- **`LevelBuilder.build()` resolves `Floor`/`Walls` with `get_node()` inside `build()`** instead of `@onready`, so it works from tool scripts and regardless of ready order.
- **HUD missed the Player's initial emits.** `World/Player` is ready before `HUD`. Added `Player.broadcast_state()` (re-emits HP and weapon), called from `Game._ready()` after the spawner/kill emits.
- **Bullet dispatch** calls typed `Enemy.take_damage` / `Spawner.take_damage` first and falls back to `has_method(&"take_damage")` + `call()`. Calling an undeclared method on a `Node2D`-typed variable isn't allowed in typed GDScript.
- **Extra `class_name`s** for typed references: `CameraShake`, `Crosshair`, `PauseMenu`, `EndScreen`, `OptionsMenu`.
- **`smoke_test.gd` was written in T8**, because `game.gd` preloads it as a const. It also (a) aims left through the virtual right stick (`using_gamepad = true`, `Input.action_press(&"aim_left")`), because the headless mouse sits at the origin and bullets otherwise never reach enemies, so the hit/kill path is now exercised; and (b) prints kills/hp on the `SMOKE enemies=` line.
- **Audio leak at exit.** Quitting on the same frame a sound starts leaked an `AudioStreamPlayback` and printed `ERROR: 2 resources still in use at exit`. Added `Sfx.stop_all()` and `Sfx.quit_cleanly(code)` (stop, wait 0.15 s, quit). The smoke test and the main-menu Exit button use it.
- **Flow field** uses typed const arrays (`Array[int]`, `Array[Vector2]`), because `PackedInt32Array(...)` is not a constant expression in 4.7. Added `@warning_ignore("integer_division")` on the BFS row computation.
- **Small additions:** `EnemyManager.is_player_alive()`, `active_count()`/`free_count()` on `BulletPool`, and an initial `field.update()` in `EnemyManager.setup()`. `CameraShake.set_bounds()` defers `reset_smoothing()` so the camera doesn't glide in from the origin. Spawner squash eases back with a per-frame lerp. `Enemy.die()` clears `home`. `UiTheme` adds `hover_pressed` and pressed/disabled font colors, plus `wire_button_sfx()` and `make_title()` helpers. Focus/click SFX are also wired on the pause, end and options buttons. `Game._end()` hides the pause menu if it was open.
- **Not done:** T11 (optional separation; a 140-enemy stress run measured about 1.7 ms of physics per tick headless, so it isn't needed yet), T12 (manual visual check, needs a human), and the commit part of T13 (no commit requested).
