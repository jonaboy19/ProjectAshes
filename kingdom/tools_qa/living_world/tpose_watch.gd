extends Node
## QA: T-pose detector. Every second, every VISIBLE humanoid skeleton whose upper arms sit exactly at their rest pose (nothing
## animates them: no clip, an inactive tree, or clips that do not key this rig) is printed once with its owner script.
## Add it to any QA run: get_tree().root.add_child(preload("res://tools_qa/living_world/tpose_watch.gd").new())
var _seen := {}
var _t := 0.0


func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0:
		return
	_t = 1.0
	for skn: Node in get_tree().root.find_children("*", "Skeleton3D", true, false):
		var sk := skn as Skeleton3D
		if sk == null or not sk.is_visible_in_tree() or _seen.has(sk.get_instance_id()):
			continue
		var ul := sk.find_bone("upperarm_l")
		var ur := sk.find_bone("upperarm_r")
		if ul < 0 or ur < 0:
			continue
		if sk.get_bone_pose_rotation(ul).angle_to(sk.get_bone_rest(ul).basis.get_rotation_quaternion()) > 0.02:
			continue
		if sk.get_bone_pose_rotation(ur).angle_to(sk.get_bone_rest(ur).basis.get_rotation_quaternion()) > 0.02:
			continue
		var actor: Node = sk
		while actor != null and actor.get_script() == null:
			actor = actor.get_parent()
		var host: Node = actor if actor else sk
		var aps := host.find_children("*", "AnimationPlayer", true, false)
		var ap: AnimationPlayer = aps[0] if not aps.is_empty() else null
		var trees := host.find_children("*", "AnimationTree", true, false)
		_seen[sk.get_instance_id()] = true
		print("TPOSE %s script=%s pos=%s ap_cur='%s' ap_playing=%s tree=%s model=%s" % [host.name,
			(host.get_script() as Script).resource_path if host.get_script() else "?", sk.global_position,
			ap.current_animation if ap else "-", ap.is_playing() if ap else false,
			("active" if (trees[0] as AnimationTree).active else "INACTIVE") if not trees.is_empty() else "none", sk.get_parent().name])
