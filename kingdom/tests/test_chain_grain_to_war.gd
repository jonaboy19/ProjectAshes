extends GdUnitTestSuite
## Section 0 of the owner blueprint, as one chain (WP-07): a farming settlement's grain stock -> caravan
## delivery -> the fortress garrison's food -> garrison hunger and morale (army/morale.gd) -> a hostile
## neighbour's opportunity score in war_sim.gd, each step published to systems/world_event_log.gd.
## A caravan lost to bandits must leave the source stock lower and the garrison hungrier.

const Hub := preload("res://scripts/realm/realm_hub.gd")
const Chain := preload("res://scripts/sim/supply_chain.gd")
const RACaravans := preload("res://scripts/sim/caravans.gd")
const WarSim := preload("res://scripts/sim/war_sim.gd")
const EventLog := preload("res://scripts/systems/world_event_log.gd")

const NATION := "ongur_khanate"
const GRAIN := 400.0

static var _world := false


func _ids() -> Array[int]:
	var out: Array[int] = []
	for s: Dictionary in WorldGen.settlements:
		if int(s["id"]) != 0 and String(s["kind"]) != "castle":
			out.append(int(s["id"]))
	return out


## A wired world: `farm` has grain, `fort` has a 20-man garrison with a thin larder.
func _rig(risky: bool, seed_value: int) -> Dictionary:
	if not _world:
		WorldGen.setup(2024)
		_world = true
	var hub: RefCounted = Hub.new()
	hub.mod("organizations").auto_seed = false
	hub.mod("organizations").gold_ref = {"gold": 5000}
	hub.mod("businesses").set_day(0)
	var ids := _ids()
	var farm := ids[0]
	var fort := ids[1]
	var st: RefCounted = hub.mod("settlements")
	var ar: RefCounted = hub.mod("armies")
	st.add_stock(farm, "grain", 2000.0)
	var start: float = st.supply_of(farm, "grain")
	var g: Dictionary = ar.found("player", "garrison", "Fort garrison", fort, {"purse": 5000, "food": 0.0})
	ar.muster(g["id"], "spear", 20, 0.0)
	ar.set_defence(fort, {"garrison": g["id"]})
	ar.stock_up(fort, "food", 30.0)     # a day and a half of bread
	var chain := Chain.new()
	var log := EventLog.new()
	var war := WarSim.new(seed_value)
	var car := RACaravans.new()
	chain.setup(st, ar, car, war, log)
	return {"hub": hub, "st": st, "ar": ar, "chain": chain, "log": log, "war": war, "farm": farm, "fort": fort,
		"gid": String(g["id"]), "start": start, "tier": "frontier" if risky else "kingdom", "stone": 1.0 if risky else 0.0}


## Finds a dispatch seed whose caravan is (or is not) ambushed, then returns the finished rig.
func _run(want_loss: bool) -> Dictionary:
	for seed_value in range(1, 400):
		var r := _rig(want_loss, seed_value)
		var d: Dictionary = r["chain"].dispatch(r["farm"], r["fort"], GRAIN, 100.0, seed_value, 0, r["tier"], r["stone"])
		assert_bool(d["ok"]).is_true()
		var arrived: Array[Dictionary] = r["chain"].tick(float(d["arrive"]) + 1.0)
		if arrived.size() == 1 and (float(arrived[0]["lost"]) > 0.0) == want_loss:
			r["dispatch"] = d
			r["arrival"] = arrived[0]
			return r
	fail("no seed produced the wanted caravan outcome")
	return {}


func test_link_1_caravan_takes_grain_out_of_the_source_stock() -> void:
	var r := _run(false)
	assert_float(r["st"].supply_of(r["farm"], "grain")).is_equal(float(r["start"]) - GRAIN)


func test_link_2_delivery_feeds_the_garrison_larder() -> void:
	var r := _run(false)
	assert_float(float(r["arrival"]["kept"])).is_equal(GRAIN)
	assert_float(float(r["ar"].defence(r["fort"])["stock"]["food"])).is_equal(30.0 + GRAIN)


func test_lost_caravan_reduces_stock_and_delivers_less() -> void:
	var r := _run(true)
	var lost := float(r["arrival"]["lost"])
	assert_float(lost).is_greater(0.0)
	assert_float(r["st"].supply_of(r["farm"], "grain")).is_equal(float(r["start"]) - GRAIN)    # the loss is never refunded
	assert_float(float(r["arrival"]["kept"])).is_equal(GRAIN - lost)
	assert_float(float(r["ar"].defence(r["fort"])["stock"]["food"])).is_equal(30.0 + GRAIN - lost)
	assert_str(String(r["arrival"]["kind"])).is_equal("caravan_lost")


func _starve_days(r: Dictionary, days: int) -> void:
	for d in days:
		r["ar"].tick_day(10 + d, {})


func test_link_3_and_4_hunger_drags_garrison_morale_and_raises_opportunity() -> void:
	var fed := _run(false)
	var fed_state: Dictionary = fed["chain"].assess(fed["fort"], NATION, 200.0, int(fed["arrival"]["event"]))
	# a delivery that never came: same garrison, thin larder, days pass
	var cut := _rig(false, 1)
	_starve_days(cut, 6)
	var cut_state: Dictionary = cut["chain"].assess(cut["fort"], NATION, 200.0)
	assert_int(int(cut_state["hungry_days"])).is_greater(2)
	assert_float(float(cut_state["morale"])).is_less(float(fed_state["morale"]))
	assert_float(float(cut_state["food_days"])).is_less(float(fed_state["food_days"]))
	assert_float(float(cut_state["score"])).is_greater(float(fed_state["score"]) + 0.2)
	assert_float(cut["war"].opportunity_of(NATION)).is_equal(float(cut_state["score"]))


func test_link_5_opportunity_pushes_the_neighbours_tension_up() -> void:
	var cut := _rig(false, 5)
	var calm := WarSim.new(5)
	_starve_days(cut, 6)
	cut["chain"].assess(cut["fort"], NATION, 200.0)
	for day in 20:
		cut["war"].tick_day(day, {})
		calm.tick_day(day, {})
	assert_float(cut["war"].tension_of(NATION)).is_greater(calm.tension_of(NATION))


func test_every_step_is_published_and_linked_by_cause() -> void:
	var r := _run(true)
	_starve_days(r, 40)    # 20 men eat the delivered larder in about three weeks
	var end: Dictionary = r["chain"].assess(r["fort"], NATION, 300.0, int(r["arrival"]["event"]))
	var by_id := {}
	for e: Dictionary in r["log"].since(0, 64):
		by_id[int(e["id"])] = e
	var kinds: Array = []
	var e2: Dictionary = by_id[int(end["event"])]
	while true:
		kinds.push_front(String(e2["type"]))
		if int(e2["cause_id"]) == 0:
			break
		e2 = by_id[int(e2["cause_id"])]
	assert_array(kinds).is_equal(["grain_dispatched", "caravan_lost", "garrison_hungry", "war_opportunity"])


func test_opportunity_survives_a_save_round_trip() -> void:
	var war := WarSim.new(9)
	war.note_opportunity(NATION, 20.0, 1.0)
	var back := WarSim.new(9)
	back.deserialize(war.serialize())
	assert_float(back.opportunity_of(NATION)).is_equal(war.opportunity_of(NATION))
