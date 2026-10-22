extends Node
## A short, skippable discovery sequence for rare places: letterbox + camera move (CutscenePlayer), a music swell,
## a title and a line of text that fade in over the view, an optional "birds take off" callback, then control goes
## back. Reusable: the Hidden Vale uses the long fly-out, scenic vistas use the 5 s pan.
##
##   var v := preload("res://scripts/cinematic/discovery_vista.gd").new()
##   world.add_child(v)
##   v.finished.connect(func(skipped: bool) -> void: ...)
##   v.play({"shots": [...CutscenePlayer shots...], "title": "The Hidden Vale", "line": "Untouched. ...",
##           "music": "res://assets/audio/region1/music/mus_r1_forest_glade.ogg", "freeze": [player], "hide": [hud],
##           "events": [[4.0, Callable]]})
## Def keys: shots (required), title, line, kicker (small line above the title), title_at (s, default 3.5),
## music (path) + music_db, freeze (nodes whose processing is paused), hide (CanvasItems hidden), events ([[t, Callable]]),
## hour (time of day to hold, optional, handled by the caller through shot "time"), small (true = compact title, no kicker).

signal finished(skipped: bool)

const TITLE_FADE := 1.3
const TEXT := Color("f6f1e7")
const ACCENT := Color("f0c060")

var cut: CutscenePlayer
var running := false
var def: Dictionary = {}

var _layer: CanvasLayer
var _title: Label
var _kicker: Label
var _line: Label
var _music: AudioStreamPlayer
var _frozen: Array = []
var _hidden: Array = []
var _events: Array = []
var _duck_db := 0.0
var _music_bus := -1
var _total := 0.0
var _skipped := false


## Shot list helpers ---------------------------------------------------------------------------------------------

## One shot: camera flies from `from` to `to` looking from `look` to `look_to`.
static func shot(from: Vector3, to: Vector3, look: Vector3, look_to: Vector3, duration: float, fov := 55.0, fov_to := -1.0, extra := {}) -> Dictionary:
	var s := {"from": from, "to": to, "look": look, "look_to": look_to, "duration": duration, "fov": fov,
		"fov_to": fov if fov_to < 0.0 else fov_to, "ease": "smooth"}
	s.merge(extra, true)
	return s


## A short pan for scenic vistas: a slow sweep from `look` to `look_to` from a fixed eye point.
static func pan(eye: Vector3, look: Vector3, look_to: Vector3, duration := 5.0) -> Array:
	return [shot(eye, eye + Vector3(0, 1.2, 0), look, look_to, duration, 58.0, 50.0, {"fade_in": 0.6, "fade_out": 0.8})]


## Playback --------------------------------------------------------------------------------------------------------

func play(p_def: Dictionary) -> void:
	def = p_def
	var shots: Array = def.get("shots", [])
	if shots.is_empty() or running:
		finished.emit(false)
		return
	running = true
	_total = CutscenePlayer.total_duration(shots)
	cut = CutscenePlayer.new()
	add_child(cut)
	for n: Variant in def.get("freeze", []):
		if n is Node and is_instance_valid(n):
			_frozen.append([n, (n as Node).process_mode])
			(n as Node).process_mode = Node.PROCESS_MODE_DISABLED
	for n: Variant in def.get("hide", []):
		if n is CanvasItem and is_instance_valid(n):
			_hidden.append([n, (n as CanvasItem).visible])
			(n as CanvasItem).visible = false
	_events = (def.get("events", []) as Array).duplicate()
	_events.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	cut.shot_started.connect(func(i: int, s: Dictionary) -> void:
		if def.has("on_shot") and def["on_shot"] is Callable:
			(def["on_shot"] as Callable).call(i, s))
	cut.finished.connect(_end.bind(false))
	cut.skipped.connect(func() -> void: _skipped = true)
	_build_title()
	_start_music()
	cut.play(shots)
	set_process(true)


func _process(_delta: float) -> void:
	if not running or cut == null:
		return
	var t := cut.elapsed
	while not _events.is_empty() and float(_events[0][0]) <= t:
		var ev: Array = _events.pop_front()
		if ev[1] is Callable:
			(ev[1] as Callable).call()
	_update_title(t)
	_update_music(t)


## Test helper: advance by `dt` without the scene tree's process loop.
func advance(dt: float) -> void:
	if cut != null:
		cut.advance(dt)
	_process(dt)


func _end(skipped: bool) -> void:
	if not running:
		return
	running = false
	skipped = skipped or _skipped
	for pair: Array in _frozen:
		if is_instance_valid(pair[0]):
			(pair[0] as Node).process_mode = pair[1]
	for pair: Array in _hidden:
		if is_instance_valid(pair[0]):
			(pair[0] as CanvasItem).visible = pair[1]
	_frozen.clear()
	_hidden.clear()
	if _layer:
		_layer.queue_free()
	_stop_music()
	if cut:
		cut.queue_free()
		cut = null
	set_process(false)
	finished.emit(skipped)
	queue_free()


## Title card ---------------------------------------------------------------------------------------------------------

func _build_title() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 91
	add_child(_layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(root)
	var box := VBoxContainer.new()
	box.anchor_left = 0.08
	box.anchor_right = 0.92
	box.anchor_top = 0.26
	box.anchor_bottom = 0.56
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 8)
	root.add_child(box)
	var tracked := FontVariation.new()
	tracked.base_font = ThemeDB.fallback_font
	tracked.spacing_glyph = 7
	tracked.variation_embolden = 0.5
	var small := bool(def.get("small", false))
	_kicker = _label(box, String(def.get("kicker", "")).to_upper(), 15, ACCENT, tracked)
	_title = _label(box, String(def.get("title", "")).to_upper() if not small else String(def.get("title", "")), 54 if not small else 30, TEXT, tracked)
	_line = _label(box, String(def.get("line", "")), 22 if not small else 18, Color(TEXT, 0.92), null)
	_line.add_theme_font_size_override("font_size", 22 if not small else 18)
	for l: Label in [_kicker, _title, _line]:
		l.modulate.a = 0.0


func _label(parent: Control, text: String, size: int, color: Color, font: Font) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if font:
		l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("outline_size", 8)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	l.add_theme_constant_override("shadow_offset_y", 2)
	parent.add_child(l)
	return l


func _update_title(t: float) -> void:
	var at := float(def.get("title_at", 3.5))
	var out_start := _total - 2.2
	var fade_out := 1.0 - clampf((t - out_start) / 1.2, 0.0, 1.0)
	_kicker.modulate.a = clampf((t - at) / TITLE_FADE, 0.0, 1.0) * fade_out
	_title.modulate.a = clampf((t - at - 0.5) / TITLE_FADE, 0.0, 1.0) * fade_out
	_line.modulate.a = clampf((t - at - 2.2) / TITLE_FADE, 0.0, 1.0) * fade_out


## Music swell -------------------------------------------------------------------------------------------------------

func _start_music() -> void:
	var path := String(def.get("music", ""))
	if path == "" or not ResourceLoader.exists(path):
		return
	var stream := load(path) as AudioStream
	if stream == null:
		return
	_music = AudioStreamPlayer.new()
	_music.stream = stream
	_music.bus = &"Master"
	_music.volume_db = -40.0
	_music.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_music)
	_music.play()
	_music_bus = AudioServer.get_bus_index("Music")
	if _music_bus >= 0:
		_duck_db = AudioServer.get_bus_volume_db(_music_bus)


func _update_music(t: float) -> void:
	if _music == null:
		return
	var peak := float(def.get("music_db", -4.0))
	var swell := clampf(t / 5.0, 0.0, 1.0)
	var fade := clampf((_total - t) / 2.5, 0.0, 1.0)
	_music.volume_db = lerpf(-40.0, peak, swell * swell) - (1.0 - fade) * 40.0
	if _music_bus >= 0:
		AudioServer.set_bus_volume_db(_music_bus, _duck_db - 14.0 * minf(swell * 2.0, 1.0) * fade)


func _stop_music() -> void:
	if _music_bus >= 0:
		AudioServer.set_bus_volume_db(_music_bus, _duck_db)
	if _music == null:
		return
	var m := _music
	_music = null
	var tw := m.create_tween()
	tw.tween_property(m, "volume_db", -60.0, 1.5)
	tw.tween_callback(m.queue_free)
	m.reparent(get_tree().root) if is_inside_tree() else m.queue_free()
