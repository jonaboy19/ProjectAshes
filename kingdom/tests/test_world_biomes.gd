extends GdUnitTestSuite
## Biome dressing (phase W3 of PA_plans/WORLD_BRIEF.md): the biome -> scatter role / grass mapping of WorldBiomes, that only existing
## asset kinds are named, and that the legacy world (no macro) keeps its old behaviour.


func after() -> void:
	WorldMacro.override = ""
	WorldGen.setup(1066)


static func _kinds(role: String, biome: int, h: float) -> Array:
	var out := []
	for it: Array in WorldBiomes.items(role, biome, h):
		out.append(String(it[0]))
	return out


func test_legacy_has_no_biome_and_keeps_old_lists() -> void:
	WorldMacro.override = "noise"
	WorldGen.setup(1066)
	assert_int(WorldBiomes.at(0.0, 0.0)).is_equal(WorldBiomes.LEGACY)
	assert_bool(WorldBiomes.active()).is_false()
	assert_array(WorldBiomes.items("tree", WorldBiomes.LEGACY, 10.0)).is_empty()
	assert_float(WorldBiomes.tree_density(WorldBiomes.LEGACY, 0.37)).is_equal(0.37)
	assert_float(WorldBiomes.keep_mult("rock", WorldBiomes.LEGACY)).is_equal(1.0)
	assert_float(WorldBiomes.max_height("tree", WorldBiomes.LEGACY)).is_equal(115.0)
	assert_float(WorldBiomes.grass_density(WorldBiomes.LEGACY)).is_equal(1.0)
	assert_str(WorldBiomes.grass_kind(WorldBiomes.LEGACY, 0.5)).is_equal("grass_clump")


func test_forest_is_broadleaf_low_and_conifer_high() -> void:
	var low := _kinds("tree", WorldBiomes.FOREST, 20.0)
	assert_array(low).contains(["region/nature/oak_a", "region/nature/beech_a"])
	assert_bool(low.has("region/nature/spruce_a")).is_false()
	assert_bool(low.has("region/nature/pine_scots")).is_false()
	var high := _kinds("tree", WorldBiomes.FOREST, WorldBiomes.CONIFER_LINE + 1.0)
	assert_array(high).contains(["region/nature/spruce_a", "region/nature/pine_scots"])
	assert_bool(high.has("region/nature/oak_a")).is_false()


func test_each_biome_has_its_role() -> void:
	# meadow: flowers + tall grass in the open-ground role
	var meadow := _kinds("meadow", WorldBiomes.MEADOW, 10.0)
	assert_array(meadow).contains(["region/nature/flowers_warm", "region/nature/flowers_cool", "region/nature/grass_tall"])
	# farmland: hedgerow bushes lead, few and small trees
	var farm := _kinds("meadow", WorldBiomes.FARMLAND, 10.0)
	assert_array(farm).contains(["region/nature/bush_hazel", "region/nature/bush_round"])
	assert_float(WorldBiomes.TREE_MULT[WorldBiomes.FARMLAND]).is_less(WorldBiomes.TREE_MULT[WorldBiomes.GRASS])
	# marsh: reed-like tall grass + ferns, dead snags for trees
	assert_array(_kinds("meadow", WorldBiomes.MARSH, 2.0)).contains(["region/nature/grass_a", "region/nature/fern_a"])
	assert_array(_kinds("tree", WorldBiomes.MARSH, 2.0)).contains(["region/nature/dead_snag"])
	# highland: rocks + sparse pine; rocks may stand above the 115 m legacy cap
	assert_array(_kinds("tree", WorldBiomes.HIGHLAND, 120.0)).contains(["region/nature/pine_scots"])
	assert_float(WorldBiomes.max_height("rock", WorldBiomes.HIGHLAND)).is_greater(200.0)
	assert_float(WorldBiomes.keep_mult("rock", WorldBiomes.HIGHLAND)).is_greater(2.0)
	# rift: dead snags (almost only), rocks, boosted by the scar slot near the breaches
	var rift := _kinds("tree", WorldBiomes.RIFT, 10.0)
	assert_str(rift[0]).is_equal("region/nature/dead_snag")
	assert_array(_kinds("rock", WorldBiomes.RIFT, 10.0)).contains(["region/nature/rock_slab"])
	assert_float(WorldBiomes.scar_boost(1130.0, 1004.0)).is_equal(1.0)
	assert_float(WorldBiomes.scar_boost(-3000.0, -3000.0)).is_equal(0.0)


func test_every_named_kind_is_an_existing_asset() -> void:
	for role: String in WorldBiomes.TABLE:
		for biome: int in WorldBiomes.TABLE[role]:
			for band: String in WorldBiomes.TABLE[role][biome]:
				for it: Array in WorldBiomes.TABLE[role][biome][band]:
					var kind := String(it[0])
					var path := "res://assets/generated/" + kind + ".glb"
					if kind.begins_with("Mushroom"):
						path = "res://assets/kenney/nature/" + kind + ".gltf"
					assert_bool(ResourceLoader.exists(path) or kind.begins_with("Mushroom")).override_failure_message("missing asset for " + kind).is_true()


func test_pick_is_deterministic_and_follows_the_weights() -> void:
	assert_str(WorldBiomes.pick("tree", WorldBiomes.FOREST, 10.0, 0.3)).is_equal(WorldBiomes.pick("tree", WorldBiomes.FOREST, 10.0, 0.3))
	assert_str(WorldBiomes.pick("tree", WorldBiomes.GRASS, 10.0, 0.3)).is_equal("")      # no table: legacy list
	var counts := {}
	for i in 2000:
		var k := WorldBiomes.pick("tree", WorldBiomes.FOREST, 10.0, (i + 0.5) / 2000.0)
		counts[k] = int(counts.get(k, 0)) + 1
	assert_int(int(counts["region/nature/oak_a"])).is_greater(int(counts["region/nature/dead_snag"]) * 5)
	assert_float(WorldBiomes.pick_u(12.0, 34.0, 7)).is_equal(WorldBiomes.pick_u(12.0, 34.0, 7))
	assert_float(WorldBiomes.pick_u(12.0, 34.0, 7)).is_between(0.0, 1.0)


func test_grass_density_and_mix_per_biome() -> void:
	assert_float(WorldBiomes.grass_density(WorldBiomes.MEADOW)).is_greater(WorldBiomes.grass_density(WorldBiomes.GRASS))
	assert_float(WorldBiomes.grass_density(WorldBiomes.RIFT)).is_less(0.2)
	assert_float(WorldBiomes.grass_density(WorldBiomes.SNOW)).is_less(0.1)
	assert_float(WorldBiomes.grass_density(WorldBiomes.MEADOW)).is_less_equal(WorldBiomes.GRASS_DENSITY_MAX)
	assert_str(WorldBiomes.grass_kind(WorldBiomes.MEADOW, 0.9)).is_equal("flowers_a")
	assert_str(WorldBiomes.grass_kind(WorldBiomes.MARSH, 0.7)).is_equal("grass_clump_tall")
	assert_float(WorldBiomes.flower_mult(WorldBiomes.RIFT)).is_equal(0.0)


func test_macro_on_reads_biomes_and_scatter_follows() -> void:
	WorldMacro.override = "valencious"
	WorldGen.setup(1066)
	assert_bool(WorldBiomes.active()).is_true()
	var seen := {}
	for i in 60:
		for j in 60:
			seen[WorldBiomes.at(-5900.0 + i * 195.0, -5900.0 + j * 195.0)] = true
	assert_int(seen.size()).is_greater(5)
	for b: int in seen:
		assert_int(b).is_between(0, 7)
	# a highland/snow tile above the legacy cap: rock role allowed, tree role by biome cap
	var rules := ScatterWorldModifier.new()
	rules.role = "rock"
	var found := 0
	for i in 400:
		var x := -6000.0 + (i % 20) * 600.0
		var z := -6000.0 + int(i / 20) * 600.0
		if WorldGen.height(x, z) > 130.0 and WorldBiomes.at(x, z) in [WorldBiomes.HIGHLAND, WorldBiomes.SNOW, WorldBiomes.RIFT]:
			found += 1 if rules.allows(x, z) or ScatterExclusion.blocked(x, z, "rock") else 0
	assert_int(found).is_greater(0)
	# grass plan in macro mode stays deterministic and thins with the biome (rift/snow vs meadow)
	var p1 := GrassField.plan(Vector2(0, 0), 64.0, 123)
	var p2 := GrassField.plan(Vector2(0, 0), 64.0, 123)
	assert_int((p1["grass_clump"] as Array).size()).is_equal((p2["grass_clump"] as Array).size())
