extends "res://scripts/ui/gamemenu/gm_tab.gd"
## INVENTORY: category list, item grid (Life.inventory), detail card, Equip / Use /
## Drop / Compare wired to Life.equipment and Life.

var _cat := "all"
var _sel := {}                       # {id, quality} of the selected stack
var _compare := false
var _all: Array[Dictionary] = []
var _shown: Array[Dictionary] = []
var _slots: Array = []
var _cat_rows: Dictionary = {}
var _grid: GridContainer
var _scroll: ScrollContainer
var _cat_title: Label
var _count_lbl: Label
var _gold_lbl: Label
var _weight_lbl: Label
var _detail: VBoxContainer
var _status := ""
var _cols := 8


## Big item preview: rarity glow, frame and the icon.
class Showcase extends Control:
	var item_id := ""
	var color := Color.WHITE
	var tint := Color.WHITE
	var _kit: GDScript = load("res://scripts/ui/gamemenu/gm_kit.gd")

	func _init() -> void:
		custom_minimum_size = Vector2(0, 124)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_style_box(_kit.box(Color(0.025, 0.022, 0.02, 0.85), Color(color, 0.55), 3, 0), r)
		var c := size * 0.5
		for i in 7:
			draw_circle(c, 62.0 - i * 8.0, Color(color, 0.028 + i * 0.006))
		var t: Texture2D = _kit.item_icon(item_id)
		if t != null:
			var s := minf(size.y - 22.0, 104.0)
			draw_texture_rect(t, Rect2(c - Vector2(s, s) * 0.5, Vector2(s, s)), false, tint)


func build() -> void:
	var root := page_hbox(14)
	# Left: categories.
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 196
	left.add_theme_constant_override("separation", 4)
	root.add_child(left)
	for c: Array in MD.CATEGORIES:
		var r := Kit.row(String(c[1]), "cat_" + String(c[0]), "")
		r.pressed.connect(_set_category.bind(String(c[0])))
		left.add_child(r)
		_cat_rows[String(c[0])] = r
	# Centre: header + grid.
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 8)
	root.add_child(mid)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	mid.add_child(head)
	_cat_title = Kit.lbl("", 18, AF.GOLD_BRIGHT, false, "title")
	head.add_child(_cat_title)
	_count_lbl = Kit.lbl("", 15, AF.TEXT_DIM)
	_count_lbl.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(_count_lbl)
	head.add_child(Kit.hspacer())
	head.add_child(Kit.tex_rect(Kit.icon("gold"), 22, AF.GOLD_BRIGHT))
	_gold_lbl = Kit.lbl("", 18, AF.GOLD_BRIGHT, false, "title")
	head.add_child(_gold_lbl)
	head.add_child(Control.new())
	head.add_child(Kit.tex_rect(Kit.icon("weight"), 22, AF.TEXT_DIM))
	_weight_lbl = Kit.lbl("", 18, AF.TEXT, false, "title")
	head.add_child(_weight_lbl)
	mid.add_child(AF.separator())
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.scroll_deadzone = 12
	mid.add_child(_scroll)
	_grid = GridContainer.new()
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 8)
	_scroll.add_child(_grid)
	_scroll.resized.connect(_fit_grid)
	# Right: detail card.
	var card := PanelContainer.new()
	card.custom_minimum_size.x = 300
	card.add_theme_stylebox_override("panel", Kit.box(Color(0.03, 0.028, 0.025, 0.6), AF.GOLD_DIM, 3, 14))
	root.add_child(card)
	var ds := ScrollContainer.new()
	ds.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ds.scroll_deadzone = 12
	card.add_child(ds)
	_detail = VBoxContainer.new()
	_detail.add_theme_constant_override("separation", 8)
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ds.add_child(_detail)
	Life.inventory_changed.connect(func() -> void:
		if is_visible_in_tree():
			refresh())


func on_show() -> void:
	_status = ""
	refresh()


func _set_category(cat: String) -> void:
	_cat = cat
	_status = ""
	refresh()


func refresh() -> void:
	_all = MD.stacks()
	_shown = MD.filter_stacks(_all, _cat)
	# Keep the selection if it still exists, else the first item.
	var found := false
	for s: Dictionary in _shown:
		if not _sel.is_empty() and s["id"] == _sel["id"] and int(s["quality"]) == int(_sel["quality"]):
			found = true
	if not found:
		_sel = {"id": _shown[0]["id"], "quality": _shown[0]["quality"]} if not _shown.is_empty() else {}
	for c: Array in MD.CATEGORIES:
		var r: Kit.Row = _cat_rows[String(c[0])]
		r.set_selected(String(c[0]) == _cat)
		r.set_right(str(MD.filter_stacks(_all, String(c[0])).size()) if String(c[0]) != "all" else "")
	_cat_title.text = MD.category_name(_cat).to_upper()
	var items := 0
	for s: Dictionary in _shown:
		items += int(s["count"])
	_count_lbl.text = "%d item%s" % [items, "" if items == 1 else "s"]
	_gold_lbl.text = _thousands(Game.gold)
	var cap := MD.carry_capacity(MD.attribute_value(Life.mastery, MD.ATTRIBUTES[0]["from"], Life.player_level()))
	var w := MD.carry_weight(_all)
	_weight_lbl.text = "%.1f / %d" % [w, int(cap)]
	_weight_lbl.add_theme_color_override("font_color", AF.TEXT if w <= cap else Kit.BAD)
	_fit_grid()
	_build_grid()
	_show_detail()
	hints_changed()


static func _thousands(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	for i in s.length():
		if i > 0 and (s.length() - i) % 3 == 0:
			out += ","
		out += s[i]
	return ("-" if n < 0 else "") + out


func _fit_grid() -> void:
	var w := _scroll.size.x
	if w <= 0.0:
		return
	var cols := maxi(3, int((w + 8.0) / (68.0 + 8.0)))
	if cols != _cols:
		_cols = cols
		_build_grid()
	_grid.columns = _cols


func _build_grid() -> void:
	Kit.clear(_grid)
	_slots.clear()
	_grid.columns = _cols
	var cells := maxi(MD.PACK_SLOTS if _cat == "all" else 24, int(ceil(float(_shown.size()) / _cols)) * _cols)
	cells = int(ceil(float(cells) / _cols)) * _cols
	for i in cells:
		var s := Kit.slot(68)
		if i < _shown.size():
			var e: Dictionary = _shown[i]
			var id := String(e["id"])
			var q := int(e["quality"])
			s.set_item(id, int(e["count"]), MD.rarity_color(MD.rarity_of(id, q)) if MD.rarity_of(id, q) != 0 else Color(0, 0, 0, 0),
				Kit.CATEGORY_TINT.get(MD.category_of(id), AF.TEXT))
			s.selected = not _sel.is_empty() and id == _sel["id"] and q == int(_sel["quality"])
			s.pressed.connect(_select.bind(id, q))
		else:
			s.disabled = true
			s.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_grid.add_child(s)
		_slots.append(s)


func _select(id: String, q: int) -> void:
	_sel = {"id": id, "quality": q}
	_status = ""
	for i in _slots.size():
		var s = _slots[i]
		s.selected = i < _shown.size() and _shown[i]["id"] == id and int(_shown[i]["quality"]) == q
		s.queue_redraw()
	_show_detail()
	hints_changed()


# ---------------------------------------------------------------------- detail ----

func _show_detail() -> void:
	Kit.clear(_detail)
	if _sel.is_empty():
		_detail.add_child(Kit.lbl("NOTHING SELECTED", 15, AF.GOLD, false, "title"))
		_detail.add_child(Kit.lbl("Pick an item from the grid to see what it does.", 16, AF.TEXT_DIM, true, "italic"))
		return
	var id := String(_sel["id"])
	var q := int(_sel["quality"])
	var d := MD.item_detail(id, q)
	var name_l := Kit.lbl(String(d["name"]), 23, AF.TEXT, true, "title_bold")
	_detail.add_child(name_l)
	_detail.add_child(Kit.lbl("%s · %s" % [d["rarity_name"], d["type"]], 15, d["rarity_color"]))
	var show := Showcase.new()
	show.item_id = id
	show.color = d["rarity_color"]
	show.tint = Kit.CATEGORY_TINT.get(String(d["category"]), AF.TEXT)
	_detail.add_child(show)
	var rows: Array = d["rows"]
	var worn := {}
	var slot := String(d["slot"])
	if _compare and bool(d["gear"]):
		worn = Life.equipment.call("equipped", slot)
		if worn.is_empty():
			_detail.add_child(Kit.lbl("Nothing worn in this slot to compare with.", 14, AF.TEXT_DIM, true, "italic"))
		else:
			_detail.add_child(Kit.lbl("Compared with %s" % Crafting_name(String(worn["id"])), 14, AF.GOLD, true, "italic"))
	var comp: Array[Dictionary] = []
	if not worn.is_empty():
		comp = MD.compare_rows(d, worn)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	_detail.add_child(box)
	for i in rows.size():
		var row: Dictionary = rows[i]
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		h.custom_minimum_size = Vector2(0, 28)
		h.add_child(Kit.tex_rect(Kit.icon(String(row["icon"])), 18, AF.TEXT_DIM))
		h.add_child(Kit.lbl(String(row["label"]), 16, AF.TEXT_DIM))
		h.add_child(Kit.hspacer())
		if not comp.is_empty() and String(comp[i]["delta_text"]) != "":
			var good := int(comp[i]["delta"]) > 0
			h.add_child(Kit.lbl(String(comp[i]["delta_text"]), 14, Kit.GREEN if good else Kit.BAD, false, "title"))
		h.add_child(Kit.lbl(String(row["text"]), 17, AF.TEXT, false, "title"))
		box.add_child(h)
		box.add_child(AF.separator())
	if String(d["flavour"]) != "":
		_detail.add_child(Kit.spacer(2))
		_detail.add_child(Kit.lbl(String(d["flavour"]), 15, AF.TEXT_DIM, true, "italic"))
	if _status != "":
		_detail.add_child(Kit.spacer(2))
		_detail.add_child(Kit.lbl(_status, 15, Kit.GREEN, true))


static func Crafting_name(id: String) -> String:
	return MD.Crafting.item_name(id)


# --------------------------------------------------------------------- actions ----

func _abs_hours() -> float:
	return WorldSim.day * 24.0 + WorldSim.time_of_day


func do_equip() -> void:
	if _sel.is_empty() or not MD.Equipment.is_equippable(String(_sel["id"])):
		return
	_status = String(Life.equipment.call("equip_from", Life, String(_sel["id"]), int(_sel["quality"])))
	Audio.play_ui("pickup")
	refresh()
	menu.call("notify_changed", "equipment")


func do_use() -> void:
	if _sel.is_empty():
		return
	var d := MD.item_detail(String(_sel["id"]), int(_sel["quality"]))
	if not bool(d["usable"]):
		return
	_status = String(Life.equipment.call("consume", Life, String(_sel["id"]), _abs_hours()))
	Audio.play_ui("pickup")
	refresh()


## Drops one of the selected stack (it is gone; there is no ground loot yet).
func do_drop() -> void:
	if _sel.is_empty():
		return
	var id := String(_sel["id"])
	var q := int(_sel["quality"])
	var done := false
	if MD.Equipment.is_equippable(id):
		for it: Object in Life.inventory.get_items_with_prototype_id(id):
			if MD.Equipment.quality_of(it) == q:
				if it.get_stack_size() > 1:
					it.set_stack_size(it.get_stack_size() - 1)
				else:
					Life.inventory.remove_item(it)
				done = true
				Life.inventory_changed.emit()
				break
	else:
		done = Life.take(id, 1)
	_status = ("You drop the %s." % MD.Crafting.item_name(id)) if done else ""
	refresh()


func do_compare() -> void:
	if _sel.is_empty() or not MD.Equipment.is_equippable(String(_sel["id"])):
		return
	_compare = not _compare
	_show_detail()
	hints_changed()


func hints() -> Array:
	var has := not _sel.is_empty()
	var gear := has and MD.Equipment.is_equippable(String(_sel["id"]))
	var usable := has and bool(MD.item_detail(String(_sel["id"]), int(_sel["quality"]))["usable"])
	return [["F", "Equip", do_equip, not gear], ["G", "Drop", do_drop, not has],
		["V", "Compare" if not _compare else "Compare: on", do_compare, not gear], ["U", "Use", do_use, not usable]]


func handle_key(e: InputEventKey) -> bool:
	match e.keycode:
		KEY_F, KEY_ENTER, KEY_KP_ENTER:
			do_equip()
		KEY_G:
			do_drop()
		KEY_V:
			do_compare()
		KEY_U:
			do_use()
		KEY_LEFT:
			_move(-1)
		KEY_RIGHT:
			_move(1)
		KEY_UP:
			_move(-_cols)
		KEY_DOWN:
			_move(_cols)
		_:
			return false
	return true


func _move(step: int) -> void:
	if _shown.is_empty():
		return
	var i := 0
	for k in _shown.size():
		if not _sel.is_empty() and _shown[k]["id"] == _sel["id"] and int(_shown[k]["quality"]) == int(_sel["quality"]):
			i = k
	i = clampi(i + step, 0, _shown.size() - 1)
	_select(String(_shown[i]["id"]), int(_shown[i]["quality"]))
