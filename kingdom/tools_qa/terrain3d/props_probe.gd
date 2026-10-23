extends SceneTree
## Lists the Terrain3D / Terrain3DMaterial properties and methods of the installed addon (diagnostics).
func _initialize() -> void:
	for c in ["Terrain3D", "Terrain3DMaterial"]:
		var names := []
		for p in ClassDB.class_get_property_list(c, true):
			names.append(p["name"])
		print(c, " props: ", names)
	var ms := []
	for m in ClassDB.class_get_method_list("Terrain3D", true):
		ms.append(m["name"])
	print("Terrain3D methods: ", ms)
	quit(0)
