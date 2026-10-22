extends "res://scripts/ui/frontend/screen.gd"
## Main menu: left menu column over the painted backdrop.

const Flow := preload("res://scripts/ui/frontend/flow.gd")
const NewGame := preload("res://scripts/ui/frontend/new_game.gd")
const LoadingScreen := preload("res://scripts/ui/frontend/loading_screen.gd")
const SlotScreen := preload("res://scripts/ui/frontend/slot_screen.gd")
const SettingsScreen := preload("res://scripts/ui/frontend/settings_screen.gd")
const Extras := preload("res://scripts/ui/frontend/extras_screen.gd")
const Credits := preload("res://scripts/ui/credits_screen.gd")

var _menu: VBoxContainer
var _continue: Button


func _init() -> void:
	super()
	can_back = false


func _ready() -> void:
	add_backdrop("main_menu", 0.1)
	add_child(FE.fade_rect(true, 0.92, 0.45))
	var left := MarginContainer.new()
	left.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	left.anchor_right = 0.0
	left.offset_left = 56
	left.offset_right = 56 + 340
	left.offset_top = 34
	left.offset_bottom = -30
	add_child(left)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	left.add_child(col)
	var lc := CenterContainer.new()
	lc.add_child(FE.logo(0.42))
	col.add_child(lc)
	# AAA pass 2026-10-06 (owner review): RISING ASHES is the dominant element of the screen, with a small studio credit.
	var head := VBoxContainer.new()
	head.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	head.offset_left = 56 + 340
	head.offset_right = -24
	head.offset_top = 70
	head.add_theme_constant_override("separation", 2)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(head)
	head.add_child(FE.title_label(96))
	var studio := AF.label("A Total Showdown Studios Game", 18, Color(1, 0.95, 0.85, 0.85))
	studio.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	studio.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	studio.add_theme_constant_override("shadow_offset_x", 1)
	studio.add_theme_constant_override("shadow_offset_y", 1)
	head.add_child(studio)
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 22)
	col.add_child(sp)
	_menu = VBoxContainer.new()
	_menu.add_theme_constant_override("separation", 2)
	col.add_child(_menu)
	var have: String = Life.saves.latest_id() if _has_life() else ""
	_continue = FE.menu_row(tr("MENU_CONTINUE"), _continue_game)
	_continue.disabled = have == ""
	_menu.add_child(_continue)
	_menu.add_child(FE.menu_row(tr("MENU_NEW"), _new_game))
	var load_b := FE.menu_row(tr("MENU_LOAD"), _load_game)
	_menu.add_child(load_b)
	_menu.add_child(FE.menu_row(tr("MENU_SETTINGS"), func() -> void: SettingsScreen.open(self)))
	_menu.add_child(FE.menu_row("Extras", func() -> void: Extras.open(self)))
	_menu.add_child(FE.menu_row(tr("MENU_CREDITS"), func() -> void: Credits.open(self)))
	# Debug builds (and any build with a `user://style_lab.flag` file): the Style Lab look-dev scene.
	if (OS.is_debug_build() or FileAccess.file_exists("user://style_lab.flag")) and ResourceLoader.exists("res://scenes/style_lab/style_lab.tscn"):
		_menu.add_child(FE.menu_row("Style Lab", func() -> void: get_tree().change_scene_to_file("res://scenes/style_lab/style_lab.tscn")))
	# iOS apps must not offer a Quit button (App Store guideline); Android and desktop do.
	if not OS.has_feature("ios"):
		_menu.add_child(FE.menu_row(tr("MENU_QUIT"), func() -> void: get_tree().quit()))
	# Version (top right), tagline (bottom right), key hints (bottom left).
	var ver := VBoxContainer.new()
	ver.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	ver.offset_left = -260
	ver.offset_right = -24
	ver.offset_top = 16
	ver.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ver)
	for txt: String in ["Version " + Flow.version_text(), "Project Ashes"]:
		var l := AF.label(txt, 13, Color(1, 1, 1, 0.75))
		l.add_theme_font_override("font", AF.wfont(500))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
		l.add_theme_constant_override("shadow_offset_x", 1)
		l.add_theme_constant_override("shadow_offset_y", 1)
		ver.add_child(l)
	var tag := VBoxContainer.new()
	tag.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	tag.offset_left = -520
	tag.offset_right = -36
	tag.offset_top = -92
	tag.offset_bottom = -30
	tag.alignment = BoxContainer.ALIGNMENT_END
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tag)
	var q := AF.label("Every life leaves a mark on the world.", 20, AF.TEXT, true)
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	q.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	q.add_theme_constant_override("shadow_offset_x", 1)
	q.add_theme_constant_override("shadow_offset_y", 2)
	tag.add_child(q)
	var a := Label.new()
	a.text = "A LIVING WORLD AWAITS"
	a.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	a.add_theme_font_override("font", AF.wfont(600))
	a.add_theme_font_size_override("font_size", 15)
	a.add_theme_color_override("font_color", AF.GOLD_BRIGHT)
	a.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	a.add_theme_constant_override("shadow_offset_y", 2)
	tag.add_child(a)
	if not Flow.is_mobile():
		var hints := FE.key_hints([["↑↓", "Navigate"], ["Enter", "Select"], ["Esc", "Back"]])
		hints.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
		hints.offset_left = 56
		hints.offset_top = -44
		hints.offset_bottom = -14
		add_child(hints)
	FE.fade_in(left, 0.6)
	if _continue.disabled:
		_menu.get_child(1).call_deferred("grab_focus")
	else:
		_continue.call_deferred("grab_focus")


func _has_life() -> bool:
	return get_tree().root.has_node("Life")


func _continue_game() -> void:
	var id: String = Life.saves.latest_id()
	if id == "":
		return
	_start_load(id)


func _start_load(id: String) -> void:
	Flow.pending_load = id
	Flow.mode = "story"
	Flow.creation = {}
	Flow.reset_world_state(get_tree())
	LoadingScreen.open(self)


func _new_game() -> void:
	NewGame.open(self)


func _load_game() -> void:
	SlotScreen.open(self, "load", _start_load)
