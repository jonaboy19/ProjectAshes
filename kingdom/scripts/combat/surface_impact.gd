extends RefCounted
## Weapon strikes that meet the world instead of a body: at a swing's hit time, if nothing was hit, a short ray
## from the chest along the swing finds a wall / prop / tree within reach and plays the material's impact
## (stone/metal: clang + sparks, wood: thunk + chips, earth: thud + dust). Listener only (player.swing_started /
## hit_confirmed), bound once from main.gd; no per-frame work.

const SQ := preload("res://scripts/world/surface_query.gd")
const K := preload("res://scripts/vfx/vfx_kit.gd")
const REACH := 1.5
## material -> [sound family, spark colour or null, particle count]
const IMPACT := {
	&"stone": ["block", Color(1.0, 0.8, 0.45), 14], &"cobble": ["block", Color(1.0, 0.8, 0.45), 14],
	&"metal": ["hit_metal", Color(1.0, 0.85, 0.5), 20], &"wood": ["hit_wood", Color(0.55, 0.40, 0.25), 8],
	&"dirt": ["hit_wood", Color(0.5, 0.42, 0.3), 6], &"mud": ["hit_wood", Color(0.3, 0.24, 0.17), 6],
	&"snow": ["hit_wood", Color(0.95, 0.97, 1.0), 8], &"grass": ["hit_wood", Color(0.45, 0.55, 0.3), 5],
	&"leaves": ["hit_wood", Color(0.45, 0.55, 0.3), 5], &"sand": ["hit_wood", Color(0.8, 0.72, 0.55), 6]}

var _p: Node3D
var _hit_id := -1


func bind(player: Node3D) -> void:
	_p = player
	if player.has_signal("swing_started"):
		player.connect("swing_started", _on_swing)
	if player.has_signal("hit_confirmed"):
		player.connect("hit_confirmed", func(_a: Array, _b: bool, _c: Array) -> void: _hit_id = int(player.call("swing_id")))


## Pure: what a strike on `material` sounds/looks like.
static func impact_for(material: StringName) -> Array:
	return IMPACT.get(material, IMPACT[&"stone"])


func _on_swing(_action: Resource, info: Dictionary) -> void:
	var p := _p
	if p == null or not p.is_inside_tree():
		return
	var id := int(info.get("id", -1))
	var hit_t := float(info.get("hit_t", 0.25))
	p.get_tree().create_timer(hit_t + 0.02).timeout.connect(func() -> void: _probe(id, float(info.get("yaw", 0.0))))


func _probe(id: int, _yaw: float) -> void:
	var p := _p
	if p == null or not is_instance_valid(p) or not p.is_inside_tree() or _hit_id == id:
		return
	if p.has_method("swing_id") and int(p.call("swing_id")) != id:
		return
	var fwd: Vector3 = p.call("facing") if p.has_method("facing") else -p.global_transform.basis.z
	var from := p.global_position + Vector3.UP * 1.1
	var ex: Array = [(p as CollisionObject3D).get_rid()] if p is CollisionObject3D else []
	var d := SQ.probe(p.get_world_3d().direct_space_state, from, from + fwd.normalized() * REACH, ex, 1)
	if not d["hit"] or d["collider"] is CharacterBody3D or d["collider"] is RigidBody3D:
		return
	play(p, d["position"], d["normal"], d["material"])


## Sound + particles for a strike on `material` at `at` (also usable by NPC fighters).
static func play(host: Node3D, at: Vector3, normal: Vector3, material: StringName) -> void:
	var spec := impact_for(material)
	var audio := host.get_tree().root.get_node_or_null(^"Audio")
	if audio != null and audio.has_method("play_sfx"):
		audio.call("play_sfx", String(spec[0]), at, -3.0)
	if DisplayServer.get_name() == "headless":
		return
	var col: Color = spec[1]
	var metal := material in [&"stone", &"cobble", &"metal"]
	K.emit(host.get_parent(), at + normal * 0.03, {"amount": int(spec[2]), "life": 0.35 if metal else 0.6,
		"dir": normal, "v": Vector2(3.0, 6.5) if metal else Vector2(1.0, 2.5), "spread": 55.0,
		"gravity": Vector3(0, -12, 0), "damping": Vector2(1, 3), "size": Vector2(0.03, 0.12) if metal else Vector2(0.05, 0.14),
		"stretch": metal, "mat": K.sprite_mat(K.DOT if metal else K.SMOKE_PUFF, K.pal_from(col), 5.0 if metal else 0.8)})
