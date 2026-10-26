extends GdUnitTestSuite
## READY_V1 C3, the found-a-camp flow: the site card (founding.evaluate_site + land_claim), the name and the C2 claim behind it,
## the Act 3 step a3_found_camp (gate order, the flag the flow sets), its tutorial prompt and the "seasons pass" card that
## replaces the bot's age / Kindling Night hooks (sleeping at a story gate).

const Hub := preload("res://scripts/realm/realm_hub.gd")
const BuildKit := preload("res://scripts/realm/build_kit.gd")
const LandClaim := preload("res://scripts/realm/land_claim.gd")
const FoundCamp := preload("res://scripts/ui/found_camp.gd")
const Director := preload("res://scripts/region1/r1_story_director.gd")
const Tutorial := preload("res://scripts/region1/tutorial_director.gd")
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


## Open ground that LandClaim allows and the founding module accepts, at least 500 m apart.
func _spots(hub: RefCounted, n: int) -> Array:
	var fd: RefCounted = hub.mod("founding")
	var out: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 91
	for _i in 6000:
		if out.size() >= n:
			break
		var p := Vector2(rng.randf_range(-3000.0, 3000.0), rng.randf_range(-3000.0, 3000.0))
		if LandClaim.block_reason(p) != "":
			continue
		var ev: Dictionary = fd.evaluate_site(p)
		if String(ev["blocked"]) != "" or float(ev["overall"]) < 0.3 or float(ev["camp"]) < float(hub.mod("camps").MIN_CAMP_SCORE):
			continue
		var far := true
		for q: Vector2 in out:
			far = far and q.distance_to(p) > 500.0
		if far:
			out.append(p)
	return out


func before_test() -> void:
	Life.life_path.flags.erase(FoundCamp.FOUNDED_FLAG)


# ------------------------------------------------------------------ the card and the claim

func test_card_for_good_ground_can_found_and_offers_a_name() -> void:
	var hub := _mk()
	var spot: Vector2 = _spots(hub, 1)[0]
	var card: Dictionary = FoundCamp.site_card(hub.mod("build_kit"), spot)
	assert_bool(bool(card["can"])).override_failure_message(String(card["reason"])).is_true()
	assert_str(String(card["reason"])).is_empty()
	assert_int(int(card["slots_left"])).is_equal(BuildKit.MAX_GRIDS)
	assert_array(card["lines"]).has_size(10)       # water, food, resources, defence, trade, legality, risk, safety, climate, room
	assert_str(String(card["default_name"])).is_not_empty()
	assert_str(String(card["verdict"])).is_not_empty()


func test_card_refuses_ground_the_claim_law_blocks() -> void:
	var hub := _mk()
	var town: Dictionary = WorldGen.settlements[0]
	var card: Dictionary = FoundCamp.site_card(hub.mod("build_kit"), town["pos"])
	assert_bool(bool(card["can"])).is_false()
	assert_str(String(card["reason"])).contains("Too close")
	# the founding attempt is refused the same way and starts nothing
	var res: Dictionary = FoundCamp.found(hub.mod("build_kit"), town["pos"], "Nope")
	assert_bool(bool(res["ok"])).is_false()
	assert_int(hub.mod("founding").active_count("player")).is_equal(0)
	assert_bool(Life.life_path.flags.has(FoundCamp.FOUNDED_FLAG)).is_false()


func test_found_makes_one_settlement_sets_the_flag_and_names_it() -> void:
	var hub := _mk()
	var spot: Vector2 = _spots(hub, 1)[0]
	var bk: RefCounted = hub.mod("build_kit")
	var res: Dictionary = FoundCamp.found(bk, spot, "  Ash   hold \n")
	assert_bool(bool(res["ok"])).override_failure_message(String(res["reason"])).is_true()
	assert_str(String(res["name"])).is_equal("Ash hold")
	assert_int(hub.mod("founding").active_count("player")).is_equal(1)
	var rows: Array = hub.player_settlements()
	assert_int(rows.size()).is_equal(1)
	assert_int(int(rows[0]["gid"])).is_equal(int(res["gid"]))
	assert_int(int(rows[0]["fid"])).is_equal(int(res["fid"]))
	assert_bool(Life.life_path.flags.has(FoundCamp.FOUNDED_FLAG)).is_true()
	# standing in the camp now: the card says so and a second founding is refused
	var again: Dictionary = FoundCamp.site_card(bk, spot)
	assert_bool(bool(again["can"])).is_false()
	assert_str(String(again["reason"])).contains("already hold")
	assert_bool(bool(FoundCamp.found(bk, spot, "Twice")["ok"])).is_false()
	assert_int(hub.player_settlements().size()).is_equal(1)


func test_blank_name_falls_back_to_the_suggested_one_and_names_are_cleaned() -> void:
	var hub := _mk()
	var spot: Vector2 = _spots(hub, 1)[0]
	var suggested := String(FoundCamp.site_card(hub.mod("build_kit"), spot)["default_name"])
	var res: Dictionary = FoundCamp.found(hub.mod("build_kit"), spot, "   ")
	assert_bool(bool(res["ok"])).is_true()
	assert_str(String(res["name"])).is_equal(suggested)
	assert_str(FoundCamp.clean_name("a".repeat(60))).has_length(FoundCamp.NAME_MAX)
	assert_str(FoundCamp.clean_name("\tNew\n  Haven ")).is_equal("New Haven")


func test_fourth_camp_is_refused_by_the_card() -> void:
	var hub := _mk()
	var spots := _spots(hub, 4)
	var bk: RefCounted = hub.mod("build_kit")
	for i in BuildKit.MAX_GRIDS:
		assert_bool(bool(FoundCamp.found(bk, spots[i], "")["ok"])).is_true()
	var card: Dictionary = FoundCamp.site_card(bk, spots[3])
	assert_int(int(card["slots_left"])).is_equal(0)
	assert_bool(bool(card["can"])).is_false()
	assert_str(String(card["reason"])).contains("at most 3")
	# giving one up reopens the slot
	bk.abandon(int((hub.player_settlements()[0] as Dictionary)["gid"]))
	assert_bool(bool(FoundCamp.site_card(bk, spots[3])["can"])).is_true()


func test_the_card_opens_on_a_hud_and_walks_card_name_claim() -> void:
	var hub := _mk()
	var spot: Vector2 = _spots(hub, 1)[0]
	var host: Control = auto_free(Control.new())
	var pl: Node3D = auto_free(Node3D.new())
	add_child(host)
	add_child(pl)
	pl.global_position = Vector3(spot.x, 0.0, spot.y)
	var ui: Control = auto_free((load("res://scripts/ui/found_camp.gd") as GDScript).new())
	host.add_child(ui)
	ui.hud = host
	ui.kit = hub.mod("build_kit")
	ui.card = FoundCamp.site_card(ui.kit, spot)
	ui._show_card()
	assert_bool(ui._row.get_child(0).disabled).is_false()
	ui._to_name()
	assert_str(ui._name_edit.text).is_equal(String(ui.card["default_name"]))
	ui._name_edit.text = "Emberfall"
	var got: Array = []
	ui.founded.connect(func(r: Dictionary) -> void: got.append(r))
	ui.visible = true
	ui._submit()
	assert_int(got.size()).is_equal(1)
	assert_str(String(got[0]["name"])).is_equal("Emberfall")
	assert_int(hub.player_settlements().size()).is_equal(1)
	get_tree().paused = false


# ------------------------------------------------------------------ the Act 3 step

func _quest() -> Region1StoryQuest:
	var q := Region1StoryQuest.new()
	q.setup(1)
	q.load_quest(Director.QUEST_PATH)
	return q


func test_step_a3_found_camp_sits_between_the_council_and_the_scar() -> void:
	var q := _quest()
	var s: Dictionary = q.step("a3_found_camp")
	assert_bool(s.is_empty()).is_false()
	assert_int(int(s["act"])).is_equal(3)
	assert_array(s["requires"]["steps"]).is_equal(["a3_council"])
	assert_array(q.step("a3_scar_front")["requires"]["steps"]).contains(["a3_found_camp"])
	assert_array(s["tutorial"]).is_equal(["found_camp"])
	assert_bool(Tutorial.PROMPTS.has("found_camp")).is_true()


func test_the_scar_front_waits_for_the_camp_and_the_flag_completes_the_step() -> void:
	var q := _quest()
	var ctx := {"age": 16, "flags": {}, "items": {}, "child": false, "vars": {}}
	for id in ["a3_council"]:
		q.status[id] = "done"
	q.status["a3_sunstone_oil"] = "done"
	q.refresh(ctx)
	assert_bool(q.is_active("a3_found_camp")).is_true()
	assert_bool(q.is_active("a3_scar_front")).override_failure_message("the Scar front opened before the camp").is_false()
	# the flow sets the life flag; the quest reads it through the ctx like every game flag
	ctx["flags"][FoundCamp.FOUNDED_FLAG] = true
	q.refresh(ctx)
	assert_bool(q.is_done("a3_found_camp")).is_true()
	assert_bool(q.is_active("a3_scar_front")).is_true()


func test_the_tutorial_prompt_shows_on_open_ground_and_ends_on_the_real_action() -> void:
	var d := Tutorial.new()
	for id in ["move", "look", "talk", "interact", "eat", "sleep", "fight", "block", "dodge", "carve", "map", "ashsight"]:
		d.skip(StringName(id))
	d.update({"can_control": true, "can_found": false}, 1.0)
	assert_str(String(d.current)).is_empty()
	d.update({"can_control": true, "can_found": true}, 1.0)
	assert_str(String(d.current)).is_equal("found_camp")
	Tutorial.tell(&"found_camp")      # static: reaches the director set with make_main()
	d.make_main()
	d.notify(&"found_camp", 1.0)
	d.update({"can_control": true, "can_found": true}, 1.0)
	assert_bool(d.is_done(&"found_camp")).is_true()
	Tutorial.main = null


# ------------------------------------------------------------------ the seasons pass

func _director() -> Node:
	Region1State.clear()
	Places.clear()
	var world: Node3D = auto_free(Node3D.new())
	var player: Node3D = auto_free(Node3D.new())
	player.add_to_group("player")
	add_child(world)
	add_child(player)
	Life.life_path.set_age(8, WorldSim.day, WorldSim.time_of_day)
	for k in Life.life_path.flags.keys():
		if String(k).begins_with("r1.") or String(k).begins_with("ember."):
			Life.life_path.flags.erase(k)
	var dir: Node = auto_free(Director.new())
	var glue: Node = auto_free(StubGlue.new())
	add_child(glue)
	add_child(dir)
	dir.setup(glue, null, player, world)
	return dir


func test_no_card_without_an_open_gate() -> void:
	var dir := _director()
	Life.life_path.set_age(12, WorldSim.day, WorldSim.time_of_day)      # old enough for the story to be open at its first step
	dir._on_tick()
	assert_dict(dir.seasons_gate()).is_empty()
	assert_dict(dir.seasons_card()).is_empty()
	Region1State.clear()


func test_the_story_opening_age_is_a_gate_too() -> void:
	var dir := _director()
	Life.life_path.set_age(4, WorldSim.day, WorldSim.time_of_day)
	dir._on_tick()
	var g: Dictionary = dir.seasons_gate()
	assert_str(String(g.get("kind", ""))).is_equal("age")
	assert_int(int(g["min"])).is_equal(8)
	((dir.seasons_card()["choices"] as Array)[0][1] as Callable).call()
	assert_int(Life.age()).is_greater_equal(8)
	assert_bool(dir.story.is_active("a1_dark_stone")).is_true()
	Region1State.clear()


func test_age_gate_card_ages_the_character_instead_of_a_bot_hook() -> void:
	var dir := _director()
	dir.story.status["a1_blessing_eve"] = "active"
	dir.story.progress["a1_blessing_eve"] = {}
	var g: Dictionary = dir.seasons_gate()
	assert_str(String(g.get("kind", ""))).is_equal("age")
	assert_int(int(g["min"])).is_equal(12)
	var card: Dictionary = dir.seasons_card()
	assert_str(String(card["title"])).is_equal("The seasons pass")
	assert_int((card["choices"] as Array).size()).is_equal(1)
	assert_int(Life.age()).is_less(12)
	((card["choices"] as Array)[0][1] as Callable).call()
	assert_int(Life.age()).is_greater_equal(12)
	assert_dict(dir.seasons_gate()).is_empty()
	Region1State.clear()


func test_festival_gate_card_starts_kindling_night() -> void:
	var dir := _director()
	dir.story.status["a1_kindling"] = "active"
	dir.story.progress["a1_kindling"] = {}
	var g: Dictionary = dir.seasons_gate()
	assert_str(String(g["kind"])).is_equal("festival")
	var seen: Array = []
	WorldSim.seasons.festival_started.connect(func(f: Dictionary) -> void: seen.append(String(f["id"])))
	((dir.seasons_card()["choices"] as Array)[0][1] as Callable).call()
	assert_array(seen).contains(["kindling_night"])
	Region1State.clear()


func test_sleeping_signal_exists_for_the_gate() -> void:
	assert_bool(Life.has_signal("slept")).is_true()
