extends SceneTree
## Bakes data/anim/clip_retime.json (scripts/actors/clip_retime.gd): per locomotion clip, the stance-phase time map that makes
## every planted foot travel backwards (relative to the body) at one constant speed.
##   godot --headless --path kingdom -s res://tools_qa/anim_states/clip_retime_bake.gd -- [--clips=Walk,Jog_Fwd] [--dry]
## Method: the clip is played raw on the adult player (tree, IK and springs off, the current retime NOT applied: the source clip
## is read from the clip libraries' own data); the ball bones are sampled at 240 Hz in model space. A foot is planted while its
## ball is within 2.5 cm of its lowest height. The planted feet's travel direction (principal xz direction) and the clip's
## stance speed S (median planted speed) are measured; the time rate is r(t) = v(t) / S on planted samples (clamped 0.55..1.8,
## lightly smoothed) and 1 in flight / swing. Output frames at 30 fps are mapped back to source times; the map is rescaled so
## the last output frame lands exactly on the source end (loops stay closed). Prints the slip before / after (m/s, mean and p90).
const BASE := 600.0
const DEFAULT_CLIPS := ["Walk", "Jog_Fwd", "Sprint", "Strafe_left", "Strafe_right", "Crouch_Fwd", "Walk_Backwards", "Walk_Stealth"]
const HZ := 240.0
const OUT_FPS := 30.0
const PLANT_H := 0.025
const R_MIN := 0.3          # a planted foot that (nearly) stops in the clip: its time is skipped through fast
const R_MAX := 2.5

var _p: Node3D
var _sk: Skeleton3D
var _ap: AnimationPlayer
var _model: Node3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var clips: Array = DEFAULT_CLIPS.duplicate()
	var dry := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--clips="):
			clips = Array(a.substr(8).split(",", false))
		elif a == "--dry":
			dry = true
	var r3 := Node3D.new()
	root.add_child(r3)
	_p = (load("res://scripts/actors/player.gd") as GDScript).new()
	r3.add_child(_p)
	_p.global_position = Vector3(0, BASE, 0)
	for i in 20:
		await physics_frame
	var life: Node = root.get_node("Life")
	life.life_path.set_age(16, root.get_node("WorldSim").day, root.get_node("WorldSim").time_of_day)
	_p.call("apply_age")
	for i in 10:
		await physics_frame
	_p.set_physics_process(false)
	var rig: Variant = _p.get("_rig")
	if rig is Object:
		(rig as Object).call("set_paused", true)
	_sk = _p.find_children("*", "Skeleton3D", true, false)[0]
	_model = _p.get("_model")
	var an: Object = _p.get("_animator")
	_ap = an.get("player")
	var tree: Variant = an.get("tree")
	if tree is AnimationTree:
		(tree as AnimationTree).active = false
	var existing := {}
	if FileAccess.file_exists("res://data/anim/clip_retime.json"):
		var ex: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/anim/clip_retime.json"))
		if ex is Dictionary:
			existing = (ex as Dictionary).get("clips", {})
	var out := {}
	for clip: String in clips:
		if not _ap.has_animation(StringName(clip)):
			print("RETIME skip (missing) ", clip)
			continue
		var anim := _ap.get_animation(StringName(clip))
		if anim.has_meta(&"clip_retime"):
			# measure the SOURCE: undo by reading the retime map's inverse is not possible here; the library must be built
			# without the current map (run with the entry removed from clip_retime.json)
			print("RETIME note: ", clip, " is already retimed in this library: remove it from clip_retime.json and rerun")
			continue
		var res := _bake(clip, anim)
		if res.is_empty():
			continue
		out[clip] = res
	if dry:
		quit()
		return
	for k: String in existing:
		if not out.has(k):
			out[k] = existing[k]
	var f := FileAccess.open("res://data/anim/clip_retime.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"_doc": "Stance retime maps (scripts/actors/clip_retime.gd), baked by tools_qa/anim_states/clip_retime_bake.gd. Do not edit by hand.", "clips": out}))
	f.close()
	print("RETIME_DONE ", out.size())
	quit()


func _ball(i: int) -> Vector3:
	var b := _sk.find_bone("ball_l" if i == 0 else "ball_r")
	return _model.global_transform.affine_inverse() * (_sk.global_transform * _sk.get_bone_global_pose(b)).origin


func _bake(clip: String, anim: Animation) -> Dictionary:
	var n := int(anim.length * HZ)
	if n < 8:
		return {}
	var pos: Array = [[], []]
	for s in n + 1:
		var t := minf(float(s) / HZ, anim.length)
		_ap.play(StringName(clip))
		_ap.seek(t, true)
		_ap.pause()
		_sk.force_update_all_bone_transforms()
		for i in 2:
			(pos[i] as Array).append(_ball(i))
	# planted masks
	var planted: Array = [[], []]
	for i in 2:
		var lo := INF
		for p: Vector3 in pos[i]:
			lo = minf(lo, p.y)
		for s in n + 1:
			(planted[i] as Array).append((pos[i][s] as Vector3).y < lo + PLANT_H)
	# travel direction of planted feet (xz), from their mean velocity
	var mean_v := Vector2.ZERO
	var cnt := 0
	for i in 2:
		for s in range(1, n + 1):
			if planted[i][s] and planted[i][s - 1]:
				var d: Vector3 = (pos[i][s] as Vector3) - (pos[i][s - 1] as Vector3)
				mean_v += Vector2(d.x, d.z) * HZ
				cnt += 1
	if cnt < 10 or mean_v.length() < 0.001:
		print("RETIME %s: no usable stance (cnt %d)" % [clip, cnt])
		return {}
	var dir := (mean_v / cnt).normalized()       # the planted feet move this way relative to the body
	# per-sample planted speed along dir (mean over planted feet), and the stance speed S
	var v := PackedFloat32Array()
	v.resize(n + 1)
	var speeds: Array[float] = []
	for s in n + 1:
		var acc := 0.0
		var k := 0
		for i in 2:
			if planted[i][s] and s > 0 and planted[i][s - 1]:
				var d: Vector3 = (pos[i][s] as Vector3) - (pos[i][s - 1] as Vector3)
				acc += Vector2(d.x, d.z).dot(dir) * HZ
				k += 1
		v[s] = acc / k if k > 0 else -INF       # -INF: no planted foot (swing / flight)
		if k > 0 and v[s] > 0.05:
			speeds.append(v[s])
	if speeds.size() < 10:
		return {}
	speeds.sort()
	var S := speeds[speeds.size() / 2]
	# slip before: |v - S| over planted samples (a body moving at S)
	var before := _slip_stats(v, PackedFloat32Array(), S)
	# rate r(t)
	var r := PackedFloat32Array()
	r.resize(n + 1)
	for s in n + 1:
		r[s] = clampf(v[s] / S, R_MIN, R_MAX) if v[s] > -INF else 1.0
	var rs := PackedFloat32Array()
	rs.resize(n + 1)
	for s in n + 1:
		var acc2 := 0.0
		var w := 0.0
		for k2 in range(-2, 3):
			var ww := 3.0 - absf(float(k2))
			acc2 += r[clampi(s + k2, 0, n)] * ww
			w += ww
		rs[s] = acc2 / w
	# cumulative output time per source sample
	var tout := PackedFloat32Array()
	tout.resize(n + 1)
	tout[0] = 0.0
	for s in range(1, n + 1):
		tout[s] = tout[s - 1] + rs[s] / HZ
	var frames := maxi(2, int(round(tout[n] * OUT_FPS)))
	var scale := tout[n] / (float(frames) / OUT_FPS)
	var map: Array = []
	var s_i := 0
	for k3 in frames + 1:
		var want := float(k3) / OUT_FPS * scale
		while s_i < n and tout[s_i + 1] < want:
			s_i += 1
		var a0 := tout[s_i]
		var a1 := tout[mini(s_i + 1, n)]
		var fr := 0.0 if a1 <= a0 else clampf((want - a0) / (a1 - a0), 0.0, 1.0)
		map.append(snappedf((float(s_i) + fr) / HZ, 0.0001))
	map[map.size() - 1] = snappedf(anim.length, 0.0001)
	var after := _slip_stats(v, rs, S)
	print("RETIME %s len %.3f -> %.3f s, stance speed %.2f m/s, slip mean %.3f -> %.3f, p90 %.3f -> %.3f m/s" % [clip, anim.length,
			float(frames) / OUT_FPS, S, before[0], after[0], before[1], after[1]])
	return {"fps": OUT_FPS, "stance_speed": snappedf(S, 0.001), "slip_before": snappedf(before[0], 0.001), "slip_after": snappedf(after[0], 0.001), "map": map}


## Slip of planted feet for a body moving at S: |v / rate - S| (rate empty = 1). Returns [mean, p90].
func _slip_stats(v: PackedFloat32Array, rate: PackedFloat32Array, S: float) -> Array:
	var vals: Array[float] = []
	for s in v.size():
		if v[s] == -INF:
			continue
		var rr := 1.0 if rate.is_empty() else rate[s]
		vals.append(absf(v[s] / rr - S))
	if vals.is_empty():
		return [0.0, 0.0]
	vals.sort()
	var m := 0.0
	for x in vals:
		m += x
	return [m / vals.size(), vals[int(vals.size() * 0.9)]]
