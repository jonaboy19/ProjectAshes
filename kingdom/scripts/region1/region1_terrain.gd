class_name Region1Terrain
extends RefCounted
## Region 1 terrain features as DATA (docs/regions/LOOK_R1.md, data/region1/terrain_stamps.json):
##   * height stamps: baked delta grids (Image FORMAT_RGBAF .res: R = metres added to the ground,
##     G = terrace tread hint, B = share of trees kept, A = rock-face mask) added at the very end of WorldGen.height(), so
##     rivers, lakes, settlements and roads underneath keep their own layout (a stamp that leaves
##     the floor at 0 never moves the river). Baked by tools_qa/region1/bake_valley.gd.
##   * trails: polylines painted as packed dirt through WorldGen.color_at().
##
## Hooks (3 lines in world_gen.gd, each commented "Region1 look hook"):
##   WorldGen.setup():  Region1Terrain.setup()          (main thread, before any chunk worker)
##   WorldGen.height(): return Region1Terrain.stamp(x, z, h)
##   WorldGen.color_at(): return Region1Terrain.paint(x, z, w)
## Read-only after setup(), so the chunk workers can call it from any thread.
## Cost: two float compares per call outside a stamp's box; one bilinear fetch inside.

const INDEX := "res://data/region1/terrain_stamps.json"

## Tools switch this off to sample the untouched terrain (bake_valley.gd).
static var enabled := true
## [{x0, z0, x1, z1, cell, nx, nz, d: PackedFloat32Array (RGBA interleaved)}]
static var _stamps: Array[Dictionary] = []
## [{pts: PackedVector2Array, half: float, box: Rect2, soft: float}]
static var _trails: Array[Dictionary] = []
static var _box := Rect2()
## Riverside groves (pass 3): extra woodland share on the Hollin's Reach floor, kept off trails and landmark clearings.
static var _groves: Array[Dictionary] = []      # [{box: Rect2, noise: FastNoiseLite, amount, shore: [in, out]}]
static var _keep_clear: Array[Vector3] = []     # (x, z, radius)


static func setup() -> void:
	_stamps.clear()
	_trails.clear()
	_box = Rect2()
	_groves.clear()
	_keep_clear.clear()
	if not enabled or not FileAccess.file_exists(INDEX) or OS.get_cmdline_user_args().has("--r1off"):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(INDEX))
	if not data is Dictionary:
		return
	for st: Dictionary in data.get("stamps", []):
		var path := String(st.get("file", ""))
		if not ResourceLoader.exists(path):
			continue
		var img := load(path) as Image
		if img == null or img.get_format() != Image.FORMAT_RGBAF:
			continue
		var o: Array = st["origin"]
		var cell := float(st["cell"])
		var e := {"x0": float(o[0]), "z0": float(o[1]), "cell": cell, "nx": img.get_width(), "nz": img.get_height(),
			"d": img.get_data().to_float32_array()}
		e["x1"] = e["x0"] + cell * (e["nx"] - 1)
		e["z1"] = e["z0"] + cell * (e["nz"] - 1)
		_stamps.append(e)
	for gv: Dictionary in data.get("groves", []):
		var b: Array = gv["box"]
		var nz := FastNoiseLite.new()
		nz.seed = int(gv.get("seed", 5))
		nz.frequency = float(gv.get("frequency", 0.03))
		nz.fractal_octaves = 2
		_groves.append({"box": Rect2(float(b[0]), float(b[1]), float(b[2]) - float(b[0]), float(b[3]) - float(b[1])), "noise": nz,
			"amount": float(gv.get("amount", 0.8)), "shore": gv.get("shore", [5.0, 45.0])})
	for kc: Array in data.get("keep_clear", []):
		_keep_clear.append(Vector3(float(kc[0]), float(kc[1]), float(kc[2])))
	for tr: Dictionary in data.get("trails", []):
		var pts := PackedVector2Array()
		for p: Array in tr["points"]:
			pts.append(Vector2(float(p[0]), float(p[1])))
		if pts.size() < 2:
			continue
		var half := float(tr.get("width", 2.4)) * 0.5
		var box := Rect2(pts[0], Vector2.ZERO)
		for p in pts:
			box = box.expand(p)
		box = box.grow(half + 3.0)
		_trails.append({"pts": pts, "half": half, "box": box, "soft": float(tr.get("soft", 1.4))})
		_box = box if _box.size == Vector2.ZERO else _box.merge(box)


## Ground height with every stamp applied (called last in WorldGen.height()).
static func stamp(x: float, z: float, h: float) -> float:
	for e: Dictionary in _stamps:
		if x <= e["x0"] or z <= e["z0"] or x >= e["x1"] or z >= e["z1"]:
			continue
		h += _sample(e, x, z, 0)
	return h


## 0..1 share of trees allowed at (x, z): 0 on stamped cliff faces (trees floated off the steep
## faces where the far ground LOD and the trunk height disagree), 1 elsewhere.
static func tree_keep(x: float, z: float) -> float:
	for e: Dictionary in _stamps:
		if x <= e["x0"] or z <= e["z0"] or x >= e["x1"] or z >= e["z1"]:
			continue
		return clampf(_sample(e, x, z, 2), 0.0, 1.0)
	return 1.0


## WorldGen.forest_density hook (pass 3): natural woodland `f`, plus riverside groves in the valleys, minus cliff faces.
static func forest(x: float, z: float, f: float) -> float:
	var p := Vector2(x, z)
	for g: Dictionary in _groves:
		if not (g["box"] as Rect2).has_point(p):
			continue
		var sh: Array = g["shore"]
		var sd := WorldGen.shore_distance(x, z)
		if sd < float(sh[0]) or sd > float(sh[1]) + 15.0:
			continue
		var k := smoothstep(float(sh[0]), float(sh[0]) + 6.0, sd) * (1.0 - smoothstep(float(sh[1]), float(sh[1]) + 15.0, sd))
		var gv := float(g["amount"]) * smoothstep(-0.15, 0.35, (g["noise"] as FastNoiseLite).get_noise_2d(x, z)) * k
		if gv <= f:
			continue
		for c: Vector3 in _keep_clear:
			var dd := p.distance_to(Vector2(c.x, c.y))
			if dd < c.z + 10.0:
				gv *= smoothstep(c.z, c.z + 10.0, dd)
		gv *= 1.0 - _trail_k(p)
		f = maxf(f, gv)
	return f * tree_keep(x, z) if f > 0.0 else f


static func _trail_k(p: Vector2) -> float:
	if _trails.is_empty() or not _box.has_point(p):
		return 0.0
	var k := 0.0
	for tr: Dictionary in _trails:
		if not (tr["box"] as Rect2).has_point(p):
			continue
		var pts: PackedVector2Array = tr["pts"]
		for i in pts.size() - 1:
			var a := pts[i]
			var ab := pts[i + 1] - a
			var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
			var d := p.distance_to(a + ab * t)
			k = maxf(k, 1.0 - smoothstep(float(tr["half"]) + 1.0, float(tr["half"]) + 5.0, d))
	return k


## Height of the RENDERED near ground (the streamed 2 m grid split on the b-c diagonal) at (x, z). Scatter placed on the
## exact WorldGen.height floats where the mesh cuts corners on steep ground (pass 3 float check); worker-thread safe.
static func mesh_ground(x: float, z: float) -> float:
	var ix := floorf(x * 0.5)
	var iz := floorf(z * 0.5)
	var fx := x * 0.5 - ix
	var fz := z * 0.5 - iz
	var x0 := ix * 2.0
	var z0 := iz * 2.0
	var hb := WorldGen.height(x0 + 2.0, z0)
	var hc := WorldGen.height(x0, z0 + 2.0)
	if fx + fz <= 1.0:
		var ha := WorldGen.height(x0, z0)
		return ha + (hb - ha) * fx + (hc - ha) * fz
	var hd := WorldGen.height(x0 + 2.0, z0 + 2.0)
	return hd + (hc - hd) * (1.0 - fx) + (hb - hd) * (1.0 - fz)


## Rock-face mask (0..1) of the stamp at (x, z): where Region1Look lays cliff rocks.
static func face(x: float, z: float) -> float:
	for e: Dictionary in _stamps:
		if x <= e["x0"] or z <= e["z0"] or x >= e["x1"] or z >= e["z1"]:
			continue
		return _sample(e, x, z, 3)
	return 0.0


## Paint hint (0..1) of the stamp at (x, z): terrace treads, field strips.
static func hint(x: float, z: float) -> float:
	for e: Dictionary in _stamps:
		if x <= e["x0"] or z <= e["z0"] or x >= e["x1"] or z >= e["z1"]:
			continue
		return _sample(e, x, z, 1)
	return 0.0


static func _sample(e: Dictionary, x: float, z: float, ch: int) -> float:
	var cell: float = e["cell"]
	var fx := (x - float(e["x0"])) / cell
	var fz := (z - float(e["z0"])) / cell
	var nx: int = e["nx"]
	var ix := mini(int(fx), nx - 2)
	var iz := mini(int(fz), int(e["nz"]) - 2)
	var tx := fx - ix
	var tz := fz - iz
	var d: PackedFloat32Array = e["d"]
	var i := (iz * nx + ix) * 4 + ch
	var a := lerpf(d[i], d[i + 4], tx)
	var b := lerpf(d[i + nx * 4], d[i + nx * 4 + 4], tx)
	return lerpf(a, b, tz)


## Material weights (see WorldGen.color_at: R path, G rock, B cobble, A forest floor) with the
## Region 1 trails painted in as packed dirt and terrace risers kept as rock.
static func paint(x: float, z: float, w: Color) -> Color:
	# Cliff faces read as stone, never as a steep lawn (the rock kit sits on top of this).
	var fc := face(x, z)
	if fc > 0.12:
		var k := smoothstep(0.12, 0.4, fc)
		w.g = maxf(w.g, k)
		w.a *= 1.0 - k
		w.r *= 1.0 - k
	if _trails.is_empty() or not _box.has_point(Vector2(x, z)):
		return w
	var p := Vector2(x, z)
	for tr: Dictionary in _trails:
		if not (tr["box"] as Rect2).has_point(p):
			continue
		var pts: PackedVector2Array = tr["pts"]
		var best := INF
		for i in pts.size() - 1:
			var a := pts[i]
			var ab := pts[i + 1] - a
			var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
			best = minf(best, p.distance_squared_to(a + ab * t))
		var half: float = tr["half"]
		var dd := sqrt(best)
		if dd < half + float(tr["soft"]):
			var k := 1.0 - smoothstep(half - 0.6, half + float(tr["soft"]), dd)
			w.r = maxf(w.r, k * 0.9)
			w.a *= 1.0 - k
	return w
