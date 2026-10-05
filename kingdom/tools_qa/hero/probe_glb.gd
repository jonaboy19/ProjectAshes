extends SceneTree
## Prints meshes / surfaces / materials / tris / skin binds of a GLB (hero Tier-A recipe probe).
## godot --headless --path kingdom -s tools_qa/hero/probe_glb.gd -- res://path.glb


func _initialize() -> void:
	var path: String = OS.get_cmdline_user_args()[0]
	var n: Node = (load(path) as PackedScene).instantiate()
	get_root().add_child(n)
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var s := "MESH %s vis=%s surf=%d skin=%d" % [m.name, m.visible, m.mesh.get_surface_count(), m.skin.get_bind_count() if m.skin else -1]
		print(s, " aabb=", m.get_aabb())
		for si in m.mesh.get_surface_count():
			var arr := m.mesh.surface_get_arrays(si)
			var idx = arr[Mesh.ARRAY_INDEX]
			var mat := m.mesh.surface_get_material(si)
			var tex := ""
			if mat is BaseMaterial3D and (mat as BaseMaterial3D).albedo_texture:
				tex = (mat as BaseMaterial3D).albedo_texture.resource_path + " " + str((mat as BaseMaterial3D).albedo_texture.get_size())
			print("  surf %d tris=%d mat=%s %s" % [si, (idx.size() if idx != null else 0) / 3, mat.resource_name if mat else "-", tex])
	quit()
