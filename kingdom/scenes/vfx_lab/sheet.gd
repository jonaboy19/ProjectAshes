extends SceneTree
## Renders contact sheets of the vfx_lab effects. Needs a display driver (xvfb + vulkan) and a fixed time step:
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver vulkan --fixed-fps 30 --path kingdom \
##       -s scenes/vfx_lab/sheet.gd -- --out=/tmp/vfx_sheet --quality=2
## One PNG per effect (frames at fixed times, side 3/4 camera) + sheet_all.png (rows = effects).
const TIMES := [0.1, 0.22, 0.4, 0.6, 0.85, 1.1, 1.45, 1.9]
var _out := "/tmp/vfx_sheet"
var _q := 2
const CW := 480
const CH := 340
func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): _out = a.substr(6)
		elif a.begins_with("--quality="): _q = int(a.substr(10))
	DirAccess.make_dir_recursive_absolute(_out)
	DisplayServer.window_set_size(Vector2i(CW, CH))
	root.size = Vector2i(CW, CH)
	var vp: Viewport = root
	var stage := Node3D.new()
	root.add_child(stage)
	var cam := VfxLab.build_stage(stage)
	VfxLab.aim(cam, Vector3(4.4, 2.5, 2.2), Vector3(0, 0.9, -2.5))
	cam.current = true
	stage.add_child(VfxLab.stand_in(Vector3.ZERO))
	await process_frame
	var rows: Array = []
	for e in VfxLab.EFFECTS:
		var fx: LabFX = load(e[1]).new()
		fx.quality = _q
		stage.add_child(fx)
		await process_frame
		var row: Array = []
		fx.play()
		var frame := 0
		var ti := 0
		while ti < TIMES.size():
			await process_frame
			frame += 1
			var t := frame / 30.0
			if t >= TIMES[ti] - 0.001:
				await RenderingServer.frame_post_draw
				row.append(vp.get_texture().get_image())
				ti += 1
		rows.append(row)
		fx.queue_free()
		for i in range(8):
			await process_frame
	var cw := CW
	var ch := CH
	var sheet := Image.create(cw * TIMES.size() / 2, ch * rows.size() / 2, false, Image.FORMAT_RGB8)
	for r in range(rows.size()):
		for c in range(TIMES.size()):
			var im: Image = rows[r][c]
			im.convert(Image.FORMAT_RGB8)
			im.resize(cw / 2, ch / 2, Image.INTERPOLATE_BILINEAR)
			sheet.blit_rect(im, Rect2i(0, 0, cw / 2, ch / 2), Vector2i(c * cw / 2, r * ch / 2))
		var one := Image.create(cw * 4, ch * 2, false, Image.FORMAT_RGB8)
		for c in range(TIMES.size()):
			var im2: Image = rows[r][c]
			im2.convert(Image.FORMAT_RGB8)
			one.blit_rect(im2, Rect2i(0, 0, cw, ch), Vector2i((c % 4) * cw, (c / 4) * ch))
		one.save_png("%s/%s.png" % [_out, VfxLab.EFFECTS[r][0]])
	sheet.save_png("%s/sheet_all.png" % _out)
	print("SHEET_DONE ", _out)
	quit()
