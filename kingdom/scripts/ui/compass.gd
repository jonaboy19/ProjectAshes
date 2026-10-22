extends Control
## Heading strip across the top of the HUD. Cardinal letters and ticks slide
## with the camera yaw; place badges, hostile camps (red) and the quest marker
## sit at their bearing. One Control, one _draw(), refreshed at 15 Hz and only
## when something actually moved.
##
## Feed it: `player` (Node3D with a `camera`), `markers` ([{pos: Vector2, kind,
## color, hostile}]) and `quest_target` (Vector2, or null for none).

const MapIcons := preload("res://scripts/ui/map_icons.gd")
const AF := preload("res://scripts/ui/ashes_frame.gd")
const HudArt := preload("res://scripts/ui/hud_art.gd")

signal tapped

const RATE := 1.0 / 15.0
const HALF_ARC := deg_to_rad(95.0)      # bearings shown either side of the heading
const BAR_HEIGHT := 44.0
const ICON := 24.0

var player: Node3D
var markers: Array = []:
	set(v):
		markers = v
		_dirty = true
var quest_target: Variant = null:
	set(v):
		quest_target = v
		_dirty = true

var _heading := 0.0
var _pos := Vector2.ZERO
var _acc := 0.0
var _dirty := true
var _letter_font: Font
var _font: Font
var _bg: StyleBoxFlat
var _press := Vector2.INF


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(320, BAR_HEIGHT + 22)
	_letter_font = AF.wfont(700)
	_font = AF.font()
	_bg = HudArt.card_box(0.8, 0)
	_bg.set_corner_radius_all(int(BAR_HEIGHT * 0.5))
	_bg.border_color = Color(AF.GOLD, 0.85)
	_bg.set_border_width_all(1)


## Heading of a camera: radians clockwise from north (north = -z).
static func heading_of(cam: Node3D) -> float:
	var f := -cam.global_transform.basis.z
	return atan2(f.x, -f.z)


## Bearing from a to b on the ground plane, radians clockwise from north.
static func bearing(a: Vector2, b: Vector2) -> float:
	var d := b - a
	return atan2(d.x, -d.y)


func _process(delta: float) -> void:
	_acc += delta
	if _acc < RATE:
		return
	_acc = 0.0
	if player == null or not is_instance_valid(player) or not is_visible_in_tree() or not player.is_inside_tree():
		return   # (a player outside the tree, e.g. mid scene swap, flooded get_global_transform errors)
	var cam: Variant = player.get("camera")
	var h := heading_of(cam if cam is Node3D and cam.is_inside_tree() else player)
	var p := Vector2(player.global_position.x, player.global_position.z)
	if _dirty or absf(angle_difference(h, _heading)) > 0.003 or p.distance_squared_to(_pos) > 0.25:
		_heading = h
		_pos = p
		_dirty = false
		queue_redraw()


func _gui_input(e: InputEvent) -> void:
	# A tap (not a drag) on the strip opens the map. Touch only: the project
	# emulates touch from the mouse, so desktop clicks arrive here too.
	if not e is InputEventScreenTouch:
		return
	if e.pressed:
		_press = e.position
	else:
		if _press != Vector2.INF and e.position.distance_to(_press) < 16.0:
			tapped.emit()
			accept_event()
		_press = Vector2.INF


func _x_for(rel: float) -> float:
	return size.x * 0.5 + rel / HALF_ARC * (size.x * 0.5 - 18.0)


func _edge_alpha(x: float) -> float:
	var t := absf(x - size.x * 0.5) / (size.x * 0.5)
	return 1.0 - smoothstep(0.72, 1.0, t)


func _draw() -> void:
	var w := size.x
	var cy := BAR_HEIGHT * 0.5
	draw_style_box(_bg, Rect2(0, 0, w, BAR_HEIGHT))
	# Ticks every 5 degrees, labels every 45.
	var hdeg := rad_to_deg(_heading)
	var first := int(floor((hdeg - rad_to_deg(HALF_ARC)) / 5.0)) * 5
	var last := int(ceil((hdeg + rad_to_deg(HALF_ARC)) / 5.0)) * 5
	for d in range(first, last + 1, 5):
		var rel := angle_difference(_heading, deg_to_rad(d))
		if absf(rel) > HALF_ARC:
			continue
		var x := _x_for(rel)
		var a := _edge_alpha(x)
		var dm := posmod(d, 360)
		if dm % 45 == 0:
			var label: String = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"][dm / 45]
			var cardinal := dm % 90 == 0
			var fs := 24 if dm == 0 else (20 if cardinal else 13)
			var col := AF.GOLD_BRIGHT if dm == 0 else (HudArt.IVORY if cardinal else AF.TEXT_DIM)
			var tw := _letter_font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(_letter_font, Vector2(x - tw * 0.5, cy + fs * 0.36), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
				Color(col, col.a * a))
		else:
			var tall := dm % 15 == 0
			var th := 9.0 if tall else 5.0
			draw_line(Vector2(x, BAR_HEIGHT - 6.0 - th), Vector2(x, BAR_HEIGHT - 6.0), Color(HudArt.IVORY, (0.55 if tall else 0.28) * a), 1.0)
	# Places, then hostiles, then the quest marker on top.
	var order := markers.duplicate()
	order.sort_custom(func(m1: Dictionary, m2: Dictionary) -> bool:
		return int(m1.get("hostile", false)) < int(m2.get("hostile", false)))
	for m: Dictionary in order:
		var mp: Vector2 = m["pos"]
		var dist := _pos.distance_to(mp)
		if dist < 6.0:
			continue
		var rel := angle_difference(_heading, bearing(_pos, mp))
		if absf(rel) > HALF_ARC:
			continue
		var x := _x_for(rel)
		var near := 1.0 - smoothstep(150.0, 400.0, dist) * 0.45
		MapIcons.draw(self, String(m.get("kind", "")), Vector2(x, cy), ICON * near, m.get("color", Color.WHITE), _edge_alpha(x))
	if quest_target is Vector2:
		var qd := _pos.distance_to(quest_target)
		var rel := angle_difference(_heading, bearing(_pos, quest_target))
		var off := absf(rel) > HALF_ARC
		rel = clampf(rel, -HALF_ARC, HALF_ARC)
		var x := _x_for(rel)
		var qa := 0.65 if off else 1.0
		MapIcons.draw(self, "quest", Vector2(x, cy), ICON + 4.0, MapIcons.QUEST, qa)
		var txt := "%d m" % int(qd) if qd < 1000.0 else "%.1f km" % (qd / 1000.0)
		var tw := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		var tx := clampf(x - tw * 0.5, 2.0, w - tw - 2.0)
		draw_string_outline(_font, Vector2(tx, BAR_HEIGHT + 15.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, Color(0, 0, 0, 0.7 * qa))
		draw_string(_font, Vector2(tx, BAR_HEIGHT + 15.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(MapIcons.QUEST, qa))
	# Centre marker: a gold diamond on the rim and a short pointer, like the template's crest pin.
	var c := w * 0.5
	HudArt.diamond(self, Vector2(c, 1.0), 6.0, AF.GOLD_BRIGHT)
	draw_line(Vector2(c, BAR_HEIGHT - 5.0), Vector2(c, BAR_HEIGHT - 1.0), AF.GOLD_BRIGHT, 2.0)
	# Small diamonds cap both ends of the bar.
	HudArt.diamond(self, Vector2(8.0, cy), 2.6, Color(AF.GOLD, 0.8))
	HudArt.diamond(self, Vector2(w - 8.0, cy), 2.6, Color(AF.GOLD, 0.8))
