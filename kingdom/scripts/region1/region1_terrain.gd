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


static func setup() -> void:
	_stamps.clear()
	_trails.clear()
	_box = Rect2()
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
