extends Control
## The homestead build menu: a catalogue of buyable pieces, a placement ghost
## in front of the player snapped to the plot's 2 m grid (green when it can be
## placed, red when it can't), and Rotate / Place / Remove / Done. Opened from
## the Pack menu while standing on an owned plot (VillageServices.pack_menu).
##   BuildMenu.open_for(hud)

signal closed

const SELF_PATH := "res://scripts/ui/build_menu.gd"
const Homestead := preload("res://scripts/sim/homestead.gd")
const FarmLedger := preload("res://scripts/ui/farm_ledger.gd")
const REACH := 3.0     # metres in front of the player the ghost sits
const ConstructionPanel := preload("res://scripts/ui/construction_panel.gd")
const W := preload("res://scripts/ui/build_widgets.gd")
const D := preload("res://scripts/realm/construction_data.gd")
const SHEET_H := 340
const PLACE_H := 214

var hud: HUD
var plot := -1
var _kind := ""
var _rot := 0
var _cell := Vector2i.ZERO
var _ghost: Node3D
var _ghost_box: MeshInstance3D
var _green: StandardMaterial3D
var _red: StandardMaterial3D

var _list: VBoxContainer
var _status: Label
var _status_box: PanelContainer
var _place_row: HBoxContainer
var _place_info: Label
var _big_rotate: Button
var _big_snap: Button
var _big_cancel: Button
var _big_place: Button
var _subtitle: Label
var _buttons: Dictionary = {}          # kind -> Button
var _crop_box: VBoxContainer
var _last_crop_cell := Vector2i(999999, 999999)
var _mode := "home"                    # home (plot pieces) | settle (catalogue) | sites | site (one site)
var _cp: RefCounted                    # ConstructionPanel
var _scroll: ScrollContainer
var _bg: ColorRect
var _tab_buttons: Dictionary = {}
var _btn_rotate: Button
var _btn_place: Button
var _btn_remove: Button
var _btn_ledger: Button
var _btn_snap: Button
var _margin: MarginContainer
var _tabs_row: HBoxContainer


static func open_for(host: HUD) -> Control:
	var s: Control = host.get_node_or_null("BuildMenu")
	if s == null:
		s = (load(SELF_PATH) as GDScript).new()
		s.name = "BuildMenu"
		host.add_child(s)
	if host.has_method("close_menu"):
		host.call("close_menu")
	s.hud = host
	s.call("open")
	return s


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UITheme.theme()
	visible = false
	_build()


func open() -> void:
	var p := _player()
	plot = -1 if p == null else Life.homestead.plot_at(Vector2(p.global_position.x, p.global_position.z))
	_kind = ""
	_rot = 0
	visible = true
	if hud and hud.controls:
		hud.controls.visible = false     # the thumb buttons would sit on top of the sheet
	Audio.play_ui("open")
	if _cp == null:
		_cp = ConstructionPanel.new(self)
	set_status("")
	set_mode("home" if plot >= 0 and Life.homestead.owns_or_leases(plot) else "settle")


func close() -> void:
	if not visible and _ghost == null:
		return
	visible = false
	if hud and hud.controls:
		hud.controls.visible = true
	if _ghost:
		_ghost.queue_free()
		_ghost = null
	if _cp != null and _cp.kind != "":
		_cp.cancel_place()
	Audio.play_ui("close")
	closed.emit()


func _input(e: InputEvent) -> void:
	if visible and _cp != null and _mode == "settle" and _cp.handle_input(e):
		get_viewport().set_input_as_handled()


func _unhandled_input(e: InputEvent) -> void:
	if not visible:
		return
	if e.is_action_pressed("ui_cancel") or e.is_action_pressed("journal"):
		close()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not visible:
		return
	if _mode != "home":
		_cp.tick(delta, _mode)
		return
	if plot < 0 or not Life.homestead.owns_or_leases(plot):
		return
	_update_ghost()


# --- modes -------------------------------------------------------------------------------

func set_mode(m: String) -> void:
	_mode = m
	if m != "home" and _ghost:
		_ghost.queue_free()
		_ghost = null
	if m == "home" and plot >= 0 and Life.homestead.owns_or_leases(plot):
		_ensure_ghost()
	if m != "settle" and _cp != null and _cp.kind != "":
		_cp.cancel_place()
	_refresh_list()


func set_status(t: String, ok := true) -> void:
	_status.text = t
	_status.add_theme_color_override("font_color", W.OK if ok else W.BAD)
	_status_box.add_theme_stylebox_override("panel", W.banner_style(ok))
	_status_box.visible = t != ""


## Place is only pressable while the blueprint is green.
func set_place_ok(ok: bool) -> void:
	if _big_place != null:
		_big_place.disabled = not ok


## One line above the big placement buttons: what is being placed, its rotation, the grid.
func set_place_info(t: String) -> void:
	if _place_info != null:
		_place_info.text = t


## Keeps the big touch buttons' captions in step with the placement state.
func refresh_place_row() -> void:
	if _cp == null or _big_snap == null:
		return
	_big_snap.text = "Grid: %s" % ("on" if _cp.snap_on else "off")
	_big_snap.button_pressed = _cp.snap_on
	_big_rotate.text = "↻ Rotate  %d°" % int(round(rad_to_deg(_cp.rot)))


func sheet_top() -> float:
	return _bg.global_position.y if _bg else 99999.0


## Opens the site panel of construction site `id` (used by the world's site interactables).
func show_site(id: int) -> void:
	if _cp == null:
		_cp = ConstructionPanel.new(self)
	_cp.show_site(id)


func _player() -> Node3D:
	return hud.player if hud else null


# --- build UI ----------------------------------------------------------------------

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(UITheme.BG_SOLID, 0.9)
	bg.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bg.custom_minimum_size = Vector2(0, SHEET_H)
	bg.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_bg = bg
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	margin.custom_minimum_size = Vector2(0, SHEET_H)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_margin = margin
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	margin.add_child(col)

	var head := HBoxContainer.new()
	col.add_child(head)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(titles)
	var title := Label.new()
	title.text = "BUILD"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", UITheme.ACCENT)
	title.add_theme_font_override("font", UITheme.title_font_weight(600))
	titles.add_child(title)
	_subtitle = Label.new()
	_subtitle.add_theme_font_size_override("font_size", 13)
	_subtitle.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	titles.add_child(_subtitle)
	_btn_rotate = _round("↻", 52, _on_rotate)
	head.add_child(_btn_rotate)
	_btn_snap = _round("#", 52, func() -> void: _cp.toggle_snap())
	head.add_child(_btn_snap)
	_btn_place = _gold("Place", _on_place)
	head.add_child(_btn_place)
	_btn_remove = _round("✕", 52, _on_remove)
	head.add_child(_btn_remove)
	_btn_ledger = _round("📒", 52, _on_ledger)
	head.add_child(_btn_ledger)
	head.add_child(_round("×", 52, close))

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	_tabs_row = tabs
	col.add_child(tabs)
	for t: Array in [["home", "Homestead"], ["settle", "Build"], ["sites", "Sites"]]:
		var tb := Button.new()
		tb.text = t[1]
		tb.toggle_mode = true
		tb.focus_mode = Control.FOCUS_NONE
		tb.custom_minimum_size = Vector2(110, 38)
		tb.pressed.connect(func() -> void:
			if t[0] == "home" and not (plot >= 0 and Life.homestead.owns_or_leases(plot)) and plot < 0:
				set_status("Stand on a homestead plot to use this tab.")
				return
			set_mode(String(t[0])))
		tabs.add_child(tb)
		_tab_buttons[t[0]] = tb

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	col.add_child(body)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll = scroll
	body.add_child(scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)

	_crop_box = VBoxContainer.new()
	_crop_box.add_theme_constant_override("separation", 4)
	_crop_box.custom_minimum_size = Vector2(180, 0)
	body.add_child(_crop_box)

	# Placement controls for touch: big Rotate / Grid / Cancel / Place, shown only while a blueprint is being placed.
	_place_row = HBoxContainer.new()
	_place_row.add_theme_constant_override("separation", 8)
	_place_row.visible = false
	col.add_child(_place_row)
	_big_rotate = _big("↻ Rotate", 150, _on_rotate)
	_place_row.add_child(_big_rotate)
	_big_snap = _big("Grid: on", 100, func() -> void: _cp.toggle_snap())
	_big_snap.toggle_mode = true
	_place_row.add_child(_big_snap)
	_place_info = Label.new()
	_place_info.add_theme_font_size_override("font_size", 12)
	_place_info.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	_place_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_place_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_place_info.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_place_row.add_child(_place_info)
	_big_cancel = _big("Cancel", 90, _on_remove)
	_place_row.add_child(_big_cancel)
	_big_place = _big("Place", 110, _on_place)
	_gold_style(_big_place)
	_place_row.add_child(_big_place)
	_status_box = PanelContainer.new()
	_status_box.add_theme_stylebox_override("panel", W.banner_style(true))
	_status_box.visible = false
	col.add_child(_status_box)
	_status = Label.new()
	_status.add_theme_color_override("font_color", UITheme.OK)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_box.add_child(_status)


func _round(text: String, diameter: int, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(diameter, diameter)
	b.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 20)
	var r := diameter / 2
	for pair: Array in [["normal", UITheme.BG, UITheme.STROKE], ["hover", UITheme.BG, UITheme.ACCENT.darkened(0.2)],
			["pressed", UITheme.ACCENT.darkened(0.35), UITheme.ACCENT]]:
		var sb := UITheme.pill(pair[1], pair[2], r)
		sb.set_content_margin_all(0)
		b.add_theme_stylebox_override(pair[0], sb)
	b.pressed.connect(cb)
	return b


## Large touch button (62 px tall) for the placement row.
func _big(text: String, width: int, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(width, 62)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 18)
	b.pressed.connect(cb)
	return b


func _gold(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(90, 52)
	b.focus_mode = Control.FOCUS_NONE
	_gold_style(b)
	b.pressed.connect(cb)
	return b


## The gold call-to-action look (matches InventoryScreen.gold_button).
static func _gold_style(b: Button) -> void:
	b.add_theme_stylebox_override("normal", UITheme.pill(UITheme.ACCENT.darkened(0.25), UITheme.ACCENT, 25))
	b.add_theme_stylebox_override("hover", UITheme.pill(UITheme.ACCENT.darkened(0.1), UITheme.ACCENT, 25))
	b.add_theme_stylebox_override("pressed", UITheme.pill(UITheme.ACCENT, Color.WHITE, 25))
	b.add_theme_stylebox_override("disabled", UITheme.pill(Color(1, 1, 1, 0.04), UITheme.STROKE, 25))
	for c in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(c, Color("1b1407"))


func _refresh_list() -> void:
	var keep_scroll := _scroll.scroll_vertical if _scroll else 0
	for c in _list.get_children():
		c.queue_free()
		_list.remove_child(c)
	_buttons.clear()
	var home := _mode == "home"
	_btn_ledger.visible = home
	_btn_remove.visible = home or (_mode == "settle" and _cp != null and _cp.kind != "")
	_btn_snap.visible = _mode == "settle" and _cp != null and _cp.kind != ""
	_btn_rotate.visible = home or (_mode == "settle" and _cp != null and _cp.kind != "")
	_btn_place.visible = home or (_mode == "settle" and _cp != null and _cp.kind != "")
	_crop_box.visible = home
	var placing: bool = _mode == "settle" and _cp != null and _cp.kind != ""
	_scroll.get_parent().visible = not placing
	_tabs_row.visible = not placing
	_subtitle.visible = true
	_place_row.visible = placing
	# the big touch buttons replace the small header ones while placing
	if placing:
		_btn_rotate.visible = false
		_btn_place.visible = false
		_btn_remove.visible = false
		_btn_snap.visible = false
		_subtitle.text = "Placing %s: drag the blueprint, green means go" % String(D.CATALOG[_cp.kind]["name"]).to_lower() \
			if _cp.upgrade_of == 0 else "Upgrading: choose the new blueprint's spot"
		refresh_place_row()
	var h := PLACE_H if placing else SHEET_H
	_bg.custom_minimum_size.y = h
	_bg.offset_top = -h
	_bg.offset_bottom = 0
	for k: String in _tab_buttons:
		(_tab_buttons[k] as Button).button_pressed = (k == _mode) or (k == "sites" and _mode == "site")
	if not home:
		if not placing:
			_subtitle.text = {"settle": "Build anywhere valid. Builders need a path to walk.", "sites": "Your holdings and building sites", "site": "Building site"}[_mode]
		if _mode == "settle":
			_cp.fill_catalog(_list)
		elif _mode == "sites":
			_cp.fill_sites(_list)
		else:
			_cp.fill_site(_list)
		_restore_scroll.call_deferred(keep_scroll)
		return
	var hs := Life.homestead
	if plot >= 0 and not hs.owns_or_leases(plot):
		_subtitle.text = "%s — unclaimed" % hs.plot_name(plot)
		var plot_info: Dictionary = hs.plots()[plot]
		var buy_row := Button.new()
		buy_row.custom_minimum_size = Vector2(0, 46)
		buy_row.focus_mode = Control.FOCUS_NONE
		buy_row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		buy_row.text = "Buy this plot  —  %dg" % int(plot_info["price"])
		buy_row.pressed.connect(func() -> void:
			set_status(hs.buy(plot))
			_refresh_list())
		_list.add_child(buy_row)
		var lease_row := Button.new()
		lease_row.custom_minimum_size = Vector2(0, 46)
		lease_row.focus_mode = Control.FOCUS_NONE
		lease_row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		lease_row.text = "Lease from the Lord  —  %dg / season, %d%% of the harvest" % [Homestead.LEASE_RENT, int(Homestead.LEASE_SHARE * 100.0)]
		lease_row.pressed.connect(func() -> void:
			set_status(hs.lease(plot))
			_refresh_list())
		_list.add_child(lease_row)
		_refresh_crop_box()
		return
	_subtitle.text = "%s%s" % [hs.plot_name(plot), "  (leased)" if hs.is_leased(plot) else ""]
	for kind: String in Homestead.CATALOG:
		var row := _home_row(kind, Homestead.CATALOG[kind])
		row.toggle_mode = true
		row.button_pressed = kind == _kind
		row.pressed.connect(_select_kind.bind(kind))
		_list.add_child(row)
		_buttons[kind] = row
	var hire_row := Button.new()
	hire_row.custom_minimum_size = Vector2(0, 46)
	hire_row.focus_mode = Control.FOCUS_NONE
	hire_row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var names := ["Osric", "Mabel", "Tomas", "Wren", "Hodge", "Ada"]
	hire_row.text = "Hire a farm hand  (%d / %d)" % [hs.workers_on(plot).size(), hs.max_workers()]
	hire_row.pressed.connect(func() -> void:
		set_status(hs.hire(plot, names[randi() % names.size()]))
		_refresh_list())
	_list.add_child(hire_row)
	_refresh_crop_box()


## A catalogue row for a homestead piece: icon, name, and cost chips coloured by what you hold.
func _home_row(kind: String, c: Dictionary) -> Button:
	var row := Button.new()
	row.custom_minimum_size = Vector2(0, 58)
	row.focus_mode = Control.FOCUS_NONE
	var inner := HBoxContainer.new()
	inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inner.offset_left = 8
	inner.offset_right = -8
	inner.add_theme_constant_override("separation", 8)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(inner)
	inner.add_child(W.icon(kind, "", 40))
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name_l := Label.new()
	name_l.text = String(c["name"])
	name_l.add_theme_font_size_override("font_size", 15)
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(name_l)
	var parts: Array = [["%dg" % int(c["gold"]), "ok" if Game.gold >= int(c["gold"]) else "short"]]
	var mats: Dictionary = c.get("mats", {})
	for item: String in mats:
		var have: int = Life.count(item)
		var need := int(mats[item])
		parts.append(["%d/%d %s" % [have, need, Life.item_name(item).to_lower()], "ok" if have >= need else "short"])
	col.add_child(W.chips(parts))
	inner.add_child(col)
	return row


func _restore_scroll(v: int) -> void:
	if _scroll:
		_scroll.scroll_vertical = v


func _on_ledger() -> void:
	if hud:
		FarmLedger.open_for(hud)


func _mats_text(c: Dictionary) -> String:
	var mats: Dictionary = c.get("mats", {})
	if mats.is_empty():
		return ""
	var parts := PackedStringArray()
	for item: String in mats:
		parts.append("%d %s" % [int(mats[item]), Life.item_name(item)])
	return "  ·  " + ", ".join(parts)


func _select_kind(kind: String) -> void:
	_kind = "" if _kind == kind else kind
	for k: String in _buttons:
		(_buttons[k] as Button).button_pressed = k == _kind
	set_status("")


func _on_rotate() -> void:
	if _mode == "settle":
		_cp.rotate_ghost()
		return
	_rot = (_rot + 1) % 4


func _on_place() -> void:
	if _mode == "settle":
		_cp.confirm_place()
		return
	if _kind == "":
		set_status("Pick something to build first.")
		return
	var why := Life.homestead.place(plot, _kind, _cell, _rot)
	set_status("Placed." if why == "" else why)
	if why == "":
		Audio.play_ui("pickup")
	_refresh_crop_box()


func _on_remove() -> void:
	if _mode == "settle":
		_cp.cancel_place()
		return
	var why := Life.homestead.remove_at(plot, _cell)
	set_status("Removed." if why == "" else why)
	_refresh_crop_box()


## The crop actions (plant / water / harvest) for whatever tilled plot the ghost
## is currently over, shown beside the catalogue so they're always in reach.
func _refresh_crop_box() -> void:
	for c in _crop_box.get_children():
		c.queue_free()
	var cr := Life.homestead.crop_at(plot, _cell)
	if cr.is_empty():
		return
	var label := Label.new()
	label.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var crop := String(cr.get("crop", ""))
	if crop == "":
		label.text = "Tilled plot: empty."
		_crop_box.add_child(label)
		for item: String in Homestead.CROPS:
			var b := Button.new()
			b.text = "Plant %s" % Life.item_name(item)
			b.focus_mode = Control.FOCUS_NONE
			b.pressed.connect(func() -> void:
				set_status(Life.homestead.plant(plot, _cell, item))
				_refresh_crop_box())
			_crop_box.add_child(b)
	else:
		var pct := int(round(Life.homestead.growth_stage(cr) * 100.0))
		var tags := PackedStringArray()
		if bool(cr.get("watered", false)):
			tags.append("watered")
		if bool(cr.get("weeded", false)):
			tags.append("weeded")
		label.text = "%s growing: %d%%%s" % [Life.item_name(crop), pct, "  (%s)" % ", ".join(tags) if not tags.is_empty() else ""]
		_crop_box.add_child(label)
		if not bool(cr.get("watered", false)) and pct < 100:
			var wb := Button.new()
			wb.text = "Water"
			wb.focus_mode = Control.FOCUS_NONE
			wb.pressed.connect(func() -> void:
				set_status(Life.homestead.water(plot, _cell))
				_refresh_crop_box())
			_crop_box.add_child(wb)
		if not bool(cr.get("weeded", false)) and pct < 100:
			var wdb := Button.new()
			wdb.text = "Weed"
			wdb.focus_mode = Control.FOCUS_NONE
			wdb.pressed.connect(func() -> void:
				set_status(Life.homestead.weed(plot, _cell))
				_refresh_crop_box())
			_crop_box.add_child(wdb)
		if Life.homestead.is_ready(cr):
			var hb := Button.new()
			hb.text = "Harvest"
			hb.focus_mode = Control.FOCUS_NONE
			_gold_style(hb)
			hb.pressed.connect(func() -> void:
				set_status(Life.homestead.harvest(plot, _cell))
				_refresh_crop_box())
			_crop_box.add_child(hb)


# --- the ghost ------------------------------------------------------------------

func _ensure_ghost() -> void:
	if _ghost:
		return
	var p := _player()
	if p == null:
		return
	_ghost = Node3D.new()
	p.get_parent().add_child(_ghost)
	_green = StandardMaterial3D.new()
	_green.albedo_color = Color(0.35, 0.95, 0.5, 0.55)
	_green.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_green.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_red = StandardMaterial3D.new()
	_red.albedo_color = Color(0.95, 0.3, 0.3, 0.55)
	_red.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_red.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_box = MeshInstance3D.new()
	_ghost_box.mesh = BoxMesh.new()
	_ghost_box.material_override = _green
	_ghost.add_child(_ghost_box)


func _update_ghost() -> void:
	var p := _player()
	if p == null or _ghost == null:
		return
	var hs := Life.homestead
	var fwd: Vector3 = p.forward() if p.has_method("forward") else -p.global_transform.basis.z
	var ahead := Vector2(p.global_position.x, p.global_position.z) + Vector2(fwd.x, fwd.z).normalized() * REACH
	_cell = hs.world_to_cell(plot, ahead)
	var world := hs.cell_world(plot, _cell)
	var plot_yaw: float = float(hs.plots()[plot]["yaw"])
	_ghost.global_position = Vector3(world.x, WorldGen.height(world.x, world.y) + 0.05, world.y)
	var kind := _kind if _kind != "" else "fence"
	var fp: Vector2i = Homestead.CATALOG.get(kind, {}).get("footprint", Vector2i.ONE)
	if _rot % 2 == 1:
		fp = Vector2i(fp.y, fp.x)
	(_ghost_box.mesh as BoxMesh).size = Vector3(float(fp.x) * Homestead.GRID * 0.92, 0.2, float(fp.y) * Homestead.GRID * 0.92)
	_ghost.rotation.y = plot_yaw + float(_rot) * PI * 0.5
	var ok := _kind != "" and Life.homestead.can_place(plot, _kind, _cell, _rot) == ""
	_ghost_box.material_override = _green if (ok or _kind == "") else _red
	if _cell != _last_crop_cell:
		_last_crop_cell = _cell
		_refresh_crop_box()
