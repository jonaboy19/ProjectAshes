extends SceneTree
## Bakes a valley stamp for Region1Terrain from its design JSON (data/region1/terrain/<id>_design.json).
##   Godot --headless --path kingdom -s res://tools_qa/region1/bake_valley.gd -- [--design=res://data/region1/terrain/hollins_reach_design.json]
##       [--preview=<abs png>] [--detail=<abs float32 raw from erode_valley.py>] [--export=<abs dir>]
## Writes res://data/region1/terrain/<id>.res (Image RGF: R = metres added, G = terrace tread hint) and prints
## the origin/cell for data/region1/terrain_stamps.json. --export also writes the stamped heights of the window
## (<id>_h.raw float32 + <id>_mask.raw float32 wall mask) for the erosion pass (tools_qa/region1/erode_valley.py).

var D: Dictionary
var spine := PackedVector2Array()
var arc := PackedFloat32Array()
var n_rim := FastNoiseLite.new()
var n_floor := FastNoiseLite.new()
var n_ledge := FastNoiseLite.new()
var natural := false


func _initialize() -> void:
	var design := "res://data/region1/terrain/hollins_reach_design.json"
	var preview := ""
	var detail := ""
	var export_dir := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--design="): design = a.substr(9)
		elif a.begins_with("--preview="): preview = a.substr(10)
		elif a.begins_with("--detail="): detail = a.substr(9)
		elif a.begins_with("--export="): export_dir = a.substr(9)
		elif a == "--natural": natural = true
	D = JSON.parse_string(FileAccess.get_file_as_string(design))
	Region1Terrain.enabled = false          # sample the untouched ground
	WorldGen.setup(1066)
	n_rim.seed = 71; n_rim.frequency = 0.012; n_rim.fractal_octaves = 2
	n_floor.seed = 72; n_floor.frequency = 0.008; n_floor.fractal_octaves = 2
	n_ledge.seed = 73; n_ledge.frequency = 0.07; n_ledge.fractal_octaves = 3
	var hill := String(D.get("type", "valley")) == "hill"
	if hill:
		spine = PackedVector2Array([_v(D["center"]), _v(D["center"]) + Vector2(1, 0)])
		arc = PackedFloat32Array([0.0, 1.0])
	# Spine: the real river polyline from its source, cut at spine_length.
	var pts: PackedVector2Array = PackedVector2Array() if hill else WorldGen.rivers[int(D.get("river_index", 0))]["points"]
	var s := 0.0
	for i in pts.size():
		if i > 0:
			s += pts[i].distance_to(pts[i - 1])
		spine.append(pts[i])
		arc.append(s)
		if s > float(D["spine_length"]):
			break
	# Smooth the spine (the river wiggles): a nearest-point parameter on a wiggly polyline jumps on the inside
	# of every bend, which printed stripes across the walls. The floor is wide enough to hold the real river.
	for _pass in (0 if hill else 24):
		var sm := spine.duplicate()
		for i in range(1, spine.size() - 1):
			sm[i] = spine[i - 1] * 0.25 + spine[i] * 0.5 + spine[i + 1] * 0.25
		spine = sm
	if not hill:
		arc.clear()
	var acc := 0.0
	for i in (0 if hill else spine.size()):
		if i > 0:
			acc += spine[i].distance_to(spine[i - 1])
		arc.append(acc)
	for k in range(0, 0 if hill else 800, 50):
		var j := 0
		while j < arc.size() - 2 and arc[j + 1] < k: j += 1
		var dd := (spine[j + 1] - spine[j]).normalized()
		var en := Vector2(-dd.y, dd.x) if Vector2(-dd.y, dd.x).x > 0.0 else Vector2(dd.y, -dd.x)
		print("SPINE s=%d p=%s east_n=%s fw=%.0f" % [k, spine[j].round(), en.snapped(Vector2(0.01, 0.01)), _tab(D["floor_half"], k)])
	var margin := float(D.get("margin", 0.0))
	var box := Rect2(spine[0], Vector2.ZERO)
	for p in spine:
		box = box.expand(p)
	box = box.grow(margin)
	if hill:
		var rr := maxf(float(D["radius"][0]), float(D["radius"][1])) * 1.35 + 12.0
		box = Rect2(_v(D["center"]) - Vector2(rr, rr), Vector2(rr, rr) * 2.0)
	var cell := float(D["cell"])
	var x0 := snappedf(box.position.x, cell)
	var z0 := snappedf(box.position.y, cell)
	var nx := int(box.size.x / cell) + 1
	var nz := int(box.size.y / cell) + 1
	var buf := PackedFloat32Array()
	buf.resize(nx * nz * 4)
	var hbuf := PackedFloat32Array()
	var mbuf := PackedFloat32Array()
	if export_dir != "":
		hbuf.resize(nx * nz)
		mbuf.resize(nx * nz)
	var det := PackedFloat32Array()
	if detail != "":
		det = FileAccess.get_file_as_bytes(detail).to_float32_array()
		print("detail cells ", det.size(), " grid ", nx * nz)
	var t0 := Time.get_ticks_msec()
	var maxr := 0.0
	for iz in nz:
		for ix in nx:
			var p := Vector2(x0 + ix * cell, z0 + iz * cell)
			var base := WorldGen.height(p.x, p.y)
			var r := _hill(p, base) if hill else _rise(p, base)
			if natural: r = PackedFloat32Array([0, 0, 1, 0, 0])
			var rise: float = r[0]
			if not det.is_empty():
				rise += det[iz * nx + ix] * r[4]
			if r[0] >= 0.0:
				rise = maxf(rise, 0.0)
			var o4 := (iz * nx + ix) * 4
			buf[o4] = rise
			buf[o4 + 1] = r[1]
			buf[o4 + 2] = r[2]
			buf[o4 + 3] = r[3]
			maxr = maxf(maxr, rise)
			if export_dir != "":
				hbuf[iz * nx + ix] = base + rise
				mbuf[iz * nx + ix] = r[4]
	# Feather the window edge to zero so the stamp can never leave a seam.
	for iz in nz:
		for ix in nx:
			var e := mini(mini(ix, nx - 1 - ix), mini(iz, nz - 1 - iz))
			if e < 6:
				buf[(iz * nx + ix) * 4] *= e / 6.0
	print("baked %dx%d cells (%.0f m) in %d ms, max rise %.1f m" % [nx, nz, cell, Time.get_ticks_msec() - t0, maxr])
	var img := Image.create_from_data(nx, nz, false, Image.FORMAT_RGBAF, buf.to_byte_array())
	var out := "res://data/region1/terrain/%s.res" % D["id"]
	var err := ResourceSaver.save(img, out)
	print("saved ", out, " err=", err)
	print("STAMP_INDEX {\"id\": \"%s\", \"file\": \"%s\", \"origin\": [%.1f, %.1f], \"cell\": %.1f}" % [D["id"], out, x0, z0, cell])
	if export_dir != "":
		DirAccess.make_dir_recursive_absolute(export_dir)
		var f := FileAccess.open(export_dir + "/%s_h.raw" % D["id"], FileAccess.WRITE)
		f.store_buffer(hbuf.to_byte_array()); f.close()
		f = FileAccess.open(export_dir + "/%s_mask.raw" % D["id"], FileAccess.WRITE)
		f.store_buffer(mbuf.to_byte_array()); f.close()
		print("EXPORT ", nx, " ", nz)
	if preview != "":
		_preview(buf, nx, nz, x0, z0, cell, preview)
	quit(0)


static func _tab(t: Array, s: float) -> float:
	if s <= float(t[0][0]):
		return float(t[0][1])
	for i in range(1, t.size()):
		if s <= float(t[i][0]):
			var a: Array = t[i - 1]
			var b: Array = t[i]
			return lerpf(float(a[1]), float(b[1]), (s - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.001))
	return float(t[t.size() - 1][1])


## [metres added, terrace tread hint, tree keep 0..1, rock-face mask, wall mask for the erosion detail]
func _rise(p: Vector2, base: float) -> PackedFloat32Array:
	var out := _rise_core(p, base)
	# Plunge pool at the valley head: a basin below the river source for the falls to land in.
	if D.has("pool"):
		var P: Dictionary = D["pool"]
		var up := (spine[0] - spine[1]).normalized()
		var pc := spine[0] + up * float(P["off"])
		var pr := float(P["r"])
		var dp := p.distance_to(pc)
		if dp < pr:
			var k := 1.0 - smoothstep(pr * 0.5, pr, dp)
			out[0] = lerpf(out[0], -float(P["depth"]), k)
			out[2] = minf(out[2], 1.0 - k)
			out[3] *= 1.0 - k
	return out


func _rise_core(p: Vector2, base: float) -> PackedFloat32Array:
	# Nearest point on the spine.
	var best := INF
	var bs := 0.0
	var bi := 0
	var bt := 0.0
	for i in spine.size() - 1:
		var a := spine[i]
		var ab := spine[i + 1] - a
		var t := (p - a).dot(ab) / maxf(ab.length_squared(), 0.0001)
		var tc := clampf(t, 0.0, 1.0)
		var dsq := p.distance_squared_to(a + ab * tc)
		if dsq < best:
			best = dsq
			bi = i
			bt = t
			bs = lerpf(arc[i], arc[i + 1], tc)
	var d := sqrt(best)
	var dir := (spine[bi + 1] - spine[bi]).normalized()
	var q := spine[bi] + (spine[bi + 1] - spine[bi]) * clampf(bt, 0.0, 1.0)
	var v := p - q
	var east := (dir.x * v.y - dir.y * v.x) < 0.0
	var head := bi == 0 and bt < 0.0
	var L := float(D["spine_length"])
	var N: Dictionary = D["noise"]
	var fw := _tab(D["floor_half"], bs) + n_floor.get_noise_2d(bs, 0.0 if east else 90.0) * float(N["floor"]) * smoothstep(40.0, 160.0, bs)
	if d <= fw:
		return PackedFloat32Array([0.0, 0.0, 1.0, 0.0, 0.0])
	var S: Dictionary = D["east"] if east else D["west"]
	var ww := _tab(S["wall"], bs)
	var rim := _tab(S["rim"], bs) * (1.0 + n_rim.get_noise_2d(bs, 0.0 if east else 50.0) * float(N["rim"]))
	var cliff := _tab(S["cliff"], bs)
	var outer := float(S["outer"])
	if S.has("notch"):
		var nt: Dictionary = S["notch"]
		rim *= 1.0 - float(nt["depth"]) * exp(-pow((bs - float(nt["s"])) / float(nt["width"]), 2.0))
	if head:
		var H: Dictionary = D["head"]
		var up := -dir
		var ang := absf(up.angle_to(p - spine[0]))
		rim *= 1.0 - float(H["falls_notch"]) * exp(-pow(ang / float(H["falls_width"]), 2.0))
		var behind := clampf(-bt * spine[0].distance_to(spine[1]) / 80.0, 0.0, 1.0)
		outer = lerpf(outer, float(H["outer"]), behind)
	# The mouth: everything fades into the meadow past the spine's end.
	var fade := 1.0 - smoothstep(L - 120.0, L, bs)
	rim *= fade
	var t := (d - fw) / ww
	var gentle := smoothstep(0.0, 1.0, minf(t, 1.0))
	var cliffy := 0.1 * smoothstep(0.0, 0.3, t) + 0.9 * smoothstep(0.24, 0.62, t)
	var shape := lerpf(gentle, cliffy, cliff)
	var rise := 0.0
	var mask := 0.0
	if t <= 1.0:
		rise = rim * shape
		mask = smoothstep(0.0, 0.15, t)
		# Rock ledges and buttresses on the cliff faces.
		rise += float(N["ledges"]) * n_ledge.get_noise_2d(p.x, p.y) * cliff * sin(PI * clampf(t, 0.0, 1.0)) * (rim / 60.0)
	else:
		var plateau := 16.0
		var o := maxf(d - fw - ww - plateau, 0.0) / outer
		rise = rim * (1.0 - smoothstep(0.0, 1.0, o))
		mask = 1.0 - smoothstep(0.3, 1.0, o)
	var tread := 0.0
	if east and S.has("terraces") and t <= 1.02:
		var T: Dictionary = S["terraces"]
		var ramp := float(T["ramp"])
		var k := smoothstep(float(T["s0"]) - ramp, float(T["s0"]) + ramp, bs) * (1.0 - smoothstep(float(T["s1"]) - ramp, float(T["s1"]) + ramp, bs))
		if k > 0.0:
			var step := float(T["step"])
			var habs := base + rim * gentle
			var lvl := habs / step
			var fr := lvl - floorf(lvl)
			var qh := (floorf(lvl) + smoothstep(0.8, 1.0, fr)) * step
			rise = lerpf(rise, maxf(qh - base, 0.0), k)
			tread = k * (1.0 - smoothstep(0.62, 0.8, fr)) * smoothstep(0.02, 0.1, t) * (1.0 - smoothstep(0.9, 1.0, t))
	var band := smoothstep(0.08, 0.2, t) * (1.0 - smoothstep(0.72, 0.9, t)) if t <= 1.0 else 0.0
	var keep := clampf(1.0 - cliff * band * 1.3, 0.0, 1.0) * (1.0 - 0.85 * tread)
	var facem := cliff * smoothstep(0.18, 0.3, t) * (1.0 - smoothstep(0.62, 0.8, t)) * smoothstep(15.0, 30.0, rim) if t <= 1.0 else 0.0
	return PackedFloat32Array([maxf(rise, 0.0), tread, keep, facem, mask])


func _preview(buf: PackedFloat32Array, nx: int, nz: int, x0: float, z0: float, cell: float, path: String) -> void:
	var img := Image.create(nx, nz, false, Image.FORMAT_RGB8)
	var H := PackedFloat32Array()
	H.resize(nx * nz)
	for iz in nz:
		for ix in nx:
			H[iz * nx + ix] = WorldGen.height(x0 + ix * cell, z0 + iz * cell) + buf[(iz * nx + ix) * 4]
	for iz in range(1, nz - 1):
		for ix in range(1, nx - 1):
			var h := H[iz * nx + ix]
			var dx := (H[iz * nx + ix + 1] - H[iz * nx + ix - 1]) / (2.0 * cell)
			var dz := (H[(iz + 1) * nx + ix] - H[(iz - 1) * nx + ix]) / (2.0 * cell)
			var n := Vector3(-dx, 1.0, -dz).normalized()
			var sh := clampf(n.dot(Vector3(-0.6, 0.6, -0.5).normalized()), 0.0, 1.0)
			var hc := clampf(h / 120.0, 0.0, 1.0)
			var c := Color(0.45 + hc * 0.45, 0.6 + hc * 0.25, 0.35 + hc * 0.3) * (0.35 + 0.75 * sh)
			var lv := WorldGen.water_level_at(x0 + ix * cell, z0 + iz * cell)
			if not is_nan(lv) and lv > h:
				c = Color(0.3, 0.5, 0.8)
			if buf[(iz * nx + ix) * 4 + 1] > 0.5:
				c = c.lerp(Color(0.9, 0.8, 0.3), 0.35)
			if buf[(iz * nx + ix) * 4 + 3] > 0.4:
				c = c.lerp(Color(0.8, 0.4, 0.3), 0.4)
			if false:
				c = c.lerp(Color(0.9, 0.8, 0.3), 0.35)
			img.set_pixel(ix, iz, c)
	img.save_png(path)
	print("preview ", path)


static func _v(a: Array) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))


## A round or long hill (type "hill"): {center, radius: [rx, rz], yaw (deg), height, top (flat fraction 0..1),
## noise (0..1 of height), clear_top (0..1 share of trees removed on the crown)}.
func _hill(p: Vector2, base: float) -> PackedFloat32Array:
	var c := _v(D["center"])
	var q := (p - c).rotated(-deg_to_rad(float(D.get("yaw", 0.0))))
	var r := _v(D["radius"])
	var ang := atan2(q.y, q.x)
	var wob := 1.0 + n_rim.get_noise_1d(ang * 60.0) * float(D.get("wobble", 0.12))
	var dn := Vector2(q.x / r.x, q.y / r.y).length() / wob
	if dn >= 1.35:
		return PackedFloat32Array([0.0, 0.0, 1.0, 0.0, 0.0])
	var top := float(D.get("top", 0.3))
	var prof := 1.0 - smoothstep(top, 1.35, dn)
	prof = prof * prof * (3.0 - 2.0 * prof)
	var h := float(D.get("height", 0.0)) * prof * (1.0 + n_ledge.get_noise_2d(p.x * 0.3, p.y * 0.3) * float(D.get("noise", 0.06)))
	if D.has("top_height"):
		# Levelled crown at an absolute height, blended back into the natural ground on the flanks.
		h = (float(D["top_height"]) + n_ledge.get_noise_2d(p.x * 0.3, p.y * 0.3) * 0.6 - base) * prof
		return PackedFloat32Array([h, 0.0, 1.0 - float(D.get("clear_top", 0.9)) * (1.0 - smoothstep(top * 0.8, top + 0.35, dn)), 0.0, 0.0])
	var keep := 1.0 - float(D.get("clear_top", 0.9)) * (1.0 - smoothstep(top * 0.8, top + 0.35, dn))
	return PackedFloat32Array([maxf(h, 0.0), 0.0, keep, 0.0, 0.0])
