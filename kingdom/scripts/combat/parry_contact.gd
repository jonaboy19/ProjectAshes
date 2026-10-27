extends RefCounted
## Blade contact on a parry / block (combat-motion worker; coordinator step 4): the defender's sword hand is pulled onto
## the attacker's blade with Godot's TwoBoneIK3D (upperarm_r -> lowerarm_r -> hand_r) for a short window, so the blades
## visibly meet, then eases back into the clip. Contact point = along the attacker's sword arm toward the defender's chest
## (BLADE_REACH m from the attacker's hand): that is where its blade is at the contact frame.
##
##   var at := ParryContact.contact_point(attacker, defender)
##   ParryContact.play(defender_model_or_actor, at)          # IK in/hold/out over ~0.3 s
## Pure maths in contact_point_from(); one IK node + one marker per defender, created on first use.

const BLADE_REACH := 0.55     ## m from the attacker's sword hand toward the defender: the blade's middle at contact
const CHEST_H := 1.25         ## m above the defender's feet
const IN_S := 0.06
const HOLD_S := 0.10
const OUT_S := 0.16
const PEAK := 0.85            ## influence at full contact (the clip's arm still shows a little)
const NODE := "ParryIK"
const K := preload("res://scripts/vfx/vfx_kit.gd")


## Steel-on-steel sparks for blade and shield contact: a few short hot streaks and a tiny warm light, no glow sprite
## (VFX.sparks adds a STAR glow that read as a cartoon starburst next to ref 03).
static func steel_sparks(parent: Node, pos: Vector3, count := 10) -> void:
	var p := K.pal_from(Color(1.0, 0.8, 0.5))
	K.emit(parent, pos, {"amount": count, "life": 0.22, "v": Vector2(2.5, 6.0), "spread": 55.0, "gravity": Vector3(0, -16, 0),
		"damping": Vector2(1, 3), "size": Vector2(0.02, 0.12), "stretch": true, "mat": K.sprite_mat(K.DOT, p, 3.0, {"heat": 1.3})})
	K.light(parent, pos, Color(1.0, 0.75, 0.45), 0.8, 0.08, 2.5)


## Pure: blade contact between an attacker's sword hand and the defender's chest.
static func contact_point_from(hand: Vector3, chest: Vector3) -> Vector3:
	var d := chest - hand
	if d.length() < 0.01:
		return hand
	return hand + d.normalized() * minf(BLADE_REACH, d.length() * 0.6)


static func contact_point(attacker: Node, defender: Node3D) -> Vector3:
	var chest := defender.global_position + Vector3.UP * CHEST_H
	if not (attacker is Node3D):
		return chest + _forward(defender) * 0.5
	var hand := _bone_world(attacker as Node3D, "hand_r")
	if not hand.is_finite():
		var a := (attacker as Node3D).global_position + Vector3.UP * CHEST_H
		return a.lerp(chest, 0.5)
	return contact_point_from(hand, chest)


static func _forward(n: Node3D) -> Vector3:
	return n.global_basis.z.normalized()


static func _bone_world(n: Node3D, bone: String) -> Vector3:
	var sks := n.find_children("*", "Skeleton3D", true, false)
	if sks.is_empty():
		return Vector3.INF
	var sk := sks[0] as Skeleton3D
	var b := sk.find_bone(bone)
	if b < 0:
		return Vector3.INF
	return sk.global_transform * sk.get_bone_global_pose(b).origin


## Pull the defender's sword hand onto `at` for one contact window.
static func play(defender: Node3D, at: Vector3) -> bool:
	var sks := defender.find_children("*", "Skeleton3D", true, false)
	if sks.is_empty():
		return false
	var sk := sks[0] as Skeleton3D
	var ik := sk.get_node_or_null(NODE) as TwoBoneIK3D
	if ik == null:
		if sk.find_bone("upperarm_r") < 0 or sk.find_bone("hand_r") < 0:
			return false
		ik = TwoBoneIK3D.new()
		ik.name = NODE
		ik.setting_count = 1
		ik.set_root_bone(0, sk.find_bone("upperarm_r"))
		ik.set_middle_bone(0, sk.find_bone("lowerarm_r"))
		ik.set_end_bone(0, sk.find_bone("hand_r"))
		sk.add_child(ik)           # last in the stack: after the clip and the rig, so the contact wins briefly
		var target := Marker3D.new()
		target.name = "ParryTarget"
		target.top_level = true
		ik.add_child(target)
		var pole := Marker3D.new()
		pole.name = "ParryPole"
		pole.top_level = true
		ik.add_child(pole)
		ik.set_target_node(0, ik.get_path_to(target))
		ik.set_pole_node(0, ik.get_path_to(pole))
		ik.influence = 0.0
	var tgt := ik.get_node("ParryTarget") as Marker3D
	var pole_m := ik.get_node("ParryPole") as Marker3D
	tgt.global_position = at
	# elbow out and down, away from the body's centre line
	var side := defender.global_basis.x.normalized()
	pole_m.global_position = defender.global_position + Vector3.UP * 0.9 - side * 0.6
	var old: Variant = ik.get_meta("tween", null)
	if old is Tween and (old as Tween).is_valid():
		(old as Tween).kill()
	var tw := ik.create_tween()
	tw.tween_property(ik, "influence", PEAK, IN_S)
	tw.tween_interval(HOLD_S)
	tw.tween_property(ik, "influence", 0.0, OUT_S).set_trans(Tween.TRANS_SINE)
	ik.set_meta("tween", tw)
	return true
