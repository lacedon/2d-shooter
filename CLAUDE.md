# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

A small 2D shooter built with Godot 4.7 (Forward Plus renderer, Jolt for 3D physics — unused for this 2D game). Design goals that should drive implementation choices:

- **Cartoonish visual style.**
- **Fast pace, with a large number of enemies on screen at once**, most of which die easily (low HP, often one hit). Enemy spawning, AI, collision and death effects must be cheap per instance — prefer lightweight nodes, pooling/reuse over repeated instantiate/free, groups or a central manager over per-enemy heavy logic, and avoid per-frame allocations.

### Architecture (prototype, see `docs/plans/2026-10-14-prototype-plan.md`)

Statically typed GDScript only. Main scene `scenes/ui/main_menu.tscn` → `scenes/game/game.tscn`.

- **Folders:** `assets/` (Kenney CC0 art/audio/font, licenses in `assets/licenses/`), `data/` (`WeaponData`/`EnemyStats` `.tres`), `scenes/{ui,game}/`, `scripts/{autoload,core,data,level,game,ui,debug}/`, `tools/setup_project.gd`.
- **Autoloads:** `McpInteractionServer` (MCP tooling, don't touch), `Events` (typed signal bus; HUD/FX/camera/game subscribe), `Settings` (ConfigFile `user://settings.cfg`), `Sfx` (one polyphonic `AudioStreamPlayer` per sound; use `Sfx.quit_cleanly()` instead of `get_tree().quit()` to avoid leaked-playback errors).
- **Level:** an ASCII map (`LevelMap.MAP`) is built at runtime by `LevelBuilder` into two `TileMapLayer`s, with the TileSet created in code (wall tiles carry the `world` collision layer).
- **Enemies:** `EnemyManager` owns a fixed `NodePool` and a swap-remove active list, and calls `enemy.step()` from its own `_physics_process` (enemies have no per-node processing). Navigation uses one shared **grid flow field** (`FlowField`): a BFS from the player's cell, recomputed only when the player changes cell (≥0.15 s apart), with per-cell directions computed lazily. Enemies don't collide with each other. Spawners block their own flow-field cell while alive.
- **Pooling:** bullets (`BulletPool`, Area2D), enemies, and FX (`FxPool`, AnimatedSprite2D) are all pre-instantiated. Pooled nodes sit at `PROCESS_MODE_DISABLED` (which removes them from physics). Release from physics callbacks is always deferred (see `EnemyManager.release`).
- **Damage contract:** `take_damage(amount: int, impulse: Vector2)` on `Enemy`/`Spawner`. The player takes contact damage through one Hurtbox Area2D.
- **Physics layers** (named in project.godot, constants in `PhysicsLayers`): 1 world, 2 player, 3 enemies, 4 spawners, 5 player_bullets.
- `tools/setup_project.gd` (idempotent) owns the input map, layer names, autoloads, main scene and window size. Run it with the editor closed: `$GODOT --headless --path . -s res://tools/setup_project.gd`.

## Commands

The Godot binary is not on `PATH`; the editor is at `/Applications/Godot.app` (see `.vscode/settings.json`). Binary: `/Applications/Godot.app/Contents/MacOS/Godot`.

```sh
GODOT=/Applications/Godot.app/Contents/MacOS/Godot
$GODOT --editor --path .          # open the editor
$GODOT --path .                   # run the main scene
$GODOT --path . res://path/to/scene.tscn   # run a specific scene
$GODOT --headless --path . --import        # (re)import assets, e.g. after adding files outside the editor
$GODOT --headless --path . --check-only --script res://path/to/script.gd   # syntax-check a GDScript file
```

No test framework or linter is set up yet. Smoke test (spawns enemies, shoots, destroys all spawners; expect `SMOKE OK`):

```sh
$GODOT --headless --path . --quit-after 3000 res://scenes/game/game.tscn -- --smoke 2>&1 | grep -E "SMOKE|ERROR|SCRIPT"
```

Gotchas: `--check-only` doesn't register autoloads, so scripts that use `Events`/`Sfx`/`Settings` report a false "Identifier not found" there. Verify them with a headless scene run instead. Run `--import` after adding `class_name` scripts. macOS has no `timeout` command.

## Conventions

- `.editorconfig` sets UTF-8; `.godot/` is the generated import cache and is gitignored — never edit it.
- Prefer editing `.tscn`/`project.godot` through the editor or minimal textual edits; keep `config_version=5` format intact.
- Input actions, autoloads and layer names live in `project.godot`; define collision layers/masks with named layers there rather than magic numbers in scripts.
