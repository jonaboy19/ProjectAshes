extends SceneTree
func _initialize() -> void:
	for s in ["", "_lod1", "_lod2"]:
		var n: Node = (load("res://assets/generated/characters/hero_tier_a/hero_meshy3%s.glb" % s) as PackedScene).instantiate()
		print("== ", s)
		for m in n.find_children("*", "MeshInstance3D", true, false):
			var mi := m as MeshInstance3D
			var t := 0
			for i in mi.mesh.get_surface_count():
				t += mi.mesh.surface_get_array_len(i)
			print(mi.name, " verts=", t, " skel=", mi.skeleton, " skin=", mi.skin != null, " parent=", mi.get_parent().name)
	quit()
