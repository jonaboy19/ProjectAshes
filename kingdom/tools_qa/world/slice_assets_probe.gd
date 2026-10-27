extends SceneTree
## Checks the benchmark-slice assets load: generated trees (LOD children) and the real-world instancer mesh asset list.

func _initialize() -> void:
	for t in ["oak_0", "ash_0", "beech_0"]:
		var p := "res://assets/generated/slice_trees/%s.gltf" % t
		print(t, " exists=", ResourceLoader.exists(p))
		if ResourceLoader.exists(p):
			var inst := (load(p) as PackedScene).instantiate()
			var names: Array = []
			for mi in inst.find_children("*", "MeshInstance3D", true, false):
				names.append(String(mi.name) + "/" + String(mi.get_parent().name))
			print("  meshes: ", names)
			inst.free()
	var RI := preload("res://scripts/world/real_instancer.gd")
	var ks: Array = RI.kinds()
	print("kinds ", ks.size())
	var ml: Array = RI.mesh_assets(false)
	print("mesh assets ", ml.size())
	quit()
