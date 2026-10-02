extends SceneTree
const Map = preload("res://scripts/ui/world_map.gd")
const Discovery = preload("res://scripts/sim/discovery.gd")
func _initialize() -> void:
	call_deferred("_capture")
func _capture() -> void:
	WorldGen.setup(1066)
	var discovery := Discovery.new()
	discovery.build_from_world()
	var map := Map.new()
	map.discovery = discovery
	root.add_child(map)
	map.open()
	var groups: Array[Dictionary] = map._marker_groups()
	var members := 0
	for group: Dictionary in groups:
		members += int(group.count)
	var eligible := 0
	for place: Dictionary in map._shown:
		if not Map.is_area(String(place.kind)) and map._passes(place) and Rect2(Vector2(-60, -60), map.size + Vector2(120, 120)).has_point(map.to_screen(place.pos)):
			eligible += 1
	assert(members == eligible, "Clustering must preserve visible members")
	for group: Dictionary in groups:
		if int(group.count) > 1:
			var old_zoom: float = map._zoom
			map._tap(map.to_screen(group.place.pos))
			assert(map._zoom > old_zoom, "Cluster tap must zoom")
			map.fit_region()
			break
	print("MAP_CLUSTER_CHECK member conservation and cluster zoom passed")
	var deadline := Time.get_ticks_msec() + 120000
	while Map._texture == null and Time.get_ticks_msec() < deadline:
		await process_frame
	if Map._texture == null:
		push_error("Region map terrain bake timed out")
		map.close()
		quit(1)
		return
	for i in range(6):
		await process_frame
	await RenderingServer.frame_post_draw
	var out := OS.get_environment("ASHES_MAP_CAPTURE")
	if out.is_empty():
		push_error("Set ASHES_MAP_CAPTURE to an output PNG")
		map.close()
		quit(1)
		return
	var result := root.get_texture().get_image().save_png(out)
	print("REGION_MAP_CAPTURE_RESULT ", result)
	map.close()
	quit(0 if result == OK else 1)
