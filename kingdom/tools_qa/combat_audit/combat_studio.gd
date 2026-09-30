extends Node3D
## Combat animation studio (docs/anim/COMBAT_AUDIT.md). Plays attack / reaction clips on the
## REAL player rig (Assets.character("Player") = MakeHuman on the UAL skeleton, with the game's
## weapon attachments), frame by frame at 30 fps, and
##   1. measures every frame: blade tip / base path and speed, hand speed, pelvis and chest yaw,
##      upper-arm spin (kinetic chain order), feet (plant + slide), pelvis travel (step-in),
##      blade edge alignment (edge leads vs flat slap) and blade-through-body penetration;
##   2. derives the combat markers: windup_end, hit_start, hit_end (fast frames), peak,
##      settle, combo_window, cancel_window (written to <out>/metrics.json);
##   3. optionally renders every frame as FRONT | SIDE | TOP views plus a tip-speed graph
##      (<out>/<clip>/f_########.png) for contact sheets (tools/qa/video_to_sheets.sh).
##
## Never run --headless when rendering (black frames). Metrics alone are fine headless.
##   Godot --path kingdom --rendering-method mobile res://tools_qa/combat_audit/combat_studio.tscn -- \
##       --out=<abs dir> --clips=Sword_Regular_A,Sword_Regular_B [--rate=1.7] [--weapon=sword_shield]
##       [--layer=upper] [--extra=res://a.glb;res://b.glb] [--render] [--list]
## --clips accepts Name or Name@rate (per-clip playback rate, e.g. the game's 1.7x).
## --weapon: sword_shield (player default) | sword | 2h | axe | dagger | spear | bow | none
## --layer=upper reproduces the game's CharacterAnimator at a standstill: legs + hips from Idle,
##   everything above the pelvis from the clip (LOWER_KEYS filter).

const FPS := 30.0
const W := 1080
const VIEW_H := 470
const GRAPH_H := 110
const LOWER_KEYS := ["root", "hips", "pelvis", "upperleg", "lowerleg", "thigh", "calf", "foot", "toes",
	"ball", "heel", "knee", "ik_", "IK", "control-"]
const WEAPONS := "res://assets/incoming/quaternius/fantasy-props-megakit/Exports/glTF/"

var args := {}
var out_dir := ""
var body: Node3D
var sk: Skeleton3D
var ap: AnimationPlayer
var anims := {}                 # name -> Animation (game library + extras)
var blade_att: Node3D           # the prop node carrying the blade (child of a BoneAttachment3D)
var blade_bone := -1
var blade_local_tip := Vector3.ZERO
var blade_local_base := Vector3.ZERO
var blade_local_grip := Vector3.ZERO
var blade_local_thin := Vector3.ZERO   # blade flat normal (thin axis), prop-parent space
var bones := {}
var pair_body: Node3D
var pair_sk: Skeleton3D
var views: Array[SubViewport] = []
var cams: Array[Camera3D] = []
var overlay: ImmediateMesh
var overlay_top: ImmediateMesh
var graph: Control
var info_label: Label
var cur := {}                   # current clip data for the graph


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and "=" in a:
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1]
		elif a.begins_with("--"):
			args[a.substr(2)] = true
	out_dir = String(args.get("out", OS.get_user_data_dir().path_join("combat_studio")))
	DirAccess.make_dir_recursive_absolute(out_dir)
	_build_body(String(args.get("weapon", "sword_shield")))
	if args.has("pair"):
		# Paired clips (finishers): a second rig 1.2 m in front of the attacker, facing it, plays the victim clip
		# on the same frame clock. --pair=<VictimClip>; the views widen to frame both.
		pair_body = Assets.character("Player", 1.8, [] as Array[String])
		add_child(pair_body)
		pair_body.position = Vector3(0, 0, float(args.get("pair_dist", "1.2")))
		pair_body.rotation.y = PI
		pair_sk = pair_body.find_children("*", "Skeleton3D", true, false)[0]
		(Assets.animation_player(pair_body) as AnimationPlayer).active = false
	for p: String in String(args.get("extra", "")).split(";", false):
		_add_lib(p)
	if args.has("probe"):
		# Rest pose (T-pose): blade axis / flat normal in Godot world and in Blender axes (x, -z, y),
		# for tools/anim/combat/combat_common.set_blade_rest().
		for b in sk.get_bone_count():
			sk.set_bone_pose(b, sk.get_bone_rest(b))
		sk.force_update_all_bone_transforms()
		var bl := _blade()
		var ax: Vector3 = ((bl["tip"] as Vector3) - (bl["grip"] as Vector3)).normalized()
		var fl: Vector3 = bl["thin"]
		var hand := _bxf("hand_r")
		print("PROBE blade_axis_godot=%s flat_godot=%s" % [ax, fl])
		print("PROBE blender axis=(%.4f, %.4f, %.4f) flat=(%.4f, %.4f, %.4f)" % [ax.x, -ax.z, ax.y, fl.x, -fl.z, fl.y])
		print("PROBE hand_r origin=%s basis=%s tip=%s grip=%s len=%.3f" % [hand.origin, hand.basis, bl["tip"], bl["grip"], ((bl["tip"] as Vector3) - (bl["grip"] as Vector3)).length()])
		print("PROBE blade_axis_in_hand_bone=%s flat_in_hand_bone=%s" % [(hand.basis.inverse() * ax).normalized(), (hand.basis.inverse() * fl).normalized()])
		get_tree().quit()
		return
	if args.has("list"):
		var names := anims.keys()
		names.sort()
		for n: String in names:
			print("CLIP %s %.3f" % [n, (anims[n] as Animation).length])
		get_tree().quit()
		return
	if args.has("render"):
		_build_views()
	_run.call_deferred()


# --- rig ---------------------------------------------------------------------------------

func _build_body(weapon: String) -> void:
	var keep: Array[String] = []
	match weapon:
		"sword_shield": keep = ["1H_Sword", "Round_Shield"]
		"sword": keep = ["1H_Sword"]
		"2h": keep = ["2H_Sword"]
		"axe": keep = ["Axe"]
		"shield": keep = ["Round_Shield"]
	body = Assets.character("Player", 1.8, keep)
	add_child(body)
	sk = body.find_children("*", "Skeleton3D", true, false)[0]
	ap = Assets.animation_player(body)
	ap.active = false            # poses are written by hand from the Animation tracks
	for n in ap.get_animation_list():
		anims[String(n)] = ap.get_animation(n)
	for b in ["pelvis", "spine_01", "spine_03", "neck_01", "Head", "upperarm_l", "upperarm_r", "lowerarm_l", "lowerarm_r",
			"hand_l", "hand_r", "thigh_l", "thigh_r", "calf_l", "calf_r", "foot_l", "foot_r", "ball_l", "ball_r", "root"]:
		bones[b] = sk.find_bone(b)
	match weapon:
		"dagger":
			Assets._attach(sk, "hand_r", WEAPONS + "Table_Knife.gltf", 0.38, Vector3(0.05, 0.02, 0), Vector3(0, 0, -90))
		"spear":
			_attach_procedural_spear()
		"bow":
			_attach_procedural_bow()
	_find_blade()


func _attach_procedural_spear() -> void:
	var att := BoneAttachment3D.new()
	att.bone_name = "hand_r"
	sk.add_child(att)
	var rs := Assets._rig_scale(sk)
	var root := Node3D.new()
	root.rotation_degrees = Vector3(0, 0, -90)
	root.position = Vector3(0.05, 0.02, 0) / rs
	att.add_child(root)
	var shaft := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.018
	cyl.bottom_radius = 0.018
	cyl.height = 2.1
	shaft.mesh = cyl
	shaft.position = Vector3(0, 0.45, 0)       # 0.6 m behind the grip, 1.5 m in front
	var tip := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.045
	cone.height = 0.28
	tip.mesh = cone
	tip.position = Vector3(0, 1.64, 0)
	tip.scale = Vector3(1.0, 1.0, 0.35)        # flat leaf blade: thin along local Z
	var hold := Node3D.new()
	hold.scale = Vector3.ONE / rs
	hold.add_child(shaft)
	hold.add_child(tip)
	root.add_child(hold)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.4, 0.25)
	shaft.material_override = mat


func _attach_procedural_bow() -> void:
	var att := BoneAttachment3D.new()
	att.bone_name = "hand_l"
	sk.add_child(att)
	var rs := Assets._rig_scale(sk)
	var hold := Node3D.new()
	hold.scale = Vector3.ONE / rs
	att.add_child(hold)
	var limb := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = 0.6
	t.outer_radius = 0.63
	limb.mesh = t
	limb.rotation_degrees = Vector3(0, 0, 90)
	limb.scale = Vector3(1.0, 1.0, 0.25)
	limb.position = Vector3(0.0, 0.0, -0.45)
	hold.add_child(limb)


## Finds the longest visible prop on a hand attachment and derives the blade axis in its
## parent (attachment) space: grip end, blade base, tip, and the thin (flat) axis.
func _find_blade() -> void:
	for att in sk.find_children("*", "BoneAttachment3D", true, false):
		var a := att as BoneAttachment3D
		if a.bone_name != "hand_r":
			continue
		for child in a.get_children():
			var prop := child as Node3D
			var box := _box_in(prop, a)
			if box.size == Vector3.ZERO:
				continue
			var ax := 0
			for i in 3:
				if box.size[i] > box.size[ax]:
					ax = i
			var thin := 0
			for i in 3:
				if box.size[i] < box.size[thin]:
					thin = i
			var c := box.get_center()
			var lo := c
			var hi := c
			lo[ax] = box.position[ax]
			hi[ax] = box.end[ax]
			var tip := hi if hi.length() > lo.length() else lo
			var grip := lo if tip == hi else hi
			blade_att = a
			blade_bone = sk.find_bone("hand_r")
			blade_local_tip = tip
			blade_local_grip = grip
			# The blade starts past the hilt: ~28 % of the prop length from the grip end
			# (sword: guard; spear: where the shaft leaves the front hand).
			blade_local_base = grip.lerp(tip, 0.28)
			var n := Vector3.ZERO
			n[thin] = 1.0
			blade_local_thin = n
			return


func _box_in(node: Node3D, space: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mi in node.find_children("*", "MeshInstance3D", true, false) + ([node] if node is MeshInstance3D else []):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var xf := Transform3D.IDENTITY
		var cur_n: Node = m
		while cur_n != null and cur_n != space:
			if cur_n is Node3D:
				xf = (cur_n as Node3D).transform * xf
			cur_n = cur_n.get_parent()
		var b := xf * m.mesh.get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out


func _add_lib(path: String) -> void:
	var inst: Node
	if not path.begins_with("res://"):
		# Work-in-progress GLB outside the project: load at runtime (no import, no .godot writes).
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		if doc.append_from_file(path, state) != OK:
			push_warning("cannot load " + path)
			return
		inst = doc.generate_scene(state)
	elif not ResourceLoader.exists(path):
		push_warning("missing lib " + path)
		return
	else:
		inst = (load(path) as PackedScene).instantiate()
	var found := inst.find_children("*", "AnimationPlayer", true, false)
	if found.is_empty():
		inst.free()
		return
	var p := found[0] as AnimationPlayer
	for n in p.get_animation_list():
		anims[String(n)] = p.get_animation(n).duplicate(true)
	inst.free()


# --- pose sampling -----------------------------------------------------------------------

func _is_lower(bone: String) -> bool:
	for k: String in LOWER_KEYS:
		if bone.begins_with(k) or bone.contains(k):
			return true
	return false


## Writes the clip pose at time t straight from the Animation tracks (root position disabled,
## as in-game). `lower_from` (optional) supplies the legs + pelvis (upper-body layering).
func _apply(anim: Animation, t: float, lower_from: Animation = null, t_lower := 0.0) -> void:
	for b in sk.get_bone_count():
		sk.set_bone_pose_position(b, sk.get_bone_rest(b).origin)
		sk.set_bone_pose_rotation(b, sk.get_bone_rest(b).basis.get_rotation_quaternion())
		sk.set_bone_pose_scale(b, Vector3.ONE)
	_apply_tracks(anim, t, 0 if lower_from == null else 1)
	if lower_from:
		_apply_tracks(lower_from, t_lower, 2)
		if args.has("rootmotion"):
			# the capsule lunge (matched to the attack's root curve) also carries the locomotion legs
			for tr in anim.get_track_count():
				if String(anim.track_get_path(tr)).ends_with(":root") and anim.track_get_type(tr) == Animation.TYPE_POSITION_3D:
					sk.set_bone_pose_position(sk.find_bone("root"), anim.position_track_interpolate(tr, t))
	sk.force_update_all_bone_transforms()


## part: 0 all bones, 1 upper only, 2 lower only.
func _apply_tracks(anim: Animation, t: float, part: int) -> void:
	for tr in anim.get_track_count():
		var path := String(anim.track_get_path(tr))
		var colon := path.find(":")
		if colon < 0:
			continue
		var bname := path.substr(colon + 1)
		var b := sk.find_bone(bname)
		if b < 0:
			continue
		if part != 0 and (_is_lower(bname) == (part == 1)):
			continue
		match anim.track_get_type(tr):
			Animation.TYPE_POSITION_3D:
				if bname == "root" and not args.has("rootmotion"):
					continue   # in place, as in-game; --rootmotion simulates a capsule lunge matched to the root track
				sk.set_bone_pose_position(b, anim.position_track_interpolate(tr, t))
			Animation.TYPE_ROTATION_3D:
				sk.set_bone_pose_rotation(b, anim.rotation_track_interpolate(tr, t))
			Animation.TYPE_SCALE_3D:
				sk.set_bone_pose_scale(b, anim.scale_track_interpolate(tr, t))


func _root_travel(anim: Animation) -> Vector3:
	for tr in anim.get_track_count():
		var path := String(anim.track_get_path(tr))
		if path.ends_with(":root") and anim.track_get_type(tr) == Animation.TYPE_POSITION_3D:
			return anim.position_track_interpolate(tr, anim.length) - anim.position_track_interpolate(tr, 0.0)
	return Vector3.ZERO


func _bp(name: String) -> Vector3:
	var i: int = bones.get(name, -1)
	if i < 0:
		return Vector3.ZERO
	return (sk.global_transform * sk.get_bone_global_pose(i)).origin


func _bxf(name: String) -> Transform3D:
	var i: int = bones.get(name, -1)
	return sk.global_transform * sk.get_bone_global_pose(i) if i >= 0 else Transform3D.IDENTITY


func _blade() -> Dictionary:
	if blade_att == null:
		return {}
	var hand := sk.global_transform * sk.get_bone_global_pose(blade_bone)
	# BoneAttachment3D places its children at the bone pose (in skeleton space).
	var xf := hand
	return {"tip": xf * blade_local_tip, "base": xf * blade_local_base, "grip": xf * blade_local_grip,
		"thin": (xf.basis * blade_local_thin).normalized()}


func _yaw_of(v: Vector3) -> float:
	return atan2(v.x, v.z)


# --- analysis ----------------------------------------------------------------------------

func _analyse(name: String, rate: float, layer: String) -> Dictionary:
	var anim: Animation = anims[name]
	var idle: Animation = anims.get("Idle", anims.get("Idle_Loop", null))
	var n := int(ceil(anim.length / rate * FPS)) + 1
	var rows: Array = []
	for i in n:
		var t := minf(i / FPS * rate, anim.length)
		if layer == "upper" and idle:
			_apply(anim, t, idle, fmod(i / FPS, idle.length))
		else:
			_apply(anim, t)
		var bl := _blade()
		var r := {"f": i, "t": t}
		for b in ["pelvis", "spine_03", "Head", "hand_r", "hand_l", "foot_l", "foot_r", "ball_l", "ball_r",
				"thigh_l", "thigh_r", "upperarm_l", "upperarm_r", "lowerarm_r", "calf_l", "calf_r", "neck_01", "spine_01", "lowerarm_l"]:
			r[b] = _bp(b)
		r["hip_yaw"] = _yaw_of((r["thigh_l"] as Vector3) - (r["thigh_r"] as Vector3))
		r["sh_yaw"] = _yaw_of((r["upperarm_l"] as Vector3) - (r["upperarm_r"] as Vector3))
		r["arm_basis"] = _bxf("upperarm_r").basis.get_rotation_quaternion()
		if not bl.is_empty():
			r["tip"] = bl["tip"]
			r["base"] = bl["base"]
			r["grip"] = bl["grip"]
			r["thin"] = bl["thin"]
		rows.append(r)
	# Unwrap the yaw tracks (no +-180 jumps) so ranges and x-factor are real angles.
	for k in ["hip_yaw", "sh_yaw"]:
		var prev_raw := float(rows[0][k])
		for i in range(1, rows.size()):
			var raw := float(rows[i][k])
			rows[i][k] = float(rows[i - 1][k]) + angle_difference(prev_raw, raw)
			prev_raw = raw
	return _derive(name, rate, layer, anim, rows)


func _speed(rows: Array, key: String, i: int) -> float:
	if i <= 0:
		return 0.0
	return ((rows[i][key] as Vector3) - (rows[i - 1][key] as Vector3)).length() * FPS


func _ang_rate(rows: Array, key: String, i: int) -> float:
	if i <= 0:
		return 0.0
	return absf(angle_difference(float(rows[i - 1][key]), float(rows[i][key]))) * FPS


func _derive(name: String, rate: float, layer: String, anim: Animation, rows: Array) -> Dictionary:
	var n := rows.size()
	var has_blade: bool = rows[0].has("tip")
	var key := "tip" if has_blade else "hand_r"
	var sp: Array[float] = []
	var hand_sp: Array[float] = []
	var hip_w: Array[float] = []
	var sh_w: Array[float] = []
	var arm_w: Array[float] = []
	for i in n:
		sp.append(_speed(rows, key, i))
		hand_sp.append(_speed(rows, "hand_r", i))
		hip_w.append(_ang_rate(rows, "hip_yaw", i))
		sh_w.append(_ang_rate(rows, "sh_yaw", i))
		var aw := 0.0
		if i > 0:
			aw = (rows[i - 1]["arm_basis"] as Quaternion).angle_to(rows[i]["arm_basis"] as Quaternion) * FPS
		arm_w.append(aw)
	# 3-tap smoothing of the tip speed (single-frame spikes from key noise are not strikes).
	var s: Array[float] = []
	for i in n:
		s.append((sp[maxi(i - 1, 0)] + 2.0 * sp[i] + sp[mini(i + 1, n - 1)]) / 4.0)
	var vmax := 0.0
	for v in s:
		vmax = maxf(vmax, v)
	# Strikes: local maxima >= 55 % of the clip max, separated by a dip below 50 % of the smaller one.
	var peaks: Array[int] = []
	for i in range(1, n - 1):
		if s[i] >= 0.55 * vmax and s[i] >= s[i - 1] and s[i] >= s[i + 1]:
			if peaks.is_empty():
				peaks.append(i)
				continue
			var last := peaks[-1]
			var dip := INF
			for j in range(last, i + 1):
				dip = minf(dip, s[j])
			if dip < 0.5 * minf(s[last], s[i]) and i - last >= 5:
				peaks.append(i)
			elif s[i] > s[last]:
				peaks[-1] = i
	var strikes: Array = []
	var prev_end := 0
	for p in peaks:
		var thr := 0.6 * s[p]
		var a := p
		while a > prev_end + 1 and s[a - 1] >= thr:
			a -= 1
		var b := p
		while b < n - 1 and s[b + 1] >= thr:
			b += 1
		# Wind-up end: the loaded moment = last tip-speed minimum before the strike ramps up.
		var w := a
		while w > prev_end + 1 and s[w - 1] <= s[w]:
			w -= 1
		# Follow-through ends when the tip drops under 15 % of the strike peak.
		var ft := b
		while ft < n - 1 and s[ft] > 0.15 * s[p]:
			ft += 1
		var st := {"windup_end": w, "hit_start": a, "peak": p, "hit_end": b, "follow_end": ft,
			"contact_frames": b - a + 1, "peak_speed": snappedf(s[p], 0.01)}
		# Kinetic chain inside [windup_end-2, peak+2]: frame of peak hips yaw rate, shoulders yaw rate,
		# upper-arm spin, hand speed, tip speed. Hips lead: expect hip <= shoulders <= arm <= hand <= tip.
		var lo := maxi(w - 3, 0)
		var hi := mini(p + 2, n - 1)
		st["chain"] = {"hips": _argmax(hip_w, lo, hi), "shoulders": _argmax(sh_w, lo, hi), "arm": _argmax(arm_w, lo, hi),
			"hand": _argmax(hand_sp, lo, hi), "tip": _argmax(sp, lo, hi)}
		# Anticipation: how far the tip travels backwards (against the strike direction) before w.
		var strike_dir := ((rows[b][key] as Vector3) - (rows[a][key] as Vector3))
		var back := 0.0
		if strike_dir.length() > 0.01:
			strike_dir = strike_dir.normalized()
			var start_i := maxi(prev_end, 0)
			for j in range(start_i + 1, w + 1):
				var d := ((rows[j][key] as Vector3) - (rows[j - 1][key] as Vector3)).dot(strike_dir)
				if d < 0.0:
					back -= d
		st["backswing_m"] = snappedf(back, 0.01)
		# Hip wind (counter-rotation) before the strike and total hip turn through it, degrees.
		var hip_min := INF
		var hip_maxv := -INF
		for j in range(maxi(prev_end, 0), ft + 1):
			var hy := rad_to_deg(float(rows[j]["hip_yaw"]))
			hip_min = minf(hip_min, hy)
			hip_maxv = maxf(hip_maxv, hy)
		st["hip_range_deg"] = snappedf(hip_maxv - hip_min, 0.1) if hip_maxv >= hip_min else 0.0
		var xf := 0.0
		for j in range(maxi(prev_end, 0), p + 1):
			xf = maxf(xf, absf(rad_to_deg(angle_difference(float(rows[j]["hip_yaw"]), float(rows[j]["sh_yaw"])))))
		st["xfactor_deg"] = snappedf(xf, 0.1)
		# Arc: tip path length vs chord over the fast frames (1.0 = a straight line).
		var path := 0.0
		for j in range(a + 1, b + 1):
			path += ((rows[j][key] as Vector3) - (rows[j - 1][key] as Vector3)).length()
		var chord := ((rows[b][key] as Vector3) - (rows[a][key] as Vector3)).length()
		st["arc_ratio"] = snappedf(path / maxf(chord, 0.001), 0.01)
		st["tip_path_m"] = snappedf(path, 0.01)
		# Strike direction over the fast frames in the character frame (+x = its left, +y up, +z forward),
		# and where the tip is at the hit (height, reach): left/right alternation and target height read from these.
		var sd := ((rows[b][key] as Vector3) - (rows[a][key] as Vector3)).normalized()
		st["tip_dir"] = [snappedf(sd.x, 0.01), snappedf(sd.y, 0.01), snappedf(sd.z, 0.01)]
		var tp := rows[p][key] as Vector3
		st["tip_at_hit"] = [snappedf(tp.x, 0.01), snappedf(tp.y, 0.01), snappedf(tp.z, 0.01)]
		# Overshoot: tip keeps travelling past hit_end (follow-through distance).
		var fol := 0.0
		for j in range(b + 1, ft + 1):
			fol += ((rows[j][key] as Vector3) - (rows[j - 1][key] as Vector3)).length()
		st["follow_m"] = snappedf(fol, 0.01)
		if has_blade:
			# Edge alignment: share of the tip velocity along the blade's flat normal (0 = edge leads, 1 = flat slap).
			var flat := 0.0
			var cnt := 0
			for j in range(a, b + 1):
				if j == 0:
					continue
				var v := (rows[j]["tip"] as Vector3) - (rows[j - 1]["tip"] as Vector3)
				if v.length() > 0.001:
					flat += absf(v.normalized().dot(rows[j]["thin"] as Vector3))
					cnt += 1
			st["flat_ratio"] = snappedf(flat / maxf(cnt, 1), 0.01)
		strikes.append(st)
		prev_end = ft
	# Whole-clip checks.
	var clip := {"clip": name, "rate": rate, "layer": layer, "length_s": snappedf(anim.length, 0.001),
		"frames_at_rate": n, "strikes": strikes, "root_travel_m": snappedf(Vector2(_root_travel(anim).x, _root_travel(anim).z).length() * _scale(), 0.01)}
	# Pelvis travel (step-in) from frame 0 to the first strike, horizontal, metres.
	if not strikes.is_empty():
		var p0 := rows[0]["pelvis"] as Vector3
		var ph := rows[strikes[0]["peak"]]["pelvis"] as Vector3
		clip["step_in_m"] = snappedf(Vector2(ph.x - p0.x, ph.z - p0.z).length(), 0.01)
		clip["step_in_fwd_m"] = snappedf(ph.z - p0.z, 0.01)
	clip["target_contact"] = _target_contact(rows) if has_blade else []
	clip["foot_slide_cm"] = _foot_slide(rows)
	clip["body_clip_frames"] = _clip_frames(rows) if has_blade else []
	clip["min_bone_h_cm"] = _min_height(rows)
	# Recoil direction for reactions: chest displacement at its max vs facing (+Z fwd, +X = char left).
	var c0 := rows[0]["spine_03"] as Vector3
	var best := Vector3.ZERO
	for r in rows:
		var d := (r["spine_03"] as Vector3) - c0
		d.y = 0.0
		if d.length() > best.length():
			best = d
	clip["chest_max_disp"] = [snappedf(best.x, 0.01), snappedf(best.z, 0.01)]
	var pe := (rows[-1]["pelvis"] as Vector3) - (rows[0]["pelvis"] as Vector3)
	clip["pelvis_end_disp"] = [snappedf(pe.x, 0.01), snappedf(pe.y, 0.01), snappedf(pe.z, 0.01)]
	# Settle: last frame with any tracked point moving faster than 0.25 m/s.
	var settle := 0
	for i in range(1, n):
		for k in ["hand_r", "hand_l", "spine_03", "pelvis"]:
			if _speed(rows, k, i) > 0.25:
				settle = i
	clip["settle_frame"] = settle
	# Markers for gameplay (frames at this rate; seconds = frame / 30).
	if not strikes.is_empty():
		var s0: Dictionary = strikes[0]
		var sl: Dictionary = strikes[-1]
		clip["markers"] = {"windup_end": s0["windup_end"], "hit_start": s0["hit_start"], "hit_end": sl["hit_end"],
			"hits": strikes.map(func(x: Dictionary) -> int: return x["peak"]),
			"trail_start": maxi(int(s0["hit_start"]) - 2, 0), "trail_end": mini(int(sl["hit_end"]) + 2, n - 1),
			"combo_window": [int(sl["hit_end"]) + 1, maxi(settle, int(sl["follow_end"]))],
			"cancel_window": [int(sl["follow_end"]), n - 1]}
	cur = {"name": name, "rows": rows, "speed": s, "strikes": strikes, "vmax": vmax, "n": n, "rate": rate, "layer": layer}
	return clip


func _scale() -> float:
	return sk.global_transform.basis.get_scale().x


func _argmax(a: Array[float], lo: int, hi: int) -> int:
	var best := lo
	for i in range(lo, hi + 1):
		if a[i] > a[best]:
			best = i
	return best


func _foot_slide(rows: Array) -> Dictionary:
	var out := {}
	for side in ["l", "r"]:
		var k: String = "ball_" + side
		var floor_h := INF
		for r in rows:
			floor_h = minf(floor_h, (r[k] as Vector3).y)
		var slide := 0.0
		for i in range(1, rows.size()):
			var a := rows[i - 1][k] as Vector3
			var b := rows[i][k] as Vector3
			if a.y < floor_h + 0.03 and b.y < floor_h + 0.03:
				slide += Vector2(b.x - a.x, b.z - a.z).length()
		out[side] = snappedf(slide * 100.0, 0.1)
	return out


## Frames where the blade (base..tip) passes through a target standing at the player's lunge standoff:
## a vertical capsule 1.3 m in front (+Z), 0.3..1.7 m high, radius 0.35 m (an enemy torso + head).
## This is the gameplay contact window (damage / hit-stop / sparks), not the speed peak.
func _target_contact(rows: Array) -> Array:
	var out: Array = []
	var s := _scale() / 1.0
	var a := Vector3(0, 0.3, 1.3)
	var b := Vector3(0, 1.7, 1.3)
	for r in rows:
		var best := INF
		for k in 9:
			var p := (r["base"] as Vector3).lerp(r["tip"] as Vector3, k / 8.0)
			best = minf(best, Geometry3D.get_closest_point_to_segment(p, a, b).distance_to(p))
		if best <= 0.35:
			out.append(r["f"])
	return out


func _min_height(rows: Array) -> float:
	var m := INF
	for r in rows:
		for k in ["pelvis", "spine_03", "Head", "hand_r", "hand_l", "foot_l", "foot_r"]:
			m = minf(m, (r[k] as Vector3).y)
	return snappedf(m * 100.0, 0.1)


## Frames where the blade (from its base to the tip) passes inside the torso, head or legs.
func _clip_frames(rows: Array) -> Array:
	var hits: Array = []
	var caps := [["pelvis", "spine_03", 0.15], ["spine_03", "neck_01", 0.13], ["Head", "Head", 0.12],
		["thigh_l", "calf_l", 0.08], ["thigh_r", "calf_r", 0.08], ["upperarm_l", "lowerarm_l", 0.06]]
	for r in rows:
		var worst := 0.0
		var part := ""
		for c in caps:
			var a := r[c[0]] as Vector3
			var b := r[c[1]] as Vector3
			for k in 9:
				var p := (r["base"] as Vector3).lerp(r["tip"] as Vector3, k / 8.0)
				var d := Geometry3D.get_closest_point_to_segment(p, a, b).distance_to(p)
				var pen: float = float(c[2]) - d
				if pen > worst:
					worst = pen
					part = c[0]
		if worst > 0.03:
			hits.append([r["f"], part, snappedf(worst * 100.0, 0.1)])
	return hits


# --- rendering ---------------------------------------------------------------------------

func _build_views() -> void:
	get_window().size = Vector2i(W, VIEW_H + GRAPH_H)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.2, 0.22, 0.26)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.75, 0.8)
	e.ambient_light_energy = 0.6
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.light_energy = 1.2
	add_child(sun)
	# Ground: grid lines every 0.25 m (foot slide reads against them).
	var grid := MeshInstance3D.new()
	var gm := ImmediateMesh.new()
	var gmat := StandardMaterial3D.new()
	gmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gmat.vertex_color_use_as_albedo = true
	gm.surface_begin(Mesh.PRIMITIVE_LINES, gmat)
	for i in range(-12, 13):
		var c := Color(0.5, 0.5, 0.55) if i % 4 == 0 else Color(0.33, 0.34, 0.38)
		gm.surface_set_color(c)
		gm.surface_add_vertex(Vector3(i * 0.25, 0.001, -3))
		gm.surface_add_vertex(Vector3(i * 0.25, 0.001, 3))
		gm.surface_add_vertex(Vector3(-3, 0.001, i * 0.25))
		gm.surface_add_vertex(Vector3(3, 0.001, i * 0.25))
	gm.surface_end()
	grid.mesh = gm
	add_child(grid)
	# Each view is an off-screen SubViewport sharing this world; frames are composed in code
	# (independent of the project's window stretch settings).
	# FRONT (camera in front of the character, which faces +Z), SIDE (from its right, -X), TOP.
	var setups := [[Vector3(0, 1.05, 6.0), Vector3(0, 1.05, 0), "FRONT", false],
		[Vector3(-6.0, 1.05, 0.3), Vector3(0, 1.05, 0.3), "SIDE (right)", false],
		[Vector3(0, 7.0, 0.35), Vector3(0, 0, 0.35), "TOP (fwd = down)", true]]
	if args.has("pair"):
		setups = [[Vector3(4.5, 1.1, 4.8), Vector3(0, 0.9, 0.6), "3/4 FRONT", false],
			[Vector3(-7.5, 1.0, 0.6), Vector3(0, 0.9, 0.6), "SIDE (right)", false],
			[Vector3(0, 8.5, 0.6), Vector3(0, 0, 0.6), "TOP (fwd = down)", true]]
	for s in setups:
		var vp := SubViewport.new()
		vp.size = Vector2i(W / 3, VIEW_H)
		vp.msaa_3d = Viewport.MSAA_4X
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(vp)
		var cam := Camera3D.new()
		cam.fov = 26.0
		vp.add_child(cam)
		cam.look_at_from_position(s[0], s[1], Vector3.FORWARD if s[3] else Vector3.UP)
		cam.current = true
		if s[3]:
			cam.cull_mask = 0xFFFFF
		else:
			cam.cull_mask = 0xFFFFF & ~2
		var lab := Label.new()
		lab.text = s[2]
		lab.add_theme_color_override("font_color", Color(1, 1, 0.8))
		lab.add_theme_font_size_override("font_size", 16)
		lab.position = Vector2(8, 6)
		vp.add_child(lab)
		views.append(vp)
		cams.append(cam)
	# Overlays: blade tip trail (all views) and hip / shoulder lines (top view only, layer 2).
	var om := MeshInstance3D.new()
	overlay = ImmediateMesh.new()
	om.mesh = overlay
	om.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(om)
	var ot := MeshInstance3D.new()
	overlay_top = ImmediateMesh.new()
	ot.mesh = overlay_top
	ot.layers = 2
	add_child(ot)
	var gvp := SubViewport.new()
	gvp.size = Vector2i(W, GRAPH_H)
	gvp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(gvp)
	graph = _Graph.new()
	graph.studio = self
	graph.size = Vector2(W, GRAPH_H)
	gvp.add_child(graph)
	views.append(gvp)


class _Graph extends Control:
	var studio: Node
	var frame := 0

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.08, 0.08, 0.1))
		var c: Dictionary = studio.cur
		if c.is_empty():
			return
		var n: int = c["n"]
		var s: Array = c["speed"]
		var vmax: float = maxf(float(c["vmax"]), 0.5)
		var x0 := 60.0
		var w := size.x - x0 - 10.0
		var h := size.y - 34.0
		var fx := func(i: float) -> float: return x0 + w * i / maxf(n - 1, 1)
		for st: Dictionary in c["strikes"]:
			draw_rect(Rect2(Vector2(fx.call(float(st["windup_end"])), 4), Vector2(fx.call(float(st["hit_start"])) - fx.call(float(st["windup_end"])), h)), Color(0.2, 0.35, 0.8, 0.35))
			draw_rect(Rect2(Vector2(fx.call(float(st["hit_start"]) - 0.5), 4), Vector2(fx.call(float(st["hit_end"]) + 0.5) - fx.call(float(st["hit_start"]) - 0.5), h)), Color(0.9, 0.25, 0.2, 0.45))
			draw_rect(Rect2(Vector2(fx.call(float(st["hit_end"]) + 0.5), 4), Vector2(fx.call(float(st["follow_end"])) - fx.call(float(st["hit_end"]) + 0.5), h)), Color(0.9, 0.7, 0.2, 0.3))
		var pts := PackedVector2Array()
		for i in n:
			pts.append(Vector2(fx.call(float(i)), 4 + h - h * float(s[i]) / vmax))
		draw_polyline(pts, Color(1, 1, 1), 2.0)
		draw_line(Vector2(fx.call(float(frame)), 0), Vector2(fx.call(float(frame)), h + 6), Color(0.3, 1, 0.4), 2.0)
		var font := get_theme_default_font()
		var phase := "recover"
		for st: Dictionary in c["strikes"]:
			if frame <= int(st["windup_end"]):
				phase = "windup"
				break
			if frame < int(st["hit_start"]):
				phase = "accel"
				break
			if frame <= int(st["hit_end"]):
				phase = "HIT (fast)"
				break
			if frame <= int(st["follow_end"]):
				phase = "follow-through"
				break
		draw_string(font, Vector2(4, 18), "%.0f m/s" % vmax, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.8, 0.8, 0.8))
		draw_string(font, Vector2(4, size.y - 8),
			"%s  @%.2fx  %s   f%d/%d  %.2fs   tip %.1f m/s   %s" % [c["name"], float(c["rate"]), String(c["layer"]), frame, n - 1,
			frame / 30.0, float(s[frame]), phase], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 0.8))


func _draw_overlay(i: int) -> void:
	overlay.clear_surfaces()
	overlay_top.clear_surfaces()
	var rows: Array = cur["rows"]
	var key := "tip" if rows[0].has("tip") else "hand_r"
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = true
	# Faint full path of the tip, then the last 8 frames bright (yellow = fast frames).
	overlay.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, mat)
	for j in rows.size():
		overlay.surface_set_color(Color(0.55, 0.6, 0.75, 0.6))
		overlay.surface_add_vertex(rows[j][key])
	overlay.surface_end()
	if i > 0:
		overlay.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, mat)
		for j in range(maxi(i - 8, 0), i + 1):
			var fast := false
			for st: Dictionary in cur["strikes"]:
				fast = fast or (j >= int(st["hit_start"]) and j <= int(st["hit_end"]))
			overlay.surface_set_color(Color(1, 0.85, 0.2) if fast else Color(0.4, 0.9, 1.0))
			overlay.surface_add_vertex(rows[j][key])
		overlay.surface_end()
	# Top view: hips (red) and shoulders (cyan) lines, lifted above the head so they read.
	overlay_top.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	var r: Dictionary = rows[i]
	var up := Vector3(0, 2.2, 0)
	var hl := (r["thigh_l"] as Vector3) - (r["thigh_r"] as Vector3)
	var hc := ((r["thigh_l"] as Vector3) + (r["thigh_r"] as Vector3)) * 0.5
	hc.y = 0
	overlay_top.surface_set_color(Color(1, 0.3, 0.25))
	overlay_top.surface_add_vertex(hc - hl.normalized() * 0.35 + up)
	overlay_top.surface_add_vertex(hc + hl.normalized() * 0.35 + up)
	var sl := (r["upperarm_l"] as Vector3) - (r["upperarm_r"] as Vector3)
	var sc := ((r["upperarm_l"] as Vector3) + (r["upperarm_r"] as Vector3)) * 0.5
	sc.y = 0
	overlay_top.surface_set_color(Color(0.3, 0.95, 1.0))
	overlay_top.surface_add_vertex(sc - sl.normalized() * 0.45 + up + Vector3(0, 0.01, 0))
	overlay_top.surface_add_vertex(sc + sl.normalized() * 0.45 + up + Vector3(0, 0.01, 0))
	overlay_top.surface_end()


# --- run ---------------------------------------------------------------------------------

func _run() -> void:
	var default_rate := float(args.get("rate", "1.0"))
	var layer := String(args.get("layer", "full"))
	var results: Array = []
	var render := args.has("render")
	for spec: String in String(args.get("clips", "")).split(",", false):
		var nm := spec
		var rate := default_rate
		if "@" in spec:
			nm = spec.get_slice("@", 0)
			rate = float(spec.get_slice("@", 1))
		if not anims.has(nm):
			print("STUDIO missing %s" % nm)
			continue
		var res := _analyse(nm, rate, layer)
		results.append(res)
		print("STUDIO ", JSON.stringify(res))
		if render:
			var dir := out_dir.path_join(nm + ("_upper" if layer == "upper" else "") + ("" if is_equal_approx(rate, 1.0) else "_x%.2f" % rate))
			DirAccess.make_dir_recursive_absolute(dir)
			var anim: Animation = anims[nm]
			var idle: Animation = anims.get("Idle", null)
			for i in int(cur["n"]):
				var t := minf(i / FPS * rate, anim.length)
				if layer == "upper" and idle:
					_apply(anim, t, idle, fmod(i / FPS, idle.length))
				else:
					_apply(anim, t)
				if pair_sk and anims.has(String(args["pair"])):
					var own := sk
					sk = pair_sk
					_apply(anims[String(args["pair"])], minf(i / FPS * rate, (anims[String(args["pair"])] as Animation).length))
					sk = own
				_draw_overlay(i)
				(graph as _Graph).frame = i
				graph.queue_redraw()
				await RenderingServer.frame_post_draw
				await RenderingServer.frame_post_draw
				var img := Image.create(W, VIEW_H + GRAPH_H, false, Image.FORMAT_RGB8)
				for v in 3:
					var vi := views[v].get_texture().get_image()
					vi.convert(Image.FORMAT_RGB8)
					img.blit_rect(vi, Rect2i(Vector2i.ZERO, vi.get_size()), Vector2i(v * (W / 3), 0))
				var gi := views[3].get_texture().get_image()
				gi.convert(Image.FORMAT_RGB8)
				img.blit_rect(gi, Rect2i(Vector2i.ZERO, gi.get_size()), Vector2i(0, VIEW_H))
				img.save_png(dir.path_join("f_%08d.png" % i))
	var f := FileAccess.open(out_dir.path_join("metrics.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(results, "  "))
	f.close()
	print("STUDIO done %d clips -> %s" % [results.size(), out_dir])
	get_tree().quit()
