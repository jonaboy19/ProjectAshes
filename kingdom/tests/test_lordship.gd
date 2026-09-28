extends GdUnitTestSuite
## Lordship: becoming a lord opens settlement management (docs/RISING_ASHES_LIFE_SIM_DESIGN.md,
## "Property, nobility, lordship"). Covers granting, daily income/food (season
## aware), infrastructure decay, deterministic issue generation, decisions
## applying their effects, projects completing (a runestone repair really
## changes the stone's condition), loyalty driving population, the harvest
## tithe, and a JSON round trip.

const Lordship := preload("res://scripts/sim/lordship.gd")

const IDLE := {"season": "summer", "at_war": false}
const WINTER := {"season": "winter", "at_war": false}


func before_test() -> void:
	WorldGen.setup(WorldSim.SEED)


func _new_lord() -> Lordship:
	return Lordship.new()


# --- granting ------------------------------------------------------------------------

func test_grant_reads_population_from_world_sim() -> void:
	var l := _new_lord()
	var v := l.grant(0, "crown")
	var expect: Vector2i = WorldSim.ranges[0]
	assert_int(int(v["population"])).is_equal(expect.y - expect.x)
	assert_int(int(v["population"])).is_greater(0)
	assert_bool(l.is_lord_of(0)).is_true()
	assert_str(String(v["reason"])).is_equal("crown")
	# Ashford's ring stones (frontier.gd's _seed_frontier) are owner-tagged 0.
	assert_bool((v["runestones"] as Array).is_empty()).is_false()


func test_grant_is_idempotent() -> void:
	var l := _new_lord()
	var a := l.grant(0, "crown")
	var b := l.grant(0, "purchase")
	assert_str(String(b["reason"])).is_equal(String(a["reason"]))
	assert_int(l.held_settlements().size()).is_equal(1)


func test_debug_grant_home() -> void:
	var l := _new_lord()
	var v := l.debug_grant_home()
	assert_int(int(v["settlement"])).is_equal(0)
	assert_bool(l.is_lord_of(0)).is_true()


# --- daily income, food, season, decay --------------------------------------------------

func test_daily_tax_income_grows_the_treasury() -> void:
	var l := _new_lord()
	l.grant(0, "crown")
	var before := int(l.villages[0]["treasury"])
	l.daily_tick(WorldSim.day, IDLE)
	assert_int(int(l.villages[0]["treasury"])).is_greater(before)


func test_winter_drains_food_stores_faster_than_summer() -> void:
	var summer := _new_lord()
	summer.grant(0, "crown")
	summer.villages[0]["food"] = 100.0
	summer.daily_tick(WorldSim.day, IDLE)
	var winter := _new_lord()
	winter.grant(0, "crown")
	winter.villages[0]["food"] = 100.0
	winter.daily_tick(WorldSim.day, WINTER)
	assert_float(float(winter.villages[0]["food"])).is_less(float(summer.villages[0]["food"]))


func test_infrastructure_decays_daily() -> void:
	var l := _new_lord()
	l.grant(0, "crown")
	var before := float(l.villages[0]["infra"]["roads"])
	l.daily_tick(WorldSim.day, IDLE)
	assert_float(float(l.villages[0]["infra"]["roads"])).is_less(before)


func test_militia_wages_are_paid_from_treasury() -> void:
	var l := _new_lord()
	l.grant(0, "crown")
	l.villages[0]["militia"] = 5
	l.villages[0]["treasury"] = 1000
	var before := int(l.villages[0]["treasury"])
	l.daily_tick(WorldSim.day, IDLE)
	var ledger: Dictionary = l.villages[0]["ledger"]
	assert_int(int(ledger["wages"])).is_equal(10)
	assert_int(int(l.villages[0]["treasury"])).is_less(before + 1000)   # wages did leave the treasury


# --- issues: deterministic generation -------------------------------------------------

func test_issue_generation_is_deterministic_per_seed() -> void:
	var a := _new_lord()
	var b := _new_lord()
	a.grant(0, "crown")
	b.grant(0, "crown")
	for d in range(WorldSim.day, WorldSim.day + 25):
		a.daily_tick(d, IDLE)
		b.daily_tick(d, IDLE)
	var ja := JSON.stringify(a.villages[0]["issues"])
	var jb := JSON.stringify(b.villages[0]["issues"])
	assert_str(ja).is_equal(jb)
	assert_int(int(a.villages[0]["population"])).is_equal(int(b.villages[0]["population"]))


# --- decisions apply their effects -----------------------------------------------------

func test_deciding_a_well_issue_spends_treasury_and_repairs_it() -> void:
	var l := _new_lord()
	l.grant(0, "crown")
	var v: Dictionary = l.villages[0]
	v["treasury"] = 100
	v["infra"]["well"] = 0.2
	var issue := l._raise_issue(v, "well_broken", WorldSim.day, {})
	assert_bool(issue.is_empty()).is_false()
	var r := l.decide(0, int(issue["id"]), 0)   # "Pay for repairs now (40g)"
	assert_bool(bool(r["ok"])).is_true()
	assert_int(int(v["treasury"])).is_equal(60)
	assert_float(float(v["infra"]["well"])).is_equal_approx(1.0, 0.001)
	assert_bool((v["issues"] as Array).is_empty()).is_true()


func test_cannot_afford_decision_is_refused_and_changes_nothing() -> void:
	var l := _new_lord()
	l.grant(0, "crown")
	var v: Dictionary = l.villages[0]
	v["treasury"] = 5
	var issue := l._raise_issue(v, "well_broken", WorldSim.day, {})
	var r := l.decide(0, int(issue["id"]), 0)
	assert_bool(bool(r["ok"])).is_false()
	assert_int(int(v["treasury"])).is_equal(5)
	assert_int((v["issues"] as Array).size()).is_equal(1)


func test_refugee_decision_grows_population_and_costs_food() -> void:
	var l := _new_lord()
	l.grant(0, "crown")
	var v: Dictionary = l.villages[0]
	v["food"] = 200.0
	var pop_before := int(v["population"])
	var issue := l._raise_issue(v, "refugees", WorldSim.day, {"count": 10})
	l.decide(0, int(issue["id"]), 0)   # take them all in
	assert_int(int(v["population"])).is_equal(pop_before + 10)
	assert_float(float(v["food"])).is_less(200.0)


func test_wolves_send_the_player_returns_a_quest_spec() -> void:
	var l := _new_lord()
	l.grant(0, "crown")
	var v: Dictionary = l.villages[0]
	Frontier.ecology.add_den("wolf", WorldGen.settlements[0]["pos"] + Vector2(50, 0), 6)
	var den_id := int(Frontier.ecology.dens.back()["id"])
	var issue := l._raise_issue(v, "wolves", WorldSim.day, {"den_id": den_id})
	var r := l.decide(0, int(issue["id"]), 1)   # "Deal with it yourself"
	assert_bool(bool(r["ok"])).is_true()
	assert_bool(r.has("quest_spec")).is_true()
	assert_int(int((r["quest_spec"] as Dictionary)["den_id"])).is_equal(den_id)


# --- projects: a runestone repair really changes the stone --------------------------

func test_runestone_repair_project_restores_the_real_stone() -> void:
	var l := _new_lord()
	l.grant(0, "crown")
	var v: Dictionary = l.villages[0]
	var stone_id := int(v["runestones"][0])
	Frontier.runestones.damage(stone_id, 0.9)
	assert_str(Frontier.runestones.condition_name(Frontier.runestones.stones[stone_id])).is_equal("dark")
	var issue := l._raise_issue(v, "runestone_cracked", WorldSim.day, {"stone_id": stone_id})
	v["treasury"] = 100
	var r := l.decide(0, int(issue["id"]), 1)   # "Send someone to see to it" -> starts a project
	assert_bool(bool(r["ok"])).is_true()
	assert_int((v["projects"] as Array).size()).is_equal(1)
	var days: int = int(Lordship.PROJECTS["repair_runestone"]["days"])
	var saw_repaired := false
	for i in days:
		for msg: String in l.daily_tick(WorldSim.day + i, IDLE):
			if msg.findn("repaired") >= 0:
				saw_repaired = true
	assert_bool(saw_repaired).is_true()
	assert_bool((v["projects"] as Array).is_empty()).is_true()
	assert_float(float(Frontier.runestones.stones[stone_id]["condition"])).is_equal_approx(1.0, 0.001)


func test_start_project_charges_the_treasury_and_completes() -> void:
	var l := _new_lord()
	l.grant(0, "crown")
	l.villages[0]["treasury"] = 100
	l.villages[0]["militia"] = 0
	var why := l.start_project(0, "recruit_militia")
	assert_str(why).is_empty()
	assert_int(int(l.villages[0]["treasury"])).is_equal(100 - int(Lordship.PROJECTS["recruit_militia"]["gold"]))
	for i in int(Lordship.PROJECTS["recruit_militia"]["days"]):
		l.daily_tick(WorldSim.day + i, IDLE)
	assert_int(int(l.villages[0]["militia"])).is_greater_equal(Lordship.MILITIA_PER_RECRUIT_PROJECT)


# --- loyalty -> population ------------------------------------------------------------

func test_low_loyalty_eventually_shrinks_the_population() -> void:
	var l := _new_lord()
	l.grant(0, "crown")
	var v: Dictionary = l.villages[0]
	var start_pop := int(v["population"])
	for i in 60:
		v["loyalty"] = 5.0    # force sustained collapse, below REVOLT_LOYALTY
		l.daily_tick(WorldSim.day + i, IDLE)
	assert_int(int(v["population"])).is_less(start_pop)


func test_high_loyalty_and_food_can_grow_the_population() -> void:
	var l := _new_lord()
	l.grant(0, "crown")
	var v: Dictionary = l.villages[0]
	v["food"] = 100000.0
	var start_pop := int(v["population"])
	var grew := false
	for i in 200:
		v["loyalty"] = 95.0
		v["food"] = 100000.0
		l.daily_tick(WorldSim.day + i, IDLE)
		if int(v["population"]) > start_pop:
			grew = true
			break
	assert_bool(grew).is_true()


# --- obligations: the harvest tithe ---------------------------------------------------

func test_autumn_raises_a_harvest_tithe_issue() -> void:
	var l := _new_lord()
	l.grant(0, "crown")
	l.daily_tick(WorldSim.day, {"season": "summer", "at_war": false})
	var found := false
	for msg: String in l.daily_tick(WorldSim.day + 1, {"season": "autumn", "at_war": false}):
		if msg.findn("tithe") >= 0:
			found = true
	var has_issue := false
	for q: Dictionary in (l.villages[0]["issues"] as Array):
		if String(q["kind"]) == "harvest_tithe":
			has_issue = true
	assert_bool(found or has_issue).is_true()


func test_levy_troops_reduces_militia_once() -> void:
	var l := _new_lord()
	l.grant(0, "crown")
	l.villages[0]["militia"] = 10
	var msg := l.levy_troops(0)
	assert_str(msg).is_not_empty()
	assert_int(int(l.villages[0]["militia"])).is_less(10)
	assert_str(l.levy_troops(0)).is_empty()   # already levied


# --- save / load -----------------------------------------------------------------------

func test_serialize_round_trip() -> void:
	var l := _new_lord()
	l.grant(0, "crown")
	var v: Dictionary = l.villages[0]
	v["treasury"] = 321
	v["loyalty"] = 42.0
	v["food"] = 17.5
	v["tax_rate"] = "harsh"
	l._raise_issue(v, "bandits", WorldSim.day, {})
	l.start_project(0, "recruit_militia")
	var snap: Dictionary = JSON.parse_string(JSON.stringify(l.serialize()))
	var restored := _new_lord()
	restored.deserialize(snap)
	assert_bool(restored.is_lord_of(0)).is_true()
	var rv: Dictionary = restored.villages[0]
	assert_int(int(rv["treasury"])).is_equal(321 - int(Lordship.PROJECTS["recruit_militia"]["gold"]))
	assert_float(float(rv["loyalty"])).is_equal_approx(42.0, 0.001)
	assert_float(float(rv["food"])).is_equal_approx(17.5, 0.001)
	assert_str(String(rv["tax_rate"])).is_equal("harsh")
	assert_int((rv["issues"] as Array).size()).is_equal(1)
	assert_int((rv["projects"] as Array).size()).is_equal(1)
