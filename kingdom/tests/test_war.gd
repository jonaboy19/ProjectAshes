extends GdUnitTestSuite
## War between Caldrenn and a neighbour: tension building to a deterministic
## declaration, the front, daily battles, exhaustion into a treaty, the
## at_war toggle, player hooks and save round trips.

const WarSim := preload("res://scripts/sim/war_sim.gd")

const HOT_CTX := {"feud_count": 2, "rift_instability": 0.9, "season": "spring"}
const COLD_CTX := {"feud_count": 0, "rift_instability": 0.0, "season": "spring"}


func _tick_until(ws: RefCounted, days: int, ctx: Dictionary, want_war: bool) -> int:
	for d in days:
		ws.tick_day(d, ctx)
		if ws.is_at_war() == want_war:
			return d
	return -1


func test_tension_declares_war_deterministically_for_a_seed() -> void:
	WorldGen.setup(2024)
	var a := WarSim.new(777)
	var b := WarSim.new(777)
	var day_a := _tick_until(a, 80, HOT_CTX, true)
	var day_b := _tick_until(b, 80, HOT_CTX, true)
	assert_int(day_a).is_greater(0)
	assert_int(day_a).is_equal(day_b)
	assert_str(a.enemy_id()).is_equal(b.enemy_id())
	assert_str(JSON.stringify(a.serialize())).is_equal(JSON.stringify(b.serialize()))


func test_peacetime_tension_decays_and_never_declares_war() -> void:
	WorldGen.setup(2024)
	var ws := WarSim.new(11)
	for d in 200:
		ws.tick_day(d, COLD_CTX)
	assert_bool(ws.is_at_war()).is_false()
	for id in WarSim.WAR_CANDIDATES:
		assert_float(ws.tension_of(id)).is_less(WarSim.TENSION_WAR_THRESHOLD)


func test_front_has_two_or_three_border_regions() -> void:
	WorldGen.setup(2024)
	var ws := WarSim.new(777)
	_tick_until(ws, 80, HOT_CTX, true)
	var front: Array = ws.front()
	assert_int(front.size()).is_between(2, 3)
	var names := {}
	for f: Dictionary in front:
		assert_bool(f.has("pos")).is_true()
		names[f["name"]] = true
	assert_int(names.size()).is_equal(front.size())    # distinct regions


func test_battles_cause_casualties() -> void:
	WorldGen.setup(2024)
	var ws := WarSim.new(777)
	_tick_until(ws, 80, HOT_CTX, true)
	var before := ws.casualties()
	var d0: int = ws._day
	for d in 12:          # battles are no longer a daily certainty: a fortnight has some
		ws.tick_day(d0 + 1 + d, HOT_CTX)
		if not ws.is_at_war():
			break
	var after := ws.casualties()
	assert_int(int(after["caldrenn"]) + int(after["enemy"])).is_greater(int(before["caldrenn"]) + int(before["enemy"]))


func test_exhaustion_ends_the_war_with_a_treaty() -> void:
	WorldGen.setup(2024)
	var ws := WarSim.new(777)
	var declared := _tick_until(ws, 80, HOT_CTX, true)
	assert_int(declared).is_greater(0)
	var ended := _tick_until(ws, 200, HOT_CTX, false)
	assert_int(ended).is_greater(declared)
	assert_bool(ws.is_at_war()).is_false()
	assert_int(ws.chronicle.size()).is_greater(0)


func test_at_war_toggles_across_a_full_war() -> void:
	WorldGen.setup(2024)
	var ws := WarSim.new(777)
	assert_bool(ws.is_at_war()).is_false()
	_tick_until(ws, 80, HOT_CTX, true)
	assert_bool(ws.is_at_war()).is_true()
	_tick_until(ws, 200, HOT_CTX, false)
	assert_bool(ws.is_at_war()).is_false()


func test_battle_at_front_and_contract_hooks_only_during_war() -> void:
	WorldGen.setup(2024)
	var ws := WarSim.new(777)
	assert_dict(ws.battle_at_front()).is_empty()
	assert_dict(ws.contract_for_merchant(1)).is_empty()
	assert_float(ws.crop_requisition_fraction()).is_equal(0.0)
	_tick_until(ws, 80, HOT_CTX, true)
	var battle := ws.battle_at_front()
	assert_bool(battle.has("pos")).is_true()
	assert_int(int(battle["size"])).is_greater(0)
	assert_bool(ws.contract_for_merchant(5).has("good")).is_true()
	assert_float(ws.crop_requisition_fraction()).is_greater(0.0)


func test_news_and_rumours_report_the_war() -> void:
	WorldGen.setup(2024)
	var ws := WarSim.new(777)
	_tick_until(ws, 80, HOT_CTX, true)
	assert_int(ws.news().size()).is_greater(0)
	var rum := ws.rumours()
	assert_bool(rum.any(func(l: String) -> bool: return l.contains(WarSim.display_name(ws.enemy_id())))).is_true()


func test_serialise_roundtrip() -> void:
	WorldGen.setup(2024)
	var ws := WarSim.new(777)
	_tick_until(ws, 80, HOT_CTX, true)
	ws.tick_day(1000, HOT_CTX)
	var copy := WarSim.new(1)
	copy.deserialize(ws.serialize())
	assert_bool(copy.is_at_war()).is_equal(ws.is_at_war())
	assert_str(copy.enemy_id()).is_equal(ws.enemy_id())
	assert_str(JSON.stringify(copy.serialize())).is_equal(JSON.stringify(ws.serialize()))


# --- war3: rarer, reasoned wars ---------------------------------------------------------------------------------

const ONGUR := "ongur_khanate"


func test_tension_alone_never_declares_war_without_a_casus_belli() -> void:
	WorldGen.setup(2024)
	var ws := WarSim.new(5)
	ws.add_tension(ONGUR, 100.0)
	assert_bool(ws.has_casus_belli(ONGUR)).is_false()
	for d in 400:
		ws.tick_day(d, COLD_CTX)
		# natural reasons may arrive on their own; while none exists, no war
		if ws.is_at_war():
			assert_bool(ws.war["cb"].is_empty()).is_false()    # every war names its cause
			return
	assert_float(ws.tension_of(ONGUR)).is_less(WarSim.TENSION_WAR_THRESHOLD + 0.001 + 20.0)


func test_no_war_while_there_is_no_reason_at_all() -> void:
	WorldGen.setup(2024)
	var ws := WarSim.new(5)
	# block every natural source: rift calm, no feuds, and strip any reason each day
	for d in 300:
		ws.tick_day(d, COLD_CTX)
		for id in WarSim.WAR_CANDIDATES:
			ws.cbs[id] = []
			ws.add_tension(id, 30.0)
		assert_bool(ws.is_at_war()).is_false()
	assert_float(ws.tension_of(ONGUR)).is_less_equal(100.0)


func test_a_casus_belli_with_high_tension_declares_war_and_names_the_cause() -> void:
	WorldGen.setup(2024)
	var ws := WarSim.new(9)
	ws.offer_cb(ONGUR, "claim", "Ongur claims the lands around Stonewatch by an old charter.", 0, "enemy")
	ws.add_tension(ONGUR, 100.0)
	var line := ""
	for d in 60:
		for l in ws.tick_day(d, COLD_CTX):
			if l.begins_with("War:"):
				line = l
		if ws.is_at_war():
			break
	assert_bool(ws.is_at_war()).is_true()
	assert_str(line).contains("Cause:")
	assert_str(line).contains("Stonewatch")
	assert_str(String(ws.war["cb"]["kind"])).is_equal("claim")
	assert_str(String(ws.war["goal"])).is_equal("land")
	assert_str(String(ws.war["aggressor"])).is_equal(ONGUR)
	assert_bool(ws.news(10).any(func(l: String) -> bool: return l.contains("Grievance with Ongur"))).is_true()


func test_every_casus_belli_kind_is_described_and_expires() -> void:
	WorldGen.setup(2024)
	var ws := WarSim.new(1)
	for kind in WarSim.CB_KINDS:
		var rec := ws.offer_cb(ONGUR, kind, "reason %s" % kind, 10)
		assert_bool(rec.is_empty()).is_false()
	assert_int(ws.casus_belli(ONGUR).size()).is_equal(WarSim.CB_MAX)    # bounded
	ws.tick_day(10 + 600, COLD_CTX)
	assert_int(ws.casus_belli(ONGUR).size()).is_less(WarSim.CB_MAX)     # the old ones lapse


func test_truce_blocks_redeclaration_until_it_ends() -> void:
	WorldGen.setup(2024)
	var ws := WarSim.new(777)
	var day := _tick_until(ws, 80, HOT_CTX, true)
	var ended := _tick_until(ws, 400, HOT_CTX, false)
	assert_int(ended).is_greater(day)
	var id: String = WarSim.WAR_CANDIDATES[0]
	var enemy: String = String(ws.last_treaty["enemy"])
	assert_bool(ws.under_truce(enemy, ended)).is_true()
	assert_int(ws.truce_days_left(enemy, ended)).is_greater(100)
	# hot as can be, with fresh reasons: still no war until the truce is over
	var d := ended + 1
	var left := ws.truce_days_left(enemy, d)
	for i in left - 1:
		ws.offer_cb(enemy, "claim", "again", d + i, "caldrenn")
		ws.add_tension(enemy, 100.0)
		ws.tick_day(d + i, HOT_CTX)
		if ws.is_at_war():
			assert_str(ws.enemy_id()).is_not_equal(enemy)   # the other neighbour may still fight
			return
	assert_bool(ws.under_truce(enemy, d + left - 1)).is_true()
	assert_str(id).is_not_empty()


func test_breaking_a_truce_hands_the_other_side_a_casus_belli() -> void:
	WorldGen.setup(2024)
	var ws := WarSim.new(777)
	_tick_until(ws, 80, HOT_CTX, true)
	var ended := _tick_until(ws, 400, HOT_CTX, false)
	var enemy := String(ws.last_treaty["enemy"])
	assert_bool(ws.break_truce(enemy, "caldrenn", ended)).is_true()
	assert_bool(ws.under_truce(enemy, ended)).is_false()
	assert_bool(ws.has_cb_kind(enemy, "broken_treaty")).is_true()
	assert_bool(ws.break_truce(enemy, "caldrenn", ended)).is_false()    # nothing left to break


func test_war_weariness_grows_and_ends_the_war_with_terms() -> void:
	WorldGen.setup(2024)
	var ws := WarSim.new(777)
	_tick_until(ws, 80, HOT_CTX, true)
	var e0 := ws.exhaustion()
	ws.tick_day(ws._day + 1, HOT_CTX)
	assert_float(ws.exhaustion()).is_greater(e0)
	assert_float(ws.enemy_exhaustion()).is_greater(0.0)
	var ended := _tick_until(ws, 400, HOT_CTX, false)
	assert_int(ended).is_greater(0)
	var t: Dictionary = ws.last_treaty
	for k in ["winner", "goal", "land", "tribute", "hostages", "marriage", "truce_days", "text", "duration"]:
		assert_bool(t.has(k)).is_true()
	assert_int(int(t["duration"])).is_between(WarSim.MIN_WAR_DAYS, WarSim.MAX_WAR_DAYS)
	assert_str(ws.chronicle[-1]).contains("Treaty of")


func test_peace_terms_follow_the_war_goal_and_the_winner() -> void:
	WorldGen.setup(2024)
	var cases := {"land": "land", "tribute": "tribute", "hostages": "hostages", "marriage": "marriage"}
	for goal in cases:
		var ws := WarSim.new(777)
		_tick_until(ws, 80, HOT_CTX, true)
		ws.set_goal(goal)
		for f: Dictionary in ws.war["front"]:
			f["control"] = 0.9      # the crown holds the field
		var t := ws.propose_terms()
		assert_str(String(t["winner"])).is_equal("caldrenn")
		match goal:
			"land":
				assert_str(String(t["land"])).is_not_empty()
			"tribute":
				assert_int(int(t["tribute"])).is_greater(0)
			"hostages":
				assert_int((t["hostages"] as Array).size()).is_greater(0)
			"marriage":
				assert_bool((t["marriage"] as Dictionary).is_empty()).is_false()
		# and a beaten crown pays instead
		for f2: Dictionary in ws.war["front"]:
			f2["control"] = 0.1
		assert_str(String(ws.propose_terms()["winner"])).is_equal("enemy")
	var dr := WarSim.new(777)
	_tick_until(dr, 80, HOT_CTX, true)
	for f3: Dictionary in dr.war["front"]:
		f3["control"] = 0.5
	dr.war["exhaustion"] = 0.5
	dr.war["enemy_exhaustion"] = 0.5
	assert_str(String(dr.propose_terms()["winner"])).is_equal("draw")


func test_hostages_are_held_then_released_after_the_truce() -> void:
	WorldGen.setup(2024)
	var ws := WarSim.new(777)
	_tick_until(ws, 80, HOT_CTX, true)
	ws.set_goal("hostages")
	for f: Dictionary in ws.war["front"]:
		f["control"] = 0.9
	ws.conclude_peace(ws._day + 30)
	assert_int(ws.hostages.size()).is_greater(0)
	assert_str(String(ws.diplomacy(String(ws.last_treaty["enemy"]))["state"])).is_equal("truce")
	ws.tick_day(ws._day + 3000, COLD_CTX)
	assert_int(ws.hostages.size()).is_equal(0)


func test_war_frequency_and_length_over_a_long_run_hit_the_target_band() -> void:
	WorldGen.setup(2024)
	var years := 16
	var wars := 0
	var war_days := 0
	var seeds := 8
	var longest := 0
	var shortest := 9999
	for sd in seeds:
		var ws := WarSim.new(100 + sd * 37)
		var feud := 1
		var start := -1
		for d in years * 360:
			if d % 40 == 0:
				feud = clampi(feud + (sd + d / 40) % 3 - 1, 0, 4)
			var was := ws.is_at_war()
			ws.tick_day(d, {"feud_count": feud, "rift_instability": 0.15, "season": "spring"})
			if ws.is_at_war():
				war_days += 1
				if not was:
					wars += 1
					start = d
			elif was:
				longest = maxi(longest, d - start)
				shortest = mini(shortest, d - start)
	var per_year := float(wars) / float(years * seeds)
	var share := float(war_days) / float(years * 360 * seeds)
	print("war frequency: %.2f wars/year, %.1f%% of time at war, %d-%d days" % [per_year, share * 100.0, shortest, longest])
	assert_float(per_year).is_between(0.25, 1.0)          # about one war every 1-3 years
	assert_float(share).is_less(0.2)                     # was 0.31
	assert_int(shortest).is_greater_equal(WarSim.MIN_WAR_DAYS)   # weeks ...
	assert_int(longest).is_less_equal(WarSim.MAX_WAR_DAYS)       # ... to months


func test_long_peace_between_wars_is_common() -> void:
	WorldGen.setup(2024)
	var gaps: Array = []
	for sd in 6:
		var ws := WarSim.new(300 + sd)
		var last_end := 0
		var was := false
		for d in 14 * 360:
			ws.tick_day(d, {"feud_count": 1, "rift_instability": 0.1, "season": "spring"})
			if ws.is_at_war() and not was:
				gaps.append(d - last_end)
			if not ws.is_at_war() and was:
				last_end = d
			was = ws.is_at_war()
	gaps.sort()
	assert_int(gaps.size()).is_greater(3)
	assert_int(gaps[gaps.size() / 2]).is_greater(200)       # median peace: most of a year or more
	assert_int(gaps[0]).is_greater(WarSim.TRUCE_DAYS.x - 1)   # never inside a truce


func test_serialise_round_trip_keeps_reasons_truce_hostages_and_acts() -> void:
	WorldGen.setup(2024)
	var ws := WarSim.new(777)
	_tick_until(ws, 80, HOT_CTX, true)
	ws.note_act("scout_front", 40, "You scouted.")
	ws.guard_settlement("Ashford", 99)
	ws.offer_cb(ONGUR, "insult", "An envoy insulted House Varrick.", 50)
	ws.set_goal("hostages")
	for f: Dictionary in ws.war["front"]:
		f["control"] = 0.9
	ws.conclude_peace(ws._day + 30)
	ws.offer_cb(ONGUR, "feud", "A feud.", 200)
	var json := JSON.stringify(ws.serialize())
	var copy := WarSim.new(1)
	copy.deserialize(JSON.parse_string(json))
	assert_str(JSON.stringify(copy.serialize())).is_equal(json)
	assert_bool(copy.has_cb_kind(ONGUR, "feud") or copy.casus_belli(ONGUR).is_empty() == false).is_true()
	assert_int(copy.act_days.get("scout_front", -1)).is_equal(40)
	assert_int(copy.hostages.size()).is_equal(ws.hostages.size())
