extends SceneTree
## W4: bakes the Region 1 landmark terrain stamps (Rift trench, Ashen Scar crater field, mine portals, Grimfen Pass cut) as delta grids.
## Same output format as bake_valley.gd (Image RGBAF .res: R metres added, G tread hint, B share of trees kept, A rock-face mask) and the same
## rule: the stamp is a DELTA on whatever ground is there, so it works on the legacy noise terrain and on the Valencious macro. Where the
## delta depends on the ground (a mine's bench) it is baked once per macro mode and the index entry carries "mode".
##   Godot --headless --path kingdom -s res://tools_qa/region1/bake_stamps.gd -- --mode=noise|valencious [--only=id,id] [--preview=<abs dir>]
##       [--design=res://data/region1/terrain/w4_designs.json]
## Prints one `STAMP_INDEX {...}` line per stamp; tools/region1/merge_stamp_index.py folds them into data/region1/terrain_stamps.json.
## Stamps never touch ground next to a planned site, a settlement or a road (they fade to 0 there), so pads and roads keep their shape.

var D: Dictionary
var mode := "noise"
var n_a := FastNoiseLite.new()
var n_b := FastNoiseLite.new()
var sites_near: Array = []          # [{p, r}] exclusion discs for the stamp being baked
var own: Array = []                 # positions of the sites that belong to the stamp (not excluded)


func _initialize() -> void:
	var design := "res://data/region1/terrain/w4_designs.json"
	var preview := ""
	var only: PackedStringArray = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--design="): design = a.substr(9)
		elif a.begins_with("--mode="): mode = a.substr(7)
		elif a.begins_with("--preview="): preview = a.substr(10)
		elif a.begins_with("--only="): only = a.substr(7).split(",", false)
	D = JSON.parse_string(FileAccess.get_file_as_string(design))
	Region1Terrain.skip_late = true         # sample the ground without the stamps being baked (the older stamps stay on: site planning depends on them)
	WorldMacro.override = mode
	n_a.seed = 411; n_a.frequency = 0.045; n_a.fractal_octaves = 3
	n_b.seed = 412; n_b.frequency = 0.011; n_b.fractal_octaves = 2
	WorldGen.setup(1066)
	print("bake mode=%s macro_active=%s sites=%d" % [mode, WorldMacro.active, WorldGen.sites.size()])
	for st: Dictionary in D["stamps"]:
		if not only.is_empty() and not (String(st["id"]) in only):
			continue
		_bake(st, preview)
	quit(0)


func _bake(st: Dictionary, preview: String) -> void:
	var M: Dictionary = st
	if st.has("modes"):
		if not (st["modes"] as Dictionary).has(mode):
			print("skip %s: no %s variant" % [st["id"], mode])
			return
		M = (st["modes"] as Dictionary)[mode]
	var ctx := _context(st, M)
	var box: Rect2 = ctx["box"]
	var cell := float(st.get("cell", 3.0))
	var x0 := snappedf(box.position.x, cell)
	var z0 := snappedf(box.position.y, cell)
	var nx := int(box.size.x / cell) + 1
	var nz := int(box.size.y / cell) + 1
	var buf := PackedFloat32Array()
	buf.resize(nx * nz * 4)
	var t0 := Time.get_ticks_msec()
	_exclusions(st, M, box)
	var maxd := 0.0
	var mind := 0.0
	for iz in nz:
		for ix in nx:
			var p := Vector2(x0 + ix * cell, z0 + iz * cell)
			var base := WorldGen.height(p.x, p.y)
			var r := _shape(st, M, ctx, p, base)
			var m := _mask(p, float(st.get("road_gap", 8.0)))
			r[0] *= m
			r[3] *= m
			r[2] = lerpf(1.0, r[2], m)
			var o4 := (iz * nx + ix) * 4
			buf[o4] = r[0]
			buf[o4 + 1] = r[1]
			buf[o4 + 2] = r[2]
			buf[o4 + 3] = minf(r[3], 0.45)     # < 0.5: the Region 1 cliff-rock kit (6-15 m limestone) is not laid on these faces
			maxd = maxf(maxd, r[0])
			mind = minf(mind, r[0])
	for iz in nz:                               # feather the window edge to zero: no seam
		for ix in nx:
			var e := mini(mini(ix, nx - 1 - ix), mini(iz, nz - 1 - iz))
			if e < 6:
				buf[(iz * nx + ix) * 4] *= e / 6.0
	var id := "%s_%s" % [st["id"], mode] if st.has("modes") else String(st["id"])
	print("baked %s %dx%d cells (%.0f m) in %d ms, delta %.1f .. +%.1f m" % [id, nx, nz, cell, Time.get_ticks_msec() - t0, mind, maxd])
	var img := Image.create_from_data(nx, nz, false, Image.FORMAT_RGBAF, buf.to_byte_array())
	var out := "res://data/region1/terrain/%s.res" % id
	print("saved ", out, " err=", ResourceSaver.save(img, out))
	var line := {"id": id, "file": out, "origin": [snappedf(x0, 0.1), snappedf(z0, 0.1)], "cell": cell, "late": true}
	if st.has("modes"):
		line["mode"] = mode
	print("STAMP_INDEX ", JSON.stringify(line))
	if preview != "":
		_preview(buf, nx, nz, x0, z0, cell, preview + "/%s.png" % id)


## Per-stamp working data (centres, frames, satellite craters ...).
func _context(st: Dictionary, M: Dictionary) -> Dictionary:
	var ctx := {}
	match String(st["type"]):
		"rift_trench":
			var c := _v(st["center"])
			ctx["c"] = c
			var r := float(st.get("extent", 330.0))
			ctx["box"] = Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0)
		"crater_field":
			var c := _v(st["center"])
			var r := float(st.get("extent", 480.0))
			ctx["c"] = c
			ctx["box"] = Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0)
			ctx["craters"] = _craters(st, M, c)
		"portal":
			var s := _site_named(String(st["site"]))
			ctx["pos"] = s["pos"]
			ctx["yaw"] = float(s["yaw"])
			ctx["bench"] = WorldGen.height(s["pos"].x, s["pos"].y)
			var r := 40.0
			ctx["box"] = Rect2(s["pos"] - Vector2(r, r), Vector2(r, r) * 2.0)
		"pass_cut":
			var s := _site_named(String(st["site"]))
			ctx["pos"] = s["pos"]
			var a := _v(st["axis"]).normalized()
			ctx["axis"] = a
			var r := float(st.get("extent", 120.0))
			ctx["box"] = Rect2(s["pos"] - Vector2(r, r), Vector2(r, r) * 2.0)
	return ctx


func _site_named(n: String) -> Dictionary:
	for s: Dictionary in WorldGen.sites:
		if String(s["name"]) == n or String(s.get("r1id", "")) == n:
			return s
	push_error("bake_stamps: no site " + n)
	quit(1)
	return {}


func _craters(st: Dictionary, M: Dictionary, c: Vector2) -> Array:
	var out: Array = []
	var main_c := c
	out.append({"c": main_c, "R": float(M["main_r"]), "D": float(M["main_depth"]), "rim": float(M["main_rim"]), "flat": float(M.get("main_flat", 0.38))})
	var rng := RandomNumberGenerator.new()
	rng.seed = int(st.get("seed", 1066))
	var tries := 0
	var want := int(M.get("satellites", 9))
	var ext := float(st.get("extent", 480.0)) - 60.0
	while out.size() < want + 1 and tries < 4000:
		tries += 1
		var ang := rng.randf() * TAU
		var dist := lerpf(float(M.get("sat_min_dist", 130.0)), float(M.get("sat_max_dist", 330.0)), sqrt(rng.randf()))
		var q := main_c + Vector2.from_angle(ang) * dist
		if absf(q.x - c.x) > ext or absf(q.y - c.y) > ext:
			continue
		var rr := rng.randf_range(float(M.get("sat_r", [14.0, 38.0])[0]), float(M.get("sat_r", [14.0, 38.0])[1]))
		var ok := true
		for o: Dictionary in out:
			if q.distance_to(o["c"]) < float(o["R"]) * 1.35 + rr * 1.35 + 6.0:
				ok = false
				break
		if not ok:
			continue
		for s: Dictionary in WorldGen.sites:                 # not on a planned site
			if q.distance_to(s["pos"]) < float(s["clear"]) + rr * 1.3 + 12.0 and not _is_own(s["pos"]):
				ok = false
				break
		if not ok or WorldGen.near_water(q.x, q.y, rr + 20.0) or WorldGen.road_distance(q.x, q.y) < rr * 1.3 + 12.0:
			continue
		var skip := false
		for s in WorldGen.settlements:
			if q.distance_to(s["pos"]) < float(s["radius"]) * 1.4 + rr * 1.4:
				skip = true
		if skip:
			continue
		out.append({"c": q, "R": rr, "D": rng.randf_range(float(M.get("sat_depth", [2.5, 6.0])[0]), float(M.get("sat_depth", [2.5, 6.0])[1])),
			"rim": rng.randf_range(0.8, 1.8), "flat": 0.3})
	print("  craters: ", out.size())
	return out


func _is_own(p: Vector2) -> bool:
	for o: Vector2 in own:
		if o.distance_to(p) < 1.0:
			return true
	return false


## Exclusion discs: every planned site / settlement / camp near the window, except the ones listed in the stamp's "own" sites.
func _exclusions(st: Dictionary, M: Dictionary, box: Rect2) -> void:
	sites_near.clear()
	own.clear()
	var own_names: Array = (st.get("own", []) as Array).duplicate()
	if st.has("site"):
		own_names.append(st["site"])       # a portal / pass stamp belongs to its own site
	for n in own_names:
		var s := _site_named(String(n))
		own.append(s["pos"])
	var wide := box.grow(120.0)
	for s: Dictionary in WorldGen.sites:
		var p: Vector2 = s["pos"]
		# Only flattened pads need protecting (a `clear` alone just removes trees, and the look landmarks share ground with the mines).
		if wide.has_point(p) and not _is_own(p) and float(s["clear"]) > 0.0 and bool(s["flatten"]):
			sites_near.append({"p": p, "r": float(s["clear"])})
	for s in WorldGen.settlements:
		if wide.grow(200.0).has_point(s["pos"]):
			sites_near.append({"p": s["pos"], "r": float(s["radius"]) * 1.2})
	print("  exclusions: ", sites_near.size(), " own=", own.size())


func _mask(p: Vector2, road_gap: float) -> float:
	var m := 1.0
	for e: Dictionary in sites_near:
		var d := p.distance_to(e["p"])
		m = minf(m, smoothstep(float(e["r"]) + 2.0, float(e["r"]) * 1.8 + 6.0, d))
		if m <= 0.0:
			return 0.0
	var rd := WorldGen.road_distance(p.x, p.y)
	m = minf(m, smoothstep(road_gap * 0.5, road_gap * 2.2, rd))
	if m > 0.0 and WorldGen.near_water(p.x, p.y, 10.0):
		m = 0.0
	return m


## [metres added, tread hint, share of trees kept, rock-face mask]
func _shape(st: Dictionary, M: Dictionary, ctx: Dictionary, p: Vector2, base: float) -> PackedFloat32Array:
	match String(st["type"]):
		"rift_trench": return _rift(M, ctx, p)
		"crater_field": return _scar(M, ctx, p)
		"portal": return _portal(M, ctx, p, base)
		"pass_cut": return _pass(M, ctx, p, base)
	return PackedFloat32Array([0, 0, 1, 0])


func _rift(M: Dictionary, ctx: Dictionary, p: Vector2) -> PackedFloat32Array:
	var q: Vector2 = p - (ctx["c"] as Vector2)
	var ang := deg_to_rad(float(M.get("angle", 25.0)))
	var u := q.x * cos(ang) + q.y * sin(ang)
	var v := -q.x * sin(ang) + q.y * cos(ang)
	var joff := 28.0 * sin(u / 57.0) + 17.0 * sin(u / 23.0 + 1.3) + 9.0 * sin(u / 11.0 + 0.4)
	if bool(M.get("center_on_site", false)):      # the trench passes through the centre (the Rift object sits in it) instead of the macro's own axis
		joff -= 17.0 * sin(1.3) + 9.0 * sin(0.4)
	var jag := float(M.get("jag", 0.3))
	var wid := (float(M["wid"]) + 6.0 * sin(u / 37.0 + 2.0)) * (1.0 + jag * n_a.get_noise_2d(u * 0.9, 17.0))
	var endf := 1.0 - smoothstep(float(M.get("len_full", 160.0)), float(M.get("len_end", 300.0)), absf(u))
	var vv := absf(v - joff)
	var shape := 1.0 - smoothstep(wid * float(M.get("floor", 0.5)), wid * 1.5, vv)
	# Rock ledges: the walls step down in broken terraces rather than one smooth ramp.
	var wall := shape * (1.0 - shape) * 4.0
	var ledge := floorf(shape * 4.0 + 0.5) / 4.0
	shape = lerpf(shape, ledge, float(M.get("ledges", 0.4)) * clampf(wall, 0.0, 1.0) * (0.6 + 0.4 * n_a.get_noise_2d(u * 0.6, v * 0.6 + 40.0)))
	var lip := float(M.get("lip", 2.5)) * exp(-pow((vv - wid * 1.9) / 7.0, 2.0))
	var delta := (-float(M["depth"]) * shape + lip) * endf
	var wide := 1.0 - smoothstep(wid * 0.8, wid * 2.6, vv)
	var face := clampf(wall, 0.0, 1.0) * endf * 0.45
	var keep := clampf(1.0 - 1.4 * wide * endf, 0.0, 1.0)
	return PackedFloat32Array([delta, 0.0, keep, face])


func _scar(M: Dictionary, ctx: Dictionary, p: Vector2) -> PackedFloat32Array:
	var delta := 0.0
	var face := 0.0
	var keep := 1.0
	for cr: Dictionary in ctx["craters"]:
		var c: Vector2 = cr["c"]
		var R: float = cr["R"]
		var dd := p.distance_to(c)
		if dd > R * 1.9:
			continue
		var ang := atan2(p.y - c.y, p.x - c.x)
		var wob := 1.0 + 0.16 * n_b.get_noise_2d(c.x + cos(ang) * 40.0, c.y + sin(ang) * 40.0) + 0.05 * n_a.get_noise_2d(p.x, p.y)
		var d := dd / (R * wob)
		var bowl := 1.0 - smoothstep(float(cr["flat"]), 1.0, d)
		var rim: float = float(cr["rim"]) * exp(-pow((d - 1.14) / 0.2, 2.0))
		delta += -float(cr["D"]) * bowl + rim
		face = maxf(face, smoothstep(0.55, 0.85, d) * (1.0 - smoothstep(0.98, 1.15, d)) * 0.45)
		keep = minf(keep, smoothstep(0.85, 1.45, d))
	return PackedFloat32Array([delta, 0.0, clampf(keep, 0.0, 1.0), face])


## Portal cut: a level bench in front of the entrance (cut or filled to the entrance's own ground height), a headwall brow raised behind it.
## Frame: f = (sin yaw, cos yaw) points out of the mine (downhill); s along f, u across.
func _portal(M: Dictionary, ctx: Dictionary, p: Vector2, base: float) -> PackedFloat32Array:
	var yaw: float = ctx["yaw"]
	var f := Vector2(sin(yaw), cos(yaw))
	var side := Vector2(f.y, -f.x)
	var q: Vector2 = p - (ctx["pos"] as Vector2)
	var s := q.dot(f)
	var u := absf(q.dot(side))
	var bench: float = ctx["bench"]
	var half := float(M.get("bench_half", 6.5))
	var feather := float(M.get("feather", 5.0))
	var s_end := float(M.get("bench_len", 20.0))
	var wu := 1.0 - smoothstep(half, half + feather, u)
	var ws := smoothstep(-2.0, -0.5, s) * (1.0 - smoothstep(s_end, s_end + feather, s))
	var wa := wu * ws
	var delta := clampf(bench - base, -4.0, 6.0) * wa      # a steep slope gets a sloping bench rather than a 10 m spoil wall
	# Headwall brow behind the portal.
	var bh := float(M.get("brow", 4.5))
	var rise := smoothstep(-2.4, -6.0, s)                      # steep face right behind the frame
	var fade := 1.0 - smoothstep(-12.0, -float(M.get("brow_len", 20.0)), s)
	var wb := (1.0 - smoothstep(half + 2.0, half + 9.0, u)) * rise * fade
	delta += bh * wb * (1.0 + 0.12 * n_a.get_noise_2d(p.x, p.y))
	var face := wb * smoothstep(-2.4, -3.6, s) * (1.0 - smoothstep(-6.0, -8.0, s)) * 0.45
	var keep := 1.0 - clampf(wa + wb * 1.5, 0.0, 1.0)
	return PackedFloat32Array([delta, 0.0, keep, face])


## Pass cut: a notch through a ridge along the road axis (floor lowered, shoulders eased), so the road sits in a gap with rock cheeks.
func _pass(M: Dictionary, ctx: Dictionary, p: Vector2, base: float) -> PackedFloat32Array:
	var a: Vector2 = ctx["axis"]
	var side := Vector2(a.y, -a.x)
	var q: Vector2 = p - (ctx["pos"] as Vector2)
	var s := q.dot(a)
	var u := absf(q.dot(side))
	var half := float(M.get("floor_half", 8.0))
	var depth := float(M.get("depth", 9.0))
	var len_half := float(M.get("len_half", 70.0))
	var along := 1.0 - smoothstep(len_half * 0.6, len_half, absf(s))
	var wall := float(M.get("wall", 14.0))
	var shape := 1.0 - smoothstep(half, half + wall, u)
	var delta := -depth * shape * along * (1.0 + 0.15 * n_a.get_noise_2d(p.x, p.y))
	var face := shape * (1.0 - shape) * 4.0 * along * 0.45
	return PackedFloat32Array([delta, 0.0, clampf(1.0 - shape * along * 1.4, 0.0, 1.0), clampf(face, 0.0, 0.45)])


func _preview(buf: PackedFloat32Array, nx: int, nz: int, x0: float, z0: float, cell: float, path: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var H := PackedFloat32Array()
	H.resize(nx * nz)
	var lo := INF
	var hi := -INF
	for iz in nz:
		for ix in nx:
			var h := WorldGen.height(x0 + ix * cell, z0 + iz * cell) + buf[(iz * nx + ix) * 4]
			H[iz * nx + ix] = h
			lo = minf(lo, h)
			hi = maxf(hi, h)
	var img := Image.create(nx, nz, false, Image.FORMAT_RGB8)
	for iz in range(1, nz - 1):
		for ix in range(1, nx - 1):
			var dx := (H[iz * nx + ix + 1] - H[iz * nx + ix - 1]) / (2.0 * cell)
			var dz := (H[(iz + 1) * nx + ix] - H[(iz - 1) * nx + ix]) / (2.0 * cell)
			var n := Vector3(-dx, 1.0, -dz).normalized()
			var sh := clampf(n.dot(Vector3(-0.6, 0.6, -0.5).normalized()), 0.0, 1.0)
			var hc := clampf((H[iz * nx + ix] - lo) / maxf(hi - lo, 1.0), 0.0, 1.0)
			var c := Color(0.45 + hc * 0.45, 0.6 + hc * 0.25, 0.35 + hc * 0.3) * (0.35 + 0.75 * sh)
			var d := buf[(iz * nx + ix) * 4]
			if d < -0.3:
				c = c.lerp(Color(0.9, 0.3, 0.9), clampf(-d / 12.0, 0.0, 0.7))
			elif d > 0.3:
				c = c.lerp(Color(0.95, 0.85, 0.3), clampf(d / 8.0, 0.0, 0.7))
			img.set_pixel(ix, iz, c)
	img.save_png(path)
	print("preview ", path)


static func _v(a: Array) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))
