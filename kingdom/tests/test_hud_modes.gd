extends GdUnitTestSuite
## Exploration / combat HUD layouts (scripts/ui/hud_mode.gd), the contextual interaction label
## (scripts/ui/interact_label.gd) and the HUD's own wiring of both.

const HudMode := preload("res://scripts/ui/hud_mode.gd")
const InteractLabel := preload("res://scripts/ui/interact_label.gd")
const HudCard := preload("res://scripts/ui/hud_card.gd")
const HudScript := preload("res://scripts/ui/hud.gd")


class Npc extends Node3D:
	var title := "Roland Ward"
	var verb := "Talk"
	func prompt() -> String:
		return verb


class Door extends Node3D:
	var prompt_text := "Enter the inn"
	var is_exit := false
	func prompt() -> String:
		return prompt_text


class Custom extends Node3D:
	func interact_label() -> Dictionary:
		return {"verb": "Work", "target": "Blacksmith"}
	func prompt() -> String:
		return "ignored"


class Bare extends Node3D:
	func prompt() -> String:
		return "Ride"


class Fields extends Node3D:
	func prompt() -> String:
		return "Work the fields (hold)"


# --- mode switching ---------------------------------------------------------------------

func test_starts_in_exploration_with_no_hotbar() -> void:
	var m := HudMode.new()
	assert_int(m.mode).is_equal(HudMode.Mode.EXPLORE)
	assert_bool(m.hotbar_wanted()).is_false()
	assert_float(m.combat_t).is_equal(0.0)


func test_hostile_expands_and_collapses_six_seconds_after() -> void:
	var m := HudMode.new()
	m.update(0.1, true, false)
	assert_bool(m.in_combat()).is_true()
	assert_bool(m.hotbar_wanted()).is_true()
	for i in 10:
		m.update(0.1, false, false)       # hostile gone: still up for COLLAPSE_DELAY
	assert_bool(m.in_combat()).is_true()
	for i in 60:
		m.update(0.1, false, false)
	assert_bool(m.in_combat()).is_false()
	for i in 10:
		m.update(0.1, false, false)
	assert_float(m.combat_t).is_equal(0.0)


func test_weapon_use_or_damage_engages() -> void:
	var m := HudMode.new()
	m.update(0.1, false, true)
	assert_bool(m.in_combat()).is_true()
	var n := HudMode.new()
	n.engage()
	assert_bool(n.in_combat()).is_true()


func test_transition_is_smooth_not_a_jump() -> void:
	var m := HudMode.new()
	m.update(0.05, true, false)
	assert_float(m.combat_t).is_between(0.01, 0.99)
	for i in 20:
		m.update(0.05, true, false)
	assert_float(m.combat_t).is_equal(1.0)
	assert_float(m.eased()).is_equal(1.0)


func test_hotbar_only_when_relevant() -> void:
	var m := HudMode.new()
	m.reveal_hotbar()
	assert_bool(m.hotbar_wanted()).is_true()
	m.update(HudMode.HOTBAR_REVEAL + 0.1, false, false)
	assert_bool(m.hotbar_wanted()).is_false()
	m.building = true
	assert_bool(m.hotbar_wanted()).is_true()
	m.building = false
	m.hotbar_pinned = true
	assert_bool(m.hotbar_wanted()).is_true()


# --- interaction labels ------------------------------------------------------------------

func test_npc_label_is_verb_and_name() -> void:
	var n: Node3D = auto_free(Npc.new())
	var l := InteractLabel.resolve(n)
	assert_str(l["text"]).is_equal("Talk — Roland Ward")
	assert_str(l["icon"]).is_equal("conversation")


func test_door_label_uses_building_name_meta_else_prompt() -> void:
	var d: Node3D = auto_free(Door.new())
	assert_str(InteractLabel.resolve(d)["text"]).is_equal("Enter — Inn")
	d.set_meta("building_name", "Golden Stag Inn")
	assert_str(InteractLabel.resolve(d)["text"]).is_equal("Enter — Golden Stag Inn")


func test_interact_label_convention_wins() -> void:
	var c: Node3D = auto_free(Custom.new())
	assert_str(InteractLabel.resolve(c)["text"]).is_equal("Work — Blacksmith")
	var m: Node3D = auto_free(Bare.new())
	m.set_meta("interact_label", "Inspect — Notice Board")
	assert_str(InteractLabel.resolve(m)["text"]).is_equal("Inspect — Notice Board")


func test_read_becomes_inspect_and_fallbacks_never_empty() -> void:
	var n: Node3D = auto_free(Npc.new())
	n.title = "Notice Board"
	n.verb = "Read"
	assert_str(InteractLabel.resolve(n)["text"]).is_equal("Inspect — Notice Board")
	assert_str(InteractLabel.resolve(auto_free(Bare.new()))["text"]).is_equal("Ride")
	assert_str(InteractLabel.resolve(auto_free(Fields.new()))["text"]).is_equal("Work — Fields (hold)")
	assert_str(InteractLabel.resolve(null)["verb"]).is_equal("Use")
	assert_str(InteractLabel.from_prompt("")["verb"]).is_equal("Use")


# --- the HUD itself ----------------------------------------------------------------------

func _hud() -> CanvasLayer:
	var p := Player.new()
	add_child(auto_free(p))
	var h: CanvasLayer = HudScript.new(p)
	add_child(auto_free(h))
	return h


func test_hud_status_card_collapses_to_portrait_and_expands_on_tap() -> void:
	var h := _hud()
	var card: Control = h.card
	assert_bool(card.expanded).is_false()
	assert_float(card.size.x).is_less(120.0)
	assert_int(card.ring_values().size()).is_equal(3)
	card.set_expanded(true)
	for i in 30:
		card._process(0.05)
	assert_float(card.size.x).is_equal(HudCard.Card.FULL.x)
	card.set_expanded(false)
	for i in 30:
		card._process(0.05)
	assert_float(card.size.x).is_equal(HudCard.Card.MINI.x)


func test_hud_labels_target_and_switches_primary_button() -> void:
	var h := _hud()
	var npc: Node3D = auto_free(Npc.new())
	add_child(npc)
	h._set_target(npc)
	assert_str(h.target_label["text"]).is_equal("Talk — Roland Ward")
	assert_str(h._pill.verb).is_equal("Talk")
	assert_str(h._pill.target).is_equal("Roland Ward")
	h._snap = true
	h._layout()
	assert_float(h._fade_goal[h._interact]).is_equal(1.0)
	assert_float(h._fade_goal[h._buttons["attack"]]).is_equal(0.0)
	h._set_target(null)
	h._layout()
	assert_float(h._fade_goal[h._interact]).is_equal(0.0)
	assert_float(h._fade_goal[h._buttons["attack"]]).is_equal(1.0)


func test_hud_combat_cluster_and_fan_reachability() -> void:
	var h := _hud()
	h.add_action_button("lock_on", "Lock", "lock_on", "glyph:lock")    # main.gd adds these two
	h.add_action_button("crouch", "Sneak", "crouch", "walk")
	h._snap = true
	h.mode.engage()
	h._layout()
	assert_float(h._fade_goal[h._buttons["block"]]).is_equal(1.0)
	assert_float(h._fade_goal[h._buttons["ability_dash"]]).is_equal(1.0)
	h.mode.update(HudMode.COLLAPSE_DELAY + 1.0, false, false)
	h._layout()
	assert_float(h._fade_goal[h._buttons["block"]]).is_equal(0.0)
	# every utility button is in the fan, nothing was dropped
	h.toggle_fan()
	assert_bool(h.fan_open).is_true()
	for key in ["map", "lock_on", "crouch", "view", "zoom_in", "zoom_out", "skills", "quickbar"]:
		assert_bool(h._fan.has(h._buttons[key])).override_failure_message(key).is_true()
	assert_bool(h._fan.has(h._pack_button)).is_true()
	assert_bool(h._fan.has(h._pause_button)).is_true()
	h.close_fan()
	assert_bool(h.fan_open).is_false()


func test_safe_insets_pushes_hud_inside_notch() -> void:
	var ins: Vector4 = HudScript.safe_insets(Vector2(2340, 1080), Rect2(96, 0, 2148, 1080), Vector2(1560, 720))
	assert_float(ins.x).is_equal_approx(64.0, 0.5)
	assert_float(ins.z).is_equal_approx(64.0, 0.5)
	assert_vector(Vector2(ins.y, ins.w)).is_equal(Vector2.ZERO)
	assert_object(HudScript.safe_insets(Vector2.ZERO, Rect2(), Vector2(1280, 720))).is_equal(Vector4.ZERO)


# --- follow-ups: door names, one-line quest tracker -------------------------------------

func test_door_building_names_are_deterministic_and_typed() -> void:
	var Door_ := preload("res://scripts/interiors/interior_door.gd")
	var a: String = Door_.building_name("inn", "Ashford", Vector2(10, 20))
	assert_str(a).ends_with(" Inn")
	assert_str(Door_.building_name("inn", "Ashford", Vector2(10, 20))).is_equal(a)
	assert_str(Door_.building_name("blacksmith", "Ashford", Vector2(3, 4))).ends_with("Smithy")
	assert_str(Door_.building_name("adventurer_guild", "Ashford", Vector2.ZERO)).is_equal("Ashford Adventurer Guild")
	assert_str(Door_.building_name("house_a", "Ashford", Vector2.ZERO)).is_empty()


func test_quest_tracker_is_one_line_then_expands_and_fades() -> void:
	var tr: Control = HudCard.QuestTracker.new()
	add_child(auto_free(tr))
	tr.set_quest({"title": "The Stones Are Dimming", "objectives": [
		{"text": "Hear what happened", "state": "current"}, {"text": "Later", "state": "todo"}]})
	assert_bool(tr.visible).is_true()
	assert_bool(tr.expanded).is_false()
	assert_str(tr.collapsed_text()).is_equal("The Stones Are Dimming  ·  Hear what happened")
	assert_bool(tr._rows.visible).is_false()
	tr.set_expanded(true)
	assert_bool(tr._rows.visible).is_true()
	tr.set_expanded(false)
	for i in 30:
		tr._process(0.5)       # 15 s with no change
	assert_bool(tr.visible).is_false()
	tr.set_quest({"title": "New", "objectives": []})
	assert_bool(tr.visible).is_true()
