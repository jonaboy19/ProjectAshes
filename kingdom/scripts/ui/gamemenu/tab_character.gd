extends "res://scripts/ui/gamemenu/gm_tab.gd"
## CHARACTER: level and XP, derived attributes, a rotatable 3D preview of the
## player with the Life.equipment slots around it, and the skills summary.

const MODEL_PROPS := {"main_hand": "1H_Sword", "off_hand": "Round_Shield"}

var _level_num: Label
var _xp_bar: Kit.Bar
var _points_val: Label
var _attr_box: VBoxContainer
var _attr_blurb: Label
var _left_slots: VBoxContainer
var _right_slots: VBoxContainer
var _slot_nodes: Dictionary = {}
var _caption: Label
var _take_off: Button
var _skills_box: VBoxContainer
var _stats_box: VBoxContainer
var _preview: Preview
var _sel_slot := ""
var _props_key := ""


## 3D preview: the player's model in its own little world, idle animation, drag to spin.
class Preview extends SubViewportContainer:
	var vp: SubViewport
	var pivot: Node3D
	var model: Node3D
	var _kit: GDScript = load("res://scripts/ui/gamemenu/gm_kit.gd")

	func _init() -> void:
		stretch = true
		mouse_filter = Control.MOUSE_FILTER_STOP
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		size_flags_vertical = Control.SIZE_EXPAND_FILL
		process_mode = Node.PROCESS_MODE_ALWAYS
		vp = SubViewport.new()
		vp.own_world_3d = true
		vp.transparent_bg = true
		vp.msaa_3d = Viewport.MSAA_2X
		vp.size = Vector2i(420, 560)
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		add_child(vp)
		var env := Environment.new()
		env.background_mode = Environment.BG_CLEAR_COLOR
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.62, 0.56, 0.5)
		env.ambient_light_energy = 0.9
		env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		var we := WorldEnvironment.new()
		we.environment = env
		vp.add_child(we)
		var sun := DirectionalLight3D.new()
		sun.light_color = Color(1.0, 0.86, 0.66)
		sun.light_energy = 1.7
		sun.rotation_degrees = Vector3(-28, 32, 0)
		vp.add_child(sun)
		var rim := DirectionalLight3D.new()
		rim.light_color = Color(0.55, 0.65, 1.0)
		rim.light_energy = 0.9
		rim.rotation_degrees = Vector3(-15, 200, 0)
		vp.add_child(rim)
		var cam := Camera3D.new()
		cam.fov = 28.0
		cam.position = Vector3(0, 1.0, 4.3)
		cam.rotation_degrees = Vector3(-2, 0, 0)
		vp.add_child(cam)
		cam.current = true
		pivot = Node3D.new()
		vp.add_child(pivot)
		# A soft gold ring under the feet.
		var disc := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.7
		cyl.bottom_radius = 0.7
		cyl.height = 0.02
		disc.mesh = cyl
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(0.85, 0.66, 0.31, 0.22)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		disc.material_override = mat
		vp.add_child(disc)

	func set_active(on: bool) -> void:
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED

	func load_model(keep: Array[String]) -> void:
		var yaw := pivot.rotation.y
		if model != null:
			pivot.remove_child(model)
			model.queue_free()
			model = null
		model = Assets.character("Player", 1.8, keep)
		model.scale *= Life.body_scale()
		pivot.add_child(model)
		pivot.rotation.y = yaw
		var ap: AnimationPlayer = Assets.animation_player(model)
		if ap != null:
			var pick := ""
			for n: String in ap.get_animation_list():
				if n == "Idle" or (pick == "" and n.to_lower().contains("idle")):
					pick = n
			if pick != "":
				ap.get_animation(pick).loop_mode = Animation.LOOP_LINEAR
				ap.play(pick)

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseMotion and (e.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			pivot.rotate_y((e as InputEventMouseMotion).relative.x * 0.012)
			accept_event()
		elif e is InputEventScreenDrag:
			pivot.rotate_y((e as InputEventScreenDrag).relative.x * 0.012)
			accept_event()


func build() -> void:
	var root := page_hbox(16)
	# Left: level, points, attributes.
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 300
	left.add_theme_constant_override("separation", 6)
	root.add_child(left)
	var lv := HBoxContainer.new()
	lv.add_theme_constant_override("separation", 12)
	left.add_child(lv)
	var lvl_col := VBoxContainer.new()
	lvl_col.add_theme_constant_override("separation", -4)
	lv.add_child(lvl_col)
	lvl_col.add_child(Kit.lbl("Level", 16, AF.TEXT_DIM))
	_level_num = Kit.lbl("1", 52, AF.TEXT, false, "title_bold")
	lvl_col.add_child(_level_num)
	var xp_col := VBoxContainer.new()
	xp_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	xp_col.alignment = BoxContainer.ALIGNMENT_CENTER
	xp_col.add_theme_constant_override("separation", 6)
	lv.add_child(xp_col)
	xp_col.add_child(Kit.lbl("Experience", 14, AF.TEXT_DIM))
	_xp_bar = Kit.bar(0.0, 16.0, AF.GOLD)
	xp_col.add_child(_xp_bar)
	var pts := HBoxContainer.new()
	pts.custom_minimum_size = Vector2(0, 40)
	pts.add_theme_constant_override("separation", 8)
	pts.add_child(Kit.lbl("Skill Points", 17, AF.TEXT))
	pts.add_child(Kit.hspacer())
	_points_val = Kit.lbl("0", 18, AF.GOLD_BRIGHT, false, "title")
	pts.add_child(_points_val)
	var pf := Kit.framed(pts, Color(0.03, 0.028, 0.025, 0.6), AF.GOLD_DIM, 4)
	pf.custom_minimum_size.y = 40
	left.add_child(pf)
	left.add_child(Kit.spacer(2))
	_attr_box = VBoxContainer.new()
	_attr_box.add_theme_constant_override("separation", 4)
	left.add_child(_attr_box)
	_attr_blurb = Kit.lbl("", 14, AF.TEXT_DIM, true, "italic")
	_attr_blurb.custom_minimum_size.y = 40
	left.add_child(_attr_blurb)
	# Centre: preview with slots either side.
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 6)
	root.add_child(mid)
	var stage := HBoxContainer.new()
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.add_theme_constant_override("separation", 8)
	mid.add_child(stage)
	_left_slots = _slot_column(MD.DOLL_LEFT)
	stage.add_child(_left_slots)
	_preview = Preview.new()
	stage.add_child(_preview)
	_right_slots = _slot_column(MD.DOLL_RIGHT)
	stage.add_child(_right_slots)
	var capbar := HBoxContainer.new()
	capbar.custom_minimum_size.y = 48
	capbar.alignment = BoxContainer.ALIGNMENT_CENTER
	capbar.add_theme_constant_override("separation", 12)
	mid.add_child(capbar)
	_caption = Kit.lbl("Drag to rotate", 16, AF.TEXT_DIM, false, "italic")
	_caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	capbar.add_child(_caption)
	_take_off = Kit.button("Take off", false, 48, 15)
	_take_off.pressed.connect(_do_take_off)
	_take_off.visible = false
	capbar.add_child(_take_off)
	# Right: skills summary, gear stats, View Skill Tree.
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 300
	right.add_theme_constant_override("separation", 4)
	root.add_child(right)
	right.add_child(Kit.section("Skills"))
	_skills_box = VBoxContainer.new()
	_skills_box.add_theme_constant_override("separation", 2)
	right.add_child(_skills_box)
	right.add_child(Kit.section("Equipment Stats", 16))
	_stats_box = VBoxContainer.new()
	_stats_box.add_theme_constant_override("separation", 1)
	right.add_child(_stats_box)
	right.add_child(Kit.hspacer())
	var vb := Kit.button("View Skill Tree", false, 48, 16)
	vb.pressed.connect(func() -> void: menu.call("open_tab", "skills"))
	right.add_child(vb)
	Life.inventory_changed.connect(func() -> void:
		if is_visible_in_tree():
			refresh())


func _slot_column(slots: Array) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 12)
	for sname: String in slots:
		var s := Kit.slot(72)
		s.empty_icon = "slot_" + sname
		s.pressed.connect(_select_slot.bind(sname))
		col.add_child(s)
		_slot_nodes[sname] = s
	return col


func on_show() -> void:
	_sel_slot = ""
	refresh()
	_preview.set_active(true)


func on_hide() -> void:
	_preview.set_active(false)


func refresh() -> void:
	var lvl := Life.player_level()
	var info := MD.level_info(Game.merit, lvl)
	_level_num.text = str(lvl)
	_xp_bar.set_ratio(float(info["ratio"]))
	_xp_bar.text = "%s / %s" % [_th(int(info["into"])), _th(int(info["needed"]))]
	_points_val.text = str(int(Life.skills.points))
	Kit.clear(_attr_box)
	for a: Dictionary in MD.attributes(Life.mastery, lvl):
		var r := Kit.row(String(a["name"]), "attr_" + String(a["id"]), str(a["value"]), "", 48)
		r.pressed.connect(func() -> void: _attr_blurb.text = String(a["blurb"]))
		_attr_box.add_child(r)
	if _attr_blurb.text == "":
		_attr_blurb.text = "Attributes are derived from what you practise (see the Skills tab)."
	# Equipment slots.
	for sname: String in _slot_nodes:
		var s: Kit.Slot = _slot_nodes[sname]
		var d := MD.doll_slot(sname)
		s.locked = not bool(d["available"])
		s.disabled = s.locked
		s.selected = sname == _sel_slot
		var id := String(d["id"])
		if id != "":
			var r := MD.rarity_of(id, int(d["quality"]))
			s.set_item(id, 0, MD.rarity_color(r) if r != 0 else Color(0, 0, 0, 0), Kit.CATEGORY_TINT.get(MD.category_of(id), AF.TEXT))
		else:
			s.set_item("")
		s.queue_redraw()
	_update_caption()
	# Skills summary.
	Kit.clear(_skills_box)
	for sk: Dictionary in MD.skill_summary(Life.mastery, Life.skills, Life.soul):
		var r2 := Kit.row(String(sk["name"]), String(sk["icon"]), str(sk["value"]), "", 48, true)
		r2.pressed.connect(func() -> void: menu.call("open_tab", "skills"))
		_skills_box.add_child(r2)
	# Gear stats.
	Kit.clear(_stats_box)
	var st: Dictionary = Life.equipment.call("stats", WorldSim.day * 24.0 + WorldSim.time_of_day)
	for pair: Array in [["stat_armour", "Armour", str(int(round(float(st["armour"]))))],
			["stat_damage", "Damage bonus", "+%d" % int(round(float(st["damage"])))],
			["stat_speed", "Speed", "%+d%%" % int(round(float(st["speed"]) * 100.0))]]:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		h.custom_minimum_size.y = 26
		h.add_child(Kit.tex_rect(Kit.icon(String(pair[0])), 18, AF.TEXT_DIM))
		h.add_child(Kit.lbl(String(pair[1]), 16, AF.TEXT_DIM))
		h.add_child(Kit.hspacer())
		h.add_child(Kit.lbl(String(pair[2]), 17, AF.TEXT, false, "title"))
		_stats_box.add_child(h)
	_rebuild_model()
	hints_changed()


static func _th(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	for i in s.length():
		if i > 0 and (s.length() - i) % 3 == 0:
			out += ","
		out += s[i]
	return out


func _rebuild_model() -> void:
	var keep: Array[String] = []
	for slot: String in MODEL_PROPS:
		if String(Life.equipment.call("item_in", slot)) != "":
			keep.append(String(MODEL_PROPS[slot]))
	var key := ",".join(keep)
	if key == _props_key and _preview.model != null:
		return
	_props_key = key
	_preview.load_model(keep)


func _select_slot(sname: String) -> void:
	_sel_slot = "" if _sel_slot == sname else sname
	for n: String in _slot_nodes:
		(_slot_nodes[n] as Kit.Slot).selected = n == _sel_slot
		(_slot_nodes[n] as Kit.Slot).queue_redraw()
	_update_caption()


func _update_caption() -> void:
	_take_off.visible = false
	if _sel_slot == "":
		_caption.text = "Drag to rotate"
		_caption.add_theme_color_override("font_color", AF.TEXT_DIM)
		return
	var d := MD.doll_slot(_sel_slot)
	if not bool(d["available"]):
		_caption.text = "%s: this game has no such slot yet." % d["label"]
		return
	if String(d["id"]) == "":
		_caption.text = "%s: nothing worn. Equip gear from the Inventory." % d["label"]
		return
	var det := MD.item_detail(String(d["id"]), int(d["quality"]), int(d["durability"]))
	_caption.text = "%s  ·  %s" % [det["name"], det["rarity_name"]]
	_caption.add_theme_color_override("font_color", det["rarity_color"])
	_take_off.visible = true


func _do_take_off() -> void:
	if _sel_slot == "":
		return
	Life.equipment.call("unequip_to", Life, _sel_slot)
	Audio.play_ui("pickup")
	_sel_slot = ""
	refresh()


func hints() -> Array:
	return [["K", "Skill Tree", func() -> void: menu.call("open_tab", "skills"), false],
		["I", "Inventory", func() -> void: menu.call("open_tab", "inventory"), false]]
