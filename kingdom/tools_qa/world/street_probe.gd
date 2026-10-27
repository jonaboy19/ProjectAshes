extends SceneTree
## Real world: what the Terrain3D control map says on Ashford's plaza/streets (towns worker: streets render as meadow).

func _initialize() -> void:
	print("PROBE real=", RealWorld.active(), " macro=", WorldMacro.is_real())
	WorldGen.setup(1066)
	print("PROBE settlements=", WorldGen.settlements.size())
	if WorldGen.settlements.is_empty():
		quit()
		return
	var a: Dictionary = WorldGen.settlements[0]
	var plan: Dictionary = a.get("plan", {})
	print("PROBE ashford ", a["name"], " pos ", a["pos"], " r ", a["radius"], " plan keys ", plan.keys())
	print("PROBE streets ", (plan.get("streets", []) as Array).slice(0, 2))
	Terrain3DBridge.configure_spacing()
	var loc := Terrain3DBridge.region_of(0.0, 0.0)
	var maps := Terrain3DBridge.build_maps(loc)
	var o := Terrain3DBridge.region_origin(loc)
	var cimg: Image = maps[1]
	for p: Vector2 in [Vector2(0, 0), Vector2(8, 3), Vector2(20, 0), Vector2(0, 25), Vector2(40, 10)]:
		var h := WorldGen.height(p.x, p.y)
		var i := int(roundf((p.x - o.x) / Terrain3DBridge.spacing_rt))
		var j := int(roundf((p.y - o.y) / Terrain3DBridge.spacing_rt))
		var word := cimg.get_data().decode_u32((j * cimg.get_width() + i) * 4)
		print("PROBE at ", p, " street_d=", WorldGen.street_distance(p.x, p.y), " color_at=", WorldGen.color_at(p.x, p.y, h, 0.05),
			" base/over/blend=", (word >> 27) & 31, "/", (word >> 22) & 31, "/", (word >> 14) & 255)
	quit()
