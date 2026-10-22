extends GdUnitTestSuite
## Exploration / combat HUD layouts (scripts/ui/hud_mode.gd), the contextual interaction label
## (scripts/ui/interact_label.gd) and the HUD's own wiring of both.

const HudMode := preload("res://scripts/ui/hud_mode.gd")
const InteractLabel := preload("res://scripts/ui/interact_label.gd")
const HudCard := preload("res://scripts/ui/hud_card.gd")
const HudScript := preload("res://scripts/ui/hud.gd")
const HudLane := preload("res://scripts/ui/hud_lane.gd")
const Nameplates := preload("res://scripts/core/nameplates.gd")
const ThreatPlates := preload("res://scripts/ui/threat_plates.gd")
const AshesFrame := preload("res://scripts/ui/ashes_frame.gd")


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


func test_hud_has_a_default_lock_button_in_combat_that_clears_jump_and_attack() -> void:
	var h := _hud()
	h._snap = true
	h._layout()
	var lock: TouchScreenButton = h._buttons["lock_combat"]
	assert_str(lock.action).is_equal("lock_on")                 # a tap presses lock_on = toggle; the look-area flick switches
	assert_float(h._fade_goal[lock]).is_equal(0.0)              # hidden while exploring
	h.mode.engage()
	h._layout()
	assert_float(h._fade_goal[lock]).is_equal(1.0)
	var lr: float = (lock.shape as CircleShape2D).radius
	for other in ["attack", "jump", "dodge", "block", "ability_dash"]:
		var b: TouchScreenButton = h._buttons[other]
		var d: float = ((h._goal[lock] as Vector2) + Vector2(lr, lr)).distance_to((h._goal[b] as Vector2) + Vector2((b.shape as CircleShape2D).radius, (b.shape as CircleShape2D).radius))
		assert_float(d).override_failure_message(other).is_greater(lr + (b.shape as CircleShape2D).radius)


# --- visual pass 2026-10: one stack for toast / hint / banner ---------------------------------------------------

func test_toast_hint_and_banner_never_overlap() -> void:
	HudLane.reset()
	# alone, each keeps its own spot
	assert_float(HudLane.y_for("hint", 83.0)).is_equal(83.0)
	HudLane.report("toast", 80.0, 40.0)
	var hint_y := HudLane.y_for("hint", 83.0)
	assert_float(hint_y).is_greater_equal(80.0 + 40.0)                   # below the toast
	HudLane.report("hint", hint_y, 52.0)
	var banner_y := HudLane.y_for("banner", 115.0)
	assert_float(banner_y).is_greater_equal(hint_y + 52.0)               # below the toast and the hint
	# the toast fades: the hint rises again
	HudLane.report("toast", 80.0, 0.0)
	assert_float(HudLane.y_for("hint", 83.0)).is_equal(83.0)
	HudLane.reset()


func test_banners_and_hints_wait_while_a_menu_is_open() -> void:
	HudLane.reset()
	assert_bool(HudLane.allowed("banner")).is_true()
	HudLane.set_menu_open(true)
	assert_bool(HudLane.allowed("banner")).is_false()
	assert_bool(HudLane.allowed("hint")).is_false()
	assert_bool(HudLane.allowed("toast")).is_true()
	HudLane.set_menu_open(false)
	assert_bool(HudLane.allowed("banner")).is_true()
	HudLane.reset()


func test_banner_holds_its_clock_while_a_sheet_is_open() -> void:
	HudLane.reset()
	var banner: Control = load("res://scripts/ui/discovery_banner.gd").new()
	add_child(banner)
	auto_free(banner)
	banner.call("show_place", "Thornfield", "Market Town")
	HudLane.set_menu_open(true)
	var t0: float = banner.get("_t")
	banner.call("_process", 1.0)
	assert_float(float(banner.get("_t"))).is_equal(t0)                   # paused behind the conversation
	HudLane.set_menu_open(false)
	banner.call("_process", 1.0)
	assert_float(float(banner.get("_t"))).is_greater(t0)
	HudLane.reset()


# --- nameplates ---------------------------------------------------------------------------------------------------

func test_nameplates_fade_out_by_their_cap_and_keep_the_nearest_six() -> void:
	assert_float(Nameplates.fade_alpha(5.0, 25.0)).is_equal(1.0)
	assert_float(Nameplates.fade_alpha(25.0, 25.0)).is_equal(0.0)
	assert_float(Nameplates.fade_alpha(23.5, 25.0)).is_between(0.2, 0.8)       # FADE_LEN is 4 m
	var rows: Array = []
	for i in 10:
		rows.append({"id": i, "dist": float(10 - i)})                      # id 9 is nearest
	var keep := Nameplates.nearest_ids(rows)
	assert_int(keep.size()).is_equal(Nameplates.MAX_SHOWN)
	assert_bool(keep.has(9)).is_true()
	assert_bool(keep.has(0)).is_false()


func test_nameplate_pixel_size_gives_a_whole_number_of_pixels_readable_at_720p() -> void:
	for vh: float in [720.0, 1080.0, 1440.0]:
		var ps := Nameplates.snapped_pixel_size(26, vh, 65.0)
		var px_per_unit := vh / (2.0 * tan(deg_to_rad(65.0) * 0.5))
		var px := 26.0 * ps * px_per_unit
		assert_float(px).is_equal_approx(roundf(px), 0.001)
		assert_float(px).is_greater_equal(Nameplates.MIN_PX * vh / 720.0 - 0.5)


func test_nameplates_stay_off_the_town_board() -> void:
	var board := Rect2(400, 100, 300, 120)
	assert_bool(Nameplates.hidden_by_sign(Vector2(500, 150), [board])).is_true()
	assert_bool(Nameplates.hidden_by_sign(Vector2(500, 300), [board])).is_false()
	assert_bool(Nameplates.hidden_by_sign(Vector2(500, 150), [])).is_false()


func test_nameplate_over_the_town_board_is_lifted_above_it_not_hidden() -> void:
	var board := Rect2(400, 100, 300, 120)
	var lift := Nameplates.sign_lift(Vector2(500, 150), [board])
	assert_float(lift).is_greater(0.0)
	# lifted by `lift` px the plate sits above the board's top edge (minus the margin)
	assert_float(lift).is_less_equal(Nameplates.MAX_LIFT)             # nudged, never flung to the top of the screen
	var tall := Rect2(400, 40, 300, 600)
	assert_float(Nameplates.sign_lift(Vector2(500, 300), [tall], 84.0)).is_less_equal(Nameplates.MAX_LIFT)
	assert_float(Nameplates.sign_lift(Vector2(500, 90), [tall], 84.0)).is_less_equal(6.0)   # near the top bar: barely moves
	assert_float(Nameplates.sign_lift(Vector2(500, 300), [board])).is_equal(0.0)
	assert_float(Nameplates.sign_lift(Vector2(500, 150), [])).is_equal(0.0)


func test_merged_threat_plate_shows_the_weakest_wolf() -> void:
	var a := {"name": "Wolf", "level": 1, "frac": 0.9}
	var b := {"name": "Wolf", "level": 1, "frac": 0.25}
	var title := ThreatPlates.plate_title(a)
	var merged := ThreatPlates.layout([
		{"at": Vector2(300, 200), "info": a, "locked": false, "a": 1.0, "title": title, "w": 100.0},
		{"at": Vector2(304, 202), "info": b, "locked": false, "a": 1.0, "title": title, "w": 100.0}])
	assert_int(merged.size()).is_equal(1)
	assert_float(float((merged[0]["info"] as Dictionary)["frac"])).is_equal_approx(0.25, 0.0001)


func test_threat_plates_merge_twins_and_offset_overlaps() -> void:
	var info := {"name": "Wolf", "level": 1, "frac": 1.0}
	var title := ThreatPlates.plate_title(info)
	assert_str(title).is_equal("Lv 1  Wolf")
	var twins := ThreatPlates.layout([
		{"at": Vector2(300.2, 200.1), "info": info, "locked": false, "a": 1.0, "title": title, "w": 100.0},
		{"at": Vector2(303.0, 204.0), "info": info, "locked": true, "a": 1.0, "title": title, "w": 100.0}])
	assert_int(twins.size()).is_equal(1)                                   # one plate: "Lv 1  Wolf  x2"
	assert_int(int((twins[0]["info"] as Dictionary)["count"])).is_equal(2)
	assert_bool(bool(twins[0]["locked"])).is_true()
	assert_vector(twins[0]["at"]).is_equal(Vector2(300, 200))              # pixel-snapped
	var other := {"name": "Bandit", "level": 2, "frac": 1.0}
	var two := ThreatPlates.layout([
		{"at": Vector2(300, 200), "info": info, "locked": false, "a": 1.0, "title": title, "w": 100.0},
		{"at": Vector2(310, 205), "info": other, "locked": false, "a": 1.0, "title": ThreatPlates.plate_title(other), "w": 100.0}])
	assert_int(two.size()).is_equal(2)
	assert_float(absf((two[1]["at"] as Vector2).y - (two[0]["at"] as Vector2).y)).is_greater_equal(ThreatPlates.PLATE_H - 0.01)


# --- typographic quotes in the talk sheet ----------------------------------------------------------------------------

func test_ascii_quotes_become_open_and_close_quotes() -> void:
	assert_str(AshesFrame.typographic("He said \"hello there\" and left.")).is_equal("He said \u201chello there\u201d and left.")
	assert_str(AshesFrame.typographic("\"Quote\" at the start")).is_equal("\u201cQuote\u201d at the start")
	assert_str(AshesFrame.typographic("(\"aside\")")).is_equal("(\u201caside\u201d)")
	assert_str(AshesFrame.typographic("Don't go; 'tis late")).is_equal("Don\u2019t go; \u2018tis late")
	assert_str(AshesFrame.typographic("No quotes here.")).is_equal("No quotes here.")


func test_a_plate_gets_one_smaller_second_line_and_it_follows_the_plate() -> void:
	var tag := Label3D.new()
	tag.text = "Hesta Thorne"
	add_child(tag)
	auto_free(tag)
	Nameplates.style(tag, Color.WHITE, 28)
	var sub := Nameplates.add_subtitle(tag, "Brewmistress")
	assert_bool(sub.is_in_group("nameplate")).is_false()              # never counts as a second plate
	assert_int(sub.font_size).is_less(tag.font_size)
	tag.transparency = 0.6
	tag.offset.y = 10.0
	Nameplates.place_subtitle(tag)
	assert_float(sub.transparency).is_equal_approx(0.6, 0.001)
	assert_float(sub.offset.y).is_less(tag.offset.y)                  # sits under the name
	tag.visible = false
	Nameplates.place_subtitle(tag)
	assert_bool(sub.visible).is_false()


func test_the_discovery_banner_sits_in_the_top_band_not_the_screen_centre() -> void:
	HudLane.reset()
	assert_float(HudLane.BANNER_Y).is_less(120.0)
	assert_float(HudLane.y_for("banner", HudLane.BANNER_Y)).is_equal(HudLane.BANNER_Y)
	HudLane.reset()


# --- the job-offer card sits in the top lane under the banner, never over the middle of the screen --------------------

func test_job_offer_card_stacks_under_toast_hint_and_banner() -> void:
	HudLane.reset()
	assert_float(HudLane.y_for("offer", HudLane.OFFER_Y)).is_equal(HudLane.OFFER_Y)
	HudLane.report("banner", 58.0, 80.0)
	assert_float(HudLane.y_for("offer", HudLane.OFFER_Y)).is_greater_equal(58.0 + 80.0)
	HudLane.report("banner", 0.0, 0.0)
	HudLane.set_menu_open(true)
	assert_bool(HudLane.allowed("offer")).is_false()                      # held back while a menu is open
	HudLane.reset()


func test_job_offer_waits_for_the_player_to_stand_still() -> void:
	HudLane.reset()
	var ws: Node3D = preload("res://scripts/world/work_spots.gd").new()
	add_child(auto_free(ws))
	var btns: Array = [["Ask for work", func() -> void: pass], ["Not now", func() -> void: pass]]
	ws._still = 0.0                                                         # just arrived, still walking
	ws._offer_card("Saltwick: Guard", "3 work orders today.", btns, "k")
	assert_bool(ws._offer == null or not ws._offer.visible).is_true()
	ws._still = ws.OFFER_STILL + 0.5                                        # stands still
	ws._offer_card("Saltwick: Guard", "3 work orders today.", btns, "k")
	assert_bool(ws._offer != null and ws._offer.visible).is_true()
	# it is a compact card in the top lane: narrower than the old 620 px panel and clear of the screen centre
	assert_float(ws._offer.offset_right - ws._offer.offset_left).is_less_equal(460.0)
	assert_float(ws._offer.offset_top).is_less(160.0)
	assert_bool(HudLane._rects.has("offer")).is_true()
	ws._still = 0.0                                                         # walks on: the card goes away
	ws._offer_card("Saltwick: Guard", "3 work orders today.", btns, "k")
	assert_bool(ws._offer.visible).is_false()
	HudLane.reset()
