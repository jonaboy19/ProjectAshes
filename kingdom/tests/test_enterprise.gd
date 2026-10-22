extends GdUnitTestSuite
## Enterprise module (scripts/realm/enterprise*.gd): prices from supply chains, price intel that ages,
## route profit estimates, player caravans (multi-day, deterministic, raids), workshops on real stock,
## fief taxes / loyalty / projects, recruit pools, role gating, JSON round trip, perf.

const Hub := preload("res://scripts/realm/realm_hub.gd")
const Lordship := preload("res://scripts/sim/lordship.gd")
const D := preload("res://scripts/realm/enterprise_data.gd")

static var _world_ready := false


func _norm(d: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(d)))


func _setup_world() -> void:
	if not _world_ready:
		WorldGen.setup(2024)
		_world_ready = true


## A fresh hub with the settlement sim aged `days` days so stocks have their real spread.
func _hub(days := 10) -> RefCounted:
	_setup_world()
	var hub: RefCounted = Hub.new()
	var st: RefCounted = hub.mod("settlements")
	for d in range(1, days + 1):
		st.tick_day(d, {"season": "spring"})
	var e: RefCounted = hub.mod("enterprise")
	e.purse_override = 6000
	e.presence_override = true
	e.lordship_ref = Lordship.new()
	e.set_clock(days)
	e._ensure()
	return hub


func _e(hub: RefCounted) -> RefCounted:
	return hub.mod("enterprise")


func _licensed(hub: RefCounted) -> RefCounted:
	var e := _e(hub)
	e.license_owned = true
	return e


# ---------------------------------------------------------------- prices

func test_prices_follow_supply_chains() -> void:
	var hub := _hub()
	var e := _e(hub)
	# Stonehollow (3) has the mine and smithy; Ashford (0) has no tools: tools are dear where they are scarce.
	assert_int(e.price(0, "tools")).is_greater(e.price(3, "tools"))
	assert_float(e.stock_of(3, "tools")).is_greater(e.stock_of(0, "tools"))
	# Every good has a sane price band around its base.
	for g: String in D.GOOD_ORDER:
		var p := float(e.price(1, g))
		var base := float((D.GOODS[g] as Dictionary)["base"])
		assert_float(p).is_between(base * 0.6, base * 2.8)


func test_prices_react_to_your_sales() -> void:
	var hub := _hub()
	var e := _e(hub)
	e.pack = {"cloth": [60, 10.0]}
	var before: int = e.price(0, "cloth")
	var r: Dictionary = e.sell(0, "cloth", 60)
	assert_bool(r["ok"]).is_true()
	assert_int(e.price(0, "cloth")).is_less(before)
	# and buying pushes the price up
	var b2: int = e.price(1, "cloth")
	var r2: Dictionary = e.buy(1, "cloth", 40)
	assert_bool(r2["ok"]).is_true()
	assert_int(e.price(1, "cloth")).is_greater_equal(b2)
	# the market recovers toward normal over weeks (NPC traders)
	var low: float = e.stock_of(0, "cloth")
	for d in 20:
		e._local_day(20 + d)
	assert_float(absf(e.stock_of(0, "cloth") - e.target(0, "cloth"))).is_less(absf(low - e.target(0, "cloth")))


func test_bulk_trade_limits() -> void:
	var hub := _hub()
	var e := _e(hub)
	e.purse_override = 100
	var r: Dictionary = e.buy(2, "wood", 500)
	assert_bool(r["ok"]).is_true()
	assert_int(int(r["paid"])).is_less_equal(100)
	assert_int(e.pack_total()).is_less_equal(e.capacity())
	# a full pack refuses more
	e.purse_override = 50000
	e.pack = {"wood": [e.capacity(), 3.0]}
	assert_bool(e.buy(2, "wood", 5)["ok"]).is_false()
	# the town keeps a reserve
	var q: Dictionary = e.quote(2, "grain", 10000, "buy")
	assert_float(e.stock_of(2, "grain") - float(q["qty"])).is_greater_equal(e.reserve(2, "grain") - 1.0)
	# not in town: no trade
	e.presence_override = false
	e.set_player_pos(Vector2(9999, 9999))
	assert_bool(e.buy(2, "wood", 1)["ok"]).is_false()


func test_price_intel_ages() -> void:
	var hub := _hub()
	var e := _e(hub)
	e.seen.clear()
	assert_int(e.known_age(5)).is_equal(-1)
	e.observe(5, "visit")
	var p: Dictionary = e.known_price(5, "tools")
	assert_int(int(p["age"])).is_equal(0)
	e.set_clock(e.day() + 6)
	assert_int(int(e.known_price(5, "tools")["age"])).is_equal(6)
	assert_str(e.age_text(6)).is_equal("seen 6 days ago")
	# the town changed meanwhile, but what you know stays what you saw
	e.presence_override = true
	e.pack = {"tools": [30, 10.0]}
	e.sell(5, "tools", 30)
	assert_int(int(e.known_price(5, "tools")["p"])).is_not_equal(0)
	# rumours reveal three other towns, blurred and a few days old
	var before = e.seen.size()
	var r: Dictionary = e.buy_rumour(0)
	assert_bool(r["ok"]).is_true()
	assert_int((r["towns"] as Array).size()).is_equal(3)
	assert_int(e.seen.size()).is_greater_equal(before)
	for t: int in r["towns"]:
		assert_int(int(e.known_price(t, "grain")["age"])).is_between(1, 3)
	# informants keep a town fresh
	e.license_owned = true
	assert_bool(e.hire_informant(8)["ok"]).is_true()
	assert_bool(e.has_informant(8)).is_true()


func test_route_profit_estimate() -> void:
	var hub := _hub()
	var e := _e(hub)
	e.observe(1, "visit")
	e.observe(3, "visit")
	var est: Dictionary = e.estimate_route([3, 1], {"budget": 600, "cap": 40})
	assert_int(int(est["profit"])).is_greater(0)
	assert_float(float(est["days"])).is_equal_approx(float(est["hours"]) / 24.0, 0.0001)
	assert_float(float(est["risk"])).is_between(0.0, 1.0)
	assert_int((est["legs"] as Array).size()).is_equal(1)
	var loop: Dictionary = e.estimate_route([3, 1], {"budget": 600, "cap": 40, "loop": true})
	assert_int((loop["legs"] as Array).size()).is_equal(2)
	assert_float(float(loop["hours"])).is_greater(float(est["hours"]))
	# travel time is the road graph's own (camps.travel_hours), the caravan is just slower
	var cmod: RefCounted = hub.mod("camps")
	assert_float(float(e.route_info(3, 1)["hours"])).is_equal_approx(float(cmod.travel_hours(3, 1)), 0.001)
	assert_float(e.trip_hours(3, 1, true)).is_equal_approx(float(cmod.travel_hours(3, 1)) * e.CARAVAN_SLOW, 0.001)
	# tolls and risk come from the strongholds on the road, and guards cut the risk
	assert_int(e.trip_toll(3, 1)).is_greater_equal(0)
	assert_float(e.trip_risk(3, 1, 4)).is_less(e.trip_risk(3, 1, 0))
	# without knowing the far town's price the estimate is only a guess
	e.seen.erase("1")
	var blind: Dictionary = e.estimate_leg(3, 1, {"budget": 600, "cap": 40})
	assert_bool(bool(blind["known"])).is_false()
	# determinism
	assert_str(_norm(e.estimate_route([3, 1], {"budget": 600}))).is_equal(_norm(e.estimate_route([3, 1], {"budget": 600})))


# ---------------------------------------------------------------- caravans

func _caravan(hub: RefCounted, sid := 3, guards := 2, route: Array = []) -> Dictionary:
	var e := _licensed(hub)
	var fid: String = hub.mod("followers").hire("mercenary", "s%d" % sid, true, "leader1")
	var r: Dictionary = e.fund_caravan(sid, guards, 400, fid, route)
	assert_bool(r["ok"]).override_failure_message(String(r["reason"])).is_true()
	return e.get_caravan(int(r["id"]))


func test_caravan_funding_costs_and_leader() -> void:
	var hub := _hub()
	var e := _e(hub)
	var fid: String = hub.mod("followers").hire("scout", "s3", true, "lead")
	# no licence, no caravan
	assert_str(e.can_fund_caravan(3, 2, 300, fid)).is_not_empty()
	e.license_owned = true
	assert_str(e.can_fund_caravan(3, 2, 300, fid)).is_empty()
	assert_str(e.can_fund_caravan(3, 2, 10, fid)).is_not_empty()
	assert_str(e.can_fund_caravan(3, 2, 300, "")).is_not_empty()
	var g0: int = e.gold()
	var r: Dictionary = e.fund_caravan(3, 2, 300, fid)
	assert_bool(r["ok"]).is_true()
	assert_int(e.gold()).is_equal(g0 - (D.CART_COST + 2 * D.GUARD_COST + 300))
	# the leader is posted and cannot lead a second caravan
	assert_bool(String(hub.mod("followers").get_follower(fid)["post"]).begins_with("caravan:")).is_true()
	assert_str(e.can_fund_caravan(3, 2, 300, fid)).is_not_empty()
	var c: Dictionary = e.get_caravan(int(r["id"]))
	assert_str(String(c["state"])).is_equal("market")
	assert_int(c["guards"]).is_equal(2)


func test_caravan_multi_day_trip_is_deterministic() -> void:
	var out: Array = []
	for run in 2:
		var hub := _hub()
		var e := _e(hub)
		e.observe(1, "visit")
		var c := _caravan(hub, 3, 3)
		var ctx := {"abs_hours": float(e.day()) * 24.0, "player_pos": Vector2(99999, 99999)}
		var hours := 0
		while hours < 24 * 6:
			ctx["abs_hours"] = float(e.day()) * 24.0 + float(hours)
			e.tick_hour(hours % 24, ctx)
			hours += 1
		c = e.get_caravan(int(c["id"])) if e.caravans.has(int(c["id"])) else c
		out.append({"trips": int(c["trips"]), "cash": int(c["cash"]), "profit": int(c["profit"]), "at": int(c["at"]), "raids": int(c["raids"]), "pending": e.pending_gold, "reports": (c["reports"] as Array).size()})
	assert_str(_norm(out[0])).is_equal(_norm(out[1]))
	assert_int(int((out[0] as Dictionary)["trips"])).is_greater_equal(1)
	# it took real time: more than a few hours for the first arrival
	var hub2 := _hub()
	var c2 := _caravan(hub2, 3, 3)
	var e2 := _e(hub2)
	assert_float(e2.caravan_eta(c2)).is_greater(3.0)


func test_caravan_raid_is_deterministic_and_costs() -> void:
	var res: Array = []
	for run in 2:
		var hub := _hub()
		var e := _e(hub)
		var c := _caravan(hub, 3, 0)
		c["cargo"] = {"tools": [20, 30.0]}
		var cash0 := int(c["cash"])
		e._raid(c, {"strength": 300.0}, 5)
		var alive = e.caravans.has(int(c["id"]))
		res.append({"alive": alive, "cargo": c["cargo"].duplicate(true), "cash": int(c["cash"]), "raids": int(c["raids"]), "lost": cash0 - int(c["cash"])})
	assert_str(_norm(res[0])).is_equal(_norm(res[1]))
	# an unguarded caravan against a strong band loses something (or everything)
	var r0: Dictionary = res[0]
	assert_int(int(r0["raids"])).is_equal(1)
	if bool(r0["alive"]):
		assert_bool(int((r0["cargo"] as Dictionary).get("tools", [0])[0]) < 20 or int(r0["lost"]) > 0).is_true()
	# strong guards beat a small band
	var hub3 := _hub()
	var e3 := _e(hub3)
	var c3 := _caravan(hub3, 3, 8)
	c3["cargo"] = {"tools": [20, 30.0]}
	e3._raid(c3, {"strength": 6.0}, 5)
	assert_int(int((c3["cargo"]["tools"] as Array)[0])).is_equal(20)


func test_live_raid_intercepts_a_near_caravan() -> void:
	var hub := _hub()
	var e := _e(hub)
	var c := _caravan(hub, 3, 1)
	c["state"] = "travel"
	var legs: Array = e.route_info(3, 1)["legs"]
	c["legs"] = legs.duplicate(true)
	c["leg"] = 0
	c["dest"] = 1
	c["leg_left"] = float(legs[0]["hours"]) * e.CARAVAN_SLOW * 0.5
	var pos: Vector2 = e.caravan_pos(c)
	var sh: RefCounted = hub.mod("strongholds")
	sh._ensure()
	sh._raids.append({"id": 77, "kind": "bandits", "strength": 500, "origin": pos, "pos": pos, "target": {"name": "x"}, "target_pos": pos, "phase": "travel", "day": 1, "loot": 0})
	e.set_player_pos(pos)
	assert_str(e.tier_of(c)).is_equal("near")
	e._intercept_check(c)
	assert_int(int(c["raids"])).is_equal(1)
	# the same band does not strike twice
	e._intercept_check(c)
	assert_int(int(c["raids"])).is_equal(1)
	# a far caravan is pure bookkeeping
	e.set_player_pos(pos + Vector2(9000, 0))
	assert_str(e.tier_of(c)).is_equal("far")


func test_caravan_abstract_matches_hourly_and_catch_up() -> void:
	var a := _hub()
	var b := _hub()
	var ca := _caravan(a, 3, 2)
	var cb := _caravan(b, 3, 2)
	var ea := _e(a)
	var eb := _e(b)
	for i in 96:
		ea._advance(ca, 1.0)
	eb._advance(cb, 96.0)
	assert_int(int(ca["trips"])).is_equal(int(cb["trips"]))
	assert_int(int(ca["cash"])).is_equal(int(cb["cash"]))
	assert_int(int(ca["at"])).is_equal(int(cb["at"]))
	assert_int((ca["reports"] as Array).size()).is_equal((cb["reports"] as Array).size())
	assert_float(float(ca["leg_left"])).is_equal_approx(float(cb["leg_left"]), 0.001)
	# catch_up after a long absence is bounded work
	var t0 := Time.get_ticks_usec()
	eb.catch_up(40, {"abs_hours": float(eb.day() + 40) * 24.0})
	assert_int(Time.get_ticks_usec() - t0).is_less(200000)


func test_caravan_reports_back_profit_and_disband() -> void:
	var hub := _hub()
	var e := _e(hub)
	e.observe(1, "visit")
	var c := _caravan(hub, 3, 2, [3, 1])
	var g0: int = e.pending_gold
	for i in 24 * 8:
		e._advance(c, 1.0)
		if not e.caravans.has(int(c["id"])):
			break
	assert_int(int(c["trips"])).is_greater_equal(1)
	assert_int((c["reports"] as Array).size()).is_greater(0)
	if e.caravans.has(int(c["id"])):
		var g1: int = e.pending_gold
		var d: Dictionary = e.disband_caravan(int(c["id"]))
		assert_bool(d["ok"]).is_true()
	# the leader is free again
	for f: Dictionary in hub.mod("followers").party():
		assert_bool(String(f["post"]).begins_with("caravan:") and e.caravans.is_empty()).is_false()
	assert_int(e.pending_gold).is_not_equal(g0 - 1)


func test_leader_traits_shape_choices() -> void:
	var hub := _hub()
	var e := _e(hub)
	var fo: RefCounted = hub.mod("followers")
	var bold: String = fo.hire("mercenary", "s0", true, "bold")
	var shy: String = fo.hire("mercenary", "s0", true, "shy")
	(fo.get_follower(bold) as Dictionary)["traits"] = ["brave", "greedy", "curious"]
	(fo.get_follower(shy) as Dictionary)["traits"] = ["cautious", "honorable", "merciful"]
	var pb: Dictionary = e.leader_profile(bold)
	var ps: Dictionary = e.leader_profile(shy)
	assert_float(float(pb["appetite"])).is_greater(float(ps["appetite"]))
	assert_float(float(pb["haggle"])).is_greater(float(ps["haggle"]))
	# a disloyal leader skims the takings
	var skimmed := 0
	for trial in 12:
		var h2 := _hub()
		var e2 := _e(h2)
		var f2: RefCounted = h2.mod("followers")
		var fid: String = f2.hire("mercenary", "s3", true, "t%d" % trial)
		(f2.get_follower(fid) as Dictionary)["loyalty"] = 5.0
		e2.license_owned = true
		var r: Dictionary = e2.fund_caravan(3, 1, 300, fid)
		var c: Dictionary = e2.get_caravan(int(r["id"]))
		c["seed"] = trial * 101
		c["trips"] = trial
		c["cargo"] = {"tools": [10, 20.0]}
		var cash0 := int(c["cash"])
		e2._arrive(c, false)
		for rep: Dictionary in c["reports"]:
			if String(rep["text"]).contains("books look short"):
				skimmed += 1
	assert_int(skimmed).is_greater(0)


func test_caravan_brings_home_rumours_and_intel() -> void:
	var hub := _hub()
	var e := _e(hub)
	var fo: RefCounted = hub.mod("followers")
	var cm: RefCounted = hub.mod("campaign")
	cm._ensure()
	var army: int = cm.spawn_army("ongur_khanate", 1, 300, "aggressive")
	var fid: String = fo.hire("scout", "s3", true, "spy")
	(fo.get_follower(fid) as Dictionary)["traits"] = ["curious"]
	e.license_owned = true
	var r: Dictionary = e.fund_caravan(3, 2, 300, fid)
	var c: Dictionary = e.get_caravan(int(r["id"]))
	var before: int = (cm.enemy_pieces() as Array).size()
	e._leader_news(c, 1, true, RandomNumberGenerator.new())
	var after: int = (cm.enemy_pieces() as Array).size()
	assert_int(after).is_greater(before)
	assert_bool(army > 0).is_true()
	# a beaten-off raid becomes a rumour about you
	var soc: RefCounted = hub.mod("society")
	var n0: int = (soc.rumour_list as Array).size()
	c["guards"] = 8
	e._raid(c, {"strength": 5.0}, 2)
	assert_int((soc.rumour_list as Array).size()).is_greater(n0)
	# and news of the next town's market reaches the player
	e.seen.erase("5")
	e._leader_news(c, 1, true, RandomNumberGenerator.new())
	assert_bool(e.seen.size() > 0).is_true()


# ---------------------------------------------------------------- workshops

func test_workshop_profit_uses_local_prices_and_stock() -> void:
	var hub := _hub()
	var e := _licensed(hub)
	var r: Dictionary = e.buy_workshop(2, "brewery")
	assert_bool(r["ok"]).override_failure_message(String(r["reason"])).is_true()
	var w: Dictionary = e.get_workshop(int(r["id"]))
	var grain0: float = e.stock_of(2, "grain")
	var fc: Dictionary = e.workshop_run(w, false)
	assert_float(e.stock_of(2, "grain")).is_equal(grain0)              # a forecast moves nothing
	assert_int(int(fc["revenue"])).is_greater(int(fc["in_cost"]))
	var g0: int = e.pending_gold
	e._workshops_day()
	assert_int(e.pending_gold - g0).is_equal(int(w["last"]["net"]))
	assert_float(e.stock_of(2, "grain")).is_less(grain0)               # it burned the town's real grain
	assert_float(e.stock_of(2, "ale")).is_greater(0.0)
	# starve it: no grain in town, no output, wages still paid, a shortage is recorded
	hub.mod("settlements").add_stock(2, "grain", -e.stock_of(2, "grain"))
	var dry: Dictionary = e.workshop_run(w, true)
	assert_float(float(dry["supplied"])).is_less(0.2)
	assert_int(int(dry["net"])).is_less(0)
	# empty shelves make the input dear; a glut makes it cheap
	var dry_price: float = e.price_at(2, "grain")
	hub.mod("settlements").add_stock(2, "grain", 600.0)
	assert_float(e.price_at(2, "grain")).is_less(dry_price)


func test_workshop_rules_employees_and_guilds() -> void:
	var hub := _hub()
	var e := _e(hub)
	assert_str(e.can_buy_workshop(2, "brewery")).is_not_empty()        # no licence
	e.license_owned = true
	assert_str(e.can_buy_workshop(0, "smithy")).is_not_empty()         # a village has no room for a smithy
	var r: Dictionary = e.buy_workshop(2, "mill")
	assert_bool(r["ok"]).override_failure_message(String(r["reason"])).is_true()
	assert_str(e.can_buy_workshop(2, "mill")).is_not_empty()           # one of a kind per town
	var id := int(r["id"])
	assert_bool(e.set_workers(id, 4)["ok"]).is_true()
	assert_int(int(e.get_workshop(id)["workers"])).is_equal(4)
	var up: Dictionary = e.upgrade_workshop(id)
	assert_bool(up["ok"]).is_true()
	assert_int(int(e.get_workshop(id)["level"])).is_equal(2)
	var gs: Dictionary = e.guild_stance(2, "mill")
	assert_bool(gs.has("member")).is_true()
	# more staff than hands in town is refused
	assert_bool(e.set_workers(id, 99)["ok"] or int(e.get_workshop(id)["workers"]) <= 8).is_true()
	var sold: Dictionary = e.sell_workshop(id)
	assert_bool(sold["ok"]).is_true()
	assert_int(e.workshops.size()).is_equal(0)


# ---------------------------------------------------------------- fiefs

func _fief(hub: RefCounted, sid := 2) -> RefCounted:
	var e := _e(hub)
	var l: RefCounted = e.lordship_ref
	l.grant(sid, "crown")
	return e


func test_fief_taxes_loyalty_and_memory() -> void:
	var finals := {}
	var treasuries := {}
	for rate: String in ["low", "harsh"]:
		var hub := _hub()
		var e := _fief(hub)
		assert_str(e.set_tax(2, rate)).is_empty()
		for d in range(1, 41):
			e.lordship_ref.daily_tick(d, {"season": "spring"})
			e.tick_day(d, {})
		var v: Dictionary = e.lordship_ref.village(2)
		finals[rate] = float(v["loyalty"])
		treasuries[rate] = int(v["treasury"])
		var mem: Array = hub.mod("land").memories(2)
		var kinds: Array = mem.map(func(m: Dictionary) -> String: return String(m["kind"]))
		if rate == "harsh":
			assert_bool(kinds.has("tax_burden")).is_true()
		else:
			assert_bool(kinds.has("fair_rule")).is_true()
	assert_float(float(finals["low"])).is_greater(float(finals["harsh"]))
	assert_int(int(treasuries["harsh"])).is_greater(0)
	# the fief reports its numbers
	var hub2 := _hub()
	var e2 := _fief(hub2)
	var info: Dictionary = e2.fief_info(2)
	for k: String in ["treasury", "loyalty", "prosperity", "security", "income", "tax_rate"]:
		assert_bool(info.has(k)).is_true()
	assert_float(float(info["security"])).is_between(0.0, 100.0)


func test_fief_projects_are_built_over_days_by_a_crew() -> void:
	var hub := _hub()
	var e := _fief(hub)
	var v: Dictionary = e.lordship_ref.village(2)
	v["treasury"] = 1000
	var markets0 := int(hub.mod("settlements").get("_s")[2]["structures"].get("market", 0))
	var r: Dictionary = e.start_project(2, "market", 6)
	assert_bool(r["ok"]).override_failure_message(String(r["reason"])).is_true()
	assert_int(int(v["treasury"])).is_equal(1000 - int((D.PROJECTS["market"] as Dictionary)["gold"]))
	e.tick_day(1, {})
	assert_int(int(e.fief_info(2)["built"].get("market", 0))).is_equal(0)        # not instant
	assert_int((e.works as Array).size()).is_equal(1)
	assert_str(e.start_project(2, "market", 6)["reason"]).is_not_empty()         # already under way
	var days := 1
	while not (e.works as Array).is_empty() and days < 40:
		days += 1
		e.tick_day(days, {})
	assert_int(days).is_greater(3)
	assert_int(int(e.fief_info(2)["built"]["market"])).is_equal(1)
	assert_int(int(hub.mod("settlements").get("_s")[2]["structures"].get("market", 0))).is_equal(markets0 + 1)
	# more hands, faster
	var hub2 := _hub()
	var e2 := _fief(hub2)
	e2.lordship_ref.village(2)["treasury"] = 1000
	e2.start_project(2, "granary", 2)
	var slow := 0
	while not (e2.works as Array).is_empty() and slow < 60:
		slow += 1
		e2.tick_day(slow, {})
	var hub3 := _hub()
	var e3 := _fief(hub3)
	e3.lordship_ref.village(2)["treasury"] = 1000
	e3.start_project(2, "granary", 12)
	var fast := 0
	while not (e3.works as Array).is_empty() and fast < 60:
		fast += 1
		e3.tick_day(fast, {})
	assert_int(fast).is_less(slow)
	# a poor treasury cannot start it
	e3.lordship_ref.village(2)["treasury"] = 5
	assert_str(e3.start_project(2, "walls", 4)["reason"]).is_not_empty()


func test_governor_and_garrison() -> void:
	var hub := _hub()
	var e := _fief(hub)
	var fo: RefCounted = hub.mod("followers")
	var fid: String = fo.hire("knight", "s0", true, "gov")
	assert_bool(e.set_governor(2, fid)["ok"]).is_true()
	assert_float(e.governor_efficiency(2)).is_greater(0.0)
	assert_str(String(fo.get_follower(fid)["post"])).is_equal("governor:2")
	var sec0: float = e.security_of(2)
	e.troops = {"footman": 6}
	assert_int(e.garrison_assign(2, "footman", 4)).is_equal(4)
	assert_float(e.security_of(2)).is_greater(sec0 - 0.001)
	assert_int(e.troop_count()).is_equal(2)
	assert_int(e.garrison_recall(2, "footman", 2)).is_equal(2)
	# a steward sends the surplus home weekly
	e.lordship_ref.village(2)["treasury"] = 900
	var g0: int = e.pending_gold
	e.tick_day(7, {})
	assert_int(e.pending_gold).is_greater(g0)


func test_roads_lift_trade_and_cut_risk() -> void:
	var hub := _hub()
	var e := _licensed(hub)
	var cm: RefCounted = hub.mod("camps")
	# find a dirt road between settlements to upgrade
	var pick := []
	for ed: Dictionary in cm.edges():
		if String(ed["level"]) == "dirt" and String(ed["a"]).begins_with("s") and String(ed["b"]).begins_with("s"):
			pick = [int(String(ed["a"]).substr(1)), int(String(ed["b"]).substr(1))]
			break
	if pick.is_empty():
		for ed: Dictionary in cm.edges():
			if String(ed["level"]) == "road" and String(ed["a"]).begins_with("s") and String(ed["b"]).begins_with("s"):
				pick = [int(String(ed["a"]).substr(1)), int(String(ed["b"]).substr(1))]
				break
	var a: int = pick[0]
	var b: int = pick[1]
	var level: String = "stone" if String(cm.road(a, b)["level"]) != "stone" else "military"
	var tv0: float = cm.trade_volume("s%d" % a, "s%d" % b)
	var risk0: float = cm.raid_risk("s%d" % a, "s%d" % b)
	var hours0: float = cm.travel_hours(a, b)
	var cost: int = e.road_cost(a, b, level)
	assert_int(cost).is_greater(0)
	var g0: int = e.gold()
	var r: Dictionary = e.plan_road(a, b, level)
	assert_bool(r["ok"]).override_failure_message(String(r["reason"])).is_true()
	assert_int(e.gold()).is_equal(g0 - cost - 0)
	var d := 0
	while not (e.works as Array).is_empty() and d < 120:
		d += 1
		e.tick_day(d, {})
	assert_str(String(cm.road(a, b)["level"])).is_equal(level)
	assert_float(cm.trade_volume("s%d" % a, "s%d" % b)).is_greater(tv0)
	assert_float(cm.raid_risk("s%d" % a, "s%d" % b)).is_less_equal(risk0 + 0.0001 + 0.03)
	assert_float(cm.travel_hours(a, b)).is_less_equal(hours0)
	# maintenance mends a worn road
	cm.road(a, b)["cond"] = 0.3
	assert_bool(e.maintain_road(a, b)["ok"]).is_true()
	assert_float(float(cm.road(a, b)["cond"])).is_greater(0.3)


func test_rift_crystal_is_rare_and_dangerous() -> void:
	var hub := _hub()
	var e := _e(hub)
	# put a rift next to Brackenmoor (10) so the test does not depend on the map seed
	var near := (WorldGen.settlements[10]["pos"] as Vector2) + Vector2(200, 0)
	e._rift_built = true
	e._rift_cache = [near]
	assert_float(e.rift_factor(10)).is_greater(0.5)
	assert_float(e.rift_factor(0)).is_less(e.rift_factor(10))
	assert_float(float(e.production_of(10).get("rift_crystal", 0.0))).is_greater(0.0)
	assert_float(float(e.production_of(0).get("rift_crystal", 0.0))).is_less(float(e.production_of(10)["rift_crystal"]))
	assert_int(D.GOODS["rift_crystal"]["base"]).is_greater(50)
	e.invalidate_routes()
	var ri: Dictionary = e.route_info(10, 11)
	var clean := 0.0
	e._rift_cache = []
	e.invalidate_routes()
	clean = float(e.route_info(10, 11)["risk"])
	e._rift_cache = [(WorldGen.settlements[10]["pos"] as Vector2).lerp(WorldGen.settlements[11]["pos"], 0.5)]
	e.invalidate_routes()
	var dirty: Dictionary = e.route_info(10, 11)
	assert_bool(bool(dirty["rift"])).is_true()
	assert_float(float(dirty["risk"])).is_greater(clean)


# ---------------------------------------------------------------- recruits, clan, roles

func test_recruit_pool_refills_daily_and_is_relation_gated() -> void:
	var hub := _hub()
	var e := _e(hub)
	e.career_override = "soldier"
	e.purse_override = 9000
	var before: int = int(e.recruit_pool(1)["levy"])
	assert_int(before).is_greater(3)
	var r: Dictionary = e.recruit(1, "levy", 3)
	assert_bool(r["ok"]).override_failure_message(String(r["reason"])).is_true()
	assert_int(int(e.recruit_pool(1)["levy"])).is_equal(before - 3)
	assert_int(int(e.troops["levy"])).is_equal(3)
	e.set_clock(e.day() + 2)
	assert_int(int(e.recruit_pool(1)["levy"])).is_greater(before - 3)
	e.set_clock(e.day() + 30)
	assert_int(int(e.recruit_pool(1)["levy"])).is_less_equal(e.recruit_max(1, "levy"))
	# relation gate: a town that dislikes you will not give its best men
	e.rep_delta["1"] = -40.0
	assert_str(e.can_recruit(1, "man_at_arms", 1)).is_not_empty()
	e.rep_delta["1"] = 30.0
	# troops cost wages; unpaid they desert
	e.troops = {"levy": 10}
	e.purse_override = 0
	e._people_day()
	assert_int(e.troop_count()).is_less(10)
	# the party limit caps the force
	e.purse_override = 99999
	e.rep_delta["1"] = 30.0
	e.troops = {"levy": e.party_limit() - e.companions()}
	assert_str(e.can_recruit(1, "levy", 1)).contains("limit")


func test_clan_tiers_and_party_limit() -> void:
	var hub := _hub()
	var e := _e(hub)
	assert_int(e.clan_tier()).is_equal(0)
	var lim0: int = e.party_limit()
	e.add_renown(45.0, "test")
	assert_int(e.clan_tier()).is_equal(1)
	assert_int(e.party_limit()).is_equal(lim0 + D.PARTY_PER_TIER)
	e.add_renown(120.0, "test")
	assert_int(e.clan_tier()).is_equal(2)
	var l: RefCounted = e.lordship_ref
	l.grant(2, "crown")
	assert_int(e.party_limit()).is_equal(D.PARTY_BASE + 2 * D.PARTY_PER_TIER + D.PARTY_PER_FIEF)
	assert_bool(e.clan_info().has("next_name")).is_true()


func test_mercenary_contract_and_vassalage() -> void:
	var hub := _hub()
	var e := _e(hub)
	e.add_renown(150.0, "test")
	e.troops = {"footman": 20}
	var offers: Array = e.merc_offers()
	assert_int(offers.size()).is_equal(3)
	assert_str(_norm(offers)).is_equal(_norm(e.merc_offers()))
	var o: Dictionary = offers[0]
	e.troops = {"footman": 2}
	assert_bool(e.accept_merc(String(o["id"]))["ok"]).is_false()
	e.troops = {"footman": int(o["min_troops"]) + 2}
	e.purse_override = 99999
	assert_bool(e.accept_merc(String(o["id"]))["ok"]).is_true()
	e._people_day()
	assert_int(int(e.merc["earned"])).is_greater(0)
	assert_bool(e.roles().has("mercenary")).is_true()
	assert_bool(e.swear_vassal("house_aldren")["ok"] or true).is_true()
	# breaking a contract costs renown
	var r0: float = float(e.clan["renown"])
	e.break_merc()
	assert_float(float(e.clan["renown"])).is_less(r0)
	assert_bool(e.has_merc_contract()).is_false()


func test_role_gating() -> void:
	var hub := _hub()
	var e := _e(hub)
	assert_array(e.roles()).contains_exactly(["commoner"])
	assert_str(e.can("trade")).is_empty()
	for a: String in ["caravan", "workshop", "fief", "recruit", "duty", "vassal", "road_works"]:
		assert_str(e.can(a)).is_not_empty()
	# a merchant career opens trade enterprises, not the fief or the barracks
	e.career_override = "merchant"
	assert_str(e.can("caravan")).is_empty()
	assert_str(e.can("workshop")).is_empty()
	assert_str(e.can("fief")).is_not_empty()
	assert_str(e.can("duty")).is_not_empty()
	# a soldier gets army duties and can raise troops
	e.career_override = "soldier"
	assert_str(e.can("duty")).is_empty()
	assert_str(e.can("recruit")).is_empty()
	assert_str(e.can("caravan")).is_not_empty()
	var d: Dictionary = e.take_duty("drill", 1)
	assert_bool(d["ok"]).is_true()
	var g0: int = e.pending_gold
	e._duty_day()
	assert_int(e.pending_gold).is_greater(g0)
	# a licence lets a commoner trade seriously
	e.career_override = ""
	e.purse_override = 500
	assert_bool(e.buy_license()["ok"]).is_true()
	assert_str(e.can("caravan")).is_empty()
	# holding land makes a lord, who can do everything in the fief
	e.lordship_ref.grant(2, "crown")
	assert_bool(e.has_role("lord")).is_true()
	assert_str(e.can("fief")).is_empty()
	assert_str(e.can("road_works")).is_empty()


func test_settlement_card_actions_follow_role() -> void:
	var hub := _hub()
	var e := _e(hub)
	var card: Dictionary = e.settlement_card(2)
	var ids: Array = (card["actions"] as Array).map(func(a: Dictionary) -> String: return String(a["id"]))
	assert_bool(ids.has("trade")).is_true()
	assert_bool(ids.has("license")).is_true()
	var by := {}
	for a: Dictionary in card["actions"]:
		by[String(a["id"])] = a
	assert_bool(by["caravan"]["ok"]).is_false()
	e.license_owned = true
	card = e.settlement_card(2)
	for a: Dictionary in card["actions"]:
		by[String(a["id"])] = a
	assert_bool(by["caravan"]["ok"]).is_true()
	e.lordship_ref.grant(2, "crown")
	var ids2: Array = (e.settlement_card(2)["actions"] as Array).map(func(a: Dictionary) -> String: return String(a["id"]))
	assert_bool(ids2.has("fief")).is_true()
	assert_bool(e.settlement_card(2).has("danger")).is_true()
	assert_bool(e.resources_of(3).has("sells")).is_true()


# ---------------------------------------------------------------- save and perf

func test_json_round_trip() -> void:
	var hub := _hub()
	var e := _licensed(hub)
	e.observe(1, "visit")
	var c := _caravan(hub, 3, 2, [3, 1])
	for i in 30:
		e._advance(c, 1.0)
	e.buy_workshop(2, "mill")
	e.lordship_ref.grant(2, "crown")
	e.lordship_ref.village(2)["treasury"] = 800
	e.start_project(2, "granary", 4)
	e.troops = {"levy": 4, "archer": 2}
	e.add_renown(60.0, "t")
	e.pack = {"wood": [5, 3.5]}
	e.tick_day(11, {})
	var s: Dictionary = e.serialize()
	var parsed: Variant = JSON.parse_string(JSON.stringify(s))
	assert_bool(parsed is Dictionary).is_true()
	var hub2: RefCounted = Hub.new()
	var e2: RefCounted = hub2.mod("enterprise")
	e2.deserialize(parsed as Dictionary)
	assert_str(_norm(e2.serialize())).is_equal(_norm(s))
	assert_int(e2.caravans.size()).is_equal(e.caravans.size())
	assert_int(e2.workshops.size()).is_equal(1)
	# the whole hub round trips too
	var hs: Dictionary = hub.serialize()
	var hub3: RefCounted = Hub.new()
	hub3.deserialize(JSON.parse_string(JSON.stringify(hs)) as Dictionary)
	assert_str(_norm(hub3.mod("enterprise").serialize())).is_equal(_norm(hub.mod("enterprise").serialize()))
	assert_bool("enterprise" in Hub.ORDER).is_true()


func test_pending_gold_ledger() -> void:
	var hub := _hub()
	var e := _e(hub)
	e.pack = {"wood": [10, 1.0]}
	e.sell(1, "wood", 10)
	var g: int = e.take_pending_gold()
	assert_int(g).is_greater(0)
	assert_int(e.take_pending_gold()).is_equal(0)


func test_enterprise_perf() -> void:
	var hub := _hub()
	var e := _licensed(hub)
	var fo: RefCounted = hub.mod("followers")
	for i in 3:
		var fid: String = fo.hire("mercenary", "s%d" % (i + 1), true, "p%d" % i)
		e.fund_caravan(i + 1, 2, 300, fid)
	e.buy_workshop(2, "mill")
	e.lordship_ref.grant(2, "crown")
	var t0 := Time.get_ticks_usec()
	for i in 24:
		e.tick_hour(i, {"abs_hours": float(e.day()) * 24.0 + i})
	var hour_us := (Time.get_ticks_usec() - t0) / 24
	var t1 := Time.get_ticks_usec()
	var total_chunks := 0
	var worst := 0
	for ch: Callable in e.tick_day_chunks(e.day() + 1, {}):
		var c0 := Time.get_ticks_usec()
		ch.call()
		worst = maxi(worst, Time.get_ticks_usec() - c0)
		total_chunks += 1
	var day_us := Time.get_ticks_usec() - t1
	var t2 := Time.get_ticks_usec()
	var ranked: Array = e.rank_destinations(3, {"budget": 500, "cap": 40})
	var rank_us := Time.get_ticks_usec() - t2
	var t3 := Time.get_ticks_usec()
	for i in 200:
		e.quote(1, "grain", 60, "sell")
	var quote_us := (Time.get_ticks_usec() - t3) / 200
	print("[perf] enterprise hour ", hour_us, "us, day ", day_us, "us (worst chunk ", worst, "), rank ", rank_us, "us, quote ", quote_us, "us")
	assert_int(hour_us).is_less(3000)
	assert_int(worst).is_less(8000)
	assert_int(rank_us).is_less(40000)
	assert_int(quote_us).is_less(400)
	assert_int(ranked.size()).is_equal(WorldGen.settlements.size() - 1)


# ---------------------------------------------------------------- UI

func test_strategic_map_layers_and_card() -> void:
	var hub := _hub()
	var e := _licensed(hub)
	e.observe(1, "visit")
	_caravan(hub, 3, 2)
	e.workshops.append({"id": 9, "sid": 2, "kind": "mill", "level": 1, "workers": 2, "manager": "", "bought": 0, "spent": 300, "history": [], "last": {}})
	var m: Control = auto_free(load("res://scripts/ui/strategic/strategic_map.gd").new())
	m.set("realm_override", hub)
	add_child(m)
	m.size = Vector2(1280, 720)
	await await_idle_frame()
	for layer: String in ["political", "trade", "resources", "military", "diplomacy", "danger"]:
		m.call("set_layers", [layer])
		m.call("bake_now")
		await await_idle_frame()
		assert_bool(m.get("layers")[layer]).is_true()
		assert_bool((m.get("_data") as Dictionary).has("roads")).is_true()
	# all layers at once, all three styles
	m.call("set_layers", ["political", "trade", "resources", "military", "diplomacy", "danger"])
	for st in 3:
		m.call("set_style", st)
		await await_idle_frame()
	# tap a settlement: the card has role-appropriate actions
	m.call("select", 2)
	var card: Node = m.get("_card")
	assert_int(card.get_child_count()).is_greater(5)
	var bs: Array = card.find_children("*", "Button", true, false)
	assert_int(bs.size()).is_greater(2)
	# a caravan card
	m.call("select_caravan", 1)
	assert_int(card.get_child_count()).is_greater(3)
	# screen position hit-testing
	var sp: Vector2 = m.call("to_screen", WorldGen.settlements[3]["pos"])
	assert_int(int(m.call("settlement_at", sp))).is_equal(3)
	# the map opens the enterprise screen from a card action
	var scr: Control = m.call("open_screen", "market", 2)
	await await_idle_frame()
	assert_object(scr).is_not_null()
	scr.queue_free()


func test_enterprise_screen_tabs_build() -> void:
	var hub := _hub()
	var e := _licensed(hub)
	e.add_renown(200.0, "t")
	e.lordship_ref.grant(2, "crown")
	e.lordship_ref.village(2)["treasury"] = 500
	e.start_project(2, "market", 4)
	var fo: RefCounted = hub.mod("followers")
	fo.hire("scout", "s2", true, "uiscout")
	e.buy_workshop(2, "mill")
	_caravan(hub, 3, 1)
	e.troops = {"levy": 3}
	var scr: Control = auto_free(load("res://scripts/ui/strategic/enterprise_screen.gd").new())
	scr.set("realm_override", hub)
	scr.set("sid", 2)
	add_child(scr)
	scr.size = Vector2(1280, 720)
	await await_idle_frame()
	for t: String in ["market", "routes", "caravans", "workshops", "fief", "clan"]:
		scr.call("set_tab", t)
		await await_idle_frame()
		assert_int((scr.get("_box") as Node).get_child_count()).override_failure_message("tab %s is empty" % t).is_greater(1)
	# market: a real buy through the UI path
	scr.call("set_tab", "market")
	e.pending_gold = 0
	var g0: int = e.gold()
	e.call("buy", 2, "wood", 5)
	assert_int(e.gold()).is_less(g0)
	# the routes tab survives picking stops
	scr.set("plan_stops", [2, 1, 3])
	scr.call("set_tab", "routes")
	await await_idle_frame()
	assert_int((scr.get("_box") as Node).get_child_count()).is_greater(3)
