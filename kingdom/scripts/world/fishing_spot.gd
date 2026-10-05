extends Node3D
## A place to fish: the end of the Emberglass Mere pier, a few points on the
## lake shore and on the banks of the Ashrun (placed by Lakeside).
##
## Interacting starts a short minigame built from plain Controls:
##   1. cast: the bobber arcs out onto the water;
##   2. wait 2-8 s: the bobber drifts; tapping early spooks the fish;
##   3. bite: the bobber dips and a "!" pops up, tap within BITE_WINDOW;
##   4. reel: keep the marker inside the moving zone by tapping (it sinks when
##      you don't). Inside the zone the catch bar fills, outside it drains.
## The fish is rolled from Gathering.FISH (perch, trout, pike, and the emberfin
## that only rises at sunset); rarer fish pull harder with a narrower zone.
##
## Self-contained like InteriorDoor: always in the "interactable" group with
## prompt() and use(). It polls "interact" itself while it is the player's
## nearest interactable, and use() has a per-frame guard, so a main.gd
## dispatcher that also calls use() does no harm.

const Gathering := preload("res://scripts/sim/gathering_items.gd")
const Crafting := preload("res://scripts/sim/crafting.gd")
const Deposits := preload("res://scripts/world/deposits.gd")
const GatherRun := preload("res://scripts/world/gather_run.gd")
const BITE_WINDOW := 1.1
const CAST_TIME := 0.9
const REEL_LIMIT := 30.0
const GRAVITY := 1.8           # marker fall, track widths per s^2
const TAP_IMPULSE := 0.6       # marker rise per tap, track widths per s
const FILL_RATE := 0.3         # catch bar per s inside the zone
const LEAVE_DISTANCE := 4.0
const TRACK_W := 420.0

enum Phase { IDLE, CAST, WAIT, BITE, REEL, DONE }

## Where the bobber lands (on the water surface).
var water_point := Vector3.ZERO
var river := false
var water_name := "Emberglass Mere"

var phase := Phase.IDLE
var fish := ""
var _t := 0.0
var _wait := 0.0
var _marker := 0.5
var _vel := 0.0
var _zone := 0.5
var _zone_goal := 0.5
var _zone_timer := 0.0
var _progress := 0.25
var _last_use_frame := -100
var _last_tap := -1.0
var _menu_was_open := false

var _bobber: Node3D
var _bang: Label3D
var _line: MeshInstance3D
var _line_mesh: ImmediateMesh
var _ui: CanvasLayer
var _status: Label
var _hint: Label
var _track: Control
var _zone_rect: ColorRect
var _marker_rect: ColorRect
var _fill: ColorRect
var _reel_box: Control


func _ready() -> void:
	add_to_group("interactable")
	Gathering.register(Life)
	_build_marker()


var deposits := Deposits.new()
var _panel: Control


## The spot's fish stock: a deposit keyed by position, regrowing daily (saved only once fished).
func dep_id() -> String:
	return "fishing/dep/fish/%d_%d" % [roundi(global_position.x), roundi(global_position.z)]


static func dep_def() -> Dictionary:
	return Deposits.make_def("fish", "perch", {"cap": 5, "regrow": 2.5})


func prompt() -> String:
	if phase == Phase.IDLE and deposits.is_depleted(dep_id(), dep_def(), WorldSim.day):
		return "Fished out"
	return "Fish" if phase == Phase.IDLE else "Reel"


func use() -> void:
	var f := Engine.get_process_frames()
	if f - _last_use_frame < 2:
		return
	_last_use_frame = f
	if phase == Phase.IDLE:
		if not is_instance_valid(_panel) and not deposits.is_depleted(dep_id(), dep_def(), WorldSim.day):
			_start()
		elif not is_instance_valid(_panel):
			Game.say("The water is still. Nothing is biting here today.")
	else:
		_tap()


func _process(delta: float) -> void:
	if phase == Phase.IDLE:
		_poll_interact()
		return
	var player := _player()
	if phase != Phase.DONE and (player == null or bool(player.get("dead")) \
			or player.global_position.distance_to(global_position) > LEAVE_DISTANCE):
		_finish("You wander off and reel in the line.", false)
		return
	_t += delta
	match phase:
		Phase.CAST:
			if _t >= CAST_TIME:
				_enter(Phase.WAIT)
		Phase.WAIT:
			_bob(0.02, 2.0)
			if _t >= _wait:
				_enter(Phase.BITE)
		Phase.BITE:
			_bob(0.07, 14.0, -0.05)
			if _t >= BITE_WINDOW:
				_finish("Too slow. It stole the bait.", false)
		Phase.REEL:
			_reel(delta)
		Phase.DONE:
			if _t >= 1.6:
				_close()
	_draw_line()


func _input(event: InputEvent) -> void:
	if phase == Phase.IDLE or phase == Phase.DONE:
		return
	if event.is_echo():
		return
	if event.is_action_pressed("interact") or event.is_action_pressed("attack") or event.is_action_pressed("ui_accept"):
		_tap()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		_finish("You reel in the line.", false)
		get_viewport().set_input_as_handled()


# --- flow -----------------------------------------------------------------------------

func _start() -> void:
	_build_ui()
	_build_bobber()
	_line.visible = true
	fish = ""
	_enter(Phase.CAST)
	var from := _rod_tip()
	_bobber.global_position = from
	_bobber.visible = true
	var t := create_tween()
	t.tween_property(_bobber, "global_position", _float_pos(), CAST_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _enter(p: Phase) -> void:
	phase = p
	_t = 0.0
	_reel_box.visible = p == Phase.REEL
	_bang.visible = p == Phase.BITE
	match p:
		Phase.CAST:
			_status.text = "Casting..."
			_hint.text = ""
		Phase.WAIT:
			_wait = randf_range(2.0, 8.0)
			_status.text = "Waiting for a bite..."
			_hint.text = "Tap when the bobber dips."
		Phase.BITE:
			fish = Gathering.roll_fish(randf(), WorldSim.time_of_day, river)
			_status.text = "A bite! Tap!"
			_hint.text = ""
		Phase.REEL:
			var f: Dictionary = Gathering.FISH[fish]
			_marker = 0.5
			_vel = 0.0
			_zone = 0.5
			_zone_goal = 0.5
			_zone_timer = 0.0
			_progress = 0.25
			_zone_rect.size.x = float(f["zone"]) * TRACK_W
			_status.text = "Something heavy..." if fish == "pike" or fish == "emberfin" else "Reel it in!"
			_hint.text = "Tap to lift the marker. Keep it in the gold zone."


func _tap() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_tap < 0.08:
		return    # the same touch arriving as a GUI tap and as an action
	_last_tap = now
	match phase:
		Phase.WAIT:
			_wait = _t + randf_range(1.5, 3.0)
			_hint.text = "Too early. The fish shy off; wait for the dip."
		Phase.BITE:
			_enter(Phase.REEL)
		Phase.REEL:
			_vel = maxf(_vel, 0.0) + TAP_IMPULSE


func _reel(delta: float) -> void:
	var f: Dictionary = Gathering.FISH[fish]
	var half := float(f["zone"]) * 0.5
	# The fish darts about: a new goal every so often, chased at its pull speed.
	_zone_timer -= delta
	if _zone_timer <= 0.0:
		_zone_timer = randf_range(0.5, 1.4)
		_zone_goal = randf_range(half, 1.0 - half)
	_zone = move_toward(_zone, _zone_goal, float(f["pull"]) * delta)
	_vel -= GRAVITY * delta
	_marker += _vel * delta
	if _marker <= 0.0:
		_marker = 0.0
		_vel = maxf(_vel, 0.0)
	elif _marker >= 1.0:
		_marker = 1.0
		_vel = minf(_vel, 0.0)
	var inside := absf(_marker - _zone) <= half
	_progress += (FILL_RATE if inside else -float(f["drain"])) * delta
	_zone_rect.position.x = (_zone - half) * TRACK_W
	_marker_rect.position.x = _marker * TRACK_W - _marker_rect.size.x * 0.5
	_marker_rect.color = Color(1, 1, 1) if inside else UITheme.DANGER
	_fill.size.x = clampf(_progress, 0.0, 1.0) * TRACK_W
	_bob(0.05, 9.0, -0.03)
	if _progress >= 1.0:
		_land()
	elif _progress <= 0.0 or _t > REEL_LIMIT:
		_finish("The line goes slack. It got away.", false)


## The fish is on the line: a short GatherSession lands it (a snapped line can lose it, skill and tackle
## decide the grade) and the catch comes off this spot's fish stock.
func _land() -> void:
	var landed := fish
	var node := {"kind": "fish", "item": landed, "level": 1 + Gathering.FISH_ORDER.find(landed) * 2,
		"qty": mini(3, deposits.units(dep_id(), dep_def(), WorldSim.day)), "quality": 50}
	_finish("The fish is on the line!", true)
	_panel = GatherRun.open(self, node, "Land the %s" % Life.item_name(landed), 0,
		hash([roundi(global_position.x), roundi(global_position.z), Engine.get_process_frames()]), _on_landed)
	if _panel == null:
		_on_landed({"ok": true, "item": landed, "count": 1, "consumed": 1, "tier": 1, "xp": 3, "skill": "fishing"})


func _on_landed(res: Dictionary) -> void:
	_panel = null
	var n: int = deposits.commit(dep_id(), dep_def(), res, WorldSim.day)
	if n <= 0:
		Game.say("It slips the hook.")
		return
	var item := String(res["item"])
	Crafting.give_item(Life, item, n, int(res.get("tier", 1)))
	Life.record("fished")
	var fish_name := Life.item_name(item)
	var text := "You caught %d %s!" % [n, fish_name] if n > 1 else "You caught %s %s!" % ["an" if "aeiou".contains(fish_name.substr(0, 1).to_lower()) else "a", fish_name]
	if item == "emberfin":
		text = "An emberfin! Its scales glow like coals in the dusk."
	text += GatherRun.deliver(res, 0)
	GatherRun.grant_xp(res)
	Game.say(text)


func _finish(text: String, caught: bool) -> void:
	if not caught:
		Game.say(text)
	if _status:
		_status.text = text
		_hint.text = ""
		_reel_box.visible = false
	if _bang:
		_bang.visible = false
	phase = Phase.DONE
	_t = 0.0
	if _ui == null:
		_close()


func _close() -> void:
	phase = Phase.IDLE
	fish = ""
	if _ui:
		_ui.queue_free()
		_ui = null
	if _bobber:
		_bobber.visible = false
	if _line:
		_line.visible = false
		_line_mesh.clear_surfaces()


# --- world bits ----------------------------------------------------------------------

func _player() -> Node3D:
	var pl: Variant = Life.player
	if pl is Node3D and is_instance_valid(pl):
		return pl
	return get_tree().get_first_node_in_group("player") as Node3D


func _water_level() -> float:
	var lv := WorldGen.water_level_at(water_point.x, water_point.z)
	return water_point.y if is_nan(lv) else lv


func _float_pos() -> Vector3:
	return Vector3(water_point.x, _water_level() + 0.02, water_point.z)


func _rod_tip() -> Vector3:
	var p := _player()
	var base := p.global_position if p else global_position
	var to := water_point - base
	to.y = 0.0
	return base + Vector3(0, 1.5, 0) + to.normalized() * 0.6


func _bob(amp: float, speed: float, sink := 0.0) -> void:
	if _bobber:
		var jitter := sin(_t * speed) * amp
		_bobber.global_position = _float_pos() + Vector3(0, jitter + sink, 0)


func _draw_line() -> void:
	if _line == null or not _line.visible or _bobber == null:
		return
	_line_mesh.clear_surfaces()
	var a := _rod_tip()
	var b := _bobber.global_position + Vector3(0, 0.06, 0)
	_line_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for i in 9:
		var k := i / 8.0
		var p := a.lerp(b, k)
		p.y -= sin(k * PI) * 0.35 * (0.3 if phase == Phase.REEL else 1.0)    # sag, taut when reeling
		_line_mesh.surface_add_vertex(p)
	_line_mesh.surface_end()


## A short stake with a lantern-coloured tip, so spots read from a distance.
func _build_marker() -> void:
	var post := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.035
	c.bottom_radius = 0.05
	c.height = 0.9
	c.radial_segments = 6
	c.rings = 1
	post.mesh = c
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.38, 0.27, 0.17)
	post.material_override = m
	post.position = Vector3(0, 0.45, 0)
	post.visibility_range_end = 60.0
	add_child(post)
	var tag := Label3D.new()
	tag.text = "Fishing"
	tag.font_size = 30
	tag.fixed_size = true
	tag.pixel_size = 0.0016
	tag.outline_size = 8
	tag.modulate = Color(0.95, 0.9, 0.75)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.position = Vector3(0, 1.15, 0)
	tag.visibility_range_end = 14.0
	add_child(tag)


func _build_bobber() -> void:
	if _bobber:
		return
	_bobber = Node3D.new()
	_bobber.top_level = true
	add_child(_bobber)
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.85, 0.15, 0.1)
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.95, 0.95, 0.92)
	for i in 2:
		var mi := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = 0.07
		s.height = 0.07
		s.is_hemisphere = true
		s.radial_segments = 10
		s.rings = 3
		mi.mesh = s
		mi.material_override = white if i == 0 else red
		mi.rotation.x = 0.0 if i == 0 else PI
		_bobber.add_child(mi)
	_bang = Label3D.new()
	_bang.text = "!"
	_bang.font_size = 96
	_bang.pixel_size = 0.006
	_bang.outline_size = 16
	_bang.modulate = UITheme.ACCENT
	_bang.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bang.no_depth_test = true
	_bang.position = Vector3(0, 0.45, 0)
	_bang.visible = false
	_bobber.add_child(_bang)
	_line_mesh = ImmediateMesh.new()
	_line = MeshInstance3D.new()
	_line.mesh = _line_mesh
	_line.top_level = true
	var lm := StandardMaterial3D.new()
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lm.albedo_color = Color(0.9, 0.9, 0.85, 0.8)
	_line.material_override = lm
	_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_line)


func _build_ui() -> void:
	if _ui:
		_ui.queue_free()
	_ui = CanvasLayer.new()
	_ui.layer = 30
	add_child(_ui)
	# Taps anywhere count (phones); the Stop button sits above and eats its own.
	var blocker := Control.new()
	blocker.set_anchors_preset(Control.PRESET_FULL_RECT)
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	blocker.gui_input.connect(func(e: InputEvent) -> void:
		if (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT) \
				or (e is InputEventScreenTouch and e.pressed):
			_tap()
			blocker.accept_event())
	_ui.add_child(blocker)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.panel_box())
	panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	panel.custom_minimum_size = Vector2(TRACK_W + 40.0, 0)
	panel.offset_left = -(TRACK_W + 40.0) * 0.5
	panel.offset_right = (TRACK_W + 40.0) * 0.5
	panel.offset_top = -300.0
	panel.offset_bottom = -120.0
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	blocker.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(box)
	var title := Label.new()
	title.text = "Fishing  ·  %s" % water_name
	title.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	box.add_child(title)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 26)
	_status.add_theme_color_override("font_color", UITheme.TEXT)
	box.add_child(_status)
	_reel_box = VBoxContainer.new()
	_reel_box.add_theme_constant_override("separation", 6)
	_reel_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_reel_box)
	_track = Control.new()
	_track.custom_minimum_size = Vector2(TRACK_W, 34)
	_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_track.clip_contents = true
	_reel_box.add_child(_track)
	var bg := ColorRect.new()
	bg.color = Color(1, 1, 1, 0.08)
	bg.size = Vector2(TRACK_W, 34)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_track.add_child(bg)
	_zone_rect = ColorRect.new()
	_zone_rect.color = Color(UITheme.ACCENT, 0.55)
	_zone_rect.size = Vector2(TRACK_W * 0.3, 34)
	_zone_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_track.add_child(_zone_rect)
	_marker_rect = ColorRect.new()
	_marker_rect.color = Color.WHITE
	_marker_rect.size = Vector2(8, 34)
	_marker_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_track.add_child(_marker_rect)
	var catch_bar := Control.new()
	catch_bar.custom_minimum_size = Vector2(TRACK_W, 10)
	catch_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reel_box.add_child(catch_bar)
	var cbg := ColorRect.new()
	cbg.color = Color(1, 1, 1, 0.08)
	cbg.size = Vector2(TRACK_W, 10)
	cbg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	catch_bar.add_child(cbg)
	_fill = ColorRect.new()
	_fill.color = UITheme.OK
	_fill.size = Vector2(0, 10)
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	catch_bar.add_child(_fill)
	_hint = Label.new()
	_hint.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_hint)
	var stop := Button.new()
	stop.text = "Stop fishing"
	stop.focus_mode = Control.FOCUS_NONE
	stop.pressed.connect(func() -> void: _finish("You reel in the line.", false))
	box.add_child(stop)


# --- dispatch --------------------------------------------------------------------

## Self-dispatch of the interact key while this is the nearest interactable.
func _poll_interact() -> void:
	var p := _player()
	if p == null or p.global_position.distance_squared_to(global_position) > 3.3 * 3.3:
		_menu_was_open = false
		return
	var menu_open := _menu_open()
	var was := _menu_was_open
	_menu_was_open = menu_open
	if menu_open or was or not Input.is_action_just_pressed("interact"):
		return
	if p.has_method("nearest_interactable") and p.call("nearest_interactable") == self:
		use()


func _menu_open() -> bool:
	var scene := get_tree().current_scene
	var hud: Variant = scene.get("hud") if scene else null
	return hud is Object and is_instance_valid(hud) and (hud as Object).has_method("is_menu_open") \
		and bool((hud as Object).call("is_menu_open"))
