class_name CutscenePlayer
extends Node
## Plays a cinematic shot list with its own Camera3D, letterbox bars, subtitles
## and fades, then hands the view back to whichever camera was current.
##
## A shot is a plain Dictionary so cutscenes can live in data (JSON, quest
## resources, code). Keys (only `from` and `duration` are needed):
##   from: Vector3          camera start position
##   to: Vector3            camera end position (default: from)
##   look: Vector3          look-at target at start (default: 10 m ahead, -Z)
##   look_to: Vector3       look-at target at end (default: look)
##   fov: float             vertical FOV at start (default 55)
##   fov_to: float          FOV at end (default: fov)
##   duration: float        seconds (default 3)
##   ease: String | float   "linear", "in", "out", "in_out" (default), "smooth",
##                          or a raw curve for @GlobalScope.ease()
##   text: String           subtitle (optional)
##   speaker: String        speaker name shown above the subtitle (optional)
##   fade_in: float         seconds fading up from black at the start (optional)
##   fade_out: float        seconds fading to black at the end (optional)
##   fade_color: Color      default black
##   time: float            optional hour of day; not applied here, passed via
##                          shot_started so the caller can set WorldSim.time_of_day
##   roll: float            camera roll in degrees (optional)
##
## Skipping: Esc / ui_cancel skips at once; any other key, click or tap shows
## "Tap again to skip" and a second one within SKIP_WINDOW skips.
##
## Hooking it in (later, e.g. from main.gd for a new game):
##   var cs := CutscenePlayer.new()
##   add_child(cs)
##   cs.shot_started.connect(func(_i: int, shot: Dictionary) -> void:
##       if shot.has("time"): WorldSim.time_of_day = float(shot["time"]))
##   cs.finished.connect(cs.queue_free)
##   cs.play(BirthCutscene.build("Aren", "Hale", "Edda", "Osric"))
## For headless tests, call advance(delta) manually instead of relying on _process.

signal finished
signal skipped
signal shot_started(index: int, shot: Dictionary)

## Height of each letterbox bar as a fraction of the screen (≈2.35:1 at 16:9).
const LETTERBOX := 0.12
const BAR_IN_TIME := 0.7
const SKIP_GRACE := 0.3
const SKIP_WINDOW := 2.5
const SUB_FADE := 0.35
const ACCENT := Color("f0c060")
const TEXT := Color("f6f1e7")

var shots: Array = []
var playing := false
var skippable := true
var index := -1
## Seconds into the current shot / since play() started.
var shot_time := 0.0
var elapsed := 0.0
var camera: Camera3D

var _prev_camera: Camera3D
var _layer: CanvasLayer
var _top: ColorRect
var _bottom: ColorRect
var _fade: ColorRect
var _sub_box: VBoxContainer
var _speaker: Label
var _text: Label
var _hint: Label
var _bars := 0.0
var _skip_armed := -1.0   # elapsed time until which a second press skips


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()


func _ready() -> void:
	set_process(playing)
	# main.gd plays cutscenes inside the world SubViewport, whose container ignores the
	# mouse, so taps and clicks never reach _input there. Listen on the window as well.
	if get_viewport() != get_tree().root:
		get_tree().root.window_input.connect(_on_window_input)


func _on_window_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or (event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION):
		_input(event)   # (a tap also arrives as an emulated click; count it once)


func _process(delta: float) -> void:
	advance(delta)


## Starts playing `list` (Array of shot Dictionaries). Replaces any cutscene in progress.
func play(list: Array) -> void:
	if playing:
		_end(false, false)
	shots = list.duplicate()
	elapsed = 0.0
	_bars = 0.0
	_skip_armed = -1.0
	if shots.is_empty():
		finished.emit()
		return
	playing = true
	_prev_camera = null
	if is_inside_tree():
		_prev_camera = get_viewport().get_camera_3d()
		# The viewport auto-promotes the first camera to enter the tree; that's us, not a camera to restore.
		if _prev_camera == camera:
			_prev_camera = null
		camera.make_current()
	_layer.visible = true
	_hint.modulate.a = 0.0
	_start_shot(0)
	_apply()
	set_process(true)


## Advances playback by `delta` seconds. Called from _process; tests can call it directly.
func advance(delta: float) -> void:
	if not playing:
		return
	elapsed += delta
	shot_time += delta
	_bars = minf(1.0, _bars + delta / BAR_IN_TIME)
	while playing and shot_time >= _duration(shots[index]):
		shot_time -= _duration(shots[index])
		if index + 1 >= shots.size():
			_end(true, false)
			return
		_start_shot(index + 1)
	_apply()


## Ends the cutscene now (if skippable) and emits `skipped` then `finished`.
func skip() -> void:
	if playing and skippable:
		_end(true, true)


## Total running time of a shot list in seconds.
static func total_duration(list: Array) -> float:
	var t := 0.0
	for s: Dictionary in list:
		t += _duration(s)
	return t


func current_shot() -> Dictionary:
	return shots[index] if playing and index >= 0 and index < shots.size() else {}


func _input(event: InputEvent) -> void:
	if not playing or not skippable:
		return
	var pressed := false
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo:
			if k.keycode == KEY_ESCAPE or event.is_action_pressed("ui_cancel"):
				skip()
				_handled()
				return
			pressed = true
	elif event is InputEventMouseButton:
		pressed = (event as InputEventMouseButton).pressed
	elif event is InputEventScreenTouch:
		pressed = (event as InputEventScreenTouch).pressed
	if not pressed:
		return
	_handled()
	press_skip()


## A tap/click/key: first arms skipping (shows the hint), a second within
## SKIP_WINDOW skips. Ignored for the first SKIP_GRACE seconds.
func press_skip() -> void:
	if not playing or elapsed < SKIP_GRACE:
		return
	if _skip_armed >= elapsed:
		skip()
	else:
		_skip_armed = elapsed + SKIP_WINDOW


func _handled() -> void:
	if is_inside_tree():
		get_viewport().set_input_as_handled()


# --- playback ------------------------------------------------------------------

static func _duration(s: Dictionary) -> float:
	return maxf(0.01, float(s.get("duration", 3.0)))


func _start_shot(i: int) -> void:
	index = i
	var s: Dictionary = shots[i]
	_speaker.text = String(s.get("speaker", "")).to_upper()
	_speaker.visible = _speaker.text != ""
	_text.text = String(s.get("text", ""))
	shot_started.emit(i, s)


func _apply() -> void:
	var s: Dictionary = shots[index]
	var dur := _duration(s)
	var t := clampf(shot_time / dur, 0.0, 1.0)
	var e := _eased(t, s.get("ease", "in_out"))
	var from: Vector3 = s.get("from", Vector3.ZERO)
	var to: Vector3 = s.get("to", from)
	var look: Vector3 = s.get("look", from + Vector3(0, 0, -10))
	var look_to: Vector3 = s.get("look_to", look)
	var fov: float = float(s.get("fov", 55.0))
	var fov_to: float = float(s.get("fov_to", fov))
	camera.fov = clampf(lerpf(fov, fov_to, e), 5.0, 150.0)
	camera.transform = _look_transform(from.lerp(to, e), look.lerp(look_to, e), float(s.get("roll", 0.0)))

	# Fades to/from colour.
	var alpha := 0.0
	var fi := float(s.get("fade_in", 0.0))
	var fo := float(s.get("fade_out", 0.0))
	if fi > 0.0 and shot_time < fi:
		alpha = 1.0 - shot_time / fi
	if fo > 0.0 and shot_time > dur - fo:
		alpha = maxf(alpha, (shot_time - (dur - fo)) / fo)
	var fc: Color = s.get("fade_color", Color.BLACK)
	_fade.color = Color(fc.r, fc.g, fc.b, clampf(alpha, 0.0, 1.0))

	# Subtitle: fades in after a beat, out at the end (unless the next shot carries on the same line).
	var sub_a := 0.0
	if _text.text != "":
		sub_a = clampf((shot_time - 0.15) / SUB_FADE, 0.0, 1.0)
		var next_same := index + 1 < shots.size() and String((shots[index + 1] as Dictionary).get("text", "")) == _text.text
		if not next_same:
			sub_a = minf(sub_a, clampf((dur - shot_time) / SUB_FADE, 0.0, 1.0))
	_sub_box.modulate.a = sub_a

	# Letterbox bars slide in.
	var b := LETTERBOX * _smooth(_bars)
	_top.anchor_bottom = b
	_bottom.anchor_top = 1.0 - b
	_hint.modulate.a = move_toward(_hint.modulate.a, 0.85 if _skip_armed >= elapsed else 0.0, 0.08)


func _end(complete: bool, was_skipped: bool) -> void:
	playing = false
	set_process(false)
	_layer.visible = false
	if is_instance_valid(_prev_camera) and _prev_camera.is_inside_tree():
		_prev_camera.make_current()
	elif camera.is_inside_tree():
		camera.clear_current(false)
	_prev_camera = null
	if was_skipped:
		skipped.emit()
	if complete:
		finished.emit()


static func _eased(t: float, mode: Variant) -> float:
	if mode is float or mode is int:
		return ease(t, float(mode))
	match String(mode):
		"linear":
			return t
		"in":
			return ease(t, 2.0)
		"out":
			return ease(t, 0.5)
		"smooth":
			return _smooth(t)
		_:
			return ease(t, -2.0)


static func _smooth(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)


static func _look_transform(pos: Vector3, target: Vector3, roll_deg := 0.0) -> Transform3D:
	var dir := target - pos
	if dir.length_squared() < 1e-6:
		dir = Vector3(0, 0, -1)
	var up := Vector3.UP
	if absf(dir.normalized().dot(up)) > 0.999:
		up = Vector3(0, 0, -1)
	var basis := Basis.looking_at(dir, up)
	if roll_deg != 0.0:
		basis = basis * Basis(Vector3(0, 0, 1), deg_to_rad(roll_deg))
	return Transform3D(basis, pos)


# --- nodes -----------------------------------------------------------------------

func _build() -> void:
	camera = Camera3D.new()
	camera.name = "CutsceneCamera"
	camera.far = 5000.0
	camera.near = 0.05
	add_child(camera)

	_layer = CanvasLayer.new()
	_layer.name = "CutsceneUI"
	_layer.layer = 90
	_layer.visible = false
	add_child(_layer)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(root)

	_fade = _rect(root, Color(0, 0, 0, 0))
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)

	_top = _rect(root, Color("050507"))
	_top.anchor_left = 0.0
	_top.anchor_right = 1.0
	_top.anchor_top = 0.0
	_top.anchor_bottom = 0.0
	_bottom = _rect(root, Color("050507"))
	_bottom.anchor_left = 0.0
	_bottom.anchor_right = 1.0
	_bottom.anchor_top = 1.0
	_bottom.anchor_bottom = 1.0

	# Subtitles sit just above the bottom bar, centred, cinema style: no box,
	# soft outline and shadow, speaker in tracked small caps in the accent colour.
	_sub_box = VBoxContainer.new()
	_sub_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sub_box.alignment = BoxContainer.ALIGNMENT_END
	_sub_box.anchor_left = 0.12
	_sub_box.anchor_right = 0.88
	_sub_box.anchor_top = 0.55
	_sub_box.anchor_bottom = 1.0 - LETTERBOX - 0.025
	_sub_box.add_theme_constant_override("separation", 6)
	root.add_child(_sub_box)

	var tracked := FontVariation.new()
	tracked.base_font = ThemeDB.fallback_font
	tracked.spacing_glyph = 3
	tracked.variation_embolden = 0.6

	_speaker = Label.new()
	_speaker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_speaker.add_theme_font_override("font", tracked)
	_speaker.add_theme_font_size_override("font_size", 14)
	_speaker.add_theme_color_override("font_color", ACCENT)
	_speaker.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	_speaker.add_theme_constant_override("shadow_offset_y", 1)
	_sub_box.add_child(_speaker)

	_text = Label.new()
	_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.add_theme_font_size_override("font_size", 24)
	_text.add_theme_color_override("font_color", TEXT)
	_text.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
	_text.add_theme_constant_override("outline_size", 6)
	_text.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	_text.add_theme_constant_override("shadow_offset_y", 2)
	_text.add_theme_constant_override("shadow_outline_size", 8)
	_sub_box.add_child(_text)
	_sub_box.modulate.a = 0.0

	_hint = Label.new()
	_hint.text = "Tap again to skip  ›"
	_hint.add_theme_font_override("font", tracked)
	_hint.add_theme_font_size_override("font_size", 12)
	_hint.add_theme_color_override("font_color", Color(TEXT, 0.9))
	_hint.anchor_left = 1.0
	_hint.anchor_right = 1.0
	_hint.anchor_top = 1.0
	_hint.anchor_bottom = 1.0
	_hint.offset_left = -220.0
	_hint.offset_right = -24.0
	_hint.offset_top = -40.0
	_hint.offset_bottom = -16.0
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.modulate.a = 0.0
	root.add_child(_hint)


func _rect(parent: Control, c: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = c
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)
	return r
