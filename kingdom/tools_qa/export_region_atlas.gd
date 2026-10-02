extends SceneTree
## Authoring export only: contains undiscovered places. Never serve as player intelligence.
func _initialize() -> void:
	WorldGen.setup(1066)
	var towns: Array = []
	for st in WorldGen.settlements:
		var p: Vector2 = st.pos
		towns.append({"name": st.name, "kind": st.kind, "pos": [p.x, p.y], "radius": st.radius})
	var routes: Array = []
	for road in WorldGen.roads:
		routes.append([road.x, road.y])
	var river_lines: Array = []
	for river in WorldGen.rivers:
		var line: Array = []
		for p: Vector2 in river.points:
			line.append([p.x, p.y])
		river_lines.append(line)
	var sites: Array = []
	for site in WorldGen.sites:
		var p: Vector2 = site.pos
		sites.append({"name": site.name, "kind": site.kind, "pos": [p.x, p.y]})
	var heights: Array = []
	var forests: Array = []
	var waters: Array = []
	for z in range(129):
		var row: Array = []
		var forest_row: Array = []
		var water_row: Array = []
		for x in range(129):
			var wx := -WorldGen.WORLD_HALF + float(x) * WorldGen.WORLD_HALF * 2.0 / 128.0
			var wz := -WorldGen.WORLD_HALF + float(z) * WorldGen.WORLD_HALF * 2.0 / 128.0
			row.append(snappedf(WorldGen.height(wx, wz), 0.1))
			forest_row.append(snappedf(WorldGen.forest_density(wx, wz), 0.01))
			water_row.append(WorldGen.is_water(wx, wz))
		heights.append(row)
		forests.append(forest_row)
		waters.append(water_row)
	var path := OS.get_environment("ASHES_ATLAS_OUTPUT")
	if path.is_empty():
		push_error("Set ASHES_ATLAS_OUTPUT to an authoring JSON file")
		quit(1)
		return
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write atlas export")
		quit(1)
		return
	file.store_string(JSON.stringify({"seed": 1066, "bounds": [-WorldGen.WORLD_HALF, WorldGen.WORLD_HALF], "towns": towns, "roads": routes, "height_grid": heights, "forest_grid": forests, "water_grid": waters, "rivers": river_lines, "sites": sites, "lake": {"pos": [WorldGen.lake_center.x, WorldGen.lake_center.y], "radius": WorldGen.lake_radius}}, "\t"))
	print("REGION_ATLAS_EXPORTED ", towns.size(), " settlements; ", routes.size(), " roads")
	quit()
