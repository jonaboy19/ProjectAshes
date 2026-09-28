extends Control
## "Family": the player's own family tree (parents, spouse, children,
## siblings-in-law via the spouse's side is out of scope for now), courtship
## status and its actions. Reached from the Pack menu (village_services.gd
## pack_menu()). Pauses the game while open, like NobilityScreen/CareerScreen.
##
## Reads Life.get("family") defensively: until autoload/life.gd owns one (see
## the hook lines in the PR notes), this screen builds its own scripts/sim/
## family.gd instance so it still shows something sensible.

const RAFamily := preload("res://scripts/sim/family.gd")
const SELF_PATH := "res://scripts/ui/family_screen.gd"

var _was_paused := false
var _box: VBoxContainer
var _own_family: RAFamily


static func open_for(hud: CanvasLayer) -> Control:
	var s: Control = hud.get_node_or_null("FamilyScreen")
	if s == null:
		s = (load(SELF_PATH) as GDScript).new()
		s.name = "FamilyScreen"
		hud.add_child(s)
	if hud.has_method("close_menu"):
		hud.call("close_menu")
	s.call("open")
	return s


func _family() -> RAFamily:
	var f: Object = Life.get("family")
	if f != null:
		return f as RAFamily
	if _own_family == null:
		_own_family = RAFamily.new()
	return _own_family


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
	head.text = "Family"
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
	var fam := _family()
	content.add_child(_heading("Parents"))
	for p: Dictionary in Life.life_path.parents:
		var role := String(p["role"])
		var alive := fam.parent_alive(role)
		var age := fam.parent_age(role)
		var line := "%s (%s), age %d" % [String(p["name"]), role.capitalize(), age]
		content.add_child(_body(line + ("." if alive else " — passed away.")))
	content.add_child(_heading("Spouse"))
	if fam.is_married():
		var sp: Dictionary = fam.spouse
		content.add_child(_body("%s, %s, age %d. Opinion of you: %d." %
			[String(sp["name"]), String(sp.get("occupation", "villager")).capitalize(), fam.spouse_age(), int(sp.get("opinion", 0))]))
	else:
		content.add_child(_body("Not married."))
		content.add_child(_heading("Courtship"))
		if fam.courtships.is_empty():
			content.add_child(_body("No one being courted right now — talk to a close friend."))
		else:
			for npc_id: String in fam.courtships:
				var c: Dictionary = fam.courtships[npc_id]
				content.add_child(_body("%s — %s (%d points)" % [npc_id, String(c["stage"]).capitalize(), int(c["points"])]))
	content.add_child(_heading("Children"))
	var kids := fam.children_list()
	if kids.is_empty():
		content.add_child(_body("None yet."))
	else:
		for c: Dictionary in kids:
			content.add_child(_body("%s %s, age %d, %s." % [String(c["name"]), Life.life_path.family_name,
				int(c["age"]), String(c["sex"])]))
	var heirs: Array = fam.heir_candidates()
	if not heirs.is_empty():
		content.add_child(_heading("Possible heirs"))
		for h: Dictionary in heirs:
			content.add_child(_body("%s, age %d." % [String(h["name"]), int(h["age"])]))
	var chron: Array = fam.chronicles_list()
	if not chron.is_empty():
		content.add_child(_heading("Chronicles of your family"))
		for ch: Dictionary in chron:
			content.add_child(_body("%s (day %d):" % [String(ch["name"]), int(ch["day"])]))
			for line: String in (ch["summary"] as Array):
				content.add_child(_body("  " + String(line)))


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
