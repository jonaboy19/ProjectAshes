class_name HUD
extends CanvasLayer
## Mobile HUD: joystick, camera drag area, action buttons, quest tracker,
## health, toasts, dialogue box and the title card. Built in code for now;
## swap to a themed .tscn when the real UI art arrives.

var player: Player
var _controls: Control
var _joystick: VirtualJoystick
var _quest_title: Label
var _quest_step: Label
var _health: ProgressBar
var _toast: Label
var _toast_tween: Tween
var _interact_button: TouchScreenButton
var _interact_label: Label
var _buttons: Array[TouchScreenButton] = []
var _dialogue_panel: PanelContainer
var _speaker: Label
var _line: Label
var _line_tween: Tween
var _title: Control

const INK := Color("1d1a1f")
const PARCHMENT := Color("f3e6cf")
const EMBER := Color("e0693a")


func _init(p: Player) -> void:
	player = p
	layer = 10


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_controls = Control.new()
	_controls.set_anchors_preset(Control.PRESET_FULL_RECT)
	_controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_controls)
	_build_look_area()
	_build_joystick()
	_build_buttons()
	_build_status(root)
	_build_toast(root)
	_build_dialogue(root)
	_build_title(root)

	player.health_changed.connect(_on_health_changed)
	player.interact_target_changed.connect(_on_target_changed)
	player.blessing_denied.connect(func() -> void: GameState.toast("You reach for a blessing... nothing answers."))
	Quests.quest_updated.connect(_on_quest_updated)
	GameState.toast_requested.connect(show_toast)
	Dialogue.dialogue_started.connect(func(_id: String) -> void: _set_dialogue_mode(true))
	Dialogue.dialogue_ended.connect(func(_id: String) -> void: _set_dialogue_mode(false))
	Dialogue.line_shown.connect(_on_line)
	get_viewport().size_changed.connect(_layout_buttons)
	_layout_buttons()


# --- Controls -----------------------------------------------------------------

func _build_look_area() -> void:
	var look := Control.new()
	look.anchor_left = 0.4
	look.anchor_right = 1.0
	look.anchor_bottom = 1.0
	look.mouse_filter = Control.MOUSE_FILTER_STOP
	look.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventScreenDrag:
			player.add_camera_input(event.relative))
	_controls.add_child(look)


func _build_joystick() -> void:
	_joystick = VirtualJoystick.new()
	_joystick.anchor_right = 0.4
	_joystick.anchor_bottom = 1.0
	_joystick.anchor_top = 0.3
	_joystick.moved.connect(func(v: Vector2) -> void: player.touch_move = v)
	_controls.add_child(_joystick)


func _build_buttons() -> void:
	_buttons.append(_make_button("attack", "Strike", 120, EMBER))
	_buttons.append(_make_button("blessing", "Bless", 88, Color("7e6bd6")))
	_buttons.append(_make_button("dodge", "Dodge", 80, Color("4d7f8f")))
	_interact_button = _make_button("interact", "Talk", 96, Color("d9a441"))
	_interact_label = _interact_button.get_child(0)
	_interact_button.visible = false


func _make_button(action: String, text: String, diameter: int, color: Color) -> TouchScreenButton:
	var button := TouchScreenButton.new()
	button.action = action
	button.texture_normal = _circle_texture(diameter, color.darkened(0.15))
	button.texture_pressed = _circle_texture(diameter, color.lightened(0.2))
	var label := Label.new()
	label.text = text
	label.size = Vector2(diameter, diameter)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 20 if diameter > 90 else 17)
	label.add_theme_color_override("font_outline_color", INK)
	label.add_theme_constant_override("outline_size", 6)
	button.add_child(label)
	_controls.add_child(button)
	return button


func _layout_buttons() -> void:
	var s := get_viewport().get_visible_rect().size
	# Thumb arc in the bottom-right corner.
	_buttons[0].position = s - Vector2(170, 170)
	_buttons[1].position = s - Vector2(290, 130)
	_buttons[2].position = s - Vector2(140, 285)
	_interact_button.position = s - Vector2(290, 260)


static func _circle_texture(diameter: int, color: Color) -> ImageTexture:
	var img := Image.create(diameter, diameter, false, Image.FORMAT_RGBA8)
	var r := diameter / 2.0
	for y in diameter:
		for x in diameter:
			var d := Vector2(x + 0.5 - r, y + 0.5 - r).length()
			if d <= r:
				var edge := clampf(r - d, 0.0, 1.0)
				var c := color if d < r - 4.0 else color.lightened(0.45)
				c.a = 0.82 * edge
				img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


func _on_target_changed(target: Interactable) -> void:
	_interact_button.visible = target != null
	if target:
		_interact_label.text = target.prompt


# --- Status -------------------------------------------------------------------

func _build_status(root: Control) -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(20, 18)
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.08, 0.07, 0.09, 0.62)))
	root.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)
	var name_label := Label.new()
	name_label.text = "SUGO WATARO"
	name_label.add_theme_font_size_override("font_size", 15)
	name_label.add_theme_color_override("font_color", Color("e9d7b6"))
	box.add_child(name_label)
	_health = ProgressBar.new()
	_health.custom_minimum_size = Vector2(260, 14)
	_health.show_percentage = false
	_health.max_value = player.max_health
	_health.value = player.health
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("c9433a")
	fill.set_corner_radius_all(4)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.5)
	bg.set_corner_radius_all(4)
	_health.add_theme_stylebox_override("fill", fill)
	_health.add_theme_stylebox_override("background", bg)
	box.add_child(_health)
	var sep := HSeparator.new()
	box.add_child(sep)
	_quest_title = Label.new()
	_quest_title.add_theme_font_size_override("font_size", 17)
	_quest_title.add_theme_color_override("font_color", Color("f0b25a"))
	box.add_child(_quest_title)
	_quest_step = Label.new()
	_quest_step.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_quest_step.custom_minimum_size = Vector2(300, 0)
	_quest_step.add_theme_font_size_override("font_size", 15)
	_quest_step.add_theme_color_override("font_color", PARCHMENT)
	box.add_child(_quest_step)


func _on_health_changed(current: int, maximum: int) -> void:
	_health.max_value = maximum
	_health.value = current


func _on_quest_updated(_id: String, title: String, step: String) -> void:
	_quest_title.text = "◆ " + title
	_quest_step.text = step


func _build_toast(root: Control) -> void:
	_toast = Label.new()
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.anchor_left = 0.2
	_toast.anchor_right = 0.8
	_toast.offset_top = 90
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast.add_theme_font_size_override("font_size", 26)
	_toast.add_theme_color_override("font_color", PARCHMENT)
	_toast.add_theme_color_override("font_outline_color", INK)
	_toast.add_theme_constant_override("outline_size", 10)
	_toast.modulate.a = 0.0
	root.add_child(_toast)


func show_toast(text: String, hold := 2.4) -> void:
	_toast.text = text
	if _toast_tween:
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast.modulate.a = 0.0
	_toast_tween.tween_property(_toast, "modulate:a", 1.0, 0.25)
	_toast_tween.tween_interval(hold)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.5)


# --- Dialogue -----------------------------------------------------------------

func _build_dialogue(root: Control) -> void:
	var catcher := Control.new()
	catcher.set_anchors_preset(Control.PRESET_FULL_RECT)
	catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	catcher.visible = false
	catcher.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventScreenTouch and event.pressed:
			_on_dialogue_tap())
	root.add_child(catcher)
	_dialogue_panel = PanelContainer.new()
	_dialogue_panel.anchor_left = 0.12
	_dialogue_panel.anchor_right = 0.88
	_dialogue_panel.anchor_top = 1.0
	_dialogue_panel.anchor_bottom = 1.0
	_dialogue_panel.offset_top = -200
	_dialogue_panel.offset_bottom = -28
	_dialogue_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := _panel_style(Color(0.09, 0.07, 0.08, 0.88))
	style.border_color = Color("b9894f")
	style.set_border_width_all(2)
	_dialogue_panel.add_theme_stylebox_override("panel", style)
	catcher.add_child(_dialogue_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_dialogue_panel.add_child(box)
	_speaker = Label.new()
	_speaker.add_theme_font_size_override("font_size", 22)
	_speaker.add_theme_color_override("font_color", Color("f0b25a"))
	box.add_child(_speaker)
	_line = Label.new()
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_line.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_line.add_theme_font_size_override("font_size", 22)
	_line.add_theme_color_override("font_color", PARCHMENT)
	box.add_child(_line)
	var hint := Label.new()
	hint.text = "tap to continue ▸"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	box.add_child(hint)


func _set_dialogue_mode(active: bool) -> void:
	_dialogue_panel.get_parent().visible = active
	_controls.visible = not active
	player.touch_move = Vector2.ZERO


func _on_line(speaker: String, text: String) -> void:
	_speaker.text = speaker
	_line.text = text
	_line.visible_ratio = 0.0
	if _line_tween:
		_line_tween.kill()
	_line_tween = create_tween()
	_line_tween.tween_property(_line, "visible_ratio", 1.0, text.length() * 0.022)


func _on_dialogue_tap() -> void:
	if _line.visible_ratio < 1.0:
		_line_tween.kill()
		_line.visible_ratio = 1.0
	else:
		Dialogue.advance()


func _unhandled_input(event: InputEvent) -> void:
	if Dialogue.is_active() and event.is_action_pressed("interact"):
		_on_dialogue_tap()


# --- Title card & helpers -------------------------------------------------------

func _build_title(root: Control) -> void:
	_title = ColorRect.new()
	(_title as ColorRect).color = Color(0.05, 0.04, 0.05, 0.92)
	_title.set_anchors_preset(Control.PRESET_FULL_RECT)
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_title)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	_title.add_child(box)
	var title := Label.new()
	title.text = "RISING ASHES"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 84)
	title.add_theme_color_override("font_color", EMBER)
	title.add_theme_color_override("font_outline_color", Color("3a1a10"))
	title.add_theme_constant_override("outline_size", 14)
	box.add_child(title)
	var sub := Label.new()
	sub.text = "Aramori  ·  Vertical Slice"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 26)
	sub.add_theme_color_override("font_color", PARCHMENT)
	box.add_child(sub)


func play_title(hold := 2.2) -> void:
	_title.visible = true
	_title.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_interval(hold)
	tween.tween_property(_title, "modulate:a", 0.0, 1.0)
	tween.tween_callback(func() -> void: _title.visible = false)


func hide_title() -> void:
	_title.visible = false


func set_controls_visible(value: bool) -> void:
	_controls.visible = value


static func _panel_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(10)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	return style
