class_name Assets
extends RefCounted
## Loads the CC0 KayKit models (assets/kaykit, by Kay Lousberg) and adapts them:
## scaling to world size, hiding unused parts, colliders, looping animations,
## and pulling single meshes out for MultiMesh foliage.

const CHAR_DIR := "res://assets/kaykit/characters/"
const MED_DIR := "res://assets/kaykit/medieval/"
## The medieval pack is modelled at tabletop scale; this makes a home ~6.5 m wide.
const BUILDING_SCALE := 8.0
## Standing height of the KayKit adventurer rig in its own units (feet to top of head).
const CHARACTER_NATIVE_HEIGHT := 2.2

static var _mesh_cache: Dictionary = {}


static func medieval(asset_name: String, scale := BUILDING_SCALE) -> Node3D:
	var scene: PackedScene = load(MED_DIR + asset_name + ".gltf")
	var root := Node3D.new()
	var model: Node3D = scene.instantiate()
	model.scale = Vector3.ONE * scale
	root.add_child(model)
	return root


## Adds a box collider sized to the model's footprint (shrunk a little so paths stay walkable).
static func add_footprint_collider(root: Node3D, shrink := 0.8) -> void:
	var box := visual_aabb(root)
	if box.size == Vector3.ZERO:
		return
	Props.add_box_collider(root, Vector3(box.size.x * shrink, box.size.y, box.size.z * shrink), box.get_center())


## First mesh inside a model scene; used to feed MultiMesh instances.
static func mesh_of(asset_name: String) -> Mesh:
	if _mesh_cache.has(asset_name):
		return _mesh_cache[asset_name]
	var scene: PackedScene = load(MED_DIR + asset_name + ".gltf")
	var inst := scene.instantiate()
	var mesh: Mesh = null
	for node in inst.find_children("*", "MeshInstance3D", true, false):
		mesh = (node as MeshInstance3D).mesh
		break
	if mesh == null and inst is MeshInstance3D:
		mesh = (inst as MeshInstance3D).mesh
	inst.free()
	_mesh_cache[asset_name] = mesh
	return mesh


## Animated character. `keep` lists mesh parts to show (body parts are always kept);
## all weapons and hats not listed are hidden. Scaled so it stands `height` metres tall.
static func character(file_name: String, height: float, keep: Array[String] = []) -> Node3D:
	var scene: PackedScene = load(CHAR_DIR + file_name + ".glb")
	var model: Node3D = scene.instantiate()
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var n := String(node.name)
		var is_body := n.contains("Arm") or n.contains("Body") or n.contains("Leg") or n.contains("Head") or n.contains("Cape")
		node.visible = is_body or keep.has(n)
	# Skinned-mesh bounds are unreliable in bind pose, so use the rig's known height.
	model.scale = Vector3.ONE * (height / CHARACTER_NATIVE_HEIGHT)
	var anim := animation_player(model)
	if anim:
		for anim_name in anim.get_animation_list():
			var a := anim.get_animation(anim_name)
			var looping := false
			for key in ["Idle", "Walking", "Running", "Blocking", "Spellcasting"]:
				looping = looping or anim_name.contains(key)
			a.loop_mode = Animation.LOOP_LINEAR if looping else Animation.LOOP_NONE
	return model


static func animation_player(model: Node) -> AnimationPlayer:
	var found := model.find_children("*", "AnimationPlayer", true, false)
	return found[0] if not found.is_empty() else null


## Combined AABB of visible meshes, in the root's local space.
static func visual_aabb(root: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if not mi.visible or mi.mesh == null:
			continue
		var xform := _relative_transform(root, mi)
		var box := xform * mi.mesh.get_aabb()
		if first:
			result = box
			first = false
		else:
			result = result.merge(box)
	return result


static func _relative_transform(root: Node3D, node: Node3D) -> Transform3D:
	var xform := Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != root:
		if current is Node3D:
			xform = (current as Node3D).transform * xform
		current = current.get_parent()
	return xform
