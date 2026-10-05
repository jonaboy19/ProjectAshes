extends SceneTree
## Contact sheet from a Movie Maker PNG sequence (or any folder of PNGs): every Nth frame in a grid.
##   Godot_console.exe --headless --path kingdom -s res://tools_qa/aaa_camera/frame_sheet.gd -- --dir=C:/tmp/walk --out=C:/tmp/walk_sheet.png --cols=4 --n=12 --w=585


func _initialize() -> void:
	var dir := ""
	var out := "user://sheet.png"
	var cols := 4
	var n := 12
	var w := 585
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--dir="):
			dir = a.substr(6)
		elif a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--cols="):
			cols = int(a.substr(7))
		elif a.begins_with("--n="):
			n = int(a.substr(4))
		elif a.begins_with("--w="):
			w = int(a.substr(4))
	var files: Array = []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".png"):
			files.append(f)
	files.sort()
	if files.is_empty():
		push_error("no frames in " + dir)
		quit(1)
		return
	var pick: Array = []
	for i in n:
		pick.append(files[int(float(i) / maxf(n - 1, 1) * (files.size() - 1))])
	var first := Image.load_from_file(dir.path_join(pick[0]))
	var h := int(float(w) * first.get_height() / first.get_width())
	var rows := int(ceil(float(pick.size()) / cols))
	var sheet := Image.create(w * cols, h * rows, false, Image.FORMAT_RGB8)
	for i in pick.size():
		var img := Image.load_from_file(dir.path_join(pick[i]))
		img.convert(Image.FORMAT_RGB8)
		img.resize(w, h, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(img, Rect2i(0, 0, w, h), Vector2i((i % cols) * w, (i / cols) * h))
	sheet.save_png(out)
	print("SHEET ", out, " frames=", files.size())
	quit()
