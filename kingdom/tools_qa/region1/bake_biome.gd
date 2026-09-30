extends SceneTree
## Bakes the Region 1 biome map (docs/regions/LOOK_R1.md) from the real WorldGen (seed 1066, stamps on):
##   R = farmland (field patchwork is drawn by shaders/region1/biome.gdshaderinc where R > 0)
##   G = heather uplands   B = lush river / lake greens   A = dry gold meadow
## 512 x 512 over the 8 x 8 km world (16 m per pixel, bilinear in the shader).
##   Godot --headless --path kingdom -s res://tools_qa/region1/bake_biome.gd -- [--size=512] [--out=res://assets/incoming/region1/terrain/biome_map.png]

func _initialize() -> void:
	var n := 512
	var out := "res://assets/incoming/region1/terrain/biome_map.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--size="): n = int(a.substr(7))
		elif a.begins_with("--out="): out = a.substr(6)
	WorldGen.setup(1066)
	var half := WorldGen.WORLD_HALF
	var cell := half * 2.0 / n
	var noise := FastNoiseLite.new()
	noise.seed = 404
	noise.frequency = 0.0016
	noise.fractal_octaves = 3
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var t0 := Time.get_ticks_msec()
	# Settlements people farm around: village / town / castle (capital) / frontier town.
	var farms: Array = []
	for s: Dictionary in WorldGen.settlements:
		var r := float(s["radius"])
		farms.append([s["pos"], r * 1.25, r * 1.25 + (430.0 if s["kind"] == "castle" else (330.0 if s["kind"] == "town" else 250.0))])
	for site: Dictionary in WorldGen.sites:
		if String(site["kind"]) in ["farm", "windmill_hill"]:
			farms.append([site["pos"], 14.0, 170.0])
	for py in n:
		for px in n:
			var x := -half + (px + 0.5) * cell
			var z := -half + (py + 0.5) * cell
			var p := Vector2(x, z)
			var h := WorldGen.height(x, z)
			var e := 4.0
			var slope := Vector2(WorldGen.height(x + e, z) - WorldGen.height(x - e, z), WorldGen.height(x, z + e) - WorldGen.height(x, z - e)).length() / (2.0 * e)
			var forest := WorldGen.forest_density(x, z)
			var shore := WorldGen.shore_distance(x, z)
			var wet := WorldGen.is_water(x, z)
			var nz := noise.get_noise_2d(x, z) * 0.5 + 0.5
			# Farmland: rings around settlements, flat, open, dry ground.
			var farm := 0.0
			for f: Array in farms:
				var d := p.distance_to(f[0])
				farm = maxf(farm, smoothstep(float(f[1]) - 10.0, float(f[1]) + 20.0, d) * (1.0 - smoothstep(float(f[2]) * 0.75, float(f[2]), d)))
			farm *= (1.0 - smoothstep(0.16, 0.32, slope)) * (1.0 - smoothstep(0.15, 0.4, forest)) * smoothstep(8.0, 30.0, shore)
			farm *= smoothstep(0.25, 0.45, nz + 0.2)
			if WorldGen.road_distance(x, z) < 5.0:
				farm = 0.0
			# Heather: high, open ground (and the tops of the new valley rims and ridges).
			var heather := smoothstep(42.0, 75.0, h) * (1.0 - smoothstep(0.35, 0.7, forest)) * (1.0 - smoothstep(0.55, 0.9, slope))
			heather = maxf(heather, smoothstep(0.6, 0.85, nz) * smoothstep(28.0, 48.0, h) * 0.6)
			# Lush greens along rivers and lakes.
			var lush := 1.0 - smoothstep(8.0, 90.0, shore)
			# Dry gold meadow: open lowland patches, more toward the south-east frontier (the Scar side).
			var frontier := 1.0 - smoothstep(300.0, 1500.0, p.distance_to(Vector2(1130, 1004)))
			var dry := smoothstep(0.52, 0.78, 1.0 - nz) * (1.0 - smoothstep(0.1, 0.4, forest)) * (1.0 - lush)
			dry = clampf(maxf(dry, frontier * 0.55 * (1.0 - smoothstep(0.2, 0.5, forest))), 0.0, 1.0)
			var hv := preload("res://scripts/world/hidden_valley.gd")
			if hv.enabled() and hv.rn_at(p) < 1.55:
				# The Hidden Vale reads lush and untouched: river greens, no fields, no dry gold, no heather.
				var k := 1.0 - smoothstep(1.3, 1.55, hv.rn_at(p))
				farm *= 1.0 - k; heather *= 1.0 - k; dry *= 1.0 - k; lush = maxf(lush, 0.75 * k)
			if wet:
				farm = 0.0; heather = 0.0; dry = 0.0; lush = 1.0
			heather *= 1.0 - farm
			dry *= 1.0 - farm * 0.8
			img.set_pixel(px, py, Color(farm, heather, lush, dry))
		if py % 64 == 0:
			print("row ", py, " ms ", Time.get_ticks_msec() - t0)
	# Two 3x3 box-blur passes: soft biome edges, no speckle where slope or forest flicker per pixel.
	for _pass in 2:
		var src := img.duplicate() as Image
		for py in n:
			for px in n:
				var acc := Color(0, 0, 0, 0)
				for oy in range(-1, 2):
					for ox in range(-1, 2):
						acc += src.get_pixel(clampi(px + ox, 0, n - 1), clampi(py + oy, 0, n - 1))
				img.set_pixel(px, py, acc / 9.0)
	var abs_out := ProjectSettings.globalize_path(out)
	DirAccess.make_dir_recursive_absolute(abs_out.get_base_dir())
	img.save_png(abs_out)
	print("saved ", abs_out, " in ", Time.get_ticks_msec() - t0, " ms")
	quit(0)
