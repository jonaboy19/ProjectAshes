extends SceneTree
## Dumps Terrain3D's generated default shader (shader_override_enabled = true copies it into shader_override) to --out=<file>.
## Used to build shaders/terrain3d_ground.gdshader (W3). Godot --headless --path kingdom -s res://tools_qa/terrain3d/dump_shader.gd -- --out=C:/x/default.gdshader
func _initialize() -> void:
	var out := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
	var t := Terrain3D.new()
	t.assets = Terrain3DBridge._make_assets()
	root.add_child(t)
	await process_frame
	var mat := t.material
	mat.shader_override_enabled = true
	await process_frame
	print("RID shader code len: ", RenderingServer.shader_get_code(mat.get_shader_rid()).length())
	if mat.shader_override == null or mat.shader_override.code == "":
		var f0 := FileAccess.open(out, FileAccess.WRITE)
		f0.store_string(RenderingServer.shader_get_code(mat.get_shader_rid()))
		print("dumped RID code")
		quit()
		return
	var code := mat.shader_override.code if mat.shader_override else "<none>"
	print("DUMP len=", code.length())
	if out != "":
		var f := FileAccess.open(out, FileAccess.WRITE)
		f.store_string(code)
	quit()
