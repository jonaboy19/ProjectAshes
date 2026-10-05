extends GdUnitTestSuite
## Thornfield as a place (docs/design/FOUNDATION_PLAN.md F8): the named roster bound to WorldSim rows, the lots the
## village life needs, the clue props, the events the real systems send to the quest bus, and the three F7 quests
## played through headless with real-ish nodes (hub, clues, barn figure, grain cart, talk menu).

const Roster := preload("res://scripts/world/thornfield/roster.gd")
const SliceTown := preload("res://scripts/world/thornfield/slice_town.gd")
const Sites := preload("res://scripts/world/thornfield/sites.gd")
const Clues := preload("res://scripts/world/thornfield/clues.gd")
const Livestock := preload("res://scripts/world/thornfield/livestock.gd")
const Hub := preload("res://scripts/world/thornfield/hub.gd")
const GrainCart := preload("res://scripts/world/thornfield/grain_cart.gd")
const BarnFigure := preload("res://scripts/world/thornfield/barn_figure.gd")
const WolfThreat := preload("res://scripts/world/thornfield/wolf_threat.gd")
const ThornTalk := preload("res://scripts/world/thornfield/thornfield_talk.gd")
const Talk := preload("res://scripts/quests/quest_talk.gd")
const Perception := preload("res://scripts/population/perception.gd")
const DialogueRunner := preload("res://scripts/sim/dialogue_runner.gd")

var _events: Array = []
var _bus_conn: Callable
var _time_before := 12.0
var _day_before := 1


func before() -> void:
	WorldGen.setup(WorldSim.SEED)
	WorldSim.reset()          # a clean population, and the roster bound to it


func before_test() -> void:
	QuestHub.reset()
	QuestBus.reset_shared()
	_events.clear()
	_time_before = WorldSim.time_of_day
	_day_before = WorldSim.day
	_bus_conn = func(t: StringName, d: Dictionary) -> void: _events.append([String(t), d])
	QuestBus.shared().fired.connect(_bus_conn)


func after_test() -> void:
	if QuestBus.shared().fired.is_connected(_bus_conn):
		QuestBus.shared().fired.disconnect(_bus_conn)
	QuestHub.reset()
	QuestBus.reset_shared()
	WorldSim.time_of_day = _time_before
	preload("res://scripts/core/node_pool.gd").clear_all()     # ambush wolves go back to the pool; free the idle bodies
	WorldSim.day = _day_before
	Perception.set_environment(12.0)


func _seen(type: String, key := "", value := "") -> Array:
	return _events.filter(func(e: Array) -> bool:
		return e[0] == type and (key == "" or String((e[1] as Dictionary).get(key, "")) == value))


func _player_at(p: Vector2) -> Node3D:
	var n := Node3D.new()
	var sc := GDScript.new()                  # a stand-in player: the properties the quest pump and the wolves read
	sc.source_code = "extends Node3D\nvar crouching := false\nvar dead := false\n"
	sc.reload()
	n.set_script(sc)
	n.add_to_group("player")
	add_child(n)
	n.global_position = Vector3(p.x, 0.0, p.y)
	return auto_free(n)


# ---------------------------------------------------------------- the roster
func test_roster_has_15_to_30_named_residents_with_everything_the_brief_asks() -> void:
	var list := Roster.residents()
	assert_int(list.size()).is_between(15, 30)
	var roles := {}
	for e: Dictionary in list:
		var id := String(e["id"])
		assert_str(String(e["name"])).is_not_empty()
		assert_int(int(e["age"])).is_greater(0)
		assert_int((e["traits"] as Array).size()).override_failure_message(id).is_between(2, 3)
		assert_bool(String(e["home"]) != "" and String(e["work"]) != "").override_failure_message(id).is_true()
		assert_bool((e["schedule"] as Array).is_empty()).override_failure_message(id).is_false()
		var d: Dictionary = e["dialogue"]
		assert_array(d["greeting"]).override_failure_message(id).is_not_empty()
		assert_array(d["rumour"]).override_failure_message(id).is_not_empty()
		assert_bool((d["opinions"] as Dictionary).is_empty()).override_failure_message(id).is_false()
		assert_bool((e["relationships"] as Dictionary).is_empty()).override_failure_message(id).is_false()
		for other: String in e["relationships"]:
			assert_bool(not Roster.entry(other).is_empty()).override_failure_message("%s -> %s" % [id, other]).is_true()
		for other2: String in d["opinions"]:
			assert_bool(not Roster.entry(other2).is_empty()).override_failure_message("%s opinion of %s" % [id, other2]).is_true()
		roles[String(e["role"])] = int(roles.get(String(e["role"]), 0)) + 1
	# The cast the brief lists.
	assert_int(int(roles.get("farmer", 0))).is_equal(4)
	assert_int(int(roles.get("guard", 0)) + int(roles.get("guard captain", 0))).is_equal(3)
	for r: String in ["brewer", "maltster", "blacksmith", "baker", "shopkeeper", "innkeeper", "miller", "herbalist", "drifter", "child", "elder"]:
		assert_int(int(roles.get(r, 0))).override_failure_message(r).is_greater(0)


func test_roster_binds_to_distinct_worldsim_people_in_thornfield() -> void:
	var rows := Roster.bind(true)
	var sid := Roster.settlement_id()
	assert_int(sid).is_greater_equal(0)
	var r: Vector2i = WorldSim.ranges[sid]
	var seen := {}
	for id: String in rows:
		var row := int(rows[id])
		assert_bool(row >= r.x and row < r.y).override_failure_message("%s row %d outside %s" % [id, row, r]).is_true()
		assert_bool(seen.has(row)).override_failure_message("row shared: " + id).is_false()
		seen[row] = true
		assert_str(WorldSim.person_name(row)).is_equal(String(Roster.entry(id)["name"]))
		assert_int(int(WorldSim.job[row])).is_equal(int(Roster.entry(id)["job"]))
		assert_str(Roster.id_of(row)).is_equal(id)
		assert_float(Roster.embody_weight(row)).is_less(1.0)
	assert_int(rows.size()).is_equal(Roster.residents().size() - 1)          # Hesta is the brewery station, not a row
	assert_bool(rows.has("hesta_thorne")).is_false()
	# Children are real child rows (the rest of the sim draws them small and has them play about the plaza).
	for kid: String in ["dilly_pennick", "pip_oakley", "wren_fenn"]:
		assert_bool(preload("res://scripts/population/npc_world.gd").is_child(int(rows[kid]))).override_failure_message(kid).is_true()
	# Everyone else is still an ordinary generated name.
	for i in range(r.x, r.x + 40):
		if not Roster.is_named(i):
			assert_float(Roster.embody_weight(i)).is_equal(1.0)
			assert_str(Roster.name_of(i)).is_empty()


func test_the_roster_seeds_warm_ties_into_the_social_graph() -> void:
	Roster.bind(true)
	var graph := preload("res://scripts/sim/npc_social_graph.gd").new()
	var n := Roster.seed_social_graph(graph, WorldSim.SEED)
	assert_int(n).is_greater(10)
	var bram := "worldsim:%d:%d" % [WorldSim.SEED, Roster.row_of("bram_oakley")]
	var tilda := "worldsim:%d:%d" % [WorldSim.SEED, Roster.row_of("tilda_fenn")]
	assert_float(graph.affinity(bram, tilda)).is_greater(5.0)
	assert_int(Roster.seed_social_graph(graph, WorldSim.SEED)).is_equal(0)       # idempotent
	# Rivals are not friends: Odo and Joss have no edge.
	assert_dict(graph.link("worldsim:%d:%d" % [WorldSim.SEED, Roster.row_of("odo_marsh")], "worldsim:%d:%d" % [WorldSim.SEED, Roster.row_of("joss_brannock")])).is_empty()


func test_named_people_walk_to_their_own_doors_and_keep_their_schedules() -> void:
	Roster.bind(true)
	var wilm := Roster.row_of("wilm_garrow")
	var smith := Roster.row_of("roderic_hale")
	var guard := Roster.row_of("ines_carrow")
	# Doors: home is a Thornfield house lot, work is the smithy lot / the barn.
	var smithy := SliceTown.building("thornfield_smithy")
	assert_bool(smithy.is_empty()).is_false()
	assert_float(Roster.spot(smith, 1).distance_to(smithy["door"])).is_less(1.2)
	assert_float(Roster.spot(wilm, 1).distance_to(Sites.door_of_site("thornfield_barn"))).is_less(1.2)
	assert_vector(Roster.spot(wilm, 2)).is_equal(Vector2.INF)         # other phases use the shared spots
	# Schedule overrides: Wilm is home at night (his body is the barn figure), Ines holds the night watch.
	assert_int(Roster.override_phase(wilm, 23.0, 1)).is_equal(0)
	assert_int(Roster.override_phase(wilm, 12.0, 1)).is_equal(2)
	assert_int(Roster.override_phase(guard, 2.0, 0)).is_equal(1)
	assert_int(Roster.override_phase(guard, 12.0, 1)).is_equal(1)       # untouched hours keep the baseline
	WorldSim.time_of_day = 23.0
	assert_int(WorldSim._current_phase(int(WorldSim.job[wilm]), wilm)).is_equal(0)
	assert_int(WorldSim._current_phase(int(WorldSim.job[guard]), guard)).is_equal(1)


func test_every_resident_has_a_dialogue_file_in_the_runner_format() -> void:
	for e: Dictionary in Roster.residents():
		if not bool(e.get("bind", true)):
			continue
		var d := DialogueRunner.load_file("thornfield/" + String(e["id"]))
		assert_bool(d.is_empty()).override_failure_message(String(e["id"])).is_false()
		var start := DialogueRunner.start_node(d)
		assert_bool(DialogueRunner.node_exists(d, start)).is_true()
		var ctx := {"tier": "stranger", "time": "morning", "child": false, "first": "X", "name": "X"}
		var line := DialogueRunner.pick_line(d, start, ctx, RandomNumberGenerator.new())
		assert_str(String(line.get("text", ""))).override_failure_message(String(e["id"])).is_not_empty()
		assert_bool(DialogueRunner.choices(d, start, ctx).size() >= 2).is_true()
		assert_bool(DialogueRunner.node_exists(d, "rumour")).is_true()
	var wilm := DialogueRunner.load_file("thornfield/wilm_garrow")
	assert_bool(DialogueRunner.node_exists(wilm, "confession") and DialogueRunner.node_exists(wilm, "bribe_paid")).is_true()


func test_the_talk_system_knows_them_by_the_ids_the_quests_use() -> void:
	Roster.bind(true)
	for id: String in ["wilm_garrow", "thornfield_miller"]:
		var info := Roster.info_for(Roster.row_of(id))
		assert_str(String(info["id"])).is_equal(id)
		assert_str(String(info["file"])).is_equal("thornfield/" + id)
	# The talk system's own identity lookup (VillageServices._npc_info) returns the roster person for a bound row.
	var sv := VillageServices.new()
	auto_free(sv)
	var wrow := Roster.row_of("wilm_garrow")
	var winfo: Dictionary = sv._npc_info({"id": "p%d" % wrow, "person": wrow})
	assert_str(String(winfo["id"])).is_equal("wilm_garrow")
	assert_str(String(winfo["name"])).is_equal("Wilm Garrow")
	assert_str(String(winfo["file"])).is_equal("thornfield/wilm_garrow")
	assert_str(String(winfo["role"])).is_equal("drifter")
	var plain := -1
	for i in range(WorldSim.ranges[Roster.settlement_id()].x, WorldSim.ranges[Roster.settlement_id()].y):
		if not Roster.is_named(i):
			plain = i
			break
	var pinfo: Dictionary = sv._npc_info({"id": "p%d" % plain, "person": plain})
	assert_str(String(pinfo["file"])).is_equal("villager")           # ordinary residents are unchanged
	assert_str(String(pinfo["id"])).is_equal("p%d" % plain)
	# Hesta is matched by the lower-cased, underscored name of her brewery station.
	assert_str(String(Roster.entry("hesta_thorne")["name"]).to_lower().replace(" ", "_")).is_equal("hesta_thorne")
	var r := QuestHub.runner()
	var opts: Array = []
	Talk.add_options(opts, {"id": "hesta_thorne", "name": "Hesta Thorne"})
	assert_int(opts.size()).is_equal(1)
	assert_str(String(opts[0][0])).contains("Ask about work")
	assert_bool(r.is_active("thornfield_spoiled_barley")).is_false()
	(opts[0][1] as Callable).call()
	assert_bool(r.is_active("thornfield_spoiled_barley")).is_true()


# ---------------------------------------------------------------- places
func test_the_planned_town_always_has_the_lots_the_village_needs() -> void:
	var s := SliceTown.town()
	assert_bool(s.is_empty()).is_false()
	for t: String in SliceTown.REQUIRED_TYPES:
		assert_array(SliceTown.lots_of_type(t)).override_failure_message("no %s lot" % t).is_not_empty()
	# One blacksmith is forced and the inn is a real inn building.
	var smithy := SliceTown.building("thornfield_smithy")
	assert_str(String(smithy["asset"])).is_equal("blacksmith")
	assert_str(String(SliceTown.building("thornfield_inn")["asset"])).is_equal("inn")
	assert_int(SliceTown.lots_of_type("house").size()).is_greater_equal(15)
	# Every tagged lot is a real lot with a door.
	for bid: String in s["plan"]["slice"]["buildings"]:
		var b: Dictionary = s["plan"]["slice"]["buildings"][bid]
		var lot: Dictionary = s["plan"]["lots"][int(b["lot"])]
		assert_str(String(lot["bid"])).is_equal(bid)
		assert_str(String(lot["btype"])).is_equal(String(b["type"]))
		assert_vector(Vector2(b["door"])).is_not_equal(Vector2.INF)


func test_the_lots_are_forced_for_any_seed() -> void:
	var s := SliceTown.town()
	for seed_value: int in [1, 77, 4242, 90210]:
		var plan := CityPlanner.plan(s, WorldGen.gate_angles(s), seed_value)
		for t: String in SliceTown.REQUIRED_TYPES:
			var found := false
			for lot: Dictionary in plan["lots"]:
				if String(lot.get("btype", "")) == t:
					found = true
			assert_bool(found).override_failure_message("seed %d has no %s" % [seed_value, t]).is_true()


func test_other_towns_are_left_alone() -> void:
	for s in WorldGen.settlements:
		if String(s["name"]) != "Thornfield":
			assert_bool((s["plan"] as Dictionary).has("slice")).is_false()


func test_brewery_farm_fields_mill_livestock_and_den_exist() -> void:
	assert_bool(Sites.brewery().is_empty()).is_false()
	var farm := Sites.farm()
	assert_bool(farm.is_empty()).is_false()
	var crops := 0
	var has_mill := false
	var has_sty := false
	var has_coop := false
	for p: Array in farm["parts"]:
		if String(p[0]).begins_with("farm/crop_"):
			crops += 1
		has_mill = has_mill or String(p[0]) == "farm/windmill"
		has_sty = has_sty or String(p[0]) == "farm/pig_sty"
		has_coop = has_coop or String(p[0]) == "farm/chicken_coop"
	assert_int(crops).is_greater_equal(8)                      # field rows
	assert_bool(has_mill and has_sty and has_coop).is_true()
	var kinds := {}
	for g: Dictionary in Livestock.groups():
		for k: Array in g["kinds"]:
			kinds[String(k[0])] = true
			assert_bool(preload("res://scripts/actors/critter.gd").KINDS.has(String(k[0]))).override_failure_message(String(k[0])).is_true()
	assert_bool(kinds.has("sheep") and kinds.has("pig") and kinds.has("chicken")).is_true()
	var places := Sites.places()
	for id: String in ["thornfield", "thornfield_barn", "thornfield_fields", "thornfield_mill"]:
		assert_bool(places.has(id)).override_failure_message(id).is_true()
	# The wolf den: reuse a den within reach of the town or add one in the forest.
	var th := WolfThreat.new()
	add_child(auto_free(th))
	var den_id := th.ensure_den()
	assert_int(den_id).is_greater_equal(0)
	var den: Dictionary = Frontier.ecology.dens[den_id]
	assert_str(String(den["species"])).is_equal("wolf")
	assert_float((den["pos"] as Vector2).distance_to(Sites.settlement()["pos"])).is_less_equal(WolfThreat.DEN_RING.y)


# ---------------------------------------------------------------- clues
func test_the_four_clues_are_placed_around_the_brewery_and_barn() -> void:
	var holder := Node3D.new()
	add_child(auto_free(holder))
	var placed := Clues.build(holder)
	assert_int(placed.size()).is_equal(4)
	var ids := []
	for c: Node in placed:
		ids.append(String(c.get("clue_id")))
		assert_bool(Interactable.component_of(c) != null).is_true()
		assert_bool((c as Node3D).global_position.distance_to(Vector3(Sites.place_pos("thornfield_barn").x, (c as Node3D).global_position.y, Sites.place_pos("thornfield_barn").y)) < 20.0).is_true()
		# Subtle: no light, no marker node.
		assert_array(c.find_children("*", "Light3D", true, false)).is_empty()
	ids.sort()
	var want := Clues.IDS.duplicate()
	want.sort()
	assert_array(ids).is_equal(want)
	for id: String in ["thornfield/clue/sack", "thornfield/clue/prints", "thornfield/clue/lock", "thornfield/clue/ledger"]:
		assert_bool(Clues.specs().has(id)).is_true()
	# Examining fires the interact event the Investigate objective counts.
	(placed[0] as Node).call("examine")
	assert_int(_seen("interact", "id", String(placed[0].get("clue_id"))).size()).is_equal(1)


# ---------------------------------------------------------------- events reach the bus
func test_a_cart_arriving_and_dying_reach_the_quest_bus() -> void:
	var route := PackedVector2Array([Sites.door_of_site("thornfield_barn"), Sites.door_of_site("thornfield_mill")])
	var player := _player_at(route[0])
	var cart: Node3D = auto_free(GrainCart.new())
	add_child(cart)
	cart.call("place_at", route[0])
	cart.call("start_route", route)
	for i in 400:
		player.global_position = Vector3(cart.global_position.x, 0.0, cart.global_position.z)     # the player walks beside it
		cart._physics_process(1.0)
		if bool(cart.get("finished")):
			break
	assert_bool(bool(cart.get("finished"))).is_true()
	var arrived := _seen("arrive", "actor", "grain_cart_1")
	assert_int(arrived.size()).is_equal(1)
	assert_str(String(arrived[0][1]["place"])).is_equal("thornfield_mill")
	assert_bool(_seen("actor_pos").is_empty()).is_false()
	# A second cart is killed by wolves' bites: `died {actor}` and the destroyed signal.
	var c2: Node3D = auto_free(GrainCart.new())
	add_child(c2)
	c2.call("place_at", route[0])
	c2.call("take_damage", 500)
	assert_bool(bool(c2.get("dead"))).is_true()
	assert_int(_seen("died", "actor", "grain_cart_1").size()).is_equal(1)


func test_a_villager_dying_fires_died_with_the_roster_id() -> void:
	Roster.bind(true)
	var row := Roster.row_of("tam_birch")
	WorldSim.kill_person(row)
	assert_int(_seen("died", "actor", "tam_birch").size()).is_equal(1)
	assert_int(_seen("died", "actor", "p%d" % row).size()).is_equal(1)
	# An ordinary resident dies as pNNN.
	var plain := -1
	for i in range(WorldSim.ranges[Roster.settlement_id()].x, WorldSim.ranges[Roster.settlement_id()].y):
		if not Roster.is_named(i) and WorldSim.health[i] != 0:
			plain = i
			break
	WorldSim.kill_person(plain)
	assert_int(_seen("died", "actor", "p%d" % plain).size()).is_equal(1)
	WorldSim.reset()          # the dead are alive again for the next test


func test_giving_goods_to_the_miller_fires_deliver_and_a_wolf_kill_fires_kill_and_died() -> void:
	Roster.bind(true)
	Life.give("barley", 4)
	var info := Roster.info_for(Roster.row_of("thornfield_miller"))
	assert_str(ThornTalk.hand_over(info, "barley", 4)).contains("hand over")
	var d := _seen("deliver", "to", "thornfield_miller")
	assert_int(d.size()).is_equal(1)
	assert_str(String(d[0][1]["item"])).is_equal("barley")
	assert_int(int(d[0][1]["amount"])).is_equal(4)
	assert_int(Life.count("barley")).is_equal(0)
	assert_str(ThornTalk.hand_over(info, "barley", 1)).contains("do not have")
	var hub: Node = auto_free(Hub.new())
	add_child(hub)
	var f := Sites.place_pos("thornfield_fields")
	Life.region1_kill.emit("wolf", Vector3(f.x, 0.0, f.y))
	assert_int(_seen("kill", "place", "thornfield_fields").size()).is_equal(1)
	assert_int(_seen("died", "actor", "wolf").size()).is_equal(1)


func test_entering_the_places_fires_enter_area_once_per_visit() -> void:
	var hub: Node = auto_free(Hub.new())
	add_child(hub)
	var player := _player_at(Sites.place_pos("thornfield_mill"))
	hub.call("poll", 0.5)
	assert_int(_seen("enter_area", "place", "thornfield_mill").size()).is_equal(1)
	hub.call("poll", 0.5)
	assert_int(_seen("enter_area", "place", "thornfield_mill").size()).is_equal(1)      # still inside: re-sent only every couple of seconds
	player.global_position = Vector3(Sites.place_pos("thornfield_barn").x, 0.0, Sites.place_pos("thornfield_barn").y)
	hub.call("poll", 0.5)
	assert_int(_seen("enter_area", "place", "thornfield_barn").size()).is_equal(1)


func test_the_wolves_can_be_given_the_cart_as_prey() -> void:
	var cart: Node3D = auto_free(GrainCart.new())
	add_child(cart)
	cart.call("place_at", Sites.door_of_site("thornfield_barn"))
	var th := WolfThreat.new()
	add_child(auto_free(th))
	th.ensure_den()
	var pack: Array = th.ambush(cart, 3)
	assert_int(pack.size()).is_equal(3)
	for w: Node3D in pack:
		assert_bool(w.has_meta("prey") and w.get_meta("prey") == cart).is_true()
		assert_str(String(w.get("species"))).is_equal("wolf")
		# With no player about, the quarry is the cart; a player standing next to the wolf takes the quarry back.
		assert_object(w.call("_quarry")).is_equal(cart)
	var near := _player_at(Vector2(pack[0].global_position.x + 2.0, pack[0].global_position.z))
	near.global_position.y = pack[0].global_position.y
	assert_object(pack[0].call("_quarry")).is_equal(near)
	th.clear_ambush()


# ---------------------------------------------------------------- the quest line, played headless
func test_the_whole_quest_line_completes_with_real_nodes() -> void:
	Roster.bind(true)
	var r := QuestHub.runner()
	var hub: Node = auto_free(Hub.new())
	add_child(hub)
	var pump: Node = hub.get("pump")
	var fig: Node3D = hub.get("figure")
	assert_object(fig).is_not_null()
	var brewery_front := Sites.to_world(Sites.brewery(), Sites.BARN_DOOR)
	var player := _player_at(brewery_front)

	# 1. Hesta offers the work; the barn gives up three clues.
	var hesta: Array = []
	Talk.add_options(hesta, {"id": "hesta_thorne", "name": "Hesta Thorne"})
	(hesta[0][1] as Callable).call()
	assert_str(r.stage_of("thornfield_spoiled_barley")).is_equal("clues")
	var clues: Array = hub.get("clues")
	for i in 3:
		(clues[i] as Node).call("examine")
	assert_str(r.stage_of("thornfield_spoiled_barley")).is_equal("stakeout")

	# 2. Dusk: the pump turns world hours into Wait; then the figure at the barn is watched from the dark.
	WorldSim.hour_changed.emit(19)
	WorldSim.hour_changed.emit(20)
	WorldSim.time_of_day = 23.0
	Perception.set_environment(23.0)
	fig.call("_set_awake", true)
	fig.rotation.y = 0.0
	var behind: Vector2 = fig.call("xz") - fig.call("watch_facing") * 11.0         # behind his back, outside his cone
	player.global_position = Vector3(behind.x, 0.0, behind.y)
	for i in 60:
		pump._process(0.6)
	assert_str(r.stage_of("thornfield_spoiled_barley")).is_equal("report")
	var rep := Talk.options_for(r, "hesta_thorne")
	assert_int(rep.size()).is_equal(1)
	(rep[0][1] as Callable).call()
	assert_bool(r.is_done("thornfield_spoiled_barley")).is_true()

	# 3. Wilm's offer: find him at the barn, hear him out, turn him in, tell Hesta.
	assert_int(r.offers_for("hesta_thorne").size()).is_equal(2)
	var culprit_offer := Talk.options_for(r, "hesta_thorne").filter(func(o: Array) -> bool: return String(o[0]).contains("Wilm"))
	(culprit_offer[0][1] as Callable).call()
	assert_str(r.stage_of("thornfield_the_culprit")).is_equal("confront")
	var wilm_info := Roster.info_for(Roster.row_of("wilm_garrow"))
	assert_bool(ThornTalk.ctx_extra(wilm_info)["thornfield_confront"]).is_true()
	player.global_position = Vector3(brewery_front.x, 0.0, brewery_front.y)
	hub.call("poll", 0.5)                         # enter_area thornfield_barn
	ThornTalk.on_node(wilm_info, "confession")    # the talk menu entering his confession node
	assert_str(r.stage_of("thornfield_the_culprit")).is_equal("verdict")
	var verdict := Talk.options_for(r, "wilm_garrow")
	assert_int(verdict.size()).is_equal(2)
	(verdict.filter(func(o: Array) -> bool: return String(o[0]).contains("turning him in"))[0][1] as Callable).call()
	assert_str(r.stage_of("thornfield_the_culprit")).is_equal("turned_in")
	var told := Talk.options_for(r, "hesta_thorne").filter(func(o: Array) -> bool: return String(o[0]).begins_with("Report"))
	(told[0][1] as Callable).call()
	assert_bool(r.is_done("thornfield_the_culprit")).is_true()

	# 4. The grain carts: load four sacks at the barn, hold off the wolves, take the cart to the mill, hand the barley over.
	var carts := Talk.options_for(r, "hesta_thorne").filter(func(o: Array) -> bool: return String(o[0]).contains("Grain"))
	(carts[0][1] as Callable).call()
	assert_str(r.stage_of("thornfield_grain_carts")).is_equal("load")
	assert_bool(hub.call("store_available")).is_true()
	hub.call("take_barley")
	assert_bool(hub.call("store_available")).is_false()
	assert_str(r.stage_of("thornfield_grain_carts")).is_equal("guard")
	hub.call("poll", 0.5)
	var cart: Node3D = hub.get("cart")
	assert_object(cart).is_not_null()
	var threat: Node = hub.get("threat")
	assert_int((threat.get("ambush_wolves") as Array).size()).is_equal(3)
	for i in 3:
		Life.region1_kill.emit("wolf", Vector3(brewery_front.x, 0.0, brewery_front.y))
	WorldSim.hour_changed.emit(21)
	assert_str(r.stage_of("thornfield_grain_carts")).is_equal("road")
	hub.call("poll", 0.5)
	assert_bool(bool(cart.get("moving"))).is_true()
	var mill := Sites.door_of_site("thornfield_mill")
	for i in 600:
		var cp := Vector2(cart.global_position.x, cart.global_position.z)
		player.global_position = Vector3(cp.x, 0.0, cp.y)           # the player walks beside the cart
		cart._physics_process(1.0)
		if bool(cart.get("finished")):
			break
	assert_str(r.stage_of("thornfield_grain_carts")).is_equal("mill")
	var miller_opts: Array = []
	ThornTalk.add_options(miller_opts, Roster.info_for(Roster.row_of("thornfield_miller")))
	assert_int(miller_opts.size()).is_equal(1)
	assert_str(String(miller_opts[0][0])).contains("barley")
	(miller_opts[0][1] as Callable).call()
	assert_bool(r.is_done("thornfield_grain_carts")).is_true()
	assert_float(mill.distance_to(Vector2(cart.global_position.x, cart.global_position.z))).is_less(6.0)
	for w: Variant in threat.get("ambush_wolves"):
		if is_instance_valid(w):
			w.queue_free()


# ---------------------------------------------------------------- playtest fixes (tools_qa/playtest_bot, tf_* stages)
func test_hesta_is_a_station_with_her_own_dialogue_and_talk_identity() -> void:
	var info := Roster.info_for_id("hesta_thorne")
	assert_str(String(info["file"])).is_equal("thornfield/hesta_thorne")
	assert_bool(DialogueRunner.load_file("thornfield/hesta_thorne").is_empty()).is_false()
	var sv := VillageServices.new()
	auto_free(sv)
	var hi: Dictionary = sv._npc_info({"id": "hesta_thorne", "name": "Hesta Thorne"})
	assert_str(String(hi["file"])).is_equal("thornfield/hesta_thorne")
	assert_str(String(hi["role"])).is_equal("brewmistress")
	var hub: Node = auto_free(Hub.new())
	add_child(hub)
	var hesta: Node3D = hub.get("hesta")
	assert_object(hesta).is_not_null()
	assert_str(String(hesta.get("title"))).is_equal("Hesta Thorne")
	assert_bool(hesta.is_in_group("interactable")).is_true()


func test_there_is_one_quest_pump_per_world() -> void:
	# two pumps (village services + the Thornfield hub) used to double every hours / observe event
	var QuestPump := preload("res://scripts/quests/quest_pump.gd")
	var host := Node.new()
	add_child(host)
	auto_free(host)
	var p1: Node = QuestPump.attach(host)
	var p2: Node = QuestPump.attach(host)
	assert_object(p2).is_same(p1)


func test_named_residents_are_inside_their_own_homes_not_the_hash_lot() -> void:
	Roster.bind(true)
	var Household := preload("res://scripts/interiors/household.gd")
	var sid := Roster.settlement_id()
	var lots: Array = (SliceTown.town()["plan"]["lots"] as Array)
	var home: Dictionary = SliceTown.building("thornfield_house_8")
	var maud := Roster.row_of("maud_pennick")
	assert_bool(Roster.rows_at(sid, int(home["lot"]), 0).has(maud)).is_true()
	var appears_in := 0
	for li in lots.size():
		var list := Household.roster_for_lot({"sid": sid, "lot": li, "count": lots.size()}, 23.0, "house")
		if list.any(func(e: Dictionary) -> bool: return int(e["person"]) == maud):
			appears_in += 1
			assert_int(li).is_equal(int(home["lot"]))
	assert_int(appears_in).is_equal(1)
	# the blacksmith works in the smithy lot, not in whatever lot the hash formula picks
	var smithy: Dictionary = SliceTown.building("thornfield_smithy")
	assert_bool(Roster.rows_at(sid, int(smithy["lot"]), 1).has(Roster.row_of("roderic_hale"))).is_true()


func test_a_shop_door_does_not_say_house() -> void:
	var BP := preload("res://scripts/world/building_profiles.gd")
	assert_str(BP.prompt("mhouse_trader")).is_equal("Enter the shop")
	assert_str(BP.prompt("inn")).is_equal("Enter the inn")
	assert_str(BP.prompt("house_13")).is_equal("Enter the house")


func test_modular_keepers_use_looks_the_asset_loader_knows() -> void:
	var Lay := preload("res://scripts/interiors/interior_layouts.gd")
	for id: String in Lay.all_ids():
		for n: Dictionary in (Lay.layout(id)["npcs"] as Array):
			var look := String(n["look"])
			assert_bool(Assets.MH_LOOKS.has(look) or Assets.LOOKS.has(look) or FileAccess.file_exists("res://assets/kaykit/characters/%s.glb" % look)).override_failure_message("%s: look '%s'" % [id, look]).is_true()

