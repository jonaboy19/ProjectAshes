extends Node
## App-level services (autoload `App`) that the settings screen and phone lifecycle need:
##  - applies the saved language (TranslationServer, res://locale/strings.csv), text size is left to
##    settings_store; colour-blind assist (a full-screen daltonisation filter), the 3D resolution scale,
##    and creates the "Voice" audio bus;
##  - caches the control settings game code reads every frame (camera speed, invert, stick size, vibration);
##  - phone lifecycle: silences the game while the app is in the background, opens the pause menu when the
##    player comes back, and turns the Android back button into the normal "cancel" action.
## Save-on-background lives in scripts/sim/save_manager.gd (autosave on NOTIFICATION_APPLICATION_PAUSED).

const SS := preload("res://scripts/ui/frontend/settings_store.gd")
const LANGS := ["en", "nl"]

## Camera drag multiplier (x, y: negative when inverted), stick scale, vibration on/off, subtitles on/off.
var look_scale := Vector2.ONE
var joystick_scale := 1.0
var vibration := true
var subtitles := true

var _cb_layer: CanvasLayer
var _cb_mat: ShaderMaterial

const CB_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform int mode = 1;
// Daltonisation: simulate the missing cone, then move the lost colour difference into channels that still work.
void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	mat3 sim = mat3(1.0);
	if (mode == 1) sim = mat3(vec3(0.567, 0.558, 0.0), vec3(0.433, 0.442, 0.242), vec3(0.0, 0.0, 0.758));
	else if (mode == 2) sim = mat3(vec3(0.625, 0.7, 0.0), vec3(0.375, 0.3, 0.3), vec3(0.0, 0.0, 0.7));
	else if (mode == 3) sim = mat3(vec3(0.95, 0.0, 0.0), vec3(0.05, 0.433, 0.475), vec3(0.0, 0.567, 0.525));
	vec3 err = c - sim * c;
	vec3 shift = vec3(0.0, err.r * 0.7, err.r * 0.7 + err.g);
	if (mode == 3) shift = vec3(err.b * 0.7, err.b * 0.7, 0.0);
	COLOR = vec4(clamp(c + shift, 0.0, 1.0), 1.0);
}
"""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().set_auto_accept_quit(true)
	if AudioServer.get_bus_index("Voice") == -1:
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, "Voice")
		AudioServer.set_bus_send(i, "Master")
	for lang: String in LANGS:
		var p := "res://locale/strings.%s.translation" % lang
		if ResourceLoader.exists(p):
			TranslationServer.add_translation(load(p))
	refresh()


## Re-read (or take) the settings and apply what belongs here. Called at start and after "Apply".
func refresh(vals := {}) -> void:
	if vals.is_empty():
		vals = SS.read_all(get_tree())
	var sens := lerpf(0.4, 1.6, clampf(float(vals.get("cam_sens", 50)) / 100.0, 0.0, 1.0))
	look_scale = Vector2(sens, sens * (-1.0 if bool(vals.get("invert_y", false)) else 1.0))
	joystick_scale = lerpf(0.6, 1.4, clampf(float(vals.get("joystick_size", 50)) / 100.0, 0.0, 1.0))
	vibration = bool(vals.get("vibration", true))
	subtitles = bool(vals.get("subtitles", true))
	TranslationServer.set_locale(LANGS[clampi(int(vals.get("language", 0)), 0, LANGS.size() - 1)])
	_colorblind(int(vals.get("colorblind", 0)))
	Quality.set_render_scale(lerpf(0.5, 1.0, clampf(float(vals.get("render_scale", 100)) / 100.0, 0.0, 1.0)))


func vibrate(ms := 40) -> void:
	if vibration and (OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")):
		Input.vibrate_handheld(ms)


func _colorblind(mode: int) -> void:
	if mode <= 0:
		if _cb_layer:
			_cb_layer.visible = false
		return
	if _cb_layer == null:
		_cb_layer = CanvasLayer.new()
		_cb_layer.layer = 120
		add_child(_cb_layer)
		var r := ColorRect.new()
		r.set_anchors_preset(Control.PRESET_FULL_RECT)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sh := Shader.new()
		sh.code = CB_SHADER
		_cb_mat = ShaderMaterial.new()
		_cb_mat.shader = sh
		r.material = _cb_mat
		_cb_layer.add_child(r)
	_cb_mat.set_shader_parameter("mode", mode)
	_cb_layer.visible = true


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED:
			# Phone locked or app switched away: go quiet (the autosave is SaveManager's job).
			AudioServer.set_bus_mute(0, true)
		NOTIFICATION_APPLICATION_RESUMED:
			AudioServer.set_bus_mute(0, SS.get_value("vol_master") <= 0)
			_open_pause_if_playing()
		NOTIFICATION_WM_GO_BACK_REQUEST:
			# Android back button: behave exactly like Esc so every open screen closes the usual way,
			# and the HUD opens the pause menu when nothing is open.
			for pressed in [true, false]:
				var ev := InputEventAction.new()
				ev.action = "ui_cancel"
				ev.pressed = pressed
				Input.parse_input_event(ev)


func _open_pause_if_playing() -> void:
	var scene := get_tree().current_scene
	var hud: Variant = scene.get("hud") if scene else null
	if hud is Object and is_instance_valid(hud) and (hud as Object).has_method("open_pause"):
		(hud as Object).call("open_pause")
