extends Control
## Full-screen techniques screen: cultivation header (realm, qi, progress,
## breakthrough), a tab per skill tree, the tree itself (nodes by tier, links
## from prerequisites, learned / learnable / locked / hidden states), a detail
## card with costs and requirements plus Learn / Equip buttons, and the loadout
## bar (4 active slots, passive slots). Pauses the game while open, like the
## world map (process_mode ALWAYS). Toggle with the "skills_screen" action (K).
##
## Wiring (HUD): see the hook lines in the skills report.
##   var screen := preload("res://scripts/ui/skills_screen.gd").new()
##   add_child(screen)                      # on the HUD CanvasLayer, above the HUD root
##   screen.open()

signal closed

const Skills := preload("res://scripts/sim/skills.gd")
const CATEGORY_ORDER := ["martial", "elemental", "ninja", "samurai", "military", "life"]
const CATEGORY_NAMES := {"martial": "Martial", "elemental": "Elemental", "ninja": "Ninja", "samurai": "Samurai",
	"military": "Military", "life": "Life"}
const DETAIL_WIDTH := 340

var skills: RefCounted
## Returns the unlock context {level, titles, flags, sects}; defaults to Life.
var ctx_provider: Callable

var _tree_id := ""
var _selected := ""
var _ctx := {}
var _was_paused := false
var _canvas: Control
var _tabs: HBoxContainer
var _realm_label: Label
var _qi_bar: ProgressBar
var _qi_text: Label
var _xp_bar: ProgressBar
var _points: Label
var _break_btn: Button
var _status: Label
var _detail: VBoxContainer
var _slot_buttons: Array[Button] = []
var _passive_row: HBoxContainer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UITheme.theme()
	visible = false
	if not InputMap.has_action("skills_screen"):
		InputMap.add_action("skills_screen")
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_K
		InputMap.action_add_event("skills_screen", ev)
	_build()


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("skills_screen"):
		if visible:
			close()
			get_viewport().set_input_as_handled()
		elif not get_tree().paused:
			open()
			get_viewport().set_input_as_handled()
	elif visible and e.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func open() -> void:
	if visible:
		return
	if skills == null:
		skills = _find_skills()
	_was_paused = get_tree().paused
	get_tree().paused = true
	visible = true
	_ctx = _context()
	for msg: String in skills.sync_progress(_ctx):
		_status.text = msg
	if _tree_id == "" and not skills.tree_order.is_empty():
		_tree_id = skills.tree_order[0]
	_rebuild_tabs()
	refresh()


func close() -> void:
	if not visible:
		return
	visible = false
	get_tree().paused = _was_paused
	closed.emit()


func _find_skills() -> RefCounted:
	var life := get_node_or_null("/root/Life")
	if life and life.get("skills") is RefCounted:
		return life.get("skills")
	for p in get_tree().get_nodes_in_group("player"):
		var c := (p as Node).get_node_or_null("TechniqueCaster")
		if c and c.get("skills") is RefCounted:
			return c.get("skills")
	return Skills.new()


func _context() -> Dictionary:
	if ctx_provider.is_valid():
		return ctx_provider.call()
	return Skills.ctx_from_life(get_node_or_null("/root/Life"))


# --- build ---------------------------------------------------------------------

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(UITheme.BG_SOLID, 0.97)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	margin.add_child(col)

	# Header: title, realm, qi and cultivation bars, points, breakthrough, close.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	col.add_child(head)
	var title := _label(head, 30, UITheme.ACCENT)
	title.text = "Techniques"
	title.add_theme_font_override("font", UITheme.title_font_weight(700))
	var realm_box := VBoxContainer.new()
	realm_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	realm_box.add_theme_constant_override("separation", 3)
	head.add_child(realm_box)
	_realm_label = _label(realm_box, 17, UITheme.TEXT)
	_realm_label.add_theme_font_override("font", UITheme.title_font_weight(600))
	var bars := HBoxContainer.new()
	bars.add_theme_constant_override("separation", 10)
	realm_box.add_child(bars)
	_qi_bar = _bar(bars, UITheme.MAGIC, 180)
	_qi_text = _label(bars, 13, UITheme.TEXT_DIM)
	_xp_bar = _bar(bars, UITheme.ACCENT, 140)
	var xp_cap := _label(bars, 13, UITheme.TEXT_DIM)
	xp_cap.text = "cultivation"
	_points = _label(head, 16, UITheme.TEXT)
	_break_btn = Button.new()
	_break_btn.text = "Breakthrough"
	_break_btn.add_theme_stylebox_override("normal", UITheme.pill(UITheme.ACCENT.darkened(0.5), UITheme.ACCENT))
	_break_btn.pressed.connect(_on_breakthrough)
	head.add_child(_break_btn)
	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.pressed.connect(close)
	head.add_child(close_btn)

	# Tree tabs.
	var tab_scroll := ScrollContainer.new()
	tab_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tab_scroll.custom_minimum_size.y = 50
	col.add_child(tab_scroll)
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 8)
	tab_scroll.add_child(_tabs)

	# Body: canvas + detail card.
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	col.add_child(body)
	var canvas_panel := PanelContainer.new()
	canvas_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cbox := UITheme.panel_box(UITheme.RADIUS, Color(1, 1, 1, 0.025))
	cbox.set_content_margin_all(6)
	canvas_panel.add_theme_stylebox_override("panel", cbox)
	body.add_child(canvas_panel)
	_canvas = TreeCanvas.new()
	_canvas.set("screen", self)
	canvas_panel.add_child(_canvas)
	var detail_panel := PanelContainer.new()
	detail_panel.custom_minimum_size.x = DETAIL_WIDTH
	body.add_child(detail_panel)
	var dscroll := ScrollContainer.new()
	dscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail_panel.add_child(dscroll)
	_detail = VBoxContainer.new()
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.add_theme_constant_override("separation", 8)
	dscroll.add_child(_detail)

	# Loadout bar.
	var bar := PanelContainer.new()
	var bbox := UITheme.panel_box(UITheme.RADIUS)
	bbox.set_content_margin_all(10)
	bar.add_theme_stylebox_override("panel", bbox)
	col.add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	bar.add_child(row)
	var lo := _label(row, 15, UITheme.ACCENT)
	lo.text = "Loadout"
	lo.add_theme_font_override("font", UITheme.title_font_weight(600))
	for i in Skills.ACTIVE_SLOTS:
		var b := Button.new()
		b.custom_minimum_size = Vector2(150, 40)
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.pressed.connect(_on_loadout_slot.bind(i))
		row.add_child(b)
		_slot_buttons.append(b)
	var sep := VSeparator.new()
	row.add_child(sep)
	var pl := _label(row, 15, UITheme.ACCENT_2)
	pl.text = "Passives"
	pl.add_theme_font_override("font", UITheme.title_font_weight(600))
	_passive_row = HBoxContainer.new()
	_passive_row.add_theme_constant_override("separation", 8)
	row.add_child(_passive_row)
	_status = _label(col, 14, UITheme.TEXT_DIM)
	_status.custom_minimum_size.y = 18


func _label(parent: Control, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _bar(parent: Control, color: Color, width: int) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.custom_minimum_size = Vector2(width, 8)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.add_theme_stylebox_override("fill", UITheme.bar_fill(color))
	parent.add_child(b)
	return b


func _rebuild_tabs() -> void:
	for c in _tabs.get_children():
		c.queue_free()
	var group := ButtonGroup.new()
	for cat: String in CATEGORY_ORDER:
		for tid: String in skills.tree_order:
			var t: Dictionary = skills.trees[tid]
			if String(t.get("category", "")) != cat:
				continue
			var b := Button.new()
			b.toggle_mode = true
			b.button_group = group
			b.text = String(t.get("name", tid))
			b.tooltip_text = "%s: %s" % [CATEGORY_NAMES.get(cat, cat), t.get("desc", "")]
			var col := Color.from_string(String(t.get("color", "#f5b841")), UITheme.ACCENT)
			b.add_theme_stylebox_override("pressed", UITheme.pill(col.darkened(0.55), col))
			b.add_theme_stylebox_override("hover_pressed", UITheme.pill(col.darkened(0.45), col))
			b.button_pressed = tid == _tree_id
			b.pressed.connect(func() -> void:
				_tree_id = tid
				_selected = ""
				refresh())
			_tabs.add_child(b)


# --- refresh -------------------------------------------------------------------

func refresh() -> void:
	if skills == null:
		return
	_realm_label.text = skills.realm_label()
	_qi_bar.max_value = skills.qi_max()
	_qi_bar.value = skills.qi
	_qi_text.text = "qi %d / %d" % [int(skills.qi), int(skills.qi_max())]
	_xp_bar.max_value = skills.stage_xp_needed()
	_xp_bar.value = skills.cult_xp
	_points.text = "%d point%s" % [skills.points, "" if skills.points == 1 else "s"]
	_points.add_theme_color_override("font_color", UITheme.ACCENT if skills.points > 0 else UITheme.TEXT_DIM)
	_break_btn.visible = skills.at_bottleneck()
	if _break_btn.visible:
		_break_btn.text = "Breakthrough (%d%%)" % int(round(skills.breakthrough_chance() * 100.0))
	if _selected == "" or not skills.techniques.has(_selected):
		var ids: Array = skills.trees.get(_tree_id, {}).get("techniques", [])
		_selected = String(ids[0]) if not ids.is_empty() else ""
	_refresh_detail()
	_refresh_loadout()
	_canvas.queue_redraw()


## Select a technique (switches to its tree).
func select(id: String) -> void:
	var tid := String(skills.get_def(id).get("tree", _tree_id))
	_selected = id
	if tid != _tree_id:
		_tree_id = tid
		_rebuild_tabs()
	refresh()


func selected() -> String:
	return _selected


func tree_id() -> String:
	return _tree_id


func context() -> Dictionary:
	return _ctx


func _refresh_detail() -> void:
	for c in _detail.get_children():
		c.queue_free()
	if _selected == "":
		return
	var d: Dictionary = skills.get_def(_selected)
	var chk: Dictionary = skills.check(_selected, _ctx)
	var known: bool = skills.is_learned(_selected)
	var col: Color = skills.color_of(_selected)
	if not chk["visible"]:
		var q := _label(_detail, 22, UITheme.TEXT_DIM)
		q.text = "???"
		var h := _label(_detail, 14, UITheme.TEXT_DIM)
		h.text = "A hidden art. Something in the world must awaken it."
		h.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		return
	var name_l := _label(_detail, 22, col.lightened(0.2))
	name_l.text = String(d["name"])
	name_l.add_theme_font_override("font", UITheme.title_font_weight(700))
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var sub := _label(_detail, 13, UITheme.TEXT_DIM)
	var rank_txt := " - rank %d / %d" % [skills.rank_of(_selected), int(d["max_rank"])] if known else ""
	sub.text = "%s %s%s" % [String(skills.tree_of(_selected).get("name", "")), "passive" if d["kind"] == "passive" else "technique", rank_txt]
	var desc := _label(_detail, 15, UITheme.TEXT)
	desc.text = String(d["desc"])
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var stats := PackedStringArray()
	if d["kind"] == "active":
		stats.append("Cost  %d %s" % [int(round(skills.cost_of(_selected))), d["resource"]])
		stats.append("Cooldown  %.1fs" % skills.cooldown_of(_selected))
		var dmg := int(skills.damage_of(_selected)) if known else int(d["damage"])
		if dmg > 0:
			stats.append("Damage  %d%s" % [dmg, " x%d" % int(d["hits"]) if int(d["hits"]) > 1 else ""])
		stats.append("Form  %s" % String(d["shape"]).replace("_", " "))
		var fx: Dictionary = d["effect"]
		if not fx.is_empty():
			stats.append("Effect  %s" % ", ".join(PackedStringArray(fx.keys().map(func(k: Variant) -> String: return String(k).replace("_", " ")))))
		if not (d["seals"] as Array).is_empty():
			stats.append("Seals  %s" % " - ".join(PackedStringArray((d["seals"] as Array).map(func(s: Variant) -> String: return String(s).capitalize()))))
	else:
		var p: Dictionary = d["passive"]
		for k: String in p:
			var v := float(p[k])
			stats.append("%s  %s" % [k.replace("_", " ").capitalize(), ("%+d%%" % int(round(v * 100.0))) if absf(v) < 1.0 else ("%+d" % int(v))])
	var st := _label(_detail, 14, UITheme.TEXT)
	st.text = "\n".join(stats)
	# Requirements.
	for reason: String in chk["reasons"]:
		var r := _label(_detail, 13, UITheme.DANGER.lightened(0.2) if reason != "Mastered." else UITheme.OK)
		r.text = reason
		r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if not chk["maxed"]:
		var learn := Button.new()
		learn.text = ("Rank up" if known else "Learn") + " (%d pt%s)" % [int(chk["cost"]), "" if int(chk["cost"]) == 1 else "s"]
		learn.disabled = not chk["ok"]
		learn.pressed.connect(func() -> void:
			var res: Dictionary = skills.learn(_selected, _ctx)
			_status.text = String(res["text"])
			refresh())
		_detail.add_child(learn)
	if known and d["kind"] == "active":
		var eq := _label(_detail, 13, UITheme.TEXT_DIM)
		eq.text = "Equip to slot"
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		_detail.add_child(row)
		for i in Skills.ACTIVE_SLOTS:
			var b := Button.new()
			b.text = str(i + 1)
			b.toggle_mode = true
			b.button_pressed = skills.slot_of(_selected) == i
			b.custom_minimum_size = Vector2(52, 40)
			b.pressed.connect(func() -> void:
				skills.equip(i, _selected if skills.slot_of(_selected) != i else "")
				refresh())
			row.add_child(b)
	elif known and d["kind"] == "passive":
		var on: bool = skills.passives.has(_selected)
		var pb := Button.new()
		pb.text = "Unequip passive" if on else "Equip passive (%d / %d)" % [skills.passives.size(), skills.passive_slots()]
		pb.disabled = not on and skills.passives.size() >= skills.passive_slots()
		pb.pressed.connect(func() -> void:
			if skills.passives.has(_selected):
				skills.unequip_passive(_selected)
			else:
				skills.equip_passive(_selected)
			refresh())
		_detail.add_child(pb)


func _refresh_loadout() -> void:
	for i in _slot_buttons.size():
		var id := String(skills.loadout[i])
		var b := _slot_buttons[i]
		if id == "":
			b.text = "%d  empty" % (i + 1)
			b.remove_theme_stylebox_override("normal")
		else:
			var col: Color = skills.color_of(id)
			b.text = "%d  %s" % [i + 1, skills.get_def(id).get("name", id)]
			b.add_theme_stylebox_override("normal", UITheme.pill(col.darkened(0.7), col.darkened(0.1)))
	for c in _passive_row.get_children():
		c.queue_free()
	for k in skills.passive_slots():
		var b := Button.new()
		b.custom_minimum_size = Vector2(120, 40)
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		if k < skills.passives.size():
			var id := String(skills.passives[k])
			b.text = String(skills.get_def(id).get("name", id))
			var col: Color = skills.color_of(id)
			b.add_theme_stylebox_override("normal", UITheme.pill(col.darkened(0.7), col.darkened(0.1)))
			b.pressed.connect(select.bind(id))
		else:
			b.text = "empty"
			b.disabled = true
		_passive_row.add_child(b)


func _on_loadout_slot(i: int) -> void:
	var id := String(skills.loadout[i])
	if id == "":
		# Equip the selected active technique here.
		if _selected != "" and skills.is_learned(_selected) and skills.get_def(_selected).get("kind", "") == "active":
			skills.equip(i, _selected)
			refresh()
		return
	select(id)


func _on_breakthrough() -> void:
	var res: Dictionary = skills.attempt_breakthrough(0.0, int(_ctx.get("level", -1)))
	_status.text = String(res["text"])
	_status.add_theme_color_override("font_color", UITheme.OK if res.get("success", false) else UITheme.DANGER)
	refresh()


# --- tree canvas -----------------------------------------------------------------

## Draws one tree: tiers top to bottom, columns -1..1, prerequisite links.
class TreeCanvas extends Control:
	var screen: Control
	var _pos := {}          # id -> Vector2 node centre
	var _radius := 28.0
	var _t := 0.0

	func _ready() -> void:
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		size_flags_vertical = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_STOP
		clip_contents = true

	func _process(delta: float) -> void:
		if is_visible_in_tree():
			_t += delta
			queue_redraw()     # learnable nodes pulse

	func _layout() -> void:
		_pos.clear()
		var sk: RefCounted = screen.get("skills")
		if sk == null:
			return
		var ids: Array = sk.trees.get(screen.call("tree_id"), {}).get("techniques", [])
		var max_tier := 1
		for id: String in ids:
			max_tier = maxi(max_tier, int(sk.get_def(id)["tier"]))
		var w := size.x
		var h := size.y
		var row := clampf((h - 70.0) / maxf(1.0, max_tier - 0.4), 64.0, 130.0)
		_radius = clampf(row * 0.27, 18.0, 30.0)
		var spread := clampf(w / 3.4, 90.0, 220.0)
		for id: String in ids:
			var d: Dictionary = sk.get_def(id)
			_pos[id] = Vector2(w * 0.5 + int(d["col"]) * spread, 26.0 + _radius + (int(d["tier"]) - 1) * row)

	func _draw() -> void:
		var sk: RefCounted = screen.get("skills")
		if sk == null:
			return
		_layout()
		var ctx: Dictionary = screen.call("context")
		var font := ThemeDB.fallback_font
		var tcol := Color.from_string(String(sk.trees.get(screen.call("tree_id"), {}).get("color", "#f5b841")), UITheme.ACCENT)
		var states := {}
		for id: String in _pos:
			states[id] = sk.check(id, ctx)
		# Links first.
		for id: String in _pos:
			if not states[id]["visible"]:
				continue
			for req: String in sk.get_def(id)["requires"]:
				if not _pos.has(req) or not states[req]["visible"]:
					continue
				var a: Vector2 = _pos[req]
				var b: Vector2 = _pos[id]
				var col := UITheme.STROKE
				var width := 2.0
				if sk.is_learned(id) and sk.is_learned(req):
					col = tcol
					width = 4.0
				elif sk.is_learned(req):
					col = Color(UITheme.ACCENT, 0.55)
					width = 3.0
				draw_line(a + (b - a).normalized() * _radius, b - (b - a).normalized() * _radius, col, width, true)
		# Nodes.
		var sel := String(screen.call("selected"))
		for id: String in _pos:
			var st: Dictionary = states[id]
			var d: Dictionary = sk.get_def(id)
			var c: Vector2 = _pos[id]
			var known: bool = sk.is_learned(id)
			if not st["visible"]:
				var prereqs_known := true
				for req: String in d["requires"]:
					prereqs_known = prereqs_known and sk.is_learned(req)
				if not prereqs_known:
					continue
				draw_circle(c, _radius, Color(1, 1, 1, 0.03))
				draw_arc(c, _radius, 0, TAU, 40, Color(1, 1, 1, 0.12), 1.5, true)
				draw_string(font, c + Vector2(-_radius, 7), "?", HORIZONTAL_ALIGNMENT_CENTER, _radius * 2.0, 20, UITheme.TEXT_DIM)
				continue
			var fill := Color(0.08, 0.09, 0.13)
			var ring := Color(1, 1, 1, 0.14)
			if known:
				fill = tcol.darkened(0.35)
				ring = tcol.lightened(0.3)
			elif st["ok"]:
				fill = Color(0.12, 0.12, 0.16)
				ring = UITheme.ACCENT.lerp(Color.WHITE, 0.25 + 0.25 * sin(_t * 4.0))
			if d["kind"] == "passive":
				var pts := PackedVector2Array([c + Vector2(0, -_radius), c + Vector2(_radius, 0), c + Vector2(0, _radius), c + Vector2(-_radius, 0)])
				draw_colored_polygon(pts, fill)
				pts.append(pts[0])
				draw_polyline(pts, ring, 2.5, true)
			else:
				draw_circle(c, _radius, fill)
				draw_arc(c, _radius, 0, TAU, 48, ring, 2.5, true)
			if id == sel:
				draw_arc(c, _radius + 6.0, 0, TAU, 48, Color.WHITE, 2.0, true)
			var glyph := _initials(String(d["name"]))
			draw_string(font, c + Vector2(-_radius, 6), glyph, HORIZONTAL_ALIGNMENT_CENTER, _radius * 2.0, 17,
				UITheme.TEXT if known or st["ok"] else UITheme.TEXT_DIM)
			draw_string(font, c + Vector2(-80, _radius + 16), String(d["name"]), HORIZONTAL_ALIGNMENT_CENTER, 160, 13,
				UITheme.TEXT if known else UITheme.TEXT_DIM)
			# Rank pips.
			var mr := int(d["max_rank"])
			if mr > 1:
				for k in mr:
					var p := c + Vector2((k - (mr - 1) * 0.5) * 9.0, _radius + 24.0)
					draw_circle(p, 3.0, tcol if k < sk.rank_of(id) else Color(1, 1, 1, 0.15))
			# Slot badge.
			var slot: int = sk.slot_of(id)
			if slot >= 0:
				var bp := c + Vector2(_radius * 0.8, -_radius * 0.8)
				draw_circle(bp, 10.0, UITheme.ACCENT)
				draw_string(font, bp + Vector2(-10, 5), str(slot + 1), HORIZONTAL_ALIGNMENT_CENTER, 20, 13, UITheme.BG_SOLID)
			elif sk.passives.has(id):
				draw_circle(c + Vector2(_radius * 0.8, -_radius * 0.8), 6.0, UITheme.ACCENT_2)

	func _gui_input(e: InputEvent) -> void:
		var at := Vector2.INF
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			at = e.position
		elif e is InputEventScreenTouch and e.pressed:
			at = e.position
		if at == Vector2.INF:
			return
		for id: String in _pos:
			if (at - (_pos[id] as Vector2)).length() <= _radius + 10.0:
				screen.call("select", id)
				accept_event()
				return

	static func _initials(n: String) -> String:
		var words := n.replace("-", " ").split(" ", false)
		if words.size() >= 2:
			return (words[0].left(1) + words[1].left(1)).to_upper()
		return n.left(2)
