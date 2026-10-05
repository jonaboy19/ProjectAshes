extends "res://scripts/interiors/interior_room.gd"
## Code-built great hall for the lord's seats of Region 1 (Crownstead Steward's Hall, Highwatch Keep): a plastered, timbered room
## furnished with the Meshy free pack's thrones, chairs, tables, bookshelves, tapestries, wall shields, sconces and bed
## (docs/qa/ASSET_AUDIT.md "furniture/" and "interior/"). Subclasses call `_build_hall(layout)` from `_init`, because InteriorDoor
## takes the Environment, preview camera and exit door out of the instanced scene BEFORE it enters the tree.
## Same contract as scenes/interiors/README.md: origin = floor centre, entrance in the +Z wall, PlayerSpawn, ExitDoor, NPCs markers.
## Furniture fronts face +Z (toward the door), x is right. Everything is static; tables, thrones, shelves and the bed get box colliders.

const FREE := "res://assets/incoming/meshy_free/"
const DoorScript := preload("res://scripts/interiors/interior_door.gd")
const HEIGHT := 4.6

## layout -> {size [w, d], title, floor, wall, beam, npcs, lights, items}. item: [asset, x, z, yaw deg, y (wall items), collider [w, d] or null]
const LAYOUTS := {
	"steward": {
		"title": "Steward's Hall", "size": [12.0, 14.0], "floor": Color("5a3d24"), "wall": Color("cdbf9d"), "beam": Color("4a3020"),
		"npcs": [["NPC_Steward", "Noble", -0.2, -3.0, 0.0, "steward"], ["NPC_Clerk", "Trader", -3.6, -2.4, 70.0, "clerk"]],
		"lights": [[0.0, 3.4, -4.4, 1.5, true], [0.0, 3.8, 2.8, 0.9, false]],
		"dais": [0.0, -5.7, 8.4, 2.6, 0.32],
		"rug": [0.0, 1.4, 4.4, 8.4, "6d1f1c", "8c3a2a"],
		"items": [
			["furniture/throne_gold_red", 0.0, -6.0, 0.0, 0.32, [0.9, 0.9]],
			["furniture/throne_red_gothic", -2.3, -5.9, 0.0, 0.32, [0.9, 0.9]],
			["furniture/throne_carved_wood", 2.3, -5.9, 0.0, 0.32, [0.9, 0.9]],
			["furniture/lectern_desk", -3.8, -3.2, 25.0, 0.0, [1.3, 1.3]],
			["furniture/table_tavern_trestle", 0.0, 0.2, 90.0, 0.0, [2.3, 1.2]],
			["furniture/table_tavern_trestle", 0.0, 2.6, 90.0, 0.0, [2.3, 1.2]],
			["furniture/chair_high_back", 0.0, -1.5, 0.0, 0.0, null],
			["furniture/chair_ornate_red", 0.0, 4.2, 180.0, 0.0, null],
			["furniture/chair_gothic_tall", -1.45, 0.2, 90.0, 0.0, null],
			["furniture/chair_armchair_wood", 1.45, 0.2, -90.0, 0.0, null],
			["furniture/chair_simple_a", -1.45, 2.6, 90.0, 0.0, null],
			["furniture/chair_simple_b", 1.45, 2.6, -90.0, 0.0, null],
			["interior/bookshelf_tall_rustic", -5.6, -1.0, 90.0, 0.0, [0.6, 1.7]],
			["interior/bookshelf_glass_cabinet", -5.6, 1.2, 90.0, 0.0, [0.6, 1.2]],
			["interior/bookshelf_wide_low", -5.65, 3.3, 90.0, 0.0, [0.4, 2.0]],
			["interior/tapestry_hunt", -3.6, -6.88, 0.0, 1.5, null],
			["interior/tapestry_hunt", 3.6, -6.88, 0.0, 1.5, null],
			["interior/wall_shield_heater", 5.88, -1.5, -90.0, 1.7, null],
			["interior/wall_shield_iron_studded", 5.82, 1.0, -90.0, 1.5, null],
			["interior/bed_canopy_red", 4.5, -5.0, 0.0, 0.0, [2.2, 2.2]],
			["lighting/sconce_torch_ornate", -2.6, -6.85, 0.0, 2.3, null],
			["lighting/sconce_torch_ornate", 2.6, -6.85, 0.0, 2.3, null],
			["lighting/sconce_wall_bowl_a", 5.85, 3.5, -90.0, 2.2, null],
			["lighting/sconce_wall_bowl_b", -5.85, -4.3, 90.0, 2.2, null],
			["props/chest_gold", -3.9, -6.3, 20.0, 0.0, [0.9, 0.7]],
			["maybe/interior/bookshelf_nook_corner", -5.1, -6.1, 0.0, 0.0, [1.8, 1.7]],
		],
	},
	"keep": {
		"title": "Highwatch Keep, great hall", "size": [14.0, 12.0], "floor": Color("4f3a28"), "wall": Color("b9b2a2"), "beam": Color("3d2a1c"),
		"npcs": [["NPC_Guard", "Guard", -2.4, -3.4, 0.0, "guard"], ["NPC_Knight", "Knight", 2.9, 0.4, 200.0, "knight"]],
		"lights": [[0.0, 3.2, -3.8, 1.5, true], [0.0, 3.6, 2.4, 0.9, false]],
		"dais": [0.0, -4.9, 7.0, 2.2, 0.3],
		"rug": [0.0, 1.2, 9.0, 4.4, "3a2a40", "55405f"],
		"items": [
			["furniture/throne_dark_red_studded", 0.0, -5.0, 0.0, 0.3, [0.9, 0.9]],
			["furniture/throne_gothic_gold", -2.4, -4.9, 0.0, 0.3, [1.0, 0.9]],
			["furniture/throne_leather_cushion", 2.4, -4.9, 0.0, 0.3, [0.8, 0.8]],
			["furniture/table_tavern_feast", -3.0, 0.8, 90.0, 0.0, [2.0, 1.1]],
			["furniture/table_tavern_feast", 3.0, 0.8, 90.0, 0.0, [2.0, 1.1]],
			["furniture/table_tavern_thick", 0.0, 2.8, 0.0, 0.0, [1.6, 1.6]],
			["furniture/chair_simple_a", -4.1, 0.8, 90.0, 0.0, null],
			["furniture/chair_simple_b", -1.9, 0.8, -90.0, 0.0, null],
			["furniture/chair_simple_a", 1.9, 0.8, 90.0, 0.0, null],
			["furniture/chair_simple_b", 4.1, 0.8, -90.0, 0.0, null],
			["interior/armour_stand_knight", -6.4, -3.6, 90.0, 0.0, [0.7, 0.9]],
			["interior/armour_stand_knight", 6.4, -3.6, -90.0, 0.0, [0.7, 0.9]],
			["interior/weapon_rack_swords", -6.6, 0.5, 90.0, 0.0, [0.4, 1.0]],
			["interior/weapon_racks_spears", 6.2, 1.8, -90.0, 0.0, [2.4, 1.3]],
			["interior/shelf_weapons_display", 6.7, -1.2, -90.0, 0.4, null],
			["interior/bookshelf_wide_low", -6.75, 3.4, 90.0, 0.0, [0.3, 1.9]],
			["interior/wall_shield_heater", -6.9, -1.6, 90.0, 1.6, null],
			["interior/wall_shield_iron_studded", -3.6, -5.88, 0.0, 1.9, null],
			["interior/wall_shield_heater", 3.6, -5.9, 0.0, 1.8, null],
			["interior/tapestry_hunt", 0.0, -5.9, 0.0, 2.6, null],
			["banners/banner_tall_cross", -5.2, -5.1, 0.0, 0.0, null],
			["banners/banner_tall_cross", 5.2, -5.1, 0.0, 0.0, null],
			["lighting/sconce_torch_bracket", -6.9, 3.8, 90.0, 2.3, null],
			["lighting/sconce_wall_bowl_a", 6.9, -3.9, -90.0, 2.3, null],
			["lighting/sconce_wall_bowl_b", -3.0, 5.88, 180.0, 2.3, null],
			["lighting/sconce_torch_ornate", 3.0, 5.88, 180.0, 2.3, null],
		],
	},
}

var _body: StaticBody3D
var _mat_cache := {}


func _build_hall(layout: String) -> void:
	var def: Dictionary = LAYOUTS[layout]
	var sz: Array = def["size"]
	var w := float(sz[0])
	var d := float(sz[1])
	set_meta("title", def["title"])
	# room shell: floor, ceiling, four walls (the +Z wall carries the exit door), cross beams
	var room := Node3D.new()
	room.name = "Room"
	add_child(room)
	_body = StaticBody3D.new()
	_body.name = "Colliders"
	add_child(_body)
	_slab(room, Vector3(w, 0.4, d), Vector3(0, -0.2, 0), def["floor"], true)
	_slab(room, Vector3(w, 0.4, d), Vector3(0, HEIGHT + 0.2, 0), def["beam"], true)
	_slab(room, Vector3(0.3, HEIGHT, d), Vector3(-w * 0.5 - 0.15, HEIGHT * 0.5, 0), def["wall"], true)
	_slab(room, Vector3(0.3, HEIGHT, d), Vector3(w * 0.5 + 0.15, HEIGHT * 0.5, 0), def["wall"], true)
	_slab(room, Vector3(w + 0.6, HEIGHT, 0.3), Vector3(0, HEIGHT * 0.5, -d * 0.5 - 0.15), def["wall"], true)
	_slab(room, Vector3(w + 0.6, HEIGHT, 0.3), Vector3(0, HEIGHT * 0.5, d * 0.5 + 0.15), def["wall"], true)
	# wainscot band and skirting so the plaster does not read as a bare box
	_slab(room, Vector3(0.1, 1.15, d), Vector3(-w * 0.5 + 0.05, 0.575, 0), def["beam"].lightened(0.1), false)
	_slab(room, Vector3(0.1, 1.15, d), Vector3(w * 0.5 - 0.05, 0.575, 0), def["beam"].lightened(0.1), false)
	_slab(room, Vector3(w, 1.15, 0.1), Vector3(0, 0.575, -d * 0.5 + 0.05), def["beam"].lightened(0.1), false)
	_slab(room, Vector3(w, 1.15, 0.1), Vector3(0, 0.575, d * 0.5 - 0.05), def["beam"].lightened(0.1), false)
	if def.has("rug"):
		var rg: Array = def["rug"]
		_slab(room, Vector3(float(rg[2]), 0.03, float(rg[3])), Vector3(float(rg[0]), 0.015, float(rg[1])), Color(rg[4]), false)
		_slab(room, Vector3(float(rg[2]) - 0.5, 0.034, float(rg[3]) - 0.5), Vector3(float(rg[0]), 0.017, float(rg[1])), Color(rg[5]), false)
	for i in int(d / 3.0):
		_slab(room, Vector3(w, 0.28, 0.32), Vector3(0, HEIGHT - 0.14, -d * 0.5 + 1.5 + i * 3.0), def["beam"], false)
	for sx: float in [-1.0, 1.0]:                 # timber posts along the long walls
		for i in int(d / 3.5) + 1:
			_slab(room, Vector3(0.26, HEIGHT, 0.26), Vector3(sx * (w * 0.5 - 0.13), HEIGHT * 0.5, -d * 0.5 + 0.2 + i * 3.5), def["beam"], false)
	if def.has("dais"):
		var ds: Array = def["dais"]
		_slab(room, Vector3(float(ds[2]), float(ds[4]), float(ds[3])), Vector3(float(ds[0]), float(ds[4]) * 0.5, float(ds[1])), def["floor"].lightened(0.12), true)
	# furniture
	var furniture := Node3D.new()
	furniture.name = "Furniture"
	add_child(furniture)
	for it: Array in def["items"]:
		_place(furniture, it)
	# player spawn, exit door, NPC markers, lights, environment, preview camera
	var spawn := Marker3D.new()
	spawn.name = "PlayerSpawn"
	add_child(spawn)
	spawn.position = Vector3(0, 0.05, d * 0.5 - 1.6)
	var exit := DoorScript.new() as Area3D
	exit.set("is_exit", true)
	exit.set("prompt_text", "Leave")
	exit.name = "ExitDoor"
	add_child(exit)
	exit.position = Vector3(0, 0, d * 0.5 - 0.45)
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(2.4, 3.3, 1.0)
	cs.shape = bx
	cs.position.y = 1.65
	exit.add_child(cs)
	var npcs := Node3D.new()
	npcs.name = "NPCs"
	add_child(npcs)
	for n: Array in def["npcs"]:
		var m := Marker3D.new()
		m.name = String(n[0])
		npcs.add_child(m)
		m.position = Vector3(float(n[2]), 0, float(n[3]))
		m.rotation.y = deg_to_rad(float(n[4]))
		m.set_meta("look", n[1])
		m.set_meta("height", 1.75)
		m.set_meta("anim", "Idle")
		m.set_meta("role", n[5])
	var li := 0
	for l: Array in def["lights"]:
		var o := OmniLight3D.new()
		o.name = "HallLight%d" % li
		li += 1
		add_child(o)
		o.position = Vector3(float(l[0]), float(l[1]), float(l[2]))
		o.light_color = Color(1.0, 0.82, 0.55)
		o.light_energy = float(l[3])
		o.light_specular = 0.3
		o.shadow_enabled = false
		o.omni_range = 10.0
		o.omni_attenuation = 1.4
		o.set_meta("flicker", bool(l[4]))
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.035, 0.028, 0.022)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1.0, 0.93, 0.8)
	env.ambient_light_energy = 1.25
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.15
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var cam := Camera3D.new()
	cam.name = "PreviewCamera"
	add_child(cam)
	cam.position = Vector3(0, 2.4, d * 0.5 - 0.3)
	cam.fov = 70.0
	cam.current = true


func _mat(col: Color) -> StandardMaterial3D:
	var k := col.to_html()
	if not _mat_cache.has(k):
		var m := StandardMaterial3D.new()
		m.albedo_color = col
		m.roughness = 0.92
		m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		_mat_cache[k] = m
	return _mat_cache[k]


func _slab(parent: Node3D, size: Vector3, at: Vector3, col: Color, solid: bool) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(col)
	mi.position = at
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	if solid:
		_collider(size, at)


func _collider(size: Vector3, at: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = size
	cs.shape = bx
	cs.position = at
	_body.add_child(cs)


func _place(parent: Node3D, it: Array) -> void:
	var path := FREE + String(it[0]) + "_lod0.glb"
	if not ResourceLoader.exists(path):
		return
	var n: Node3D = Assets.static_model(path)
	if n == null:
		return
	parent.add_child(n)
	var box := Assets.visual_aabb(n)
	var y := float(it[4])
	n.position = Vector3(float(it[1]), y - box.position.y, float(it[2]))
	n.rotation.y = deg_to_rad(float(it[3]))
	for g in n.find_children("*", "GeometryInstance3D", true, false):
		(g as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if it[5] != null:
		var c: Array = it[5]
		_collider(Vector3(float(c[0]), maxf(box.size.y, 0.6), float(c[1])), Vector3(float(it[1]), y + maxf(box.size.y, 0.6) * 0.5, float(it[2])))
