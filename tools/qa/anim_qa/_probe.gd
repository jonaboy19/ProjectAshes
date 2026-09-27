extends SceneTree
func _init() -> void:
	var files := ["res://assets/incoming/quaternius/ultimate-animated-character/glTF/Goblin_Male.gltf",
		"res://assets/incoming/quaternius/ultimate-animated-animals/glTF/Wolf.gltf"]
	for n in ["goblin","orc","troll","wolf","boar","bear","spider","wyvern"]:
		files.append("res://assets/incoming/ai3d/meshy/creatures/%s.glb" % n)
	for n in ["procedural/chicken","procedural/rabbit","procedural/duck","quaternius/cow","quaternius/horse_riding","quaternius/dog","quaternius/cat","quaternius/deer"]:
		files.append("res://assets/incoming/animals/%s.glb" % n)
	for f in files:
		printerr("LOADING ", f, " ", Time.get_ticks_msec())
		var m: Node = (load(f) as PackedScene).instantiate()
		var ap := Assets.animation_player(m)
		var sks := m.find_children("*", "Skeleton3D", true, false)
		var line: String = f.get_file() + " clips=" + str(ap.get_animation_list() if ap else []) 
		if sks.size() > 0:
			var sk: Skeleton3D = sks[0]
			var names := []
			for i in sk.get_bone_count(): names.append(sk.get_bone_name(i))
			line += "\n   bones=" + str(names)
		print(line)
		m.free()
	quit()
