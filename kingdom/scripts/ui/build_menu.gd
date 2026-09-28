extends Control
## The homestead build menu: a catalogue of buyable pieces, a placement ghost
## in front of the player snapped to the plot's 2 m grid (green when it can be
## placed, red when it can't), and Rotate / Place / Remove / Done. Opened from
## the Pack menu while standing on an owned plot (VillageServices.pack_menu).
##   BuildMenu.open_for(hud)

signal closed

const SELF_PATH := "res://scripts/ui/build_menu.gd"
const Homestead := preload("res://scripts/sim/homestead.gd")
const REACH := 3.0     # metres in front of the player the ghost sits

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
var _subtitle: Label
var _buttons: Dictionary = {}          # kind -> Button
var _crop_box: VBoxContainer
var _last_crop_cell := Vector2i(999999, 999999)


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
	if plot < 0 or not Life.homestead.is_owned(plot):
		close()
		return
	_kind = ""
	_rot = 0
	visible = true
	Audio.play_ui("open")
	_ensure_ghost()
	_refresh_list()
	_status.text = ""


func close() -> void:
	if not visible and _ghost == null:
		return
	visible = false
	if _ghost:
		_ghost.queue_free()
		_ghost = null
	Audio.play_ui("close")
	closed.emit()


func _unhandled_input(e: InputEvent) -> void:
	if not visible:
		return
	if e.is_action_pressed("ui_cancel") or e.is_action_pressed("journal"):
		close()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if not visible:
		return
	_update_ghost()


func _player() -> Node3D:
	return hud.player if hud else null


# --- build UI ----------------------------------------------------------------------

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(UITheme.BG_SOLID, 0.9)
	bg.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bg.custom_minimum_size = Vector2(0, 260)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	margin.custom_minimum_size = Vector2(0, 260)
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
	head.add_child(_round("↻", 52, _on_rotate))
	head.add_child(_gold("Place", _on_place))
	head.add_child(_round("✕", 52, _on_remove))
	head.add_child(_round("×", 52, close))

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	col.add_child(body)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)

	_crop_box = VBoxContainer.new()
	_crop_box.add_theme_constant_override("separation", 4)
	_crop_box.custom_minimum_size = Vector2(180, 0)
	body.add_child(_crop_box)

	_status = Label.new()
	_status.add_theme_color_override("font_color", UITheme.OK)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_status)


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
	for c in _list.get_children():
		c.queue_free()
	_buttons.clear()
	for kind: String in Homestead.CATALOG:
		var c: Dictionary = Homestead.CATALOG[kind]
		var row := Button.new()
		row.custom_minimum_size = Vector2(0, 46)
		row.focus_mode = Control.FOCUS_NONE
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.text = "%s  —  %dg%s" % [c["name"], int(c["gold"]), _mats_text(c)]
		row.toggle_mode = true
		row.button_pressed = kind == _kind
		row.pressed.connect(_select_kind.bind(kind))
		_list.add_child(row)
		_buttons[kind] = row
	_refresh_crop_box()


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
	_status.text = ""


func _on_rotate() -> void:
	_rot = (_rot + 1) % 4


func _on_place() -> void:
	if _kind == "":
		_status.text = "Pick something to build first."
		return
	var why := Life.homestead.place(plot, _kind, _cell, _rot)
	_status.text = "Placed." if why == "" else why
	if why == "":
		Audio.play_ui("pickup")
	_refresh_crop_box()


func _on_remove() -> void:
	var why := Life.homestead.remove_at(plot, _cell)
	_status.text = "Removed." if why == "" else why
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
				_status.text = Life.homestead.plant(plot, _cell, item)
				_refresh_crop_box())
			_crop_box.add_child(b)
	else:
		var pct := int(round(Life.homestead.growth_stage(cr) * 100.0))
		label.text = "%s growing: %d%%%s" % [Life.item_name(crop), pct, "  (watered)" if bool(cr.get("watered", false)) else ""]
		_crop_box.add_child(label)
		if not bool(cr.get("watered", false)) and pct < 100:
			var wb := Button.new()
			wb.text = "Water"
			wb.focus_mode = Control.FOCUS_NONE
			wb.pressed.connect(func() -> void:
				_status.text = Life.homestead.water(plot, _cell)
				_refresh_crop_box())
			_crop_box.add_child(wb)
		if Life.homestead.is_ready(cr):
			var hb := Button.new()
			hb.text = "Harvest"
			hb.focus_mode = Control.FOCUS_NONE
			_gold_style(hb)
			hb.pressed.connect(func() -> void:
				_status.text = Life.homestead.harvest(plot, _cell)
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
