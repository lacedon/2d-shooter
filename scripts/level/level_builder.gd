class_name LevelBuilder
extends Node2D
## Builds the TileSet in code and paints the ASCII map into the Floor and
## Walls TileMapLayer children. Returns spawn info and the shared FlowField.

class LevelInfo extends RefCounted:
	var player_start: Vector2 = Vector2.ZERO
	var spawner_cells: Array[Vector2i] = []
	var flow_field: FlowField
	var bounds: Rect2 = Rect2()

const FLOOR_A := preload("res://assets/sprites/tiles/floor_a.png")
const FLOOR_B := preload("res://assets/sprites/tiles/floor_b.png")
const WALL := preload("res://assets/sprites/tiles/wall.png")

const SRC_FLOOR_A := 0
const SRC_FLOOR_B := 1
const SRC_WALL := 2


static func cell_center(c: Vector2i) -> Vector2:
	var t := float(LevelMap.TILE_SIZE)
	return Vector2(c) * t + Vector2(t, t) * 0.5


func build(map_text: String) -> LevelInfo:
	var info := LevelInfo.new()
	var rows: PackedStringArray = []
	for line: String in map_text.split("\n"):
		var row := line.trim_suffix("\r")
		if not row.is_empty():
			rows.append(row)
	if rows.is_empty():
		push_error("LevelBuilder: empty map")
		return info
	var w := rows[0].length()
	var h := rows.size()
	for row: String in rows:
		if row.length() != w:
			push_error("LevelBuilder: map rows have unequal length (%d vs %d)" % [row.length(), w])
			return info

	# Resolved here (not @onready) so build() works regardless of ready order.
	var floor_layer := get_node(^"Floor") as TileMapLayer
	var walls_layer := get_node(^"Walls") as TileMapLayer
	var ts := _make_tile_set()
	floor_layer.tile_set = ts
	walls_layer.tile_set = ts
	floor_layer.clear()
	walls_layer.clear()

	var walkable := PackedByteArray()
	walkable.resize(w * h)
	walkable.fill(0)
	for y in h:
		var row := rows[y]
		for x in w:
			var ch := row[x]
			var cell := Vector2i(x, y)
			match ch:
				"#":
					walls_layer.set_cell(cell, SRC_WALL, Vector2i.ZERO)
				".", "P", "S":
					var src := SRC_FLOOR_B if (x * 7 + y * 13) % 5 == 0 else SRC_FLOOR_A
					floor_layer.set_cell(cell, src, Vector2i.ZERO)
					walkable[y * w + x] = 1
					if ch == "P":
						info.player_start = cell_center(cell)
					elif ch == "S":
						info.spawner_cells.append(cell)
				_:
					pass  # void: blocked, no tile

	var t := LevelMap.TILE_SIZE
	info.flow_field = FlowField.new(w, h, t, walkable)
	info.bounds = Rect2(0, 0, w * t, h * t)
	return info


func _make_tile_set() -> TileSet:
	var t := LevelMap.TILE_SIZE
	var ts := TileSet.new()
	ts.tile_size = Vector2i(t, t)
	# Physics layer must exist before sources are added (see plan R7).
	ts.add_physics_layer()
	ts.set_physics_layer_collision_layer(0, PhysicsLayers.WORLD)
	ts.set_physics_layer_collision_mask(0, 0)
	var textures: Array[Texture2D] = [FLOOR_A, FLOOR_B, WALL]
	for id in textures.size():
		var src := TileSetAtlasSource.new()
		src.texture = textures[id]
		src.texture_region_size = Vector2i(t, t)
		src.create_tile(Vector2i.ZERO)
		ts.add_source(src, id)
		if id == SRC_WALL:
			# Collision polygons only after add_source; points are tile-center relative.
			var half := t * 0.5
			var td := src.get_tile_data(Vector2i.ZERO, 0)
			td.add_collision_polygon(0)
			td.set_collision_polygon_points(0, 0, PackedVector2Array([
				Vector2(-half, -half), Vector2(half, -half),
				Vector2(half, half), Vector2(-half, half),
			]))
	return ts
