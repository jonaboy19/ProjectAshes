extends Control
## A merchant's wares: what one shop (data/items/shops.json) stocks at this settlement's tier, with category
## tabs, an item detail card, and Buy / Sell against a market (scripts/sim/market.gd). Sells and buys through
## the market, so prices move with stock, the merchant's purse can run dry, and the shelves restock with the day tick.
##
## Opened from a merchant's menu in village_services.gd:
##   opts.append(ShopScreen.menu_option(hud, "blacksmith", Life.market, 1, "Browse the forge's wares"))
## or ShopScreen.open_for(hud, "alchemist", market, tier, "Alchemist"). Pauses the game while open.

signal closed

const ItemsDB := preload("res://scripts/sim/items_db.gd")
const MD := preload("res://scripts/ui/gamemenu/menu_data.gd")
const SELF_PATH := "res://scripts/ui/shop_screen.gd"
const CATS := [["all", "All"], ["weapons", "Weapons"], ["armor", "Armour"], ["consumables", "Goods"], ["materials", "Materials"], ["tools", "Tools"], ["misc", "Other"]]

var shop_id := ""
var market: Object = null
var tier := 1
var title_text := ""
var _selling := false
var _cat := "all"
var _sel := ""
var _was_paused := false
var _status := ""

var _title: Label
var _gold: Label
var _purse: Label
var _tabs: HBoxContainer
var _mode_buy: Button
var _mode_sell: Button
var _list: VBoxContainer
var _detail: VBoxContainer
var _buy_btn: Button
var _msg: Label
var _panel: PanelContainer


## Opens (creating on first use) as a child of `host`. `market` is an RAMarket (Life.market or economy.markets[id]).
static func open_for(host: Node, shop: String, m: Object, shop_tier := 1, title := "") -> Control:
	var s: Control = host.get_node_or_null("ShopScreen")
	if s == null:
		s = (load(SELF_PATH) as GDScript).new()
		s.name = "ShopScreen"
		host.add_child(s)
	if host.has_method("close_menu"):
		host.call("close_menu")
	s.call("open", shop, m, shop_tier, title)
	return s


## A show_menu() option that opens the shop.
static func menu_option(host: Node, shop: String, m: Object, shop_tier := 1, label := "Browse wares", title := "") -> Array:
	return [label, func() -> String:
		open_for(host, shop, m, shop_tier, title)
		return ""]


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UITheme.theme()
	visible = false
	_build()
	if Engine.has_singleton("Life") or get_node_or_null("/root/Life") != null:
		Life.inventory_changed.connect(func() -> void:
			if visible:
				refresh())
	get_viewport().size_changed.connect(_layout)


func open(shop: String, m: Object, shop_tier := 1, title := "") -> void:
	shop_id = shop
	market = m
	tier = shop_tier
	title_text = title if title != "" else String(ItemsDB.shop(shop).get("name", shop.capitalize()))
	_selling = false
	_cat = "all"
	_sel = ""
	_status = ""
	if not visible:
		_was_paused = get_tree().paused
		get_tree().paused = true
		visible = true
		if get_node_or_null("/root/Audio") != null:
			Audio.play_ui("open")
	_layout()
	refresh()


func close_screen() -> void:
	if not visible:
		return
	visible = false
	get_tree().paused = _was_paused
	if get_node_or_null("/root/Audio") != null:
		Audio.play_ui("close")
	closed.emit()


func _unhandled_input(e: InputEvent) -> void:
	if visible and (e.is_action_pressed("ui_cancel") or e.is_action_pressed("journal")):
		get_viewport().set_input_as_handled()
		close_screen()


# --- building --------------------------------------------------------------------------------------------------------

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UITheme.panel_box())
	add_child(_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	_panel.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	col.add_child(head)
	_title = Label.new()
	_title.add_theme_font_override("font", UITheme.title_font())
	_title.add_theme_font_size_override("font_size", 26)
	_title.add_theme_color_override("font_color", UITheme.ACCENT)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	_gold = Label.new()
	_gold.add_theme_color_override("font_color", UITheme.ACCENT)
	head.add_child(_gold)
	_purse = Label.new()
	_purse.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	head.add_child(_purse)
	var modes := HBoxContainer.new()
	modes.add_theme_constant_override("separation", 6)
	col.add_child(modes)
	_mode_buy = _mode_button("Buy", false)
	_mode_sell = _mode_button("Sell", true)
	modes.add_child(_mode_buy)
	modes.add_child(_mode_sell)
	var tabs_scroll := ScrollContainer.new()
	tabs_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs_scroll.custom_minimum_size.y = 46
	col.add_child(tabs_scroll)
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 6)
	tabs_scroll.add_child(_tabs)
	for c: Array in CATS:
		var b := Button.new()
		b.text = String(c[1])
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func() -> void:
			_cat = String(c[0])
			_sel = ""
			refresh())
		b.set_meta("cat", String(c[0]))
		_tabs.add_child(b)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	col.add_child(body)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.scroll_deadzone = 12
	body.add_child(scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	var dpanel := PanelContainer.new()
	dpanel.custom_minimum_size.x = 250
	dpanel.size_flags_horizontal = Control.SIZE_FILL
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0, 0, 0, 0.3)
	box.border_color = UITheme.STROKE
	box.set_border_width_all(1)
	box.set_corner_radius_all(10)
	box.set_content_margin_all(12)
	dpanel.add_theme_stylebox_override("panel", box)
	body.add_child(dpanel)
	var dcol := VBoxContainer.new()
	dcol.add_theme_constant_override("separation", 8)
	dpanel.add_child(dcol)
	_detail = VBoxContainer.new()
	_detail.add_theme_constant_override("separation", 6)
	_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dcol.add_child(_detail)
	_buy_btn = Button.new()
	_buy_btn.custom_minimum_size.y = 50
	_buy_btn.pressed.connect(_transact)
	dcol.add_child(_buy_btn)
	_msg = Label.new()
	_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_msg.add_theme_color_override("font_color", UITheme.OK)
	col.add_child(_msg)
	var close := Button.new()
	close.text = "Close"
	close.custom_minimum_size.y = 50
	close.pressed.connect(close_screen)
	col.add_child(close)


func _mode_button(text: String, sell: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(110, 40)
	b.pressed.connect(func() -> void:
		_selling = sell
		_sel = ""
		_status = ""
		refresh())
	return b


func _layout() -> void:
	if _panel == null:
		return
	var vw := get_viewport().get_visible_rect().size
	# (full-rect anchors from _ready already size this root; assigning size warned)
	var w := clampf(vw.x * 0.96, 320.0, 980.0)
	var h := vw.y * 0.94
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = -w * 0.5
	_panel.offset_right = w * 0.5
	_panel.offset_top = -h * 0.5
	_panel.offset_bottom = h * 0.5
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH


# --- content ------------------------------------------------------------------------------------------------------------

## [{id, price, stock, count}] for the current mode and category.
func rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if market == null:
		return out
	if not _selling:
		var seen := {}
		for g: Dictionary in ItemsDB.shop_goods(shop_id, tier):
			var id := String(g["item"])
			if seen.has(id) or not (market.get("base_price") as Dictionary).has(id):
				continue
			seen[id] = true
			if _cat != "all" and MD.category_of(id) != _cat and not (_cat == "misc" and ["quest", "misc"].has(MD.category_of(id))):
				continue
			out.append({"id": id, "price": int(market.call("price", id)), "stock": int((market.get("stock") as Dictionary).get(id, 0)), "count": 0})
	else:
		for s: Dictionary in MD.stacks():
			var id2 := String(s["id"])
			if _cat != "all" and MD.category_of(id2) != _cat and not (_cat == "misc" and ["quest", "misc"].has(MD.category_of(id2))):
				continue
			if MD.category_of(id2) == "quest":
				continue
			out.append({"id": id2, "price": maxi(1, int(round(float(market.call("sell_price", id2)) * (float(MD.Crafting.QUALITY_MULT[clampi(int(s["quality"]), 0, 2)]) if MD.Equipment.is_equippable(id2) else 1.0)))),
				"stock": 0, "count": int(s["count"]), "quality": int(s["quality"])})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var la := int(ItemsDB.info(String(a["id"])).get("level", 1))
		var lb := int(ItemsDB.info(String(b["id"])).get("level", 1))
		if la != lb:
			return la < lb
		return String(a["id"]) < String(b["id"]))
	return out


func refresh() -> void:
	_title.text = title_text
	_gold.text = "You: %d g" % int(Game.gold) if get_node_or_null("/root/Game") != null else ""
	_purse.text = ("   Purse: %d g" % int(market.get("purse"))) if market != null else ""
	_mode_buy.button_pressed = not _selling
	_mode_sell.button_pressed = _selling
	for b in _tabs.get_children():
		(b as Button).button_pressed = String(b.get_meta("cat")) == _cat
	for c in _list.get_children():
		c.queue_free()
	var rs := rows()
	if rs.is_empty():
		var l := Label.new()
		l.text = "Nothing here." if not _selling else "You have nothing this merchant wants."
		l.add_theme_color_override("font_color", UITheme.TEXT_DIM)
		_list.add_child(l)
	var picked := false
	for r: Dictionary in rs:
		_list.add_child(_row(r))
		if String(r["id"]) == _sel:
			picked = true
	if not picked:
		_sel = String(rs[0]["id"]) if not rs.is_empty() else ""
	_show_detail()
	_msg.text = _status


func _row(r: Dictionary) -> Control:
	var id := String(r["id"])
	var b := Button.new()
	b.toggle_mode = false
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 58)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var sb := StyleBoxFlat.new()
	var sel := id == _sel
	sb.bg_color = Color(1, 1, 1, 0.12) if sel else Color(1, 1, 1, 0.05)
	sb.border_color = UITheme.ACCENT if sel else Color(1, 1, 1, 0.08)
	sb.set_border_width_all(2 if sel else 1)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(6)
	for st in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(st, sb)
	b.pressed.connect(func() -> void:
		_sel = id
		_status = ""
		refresh())
	var h := HBoxContainer.new()
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.add_theme_constant_override("separation", 10)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(h)
	var tex := TextureRect.new()
	tex.texture = UITheme.icon("items/" + id)
	tex.custom_minimum_size = Vector2(44, 44)
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(tex)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(vb)
	var q := int(r.get("quality", 1))
	var name := Label.new()
	name.text = MD.Crafting.item_name(id) + ((" (%s)" % MD.Crafting.quality_name(q).to_lower()) if q != 1 and MD.Equipment.is_equippable(id) else "")
	name.add_theme_color_override("font_color", MD.rarity_color(MD.rarity_of(id, q)))
	name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(name)
	var sub := Label.new()
	sub.text = ItemsDB.stat_line(id)
	sub.add_theme_font_size_override("font_size", 13)
	sub.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(sub)
	var price := Label.new()
	price.text = "%d g" % int(r["price"])
	price.add_theme_color_override("font_color", UITheme.ACCENT)
	price.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(price)
	var cnt := Label.new()
	cnt.custom_minimum_size.x = 56
	cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cnt.text = ("×%d" % int(r["stock"])) if not _selling else ("×%d" % int(r["count"]))
	cnt.add_theme_color_override("font_color", UITheme.DANGER if (not _selling and int(r["stock"]) <= 0) else UITheme.TEXT_DIM)
	cnt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(cnt)
	return b


func _show_detail() -> void:
	for c in _detail.get_children():
		c.queue_free()
	if _sel == "":
		_buy_btn.visible = false
		return
	_buy_btn.visible = true
	var d := MD.item_detail(_sel, 1)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	_detail.add_child(head)
	var tex := TextureRect.new()
	tex.texture = UITheme.icon("items/" + _sel)
	tex.custom_minimum_size = Vector2(64, 64)
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	head.add_child(tex)
	var nm := Label.new()
	nm.text = String(d["name"])
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.add_theme_font_override("font", UITheme.title_font_weight(600))
	nm.add_theme_font_size_override("font_size", 19)
	nm.add_theme_color_override("font_color", d["rarity_color"])
	head.add_child(nm)
	var meta := Label.new()
	meta.text = "%s  ·  %s" % [d["rarity_name"], d["type"]]
	meta.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	_detail.add_child(meta)
	for row: Dictionary in d["rows"]:
		var l := Label.new()
		l.text = "%s:  %s" % [row["label"], row["text"]]
		l.add_theme_font_size_override("font_size", 14)
		l.add_theme_color_override("font_color", UITheme.TEXT)
		_detail.add_child(l)
	var fl := Label.new()
	fl.text = String(d["flavour"])
	fl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fl.add_theme_font_size_override("font_size", 13)
	fl.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	_detail.add_child(fl)
	var price := _price_of(_sel)
	if _selling:
		_buy_btn.text = "Sell for %d g" % price
		_buy_btn.disabled = int(Life.count(_sel)) <= 0 or int(market.get("purse")) < price
	else:
		_buy_btn.text = "Buy for %d g" % price
		_buy_btn.disabled = String(market.call("can_buy", _sel, Game.gold)) != ""


func _price_of(id: String) -> int:
	return int(market.call("sell_price", id)) if _selling else int(market.call("price", id))


func _transact() -> void:
	if _sel == "" or market == null:
		return
	if _selling:
		var got := int(market.call("sell", _sel))
		if got < 0:
			_status = "The merchant can't afford it today."
		elif not bool(Life.take(_sel, 1)):
			_status = "You have no %s." % MD.Crafting.item_name(_sel)
		else:
			Game.add_gold(got)
			Life.record("traded", 0.5)
			_status = "Sold %s for %d gold." % [MD.Crafting.item_name(_sel), got]
	else:
		var why := String(market.call("can_buy", _sel, Game.gold))
		if why != "":
			_status = why
		else:
			var paid := int(market.call("buy", _sel, Game.gold))
			Game.add_gold(-paid)
			Life.give(_sel, 1)
			Life.record("traded", 0.3)
			_status = "Bought %s for %d gold." % [MD.Crafting.item_name(_sel), paid]
	if get_node_or_null("/root/Audio") != null:
		Audio.play_ui("pickup")
	refresh()
