extends Control
## The tactical battle map (docs/design/WAR_COMMAND_RULEBOOK.md §1-2, §25-40, §48-50; reference panels "Tactical Battle Map",
## "Battle Deployment", "Live Battle Command"). Shows a Tactical battle (scripts/realm/tactical.gd) on the real ground in the
## three display styles of the war map, with unit blocks (facing, formation, depth layers), drag orders, the behaviour menu,
## time controls, the battle information panel, fog of war, range rings and contour lines. Nothing here runs per frame
## except the step clock while the battle plays; the map redraws when a step has been taken or the player acts.

signal closed
signal finished(result: Dictionary)

const AF := preload("res://scripts/ui/ashes_frame.gd")
const Kit := preload("res://scripts/ui/gamemenu/gm_kit.gd")
const Tokens := preload("res://scripts/ui/war/war_tokens.gd")
const Radial := preload("res://scripts/ui/war/war_radial.gd")
const Extras := preload("res://scripts/ui/war/war_extras.gd")
const Tac := preload("res://scripts/realm/tactical.gd")
const WarUnits := preload("res://scripts/realm/war_units.gd")
const WarAdvisors := preload("res://scripts/realm/war_advisors.gd")

const SPEEDS := [["Pause", 0.0], ["Normal", 1.0], ["Fast", 2.0], ["x2", 4.0], ["x5", 10.0]]
const PANEL_W := 330.0
const STRIP_W := 98.0
const ORDER_COL := {"advance": Color("5aa0ff"), "charge": Color("ff7a4a"), "retreat": Color("f0d060"), "fallback": Color("f0d060"), "withdraw_fighting": Color("f0d060"),
	"flank": Color("5fe0d0"), "harass": Color("c58cff"), "march": Color("5aa0ff"), "intercept": Color("ff7a4a"), "commit": Color("ff7a4a"), "feint": Color("c58cff"),
	"screen": Color("9fb4d0"), "defend": Color("9be36a"), "hide": Color("9fb4d0"), "focus_fire": Color("ff5050"), "reserve": Color("9fb4d0")}

var tt: RefCounted = null            # the Tactical battle
var cm: RefCounted = null            # campaign (optional): result is written back through it
var eng_id := -1
var on_done := Callable()
var style := Tokens.TACTICAL
var side := 0                        # the viewer's side (0 or 1)
var speed_idx := 1
var sel: Array = []
var show_range := false
var show_contours := false
var target_mode := false
var embedded := false
var panel_tab := "info"
var status_text := ""

var _units: Array = []              # units_view cache
var _canvas: Control
var _layer: Control
var _panel: VBoxContainer
var _panel_scroll: ScrollContainer
var _strip: VBoxContainer
var _strip_scroll: ScrollContainer
var _row: BoxContainer
var _radial: Control
var _toast: Label
var _title: Label
var _clock: Label
var _speed_btns: Array = []
var _style_btns: Array = []
var _deploy_bar: Control
var _cmd_bar: Control
var _form_popup: Control
var _tex: ImageTexture
var _tex_sig := ""
var _contours: Array = []
var _mask := PackedByteArray()
var _mask_step := -99
var _seen_cells := PackedByteArray()
var _fog_tex: ImageTexture
var _fog_step := -99
var _font: Font
var _title_font: Font
var _zoom := 1.0
var _origin := Vector2.ZERO
var _fit := 1.0
var _drag: Dictionary = {}
var _pan_from := Vector2.ZERO
var _press := Vector2.ZERO
var _press_unit := -1
var _acc := 0.0
var _built := false
var _sig_panel := ""
var _form_state := {"name": "line", "width": 12, "depth": 3, "spacing": 1.0, "ranged_behind": true, "cav": true}
var _ended_handled := false
var _advice: Array = []
var _advice_tick := -1


## Opens the battle over `host`. Returns the view.
static func open_modal(host: Node, battle: RefCounted, campaign: RefCounted = null, engagement := -1, done := Callable()) -> Control:
	var layer := CanvasLayer.new()
	layer.layer = 75
	layer.name = "TacticalLayer"
	var v: Control = load("res://scripts/ui/war/tactical_view.gd").new()
	v.set("tt", battle)
	v.set("cm", campaign)
	v.set("eng_id", engagement)
	v.set("on_done", done)
	layer.add_child(v)
	v.connect("closed", layer.queue_free)
	host.add_child(layer)
	return v


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	clip_contents = true
	_font = AF.font(AF.BODY_FONT)
	_title_font = AF.title_font(700)
	if tt != null:
		_build()


func set_battle(battle: RefCounted) -> void:
	tt = battle
	if is_inside_tree() and not _built:
		_build()


func _side_is_player(k: int) -> bool:
	return bool((tt.S[k] as Dictionary)["player"])


func _build() -> void:
	if _built or tt == null:
		return
	_built = true
	side = 0 if _side_is_player(0) or not _side_is_player(1) else 1
	tt.auto[side] = false
	_row = BoxContainer.new()
	_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_row.add_theme_constant_override("separation", 0)
	add_child(_row)
	_canvas = Control.new()
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.clip_contents = true
	_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_canvas.gui_input.connect(_canvas_input)
	_canvas.resized.connect(_on_resized)
	_row.add_child(_canvas)
	_layer = MapLayer.new()
	_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.set("view", self)
	_canvas.add_child(_layer)
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(PANEL_W, 260)
	pc.add_theme_stylebox_override("panel", Kit.box(Color(0.035, 0.03, 0.027, 0.97), AF.GOLD_DIM, 0, 10))
	_row.add_child(pc)
	_panel_scroll = ScrollContainer.new()
	_panel_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pc.add_child(_panel_scroll)
	_panel = VBoxContainer.new()
	_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panel.add_theme_constant_override("separation", 6)
	_panel_scroll.add_child(_panel)
	_build_toolbar()
	_build_strip()
	_build_bottom()
	_toast = Kit.lbl("", 18, AF.GOLD_BRIGHT, true, "italic")
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_toast.offset_left = -300
	_toast.offset_right = 300
	_toast.offset_top = 92
	_toast.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_toast.add_theme_constant_override("outline_size", 6)
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_canvas.add_child(_toast)
	_radial = Radial.new()
	_radial.picked.connect(_on_behavior_picked)
	_radial.cancelled.connect(func() -> void: pass)
	_canvas.add_child(_radial)
	set_process(true)
	_relayout()
	_fit_view()
	_refresh(true)


func _on_resized() -> void:
	_fit_view()
	_relayout()
	_layer.queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _built:
		_relayout()


func _relayout() -> void:
	if not _built:
		return
	var portrait := size.x < size.y or size.x < 820.0
	_row.vertical = portrait
	var pc := _panel_scroll.get_parent() as Control
	pc.custom_minimum_size = Vector2(0, size.y * 0.36) if portrait else Vector2(PANEL_W, 0)


# ----------------------------------------------------------------- build --

func _styled(text: String, on: bool, cb: Callable, min_w := 0.0) -> Button:
	var b := Kit.tab_button(text, on, cb, min_w)
	b.custom_minimum_size.y = 46
	return b


func _build_toolbar() -> void:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", Kit.box(Color(0.03, 0.028, 0.025, 0.88), AF.GOLD_DIM, 4, 6))
	bar.position = Vector2(8, 8)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	bar.add_child(v)
	var h1 := HBoxContainer.new()
	h1.add_theme_constant_override("separation", 6)
	v.add_child(h1)
	_title = Kit.lbl("", 19, AF.GOLD_BRIGHT, false, "title_bold")
	_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h1.add_child(_title)
	_clock = Kit.lbl("Time 00:00:00", 17, AF.TEXT)
	_clock.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h1.add_child(_clock)
	var h2 := HBoxContainer.new()
	h2.add_theme_constant_override("separation", 6)
	v.add_child(h2)
	for i in Tokens.STYLE_NAMES.size():
		var b := _styled(Tokens.STYLE_NAMES[i], i == style, set_style.bind(i), 100)
		h2.add_child(b)
		_style_btns.append(b)
	h2.add_child(_styled("Leave" if eng_id >= 0 else "Close", false, close, 74))
	_canvas.add_child(bar)


func _build_strip() -> void:
	_strip_scroll = ScrollContainer.new()
	_strip_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_strip_scroll.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	_strip_scroll.offset_left = 6
	_strip_scroll.offset_right = STRIP_W + 6
	_strip_scroll.offset_top = 118
	_strip_scroll.offset_bottom = -132
	_strip = VBoxContainer.new()
	_strip.add_theme_constant_override("separation", 4)
	_strip_scroll.add_child(_strip)
	_canvas.add_child(_strip_scroll)


func _build_bottom() -> void:
	# time controls (panel: Pause / Normal / Fast / x2 / x5) and map toggles
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
	v.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	v.offset_left = 8
	v.offset_right = -8
	v.offset_bottom = -8
	v.offset_top = -126
	v.alignment = BoxContainer.ALIGNMENT_END
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cmd_bar = HBoxContainer.new()
	_cmd_bar.add_theme_constant_override("separation", 4)
	v.add_child(_cmd_bar)
	_deploy_bar = HBoxContainer.new()
	_deploy_bar.add_theme_constant_override("separation", 4)
	v.add_child(_deploy_bar)
	var tc := HBoxContainer.new()
	tc.add_theme_constant_override("separation", 4)
	v.add_child(tc)
	for i in SPEEDS.size():
		var b := _styled(String((SPEEDS[i] as Array)[0]), i == speed_idx, set_speed.bind(i), 66)
		tc.add_child(b)
		_speed_btns.append(b)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tc.add_child(sp)
	var rng := Kit.tab_button("Range", show_range, func() -> void: show_range = not show_range; _restyle_toggles(); _layer.queue_redraw(), 66)
	var con := Kit.tab_button("Contours", show_contours, func() -> void: show_contours = not show_contours; _restyle_toggles(); _layer.queue_redraw(), 90)
	rng.name = "RangeBtn"
	con.name = "ContoursBtn"
	for b2: Button in [rng, con]:
		b2.custom_minimum_size.y = 46
		tc.add_child(b2)
	for b3: Array in [["+", zoom_in], ["-", zoom_out], ["Fit", _fit_view_and_redraw]]:
		var z := Kit.button(String(b3[0]), false, 46.0, 22)
		z.custom_minimum_size = Vector2(46, 46)
		z.pressed.connect(b3[1])
		tc.add_child(z)
	_canvas.add_child(v)


func _restyle(b: Button, on: bool) -> void:
	var normal := Kit.box(Color(0.03, 0.028, 0.025, 0.6), AF.GOLD_DIM, 3, 8)
	var lit := Kit.box(Color(AF.GOLD.r, AF.GOLD.g, AF.GOLD.b, 0.22), AF.GOLD, 3, 8)
	b.add_theme_stylebox_override("normal", lit if on else normal)
	b.add_theme_stylebox_override("focus", lit if on else normal)
	b.add_theme_color_override("font_color", AF.GOLD_BRIGHT if on else AF.TEXT_DIM)


func _restyle_toggles() -> void:
	for i in _speed_btns.size():
		_restyle(_speed_btns[i], i == speed_idx)
	for i in _style_btns.size():
		_restyle(_style_btns[i], i == style)
	var r := _canvas.find_child("RangeBtn", true, false) as Button
	var c := _canvas.find_child("ContoursBtn", true, false) as Button
	if r:
		_restyle(r, show_range)
	if c:
		_restyle(c, show_contours)


# ---------------------------------------------------------------- state --

func set_style(s: int) -> void:
	style = clampi(s, 0, 2)
	_tex_sig = ""
	_restyle_toggles()
	_refresh(true)


func set_speed(i: int) -> void:
	speed_idx = clampi(i, 0, SPEEDS.size() - 1)
	_restyle_toggles()


func say(text: String) -> void:
	status_text = text
	if _toast:
		_toast.text = text
		var t := get_tree().create_timer(6.0)
		t.timeout.connect(func() -> void:
			if is_instance_valid(_toast) and _toast.text == text:
				_toast.text = "")


func close() -> void:
	if tt != null:
		tt.auto[side] = true
	if cm != null and eng_id >= 0:
		if String(tt.phase) == "ended":
			cm.call("tactical_apply", eng_id)
		else:
			cm.call("tactical_leave", eng_id)
	if on_done.is_valid():
		on_done.call()
	closed.emit()


func is_deploying() -> bool:
	return tt != null and String(tt.phase) == "deploy"


func start_battle() -> void:
	if not is_deploying():
		return
	tt.begin()
	_fit_view()
	say("The armies advance.")
	speed_idx = 1
	_restyle_toggles()
	_refresh(true)


func _process(delta: float) -> void:
	if not _built or tt == null:
		return
	var sp := float((SPEEDS[speed_idx] as Array)[1])
	if String(tt.phase) != "battle" or sp <= 0.0 or not tt.pending_duel.is_empty():
		return
	_acc += delta * sp
	var n := 0
	while _acc >= 1.0 and n < 12:
		_acc -= 1.0
		tt.step()
		n += 1
		if String(tt.phase) != "battle" or not tt.pending_duel.is_empty():
			break
	if n > 0:
		_refresh(false)


func step_once(count := 1) -> void:
	tt.advance(count)
	_refresh(false)


## Rebuilds the cached view of the field and redraws. full: also rebuild the panel and strip.
func _refresh(full: bool) -> void:
	if tt == null or not _built:
		return
	_units = tt.units_view(side)
	var keep: Array = []
	for i: int in sel:
		for u: Dictionary in _units:
			if int(u["i"]) == i and int(u["side"]) == side:
				keep.append(i)
				break
	sel = keep
	_title.text = "%s - %s" % [String(tt.name), String(tt.terrain_name)]
	_clock.text = "Time: %s" % tt.time_text()
	if int(tt.step_no) - _mask_step >= 3 or full:
		_mask = tt.visible_mask(side)
		_mask_step = int(tt.step_no)
		for k in _mask.size():
			if _mask[k] == 2:
				if _seen_cells.size() != _mask.size():
					_seen_cells.resize(_mask.size())
				_seen_cells[k] = 1
	if _seen_cells.size() != tt.tc.size():
		_seen_cells.resize(tt.tc.size())
	_layer.queue_redraw()
	var sig := "%d|%s|%d|%d|%s|%d" % [int(tt.step_no) / 3, tt.phase, sel.size(), (tt.duels as Array).size(), str(tt.pending_duel.is_empty()), _units.size()]
	if full or sig != _sig_panel:
		_sig_panel = sig
		_rebuild_strip()
		_rebuild_panel()
		_rebuild_bars()
	if String(tt.phase) == "ended" and not _ended_handled:
		_ended_handled = true
		_fit_view()
		finished.emit(tt.result)
		_rebuild_panel()
		_rebuild_bars()


func _rebuild_strip() -> void:
	Kit.clear(_strip)
	for u: Dictionary in _units:
		if int(u["side"]) != side:
			continue
		var b := StripCard.new()
		b.u = u
		b.on = sel.has(int(u["i"]))
		b.custom_minimum_size = Vector2(STRIP_W - 6.0, 52)
		b.pressed.connect(select_unit.bind(int(u["i"])))
		_strip.add_child(b)


func select_unit(i: int, additive := false) -> void:
	if additive:
		if sel.has(i):
			sel.erase(i)
		else:
			sel.append(i)
	else:
		sel = [i]
	_refresh(true)


func select_all() -> void:
	sel = []
	for u: Dictionary in _units:
		if int(u["side"]) == side and int(u["st"]) < Tac.S_DEAD:
			sel.append(int(u["i"]))
	_refresh(true)


func unit_by_index(i: int) -> Dictionary:
	for u: Dictionary in _units:
		if int(u["i"]) == i:
			return u
	return {}


# -------------------------------------------------------------- geometry --

func _fit_view() -> void:
	if tt == null or _canvas == null:
		return
	var cs := _canvas.size
	var m: float = tt.size_m()
	var avail := Vector2(maxf(cs.x - STRIP_W - 24.0, 100.0), maxf(cs.y - 250.0, 100.0))
	_fit = minf(avail.x, avail.y) / m
	# frame the armies (plus margin) rather than the whole square
	var lo := Vector2(1.0e9, 1.0e9)
	var hi := Vector2(-1.0e9, -1.0e9)
	for i in tt.unit_count():
		if int(tt.u_st[i]) >= Tac.S_DEAD:
			continue
		var mine := int(tt.u_side[i]) == side
		if mine or (not is_deploying() and ((int(tt.u_seen[i]) >> side) & 1) == 1):
			lo = Vector2(minf(lo.x, tt.u_x[i]), minf(lo.y, tt.u_y[i]))
			hi = Vector2(maxf(hi.x, tt.u_x[i]), maxf(hi.y, tt.u_y[i]))
	if is_deploying() and lo.x < hi.x:
		var an := Vector2(float((tt.S[1 - side]["anchor"] as Array)[0]), float((tt.S[1 - side]["anchor"] as Array)[1]))
		lo = Vector2(minf(lo.x, an.x), minf(lo.y, an.y)) if lo.distance_to(an) < 600.0 else lo
		hi = Vector2(maxf(hi.x, an.x), maxf(hi.y, an.y)) if lo.distance_to(an) < 600.0 else hi
	if lo.x > hi.x or String(tt.phase) == "ended":
		lo = Vector2.ZERO
		hi = Vector2(m, m)
	var ext := (hi - lo) + Vector2(260, 260)
	_zoom = clampf(minf(avail.x / ext.x, avail.y / ext.y), _fit, _fit * 4.0)
	var mid := (lo + hi) * 0.5
	_origin = Vector2(STRIP_W + 16.0, 112.0) + avail * 0.5 - mid * _zoom


func to_screen(p: Vector2) -> Vector2:
	return _origin + p * _zoom


func to_world(s: Vector2) -> Vector2:
	return (s - _origin) / _zoom


func _fit_view_and_redraw() -> void:
	_fit_view()
	_layer.queue_redraw()


func zoom_in() -> void:
	_zoom_at(_canvas.size * 0.5, 1.3)


func zoom_out() -> void:
	_zoom_at(_canvas.size * 0.5, 1.0 / 1.3)


func _zoom_at(at: Vector2, f: float) -> void:
	var w := to_world(at)
	_zoom = clampf(_zoom * f, _fit * 0.6, _fit * 6.0)
	_origin = at - w * _zoom
	_layer.queue_redraw()


# ----------------------------------------------------------------- input --

func _canvas_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_at(mb.position, 1.15)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_at(mb.position, 1.0 / 1.15)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_press = mb.position
				_press_unit = unit_at(mb.position, true)
				_drag = {}
				_pan_from = mb.position
			else:
				_release(mb.position)
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if not sel.is_empty():
				_open_menu(to_world(mb.position), unit_at(mb.position, false), mb.position)
	elif e is InputEventMouseMotion:
		var mm := e as InputEventMouseMotion
		if mm.button_mask & MOUSE_BUTTON_MASK_LEFT:
			if _press_unit >= 0:
				_drag = {"unit": _press_unit, "to": mm.position}
				_layer.queue_redraw()
			elif mm.position.distance_to(_press) > 10.0:
				_origin += mm.relative
				_layer.queue_redraw()
		elif mm.button_mask & (MOUSE_BUTTON_MASK_MIDDLE | MOUSE_BUTTON_MASK_RIGHT):
			_origin += mm.relative
			_layer.queue_redraw()


func unit_at(s: Vector2, own_only: bool) -> int:
	var best := -1
	var bd := 1.0e9
	for u: Dictionary in _units:
		if own_only and int(u["side"]) != side:
			continue
		if bool(u.get("ghost", false)):
			continue
		var c := to_screen(Vector2(float(u["x"]), float(u["y"])))
		var r := maxf(float(u["rad"]) * _zoom, 16.0)
		var d := s.distance_to(c)
		if d <= r and d < bd:
			bd = d
			best = int(u["i"])
	return best


func _release(pos: Vector2) -> void:
	var moved := pos.distance_to(_press)
	if moved < 12.0:
		var hit := unit_at(pos, false)
		if hit >= 0:
			var u := unit_by_index(hit)
			if int(u["side"]) == side:
				select_unit(hit)
			elif not sel.is_empty():
				_open_menu(Vector2(float(u["x"]), float(u["y"])), hit, pos)
		elif target_mode and not sel.is_empty():
			target_mode = false
			_open_menu(to_world(pos), -1, pos)
		else:
			if not sel.is_empty():
				sel = []
				_refresh(true)
	elif _press_unit >= 0:
		var uu := unit_by_index(_press_unit)
		if not sel.has(_press_unit):
			sel = [_press_unit]
		var dest := to_world(pos)
		if is_deploying():
			for i: int in sel:
				var off := dest - Vector2(float(uu["x"]), float(uu["y"]))
				var cu := unit_by_index(i)
				tt.deploy_move(i, float(cu["x"]) + off.x, float(cu["y"]) + off.y)
			_refresh(true)
		else:
			_open_menu(dest, unit_at(pos, false), pos)
	_drag = {}
	_layer.queue_redraw()


var _menu_ctx: Dictionary = {}


## The behaviour menu at a point (R§5): same radial as the war map, filtered to what a battle understands.
func _open_menu(dest: Vector2, target_unit: int, screen_pos: Vector2) -> void:
	if sel.is_empty():
		say("Select a formation first.")
		return
	if is_deploying():
		say("Drag formations to place them, then press Start Battle.")
		return
	var first := int(sel[0])
	var info := _order_info(first, dest)
	_menu_ctx = {"dest": dest, "target": target_unit}
	var enabled := func(b: String) -> bool:
		var needs := String((Tac.beh(b) as Dictionary)["needs"])
		return needs != "unit" or (target_unit >= 0 and int(tt.u_side[target_unit]) != side)
	_radial.call("open_at", screen_pos, Rect2(Vector2.ZERO, _canvas.size), "Order", info, "intercept" if target_unit >= 0 and int(tt.u_side[target_unit]) != side else "advance", enabled)


func _order_info(i: int, dest: Vector2) -> String:
	var u := unit_by_index(i)
	if u.is_empty():
		return ""
	var d := Vector2(float(u["x"]), float(u["y"])).distance_to(dest)
	var sig: Dictionary = tt.signal_info(side, i)
	var sp := 1.3 * float(WarUnits.kind(String(u["kind"]))["speed"]) if not bool(u["elite"]) else 1.3
	var mins := d / maxf(sp * 0.9, 0.3) / 60.0
	var msg := "Orders reach them by %s" % String(sig["via"])
	if String(sig["via"]) == "runner":
		msg += " in about %d min" % maxi(1, int(round(float(sig["eta"]) / 60.0)))
	return "Distance %d m, about %d min\nGround: %s\n%s" % [int(d), maxi(1, int(round(mins))), String(tt.terrain_name_at(dest.x, dest.y)), msg]


func _on_behavior_picked(b: String) -> void:
	var dest: Vector2 = _menu_ctx.get("dest", Vector2.ZERO)
	var tg := int(_menu_ctx.get("target", -1))
	issue(b, dest, tg if tg >= 0 and int(tt.u_side[tg]) != side else -1)


## Sends the selection an order through the signal system. Returns the results (eta / via per unit).
func issue(behavior: String, dest: Vector2, target := -1) -> Array:
	var out: Array = []
	var o := {"behavior": behavior, "x": dest.x, "y": dest.y}
	if target >= 0:
		o["target"] = target
	var shown := ""
	for i in sel:
		var r: Dictionary = tt.order(side, int(i), o)
		out.append(r)
		if bool(r.get("ok", false)) and shown == "":
			shown = "%s: %s" % [String(Tac.beh(behavior)["name"]), ("arrives at once (%s)" % String(r["via"])) if float(r["eta"]) <= Tac.STEP + 0.1 else ("a runner carries the order: about %d min" % maxi(1, int(round(float(r["eta"]) / 60.0))))]
	if shown != "":
		say(shown)
	_refresh(true)
	return out


func quick_order(behavior: String) -> Array:
	if sel.is_empty():
		say("Select a formation first.")
		return []
	if behavior == "focus_fire":
		target_mode = false
		var tgt := _nearest_enemy_to(sel)
		if tgt < 0:
			say("No enemy in sight to focus on.")
			return []
		return issue(behavior, Vector2(tt.u_x[tgt], tt.u_y[tgt]), tgt)
	if behavior in ["hold", "form_line", "reserve"]:
		var cu := unit_by_index(int(sel[0]))
		return issue(behavior, Vector2(float(cu["x"]), float(cu["y"])))
	if behavior in ["fallback", "retreat"]:
		var hq := Vector2(float((tt.S[side]["hq"] as Array)[0]), float((tt.S[side]["hq"] as Array)[1]))
		return issue(behavior, hq)
	if behavior == "follow":
		var al := -1
		for u: Dictionary in _units:
			if int(u["side"]) == side and not sel.has(int(u["i"])):
				al = int(u["i"])
				break
		if al < 0:
			say("No one to follow.")
			return []
		return issue(behavior, Vector2(tt.u_x[al], tt.u_y[al]), al)
	target_mode = true
	say("Tap where the selection should go.")
	return []


func _nearest_enemy_to(ids: Array) -> int:
	var c := Vector2.ZERO
	for i: int in ids:
		c += Vector2(tt.u_x[i], tt.u_y[i])
	c /= float(maxi(ids.size(), 1))
	var best := -1
	var bd := 1e18
	for u: Dictionary in _units:
		if int(u["side"]) != side and not bool(u.get("ghost", false)):
			var d := c.distance_squared_to(Vector2(float(u["x"]), float(u["y"])))
			if d < bd:
				bd = d
				best = int(u["i"])
	return best


# ---------------------------------------------------------------- panels --

func _card(border := AF.GOLD_DIM) -> VBoxContainer:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", Kit.box(Color(0.03, 0.028, 0.025, 0.6), border, 3, 8))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	pc.add_child(v)
	_panel.add_child(pc)
	return v


func _btn(text: String, cb: Callable, primary := false, h := 48.0) -> Button:
	var b := Kit.button(text, primary, h, 16)
	b.pressed.connect(cb)
	return b


func _rebuild_panel() -> void:
	if _panel == null:
		return
	Kit.clear(_panel)
	if String(tt.phase) == "ended":
		_panel_result()
		return
	if is_deploying():
		_panel_deploy()
	_panel_forces()
	if not tt.pending_duel.is_empty():
		_panel_duel()
	if not sel.is_empty():
		_panel_selected()
	_panel_terrain()
	_panel_advice()
	_panel_orders()
	_panel_log()


func _panel_forces() -> void:
	var v := _card()
	v.add_child(Kit.lbl("Battle Information", 18, AF.GOLD_BRIGHT, false, "title_bold"))
	var mine: Dictionary = tt.forces(side)
	var row := HBoxContainer.new()
	var ob := Kit.lbl("Our Forces", 16, Color("7fb0ff"))
	row.add_child(ob)
	v.add_child(row)
	v.add_child(Kit.lbl("%s men in %d formations" % [_th(int(mine["men"])), int(mine["units"])], 16, AF.TEXT))
	v.add_child(Kit.lbl("Morale: %s" % Tokens.level_word(float(mine["morale"])), 15, AF.TEXT_DIM))
	v.add_child(Kit.bar(float(mine["morale"]), 9.0, Color("5fae4c") if float(mine["morale"]) > 0.45 else Color("c2412f")))
	var en: Dictionary = tt.enemy_intel(side)
	v.add_child(Kit.lbl("Enemy Forces", 16, Color("ff8a7a")))
	if int(en["seen_units"]) == 0:
		v.add_child(Kit.lbl("Unknown. Send scouts.", 15, AF.TEXT_DIM, true, "italic"))
	else:
		var txt := "%s men" % _th(int(en["est_max"])) if bool(en["exact"]) else "~%s-%s men" % [_th(int(en["est_min"])), _th(int(en["est_max"]))]
		v.add_child(Kit.lbl("%s (%d of %d formations seen)" % [txt, int(en["seen_units"]), int(en["total_units"])], 15, AF.TEXT, true))
		var parts: Array = []
		for k: String in (en["comp"] as Dictionary):
			parts.append("%s ~%d" % [String(WarUnits.kind(k)["name"]) if WarUnits.KINDS.has(k) else String(Tac.ELITE[k]["name"]), int(round(float((en["comp"] as Dictionary)[k]) / 10.0)) * 10])
		v.add_child(Kit.lbl(", ".join(PackedStringArray(parts)), 14, AF.TEXT_DIM, true))
	var arr: Array = tt.arrivals(side)
	if not arr.is_empty():
		v.add_child(Kit.lbl("Reinforcements: %s arrive in %d min" % [String((arr[0] as Dictionary)["name"]), int(ceil(float((arr[0] as Dictionary)["eta"]) / 60.0))], 14, AF.GOLD))
	if eng_id >= 0 and cm != null and not is_deploying():
		var b := _btn("Send Reinforcements", _send_reinforcements, false, 46)
		v.add_child(b)


func _send_reinforcements() -> void:
	if cm == null:
		return
	var r: Dictionary = cm.call("tactical_reinforce", eng_id)
	say("Reinforcements sent: %d formation%s, about %d min." % [int(r["sent"]), "" if int(r["sent"]) == 1 else "s", int(r.get("eta_min", 0))] if bool(r["ok"]) else String(r.get("reason", "No one to send.")))
	_refresh(true)


func _panel_terrain() -> void:
	var v := _card()
	v.add_child(Kit.lbl("Terrain", 16, AF.GOLD))
	var share: Dictionary = tt.terrain_share()
	var keys := share.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return float(share[a]) > float(share[b]))
	var parts: Array = []
	for k: String in keys.slice(0, 3):
		parts.append("%s %d%%" % [k, int(round(float(share[k]) * 100.0))])
	v.add_child(Kit.lbl(", ".join(PackedStringArray(parts)), 15, AF.TEXT, true))
	var wx := String(tt.weather)
	var vis := "Good"
	var wv := float(WarUnits.WEATHER[wx]["vision"]) * (0.45 if tt.night else 1.0)
	vis = "Good" if wv > 0.85 else ("Reduced" if wv > 0.5 else "Poor")
	v.add_child(Kit.lbl("Weather: %s%s" % [wx.capitalize(), " (night)" if tt.night else ""], 15, AF.TEXT))
	v.add_child(Kit.lbl("Visibility: %s" % vis, 15, AF.TEXT_DIM))
	v.add_child(Kit.lbl("Doctrines: you %s, they %s" % [String(Tac.DOCTRINE[tt.S[side]["doctrine"]]["name"]), String(Tac.DOCTRINE[tt.S[1 - side]["doctrine"]]["name"])], 14, AF.TEXT_DIM, true))


func _panel_selected() -> void:
	var v := _card(AF.GOLD)
	var first := unit_by_index(int(sel[0]))
	if first.is_empty():
		return
	var title := String(first["name"]) if sel.size() == 1 else "%d formations" % sel.size()
	v.add_child(Kit.lbl(title, 18, AF.GOLD_BRIGHT, false, "title_bold"))
	if sel.size() == 1:
		v.add_child(Kit.lbl("%s men of %s   Quality: %s" % [_th(int(first["men"])), _th(int(first["men0"])), Tokens.quality_word(float(first["quality"]))], 15, AF.TEXT))
		v.add_child(Kit.lbl("Morale %s   Stamina %d%%" % [Tokens.level_word(float(first["morale"])), int(round((1.0 - float(first["fatigue"])) * 100.0))], 15, AF.TEXT_DIM))
		if float(first["rng"]) > 0.0:
			v.add_child(Kit.lbl("Ammunition %d%%   Range %d m" % [int(float(first["ammo"]) * 100.0), int(first["rng"])], 15, AF.TEXT_DIM))
		v.add_child(Kit.lbl("%s, %s" % [String(first["state"]).capitalize(), String((Tac.beh(String(first["behavior"])) as Dictionary)["name"])], 15, AF.TEXT))
		v.add_child(Kit.lbl("Formation: %s   Layer: %s" % [String((Tac.FORM[Tac.form_key(String(first["formation"]))] as Dictionary)["name"]), String(Tac.LAYER_NAMES.get(String(first["layer"]), ""))], 14, AF.TEXT_DIM, true))
		if bool(first["surrounded"]):
			v.add_child(Kit.lbl("SURROUNDED: cannot retreat, morale falling", 15, Color("ff7a6a"), true))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.add_child(_btn("Formation", open_formation_editor, false, 46))
	if bool(first["elite"]) and sel.size() == 1:
		row.add_child(_btn("Challenge", _challenge, false, 46))
	v.add_child(row)
	if is_deploying():
		var lr := GridContainer.new()
		lr.columns = 3
		for ly: String in Tac.LAYERS:
			var lb := Kit.button(String(Tac.LAYER_NAMES[ly]), String(first["layer"]) == ly, 42.0, 13)
			lb.pressed.connect(_set_layer.bind(ly))
			lr.add_child(lb)
		v.add_child(lr)


func _challenge() -> void:
	if sel.size() != 1:
		return
	var r: Dictionary = tt.challenge(side, int(sel[0]))
	say("Your champion rides to meet theirs." if bool(r.get("ok", false)) else String(r.get("reason", "")))
	_refresh(true)


func _set_layer(ly: String) -> void:
	for i in sel:
		tt.set_layer(int(i), ly)
	_refresh(true)


func _panel_deploy() -> void:
	var v := _card(AF.GOLD)
	v.add_child(Kit.lbl("Battle Deployment", 18, AF.GOLD_BRIGHT, false, "title_bold"))
	v.add_child(Kit.lbl("Drag formations into place. Shields in front, spears behind, archers third, mages at the rear, cavalry on the flanks, veterans in reserve.", 14, AF.TEXT_DIM, true))
	v.add_child(_btn("Auto Arrange", func() -> void: tt.auto_arrange(side); _refresh(true), false, 46))
	v.add_child(_btn("Start Battle", start_battle, true, 56))


func _panel_duel() -> void:
	var v := _card(Color("ff7a4a"))
	var pd: Dictionary = tt.pending_duel
	v.add_child(Kit.lbl("A champion challenges yours!", 18, Color("ffb080"), false, "title_bold"))
	v.add_child(Kit.lbl("%s faces %s. Fight personally, send the champion, or avoid the duel (R§40)." % [String(tt.u_meta[int(pd["theirs"])]["name"]), String(tt.u_meta[int(pd["mine"])]["name"])], 14, AF.TEXT, true))
	v.add_child(_btn("Send champion", func() -> void: tt.duel_respond(int(pd["mine"]), true); _refresh(true), true, 48))
	v.add_child(_btn("Fight personally", func() -> void: tt.duel_respond(int(pd["mine"]), true); say("You take up your sword."); _refresh(true), false, 46))
	v.add_child(_btn("Avoid", func() -> void: tt.duel_respond(int(pd["mine"]), false); _refresh(true), false, 46))


func _panel_advice() -> void:
	var tick := int(float(tt.t) / 600.0)
	if tick != _advice_tick:
		_advice_tick = tick
		if cm != null and eng_id >= 0:
			_advice = cm.call("battle_advice", eng_id)
		else:
			_advice = WarAdvisors.battle_advice(tt, side, WarAdvisors.roster(int(tt.seed)), tick)
	if _advice.is_empty():
		return
	var v := _card()
	v.add_child(Kit.lbl("Advisors", 16, AF.GOLD))
	for l: Dictionary in _advice:
		v.add_child(Kit.lbl("%s (%s): %s" % [String(l["title"]), String(l["confidence"]), String(l["text"])], 14, AF.TEXT, true, "italic"))


func _panel_orders() -> void:
	var list: Array = tt.orders_view(side)
	if list.is_empty():
		return
	var v := _card()
	v.add_child(Kit.lbl("Messengers and orders", 16, AF.GOLD))
	for l: Dictionary in list.slice(maxi(0, list.size() - 6)):
		var st := String(l["status"])
		var txt := String(l["label"])
		var tail := ""
		var col := AF.TEXT_DIM
		match st:
			"travelling":
				tail = "Arrive in %d min" % maxi(1, int(ceil(float(l["eta"]) / 60.0))) if String(l["via"]) == "runner" else "Signalled"
				col = Color("9fb4d0")
			"delivered":
				tail = "Delivered"
				col = Color("7fd18b")
			"lost", "no word":
				tail = "No word yet" if st == "no word" else "Lost on the road"
				col = Color("e0685a")
			"failed", "superseded":
				tail = "Could not be carried out"
		v.add_child(Kit.lbl("%s  -  %s" % [txt, tail], 14, col, true))


func _panel_log() -> void:
	var v := _card()
	v.add_child(Kit.lbl("Reports", 16, AF.GOLD))
	var evs: Array = tt.events
	for ev: Dictionary in evs.slice(maxi(0, evs.size() - 6)):
		v.add_child(Kit.lbl("%s  %s" % [_hms(float(ev["t"])), String(ev["text"])], 13, AF.TEXT_DIM, true))


func _panel_result() -> void:
	var res: Dictionary = tt.result
	Extras.build_aftermath(_panel, res, side, Callable(self, "_pursue"), Callable(self, "close"))


func _pursue() -> void:
	if cm != null and eng_id >= 0:
		cm.call("tactical_apply", eng_id)
		say("The cavalry ride after the broken enemy.")
	close()


func _rebuild_bars() -> void:
	if _cmd_bar == null:
		return
	Kit.clear(_cmd_bar)
	Kit.clear(_deploy_bar)
	var ended := String(tt.phase) == "ended"
	_cmd_bar.visible = not ended and not is_deploying()
	_deploy_bar.visible = is_deploying()
	if is_deploying():
		var sb := Kit.button("Start Battle", true, 54.0, 20)
		sb.custom_minimum_size.x = 210
		sb.pressed.connect(start_battle)
		_deploy_bar.add_child(sb)
		var aa := Kit.button("Auto Arrange", false, 54.0, 16)
		aa.pressed.connect(func() -> void: tt.auto_arrange(side); _refresh(true))
		_deploy_bar.add_child(aa)
		var all := Kit.button("Select all", false, 54.0, 16)
		all.pressed.connect(select_all)
		_deploy_bar.add_child(all)
	for spec: Array in [["Hold", "hold"], ["Charge", "charge"], ["Fall Back", "fallback"], ["Focus Fire", "focus_fire"], ["Follow", "follow"], ["Screen", "screen"], ["Form Line", "form_line"], ["Target", "advance"]]:
		var b := Kit.button(String(spec[0]), false, 46.0, 14)
		b.custom_minimum_size = Vector2(62, 46)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(quick_order.bind(String(spec[1])))
		_cmd_bar.add_child(b)
	var all2 := Kit.button("All", false, 46.0, 14)
	all2.custom_minimum_size = Vector2(46, 46)
	all2.pressed.connect(select_all)
	_cmd_bar.add_child(all2)
	_restyle_toggles()


# ---------------------------------------------------------- formation editor --

func open_formation_editor() -> void:
	if sel.is_empty():
		say("Select a formation first.")
		return
	if _form_popup != null and is_instance_valid(_form_popup):
		_form_popup.queue_free()
	var u := unit_by_index(int(sel[0]))
	_form_state["name"] = Tac.form_key(String(u["formation"]))
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", Kit.box(Color(0.03, 0.028, 0.025, 0.97), AF.GOLD, 4, 12))
	pc.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	pc.custom_minimum_size = Vector2(min(_canvas.size.x - 20.0, 460.0), 0)
	pc.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pc.grow_vertical = Control.GROW_DIRECTION_BOTH
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, minf(_canvas.size.y - 60.0, 560.0))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pc.add_child(scroll)
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 6)
	scroll.add_child(root)
	_form_popup = pc
	_canvas.add_child(pc)
	_fill_formation_editor(root)


func _fill_formation_editor(root: VBoxContainer) -> void:
	Kit.clear(root)
	var u := unit_by_index(int(sel[0]))
	root.add_child(Kit.lbl("Formation Setup: %s (%s)" % [String(u["name"]), _th(int(u["men"]))], 19, AF.GOLD_BRIGHT, false, "title_bold"))
	var grid := GridContainer.new()
	grid.columns = 4
	for f: String in Tac.FORM_ORDER:
		var b := Kit.button(String((Tac.FORM[f] as Dictionary)["name"]), String(_form_state["name"]) == f, 44.0, 13)
		b.pressed.connect(func() -> void: _form_state["name"] = f; _fill_formation_editor(root))
		grid.add_child(b)
	root.add_child(grid)
	var preview := FormPreview.new()
	preview.custom_minimum_size = Vector2(0, 150)
	preview.state = _form_state
	preview.men = int(u["men"])
	root.add_child(preview)
	if String(_form_state["name"]) == "custom":
		for spec: Array in [["Width", "width", 4.0, 40.0, 1.0], ["Depth", "depth", 1.0, 8.0, 1.0], ["Spacing", "spacing", 0.6, 2.5, 0.1]]:
			var h := HBoxContainer.new()
			h.add_child(Kit.lbl(String(spec[0]), 15, AF.TEXT))
			var sl := HSlider.new()
			sl.min_value = float(spec[2])
			sl.max_value = float(spec[3])
			sl.step = float(spec[4])
			sl.value = float(_form_state[spec[1]])
			sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			sl.custom_minimum_size = Vector2(160, 30)
			sl.value_changed.connect(func(v: float) -> void: _form_state[spec[1]] = v; preview.queue_redraw(); _update_bars(root))
			h.add_child(sl)
			root.add_child(h)
	var bars := VBoxContainer.new()
	bars.name = "Bars"
	root.add_child(bars)
	_update_bars(root)
	var toggles := HBoxContainer.new()
	var t1 := CheckButton.new()
	t1.text = "Keep ranged behind"
	t1.button_pressed = bool(_form_state["ranged_behind"])
	t1.toggled.connect(func(on: bool) -> void: _form_state["ranged_behind"] = on)
	toggles.add_child(t1)
	root.add_child(toggles)
	var t2 := CheckButton.new()
	t2.text = "Allow cavalry support"
	t2.button_pressed = bool(_form_state["cav"])
	t2.toggled.connect(func(on: bool) -> void: _form_state["cav"] = on)
	root.add_child(t2)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var ap := Kit.button("Apply", true, 52.0, 18)
	ap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ap.pressed.connect(_apply_formation)
	row.add_child(ap)
	var cn := Kit.button("Cancel", false, 52.0, 16)
	cn.pressed.connect(func() -> void: _form_popup.queue_free())
	row.add_child(cn)
	root.add_child(row)


func _update_bars(root: VBoxContainer) -> void:
	var bars := root.find_child("Bars", true, false) as VBoxContainer
	if bars == null:
		return
	Kit.clear(bars)
	var st: Dictionary = Tac.formation_stats(String(_form_state["name"]), int(_form_state["width"]), int(_form_state["depth"]), float(_form_state["spacing"]))
	bars.add_child(Kit.lbl(String(st["note"]), 14, AF.TEXT_DIM, true, "italic"))
	for spec: Array in [["Attack", "atk"], ["Defense", "def"], ["Mobility", "mob"], ["Vs Cavalry", "vs_cav"], ["Vs Ranged", "vs_rng"]]:
		var r := HBoxContainer.new()
		var l := Kit.lbl(String(spec[0]), 14, AF.TEXT)
		l.custom_minimum_size = Vector2(96, 0)
		r.add_child(l)
		var b := Kit.bar(clampf(float(st[spec[1]]) / 1.8, 0.0, 1.0), 10.0, Color("5a8fd0"), "%.2f" % float(st[spec[1]]))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(b)
		bars.add_child(r)


func _apply_formation() -> void:
	for i in sel:
		tt.set_formation(int(i), String(_form_state["name"]))
		if String(_form_state["name"]) == "custom":
			(tt.u_meta[int(i)] as Dictionary)["custom"] = {"width": int(_form_state["width"]), "depth": int(_form_state["depth"]), "spacing": float(_form_state["spacing"])}
	tt.S[side]["ranged_behind"] = bool(_form_state["ranged_behind"])
	tt.S[side]["cav_support"] = bool(_form_state["cav"])
	if is_deploying():
		tt.layout(side)
	if _form_popup != null and is_instance_valid(_form_popup):
		_form_popup.queue_free()
	say("Formation set: %s." % String((Tac.FORM[String(_form_state["name"])] as Dictionary)["name"]))
	_refresh(true)


# ------------------------------------------------------------------ helpers --

static func _th(n: int) -> String:
	var s := str(n)
	return s if n < 1000 else "%s,%s" % [s.substr(0, s.length() - 3), s.substr(s.length() - 3)]


static func _hms(t: float) -> String:
	var s := int(t)
	return "%02d:%02d" % [(s / 60) % 60 + (s / 3600) * 60, s % 60]


## Pixel terrain texture for the current style, hill-shaded from the real heights.
func terrain_texture() -> ImageTexture:
	var sig := "%d|%s" % [style, tt.name]
	if _tex != null and sig == _tex_sig:
		return _tex
	_tex_sig = sig
	var n: int = tt.n
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var pal := _palette()
	for j in n:
		for i in n:
			var code := int(tt.tc[j * n + i])
			var col: Color = (pal["cells"] as Array)[code]
			var hl: float = tt.hh[j * n + maxi(i - 1, 0)]
			var hr: float = tt.hh[j * n + mini(i + 1, n - 1)]
			var hu: float = tt.hh[maxi(j - 1, 0) * n + i]
			var hd: float = tt.hh[mini(j + 1, n - 1) * n + i]
			var shade := clampf(((hl - hr) + (hu - hd)) * 0.012 * float(pal["relief"]), -0.3, 0.3)
			col = col.lightened(shade) if shade > 0.0 else col.darkened(-shade)
			img.set_pixel(i, j, col)
	_tex = ImageTexture.create_from_image(img)
	_contours = _build_contours()
	return _tex


func _palette() -> Dictionary:
	var cells: Array = []
	match style:
		Tokens.REALISTIC:
			cells = [Color("b3bc86"), Color("6f8a58"), Color("a39a72"), Color("8c8672"), Color("7fa0b0"), Color("9ab3b2"), Color("c8b98c"), Color("b89c70"), Color("b0a08a"), Color("8a9a7a"), Color("5a544a"), Color("6a4a30"), Color("a08c70"), Color("7a6a4a"), Color("4a443a"), Color("8a8a70"), Color("7a6c60"), Color("9a8a60")]
			return {"cells": cells, "relief": 1.0, "bg": Color("d9d2b8"), "line": Color(0.3, 0.25, 0.15, 0.5), "label": Color("2b2115"), "grid": Color(0.3, 0.25, 0.15, 0.12)}
		Tokens.TABLE:
			cells = [Color("d8c890"), Color("7ea060"), Color("c8a868"), Color("a89878"), Color("6f97b8"), Color("8fb0c0"), Color("b0804a"), Color("8a5a30"), Color("b06a4a"), Color("98a878"), Color("5a4630"), Color("4a2e18"), Color("a08a58"), Color("70502a"), Color("3a2c1c"), Color("9a8a60"), Color("8a5c48"), Color("8a6a3a")]
			return {"cells": cells, "relief": 0.6, "bg": Color("3a2a1a"), "line": Color(0.25, 0.15, 0.05, 0.45), "label": Color("fff0d0"), "grid": Color(0.2, 0.12, 0.05, 0.18)}
		_:
			cells = [Color("202624"), Color("12301f"), Color("302f26"), Color("45453f"), Color("123a58"), Color("1a4c68"), Color("c4bca8"), Color("d8d0b8"), Color("4a4640"), Color("1c3a34"), Color("9a9a9a"), Color("c88a30"), Color("6a5a40"), Color("a07a30"), Color("b8b8b8"), Color("4a3a2a"), Color("2a2622"), Color("c8a848")]
			return {"cells": cells, "relief": 0.8, "bg": Color("0a0c0c"), "line": Color(0.9, 0.85, 0.7, 0.28), "label": Color("ffffff"), "grid": Color(1, 1, 1, 0.05)}


## Marching squares on the real heights every 6 m.
func _build_contours() -> Array:
	var out: Array = []
	var n: int = tt.n
	var cell: float = tt.cell
	var lo := 1.0e9
	var hi := -1.0e9
	for k in tt.hh.size():
		lo = minf(lo, tt.hh[k])
		hi = maxf(hi, tt.hh[k])
	var lv: float = ceil(lo / 6.0) * 6.0
	while lv <= hi:
		var segs := PackedVector2Array()
		for j in n - 1:
			for i in n - 1:
				var h00: float = tt.hh[j * n + i]
				var h10: float = tt.hh[j * n + i + 1]
				var h01: float = tt.hh[(j + 1) * n + i]
				var h11: float = tt.hh[(j + 1) * n + i + 1]
				var pts: Array = []
				var x0 := (float(i) + 0.5) * cell
				var y0 := (float(j) + 0.5) * cell
				if (h00 < lv) != (h10 < lv):
					pts.append(Vector2(x0 + cell * (lv - h00) / (h10 - h00), y0))
				if (h10 < lv) != (h11 < lv):
					pts.append(Vector2(x0 + cell, y0 + cell * (lv - h10) / (h11 - h10)))
				if (h01 < lv) != (h11 < lv):
					pts.append(Vector2(x0 + cell * (lv - h01) / (h11 - h01), y0 + cell))
				if (h00 < lv) != (h01 < lv):
					pts.append(Vector2(x0, y0 + cell * (lv - h00) / (h01 - h00)))
				if pts.size() >= 2:
					segs.append(pts[0])
					segs.append(pts[1])
		out.append({"level": lv, "segs": segs})
		lv += 6.0
	return out


func contour_count() -> int:
	terrain_texture()
	return _contours.size()


# ------------------------------------------------------------------ drawing --

class MapLayer extends Control:
	var view: Control

	func _draw() -> void:
		if view != null:
			view.call("_draw_map", self)


class StripCard extends Button:
	var u: Dictionary = {}
	var on := false

	func _ready() -> void:
		flat = true
		focus_mode = Control.FOCUS_NONE

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(1, 0.85, 0.4, 0.22) if on else Color(0.03, 0.028, 0.025, 0.82))
		draw_rect(r, AF.GOLD if on else AF.GOLD_DIM, false, 2.0 if on else 1.0)
		var kind := String(u.get("kind", "infantry"))
		var gk := String({"champion": "infantry", "knight": "heavy_cav", "bender": "mage", "marksman": "archer"}.get(kind, kind))
		Tokens.glyph(self, String(gk), Vector2(18, 18), 9.0, Color("9fc4ff") if int(u.get("st", 0)) < 4 else Color("ff9a8a"), 2.2)
		var f := AF.font(AF.BODY_FONT)
		draw_string(f, Vector2(34, 22), str(int(u.get("men", 0))), HORIZONTAL_ALIGNMENT_LEFT, size.x - 36.0, 17, AF.TEXT)
		var m := clampf(float(u.get("morale", 0.0)), 0.0, 1.0)
		draw_rect(Rect2(6, size.y - 13, size.x - 12, 5), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(6, size.y - 13, (size.x - 12) * m, 5), Color("5fae4c") if m > 0.45 else Color("c2412f"))
		var fat := clampf(1.0 - float(u.get("fatigue", 0.0)), 0.0, 1.0)
		draw_rect(Rect2(6, size.y - 7, (size.x - 12) * fat, 3), Color("d0a040"))
		var st := int(u.get("st", 0))
		if st == Tac.S_ROUT:
			draw_string(f, Vector2(6, size.y - 18), "ROUT", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("ff7a6a"))
		elif st == Tac.S_FIGHT:
			Tokens.glyph(self, "swords", Vector2(size.x - 14, 14), 6.0, Color("ff8a5a"), 1.8)


class FormPreview extends Control:
	var state: Dictionary = {}
	var men := 300

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.028, 0.025, 0.8))
		draw_rect(Rect2(Vector2.ZERO, size), AF.GOLD_DIM, false, 1.0)
		var name_ := String(state.get("name", "line"))
		var pts := Extras.formation_points(name_, clampi(men / 12, 12, 90), int(state.get("width", 12)), int(state.get("depth", 3)), float(state.get("spacing", 1.0)))
		var c := size * 0.5
		for p: Vector2 in pts:
			draw_circle(c + p * 10.0 * minf(size.y / 150.0, 1.3), 3.2, Color("5a9fff"))
		draw_string(AF.font(AF.BODY_FONT), Vector2(8, 18), "Preview", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, AF.TEXT_DIM)
		draw_line(c + Vector2(0, -size.y * 0.42), c + Vector2(0, -size.y * 0.3), Color("ffd070"), 2.0)
		Tokens.arrow_head(self, c + Vector2(0, -size.y * 0.46), Vector2(0, -1), Color("ffd070"), 9.0)


func _draw_map(ci: Control) -> void:
	var pal := _palette()
	ci.draw_rect(Rect2(Vector2.ZERO, ci.size), pal["bg"])
	var m: float = tt.size_m()
	var tl := to_screen(Vector2.ZERO)
	var br := to_screen(Vector2(m, m))
	if style == Tokens.TABLE:
		ci.draw_rect(Rect2(tl - Vector2(14, 14), br - tl + Vector2(28, 28)), Color("6a4a2a"))
		ci.draw_rect(Rect2(tl - Vector2(14, 14), br - tl + Vector2(28, 28)), Color("2e1e0e"), false, 3.0)
	ci.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	ci.draw_texture_rect(terrain_texture(), Rect2(tl, br - tl), false)
	# gentle grid at each 200 m
	var g := 200.0
	var x := g
	while x < m:
		ci.draw_line(to_screen(Vector2(x, 0)), to_screen(Vector2(x, m)), pal["grid"], 1.0)
		ci.draw_line(to_screen(Vector2(0, x)), to_screen(Vector2(m, x)), pal["grid"], 1.0)
		x += g
	if show_contours:
		terrain_texture()
		for c: Dictionary in _contours:
			var segs: PackedVector2Array = c["segs"]
			var major := int(round(float(c["level"]) / 6.0)) % 5 == 0
			var col: Color = pal["line"]
			for k in range(0, segs.size() - 1, 2):
				ci.draw_line(to_screen(segs[k]), to_screen(segs[k + 1]), Color(col, col.a * (1.6 if major else 0.8)), 1.6 if major else 1.0)
	# ring walls, names of real places
	for f: Dictionary in tt.feats:
		var fp := to_screen(Vector2(float(f["x"]), float(f["y"])))
		if Rect2(Vector2.ZERO, ci.size).has_point(fp):
			Tokens.text_centered(ci, _font, String(f["name"]), fp, 14, pal["label"], Color(0, 0, 0, 0.6) if style != Tokens.REALISTIC else Color(1, 1, 1, 0.6), 3)
	_draw_fog(ci)
	if is_deploying():
		_draw_zone(ci)
	# hq banners
	for k in 2:
		var hq := Vector2(float((tt.S[k]["hq"] as Array)[0]), float((tt.S[k]["hq"] as Array)[1]))
		if k == side or _hq_known(k):
			var hp := to_screen(hq)
			Tokens.glyph(ci, "army", hp, 11.0, Tokens.BLUE.lightened(0.3) if k == side else Tokens.RED.lightened(0.3), 2.4)
			if k == side:
				var near := float(tt.S[k]["near"]) * float(tt._wx["signal"]) * (0.7 if tt.night else 1.0)
				if show_range:
					ci.draw_arc(hp, near * _zoom, 0, TAU, 64, Color("ffd070", 0.35), 1.5, true)
	_draw_orders(ci)
	_draw_units(ci, pal)
	_draw_signals(ci)
	_draw_drag(ci)
	_draw_minimap(ci)


func _hq_known(_k: int) -> bool:
	return false


func _draw_fog(ci: Control) -> void:
	if _mask.size() != tt.tc.size() or String(tt.phase) == "ended":
		return
	if _fog_tex == null or _fog_step != _mask_step:
		var n: int = tt.n
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		for j in n:
			for i in n:
				var k := j * n + i
				var al := 0.0
				if _mask[k] != 2:
					al = 0.5 if (k < _seen_cells.size() and _seen_cells[k] == 1) else 0.74
				img.set_pixel(i, j, Color(0.02, 0.02, 0.03, al))
		_fog_tex = ImageTexture.create_from_image(img)
		_fog_step = _mask_step
	var m: float = tt.size_m()
	var tl := to_screen(Vector2.ZERO)
	ci.draw_texture_rect(_fog_tex, Rect2(tl, to_screen(Vector2(m, m)) - tl), false)


func _draw_zone(ci: Control) -> void:
	var st: Dictionary = tt.S[side]
	var ax := Vector2.from_angle(float(st["axis"]))
	var pv := Vector2(-ax.y, ax.x)
	var anc := Vector2(float((st["anchor"] as Array)[0]), float((st["anchor"] as Array)[1]))
	var zw := float(st["zone_w"]) * 1.6
	var dsc := float(st["dscale"])
	var pts := PackedVector2Array([anc + pv * zw + ax * 20.0 * dsc, anc - pv * zw + ax * 20.0 * dsc, anc - pv * zw - ax * 420.0 * dsc, anc + pv * zw - ax * 420.0 * dsc])
	var sp := PackedVector2Array()
	for p: Vector2 in pts:
		sp.append(to_screen(p))
	ci.draw_colored_polygon(sp, Color(0.35, 0.6, 1.0, 0.1))
	sp.append(sp[0])
	ci.draw_polyline(sp, Color(0.45, 0.7, 1.0, 0.7), 2.0, true)


func _draw_orders(ci: Control) -> void:
	for u: Dictionary in _units:
		if int(u["side"]) != side or bool(u.get("ghost", false)) or int(u["st"]) >= Tac.S_DEAD:
			continue
		var b := String(u["behavior"])
		if b in ["hold", "reserve", "form_line", "ambush", "attack_if_attacked", "focus_fire"] and not sel.has(int(u["i"])):
			continue
		var from := to_screen(Vector2(float(u["x"]), float(u["y"])))
		var col: Color = ORDER_COL.get(b, Color("9fb4d0"))
		var to := to_screen(Vector2(float(u["tx"]), float(u["ty"])))
		if from.distance_to(to) > 16.0 and int(u["st"]) != Tac.S_FIGHT:
			var wp: Array = u["wp"]
			var pprev := from
			for w: Vector2 in wp:
				var ws := to_screen(w)
				Tokens.dashed(ci, pprev, ws, Color(col, 0.75), 2.4, 9.0, 6.0)
				pprev = ws
			Tokens.dashed(ci, pprev, to, Color(col, 0.85), 2.6, 10.0, 6.0)
			Tokens.arrow_head(ci, to, to - pprev, col, 11.0)
		if b in ["focus_fire", "intercept"] and (u["order"] as Dictionary).has("target"):
			var tg := int((u["order"] as Dictionary)["target"])
			if tg >= 0 and tg < tt.unit_count():
				Tokens.dashed(ci, from, to_screen(Vector2(tt.u_x[tg], tt.u_y[tg])), Color("ff5050", 0.85), 2.4, 6.0, 4.0)


func _draw_units(ci: Control, pal: Dictionary) -> void:
	# back to front: ghosts, enemies, own
	for pass_ in 3:
		for u: Dictionary in _units:
			var ghost := bool(u.get("ghost", false))
			var own := int(u["side"]) == side
			if (pass_ == 0 and not ghost) or (pass_ == 1 and (ghost or own)) or (pass_ == 2 and (ghost or not own)):
				continue
			_draw_unit(ci, u, pal, own, ghost)


func _draw_unit(ci: Control, u: Dictionary, pal: Dictionary, own: bool, ghost: bool) -> void:
	var c := to_screen(Vector2(float(u["x"]), float(u["y"])))
	if not Rect2(Vector2.ZERO, ci.size).grow(60).has_point(c):
		return
	var col: Color = Tokens.BLUE if own else Tokens.RED
	var kind := String(u["kind"])
	var gk := String({"champion": "infantry", "knight": "heavy_cav", "bender": "mage", "marksman": "archer"}.get(kind, kind))
	if ghost:
		var a := clampf(1.0 - float(u["age"]) / 2400.0, 0.25, 0.7)
		var rr := maxf(float(u["rad"]) * _zoom, 12.0)
		ci.draw_circle(c, rr * 1.6, Color(col, 0.08))
		ci.draw_arc(c, rr * 1.6, 0, TAU, 28, Color(col, a * 0.6), 1.5, true)
		Tokens.text_centered(ci, _font, "?", c, 20, Color(1, 1, 1, a), Color(0, 0, 0, 0.8), 4)
		Tokens.text_centered(ci, _font, "Last seen %d min ago" % maxi(1, int(float(u["age"]) / 60.0)), c + Vector2(0, rr * 1.6 + 14.0), 12, Color(1, 1, 1, a), Color(0, 0, 0, 0.8), 3)
		return
	var men := int(u["men"])
	var rad := maxf(float(u["rad"]) * _zoom, 10.0)
	var face := float(u["face"])
	var selected := sel.has(int(u["i"])) and own
	var alpha := 0.55 if bool(u["hidden"]) else 1.0
	if int(u["st"]) == Tac.S_ROUT:
		alpha = 0.7
	# range ring and sight cone
	if own and float(u["rng"]) > 0.0 and (show_range or selected):
		ci.draw_arc(c, float(u["rng"]) * _zoom, 0, TAU, 48, Color(1, 0.85, 0.4, 0.5), 1.5, true)
		ci.draw_circle(c, float(u["rng"]) * _zoom, Color(1, 0.85, 0.4, 0.05))
	if selected:
		ci.draw_arc(c, rad * 1.5 + 4.0, 0, TAU, 32, Tokens.GOLD, 3.0, true)
	# the block: dots in the shape of the formation, rotated to the facing
	var fk := Tac.form_key(String(u["formation"]))
	var n_dots := clampi(int(ceil(float(men) / 14.0)), 3, 48) if not bool(u["elite"]) else 1
	var scale := maxf(rad / 7.0, 0.6) * 0.62
	if style == Tokens.TABLE:
		Tokens.shadow(ci, c + Vector2(2, 3), rad * 1.1, rad * 0.7, 0.35)
		var ph := Rect2(c - Vector2(rad * 1.05, rad * 0.75), Vector2(rad * 2.1, rad * 1.5))
		ci.draw_set_transform(c, face + PI * 0.5, Vector2.ONE)
		var r2 := Rect2(-Vector2(rad * 0.95, rad * 0.65), Vector2(rad * 1.9, rad * 1.3))
		ci.draw_rect(r2, Color(Tokens.WOOD_LIGHT, alpha))
		ci.draw_rect(Rect2(r2.position + Vector2(2, 2), r2.size - Vector2(4, 4)), Color(col.darkened(0.15), alpha))
		ci.draw_rect(r2, Color(Tokens.WOOD_DARK, alpha), false, 2.0)
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		ph = ph
	else:
		var pts := Extras.formation_points(fk, n_dots)
		var xf := Transform2D(face + PI * 0.5, c)
		var dcol := Color(col.lightened(0.15), alpha)
		var bw := maxf(rad * 0.22, 1.6)
		for p: Vector2 in pts:
			ci.draw_circle(xf * (p * scale * 1.0), bw, dcol)
		# block outline
		var ext := Vector2(rad * 0.95, rad * 0.7)
		var corners := PackedVector2Array([xf * Vector2(-ext.x, -ext.y), xf * Vector2(ext.x, -ext.y), xf * Vector2(ext.x, ext.y), xf * Vector2(-ext.x, ext.y), xf * Vector2(-ext.x, -ext.y)])
		ci.draw_polyline(corners, Color(col, 0.55 * alpha), 1.5, true)
	# facing marker
	var fdir := Vector2.from_angle(face)
	Tokens.arrow_head(ci, c + fdir * (rad * 1.25 + 4.0), fdir, Color(1, 1, 1, 0.85 * alpha), maxf(rad * 0.4, 6.0))
	Tokens.glyph(ci, gk, c, maxf(rad * 0.42, 6.0), Color(1, 1, 1, 0.92 * alpha), 2.0)
	# depth layer tag in deployment
	if is_deploying() and own and selected:
		Tokens.text_centered(ci, _font, String(Tac.LAYER_NAMES.get(String(u["layer"]), "")), c + Vector2(0, -rad * 1.4 - 8.0), 12, Color("cfe0ff"), Color(0, 0, 0, 0.85), 3)
	# numbers, morale and state
	var lab := str(men) if not bool(u["elite"]) else String(u["name"])
	Tokens.text_centered(ci, _font, lab, c + Vector2(0, rad * 1.25 + 18.0), 14 if _zoom > _fit * 0.8 else 12, Color(1, 1, 1, alpha) if style != Tokens.REALISTIC else Color("2b2115"), Color(0, 0, 0, 0.85) if style != Tokens.REALISTIC else Color(1, 1, 1, 0.7), 4)
	if own:
		var mw := rad * 1.6
		var mp := c + Vector2(-mw * 0.5, rad * 0.95 + 4.0)
		ci.draw_rect(Rect2(mp, Vector2(mw, 3.0)), Color(0, 0, 0, 0.6))
		var mor := float(u["morale"])
		ci.draw_rect(Rect2(mp, Vector2(mw * mor, 3.0)), Color("5fae4c") if mor > 0.45 else Color("c2412f"))
	match int(u["st"]):
		Tac.S_FIGHT:
			Tokens.glyph(ci, "swords", c + Vector2(rad * 1.0, -rad * 1.0), 7.0, Color("ff8a5a"), 2.0)
		Tac.S_ROUT:
			Tokens.text_centered(ci, _font, "ROUT", c + Vector2(0, -rad * 1.4), 13, Color("ff7a6a"), Color(0, 0, 0, 0.9), 4)
		Tac.S_DUEL:
			Tokens.text_centered(ci, _font, "DUEL", c + Vector2(0, -rad * 1.4), 13, Color("ffd070"), Color(0, 0, 0, 0.9), 4)
		Tac.S_RETREAT:
			Tokens.text_centered(ci, _font, "retreating", c + Vector2(0, -rad * 1.4), 12, Color("f0d060"), Color(0, 0, 0, 0.9), 4)
	if bool(u["surrounded"]):
		ci.draw_arc(c, rad * 1.7, 0, TAU, 24, Color("ff5030", 0.8), 2.0, true)
	if bool(u["hidden"]):
		Tokens.dashed(ci, c - Vector2(rad, rad), c + Vector2(rad, -rad), Color(1, 1, 1, 0.5), 1.5, 4.0, 4.0)


func _draw_signals(ci: Control) -> void:
	for s: Dictionary in tt.signals_in_flight(side):
		var p := to_screen(Vector2(float(s["x"]), float(s["y"])))
		if String(s["via"]) == "runner":
			ci.draw_circle(p, 5.0, Color("ffe6a0"))
			ci.draw_arc(p, 8.0, 0, TAU, 14, Color("ffe6a0", 0.7), 1.5, true)
			Tokens.text_centered(ci, _font, "%d min" % maxi(1, int(ceil(float(s["eta"]) / 60.0))), p + Vector2(0, -14), 12, Color("ffe6a0"), Color(0, 0, 0, 0.9), 3)
		else:
			ci.draw_circle(p, 3.0, Color("fff0c0", 0.9))


func _draw_drag(ci: Control) -> void:
	if _drag.is_empty():
		return
	var u := unit_by_index(int(_drag["unit"]))
	if u.is_empty():
		return
	var from := to_screen(Vector2(float(u["x"]), float(u["y"])))
	var to: Vector2 = _drag["to"]
	Tokens.dashed(ci, from, to, Color(1, 1, 1, 0.95), 4.0, 14.0, 8.0)
	Tokens.arrow_head(ci, to, to - from, Color(1, 1, 1, 0.95), 16.0)
	ci.draw_circle(to, 16.0, Color(1, 1, 1, 0.2))


func _draw_minimap(ci: Control) -> void:
	var w := 112.0
	var o := Vector2(ci.size.x - w - 10.0, 10.0)
	ci.draw_rect(Rect2(o - Vector2(3, 3), Vector2(w + 6, w + 6)), Color(0.02, 0.02, 0.02, 0.9))
	ci.draw_texture_rect(terrain_texture(), Rect2(o, Vector2(w, w)), false)
	var k := w / float(tt.size_m())
	for u: Dictionary in _units:
		var p := o + Vector2(float(u["x"]), float(u["y"])) * k
		var own := int(u["side"]) == side
		ci.draw_circle(p, 2.4, (Tokens.BLUE.lightened(0.3) if own else Tokens.RED.lightened(0.2)) if not bool(u.get("ghost", false)) else Color(1, 1, 1, 0.3))
	var a := (Vector2.ZERO - _origin) / _zoom * k + o
	var b := (ci.size - _origin) / _zoom * k + o
	ci.draw_rect(Rect2(a, b - a).intersection(Rect2(o, Vector2(w, w))), Color(1, 1, 1, 0.8), false, 1.0)
