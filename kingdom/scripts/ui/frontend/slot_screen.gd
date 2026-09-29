extends "res://scripts/ui/frontend/screen.gd"
## Save-slot screen for both "load" and "save" (Load Game template / Save Game template).
##   SlotScreen.open(parent, "load", on_load)   on_load(id) -> starts the game from the menus;
##                                              omit it in-game to restore into the running world.
##   SlotScreen.open(parent, "save")
## Reads Life.saves (scripts/sim/save_manager.gd): list_slots / slot_meta / load_thumbnail /
## save_slot / delete_slot / load_slot.

const SaveManager := preload("res://scripts/sim/save_manager.gd")

signal loaded(id: String)

var mode := "load"
var on_load := Callable()
## Test hook: [{id, exists, kind, meta}] instead of Life.saves.list_slots().
var fake_rows: Array = []

var _rows_box: VBoxContainer
var _group := ButtonGroup.new()
var _buttons := {}                # id -> Button
var _rows := {}                   # id -> row dict
var _sel := ""
var _status: Label
var _d_thumb: TextureRect
var _d_title: Label
var _d_lines: VBoxContainer
var _act_primary: Button
var _act_delete: Button
var _act_load: Button
var _detail := true


static func open(parent: Node, m := "load", load_cb := Callable(), over_game := false) -> Control:
	var s: Variant = load("res://scripts/ui/frontend/slot_screen.gd").new()
	s.mode = m
	s.on_load = load_cb
	s.translucent = over_game
	parent.add_child(s)
	return s


func _ready() -> void:
	_detail = mode == "load"
	add_backdrop("main_menu" if _detail else "new_game", 0.7)
	var mc := margin_box(34)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	mc.add_child(col)
	col.add_child(FE.header("Load Game" if _detail else "Save Game", back))
	_status = AF.label("", 16, AF.RED)
	_status.visible = false
	col.add_child(_status)
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 20)
	col.add_child(row)
	if not _detail:
		var sp := Control.new()
		sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sp.size_flags_stretch_ratio = 0.3
		row.add_child(sp)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_stretch_ratio = 1.6 if _detail else 2.4
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	row.add_child(scroll)
	_rows_box = VBoxContainer.new()
	_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows_box.add_theme_constant_override("separation", 8)
	scroll.add_child(_rows_box)
	if _detail:
		row.add_child(_build_detail())
	else:
		var sp2 := Control.new()
		sp2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sp2.size_flags_stretch_ratio = 0.3
		row.add_child(sp2)
		var foot := HBoxContainer.new()
		foot.alignment = BoxContainer.ALIGNMENT_CENTER
		foot.add_theme_constant_override("separation", 14)
		_act_primary = FE.gold_btn("Save", _do_primary, 140)
		_act_load = FE.ghost_button("Load", _do_load, 140)
		_act_delete = FE.ghost_button("Delete", _ask_delete, 140)
		foot.add_child(_act_primary)
		foot.add_child(_act_load)
		foot.add_child(_act_delete)
		foot.add_child(FE.ghost_button("Back", back, 140))
		col.add_child(foot)
	refresh()
	FE.fade_in(self, 0.25)


func _build_detail() -> Control:
	var pc := PanelContainer.new()
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pc.size_flags_stretch_ratio = 1.0
	pc.add_theme_stylebox_override("panel", AF.panel(AF.PANEL, AF.GOLD_DIM, 4, 16))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	pc.add_child(v)
	_d_thumb = TextureRect.new()
	_d_thumb.custom_minimum_size = Vector2(0, 190)
	_d_thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_d_thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_d_thumb.clip_contents = true
	v.add_child(_d_thumb)
	_d_title = Label.new()
	_d_title.add_theme_font_override("font", AF.wfont(600))
	_d_title.add_theme_font_size_override("font_size", 24)
	_d_title.add_theme_color_override("font_color", AF.TEXT)
	_d_title.clip_text = true
	v.add_child(_d_title)
	_d_lines = VBoxContainer.new()
	_d_lines.add_theme_constant_override("separation", 6)
	v.add_child(_d_lines)
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(fill)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	v.add_child(h)
	_act_primary = FE.gold_btn("Load Game", _do_primary, 200)
	_act_primary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(_act_primary)
	_act_delete = FE.ghost_button("", _ask_delete, 52)
	_act_delete.icon = _trash_icon()
	_act_delete.expand_icon = false
	_act_delete.tooltip_text = "Delete save"
	h.add_child(_act_delete)
	return pc


func _trash_icon() -> Texture2D:
	var svg := """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24"><g fill="none" stroke="#d8a84e" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M4 7h16M9 7V4h6v3M6 7l1 13h10l1-13M10 11v6M14 11v6"/></g></svg>"""
	var img := Image.new()
	img.load_svg_from_string(svg, 1.0)
	return ImageTexture.create_from_image(img)


func _list() -> Array:
	var rows: Array = fake_rows if not fake_rows.is_empty() else Life.saves.list_slots()
	var out: Array = []
	if _detail:
		for r: Dictionary in rows:
			if r["exists"]:
				out.append(r)
		out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return float((a["meta"] as Dictionary).get("saved_at", 0.0)) > float((b["meta"] as Dictionary).get("saved_at", 0.0)))
		return out
	for kind: String in ["auto", "manual", "quick"]:
		for r: Dictionary in rows:
			if String(r["kind"]) == kind:
				out.append(r)
	return out


func refresh() -> void:
	for c in _rows_box.get_children():
		_rows_box.remove_child(c)
		c.queue_free()
	_buttons.clear()
	_rows.clear()
	var rows := _list()
	if rows.is_empty():
		_rows_box.add_child(AF.label("No saved games yet.", 20, AF.TEXT_DIM, true))
	var last_kind := ""
	for r: Dictionary in rows:
		if not _detail and String(r["kind"]) != last_kind:
			last_kind = String(r["kind"])
			var hl := Label.new()
			hl.text = {"auto": "AUTO SAVE", "manual": "MANUAL SAVE", "quick": "QUICK SAVE"}.get(last_kind, "")
			hl.add_theme_font_override("font", AF.wfont(600))
			hl.add_theme_font_size_override("font_size", 14)
			hl.add_theme_color_override("font_color", AF.GOLD)
			_rows_box.add_child(hl)
		var b := _row(r)
		_rows_box.add_child(b)
		_buttons[String(r["id"])] = b
		_rows[String(r["id"])] = r
	if not _buttons.has(_sel):
		_sel = String(rows[0]["id"]) if not rows.is_empty() else ""
	if _sel != "":
		_select(_sel, false)
	else:
		_update_detail()
	_show_error(Life.saves.last_error if fake_rows.is_empty() else "")
	if is_inside_tree() and _buttons.has(_sel):
		(_buttons[_sel] as Button).call_deferred("grab_focus")


func _thumb_for(r: Dictionary) -> Texture2D:
	if r["exists"] and fake_rows.is_empty():
		var t: Texture2D = Life.saves.load_thumbnail(String(r["id"]))
		if t:
			return t
	elif r["exists"] and r.has("thumb"):
		return r["thumb"]
	# Placeholder art until a real thumbnail exists.
	for ext: String in [".png", ".jpg"]:
		var p: String = AF.BG_DIR + "main_menu" + ext
		if ResourceLoader.exists(p):
			return load(p)
	return null


func _row(r: Dictionary) -> Button:
	var id := String(r["id"])
	var meta: Dictionary = r["meta"]
	var exists: bool = r["exists"]
	var b := Button.new()
	b.toggle_mode = true
	b.button_group = _group
	b.custom_minimum_size = Vector2(0, 90)
	b.focus_mode = Control.FOCUS_ALL
	var n := AF.panel(Color(0.04, 0.036, 0.03, 0.82), AF.GOLD_DIM, 3, 8)
	n.shadow_size = 0
	var s := AF.panel(Color(0.5, 0.36, 0.13, 0.26), AF.GOLD, 3, 8)
	s.shadow_size = 0
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", s)
	for st: String in ["pressed", "focus", "hover_pressed"]:
		b.add_theme_stylebox_override(st, s)
	var h := HBoxContainer.new()
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 8
	h.offset_right = -12
	h.offset_top = 6
	h.offset_bottom = -6
	h.add_theme_constant_override("separation", 14)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(h)
	var th := TextureRect.new()
	th.custom_minimum_size = Vector2(124, 0)
	th.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	th.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	th.clip_contents = true
	th.texture = _thumb_for(r)
	th.modulate = Color.WHITE if exists else Color(0.3, 0.3, 0.3)
	th.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(th)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 1)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)
	var t := Label.new()
	t.text = SaveManager.slot_label(id)
	if exists and String(meta.get("location", "")) != "":
		t.text += "  -  " + String(meta["location"])
	t.add_theme_font_override("font", AF.wfont(600))
	t.add_theme_font_size_override("font_size", 17)
	t.add_theme_color_override("font_color", AF.GOLD_BRIGHT if exists else AF.TEXT_DIM)
	t.clip_text = true
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(t)
	if exists:
		var l2 := AF.label("Day %d  ·  %s" % [int(meta.get("day", 1)), _who(meta)], 15, AF.TEXT)
		l2.autowrap_mode = TextServer.AUTOWRAP_OFF
		l2.clip_text = true
		l2.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(l2)
		var l3 := AF.label("%s  ·  played %s" % [_clock(float(meta.get("time", 8.0))), _fmt_play(float(meta.get("playtime", 0.0)))], 14, AF.TEXT_DIM)
		l3.autowrap_mode = TextServer.AUTOWRAP_OFF
		l3.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(l3)
		var d := AF.label(_date(meta), 13, AF.TEXT_DIM)
		d.size_flags_vertical = Control.SIZE_SHRINK_END
		d.mouse_filter = Control.MOUSE_FILTER_IGNORE
		d.autowrap_mode = TextServer.AUTOWRAP_OFF
		d.custom_minimum_size = Vector2(112, 0)
		d.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		h.add_child(d)
	else:
		var e := AF.label("Empty slot", 16, AF.TEXT_DIM, true)
		e.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(e)
	b.pressed.connect(_select.bind(id, true))
	b.focus_entered.connect(_select.bind(id, false))
	b.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.double_click and ev.button_index == MOUSE_BUTTON_LEFT and _detail:
			_do_primary())
	return b


func _who(meta: Dictionary) -> String:
	var s := String(meta.get("name", "Wanderer"))
	var age := int(meta.get("age", -1))
	if age >= 0:
		s += ", age %d" % age
	var title := String(meta.get("title", ""))
	if title != "":
		s += "  ·  " + title
	return s


func _clock(t: float) -> String:
	return "%02d:%02d" % [int(t), int(fmod(t, 1.0) * 60.0)]


func _fmt_play(sec: float) -> String:
	var m := int(sec) / 60
	return "%dh %02dm" % [m / 60, m % 60] if m >= 60 else "%d min" % m


func _date(meta: Dictionary) -> String:
	var s := String(meta.get("saved_at_text", "")).replace("T", " ")
	return s.substr(0, 16)


func _select(id: String, _pressed := false) -> void:
	_sel = id
	if _buttons.has(id) and not (_buttons[id] as Button).button_pressed:
		(_buttons[id] as Button).set_pressed_no_signal(true)
	_update_detail()


func _update_detail() -> void:
	var r: Dictionary = _rows.get(_sel, {})
	var exists: bool = not r.is_empty() and r["exists"]
	if _act_primary:
		_act_primary.disabled = not exists if _detail else (r.is_empty() or String(r["kind"]) == "auto")
	if _act_load:
		_act_load.disabled = not exists
	if _act_delete:
		_act_delete.disabled = not exists
	if not _detail:
		return
	for c in _d_lines.get_children():
		c.queue_free()
	if r.is_empty():
		_d_title.text = ""
		_d_thumb.texture = null
		return
	var meta: Dictionary = r["meta"]
	_d_thumb.texture = _thumb_for(r)
	_d_title.text = SaveManager.slot_label(String(r["id"]))
	_d_lines.add_child(AF.label(_who(meta), 18, AF.TEXT))
	_d_lines.add_child(AF.label("Day %d, %s  ·  %s" % [int(meta.get("day", 1)), _clock(float(meta.get("time", 8.0))),
		String(meta.get("location", "-"))], 16, AF.TEXT_DIM))
	_d_lines.add_child(AF.separator())
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 6)
	_d_lines.add_child(grid)
	for p: Array in [["Playtime", _fmt_play(float(meta.get("playtime", 0.0)))], ["Saved", _date(meta)],
			["Version", String(meta.get("game_version", "-"))], ["Platform", String(meta.get("platform", "-"))]]:
		var k := AF.label(String(p[0]), 15, AF.GOLD)
		k.autowrap_mode = TextServer.AUTOWRAP_OFF
		grid.add_child(k)
		var val := AF.label(String(p[1]), 15, AF.TEXT)
		val.autowrap_mode = TextServer.AUTOWRAP_OFF
		grid.add_child(val)


func _show_error(text: String) -> void:
	_status.visible = text != ""
	_status.text = text


# --- actions -------------------------------------------------------------------

func _do_primary() -> void:
	if _sel == "":
		return
	if _detail:
		_do_load()
		return
	var r: Dictionary = _rows.get(_sel, {})
	if r.get("exists", false):
		FE.confirm(self, "Overwrite %s?" % SaveManager.slot_label(_sel), _do_save, "Overwrite")
	else:
		_do_save()


func _do_load() -> void:
	if _sel == "" or not (_rows.get(_sel, {}) as Dictionary).get("exists", false):
		return
	if on_load.is_valid():
		on_load.call(_sel)
		return
	if Life.saves.load_slot(_sel):
		loaded.emit(_sel)
		FE.play("open")
		queue_free()
	else:
		_show_error(Life.saves.last_error)
		refresh()


func _do_save() -> void:
	var id := _sel
	# Hide every UI layer for two frames so the thumbnail shows the world, not the menu.
	var top: Node = self
	while top.get_parent() and not (top.get_parent() is CanvasLayer or top.get_parent() is Window):
		top = top.get_parent()
	var was := (top as CanvasItem).visible if top is CanvasItem else true
	if top is CanvasItem:
		(top as CanvasItem).visible = false
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var ok: bool = Life.saves.save_slot(id)
	if top is CanvasItem:
		(top as CanvasItem).visible = was
	_show_error("" if ok else Life.saves.last_error)
	if ok:
		FE.play("open")
	refresh()


func _ask_delete() -> void:
	if _sel == "":
		return
	var id := _sel
	FE.confirm(self, "Delete %s?\nThis cannot be undone." % SaveManager.slot_label(id), func() -> void:
		if not Life.saves.delete_slot(id):
			_show_error(Life.saves.last_error)
		_sel = ""
		refresh(), "Delete", true)
