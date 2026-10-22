extends SceneTree
## Hillshade of a window around a site: Godot -s w4_probe2.gd -- --site="Grimfen Pass" --half=200 --cell=4 --out=<png> [--world_macro=valencious]
func _initialize() -> void:
	var site := "Grimfen Pass"; var half := 200.0; var cell := 4.0; var out := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--site="): site = a.substr(7)
		elif a.begins_with("--half="): half = float(a.substr(7))
		elif a.begins_with("--cell="): cell = float(a.substr(7))
		elif a.begins_with("--out="): out = a.substr(6)
	WorldGen.setup(1066)
	for s: Dictionary in WorldGen.sites:
		if String(s["name"]) == site:
			var c: Vector2 = s["pos"]
			var n := int(half * 2.0 / cell)
			var img := Image.create(n, n, false, Image.FORMAT_RGB8)
			var lo := INF; var hi := -INF
			var H := PackedFloat32Array(); H.resize(n * n)
			for iz in n:
				for ix in n:
					var h := WorldGen.height(c.x - half + ix * cell, c.y - half + iz * cell)
					H[iz * n + ix] = h; lo = minf(lo, h); hi = maxf(hi, h)
			for iz in range(1, n - 1):
				for ix in range(1, n - 1):
					var dx := (H[iz * n + ix + 1] - H[iz * n + ix - 1]) / (2.0 * cell)
					var dz := (H[(iz + 1) * n + ix] - H[(iz - 1) * n + ix]) / (2.0 * cell)
					var sh := clampf(Vector3(-dx, 1.0, -dz).normalized().dot(Vector3(-0.6, 0.6, -0.5).normalized()), 0.0, 1.0)
					var hc := (H[iz * n + ix] - lo) / maxf(hi - lo, 1.0)
					var col := Color(0.4 + hc * 0.5, 0.55 + hc * 0.3, 0.35 + hc * 0.4) * (0.3 + 0.8 * sh)
					var rd := WorldGen.road_distance(c.x - half + ix * cell, c.y - half + iz * cell)
					if rd < 4.0: col = Color(0.9, 0.2, 0.2)
					img.set_pixel(ix, iz, col)
			img.save_png(out)
			print("SITE ", site, " ", c, " yaw ", s["yaw"], " h ", lo, "..", hi, " saved ", out)
	quit(0)
