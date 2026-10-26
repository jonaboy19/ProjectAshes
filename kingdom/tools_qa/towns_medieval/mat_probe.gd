extends SceneTree
## Prints the material/shader of each surface of a few town buildings (headless; no screenshots).
func _init() -> void:
	await process_frame
	for key in ["inn", "house_1", "mhouse_peasant_a", "chapel", "stable"]:
		var m: ArrayMesh = Assets.building_mesh(key)
		if m == null:
			print(key, " null"); continue
		for i in m.get_surface_count():
			var mat := m.surface_get_material(i)
			var sh := ""
			if mat is ShaderMaterial:
				sh = (mat as ShaderMaterial).shader.resource_path + " moss=" + str((mat as ShaderMaterial).get_shader_parameter("moss")) + " w=" + str((mat as ShaderMaterial).get_shader_parameter("weather"))
			print(key, " s", i, " ", mat.get_class() if mat else "none", " ", sh)
	quit()
