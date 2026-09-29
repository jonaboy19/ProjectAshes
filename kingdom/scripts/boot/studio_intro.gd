class_name StudioIntro
extends Control
## The studio logo film ("Total Showdown Studios", 5 s, no audio, fades to dark at the end).
## Played contained (letterboxed) in the middle of a black screen so the logo is never cropped
## on wide phones or tablets; the picture's own dark edges hide the bars. Tap, click or any key
## skips it after SKIP_AFTER seconds. If the video cannot be loaded or never starts, a still of the
## logo fades in for a couple of seconds instead so the boot never stalls.

signal finished

const VIDEO := "res://assets/video/studio_intro.ogv"
const POSTER := "res://assets/art/ui/boot_splash.png"
const SKIP_AFTER := 1.0
const START_TIMEOUT := 2.0
const RATIO := 1280.0 / 720.0

var _player: VideoStreamPlayer
var _poster: TextureRect
var _hint: Label
var _time := 0.0
var _done := false
var _started := false
var _fallback := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var black := ColorRect.new()
	black.color = Color.BLACK
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(black)
	var fit := AspectRatioContainer.new()
	fit.set_anchors_preset(Control.PRESET_FULL_RECT)
	fit.ratio = RATIO
	fit.stretch_mode = AspectRatioContainer.STRETCH_FIT
	fit.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fit)
	var stream: VideoStream = load(VIDEO) if ResourceLoader.exists(VIDEO) else null
	if stream:
		_player = VideoStreamPlayer.new()
		_player.stream = stream
		_player.expand = true
		_player.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_player.finished.connect(_finish)
		fit.add_child(_player)
		_player.play()
	else:
		_start_fallback()
	_hint = Label.new()
	_hint.text = tr("TAP_SKIP")
	_hint.add_theme_font_size_override("font_size", 16)
	_hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 24)
	_hint.modulate.a = 0.0
	add_child(_hint)


func _process(delta: float) -> void:
	if _done:
		return
	_time += delta
	if _player and not _fallback:
		if _player.is_playing() and _player.stream_position > 0.05:
			_started = true
		elif not _started and _time > START_TIMEOUT:
			print("[intro] video did not start, showing still")
			_player.queue_free()
			_player = null
			_start_fallback()
	if _time > SKIP_AFTER and _hint.modulate.a < 1.0:
		_hint.modulate.a = minf(1.0, _hint.modulate.a + delta * 2.0)


func _start_fallback() -> void:
	_fallback = true
	_time = 0.0
	_poster = TextureRect.new()
	if ResourceLoader.exists(POSTER):
		_poster.texture = load(POSTER)
	_poster.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_poster.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_poster.set_anchors_preset(Control.PRESET_FULL_RECT)
	_poster.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_poster.modulate.a = 0.0
	add_child(_poster)
	move_child(_poster, 1)
	var tw := create_tween()
	tw.tween_property(_poster, "modulate:a", 1.0, 0.5)
	tw.tween_interval(1.6)
	tw.tween_property(_poster, "modulate:a", 0.0, 0.5)
	tw.tween_callback(_finish)


func _gui_input(e: InputEvent) -> void:
	if _time > SKIP_AFTER and (e is InputEventMouseButton or e is InputEventScreenTouch) and e.is_pressed():
		accept_event()
		skip()


func _unhandled_key_input(e: InputEvent) -> void:
	if _time > SKIP_AFTER and e.is_pressed() and not e.is_echo():
		get_viewport().set_input_as_handled()
		skip()


func skip() -> void:
	if _done:
		return
	_done = true
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.25)
	tw.tween_callback(func() -> void:
		if _player:
			_player.stop()
		finished.emit())


func _finish() -> void:
	if _done:
		return
	_done = true
	finished.emit()
