extends GdUnitTestSuite
## W6 real-elevation world (docs/world/REAL_WORLD.md): --world_macro=real. Ids/names/roads never change, settlements stand on dry ground
## inside the Valencious box, the re-anchoring is identity off the real world, lakes/sea/rivers give water, the snow line falls northward.


func after() -> void:
	WorldMacro.override = ""
	WorldGen.setup(1066)


func test_remap_is_identity_off_the_real_world() -> void:
	WorldMacro.override = ""
	assert_vector(RealWorld.remap(Vector2(1130, 1004))).is_equal(Vector2(1130, 1004))
	assert_bool(RealWorld.in_realm(Vector2(99999, 0))).is_true()


func test_real_world_keeps_ids_and_moves_places_onto_dry_ground() -> void:
	WorldMacro.override = ""
	WorldGen.setup(1066)
	var names: Array = []
	for st in WorldGen.settlements:
		names.append(st["name"])
	var roads := WorldGen.roads.duplicate()
	var nsites := WorldGen.sites.size()
	WorldMacro.override = "real"
	WorldGen.setup(1066)
	assert_bool(RealWorld.active()).is_true()
	assert_float(WorldMacro.HALF).is_equal(16384.0)
	var now: Array = []
	for st in WorldGen.settlements:
		now.append(st["name"])
		var p: Vector2 = st["pos"]
		assert_bool(RealWorld.in_realm(p)).override_failure_message("%s outside the realm" % st["name"]).is_true()
		assert_bool(WorldGen.is_water(p.x, p.y)).override_failure_message("%s under water" % st["name"]).is_false()
	assert_array(now).is_equal(names)
	assert_array(WorldGen.roads).is_equal(roads)
	assert_int(WorldGen.sites.size()).is_equal(nsites)
	assert_vector(WorldGen.settlements[0]["pos"]).is_equal(Vector2.ZERO)    # Ashford stays the origin


func test_real_water_snow_and_lock() -> void:
	WorldMacro.override = "real"
	WorldGen.setup(1066)
	assert_int(WorldGen.rivers.size()).is_greater(5)
	assert_float(WorldGen.water_level_at(-15500.0, 0.0)).is_equal(0.0)          # the Tideclad Sea
	var m := RealWorld.mere()
	assert_bool(m.is_empty()).is_false()
	assert_bool(is_nan(WorldGen.water_level_at(m["centre"].x, m["centre"].y))).is_false()
	assert_float(Terrain3DBridge.snow_line(-7000.0)).is_less(Terrain3DBridge.snow_line(7000.0))
	assert_bool(RealWorld.in_realm(Vector2(0, -12000))).is_false()               # Frostcrown Holds: locked
	Terrain3DBridge.configure_spacing()
	assert_float(Terrain3DBridge.region_m()).is_equal(768.0)
	var box := RealWorld.box()
	assert_bool(Terrain3DBridge.in_world(Terrain3DBridge.region_of(box.position.x, box.position.y))).is_true()
	assert_bool(Terrain3DBridge.in_world(Terrain3DBridge.region_of(box.end.x - 1.0, box.end.y - 1.0))).is_true()
