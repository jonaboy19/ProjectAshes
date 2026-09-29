class_name Region1TutorialPromptView
extends Control
## Draws the tutorial director's current prompt (package L16): a pulsing gold ring on the
## HUD element to use, an animated gesture (drag, swipe, tap, hold, trace), one short line
## of text in a dark-gold pill and a small skip button. Touch-first: art does the teaching,
## text is a caption. No assets needed (everything is drawn), so it works in any scene.
##
##   var view := Region1TutorialPromptView.new()
##   hud_layer.add_child(view)                        # a CanvasLayer above the HUD
##   view.bind(director)                              # connects shown/hidden, skip -> skip_current
##   view.set_hud_anchor(&"btn_attack", attack_button.get_global_rect().get_center())
##
## Anchors default to a typical phone HUD (fractions of the viewport) until the HUD sets them.

signal skip_pressed

const PANEL := Color(0.043, 0.039, 0.035, 0.88)
const GOLD := Color("d8a84e")
const GOLD_BRIGHT := Color("f3cf7a")
const TEXT := Color("ece3cf")
const BODY_FONT := "res://assets/ui/fonts/IMFellEnglish-Regular.ttf"
const SKIP_SIZE := 48.0          # touch target (px at 1080p height, scaled below)
const DEFAULT_ANCHORS := {
	"left_stick": Vector2(0.13, 0.76), "screen_right": Vector2(0.70, 0.45),
	"btn_attack": Vector2(0.89, 0.80), "btn_block": Vector2(0.78, 0.88), "btn_dodge": Vector2(0.94, 0.62),
	"btn_interact": Vector2(0.79, 0.66), "btn_eat": Vector2(0.66, 0.89), "btn_map": Vector2(0.94, 0.09),
	"center": Vector2(0.5, 0.42),
}

var director: Region1TutorialDirector
var prompt: Dictionary = {}
var _anchors: Dictionary = {}     # name -> screen position (px), overrides DEFAULT_ANCHORS
var _t := 0.0
var _alpha := 0.0
var _target_alpha := 0.0
var _done_flash := 0.0
var _label: Label
var _pill: PanelContainer
var _skip: Button
var _font: Font


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = load(BODY_FONT) if ResourceLoader.exists(BODY_FONT) else ThemeDB.fallback_font
	_pill = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL
	sb.border_color = GOLD
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(26)
	sb.content_margin_left = 22
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 10
	_pill.add_theme_stylebox_override("panel", sb)
	_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pill.add_child(row)
	_label = Label.new()
	_label.add_theme_font_override("font", _font)
	_label.add_theme_color_override("font_color", TEXT)
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	_label.add_theme_constant_override("outline_size", 4)
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_label)
	_skip = Button.new()
	_skip.text = "x"
	_skip.flat = true
	_skip.focus_mode = Control.FOCUS_NONE
	_skip.tooltip_text = _tr("TUT_SKIP", "Skip")
	_skip.add_theme_color_override("font_color", GOLD)
	_skip.add_theme_color_override("font_hover_color", GOLD_BRIGHT)
	_skip.pressed.connect(func() -> void: skip_pressed.emit())
	row.add_child(_skip)
	add_child(_pill)
	_pill.visible = false
	resized.connect(_layout)


## Wire to a director: prompts show and hide themselves, the skip button skips.
func bind(d: Region1TutorialDirector) -> void:
	director = d
	d.prompt_shown.connect(show_prompt)
	d.prompt_hidden.connect(hide_prompt)
	skip_pressed.connect(d.skip_current)


func set_hud_anchor(anchor_name: StringName, screen_pos: Vector2) -> void:
	_anchors[String(anchor_name)] = screen_pos


func anchor_pos(anchor_name: String) -> Vector2:
	if _anchors.has(anchor_name):
		return _anchors[anchor_name]
	var f: Vector2 = DEFAULT_ANCHORS.get(anchor_name, DEFAULT_ANCHORS["center"])
	return f * size


func show_prompt(_id: StringName, p: Dictionary) -> void:
	prompt = p
	var text := _tr(String(p.get("text_key", "")), String(p.get("text_en", "")))
	_label.text = text
	_target_alpha = 1.0
	_done_flash = 0.0
	_t = 0.0
	_pill.visible = true
	_layout()


func hide_prompt(_id: StringName, reason: StringName) -> void:
	_target_alpha = 0.0
	if reason == &"done":
		_done_flash = 1.0


func _tr(key: String, fallback: String) -> String:
	if key == "":
		return fallback
	var s := tr(key)
	return fallback if s == key else s


func _ui_scale() -> float:
	return clampf(size.y / 1080.0, 0.5, 2.0) if size.y > 0.0 else 1.0


func _layout() -> void:
	if prompt.is_empty() or _pill == null:
		return
	var k := _ui_scale()
	_label.add_theme_font_size_override("font_size", int(round(40.0 * k)))
	_skip.add_theme_font_size_override("font_size", int(round(34.0 * k)))
	_skip.custom_minimum_size = Vector2(SKIP_SIZE, SKIP_SIZE) * maxf(k, 1.0)
	_pill.reset_size()
	var sz := _pill.get_combined_minimum_size()
	if bool(prompt.get("plain", false)):
		# A text-only hint (realm_encounters.gd): no ring, no gesture, high and centred.
		_pill.position = Vector2(clampf((size.x - sz.x) * 0.5, 16.0, maxf(16.0, size.x - sz.x - 16.0)), size.y * 0.16)
		return
	var a := anchor_pos(String(prompt.get("anchor", "center")))
	# Above the anchor; below it near the top edge, and below the big glyph for "trace".
	var below := a.y <= size.y * 0.3 or String(prompt.get("touch", "")) == "trace"
	var gap := (140.0 if String(prompt.get("touch", "")) == "trace" else 110.0) * k
	var y := a.y + gap if below else a.y - 120.0 * k - sz.y
	var x := clampf(a.x - sz.x * 0.5, 16.0, size.x - sz.x - 16.0)
	_pill.position = Vector2(x, clampf(y, 16.0, size.y - sz.y - 16.0))


func _process(delta: float) -> void:
	_t += delta
	_alpha = move_toward(_alpha, _target_alpha, delta * 5.0)
	_done_flash = maxf(0.0, _done_flash - delta * 2.0)
	_pill.modulate.a = _alpha
	_skip.disabled = _alpha < 0.5
	if _alpha <= 0.0 and _done_flash <= 0.0 and _target_alpha == 0.0:
		_pill.visible = false
	queue_redraw()


func _draw() -> void:
	if prompt.is_empty() or bool(prompt.get("plain", false)) or (_alpha <= 0.01 and _done_flash <= 0.0):
		return
	var k := _ui_scale()
	var a := anchor_pos(String(prompt.get("anchor", "center")))
	var gold := Color(GOLD_BRIGHT, _alpha)
	# Pulsing ring on the HUD element.
	var pulse := fmod(_t, 1.2) / 1.2
	draw_arc(a, (46.0 + 26.0 * pulse) * k, 0.0, TAU, 48, Color(GOLD_BRIGHT, _alpha * (1.0 - pulse)), 4.0 * k, true)
	draw_arc(a, 44.0 * k, 0.0, TAU, 48, Color(GOLD, _alpha * 0.9), 3.0 * k, true)
	match String(prompt.get("touch", "tap")):
		"drag":
			var off := Vector2(0, -1).rotated(sin(_t * 1.6) * 0.9) * 48.0 * k
			_finger(a + off, k, gold)
			_arrow(a, a + off * 1.8, k, Color(GOLD, _alpha * 0.8))
		"swipe":
			var s := fmod(_t, 1.4) / 1.4
			var from := a + Vector2(-130, 0) * k
			var to := a + Vector2(130, 0) * k
			_arrow(from, to, k, Color(GOLD, _alpha * 0.7))
			_finger(from.lerp(to, ease(s, 0.5)), k, gold)
		"hold":
			var h := fmod(_t, 1.6) / 1.6
			draw_arc(a, 30.0 * k, -PI / 2.0, -PI / 2.0 + TAU * h, 40, gold, 6.0 * k, true)
			_finger(a, k, gold)
		"trace":
			# A three-stroke glyph (down, across, up) with a dot tracing it.
			var pts := PackedVector2Array([a + Vector2(-80, -110) * k, a + Vector2(-80, 80) * k,
				a + Vector2(80, 80) * k, a + Vector2(80, -110) * k])
			for i in pts.size() - 1:
				_dashed(pts[i], pts[i + 1], k, Color(GOLD, _alpha * 0.7))
			var tt := fmod(_t, 2.4) / 2.4 * 3.0
			var seg := mini(int(tt), 2)
			_finger(pts[seg].lerp(pts[seg + 1], tt - seg), k, gold)
		_:
			var r := fmod(_t, 0.9) / 0.9
			draw_arc(a, 20.0 * k + 30.0 * k * r, 0.0, TAU, 32, Color(GOLD_BRIGHT, _alpha * (1.0 - r)), 3.0 * k, true)
			_finger(a + Vector2(0, -6.0 * k * (1.0 - r)), k, gold)
	if _done_flash > 0.0:
		# Satisfying "learnt it" flash: a bright ring and a tick.
		var f := _done_flash
		draw_arc(a, (44.0 + 60.0 * (1.0 - f)) * k, 0.0, TAU, 48, Color(GOLD_BRIGHT, f), 6.0 * k, true)
		draw_polyline(PackedVector2Array([a + Vector2(-18, 0) * k, a + Vector2(-5, 14) * k, a + Vector2(20, -14) * k]),
			Color(GOLD_BRIGHT, f), 7.0 * k, true)


func _finger(p: Vector2, k: float, c: Color) -> void:
	draw_circle(p + Vector2(3, 4) * k, 17.0 * k, Color(0, 0, 0, c.a * 0.35))
	draw_circle(p, 17.0 * k, Color(TEXT, c.a * 0.95))
	draw_arc(p, 17.0 * k, 0.0, TAU, 32, c, 3.0 * k, true)


func _arrow(from: Vector2, to: Vector2, k: float, c: Color) -> void:
	if from.distance_to(to) < 4.0:
		return
	draw_line(from, to, c, 4.0 * k, true)
	var d := (to - from).normalized()
	draw_line(to, to - d.rotated(0.5) * 16.0 * k, c, 4.0 * k, true)
	draw_line(to, to - d.rotated(-0.5) * 16.0 * k, c, 4.0 * k, true)


func _dashed(from: Vector2, to: Vector2, k: float, c: Color) -> void:
	var n := int(from.distance_to(to) / (14.0 * k))
	for i in n:
		if i % 2 == 0:
			draw_line(from.lerp(to, float(i) / n), from.lerp(to, float(i + 1) / n), c, 5.0 * k, true)
