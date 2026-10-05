class_name CreditsScreen
extends Control
## "Credits & Licences": kingdom/CREDITS.md (asset credits and MIT notices), the
## licence files of the shipped addons, and the Godot Engine licence with its
## third-party notices. Scrollable (touch drag or wheel), sized for phones.
## Open with CreditsScreen.open(hud); CREDITS.md and addons/*/LICENSE* are
## added to exports by the include filter in export_presets.cfg.

const AF := preload("res://scripts/ui/ashes_frame.gd")
const FE := preload("res://scripts/ui/frontend/fe.gd")
const CREDITS_PATH := "res://CREDITS.md"
## Addons shipped in the build (LimboAI and Terrain3D are disabled; see project.godot).
const ADDON_LICENCES := ["gloot", "dialogue_manager", "guide", "quest_weaver", "GodotGAS", "sky_3d",
	"road-generator", "proton_scatter"]

var _text: RichTextLabel
var _full_button: Button


static func open(hud: Node) -> CreditsScreen:
	var s := CreditsScreen.new()
	hud.add_child(s)
	return s


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = AF.theme()
	add_child(FE.backdrop_stack("main_menu", 0.72))
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_stylebox_override("panel", AF.panel(Color(0.03, 0.028, 0.025, 0.9), AF.GOLD, 4, 22))
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	box.add_child(FE.header("Credits & Licences", queue_free, 24))
	box.add_child(AF.separator())
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.scroll_deadzone = 12
	box.add_child(scroll)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(0, 0)
	_text.scroll_active = false
	_text.selection_enabled = false
	_text.mouse_filter = Control.MOUSE_FILTER_PASS
	_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text.add_theme_font_override("normal_font", AF.font(AF.BODY_FONT))
	_text.add_theme_font_override("bold_font", AF.wfont(600))
	_text.add_theme_font_size_override("normal_font_size", 18)
	_text.add_theme_font_size_override("bold_font_size", 17)
	_text.add_theme_color_override("default_color", AF.TEXT)
	_text.meta_clicked.connect(func(meta: Variant) -> void: OS.shell_open(str(meta)))
	scroll.add_child(_text)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_END
	box.add_child(row)
	_full_button = FE.ghost_button("Engine licence texts", _show_full_licences, 240)
	row.add_child(_full_button)
	var close := FE.gold_btn("Close", queue_free, 160)
	row.add_child(close)
	_text.text = build_text()
	get_viewport().size_changed.connect(_layout)
	_layout()
	close.grab_focus()


func _layout() -> void:
	var vw := get_viewport().get_visible_rect().size
	# (full-rect anchors from _ready already size this root; assigning size warned)
	var panel: Control = get_child(1)
	var w := clampf(vw.x * 0.94, 320.0, 980.0)
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


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("journal"):
		get_viewport().set_input_as_handled()
		queue_free()


## Everything except the long third-party licence texts.
static func build_text() -> String:
	var out := PackedStringArray()
	if FileAccess.file_exists(CREDITS_PATH):
		out.append(md_to_bbcode(FileAccess.get_file_as_string(CREDITS_PATH)))
	else:
		out.append("[b]CREDITS.md is missing from this build.[/b]")
	out.append(_heading("Addon licences"))
	for addon: String in ADDON_LICENCES:
		for f in ["LICENSE", "LICENSE.md", "LICENSE.txt", "LICENCE", "LICENCE.md"]:
			var p := "res://addons/%s/%s" % [addon, f]
			if FileAccess.file_exists(p):
				out.append("[b]%s[/b]\n[color=#%s]%s[/color]" % [addon, AF.TEXT_DIM.to_html(false),
					_escape(FileAccess.get_file_as_string(p).strip_edges())])
				break
	out.append(_heading("Godot Engine"))
	out.append("This game uses the Godot Engine, available under the following licence:\n\n" + _escape(Engine.get_license_text()))
	out.append(_heading("Godot third-party components"))
	var comps := PackedStringArray()
	for c: Dictionary in Engine.get_copyright_info():
		var lic := PackedStringArray()
		var who := PackedStringArray()
		for part: Dictionary in c["parts"]:
			if not lic.has(part["license"]):
				lic.append(part["license"])
			for cr: String in part["copyright"]:
				who.append(cr)
		comps.append("[b]%s[/b] (%s): %s" % [_escape(c["name"]), ", ".join(lic), _escape("; ".join(who))])
	out.append("\n".join(comps))
	return "\n\n".join(out)


func _show_full_licences() -> void:
	var out := PackedStringArray()
	out.append(_heading("Licence texts of Godot's third-party components"))
	var info := Engine.get_license_info()
	for name: String in info:
		out.append("[b]%s[/b]\n%s" % [_escape(name), _escape(str(info[name]))])
	_text.text += "\n\n" + "\n\n".join(out)
	_full_button.disabled = true


static func _heading(t: String) -> String:
	return "[font_size=22][color=#%s]%s[/color][/font_size]" % [AF.GOLD_BRIGHT.to_html(false), t]


static func _escape(s: String) -> String:
	return s.replace("[", "[lb]")


## Minimal Markdown -> BBCode: headings, bullets, **bold**, `code`, [text](url).
static func md_to_bbcode(md: String) -> String:
	var lines := PackedStringArray()
	var bold := RegEx.create_from_string("\\*\\*(.+?)\\*\\*")
	var code := RegEx.create_from_string("`([^`]+)`")
	var link := RegEx.create_from_string("\\[([^\\]]+)\\]\\(([^)]+)\\)")
	var url := RegEx.create_from_string("(?<![=\\]])\\b(https?://[^\\s)]+)")
	for raw in md.split("\n"):
		var l := raw.strip_edges(false, true)
		var level := 0
		while level < l.length() and l[level] == "#":
			level += 1
		if level > 0:
			l = l.substr(level).strip_edges()
		var bullet := l.begins_with("- ") or l.begins_with("* ")
		if bullet:
			l = l.substr(2)
		l = link.sub(l, "\u0001$2\u0002$1\u0003", true)
		l = _escape(l).replace("\u0001", "[url=").replace("\u0002", "]").replace("\u0003", "[/url]")
		l = url.sub(l, "[url=$1]$1[/url]", true)
		l = bold.sub(l, "[b]$1[/b]", true)
		l = code.sub(l, "[code]$1[/code]", true)
		if level > 0:
			l = _heading(l) if level <= 2 else "[b]%s[/b]" % l
		elif bullet:
			l = "  •  " + l
		lines.append(l)
	return "\n".join(lines)
