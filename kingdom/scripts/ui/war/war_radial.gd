extends Control
## The radial behaviour menu (rulebook §5): after dragging a piece to a place, pick what it should DO there.
## Eight primary behaviours in a ring, a centre button for the other eight, a card with the move estimate.
## Big touch targets; a tap anywhere outside cancels.

signal picked(behavior: String)
signal cancelled

const AF := preload("res://scripts/ui/ashes_frame.gd")
const Kit := preload("res://scripts/ui/gamemenu/gm_kit.gd")
const WarUnits := preload("res://scripts/realm/war_units.gd")
const BTN := Vector2(112, 64)
const RING := 158.0

var _more := false
var _center := Vector2.ZERO
var _bounds := Rect2()
var _info := ""
var _title := ""
var _preferred := "advance"
var _enabled := Callable()
var _nodes: Array = []


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


## center: where the ring opens (canvas px); bounds: the canvas rect; info: estimate text;
## enabled: Callable(behavior) -> bool (behaviours that cannot be used right now are greyed).
func open_at(center: Vector2, bounds: Rect2, title: String, info: String, preferred: String, enabled: Callable) -> void:
	_bounds = bounds
	_info = info
	_title = title
	_preferred = preferred
	_enabled = enabled
	_more = false
	var m := RING + BTN.x * 0.5 + 8.0
	_center = Vector2(clampf(center.x, bounds.position.x + m, maxf(bounds.end.x - m, bounds.position.x + m)),
		clampf(center.y, bounds.position.y + RING + BTN.y * 0.5 + 8.0, maxf(bounds.end.y - RING - BTN.y * 0.5 - 70.0, bounds.position.y + RING + BTN.y * 0.5 + 8.0)))
	visible = true
	_build()


func close_menu() -> void:
	visible = false
	Kit.clear(self)
	_nodes.clear()


func _gui_input(e: InputEvent) -> void:
	if not visible:
		return
	var tap := false
	if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
		tap = true
	elif e is InputEventScreenTouch and (e as InputEventScreenTouch).pressed:
		tap = true
	if tap:
		close_menu()
		cancelled.emit()
		accept_event()


func _build() -> void:
	Kit.clear(self)
	_nodes.clear()
	var ids: Array = WarUnits.MENU_MORE if _more else WarUnits.MENU_PRIMARY
	var n := ids.size()
	for i in n:
		var a := -PI / 2.0 + TAU * float(i) / float(n)
		var c := _center + Vector2(cos(a), sin(a)) * RING
		var id: String = ids[i]
		var ok := not _enabled.is_valid() or bool(_enabled.call(id))
		var b := _button(String((WarUnits.behaviour(id) as Dictionary)["name"]), id == _preferred and ok, not ok)
		b.position = c - BTN * 0.5
		if ok:
			b.pressed.connect(_pick.bind(id))
		add_child(b)
	var mid := _button("Back" if _more else "More...", false, false)
	mid.size = Vector2(96, 96)
	mid.custom_minimum_size = Vector2(96, 96)
	mid.position = _center - Vector2(48, 48)
	mid.pressed.connect(_toggle_more)
	add_child(mid)
	# estimate card
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", Kit.box(Color(0.03, 0.028, 0.025, 0.94), AF.GOLD, 4, 10))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.add_child(Kit.lbl(_title, 19, AF.GOLD_BRIGHT, false, "title"))
	for line in _info.split("\n"):
		v.add_child(Kit.lbl(line, 15, AF.TEXT))
	var x := Kit.button("Cancel", false, 48.0, 16)
	x.pressed.connect(func() -> void:
		close_menu()
		cancelled.emit())
	v.add_child(x)
	card.add_child(v)
	add_child(card)
	card.size = Vector2(330, 10)
	var below := _center.y + RING + BTN.y * 0.5 + 10.0
	var h := 100.0 + 20.0 * float(_info.split("\n").size())
	var py := below if below + h < _bounds.end.y else _center.y - RING - BTN.y * 0.5 - 10.0 - h
	card.position = Vector2(clampf(_center.x - 165.0, _bounds.position.x + 4.0, _bounds.end.x - 334.0), py)


func _button(text: String, primary: bool, disabled: bool) -> Button:
	var b := Kit.button(text, primary, BTN.y, 16)
	b.custom_minimum_size = BTN
	b.size = BTN
	b.disabled = disabled
	b.clip_text = true
	return b


func _toggle_more() -> void:
	_more = not _more
	_build()


func _pick(id: String) -> void:
	close_menu()
	picked.emit(id)


func _draw() -> void:
	if visible:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.38))
		draw_arc(_center, RING, 0, TAU, 60, Color(AF.GOLD, 0.35), 2.0, true)
