extends Control
## Tutorial director sandbox (package L16): the prompt view over a mock phone HUD, driven
## either by you or by a scripted autoplay that screenshots every prompt.
##
## Windowed (needs a GPU for screenshots; do not pass --headless):
##   Godot --path kingdom res://tools_qa/region1/tutorial_sandbox.tscn
##   Godot --path kingdom res://tools_qa/region1/tutorial_sandbox.tscn -- --shots=<dir>   (autoplay, then quit)
##   add --keyboard for keyboard captions, --lang=nl for Dutch.
##
## Interactive keys: 1..9, 0 toggle contexts (see the panel); WASD move, mouse drag look,
## E talk/use, B sleep, F eat, J strike, L block, Space dodge, Tab map, C carve, H ashsight,
## X skip, R replay all, T tips on/off.
## Autoplay exit code: 0 when every prompt showed in its context and was dismissed by its action.

const ORDER := ["move", "look", "talk", "interact", "eat", "sleep", "map", "carve", "ashsight", "fight", "block", "dodge"]
## Context that makes each prompt relevant in the autoplay.
const CONTEXT := {
	"move": {"can_control": true}, "look": {"can_control": true},
	"talk": {"can_control": true, "near_npc": true}, "interact": {"can_control": true, "near_interactable": true},
	"eat": {"can_control": true, "food": 20.0, "has_food": true}, "sleep": {"can_control": true, "near_bed": true, "rest": 25.0, "is_night": true},
	"map": {"can_control": true, "new_marker": true}, "carve": {"can_control": true, "near_dim_stone": true, "knows_glyph": true},
	"ashsight": {"can_control": true, "near_ash_site": true}, "fight": {"can_control": true, "enemy_near": true},
	"block": {"can_control": true, "enemy_near": true, "enemy_winding_up": true},
	"dodge": {"can_control": true, "enemy_near": true, "enemy_winding_up": true},
}
const TOGGLES := [["near_npc", KEY_1], ["near_interactable", KEY_2], ["hungry", KEY_3], ["near_bed", KEY_4],
	["new_marker", KEY_5], ["near_dim_stone", KEY_6], ["near_ash_site", KEY_7], ["enemy_near", KEY_8],
	["enemy_winding_up", KEY_9], ["blocked", KEY_0]]

var director := Region1TutorialDirector.new()
var view: Region1TutorialPromptView
var ctx := {"can_control": true, "food": 80.0, "rest": 80.0, "has_food": true, "knows_glyph": true, "touch": true}
var shots_dir := ""
var lang := "en"
var _log: PackedStringArray = []
var _info: Label
var _dragging := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			shots_dir = a.substr(8)
		elif a == "--keyboard":
			ctx["touch"] = false
		elif a.begins_with("--lang="):
			lang = a.substr(7)
	for l: String in ["en", "nl"]:   # the game loads these in app_services.gd
		var p := "res://locale/strings.%s.translation" % l
		if ResourceLoader.exists(p):
			TranslationServer.add_translation(load(p))
	TranslationServer.set_locale(lang)
	view = Region1TutorialPromptView.new()
	add_child(view)
	view.bind(director)
	_info = Label.new()
	_info.position = Vector2(16, 12)
	_info.add_theme_color_override("font_color", Color(0.15, 0.12, 0.08))
	_info.add_theme_font_size_override("font_size", 13)
	add_child(_info)
	director.prompt_shown.connect(func(id: StringName, _p: Dictionary) -> void: _note("shown " + id))
	director.prompt_hidden.connect(func(id: StringName, why: StringName) -> void: _note("hidden %s (%s)" % [id, why]))
	if shots_dir != "":
		DirAccess.make_dir_recursive_absolute(shots_dir)
		_autoplay()


func _note(s: String) -> void:
	_log.append("%6.2f %s" % [Time.get_ticks_msec() / 1000.0, s])
	print(_log[-1])


func _process(delta: float) -> void:
	if shots_dir == "":
		var move := Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_A) \
			or Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_D)
		if move:
			director.notify(&"move", delta)
		if Input.is_physical_key_pressed(KEY_H):
			director.notify(&"ashsight", delta * 2.0)
		director.update(ctx, delta)
	var on: PackedStringArray = []
	for t: Array in TOGGLES:
		on.append("%s %s" % [OS.get_keycode_string(t[1]), t[0] + ("*" if bool(ctx.get(t[0], false)) else "")])
	_info.text = "Tutorial sandbox (L16)   current: %s   pending: %d\n%s" % [director.current,
		director.pending().size(), "   ".join(on)]
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if shots_dir != "":
		return
	if event is InputEventMouseButton:
		_dragging = event.pressed
	elif event is InputEventMouseMotion and _dragging:
		director.notify(&"look", event.relative.length() / 400.0)
	elif event is InputEventKey and event.pressed and not event.echo:
		for t: Array in TOGGLES:
			if event.physical_keycode == t[1]:
				ctx[t[0]] = not bool(ctx.get(t[0], false))
				if t[0] == "hungry":
					ctx["food"] = 20.0 if ctx["hungry"] else 80.0
				if t[0] == "near_bed":
					ctx["rest"] = 25.0 if ctx["near_bed"] else 80.0
		match event.physical_keycode:
			KEY_E: director.notify(&"talk"); director.notify(&"interact")
			KEY_B: director.notify(&"sleep")
			KEY_F: director.notify(&"eat")
			KEY_J: director.notify(&"attack")
			KEY_L: director.notify(&"block")
			KEY_SPACE: director.notify(&"dodge")
			KEY_TAB: director.notify(&"map")
			KEY_C: director.notify(&"carve")
			KEY_X: director.skip_current()
			KEY_R: director.replay_all()
			KEY_T: director.set_enabled(not director.enabled)


# --- mock world + HUD ------------------------------------------------------------------

func _draw() -> void:
	var s := size
	# Storybook dusk: warm sky, green hills, a road with a glowing stone.
	for i in 24:
		var t := float(i) / 23.0
		draw_rect(Rect2(0, s.y * 0.55 * t, s.x, s.y * 0.56 / 23.0 + 1.0),
			Color("f6d9a0").lerp(Color("9cc3e0"), 1.0 - t))
	draw_colored_polygon(PackedVector2Array([Vector2(0, s.y * 0.55), Vector2(s.x * 0.3, s.y * 0.45),
		Vector2(s.x * 0.62, s.y * 0.52), Vector2(s.x, s.y * 0.44), Vector2(s.x, s.y), Vector2(0, s.y)]), Color("7fa65a"))
	draw_colored_polygon(PackedVector2Array([Vector2(s.x * 0.42, s.y), Vector2(s.x * 0.49, s.y * 0.53),
		Vector2(s.x * 0.53, s.y * 0.53), Vector2(s.x * 0.66, s.y)]), Color("c9ad7c"))
	var stone := Vector2(s.x * 0.58, s.y * 0.58)
	draw_rect(Rect2(stone - Vector2(10, 34), Vector2(20, 40)), Color("8c8a86"))
	var lit := not bool(ctx.get("near_dim_stone", false)) or director.is_done(&"carve")
	draw_line(stone + Vector2(0, -26), stone + Vector2(0, -6), Color("6fd3ff") if lit else Color("4a4a4a"), 3.0)
	# Mock HUD: stick + round buttons at the view's default anchors.
	var hud := {"left_stick": "", "btn_attack": "J", "btn_block": "L", "btn_dodge": "_", "btn_interact": "E",
		"btn_eat": "F", "btn_map": "M"}
	for k: String in hud:
		var p := view.anchor_pos(k)
		var r := 64.0 if k == "left_stick" else 38.0
		draw_circle(p, r * size.y / 1080.0 * 1.6, Color(0.05, 0.04, 0.03, 0.45))
		draw_arc(p, r * size.y / 1080.0 * 1.6, 0.0, TAU, 40, Color("d8a84e"), 2.0, true)


# --- autoplay ---------------------------------------------------------------------------

func _wait(sec: float) -> void:
	var t := 0.0
	while t < sec:
		await get_tree().process_frame
		var dt := get_process_delta_time()
		director.update(ctx, dt)
		t += dt


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [shots_dir, name])


func _set_ctx(c: Dictionary) -> void:
	for k: String in ["near_npc", "near_interactable", "near_bed", "is_night", "new_marker", "near_dim_stone",
			"near_ash_site", "enemy_near", "enemy_winding_up", "blocked"]:
		ctx[k] = false
	ctx["food"] = 80.0
	ctx["rest"] = 80.0
	for k: String in c:
		ctx[k] = c[k]


func _autoplay() -> void:
	var fails := 0
	var n := 0
	for id: String in ORDER:
		n += 1
		_set_ctx(CONTEXT[id])
		var waited := 0.0
		while director.current != StringName(id) and waited < 5.0:
			await _wait(0.1)
			waited += 0.1
		if director.current != StringName(id):
			_note("FAIL %s never showed (current=%s)" % [id, director.current])
			fails += 1
			continue
		await _wait(0.85)
		await _shot("%02d_%s" % [n, id])
		var p: Dictionary = Region1TutorialDirector.PROMPTS[id]
		var amount := float(p["amount"])
		director.notify(&"wrong_action")   # anything else must not dismiss it
		if director.current != StringName(id):
			_note("FAIL %s dismissed by a wrong action" % id)
			fails += 1
		var steps := 10 if amount < 2.0 and String(p["action"]) in ["move", "look"] else int(amount)
		for i in steps:
			director.notify(StringName(p["action"]), amount / steps)
			await _wait(0.05)
		if not director.is_done(StringName(id)):
			_note("FAIL %s not done after its action" % id)
			fails += 1
		if id == "fight":
			await _wait(0.12)
			await _shot("%02d_%s_done" % [n, id])
	# Replay one prompt out of context, then skip it with the skip button path.
	_set_ctx({"can_control": true})
	director.replay(&"carve")
	await _wait(1.0)
	await _shot("%02d_replay_carve" % (n + 1))
	if director.current != &"carve":
		_note("FAIL replayed carve did not show")
		fails += 1
	view.skip_pressed.emit()
	if director.status(&"carve") != Region1TutorialDirector.State.SKIPPED:
		_note("FAIL skip button did not skip")
		fails += 1
	# Keyboard caption variant.
	ctx["touch"] = false
	_set_ctx(CONTEXT["fight"])
	director.replay(&"fight")
	await _wait(1.0)
	await _shot("%02d_keyboard_fight" % (n + 2))
	_note("autoplay done: %d prompts, %d failures" % [ORDER.size(), fails])
	var f := FileAccess.open(shots_dir + "/tutorial_sandbox.log", FileAccess.WRITE)
	if f:
		f.store_string("\n".join(_log) + "\n")
	get_tree().quit(0 if fails == 0 else 1)
