extends GdUnitTestSuite
## Region sites: farms, bridges, ruins and landmarks sit on dry, free ground,
## clear their trees, and the dressing builds every site without errors.


func before() -> void:
	WorldGen.setup(1066)


func test_sites_are_planned() -> void:
	var kinds := {}
	for s in WorldGen.sites:
		kinds[s["kind"]] = int(kinds.get(s["kind"], 0)) + 1
		print("%s %s at %s" % [s["kind"], s["name"], s["pos"]])
	for k in ["farm", "waystation", "waystone", "shrine", "hollow", "bandit_camp", "watchfort", "rift"]:
		assert_bool(kinds.has(k)).override_failure_message("missing site kind %s (%s)" % [k, kinds]).is_true()


func test_sites_are_dry_and_treeless() -> void:
	for s in WorldGen.sites:
		var p: Vector2 = s["pos"]
		if s["kind"] in ["bridge", "hollow"] or s.has("region1"):
			continue        # the look agent's landmarks (valley, ferry, drowned bell...) stand in or by water on purpose
		assert_bool(WorldGen.is_water(p.x, p.y)).override_failure_message("%s wet at %s" % [s["name"], p]).is_false()
		if float(s["clear"]) > 0.0:
			assert_float(WorldGen.forest_density(p.x, p.y)).is_equal(0.0)


func test_dressing_builds_everything() -> void:
	var d := RegionDressing.new()
	add_child(d)
	d.build_all_now()
	var in_season := 0
	for site in WorldGen.sites:
		if not site.has("season"):      # seasonal pieces (the Solkar caravans) wait for their season
			in_season += 1
	assert_int(d.built_count()).is_equal(in_season)
	d.free()
