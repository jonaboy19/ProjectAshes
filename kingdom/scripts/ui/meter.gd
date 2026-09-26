class_name Meter
extends Control
## Slim rounded bar (health, stamina, magicules). Drawn directly so its height
## is exactly what you ask for; the fill eases toward the value and a pale
## "recent loss" ghost trails behind it.

var max_value := 100.0:
	set(v):
		max_value = maxf(v, 0.001)
		queue_redraw()
var value := 100.0:
	set(v):
		value = v
		set_process(true)
var color := Color.WHITE
var _shown := 100.0
var _ghost := 100.0


func _init(fill: Color = Color.WHITE, bar_size := Vector2(268, 8)) -> void:
	color = fill
	custom_minimum_size = bar_size
	size = bar_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE


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
	var r := size.y * 0.5
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.45)
	bg.set_corner_radius_all(int(r))
	bg.anti_aliasing = true
	draw_style_box(bg, Rect2(Vector2.ZERO, size))
	for pair in [[_ghost, Color(1, 1, 1, 0.35)], [_shown, color]]:
		var w := size.x * clampf(float(pair[0]) / max_value, 0.0, 1.0)
		if w < 1.0:
			continue
		var sb := StyleBoxFlat.new()
		sb.bg_color = pair[1]
		sb.set_corner_radius_all(int(r))
		sb.anti_aliasing = true
		draw_style_box(sb, Rect2(Vector2.ZERO, Vector2(maxf(w, size.y), size.y)))
