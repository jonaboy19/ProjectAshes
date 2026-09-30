extends RefCounted
## The settlement half of the build menu (scripts/ui/build_menu.gd hosts it): the tiered catalogue with locked
## entries showing what they still need and costs against your stock, the placement ghost (drag it, rotate,
## confirm), the list of holdings and sites, and the site panel: stage, progress, workers, ETA, missing
## materials, assign/hire builders and haulers, deposit, learn, upgrade.
## Everything reads and writes scripts/realm/construction.gd through Life.realm.mod("construction").

const D := preload("res://scripts/realm/construction_data.gd")
const Nav := preload("res://scripts/realm/construction_nav.gd")
const W := preload("res://scripts/ui/build_widgets.gd")
const REACH := 7.0
const TIER_SHORT := ["Survival", "Camp", "Village", "Town", "Seat"]
const GRID_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
uniform vec4 col : source_color = vec4(1.0, 1.0, 1.0, 0.6);
uniform float cell = 2.0;
uniform float radius = 7.0;
varying vec3 wp;
varying vec2 lp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; lp = VERTEX.xz; }
void fragment() {
	vec2 g = abs(fract(wp.xz / cell + 0.5) - 0.5) * cell;
	float line = 1.0 - smoothstep(0.0, 0.06, min(g.x, g.y));
	float fade = 1.0 - smoothstep(radius * 0.35, radius, length(lp));
	ALBEDO = col.rgb;
	ALPHA = line * fade * col.a;
}
"""

var menu: Control
var tier := 0
var kind := ""              # the blueprint being placed ("" = none)
var upgrade_of := 0         # site being upgraded by the blueprint
var rot := 0.0
var snap_on := true
var site_id := 0            # the site whose panel is open (0 = none)
var dragged := false
var ghost: Node3D
var ghost_mesh: MeshInstance3D
var ghost_box: MeshInstance3D
var ghost_frame: Node3D
var ghost_arrow: MeshInstance3D
var ghost_label: Label3D
var grid: MeshInstance3D
var _grid_mat: ShaderMaterial
var _frame_ok: StandardMaterial3D
var _frame_bad: StandardMaterial3D
var _ok := false
var _pulse := 0.0
var _pos := Vector2.ZERO
var _green: StandardMaterial3D
var _red: StandardMaterial3D
var _refresh_timer := 0.0
var _last_reason := ""


func _init(p_menu: Control) -> void:
	menu = p_menu


func get_process_delta() -> float:
	return menu.get_process_delta_time()


func cons() -> RefCounted:
	return Life.realm.mod("construction")


func _player() -> Node3D:
	return menu.call("_player")


func _pp() -> Vector2:
	var p := _player()
	return Vector2(p.global_position.x, p.global_position.z) if p != null else Vector2.ZERO


func _view() -> Node:
	return menu.get_tree().get_first_node_in_group("construction_view")


func _say(t: String, ok := true) -> void:
	menu.call("set_status", t, ok)


# --- catalogue ---------------------------------------------------------------------------

func _btn(text: String, cb: Callable, min_w := 0) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(min_w, 44)
	b.pressed.connect(cb)
	return b


func _label(text: String, dim := false, size := 14) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	if dim:
		l.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	return l


func _rich(bb: String) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_theme_font_size_override("normal_font_size", 13)
	r.text = bb
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return r


## Cost line coloured by what you have: "[color]3/10 log[/color]".
func cost_bb(k: String, upgrade := false) -> String:
	var c := cons()
	var cost: Dictionary = c.costs_for(k, upgrade)
	var parts := PackedStringArray()
	var pos := _pp()
	for item: String in D.MATERIAL_ORDER:
		if not cost.has(item):
			continue
		var have: int = c.available(item, pos)
		var need := int(cost[item])
		var col := "#8fdc8f" if have >= need else ("#e0c060" if have >= int(ceil(need * D.START_SHARE)) else "#e07070")
		parts.append("[color=%s]%d/%d %s[/color]" % [col, have, need, String(D.MATERIALS.get(item, item)).to_lower()])
	return "  ".join(parts)


## Cost chips [text, state] for kind `k` against what you hold here (inventory + stockpile).
func cost_parts(k: String, upgrade := false) -> Array:
	var c := cons()
	var cost: Dictionary = c.costs_for(k, upgrade)
	var out: Array = []
	var pos := _pp()
	for item: String in D.MATERIAL_ORDER:
		if not cost.has(item):
			continue
		var have: int = c.available(item, pos)
		var need := int(cost[item])
		var state := "ok" if have >= need else ("some" if have >= int(ceil(need * D.START_SHARE)) else "short")
		out.append(["%d/%d %s" % [have, need, String(D.MATERIALS.get(item, item)).to_lower()], state])
	return out


func fill_catalog(list: VBoxContainer) -> void:
	var c := cons()
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	for t in 5:
		var open: bool = t == 0 or c.tier_built(t - 1) + int(c.external.get("_any", 0)) >= 1
		var b := _btn(("" if open else "🔒 ") + String(TIER_SHORT[t]), func() -> void:
			tier = t
			menu.call("_refresh_list"), 0)
		b.toggle_mode = true
		b.button_pressed = t == tier
		b.add_theme_font_size_override("font_size", 13)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.tooltip_text = String(D.TIER_NAMES[t])
		tabs.add_child(b)
	list.add_child(tabs)
	var pos := _pp()
	for k: String in D.kinds_of_tier(tier):
		var d: Dictionary = D.CATALOG[k]
		var needs: Array = c.missing_needs(k)
		var locked := not needs.is_empty()
		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(0, 58)
		row.add_theme_constant_override("separation", 8)
		var ic := W.icon(k, String(d["role"]), 44)
		ic.set("locked", locked)
		row.add_child(ic)
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 2)
		var skill := float(d.get("min_skill", 0.0))
		var head := _label("%s   %dh labour%s" % [String(d["name"]), int(d["hours"]),
			"   skill %d" % int(round(skill * 100.0)) if skill > 0.0 else ""], false, 15)
		head.add_theme_color_override("font_color", UITheme.ACCENT if not locked else UITheme.TEXT_DIM)
		col.add_child(head)
		col.add_child(W.chips(cost_parts(k)))
		if locked:
			col.add_child(W.locked_banner(needs))
		else:
			col.add_child(_label(String(d["desc"]), true, 12))
		row.add_child(col)
		var place := _btn("Place" if not locked else "🔒", func() -> void: begin_place(k), 80)
		place.disabled = locked
		place.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(place)
		list.add_child(row)
		list.add_child(HSeparator.new())
	# what you know
	var known := PackedStringArray()
	for f: String in D.KNOW_NAMES:
		if c.knows(f):
			known.append(String(D.KNOW_NAMES[f]))
	list.add_child(_label("Know-how: %s" % (", ".join(known) if not known.is_empty() else "nothing yet. Build a workbench to learn carpentry."), true, 12))
	if pos != Vector2.ZERO:
		var hid: int = c.holding_at(pos)
		if hid > 0:
			list.add_child(_label("Here: %s" % _holding_line(hid), true, 12))


func _holding_line(hid: int) -> String:
	var h: Dictionary = cons().holding_info(hid)
	return "%s (%s), %d buildings, %d people, %d beds" % [h["name"], String(h["level_name"]).to_lower(), int(h["buildings"]), int(h["pop"]), int(h["beds"])]


# --- placement ---------------------------------------------------------------------------

func begin_place(k: String, upgrade_site := 0) -> void:
	kind = k
	upgrade_of = upgrade_site
	dragged = false
	rot = 0.0
	if upgrade_site > 0:
		var s: Dictionary = cons().sites.get(upgrade_site, {})
		if not s.is_empty():
			_pos = cons().site_pos(s)
			rot = float(s["yaw"])
			dragged = true
	site_id = 0
	_ensure_ghost()
	_say("Drag the ghost (or walk) to a spot. Green means you can build there.")
	menu.call("_refresh_list")


func cancel_place() -> void:
	kind = ""
	upgrade_of = 0
	if ghost != null:
		ghost.queue_free()
		ghost = null
	if grid != null:
		grid.queue_free()
		grid = null
	menu.call("_refresh_list")


func rotate_ghost() -> void:
	rot = fposmod(rot + PI * 0.25, TAU)
	menu.call("refresh_place_row")


func toggle_snap() -> void:
	snap_on = not snap_on
	_say("Grid snap %s." % ("on: the blueprint jumps to a 2 m grid" if snap_on else "off: free placement"))
	menu.call("refresh_place_row")


func _ensure_ghost() -> void:
	var p := _player()
	if p == null:
		return
	if ghost != null:
		ghost.queue_free()
	if grid != null:
		grid.queue_free()
		grid = null
	ghost = Node3D.new()
	p.get_parent().add_child(ghost)
	_green = StandardMaterial3D.new()
	_green.albedo_color = Color(0.35, 0.95, 0.5, 0.5)
	_green.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_green.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_red = _green.duplicate()
	_red.albedo_color = Color(0.95, 0.3, 0.3, 0.5)
	ghost_box = MeshInstance3D.new()
	ghost_box.mesh = BoxMesh.new()
	ghost_box.material_override = _green
	ghost.add_child(ghost_box)
	ghost_mesh = MeshInstance3D.new()
	ghost.add_child(ghost_mesh)
	_build_ghost_extras(p)
	var v := _view()
	if v != null and kind != "":
		var b: Dictionary = v.call("_building_mesh", kind)
		if not b.is_empty():
			ghost_mesh.mesh = b["mesh"]
			ghost_mesh.position = b["offset"]
			ghost_mesh.scale = Vector3.ONE * float(b["scale"])
			ghost_mesh.material_override = _green
	var pp := _pp()
	var fwd: Vector3 = p.forward() if p.has_method("forward") else -p.global_transform.basis.z
	_pos = pp + Vector2(fwd.x, fwd.z).normalized() * (REACH + D.half_size(kind).length())


## Footprint frame, door arrow, snap grid and the floating verdict label around the ghost.
func _build_ghost_extras(p: Node3D) -> void:
	_frame_ok = StandardMaterial3D.new()
	_frame_ok.albedo_color = Color(0.55, 1.0, 0.65, 0.95)
	_frame_ok.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_frame_ok.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_frame_bad = _frame_ok.duplicate()
	_frame_bad.albedo_color = Color(1.0, 0.4, 0.38, 0.95)
	var sz: Vector2 = D.CATALOG[kind]["size"]
	ghost_frame = Node3D.new()
	ghost.add_child(ghost_frame)
	var t := 0.14
	for e: Array in [[Vector3(sz.x + t, 0.1, t), Vector3(0, 0.08, sz.y * 0.5)], [Vector3(sz.x + t, 0.1, t), Vector3(0, 0.08, -sz.y * 0.5)],
			[Vector3(t, 0.1, sz.y + t), Vector3(sz.x * 0.5, 0.08, 0)], [Vector3(t, 0.1, sz.y + t), Vector3(-sz.x * 0.5, 0.08, 0)]]:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = e[0]
		mi.mesh = bm
		mi.position = e[1]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ghost_frame.add_child(mi)
	# an arrow on the front (door) side, so rotating reads at a glance
	ghost_arrow = MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(1.1, 1.1, 0.06)
	ghost_arrow.mesh = pm
	ghost_arrow.rotation.x = PI * 0.5
	ghost_arrow.position = Vector3(0, 0.1, sz.y * 0.5 + 0.9)
	ghost_arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ghost.add_child(ghost_arrow)
	ghost_label = Label3D.new()
	ghost_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	ghost_label.fixed_size = true
	ghost_label.pixel_size = 0.0009
	ghost_label.font_size = 34
	ghost_label.outline_size = 14
	ghost_label.no_depth_test = true
	ghost_label.render_priority = 6
	ghost_label.position = Vector3(0, 3.0, 0)
	ghost.add_child(ghost_label)
	# world-aligned 2 m grid under the snapped spot
	var sh := Shader.new()
	sh.code = GRID_SHADER
	_grid_mat = ShaderMaterial.new()
	_grid_mat.shader = sh
	grid = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(16, 16)
	plane.subdivide_width = 1
	plane.subdivide_depth = 1
	grid.mesh = plane
	grid.material_override = _grid_mat
	grid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.get_parent().add_child(grid)


## Pointer drag (mouse or touch) moves the ghost over the ground.
func handle_input(e: InputEvent) -> bool:
	if kind == "" or ghost == null:
		return false
	var at := Vector2.INF
	if e is InputEventScreenDrag or e is InputEventScreenTouch:
		at = (e as Variant).position
	elif e is InputEventMouseMotion and ((e as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		at = (e as InputEventMouseMotion).position
	elif e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT and (e as InputEventMouseButton).pressed:
		at = (e as InputEventMouseButton).position
	if at == Vector2.INF:
		return false
	var sheet_top: float = menu.call("sheet_top")
	if at.y > sheet_top:
		return false
	var p := _player()
	var cam: Camera3D = p.get("camera") if p != null else null
	if cam == null:
		return false
	var vp := cam.get_viewport()
	var k := Vector2(vp.size) / menu.get_viewport().get_visible_rect().size
	var q := at * k
	var o := cam.project_ray_origin(q)
	var n := cam.project_ray_normal(q)
	var y := p.global_position.y
	for _i in 4:
		if absf(n.y) < 0.001:
			return false
		var t := (y - o.y) / n.y
		if t < 0.0:
			return false
		var hit := o + n * t
		y = WorldGen.height(hit.x, hit.z)
		_pos = Vector2(hit.x, hit.z)
	dragged = true
	return true


func update_ghost() -> void:
	if kind == "" or ghost == null:
		return
	var c := cons()
	var p := _player()
	if not dragged and p != null:
		var fwd: Vector3 = p.forward() if p.has_method("forward") else -p.global_transform.basis.z
		_pos = _pp() + Vector2(fwd.x, fwd.z).normalized() * (REACH + D.half_size(kind).length())
	var pos: Vector2 = c.snap(_pos) if snap_on else _pos
	var g: Dictionary = c.ground(kind, pos, rot)
	ghost.global_position = Vector3(pos.x, float(g["base"]) if bool(g["ok"]) else WorldGen.height(pos.x, pos.y), pos.y)
	ghost.rotation.y = rot
	var sz: Vector2 = D.CATALOG[kind]["size"]
	(ghost_box.mesh as BoxMesh).size = Vector3(sz.x, 0.15, sz.y)
	var why := _reason(pos)
	var ok := why == ""
	var mat := _green if ok else _red
	# pulse so the verdict is unmissable on a small screen
	_pulse += get_process_delta()
	var a := 0.42 + 0.14 * sin(_pulse * 5.0)
	_green.albedo_color.a = a
	_red.albedo_color.a = a
	ghost_box.material_override = mat
	if ghost_mesh.mesh != null:
		ghost_mesh.material_override = mat
	if ghost_frame != null:
		var fm := _frame_ok if ok else _frame_bad
		for f in ghost_frame.get_children():
			(f as MeshInstance3D).material_override = fm
		ghost_arrow.material_override = fm
		ghost_label.text = "✓ Build here" if ok else "✗ " + why
		ghost_label.modulate = W.OK if ok else W.BAD
		ghost_label.outline_modulate = Color(0.05, 0.05, 0.05, 0.95)
		ghost_label.position.y = maxf(2.5, float(D.CATALOG[kind]["size"].x) * 0.5 + 1.5)
	if grid != null:
		grid.visible = snap_on
		grid.global_position = Vector3(pos.x, ghost.global_position.y + 0.06, pos.y)
		_grid_mat.set_shader_parameter("col", Color(0.55, 1.0, 0.65, 0.55) if ok else Color(1.0, 0.45, 0.4, 0.55))
	if why != _last_reason or ok != _ok:
		_last_reason = why
		_ok = ok
		_say("Ready to build here. Tap Place to lay the blueprint." if ok else why, ok)
	menu.call("set_place_info", "%s  ·  %d°  ·  grid %s" % [String(D.CATALOG[kind]["name"]), int(round(rad_to_deg(rot))), "on" if snap_on else "off"])


func _reason(pos: Vector2) -> String:
	if _pp().distance_to(pos) > D.PLACE_REACH:
		return "Too far from you."
	return cons().can_place(kind, pos, rot, upgrade_of)


func confirm_place() -> void:
	if kind == "":
		_say("Pick something to build first.")
		return
	var c := cons()
	var pos: Vector2 = c.snap(_pos) if snap_on else _pos
	var why := _reason(pos)
	if why != "":
		_say(why)
		return
	var r: Dictionary = c.place(kind, pos, rot, upgrade_of, _pp())
	if not bool(r["ok"]):
		_say(String(r["reason"]))
		return
	Audio.play_ui("pickup")
	var id := int(r["id"])
	var nm := String(D.CATALOG[kind]["name"])
	Game.say("Blueprint laid: %s. Stock it and put workers on it." % nm)
	cancel_place()
	var v := _view()
	if v != null:
		v.call("refresh")
	show_site(id)


# --- sites ---------------------------------------------------------------------------------

func fill_sites(list: VBoxContainer) -> void:
	var c := cons()
	if c.holdings.is_empty():
		list.add_child(_label("Nothing built yet. Gather logs, thatch, stone and clay, then lay a blueprint from the Build tab.", true))
		return
	var ids: Array = c.holdings.keys()
	ids.sort()
	for hid: int in ids:
		var h: Dictionary = c.holding_info(hid)
		var head := _label("%s: %s" % [h["name"], String(h["level_name"])], false, 16)
		head.add_theme_color_override("font_color", UITheme.ACCENT)
		list.add_child(head)
		var need: Array = h["next"]
		list.add_child(_label("%d buildings, %d people, %d beds. Leaning %s.%s" % [int(h["buildings"]), int(h["pop"]), int(h["beds"]), String(h["identity"]) if String(h["identity"]) != "" else "nothing yet",
			"  To grow: " + ", ".join(PackedStringArray(need)) if not need.is_empty() else ""], true, 12))
		list.add_child(_label("Stockpile %d/%d" % [int(h["store_used"]), int(h["store_cap"])], true, 12))
		var row := HBoxContainer.new()
		row.add_child(_btn("Stock all my materials", func() -> void:
			var n: int = c.deposit_all(hid)
			_say("Stockpiled %d items." % n if n > 0 else "Nothing to stockpile (or the store is full)."); menu.call("_refresh_list")))
		list.add_child(row)
		for sid: int in c.sites:
			var s: Dictionary = c.sites[sid]
			if int(s["holding"]) != hid:
				continue
			var info: Dictionary = c.site_info(sid, {"player_pos": _pp()})
			var txt := "%s: %s" % [info["name"], "built" if String(info["state"]) == "done" else "%s %d%%, %d on site%s" % [String(info["stage"]), int(round(float(info["pct"]) * 100.0)), int(info["workers"]), "  STALLED" if String(info["stall"]) != "" else ""]]
			var b := _btn(txt, func() -> void: show_site(sid))
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			list.add_child(b)
		list.add_child(HSeparator.new())


func show_site(id: int) -> void:
	site_id = id
	menu.call("set_mode", "site")


func fill_site(list: VBoxContainer) -> void:
	var c := cons()
	var s: Dictionary = c.sites.get(site_id, {})
	if s.is_empty():
		site_id = 0
		menu.call("set_mode", "sites")
		return
	var ctx := {"player_pos": _pp()}
	var info: Dictionary = c.site_info(site_id, ctx)
	var back := _btn("< All sites", func() -> void:
		site_id = 0
		menu.call("set_mode", "sites"), 120)
	list.add_child(back)
	var done := String(info["state"]) == "done"
	var title := _label("%s%s" % [info["name"], "  (upgrade)" if bool(info["upgrade"]) else ""], false, 18)
	title.add_theme_color_override("font_color", UITheme.ACCENT)
	list.add_child(title)
	if done:
		_fill_done(list, s)
		return
	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = 100
	bar.value = float(info["pct"]) * 100.0
	bar.custom_minimum_size = Vector2(0, 22)
	bar.show_percentage = false
	var stalled := String(info["stall"]) != ""
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.045, 0.04, 0.9)
	bg.border_color = Color(0.78, 0.66, 0.42, 0.9)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(8)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.95, 0.74, 0.3) if not stalled else Color(0.85, 0.35, 0.28)
	fill.set_corner_radius_all(8)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)
	list.add_child(bar)
	var stages := PackedStringArray()
	for i in D.STAGES.size() - 1:
		stages.append(("[b]%s[/b]" if i == int(info["stage_i"]) else "%s") % String(D.STAGES[i]).capitalize())
	list.add_child(_rich("%s  (%d%%)" % [" > ".join(stages), int(round(float(info["pct"]) * 100.0))]))
	var eta := float(info["eta"])
	list.add_child(_rich("Crew: %d builder%s, %d hauler%s, %d master%s.  Speed %.1f labour-h per hour%s.  ETA: %s" % [int(info["builders"]), "" if int(info["builders"]) == 1 else "s",
		int(info["haulers"]), "" if int(info["haulers"]) == 1 else "s", int(info["masters"]), "" if int(info["masters"]) == 1 else "s", float(info["rate"]),
		", tools" if bool(info["tools"]) else ", no tools", ("~%d game hours" % int(ceil(eta))) if eta >= 0.0 else "stalled"]))
	if String(info["stall"]) != "":
		list.add_child(_rich("[color=#e07070]%s[/color]" % String(info["stall"])))
	# materials
	var mats := PackedStringArray()
	for item: String in D.MATERIAL_ORDER:
		if not (info["need"] as Dictionary).has(item):
			continue
		var need := int(info["need"][item])
		var have := int((info["have"] as Dictionary).get(item, 0))
		var mine: int = c.available(item, c.site_pos(s))
		mats.append("[color=%s]%d/%d %s[/color] (you hold %d)" % ["#8fdc8f" if have >= need else "#e0c060", have, need, String(D.MATERIALS.get(item, item)).to_lower(), mine])
	list.add_child(_rich("Materials: " + ";  ".join(mats)))
	var r1 := HFlowContainer.new()
	var pw: Dictionary = c.player_worker()
	var mine_here := not pw.is_empty() and int(pw["site"]) == site_id
	r1.add_child(_btn("Stop working" if mine_here else "Work here", func() -> void:
		if mine_here:
			c.unassign(String(pw["id"]))
		else:
			c.assign_player(site_id)
			_say("You pick up a hammer. Stay within %d m." % int(D.PLAYER_NEAR))
		menu.call("_refresh_list")))
	r1.add_child(_btn("Haul for this site" if not (mine_here and String(pw["role"]) == "haul") else "Build instead", func() -> void:
		c.assign_player(site_id, "build" if (mine_here and String(pw["role"]) == "haul") else "haul")
		menu.call("_refresh_list")))
	r1.add_child(_btn("Deposit my materials", func() -> void:
		var n: int = c.deliver_all(site_id)
		_say("Delivered %d items." % n if n > 0 else "You have nothing this site needs.")
		menu.call("_refresh_list")))
	list.add_child(r1)
	var r2 := HFlowContainer.new()
	r2.add_child(_btn("Hire builder (%dg/day)" % D.HIRE_WAGE, func() -> void: _hire(false, "build")))
	r2.add_child(_btn("Hire hauler (%dg/day)" % (D.HIRE_WAGE - 1), func() -> void: _hire(false, "haul")))
	r2.add_child(_btn("Hire master builder (%dg/day)" % D.MASTER_WAGE, func() -> void: _hire(true, "build")))
	list.add_child(r2)
	var fm: RefCounted = Life.realm.mod("followers")
	if fm != null:
		var r3 := HFlowContainer.new()
		for f: Dictionary in fm.party():
			if String(f["status"]) != "present":
				continue
			var fid := String(f["id"])
			r3.add_child(_btn("Assign %s" % String(f["name"]).get_slice(" ", 0), func() -> void:
				c.assign_follower(site_id, fid)
				menu.call("_refresh_list")))
		if r3.get_child_count() > 0:
			list.add_child(r3)
	# crew
	for wid: String in s["workers"]:
		var w: Dictionary = c.workers[wid]
		var line := HBoxContainer.new()
		var sk := int(round(c.worker_skill(w, c.discipline_of(String(s["kind"]))) * 100.0))
		var lab := _label("%s (%s, skill %d%s)" % [w["name"], w["role"], sk, ", wage %dg" % int(w["wage"]) if int(w["wage"]) > 0 else ""], true, 12)
		lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(lab)
		line.add_child(_btn("Send off", func() -> void:
			c.unassign(wid)
			menu.call("_refresh_list"), 90))
		list.add_child(line)
	# lessons
	var lessons := HFlowContainer.new()
	for f: String in D.LESSONS:
		if c.knows(f):
			continue
		lessons.add_child(_btn("Learn %s (%dg)" % [String(D.LESSONS[f]["name"]), int(D.LESSONS[f]["gold"])], func() -> void:
			var r: Dictionary = c.learn_lesson(f)
			_say("You learn %s." % String(D.KNOW_NAMES[f]).to_lower() if bool(r["ok"]) else String(r["reason"]))
			menu.call("_refresh_list")))
	if lessons.get_child_count() > 0:
		list.add_child(_label("A master builder on your crew teaches:", true, 12))
		list.add_child(lessons)
	list.add_child(_btn("Cancel site (materials go to the stockpile)", func() -> void:
		c.cancel_site(site_id)
		site_id = 0
		menu.call("set_mode", "sites")))


func _hire(master: bool, role: String) -> void:
	var r: Dictionary = cons().hire_builder(site_id, master, role)
	_say("Hired." if bool(r["ok"]) else String(r["reason"]))
	menu.call("_refresh_list")


func _fill_done(list: VBoxContainer, s: Dictionary) -> void:
	var c := cons()
	var d: Dictionary = D.CATALOG[String(s["kind"])]
	list.add_child(_label(String(d["desc"]), true))
	list.add_child(_label("Built on day %d%s." % [int(s["done_day"]), " (upgraded from %s)" % String(s["from_kind"]).replace("_", " ") if s.has("from_kind") else ""], true, 12))
	for k: String in c.upgrade_options(site_id):
		var needs: Array = c.missing_needs_for_upgrade(k)
		var row := HBoxContainer.new()
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(_label("Upgrade to %s%s" % [String(D.CATALOG[k]["name"]), "" if needs.is_empty() else "  [locked]"], false, 15))
		col.add_child(W.chips(cost_parts(k, true)))
		if not needs.is_empty():
			col.add_child(W.locked_banner(needs))
		row.add_child(col)
		var b := _btn("Upgrade", func() -> void: begin_place(k, site_id), 88)
		b.disabled = not needs.is_empty()
		row.add_child(b)
		list.add_child(row)
	if D.STATIONS.has(String(s["kind"])):
		var stn: Dictionary = D.STATIONS[String(s["kind"])]
		var r := HFlowContainer.new()
		r.add_child(_btn("Make %s from your %s (all)" % [String(D.MATERIALS[stn["out"]]).to_lower(), String(D.MATERIALS[stn["in"]]).to_lower()], func() -> void:
			var res: Dictionary = c.process(String(s["kind"]), 999, _pp())
			_say("Made %d %s." % [int(res["made"]), String(D.MATERIALS[stn["out"]]).to_lower()] if bool(res["ok"]) else String(res["reason"]))
			menu.call("_refresh_list")))
		r.add_child(_btn("Hire a worker here (%dg/day)" % D.HIRE_WAGE, func() -> void:
			var hr: Dictionary = c.hire_builder(site_id, false, "craft")
			_say("Hired. They work from the stockpile." if bool(hr["ok"]) else String(hr["reason"]))
			menu.call("_refresh_list")))
		list.add_child(r)
		list.add_child(_label("%d working here." % c.worker_count(site_id, "craft"), true, 12))
	var hid := int(s["holding"])
	if String(d["role"]) == "storage":
		list.add_child(_btn("Stock all my materials (%d/%d)" % [c.store_used(hid), c.store_cap(hid)], func() -> void:
			var n: int = c.deposit_all(hid)
			_say("Stockpiled %d items." % n)
			menu.call("_refresh_list")))


# --- per frame -----------------------------------------------------------------------------

func tick(delta: float, mode: String) -> void:
	update_ghost()
	_refresh_timer -= delta
	if _refresh_timer <= 0.0:
		_refresh_timer = 1.0
		if (mode == "site" or mode == "sites") and kind == "":
			menu.call("_refresh_list")
