extends GdUnitTestSuite
## Place discovery: the place list covers settlements, region sites (not
## waystones), visible lore places and named monster camps; walking close finds
## a place once; the found set survives a JSON save round trip.

const Discovery := preload("res://scripts/sim/discovery.gd")


func before() -> void:
	WorldGen.setup(1066)


func _world() -> RefCounted:
	var d := Discovery.new()
	d.build_from_world()           # lore from data/world/first_region.json
	return d


func _find(d: RefCounted, place_name: String) -> Dictionary:
	for pl: Dictionary in d.places:
		if pl["name"] == place_name:
			return pl
	return {}


func test_places_cover_every_source() -> void:
	var d := _world()
	var cats := {}
	for pl: Dictionary in d.places:
		cats[pl["category"]] = true
		assert_str(pl["kind"]).override_failure_message("waystone listed: %s" % pl).is_not_equal("waystone")
	for c in ["settlement", "site", "camp", "lore"]:
		assert_bool(cats.has(c)).override_failure_message("no %s places (%s)" % [c, cats]).is_true()
	for s: Dictionary in WorldGen.settlements:
		# The map shows the poster name for Oakvale (Greenhollow) and Ironmarch (Silverford): Discovery.display_name().
		var shown: String = Discovery.display_name(String(s["name"]))
		assert_bool(_find(d, shown).is_empty()).override_failure_message("missing %s" % shown).is_false()
	# Camps are named after the lore places they were laid out from, and hostile.
	var warren := _find(d, "Mossfang Warren")
	assert_str(warren.get("category", "")).is_equal("camp")
	assert_bool(warren.get("hostile", false)).is_true()
	assert_bool(_find(d, "Cinderpost Waystation").get("travel", false)).is_true()


func test_hidden_and_duplicate_lore_places_are_skipped() -> void:
	var d := _world()
	assert_bool(_find(d, "Emberglass Mere").is_empty()).is_false()
	# Whisper Hollow is hidden in the lore; only the region site of that name may exist.
	for pl: Dictionary in d.places:
		assert_bool(pl["category"] == "lore" and pl["name"] == "Whisper Hollow").is_false()
	# Ashford is both a settlement and a lore place: listed once.
	var n := 0
	for pl: Dictionary in d.places:
		if pl["name"] == "Ashford":
			n += 1
	assert_int(n).is_equal(1)
	var ids := {}
	for pl: Dictionary in d.places:
		assert_bool(ids.has(pl["id"])).override_failure_message("duplicate id %s" % pl["id"]).is_false()
		ids[pl["id"]] = true


func test_walking_close_discovers_once() -> void:
	var d := Discovery.new()
	d.build([{"name": "Testholm", "pos": Vector2(0, 0), "radius": 60.0, "kind": "village"}],
		[{"name": "Old Well", "kind": "ruin", "pos": Vector2(500, 0), "clear": 0.0},
		 {"name": "Waystone", "kind": "waystone", "pos": Vector2(900, 0), "clear": 0.0}],
		[{"id": "cave", "name": "Echo Cave", "kind": "cave", "pos": [0, 800]},
		 {"id": "secret", "name": "Secret Grove", "kind": "hidden_place", "pos": [0, -800], "hidden": true}],
		[])
	assert_int(d.places.size()).is_equal(3)
	var events := []
	d.place_discovered.connect(func(pl: Dictionary) -> void: events.append(pl["name"]))
	assert_array(d.update(Vector2(300, 0), 1)).is_empty()
	assert_int(d.update(Vector2(470, 10), 2).size()).is_equal(1)    # within 40 m of the well
	assert_array(d.update(Vector2(470, 10), 2)).is_empty()          # only once
	assert_int(d.update(Vector2(55, 0), 3).size()).is_equal(1)      # inside the village radius
	assert_array(events).contains_exactly(["Old Well", "Testholm"])
	assert_bool(d.is_discovered("lore:cave")).is_false()
	assert_int(d.discovered_count()).is_equal(2)
	assert_int(d.travel_points().size()).is_equal(0)       # settlements are not fast-travel points: only waystations are
	assert_int(d.nearby(Vector2(0, 0), 600.0).size()).is_equal(2)
	assert_int(d.nearby(Vector2(0, 0), 900.0, true).size()).is_equal(3)


func test_serialize_round_trip() -> void:
	var d := _world()
	d.update(Vector2(0, 0), 4)
	var ws: Dictionary = _find(d, "Cinderpost Waystation")
	d.update(ws["pos"], 7)
	var saved: Variant = JSON.parse_string(JSON.stringify(d.serialize()))   # as a save file stores it
	var d2 := _world()
	d2.deserialize(saved)
	assert_int(d2.discovered_count()).is_equal(d.discovered_count())
	assert_bool(d2.is_discovered("settlement:Ashford")).is_true()
	assert_bool(d2.is_discovered(ws["id"])).is_true()
	assert_int(int(d2.found[ws["id"]])).is_equal(7)
	# Restored places are not found again, and an empty save clears everything.
	assert_array(d2.update(Vector2(0, 0), 9)).is_empty()
	d2.deserialize({})
	assert_int(d2.discovered_count()).is_equal(0)
