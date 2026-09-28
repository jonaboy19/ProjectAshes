extends GdUnitTestSuite
## The world map: region data, known-from-start places, the discovered counter, fog of
## war, the painted terrain bake and view coordinates. (The drawing itself is checked by
## rendering screenshots, see the ashes-visual-qa skill.)

const WorldMap := preload("res://scripts/ui/world_map.gd")
const Discovery := preload("res://scripts/sim/discovery.gd")


func before() -> void:
	WorldGen.setup(1066)


func _discovery() -> RefCounted:
	var d := Discovery.new()
	d.build_from_world()
	return d


func _find(d: RefCounted, place_name: String) -> Dictionary:
	for pl: Dictionary in d.places:
		if pl["name"] == place_name:
			return pl
	return {}


func test_regions_data_defines_current_region_and_unexplored_neighbours() -> void:
	var data := WorldMap.load_regions()
	var cur: Dictionary = {}
	var placeholders := 0
	for r: Dictionary in data["regions"]:
		if r["id"] == data["current"]:
			cur = r
	assert_bool(cur.is_empty()).override_failure_message("current region missing").is_false()
	var b: Rect2 = cur["bounds"]
	assert_bool(b.has_point(Vector2.ZERO)).is_true()
	assert_float(b.size.x).is_greater_equal(WorldGen.WORLD_HALF * 2.0)
	for r: Dictionary in data["regions"]:
		if r["id"] == cur["id"]:
			continue
		placeholders += 1
		assert_str(String(r["name"])).is_equal("Unexplored lands")
		assert_bool((r["bounds"] as Rect2).intersects(b, false)).override_failure_message("%s overlaps the current region" % r["id"]).is_false()
	assert_int(placeholders).is_greater_equal(1)


func test_home_and_capital_and_kingdom_road_places_are_known_from_start() -> void:
	var d := _discovery()
	var known := WorldMap.known_from_start(d.places)
	assert_bool(known.has("settlement:Ashford")).is_true()
	assert_bool(known.has("settlement:Kingsreach")).is_true()
	assert_bool(known.has(_find(d, "Cinderpost Waystation")["id"])).override_failure_message("waystation on the kingdom road").is_true()
	# Hostile camps and far settlements are not given away.
	assert_bool(known.has(_find(d, "Mossfang Warren")["id"])).is_false()
	assert_bool(known.has("settlement:Millbrook")).is_false()
	assert_int(known.size()).is_between(3, 20)
	# The road path really connects home to the capital.
	var path := WorldMap.road_path_home_to_capital()
	assert_int(path.size()).is_greater_equal(1)
	assert_vector(path[path.size() - 1][0]).is_equal(WorldGen.settlements[0]["pos"])


func test_counter_counts_known_plus_discovered_and_skips_farms() -> void:
	var d := _discovery()
	var m: Control = auto_free(WorldMap.new())
	add_child(m)
	m.discovery = d
	m.refresh_model()
	var start: int = m.places_discovered()
	var total: int = m.places_total()
	assert_int(start).is_greater_equal(3)
	assert_int(total).is_greater(start)
	assert_str(WorldMap.counter_text(start, total)).is_equal("%d of %d places discovered" % [start, total])
	var countable := 0
	for pl: Dictionary in d.places:
		if String(pl["kind"]) != "farm" and String(pl["kind"]) != "wayshrine" and String(pl["kind"]) != "road":
			countable += 1
	assert_int(total).is_equal(countable)
	# Finding a far place adds exactly one.
	var far := _find(d, "Millbrook")
	assert_bool(d.discover(far["id"], 1)).is_true()
	m.refresh_model()
	assert_int(m.places_discovered()).is_equal(start + 1)
	# Finding a farm changes nothing in the counter.
	var farm := {}
	for pl: Dictionary in d.places:
		if pl["kind"] == "farm" and not m.is_place_known(pl):
			farm = pl
			break
	if not farm.is_empty():
		d.discover(farm["id"], 1)
		m.refresh_model()
		assert_int(m.places_discovered()).is_equal(start + 1)


func test_fog_field_is_clear_at_sources_and_hidden_far_away() -> void:
	var rect := Rect2(Vector2(-2048, -2048), Vector2(4096, 4096))
	var f := WorldMap.fog_field([[Vector2(0, 0), 400.0]], rect, 64)
	var mid := 32 * 64 + 32
	assert_float(f[mid]).is_equal(0.0)
	assert_float(f[0]).is_equal(1.0)
	assert_float(f[63 * 64 + 63]).is_equal(1.0)
	var none := WorldMap.fog_field([], rect, 16)
	for v in none:
		assert_float(v).is_equal(1.0)


func test_terrain_bake_paints_water_and_fades_the_border() -> void:
	var img: Image = WorldMap.paint_terrain(128)
	assert_int(img.get_width()).is_equal(128)
	assert_float(img.get_pixel(64, 64).a).is_equal(1.0)
	assert_float(img.get_pixel(0, 0).a).is_less(0.2)
	# Emberglass Mere reads blue.
	var half := WorldGen.WORLD_HALF
	var c := WorldGen.lake_center
	var px := Vector2i(int((c.x + half) / (half * 2.0) * 128.0), int((c.y + half) / (half * 2.0) * 128.0))
	var col := img.get_pixel(px.x, px.y)
	assert_float(col.b).is_greater(col.r)


func test_view_coordinates_round_trip_and_fit_shows_the_whole_region() -> void:
	var m: Control = auto_free(WorldMap.new())
	add_child(m)
	m.size = Vector2(1280, 720)
	m.fit_region()
	var p := Vector2(560, -420)
	assert_vector(m.to_world(m.to_screen(p))).is_equal_approx(p, Vector2(0.01, 0.01))
	var tl: Vector2 = m.to_screen(Vector2(-WorldGen.WORLD_HALF, -WorldGen.WORLD_HALF))
	var br: Vector2 = m.to_screen(Vector2(WorldGen.WORLD_HALF, WorldGen.WORLD_HALF))
	assert_bool(tl.x >= 0.0 and tl.y >= 0.0 and br.x <= 1280.0 and br.y <= 720.0).is_true()
	m.focus_on(Vector2(0, 0), 0.9)
	assert_vector(m.to_screen(Vector2.ZERO)).is_equal_approx(Vector2(640, 360), Vector2(0.01, 0.01))
