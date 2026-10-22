extends Node
## Red rim highlight on the locked enemy (soft) and on the enemy that is striking right now (strong, pulsing).
## One additive fresnel overlay material per highlighted actor (shaders/enemy_rim.gdshader), applied as
## material_overlay to its meshes and removed on clear: no outline pass, no lights, MAX_ACTIVE actors.
## Preload, no class_name:
##   const Highlight := preload("res://scripts/combat/enemy_highlight.gd")
##   Highlight.at(world).lock(actor) / .strike(actor, seconds) / .clear(actor)

const SHADER := preload("res://shaders/enemy_rim.gdshader")
const NODE_NAME := "EnemyHighlight"
const MAX_ACTIVE := 3
const MAX_MESHES := 8
const LOCK_STRENGTH := 0.95
const STRIKE_STRENGTH := 1.0
const LOCK_COLOR := Color(1.0, 0.28, 0.12)
const STRIKE_COLOR := Color(1.0, 0.12, 0.05)

var _entries: Array[Dictionary] = []   # {actor, meshes, mat, kind, until}
var _locked: Node3D = null
var _t := 0.0


static func at(world: Node) -> Node:
	var found := world.get_node_or_null(NODE_NAME)
	if found:
		return found
	var n: Node = (load("res://scripts/combat/enemy_highlight.gd") as GDScript).new()
	n.name = NODE_NAME
	world.add_child(n)
	return n


func _ready() -> void:
	set_process(false)


func active_count() -> int:
	_prune()
	return _entries.size()


func is_highlighted(actor: Node) -> bool:
	return _find(actor) >= 0


## Soft highlight on the lock-on target; replaces the previous lock.
func lock(actor: Node3D) -> void:
	if _locked != null and _locked != actor:
		if is_instance_valid(_locked):
			var i := _find(_locked)
			if i >= 0 and _entries[i]["kind"] == "lock":
				_remove(i)
	_locked = actor
	if actor != null:
		_apply(actor, "lock", 0.0)


func unlock() -> void:
	if _locked != null and is_instance_valid(_locked):
		var i := _find(_locked)
		if i >= 0 and _entries[i]["kind"] == "lock":
			_remove(i)
	_locked = null


## Strong pulsing highlight for `seconds` (the windup); falls back to the lock look if it was locked.
func strike(actor: Node3D, seconds: float) -> void:
	_apply(actor, "strike", Time.get_ticks_msec() * 0.001 + seconds)


func clear(actor: Node3D) -> void:
	var i := _find(actor)
	if i < 0:
		return
	_remove(i)
	if actor == _locked and is_instance_valid(actor):
		_apply(actor, "lock", 0.0)


func _find(actor: Node) -> int:
	for i in _entries.size():
		if _entries[i]["actor"] == actor:
			return i
	return -1


func _apply(actor: Node3D, kind: String, until: float) -> void:
	if actor == null or not is_instance_valid(actor):
		return
	var i := _find(actor)
	if i >= 0:
		var e := _entries[i]
		if kind == "lock" and e["kind"] == "strike":
			return                       # a strike outranks the lock look until it ends
		e["kind"] = kind
		e["until"] = until
		_style(e)
		set_process(true)
		return
	_prune()
	if _entries.size() >= MAX_ACTIVE:
		if kind == "lock":
			return
		_remove(0)                        # oldest makes room for a striker
	var meshes: Array = []
	for m in actor.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.material_overlay == null and meshes.size() < MAX_MESHES:
			meshes.append(mi)
	if meshes.is_empty():
		return
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	var e := {"actor": actor, "meshes": meshes, "mat": mat, "kind": kind, "until": until}
	for mi: MeshInstance3D in meshes:
		mi.material_overlay = mat
	_entries.append(e)
	_style(e)
	set_process(true)


func _style(e: Dictionary) -> void:
	var mat: ShaderMaterial = e["mat"]
	var strike: bool = e["kind"] == "strike"
	mat.set_shader_parameter("color", STRIKE_COLOR if strike else LOCK_COLOR)
	mat.set_shader_parameter("strength", STRIKE_STRENGTH if strike else LOCK_STRENGTH)
	mat.set_shader_parameter("body", 0.2 if strike else 0.1)


func _remove(i: int) -> void:
	var e := _entries[i]
	for mi: Variant in e["meshes"]:
		if is_instance_valid(mi) and (mi as MeshInstance3D).material_overlay == e["mat"]:
			(mi as MeshInstance3D).material_overlay = null
	_entries.remove_at(i)
	if _entries.is_empty():
		set_process(false)


func _prune() -> void:
	var i := _entries.size() - 1
	while i >= 0:
		var a: Variant = _entries[i]["actor"]
		if not is_instance_valid(a) or not (a as Node).is_inside_tree() or (a as Node).get("dead") == true:
			_remove(i)
		i -= 1


func _process(delta: float) -> void:
	_t += delta
	var now := Time.get_ticks_msec() * 0.001
	_prune()
	var i := _entries.size() - 1
	while i >= 0:
		var e := _entries[i]
		if e["kind"] == "strike":
			if now >= float(e["until"]):
				var a: Node3D = e["actor"]
				_remove(i)
				if a == _locked:
					_apply(a, "lock", 0.0)
			else:
				(e["mat"] as ShaderMaterial).set_shader_parameter("strength", STRIKE_STRENGTH * (0.8 + 0.2 * sin(_t * 18.0)))
		i -= 1
	if _entries.is_empty():
		set_process(false)


func _exit_tree() -> void:
	while not _entries.is_empty():
		_remove(_entries.size() - 1)
