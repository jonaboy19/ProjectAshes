extends Control
## Palworld-style build mode for the modular kit, made for thumbs (docs/design/RETINUE_SETTLEMENT_ASCENSION.md 4.9, L35).
##   Bottom tray: category tabs (Foundations .. Roads, Blueprints) and the pieces with their cost (red = missing, grey = locked).
##   One-finger drag on the world moves the ghost; it snaps to the 2 m cells / wall edges / storeys (props: 0.5 m, 15 deg).
##   Ghost colours: green = placeable, amber = a plan (materials missing: the crew will build it), red = blocked (reason chip).
##   Right thumb column: rotate, storey up / down, place (check), cancel. Left column: Plan, Remove, Crew, Undo, Done.
##   Remove: aim at a piece, place removes it (50 % refund; pieces that lose support fall, 25 % refund each).
##   Roads: pick a road tier and draw with a finger; the stroke is smoothed (scripts/build/road_tool.gd); place pays for it.
##   Crew: every loose plan becomes one construction site (construction.place_kit_plan) that the existing crews raise.
## Open from the build menu ("Free build" tab) or BuildMode.open_for(hud). The lab drives it directly (tools_qa/build_lab).

signal closed

const SELF_PATH := "res://scripts/build/build_mode.gd"
const BuildKit := preload("res://scripts/realm/build_kit.gd")
const KitMeshes := preload("res://scripts/build/kit_meshes.gd")
const RoadTool := preload("res://scripts/build/road_tool.gd")
const Renderer := preload("res://scripts/build/build_renderer.gd")
const BTN := 64
const REACH := 7.0
const UNDO_MAX := 20

var hud: Node
var kit: RefCounted
var camera: Camera3D
var world: Node3D
var player: Node3D
var renderer: Node3D

var gid := 0
var mode := "piece"                    # piece | remove | blueprint | road
var kind := ""
var blueprint := ""
var road_tier := "dirt"
var rot := 0
var level := 0
var plan_mode := false
var aim_screen := Vector2(-1, -1)      # (-1,-1) = in front of the player / screen centre
var last_snap := {}
var last_check := {}
var _cat := "foundation"
var _ghost: MeshInstance3D
var _undo: Array = []                  # [gid, pid]
var _stroke: Array = []                # road stroke (world points)
var _touches := {}
var _twist_ref := 0.0
var _dragging := false
var _status: Label
var _cost: Label
var _tray_tabs: HBoxContainer
var _tray_items: HBoxContainer
var _btn_plan: Button
var _btn_remove: Button
var _btn_place: Button
var _remove_pick := 0


static func open_for(host: Node) -> Control:
	var s: Control = host.get_node_or_null("BuildMode")
	if s == null:
		s = (load(SELF_PATH) as GDScript).new()
		s.name = "BuildMode"
		host.add_child(s)
	if host.has_method("close_menu"):
		host.call("close_menu")
	s.set("hud", host)
	s.call("open")
	return s


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists("res://scripts/ui/ui_theme.gd"):
		theme = UITheme.theme()
	_build_ui()
	visible = false


func open() -> void:
	if kit == null and Life.get("realm") != null:
		kit = Life.realm.mod("build_kit")
	if camera == null:
		camera = get_viewport().get_camera_3d()
	if world == null:
		var main: Node = get_tree().current_scene
		world = main.get("world") if main != null and main.get("world") is Node3D else main as Node3D
	if player == null:
		player = get_tree().get_first_node_in_group("player") as Node3D
	if renderer == null and world != null:
		renderer = world.get_node_or_null("BuildKitView")
		if renderer == null:
			renderer = Renderer.new()
			renderer.name = "BuildKitView"
			renderer.set("kit", kit)
			world.add_child(renderer)
	if kit != null and not WorldGen.settlements.is_empty():
		kit.height_fn = func(x: float, z: float) -> float: return WorldGen.height(x, z)
	if hud != null and hud.get("controls") != null:
		(hud.get("controls") as Control).visible = false
	visible = true
	gid = kit.grid_at(_aim_world()) if kit != null else 0
	select_category(_cat)
	_say("")


func close() -> void:
	visible = false
	if _ghost:
		_ghost.queue_free()
		_ghost = null
	if hud != null and hud.get("controls") != null:
		(hud.get("controls") as Control).visible = true
	closed.emit()


# ------------------------------------------------------------------ UI

func _btn(text: String, cb: Callable, w := BTN, h := BTN) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(w, h)
	b.add_theme_font_size_override("font_size", 22 if text.length() <= 2 else 15)
	b.pressed.connect(cb)
	return b


func _build_ui() -> void:
	var top := PanelContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	top.position.y = 12
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tv := VBoxContainer.new()
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 18)
	_cost = Label.new()
	_cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cost.add_theme_font_size_override("font_size", 15)
	tv.add_child(_status)
	tv.add_child(_cost)
	top.add_child(tv)
	add_child(top)
	top.resized.connect(func() -> void: top.position.x = (size.x - top.size.x) * 0.5)

	var tray := PanelContainer.new()
	tray.anchor_left = 0.0
	tray.anchor_right = 1.0
	tray.anchor_top = 1.0
	tray.anchor_bottom = 1.0
	tray.offset_top = -168
	tray.offset_left = 8
	tray.offset_right = -8
	tray.offset_bottom = -8
	add_child(tray)
	var tcol := VBoxContainer.new()
	tray.add_child(tcol)
	var ts := ScrollContainer.new()
	ts.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ts.custom_minimum_size.y = 50
	_tray_tabs = HBoxContainer.new()
	ts.add_child(_tray_tabs)
	tcol.add_child(ts)
	var cats: Dictionary = BuildKit.catalog().get("category_names", {})
	for c: String in BuildKit.catalog().get("categories", []):
		var cc := c
		_tray_tabs.add_child(_btn(String(cats.get(c, c)), func() -> void: select_category(cc), 132, 46))
	_tray_tabs.add_child(_btn("Blueprints", func() -> void: select_category("blueprints"), 132, 46))
	_tray_tabs.add_child(_btn("Draw road", func() -> void: select_category("roads"), 132, 46))
	var is_ := ScrollContainer.new()
	is_.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	is_.custom_minimum_size.y = 96
	_tray_items = HBoxContainer.new()
	is_.add_child(_tray_items)
	tcol.add_child(is_)

	var right := VBoxContainer.new()
	right.anchor_left = 1.0
	right.anchor_right = 1.0
	right.anchor_top = 1.0
	right.anchor_bottom = 1.0
	right.offset_left = -(BTN + 20)
	right.offset_right = -12
	right.offset_top = -176 - 5 * (BTN + 8)
	right.offset_bottom = -180
	right.add_theme_constant_override("separation", 8)
	right.add_child(_btn("⟳", rotate_piece))
	right.add_child(_btn("▲", func() -> void: set_level(level + 1)))
	right.add_child(_btn("▼", func() -> void: set_level(level - 1)))
	_btn_place = _btn("✓", confirm)
	_btn_place.add_theme_color_override("font_color", Color(0.4, 1.0, 0.45))
	right.add_child(_btn_place)
	right.add_child(_btn("✗", cancel))
	add_child(right)

	var left := VBoxContainer.new()
	left.anchor_top = 1.0
	left.anchor_bottom = 1.0
	left.offset_left = 12
	left.offset_right = 12 + 104
	left.offset_top = -176 - 5 * (BTN + 8)
	left.offset_bottom = -180
	left.add_theme_constant_override("separation", 8)
	_btn_plan = _btn("Plan", toggle_plan, 104)
	_btn_plan.toggle_mode = true
	left.add_child(_btn_plan)
	_btn_remove = _btn("Remove", func() -> void: set_mode("piece" if mode == "remove" else "remove"), 104)
	_btn_remove.toggle_mode = true
	left.add_child(_btn_remove)
	left.add_child(_btn("Crew", hand_to_crew, 104))
	left.add_child(_btn("Undo", undo, 104))
	left.add_child(_btn("Done", close, 104))
	add_child(left)


func select_category(c: String) -> void:
	_cat = c
	for ch in _tray_items.get_children():
		ch.queue_free()
	if c == "blueprints":
		for bp: String in BuildKit.catalog().get("blueprints", {}):
			var bb := bp
			var d: Dictionary = BuildKit.catalog()["blueprints"][bp]
			_tray_items.add_child(_btn("%s\n%d pieces" % [d["name"], (d["pieces"] as Array).size()], func() -> void: pick_blueprint(bb), 170, 84))
		return
	if c == "roads":
		for t: String in BuildKit.catalog().get("roads", {}):
			var tt := t
			var rd := BuildKit.road_def(t)
			_tray_items.add_child(_btn("%s\n%s / 10 m" % [rd["name"], _cost_text(rd.get("cost_per_10m", {}))], func() -> void: pick_road(tt), 170, 84))
		return
	for k: String in BuildKit.kinds_in(c):
		var kk := k
		var d := BuildKit.def(k)
		var b := _btn("%s\n%s" % [d["name"], _cost_text(d.get("cost", {}))], func() -> void: pick(kk), 170, 84)
		if kit != null and not kit.knows(String(d.get("know", ""))):
			b.modulate = Color(0.6, 0.6, 0.6)
			b.tooltip_text = "Learn %s" % String(d["know"]).trim_prefix("build:")
		elif kit != null and not kit.missing_for(d.get("cost", {})).is_empty():
			b.add_theme_color_override("font_color", Color(1.0, 0.72, 0.4))
		_tray_items.add_child(b)


static func _cost_text(cost: Dictionary) -> String:
	if cost.is_empty():
		return "free"
	var parts: PackedStringArray = []
	for item: String in cost:
		parts.append("%d %s" % [int(cost[item]), item.replace("_", " ")])
	return ", ".join(parts)


func _say(t: String, col := Color(1, 1, 1)) -> void:
	if _status:
		_status.text = t
		_status.add_theme_color_override("font_color", col)


# ------------------------------------------------------------------ actions (public so the lab and tests drive them)

func pick(k: String) -> void:
	kind = k
	set_mode("piece")
	var d := BuildKit.def(k)
	level = maxi(level, int(d.get("min_level", 0)))
	if bool(d.get("ground_only", false)) or String(d.get("layer", "")) == "foundation":
		level = 0
	_ensure_ghost()


func pick_blueprint(bp: String) -> void:
	blueprint = bp
	set_mode("blueprint")
	_ensure_ghost()


func pick_road(t: String) -> void:
	road_tier = t
	_stroke.clear()
	set_mode("road")


func set_mode(m: String) -> void:
	mode = m
	if _btn_remove:
		_btn_remove.button_pressed = m == "remove"
	if m != "road":
		_stroke.clear()
	_ensure_ghost()


func toggle_plan() -> void:
	plan_mode = not plan_mode
	if _btn_plan:
		_btn_plan.button_pressed = plan_mode


func rotate_piece() -> void:
	rot += 1


func set_level(l: int) -> void:
	level = clampi(l, 0, BuildKit.MAX_LEVEL)


func cancel() -> void:
	if mode == "road" and not _stroke.is_empty():
		_stroke.clear()
		return
	kind = ""
	blueprint = ""
	set_mode("piece")
	_say("")


func undo() -> void:
	while not _undo.is_empty():
		var u: Array = _undo.pop_back()
		if kit.grids.has(int(u[0])) and (kit.grids[int(u[0])]["pieces"] as Dictionary).has(int(u[1])):
			kit.remove(int(u[0]), int(u[1]), 1.0)
			_say("Undone.")
			return


func hand_to_crew() -> void:
	if gid == 0:
		_say("No settlement here.", Color(1, 0.5, 0.4))
		return
	var r: Dictionary = kit.hand_to_workers(gid)
	if bool(r["ok"]):
		_say("%d planned pieces handed to the crew (site %d). Hire builders at the site." % [r["pieces"], r["site"]], Color(0.6, 0.9, 1.0))
	else:
		_say(String(r["reason"]), Color(1, 0.6, 0.4))


## The check button: found a settlement, place a piece / blueprint, remove the aimed piece, or pay for the drawn road.
func confirm() -> void:
	if kit == null:
		return
	var aim := _aim_world()
	if gid == 0 or not kit.grids.has(gid):
		gid = kit.grid_at(aim)
	if gid == 0:
		var f: Dictionary = kit.ensure_grid(aim)
		if not bool(f["ok"]):
			_say(String(f["reason"]), Color(1, 0.4, 0.35))
			return
		gid = int(f["gid"])
		_say("Founded %s. Lay foundations first." % kit.grids[gid]["name"], Color(0.6, 1.0, 0.6))
		return
	match mode:
		"remove":
			if _remove_pick > 0:
				var r: Dictionary = kit.remove(gid, _remove_pick)
				_say("Removed. Refund: %s%s" % [_cost_text(r["refund"]), ("  (%d pieces fell)" % (r["collapsed"] as Array).size()) if not (r["collapsed"] as Array).is_empty() else ""])
				_remove_pick = 0
		"blueprint":
			if blueprint == "":
				return
			var s: Dictionary = kit.snap_world(gid, "foundation_timber", aim, 0, 0)
			var r2: Dictionary = kit.place_blueprint(gid, blueprint, int(s["i"]), int(s["k"]), posmod(rot, 4))
			_say("%s: %d pieces laid as plans%s. Tap Crew to have them built." % [BuildKit.catalog()["blueprints"][blueprint]["name"], r2["placed"],
				(", %d blocked" % int(r2["failed"])) if int(r2["failed"]) > 0 else ""], Color(1.0, 0.85, 0.5))
		"road":
			if _stroke.size() < 2:
				_say("Drag a finger across the ground to draw the road.")
				return
			var ends: Array = []
			for road: Dictionary in kit.grids[gid]["roads"]:
				for idx in [0, (road["pts"] as Array).size() - 1]:
					var a: Array = road["pts"][idx]
					ends.append(kit.to_world(gid, Vector3(float(a[0]), float(a[1]), float(a[2]))))
			var pts := RoadTool.process(_stroke, ends)
			var r3: Dictionary = kit.add_road(gid, road_tier, pts)
			_say("Road laid." if bool(r3["ok"]) else String(r3["reason"]), Color(0.6, 1.0, 0.6) if bool(r3["ok"]) else Color(1, 0.5, 0.4))
			_stroke.clear()
		_:
			if kind == "" or last_snap.is_empty():
				return
			var r4: Dictionary = kit.place(gid, last_snap, plan_mode)
			if bool(r4["ok"]):
				_undo.append([gid, int(r4["id"])])
				if _undo.size() > UNDO_MAX:
					_undo.pop_front()
				if OS.has_feature("mobile"):
					Input.vibrate_handheld(18)
				_say("Plan laid: the crew will build it." if bool(r4.get("plan", false)) else "Built.", Color(1.0, 0.85, 0.5) if bool(r4.get("plan", false)) else Color(0.6, 1.0, 0.6))
			else:
				_say(String(r4["reason"]), Color(1, 0.45, 0.35))
	if renderer != null:
		renderer.call("rebuild_all")
	select_category(_cat)


# ------------------------------------------------------------------ aiming and the ghost

func _ensure_ghost() -> void:
	if _ghost == null and world != null:
		_ghost = MeshInstance3D.new()
		_ghost.name = "BuildGhost"
		_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		world.add_child(_ghost)
	if _ghost == null:
		return
	match mode:
		"piece":
			_ghost.mesh = KitMeshes.mesh(kind, 1) if kind != "" else null
		"blueprint":
			var b := BoxMesh.new()
			b.size = Vector3(4, 0.4, 4)
			_ghost.mesh = b
		_:
			_ghost.mesh = null


func _plane_y() -> float:
	var base := 0.0
	if kit != null and gid > 0 and kit.grids.has(gid):
		base = kit.to_world(gid, Vector3.ZERO).y
	elif player != null:
		base = player.global_position.y
	return base + (BuildKit.level_y(level) if level > 0 else 0.0)


func _aim_world() -> Vector3:
	if camera == null:
		return player.global_position if player != null else Vector3.ZERO
	var sp := aim_screen
	if sp.x < 0.0:
		if player != null:
			var fwd := -player.global_transform.basis.z
			fwd.y = 0.0
			return player.global_position + fwd.normalized() * REACH
		sp = get_viewport().get_visible_rect().size * Vector2(0.5, 0.55)
	var o := camera.project_ray_origin(sp)
	var d := camera.project_ray_normal(sp)
	var py := _plane_y()
	if absf(d.y) < 0.0001:
		return o + d * 20.0
	var t := (py - o.y) / d.y
	return o + d * maxf(t, 0.0)


func _process(_delta: float) -> void:
	if not visible or kit == null:
		return
	var aim := _aim_world()
	if gid == 0 or not kit.grids.has(gid):
		gid = kit.grid_at(aim)
	if gid == 0:
		_say("No settlement here: tap ✓ to found one (%d of %d)." % [kit.grids.size(), BuildKit.MAX_GRIDS])
		if _ghost:
			_ghost.visible = false
		return
	match mode:
		"piece":
			if kind == "":
				_ghost.visible = false
				_cost.text = "Pick a piece from the tray."
				return
			last_snap = kit.snap_world(gid, kind, aim, rot, level)
			last_check = kit.check(gid, last_snap, plan_mode)
			var state := "ok"
			if not bool(last_check["ok"]):
				state = "plan" if bool(last_check["plan"]) else "bad"
			elif plan_mode or bool(last_check["plan"]):
				state = "plan"
			_ghost.visible = true
			_ghost.mesh = KitMeshes.mesh(kind, 1)
			_ghost.material_override = KitMeshes.ghost_material(state)
			_ghost.global_transform = Transform3D(Basis(Vector3.UP, float(last_snap["yaw"])), last_snap["world"])
			var d := BuildKit.def(kind)
			_cost.text = "%s  ·  %s  ·  storey %d  ·  tier %d" % [d["name"], _cost_text(d.get("cost", {})), int(last_snap["L"]), int(d.get("tier", 0))]
			if state == "ok":
				_say("Support %d%%" % roundi(float(last_check["integrity"]) * 100.0), Color(0.6, 1.0, 0.6))
			elif state == "plan" and bool(last_check["ok"]):
				_say("Plan: the crew builds it when materials arrive.", Color(1.0, 0.85, 0.5))
			else:
				_say(String(last_check["reason"]), Color(1.0, 0.5, 0.4) if state == "bad" else Color(1.0, 0.85, 0.5))
		"remove":
			_remove_pick = _nearest_piece(aim)
			if _remove_pick > 0:
				var r: Dictionary = kit.grids[gid]["pieces"][_remove_pick]
				_ghost.visible = true
				_ghost.mesh = KitMeshes.mesh(String(r["kind"]), 1)
				_ghost.material_override = KitMeshes.ghost_material("bad")
				_ghost.global_transform = Transform3D(Renderer.piece_transform(r).basis, kit.to_world(gid, Renderer.piece_transform(r).origin)).scaled_local(Vector3.ONE * 1.02)
				_say("Remove %s? ✓ = yes (half the materials back)" % BuildKit.def(String(r["kind"]))["name"], Color(1.0, 0.6, 0.5))
			else:
				_ghost.visible = false
				_say("Aim at a piece to remove it.")
		"blueprint":
			var s: Dictionary = kit.snap_world(gid, "foundation_timber", aim, 0, 0)
			_ghost.visible = true
			_ghost.material_override = KitMeshes.ghost_material("plan")
			_ghost.global_transform = Transform3D(Basis(Vector3.UP, posmod(rot, 4) * PI * 0.5), (s["world"] as Vector3) + Basis(Vector3.UP, posmod(rot, 4) * PI * 0.5) * Vector3(1, 0.2, 1))
			_cost.text = "%s: %s" % [BuildKit.catalog()["blueprints"][blueprint]["name"], BuildKit.catalog()["blueprints"][blueprint]["desc"]] if blueprint != "" else "Pick a blueprint."
			_say("✓ lays it as plans; Crew hands the plans to builders.", Color(1.0, 0.85, 0.5))
		"road":
			if _ghost:
				_ghost.visible = false
			var rc: Dictionary = kit.road_cost(road_tier, _stroke)
			_cost.text = "%s: %.0f m  ·  %s" % [BuildKit.road_def(road_tier)["name"], BuildKit.polyline_length(_stroke), _cost_text(rc["cost"])]
			_say("Drag to draw, ✓ to build, ✗ to clear.")


func _nearest_piece(aim: Vector3) -> int:
	var best := 0
	var bd := 2.0
	var local: Vector3 = kit.to_local(gid, aim)
	for pid: int in kit.grids[gid]["pieces"]:
		var r: Dictionary = kit.grids[gid]["pieces"][pid]
		if absi(int(r["L"]) - level) > 0:
			continue
		var p: Array = r["p"]
		var dd := Vector2(float(p[0]) - local.x, float(p[2]) - local.z).length()
		if dd < bd:
			bd = dd
			best = pid
	return best


# ------------------------------------------------------------------ touch

func _unhandled_input(e: InputEvent) -> void:
	if not visible:
		return
	if e is InputEventScreenTouch:
		var t := e as InputEventScreenTouch
		if t.pressed:
			_touches[t.index] = t.position
		else:
			_touches.erase(t.index)
		if _touches.size() == 2:
			_twist_ref = _twist_angle()
		if _touches.size() == 1 and t.pressed:
			aim_screen = t.position
			if mode == "road":
				_stroke.append(_aim_world())
		get_viewport().set_input_as_handled()
	elif e is InputEventScreenDrag:
		var dr := e as InputEventScreenDrag
		_touches[dr.index] = dr.position
		if _touches.size() >= 2:
			var a := _twist_angle()
			if absf(angle_difference(_twist_ref, a)) > PI / 5.0:     # two-finger twist: a quarter turn
				rot += 1 if angle_difference(_twist_ref, a) > 0.0 else -1
				_twist_ref = a
		else:
			aim_screen = dr.position
			if mode == "road":
				var p := _aim_world()
				if _stroke.is_empty() or (_stroke[-1] as Vector3).distance_to(p) > 1.0:
					_stroke.append(p)
		get_viewport().set_input_as_handled()
	elif e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_dragging = (e as InputEventMouseButton).pressed
		aim_screen = (e as InputEventMouseButton).position
	elif e is InputEventMouseMotion and _dragging:
		aim_screen = (e as InputEventMouseMotion).position
		if mode == "road":
			var p2 := _aim_world()
			if _stroke.is_empty() or (_stroke[-1] as Vector3).distance_to(p2) > 1.0:
				_stroke.append(p2)
	elif e is InputEventKey and (e as InputEventKey).pressed:
		match (e as InputEventKey).keycode:
			KEY_R:
				rotate_piece()
			KEY_PAGEUP:
				set_level(level + 1)
			KEY_PAGEDOWN:
				set_level(level - 1)
			KEY_ENTER, KEY_KP_ENTER:
				confirm()
			KEY_ESCAPE:
				cancel()


func _twist_angle() -> float:
	var ks := _touches.keys()
	if ks.size() < 2:
		return 0.0
	return ((_touches[ks[1]] as Vector2) - (_touches[ks[0]] as Vector2)).angle()
