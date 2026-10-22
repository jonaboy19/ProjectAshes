extends GdUnitTestSuite
## Water must only show where terrain really dips below it. The far horizon mesh (region1_horizon.gd, 72 m grid) used to raise any
## vertex inside a river / lake band to the water level, so narrow rivers became flat blue slabs hanging over lower dry ground.
## Checks: (1) no raised horizon water vertex has a lower dry neighbour; (2) the streamed WaterStreamer surface never sits more than
## 1 m above the terrain at a vertex next to a missing (dry) quad's ground.

const Horizon := preload("res://scripts/region1/region1_horizon.gd")


func test_horizon_water_never_hangs_over_dry_ground() -> void:
	WorldGen.setup(1066)
	var h = Horizon.new()
	h._work()
	var res: Dictionary = h._result
	var n: int = res["n"]
	var verts: PackedVector3Array = res["verts"]
	var cols: PackedColorArray = res["cols"]
	var raised := 0
	var hanging := 0
	for j in range(1, n - 1):
		for i in range(1, n - 1):
			var v := verts[j * n + i]
			var g := WorldGen.height(v.x, v.z)
			if v.y <= g + 0.2:
				continue
			raised += 1
			for dj in range(-1, 2):
				for di in range(-1, 2):
					var u := verts[(j + dj) * n + i + di]
					if u.y < v.y - 1.0 and u.y <= WorldGen.height(u.x, u.z) + 0.2:      # a DRY lower neighbour (river levels step down between water vertices)
						hanging += 1
	h.free()
	assert_int(raised).is_greater(0)
	assert_int(hanging).override_failure_message("%d horizon water vertices hang over lower neighbours" % hanging).is_equal(0)


func test_streamed_water_is_below_terrain_edges() -> void:
	WorldGen.setup(1066)
	var c := WorldGen.lake_center
	var bad := 0
	for cz in range(-3, 4):
		for cx in range(-3, 4):
			var origin := Vector2(floorf(c.x / 64.0) + cx, floorf(c.y / 64.0) + cz) * 64.0
			var mesh := WaterStreamer.build_mesh(origin)
			if mesh == null:
				continue
			var vs: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			for v in vs:
				var g := WorldGen.height(v.x, v.z)
				if v.y - g > 1.0 and not WorldGen.is_water(v.x, v.z):
					bad += 1
	assert_int(bad).override_failure_message("%d water vertices float over dry ground" % bad).is_equal(0)
