extends Control
## "Nobility": every noble house of Caldrenn, its sigil, head, holdings, a
## wealth and influence bar, your standing with it and any feud it's in.
## Reached from the Pack menu (village_services.gd pack_menu()). Pauses the
## game while open, like CareerScreen and CraftingScreen.
##
## Reads Life.nobility defensively: until autoload/life.gd owns one (see the
## hook lines in the PR notes), this screen builds its own scripts/sim/
## nobility.gd instance so it still shows something sensible.

const RANobility := preload("res://scripts/sim/nobility.gd")
const SELF_PATH := "res://scripts/ui/nobility_screen.gd"

var _was_paused := false
var _box: VBoxContainer
var _own_nobility: RANobility


static func open_for(hud: CanvasLayer) -> Control:
	var s: Control = hud.get_node_or_null("NobilityScreen")
	if s == null:
		s = (load(SELF_PATH) as GDScript).new()
		s.name = "NobilityScreen"
		hud.add_child(s)
	if hud.has_method("close_menu"):
		hud.call("close_menu")
	s.call("open")
	return s


func _nobility() -> RANobility:
	var n: Object = Life.get("nobility")
	if n != null:
		return n as RANobility
	if _own_nobility == null:
		_own_nobility = RANobility.new()
	return _own_nobility


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
	head.text = "Nobility"
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
	content.add_theme_constant_override("separation", 18)
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
	# (full-rect anchors from _ready already size this root; assigning size warned)
	var panel: Control = get_child(1)
	var w := clampf(vw.x * 0.94, 320.0, 820.0)
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
	var nob := _nobility()
	for h: Dictionary in nob.houses:
		content.add_child(_house_card(nob, h))
	var feuds := nob.feuds()
	content.add_child(_heading("Feuds"))
	if feuds.is_empty():
		content.add_child(_body("No open feuds among the great houses, for now."))
	else:
		for f: Dictionary in feuds:
			content.add_child(_body("%s vs %s — over %s (since day %d)." %
				[nob.house_name(String(f["house_a"])), nob.house_name(String(f["house_b"])), String(f["cause"]), int(f["since_day"])]))
	content.add_child(_heading("Word around the realm"))
	var rumours := nob.rumours()
	if rumours.is_empty():
		content.add_child(_body("Nothing worth repeating."))
	else:
		for r: String in rumours:
			content.add_child(_body("• " + r))


func _house_card(nob: RANobility, h: Dictionary) -> PanelContainer:
	var hid := String(h["id"])
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UITheme.panel_box())
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	card.add_child(col)
	var title := HBoxContainer.new()
	col.add_child(title)
	var sigil := ColorRect.new()
	sigil.color = Color(String(h.get("sigil_color", "#888888")))
	sigil.custom_minimum_size = Vector2(18, 18)
	title.add_child(sigil)
	var name_label := Label.new()
	name_label.text = "  %s" % String(h["name"])
	name_label.add_theme_font_override("font", UITheme.title_font_weight(600))
	name_label.add_theme_font_size_override("font_size", 18)
	name_label.add_theme_color_override("font_color", UITheme.TEXT)
	title.add_child(name_label)
	var head_info: Dictionary = h.get("head", {})
	var title_word := "Lady" if String(head_info.get("gender", "male")) == "female" else "Lord"
	col.add_child(_body("%s %s, head of the house." % [title_word, String(head_info.get("name", "?"))]))
	var holdings := nob.holdings_of(hid)
	var parts := PackedStringArray()
	var settlements: Array = holdings.get("settlements", [])
	if not settlements.is_empty():
		var names := PackedStringArray()
		for idx: int in settlements:
			names.append(WorldGen.display_name(String(WorldGen.settlements[idx]["name"])))
		parts.append("fiefs: " + ", ".join(names))
	if not (holdings.get("mills", []) as Array).is_empty():
		parts.append("%d mill(s)" % (holdings["mills"] as Array).size())
	if not (holdings.get("bridges", []) as Array).is_empty():
		parts.append("%d bridge(s)" % (holdings["bridges"] as Array).size())
	if bool(holdings.get("forest", false)):
		parts.append("a forest")
	if bool(holdings.get("mine", false)):
		parts.append("the mine")
	if not (holdings.get("fishing", []) as Array).is_empty():
		parts.append("fishing rights")
	col.add_child(_body("Holdings: %s" % (", ".join(parts) if not parts.is_empty() else "none, for now")))
	col.add_child(_bar_row("Wealth", clampf(float(nob.wealth.get(hid, 0)) / 10000.0, 0.0, 1.0), UITheme.ACCENT))
	col.add_child(_bar_row("Influence", clampf(float(nob.influence.get(hid, 0.0)) / 100.0, 0.0, 1.0), UITheme.ACCENT_2))
	var op := nob.opinion(hid)
	var standing := "Hostile" if op <= RANobility.HOSTILE_OPINION else ("Friendly" if op >= RANobility.SPONSOR_OPINION else "Neutral")
	col.add_child(_body("Your standing: %s (%d)" % [standing, int(round(op))]))
	if nob.is_struggling(hid):
		col.add_child(_body("Struggling — might sell a holding."))
	return card


func _bar_row(label_text: String, frac: float, color: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var l := Label.new()
	l.text = label_text
	l.custom_minimum_size = Vector2(70, 0)
	l.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	row.add_child(l)
	var b := ProgressBar.new()
	b.show_percentage = false
	b.min_value = 0.0
	b.max_value = 1.0
	b.value = frac
	b.custom_minimum_size = Vector2(140, 10)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.add_theme_stylebox_override("fill", UITheme.bar_fill(color))
	row.add_child(b)
	return row


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
