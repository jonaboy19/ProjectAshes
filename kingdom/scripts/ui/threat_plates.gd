extends Control
## Floating threat plates (level, name, small health bar) over hostiles, ONLY while they are engaged with the
## player or locked on. At most MAX_PLATES at once (locked first, then nearest engaged). Screen-space ink plates,
## projected each frame from a 10 Hz selection so the cost is a handful of unproject calls.

const AF := preload("res://scripts/ui/ashes_frame.gd")
const MAX_PLATES := 4
const ENGAGE_DIST := 26.0
const SCAN := 0.1
const HEAD := 2.2          # m above the body origin when the actor does not say otherwise

var player: Node3D
var _font: Font
var _body: Font
var _scan := 0.0
var _picked: Array = []    # [{node, locked}]
var _fade := {}            # instance id -> alpha, so plates ease in and out
## Test hook: nodes to consider instead of the "team1" group.
var candidates_override: Array = []
var dim := 1.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = AF.title_font(700)
	_body = AF.font()


## True when this actor is fighting: locked on, or alerted / attacking (State.ALERT = 1, ATTACK = 2) within range.
static func is_engaged(state: int, dist: float, locked: bool, dead: bool) -> bool:
	if dead:
		return false
	if locked:
		return dist <= ENGAGE_DIST * 1.6
	return state >= 1 and state <= 2 and dist <= ENGAGE_DIST


## rows: [{node, dist, engaged, locked}] -> the picked rows: locked first, then nearest, at most `max_n`.
static func select(rows: Array, max_n := MAX_PLATES) -> Array:
	var out: Array = []
	for r: Dictionary in rows:
		if bool(r.get("engaged", false)):
			out.append(r)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if bool(a.get("locked", false)) != bool(b.get("locked", false)):
			return bool(a.get("locked", false))
		return float(a.get("dist", 0.0)) < float(b.get("dist", 0.0)))
	if out.size() > max_n:
		out.resize(max_n)
	return out


static func plate_info(n: Node) -> Dictionary:
	var nm := String(n.get("named")) if n.get("named") != null else ""
	if nm == "":
		nm = String(n.get("species")) if n.get("species") != null else String(n.name)
	nm = nm.replace("_", " ").capitalize()
	var mx := maxf(float(n.get("max_health")) if n.get("max_health") != null else 1.0, 1.0)
	var hp := float(n.get("health")) if n.get("health") != null else mx
	return {"name": nm, "level": int(n.get("level")) if n.get("level") != null else 1, "frac": clampf(hp / mx, 0.0, 1.0)}


func _process(delta: float) -> void:
	_scan -= delta
	if _scan <= 0.0:
		_scan = SCAN
		_pick()
	queue_redraw()


func _pick() -> void:
	if player == null or not is_instance_valid(player) or not player.is_inside_tree():
		_picked = []      # the HUD is built before the player joins the tree (48 boot errors without this)
		return
	var locked: Node = player.call("locked_target") if player.has_method("locked_target") else null
	var rows: Array = []
	var pool: Array = candidates_override if not candidates_override.is_empty() else get_tree().get_nodes_in_group("team1")
	var p := player.global_position
	for e in pool:
		if not (e is Node3D) or not is_instance_valid(e):
			continue
		var n3 := e as Node3D
		var d := n3.global_position.distance_to(p)
		if d > ENGAGE_DIST * 1.6:
			continue
		var st := int(n3.get("state")) if n3.get("state") != null else 0
		var is_lock := n3 == locked
		rows.append({"node": n3, "dist": d, "locked": is_lock,
			"engaged": is_engaged(st, d, is_lock, n3.get("dead") == true)})
	_picked = select(rows)


func _draw() -> void:
	var cam := _camera()
	if cam == null:
		return
	var live := {}
	for r: Dictionary in _picked:
		var n := r["node"] as Node3D
		if not is_instance_valid(n):
			continue
		live[n.get_instance_id()] = true
	for id: int in _fade.keys():
		if not live.has(id):
			_fade[id] = move_toward(float(_fade[id]), 0.0, 0.12)
			if float(_fade[id]) <= 0.0:
				_fade.erase(id)
	for r: Dictionary in _picked:
		var n := r["node"] as Node3D
		if not is_instance_valid(n):
			continue
		var id := n.get_instance_id()
		_fade[id] = move_toward(float(_fade.get(id, 0.0)), 1.0, 0.18)
		var head := n.global_position + Vector3.UP * (float(n.get("plate_height")) if n.get("plate_height") != null else HEAD)
		if cam.is_position_behind(head):
			continue
		_plate(_to_overlay(cam, cam.unproject_position(head)), plate_info(n), bool(r["locked"]), float(_fade[id]) * dim)


func _plate(at: Vector2, info: Dictionary, locked: bool, a: float) -> void:
	if a <= 0.01:
		return
	var title := "Lv %d  %s" % [int(info["level"]), String(info["name"])]
	var w := maxf(_font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 18.0, 96.0)
	var box := Rect2(at + Vector2(-w * 0.5, -40.0), Vector2(w, 30))
	draw_rect(box, Color(0.043, 0.039, 0.035, 0.82 * a))
	draw_rect(box, Color(AF.GOLD_BRIGHT if locked else AF.GOLD_DIM, (1.0 if locked else 0.8) * a), false, 1.5 if locked else 1.0)
	draw_string(_font, box.position + Vector2(0, 16), title, HORIZONTAL_ALIGNMENT_CENTER, w, 15, Color(AF.TEXT, a))
	var bar := Rect2(box.position + Vector2(6, 21), Vector2(w - 12, 5))
	draw_rect(bar, Color(0, 0, 0, 0.7 * a))
	var f := float(info["frac"])
	var col := Color("b8322a").lerp(Color("d96a3a"), f)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * f, bar.size.y)), Color(col, a))


## The player's own camera: the 3D world may render in a different viewport than this overlay.
func _camera() -> Camera3D:
	if player != null and is_instance_valid(player) and player.get("camera") is Camera3D:
		return player.get("camera") as Camera3D
	return get_viewport().get_camera_3d()


func _to_overlay(cam: Camera3D, p: Vector2) -> Vector2:
	var vs := cam.get_viewport().get_visible_rect().size
	if vs.x < 1.0 or vs.y < 1.0:
		return p
	return p / vs * size
