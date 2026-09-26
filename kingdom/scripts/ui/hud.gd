class_name HUD
extends CanvasLayer
## Full-resolution UI drawn over the low-resolution pixel render: stats, orders,
## touch controls and messages. Crisp text on top of chunky pixels.

const INK := Color("1a1420")
const GOLD := Color("f0c060")
const PAPER := Color("efe3c8")

var player: Player
var controls: Control
var _stats: Label
var _where: Label
var _perf: Label
var _danger: Label
var _health: ProgressBar
var _stamina: ProgressBar
var _toast: Label
var _toast_tween: Tween
var _interact: TouchScreenButton
var _interact_label: Label
var _order_buttons: Array[TouchScreenButton] = []
var _buttons: Dictionary = {}
var _loading: ColorRect
var _loading_label: Label
var _needs: Label
var _menu: PanelContainer
var _menu_source: Callable
var _pack_button: TouchScreenButton


func _init(p: Player) -> void:
	player = p
	layer = 10


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	controls = Control.new()
	controls.set_anchors_preset(Control.PRESET_FULL_RECT)
	controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(controls)

	var look := Control.new()
	look.anchor_left = 0.4
	look.anchor_right = 1.0
	look.anchor_bottom = 1.0
	look.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventScreenDrag:
			player.add_look(e.relative))
	controls.add_child(look)
	var stick := VirtualJoystick.new()
	stick.anchor_right = 0.4
	stick.anchor_top = 0.3
	stick.anchor_bottom = 1.0
	stick.moved.connect(func(v: Vector2) -> void: player.touch_move = v)
	controls.add_child(stick)

	_buttons["attack"] = _button("attack", "Strike", 112, Color("c9533c"))
	_buttons["dodge"] = _button("dodge", "Dodge", 80, Color("4d8f86"))
	_buttons["block"] = _button("block", "Block", 80, Color("7a6a9c"))
	_buttons["view"] = _button("view_cycle", "1st/3rd", 70, Color("4d6f8f"))
	_buttons["zoom_out"] = _button("zoom_out", "Zoom -", 70, Color("4d6f8f"))
	_buttons["zoom_in"] = _button("zoom_in", "Zoom +", 70, Color("4d6f8f"))
	_interact = _button("interact", "Talk", 90, Color("c9a24a"))
	_pack_button = _button("journal", "Pack", 70, Color("8a6a3a"))
	_interact_label = _interact.get_child(0)
	_interact.visible = false
	for pair in [["order_follow", "Follow"], ["order_hold", "Hold"], ["order_charge", "Charge!"]]:
		var b := _button(pair[0], pair[1], 76, Color("5b7d4a"))
		b.visible = false
		_order_buttons.append(b)

	_stats = _label(root, 18, PAPER)
	_stats.position = Vector2(18, 14)
	_health = ProgressBar.new()
	_health.position = Vector2(18, 134)
	_health.custom_minimum_size = Vector2(220, 12)
	_health.show_percentage = false
	_health.max_value = player.max_health
	_health.value = player.health
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("c9433a")
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.55)
	bg.border_color = INK
	bg.set_border_width_all(2)
	_health.add_theme_stylebox_override("fill", fill)
	_health.add_theme_stylebox_override("background", bg)
	root.add_child(_health)
	_stamina = _bar(root, Vector2(18, 152), Color("e0b84a"), 8)
	_stamina.max_value = Player.MAX_STAMINA
	_stamina.value = Player.MAX_STAMINA
	_needs = _label(root, 15, PAPER)
	_needs.position = Vector2(18, 164)
	_where = _label(root, 18, PAPER)
	_where.anchor_left = 1.0
	_where.anchor_right = 1.0
	_where.offset_left = -520
	_where.offset_right = -112
	_where.offset_top = 14
	_where.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_perf = _label(root, 13, Color(1, 1, 1, 0.7))
	_perf.anchor_left = 0.5
	_perf.anchor_right = 0.5
	_perf.offset_left = -300
	_perf.offset_right = 300
	_perf.offset_top = 8
	_perf.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_danger = _label(root, 16, PAPER)
	_danger.anchor_left = 1.0
	_danger.anchor_right = 1.0
	_danger.offset_left = -520
	_danger.offset_right = -112
	_danger.offset_top = 96
	_danger.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_toast = _label(root, 24, PAPER)
	_toast.anchor_left = 0.15
	_toast.anchor_right = 0.85
	_toast.offset_top = 120
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast.modulate.a = 0.0

	_menu = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.06, 0.1, 0.92)
	style.border_color = GOLD.darkened(0.3)
	style.set_border_width_all(3)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(18)
	_menu.add_theme_stylebox_override("panel", style)
	_menu.anchor_left = 0.5
	_menu.anchor_right = 0.5
	_menu.anchor_top = 0.5
	_menu.anchor_bottom = 0.5
	_menu.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_menu.grow_vertical = Control.GROW_DIRECTION_BOTH
	_menu.custom_minimum_size = Vector2(520, 0)
	_menu.visible = false
	root.add_child(_menu)

	_loading = ColorRect.new()
	_loading.color = INK
	_loading.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(_loading)
	_loading_label = _label(_loading, 30, GOLD)
	_loading_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_loading_label.text = "Forging the realm..."

	player.stamina_changed.connect(func(c: float, _m: float) -> void: _stamina.value = c)
	player.health_changed.connect(func(c: int, m: int) -> void:
		_health.max_value = m
		_health.value = c)
	Game.toast.connect(show_toast)
	get_viewport().size_changed.connect(_layout)
	_layout()


func hide_loading() -> void:
	_loading.visible = false


func set_loading_text(text: String) -> void:
	_loading_label.text = text


func _bar(parent: Control, pos: Vector2, color: Color, height: int) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.position = pos
	bar.custom_minimum_size = Vector2(220, height)
	bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.55)
	bg.border_color = INK
	bg.set_border_width_all(2)
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", bg)
	parent.add_child(bar)
	return bar


func _label(parent: Control, size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", INK)
	l.add_theme_constant_override("outline_size", 8)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _button(action: String, text: String, size: int, color: Color) -> TouchScreenButton:
	var b := TouchScreenButton.new()
	b.action = action
	b.texture_normal = _pixel_square(size, color)
	b.texture_pressed = _pixel_square(size, color.lightened(0.25))
	var l := Label.new()
	l.text = text
	l.size = Vector2(size, size)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 17 if size > 80 else 14)
	l.add_theme_color_override("font_outline_color", INK)
	l.add_theme_constant_override("outline_size", 6)
	b.add_child(l)
	controls.add_child(b)
	return b


## Chunky bevelled square in the pixel-art style.
static func _pixel_square(size: int, color: Color) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := color
	c.a = 0.85
	img.fill(c)
	var edge := 4
	img.fill_rect(Rect2i(0, 0, size, edge), color.lightened(0.3))
	img.fill_rect(Rect2i(0, 0, edge, size), color.lightened(0.3))
	img.fill_rect(Rect2i(0, size - edge, size, edge), color.darkened(0.45))
	img.fill_rect(Rect2i(size - edge, 0, edge, size), color.darkened(0.45))
	for corner in [Vector2i(0, 0), Vector2i(size - edge, 0), Vector2i(0, size - edge), Vector2i(size - edge, size - edge)]:
		img.fill_rect(Rect2i(corner, Vector2i(edge, edge)), Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(img)


func _layout() -> void:
	var s := get_viewport().get_visible_rect().size
	_buttons["attack"].position = s - Vector2(150, 150)
	_interact.position = s - Vector2(150, 270)
	_buttons["dodge"].position = s - Vector2(250, 115)
	_buttons["block"].position = s - Vector2(250, 215)
	_buttons["view"].position = Vector2(s.x - 100, 230)
	_pack_button.position = Vector2(s.x - 100, 310)
	_buttons["zoom_in"].position = Vector2(s.x - 100, 70)
	_buttons["zoom_out"].position = Vector2(s.x - 100, 150)
	for i in _order_buttons.size():
		_order_buttons[i].position = Vector2(s.x * 0.5 - 125 + i * 88, s.y - 96)


func show_toast(text: String) -> void:
	_toast.text = text
	if _toast_tween:
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast.modulate.a = 0.0
	_toast_tween.tween_property(_toast, "modulate:a", 1.0, 0.2)
	_toast_tween.tween_interval(3.2)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.5)


func update_status(soldiers: int, order_name: String, target: Node3D, perf: String) -> void:
	var c := Life.careers
	var job_line := "Unemployed"
	if c.is_employed():
		var duty := ""
		if c.is_on_shift(WorldSim.time_of_day):
			var p2 := Vector2(player.global_position.x, player.global_position.z)
			duty = "  · ON DUTY" if c.at_post(p2) else "  · AWAY FROM POST"
		job_line = "%s, %s%s" % [c.player["seat"], c.player_org()["name"], duty]
	_stats.text = "%s\n%s\nGold  %d   Merit  %d\nSoldiers  %d / %d%s" % [Game.rank_name().to_upper(), job_line, Game.gold,
		Game.merit, soldiers, Game.max_soldiers(), ("  ·  " + order_name) if soldiers > 0 else ""]
	var n := Life.needs
	_needs.text = "%s  ·  %s" % [n.hunger_label(), n.rest_label()]
	_needs.add_theme_color_override("font_color", PAPER if n.food >= 25.0 and n.rest >= 30.0 else Color("ff9a6a"))
	var p := Vector2(player.global_position.x, player.global_position.z)
	var near := WorldGen.nearest_settlement(p)
	var place := "Wilderness"
	if not near.is_empty():
		var d := p.distance_to(near["pos"])
		place = near["name"] if d < near["radius"] * 1.6 else "Road to %s  (%dm)" % [near["name"], int(d)]
	var t := WorldSim.time_of_day
	_where.text = "%s\nDay %d  %02d:%02d\nRealm  %s souls" % [place, WorldSim.day, int(t), int(fmod(t, 1.0) * 60.0),
		_thousands(WorldSim.population())]
	_perf.text = perf
	_interact.visible = target != null
	if target and target.has_method("prompt"):
		_interact_label.text = target.prompt()
	for b in _order_buttons:
		b.visible = soldiers > 0


## Opens a menu. `source` returns {title, body, options: [[label, Callable() -> String, enabled?]]};
## it is called again after every choice so prices and stock stay current.
func show_menu(source: Callable) -> void:
	_menu_source = source
	_rebuild_menu()
	_menu.visible = true


func close_menu() -> void:
	_menu.visible = false


func is_menu_open() -> bool:
	return _menu.visible


func _rebuild_menu() -> void:
	for child in _menu.get_children():
		child.queue_free()
	var data: Dictionary = _menu_source.call()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_menu.add_child(box)
	var head := _label(box, 26, GOLD)
	head.text = data.get("title", "")
	var body := _label(box, 16, PAPER)
	body.text = data.get("body", "")
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size.x = 480
	for opt: Array in data.get("options", []):
		var b := Button.new()
		b.text = opt[0]
		b.custom_minimum_size = Vector2(480, 44)
		b.add_theme_font_size_override("font_size", 17)
		b.disabled = opt.size() > 2 and not opt[2]
		var action: Callable = opt[1]
		b.pressed.connect(func() -> void:
			var msg: Variant = action.call()
			if msg is String and msg != "":
				show_toast(msg)
			if _menu.visible:
				_rebuild_menu())
		box.add_child(b)
	var close := Button.new()
	close.text = "Leave"
	close.custom_minimum_size = Vector2(480, 40)
	close.pressed.connect(close_menu)
	box.add_child(close)


## Danger readout with its biggest reasons, e.g. "Dangerous 41 · Wolf den +22 · Runestone -18".
func update_danger(t: Dictionary) -> void:
	var total: float = t["total"]
	var lines: Array = t["lines"].duplicate()
	lines.sort_custom(func(a: Array, b: Array) -> bool: return absf(a[1]) > absf(b[1]))
	var parts := PackedStringArray()
	for l in lines.slice(0, 3):
		parts.append("%s %+d" % [l[0], int(l[1])])
	_danger.text = "Danger  %s %d\n%s" % [RAThreatMap.describe(total), int(total), "\n".join(parts)]
	var c := Color("9fe39f").lerp(Color("ff7b5c"), clampf(total / 70.0, 0.0, 1.0))
	_danger.add_theme_color_override("font_color", c)


static func _thousands(n: int) -> String:
	var s := str(n)
	var out := ""
	for i in s.length():
		if i > 0 and (s.length() - i) % 3 == 0:
			out += ","
		out += s[i]
	return out
