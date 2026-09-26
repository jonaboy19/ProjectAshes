class_name Assets
extends RefCounted
## Loads the CC0 KayKit models (by Kay Lousberg) and adapts them for the world:
## scale, part visibility, colliders, animation looping, MultiMesh meshes and
## pre-rendered sprite impostors for distant crowds.

const CHAR_DIR := "res://assets/kaykit/characters/"
const MED_DIR := "res://assets/kaykit/medieval/"
const WEAPON_DIR := "res://assets/kaykit/weapons/"
const BUILDING_SCALE := 8.0
## Standing height of the KayKit adventurer rig in its own units.
const CHARACTER_NATIVE_HEIGHT := 2.2
const LOOPING := ["Idle", "Walking", "Running", "Blocking", "Spellcasting", "Cheer"]

static var _mesh_cache: Dictionary = {}
static var _materials: Dictionary = {}


static func flat_material(color: Color, vertex_colors := false) -> StandardMaterial3D:
	var key := "%s|%s" % [color.to_html(), vertex_colors]
	if _materials.has(key):
		return _materials[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 1.0
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.vertex_color_use_as_albedo = vertex_colors
	m.vertex_color_is_srgb = true
	_materials[key] = m
	return m


static func medieval(asset_name: String, scale := BUILDING_SCALE) -> Node3D:
	var root := Node3D.new()
	var model: Node3D = (load(MED_DIR + asset_name + ".gltf") as PackedScene).instantiate()
	model.scale = Vector3.ONE * scale
	root.add_child(model)
	return root


static func weapon(asset_name: String) -> Node3D:
	return (load(WEAPON_DIR + asset_name + ".gltf") as PackedScene).instantiate()


static func add_footprint_collider(root: Node3D, shrink := 0.8) -> void:
	var box := visual_aabb(root)
	if box.size == Vector3.ZERO:
		return
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(box.size.x * shrink, box.size.y, box.size.z * shrink)
	shape.shape = box_shape
	body.position = box.get_center()
	body.add_child(shape)
	root.add_child(body)


static func mesh_of(asset_name: String) -> Mesh:
	if _mesh_cache.has(asset_name):
		return _mesh_cache[asset_name]
	var inst := (load(MED_DIR + asset_name + ".gltf") as PackedScene).instantiate()
	var mesh: Mesh = null
	var found := inst.find_children("*", "MeshInstance3D", true, false)
	if not found.is_empty():
		mesh = (found[0] as MeshInstance3D).mesh
	elif inst is MeshInstance3D:
		mesh = (inst as MeshInstance3D).mesh
	inst.free()
	_mesh_cache[asset_name] = mesh
	return mesh


## Animated character standing `height` metres tall. Body parts always show;
## weapons/hats only if named in `keep`.
static func character(file_name: String, height: float, keep: Array[String] = []) -> Node3D:
	var model: Node3D = (load(CHAR_DIR + file_name + ".glb") as PackedScene).instantiate()
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var n := String(node.name)
		var is_body := n.contains("Arm") or n.contains("Body") or n.contains("Leg") or n.contains("Head") or n.contains("Cape")
		node.visible = is_body or keep.has(n)
	model.scale = Vector3.ONE * (height / CHARACTER_NATIVE_HEIGHT)
	var anim := animation_player(model)
	if anim:
		for anim_name in anim.get_animation_list():
			var looping := false
			for key: String in LOOPING:
				looping = looping or anim_name.contains(key)
			anim.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR if looping else Animation.LOOP_NONE
	return model


static func animation_player(model: Node) -> AnimationPlayer:
	var found := model.find_children("*", "AnimationPlayer", true, false)
	return found[0] if not found.is_empty() else null


static func visual_aabb(root: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if not mi.visible or mi.mesh == null:
			continue
		var xform := Transform3D.IDENTITY
		var current: Node = mi
		while current != null and current != root:
			if current is Node3D:
				xform = (current as Node3D).transform * xform
			current = current.get_parent()
		var box := xform * mi.mesh.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result
