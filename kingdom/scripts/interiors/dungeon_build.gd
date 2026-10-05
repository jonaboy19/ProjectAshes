extends RefCounted
## Builds one dungeon interior from a layout (dungeon_gen.gd) when the player walks in, and nothing persists:
## the returned Node3D is freed by InteriorDoor.leave(). Draw-call plan (checked by tools_qa/caves):
## ~1 surface pair per 6x6-cell chunk, one MultiMesh per clutter kind, one for flames, one water mesh,
## a handful of props and thing-meshes, at most 12 real lights with distance fade. A 12-room dungeon stays
## below the 150-draw budget of docs/design/SIM_HIERARCHY.md with its creatures.

const Gen := preload("res://scripts/interiors/dungeon_gen.gd")
const Kit := preload("res://scripts/interiors/dungeon_kit.gd")
const Root := preload("res://scripts/interiors/dungeon_root.gd")
const Thing := preload("res://scripts/interiors/dungeon_thing.gd")
const Creature := preload("res://scripts/interiors/dungeon_creature.gd")
const MAX_LIGHTS := 12
const MAX_LIGHTS_PER_ROOM := 4      # phone budget: a room never carries more real lights than this (emissive meshes are free)


## opts: day (int), lead (String hidden-entrance id a journal points at), creatures (bool, default true),
##       exit_label (String), entrance (InteriorDoor, unused here).
static func build(g: Dictionary, state: Dictionary, opts: Dictionary = {}) -> Node3D:
	_ensure_state(state)
	var root := Root.new()
	root.name = "Dungeon_%s" % g["id"]
	root.g = g
	root.state = state
	root.day = int(opts.get("day", 1))
	var theme: String = g["theme"]
	var content: Dictionary = g["content"]
	# --- walls, floors, ceilings -------------------------------------------------------------
	var chunks := Kit.build_chunks(g)
	for c: Dictionary in chunks:
		var holder := StaticBody3D.new()
		holder.name = "Chunk_%d_%d" % [c["key"].x, c["key"].y]
		holder.collision_layer = 1
		holder.collision_mask = 0
		var mi := MeshInstance3D.new()
		mi.mesh = c["mesh"]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(mi)
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(c["faces"])
		shape.backface_collision = true
		var cs := CollisionShape3D.new()
		cs.shape = shape
		holder.add_child(cs)
		root.add_child(holder)
	root.set_meta("chunks", chunks.size())
	root.set_meta("tris", Kit.triangle_count(chunks))
	if theme == "flooded":
		root.add_child(_water(g))
	# --- environment ---------------------------------------------------------------------------
	var we := WorldEnvironment.new()
	we.environment = _environment(g)
	root.add_child(we)
	# --- entrance: spawn marker and the exit ---------------------------------------------------
	var ex: Dictionary = content["exit"]
	var inward := Vector3(sin(float(ex["yaw"])), 0, cos(float(ex["yaw"])))
	var spawn := Marker3D.new()
	spawn.name = "PlayerSpawn"
	# 3.2 m in (was 1.9): the chase camera hangs ~4 m behind the player, so a spawn this close to the entrance wall put the
	# lens in or behind it on the first frames; here the arm has room and the camp is in front of the lens.
	spawn.position = (ex["pos"] as Vector3) + inward * 3.2 + Vector3(0, 0.1, 0)
	spawn.rotation.y = atan2(-inward.x, -inward.z)
	root.add_child(spawn)
	var exit := InteriorDoor.new()
	exit.name = "ExitDoor"
	exit.is_exit = true
	exit.prompt_text = String(opts.get("exit_label", "Leave"))
	exit.collision_layer = 0
	exit.collision_mask = InteriorDoor.PLAYER_TRIGGER_LAYER
	var ecs := CollisionShape3D.new()
	var esh := SphereShape3D.new()
	esh.radius = 2.4
	ecs.shape = esh
	ecs.position.y = 1.0
	exit.add_child(ecs)
	root.add_child(exit)
	exit.position = (ex["pos"] as Vector3) + inward * 0.6
	_exit_visual(root, exit, inward)
	# --- lights, clutter, gates, things, creatures ---------------------------------------------
	_lights(root, g, content, theme)
	_clutter(root, g, content, theme)
	_gates(root, g, theme)
	_things(root, g, content, theme, state, opts)
	if bool(opts.get("creatures", true)):
		_creatures(root, g, content, state)
	if bool(state.get("boss_dead", false)) and not state["looted"].has("boss_chest") and content.has("boss"):
		var bc: Dictionary = content["creatures"][0]
		for cr: Dictionary in content["creatures"]:
			if bool(cr.get("boss", false)):
				bc = cr
		root.spawn_boss_chest.call_deferred(bc["pos"])
	return root


static func _ensure_state(s: Dictionary) -> void:
	for k in ["opened", "looted", "harvested", "read", "killed"]:
		if not s.has(k) or not s[k] is Dictionary:
			s[k] = {}
	if not s.has("boss_dead"):
		s["boss_dead"] = false
	if not s.has("cleared"):
		s["cleared"] = false


static func _environment(g: Dictionary) -> Environment:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	# Readable without a torch: the theme's ambient is lifted toward its wall tint (crystal caves read violet), the
	# torch / lights still make the difference between dim and lit.
	var amb: Color = g["ambient"]
	var tint: Color = g.get("tint", amb)
	env.ambient_light_color = amb.lerp(tint, 0.55 if g.get("light_kind", "") == "crystal" else 0.30)
	env.ambient_light_energy = 1.6 if not bool(g["dark"]) else (3.2 if g.get("light_kind", "") == "crystal" else 2.2)
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = g["fog"]
	env.fog_density = 0.010 if bool(g["dark"]) else 0.007
	env.fog_aerial_perspective = 0.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	return env


static func _water(g: Dictionary) -> MeshInstance3D:
	var side: int = g["w"]
	var cells: PackedByteArray = g["cells"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	for z in range(side):
		for x in range(side):
			if cells[z * side + x] != Gen.POOL:
				continue
			# one quad a little bigger than the cell so the surface meets the sloped banks
			var p := Gen.cell_pos(g, Vector2i(x, z)) + Vector3(0, -0.22, 0)
			var h := Gen.CELL * 0.5 + 0.9
			st.set_normal(Vector3.UP)
			for v: Vector3 in [Vector3(-h, 0, -h), Vector3(-h, 0, h), Vector3(h, 0, h), Vector3(-h, 0, -h), Vector3(h, 0, h), Vector3(h, 0, -h)]:
				st.add_vertex(p + v)
			any = true
	var mi := MeshInstance3D.new()
	mi.name = "Water"
	if any:
		mi.mesh = st.commit()
		mi.material_override = Kit.materials("flooded")["water"]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func _exit_visual(root: Node3D, exit: Node3D, inward: Vector3) -> void:
	# the way back to daylight: a soft swirling opening (gold core fading into the cave's violet), never a flat white card
	var q := MeshInstance3D.new()
	var bm := QuadMesh.new()       # one-sided (faces into the room): a box showed its back to a camera pushed behind the wall
	bm.size = Vector2(2.0, 2.2)
	q.mesh = bm
	var mat := ShaderMaterial.new()
	mat.shader = _portal_shader()
	q.material_override = mat
	q.position = Vector3(0, 1.15, -0.55)
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	exit.add_child(q)
	exit.rotation.y = atan2(inward.x, inward.z)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.82, 0.55)
	l.omni_range = 9.0
	l.light_energy = 1.0
	l.position = Vector3(0, 1.8, 1.2)
	exit.add_child(l)


static var _portal: Shader


static func _portal_shader() -> Shader:
	if _portal == null:
		_portal = Shader.new()
		_portal.code = """
shader_type spatial;
render_mode unshaded, blend_mix, cull_back, depth_draw_never, shadows_disabled;
// Soft exit opening: a slow spiral of warm daylight gold into rift violet, feathered at the edge. Peak value stays
// well under pure white (Style G: no flat white rectangles).
void fragment() {
	vec2 p = (UV - vec2(0.5)) * vec2(1.0, 1.1);
	float r = length(p) * 2.0;
	float ang = atan(p.y, p.x);
	float spin = ang + r * 3.2 - TIME * 0.55;
	float arms = 0.5 + 0.5 * sin(spin * 3.0);
	float core = 1.0 - smoothstep(0.0, 0.85, r);
	vec3 gold = vec3(0.90, 0.72, 0.42);
	vec3 violet = vec3(0.50, 0.32, 0.80);
	vec3 col = mix(violet, gold, clamp(core * 0.9 + arms * 0.18, 0.0, 1.0));
	col *= 0.80 + 0.12 * arms;
	float edge = 1.0 - smoothstep(0.55, 1.0, r);
	ALBEDO = min(col, vec3(0.92));
	ALPHA = edge * (0.55 + 0.4 * core);
}
"""
	return _portal


# ---------------------------------------------------------------------------------------------
# lights

static func _lights(root, g: Dictionary, content: Dictionary, theme: String) -> void:
	var flames: Array[Transform3D] = []
	var pits: Array[Transform3D] = []
	var brackets: Array[Transform3D] = []
	var glow_caps: Array[Transform3D] = []
	var crystals: Array[Transform3D] = []
	var made := 0
	var per_room := {}
	var ordered: Array = content["lights"].duplicate()
	# entrance room first, so the lights near the player always exist
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["room"]) < int(b["room"]))
	for l: Dictionary in ordered:
		var pos: Vector3 = l["pos"]
		var inward := Vector3(sin(float(l["yaw"])), 0, cos(float(l["yaw"])))
		var kind: String = l["kind"]
		var light_pos := pos + Vector3(0, 1.6, 0) + inward * 0.6
		match kind:
			"torch", "lantern", "brazier":
				var fl := pos + Vector3(0, 2.05, 0) + inward * 0.25
				brackets.append(Transform3D(Basis(), pos + Vector3(0, 1.15, 0) + inward * 0.1))
				flames.append(Transform3D(Basis().scaled(Vector3.ONE * (1.0 if kind != "brazier" else 1.5)), fl))
				light_pos = fl + inward * 0.5
			"campfire":
				pits.append(Transform3D(Basis(), pos))
				flames.append(Transform3D(Basis().scaled(Vector3.ONE * 2.4), pos + Vector3(0, 0.1, 0)))
				light_pos = pos + Vector3(0, 1.1, 0)
			"glowcap":
				glow_caps.append(Transform3D(Basis(Vector3.UP, randf() * TAU).scaled(Vector3.ONE * 1.6), pos))
				light_pos = pos + Vector3(0, 0.9, 0) + inward * 0.4
			"crystal":
				crystals.append(Transform3D(Basis(Vector3.UP, randf() * TAU).scaled(Vector3.ONE * 1.5), pos + inward * 0.2))
				# two small emissive companions on the floor beside it: glow without another real light
				var side := inward.cross(Vector3.UP)
				for k in 2:
					var off := (0.9 + 0.5 * k) * (1.0 if k == 0 else -1.0)
					crystals.append(Transform3D(Basis(Vector3.UP, randf() * TAU).scaled(Vector3.ONE * (0.8 + 0.3 * k)), pos + inward * (0.6 + 0.3 * k) + side * off))
				light_pos = pos + Vector3(0, 1.2, 0) + inward * 0.6
		var room_id := int(l.get("room", -1))
		if made >= MAX_LIGHTS or int(per_room.get(room_id, 0)) >= MAX_LIGHTS_PER_ROOM:
			continue
		per_room[room_id] = int(per_room.get(room_id, 0)) + 1
		made += 1
		var omni := OmniLight3D.new()
		omni.light_color = l["color"]
		omni.omni_range = float(l["range"])
		omni.light_energy = float(l["energy"])
		omni.shadow_enabled = false
		omni.distance_fade_enabled = true
		omni.distance_fade_begin = 18.0
		omni.distance_fade_length = 8.0
		root.add_child(omni)
		omni.position = light_pos
		if kind in ["torch", "lantern", "brazier", "campfire"]:
			root.flicker.append([omni, omni.light_energy, randf() * 10.0])
	_multimesh(root, Kit.prop_mesh("flame", theme), flames, "Flames")
	_multimesh(root, Kit.prop_mesh("bracket", theme), brackets, "Brackets")
	_multimesh(root, Kit.prop_mesh("firepit", theme), pits, "FirePits")
	_multimesh(root, Kit.prop_mesh("glowcap", theme), glow_caps, "GlowCaps")
	_multimesh(root, Kit.prop_mesh("crystal", theme), crystals, "LightCrystals")


static func _multimesh(root: Node3D, mesh: Mesh, xforms: Array[Transform3D], nm: String) -> void:
	if xforms.is_empty() or mesh == null:
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = nm
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mmi)


static func _clutter(root: Node3D, g: Dictionary, content: Dictionary, theme: String) -> void:
	var by_kind := {}
	var body := StaticBody3D.new()
	body.name = "ClutterBody"
	body.collision_layer = 1
	body.collision_mask = 0
	for c: Dictionary in content["clutter"]:
		var kind: String = c["kind"]
		var s := float(c["scale"])
		var t := Transform3D(Basis(Vector3.UP, float(c["yaw"])).scaled(Vector3.ONE * s), c["pos"])
		if not by_kind.has(kind):
			by_kind[kind] = [] as Array[Transform3D]
		(by_kind[kind] as Array[Transform3D]).append(t)
		var shape: Shape3D = null
		var off := Vector3.ZERO
		match kind:
			"pillar":
				var cyl := CylinderShape3D.new()
				cyl.radius = 0.55 * s
				cyl.height = 3.6 * s
				shape = cyl
				off = Vector3(0, 1.8 * s, 0)
			"crate", "barrel":
				var bx := BoxShape3D.new()
				bx.size = Vector3(0.75, 0.8, 0.75) * s
				shape = bx
				off = Vector3(0, 0.4 * s, 0)
			"rock", "stalagmite", "crystal":
				var cy2 := CylinderShape3D.new()
				cy2.radius = 0.45 * s
				cy2.height = 1.0 * s
				shape = cy2
				off = Vector3(0, 0.5 * s, 0)
		if shape != null:
			var cs := CollisionShape3D.new()
			cs.shape = shape
			cs.position = (c["pos"] as Vector3) + off
			body.add_child(cs)
	root.add_child(body)
	for kind: String in by_kind:
		_multimesh(root, Kit.prop_mesh(kind, theme), by_kind[kind], "Clutter_" + kind)


# ---------------------------------------------------------------------------------------------
# gates

static func _gates(root, g: Dictionary, theme: String) -> void:
	var hr: Array = g["height"]
	var h := float(hr[0]) - 0.15
	for gt: Dictionary in g["gates"]:
		var gid := int(gt["id"])
		if root.is_open(gid):
			continue
		var body := StaticBody3D.new()
		body.name = "Gate%d" % gid
		body.collision_layer = 1
		body.collision_mask = 0
		var pos: Vector3 = Gen.cell_pos(g, gt["cell"])
		var along_x: bool = gt["axis"] == "x"
		var size := Vector3(0.5, h, Gen.CELL + 0.4) if along_x else Vector3(Gen.CELL + 0.4, h, 0.5)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		cs.position.y = h * 0.5
		body.add_child(cs)
		var kind: String = gt["kind"]
		if kind == "collapse":
			# a heap of fallen rock across the tunnel
			var mi := MeshInstance3D.new()
			mi.mesh = Kit.prop_mesh("rock", theme)
			mi.scale = Vector3(2.6, 5.0, 2.6) if along_x else Vector3(2.6, 5.0, 2.6)
			mi.position.y = 0.0
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			body.add_child(mi)
			for i in 3:
				var m2 := MeshInstance3D.new()
				m2.mesh = Kit.prop_mesh("rock", theme)
				m2.scale = Vector3.ONE * (1.6 + i * 0.3)
				m2.position = Vector3(0, 0, -0.9 + i * 0.9) if along_x else Vector3(-0.9 + i * 0.9, 0, 0)
				m2.rotation.y = i * 1.3
				body.add_child(m2)
		else:
			var col := Color(0.5, 0.38, 0.22) if theme in ["mine", "hideout", "warren"] else Color(0.55, 0.55, 0.58)
			var door := MeshInstance3D.new()
			door.mesh = Kit.box_mesh(size - Vector3(0, 0.1, 0) * 1.0, col, theme)
			door.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			body.add_child(door)
			if kind == "rune":
				var rm := StandardMaterial3D.new()
				rm.albedo_color = Color(0.85, 0.5, 1.0)
				rm.emission_enabled = true
				rm.emission = rm.albedo_color
				rm.emission_energy_multiplier = 2.0
				var rq := MeshInstance3D.new()
				var qb := BoxMesh.new()
				qb.size = Vector3(0.56, 1.2, 1.2) if along_x else Vector3(1.2, 1.2, 0.56)
				rq.mesh = qb
				rq.material_override = rm
				rq.position.y = h * 0.55
				rq.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				body.add_child(rq)
				var rl := OmniLight3D.new()
				rl.light_color = Color(0.85, 0.5, 1.0)
				rl.omni_range = 5.0
				rl.light_energy = 0.8
				rl.position = Vector3(1.2, h * 0.55, 0) if along_x else Vector3(0, h * 0.55, 1.2)
				body.add_child(rl)
		root.add_child(body)
		body.position = pos
		root.gates[gid] = body
		# rune and collapse gates also need something to interact with on each side
		if kind in ["rune", "collapse"]:
			for side in [-1.0, 1.0]:
				var t := Thing.new()
				root.add_child(t)
				t.setup("gate", {"id": "gate%d_%d" % [gid, int(side)], "gate": gid, "gkind": kind, "fact": gt["fact"]}, root, theme, 2.3)
				t.position = pos + (Vector3(side * 1.6, 0, 0) if not along_x else Vector3(0, 0, side * 1.6))
				root.things["gate%d_%d" % [gid, int(side)]] = t
				root.gate_opened.connect(func(opened: int, _how: String) -> void:
					if opened == gid and is_instance_valid(t):
						t.done = true
						t._retire())


# ---------------------------------------------------------------------------------------------
# things

static func _things(root, g: Dictionary, content: Dictionary, theme: String, state: Dictionary, opts: Dictionary) -> void:
	var day := int(opts.get("day", 1))
	# resource nodes regrow after two weeks
	for id: String in state["harvested"].keys():
		if day - int(state["harvested"][id]) >= 14:
			state["harvested"].erase(id)
	for c: Dictionary in content["chests"]:
		if state["looted"].has(c["id"]):
			continue
		var t := _thing(root, "chest", c, theme)
		t.position = c["pos"]
		t.rotation.y = float(c["yaw"])
	var batches := {}
	for n: Dictionary in content["nodes"]:
		if state["harvested"].has(n["id"]):
			continue
		var t2 := _thing(root, "node", n, theme)
		t2.position = n["pos"]
		var nk := String(n["kind"])
		if not batches.has(nk):
			batches[nk] = []
		(batches[nk] as Array).append(n)
	for nk: String in batches:
		var list: Array = batches[nk]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		var mesh: Mesh = Kit.prop_mesh("rock", theme)
		var sc := 0.8
		match nk:
			"glowcap", "healing_herb":
				mesh = Kit.prop_mesh("glowcap", theme)
				sc = 1.6 if nk == "glowcap" else 1.1
			"rift_crystal":
				mesh = Kit.prop_mesh("crystal", theme)
				sc = 0.9
		mm.mesh = mesh
		mm.instance_count = list.size()
		var idx := {}
		var poss := {}
		for i in list.size():
			var nd: Dictionary = list[i]
			mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, float(nd["yaw"])).scaled(Vector3.ONE * sc), nd["pos"]))
			idx[nd["id"]] = i
			poss[nd["id"]] = nd["pos"]
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Nodes_" + nk
		mmi.multimesh = mm
		if nk in ["iron_ore", "copper_ore", "coal", "silver_ore"]:
			mmi.material_override = Thing._ore_material(nk)
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mmi)
		root.node_batches[nk] = {"mm": mm, "idx": idx, "pos": poss}
	var lead := String(opts.get("lead", ""))
	for l: Dictionary in content["lore"]:
		var d := l.duplicate()
		if lead != "" and String(l.get("kind", "")) != "rune" and not d.has("lead"):
			d["lead"] = lead
			lead = ""       # the first find carries it
		var t3 := _thing(root, "lore", d, theme)
		t3.position = l["pos"]
		t3.rotation.y = float(l["yaw"])
	for lv: Dictionary in content["levers"]:
		if root.is_open(int(lv["gate"])):
			continue
		var t4 := _thing(root, "lever", lv, theme)
		t4.position = lv["pos"]
	for pl: Dictionary in content["plates"]:
		if root.is_open(int(pl["gate"])):
			continue
		var t5 := _thing(root, "plate", pl, theme, 0.9)
		t5.position = pl["pos"]
	for tr: Dictionary in content["traps"]:
		var t6 := _thing(root, "trap", tr, theme, 0.9)
		t6.position = tr["pos"]
	for p: Dictionary in content["props"]:
		if String(p["kind"]) == "torch_cache":
			var life: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Life")
			var has_torch := life != null and int(life.call("count", "torch")) > 0
			if not has_torch:
				var t7 := _thing(root, "torch_cache", p, theme)
				t7.position = p["pos"]
				t7.rotation.y = float(p["yaw"])


static func _thing(root, kind: String, d: Dictionary, theme: String, radius := 1.8) -> Thing:
	var t := Thing.new()
	root.add_child(t)
	t.setup(kind, d, root, theme, radius)
	root.things[String(d["id"])] = t
	return t


# ---------------------------------------------------------------------------------------------
# creatures

static func _creatures(root, g: Dictionary, content: Dictionary, state: Dictionary) -> void:
	for c: Dictionary in content["creatures"]:
		if state["killed"].has(c["id"]):
			continue
		var m := Creature.new()
		m.kind = String(c["kind"])
		m.cid = String(c["id"])
		m.level = int(c["level"])
		m.boss = bool(c.get("boss", false))
		m.asleep = bool(c.get("asleep", false))
		m.display_name = String(c.get("name", ""))
		m.trophy = String(c.get("trophy", ""))
		m.body_scale = float(c.get("scale", 1.0))
		m.element = String(c.get("element", ""))
		m.hp_mul = float(c.get("hp_mul", 0.0))
		m.root = root
		root.add_child(m)
		if m.is_queued_for_deletion():
			continue
		m.position = (c["pos"] as Vector3) + Vector3(0, 0.05, 0)
		m.rotation.y = float(c.get("yaw", 0.0))
		root.register_creature(m)
