class_name ContactIK
extends SkeletonModifier3D
## Cheap runtime ground contact for NPC work / rest clips on the UAL skeleton (kneel, plant, pick, sit on the ground).
##
## Clips are baked on the Quaternius UAL mannequin; the game's MakeHuman / G6 bodies have other limb proportions, so the
## same clip can float a kneeling villager 2-4 cm or push hands a few cm into the soil. Per frame (only while enabled):
##   1. pelvis: the lowest contact joint (knees, ankles, balls of the feet, minus their skin radius) is brought onto the
##      ground: float is pulled down, penetration pushed up (both clamped to MAX_PELVIS, smoothed, so it never pops);
##   2. hands: analytic two-bone arm IK keeps the wrist and the finger tips at least their skin radius above the ground,
##      the hand keeps its animated rotation and the elbow stays in its bend plane.
## Ground height comes from `ground_y` (world), which the owner refreshes from SurfaceQuery.ground a few times a second.
##
## Cost: no node exists unless an NPC within ContactIK.RANGE of the camera plays a clip whose sidecar says
## `"contact_ik": true`, at most ContactIK.BUDGET at once (a modifier forces a skeleton update every frame, see
## docs/anim/patches/P6_npc_foot_ik_cost.md). ~0.03 ms per NPC measured by tools_qa/anim_states/contact_ik_probe.gd.

const MAX_PELVIS := 0.10        # m, never move the body more than this
const SMOOTH := 12.0            # 1/s, pelvis offset follow rate
const R_KNEE := 0.055           # joint centre to skin under the knee cap / shin
const R_ANKLE := 0.06           # ankle joint above the floor when the shin rests on it
const R_BALL := 0.025           # ball of the foot joint above the sole
const R_HEEL := 0.075           # ankle joint above the floor for a standing heel
const R_WRIST := 0.035
const R_TIP := 0.012
const HAND_BAND := 0.36         # m: with hand_contact, a wrist this close above the ground is pulled onto it

var ground_y := 0.0             # world height of the surface under the character
var hand_contact := false       # clip puts the hands on the ground (dig, pull, pick): pull hands within HAND_BAND down onto it
var pelvis_off := 0.0           # current smoothed offset (m, world up)
var last_float := 0.0           # diagnostics: lowest contact above ground before the fix (m, negative = penetration)
var last_hand_lift := 0.0
var last_spine_bend := 0.0      # rad, diagnostics

const RANGE := 15.0              # m from the camera
const BUDGET := 4               # concurrent NPCs with contact IK
const REFRESH := 0.25           # s between ground / range checks

static var _live := 0
## Off with the command-line flag --no-contact-ik (A/B perf runs).
static var enabled := not OS.get_cmdline_user_args().has("--no-contact-ik")
static var cost_usec := 0      # diagnostics: summed modifier time (probe reads it)
static var cost_calls := 0

var _b := {}
var _t := 0.0
var _body: Node3D               # the character root (ground probe origin, distance to the camera)
var _anim: AnimationPlayer      # released as soon as the playing clip is no longer a contact clip
var _clamped: Array = []        # [[MeshInstance3D, previous material_override]] while the floor-clamp body material is on

const FLOOR_CLAMP := preload("res://shaders/npc/npc_floor_clamp.gdshader")
static var _clamp_cache := {}   # source material id -> ShaderMaterial
var _tips := {"l": PackedInt32Array(), "r": PackedInt32Array()}
var _ok := false
var _spine := -1


## Adds contact IK to `skeleton` if the NPC is near the camera and the budget allows. Returns the node or null.
static func request(skeleton: Skeleton3D, body: Node3D, anim: AnimationPlayer = null) -> ContactIK:
	if not enabled or skeleton == null or body == null or _live >= BUDGET:
		return null
	var cam := body.get_viewport().get_camera_3d() if body.is_inside_tree() else null
	if cam == null or cam.global_position.distance_to(body.global_position) > RANGE:
		return null
	var c := ContactIK.new()
	if OS.has_environment("CIK_STATS"):
		print("CIK_STATS request live=%d" % (_live + 1))
	c.name = "ContactIK"
	c._body = body
	c._anim = anim
	if anim != null:
		c.hand_contact = bool(LifeLibrary.info(String(anim.current_animation)).get("hand_contact", false))
	skeleton.add_child(c)
	return c


## Removes it again (clip ended / NPC left range).
func release() -> void:
	if is_queued_for_deletion():
		return
	queue_free()


func _enter_tree() -> void:
	_live += 1


func _exit_tree() -> void:
	_live -= 1
	_unclamp()
	if OS.has_environment("CIK_STATS"):
		print("CIK_STATS live=%d calls=%d avg_ms=%.4f" % [_live, cost_calls, float(cost_usec) / maxf(cost_calls, 1) / 1000.0])


func _ready() -> void:
	_resolve()
	if _body != null:          # managed by request(); a bare ContactIK (tests, tools) keeps its ground_y and never releases itself
		_refresh()
	else:
		set_process(false)


func _process(dt: float) -> void:
	_t += dt
	if _t >= REFRESH:
		_t = 0.0
		_refresh()


func _refresh() -> void:
	if _body == null or not is_instance_valid(_body):
		release()
		return
	if _anim != null and is_instance_valid(_anim) and _anim.current_animation != "" and not bool(LifeLibrary.info(String(_anim.current_animation)).get("contact_ik", false)):
		release()
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null or cam.global_position.distance_to(_body.global_position) > RANGE * 1.15:
		release()
		return
	var space := _body.get_world_3d().direct_space_state
	var excl: Array[RID] = []
	if _body is CollisionObject3D:
		excl.append((_body as CollisionObject3D).get_rid())
	var hit: Dictionary = SurfaceQuery.ground(space, _body.global_position, excl)
	ground_y = float((hit.get("position", _body.global_position) as Vector3).y) if bool(hit.get("hit", false)) else _body.global_position.y
	if _clamped.is_empty():
		_clamp()
	for e: Array in _clamped:
		if is_instance_valid(e[0]):
			(e[0] as GeometryInstance3D).set_instance_shader_parameter(&"floor_y", ground_y)


## Body meshes get the floor-clamp material (cloth hems lie on the ground instead of sinking through it).
func _clamp() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	for mi: MeshInstance3D in sk.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or mi.mesh.get_surface_count() != 1 or mi.material_override is ShaderMaterial:
			continue
		var src := (mi.material_override if mi.material_override != null else mi.mesh.surface_get_material(0)) as BaseMaterial3D
		if src == null:
			continue
		var key := src.get_instance_id()
		var sm: ShaderMaterial = _clamp_cache.get(key)
		if sm == null:
			sm = _clamp_material(src)
			_clamp_cache[key] = sm
		_clamped.append([mi, mi.material_override])
		mi.material_override = sm
		mi.set_instance_shader_parameter(&"floor_y", ground_y)


## The body's own StandardMaterial3D converted to its generated shader (exact same look), with the floor clamp
## injected at the top of vertex(): skinned vertices below `floor_y + 6 mm` are laid onto the ground.
static func _clamp_material(src: BaseMaterial3D) -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	sm.shader = FLOOR_CLAMP
	sm.set_shader_parameter("albedo_tex", src.albedo_texture)
	sm.set_shader_parameter("has_tex", src.albedo_texture != null)
	sm.set_shader_parameter("albedo_color", src.albedo_color)
	sm.set_shader_parameter("roughness", src.roughness)
	sm.set_shader_parameter("metallic", src.metallic)
	sm.set_shader_parameter("specular", src.metallic_specular)
	sm.set_shader_parameter("use_vertex_color", src.vertex_color_use_as_albedo)
	sm.set_shader_parameter("vertex_color_srgb", src.vertex_color_is_srgb)
	sm.set_shader_parameter("vc_to_srgb", not src.vertex_color_is_srgb)   # matches the StandardMaterial3D look (A/B shots)
	sm.set_shader_parameter("has_normal", src.normal_enabled and src.normal_texture != null)
	sm.set_shader_parameter("normal_tex", src.normal_texture)
	sm.set_shader_parameter("normal_scale", src.normal_scale)
	sm.set_shader_parameter("has_ao", src.ao_enabled and src.ao_texture != null)
	sm.set_shader_parameter("ao_tex", src.ao_texture)
	sm.set_shader_parameter("ao_light_affect", src.ao_light_affect)
	return sm


func _unclamp() -> void:
	for e: Array in _clamped:
		if is_instance_valid(e[0]):
			(e[0] as MeshInstance3D).material_override = e[1]
	_clamped.clear()


func _resolve() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	for n: String in ["pelvis", "thigh_l", "calf_l", "foot_l", "ball_l", "thigh_r", "calf_r", "foot_r", "ball_r",
			"upperarm_l", "lowerarm_l", "hand_l", "upperarm_r", "lowerarm_r", "hand_r"]:
		var i := sk.find_bone(n)
		if i < 0:
			return
		_b[n] = i
	for s: String in ["l", "r"]:
		var t := PackedInt32Array()
		for f: String in ["thumb", "index", "middle", "ring", "pinky"]:
			var i := sk.find_bone("%s_03_%s" % [f, s])
			if i >= 0:
				t.append(i)
		_tips[s] = t
	_spine = sk.find_bone("spine_02")
	_ok = true


func _process_modification_with_delta(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_modify(delta)
	cost_usec += Time.get_ticks_usec() - t0
	cost_calls += 1


func _modify(delta: float) -> void:
	if not _ok:
		_resolve()
		if not _ok:
			return
	var sk := get_skeleton()
	var xf := sk.global_transform
	var inv := xf.affine_inverse()
	var up := (inv.basis * Vector3.UP).normalized()          # world up in skeleton space
	var scale := (xf.basis * up).length()                    # skeleton -> world metres along up
	var g_local := inv * Vector3(0.0, ground_y, 0.0)
	var g_h := up.dot(g_local)                               # ground height measured along `up` in skeleton space

	# ---- 1. pelvis
	var lowest := INF
	for s: String in ["l", "r"]:
		var knee := sk.get_bone_global_pose(_b["calf_" + s]).origin
		var ankle := sk.get_bone_global_pose(_b["foot_" + s]).origin
		var ball := sk.get_bone_global_pose(_b["ball_" + s]).origin
		lowest = minf(lowest, (up.dot(knee) - g_h) * scale - R_KNEE)
		lowest = minf(lowest, (up.dot(ankle) - g_h) * scale - R_ANKLE)
		lowest = minf(lowest, (up.dot(ball) - g_h) * scale - R_BALL)
	last_float = lowest
	var want := clampf(-lowest, -MAX_PELVIS, MAX_PELVIS)
	pelvis_off = lerpf(pelvis_off, want, clampf(delta * SMOOTH, 0.0, 1.0))
	if absf(pelvis_off) > 0.0005:
		var pi: int = _b["pelvis"]
		var gp := sk.get_bone_global_pose(pi)
		gp.origin += up * (pelvis_off / maxf(scale, 1e-4))
		sk.set_bone_global_pose(pi, gp)

	# ---- 2. hands (two passes: if a hand-contact target is out of the arm's reach, bend the spine forward first)
	last_hand_lift = 0.0
	var plan := _hand_plan(sk, up, g_h, scale)
	if hand_contact and _spine >= 0:
		var short := 0.0
		var dir := Vector3.ZERO
		for p: Dictionary in plan:
			var sh: Vector3 = sk.get_bone_global_pose(p["ua"]).origin
			short = maxf(short, sh.distance_to(p["target"]) - p["reach"] * 0.97)
			dir += (p["target"] as Vector3) - sh
		if short > 0.005:
			dir -= up * up.dot(dir)
			if dir.length() > 1e-4:
				var axis := up.cross(dir.normalized()).normalized()
				var sp := sk.get_bone_global_pose(_spine)
				var arm := sp.origin.distance_to(sk.get_bone_global_pose(plan[0]["ua"]).origin)
				var ang := clampf(short / maxf(arm, 0.1), 0.0, 0.6)
				# rotate so the shoulders go down/forward: positive angle about axis = up x dir tips the top toward dir
				sk.set_bone_global_pose(_spine, Transform3D(Basis(axis, ang) * sp.basis, sp.origin))
				last_spine_bend = ang
				plan = _hand_plan(sk, up, g_h, scale)
	for p: Dictionary in plan:
		last_hand_lift = maxf(last_hand_lift, absf(p["need"]))
		_two_bone(sk, p["ua"], p["la"], p["ha"], p["target"])


## Per hand that needs a correction: {ua, la, ha, need (m, + = up), target (skeleton space), reach}.
func _hand_plan(sk: Skeleton3D, up: Vector3, g_h: float, scale: float) -> Array:
	var out := []
	for s: String in ["l", "r"]:
		var ua: int = _b["upperarm_" + s]
		var la: int = _b["lowerarm_" + s]
		var ha: int = _b["hand_" + s]
		var hand := sk.get_bone_global_pose(ha)
		var need := R_WRIST - (up.dot(hand.origin) - g_h) * scale
		for t: int in _tips[s]:
			need = maxf(need, R_TIP - (up.dot(sk.get_bone_global_pose(t).origin) - g_h) * scale)
		if need <= 0.001:
			if not hand_contact:
				continue
			# shorter-armed bodies: the authored ground touch ends in the air; pull a near-ground hand down onto it
			# (need = -(lowest of wrist / finger tips above their skin radius))
			var h := (up.dot(hand.origin) - g_h) * scale
			if h >= HAND_BAND:
				continue
			var w := clampf((HAND_BAND - h) / (HAND_BAND * 0.5), 0.0, 1.0)
			need = need * w * w * (3.0 - 2.0 * w)
			if need >= -0.001:
				continue
		var a := sk.get_bone_global_pose(ua).origin
		var reach := a.distance_to(sk.get_bone_global_pose(la).origin) + sk.get_bone_global_pose(la).origin.distance_to(hand.origin)
		out.append({"ua": ua, "la": la, "ha": ha, "need": need, "target": hand.origin + up * (need / maxf(scale, 1e-4)), "reach": reach})
	return out


## Moves the end of upper -> lower -> end to `target` (skeleton space), elbow kept in its plane, end keeps its rotation.
func _two_bone(sk: Skeleton3D, upper: int, lower: int, end: int, target: Vector3) -> void:
	var mu := sk.get_bone_global_pose(upper)
	var ml := sk.get_bone_global_pose(lower)
	var me := sk.get_bone_global_pose(end)
	var a := mu.origin
	var b := ml.origin
	var c := me.origin
	var la := a.distance_to(b)
	var lb := b.distance_to(c)
	var d := minf(a.distance_to(target), (la + lb) * 0.999)
	if d < 1e-4 or la < 1e-4 or lb < 1e-4:
		return
	var u := (target - a).normalized()
	var v := (b - a) - u * (b - a).dot(u)
	if v.length() < 1e-5:
		return
	v = v.normalized()
	var al := acos(clampf((la * la + d * d - lb * lb) / (2.0 * la * d), -1.0, 1.0))
	var b2 := a + (u * cos(al) + v * sin(al)) * la
	var c2 := a + u * d
	var r1 := Quaternion((b - a).normalized(), (b2 - a).normalized())
	var r2 := Quaternion((r1 * (c - b)).normalized(), (c2 - b2).normalized())
	sk.set_bone_global_pose(upper, Transform3D(Basis(r1) * mu.basis, a))
	sk.set_bone_global_pose(lower, Transform3D(Basis(r2 * r1) * ml.basis, b2))
	sk.set_bone_global_pose(end, Transform3D(me.basis, c2))
