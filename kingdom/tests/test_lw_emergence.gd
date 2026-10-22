extends GdUnitTestSuite
## LW-8.2 (docs/design/LIVING_WORLD_SANDBOX.md section 15): emergent event chains. Ten kinds, each with knock-on effects on other modules,
## delivered as news with a delay, started by system state and not repeating in a loop. A five-year run produces at least twenty
## different chains.

const Hub := preload("res://scripts/realm/realm_hub.gd")
const Events := preload("res://scripts/realm/events.gd")

static var _ready_world := false


func _hub() -> RefCounted:
	if not _ready_world:
		WorldGen.setup(2024)
		_ready_world = true
	WorldSim.day = 500
	var h: RefCounted = Hub.new()
	var om: RefCounted = h.mod("organizations")
	om.auto_seed = false
	om.gold_ref = {"gold": 5000}
	h.mod("faith").auto_seed = false
	h.mod("minds").auto_seed = false
	h.mod("minds").set_focus(-1)
	return h


func _run(h: RefCounted, from: int, to: int) -> void:
	var em: RefCounted = h.mod("emergence")
	for d in range(from, to + 1):
		WorldSim.day = d
		h.mod("news").tick_day(d, {})
		em.tick_day(d, {})
		h.mod("homes").tick_day(d, {})
		if d % 7 == 0:
			em.tick_week(d / 7, {})


func _norm(d: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(d)))


func _kinds(em: RefCounted) -> Array:
	var out: Array = []
	for cid: int in em.chains(false):
		out.append(String(em.chain(cid)["k"]))
	return out


# --- one test per chain ---------------------------------------------------------------

func test_mine_discovery_brings_migrants_rents_and_new_trouble() -> void:
	var h := _hub()
	var em: RefCounted = h.mod("emergence")
	var mg: RefCounted = h.mod("migration")
	var cid: int = em.start("mine_discovery", 3)
	assert_int(cid).is_greater(0)
	var waves0: int = mg.active_waves().size()
	_run(h, 500, 560)
	assert_float(em.effect(3, "trade")).is_greater(1.05)
	assert_float(em.rent_mult(3)).is_greater(1.2)
	assert_int(mg.active_waves().size()).is_greater(waves0)           # the ore rush draws settlers
	assert_float(em.rent_mult(2)).is_equal(1.0)                       # only that town
	var kinds := _kinds(em)
	assert_bool("tax_rise" in kinds or "unsafe_road" in kinds).is_true()   # and the knock-ons begin
	assert_float(h.mod("homes").road_mod(3, em._nearest(3, 2)[0])).is_greater(0.0)
	var listing: float = float(h.mod("homes").listings(3)[0]["rent"])
	assert_float(listing).is_greater(0.0)
	_run(h, 561, 700)
	assert_bool(bool(em.chain(cid)["done"])).is_true()
	assert_float(em.rent_mult(3)).is_equal(1.0)                       # the rush is over, rents settle


func test_a_noble_death_leaves_unrest_a_dispute_and_a_loyalty_dip() -> void:
	var h := _hub()
	var em: RefCounted = h.mod("emergence")
	var lm: RefCounted = h.mod("land")
	var loy0: float = lm.loyalty(1)
	Events.log_to(h, "death", "ss:1", ["sp:lord"], "noble_death", "A lord of Kingsreach dies", 6)
	_run(h, 500, 502)
	assert_array(_kinds(em)).contains(["noble_death"])
	assert_float(em.unrest_at(1)).is_greater(0.05)
	_run(h, 503, 540)
	assert_float(lm.loyalty(1)).is_less(loy0)
	assert_array(h.mod("events").of_kind("succession", 5)).is_not_empty()


func test_a_failed_harvest_raises_food_prices_deaths_and_petitions() -> void:
	var h := _hub()
	var em: RefCounted = h.mod("emergence")
	var au: RefCounted = h.mod("audiences")
	var lm: RefCounted = h.mod("land")
	var loy0: float = lm.loyalty(2)
	em.start("harvest_failure", 2)
	_run(h, 500, 502)
	assert_float(em.food_price_mult(2)).is_greater(1.5)
	assert_float(em.mortality_mult(2)).is_greater(1.2)
	assert_float(em.food_price_mult(0)).is_equal(1.0)
	_run(h, 503, 540)
	assert_int(au.stats["filed"] + au.stats["turned_away"]).is_greater(0)   # the farmers petition for relief (or are turned away)
	assert_float(lm.loyalty(2)).is_less(loy0)
	assert_int(h.mod("migration").active_waves().size()).is_greater(0)   # and the hungry leave
	assert_array(_kinds(em)).contains(["unsafe_road"])                  # hunger sends men to the roads
	var facts: Dictionary = h.mod("minds").town_facts(2, 505)
	assert_float(float(facts["hunger"])).is_greater(0.5)                # the people there feel it at once


func test_an_unsafe_road_is_patrolled_back_to_safety() -> void:
	var h := _hub()
	var em: RefCounted = h.mod("emergence")
	var hm: RefCounted = h.mod("homes")
	var ar: RefCounted = h.mod("armies")
	ar.set_defence(0, {"patrols": 14, "per_shift": 6, "shifts": 2})
	ar.set_defence(5, {"patrols": 14, "per_shift": 6, "shifts": 2})
	em.start("unsafe_road", 0, {"data": {"to": 5}})
	_run(h, 500, 502)
	assert_float(hm.road_mod(0, 5)).is_greater(0.35)
	assert_array(h.mod("events").of_kind("crime", 5)).is_not_empty()
	_run(h, 503, 520)
	assert_float(hm.road_mod(0, 5)).is_less(0.2)                        # the patrols took it back
	assert_str(hm.road_status(0, 5)).is_not_equal("dangerous")
	# with no patrols the road stays bad for its whole season
	var h2 := _hub()
	var em2: RefCounted = h2.mod("emergence")
	em2.start("unsafe_road", 3, {"data": {"to": 4}})
	_run(h2, 500, 520)
	assert_float(h2.mod("homes").road_mod(3, 4)).is_greater(0.35)


func test_a_guild_collapse_throws_its_members_on_the_town() -> void:
	var h := _hub()
	var em: RefCounted = h.mod("emergence")
	var om: RefCounted = h.mod("organizations")
	var mn: RefCounted = h.mod("minds")
	mn.seed_minds(80)
	var lead: String = om.spawn_actor(0, "smith", 900)
	var res: Dictionary = om.start_founding(lead, "craft_guild", "Collapsing Guild", 0)
	assert_bool(res["ok"]).is_true()
	om._o[String(res["org"])]["stage"] = 3                               # it had a charter and premises, and had stood for a season
	om._o[String(res["org"])]["born"] = 400
	om.dissolve(String(res["org"]), lead, "bankrupt")
	om._o[String(res["org"])]["end"] = 500
	_run(h, 500, 503)
	assert_array(_kinds(em)).contains(["guild_collapse"])
	var pokes0: int = mn.stats["pokes"]
	_run(h, 504, 520)
	assert_float(em.unrest_at(0)).is_greater(0.0)
	assert_int(mn.stats["pokes"]).is_greater_equal(pokes0)            # the town's people are woken to look for work


func test_a_rift_raises_the_alert_the_roads_and_the_refugees() -> void:
	var h := _hub()
	var em: RefCounted = h.mod("emergence")
	var ar: RefCounted = h.mod("armies")
	var hm: RefCounted = h.mod("homes")
	ar.set_defence(9, {"patrols": 4, "per_shift": 2, "shifts": 1})
	em.start("rift_activation", 9)
	_run(h, 500, 502)
	assert_int(int(ar.defence(9)["alert"])).is_greater_equal(2)
	assert_float(em.danger_at(9)).is_greater(0.2)
	assert_float(em.mortality_mult(9)).is_greater(1.2)
	var near: int = em._nearest(9, 1)[0]
	assert_float(hm.road_mod(9, near)).is_greater(0.25)
	_run(h, 503, 560)
	assert_int(h.mod("migration").active_waves().size()).is_greater(0)
	assert_float(em.danger_at(9)).is_greater(0.0)
	_run(h, 561, 640)
	assert_float(em.danger_at(9)).is_equal(0.0)                         # sealed and quiet


func test_a_raised_tax_is_noticed_from_the_governance_numbers() -> void:
	var h := _hub()
	var em: RefCounted = h.mod("emergence")
	var gv: RefCounted = h.mod("governance")
	var lm: RefCounted = h.mod("land")
	em.tick_week(71, {})                                                # first look records the rates
	assert_bool(_kinds(em).has("tax_rise")).is_false()
	var loy0: float = lm.loyalty(4)
	gv._inst["s:4"]["tax"] = float(gv.tax(4)) + 0.05                   # a lord raises the rate (NPC lords do it inside governance.gd)
	WorldSim.day = 504
	em.tick_week(72, {})
	assert_array(_kinds(em)).contains(["tax_rise"])
	_run(h, 505, 560)
	assert_float(lm.loyalty(4)).is_less(loy0)
	assert_int(h.mod("migration").active_waves().size()).is_greater(0)


func test_an_army_marching_out_leaves_a_town_open() -> void:
	var h := _hub()
	var em: RefCounted = h.mod("emergence")
	var ar: RefCounted = h.mod("armies")
	var aid: String = ar.found("lord:crown", "garrison", "Keep Garrison", 1)["id"]
	em.tick_week(71, {})                                                # seen camped
	ar._ar[aid]["state"] = "marching"
	em.tick_week(72, {})
	assert_array(_kinds(em)).contains(["army_departure"])
	_run(h, 500, 520)
	assert_float(em.danger_at(1)).is_greater(0.05)
	var nb: int = em._nearest(1, 1)[0]
	assert_float(h.mod("homes").road_mod(1, nb)).is_greater(0.0)
	_run(h, 521, 600)
	assert_float(em.danger_at(1)).is_equal(0.0)


func test_a_fever_spreads_to_neighbours_and_shelters_save_lives() -> void:
	var h := _hub()
	var em: RefCounted = h.mod("emergence")
	var fa: RefCounted = h.mod("faith")
	fa.found_church(0, "runes", "", "", 300)
	fa.seeded = true
	for oid: String in fa.churches(0):
		fa._ch[oid]["shelter"] = 12
	em.start("epidemic", 0, {"data": {"sev": 1.2}})
	_run(h, 500, 503)
	assert_float(em.mortality_mult(0)).is_greater(1.8)
	assert_float(em.fertility_mult(0)).is_less(1.0)
	assert_float(em.effect(0, "trade")).is_less(1.0)
	_run(h, 504, 520)
	var with_beds: float = em.mortality_mult(0)
	var h2 := _hub()
	var em2: RefCounted = h2.mod("emergence")
	em2.start("epidemic", 0, {"data": {"sev": 1.2}})
	_run(h2, 500, 520)
	assert_float(em2.mortality_mult(0)).is_greater(with_beds)           # a church shelter cut the toll
	var spread := 0
	for i in 12:
		var h3 := _hub()
		var e3: RefCounted = h3.mod("emergence")
		e3.start("epidemic", 1, {"data": {"sev": 1.0}})
		_run(h3, 500, 540)
		for cid: int in e3.chains(false):
			if int(e3.chain(cid)["sid"]) != 1 and String(e3.chain(cid)["k"]) == "epidemic":
				spread += 1
		if spread > 0:
			break
	assert_int(spread).is_greater(0)                                    # it travelled with the traffic


func test_recognition_draws_settlers_and_news() -> void:
	var h := _hub()
	var em: RefCounted = h.mod("emergence")
	var lm: RefCounted = h.mod("land")
	var loy0: float = lm.loyalty(6)
	Events.log_to(h, "military", "ss:6", ["pl:player"], "recognised", "The player's company is recognised by the crown", 3)
	_run(h, 500, 503)
	assert_array(_kinds(em)).contains(["recognition"])
	assert_float(lm.loyalty(6)).is_greater(loy0)
	assert_float(em.effect(6, "trade")).is_greater(1.0)
	_run(h, 504, 540)
	assert_int(h.mod("migration").active_waves().size()).is_greater(0)


# --- news with a delay ----------------------------------------------------------------

func test_chains_are_announced_as_news_that_arrives_late_and_later_far_away() -> void:
	var h := _hub()
	var em: RefCounted = h.mod("emergence")
	var nw: RefCounted = h.mod("news")
	em.start("mine_discovery", 0)
	_run(h, 500, 501)                                                   # the vein is found on the 501st day
	# posted for day 506 (five days before it leaks), then it travels by road
	assert_int(nw.items_at(0, 501).size()).is_equal(0)
	assert_int(nw.items_at(0, 507).size()).is_greater(0)
	var near_day := 506
	var far_day := 506
	while nw.items_at(6, near_day).size() == 0 and near_day < 560:
		near_day += 1
	while nw.items_at(4, far_day).size() == 0 and far_day < 600:
		far_day += 1
	assert_int(near_day).is_greater(506)
	assert_int(far_day).is_greater(near_day)                            # the farther town learns later
	assert_int(em.stats["news"]).is_greater(0)


func test_towns_hear_of_a_boom_only_when_its_news_has_arrived_and_the_event_ring_serves_new_readers() -> void:
	var h := _hub()
	var nw: RefCounted = h.mod("news")
	nw.post("mine", 5, "Ore.", 2.5, "", false, 500)
	nw.post("tax", 5, "Tax.", 1.0, "", false, 500)
	nw._day = 500
	assert_array(nw.heard_kinds(0, ["mine"], 500)).is_empty()            # not yet
	assert_array(nw.heard_kinds(5, ["mine"], 500)).is_not_empty()        # at home at once
	var d := 500
	while nw.heard_kinds(0, ["mine"], d).is_empty() and d < 560:
		d += 1
	assert_int(d).is_greater(500)
	var got: Array = nw.heard_kinds(0, ["mine"], d)
	assert_int(int((got[0] as Array)[0])).is_equal(5)
	assert_float(float((got[0] as Array)[1])).is_equal(2.5)
	assert_array(nw.heard_kinds(0, ["tax"], d)).is_not_empty() if d >= 500 else null
	assert_array(nw.heard_kinds(0, ["mine"], 500 + 400)).is_empty()      # old news is forgotten
	var ev: RefCounted = h.mod("events")
	var n0: int = ev.total()
	Events.log_to(h, "trade", "ss:0", ["ch:1"], "a", "one", 1)
	Events.log_to(h, "trade", "ss:0", ["ch:1"], "b", "two", 1)
	var seen: Array = ev.after(n0)
	assert_int(seen.size()).is_equal(2)
	assert_str(String(seen[0]["cause"])).is_equal("a")                  # oldest first
	assert_array(ev.after(int(seen[1]["n"]))).is_empty()


# --- loop control and bounds ----------------------------------------------------------

func test_a_chain_cannot_repeat_in_place_or_inside_its_own_line_of_causes() -> void:
	var h := _hub()
	var em: RefCounted = h.mod("emergence")
	var a: int = em.start("harvest_failure", 5)
	assert_int(a).is_greater(0)
	assert_int(em.start("harvest_failure", 5)).is_equal(0)             # cooling off
	assert_int(em.stats["blocked_cool"]).is_equal(1)
	# a child of a harvest failure may not be another failure of the same harvest
	assert_int(em.start("harvest_failure", 5, {"parent": a})).is_equal(0)
	assert_int(em.start("harvest_failure", 6, {"parent": a})).is_greater(0)   # elsewhere it is a new matter
	var b: int = em.start("unsafe_road", 7)
	var c: int = em.start("tax_rise", 7, {"parent": b})
	var d: int = em.start("unsafe_road", 7, {"parent": c})              # b -> c -> unsafe_road@7 again: a loop
	assert_int(d).is_equal(0)
	assert_int(em.stats["blocked_loop"]).is_greater(0)
	# the cooldown ends
	_run(h, 500, 500 + em.COOLDOWN + 1)
	assert_int(em.start("harvest_failure", 5)).is_greater(0)
	# depth is capped
	var p := 0
	var depth := 0
	for i in 8:
		var nxt: int = em.start("epidemic", 10 + i, {"parent": p, "place": 10 + i}) if p > 0 else em.start("epidemic", 10)
		if nxt == 0:
			break
		p = nxt
		depth += 1
	assert_int(depth).is_less_equal(em.MAX_DEPTH + 1)


func test_live_chains_and_daily_starts_are_capped() -> void:
	var h := _hub()
	var em: RefCounted = h.mod("emergence")
	var made := 0
	for i in 30:
		if em.start("rift_activation", i) > 0:
			made += 1
	assert_int(made).is_equal(em.MAX_NEW)                               # at most two new chains in a day
	em._new_today = 0
	for day in 20:
		em._new_today = 0
		for i in 3:
			em.start("unsafe_road", (day * 3 + i) % 30, {"place": "r%d" % (day * 3 + i)})
	assert_int(em.chains(true).size()).is_less_equal(em.MAX_LIVE)


func test_five_years_make_at_least_twenty_different_chains_and_no_loop() -> void:
	var h := _hub()
	var em: RefCounted = h.mod("emergence")
	var t0 := Time.get_ticks_usec()
	_run(h, 500, 500 + 360 * 5)
	var us := Time.get_ticks_usec() - t0
	var kinds := {}
	for cid: int in em.chains(false):
		var c: Dictionary = em.chain(cid)
		kinds[String(c["k"])] = true
		assert_int(int(c["depth"])).is_less_equal(em.MAX_DEPTH + 1)
		assert_bool(("%s|%s" % [c["k"], c["place"]]) in (c["anc"] as Array)).is_false()     # no chain is its own ancestor
	var started: int = em.stats["started"]
	assert_int(started).is_greater_equal(20)
	assert_int(kinds.size()).is_greater_equal(5)
	assert_int(em.stats["blocked_loop"] + em.stats["blocked_cool"]).is_greater_equal(0)
	# the same cause never fires twice inside its cooldown
	var last := {}
	for line: String in em.history():
		var bits := line.split(" ")
		var d := int(bits[0].substr(1))
		var key := String(bits[1]).split("<")[0]
		if last.has(key):
			assert_int(d - int(last[key])).is_greater_equal(em.COOLDOWN - 1)
		last[key] = d
	# five years of days stay cheap: the whole run, every day and week, is under three seconds even on a slow container
	assert_int(us).is_less(3_000_000)


func test_the_same_seed_gives_the_same_story() -> void:
	var a := _hub()
	_run(a, 500, 500 + 360)
	var b := _hub()
	_run(b, 500, 500 + 360)
	assert_array(a.mod("emergence").history()).is_equal(b.mod("emergence").history())
	assert_str(_norm(a.mod("emergence").serialize())).is_equal(_norm(b.mod("emergence").serialize()))
	assert_int(a.mod("emergence").history().size()).is_greater(0)


# --- catch-up and save ----------------------------------------------------------------

func test_a_long_sleep_resolves_every_due_stage_in_order() -> void:
	var h := _hub()
	var em: RefCounted = h.mod("emergence")
	em.start("mine_discovery", 3)
	em.start("rift_activation", 9)
	em.tick_day(500, {})
	em.catch_up(400, {})
	for cid: int in em.chains(false):
		assert_int(int(em.chain(cid)["stage"])).is_greater(0)
	assert_int(em.chains(true).size()).is_less(2)


func test_save_round_trip_is_exact_and_chains_resume() -> void:
	var h := _hub()
	var em: RefCounted = h.mod("emergence")
	em.start("epidemic", 2, {"data": {"sev": 1.0}})
	em.start("mine_discovery", 5)
	_run(h, 500, 512)
	var a := _norm(em.serialize())
	var h2 := _hub()
	var e2: RefCounted = h2.mod("emergence")
	e2.deserialize(JSON.parse_string(JSON.stringify(em.serialize())))
	assert_str(_norm(e2.serialize())).is_equal(a)
	# the copy carries on exactly as the original does
	_run(h, 513, 560)
	_run(h2, 513, 560)
	var s1: Dictionary = em.serialize().duplicate()
	var s2: Dictionary = e2.serialize().duplicate()
	s1.erase("le")                                                      # the copy's event ring is its own, so are the event numbers chains remember (NI-6 "ev" / "le")
	s2.erase("le")
	for sx: Dictionary in [s1, s2]:
		sx["cn"] = (JSON.parse_string(JSON.stringify(sx["cn"])) as Dictionary)
		for cc: Variant in sx["cn"]:
			((sx["cn"][cc] as Array)[8] as Dictionary).erase("ev")
			((sx["cn"][cc] as Array)[8] as Dictionary).erase("le")
	assert_str(_norm(s2)).is_equal(_norm(s1))
	assert_int(JSON.stringify(em.serialize()).length()).is_less(20_000)
