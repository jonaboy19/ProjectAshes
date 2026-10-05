extends SceneTree
## Standalone before / after of the 2D and nameplate fixes: the toast + hint + banner stack, distant nameplates and the
## talk sheet's quotes, all built from the real classes. `--mode=before` turns the new behaviour off (HudLane.enabled = false,
## no Nameplates.refresh, straight quotes), `--mode=after` is the shipped behaviour.
## xvfb-run -a -s "-screen 0 1280x720x24" $G --path . --rendering-driver vulkan -s res://tools_qa/visual_pass/widgets_standalone.gd -- --mode=after --out=/path.png
## The sheet holds three 640x360 panels side by side: toasts, nameplates, quotes.

var _out := "/tmp/widgets.png"
var _after := true
const HudLane := preload("res://scripts/ui/hud_lane.gd")


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		if a == "--mode=before":
			_after = false
	_run.call_deferred()


func _grab() -> Image:
	await process_frame
	await process_frame
	await process_frame
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	img.resize(640, 360, Image.INTERPOLATE_LANCZOS)
	return img


func _run() -> void:
	var AF: GDScript = load("res://scripts/ui/ashes_frame.gd")
	var HudArt: GDScript = load("res://scripts/ui/hud_art.gd")
	HudLane.reset()
	HudLane.enabled = _after
	var panels: Array[Image] = []
	# ---------------------------------------------------------------- panel 1: toast + hint + banner
	var layer := CanvasLayer.new()
	root.add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0.36, 0.45, 0.30)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	var toast := PanelContainer.new()
	var tb: StyleBox = HudArt.card_box(0.9, 10)
	toast.add_theme_stylebox_override("panel", tb)
	toast.anchor_left = 0.5
	toast.anchor_right = 0.5
	toast.offset_top = 80
	toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	var tl := Label.new()
	tl.text = "Wolves at the hedge. Hold them off the cart."
	tl.add_theme_font_override("font", AF.font())
	tl.add_theme_font_size_override("font_size", 19)
	toast.add_child(tl)
	layer.add_child(toast)
	var view: Control = (load("res://scripts/region1/tutorial_prompt_view.gd") as GDScript).new()
	layer.add_child(view)
	var banner: Control = (load("res://scripts/ui/discovery_banner.gd") as GDScript).new()
	layer.add_child(banner)
	var rep := func() -> void:
		if is_instance_valid(toast):
			HudLane.report("toast", toast.position.y, toast.size.y)
	process_frame.connect(rep)
	await process_frame
	view.call("show_prompt", &"move", {"text_key": "", "text_en": "Drag to walk", "anchor": "left_stick", "touch": "drag"})
	banner.call("show_place", "Thornfield", "Market Town")
	for i in 70:
		await process_frame
	panels.append(await _grab())
	process_frame.disconnect(rep)
	layer.queue_free()
	await process_frame
	HudLane.reset()
	# ---------------------------------------------------------------- panel 2: nameplates down a street
	var w3 := Node3D.new()
	root.add_child(w3)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.62, 0.72, 0.85)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.8, 0.8, 0.8)
	w3.add_child(env)
	var cam := Camera3D.new()
	cam.fov = 65.0
	w3.add_child(cam)
	cam.position = Vector3(0, 2.4, 0)
	cam.look_at_from_position(cam.position, Vector3(0, 2.0, -30))
	cam.current = true
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(80, 80)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.5, 0.42, 0.3)
	ground.material_override = gm
	w3.add_child(ground)
	for i in 6:      # roofs
		var roof := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(6, 5, 6)
		roof.mesh = bm
		var rm := StandardMaterial3D.new()
		rm.albedo_color = Color(0.55, 0.3, 0.22)
		roof.material_override = rm
		w3.add_child(roof)
		roof.position = Vector3(-9 if i % 2 == 0 else 9, 2.5, -8 - i * 6.5)
	var Nameplates: GDScript = load("res://scripts/core/nameplates.gd")
	var names := ["Aldric", "Bryce", "Mira", "Osric", "Hale", "Tamsin", "Garrick", "Ivo", "Wren", "Cade", "Sybil", "Pell", "Dunn", "Marek"]
	for i in names.size():
		var tag := Label3D.new()
		tag.text = "%s · villager" % names[i]
		w3.add_child(tag)
		Nameplates.style(tag, Color("9ad0ff"), 26, 40.0 if i % 3 == 0 else 22.0)
		tag.global_position = Vector3(-4.0 + float((i * 7) % 9), 2.4, -4.0 - float(i) * 2.4)
		if not _after:
			tag.set_meta("np_max", 40.0)
	# town board
	var board := Node3D.new()
	board.add_to_group("world_sign")
	board.set_meta("sign_rect", Rect2(-2.4, -0.85, 4.8, 1.7))
	w3.add_child(board)
	board.position = Vector3(0, 3.4, -9)
	var bmesh := MeshInstance3D.new()
	var bbox := BoxMesh.new()
	bbox.size = Vector3(4.6, 1.5, 0.14)
	bmesh.mesh = bbox
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.2, 0.15, 0.1)
	bmesh.material_override = bmat
	board.add_child(bmesh)
	var btxt := Label3D.new()
	btxt.text = "THORNFIELD"
	btxt.font_size = 72
	btxt.pixel_size = 0.0115
	btxt.modulate = Color(0.9, 0.75, 0.4)
	btxt.shaded = false
	btxt.position = Vector3(0, 0, 0.1)
	board.add_child(btxt)
	var near_tag := Label3D.new()      # a villager standing under the board
	near_tag.text = "Hesta Thorne"
	w3.add_child(near_tag)
	Nameplates.style(near_tag, Color(1, 0.95, 0.85), 26, 40.0)
	near_tag.global_position = Vector3(0, 2.6, -8.4)
	for i in 5:
		await process_frame
	if _after:
		Nameplates.refresh(self, cam)
	panels.append(await _grab())
	w3.queue_free()
	await process_frame
	# ---------------------------------------------------------------- panel 3: quotes
	var layer3 := CanvasLayer.new()
	root.add_child(layer3)
	var bg3 := ColorRect.new()
	bg3.color = Color(0.043, 0.039, 0.035)
	bg3.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer3.add_child(bg3)
	var q := Label.new()
	var raw := "\"I knew your grandmother. Or someone like her.\" Hild said, \"Don't ask about the 'old mill' now.\""
	q.text = AF.call("typographic", raw) if _after else raw
	q.add_theme_font_override("font", AF.font())
	q.add_theme_font_size_override("font_size", 40)
	q.add_theme_color_override("font_color", Color("ece3cf"))
	q.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	q.position = Vector2(60, 90)
	q.size = Vector2(1100, 400)
	layer3.add_child(q)
	for i in 4:
		await process_frame
	panels.append(await _grab())
	var sheet := Image.create(640 * 3, 360, false, Image.FORMAT_RGB8)
	for i in panels.size():
		sheet.blit_rect(panels[i], Rect2i(0, 0, 640, 360), Vector2i(i * 640, 0))
	sheet.save_png(_out)
	print("saved ", _out)
	quit()
