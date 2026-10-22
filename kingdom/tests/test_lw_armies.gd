extends GdUnitTestSuite
## LW-7.1 to 7.3 (docs/design/LIVING_WORLD_SANDBOX.md section 9): force types with legal status and size limits (suspicion through territory and
## diplomacy), the Army entity (ar: ids, real recruits through recruitment contracts, wages, food, training, specialisation, morale, discipline),
## officers with standing orders and delegated subcommanders, couriers and fog of war, logistics and desertion, levies that cut harvests,
## settlement defence and attacker choice, campaign / siege integration, NPC parity, save round trip, determinism, tick cost.

const Hub := preload("res://scripts/realm/realm_hub.gd")
const Rec := preload("res://scripts/realm/recruitment.gd")
const D := preload("res://scripts/realm/armies_data.gd")
const Reg := preload("res://scripts/realm/registry.gd")
const Siege := preload("res://scripts/realm/siege.gd")

static var _world := false


func _hub() -> RefCounted:
	if not _world:
		WorldGen.setup(2024)
		_world = true
	var h: RefCounted = Hub.new()
	h.mod("organizations").auto_seed = false
	h.mod("organizations").gold_ref = {"gold": 5000}
	h.mod("businesses").set_day(0)
	return h


func _norm(d: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(d)))


## First difference between two JSON-normalised values ("" when equal), for readable round-trip failures.
func _diff(x: Variant, y: Variant, path := "") -> String:
	if typeof(x) != typeof(y):
		return "%s type %s vs %s" % [path, str(x), str(y)]
	if x is Dictionary:
		for k: Variant in x:
			if not (y as Dictionary).has(k):
				return "%s/%s missing" % [path, k]
			var r := _diff(x[k], y[k], "%s/%s" % [path, k])
			if r != "":
				return r
		for k2: Variant in y:
			if not (x as Dictionary).has(k2):
				return "%s/%s extra" % [path, k2]
	elif x is Array:
		if (x as Array).size() != (y as Array).size():
			return "%s len %d vs %d" % [path, (x as Array).size(), (y as Array).size()]
		for i in (x as Array).size():
			var r2 := _diff(x[i], y[i], "%s[%d]" % [path, i])
			if r2 != "":
				return r2
	elif x != y:
		return "%s: %s vs %s" % [path, str(x), str(y)]
	return ""


func _arm(h: RefCounted) -> RefCounted:
	return h.mod("armies")


func _mk(h: RefCounted, owner := "player", kind := "garrison", sid := 0, purse := 500) -> String:
	var r: Dictionary = _arm(h).found(owner, kind, "", sid, {"purse": purse, "food": 200.0})
	assert_bool(r["ok"]).is_true()
	return r["id"]


func _hours(h: RefCounted, n: int) -> void:
	for i in n:
		_arm(h).tick_hour(i % 24, {})


func _days(h: RefCounted, from: int, to: int) -> void:
	for d in range(from, to + 1):
		_arm(h).tick_day(d, {})


# --- 1. force types and legal limits ------------------------------------------------------

func test_thirteen_force_types_with_legal_status() -> void:
	assert_int(D.FORCES.size()).is_equal(13)
	for k: String in ["royal", "household", "garrison", "town_guard", "militia", "levy", "mercenary", "guild_security", "bodyguard", "adventurer_band", "sect_order", "independent_legion", "rebels"]:
		assert_bool(D.FORCES.has(k)).is_true()
		assert_bool(String(D.FORCES[k]["legal"]) in D.LEGAL_ORDER).is_true()
	var a := _arm(_hub())
	assert_str(a.legal_status("player", "garrison")).is_equal("lawful")
	assert_str(a.legal_status("player", "rebels")).is_equal("illegal")
	assert_int(a.legal_limit("player", "rebels")).is_equal(0)
	assert_int(a.legal_limit("player", "royal")).is_greater(a.legal_limit("player", "town_guard"))


func test_limit_grows_with_rank_and_recognition_legalises() -> void:
	var h := _hub()
	var a := _arm(h)
	var lo: int = a.legal_limit("lord_x", "household")
	var st: RefCounted = h.mod("stewardship")
	var key: String = st.office_key(0, 2)
	st.assume(key, "lord_x", "Lord X")
	assert_int(a.owner_rank("lord_x")).is_greater(0)
	assert_int(a.legal_limit("lord_x", "household")).is_greater(lo)
	assert_str(a.legal_status("legion", "independent_legion")).is_equal("illegal")
	a.recognise("legion", "caldrenn")
	assert_str(a.legal_status("legion", "independent_legion")).is_equal("licensed")
	assert_int(a.legal_limit("legion", "independent_legion")).is_equal(D.RECOGNISED_LIMIT)


func test_going_over_limit_raises_suspicion_in_diplomacy_and_territory() -> void:
	var h := _hub()
	var a := _arm(h)
	var dip: RefCounted = h.mod("diplomacy")
	var tr: RefCounted = h.mod("territory")
	var vis0: float = dip.visibility_of("reb")
	var id := _mk(h, "reb", "rebels", 3)
	a.add_unit(id, "spear", 40)
	assert_float(a.suspicion("reb")).is_greater(0.1)
	assert_float(dip.visibility_of("reb")).is_greater(vis0)
	assert_float(tr.suspicion_at(3)).is_greater(0.0)
	var c0: float = dip.conduct_of("reb", "caldrenn")
	assert_float(c0).is_less(0.0)
	# a lawful force inside its limit raises nothing
	var id2 := _mk(h, "sir_ok", "town_guard", 1)
	a.add_unit(id2, "spear", 10)
	assert_float(a.suspicion("sir_ok")).is_equal(0.0)
	# suspicion decays weekly once the men are gone
	a.disband(id)
	for w in 20:
		a.tick_week(w, {})
	assert_float(a.suspicion("reb")).is_equal(0.0)
	assert_float(tr.suspicion_at(3)).is_equal(0.0)


# --- 2. the army entity -----------------------------------------------------------------

func test_army_ids_come_from_the_registry() -> void:
	var h := _hub()
	var id := _mk(h)
	assert_bool(Reg.is_pid(id)).is_true()
	assert_str(Reg.prefix_of(id)).is_equal("ar")
	assert_int(h.mod("registry").issued("ar")).is_equal(1)
	assert_str(_mk(h, "player", "militia")).is_equal("ar:2")


func test_real_recruits_join_through_contracts_and_are_paid_by_them() -> void:
	var h := _hub()
	var a := _arm(h)
	var id := _mk(h)
	var rg: Vector2i = WorldSim.ranges[0]
	var joined := 0
	for row in range(rg.x, rg.x + 40):
		if WorldSim.health[row] == 0:
			continue
		var r: Dictionary = a.enlist(id, "spear", row, Rec.make_terms(60, "guard", 0, true))
		if bool(r.get("ok", false)):
			joined += 1
			assert_str(String(h.mod("recruitment").contract(String(r["cid"]))["st"])).is_equal("active")
			assert_bool(h.mod("registry").lookup("ws:%d" % row) != "").is_true()
	assert_int(joined).is_greater(0)
	assert_int(a.men(id)).is_equal(joined)
	assert_int(int(a.army(id)["contracted"])).is_equal(joined)
	# contracted men are paid through their contracts: the army's own wage bill excludes them
	assert_int(int(a.upkeep(id)["wages"])).is_equal(0)
	a.add_unit(id, "spear", 20)
	assert_int(int(a.upkeep(id)["wages"])).is_greater(0)


func test_training_takes_days_and_costs_gold_and_specialisation() -> void:
	var h := _hub()
	var a := _arm(h)
	var id := _mk(h, "player", "garrison", 0, 10000)
	a.army(id)["food"] = 5000.0
	var uid: int = a.add_unit(id, "archer", 20)
	var p0: float = a.unit_power(a.unit(id, uid))
	var r: Dictionary = a.train(id, uid, 2)
	assert_bool(r["ok"]).is_true()
	assert_int(int(r["days"])).is_greater(5)
	assert_int(int(a.army(id)["purse"])).is_less(10000)
	assert_bool(a.train(id, uid, 3)["ok"]).is_false()        # busy
	_days(h, 1, int(r["days"]) - 1)
	assert_int(int(a.unit(id, uid)["lvl"])).is_equal(0)
	_days(h, int(r["days"]), int(r["days"]) + 1)
	assert_int(int(a.unit(id, uid)["lvl"])).is_equal(2)
	assert_float(a.unit_power(a.unit(id, uid))).is_greater(p0 * 1.2)
	assert_bool(a.specialise(id, uid, "charge")["ok"]).is_false()   # archers cannot charge
	assert_bool(a.specialise(id, uid, "volley")["ok"]).is_true()
	_days(h, 20, 40)
	assert_str(String(a.unit(id, uid)["spec"])).is_equal("volley")
	# cannot afford more drill
	a.army(id)["purse"] = 0
	assert_bool(a.train(id, uid, 5)["ok"]).is_false()


func test_equipment_and_morale_change_strength() -> void:
	var h := _hub()
	var a := _arm(h)
	var id := _mk(h)
	var uid: int = a.add_unit(id, "infantry", 30, {"eq": 0.2})
	var p0: float = a.power(id)
	assert_bool(a.equip(id, uid, 0.9, 4.0)).is_true()
	assert_float(a.power(id)).is_greater(p0)
	var p1: float = a.power(id)
	a.hurt(id, 0.0, 0.3)
	assert_float(a.power(id)).is_less(p1)


# --- 3. officers --------------------------------------------------------------------------

func test_officers_have_competence_personality_and_standing_orders() -> void:
	var h := _hub()
	var a := _arm(h)
	var id := _mk(h)
	var rg: Vector2i = WorldSim.ranges[0]
	var oid: String = a.appoint(id, {"row": rg.x + 3})
	assert_bool(Reg.is_pid(oid)).is_true()
	assert_bool(h.mod("registry").is_upgraded(oid)).is_true()
	var o: Dictionary = a.officer(id, oid)
	assert_float(float(o["comp"])).is_between(0.0, 1.0)
	assert_bool(String(o["pers"]) in D.OFFICER_PERS).is_true()
	assert_bool(a.set_standing(id, {"kind": "patrol", "retreat_morale": 0.3}, oid)).is_true()
	assert_str(String(a.officer(id, oid)["standing"]["kind"])).is_equal("patrol")
	var good: String = a.appoint(id, {"name": "Able", "comp": 0.95, "pers": "loyal"}, "sub")
	var bad: String = a.appoint(id, {"name": "Dull", "comp": 0.05, "pers": "greedy"}, "sub")
	var u1: int = a.add_unit(id, "spear", 20)
	var u2: int = a.add_unit(id, "spear", 20)
	assert_bool(a.delegate(id, good, [u1])).is_true()
	assert_bool(a.delegate(id, bad, [u2])).is_true()
	assert_bool(a.delegate(id, oid, [u1])).is_false()        # the commander does not sub-command
	assert_str(String(a.unit(id, u1)["off"])).is_equal(good)
	assert_bool(a.delegate(id, "ch:nobody", [u1])).is_false()
	a.delegate(id, good, [u1])
	var order := {"kind": "attack", "x": 100.0, "y": 100.0}
	var pg: float = a.obedience(id, u1, order)["p"]
	var pb: float = a.obedience(id, u2, order)["p"]
	assert_float(pg).is_greater(pb)


func test_obedience_falls_with_morale_discipline_pay_and_distance() -> void:
	var h := _hub()
	var a := _arm(h)
	var id := _mk(h, "player", "garrison", 0)
	a.set_hq("player", [0.0, 0.0])
	a.appoint(id, {"name": "Cap", "comp": 0.5, "pers": "loyal"})
	var uid: int = a.add_unit(id, "spear", 30, {"mo": 0.9, "di": 0.9})
	var order := {"kind": "attack"}
	var p_good: float = a.obedience(id, uid, order)["p"]
	a.unit(id, uid)["mo"] = 0.2
	a.unit(id, uid)["di"] = 0.2
	var p_bad: float = a.obedience(id, uid, order)["p"]
	assert_float(p_bad).is_less(p_good - 0.3)
	a.unit(id, uid)["mo"] = 0.9
	a.unit(id, uid)["di"] = 0.9
	a.army(id)["unpaid"] = 4
	assert_float(a.obedience(id, uid, order)["p"]).is_less(p_good)
	a.army(id)["unpaid"] = 0
	a.army(id)["pos"] = [9000.0, 0.0]      # far away: communications poor
	assert_float(a.comms(id)).is_less(0.9)
	assert_float(a.obedience(id, uid, order)["p"]).is_less(p_good)
	# the same inputs always give the same answer
	assert_str(_norm(a.obedience(id, uid, order, 5))).is_equal(_norm(a.obedience(id, uid, order, 5)))


func test_mutinous_unit_defies_and_follows_nothing() -> void:
	var h := _hub()
	var a := _arm(h)
	var id := _mk(h)
	a.set_hq("player", [0.0, 0.0])
	a.appoint(id, {"name": "Cap", "comp": 0.2, "pers": "greedy", "loy": 0.1})
	a.add_unit(id, "spear", 40, {"mo": 0.05, "di": 0.05})
	a.army(id)["unpaid"] = 5
	var r: Dictionary = a.send_order(id, {"kind": "attack", "x": 500.0, "y": 0.0})
	_hours(h, int(r["eta_hours"]) + 1)
	_hours(h, int(r["eta_hours"]) + 1)
	assert_str(String(a.order_view(int(r["seq"]))["state"])).is_equal("defied")
	assert_str(String(a.army(id)["order"]["kind"])).is_equal("hold")


# --- 4. command: couriers and fog ---------------------------------------------------------

func test_orders_arrive_after_the_courier_ride_and_the_reply_comes_later() -> void:
	var h := _hub()
	var a := _arm(h)
	var id := _mk(h, "player", "garrison", 0)
	a.set_hq("player", [0.0, 0.0])
	a.army(id)["pos"] = [4000.0, 0.0]
	a.appoint(id, {"name": "Cap", "comp": 0.9, "pers": "loyal", "loy": 1.0})
	a.add_unit(id, "spear", 20, {"mo": 1.0, "di": 1.0})
	var r: Dictionary = a.send_order(id, {"kind": "move", "x": 4000.0, "y": 900.0})
	var eta := int(r["eta_hours"])
	assert_int(eta).is_equal(int(ceil(4000.0 / D.COURIER_SPEED)))
	assert_int(eta).is_greater(3)
	_hours(h, eta - 1)
	assert_str(String(a.army(id)["order"]["kind"])).is_equal("hold")
	assert_str(String(a.order_view(int(r["seq"]))["state"])).is_equal("sent")
	_hours(h, 1)
	assert_str(String(a.army(id)["order"]["kind"])).is_equal("move")
	# the sender still does not know: the reply is on its way back
	assert_str(String(a.order_view(int(r["seq"]))["state"])).is_equal("sent")
	_hours(h, eta)
	assert_str(String(a.order_view(int(r["seq"]))["state"])).is_equal("obeyed")
	# the army marches at army speed
	assert_float(float(a.army(id)["pos"][1])).is_equal(900.0)     # 900 m at 180 m/h took five of those hours
	assert_str(String(a.army(id)["state"])).is_equal("camped")


func test_lost_courier_means_no_reply() -> void:
	var h := _hub()
	var a := _arm(h)
	var id := _mk(h, "player", "garrison", 0)
	a.set_hq("player", [0.0, 0.0])
	a.army(id)["pos"] = [3000.0, 0.0]
	a.add_unit(id, "spear", 20)
	var foe := _mk(h, "raiders", "rebels", 1)
	a.add_unit(foe, "spear", 20)
	a.army(foe)["pos"] = [1500.0, 50.0]
	a.set_hostile("player", "raiders")
	var lost := 0
	for i in 12:
		var r: Dictionary = a.send_order(id, {"kind": "move", "x": 10.0 * i, "y": 0.0})
		_hours(h, int(r["eta_hours"]) * 2 + 1)
		if String(a.order_view(int(r["seq"]))["state"]) == "no_reply":
			lost += 1
	assert_int(lost).is_greater(0)
	assert_int(lost).is_less(12)
	assert_int(int(a.stats["lost_orders"])).is_equal(lost)


func test_scouting_gives_last_known_positions_confirmed_then_stale() -> void:
	var h := _hub()
	var a := _arm(h)
	var mine := _mk(h, "player", "royal", 0)
	a.add_unit(mine, "scout", 6)
	a.army(mine)["pos"] = [0.0, 0.0]
	var foe := _mk(h, "raiders", "rebels", 1)
	a.add_unit(foe, "spear", 50)
	a.army(foe)["pos"] = [250.0, 0.0]          # beyond plain sight (140) but inside scout sight (320)
	a.set_hostile("player", "raiders")
	var far := _mk(h, "raiders", "rebels", 2)
	a.add_unit(far, "spear", 30)
	a.army(far)["pos"] = [5000.0, 0.0]
	a.scout_pass()
	var km: Array = a.known_map("player")
	var seen: Dictionary = {}
	for e: Dictionary in km:
		seen[e["id"]] = e
	assert_bool(seen.has(foe)).is_true()
	assert_bool(seen.has(far)).is_false()                   # never seen: not on the map at all
	assert_str(String(seen[foe]["status"])).is_equal("confirmed")
	assert_int(int(seen[foe]["n"])).is_between(40, 60)      # an estimate, not the truth
	# the enemy walks away: what we know is where we last saw them, and it goes stale
	a.army(foe)["pos"] = [4000.0, 4000.0]
	a.army(mine)["pos"] = [0.0, 0.0]
	_hours(h, 8)
	km = a.known_map("player")
	for e2: Dictionary in km:
		if e2["id"] == foe:
			assert_str(String(e2["status"])).is_equal("stale")
			assert_float(float(e2["pos"][0])).is_equal(250.0)
			assert_float(float(e2["conf"])).is_less(1.0)
	_hours(h, 24 * 20)
	for e3: Dictionary in a.known_map("player"):
		assert_bool(e3["id"] == foe).is_false()          # long forgotten


func test_without_scouts_sight_is_short_and_blurry() -> void:
	var h := _hub()
	var a := _arm(h)
	var mine := _mk(h, "player", "garrison", 0)
	a.add_unit(mine, "spear", 10)
	a.army(mine)["pos"] = [0.0, 0.0]
	var foe := _mk(h, "raiders", "rebels", 1)
	a.add_unit(foe, "spear", 50)
	a.army(foe)["pos"] = [250.0, 0.0]
	a.set_hostile("player", "raiders")
	assert_int(a.scout_pass()).is_equal(0)
	a.army(foe)["pos"] = [100.0, 0.0]
	assert_int(a.scout_pass()).is_greater(0)
	assert_str(String(a._sight["player"][foe]["src"])).is_equal("sight")


func test_delegated_army_acts_on_standing_orders_when_cut_off() -> void:
	var h := _hub()
	var a := _arm(h)
	var id := _mk(h, "player", "garrison", 0)
	a.set_hq("player", [0.0, 0.0])
	a.appoint(id, {"name": "Cap", "comp": 0.7, "pers": "careful"})
	a.add_unit(id, "spear", 30, {"mo": 0.9})
	a.set_standing(id, {"kind": "patrol", "radius": 300.0, "retreat_morale": 0.3})
	_days(h, 1, 2)
	assert_bool((a.army(id)["dest"] as Array).is_empty()).is_true()          # manual and in touch: waits for orders
	a.set_mode(id, "delegated")
	_days(h, 3, 3)
	assert_bool((a.army(id)["dest"] as Array).is_empty()).is_false()
	assert_str(String(a.army(id)["order"]["kind"])).is_equal("patrol")
	# a broken army falls back on its own
	a.unit(id, a.army(id)["units"][0]["u"])["mo"] = 0.05
	a.army(id)["dest"] = []
	_days(h, 4, 4)
	assert_str(String(a.army(id)["order"]["kind"])).is_equal("retreat")
	# it avoids a much stronger enemy it knows about
	var id2 := _mk(h, "player", "garrison", 1)
	a.add_unit(id2, "spear", 10, {"mo": 0.9})
	a.set_mode(id2, "delegated")
	a.set_standing(id2, {"kind": "defend", "avoid_ratio": 1.0, "radius": 400.0, "retreat_morale": 0.1}, "")
	a.army(id2)["pos"] = [0.0, 0.0]
	var foe := _mk(h, "raiders", "rebels", 2)
	a.add_unit(foe, "cavalry", 80)
	a.army(foe)["pos"] = [100.0, 0.0]
	a.set_hostile("player", "raiders")
	a.scout_pass()
	_days(h, 5, 5)
	assert_str(String(a.army(id2)["order"]["kind"])).is_equal("retreat")


# --- 5. logistics ---------------------------------------------------------------------------

func test_wages_and_food_are_consumed_daily_and_land_in_the_ledger() -> void:
	var h := _hub()
	var a := _arm(h)
	var id := _mk(h, "player", "garrison", 0, 400)
	a.add_unit(id, "infantry", 30)
	var wage: int = a.upkeep(id)["wages"]
	assert_int(wage).is_greater(0)
	_days(h, 1, 3)
	assert_int(int(a.army(id)["purse"])).is_equal(400 - wage * 3)
	assert_float(float(a.army(id)["food"])).is_equal(200.0 - 90.0)
	assert_int(int(a.army(id)["ledger"]["wages"])).is_equal(wage * 3)
	assert_int(int(a.upkeep_total("player")["wages"])).is_equal(wage)
	assert_int(int(a.army(id)["unpaid"])).is_equal(0)


func test_unpaid_army_loses_morale_then_deserts() -> void:
	var h := _hub()
	var a := _arm(h)
	var id := _mk(h, "player", "mercenary", 0, 0)
	a.add_unit(id, "infantry", 80, {"mo": 0.7, "di": 0.3})
	var m0: float = a.morale(id)
	_days(h, 1, 2)
	assert_int(a.men(id)).is_equal(80)                # grace period
	assert_float(a.morale(id)).is_less(m0)
	_days(h, 3, 8)
	assert_int(a.men(id)).is_less(80)
	assert_int(int(a.army(id)["deserted"])).is_greater(0)
	assert_int(h.mod("events").recent(50).filter(func(e: Dictionary) -> bool: return String(e["cause"]).begins_with("desertion")).size()).is_greater(0)
	# paying the arrears stops it
	a.fund(id, 5000)
	a.army(id)["food"] = 3000.0
	var left: int = a.men(id)
	assert_int(left).is_greater(0)
	_days(h, 9, 12)
	assert_int(a.men(id)).is_equal(left)
	assert_int(int(a.army(id)["unpaid"])).is_equal(0)


func test_hunger_hurts_and_a_supply_train_feeds() -> void:
	var h := _hub()
	var a := _arm(h)
	var id := _mk(h, "player", "garrison", 0, 5000)
	a.add_unit(id, "spear", 40)
	a.army(id)["food"] = 0.0
	a.add_wagons(id, 3)
	_days(h, 1, 2)
	assert_int(int(a.army(id)["hungry"])).is_equal(2)
	var starving: float = a.power(id)
	var t: Dictionary = a.send_train(id, [600.0, 0.0], 300.0, 100, 3)
	assert_bool(t["ok"]).is_true()
	_hours(h, int(t["eta_h"]) + 1)
	assert_float(float(a.army(id)["food"])).is_greater(250.0)
	assert_int(a.trains().size()).is_equal(0)
	_days(h, 3, 3)
	assert_int(int(a.army(id)["hungry"])).is_equal(0)
	assert_float(a.power(id)).is_greater(starving)


func test_a_supply_train_can_be_intercepted() -> void:
	var h := _hub()
	var a := _arm(h)
	var id := _mk(h, "player", "garrison", 0)
	a.add_unit(id, "spear", 10)
	a.army(id)["pos"] = [5000.0, 0.0]
	var foe := _mk(h, "raiders", "rebels", 1)
	a.add_unit(foe, "spear", 10)
	var t: Dictionary = a.send_train(id, [0.0, 0.0], 100.0, 50, 1)
	a.army(foe)["pos"] = [10.0, 0.0]
	assert_bool(a.intercept_train(int(t["t"]), foe)).is_true()
	_hours(h, 1)
	assert_int(a.trains().size()).is_equal(0)
	assert_float(float(a.army(id)["food"])).is_equal(200.0)


func test_levy_draws_farmers_cuts_the_harvest_and_ends() -> void:
	var h := _hub()
	var a := _arm(h)
	var fm: RefCounted = h.mod("farming")
	fm.ensure()
	var sid := -1
	var P: Dictionary = {}
	for pid: String in fm.parcels():
		P = fm.parcel(pid)
		sid = int(P["sid"])
		break
	assert_bool(sid >= 0).is_true()
	var base: float = fm._labour_units(P)
	var r: Dictionary = a.levy("player", sid, 25, 10, {"force": true})
	assert_bool(r["ok"]).is_true()
	assert_float(fm.levy_fraction(sid)).is_greater(0.0)
	assert_float(fm._labour_units(P)).is_less(base)
	assert_int(a.levied_at(sid)).is_equal(int(r["n"]))
	# a village cannot be levied twice at once
	assert_bool(a.levy("player", sid, 5, 10, {"force": true})["ok"]).is_false()
	_days(h, 1, 11)
	assert_float(fm.levy_fraction(sid)).is_equal(0.0)
	assert_float(fm._labour_units(P)).is_equal(base)
	assert_bool(a.army(r["id"]).is_empty()).is_true()


func test_levy_beyond_the_office_limit_is_refused_unless_forced() -> void:
	var h := _hub()
	var a := _arm(h)
	var lim: int = a.legal_limit("player", "levy")
	assert_int(lim).is_greater(0)
	var sid := 0
	var r: Dictionary = a.levy("player", sid, lim + 1000, 5)
	# capped by the village's hands first; if that is still over the legal limit it is refused
	if not bool(r["ok"]):
		assert_str(String(r["reason"])).is_equal("over_legal_limit")
	var f: Dictionary = a.levy("player", 1, lim + 1000, 5, {"force": true})
	assert_bool(f["ok"]).is_true()
	assert_bool(f["over"]).is_true()
	assert_float(a.suspicion("player")).is_greater(0.0)


# --- 6. settlement defence --------------------------------------------------------------------

func _fort(h: RefCounted, sid := 0, men := 40, per_shift := 2) -> String:
	var a := _arm(h)
	var g := _mk(h, "player", "garrison", sid, 2000)
	a.add_unit(g, "spear", men, {"lvl": 2, "eq": 0.7, "mo": 0.8, "di": 0.8})
	a.appoint(g, {"name": "Warden", "comp": 0.7, "pers": "loyal", "loy": 0.9})
	a.set_defence(sid, {"garrison": g, "patrols": 4, "shifts": 3, "per_shift": per_shift, "walls": 2})
	a.stock_up(sid, "food", 400.0)
	return g


func test_defence_plan_rating_watch_and_weak_points() -> void:
	var h := _hub()
	var a := _arm(h)
	_fort(h, 0, 40, 0)
	assert_float(a.watch_cover(0)).is_equal(0.0)
	assert_bool("gate_unwatched" in a.weak_points(0)).is_true()
	var r0: float = a.defence_rating(0)
	a.set_defence(0, {"per_shift": 2})
	assert_float(a.watch_cover(0)).is_equal(1.0)
	assert_bool("gate_unwatched" in a.weak_points(0)).is_false()
	assert_float(a.defence_rating(0)).is_greater(r0)
	var r1: float = a.defence_rating(0)
	a.set_defence(0, {"walls": 0})
	assert_float(a.defence_rating(0)).is_less(r1)
	assert_bool("no_walls" in a.weak_points(0)).is_true()
	assert_bool("undefended" in a.weak_points(5)).is_true()
	assert_float(a.defence_rating(5)).is_equal(0.0)


func test_alert_musters_the_garrison_and_evacuation_runs() -> void:
	var h := _hub()
	var a := _arm(h)
	var g := _fort(h)
	a.set_defence(0, {"muster": [120.0, 80.0]})
	assert_bool(a.raise_alert(0, 1)).is_true()
	assert_float(float(a.army(g)["dest"][0])).is_equal(120.0)
	assert_bool(a.raise_alert(0, 1)).is_false()
	assert_str(String(a.defence(0)["evac"]["state"])).is_equal("none")
	a.raise_alert(0, 3)                                      # level 3 starts the evacuation
	assert_str(String(a.defence(0)["evac"]["state"])).is_equal("evacuating")
	assert_int(int(a.defence(0)["evac"]["to"])).is_greater(-1)
	assert_bool(a.evacuate(0)["ok"]).is_false()
	_days(h, 1, 3)
	assert_str(String(a.defence(0)["evac"]["state"])).is_equal("done")
	assert_bool(a.return_evacuees(0)).is_true()
	assert_str(String(a.defence(0)["evac"]["state"])).is_equal("none")


func test_fallback_leaves_the_walls_weak() -> void:
	var h := _hub()
	var a := _arm(h)
	var g := _fort(h)
	a.set_defence(0, {"fallback": {"kind": "hill fort", "pos": [300.0, 300.0]}})
	var r0: float = a.defence_rating(0)
	assert_bool(a.fall_back(0)).is_true()
	assert_float(a.defence_rating(0)).is_less(r0 * 0.5)
	assert_float(float(a.army(g)["pos"][0])).is_equal(300.0)


func test_attackers_choose_assault_blockade_bribe_or_another_target() -> void:
	var h := _hub()
	var a := _arm(h)
	# a weak, unwatched, unpaid place
	var weak := _mk(h, "player", "garrison", 1, 0)
	a.add_unit(weak, "spear", 6, {"mo": 0.3, "di": 0.3})
	a.appoint(weak, {"name": "Sell", "comp": 0.2, "pers": "greedy", "loy": 0.1})
	a.set_defence(1, {"garrison": weak, "walls": 0})
	a.army(weak)["unpaid"] = 5
	_fort(h, 0, 60, 2)
	var strong_att := {"owner": "horde", "power": 400.0, "men": 200, "gold": 0.0, "patience": 3, "scouts": true}
	var pick: Dictionary = a.choose_attack(strong_att, [0, 1])
	assert_int(int(pick["sid"])).is_equal(1)                 # the weak one
	assert_str(String(pick["method"])).is_not_equal("skip")
	# a small band with gold prefers buying a gate where the garrison is unpaid
	var thieves := {"owner": "thieves", "power": 0.5, "men": 8, "gold": 500.0, "patience": 2, "scouts": true}
	var p2: Dictionary = a.choose_attack(thieves, [1])
	assert_str(String(p2["method"])).is_equal("bribe_insider")
	# a patient, strong army against well-stocked walls with a thin stock chooses to starve them
	a.set_defence(0, {"walls": 3})
	a.army(_fort_garrison(a, 0))["unpaid"] = 0
	var big := {"owner": "siegers", "power": 150.0, "men": 100, "gold": 0.0, "patience": 60, "scouts": true}
	a.stock_up(0, "food", -380.0)
	var p3: Dictionary = a.choose_attack(big, [0])
	assert_str(String(p3["method"])).is_equal("blockade")
	# a weak band against a strong, watched fort skips
	var tiny := {"owner": "tiny", "power": 5.0, "men": 5, "gold": 0.0, "patience": 1, "scouts": true}
	a.stock_up(0, "food", 600.0)
	assert_str(String(a.choose_attack(tiny, [0])["method"])).is_equal("skip")
	# deterministic
	assert_str(_norm(a.choose_attack(strong_att, [0, 1]))).is_equal(_norm(a.choose_attack(strong_att, [0, 1])))


func _fort_garrison(a: RefCounted, sid: int) -> String:
	return String(a.defence(sid)["garrison"])


func test_assault_blockade_and_bribe_are_resolved_and_logged() -> void:
	var h := _hub()
	var a := _arm(h)
	var g := _fort(h, 0, 80, 2)
	var ev: RefCounted = h.mod("events")
	var n0: int = ev.size()
	# a big army against the walls
	var res: Dictionary = a.resolve_attack({"owner": "horde", "power": 3000.0, "gold": 0.0}, 0, "assault", {"player_present": false})
	assert_bool(res["won"]).is_true()
	assert_bool(String(res["text"]).begins_with("While you were away")).is_true()
	assert_bool(bool(a.defence(0)["fell_back"])).is_true()
	assert_int(a.men(g)).is_less(80)
	assert_int(ev.size()).is_greater(n0)
	# a small raid is beaten off
	a.return_evacuees(0)
	var g2 := _fort(h, 2, 80, 2)
	var res2: Dictionary = a.resolve_attack({"owner": "scrubs", "power": 20.0}, 2, "assault", {"player_present": true})
	assert_bool(res2["won"]).is_false()
	assert_bool(String(res2["text"]).begins_with("While")).is_false()
	assert_bool(a.men(g2) > 0).is_true()
	# blockade starves the place and then it gives in
	var g3 := _fort(h, 3, 20, 2)
	a.army(g3)["food"] = 0.0
	a.stock_up(3, "food", -300.0)
	a.stock_up(3, "food", 40.0)
	a.resolve_attack({"owner": "siegers", "power": 100.0, "men": 60, "patience": 60}, 3, "blockade")
	assert_bool(a.blockades().has(3)).is_true()
	_days(h, 1, 40)
	assert_bool(a.blockades().has(3)).is_false()
	assert_float(float(a.defence(3)["stock"]["food"])).is_equal(0.0)
	assert_bool(bool(a.defence(3)["fell_back"])).is_true()          # starved into surrender
	# bribe a gate where the garrison is unpaid and disloyal
	var g4 := _mk(h, "player", "garrison", 4, 0)
	a.add_unit(g4, "spear", 10, {"mo": 0.2, "di": 0.2})
	a.appoint(g4, {"name": "Judas", "comp": 0.2, "pers": "greedy", "loy": 0.0})
	a.set_defence(4, {"garrison": g4})
	a.army(g4)["unpaid"] = 6
	assert_float(a.insider_chance(4)).is_greater(0.7)
	var betrayed := 0
	for d in 10:
		a.set_day(d)
		var r: Dictionary = a.resolve_attack({"owner": "thieves", "power": 80.0, "gold": 400.0}, 4, "bribe_insider")
		if r.get("betrayed", false):
			betrayed += 1
	assert_int(betrayed).is_greater(3)
	assert_int(int(a.stats["betrayals"])).is_equal(betrayed)


func test_npc_bandits_use_the_same_rules_against_defended_places() -> void:
	var h := _hub()
	var a := _arm(h)
	_fort(h, 0, 30, 1)
	_fort(h, 1, 10, 0)
	var texts := 0
	for w in 40:
		a.set_day(w * 7)
		texts += a.tick_week(w, {}).size()
	assert_int(texts).is_greater(0)
	assert_int(int(a.stats["raids"])).is_greater(0)


# --- 7. campaign and siege -------------------------------------------------------------------

func test_campaign_battle_uses_the_army_entity_and_logs_ar_ids() -> void:
	var h := _hub()
	var a := _arm(h)
	var cm: RefCounted = h.mod("campaign")
	cm.set_hq(0)
	cm.tick_day(0, {})
	var mine := _mk(h, "player", "royal", 0, 5000)
	a.add_unit(mine, "infantry", 200, {"lvl": 4, "eq": 0.9, "mo": 0.9, "di": 0.9})
	a.appoint(mine, {"name": "Marshal", "comp": 0.9, "pers": "bold"})
	var foe := _mk(h, "ongur_khanate", "royal", 1, 5000)
	a.add_unit(foe, "infantry", 200, {"lvl": 0, "eq": 0.1, "mo": 0.4, "di": 0.2})
	var c1: int = a.spawn_campaign(mine, 1)
	var c2: int = a.spawn_campaign(foe, 1)
	assert_int(c1).is_greater(0)
	assert_str(a.pid_of_campaign(c1)).is_equal(mine)
	assert_float(a.power_mult(c1)).is_greater(a.power_mult(c2))
	assert_float(a.power_mult(999)).is_equal(1.0)
	var out: Array = cm._resolve(1, [c1], [c2], false, {})
	assert_array(out).is_not_empty()
	var evs: Array = h.mod("events").by_actor(mine, 10)
	assert_bool(evs.filter(func(e: Dictionary) -> bool: return String(e["kind"]) == "battle").size() > 0).is_true()
	for e: Dictionary in evs:
		for act: String in e["actors"]:
			assert_bool(Reg.is_pid(act)).is_true()
	# the better army (trained, equipped, led) wins and loses fewer men
	assert_int(a.men(mine)).is_greater(a.men(foe) if a.army(foe).size() > 0 else 0)
	if not a.army(foe).is_empty():
		assert_int(a.men(mine)).is_greater(a.men(foe))


func test_destroyed_campaign_piece_disbands_the_entity() -> void:
	var h := _hub()
	var a := _arm(h)
	var cm: RefCounted = h.mod("campaign")
	cm.set_hq(0)
	cm.tick_day(0, {})
	var id := _mk(h, "player", "royal", 0)
	a.add_unit(id, "spear", 50)
	var cid: int = a.spawn_campaign(id, 0)
	var foe_id := _mk(h, "ongur_khanate", "royal", 1)
	a.add_unit(foe_id, "cavalry", 500, {"lvl": 5, "eq": 1.0, "mo": 1.0, "di": 1.0})
	var fid: int = a.spawn_campaign(foe_id, 0)
	cm._resolve(0, [fid], [cid], false, {})
	cm.tick_hour(0, {})
	a.sync_from_campaign(cid)
	assert_bool(a.army(id).is_empty() or a.men(id) < 50).is_true()


func test_siege_spec_comes_from_real_armies_and_losses_flow_back() -> void:
	var h := _hub()
	var a := _arm(h)
	var g := _fort(h, 0, 60, 2)
	var att := _mk(h, "ongur_khanate", "royal", 1, 3000)
	a.add_unit(att, "infantry", 120, {"lvl": 2, "eq": 0.6})
	a.add_unit(att, "archer", 60, {"lvl": 2})
	a.add_unit(att, "engineer", 30, {"lvl": 1})
	a.add_unit(att, "medic", 10)
	var spec: Dictionary = a.siege_spec(att, 0, {"key": "t0", "name": "Thornfield", "kind": "town", "defender": "player", "seed": 7})
	assert_int(int(spec["camp"]["men"])).is_equal(a.men(att))
	assert_int(int(spec["camp"]["engineers"])).is_equal(30)
	assert_int(int(spec["garrison"])).is_equal(a.men(g) + 4)
	assert_int((spec["att_units"] as Array).size()).is_equal(4)
	var sg: RefCounted = Siege.create(spec)
	assert_int(int(sg.s["garrison"])).is_equal(int(spec["garrison"]))
	sg.s["garrison"] = 20
	sg.s["camp"]["men"] = 150
	sg.s["status"] = "fallen"
	var before_def: int = a.men(g)
	var before_att: int = a.men(att)
	var res: Dictionary = a.apply_siege_result(att, 0, sg.s)
	assert_int(a.men(g)).is_less(before_def)
	assert_int(a.men(att)).is_less(before_att)
	assert_bool(res["fell"]).is_true()
	assert_bool(bool(a.defence(0)["fell_back"])).is_true()


# --- 8. NPC parity and budgets ---------------------------------------------------------------

func test_npc_kingdoms_field_armies_under_the_same_rules() -> void:
	var h := _hub()
	var a := _arm(h)
	a.tick_day(1, {})
	var npc: Array = []
	for id: String in a.ids():
		if bool(a.army(id)["npc"]):
			npc.append(id)
	assert_int(npc.size()).is_greater(3)
	for id2: String in npc:
		var ar: Dictionary = a.army(id2)
		assert_int(a.men(id2)).is_less_equal(a.legal_limit(String(ar["owner"]), "royal"))
		assert_int(int(a.upkeep(id2)["wages"])).is_greater(0)
	# they pay wages from the same purse, topped up from the kingdom's wealth (which shrinks)
	var id3: String = npc[0]
	var owner := String(a.army(id3)["owner"])
	var w0 := float(h.mod("factions").faction(owner)["wealth"])
	a.army(id3)["purse"] = 0
	_days(h, 2, 3)
	assert_float(float(h.mod("factions").faction(owner)["wealth"])).is_less(w0)
	assert_int(int(a.army(id3)["unpaid"])).is_equal(0)
	assert_int(int(a.army(id3)["ledger"]["wages"])).is_greater(0)
	# a broke kingdom goes unpaid and unfed like anyone else
	h.mod("factions").add_wealth(owner, -1.0e9)
	a.army(id3)["purse"] = 0
	a.army(id3)["food"] = 0.0
	var m0: int = a.men(id3)
	_days(h, 4, 14)
	assert_int(int(a.army(id3)["unpaid"])).is_greater(0)
	assert_int(int(a.army(id3)["hungry"])).is_greater(0)
	assert_int(a.men(id3)).is_less(m0)


func test_determinism() -> void:
	var out: Array = []
	for i in 2:
		var h := _hub()
		var a := _arm(h)
		var g := _fort(h, 0, 50, 1)
		a.set_hq("player", [0.0, 0.0])
		a.set_mode(g, "delegated")
		a.set_standing(g, {"kind": "patrol"})
		for d in range(1, 30):
			a.tick_day(d, {})
			_hours(h, 4)
			if d % 7 == 0:
				a.tick_week(d / 7, {})
		out.append(_norm(a.serialize()))
	assert_str(out[0]).is_equal(out[1])


func test_catch_up_matches_day_by_day_for_pay_and_food() -> void:
	var h1 := _hub()
	var h2 := _hub()
	var ids: Array = []
	for h: RefCounted in [h1, h2]:
		var id := _mk(h, "player", "garrison", 0, 600)
		_arm(h).add_unit(id, "infantry", 30)
		ids.append(id)
	_days(h1, 1, 6)
	_arm(h2).catch_up(6, {})
	assert_int(int(_arm(h2).army(ids[1])["purse"])).is_equal(int(_arm(h1).army(ids[0])["purse"]))
	assert_float(float(_arm(h2).army(ids[1])["food"])).is_equal(float(_arm(h1).army(ids[0])["food"]))
	# a long absence without money costs men, in one step
	var h3 := _hub()
	var id3 := _mk(h3, "player", "mercenary", 0, 0)
	_arm(h3).add_unit(id3, "infantry", 100, {"di": 0.2})
	_arm(h3).catch_up(30, {})
	assert_int(_arm(h3).men(id3)).is_less(100)


func test_save_round_trip_through_json() -> void:
	var h := _hub()
	var a := _arm(h)
	var g := _fort(h, 0, 40, 2)
	a.set_hq("player", [0.0, 0.0])
	a.army(g)["pos"] = [2500.0, 0.0]
	var uid: int = a.army(g)["units"][0]["u"]
	a.train(g, uid, 3)
	a.send_order(g, {"kind": "move", "x": 100.0, "y": 0.0})
	a.send_train(g, [0.0, 0.0], 100.0, 10, 1)
	a.set_hostile("player", "raiders")
	var foe := _mk(h, "raiders", "rebels", 1)
	a.add_unit(foe, "scout", 5)
	a.army(foe)["pos"] = [2600.0, 0.0]
	a.scout_pass()
	a.levy("player", 2, 10, 15, {"force": true})
	a.raise_alert(0, 3)
	a.resolve_attack({"owner": "b", "power": 50.0, "men": 20, "patience": 30}, 0, "blockade")
	a.recognise("legion")
	_days(h, 1, 3)
	_hours(h, 3)
	var raw: String = JSON.stringify(h.serialize())
	var h2 := _hub()
	h2.deserialize(JSON.parse_string(raw))
	assert_str(_diff(JSON.parse_string(_norm(_arm(h2).serialize())), JSON.parse_string(_norm(_arm(h).serialize())))).is_equal("")
	# behaves the same after the load
	_days(h, 4, 9)
	_days(h2, 4, 9)
	assert_str(_diff(JSON.parse_string(_norm(_arm(h2).serialize())), JSON.parse_string(_norm(_arm(h).serialize())))).is_equal("")
	assert_float(h2.mod("farming").levy_fraction(2)).is_equal(h.mod("farming").levy_fraction(2))
	# ids keep counting after a load
	var nid: String = _mk(h2)
	assert_bool(_arm(h).ids().has(nid)).is_false()


func test_tick_cost_with_many_armies() -> void:
	var h := _hub()
	var a := _arm(h)
	for i in 60:
		var id := _mk(h, "owner%d" % (i % 6), "garrison", i % 20, 5000)
		for k in 4:
			a.add_unit(id, ["spear", "archer", "scout", "cavalry"][k], 20)
		a.army(id)["pos"] = [float(i * 150 % 3000), float(i * 90 % 2000)]
		if i % 3 == 0:
			a.set_mode(id, "delegated")
			a.set_standing(id, {"kind": "patrol"})
	for i in 5:
		a.set_hostile("owner%d" % i, "owner%d" % (i + 1))
	for i in 10:
		a.set_defence(i, {"garrison": a.ids()[i], "per_shift": 2})
	var t0 := Time.get_ticks_usec()
	# best of three passes: a loaded CI box adds noise but never makes the code faster
	var worst_hour := 1 << 30
	var worst_chunk := 1 << 30
	for rep in 3:
		var wh := 0
		for i in 24:
			var t1 := Time.get_ticks_usec()
			a.tick_hour(i, {})
			wh = maxi(wh, Time.get_ticks_usec() - t1)
		worst_hour = mini(worst_hour, wh)
		var wc := 0
		for ch: Callable in a.tick_day_chunks(1 + rep, {}):
			var t2 := Time.get_ticks_usec()
			ch.call()
			wc = maxi(wc, Time.get_ticks_usec() - t2)
		worst_chunk = mini(worst_chunk, wc)
	var t3 := Time.get_ticks_usec()
	a.known_map("owner0")
	var kmap := Time.get_ticks_usec() - t3
	print("armies: 60 armies worst hour %d us, worst day chunk %d us, known_map %d us, total %d us" % [worst_hour, worst_chunk, kmap, Time.get_ticks_usec() - t0])
	assert_int(worst_hour).is_less(4000)        # doc: hour 0.3 ms per 10 armies, x2 headroom for a shared runner
	assert_int(worst_chunk).is_less(8000)
	assert_int(kmap).is_less(1000)
	assert_int(a.count()).is_less_equal(D.CAMP_ARMY_MAX)
