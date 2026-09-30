extends Node3D
## Runtime of the caves planned by region_caves.gd: builds each cave mouth near the player, places a
## dungeon_door.gd in it and runs the hidden-entrance reveals (waterfall, vines, rockfall, night rune).
## Add ONE child to RegionDressing._ready: `add_child(preload("res://scripts/world/region_caves_view.gd").new())`.
## It finds the player itself (group "player"), streams mouths within BUILD and frees them past FREE.
## Discoveries land in Life.discovery (map + journal + banner) and the exploration realm module
## (scripts/realm/exploration.gd).

const Plan := preload("res://scripts/world/region_caves.gd")
const Kit := preload("res://scripts/interiors/dungeon_kit.gd")
const DungeonDoor := preload("res://scripts/interiors/dungeon_door.gd")
const Thing := preload("res://scripts/interiors/dungeon_thing.gd")
const BUILD := 230.0
const FREE := 320.0

var _built: Dictionary = {}        # dungeon_id -> Node3D
var _timer := 0.0
var _player: Node3D = null
var _sites_by_id: Dictionary = {}  # dungeon_id -> site dictionary
var _local_revealed: Dictionary = {}


func _ready() -> void:
	name = "RegionCaves"
	for s in Plan.cave_sites():
		_sites_by_id[String(s["cave"]["dungeon_id"])] = s
	_restore_discoveries()


## After a load: hidden places already revealed must be on the map again.
func _restore_discoveries() -> void:
	var life := get_node_or_null("/root/Life")
	if life == null or life.get("discovery") == null or life.get("realm") == null:
		return
	var ex: Variant = life.realm.mod("exploration")
	if ex == null:
		return
	for id: String in ex.revealed:
		if _sites_by_id.has(id):
			life.discovery.reveal_site(_sites_by_id[id], int(ex.revealed[id]), false)


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.6
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
		if _player == null:
			return
	var p := Vector2(_player.global_position.x, _player.global_position.z)
	for id: String in _sites_by_id:
		var s: Dictionary = _sites_by_id[id]
		var d := p.distance_to(s["pos"])
		if d < BUILD and not _built.has(id):
			_built[id] = _build(s)
		elif d > FREE and _built.has(id):
			var n: Node3D = _built[id]
			_built.erase(id)
			if is_instance_valid(n):
				n.queue_free()
	for id: String in _built:
		_tick_site(_sites_by_id[id], _built[id], p)


func built_count() -> int:
	return _built.size()


## Builds every cave mouth now (screenshots, tests).
func build_all_now() -> void:
	for id: String in _sites_by_id:
		if not _built.has(id):
			_built[id] = _build(_sites_by_id[id])


func door_for(dungeon_id: String) -> Node:
	if _built.has(dungeon_id) and is_instance_valid(_built[dungeon_id]):
		return (_built[dungeon_id] as Node).get_node_or_null("Door")
	return null


func _exploration() -> Variant:
	var life := get_node_or_null("/root/Life")
	if life != null and life.get("realm") != null:
		return life.realm.mod("exploration")
	return null


func is_revealed(id: String) -> bool:
	var ex: Variant = _exploration()
	if ex != null:
		return ex.is_revealed(id)
	return _local_revealed.has(id)



func _is_night() -> bool:
	var ws := get_node_or_null("/root/WorldSim")
	var h := 12.0 if ws == null or ws.get("time_of_day") == null else float(ws.get("time_of_day"))
	return h >= 20.5 or h < 5.0


func _knows_lead(id: String) -> bool:
	var ex: Variant = _exploration()
	return ex != null and ex.knows_lead(id)


func _build(s: Dictionary) -> Node3D:
	var c: Dictionary = s["cave"]
	var pos: Vector2 = s["pos"]
	var root := Node3D.new()
	root.name = "Cave_%s" % c["dungeon_id"]
	add_child(root)
	root.position = Vector3(pos.x, WorldGen.height(pos.x, pos.y), pos.y)
	root.rotation.y = float(s["yaw"])
	var theme: String = c["theme"]
	var hidden: bool = bool(c["hidden"])
	var revealed := not hidden or is_revealed(c["dungeon_id"])
	var own_mouth := not (theme == "mine" and not hidden) and String(c["reveal"]) != "waterfall"
	if own_mouth:
		root.add_child(_mouth(theme, hidden and not revealed, String(c["reveal"])))
	elif String(c["reveal"]) == "waterfall":
		root.add_child(_mouth(theme, false, "waterfall"))
	# the door sits just inside the mouth; `mine_entrance` opens at about z = 2.5
	var door := DungeonDoor.new()
	door.name = "Door"
	root.add_child(door)
	door.configure(c)
	door.name = "Door"
	var front := 1.3 if theme != "mine" or hidden else 2.6
	door.position = Vector3(0, 0.0, front)
	door.global_position.y = WorldGen.height(door.global_position.x, door.global_position.z)
	door.monitoring = revealed
	if not revealed:
		door.set_meta("sealed", true)
	# reveal interactions
	if hidden and not revealed:
		match String(c["reveal"]):
			"vines":
				_vines(root, s)
			"rockfall":
				_rockfall(root, s)
			"night":
				_night_plug(root, s)
			"waterfall":
				pass
	return root


func _tick_site(s: Dictionary, node: Node3D, p: Vector2) -> void:
	var c: Dictionary = s["cave"]
	if not bool(c["hidden"]):
		return
	var id: String = c["dungeon_id"]
	if is_revealed(id):
		return
	match String(c["reveal"]):
		"waterfall":
			# walking through the curtain finds the dry ledge behind it
			var door := node.get_node_or_null("Door") as Node3D
			if door != null and p.distance_to(Vector2(door.global_position.x, door.global_position.z)) < 3.0:
				reveal(id, "waterfall")
		"night":
			var plug := node.get_node_or_null("NightPlug") as Node3D
			if plug != null:
				var show := _is_night() or _knows_lead(id)
				plug.get_node("Glow").visible = show
				(plug.get_node("Light") as OmniLight3D).light_energy = 1.2 if show else 0.0
				# the rock plug only lets you through at night (or once you know where to look)
				var ready := _is_night()
				var door2 := node.get_node_or_null("Door") as InteriorDoor
				if door2 != null:
					door2.monitoring = ready
				var blocker := plug.get_node_or_null("Body/Shape") as CollisionShape3D
				if blocker != null:
					blocker.disabled = ready
				plug.get_node("Rock").visible = not ready
				if ready and p.distance_to(Vector2(plug.global_position.x, plug.global_position.z)) < 6.0:
					reveal(id, "night")


## Reveal a hidden entrance: map + journal + banner, door becomes usable.
func reveal(id: String, how: String) -> bool:
	if is_revealed(id):
		return false
	var s: Dictionary = _sites_by_id.get(id, {})
	if s.is_empty():
		return false
	var ex: Variant = _exploration()
	var day := 1
	var ws := get_node_or_null("/root/WorldSim")
	if ws != null and ws.get("day") != null:
		day = int(ws.get("day"))
	if ex != null:
		ex.reveal(id, day)
	else:
		_local_revealed[id] = day
	var life := get_node_or_null("/root/Life")
	if life != null and life.get("discovery") != null:
		life.discovery.reveal_site(s, day, true)
	var game := get_node_or_null("/root/Game")
	if game != null:
		var line := "You have found a hidden entrance: %s." % s["name"]
		game.call("say", line)
	# visuals + door
	if _built.has(id) and is_instance_valid(_built[id]):
		var node: Node3D = _built[id]
		var door := node.get_node_or_null("Door") as InteriorDoor
		if door != null:
			door.monitoring = true
		for n in ["Vines", "Rockfall", "NightPlug"]:
			var v := node.get_node_or_null(n)
			if v != null:
				if n == "NightPlug":
					v.queue_free()
				else:
					for cs in v.find_children("*", "CollisionShape3D", true, false):
						(cs as CollisionShape3D).set_deferred("disabled", true)
					var tw := create_tween()
					tw.tween_property(v, "position:y", v.position.y - 4.0 if n == "Rockfall" else v.position.y - 0.5, 1.0)
					if n == "Vines":
						tw.parallel().tween_property(v, "scale", Vector3(1, 0.01, 1), 0.8)
					tw.tween_callback(v.queue_free)
		for t in node.find_children("reveal_*", "Area3D", true, false):
			(t as InteriorDoor).monitoring = false
			if t.is_in_group("interactable"):
				t.remove_from_group("interactable")
	return true


## A dungeon_thing "reveal" interaction calls this (vines cut, rockfall cleared).
func reveal_by_thing(id: String, how: String) -> void:
	reveal(id, how)


# --- hidden entrance dressing -----------------------------------------------------------------

static var _mouth_cache: Dictionary = {}


## The cave mouth: a horseshoe of faceted boulders round a dark opening (or a carved doorway for crypts).
func _mouth(theme: String, plugged: bool, reveal_kind: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Mouth"
	var key := theme if theme != "flooded" and theme != "crystal" and theme != "warren" else "cave"
	if not _mouth_cache.has(key):
		_mouth_cache[key] = _mouth_mesh(key)
	var mi := MeshInstance3D.new()
	mi.mesh = _mouth_cache[key]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	mi.position.y = -0.25
	root.add_child(mi)
	# colliders: two jambs and a lintel, so the opening stays walkable
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	root.add_child(body)
	for b: Array in [[Vector3(-2.4, 1.6, 0.0), Vector3(1.6, 3.4, 3.0)], [Vector3(2.4, 1.6, 0.0), Vector3(1.6, 3.4, 3.0)], [Vector3(0, 3.6, 0.0), Vector3(5.6, 1.2, 3.0)], [Vector3(0, 1.6, -1.7), Vector3(5.0, 3.4, 0.8)]]:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = b[1]
		cs.shape = bs
		cs.position = b[0]
		body.add_child(cs)
	return root


static func _mouth_mesh(key: String) -> ArrayMesh:
	var acc := Kit.Acc.new()
	var seed_n := 5
	if key == "crypt":
		var stone := Color(0.62, 0.62, 0.64)
		Kit._box(acc, Vector3(-2.1, 1.7, 0), Vector3(1.4, 3.4, 1.6), 0.0, stone)
		Kit._box(acc, Vector3(2.1, 1.7, 0), Vector3(1.4, 3.4, 1.6), 0.0, stone)
		Kit._box(acc, Vector3(0, 3.65, 0), Vector3(5.6, 0.9, 1.8), 0.0, stone * 0.92)
		Kit._box(acc, Vector3(0, 4.3, 0), Vector3(4.6, 0.5, 1.4), 0.0, stone * 0.85)
		Kit._box(acc, Vector3(-3.1, 0.6, 0.6), Vector3(1.0, 1.2, 1.0), 0.4, stone * 0.8)
	else:
		for i in 9:
			var a := PI * float(i) / 8.0
			var pos := Vector3(cos(a) * 2.35, sin(a) * 2.2 + 0.2, (Kit._h01(i, seed_n, 1, 4) - 0.5) * 0.8)
			var r := Vector3(1.05, 1.0, 1.1) * (0.85 + 0.45 * Kit._h01(i, seed_n, 2, 4))
			Kit._blob(acc, pos, r, Color(0.52, 0.49, 0.45) * (0.85 + 0.2 * Kit._h01(i, seed_n, 3, 4)), 50 + i)
		Kit._blob(acc, Vector3(0, 3.0, -0.3), Vector3(2.6, 1.3, 1.6), Color(0.46, 0.44, 0.41), 70)
		Kit._blob(acc, Vector3(-3.4, 0.0, 0.3), Vector3(1.2, 1.6, 1.2), Color(0.5, 0.47, 0.43), 71)
		Kit._blob(acc, Vector3(3.3, 0.0, 0.1), Vector3(1.3, 1.5, 1.2), Color(0.48, 0.46, 0.42), 72)
		Kit._blob(acc, Vector3(-4.5, 0.0, 1.5), Vector3(0.9, 0.7, 0.9), Color(0.5, 0.47, 0.43), 73)
	# the dark inside: a black quad just behind the jambs
	var bk := Color(0.0, 0.0, 0.0)
	Kit._quad(acc, Vector3(-2.0, 0, -1.0), Vector3(2.0, 0, -1.0), Vector3(2.0, 3.4, -1.0), Vector3(-2.0, 3.4, -1.0), bk, bk, bk, bk)
	var mats := Kit.materials("crypt" if key == "crypt" else "cave")
	var m := Kit._to_mesh(acc, mats["shell"])
	return m


func _vines(root: Node3D, s: Dictionary) -> void:
	var v := Node3D.new()
	v.name = "Vines"
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.36, 0.14)
	mat.roughness = 1.0
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(s["name"])
	for i in 26:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		var len := rng.randf_range(2.6, 4.2)
		bm.size = Vector3(0.16, len, 0.06)
		mi.mesh = bm
		mi.material_override = mat
		mi.position = Vector3(-2.3 + 4.6 * float(i) / 25.0 + rng.randf_range(-0.12, 0.12), 3.7 - len * 0.5, 1.0 + rng.randf_range(-0.15, 0.25))
		mi.rotation.z = rng.randf_range(-0.12, 0.12)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		v.add_child(mi)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(4.8, 3.6, 0.3)
	cs.shape = bs
	cs.position = Vector3(0, 1.8, 1.0)
	body.add_child(cs)
	v.add_child(body)
	root.add_child(v)
	_reveal_thing(root, s, "vines", Vector3(0, 0, 2.6))


func _rockfall(root: Node3D, s: Dictionary) -> void:
	var v := Node3D.new()
	v.name = "Rockfall"
	var acc := Kit.Acc.new()
	for i in 7:
		Kit._blob(acc, Vector3(-1.9 + i * 0.63, 0, 0.3 + (i % 2) * 0.4), Vector3(1.0, 1.1, 1.0) * (0.8 + (i % 3) * 0.25), Color(0.5, 0.47, 0.43) * (0.85 + 0.05 * i), 90 + i)
	Kit._blob(acc, Vector3(0, 1.1, 0.4), Vector3(1.8, 1.3, 1.2), Color(0.46, 0.44, 0.41), 99)
	var mi := MeshInstance3D.new()
	mi.mesh = Kit._to_mesh(acc, Kit.materials("cave")["shell"])
	v.add_child(mi)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(4.6, 3.0, 1.8)
	cs.shape = bs
	cs.position = Vector3(0, 1.5, 0.6)
	body.add_child(cs)
	v.add_child(body)
	v.position = Vector3(0, -0.1, 0.9)
	root.add_child(v)
	_reveal_thing(root, s, "rockfall", Vector3(0, 0, 3.0))


func _night_plug(root: Node3D, s: Dictionary) -> void:
	var v := Node3D.new()
	v.name = "NightPlug"
	var acc := Kit.Acc.new()
	Kit._blob(acc, Vector3(0, 0, 0), Vector3(2.8, 3.4, 0.9), Color(0.47, 0.45, 0.43), 120)
	var rock := MeshInstance3D.new()
	rock.name = "Rock"
	rock.mesh = Kit._to_mesh(acc, Kit.materials("cave")["shell"])
	v.add_child(rock)
	# violet seams that only show after dark (or once a rumour told you where to look)
	var glow := MeshInstance3D.new()
	glow.name = "Glow"
	var bm := BoxMesh.new()
	bm.size = Vector3(0.12, 2.6, 0.1)
	glow.mesh = bm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.8, 0.45, 1.0)
	gm.emission_enabled = true
	gm.emission = Color(0.8, 0.45, 1.0)
	gm.emission_energy_multiplier = 2.4
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.material_override = gm
	glow.position = Vector3(0.1, 1.7, 1.0)
	glow.rotation.z = 0.25
	glow.visible = false
	v.add_child(glow)
	var l := OmniLight3D.new()
	l.light_color = Color(0.8, 0.45, 1.0)
	l.omni_range = 7.0
	l.light_energy = 0.0
	l.name = "Light"
	l.position = Vector3(0, 1.8, 1.6)
	v.add_child(l)
	var body := StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	var bs := BoxShape3D.new()
	bs.size = Vector3(4.8, 3.6, 1.0)
	cs.shape = bs
	cs.position = Vector3(0, 1.8, 0.4)
	body.add_child(cs)
	v.add_child(body)
	v.position = Vector3(0, 0, 0.9)
	root.add_child(v)


func _reveal_thing(root: Node3D, s: Dictionary, rkind: String, at: Vector3) -> void:
	var t := Thing.new()
	t.name = "reveal_%s" % rkind
	root.add_child(t)
	t.setup("reveal", {"id": "reveal", "rkind": rkind, "site": String(s["cave"]["dungeon_id"])}, self, String(s["cave"]["theme"]), 2.6)
	t.position = at
