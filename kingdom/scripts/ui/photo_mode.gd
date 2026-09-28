extends Control
## Photo mode: pauses the game, hides the HUD and hands the view to a free
## camera that orbits and dollies around the player. A glass side panel holds
## sliders for field of view, depth-of-field blur and time of day, colour filters
## (a tinted copy of the world Environment set on the photo camera, so the real
## one is never touched) and the shutter, which saves a PNG to user://photos/.
##
## process_mode ALWAYS: it runs while the tree is paused.

signal closed
signal screenshot_saved(path: String)
## The time-of-day slider moved (hours). Daylight is refreshed through the
## current scene's _update_daylight() when it has one; connect this for more.
signal time_scrubbed(hours: float)

const PHOTO_DIR := "user://photos"
const FILTERS := ["None", "Warm", "Cool", "Sepia", "B&W", "Vivid"]
const MIN_DIST := 1.2
const MAX_DIST := 28.0

var player: Node3D

var _cam: Camera3D
var _attrs: CameraAttributesPractical
var _base_env: Environment
var _filter := "None"
var _yaw := 0.0
var _pitch := -0.2
var _dist := 5.0
var _target := Vector3.ZERO
var _blur := 0.0
var _was_paused := false
var _orig_time := 8.0
var _orig_day := 1
var _touches: Dictionary = {}

var _panel: PanelContainer
var _fov_slider: HSlider
var _blur_slider: HSlider
var _time_slider: HSlider
var _time_value: Label
var _filter_buttons: Dictionary = {}
var _hint: Label
var _flash: ColorRect
var _saved_label: Label
var _show_ui: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UITheme.theme()
	visible = false
	_build_ui()
	set_process(false)


func is_active() -> bool:
	return _cam != null


func open(p: Node3D) -> void:
	if is_active() or p == null:
		return
	player = p
	_was_paused = get_tree().paused
	get_tree().paused = true
	_base_env = _find_environment()
	var ws := _world_sim()
	if ws:
		_orig_time = float(ws.get("time_of_day"))
		_orig_day = int(ws.get("day"))
	var src: Variant = player.get("camera")
	_cam = Camera3D.new()
	_attrs = CameraAttributesPractical.new()
	_attrs.dof_blur_far_enabled = false
	_attrs.dof_blur_near_enabled = false
	_cam.attributes = _attrs
	player.get_parent().add_child(_cam)
	_target = player.global_position + Vector3(0, 1.3, 0)
	if src is Camera3D:
		var sc: Camera3D = src
		_cam.fov = sc.fov
		_cam.far = sc.far
		var off := sc.global_position - _target
		_dist = clampf(off.length(), MIN_DIST * 2.0, MAX_DIST)
		_yaw = atan2(off.x, off.z)
		_pitch = -asin(clampf(off.y / maxf(off.length(), 0.001), -1.0, 1.0))
	_fov_slider.set_value_no_signal(_cam.fov)
	_blur_slider.set_value_no_signal(0.0)
	_blur = 0.0
	_time_slider.set_value_no_signal(_orig_time)
	_time_value.text = _clock(_orig_time)
	_set_filter("None")
	_cam.current = true
	_update_camera()
	_touches.clear()
	_panel.visible = true
	_show_ui.visible = false
	_saved_label.modulate.a = 0.0
	visible = true
	set_process(true)


func close() -> void:
	if not is_active():
		return
	var ws := _world_sim()
	if ws:
		ws.set("time_of_day", _orig_time)
		ws.set("day", _orig_day)
		_refresh_daylight()
	var src: Variant = player.get("camera") if is_instance_valid(player) else null
	if src is Camera3D:
		(src as Camera3D).current = true
	_cam.queue_free()
	_cam = null
	visible = false
	set_process(false)
	get_tree().paused = _was_paused
	closed.emit()


func _unhandled_input(e: InputEvent) -> void:
	if is_active() and (e.is_action_pressed("ui_cancel") or e.is_action_pressed("photo_mode")):
		close()
		get_viewport().set_input_as_handled()


# --- camera ----------------------------------------------------------------------

func _process(_delta: float) -> void:
	if is_active():
		_update_camera()


func _update_camera() -> void:
	var dir := Vector3(sin(_yaw) * cos(_pitch), -sin(_pitch), cos(_yaw) * cos(_pitch))
	var pos := _target + dir * _dist
	var ground := WorldGen.height(pos.x, pos.z) + 0.35
	var water := WorldGen.water_level_at(pos.x, pos.z)
	if not is_nan(water):
		ground = maxf(ground, water + 0.3)
	pos.y = maxf(pos.y, ground)
	_cam.global_position = pos
	if not pos.is_equal_approx(_target):
		_cam.look_at(_target, Vector3.UP)
	# Focus on the player; blur what lies well behind (and a little in front).
	var focus := pos.distance_to(_target)
	var on := _blur > 0.01
	_attrs.dof_blur_far_enabled = on
	_attrs.dof_blur_near_enabled = on
	_attrs.dof_blur_far_distance = focus + lerpf(6.0, 1.0, _blur)
	_attrs.dof_blur_far_transition = lerpf(12.0, 3.0, _blur)
	_attrs.dof_blur_near_distance = maxf(0.1, focus * 0.45)
	_attrs.dof_blur_near_transition = maxf(0.1, focus * 0.3)
	_attrs.dof_blur_amount = _blur * 0.2


func _gui_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		if e.pressed:
			_touches[e.index] = e.position
		else:
			_touches.erase(e.index)
		accept_event()
	elif e is InputEventScreenDrag:
		var old: Vector2 = _touches.get(e.index, e.position - e.relative)
		_touches[e.index] = e.position
		if _touches.size() == 1:
			_yaw -= e.relative.x * 0.007
			_pitch = clampf(_pitch + e.relative.y * 0.005, -1.35, 1.2)
		elif _touches.size() >= 2:
			for k: int in _touches:
				if k != e.index:
					var o: Vector2 = _touches[k]
					var d0 := old.distance_to(o)
					var d1 := (e.position as Vector2).distance_to(o)
					if d0 > 4.0 and d1 > 4.0:
						_dist = clampf(_dist * d0 / d1, MIN_DIST, MAX_DIST)
					break
		accept_event()
	elif e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP:
			_dist = clampf(_dist / 1.12, MIN_DIST, MAX_DIST)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_dist = clampf(_dist * 1.12, MIN_DIST, MAX_DIST)
	elif e is InputEventMagnifyGesture:
		_dist = clampf(_dist / e.factor, MIN_DIST, MAX_DIST)


# --- environment & filters -------------------------------------------------------

func _find_environment() -> Environment:
	var src: Variant = player.get("camera") if player else null
	if src is Camera3D and (src as Camera3D).environment:
		return (src as Camera3D).environment       # interiors give the camera their own
	var w3d := player.get_world_3d() if player else null
	if w3d and w3d.environment:
		return w3d.environment
	var found := player.get_viewport().find_children("*", "WorldEnvironment", true, false) if player else []
	return (found[0] as WorldEnvironment).environment if not found.is_empty() else null


func _set_filter(f: String) -> void:
	_filter = f
	for k: String in _filter_buttons:
		(_filter_buttons[k] as Button).button_pressed = k == f
	_apply_environment()


## A copy of the world Environment with the filter's adjustments, on the photo camera only.
func _apply_environment() -> void:
	if _cam == null:
		return
	if _base_env == null or _filter == "None":
		_cam.environment = null
		return
	var env: Environment = _base_env.duplicate()
	env.adjustment_enabled = true
	var sat := _base_env.adjustment_saturation if _base_env.adjustment_enabled else 1.0
	var con := _base_env.adjustment_contrast if _base_env.adjustment_enabled else 1.0
	var bri := _base_env.adjustment_brightness if _base_env.adjustment_enabled else 1.0
	match _filter:
		"Warm":
			env.adjustment_saturation = sat * 1.08
			env.adjustment_color_correction = _tint([[0.0, Color(0.03, 0.01, 0.0)], [1.0, Color(1.0, 0.9, 0.74)]])
		"Cool":
			env.adjustment_saturation = sat * 0.92
			env.adjustment_color_correction = _tint([[0.0, Color(0.0, 0.01, 0.04)], [1.0, Color(0.82, 0.94, 1.0)]])
		"Sepia":
			env.adjustment_saturation = 0.0
			env.adjustment_contrast = con * 1.05
			env.adjustment_color_correction = _tint([[0.0, Color(0.08, 0.05, 0.02)], [0.5, Color(0.6, 0.46, 0.3)],
				[1.0, Color(1.0, 0.94, 0.8)]])
		"B&W":
			env.adjustment_saturation = 0.0
			env.adjustment_contrast = con * 1.18
		"Vivid":
			env.adjustment_saturation = sat * 1.3
			env.adjustment_contrast = con * 1.08
			env.adjustment_brightness = bri * 1.03
	_cam.environment = env


static func _tint(stops: Array) -> GradientTexture1D:
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for s: Array in stops:
		offs.append(float(s[0]))
		cols.append(s[1])
	var g := Gradient.new()
	g.offsets = offs
	g.colors = cols
	var tex := GradientTexture1D.new()
	tex.gradient = g
	tex.width = 256
	return tex


func _refresh_daylight() -> void:
	var scene := get_tree().current_scene
	if scene and scene.has_method("_update_daylight"):
		scene.call("_update_daylight")


func _world_sim() -> Node:
	return get_node_or_null("/root/WorldSim")


# --- screenshot ------------------------------------------------------------------

func _capture() -> void:
	DirAccess.make_dir_recursive_absolute(PHOTO_DIR)
	var was_panel := _panel.visible
	_panel.visible = false
	_show_ui.visible = false
	_hint.visible = false
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var stamp := Time.get_datetime_string_from_system().replace(":", "").replace("-", "").replace("T", "_")
	var path := "%s/rising_ashes_%s_%03d.png" % [PHOTO_DIR, stamp, Time.get_ticks_msec() % 1000]
	var err := img.save_png(path) if img else ERR_CANT_CREATE
	_panel.visible = was_panel
	_show_ui.visible = not was_panel
	_hint.visible = true
	_flash.modulate.a = 0.85
	var tw := create_tween()
	tw.tween_property(_flash, "modulate:a", 0.0, 0.35)
	_saved_label.text = ("Saved  " + path.get_file()) if err == OK else "Could not save the photo"
	var tl := create_tween()
	tl.tween_property(_saved_label, "modulate:a", 1.0, 0.15)
	tl.tween_interval(2.0)
	tl.tween_property(_saved_label, "modulate:a", 0.0, 0.5)
	if err == OK:
		screenshot_saved.emit(ProjectSettings.globalize_path(path))


# --- UI --------------------------------------------------------------------------

func _build_ui() -> void:
	_flash = ColorRect.new()
	_flash.color = Color.WHITE
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.modulate.a = 0.0
	add_child(_flash)

	_hint = _label(self, 14, UITheme.TEXT_DIM)
	_hint.text = "Drag to orbit  ·  pinch to move closer"
	_hint.position = Vector2(24, 20)

	_saved_label = _label(self, 16, UITheme.OK)
	_saved_label.anchor_left = 0.5
	_saved_label.anchor_right = 0.5
	_saved_label.anchor_top = 1.0
	_saved_label.anchor_bottom = 1.0
	_saved_label.offset_top = -60
	_saved_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_saved_label.modulate.a = 0.0

	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UITheme.panel_box(20))
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 0.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -360
	_panel.offset_right = -16
	_panel.offset_top = 16
	_panel.offset_bottom = -16
	add_child(_panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(scroll)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)

	var head := _label(box, 24, UITheme.ACCENT)
	head.add_theme_font_override("font", UITheme.title_font_weight(700))
	head.text = "PHOTO MODE"
	var rule := ColorRect.new()
	rule.color = UITheme.ACCENT
	rule.custom_minimum_size = Vector2(56, 2)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	box.add_child(rule)

	_fov_slider = _slider_row(box, "Field of view", 20.0, 100.0, 1.0, func(v: float) -> String: return "%d°" % int(v),
		func(v: float) -> void:
			if _cam: _cam.fov = v)
	_blur_slider = _slider_row(box, "Depth of field", 0.0, 1.0, 0.01, func(v: float) -> String:
			return "Off" if v < 0.01 else "%d%%" % int(v * 100.0),
		func(v: float) -> void: _blur = v)
	_time_slider = _slider_row(box, "Time of day", 0.0, 23.99, 0.05, _clock, _on_time)
	_time_value = _time_slider.get_meta("value_label")

	var ftitle := _label(box, 13, UITheme.TEXT_DIM)
	ftitle.text = "FILTER"
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	box.add_child(grid)
	for f: String in FILTERS:
		var b := Button.new()
		b.text = f
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(96, 48)
		b.add_theme_stylebox_override("pressed", UITheme.pill(UITheme.ACCENT.darkened(0.35), UITheme.ACCENT))
		b.add_theme_stylebox_override("hover_pressed", UITheme.pill(UITheme.ACCENT.darkened(0.3), UITheme.ACCENT))
		b.pressed.connect(_set_filter.bind(f))
		grid.add_child(b)
		_filter_buttons[f] = b

	var spacer := Control.new()
	spacer.custom_minimum_size.y = 6
	box.add_child(spacer)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	var shutter := Button.new()
	shutter.icon = UITheme.glyph("camera", 44)
	shutter.text = "Capture"
	shutter.focus_mode = Control.FOCUS_NONE
	shutter.custom_minimum_size = Vector2(0, 64)
	shutter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shutter.add_theme_font_size_override("font_size", 19)
	shutter.add_theme_stylebox_override("normal", UITheme.pill(UITheme.ACCENT.darkened(0.25), UITheme.ACCENT, 32))
	shutter.add_theme_stylebox_override("hover", UITheme.pill(UITheme.ACCENT.darkened(0.1), UITheme.ACCENT, 32))
	shutter.add_theme_stylebox_override("pressed", UITheme.pill(UITheme.ACCENT, Color.WHITE, 32))
	shutter.pressed.connect(_capture)
	row.add_child(shutter)
	var hide_btn := Button.new()
	hide_btn.text = "Hide"
	hide_btn.focus_mode = Control.FOCUS_NONE
	hide_btn.custom_minimum_size = Vector2(84, 64)
	hide_btn.pressed.connect(func() -> void:
		_panel.visible = false
		_show_ui.visible = true)
	row.add_child(hide_btn)
	var exit_btn := Button.new()
	exit_btn.text = "Exit photo mode"
	exit_btn.focus_mode = Control.FOCUS_NONE
	exit_btn.custom_minimum_size = Vector2(0, 52)
	exit_btn.add_theme_stylebox_override("normal", UITheme.pill(Color(0, 0, 0, 0), UITheme.STROKE))
	exit_btn.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	exit_btn.pressed.connect(close)
	box.add_child(exit_btn)

	# Brings the panel back after "Hide" (the view stays clean for framing).
	_show_ui = Button.new()
	_show_ui.text = "Show controls"
	_show_ui.focus_mode = Control.FOCUS_NONE
	_show_ui.anchor_left = 1.0
	_show_ui.anchor_right = 1.0
	_show_ui.offset_left = -196
	_show_ui.offset_right = -20
	_show_ui.offset_top = 20
	_show_ui.offset_bottom = 72
	_show_ui.visible = false
	_show_ui.pressed.connect(func() -> void:
		_panel.visible = true
		_show_ui.visible = false)
	add_child(_show_ui)


func _slider_row(parent: Control, title: String, lo: float, hi: float, step: float, fmt: Callable, on_change: Callable) -> HSlider:
	var head := HBoxContainer.new()
	parent.add_child(head)
	var t := _label(head, 15, UITheme.TEXT)
	t.text = title
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := _label(head, 15, UITheme.ACCENT)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.custom_minimum_size = Vector2(300, 40)
	s.focus_mode = Control.FOCUS_NONE
	s.value_changed.connect(func(x: float) -> void:
		v.text = fmt.call(x)
		on_change.call(x))
	s.set_meta("value_label", v)
	parent.add_child(s)
	return s


func _on_time(h: float) -> void:
	var ws := _world_sim()
	if ws == null:
		return
	ws.set("time_of_day", h)
	_refresh_daylight()
	_apply_environment()        # the filter copy must pick up the new fog and sky energy
	time_scrubbed.emit(h)


static func _clock(h: float) -> String:
	return "%02d:%02d" % [int(h), int(fmod(h, 1.0) * 60.0)]


func _label(parent: Control, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l
