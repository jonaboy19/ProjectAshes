extends Control
## Rune canvas (L8 test scene): draw a glyph on a stone face with a finger or the mouse.
##   * glowing stroke trail with sparks; the stone "carves" the recognized rune in its colour;
##   * result card: glyph, confidence, one bar per glyph, match time in ms;
##   * PRACTICE mode: a target rune with a guide to trace; streak and accuracy;
##   * ASSIST toggle (relaxed threshold), GUIDE toggle, CLEAR.
## Same input path for a finger, the mouse and the scripted demo (`--demo`).
##
##   Godot --path kingdom res://tools_qa/region1/rune_canvas.tscn                (play by hand)
##   Godot --path kingdom --write-movie out/frame.png --fixed-fps 30 --quit-after 540 \
##         --resolution 1280x720 res://tools_qa/region1/rune_canvas.tscn -- --demo
## Args after `--`: --demo (scripted strokes), --practice (start in practice mode), --seed=N.
## Never run windowed captures with --headless (black frames).

const AF := preload("res://scripts/ui/ashes_frame.gd")
const Gesture := preload("res://scripts/region1/rune_gesture.gd")

const BASE := Vector2(1280, 720)
const STONE := Rect2(40, 40, 760, 560)
const COMMIT_FAST := 0.32     # s after finger-up when the strokes already are a complete glyph
const COMMIT_SLOW := 0.9      # s to wait for a second stroke otherwise
const TRAIL := Color(0.62, 0.86, 1.0)

var rec = Gesture.new()
var strokes: Array[PackedVector2Array] = []      # committed-to-canvas strokes of the current attempt
var _cur := PackedVector2Array()
var _drawing := false
var _last_up := -1.0
var _pending := false
var _clock := 0.0
var _rng := RandomNumberGenerator.new()

var practice := false
var assist := false
var guide := true
var target_index := 0
var streak := 0
var best_streak := 0
var attempts := 0
var hits := 0
var conf_sum := 0.0

var last: Dictionary = {}          # last recognition result
var last_time := -10.0
var _message := "Draw a rune"
var _fade := {}                    # {t0, strokes, color, ok}
var _carve := {}                   # {t0, id, center, size, color}
var _sparks: Array = []            # [pos, vel, age, life, color]
var _ink: Control
var _ui := {}
var _demo := false
var _demo_steps: Array = []
var _demo_i := 0
var _demo_t := 0.0
var _demo_stroke := 0
var _demo_idx := 0
var _demo_pts: Array = []
var _scale := 1.0
var _off := Vector2.ZERO


func _ready() -> void:
	var seed_value := 7
	for a in OS.get_cmdline_user_args():
		if a == "--demo":
			_demo = true
		elif a == "--practice":
			practice = true
		elif a.begins_with("--seed="):
			seed_value = int(a.substr(7))
	_rng.seed = seed_value
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_ink = Control.new()
	_ink.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ink.set_anchors_preset(Control.PRESET_FULL_RECT)
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_ink.material = mat
	_ink.draw.connect(_draw_ink)
	add_child(_ink)
	_build_buttons()
	resized.connect(_on_resized)
	_on_resized()
	if _demo:
		_build_demo()


func _on_resized() -> void:
	_scale = minf(size.x / BASE.x, size.y / BASE.y)
	_off = (size - BASE * _scale) * 0.5
	_layout_buttons()
	queue_redraw()


## base-space point -> screen, and back
func _to_screen(p: Vector2) -> Vector2:
	return _off + p * _scale


func _to_base(p: Vector2) -> Vector2:
	return (p - _off) / _scale


func _stone_screen() -> Rect2:
	return Rect2(_to_screen(STONE.position), STONE.size * _scale)


# ============================================================================ buttons

func _build_buttons() -> void:
	for spec in [["clear", "Clear"], ["practice", "Practice"], ["assist", "Assist"], ["guide", "Guide"]]:
		var b := Button.new()
		b.text = spec[1]
		b.focus_mode = Control.FOCUS_NONE
		b.toggle_mode = spec[0] != "clear"
		b.add_theme_font_override("font", AF.title_font(600))
		b.add_theme_font_size_override("font_size", 22)
		b.add_theme_color_override("font_color", AF.TEXT)
		b.add_theme_color_override("font_pressed_color", AF.GOLD_BRIGHT)
		b.add_theme_color_override("font_hover_color", AF.GOLD_BRIGHT)
		for st in ["normal", "hover", "pressed"]:
			var sb: StyleBoxFlat = AF.panel(AF.PANEL_SOFT if st != "pressed" else Color(AF.GOLD.r, AF.GOLD.g, AF.GOLD.b, 0.28),
				AF.GOLD if st != "normal" else AF.GOLD_DIM, 6, 10)
			b.add_theme_stylebox_override(st, sb)
		add_child(b)
		_ui[spec[0]] = b
	_ui["clear"].pressed.connect(func() -> void: clear_canvas("Cleared"))
	_ui["practice"].toggled.connect(func(on: bool) -> void: set_practice(on))
	_ui["assist"].toggled.connect(func(on: bool) -> void: assist = on; queue_redraw())
	_ui["guide"].toggled.connect(func(on: bool) -> void: guide = on)
	_ui["guide"].set_pressed_no_signal(true)
	_ui["practice"].set_pressed_no_signal(practice)


func _layout_buttons() -> void:
	var names := ["clear", "practice", "assist", "guide"]
	var x := 40.0
	for i in names.size():
		var b: Button = _ui.get(names[i])
		if b == null:
			continue
		var w := 170.0 if i != 1 else 200.0
		b.position = _to_screen(Vector2(x, 622))
		b.size = Vector2(w, 66) * _scale
		x += w + 16.0


# ============================================================================ input (finger, mouse, demo)

func _gui_input(ev: InputEvent) -> void:
	if _demo:
		return
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed:
			begin_stroke(_to_base(ev.position))
		else:
			end_stroke()
	elif ev is InputEventMouseMotion and _drawing:
		add_point(_to_base(ev.position))


func begin_stroke(p: Vector2) -> void:
	if not STONE.has_point(p):
		return
	_pending = false
	_drawing = true
	_cur = PackedVector2Array([p])
	if strokes.is_empty():
		_carve = {}
		_fade = {}
		last = {}
		_message = "Drawing"


func add_point(p: Vector2) -> void:
	if not _drawing:
		return
	p = Vector2(clampf(p.x, STONE.position.x + 4, STONE.end.x - 4), clampf(p.y, STONE.position.y + 4, STONE.end.y - 4))
	if _cur.is_empty() or _cur[_cur.size() - 1].distance_to(p) > 1.5:
		var prev := _cur[_cur.size() - 1] if not _cur.is_empty() else p
		_cur.append(p)
		# sparks fly off the fingertip
		for i in 1:
			var v := Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(20.0, 90.0) + (p - prev) * 2.0
			_sparks.append([p, v, 0.0, _rng.randf_range(0.35, 0.8), TRAIL.lerp(Color(1, 1, 1), _rng.randf() * 0.6)])
		if _sparks.size() > 160:
			_sparks = _sparks.slice(_sparks.size() - 160)


func end_stroke() -> void:
	if not _drawing:
		return
	_drawing = false
	if _cur.size() >= 2:
		strokes.append(_cur)
	_cur = PackedVector2Array()
	if strokes.is_empty():
		return
	_last_up = _clock
	_pending = true
	# a complete single glyph can commit quickly; anything else waits for another stroke
	var r = rec.recognize(strokes, 1.0 if assist else 0.0)
	var complete: bool = r["accepted"] and rec.glyph_strokes(String(r["id"])).size() == strokes.size()
	_last_delay = COMMIT_FAST if complete else COMMIT_SLOW


var _last_delay := COMMIT_SLOW


func clear_canvas(msg := "Draw a rune") -> void:
	strokes.clear()
	_cur = PackedVector2Array()
	_drawing = false
	_pending = false
	_fade = {}
	_carve = {}
	last = {}
	_message = msg
	queue_redraw()


func set_practice(on: bool) -> void:
	var was := practice
	practice = on
	if _ui.has("practice"):
		_ui["practice"].set_pressed_no_signal(on)
	if on and not was:
		streak = 0
		hits = 0
		attempts = 0
		best_streak = 0
		conf_sum = 0.0
		_message = "Trace the rune"
	clear_canvas(_message)


func target_id() -> String:
	return rec.glyph_ids[target_index % rec.glyph_ids.size()]


# ============================================================================ recognition and feedback

func _commit() -> void:
	_pending = false
	if strokes.is_empty():
		return
	var r = rec.recognize(strokes, 1.0 if assist else 0.0)
	last = r
	last_time = _clock
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for s in strokes:
		for p in s:
			lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
			hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	var center := (lo + hi) * 0.5
	var size := maxf(hi.x - lo.x, hi.y - lo.y)
	var ok: bool = r["accepted"]
	attempts += 1
	if ok:
		var id := String(r["id"])
		var col: Color = rec.glyph_color(id)
		_fade = {"t0": _clock, "strokes": strokes.duplicate(), "color": col, "ok": true}
		_carve = {"t0": _clock, "id": id, "center": center, "size": clampf(size, 150.0, 380.0), "color": col}
		conf_sum += float(r["score"])
		if practice:
			if id == target_id():
				hits += 1
				streak += 1
				best_streak = maxi(best_streak, streak)
				_message = "Yes! %s" % rec.glyph_info(id)["name"]
				target_index += 1
			else:
				streak = 0
				_message = "That is %s. Draw %s." % [rec.glyph_info(id)["name"], rec.glyph_info(target_id())["name"]]
		else:
			_message = String(rec.glyph_info(id)["name"])
	else:
		streak = 0
		var why := {"low": "Not a rune. Try again", "ambiguous": "Too close to call, redraw it", "too_small": "Draw bigger",
			"too_many_strokes": "Too many strokes", "no_strokes": "Draw a rune"}
		_message = why.get(String(r["reason"]), "Not a rune")
		_fade = {"t0": _clock, "strokes": strokes.duplicate(), "color": Color(1.0, 0.45, 0.35), "ok": false}
	strokes.clear()
	queue_redraw()


func _process(delta: float) -> void:
	_clock += delta
	if _demo:
		_run_demo(delta)
	if _pending and _clock - _last_up >= _last_delay:
		_commit()
	# sparks
	var alive: Array = []
	for s in _sparks:
		s[2] += delta
		if s[2] < s[3]:
			s[0] += s[1] * delta
			s[1] = s[1] * (1.0 - 2.5 * delta) + Vector2(0, 40.0) * delta
			alive.append(s)
	_sparks = alive
	_ink.queue_redraw()
	if _clock - last_time < 4.0 or not _carve.is_empty():
		queue_redraw()


# ============================================================================ drawing: stone, panel

func _draw() -> void:
	var f_title := AF.title_font(600)
	var f_body := AF.title_font(430)   # Cinzel light: the IM Fell body font renders as blocks in this sandbox
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.055, 0.05, 0.045))
	_draw_stone()
	# right card
	var card := Rect2(_to_screen(Vector2(830, 40)), Vector2(410, 560) * _scale)
	draw_style_box(AF.panel(AF.PANEL, AF.GOLD, 6, 0), card)
	var x0 := card.position.x + 24.0 * _scale
	var w := card.size.x - 48.0 * _scale
	var y := card.position.y + 44.0 * _scale
	draw_string(f_title, Vector2(x0, y), "RUNE CARVER", HORIZONTAL_ALIGNMENT_LEFT, w, int(30 * _scale), AF.GOLD_BRIGHT)
	y += 30.0 * _scale
	draw_string(f_body, Vector2(x0, y), "PRACTICE MODE" if practice else "FREE DRAW", HORIZONTAL_ALIGNMENT_LEFT, w, int(20 * _scale), AF.TEXT_DIM)
	y += 14.0 * _scale
	draw_line(Vector2(x0, y), Vector2(x0 + w, y), AF.GOLD_DIM, 1.0)
	y += 34.0 * _scale
	# main message
	var msg_col := AF.TEXT
	if not last.is_empty() and _clock - last_time < 4.0:
		msg_col = rec.glyph_color(String(last["id"])) if last["accepted"] else Color(1.0, 0.55, 0.45)
	draw_string(f_title, Vector2(x0, y), _message, HORIZONTAL_ALIGNMENT_LEFT, w, int(30 * _scale), msg_col)
	y += 22.0 * _scale
	if practice:
		var tid := target_id()
		var tcol: Color = rec.glyph_color(tid)
		draw_string(f_body, Vector2(x0, y + 16.0 * _scale), "Draw: %s" % String(rec.glyph_info(tid)["name"]).to_upper(),
			HORIZONTAL_ALIGNMENT_LEFT, w, int(24 * _scale), tcol)
		y += 34.0 * _scale
		draw_multiline_string(f_body, Vector2(x0, y + 12.0 * _scale), String(rec.glyph_info(tid)["hint"]),
			HORIZONTAL_ALIGNMENT_LEFT, w, int(19 * _scale), 3, AF.TEXT_DIM)
		y += 74.0 * _scale
	else:
		if not last.is_empty() and last["accepted"]:
			draw_multiline_string(f_body, Vector2(x0, y + 16.0 * _scale), String(rec.glyph_info(String(last["id"]))["meaning"]),
				HORIZONTAL_ALIGNMENT_LEFT, w, int(19 * _scale), 3, AF.TEXT_DIM)
		y += 96.0 * _scale
	# confidence
	var score := float(last.get("score", 0.0)) if not last.is_empty() else 0.0
	draw_string(f_body, Vector2(x0, y + 8.0 * _scale), "Confidence", HORIZONTAL_ALIGNMENT_LEFT, w, int(20 * _scale), AF.TEXT_DIM)
	draw_string(f_title, Vector2(x0 + w - 110.0 * _scale, y + 8.0 * _scale), "%d%%" % int(round(score * 100.0)),
		HORIZONTAL_ALIGNMENT_RIGHT, 110.0 * _scale, int(28 * _scale), AF.GOLD_BRIGHT)
	y += 22.0 * _scale
	var bar := Rect2(x0, y, w, 16.0 * _scale)
	draw_rect(bar, Color(1, 1, 1, 0.08))
	var bar_col := Color(0.4, 0.85, 1.0)
	if not last.is_empty():
		bar_col = rec.glyph_color(String(last["id"])) if last["accepted"] else Color(1.0, 0.5, 0.4)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * score, bar.size.y)), bar_col)
	var thr := (float(rec.opts["min_sim"]) - (float(rec.opts["assist_relax"]) if assist else 0.0) - float(rec.opts["confidence_floor"])) / (1.0 - float(rec.opts["confidence_floor"]))
	draw_line(Vector2(bar.position.x + bar.size.x * thr, bar.position.y - 4.0 * _scale),
		Vector2(bar.position.x + bar.size.x * thr, bar.end.y + 4.0 * _scale), AF.TEXT, 2.0)
	y += 52.0 * _scale
	# one row per glyph
	var scores: Dictionary = last.get("scores", {}) if not last.is_empty() else {}
	for id in rec.glyph_ids:
		var s := float(scores.get(id, 0.0))
		var col: Color = rec.glyph_color(id)
		draw_string(f_body, Vector2(x0, y), String(rec.glyph_info(id)["name"]), HORIZONTAL_ALIGNMENT_LEFT, 90.0 * _scale, int(20 * _scale), col)
		var row := Rect2(x0 + 96.0 * _scale, y - 14.0 * _scale, w - 96.0 * _scale - 56.0 * _scale, 10.0 * _scale)
		draw_rect(row, Color(1, 1, 1, 0.07))
		draw_rect(Rect2(row.position, Vector2(row.size.x * clampf(s, 0.0, 1.0), row.size.y)), Color(col.r, col.g, col.b, 0.85))
		draw_string(f_body, Vector2(row.end.x + 8.0 * _scale, y), "%.2f" % s, HORIZONTAL_ALIGNMENT_LEFT, 56.0 * _scale, int(17 * _scale), AF.TEXT_DIM)
		y += 34.0 * _scale
	# footer stats
	var foot := "match %.2f ms" % (float(last.get("us", 0)) / 1000.0) if not last.is_empty() else "match -"
	draw_string(f_body, Vector2(x0, card.end.y - 46.0 * _scale), foot + ("   assist on" if assist else ""), HORIZONTAL_ALIGNMENT_LEFT, w, int(17 * _scale), AF.TEXT_DIM)
	if practice:
		var avg := (conf_sum / maxf(1.0, hits)) * 100.0
		draw_string(f_body, Vector2(x0, card.end.y - 20.0 * _scale), "Streak %d   Best %d   Hits %d/%d   Avg %d%%" % [streak, best_streak, hits, attempts, int(avg)],
			HORIZONTAL_ALIGNMENT_LEFT, w, int(19 * _scale), AF.GOLD)


func _round_rect(r: Rect2, rad: float, seg := 8) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var corners := [[r.position + Vector2(rad, rad), PI], [r.position + Vector2(r.size.x - rad, rad), PI * 1.5],
		[r.position + r.size - Vector2(rad, rad), 0.0], [r.position + Vector2(rad, r.size.y - rad), PI * 0.5]]
	for c in corners:
		for i in seg + 1:
			var a: float = c[1] + (PI * 0.5) * float(i) / seg
			pts.append(c[0] + Vector2(cos(a), sin(a)) * rad)
	return pts


func _draw_stone() -> void:
	var r := _stone_screen()
	var rr := 40.0 * _scale
	draw_colored_polygon(_round_rect(r.grow(8.0 * _scale), rr + 8.0 * _scale), Color(0, 0, 0, 0.4))
	var pts := _round_rect(r, rr)
	var cols := PackedColorArray()
	var top := Color(0.31, 0.33, 0.38)
	var bot := Color(0.11, 0.12, 0.15)
	for p in pts:
		var t := clampf((p.y - r.position.y) / r.size.y, 0.0, 1.0)
		var side := absf((p.x - r.get_center().x) / (r.size.x * 0.5))
		cols.append(top.lerp(bot, t * 0.85).darkened(side * side * 0.25))
	draw_polygon(pts, cols)
	var g := RandomNumberGenerator.new()
	g.seed = 99
	for i in 320:
		var p := r.position + Vector2(g.randf(), g.randf()) * r.size
		var a := g.randf_range(0.02, 0.08)
		draw_circle(p, g.randf_range(1.0, 3.4) * _scale, Color(1, 1, 1, a) if g.randf() < 0.5 else Color(0, 0, 0, a * 1.6))
	for i in 26:
		var p := r.position + Vector2(g.randf(), g.randf() * 0.3 + 0.7) * r.size
		draw_circle(p, g.randf_range(8.0, 24.0) * _scale, Color(0.3, 0.44, 0.2, 0.07))
	for i in 3:
		var p := r.position + Vector2(g.randf(), g.randf()) * r.size
		var line := PackedVector2Array([p])
		for k in 5:
			p += Vector2(g.randf_range(-22, 22), g.randf_range(6, 34)) * _scale
			line.append(p)
		draw_polyline(line, Color(0, 0, 0, 0.35), 1.6 * _scale)
	var edge := pts.duplicate()
	edge.append(pts[0])
	draw_polyline(edge, AF.GOLD_DIM, 2.0, true)
	# faint tap-here hint
	if strokes.is_empty() and _cur.is_empty() and _fade.is_empty() and _carve.is_empty() and not practice:
		draw_string(AF.title_font(430), r.position + Vector2(0, r.size.y * 0.52), "Draw a rune with your finger",
			HORIZONTAL_ALIGNMENT_CENTER, r.size.x, int(26 * _scale), Color(1, 1, 1, 0.30))


# ============================================================================ drawing: glowing ink layer

func _glow_line(pts: PackedVector2Array, col: Color, alpha := 1.0, wscale := 1.0) -> void:
	if pts.size() < 2:
		return
	var sp := PackedVector2Array()
	for p in pts:
		sp.append(_to_screen(p))
	var layers := [[30.0, 0.05], [20.0, 0.10], [12.0, 0.22], [6.0, 0.55], [2.6, 0.95]]
	for l in layers:
		var c := col if l[1] < 0.9 else col.lerp(Color.WHITE, 0.75)
		_ink.draw_polyline(sp, Color(c.r, c.g, c.b, l[1] * alpha), l[0] * _scale * wscale, true)


func _draw_ink() -> void:
	# practice guide
	if practice and guide and strokes.is_empty() and not _drawing:
		_draw_guide(target_id())
	# the live strokes
	for s in strokes:
		_glow_line(s, TRAIL)
	if _drawing and _cur.size() >= 2:
		_glow_line(_cur, TRAIL)
		_ink.draw_circle(_to_screen(_cur[_cur.size() - 1]), 12.0 * _scale, Color(0.7, 0.9, 1.0, 0.5))
		_ink.draw_circle(_to_screen(_cur[_cur.size() - 1]), 5.0 * _scale, Color(1, 1, 1, 0.9))
	# fading old strokes after a commit
	if not _fade.is_empty():
		var k := 1.0 - (_clock - float(_fade["t0"])) / (0.7 if _fade["ok"] else 0.55)
		if k <= 0.0:
			_fade = {}
		else:
			for s in _fade["strokes"]:
				_glow_line(s, _fade["color"], k * k)
	# carved rune
	if not _carve.is_empty():
		_draw_carve()
	# sparks
	for s in _sparks:
		var a := 1.0 - float(s[2]) / float(s[3])
		var c: Color = s[4]
		_ink.draw_circle(_to_screen(s[0]), (2.0 + 2.5 * a) * _scale, Color(c.r, c.g, c.b, a * 0.9))


func _glyph_points(id: String, center: Vector2, sz: float) -> Array:
	var out: Array = []
	for s in rec.glyph_strokes(id):
		var pv := PackedVector2Array()
		for p in s:
			pv.append(center + (p - Vector2(0.5, 0.5)) * sz)
		out.append(pv)
	return out


func _draw_carve() -> void:
	var t := _clock - float(_carve["t0"])
	var col: Color = _carve["color"]
	var fade_in := clampf((t - 0.12) / 0.35, 0.0, 1.0)
	var fade_out := 1.0 - clampf((t - 2.6) / 1.2, 0.0, 1.0)
	if fade_out <= 0.0:
		_carve = {}
		return
	var a := fade_in * fade_out
	var center: Vector2 = _carve["center"]
	var sz: float = _carve["size"]
	# flare ring
	if t < 0.9:
		var rad := (40.0 + t * 260.0) * _scale
		_ink.draw_arc(_to_screen(center), rad, 0.0, TAU, 64, Color(col.r, col.g, col.b, (1.0 - t / 0.9) * 0.55), 6.0 * _scale, true)
		_ink.draw_circle(_to_screen(center), sz * 0.55 * _scale, Color(col.r, col.g, col.b, (1.0 - t / 0.9) * 0.16))
	var pulse := 0.85 + 0.15 * sin(t * 5.0)
	for s in _glyph_points(String(_carve["id"]), center, sz):
		_glow_line(s, col, a * pulse, 1.25)


func _draw_guide(id: String) -> void:
	var col: Color = rec.glyph_color(id)
	var c := STONE.get_center() + Vector2(0, 10)
	var sz := 320.0
	var pulse := 0.55 + 0.25 * sin(_clock * 3.0)
	var n := 0
	for s: PackedVector2Array in _glyph_points(id, c, sz):
		n += 1
		# dotted path with a moving highlight from the start, an arrow head and the stroke number
		var dense := Gesture.resample(s, 60)
		var head := fmod(_clock * 0.55 + n * 0.3, 1.4)
		for i in dense.size():
			var t := float(i) / (dense.size() - 1)
			var near := clampf(1.0 - absf(t - head) * 5.0, 0.0, 1.0)
			if i % 2 == 0 or near > 0.0:
				_ink.draw_circle(_to_screen(dense[i]), (3.0 + 4.0 * near) * _scale, Color(col.r, col.g, col.b, 0.22 * pulse + 0.6 * near))
		var s0 := _to_screen(s[0])
		_ink.draw_arc(s0, 16.0 * _scale, 0.0, TAU, 24, Color(1, 1, 1, 0.7), 2.0 * _scale, true)
		_ink.draw_string(AF.title_font(600), s0 + Vector2(-6, 8) * _scale, str(n), HORIZONTAL_ALIGNMENT_LEFT, -1, int(20 * _scale), Color(1, 1, 1, 0.9))
		var e := s[s.size() - 1]
		var d := (e - s[s.size() - 2]).normalized()
		var ep := _to_screen(e)
		var nrm := Vector2(-d.y, d.x)
		_ink.draw_colored_polygon(PackedVector2Array([ep + d * 12.0 * _scale, ep - d * 8.0 * _scale + nrm * 9.0 * _scale,
			ep - d * 8.0 * _scale - nrm * 9.0 * _scale]), Color(col.r, col.g, col.b, 0.75))


# ============================================================================ scripted demo

func _build_demo() -> void:
	# what to draw: [seconds before, glyph or "", options, practice switch]
	var c := STONE.get_center()
	var base := {"origin": c, "scale": 300.0, "jitter": 0.02, "wobble": 0.03}
	var step := func(wait: float, id: String, rot: float, extra := {}) -> Dictionary:
		var o := base.duplicate()
		o["rotation"] = rot
		o.merge(extra, true)
		return {"wait": wait, "id": id, "opts": o}
	_demo_steps = [
		step.call(0.7, "ward", 0.0, {"keep_order": true}),
		step.call(1.9, "lure", 0.0, {"keep_order": true, "keep_direction": true}),
		step.call(1.9, "alarm", 0.0, {"keep_order": true}),
		step.call(1.9, "bless", 0.5, {"keep_order": true}),
		step.call(1.9, "lure", 2.4, {"keep_order": true, "keep_direction": true}),   # rotated: still a lure
		{"wait": 1.8, "id": "", "opts": {}, "mode": "scribble"},
		{"wait": 2.0, "id": "", "opts": {}, "mode": "practice_on"},
		step.call(1.6, "ward", 0.4, {"keep_order": true, "scale": 280.0, "jitter": 0.04}),
		step.call(1.9, "lure", -0.3, {"keep_order": true, "keep_direction": true, "jitter": 0.04}),
		step.call(1.9, "alarm", 0.2, {"keep_order": true, "jitter": 0.04}),
		step.call(1.9, "bless", -0.6, {"keep_order": true, "jitter": 0.04}),
		{"wait": 2.2, "id": "", "opts": {}, "mode": "end"},
	]
	_demo_i = 0
	_demo_t = 0.0
	_demo_stroke = -1


func _run_demo(delta: float) -> void:
	if _demo_i >= _demo_steps.size():
		return
	_demo_t += delta
	var st: Dictionary = _demo_steps[_demo_i]
	if _demo_stroke < 0:
		if _demo_t < float(st["wait"]):
			return
		var mode := String(st.get("mode", ""))
		if mode == "practice_on":
			set_practice(true)
			_demo_next()
			return
		if mode == "end":
			get_tree().quit()
			return
		if mode == "scribble":
			var pts: Array = []
			var p := STONE.get_center() + Vector2(-120, 20)
			var dir := 0.4
			for i in 42:
				dir += _rng.randfn(0.0, 0.7)
				p += Vector2.from_angle(dir) * 9.0
				pts.append(p)
			_demo_pts = [PackedVector2Array(pts)]
		else:
			_demo_pts = rec.synthesize(String(st["id"]), _rng, st["opts"])
		_demo_stroke = 0
		_demo_t = 0.0
		_begin_demo_stroke()
		return
	# drawing: 1.05 s per stroke, then a short lift
	var pts: PackedVector2Array = _demo_pts[_demo_stroke]
	var dur := 1.05
	if _demo_t < dur:
		var upto := int(float(pts.size()) * (_demo_t / dur))
		while _demo_idx < mini(upto, pts.size()):
			add_point(pts[_demo_idx])
			_demo_idx += 1
	else:
		while _demo_idx < pts.size():
			add_point(pts[_demo_idx])
			_demo_idx += 1
		end_stroke()
		_demo_stroke += 1
		_demo_t = 0.0
		if _demo_stroke >= _demo_pts.size():
			_demo_next()
		else:
			_demo_t = -0.18   # pen lift between strokes
			_begin_demo_stroke()


func _begin_demo_stroke() -> void:
	_demo_idx = 1
	begin_stroke(_demo_pts[_demo_stroke][0])


func _demo_next() -> void:
	_demo_i += 1
	_demo_stroke = -1
	_demo_t = 0.0
