class_name RealSlice
extends Node3D
## Benchmark slice countryside route (docs/plans/BENCHMARK_SLICE.md item 5) on the real-world terrain: AUTHORED, not scattered.
## Data: data/world/real/slice_route.json. Ashford's east edge -> worn footpath -> a dry-stone field wall with a stile and nettles,
## ferns and flowers clustered along its foot -> the Waymark Stone on the knoll (view to the snowy fells) -> a recognisable copse
## with a clearing (bare soil, a mossy log) -> the bandit camp on the Kingsreach road.
##   static setup()      (WorldGen._relocate_real): paints the footpath and bare-soil patches into the ground (Region1Terrain trails).
##   static in_corridor  procedural dressing (RealInstancer trees/undergrowth, field walls) keeps out of the route so only authored
##                       things stand there.
##   node _ready         builds the walls, wall-foot plants, the copse, clearing props and the stone (a few MultiMeshes + scenes).

const DATA := "res://data/world/real/slice_route.json"
const NATURE := "res://assets/generated/region/nature/"

static var _d: Dictionary = {}
static var _path := PackedVector2Array()
static var _corridor := 14.0
static var _copse_c := Vector2.INF
static var _copse_r := 0.0
static var _box := Rect2()


static func _load() -> void:
	if not _d.is_empty() or not FileAccess.file_exists(DATA) or OS.get_cmdline_user_args().has("--slice_off"):   # --slice_off: before/after A/B
		return
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	if not v is Dictionary:
		return
	_d = v
	_path = _pts(_d["path"]["points"])
	_corridor = float(_d.get("corridor_m", 14.0))
	_copse_c = Vector2(float(_d["copse"]["centre"][0]), float(_d["copse"]["centre"][1]))
	_copse_r = float(_d["copse"]["radius"])
	_box = Rect2(_path[0], Vector2.ZERO)
	for p in _path:
		_box = _box.expand(p)
	_box = _box.expand(_copse_c).grow(_copse_r + _corridor + 40.0)
	for w: Dictionary in _d["walls"]:
		for p in _pts(w["points"]):
			_box = _box.expand(p)


static func _pts(a: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Array in a:
		out.append(Vector2(float(p[0]), float(p[1])))
	return out


## WorldGen._relocate_real: footpath + bare soil into the ground paint. Real world only.
static func setup() -> void:
	_load()
	if _d.is_empty():
		return
	Region1Terrain.add_trail(_path, float(_d["path"]["width"]), float(_d["path"].get("soft", 1.6)))
	for b: Array in _d["bare_soil"]:
		var c := Vector2(float(b[0]), float(b[1]))
		Region1Terrain.add_trail(PackedVector2Array([c - Vector2(0.01, 0), c + Vector2(0.01, 0)]), float(b[2]) * 2.0, 2.4)


## True near the authored route (footpath corridor, the copse, the walls): procedural dressing stays out. Thread-safe after setup().
static func in_corridor(x: float, z: float, extra := 0.0) -> bool:
	if _d.is_empty() or not _box.has_point(Vector2(x, z)):
		return false
	var p := Vector2(x, z)
	if p.distance_to(_copse_c) < _copse_r + extra:
		return true
	for i in _path.size() - 1:
		if p.distance_to(Geometry2D.get_closest_point_to_segment(p, _path[i], _path[i + 1])) < _corridor + extra:
			return true
	for w: Dictionary in _d["walls"]:
		var wp := _pts(w["points"])
		for i in wp.size() - 1:
			if p.distance_to(Geometry2D.get_closest_point_to_segment(p, wp[i], wp[i + 1])) < 6.0 + extra:
				return true
	return false


# --- the authored props -------------------------------------------------------------------------------------------------

var _rng := RandomNumberGenerator.new()
var _plants: Dictionary = {}   # glb name -> Array[Transform3D]


func _ready() -> void:
	name = "RealSlice"
	_load()
	if _d.is_empty() or not RealWorld.active():
		return
	_rng.seed = 2610
	var wall_mesh: Mesh = preload("res://scripts/world/real_landmarks.gd")._drystone_mesh()
	var wall_ts: Array[Transform3D] = []
	for w: Dictionary in _d["walls"]:
		_wall(_pts(w["points"]), Vector2(float(w["gap_at"][0]), float(w["gap_at"][1])), float(w.get("gap", 0.0)), wall_ts)
	_mmi(wall_mesh, wall_ts, 700.0)
	_road()
	_verges()
	_tree_belt()
	_copse()
	_stone()
	for k: String in _plants:
		_mmi_scene(k, _plants[k], 260.0)


func _ground(p: Vector2) -> float:
	return WorldGen.height(p.x, p.y)


## One wall along a polyline: 4 m dry-stone segments following the ground, a stile gap where the footpath crosses (`gap` m half
## width; 0 = the wall simply starts/ends there), and plants clustered at its foot on both sides.
func _wall(pts: PackedVector2Array, gap_at: Vector2, gap: float, out: Array[Transform3D]) -> void:
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var dir := (b - a).normalized()
		var side := dir.orthogonal()
		var steps := int(a.distance_to(b) / 4.0)
		for s in steps:
			var p := a + dir * (s * 4.0 + 2.0)
			if gap > 0.0 and p.distance_to(gap_at) < gap + 2.0:
				continue
			var h := _ground(p)
			var yaw := -atan2(dir.y, dir.x)
			var pitch := atan2(_ground(p + dir * 2.0) - _ground(p - dir * 2.0), 4.0)
			out.append(Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, pitch), Vector3(p.x, h - 0.08, p.y)))
			# wall-foot clusters: nettles/ferns/tall grass hug the stones, flowers and hazel a little further out
			for sd in [-1.0, 1.0]:
				if _rng.randf() < 0.75:
					var q: Vector2 = p + side * float(sd) * _rng.randf_range(0.7, 1.4) + dir * _rng.randf_range(-1.6, 1.6)
					_plant(["fern_a", "fern_b", "grass_tall", "grass_tall", "fern_b"][_rng.randi() % 5], q, _rng.randf_range(0.8, 1.3))
				if _rng.randf() < 0.22:
					var q2: Vector2 = p + side * float(sd) * _rng.randf_range(1.6, 3.0)
					_plant(["flowers_warm", "flowers_cool", "bush_hazel", "bush_berry"][_rng.randi() % 4], q2, _rng.randf_range(0.8, 1.2))


## Stylised region-set plants (blob bushes, cartoon ferns) are banned on the benchmark slice; only scans/generated assets.
const BANNED := ["bush_hazel", "bush_berry", "bush_dark", "bush_round", "fern_a", "fern_b", "grass_tall", "grass_a", "flowers_warm", "flowers_cool"]


func _plant(kind: String, p: Vector2, s: float) -> void:
	if kind in BANNED:
		return
	if not ResourceLoader.exists(NATURE + kind + ".glb") or WorldGen.road_distance(p.x, p.y) < 3.0:
		return
	if not _plants.has(kind):
		_plants[kind] = [] as Array[Transform3D]
	(_plants[kind] as Array).append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(p.x, _ground(p) - 0.05, p.y)))


const TRACKS := "res://assets/cc0/textures/muddy_tracks/muddy_tracks_"


## The worn road (ref 01): a ground-hugging ribbon along the footpath with the CC0 Poly Haven "muddy tracks" PBR set (cart ruts run
## along its length), its frayed edges blended into the painted trail below; a puddle in the dip by the stile.
func _road() -> void:
	var w := float(_d["path"].get("road_width", 3.0))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var dense := PackedVector2Array()
	for i in _path.size() - 1:
		var n := maxi(1, int(_path[i].distance_to(_path[i + 1]) / 1.5))
		for k in n:
			dense.append(_path[i].lerp(_path[i + 1], float(k) / n))
	dense.append(_path[_path.size() - 1])
	var v := 0.0
	var cols := 9                      # across the road, so the ribbon follows the camber of the ground
	for i in dense.size() - 1:
		var a := dense[i]
		var b := dense[i + 1]
		var side := (b - a).normalized().orthogonal()
		var seg := a.distance_to(b)
		for c in cols - 1:
			var quad: Array[Vector3] = []
			var uvs: Array[Vector2] = []
			for corner: Vector2i in [Vector2i(0, c), Vector2i(1, c), Vector2i(1, c + 1), Vector2i(0, c + 1)]:
				var base := a if corner.x == 0 else b
				var t := float(corner.y) / (cols - 1) - 0.5
				var q := base + side * t * w * (1.0 + 0.08 * sin(v * 0.21 + corner.y))
				quad.append(Vector3(q.x, WorldGen.height(q.x, q.y) + 0.14, q.y))
				uvs.append(Vector2(t + 0.5, (v + (seg if corner.x == 1 else 0.0)) / w))
			for idx in [0, 1, 2, 0, 2, 3]:
				var edge := absf(uvs[idx].x - 0.5) * 2.0
				st.set_color(Color(1, 1, 1, 1.0 - smoothstep(0.55, 1.0, edge)))
				st.set_uv(uvs[idx])
				st.add_vertex(quad[idx])
		v += seg
	st.generate_normals()
	st.generate_tangents()
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load("res://assets/incoming/polyhaven/textures/dirt/dirt_diff_2k.jpg")   # dusty grey-beige dirt (ref 01)
	mat.detail_enabled = false
	mat.normal_enabled = true
	mat.normal_texture = load(TRACKS + "nor_gl_2k.jpg")
	mat.roughness_texture = load(TRACKS + "arm_2k.jpg")
	mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(0.92, 0.88, 0.82)     # ruts come from the muddy_tracks normal map; the colour from Poly Haven dirt
	mat.normal_scale = 1.6
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	# puddle in the low spot of the road near the stile
	var pd: Array = _d.get("puddle", [214.0, 64.0, 1.6])
	var pp := Vector2(float(pd[0]), float(pd[1]))
	var pm := CylinderMesh.new()
	pm.top_radius = float(pd[2])
	pm.bottom_radius = float(pd[2])
	pm.height = 0.02
	pm.radial_segments = 14
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.22, 0.2, 0.17)
	wm.metallic = 0.6
	wm.roughness = 0.04
	pm.material = wm
	var pmi := MeshInstance3D.new()
	pmi.mesh = pm
	pmi.transform = Transform3D(Basis.from_scale(Vector3(1.0, 1.0, 0.6)) * Basis(Vector3.UP, 0.4), Vector3(pp.x, WorldGen.height(pp.x, pp.y) + 0.07, pp.y))
	add_child(pmi)


const PH := "res://assets/incoming/polyhaven/models/"
## Real-scan CC0 meadow (Poly Haven): [gltf, share, scale min, max, max distance from the road edge m]
## Scales: the scans are true size (bermuda tufts ~2 cm, medium tufts ~15 cm); the meadow of ref 01 is knee-to-waist high.
## v6 gate: the bermuda set is mostly dead/flattened tufts (read as brown scrub when scaled) and fern/nettle rendered near-black:
## the meadow body is the two green medium tufts; ferns/nettles stay rare accents near the walls.
const MEADOW := [["grass_medium_02/grass_medium_02_1k.gltf", 0.55, 3.2, 4.6, 9.0],
	["grass_medium_01/grass_medium_01_1k.gltf", 0.43, 3.0, 4.4, 8.0], ["fern_02/fern_02_1k.gltf", 0.025, 0.7, 1.1, 9.0],
	["nettle_plant/nettle_plant_1k.gltf", 0.015, 0.8, 1.1, 4.0], ["dandelion_01/dandelion_01_1k.gltf", 0.01, 1.0, 1.3, 3.0]]
const CHUNK_M := 24.0


## Dense continuous meadow from Poly Haven CC0 scans right up to the road edge (ref 01): every variant mesh of each gltf, MultiMesh
## chunks of CHUNK_M m along the road with a 70 m distance fade; a narrow trampled strip at the edge stays sparser. LOW / iGPU: 40 %.
func _meadow() -> void:
	var variants: Array = []          # [mesh, share, smin, smax, reach]
	for m: Array in MEADOW:
		if not ResourceLoader.exists(PH + String(m[0])):
			continue
		var inst := (load(PH + String(m[0])) as PackedScene).instantiate()
		var mis := inst.find_children("*", "MeshInstance3D", true, false)
		for mi: MeshInstance3D in mis:
			if String(mi.name).contains("dead") or String(mi.get_parent().name).contains("dead"):
				continue
			# Poly Haven scans carry their real size in the node transforms (the meshes are a few cm): keep the node basis
			var tb := Transform3D()
			var nd: Node = mi
			while nd != null and nd != inst:
				if nd is Node3D:
					tb = (nd as Node3D).transform * tb
				nd = nd.get_parent()
			var mesh: Mesh = mi.mesh.duplicate()
			for si in mesh.get_surface_count():
				var sm := mesh.surface_get_material(si)
				if sm is BaseMaterial3D:
					var nm := (sm as BaseMaterial3D).duplicate() as BaseMaterial3D
					nm.albedo_color = Color(0.82, 1.08, 0.62)      # ref 01 meadow: fresh mid-green, not straw
					nm.cull_mode = BaseMaterial3D.CULL_DISABLED
					mesh.surface_set_material(si, nm)
			variants.append([mesh, float(m[1]) / mis.size(), m[2], m[3], m[4], tb.basis])
		inst.free()
	if variants.is_empty():
		return
	var cum := PackedFloat32Array()
	var tot := 0.0
	for v: Array in variants:
		tot += float(v[1])
		cum.append(tot)
	var q: Node = Engine.get_main_loop().root.get_node_or_null("Quality") if Engine.get_main_loop() is SceneTree else null
	var dens := clampf(float(q.call("value", "scatter")) if q and q.has_method("value") else 1.0, 0.4, 1.0)
	var step := 0.5 / sqrt(dens)
	var w := float(_d["path"].get("road_width", 3.0)) * 0.5
	var buckets: Dictionary = {}       # Vector2i(variant, chunk) -> Array[Transform3D]
	var walked := 0.0
	for i in _path.size() - 1:
		var a := _path[i]
		var b := _path[i + 1]
		var dir := (b - a).normalized()
		var side := dir.orthogonal()
		var length := a.distance_to(b)
		var along := 0.0
		while along < length:
			for sd in [-1.0, 1.0]:
				var off := w - 0.3
				while off < w + 9.0:
					off += step * _rng.randf_range(0.6, 1.4)
					if off < w + 0.6 and _rng.randf() < 0.6:
						continue             # trampled strip along the road edge
					var r := _rng.randf() * tot
					var vi := cum.bsearch(r)
					var v: Array = variants[mini(vi, variants.size() - 1)]
					if off - w > float(v[4]):
						continue
					var p: Vector2 = a + dir * (along + _rng.randf_range(-step, step)) + side * float(sd) * off
					if WorldGen.road_distance(p.x, p.y) < 2.0:
						continue
					var s := _rng.randf_range(float(v[2]), float(v[3]))
					var key := Vector2i(mini(vi, variants.size() - 1), int((walked + along) / CHUNK_M))
					if not buckets.has(key):
						buckets[key] = [] as Array[Transform3D]
					(buckets[key] as Array).append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * s) * (v[5] as Basis), Vector3(p.x, _ground(p) - 0.03, p.y)))
			along += step
		walked += length
	for key: Vector2i in buckets:
		var ts: Array[Transform3D] = []
		ts.assign(buckets[key])
		_mmi((variants[key.x] as Array)[0], ts, 70.0)


## Soft tall-grass verges with flowers on both sides of the road (ref 01): a dense band, densest at the road edge, broken by gaps.
func _verges() -> void:
	_meadow()
	if true:
		return          # the clump verges below are replaced by the Poly Haven meadow (kept for A/B)
	var w := float(_d["path"].get("road_width", 3.0)) * 0.5
	for i in _path.size() - 1:
		var a := _path[i]
		var b := _path[i + 1]
		var dir := (b - a).normalized()
		var side := dir.orthogonal()
		var along := 0.0
		var length := a.distance_to(b)
		while along < length:
			for sd in [-1.0, 1.0]:
				var off := w + 0.2 + pow(_rng.randf(), 1.6) * 7.5
				var q: Vector2 = a + dir * (along + _rng.randf_range(-0.4, 0.4)) + side * float(sd) * off
				var r := _rng.randf()
				if r < 0.06:
					_plant(["flowers_warm", "flowers_cool"][_rng.randi() % 2], q, _rng.randf_range(0.8, 1.2))
				elif r < 0.14:
					_plant("grass_tall", q, _rng.randf_range(0.9, 1.3))
				else:
					_plant("grass_a", q, _rng.randf_range(1.2, 2.0))
			along += 0.55


## Tree masses (ref 01 "grouped tree masses"): a belt of trees and hazel along the north side of the long wall, densest in the middle.
func _tree_belt() -> void:
	for wb: Dictionary in _d.get("tree_belts", []):
		var pts := _pts(wb["points"])
		var depth := float(wb.get("depth", 14.0))
		for i in pts.size() - 1:
			var a := pts[i]
			var b := pts[i + 1]
			var dir := (b - a).normalized()
			var side := dir.orthogonal() * float(wb.get("side", -1.0))
			var along := 3.0
			while along < a.distance_to(b):
				var p := a + dir * along + side * _rng.randf_range(4.0, depth)
				_scene(["oak_a", "oak_b", "beech_a", "beech_b", "dark_oak"][_rng.randi() % 5], p, _rng.randf_range(1.3, 1.8), _rng.randf() * TAU)
				_scene(["bush_hazel", "bush_dark", "bush_round"][_rng.randi() % 3], p + side * _rng.randf_range(-3.0, -1.0), _rng.randf_range(1.0, 1.5), _rng.randf() * TAU)
				along += _rng.randf_range(5.0, 8.0)


## The copse: hand-placed trees (recognisable group), undergrowth inside, an open clearing with bare soil and a mossy log.
func _copse() -> void:
	var cl: Array = _d["copse"]["clearing"]
	var cc := Vector2(float(cl[0]), float(cl[1]))
	for t: Array in _d["copse"]["trees"]:
		var p := Vector2(float(t[1]), float(t[2]))
		_scene(String(t[0]), p, float(t[3]), _rng.randf() * TAU)
	for i in 40:
		var a := _rng.randf() * TAU
		var p := _copse_c + Vector2(cos(a), sin(a)) * _rng.randf_range(4.0, _copse_r)
		if p.distance_to(cc) < float(cl[2]) + 2.0:
			continue
		_scene(["fern_a", "fern_b", "bush_dark", "bush_hazel"][_rng.randi() % 4], p, _rng.randf_range(0.8, 1.2), _rng.randf() * TAU)
	for pr: Array in _d["clearing_props"]:
		_scene(String(pr[0]), Vector2(float(pr[1]), float(pr[2])), float(pr[3]), float(pr[4]))


## Broadleaf kinds -> the Blender-generated realistic trees (tools/blender_trees/make_trees.py: oak/ash/beech, Poly Haven bark,
## leaf-card atlas, LOD0/LOD1/LOD2 children) instead of the stylised region set (owner: no lollipop trees).
const SLICE_TREES := "res://assets/generated/slice_trees/"
const TREE_MAP := {"oak_a": "oak_0", "oak_b": "oak_1", "dark_oak": "oak_1", "beech_a": "beech_0", "beech_b": "beech_1", "young_oak": "ash_0"}


func _scene(kind: String, p: Vector2, s: float, yaw: float) -> void:
	if kind in BANNED:
		return
	var path := NATURE + kind + ".glb"
	var real_tree := TREE_MAP.has(kind) and ResourceLoader.exists(SLICE_TREES + String(TREE_MAP[kind]) + ".gltf")
	if real_tree:
		path = SLICE_TREES + String(TREE_MAP[kind]) + ".gltf"
		s *= 0.75 if kind != "young_oak" else 0.55       # generated trees are 14-17 m at scale 1
	if not ResourceLoader.exists(path):
		return
	var n := (load(path) as PackedScene).instantiate() as Node3D
	n.transform = Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s), Vector3(p.x, _ground(p) - 0.1, p.y))
	if real_tree:
		var ranges := {"LOD0": [0.0, 45.0], "LOD1": [45.0, 160.0], "LOD2": [160.0, 2500.0]}
		for gi in n.find_children("*", "GeometryInstance3D", true, false):
			for k: String in ranges:
				if String(gi.name).begins_with(k) or String(gi.get_parent().name).begins_with(k):
					(gi as GeometryInstance3D).visibility_range_begin = float(ranges[k][0])
					(gi as GeometryInstance3D).visibility_range_end = float(ranges[k][1])
	add_child(n)


## The Waymark Stone: a weathered standing stone on the knoll (the route's view point toward the fells).
func _stone() -> void:
	var lm: Dictionary = _d["landmark"]
	var p := Vector2(float(lm["at"][0]), float(lm["at"][1]))
	var hgt := float(lm["height"])
	var m := CylinderMesh.new()
	m.top_radius = 0.42
	m.bottom_radius = 0.7
	m.height = hgt
	m.radial_segments = 7
	m.rings = 3
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load("res://assets/incoming/polyhaven/textures/mossy_stone_wall/mossy_stone_wall_diff_2k.jpg")
	mat.uv1_triplanar = true
	mat.uv1_scale = Vector3(0.6, 0.6, 0.6)
	mat.roughness = 0.95
	mat.albedo_color = Color(0.78, 0.78, 0.76)
	m.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.transform = Transform3D(Basis(Vector3.FORWARD, 0.06) * Basis(Vector3.UP, 0.4), Vector3(p.x, _ground(p) + hgt * 0.45, p.y))
	add_child(mi)
	_scene("rock_cluster", p + Vector2(1.6, 0.8), 0.7, 1.1)
	for i in 10:
		var a := _rng.randf() * TAU
		_plant(["grass_tall", "flowers_cool", "fern_b"][i % 3], p + Vector2(cos(a), sin(a)) * _rng.randf_range(1.2, 3.5), _rng.randf_range(0.7, 1.0))


func _mmi(mesh: Mesh, ts: Array[Transform3D], range_end: float) -> void:
	if ts.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = ts.size()
	for i in ts.size():
		mm.set_instance_transform(i, ts[i])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.visibility_range_end = range_end
	mi.visibility_range_end_margin = range_end * 0.15
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(mi)


## A MultiMesh per plant kind from the glb's first mesh (materials ride on the mesh surfaces).
func _mmi_scene(kind: String, ts: Array, range_end: float) -> void:
	var inst := (load(NATURE + kind + ".glb") as PackedScene).instantiate()
	var mis := inst.find_children("*", "MeshInstance3D", true, false)
	if not mis.is_empty():
		var typed: Array[Transform3D] = []
		typed.assign(ts)
		_mmi((mis[0] as MeshInstance3D).mesh, typed, range_end)
	inst.free()
