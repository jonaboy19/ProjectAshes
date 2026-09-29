class_name AshsightHud
extends Control
## Ashsight on-screen UI (built in code, no theme or textures needed, sized for phones):
##   - title (site) and a soft caption for the current beat,
##   - a scrub bar under the thumb: play/pause, a draggable track with beat ticks, time, a
##     slow-motion toggle (1x / 0.5x / 0.25x), and a close button.
## It only emits signals; AshsightController wires them to the replay.
##
## Touch targets are at least 64 px on a 1080 px tall screen (the UI scales with the viewport).

signal seek_requested(t: float)
signal scrub_started
signal scrub_ended
signal play_toggled
signal speed_cycled
signal closed

const EMBER := Color(1.0, 0.72, 0.35)
const EMBER_DEEP := Color(1.0, 0.46, 0.18)
const CREAM := Color(1.0, 0.95, 0.84)
const PANEL := Color(0.13, 0.075, 0.04, 0.66)

var duration := 1.0
var time := 0.0
var playing := true
var speed := 1.0
var marks: Array = []   # [{t, label}]
var acts: Array = []    # [{t, actor, kind}]

var _title: Label
var _sub: Label
var _caption: Label
var _panel: PanelContainer
var _track: ScrubTrack
var _time_label: Label
var _play_btn: HudButton
var _speed_btn: HudButton
var _close_btn: HudButton
var _caption_alpha := 0.0
var _caption_text := ""
var _scrubbing := false
var _ui := 1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	_layout()


func _build() -> void:
	_title = _label(46, CREAM, self)
	_title.position = Vector2(40, 28)
	_sub = _label(26, EMBER, self)
	_sub.position = Vector2(42, 92)
	_caption = _label(38, CREAM, self)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.modulate.a = 0.0
	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL
	sb.set_corner_radius_all(30)
	sb.set_border_width_all(2)
	sb.border_color = Color(EMBER.r, EMBER.g, EMBER.b, 0.55)
	sb.content_margin_left = 22
	sb.content_margin_right = 26
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	sb.shadow_color = Color(0, 0, 0, 0.3)
	sb.shadow_size = 12
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	_panel.add_child(row)
	_play_btn = _button(0)
	_play_btn.pressed_signal.connect(func() -> void: play_toggled.emit())
	row.add_child(_play_btn)
	_track = ScrubTrack.new()
	_track.hud = self
	_track.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_track.custom_minimum_size = Vector2(200, 72)
	row.add_child(_track)
	_time_label = _label(28, CREAM)
	_time_label.custom_minimum_size = Vector2(150, 0)
	_time_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(_time_label)
	_speed_btn = _button(1)
	_speed_btn.pressed_signal.connect(func() -> void: speed_cycled.emit())
	row.add_child(_speed_btn)
	_close_btn = _button(2)
	_close_btn.pressed_signal.connect(func() -> void: closed.emit())
	_close_btn.custom_minimum_size = Vector2(72, 72)
	add_child(_close_btn)


func _label(size: int, color: Color, parent: Node = null) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.16, 0.09, 0.05, 0.95))
	l.add_theme_constant_override("outline_size", 9)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if parent != null:
		parent.add_child(l)
	return l


func _button(kind: int) -> HudButton:
	var b := HudButton.new()
	b.hud = self
	b.kind = kind
	b.custom_minimum_size = Vector2(96, 72) if kind == 1 else Vector2(72, 72)
	return b


func _layout() -> void:
	var vs := get_viewport_rect().size
	if vs.x < 8.0 or vs.y < 8.0:
		return
	position = Vector2.ZERO
	size = vs
	_ui = clampf(minf(vs.x, vs.y * 2.0) / 2000.0, 0.6, 1.6) if vs.x > vs.y else clampf(vs.x / 1000.0, 0.6, 1.4)
	var m := 40.0 * _ui
	_panel.position = Vector2(m, vs.y - 118.0 * _ui - m * 0.4)
	_panel.size = Vector2(vs.x - m * 2.0, 100.0 * _ui)
	_panel.scale = Vector2.ONE
	_title.position = Vector2(m, 24.0 * _ui)
	_sub.position = Vector2(m + 2, 24.0 * _ui + 62.0 * _ui)
	_title.add_theme_font_size_override("font_size", int(46.0 * _ui))
	_sub.add_theme_font_size_override("font_size", int(26.0 * _ui))
	_caption.add_theme_font_size_override("font_size", int(38.0 * _ui))
	_time_label.add_theme_font_size_override("font_size", int(28.0 * _ui))
	_caption.position = Vector2(m, _panel.position.y - 74.0 * _ui)
	_caption.size = Vector2(vs.x - m * 2.0, 60.0 * _ui)
	_close_btn.position = Vector2(vs.x - m - 72.0, 24.0 * _ui)


func set_incident(title: String, subtitle: String, dur: float, mark_list: Array, act_list: Array) -> void:
	_title.text = title
	_sub.text = subtitle
	duration = maxf(dur, 0.01)
	marks = mark_list
	acts = act_list
	_track.queue_redraw()


func set_state(t: float, is_playing: bool, spd: float) -> void:
	if get_viewport_rect().size != size:
		_layout()
	time = t
	playing = is_playing
	speed = spd
	_time_label.text = "%s / %s" % [_fmt(minf(t, duration)), _fmt(duration)]
	_track.queue_redraw()
	_play_btn.queue_redraw()
	_speed_btn.queue_redraw()
	# caption: the beat nearest to now, fading in and out
	var best := ""
	var bd := 1.6
	for m: Dictionary in marks:
		var d := absf(float(m["t"]) - t)
		if d < bd:
			bd = d
			best = String(m["label"])
	if best != _caption_text and best != "":
		_caption_text = best
		_caption.text = best.capitalize()
	var target := 1.0 - clampf(bd / 1.6, 0.0, 1.0) if best != "" else 0.0
	_caption_alpha = lerpf(_caption_alpha, target, 0.25)
	_caption.modulate.a = clampf(_caption_alpha * 1.6, 0.0, 1.0)


static func _fmt(s: float) -> String:
	var i := int(s)
	return "%d:%02d" % [i / 60, i % 60]


# --- inner controls -------------------------------------------------------------------------

class HudButton extends Control:
	signal pressed_signal
	var hud: AshsightHud
	var kind := 0   # 0 play/pause, 1 speed, 2 close
	var _down := false

	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			_down = (ev as InputEventMouseButton).pressed
			queue_redraw()
			if not _down:
				pressed_signal.emit()
			accept_event()

	func _draw() -> void:
		var r := size * 0.5
		var c := Vector2(r.x, r.y)
		var rad := minf(r.x, r.y)
		var fill := Color(1, 0.72, 0.35, 0.28 if not _down else 0.5)
		if kind == 1:
			draw_style_box(_pill(fill), Rect2(Vector2.ZERO, size))
			var txt := "1x" if is_equal_approx(hud.speed, 1.0) else ("0.5x" if is_equal_approx(hud.speed, 0.5) else "0.25x")
			var f := get_theme_default_font()
			var fs := int(size.y * 0.42)
			var w := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(f, Vector2(c.x - w * 0.5, c.y + fs * 0.35), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, CREAM)
			return
		draw_circle(c, rad, fill)
		draw_arc(c, rad - 1.0, 0.0, TAU, 40, Color(1, 0.72, 0.35, 0.7), 2.0, true)
		if kind == 0:
			if hud.playing:
				draw_rect(Rect2(c.x - rad * 0.32, c.y - rad * 0.36, rad * 0.22, rad * 0.72), CREAM)
				draw_rect(Rect2(c.x + rad * 0.10, c.y - rad * 0.36, rad * 0.22, rad * 0.72), CREAM)
			else:
				draw_colored_polygon(PackedVector2Array([Vector2(c.x - rad * 0.24, c.y - rad * 0.42),
					Vector2(c.x + rad * 0.44, c.y), Vector2(c.x - rad * 0.24, c.y + rad * 0.42)]), CREAM)
		else:
			var d := rad * 0.32
			draw_line(c + Vector2(-d, -d), c + Vector2(d, d), CREAM, 4.0, true)
			draw_line(c + Vector2(-d, d), c + Vector2(d, -d), CREAM, 4.0, true)

	func _pill(col: Color) -> StyleBoxFlat:
		var sb := StyleBoxFlat.new()
		sb.bg_color = col
		sb.set_corner_radius_all(int(size.y * 0.5))
		sb.set_border_width_all(2)
		sb.border_color = Color(1, 0.72, 0.35, 0.7)
		return sb


class ScrubTrack extends Control:
	var hud: AshsightHud
	var _drag := false

	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			var down := (ev as InputEventMouseButton).pressed
			if down and not _drag:
				_drag = true
				hud.scrub_started.emit()
				_seek((ev as InputEventMouseButton).position.x)
			elif not down and _drag:
				_drag = false
				hud.scrub_ended.emit()
			accept_event()
		elif ev is InputEventMouseMotion and _drag:
			_seek((ev as InputEventMouseMotion).position.x)
			accept_event()

	func _seek(x: float) -> void:
		var pad := 22.0
		var k := clampf((x - pad) / maxf(size.x - pad * 2.0, 1.0), 0.0, 1.0)
		hud.seek_requested.emit(k * (hud.duration + AshMemory.ASH_END_S))

	func _draw() -> void:
		var pad := 22.0
		var w := size.x - pad * 2.0
		var y := size.y * 0.5
		var total := hud.duration + AshMemory.ASH_END_S
		var k := clampf(hud.time / total, 0.0, 1.0)
		draw_line(Vector2(pad, y), Vector2(pad + w, y), Color(1, 0.95, 0.84, 0.22), 12.0, true)
		draw_line(Vector2(pad, y), Vector2(pad + w * k, y), AshsightHud.EMBER_DEEP, 12.0, true)
		draw_line(Vector2(pad, y), Vector2(pad + w * k, y - 1.0), Color(1, 0.86, 0.5, 0.9), 5.0, true)
		# beat ticks: diamonds for story beats, dots for actors' acts
		for m: Dictionary in hud.marks:
			var x := pad + w * clampf(float(m["t"]) / total, 0.0, 1.0)
			draw_colored_polygon(PackedVector2Array([Vector2(x, y - 15), Vector2(x + 9, y - 6), Vector2(x, y + 3), Vector2(x - 9, y - 6)]).duplicate(),
				AshsightHud.CREAM)
		for a: Dictionary in hud.acts:
			var x2 := pad + w * clampf(float(a["t"]) / total, 0.0, 1.0)
			draw_circle(Vector2(x2, y + 16), 4.0, AshsightHud.EMBER)
		var tx := pad + w * k
		draw_circle(Vector2(tx, y), 20.0, Color(0.13, 0.075, 0.04, 0.8))
		draw_circle(Vector2(tx, y), 16.0, AshsightHud.CREAM)
		draw_circle(Vector2(tx, y), 8.0, AshsightHud.EMBER_DEEP)
