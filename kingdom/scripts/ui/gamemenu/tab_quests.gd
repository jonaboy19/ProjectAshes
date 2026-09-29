extends "res://scripts/ui/gamemenu/gm_tab.gd"
## QUESTS: Active / Completed / Failed, Main and Side groups, the selected quest
## with objectives and rewards, Track and Show on Map. Data: Life.radiant (radiant,
## lord and career quests), Life.guild commissions, Quest Weaver graph quests.

const STATES := [["active", "Active"], ["completed", "Completed"], ["failed", "Failed"]]

var _state := "active"
var _state_bar: HBoxContainer
var _ld: Kit.ListDetail
var _data := {}
var _by_id: Dictionary = {}
var _track_btn: Button
var _map_btn: Button


func build() -> void:
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", 10)
	add_child(col)
	_state_bar = HBoxContainer.new()
	_state_bar.add_theme_constant_override("separation", 6)
	col.add_child(_state_bar)
	_ld = Kit.ListDetail.new(330)
	_ld.selected.connect(func(_id: String) -> void:
		_show_detail()
		hints_changed())
	col.add_child(_ld)


func on_show() -> void:
	refresh()


func refresh() -> void:
	_data = MD.quests()
	Kit.clear(_state_bar)
	for s: Array in STATES:
		var n := (_data[s[0]] as Array).size()
		var label := "%s (%d)" % [s[1], n] if n > 0 else String(s[1])
		_state_bar.add_child(Kit.tab_button(label, String(s[0]) == _state, func() -> void: _set_state(String(s[0])), 150))
	_by_id.clear()
	var items: Array = []
	var list: Array = _data[_state]
	for group: Array in [["main", "Main Quests"], ["side", "Side Quests"]]:
		var rows: Array = list.filter(func(q: Dictionary) -> bool: return q["group"] == group[0])
		if rows.is_empty():
			continue
		items.append({"header": group[1]})
		for q: Dictionary in rows:
			_by_id[String(q["id"])] = q
			items.append({"id": q["id"], "name": q["title"], "marker": "diamond", "right": "Tracked" if bool(q.get("tracked", false)) else ""})
	_ld.set_items(items)
	if _ld.current != "":
		_ld.select(_ld.current)
	_show_detail()
	hints_changed()


func _set_state(s: String) -> void:
	_state = s
	refresh()


func _current() -> Dictionary:
	return _by_id.get(_ld.current, {})


func _show_detail() -> void:
	var d := _ld.detail
	Kit.clear(d)
	_track_btn = null
	_map_btn = null
	var q := _current()
	if q.is_empty():
		var counts := MD.quest_counts()
		match _state:
			"active":
				d.add_child(Kit.lbl("No quests in progress", 24, AF.TEXT, false, "title_bold"))
				d.add_child(Kit.lbl("Ask around the village, check the Guild board or wait for a lord's summons. Jobs you take up are tracked here.", 17, AF.TEXT_DIM, true, "italic"))
			"completed":
				d.add_child(Kit.lbl("Completed quests", 24, AF.TEXT, false, "title_bold"))
				d.add_child(Kit.lbl("%d quest%s finished in this life." % [counts["completed"], "" if int(counts["completed"]) == 1 else "s"], 18, AF.GOLD_BRIGHT, true))
				d.add_child(Kit.lbl("The game keeps only the tally; quests you finish while this menu is in use are listed here by name.", 15, AF.TEXT_DIM, true, "italic"))
			_:
				d.add_child(Kit.lbl("Failed quests", 24, AF.TEXT, false, "title_bold"))
				d.add_child(Kit.lbl("%d quest%s failed or abandoned." % [counts["failed"], "" if int(counts["failed"]) == 1 else "s"], 18, AF.GOLD_BRIGHT, true))
		return
	d.add_child(Kit.lbl(String(q["title"]), 28, AF.TEXT, true, "title_bold"))
	d.add_child(Kit.lbl(String(q["subtitle"]), 16, AF.GOLD))
	if String(q["desc"]) != "":
		d.add_child(Kit.lbl(String(q["desc"]), 17, AF.TEXT, true))
	if q["pos"] is Vector2 and Life.player != null:
		var pp := Vector2(Life.player.global_position.x, Life.player.global_position.z)
		d.add_child(Kit.lbl("Objective: %s from you." % MD.direction_text(pp, q["pos"]), 15, AF.TEXT_DIM, true, "italic"))
	var objs: Array = q["objectives"]
	if not objs.is_empty():
		d.add_child(Kit.section("Objectives", 18))
		for o: Dictionary in objs:
			var h := HBoxContainer.new()
			h.add_theme_constant_override("separation", 10)
			h.add_child(Kit.Check.new(bool(o["done"])))
			var l := Kit.lbl(String(o["text"]), 17, AF.TEXT_DIM if bool(o["done"]) else AF.TEXT, true)
			h.add_child(l)
			d.add_child(h)
	var rewards: Array = q["rewards"]
	if not rewards.is_empty():
		d.add_child(Kit.section("Rewards", 18))
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 22)
		flow.add_theme_constant_override("v_separation", 8)
		d.add_child(flow)
		for r: Dictionary in rewards:
			var h2 := HBoxContainer.new()
			h2.add_theme_constant_override("separation", 8)
			var icon_name := String(r["icon"])
			if String(r.get("kind", "")) == "item" and Kit.item_icon(String(r.get("item", ""))) != null:
				h2.add_child(Kit.framed_icon("items/" + String(r["item"]), 36, AF.TEXT))
			else:
				h2.add_child(Kit.framed_icon(icon_name, 36, AF.GOLD_BRIGHT))
			var t := Kit.lbl(String(r["text"]), 17, AF.TEXT)
			t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			h2.add_child(t)
			flow.add_child(h2)
	if _state == "active":
		d.add_child(Kit.hspacer())
		var bar := HBoxContainer.new()
		bar.add_theme_constant_override("separation", 12)
		d.add_child(bar)
		var tracked := bool(q.get("tracked", false))
		_track_btn = Kit.button("Tracked" if tracked else "Track", not tracked, 48, 16)
		_track_btn.disabled = tracked or String(q["source"]) != "radiant"
		_track_btn.custom_minimum_size.x = 150
		_track_btn.pressed.connect(do_track)
		bar.add_child(_track_btn)
		_map_btn = Kit.button("Show on Map", false, 48, 16)
		_map_btn.disabled = not (q["pos"] is Vector2)
		_map_btn.custom_minimum_size.x = 170
		_map_btn.pressed.connect(do_show_on_map)
		bar.add_child(_map_btn)


func do_track() -> void:
	var q := _current()
	if q.is_empty() or String(q["source"]) != "radiant":
		return
	Life.radiant.tracked = String(q["id"])
	Audio.play_ui("pickup")
	Game.say("Tracking: %s" % String(q["title"]))
	refresh()


func do_show_on_map() -> void:
	var q := _current()
	if q.is_empty() or not (q["pos"] is Vector2):
		return
	menu.call("show_on_map", q["pos"], String(q["group"]))


func handle_key(e: InputEventKey) -> bool:
	match e.keycode:
		KEY_T:
			do_track()
		KEY_ENTER, KEY_KP_ENTER:
			do_show_on_map()
		KEY_UP:
			_ld.step(-1)
		KEY_DOWN:
			_ld.step(1)
		KEY_LEFT, KEY_RIGHT:
			var i := 0
			for k in STATES.size():
				if STATES[k][0] == _state:
					i = k
			_set_state(String(STATES[clampi(i + (1 if e.keycode == KEY_RIGHT else -1), 0, STATES.size() - 1)][0]))
		_:
			return false
	return true


func hints() -> Array:
	var q := _current()
	var can_track := not q.is_empty() and _state == "active" and String(q["source"]) == "radiant" and not bool(q.get("tracked", false))
	var can_map := not q.is_empty() and q["pos"] is Vector2
	return [["T", "Track", do_track, not can_track], ["Enter", "Show on Map", do_show_on_map, not can_map],
		["Up/Dn", "Select", func() -> void: _ld.step(1), false]]
