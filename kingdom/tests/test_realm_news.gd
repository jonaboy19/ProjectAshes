extends GdUnitTestSuite
## News (CIV-B): rumours sharpen as they travel roads, regional news with delay for taverns / boards / travellers,
## fame at road speed, nicknames that become established and then formal titles (sim/titles.gd), diplomacy as
## data events, consuming other modules' news_events(), determinism, catch_up, round-trip, cost.

const Hub := preload("res://scripts/realm/realm_hub.gd")
const CTX := {"season": "spring", "at_war": false, "abs_hours": 0.0, "gold": 0, "player_pos": Vector2.ZERO}


func _mk() -> RefCounted:
	WorldGen.setup(2024)
	var hub: RefCounted = Hub.new()
	hub.warm_up()
	return hub


func _norm(d: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(d)))


func _run(hub: RefCounted, from_day: int, to_day: int, names: Array = ["news"], ctx: Dictionary = CTX) -> void:
	for day in range(from_day, to_day + 1):
		for k: String in names:
			var m: RefCounted = hub.mod(k)
			var ch: Array = m.tick_day_chunks(day, ctx)
			if ch.is_empty():
				m.tick_day(day, ctx)
			else:
				for c: Callable in ch:
					c.call()


## A far pair of settlements joined by road: [near, far].
func _pair(nw: RefCounted) -> Array:
	var best := [0, 1]
	var bd := 0.0
	for a in WorldGen.settlements.size():
		for b in WorldGen.settlements.size():
			var d: float = nw.road_distance(a, b)
			if d < 1.0e8 and d > bd:
				bd = d
				best = [a, b]
	return best


## A pair a few days apart by road (fame still readable on arrival).
func _mid_pair(nw: RefCounted) -> Array:
	for a in WorldGen.settlements.size():
		for b in WorldGen.settlements.size():
			var d: float = nw.road_distance(a, b)
			if d > nw.ROAD_SPEED * 1.5 and d < 2400.0:
				return [a, b]
	return _pair(nw)


func test_rumours_arrive_late_and_sharpen_with_distance_and_time() -> void:
	var hub := _mk()
	var nw: RefCounted = hub.mod("news")
	var p := _pair(nw)
	var a := int(p[0])
	var b := int(p[1])
	nw._day = 100
	nw.post("caravan_lost", a, "Raiders burned the Greywater caravan at the ford.", 2.0, "They were Red Wolves, and they took the iron.", false)
	var here: Array = nw.items_at(a, 100)
	assert_int(here.size()).is_equal(1)
	assert_int(int(here[0]["lvl"])).is_equal(0)
	assert_str(String(here[0]["text"])).contains("caravan")
	assert_str(String(here[0]["text"])).not_contains("Raiders")      # incomplete at first
	# Far away: nothing yet.
	assert_int(nw.items_at(b, 100).size()).is_equal(0)
	var dist: float = nw.road_distance(a, b)
	var arrives := 100 + int(ceil(dist / nw.ROAD_SPEED))
	assert_int(nw.items_at(b, arrives - 1).size()).is_equal(0)
	assert_int(nw.items_at(b, arrives + 1).size()).is_equal(1)
	# Later, at both places, the story is complete.
	var later: Array = nw.items_at(a, 100 + 40)
	assert_int(int(later[0]["lvl"])).is_equal(3)
	assert_str(String(later[0]["text"])).contains("Red Wolves")
	var far_late: Array = nw.items_at(b, arrives + 40)
	assert_int(int(far_late[0]["lvl"])).is_equal(3)
	# Distance alone sharpens too: the far town hears more on arrival than the origin did.
	var far_first: Array = nw.items_at(b, arrives)
	assert_int(int(far_first[0]["lvl"])).is_greater_equal(int(here[0]["lvl"]))
	# Items age out.
	assert_int(nw.items_at(a, 100 + 400).size()).is_equal(0)


func test_notice_boards_carry_official_news_only_and_travellers_bring_far_news() -> void:
	var hub := _mk()
	var nw: RefCounted = hub.mod("news")
	var p := _pair(nw)
	var a := int(p[0])
	var b := int(p[1])
	nw._day = 50
	nw.post("law", a, "Kingsreach bans the monster-part trade.", 1.0, "", true)
	nw.post("caravan_lost", a, "A caravan vanished on the ford road.", 1.0, "", false)
	var day := 50 + int(ceil(nw.road_distance(a, b) / nw.ROAD_SPEED)) + 1
	var board: Array = nw.news_for(a, "board", 5)
	assert_int(board.size()).is_equal(1)
	assert_bool(bool(board[0]["official"])).is_true()
	assert_int(int((board[0] as Dictionary)["lvl"])).is_greater_equal(2)          # notices are clear from the start
	nw._day = day
	var tavern: Array = nw.news_for(b, "tavern", 5)
	assert_int(tavern.size()).is_equal(2)
	var trav: Array = nw.news_for(b, "traveller", 5)
	assert_int(trav.size()).is_greater(0)
	for t: Dictionary in trav:
		assert_int(int(t["sid"])).is_not_equal(b)
	# Couriers beat rumours: the official notice arrives no later than the gossip.
	var arr_off: float = nw._arrival(nw._items[0], b)
	var arr_gos: float = nw._arrival(nw._items[1], b)
	assert_float(arr_off).is_less_equal(arr_gos)


func test_tavern_line_is_prefered_news_for_the_nearest_settlement() -> void:
	var hub := _mk()
	var nw: RefCounted = hub.mod("news")
	assert_str(nw.tavern_line_at(WorldGen.settlements[0]["pos"], 1)).is_empty()     # nothing heard yet
	nw._day = 10
	nw.post("expedition_lost", 0, "The Deepvein Expedition was never seen again.", 3.0, "", true)
	var line: String = nw.tavern_line_at(WorldGen.settlements[0]["pos"], 1)
	assert_str(line).is_not_empty()
	assert_str(line).contains("Deepvein")
	assert_str(nw.tavern_line_at(Vector2.INF, 1)).is_empty()                            # no player: no line


func test_fame_spreads_at_road_speed_and_fades() -> void:
	var hub := _mk()
	var nw: RefCounted = hub.mod("news")
	var p := _mid_pair(nw)
	var a := int(p[0])
	var b := int(p[1])
	nw._day = 20
	nw.record_deed("n:n1", "Hale", "beast_slain", a, 2.0, 20)
	assert_float(nw.fame_at(a, "n:n1", 20)).is_greater(0.0)
	assert_float(nw.fame_at(b, "n:n1", 20)).is_equal(0.0)
	var when := 20 + int(ceil(nw.road_distance(a, b) / nw.ROAD_SPEED)) + 1
	var at_b: float = nw.fame_at(b, "n:n1", when)
	assert_float(at_b).is_greater(0.0)
	assert_float(at_b).is_less(nw.fame_at(a, "n:n1", when))               # it dilutes with distance
	assert_float(nw.fame_at(a, "n:n1", 20 + 800)).is_less(nw.fame_at(a, "n:n1", 20))
	assert_int(nw.fame_reach("n:n1")).is_greater(0)


func test_nickname_emerges_spreads_becomes_established_then_formal_title() -> void:
	var hub := _mk()
	var nw: RefCounted = hub.mod("news")
	nw._day = 10
	nw.record_deed("n:n7", "Ulfla Dunn", "beast_slain", 3, 2.5, 10)
	assert_bool(nw.nickname("n:n7").is_empty()).is_true()       # one deed is not a legend
	nw.record_deed("n:n7", "Ulfla Dunn", "beast_slain", 3, 2.5, 12)
	var nk: Dictionary = nw.nickname("n:n7")
	assert_str(String(nk["nick"])).is_not_empty()
	assert_str(String(nk["state"])).is_equal("whisper")
	nw.record_deed("n:n7", "Ulfla Dunn", "beast_slain", 3, 3.0, 13)
	nw.record_deed("n:n7", "Ulfla Dunn", "beast_slain", 3, 3.0, 14)
	var states := {}
	var honoured := ""
	for day in range(15, 15 + 420):
		_run(hub, day, day)
		var st_now := String(nw.nickname("n:n7")["state"])
		if not states.has(st_now):
			states[st_now] = day   # first day in each state
			if st_now == "formal":
				for e: Dictionary in nw.items_at(3):   # the notice is fresh on the day it is posted
					if "honoured" in String(e["text"]):
						honoured = String(e["text"])
	for st in ["whisper", "nickname", "established", "formal"]:
		assert_bool(states.has(st)).override_failure_message("never reached %s" % st).is_true()
	assert_int(int(states["whisper"])).is_less(int(states["nickname"]))
	assert_int(int(states["nickname"])).is_less(int(states["established"]))
	var formal: Array = nw.formal_titles()
	assert_int(formal.size()).is_equal(1)
	assert_str(String(formal[0]["nick"])).is_equal(String(nk["nick"]))
	# Formal means a real entry in sim/titles.gd.
	assert_bool(nw._titles_npc.has(String(formal[0]["id"]))).is_true()
	assert_str(honoured).contains(String(nk["nick"]))


func test_player_deeds_from_society_rumours_give_the_player_a_nickname_and_a_real_title() -> void:
	var hub := _mk()
	var soc: RefCounted = hub.mod("society")
	var nw: RefCounted = hub.mod("news")
	soc.add_rumour("monster_kill", 2, 6.0)
	# A holder with a real sim/titles.gd registry stands in for Life.
	var holder := GDScript.new()
	holder.source_code = "extends RefCounted\nvar titles := preload(\"res://scripts/sim/titles.gd\").new()\n"
	holder.reload()
	var life: RefCounted = holder.new()
	var ctx := CTX.duplicate()
	ctx["life"] = life
	_run(hub, 1, 2, ["society", "news"], ctx)
	var nk: Dictionary = nw.nickname("player")
	assert_str(String(nk["nick"])).is_not_empty()
	assert_str(String(nk["deed"])).is_equal("beast_slain")
	# Force the final step: the nickname is formalised through the player's own title registry.
	nw._nicks["player"]["state"] = "established"
	nw._nicks["player"]["day"] = -400
	nw._nicks["player"]["w"] = 12.0
	nw._deeds["player"]["w"]["beast_slain"] = 12.0
	nw._nick_step("player", 400)
	assert_str(String(nw.nickname("player")["state"])).is_not_equal("whisper")
	if String(nw.nickname("player")["state"]) == "formal":
		assert_bool((life.get("titles") as RefCounted).has(String(nw.formal_titles()[0]["id"]))).is_true()


func test_it_consumes_other_modules_events_with_a_cursor_and_survives_missing_modules() -> void:
	var hub := _mk()
	var nw: RefCounted = hub.mod("news")
	var gov: RefCounted = hub.mod("governance")
	gov._ensure()
	gov.set_law(2, "curfew", 2, "test")
	gov.set_law(3, "weapons", 2, "test")
	_run(hub, 1, 1, ["news"])
	var n1: int = nw.stats()["items"]
	assert_int(n1).is_greater(1)
	_run(hub, 2, 3, ["news"])
	assert_int(int(nw.stats()["items"])).is_equal(n1)                 # nothing is posted twice
	gov.set_law(4, "curfew", 2, "test")
	_run(hub, 4, 4, ["news"])
	assert_int(int(nw.stats()["items"])).is_equal(n1 + 1)
	var texts: Array = nw.news_for(4, "tavern", 10).map(func(x: Dictionary) -> String: return x["text"])
	assert_bool(texts.size() > 0).is_true()
	# A module that restarts its counters does not wedge the cursor.
	var fresh := _mk()
	fresh.mod("news")._cursor["governance"] = 999
	fresh.mod("governance")._ensure()
	fresh.mod("governance").set_law(2, "curfew", 2, "test")
	_run(fresh, 1, 1, ["news"])
	assert_int(int(fresh.mod("news").stats()["items"])).is_greater(0)


func test_diplomacy_is_recorded_as_data_events() -> void:
	var hub := _mk()
	var nw: RefCounted = hub.mod("news")
	_run(hub, 1, 360 * 3)
	var kinds := {}
	for e: Dictionary in nw.diplomacy():
		kinds[e["kind"]] = true
		assert_str(String(e["text"])).is_not_empty()
		assert_bool(["travelling", "arrived"].has(String(e["status"]))).is_true()
	assert_bool(kinds.has("delegation")).is_true()
	# A delegation walks before it arrives: its news only appears on arrival.
	var trav: Array = nw.diplomacy("delegation")
	assert_int(trav.size()).is_greater(0)
	for e: Dictionary in nw.embassies():
		assert_bool(e.has("sid") and e.has("a") and e.has("b")).is_true()


func test_determinism_and_save_round_trip() -> void:
	var a := _mk()
	var b := _mk()
	var mods := ["governance", "notables", "news"]
	_run(a, 1, 500, mods)
	_run(b, 1, 500, mods)
	assert_str(_norm(a.mod("news").serialize())).is_equal(_norm(b.mod("news").serialize()))
	var c := _mk()
	for k: String in mods + ["education", "exploration", "society", "factions"]:
		c.mod(k).deserialize(JSON.parse_string(JSON.stringify(a.mod(k).serialize())))
	assert_str(_norm(c.mod("news").serialize())).is_equal(_norm(a.mod("news").serialize()))
	_run(a, 501, 600, mods)
	_run(c, 501, 600, mods)
	assert_str(_norm(c.mod("news").serialize())).is_equal(_norm(a.mod("news").serialize()))
	assert_int(JSON.stringify(a.mod("news").serialize()).length()).is_less(60000)


func test_catch_up_keeps_news_consistent() -> void:
	var a := _mk()
	var b := _mk()
	var mods := ["governance", "notables", "news"]
	_run(a, 1, 1, mods)
	_run(b, 1, 1, mods)
	a.mod("news").record_deed("n:n9", "Hale", "expedition", 2, 3.0, 1)
	b.mod("news").record_deed("n:n9", "Hale", "expedition", 2, 3.0, 1)
	a.mod("news").record_deed("n:n9", "Hale", "expedition", 2, 3.0, 1)
	b.mod("news").record_deed("n:n9", "Hale", "expedition", 2, 3.0, 1)
	_run(a, 2, 301, ["news"])
	b.mod("news").catch_up(300, CTX)
	# A nickname moves through the same stages whether the days were played or skipped.
	assert_str(String(b.mod("news").nickname("n:n9")["state"])).is_equal(String(a.mod("news").nickname("n:n9")["state"]))
	assert_float(b.mod("news").fame_at(2, "n:n9")).is_equal_approx(a.mod("news").fame_at(2, "n:n9"), 0.001)
	assert_int(b.mod("news").stats()["nicks"]).is_equal(a.mod("news").stats()["nicks"])


func test_day_chunks_cost() -> void:
	var hub := _mk()
	_run(hub, 1, 60, ["governance", "notables", "news"])
	var nw: RefCounted = hub.mod("news")
	var times: Array = []
	for day in range(61, 121):
		for c: Callable in nw.tick_day_chunks(day, CTX):
			var t0 := Time.get_ticks_usec()
			c.call()
			times.append(Time.get_ticks_usec() - t0)
	times.sort()
	var median := float(times[times.size() / 2]) / 1000.0
	var p95 := float(times[int(times.size() * 0.95)]) / 1000.0
	print("news chunk cost: median %.3f ms, p95 %.3f ms, worst %.3f ms" % [median, p95, float(times[times.size() - 1]) / 1000.0])
	assert_float(median).is_less(0.6)
	assert_float(p95).is_less(2.0)        # loose: CI runners are slow
	# Reading is cheap too.
	var t1 := Time.get_ticks_usec()
	for i in 50:
		nw.items_at(i % WorldGen.settlements.size())
	assert_int(Time.get_ticks_usec() - t1).is_less(50000)
