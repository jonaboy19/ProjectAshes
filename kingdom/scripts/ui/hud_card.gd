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

	var health: Meter
	var stamina: Meter
	var soul: Meter
	var portrait: Control
	var _title: Label
	var _job: Label
	var _gold: Label
	var _merit: Label
	var _needs: Label
	var _soldiers: Label
	var _rank := 0
	var _box: StyleBoxFlat
	var _soul_visible := false

	func _init() -> void:
		size = Vector2(332, 172)
		custom_minimum_size = size
		mouse_filter = Control.MOUSE_FILTER_IGNORE
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
		p.position = Vector2(16, 16)
		p.size = Vector2(PORTRAIT, PORTRAIT)
		p.custom_minimum_size = p.size
		add_child(p)
		move_child(p, 0)

	func set_state(rank_name: String, rank: int, job: String, gold: int, merit: int, needs: String, needs_ok: bool,
			soldiers_text: String, soul_frac: float) -> void:
		if rank != _rank:
			_rank = rank
			queue_redraw()
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
			soul.visible = show_soul
		if show_soul:
			soul.max_value = 1.0
			soul.value = soul_frac

	func _draw() -> void:
		draw_style_box(_box, Rect2(Vector2.ZERO, size))
		# A thin inner gold hairline for depth.
		draw_rect(Rect2(Vector2(3, 3), size - Vector2(6, 6)), Color(AF.GOLD, 0.16), false, 1.0)
		var pc := Vector2(16 + PORTRAIT * 0.5, 16 + PORTRAIT * 0.5)
		# Portrait socket + rim.
		draw_circle(pc, PORTRAIT * 0.5 + 4.0, Color(0, 0, 0, 0.55))
		draw_circle(pc, PORTRAIT * 0.5, Color(0.1, 0.08, 0.06, 1.0))
		draw_arc(pc, PORTRAIT * 0.5 + 1.5, 0, TAU, 56, AF.GOLD, 3.0, true)
		draw_arc(pc, PORTRAIT * 0.5 + 3.4, 0, TAU, 56, Color(AF.GOLD, 0.35), 1.0, true)
		# Rank crest pinned to the portrait's lower right.
		HudArt.draw_crest(self, Rect2(Vector2(66, 62), Vector2(30, 38)), HudArt.rank_emblem(_rank))
		# Coin and merit star icons.
		var gy := 60.0 + 12.0
		draw_circle(Vector2(108, gy), 8.0, AF.GOLD)
		draw_arc(Vector2(108, gy), 5.2, 0, TAU, 20, Color("8a6224"), 1.4, true)
		draw_arc(Vector2(108, gy), 8.0, 0, TAU, 24, AF.GOLD_BRIGHT, 1.2, true)
		_star(Vector2(200, gy), 8.5, HudArt.IVORY)
		# Bar icons.
		var hi := HudArt.icon("health")
		if hi:
			draw_texture_rect(hi, Rect2(Vector2(12, 92), Vector2(17, 17)), false)
		var si := HudArt.icon("stamina")
		if si:
			draw_texture_rect(si, Rect2(Vector2(12, 109), Vector2(17, 17)), false)
		if _soul_visible:
			HudArt.diamond(self, Vector2(20, 130), 5.0, HudArt.SOUL_BLUE)
		draw_line(Vector2(14, 138), Vector2(size.x - 14, 138), Color(AF.GOLD, 0.2), 1.0)

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
