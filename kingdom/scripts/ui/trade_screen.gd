extends Control
## "Trade": the merchant career's screen, reached from the trader menu
## (village_services.gd merchant_menu() -- see the hook line noted there).
## Shows the local market with rising/falling price arrows, the player's own
## cargo, buy/sell, known prices elsewhere (visited or heard by rumour, with a
## date stamp), caravans in transit and contract offers. Pauses the game like
## CraftingScreen and the career screen.
##
## Reads Life defensively (Life.get("economy")) so the screen shows a plain
## placeholder instead of erroring until autoload/life.gd exposes `economy`
## (RAEconomy) -- see the hook lines noted in scripts/sim/economy.gd's docstring.

const SELF_PATH := "res://scripts/ui/trade_screen.gd"
const HOME_ID := 0     # WorldGen.settlements[0] = Ashford, Life.market

var _was_paused := false
var _box: VBoxContainer
var _last_prices: Dictionary = {}     # item -> price last refresh, for the arrows


static func open_for(hud: CanvasLayer) -> Control:
	var s: Control = hud.get_node_or_null("TradeScreen")
	if s == null:
		s = (load(SELF_PATH) as GDScript).new()
		s.name = "TradeScreen"
		hud.add_child(s)
	if hud.has_method("close_menu"):
		hud.call("close_menu")
	s.call("open")
	return s


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UITheme.theme()
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_stylebox_override("panel", UITheme.panel_box())
	add_child(panel)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 10)
	panel.add_child(_box)
	var head := Label.new()
	head.text = "Trade"
	head.add_theme_font_override("font", UITheme.title_font())
	head.add_theme_font_size_override("font_size", 26)
	head.add_theme_color_override("font_color", UITheme.ACCENT)
	_box.add_child(head)
	var rule := ColorRect.new()
	rule.color = UITheme.ACCENT
	rule.custom_minimum_size = Vector2(56, 2)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_box.add_child(rule)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_box.add_child(scroll)
	var content := VBoxContainer.new()
	content.name = "Content"
	content.add_theme_constant_override("separation", 16)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	var close := Button.new()
	close.text = "Close"
	close.custom_minimum_size = Vector2(0, 50)
	close.pressed.connect(close_screen)
	_box.add_child(close)
	get_viewport().size_changed.connect(_layout)
	_layout()


func open() -> void:
	if not visible:
		_was_paused = get_tree().paused
		get_tree().paused = true
		visible = true
		Audio.play_ui("open")
	var eco: Object = Life.get("economy")
	if eco != null:
		eco.call("learn_prices", HOME_ID, float(WorldSim.day) + WorldSim.time_of_day / 24.0)
	_refresh()


func close_screen() -> void:
	if not visible:
		return
	visible = false
	get_tree().paused = _was_paused
	Audio.play_ui("close")


func _unhandled_input(e: InputEvent) -> void:
	if not visible:
		return
	if e.is_action_pressed("ui_cancel") or e.is_action_pressed("journal"):
		get_viewport().set_input_as_handled()
		close_screen()


func _layout() -> void:
	var vw := get_viewport().get_visible_rect().size
	position = Vector2.ZERO
	size = vw
	var panel: Control = get_child(1)
	var w := clampf(vw.x * 0.96, 320.0, 820.0)
	var h := vw.y * 0.92
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -w * 0.5
	panel.offset_right = w * 0.5
	panel.offset_top = -h * 0.5
	panel.offset_bottom = h * 0.5
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH


# --- content ------------------------------------------------------------------------

func _content() -> VBoxContainer:
	return _box.get_child(2).get_child(0)   # ScrollContainer -> Content


func _refresh() -> void:
	var content := _content()
	for c in content.get_children():
		c.queue_free()
	var eco: Object = Life.get("economy")
	if eco == null:
		content.add_child(_heading("The roads are quiet"))
		content.add_child(_body("No regional trade to speak of yet."))
		return
	content.add_child(_heading("%s Market" % String(WorldGen.settlements[HOME_ID]["name"])))
	_local_market_rows(content, eco)
	content.add_child(_heading("Your Cargo"))
	_cargo_rows(content, eco)
	content.add_child(_heading("Known Prices Elsewhere"))
	_known_rows(content, eco)
	content.add_child(_heading("Caravans"))
	_caravan_rows(content, eco)
	content.add_child(_heading("Contracts"))
	_contract_rows(content, eco)
	content.add_child(_heading("Merchant Life"))
	content.add_child(_body("Cart: %s   Caravan: %s   Shop: %s   Lifetime trade: %d gold" % [
		"Yes" if bool(eco.get("owns_cart")) else "No", "Yes" if bool(eco.get("owns_caravan")) else "No",
		"Yes" if bool(eco.get("has_shop")) else "No", int(eco.get("trade_volume"))]))


func _local_market_rows(content: VBoxContainer, eco: Object) -> void:
	var m: Object = (eco.get("markets") as Dictionary).get(HOME_ID)
	if m == null:
		content.add_child(_body("Nothing for sale here."))
		return
	for item: String in (m.get("base_price") as Dictionary):
		var p := int(m.call("price", item))
		var arrow := _arrow(item, p)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.add_child(_body("%s  %s  %dg  (%d in stock)" % [_label(item), arrow, p, int((m.get("stock") as Dictionary).get(item, 0))]))
		var buy := Button.new()
		buy.text = "Buy"
		buy.disabled = String(m.call("can_buy", item, Game.gold)) != ""
		buy.pressed.connect(func() -> void:
			_buy_local(eco, item)
			_refresh())
		row.add_child(buy)
		content.add_child(row)


## Mirrors Life.buy()'s gold/inventory side effects for the home settlement's
## market (economy.buy() only moves the market's own stock/purse), so buying
## from this screen behaves exactly like the existing merchant_menu button.
func _buy_local(eco: Object, item: String) -> void:
	var m: Object = (eco.get("markets") as Dictionary).get(HOME_ID)
	if String(m.call("can_buy", item, Game.gold)) != "":
		return
	var paid := int(eco.call("buy", HOME_ID, item, Game.gold))
	if paid >= 0:
		Game.add_gold(-paid)
		Life.give(item)


func _sell_local(eco: Object, item: String) -> void:
	if int(Life.count(item)) <= 0:
		return
	var got := int(eco.call("sell", HOME_ID, item))
	if got < 0:
		return
	Life.take(item)
	Game.add_gold(got)


func _cargo_rows(content: VBoxContainer, eco: Object) -> void:
	var m: Object = (eco.get("markets") as Dictionary).get(HOME_ID)
	var any := false
	if m != null:
		for item: String in (m.get("base_price") as Dictionary):
			var n := int(Life.count(item))
			if n <= 0:
				continue
			any = true
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 10)
			row.add_child(_body("%s ×%d  —  %dg each" % [_label(item), n, int(m.call("sell_price", item))]))
			var sell := Button.new()
			sell.text = "Sell"
			sell.pressed.connect(func() -> void:
				_sell_local(eco, item)
				_refresh())
			row.add_child(sell)
			content.add_child(row)
	if not any:
		content.add_child(_body("Nothing worth selling here."))


func _known_rows(content: VBoxContainer, eco: Object) -> void:
	var known: Dictionary = eco.get("known_prices")
	if known.is_empty():
		content.add_child(_body("Visit other towns, or listen for rumours, to learn their prices."))
		return
	for id in known:
		if int(id) == HOME_ID:
			continue
		var name := String(WorldGen.settlements[int(id)]["name"]) if int(id) < WorldGen.settlements.size() else "?"
		content.add_child(_sub_label(name))
		for item: String in (known[id] as Dictionary):
			var e: Dictionary = known[id][item]
			var day := float(e.get("day", 0.0))
			content.add_child(_body("  %s — %dg (as of day %d)" % [_label(item), int(e.get("price", 0)), int(day)]))


func _caravan_rows(content: VBoxContainer, eco: Object) -> void:
	var car: Object = eco.get("caravans")
	var list: Array = car.call("in_transit") if car != null else []
	if list.is_empty():
		content.add_child(_body("No caravans on the road."))
		return
	for c: Dictionary in list:
		var to := String(WorldGen.settlements[int(c["to"])]["name"]) if int(c["to"]) < WorldGen.settlements.size() else "?"
		var eta := maxf(0.0, float(c["arrive"]) - (float(WorldSim.day) * 24.0 + WorldSim.time_of_day))
		content.add_child(_body("To %s — %d guard%s, %d hour%s out." % [to, int(c["guards"]),
			"" if int(c["guards"]) == 1 else "s", int(ceil(eta)), "" if int(ceil(eta)) == 1 else "s"]))


func _contract_rows(content: VBoxContainer, eco: Object) -> void:
	var contracts: Array = eco.get("contracts")
	if contracts.is_empty():
		content.add_child(_body("No delivery offers right now."))
		return
	for c: Dictionary in contracts:
		var to := String(WorldGen.settlements[int(c["to"])]["name"]) if int(c["to"]) < WorldGen.settlements.size() else "?"
		content.add_child(_body("Deliver %d %s to %s by day %d for %d gold (%d/%d delivered)." % [
			int(c["amount"]), _label(String(c["item"])), to, int(c["due_day"]), int(c["reward"]),
			int(c["filled"]), int(c["amount"])]))


func _arrow(item: String, p: int) -> String:
	var was: int = int(_last_prices.get(item, p))
	_last_prices[item] = p
	if p > was:
		return "^"
	if p < was:
		return "v"
	return "-"


func _label(item: String) -> String:
	return Life.item_name(item) if Life.item_prop(item, "name", "") != "" else item.replace("_", " ").capitalize()


func _heading(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_override("font", UITheme.title_font_weight(600))
	l.add_theme_font_size_override("font_size", 19)
	l.add_theme_color_override("font_color", UITheme.ACCENT_2)
	return l


func _sub_label(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_color_override("font_color", UITheme.ACCENT_2)
	return l


func _body(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", UITheme.TEXT)
	return l
