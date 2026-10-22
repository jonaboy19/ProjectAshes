extends RefCounted


func run(args: Dictionary) -> void:
	WorldGen.setup(int(args.get("seed", 1066)))
	var sites: Array = WorldGen.sites
	print("sites ", sites.size(), " settlements ", WorldGen.settlements.size())
	for s: Dictionary in sites:
		if args.has("kind") and String(s["kind"]) != String(args["kind"]):
			continue
		if args.has("name") and not String(s["name"]).contains(String(args["name"])):
			continue
		print("%d %s [%s] pos(%.0f, %.0f) yaw %.2f clear %.0f parts %d span %s deck %s asset %s" % [int(s["id"]), s["name"], s["kind"], (s["pos"] as Vector2).x, (s["pos"] as Vector2).y,
			float(s["yaw"]), float(s["clear"]), (s["parts"] as Array).size(), s.get("span", "-"), s.get("deck", "-"), s.get("asset", "-")])
	if args.has("crossings"):
		for st: Dictionary in WorldGen.settlements:
			var c: Vector2 = st["pos"]
			var found := 0
			for ang_i in 72:
				var dir := Vector2.from_angle(TAU * ang_i / 72.0)
				var wet0 := -1.0
				var t := 20.0
				while t < 320.0:
					var p := c + dir * t
					var wet := WorldGen.is_water(p.x, p.y)
					if wet and wet0 < 0.0:
						wet0 = t
					elif not wet and wet0 >= 0.0:
						var w := t - wet0
						if w >= 3.0 and w <= 9.0:
							var mid := c + dir * (wet0 + w * 0.5)
							print("crossing %s ang %d dist %.0f width %.1f at (%.0f, %.0f)" % [st["name"], ang_i * 5, wet0 + w * 0.5, w, mid.x, mid.y])
							found += 1
						wet0 = -1.0
					t += 1.0
			print("  %s: %d" % [st["name"], found])
