class_name AshGhostPool
extends Node3D
## A fixed pool of Ashsight ghosts: instantiated once in `_ready` (eight small scenes),
## recycled forever, never allocated during a replay. When it runs dry `acquire()` returns
## null and the caller simply skips that actor (a replay never has more than a handful:
## AshMemory.MAX_ACTORS caps it).

const GHOST_SCENE := preload("res://scenes/region1/ash_ghost.tscn")

@export var capacity := 8

var _free: Array[AshGhost] = []
var _all: Array[AshGhost] = []


func _ready() -> void:
	for i in capacity:
		var g := GHOST_SCENE.instantiate() as AshGhost
		add_child(g)
		g.deactivate()
		_free.append(g)
		_all.append(g)


func acquire(role: String = "") -> AshGhost:
	if _free.is_empty():
		return null
	var g: AshGhost = _free.pop_back()
	g.activate(role)
	return g


func release(g: AshGhost) -> void:
	if g == null or not g.active:
		return
	g.deactivate()
	_free.append(g)


func release_all() -> void:
	for g in _all:
		release(g)


func free_count() -> int:
	return _free.size()


func active_count() -> int:
	return _all.size() - _free.size()
