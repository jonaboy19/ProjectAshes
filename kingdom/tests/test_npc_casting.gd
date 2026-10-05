extends GdUnitTestSuite
## NPC casters (bandit mage, sect disciple, knight captain, veteran mage) cast through the SAME AbilityRunner as the
## player, with NpcFighter decisions: data integrity, determinism, cooldown-only costs, chant vs chantless by profile,
## chant breaking on a stagger, wards, range and `when` rules, and a headless duel sanity band.

const NpcCaster := preload("res://scripts/combat/npc_caster.gd")
const Runner := preload("res://scripts/abilities/ability_runner.gd")
const PowerTrees := preload("res://scripts/abilities/power_trees.gd")
const AbilityLib := preload("res://scripts/abilities/ability_lib.gd")
const AbilityDef := preload("res://scripts/abilities/ability_def.gd")
const Fighter := preload("res://scripts/combat/npc_fighter.gd")
const DuelLib := preload("res://tools_qa/combat/caster_duel_lib.gd")

const IDS := ["bandit_mage", "sect_disciple", "knight_captain", "veteran_mage"]


func _ctx(extra := {}) -> Dictionary:
	var c := {"dist": 4.0, "target_state": "idle", "has_token": true, "own_hp_frac": 1.0, "sees_target": true}
	c.merge(extra, true)
	return c


func test_the_four_casters_exist_and_build() -> void:
	assert_array(NpcCaster.ids()).contains(IDS)
	for id: String in IDS:
		var c: RefCounted = NpcCaster.make(id, 3)
		assert_bool(Fighter.has_archetype(String(c.row["fighter"]))).is_true()
		assert_int((c.abilities as Array).size()).is_equal((c.row["abilities"] as Array).size())   # every id resolved
		assert_bool(c.runner is Runner).is_true()
		assert_bool(c.runner.costs_enabled).is_false()          # NPCs: cooldown only
		assert_bool((c.fighter.moves as Array).size() >= 2).is_true()
		assert_bool(c.effects() == c.runner.effects).is_true()  # one effect set per actor


func test_casters_follow_the_power_rules_of_their_own_profile() -> void:
	for id: String in IDS:
		var c: RefCounted = NpcCaster.make(id, 1)
		var prof: Dictionary = c.profile
		var path := String(c.row["path"])
		for a: Dictionary in c.abilities:
			var ab: Dictionary = a["def"]
			assert_str(ab["path"]).override_failure_message("%s casts a %s ability" % [id, ab["path"]]).is_equal(path)
			var st := PowerTrees.state(String(a["id"]), prof)
			assert_bool(st["state"] in ["ready", "known"]).override_failure_message("%s lacks %s for %s" % [id, str(st["reasons"]), a["id"]]).is_true()
		var realm := int((prof["realms"][path] as Dictionary)["realm"])
		assert_int((prof["subpaths"][path] as Array).size()).is_less_equal(PowerTrees.subpath_slots(path, realm))
	# Region 1 NPCs stay inside the caps; the veteran is the Region 2 teaser.
	for id: String in ["bandit_mage", "sect_disciple", "knight_captain"]:
		assert_int(int(NpcCaster.rows()[id]["realm"])).is_less_equal(3)
		assert_int(int(NpcCaster.rows()[id]["level"])).is_less_equal(60)
	assert_int(int(NpcCaster.rows()["veteran_mage"]["realm"])).is_greater_equal(4)


func test_same_seed_same_decisions() -> void:
	for id: String in IDS:
		var a: RefCounted = NpcCaster.make(id, 99)
		var b: RefCounted = NpcCaster.make(id, 99)
		for i in 120:
			var ctx := _ctx({"dist": 1.0 + float(i % 9), "target_state": ["idle", "windup", "recovery"][i % 3], "own_hp_frac": 1.0 - float(i % 5) * 0.2})
			var da: Dictionary = a.think(0.25, ctx)
			var db: Dictionary = b.think(0.25, ctx)
			assert_str(da["ability"]).is_equal(db["ability"])
			assert_str(da["intent"]).is_equal(db["intent"])
			assert_int(int(da["fight"]["intent"])).is_equal(int(db["fight"]["intent"]))
			if da["ability"] != "":
				var ra: Dictionary = a.cast(da["ability"])
				var rb: Dictionary = b.cast(db["ability"])
				assert_bool(ra.get("ok", false)).is_equal(rb.get("ok", false))
			a.update(0.25)
			b.update(0.25)


func test_a_cast_runs_chant_windup_execute_and_cooldown_without_paying() -> void:
	var c: RefCounted = NpcCaster.make("bandit_mage", 5)
	var seen := []
	c.runner.executed.connect(func(id: String, _ab: Dictionary, cast: Dictionary) -> void: seen.append([id, cast["damage"]]))
	var r: Dictionary = c.cast("mg_fire_ember", "foe")
	assert_str(r["phase"]).is_equal("chant")
	var chant: float = r["chant_time"]
	assert_float(chant).is_greater(0.5)
	assert_bool(c.runner.cooldown_left("mg_fire_ember") == 0.0).is_true()      # nothing is committed mid-chant
	var t := 0.0
	while seen.is_empty() and t < 10.0:
		c.update(0.05)
		t += 0.05
	assert_int(seen.size()).is_equal(1)
	assert_str(seen[0][0]).is_equal("mg_fire_ember")
	var windup := float(AbilityLib.get_def("mg_fire_ember")["windup"])
	assert_float(t).is_equal_approx(chant + windup, 0.12)
	assert_float(c.runner.cooldown_left("mg_fire_ember")).is_greater(0.0)
	assert_bool(c.cast("mg_fire_ember")["ok"]).is_false()                      # on cooldown
	assert_int(c.casts).is_equal(1)


func test_a_stagger_breaks_the_chant_and_the_spell_fizzles() -> void:
	var c: RefCounted = NpcCaster.make("bandit_mage", 5)
	var fired := []
	c.runner.executed.connect(func(id: String, _a: Dictionary, _c: Dictionary) -> void: fired.append(id))
	c.cast("mg_spark", "foe")
	c.update(0.3)
	assert_int(c.runner.phase).is_equal(Runner.Phase.CHANT)
	assert_bool(c.on_blow(500.0, 30.0, 10.0)).is_true()           # a huge blow staggers
	assert_int(c.runner.phase).is_equal(Runner.Phase.IDLE)
	assert_int(c.chants_broken).is_equal(1)
	assert_float(c.runner.cooldown_left("mg_spark")).is_equal_approx(Runner.FIZZLE_COOLDOWN, 0.0001)
	c.update(5.0)
	assert_array(fired).is_empty()
	# A small blow that does not stagger and is under the chant_break damage lets the chant go on.
	var d: RefCounted = NpcCaster.make("bandit_mage", 6)
	d.cast("mg_spark", "foe")
	d.on_blow(1.0, 2.0, 50.0)
	assert_int(d.runner.phase).is_equal(Runner.Phase.CHANT)
	# A hit of chant_break damage does break it even without a stagger.
	d.on_blow(1.0, 10.0, 60.0)
	assert_int(d.runner.phase).is_equal(Runner.Phase.IDLE)
	# A stagger during the windup drops the effect, too.
	var e: RefCounted = NpcCaster.make("veteran_mage", 7)
	e.cast("mg_spark_chain", "foe")
	assert_int(e.runner.phase).is_equal(Runner.Phase.WINDUP)       # chantless: straight to the windup
	e.on_blow(500.0, 30.0, 70.0)
	assert_int(e.runner.phase).is_equal(Runner.Phase.IDLE)


func test_chantless_veteran_casts_faster_than_the_bandit_mage() -> void:
	var m: RefCounted = NpcCaster.make("bandit_mage", 1)
	var v: RefCounted = NpcCaster.make("veteran_mage", 1)
	var tm := 0.0
	var tv := 0.0
	var done := []
	m.runner.executed.connect(func(_i: String, _a: Dictionary, _c: Dictionary) -> void: done.append("m"))
	v.runner.executed.connect(func(_i: String, _a: Dictionary, _c: Dictionary) -> void: done.append("v"))
	m.cast("mg_spark")
	v.cast("mg_spark")
	while done.size() < 2 and tm < 10.0:
		m.update(0.05)
		v.update(0.05)
		tm += 0.05
		if done.has("v") and tv == 0.0:
			tv = tm
	assert_array(done).is_equal(["v", "m"])
	assert_float(tv).is_less(tm)


func test_a_ward_cast_on_the_caster_soaks_a_blow() -> void:
	var c: RefCounted = NpcCaster.make("bandit_mage", 2)
	var def := AbilityLib.get_def("mg_ward")
	c.apply(def, 0, c.effects(), "self")
	assert_bool(c.effects().has("ward")).is_true()
	var r: Dictionary = c.deal(20.0)
	assert_int(r["absorbed"]).is_equal(20)
	assert_int(r["amount"]).is_equal(0)
	r = c.deal(25.0)
	assert_int(r["amount"]).is_equal(15)                         # 30 pool: 10 left, 25 - 10 = 15 through
	assert_bool(c.effects().has("ward")).is_false()
	# A second ward cast while one holds does not stack: same family, replace-if-stronger.
	c.apply(def, 0, c.effects(), "self")
	assert_str(c.apply(def, 0, c.effects(), "self")["actions"][0]["action"]).is_equal("refreshed")
	assert_int(c.effects().count("ward")).is_equal(1)


func test_think_respects_range_and_the_when_rules() -> void:
	var far := {}
	for i in 40:
		var k0: RefCounted = NpcCaster.make("knight_captain", 11 + i)
		var d0: Dictionary = k0.think(0.25, _ctx({"dist": 9.0}))      # beyond the charge: only the aura makes sense
		if d0["ability"] != "":
			far[d0["ability"]] = true
			assert_str(d0["intent"]).is_equal("cast")
	assert_array(far.keys()).is_equal(["kn_aura"])
	# Aura up, mid range: the charge closes the gap; never a melee form out of reach.
	var seen := {}
	for i in 60:
		var kk: RefCounted = NpcCaster.make("knight_captain", 100 + i)
		kk.effects().apply({"type": "aura", "family": "knight_aura", "stats": {}, "duration": 10.0})
		var dd: Dictionary = kk.think(0.25, _ctx({"dist": 6.0}))
		if dd["ability"] != "":
			seen[dd["ability"]] = true
	assert_array(seen.keys()).is_equal(["kn_charge"])
	# Close in: attacks only, and a guard cast when the foe winds up.
	var close := {}
	var guard := {}
	for i in 80:
		var kk2: RefCounted = NpcCaster.make("knight_captain", 200 + i)
		kk2.effects().apply({"type": "aura", "family": "knight_aura", "stats": {}, "duration": 10.0})
		var a1: Dictionary = kk2.think(0.25, _ctx({"dist": 1.5}))
		if a1["ability"] != "":
			close[a1["ability"]] = true
		var kk3: RefCounted = NpcCaster.make("knight_captain", 300 + i)
		kk3.effects().apply({"type": "aura", "family": "knight_aura", "stats": {}, "duration": 10.0})
		var a2: Dictionary = kk3.think(0.25, _ctx({"dist": 1.5, "target_state": "windup"}))
		if a2["ability"] != "":
			guard[a2["ability"]] = true
	for id: String in close:
		assert_bool(id in ["kn_rising_slash", "kn_cross_cut", "kn_edge"]).override_failure_message("close cast " + id).is_true()
	assert_bool(guard.has("kn_guard")).is_true()
	# Perception gate: when the target is not seen the caster holds and never casts.
	var blind: Dictionary = NpcCaster.make("bandit_mage", 1).think(0.25, _ctx({"sees_target": false}))
	assert_str(blind["intent"]).is_equal("hold")
	assert_str(blind["ability"]).is_equal("")


func test_a_mage_kites_when_pressed_and_out_of_spells() -> void:
	var m: RefCounted = NpcCaster.make("bandit_mage", 4)
	for a: Dictionary in m.abilities:
		m.runner.set_cooldown(String(a["id"]), 30.0)
	var kites := 0
	for i in 40:
		if m.think(0.25, _ctx({"dist": 2.0}))["intent"] == "kite":
			kites += 1
	assert_int(kites).is_equal(40)
	var fighter_only: RefCounted = NpcCaster.make("knight_captain", 4)
	for a: Dictionary in fighter_only.abilities:
		fighter_only.runner.set_cooldown(String(a["id"]), 30.0)
	assert_str(fighter_only.think(0.25, _ctx({"dist": 1.0}))["intent"]).is_equal("fight")    # knights stand and fight


func test_no_ability_is_cast_inside_its_own_cooldown_over_a_long_fight() -> void:
	for id: String in IDS:
		var c: RefCounted = NpcCaster.make(id, 21)
		var last := {}
		var violations := 0
		var t := 0.0
		c.runner.executed.connect(func(aid: String, _ab: Dictionary, _cast: Dictionary) -> void:
			var cd := float(AbilityLib.get_def(aid)["cooldown"])
			if last.has(aid) and t - float(last[aid]) < cd - 0.06:
				violations += 1
			last[aid] = t)
		while t < 120.0:
			var d: Dictionary = c.think(0.25, _ctx({"dist": 1.0 + float(int(t / 3.0) % 8), "target_state": ["idle", "windup", "recovery"][int(t) % 3],
				"own_hp_frac": 1.0 - float(int(t / 10.0) % 4) * 0.2}))
			if d["ability"] != "":
				c.cast(d["ability"], "foe")
			for k in 5:
				c.update(0.05)
				t += 0.05
		assert_int(violations).override_failure_message(id).is_equal(0)
		assert_int(c.casts).override_failure_message(id + " never cast").is_greater(5)


func test_duel_sanity_band_mage_vs_bandit() -> void:
	var lib := DuelLib.new()
	var r: Dictionary = lib.run("bandit_mage", "bandit", 40, 7)
	assert_float(r["a_win"] + r["b_win"] + r["draw"]).is_equal_approx(100.0, 0.01)
	assert_float(r["a_win"]).is_between(25.0, 85.0)        # a level-matched mage vs a bandit is a real fight
	assert_float(r["a_casts"]).is_greater(3.0)             # and she actually casts, chants break sometimes
	assert_float(r["a_broken"]).is_greater(0.0)
	assert_float(r["ttk"]).is_between(5.0, 60.0)
	var again: Dictionary = DuelLib.new().run("bandit_mage", "bandit", 40, 7)
	assert_float(again["a_win"]).is_equal(r["a_win"])      # replays exactly
	assert_float(again["ttk"]).is_equal_approx(r["ttk"], 0.0001)


func test_duel_sanity_other_casters_beat_or_trade_with_a_bandit() -> void:
	var lib := DuelLib.new()
	for pair: Array in [["sect_disciple", "bandit"], ["knight_captain", "bandit"]]:
		var r: Dictionary = lib.run(String(pair[0]), String(pair[1]), 30, 3)
		assert_float(r["a_win"]).override_failure_message("%s win %s" % [pair[0], r["a_win"]]).is_between(35.0, 95.0)
		assert_float(r["a_casts"]).is_greater(3.0)
