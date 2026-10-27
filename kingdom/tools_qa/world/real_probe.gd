extends SceneTree
## W6 headless probe of the real world: setup time, settlements on dry ground, water, one Terrain3D region bake.
## Godot --headless --path kingdom -s res://tools_qa/world/real_probe.gd -- --world_macro=real

func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	WorldGen.setup(1066)
	print("MODE ", WorldMacro.mode(), " real=", RealWorld.active(), " setup_ms=", Time.get_ticks_msec() - t0, " macro_mb=", WorldMacro.memory_bytes() / 1048576.0)
	var wet := 0
	for st in WorldGen.settlements:
		var p: Vector2 = st["pos"]
		var w := WorldGen.is_water(p.x, p.y)
		if w:
			wet += 1
		print("  %-12s (%6.0f,%6.0f) h=%6.1f water=%s realm=%s" % [st["name"], p.x, p.y, WorldGen.height(p.x, p.y), w, RealWorld.in_realm(p)])
	var out := 0
	for s in WorldGen.sites:
		if not RealWorld.in_realm(s["pos"]):
			out += 1
	print("settlements_wet=", wet, " sites=", WorldGen.sites.size(), " sites_outside=", out, " rivers=", WorldGen.rivers.size(),
		" mere=", WorldGen.lake_center, " lvl=", WorldGen.lake_level, " water@mere=", WorldGen.water_level_at(WorldGen.lake_center.x, WorldGen.lake_center.y))
	for at: Vector2 in [Vector2(0, 0), Vector2(-7000, -1000), Vector2(1000, -6000)]:
		var tt := Time.get_ticks_usec()
		for i in 20000:
			WorldGen.height(at.x + (i % 141) * 1.5, at.y + (i / 141) * 1.5)
		var t_raw := Time.get_ticks_usec()
		for i in 20000:
			WorldGen._raw_height(at.x + (i % 141) * 1.5, at.y + (i / 141) * 1.5)
		var t_c := Time.get_ticks_usec()
		for i in 20000:
			WorldGen.color_at(at.x + (i % 141) * 1.5, at.y + (i / 141) * 1.5, 100.0, 0.1)
		print("at ", at, " height_us=", (t_raw - tt) / 20000.0, " raw_us=", (t_c - t_raw) / 20000.0, " color_us=", (Time.get_ticks_usec() - t_c) / 20000.0)
	Terrain3DBridge.configure_spacing()
	var b := Time.get_ticks_msec()
	var maps := Terrain3DBridge.build_maps(Terrain3DBridge.region_of(0.0, 0.0))
	print("region_bake_ms=", Time.get_ticks_msec() - b, " size=", maps[0].get_width(), " snow_line_N=", Terrain3DBridge.snow_line(-7000.0))
	RealInstancer.kinds()
	var ti := Time.get_ticks_msec()
	var plan := RealInstancer.plan(Terrain3DBridge.region_origin(Terrain3DBridge.region_of(-300.0, 300.0)), Terrain3DBridge.region_m(), 1.0)
	var tot := 0
	for id: int in plan:
		tot += (plan[id] as Array).size()
	print("instancer kinds=", RealInstancer.kinds().size(), " instances=", tot, " meshes_used=", plan.size(), " plan_ms=", Time.get_ticks_msec() - ti)
	var cm := Terrain3DBridge.build_maps(Terrain3DBridge.region_of(-114.0, -2275.0))
	var hist := {}
	var cimg: Image = cm[1]
	for j in range(0, cimg.get_height(), 4):
		for i in range(0, cimg.get_width(), 4):
			var word := cimg.get_data().decode_u32((j * cimg.get_width() + i) * 4)
			var key := "%d/%d" % [(word >> 27) & 31, (word >> 22) & 31]
			hist[key] = int(hist.get(key, 0)) + 1
	print("control base/overlay histogram near Highcliff: ", hist)
	print("remap(1130,1004)=", RealWorld.remap(Vector2(1130, 1004)), " warp(0,0)=", RealWorld.warp(Vector2.ZERO))
	quit()
