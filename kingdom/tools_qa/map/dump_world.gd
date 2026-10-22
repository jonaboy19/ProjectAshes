extends SceneTree
## Samples the REAL WorldGen (seed 1066) into <out>/region1_world.json (+ region1_grid.bin) for the parchment painter.
##   Godot --path kingdom -s res://tools_qa/map/dump_world.gd -- --out=<dir> [--grid=512]
## Grid layout (float32, row-major, north = row 0): per cell 4 floats: height, water_level_minus_height (>0 = wet), forest 0..1, road_dist.

func _initialize() -> void:
	var out_dir := "user://map"
	var n := 512
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out_dir = a.substr(6)
		elif a.begins_with("--grid="): n = int(a.substr(7))
	DirAccess.make_dir_recursive_absolute(out_dir)
	WorldGen.setup(1066)
	var half := WorldGen.WORLD_HALF
	var cell := half * 2.0 / n
	var buf := PackedFloat32Array()
	buf.resize(n * n * 4)
	var t0 := Time.get_ticks_msec()
	for y in n:
		var wz := -half + (y + 0.5) * cell
		for x in n:
			var wx := -half + (x + 0.5) * cell
			var h := WorldGen.height(wx, wz)
			var lv := WorldGen.water_level_at(wx, wz)
			var i := (y * n + x) * 4
			buf[i] = h
			buf[i + 1] = (lv - h) if (not is_nan(lv) and lv > h) else 0.0
			buf[i + 2] = 0.0 if buf[i + 1] > 0.0 else clampf(WorldGen.forest_density(wx, wz), 0.0, 1.0)
			buf[i + 3] = WorldGen.road_distance(wx, wz)
	print("sampled ", n, "x", n, " in ms ", Time.get_ticks_msec() - t0)
	var f := FileAccess.open(out_dir + "/region1_grid.bin", FileAccess.WRITE)
	f.store_buffer(buf.to_byte_array())
	f.close()
	var d := {"seed": 1066, "half": half, "grid": n, "cell_m": cell, "settlements": [], "roads": [], "sites": [], "rivers": [], "places": []}
	for s: Dictionary in WorldGen.settlements:
		d["settlements"].append({"id": s["id"], "name": s["name"], "kind": s["kind"], "pos": [s["pos"].x, s["pos"].y], "radius": s["radius"], "population": s.get("population", 0)})
	for r in WorldGen.roads:
		d["roads"].append({"a": r.x, "b": r.y, "tier": WorldGen.road_tier(r.x, r.y)})
	for s: Dictionary in WorldGen.sites:
		d["sites"].append({"id": s["id"], "name": s["name"], "kind": s["kind"], "pos": [s["pos"].x, s["pos"].y]})
	for r: Dictionary in WorldGen.rivers:
		var pts := []
		var w: PackedFloat32Array = r.get("width", PackedFloat32Array())
		var i := 0
		for p: Vector2 in r["points"]:
			pts.append([snappedf(p.x, 0.1), snappedf(p.y, 0.1), snappedf(w[i] if i < w.size() else 8.0, 0.1)])
			i += 1
		d["rivers"].append(pts)
	d["lake"] = {"center": [WorldGen.lake_center.x, WorldGen.lake_center.y], "radius": WorldGen.lake_radius}
	var Disc := load("res://scripts/sim/discovery.gd")
	var disc = Disc.new()
	disc.build_from_world(root.get_node("Life").lore.places_in_region())
	for pl: Dictionary in disc.places:
		d["places"].append({"id": pl["id"], "name": pl["name"], "kind": pl["kind"], "category": pl["category"], "pos": [pl["pos"].x, pl["pos"].y], "hostile": pl["hostile"], "radius": pl.get("radius", 0)})
	var jf := FileAccess.open(out_dir + "/region1_world.json", FileAccess.WRITE)
	jf.store_string(JSON.stringify(d))
	jf.close()
	print("DUMPED ", d["settlements"].size(), " settlements ", d["sites"].size(), " sites ", d["rivers"].size(), " rivers ", d["places"].size(), " places")
	quit(0)
