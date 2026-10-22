extends GdUnitTestSuite
## Region 1 blocker found by the story playtest: the "Kneel at the ashes" / "Face the Scar" prompts sit on the player (distance 0), so the
## interact picker chose them over a person standing beside the player: Mother, then Idra at the Pennick farm, could not be talked to.

const FollowStation := preload("res://scripts/region1/r1_follow_station.gd")
const Picker := preload("res://scripts/interaction/interaction_picker.gd")


func test_an_on_player_prompt_ranks_as_a_passer_by() -> void:
	var player: Node3D = auto_free(Node3D.new())
	player.add_to_group("player")
	add_child(player)
	var st: Node3D = auto_free(FollowStation.new("Test"))
	st.finder = func(pp: Vector2) -> Dictionary: return {"pos": pp, "at_player_height": true, "verb": "Kneel", "menu": func() -> Dictionary: return {}}
	add_child(st)
	st._process(1.0)
	assert_bool(st.has_meta("low_priority")).is_true()
	# the picker: the ashes (low priority, on the player) against a person 1.8 m ahead, faced
	var pos := Vector3.ZERO
	var facing := Vector3(0, 0, -1)
	var ash := {"id": "ash", "pos": pos, "low_priority": true}
	var npc := {"id": "npc", "pos": Vector3(0, 0, -1.8)}
	assert_str(String(Picker.pick(pos, facing, [ash, npc]).get("id", ""))).is_equal("npc")
	# alone, the ashes still work
	assert_str(String(Picker.pick(pos, facing, [ash]).get("id", ""))).is_equal("ash")


func test_a_stone_prompt_keeps_its_priority() -> void:
	var player: Node3D = auto_free(Node3D.new())
	player.add_to_group("player")
	add_child(player)
	var st: Node3D = auto_free(FollowStation.new("Test2"))
	st.finder = func(pp: Vector2) -> Dictionary: return {"pos": pp + Vector2(2, 0), "verb": "Read", "menu": func() -> Dictionary: return {}}
	add_child(st)
	WorldGen.setup(2024)
	st._process(1.0)
	assert_bool(st.has_meta("low_priority")).is_false()


const StoryDirector := preload("res://scripts/region1/r1_story_director.gd")


class StubGlue extends Node:
	var tutorial = null
	func npc_extra_options(_id: String) -> Array:
		return []


## Found by the story playtest: a choice that finishes a step mid-conversation made the director free the speaker's Station, and the open
## sheet then called a freed Station's menu on every rebuild.
func test_the_director_keeps_the_person_you_are_talking_to() -> void:
	var world: Node3D = auto_free(Node3D.new())
	var player: Node3D = auto_free(Node3D.new())
	player.add_to_group("player")
	add_child(world)
	add_child(player)
	var glue: Node = auto_free(StubGlue.new())
	add_child(glue)
	var dir: Node = auto_free(StoryDirector.new())
	add_child(dir)
	dir.setup(glue, null, player, world)
	dir.story.status.clear()
	var npc: Node3D = auto_free(Node3D.new())
	world.add_child(npc)
	dir._npcs["speaker@nowhere"] = npc
	dir._conv = {"npc": "speaker", "step": "x", "file": "", "node": "", "speaker": "speaker", "line": "", "options": []}
	dir._manage_npcs()
	assert_bool(dir._npcs.has("speaker@nowhere") and not npc.is_queued_for_deletion()).override_failure_message("freed mid-conversation").is_true()
	dir._conv = {}
	dir._manage_npcs()
	assert_bool(dir._npcs.has("speaker@nowhere")).is_false()


const ScarTide := preload("res://scripts/region1/scar_tide.gd")
const Glue := preload("res://scripts/region1/region1_glue.gd")


## Found by the story playtest (Act IV, Greyseam): burning the Scar back leaves ashes at its edge, and the ashes prompt (same on-player rank,
## name sorts first) hid "Face the Scar", so the next burn or the harvest could not be started there.
func test_the_scar_prompt_wins_over_the_ashes_at_its_edge() -> void:
	WorldGen.setup(2024)
	var glue: Node = auto_free(Glue.new())
	var scar := ScarTide.new()
	scar.setup(3)
	scar.start_day = 0
	scar.season_cb = func() -> int: return 1
	var at := Vector2(-500, 470)
	scar.seed_at(at, 3.0, "test")
	var front: Vector2 = scar.nearest_front(at, 80.0)
	assert_bool(front != Vector2.INF).is_true()
	glue.scar = scar
	var mem := AshMemory.new().setup(1) as AshMemory
	mem.begin_incident(&"fire", front, AshMemory.clock(), {}, true)
	glue.mem = mem
	glue.ash = auto_free(AshsightController.new())
	assert_bool(mem.incidents_near(front, 40.0).is_empty()).is_false()      # warm ashes lie at the edge
	assert_bool((glue._scar_finder(front) as Dictionary).is_empty()).is_false()
	assert_bool((glue._ash_finder(front) as Dictionary).is_empty()).is_true()   # so the Scar prompt is the only one on the player
	# away from every front the ashes are offered as before
	var far := front + Vector2(400, 0)
	mem.begin_incident(&"fire", far, AshMemory.clock(), {}, true)
	assert_bool((glue._ash_finder(far) as Dictionary).is_empty()).is_false()


## Found by the story playtest (Act IV, Greyseam): warm ashes near the Elder Stone (the burnt-back seam) took the on-player tie and the stone's
## own prompt, and with it "Relight the Elder Stone", could not be opened. The stone wins within reach; its menu still offers the kneel.
func test_a_stone_in_reach_wins_over_warm_ashes_and_offers_the_kneel() -> void:
	WorldGen.setup(2024)
	var glue: Node = auto_free(Glue.new())
	glue.wl = Wardlines.new()
	var net := RARunestoneNetwork.new()
	var at := Vector2(300, 300)
	var st: Dictionary = net.add_stone(at, 100.0, -1, "Test Stone")
	glue._net = net
	var mem := AshMemory.new().setup(1) as AshMemory
	mem.begin_incident(&"fire", at + Vector2(6, 0), AshMemory.clock(), {}, true)
	glue.mem = mem
	glue.ash = auto_free(AshsightController.new())
	var near := at + Vector2(1.5, 0)
	assert_bool((glue._stone_finder(near) as Dictionary).is_empty()).is_false()
	assert_bool((glue._ash_finder(near) as Dictionary).is_empty()).is_true()
	var texts: Array[String] = []
	for o: Array in glue.stone_menu(int(st["id"]))["options"]:
		texts.append(String(o[0]))
	assert_bool(texts.has("Kneel and read the ashes")).is_true()
	# out of the stone's reach the ashes are offered as before
	var away := at + Vector2(20, 0)
	assert_bool((glue._stone_finder(away) as Dictionary).is_empty()).is_true()
	assert_bool((glue._ash_finder(away) as Dictionary).is_empty()).is_false()


## Found by the story playtest (Act IV, Greyseam): an Elder Stone's raised ring keeps the player ~4.5 m from its centre, past the 3 m reach.
func test_an_elder_stone_is_reachable_from_beside_its_ring() -> void:
	WorldGen.setup(2024)
	var glue: Node = auto_free(Glue.new())
	glue.wl = Wardlines.new()
	var net := RARunestoneNetwork.new()
	var at := Vector2(300, 300)
	net.add_stone(at, 100.0, -1, "Elder Stone (Test)")
	net.add_stone(at + Vector2(200, 0), 100.0, -1, "Plain Stone")
	glue._net = net
	var pp := at + Vector2(4.5, 0)
	var found: Dictionary = glue._stone_finder(pp)
	assert_bool(found.is_empty()).is_false()
	assert_float((found["pos"] as Vector2).distance_to(pp)).is_less(2.0)    # inside the picker's range
	assert_bool((glue._stone_finder(at + Vector2(7.5, 0)) as Dictionary).is_empty()).is_true()
	# an ordinary stone keeps its 3 m reach
	assert_bool((glue._stone_finder(at + Vector2(200, 0) + Vector2(4.5, 0)) as Dictionary).is_empty()).is_true()
	assert_bool((glue._stone_finder(at + Vector2(200, 0) + Vector2(2.5, 0)) as Dictionary).is_empty()).is_false()


## Found by the story playtest (Act IV, Crownstead): "Link to a nearby stone" ran _link_menu, whose Dictionary the menu row ignored (a row only
## reports a message), so no stone could ever be linked from the menu. The row now opens the second page.
func test_the_link_row_opens_the_second_page() -> void:
	WorldGen.setup(2024)
	var glue: Node = auto_free(Glue.new())
	glue.wl = Wardlines.new()
	var net := RARunestoneNetwork.new()
	var st: Dictionary = net.add_stone(Vector2(300, 300), 100.0, -1, "Test Stone")
	glue._net = net
	var opened: Array = []
	var hud: Node = auto_free(_MenuSpy.new(opened))
	glue.hud = hud
	var link_opt: Array = []
	for o: Array in glue.stone_menu(int(st["id"]))["options"]:
		if String(o[0]).begins_with("Link to"):
			link_opt = o
	assert_bool(link_opt.is_empty()).is_false()
	var msg: Variant = (link_opt[1] as Callable).call()
	assert_bool(msg is String).is_true()          # what a row's action must return
	assert_int(opened.size()).is_equal(1)         # and the page was handed to the menu


class _MenuSpy extends Node:
	var opened: Array
	func _init(into: Array) -> void:
		opened = into
	func show_menu(src: Callable) -> void:
		opened.append(src)


## Found by the story playtest (Act V gate, "Route 3 ward-lines toward the Edge"): the link list offered stones already at their link limit,
## and the player's pick ended in "the link will not hold". The list now names only stones that can take the line.
func test_the_link_list_skips_full_stones() -> void:
	WorldGen.setup(2024)
	var glue: Node = auto_free(Glue.new())
	var w := Wardlines.new().setup(1) as Wardlines
	var net := RARunestoneNetwork.new()
	for k in 7:
		net.add_stone(Vector2(300 + 40 * k, 300), 100.0, -1, "S%d" % k)
	w.bind_network(net, PackedInt32Array([0]))
	glue.wl = w
	glue._net = net
	var full := 6
	for k in 6:
		if w.degree(full) < 4:
			w.add_link(full, k)
	assert_int(w.degree(full)).is_greater_equal(4)      # S6 holds its limit of wardlines
	var t := -1
	for k in 6:
		if w._find_link(full, k) < 0:
			t = k
	assert_int(t).is_greater_equal(0)                   # a stone S6 is not linked to
	var rows: Array[String] = []
	for o: Array in glue._link_menu(t)["options"]:
		rows.append(String(o[0]))
	assert_bool(rows.any(func(r: String) -> bool: return r.begins_with("S6"))).is_false()
	assert_bool(rows.size() > 1).is_true()              # the others are still offered (and "Back")
