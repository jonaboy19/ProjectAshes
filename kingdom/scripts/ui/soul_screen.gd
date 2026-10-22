extends Control
## "Soul": current soul tier and progress toward the next, the emerging or
## chosen Path, unlocked elemental evolutions, and a Breakthrough button once
## one is available. Reached from the Pack menu (village_services.gd
## pack_menu()), next to "Career & life". Pauses the game while open, like
## CareerScreen and ChronicleScreen.
##
## Reads Life defensively (Life.get(...) rather than Life.soul) so the screen
## shows a plain placeholder instead of erroring until autoload/life.gd exposes
## `soul` (RASoul) and `skill_evolution` (RASkillEvolution) — see the hook
## lines in the soul_hooks report.

const SELF_PATH := "res://scripts/ui/soul_screen.gd"

var _was_paused := false
var _box: VBoxContainer


## Loads via SELF_PATH (not a class name) so this compiles fine the moment the
## file exists, before Godot has rescanned the global class list. `soul` and
## `evolution` are optional explicit references (tests, callers that don't go
## through Life); when omitted the screen falls back to Life.get(...).
static func open(hud: CanvasLayer, soul: Object = null, evolution: Object = null) -> Control:
	var s: Control = hud.get_node_or_null("SoulScreen")
	if s == null:
		s = (load(SELF_PATH) as GDScript).new()
		s.name = "SoulScreen"
		hud.add_child(s)
	if soul != null:
		s.set("_soul_override", soul)
	if evolution != null:
		s.set("_evolution_override", evolution)
	if hud.has_method("close_menu"):
		hud.call("close_menu")
	s.call("open_screen")
	return s


## Alias matching the rest of the pack menu's screens (CareerScreen.open_for, …).
static func open_for(hud: CanvasLayer) -> Control:
	return open(hud)


var _soul_override: Object = null
var _evolution_override: Object = null


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
	head.text = "Soul"
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


func open_screen() -> void:
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

func _soul() -> Object:
	return _soul_override if _soul_override != null else Life.get("soul")


func _evolution() -> Object:
	return _evolution_override if _evolution_override != null else Life.get("skill_evolution")


func _content() -> VBoxContainer:
	return _box.get_child(2).get_child(0)   # ScrollContainer -> Content


func _refresh() -> void:
	var content := _content()
	for c in content.get_children():
		c.queue_free()
	var soul: Object = _soul()
	if soul == null:
		content.add_child(_heading("No soul yet"))
		content.add_child(_body("This life hasn't started earning Soul Power yet."))
		return
	var prog: Dictionary = soul.call("progress")
	content.add_child(_heading("Tier: %s" % String(prog.get("tier_name", "?"))))
	content.add_child(_body(String(soul.call("tier_info").get("flavour", ""))))
	content.add_child(_progress_bar(float(prog.get("ratio", 0.0))))
	if float(prog.get("ratio", 0.0)) < 1.0:
		content.add_child(_body("%d / %d toward %s" % [int(prog.get("into", 0.0)), int(prog.get("needed", 0.0)),
			String(prog.get("next_tier", "?"))]))
	else:
		content.add_child(_body("At the peak of this tier."))
	content.add_child(_heading("Path"))
	var path_info: Dictionary = soul.call("path_info")
	if not path_info.is_empty():
		content.add_child(_body("%s — %s" % [String(path_info.get("name", "")), String(path_info.get("flavour", ""))]))
	else:
		var mastery: Object = Life.get("mastery")
		var disciplines := {}
		if mastery != null:
			for row: Dictionary in (mastery.call("top", 6) as Array):
				disciplines[String(row["discipline"])] = int(row["level"])
		var dominant: Dictionary = soul.call("dominant_path", disciplines)
		if dominant.is_empty():
			content.add_child(_body("No Path has emerged yet. Keep living; it will show itself."))
		else:
			content.add_child(_body("Emerging: %s" % String(dominant.get("name", ""))))
			content.add_child(_body(String(dominant.get("flavour", ""))))
			var choose := Button.new()
			choose.text = "Take up " + String(dominant.get("name", ""))
			choose.custom_minimum_size = Vector2(0, 44)
			var path_id := String(dominant.get("id", ""))
			choose.pressed.connect(func() -> void:
				soul.call("choose_path", path_id)
				_refresh())
			content.add_child(choose)
	content.add_child(_heading("Evolutions"))
	var evolution := _evolution()
	if evolution == null or (evolution.call("evolutions") as Dictionary).is_empty():
		content.add_child(_body("No abilities have evolved yet — how you use them shapes what they become."))
	else:
		var evos: Dictionary = evolution.call("evolutions")
		for id: String in evos:
			var def: Dictionary = evos[id]
			content.add_child(_body("%s (%s)" % [String(def.get("name", id)), String(def.get("element", ""))]))
	content.add_child(_heading("Breakthrough"))
	if bool(soul.call("can_attempt_breakthrough")):
		var btn := Button.new()
		btn.text = "Attempt breakthrough"
		btn.custom_minimum_size = Vector2(0, 50)
		btn.pressed.connect(func() -> void:
			var r: Dictionary = soul.call("attempt_breakthrough", -1, {})
			Game.say(String(r.get("text", "")))
			_refresh())
		content.add_child(btn)
	else:
		content.add_child(_body("Not ready. Your soul needs more banked power (or a lower tier still grows on its own)."))


func _progress_bar(ratio: float) -> Control:
	var bg := PanelContainer.new()
	bg.custom_minimum_size = Vector2(0, 18)
	var fill := ColorRect.new()
	fill.color = UITheme.ACCENT
	fill.custom_minimum_size = Vector2(0, 18)
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(0, 18)
	var track := ColorRect.new()
	track.color = Color(1, 1, 1, 0.12)
	track.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wrap.add_child(track)
	fill.set_anchors_preset(Control.PRESET_TOP_LEFT)
	fill.anchor_bottom = 1.0
	fill.anchor_right = clampf(ratio, 0.0, 1.0)
	fill.offset_right = 0.0
	fill.offset_left = 0.0
	fill.offset_bottom = 0.0
	fill.offset_top = 0.0
	wrap.add_child(fill)
	return wrap


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
