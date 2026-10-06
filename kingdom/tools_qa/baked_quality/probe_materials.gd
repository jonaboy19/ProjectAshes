extends SceneTree
## Lists every BUILDINGS mesh: surfaces, tris, material kind, albedo texture (path/size). Output feeds the atlas planning.
func _initialize() -> void:
	await process_frame
	var cls = Assets
	var seen := {}
	for key: String in cls.BUILDINGS:
		var entry: Array = cls.BUILDINGS[key]
		for lod in entry.size() / 2:
			var k := key if lod == 0 else "%s:lod%d" % [key, lod]
			var m: ArrayMesh = cls.building_mesh(k)
			if m == null:
				print("PROBE ", k, " NULL"); continue
			var parts := []
			for i in m.get_surface_count():
				var mat := m.surface_get_material(i)
				var tex := ""
				var id := mat.get_instance_id() if mat else 0
				if mat is ShaderMaterial:
					var t = (mat as ShaderMaterial).get_shader_parameter("albedo_tex")
					if t == null: t = (mat as ShaderMaterial).get_shader_parameter("albedo_texture")
					if t is Texture2D: tex = "%s %dx%d" % [t.resource_path.get_file(), t.get_width(), t.get_height()]
				elif mat is BaseMaterial3D and mat.albedo_texture:
					tex = "%s %dx%d" % [mat.albedo_texture.resource_path.get_file(), mat.albedo_texture.get_width(), mat.albedo_texture.get_height()]
				var ar := m.surface_get_arrays(i)
				parts.append("%s#%d[%s %dv col=%s]" % [(mat.get_class() if mat else "null"), id % 100000, tex, (ar[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), str(ar[Mesh.ARRAY_COLOR] != null)])
				seen[id] = true
			print("PROBE ", k, " ", " | ".join(parts))
	print("PROBE unique materials ", seen.size())
	quit()
