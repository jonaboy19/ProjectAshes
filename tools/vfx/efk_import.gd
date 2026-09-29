extends SceneTree
## Convert Effekseer .efkefc files to Godot .res resources WITHOUT enabling the editor plugin
## (the plugin's import plugin only registers in an editor session that started with it enabled;
## `godot --headless --import` on an existing .godot cache skips it). Uses the GDExtension's own
## EffekseerEffect.import(), same call the plugin makes.
##   Godot --path kingdom --headless --script res://../tools/vfx/efk_import.gd   (or copy next to the project)
##   args after --:  <res://source.efkefc> <res://dest.res> [scale]
func _init() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() < 2:
		printerr("usage: -- <res://src.efkefc> <res://dst.res> [scale]")
		quit(1)
		return
	var e := EffekseerEffect.new()
	e.import(a[0], true)
	e.scale = float(a[2]) if a.size() > 2 else 1.0
	var err := ResourceSaver.save(e, a[1], ResourceSaver.FLAG_COMPRESS)
	print("efk_import ", a[0], " -> ", a[1], " err=", err, " bytes=", e.data_bytes.size())
	quit(0 if err == OK else 1)
