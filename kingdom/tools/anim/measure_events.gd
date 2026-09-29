extends SceneTree
## Event measurement for clip libraries (UAL skeleton GLBs): finds the strike / release frames from the
## actual bone motion instead of guessing. For every clip it samples the pose at 30 fps and tracks the
## hands and feet relative to the pelvis:
##   peak    = frame of the fastest end-effector (m/s, relative to the pelvis)
##   hits[]  = every speed peak above 45% of the clip's fastest and above MIN_SPEED (multi-hit combos),
##             each with the limb, the peak speed and `hit` = frame of maximum reach within 6 frames after
##             the peak (the moment the fist / foot / hand is fully extended: use it as the hit / release /
##             VFX spawn frame)
##   travel  = root position track (metres, x/y/z) first to last key
##   foot_min= lowest foot / toe height above the standing rest height (negative = sinks into the floor)
##   hand_min= lowest hand height (metres above the floor)
##
##   godot --path kingdom -s tools/anim/measure_events.gd -- --glb=<res:// or absolute glb> --json=<out.json> [--clips=A,B] [--limbs=feet|all]
##   (default detects strikes on the hands; --limbs=feet for kicks, all for mixed clips)
## Windowed or --headless both work (no rendering needed).

const FPS := 30.0
const MIN_SPEED := 2.0
var _glbs: Array[String] = []
var _json := "user://events.json"
var _only: Array[String] = []
var _clips: Array = []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--glb="): _glbs.append(a.substr(6))
		elif a.begins_with("--json="): _json = a.substr(7)
		elif a.begins_with("--clips="): _only.append_array(a.substr(8).split(","))
		elif a == "--paths": _paths = true
		elif a == "--limbs=feet": _det = ["foot_l", "foot_r"]
		elif a == "--limbs=all": _det = ["hand_l", "hand_r", "foot_l", "foot_r"]
	var model := Assets.character("Player", 1.8, [])
	root.add_child(model)
	var ap := Assets.animation_player(model)
	var sk_path := ""
	for n in ap.get_animation_list():
		var a := ap.get_animation(n)
		if a.get_track_count() > 0:
			var tp := String(a.track_get_path(0))
			sk_path = tp.substr(0, tp.find(":"))
			break
	for f in _glbs:
		var inst: Node
		if f.begins_with("res://"):
			inst = Assets.scene(f).instantiate()
		else:
			var doc := GLTFDocument.new()
			var st := GLTFState.new()
			doc.append_from_file(f, st)
			inst = doc.generate_scene(st)
		var src: AnimationPlayer = inst.find_children("*", "AnimationPlayer", true, false)[0]
		for n in src.get_animation_list():
			if not _only.is_empty() and not (n in _only):
				continue
			var a: Animation = src.get_animation(n).duplicate(true)
			var travel := Vector3.ZERO
			for t in a.get_track_count():
				var tp := String(a.track_get_path(t))
				var colon := tp.find(":")
				if colon > 0:
					if tp.substr(colon) == ":root" and a.track_get_type(t) == Animation.TYPE_POSITION_3D:
						var n_keys := a.track_get_key_count(t)
						if n_keys > 1:
							travel = (a.track_get_key_value(t, n_keys - 1) as Vector3) - (a.track_get_key_value(t, 0) as Vector3)
						a.track_set_enabled(t, false)
					a.track_set_path(t, NodePath(sk_path + tp.substr(colon)))
			_clips.append([n, a, travel])
		inst.free()
	_clips.sort_custom(func(x, y): return String(x[0]) < String(y[0]))
	_setup(model, ap)


var _sk: Skeleton3D
var _ap: AnimationPlayer
var _limbs := ["hand_l", "hand_r", "foot_l", "foot_r"]   # --limbs=hands|feet|all restricts the strike detection
var _paths := false                # --paths also dumps every limb path (metres, relative to the pelvis, model space: +Z = character forward)
var _det := ["hand_l", "hand_r"]
var _ids := {}
var _toes := {}
var _pel := 0
var _rest_toe_y := {}
var _out := {}
var _ci := 0
var _fi := 0
var _wait := 0
var _pos := {}
var _pabs: Array = []              # pelvis position in model space per frame (with --paths)
var _minb: Array = []              # lowest bone height per frame (metres above the floor, all bones but root)
var _head: Array = []              # head position per frame (model space)
var _pelv: Array = []              # pelvis height per frame
var _cpos := {}                    # limb -> path in the chest yaw frame (x = character left, y up, z = forward), origin = shoulder midpoint
var _ul := 0
var _hd := 0
var _ur := 0
var _foot_min := 9.0
var _hand_min := 9.0


func _setup(model: Node3D, ap: AnimationPlayer) -> void:
	_ap = ap
	_sk = model.find_children("*", "Skeleton3D", true, false)[0]
	var lib := AnimationLibrary.new()
	for c in _clips:
		lib.add_animation(c[0], c[1])
	ap.add_animation_library("ev", lib)
	for l: String in _limbs:
		_ids[l] = _sk.find_bone(l)
	_toes = {"ball_l": _sk.find_bone("ball_l"), "ball_r": _sk.find_bone("ball_r")}
	_pel = _sk.find_bone("pelvis")
	_ul = _sk.find_bone("upperarm_l")
	_hd = _sk.find_bone("Head")
	_ur = _sk.find_bone("upperarm_r")
	for k: String in _toes:
		_rest_toe_y[k] = (_sk.global_transform * _sk.get_bone_global_rest(_toes[k])).origin.y


func _process(_d: float) -> bool:
	if _ap == null:
		return false
	if _ci >= _clips.size():
		var f := FileAccess.open(_json, FileAccess.WRITE)
		f.store_string(JSON.stringify(_out, "  "))
		f.close()
		print("EVENTS ", _clips.size(), " clips -> ", _json)
		return true
	var c: Array = _clips[_ci]
	var anim: Animation = c[1]
	var n := int(round(anim.length * FPS)) + 1
	if _fi == 0 and _wait == 0:
		_ap.play("ev/" + String(c[0]))
		_pos = {}
		_cpos = {}
		_pabs = []
		_head = []
		_pelv = []
		_minb = []
		for l: String in _limbs:
			_pos[l] = []
			_cpos[l] = []
		_foot_min = 9.0
		_hand_min = 9.0
	if _wait == 0:
		_ap.seek(minf(float(_fi) / FPS, anim.length), true)
		_ap.pause()
		_wait = 2
		return false
	_wait -= 1
	if _wait > 0:
		return false
	var gp: Vector3 = (_sk.global_transform * _sk.get_bone_global_pose(_pel)).origin
	var pu: Vector3 = (_sk.global_transform * _sk.get_bone_global_pose(_ul)).origin
	var pr: Vector3 = (_sk.global_transform * _sk.get_bone_global_pose(_ur)).origin
	var lat := Vector3(pu.x - pr.x, 0.0, pu.z - pr.z).normalized()
	var fwd := lat.cross(Vector3.UP)
	var smid := (pu + pr) * 0.5
	_pabs.append(gp)
	_pelv.append(gp.y)
	_head.append((_sk.global_transform * _sk.get_bone_global_pose(_hd)).origin)
	var lowest := 9.0
	for b in _sk.get_bone_count():
		if _sk.get_bone_name(b) != "root":
			lowest = minf(lowest, (_sk.global_transform * _sk.get_bone_global_pose(b)).origin.y)
	_minb.append(lowest)
	for l: String in _limbs:
		var p: Vector3 = (_sk.global_transform * _sk.get_bone_global_pose(_ids[l])).origin
		(_pos[l] as Array).append(p - gp)
		var rel := p - smid
		(_cpos[l] as Array).append(Vector3(rel.dot(lat), rel.y, rel.dot(fwd)))
		if l.begins_with("hand"):
			_hand_min = minf(_hand_min, p.y)
	for k: String in _toes:
		var ty: float = (_sk.global_transform * _sk.get_bone_global_pose(_toes[k])).origin.y - float(_rest_toe_y[k])
		_foot_min = minf(_foot_min, ty)
	_fi += 1
	if _fi < n:
		return false
	_finish_clip(c, n)
	_ci += 1
	_fi = 0
	return false


func _finish_clip(c: Array, n: int) -> void:
	var anim: Animation = c[1]
	var limbs := _det
	var pos := _pos
	var foot_min := _foot_min
	var hand_min := _hand_min
	if true:
		# speed series per limb (m/s, 3-frame centred difference), relative to the pelvis
		var speed := {}
		var best := 0.0
		for l: String in limbs:
			var arr: Array = pos[l]
			var s: Array = []
			for i in n:
				var a: Vector3 = arr[maxi(i - 1, 0)]
				var b: Vector3 = arr[mini(i + 1, n - 1)]
				var dt := float(mini(i + 1, n - 1) - maxi(i - 1, 0)) / FPS
				s.append(a.distance_to(b) / maxf(dt, 0.001))
			speed[l] = s
			for v: float in s:
				best = maxf(best, v)
		var hits: Array = []
		var peak_frame := 0
		var peak_limb := ""
		var peak_v := 0.0
		for l: String in limbs:
			var s: Array = speed[l]
			for i in range(1, n - 1):
				var v: float = s[i]
				if v > peak_v:
					peak_v = v
					peak_frame = i
					peak_limb = l
				if v >= MIN_SPEED and v >= 0.45 * best and v >= float(s[i - 1]) and v > float(s[i + 1]):
					var reach_f := i
					var reach_d := 0.0
					for j in range(i, mini(i + 7, n)):
						var d: float = (pos[l][j] as Vector3).length()
						if d > reach_d:
							reach_d = d
							reach_f = j
					hits.append({"limb": l, "peak": i, "hit": reach_f, "hit_s": snappedf(reach_f / FPS, 0.001),
						"speed": snappedf(v, 0.1), "reach_m": snappedf(reach_d, 0.01)})
		hits.sort_custom(func(x, y): return int(x["peak"]) < int(y["peak"]))
		# merge peaks of different limbs closer than 5 frames (keep the faster)
		var merged: Array = []
		for h in hits:
			if not merged.is_empty() and int(h["peak"]) - int(merged[-1]["peak"]) < 5:
				if float(h["speed"]) > float(merged[-1]["speed"]):
					merged[-1] = h
				continue
			merged.append(h)
		_out[String(c[0])] = {"len_s": snappedf(anim.length, 0.001), "frames": n - 1, "loop": anim.loop_mode != Animation.LOOP_NONE,
			"peak_frame": peak_frame, "peak_limb": peak_limb, "peak_speed": snappedf(peak_v, 0.1),
			"hits": merged, "travel_m": [snappedf((c[2] as Vector3).x, 0.01), snappedf((c[2] as Vector3).y, 0.01), snappedf((c[2] as Vector3).z, 0.01)],
			"foot_min": snappedf(foot_min, 0.001), "hand_min": snappedf(hand_min, 0.001)}
		# reaction metrics: frame of the largest head displacement from frame 0 (first 60% of the clip = recoil peak),
		# and the first frame from which the pelvis stays below 0.5 m (body on the ground)
		var recoil_f := 0
		var recoil_d := 0.0
		for i in range(1, maxi(int(n * 0.6), 2)):
			var dd: float = ((_head[i] as Vector3) - (_head[0] as Vector3)).length()
			if dd > recoil_d:
				recoil_d = dd
				recoil_f = i
		var down_f := -1
		for i in range(n - 1, -1, -1):
			if float(_pelv[i]) < 0.5:
				down_f = i
			else:
				break
		var up_f := 0
		var up_y := -9.0
		for i in n:
			var hy: float = ((_pos["hand_l"][i] as Vector3).y + (_pos["hand_r"][i] as Vector3).y) * 0.5
			if hy > up_y:
				up_y = hy
				up_f = i
		_out[String(c[0])]["handup_frame"] = up_f          # both hands highest (arms raised overhead: aura / buff clips)
		_out[String(c[0])]["handup_y"] = snappedf(up_y, 0.01)
		_out[String(c[0])]["recoil_frame"] = recoil_f
		_out[String(c[0])]["recoil_m"] = snappedf(recoil_d, 0.01)
		_out[String(c[0])]["down_frame"] = down_f if down_f < n - 1 else -1
		if _paths:
			var pp := {}
			for l: String in _limbs:
				pp[l] = (pos[l] as Array).map(func(v: Vector3): return [snappedf(v.x, 0.001), snappedf(v.y, 0.001), snappedf(v.z, 0.001)])
			_out[String(c[0])]["paths"] = pp
			var cp := {}
			for l: String in _limbs:
				cp[l] = (_cpos[l] as Array).map(func(v: Vector3): return [snappedf(v.x, 0.001), snappedf(v.y, 0.001), snappedf(v.z, 0.001)])
			_out[String(c[0])]["cpaths"] = cp
			_out[String(c[0])]["pelvis_abs"] = _pabs.map(func(v: Vector3): return [snappedf(v.x, 0.001), snappedf(v.y, 0.001), snappedf(v.z, 0.001)])
			_out[String(c[0])]["lowest_bone"] = _minb.map(func(v: float): return snappedf(v, 0.001))
