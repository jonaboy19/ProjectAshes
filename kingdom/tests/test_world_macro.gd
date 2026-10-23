extends GdUnitTestSuite
## World macro heightmap (phase W1 of PA_plans/WORLD_BRIEF.md): --world_macro=valencious replaces the noise inside WorldGen._raw_height with
## data/world/macro/height_16.png. Legacy (noise) must stay byte-identical; with the macro on, no settlement/camp/site may move, settlement
## pads stay flat, rivers fall downstream, nothing important is underwater, and the Terrain3D bridge still equals WorldGen.height.

var PLACES := ProjectSettings.globalize_path("res://") + "../docs/world/valencious_places.json"


func after() -> void:
	WorldMacro.override = ""
	WorldGen.setup(1066)


static func _snapshot() -> Dictionary:
	var s := {"settlements": [], "sites": [], "camps": [], "roads": WorldGen.roads.duplicate()}
	for st in WorldGen.settlements:
		s["settlements"].append([st["name"], st["pos"], st["radius"], st["kind"]])
	for si in WorldGen.sites:
		s["sites"].append([si["id"], si["name"], si["pos"], si["clear"]])
	for c in WorldGen.camp_grounds:
		s["camps"].append([c["pos"], c["radius"]])
	return s


func test_macro_file_decodes_and_samples() -> void:
	WorldMacro.override = "valencious"
	assert_bool(WorldMacro.prepare()).is_true()
	assert_int(WorldMacro.memory_bytes()).is_greater(30000000)
	var lo := 1.0e9
	var hi := -1.0e9
	for i in 400:
		var h := WorldMacro.sample(-6144.0 + i * 30.7, -6144.0 + i * 29.3)
		lo = minf(lo, h)
		hi = maxf(hi, h)
	assert_float(lo).is_greater_equal(-20.0)
	assert_float(hi).is_less_equal(300.01)
	assert_float(hi - lo).is_greater(20.0)
	# bilinear: continuous across a pixel edge
	var a := WorldMacro.sample(300.0, 300.0)
	var b := WorldMacro.sample(300.001, 300.0)
	assert_float(absf(a - b)).is_less(0.01)
	assert_int(WorldMacro.biome_at(0.0, 0.0)).is_between(0, 7)


func test_legacy_noise_is_default_and_unchanged() -> void:
	WorldMacro.override = ""
	assert_str(WorldMacro.mode()).is_equal("noise")
	WorldGen.setup(1066)
	assert_bool(WorldMacro.active).is_false()
	var h0 := WorldGen.height(0.0, 0.0)
	var h1 := WorldGen.height(900.0, -400.0)
	WorldGen.setup(1066)
	assert_float(WorldGen.height(0.0, 0.0)).is_equal(h0)
	assert_float(WorldGen.height(900.0, -400.0)).is_equal(h1)


func test_no_registered_position_moves_with_the_macro_on() -> void:
	WorldMacro.override = "noise"
	WorldGen.setup(1066)
	var legacy := _snapshot()
	WorldMacro.override = "valencious"
	WorldGen.setup(1066)
	assert_bool(WorldMacro.active).is_true()
	var macro := _snapshot()
	assert_int(macro["settlements"].size()).is_equal(30)
	assert_bool(macro["settlements"] == legacy["settlements"]).override_failure_message("a settlement moved").is_true()
	assert_bool(macro["roads"] == legacy["roads"]).override_failure_message("road topology changed").is_true()
	assert_int(macro["sites"].size()).is_equal(legacy["sites"].size())
	assert_bool(macro["sites"] == legacy["sites"]).override_failure_message("a site moved").is_true()
	assert_bool(macro["camps"] == legacy["camps"]).override_failure_message("a camp moved").is_true()


func test_all_bible_positions_unchanged_with_the_macro_on() -> void:
	WorldMacro.override = "valencious"
	WorldGen.setup(1066)
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(PLACES))
	assert_bool(data is Dictionary).is_true()
	var by_name := {}
	for st in WorldGen.settlements:
		by_name[st["name"]] = st["pos"]
	var site_pos: Array = []
	for si in WorldGen.sites:
		site_pos.append([si["name"], si["pos"]])
	var checked := 0
	var bad: Array[String] = []
	for p: Dictionary in data["places"]:
		var cat: String = p["category"]
		if cat != "settlement" and cat != "site":
			continue
		var pos := Vector2(float(p["x"]), float(p["z"]))
		if p["name"] == "Scar Mouth Arena":       # W4: one arena record, at the canon point of data/world/first_region.json (the searched 2399,2468 record is gone)
			pos = Vector2(2864.1, 2586.4)
		var found := false
		if cat == "settlement":
			found = by_name.has(p["name"]) and (by_name[p["name"]] as Vector2).distance_to(pos) < 0.2
		else:
			for sp in site_pos:
				if sp[0] == p["name"] and (sp[1] as Vector2).distance_to(pos) < 0.2:
					found = true
					break
		checked += 1
		if not found:
			bad.append(String(p["name"]))
	assert_int(checked).is_greater(280)
	assert_array(bad).override_failure_message("moved or missing: %s" % [bad.slice(0, 8)]).is_empty()


func test_settlement_pads_flat_and_dry_with_the_macro_on() -> void:
	WorldMacro.override = "valencious"
	WorldGen.setup(1066)
	for st in WorldGen.settlements:
		var p: Vector2 = st["pos"]
		var h := WorldGen.height(p.x, p.y)
		# the centre sits on the town road bed, which WorldGen.height cuts 0.4 m below the pad (legacy does the same): pad = base_h - 0.4
		assert_float(absf(h - float(st["base_h"]))).override_failure_message("%s pad %.3f vs base %.3f" % [st["name"], h, st["base_h"]]).is_less(0.45)
		for k in 6:
			var q := p + Vector2.from_angle(k * TAU / 6.0) * float(st["radius"]) * 0.4
			assert_float(absf(WorldGen.height(q.x, q.y) - float(st["base_h"]))).override_failure_message("%s pad edge %.2f off" % [st["name"], WorldGen.height(q.x, q.y) - float(st["base_h"])]).is_less(0.5)
		assert_bool(WorldGen.is_water(p.x, p.y)).override_failure_message("%s is underwater" % st["name"]).is_false()
		var ring_wet := 0
		for k in 8:
			var q := p + Vector2.from_angle(k * TAU / 8.0) * float(st["radius"]) * 0.9
			if WorldGen.is_water(q.x, q.y):
				ring_wet += 1
		assert_int(ring_wet).override_failure_message("%s has water inside its pad" % st["name"]).is_equal(0)


func test_rivers_fall_downstream_with_the_macro_on() -> void:
	WorldMacro.override = "valencious"
	WorldGen.setup(1066)
	assert_int(WorldGen.rivers.size()).is_greater_equal(3)
	for r: Dictionary in WorldGen.rivers:
		var lv: PackedFloat32Array = r["level"]
		var n := lv.size()
		assert_float(lv[0] - lv[n - 1]).override_failure_message("a river does not fall overall").is_greater(0.5)
		var rises := 0.0
		for i in range(1, n):
			rises = maxf(rises, lv[i] - lv[i - 1])
		assert_float(rises).override_failure_message("river level rises by %.3f m between samples" % rises).is_less(0.05)
	var d := WorldGen.lake_center.distance_to(Vector2(-420.0, 300.0))
	assert_float(d).is_less(1.0)
	assert_bool(WorldGen.is_water(WorldGen.lake_center.x, WorldGen.lake_center.y)).is_true()


func test_terrain3d_bridge_parity_with_the_macro_on() -> void:
	if not TerrainBackend.available():
		return
	WorldMacro.override = "valencious"
	WorldGen.setup(1066)
	var b := Terrain3DBridge.new()
	b.region_radius = 0
	add_child(b)
	var at := Vector3(900.0, 0.0, -400.0)
	b.build_all_now(at)
	var o := Terrain3DBridge.region_origin(Terrain3DBridge.region_of(at.x, at.z))
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var worst_lattice := 0.0
	var over := 0
	for i in 800:
		var x := o.x + rng.randf_range(2.0, Terrain3DBridge.REGION_M - 2.0)
		var z := o.y + rng.randf_range(2.0, Terrain3DBridge.REGION_M - 2.0)
		if absf(b.sampled_height(x, z) - WorldGen.height(x, z)) > 0.1:
			over += 1
		var lx := o.x + floorf((x - o.x) / Terrain3DBridge.SPACING) * Terrain3DBridge.SPACING
		var lz := o.y + floorf((z - o.y) / Terrain3DBridge.SPACING) * Terrain3DBridge.SPACING
		worst_lattice = maxf(worst_lattice, absf(b.sampled_height(lx, lz) - WorldGen.height(lx, lz)))
	b.queue_free()
	assert_float(worst_lattice).is_less(0.001)
	assert_float(float(over) / 800.0).is_less(0.01)
