extends GdUnitTestSuite
## WP-17: deer scarcity -> bolder wolves near farms -> livestock lost -> settlement bounty on the radiant
## board -> a hunter NPC is hired when nobody claims it (or the player claims it first).

const RQ := preload("res://scripts/sim/radiant_quests.gd")

func _rig(prey: float, seed_value := 7) -> Dictionary:
	WorldGen.setup(1066)
	var home: Dictionary = WorldGen.settlements[0]
	var eco := RAMonsterEcology.new(seed_value)
	var den := eco.add_den("wolf", (home["pos"] as Vector2) + Vector2(120, 0), 8)
	var chain := RAEcologyBounty.new()
	var sid := int(home.get("id", 0))
	chain.bind(eco, func(_s: int) -> float: return prey,
		func(d: Dictionary) -> Dictionary: return {"sid": sid, "pos": home["pos"], "name": String(home.get("name", "Ashford"))})
	return {"eco": eco, "den": den, "chain": chain, "rq": RQ.new(), "sid": sid, "home": home}


func _run(r: Dictionary, days: int, pay := Callable()) -> Array:
	var events: Array = []
	for day in range(1, days + 1):
		(r["eco"] as RAMonsterEcology).tick_day(func(_p: Vector2) -> float: return 0.0, 0.0, false)
		events.append_array((r["chain"] as RAEcologyBounty).tick_day(day, r["rq"], pay))
	return events


func _types(events: Array) -> Array:
	return events.map(func(e: Dictionary) -> String: return String(e["type"]))


func test_scarcity_raises_wolf_aggression_and_losses() -> void:
	var lean := _rig(0.0)
	var fat := _rig(1.0)
	_run(lean, 30)
	_run(fat, 30)
	var lean_losses := (lean["eco"] as RAMonsterEcology).events_since(0).filter(func(e: Dictionary) -> bool: return e["type"] == "livestock_taken").size()
	var fat_losses := (fat["eco"] as RAMonsterEcology).events_since(0).filter(func(e: Dictionary) -> bool: return e["type"] == "livestock_taken").size()
	assert_float(lean["chain"].scarcity_at(lean["home"]["pos"])).is_equal(1.0)
	assert_float(fat["chain"].scarcity_at(fat["home"]["pos"])).is_equal(0.0)
	assert_float(float(lean["den"]["aggression"])).is_greater(float(fat["den"]["aggression"]))
	assert_int(lean_losses).is_greater(fat_losses)


func test_losses_post_a_bounty_on_the_board() -> void:
	var r := _rig(0.0)
	var events := _run(r, 40, func(_s: int, _g: int) -> bool: return false)   # settlement too poor to hire yet
	assert_array(_types(events)).contains(["bounty_posted"])
	var b: Dictionary = (r["chain"] as RAEcologyBounty).bounties[0]
	assert_int(int(b["den_id"])).is_equal(int(r["den"]["id"]))
	var q: Dictionary = (r["rq"] as RQ).find(String(b["quest_id"]))
	assert_str(String(q["kind"])).is_equal("clear_wolves")
	assert_int(int(q["stages"][0]["den_id"])).is_equal(int(r["den"]["id"]))
	# The offer is not rotated off the board while the settlement waits.
	(r["rq"] as RQ).tick_day(40 + RQ.OFFER_DAYS + 2, {"home": Vector2.ZERO, "dens": [], "sites": [], "places": {}}, 1)
	assert_dict((r["rq"] as RQ).find(String(b["quest_id"]))).is_not_empty()


func _first_bounty_day(r: Dictionary) -> int:
	for e: Dictionary in _run(r, 120, func(_s: int, _g: int) -> bool: return false):
		if e["type"] == "bounty_posted":
			return int(e["day"])
	return 9999


func test_scarcity_brings_the_bounty_sooner() -> void:
	assert_int(_first_bounty_day(_rig(0.0))).is_less_equal(_first_bounty_day(_rig(1.0)))


func test_ignored_bounty_hires_a_hunter_who_thins_the_den() -> void:
	var r := _rig(0.0)
	var paid := []
	var events := _run(r, 80, func(sid: int, gold: int) -> bool:
		paid.append([sid, gold])
		return true)
	assert_array(_types(events)).contains(["bounty_posted", "hunter_hired"])
	var chain := r["chain"] as RAEcologyBounty
	assert_int(chain.hunters.size()).is_greater_equal(1)
	assert_int(paid.size()).is_greater_equal(1)
	assert_int(int(paid[0][1])).is_greater(0)
	assert_str(String(chain.hunters[0]["name"])).is_not_empty()
	# The posted offer is gone and the den was cut.
	assert_dict((r["rq"] as RQ).find(String(chain.bounties[0]["quest_id"]))).is_empty()
	assert_int(int(r["den"]["population"])).is_less(8)


func test_poor_settlement_cannot_hire_so_bounty_stays_posted() -> void:
	var r := _rig(0.0)
	var events := _run(r, 80, func(_sid: int, _gold: int) -> bool: return false)
	assert_array(_types(events)).not_contains(["hunter_hired"])
	assert_array((r["chain"] as RAEcologyBounty).hunters).is_empty()
	assert_str(String((r["chain"] as RAEcologyBounty).bounties[0]["state"])).is_equal("posted")


func test_player_claim_prevents_hiring_and_resolves_on_den_death() -> void:
	var r := _rig(0.0)
	var chain := r["chain"] as RAEcologyBounty
	var rq := r["rq"] as RQ
	var day := 0
	while chain.bounties.is_empty() and day < 60:
		day += 1
		(r["eco"] as RAMonsterEcology).tick_day(func(_p: Vector2) -> float: return 0.0, 0.0, false)
		chain.tick_day(day, rq)
	assert_int(chain.bounties.size()).is_equal(1)
	var qid := String(chain.bounties[0]["quest_id"])
	assert_str(rq.accept(qid, day)).is_empty()
	var events: Array = []
	for _i in RAEcologyBounty.HIRE_AFTER_DAYS + 3:
		day += 1
		events.append_array(chain.tick_day(day, rq, func(_s: int, _g: int) -> bool: return true))
	assert_array(_types(events)).not_contains(["hunter_hired"])
	assert_str(String(chain.bounties[0]["state"])).is_equal("claimed")
	(r["eco"] as RAMonsterEcology).cull(int(r["den"]["id"]), 100)
	events = chain.tick_day(day + 1, rq)
	assert_array(_types(events)).contains(["bounty_resolved"])


func test_serialize_round_trips() -> void:
	var r := _rig(0.0)
	_run(r, 80, func(_s: int, _g: int) -> bool: return true)
	var chain := r["chain"] as RAEcologyBounty
	var copy := RAEcologyBounty.new()
	copy.deserialize(JSON.parse_string(JSON.stringify(chain.serialize())))
	assert_int(copy.bounties.size()).is_equal(chain.bounties.size())
	assert_int(copy.hunters.size()).is_equal(chain.hunters.size())
	assert_str(String(copy.bounties[0]["state"])).is_equal(String(chain.bounties[0]["state"]))
