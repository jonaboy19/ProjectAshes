extends "res://scripts/ui/frontend/screen.gd"
## In-game pause menu over a blurred, darkened game. Pauses the tree while open.
##   PauseMenu.open(hud_or_any_node)      (Esc / pause button)
## Resume, Save Game, Load Game, Settings, Photo Mode, Exit to Main Menu.

const Flow := preload("res://scripts/ui/frontend/flow.gd")
const SlotScreen := preload("res://scripts/ui/frontend/slot_screen.gd")
const SettingsScreen := preload("res://scripts/ui/frontend/settings_screen.gd")

const BLUR_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float lod = 3.0;
uniform float darken = 0.55;
void fragment() {
	vec3 c = textureLod(screen_tex, SCREEN_UV, lod).rgb;
	c = mix(c, vec3(dot(c, vec3(0.3, 0.55, 0.15))), 0.25);
	COLOR = vec4(c * darken * vec3(1.0, 0.95, 0.88), 1.0);
}
"""

var host: Node
var _was_paused := false
var _menu: VBoxContainer
var _panel: Control
var _photo_cb := Callable()


static func open(parent: Node, photo_cb := Callable()) -> Control:
	var existing := parent.get_node_or_null("PauseMenu")
	if existing:
		return existing
	var s: Variant = load("res://scripts/ui/frontend/pause_menu.gd").new()
	s.name = "PauseMenu"
	s.host = parent
	s._photo_cb = photo_cb
	parent.add_child(s)
	return s


func _ready() -> void:
	_was_paused = get_tree().paused
	get_tree().paused = true
	var blur := ColorRect.new()
	blur.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	blur.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = BLUR_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	blur.material = mat
	add_child(blur)
	add_child(FE.fade_rect(true, 0.55, 0.5))
	_panel = PanelContainer.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(380, 0)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_panel.add_theme_stylebox_override("panel", AF.panel(Color(0.03, 0.028, 0.025, 0.88), AF.GOLD, 4, 22))
	add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_panel.add_child(v)
	var t := Label.new()
	t.text = "PAUSED"
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_override("font", AF.wfont(700))
	t.add_theme_font_size_override("font_size", 30)
	t.add_theme_color_override("font_color", AF.TEXT)
	v.add_child(t)
	v.add_child(AF.separator())
	_menu = VBoxContainer.new()
	_menu.add_theme_constant_override("separation", 2)
	v.add_child(_menu)
	_menu.add_child(FE.menu_row("Resume Game", resume, 20, 50))
	_menu.add_child(FE.menu_row("Save Game", func() -> void: SlotScreen.open(self, "save", Callable(), true), 20, 50))
	_menu.add_child(FE.menu_row("Load Game", _load, 20, 50))
	_menu.add_child(FE.menu_row("Settings", func() -> void: SettingsScreen.open(self, true), 20, 50))
	var photo := FE.menu_row("Photo Mode", _photo, 20, 50)
	photo.disabled = not (_photo_cb.is_valid() or (host and host.has_method("open_photo_mode")))
	_menu.add_child(photo)
	_menu.add_child(FE.menu_row("Exit to Main Menu", _exit, 20, 50))
	_panel.position.x = 0
	FE.fade_in(self, 0.18)
	(_menu.get_child(0) as Control).call_deferred("grab_focus")
	# Left-align the panel like the template (a menu column on the left third).
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	_panel.offset_left = 90
	_panel.offset_right = 90 + 380
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH


func _load() -> void:
	var s := SlotScreen.open(self, "load", Callable(), true)
	s.connect("loaded", func(_id: String) -> void: resume())


func _photo() -> void:
	resume()
	if _photo_cb.is_valid():
		_photo_cb.call()
	elif host and host.has_method("open_photo_mode"):
		host.call_deferred("open_photo_mode")


func _exit() -> void:
	FE.confirm(self, "Return to the main menu?\nUnsaved progress will be lost.", func() -> void:
		Flow.exit_to_menu(get_tree()), "Exit")


func resume() -> void:
	get_tree().paused = _was_paused
	FE.play("close")
	queue_free()


func back() -> void:
	resume()
