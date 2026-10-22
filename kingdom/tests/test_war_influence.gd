extends GdUnitTestSuite
## "Your part in the war" (scripts/realm/war_influence.gd): every action the player's character can take in a war,
## its gate, and what it feeds: war_sim tension/support/weariness/goal/guard, campaign armies/couriers/depots/
## covert evidence/engagements, factions relations and war reputation, society evidence. Plus the war3 polish:
## fair mirrored battles, the hero's morale aura and the smoothed tactical terrain.

const WarSim := preload("res://scripts/sim/war_sim.gd")
const Hub := preload("res://scripts/realm/realm_hub.gd")
const WarInfluence := preload("res://scripts/realm/war_influence.gd")
const Tac := preload("res://scripts/realm/tactical.gd")
const TView := preload("res://scripts/ui/war/tactical_view.gd")
const WarMap := preload("res://scripts/ui/war/war_map.gd")

const ENEMY := "ongur_khanate"
const HOT := {"feud_count": 2, "rift_instability": 0.9, "season": "spring"}
const COLD := {"feud_count": 0, "rift_instability": 0.0, "season": "spring"}

var _gold0 := 0


func before_test() -> void:
	_gold0 = Game.gold
	Game.gold = 500


func after_test() -> void:
	Game.gold = _gold0


## A stand-in for the Life autoload: war, career, a bag of goods and an injuries log.
func _life() -> RefCounted:
	var sc := GDScript.new()
	sc.source_code = "extends RefCounted\nvar war\nvar realm\nvar career_id := \"\"\nvar career_rank := \"\"\nvar items := {}\nvar wounds: Array = []\nvar injuries = self\nvar nobility = null\n" \
		+ "func add(type, day, days := -1):\n\twounds.append(type)\n\treturn {}\n" \
		+ "func count(i):\n\treturn int(items.get(i, 0))\n" \
		+ "func give(i, n := 1):\n\titems[i] = count(i) + n\n" \
		+ "func take(i, n := 1):\n\tif count(i) < n:\n\t\treturn false\n\titems[i] = count(i) - n\n\treturn true\n" \
		+ "func item_prop(i, p, d = null):\n\treturn 10\n"
	sc.reload()
	return sc.new()


## Peace: a hub, a bound life with a fresh war_sim and a player army at the capital.
func _peace() -> Dictionary:
	WorldGen.setup(2024)
	var h: RefCounted = Hub.new()
	var cm: RefCounted = h.mod("campaign")
	cm.call("set_hq", 0)
	cm.call("tick_day", 0, {})
	var life := _life()
	life.war = WarSim.new(777)
	life.realm = h
	cm.call("bind_life", life)
	return {"hub": h, "cm": cm, "life": life, "war": life.war, "wi": WarInfluence.new(life, h)}


## War: as _peace() but the war is on (hot ctx), enemy columns are on the map, the crown has an army.
func _war() -> Dictionary:
	var w := _peace()
	var ws: RefCounted = w["war"]
	var d := 0
	while not ws.is_at_war() and d < 120:
		ws.tick_day(d, HOT)
		d += 1
	assert_bool(ws.is_at_war()).is_true()
	var cm: RefCounted = w["cm"]
	cm.call("tick_day", d, {"life": w["life"]})
	w["crown"] = cm.call("spawn_army", "player", 0, 600, "loyal", "Ashford Host")
	w["day"] = d
	return w


func _rel(w: Dictionary, a: String, b: String) -> Dictionary:
	return (w["hub"] as RefCounted).call("mod", "factions").call("relation", a, b)


func _unit_ids(cm: RefCounted, army: int) -> Array:
	return (cm.call("army_units", army) as Array).map(func(u: Dictionary) -> int: return int(u["id"]))


func _age(w: Dictionary, days: int) -> void:
	var ws: RefCounted = w["war"]
	for i in days:
		ws.tick_day(ws._day + 1, HOT)


# --- gates ------------------------------------------------------------------------------------------------------

func test_war_actions_are_gated_by_war_and_peace() -> void:
	var w := _peace()
	var wi: RefCounted = w["wi"]
	assert_bool(wi.call("can", "enlist")["ok"]).is_false()
	assert_str(wi.call("can", "enlist")["reason"]).contains("not at war")
	assert_bool(wi.call("can", "scout_front")["ok"]).is_true()        # at peace it reads the border
	assert_bool(wi.call("can", "mediate")["ok"]).is_false()           # no quarrel yet
	var ww := _war()
	assert_bool((ww["wi"] as RefCounted).call("can", "mediate")["ok"]).is_false()   # too late once armies march
	assert_str((ww["wi"] as RefCounted).call("can", "mediate")["reason"]).contains("marching")
	var list: Array = (ww["wi"] as RefCounted).call("actions")
	assert_int(list.size()).is_equal(WarInfluence.ACTIONS.size())
	for a: Dictionary in list:
		for k in ["id", "label", "blurb", "feeds", "ok", "reason", "cost"]:
			assert_bool(a.has(k)).is_true()
		if not bool(a["ok"]):
			assert_str(String(a["reason"])).is_not_empty()      # a gated action says why


func test_unknown_or_gated_action_changes_nothing() -> void:
	var w := _war()
	var wi: RefCounted = w["wi"]
	var ws: RefCounted = w["war"]
	var t0: float = ws.tension_of(ENEMY)
	var g0 := Game.gold
	var r: Dictionary = wi.call("do", "provoke")      # war is on: too late
	assert_bool(r["ok"]).is_false()
	assert_bool(wi.call("do", "no_such_thing")["ok"]).is_false()
	assert_float(ws.tension_of(ENEMY)).is_equal(t0)
	assert_int(Game.gold).is_equal(g0)


func test_leads_are_plain_sentences_not_markers() -> void:
	var w := _war()
	var leads: Array = (w["wi"] as RefCounted).call("leads")
	assert_int(leads.size()).is_greater(1)
	for l in leads:
		assert_bool(l is String).is_true()
		assert_int(String(l).length()).is_greater(20)
	var p := _peace()
	(p["war"] as RefCounted).call("offer_cb", ENEMY, "insult", "An envoy insulted House Corvane.", 0)
	var pl: Array = (p["wi"] as RefCounted).call("leads")
	assert_bool(pl.any(func(l: String) -> bool: return l.contains("insulted House Corvane"))).is_true()


# --- enlist / militia ---------------------------------------------------------------------------------------------

func test_enlist_joins_a_crown_company_and_earns_trust_once_per_war() -> void:
	var w := _war()
	var wi: RefCounted = w["wi"]
	var cm: RefCounted = w["cm"]
	var army0: Dictionary = cm.call("player_armies")[0]
	var trust0 := float(_rel(w, "player", "caldrenn")["trust"])
	var r: Dictionary = wi.call("do", "enlist")
	assert_bool(r["ok"]).is_true()
	assert_int(Game.gold).is_equal(515)
	var army1: Dictionary = cm.call("armies").filter(func(a: Dictionary) -> bool: return int(a["id"]) == int(army0["id"]))[0]
	assert_float(army1["morale"]).is_greater(float(army0["morale"]) - 0.0001)
	assert_int(army1["strength"]).is_equal(int(army0["strength"]) + 1)
	assert_float(float(_rel(w, "player", "caldrenn")["trust"])).is_greater(trust0)
	assert_float(float((w["war"] as RefCounted).war["support"])).is_greater(-0.11)
	assert_bool(wi.call("can", "enlist")["ok"]).is_false()
	assert_str(wi.call("can", "enlist")["reason"]).is_not_empty()


func test_raise_militia_needs_standing_and_adds_a_personal_army() -> void:
	var w := _war()
	var wi: RefCounted = w["wi"]
	var cm: RefCounted = w["cm"]
	# an unknown commoner with no land is turned away
	wi.set("override", {"tier": 1, "landholder": false, "crown_trust": 20.0, "soldier": false})
	assert_bool(wi.call("can", "raise_militia")["ok"]).is_false()
	# land opens the door
	wi.set("override", {"landholder": true})
	assert_bool(wi.call("can", "raise_militia")["ok"]).is_true()
	var armies0: int = cm.call("player_armies").size()
	var sup0 := float((w["war"] as RefCounted).war["support"])
	var weary0: float = (w["war"] as RefCounted).exhaustion()
	var r: Dictionary = wi.call("do", "raise_militia", {"men": 40})
	assert_bool(r["ok"]).is_true()
	assert_int(cm.call("player_armies").size()).is_equal(armies0 + 1)
	assert_int(Game.gold).is_equal(440)
	assert_float(float((w["war"] as RefCounted).war["support"])).is_greater(sup0)
	assert_float((w["war"] as RefCounted).exhaustion()).is_less(weary0 + 0.0001)
	var mine: Dictionary = cm.call("player_armies").filter(func(a: Dictionary) -> bool: return int(a["id"]) == int(r["army_id"]))[0]
	assert_int(mine["strength"]).is_equal(40)
	var units: Array = cm.call("army_units", int(r["army_id"]))
	assert_bool(units.all(func(u: Dictionary) -> bool: return String(u["owner"]) == "personal")).is_true()
	assert_bool(wi.call("can", "raise_militia")["ok"]).is_false()        # cooldown


# --- scout, carry ----------------------------------------------------------------------------------------------

func test_scout_front_reveals_the_nearest_enemy_host_on_the_war_map() -> void:
	var w := _war()
	var cm: RefCounted = w["cm"]
	var before: int = cm.call("known_map").filter(func(e: Dictionary) -> bool: return e["kind"] == "force" and e["faction"] == ENEMY).size()
	var r: Dictionary = (w["wi"] as RefCounted).call("do", "scout_front")
	assert_bool(r["ok"]).is_true()
	assert_str(r["text"]).contains("war map")
	var after: Array = cm.call("known_map").filter(func(e: Dictionary) -> bool: return e["kind"] == "force" and e["faction"] == ENEMY)
	assert_int(after.size()).is_greater(before)
	assert_str(after[0]["source"]).is_equal("scout")


func test_scout_at_peace_reads_the_border_and_names_the_cause() -> void:
	var w := _peace()
	var ws: RefCounted = w["war"]
	ws.call("offer_cb", ENEMY, "claim", "Ongur claims the lands around Stonewatch by an old charter.", 0)
	ws.call("add_tension", ENEMY, 50.0)
	var r: Dictionary = (w["wi"] as RefCounted).call("do", "scout_front")
	assert_bool(r["ok"]).is_true()
	assert_str(r["text"]).contains("Stonewatch")
	assert_int((r["reasons"] as Array).size()).is_equal(1)


func test_carrying_an_order_yourself_is_faster_and_cannot_be_intercepted() -> void:
	var w := _war()
	var cm: RefCounted = w["cm"]
	var far := 1
	var bl := -1.0
	for i in range(1, WorldGen.settlements.size()):
		var p: Array = cm.call("path", 0, i)
		if not p.is_empty() and float(cm.call("path_length", p)) > bl:
			bl = cm.call("path_length", p)
			far = i
	var aid: int = cm.call("spawn_army", "player", far, 300, "loyal", "Far Company")
	var order := {"kind": "hold", "target": far}
	var plain: Dictionary = cm.call("issue_order", aid, order)
	var r: Dictionary = (w["wi"] as RefCounted).call("do", "carry_message", {"army_id": aid, "order": order})
	assert_bool(r["ok"]).is_true()
	var mine: Dictionary = r["courier"]
	assert_int(int(mine["eta_hours"])).is_less(int(plain["eta_hours"]))
	assert_bool(mine["safe"]).is_true()
	assert_bool(plain["safe"]).is_false()
	# a safe courier rides straight through an enemy camp that would cut down a hired one
	var cours: Array = cm.call("couriers")
	assert_int(cours.size()).is_equal(2)
	var cm_safe: Dictionary = cours.filter(func(c: Dictionary) -> bool: return bool(c["safe"]))[0]
	assert_bool(cm_safe["intercepted"]).is_false()


# --- supply, caravan -----------------------------------------------------------------------------------------------

func test_selling_to_the_depots_feeds_the_army_and_the_war() -> void:
	var w := _war()
	var life: RefCounted = w["life"]
	var cm: RefCounted = w["cm"]
	var ws: RefCounted = w["war"]
	life.call("give", "bread", 12)
	assert_bool((w["wi"] as RefCounted).call("can", "supply_army")["ok"]).is_true()
	var sup0 := float(ws.war["support"])
	var trust0 := float(_rel(w, "player", "caldrenn")["trust"])
	var stock0 := 0.0
	for d: Dictionary in cm.call("depots"):
		if d["faction"] == "player":
			stock0 += float(d["stock"])
	var r: Dictionary = (w["wi"] as RefCounted).call("do", "supply_army", {"good": "bread", "qty": 10})
	assert_bool(r["ok"]).is_true()
	assert_int(life.call("count", "bread")).is_equal(2)
	assert_int(Game.gold).is_greater(500)                              # they pay
	var stock1 := 0.0
	for d2: Dictionary in cm.call("depots"):
		if d2["faction"] == "player":
			stock1 += float(d2["stock"])
	assert_float(stock1).is_greater(stock0)
	assert_float(float(ws.war["support"])).is_greater(sup0)
	assert_float(float(_rel(w, "player", "caldrenn")["trust"])).is_greater(trust0)


func test_profiteering_sells_to_the_enemy_and_the_crown_remembers() -> void:
	var w := _war()
	var life: RefCounted = w["life"]
	var ws: RefCounted = w["war"]
	life.call("give", "bread", 8)
	var sup0 := float(ws.war["support"])
	var grief0 := float(_rel(w, "player", "caldrenn")["grievance"])
	var r: Dictionary = (w["wi"] as RefCounted).call("do", "supply_army", {"good": "bread", "qty": 8, "side": "enemy"})
	assert_bool(r["ok"]).is_true()
	assert_float(float(ws.war["support"])).is_less(sup0)
	assert_float(float(_rel(w, "player", "caldrenn")["grievance"])).is_greater(grief0)
	var rep: Dictionary = (w["hub"] as RefCounted).call("mod", "factions").call("war_rep", "player")
	assert_float(float(rep["ruthless"])).is_greater(0.0)


func test_a_caravan_through_the_front_pays_double_or_loses_the_cargo() -> void:
	var seen := {"through": 0, "lost": 0}
	for day in 14:
		var w := _war()
		var life: RefCounted = w["life"]
		life.call("give", "cheese", 6)
		(w["war"] as RefCounted)._day += day * 7
		var g0 := Game.gold
		var r: Dictionary = (w["wi"] as RefCounted).call("do", "run_caravan", {"good": "cheese", "qty": 6})
		assert_bool(r["ok"]).is_true()
		assert_int(life.call("count", "cheese")).is_equal(0)           # the cargo leaves either way
		if bool(r["through"]):
			seen["through"] += 1
			assert_int(Game.gold).is_equal(g0 + 120)                   # 6 x 10 x 2
		else:
			seen["lost"] += 1
			assert_int(Game.gold).is_equal(g0)
	assert_int(seen["through"]).is_greater(0)
	assert_int(seen["lost"] + seen["through"]).is_equal(14)


# --- covert ops, evidence ----------------------------------------------------------------------------------------

func test_sabotage_spy_forgery_leave_evidence_in_campaign_and_society() -> void:
	var w := _war()
	var cm: RefCounted = w["cm"]
	var soc: RefCounted = (w["hub"] as RefCounted).call("mod", "society")
	var e0: int = soc.call("evidence").size()
	var ids := []
	for id in ["sabotage", "spy", "forge_letter"]:
		_age(w, 6)          # cooldowns
		var r: Dictionary = (w["wi"] as RefCounted).call("do", id)
		assert_bool(r["ok"]).is_true()
		assert_str(String(r["society_evidence"])).is_not_empty()
		ids.append(int(r["evidence_id"]))
	assert_int(soc.call("evidence").size()).is_equal(e0 + 3)
	assert_int(cm.call("evidence").size()).is_equal(3)
	var types := {}
	for e: Dictionary in soc.call("evidence"):
		types[e["type"]] = true
	assert_bool(types.has("cut_rope") and types.has("coded_note") and types.has("forged_seal")).is_true()
	assert_int(Game.gold).is_equal(500 - 40 - 25 - 30)


func test_a_successful_spy_reveals_precise_intel() -> void:
	var w := _war()
	var cm: RefCounted = w["cm"]
	var foe: Dictionary = cm.call("armies").filter(func(a: Dictionary) -> bool: return a["faction"] != "player")[0]
	var hit := false
	for i in 30:         # the op is a roll: some attempt succeeds
		var res: Dictionary = cm.call("covert_op", "spy", int(foe["id"]))
		if bool(res["ok"]):
			hit = true
			break
	assert_bool(hit).is_true()
	var km: Array = cm.call("known_map").filter(func(e: Dictionary) -> bool: return e["kind"] == "force" and e["source"] == "spy")
	assert_int(km.size()).is_greater(0)
	assert_float(km[0]["confidence"]).is_greater(0.85)


func test_exposed_covert_work_sours_relations_and_hands_the_enemy_a_casus_belli() -> void:
	var w := _war()
	var cm: RefCounted = w["cm"]
	var ws: RefCounted = w["war"]
	var foe: Dictionary = cm.call("armies").filter(func(a: Dictionary) -> bool: return a["faction"] != "player")[0]
	var res: Dictionary = cm.call("covert_op", "assassination", int(foe["id"]), {"crestless": false})
	assert_int(int(res["evidence_id"])).is_greater(-1)
	var grief0 := float(_rel(w, "player", String(foe["faction"]))["grievance"])
	var t0: float = ws.tension_of(String(foe["faction"]))
	var found := false
	for d in 120:
		cm.call("tick_day", 50 + d, {"life": w["life"]})
		var evs: Array = cm.call("evidence").filter(func(e: Dictionary) -> bool: return bool(e["discovered"]))
		if not evs.is_empty():
			found = true
			break
	assert_bool(found).is_true()
	assert_float(float(_rel(w, "player", String(foe["faction"]))["grievance"])).is_greater(grief0)
	assert_float(ws.tension_of(String(foe["faction"]))).is_greater(t0)
	assert_bool(ws.has_cb_kind(String(foe["faction"]), "incident")).is_true()
	var rep: Dictionary = (w["hub"] as RefCounted).call("mod", "factions").call("war_rep", "player")
	assert_float(float(rep["ruthless"])).is_greater(0.0)


func test_covering_your_tracks_lowers_the_chance_of_being_found() -> void:
	var w := _war()
	var cm: RefCounted = w["cm"]
	var foe: Dictionary = cm.call("armies").filter(func(a: Dictionary) -> bool: return a["faction"] != "player")[0]
	var res: Dictionary = cm.call("covert_op", "sabotage", int(foe["node"]), {"crestless": false})
	var before: float = cm.call("evidence")[0]["clarity"]
	assert_bool(cm.call("cover_tracks", int(res["evidence_id"]))).is_true()
	assert_float(float(cm.call("evidence")[0]["clarity"])).is_less(before)
	var soc: RefCounted = (w["hub"] as RefCounted).call("mod", "society")
	assert_bool(soc.call("evidence").any(func(e: Dictionary) -> bool: return e["id"] == res["society_evidence"])).is_false()


# --- brokering, provoking ------------------------------------------------------------------------------------------

func test_brokering_peace_needs_both_courts_and_ends_a_weary_war_with_terms() -> void:
	var w := _war()
	var wi: RefCounted = w["wi"]
	var ws: RefCounted = w["war"]
	wi.set("override", {"crown_trust": 10.0, "enemy_trust": 5.0, "tier": 1})
	_age(w, 12)
	assert_bool(wi.call("can", "broker_peace")["ok"]).is_false()
	assert_str(wi.call("can", "broker_peace")["reason"]).contains("trusts")
	wi.set("override", {"crown_trust": 70.0, "enemy_trust": 60.0, "tier": 4})
	assert_bool(wi.call("can", "broker_peace")["ok"]).is_true()
	# a weary war: the brokered terms are signed, the truce starts, both sides send gifts
	ws.war["exhaustion"] = 0.8
	ws.war["enemy_exhaustion"] = 0.8
	var g0 := Game.gold
	var done := false
	for d in 10:
		var r: Dictionary = wi.call("do", "broker_peace", {"terms": "lenient"})
		if bool(r["ok"]) and bool(r.get("concluded", false)):
			done = true
			assert_str(r["text"]).contains("signed")
			break
		_age(w, 16)
		ws.war["exhaustion"] = 0.8
		ws.war["enemy_exhaustion"] = 0.8
	assert_bool(done).is_true()
	assert_bool(ws.is_at_war()).is_false()
	assert_bool(ws.under_truce(ENEMY)).is_true()
	assert_str(String(ws.last_treaty["text"])).contains("by your brokering")
	assert_int(Game.gold).is_greater(g0)
	assert_float(float(_rel(w, "player", ENEMY)["trust"])).is_greater(5.0)


func test_a_failed_brokering_costs_trust_and_a_success_adds_peace_pressure() -> void:
	var w := _war()
	var wi: RefCounted = w["wi"]
	var ws: RefCounted = w["war"]
	wi.set("override", {"crown_trust": 50.0, "enemy_trust": 40.0, "tier": 2})
	_age(w, 12)
	var p0 := float(ws.war.get("pressure", 0.0))
	var r: Dictionary = wi.call("do", "broker_peace", {"terms": "harsh"})
	assert_bool(r["ok"]).is_true()
	if bool(r["success"]):
		assert_float(float(ws.war.get("pressure", 0.0)) + (1.0 if bool(r.get("concluded", false)) else 0.0)).is_greater(p0)
	else:
		assert_str(r["text"]).contains("neither will be the first")


func test_mediating_before_blows_eases_tension_and_trusts() -> void:
	var w := _peace()
	var ws: RefCounted = w["war"]
	ws.call("add_tension", ENEMY, 60.0)
	ws.call("offer_cb", ENEMY, "incident", "A border incident.", 0)
	var t0: float = ws.tension_of(ENEMY)
	var trust0 := float(_rel(w, "player", ENEMY)["trust"])
	(w["wi"] as RefCounted).set("override", {"crown_trust": 60.0})
	var r: Dictionary = (w["wi"] as RefCounted).call("do", "mediate")
	assert_bool(r["ok"]).is_true()
	assert_float(ws.tension_of(ENEMY)).is_less(t0)
	assert_bool(ws.has_cb_kind(ENEMY, "incident")).is_false()
	assert_float(float(_rel(w, "player", ENEMY)["trust"])).is_greater(trust0)


func test_provoking_an_incident_raises_tension_gives_a_casus_belli_and_risks_exposure() -> void:
	var w := _peace()
	var ws: RefCounted = w["war"]
	var soc: RefCounted = (w["hub"] as RefCounted).call("mod", "society")
	var t0: float = ws.tension_of(ENEMY)
	var grief0 := float(_rel(w, "player", ENEMY)["grievance"])
	var e0: int = soc.call("evidence").size()
	var r: Dictionary = (w["wi"] as RefCounted).call("do", "provoke", {"nation": ENEMY})
	assert_bool(r["ok"]).is_true()
	assert_float(ws.tension_of(ENEMY)).is_greater(t0 + 10.0)
	assert_bool(ws.has_casus_belli(ENEMY)).is_true()
	assert_float(float(_rel(w, "player", ENEMY)["grievance"])).is_greater(grief0)
	assert_int(soc.call("evidence").size()).is_equal(e0 + 1)
	assert_int(((w["cm"] as RefCounted).call("evidence") as Array).size()).is_equal(1)
	var rep: Dictionary = (w["hub"] as RefCounted).call("mod", "factions").call("war_rep", "player")
	assert_float(float(rep["honour"])).is_less(0.0)
	assert_bool((w["wi"] as RefCounted).call("can", "provoke")["ok"]).is_false()     # cooldown


func test_provoking_under_a_truce_breaks_it() -> void:
	var w := _peace()
	var ws: RefCounted = w["war"]
	ws.truce_until[ENEMY] = 400
	assert_bool(ws.under_truce(ENEMY, 0)).is_true()
	var r: Dictionary = (w["wi"] as RefCounted).call("do", "provoke", {"nation": ENEMY})
	assert_bool(r["ok"]).is_true()
	assert_bool(r["broke_truce"]).is_true()
	assert_bool(ws.under_truce(ENEMY, 0)).is_false()
	assert_bool(ws.has_cb_kind(ENEMY, "broken_treaty")).is_true()
	var rep: Dictionary = (w["hub"] as RefCounted).call("mod", "factions").call("war_rep", "player")
	assert_float(float(rep["honour"])).is_less(-5.0)


func test_provoking_then_waiting_can_start_a_war_that_needs_a_reason() -> void:
	var w := _peace()
	var ws: RefCounted = w["war"]
	for i in 6:
		_age_peace(ws, 13)
		(w["wi"] as RefCounted).call("do", "provoke", {"nation": ENEMY})
		ws.call("add_tension", ENEMY, 40.0)
	var declared := false
	for d in 200:
		ws.call("tick_day", ws._day + 1, COLD)
		if ws.is_at_war():
			declared = true
			break
	assert_bool(declared).is_true()
	assert_bool((ws.war["cb"] as Dictionary).is_empty()).is_false()


func _age_peace(ws: RefCounted, days: int) -> void:
	for i in days:
		ws.call("tick_day", ws._day + 1, COLD)


# --- fighting, defending, council ---------------------------------------------------------------------------------

func test_fighting_personally_adds_a_champion_and_steadies_the_crown_line() -> void:
	var w := _war()
	var cm: RefCounted = w["cm"]
	var foe_id: int = cm.call("armies").filter(func(a: Dictionary) -> bool: return a["faction"] != "player")[0]["id"]
	var mine: int = w["crown"]
	assert_bool((w["wi"] as RefCounted).call("can", "champion")["ok"]).is_false()     # no fight yet
	var e: Dictionary = cm.call("open_engagement", _unit_ids(cm, mine), _unit_ids(cm, foe_id), 100.0, 100.0)
	assert_bool(e.is_empty()).is_false()
	var eng_id := int(e["id"])
	var base: Dictionary = cm.call("engagement_raw", eng_id)
	assert_str(String(base.get("champion_side", ""))).is_empty()
	var r: Dictionary = (w["wi"] as RefCounted).call("do", "champion")
	assert_bool(r["ok"]).is_true()
	assert_str(r["text"]).contains("front rank")
	var raw: Dictionary = cm.call("engagement_raw", eng_id)
	assert_str(String(raw["champion_side"])).is_not_empty()
	assert_bool((raw["log"] as Array).any(func(l: String) -> bool: return l.contains("place in the line"))).is_true()
	# once in the line you cannot join twice
	assert_bool(cm.call("join_engagement", eng_id)["ok"]).is_false()
	# and the wound roll is reported and applied to the life
	if bool(r["wounded"]):
		assert_int((w["life"] as RefCounted).wounds.size()).is_equal(1)


func test_champion_boosts_the_engagement_against_the_same_fight_without_one() -> void:
	var ratios := []
	for with_champ in [false, true]:
		var w := _war()
		var cm: RefCounted = w["cm"]
		var foe_id: int = cm.call("armies").filter(func(a: Dictionary) -> bool: return a["faction"] != "player")[0]["id"]
		var e: Dictionary = cm.call("open_engagement", _unit_ids(cm, int(w["crown"])), _unit_ids(cm, foe_id), 100.0, 100.0)
		var eng_id := int(e["id"])
		if with_champ:
			cm.call("join_engagement", eng_id)
		var lost := 0.0
		for h in 6:
			cm.call("tick_hour", h, {"life": w["life"]})
		var view: Dictionary = cm.call("engagement_view", eng_id)
		ratios.append(float(view["ratio_player"]))
	assert_float(ratios[1]).is_greater(ratios[0])


func test_the_champion_becomes_a_hero_unit_on_the_tactical_map_and_steadies_morale() -> void:
	WorldGen.setup(2024)
	var mk := func(hero: bool) -> RefCounted:
		var a: Array = []
		for i in 3:
			a.append({"cid": 0, "name": "Inf %d" % i, "kind": "infantry", "men": 150, "quality": 0.6, "morale": 0.6, "fatigue": 0.0})
		var elites := []
		if hero:
			elites.append({"kind": "champion", "name": "You", "men": 1, "quality": 0.95, "morale": 1.0, "hero": true})
		var sa := {"faction": "caldrenn", "player": false, "name": "a", "units": a, "elites": elites, "supply": 3.0,
			"cmd": {"name": "G", "personality": "loyal", "skill": 2, "tactics": 48, "experience": 48}}
		var sb := {"faction": "ongur_khanate", "player": false, "name": "b", "units": a.duplicate(true), "supply": 3.0,
			"cmd": {"name": "H", "personality": "loyal", "skill": 2, "tactics": 48, "experience": 48}}
		return Tac.create({"seed": 41, "name": "T", "center": [-1800.0, -2300.0], "deploy": false, "attacker": "b", "sides": {"a": sa, "b": sb}})
	var plain: RefCounted = mk.call(false)
	var heroic: RefCounted = mk.call(true)
	var hero_i := -1
	for i in heroic.unit_count():
		if bool((heroic.u_meta[i] as Dictionary).get("hero", false)):
			hero_i = i
	assert_int(hero_i).is_greater(-1)
	plain.advance(60)
	heroic.advance(60)
	# the same three-unit line holds its morale better with the hero in it (mean morale of the side's non-hero units)
	var mor := func(tt: RefCounted) -> float:
		var s := 0.0
		var n := 0.0
		for i in tt.unit_count():
			if int(tt.u_side[i]) == 0 and not bool((tt.u_meta[i] as Dictionary).get("hero", false)) and tt.u_st[i] < 7:
				s += tt.u_mor[i]
				n += 1.0
		return s / maxf(n, 1.0)
	assert_float(mor.call(heroic)).is_greater(mor.call(plain) - 0.0001)


func test_defending_home_turns_raiders_back_and_steadies_the_people() -> void:
	var w := _war()
	var wi: RefCounted = w["wi"]
	var ws: RefCounted = w["war"]
	var land: RefCounted = (w["hub"] as RefCounted).call("mod", "land")
	wi.set("override", {"home_threatened": true})
	assert_bool(wi.call("can", "defend_home")["ok"]).is_true()
	var loy0: float = land.call("loyalty", 0)
	var r: Dictionary = wi.call("do", "defend_home")
	assert_bool(r["ok"]).is_true()
	assert_float(land.call("loyalty", 0)).is_greater(loy0)
	assert_int(Game.gold).is_equal(475)
	var name := String(r["settlement"])
	assert_bool(ws.guarded.has(name)).is_true()
	# put a front region right at home and let ten days pass: nobody is raided while guarded
	var home: Dictionary = WorldGen.settlements[0]
	ws.war["front"] = [{"name": "Home march", "pos": home["pos"], "control": 0.5}]
	var raided := 0
	var turned := 0
	for i in 120:
		ws.war["exhaustion"] = 0.0          # keep the war going long enough for raiders to try
		ws.war["enemy_exhaustion"] = 0.0
		ws.war["front"][0]["control"] = 0.5       # a decisive front would end the war
		ws.guard_settlement(name, ws._day + 10)
		for line: String in ws.call("tick_day", ws._day + 1, HOT):
			if line.contains("turned back"):
				turned += 1
		for rd: Dictionary in ws.call("raided_today"):
			if String(rd["settlement_name"]) == name:
				raided += 1
		if not ws.is_at_war():
			break
	assert_int(raided).is_equal(0)
	assert_int(turned).is_greater(0)


func test_pushing_a_war_goal_changes_the_peace_that_follows() -> void:
	var w := _war()
	var wi: RefCounted = w["wi"]
	var ws: RefCounted = w["war"]
	wi.set("override", {"crown_trust": 80.0})
	var old := String(ws.war["goal"])
	var goal := "hostages" if old != "hostages" else "land"
	var r: Dictionary = wi.call("do", "push_goal", {"goal": goal})
	assert_bool(r["ok"]).is_true()
	assert_str(String(ws.war["goal"])).is_equal(goal)
	assert_bool((w["cm"] as RefCounted).call("war_goals").any(func(g: Dictionary) -> bool: return String(g["text"]).contains("Your council"))).is_true()
	for f: Dictionary in ws.war["front"]:
		f["control"] = 0.9
	var t: Dictionary = ws.propose_terms()
	assert_str(String(t["goal"])).is_equal(goal)
	if goal == "hostages":
		assert_int((t["hostages"] as Array).size()).is_greater(0)
	wi.set("override", {"crown_trust": 10.0, "tier": 1, "landholder": false})
	assert_bool(wi.call("can", "push_goal")["ok"]).is_false()


# --- the realm applies the peace -------------------------------------------------------------------------------------

func test_a_lost_war_cedes_the_named_land_and_a_won_one_confirms_it() -> void:
	var w := _war()
	var ws: RefCounted = w["war"]
	var cm: RefCounted = w["cm"]
	var land: RefCounted = (w["hub"] as RefCounted).call("mod", "land")
	var fac: RefCounted = (w["hub"] as RefCounted).call("mod", "factions")
	ws.set_goal("land")
	for f: Dictionary in ws.war["front"]:
		f["control"] = 0.05        # the enemy holds the ground
	var t: Dictionary = ws.propose_terms()
	assert_str(String(t["winner"])).is_equal("enemy")
	var name := String(t["land"])
	assert_str(name).is_not_empty()
	var wealth0: float = fac.call("faction", "caldrenn")["wealth"]
	ws.conclude_peace(ws._day + 40, t)
	cm.call("tick_day", ws._day + 41, {"life": w["life"]})
	var sid := -1
	for s: Dictionary in WorldGen.settlements:
		if String(s["name"]) == name:
			sid = int(s["id"])
	if sid >= 0:
		assert_str(String(land.call("deed", sid)["occupier"])).is_equal(ENEMY)
	assert_bool(cm.call("captured").values().has(ENEMY) or sid < 0).is_true()
	if int(t["tribute"]) > 0:
		assert_float(float(fac.call("faction", "caldrenn")["wealth"])).is_less(wealth0)
	# applying twice does nothing more
	var n0: int = land.call("deed", sid)["history"].size() if sid >= 0 else 0
	cm.call("tick_day", ws._day + 42, {"life": w["life"]})
	if sid >= 0:
		assert_int(land.call("deed", sid)["history"].size()).is_equal(n0)


func test_campaign_feeds_claims_on_land_you_hold_to_the_war_sim() -> void:
	var w := _peace()
	var ws: RefCounted = w["war"]
	var cm: RefCounted = w["cm"]
	var land: RefCounted = (w["hub"] as RefCounted).call("mod", "land")
	var sid := -1
	for s: Dictionary in WorldGen.settlements:
		if String(s["kind"]) == "frontier_town":
			sid = int(s["id"])
			break
	assert_int(sid).is_greater(-1)
	land.call("occupy", sid, "player")
	var got := false
	for d in 400:
		cm.call("tick_day", d + 1, {"life": w["life"]})
		for id in WarSim.WAR_CANDIDATES:
			if ws.has_cb_kind(id, "claim"):
				got = true
		if got:
			break
	assert_bool(got).is_true()
	assert_bool(ws.news(10).any(func(l: String) -> bool: return l.contains("Grievance with"))).is_true()


func test_engagement_results_feed_the_abstract_war() -> void:
	var w := _war()
	var ws: RefCounted = w["war"]
	var sup0 := float(ws.war["support"])
	var cas0: int = int(ws.war["enemy_losses"])
	var ctrl0 := 0.0
	for f: Dictionary in ws.war["front"]:
		ctrl0 += float(f["control"])
	ws.call("note_engagement", true, 20, 60, (ws.war["front"][0]["pos"] as Vector2))
	assert_float(float(ws.war["support"])).is_greater(sup0)
	assert_int(int(ws.war["enemy_losses"])).is_equal(cas0 + 60)
	var ctrl1 := 0.0
	for f2: Dictionary in ws.war["front"]:
		ctrl1 += float(f2["control"])
	assert_float(ctrl1).is_greater(ctrl0)


# --- fair battles and smooth terrain -------------------------------------------------------------------------------

func _army16(scale := 1.0) -> Array:
	var kinds := ["infantry", "infantry", "infantry", "infantry", "spear", "spear", "spear", "archer", "archer", "archer", "heavy_cav", "heavy_cav", "light_cav", "light_cav", "mage", "scout"]
	var units: Array = []
	for i in 16:
		units.append({"cid": 0, "name": "%s %d" % [kinds[i], i], "kind": kinds[i], "men": int((200 if kinds[i] in ["infantry", "spear"] else 100) * scale), "quality": 0.6, "morale": 0.75, "fatigue": 0.0})
	return units


func _side16(scale := 1.0) -> Dictionary:
	return {"faction": "caldrenn", "player": false, "name": "caldrenn", "units": _army16(scale), "supply": 3.0,
		"cmd": {"name": "Gen", "personality": "loyal", "skill": 2, "tactics": 48, "experience": 48, "leadership": 50, "discipline": 50, "adaptability": 50, "scouting": 50, "logistics": 50}}


func _open_spots(n: int) -> Array:
	var out: Array = []
	var tries := 0
	while out.size() < n and tries < 4000:
		tries += 1
		var p := Vector2(-3800 + (tries * 1733) % 7600, -3800 + (tries * 3119) % 7600)
		var g: Dictionary = Tac.gen_grid(p, 40, 40.0)
		var c: Array = g["counts"]
		if int(c[Tac.T_WALL]) + int(c[Tac.T_TOWN]) + int(c[Tac.T_RIVER]) + int(c[Tac.T_BRIDGE]) == 0 and int(c[Tac.T_MOUNT]) < 120 and int(c[Tac.T_OPEN]) + int(c[Tac.T_ROAD]) > 600:
			out.append(p)
	return out


func test_mirrored_even_battles_are_fair_for_the_attacker() -> void:
	WorldGen.setup(2024)
	var spots := _open_spots(10)
	assert_int(spots.size()).is_greater_equal(8)
	var att_wins := 0
	var decided := 0
	var a_wins := 0
	var runs := 0
	for att in ["a", "b"]:
		for sd in spots.size():
			var p: Vector2 = spots[sd]
			var tt: RefCounted = Tac.create({"seed": 100 + sd, "name": "T", "center": [p.x, p.y], "deploy": false, "attacker": att, "sides": {"a": _side16(), "b": _side16()}})
			var r: Dictionary = tt.run_to_end(2200)
			runs += 1
			if String(r["winner"]) != "":
				decided += 1
				if String(r["winner"]) == att:
					att_wins += 1
				if String(r["winner"]) == "a":
					a_wins += 1
	var share := float(att_wins) / float(maxi(decided, 1))
	print("mirrored 16v16: attacker wins %d of %d decided (%.0f%%); side a wins %d" % [att_wins, decided, share * 100.0, a_wins])
	assert_int(decided).is_greater(runs - 4)
	assert_float(share).is_between(0.35, 0.65)            # was 10%
	assert_float(float(a_wins) / float(maxi(decided, 1))).is_between(0.3, 0.7)


func test_defender_fortify_bonus_only_when_holding_high_ground() -> void:
	WorldGen.setup(2024)
	var p := Vector2(-1800.0, -2300.0)
	var tt: RefCounted = Tac.create({"seed": 3, "name": "T", "center": [p.x, p.y], "deploy": false, "attacker": "a", "sides": {"a": _side16(), "b": _side16()}})
	assert_float(Tac.ATTACK_EDGE).is_greater(1.0)
	assert_float(Tac.HOLD_HEIGHT).is_greater(0.0)
	# siege fights (walled rings) get no attacker initiative bonus
	var ring := {"c": [800.0, 800.0], "r": 300.0, "gates": [0.0], "breaches": [], "landings": [], "inner": []}
	var ts: RefCounted = Tac.create({"seed": 3, "name": "S", "center": [p.x, p.y], "deploy": false, "attacker": "a", "opts": {"ring": ring}, "sides": {"a": _side16(), "b": _side16()}})
	assert_float(tt._att_edge).is_equal(Tac.ATTACK_EDGE)
	assert_float(ts._att_edge).is_equal(1.0)


func test_both_sides_pick_their_approach_anchor() -> void:
	WorldGen.setup(2024)
	var p := Vector2(-2300.0, -2300.0)
	var moved := 0
	for att in ["a", "b"]:
		var tt: RefCounted = Tac.create({"seed": 8, "name": "T", "center": [p.x, p.y], "deploy": true, "attacker": att, "sides": {"a": _side16(), "b": _side16()}})
		var half: float = float(tt.n) * float(tt.cell) * 0.5
		for k in 2:
			var an := Vector2(float(tt.S[k]["anchor"][0]), float(tt.S[k]["anchor"][1]))
			var dirv := Vector2.from_angle(float(tt.S[k]["axis"]))
			var nominal := Vector2(half, half) - dirv * minf(520.0, half * 0.66)
			if an.distance_to(nominal) > 1.0:
				moved += 1
	assert_int(moved).is_greater(0)         # anchors are searched for both attacker and defender


func test_tactical_terrain_texture_is_smoothed_not_blocky() -> void:
	WorldGen.setup(2024)
	var tt: RefCounted = Tac.create({"seed": 12, "name": "Smooth", "center": [-1800.0, -2300.0], "deploy": true, "attacker": "b", "sides": {"a": _side16(), "b": _side16()}})
	var v: Control = TView.new()
	v.set("tt", tt)
	v.size = Vector2(1280, 720)
	add_child(auto_free(v))
	var t0 := Time.get_ticks_usec()
	var tex: ImageTexture = v.call("terrain_texture")
	var bake_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	print("tactical terrain bake: %.0f ms" % bake_ms)
	var up: int = TView.SMOOTH_UP
	assert_int(tex.get_width()).is_equal(tt.n * up)
	assert_int(tex.get_height()).is_equal(tt.n * up)
	var img := tex.get_image()
	# blocky = runs of identical pixels the width of a cell; smooth = neighbours mostly differ a little
	var same := 0
	var total := 0
	var big := 0
	for y in range(0, img.get_height(), 7):
		for x in range(img.get_width() - 1):
			var a := img.get_pixel(x, y)
			var b := img.get_pixel(x + 1, y)
			total += 1
			if a == b:
				same += 1
			if absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > 0.45:
				big += 1
	assert_float(float(same) / float(total)).is_less(0.35)
	assert_float(float(big) / float(total)).is_less(0.04)    # only thin seams between ground classes, never cell-wide jumps
	assert_bool(bake_ms < 2500.0).is_true()


func test_perf_sixteen_versus_sixteen_still_within_budget_with_the_fairness_changes() -> void:
	WorldGen.setup(2024)
	var best := 1.0e9
	for rep in 5:
		var tt: RefCounted = Tac.create({"seed": 131, "name": "P", "center": [-1800.0, -2300.0], "deploy": false, "attacker": "a", "sides": {"a": _side16(), "b": _side16()}})
		var t0 := Time.get_ticks_usec()
		for i in 600:
			tt.step()
		best = minf(best, float(Time.get_ticks_usec() - t0) / 1000.0)
	print("16v16 x600 steps: %.1f ms" % best)
	assert_float(best).is_less(50.0)


# --- the UI ---------------------------------------------------------------------------------------------------------

func _texts(n: Node, out: Array = []) -> Array:
	if n is Label:
		out.append((n as Label).text)
	elif n is Button:
		out.append((n as Button).text)
	for c in n.get_children():
		_texts(c, out)
	return out


func test_your_part_tab_lists_diplomacy_leads_and_actions_and_runs_them() -> void:
	var w := _war()
	var m: Control = WarMap.new()
	m.set("realm_override", w["hub"])
	m.size = Vector2(1280, 720)
	add_child(auto_free(m))
	var wi: RefCounted = m.call("influence")
	wi.set("life", w["life"])
	m.call("set_tab", "part")
	var txt := "\n".join(PackedStringArray(_texts(m.get("_panel"))))
	assert_str(txt).contains("YOUR PART IN THE WAR")
	assert_str(txt).contains("Borders and courts")
	assert_str(txt).contains("Ongur")
	assert_str(txt).contains("What you can do")
	assert_str(txt).contains("Enlist in the crown's host")
	assert_str(txt).contains("Do it")
	assert_str(txt).contains("Word on the road")
	# a gated action shows why, in words
	assert_str(txt).contains("Provoke an incident")
	assert_str(txt).contains("armies are marching")
	# pressing an action runs it, toasts the result and redraws
	var r: Dictionary = m.call("do_war_action", "enlist")
	assert_bool(r["ok"]).is_true()
	assert_str(String(m.get("status_text"))).contains("crown's shilling")
	var txt2 := "\n".join(PackedStringArray(_texts(m.get("_panel"))))
	assert_str(txt2).contains("What you have done")
	assert_str(txt2).contains("done that too recently")
