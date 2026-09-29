extends Control
## Circular minimap (top right): a window onto the BAKED world map texture that
## world_map.gd paints once on a worker thread, so it costs one textured quad and a
## handful of marker icons - no second 3D render. North is up; discovered places,
## hostile camps and the quest marker sit on it, the player arrow turns with the camera.
## Tap it to open the full map.

signal tapped

const AF := preload("res://scripts/ui/ashes_frame.gd")
const HudArt := preload("res://scripts/ui/hud_art.gd")
const HudCard := preload("res://scripts/ui/hud_card.gd")
const MapIcons := preload("res://scripts/ui/map_icons.gd")
const WorldMap := preload("res://scripts/ui/world_map.gd")
const CompassBar := preload("res://scripts/ui/compass.gd")

const SHADER := """
shader_type canvas_item;
uniform vec2 centre_uv = vec2(0.5);
uniform float radius_uv = 0.05;
uniform float feather = 0.004;
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float d = distance(UV, centre_uv);
	c.a *= 1.0 - smoothstep(radius_uv - feather, radius_uv, d);
	// Slightly warm, slightly darker: sits in the dark gold frame.
	c.rgb = mix(c.rgb, c.rgb * vec3(1.0, 0.92, 0.8), 0.5) * 0.92;
	COLOR = c;
}
"""

const RANGE_M := 250.0            # metres from the player to the rim
const RATE := 1.0 / 8.0

var player: Node3D
var markers: Array = []:
	set(v):
		markers = v
		_dirty = true
var quest_target: Variant = null:
	set(v):
		quest_target = v
		_dirty = true

var _terrain: Control
var _mat: ShaderMaterial
var _pos := Vector2.INF
var _heading := 0.0
var _acc := 0.0
var _dirty := true
var _press := Vector2.INF
var _pulse := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	if size == Vector2.ZERO:
		size = Vector2(124, 124)
	custom_minimum_size = size
	var sh := Shader.new()
	sh.code = SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_terrain = Control.new()
	_terrain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_terrain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_terrain.material = _mat
	_terrain.draw.connect(_draw_terrain)
	add_child(_terrain)
	resized.connect(func() -> void:
		_dirty = true)


func _process(delta: float) -> void:
	_acc += delta
	_pulse += delta
	if _acc < RATE:
		return
	_acc = 0.0
	if player == null or not is_instance_valid(player) or not player.is_inside_tree() or not is_visible_in_tree():
		return
	var p := Vector2(player.global_position.x, player.global_position.z)
	var cam: Variant = player.get("camera")
	var h := CompassBar.heading_of(cam if cam is Node3D and cam.is_inside_tree() else player)
	var animate := quest_target is Vector2
	if _dirty or animate or p.distance_squared_to(_pos) > 0.25 or absf(angle_difference(h, _heading)) > 0.01:
		_pos = p
		_heading = h
		_dirty = false
		_terrain.queue_redraw()
		queue_redraw()


func _gui_input(e: InputEvent) -> void:
	if not e is InputEventScreenTouch:
		return
	if e.pressed:
		_press = e.position
	else:
		if _press != Vector2.INF and e.position.distance_to(_press) < 16.0:
			tapped.emit()
			accept_event()
		_press = Vector2.INF


func _world_tex() -> Texture2D:
	return WorldMap._texture


## World position -> local pixel position (north up).
func _to_px(w: Vector2) -> Vector2:
	var r := size.x * 0.5
	return Vector2(r, r) + (w - _pos) / RANGE_M * (r - 4.0)


func _draw_terrain() -> void:
	var r := size.x * 0.5
	var tex := _world_tex()
	if tex == null or _pos == Vector2.INF:
		_terrain.draw_circle(Vector2(r, r), r - 3.0, Color("6f7f54"))
		return
	var half := WorldGen.WORLD_HALF
	var w := tex.get_size()
	var uv_c := (_pos + Vector2(half, half)) / (half * 2.0)
	var span_uv := RANGE_M / (half * 2.0)
	var scale_out := r / (r - 4.0)                       # the rim ring sits inside the disc edge
	var src := Rect2((uv_c - Vector2(span_uv, span_uv) * scale_out) * w, Vector2(span_uv, span_uv) * 2.0 * scale_out * w)
	_mat.set_shader_parameter("centre_uv", (src.position + src.size * 0.5) / w)
	_mat.set_shader_parameter("radius_uv", src.size.x * 0.5 / w.x * (r - 3.0) / r)
	_terrain.draw_texture_rect_region(tex, Rect2(Vector2.ZERO, size), src)


func _draw() -> void:
	var r := size.x * 0.5
	var c := Vector2(r, r)
	# Shadow, dark socket, frame.
	draw_circle(c + Vector2(0, 3), r + 1.0, Color(0, 0, 0, 0.4))
	draw_arc(c, r - 1.5, 0, TAU, 72, Color(0.03, 0.025, 0.02, 0.85), 5.0, true)
	if _pos == Vector2.INF:
		_ring(c, r)
		return
	# Markers: places inside the disc, hostile camps red.
	var order := markers.duplicate()
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("hostile", false)) < int(b.get("hostile", false)))
	for m: Dictionary in order:
		var mp: Vector2 = m["pos"]
		var q := _to_px(mp)
		if q.distance_to(c) > r - 12.0:
			continue
		MapIcons.draw(self, String(m.get("kind", "")), q, 13.0, m.get("color", Color.WHITE), 0.95)
	if quest_target is Vector2:
		var qp := _to_px(quest_target as Vector2)
		var off := qp.distance_to(c) > r - 14.0
		if off:
			qp = c + (qp - c).normalized() * (r - 14.0)
		var pulse := 0.5 + 0.5 * sin(_pulse * 4.0)
		draw_circle(qp, 8.0 + pulse * 2.0, Color(MapIcons.QUEST, 0.25))
		MapIcons.draw(self, "quest", qp, 15.0, MapIcons.QUEST, 1.0 if not off else 0.85)
	MapIcons.draw_player(self, c, 5.5, _heading)
	_ring(c, r)


func _ring(c: Vector2, r: float) -> void:
	draw_arc(c, r - 3.0, 0, TAU, 72, AF.GOLD, 2.5, true)
	draw_arc(c, r - 6.2, 0, TAU, 72, Color(AF.GOLD, 0.3), 1.0, true)
	draw_arc(c, r + 0.5, 0, TAU, 72, Color(0, 0, 0, 0.55), 1.5, true)
	# Gold "N" on a small badge at the top of the rim.
	var f := AF.wfont(800)
	var tp := Vector2(c.x, 7.0)
	draw_circle(tp, 8.0, Color(0.05, 0.04, 0.03, 0.95))
	draw_arc(tp, 8.0, 0, TAU, 20, AF.GOLD, 1.3, true)
	draw_string(f, tp + Vector2(-8.0, 5.0), "N", HORIZONTAL_ALIGNMENT_CENTER, 16.0, 12, AF.GOLD_BRIGHT)
