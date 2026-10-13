# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

A small 2D shooter built with Godot 4.7 (Forward Plus renderer, Jolt for 3D physics — unused for this 2D game). Design goals that should drive implementation choices:

- **Cartoonish visual style.**
- **Fast pace, with a large number of enemies on screen at once**, most of which die easily (low HP, often one hit). Enemy spawning, AI, collision and death effects must be cheap per instance — prefer lightweight nodes, pooling/reuse over repeated instantiate/free, groups or a central manager over per-enemy heavy logic, and avoid per-frame allocations.

The repo is currently a fresh Godot skeleton (only `project.godot` and `icon.svg`); no scenes or scripts exist yet. Update this file as the architecture takes shape.

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

No test framework or linter is set up yet.

## Conventions

- `.editorconfig` sets UTF-8; `.godot/` is the generated import cache and is gitignored — never edit it.
- Prefer editing `.tscn`/`project.godot` through the editor or minimal textual edits; keep `config_version=5` format intact.
- Input actions, autoloads and layer names live in `project.godot`; define collision layers/masks with named layers there rather than magic numbers in scripts.
