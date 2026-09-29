extends "res://scripts/ui/frontend/screen.gd"
## THE settings screen (main menu and in-game): tabs Graphics / Audio / Gameplay /
## Controls / Language / Accessibility, "< value >" rows, Apply / Reset / Back.
## Values persist through settings_store.gd (user://settings.cfg; the graphics preset
## goes through the `Quality` autoload, which keeps its own [graphics] keys).
##   SettingsScreen.open(parent)          from the main menu
##   SettingsScreen.open(parent, true)    over the running game (pause menu)

const SS := preload("res://scripts/ui/frontend/settings_store.gd")
const Flow := preload("res://scripts/ui/frontend/flow.gd")
const SelRow := preload("res://scripts/ui/frontend/sel_row.gd")

const TABS := ["Graphics", "Audio", "Gameplay", "Controls", "Language", "Accessibility"]
const DIFFICULTY := ["Story", "Normal", "Hard", "Brutal"]

var start_tab := 0
var _vals := {}
var _saved := {}
var _tab := 0
var _tab_buttons: Array[Button] = []
var _content: VBoxContainer
var _title: Label
var _caption: Label
var _dirty_label: Label
var _loading_tab := false
var _paused_by_me := false


static func open(parent: Node, over_game := false, tab := 0) -> Control:
	var s: Variant = load("res://scripts/ui/frontend/settings_screen.gd").new()
	s.translucent = over_game
	s.start_tab = tab
	parent.add_child(s)
	return s


func _ready() -> void:
	if translucent and not get_tree().paused:
		get_tree().paused = true
		_paused_by_me = true
	_saved = SS.read_all(get_tree())
	_vals = _saved.duplicate()
	add_backdrop("settings", 0.62)
	var mc := margin_box(34)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	mc.add_child(col)
	col.add_child(FE.header("Settings", back))
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 18)
	col.add_child(row)
	# Tabs.
	var tabs := PanelContainer.new()
	tabs.custom_minimum_size = Vector2(250, 0)
	tabs.add_theme_stylebox_override("panel", AF.panel(AF.PANEL, AF.GOLD_DIM, 4, 10))
	row.add_child(tabs)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 4)
	tabs.add_child(tv)
	for i in TABS.size():
		var b := FE.menu_row(TABS[i], Callable(), 19, 50)
		b.focus_entered.connect(_show_tab.bind(i))
		b.pressed.connect(_show_tab.bind(i))
		tv.add_child(b)
		_tab_buttons.append(b)
	# Rows.
	var mid := PanelContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_theme_stylebox_override("panel", AF.panel(AF.PANEL, AF.GOLD_DIM, 4, 14))
	row.add_child(mid)
	var mv := VBoxContainer.new()
	mv.add_theme_constant_override("separation", 8)
	mid.add_child(mv)
	_title = Label.new()
	_title.add_theme_font_override("font", AF.wfont(600))
	_title.add_theme_font_size_override("font_size", 20)
	_title.add_theme_color_override("font_color", AF.GOLD_BRIGHT)
	mv.add_child(_title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	mv.add_child(scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 4)
	scroll.add_child(_content)
	# Preview column.
	var pv := PanelContainer.new()
	pv.custom_minimum_size = Vector2(290, 0)
	pv.add_theme_stylebox_override("panel", AF.panel(AF.PANEL, AF.GOLD_DIM, 4, 10))
	row.add_child(pv)
	var pcol := VBoxContainer.new()
	pcol.add_theme_constant_override("separation", 8)
	pv.add_child(pcol)
	var img := TextureRect.new()
	img.custom_minimum_size = Vector2(0, 330)
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	img.clip_contents = true
	for ext: String in [".png", ".jpg", ".webp"]:
		if ResourceLoader.exists(AF.BG_DIR + "settings" + ext):
			img.texture = load(AF.BG_DIR + "settings" + ext)
			break
	pcol.add_child(img)
	_caption = AF.label("", 16, AF.TEXT_DIM)
	pcol.add_child(_caption)
	_dirty_label = AF.label("", 15, AF.GOLD, true)
	pcol.add_child(_dirty_label)
	# Footer.
	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_END
	foot.add_theme_constant_override("separation", 12)
	col.add_child(foot)
	if not Flow.is_mobile():
		var hints := FE.key_hints([["↑↓", "Select"], ["←→", "Change"], ["Esc", "Back"]])
		hints.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		foot.add_child(hints)
	foot.add_child(FE.gold_btn("Apply", _apply, 150))
	foot.add_child(FE.ghost_button("Reset", _reset, 130))
	foot.add_child(FE.ghost_button("Back", back, 130))
	_show_tab(clampi(start_tab, 0, TABS.size() - 1))
	FE.fade_in(self, 0.25)
	_tab_buttons[_tab].call_deferred("grab_focus")


func _show_tab(i: int) -> void:
	if _loading_tab:
		return
	_tab = i
	for j in _tab_buttons.size():
		_tab_buttons[j].add_theme_color_override("font_color", AF.GOLD_BRIGHT if j == i else AF.TEXT)
	for c in _content.get_children():
		_content.remove_child(c)
		c.queue_free()
	_title.text = "%s Settings" % TABS[i]
	match TABS[i]:
		"Graphics": _tab_graphics()
		"Audio": _tab_audio()
		"Gameplay": _tab_gameplay()
		"Controls": _tab_controls()
		"Language": _tab_language()
		"Accessibility": _tab_access()
	_update_caption()


func _row(key: String, label: String, kind: String, opts: Array, hint := "") -> SelRow:
	var r := SelRow.new()
	r.setup(key, label, kind, opts, _vals.get(key, SS.DEFAULTS.get(key, 0)), hint)
	r.changed.connect(_on_changed)
	_content.add_child(r)
	return r


func _tab_graphics() -> void:
	_row("preset", "Graphics Preset", "opt", ["Auto", "Low", "Medium", "High", "Ultra"])
	if not Flow.is_mobile():
		_row("resolution", "Resolution", "opt", SS.RES_OPTIONS)
		_row("display_mode", "Display Mode", "opt", ["Windowed", "Fullscreen", "Borderless"])
	_row("vsync", "VSync", "opt", ["Off", "On", "Adaptive"])
	_row("aa", "Anti-Aliasing", "opt", ["Off", "FXAA", "MSAA 2x", "MSAA 4x"])
	_row("view_distance", "View Distance", "opt", SS.LEVELS)
	_row("shadows", "Shadows", "opt", SS.LEVELS)
	_row("textures", "Textures", "opt", SS.LEVELS)
	_row("effects", "Effects", "opt", SS.LEVELS)
	_row("fps_limit", "Frame Rate Limit", "opt", ["30", "60", "Unlimited"])


func _tab_audio() -> void:
	_row("vol_master", "Master Volume", "slider", [])
	_row("vol_music", "Music", "slider", [])
	_row("vol_sfx", "Sound Effects", "slider", [])
	_row("vol_ambience", "Ambience", "slider", [])
	_row("vol_voice", "Voice", "slider", [])


func _tab_gameplay() -> void:
	_row("difficulty", "Difficulty", "opt", DIFFICULTY)
	_row("cam_sens", "Camera Sensitivity", "slider", [])
	_row("invert_y", "Invert Y Axis", "toggle", [])
	_row("subtitles", "Subtitles", "toggle", [])
	_row("hud_minimap", "HUD: Minimap", "toggle", [])
	_row("hud_compass", "HUD: Compass", "toggle", [])
	_row("hud_quests", "HUD: Quest Tracker", "toggle", [])
	_row("hud_damage", "HUD: Damage Numbers", "toggle", [])


func _tab_controls() -> void:
	var note := AF.label("Select a key and press Enter (or tap it), then press the new key. Esc cancels.", 15, AF.TEXT_DIM, true)
	_content.add_child(note)
	for a: Array in SS.ACTIONS:
		var act := String(a[0])
		if not InputMap.has_action(act):
			continue
		var r := SelRow.new()
		r.setup("act:" + act, String(a[1]), "key", [], SS.binding_text(act))
		r.changed.connect(_on_changed)
		_content.add_child(r)


func _tab_language() -> void:
	_row("language", "Language", "opt", ["English"])
	for l: String in ["Français", "Deutsch", "Español", "Português", "日本語"]:
		var r := SelRow.new()
		r.setup("", l, "info", [], "Coming soon")
		r.modulate = Color(1, 1, 1, 0.5)
		r.focus_mode = Control.FOCUS_NONE
		_content.add_child(r)


func _tab_access() -> void:
	_row("text_size", "Text Size", "opt", ["Small", "Normal", "Large", "Extra Large"])
	_row("colorblind", "Colour-Blind Mode", "opt", ["Off", "Protanopia", "Deuteranopia", "Tritanopia"])
	_row("screen_shake", "Screen Shake", "opt", ["Off", "Reduced", "Full"])
	_content.add_child(AF.label("Colour-blind filters are a placeholder and will be applied in a later update.", 15, AF.TEXT_DIM, true))


func _on_changed(key: String, value: Variant) -> void:
	if key.begins_with("act:"):
		SS.set_binding(key.substr(4), int(value))
		return
	_vals[key] = value
	if SS.BUSES.has(key):
		SS.apply_volume(key, int(value))     # live preview of volume
	_update_caption()


func _update_caption() -> void:
	var names := ["Auto", "Low", "Medium", "High", "Ultra"]
	var pre := int(_vals.get("preset", 0))
	var txt := "Preset: %s" % names[clampi(pre, 0, 4)]
	if pre == 0 and get_tree().root.has_node("Quality"):
		txt = "Preset: Auto (%s)" % Quality.tier_name()
	_caption.text = txt
	var changed := false
	for k: String in _vals:
		if _vals[k] != _saved.get(k):
			changed = true
			break
	_dirty_label.text = "Unapplied changes" if changed else ""


func _apply() -> void:
	SS.write_all(_vals)
	SS.apply_all(get_tree(), _vals, true)
	_saved = _vals.duplicate()
	FE.play("open")
	_update_caption()
	_dirty_label.text = "Settings applied."


func _reset() -> void:
	var keep_controls: bool = TABS[_tab] != "Controls"
	if not keep_controls:
		SS.reset_controls()
		InputMap.load_from_project_settings()
		var g := get_tree().root.get_node_or_null("Game")
		if g:
			g.call("_setup_input")
	else:
		_vals = SS.DEFAULTS.duplicate()
		_vals["preset"] = 0
	_show_tab(_tab)
	_update_caption()


func back() -> void:
	# Drop un-applied live previews (volumes).
	for k: String in SS.BUSES:
		SS.apply_volume(k, int(_saved.get(k, SS.DEFAULTS[k])))
	super()


func _exit_tree() -> void:
	if _paused_by_me and get_tree():
		get_tree().paused = false
