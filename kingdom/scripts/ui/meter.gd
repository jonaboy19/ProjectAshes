class_name Meter
extends Control
## Slim gold-framed bar (health, stamina, magicules). Drawn directly so its height
## is exactly what you ask for; the fill eases toward the value and a pale
## "recent loss" ghost trails behind it. The fill has a lit top half like the
## user's HUD template (red health, gold stamina).

var max_value := 100.0:
	set(v):
		max_value = maxf(v, 0.001)
		queue_redraw()
var value := 100.0:
	set(v):
		value = v
		set_process(true)
var color := Color.WHITE
## Draw "42 / 100" centred on the bar (for bars tall enough to hold it).
var show_text := false
var _shown := 100.0
var _ghost := 100.0
var _trough := StyleBoxFlat.new()
var _fill := StyleBoxFlat.new()
var _gloss := StyleBoxFlat.new()
var _ghost_box := StyleBoxFlat.new()


func _init(fill: Color = Color.WHITE, bar_size := Vector2(268, 8)) -> void:
	color = fill
	custom_minimum_size = bar_size
	size = bar_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_trough.bg_color = Color(0.02, 0.018, 0.015, 0.78)
	_trough.border_color = Color(0.85, 0.66, 0.31, 0.55)
	_trough.set_border_width_all(1)
	_trough.anti_aliasing = true
	_ghost_box.bg_color = Color(1, 1, 1, 0.35)
	_ghost_box.anti_aliasing = true
	_fill.bg_color = fill
	_fill.anti_aliasing = true
	_gloss.bg_color = Color(1, 1, 1, 0.22)
	_gloss.anti_aliasing = true


func _ready() -> void:
	_shown = value
	_ghost = value


func _process(delta: float) -> void:
	_shown = lerpf(_shown, value, minf(1.0, delta * 14.0))
	_ghost = maxf(_shown, _ghost - max_value * 0.6 * delta) if _ghost > _shown else _shown
	if absf(_shown - value) < 0.05 and absf(_ghost - _shown) < 0.05:
		_shown = value
		_ghost = value
		set_process(false)
	queue_redraw()


func _draw() -> void:
	var r := int(minf(size.y * 0.5, 4.0))
	_trough.set_corner_radius_all(r)
	draw_style_box(_trough, Rect2(Vector2.ZERO, size))
	var inner := Rect2(Vector2(1, 1), size - Vector2(2, 2))
	if inner.size.y < 1.0:
		return
	var ir := int(minf(inner.size.y * 0.5, 3.0))
	for pass_i in 2:
		var v := _ghost if pass_i == 0 else _shown
		var w := inner.size.x * clampf(v / max_value, 0.0, 1.0)
		if w < 1.0:
			continue
		var rect := Rect2(inner.position, Vector2(maxf(w, inner.size.y), inner.size.y))
		if pass_i == 0:
			_ghost_box.set_corner_radius_all(ir)
			draw_style_box(_ghost_box, rect)
		else:
			_fill.bg_color = color
			_fill.set_corner_radius_all(ir)
			draw_style_box(_fill, rect)
			_gloss.set_corner_radius_all(ir)
			draw_style_box(_gloss, Rect2(rect.position + Vector2(0, 0), Vector2(rect.size.x, maxf(1.0, rect.size.y * 0.42))))
	if show_text and size.y >= 12.0:
		var f := ThemeDB.fallback_font
		var t := "%d / %d" % [int(round(value)), int(round(max_value))]
		var fs := int(size.y * 0.72)
		var tw := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var pos := Vector2((size.x - tw) * 0.5, size.y * 0.5 + fs * 0.36)
		draw_string_outline(f, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(0, 0, 0, 0.8))
		draw_string(f, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("f3e6c8"))
