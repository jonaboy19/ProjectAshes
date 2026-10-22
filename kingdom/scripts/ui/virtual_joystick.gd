class_name VirtualJoystick
extends Control
## Floating thumbstick for the left side of the screen. Tracks its own touch index
## so it works while the other thumb presses buttons or turns the camera.

const AF := preload("res://scripts/ui/ashes_frame.gd")

signal moved(vector: Vector2)

const RADIUS := 90.0
## Settings screen "Joystick Size" (0.6-1.4), set by the HUD.
var size_scale := 1.0
const KNOB := 42.0

var output := Vector2.ZERO
var _touch_index := -1
var _center := Vector2.ZERO
var _knob := Vector2.ZERO
var _rest_center := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(_reset)
	_reset()


func _r() -> float:
	return RADIUS * size_scale


func _reset() -> void:
	_rest_center = Vector2(_r() + 70.0, size.y - _r() - 70.0)
	if _touch_index == -1:
		_center = _rest_center
		_knob = _center
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _touch_index == -1:
			_touch_index = event.index
			_center = event.position
			_update(event.position)
		elif not event.pressed and event.index == _touch_index:
			_touch_index = -1
			_center = _rest_center
			_update(_center)
		accept_event()
	elif event is InputEventScreenDrag and event.index == _touch_index:
		_update(event.position)
		accept_event()


func _update(pos: Vector2) -> void:
	var offset := (pos - _center).limit_length(_r())
	_knob = _center + offset
	output = offset / _r()
	moved.emit(output)
	queue_redraw()


func _draw() -> void:
	var active := _touch_index != -1
	draw_circle(_center, _r(), Color(0.04, 0.035, 0.03, 0.44 if active else 0.3))
	draw_arc(_center, _r(), 0, TAU, 64, Color(AF.GOLD, 0.85 if active else 0.6), 2.5, true)
	draw_arc(_center, _r() - 6.0, 0, TAU, 64, Color(AF.GOLD, 0.2), 1.0, true)
	# Four small chevrons on the ring, like the user's joystick.
	for i in 4:
		var d := Vector2.from_angle(i * PI * 0.5)
		var n := Vector2(-d.y, d.x)
		var p := _center + d * (_r() - 16.0)
		draw_polyline(PackedVector2Array([p - d * 4.0 + n * 6.0, p + d * 3.0, p - d * 4.0 - n * 6.0]), Color(AF.TEXT, 0.5), 2.0, true)
	if output.length() > 0.05:
		# Direction arc toward the push.
		var a := output.angle()
		draw_arc(_center, _r() - 3.0, a - 0.5, a + 0.5, 24, AF.GOLD_BRIGHT, 4.0, true)
	draw_circle(_knob, KNOB + 3.0, Color(0, 0, 0, 0.3))
	draw_circle(_knob, KNOB, Color(0.93, 0.9, 0.82, 0.8 if active else 0.6))
	draw_arc(_knob, KNOB - 1.0, 0, TAU, 48, AF.GOLD, 2.0, true)
