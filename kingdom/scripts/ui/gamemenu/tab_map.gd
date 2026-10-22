extends "res://scripts/ui/gamemenu/gm_tab.gd"
## MAP: the HUD's existing region map (world_map.gd) hosted inside the tab, with a
## filter list on the left. The map keeps all its own behaviour (fog, discovery,
## fast travel card, legend); this tab only reparents it, filters places and
## drives zoom / marker / legend / focus.

var _host: Control
var _rows: Dictionary = {}
var _filter := "all"
var _map: Control
var _home: Node
var _hooked := false
var _home_index := 0
var _need_fit := false
var _placeholder: Label


func build() -> void:
	var root := page_hbox(14)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 210
	left.add_theme_constant_override("separation", 4)
	root.add_child(left)
	for f: Array in MD.MAP_FILTERS:
		var r := Kit.row(String(f[1]), String(f[2]), "", "", 48)
		r.pressed.connect(set_filter.bind(String(f[0])))
		left.add_child(r)
		_rows[String(f[0])] = r
	_host = Control.new()
	_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_host.clip_contents = true
	root.add_child(_host)
	_placeholder = Kit.lbl("The map is not available yet.", 18, AF.TEXT_DIM, false, "italic")
	_placeholder.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_placeholder.visible = false
	_host.add_child(_placeholder)


func on_show() -> void:
	var hud: Object = menu.get("hud")
	var m: Variant = hud.get("world_map") if hud != null else null
	if not (m is Control):
		_placeholder.visible = true
		return
	_map = m
	_home = _map.get_parent()
	# The map stays a child of the HUD (re-parenting it would re-hook every button); it is
	# lifted above the menu and laid over this tab's host rectangle.
	_home_index = _map.get_index()
	_map.set("embedded", true)
	_map.set("discovery", hud.call("get_discovery"))
	_map.clip_contents = true
	_map.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_home.move_child(_map, -1)
	if not _hooked:
		_hooked = true
		_map.connect("travel_requested", func(_p: Vector2, _h: float, _pl: Dictionary) -> void: menu.call("close"))
		_host.resized.connect(_place)
		menu.resized.connect(_place)
	_need_fit = true
	_place()
	if _map.visible:
		_map.call("refresh")
	else:
		_map.call("open")
	_apply_filter()
	refresh()
	_place.call_deferred()


## Lays the map over the host rectangle (and fits the region once the size is real).
func _place() -> void:
	if _map == null or not is_instance_valid(_map) or not _map.visible and not _need_fit:
		return
	if _host.size.x < 32.0:
		return
	_map.global_position = _host.global_position
	_map.size = _host.size
	if _need_fit:
		_need_fit = false
		_map.call("fit_region")
	_map.queue_redraw()


func on_hide() -> void:
	if _map == null or not is_instance_valid(_map):
		return
	if _map.visible:
		_map.call("close")
	_map.set("embedded", false)
	_map.set("place_filter", Callable())
	_map.clip_contents = false
	if _home != null and is_instance_valid(_home) and _map.get_parent() == _home:
		_home.move_child(_map, mini(_home_index, _home.get_child_count() - 1))
	_map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_map = null


func refresh() -> void:
	for k: String in _rows:
		(_rows[k] as Kit.Row).set_selected(k == _filter)
	hints_changed()


func set_filter(id: String) -> void:
	_filter = id
	_apply_filter()
	refresh()


func _apply_filter() -> void:
	if _map == null:
		return
	var f := _filter
	_map.set("place_filter", Callable() if f == "all" else func(pl: Dictionary) -> bool: return MD.map_filter(f, pl))
	# Quest filters show the tracked quest's marker only when its group matches.
	var target: Variant = _quest_target()
	if f == "main" or f == "side":
		var tq: Dictionary = Life.radiant.tracked_quest()
		var main := not tq.is_empty() and MD.MAIN_KINDS.has(String(tq.get("kind", "")))
		if tq.is_empty() or main != (f == "main"):
			target = null
	_map.set("quest_target", target)
	_map.call("_select", {})
	_map.queue_redraw()


func _quest_target() -> Variant:
	var hud: Object = menu.get("hud")
	if hud != null and hud.has_method("_quest_target"):
		return hud.call("_quest_target")
	return Life.radiant.active_objective_position()


## Centres the map on a world position (used by the Quests tab "Show on Map").
func focus_world(pos: Vector2) -> void:
	if _map == null:
		return
	_filter = "all"
	_apply_filter()
	refresh()
	_map.set("quest_target", pos)
	_map.call("focus_on", pos, 0.6)


func do_zoom(factor: float) -> void:
	if _map != null:
		_map.call("zoom_by", factor)


func do_marker() -> void:
	if _map == null:
		return
	var hud: Object = menu.get("hud")
	if _map.get("marker") is Vector2:
		_map.call("place_marker", null)
		if hud != null and hud.has_method("set_quest_target"):
			hud.call("set_quest_target", null)
		return
	var sel: Dictionary = _map.call("selected_place")
	var pos: Vector2 = sel["pos"] if not sel.is_empty() else _map.call("view_center")
	_map.call("place_marker", pos)
	if hud != null and hud.has_method("set_quest_target"):
		hud.call("set_quest_target", pos)
	Audio.play_ui("pickup")


func do_legend() -> void:
	if _map != null:
		_map.call("toggle_legend")


func do_focus() -> void:
	if _map != null:
		_map.call("focus_player")


func handle_key(e: InputEventKey) -> bool:
	match e.keycode:
		KEY_L:
			do_legend()
		KEY_F:
			do_focus()
		KEY_P:
			do_marker()
		KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
			do_zoom(1.4)
		KEY_MINUS, KEY_KP_SUBTRACT:
			do_zoom(1.0 / 1.4)
		_:
			return false
	return true


func hints() -> Array:
	var has_marker: bool = _map != null and _map.get("marker") is Vector2
	return [["+/-", "Zoom", func() -> void: do_zoom(1.4), false], ["P", "Clear Marker" if has_marker else "Place Marker", do_marker, false],
		["L", "Legend", do_legend, false], ["F", "Focus Player", do_focus, false]]
