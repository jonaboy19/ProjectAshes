extends Control
## "Farm Ledger": crops and days to harvest, hired hands and their wages,
## farm storage (with a Sell button per item) and the estate's level. Reached
## from the Pack menu (village_services.gd pack_menu()) or the build menu's
## ledger button while on a homestead plot. Pauses the game while open, the
## same as CareerScreen and CraftingScreen.
##
##   FarmLedger.open_for(hud)

const Homestead := preload("res://scripts/sim/homestead.gd")
const SELF_PATH := "res://scripts/ui/farm_ledger.gd"

var _was_paused := false
var _box: VBoxContainer


## Loads via SELF_PATH so this compiles fine the moment the file exists.
static func open_for(hud: CanvasLayer) -> Control:
	var s: Control = hud.get_node_or_null("FarmLedger")
	if s == null:
		s = (load(SELF_PATH) as GDScript).new()
		s.name = "FarmLedger"
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
	add_child(panel)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 10)
	panel.add_child(_box)
	var head := Label.new()
	head.text = "Farm Ledger"
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
	var w := clampf(vw.x * 0.94, 320.0, 760.0)
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

func _refresh() -> void:
	var content: VBoxContainer = _content()
	for c in content.get_children():
		c.queue_free()
	var hs := Life.homestead
	var plots_worked := PackedInt32Array()
	for i in hs.plots().size():
		if hs.owns_or_leases(i):
			plots_worked.append(i)
	if plots_worked.is_empty():
		content.add_child(_heading("No land yet"))
		content.add_child(_body("Buy or lease a homestead plot outside Ashford to start farming."))
		return
	content.add_child(_heading("Estate"))
	content.add_child(_body("%s  ·  %d plot%s worked  ·  %d hand%s" % [hs.estate_level_name(),
		plots_worked.size(), "" if plots_worked.size() == 1 else "s",
		hs.workers.size(), "" if hs.workers.size() == 1 else "s"]))
	content.add_child(_heading("Fields"))
	var any_crop := false
	for plot: int in plots_worked:
		var tag := " (leased)" if hs.is_leased(plot) else ""
		for cr: Dictionary in hs.crops:
			if int(cr["plot"]) != plot or String(cr.get("crop", "")) == "":
				continue
			any_crop = true
			var pct := int(round(hs.growth_stage(cr) * 100.0))
			var line := "%s%s — %s: %d%%" % [hs.plot_name(plot), tag, Life.item_name(String(cr["crop"])), pct]
			if pct >= 100:
				line += "  (ready)"
			content.add_child(_body(line))
	if not any_crop:
		content.add_child(_body("Nothing planted. Till a crop plot at the build menu and plant something in season."))
	content.add_child(_heading("Hands"))
	if hs.workers.is_empty():
		content.add_child(_body("No hired hands. Hire some from the build menu once you own or lease a plot."))
	else:
		for w: Dictionary in hs.workers:
			var unpaid := int(w.get("unpaid_days", 0))
			var warn := "  (unpaid %d day%s)" % [unpaid, "" if unpaid == 1 else "s"] if unpaid > 0 else ""
			content.add_child(_row(
				"%s — %d gold/day%s" % [String(w["name"]), int(w["wage"]), warn],
				"Let go", fire_worker.bind(int(w["uid"]))))
	content.add_child(_heading("Storage  (%d / %d)" % [hs.storage_used(), hs.storage_cap()]))
	if hs.storage.is_empty():
		content.add_child(_body("Empty. Hired hands harvest ready crops here automatically."))
	else:
		for item: String in hs.storage:
			var n := int(hs.storage[item])
			if n <= 0:
				continue
			content.add_child(_row("%d %s" % [n, Life.item_name(item)], "Sell all", sell_item.bind(item)))


func fire_worker(uid: int) -> void:
	Game.say(Life.homestead.fire(uid))
	_refresh()


func sell_item(item: String) -> void:
	var hs := Life.homestead
	var r: Dictionary = hs.sell_storage(item, int(hs.storage.get(item, 0)))
	if int(r.get("sold", 0)) > 0:
		Game.say("Sold %d %s for %d gold." % [int(r["sold"]), Life.item_name(item), int(r["gold"])])
	else:
		Game.say("The merchant can't afford it today.")
	_refresh()


func _content() -> VBoxContainer:
	return _box.get_child(2).get_child(0)   # ScrollContainer -> Content


func _row(text: String, button_text: String, cb: Callable) -> HBoxContainer:
	var h := HBoxContainer.new()
	var l := _body(text)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	var b := Button.new()
	b.text = button_text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	h.add_child(b)
	return h


func _heading(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_override("font", UITheme.title_font_weight(600))
	l.add_theme_font_size_override("font_size", 19)
	l.add_theme_color_override("font_color", UITheme.ACCENT_2)
	return l


func _body(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", UITheme.TEXT)
	return l
