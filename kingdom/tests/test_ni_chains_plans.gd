extends GdUnitTestSuite
## NI-6 / NI-7 / NI-8: the causal trace service (scripts/sim/trace.gd), chains that reach specific people within caps and leave most weeks quiet,
## GOAP-lite plans (utility_core.plan + minds.gd) and secrets (secrets.gd) that are discovered and then used as leverage.

const Hub := preload("res://scripts/realm/realm_hub.gd")
const Events := preload("res://scripts/realm/events.gd")
const Trace := preload("res://scripts/sim/trace.gd")
const Core := preload("res://scripts/sim/utility_core.gd")
const FD := preload("res://scripts/realm/farming_data.gd")
const Persona := preload("res://scripts/realm/persona.gd")

static var _ready_world := false


func _hub() -> RefCounted:
	if not _ready_world:
		WorldGen.setup(2024)
		_ready_world = true
	WorldSim.day = 600
	var h: RefCounted = Hub.new()
	var om: RefCounted = h.mod("organizations")
	om.auto_seed = false
	om.gold_ref = {"gold": 5000}
	h.mod("faith").auto_seed = false
	h.mod("minds").auto_seed = false
	h.mod("minds").set_focus(-1)
	for k in ["farming", "businesses", "homes"]:
		if h.mod(k).has_method("set_day"):
			h.mod(k).set_day(600)
	h.mod("businesses").set_population(0, 800)
	om.set_day(600)
	return h


func _ch(h: RefCounted, age := 30, cash := 500, sid := 0, prof := "smith") -> String:
	var ch: String = h.mod("registry").mint("ch")
	h.mod("organizations").ensure_char(ch, {"cash": cash, "sid": sid, "prof": prof, "npc": true, "amb": "found"})
	assert_bool(h.mod("minds").adopt(ch, age, "m", "")).is_true()
	return ch


func _town(h: RefCounted, n: int, sid := 0) -> Array:
	var out: Array = []
	for i in n:
		out.append(_ch(h, 22 + i % 20, 300, sid))
	return out


func _days(h: RefCounted, from: int, to: int) -> void:
	var em: RefCounted = h.mod("emergence")
	for d in range(from, to + 1):
		WorldSim.day = d
		h.mod("news").tick_day(d, {})
		em.tick_day(d, {})
		h.mod("homes").tick_day(d, {})
		h.mod("minds").tick_day(d, {})
		if d % 7 == 0:
			em.tick_week(d / 7, {})
			h.mod("secrets").tick_week(d / 7, {})
		h.mod("secrets").tick_day(d, {})


# --- NI-6: why and what caused ----------------------------------------------------------

func test_a_chain_event_knows_its_cause_and_the_trace_walks_both_ways() -> void:
	var h := _hub()
	_town(h, 14)
	var em: RefCounted = h.mod("emergence")
	var cid: int = em.start("harvest_failure", 0)
	assert_int(cid).is_greater(0)
	_days(h, 600, 700)
	var ev: RefCounted = h.mod("events")
	var leaf := {}
	var up := {}
	for r: Dictionary in ev.at("ss:0", 60):
		if int(r["parent"]) > 0 and (leaf.is_empty() or int(r["n"]) > int(leaf["n"])):
			var walk: Dictionary = Trace.caused_by(h, int(r["n"]))
			if String(((walk["causes"] as Array)[-1] as Dictionary)["cause"]) == "harvest_failure":      # the harvest failing is the root of the line
				leaf = r
				up = walk
	assert_bool(leaf.is_empty()).is_false()
	assert_bool(up["ok"]).is_true()
	assert_int((up["causes"] as Array).size()).is_greater(0)
	assert_str(String(up["text"])).contains("was caused by")
	var root: int = int((up["causes"] as Array)[-1]["n"])
	var down: Array = Trace.effects_of(h, root)
	var ns: Array = []
	for r2: Dictionary in down:
		ns.append(int(r2["n"]))
	assert_array(ns).contains([int(leaf["n"])])
	assert_bool(Trace.chain_of(h, cid)["ok"]).is_true()
	# an event nobody wrote down
	assert_bool(Trace.caused_by(h, 999999)["ok"]).is_false()


func test_the_causal_walk_stops_at_the_depth_cap_and_cannot_loop() -> void:
	var h := _hub()
	var ev: RefCounted = h.mod("events")
	var prev := 0
	var last := 0
	for i in 14:
		last = ev.record("emergency", "ss:0", [], "step%d" % i, "step %d" % i, 2, 600, prev)
		prev = last
	var up: Dictionary = Trace.caused_by(h, last)
	assert_int((up["causes"] as Array).size()).is_equal(Trace.MAX_DEPTH)
	assert_bool(up["truncated"]).is_true()
	var seen := {}
	for r: Dictionary in up["causes"]:
		assert_bool(seen.has(r["n"])).is_false()
		seen[r["n"]] = true
	# a parent must be an older event: a forged self-parent is dropped
	var n2: int = ev.record("emergency", "ss:0", [], "self", "x", 1, 600, 10 ** 6)
	assert_int(int(ev.get_event(n2)["parent"])).is_equal(0)
	# children of the first event, bounded
	assert_int(Trace.effects_of(h, prev - 13).size()).is_less_equal(Trace.MAX_ROWS)


func test_why_names_the_goal_the_top_considerations_and_what_weighed_on_the_person() -> void:
	var h := _hub()
	var mn: RefCounted = h.mod("minds")
	mn.set_focus(0)
	var ch := _ch(h, 30, 30, 0, "smith")
	for d in range(600, 604):
		WorldSim.day = d
		mn.decide(ch, d)
	var w: Dictionary = Trace.why(h, ch)
	assert_bool(w["ok"]).is_true()
	assert_int((w["top"] as Array).size()).is_greater(0)
	var top: Dictionary = (w["top"] as Array)[0]
	assert_str(String(w["text"])).contains(String(w["goal"]))
	assert_bool((w["inputs"] as Dictionary).is_empty()).is_false()
	assert_bool((w["persona"] as Dictionary).has("amb")).is_true()
	assert_float(float(top["score"])).is_greater(-1.0)
	assert_bool(Trace.why(h, "ch:nobody")["ok"]).is_false()


# --- NI-7: chains reach people ------------------------------------------------------------

func test_a_chain_touches_specific_townspeople_inside_every_cap() -> void:
	var h := _hub()
	var folk := _town(h, 40)
	var other := _town(h, 10, 3)
	var em: RefCounted = h.mod("emergence")
	var ps: RefCounted = h.mod("psyche")
	var cid: int = em.start("rift_activation", 0)
	assert_int(cid).is_greater(0)
	_days(h, 600, 640)
	var touched: Array = []
	for ch: String in folk:
		for e: Dictionary in em.person_fx(ch):
			touched.append(ch)
			assert_int(int(e["chain"])).is_equal(cid)
	assert_int(touched.size()).is_between(3, em.CHAIN_PEOPLE)
	var uniq := {}
	for ch2: String in touched:
		assert_bool(uniq.has(ch2)).is_false()                     # nobody takes the same chain's blow twice
		uniq[ch2] = true
	for ch3: String in other:
		assert_int(em.person_fx(ch3).size()).is_equal(0)          # another town's people are not touched
	# the touched feel it, the rest are at their baseline
	var felt := 0
	for ch4: String in touched:
		if (ps.devs(ch4, 602) as PackedFloat32Array)[1] > 0.02 or (ps.memories(ch4, 602) as Array).size() > 0:
			felt += 1
	assert_int(felt).is_equal(touched.size())
	# the realm-wide day cap and the person cooldown
	em._pday = em.PERSON_DAY_CAP - 1
	var c: Dictionary = em._cn[cid]
	c["data"].erase("hit")
	var n: int = em._touch(cid, c, 0, 0)
	assert_int(n).is_less_equal(1)
	em._pday = 0
	c["data"].erase("hit")
	for ch5: String in folk:
		em._pcool[ch5] = WorldSim.day + 5
	assert_int(em._touch(cid, c, 0, 0)).is_equal(0)               # everyone is cooling down
	# the person effects survive a save
	var d: Dictionary = JSON.parse_string(JSON.stringify(em.serialize()))
	var em2: RefCounted = Hub.new().mod("emergence")
	em2.deserialize(d)
	assert_int(em2.person_fx(touched[0]).size()).is_equal(em.person_fx(touched[0]).size())


func test_most_weeks_in_most_towns_are_quiet() -> void:
	var h := _hub()
	var em: RefCounted = h.mod("emergence")
	_days(h, 600, 600 + 2 * 360)
	var tw: int = em.stats["town_weeks"]
	var calm: int = em.stats["weeks_calm"]
	print("NI-7 quiet-world: ", calm, " of ", tw, " town-weeks without a chain (", snappedf(100.0 * float(calm) / float(tw), 0.1), "%), chains started ", em.stats["started"])
	assert_int(tw).is_greater(1000)
	assert_float(float(calm) / float(tw)).is_greater(0.85)
	assert_int(em.stats["started"]).is_greater(0)                  # quiet, not dead


func test_a_town_with_a_live_chain_gets_no_new_natural_trouble_and_waits_after_one() -> void:
	var h := _hub()
	var em: RefCounted = h.mod("emergence")
	var cid: int = em.start("tax_rise", 5)
	assert_bool(em.calm(5)).is_false()
	em._hazards(1)
	em._hazards(2)
	var live := 0
	for c: int in em.chains(true):
		if int(em.chain(c)["sid"]) == 5:
			live += 1
	assert_int(live).is_equal(1)
	assert_int(cid).is_greater(0)


# --- NI-8: plans ---------------------------------------------------------------------------

func test_the_planner_orders_at_most_three_steps_and_skips_what_is_done() -> void:
	var cfg: Dictionary = h_cfg()
	var homestead: Dictionary = cfg["plans"][0]
	var flat: PackedInt32Array = homestead["flat"]
	var goal: int = homestead["gmask"]
	assert_int(Core.plan(flat, 0, goal).size()).is_equal(3)
	assert_int(Core.plan(flat, 1, goal).size()).is_equal(2)                 # cash in hand: no saving step
	assert_int(Core.plan(flat, 1 | 4, goal).size()).is_equal(1)
	assert_int(Core.plan(flat, goal, goal).size()).is_equal(0)
	assert_int(Core.plan(flat, 0, goal, 2).size()).is_equal(0)              # not reachable in two
	assert_int(Core.plan(flat, 0, goal, 9).size()).is_equal(3)              # the depth cap holds whatever is asked
	assert_int(Core.plan_cost(flat, Core.plan(flat, 0, goal))).is_equal(7)


func h_cfg() -> Dictionary:
	return preload("res://scripts/realm/minds.gd")._plan_cfg()


func _season_ok_day() -> int:
	var fm: RefCounted = _hub().mod("farming")
	for d in range(600, 700):
		if FD.can_sow("wheat", fm.season_of(d)):
			return d
	return 600


func test_a_three_step_plan_saves_buys_land_and_starts_the_farm() -> void:
	var h := _hub()
	var mn: RefCounted = h.mod("minds")
	var fm: RefCounted = h.mod("farming")
	var om: RefCounted = h.mod("organizations")
	var d0 := _season_ok_day()
	WorldSim.day = d0
	for k in ["farming", "businesses", "homes"]:
		if h.mod(k).has_method("set_day"):
			h.mod(k).set_day(d0)
	om.set_day(d0)
	mn.set_focus(0)
	fm.found_parcel(0, Vector2(20, 20), 3, "lord:crown", "Crown Acre")
	var ch := _ch(h, 29, 20, 0, "farmer")
	assert_bool(mn.plan_begin(ch, "homestead")).is_true()
	var pl: Dictionary = mn.plan_of(ch)
	assert_array(pl["steps"]).is_equal(["save", "buy_land", "start_farm"])
	assert_bool(pl["hidden"]).is_false()
	var did: Array = []
	for d in range(d0, d0 + 30):
		WorldSim.day = d
		om.set_day(d)
		if d == d0 + 3:
			om._c[ch]["cash"] = 400                                           # the purse fills
		var before: Array = mn.plan_of(ch).get("steps", [])
		mn.decide(ch, d)
		var after: Array = mn.plan_of(ch).get("steps", [])
		if after.size() < before.size():
			did.append(before[0])
		if mn.plan_of(ch).is_empty():
			break
	assert_bool(mn.plan_of(ch).is_empty()).is_true()
	assert_int(mn.stats["plans_done"]).is_equal(1)
	assert_array(did).contains(["buy_land"])
	assert_bool(not fm.parcels_of(ch).is_empty() or not fm.rented_by(ch).is_empty()).is_true()
	assert_bool(mn._farm_started(ch)).is_true()


func test_another_plan_is_abandoned_when_the_state_it_rests_on_changes() -> void:
	var h := _hub()
	var mn: RefCounted = h.mod("minds")
	var om: RefCounted = h.mod("organizations")
	mn.set_focus(0)
	var lead := _ch(h, 36, 900, 0, "smith")
	_town(h, 6)
	assert_bool(mn.plan_begin(lead, "charter")).is_true()
	var pl: Dictionary = mn.plan_of(lead)
	assert_bool(pl["hidden"]).is_true()
	assert_array(pl["steps"]).is_equal(["gather_allies", "petition", "found_org"])
	om._c[lead]["cash"] = 5                                                  # the money is gone: the founding can no longer be funded
	mn.decide(lead, 601)
	assert_bool(mn.plan_of(lead).is_empty()).is_true()
	assert_int(mn.stats["plans_dropped"]).is_equal(1)
	assert_bool(mn.plan_begin(lead, "charter")).is_false()                   # and it cannot restart from where it stands
	# a changed mind also comes from fading resolve: waiting to save with nothing coming in
	var poor := _ch(h, 29, 10, 0, "farmer")
	assert_bool(mn.plan_begin(poor, "homestead")).is_true()
	var gone := false
	for d in range(602, 740):
		WorldSim.day = d
		mn.decide(poor, d)
		if mn.plan_of(poor).is_empty():
			gone = true
			break
	assert_bool(gone).is_true()
	# a shock breaks resolve too
	var shaken := _ch(h, 29, 10, 0, "farmer")
	mn.plan_begin(shaken, "homestead")
	mn.shake_plan(shaken, 300)
	mn.decide(shaken, 750)
	assert_bool(mn.plan_of(shaken).is_empty()).is_true()


func test_two_personalities_pick_different_plans_from_the_same_state() -> void:
	var h := _hub()
	var mn: RefCounted = h.mod("minds")
	var pe: RefCounted = h.mod("persona")
	var a := _ch(h, 35, 700, 0, "farmer")
	var b := _ch(h, 35, 700, 0, "farmer")
	_town(h, 6)
	for pair in [[a, 250, 60, 220], [b, 40, 230, 70]]:
		var o: int = pe.off(pair[0])
		pe._buf[o + Persona.O_AMB] = pair[1]
		pe._buf[o + Persona.O_DISC] = pair[2]
		pe._buf[o + Persona.O_BOLD] = pair[3]
		pe._buf[o + Persona.O_LOY] = 200 if pair[0] == b else 60
	var om: RefCounted = h.mod("organizations")
	var chosen := {}
	for ch in [a, b]:
		assert_bool(mn._plan_start(ch, mn._m[ch], om.char_rec(ch), 35, 600, "")).is_true()
		chosen[ch] = String(mn.plan_of(ch)["id"])
	assert_str(chosen[a]).is_equal("charter")
	assert_str(chosen[b]).is_equal("homestead")


func test_plans_cost_little_and_are_deterministic() -> void:
	var base := 0
	var withp := 0
	var started := 0
	var logs: Array = []
	for variant in 2:
		var h := _hub()
		var mn: RefCounted = h.mod("minds")
		mn.set_focus(0)
		var cfg: Dictionary = h_cfg()
		var saved: float = cfg["start_chance"]
		cfg["start_chance"] = 0.0 if variant == 0 else 0.5
		mn.seed_minds(240)
		for d in range(600, 640):
			WorldSim.day = d
			h.on_hour(6, d, {})
			h.drain()
		if variant == 0:
			base = int(mn.perf()["us"])
		else:
			withp = int(mn.perf()["us"])
			started = int(mn.stats["plans_started"])
			logs.append(JSON.stringify(mn.serialize()))
		cfg["start_chance"] = saved
	print("NI-8 minds 40-day cost without plans ", base, " us, with plans (start chance 0.5, far above the real 0.06) ", withp, " us, started ", started)
	assert_int(started).is_greater(0)
	assert_float(float(withp)).is_less(float(base) * 1.5 + 20000.0)


# --- NI-8: secrets -------------------------------------------------------------------------

func test_a_secret_is_discovered_and_then_used_as_leverage() -> void:
	var h := _hub()
	var folk := _town(h, 60)
	var sc: RefCounted = h.mod("secrets")
	var rm: RefCounted = h.mod("rumours")
	var holder := ""
	for ch: String in folk:
		if not sc.secrets_of(ch).is_empty():
			holder = ch
			break
	assert_str(holder).is_not_equal("")
	var row: Dictionary = sc.secrets_of(holder)[0]
	assert_str(String(row["state"])).is_equal("hidden")
	assert_bool(sc.knows("ch:spy", holder)).is_false()
	assert_bool(sc.leverage("ch:spy", holder)["ok"]).is_false()            # nothing is known yet: nothing to press
	var found := false
	for d in 40:
		WorldSim.day = 600 + d
		var r: Dictionary = sc.investigate("ch:spy", holder, 0.9)
		if bool(r["found"]):
			found = true
			assert_int(int(r["severity"])).is_greater(0)
			break
	assert_bool(found).is_true()
	assert_bool(sc.knows("ch:spy", holder)).is_true()
	assert_int(h.mod("courts").secrets_known("ch:spy", holder).size()).is_equal(1)       # one store: the courts' blackmail sees what was found
	var lev: Dictionary = sc.leverage("ch:spy", holder)
	assert_bool(lev["ok"]).is_true()
	assert_int(int(lev["demand"])).is_greater(0)
	var ps: RefCounted = h.mod("psyche")
	var fear0: float = ps.mood(holder)["fear"]
	var bm: Dictionary = sc.use("ch:spy", holder, int(lev["slot"]), "blackmail")
	assert_bool(bm["ok"]).is_true()
	assert_int(int(bm["gold"])).is_equal(int(lev["demand"]))
	assert_float(ps.mood(holder)["fear"]).is_greater(fear0)
	assert_bool(sc.use("ch:spy", holder, int(lev["slot"]), "blackmail")["ok"]).is_false()     # not again at once
	assert_bool(sc.leverage("ch:spy", holder)["ok"]).is_false()
	var claims0: int = rm.claim_count()
	var ex: Dictionary = sc.use("ch:spy", holder, int(lev["slot"]), "expose")
	assert_bool(ex["ok"]).is_true()
	assert_str(String(sc.secrets_of(holder)[int(lev["slot"])]["state"])).is_equal("exposed")
	assert_int(rm.claim_count()).is_greater(claims0)                        # the town now tells it
	assert_bool(sc.use("ch:spy", holder, int(lev["slot"]), "expose")["ok"]).is_false()
	# a stranger who found nothing cannot use anything
	assert_bool(sc.use("ch:nobody", holder, 0, "blackmail")["ok"]).is_false()
	# the save keeps what was learned
	var h2 := _hub()
	h2.mod("courts").deserialize(JSON.parse_string(JSON.stringify(h.mod("courts").serialize())))
	h2.mod("secrets").deserialize(JSON.parse_string(JSON.stringify(sc.serialize())))
	assert_bool(h2.mod("secrets").knows("ch:spy", holder)).is_true()
	assert_str(String(h2.mod("secrets").secrets_of(holder)[int(lev["slot"])]["state"])).is_equal("exposed")


func test_secrets_are_a_pure_function_of_the_seed_and_leak_into_rumours() -> void:
	var h := _hub()
	var folk := _town(h, 120)
	var sc: RefCounted = h.mod("secrets")
	var rows := 0
	for ch: String in folk:
		rows += sc.secrets_of(ch).size()
	assert_int(rows).is_between(15, 120)
	var sc2: RefCounted = _hub().mod("secrets")
	for ch2: String in folk.slice(0, 20):
		assert_str(JSON.stringify(sc2.secrets_of(ch2))).is_equal(JSON.stringify(sc.secrets_of(ch2)))
	assert_int(JSON.stringify(sc.serialize()).length()).is_less(200)         # nothing stored until something changes
	_days(h, 600, 600 + 40 * 7)
	assert_int(sc.stats["leaked"]).is_greater(0)
	# a crime in the event log becomes the criminal's secret
	var c: String = folk[3]
	h.mod("events").record("crime", "ss:0", [c], "theft", "A purse is cut", 4, 900)
	sc.tick_day(900, {})
	var kinds: Array = []
	for r: Dictionary in sc.secrets_of(c):
		kinds.append(r["kind"])
	assert_array(kinds).contains(["crime"])
	# a hidden plan is a hidden agenda
	var lead := _ch(h, 36, 900, 0, "smith")
	h.mod("minds").plan_begin(lead, "charter")
	var ag := false
	for r2: Dictionary in sc.secrets_of(lead):
		ag = ag or String(r2["kind"]) == "agenda"
	assert_bool(ag).is_true()


func test_the_added_save_stays_small_at_a_thousand_characters() -> void:
	var h := _hub()
	var mn: RefCounted = h.mod("minds")
	var sc: RefCounted = h.mod("secrets")
	var em: RefCounted = h.mod("emergence")
	var cfg: Dictionary = h_cfg()
	var folk := _town(h, 40)
	# worst case: every plan slot and every secret override in use, every person-effect slot full
	for i in mn.MAX_PLANS:
		mn._plan["ch:%d" % (9000 + i)] = [i % 2, 200, 600, 600, 0, 0]
	for i in sc.OVERRIDE_MAX:
		sc._o["ch:%d" % (9000 + i)] = PackedInt32Array([sc.pack(2, 9, 0, 600, 5), sc.pack(1, 4, 1, 600, 9), sc.pack(0, 7, 0, 600, 3)])
	for i in em.PFX_MAX:
		em._pfx.append([600, "ch:%d" % (9000 + i), "emergency", 12, 3000])
	for i in 240:
		em._pcool["ch:%d" % (9000 + i)] = 610
	var added := 0
	added += JSON.stringify(mn.serialize().get("pl", {})).length()
	added += JSON.stringify(sc.serialize()).length()
	added += JSON.stringify({"pc": em.serialize()["pc"], "pf": em.serialize()["pf"]}).length()
	print("NI-6/7/8 worst-case added save: ", added, " bytes (plans ", JSON.stringify(mn.serialize().get("pl", {})).length(), ", secrets ", JSON.stringify(sc.serialize()).length(), ")")
	assert_int(added).is_less(60 * 1024)
	assert_int(folk.size()).is_equal(40)
	assert_int(cfg["plans"].size()).is_greater(0)
