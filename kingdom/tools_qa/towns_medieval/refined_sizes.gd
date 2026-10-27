extends SceneTree
## Prints the bounds of every refined building (props_refined/buildings/<name>/<name>.glb): size, min corner, so lot
## footprints and door sides can be set.  godot --headless --path kingdom -s res://tools_qa/towns_medieval/refined_sizes.gd


func _initialize() -> void:
	var dir := "res://assets/props_refined/buildings/"
	for n: String in DirAccess.get_directories_at(dir):
		var path := "%s%s/%s.glb" % [dir, n, n]
		if not ResourceLoader.exists(path):
			continue
		var scene := (load(path) as PackedScene).instantiate()
		var bb := AABB()
		var first := true
		for mi in scene.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			var xf := Transform3D.IDENTITY
			var up: Node = m
			while up != null and up != scene:
				if up is Node3D:
					xf = (up as Node3D).transform * xf
				up = up.get_parent()
			var b := xf * m.get_aabb()
			bb = b if first else bb.merge(b)
			first = false
		print("REFINED %s size=%s min=%s" % [n, bb.size, bb.position])
		scene.free()
	quit(0)
