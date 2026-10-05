extends Control
## Centre-screen event banners in the dark-gold style of the user's template:
##   LOCATION DISCOVERED  a framed card with the tower-and-crown crest and the big place name,
##   QUEST COMPLETED      a strip with crossed-sword icon, quest title underneath,
##   LEVEL UP             a strip with the phoenix and "Level N - +1 Skill Point".
## Banners queue and show one after another, ~3.5 s each: fade in, hold, fade out.
## (File name kept: HUD, tests and other scripts refer to discovery_banner.gd.)
##
##   banner.show_place("Kingsreach", "Capital")                      # location (old API)
##   banner.show_event("quest", "Quest Completed", "A Farmer's Problem")
##   banner.show_event("level", "Level Up", "Level 4  ·  +1 Skill Point")

const AF := preload("res://scripts/ui/ashes_frame.gd")
const HudArt := preload("res://scripts/ui/hud_art.gd")
const HudLane := preload("res://scripts/ui/hud_lane.gd")

const DURATION := 3.5
const FADE_IN := 0.7
const FADE_OUT := 1.0

var _queue: Array[Dictionary] = []
var _kind := "location"
var _title := ""
var _subtitle := ""
var _kicker := ""
var _t := -1.0
var _title_font: Font
var _body_font: Font
var _text_font: Font


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_font = AF.wfont(700)
	_body_font = AF.wfont(600)
	_text_font = AF.font()
	set_process(false)


## Queues a location banner. `kicker` is the small line above the name ("Discovered").
func show_place(title: String, subtitle: String, kicker := "Location Discovered") -> void:
	show_event("location", title, subtitle, kicker if kicker != "Discovered" else "Location Discovered")


## kind: "location" | "quest" | "level". For quest / level `title` is the headline
## ("Quest Completed") and `subtitle` the detail line.
func show_event(kind: String, title: String, subtitle := "", kicker := "") -> void:
	_queue.append({"kind": kind, "title": title, "subtitle": subtitle, "kicker": kicker})
	if _t < 0.0:
		_next()


func is_showing() -> bool:
	return _t >= 0.0


func _next() -> void:
	if _queue.is_empty():
		_t = -1.0
		HudLane.report("banner", 0.0, 0.0)
		set_process(false)
		queue_redraw()
		return
	var d: Dictionary = _queue.pop_front()
	_kind = String(d["kind"])
	_title = String(d["title"]).to_upper()
	_subtitle = String(d["subtitle"])
	_kicker = String(d["kicker"]).to_upper()
	_t = 0.0
	set_process(true)


func _process(delta: float) -> void:
	if not HudLane.allowed("banner"):
		# A menu or conversation sheet is open: hold the banner (clock paused) until it closes.
		HudLane.report("banner", 0.0, 0.0)
		queue_redraw()
		return
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
	if a <= 0.001 or not HudLane.allowed("banner"):
		return
	if _title_font == null:
		_ready()
	# The viewport, not our own rect: the HUD root this sits in may not be full-size.
	var vw := get_viewport_rect().size
	var k := clampf(vw.x / 1280.0, 0.75, 1.4)
	var rise := (1.0 - smoothstep(0.0, FADE_IN * 1.4, _t)) * 12.0 * k
	match _kind:
		"location":
			_draw_location(vw, k, a, rise)
		_:
			_draw_strip(vw, k, a, rise)


func _fade_band(vw: Vector2, cy: float, h: float, a: float, strength := 0.66) -> void:
	# Transparent at the ends, dark in the middle, so the card sits in a soft shadow.
	var band := Color(0.02, 0.016, 0.012, strength * a)
	var clear := Color(band, 0.0)
	var xs := [0.0, vw.x * 0.2, vw.x * 0.8, vw.x]
	var cols := [clear, band, band, clear]
	for i in 3:
		var quad := PackedVector2Array([Vector2(xs[i], cy - h * 0.5), Vector2(xs[i + 1], cy - h * 0.5),
			Vector2(xs[i + 1], cy + h * 0.5), Vector2(xs[i], cy + h * 0.5)])
		draw_polygon(quad, PackedColorArray([cols[i], cols[i + 1], cols[i + 1], cols[i]]))


func _draw_location(vw: Vector2, k: float, a: float, rise: float) -> void:
	var cx := vw.x * 0.5
	var w := 600.0 * k
	var h := 214.0 * k
	var top := HudLane.y_for("banner", vw.y * 0.16) + rise
	HudLane.report("banner", top - rise, h)
	var r := Rect2(Vector2(cx - w * 0.5, top), Vector2(w, h))
	_fade_band(vw, r.get_center().y, h + 70.0 * k, a, 0.5)
	draw_rect(r, Color(0.035, 0.03, 0.026, 0.9 * a))
	# Lit upper half, like an illuminated plaque.
	draw_rect(Rect2(r.position, Vector2(r.size.x, r.size.y * 0.5)), Color(0.85, 0.66, 0.31, 0.05 * a))
	HudArt.draw_ornate_frame(self, r, AF.GOLD, a, 18.0 * k)
	# Crest, with a soft glow behind.
	var crest := HudArt.emblem("tower_crown")
	var cs := 76.0 * k
	var cc := Vector2(cx, top + 16.0 * k + cs * 0.5)
	draw_circle(cc, cs * 0.62, Color(AF.GOLD, 0.08 * a))
	if crest:
		draw_texture_rect(crest, Rect2(cc - Vector2(cs, cs) * 0.5, Vector2(cs, cs)), false, Color(1, 1, 1, a))
	# Kicker, big name, subtitle.
	var kicker := _kicker if _kicker != "" else "LOCATION DISCOVERED"
	var ks := int(15 * k)
	var kw := _spaced_width(_body_font, kicker, ks, 5.0 * k)
	var ky := top + 16.0 * k + cs + 24.0 * k
	_draw_spaced(_body_font, kicker, Vector2(cx - kw * 0.5, ky), ks, 5.0 * k, Color(AF.GOLD_BRIGHT, 0.95 * a))
	var ts := int(46 * k)
	var spread := lerpf(2.0, 8.0, ease(clampf(_t / DURATION, 0.0, 1.0), 0.4)) * k
	while ts > 20 and _spaced_width(_title_font, _title, ts, spread) > w - 70.0 * k:
		ts -= 2
	var tw := _spaced_width(_title_font, _title, ts, spread)
	var ty := ky + 12.0 * k + ts * 0.9
	_draw_spaced(_title_font, _title, Vector2(cx - tw * 0.5, ty + 3), ts, spread, Color(0, 0, 0, 0.55 * a))
	_draw_spaced(_title_font, _title, Vector2(cx - tw * 0.5, ty), ts, spread, Color(HudArt.IVORY, a))
	if _subtitle != "":
		var ss := int(16 * k)
		var st := _subtitle.to_upper()
		var sw := _spaced_width(_body_font, st, ss, 4.0 * k)
		var sy := r.end.y - 16.0 * k
		_draw_spaced(_body_font, st, Vector2(cx - sw * 0.5, sy), ss, 4.0 * k, Color(HudArt.IVORY_DIM, HudArt.IVORY_DIM.a * a))
		var grow := ease(smoothstep(0.1, FADE_IN + 0.5, _t), 0.5)
		var gap := sw * 0.5 + 16.0 * k
		var len := 130.0 * k * grow
		var ry := sy - ss * 0.35
		HudArt.draw_rule(self, Vector2(cx - gap - len, ry), Vector2(cx - gap, ry), AF.GOLD, a)
		HudArt.draw_rule(self, Vector2(cx + gap, ry), Vector2(cx + gap + len, ry), AF.GOLD, a)


func _draw_strip(vw: Vector2, k: float, a: float, rise: float) -> void:
	var cx := vw.x * 0.5
	var w := 500.0 * k
	var h := 92.0 * k
	var top := HudLane.y_for("banner", vw.y * 0.2) + rise
	HudLane.report("banner", top - rise, h)
	var r := Rect2(Vector2(cx - w * 0.5, top), Vector2(w, h))
	_fade_band(vw, r.get_center().y, h + 44.0 * k, a, 0.45)
	# Panel: dark, with the gold gradient wash the template's strips have on the icon side.
	draw_rect(r, Color(0.035, 0.03, 0.026, 0.92 * a))
	draw_polygon(PackedVector2Array([r.position, r.position + Vector2(w * 0.55, 0), r.position + Vector2(w * 0.55, h), r.position + Vector2(0, h)]),
		PackedColorArray([Color(AF.GOLD, 0.16 * a), Color(AF.GOLD, 0.0), Color(AF.GOLD, 0.0), Color(AF.GOLD, 0.16 * a)]))
	HudArt.draw_ornate_frame(self, r, AF.GOLD, a, 14.0 * k)
	# Diamond-framed icon on the left.
	var ic := Vector2(r.position.x + 52.0 * k, r.get_center().y)
	var ir := 30.0 * k
	HudArt.diamond(self, ic, ir, Color(0.06, 0.05, 0.04, a))
	var dm := PackedVector2Array([ic + Vector2(0, -ir), ic + Vector2(ir, 0), ic + Vector2(0, ir), ic + Vector2(-ir, 0), ic + Vector2(0, -ir)])
	draw_polyline(dm, Color(AF.GOLD, a), 2.0, true)
	var tex: Texture2D = HudArt.icon("attack") if _kind == "quest" else HudArt.emblem("phoenix")
	if tex:
		var s := ir * 1.35
		draw_texture_rect(tex, Rect2(ic - Vector2(s, s) * 0.5, Vector2(s, s)), false, Color(1, 1, 1, a))
	# Headline (centred in the space right of the icon) and detail line.
	var tx := r.position.x + 100.0 * k
	var tw_avail := r.end.x - tx - 24.0 * k
	var hs := int(24 * k)
	var spread := 3.0 * k
	while hs > 14 and _spaced_width(_title_font, _title, hs, spread) > tw_avail:
		hs -= 2
	var hw := _spaced_width(_title_font, _title, hs, spread)
	var hx := tx + (tw_avail - hw) * 0.5
	var hy := r.position.y + h * 0.42
	_draw_spaced(_title_font, _title, Vector2(hx, hy + 2), hs, spread, Color(0, 0, 0, 0.5 * a))
	_draw_spaced(_title_font, _title, Vector2(hx, hy), hs, spread, Color(AF.GOLD_BRIGHT, a))
	var ds := int(20 * k)
	while ds > 12 and _text_font.get_string_size(_subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, ds).x > tw_avail:
		ds -= 1
	var dw := _text_font.get_string_size(_subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, ds).x
	draw_string(_text_font, Vector2(tx + (tw_avail - dw) * 0.5, hy + 8.0 * k + ds), _subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, ds, Color(HudArt.IVORY, a))


func _spaced_width(f: Font, text: String, font_size: int, spacing: float) -> float:
	var total := 0.0
	for ch in text:
		total += f.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + spacing
	return maxf(0.0, total - spacing)


func _draw_spaced(f: Font, text: String, pos: Vector2, font_size: int, spacing: float, color: Color) -> void:
	var x := pos.x
	for ch in text:
		draw_string(f, Vector2(x, pos.y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
		x += f.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + spacing
