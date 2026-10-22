extends Control
## Radial technique wheel. Hold the `technique_wheel` action (T / right shoulder) or long-press a technique slot;
## the world slows while it is open, the wedge under the pointer / stick glows, the hub shows the live name, cost and
## recharge, and releasing (or tapping a wedge) casts it with a dissolve. Touch: keep the finger down, slide, lift.
## Keyboard: hold T and point with the mouse, or arrows / 1-8; a quick tap keeps it open until you click, press T or Esc.
## Controller: hold the shoulder button and push a stick.
##
## Time safeguards: Engine.time_scale is held at SLOW_SCALE only while open, restored on close, on _exit_tree, on
## hide, on pause, on death, on focus loss, after MAX_OPEN real seconds, and whenever the Slow Time setting is off.
## A hit-stop (player.gd) briefly sets its own scale; the wheel never fights it.
##
##   var w := preload("res://scripts/ui/technique_wheel.gd").new()
##   hud_root.add_child(w)

signal confirmed(id: String)
signal closed

const Model := preload("res://scripts/ui/technique_wheel_model.gd")
const AF := preload("res://scripts/ui/ashes_frame.gd")
const HudArt := preload("res://scripts/ui/hud_art.gd")
const SettingsStore := preload("res://scripts/ui/frontend/settings_store.gd")

const SLOW_SCALE := 0.2
const MAX_OPEN := 12.0            # real seconds before the wheel gives up and cancels
const STICKY_TAP := 0.25          # a press shorter than this keeps the wheel open
const OPEN_TIME := 0.16
const DISSOLVE_TIME := 0.3
const REFRESH := 0.1

var caster: Node
var player: Node
## Set by the HUD: returns false while a menu / dialogue / map owns the screen.
var allowed := Callable()
## Test hook: when set, used instead of gathering from the caster.
var entries_override: Array = []

var is_open := false
var hover := -1
var source := "key"                # key | touch | pad
var entries: Array = []

var _sticky := false
var _press_real := 0.0
var _open_real := 0.0
var _last_us := 0
var _open_t := 0.0
var _dissolve_t := -1.0
var _dissolve_idx := -1
var _pointer := Vector2.ZERO
var _refresh := 0.0
var _slowing := false
var _font: Font
var _body: Font
var _shards: Array = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_font = AF.title_font(700)
	_body = AF.font()
	set_process(false)


func _exit_tree() -> void:
	_restore_time()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		if is_open:
			close_wheel(false)
	elif what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree() and is_open:
		close_wheel(false)


# --- open / close ----------------------------------------------------------------------

func can_open() -> bool:
	if is_open or not is_inside_tree() or get_tree().paused:
		return false
	if player != null and is_instance_valid(player) and player.get("dead") == true:
		return false
	if allowed.is_valid() and not bool(allowed.call()):
		return false
	return true


## `at`: where the pointer / finger is (touch); ZERO uses the mouse.
func open_wheel(src := "key", at := Vector2.ZERO) -> bool:
	if not can_open():
		return false
	_gather()
	if entries.is_empty():
		return false
	source = src
	is_open = true
	hover = -1
	_sticky = false
	_open_real = 0.0
	_press_real = 0.0
	_open_t = 0.0
	_dissolve_t = -1.0
	_last_us = Time.get_ticks_usec()
	_pointer = at if at != Vector2.ZERO else get_viewport().get_mouse_position()
	visible = true
	set_process(true)
	_apply_time()
	queue_redraw()
	return true


## confirm = cast the hovered wedge (with the dissolve); else just close.
func close_wheel(confirm := false) -> void:
	if not is_open:
		return
	var idx := hover
	is_open = false
	_restore_time()
	if confirm and idx >= 0 and idx < entries.size():
		_dissolve_idx = idx
		_dissolve_t = 0.0
		_build_shards(idx)
		var id := String((entries[idx] as Dictionary)["id"])
		_cast(id)
		confirmed.emit(id)
	else:
		_dissolve_idx = -1
		_dissolve_t = 1.0      # fade the whole ring quickly
	closed.emit()


func _cast(id: String) -> void:
	if caster != null and is_instance_valid(caster) and caster.has_method("cast_technique"):
		caster.call("cast_technique", id, false)


func _gather() -> void:
	if not entries_override.is_empty():
		entries = entries_override.duplicate()
		return
	if caster == null or not is_instance_valid(caster):
		caster = _find_caster()
	entries = []
	if caster == null:
		return
	var skills: RefCounted = caster.get("skills")
	var power: Array = []
	var life := get_node_or_null("/root/Life")
	if life != null and life.get("realm") != null:
		var hub: Variant = life.get("realm")
		if hub is Object and (hub as Object).has_method("mod") and (hub.get("mods") as Dictionary).has("power_paths"):
			var pp: Object = hub.mod("power_paths")
			if pp != null:
				power = pp.call("known_techniques")
	var pools: Dictionary = caster.call("pools") if caster.has_method("pools") else {}
	for id in Model.gather_ids(skills, power):
		var left := -1.0
		if skills == null or not skills.techniques.has(id):
			left = float(caster.call("_hook_cooldown_left", id)) if caster.has_method("_hook_cooldown_left") else 0.0
		entries.append(Model.entry(id, skills, pools, left))


func _find_caster() -> Node:
	for p in get_tree().get_nodes_in_group("player"):
		var c := (p as Node).get_node_or_null("TechniqueCaster")
		if c:
			return c
	return null


# --- time ------------------------------------------------------------------------------

func _slow_wanted() -> bool:
	var on := true
	var v: Variant = SettingsStore.get_value("wheel_slow")
	if v != null:
		on = bool(v)
	var hit_stop: bool = player != null and is_instance_valid(player) and bool(player.get("_hit_stopping"))
	return Model.slow_scale(on, hit_stop) < 1.0


func _apply_time() -> void:
	if not is_open:
		return
	if _slow_wanted():
		Engine.time_scale = SLOW_SCALE
		_slowing = true


func _restore_time() -> void:
	if _slowing:
		_slowing = false
		Engine.time_scale = 1.0


# --- input -----------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not is_open:
		if event.is_action_pressed("technique_wheel") and not (event is InputEventKey and event.echo):
			if open_wheel("pad" if event is InputEventJoypadButton else "key"):
				get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("technique_wheel") and not (event is InputEventKey and event.echo):
		close_wheel(hover >= 0)      # the sticky wheel: press again to take the hovered wedge
		get_viewport().set_input_as_handled()
	elif event.is_action_released("technique_wheel"):
		if source != "touch":
			if _press_real < STICKY_TAP and source == "key" and not _sticky:
				_sticky = true
			elif not _sticky:
				close_wheel(hover >= 0)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		close_wheel(false)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		_point((event as InputEventMouseMotion).position)
	elif event is InputEventScreenDrag:
		_point((event as InputEventScreenDrag).position)
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		_point(st.position)
		if not st.pressed:
			close_wheel(hover >= 0)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_point((event as InputEventMouseButton).position)
		close_wheel(hover >= 0)
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		_key(event as InputEventKey)


func _key(e: InputEventKey) -> void:
	var n := entries.size()
	match e.physical_keycode:
		KEY_RIGHT, KEY_D, KEY_DOWN:
			hover = Model.step_wedge(hover, 1, n)
		KEY_LEFT, KEY_A, KEY_UP:
			hover = Model.step_wedge(hover, -1, n)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			close_wheel(hover >= 0)
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8:
			var i := int(e.physical_keycode) - KEY_1
			if i < n:
				hover = i
				close_wheel(true)
		_:
			return
	get_viewport().set_input_as_handled()
	queue_redraw()


func ring_centre() -> Vector2:
	return size * 0.5


func ring_radius() -> float:
	return clampf(minf(size.x, size.y) * 0.4, 150.0, 240.0)


func _point(p: Vector2) -> void:
	_pointer = p
	hover = Model.wedge_at(p - ring_centre(), entries.size(), ring_radius() * 0.62)
	queue_redraw()


## Controller sticks drive the hover while open.
func _stick() -> void:
	for pair: Array in [[JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y], [JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y]]:
		var v := Vector2(Input.get_joy_axis(0, pair[0]), Input.get_joy_axis(0, pair[1]))
		if v.length() > 0.55:
			hover = Model.wedge_at(v, entries.size(), 1.0)
			return


func _process(_delta: float) -> void:
	# Real time: the world (and this node's delta) is slowed while the wheel is open.
	var now := Time.get_ticks_usec()
	var rd := clampf(float(now - _last_us) / 1e6, 0.0, 0.1)
	_last_us = now
	if is_open:
		_open_real += rd
		if Input.is_action_pressed("technique_wheel"):
			_press_real += rd
		_open_t = minf(_open_t + rd / OPEN_TIME, 1.0)
		_refresh -= rd
		if _refresh <= 0.0:
			_refresh = REFRESH
			_refresh_entries()
		_stick()
		_apply_time()
		var dead: bool = player != null and is_instance_valid(player) and player.get("dead") == true
		if _open_real > MAX_OPEN or get_tree().paused or dead or (allowed.is_valid() and not bool(allowed.call())):
			close_wheel(false)
	elif _dissolve_t >= 0.0:
		_dissolve_t += rd / (DISSOLVE_TIME if _dissolve_idx >= 0 else 0.12)
		if _dissolve_t >= 1.0:
			_dissolve_t = -1.0
			visible = false
			set_process(false)
	else:
		visible = false
		set_process(false)
	queue_redraw()


func _refresh_entries() -> void:
	if not entries_override.is_empty() or caster == null or not is_instance_valid(caster):
		return
	var skills: RefCounted = caster.get("skills")
	var pools: Dictionary = caster.call("pools") if caster.has_method("pools") else {}
	for i in entries.size():
		var id := String((entries[i] as Dictionary)["id"])
		var left := -1.0
		if skills == null or not skills.techniques.has(id):
			left = float(caster.call("_hook_cooldown_left", id)) if caster.has_method("_hook_cooldown_left") else 0.0
		entries[i] = Model.entry(id, skills, pools, left)


# --- drawing: ink-brush AshesFrame wedges ----------------------------------------------

func _wedge_poly(i: int, n: int, r_in: float, r_out: float, grow := 0.0, jitter := 0.0) -> PackedVector2Array:
	var step := TAU / float(n)
	var gap := 0.045
	var a0 := Model.wedge_angle(i, n) - step * 0.5 + gap + grow * 0.0
	var a1 := Model.wedge_angle(i, n) + step * 0.5 - gap
	var steps := maxi(4, int(24.0 / float(n)) + 4)
	var pts := PackedVector2Array()
	var c := ring_centre()
	for k in steps + 1:
		var a := lerpf(a0, a1, float(k) / steps)
		var j := 1.0 + jitter * sin(a * 23.0 + float(i) * 1.7) * 0.012
		pts.append(c + Vector2(sin(a), -cos(a)) * (r_out + grow) * j)
	for k in steps + 1:
		var a := lerpf(a1, a0, float(k) / steps)
		pts.append(c + Vector2(sin(a), -cos(a)) * (r_in - grow * 0.4))
	return pts


func _draw() -> void:
	if entries.is_empty():
		return
	var n := entries.size()
	var fade := 1.0
	if not is_open:
		fade = 1.0 - smoothstep(0.0, 1.0, maxf(_dissolve_t, 0.0)) if _dissolve_idx < 0 else 1.0
	var open_k := smoothstep(0.0, 1.0, _open_t)
	var a := open_k * fade
	var c := ring_centre()
	var r_out := ring_radius() * (0.86 + 0.14 * open_k)
	var r_in := r_out * 0.4
	# Vignette that pulls the eye in without hiding the fight.
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.015, 0.01, 0.38 * a))
	draw_circle(c, r_out + 18.0, Color(0.02, 0.015, 0.01, 0.35 * a))
	for i in n:
		var e: Dictionary = entries[i]
		var dissolving := _dissolve_idx == i and not is_open
		if dissolving:
			continue
		var col: Color = e["color"]
		var hot := i == hover and is_open
		var ready := bool(e["ready"])
		var wa := a * (0.5 if (not is_open and _dissolve_idx >= 0) else 1.0) * (1.0 - (_dissolve_t if _dissolve_idx >= 0 and not is_open else 0.0))
		var fill := Color(AF.PANEL.r, AF.PANEL.g, AF.PANEL.b, 0.88 * wa).lerp(col.darkened(0.55), 0.22 if ready else 0.05)
		draw_colored_polygon(_wedge_poly(i, n, r_in, r_out), fill)
		if hot:
			for layer in 4:            # focus glow: stacked translucent rims, brightest at the edge
				var g := _wedge_poly(i, n, r_in, r_out, 5.0 + layer * 5.0)
				draw_colored_polygon(g, Color(col.r, col.g, col.b, 0.07 * wa))
			draw_colored_polygon(_wedge_poly(i, n, r_in, r_out), Color(col.r, col.g, col.b, 0.22 * wa))
		# Ink-brush edge: a heavy jittered stroke under a gold hairline.
		var edge := _wedge_poly(i, n, r_in, r_out, 0.0, 1.0)
		edge.append(edge[0])
		draw_polyline(edge, Color(0.0, 0.0, 0.0, 0.8 * wa), 5.0 if hot else 3.5, true)
		draw_polyline(edge, Color(AF.GOLD_BRIGHT if hot else AF.GOLD_DIM, (1.0 if hot else 0.8) * wa), 2.0 if hot else 1.0, true)
		if not ready:
			draw_colored_polygon(_wedge_poly(i, n, r_in, r_out), Color(0.02, 0.02, 0.04, 0.45 * wa))
			var left := float(e["left"])
			if left > 0.0 and float(e["cooldown"]) > 0.0:
				var frac := clampf(left / float(e["cooldown"]), 0.0, 1.0)
				var ang := Model.wedge_angle(i, n)
				var mid := c + Vector2(sin(ang), -cos(ang)) * (r_in + (r_out - r_in) * 0.5)
				draw_arc(mid, 26.0, -PI * 0.5, -PI * 0.5 + TAU * frac, 24, Color(AF.GOLD, 0.5 * wa), 2.0, true)
		# Glyph + caption.
		var ang2 := Model.wedge_angle(i, n)
		var mid2 := c + Vector2(sin(ang2), -cos(ang2)) * (r_in + (r_out - r_in) * 0.5)
		var disc := Color(col.r, col.g, col.b, (0.95 if ready else 0.35) * wa)
		draw_circle(mid2, 25.0 if hot else 22.0, Color(0, 0, 0, 0.55 * wa))
		draw_arc(mid2, 25.0 if hot else 22.0, 0.0, TAU, 28, disc, 2.5, true)
		var ini := _initials(String(e["name"]))
		draw_string(_font, mid2 + Vector2(-30, 7), ini, HORIZONTAL_ALIGNMENT_CENTER, 60, 20, Color(AF.TEXT, wa * (1.0 if ready else 0.5)))
		var cap_pos := mid2 + Vector2(-60, 43)
		draw_string_outline(_body, cap_pos, String(e["name"]), HORIZONTAL_ALIGNMENT_CENTER, 120, 14, 4, Color(0, 0, 0, 0.8 * wa))
		draw_string(_body, cap_pos, String(e["name"]), HORIZONTAL_ALIGNMENT_CENTER, 120, 14,
			Color(AF.GOLD_BRIGHT if hot else AF.TEXT, wa * (1.0 if ready else 0.55)))
	# Hub.
	draw_circle(c, r_in - 8.0, Color(AF.PANEL.r, AF.PANEL.g, AF.PANEL.b, 0.94 * a))
	draw_arc(c, r_in - 8.0, 0.0, TAU, 56, Color(0, 0, 0, 0.8 * a), 4.0, true)
	draw_arc(c, r_in - 8.0, 0.0, TAU, 56, Color(AF.GOLD, 0.9 * a), 1.2, true)
	var shown: Dictionary = entries[hover] if hover >= 0 and hover < n else {}
	if not is_open and _dissolve_idx >= 0:
		shown = entries[_dissolve_idx]
	var lines := Model.hub_lines(shown)
	var w := (r_in - 14.0) * 2.0
	var ty := c.y - 6.0
	draw_string(_font, Vector2(c.x - w * 0.5, ty - 10.0), String(lines["name"]), HORIZONTAL_ALIGNMENT_CENTER, w, 17, Color(AF.GOLD_BRIGHT, a))
	if String(lines["cost"]) != "":
		draw_string(_body, Vector2(c.x - w * 0.5, ty + 14.0), String(lines["cost"]), HORIZONTAL_ALIGNMENT_CENTER, w, 15, Color(AF.TEXT, a))
	var ok := shown.is_empty() or bool(shown.get("ready", false))
	draw_string(_body, Vector2(c.x - w * 0.5, ty + 34.0), String(lines["state"]), HORIZONTAL_ALIGNMENT_CENTER, w, 13,
		Color(AF.TEXT_DIM if ok else Color("e0a070"), a))
	if is_open:
		var hint := "Hold, slide, release" if source == "touch" else ("Stick to aim, release to cast" if source == "pad" else "Point, click or release T. Esc cancels")
		draw_string(_body, Vector2(c.x - 200.0, c.y + r_out + 34.0), hint, HORIZONTAL_ALIGNMENT_CENTER, 400, 14, Color(AF.TEXT_DIM, a))
	# Dissolve of the chosen wedge: shards drift outward and fade, ink-like.
	if not is_open and _dissolve_idx >= 0 and _dissolve_t >= 0.0:
		_draw_dissolve(n, r_in, r_out)


func _build_shards(idx: int) -> void:
	_shards = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 7000 + idx
	for k in 12:
		_shards.append({"u": float(k % 4) / 4.0, "v": float(k / 4) / 3.0, "thr": rng.randf_range(0.0, 0.45), "drift": rng.randf_range(16.0, 46.0)})


func _draw_dissolve(n: int, r_in: float, r_out: float) -> void:
	if _dissolve_idx >= entries.size():
		return
	var e: Dictionary = entries[_dissolve_idx]
	var col: Color = e["color"]
	var c := ring_centre()
	var step := TAU / float(n)
	var base := Model.wedge_angle(_dissolve_idx, n)
	for s: Dictionary in _shards:
		var t := clampf((_dissolve_t - float(s["thr"])) / 0.55, 0.0, 1.0)
		var al := 1.0 - t
		if al <= 0.0:
			continue
		var a0 := base - step * 0.5 + 0.045 + (step - 0.09) * float(s["u"])
		var a1 := a0 + (step - 0.09) * 0.25
		var r0 := lerpf(r_in, r_out, float(s["v"]))
		var r1 := lerpf(r_in, r_out, minf(float(s["v"]) + 0.34, 1.0))
		var out := Vector2(sin(base), -cos(base)) * float(s["drift"]) * t
		var pts := PackedVector2Array()
		for k in 4:
			var a := lerpf(a0, a1, float(k) / 3.0)
			pts.append(c + out + Vector2(sin(a), -cos(a)) * r1)
		for k in 4:
			var a := lerpf(a1, a0, float(k) / 3.0)
			pts.append(c + out + Vector2(sin(a), -cos(a)) * r0)
		draw_colored_polygon(pts, Color(col.r, col.g, col.b, 0.55 * al).lerp(Color(AF.GOLD_BRIGHT, 0.7 * al), t * 0.4))


static func _initials(n: String) -> String:
	var words := n.replace("-", " ").split(" ", false)
	if words.size() >= 2:
		return (words[0].left(1) + words[1].left(1)).to_upper()
	return n.left(2)
