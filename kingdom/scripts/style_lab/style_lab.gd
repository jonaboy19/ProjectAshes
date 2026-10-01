extends Control
## STYLE LAB: five dioramas of the same medieval street corner in five visual styles (see docs/design/STYLE_LAB.md).
##
## Interactive (phone or PC):   godot --path kingdom -- --style_lab            (grid; tap a tile for full screen)
##                              ... --style_lab --box=C --cam=close            (open one box directly)
## Render (QA, xvfb or GPU):    godot --path kingdom --rendering-driver vulkan -- --shot=style_lab \
##                                 --out=/tmp/claude-0/shots/style_lab [--box=A,B,C,D,E] [--w=2340 --h=1080]
##   writes <out>_<id>_over.png, <out>_<id>_close.png and <out>_stats.json (draw calls, primitives, objects).
## Each box is its own SubViewport with its own World3D, Environment and sun, so they never leak into each other.

const Style := preload("res://scripts/style_lab/lab_style.gd")
const Diorama := preload("res://scripts/style_lab/lab_diorama.gd")
const Gate := preload("res://scripts/style_lab/lab_gate.gd")

const CAMS := {
	"over": {"pos": Vector3(7.6, 6.2, 12.6), "at": Vector3(-0.2, 1.6, -0.6), "fov": 50.0},
	"close": {"pos": Vector3(2.0, 1.5, 5.3), "at": Vector3(0.0, 1.12, 1.9), "fov": 34.0},
}

const CAMS_G := {
	"over": {"pos": Vector3(0.0, 1.95, 2.8), "at": Vector3(0.0, 4.2, -30.0), "fov": 52.0},
	"close": {"pos": Vector3(2.4, 1.55, 3.0), "at": Vector3(0.0, 1.25, -1.0), "fov": 40.0},
	"facade": {"pos": Vector3(1.0, 2.2, -4.0), "at": Vector3(-8.5, 4.0, -13.0), "fov": 55.0},
	"gate": {"pos": Vector3(0.0, 2.5, -4.0), "at": Vector3(0.0, 14.0, -40.0), "fov": 62.0},
	"stall": {"pos": Vector3(1.5, 1.7, -2.0), "at": Vector3(-6.7, 1.2, -5.0), "fov": 55.0},
}

var _args := {}
var _boxes := {}            # id -> {vp, dio, ctx, pivot, cam}
var _tiles := {}            # id -> {container, label}
var _focus := ""
var _cam_name := "over"
var _grid: GridContainer
var _bar: HBoxContainer
var _hud: Label
var _stat_t := 0.0


func _ready() -> void:
	_args = _parse_args()
	Style.tier = String(_args.get("tier", "high"))
	if OS.has_feature("mobile"):
		DisplayServer.screen_set_orientation(DisplayServer.SCREEN_LANDSCAPE)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color("14110f")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	if _args.has("shot"):
		await _shot_mode()
	else:
		_ui_mode()


static func _parse_args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1] if kv.size() > 1 else "1"
	return out


func _ids() -> Array:
	var want := String(_args.get("box", ""))
	if want == "":
		return Style.IDS.duplicate()
	var out := []
	for s in want.split(",", false):
		if Style.IDS.has(s.to_upper()):
			out.append(s.to_upper())
	return out


# --- box construction -----------------------------------------------------------------------------------------

func _make_box(id: String, parent: Node, size: Vector2i) -> Dictionary:
	var vp := SubViewport.new()
	vp.name = "Box" + id
	vp.own_world_3d = true
	vp.size = size
	vp.msaa_3d = Viewport.MSAA_2X
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	parent.add_child(vp)
	var dio: Node3D = Gate.new() if id == "G" else Diorama.new()
	vp.add_child(dio)
	dio.build(id)
	var ctx := Style.setup(id, vp, dio, dio.lamp_top)
	var pivot := Node3D.new()
	pivot.name = "Pivot"
	pivot.position = Vector3(0, 1.2, 0)
	vp.add_child(pivot)
	var cam := Camera3D.new()
	cam.name = "Cam"
	cam.far = 450.0
	cam.near = 0.1
	pivot.add_child(cam)
	cam.current = true
	var box := {"vp": vp, "dio": dio, "ctx": ctx, "pivot": pivot, "cam": cam}
	_point_cam(box, "over")
	return box


func _point_cam(box: Dictionary, which: String) -> void:
	var c: Dictionary = (CAMS_G if String((box["vp"] as SubViewport).name) == "BoxG" else CAMS)[which]
	var cam: Camera3D = box["cam"]
	var pivot: Node3D = box["pivot"]
	pivot.rotation = Vector3.ZERO
	pivot.position = c["at"]
	cam.fov = c["fov"]
	cam.position = (c["pos"] as Vector3) - (c["at"] as Vector3)
	cam.look_at(c["at"])
	cam.rotation = cam.rotation   # keep local


func _stats(box: Dictionary) -> Dictionary:
	var rid: RID = (box["vp"] as SubViewport).get_viewport_rid()
	var vis := RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE
	var sh := RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW
	return {
		"draw_calls": RenderingServer.viewport_get_render_info(rid, vis, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
		"primitives": RenderingServer.viewport_get_render_info(rid, vis, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME),
		"objects": RenderingServer.viewport_get_render_info(rid, vis, RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME),
		"shadow_draw_calls": RenderingServer.viewport_get_render_info(rid, sh, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
		"shadow_primitives": RenderingServer.viewport_get_render_info(rid, sh, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME),
	}


# --- shot mode ------------------------------------------------------------------------------------------------

func _shot_mode() -> void:
	var out_prefix := String(_args.get("out", "/tmp/claude-0/shots/style_lab"))
	if out_prefix.ends_with(".png"):
		out_prefix = out_prefix.trim_suffix(".png")
	var size := Vector2i(int(_args.get("w", "2340")), int(_args.get("h", "1080")))
	var all_stats := {"renderer": RenderingServer.get_current_rendering_method(), "size": [size.x, size.y],
		"adapter": RenderingServer.get_video_adapter_name(), "boxes": {}}
	for id in _ids():
		var holder := Node.new()
		add_child(holder)
		var box := _make_box(id, holder, size)
		var vp: SubViewport = box["vp"]
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		for i in 4:
			await get_tree().process_frame
		Style.finalize(id, box["ctx"], vp)
		for i in 8:
			await get_tree().process_frame
		var per_cam := {}
		for which in (["over", "close", "facade", "gate", "stall"] if id == "G" else ["over", "close"]):
			_point_cam(box, which)
			for i in 5:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var img := vp.get_texture().get_image()
			var path := "%s_%s_%s.png" % [out_prefix, id, which]
			img.save_png(path)
			per_cam[which] = _stats(box)
			print("style_lab %s %s -> %s  %s" % [id, which, path, str(per_cam[which])])
		all_stats["boxes"][id] = per_cam
		var tri := 0
		all_stats["boxes"][id]["dio_notes"] = (box["dio"] as Node3D).get("tri_note")
		holder.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	all_stats["texture_mem_mb"] = snappedf(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED) / 1048576.0, 0.1)
	var f := FileAccess.open(out_prefix + "_stats.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(all_stats, "  "))
		f.close()
	get_tree().quit()


# --- interactive ----------------------------------------------------------------------------------------------

func _ui_mode() -> void:
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_grid.add_theme_constant_override("h_separation", 6)
	_grid.add_theme_constant_override("v_separation", 6)
	add_child(_grid)
	var tile_size := Vector2i(780, 520)
	for id in _ids():
		var cont := SubViewportContainer.new()
		cont.stretch = true
		cont.custom_minimum_size = Vector2(380, 250)
		cont.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cont.size_flags_vertical = Control.SIZE_EXPAND_FILL
		cont.mouse_filter = Control.MOUSE_FILTER_STOP
		_grid.add_child(cont)
		var box := _make_box(id, cont, tile_size)
		_boxes[id] = box
		var lab := Label.new()
		lab.position = Vector2(10, 6)
		lab.add_theme_font_size_override("font_size", 22)
		lab.add_theme_color_override("font_outline_color", Color.BLACK)
		lab.add_theme_constant_override("outline_size", 6)
		lab.text = Style.TITLES[id]
		cont.add_child(lab)
		_tiles[id] = {"container": cont, "label": lab}
		cont.gui_input.connect(_tile_input.bind(id))
		(box["vp"] as SubViewport).render_target_update_mode = SubViewport.UPDATE_ONCE
	# an empty 6th cell hosts the exit / help button
	var help := VBoxContainer.new()
	help.alignment = BoxContainer.ALIGNMENT_CENTER
	help.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var t := Label.new()
	t.text = "STYLE LAB\nTap a box for full screen.\nSame street corner, five looks.\nIn full screen: drag to orbit."
	t.add_theme_font_size_override("font_size", 22)
	help.add_child(t)
	var exit := Button.new()
	exit.text = "Back to menu"
	exit.custom_minimum_size = Vector2(260, 80)
	exit.pressed.connect(_exit)
	help.add_child(exit)
	_grid.add_child(help)
	# the controls bar shown in focus mode
	_bar = HBoxContainer.new()
	_bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_bar.offset_top = -96
	_bar.offset_bottom = -8
	_bar.offset_left = 12
	_bar.offset_right = -12
	_bar.visible = false
	for spec in [["< Prev", func() -> void: _step(-1)], ["Next >", func() -> void: _step(1)],
			["Overview / Close-up", _toggle_cam], ["Grid", _show_grid]]:
		var b := Button.new()
		b.text = spec[0]
		b.custom_minimum_size = Vector2(190, 80)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(spec[1])
		_bar.add_child(b)
	add_child(_bar)
	_hud = Label.new()
	_hud.position = Vector2(14, 10)
	_hud.add_theme_font_size_override("font_size", 24)
	_hud.add_theme_color_override("font_outline_color", Color.BLACK)
	_hud.add_theme_constant_override("outline_size", 8)
	_hud.visible = false
	add_child(_hud)
	await get_tree().process_frame
	await get_tree().process_frame
	for id in _boxes:
		Style.finalize(id, _boxes[id]["ctx"], _boxes[id]["vp"])
		(_boxes[id]["vp"] as SubViewport).render_target_update_mode = SubViewport.UPDATE_ONCE
	if _args.has("cam"):
		_cam_name = "close" if String(_args["cam"]).begins_with("c") else "over"
	var ids := _ids()
	if _args.has("box") and ids.size() == 1:
		_open(ids[0])


func _tile_input(ev: InputEvent, id: String) -> void:
	var tap: bool = false
	if ev is InputEventMouseButton:
		tap = ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT
	elif ev is InputEventScreenTouch:
		tap = ev.pressed
	if tap and _focus == "":
		_open(id)


func _open(id: String) -> void:
	_focus = id
	for k in _tiles:
		(_tiles[k]["container"] as Control).visible = false
	for k in _boxes:
		(_boxes[k]["vp"] as SubViewport).render_target_update_mode = SubViewport.UPDATE_DISABLED
	var cont: SubViewportContainer = _tiles[id]["container"]
	cont.visible = true
	cont.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_grid.visible = false
	cont.reparent(self, false)
	move_child(cont, 1)
	cont.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	(_boxes[id]["vp"] as SubViewport).render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_point_cam(_boxes[id], _cam_name)
	_bar.visible = true
	_hud.visible = true


func _show_grid() -> void:
	if _focus == "":
		return
	var cont: SubViewportContainer = _tiles[_focus]["container"]
	cont.reparent(_grid, false)
	_grid.move_child(cont, Style.IDS.find(_focus))
	_focus = ""
	_grid.visible = true
	_bar.visible = false
	_hud.visible = false
	for k in _tiles:
		(_tiles[k]["container"] as Control).visible = true
		(_boxes[k]["vp"] as SubViewport).render_target_update_mode = SubViewport.UPDATE_ONCE


func _step(d: int) -> void:
	if _focus == "":
		return
	var ids := _ids()
	var i := (ids.find(_focus) + d + ids.size()) % ids.size()
	var cur := _focus
	_show_grid()
	_open(ids[i])


func _toggle_cam() -> void:
	_cam_name = "close" if _cam_name == "over" else "over"
	if _focus != "":
		_point_cam(_boxes[_focus], _cam_name)


func _exit() -> void:
	get_tree().change_scene_to_file("res://scenes/boot.tscn")


func _unhandled_input(ev: InputEvent) -> void:
	if ev.is_action_pressed("ui_cancel"):
		if _focus != "":
			_show_grid()
		else:
			_exit()
	elif _focus != "" and (ev is InputEventScreenDrag or (ev is InputEventMouseMotion and (ev.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0)):
		var pivot: Node3D = _boxes[_focus]["pivot"]
		pivot.rotate_y(-ev.relative.x * 0.006)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if _focus != "":
			_show_grid()
		else:
			_exit()


func _process(delta: float) -> void:
	_stat_t += delta
	if _stat_t < 0.4:
		return
	_stat_t = 0.0
	if _focus != "" and _boxes.has(_focus):
		var s := _stats(_boxes[_focus])
		_hud.text = "%s   [%s]\nfps %d   draws %d (+%d shadow)   tris %dk (+%dk shadow)" % [
			Style.TITLES[_focus], _cam_name, Engine.get_frames_per_second(), s["draw_calls"], s["shadow_draw_calls"],
			int(s["primitives"]) / 1000, int(s["shadow_primitives"]) / 1000]
	elif _focus == "":
		for id in _boxes:
			var s := _stats(_boxes[id])
			(_tiles[id]["label"] as Label).text = "%s\ndraws %d  tris %dk" % [Style.TITLES[id], s["draw_calls"], int(s["primitives"]) / 1000]
