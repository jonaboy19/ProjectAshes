class_name RegionDressing
extends Node3D
## Gives WorldGen.sites (planned by RegionSites) bodies near the player: every
## part is a region GLB with its LOD1 swapped in past LOD_DIST, snapped to the
## terrain, with a cheap box collider where it matters. Sites are built inside
## BUILD and freed past FREE, so the whole region costs nothing far away.
## Windmill sails turn, campfires and lanterns flicker, the Rift pulses.

const REGION := "res://assets/generated/region/"
const GEN := "res://assets/generated/"
const MESHY := "res://assets/incoming/ai3d/meshy/"
const BUILD := 240.0
const FREE := 330.0
const LOD_DIST := 55.0
const Breakable := preload("res://scripts/world/breakable.gd")
const BRIDGE_DECK := {"road/bridge_stone": [2.6, 12.0], "road/bridge_wood": [1.6, 14.0]}

var focus := Vector3.ZERO
var _built: Dictionary = {}          # site id -> Node3D
var _sails: Array[Node3D] = []
var _flicker: Array[OmniLight3D] = []
var _timer := 0.0
var _t := 0.0


func _process(delta: float) -> void:
	Breakable.tick(delta)   # breakable props: melee sweep + regrowth (once per frame)
	_t += delta
	for s in _sails:
		if is_instance_valid(s):
			s.rotate_object_local(Vector3.BACK, delta * 0.45)
	for i in _flicker.size():
		var l := _flicker[i]
		if is_instance_valid(l):
			var base: float = l.get_meta("base", 1.0)
			l.light_energy = base * (0.82 + 0.18 * sin(_t * 7.3 + i * 1.7) * sin(_t * 3.1 + i))
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.75
	var p := Vector2(focus.x, focus.z)
	for site in WorldGen.sites:
		var id: int = site["id"]
		var d := p.distance_to(site["pos"])
		if d < BUILD and not _built.has(id):
			_built[id] = _build(site)
		elif d > FREE and _built.has(id):
			var n: Node3D = _built[id]
			_built.erase(id)
			if is_instance_valid(n):
				n.queue_free()
			_sails = _sails.filter(func(x: Node3D) -> bool: return is_instance_valid(x) and not n.is_ancestor_of(x))
			_flicker = _flicker.filter(func(x: OmniLight3D) -> bool: return is_instance_valid(x) and not n.is_ancestor_of(x))


## Builds every site at once (screenshots, tests).
func build_all_now() -> void:
	for site in WorldGen.sites:
		if not _built.has(site["id"]):
			_built[site["id"]] = _build(site)


func built_count() -> int:
	return _built.size()


func _build(site: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = String(site["name"]).replace(" ", "") + str(site["id"])
	add_child(root)
	var c: Vector2 = site["pos"]
	var yaw: float = site["yaw"]
	root.global_position = Vector3(c.x, WorldGen.height(c.x, c.y), c.y)
	root.rotation.y = yaw
	if site["kind"] == "bridge":
		_build_bridge(root, site)
		return root
	var basis := Basis(Vector3.UP, yaw)
	for part: Array in site["parts"]:
		var off: Vector2 = part[1]
		var local := Vector3(off.x, 0.0, off.y)
		var world := root.global_position + basis * local
		var n := _spawn(String(part[0]))
		if n == null:
			continue
		root.add_child(n)
		n.rotation.y = float(part[2])
		# Settle on the lowest ground under the footprint so nothing floats on a slope.
		var box := Assets.visual_aabb(n)
		var ground := _footprint_ground(world, basis * Basis(Vector3.UP, float(part[2])), box)
		n.global_position = Vector3(world.x, ground, world.z)
		var prop := String(part[0]).trim_prefix("props/")
		if String(part[0]).begins_with("props/") and Breakable.is_breakable(prop):
			var b: StaticBody3D = Breakable.new()   # barrels, crates, sacks: smashable, always solid
			b.setup_node(n, box, prop)
			n.add_child(b)
		elif bool(part[3]):
			_collider(n, box)
		if String(part[0]) == "farm/windmill":
			_add_sails(n)
	for l: Array in site["lights"]:
		var light := OmniLight3D.new()
		light.light_color = l[1]
		light.omni_range = l[2]
		light.light_energy = 1.4
		light.shadow_enabled = false
		light.set_meta("base", 1.4)
		root.add_child(light)
		var lp: Vector3 = l[0]
		var at := root.global_position + basis * Vector3(lp.x, 0.0, lp.z)
		light.global_position = Vector3(at.x, WorldGen.height(at.x, at.z) + lp.y, at.z)
		if bool(l[3]):
			_flicker.append(light)
	return root


func _footprint_ground(world: Vector3, basis: Basis, box: AABB) -> float:
	var lowest := WorldGen.height(world.x, world.z)
	if box.size.x * box.size.z < 4.0:
		return lowest - 0.03
	for corner in [Vector3(box.position.x, 0, box.position.z), Vector3(box.end.x, 0, box.position.z),
			Vector3(box.position.x, 0, box.end.z), Vector3(box.end.x, 0, box.end.z)]:
		var q: Vector3 = world + basis * (corner * 0.8)
		lowest = minf(lowest, WorldGen.height(q.x, q.z))
	return lowest - 0.08


## "farm/barn" -> region set, "props/x" -> generated props, "nature:x" -> region
## nature (with its wind materials), "meshy:x@H" -> a Meshy landmark scaled to H m.
func _spawn(asset: String) -> Node3D:
	if asset.begins_with("meshy:"):
		var spec := asset.substr(6).split("@")
		var target := float(spec[1]) if spec.size() > 1 else 4.0
		var n := _lod_pair(MESHY + spec[0] + "_lod0.glb", MESHY + spec[0] + "_lod1.glb", 90.0)
		if n == null:
			return null
		var box := Assets.visual_aabb(n)
		var k := target / maxf(box.size.y, 0.01)
		var holder := Node3D.new()
		holder.add_child(n)
		n.scale = Vector3.ONE * k
		n.position.y = -box.position.y * k
		return holder
	if asset.begins_with("nature:"):
		var name := asset.substr(7)
		var nat := _lod_pair(REGION + "nature/" + name + ".glb", REGION + "nature/" + name + "_lod1.glb", LOD_DIST)
		if nat:
			# COLOR_0 on these is wind data, not colour: swap in the wind/AO materials
			# the terrain streamer uses (Assets._region_materials), or they render blue.
			for mi in nat.find_children("*", "MeshInstance3D", true, false):
				var mesh := (mi as MeshInstance3D).mesh as ArrayMesh
				if mesh:
					Assets._region_materials(mesh, "region/nature/" + name)
		return nat
	if asset.begins_with("props/"):
		return _lod_pair(GEN + asset + ".glb", "", 0.0)
	return _lod_pair(REGION + asset + ".glb", REGION + asset + "_lod1.glb", LOD_DIST)


func _lod_pair(lod0: String, lod1: String, dist: float) -> Node3D:
	if not ResourceLoader.exists(lod0):
		return null
	var holder := Node3D.new()
	var near: Node3D = (load(lod0) as PackedScene).instantiate()
	holder.add_child(near)
	var extent := Assets.visual_aabb(near).size.length()
	var far_end := 120.0 if extent < 3.0 else (260.0 if extent < 10.0 else 600.0)
	if dist > 0.0 and lod1 != "" and ResourceLoader.exists(lod1):
		var far: Node3D = (load(lod1) as PackedScene).instantiate()
		holder.add_child(far)
		_ranges(near, 0.0, dist)
		_ranges(far, dist, far_end)
	else:
		_ranges(near, 0.0, far_end)
	if extent < 2.5:
		_no_shadow(near)
	return holder


func _ranges(n: Node, begin: float, end: float) -> void:
	if n is GeometryInstance3D:
		var g := n as GeometryInstance3D
		g.visibility_range_begin = begin
		g.visibility_range_begin_margin = 3.0 if begin > 0.0 else 0.0
		g.visibility_range_end = end
		g.visibility_range_end_margin = 3.0
		g.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	for ch in n.get_children():
		_ranges(ch, begin, end)


func _no_shadow(n: Node) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for ch in n.get_children():
		_no_shadow(ch)


func _collider(n: Node3D, box: AABB) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(box.size.x * 0.85, box.size.y, box.size.z * 0.85)
	shape.shape = b
	shape.position = box.get_center()
	body.add_child(shape)
	n.add_child(body)


func _add_sails(mill: Node3D) -> void:
	var hub := mill.find_child("sail_hub", true, false) as Node3D
	var sails := _lod_pair(REGION + "farm/windmill_sails.glb", REGION + "farm/windmill_sails_lod1.glb", LOD_DIST)
	if sails == null:
		return
	if hub:
		hub.add_child(sails)
	else:
		mill.add_child(sails)
		sails.position = Vector3(0, 10.1, 2.95)
	_sails.append(sails)


## Bridge scaled along the road to span the wet stretch, deck flush with the
## higher bank, and a walkable deck collider.
func _build_bridge(root: Node3D, site: Dictionary) -> void:
	var asset: String = site["asset"]
	var n := _spawn(asset)
	if n == null:
		return
	var spec: Array = BRIDGE_DECK[asset]
	var deck: float = spec[0]
	var length_k := maxf(1.0, float(site["span"]) / float(spec[1]))
	root.add_child(n)
	n.scale = Vector3(1.0, 1.0, length_k)
	var top: float = site["deck"] + 0.1
	root.global_position.y = top - deck
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(3.0, 0.3, float(spec[1]) * length_k)
	shape.shape = b
	shape.position = Vector3(0, deck - 0.15, 0)
	body.add_child(shape)
	root.add_child(body)
