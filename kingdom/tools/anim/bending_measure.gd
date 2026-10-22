extends SceneTree
## Floor-penetration and travel check of the bending clips, no rendering and no frame stepping (poses are sampled
## straight from the tracks onto the player's skeleton):
##   godot --headless --path kingdom -s tools/anim/bending_measure.gd [-- --prepared] [--json=out.json]
## For every clip: sink = lowest bone height below the standing rest minimum (negative = under the floor, metres),
## root_travel = horizontal travel of the pelvis over the clip. `--prepared` measures the clip as the game plays it
## (BendingLibrary.prepare: root track removed, lift, trim, blend_out) so the fixes can be verified.

const BendingLibrary := preload("res://scripts/actors/bending_library.gd")
const FPS := 30.0


var _done := false


func _initialize() -> void:
	var model := Assets.character("Player", 1.8, [])
	root.add_child(model)


func _process(_d: float) -> bool:
	if _done:
		return true
	_done = true
	_run()
	return true


func _run() -> void:
	var prepared := false
	var json_path := ""
	for a in OS.get_cmdline_user_args():
		if a == "--prepared":
			prepared = true
		elif a.begins_with("--json="):
			json_path = a.substr(7)
	var model: Node3D = root.get_child(root.get_child_count() - 1)
	var sk: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
	var ap_game := Assets.animation_player(model)
	var sk_path := ""
	for n in ap_game.get_animation_list():
		var a := ap_game.get_animation(n)
		if a.get_track_count() > 0:
			var tp := String(a.track_get_path(0))
			sk_path = tp.substr(0, tp.find(":"))
			break
	var rest_min := _lowest(sk)
	var sk_scale := sk.global_transform.basis.get_scale().y
	var inst: Node = (load(BendingLibrary.GLB) as PackedScene).instantiate()
	var src: AnimationPlayer = inst.find_children("*", "AnimationPlayer", true, false)[0]
	var out := {}
	var names: Array = Array(src.get_animation_list())
	names.sort()
	for n: String in names:
		if n == "RESET":
			continue
		var a: Animation = src.get_animation(n)
		if prepared:
			a = BendingLibrary.prepare(a, sk_path, BendingLibrary.info(n))
		var sink := 9.0
		var series: Array[float] = []
		var p0 := Vector3.ZERO
		var travel := 0.0
		var frames := int(round(a.length * FPS)) + 1
		for f in frames:
			var t := minf(float(f) / FPS, a.length)
			_pose(sk, a, t)
			var dip := _lowest(sk) - rest_min
			sink = minf(sink, dip)
			series.append(dip)
			var pel: Vector3 = sk.get_bone_global_pose(sk.find_bone("pelvis")).origin
			if f == 0:
				p0 = pel
			travel = maxf(travel, Vector2(pel.x - p0.x, pel.z - p0.z).length())
		out[n] = {"len": snappedf(a.length, 0.01), "sink": snappedf(sink, 0.001), "pelvis_drift": snappedf(travel, 0.01),
			"lift": _lift_curve(series, 1.0 / maxf(sk_scale, 0.0001))}
		print("%-26s len %.2f  sink %+.3f  pelvis drift %.2f" % [n, a.length, sink, travel])
	if json_path != "":
		var f := FileAccess.open(json_path, FileAccess.WRITE)
		f.store_string(JSON.stringify(out, "  "))
		f.close()
	inst.free()
	quit()


func _lowest(sk: Skeleton3D) -> float:
	var lo := 9.0
	for b in sk.get_bone_count():
		if sk.get_bone_name(b) == "root":
			continue
		lo = minf(lo, (sk.global_transform * sk.get_bone_global_pose(b)).origin.y)
	return lo


func _pose(sk: Skeleton3D, a: Animation, t: float) -> void:
	for i in a.get_track_count():
		if not a.track_is_enabled(i):
			continue
		var tp := String(a.track_get_path(i))
		var colon := tp.find(":")
		if colon < 0:
			continue
		var b := sk.find_bone(tp.substr(colon + 1))
		if b < 0:
			continue
		match a.track_get_type(i):
			Animation.TYPE_POSITION_3D:
				sk.set_bone_pose_position(b, a.position_track_interpolate(i, t))
			Animation.TYPE_ROTATION_3D:
				sk.set_bone_pose_rotation(b, a.rotation_track_interpolate(i, t))


## Pelvis lift (skeleton units) per 1/10 s that keeps the lowest bone at the floor: the dip below the standing minimum
## (more than 1 cm), widened by 0.1 s on each side and smoothed so the body does not jerk. [] when the clip never sinks.
func _lift_curve(series: Array[float], unit: float) -> Array:
	var need: Array[float] = []
	var any := false
	for d: float in series:
		var v := maxf(-d - 0.01, 0.0)
		need.append(v)
		any = any or v > 0.0
	if not any:
		return []
	var n := need.size()
	var wide: Array[float] = []
	for i in n:
		var m := 0.0
		for j in range(maxi(i - 3, 0), mini(i + 4, n)):
			m = maxf(m, need[j])
		wide.append(m)
	var out: Array = []
	var step := 3
	var i := 0
	while i < n + step:
		var k := mini(i, n - 1)
		var acc := 0.0
		var cnt := 0
		for j in range(maxi(k - 3, 0), mini(k + 4, n)):
			acc += wide[j]
			cnt += 1
		out.append([snappedf(float(k) / FPS, 0.001), snappedf(acc / maxf(cnt, 1) * unit + 0.0, 0.0005)])
		if k == n - 1:
			break
		i += step
	return out
