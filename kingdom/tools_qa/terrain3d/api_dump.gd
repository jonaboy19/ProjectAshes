extends SceneTree
## Dumps the Terrain3D 1.0.2 runtime API we may adopt (W6.4): instancer, mesh assets, material shader params, collision modes, data queries.

func _initialize() -> void:
	for cls in ["Terrain3D", "Terrain3DInstancer", "Terrain3DMeshAsset", "Terrain3DMaterial", "Terrain3DData", "Terrain3DCollision", "Terrain3DAssets"]:
		if not ClassDB.class_exists(cls):
			print(cls, " MISSING")
			continue
		var ms: Array = []
		for m in ClassDB.class_get_method_list(cls, true):
			ms.append(String(m["name"]))
		var ps: Array = []
		for p in ClassDB.class_get_property_list(cls, true):
			ps.append(String(p["name"]))
		print("== ", cls, "\n  methods: ", ", ".join(ms), "\n  props: ", ", ".join(ps))
	var t := Terrain3D.new()
	root.add_child(t)
	await process_frame
	var mat: Terrain3DMaterial = t.material
	if mat:
		var sh: Shader = mat.get_shader_rid() if false else null
		print("== material shader params:")
		for p in mat.get_property_list():
			var n := String(p["name"])
			if n.begins_with("_shader_parameters/") or n.contains("auto") or n.contains("macro") or n.contains("noise") or n.contains("projection"):
				print("  ", n, " = ", mat.get(n))
	quit()
