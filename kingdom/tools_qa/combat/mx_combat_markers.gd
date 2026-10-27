extends SceneTree
## Measures the owner's Mixamo combat clips (assets/incoming/animations/mixamo_combat/UAL_Mx_*.glb) and writes
## data/combat/mx_combat_markers.json, which CombatMoves' full-motion chains read (timing is data, not guesses):
##   len        clip seconds
##   hit        contact frame = peak speed of the weapon hand (hand_r, or hand_l when it is clearly faster), relative to root
##   active     [from, to] where that hand moves faster than 55 % of its peak around the hit
##   fwd_hit    forward root travel (m, UAL body) from 0 to the hit; fwd_end = to the clip end; side_end lateral
##   dir        swing direction at the hit from the hand velocity: overhead | thrust | left | right | rising
##   lift       max root-relative pelvis drop (big = goes to the floor: deaths, knockdowns)
##   godot --headless --path kingdom -s res://tools_qa/combat/mx_combat_markers.gd
const DIR := "res://assets/incoming/animations/mixamo_combat/"
const OUT := "res://data/combat/mx_combat_markers.json"
const FPS := 30.0


func _initialize() -> void:
	var out := {}
	for f in DirAccess.get_files_at(DIR):
		if not f.ends_with(".glb"):
			continue
		var ps := load(DIR + f) as PackedScene
		if ps == null:
			continue
		var inst := ps.instantiate()
		root.add_child(inst)
		var ap := inst.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		var sk := inst.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		for lib_name in ap.get_animation_library_list():
			var lib := ap.get_animation_library(lib_name)
			for an in lib.get_animation_list():
				var full := (String(lib_name) + "/" + an) if String(lib_name) != "" else String(an)
				out[String(an)] = _measure(ap, sk, full, ap.get_animation(full))
		inst.queue_free()
		print("measured ", f)
	var fa := FileAccess.open(OUT, FileAccess.WRITE)
	fa.store_string(JSON.stringify(out, " ", true))
	fa.close()
	print("wrote ", out.size(), " clips -> ", OUT)
	quit()


func _measure(ap: AnimationPlayer, sk: Skeleton3D, full: String, anim: Animation) -> Dictionary:
	var bi := {"root": sk.find_bone("root"), "hand_r": sk.find_bone("hand_r"), "hand_l": sk.find_bone("hand_l"),
		"pelvis": sk.find_bone("pelvis")}
	var n := int(ceil(anim.length * FPS)) + 1
	var hr := PackedVector3Array()
	var hl := PackedVector3Array()
	var rt := PackedVector3Array()
	var pel := PackedFloat32Array()
	# Manual FK from the clip's own tracks (seeking a mixer outside the frame loop does not refresh the skeleton).
	for i in n:
		var tt := minf(i / FPS, anim.length)
		var r := _global(sk, anim, bi["root"], tt).origin
		rt.append(r)
		hr.append(_global(sk, anim, bi["hand_r"], tt).origin - r)
		hl.append(_global(sk, anim, bi["hand_l"], tt).origin - r)
		pel.append(_global(sk, anim, bi["pelvis"], tt).origin.y)
	var spd_r := _speeds(hr)
	var spd_l := _speeds(hl)
	var use_l: bool = _mx(spd_l) > _mx(spd_r) * 1.25
	var spd := spd_l if use_l else spd_r
	var pos := hl if use_l else hr
	var peak_i := 0
	for i in spd.size():
		if spd[i] > spd[peak_i]:
			peak_i = i
	var thr := spd[peak_i] * 0.55 if spd.size() > 0 else 0.0
	var a := peak_i
	while a > 0 and spd[a - 1] > thr:
		a -= 1
	var b := peak_i
	while b < spd.size() - 1 and spd[b + 1] > thr:
		b += 1
	var v := Vector3.ZERO
	if peak_i > 0 and peak_i < pos.size() - 1:
		v = pos[peak_i + 1] - pos[peak_i - 1]
	var dir := "thrust"
	var av := v.abs()
	if av.y > av.x and av.y > av.z:
		dir = "overhead" if v.y < 0.0 else "rising"
	elif av.x > av.z:
		dir = "left" if v.x > 0.0 else "right"   # model +X is the body's left (faces +Z); a blade moving to +X cuts toward its left
	var hit_i := peak_i
	var p0 := pel[0] if pel.size() > 0 else 0.0
	var drop := 0.0
	for y in pel:
		drop = maxf(drop, p0 - y)
	return {"len": snappedf(anim.length, 0.001), "hit": snappedf(hit_i / FPS, 0.001),
		"active": [snappedf(a / FPS, 0.001), snappedf(b / FPS, 0.001)], "peak_ms": snappedf(spd[peak_i] if spd.size() > 0 else 0.0, 0.01),
		"hand": "l" if use_l else "r", "dir": dir,
		"fwd_hit": snappedf(rt[mini(hit_i, rt.size() - 1)].z - rt[0].z, 0.001),
		"fwd_end": snappedf(rt[rt.size() - 1].z - rt[0].z, 0.001), "side_end": snappedf(rt[rt.size() - 1].x - rt[0].x, 0.001),
		"drop": snappedf(drop, 0.001), "loop": anim.loop_mode != Animation.LOOP_NONE}


func _speeds(p: PackedVector3Array) -> PackedFloat32Array:
	var s := PackedFloat32Array()
	for i in p.size():
		var a := p[maxi(i - 1, 0)]
		var b := p[mini(i + 1, p.size() - 1)]
		s.append(a.distance_to(b) * FPS / 2.0)
	return s


func _mx(a: PackedFloat32Array) -> float:
	var m := 0.0
	for v in a:
		m = maxf(m, v)
	return m


var _track_cache := {}


func _track(anim: Animation, bone: String, type: int) -> int:
	var k := "%d:%s:%d" % [anim.get_instance_id(), bone, type]
	if not _track_cache.has(k):
		var f := -1
		for i in anim.get_track_count():
			if anim.track_get_type(i) == type and String(anim.track_get_path(i)).ends_with(":" + bone):
				f = i
				break
		_track_cache[k] = f
	return _track_cache[k]


func _global(sk: Skeleton3D, anim: Animation, b: int, t: float) -> Transform3D:
	var x := Transform3D.IDENTITY
	while b >= 0:
		var rest := sk.get_bone_rest(b)
		var nm := sk.get_bone_name(b)
		var pt := _track(anim, nm, Animation.TYPE_POSITION_3D)
		var rt := _track(anim, nm, Animation.TYPE_ROTATION_3D)
		var pos := anim.position_track_interpolate(pt, t) if pt >= 0 else rest.origin
		var rot := anim.rotation_track_interpolate(rt, t) if rt >= 0 else rest.basis.get_rotation_quaternion()
		x = Transform3D(Basis(rot), pos) * x
		b = sk.get_bone_parent(b)
	return x
