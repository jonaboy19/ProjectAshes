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

## Realistic humanoids (Quaternius, CC0): base body + outfit + hair on one
## shared skeleton, driven by the Universal Animation Library (86 clips).
const USE_REALISTIC := true
const Q := "res://assets/incoming/quaternius/"
const UBC := Q + "universal-base-characters/"
const OUTFITS := Q + "modular-character-outfits-fantasy/Exports/glTF (Godot-Unreal)/Outfits/"
const HAIR := UBC + "Hairstyles/Rigged to Head Bone/glTF (Godot -Unreal)/"
const UAL_FILES := [Q + "universal-animation-library/Unreal-Godot/UAL1_Standard.glb",
	Q + "universal-animation-library-2/Unreal-Godot/UAL2_Standard.glb"]
const WEAPONS := Q + "fantasy-props-megakit/Exports/glTF/"
const HELMET := Q + "lowpoly-animated-knight/FBX/Helmet1.fbx"
## Old KayKit clip names -> UAL clips, so gameplay code keeps using one vocabulary.
## (Godot's importer strips the "_Loop" suffix from looping clips and marks them looping.)
const UAL_ALIASES := {
	"Walking_A": "Walk", "Running_A": "Jog_Fwd",
	"1H_Melee_Attack_Chop": "Sword_Regular_A", "1H_Melee_Attack_Slice_Diagonal": "Sword_Regular_B",
	"1H_Melee_Attack_Slice_Horizontal": "Sword_Regular_C", "1H_Melee_Attack_Stab": "Sword_Attack",
	"Blocking": "Idle_Shield", "Block_Hit": "Sword_Block", "Dodge_Forward": "Roll",
	"Dodge_Backward": "Roll", "Hit_A": "Hit_Chest", "Hit_B": "Hit_Knockback", "Death_A": "Death01",
	"Death_B": "Death01", "Cheer": "Yes", "Spellcast_Shoot": "Spell_Simple_Shoot",
	"Spellcast_Raise": "Spell_Simple_Enter", "Sit_Floor_Idle": "Sitting_Idle",
	"2H_Melee_Idle": "Sword_Idle", "Interact": "Interact",
}
## KayKit look names used around the game -> humanoid recipes.
const LOOKS := {
	"Knight": {"outfit": "Male_Ranger", "hide": ["Head_Hood"], "hair": "Hair_SimpleParted", "sex": "Male"},
	"Barbarian": {"outfit": "Male_Ranger", "hide": [], "hair": "Hair_Beard", "sex": "Male"},
	"Rogue_Hooded": {"outfit": "Male_Peasant", "hide": [], "hair": "Hair_Buzzed", "sex": "Male", "alt": "Female_Peasant"},
	"Rogue": {"outfit": "Male_Peasant", "hide": [], "hair": "Hair_SimpleParted", "sex": "Male"},
	"Mage": {"outfit": "Female_Peasant", "hide": [], "hair": "Hair_Long", "sex": "Female"},
}

## City buildings and props (Quaternius CC0): key -> [path, target size in metres
## along the longest horizontal side]. Meshes are merged and scaled once.
const VILLAGE := Q + "medieval-village-pack/"
const RTS := Q + "ultimate-fantasy-rts/glTF/"
const BUILDINGS := {
	"adventurer_guild": ["res://assets/generated/adventurer_guild.glb", 0.0],
	"healer_house": ["res://assets/generated/healer_house.glb", 0.0],
	"house_1": [VILLAGE + "Buildings/FBX/House_1.fbx", 9.0],
	"house_2": [VILLAGE + "Buildings/FBX/House_2.fbx", 9.5],
	"house_3": [VILLAGE + "Buildings/FBX/House_3.fbx", 9.0],
	"house_4": [VILLAGE + "Buildings/FBX/House_4.fbx", 10.0],
	"inn": [VILLAGE + "Buildings/FBX/Inn.fbx", 15.0],
	"blacksmith": [VILLAGE + "Buildings/FBX/Blacksmith.fbx", 11.0],
	"stable": [VILLAGE + "Buildings/FBX/Stable.fbx", 14.0],
	"sawmill": [VILLAGE + "Buildings/FBX/Sawmill.fbx", 12.0],
	"mill": [VILLAGE + "Buildings/FBX/Mill.fbx", 11.0],
	"bell_tower": [VILLAGE + "Buildings/FBX/Bell_Tower.fbx", 7.5],
	"market_stand_1": [VILLAGE + "Props/FBX/MarketStand_1.fbx", 3.6],
	"market_stand_2": [VILLAGE + "Props/FBX/MarketStand_2.fbx", 3.6],
	"well": [VILLAGE + "Props/FBX/Well.fbx", 2.8],
	"cart": [VILLAGE + "Props/FBX/Cart.fbx", 3.0],
	"barrel": [VILLAGE + "Props/FBX/Barrel.fbx", 0.9],
	"crate": [VILLAGE + "Props/FBX/Crate.fbx", 1.0],
	"hay": [VILLAGE + "Props/FBX/Hay.fbx", 1.6],
	"bench": [VILLAGE + "Props/FBX/Bench_1.fbx", 2.0],
	"castle": [RTS + "Wonder_SecondAge_Level3.gltf", 52.0],
	"temple": [RTS + "Temple_SecondAge_Level3.gltf", 20.0],
	"watchtower": [RTS + "WatchTower_SecondAge_Level3.gltf", 7.0],
	"wall": [RTS + "Wall_SecondAge.gltf", 0.0],
	"wall_tower": [RTS + "WallTowers_SecondAge.gltf", 0.0],
	"wall_gate": [RTS + "WallTowers_Door_SecondAge.gltf", 0.0],
}

## Nature (Quaternius Stylized Nature MegaKit, CC0): key -> target height in metres.
const NATURE_DIR := Q + "stylized-nature-megakit/glTF/"
const NATURE := {
	"CommonTree_1": 11.0, "CommonTree_2": 12.0, "CommonTree_3": 10.0, "CommonTree_4": 13.0, "CommonTree_5": 11.0,
	"Pine_1": 14.0, "Pine_2": 15.0, "Pine_3": 13.0, "Pine_4": 16.0, "Pine_5": 12.0,
	"TwistedTree_1": 8.0, "TwistedTree_3": 9.0, "DeadTree_2": 7.0,
	"Bush_Common": 1.4, "Bush_Common_Flowers": 1.3, "Fern_1": 0.8, "Plant_1_Big": 1.2,
	"Rock_Medium_1": 1.6, "Rock_Medium_2": 1.3, "Rock_Medium_3": 2.0,
	"Flower_3_Group": 0.4, "Flower_4_Group": 0.4, "Mushroom_Common": 0.25,
}

static var _mesh_cache: Dictionary = {}
static var _building_cache: Dictionary = {}
static var _ual_library: AnimationLibrary
static var _ual_skeleton_path := ""
static var _trimmed_bodies: Dictionary = {}
const HAIR_COLORS := [Color("2b1d14"), Color("4a3020"), Color("6b4a2b"), Color("a67b4b"), Color("1a1a1a"), Color("8a3b1c"), Color("c9a86b")]
## Base-body bones kept when clothing is worn (the rest would clip through outfits).
const EXPOSED_KEYS := ["Head", "neck", "hand", "thumb", "index", "middle", "ring", "pinky"]
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
	if USE_REALISTIC and LOOKS.has(file_name):
		return humanoid(LOOKS[file_name], height, keep)
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


# --- Realistic humanoids ------------------------------------------------------------

## Builds a rigged humanoid: base body (head, hands), outfit and hair meshes bound
## to the base skeleton, props on bone attachments, and an AnimationPlayer with
## the UAL clips (plus KayKit-name aliases).
static func humanoid(look: Dictionary, height: float, keep: Array[String] = []) -> Node3D:
	var sex: String = look["sex"]
	var outfit: String = look["outfit"]
	if look.has("alt") and randf() < 0.5:
		outfit = look["alt"]
		sex = "Female"
	var root := Node3D.new()
	var base: Node3D = (load(UBC + "Base Characters/Godot - UE/Superhero_%s_FullBody.gltf" % sex) as PackedScene).instantiate()
	root.add_child(base)
	var skeleton: Skeleton3D = base.find_children("*", "Skeleton3D", true, false)[0]
	for mi in skeleton.find_children("*", "MeshInstance3D", false, false):
		if String(mi.name).to_lower().begins_with("superhero"):
			(mi as MeshInstance3D).mesh = _trimmed_body(mi as MeshInstance3D, skeleton, sex)
	_bind_meshes(OUTFITS + outfit + ".gltf", skeleton, look.get("hide", []))
	var hair: String = look.get("hair", "")
	if sex == "Female" and hair.contains("Beard"):
		hair = "Hair_Long"
	if hair != "":
		var tint: Color = HAIR_COLORS[randi() % HAIR_COLORS.size()]
		_bind_meshes(HAIR + hair + ".gltf", skeleton, [], tint)
		_bind_meshes(HAIR + ("Eyebrows_Female" if sex == "Female" else "Eyebrows_Regular") + ".gltf", skeleton, [], tint)
	# Props from the old KayKit part names.
	for part in keep:
		if part.contains("Helmet"):
			_attach(skeleton, "Head", HELMET, 0.3, Vector3(0, 0.08, 0.02), Vector3.ZERO)
		elif part.contains("Axe"):
			_attach(skeleton, "hand_r", WEAPONS + "Axe_Bronze.gltf", 0.75, Vector3(0.05, 0.02, 0), Vector3(0, 0, -90))
		elif part.contains("2H_Sword"):
			_attach(skeleton, "hand_r", WEAPONS + "Sword_Bronze.gltf", 1.3, Vector3(0.05, 0.02, 0), Vector3(0, 0, -90))
		elif part.contains("Sword"):
			_attach(skeleton, "hand_r", WEAPONS + "Sword_Bronze.gltf", 0.95, Vector3(0.05, 0.02, 0), Vector3(0, 0, -90))
		elif part.contains("Shield"):
			_attach(skeleton, "lowerarm_l", WEAPONS + "Shield_Wooden.gltf", 0.62, Vector3(0.12, 0, 0.08), Vector3(0, 90, 0))
	# Animation player driving the base skeleton.
	var anim := AnimationPlayer.new()
	anim.name = "AnimationPlayer"
	base.add_child(anim)
	anim.root_node = anim.get_path_to(base)
	anim.add_animation_library("", _ual_for(base.get_path_to(skeleton)))
	# Scale to height from the head bone's rest position (through the rig's own transforms).
	var head := skeleton.find_bone("Head")
	var native := 1.8
	if head >= 0:
		var xform := Transform3D.IDENTITY
		var node: Node = skeleton
		while node != null and node != root:
			if node is Node3D:
				xform = (node as Node3D).transform * xform
			node = node.get_parent()
		native = (xform * skeleton.get_bone_global_rest(head).origin).y * 1.1
	root.scale = Vector3.ONE * (height / maxf(native, 0.01))
	return root


static func _bind_meshes(path: String, skeleton: Skeleton3D, hide: Array, tint := Color.WHITE) -> void:
	if not ResourceLoader.exists(path):
		push_warning("Missing humanoid part: " + path)
		return
	var scene: Node = (load(path) as PackedScene).instantiate()
	for mi in scene.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var skip := false
		for h: String in hide:
			if String(m.name).contains(h):
				skip = true
		if skip:
			continue
		m.get_parent().remove_child(m)
		m.owner = null
		m.transform = Transform3D.IDENTITY
		skeleton.add_child(m)
		m.skeleton = NodePath("..")
		if tint != Color.WHITE:
			for surf in m.mesh.get_surface_count():
				var mat := m.get_active_material(surf)
				if mat is BaseMaterial3D:
					var tinted := (mat as BaseMaterial3D).duplicate() as BaseMaterial3D
					tinted.albedo_color = tint
					m.set_surface_override_material(surf, tinted)
	scene.free()


static func _attach(skeleton: Skeleton3D, bone: String, path: String, length: float, offset: Vector3, rot_deg: Vector3) -> void:
	if skeleton.find_bone(bone) < 0 or not ResourceLoader.exists(path):
		return
	var att := BoneAttachment3D.new()
	att.bone_name = bone
	skeleton.add_child(att)
	var prop: Node3D = (load(path) as PackedScene).instantiate()
	var box := visual_aabb(prop)
	var longest := maxf(box.size.x, maxf(box.size.y, box.size.z))
	# Bone space is in the rig's own units (the UE rig is in centimetres under a
	# scaled Armature), so convert metres into skeleton units.
	var rig_scale := _rig_scale(skeleton)
	prop.scale = Vector3.ONE * (length / maxf(longest, 0.001) / rig_scale)
	prop.position = offset / rig_scale
	prop.rotation_degrees = rot_deg
	att.add_child(prop)


## The base body cut down to head, neck and hands: triangles whose vertices are
## mostly skinned to exposed bones. Cached per sex.
static func _trimmed_body(mi: MeshInstance3D, skeleton: Skeleton3D, sex: String) -> Mesh:
	if _trimmed_bodies.has(sex):
		return _trimmed_bodies[sex]
	var src := mi.mesh
	var keep_bind := {}
	var skin := mi.skin
	for b in skin.get_bind_count():
		var bone_name := String(skin.get_bind_name(b))
		if bone_name == "" and skin.get_bind_bone(b) >= 0:
			bone_name = skeleton.get_bone_name(skin.get_bind_bone(b))
		for key: String in EXPOSED_KEYS:
			if bone_name.begins_with(key) or bone_name.contains("_" + key) or bone_name == key:
				keep_bind[b] = true
	var out := ArrayMesh.new()
	for surf in src.get_surface_count():
		var arrays := src.surface_get_arrays(surf)
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var per := bones.size() / maxi((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), 1)
		var exposed := func(v: int) -> bool:
			var best := 0
			var best_w := -1.0
			for k in per:
				if weights[v * per + k] > best_w:
					best_w = weights[v * per + k]
					best = bones[v * per + k]
			return keep_bind.has(best)
		var kept := PackedInt32Array()
		for t in range(0, indices.size(), 3):
			if exposed.call(indices[t]) and exposed.call(indices[t + 1]) and exposed.call(indices[t + 2]):
				kept.append(indices[t])
				kept.append(indices[t + 1])
				kept.append(indices[t + 2])
		if kept.is_empty():
			continue
		arrays[Mesh.ARRAY_INDEX] = kept
		# Drop optional custom channels (their packing flags don't round-trip).
		for ch in [Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM1, Mesh.ARRAY_CUSTOM2, Mesh.ARRAY_CUSTOM3]:
			arrays[ch] = null
		var fmt: int = src.surface_get_format(surf)
		var flags: int = fmt & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, src.surface_get_blend_shape_arrays(surf), {}, flags)
		out.surface_set_material(out.get_surface_count() - 1, mi.get_active_material(surf))
	var result: Mesh = out if out.get_surface_count() > 0 else src
	_trimmed_bodies[sex] = result
	return result


## Accumulated scale from the skeleton up to the character's base scene.
static func _rig_scale(skeleton: Skeleton3D) -> float:
	var sc := 1.0
	var node: Node = skeleton
	while node != null and node.get_parent() != null and not (node.get_parent() is Node3D and node.get_parent().get_parent() == null):
		if node is Node3D:
			sc *= (node as Node3D).scale.x
		if node.name.begins_with("Superhero") or node.name.begins_with("SuperHero"):
			break
		node = node.get_parent()
	return maxf(sc, 0.0001)


## UAL clips with track paths rewritten for this skeleton path, plus aliases. Cached.
static func _ual_for(skeleton_path: NodePath) -> AnimationLibrary:
	var sk := String(skeleton_path)
	if _ual_library and _ual_skeleton_path == sk:
		return _ual_library
	var lib := AnimationLibrary.new()
	for file: String in UAL_FILES:
		var inst: Node = (load(file) as PackedScene).instantiate()
		var ap: AnimationPlayer = inst.find_children("*", "AnimationPlayer", true, false)[0]
		for anim_name in ap.get_animation_list():
			var a: Animation = ap.get_animation(anim_name).duplicate(true)
			for t in a.get_track_count():
				var tp := String(a.track_get_path(t))
				var colon := tp.find(":")
				if colon > 0:
					a.track_set_path(t, NodePath(sk + tp.substr(colon)))
			if anim_name == "Sword_Idle":
				a.loop_mode = Animation.LOOP_LINEAR
			if not lib.has_animation(anim_name):
				lib.add_animation(anim_name, a)
		inst.free()
	for alias: String in UAL_ALIASES:
		var target: String = UAL_ALIASES[alias]
		if lib.has_animation(target) and not lib.has_animation(alias):
			# A separate copy: the mixer caches tracks per Animation resource.
			lib.add_animation(alias, lib.get_animation(target).duplicate(true))
	_ual_library = lib
	_ual_skeleton_path = sk
	return lib


# --- Buildings -------------------------------------------------------------------------

## One merged mesh per building (all parts, grouped by material), scaled so its
## longest horizontal side is the catalogue size (0 = native size), centred on
## x/z with its base at y = 0. Ready for MultiMesh instancing.
static func building_mesh(key: String) -> ArrayMesh:
	if _building_cache.has(key):
		return _building_cache[key]
	var entry: Array = BUILDINGS[key]
	var mesh := merged_mesh(entry[0])
	if mesh == null:
		return null
	var box := mesh.get_aabb()
	var target: float = entry[1]
	var s := 1.0 if target <= 0.0 else target / maxf(maxf(box.size.x, box.size.z), 0.001)
	var fit := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * s),
		Vector3(-(box.position.x + box.size.x * 0.5) * s, -box.position.y * s, -(box.position.z + box.size.z * 0.5) * s))
	mesh = _transformed(mesh, fit)
	_building_cache[key] = mesh
	return mesh


static func merged_mesh(path: String) -> ArrayMesh:
	if not ResourceLoader.exists(path):
		push_warning("Missing building: " + path)
		return null
	var inst: Node = (load(path) as PackedScene).instantiate()
	var tools := {}          # material -> SurfaceTool
	var root3d := inst as Node3D
	for node in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		var xform := Transform3D.IDENTITY
		var cur: Node = mi
		while cur != null and cur != inst:
			if cur is Node3D:
				xform = (cur as Node3D).transform * xform
			cur = cur.get_parent()
		for surf in mi.mesh.get_surface_count():
			var mat: Material = mi.get_active_material(surf)
			if not tools.has(mat):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				tools[mat] = st
			(tools[mat] as SurfaceTool).append_from(mi.mesh, surf, xform)
	if root3d == null and inst is MeshInstance3D:
		pass
	inst.free()
	var out := ArrayMesh.new()
	for mat in tools:
		var st: SurfaceTool = tools[mat]
		st.commit(out)
		out.surface_set_material(out.get_surface_count() - 1, mat)
	return out if out.get_surface_count() > 0 else null


static func _transformed(mesh: ArrayMesh, xform: Transform3D) -> ArrayMesh:
	var out := ArrayMesh.new()
	for surf in mesh.get_surface_count():
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.append_from(mesh, surf, xform)
		st.commit(out)
		out.surface_set_material(surf, mesh.surface_get_material(surf))
	return out


## Static building node with a box collider (for landmarks placed individually).
static func building_node(key: String, collide := true) -> Node3D:
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = building_mesh(key)
	root.add_child(mi)
	if collide and mi.mesh:
		var box := mi.mesh.get_aabb()
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(box.size.x * 0.85, box.size.y, box.size.z * 0.85)
		shape.shape = bs
		body.position = box.get_center()
		body.add_child(shape)
		root.add_child(body)
	return root


## Nature mesh scaled to its catalogue height, base at y = 0.
static func nature_mesh(key: String) -> ArrayMesh:
	var cache_key := "nature:" + key
	if _building_cache.has(cache_key):
		return _building_cache[cache_key]
	# "scan/<name>" = decimated Poly Haven photo-scan (tools/blender/decimate_scans.py);
	# "nature/<name>" = Blender-generated trees and plants (tools/blender/make_nature.py). Real scale.
	var is_scan := key.begins_with("scan/") or key.begins_with("nature/")
	var mesh := merged_mesh("res://assets/generated/" + key + ".glb" if is_scan else NATURE_DIR + key + ".gltf")
	if mesh == null:
		return null
	var box := mesh.get_aabb()
	var s: float = 1.0 if is_scan else NATURE[key] / maxf(box.size.y, 0.001)
	mesh = _transformed(mesh, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * s),
		Vector3(-(box.position.x + box.size.x * 0.5) * s, -box.position.y * s, -(box.position.z + box.size.z * 0.5) * s)))
	_building_cache[cache_key] = mesh
	return mesh
