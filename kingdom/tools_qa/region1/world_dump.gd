extends SceneTree
## Prints the Region 1 world sites (C1 C2 C10) planned by RegionSites (seed 1066): name, kind, position, part count.
##   Godot --headless --path kingdom -s res://tools_qa/region1/world_dump.gd [-- --json=<file>]
func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	WorldGen.setup(1066)
	print("WorldGen.setup + RegionSites.plan: %d ms, %d sites, %d settlements" % [Time.get_ticks_msec() - t0, WorldGen.sites.size(), WorldGen.settlements.size()])
	for s in WorldGen.sites:
		if String(s["name"]) in ["Greyseam Mine", "The Ashen Scar", "The Rift", "Scar Watch", "Shrine of the Sleeping Flame", "Ember Watch"] or String(s.get("region1", "")) != "":
			print("  ref %-28s %-14s (%7.1f, %7.1f)" % [s["name"], s["kind"], s["pos"].x, s["pos"].y])
	for st in WorldGen.settlements:
		print("  town %2d %-12s %-13s (%7.1f, %7.1f) r=%d" % [st["id"], st["name"], st["kind"], st["pos"].x, st["pos"].y, st["radius"]])
	var rows: Array = []
	for s in WorldGen.sites:
		if String(s.get("r1id", "")) != "":
			var row := {"id": s["id"], "r1id": s["r1id"], "name": s["name"], "kind": s["kind"], "pos": [snappedf(s["pos"].x, 0.1), snappedf(s["pos"].y, 0.1)],
				"yaw": snappedf(float(s["yaw"]), 0.001), "h": snappedf(WorldGen.height(s["pos"].x, s["pos"].y), 0.1), "parts": s["parts"].size(), "clear": s["clear"]}
			rows.append(row)
			print("%4d %-22s %-14s (%7.1f, %7.1f) h=%5.1f parts=%d" % [s["id"], s["r1id"], s["kind"], s["pos"].x, s["pos"].y, row["h"], s["parts"].size()])
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--json="):
			var f := FileAccess.open(a.substr(7), FileAccess.WRITE)
			f.store_string(JSON.stringify(rows, " "))
	quit(0)
