extends GdUnitTestSuite
## READY_V1 C3, found a camp: the site card (water, slope, danger, land law), the naming and the claim; the story step
## a3_found_camp is satisfied by the claim; the seasons-pass card (age and festival gates) replaces the bot's ageing hooks.

const Hub := preload("res://scripts/realm/realm_hub.gd")
const FoundFlow := preload("res://scripts/realm/found_flow.gd")
const LandClaim := preload("res://scripts/realm/land_claim.gd")
const SeasonsPass := preload("res://scripts/region1/seasons_pass.gd")
const Director := preload("res://scripts/region1/r1_story_director.gd")
const Places := preload("res://scripts/region1/region1_places.gd")


class StubGlue extends Node:
	var tutorial = null
	func npc_extra_options(_id: String) -> Array:
		return []


func _mk() -> RefCounted:
	WorldGen.setup(WorldSim.SEED)
	var hub: RefCounted = Hub.new()
	var rs := RARunestoneNetwork.new()
	rs.seed_road_stones()
	hub.mod("civilization").runestones = rs
	for m: String in ["civilization", "migration", "land"]:
		hub.mod(m)._ensure()
	hub.mod("build_kit").height_fn = func(x: float, z: float) -> float: return WorldGen.height(x, z)
	return hub


func _spots(hub: RefCounted, n: int) -> Array:
	var out: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 91
	for _i in 6000:
		if out.size() >= n:
			break
		var p := Vector2(rng.randf_range(-3000.0, 3000.0), rng.randf_range(-3000.0, 3000.0))
		if not bool(hub.mod("founding").check_site(p)["ok"]):
			continue
		var far := true
		for q: Vector2 in out:
			far = far and q.distance_to(p) > 500.0
		if far:
			out.append(p)
	return out


func test_the_card_reads_the_ground_and_says_yes_on_good_land() -> void:
	var hub := _mk()
	var spot: Vector2 = _spots(hub, 1)[0]
	var card := FoundFlow.site_card(hub, spot)
	assert_bool(bool(card["ok"])).override_failure_message(String(card["reason"])).is_true()
	var labels: Array = (card["rows"] as Array).map(func(r: Array) -> String: return String(r[0]))
	assert_array(labels).contains(["Water", "Slope", "Danger", "Land law"])
	for r: Array in card["rows"]:
		assert_str(String(r[1])).is_not_empty()
		assert_float(float(r[2])).is_between(0.0, 1.0)
	assert_str(String(card["name"])).is_not_empty()
	assert_int(int(card["left"])).is_equal(3)


func test_the_card_refuses_water_a_settlement_and_held_ground() -> void:
	var hub := _mk()
	var spot: Vector2 = _spots(hub, 1)[0]
	var near_ashford := Vector2(WorldGen.settlements[0]["pos"]) + Vector2(20, 20)
	var c1 := FoundFlow.site_card(hub, near_ashford)
	assert_bool(bool(c1["ok"])).is_false()
	assert_str(String(c1["reason"])).is_not_empty()
	assert_str(String(c1["law_block"])).is_not_empty()
	var r := FoundFlow.found(hub, spot, "Newhold")
	assert_bool(bool(r["ok"])).is_true()
	var again := FoundFlow.site_card(hub, spot + Vector2(4, 4))
	assert_bool(bool(again["ok"])).is_false()
	assert_str(String(again["reason"])).contains("already hold")
	assert_int(int(again["left"])).is_equal(2)


func test_found_makes_one_linked_settlement_with_the_chosen_name() -> void:
	var hub := _mk()
	var spot: Vector2 = _spots(hub, 1)[0]
	var got: Array = []
	hub.mod("build_kit").founded.connect(func(gid: int, fid: int) -> void: got.append([gid, fid]))
	var r := FoundFlow.found(hub, spot, "  Embergate  \nand a very long tail that is cut off  ")
	assert_bool(bool(r["ok"])).override_failure_message(String(r["reason"])).is_true()
	assert_str(String(r["name"])).is_equal(FoundFlow.clean_name("  Embergate  \nand a very long tail that is cut off  "))
	assert_int(String(r["name"]).length()).is_less_equal(FoundFlow.NAME_MAX)
	assert_str(String(r["name"])).starts_with("Embergate")
	assert_int(hub.player_settlements().size()).is_equal(1)
	assert_int(int(r["fid"])).is_greater(0)
	assert_int(hub.mod("founding").active_count("player")).is_equal(1)
	assert_array(got).has_size(1)
	assert_int(int(got[0][0])).is_equal(int(r["gid"]))


func test_a_blank_name_keeps_the_founding_modules_own_name_and_the_fourth_camp_is_refused() -> void:
	var hub := _mk()
	var spots := _spots(hub, 4)
	assert_int(spots.size()).is_equal(4)
	var first := FoundFlow.found(hub, spots[0], "   ")
	assert_bool(bool(first["ok"])).is_true()
	assert_str(String(first["name"])).is_not_empty()
	for i in [1, 2]:
		assert_bool(bool(FoundFlow.found(hub, spots[i], "Camp %d" % i)["ok"])).is_true()
	var card := FoundFlow.site_card(hub, spots[3])
	assert_bool(bool(card["ok"])).is_false()
	assert_str(String(card["reason"])).contains("at most 3")
	assert_bool(bool(FoundFlow.found(hub, spots[3], "Fourth")["ok"])).is_false()
	assert_int(hub.player_settlements().size()).is_equal(3)


func test_a_claim_satisfies_the_a3_found_camp_step() -> void:
	Region1State.clear()
	Places.clear()
	var world: Node3D = auto_free(Node3D.new())
	var player: Node3D = auto_free(Node3D.new())
	player.add_to_group("player")
	add_child(world)
	add_child(player)
	var dir: Node = auto_free(Director.new())
	var glue: Node = auto_free(StubGlue.new())
	add_child(glue)
	add_child(dir)
	dir.setup(glue, null, player, world)
	for s: Dictionary in dir.story.steps:
		if String(s["id"]) in ["a3_council", "a3_silverford", "a2_thief_truth"]:
			dir.story.status[String(s["id"])] = "done"
	dir.story.status["a3_found_camp"] = "active"
	dir.story.progress["a3_found_camp"] = {}
	assert_str(String(dir.story.current_objective("a3_found_camp")["id"])).is_equal("found")
	dir._on_camp_founded(1, 1)    # what BuildKit.founded calls through the signal
	assert_bool(dir.story.has_flag("r1.a3.camp_founded")).is_true()
	assert_str(String(dir.story.current_objective("a3_found_camp")["id"])).is_equal("told")
	assert_bool(dir.story.step("a4_dark_night")["requires"]["steps"].has("a3_found_camp")).is_true()
	Region1State.clear()
	Places.clear()


func test_the_seasons_pass_card_ages_the_character_at_an_age_gate() -> void:
	Region1State.clear()
	var q := Region1StoryQuest.new()
	q.setup(WorldSim.SEED)
	q.load_quest("res://data/region1/quests/r1_main.json")
	Life.life_path.set_age(10, WorldSim.day, WorldSim.time_of_day)
	q.status["a1_blessing_eve"] = "active"
	var g := SeasonsPass.gate(q, {"age": 10})
	assert_str(String(g["kind"])).is_equal("age")
	assert_int(int(g["min"])).is_equal(12)
	var card := SeasonsPass.card(g)
	assert_str(String(card["title"])).is_equal("The seasons pass")
	assert_int((card["choices"] as Array).size()).is_equal(2)
	assert_dict(SeasonsPass.gate(q, {"age": 12})).is_empty()
	SeasonsPass.apply(g)
	assert_int(Life.age()).is_equal(12)
	assert_bool(SeasonsPass.gate(q, {"age": Life.age()}).is_empty()).is_true()
	Region1State.clear()


func test_the_seasons_pass_card_runs_the_calendar_to_kindling_night() -> void:
	Region1State.clear()
	var q := Region1StoryQuest.new()
	q.setup(WorldSim.SEED)
	q.load_quest("res://data/region1/quests/r1_main.json")
	q.status["a1_kindling"] = "active"
	var g := SeasonsPass.gate(q, {"age": 10})
	assert_str(String(g["kind"])).is_equal("festival")
	assert_str(String(g["festival"])).is_equal("kindling_night")
	var seen: Array = []
	var se: Node = WorldSim.seasons
	var cb := func(f: Dictionary) -> void: seen.append(String(f.get("id", "")))
	se.festival_started.connect(cb)
	var off0: int = se.day_offset
	SeasonsPass.apply(g)
	se.festival_started.disconnect(cb)
	assert_array(seen).is_equal(["kindling_night"])
	assert_str(String(se.festival_today().get("id", ""))).is_equal("kindling_night")
	assert_float(WorldSim.time_of_day).is_equal(SeasonsPass.EVENING_HOUR)
	se.day_offset = off0
	Region1State.clear()
