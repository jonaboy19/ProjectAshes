extends Control
## "Career & Life": current role and rank, what the next rank still needs, the
## player's top masteries in plain words, standing per reputation sphere, and
## the running biography summary. Reached from the Pack menu, next to "Photo
## mode" (village_services.gd pack_menu()). Pauses the game while open, like
## CraftingScreen and the skills screen.
##
## Reads Life defensively (Life.get(...) rather than Life.mastery) so the
## screen shows a plain placeholder instead of erroring until autoload/life.gd
## exposes `mastery` (RAMastery), `biography` (RABiography), `career_id` and
## `career_rank` (career_ladders.gd ids) — see the hook lines in the PR notes.

const CareerLadders := preload("res://scripts/sim/career_ladders.gd")
const Mastery := preload("res://scripts/sim/mastery.gd")
const SELF_PATH := "res://scripts/ui/career_screen.gd"

var _was_paused := false
var _box: VBoxContainer


## Loads via SELF_PATH (not the CareerScreen class name) so this compiles fine
## the moment the file exists, before Godot has rescanned the global class list.
static func open_for(hud: CanvasLayer) -> Control:
	var s: Control = hud.get_node_or_null("CareerScreen")
	if s == null:
		s = (load(SELF_PATH) as GDScript).new()
		s.name = "CareerScreen"
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
	head.text = "Career & Life"
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
	var mastery: Object = Life.get("mastery")
	var biography: Object = Life.get("biography")
	if mastery == null or biography == null:
		content.add_child(_heading("Not yet lived"))
		content.add_child(_body("This life hasn't started accumulating a career yet."))
		return
	var career := String(Life.get("career_id"))
	var rank := String(Life.get("career_rank"))
	content.add_child(_heading("Current life"))
	if career != "":
		content.add_child(_body("%s — %s" % [career.capitalize(), CareerLadders.title_for(career, rank)]))
	else:
		content.add_child(_body("No career yet. Take up work in the village to begin one."))
	content.add_child(_heading("Next rank"))
	if career != "":
		var ctx := _promotion_ctx(career, rank, mastery, biography)
		var check := CareerLadders.check_promotion(ctx)
		var nxt: Dictionary = check.get("next", {})
		if nxt.is_empty():
			content.add_child(_body("At the top of this ladder."))
		else:
			content.add_child(_body("%s" % String(nxt["title"])))
			var missing: PackedStringArray = check.get("missing", PackedStringArray())
			if missing.is_empty():
				content.add_child(_body("Ready. Report to whoever can sign for it."))
			else:
				for m: String in missing:
					content.add_child(_body("• " + m))
	content.add_child(_heading("Masteries"))
	var top: Array = mastery.call("top", 6)
	if top.is_empty():
		content.add_child(_body("Nothing practised enough yet to show."))
	else:
		for row: Dictionary in top:
			var yrs := int(mastery.call("years_practised", row["discipline"]))
			var yr_text := " (%d yr)" % yrs if yrs > 0 else ""
			content.add_child(_body("%s — %s%s" % [String(row["discipline"]).capitalize(), row["word"], yr_text]))
	content.add_child(_heading("Reputation"))
	for sphere: String in ["military", "trade", "craft", "farming", "faith", "underworld"]:
		var v := float(biography.call("rep", sphere))
		content.add_child(_body("%s: %d" % [sphere.capitalize(), int(round(v))]))
	content.add_child(_heading("Biography"))
	for line: String in (biography.call("summary", int(WorldSim.day)) as Array):
		content.add_child(_body(String(line)))


func _content() -> VBoxContainer:
	return _box.get_child(2).get_child(0)   # ScrollContainer -> Content


func _promotion_ctx(career: String, rank: String, mastery: Object, biography: Object) -> Dictionary:
	var since := int(Life.get("career_since_day")) if Life.get("career_since_day") != null else WorldSim.day
	var flags: Dictionary = {}
	if Life.get("life_path") != null:
		flags = Life.life_path.flags
	return {
		"career": career, "rank": rank, "since_day": since, "day": WorldSim.day,
		"mastery": mastery, "biography": biography, "careers": Life.careers,
		"gold": Game.gold, "at_war": bool(flags.get("at_war", false)),
		"sponsor_tier": int(Life.get("career_sponsor_tier")) if Life.get("career_sponsor_tier") != null else 0,
		"owns_plot": not Life.homestead.owned.is_empty(),
	}


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
