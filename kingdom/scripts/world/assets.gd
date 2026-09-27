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
	Q + "universal-animation-library-2/Unreal-Godot/UAL2_Standard.glb",
	# 119 extra CC0 clips retargeted onto UAL (incoming/characters/README.md, "Recommendation"):
	# dodges, deaths, bow/crossbow, climb, two-handed, farm work, fishing, social.
	"res://assets/incoming/characters/_library/UAL_Extra_Mesh2Motion.glb",
	"res://assets/incoming/characters/_library/UAL_Extra_Mocap.glb",
	"res://assets/incoming/characters/_library/UAL_Extra_G6_male.glb"]
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
## Blender-built village set (tools/blender/make_village_*.py); the old pack paths are gone.
const GEN := "res://assets/generated/"
const MESHY := "res://assets/incoming/ai3d/meshy/"
const BUILDINGS := {
	# Hero buildings generated with Meshy from the concept sheets (user, see
	# docs/art_reference/concept_*.png), decimated to lod0/lod1 by tools/meshy.
	"adventurer_guild": [MESHY + "guild_lod0.glb", 16.0, MESHY + "guild_lod1.glb", 70.0],
	"healer_house": [MESHY + "healer_lod0.glb", 9.5, MESHY + "healer_lod1.glb", 70.0],
	"house_1": [GEN + "village_house_a.glb", 0.0, GEN + "village_house_a_lod1.glb", 45.0],
	"house_2": [GEN + "village_house_b.glb", 0.0, GEN + "village_house_b_lod1.glb", 45.0],
	"house_3": [GEN + "village_house_c.glb", 0.0, GEN + "village_house_c_lod1.glb", 45.0],
	"house_4": [GEN + "village_house_d.glb", 0.0, GEN + "village_house_d_lod1.glb", 45.0],
	"house_5": [GEN + "village_house_a_2.glb", 0.0, GEN + "village_house_a_2_lod1.glb", 45.0],
	"house_6": [GEN + "village_house_b_2.glb", 0.0, GEN + "village_house_b_2_lod1.glb", 45.0],
	"house_7": [GEN + "village_house_c_2.glb", 0.0, GEN + "village_house_c_2_lod1.glb", 45.0],
	"house_8": [GEN + "village_house_d_2.glb", 0.0, GEN + "village_house_d_2_lod1.glb", 45.0],
	"house_9": [GEN + "village_house_a_3.glb", 0.0, GEN + "village_house_a_3_lod1.glb", 45.0],
	"house_10": [GEN + "village_house_b_3.glb", 0.0, GEN + "village_house_b_3_lod1.glb", 45.0],
	"house_11": [GEN + "village_house_c_3.glb", 0.0, GEN + "village_house_c_3_lod1.glb", 45.0],
	"house_12": [GEN + "village_house_d_3.glb", 0.0, GEN + "village_house_d_3_lod1.glb", 45.0],
	"house_13": [GEN + "village_house_a_4.glb", 0.0, GEN + "village_house_a_4_lod1.glb", 45.0],
	"house_14": [GEN + "village_house_b_4.glb", 0.0, GEN + "village_house_b_4_lod1.glb", 45.0],
	"house_15": [GEN + "village_house_c_4.glb", 0.0, GEN + "village_house_c_4_lod1.glb", 45.0],
	"house_16": [GEN + "village_house_d_4.glb", 0.0, GEN + "village_house_d_4_lod1.glb", 45.0],
	# Meshy house types (user, paid plan): fitted to the 10.5 m lots.
	"mhouse_peasant_a": [MESHY + "house_peasant_a_lod0.glb", 7.5, MESHY + "house_peasant_a_lod1.glb", 45.0],
	"mhouse_peasant_b": [MESHY + "house_peasant_b_lod0.glb", 8.0, MESHY + "house_peasant_b_lod1.glb", 45.0],
	"mhouse_family": [MESHY + "house_family_lod0.glb", 9.0, MESHY + "house_family_lod1.glb", 45.0],
	"mhouse_trader": [MESHY + "house_trader_lod0.glb", 8.5, MESHY + "house_trader_lod1.glb", 45.0],
	"mhouse_manor": [MESHY + "house_manor_lod0.glb", 10.0, MESHY + "house_manor_lod1.glb", 45.0],
	"inn": [MESHY + "inn_lod0.glb", 13.5, MESHY + "inn_lod1.glb", 70.0],
	"blacksmith": [MESHY + "blacksmith_lod0.glb", 11.0, MESHY + "blacksmith_lod1.glb", 70.0],
	"stable": [GEN + "village_barn.glb", 0.0, GEN + "village_barn_lod1.glb", 45.0],
	"sawmill": [VILLAGE + "Buildings/FBX/Sawmill.fbx", 12.0],
	"mill": [VILLAGE + "Buildings/FBX/Mill.fbx", 11.0],
	"bell_tower": [GEN + "bell_tower.glb", 0.0],
	"chapel": [GEN + "chapel.glb", 0.0, GEN + "chapel_lod1.glb", 60.0],
	"market_stand_1": [MESHY + "stall_produce_lod0.glb", 3.8, MESHY + "stall_produce_lod1.glb", 40.0],
	"market_stand_2": [MESHY + "stall_cloth_lod0.glb", 3.8, MESHY + "stall_cloth_lod1.glb", 40.0],
	"market_stand_3": [GEN + "village_stall_3.glb", 0.0],
	"market_stand_4": [GEN + "village_stall_4.glb", 0.0],
	"planter_box": [GEN + "planter_box.glb", 0.0],
	"flower_bed": [GEN + "flower_bed.glb", 0.0],
	"fence": [GEN + "fence_section.glb", 0.0],
	"well": [GEN + "village_well.glb", 0.0],
	"cart": [GEN + "market_cart.glb", 0.0],
	"hand_cart": [GEN + "hand_cart.glb", 0.0],
	"lamp_post": [GEN + "lamp_post.glb", 0.0],
	"signpost": [GEN + "signpost.glb", 0.0],
	"haystack": [GEN + "haystack.glb", 0.0],
	"woodpile": [GEN + "woodpile.glb", 0.0],
	"washing_line": [GEN + "washing_line.glb", 0.0],
	"garden_plot": [GEN + "garden_plot.glb", 0.0],
	"field_crops": [GEN + "field_crops.glb", 0.0],
	"barrel": [VILLAGE + "Props/FBX/Barrel.fbx", 0.9],
	"crate": [VILLAGE + "Props/FBX/Crate.fbx", 1.0],
	"hay": [VILLAGE + "Props/FBX/Hay.fbx", 1.6],
	"bench": [VILLAGE + "Props/FBX/Bench_1.fbx", 2.0],
	"castle": [GEN + "castle_keep.glb", 0.0],
	"temple": [GEN + "temple.glb", 0.0],
	"watchtower": [RTS + "WatchTower_SecondAge_Level3.gltf", 7.0],
	"wall": [GEN + "town_wall.glb", 0.0],
	"wall_tower": [GEN + "town_wall_tower.glb", 0.0],
	"wall_gate": [GEN + "town_gate.glb", 0.0],
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
## One clip library per skeleton path (MakeHuman, G6/CDmir and Meshy rigs differ), built once.
static var _ual_cache := {}
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
## MakeHuman (CC0) villagers rigged on the UAL skeleton (tools/blender/make_humans.py).
const MH_DIR := "res://assets/generated/characters/"
## Guard gear from the armor library (CC-BY 3.0: Lotnik; Jacques Fourie; see CREDITS.md).
const GUARD_HELM := "res://assets/incoming/armor/opengameart/cc-by/anglo-saxon-helmets/anglo_saxon_helm2.glb"
const GUARD_SHIELD := "res://assets/incoming/armor/polypizza_sel/shield_round_wood_boss.glb"
## Look names -> MakeHuman character GLBs (one is picked at random).
## Paths containing "/" are full resource paths without ".glb" (the CC0 G6 and
## CDmir villagers in incoming/characters, already on the UAL skeleton).
const G6 := "res://assets/incoming/characters/g6-ual/"
## Meshy armored humanoids re-rigged to UAL (user's PC session); their helmets are part of the mesh.
const ARMORED := "res://assets/incoming/ai3d/meshy/armored/"
const CDMIR := "res://assets/incoming/characters/cdmir-ual/"
const MH_LOOKS := {
	"Rogue_Hooded": ["villager_man_a", "villager_man_b", "villager_woman_a", "villager_woman_b", "elder_man", "elder_woman",
		G6 + "g6_m_villager_tunic", G6 + "g6_f_villager_tunic", G6 + "g6_f_worker_apron"],
	"Barbarian": ["villager_man_a", "villager_man_b", "father", G6 + "g6_m_worker_apron", G6 + "g6_m_hunter_leather"],
	"Mage": ["villager_woman_a", "villager_woman_b", "mother", "elder_woman", G6 + "g6_f_villager_tunic", G6 + "g6_f_blacksmith_apron"],
	"Rogue": ["villager_man_b", "elder_man", "villager_man_a", G6 + "g6_m_villager_tunic", G6 + "g6_m_hunter_leather"],
	"Blacksmith": [G6 + "g6_m_blacksmith_apron"], "Innkeeper": [G6 + "g6_m_worker_apron", G6 + "g6_f_worker_apron"],
	"Hunter": [G6 + "g6_m_hunter_leather", G6 + "g6_f_hunter_leather"], "Monk": [CDMIR + "cdmir_monk"],
	"Herbalist": [CDMIR + "cdmir_old_lady"], "Trader": [G6 + "g6_m_villager_tunic", G6 + "g6_f_worker_apron"],
	"Knight": [ARMORED + "guard", ARMORED + "mercenary"],
	"Player": ["player_young"], "Guard": [ARMORED + "guard"], "Plate_Knight": [ARMORED + "knight"],
	"Mercenary": [ARMORED + "mercenary"], "Bandit": [ARMORED + "bandit"], "Noble": [ARMORED + "noble"],
	"Orc_Warchief": [ARMORED + "orc_warchief"],
	"Mother": ["mother"], "Father": ["father"],
	"Child_Boy": ["child_boy"], "Child_Girl": ["child_girl"],
	"Elder_Man": ["elder_man"], "Elder_Woman": ["elder_woman"],
}
const USE_MAKEHUMAN := true


static func character(file_name: String, height: float, keep: Array[String] = []) -> Node3D:
	if USE_MAKEHUMAN and MH_LOOKS.has(file_name):
		var files: Array = MH_LOOKS[file_name]
		return mh_character(files[randi() % files.size()], height, keep)
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
## A MakeHuman GLB on the UAL skeleton, `height` metres tall, with the UAL clips.
static func mh_character(file: String, height: float, keep: Array[String] = [], lod1 := false) -> Node3D:
	var root := Node3D.new()
	var path := (file if file.contains("/") else MH_DIR + file) + ("_lod1" if lod1 and not file.contains("/") else "") + ".glb"
	var base: Node3D = (load(path) as PackedScene).instantiate()
	root.add_child(base)
	var skeleton: Skeleton3D = base.find_children("*", "Skeleton3D", true, false)[0]
	var armored := file.begins_with(ARMORED)
	for part in keep:      # same props as humanoid(); the rig is in metres
		if armored and part.contains("Helmet"):
			continue
		if part.contains("Helmet"):
			_attach(skeleton, "Head", GUARD_HELM, 0.27, Vector3(0, 0.07, 0.01), Vector3.ZERO)
		elif part.contains("Axe"):
			_attach(skeleton, "hand_r", WEAPONS + "Axe_Bronze.gltf", 0.75, Vector3(0.05, 0.02, 0), Vector3(0, 0, -90))
		elif part.contains("2H_Sword"):
			_attach(skeleton, "hand_r", WEAPONS + "Sword_Bronze.gltf", 1.3, Vector3(0.05, 0.02, 0), Vector3(0, 0, -90))
		elif part.contains("Sword"):
			_attach(skeleton, "hand_r", WEAPONS + "Sword_Bronze.gltf", 0.95, Vector3(0.05, 0.02, 0), Vector3(0, 0, -90))
		elif part.contains("Shield"):
			_attach(skeleton, "lowerarm_l", GUARD_SHIELD, 0.65, Vector3(0.12, 0, 0.08), Vector3(0, 90, 0))
	var anim := AnimationPlayer.new()
	anim.name = "AnimationPlayer"
	base.add_child(anim)
	anim.root_node = anim.get_path_to(base)
	anim.add_animation_library("", _ual_for(base.get_path_to(skeleton)))
	var head := skeleton.find_bone("Head")
	var native := skeleton.get_bone_global_rest(head).origin.y * 1.1
	# Helmets/hoods sit above the head bone: scale armored models so the helmet top
	# lands near the requested height (ratios from ai3d/meshy/armored/README.md).
	var k := 0.9 if armored else 1.0
	root.scale = Vector3.ONE * (height * k / maxf(native, 0.01))
	return root


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
			_attach(skeleton, "Head", GUARD_HELM, 0.27, Vector3(0, 0.07, 0.01), Vector3.ZERO)
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
	if _ual_cache.has(sk):
		return _ual_cache[sk]
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
	_ual_cache[sk] = lib
	return lib


# --- Buildings -------------------------------------------------------------------------

## One merged mesh per building (all parts, grouped by material), scaled so its
## longest horizontal side is the catalogue size (0 = native size), centred on
## x/z with its base at y = 0. Ready for MultiMesh instancing.
## Chimney openings of a building in its fitted mesh space (from `chimney_top*`
## marker nodes the Blender generators export), for smoke emitters.
static var _chimney_cache := {}


static func chimney_points(key: String) -> Array[Vector3]:
	if _chimney_cache.has(key):
		return _chimney_cache[key]
	var out: Array[Vector3] = []
	var entry: Array = BUILDINGS.get(key, [])
	if entry.is_empty() or not ResourceLoader.exists(entry[0]):
		_chimney_cache[key] = out
		return out
	var raw := merged_mesh(entry[0])
	var inst: Node3D = (load(entry[0]) as PackedScene).instantiate()
	if raw:
		var box := raw.get_aabb()
		var target: float = entry[1]
		var sc := 1.0 if target <= 0.0 else target / maxf(maxf(box.size.x, box.size.z), 0.001)
		var off := Vector3(-(box.position.x + box.size.x * 0.5), -box.position.y, -(box.position.z + box.size.z * 0.5))
		for n in inst.find_children("chimney_top*", "Node3D", true, false):
			var t := Transform3D.IDENTITY
			var cur: Node = n
			while cur != null and cur != inst:
				t = (cur as Node3D).transform * t
				cur = cur.get_parent()
			out.append((t.origin + off) * sc)
	inst.free()
	_chimney_cache[key] = out
	return out


## Distance where a building swaps to its far version (0 = no LOD).
static func building_lod_distance(key: String) -> float:
	var entry: Array = BUILDINGS.get(key, [])
	return float(entry[3]) if entry.size() > 3 else 0.0


## Far-distance version of a building, or null if it has none.
static func building_lod_mesh(key: String) -> ArrayMesh:
	var entry: Array = BUILDINGS.get(key, [])
	if entry.size() < 3:
		return null
	return building_mesh(key + ":lod1")


static func building_mesh(key: String) -> ArrayMesh:
	if _building_cache.has(key):
		return _building_cache[key]
	var is_lod := key.ends_with(":lod1")
	var entry: Array = BUILDINGS[key.trim_suffix(":lod1")]
	var mesh := merged_mesh(entry[2] if is_lod else entry[0])
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
		bs.size = Vector3(box.size.x * 0.92, box.size.y, box.size.z * 0.92)
		shape.shape = bs
		body.position = box.get_center()
		body.add_child(shape)
		root.add_child(body)
	return root


## Nature mesh scaled to its catalogue height, base at y = 0.
static var _leaf_materials := {}


## Swaps alpha-cut leaf/needle surfaces of Blender trees to the swaying foliage shader.
static func _windy_leaves(mesh: ArrayMesh) -> void:
	for i in mesh.get_surface_count():
		var m := mesh.surface_get_material(i) as BaseMaterial3D
		if m == null or m.transparency != BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
			continue
		if not _leaf_materials.has(m):
			var sm := ShaderMaterial.new()
			sm.shader = preload("res://shaders/tree_wind.gdshader")
			sm.set_shader_parameter("albedo_tex", m.albedo_texture)
			sm.set_shader_parameter("albedo", m.albedo_color)
			sm.set_shader_parameter("alpha_cut", m.alpha_scissor_threshold)
			_leaf_materials[m] = sm
		mesh.surface_set_material(i, _leaf_materials[m])


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
	if key.begins_with("nature/"):
		_windy_leaves(mesh)
	var box := mesh.get_aabb()
	var s: float = 1.0 if is_scan else NATURE[key] / maxf(box.size.y, 0.001)
	mesh = _transformed(mesh, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * s),
		Vector3(-(box.position.x + box.size.x * 0.5) * s, -box.position.y * s, -(box.position.z + box.size.z * 0.5) * s)))
	_building_cache[cache_key] = mesh
	return mesh
