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
## Region 1 world packages (C1 C2 C10): extra asset keys "free:<cat>/<name>@<h>" (incoming/meshy_free) and
## "r1:<dir>/<name>@<h>" (incoming/region1), and bodies that are not meshes (signs, named NPCs, doors).
const Extras := preload("res://scripts/world/region1_extras.gd")
const FREE_PACK := "res://assets/incoming/meshy_free/"
const R1 := "res://assets/incoming/region1/"
const R1_KIT := "res://assets/incoming/region1/highwatch/highwatch_kit.tres"
const R1_KIT_LOW := "res://assets/incoming/region1/highwatch/highwatch_kit_low.tres"
const BRIDGE_DECK := {"road/bridge_stone": [2.6, 12.0], "road/bridge_wood": [1.6, 14.0]}

var focus := Vector3.ZERO
var _built: Dictionary = {}          # site id -> Node3D
var _sails: Array[Node3D] = []
var _flicker: Array[OmniLight3D] = []
var _timer := 0.0
var _t := 0.0

## Hitch-free streaming: a site's parts used to be loaded from disk and instanced
## in one frame (50-66 ms spikes when a farmstead came within BUILD). Now every
## site asset is loaded once while the game is still booting (Assets.scene keeps
## it for the session), and parts are built from a queue within BUILD_BUDGET_MS
## per frame.
##
## NOT on a loader thread: load_threaded_request() of these GLBs was THE random
## 0xC0000005 crash (~1 in 8 boots, 2026-09-28). A worker thread loading a mesh
## runs ArrayMesh::_set_surfaces -> BaseMaterial3D shader update, which touches
## the engine's shared material/shader HashSet while the main thread creates
## StandardMaterial3Ds (flat materials, VFX, region materials) -> torn hash table.
## (Found with WinDbg on the crash dumps: HashSet::_insert <- material shader
## update <- mesh.cpp _set_surfaces <- resource loader, on "WorkerThread N".)
## Rule for this project: never threaded-load anything that carries materials.
const BUILD_BUDGET_MS := 2.0
var _queue: Array = []               # [root, site, kind, index] work items


func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	var n := 0
	var paths: Array = [REGION + "farm/windmill_sails.glb", REGION + "road/bridge_stone.glb", REGION + "road/bridge_wood.glb"]
	var seen_assets := {}     # a few hundred sites share a few dozen assets: resolve each asset once
	for site in WorldGen.sites:
		for part: Array in site.get("parts", []):
			var asset := String(part[0])
			if not seen_assets.has(asset):
				seen_assets[asset] = true
				paths.append_array(_paths(asset))
	for path: String in paths:
		if path != "" and ResourceLoader.exists(path) and Assets.scene(path) != null:
			n += 1
	print("RegionDressing: preloaded %d region scenes in %d ms (main thread)" % [n, Time.get_ticks_msec() - t0])
	# Region1 look hook (docs/regions/LOOK_R1.md): landmark bodies, cliff rocks, waterfalls and the far horizon.
	add_child(preload("res://scripts/region1/region1_look.gd").new())
	add_child(preload("res://scripts/world/exploration_director.gd").new())   # Hidden valley hook: the vale, its cutscene and the exploration POIs
	# Region1 world hook (docs/regions/REGION_1_PLAN.md C11): creature dens, Stagborn herds, bandit rosters (placement only).
	add_child(preload("res://scripts/world/region1_creatures.gd").new())
	# Caves hook (scripts/world/region_caves.gd): walk-in doors for the planned cave, mine, hideout and crypt sites.
	add_child(preload("res://scripts/world/region_caves_view.gd").new())


## Every file is loaded at boot now, so any part can be built right away.
func _ready_to_spawn(_asset: String) -> bool:
	return true


## The GLB paths _spawn will load for an asset key (LOD0 and LOD1).
func _paths(asset: String) -> Array:
	if asset.begins_with("free:") or asset.begins_with("r1:"):
		return []      # loaded when a site is built: hundreds of baked textures must not sit in VRAM from boot
	if asset.begins_with("meshy:"):
		var n := asset.substr(6).split("@")[0]
		return [MESHY + n + "_lod0.glb", MESHY + n + "_lod1.glb"]
	if asset.begins_with("nature:"):
		var nm := asset.substr(7)
		return [REGION + "nature/" + nm + ".glb", REGION + "nature/" + nm + "_lod1.glb"]
	if asset.begins_with("gen:"):
		var gn := asset.substr(4).split("@")[0]
		return [GEN + gn + ".glb", GEN + gn + "_lod1.glb"]
	if asset.begins_with("props/"):
		return [GEN + asset + ".glb"]
	return [REGION + asset + ".glb", REGION + asset + "_lod1.glb"]


## Builds queued site parts until the frame budget is spent.
func _drain_queue() -> void:
	var t0 := Time.get_ticks_usec()
	while not _queue.is_empty() and Time.get_ticks_usec() - t0 < BUILD_BUDGET_MS * 1000.0:
		var item: Array = _queue[0]
		# Variant first: assigning a freed Node to a typed var is a SCRIPT ERROR every frame.
		var root_v: Variant = item[0]
		if not is_instance_valid(root_v):
			_queue.pop_front()
			continue
		var root: Node3D = root_v
		var site: Dictionary = item[1]
		if item[2] == "part":
			var part: Array = site["parts"][item[3]]
			if not _ready_to_spawn(String(part[0])):
				return          # still loading from disk: try again next frame
			_build_part(root, site, part)
		else:
			_build_light(root, site["lights"][item[3]])
		_queue.pop_front()


var dbg_usec := 0      # QA: total _process time (usec) and frames, read by tools/qa/water_shots/water_prof.gd
var dbg_frames := 0


func _process(delta: float) -> void:
	var _t0 := Time.get_ticks_usec()
	_process_inner(delta)
	dbg_usec += Time.get_ticks_usec() - _t0
	dbg_frames += 1


func _process_inner(delta: float) -> void:
	Breakable.tick(delta)   # breakable props: melee sweep + regrowth (once per frame)
	_drain_queue()
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
		if not _in_season(site):
			d = INF      # seasonal pieces (the Solkar caravans) exist only in their season
		if d < BUILD and not _built.has(id):
			_built[id] = _build(site)
		elif d > FREE and _built.has(id):
			var n: Node3D = _built[id]
			_built.erase(id)
			if is_instance_valid(n):
				n.queue_free()
			_sails = _sails.filter(func(x: Node3D) -> bool: return is_instance_valid(x) and not n.is_ancestor_of(x))
			_flicker = _flicker.filter(func(x: OmniLight3D) -> bool: return is_instance_valid(x) and not n.is_ancestor_of(x))


## Builds every site at once (screenshots, tests, teleports): blocks on purpose.
func build_all_now() -> void:
	for site in WorldGen.sites:
		if not _built.has(site["id"]) and _in_season(site):
			_built[site["id"]] = _build(site)
	while not _queue.is_empty():
		var item: Array = _queue.pop_front()
		if not is_instance_valid(item[0]):
			continue
		if item[2] == "part":
			_build_part(item[0], item[1], item[1]["parts"][item[3]])
		else:
			_build_light(item[0], item[1]["lights"][item[3]])


## Sites may name a season ("season": "summer"); everything else is always there.
func _in_season(site: Dictionary) -> bool:
	if not site.has("season"):
		return true
	var ws := get_node_or_null("/root/WorldSim")
	return ws != null and String(ws.get("season")) == String(site["season"])


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
	if site["kind"] == "rift":
		VFX.rift(root, root.global_position + Vector3.UP * 0.2, 6.0, 0.0)   # freed with the site
	if site["kind"] == "bridge":
		_build_bridge(root, site)
		return root
	_scatter_ground(root, site)
	# Parts and lights are queued and built a few per frame (see _drain_queue).
	for i in site["parts"].size():
		_queue.append([root, site, "part", i])
	for i in site["lights"].size():
		_queue.append([root, site, "light", i])
	if site.has("x"):
		Extras.build(root, site)
	return root


func _build_part(root: Node3D, site: Dictionary, part: Array) -> void:
	var basis := Basis(Vector3.UP, float(site["yaw"]))
	var off: Vector2 = part[1]
	var world := root.global_position + basis * Vector3(off.x, 0.0, off.y)
	var n := _spawn(String(part[0]))
	if n == null:
		return
	root.add_child(n)
	n.rotation.y = float(part[2])
	# Settle on the lowest ground under the footprint so nothing floats on a slope.
	var box := Assets.visual_aabb(n)
	var ground := _footprint_ground(world, basis * Basis(Vector3.UP, float(part[2])), box)
	n.global_position = Vector3(world.x, ground + (float(part[4]) if part.size() > 4 else 0.0), world.z)
	var prop := String(part[0]).trim_prefix("props/")
	if String(part[0]).begins_with("props/") and Breakable.is_breakable(prop):
		var b: StaticBody3D = Breakable.new()   # barrels, crates, sacks: smashable, always solid
		b.setup_node(n, box, prop)
		n.add_child(b)
	elif bool(part[3]):
		_collider(n, box)
	if String(part[0]) == "farm/windmill":
		_add_sails(n)
	if not String(part[0]).begins_with("props/"):
		_base_clutter(root, world, basis * Basis(Vector3.UP, float(part[2])), box)


func _build_light(root: Node3D, l: Array) -> void:
	var basis := root.global_transform.basis
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


## A couple of small stones or weeds tucked against a farm/mine/camp building's
## base, matching WorldGen.color_at()'s new dirt ring around every site clearing
## (see world_gen.gd). Skipped for small props (crates, barrels...); only worth
## it for building-sized footprints. Sites are few, so plain child nodes (no
## MultiMesh batching) are cheap enough.
func _base_clutter(root: Node3D, world: Vector3, basis: Basis, box: AABB) -> void:
	if box.size.x * box.size.z < 3.0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2(world.x, world.z))
	var hug := maxf(box.size.x, box.size.z) * 0.5 + 0.3
	for k in 2:
		var ang := rng.randf() * TAU
		var at := world + basis * (Vector3(cos(ang), 0, sin(ang)) * hug)
		var picks: Array[String] = ["rock_medium", "flowers_warm", "fern_b", "bush_round"]
		var kind: String = "region/nature/" + picks[rng.randi() % picks.size()]
		var mesh := Assets.nature_mesh(kind)
		if mesh == null:
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
		mi.rotation.y = rng.randf() * TAU
		mi.global_position = Vector3(at.x, WorldGen.height(at.x, at.z) - 0.03, at.z)


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
	if asset.begins_with("free:") or asset.begins_with("r1:"):
		return _spawn_kit(asset)
	if asset.begins_with("meshy:"):
		var spec := asset.substr(6).split("@")
		var target := float(spec[1]) if spec.size() > 1 else 4.0
		var n := _lod_pair(MESHY + spec[0] + "_lod0.glb", MESHY + spec[0] + "_lod1.glb", 90.0, target)
		if n == null:
			return null
		var box := Assets.visual_aabb(n)
		var k := target / maxf(box.size.y, 0.01)
		# Round 2: far stages for hero pieces that ship lod2/lod3 (3.5-7k / ~1k tris) so a
		# landmark seen from a kilometre away no longer draws its 20k+ tri lod1.
		var l2 := MESHY + spec[0] + "_lod2.glb"
		var l3 := MESHY + spec[0] + "_lod3.glb"
		if ResourceLoader.exists(l2) and n.get_child_count() > 1:
			var stage_end := 400.0 if ResourceLoader.exists(l3) else 0.0
			_ranges(n.get_child(1), 90.0, 200.0)
			var m2 := Assets.static_model(l2)
			n.add_child(m2)
			_ranges(m2, 200.0, stage_end if stage_end > 0.0 else 600.0)
			if stage_end > 0.0:
				var m3 := Assets.static_model(l3)
				n.add_child(m3)
				_ranges(m3, stage_end, 600.0)
		var holder := Node3D.new()
		holder.add_child(n)
		n.scale = Vector3.ONE * k
		n.position.y = -box.position.y * k
		return holder
	if asset.begins_with("gen:"):
		# A big building from assets/generated at a uniform scale (castle keep, temple, chapel...).
		var gspec := asset.substr(4).split("@")
		var gn := _lod_pair(GEN + gspec[0] + ".glb", GEN + gspec[0] + "_lod1.glb", 110.0)
		if gn == null:
			return null
		var gholder := Node3D.new()
		gholder.add_child(gn)
		gn.scale = Vector3.ONE * (float(gspec[1]) if gspec.size() > 1 else 1.0)
		return gholder
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


## "free:market/stall_apples@3.2" (Meshy free pack) or "r1:stones/elder_stone" (the local session's Region 1 kits):
## LOD0 and LOD1 pair, fitted to @H metres tall when given (else natural size), standing on its own base.
## The Highwatch kit ships without textures: its atlas material goes on every mesh.
func _spawn_kit(asset: String) -> Node3D:
	var is_free := asset.begins_with("free:")
	var spec := asset.substr(5 if is_free else 3).split("@")
	var base := (FREE_PACK if is_free else R1) + spec[0]
	var lod0 := base + "_lod0.glb"
	var lod1 := base + "_lod1.glb"
	if not ResourceLoader.exists(lod0):
		lod0 = base + ".glb"
		lod1 = ""
	var target := float(spec[1]) if spec.size() > 1 else 0.0
	var n := _lod_pair(lod0, lod1, 55.0 if target < 6.0 else 85.0, target)
	if n == null:
		return null
	var box := Assets.visual_aabb(n)
	var k := target / maxf(box.size.y, 0.01) if target > 0.0 else 1.0
	if spec[0].begins_with("highwatch/"):
		var low := int(Quality.tier) <= 1
		var mat := load(R1_KIT_LOW if low else R1_KIT) as Material
		if mat != null:
			for mi in n.find_children("*", "MeshInstance3D", true, false):
				(mi as MeshInstance3D).material_override = mat
	var holder := Node3D.new()
	holder.add_child(n)
	n.scale = Vector3.ONE * k
	n.position.y = -box.position.y * k
	return holder


## `fit_height` > 0: the piece is later scaled to that height (Meshy landmarks import at
## ~2 m and are scaled x4-9), so its cull ranges and shadow rule must use the SCALED size.
## Before this a 9 m guild hall counted as a 2.4 m prop: cut off at 120 m, no shadows.
func _lod_pair(lod0: String, lod1: String, dist: float, fit_height := 0.0) -> Node3D:
	if not ResourceLoader.exists(lod0):
		return null
	var holder := Node3D.new()
	# One merged MeshInstance3D per part (draw calls = materials) except wind-shaded nature.
	var merge := not lod0.contains("/nature/")
	var near: Node3D = Assets.static_model(lod0) if merge else Assets.scene(lod0).instantiate()
	holder.add_child(near)
	var raw := Assets.visual_aabb(near)
	var extent := raw.size.length()
	if fit_height > 0.0:
		extent *= fit_height / maxf(raw.size.y, 0.01)
	var far_end := 120.0 if extent < 3.0 else (260.0 if extent < 10.0 else 600.0)
	if dist > 0.0 and lod1 != "" and ResourceLoader.exists(lod1):
		var far: Node3D = Assets.static_model(lod1) if merge else Assets.scene(lod1).instantiate()
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


## Kinds of ground dressing per site: flowers, tufts, ferns, stones and bushes strewn
## through the worn-dirt ring so a fort, camp or farm never sits on a bare brown disc
## (art style: nothing on bare flat ground). One MultiMesh per kind per site.
const SCATTER_KINDS := ["nature/flowers_a", "nature/grass_clump_tall", "region/nature/flowers_warm",
	"region/nature/flowers_cool", "region/nature/fern_b", "region/nature/rock_medium", "region/nature/bush_round"]
const SCATTER_SKIP := ["bridge", "waystone", "wayshrine", "rift"]


func _scatter_ground(root: Node3D, site: Dictionary) -> void:
	var clear: float = site["clear"]
	if clear < 12.0 or String(site["kind"]) in SCATTER_SKIP:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(site["id"]) + "scatter")
	var c: Vector2 = site["pos"]
	var basis := Basis(Vector3.UP, float(site["yaw"]))
	var lists: Array = []
	for k in SCATTER_KINDS.size():
		lists.append([] as Array[Transform3D])
	var count := int(clear * 2.4)
	for i in count:
		var a := rng.randf() * TAU
		var r := clear * sqrt(rng.randf_range(0.08, 1.15))
		var q := c + Vector2(cos(a), sin(a)) * r
		if WorldGen.is_water(q.x, q.y) or WorldGen.road_distance(q.x, q.y) < 3.0:
			continue
		var blocked := false
		for part: Array in site["parts"]:
			var off: Vector2 = part[1]
			var w := c + Vector2((basis * Vector3(off.x, 0, off.y)).x, (basis * Vector3(off.x, 0, off.y)).z)
			if q.distance_to(w) < 2.6:
				blocked = true
				break
		if blocked:
			continue
		var k := rng.randi() % SCATTER_KINDS.size()
		var sc := rng.randf_range(0.8, 1.4) * (0.75 if k == 6 else 1.0)
		(lists[k] as Array[Transform3D]).append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * sc),
			Vector3(q.x, WorldGen.height(q.x, q.y) - 0.04, q.y)))
	for k in SCATTER_KINDS.size():
		var list: Array[Transform3D] = lists[k]
		if list.is_empty():
			continue
		var mesh := Assets.nature_mesh(SCATTER_KINDS[k])
		if mesh == null:
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.top_level = true
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = 110.0
		mmi.visibility_range_end_margin = 10.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		root.add_child(mmi)
