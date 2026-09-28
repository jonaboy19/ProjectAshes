extends Control
## Cinematic "place discovered" title: a dark band across the upper third, the
## place name in large serif capitals that slowly spread apart, gold rules with
## a diamond either side and the kind underneath. 3.5 s: fade in, hold, fade out.
## Discoveries that arrive while one is showing wait their turn.

const DURATION := 3.5
const FADE_IN := 0.7
const FADE_OUT := 1.0

var _queue: Array[Dictionary] = []
var _title := ""
var _subtitle := ""
var _kicker := ""
var _t := -1.0
var _title_font: Font
var _body_font: Font


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_font = UITheme.title_font_weight(700)
	_body_font = UITheme.title_font_weight(500)
	set_process(false)


## Queues a banner. `kicker` is the small line above the name ("Discovered").
func show_place(title: String, subtitle: String, kicker := "Discovered") -> void:
	_queue.append({"title": title, "subtitle": subtitle, "kicker": kicker})
	if _t < 0.0:
		_next()


func is_showing() -> bool:
	return _t >= 0.0


func _next() -> void:
	if _queue.is_empty():
		_t = -1.0
		set_process(false)
		queue_redraw()
		return
	var d: Dictionary = _queue.pop_front()
	_title = String(d["title"]).to_upper()
	_subtitle = String(d["subtitle"]).to_upper()
	_kicker = String(d["kicker"]).to_upper()
	_t = 0.0
	set_process(true)


func _process(delta: float) -> void:
	_t += delta
	if _t >= DURATION:
		_next()
	queue_redraw()


func _alpha() -> float:
	if _t < 0.0:
		return 0.0
	var a := smoothstep(0.0, FADE_IN, _t)
	return a * (1.0 - smoothstep(DURATION - FADE_OUT, DURATION, _t))


func _draw() -> void:
	var a := _alpha()
	if a <= 0.001:
		return
	var vw := size
	var scale_k := clampf(vw.x / 1280.0, 0.7, 1.4)
	var cy := vw.y * 0.3
	var band_h := 150.0 * scale_k
	# Band: transparent at the ends, dark in the middle; horizontal gradient via a quad strip.
	var band := Color(0.02, 0.025, 0.045, 0.62 * a)
	var clear := Color(band, 0.0)
	var xs := [0.0, vw.x * 0.22, vw.x * 0.78, vw.x]
	var cols := [clear, band, band, clear]
	for i in 3:
		var quad := PackedVector2Array([Vector2(xs[i], cy - band_h * 0.5), Vector2(xs[i + 1], cy - band_h * 0.5),
			Vector2(xs[i + 1], cy + band_h * 0.5), Vector2(xs[i], cy + band_h * 0.5)])
		draw_polygon(quad, PackedColorArray([cols[i], cols[i + 1], cols[i + 1], cols[i]]))
	# Title: letters spread from tight to airy over the whole banner.
	var title_size := int(58 * scale_k)
	var spread := lerpf(2.0, 9.0, ease(clampf(_t / DURATION, 0.0, 1.0), 0.4)) * scale_k
	var widths := PackedFloat32Array()
	var total := 0.0
	for ch in _title:
		var cw := _title_font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size).x
		widths.append(cw)
		total += cw + spread
	total -= spread
	var x := vw.x * 0.5 - total * 0.5
	var base_y := cy + title_size * 0.3
	var rise := (1.0 - smoothstep(0.0, FADE_IN * 1.4, _t)) * 10.0 * scale_k
	for i in _title.length():
		var ch := _title[i]
		var p := Vector2(x, base_y + rise)
		draw_string(_title_font, p + Vector2(0, 3), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size, Color(0, 0, 0, 0.55 * a))
		draw_string(_title_font, p, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size, Color(UITheme.TEXT, a))
		x += widths[i] + spread
	# Kicker above, subtitle below, gold rules with diamonds either side of the subtitle.
	var kicker := _kicker
	var k_size := int(15 * scale_k)
	var kw := _spaced_width(kicker, k_size, 5.0 * scale_k)
	_draw_spaced(kicker, Vector2(vw.x * 0.5 - kw * 0.5, cy - title_size * 0.62), k_size, 5.0 * scale_k,
		Color(UITheme.ACCENT, 0.9 * a))
	var s_size := int(18 * scale_k)
	var sw := _spaced_width(_subtitle, s_size, 4.0 * scale_k)
	var sy := cy + title_size * 0.95
	_draw_spaced(_subtitle, Vector2(vw.x * 0.5 - sw * 0.5, sy), s_size, 4.0 * scale_k, Color(UITheme.TEXT_DIM, UITheme.TEXT_DIM.a * a))
	var grow := ease(smoothstep(0.1, FADE_IN + 0.5, _t), 0.5)
	var rule_len := 150.0 * scale_k * grow
	var ry := sy - s_size * 0.35
	var gap := sw * 0.5 + 18.0 * scale_k
	for side: float in [-1.0, 1.0]:
		var inner := Vector2(vw.x * 0.5 + side * gap, ry)
		var outer := inner + Vector2(side * rule_len, 0)
		draw_line(inner, outer, Color(UITheme.ACCENT, 0.85 * a), 1.5, true)
		var dm := inner + Vector2(side * -2.0, 0)
		var r := 4.5 * scale_k
		draw_colored_polygon(PackedVector2Array([dm + Vector2(0, -r), dm + Vector2(r, 0), dm + Vector2(0, r), dm + Vector2(-r, 0)]),
			Color(UITheme.ACCENT, a))


func _spaced_width(text: String, font_size: int, spacing: float) -> float:
	var total := 0.0
	for ch in text:
		total += _body_font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + spacing
	return maxf(0.0, total - spacing)


func _draw_spaced(text: String, pos: Vector2, font_size: int, spacing: float, color: Color) -> void:
	var x := pos.x
	for ch in text:
		draw_string(_body_font, Vector2(x, pos.y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
		x += _body_font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + spacing
