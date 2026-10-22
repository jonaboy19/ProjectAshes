extends GdUnitTestSuite
## The Soldier career as real mechanics (F11): enlisting with a kit, a post and an officer, muster attendance, duties
## generated from data into library quests, merit and promotion with a service-time gate, weekly pay and docking,
## discipline (crimes, demotion, desertion, leave), the squad at corporal and above, and saves.

const Hub := preload("res://scripts/realm/realm_hub.gd")
const Mastery := preload("res://scripts/sim/mastery.gd")
const Biography := preload("res://scripts/sim/biography.gd")
const Career := preload("res://scripts/sim/soldier_career.gd")
const SoldierUI := preload("res://scripts/ui/soldier_ui.gd")
const CareerLadders := preload("res://scripts/sim/career_ladders.gd")
const Equipment := preload("res://scripts/sim/equipment.gd")
const NpcFighter := preload("res://scripts/combat/npc_fighter.gd")

static var _world_ready := false
var _bus: QuestBus
var _mods: Array = []


## A stand-in for Life: the pack and the equipment system the kit is issued through.
class StubLife extends RefCounted:
	const Eq := preload("res://scripts/sim/equipment.gd")
	var equipment := Eq.new()
	var pack: Dictionary = {}

	func give(item: String, amount := 1) -> void:
		pack[item] = int(pack.get(item, 0)) + amount

	func take(item: String, amount := 1) -> bool:
		if int(pack.get(item, 0)) < amount:
			return false
		pack[item] = int(pack[item]) - amount
		return true

	func count(item: String) -> int:
		return int(pack.get(item, 0))


func before_test() -> void:
	_bus = QuestBus.new()
	_mods = []


func after_test() -> void:
	for m: RefCounted in _mods:
		m.release()


func _norm(d: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(d)))


## A hub with the soldier module wired to private mastery, biography, bus and kit stub; enlisted on day 10.
func _sol(enlist := true, day := 10) -> RefCounted:
	if not _world_ready:
		WorldGen.setup(2024)
		_world_ready = true
	var hub: RefCounted = Hub.new()
	var m: RefCounted = hub.mod("soldier")
	m.mastery_ref = Mastery.new()
	m.bio_ref = Biography.new()
	m.gold_ref = 1000
	m.sync_life = false
	m.bus_ref = _bus
	m.life_ref = StubLife.new()
	_mods.append(m)
	if enlist:
		var r: Dictionary = m.enlist(day, "captain")
		assert_bool(r["ok"]).is_true()
	return m


func _at_post(m: RefCounted) -> Vector2:
	return m.post_pos() + Vector2(2, 1)


## Force a rank without ceremony (rank, merit and the squad that goes with it).
func _set_rank(m: RefCounted, rk: int, day: int, merit := -1.0) -> void:
	m.rank = rk
	m.since_day = day
	m.merit = merit if merit >= 0.0 else float(Career.rank_def(rk)["merit"])
	m.squad.set_rank(rk, day, 1)


## Answer muster at the post on `day`, then let the day pass so it is settled.
func _muster_day(m: RefCounted, day: int) -> void:
	m.muster_attend(day, 6.5, _at_post(m))


## Finish today's duty by feeding the bus the events its objectives want.
func _finish_duty(m: RefCounted, d: Dictionary) -> void:
	var stage: Dictionary = (d["def"]["stages"] as Array)[0]
	for o: Dictionary in stage["objectives"]:
		match String(o["type"]):
			"goto":
				var p: Array = o["pos"]
				_bus.emit_event(&"position", {"x": float(p[0]), "y": float(p[1])})
			"wait", "protect":
				for h in int(ceil(float(o["hours"]))):
					_bus.emit_event(&"hours", {"amount": 1.0, "hour": float((22 + h) % 24)})
			"escort":
				_bus.emit_event(&"arrive", {"actor": o["actor"], "place": o["place"]})
			"kill":
				_bus.emit_event(&"kill", {"target": o["target"], "place": o["place"], "amount": int(o["count"])})
			"deliver":
				_bus.emit_event(&"deliver", {"item": o["item"], "to": o["to"], "amount": 1})
			"investigate":
				for c: String in o["clues"]:
					_bus.emit_event(&"interact", {"id": c})


# ---------------------------------------------------------------- data and enlisting

func test_five_ranks_rise_in_merit_time_wage_and_squad() -> void:
	var ids: Array = []
	for i in Career.rank_count():
		ids.append(Career.rank_id(i))
	assert_array(ids).is_equal(["recruit", "private", "corporal", "sergeant", "lieutenant"])
	for i in range(1, Career.rank_count()):
		assert_int(int(Career.rank_def(i)["merit"])).is_greater(int(Career.rank_def(i - 1)["merit"]))
		assert_int(Career.weekly_wage(i)).is_greater(Career.weekly_wage(i - 1))
		assert_int(int(Career.rank_def(i)["min_days"])).is_greater_equal(int(Career.rank_def(i - 1)["min_days"]))
		assert_int(Career.squad_size(i)).is_greater_equal(Career.squad_size(i - 1))
	assert_int(Career.squad_size(1)).is_equal(0)
	assert_int(Career.squad_size(2)).is_between(2, 4)
	assert_int(Career.squad_size(4)).is_equal(4)


func test_ranks_map_onto_the_shared_soldier_ladder_and_troop_caps() -> void:
	for i in Career.rank_count():
		assert_int(CareerLadders.rank_index("soldier", Career.ladder_id(i))).is_greater_equal(0)
		assert_int(Career.troops_for_rank(i)).is_equal(CareerLadders.troops_for_rank(Career.ladder_id(i)))
	assert_int(Career.troops_for_rank(4)).is_greater(Career.troops_for_rank(1))


func test_enlisting_gives_a_post_an_officer_and_the_lowest_rank() -> void:
	var m := _sol(false)
	assert_str(m.enlist_refusal(10)).is_equal("")
	var r: Dictionary = m.enlist(10, "guard_post")
	assert_bool(r["ok"]).is_true()
	assert_bool(m.active).is_true()
	assert_str(m.rank_id()).is_equal("recruit")
	assert_str(String(m.post["name"])).is_not_empty()
	assert_str(String(m.officer["name"])).is_not_empty()
	assert_str(String(m.officer["title"])).is_not_empty()
	assert_int(m.weekly_wage()).is_equal(Career.weekly_wage(0))
	assert_str(String(m.enlist(11)["reason"])).contains("already")


func test_the_outpost_near_thornfield_is_data_and_the_town_watch_is_the_fallback() -> void:
	var data_posts: Dictionary = Career.data()["posts"]
	assert_str(String(data_posts["outposts"][0]["settlement"])).is_equal("Thornfield")
	var with_thornfield: Array = [{"name": "Ashford", "pos": Vector2(0, 0), "radius": 50.0}, {"name": "Thornfield", "pos": Vector2(500, 300), "radius": 60.0}]
	var p: Dictionary = Career.resolve_post(with_thornfield)
	assert_str(String(p["kind"])).is_equal("outpost")
	assert_int(int(p["sid"])).is_equal(1)
	assert_float((p["pos"] as Vector2).distance_to(Vector2(500, 300))).is_greater(0.0)
	var without: Array = [{"name": "Ashford", "pos": Vector2(10, 20), "radius": 50.0}]
	var w: Dictionary = Career.resolve_post(without)
	assert_str(String(w["kind"])).is_equal("watch")
	assert_str(String(w["id"])).is_equal("town_watch")
	assert_float((w["pos"] as Vector2).distance_to(Vector2(10, 20))).is_less(1.0)
	# The module uses whichever the world offers.
	var m := _sol(false)
	m.settlements_ref = without
	m.enlist(5)
	assert_str(String(m.post["kind"])).is_equal("watch")


func test_the_kit_is_issued_and_worn_through_the_equipment_system() -> void:
	var m := _sol()
	var life: StubLife = m.life_ref
	var kit := Career.kit_for(0)
	assert_int(kit.size()).is_greater_equal(4)
	for slot: String in kit:
		assert_bool(Equipment.item_info(String(kit[slot])).is_empty()).override_failure_message("unknown item %s" % kit[slot]).is_false()
		assert_str(life.equipment.item_in(slot)).is_equal(String(kit[slot]))
	assert_str(life.equipment.item_in("main_hand")).is_equal("bronze_spear")


func test_a_promotion_issues_the_better_kit() -> void:
	var m := _sol()
	var life: StubLife = m.life_ref
	_set_rank(m, 1, 10, 20.0)
	m.merit = 60.0
	m.since_day = 0
	var pr: Dictionary = m.petition(30)
	assert_bool(pr["ok"]).is_true()
	assert_str(m.rank_id()).is_equal("corporal")
	assert_str(life.equipment.item_in("body")).is_equal(String(Career.kit_for(2)["body"]))
	assert_str(life.equipment.item_in("body")).is_not_equal(String(Career.kit_for(0)["body"]))


func test_every_kit_item_in_every_rank_exists() -> void:
	for i in Career.rank_count():
		for slot: String in Career.kit_for(i):
			var id := String(Career.kit_for(i)[slot])
			assert_str(Equipment.slot_of(id)).override_failure_message("%s should be an item for slot %s" % [id, slot]).is_equal(slot)


# ---------------------------------------------------------------- muster

func test_muster_counts_only_at_the_post_inside_the_window_once_a_day() -> void:
	var m := _sol()
	assert_bool(m.muster_attend(11, 6.5, m.post_pos() + Vector2(400, 0))).is_false()
	assert_bool(m.muster_attend(11, 13.0, _at_post(m))).is_false()
	assert_bool(m.muster_attend(11, 6.5, _at_post(m))).is_true()
	assert_bool(m.attended_on(11)).is_true()
	assert_bool(m.muster_attend(11, 7.0, _at_post(m))).is_false()
	assert_int(m.stat("musters")).is_equal(1)
	assert_float(m.merit).is_equal(float(Career.muster()["attend_merit"]))


func test_the_hour_tick_takes_muster_from_the_player_position() -> void:
	var m := _sol()
	var day := int(WorldSim.day)
	m.enlisted_day = day - 5
	m.tick_hour(6, {"player_pos": m.post_pos() + Vector2(900, 900)})
	assert_bool(m.attended_on(day)).is_false()
	m.tick_hour(6, {"player_pos": _at_post(m)})
	assert_bool(m.attended_on(day)).is_true()


func test_a_missed_muster_costs_merit_and_an_answered_one_resets_the_run() -> void:
	var m := _sol()
	m.merit = 10.0
	m.tick_day(12, {})        # settles day 11: never answered
	assert_int(m.missed_run).is_equal(1)
	assert_int(m.missed_week).is_equal(1)
	assert_float(m.merit).is_equal(10.0 + float(Career.muster()["miss_merit"]))
	_muster_day(m, 12)
	assert_int(m.missed_run).is_equal(0)
	m.tick_day(13, {})
	assert_int(m.missed_run).is_equal(0)
	assert_int(m.stat("missed_musters")).is_equal(1)


# ---------------------------------------------------------------- duty generation

func test_every_duty_kind_builds_a_valid_library_quest() -> void:
	var post := {"id": "p", "name": "the Post", "pos": Vector2(100, 100), "places": Career.data()["posts"]["outposts"][0]["places"]}
	var want := {"patrol": "goto", "guard_gate": "wait", "escort": "escort", "clear": "kill", "deliver_orders": "deliver", "investigate": "investigate"}
	for kind: String in Career.DUTY_KINDS:
		var r := RandomNumberGenerator.new()
		r.seed = 5
		var d: Dictionary = Career.gen_duty(kind, 3, post, r)
		assert_bool(d.is_empty()).override_failure_message(kind).is_false()
		var def := QuestDef.from_dict(d["def"])
		assert_int(def.validate().size()).override_failure_message("%s: %s" % [kind, def.validate()]).is_equal(0)
		var types: PackedStringArray = def.objective_types()
		assert_bool(types.has(String(want[kind]))).override_failure_message("%s has %s" % [kind, types]).is_true()
	assert_int(Career.DUTY_KINDS.size()).is_equal(6)


func test_a_patrol_is_a_sequence_of_waypoints_around_the_post() -> void:
	var m := _sol()
	var d: Dictionary = m.offer_duty(11, "patrol")
	var stage: Dictionary = d["def"]["stages"][0]
	assert_str(String(stage["mode"])).is_equal("sequence")
	assert_int((stage["objectives"] as Array).size()).is_equal(int(Career.duty_def("patrol")["waypoints"]))
	for o: Dictionary in stage["objectives"]:
		var p: Array = o["pos"]
		assert_float(Vector2(float(p[0]), float(p[1])).distance_to(m.post_pos())).is_less(120.0)


func test_the_gate_watch_is_waiting_through_the_night_and_protecting_the_gate() -> void:
	var m := _sol()
	var d: Dictionary = m.offer_duty(11, "guard_gate")
	var types := []
	for o: Dictionary in d["def"]["stages"][0]["objectives"]:
		types.append(String(o["type"]))
	assert_array(types).contains_exactly(["wait", "protect"])
	assert_bool(d["def"]["stages"][0]["objectives"][0].has("window")).is_true()


func test_duties_open_with_rank() -> void:
	assert_bool(Career.kinds_for(0).has("investigate")).is_false()
	assert_bool(Career.kinds_for(0).has("escort")).is_false()
	assert_bool(Career.kinds_for(1).has("clear")).is_true()
	assert_bool(Career.kinds_for(2).has("investigate")).is_true()
	assert_int(Career.kinds_for(4).size()).is_equal(6)
	for i in 30:
		var r := RandomNumberGenerator.new()
		r.seed = i
		assert_bool(Career.kinds_for(0).has(Career.pick_kind(r, 0))).is_true()


func test_todays_duty_is_deterministic_and_offered_once() -> void:
	var a := _sol()
	var b := _sol()
	var da: Dictionary = a.todays_duty(11)
	var db: Dictionary = b.todays_duty(11)
	assert_str(_norm(da["def"])).is_equal(_norm(db["def"]))
	assert_str(String(a.todays_duty(11)["id"])).is_equal(String(da["id"]))
	assert_str(String(da["state"])).is_equal("offered")


# ---------------------------------------------------------------- running duties

func test_every_duty_kind_can_be_taken_and_finished_for_merit_and_pay() -> void:
	for kind: String in Career.DUTY_KINDS:
		var m := _sol()
		_set_rank(m, 2, 0, 70.0)
		var d: Dictionary = m.offer_duty(11, kind)
		var acc: Dictionary = m.accept_duty(11)
		assert_bool(acc["ok"]).override_failure_message("%s: %s" % [kind, acc]).is_true()
		assert_int(m.duty_lines().size()).is_greater(0)
		_finish_duty(m, d)
		assert_str(String(m.duty["state"])).override_failure_message(kind).is_equal("done")
		assert_int(m.stat("duties")).is_equal(1)
		assert_int(m.stat(kind)).is_equal(1)
		assert_int(m.pending_gold).is_equal(int(Career.duty_def(kind)["gold"]))
		assert_float(m.merit).is_greater_equal(70.0 + float(Career.duty_def(kind)["merit"]))


func test_a_patrol_needs_the_waypoints_in_order() -> void:
	var m := _sol()
	var d: Dictionary = m.offer_duty(11, "patrol")
	m.accept_duty(11)
	var objs: Array = d["def"]["stages"][0]["objectives"]
	var last: Array = objs[objs.size() - 1]["pos"]
	_bus.emit_event(&"position", {"x": float(last[0]), "y": float(last[1])})     # the last waypoint first: nothing
	assert_str(String(m.duty["state"])).is_equal("active")
	_finish_duty(m, d)
	assert_str(String(m.duty["state"])).is_equal("done")
	assert_int(m.stat("patrols")).is_equal(1)


func test_kills_on_duty_earn_merit_up_to_a_cap_and_kills_off_duty_do_not() -> void:
	var m := _sol()
	_bus.emit_event(&"kill", {"target": "wolf", "amount": 3})
	assert_float(m.merit).is_equal(0.0)
	m.offer_duty(11, "clear")
	m.accept_duty(11)
	_bus.emit_event(&"kill", {"target": "rat", "place": "somewhere", "amount": 2})
	assert_float(m.merit).is_equal(2.0 * float(Career.data()["merit"]["kill"]))
	_bus.emit_event(&"kill", {"target": "rat", "amount": 50})
	assert_float(m.merit).is_equal(float(Career.data()["merit"]["kill_cap_per_duty"]) * float(Career.data()["merit"]["kill"]))
	assert_int(m.stat("kills")).is_equal(52)


func test_a_failed_duty_costs_merit_and_an_abandoned_one_too() -> void:
	var m := _sol()
	m.merit = 20.0
	m.offer_duty(11, "escort")
	m.accept_duty(11)
	var cart := "supply_cart"
	_bus.emit_event(&"died", {"actor": cart})
	assert_str(String(m.duty["state"])).is_equal("failed")
	assert_float(m.merit).is_equal(20.0 + float(Career.data()["merit"]["duty_failed"]))
	assert_int(m.stat("duties_failed")).is_equal(1)
	var m2 := _sol()
	m2.merit = 20.0
	m2.offer_duty(11, "patrol")
	m2.accept_duty(11)
	m2.abandon_duty(11)
	assert_float(m2.merit).is_equal(20.0 + float(Career.data()["merit"]["duty_abandoned"]))


func test_an_unfinished_duty_lapses_at_the_next_day() -> void:
	var m := _sol()
	m.offer_duty(11, "patrol")
	m.accept_duty(11)
	_muster_day(m, 12)
	m.tick_day(13, {})
	assert_int(m.stat("duties_abandoned")).is_equal(1)
	assert_int(int(m.todays_duty(13)["day"])).is_equal(13)


func test_on_leave_there_is_no_duty() -> void:
	var m := _sol()
	m.request_leave(11, 2)
	assert_bool(m.todays_duty(12).is_empty()).is_true()


# ---------------------------------------------------------------- merit and promotion

func test_promotion_needs_both_the_merit_and_the_service_time() -> void:
	var r1: Dictionary = Career.promotion(0, 25.0, 3)
	assert_bool(r1["eligible"]).is_false()
	assert_int((r1["missing"] as PackedStringArray).size()).is_equal(1)       # merit is met, time is not
	assert_bool(Career.promotion(0, 5.0, 30)["eligible"]).is_false()           # time is met, merit is not
	var both: Dictionary = Career.promotion(0, 25.0, 30)
	assert_bool(both["eligible"]).is_true()
	assert_str(String(both["next"]["title"])).is_equal("Private")
	assert_bool(Career.promotion(4, 9999.0, 9999)["eligible"]).is_false()      # nothing above lieutenant
	assert_bool((Career.promotion(4, 1.0, 1)["next"] as Dictionary).is_empty()).is_true()


func test_each_threshold_is_exact() -> void:
	for rk in range(0, Career.rank_count() - 1):
		var nxt := Career.rank_def(rk + 1)
		var need_m := float(nxt["merit"])
		var need_d := int(nxt["min_days"])
		assert_bool(Career.promotion(rk, need_m, need_d)["eligible"]).is_true()
		assert_bool(Career.promotion(rk, need_m - 1.0, need_d)["eligible"]).is_false()
		assert_bool(Career.promotion(rk, need_m, need_d - 1)["eligible"]).is_false()


func test_a_petition_refuses_until_ready_then_gives_the_ceremony_line() -> void:
	var m := _sol()
	m.merit = 100.0
	var no: Dictionary = m.petition(12)      # merit plenty, only 2 days served
	assert_bool(no["ok"]).is_false()
	assert_int((no["missing"] as PackedStringArray).size()).is_equal(1)
	var yes: Dictionary = m.petition(10 + int(Career.rank_def(1)["min_days"]))
	assert_bool(yes["ok"]).is_true()
	assert_str(m.rank_id()).is_equal("private")
	assert_str(String(yes["text"])).is_equal(String(Career.rank_def(1)["ceremony"]))
	assert_int(m.days_in_rank(10 + int(Career.rank_def(1)["min_days"]))).is_equal(0)
	assert_str(m.ladder_rank_id()).is_equal("soldier")


func test_the_daily_tick_promotes_when_merit_and_time_allow() -> void:
	var m := _sol()
	m.merit = 25.0
	_muster_day(m, 20)
	var out: Array = m.tick_day(21, {})
	assert_str(m.rank_id()).is_equal("private")
	assert_bool(out.any(func(l: Variant) -> bool: return String(l).contains("Private"))).is_true()


func test_merit_comes_from_duties_kills_commendations_and_attendance() -> void:
	var m := _sol()
	_muster_day(m, 11)
	assert_float(m.merit).is_equal(1.0)
	m.commend(11, "test")
	assert_float(m.merit).is_equal(1.0 + float(Career.data()["merit"]["commendation"]))
	assert_int(m.stat("commendations")).is_equal(1)
	var d: Dictionary = m.offer_duty(12, "deliver_orders")
	m.accept_duty(12)
	_finish_duty(m, d)
	assert_float(m.merit).is_greater(1.0 + float(Career.data()["merit"]["commendation"]) + float(Career.duty_def("deliver_orders")["merit"]) - 0.01)


func test_a_ladder_rank_is_written_to_the_biography_and_mastery_grows_with_duty() -> void:
	var m := _sol()
	var before: int = m.mastery_ref.level("soldiering")
	m.merit = 25.0
	for i in 8:
		m.mastery_ref.gain("soldiering", 1.0, i)
	assert_int(m.mastery_ref.level("soldiering")).is_greater(before)
	assert_bool(m.petition(40)["ok"]).is_true()
	assert_float(m.military_rep()).is_greater(0.0)


# ---------------------------------------------------------------- pay

func test_the_weekly_wage_follows_rank() -> void:
	var m := _sol()
	for rk in Career.rank_count():
		m.rank = rk
		m.missed_week = 0
		m.pending_gold = 0
		m.tick_week(3, {})
		assert_int(m.pending_gold).is_equal(Career.weekly_wage(rk))
	assert_int(m.take_pending_gold()).is_equal(Career.weekly_wage(4))
	assert_int(m.pending_gold).is_equal(0)


func test_missed_musters_dock_the_wage_and_the_week_resets() -> void:
	var m := _sol()
	m.missed_week = 2
	m.tick_week(3, {})
	var dock := float(Career.data()["pay"]["dock_per_missed_muster"]) * 2.0
	assert_int(m.pending_gold).is_equal(int(round(float(Career.weekly_wage(0)) * (1.0 - dock))))
	assert_int(m.pending_gold).is_less(Career.weekly_wage(0))
	assert_int(m.missed_week).is_equal(0)
	m.pending_gold = 0
	m.tick_week(4, {})
	assert_int(m.pending_gold).is_equal(Career.weekly_wage(0))
	assert_int(Career.pay_for_week(0, 99, false, false)).is_equal(0)


func test_leave_excuses_muster_and_pays_half() -> void:
	var m := _sol()
	var r: Dictionary = m.request_leave(11, 3)
	assert_bool(r["ok"]).is_true()
	assert_bool(m.is_on_leave(12)).is_true()
	m.tick_day(12, {})
	m.tick_day(13, {})
	assert_int(m.missed_run).is_equal(0)
	m.tick_week(2, {})
	assert_int(m.pending_gold).is_equal(int(round(float(Career.weekly_wage(0)) * float(Career.data()["pay"]["leave_fraction"]))))
	assert_bool(m.request_leave(12, 2)["ok"]).is_false()


func test_leave_has_a_cooldown_and_a_limit_and_is_refused_mid_duty() -> void:
	var m := _sol()
	var r: Dictionary = m.request_leave(11, 99)
	assert_int(int(r["days"])).is_equal(int(Career.data()["leave"]["max_days"]))
	assert_bool(m.request_leave(int(r["until"]) + 1, 2)["ok"]).is_false()
	var cool: int = m.leave_ready
	m.leave_until = -1
	assert_bool(m.request_leave(cool, 1)["ok"]).is_true()
	var m2 := _sol()
	m2.offer_duty(11, "patrol")
	m2.accept_duty(11)
	assert_str(String(m2.request_leave(11, 2)["reason"])).contains("duty")


# ---------------------------------------------------------------- discipline

func test_a_crime_costs_merit_by_severity() -> void:
	var m := _sol()
	_set_rank(m, 1, 10)
	m.merit = 50.0
	var r: Dictionary = m.report_crime("pickpocket", 12)
	assert_int(int(r["merit"])).is_equal(int(Career.data()["discipline"]["crime_merit_per_severity"]) * 1)
	assert_float(m.merit).is_equal(50.0 + float(r["merit"]))
	var r2: Dictionary = m.report_crime("robbery", 13)
	assert_int(int(r2["merit"])).is_equal(int(Career.data()["discipline"]["crime_merit_per_severity"]) * 3)
	assert_int(m.stat("crimes")).is_equal(2)


func test_repeat_crimes_demote_a_rank_and_the_kit_and_squad_follow() -> void:
	var m := _sol()
	_set_rank(m, 3, 10)
	m.squad.set_rank(3, 10, 1)
	assert_int(m.squad.size()).is_equal(3)
	m.merit = 500.0       # plenty of merit: it is the repeat offence that demotes
	m.report_crime("assault", 12)
	assert_str(m.rank_id()).is_equal("sergeant")
	var r: Dictionary = m.report_crime("assault", 13)
	assert_bool(r["demoted"]).is_true()
	assert_str(m.rank_id()).is_equal("corporal")
	assert_int(m.demotions).is_equal(1)
	assert_int(m.squad.size()).is_equal(2)
	assert_int(m.crimes_in_rank).is_equal(0)
	assert_float(m.merit).is_equal(float(Career.rank_def(2)["merit"]))


func test_a_ruined_record_demotes_even_on_a_first_offence() -> void:
	var m := _sol()
	_set_rank(m, 2, 10, 60.0)
	var r: Dictionary = m.report_crime("murder", 12, 5)     # severe but not beyond the colours
	assert_bool(r["demoted"]).is_true()
	assert_str(m.rank_id()).is_equal("private")


func test_a_heinous_crime_ends_service_and_a_lowly_recruit_can_be_discharged() -> void:
	var m := _sol()
	var r: Dictionary = m.report_crime("murder", 12)
	assert_bool(r["discharged"]).is_true()
	assert_bool(m.active).is_false()
	assert_str(m.struck_off).is_equal("discipline")
	assert_str(m.enlist_refusal(13)).contains("struck off")
	var m2 := _sol()
	m2.merit = -5.0
	m2.report_crime("burglary", 12)      # recruit at the bottom of the ladder
	assert_bool(m2.active).is_false()


func test_society_crimes_the_soldier_was_identified_for_are_judged_once() -> void:
	var m := _sol()
	_set_rank(m, 1, 10, 40.0)
	var soc: RefCounted = m.hub.mod("society")
	soc.crimes.append({"id": "c1", "kind": "robbery", "sid": 0, "day": 11, "witnesses": 2, "noticed": 2, "identified": 1, "reported": 1, "solved": false})
	soc.crimes.append({"id": "c2", "kind": "robbery", "sid": 0, "day": 11, "witnesses": 2, "noticed": 0, "identified": 0, "reported": 0, "solved": false})
	soc.crimes.append({"id": "c0", "kind": "robbery", "sid": 0, "day": 2, "witnesses": 2, "noticed": 2, "identified": 2, "reported": 2, "solved": false})
	_muster_day(m, 11)
	m.tick_day(12, {})
	assert_int(m.stat("crimes")).is_equal(1)
	assert_float(m.merit).is_less(40.0)
	m.tick_day(13, {})
	assert_int(m.stat("crimes")).is_equal(1)


func test_missing_enough_musters_is_desertion() -> void:
	var m := _sol()
	var soc: RefCounted = m.hub.mod("society")
	var n := int(Career.muster()["desert_after"])
	for d in n - 1:
		m.tick_day(12 + d, {})
		assert_bool(m.active).is_true()
	assert_int(m.missed_run).is_equal(n - 1)
	var out: Array = m.tick_day(12 + n - 1, {})
	assert_bool(m.active).is_false()
	assert_bool(m.deserter).is_true()
	assert_str(m.struck_off).is_equal("desertion")
	assert_str(String(out[0])).contains("deserter")
	assert_int(m.bounty_owed()).is_equal(int(Career.data()["discipline"]["desertion_bounty"]))
	assert_int(soc.bounty(int(m.post["sid"]))).is_equal(int(Career.data()["discipline"]["desertion_bounty"]))
	assert_int(m.stat("desertions")).is_equal(1)


func test_a_deserter_gets_no_pay_and_cannot_re_enlist_for_a_while() -> void:
	var m := _sol()
	for d in int(Career.muster()["desert_after"]):
		m.tick_day(12 + d, {})
	m.pending_gold = 0
	m.tick_week(5, {})
	assert_int(m.pending_gold).is_equal(0)
	assert_int(Career.pay_for_week(3, 0, false, true)).is_equal(0)
	assert_str(m.enlist_refusal(20)).contains("struck off")
	assert_str(m.enlist_refusal(m.banned_until)).is_equal("")
	assert_bool(m.enlist(m.banned_until)["ok"]).is_true()
	assert_bool(m.deserter).is_false()
	assert_str(m.rank_id()).is_equal("recruit")


func test_resigning_leaves_without_a_ban_or_bounty() -> void:
	var m := _sol()
	m.resign(15)
	assert_bool(m.active).is_false()
	assert_str(m.enlist_refusal(16)).is_equal("")
	assert_int(m.bounty_owed()).is_equal(0)


func test_sleeping_through_days_counts_as_absence_beyond_one_night() -> void:
	var m := _sol()
	m.catch_up(1, {})
	assert_int(m.missed_run).is_equal(0)
	m.catch_up(3, {})
	assert_int(m.missed_run).is_equal(2)
	var m2 := _sol()
	m2.request_leave(11, 5)
	m2.catch_up(5, {})
	assert_int(m2.missed_run).is_equal(0)
	var m3 := _sol()
	m3.catch_up(30, {})
	assert_bool(m3.active).is_false()
	assert_bool(m3.deserter).is_true()


# ---------------------------------------------------------------- squad

func test_the_squad_comes_with_corporal_and_grows_with_rank() -> void:
	var m := _sol()
	assert_int(m.squad.size()).is_equal(0)
	assert_bool(m.has_squad()).is_false()
	m.merit = 25.0
	assert_bool(m.petition(30)["ok"]).is_true()      # private: still no squad
	assert_int(m.squad.size()).is_equal(0)
	m.merit = 60.0
	assert_bool(m.petition(60)["ok"]).is_true()      # corporal
	assert_int(m.squad.size()).is_equal(2)
	assert_bool(m.has_squad()).is_true()
	m.merit = 130.0
	assert_bool(m.petition(100)["ok"]).is_true()
	assert_int(m.squad.size()).is_equal(3)
	m.merit = 240.0
	assert_bool(m.petition(150)["ok"]).is_true()
	assert_int(m.squad.size()).is_equal(4)
	var names := {}
	for n in m.squad.names():
		names[n] = true
	assert_int(names.size()).is_equal(4)
	for n in m.squad.names():
		assert_str(String(n)).contains(" ")


func test_squad_members_are_wounded_heal_and_can_die_and_be_replaced() -> void:
	var m := _sol()
	_set_rank(m, 3, 10)
	var first: String = String(m.squad.member(0)["name"])
	var max_hp: int = int(m.squad.member(0)["max_hp"])
	assert_str(m.squad_damage(0, 1, 20)).is_equal("ready")
	assert_str(m.squad_damage(0, max_hp, 20)).is_not_equal("ready")
	# A heavy blow wounds before it kills: the soldier is out, not dead, and heals over days.
	m.squad.deserialize(m.squad.serialize())
	var m2 := _sol()
	_set_rank(m2, 3, 10)
	var hp: int = int(m2.squad.member(1)["max_hp"])
	assert_str(m2.squad_damage(1, int(hp * 0.7), 20)).is_equal("wounded")
	assert_int(m2.squad.wounded_count()).is_equal(1)
	assert_int(m2.squad.ready_count()).is_equal(2)
	assert_str(m2.squad_damage(1, 5, 20)).is_equal("")           # the wounded cannot be hurt again
	m2.squad.tick_day(21, 1)
	assert_int(m2.squad.wounded_count()).is_equal(1)
	var out: Array = m2.squad.tick_day(20 + int(Career.data()["squad"]["wound_days"]), 1)
	assert_int(m2.squad.wounded_count()).is_equal(0)
	assert_str(String(out[0])).contains("fit for duty")
	# Death: a replacement is posted a couple of days on.
	var lost: String = String(m2.squad.member(0)["name"])
	m2.squad.kill(0, 30)
	assert_int(m2.squad.dead_count()).is_equal(1)
	assert_array(Array(m2.squad.fallen)).contains([lost])
	var out2: Array = m2.squad.tick_day(30 + int(Career.data()["squad"]["replace_days"]), 1)
	assert_int(m2.squad.dead_count()).is_equal(0)
	assert_int(m2.squad.size()).is_equal(3)
	assert_str(String(out2[0])).contains(lost)
	assert_str(String(m2.squad.member(0)["name"])).is_not_equal(lost)
	assert_str(first).is_not_empty()


func test_casualties_cost_the_commendation_chance() -> void:
	var m := _sol()
	_set_rank(m, 2, 0, 70.0)
	var d: Dictionary = m.offer_duty(11, "deliver_orders")
	m.accept_duty(11)
	m.squad_damage(0, int(m.squad.member(0)["max_hp"]), 11)
	assert_int(int(m.duty["casualties"])).is_equal(1)
	_finish_duty(m, d)
	assert_int(m.stat("commendations")).is_equal(0)
	assert_int(m.stat("squad_lost")).is_equal(1)


func test_the_squad_stands_in_a_column_behind_the_leader_and_fights_with_npc_fighter() -> void:
	var m := _sol()
	_set_rank(m, 4, 10)
	var slots := {}
	for i in m.squad.size():
		var s: Vector2 = m.squad.follow_slot(i, Vector2(100, 100), Vector2(0, -1))
		assert_float(s.y).is_greater(100.0)          # behind a leader who faces -y
		slots[str(s)] = true
	assert_int(slots.size()).is_equal(m.squad.size())
	var f: RefCounted = m.squad.fighter(0)
	assert_str(f.get_script().resource_path).is_equal("res://scripts/combat/npc_fighter.gd")
	assert_bool(NpcFighter.has_archetype(f.archetype)).is_true()
	var out: Dictionary = m.squad.think(0, 0.3, {"dist": 20.0, "has_token": true})
	assert_int(int(out["intent"])).is_equal(NpcFighter.Intent.APPROACH)
	m.squad.damage(0, int(m.squad.member(0)["max_hp"] * 0.8), 12)    # wounded: holds
	assert_int(int(m.squad.think(0, 0.3, {"dist": 20.0})["intent"])).is_equal(NpcFighter.Intent.HOLD)


# ---------------------------------------------------------------- save

func test_the_career_survives_a_save_round_trip_mid_duty() -> void:
	var m := _sol()
	_set_rank(m, 3, 15, 150.0)
	m.kit = Career.kit_for(3)
	_muster_day(m, 20)
	m.report_crime("trespass", 21)
	m.squad_damage(0, int(int(m.squad.member(0)["max_hp"]) * 0.7), 21)
	var d: Dictionary = m.offer_duty(22, "patrol")
	m.accept_duty(22)
	var objs: Array = d["def"]["stages"][0]["objectives"]
	var p0: Array = objs[0]["pos"]
	_bus.emit_event(&"position", {"x": float(p0[0]), "y": float(p0[1])})    # the first waypoint is reached
	var blob := _norm(m.serialize())
	var bus2 := QuestBus.new()
	var m2 := _sol(false)
	m2.bus_ref = bus2
	m2.deserialize(JSON.parse_string(JSON.stringify(m.serialize())))
	assert_str(_norm(m2.serialize())).is_equal(blob)
	assert_int(m2.rank).is_equal(3)
	assert_float(m2.merit).is_equal(m.merit)
	assert_int(m2.squad.size()).is_equal(3)
	assert_int(m2.squad.wounded_count()).is_equal(1)
	assert_str(String(m2.squad.member(0)["name"])).is_equal(String(m.squad.member(0)["name"]))
	assert_str(String(m2.duty["state"])).is_equal("active")
	# The duty carries on from the waypoint already reached.
	for i in range(1, objs.size()):
		var p: Array = objs[i]["pos"]
		bus2.emit_event(&"position", {"x": float(p[0]), "y": float(p[1])})
	assert_str(String(m2.duty["state"])).is_equal("done")
	assert_int(m2.stat("patrols")).is_equal(1)
	m2.release()


func test_the_soldier_module_is_saved_with_the_realm_hub() -> void:
	var m := _sol()
	m.merit = 33.0
	var hub: RefCounted = m.hub
	var saved: Dictionary = JSON.parse_string(JSON.stringify(hub.serialize()))
	assert_bool(saved.has("soldier")).is_true()
	var hub2: RefCounted = Hub.new()
	hub2.deserialize(saved)
	var m2: RefCounted = hub2.mod("soldier")
	_mods.append(m2)
	assert_bool(m2.active).is_true()
	assert_float(m2.merit).is_equal(33.0)
	assert_str(String(m2.officer["name"])).is_equal(String(m.officer["name"]))


func test_the_soldier_module_is_deterministic() -> void:
	var a := _sol()
	var b := _sol()
	assert_str(_norm(a.officer)).is_equal(_norm(b.officer))
	assert_str(_norm(a.post)).is_equal(_norm(b.post))
	_set_rank(a, 4, 10)
	_set_rank(b, 4, 10)
	assert_str(_norm(a.squad.serialize())).is_equal(_norm(b.squad.serialize()))


# ---------------------------------------------------------------- UI data

func test_the_career_screen_has_rank_merit_pay_next_promotion_duty_and_squad() -> void:
	var m := _sol()
	_set_rank(m, 2, 10, 70.0)
	m.offer_duty(11, "patrol")
	var v: Dictionary = m.status_view(11)
	var heads: Array = []
	for pair: Array in SoldierUI.summary(v):
		heads.append(String(pair[0]))
	assert_array(heads).is_equal(["Service", "Promotion", "Pay and muster", "Today's duty", "Squad"])
	assert_str(String(v["rank"])).is_equal("Corporal")
	assert_int(int(v["merit"])).is_equal(70)
	assert_str(SoldierUI.pay_text(v)).contains("%dg a week" % Career.weekly_wage(2))
	assert_str(String(v["next"]["title"])).is_equal("Sergeant")
	assert_int(SoldierUI.squad_lines(v).size()).is_equal(2)
	var inactive: Dictionary = _sol(false).status_view(11)
	assert_str(String(SoldierUI.summary(inactive)[0][1][0])).contains("Not enlisted")


func test_the_captain_menu_offers_enlisting_then_the_soldier_options() -> void:
	var m := _sol(false)
	SoldierUI.module_override = m
	SoldierUI.day_override = 10
	var menu: Dictionary = SoldierUI.captain_menu(null)
	assert_str(String((menu["options"] as Array)[0][0])).is_equal("Enlist")
	assert_bool((menu["options"] as Array)[0][2]).is_true()
	m.enlist(10, "captain")
	var menu2: Dictionary = SoldierUI.captain_menu(null)
	var labels: Array = []
	for o: Array in menu2["options"]:
		labels.append(String(o[0]))
	assert_bool(labels.has("Report for muster")).is_true()
	assert_bool(labels.has("Request leave (3 days)")).is_true()
	assert_bool(labels.has("Resign your commission")).is_true()
	assert_bool(labels.has("Enlist")).is_false()
	SoldierUI.module_override = null
	SoldierUI.day_override = -1


# ---------------------------------------------------------------- screens and bodies compile and render

const CareerTasks := preload("res://scripts/ui/career_tasks.gd")


func _texts(n: Node, out: Array = []) -> Array:
	if n is Label:
		out.append((n as Label).text)
	elif n is Button:
		out.append((n as Button).text)
	for c in n.get_children():
		_texts(c, out)
	return out


func _find_button(n: Node, text: String) -> Button:
	if n is Button and (n as Button).text.begins_with(text) and not (n as Button).disabled:
		return n as Button
	for c in n.get_children():
		var r := _find_button(c, text)
		if r != null:
			return r
	return null


func test_the_work_screen_enlists_shows_the_duty_and_lists_the_ladder() -> void:
	var m := _sol(false)
	CareerTasks.modules = {"soldier": m}
	CareerTasks.day_override = 10
	var s: Control = auto_free(CareerTasks.new())
	add_child(s)
	s.open("soldier")
	var before: String = "\n".join(_texts(s.get("_content")))
	var b := _find_button(s.get("_content"), "Enlist at the guard post")
	if b != null:
		b.pressed.emit()
	var was_active: bool = m.active
	var all: String = "\n".join(_texts(s.get("_content")))
	var take := _find_button(s.get("_content"), "Take today's duty")
	if take != null:
		take.pressed.emit()
	var duty_state := String(m.duty.get("state", ""))
	s.call("_set_tab", "ladder")
	var ladder: String = "\n".join(_texts(s.get("_content")))
	s.call("close_screen")      # (unpauses the tree before any assertion can end the test early)
	CareerTasks.modules = {}
	CareerTasks.day_override = -1
	assert_str(before).contains("Enlist")
	assert_bool(was_active).is_true()
	for t in ["Recruit", "Today's duty", "Pay and muster", "Squad"]:
		assert_str(all).contains(t)
	assert_str(duty_state).is_equal("active")
	for title in ["Recruit", "Private", "Corporal", "Sergeant", "Lieutenant"]:
		assert_str(ladder).contains(title)


func test_the_body_scripts_compile() -> void:
	for path in ["res://scripts/actors/squad_soldier.gd", "res://scripts/actors/squad_manager.gd", "res://scripts/actors/captain.gd", "res://scripts/ui/career_screen.gd"]:
		var sc: GDScript = load(path)
		assert_object(sc).override_failure_message(path).is_not_null()
		assert_bool(sc.can_instantiate()).override_failure_message(path).is_true()
