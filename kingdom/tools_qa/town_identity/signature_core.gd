extends RefCounted
const TownIdentity := preload("res://scripts/world/town_identity.gd")


func run(seed_value: int, out: String, threshold: float, legacy := false) -> int:
	TownIdentity.legacy_all = legacy      # before / after: the original layout of every town
	TownIdentity.reset()
	WorldGen.setup(seed_value)
	var rep := TownIdentity.report(WorldGen.settlements, threshold)
	var lines: Array[String] = []
	lines.append("=== TOWN SIGNATURES seed=%d  %d towns, %d pairs ===" % [seed_value, (rep["rows"] as Array).size(), int(rep["pairs"])])
	lines.append("distinctness (weighted Gower distance 0..1): min %.3f (%s / %s), mean %.3f, threshold %.2f, pairs below threshold: %d" % [
		float(rep["min_distance"]), (rep["min_pair"] as Array)[0], (rep["min_pair"] as Array)[1], float(rep["mean_distance"]), threshold, (rep["violations"] as Array).size()])
	lines.append("")
	lines.append("%-12s %-9s %-9s %-9s %-7s %-10s %-10s %-9s %-15s %-8s %s" % ["town", "arch", "size", "roof", "wall", "layout", "palette", "banner", "kits", "nearest", "terrain"])
	for r: Dictionary in rep["rows"]:
		lines.append("%-12s %-9s %-9s %-9s %-7s %-10s %-10s %-13s %-30s %s %.2f  [%s]  %s" % [r["name"], r["arch"], r["size"], r["roof"], r["wall"], r["layout"], r["palette"], r["banner"], ",".join(r["kits"]), r["nearest"], float(r["nearest_distance"]), ",".join(r["terrain"]), r["flavour"]])
	lines.append("")
	lines.append("layout stats: lots, extent along / across the road axis (m), roof shares of the plain houses, landmarks")
	for st in WorldGen.settlements:
		var plan: Dictionary = st["plan"]
		var prof := TownIdentity.profile(st)
		var axis := TownIdentity.main_axis(plan["gates"])
		var nrm := Vector2(-axis.y, axis.x)
		var along := 0.0
		var across := 0.0
		var roofs := {}
		var plain := 0
		for lot: Dictionary in plan["lots"]:
			var v: Vector2 = (lot["pos"] as Vector2) - (st["pos"] as Vector2)
			along = maxf(along, absf(v.dot(axis)))
			across = maxf(across, absf(v.dot(nrm)))
			var g := TownIdentity.roof_of(String(lot["asset"]))
			if g != "":
				roofs[g] = int(roofs.get(g, 0)) + 1
				plain += 1
		var shares: Array[String] = []
		for g: String in TownIdentity.ROOF_KINDS:
			shares.append("%s %d%%" % [g, roundi(100.0 * float(roofs.get(g, 0)) / float(maxi(plain, 1)))])
		var lms: Array[String] = []
		for lm: Dictionary in plan["landmarks"]:
			lms.append(String(lm["asset"]))
		lines.append("%-12s %-9s lots %3d  along %5.1f across %5.1f  streets %3d  plaza %4.1f  roofs [%s]  landmarks %s" % [st["name"], prof["layout"], (plan["lots"] as Array).size(), along, across, (plan["streets"] as Array).size(), float(plan["plaza_r"]), ", ".join(shares), ",".join(lms)])
	for b: Array in rep["violations"]:
		lines.append("TOO SIMILAR: %s / %s  distance %.3f" % [b[0], b[1], float(b[2])])
	var text := "\n".join(lines)
	print(text)
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	var f := FileAccess.open(out + ".txt", FileAccess.WRITE)
	f.store_string(text + "\n")
	f.close()
	var jf := FileAccess.open(out + ".json", FileAccess.WRITE)
	jf.store_string(JSON.stringify(rep, "  "))
	jf.close()
	return 0 if (rep["violations"] as Array).is_empty() else 1
