class_name HUD
extends CanvasLayer
## Full-resolution UI drawn over the low-resolution pixel render: stats, orders,
## touch controls and messages. Crisp text on top of chunky pixels.


var player: Player
var controls: Control
var _stats: Label
var _where: Label
var _perf: Label
var _danger: Label
var _health: Meter
var _stamina: Meter
var _toast: Label
var _toast_tween: Tween
var _interact: TouchScreenButton
var _interact_label: Label
var _order_buttons: Array[TouchScreenButton] = []
var _buttons: Dictionary = {}
var _loading: ColorRect
var _loading_label: Label
var _needs: Label
var _rank: Label
var _toast_box: PanelContainer
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

	_buttons["attack"] = _button("attack", "", 128, UITheme.ACTION_ATTACK, "broadsword")
	_buttons["dodge"] = _button("dodge", "", 84, UITheme.ACTION_DODGE, "dodge")
	_buttons["block"] = _button("block", "", 84, UITheme.ACTION_BLOCK, "checked-shield")
	_buttons["view"] = _button("view_cycle", "", 58, UITheme.ACTION_UTIL, "eye-target")
	_buttons["zoom_out"] = _button("zoom_out", "−", 58, UITheme.ACTION_UTIL, "")
	_buttons["zoom_in"] = _button("zoom_in", "+", 58, UITheme.ACTION_UTIL, "")
	_interact = _button("interact", "Talk", 96, UITheme.ACTION_TALK, "hand")
	_pack_button = _button("journal", "", 58, UITheme.ACTION_UTIL, "knapsack")
	_interact_label = _interact.get_child(0)
	_interact.visible = false
	for pair in [["order_follow", "Follow", "walk"], ["order_hold", "Hold", "flag-objective"], ["order_charge", "Charge", "charging-bull"]]:
		var b := _button(pair[0], pair[1], 72, Color("5fae6b"), pair[2])
		b.visible = false
		_order_buttons.append(b)

	# Status card, top left.
	var card := Panel.new()
	card.add_theme_stylebox_override("panel", UITheme.panel_box(16))
	card.position = Vector2(12, 12)
	card.size = Vector2(300, 196)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(card)
	_rank = _label(root, 20, UITheme.ACCENT)
	_rank.add_theme_font_override("font", UITheme.title_font())
	_rank.position = Vector2(28, 20)
	_stats = _label(root, 15, UITheme.TEXT)
	_stats.position = Vector2(28, 50)
	_health = _bar(root, Vector2(28, 132), UITheme.HEALTH, 10)
	_health.max_value = player.max_health
	_health.value = player.health
	_stamina = _bar(root, Vector2(28, 148), UITheme.STAMINA, 6)
	_stamina.max_value = Player.MAX_STAMINA
	_stamina.value = Player.MAX_STAMINA
	_needs = _label(root, 13, UITheme.TEXT_DIM)
	_needs.position = Vector2(28, 162)
	_where = _label(root, 17, UITheme.TEXT)
	_where.anchor_left = 1.0
	_where.anchor_right = 1.0
	_where.offset_left = -520
	_where.offset_right = -96
	_where.offset_top = 16
	_where.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_perf = _label(root, 12, Color(1, 1, 1, 0.55))
	_perf.anchor_left = 0.5
	_perf.anchor_right = 0.5
	_perf.offset_left = -300
	_perf.offset_right = 300
	_perf.offset_top = 6
	_perf.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_danger = _label(root, 14, UITheme.TEXT)
	_danger.anchor_left = 1.0
	_danger.anchor_right = 1.0
	_danger.offset_left = -520
	_danger.offset_right = -96
	_danger.offset_top = 94
	_danger.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_toast_box = PanelContainer.new()
	_toast_box.add_theme_stylebox_override("panel", UITheme.pill(UITheme.BG, UITheme.ACCENT.darkened(0.3), 22))
	_toast_box.anchor_left = 0.5
	_toast_box.anchor_right = 0.5
	_toast_box.offset_top = 64
	_toast_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_box.modulate.a = 0.0
	root.add_child(_toast_box)
	_toast = _label(_toast_box, 18, UITheme.TEXT)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast.custom_minimum_size.x = 420

	_menu = PanelContainer.new()
	_menu.theme = UITheme.theme()
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
	_loading.color = UITheme.BG_SOLID
	_loading.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(_loading)
	_loading_label = _label(_loading, 30, UITheme.ACCENT)
	_loading_label.add_theme_font_override("font", UITheme.title_font())
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


func _bar(parent: Control, pos: Vector2, color: Color, height: int) -> Meter:
	var bar := Meter.new(color, Vector2(268, height))
	bar.position = pos
	parent.add_child(bar)
	return bar


func _label(parent: Control, size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.add_theme_constant_override("shadow_outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _button(action: String, text: String, size: int, color: Color, icon_name := "") -> TouchScreenButton:
	var b := TouchScreenButton.new()
	b.action = action
	var ic := UITheme.icon(icon_name) if icon_name != "" else null
	b.texture_normal = UITheme.round_button(size, color, ic)
	b.texture_pressed = UITheme.round_button(size, color, ic, true)
	var circle := CircleShape2D.new()
	circle.radius = size * 0.5
	b.shape = circle
	b.shape_centered = true
	var l := Label.new()
	l.text = text
	l.size = Vector2(size, size) if ic == null else Vector2(size, 22)
	l.position = Vector2.ZERO if ic == null else Vector2(0, size + 2)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 28 if ic == null else 13)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("shadow_outline_size", 4)
	b.add_child(l)
	controls.add_child(b)
	return b


func _layout() -> void:
	var s := get_viewport().get_visible_rect().size
	_buttons["attack"].position = s - Vector2(168, 168)
	_buttons["dodge"].position = s - Vector2(270, 112)
	_buttons["block"].position = s - Vector2(240, 226)
	_interact.position = s - Vector2(150, 300)
	var col := s.x - 80
	_buttons["zoom_in"].position = Vector2(col, 84)
	_buttons["zoom_out"].position = Vector2(col, 152)
	_buttons["view"].position = Vector2(col, 220)
	_pack_button.position = Vector2(col, 288)
	for i in _order_buttons.size():
		_order_buttons[i].position = Vector2(s.x * 0.5 - 130 + i * 92, s.y - 110)


func show_toast(text: String) -> void:
	_toast.text = text
	if _toast_tween:
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_box.modulate.a = 0.0
	_toast_box.scale = Vector2.ONE
	_toast_tween.tween_property(_toast_box, "modulate:a", 1.0, 0.18)
	_toast_tween.tween_interval(3.2)
	_toast_tween.tween_property(_toast_box, "modulate:a", 0.0, 0.45)


func update_status(soldiers: int, order_name: String, target: Node3D, perf: String) -> void:
	var c := Life.careers
	var job_line := "Unemployed"
	if c.is_employed():
		var duty := ""
		if c.is_on_shift(WorldSim.time_of_day):
			var p2 := Vector2(player.global_position.x, player.global_position.z)
			duty = "  · ON DUTY" if c.at_post(p2) else "  · AWAY FROM POST"
		job_line = "%s, %s%s" % [c.player["seat"], c.player_org()["name"], duty]
	_rank.text = Game.rank_name().to_upper()
	_stats.text = "%s\n◆ %d gold    ✦ %d merit\nSoldiers %d / %d%s" % [job_line, Game.gold,
		Game.merit, soldiers, Game.max_soldiers(), ("  ·  " + order_name) if soldiers > 0 else ""]
	var n := Life.needs
	_needs.text = "%s  ·  %s" % [n.hunger_label(), n.rest_label()]
	_needs.add_theme_color_override("font_color", UITheme.TEXT_DIM if n.food >= 25.0 and n.rest >= 30.0 else UITheme.DANGER)
	var p := Vector2(player.global_position.x, player.global_position.z)
	var near := WorldGen.nearest_settlement(p)
	var place := "Wilderness"
	if not near.is_empty():
		var d := p.distance_to(near["pos"])
		place = near["name"] if d < near["radius"] * 1.6 else "Road to %s  (%dm)" % [near["name"], int(d)]
		var named := Life.place_at(p)
		if d >= near["radius"] * 1.6 and not named.is_empty():
			place = "%s  ·  %s %dm" % [named["name"], near["name"], int(d)]
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
		child.visible = false     # stop the outgoing page from sizing the panel
		child.queue_free()
	# Controls grow but never shrink: without this the panel keeps the height of the
	# tallest page shown before and ends up mostly off screen (playtest 03_interact).
	_fit_menu.call_deferred()
	var data: Dictionary = _menu_source.call()
	var vw := get_viewport().get_visible_rect().size
	var width := clampf(vw.x * 0.9, 340.0, 560.0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_menu.add_child(box)
	var head := _label(box, 26, UITheme.ACCENT)
	head.add_theme_font_override("font", UITheme.title_font())
	head.text = data.get("title", "")
	var rule := ColorRect.new()
	rule.color = UITheme.ACCENT
	rule.custom_minimum_size = Vector2(56, 2)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	box.add_child(rule)
	var body := _label(box, 15, UITheme.TEXT_DIM)
	body.text = data.get("body", "")
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size.x = width
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(width, 0)
	box.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	var options: Array = data.get("options", [])
	for opt: Array in options:
		var btn := Button.new()
		btn.text = opt[0]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(width, 50)
		btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		btn.disabled = opt.size() > 2 and not opt[2]
		var action: Callable = opt[1]
		btn.pressed.connect(func() -> void:
			var msg: Variant = action.call()
			if msg is String and msg != "":
				show_toast(msg)
			if _menu.visible:
				_rebuild_menu())
		list.add_child(btn)
	scroll.custom_minimum_size.y = minf(options.size() * 58.0, vw.y * 0.45)
	var close := Button.new()
	close.text = "Close"
	close.custom_minimum_size = Vector2(width, 46)
	close.add_theme_stylebox_override("normal", UITheme.pill(Color(0, 0, 0, 0), UITheme.STROKE))
	close.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	close.pressed.connect(close_menu)
	box.add_child(close)


## Shrink the (centre-anchored) menu panel to its content and keep it centred.
func _fit_menu() -> void:
	# Wait for layout: the autowrapped body label first measures at zero width (one word
	# per line, a very tall minimum) and only settles once it has its real width.
	for i in 2:
		await get_tree().process_frame
	var s := _menu.get_combined_minimum_size()
	# The panel can hold a stale size that its offsets no longer describe, so assigning the
	# same offsets again would be a no-op: set the size itself too.
	_menu.size = s
	_menu.offset_left = -s.x * 0.5
	_menu.offset_right = s.x * 0.5
	_menu.offset_top = -s.y * 0.5
	_menu.offset_bottom = s.y * 0.5


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
