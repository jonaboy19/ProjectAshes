extends GdUnitTestSuite
## Skills and techniques (scripts/sim/skills.gd, data/skills/*.json): data
## integrity, unlock rules, costs, cooldowns, loadout, cultivation realms and
## breakthroughs, hand seals and save/load.

const Skills := preload("res://scripts/sim/skills.gd")

## Stock clips on the UAL rig (Assets.UAL_FILES). Each technique's last
## animation choice must be one of these so it always has something to play.
const STOCK_CLIPS := ["Idle", "Interact", "Jump", "Punch_Cross", "Punch_Jab", "Roll", "Spell_Simple_Enter",
	"Spell_Simple_Exit", "Spell_Simple_Idle", "Spell_Simple_Shoot", "Sprint", "Sword_Attack", "Sword_Idle",
	"Farm_Harvest", "Farm_PlantSeed", "Farm_Watering", "Fixing_Kneeling", "Melee_Hook", "NinjaJump_Start",
	"OverhandThrow", "Slide", "Sword_Block", "Sword_Dash", "Sword_Heavy_Combo", "Sword_Regular_A",
	"Sword_Regular_B", "Sword_Regular_C", "Sword_Regular_Combo", "TreeChopping", "Attack_Ground_Pound",
	"Backflip", "Bow_Release", "Meditate", "Sword_Attack_Air_Vertical", "Throw_Object", "Cheering_Two_Hands",
	"Kick_Breach", "Salute", "Angry", "G6_cast_unarmed_magic", "G6_cast_unarmed_magic_2",
	"G6_channel_unarmed_magic", "G6_channel_two_handed_staff", "G6_cast_two_handed_staff",
	"G6_cast_two_handed_melee_3", "G6_cast_off_hand_shield", "G6_power_up", "G6_power_up_2", "G6_power_up_3",
	"G6_pray"]
const TREES := ["swordsmanship", "fist_palm", "fire", "water", "wind", "earth", "lightning", "qi", "shadow",
	"iaido", "command", "crafting", "farming"]


func _ctx(level := 1, sects := [], titles := {}, flags := {}) -> Dictionary:
	return {"level": level, "titles": titles, "flags": flags, "sects": sects}


func _fresh() -> Skills:
	return Skills.new()


# --- data ------------------------------------------------------------------------

func test_data_loads_every_tree_and_validates() -> void:
	var s := _fresh()
	for tid: String in TREES:
		assert_bool(s.trees.has(tid)).override_failure_message("missing tree " + tid).is_true()
		assert_int((s.trees[tid]["techniques"] as Array).size()).is_greater_equal(5)
	assert_array(s.validate()).is_empty()
	assert_int(s.realms.size()).is_greater_equal(8)
	assert_str(s.realm_name(1)).is_equal("Qi Condensation")
	assert_str(s.realm_name(2)).is_equal("Foundation Establishment")
	assert_str(s.realm_name(3)).is_equal("Core Formation")


func test_every_active_has_cost_cooldown_clip_and_vfx() -> void:
	var s := _fresh()
	for id: String in s.techniques:
		var d: Dictionary = s.techniques[id]
		if d["kind"] != "active":
			continue
		assert_bool(d["resource"] in Skills.RESOURCES).override_failure_message(id).is_true()
		assert_float(float(d["cooldown"])).override_failure_message(id).is_greater(0.0)
		assert_str(String(d["vfx"])).override_failure_message(id + " has no vfx id").is_not_empty()
		var anims: Array = d["anims"]
		assert_bool(STOCK_CLIPS.has(anims[anims.size() - 1])) \
			.override_failure_message("%s falls back to unknown clip %s" % [id, anims[anims.size() - 1]]).is_true()


# --- points & unlocks --------------------------------------------------------------

func test_points_from_level_sect_and_titles_are_credited_once() -> void:
	var s := _fresh()
	s.sync_progress(_ctx(5))
	assert_int(s.points).is_equal(Skills.points_for_level(5))
	s.sync_progress(_ctx(5))
	assert_int(s.points).is_equal(Skills.points_for_level(5))
	s.sync_progress(_ctx(6, ["iron_lotus_monastery"], {"iron_body": 3}))
	assert_int(s.points).is_equal(Skills.points_for_level(6) + Skills.SECT_POINTS + Skills.TITLE_POINTS)
	s.sync_progress(_ctx(6, ["iron_lotus_monastery"], {"iron_body": 3}))
	assert_int(s.points).is_equal(Skills.points_for_level(6) + Skills.SECT_POINTS + Skills.TITLE_POINTS)
	assert_int(Skills.points_for_level(10)).is_equal(9 + 2)


func test_prerequisites_and_level_gate() -> void:
	var s := _fresh()
	s.points = 20
	var c := s.check("fire_pillar", _ctx(1))
	assert_bool(c["ok"]).is_false()
	assert_bool(s.learn("fire_pillar", _ctx(10))["ok"]).is_false()
	for id: String in ["fire_ember_orb", "fire_kindled_heart", "fire_flame_wave"]:
		assert_bool(s.learn(id, _ctx(10))["ok"]).override_failure_message(id).is_true()
	assert_str(" ".join(PackedStringArray(s.check("fire_pillar", _ctx(3))["reasons"]))).contains("level 6")
	assert_bool(s.learn("fire_pillar", _ctx(6))["ok"]).is_true()
	assert_int(s.points).is_equal(16)


func test_sect_realm_title_and_manual_gates() -> void:
	var s := _fresh()
	s.points = 50
	for id: String in ["fire_ember_orb", "fire_kindled_heart", "fire_flame_wave", "fire_pillar"]:
		s.grant(id)
	# Sect + realm.
	assert_bool(s.can_learn("fire_dawnflame_nova", _ctx(20))).is_false()
	s.realm = 2
	assert_bool(s.can_learn("fire_dawnflame_nova", _ctx(20))).is_false()
	assert_bool(s.can_learn("fire_dawnflame_nova", _ctx(20, ["dawnflame_seminary"]))).is_true()
	s.learn("fire_dawnflame_nova", _ctx(20, ["dawnflame_seminary"]))
	# Title.
	s.realm = 3
	assert_bool(s.can_learn("fire_phoenix_core", _ctx(20))).is_false()
	assert_bool(s.can_learn("fire_phoenix_core", _ctx(20, [], {"ash_walker": 1}))).is_true()
	# Manual found in the world.
	for id: String in ["sword_rising_cut", "sword_steady_grip", "sword_whirl", "sword_qi_crescent"]:
		s.grant(id)
	assert_bool(s.can_learn("sword_heaven_splitter", _ctx(20))).is_false()
	var before := s.points
	var r := s.read_manual("manual_heaven_splitting", 12)
	assert_bool(r["ok"]).is_true()
	assert_int(s.points).is_equal(before + 1)
	assert_bool(s.can_learn("sword_heaven_splitter", _ctx(20))).is_true()
	assert_bool(s.read_manual("manual_heaven_splitting", 13)["ok"]).is_false()


func test_granting_manual_teaches_for_free() -> void:
	var s := _fresh()
	s.read_manual("manual_basic_breathing")
	assert_bool(s.is_learned("qi_gathering")).is_true()
	assert_int(s.points).is_equal(1)


func test_hidden_technique_appears_only_after_its_trigger() -> void:
	var s := _fresh()
	s.grant("fire_ember_orb")
	assert_bool(s.is_visible("fire_ember_step", _ctx(5))).is_false()
	assert_bool(s.can_learn("fire_ember_step", _ctx(5))).is_false()
	var awakened := _ctx(5, [], {}, {"ability:ember_step": true})
	assert_bool(s.is_visible("fire_ember_step", awakened)).is_true()
	assert_bool(s.can_learn("fire_ember_step", awakened)).is_true()   # 0 points
	assert_bool(s.learn("fire_ember_step", awakened)["ok"]).is_true()


func test_ranks_cost_points_and_cap() -> void:
	var s := _fresh()
	s.points = 3
	for i in 3:
		assert_bool(s.learn("fire_ember_orb", _ctx(1))["ok"]).is_true()
	assert_int(s.rank_of("fire_ember_orb")).is_equal(3)
	assert_int(s.points).is_equal(0)
	s.points = 5
	var r := s.learn("fire_ember_orb", _ctx(1))
	assert_bool(r["ok"]).is_false()
	assert_str(r["text"]).contains("Mastered")
	assert_int(s.points).is_equal(5)


# --- casting -----------------------------------------------------------------------

func test_costs_are_checked_and_paid() -> void:
	var s := _fresh()
	s.grant("fire_ember_orb")      # 5 magicules
	s.grant("sword_rising_cut")    # 14 stamina
	s.grant("qi_bolt")             # 10 qi
	assert_bool(s.can_cast("fire_ember_orb", {"magicules": 2.0})["ok"]).is_false()
	assert_bool(s.can_cast("sword_rising_cut", {"stamina": 13.0})["ok"]).is_false()
	var r := s.begin_cast("sword_rising_cut", {"stamina": 50.0})
	assert_bool(r["ok"]).is_true()
	assert_str(r["resource"]).is_equal("stamina")
	assert_float(r["cost"]).is_equal(14.0)
	s.qi = 5.0
	assert_bool(s.can_cast("qi_bolt")["ok"]).is_false()
	s.qi = 15.0
	assert_bool(s.begin_cast("qi_bolt")["ok"]).is_true()
	assert_float(s.qi).is_equal_approx(5.0, 0.001)
	assert_bool(s.can_cast("crafting_unknown")["ok"]).is_false()
	assert_bool(s.can_cast("craft_apprentice")["ok"]).is_false()   # not learned
	s.grant("craft_apprentice")
	assert_str(s.can_cast("craft_apprentice")["reason"]).is_equal("Passive.")


func test_cooldowns_block_and_expire() -> void:
	var s := _fresh()
	s.grant("fire_ember_orb")
	var pools := {"magicules": 100.0}
	assert_bool(s.begin_cast("fire_ember_orb", pools)["ok"]).is_true()
	assert_float(s.cooldown_fraction("fire_ember_orb")).is_equal(1.0)
	assert_bool(s.can_cast("fire_ember_orb", pools)["ok"]).is_false()
	s.tick(1.0)
	assert_float(s.cooldown_left("fire_ember_orb")).is_equal_approx(1.5, 0.001)
	s.tick(1.6)
	assert_float(s.cooldown_left("fire_ember_orb")).is_equal(0.0)
	assert_bool(s.can_cast("fire_ember_orb", pools)["ok"]).is_true()
	# Higher rank, shorter cooldown.
	s.ranks["fire_ember_orb"] = 3
	assert_float(s.cooldown_of("fire_ember_orb")).is_equal_approx(2.5 * 0.8, 0.001)


func test_damage_scales_with_rank_realm_and_passives() -> void:
	var s := _fresh()
	s.grant("fire_ember_orb")
	var base := s.damage_of("fire_ember_orb")
	assert_int(base).is_equal(22)
	s.ranks["fire_ember_orb"] = 2
	assert_int(s.damage_of("fire_ember_orb")).is_equal(int(round(22 * 1.25)))
	s.grant("fire_kindled_heart")          # auto-equipped passive: fire_damage +0.08
	assert_bool(s.passives.has("fire_kindled_heart")).is_true()
	assert_int(s.damage_of("fire_ember_orb")).is_equal(int(round(22 * 1.25 * 1.08)))
	s.realm = 2
	assert_int(s.damage_of("fire_ember_orb")).is_equal(int(round(22 * 1.25 * 1.08 * 1.35)))


func test_passive_cost_reduction_and_buffs() -> void:
	var s := _fresh()
	s.grant("sword_rising_cut")
	s.grant("wind_light_step")             # stamina_cost -0.05
	assert_float(s.cost_of("sword_rising_cut")).is_equal_approx(14.0 * 0.95, 0.001)
	s.add_buff({"damage_taken": -0.35}, 2.0, "stone")
	assert_float(float(s.effects()["damage_taken"])).is_equal_approx(-0.35, 0.001)
	s.tick(2.5)
	assert_bool(s.effects().has("damage_taken")).is_false()


# --- loadout -----------------------------------------------------------------------

func test_loadout_fills_swaps_and_rejects() -> void:
	var s := _fresh()
	s.grant("fire_ember_orb")
	s.grant("sword_rising_cut")
	assert_array(s.loadout).is_equal(["fire_ember_orb", "sword_rising_cut", "", ""])
	assert_bool(s.equip(3, "fire_ember_orb")).is_true()
	assert_array(s.loadout).is_equal(["", "sword_rising_cut", "", "fire_ember_orb"])
	assert_bool(s.equip(0, "water_whip")).is_false()      # not learned
	s.grant("craft_apprentice")
	assert_bool(s.equip(0, "craft_apprentice")).is_false()  # passive
	assert_bool(s.equip(7, "fire_ember_orb")).is_false()
	s.unequip(1)
	assert_str(s.loadout[1]).is_empty()


func test_passive_slots_grow_with_realm() -> void:
	var s := _fresh()
	for id: String in ["craft_apprentice", "farm_green_thumb", "fire_kindled_heart"]:
		s.grant(id)
	assert_int(s.passive_slots()).is_equal(2)
	assert_int(s.passives.size()).is_equal(2)
	assert_bool(s.equip_passive("fire_kindled_heart")).is_false()
	s.realm = 2
	assert_int(s.passive_slots()).is_equal(3)
	assert_bool(s.equip_passive("fire_kindled_heart")).is_true()


# --- cultivation -------------------------------------------------------------------

func test_realm_stages_bottleneck_and_breakthrough() -> void:
	var s := _fresh()
	s.realm = 1
	s.qi = 0.0
	assert_float(s.qi_max()).is_equal(60.0)
	assert_int(s.cultivate(s.stage_xp_needed())).is_equal(1)
	assert_str(s.realm_label()).is_equal("Qi Condensation, layer 2")
	assert_float(s.qi_max()).is_greater(60.0)
	s.cultivate(100000.0)
	assert_int(s.stage).is_equal(8)
	assert_bool(s.at_bottleneck()).is_true()
	# Too low a level for Foundation.
	assert_bool(s.attempt_breakthrough(0.0, 3)["ok"]).is_false()
	# Failure: qi deviation.
	var xp := s.cult_xp
	var fail := s.attempt_breakthrough(0.0, 50, 0.999)
	assert_bool(fail["ok"]).is_true()
	assert_bool(fail["success"]).is_false()
	assert_int(fail["damage"]).is_greater(0)
	assert_int(s.realm).is_equal(1)
	assert_float(s.cult_xp).is_equal_approx(xp * Skills.DEVIATION_KEEP, 0.01)
	assert_bool(s.at_bottleneck()).is_false()
	# Success.
	s.cultivate(100000.0)
	var pts := s.points
	var ok := s.attempt_breakthrough(0.0, 50, 0.0)
	assert_bool(ok["success"]).is_true()
	assert_int(s.realm).is_equal(2)
	assert_int(s.stage).is_equal(0)
	assert_float(s.qi).is_equal(s.qi_max())
	assert_float(s.qi_max()).is_equal(150.0)
	assert_int(s.points).is_equal(pts + Skills.BREAKTHROUGH_POINTS)
	assert_float(ok["magicule_growth"]).is_greater(0.0)
	assert_str(s.realm_label()).is_equal("Foundation Establishment, early stage")


func test_breakthrough_needs_the_peak() -> void:
	var s := _fresh()
	assert_bool(s.at_bottleneck()).is_false()
	assert_bool(s.attempt_breakthrough(0.0, -1, 0.0)["ok"]).is_false()
	s.cultivate(40.0)                      # Mortal Body has a single stage
	assert_bool(s.at_bottleneck()).is_true()
	assert_bool(s.attempt_breakthrough(0.0, -1, 0.5)["success"]).is_true()   # the first awakening never fails
	assert_str(s.realm_name()).is_equal("Qi Condensation")


func test_qi_regenerates_up_to_the_pool() -> void:
	var s := _fresh()
	s.qi = 0.0
	s.tick(10.0)
	assert_float(s.qi).is_equal_approx(4.0, 0.001)     # Mortal Body: 0.4 qi/s
	s.tick(1000.0)
	assert_float(s.qi).is_equal(s.qi_max())


# --- hand seals ----------------------------------------------------------------------

func test_sealed_techniques_hit_harder_and_fizzle_rests() -> void:
	var s := _fresh()
	s.grant("shadow_clone")
	assert_bool(s.needs_seals("shadow_clone")).is_true()
	assert_bool(s.needs_seals("fire_ember_orb")).is_false()
	s.qi = 1000.0
	s.realm = 1
	var plain: int = s.begin_cast("shadow_clone")["damage"]
	s.cooldowns.clear()
	s.qi = 1000.0
	var sealed: int = s.begin_cast("shadow_clone", {}, true)["damage"]
	assert_int(sealed).is_equal(int(round(plain * (1.0 + Skills.SEAL_BONUS))))
	s.cooldowns.clear()
	s.fizzle("shadow_clone")
	assert_float(s.cooldown_left("shadow_clone")).is_equal(2.0)


# --- context & save ------------------------------------------------------------------

func test_sect_membership_from_life_flags() -> void:
	var sects := Skills.sects_from_flags({"recruited:sect": true, "sect:iron_lotus_monastery": true,
		"member:windstep_lodge": true, "class:Tracker": true, "sect:old": false})
	assert_array(sects).contains_exactly_in_any_order(["sect", "iron_lotus_monastery", "windstep_lodge"])
	var ctx := Skills.ctx_from_life(null)
	assert_int(ctx["level"]).is_equal(1)


func test_serialisation_round_trip_through_json() -> void:
	var s := _fresh()
	s.sync_progress(_ctx(8, ["hall_of_four_currents"], {"moon_child": 2}))
	s.learn("water_whip", _ctx(8))
	s.learn("water_whip", _ctx(8))
	s.grant("fire_kindled_heart")
	s.read_manual("manual_lodge_winds", 4)
	s.equip(3, "water_whip")
	s.begin_cast("water_whip", {"magicules": 50.0})
	s.realm = 1
	s.cultivate(70.0)
	s.add_buff({"crit_chance": 0.2}, 5.0, "sight")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(s.serialize()))
	var t := _fresh()
	t.deserialize(saved)
	assert_str(JSON.stringify(t.serialize())).is_equal(JSON.stringify(s.serialize()))
	assert_int(t.rank_of("water_whip")).is_equal(2)
	assert_str(t.loadout[3]).is_equal("water_whip")
	assert_float(t.cooldown_left("water_whip")).is_greater(0.0)
	assert_int(t.stage).is_equal(s.stage)
	assert_bool(t.manuals.has("manual_lodge_winds")).is_true()
	# Stale ids from an older data set are dropped, not crashed on.
	saved["ranks"]["removed_art"] = 2
	saved["loadout"][0] = "removed_art"
	var u := _fresh()
	u.deserialize(saved)
	assert_bool(u.ranks.has("removed_art")).is_false()
	assert_str(u.loadout[0]).is_empty()


func test_seeded_breakthrough_rolls_are_deterministic() -> void:
	var a := Skills.new(true, 42)
	var b := Skills.new(true, 42)
	var ra := []
	var rb := []
	for i in 6:
		for s: Skills in [a, b]:
			s.realm = 3
			s.stage = s.stage_count() - 1
			s.cult_xp = s.stage_xp_needed()
		ra.append(a.attempt_breakthrough()["success"])
		rb.append(b.attempt_breakthrough()["success"])
	assert_array(ra).is_equal(rb)
