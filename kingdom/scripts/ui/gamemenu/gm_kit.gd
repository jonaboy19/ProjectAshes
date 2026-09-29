extends RefCounted
## Small widget kit for the in-game tabbed menu, built on ashes_frame.gd (the shared
## dark-gold look). Everything is drawn in code or from the white game-icons SVGs
## in assets/ui/icons/gm/ (UI) and assets/ui/icons/items/ (item ids).

const AF := preload("res://scripts/ui/ashes_frame.gd")
const ICON_DIR := "res://assets/ui/icons/"
const KIT_PATH := "res://scripts/ui/gamemenu/gm_kit.gd"
const GREEN := Color("7fd18b")
const BAD := Color("e0685a")
## Item icon tint by pack category (the SVGs are white).
const CATEGORY_TINT := {"weapons": Color("cfd8ea"), "armor": Color("c9bfae"), "consumables": Color("ee9c7c"),
	"materials": Color("dcc08f"), "quest": Color("f5c46a"), "misc": Color("b9c2d6")}

static var _icon_cache: Dictionary = {}


# ------------------------------------------------------------------- textures ----

static func icon(icon_name: String) -> Texture2D:
	if _icon_cache.has(icon_name):
		return _icon_cache[icon_name]
	var p := ICON_DIR + ("items/" + icon_name.trim_prefix("items/") if icon_name.begins_with("items/") else "gm/" + icon_name) + ".svg"
	var t: Texture2D = load(p) if ResourceLoader.exists(p) else null
	_icon_cache[icon_name] = t
	return t


static func item_icon(id: String) -> Texture2D:
	return icon("items/" + id)


static func tex_rect(t: Texture2D, side: float, tint := AF.TEXT) -> TextureRect:
	var r := TextureRect.new()
	r.texture = t
	r.custom_minimum_size = Vector2(side, side)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	r.modulate = tint
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


# --------------------------------------------------------------------- labels ----

static func lbl(text: String, size := 16, color := AF.TEXT, wrap := false, style := "body") -> Label:
	var l := Label.new()
	l.text = text
	var f: Font
	match style:
		"title":
			f = AF.title_font(600)
		"title_bold":
			f = AF.title_font(700)
		"italic":
			f = AF.font(AF.ITALIC_FONT)
		_:
			f = AF.font(AF.BODY_FONT)
	l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wrap else TextServer.AUTOWRAP_OFF
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if wrap:
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


## Gold section title with a thin line under it ("Objectives", "Rewards", "Skills").
static func section(text: String, size := 18) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	v.add_child(lbl(text, size, AF.GOLD, false, "title"))
	v.add_child(AF.separator())
	return v


static func spacer(h := 8.0) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func hspacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


# ---------------------------------------------------------------- panel boxes ----

static func box(bg: Color, border: Color, radius := 3, margin := 8) -> StyleBoxFlat:
	var s := AF.panel(bg, border, radius, margin)
	s.shadow_size = 0
	return s


static func framed(child: Control, bg := Color(0.03, 0.028, 0.025, 0.7), border := AF.GOLD_DIM, margin := 10) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(bg, border, 3, margin))
	p.add_child(child)
	return p


static func framed_icon(icon_name: String, side := 44.0, tint := AF.GOLD_BRIGHT, border := AF.GOLD_DIM) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(Color(0.05, 0.045, 0.04, 0.9), border, 3, 4))
	p.custom_minimum_size = Vector2(side, side)
	var t := icon(icon_name)
	if t != null:
		p.add_child(tex_rect(t, side - 10.0, tint))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


# ----------------------------------------------------------------------- Bar ----

class Bar extends Control:
	var ratio := 0.0
	var fill := AF.GOLD
	var text := ""

	func _init(h := 10.0, c := AF.GOLD) -> void:
		custom_minimum_size = Vector2(40, h)
		fill = c
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_horizontal = Control.SIZE_EXPAND_FILL

	func set_ratio(r: float) -> void:
		ratio = clampf(r, 0.0, 1.0)
		queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(0, 0, 0, 0.6))
		var w := (size.x - 2.0) * ratio
		if w > 0.5:
			draw_rect(Rect2(1, 1, w, size.y - 2.0), fill.darkened(0.25))
			draw_rect(Rect2(1, 1, w, maxf(1.0, (size.y - 2.0) * 0.45)), fill)
		draw_rect(r, AF.GOLD_DIM, false, 1.0)
		if text != "":
			var f := AF.font(AF.BODY_FONT)
			var fs := int(clampf(size.y - 2.0, 11.0, 16.0))
			var tw := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var bp := Vector2((size.x - tw) * 0.5, size.y * 0.5 + fs * 0.34)
			draw_string_outline(f, bp, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.85))
			draw_string(f, bp, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, AF.TEXT)


static func bar(ratio: float, h := 10.0, color := AF.GOLD, text := "") -> Bar:
	var b := Bar.new(h, color)
	b.text = text
	b.ratio = clampf(ratio, 0.0, 1.0)
	return b


# ------------------------------------------------------------ Diamond / Check ----

class Diamond extends Control:
	var color := AF.GOLD
	var filled := true

	func _init(side := 12.0, c := AF.GOLD, is_filled := true) -> void:
		custom_minimum_size = Vector2(side, side)
		color = c
		filled = is_filled
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _draw() -> void:
		var c := size * 0.5
		var h := minf(size.x, size.y) * 0.5
		var pts := PackedVector2Array([c + Vector2(0, -h), c + Vector2(h, 0), c + Vector2(0, h), c + Vector2(-h, 0)])
		if filled:
			draw_colored_polygon(pts, color)
		pts.append(pts[0])
		draw_polyline(pts, color.lightened(0.25) if filled else color, 1.2, true)


class Check extends Control:
	var done := false

	func _init(d := false, side := 18.0) -> void:
		done = d
		custom_minimum_size = Vector2(side, side)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 1.5
		draw_arc(c, r, 0, TAU, 24, AF.GOLD if done else AF.GOLD_DIM, 1.5, true)
		if done:
			draw_circle(c, r - 3.0, Color(AF.GOLD, 0.35))
			draw_polyline(PackedVector2Array([c + Vector2(-r * 0.45, 0), c + Vector2(-r * 0.1, r * 0.4), c + Vector2(r * 0.55, -r * 0.4)]),
				AF.GOLD_BRIGHT, 2.0, true)


static func diamond(side := 12.0, color := AF.GOLD, filled := true) -> Diamond:
	return Diamond.new(side, color, filled)


# ------------------------------------------------------------------------ Row ----

## A list row: [marker/icon] name ......... right text. Gold frame when selected.
class Row extends Button:
	var key := ""
	var _selected := false
	var _name: Label
	var _right: Label

	func _init(text: String, icon_name := "", right := "", marker := "", height := 48.0, framed := false) -> void:
		custom_minimum_size = Vector2(0, height)
		focus_mode = Control.FOCUS_NONE
		alignment = HORIZONTAL_ALIGNMENT_LEFT
		toggle_mode = false
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 10)
		h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		h.offset_left = 12
		h.offset_right = -12
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(h)
		if marker == "diamond":
			h.add_child(Diamond.new(11.0))
		elif icon_name != "":
			var t: Texture2D = load(KIT_PATH).icon(icon_name)
			if t != null:
				var tr := TextureRect.new()
				tr.texture = t
				tr.custom_minimum_size = Vector2(24, 24)
				tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				tr.modulate = AF.TEXT
				tr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
				tr.name = "Icon"
				if framed:
					tr.custom_minimum_size = Vector2(26, 26)
					var fp := PanelContainer.new()
					fp.add_theme_stylebox_override("panel", load(KIT_PATH).box(Color(0.05, 0.045, 0.04, 0.9), AF.GOLD_DIM, 3, 5))
					fp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
					fp.mouse_filter = Control.MOUSE_FILTER_IGNORE
					fp.add_child(tr)
					tr.modulate = AF.GOLD_BRIGHT
					h.add_child(fp)
				else:
					h.add_child(tr)
		_name = Label.new()
		_name.text = text
		_name.add_theme_font_override("font", AF.font(AF.BODY_FONT))
		_name.add_theme_font_size_override("font_size", 18)
		_name.add_theme_color_override("font_color", AF.TEXT)
		_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_name.clip_text = true
		_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(_name)
		_right = Label.new()
		_right.text = right
		_right.add_theme_font_override("font", AF.title_font(600))
		_right.add_theme_font_size_override("font_size", 16)
		_right.add_theme_color_override("font_color", AF.GOLD_BRIGHT)
		_right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(_right)
		set_selected(false)

	func set_selected(on: bool) -> void:
		_selected = on
		add_theme_stylebox_override("normal", AF.row(on, false))
		add_theme_stylebox_override("hover", AF.row(on, true))
		add_theme_stylebox_override("pressed", AF.row(true, false))
		add_theme_stylebox_override("focus", AF.row(on, true))
		if _name:
			_name.add_theme_color_override("font_color", AF.GOLD_BRIGHT if on else AF.TEXT)

	func set_right(t: String) -> void:
		_right.text = t

	func set_name_color(c: Color) -> void:
		_name.add_theme_color_override("font_color", c)


static func row(text: String, icon_name := "", right := "", marker := "", height := 48.0, framed := false) -> Row:
	return Row.new(text, icon_name, right, marker, height, framed)


# ----------------------------------------------------------------------- Slot ----

## Item / equipment slot: dark cell, tinted icon, stack count, rarity edge, gold frame when selected.
class Slot extends Button:
	var item_id := ""
	var count := 0
	var edge := Color(0, 0, 0, 0)
	var tint := AF.TEXT
	var empty_icon := ""
	var selected := false
	var locked := false
	var caption := ""
	var _kit: GDScript = load(KIT_PATH)

	func _init(side := 68.0) -> void:
		custom_minimum_size = Vector2(side, side)
		focus_mode = Control.FOCUS_NONE
		flat = true
		for st: String in ["normal", "hover", "pressed", "focus", "disabled"]:
			add_theme_stylebox_override(st, StyleBoxEmpty.new())

	func set_item(id: String, n := 0, edge_color := Color(0, 0, 0, 0), tint_color := AF.TEXT) -> void:
		item_id = id
		count = n
		edge = edge_color
		tint = tint_color
		queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var hover := is_hovered() and not disabled
		var sb := AF.slot(selected)
		if hover and not selected:
			sb.border_color = AF.GOLD
		if item_id == "":
			sb.bg_color = Color(0.06, 0.055, 0.05, 0.75)
		draw_style_box(sb, r)
		if item_id != "":
			var t: Texture2D = _kit.item_icon(item_id)
			var inner := r.grow(-size.x * 0.17)
			if t != null:
				draw_texture_rect(t, inner, false, tint)
			else:
				var f := AF.title_font(700)
				var fs := int(size.x * 0.42)
				var letter := item_id.substr(0, 1).to_upper()
				var ts := f.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
				draw_string(f, Vector2((size.x - ts.x) * 0.5, size.y * 0.5 + fs * 0.34), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, tint)
			if edge.a > 0.0:
				draw_rect(Rect2(3, size.y - 5, size.x - 6, 2), edge)
			if count > 1:
				var f2 := AF.font(AF.BODY_FONT)
				var fs2 := int(clampf(size.x * 0.22, 12.0, 17.0))
				var txt := str(count)
				var tw := f2.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2).x
				var pos := Vector2(size.x - tw - 7, size.y - 9)
				draw_string_outline(f2, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, 5, Color(0, 0, 0, 0.9))
				draw_string(f2, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, AF.TEXT)
		elif empty_icon != "":
			var t2: Texture2D = _kit.icon(empty_icon)
			if t2 != null:
				draw_texture_rect(t2, r.grow(-size.x * 0.24), false, Color(AF.TEXT, 0.16 if not locked else 0.07))
		if locked:
			draw_rect(r.grow(-2), Color(0, 0, 0, 0.35))

	func _notification(what: int) -> void:
		if what == NOTIFICATION_MOUSE_ENTER or what == NOTIFICATION_MOUSE_EXIT:
			queue_redraw()


static func slot(side := 68.0) -> Slot:
	return Slot.new(side)


# -------------------------------------------------------------------- Buttons ----

## Gold-framed text button (Learn, Track, Show on Map...). primary = filled gold.
static func button(text: String, primary := false, min_h := 48.0, size := 17) -> Button:
	var b: Button
	if primary:
		b = AF.gold_button(text)
		b.add_theme_font_size_override("font_size", size)
		for st: String in ["normal", "hover", "pressed", "disabled", "focus"]:
			var sb: StyleBoxFlat = b.get_theme_stylebox(st)
			sb.content_margin_left = 16
			sb.content_margin_right = 16
			sb.content_margin_top = 8
			sb.content_margin_bottom = 8
	else:
		b = Button.new()
		b.text = text
		b.add_theme_font_override("font", AF.title_font(600))
		b.add_theme_font_size_override("font_size", size)
		b.add_theme_stylebox_override("normal", box(Color(0.04, 0.036, 0.03, 0.8), AF.GOLD_DIM, 3, 8))
		b.add_theme_stylebox_override("hover", box(Color(0.16, 0.12, 0.06, 0.9), AF.GOLD, 3, 8))
		b.add_theme_stylebox_override("pressed", box(Color(0.24, 0.17, 0.07, 0.95), AF.GOLD_BRIGHT, 3, 8))
		b.add_theme_stylebox_override("focus", box(Color(0.16, 0.12, 0.06, 0.9), AF.GOLD, 3, 8))
		b.add_theme_stylebox_override("disabled", box(Color(0.03, 0.03, 0.03, 0.5), Color(AF.GOLD_DIM, 0.2), 3, 8))
		b.add_theme_color_override("font_color", AF.TEXT)
		b.add_theme_color_override("font_hover_color", AF.GOLD_BRIGHT)
		b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.28))
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, min_h)
	return b


## A key chip that is also clickable: [F] Equip. Returns the container; `.set_meta("btn")`
## holds the Button. `disabled` greys it out.
static func hint(key: String, text: String, cb: Callable, disabled := false) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	var chip := AF.key_hint(key, "")
	# key_hint adds an (empty) label after the chip: keep only the chip.
	var chip_box: Control = chip.get_child(0)
	chip.remove_child(chip_box)
	chip.queue_free()
	chip_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(chip_box)
	var b := Button.new()
	b.text = text
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 48)
	b.add_theme_font_override("font", AF.font(AF.BODY_FONT))
	b.add_theme_font_size_override("font_size", 17)
	b.add_theme_color_override("font_color", AF.TEXT_DIM if not disabled else Color(AF.TEXT_DIM, 0.4))
	b.add_theme_color_override("font_hover_color", AF.GOLD_BRIGHT)
	b.add_theme_color_override("font_pressed_color", AF.GOLD_BRIGHT)
	b.add_theme_color_override("font_disabled_color", Color(AF.TEXT_DIM, 0.35))
	for st: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	b.disabled = disabled
	b.pressed.connect(cb)
	h.add_child(b)
	chip_box.modulate.a = 0.4 if disabled else 1.0
	return h


## Tab-style toggle used for sub-tabs and quest states: gold-lit when active.
static func tab_button(text: String, active: bool, cb: Callable, min_w := 0.0) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(min_w, 48)
	b.add_theme_font_override("font", AF.title_font(600))
	b.add_theme_font_size_override("font_size", 15)
	var normal := box(Color(0.03, 0.028, 0.025, 0.55), AF.GOLD_DIM, 3, 8)
	var on := box(Color(AF.GOLD.r, AF.GOLD.g, AF.GOLD.b, 0.2), AF.GOLD, 3, 8)
	b.add_theme_stylebox_override("normal", on if active else normal)
	b.add_theme_stylebox_override("hover", box(Color(AF.GOLD.r, AF.GOLD.g, AF.GOLD.b, 0.28), AF.GOLD_BRIGHT, 3, 8))
	b.add_theme_stylebox_override("pressed", on)
	b.add_theme_stylebox_override("focus", on if active else normal)
	b.add_theme_color_override("font_color", AF.GOLD_BRIGHT if active else AF.TEXT_DIM)
	b.add_theme_color_override("font_hover_color", AF.GOLD_BRIGHT)
	b.pressed.connect(cb)
	return b


# ---------------------------------------------------------------- ListDetail ----

## Left list of selectable rows + right detail panel, both scrolling. Entries:
## {id, name, icon?, right?, marker?, header?}; a "header" entry is a group title.
class ListDetail extends HBoxContainer:
	signal selected(id: String)
	var list: VBoxContainer
	var detail: VBoxContainer
	var detail_scroll: ScrollContainer
	var _rows: Dictionary = {}
	var current := ""
	var _kit: GDScript = load(KIT_PATH)

	func _init(list_width := 250.0) -> void:
		add_theme_constant_override("separation", 14)
		size_flags_vertical = Control.SIZE_EXPAND_FILL
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var ls := ScrollContainer.new()
		ls.custom_minimum_size.x = list_width
		ls.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		ls.scroll_deadzone = 12
		add_child(ls)
		list = VBoxContainer.new()
		list.add_theme_constant_override("separation", 4)
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ls.add_child(list)
		var panel := PanelContainer.new()
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.add_theme_stylebox_override("panel", _kit.box(Color(0.03, 0.028, 0.025, 0.55), AF.GOLD_DIM, 3, 16))
		add_child(panel)
		detail_scroll = ScrollContainer.new()
		detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		detail_scroll.scroll_deadzone = 12
		panel.add_child(detail_scroll)
		detail = VBoxContainer.new()
		detail.add_theme_constant_override("separation", 10)
		detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		detail_scroll.add_child(detail)

	func set_items(items: Array, keep := true) -> void:
		var old := current if keep else ""
		_kit.clear(list)
		_rows.clear()
		var first := ""
		for e: Dictionary in items:
			if e.has("header"):
				list.add_child(_kit.list_header(String(e["header"])))
				continue
			if e.has("note"):
				list.add_child(_kit.lbl(String(e["note"]), 15, AF.TEXT_DIM, true, "italic"))
				continue
			var r: Row = _kit.row(String(e["name"]), String(e.get("icon", "")), String(e.get("right", "")), String(e.get("marker", "")))
			r.key = String(e["id"])
			r.pressed.connect(select.bind(r.key))
			list.add_child(r)
			_rows[r.key] = r
			if first == "":
				first = r.key
		current = old if _rows.has(old) else first
		for k: String in _rows:
			(_rows[k] as Row).set_selected(k == current)

	func select(id: String) -> void:
		if not _rows.has(id):
			return
		current = id
		for k: String in _rows:
			(_rows[k] as Row).set_selected(k == id)
		selected.emit(id)

	func step(delta: int) -> void:
		var keys: Array = _rows.keys()
		if keys.is_empty():
			return
		var i := keys.find(current)
		select(String(keys[clampi(i + delta, 0, keys.size() - 1)]))


static func list_header(text: String) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	h.custom_minimum_size = Vector2(0, 34)
	h.add_child(lbl(text, 16, AF.GOLD, false, "title"))
	var line := AF.separator()
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(line)
	return h
