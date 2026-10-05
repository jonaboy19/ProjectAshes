extends GdUnitTestSuite
## F1 interaction framework: the pure picker, the Interactable component and legacy wrapping, the single
## "interact" route (Interaction / InteractionController), and each new interactable kind's effect.

const Picker := preload("res://scripts/interaction/interaction_picker.gd")
const Container_ := preload("res://scripts/interaction/kinds/container.gd")
const InnProps := preload("res://scripts/interaction/kinds/inn_props.gd")
const InteractLabel := preload("res://scripts/ui/interact_label.gd")


# --- helpers ----------------------------------------------------------------------------------------

func _cand(id: String, pos: Vector3, extra := {}) -> Dictionary:
	var c := {"id": id, "pos": pos}
	c.merge(extra, true)
	return c


class FakePlayer extends Node3D:
	var dead := false
	var velocity := Vector3.ZERO
	var mounted_calls := 0
	func facing() -> Vector3:
		return Vector3(0, 0, 1)
	func toggle_mount(_t: Node3D = null) -> void:
		mounted_calls += 1


class LegacyThing extends Node3D:
	var uses := 0
	var text := "Open the thing"
	func _ready() -> void:
		add_to_group("interactable")
	func prompt() -> String:
		return text
	func use() -> void:
		uses += 1


func _player(at := Vector3.ZERO) -> FakePlayer:
	var p := FakePlayer.new()
	add_child(p)
	p.global_position = at
	auto_free(p)
	return p


# --- picker scoring ----------------------------------------------------------------------------------

func test_picker_nothing_in_reach() -> void:
	assert_dict(Picker.pick(Vector3.ZERO, Vector3.FORWARD, [])).is_empty()
	assert_dict(Picker.pick(Vector3.ZERO, Vector3.FORWARD, [_cand("far", Vector3(0, 0, 5))])).is_empty()


func test_picker_nearest_wins() -> void:
	var best := Picker.pick(Vector3.ZERO, Vector3(0, 0, 1), [_cand("far", Vector3(0, 0, 2.5)), _cand("near", Vector3(0, 0, 1.0))])
	assert_str(best["id"]).is_equal("near")


func test_picker_respects_per_candidate_range() -> void:
	var tight := _cand("tight", Vector3(0, 0, 1.5), {"range": 1.0})
	var wide := _cand("wide", Vector3(0, 0, 2.5), {"range": 4.0})
	assert_str(Picker.pick(Vector3.ZERO, Vector3(0, 0, 1), [tight, wide])["id"]).is_equal("wide")


func test_picker_facing_breaks_near_ties() -> void:
	var ahead := _cand("ahead", Vector3(0, 0, 1.6))
	var behind := _cand("behind", Vector3(0, 0, -1.5))     # slightly nearer, but behind the player
	assert_str(Picker.pick(Vector3.ZERO, Vector3(0, 0, 1), [behind, ahead])["id"]).is_equal("ahead")
	# Turn around and the other one wins.
	assert_str(Picker.pick(Vector3.ZERO, Vector3(0, 0, -1), [behind, ahead])["id"]).is_equal("behind")


func test_picker_facing_does_not_outweigh_a_much_closer_one() -> void:
	var close_behind := _cand("close", Vector3(0, 0, -0.8))
	var far_ahead := _cand("far", Vector3(0, 0, 3.0))
	assert_str(Picker.pick(Vector3.ZERO, Vector3(0, 0, 1), [far_ahead, close_behind])["id"]).is_equal("close")


func test_picker_priority_beats_slightly_nearer() -> void:
	var plain := _cand("plain", Vector3(0, 0, 1.0))
	var door := _cand("door", Vector3(0, 0, 1.8), {"priority": 1})
	assert_str(Picker.pick(Vector3.ZERO, Vector3(0, 0, 1), [plain, door])["id"]).is_equal("door")
	# ...but not when it is far out of proportion.
	var far_door := _cand("door", Vector3(0, 0, 3.1), {"priority": 1})
	assert_str(Picker.pick(Vector3.ZERO, Vector3(0, 0, 1), [plain, far_door])["id"]).is_equal("plain")


func test_picker_low_priority_penalty() -> void:
	var talk := _cand("talk", Vector3(0, 0, 1.0), {"low_priority": true})
	var door := _cand("door", Vector3(0, 0, 2.2))
	assert_str(Picker.pick(Vector3.ZERO, Vector3(0, 0, 1), [talk, door])["id"]).is_equal("door")
	# Alone, the passer-by is still offered.
	assert_str(Picker.pick(Vector3.ZERO, Vector3(0, 0, 1), [talk])["id"]).is_equal("talk")
	# The penalty never pushes it out of its own range (clamped like the old d = minf(d + 1.6, 3.19)).
	var edge := _cand("edge", Vector3(0, 0, 3.0), {"low_priority": true})
	assert_str(Picker.pick(Vector3.ZERO, Vector3(0, 0, 1), [edge])["id"]).is_equal("edge")


func test_picker_mount_wins_outright_when_mounted() -> void:
	var horse := _cand("mount", Vector3(0, 0, 9.0), {"mount": true})
	var door := _cand("door", Vector3(0, 0, 0.5), {"priority": 5})
	assert_str(Picker.pick(Vector3.ZERO, Vector3(0, 0, 1), [door, horse], [], true)["id"]).is_equal("mount")
	# Not mounted: a far horse is simply out of range.
	assert_str(Picker.pick(Vector3.ZERO, Vector3(0, 0, 1), [door, horse], [], false)["id"]).is_equal("door")


func test_picker_providers_plug_in() -> void:
	var prov := func(pos: Vector3, _facing: Vector3) -> Array:
		return [{"id": "vault", "pos": pos + Vector3(0, 0, 0.5), "priority": 2, "verb": "Vault"}]
	var best := Picker.pick(Vector3.ZERO, Vector3(0, 0, 1), [_cand("door", Vector3(0, 0, 1.0))], [prov])
	assert_str(best["id"]).is_equal("vault")
	assert_str(best["verb"]).is_equal("Vault")


func test_picker_tie_is_deterministic() -> void:
	var a := _cand("b_second", Vector3(1, 0, 0))
	var b := _cand("a_first", Vector3(-1, 0, 0))
	assert_str(Picker.pick(Vector3.ZERO, Vector3.ZERO, [a, b])["id"]).is_equal("a_first")
	assert_str(Picker.pick(Vector3.ZERO, Vector3.ZERO, [b, a])["id"]).is_equal("a_first")


# --- legacy wrapping and the component --------------------------------------------------------------

func test_legacy_group_member_is_wrapped_and_used() -> void:
	var p := _player()
	var t := LegacyThing.new()
	add_child(t)
	auto_free(t)
	t.global_position = Vector3(0, 0, 1.5)
	var c := Interactable.for_node(t)
	assert_object(c).is_not_null()
	assert_bool(c.legacy).is_true()
	assert_object(Interactable.for_node(t)).is_same(c)          # cached
	assert_bool(Interaction.activate(p)).is_true()
	assert_int(t.uses).is_equal(1)
	assert_object(Interaction.best_node(p)).is_same(t)


func test_legacy_label_comes_from_prompt() -> void:
	var t := LegacyThing.new()
	add_child(t)
	auto_free(t)
	var lab := Interactable.for_node(t).label()
	assert_str(lab["verb"]).is_equal("Open")
	assert_str(lab["target"]).is_equal("Thing")
	assert_str(InteractLabel.resolve(t)["text"]).is_equal("Open — Thing")


func test_legacy_low_priority_meta_is_honoured() -> void:
	var p := _player()
	var talk := LegacyThing.new()
	talk.set_meta("low_priority", true)
	add_child(talk)
	auto_free(talk)
	talk.global_position = Vector3(0, 0, 0.8)
	var door := LegacyThing.new()
	add_child(door)
	auto_free(door)
	door.global_position = Vector3(0, 0, 2.0)
	assert_object(Interaction.best_node(p)).is_same(door)


func test_component_attach_registers_group_and_runs_action() -> void:
	var host := Node3D.new()
	add_child(host)
	auto_free(host)
	var hits := []
	var c := Interactable.attach(host, {"id": "t/1", "verb": "Pull", "target": "Chain", "do": func(_p: Node) -> void: hits.append(1)})
	assert_bool(host.is_in_group("interactable")).is_true()
	assert_str(c.stable_id()).is_equal("t/1")
	c.interact(null)
	assert_int(hits.size()).is_equal(1)
	assert_str(InteractLabel.resolve(host)["text"]).is_equal("Pull — Chain")
	Interactable.set_active(host, false)
	assert_bool(host.is_in_group("interactable")).is_false()
	Interactable.set_active(host, true)
	assert_bool(host.is_in_group("interactable")).is_true()


func test_can_interact_gates_the_action() -> void:
	var p := _player()
	var host := Node3D.new()
	add_child(host)
	auto_free(host)
	host.global_position = Vector3(0, 0, 1)
	var ok := [false]
	var hits := []
	Interactable.attach(host, {"can": func(_p: Node) -> bool: return ok[0], "do": func(_p: Node) -> void: hits.append(1)})
	assert_bool(Interaction.activate(p)).is_false()
	ok[0] = true
	assert_bool(Interaction.activate(p)).is_true()
	assert_int(hits.size()).is_equal(1)


func test_interaction_providers_plug_into_activate() -> void:
	var p := _player()
	var hits := []
	var prov := func(pos: Vector3, _f: Vector3) -> Array:
		return [{"id": "climb", "pos": pos, "priority": 3, "verb": "Climb", "target": "Ledge",
			"interact": func(_pl: Node) -> void: hits.append("climb")}]
	Interaction.add_provider(prov)
	assert_bool(Interaction.activate(p)).is_true()
	Interaction.remove_provider(prov)
	assert_array(hits).is_equal(["climb"])
	assert_bool(Interaction.activate(p)).is_false()


func test_mounted_player_dismounts_through_the_one_route() -> void:
	var p := _player()
	# A minimal rideable stand-in: legacy wrapper maps rideable() to the mount candidate.
	var h := RideableThing.new()
	add_child(h)
	auto_free(h)
	h.global_position = Vector3(0, 0, 1.0)
	assert_bool(Interaction.activate(p)).is_true()
	assert_int(p.mounted_calls).is_equal(1)


class RideableThing extends Node3D:
	func _ready() -> void:
		add_to_group("interactable")
	func rideable() -> bool:
		return true
	func prompt() -> String:
		return "Ride"


func test_controller_hold_runs_after_hold_time() -> void:
	var p := _player()
	var host := Node3D.new()
	add_child(host)
	auto_free(host)
	host.global_position = Vector3(0, 0, 1)
	var done := []
	var progress := []
	var c := Interactable.attach(host, {"verb": "Work", "hold_time": 1.0, "do": func(_pl: Node) -> void: done.append(1)})
	c.hold_progress.connect(func(_pl: Node, f: float) -> void: progress.append(f))
	var ctl := InteractionController.new()
	p.add_child(ctl)
	ctl._begin_hold(c)
	Input.action_press("interact")
	ctl._process(0.4)
	assert_int(done.size()).is_equal(0)
	assert_float(progress[-1]).is_equal_approx(0.4, 0.001)
	ctl._process(0.7)
	assert_int(done.size()).is_equal(1)
	assert_object(ctl.holding()).is_null()
	Input.action_release("interact")


func test_controller_hold_cancels_on_release() -> void:
	var p := _player()
	var host := Node3D.new()
	add_child(host)
	auto_free(host)
	host.global_position = Vector3(0, 0, 1)
	var cancelled := []
	var done := []
	var c := Interactable.attach(host, {"hold_time": 1.0, "do": func(_pl: Node) -> void: done.append(1)})
	c.hold_cancelled.connect(func(_pl: Node) -> void: cancelled.append(1))
	var ctl := InteractionController.new()
	p.add_child(ctl)
	ctl._begin_hold(c)
	Input.action_release("interact")
	ctl._process(0.2)
	assert_int(cancelled.size()).is_equal(1)
	assert_int(done.size()).is_equal(0)


# --- the new kinds ------------------------------------------------------------------------------------

func test_ground_item_take_gives_to_inventory() -> void:
	var before := Life.count("bread")
	var g := GroundItem.spawn(self, Vector3(0, 0, 1), "bread", 2, "farmer_joe")
	assert_str(String(g.get_meta("owner"))).is_equal("farmer_joe")
	var taken := []
	g.taken.connect(func(item: String, qty: int, owner: String) -> void: taken.append([item, qty, owner]))
	var p := _player()
	assert_bool(Interaction.activate(p)).is_true()
	assert_int(Life.count("bread")).is_equal(before + 2)
	assert_array(taken).is_equal([["bread", 2, "farmer_joe"]])
	assert_bool(g.take()).is_false()       # already gone


func test_ground_item_label() -> void:
	var g := GroundItem.spawn(self, Vector3.ZERO, "bread", 1)
	auto_free(g)
	assert_str(InteractLabel.resolve(g)["verb"]).is_equal("Take")


func test_corpse_roll_is_deterministic_and_search_pays_once() -> void:
	CorpseLoot.reset()
	var a := CorpseLoot.roll("person/7", CorpseLoot.GUARD)
	assert_dict(a).is_equal(CorpseLoot.roll("person/7", CorpseLoot.GUARD))
	assert_int(int(a["gold"])).is_between(3, 14)
	var body := Node3D.new()
	add_child(body)
	auto_free(body)
	body.global_position = Vector3(0, 0, 1)
	var c := CorpseLoot.attach(body, "person/7", CorpseLoot.GUARD)
	assert_str(c.label()["verb"]).is_equal("Search")
	var gold := Game.gold
	var p := _player()
	assert_bool(Interaction.activate(p)).is_true()
	assert_int(Game.gold).is_equal(gold + int(a["gold"]))
	assert_bool(c.can_interact(p)).is_false()                  # a searched body is bare
	assert_bool(body.is_in_group("interactable")).is_false()
	assert_dict(CorpseLoot.search("person/7", CorpseLoot.GUARD)).is_empty()
	CorpseLoot.reset()


func test_corpse_not_searchable_when_it_stands_up() -> void:
	CorpseLoot.reset()
	var body := Node3D.new()
	add_child(body)
	auto_free(body)
	var down := [true]
	var c := CorpseLoot.attach(body, "person/9", CorpseLoot.CIVILIAN, func() -> bool: return down[0])
	assert_bool(c.can_interact(null)).is_true()
	down[0] = false
	assert_bool(c.can_interact(null)).is_false()
	CorpseLoot.reset()


func test_seat_sits_and_stands_on_move() -> void:
	var seat := Seat.spawn(self, Vector3(2, 0, 0), PI, "bench")
	auto_free(seat)
	var p := _player()
	assert_bool(seat.sit(p)).is_true()
	assert_object(seat.occupant).is_same(p)
	assert_vector(p.global_position).is_equal_approx(Vector3(2, 0, 0), Vector3(0.01, 0.01, 0.01))
	assert_str(seat.stance_name()).is_equal("sit_bench")
	assert_str(InteractLabel.resolve(seat)["verb"]).is_equal("Stand")
	var other := _player(Vector3(5, 0, 0))
	assert_bool(seat.sit(other)).is_false()                     # taken
	assert_bool(Seat.should_stand(Vector2(0, 0))).is_false()
	assert_bool(Seat.should_stand(Vector2(0, -0.8))).is_true()
	assert_bool(Seat.should_stand(Vector2.ZERO, true)).is_true()
	seat.stand(p)
	assert_object(seat.occupant).is_null()
	assert_str(InteractLabel.resolve(seat)["verb"]).is_equal("Sit")


func test_seat_toggles_through_interact() -> void:
	var seat := Seat.spawn(self, Vector3(0, 0, 1), 0.0, "chair")
	auto_free(seat)
	var p := _player()
	assert_bool(Interaction.activate(p)).is_true()
	assert_object(seat.occupant).is_same(p)
	assert_bool(Interaction.activate(p)).is_true()
	assert_object(seat.occupant).is_null()


func test_container_open_withdraw_and_deposit() -> void:
	var c: Node3D = Container_.spawn(self, Vector3(0, 0, 1), "test/crate", "Crate", [{"item": "bread", "qty": 3}])
	auto_free(c)
	assert_str(InteractLabel.resolve(c)["verb"]).is_equal("Open")
	var menu: Dictionary = c.call("_menu")
	assert_str(String(menu["title"])).is_equal("Crate")
	var labels := []
	for o: Array in menu["options"]:
		labels.append(String(o[0]))
	assert_bool(labels.any(func(l: String) -> bool: return l.begins_with("Withdraw"))).is_true()
	var before := Life.count("bread")
	c.call("_withdraw", "bread", 2)
	assert_int(Life.count("bread")).is_equal(before + 2)
	assert_int(int((c.get("contents") as Array)[0]["qty"])).is_equal(1)
	c.call("_withdraw", "bread", 5)
	assert_int((c.get("contents") as Array).size()).is_equal(0)
	assert_int(Life.count("bread")).is_equal(before + 3)
	c.call("_deposit", "bread", 1)
	assert_int(Life.count("bread")).is_equal(before + 2)
	assert_int((c.get("contents") as Array).size()).is_equal(1)


func test_container_contents_are_deterministic() -> void:
	assert_array(Container_.roll_contents("inn/crate/1")).is_equal(Container_.roll_contents("inn/crate/1"))
	assert_bool(Container_.roll_contents("inn/crate/1").is_empty()).is_false()


func test_ladder_moves_between_markers() -> void:
	var l := Ladder.spawn(self, Vector3(1, 0, 1), Vector3(1, 4, 1.5))
	auto_free(l)
	assert_float(l.height()).is_equal_approx(4.0, 0.001)
	var p := _player(Vector3(1, 0, 1.3))
	var seen := []
	l.climbed.connect(func(up: bool) -> void: seen.append(up))
	# At the bottom, the picker offers the bottom end.
	assert_bool(Interaction.activate(p)).is_true()
	assert_vector(p.global_position).is_equal_approx(Vector3(1, 4, 1.5), Vector3(0.01, 0.01, 0.01))
	# Now at the top: the top end is the one in reach.
	assert_bool(Interaction.activate(p)).is_true()
	assert_vector(p.global_position).is_equal_approx(Vector3(1, 0, 1), Vector3(0.01, 0.01, 0.01))
	assert_array(seen).is_equal([true, false])


func test_lever_pull_toggles_and_notifies() -> void:
	var l := Lever.spawn(self, Vector3(0, 1, 1), "test/lever")
	auto_free(l)
	var states := []
	l.on_pull = func(on: bool) -> void: states.append(on)
	var p := _player()
	assert_str(InteractLabel.resolve(l)["text"]).is_equal("Pull — Lever")
	assert_bool(Interaction.activate(p)).is_true()
	assert_bool(l.pulled).is_true()
	assert_bool(Interaction.activate(p)).is_true()
	assert_bool(l.pulled).is_false()
	assert_array(states).is_equal([true, false])


func test_once_lever_stays_pulled() -> void:
	var l := Lever.spawn(self, Vector3(0, 1, 1), "test/once", 0.0, true)
	auto_free(l)
	var p := _player()
	assert_bool(Interaction.activate(p)).is_true()
	assert_bool(Interaction.activate(p)).is_false()       # no longer offered
	assert_bool(l.pulled).is_true()


func test_inn_props_place_one_of_each_kind() -> void:
	var room := Node3D.new()
	room.scene_file_path = "res://scenes/interiors/inn_interior.tscn"
	add_child(room)
	auto_free(room)
	var root := InnProps.populate(room)
	assert_object(root).is_not_null()
	assert_object(InnProps.populate(room)).is_same(root)       # once
	assert_int(root.find_children("*", "Seat", true, false).size()).is_equal(1)
	assert_int(root.find_children("*", "GroundItem", true, false).size()).is_equal(1)
	assert_int(root.find_children("*", "Ladder", true, false).size()).is_equal(1)
	assert_int(root.find_children("*", "Lever", true, false).size()).is_equal(1)
	assert_int(root.find_children("Container_*", "Node3D", true, false).size()).is_equal(1)
	assert_object(Interactable.component_of(root.get_node("FallenTraveller"))).is_not_null()
	var plain := Node3D.new()
	add_child(plain)
	auto_free(plain)
	assert_object(InnProps.populate(plain)).is_null()


# --- the old dispatch chain is gone ------------------------------------------------------------------

func test_no_copied_poll_interact_is_left() -> void:
	for path: String in ["res://scripts/world/home_chest.gd", "res://scripts/world/ore_vein.gd", "res://scripts/world/forage_nodes.gd",
			"res://scripts/world/fishing_spot.gd", "res://scripts/world/farm_work_spot.gd", "res://scripts/world/build_resources.gd",
			"res://scripts/world/exploration_director.gd", "res://scripts/world/towers/tower_point.gd",
			"res://scripts/world/towers/tower_run.gd", "res://scripts/interiors/dungeon_thing.gd", "res://scripts/core/main.gd"]:
		var src := FileAccess.get_file_as_string(path)
		assert_bool(src.contains("func _poll_interact")).is_false()
		assert_bool(src.contains("is_action_just_pressed(\"interact\")")).is_false()
	var main := FileAccess.get_file_as_string("res://scripts/core/main.gd")
	assert_bool(main.contains("target is Captain")).is_false()
	assert_bool(main.contains("target is InteriorDoor")).is_false()
