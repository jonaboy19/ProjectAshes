extends SceneTree
## Prints size (w x h x d, metres) and tris of every meshy_dl3 LOD0 model: headless, no rendering.
func _initialize() -> void:
	var root_dir := "res://assets/incoming/meshy_dl3/"
	var dirs := Array(DirAccess.get_directories_at(root_dir))
	dirs.sort()
	for d: String in dirs:
		var files := Array(DirAccess.get_files_at(root_dir + d))
		files.sort()
		for f: String in files:
			if not f.ends_with("_lod0.glb"):
				continue
			var n: Node3D = Assets.static_model(root_dir + d + "/" + f)
			var box := Assets.visual_aabb(n)
			var tris := 0
			for mi in n.find_children("*", "MeshInstance3D", true, false) + ([n] if n is MeshInstance3D else []):
				if (mi as MeshInstance3D).mesh:
					tris += (mi as MeshInstance3D).mesh.get_faces().size() / 3
			print("DIM %s/%s %.2f %.2f %.2f tris=%d minY=%.2f" % [d, f.trim_suffix("_lod0.glb"), box.size.x, box.size.y, box.size.z, tris, box.position.y])
	quit()
