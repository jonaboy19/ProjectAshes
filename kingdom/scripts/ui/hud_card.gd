extends RefCounted
## The small dark-gold widgets of the in-game HUD (inner classes, one preload):
##   Card          top-left character card: round portrait, crest, title, job, gold / merit,
##                 health / stamina / soul bars, status line
##   QuestTracker  the tracked quest under the card: title + 1-3 objectives
##   InfoBlock     top-right place name, "Day N · Season", time with sun / moon, realm souls
##   DangerBadge   compact danger pill
##   CircleMask    canvas shader material that clips a texture to a circle
##
##   const HudCard := preload("res://scripts/ui/hud_card.gd")
##   var card := HudCard.Card.new()

const AF := preload("res://scripts/ui/ashes_frame.gd")
const HudArt := preload("res://scripts/ui/hud_art.gd")

const CARD_W := 332.0
const CARD_H := 172.0

const MASK_SHADER := """
shader_type canvas_item;
uniform float feather = 0.02;
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float d = distance(UV, vec2(0.5));
	c.a *= 1.0 - smoothstep(0.5 - feather, 0.5, d);
	COLOR = c;
}
"""

static var _mask_material: ShaderMaterial


## Clips whatever texture a CanvasItem draws to the circle inscribed in its rect.
static func circle_mask() -> ShaderMaterial:
	if _mask_material == null:
		var sh := Shader.new()
		sh.code = MASK_SHADER
		_mask_material = ShaderMaterial.new()
		_mask_material.shader = sh
	return _mask_material


# ------------------------------------------------------------------------------------
class Card extends Control:
	const AF := preload("res://scripts/ui/ashes_frame.gd")
	const HudArt := preload("res://scripts/ui/hud_art.gd")
	const PORTRAIT := 74.0
	const MINI := Vector2(94, 94)         # collapsed: portrait inside three thin rings
	const FULL := Vector2(332, 172)
	const MINI_PORTRAIT := 52.0
	const AUTO_COLLAPSE := 8.0            # seconds an expanded card stays open

	signal toggled(expanded: bool)

	var health: Meter
	var stamina: Meter
	var soul: Meter
	var portrait: Control
	var expanded := false
	var _title: Label
	var _job: Label
	var _gold: Label
	var _merit: Label
	var _needs: Label
	var _soldiers: Label
	var _detail: Array[Control] = []      # everything that only the expanded card shows
	var _rank := 0
	var _box: StyleBoxFlat
	var _soul_visible := false
	var _t := 0.0                         # 0 collapsed .. 1 expanded (eased in _process)
	var _food := 1.0
	var _open_for := 0.0
	var _press := Vector2.INF

	func _init() -> void:
		size = MINI
		custom_minimum_size = size
		mouse_filter = Control.MOUSE_FILTER_STOP
		_box = HudArt.card_box(0.84)

	func _ready() -> void:
		HudArt.redraw_soon(self, 0.3)
		HudArt.redraw_soon(self, 1.0)
		_title = _lbl(22, AF.GOLD_BRIGHT, true)
		_title.position = Vector2(102, 9)
		_job = _lbl(15, HudArt.IVORY, false)
		_job.position = Vector2(102, 38)
		_job.size = Vector2(216, 20)
		_job.clip_text = true
		_job.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_gold = _lbl(16, HudArt.IVORY, false)
		_gold.position = Vector2(122, 60)
		_merit = _lbl(16, HudArt.IVORY, false)
		_merit.position = Vector2(214, 60)
		health = Meter.new(HudArt.HEART_RED, Vector2(286, 11))
		health.position = Vector2(32, 96)
		add_child(health)
		stamina = Meter.new(HudArt.STAMINA_GOLD, Vector2(286, 8))
		stamina.position = Vector2(32, 113)
		add_child(stamina)
		soul = Meter.new(HudArt.SOUL_BLUE, Vector2(286, 6))
		soul.position = Vector2(32, 127)
		soul.visible = false
		add_child(soul)
		_needs = _lbl(14, AF.TEXT_DIM, false)
		_needs.position = Vector2(14, 142)
		_soldiers = _lbl(14, AF.TEXT_DIM, false)
		_soldiers.position = Vector2(150, 142)
		_soldiers.size = Vector2(168, 20)
		_soldiers.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		for c: Control in [_title, _job, _gold, _merit, health, stamina, _needs, _soldiers]:
			_detail.append(c)
		_apply(true)
		set_process(true)

	func _lbl(fs: int, col: Color, title: bool) -> Label:
		var l := Label.new()
		l.add_theme_font_override("font", AF.wfont(700) if title else AF.font())
		l.add_theme_font_size_override("font_size", fs)
		l.add_theme_color_override("font_color", col)
		l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
		l.add_theme_constant_override("shadow_offset_y", 1)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(l)
		return l

	## Puts the round portrait (a Control already masked to a circle) into its frame.
	func set_portrait(p: Control) -> void:
		if portrait and is_instance_valid(portrait):
			portrait.queue_free()
		portrait = p
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(p)
		move_child(p, 0)
		_apply(true)

	func set_expanded(v: bool) -> void:
		if v == expanded:
			return
		expanded = v
		_open_for = 0.0
		toggled.emit(v)

	func eased() -> float:
		return _t * _t * (3.0 - 2.0 * _t)

	func _process(delta: float) -> void:
		if expanded:
			_open_for += delta
			if _open_for > AUTO_COLLAPSE:
				set_expanded(false)
		var goal := 1.0 if expanded else 0.0
		if not is_equal_approx(_t, goal):
			_t = move_toward(_t, goal, delta / 0.22)
			_apply(false)
		elif _t == 0.0:
			queue_redraw()      # the rings follow health / stamina / hunger

	func _apply(snap: bool) -> void:
		var e := eased()
		var s := MINI.lerp(FULL, e)
		custom_minimum_size = s
		size = s
		for c in _detail:
			if c != null:
				c.modulate.a = e
				c.visible = e > 0.02
		if soul:
			soul.modulate.a = e
			soul.visible = _soul_visible and e > 0.02
		if portrait and is_instance_valid(portrait):
			var d := lerpf(MINI_PORTRAIT, PORTRAIT, e)
			var centre := _portrait_centre()
			portrait.size = Vector2(d, d)
			portrait.custom_minimum_size = portrait.size
			portrait.position = centre - portrait.size * 0.5
		queue_redraw()

	func _portrait_centre() -> Vector2:
		return MINI * 0.5 if _t <= 0.0 else (MINI * 0.5).lerp(Vector2(16 + PORTRAIT * 0.5, 16 + PORTRAIT * 0.5), eased())

	func set_state(rank_name: String, rank: int, job: String, gold: int, merit: int, needs: String, needs_ok: bool,
			soldiers_text: String, soul_frac: float, food_frac := 1.0) -> void:
		if rank != _rank:
			_rank = rank
			queue_redraw()
		_food = clampf(food_frac, 0.0, 1.0)
		_title.text = rank_name.to_upper()
		_job.text = job
		_gold.text = "%d gold" % gold
		_merit.text = "%d merit" % merit
		_needs.text = needs
		_needs.add_theme_color_override("font_color", AF.TEXT_DIM if needs_ok else Color("ff8a70"))
		_soldiers.text = soldiers_text
		var show_soul := soul_frac >= 0.0
		if show_soul != _soul_visible:
			_soul_visible = show_soul
			soul.visible = show_soul and eased() > 0.02
		if show_soul:
			soul.max_value = 1.0
			soul.value = soul_frac

	func _gui_input(e: InputEvent) -> void:
		if not e is InputEventScreenTouch:
			return
		if e.pressed:
			_press = e.position
		else:
			if _press != Vector2.INF and e.position.distance_to(_press) < 24.0:
				set_expanded(not expanded)
				accept_event()
			_press = Vector2.INF

	## Fractions for the three collapsed rings (health, stamina, hunger).
	func ring_values() -> Array[float]:
		var h := clampf(health.value / maxf(health.max_value, 1.0), 0.0, 1.0) if health else 1.0
		var s := clampf(stamina.value / maxf(stamina.max_value, 1.0), 0.0, 1.0) if stamina else 1.0
		return [h, s, _food]

	func _draw() -> void:
		var e := eased()
		var pc := _portrait_centre()
		var pr := lerpf(MINI_PORTRAIT, PORTRAIT, e) * 0.5
		if e > 0.0:
			var bx := _box.duplicate() as StyleBoxFlat
			bx.bg_color.a *= e
			bx.border_color.a *= e
			bx.shadow_color.a *= e
			draw_style_box(bx, Rect2(Vector2.ZERO, size))
			# A thin inner gold hairline for depth.
			draw_rect(Rect2(Vector2(3, 3), size - Vector2(6, 6)), Color(AF.GOLD, 0.16 * e), false, 1.0)
		# Portrait socket + rim.
		draw_circle(pc, pr + 4.0, Color(0, 0, 0, 0.55))
		draw_circle(pc, pr, Color(0.1, 0.08, 0.06, 1.0))
		draw_arc(pc, pr + 1.5, 0, TAU, 56, AF.GOLD, 3.0, true)
		draw_arc(pc, pr + 3.4, 0, TAU, 56, Color(AF.GOLD, 0.35), 1.0, true)
		if e < 1.0:
			_draw_rings(pc, pr, 1.0 - e)
		if e <= 0.02:
			return
		# Rank crest pinned to the portrait's lower right.
		var crest := Rect2(Vector2(66, 62), Vector2(30, 38))
		if e > 0.6:
			HudArt.draw_crest(self, crest, HudArt.rank_emblem(_rank))
		# Coin and merit star icons.
		var gy := 60.0 + 12.0
		var ac := Color(1, 1, 1, e)
		draw_circle(Vector2(108, gy), 8.0, Color(AF.GOLD, e))
		draw_arc(Vector2(108, gy), 5.2, 0, TAU, 20, Color(0.54, 0.384, 0.141, e), 1.4, true)
		draw_arc(Vector2(108, gy), 8.0, 0, TAU, 24, Color(AF.GOLD_BRIGHT, e), 1.2, true)
		_star(Vector2(200, gy), 8.5, Color(HudArt.IVORY, e))
		# Bar icons.
		var hi := HudArt.icon("health")
		if hi:
			draw_texture_rect(hi, Rect2(Vector2(12, 92), Vector2(17, 17)), false, ac)
		var si := HudArt.icon("stamina")
		if si:
			draw_texture_rect(si, Rect2(Vector2(12, 109), Vector2(17, 17)), false, ac)
		if _soul_visible:
			HudArt.diamond(self, Vector2(20, 130), 5.0, Color(HudArt.SOUL_BLUE, e))
		draw_line(Vector2(14, 138), Vector2(size.x - 14, 138), Color(AF.GOLD, 0.2 * e), 1.0)

	## Thin concentric rings outside the portrait: health (red), stamina (gold), hunger (green; amber when low).
	func _draw_rings(pc: Vector2, pr: float, a: float) -> void:
		var vals := ring_values()
		var cols := [HudArt.HEART_RED, HudArt.STAMINA_GOLD, Color("8fcf6a") if vals[2] > 0.3 else Color("ff9a4a")]
		for i in 3:
			var r := pr + 8.0 + i * 4.6
			draw_arc(pc, r, 0, TAU, 48, Color(0, 0, 0, 0.5 * a), 3.2, true)
			if vals[i] > 0.004:
				draw_arc(pc, r, -PI * 0.5, -PI * 0.5 + TAU * vals[i], 48, Color(cols[i], a), 3.0, true)

	func _star(c: Vector2, r: float, col: Color) -> void:
		var pts := PackedVector2Array()
		for i in 10:
			var a := -PI * 0.5 + i * PI / 5.0
			var rr := r if i % 2 == 0 else r * 0.42
			pts.append(c + Vector2(cos(a), sin(a)) * rr)
		draw_colored_polygon(pts, col)


# ------------------------------------------------------------------------------------
class QuestTracker extends PanelContainer:
	const AF := preload("res://scripts/ui/ashes_frame.gd")
	const HudArt := preload("res://scripts/ui/hud_art.gd")

	var _box: VBoxContainer
	var _kicker: Label
	var _title: Label
	var _rows: VBoxContainer
	var _sig := ""

	func _init() -> void:
		custom_minimum_size = Vector2(332, 0)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := HudArt.card_box(0.8, 10)
		sb.content_margin_left = 14
		sb.content_margin_right = 12
		add_theme_stylebox_override("panel", sb)
		_box = VBoxContainer.new()
		_box.add_theme_constant_override("separation", 2)
		_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_box)
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 6)
		head.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_box.add_child(head)
		var bang := Label.new()
		bang.text = "!"
		bang.add_theme_font_override("font", AF.wfont(800))
		bang.add_theme_font_size_override("font_size", 17)
		bang.add_theme_color_override("font_color", AF.GOLD_BRIGHT)
		bang.mouse_filter = Control.MOUSE_FILTER_IGNORE
		head.add_child(bang)
		_title = Label.new()
		_title.add_theme_font_override("font", AF.wfont(700))
		_title.add_theme_font_size_override("font_size", 15)
		_title.add_theme_color_override("font_color", AF.GOLD_BRIGHT)
		_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		head.add_child(_title)
		_rows = VBoxContainer.new()
		_rows.add_theme_constant_override("separation", 1)
		_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_box.add_child(_rows)
		visible = false

	## quest = {} to hide, else {title, objectives: [{text, state: "done"|"current"|"todo"}]}.
	func set_quest(quest: Dictionary) -> void:
		var sig := JSON.stringify(quest)
		if sig == _sig:
			return
		_sig = sig
		if quest.is_empty():
			visible = false
			return
		visible = true
		_title.text = String(quest.get("title", ""))
		_settle.call_deferred()
		for c in _rows.get_children():
			_rows.remove_child(c)
			c.queue_free()
		for o: Dictionary in quest.get("objectives", []):
			var state := String(o.get("state", "todo"))
			var l := Label.new()
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size.x = 296
			l.text = ("✓ " if state == "done" else ("• " if state == "current" else "◦ ")) + String(o.get("text", ""))
			l.add_theme_font_override("font", AF.font())
			l.add_theme_font_size_override("font_size", 14)
			l.add_theme_color_override("font_color", HudArt.IVORY if state == "current" else (AF.TEXT_DIM if state == "todo" else Color(HudArt.OK_GREEN, 0.85)))
			l.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_rows.add_child(l)
		reset_size()

	## Autowrapped labels first measure at zero width (very tall); once laid out, shrink back.
	func _settle() -> void:
		for i in 2:
			await get_tree().process_frame
		size = Vector2(custom_minimum_size.x, 0.0)


# ------------------------------------------------------------------------------------
class InfoBlock extends Control:
	const AF := preload("res://scripts/ui/ashes_frame.gd")
	const HudArt := preload("res://scripts/ui/hud_art.gd")

	var place := ""
	var day_line := ""
	var time_text := ""
	var night := false
	var realm := ""
	var show_realm := false             # the realm-souls line: only when the status card is expanded
	var _tf: Font
	var _bf: Font

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(300, 84)
		size = custom_minimum_size

	func _ready() -> void:
		_tf = AF.wfont(700)
		_bf = AF.font()

	func set_info(p: String, d: String, t: String, is_night: bool, r: String) -> void:
		if p == place and d == day_line and t == time_text and is_night == night and r == realm:
			return
		place = p
		day_line = d
		time_text = t
		night = is_night
		realm = r
		queue_redraw()

	func _text(f: Font, s: String, fs: int, right_x: float, y: float, col: Color) -> float:
		var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var pos := Vector2(right_x - w, y)
		draw_string_outline(f, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color(0.02, 0.015, 0.01, 0.85))
		draw_string(f, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		return w

	func _draw() -> void:
		if _tf == null:
			return
		var rx := size.x - 2.0
		# Place name; shrinks for long road names.
		var fs := 26
		while fs > 15 and _tf.get_string_size(place, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > size.x - 4.0:
			fs -= 2
		_text(_tf, place, fs, rx, 24.0, HudArt.IVORY)
		# Day · season   [sun/moon] hh:mm
		var tw := _text(_bf, time_text, 19, rx, 50.0, HudArt.IVORY)
		var ic := Vector2(rx - tw - 16.0, 43.0)
		draw_circle(ic, 11.0, Color(0, 0, 0, 0.35))
		if night:
			HudArt.draw_moon(self, ic, 8.5, Color("cfd8ff"))
		else:
			HudArt.draw_sun(self, ic, 9.5, Color("ffc94a"))
		_text(_bf, day_line, 19, ic.x - 15.0, 50.0, HudArt.IVORY)
		if show_realm:
			_text(_bf, realm, 15, rx, 72.0, Color(HudArt.IVORY, 0.78))


# ------------------------------------------------------------------------------------
class DangerBadge extends Control:
	const AF := preload("res://scripts/ui/ashes_frame.gd")
	const HudArt := preload("res://scripts/ui/hud_art.gd")

	var text := ""
	var tint := Color("7be0a0")
	var _box: StyleBoxFlat

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(120, 26)
		size = custom_minimum_size
		_box = HudArt.card_box(0.72, 4)

	func set_danger(t: String, c: Color) -> void:
		if t == text and c == tint:
			return
		text = t
		tint = c
		var w := AF.font().get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		custom_minimum_size = Vector2(w + 46.0, 26)
		size = custom_minimum_size
		queue_redraw()

	func _draw() -> void:
		_box.border_color = Color(tint, 0.7)
		draw_style_box(_box, Rect2(Vector2.ZERO, size))
		# Little shield pip in the danger colour.
		var r := Rect2(Vector2(8, 4), Vector2(14, 18))
		var pts := HudArt.shield_points(r, 6)
		draw_colored_polygon(pts, Color(tint, 0.9))
		draw_string(AF.font(), Vector2(30, 18), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, HudArt.IVORY)


# ------------------------------------------------------------------------------------
## The contextual interaction label that sits on top of the primary action button:
## "Talk — Roland Ward" in the parchment / gold card style (replaces the old "Tap to use" caption).
class ActionPill extends Control:
	const AF := preload("res://scripts/ui/ashes_frame.gd")
	const HudArt := preload("res://scripts/ui/hud_art.gd")
	const MAX_W := 380.0
	const H := 40.0

	var verb := ""
	var target := ""
	var _box: StyleBoxFlat
	var _fs := 21

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_box = HudArt.card_box(0.9, 8)
		_box.set_corner_radius_all(10)
		size = Vector2(120, H)

	func set_label(v: String, t: String) -> void:
		if v == verb and t == target:
			return
		verb = v
		target = t
		_fs = 21
		var tw := _measure()
		while tw > MAX_W and _fs > 14:
			_fs -= 1
			tw = _measure()
		size = Vector2(minf(tw, MAX_W) + 30.0, H)
		queue_redraw()

	func _measure() -> float:
		var w := AF.wfont(700).get_string_size(verb, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs).x
		if target != "":
			w += AF.font().get_string_size("  —  " + target, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs).x
		return w

	func _draw() -> void:
		draw_style_box(_box, Rect2(Vector2.ZERO, size))
		draw_rect(Rect2(Vector2(3, 3), size - Vector2(6, 6)), Color(AF.GOLD, 0.16), false, 1.0)
		var base := Vector2(15, H * 0.5 + _fs * 0.36)
		var vf := AF.wfont(700)
		var bf := AF.font()
		draw_string_outline(vf, base, verb, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs, 4, Color(0, 0, 0, 0.7))
		draw_string(vf, base, verb, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs, AF.GOLD_BRIGHT)
		if target != "":
			var x := base.x + vf.get_string_size(verb, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs).x
			var rest := "  —  "
			draw_string(bf, Vector2(x, base.y), rest, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs, Color(AF.GOLD, 0.7))
			x += bf.get_string_size(rest, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs).x
			draw_string_outline(bf, Vector2(x, base.y), target, HORIZONTAL_ALIGNMENT_LEFT, MAX_W, _fs, 4, Color(0, 0, 0, 0.7))
			draw_string(bf, Vector2(x, base.y), target, HORIZONTAL_ALIGNMENT_LEFT, MAX_W, _fs, HudArt.IVORY)
