extends GdUnitTestSuite
## MN-1..5: the naming bond: preview == cost, ratio thresholds, hollowing floor, refused names and cooldown, exhaustion tiers, bond tracks and
## dormancy, forbidden species, tribe rite, monster followers (named and hired), the monster will, save round trip, determinism.

const Bonds := preload("res://scripts/realm/monster_bonds.gd")
const Hub := preload("res://scripts/realm/realm_hub.gd")


func _mb(seed_v := 8128) -> Object:
	var m: Object = Bonds.new()
	m.seed_value = seed_v
	m.naming = RANaming.new(seed_v)
	return m


func _name(mb: Object, pool: RAMagicules, target: Dictionary, opts := {}) -> Dictionary:
	return mb.name_creature(pool, RAInjuries.new(), int(opts.get("cl", 10)), target, String(target.get("name", "Ash")), opts)


## First key (deterministic) for which the rite is not refused.
func _name_ok(mb: Object, pool: RAMagicules, base: Dictionary, opts := {}) -> Dictionary:
	for i in 80:
		var t := base.duplicate()
		t["key"] = "%s:k%d" % [base.get("species", "x"), i]
		t["name"] = "N%d" % i
		var r := _name(mb, pool, t, opts)
		if r["outcome"] == "named":
			return r
	return {"outcome": "none", "ok": false}


func test_preview_matches_cost_and_forbids_undead() -> void:
	var mb := _mb()
	var pool := RAMagicules.new(400.0, 2.0, 1)
	var pv: Dictionary = mb.preview(pool, 10, 3, "goblin", 4)
	assert_int(int(pv["cost"])).is_equal(RANaming.cost("goblin", 4))
	var before := pool.current
	var r := _name_ok(mb, pool, {"species": "goblin", "level": 4})
	assert_str(r["outcome"]).is_equal("named")
	assert_int(int(r["cost"])).is_equal(int(pv["cost"]))
	assert_float(before - pool.current).is_equal_approx(float(pv["cost"]), 1.01)
	var u: Dictionary = mb.preview(pool, 10, 3, "undead", 3)
	assert_bool(u["forbidden"]).is_true()
	assert_bool(u["possible"]).is_false()
	var ur := _name(mb, pool, {"species": "undead", "level": 3})
	assert_str(ur["outcome"]).is_equal("forbidden")
	assert_int(mb.count()).is_equal(1)


func test_ratio_thresholds_and_refused_outright() -> void:
	assert_float(Bonds.ratio("goblin", 4, 10, 3)).is_less(1.0)
	assert_float(Bonds.ratio("ogre", 4, 5, 3)).is_between(1.5, 2.5)
	assert_float(Bonds.ratio("ogre", 20, 5, 3)).is_greater(2.5)
	var mb := _mb()
	var pool := RAMagicules.new(900.0, 2.0, 1)
	var pv: Dictionary = mb.preview(pool, 5, 3, "ogre", 20)
	assert_bool(pv["refuse_outright"]).is_true()
	assert_str(pv["note"]).contains("storm")
	var before := pool.current
	var r := _name(mb, pool, {"species": "ogre", "level": 20}, {"cl": 5})
	assert_str(r["outcome"]).is_equal("refused_outright")
	assert_float(pool.current).is_equal(before)
	assert_int(mb.count()).is_equal(0)


func test_hollowing_shrinks_pool_and_never_below_floor() -> void:
	var mb := _mb()
	var pool := RAMagicules.new(5000.0, 2.0, 1)
	var r := _name_ok(mb, pool, {"species": "ogre", "level": 4}, {"cl": 5})
	assert_str(r["outcome"]).is_equal("named")
	assert_float(Bonds.ratio("ogre", 4, 5, 3)).is_greater(1.5)
	assert_float(r["hollowed"]).is_greater(0.0)
	assert_float(pool.max_pool).is_less(5000.0)
	assert_float(mb.bond(r["bond"]["id"])["independence"]).is_equal(0.8)
	# Push toward the floor with ratio ~2.4 rites.
	for i in 6:
		_name_ok(mb, pool, {"species": "ogre", "level": 9, "name": "H%d" % i}, {"cl": 8})
	assert_float(pool.max_pool).is_greater_equal(5000.0 * 0.25 - 0.01)
	assert_float(mb.hollowed_total).is_greater(0.0)


func test_refused_name_sets_seven_day_cooldown() -> void:
	var mb := _mb()
	var pool := RAMagicules.new(600.0, 2.0, 1)
	var hit := ""
	var key := ""
	for i in 40:
		key = "orc:r%d" % i
		var r := _name(mb, pool, {"species": "orc", "level": 3, "key": key, "pride": 0.9, "grudge": 1.0}, {"day": 10})
		if r["outcome"] in ["refused", "backlash", "named_back"]:
			hit = r["outcome"]
			break
	assert_str(hit).is_not_empty()
	var again := _name(mb, pool, {"species": "orc", "level": 3, "key": key, "pride": 0.9}, {"day": 13})
	assert_str(again["outcome"]).is_equal("cooldown")
	var later := _name(mb, pool, {"species": "orc", "level": 3, "key": key, "pride": 0.9}, {"day": 18})
	assert_str(later["outcome"]).is_not_equal("cooldown")


func test_exhaustion_tiers() -> void:
	assert_str(Bonds.exhaustion_tier(10.0, 100.0, 100.0)).is_equal("none")
	assert_str(Bonds.exhaustion_tier(50.0, 100.0, 100.0)).is_equal("winded")
	assert_str(Bonds.exhaustion_tier(80.0, 100.0, 100.0)).is_equal("fatigue")
	assert_str(Bonds.exhaustion_tier(60.0, 100.0, 30.0)).is_equal("overdrawn")
	# Overdrawn rite: collapse of 6..24 hours is recorded, the namer is exhausted.
	var mb := _mb()
	var pool := RAMagicules.new(40.0, 1.0, 5)
	pool.current = 25.0
	var cost := RANaming.cost("goblin", 3)
	assert_float(float(cost)).is_greater(25.0)
	var r := _name_ok(mb, pool, {"species": "goblin", "level": 3}, {"cl": 6})
	assert_str(r["outcome"]).is_equal("named")
	assert_str(r["exhaustion"]).is_equal("overdrawn")
	assert_int(r["collapse_hours"]).is_between(6, 24)
	assert_float(pool.exhaustion).is_greater(0.0)


func test_tracks_caps_depth_thresholds_and_dormancy() -> void:
	var mb := _mb()
	var pool := RAMagicules.new(2000.0, 2.0, 1)
	var g := _name_ok(mb, pool, {"species": "goblin", "level": 3}, {"cl": 12, "tier": 4})
	var gid: String = g["bond"]["id"]
	assert_array(mb.bond(gid)["start"]).is_equal([1, 1, 1, 1])
	mb.add_depth(gid, 29.0)
	assert_int(mb.bond(gid)["form"]).is_equal(1)
	mb._day = 5
	mb.add_depth(gid, 1.0)
	assert_int(mb.bond(gid)["form"]).is_equal(2)
	assert_bool(mb.is_dormant(gid, 6)).is_true()
	assert_bool(mb.can_command(gid)).is_false()
	assert_bool(mb.is_dormant(gid, 9)).is_false()
	mb.add_depth(gid, 100.0)
	assert_int(mb.bond(gid)["speech"]).is_equal(2)       # a Lesser Name caps every track at 2
	var w := _name_ok(mb, pool, {"species": "wolf", "level": 3}, {"cl": 12, "tier": 5, "grade": "true"})
	assert_str(w["outcome"]).is_equal("named")
	var wid: String = w["bond"]["id"]
	assert_array(mb.bond(wid)["start"]).is_equal([2, 2, 2, 2])
	mb.add_depth(wid, 100.0)
	var wb: Dictionary = mb.bond(wid)
	assert_int(wb["speech"]).is_equal(2)                  # wolves reach Speech 2 only
	assert_int(wb["form"]).is_equal(3)
	assert_int(wb["ability"]).is_equal(4)
	assert_int(Bonds.band_cap(3)).is_equal(2)
	assert_int(Bonds.band_cap(5)).is_equal(3)
	assert_int(Bonds.band_cap(7)).is_equal(4)


func test_tribe_rite_cost_cap_vassal_and_defector() -> void:
	var mb := _mb()
	var pool := RAMagicules.new(3000.0, 2.0, 1)
	var members: Array = []
	for i in 7:
		members.append({"species": "goblin", "level": 2, "name": "g%d" % i})
	var single := RANaming.cost("goblin", 3)
	var big: Array = []
	for i in 10:
		big.append({"species": "goblin", "level": 2})
	var capped: Dictionary = mb.tribe_name(pool, RAInjuries.new(), 12, {"species": "goblin", "level": 3, "key": "warren"}, "Chief", big, {"tier": 3, "feast": true})
	assert_bool(capped["ok"]).is_false()                  # at most 3 + tier*2 = 9 kin
	var rite: Dictionary = {}
	for i in 60:
		rite = mb.tribe_name(pool, RAInjuries.new(), 12, {"species": "goblin", "level": 3, "key": "warren%d" % i, "pride": 0.0}, "Chief%d" % i, members,
			{"tier": 3, "feast": true, "camp": "camp_%d" % i, "day": 1})
		if bool(rite["ok"]):
			break
	assert_bool(rite["ok"]).is_true()
	assert_int(int(rite["cost"])).is_greater_equal(int(float(single) * 1.4))
	assert_bool(mb.camp_attacks(rite["camp"], "player")).is_false()
	assert_bool(mb.camp_attacks(rite["camp"], "stranger")).is_true()
	# Without a feast the whole tribe starts at loyalty 55.
	var mb2 := _mb()
	var pool2 := RAMagicules.new(3000.0, 2.0, 1)
	var r2: Dictionary = {}
	for i in 60:
		r2 = mb2.tribe_name(pool2, RAInjuries.new(), 12, {"species": "goblin", "level": 3, "key": "w%d" % i}, "C%d" % i, members, {"tier": 3, "feast": false, "camp": "c%d" % i})
		if bool(r2["ok"]) and not (r2["members"] as Array).is_empty():
			break
	assert_int(int(r2["members"][0]["loyalty"])).is_equal(55)
	# A defecting lieutenant becomes a rival band for some camp.
	var found := false
	for i in 120:
		var m3 := _mb(i + 1)
		var p3 := RAMagicules.new(3000.0, 2.0, 1)
		var r3: Dictionary = m3.tribe_name(p3, RAInjuries.new(), 12, {"species": "goblin", "level": 3, "key": "z"}, "Z", members, {"tier": 3, "feast": true, "camp": "cz%d" % i})
		if bool(r3["ok"]) and not (r3["defectors"] as Array).is_empty():
			assert_int(m3.rivals.size()).is_equal(1)
			found = true
			break
	assert_bool(found).is_true()


func test_named_and_hired_monsters_become_followers() -> void:
	var hub = Hub.new()
	var mb: Object = hub.mod("monster_bonds")
	mb.naming = RANaming.new()
	var pool := RAMagicules.new(500.0, 2.0, 1)
	var r := _name_ok(mb, pool, {"species": "orc", "level": 3}, {"cl": 12, "klass": "guardian", "tier": 4})
	assert_str(r["outcome"]).is_equal("named")
	var fid: String = mb.recruit_follower(r["bond"]["id"])
	assert_str(fid).is_not_empty()
	var f: Dictionary = hub.mod("followers").get_follower(fid)
	assert_str(f["flags"]["monster"]).is_equal("orc")
	assert_str(f["status"]).is_equal("present")
	assert_bool("honorable" in f["traits"]).is_true()
	assert_str(mb.recruit_follower(r["bond"]["id"])).is_equal(fid)       # idempotent
	var comp: Array = mb.companions_of("player")
	assert_int(comp.size()).is_equal(1)
	assert_str(comp[0]["species"]).is_equal("orc")
	# Hire path: speech, a den and a wage.
	assert_bool(mb.hire_monster("goblin", "Tuk", 1, {"w": 10, "h": 1})["ok"]).is_false()
	assert_bool(mb.hire_monster("goblin", "Tuk", 2, {"w": 10, "h": 0})["ok"]).is_false()
	assert_bool(mb.hire_monster("goblin", "Tuk", 2, {"w": 1, "h": 1})["ok"]).is_false()
	var h: Dictionary = mb.hire_monster("lizardfolk", "Sess", 3, {"w": 12, "h": 1})
	assert_bool(h["ok"]).is_true()
	assert_str(h["fid"]).is_not_empty()
	assert_bool(mb.hire_monster("undead", "Bone", 3, {"w": 99, "h": 1})["ok"]).is_false()


func test_monster_will_ambition_and_orders() -> void:
	var mb := _mb()
	var pool := RAMagicules.new(2000.0, 2.0, 1)
	var o := _name_ok(mb, pool, {"species": "orc", "level": 3}, {"cl": 12})
	var oid: String = o["bond"]["id"]
	assert_str(mb.respond(oid, "burn_granary")["action"]).is_equal("refuse")
	assert_str(mb.respond(oid, "follow")["action"]).is_equal("obey")
	mb.bond(oid)["dormant_until"] = 99
	assert_str(mb.respond(oid, "follow")["action"]).is_equal("refuse")
	# Ambition odds: wolves rarely roll an agenda, goblins usually do.
	var wolf_amb := 0
	var gob_amb := 0
	for i in 200:
		if mb._roll_ambition("wolf", "w%d" % i) != "none":
			wolf_amb += 1
		if mb._roll_ambition("goblin", "g%d" % i) != "none":
			gob_amb += 1
	assert_int(wolf_amb).is_less(40)
	assert_int(gob_amb).is_greater(120)
	# A greedy independent goblin leaves when denied land.
	var gid := ""
	for i in 40:
		var g := _name_ok(mb, pool, {"species": "goblin", "level": 2, "name": "G%d" % i}, {"cl": 12})
		if g["ok"] and mb.bond(g["bond"]["id"])["ambition"] in ["greed", "power"]:
			gid = g["bond"]["id"]
			break
		if mb.count() >= 15:
			break
	assert_str(gid).is_not_empty()
	mb.bond(gid)["independence"] = 0.6
	assert_bool(mb.consider_leaving(gid, "land")["leaves"]).is_true()


func test_keep_and_loyalty_decay_and_byname() -> void:
	var mb := _mb()
	var pool := RAMagicules.new(900.0, 2.0, 1)
	var r := _name_ok(mb, pool, {"species": "wolf", "level": 2}, {"cl": 12})
	var id: String = r["bond"]["id"]
	var l0: int = mb.bond(id)["loyalty"]
	mb.set_keep(id, false, true, false)
	for d in 5:
		mb.tick_day(10 + d, {})
	assert_int(mb.bond(id)["loyalty"]).is_less(l0)
	mb.set_keep(id, true, true, true)
	var depth0: float = mb.bond(id)["depth"]
	mb.tick_day(20, {})
	assert_float(mb.bond(id)["depth"]).is_greater(depth0)
	mb.record_deed(id, 3)
	assert_str(mb.bond(id)["byname"]).is_not_empty()


func test_save_round_trip_and_determinism() -> void:
	var a := _mb(77)
	var b := _mb(77)
	var pa := RAMagicules.new(900.0, 2.0, 1)
	var pb := RAMagicules.new(900.0, 2.0, 1)
	var ra := _name_ok(a, pa, {"species": "kobold", "level": 3}, {"cl": 12})
	var rb := _name_ok(b, pb, {"species": "kobold", "level": 3}, {"cl": 12})
	assert_str(ra["outcome"]).is_equal(rb["outcome"])
	assert_dict(a.bond(ra["bond"]["id"])).is_equal(b.bond(rb["bond"]["id"]))
	a.add_depth(ra["bond"]["id"], 40.0)
	var js := JSON.stringify(a.serialize())
	var c := _mb(77)
	c.deserialize(JSON.parse_string(js))
	var ca: Dictionary = c.bond(ra["bond"]["id"])
	var oa: Dictionary = a.bond(ra["bond"]["id"])
	for k in ["species", "form", "mind", "speech", "ability", "ref"]:
		assert_that(ca[k]).is_equal(oa[k])
	assert_float(ca["depth"]).is_equal_approx(oa["depth"], 0.001)
	assert_int(c.count()).is_equal(1)
