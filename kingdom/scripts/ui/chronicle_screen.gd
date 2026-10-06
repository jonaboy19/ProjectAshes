extends Control
## "Chronicle": recent news of people the player knows — deaths, births,
## promotions, marriages — and a family tree view for one of them. Reached
## from the Pack menu (village_services.gd pack_menu()). Pauses the game
## while open, like NobilityScreen and CareerScreen.
##
## Reads Life.life_courses defensively: until autoload/life.gd owns one (see
## the hook lines in the task report), this screen builds its own
## scripts/sim/life_courses.gd instance so it still shows something sensible.

const LifeCourses := preload("res://scripts/sim/life_courses.gd")
const SELF_PATH := "res://scripts/ui/chronicle_screen.gd"
## How far back "recent news" looks, in in-game days.
const NEWS_WINDOW_DAYS := 3650
const MAX_NEWS_SHOWN := 20

var _was_paused := false
var _box: VBoxContainer
var _own_life_courses: LifeCourses
var _family_box: VBoxContainer
var _shown_family_id := -1


static func open_for(hud: CanvasLayer) -> Control:
	var s: Control = hud.get_node_or_null("ChronicleScreen")
	if s == null:
		s = (load(SELF_PATH) as GDScript).new()
		s.name = "ChronicleScreen"
		hud.add_child(s)
	if hud.has_method("close_menu"):
		hud.call("close_menu")
	s.call("open")
	return s


func _life_courses() -> LifeCourses:
	var lc: Object = Life.get("life_courses")
	if lc != null:
		return lc as LifeCourses
	if _own_life_courses == null:
		_own_life_courses = LifeCourses.new()
		_own_life_courses.seed_from(WorldSim.SEED)
		_own_life_courses.populate_region(150, WorldSim.day)
	return _own_life_courses


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
	head.text = "Chronicle"
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
	_shown_family_id = -1
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
	var lc := _life_courses()
	var day := WorldSim.day
	content.add_child(_heading("Recent news"))
	var news := lc.news_since(maxi(0, day - NEWS_WINDOW_DAYS))
	if news.is_empty():
		content.add_child(_body("Nothing new — but the world is still turning."))
	else:
		var start := maxi(0, news.size() - MAX_NEWS_SHOWN)
		for i in range(news.size() - 1, start - 1, -1):
			content.add_child(_body("• " + String(news[i])))
	content.add_child(_heading("People you know"))
	var known := lc.known_people()
	if known.is_empty():
		content.add_child(_body("You haven't yet met anyone worth remembering."))
	else:
		for id in known:
			content.add_child(_person_row(lc, id, day))
	_family_box = VBoxContainer.new()
	_family_box.add_theme_constant_override("separation", 4)
	content.add_child(_family_box)
	if _shown_family_id >= 0:
		_show_family(_shown_family_id)


func _person_row(lc: LifeCourses, id: int, day: int) -> PanelContainer:
	var p := lc.person(id)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UITheme.panel_box())
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	card.add_child(col)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)
	var name_label := Label.new()
	var status := "" if bool(p.get("alive", true)) else "  (deceased)"
	name_label.text = "%s%s" % [String(p.get("name", "?")), status]
	name_label.add_theme_font_override("font", UITheme.title_font_weight(600))
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.add_theme_color_override("font_color", UITheme.TEXT if bool(p.get("alive", true)) else UITheme.TEXT_DIM)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	var tree_btn := Button.new()
	tree_btn.text = "Family tree"
	tree_btn.pressed.connect(func() -> void:
		_shown_family_id = id
		_show_family(id))
	row.add_child(tree_btn)
	var settlement_name := "the village"
	var sidx := int(p.get("settlement", -1))
	if sidx >= 0 and sidx < WorldGen.settlements.size():
		settlement_name = WorldGen.display_name(String(WorldGen.settlements[sidx]["name"]))
	var occ := String(p.get("occupation", ""))
	var rank := String(p.get("rank", ""))
	var role_text := ("%s, %s" % [rank.capitalize(), occ]) if rank != "" else occ.capitalize()
	col.add_child(_body("Age %d · %s · %s" % [lc.age_years(id, day), role_text, settlement_name]))
	if not bool(p.get("alive", true)):
		var cause := String(p.get("cause_of_death", ""))
		if cause != "":
			col.add_child(_body("Died %s." % LifeCourses.CAUSE_TEXT.get(cause, cause)))
	return card


func _show_family(id: int) -> void:
	for c in _family_box.get_children():
		c.queue_free()
	var lc := _life_courses()
	var tree := lc.family_tree(id)
	if tree.is_empty():
		return
	_family_box.add_child(_heading("Family of %s" % String(tree["person"].get("name", "?"))))
	var parents: Array = tree.get("parents", [])
	if not parents.is_empty():
		var names := PackedStringArray()
		for pp: Dictionary in parents:
			names.append(String(pp.get("name", "?")))
		_family_box.add_child(_body("Parents: " + ", ".join(names)))
	var spouse: Dictionary = tree.get("spouse", {})
	if not spouse.is_empty():
		_family_box.add_child(_body("Spouse: " + String(spouse.get("name", "?"))))
	var children: Array = tree.get("children", [])
	if not children.is_empty():
		var names2 := PackedStringArray()
		for cc: Dictionary in children:
			names2.append(String(cc.get("name", "?")))
		_family_box.add_child(_body("Children: " + ", ".join(names2)))
	elif spouse.is_empty() and parents.is_empty():
		_family_box.add_child(_body("No known family on record."))


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
