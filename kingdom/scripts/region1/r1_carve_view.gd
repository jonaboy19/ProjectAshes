extends Control
## The runecarving canvas (package C3, mechanic N1): the player draws a glyph on the face of a stone
## with a finger or the mouse, the RuneGesture recognizer names it, and the stone takes it.
## A light full-screen overlay: a slate stone face, a glowing trail, the four glyph cards as a guide.
##
##   var v := preload("res://scripts/region1/r1_carve_view.gd").new()
##   hud.add_child(v)
##   v.open(recognizer, "Miller's Stone", ["ward", "lure", "alarm", "bless"])
##   v.carved.connect(func(glyph, result): ...)       # glyph accepted (or chosen by the fallback)
##   v.closed.connect(...)
##
## Never locks the player in: the close button and Esc / back always work, and after three failed
## attempts a "Choose a glyph" row appears so nobody is stuck on a gesture they cannot draw.

signal carved(glyph: String, result: Dictionary)
signal closed

const AF := preload("res://scripts/ui/ashes_frame.gd")
const SETTLE_SECONDS := 0.85
const TRAIL_FADE := 2.4

var recognizer: RuneGesture
var stone_name := ""
var allowed: PackedStringArray = PackedStringArray()
var assist := 0.0
var last_result: Dictionary = {}

var _strokes: Array[PackedVector2Array] = []
var _current := PackedVector2Array()
var _drawing := false
var _idle := 0.0
var _fails := 0
var _message := ""
var _message_color := Color.WHITE
var _flash := 0.0
var _flash_color := Color.WHITE
var _stone_rect := Rect2()
var _title: Label
var _sub: Label
var _choose_row: HBoxContainer
var _close_btn: Button
var _accepted_glyph := ""
var _accepted_at := 0.0
var _t := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = AF.theme()
	visible = false
	_title = Label.new()
	_title.add_theme_font_override("font", AF.wfont(700))
	_title.add_theme_font_size_override("font_size", 28)
	_title.add_theme_color_override("font_color", AF.GOLD_BRIGHT)
	_title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_title.position = Vector2(0, 26)
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title)
	_sub = Label.new()
	_sub.add_theme_font_override("font", AF.font())
	_sub.add_theme_font_size_override("font_size", 17)
	_sub.add_theme_color_override("font_color", AF.TEXT_DIM)
	_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_sub)
	_close_btn = AF.gold_button("Step back")
	_close_btn.custom_minimum_size = Vector2(150, 48)
	_close_btn.pressed.connect(close)
	add_child(_close_btn)
	_choose_row = HBoxContainer.new()
	_choose_row.add_theme_constant_override("separation", 10)
	_choose_row.visible = false
	add_child(_choose_row)
	resized.connect(_layout)


func open(rec: RuneGesture, p_stone_name: String, p_allowed: Array = ["ward", "lure", "alarm", "bless"], p_assist := 0.0) -> void:
	recognizer = rec
	stone_name = p_stone_name
	allowed = PackedStringArray(p_allowed)
	assist = p_assist
	_strokes.clear()
	_current = PackedVector2Array()
	_fails = 0
	_message = "Draw a glyph on the stone."
	_message_color = AF.TEXT_DIM
	_accepted_glyph = ""
	_choose_row.visible = false
	_title.text = "Carve: %s" % stone_name
	_sub.text = "Ward: a diamond   Lure: an arrowhead and shaft   Alarm: a zigzag   Bless: a cross"
	visible = true
	_layout()
	_build_choose_row()
	queue_redraw()


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func _layout() -> void:
	var s := size
	if s.x < 10.0:
		return
	var w := minf(s.x * 0.62, s.y * 0.95)
	var h := s.y * 0.6
	_stone_rect = Rect2((s.x - w) * 0.5, s.y * 0.17, w, h)
	_title.size = Vector2(s.x, 40)
	_title.position = Vector2(0, 28)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub.size = Vector2(s.x, 26)
	_sub.position = Vector2(0, 72)
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_close_btn.position = Vector2(s.x - 174.0, 24.0)
	_choose_row.position = Vector2((s.x - _choose_row.size.x) * 0.5, _stone_rect.end.y + 52.0)


func _build_choose_row() -> void:
	for c in _choose_row.get_children():
		c.queue_free()
	for g: String in allowed:
		var b := Button.new()
		b.text = String(recognizer.glyph_info(g).get("name", g.capitalize()))
		b.custom_minimum_size = Vector2(120, 48)
		b.pressed.connect(_choose.bind(g))
		_choose_row.add_child(b)
	_choose_row.call_deferred("reset_size")
	_layout.call_deferred()


func _choose(glyph: String) -> void:
	_accept(glyph, {"glyph": glyph, "score": 1.0, "accepted": true, "chosen": true})


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 1.6)
	if _accepted_glyph != "":
		if _t - _accepted_at > 1.3:
			var g := _accepted_glyph
			_accepted_glyph = ""
			close()
			carved.emit(g, last_result)
		queue_redraw()
		return
	if not _drawing and not _strokes.is_empty():
		_idle += delta
		if _idle >= SETTLE_SECONDS:
			_recognize()
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if _accepted_glyph != "":
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		if (event as InputEventMouseButton).pressed:
			_begin((event as InputEventMouseButton).position)
		else:
			_end()
	elif event is InputEventMouseMotion and _drawing:
		_add_point((event as InputEventMouseMotion).position)
	elif event is InputEventScreenTouch:
		if (event as InputEventScreenTouch).pressed:
			_begin((event as InputEventScreenTouch).position)
		else:
			_end()
	elif event is InputEventScreenDrag and _drawing:
		_add_point((event as InputEventScreenDrag).position)


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _begin(p: Vector2) -> void:
	if not _stone_rect.grow(40.0).has_point(p):
		return
	_drawing = true
	_idle = 0.0
	_current = PackedVector2Array([p])


func _add_point(p: Vector2) -> void:
	if _current.is_empty() or p.distance_to(_current[_current.size() - 1]) > 3.0:
		_current.append(p)


func _end() -> void:
	if not _drawing:
		return
	_drawing = false
	if _current.size() >= 2:
		_strokes.append(_current)
	_current = PackedVector2Array()
	_idle = 0.0


func _recognize() -> void:
	var res := recognizer.recognize(_strokes, assist + 0.25 * minf(_fails, 3))
	last_result = res
	var id := String(res.get("id", ""))
	if bool(res.get("accepted", false)) and allowed.has(id):
		_accept(id, res)
		return
	_fails += 1
	_strokes.clear()
	match String(res.get("reason", "")):
		"too_small":
			_message = "Draw it bigger."
		"too_many_strokes":
			_message = "Too many strokes. Draw it again."
		"ambiguous":
			_message = "The stone cannot tell. Draw it slower."
		_:
			_message = "Nothing takes. Try again."
	_message_color = Color("ff9a7a")
	_flash = 1.0
	_flash_color = Color(1.0, 0.5, 0.35)
	if _fails >= 3:
		_choose_row.visible = true
		_message += "  Or choose a glyph below."


func _accept(glyph: String, res: Dictionary) -> void:
	last_result = res
	_accepted_glyph = glyph
	_accepted_at = _t
	var col := recognizer.glyph_color(glyph)
	var nm := String(recognizer.glyph_info(glyph).get("name", glyph.capitalize()))
	_message = "%s (%d%%)" % [nm, int(round(float(res.get("score", 1.0)) * 100.0))]
	_message_color = col
	_flash = 1.0
	_flash_color = col
	_choose_row.visible = false
	Audio.play_ui("pickup")


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.01, 0.01, 0.03, 0.72))
	var r := _stone_rect
	# The stone face: slate with a pale rim and faint moss.
	draw_rect(r.grow(10.0), Color(0.1, 0.1, 0.13))
	draw_rect(r, Color(0.23, 0.25, 0.3))
	for i in 7:
		var y := r.position.y + r.size.y * (float(i) + 0.5) / 7.0
		draw_line(Vector2(r.position.x + 12, y + sin(i * 2.3) * 6.0), Vector2(r.end.x - 12, y + cos(i * 1.7) * 6.0), Color(0, 0, 0, 0.07), 6.0)
	draw_rect(r, Color(AF.GOLD, 0.75), false, 2.0)
	if _flash > 0.0:
		draw_rect(r.grow(10.0), Color(_flash_color, 0.35 * _flash), false, 8.0 * _flash)
	# Faint ghost guides while the player has failed a few times.
	if _fails >= 2 and recognizer != null:
		for g: String in allowed:
			pass
	# The trail, glowing: a wide soft line under a bright thin one.
	var col := Color(0.45, 0.8, 1.0)
	if _accepted_glyph != "" and recognizer != null:
		col = recognizer.glyph_color(_accepted_glyph)
	for s: PackedVector2Array in _strokes:
		_trail(s, col)
	if _current.size() >= 2:
		_trail(_current, col)
	# Guide cards: the four glyphs, drawn small, along the bottom of the stone.
	if recognizer != null:
		var n := allowed.size()
		var cw := minf(r.size.x / maxf(1.0, float(n)), 120.0)
		var x0 := r.position.x + (r.size.x - cw * n) * 0.5
		for i in n:
			var cr := Rect2(x0 + cw * i + 8.0, r.end.y - cw * 0.85, cw - 16.0, cw * 0.7)
			var gc := recognizer.glyph_color(allowed[i])
			for st: PackedVector2Array in recognizer.glyph_strokes(allowed[i]):
				var pts := PackedVector2Array()
				for p in st:
					pts.append(cr.position + Vector2(p.x, p.y) * cr.size)
				if pts.size() >= 2:
					draw_polyline(pts, Color(gc, 0.45), 2.0, true)
	var font := AF.font()
	var fs := 22
	var tw := font.get_string_size(_message, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, Vector2((size.x - tw) * 0.5, r.end.y + 34.0), _message, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, _message_color)


func _trail(s: PackedVector2Array, col: Color) -> void:
	if s.size() < 2:
		return
	draw_polyline(s, Color(col, 0.22), 16.0, true)
	draw_polyline(s, Color(col, 0.5), 8.0, true)
	draw_polyline(s, Color(1, 1, 1, 0.92).lerp(col, 0.25), 3.0, true)
