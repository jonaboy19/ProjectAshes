extends Control
## Full-screen crafting: station tabs (the stations in reach, or every kind when
## browsing with none nearby), the skills that station teaches with their xp
## bars, the recipe list for the station (what you can make now first), and a
## detail panel with the ingredients (owned / needed), the quality odds for your
## skill, what the result does, and a Craft button that fills a progress bar
## before the item is made. Each craft takes a little in-game time.
##
## Station menus in village_services.gd open it for a fixed kind:
##   opts.append(CraftingScreen.menu_option(hud, ["hearth"], "Cook at the hearth"))
## and the HUD's Craft button opens it for whatever is in reach of the player:
##   CraftingScreen.open_for(hud)
## Pauses the game while open (process_mode ALWAYS).

signal closed

const Crafting := preload("res://scripts/sim/crafting.gd")
const Equipment := preload("res://scripts/sim/equipment.gd")
const Inv := preload("res://scripts/ui/inventory_screen.gd")
const SELF_PATH := "res://scripts/ui/crafting_screen.gd"
## Real seconds per recipe "time" unit (the progress bar).
const SECONDS_PER_TIME := 0.7

var kinds: Array = []                # station kinds in reach ([] = browsing)
var station_label := ""
var _kind := ""                      # the tab shown
var _recipe := ""
var _busy := false
var _was_paused := false
var _title_font: Font

var _subtitle: Label
var _tabs_box: HBoxContainer
var _skills_box: VBoxContainer
var _list: VBoxContainer
var _detail_panel: PanelContainer
var _left_panel: PanelContainer
var _icon: Inv.Tile
var _name: Label
var _kind_label: Label
var _odds: RichTextLabel
var _needs: VBoxContainer
var _info: Label
var _craft_btn: Button
var _bar: ProgressBar
var _status: Label
var _tween: Tween


## Opens (creating on first use) as a child of `host` (the HUD layer). With no
## kinds, uses the stations in reach of the player.
static func open_for(host: Node, station_kinds: Array = [], label := "") -> Control:
	var s: Control = host.get_node_or_null("CraftingScreen")
	if s == null:
		s = (load(SELF_PATH) as GDScript).new()
		s.name = "CraftingScreen"
		host.add_child(s)
	if host.has_method("close_menu"):
		host.call("close_menu")
	var ks := station_kinds.duplicate()
	var lbl := label
	if ks.is_empty():
		var near := stations_in_reach()
		for st: Dictionary in near:
			if not ks.has(st["kind"]):
				ks.append(st["kind"])
		if not near.is_empty() and lbl == "":
			lbl = String(near[0]["name"])
	s.call("open", ks, lbl)
	return s


## Stations near the player (Life.player), nearest first.
static func stations_in_reach() -> Array:
	var pl: Variant = Life.player
	if not (pl is Node3D) or not is_instance_valid(pl):
		return []
	return Inv.shared_crafting().call("stations_near", (pl as Node3D).global_position)


## A show_menu() option that opens the screen for `station_kinds` (String or Array).
static func menu_option(host: Node, station_kinds: Variant, label := "Craft", title := "") -> Array:
	var ks: Array = station_kinds if station_kinds is Array else [station_kinds]
	return [label, func() -> String:
		open_for(host, ks, title)
		return ""]


# --- lifecycle --------------------------------------------------------------------------

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UITheme.theme()
	visible = false
	_title_font = UITheme.title_font_weight(600)
	_build()
	Life.inventory_changed.connect(func() -> void:
		if visible and not _busy:
			refresh())
	resized.connect(_fit)


func open(station_kinds: Array = [], label := "") -> void:
	kinds = station_kinds.duplicate()
	station_label = label
	var crafting := Inv.shared_crafting()
	_kind = String(kinds[0]) if not kinds.is_empty() else String(crafting.get("station_kinds").keys()[0])
	_recipe = ""
	_status.text = ""
	if not visible:
		_was_paused = get_tree().paused
		get_tree().paused = true
		visible = true
		Audio.play_ui("open")
	_fit()
	refresh()


func close() -> void:
	if not visible:
		return
	_cancel()
	visible = false
	get_tree().paused = _was_paused
	Audio.play_ui("close")
	closed.emit()


func _unhandled_input(e: InputEvent) -> void:
	if not visible:
		return
	if e.is_action_pressed("ui_cancel") or e.is_action_pressed("journal"):
		close()
		get_viewport().set_input_as_handled()


# --- build ------------------------------------------------------------------------------

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(UITheme.BG_SOLID, 0.96)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	margin.add_child(col)

	var head := HBoxContainer.new()
	col.add_child(head)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(titles)
	var title := _label(titles, 28, UITheme.ACCENT)
	title.text = "CRAFTING"
	title.add_theme_font_override("font", _title_font)
	var rule := ColorRect.new()
	rule.color = UITheme.ACCENT
	rule.custom_minimum_size = Vector2(56, 2)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	titles.add_child(rule)
	_subtitle = _label(titles, 15, UITheme.TEXT_DIM)
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var pack := Button.new()
	pack.text = "Pack"
	pack.focus_mode = Control.FOCUS_NONE
	pack.custom_minimum_size = Vector2(96, 52)
	pack.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	pack.pressed.connect(func() -> void:
		var host := get_parent()
		close()
		Inv.open_for(host))
	head.add_child(pack)
	var gap := Control.new()
	gap.custom_minimum_size.x = 10
	head.add_child(gap)
	head.add_child(Inv.round_button("×", 60, 34, close))

	var tabs_scroll := ScrollContainer.new()
	tabs_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs_scroll.custom_minimum_size.y = 50
	col.add_child(tabs_scroll)
	_tabs_box = HBoxContainer.new()
	_tabs_box.add_theme_constant_override("separation", 6)
	tabs_scroll.add_child(_tabs_box)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	col.add_child(body)

	# Left: skills of the station.
	_left_panel = PanelContainer.new()
	_left_panel.add_theme_stylebox_override("panel", _panel())
	body.add_child(_left_panel)
	_skills_box = VBoxContainer.new()
	_skills_box.add_theme_constant_override("separation", 8)
	_left_panel.add_child(_skills_box)

	# Centre: recipe list.
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.scroll_deadzone = 12
	body.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_list)

	# Right: detail.
	_detail_panel = PanelContainer.new()
	_detail_panel.add_theme_stylebox_override("panel", _panel())
	body.add_child(_detail_panel)
	var det := VBoxContainer.new()
	det.add_theme_constant_override("separation", 8)
	_detail_panel.add_child(det)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	det.add_child(top)
	_icon = Inv.Tile.new(72)
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(_icon)
	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_child(names)
	_kind_label = _label(names, 13, UITheme.ACCENT_2)
	_name = _label(names, 21, UITheme.TEXT)
	_name.add_theme_font_override("font", _title_font)
	_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var dscroll := ScrollContainer.new()
	dscroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	det.add_child(dscroll)
	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("separation", 6)
	dscroll.add_child(inner)
	var nh := _label(inner, 13, UITheme.TEXT_DIM)
	nh.text = "REQUIRES"
	_needs = VBoxContainer.new()
	_needs.add_theme_constant_override("separation", 2)
	inner.add_child(_needs)
	_odds = RichTextLabel.new()
	_odds.bbcode_enabled = true
	_odds.fit_content = true
	_odds.scroll_active = false
	_odds.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_odds.add_theme_font_size_override("normal_font_size", 14)
	inner.add_child(_odds)
	_info = _label(inner, 14, UITheme.TEXT_DIM)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.custom_minimum_size.y = 10
	_bar.max_value = 1.0
	_bar.step = 0.0
	_bar.add_theme_stylebox_override("fill", UITheme.bar_fill(UITheme.ACCENT))
	det.add_child(_bar)
	_craft_btn = Button.new()
	_craft_btn.text = "Craft"
	_craft_btn.focus_mode = Control.FOCUS_NONE
	_craft_btn.custom_minimum_size = Vector2(0, 56)
	_craft_btn.add_theme_font_size_override("font_size", 19)
	Inv.gold_button(_craft_btn)
	_craft_btn.pressed.connect(_on_craft)
	det.add_child(_craft_btn)
	_status = _label(det, 14, UITheme.OK)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _panel() -> StyleBoxFlat:
	var s := UITheme.panel_box(18)
	s.set_content_margin_all(16)
	s.shadow_size = 8
	return s


func _label(parent: Control, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _fit() -> void:
	var w := size.x if size.x > 0.0 else get_viewport_rect().size.x
	var narrow := w < 1000.0
	_left_panel.custom_minimum_size.x = 190.0 if narrow else 240.0
	_detail_panel.custom_minimum_size.x = 270.0 if narrow else 340.0


# --- refresh ----------------------------------------------------------------------------

func _ctx() -> Dictionary:
	var org := ""
	var c: Variant = Life.get("careers")
	if c is Object and bool((c as Object).call("is_employed")):
		org = String(((c as Object).get("player") as Dictionary).get("org", ""))
	return {"equipment": Inv.shared_equipment(), "org": org}


func _browsing() -> bool:
	return kinds.is_empty()


func refresh() -> void:
	var crafting := Inv.shared_crafting()
	var sk: Dictionary = crafting.get("station_kinds")
	if _browsing():
		_subtitle.text = "No workstation in reach: browsing. Cook at a hearth or a campfire, forge at the smithy's anvil, " \
			+ "work leather and wood at its bench, brew at the healer's table."
	else:
		var names := PackedStringArray()
		for k in kinds:
			names.append(String(crafting.call("station_name", k)))
		_subtitle.text = ("At the %s" % station_label) if station_label != "" else ("At the " + ", ".join(names).to_lower())
	# Tabs.
	for c in _tabs_box.get_children():
		_tabs_box.remove_child(c)
		c.queue_free()
	var group := ButtonGroup.new()
	for k: String in (sk.keys() if _browsing() else kinds):
		var b := Button.new()
		b.text = String(crafting.call("station_name", k))
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 44)
		b.button_pressed = k == _kind
		b.pressed.connect(func() -> void:
			_kind = k
			_recipe = ""
			_status.text = ""
			refresh())
		_tabs_box.add_child(b)
	# Skills.
	for c in _skills_box.get_children():
		_skills_box.remove_child(c)
		c.queue_free()
	var sh := _label(_skills_box, 13, UITheme.ACCENT_2)
	sh.text = "SKILLS"
	for s: String in sk.get(_kind, {}).get("skills", []):
		var l := _label(_skills_box, 17, UITheme.TEXT)
		l.text = "%s  %d" % [crafting.call("skill_name", s), crafting.call("level", s)]
		var prog: Vector2i = crafting.call("xp_progress", s)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size.y = 8
		bar.max_value = maxf(1.0, prog.y)
		bar.value = prog.x if prog.y > 0 else bar.max_value
		bar.add_theme_stylebox_override("fill", UITheme.bar_fill(UITheme.ACCENT_2))
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_skills_box.add_child(bar)
		var xl := _label(_skills_box, 12, UITheme.TEXT_DIM)
		xl.text = ("%d / %d xp" % [prog.x, prog.y]) if prog.y > 0 else "Mastered"
		var bonus := Crafting.career_xp_mult(s, String(_ctx()["org"]))
		if bonus > 1.0:
			xl.text += "  ·  your post: +%d%%" % int((bonus - 1.0) * 100.0)
	# Recipes: craftable first, then by level.
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	var rs: Array[Dictionary] = crafting.call("recipes_for", [_kind])
	var ctx := _ctx()
	var rows: Array = []
	for r: Dictionary in rs:
		var why := String(crafting.call("can_craft", r["id"], Life, null if _browsing() else kinds, ctx))
		rows.append([r, why])
	rows.sort_custom(func(a: Array, b: Array) -> bool:
		if (a[1] == "") != (b[1] == ""):
			return a[1] == ""
		return int(a[0].get("level", 1)) < int(b[0].get("level", 1)))
	if _recipe == "" and not rows.is_empty():
		_recipe = String(rows[0][0]["id"])
	for row: Array in rows:
		_list.add_child(_recipe_row(row[0], String(row[1])))
	_show_detail()


func _recipe_row(r: Dictionary, why: String) -> Button:
	var crafting := Inv.shared_crafting()
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 68)
	b.toggle_mode = true
	b.button_pressed = String(r["id"]) == _recipe
	var sel := UITheme.pill(UITheme.SURFACE_HOVER, UITheme.ACCENT)
	b.add_theme_stylebox_override("pressed", sel)
	b.add_theme_stylebox_override("hover_pressed", sel)
	b.pressed.connect(func() -> void:
		_recipe = String(r["id"])
		_status.text = ""
		refresh())
	var h := HBoxContainer.new()
	h.set_anchors_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 8
	h.offset_right = -12
	h.add_theme_constant_override("separation", 12)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(h)
	var t := Inv.Tile.new(52)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var out_item := String(r.get("output", {}).get("item", "iron_ingot" if bool(r.get("repair", false)) else ""))
	t.set_item(out_item, 1, int(r.get("output", {}).get("count", 1)))
	h.add_child(t)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)
	var n := _label(v, 17, UITheme.TEXT if why == "" else UITheme.TEXT_DIM)
	n.text = String(crafting.call("recipe_name", r))
	n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var s := _label(v, 12, UITheme.TEXT_DIM)
	s.text = "%s %d" % [crafting.call("skill_name", r["skill"]), int(r.get("level", 1))]
	var st := _label(h, 13, UITheme.OK if why == "" else UITheme.DANGER.lightened(0.15))
	st.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var locked := why.begins_with("Needs %s " % crafting.call("skill_name", r["skill"]))
	st.text = "Ready" if why == "" else ("Browse" if _browsing() and why.begins_with("Needs a ") \
		else ("Lv %d" % int(r.get("level", 1)) if locked else "Missing"))
	if _browsing() and why.begins_with("Needs a "):
		st.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	return b


func _show_detail() -> void:
	var crafting := Inv.shared_crafting()
	var r: Dictionary = crafting.call("recipe", _recipe)
	for c in _needs.get_children():
		_needs.remove_child(c)
		c.queue_free()
	if r.is_empty():
		_icon.set_item("")
		_kind_label.text = "NO RECIPES"
		_name.text = ""
		_odds.text = ""
		_info.text = ""
		_craft_btn.disabled = true
		_bar.value = 0.0
		return
	var skill := String(r["skill"])
	var out: Dictionary = r.get("output", {})
	var item := String(out.get("item", ""))
	var repair := bool(r.get("repair", false))
	_icon.set_item(item if item != "" else "iron_ingot", 1, int(out.get("count", 1)))
	var stations := PackedStringArray()
	for k in r.get("stations", []):
		stations.append(String(crafting.call("station_name", k)))
	_kind_label.text = ("%s %d  ·  %s" % [crafting.call("skill_name", skill), int(r.get("level", 1)), " / ".join(stations)]).to_upper()
	_name.text = String(crafting.call("recipe_name", r)) + ((" ×%d" % int(out["count"])) if int(out.get("count", 1)) > 1 else "")
	for row: Dictionary in crafting.call("requirements", r, Life):
		var ok := int(row["have"]) >= int(row["need"])
		var l := _label(_needs, 15, UITheme.TEXT if ok else UITheme.DANGER.lightened(0.15))
		l.text = "%s   %d / %d" % [row["name"], row["have"], row["need"]]
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var lvl := int(crafting.call("level", skill))
	var o := Crafting.quality_odds(lvl, int(r.get("level", 1)))
	var gear := Equipment.is_equippable(item)
	var qc: Array = Crafting.QUALITY_COLORS
	if gear:
		_odds.text = "[color=#%s]Rough %d%%[/color]   [color=#%s]Fine %d%%[/color]   [color=#%s]Masterwork %d%%[/color]" % [
			(qc[0] as Color).to_html(false), int(round(o[0] * 100)), (qc[1] as Color).to_html(false), int(round(o[1] * 100)),
			(qc[2] as Color).to_html(false), int(round(o[2] * 100))]
	elif repair:
		_odds.text = "[color=#%s]Rough mend (60%%) %d%%[/color]   [color=#%s]Full repair %d%%[/color]" % [
			(qc[0] as Color).to_html(false), int(round(o[0] * 100)), (qc[1] as Color).to_html(false), int(round((o[1] + o[2]) * 100))]
	else:
		_odds.text = "[color=#%s]Masterwork batch (+1): %d%%[/color]" % [(qc[2] as Color).to_html(false), int(round(o[2] * 100))]
	var info := ""
	if repair:
		info = "Restores the durability of everything you wear."
	elif item != "":
		info = Inv.describe(item)
	info += "\n+%d %s xp  ·  takes %d min" % [int(r.get("xp", 5)), crafting.call("skill_name", skill),
		int(round(float(r.get("time", 1.5)) * 15.0))]
	_info.text = info.strip_edges()
	var why := String(crafting.call("can_craft", _recipe, Life, null if _browsing() else kinds, _ctx()))
	_craft_btn.disabled = why != "" or _busy
	_craft_btn.text = "Crafting…" if _busy else (String(crafting.get("skills").get(skill, {}).get("verb", "Craft")) if why == "" else why)
	_craft_btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if not _busy:
		_bar.value = 0.0


# --- crafting ---------------------------------------------------------------------------

func _on_craft() -> void:
	if _busy or _recipe == "":
		return
	var crafting := Inv.shared_crafting()
	var r: Dictionary = crafting.call("recipe", _recipe)
	if String(crafting.call("can_craft", _recipe, Life, kinds, _ctx())) != "":
		return
	_busy = true
	_status.text = ""
	_show_detail()
	_bar.value = 0.0
	_tween = create_tween()
	_tween.tween_property(_bar, "value", 1.0, maxf(0.3, float(r.get("time", 1.5)) * SECONDS_PER_TIME))
	_tween.finished.connect(_finish_craft.bind(_recipe))


func _cancel() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_busy = false
	_bar.value = 0.0


func _finish_craft(id: String) -> void:
	_busy = false
	var crafting := Inv.shared_crafting()
	var res: Dictionary = crafting.call("craft", id, Life, kinds, _ctx())
	_status.text = String(res.get("text", ""))
	_status.add_theme_color_override("font_color", UITheme.OK if res.get("ok", false) else UITheme.DANGER)
	if res.get("ok", false):
		Life.record(String(res.get("tag", "crafted")), 0.5)
		WorldSim.advance_hours(float(res.get("hours", 0.25)))
		Audio.play_ui("level_up" if res.get("level_up", false) else "pickup")
		if res.get("level_up", false):
			Game.say(String(res["text"]))
	refresh()
