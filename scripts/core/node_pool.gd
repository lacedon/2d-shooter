class_name NodePool
extends RefCounted
## Fixed-size free-list pool. O(1) acquire/release, no growth.
## Pooled nodes are kept in the tree with PROCESS_MODE_DISABLED, which also
## removes CollisionObject2D nodes from the physics space.
## release() must only be called from a deferred context (see EnemyManager/BulletPool).

var _free: Array[Node] = []


func _init(scene: PackedScene, count: int, parent: Node, on_create: Callable = Callable()) -> void:
	_free.resize(0)
	for i in count:
		var n: Node = scene.instantiate()
		if on_create.is_valid():
			on_create.call(n)
		parent.add_child(n)
		_deactivate(n)
		_free.append(n)


func acquire() -> Node:
	if _free.is_empty():
		return null
	return _free.pop_back()


func release(n: Node) -> void:
	_deactivate(n)
	_free.append(n)


func free_count() -> int:
	return _free.size()


func _deactivate(n: Node) -> void:
	n.process_mode = Node.PROCESS_MODE_DISABLED
	var ci := n as CanvasItem
	if ci != null:
		ci.visible = false
