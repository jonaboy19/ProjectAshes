extends Control
## World-space marker for a PLAYER-PINNED target only (map "Place Marker" or a quest's "Pin to World").
## Owner rule: story leads and tracked quests stay text-only (compass / tracker); nothing but an explicit pin ever
## reaches this node, and it has no glow, only a small ink diamond, the name, and a "verb · distance" line.
## Off-screen or behind the camera it clamps to the safe screen edge with an arrow.
##
##   marker.set_pin(Vector3(x, y, z), "Old watchtower", "Travel")      marker.clear_pin()

const AF := preload("res://scripts/ui/ashes_frame.gd")
const ARRIVE := 5.0          # m: the marker fades out when you are this close
const EDGE_PAD := 44.0

var player: Node3D
var pin: Dictionary = {}     # {pos: Vector3, name: String, verb: String}
## Fraction of the marker's normal alpha (the HUD lowers it in combat and hides it with the chrome).
var dim := 1.0
var _font: Font
var _body: Font
var _screen := Vector2.ZERO  # last placed marker position (tests read it)
var _clamped := false
var _angle := 0.0
var _dist := 0.0
var _shown := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = AF.title_font(700)
	_body = AF.font()
	set_process(false)


## `pos` may be a Vector3 or a ground Vector2 (x, z): the marker then hovers 3 m over the terrain there.
func set_pin(pos: Variant, label := "Marker", verb := "Travel") -> void:
	var p := Vector3.ZERO
	if pos is Vector2:
		var v := pos as Vector2
		p = Vector3(v.x, WorldGen.height(v.x, v.y) + 3.0, v.y)
	elif pos is Vector3:
		p = pos
	else:
		clear_pin()
		return
	pin = {"pos": p, "name": label, "verb": verb}
	set_process(true)
	queue_redraw()


func clear_pin() -> void:
	pin = {}
	_shown = false
	set_process(false)
	queue_redraw()


func has_pin() -> bool:
	return not pin.is_empty()


# --- pure helpers (unit tested) ---------------------------------------------------------

## "42 m", "980 m", "1.4 km".
static func distance_text(m: float) -> String:
	if m < 1000.0:
		return "%d m" % int(round(m))
	return "%.1f km" % (m / 1000.0)


static func verb_line(verb: String, m: float) -> String:
	return "%s · %s" % [verb, distance_text(m)] if verb != "" else distance_text(m)


## Where the marker sits on screen. `screen` is the projected point, `behind` = the point is behind the camera.
## -> {pos: Vector2, clamped: bool, angle: float (rad, 0 = right)}
static func place(screen: Vector2, behind: bool, view: Vector2, safe: Rect2, pad := EDGE_PAD) -> Dictionary:
	var inner := safe.grow(-pad)
	if inner.size.x <= 0.0 or inner.size.y <= 0.0:
		inner = Rect2(view * 0.25, view * 0.5)
	var centre := safe.get_center()
	var p := screen
	if behind:
		# Behind the lens the projection mirrors: flip it through the centre so the arrow points the short way round.
		p = centre - (screen - centre)
		if p.distance_to(centre) < 1.0:
			p = centre + Vector2(0, inner.size.y * 0.5)
	if inner.has_point(p) and not behind:
		return {"pos": p, "clamped": false, "angle": 0.0}
	var d := p - centre
	if d.length() < 0.001:
		d = Vector2.DOWN
	var hx := inner.size.x * 0.5
	var hy := inner.size.y * 0.5
	var k := minf(hx / maxf(absf(d.x), 0.001), hy / maxf(absf(d.y), 0.001))
	return {"pos": centre + d * k, "clamped": true, "angle": d.angle()}


# --- runtime ----------------------------------------------------------------------------

func _process(_delta: float) -> void:
	_shown = false
	if pin.is_empty():
		return
	var cam := _camera()
	if cam == null or player == null or not is_instance_valid(player):
		return
	var wp: Vector3 = pin["pos"]
	_dist = Vector2(wp.x - player.global_position.x, wp.z - player.global_position.z).length()
	var behind := cam.is_position_behind(wp)
	var sp := to_overlay(cam, cam.unproject_position(wp))
	var placed := place(sp, behind, size, Rect2(Vector2.ZERO, size).grow(-8.0))
	_screen = placed["pos"]
	_clamped = placed["clamped"]
	_angle = placed["angle"]
	_shown = _dist > ARRIVE and dim > 0.02
	queue_redraw()


func _draw() -> void:
	if not _shown or pin.is_empty():
		return
	var a := dim * clampf((_dist - ARRIVE) / 6.0, 0.0, 1.0)
	var c := _screen
	var ink := Color(0.043, 0.039, 0.035, 0.9 * a)
	var gold := Color(AF.GOLD_BRIGHT, a)
	var d := 11.0
	var dia := PackedVector2Array([c + Vector2(0, -d), c + Vector2(d, 0), c + Vector2(0, d), c + Vector2(-d, 0)])
	draw_colored_polygon(dia, ink)
	var outline := PackedVector2Array(dia)
	outline.append(dia[0])
	draw_polyline(outline, gold, 2.0, true)
	draw_circle(c, 2.5, gold)
	if _clamped:
		var dir := Vector2.from_angle(_angle)
		var tip := c + dir * (d + 12.0)
		var side := dir.orthogonal() * 7.0
		draw_colored_polygon(PackedVector2Array([tip, c + dir * (d + 3.0) + side, c + dir * (d + 3.0) - side]), Color(AF.GOLD, a))
	# Name over a verb line; kept on screen when clamped.
	var name_s := String(pin.get("name", ""))
	var line := verb_line(String(pin.get("verb", "")), _dist)
	var tw := maxf(_body.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x, _font.get_string_size(name_s, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x) + 20.0
	var box := Rect2(c + Vector2(-tw * 0.5, d + 16.0), Vector2(tw, 44))
	if _clamped and c.y > size.y - 90.0:
		box.position.y = c.y - d - 16.0 - box.size.y
	box.position.x = clampf(box.position.x, 6.0, size.x - tw - 6.0)
	draw_rect(box, ink)
	draw_rect(box, Color(AF.GOLD, 0.8 * a), false, 1.0)
	draw_string(_font, box.position + Vector2(0, 19), name_s, HORIZONTAL_ALIGNMENT_CENTER, tw, 16, Color(AF.TEXT, a))
	draw_string(_body, box.position + Vector2(0, 37), line, HORIZONTAL_ALIGNMENT_CENTER, tw, 15, Color(AF.GOLD, a))


## The player's own camera: the 3D world may render in a different viewport than this overlay.
func _camera() -> Camera3D:
	if player != null and is_instance_valid(player) and player.get("camera") is Camera3D:
		return player.get("camera") as Camera3D
	return get_viewport().get_camera_3d()


## A projected point (in the camera's own viewport pixels) in this overlay's coordinates.
func to_overlay(cam: Camera3D, p: Vector2) -> Vector2:
	var vs := cam.get_viewport().get_visible_rect().size
	if vs.x < 1.0 or vs.y < 1.0:
		return p
	return p / vs * size
