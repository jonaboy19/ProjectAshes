extends Node
const FaceState := preload("res://scripts/living_world/face_state.gd")
const NpcFaceCard := preload("res://scripts/living_world/npc_face_card.gd")

## Tier-A hero face + secondary motion driver (added by HeroTierA.upgrade, child of the skeleton; no bone changes).
## - Face: FaceState (docs/art/FACES.md) drives blink, moods, brows (hero_character.gdshader face_brow), the Lids patch and
##   the mouth card. set_mood(name), say(text), talk(seconds); set_expression() kept for older callers.
## - Secondary motion: a damped spring on the pelvis/head world acceleration feeds the `sway` uniform of the hair cards and
##   the HeroOutfit garment shader (hood tip, satchel, skirt hem lag and settle). Vertex-shader sway = zero bone cost.
## Cost: one _process per hero, ~10 blend-shape/uniform writes.

var sk: Skeleton3D
var parts := {}
var outfit: MeshInstance3D
var _face: MeshInstance3D
var _state := FaceState.new()
var _body_mat: ShaderMaterial        # the hero's OWN duplicate of the body material (never the shared cache)
var _card: NpcFaceCard
var _sent_brow := 9.0
var lids_allowed := true
var _pel := -1
var _head := -1
var _prev_p := Vector3.ZERO
var _prev_v := Vector3.ZERO
var _spring := Vector3.ZERO
var _spring_v := Vector3.ZERO
var _spring_h := Vector3.ZERO
var _spring_hv := Vector3.ZERO
var _prev_hp := Vector3.ZERO
var _prev_hv := Vector3.ZERO
var _primed := false


func setup(skeleton: Skeleton3D, p: Dictionary, garment: MeshInstance3D) -> void:
	sk = skeleton
	parts = p
	outfit = garment
	_face = parts.get("FaceSkin")
	_pel = sk.find_bone("pelvis")
	_head = sk.find_bone("Head")
	_body_mat = parts.get("BodyMat")
	var tree := Engine.get_main_loop() as SceneTree
	var q: Node = tree.root.get_node_or_null("Quality") if tree != null else null
	lids_allowed = q == null or int(q.get("tier")) >= 1
	# mouth card on the Head bone, every tier (one draw, the hero is always near); placement from face_offsets.json["hero"]
	var o := NpcFaceCard.offsets_for("hero")
	if not bool(o.get("disabled", false)):
		var off: Array = o.get("offset", [])
		var sz: Array = o.get("size", [])
		_card = NpcFaceCard.new(sk, Vector3(off[0], off[1], off[2]) if off.size() == 3 else Vector3(0.0, 0.08, 0.06),
			Vector2(sz[0], sz[1]) if sz.size() == 2 else NpcFaceCard.DEFAULT_SIZE, true, NpcFaceCard.layout_of(o))
		_card.state = _state


## Legacy dialogue hooks: a weighted expression maps to a mood / mouth flap.
func set_expression(n: String, weight: float, _seconds := 0.25) -> void:
	if n == "Smile":
		_state.set_mood("happy" if weight >= 0.5 else "neutral")
	elif n == "Brow_Up":
		_state.set_mood("surprise" if weight >= 0.5 else "neutral")


func talk(seconds: float) -> void:
	_state.say(seconds)


func set_mood(m: String) -> void:
	_state.set_mood(m)


func say(text: String) -> void:
	_state.say(FaceState.say_seconds(text))


func _bs(n: String, w: float) -> void:
	var lids: MeshInstance3D = parts.get("Lids")
	if lids and n.begins_with("Blink"):
		lids.visible = w > 0.03                     # Meshy hero: lid patches only exist while blinking
		var li := lids.find_blend_shape_by_name("Blink")
		if li >= 0:
			lids.set_blend_shape_value(li, w)
	if _face == null:
		return
	var i := _face.find_blend_shape_by_name(n)
	if i >= 0:
		_face.set_blend_shape_value(i, w)


func _process(dt: float) -> void:
	if sk == null or dt <= 0.0:
		return
	# face: blink, mood, mouth (FaceState); the Meshy hero shows it through the brow uniform, the Lids patch and the mouth card
	var f: Dictionary = _card.tick(dt) if _card != null and _card.is_valid() else _state.step(dt)
	var lid_w := maxf(float(f["lids"]), 0.0)
	if not lids_allowed:
		lid_w = 1.0 if lid_w >= 0.999 else 0.0               # LOW: blink only, no mood squint
	_bs("Blink_L", lid_w)
	_bs("Blink_R", lid_w)
	if _body_mat != null and absf(float(f["brow"]) - _sent_brow) > 0.005:
		_sent_brow = float(f["brow"])
		_body_mat.set_shader_parameter("face_brow", _sent_brow)
	_bs("Jaw_Open", float(f["mouth_open"]))
	_bs("Smile", maxf(float(f["mouth_curve"]), 0.0))
	_bs("Brow_Up", maxf(float(f["brow"]), 0.0))
	# secondary motion: springs on world acceleration of the pelvis (garments) and the head (hair)
	var p := (sk.global_transform * sk.get_bone_global_pose(_pel)).origin if _pel >= 0 else sk.global_position
	var hp := (sk.global_transform * sk.get_bone_global_pose(_head)).origin if _head >= 0 else p
	if not _primed:
		_prev_p = p
		_prev_hp = hp
		_primed = true
	var v := (p - _prev_p) / dt
	var a := (v - _prev_v) / dt
	_prev_p = p
	_prev_v = v
	var hv := (hp - _prev_hp) / dt
	var ha := (hv - _prev_hv) / dt
	_prev_hp = hp
	_prev_hv = hv
	# target: cloth trails the motion (drag) and swings back against acceleration; spring k=60, damping 9
	var tgt := (-v * 0.018 - a * 0.004).limit_length(0.09)
	tgt.y = minf(tgt.y, 0.02)
	_spring_v += ((tgt - _spring) * 60.0 - _spring_v * 9.0) * dt
	_spring += _spring_v * dt
	var tgt_h := (-hv * 0.012 - ha * 0.003).limit_length(0.05)
	_spring_hv += ((tgt_h - _spring_h) * 90.0 - _spring_hv * 10.0) * dt
	_spring_h += _spring_hv * dt
	if outfit and outfit.material_override is ShaderMaterial:
		(outfit.material_override as ShaderMaterial).set_shader_parameter("sway", outfit.global_transform.basis.inverse() * _spring)
	var hair: MeshInstance3D = parts.get("HairCards")
	if hair and hair.material_override is ShaderMaterial:
		(hair.material_override as ShaderMaterial).set_shader_parameter("sway", hair.global_transform.basis.inverse() * _spring_h)
