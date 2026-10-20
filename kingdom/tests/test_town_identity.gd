extends GdUnitTestSuite
## Per-settlement visual identity (scripts/world/town_identity.gd, data/world/town_identity.json): every town has a profile, no two towns
## look alike (pairwise distinctness), the layout shapes, roof mixes, colour language and street-activity bias really differ, and the
## builder applies the palette without extra draws. VERTICAL_SLICE: "recognise a settlement without reading its name".

const TownIdentity := preload("res://scripts/world/town_identity.gd")
const MicroEvents := preload("res://scripts/population/micro_events.gd")

const THRESHOLD := 0.2


func before() -> void:
	WorldGen.setup(1066)


func _town(name: String) -> Dictionary:
	for s in WorldGen.settlements:
		if s["name"] == name:
			return s
	return {}


func test_every_settlement_has_a_profile() -> void:
	assert_int(WorldGen.settlements.size()).is_greater_equal(30)
	var arches: Array = TownIdentity.data()["archetypes"].keys()
	for s in WorldGen.settlements:
		var p := TownIdentity.profile(s)
		assert_str(String(p["name"])).is_equal(String(s["name"]))
		assert_bool(arches.has(p["arch"])).override_failure_message("%s: unknown archetype %s" % [s["name"], p["arch"]]).is_true()
		assert_bool(TownIdentity.ROOF_KINDS.has(p["roof_main"])).is_true()
		assert_bool(TownIdentity.WALL_STYLES.has(p["wall"])).is_true()
		assert_bool(TownIdentity.LAYOUT_KINDS.has(p["layout"])).is_true()
		assert_bool((p["cloth"] as Array).size() >= 3).override_failure_message("%s has no clothing palette" % s["name"]).is_true()
		assert_bool(["village", "hamlet", "town", "frontier", "castle"].has(p["size"])).is_true()


func test_no_two_towns_look_alike() -> void:
	var rep := TownIdentity.report(WorldGen.settlements, THRESHOLD)
	assert_int((rep["violations"] as Array).size()).override_failure_message("towns too similar: %s" % str(rep["violations"])).is_equal(0)
	assert_float(float(rep["min_distance"])).is_greater_equal(THRESHOLD)
	assert_float(float(rep["mean_distance"])).is_greater(0.4)


func test_distance_is_symmetric_and_zero_for_self() -> void:
	var a := TownIdentity.profile(_town("Ashford"))
	var b := TownIdentity.profile(_town("Skarholm"))
	assert_float(TownIdentity.distance(a, a)).is_equal(0.0)
	assert_float(TownIdentity.distance(a, b)).is_equal_approx(TownIdentity.distance(b, a), 0.0001)
	assert_float(TownIdentity.distance(a, b)).is_greater(0.4)


func test_kits_and_yards_reference_real_assets() -> void:
	var seen := {}
	for s in WorldGen.settlements:
		for sp: Dictionary in TownIdentity.profile(s)["dress"]:
			seen[String(sp["id"])] = true
	assert_int(seen.size()).is_greater(20)
	for id: String in seen:
		assert_object(TownIdentity.mesh_by_id(id)).override_failure_message("kit prop '%s' has no mesh" % id).is_not_null()
	for id: String in ["g:region/mine/mine_winch", "g:region/mine/mine_cart", "g:region/mine/rail_straight", "g:region/mine/miners_hut",
			"g:region/road/toll_booth", "g:region/ruins/bandit_palisade", "g:region/nature/oak_a", "g:region/nature/bush_round", "g:runestone", "g:rowboat", "g:pier", "watchtower", "mill", "stable"]:
		assert_object(TownIdentity.mesh_by_id(id)).override_failure_message("yard piece '%s' has no mesh" % id).is_not_null()


func test_kingsreach_keeps_the_reference_look() -> void:
	var p := TownIdentity.profile(_town("Kingsreach"))
	assert_bool(bool(p["legacy"])).is_true()
	assert_str(String(p["wall"])).is_equal("stone")
	assert_str(String(p["layout"])).is_equal("royal")
	assert_bool((p["lay"] as Dictionary).is_empty()).is_true()
	assert_object(TownIdentity.mesh_variant(p, "banner_pole")).is_null()     # stock crown banners
	assert_array(p["dress"]).is_empty()


func _count_roof(plan: Dictionary, group: String) -> int:
	var n := 0
	for lot: Dictionary in plan["lots"]:
		if TownIdentity.roof_of(String(lot["asset"])) == group:
			n += 1
	return n


func test_roof_mix_follows_the_profile() -> void:
	var ash: Dictionary = _town("Ashford")["plan"]
	var ironmarch: Dictionary = _town("Ironmarch")["plan"]
	var thatch_ash := float(_count_roof(ash, "thatch")) / float((ash["lots"] as Array).size())
	var thatch_iron := float(_count_roof(ironmarch, "thatch")) / float((ironmarch["lots"] as Array).size())
	var tall_ash := float(_count_roof(ash, "tall")) / float((ash["lots"] as Array).size())
	var tall_iron := float(_count_roof(ironmarch, "tall")) / float((ironmarch["lots"] as Array).size())
	assert_float(thatch_ash).is_greater(thatch_iron + 0.2)
	assert_float(tall_iron).is_greater(tall_ash + 0.15)


func _extent(plan: Dictionary, axis: Vector2) -> Vector2:
	# (extent along the road axis, extent across it) of the lots
	var c: Vector2 = plan["centre"]
	var n := Vector2(-axis.y, axis.x)
	var along := 0.0
	var across := 0.0
	for lot: Dictionary in plan["lots"]:
		var v: Vector2 = (lot["pos"] as Vector2) - c
		along = maxf(along, absf(v.dot(axis)))
		across = maxf(across, absf(v.dot(n)))
	return Vector2(along, across)


func test_layout_shapes_differ() -> void:
	# Mining towns are strung along their road: long and narrow.
	for name: String in ["Skarholm", "Stonehollow", "Cindermoor"]:
		var plan: Dictionary = _town(name)["plan"]
		var ext := _extent(plan, TownIdentity.main_axis(plan["gates"]))
		assert_float(ext.x).override_failure_message("%s along %s across %s" % [name, ext.x, ext.y]).is_greater(ext.y * 1.15)
	# A radial crossroads market town is round.
	var iron: Dictionary = _town("Ironmarch")["plan"]
	var e2 := _extent(iron, TownIdentity.main_axis(iron["gates"]))
	assert_float(e2.y).is_greater(e2.x * 0.6)
	# Farming villages are loose: well under the 31-34 homes the same village had when every town used one layout.
	assert_int((_town("Millbrook")["plan"]["lots"] as Array).size()).is_less(31)
	assert_int((_town("Ironmarch")["plan"]["lots"] as Array).size()).is_greater(100)
	# Religious towns put the temple (a bell tower in a village) at the heart of a big close.
	for name: String in ["Westfen", "Amberley"]:
		var s := _town(name)
		var plan: Dictionary = s["plan"]
		var lm_pos := Vector2.INF
		for lm: Dictionary in plan["landmarks"]:
			if String(lm["asset"]) in ["temple", "bell_tower"]:
				lm_pos = lm["pos"]
		assert_float(lm_pos.distance_to(s["pos"])).is_less(1.0)
	# Scholarly towns get an academy hall; back-alley towns narrow lanes.
	var acad := false
	for lm: Dictionary in _town("Emberfall")["plan"]["landmarks"]:
		acad = acad or String(lm["asset"]) == "chapel"
	assert_bool(acad).is_true()


func test_every_lot_still_fits_its_town() -> void:
	for s in WorldGen.settlements:
		var plan: Dictionary = s["plan"]
		assert_int((plan["lots"] as Array).size()).override_failure_message("%s has %d lots" % [s["name"], (plan["lots"] as Array).size()]).is_greater(6)
		var r := float(plan["wall_radius"])
		for lot: Dictionary in plan["lots"]:
			assert_float((lot["pos"] as Vector2).distance_to(s["pos"])).is_less(r)
			assert_bool(CityPlanner.fits(String(lot["asset"]), lot["pos"], lot["yaw"], s["pos"], r, plan["walls"], plan["inner_wall"], plan["landmarks"])).override_failure_message("%s: %s does not fit" % [s["name"], lot["asset"]]).is_true()


func test_colour_language_differs() -> void:
	var names := []
	var banners := {}
	for s in WorldGen.settlements:
		var p := TownIdentity.profile(s)
		var key := "%s/%s" % [(p["banner"][0] as Color).to_html(false), (p["banner"][1] as Color).to_html(false)]
		banners[key] = true
		names.append(p["name"])
	assert_int(banners.size()).is_greater_equal(28)       # almost every town flies its own colours
	var a := TownIdentity.profile(_town("Redwater"))
	var b := TownIdentity.profile(_town("Highcliff"))
	var m1 := TownIdentity.mesh_variant(a, "banner_pole")
	var m2 := TownIdentity.mesh_variant(b, "banner_pole")
	assert_object(m1).is_not_null()
	assert_bool(m1 != m2).is_true()
	assert_bool(TownIdentity.mesh_variant(a, "banner_pole") == m1).is_true()          # cached: towns share by colour
	assert_object(TownIdentity.mesh_variant(a, "d:striped_awning")).is_not_null()
	assert_object(TownIdentity.mesh_variant(a, "wall_banner")).is_not_null()
	assert_object(TownIdentity.mesh_variant(a, "bunting")).is_not_null()
	# Guard uniforms differ town to town; a criminal town is shabbier than a merchant one.
	assert_bool((a["guard"] as Color) != (b["guard"] as Color)).is_true()
	var lot := {"seed": 77, "wealth": 0.3}
	var shabby := TownIdentity.lot_tint(TownIdentity.profile(_town("Marrowick")), lot)
	var neat := TownIdentity.lot_tint(TownIdentity.profile(_town("Ironmarch")), lot)
	assert_float(shabby.get_luminance()).is_less(neat.get_luminance() - 0.1)


func test_street_activity_and_guards_follow_identity() -> void:
	var farm := TownIdentity.activity_bias(_town("Millbrook")["id"])
	var trade := TownIdentity.activity_bias(_town("Ironmarch")["id"])
	var mine := TownIdentity.activity_bias(_town("Skarholm")["id"])
	var crime := TownIdentity.activity_bias(_town("Marrowick")["id"])
	assert_float(float(farm.get("hay_wagon", 1.0))).is_greater(1.5)
	assert_float(float(trade.get("hay_wagon", 1.0))).is_less(1.0)
	assert_float(float(trade.get("caravan_arrival", 1.0))).is_greater(1.5)
	assert_float(float(mine.get("wood_cart", 1.0))).is_greater(1.5)
	assert_float(float(crime.get("thief_running", 1.0))).is_greater(1.5)
	assert_float(float(crime.get("soldiers_marching", 1.0))).is_less(0.6)
	# micro_events reads it: a boosted id weighs more in the same situation.
	var entry := MicroEvents.entry_of("cart_through")
	var base_ctx := MicroEvents.make_context(10.0, 3, "market", false, {})
	var boosted := MicroEvents.make_context(10.0, 3, "market", false, {}, "town", {"town_bias": {"cart_through": 2.0}})
	assert_float(MicroEvents.weight_of(entry, boosted)).is_equal_approx(MicroEvents.weight_of(entry, base_ctx) * 2.0, 0.0001)
	# Guards: fortress towns draw more, criminal towns fewer.
	var fort := _town("Highcliff")
	var crim := _town("Marrowick")
	var more := 0
	var fewer := 0
	for i in 600:
		if TownIdentity.adjust_job(4, fort, i) == 3:
			more += 1
		if TownIdentity.adjust_job(3, crim, i) == 4:
			fewer += 1
	assert_int(more).is_greater(5)
	assert_int(fewer).is_greater(100)
	assert_int(TownIdentity.adjust_job(3, _town("Kingsreach"), 5)).is_equal(3)


func test_people_tint_follows_town() -> void:
	var guard_a := TownIdentity.person_tint(_town("Redwater")["id"], 11, true)
	var guard_b := TownIdentity.person_tint(_town("Blackwater")["id"], 11, true)
	assert_bool((guard_a[0] as Color) != (guard_b[0] as Color)).is_true()
	assert_float(float(guard_a[1])).is_greater(0.4)
	var civ := TownIdentity.person_tint(_town("Redwater")["id"], 12, false)
	assert_float(float(civ[1])).is_between(0.2, 0.45)
	assert_float(float(TownIdentity.person_tint(_town("Kingsreach")["id"], 12, false)[1])).is_equal(0.0)


## House batches only (the ones that receive wall decals): ivy and market goods carry a per-instance colour jitter in every town
## (Style G), tinted by the profile or not.
func _tinted_batches(root: Node3D) -> int:
	var n := 0
	for m in root.find_children("*", "MultiMeshInstance3D", true, false):
		var mmi := m as MultiMeshInstance3D
		if mmi.multimesh != null and mmi.multimesh.use_colors and (mmi.layers & TownDecals.WALL_LAYER) != 0:
			n += 1
	return n


## The builder tints houses with the palette (MultiMesh colours, no extra draws) except in the legacy-look capital, and builds the
## wall style and a yard that carry the dominant industry.
func test_builder_applies_the_profile() -> void:
	var sb := SettlementBuilder.new()
	add_child(sb)
	auto_free(sb)
	var skar := _town("Skarholm")
	var root: Node3D = sb._build(skar, true)
	assert_int(_tinted_batches(root)).is_greater(2)
	var winch := 0
	var rails := 0
	for m in root.find_children("*", "MultiMeshInstance3D", true, false):
		var mm := (m as MultiMeshInstance3D).multimesh
		if mm.mesh != null and mm.mesh == TownIdentity.mesh_by_id("g:region/mine/mine_winch"):
			winch += 1
		if mm.mesh != null and mm.mesh == TownIdentity.mesh_by_id("g:region/mine/rail_straight"):
			rails += 1
	assert_int(winch + rails).override_failure_message("Skarholm has no mine yard (winch %d, rails %d)" % [winch, rails]).is_greater(0)
	var king := _town("Kingsreach")
	var kroot: Node3D = sb._build(king, true)
	assert_int(_tinted_batches(kroot)).is_equal(0)
	# Wall styles: a palisade town gets palisade pieces and colliders, a stone one the stone ring.
	var grey := _town("Greywatch")
	var groot: Node3D = sb._build(grey, true)
	var pal := 0
	for m in groot.find_children("*", "MultiMeshInstance3D", true, false):
		var mm2 := (m as MultiMeshInstance3D).multimesh
		if mm2.mesh == TownIdentity.mesh_by_id("g:region/ruins/bandit_palisade"):
			pal += mm2.instance_count
	assert_int(pal).is_greater(30)


func test_villages_have_unique_signatures() -> void:
	var rep := TownIdentity.report(WorldGen.settlements, THRESHOLD)
	assert_int(int(rep["villages"])).is_greater_equal(15)
	assert_int((rep["village_violations"] as Array).size()).override_failure_message("villages too similar: %s" % str(rep["village_violations"])).is_equal(0)
	assert_float(float(rep["village_min_distance"])).is_greater_equal(TownIdentity.VILLAGE_THRESHOLD)
	var seen := {}
	for r: Dictionary in rep["rows"]:
		if String(r["street"]) == "":
			continue
		assert_bool(TownIdentity.VILLAGE_STREETS.has(r["street"])).is_true()
		var key := ",".join(PackedStringArray(r["features"]))
		assert_bool(seen.has(key)).override_failure_message("%s repeats the feature set %s" % [r["name"], key]).is_false()
		seen[key] = true
