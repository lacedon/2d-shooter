class_name FlowField
extends RefCounted
## Shared grid flow field toward the player. BFS (4-neighbour) distance map,
## recomputed only when the target changes cell. Per-cell move direction is
## computed lazily on first query and cached until the next recompute.
## No allocations in update()/get_direction().

# 0..3 orthogonal, 4..7 diagonal.
const _DX: Array[int] = [1, -1, 0, 0, 1, 1, -1, -1]
const _DY: Array[int] = [0, 0, 1, -1, 1, -1, 1, -1]
const _INV_SQRT2 := 0.70710678
const _DIRS: Array[Vector2] = [
	Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1),
	Vector2(_INV_SQRT2, _INV_SQRT2), Vector2(_INV_SQRT2, -_INV_SQRT2),
	Vector2(-_INV_SQRT2, _INV_SQRT2), Vector2(-_INV_SQRT2, -_INV_SQRT2),
]

var width: int
var height: int
var tile: int
var target_cell: Vector2i = Vector2i(-1, -1)

var _walkable: PackedByteArray      # 1 = walkable; spawner cells set to 0 while alive
var _dist: PackedInt32Array         # -1 = unreachable
var _queue: PackedInt32Array        # preallocated w*h, linear BFS queue
var _dirs: PackedVector2Array       # lazy per-cell direction cache
var _dir_stamp: PackedInt32Array    # _dirs[i] valid iff _dir_stamp[i] == _stamp
var _stamp: int = 0


func _init(w: int, h: int, tile_size: int, walkable: PackedByteArray) -> void:
	width = w
	height = h
	tile = tile_size
	_walkable = walkable.duplicate()
	var n := w * h
	if _walkable.size() != n:
		push_error("FlowField: walkable size %d != %d" % [_walkable.size(), n])
		_walkable.resize(n)
	_dist.resize(n)
	_dist.fill(-1)
	_queue.resize(n)
	_dirs.resize(n)
	_dir_stamp.resize(n)
	_dir_stamp.fill(-1)


func world_to_cell(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / tile), floori(p.y / tile))


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < width and c.y < height


func is_walkable(c: Vector2i) -> bool:
	return in_bounds(c) and _walkable[c.y * width + c.x] == 1


func set_blocked(cell: Vector2i, blocked: bool) -> void:
	if not in_bounds(cell):
		return
	_walkable[cell.y * width + cell.x] = 0 if blocked else 1
	target_cell = Vector2i(-1, -1)  # force recompute on next update()


## Recomputes the distance map if the target moved to a new walkable cell.
## Returns true if a recompute happened.
func update(target_world: Vector2) -> bool:
	var c := world_to_cell(target_world)
	if c == target_cell or not is_walkable(c):
		return false
	_dist.fill(-1)
	var ci := c.y * width + c.x
	_dist[ci] = 0
	_queue[0] = ci
	var head := 0
	var tail := 1
	while head < tail:
		var cur := _queue[head]
		head += 1
		var cx := cur % width
		@warning_ignore("integer_division")
		var cy := cur / width
		var nd := _dist[cur] + 1
		for k in 4:
			var nx := cx + _DX[k]
			var ny := cy + _DY[k]
			if nx < 0 or ny < 0 or nx >= width or ny >= height:
				continue
			var ni := ny * width + nx
			if _walkable[ni] == 0 or _dist[ni] >= 0:
				continue
			_dist[ni] = nd
			_queue[tail] = ni
			tail += 1
	_stamp += 1
	target_cell = c
	return true


## Unit direction toward the target for the cell containing world_pos.
## ZERO if unknown, unreachable, out of bounds, or at the target cell.
func get_direction(world_pos: Vector2) -> Vector2:
	var cx := floori(world_pos.x / tile)
	var cy := floori(world_pos.y / tile)
	if cx < 0 or cy < 0 or cx >= width or cy >= height:
		return Vector2.ZERO
	var i := cy * width + cx
	var d := _dist[i]
	if d < 0:
		return Vector2.ZERO
	if _dir_stamp[i] == _stamp:
		return _dirs[i]
	var best := d
	var best_k := -1
	for k in 8:
		var nx := cx + _DX[k]
		var ny := cy + _DY[k]
		if nx < 0 or ny < 0 or nx >= width or ny >= height:
			continue
		if k >= 4:
			# No corner cutting: both adjacent orthogonals must be walkable.
			if _walkable[cy * width + nx] == 0 or _walkable[ny * width + cx] == 0:
				continue
		var nd := _dist[ny * width + nx]
		if nd >= 0 and nd < best:
			best = nd
			best_k = k
	var dir := Vector2.ZERO if best_k < 0 else _DIRS[best_k]
	_dirs[i] = dir
	_dir_stamp[i] = _stamp
	return dir
