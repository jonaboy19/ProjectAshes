extends GdUnitTestSuite
## LW-8 (docs/design/LIVING_WORLD_SANDBOX.md section 11, "memory and rumour"): characters remember significant events about the player and each
## other (bounded), stories spread by road distance, can be wrong, can be investigated and corrected, and the save stays small.

const Hub := preload("res://scripts/realm/realm_hub.gd")
const Events := preload("res://scripts/realm/events.gd")

static var _ready_world := false


func _hub() -> RefCounted:
	if not _ready_world:
		WorldGen.setup(2024)
		_ready_world = true
	WorldSim.day = 100
	var h: RefCounted = Hub.new()
	var om: RefCounted = h.mod("organizations")
	om.auto_seed = false
	om.gold_ref = {"gold": 5000}
	h.mod("faith").auto_seed = false
	h.mod("minds").auto_seed = false
	h.mod("minds").set_focus(-1)
	return h


func _norm(d: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(d)))


func _days(h: RefCounted, from: int, to: int) -> void:
	for d in range(from, to + 1):
		WorldSim.day = d
		h.mod("rumours").tick_day(d, {})


# --- memory ---------------------------------------------------------------------------

func test_memory_is_bounded_and_keeps_what_matters() -> void:
	var rm: RefCounted = _hub().mod("rumours")
	for i in 30:
		rm.witness("ch:1", "trade", "ch:%d" % (100 + i), 2.0 + float(i % 3), 0, {"quiet": true})
	rm.witness("ch:1", "crime", "ch:9", -90.0, 0, {"quiet": true})
	var mem: Array = rm.memories("ch:1")
	assert_int(mem.size()).is_less_equal(rm.MEM_MAX)
	var kept := false
	for m: Dictionary in mem:
		if String(m["subject"]) == "ch:9":
			kept = true
	assert_bool(kept).is_true()                                    # the striking memory outlives the dull ones


func test_the_same_story_strengthens_a_memory_instead_of_piling_up() -> void:
	var rm: RefCounted = _hub().mod("rumours")
	var cid: int = rm.say("crime", "ch:7", 0, -40.0)
	rm._remember("ch:2", "ch:7", "crime", -40.0, 40, cid)
	rm._remember("ch:2", "ch:7", "crime", -40.0, 80, cid)
	assert_int(rm.memories("ch:2").size()).is_equal(1)
	assert_int(int(rm.memories("ch:2")[0]["conf"])).is_equal(80)


func test_opinion_blends_memory_with_the_town_and_fades() -> void:
	var rm: RefCounted = _hub().mod("rumours")
	rm.witness("ch:1", "crime", "ch:5", -60.0, 0, {"quiet": true})
	var fresh: float = rm.opinion("ch:1", "ch:5")
	assert_float(fresh).is_less(-40.0)
	WorldSim.day = 100 + 600
	rm._day = 700
	assert_float(rm.opinion("ch:1", "ch:5")).is_greater(fresh)   # old memories weigh less
	assert_float(rm.opinion("ch:1", "ch:404")).is_equal(0.0)


# --- spread ---------------------------------------------------------------------------

func test_a_story_reaches_a_far_town_later_than_a_near_one() -> void:
	var h := _hub()
	var rm: RefCounted = h.mod("rumours")
	var nw: RefCounted = h.mod("news")
	var near := 6       # 741 from town 0
	var far := 4        # 2324 from town 0
	var cid: int = rm.say("battle", "ch:3", 0, 50.0)
	assert_int(rm.heard_in(0, "ch:3").size()).is_equal(1)           # told at home at once
	assert_int(rm.heard_in(near, "ch:3").size()).is_equal(0)
	var t_near := 100 + 1 + int(nw.road_distance(0, near) / rm.SPEED)
	var t_far := 100 + 1 + int(nw.road_distance(0, far) / rm.SPEED)
	assert_int(t_far).is_greater(t_near)
	_days(h, 101, t_near)
	assert_int(rm.heard_in(near, "ch:3").size()).is_equal(1)
	assert_int(rm.heard_in(far, "ch:3").size()).is_equal(0)         # not yet
	_days(h, t_near + 1, t_far)
	assert_int(rm.heard_in(far, "ch:3").size()).is_equal(1)
	assert_int(cid).is_greater(0)


func test_distance_garbles_a_story_and_some_towns_hear_it_wrong() -> void:
	var h := _hub()
	var rm: RefCounted = h.mod("rumours")
	for k in 10:
		assert_int(rm.say("battle", "ch:%d" % (200 + k), 0, 60.0)).is_greater(0)
	rm.catch_up(200, {})                                              # everything in flight has arrived
	var wrong := 0
	var heard := 0
	for k in 10:
		for sid in [4, 3, 7, 9]:
			var rows: Array = rm.heard_in(sid, "ch:%d" % (200 + k))
			if rows.is_empty():
				continue
			heard += 1
			if absf(float(rows[0]["said"]) - 60.0) > 15.0:
				wrong += 1
	assert_int(heard).is_equal(40)
	assert_int(wrong).is_greater(1)                                  # far towns do not hear what happened exactly
	assert_int(wrong).is_less(heard)                                  # but most stories are roughly right


func test_a_false_tale_travels_and_is_believed_in_town() -> void:
	var h := _hub()
	var mn: RefCounted = h.mod("minds")
	mn.seed_minds(40)
	var rm: RefCounted = h.mod("rumours")
	var sid := 0
	var who: Array = mn.in_town(sid)
	assert_int(who.size()).is_greater(0)
	var cid: int = rm.say("crime", "ch:900", sid, 40.0, {"wrong": true, "by": String(who[0])})
	assert_float(float(rm.claim(cid)["m"])).is_less(0.0)             # told as bad although the truth is good
	assert_float(float(rm.claim(cid)["t"])).is_greater(0.0)
	_days(h, 100, 140)
	var believers := 0
	for ch: String in mn.ids():
		if rm.believes_falsely(ch, "ch:900"):
			believers += 1
	assert_int(believers).is_greater(0)


# --- investigation --------------------------------------------------------------------

func test_investigation_finds_the_truth_and_corrects_every_town_and_believer() -> void:
	var h := _hub()
	var mn: RefCounted = h.mod("minds")
	mn.seed_minds(40)
	var rm: RefCounted = h.mod("rumours")
	var om: RefCounted = h.mod("organizations")
	var sleuth: String = mn.ids()[0]
	om.earn(sleuth, 400)
	var liar: String = mn.ids()[1]
	var cid: int = rm.say("crime", "ch:901", 0, 45.0, {"wrong": true, "by": liar})
	_days(h, 100, 150)
	var rep_before: float = float(h.mod("reputation").truth("i:" + liar).get("reliability", 0.0)) if not h.mod("reputation").truth("i:" + liar).is_empty() else 0.0
	var res: Dictionary = {}
	for tries in 6:
		WorldSim.day = 150 + tries
		rm._day = 150 + tries
		res = rm.investigate(cid, sleuth, 1.0, 100)
		if bool(res["found"]):
			break
	assert_bool(res["found"]).is_true()
	assert_bool(res["was_wrong"]).is_true()
	assert_float(float(res["true_mag"])).is_equal(45.0)
	# nobody still believes the false version
	for ch: String in mn.ids():
		assert_bool(rm.believes_falsely(ch, "ch:901")).is_false()
	for t in 30:
		for row: Dictionary in rm.heard_in(t, "ch:901"):
			if int(row["id"]) == cid:
				assert_float(float(row["said"])).is_equal(45.0)
				assert_bool(row["corrected"]).is_true()
	var rep_after: float = float(h.mod("reputation").truth("i:" + liar).get("reliability", 0.0))
	assert_float(rep_after).is_less(rep_before)                       # the liar paid
	assert_bool(rm.investigate(cid, sleuth, 0.1)["found"]).is_true()  # a settled case stays settled


func test_investigation_can_fail_and_digging_costs_gold() -> void:
	var h := _hub()
	var rm: RefCounted = h.mod("rumours")
	var om: RefCounted = h.mod("organizations")
	om.ensure_char("ch:77", {"cash": 10})
	var cid: int = rm.say("crime", "ch:902", 0, -40.0, {"wrong": true})
	assert_bool(rm.investigate(cid, "ch:77", 0.5, 100)["ok"]).is_false()   # no gold for it
	var fails := 0
	var finds := 0
	for i in 24:
		rm._day = 100 + i
		WorldSim.day = 100 + i
		var c2: int = rm.say("crime", "ch:%d" % (910 + i), 0, -40.0, {"wrong": true})
		var r: Dictionary = rm.investigate(c2, "ch:77", 0.0)
		if bool(r["found"]):
			finds += 1
		else:
			fails += 1
	assert_int(fails).is_greater(0)                                   # an unskilled digger often finds nothing
	assert_int(finds).is_greater(0)                                   # and sometimes gets lucky
	assert_int(fails).is_greater(finds)


func test_a_false_story_damages_a_name_in_reputation_until_it_is_corrected() -> void:
	var h := _hub()
	var rm: RefCounted = h.mod("rumours")
	var rep: RefCounted = h.mod("reputation")
	var om: RefCounted = h.mod("organizations")
	om.ensure_char("ch:55", {"cash": 400})
	# the truth is a good deed (+40 competence-ish), but the tale told is the reverse
	var cid: int = rm.say("founding", "ch:60", 0, 50.0, {"wrong": true, "by": "ch:55"})
	var told: float = float(rm.claim(cid)["m"])
	assert_float(told).is_less(0.0)
	var axis: String = rm.KIND_AXIS["founding"]
	var damaged: float = float(rep.truth("i:ch:60").get(axis, 0.0))
	assert_float(damaged).is_less(0.0)                                  # the false story moved the axis the wrong way
	var found := false
	for i in 8:
		rm._day = 100 + i
		WorldSim.day = 100 + i
		if bool(rm.investigate(cid, "ch:55", 1.0, 100)["found"]):
			found = true
			break
	assert_bool(found).is_true()
	var mended: float = float(rep.truth("i:ch:60").get(axis, 0.0))
	assert_float(mended).is_greater(damaged)                            # corrected: the name is mended by the same measure
	assert_float(mended).is_greater(0.0)


# --- the event ring and the player ----------------------------------------------------

func test_significant_events_become_stories_with_witnesses() -> void:
	var h := _hub()
	var mn: RefCounted = h.mod("minds")
	mn.seed_minds(60)
	var rm: RefCounted = h.mod("rumours")
	var reg: RefCounted = h.mod("registry")
	var who: String = mn.in_town(0)[0] if mn.in_town(0).size() > 0 else mn.ids()[0]
	Events.log_to(h, "crime", "ss:0", [who], "robbery", "Someone was robbed", 6)
	Events.log_to(h, "trade", "ss:0", [who], "minor", "A small thing", 1)   # too small to talk about
	assert_int(rm.heard_in(0, who).size()).is_equal(0)
	rm.tick_day(101, {})
	assert_int(rm.heard_in(0, who).size()).is_equal(1)             # the robbery became a story; the small trade did not
	assert_str(String(rm.heard_in(0, who)[0]["kind"])).is_equal("crime")
	var kept := 0
	for ch: String in mn.in_town(0):
		for m: Dictionary in rm.memories(ch):
			if String(m["subject"]) == who:
				kept += 1
	assert_int(kept).is_greater(0)
	assert_str(reg.lookup("pl:player")).is_equal("")


func test_what_the_player_does_is_remembered_by_those_who_saw() -> void:
	var h := _hub()
	var rm: RefCounted = h.mod("rumours")
	var reg: RefCounted = h.mod("registry")
	var pl: String = reg.ref("pl:player")
	var cid: int = rm.note_player("battle", 0, 55.0, ["ch:31", "ch:32"])
	assert_int(cid).is_greater(0)
	assert_float(rm.opinion("ch:31", pl)).is_greater(40.0)
	assert_float(rm.opinion("ch:33", pl)).is_equal(0.0)               # a stranger has not heard yet
	assert_float(rm.town_view(1, pl)).is_equal(0.0)
	_days(h, 100, 120)
	assert_float(rm.town_view(1, pl)).is_not_equal(0.0)               # the next town heard it after two weeks on the road


# --- size and save --------------------------------------------------------------------

func test_claims_and_memories_stay_bounded() -> void:
	var h := _hub()
	var rm: RefCounted = h.mod("rumours")
	for i in 600:
		rm.say("trade", "ch:%d" % (i % 90), i % 30, float(i % 50) - 20.0)
		rm.witness("ch:%d" % (i % 25), "trade", "ch:%d" % (i % 90), float(i % 50), i % 30, {"quiet": true})
	assert_int(rm.claim_count()).is_less_equal(rm.CLAIM_MAX)
	for k in 25:
		assert_int(rm.memories("ch:%d" % k).size()).is_less_equal(rm.MEM_MAX)
	var raw := JSON.stringify(rm.serialize()).length()
	assert_int(raw).is_less(220_000)


func test_save_round_trip_is_exact() -> void:
	var h := _hub()
	var mn: RefCounted = h.mod("minds")
	mn.seed_minds(40)
	var rm: RefCounted = h.mod("rumours")
	for i in 25:
		rm.say("battle", "ch:%d" % i, i % 7, float(i) * 3.0 - 30.0, {"wrong": i % 5 == 0})
		rm.witness("ch:%d" % (i + 1), "crime", "ch:%d" % i, -20.0, i % 7, {"quiet": true})
	_days(h, 100, 118)
	var a := _norm(rm.serialize())
	var h2 := _hub()
	var rm2: RefCounted = h2.mod("rumours")
	rm2.deserialize(JSON.parse_string(JSON.stringify(rm.serialize())))
	assert_str(_norm(rm2.serialize())).is_equal(a)
	assert_int(rm2.heard_in(0, "ch:1").size()).is_equal(rm.heard_in(0, "ch:1").size())
