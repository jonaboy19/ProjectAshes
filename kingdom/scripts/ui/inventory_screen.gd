extends Control
## Full-screen pack and equipment: a grid of item tiles with filter tabs and a
## sort toggle, the paper-doll of the seven equipment slots with the stat sums
## and active buffs, and a detail panel for the selected item (use, equip or
## take off, drop, and what the market pays for it).
##
## Icons: an SVG at assets/ui/icons/items/<item id>.svg is used when one has been
## imported (e.g. game-icons.net, CC-BY, from assets/incoming/game-icons); until
## then each tile is a rounded swatch in its category colour with the item's
## initial. Quality shows as a coloured pip (rough grey, fine teal, masterwork gold).
##
## Reads Life.inventory, and Life.equipment / Life.crafting when Life owns them
## (otherwise a shared fallback, so the screen works before those hooks land).
## Pauses the game while open (process_mode ALWAYS), like the world map.
##   InventoryScreen.open_for(hud)

signal closed

const Crafting := preload("res://scripts/sim/crafting.gd")
const Equipment := preload("res://scripts/sim/equipment.gd")
const SELF_PATH := "res://scripts/ui/inventory_screen.gd"

const CATEGORY_COLORS := {
	"food": Color("c9824a"), "healing": Color("d9566a"), "material": Color("8c7f68"),
	"ore": Color("6f7d92"), "gear": Color("2f9e9a"), "tack": Color("9c6a3f"), "other": Color("6c7a99"),
}
const FILTERS := [["all", "All"], ["food", "Food"], ["healing", "Remedies"], ["material", "Materials"],
	["gear", "Gear"], ["other", "Other"]]
const SORTS := [["name", "Name"], ["category", "Type"], ["value", "Value"], ["count", "Count"]]
## Paper-doll layout (3 columns); "" is an empty cell.
const DOLL := ["", "head", "trinket", "main_hand", "body", "off_hand", "hands", "feet", ""]

static var _fallback_equipment: RefCounted
static var _fallback_crafting: RefCounted

var _filter := "all"
var _sort := 0
## {id, quality, slot ("" = in the pack)}
var _selected: Dictionary = {}
var _was_paused := false
var _tile := 84

var _title_font: Font
var _grid: GridContainer
var _scroll: ScrollContainer
var _doll_tiles: Dictionary = {}     # slot -> Tile
var _stats_label: Label
var _buffs_label: Label
var _subtitle: Label
var _detail_icon: Tile
var _detail_name: Label
var _detail_kind: Label
var _detail_text: Label
var _btn_use: Button
var _btn_equip: Button
var _btn_drop: Button
var _status: Label
var _sort_btn: Button
var _tabs: Dictionary = {}
var _doll_panel: PanelContainer
var _detail_panel: PanelContainer


## A square item tile drawn in code: category swatch, icon or initial, count, quality pip.
class Tile extends Button:
	var item_id := ""
	var quality := 1
	var amount := 0
	var slot_label := ""
	var selected := false

	func _init(side: int) -> void:
		custom_minimum_size = Vector2(side, side)
		focus_mode = Control.FOCUS_NONE
		flat = true
		for st in ["normal", "hover", "pressed", "focus", "disabled"]:
			add_theme_stylebox_override(st, StyleBoxEmpty.new())

	func set_item(id: String, q := 1, n := 0) -> void:
		item_id = id
		quality = q
		amount = n
		queue_redraw()

	func _draw() -> void:
		draw_item(self, Rect2(Vector2.ZERO, size), item_id, quality, amount, selected, slot_label)

	## Shared with the crafting screen.
	static func draw_item(ci: CanvasItem, r: Rect2, id: String, q: int, n: int, sel := false, empty_label := "") -> void:
		var font := ThemeDB.fallback_font
		var box := StyleBoxFlat.new()
		box.set_corner_radius_all(int(r.size.x * 0.16))
		box.anti_aliasing = true
		box.set_border_width_all(2 if sel else 1)
		if id == "":
			box.bg_color = Color(1, 1, 1, 0.035)
			box.border_color = UITheme.ACCENT if sel else Color(1, 1, 1, 0.1)
			ci.draw_style_box(box, r)
			if empty_label != "":
				var fs := int(r.size.x * 0.15)
				var tw := font.get_string_size(empty_label, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
				ci.draw_string(font, r.position + Vector2((r.size.x - tw) * 0.5, r.size.y * 0.56), empty_label,
					HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UITheme.TEXT_DIM * Color(1, 1, 1, 0.6))
			return
		var col: Color = CATEGORY_COLORS.get(String(Crafting.item_info(id).get("category", "other")), CATEGORY_COLORS["other"])
		box.bg_color = col.darkened(0.55)
		box.bg_color.a = 0.92
		box.border_color = UITheme.ACCENT if sel else col.darkened(0.1)
		ci.draw_style_box(box, r)
		var inner := r.grow(-r.size.x * 0.1)
		var glow := StyleBoxFlat.new()
		glow.bg_color = col.darkened(0.2)
		glow.bg_color.a = 0.55
		glow.set_corner_radius_all(int(inner.size.x * 0.5))
		glow.anti_aliasing = true
		ci.draw_style_box(glow, inner.grow(-inner.size.x * 0.08))
		var tex := UITheme.icon("items/" + id)
		if tex:
			var s := inner.size.x * 0.72
			ci.draw_texture_rect(tex, Rect2(r.get_center() - Vector2(s, s) * 0.5, Vector2(s, s)), false)
		else:
			var letter := Crafting.item_name(id).substr(0, 1).to_upper()
			var fs := int(r.size.x * 0.42)
			var f: Font = UITheme.title_font()
			var ts := f.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
			var pos := r.position + Vector2((r.size.x - ts.x) * 0.5, r.size.y * 0.5 + fs * 0.36)
			ci.draw_string(f, pos + Vector2(0, 2), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.45))
			ci.draw_string(f, pos, letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UITheme.TEXT)
		if Equipment.is_equippable(id):
			var pc: Color = Crafting.QUALITY_COLORS[clampi(q, 0, 2)]
			ci.draw_circle(r.position + Vector2(r.size.x * 0.17, r.size.y * 0.17), r.size.x * 0.07, pc)
		if n > 1:
			var t := "×%d" % n
			var fs2 := int(r.size.x * 0.19)
			var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2).x
			var pill := StyleBoxFlat.new()
			pill.bg_color = Color(0, 0, 0, 0.6)
			pill.set_corner_radius_all(fs2)
			var pr := Rect2(r.end - Vector2(w + 12, fs2 + 8) - Vector2(4, 4), Vector2(w + 12, fs2 + 8))
			ci.draw_style_box(pill, pr)
			ci.draw_string(font, pr.position + Vector2(6, fs2 + 1), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, UITheme.TEXT)


# --- shared helpers ---------------------------------------------------------------------

static func category_of(id: String) -> String:
	var c := String(Crafting.item_info(id).get("category", "other"))
	return c if CATEGORY_COLORS.has(c) else "other"


static func category_color(id: String) -> Color:
	return CATEGORY_COLORS[category_of(id)]


static func item_texture(id: String) -> Texture2D:
	return UITheme.icon("items/" + id)


static func filter_of(id: String) -> String:
	match category_of(id):
		"food":
			return "food"
		"healing":
			return "healing"
		"material", "ore", "tack":
			return "material"
		"gear":
			return "gear"
	return "other"


static func shared_equipment() -> RefCounted:
	var e: Variant = Life.get("equipment")
	if e is RefCounted:
		return e
	if _fallback_equipment == null:
		_fallback_equipment = Equipment.new()
	return _fallback_equipment


static func shared_crafting() -> RefCounted:
	var c: Variant = Life.get("crafting")
	if c is RefCounted:
		return c
	if _fallback_crafting == null:
		_fallback_crafting = Crafting.new()
	return _fallback_crafting


static func abs_hours() -> float:
	return WorldSim.day * 24.0 + WorldSim.time_of_day


## What the market pays for one (quality scales gear), or 0.
static func sell_value(id: String, quality := 1) -> int:
	var m: Variant = Life.get("market")
	var base := 0
	if m is Object and ((m as Object).get("base_price") as Dictionary).has(id):
		base = int((m as Object).call("sell_price", id))
	else:
		base = int(floor(float(Crafting.item_info(id).get("price", 0)) * 0.5))
	if Equipment.is_equippable(id):
		base = int(round(base * [0.6, 1.0, 1.7][clampi(quality, 0, 2)]))
	return maxi(0, base)


## Opens (creating on first use) the screen as a child of `host` (the HUD layer).
static func open_for(host: Node) -> Control:
	var s: Control = host.get_node_or_null("InventoryScreen")
	if s == null:
		s = (load(SELF_PATH) as GDScript).new()
		s.name = "InventoryScreen"
		host.add_child(s)
	if host.has_method("close_menu"):
		host.call("close_menu")
	s.call("open")
	return s


# --- lifecycle --------------------------------------------------------------------------

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UITheme.theme()
	visible = false
	_title_font = UITheme.title_font_weight(600)
	_build()
	Life.inventory_changed.connect(func() -> void:
		if visible:
			refresh())
	resized.connect(_fit)


func open() -> void:
	if visible:
		refresh()
		return
	_was_paused = get_tree().paused
	get_tree().paused = true
	visible = true
	Audio.play_ui("open")
	_status.text = ""
	_fit()
	refresh()


func close() -> void:
	if not visible:
		return
	visible = false
	get_tree().paused = _was_paused
	Audio.play_ui("close")
	closed.emit()


func _unhandled_input(e: InputEvent) -> void:
	if not visible:
		return
	if e.is_action_pressed("ui_cancel") or e.is_action_pressed("journal"):
		close()
		get_viewport().set_input_as_handled()


# --- build ------------------------------------------------------------------------------

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(UITheme.BG_SOLID, 0.96)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	margin.add_child(col)

	# Header: title, rule, subtitle (gold and carried), close.
	var head := HBoxContainer.new()
	col.add_child(head)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(titles)
	var title := _label(titles, 28, UITheme.ACCENT)
	title.text = "PACK & EQUIPMENT"
	title.add_theme_font_override("font", _title_font)
	var rule := ColorRect.new()
	rule.color = UITheme.ACCENT
	rule.custom_minimum_size = Vector2(56, 2)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	titles.add_child(rule)
	_subtitle = _label(titles, 15, UITheme.TEXT_DIM)
	head.add_child(round_button("×", 60, 34, close))

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	col.add_child(body)

	# Left: paper-doll and stats.
	_doll_panel = PanelContainer.new()
	_doll_panel.add_theme_stylebox_override("panel", _panel())
	body.add_child(_doll_panel)
	var dbox := VBoxContainer.new()
	dbox.add_theme_constant_override("separation", 10)
	_doll_panel.add_child(dbox)
	var dh := _label(dbox, 13, UITheme.ACCENT_2)
	dh.text = "EQUIPPED"
	var doll := GridContainer.new()
	doll.columns = 3
	doll.add_theme_constant_override("h_separation", 8)
	doll.add_theme_constant_override("v_separation", 8)
	doll.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	dbox.add_child(doll)
	for slot: String in DOLL:
		if slot == "":
			var gap := Control.new()
			gap.custom_minimum_size = Vector2(72, 72)
			doll.add_child(gap)
			continue
		var t := Tile.new(72)
		t.slot_label = String(Equipment.SLOT_NAMES[slot])
		t.pressed.connect(_select_slot.bind(slot))
		doll.add_child(t)
		_doll_tiles[slot] = t
	_stats_label = _label(dbox, 15, UITheme.TEXT)
	_stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_buffs_label = _label(dbox, 13, UITheme.OK)
	_buffs_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	# Centre: tabs, sort, grid.
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 10)
	body.add_child(mid)
	var tabs_scroll := ScrollContainer.new()
	tabs_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs_scroll.custom_minimum_size.y = 50
	mid.add_child(tabs_scroll)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	tabs_scroll.add_child(tabs)
	var group := ButtonGroup.new()
	for f: Array in FILTERS:
		var b := Button.new()
		b.text = f[1]
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 44)
		b.button_pressed = f[0] == _filter
		b.pressed.connect(func() -> void:
			_filter = f[0]
			refresh())
		tabs.add_child(b)
		_tabs[f[0]] = b
	_sort_btn = Button.new()
	_sort_btn.focus_mode = Control.FOCUS_NONE
	_sort_btn.custom_minimum_size = Vector2(0, 44)
	_sort_btn.pressed.connect(func() -> void:
		_sort = (_sort + 1) % SORTS.size()
		refresh())
	tabs.add_child(_sort_btn)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.scroll_deadzone = 12
	mid.add_child(_scroll)
	_grid = GridContainer.new()
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	_scroll.add_child(_grid)
	_scroll.resized.connect(_fit_grid)

	# Right: detail.
	_detail_panel = PanelContainer.new()
	_detail_panel.add_theme_stylebox_override("panel", _panel())
	body.add_child(_detail_panel)
	var det := VBoxContainer.new()
	det.add_theme_constant_override("separation", 8)
	_detail_panel.add_child(det)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	det.add_child(top)
	_detail_icon = Tile.new(76)
	_detail_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(_detail_icon)
	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_child(names)
	_detail_kind = _label(names, 13, UITheme.ACCENT_2)
	_detail_name = _label(names, 21, UITheme.TEXT)
	_detail_name.add_theme_font_override("font", _title_font)
	_detail_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var dscroll := ScrollContainer.new()
	dscroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	det.add_child(dscroll)
	_detail_text = _label(dscroll, 15, UITheme.TEXT_DIM)
	_detail_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_use = _action_button(det, "Use", true, _on_use)
	_btn_equip = _action_button(det, "Equip", false, _on_equip)
	_btn_drop = _action_button(det, "Drop one", false, _on_drop)
	_btn_drop.add_theme_color_override("font_color", UITheme.DANGER.lightened(0.2))
	_status = _label(det, 14, UITheme.OK)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _panel() -> StyleBoxFlat:
	var s := UITheme.panel_box(18)
	s.set_content_margin_all(16)
	s.shadow_size = 8
	return s


func _label(parent: Control, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _action_button(parent: Control, text: String, primary: bool, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 50)
	b.add_theme_font_size_override("font_size", 17)
	if primary:
		gold_button(b)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


## The gold call-to-action look (the map's travel button).
static func gold_button(b: Button) -> void:
	b.add_theme_stylebox_override("normal", UITheme.pill(UITheme.ACCENT.darkened(0.25), UITheme.ACCENT, 25))
	b.add_theme_stylebox_override("hover", UITheme.pill(UITheme.ACCENT.darkened(0.1), UITheme.ACCENT, 25))
	b.add_theme_stylebox_override("pressed", UITheme.pill(UITheme.ACCENT, Color.WHITE, 25))
	b.add_theme_stylebox_override("disabled", UITheme.pill(Color(1, 1, 1, 0.04), UITheme.STROKE, 25))
	for c in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(c, Color("1b1407"))


static func round_button(text: String, diameter: int, font_size: int, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(diameter, diameter)
	b.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", font_size)
	var r := diameter / 2
	for pair: Array in [["normal", UITheme.BG, UITheme.STROKE], ["hover", UITheme.BG, UITheme.ACCENT.darkened(0.2)],
			["pressed", UITheme.ACCENT.darkened(0.35), UITheme.ACCENT]]:
		var sb := UITheme.pill(pair[1], pair[2], r)
		sb.set_content_margin_all(0)
		b.add_theme_stylebox_override(pair[0], sb)
	b.pressed.connect(cb)
	return b


## Column widths for the screen size (phones in landscape down to ~640 px wide).
func _fit() -> void:
	var w := size.x if size.x > 0.0 else get_viewport_rect().size.x
	var narrow := w < 1000.0
	_tile = 72 if narrow else 84
	_doll_panel.custom_minimum_size.x = 250.0 if narrow else 280.0
	_detail_panel.custom_minimum_size.x = 250.0 if narrow else 310.0
	_fit_grid()


func _fit_grid() -> void:
	var w := _scroll.size.x
	if w <= 0.0:
		return
	_grid.columns = maxi(2, int((w - 8.0) / (_tile + 10.0)))


# --- data -------------------------------------------------------------------------------

## Carried stacks grouped by item and quality: [{id, quality, count}].
func _stacks() -> Array[Dictionary]:
	var by := {}
	var order: Array[String] = []
	for it in Life.inventory.get_items():
		var id := it.get_prototype().get_prototype_id()
		var q := Equipment.quality_of(it) if Equipment.is_equippable(id) else 1
		var key := "%s#%d" % [id, q]
		if not by.has(key):
			by[key] = {"id": id, "quality": q, "count": 0}
			order.append(key)
		by[key]["count"] = int(by[key]["count"]) + it.get_stack_size()
	var out: Array[Dictionary] = []
	for k in order:
		var e: Dictionary = by[k]
		if _filter == "all" or filter_of(String(e["id"])) == _filter:
			out.append(e)
	var mode := String(SORTS[_sort][0])
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ia := String(a["id"])
		var ib := String(b["id"])
		match mode:
			"category":
				if category_of(ia) != category_of(ib):
					return category_of(ia) < category_of(ib)
			"value":
				var va := sell_value(ia, int(a["quality"]))
				var vb := sell_value(ib, int(b["quality"]))
				if va != vb:
					return va > vb
			"count":
				if int(a["count"]) != int(b["count"]):
					return int(a["count"]) > int(b["count"])
		if Crafting.item_name(ia) != Crafting.item_name(ib):
			return Crafting.item_name(ia) < Crafting.item_name(ib)
		return int(a["quality"]) > int(b["quality"]))
	return out


func refresh() -> void:
	var eq := shared_equipment()
	var now := abs_hours()
	var carried := 0
	for it in Life.inventory.get_items():
		carried += it.get_stack_size()
	_subtitle.text = "%d gold  ·  %d items carried" % [Game.gold, carried]
	_sort_btn.text = "Sort: %s" % SORTS[_sort][1]
	# Grid.
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	var stacks := _stacks()
	var still_there := _selected.is_empty() or String(_selected.get("slot", "")) != ""
	for e in stacks:
		var t := Tile.new(_tile)
		t.set_item(String(e["id"]), int(e["quality"]), int(e["count"]))
		t.selected = String(_selected.get("slot", "x")) == "" and _selected.get("id", "") == e["id"] \
			and int(_selected.get("quality", -1)) == int(e["quality"])
		if t.selected:
			still_there = true
		t.pressed.connect(_select_item.bind(String(e["id"]), int(e["quality"])))
		_grid.add_child(t)
	if stacks.is_empty():
		var l := _label(_grid, 15, UITheme.TEXT_DIM)
		l.text = "Nothing here." if _filter != "all" else "Your pack is empty."
	if not still_there:
		_selected = {}
	# Doll.
	for slot: String in _doll_tiles:
		var t: Tile = _doll_tiles[slot]
		var e: Dictionary = eq.call("equipped", slot)
		t.set_item(String(e.get("id", "")), int(e.get("quality", 1)))
		t.selected = String(_selected.get("slot", "")) == slot
		t.queue_redraw()
	var st: Dictionary = eq.call("stats", now)
	_stats_label.text = "Armour %d   Damage +%d\nSpeed %+d%%" % [int(round(float(st["armour"]))),
		int(round(float(st["damage"]))), int(round(float(st["speed"]) * 100.0))]
	var bl := PackedStringArray()
	for b: Dictionary in eq.call("active_buffs", now):
		bl.append("%s: %s  (%s left)" % [b["name"], _stat_text(String(b["stat"]), float(b["value"])),
			_hours_text(float(b["until"]) - now)])
	_buffs_label.text = "\n".join(bl)
	_buffs_label.visible = not bl.is_empty()
	_show_detail()


func _select_item(id: String, q: int) -> void:
	_selected = {"id": id, "quality": q, "slot": ""}
	_status.text = ""
	refresh()


func _select_slot(slot: String) -> void:
	var e: Dictionary = shared_equipment().call("equipped", slot)
	if e.is_empty():
		_selected = {}
		_status.text = "%s: nothing worn. Pick gear from your pack." % Equipment.SLOT_NAMES[slot]
	else:
		_selected = {"id": String(e["id"]), "quality": int(e["quality"]), "slot": slot}
		_status.text = ""
	refresh()


static func _stat_text(stat: String, v: float) -> String:
	match stat:
		"speed":
			return "%+d%% speed" % int(round(v * 100.0))
		"stamina_regen":
			return "%+d%% stamina recovery" % int(round(v * 100.0))
		"max_health":
			return "%+d health" % int(v)
	return "%+d %s" % [int(v), stat]


static func _hours_text(h: float) -> String:
	if h >= 1.0:
		return "%dh %02dm" % [int(h), int(fmod(h, 1.0) * 60.0)]
	return "%dm" % maxi(1, int(h * 60.0))


## Lines describing an item (shared with the crafting screen).
static func describe(id: String, quality := 1, durability := -1) -> String:
	var info := Crafting.item_info(id)
	var lines := PackedStringArray()
	if info.has("description"):
		lines.append(String(info["description"]))
	if float(info.get("nutrition", 0.0)) > 0.0:
		lines.append("Nourishes %d." % int(info["nutrition"]))
	if int(info.get("heal", 0)) > 0:
		lines.append("Heals %d." % int(info["heal"]))
	if info.has("buff_stat"):
		lines.append("%s: %s for %dh." % [info.get("buff_name", "Buff"),
			_stat_text(String(info["buff_stat"]), float(info.get("buff_value", 0.0))), int(info.get("buff_hours", 1))])
	if info.has("cures"):
		lines.append("Cures: %s." % String(info["cures"]).replace("_", " "))
	if Equipment.is_equippable(id):
		var st := Equipment.item_stats(id, quality, durability)
		var parts := PackedStringArray()
		if float(st["armour"]) != 0.0:
			parts.append("Armour %d" % int(round(float(st["armour"]))))
		if float(st["damage"]) != 0.0:
			parts.append("Damage +%d" % int(round(float(st["damage"]))))
		if float(st["speed"]) != 0.0:
			parts.append("Speed %+d%%" % int(round(float(st["speed"]) * 100.0)))
		lines.append("%s slot.  %s" % [Equipment.SLOT_NAMES[Equipment.slot_of(id)], "  ·  ".join(parts)])
		var maxd := Equipment.max_durability(id, quality)
		lines.append("Durability %d / %d%s" % [maxd if durability < 0 else durability, maxd,
			"  (worn out: half effect)" if durability == 0 else ""])
		if info.has("tool"):
			lines.append("Tool: helps %s." % String(info["tool"]))
	return "\n".join(lines)


func _show_detail() -> void:
	var has := not _selected.is_empty()
	_detail_panel.modulate.a = 1.0
	_btn_use.visible = false
	_btn_equip.visible = false
	_btn_drop.visible = false
	if not has:
		_detail_icon.set_item("")
		_detail_kind.text = "SELECT AN ITEM"
		_detail_name.text = ""
		_detail_text.text = "Tap an item to see what it does.\nTap a slot on the left to see what you wear."
		return
	var id := String(_selected["id"])
	var q := int(_selected.get("quality", 1))
	var slot := String(_selected.get("slot", ""))
	var gear := Equipment.is_equippable(id)
	var dur := -1
	if slot != "":
		dur = int(shared_equipment().call("equipped", slot).get("durability", -1))
	_detail_icon.set_item(id, q)
	var kind := String(FILTERS[FILTERS.map(func(f: Array) -> String: return f[0]).find(filter_of(id))][1]).to_upper()
	if gear:
		kind += "  ·  " + Crafting.quality_name(q).to_upper()
	if slot != "":
		kind += "  ·  WORN"
	_detail_kind.text = kind
	_detail_kind.add_theme_color_override("font_color", Crafting.QUALITY_COLORS[q] if gear else UITheme.ACCENT_2)
	_detail_name.text = Crafting.item_name(id)
	var lines := describe(id, q, dur)
	var have := _count_quality(id, q) if slot == "" else 0
	var sv := sell_value(id, q)
	lines += "\n\nCarried: %d   ·   Sells for %s" % [have, ("%dg" % sv) if sv > 0 else "nothing"]
	_detail_text.text = lines.strip_edges()
	var info := Crafting.item_info(id)
	var usable := float(info.get("nutrition", 0.0)) > 0.0 or int(info.get("heal", 0)) > 0 \
		or info.has("buff_stat") or info.has("cures") or info.has("rest_bonus")
	_btn_use.visible = usable and slot == ""
	_btn_use.text = "Eat" if category_of(id) == "food" else ("Camp" if info.has("rest_bonus") else "Use")
	_btn_equip.visible = gear
	_btn_equip.text = "Take off" if slot != "" else "Equip"
	if gear and slot == "":
		var cur := String(shared_equipment().call("item_in", Equipment.slot_of(id)))
		if cur != "":
			_btn_equip.text = "Equip (swap %s)" % Crafting.item_name(cur)
		if not _btn_use.visible:
			gold_button(_btn_equip)
	_btn_drop.visible = slot == "" and have > 0


func _count_quality(id: String, q: int) -> int:
	var n := 0
	for it in Life.inventory.get_items_with_prototype_id(id):
		if not Equipment.is_equippable(id) or Equipment.quality_of(it) == q:
			n += it.get_stack_size()
	return n


# --- actions ----------------------------------------------------------------------------

func _on_use() -> void:
	if _selected.is_empty():
		return
	var id := String(_selected["id"])
	_status.text = String(shared_equipment().call("consume", Life, id, abs_hours()))
	Audio.play_ui("pickup")
	refresh()


func _on_equip() -> void:
	if _selected.is_empty():
		return
	var eq := shared_equipment()
	var slot := String(_selected.get("slot", ""))
	if slot != "":
		_status.text = String(eq.call("unequip_to", Life, slot))
		_selected = {}
	else:
		var id := String(_selected["id"])
		_status.text = String(eq.call("equip_from", Life, id, int(_selected.get("quality", 1))))
		_selected = {"id": id, "quality": int(_selected.get("quality", 1)), "slot": Equipment.slot_of(id)}
	Audio.play_ui("pickup")
	refresh()


## Drops one of the selected stack (it is gone; there is no ground loot yet).
func _on_drop() -> void:
	if _selected.is_empty():
		return
	var id := String(_selected["id"])
	var q := int(_selected.get("quality", 1))
	var done := false
	if Equipment.is_equippable(id):
		for it in Life.inventory.get_items_with_prototype_id(id):
			if Equipment.quality_of(it) == q:
				if it.get_stack_size() > 1:
					it.set_stack_size(it.get_stack_size() - 1)
				else:
					Life.inventory.remove_item(it)
				done = true
				Life.inventory_changed.emit()
				break
	else:
		done = Life.take(id, 1)
	_status.text = ("You drop the %s." % Crafting.item_name(id)) if done else ""
	refresh()
