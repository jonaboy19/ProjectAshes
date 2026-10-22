extends VBoxContainer
## The tiny mobile interaction for one work task (scripts/realm/work.gd): a tap-timing bar, a
## hold-and-release bar, or a short list of choices. Emits `finished(quality, choice)` once.
## No _process while idle: it only runs for the seconds a bar is moving.

signal finished(quality: float, choice: int)

const AF := preload("res://scripts/ui/ashes_frame.gd")
const Work := preload("res://scripts/realm/work.gd")
const BAR_W := 560.0
const BAR_H := 40.0

var task: Dictionary = {}
var _kind := ""
var _t := 0.0
var _fill := 0.0
var _holding := false
var _done := false
var _marker: ColorRect
var _zone: ColorRect
var _fill_rect: ColorRect
var _hint: Label
var _speed := 1.0
var _bw := BAR_W      # bar width; a narrow (portrait) screen passes task["bar_w"] to shrink it


func setup(t: Dictionary) -> void:
	task = t
	_bw = minf(float(t.get("bar_w", BAR_W)), BAR_W)
	_kind = String(t["widget"])
	add_theme_constant_override("separation", 10)
	set_process(false)
	match _kind:
		"timing":
			_build_bar(false)
		"hold":
			_build_bar(true)
		_:
			_build_choices()


func _bar() -> Control:
	var track := Control.new()
	track.custom_minimum_size = Vector2(_bw, BAR_H)
	track.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.6)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	track.add_child(bg)
	var edge := ReferenceRect.new()
	edge.border_color = AF.GOLD_DIM
	edge.editor_only = false
	edge.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	track.add_child(edge)
	var w := float(task["zone"])
	var at := float(task["zone_at"])
	_zone = ColorRect.new()
	_zone.color = Color(AF.GOLD.r, AF.GOLD.g, AF.GOLD.b, 0.45)
	_zone.position = Vector2((at - w * 0.5) * _bw, 0)
	_zone.size = Vector2(w * _bw, BAR_H)
	track.add_child(_zone)
	var centre := ColorRect.new()
	centre.color = AF.GOLD_BRIGHT
	centre.position = Vector2(at * _bw - 1.0, 0)
	centre.size = Vector2(2, BAR_H)
	track.add_child(centre)
	return track


func _build_bar(hold: bool) -> void:
	_speed = 0.75 + float(task["diff"]) * 0.9
	var track := _bar()
	add_child(track)
	if hold:
		_fill_rect = ColorRect.new()
		_fill_rect.color = Color(AF.TEXT.r, AF.TEXT.g, AF.TEXT.b, 0.35)
		_fill_rect.size = Vector2(0, BAR_H)
		track.add_child(_fill_rect)
	_marker = ColorRect.new()
	_marker.color = AF.TEXT
	_marker.size = Vector2(6, BAR_H + 10)
	_marker.position = Vector2(-3, -5)
	track.add_child(_marker)
	_hint = AF.label("Hold to fill, release in the gold." if hold else "Tap when the marker is in the gold.", 16, AF.TEXT_DIM, true)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_hint)
	var b := AF.gold_button("Hold" if hold else "Strike")
	b.custom_minimum_size = Vector2(0, 64)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if hold:
		b.button_down.connect(_hold_down)
		b.button_up.connect(_hold_up)
	else:
		b.pressed.connect(_tap)
	add_child(b)
	set_process(true)


func _build_choices() -> void:
	var opts: Array = task["options"]
	for i in opts.size():
		var o: Dictionary = opts[i]
		var b := Button.new()
		b.text = "%s%s" % [String(o["text"]), _hint_for(o)]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size = Vector2(0, 54)
		b.add_theme_font_size_override("font_size", 19)
		b.add_theme_stylebox_override("normal", AF.slot())
		b.pressed.connect(_pick.bind(i))
		add_child(b)


func _hint_for(o: Dictionary) -> String:
	var bits: Array = []
	if int(o.get("tip", 0)) != 0:
		bits.append("%+dg" % int(o["tip"]))
	var rg := float(o.get("regard", 0.0))
	if rg > 0.3:
		bits.append("liked")
	elif rg < -0.3:
		bits.append("resented")
	return "" if bits.is_empty() else "   (%s)" % ", ".join(bits)


func _process(delta: float) -> void:
	if _done:
		return
	if _kind == "timing":
		_t += delta * _speed
		_marker.position.x = pingpong(_t, 1.0) * _bw - 3.0
	elif _kind == "hold" and _holding:
		_fill = minf(1.0, _fill + delta * _speed * 0.55)
		_fill_rect.size.x = _fill * _bw
		_marker.position.x = _fill * _bw - 3.0
		if _fill >= 1.0:
			_hold_up()


func _tap() -> void:
	if _done:
		return
	_finish(Work.timing_quality(pingpong(_t, 1.0), float(task["zone_at"]), float(task["zone"])), -1)


func _hold_down() -> void:
	_holding = true


func _hold_up() -> void:
	if _done or not _holding:
		return
	_finish(Work.hold_quality(_fill, float(task["zone_at"]), float(task["zone"])), -1)


func _pick(i: int) -> void:
	if not _done:
		_finish(float((task["options"] as Array)[i]["q"]), i)


func _finish(q: float, choice: int) -> void:
	_done = true
	set_process(false)
	finished.emit(q, choice)
