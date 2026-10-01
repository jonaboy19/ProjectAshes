extends Node3D
## Region 1 look-dev presenter (docs/regions/LOOK_R1.md). Added once by RegionDressing._ready (Region1 look hook).
## Gives bodies to the landmarks in data/region1/landmarks.json and to the terrain stamps:
##   * landmark parts: big pieces (skyline, >= FAR_SIZE m) are built at boot and stay, with their LOD1 out to
##     2.5 km, so the Hollin Watch tower, the Drowned Bell or the windmills read from far away; small parts,
##     scatter and lights are streamed within NEAR of the player;
##   * cliff kits: warm limestone rocks laid on the stamped cliff faces (Region1Terrain.face), batched in
##     MultiMesh cells;
##   * waterfalls: a ribbon that hugs the real cliff profile, a plunge pool and foam;
##   * the far horizon (Region1Horizon): low-res terrain + canopy blobs beyond the streamed ring.
## Per-frame cost: a 0.5 s timer (streaming check over a handful of landmarks) plus windmill sails.

const Landmarks := preload("res://scripts/region1/region1_landmarks.gd")
const Horizon := preload("res://scripts/region1/region1_horizon.gd")
const FREE := "res://assets/incoming/meshy_free/"
const R1 := "res://assets/incoming/region1/"
const REGION := "res://assets/generated/region/"
const NEAR := 420.0
const NEAR_FREE := 520.0
const FAR_SIZE := 7.5
const FAR_END := 2600.0
const ROCK_NEAR := 260.0
const BIOME := "res://assets/incoming/region1/terrain/biome_map.png"

var focus := Vector3.ZERO
var horizon: Node3D
var _data: Dictionary = {}
var _near: Dictionary = {}          # landmark id -> Node3D (streamed)
var _sails: Array[Node3D] = []
var _timer := 0.0
var _water_mat: Material
var _fall_mat: ShaderMaterial


func _ready() -> void:
	name = "Region1Look"
	# QA A/B switches (look_capture.gd): --r1off drops the whole presenter, --r1nohorizon only the far horizon.
	var qa := OS.get_cmdline_user_args()
	if qa.has("--r1off"):
		set_process(false)
		return
	var t0 := Time.get_ticks_msec()
	_data = Landmarks.data()
	for lm: Dictionary in _data.get("landmarks", []):
		var far := Node3D.new()
		far.name = String(lm["id"]) + "_far"
		add_child(far)
		_build_parts(far, lm, true)
		for wf: Dictionary in lm.get("waterfalls", []):
			_build_waterfall(far, wf)
	for kit: Dictionary in _data.get("cliff_kits", []):
		_build_cliffs(kit)
	if not qa.has("--r1nohorizon"):
		horizon = Horizon.new()
		add_child(horizon)
	_apply_biome()
	print("Region1Look: %d landmarks, built in %d ms" % [_data.get("landmarks", []).size(), Time.get_ticks_msec() - t0])


func _process(delta: float) -> void:
	var p := get_parent()
	if p and "focus" in p:
		focus = p.focus
	for s in _sails:
		if is_instance_valid(s):
			s.rotate_object_local(Vector3.BACK, delta * 0.45)
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.5
	update_now()


## Builds / frees the near parts of every landmark around `focus` (also used by capture tools).
func update_now() -> void:
	var f := Vector2(focus.x, focus.z)
	for lm: Dictionary in _data.get("landmarks", []):
		var id := String(lm["id"])
		var d := f.distance_to(_v2(lm["pos"]))
		var reach := float(lm.get("near", NEAR))
		if d < reach and not _near.has(id):
			var root := Node3D.new()
			root.name = id + "_near"
			add_child(root)
			_build_parts(root, lm, false)
			_build_scatter(root, lm)
			_build_lights(root, lm)
			_near[id] = root
		elif d > reach + (NEAR_FREE - NEAR) and _near.has(id):
			var n: Node3D = _near[id]
			_near.erase(id)
			_sails = _sails.filter(func(x: Node3D) -> bool: return is_instance_valid(x) and not n.is_ancestor_of(x))
			n.queue_free()


static func _v2(a: Array) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))


## The baked biome map (tools_qa/region1/bake_biome.gd) drives terrain tints and the farmland patchwork in
## shaders/terrain.gdshader (via shaders/region1/biome.gdshaderinc) and on the far horizon.
func _apply_biome() -> void:
	if not ResourceLoader.exists(BIOME):
		return
	var tex := load(BIOME) as Texture2D
	var w := get_parent()
	while w != null:
		for ch in w.get_children():
			if ch is TerrainStreamer:
				var m: ShaderMaterial = ch.get("_ground_material")
				if m:
					m.set_shader_parameter("region_biome", tex)
		w = w.get_parent()
	if horizon:
		horizon.set("biome", tex)


# --- Assets --------------------------------------------------------------------

## "free:cat/name" -> meshy_free, "r1:dir/name" -> region1 kits, "gen:farm/windmill" -> generated/region,
## "nature:oak_a" -> region nature, or a res:// path. Returns [lod0, lod1 or ""].
static func asset_paths(a: String) -> Array:
	var p0 := ""
	var p1 := ""
	if a.begins_with("free:"):
		p0 = FREE + a.substr(5) + "_lod0.glb"
		p1 = FREE + a.substr(5) + "_lod1.glb"
	elif a.begins_with("r1:"):
		p0 = R1 + a.substr(3) + "_lod0.glb"
		p1 = R1 + a.substr(3) + "_lod1.glb"
		if not ResourceLoader.exists(p0):
			p0 = R1 + a.substr(3) + ".glb"
	elif a.begins_with("gen:"):
		p0 = REGION + a.substr(4) + ".glb"
		p1 = REGION + a.substr(4) + "_lod1.glb"
	elif a.begins_with("nature:"):
		p0 = REGION + "nature/" + a.substr(7) + ".glb"
		p1 = REGION + "nature/" + a.substr(7) + "_lod1.glb"
	else:
		p0 = a
	return [p0, p1 if p1 != "" and ResourceLoader.exists(p1) else ""]


## A part's model fitted to `h` metres tall (or scaled by `s`), LOD0 -> LOD1 by distance. Returns [node, height].
func _model(a: String, h: float, s: float) -> Array:
	var paths := asset_paths(a)
	if not ResourceLoader.exists(paths[0]):
		push_warning("Region1Look: missing " + paths[0])
		return [null, 0.0]
	var nature := a.begins_with("nature:")
	var near: Node3D = Assets.scene(paths[0]).instantiate() if nature else Assets.static_model(paths[0])
	var box := Assets.visual_aabb(near)
	var k := s
	if h > 0.0:
		k = h / maxf(box.size.y, 0.01)
	var holder := Node3D.new()
	holder.add_child(near)
	var size := box.size.length() * k
	var far_end := 160.0 if size < 3.0 else (600.0 if size < FAR_SIZE else FAR_END)
	var swap := clampf(size * 9.0, 40.0, 140.0)
	if paths[1] != "":
		var far: Node3D = Assets.scene(paths[1]).instantiate() if nature else Assets.static_model(paths[1])
		holder.add_child(far)
		_ranges(near, 0.0, swap)
		_ranges(far, swap, far_end)
	else:
		_ranges(near, 0.0, far_end)
	if nature:
		for mi in holder.find_children("*", "MeshInstance3D", true, false):
			var mesh := (mi as MeshInstance3D).mesh as ArrayMesh
			if mesh:
				Assets._region_materials(mesh, "region/nature/" + a.substr(7))
	if size < 2.5:
		_no_shadow(holder)
	holder.scale = Vector3.ONE * k
	return [holder, box.size.y * k, box, k]


func _ranges(n: Node, begin: float, end: float) -> void:
	if n is GeometryInstance3D:
		var g := n as GeometryInstance3D
		g.visibility_range_begin = begin
		g.visibility_range_begin_margin = 4.0 if begin > 0.0 else 0.0
		g.visibility_range_end = end
		g.visibility_range_end_margin = 8.0
		g.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	for ch in n.get_children():
		_ranges(ch, begin, end)


func _no_shadow(n: Node) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for ch in n.get_children():
		_no_shadow(ch)


# --- Parts ---------------------------------------------------------------------

## Part: {a, at: [x, z] (landmark-local, rotated by the landmark yaw), yaw (deg), h (fit height m) | s (scale),
##        y (m above ground), sink (m), abs_y (absolute height), water (sit on the water level), tilt: [x, z] deg,
##        collide, far (force skyline), near (force streamed)}
func _build_parts(root: Node3D, lm: Dictionary, far_pass: bool) -> void:
	var c := _v2(lm["pos"])
	var lyaw := deg_to_rad(float(lm.get("yaw", 0.0)))
	for part: Dictionary in lm.get("parts", []):
		var is_far := bool(part.get("far", float(part.get("h", 0.0)) >= FAR_SIZE)) and not bool(part.get("near", false))
		if is_far != far_pass:
			continue
		if part.has("w"):
			# "w": absolute world [x, z] (only meaningful for landmarks with yaw 0).
			part = part.duplicate()
			var wv := _v2(part["w"]) - c
			part["at"] = [wv.x, wv.y]
		for rep in _repeats(part):
			_place(root, c, lyaw, rep)


## A part may repeat along a row or ring: "row": {n, step: [dx, dz]} / "ring": {n, r, face_in}.
static func _repeats(part: Dictionary) -> Array:
	if part.has("row"):
		var out := []
		var row: Dictionary = part["row"]
		var st := _v2(row["step"])
		for i in int(row["n"]):
			var p := part.duplicate()
			var at := _v2(part.get("at", [0, 0])) + st * i
			p["at"] = [at.x, at.y]
			var hsh := fposmod(sin(i * 12.9898) * 43758.5453, 1.0)
			p["yaw"] = float(part.get("yaw", 0.0)) + float(row.get("jitter", 0.0)) * (hsh - 0.5) * 2.0
			p["seed"] = i
			out.append(p)
		return out
	if part.has("ring"):
		var out := []
		var ring: Dictionary = part["ring"]
		var n := int(ring["n"])
		var ctr := _v2(part.get("at", [0, 0]))
		for i in n:
			var ang := TAU * i / n + deg_to_rad(float(ring.get("start", 0.0)))
			var p := part.duplicate()
			var at := ctr + Vector2(cos(ang), sin(ang)) * float(ring["r"])
			p["at"] = [at.x, at.y]
			p["yaw"] = rad_to_deg(atan2(-cos(ang), -sin(ang))) + float(part.get("yaw", 0.0)) if bool(ring.get("face_in", true)) else float(part.get("yaw", 0.0))
			p["seed"] = i
			out.append(p)
		return out
	return [part]


func _place(root: Node3D, c: Vector2, lyaw: float, part: Dictionary) -> void:
	var m := _model(String(part["a"]), float(part.get("h", 0.0)), float(part.get("s", 1.0)))
	var n: Node3D = m[0]
	if n == null:
		return
	var local := _v2(part.get("at", [0, 0])).rotated(-lyaw)
	var w := c + local
	var yaw := lyaw + deg_to_rad(float(part.get("yaw", 0.0)))
	var y: float
	if part.has("abs_y"):
		y = float(part["abs_y"])
	elif bool(part.get("water", false)):
		var lv := WorldGen.water_level_at(w.x, w.y)
		y = lv if not is_nan(lv) else WorldGen.height(w.x, w.y)
	else:
		var box: AABB = m[2]
		var k: float = m[3]
		var fp := Vector2(box.size.x, box.size.z) * k
		if bool(part.get("nudge", false)):     # opt-in (data/region1/landmarks.json): never for pieces of a composition
			w = _flat_spot(w, yaw, fp, box.size.y * k)
		y = _footprint_ground(w, yaw, fp)
	y += float(part.get("y", 0.0)) - float(part.get("sink", 0.0))
	root.add_child(n)
	n.global_position = Vector3(w.x, y, w.y)
	if OS.get_cmdline_user_args().has("--r1debug"):
		print("[r1look] %s at %s y=%.1f h=%.1f" % [part["a"], w.round(), y, float(m[1])])
	n.rotation = Vector3(deg_to_rad(float(part.get("tilt", [0, 0])[0])), yaw, deg_to_rad(float(part.get("tilt", [0, 0])[1])))
	if bool(part.get("collide", false)):
		_collider(n, m[2])
	if String(part["a"]) == "gen:farm/windmill":
		_add_sails(n)


## A part whose footprint straddles a drop (other world seeds move the terrain under these fixed coordinates: the lowest-corner
## snap then buries it) steps to the nearest ground within 10 m that is flat enough; otherwise it stays (world lint).
static func _flat_spot(w: Vector2, yaw: float, size: Vector2, height: float) -> Vector2:
	if size.x * size.y < 4.0:
		return w
	var limit := maxf(0.8, height * 0.3)
	if _footprint_spread(w, yaw, size) <= limit:
		return w
	var best := w
	var best_spread := INF
	for r: float in [2.0, 4.0, 6.0, 8.0, 10.0]:
		for i in 8:
			var q := w + Vector2.from_angle(TAU * i / 8.0) * r
			var sp := _footprint_spread(q, yaw, size)
			if sp < best_spread:
				best_spread = sp
				best = q
		if best_spread <= limit:
			break
	return best if best_spread < _footprint_spread(w, yaw, size) else w


static func _footprint_spread(w: Vector2, yaw: float, size: Vector2) -> float:
	var h0 := WorldGen.height(w.x, w.y)
	var lo := h0
	var hi := h0
	for cx: float in [-0.4, 0.4]:
		for cz: float in [-0.4, 0.4]:
			var q := w + Vector2(size.x * cx, size.y * cz).rotated(-yaw)
			var h := WorldGen.height(q.x, q.y)
			lo = minf(lo, h)
			hi = maxf(hi, h)
	return hi - lo


## Lowest ground under the part's footprint (so nothing floats on a slope).
static func _footprint_ground(w: Vector2, yaw: float, size: Vector2) -> float:
	var lo := WorldGen.height(w.x, w.y)
	if size.x * size.y < 4.0:
		return lo - 0.03
	for cx: float in [-0.4, 0.4]:
		for cz: float in [-0.4, 0.4]:
			var q := w + Vector2(size.x * cx, size.y * cz).rotated(-yaw)
			lo = minf(lo, WorldGen.height(q.x, q.y))
	return lo - 0.08


func _collider(n: Node3D, box: AABB) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(box.size.x * 0.8, box.size.y, box.size.z * 0.8)
	shape.shape = b
	shape.position = box.get_center()
	body.add_child(shape)
	# The holder is scaled; put the body on the unscaled model child so the box matches the mesh.
	(n.get_child(0) as Node3D).add_child(body)


func _add_sails(mill: Node3D) -> void:
	var paths := asset_paths("gen:farm/windmill_sails")
	if not ResourceLoader.exists(paths[0]):
		return
	var sails: Node3D = Assets.static_model(paths[0])
	var model := mill.get_child(0)
	var hub := model.find_child("sail_hub", true, false) as Node3D
	if hub:
		hub.add_child(sails)
	else:
		model.add_child(sails)
		sails.position = Vector3(0, 10.1, 2.95)
	_ranges(sails, 0.0, FAR_END)
	_sails.append(sails)


# --- Scatter and lights ----------------------------------------------------------

## Scatter: {kind (Assets.nature_mesh key), n, r, r0, at, s: [min, max], end}. One MultiMesh per entry.
func _build_scatter(root: Node3D, lm: Dictionary) -> void:
	var c := _v2(lm["pos"])
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(lm["id"]))
	for sc: Dictionary in lm.get("scatter", []):
		var mesh := Assets.nature_mesh(String(sc["kind"]))
		if mesh == null:
			continue
		var ctr := _v2(sc["w"]) if sc.has("w") else c + _v2(sc.get("at", [0, 0])).rotated(-deg_to_rad(float(lm.get("yaw", 0.0))))
		var r := float(sc.get("r", 20.0))
		var r0 := float(sc.get("r0", 0.0))
		var smin := float(sc.get("s", [0.8, 1.3])[0])
		var smax := float(sc.get("s", [0.8, 1.3])[1])
		var list: Array[Transform3D] = []
		for i in int(sc.get("n", 60)):
			var a := rng.randf() * TAU
			var d := sqrt(rng.randf_range((r0 / r) * (r0 / r), 1.0)) * r
			var q := ctr + Vector2(cos(a), sin(a)) * d
			if WorldGen.is_water(q.x, q.y) and not bool(sc.get("wet", false)):
				continue
			var s := rng.randf_range(smin, smax)
			list.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(q.x, WorldGen.height(q.x, q.y) - 0.04, q.y)))
		if list.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = float(sc.get("end", 140.0))
		mmi.visibility_range_end_margin = 10.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		root.add_child(mmi)


## Lights: {at: [x, z], y, color, range}. Lamps join "street_lamp", so main.gd lights them only at night.
func _build_lights(root: Node3D, lm: Dictionary) -> void:
	var c := _v2(lm["pos"])
	var lyaw := deg_to_rad(float(lm.get("yaw", 0.0)))
	for l: Dictionary in lm.get("lights", []):
		var w := _v2(l["w"]) if l.has("w") else c + _v2(l["at"]).rotated(-lyaw)
		var light := OmniLight3D.new()
		light.light_color = Color(String(l.get("color", "ffb35c")))
		light.omni_range = float(l.get("range", 9.0))
		light.light_energy = 0.0
		light.shadow_enabled = false
		light.add_to_group("street_lamp")
		root.add_child(light)
		var base := WorldGen.water_level_at(w.x, w.y) if bool(l.get("water", false)) else WorldGen.height(w.x, w.y)
		if is_nan(base):
			base = WorldGen.height(w.x, w.y)
		light.global_position = Vector3(w.x, base + float(l.get("y", 2.5)), w.y)


# --- Cliff kits -------------------------------------------------------------------

## Rocks on every stamped cliff face: {rocks: [[asset, weight], ...], step, min_h, max_h, seed}.
func _build_cliffs(kit: Dictionary) -> void:
	var rocks: Array = kit["rocks"]
	var meshes: Array[Mesh] = []
	var heights: Array[float] = []
	var weights: Array[float] = []
	var total := 0.0
	for r: Array in rocks:
		var paths := asset_paths(String(r[0]))
		if not ResourceLoader.exists(paths[0]):
			continue
		var mi := Assets.static_model(paths[0]) as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		meshes.append(mi.mesh)
		heights.append(maxf(mi.mesh.get_aabb().size.y, 0.1))
		weights.append(float(r[1]))
		total += float(r[1])
		mi.free()
	if meshes.is_empty():
		return
	var lumps: Array[Mesh] = []
	for m in meshes:
		lumps.append(_lump(m.get_aabb(), Color("8a755c")))
	var qn := get_node_or_null("/root/Quality")
	var low := qn != null and int(qn.get("view_radius")) <= 2
	var rng := RandomNumberGenerator.new()
	rng.seed = int(kit.get("seed", 7))
	var step := float(kit.get("step", 8.0))
	var cell := 96.0
	var cells: Dictionary = {}       # Vector2i -> Array (per mesh) of Transform3D
	var count := 0
	for e: Dictionary in Region1Terrain._stamps:
		var z := float(e["z0"]) + step
		while z < float(e["z1"]) - step:
			var x := float(e["x0"]) + step
			while x < float(e["x1"]) - step:
				var px := x + rng.randf_range(-0.45, 0.45) * step
				var pz := z + rng.randf_range(-0.45, 0.45) * step
				var f := Region1Terrain.face(px, pz)
				if f > 0.5 and rng.randf() < f * 1.2 * float(kit.get("density", 1.0)):
					var pick := rng.randf() * total
					var mi := 0
					while mi < weights.size() - 1 and pick > weights[mi]:
						pick -= weights[mi]
						mi += 1
					var target := lerpf(float(kit.get("min_h", 6.0)), float(kit.get("max_h", 15.0)), rng.randf()) * lerpf(0.7, 1.0, f)
					var k := target / heights[mi]
					var gx := WorldGen.height(px + 2.0, pz) - WorldGen.height(px - 2.0, pz)
					var gz := WorldGen.height(px, pz + 2.0) - WorldGen.height(px, pz - 2.0)
					var yaw := atan2(-gx, -gz) + rng.randf_range(-0.6, 0.6)
					var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, rng.randf_range(-0.2, 0.2)) * Basis(Vector3.FORWARD, rng.randf_range(-0.15, 0.15))
					basis = basis * Basis.from_scale(Vector3(k * rng.randf_range(1.0, 1.6), k, k * rng.randf_range(0.55, 0.85)))
					# Push the rock into the slope (uphill) so it reads as the cliff itself, not a stone stuck on grass.
					var up := Vector2(gx, gz).normalized() * target * float(kit.get("embed", 0.3))
					var pos := Vector3(px + up.x, mesh_floor(px + up.x, pz + up.y, target * 0.2, 2.0) - target * 0.08, pz + up.y)
					# No rock on a road: its footprint (the mesh box at the rock's scale) keeps clear of the road's half-width (world lint).
					if WorldGen.road_distance(pos.x, pos.z) < 14.0:
						var bs := basis.get_scale()
						var ab := meshes[mi].get_aabb().size
						var reach := 0.5 * maxf(ab.x * bs.x, ab.z * bs.z) * 1.15 + 0.4
						var ri := WorldGen.road_info(pos.x, pos.z)
						if float(ri["dist"]) < float(ri["width"]) * 0.5 + reach:
							x += step
							continue
					var key := Vector2i(floori(px / cell), floori(pz / cell))
					if not cells.has(key):
						var arrs := []
						for _m in meshes.size():
							arrs.append([] as Array[Transform3D])
						cells[key] = arrs
					(cells[key][mi] as Array[Transform3D]).append(Transform3D(basis, pos))
					count += 1
				x += step
			z += step
	for key: Vector2i in cells:
		for mi in meshes.size():
			var list: Array[Transform3D] = cells[key][mi]
			if list.is_empty():
				continue
			# Full rock (1.5-2.5k tris) near; past ROCK_NEAR a 48-tri painted lump that fills the same box.
			for lod in (1 if low else 2):
				var mm := MultiMesh.new()
				mm.transform_format = MultiMesh.TRANSFORM_3D
				mm.mesh = meshes[mi] if lod == 0 else lumps[mi]
				mm.instance_count = list.size()
				for i in list.size():
					mm.set_instance_transform(i, list[i])
				var mmi := MultiMeshInstance3D.new()
				mmi.name = "Cliffs_%d_%d_%d_%d" % [key.x, key.y, mi, lod]
				mmi.multimesh = mm
				if lod == 0:
					mmi.visibility_range_end = 320.0 if low else ROCK_NEAR   # LOW: rocks only near (triangle budget 300k)
				else:
					mmi.visibility_range_begin = ROCK_NEAR
					mmi.visibility_range_end = float(kit.get("end", 1600.0))
				mmi.visibility_range_end_margin = 20.0
				if low or lod == 1:
					mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				add_child(mmi)
	var tri_note := ""
	for mi in meshes.size():
		tri_note += " %d" % (meshes[mi].get_faces().size() / 3)
	print("Region1Look: %d cliff rocks in %d cells (tris per rock:%s)" % [count, cells.size(), tri_note])


## A low-poly lump (8 x 4 sphere, 48 tris) filling `box`, painted warm stone: the far stand-in for a cliff rock.
static func _lump(box: AABB, col: Color) -> Mesh:
	var sm := SphereMesh.new()
	sm.radial_segments = 8
	sm.rings = 4
	sm.radius = 0.5
	sm.height = 1.0
	var st := SurfaceTool.new()
	st.append_from(sm, 0, Transform3D(Basis.from_scale(box.size * Vector3(0.85, 0.8, 0.85)), box.get_center()))
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = 0.95
	var out := st.commit()
	out.surface_set_material(0, mat)
	return out


## Lowest height of the rendered terrain around (x, z) within `r` m: the streamed mesh is a 2 m grid (4 m past
## 110 m), so on a sheer wall it runs well below WorldGen.height() between vertices. Rocks placed on the exact height
## floated in front of steep walls; seating them on the lowest grid vertex of their footprint buries them instead.
static func mesh_floor(x: float, z: float, r: float, g := 4.0) -> float:
	var lo := INF
	var x0 := floorf((x - r) / g) * g
	var z0 := floorf((z - r) / g) * g
	var gz := z0
	while gz <= z + r + g:
		var gx := x0
		while gx <= x + r + g:
			lo = minf(lo, WorldGen.height(gx, gz))
			gx += g
		gz += g
	return lo


# --- Waterfalls ---------------------------------------------------------------------

## {at: [x, z] (foot of the falls), dir: [x, z] (toward the cliff), width, pool_r, reach}
func _build_waterfall(root: Node3D, wf: Dictionary) -> void:
	var base := _v2(wf["at"])
	var dir := _v2(wf["dir"]).normalized()
	var side := Vector2(-dir.y, dir.x)
	var width := float(wf.get("width", 7.0))
	var reach := float(wf.get("reach", 90.0))
	# Walk up the cliff: the ribbon hugs the ground 0.9 m proud of it, from the lip back down to the pool.
	var prof: Array[Vector3] = []
	var t := 0.0
	var lip := -1.0
	var hmax := -INF
	while t <= reach:
		var q := base + dir * t
		var h := WorldGen.height(q.x, q.y)
		prof.append(Vector3(q.x, h, q.y))
		if h > hmax + 0.05:
			hmax = h
			lip = t
		t += 1.0
	var level := WorldGen.water_level_at(base.x, base.y)
	if is_nan(level):
		level = WorldGen.height(base.x, base.y) + 0.3
	var top := int(lip) + int(wf.get("over", 10))
	top = mini(top, prof.size() - 1)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var along := 0.0
	var prev := Vector3.INF
	var rows: Array = []
	for i in range(top, -1, -1):
		var p: Vector3 = prof[i]
		var out := -dir * (0.9 + clampf((p.y - level) * 0.02, 0.0, 1.2))
		var y := maxf(p.y + 0.35, level + 0.05)
		var pos := Vector3(p.x + out.x, y, p.z + out.y)
		if prev != Vector3.INF:
			along += pos.distance_to(prev)
		prev = pos
		var wk := lerpf(0.75, 1.25, clampf(float(top - i) / maxf(top, 1), 0.0, 1.0))
		rows.append([pos, along, width * wk])
		if y <= level + 0.06 and i < lip:
			break
	for r in rows.size() - 1:
		var a: Array = rows[r]
		var b: Array = rows[r + 1]
		var pa: Vector3 = a[0]
		var pb: Vector3 = b[0]
		var sa := Vector3(side.x, 0, side.y) * float(a[2]) * 0.5
		var sb := Vector3(side.x, 0, side.y) * float(b[2]) * 0.5
		var verts := [pa - sa, pa + sa, pb - sb, pb + sb]
		var uvs := [Vector2(0, a[1]), Vector2(1, a[1]), Vector2(0, b[1]), Vector2(1, b[1])]
		for idx in [0, 1, 2, 1, 3, 2]:
			st.set_uv(uvs[idx] / Vector2(1.0, width))
			st.set_normal(Vector3(-dir.x, 0.4, -dir.y).normalized())
			st.add_vertex(verts[idx])
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.name = "Waterfall"
	mi.mesh = mesh
	mi.material_override = _falls_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = FAR_END
	root.add_child(mi)
	# Plunge pool: a still disc on the river level, the game's own water material when it can be found.
	var pool_r := float(wf.get("pool_r", 11.0))
	var disc := CylinderMesh.new()
	disc.top_radius = pool_r
	disc.bottom_radius = pool_r
	disc.height = 0.05
	disc.radial_segments = 28
	disc.rings = 1
	var pool := MeshInstance3D.new()
	pool.name = "PlungePool"
	pool.mesh = disc
	pool.material_override = _pool_material()
	pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(pool)
	var pc := base + dir * float(wf.get("pool_off", 6.0))
	pool.global_position = Vector3(pc.x, level + 0.02, pc.y)
	# Foam where the water lands.
	var foam := MeshInstance3D.new()
	foam.name = "FallsFoam"
	var fm := SphereMesh.new()
	fm.radius = 1.0
	fm.height = 0.9
	fm.radial_segments = 12
	fm.rings = 5
	foam.mesh = fm
	foam.material_override = _falls_material()
	foam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(foam)
	var landing: Vector3 = rows[rows.size() - 1][0]
	foam.global_position = Vector3(landing.x, level, landing.z)
	foam.scale = Vector3(width * 0.8, 1.6, width * 0.5)


func _falls_material() -> ShaderMaterial:
	if _fall_mat == null:
		_fall_mat = ShaderMaterial.new()
		_fall_mat.shader = preload("res://shaders/region1/waterfall.gdshader")
	return _fall_mat


func _pool_material() -> Material:
	var w := get_parent()
	while w != null:
		for ch in w.get_children():
			if ch is WaterStreamer and ch.get("_material") != null:
				return ch.get("_material")
		w = w.get_parent()
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.25, 0.55, 0.7, 0.85)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.1
	return m
