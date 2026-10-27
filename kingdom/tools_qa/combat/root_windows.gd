extends SceneTree
## Prints where each dodge/step clip's root actually travels (10 %..95 % of horizontal travel) so trims keep the motion.
##   godot --headless --path kingdom -s res://tools_qa/combat/root_windows.gd
const CM := preload("res://scripts/combat/combat_motion.gd")
func _initialize() -> void:
	var inst := (load("res://assets/incoming/animations/mixamo_combat/UAL_Mx_combat_set4.glb") as PackedScene).instantiate()
	var ap := inst.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	for n in ap.get_animation_list():
		if not ("Dodge" in n or "Roll" in n or "Step" in n):
			continue
		var p := CM.profile(ap.get_animation(n))
		var total := p[p.size() - 1]
		var tl := Vector2(total.x, total.z).length()
		var t0 := -1.0
		var t1 := -1.0
		for i in p.size():
			var d := Vector2(p[i].x, p[i].z).length()
			if t0 < 0.0 and d >= tl * 0.1:
				t0 = i / 30.0
			if t1 < 0.0 and d >= tl * 0.95:
				t1 = i / 30.0
		print("WIN %s len=%.2f travel=%.2f (x %.2f z %.2f) move=%.2f..%.2f" % [n, ap.get_animation(n).length, tl, total.x, total.z, t0, t1])
	quit()
