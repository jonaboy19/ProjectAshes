class_name HUD
extends CanvasLayer
## Full-resolution UI drawn over the low-resolution pixel render: stats, orders,
## touch controls and messages. Crisp text on top of chunky pixels.
##
## Navigation: a compass strip (top centre), place discovery with a cinematic
## banner, a full-screen world map with fast travel, and photo mode. The map and
## photo mode are children of this layer but not of the HUD root, so hiding the
## root (photo mode) keeps them on screen.
##
## Wiring for main.gd: `hud.fast_travel_requested.connect(func(p: Vector2) -> void: _teleport(p, 0.0))`.
## More touch buttons: `hud.add_action_button("ride", "Ride", "ride", "walk")`.

## Fast travel confirmed on the map. The screen is already black and the clock
## advanced; teleport the player to `pos` (x/z) synchronously in the handler.
signal fast_travel_requested(pos: Vector2)
signal place_discovered(place: Dictionary)

const InventoryScreen := preload("res://scripts/ui/inventory_screen.gd")
const CraftingScreen := preload("res://scripts/ui/crafting_screen.gd")
const TechniqueButtons := preload("res://scripts/ui/technique_buttons.gd")
const SkillsScreen := preload("res://scripts/ui/skills_screen.gd")
var skills_screen: Control
const Discovery := preload("res://scripts/sim/discovery.gd")
const CompassBar := preload("res://scripts/ui/compass.gd")
const WorldMap := preload("res://scripts/ui/world_map.gd")
const PhotoMode := preload("res://scripts/ui/photo_mode.gd")
const DiscoveryBanner := preload("res://scripts/ui/discovery_banner.gd")
const MapIcons := preload("res://scripts/ui/map_icons.gd")

const DISCOVERY_RATE := 0.25       # s between discovery checks
const MARKER_RATE := 1.0           # s between compass marker rebuilds
const COMPASS_RANGE := 400.0       # discovered places shown on the compass
const HOSTILE_RANGE := 250.0       # camps shown (red) even before they are found
const COMBAT_RANGE := 45.0         # enemies this close block fast travel (same as the battle music)
const DOCK_SIZE := 58
const DOCK_STEP := 78              # button + caption

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
var _root: Control
var compass: Control               # scripts/ui/compass.gd
var banner: Control                # scripts/ui/discovery_banner.gd
var world_map: Control             # scripts/ui/world_map.gd
var photo_mode: Control            # scripts/ui/photo_mode.gd
var discovery: RefCounted          # scripts/sim/discovery.gd (Life.discovery when Life owns one)
var _fade: ColorRect
var _dock: Array[TouchScreenButton] = []     # auto-placed action buttons, in order
var _anchored: Dictionary = {}               # TouchScreenButton -> offset from the bottom-right corner
var _nav_timer := 0.0
var _marker_timer := 0.0
var _quest_override: Variant = null
## Anything with active_objective_position() -> Vector2|null (e.g. the radiant
## quest tracker: `hud.quest_source = services.radiant()`). Life.radiant is used
## automatically when Life owns one.
var quest_source: Object


func _init(p: Player) -> void:
	player = p
	layer = 10


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_root = root
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
	for extra: Array in [["order_retreat", KEY_G], ["order_formation", KEY_B]]:
		if not InputMap.has_action(extra[0]):
			InputMap.add_action(extra[0])
			var ev := InputEventKey.new()
			ev.physical_keycode = extra[1]
			InputMap.action_add_event(extra[0], ev)
	for pair in [["order_follow", "Follow", "walk"], ["order_hold", "Hold", "flag-objective"], ["order_charge", "Charge", "charging-bull"],
			["order_retreat", "Retreat", "dodge"], ["order_formation", "Form", "checked-shield"]]:
		var b := _button(pair[0], pair[1], 72, Color("5fae6b"), pair[2])
		b.visible = false
		_order_buttons.append(b)
	var techniques := TechniqueButtons.new()
	controls.add_child(techniques)
	techniques.open_skills_requested.connect(func() -> void: skills_screen.open())

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
	_perf.anchor_top = 1.0
	_perf.anchor_bottom = 1.0
	_perf.offset_left = -300
	_perf.offset_right = 300
	_perf.offset_top = -22
	_perf.offset_bottom = -4
	_perf.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_danger = _label(root, 14, UITheme.TEXT)
	# Under the status card, clear of the right-hand dock and the combat buttons.
	_danger.offset_left = 20
	_danger.offset_right = 420
	_danger.offset_top = 216
	_danger.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_toast_box = PanelContainer.new()
	_toast_box.add_theme_stylebox_override("panel", UITheme.pill(UITheme.BG, UITheme.ACCENT.darkened(0.3), 22))
	_toast_box.anchor_left = 0.5
	_toast_box.anchor_right = 0.5
	_toast_box.offset_top = 80
	_toast_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_box.modulate.a = 0.0
	root.add_child(_toast_box)
	_toast = _label(_toast_box, 18, UITheme.TEXT)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast.custom_minimum_size.x = 420

	_build_navigation(root)

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
	_build_overlays()
	get_viewport().size_changed.connect(_layout)
	_layout()


func hide_loading() -> void:
	_loading.visible = false
	world_map.start_bake()      # paint the map terrain in the background now the world exists


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
	return _make_button(action, text, size, color, UITheme.icon(icon_name) if icon_name != "" else null)


func _make_button(action: String, text: String, size: int, color: Color, ic: Texture2D) -> TouchScreenButton:
	var b := TouchScreenButton.new()
	b.action = action
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
	# Dock: a column left of the utility column, then further columns, kept clear
	# of the interact / attack cluster at the bottom right.
	var top := 118.0   # clear of the place / day / realm lines
	var bottom := s.y - 300.0 - 8.0
	var rows := maxi(1, int((bottom - top - DOCK_SIZE) / DOCK_STEP) + 1)
	for i in _dock.size():
		@warning_ignore("integer_division")
		var c := i / rows
		_dock[i].position = Vector2(col - (c + 1) * (DOCK_SIZE + 12), top + (i % rows) * DOCK_STEP)
	for b: TouchScreenButton in _anchored:
		b.position = s - (_anchored[b] as Vector2)
	if compass:
		var w := clampf(s.x - 2.0 * 430.0, 260.0, 480.0)
		compass.size = Vector2(w, compass.custom_minimum_size.y)
		compass.position = Vector2((s.x - w) * 0.5, 10.0)
		# The place line lives right of the compass and wraps rather than running under it.
		_where.offset_left = -(s.x - (compass.position.x + w + 14.0))
		_where.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


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
	if not _menu.visible:
		Audio.play_ui("open")
	_menu_source = source
	_rebuild_menu()
	_menu.visible = true


func close_menu() -> void:
	if _menu.visible:
		Audio.play_ui("close")
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


# --- action buttons ----------------------------------------------------------------

## Adds a round touch button and returns it (also kept in the button table under
## `button_name`). `action` is an InputMap action name (the button presses it, like
## the attack button) or a Callable run on press. `icon_name` is an SVG in
## assets/ui/icons/ or "glyph:<name>" for a UITheme.glyph ("map", "camera",
## "compass"). By default the button joins the dock next to the utility column;
## pass `anchor` (offset from the bottom-right corner, like the attack cluster)
## to place it yourself. Call after the HUD is in the tree.
##   hud.add_action_button("ride", "Ride", "ride", "walk")
##   hud.add_action_button("lock_on", "Lock", "lock_on", "eye-target", UITheme.ACTION_BLOCK, 72, Vector2(330, 200))
func add_action_button(button_name: String, label: String, action: Variant, icon_name := "",
		color := UITheme.ACTION_UTIL, size := DOCK_SIZE, anchor := Vector2.INF) -> TouchScreenButton:
	var ic: Texture2D = null
	if icon_name.begins_with("glyph:"):
		ic = UITheme.glyph(icon_name.trim_prefix("glyph:"))
	elif icon_name != "":
		ic = UITheme.icon(icon_name)
	var b := _make_button(action if action is String else "", label, size, color, ic)
	if action is Callable:
		b.pressed.connect(action)
	if ic != null:
		var cap: Label = b.get_child(0)
		cap.add_theme_font_size_override("font_size", 12)
		cap.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	var old: Variant = _buttons.get(button_name)
	if old is TouchScreenButton and (_dock.has(old) or _anchored.has(old)):
		remove_action_button(button_name)   # re-adding replaces; built-in buttons are never replaced
	_buttons[button_name] = b
	if anchor == Vector2.INF:
		_dock.append(b)
	else:
		_anchored[b] = anchor
	_layout()
	return b


func remove_action_button(button_name: String) -> void:
	var b: TouchScreenButton = _buttons.get(button_name)
	if b == null:
		return
	_buttons.erase(button_name)
	_dock.erase(b)
	_anchored.erase(b)
	b.queue_free()
	_layout()


func get_action_button(button_name: String) -> TouchScreenButton:
	return _buttons.get(button_name)


# --- navigation: discovery, compass, map, photo mode ---------------------------------

func _build_navigation(root: Control) -> void:
	for pair: Array in [["world_map", KEY_M], ["photo_mode", KEY_P]]:
		if not InputMap.has_action(pair[0]):
			InputMap.add_action(pair[0])
			var ev := InputEventKey.new()
			ev.physical_keycode = pair[1]
			InputMap.action_add_event(pair[0], ev)
	compass = CompassBar.new()
	compass.player = player
	compass.tapped.connect(toggle_map)
	root.add_child(compass)
	banner = DiscoveryBanner.new()
	root.add_child(banner)
	add_action_button("map", "Map", "world_map", "glyph:map", UITheme.ACTION_TALK.darkened(0.15))
	# Photo mode, inventory, crafting and the arts live in the Pack menu (the dock stays
	# short so it never crowds the combat cluster); keys P, K and the pack key still work.


## Map, photo mode and the travel fade sit above the HUD root (not hidden with it).
func _build_overlays() -> void:
	skills_screen = SkillsScreen.new()
	add_child(skills_screen)
	world_map = WorldMap.new()
	world_map.player = player
	world_map.travel_check = _travel_block_reason
	world_map.travel_requested.connect(_on_travel_requested)
	add_child(world_map)
	photo_mode = PhotoMode.new()
	photo_mode.closed.connect(func() -> void: _root.visible = true)
	photo_mode.screenshot_saved.connect(func(path: String) -> void: print("[photo] saved ", path))
	add_child(photo_mode)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.process_mode = Node.PROCESS_MODE_ALWAYS
	_fade.visible = false
	add_child(_fade)


## The discovery tracker: Life's when Life owns one (so it is saved), else the HUD's.
func get_discovery() -> RefCounted:
	if discovery == null:
		var owned: Variant = Life.get("discovery")
		discovery = owned if owned is RefCounted else Discovery.new()
	if discovery.places.is_empty() and not WorldGen.settlements.is_empty():
		discovery.build_from_world(Life.lore.places_in_region())
	return discovery


## Overrides the compass/map quest marker (Vector2 x/z), or null to go back to
## the accepted guild commission's target.
func set_quest_target(pos: Variant) -> void:
	_quest_override = pos
	_marker_timer = 0.0


func _unhandled_input(event: InputEvent) -> void:
	if _loading.visible or not visible:
		return
	if event.is_action_pressed("world_map"):
		toggle_map()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("photo_mode"):
		open_photo_mode()
		get_viewport().set_input_as_handled()


func toggle_map() -> void:
	if world_map.visible:
		world_map.close()
		return
	if photo_mode.is_active() or _loading.visible or _fade.visible:
		return
	close_menu()
	world_map.discovery = get_discovery()
	world_map.quest_target = _quest_target()
	world_map.open()


func open_photo_mode() -> void:
	if photo_mode.is_active() or world_map.visible or _loading.visible or _fade.visible:
		return
	close_menu()
	_root.visible = false
	photo_mode.open(player)


func _process(delta: float) -> void:
	if not visible or _loading.visible or player == null or not player.is_inside_tree():
		return
	_nav_timer -= delta
	if _nav_timer <= 0.0:
		_nav_timer = DISCOVERY_RATE
		_check_discovery()
	_marker_timer -= delta
	if _marker_timer <= 0.0:
		_marker_timer = MARKER_RATE
		_refresh_markers()


func _player_xz() -> Vector2:
	return Vector2(player.global_position.x, player.global_position.z)


func _check_discovery() -> void:
	if InteriorDoor.active != null:
		return
	var d := get_discovery()
	for pl: Dictionary in d.update(_player_xz(), WorldSim.day):
		banner.show_place(pl["name"], Discovery.kind_label(String(pl["kind"])))
		place_discovered.emit(pl)
		_reward_discovery(pl)
		_marker_timer = 0.0


## A little experience for finding a place: Life's XP API if it has one, else
## merit (which drives Life.player_level), granted after the banner so the
## "+merit" toast does not talk over it.
func _reward_discovery(pl: Dictionary) -> void:
	var amount := 5 if pl["category"] == "settlement" else 3
	var reason := "discovered %s" % pl["name"]
	get_tree().create_timer(DiscoveryBanner.DURATION * 0.8, false).timeout.connect(func() -> void:
		if Life.has_method("add_xp"):
			Life.call("add_xp", amount * 10, reason)
		elif Life.has_method("add_merit"):
			Life.add_merit(amount, reason))


func _refresh_markers() -> void:
	var d := get_discovery()
	var p := _player_xz()
	var list := []
	var seen := {}
	for pl: Dictionary in d.nearby(p, COMPASS_RANGE):
		seen[pl["id"]] = true
		list.append({"pos": pl["pos"], "kind": pl["kind"], "color": MapIcons.color_for(pl), "hostile": pl["hostile"]})
	for pl: Dictionary in d.nearby(p, HOSTILE_RANGE, true):
		if pl["hostile"] and not seen.has(pl["id"]):
			list.append({"pos": pl["pos"], "kind": pl["kind"], "color": MapIcons.HOSTILE, "hostile": true})
	compass.markers = list
	compass.quest_target = _quest_target()


## Where the active objective is: an override, the tracked radiant quest's stage,
## else the first accepted guild
## commission with a place (cull -> its den, deliver/escort -> the destination
## settlement, investigate -> the rumour's location). null when there is none.
func _quest_target() -> Variant:
	if _quest_override is Vector2:
		return _quest_override
	for src: Variant in [quest_source, Life.get("radiant")]:
		if src is Object and is_instance_valid(src) and (src as Object).has_method("active_objective_position"):
			var qp: Variant = (src as Object).call("active_objective_position")
			if qp is Vector2:
				return qp
	for c: Dictionary in Life.guild.active_for(RAAdventurerGuild.PLAYER):
		var t: Dictionary = c.get("target", {})
		match String(c.get("type", "")):
			"cull":
				for den: Dictionary in Frontier.ecology.dens:
					if int(den["id"]) == int(t.get("den", -1)) and den.get("alive", true):
						return den["pos"]
			"deliver", "escort":
				for s: Dictionary in WorldGen.settlements:
					if s["name"] == String(t.get("to", "")):
						return s["pos"]
			"investigate":
				for m: Dictionary in Frontier.threat.modifiers:
					if str(hash(m.get("label", ""))) == String(t.get("rumour", "")) and m.has("pos"):
						return m["pos"]
	return null


## "" when fast travel is allowed, else why not.
func _travel_block_reason() -> String:
	if player.dead:
		return "You cannot travel now."
	if InteriorDoor.active != null:
		return "Step outside first."
	var p := player.global_position
	for e in get_tree().get_nodes_in_group("team1"):
		if e is Node3D and (e as Node3D).global_position.distance_to(p) < COMBAT_RANGE:
			return "Enemies are near. You cannot fast travel during combat."
	return ""


func _on_travel_requested(pos: Vector2, hours: float, place: Dictionary) -> void:
	_fade.visible = true
	_fade.color.a = 0.0
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.45)
	await tw.finished
	WorldSim.advance_hours(hours)
	if fast_travel_requested.get_connections().is_empty():
		# Not wired yet: move the player directly (terrain streams in around them).
		player.global_position = Vector3(pos.x, WorldGen.height(pos.x, pos.y) + 0.5, pos.y)
		player.velocity = Vector3.ZERO
	else:
		fast_travel_requested.emit(pos)
	for i in 3:
		await get_tree().process_frame
	_nav_timer = 0.0
	_marker_timer = 0.0
	var tw2 := create_tween()
	tw2.tween_property(_fade, "color:a", 0.0, 0.7)
	await tw2.finished
	_fade.visible = false
	show_toast("Arrived at %s  ·  %s on the road" % [place.get("name", "your destination"), WorldMap.fmt_hours(hours)])
