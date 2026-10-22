extends SceneTree
## W2 measurements with the current --world_macro mode: river bank gaps, road grades, landmark pad flatness.
func _initialize() -> void:
	WorldGen.setup(1066)
	print("MODE ", WorldMacro.mode(), " active=", WorldMacro.active)
	# rivers
	for ri in WorldGen.rivers.size():
		var r: Dictionary = WorldGen.rivers[ri]
		var pts: PackedVector2Array = r["points"]
		var n := 0
		var gaps := 0
		var worst := 0.0
		var dry_centre := 0
		var deep := 0
		var gap_list: Array[float] = []
		for i in range(1, pts.size() - 1, 1):
			var p := pts[i]
			if absf(p.x) > 6100 or absf(p.y) > 6100:
				continue
			var dir := (pts[i + 1] - pts[i - 1]).normalized()
			var nrm := dir.orthogonal()
			var lv := WorldGen.water_level_at(p.x, p.y)
			if is_nan(lv):
				continue
			n += 1
			var d0 := lv - WorldGen.height(p.x, p.y)
			if d0 <= 0.0:
				dry_centre += 1
			if d0 > 4.0:
				deep += 1
			for side in [-1.0, 1.0]:
				var gap := -1.0
				var o := 0.0
				while o < 60.0:
					var q: Vector2 = p + nrm * side * o
					var dep := WorldGen.water_level_at(q.x, q.y)
					if is_nan(dep):
						break
					var g := WorldGen.height(q.x, q.y) - dep
					if g >= 0.0:
						gap = g
						break
					o += 0.25
				if gap >= 0.0:
					gap_list.append(gap)
					worst = maxf(worst, gap)
					if gap > 0.3:
						gaps += 1
		gap_list.sort()
		print("river %d: samples %d dry-centre %d deeper-than-4m %d shore gap p50 %.3f p95 %.3f max %.3f over0.3 %d of %d" % [ri, n, dry_centre, deep, gap_list[gap_list.size() / 2] if gap_list.size() > 0 else -1.0, gap_list[int(gap_list.size() * 0.95)] if gap_list.size() > 0 else -1.0, worst, gaps, gap_list.size()])
	# roads
	var tot := 0.0
	var steep := 0.0
	var worst_g := 0.0
	var worst_road := ""
	for r in WorldGen.roads:
		var a: Vector2 = WorldGen.settlements[r.x]["pos"]
		var b: Vector2 = WorldGen.settlements[r.y]["pos"]
		var len := a.distance_to(b)
		var steps := int(len / 8.0)
		var prev := WorldGen.height(a.x, a.y)
		var rs := 0.0
		var rg := 0.0
		for k in range(1, steps + 1):
			var p := a.lerp(b, float(k) / steps)
			var h := WorldGen.height(p.x, p.y)
			var g := absf(h - prev) / (len / steps)
			if g > 0.12:
				rs += len / steps
			rg = maxf(rg, g)
			prev = h
		tot += len
		steep += rs
		if rg > worst_g:
			worst_g = rg
			worst_road = "%s-%s" % [WorldGen.settlements[r.x]["name"], WorldGen.settlements[r.y]["name"]]
		if rs > 60.0:
			print("  road %s-%s %.0f m, steeper than 12%%: %.0f m, max %.0f%%" % [WorldGen.settlements[r.x]["name"], WorldGen.settlements[r.y]["name"], len, rs, rg * 100.0])
	print("ROADS total %.0f m, > 12%% grade %.0f m (%.1f%%), worst %.0f%% on %s" % [tot, steep, steep / tot * 100.0, worst_g * 100.0, worst_road])
	# landmark pads: sites with a clearing that flattens
	var pads := 0
	var bad := 0
	var wrst := 0.0
	for c in WorldGen.clearings:
		if not bool(c["flatten"]):
			continue
		pads += 1
		var cr: float = c["radius"]
		var p: Vector2 = c["pos"]
		var m := 0.0
		for k in 8:
			var q := p + Vector2.from_angle(k * TAU / 8.0) * cr * 0.6
			m = maxf(m, absf(WorldGen.height(q.x, q.y) - float(c["base_h"])))
		wrst = maxf(wrst, m)
		if m > 0.2:
			bad += 1
			if m > 1.0:
				print("  pad at (%.0f, %.0f) r=%.0f off by %.2f  river_d=%.0f" % [p.x, p.y, cr, m, WorldGen.shore_distance(p.x, p.y)])
	print("PADS flattened clearings %d, off by > 0.2 m at 0.6r: %d, worst %.2f" % [pads, bad, wrst])
	quit(0)
