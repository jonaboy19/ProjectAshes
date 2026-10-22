extends GdUnitTestSuite
## Region 1 playtest follow-up: `a4_five_hearts` ("Route 3 ward-lines toward the Edge") and `a5_turn_the_tide` ("burn or ward 8 Scar
## cells") used to need forced events. Auto-linking filled the Rift's Edge camp stones (East 4, West 5, max 4), so a fresh world could
## not route three lines there. Here a fresh world, built the way the glue builds it, completes both steps through the same calls the
## menus make (`_link_menu` rows, `_make_link`, `scar_menu` rows, `_scar_burn`).

const Glue := preload("res://scripts/region1/region1_glue.gd")
const Director := preload("res://scripts/region1/r1_story_director.gd")
const Places := preload("res://scripts/region1/region1_places.gd")
const ScarTide := preload("res://scripts/region1/scar_tide.gd")
const Ward := preload("res://scripts/region1/wardlines.gd")
const ELDER_PREFIX := "Elder Stone ("
const ELDERS := ["elder_glade", "elder_greyseam", "elder_highwatch", "elder_crownstead", "elder_elden"]

var glue: Node
var dir: Node
var player: Node3D
var wl


class StubGlue extends Node:
	var tutorial = null
	func npc_extra_options(_id: String) -> Array:
		return []


func before_test() -> void:
	WorldGen.setup(1066)
	Region1State.clear()
	Places.clear()
	Life.life_path.set_age(30, WorldSim.day, WorldSim.time_of_day)
	for k in Life.life_path.flags.keys():
		if String(k).begins_with("r1."):
			Life.life_path.flags.erase(k)
	Frontier.reset()
	var net: RARunestoneNetwork = Frontier.runestones
	for id in ELDERS:
		var r := Places.resolve(id)
		var s := net.add_stone(r["pos"], 240.0, -1, ELDER_PREFIX + id + ")")
		s["elder"] = true
	glue = auto_free(Glue.new())
	glue._net = net
	wl = Ward.new().setup(1066)
	glue.wl = wl
	var scar := ScarTide.new()
	scar.setup(3)
	scar.start_day = 0
	scar.season_cb = func() -> int: return 1
	glue.scar = scar
	glue._ensure_story_stones(net)
	wl.bind_network(net, glue.elder_network_ids(net))
	glue._reserve_story_link_slots()
	player = auto_free(Node3D.new())
	player.add_to_group("player")
	add_child(player)
	glue.player = player
	var wnode: Node3D = auto_free(Node3D.new())
	add_child(wnode)
	glue.world = wnode
	dir = auto_free(Director.new())
	var stub: Node = auto_free(StubGlue.new())
	add_child(stub)
	add_child(dir)
	dir.setup(stub, null, player, auto_free(Node3D.new()))
	glue.story = dir


func after_test() -> void:
	Region1State.clear()
	Places.clear()


func _open_step(id: String) -> void:
	for s: Dictionary in dir.story.steps:
		if String(s["id"]) == id:
			break
		dir.story.status[String(s["id"])] = "done"
	dir.story.refresh(dir.ctx())
	assert_bool(dir.story.is_active(id)).override_failure_message("%s did not open" % id).is_true()


func _camp_stones() -> Array[int]:
	var out: Array[int] = []
	for s: Dictionary in glue._net.stones:
		if String(s["name"]).begins_with("Rift's Edge Stone"):
			out.append(int(s["id"]))
	return out


func test_a_fresh_world_leaves_room_to_route_three_lines_to_the_camp() -> void:
	var camp := _camp_stones()
	assert_int(camp.size()).is_equal(3)
	var free := 0
	for id in camp:
		free += wl.link_cap(id) - wl.degree(id)
	assert_int(free).override_failure_message("free link slots on the camp stones: %d" % free).is_greater_equal(3)


func test_a4_five_hearts_completes_through_the_link_menu() -> void:
	_open_step("a4_five_hearts")
	dir.set_flag("r1.a4.done")
	assert_str(String(dir.story.current_objective("a4_five_hearts").get("id", ""))).is_equal("lines")
	var made := 0
	# From each camp stone, take the first row the player's link list offers (a stone outside the camp, as a player would pick).
	for round in 6:
		for id in _camp_stones():
			var rows: Array = glue._link_menu(id)["options"]
			for o: Array in rows:
				if String(o[0]) == "Back" or String(o[0]).begins_with("No stone"):
					continue
				var msg: String = (o[1] as Callable).call()
				if msg.begins_with("The wardline hums"):
					made += 1
				break
			if dir.story.is_done("a4_five_hearts"):
				break
		if dir.story.is_done("a4_five_hearts"):
			break
	assert_int(made).is_greater_equal(3)
	assert_bool(dir.story.is_done("a4_five_hearts")).override_failure_message("a4_five_hearts not done after %d links: %s %s" % [made, dir.story.progress, Places.resolve("rifts_edge_camp")]).is_true()


func test_a4_counts_lines_made_from_outside_the_camp() -> void:
	_open_step("a4_five_hearts")
	dir.set_flag("r1.a4.done")
	var camp := _camp_stones()
	var made := 0
	for s: Dictionary in glue._net.stones:
		var j := int(s["id"])
		if camp.has(j) or String(s["name"]).begins_with(ELDER_PREFIX) or made >= 3:
			continue
		for id in camp:
			if wl._find_link(id, j) >= 0 or not (wl.st_pos[id] as Vector2).distance_to(wl.st_pos[j]) <= 700.0:
				continue
			if wl.degree(j) >= wl.link_cap(j) or wl.degree(id) >= wl.link_cap(id):
				continue
			if String(glue._make_link(j, id)).begins_with("The wardline hums"):
				made += 1
			break
	assert_int(made).is_equal(3)
	assert_bool(dir.story.is_done("a4_five_hearts")).is_true()


func test_a5_turn_the_tide_scar_cells_can_be_burned_by_a_player() -> void:
	_open_step("a5_turn_the_tide")
	var pos: Vector2 = Places.position_of("ashen_scar")
	glue._seed_outbreaks_for_step("a5_turn_the_tide")
	player.global_position = Vector3(pos.x, 0.0, pos.y)
	# First two objectives are the carve and the allies flag; the tide listens only after them.
	dir.set_flag("r1.a5.allies")
	dir.notify(&"carve", {"glyph": "ward", "stone": "scar_anchor", "amount": 1})
	assert_str(String(dir.story.current_objective("a5_turn_the_tide").get("id", ""))).is_equal("tide")
	var f: Vector2 = glue.scar.nearest_front(pos, 400.0)
	assert_bool(f != Vector2.INF).override_failure_message("no Scar front near the Ashen Scar").is_true()
	# The player walks to the front and uses the menu row.
	player.global_position = Vector3(f.x, 0.0, f.y)
	assert_bool(not glue._scar_finder(f).is_empty()).is_true()
	Life.give("firewood", 40)
	var rows: Array = glue.scar_menu(f)["options"]
	assert_bool(String(rows[0][0]).begins_with("Burn it back")).is_true()
	var burns := 0
	while not dir.story.is_done("a5_turn_the_tide") and burns < 8:
		f = glue.scar.nearest_front(pos, 400.0)
		if f == Vector2.INF:
			break
		player.global_position = Vector3(f.x, 0.0, f.y)
		(glue.scar_menu(f)["options"][0][1] as Callable).call()
		burns += 1
	assert_bool(dir.story.objective_done("a5_turn_the_tide", "tide")).override_failure_message("8 cells not contained after %d burns" % burns).is_true()
	assert_int(burns).is_less_equal(4)
