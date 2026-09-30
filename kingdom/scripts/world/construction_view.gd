extends Node3D
## Gives the player's construction sites (scripts/realm/construction.gd) a body. A site is a cheap node: a
## foundation slab, the building's own mesh revealed from the ground up by progress (foundation, frame, walls,
## roof, complete) behind a scaffold, piles of the materials delivered, and a label with the stage, progress bar,
## worker count, ETA and what is missing. Builders and haulers walk real routes (construction_nav.gd) between the
## storage pile and the site; worn trails are drawn as paths. Sites are built within BUILD metres and freed past
## FREE; progress is read from the sim every REFRESH_PERIOD seconds (the sim itself steps on WorldSim.hour_changed).

const BuildMenu := preload("res://scripts/ui/build_menu.gd")
const D := preload("res://scripts/realm/construction_data.gd")
const Nav := preload("res://scripts/realm/construction_nav.gd")
const BUILD := 160.0
const FREE := 220.0
const REFRESH_PERIOD := 0.5
const LABEL_NEAR := 55.0
const WORKER_NEAR := 90.0
const MAX_VISUAL_WORKERS := 16
const WALK_SPEED := 2.4
const UPGRADE_SWAP := 0.3

const REVEAL_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo : source_color = vec4(1.0);
uniform bool use_tex = false;
uniform bool use_vcol = false;
uniform float rough = 0.9;
uniform float alpha_cut = 0.0;
uniform float tint_mix = 0.0;
instance uniform float reveal_y = 1000.0;
varying float ly;
void vertex() { ly = VERTEX.y; }
void fragment() {
	if (ly > reveal_y) { discard; }
	vec4 c = albedo;
	if (use_tex) { c *= texture(albedo_tex, UV); }
	if (use_vcol) { c.rgb *= COLOR.rgb; }
	if (alpha_cut > 0.0 && c.a < alpha_cut) { discard; }
	ALBEDO = mix(c.rgb, c.rgb * vec3(1.05, 0.98, 0.88), tint_mix);
	ROUGHNESS = rough;
	SPECULAR = 0.15;
}
"""

var hud: Node
var focus := Vector3.ZERO
var _timer := 0.0
var _nodes: Dictionary = {}           # site id -> SiteNode
var _shader: Shader
var _reveal_mats: Dictionary = {}     # source material instance id -> ShaderMaterial
var _meshes: Dictionary = {}
var _mats: Dictionary = {}
var _pile_meshes: Dictionary = {}
var _trail_mm: MultiMeshInstance3D
var _trail_sig := ""
var _walkers: Array = []              # Walker
var _walker_sig := ""
var _markers: Node3D
var ghost_kind := ""


class SiteNode extends Node3D:
	var view: Node
	var id := 0
	var kind := ""
	var state := "site"
	var pct := 0.0
	var upgrade_of := 0
	var mesh_inst: MeshInstance3D
	var mesh_top := 1.0               # mesh-local height
	var mesh_scale := 1.0
	var slab: MeshInstance3D
	var poles: Array = []
	var rails: Array = []
	var piles: Node3D
	var label: Label3D
	var body: StaticBody3D
	var half := Vector2(2, 2)
	var old_hidden := false
	var sig := ""

	func prompt() -> String:
		var cons: RefCounted = Life.realm.mod("construction")
		var info: Dictionary = cons.site_info(id)
		if info.is_empty():
			return ""
		if String(info["state"]) == "done":
			return "%s" % String(info["name"])
		return "Help build: %s (%d%%)" % [String(info["name"]), int(round(float(info["pct"]) * 100.0))]

	func use() -> void:
		view.call("on_use", self)


class Walker extends Node3D:
	var model: Node3D
	var anim: AnimationPlayer
	var site := 0
	var role := "build"
	var route := PackedVector2Array()
	var leg := 0
	var state := "walk"
	var timer := 0.0
	var hub := Vector2.ZERO
	var door := Vector2.ZERO
	var work_pt := Vector2.ZERO
	var carry: MeshInstance3D
	var speed_mult := 1.0
	var seed_v := 0.0


func _cons() -> RefCounted:
	return Life.realm.mod("construction")


func _ready() -> void:
	add_to_group("construction_view")
	_shader = Shader.new()
	_shader.code = REVEAL_SHADER
	_markers = Node3D.new()
	add_child(_markers)


func _process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_timer = REFRESH_PERIOD
		refresh()
	_walk(delta)


## Builds everything in range at once (screenshots, teleports).
func build_all_now() -> void:
	refresh()


func refresh() -> void:
	var cons := _cons()
	if cons == null:
		return
	var p := Vector2(focus.x, focus.z)
	var pl: Variant = Life.player
	if pl is Node3D and is_instance_valid(pl):
		p = Vector2((pl as Node3D).global_position.x, (pl as Node3D).global_position.z)
	var upgrading := {}
	for id: int in cons.sites:
		var s: Dictionary = cons.sites[id]
		if int(s.get("upgrade_of", 0)) > 0 and String(s["state"]) == "site":
			upgrading[int(s["upgrade_of"])] = id
	for id: int in cons.sites:
		var s: Dictionary = cons.sites[id]
		var d := p.distance_to(cons.site_pos(s))
		if d < BUILD and not _nodes.has(id):
			_nodes[id] = _make_site(s)
		elif d > FREE and _nodes.has(id):
			(_nodes[id] as Node).queue_free()
			_nodes.erase(id)
	for id: int in _nodes.keys():
		if not cons.sites.has(id):
			(_nodes[id] as Node).queue_free()
			_nodes.erase(id)
	var ctx := {"player_pos": p}
	for id: int in _nodes:
		_update_site(_nodes[id], cons, p, ctx, upgrading)
	_update_trails(cons, p)
	_update_walkers(cons, p)


# --- sites ------------------------------------------------------------------------------

func _mat(key: String, col: Color, rough := 0.95) -> StandardMaterial3D:
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = col
		m.roughness = rough
		m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		_mats[key] = m
	return _mats[key]


func _box(size: Vector3, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _make_site(s: Dictionary) -> SiteNode:
	var n := SiteNode.new()
	n.view = self
	n.id = int(s["id"])
	n.kind = String(s["kind"])
	n.name = "Site_%d_%s" % [n.id, n.kind]
	n.half = D.half_size(n.kind)
	var sz: Vector2 = D.CATALOG[n.kind]["size"]
	add_child(n)
	var cons := _cons()
	var pos: Vector2 = cons.site_pos(s)
	var g: Dictionary = cons.ground(n.kind, pos, float(s["yaw"]))
	var base := float(g["base"])
	n.position = Vector3(pos.x, base, pos.y)
	n.rotation.y = float(s["yaw"])
	# foundation slab down to the lowest corner so the building sits level on a slope
	var depth := maxf(0.25, base - float(g["low"]) + 0.25)
	n.slab = _box(Vector3(sz.x + 0.5, depth + 0.12, sz.y + 0.5), _mat("slab", Color(0.46, 0.43, 0.38)), Vector3(0, 0.06 - depth * 0.5, 0))
	n.add_child(n.slab)
	# mesh
	var built := _building_mesh(n.kind)
	if not built.is_empty():
		var mi := MeshInstance3D.new()
		mi.mesh = built["mesh"]
		mi.position = built["offset"]
		mi.scale = Vector3.ONE * float(built["scale"])
		n.mesh_top = float(built["top"])
		n.mesh_scale = float(built["scale"])
		mi.set_surface_override_material(0, null)
		n.mesh_inst = mi
		n.add_child(mi)
		_apply_reveal(mi)
	# scaffold
	for i in 4:
		var sx := -1.0 if i % 2 == 0 else 1.0
		var sy := -1.0 if i < 2 else 1.0
		var pole := _box(Vector3(0.14, 1.0, 0.14), _mat("pole", Color(0.5, 0.36, 0.2)), Vector3(sx * (sz.x * 0.5 + 0.5), 0.5, sy * (sz.y * 0.5 + 0.5)))
		n.add_child(pole)
		n.poles.append(pole)
	for r in 3:
		for side in 4:
			var horiz := side < 2
			var sgn := -1.0 if side % 2 == 0 else 1.0
			var rail := _box(Vector3(sz.x + 1.0, 0.1, 0.08) if horiz else Vector3(0.08, 0.1, sz.y + 1.0), _mat("rail", Color(0.6, 0.45, 0.26)),
				Vector3(0, 0.0, sgn * (sz.y * 0.5 + 0.5)) if horiz else Vector3(sgn * (sz.x * 0.5 + 0.5), 0.0, 0))
			n.add_child(rail)
			n.rails.append([rail, r])
	n.piles = Node3D.new()
	n.add_child(n.piles)
	n.label = Label3D.new()
	n.label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	n.label.fixed_size = true
	n.label.pixel_size = 0.0009
	n.label.font_size = 36
	n.label.outline_size = 14
	n.label.no_depth_test = true
	n.label.render_priority = 5
	n.label.position = Vector3(0, 5.5, 0)
	n.add_child(n.label)
	# collider (a gate is a gap, not a wall)
	if n.kind not in ["gate", "campfire", "field"]:
		n.body = StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(sz.x * 0.92, 3.0, sz.y * 0.92)
		cs.shape = bs
		cs.position.y = 1.5
		n.body.add_child(cs)
		n.add_child(n.body)
	n.add_to_group("interactable")
	return n


## Mesh of a catalogue kind, fitted to its footprint and standing on y = 0: {mesh, offset, scale, top}.
func _building_mesh(kind: String) -> Dictionary:
	if _meshes.has(kind):
		return _meshes[kind]
	var d: Dictionary = D.CATALOG[kind]
	var asset := String(d["asset"])
	var mesh: ArrayMesh = null
	if asset.begins_with("proc:"):
		mesh = _proc_mesh(asset.substr(5))
	elif Assets.BUILDINGS.has(asset):
		mesh = Assets.building_mesh(asset)
	elif asset.begins_with("res://"):
		mesh = Assets.merged_mesh(asset)
	var out := {}
	if mesh != null:
		var box := mesh.get_aabb()
		var sz: Vector2 = d["size"]
		var k := 1.0
		if not asset.begins_with("proc:"):
			k = clampf(maxf(sz.x, sz.y) / maxf(maxf(box.size.x, box.size.z), 0.01), 0.35, 2.5)
			if Assets.BUILDINGS.has(asset) and String(d["role"]) != "defence":
				k = clampf(k, 0.6, 1.4)
		out = {"mesh": mesh, "scale": k, "top": box.end.y,
			"offset": Vector3(-(box.position.x + box.size.x * 0.5) * k, -box.position.y * k, -(box.position.z + box.size.z * 0.5) * k)}
	_meshes[kind] = out
	return out


func _proc_mesh(name: String) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var parts: Array = []
	match name:
		"rack":
			for x in [-1.0, 1.0]:
				parts.append([Vector3(0.1, 1.5, 0.1), Vector3(x, 0.75, 0)])
			parts.append([Vector3(2.4, 0.08, 0.08), Vector3(0, 1.4, 0)])
			parts.append([Vector3(2.4, 0.08, 0.08), Vector3(0, 0.9, 0)])
			for i in 5:
				parts.append([Vector3(0.05, 0.5, 0.05), Vector3(-0.9 + i * 0.45, 1.1, 0)])
		"sawhorse":
			for x in [-0.8, 0.8]:
				parts.append([Vector3(0.12, 0.9, 0.9), Vector3(x, 0.45, 0)])
			parts.append([Vector3(2.0, 0.12, 0.14), Vector3(0, 0.9, 0)])
			parts.append([Vector3(1.7, 0.16, 0.16), Vector3(0, 1.05, 0.05)])
		"mason":
			parts.append([Vector3(2.4, 0.9, 1.2), Vector3(0, 0.45, 0)])
			parts.append([Vector3(1.0, 0.5, 0.8), Vector3(0.3, 1.15, 0)])
			parts.append([Vector3(0.6, 0.3, 0.5), Vector3(-0.8, 1.05, 0.1)])
	for p: Array in parts:
		var b := BoxMesh.new()
		b.size = p[0]
		st.append_from(b, 0, Transform3D(Basis.IDENTITY, p[1]))
	var m := st.commit()
	m.surface_set_material(0, _mat("proc_" + name, Color(0.55, 0.4, 0.24) if name != "mason" else Color(0.58, 0.56, 0.52)))
	return m


func _apply_reveal(mi: MeshInstance3D) -> void:
	var mesh := mi.mesh
	for i in mesh.get_surface_count():
		var src := mesh.surface_get_material(i)
		var key := src.get_instance_id() if src != null else 0
		if not _reveal_mats.has(key):
			var sm := ShaderMaterial.new()
			sm.shader = _shader
			if src is BaseMaterial3D:
				var bm := src as BaseMaterial3D
				sm.set_shader_parameter("albedo", bm.albedo_color)
				if bm.albedo_texture != null:
					sm.set_shader_parameter("albedo_tex", bm.albedo_texture)
					sm.set_shader_parameter("use_tex", true)
				sm.set_shader_parameter("use_vcol", bm.vertex_color_use_as_albedo)
				sm.set_shader_parameter("rough", bm.roughness)
				if bm.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
					sm.set_shader_parameter("alpha_cut", bm.alpha_scissor_threshold)
			_reveal_mats[key] = sm
		mi.set_surface_override_material(i, _reveal_mats[key])


func _reveal_height(n: SiteNode, pct: float) -> float:
	if n.state == "done" or pct >= 1.0:
		return 10000.0
	var t := smoothstep(0.1, 0.97, pct)
	return n.mesh_top * t


func _update_site(n: SiteNode, cons: RefCounted, player: Vector2, ctx: Dictionary, upgrading: Dictionary) -> void:
	var info: Dictionary = cons.site_info(n.id, ctx)
	if info.is_empty():
		return
	var s: Dictionary = cons.sites[n.id]
	n.state = String(s["state"])
	var pct := float(info["pct"])
	# smooth between hourly ticks while work is going on
	if n.state == "site" and String(info["stall"]) == "" and float(info["rate"]) > 0.0 and WorldSim.time_of_day >= D.WORK_FROM and WorldSim.time_of_day < D.WORK_TO:
		pct = minf(1.0, pct + float(info["rate"]) * fposmod(WorldSim.time_of_day, 1.0) / maxf(float(s["total"]), 0.01))
	n.upgrade_of = int(s.get("upgrade_of", 0))
	var vis_pct := pct
	if n.upgrade_of > 0 and n.state == "site":
		vis_pct = maxf(0.0, (pct - UPGRADE_SWAP) / (1.0 - UPGRADE_SWAP))
	n.pct = vis_pct
	var done := n.state == "done"
	# an old building under upgrade disappears once the new frame starts
	var hide_old := false
	if upgrading.has(n.id):
		var up: Dictionary = cons.sites[upgrading[n.id]]
		var up_pct := clampf(float(up["progress"]) / maxf(float(up["total"]), 0.01), 0.0, 1.0)
		hide_old = up_pct >= UPGRADE_SWAP
	if n.mesh_inst != null:
		n.mesh_inst.visible = not hide_old and (not (n.upgrade_of > 0) or pct >= UPGRADE_SWAP or done)
		n.mesh_inst.set_instance_shader_parameter("reveal_y", _reveal_height(n, vis_pct))
	n.slab.visible = not hide_old and not (done and n.kind in ["fence", "palisade", "stone_wall"])
	if n.body != null:
		n.body.process_mode = Node.PROCESS_MODE_DISABLED if hide_old else Node.PROCESS_MODE_INHERIT
	# scaffold
	var scaff := (not done) and vis_pct < 0.96 and n.kind not in ["campfire", "fence"]
	var top := maxf(1.2, _reveal_height(n, vis_pct) * n.mesh_scale + 0.9) if not done else 1.0
	top = minf(top, n.mesh_top * n.mesh_scale + 1.2)
	for pole: MeshInstance3D in n.poles:
		pole.visible = scaff
		(pole.mesh as BoxMesh).size.y = top
		pole.position.y = top * 0.5
	for rr: Array in n.rails:
		var rail: MeshInstance3D = rr[0]
		var level := int(rr[1])
		rail.visible = scaff
		rail.position.y = top * (0.3 + 0.3 * level)
	# material piles
	var psig := "%s|%s" % [JSON.stringify(s["have"]), str(done)]
	if psig != n.sig:
		n.sig = psig
		for c in n.piles.get_children():
			c.queue_free()
		if not done:
			_build_piles(n, s)
	n.piles.visible = not done
	# label
	var close := player.distance_to(cons.site_pos(s)) < LABEL_NEAR
	n.label.visible = close and not hide_old and (not done or player.distance_to(cons.site_pos(s)) < 14.0)
	if n.label.visible:
		n.label.text = _label_text(info, n)
		n.label.modulate = Color(1, 0.85, 0.6) if String(info["stall"]) == "" else Color(1, 0.6, 0.5)
		n.label.position.y = maxf(3.5, n.mesh_top * n.mesh_scale + 1.6)


func _label_text(info: Dictionary, n: SiteNode) -> String:
	if String(info["state"]) == "done":
		return String(info["name"])
	var pct := int(round(n.pct * 100.0)) if n.upgrade_of == 0 else int(round(float(info["pct"]) * 100.0))
	var filled := clampi(int(round(float(pct) / 10.0)), 0, 10)
	var bar := "[" + "#".repeat(filled) + "-".repeat(10 - filled) + "]"
	var lines: PackedStringArray = []
	lines.append("%s%s" % [String(info["name"]), " (upgrade)" if bool(info["upgrade"]) else ""])
	lines.append("%s  %s %d%%" % [String(D.STAGES[D.stage_index(float(info["pct"]))]).capitalize(), bar, pct])
	var who := "%d builder%s" % [int(info["builders"]), "" if int(info["builders"]) == 1 else "s"]
	if int(info["haulers"]) > 0:
		who += ", %d hauler%s" % [int(info["haulers"]), "" if int(info["haulers"]) == 1 else "s"]
	var eta := float(info["eta"])
	lines.append("%s  %s" % [who, ("~%d h" % int(ceil(eta))) if eta >= 0.0 else "stalled"])
	if String(info["stall"]) != "":
		lines.append(String(info["stall"]))
	return "\n".join(lines)


func _pile_mesh(item: String) -> Mesh:
	if _pile_meshes.has(item):
		return _pile_meshes[item]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var col := Color(0.5, 0.36, 0.2)
	match item:
		"log":
			col = Color(0.42, 0.29, 0.16)
			for i in 6:
				var c := CylinderMesh.new()
				c.top_radius = 0.14
				c.bottom_radius = 0.14
				c.height = 1.6
				c.radial_segments = 6
				c.rings = 1
				var row := i / 3
				st.append_from(c, 0, Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), Vector3(0, 0.14 + row * 0.25, -0.3 + (i % 3) * 0.3 - row * 0.15)))
		"plank":
			col = Color(0.72, 0.56, 0.34)
			for i in 5:
				var b := BoxMesh.new()
				b.size = Vector3(1.6, 0.07, 0.3)
				st.append_from(b, 0, Transform3D(Basis.IDENTITY, Vector3(0, 0.05 + i * 0.08, 0)))
		"stone":
			col = Color(0.5, 0.5, 0.48)
			for i in 6:
				var sp := SphereMesh.new()
				sp.radius = 0.28
				sp.height = 0.45
				sp.radial_segments = 6
				sp.rings = 3
				st.append_from(sp, 0, Transform3D(Basis.IDENTITY, Vector3(cos(i * 1.3) * 0.5, 0.2 + (i / 4) * 0.25, sin(i * 1.3) * 0.4)))
		"cut_stone":
			col = Color(0.68, 0.66, 0.6)
			for i in 6:
				var b := BoxMesh.new()
				b.size = Vector3(0.6, 0.3, 0.4)
				st.append_from(b, 0, Transform3D(Basis.IDENTITY, Vector3(-0.35 + (i % 3) * 0.36, 0.15 + (i / 3) * 0.3, 0)))
		"clay":
			col = Color(0.64, 0.38, 0.25)
			var sp2 := SphereMesh.new()
			sp2.radius = 0.7
			sp2.height = 0.7
			sp2.radial_segments = 8
			sp2.rings = 3
			st.append_from(sp2, 0, Transform3D(Basis.IDENTITY, Vector3(0, 0.1, 0)))
		"thatch":
			col = Color(0.78, 0.66, 0.3)
			for i in 3:
				var cone := CylinderMesh.new()
				cone.top_radius = 0.05
				cone.bottom_radius = 0.42
				cone.height = 0.9
				cone.radial_segments = 6
				cone.rings = 1
				st.append_from(cone, 0, Transform3D(Basis.IDENTITY, Vector3(-0.5 + i * 0.5, 0.45, 0)))
		_:
			col = Color(0.35, 0.35, 0.4)
			var b2 := BoxMesh.new()
			b2.size = Vector3(0.6, 0.4, 0.5)
			st.append_from(b2, 0, Transform3D(Basis.IDENTITY, Vector3(0, 0.2, 0)))
	var m := st.commit()
	m.surface_set_material(0, _mat("pile_" + item, col))
	_pile_meshes[item] = m
	return m


func _build_piles(n: SiteNode, s: Dictionary) -> void:
	var slot := 0
	for item: String in D.MATERIAL_ORDER:
		var need := int(s["need"].get(item, 0))
		var have := int(s["have"].get(item, 0))
		if need <= 0 or have <= 0:
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = _pile_mesh(item)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var k := 0.45 + 0.75 * float(have) / need
		mi.scale = Vector3(k, k, k)
		var side := n.half.x + 1.8 + float(slot / 2) * 1.6
		mi.position = Vector3(side if slot % 2 == 0 else -side, 0.0, n.half.y * 0.4)
		mi.rotation.y = float(slot) * 0.7
		n.piles.add_child(mi)
		slot += 1


# --- interaction ------------------------------------------------------------------------

func on_use(n: SiteNode) -> void:
	var cons := _cons()
	var s: Dictionary = cons.sites.get(n.id, {})
	if s.is_empty():
		return
	if String(s["state"]) == "done":
		open_panel(n.id)
		return
	var pw: Dictionary = cons.player_worker()
	if not pw.is_empty() and int(pw["site"]) == n.id:
		cons.unassign(String(pw["id"]))
		Game.say("You put down your tools.")
	else:
		cons.assign_player(n.id)
		Game.say("You pick up a hammer. Stay close and the work goes faster. (Open the build menu to manage the crew.)")
	open_panel(n.id)


func open_panel(site_id: int) -> void:
	if hud == null:
		return
	var menu: Control = BuildMenu.open_for(hud as HUD)
	if menu != null and menu.has_method("show_site"):
		menu.call("show_site", site_id)


# --- trails -----------------------------------------------------------------------------

func _update_trails(cons: RefCounted, p: Vector2) -> void:
	var list: Array = cons.trail_list()
	var road_n := 0
	var foot_n := 0
	for t: Dictionary in list:
		if String(t["level"]) == "road":
			road_n += 1
		elif String(t["level"]) == "footpath":
			foot_n += 1
	var sig := "%d:%d:%d" % [list.size(), foot_n, road_n]
	if sig == _trail_sig:
		return
	_trail_sig = sig
	if _trail_mm == null:
		_trail_mm = MultiMeshInstance3D.new()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		var q := BoxMesh.new()
		q.size = Vector3(1.0, 0.05, 1.0)
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.roughness = 1.0
		m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		q.material = m
		mm.mesh = q
		_trail_mm.multimesh = mm
		_trail_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_trail_mm)
	var xs: Array = []
	for t: Dictionary in list:
		var a: Vector2 = t["a"]
		var b: Vector2 = t["b"]
		var len := a.distance_to(b)
		var n := maxi(1, int(ceil(len / 1.6)))
		var road := String(t["level"]) == "road"
		var width := 2.0 if road else (1.3 if String(t["level"]) == "footpath" else 0.7)
		var col := Color(0.52, 0.42, 0.3) if road else (Color(0.46, 0.36, 0.25) if String(t["level"]) == "footpath" else Color(0.4, 0.32, 0.22, 0.6))
		var yaw := atan2(b.x - a.x, b.y - a.y)
		for i in n:
			var q := a.lerp(b, (float(i) + 0.5) / n)
			var h := WorldGen.height(q.x, q.y) + 0.03
			xs.append([Transform3D(Basis(Vector3.UP, yaw).scaled_local(Vector3(width, 1, 1.9)), Vector3(q.x, h, q.y)), col])
	var mm2 := _trail_mm.multimesh
	mm2.instance_count = xs.size()
	for i in xs.size():
		mm2.set_instance_transform(i, xs[i][0])
		mm2.set_instance_color(i, xs[i][1])


# --- people -----------------------------------------------------------------------------

func _update_walkers(cons: RefCounted, p: Vector2) -> void:
	var want: Array = []
	for id: int in cons.sites:
		var s: Dictionary = cons.sites[id]
		if String(s["state"]) == "done" and not D.STATIONS.has(String(s["kind"])):
			continue
		if p.distance_to(cons.site_pos(s)) > WORKER_NEAR or not _nodes.has(id):
			continue
		for wid: String in s["workers"]:
			want.append([id, wid, String(cons.workers[wid]["role"])])
			if want.size() >= MAX_VISUAL_WORKERS:
				break
	var sig := JSON.stringify(want)
	if sig == _walker_sig:
		return
	_walker_sig = sig
	for w: Walker in _walkers:
		w.queue_free()
	_walkers.clear()
	for e: Array in want:
		_walkers.append(_make_walker(cons, int(e[0]), String(e[1]), String(e[2])))


func _make_walker(cons: RefCounted, site_id: int, wid: String, role: String) -> Walker:
	var s: Dictionary = cons.sites[site_id]
	var w := Walker.new()
	w.site = site_id
	w.role = role
	w.seed_v = float(hash(wid) % 1000) / 1000.0
	var skins := ["Barbarian", "Knight", "Rogue", "Rogue_Hooded"]
	var src := String(cons.workers[wid]["src"])
	w.model = Assets.character(skins[hash(wid) % skins.size()] if src != "player" else "Knight", 1.7)
	w.add_child(w.model)
	w.anim = Assets.animation_player(w.model)
	w.hub = cons.hub_pos(int(s["holding"]))
	w.door = Nav.door_of(s)
	var start := w.hub if role == "haul" else w.door + Vector2(sin(w.seed_v * TAU), cos(w.seed_v * TAU)) * 2.0
	if src == "player":
		var pl: Variant = Life.player
		if pl is Node3D and is_instance_valid(pl):
			start = Vector2((pl as Node3D).global_position.x, (pl as Node3D).global_position.z)
	add_child(w)
	w.position = Vector3(start.x, WorldGen.height(start.x, start.y), start.y)
	if role == "haul":
		w.carry = MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(0.5, 0.35, 0.35)
		w.carry.mesh = b
		w.carry.material_override = _mat("carry", Color(0.5, 0.36, 0.2))
		w.carry.position = Vector3(0, 1.2, 0.3)
		w.add_child(w.carry)
		w.carry.visible = false
	w.state = "new"
	return w


func _play(w: Walker, names: Array) -> void:
	if w.anim == null:
		return
	for nm: String in names:
		if w.anim.has_animation(nm):
			if w.anim.current_animation != nm:
				w.anim.get_animation(nm).loop_mode = Animation.LOOP_LINEAR
				w.anim.play(nm, 0.15)
			return


func _walk(delta: float) -> void:
	var cons := _cons()
	if cons == null:
		return
	for w: Walker in _walkers:
		if not cons.sites.has(w.site):
			continue
		var s: Dictionary = cons.sites[w.site]
		w.timer -= delta
		match w.state:
			"new":
				_begin_trip(w, cons, s)
			"walk":
				if w.route.size() < 2 or w.leg >= w.route.size() - 1:
					_arrive(w, cons, s)
				else:
					var cur := Vector2(w.position.x, w.position.z)
					var tgt: Vector2 = w.route[w.leg + 1]
					var d := tgt - cur
					var step := WALK_SPEED * delta * w.speed_mult
					if d.length() <= step:
						w.leg += 1
						cur = tgt
					else:
						cur += d.normalized() * step
						w.rotation.y = lerp_angle(w.rotation.y, atan2(d.x, d.y), minf(1.0, delta * 8.0))
					w.position = Vector3(cur.x, WorldGen.height(cur.x, cur.y), cur.y)
			"work":
				var face := Vector2(s["pos"][0], s["pos"][1]) - Vector2(w.position.x, w.position.z)
				w.rotation.y = lerp_angle(w.rotation.y, atan2(face.x, face.y), minf(1.0, delta * 4.0))
				if w.timer <= 0.0:
					_begin_trip(w, cons, s)
			"wait":
				if w.timer <= 0.0:
					_begin_trip(w, cons, s)


func _goto(w: Walker, cons: RefCounted, to: Vector2, s: Dictionary) -> void:
	var from := Vector2(w.position.x, w.position.z)
	w.route = Nav.route(cons, from, to, int(s["id"]))
	if w.route.size() < 2:
		w.route = PackedVector2Array([from, to])
	w.leg = 0
	w.state = "walk"
	var hs: Dictionary = cons.hub_site(int(s["holding"]))
	w.speed_mult = cons.path_speed(int(hs["id"]), int(s["id"])) if not hs.is_empty() else 1.0
	_play(w, ["Walking_A", "Walking_B", "Running_A"])


func _begin_trip(w: Walker, cons: RefCounted, s: Dictionary) -> void:
	var active := String(s["state"]) == "site" or D.STATIONS.has(String(s["kind"]))
	if not active:
		w.state = "wait"
		w.timer = 2.0
		return
	if w.role == "haul":
		var at_site := Vector2(w.position.x, w.position.z).distance_to(w.door) < 3.0
		w.carry.visible = not at_site
		if at_site:
			w.carry.visible = false
			_goto(w, cons, w.hub, s)
		else:
			w.carry.visible = true
			_goto(w, cons, w.door, s)
	else:
		# a spot around the footprint to work at
		var half := D.half_size(String(s["kind"]))
		var ang := w.seed_v * TAU + float(w.get_index()) * 1.9
		var pos := Vector2(s["pos"][0], s["pos"][1])
		var r := half.length() + 1.4
		w.work_pt = pos + Vector2(cos(ang), sin(ang)) * r
		_goto(w, cons, w.work_pt, s)


func _arrive(w: Walker, cons: RefCounted, s: Dictionary) -> void:
	if w.role == "haul":
		var at_site := Vector2(w.position.x, w.position.z).distance_to(w.door) < 3.0
		if at_site:
			w.carry.visible = false
		else:
			w.carry.visible = true
		w.state = "wait"
		w.timer = 0.8
		_play(w, ["Idle"])
		return
	w.state = "work"
	w.timer = 6.0 + w.seed_v * 4.0
	_play(w, ["1H_Melee_Attack_Chop", "Interact", "PickUp"])
