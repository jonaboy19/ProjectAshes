extends SceneTree
## Character creator screenshot: godot --path kingdom --rendering-method mobile --resolution 1280x720 -s tools_qa/hero/creator_shot.gd -- --out=C:/tmp/x/creator.png
func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var out := "user://creator.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
	get_root().size = Vector2i(1280, 720)
	var cc: Control = (load("res://scripts/ui/character_creation.gd") as GDScript).call("open", get_root(), func(_r: Dictionary) -> void: pass)
	for i in 30:
		await process_frame
	for b in cc.find_children("*", "Button", true, false):
		if (b as Button).text == "Hood up":
			(b as Button).button_pressed = true
	cc.get("ap")["skin"] = 3
	cc.get("ap")["hair_color"] = 3
	cc.call("_changed")
	for i in 40:
		await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(out)
	quit()
