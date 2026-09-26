class_name VirtualJoystick
extends Control
## Floating thumbstick for the left side of the screen. Tracks its own touch index
## so it works while the other thumb presses buttons or turns the camera.

signal moved(vector: Vector2)

const RADIUS := 90.0
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


func _reset() -> void:
	_rest_center = Vector2(RADIUS + 70.0, size.y - RADIUS - 70.0)
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
	var offset := (pos - _center).limit_length(RADIUS)
	_knob = _center + offset
	output = offset / RADIUS
	moved.emit(output)
	queue_redraw()


func _draw() -> void:
	draw_circle(_center, RADIUS, Color(0, 0, 0, 0.28))
	draw_arc(_center, RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.45), 3.0, true)
	draw_circle(_knob, KNOB, Color(1, 0.93, 0.85, 0.75))
