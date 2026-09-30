extends GdUnitTestSuite
## Region 1 hooks (C-H, H3-H7, C4): the save round trip through Life, the Wardlines coverage override on the
## runestone network, the Scar Tide sim (spread rules, wards, fire, harvest, save), scar goods prices, the story
## place resolver, menu hooks and the music bank entries for the area themes.

const State := preload("res://scripts/region1/region1_state.gd")
const Demo := preload("res://scripts/region1/demo_sim.gd")
const ScarTide := preload("res://scripts/region1/scar_tide.gd")
const Places := preload("res://scripts/region1/region1_places.gd")
const Economy := preload("res://scripts/sim/economy.gd")
const MusicBankRef := preload("res://scripts/audio/music_bank.gd")


func before_test() -> void:
	State.clear()
	Places.clear()


func after_test() -> void:
	State.clear()


func _roundtrip(d: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(d))


# --- H1 / H2 -------------------------------------------------------------------------

func test_life_snapshot_keeps_region1_block() -> void:
	var s := Demo.new().setup(5) as Region1Sim
	for i in 10:
		s.tick(0.5)
	State.register_sim(s)
	var before := s.digest()
	var snap: Dictionary = _roundtrip(Life.snapshot())
	assert_bool(snap.has("region1")).is_true()
	s.tick(3.0)   # diverge
	Life.restore(snap)
	assert_str(s.digest()).is_equal(before)


func test_old_save_without_region1_block_restores_defaults() -> void:
	var s := Demo.new().setup(5) as Region1Sim
	State.register_sim(s)
	var snap: Dictionary = _roundtrip(Life.snapshot())
	snap.erase("region1")
	s.tick(2.0)
	Life.restore(snap)
	assert_float(s.day_f).is_equal(0.0)


# --- H3 ------------------------------------------------------------------------------

func test_coverage_override_replaces_the_network_body() -> void:
	var net := RARunestoneNetwork.new()
	net.add_stone(Vector2(0, 0), 100.0)
	assert_float(net.coverage(Vector2(0, 0))).is_greater(0.9)
	net.coverage_override = func(_p: Vector2) -> float: return 0.25
	assert_float(net.coverage(Vector2(0, 0))).is_equal(0.25)
	net.coverage_override = Callable()
	assert_float(net.coverage(Vector2(0, 0))).is_greater(0.9)


func test_old_wear_is_off_while_wardlines_owns_it() -> void:
	var net := RARunestoneNetwork.new()
	net.add_stone(Vector2(0, 0), 100.0)
	net.coverage_override = func(_p: Vector2) -> float: return 0.0
	net.tick_day(5)
	assert_float(float(net.stones[0]["condition"])).is_equal(1.0)


# --- Scar Tide -------------------------------------------------------------------------

func _scar(seed_value := 3) -> Region1Sim:
	var s := ScarTide.new()
	s.setup(seed_value)
	s.start_day = 0
	s.season_cb = func() -> int: return 1    # summer: the fastest spread
	return s


func _run(s: Region1Sim, days: int) -> void:
	for i in days * 2:
		s.tick(0.5)


func test_scar_starts_at_the_ashen_scar_and_spreads() -> void:
	var s := _scar()
	var start: int = s.extent()
	assert_int(start).is_greater(5)
	_run(s, 60)
	assert_int(s.extent()).is_greater(start + 10)
	assert_bool(s.is_infected(Vector2(1380, 980))).is_true()


func test_scar_is_deterministic_and_saves() -> void:
	var a := _scar(7)
	var b := _scar(7)
	_run(a, 40)
	_run(b, 40)
	assert_str(a.digest()).is_equal(b.digest())
	var snap := _roundtrip(a.serialize())
	var c := ScarTide.new()
	c.setup(7)
	c.season_cb = a.season_cb
	c.deserialize(snap)
	assert_str(c.digest()).is_equal(a.digest())
	_run(a, 10)
	_run(c, 10)
	assert_str(c.digest()).is_equal(a.digest())


func test_the_tide_never_crosses_a_glowing_stone() -> void:
	var s := _scar()
	# A strong ward ring around the Scar's edge.
	s.coverage = func(p: Vector2) -> float: return 0.95 if p.distance_to(Vector2(1380, 980)) > 130.0 else 0.0
	_run(s, 150)
	for c in s.front_points(2000):
		assert_float(c.distance_to(Vector2(1380, 980))).is_less(130.0 + ScarTide.CELL)
	assert_int(s.ward_pressed.size() + s.event_log.size()).is_greater(0)


func test_weak_wards_only_slow_the_tide() -> void:
	var free := _scar(11)
	var slowed := _scar(11)
	slowed.coverage = func(_p: Vector2) -> float: return 0.4
	_run(free, 60)
	_run(slowed, 60)
	assert_int(slowed.extent()).is_less(free.extent())
	assert_int(slowed.extent()).is_greater(ScarTide.new().setup(11).extent())


func test_winter_is_a_containment_window() -> void:
	var s := _scar()
	s.season_cb = func() -> int: return 3
	var start: int = s.extent()
	_run(s, 60)
	assert_int(s.extent()).is_equal(start)


func test_nothing_spreads_before_the_start_day() -> void:
	var s := _scar()
	var start: int = s.extent()
	_run(s, 10)   # spread_after_day is 20
	assert_int(s.extent()).is_equal(start)


func test_fire_clears_cells_and_leaves_them_immune() -> void:
	var s := _scar()
	_run(s, 30)
	var centre := Vector2(1380, 980)
	var before: int = s.extent()
	var cleared: int = s.burn(centre, 70.0, 1.0)
	assert_int(cleared).is_greater(0)
	assert_int(s.extent()).is_equal(before - cleared)
	assert_bool(s.is_infected(centre)).is_false()
	# Immune for a few days: the tide cannot retake the burned cells at once.
	_run(s, 3)
	assert_bool(s.is_infected(centre)).is_false()
	assert_int(s.contained_total).is_equal(cleared)


func test_harvest_gives_crystals_once() -> void:
	var s := _scar(5)
	_run(s, 40)
	var total := 0
	for k in 3:
		var r: Dictionary = s.harvest(Vector2(1380, 980), 300.0)
		total += int(r["crystals"]) + int(r["bloom"])
	assert_int(total).is_greater(0)
	var again: Dictionary = s.harvest(Vector2(1380, 980), 300.0)
	assert_int(int(again["crystals"])).is_equal(0)


func test_outbreak_seeds_cells_where_the_story_needs_them() -> void:
	var s := _scar()
	var p := Vector2(-500, 470)
	assert_int(s.count_near(p, 140.0)).is_equal(0)
	assert_int(s.seed_at(p, 2.5, "greenhollow_south_fields")).is_greater(6)
	assert_int(s.count_near(p, 140.0)).is_greater(6)


func test_wolves_in_the_scar_become_rift_wolves() -> void:
	var s := _scar()
	assert_str(s.variant_for("wolf", Vector2(1380, 980))).is_equal("corrupted_wolf")
	assert_str(s.variant_for("wolf", Vector2(-2000, 0))).is_equal("wolf")
	var eco := RAMonsterEcology.new()
	assert_str(eco.variant_for("wolf", Vector2(1380, 980))).is_equal("wolf")   # no hook set: unchanged
	eco.variant_override = Callable(s, "variant_for")
	assert_str(eco.variant_for("wolf", Vector2(1380, 980))).is_equal("corrupted_wolf")


func test_mask_image_is_one_texel_per_cell() -> void:
	var s := _scar()
	var img: Image = s.mask_image()
	assert_int(img.get_width()).is_equal(ScarTide.N)
	var c := ScarTide.cell_of(Vector2(1380, 980))
	assert_int(int(img.get_pixel(c.x, c.y).r * 255.0)).is_greater(100)
	assert_int(int(img.get_pixel(0, 0).r * 255.0)).is_equal(0)


func test_tick_cost_stays_small() -> void:
	var s := _scar()
	_run(s, 120)
	var t0 := Time.get_ticks_usec()
	for i in 20:
		s.tick(0.5)
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0 / 20.0
	assert_float(ms).is_less(5.0)   # budget 2 ms on a quiet box; slack for CI load


# --- economy ---------------------------------------------------------------------------

func test_scar_goods_price_follows_the_size_of_the_scar() -> void:
	var eco := Economy.new()
	var town := {"id": 3, "name": "Testford", "kind": "town", "pos": Vector2.ZERO, "radius": 100.0, "population": 300}
	var m: RAMarket = eco.call("_build_market", town)
	assert_bool(m.base_price.has("scar_crystal")).is_true()
	var ctx := {"season": "spring", "festival": false, "at_war": false, "mine_opened": false}
	eco.markets[3] = m
	eco.scar_price_mult = 0.55
	eco.tick_hour(0.0, ctx)
	var cheap := m.price("scar_crystal")
	eco.scar_price_mult = 1.9
	eco.tick_hour(0.0, ctx)
	assert_int(m.price("scar_crystal")).is_greater(cheap)


func test_scar_price_mult_from_the_sim() -> void:
	var s := _scar()
	var small: float = s.price_mult()
	_run(s, 200)
	assert_float(s.price_mult()).is_less(small + 0.0001)


# --- story place resolver -----------------------------------------------------------------

func test_places_resolve_with_overrides_and_registry_fallback() -> void:
	var miller: Dictionary = Places.resolve("miller_stone")
	assert_bool(miller.is_empty()).is_false()
	Places.set_override("miller_stone", Vector2(10, 20), 15.0)
	assert_object(Places.position_of("miller_stone")).is_equal(Vector2(10, 20))
	assert_float(float(Places.resolve("miller_stone")["radius"])).is_equal(15.0)
	assert_str(Places.place_at(Vector2(12, 22))).is_equal("miller_stone")


func test_places_text_lead_is_words_not_a_marker() -> void:
	Places.set_override("miller_stone", Vector2(-200, -100), 20.0)
	var t: String = Places.lead_text(Vector2.ZERO, "miller_stone")
	assert_str(t).contains("north-west")


# --- menus and music ----------------------------------------------------------------------

func test_story_entries_reach_the_quest_tab_and_journal() -> void:
	const MD := preload("res://scripts/ui/gamemenu/menu_data.gd")
	var before := MD.extra_quests.size()
	var c := Callable(self, "_fake_quests")
	MD.extra_quests.append(c)
	var q: Dictionary = MD.quests()
	assert_int((q["active"] as Array).size()).is_greater(0)
	var found := false
	for e: Dictionary in q["active"]:
		found = found or String(e["id"]) == "fake_story"
	assert_bool(found).is_true()
	MD.extra_quests.erase(c)
	assert_int(MD.extra_quests.size()).is_equal(before)


func _fake_quests() -> Dictionary:
	return {"active": [{"id": "fake_story", "title": "T", "subtitle": "", "desc": "", "group": "main", "state": "active",
		"objectives": [], "rewards": [], "pos": null, "tracked": false, "source": "region1"}], "completed": [], "failed": []}


func test_music_bank_knows_the_region_1_themes() -> void:
	for clip: StringName in [&"r1_village_day", &"r1_guild_town", &"r1_highwatch_keep", &"r1_forest_glade", &"r1_rift_wilds",
			&"r1_night", &"r1_boss_warden", &"r1_lament", &"r1_kindling", &"r1_finale"]:
		assert_bool(MusicBankRef.CLIPS.has(clip)).is_true()
		assert_bool(MusicBankRef.MOODS.has(clip)).is_true()
	assert_bool(bool(MusicBankRef.CLIPS[&"r1_finale"][3])).is_false()   # the finale plays once


func test_story_cue_switches_the_mood_and_ignores_unknown_cues() -> void:
	Audio.set_story_cue("r1_lament")
	assert_str(String(Audio.story_cue())).is_equal("r1_lament")
	Audio.set_story_cue("not_a_cue")
	assert_str(String(Audio.story_cue())).is_equal("")
	Audio.set_story_cue("silence")
	assert_str(String(Audio.story_cue())).is_equal("silence")
	Audio.set_story_cue("")


func test_new_story_items_exist() -> void:
	for id in ["wardwright_chisel", "sunstone_oil", "scar_crystal", "scarbloom", "maren_staff", "rowan_lance", "anchor_stone",
			"elder_keystone_shard", "heirloom_blade", "heirloom_lantern"]:
		assert_bool(Life.inventory != null).is_true()
		assert_bool(Life.item_prop(id, "name", "") != "").is_true()
