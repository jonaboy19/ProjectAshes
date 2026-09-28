extends GdUnitTestSuite
## Radiant quests: generation is deterministic for a seed, follows the world
## (dens, waystation, Whisper Hollow), progresses by polling, and saves.

const RadiantQuests := preload("res://scripts/sim/radiant_quests.gd")


func _world() -> Dictionary:
	return {
		"home": Vector2.ZERO,
		"dens": [{"id": 0, "species": "wolf", "pos": Vector2(420, 310), "population": 6, "alive": true},
			{"id": 1, "species": "wolf", "pos": Vector2(-500, 700), "population": 0, "alive": false}],
		"sites": [{"name": "Cinderpost Waystation", "kind": "waystation", "pos": Vector2(300, -210)}],
		"places": {"whisper_hollow": {"name": "Whisper Hollow", "kind": "hidden_place", "pos": Vector2(-560, 520), "radius": 12}},
	}


static func _json(quests: Array) -> String:
	return JSON.stringify(RadiantQuests._enc(quests))


func test_generation_is_deterministic_with_a_seed() -> void:
	var a := RadiantQuests.generate(_world(), 1234, 7)
	var b := RadiantQuests.generate(_world(), 1234, 7)
	assert_int(a.size()).is_equal(RadiantQuests.BOARD_SIZE)
	assert_str(_json(a)).is_equal(_json(b))
	# Another day or seed gives another board.
	assert_str(_json(RadiantQuests.generate(_world(), 1234, 8))).is_not_equal(_json(a))
	assert_str(_json(RadiantQuests.generate(_world(), 99, 7))).is_not_equal(_json(a))


func test_every_kind_appears_when_the_world_allows() -> void:
	var kinds := {}
	for q: Dictionary in RadiantQuests.generate(_world(), 5, 1):
		kinds[q["kind"]] = true
	for k: String in RadiantQuests.KINDS:
		assert_bool(kinds.has(k)).override_failure_message("missing %s" % k).is_true()


func test_kinds_follow_world_state() -> void:
	var bare := {"home": Vector2.ZERO, "dens": [], "sites": [], "places": {}}
	assert_array(RadiantQuests.available_kinds(bare)).is_equal(["fetch_herbs"])
	for q: Dictionary in RadiantQuests.generate(bare, 5, 1, 3):
		assert_str(q["kind"]).is_equal("fetch_herbs")
	# Wolf quests only ever target a living den.
	for day in 10:
		for q: Dictionary in RadiantQuests.generate(_world(), 11, day):
			if q["kind"] == "clear_wolves":
				assert_int(int(q["stages"][0]["den_id"])).is_equal(0)


func test_offers_depend_on_relationship() -> void:
	var rq := RadiantQuests.new()
	rq.tick_day(1, _world(), 5)
	assert_int(rq.offers.size()).is_equal(RadiantQuests.BOARD_SIZE)
	assert_array(rq.offers_for("villager", 2)).is_empty()       # strangers aren't asked
	assert_array(rq.offers_for("villager", 3)).is_not_empty()   # acquaintances are
	assert_array(rq.offers_for("guild", 1)).is_empty()          # rivals get nothing
	assert_array(rq.offers_for("guild", 2)).is_not_empty()      # the guild posts for anyone


func _offer(rq: RadiantQuests, kind: String) -> Dictionary:
	for q: Dictionary in rq.offers:
		if q["kind"] == kind:
			return q
	return {}


func test_reach_quest_progresses_and_objective_moves() -> void:
	var rq := RadiantQuests.new()
	rq.tick_day(1, _world(), 5)
	var q := _offer(rq, "lost_child")
	assert_str(rq.accept(q["id"], 1, "p7", "Maud", Vector2(2, 3))).is_equal("")
	var search: Vector2 = q["stages"][0]["pos"]
	assert_that(rq.active_objective_position()).is_equal(search)
	assert_array(rq.update({"pos": Vector2(900, 900)})).is_empty()
	var ev := rq.update({"pos": search})
	assert_str(ev[0]["type"]).is_equal("stage")
	assert_that(rq.active_objective_position()).is_equal(Vector2.ZERO)
	ev = rq.update({"pos": Vector2(5, 5)})
	assert_str(ev[0]["type"]).is_equal("complete")
	assert_int(int(ev[0]["reward"]["gold"])).is_greater(0)
	assert_that(rq.active_objective_position()).is_null()
	assert_int(rq.completed).is_equal(1)


func test_herbs_and_wolves_need_their_conditions() -> void:
	var rq := RadiantQuests.new()
	rq.tick_day(1, _world(), 5)
	var herbs := _offer(rq, "fetch_herbs")
	var wolves := _offer(rq, "clear_wolves")
	var pop := {"n": 6}
	var have := {"n": 0}
	var ctx := {"pos": Vector2(9999, 9999), "count_item": func(_i: String) -> int: return have["n"],
		"den_population": func(_id: int) -> int: return pop["n"]}
	rq.accept(herbs["id"], 1, "herbalist", "Herbalist", Vector2(9, 9), ctx)
	rq.accept(wolves["id"], 1, "guild", "Guild", Vector2(4, 4), ctx)
	rq.update(ctx)
	assert_str(rq.turn_in(herbs["id"], ctx["count_item"])["text"]).contains("nothing to report")
	have["n"] = 10
	pop["n"] = 6 - int(wolves["stages"][0]["kills"])
	var types := rq.update(ctx).map(func(e: Dictionary) -> String: return e["type"])
	assert_array(types).is_equal(["ready", "ready"])
	assert_int(rq.ready_for("herbalist").size()).is_equal(1)
	have["n"] = 1
	assert_bool(rq.turn_in(herbs["id"], ctx["count_item"])["ok"]).is_false()   # sold the herbs meanwhile
	have["n"] = 10
	var r := rq.turn_in(herbs["id"], ctx["count_item"])
	assert_bool(r["ok"]).is_true()
	assert_int(int(r["take"]["healing_herb"])).is_equal(int(herbs["stages"][0]["amount"]))


func test_deadline_fails_quest() -> void:
	var rq := RadiantQuests.new()
	rq.tick_day(1, _world(), 5)
	var q := _offer(rq, "escort")
	rq.accept(q["id"], 1)
	var ev := rq.tick_day(1 + int(q["days"]) + 1, _world(), 5)
	assert_int(ev.size()).is_equal(1)
	assert_str(ev[0]["type"]).is_equal("failed")
	assert_array(rq.active).is_empty()


func test_active_limit() -> void:
	var rq := RadiantQuests.new()
	rq.tick_day(1, _world(), 5)
	var ids: Array = rq.offers.map(func(q: Dictionary) -> String: return q["id"])
	for i in RadiantQuests.MAX_ACTIVE:
		assert_str(rq.accept(ids[i], 1)).is_equal("")
	assert_str(rq.accept(ids[RadiantQuests.MAX_ACTIVE], 1)).is_not_equal("")


func test_serialise_roundtrip() -> void:
	var rq := RadiantQuests.new()
	rq.tick_day(2, _world(), 5)
	rq.accept(_offer(rq, "deliver")["id"], 2, "p1", "Edda", Vector2(1, 2))
	var copy := RadiantQuests.new()
	copy.deserialize(JSON.parse_string(JSON.stringify(rq.serialize())))
	assert_int(copy.offers.size()).is_equal(rq.offers.size())
	assert_int(copy.active.size()).is_equal(1)
	assert_that(copy.active_objective_position()).is_equal(rq.active_objective_position())
	assert_str(_json(copy.active)).is_equal(_json(rq.active))
	# Loaded quests still progress.
	var ev := copy.update({"pos": copy.active_objective_position()})
	assert_str(ev[0]["type"]).is_equal("complete")
