extends CanvasLayer
## Tower UI, all built in code on its own CanvasLayer (docs/design/DUNGEON_TOWERS.md):
##   menu()           one modal panel for everything textual: boss-door prompt, teleport gate, vendor, scout, party hire,
##                    race board, rest. Buttons are touch sized.
##   banner()         the floor-clear / arrival banner
##   set_boss()       top-centre boss health bar with phase pips, a "?" / pattern callout and the enrage flash
##   FloorMap         a small explored-cells map (tap to enlarge) with the player arrow and discovered points
## Nothing here touches game state; callers pass callables.

const FG := preload("res://scripts/world/towers/floor_gen.gd")
const TowerData := preload("res://scripts/world/towers/tower_data.gd")

signal menu_closed

var _root: Control
var _menu_dim: ColorRect
var _menu_panel: PanelContainer
var _menu_box: VBoxContainer
var _banner: Label
var _banner_sub: Label
var _banner_box: VBoxContainer
var _boss_box: VBoxContainer
var _boss_name: Label
var _boss_bar: ProgressBar
var _boss_call: Label
var _boss_pips: HBoxContainer
var _map: Control
var _map_label: Label
var _map_box: VBoxContainer
var _big_map := false
var _tween: Tween
var _call_tween: Tween
var menu_open := false


func _ready() -> void:
	layer = 61
	name = "TowerUI"
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UITheme.theme()
	add_child(_root)
	_build_banner()
	_build_boss_bar()
	_build_map()
	_build_menu()


# ------------------------------------------------------------------ banner

func _build_banner() -> void:
	_banner_box = VBoxContainer.new()
	_banner_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner_box.anchor_left = 0.0
	_banner_box.anchor_right = 1.0
	_banner_box.offset_top = 120.0
	_banner_box.offset_bottom = 300.0
	_banner_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	_banner_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner_box.modulate.a = 0.0
	_root.add_child(_banner_box)
	_banner = Label.new()
	_banner.add_theme_font_override("font", UITheme.title_font())
	_banner.add_theme_font_size_override("font_size", 46)
	_banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_banner.add_theme_constant_override("outline_size", 10)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_box.add_child(_banner)
	_banner_sub = Label.new()
	_banner_sub.add_theme_font_size_override("font_size", 22)
	_banner_sub.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_banner_sub.add_theme_constant_override("outline_size", 8)
	_banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_banner_box.add_child(_banner_sub)


func banner(title: String, sub := "", color := UITheme.ACCENT, seconds := 4.0) -> void:
	_banner.text = title
	_banner.add_theme_color_override("font_color", color)
	_banner_sub.text = sub
	_banner_sub.add_theme_color_override("font_color", UITheme.TEXT)
	if _tween:
		_tween.kill()
	_banner_box.modulate.a = 0.0
	_tween = create_tween()
	_tween.tween_property(_banner_box, "modulate:a", 1.0, 0.35)
	_tween.tween_interval(seconds)
	_tween.tween_property(_banner_box, "modulate:a", 0.0, 0.8)


func banner_visible() -> bool:
	return _banner_box.modulate.a > 0.05


# ------------------------------------------------------------------ boss bar

func _build_boss_bar() -> void:
	_boss_box = VBoxContainer.new()
	_boss_box.anchor_left = 0.5
	_boss_box.anchor_right = 0.5
	_boss_box.offset_left = -260.0
	_boss_box.offset_right = 260.0
	_boss_box.offset_top = 14.0
	_boss_box.visible = false
	_boss_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_boss_box)
	_boss_name = Label.new()
	_boss_name.add_theme_font_override("font", UITheme.title_font())
	_boss_name.add_theme_font_size_override("font_size", 24)
	_boss_name.add_theme_color_override("font_color", Color("ffb38a"))
	_boss_name.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_boss_name.add_theme_constant_override("outline_size", 8)
	_boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_box.add_child(_boss_name)
	_boss_bar = ProgressBar.new()
	_boss_bar.custom_minimum_size = Vector2(520, 20)
	_boss_bar.show_percentage = false
	_boss_bar.max_value = 100.0
	_boss_bar.value = 100.0
	_boss_bar.add_theme_stylebox_override("fill", UITheme.bar_fill(Color("d9483b")))
	_boss_box.add_child(_boss_bar)
	_boss_pips = HBoxContainer.new()
	_boss_pips.alignment = BoxContainer.ALIGNMENT_CENTER
	_boss_pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_box.add_child(_boss_pips)
	for i in 3:
		var p := ColorRect.new()
		p.custom_minimum_size = Vector2(28, 5)
		p.color = Color(1, 1, 1, 0.25)
		_boss_pips.add_child(p)
	_boss_call = Label.new()
	_boss_call.add_theme_font_size_override("font_size", 26)
	_boss_call.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_boss_call.add_theme_constant_override("outline_size", 8)
	_boss_call.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_box.add_child(_boss_call)


func set_boss(title: String, hp: int, max_hp: int, phase := 1, enraged := false, shown := true) -> void:
	_boss_box.visible = shown
	if not shown:
		return
	_boss_name.text = title
	_boss_bar.max_value = float(max_hp)
	_boss_bar.value = float(hp)
	_boss_bar.add_theme_stylebox_override("fill", UITheme.bar_fill(Color("ff5a3a") if enraged else Color("d9483b")))
	for i in _boss_pips.get_child_count():
		(_boss_pips.get_child(i) as ColorRect).color = Color(1.0, 0.75, 0.3, 0.95) if i < phase else Color(1, 1, 1, 0.25)


func boss_call(text: String, known: bool) -> void:
	_boss_call.text = text
	_boss_call.add_theme_color_override("font_color", Color("ffd27a") if known else Color("ff8f8f"))
	_boss_call.modulate.a = 1.0
	if _call_tween:
		_call_tween.kill()
	_call_tween = create_tween()
	_call_tween.tween_interval(1.2)
	_call_tween.tween_property(_boss_call, "modulate:a", 0.0, 0.6)


# ------------------------------------------------------------------ menu

func _build_menu() -> void:
	_menu_dim = ColorRect.new()
	_menu_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu_dim.color = Color(0, 0, 0, 0.5)
	_menu_dim.visible = false
	_menu_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_menu_dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu_dim.add_child(center)
	_menu_panel = PanelContainer.new()
	_menu_panel.custom_minimum_size = Vector2(520, 0)
	center.add_child(_menu_panel)
	_menu_box = VBoxContainer.new()
	_menu_box.add_theme_constant_override("separation", 10)
	_menu_panel.add_child(_menu_box)


## A modal panel. `lines`: body text (one paragraph per entry). `buttons`: [[label, Callable, (optional) enabled]].
## A Close button is always appended. Returns the panel so tests and shots can inspect it.
func menu(title: String, lines: Array, buttons: Array, close_label := "Close") -> Control:
	for c in _menu_box.get_children():
		_menu_box.remove_child(c)
		c.queue_free()
	var t := Label.new()
	t.text = title
	t.add_theme_font_override("font", UITheme.title_font())
	t.add_theme_font_size_override("font_size", 28)
	t.add_theme_color_override("font_color", UITheme.ACCENT)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_menu_box.add_child(t)
	for l in lines:
		var lab := Label.new()
		lab.text = String(l)
		lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lab.custom_minimum_size = Vector2(480, 0)
		lab.add_theme_font_size_override("font_size", 18)
		_menu_box.add_child(lab)
	var scroll_needed := buttons.size() > 7
	var holder: VBoxContainer = VBoxContainer.new()
	holder.add_theme_constant_override("separation", 8)
	if scroll_needed:
		var sc := ScrollContainer.new()
		sc.custom_minimum_size = Vector2(500, 380)
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		sc.add_child(holder)
		holder.custom_minimum_size = Vector2(480, 0)
		_menu_box.add_child(sc)
	else:
		_menu_box.add_child(holder)
	for b: Array in buttons:
		var btn := Button.new()
		btn.text = String(b[0])
		btn.custom_minimum_size = Vector2(0, 54)
		btn.add_theme_font_size_override("font_size", 19)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.disabled = b.size() > 2 and not bool(b[2])
		var cb: Callable = b[1]
		btn.pressed.connect(func() -> void:
			close_menu()
			cb.call())
		holder.add_child(btn)
	var close := Button.new()
	close.text = close_label
	close.custom_minimum_size = Vector2(0, 50)
	close.pressed.connect(close_menu)
	_menu_box.add_child(close)
	_menu_dim.visible = true
	menu_open = true
	return _menu_panel


func close_menu() -> void:
	if not menu_open:
		return
	_menu_dim.visible = false
	menu_open = false
	menu_closed.emit()


# ------------------------------------------------------------------ floor map

class FloorMap extends Control:
	var L: Dictionary = {}
	var explored: Dictionary = {}
	var found: Dictionary = {}          # point kind -> Array[Vector2i] discovered
	var player_cell := Vector2i(0, 0)
	var player_yaw := 0.0
	var boss_open := false
	var reveal_all := false

	func _draw() -> void:
		if L.is_empty():
			return
		var w := int(L["w"])
		var h := int(L["h"])
		var cs := minf(size.x / float(w), size.y / float(h))
		draw_rect(Rect2(Vector2.ZERO, Vector2(cs * w, cs * h)), Color(0.04, 0.05, 0.08, 0.78))
		var open: PackedByteArray = L["open"]
		var accent: Color = TowerData.theme(String(L["theme"]))["accent"]
		for y in h:
			for x in w:
				var c := Vector2i(x, y)
				if not explored.has(c) and not reveal_all:
					continue
				var p := Vector2(float(x), float(y)) * cs
				var fill := Color(0.22, 0.25, 0.32, 0.95)
				if c == L["safe_cell"]:
					fill = Color(0.55, 0.42, 0.2, 0.95)
				elif (L["boss_block"] as Rect2i).has_point(c):
					fill = Color(0.42, 0.18, 0.16, 0.95)
				draw_rect(Rect2(p + Vector2.ONE, Vector2(cs - 2.0, cs - 2.0)), fill)
				var m := int(open[y * w + x])
				# corridors: open edges bridge the gap to the neighbour
				if m & 2 and (x + 1 < w) and (explored.has(Vector2i(x + 1, y)) or reveal_all):
					draw_rect(Rect2(p + Vector2(cs - 2.0, 1.0), Vector2(3.0, cs - 2.0)), fill)
				if m & 4 and (y + 1 < h) and (explored.has(Vector2i(x, y + 1)) or reveal_all):
					draw_rect(Rect2(p + Vector2(1.0, cs - 2.0), Vector2(cs - 2.0, 3.0)), fill)
		# markers
		var sp := Vector2(L["start"]) * cs + Vector2(cs, cs) * 0.5
		draw_circle(sp, cs * 0.22, accent)
		if explored.has(L["safe_cell"]) or reveal_all:
			draw_circle(Vector2(L["safe_cell"]) * cs + Vector2(cs, cs) * 0.5, cs * 0.26, Color(1.0, 0.8, 0.4))
		if explored.has(L["door_cell"]) or reveal_all:
			var dp := Vector2(L["door_cell"]) * cs + Vector2(cs, cs) * 0.5
			draw_rect(Rect2(dp - Vector2(cs * 0.22, cs * 0.22), Vector2(cs * 0.44, cs * 0.44)), Color(1.0, 0.4, 0.3))
		for c: Vector2i in found.get("chest", []):
			draw_rect(Rect2(Vector2(c) * cs + Vector2(cs, cs) * 0.5 - Vector2(3, 3), Vector2(6, 6)), Color(0.9, 0.8, 0.3))
		# player arrow
		var pp := Vector2(player_cell) * cs + Vector2(cs, cs) * 0.5
		var dir := Vector2(sin(player_yaw), cos(player_yaw))
		var pts := PackedVector2Array([pp + dir * cs * 0.45, pp + dir.rotated(2.5) * cs * 0.35, pp + dir.rotated(-2.5) * cs * 0.35])
		draw_colored_polygon(pts, Color.WHITE)

	func _gui_input(ev: InputEvent) -> void:
		if (ev is InputEventMouseButton and ev.pressed) or (ev is InputEventScreenTouch and ev.pressed):
			toggled.emit()

	signal toggled


func _build_map() -> void:
	_map_box = VBoxContainer.new()
	_map_box.anchor_left = 1.0
	_map_box.anchor_right = 1.0
	_map_box.offset_left = -188.0
	_map_box.offset_right = -10.0
	_map_box.offset_top = 210.0
	_map_box.visible = false
	_map_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_map_box)
	_map_label = Label.new()
	_map_label.add_theme_font_size_override("font_size", 14)
	_map_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_map_label.add_theme_constant_override("outline_size", 5)
	_map_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_map_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_map_box.add_child(_map_label)
	_map = FloorMap.new()
	_map.custom_minimum_size = Vector2(168, 168)
	(_map as FloorMap).toggled.connect(_toggle_big_map)
	_map_box.add_child(_map)


func _toggle_big_map() -> void:
	_big_map = not _big_map
	_map.custom_minimum_size = Vector2(430, 430) if _big_map else Vector2(168, 168)
	_map_box.offset_left = -450.0 if _big_map else -188.0
	_map_box.size = Vector2.ZERO
	_map.queue_redraw()


func show_map(on: bool) -> void:
	_map_box.visible = on


func map_update(L: Dictionary, explored: Dictionary, found: Dictionary, player_cell: Vector2i, yaw: float, label: String, reveal_all := false) -> void:
	var m := _map as FloorMap
	m.L = L
	m.explored = explored
	m.found = found
	m.player_cell = player_cell
	m.player_yaw = yaw
	m.reveal_all = reveal_all
	_map_label.text = label
	m.queue_redraw()


## Map image for shots / tests.
func map_node() -> Control:
	return _map
