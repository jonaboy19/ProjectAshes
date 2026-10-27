extends SceneTree
## Ranks guard/idle clips by stance width and depth (AAA gate ref 03: wide, bent-knee): mean foot spread (m), pelvis drop
## below the standing rest (m) and the shield-hand height (m) over the clip, manual FK from the clip tracks.
##   godot --headless --path kingdom -s res://tools_qa/combat/stance_measure.gd
const FILES := ["res://assets/incoming/animations/mixamo_combat/UAL_Mx_sword_and_shield.glb",
	"res://assets/incoming/animations/mixamo_combat/UAL_Mx_great_sword.glb",
	"res://assets/incoming/animations/mixamo_combat/UAL_Mx_melee_axe.glb",
	"res://assets/incoming/animations/mixamo_owner/UAL_Mixamo_Owner.glb",
	"res://assets/incoming/animations/mixamo_owner/UAL_Mixamo_Owner2.glb"]
var _tc := {}

func _initialize() -> void:
	var rows: Array = []
	for f in FILES:
		var inst := (load(f) as PackedScene).instantiate()
		root.add_child(inst)
		var ap := inst.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		var sk := inst.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		var rest_pel := _g(sk, null, sk.find_bone("pelvis"), 0.0).origin.y
		for an in ap.get_animation_list():
			var low := String(an).to_lower()
			if not (("idle" in low or "block" in low or "walk" in low or "strafe" in low) and not "crouch" in low):
				continue
			var a := ap.get_animation(an)
			var n := 12
			var spread := 0.0; var pel := 0.0; var hand := 0.0
			for i in n:
				var t := a.length * i / n
				var fl := _g(sk, a, sk.find_bone("foot_l"), t).origin
				var fr := _g(sk, a, sk.find_bone("foot_r"), t).origin
				spread += Vector2(fl.x - fr.x, fl.z - fr.z).length() / n
				pel += _g(sk, a, sk.find_bone("pelvis"), t).origin.y / n
				hand += _g(sk, a, sk.find_bone("hand_l"), t).origin.y / n
			rows.append([an, snappedf(spread, 0.01), snappedf(rest_pel - pel, 0.01), snappedf(hand, 0.01)])
		inst.queue_free()
	rows.sort_custom(func(x, y): return x[1] + x[2] * 2.0 > y[1] + y[2] * 2.0)
	for r in rows:
		print("STANCE %s spread=%.2f drop=%.2f shield_hand_y=%.2f" % r)
	quit()

func _tr(a: Animation, bone: String, type: int) -> int:
	if a == null:
		return -1
	var k := "%d:%s:%d" % [a.get_instance_id(), bone, type]
	if not _tc.has(k):
		var f := -1
		for i in a.get_track_count():
			if a.track_get_type(i) == type and String(a.track_get_path(i)).ends_with(":" + bone):
				f = i
				break
		_tc[k] = f
	return _tc[k]

func _g(sk: Skeleton3D, a: Animation, b: int, t: float) -> Transform3D:
	var x := Transform3D.IDENTITY
	while b >= 0:
		var rest := sk.get_bone_rest(b)
		var nm := sk.get_bone_name(b)
		var pt := _tr(a, nm, Animation.TYPE_POSITION_3D)
		var rt := _tr(a, nm, Animation.TYPE_ROTATION_3D)
		var pos := a.position_track_interpolate(pt, t) if pt >= 0 else rest.origin
		var rot := a.rotation_track_interpolate(rt, t) if rt >= 0 else rest.basis.get_rotation_quaternion()
		if nm == "root":
			pos = Vector3.ZERO
		x = Transform3D(Basis(rot), pos) * x
		b = sk.get_bone_parent(b)
	return x
