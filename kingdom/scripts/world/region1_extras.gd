extends RefCounted
## Region 1 site bodies that are not static meshes (packages C1 C2 C10, docs/regions/REGION_1_PLAN.md).
## RegionDressing calls `build(root, site)` for every site that carries an "x" block:
##   x.label   {text, sub, at: [x, y], h}     a painted name board, readable from 60 m (so a screenshot names the town)
##   x.npcs    [{name, role, look, at, yaw, greet, lines[], trade}]   named people: a "Talk" station that tells the
##                                            town's trade and rumours (no per-frame work)
##   x.people  [{look, at, yaw}]              standing extras (pilgrims, guards): idle animation, distance culled
##   x.doors   [{scene, at, yaw, prompt}]     InteriorDoor into an interior scene (guild hall, chapel)
##   x.mounds  [{at, r, h}]                   snow drifts (Grimfen Pass): ONE MultiMesh, one draw call
## Site-local offsets: `at` = [x right, y front] like site parts; yaw is degrees relative to the site.

const DistanceCull := preload("res://scripts/core/distance_cull.gd")
const INK := Color(0.96, 0.86, 0.58)
const BOARD := Color(0.30, 0.19, 0.10)


static func build(root: Node3D, site: Dictionary) -> void:
	var x: Dictionary = site.get("x", {})
	if x.has("label"):
		_label(root, x["label"])
	for npc: Dictionary in x.get("npcs", []):
		_npc(root, npc, site)
	for p: Dictionary in x.get("people", []):
		_person(root, p)
	for d: Dictionary in x.get("doors", []):
		_door(root, d)
	if x.has("mounds"):
		_mounds(root, x["mounds"])


static func _ground_at(root: Node3D, at: Array) -> Vector3:
	var w := root.global_transform * Vector3(float(at[0]), 0.0, float(at[1]))
	return Vector3(w.x, WorldGen.height(w.x, w.z), w.z)


## A name board: a dark plank with the town name in gold letters, on two posts. World-sized (not a nameplate) so
## it reads in a screenshot from the road.
static func _label(root: Node3D, lab: Dictionary) -> void:
	var at: Array = lab.get("at", [0, 6])
	var g := _ground_at(root, at)
	var holder := Node3D.new()
	holder.name = "NameBoard"
	root.add_child(holder)
	holder.global_position = g
	var h := float(lab.get("h", 3.4))
	var plank := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(4.6, 1.5, 0.14)
	plank.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = BOARD
	mat.roughness = 0.9
	plank.material_override = mat
	plank.position = Vector3(0, h, 0)
	plank.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(plank)
	for sx: float in [-2.0, 2.0]:
		var post := MeshInstance3D.new()
		var pm := CylinderMesh.new()
		pm.top_radius = 0.09
		pm.bottom_radius = 0.11
		pm.height = h + 0.6
		post.mesh = pm
		post.material_override = mat
		post.position = Vector3(sx, (h + 0.6) * 0.5 - 0.2, 0)
		post.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(post)
	for side: float in [1.0, -1.0]:
		var t := Label3D.new()
		t.text = String(lab.get("text", ""))
		t.font_size = 72
		t.pixel_size = 0.0115
		t.outline_size = 0
		t.modulate = INK
		t.shaded = false
		t.double_sided = false
		t.position = Vector3(0, h + 0.22, 0.09 * side)
		t.rotation.y = 0.0 if side > 0.0 else PI
		t.visibility_range_end = 90.0
		holder.add_child(t)
		var sub := String(lab.get("sub", ""))
		if sub != "":
			var s := Label3D.new()
			s.text = sub
			s.font_size = 40
			s.pixel_size = 0.0100
			s.outline_size = 0
			s.modulate = Color(0.85, 0.75, 0.55)
			s.shaded = false
			s.double_sided = false
			s.position = Vector3(0, h - 0.42, 0.09 * side)
			s.rotation.y = 0.0 if side > 0.0 else PI
			s.visibility_range_end = 70.0
			holder.add_child(s)
	holder.rotation.y = deg_to_rad(float(lab.get("yaw", 0.0)))


static func _body(look: String) -> Node3D:
	var body := Assets.character(look, 1.74, [])
	var anim := Assets.animation_player(body)
	if anim:
		anim.play("Idle" if anim.has_animation("Idle") else anim.get_animation_list()[0])
	DistanceCull.attach(body, 80.0, anim)
	return body


static func _npc(root: Node3D, npc: Dictionary, site: Dictionary) -> void:
	var title := "%s · %s" % [npc.get("name", "Villager"), npc.get("role", "")]
	var state := {"i": 0}
	var lines: Array = npc.get("lines", [])
	var town := String(site.get("town", site.get("name", "")))
	var menu := func() -> Dictionary:
		var opts: Array = []
		if not lines.is_empty():
			opts.append(["Any news from %s?" % town, func() -> String:
				state["i"] = (int(state["i"]) + 1) % lines.size()
				return String(lines[int(state["i"])])])
		if String(npc.get("trade", "")) != "":
			opts.append(["What is %s known for?" % town, func() -> String: return String(npc["trade"])])
		return {"title": title, "body": String(npc.get("greet", "Well met, traveller.")), "options": opts}
	var st := Station.new(title, "Talk", menu)
	root.add_child(st)
	var at: Array = npc.get("at", [0, 4])
	st.global_position = _ground_at(root, at)
	st.rotation.y = deg_to_rad(float(npc.get("yaw", 0.0)))
	st.add_child(_body(String(npc.get("look", "Rogue_Hooded"))))


static func _person(root: Node3D, p: Dictionary) -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	holder.global_position = _ground_at(root, p.get("at", [0, 0]))
	holder.rotation.y = deg_to_rad(float(p.get("yaw", 0.0)))
	holder.add_child(_body(String(p.get("look", "Rogue_Hooded"))))


static func _door(root: Node3D, d: Dictionary) -> void:
	var door := InteriorDoor.new()
	door.name = "Door_" + String(d.get("scene", "")).get_file().get_basename()
	door.interior_scene = String(d.get("scene", ""))
	door.prompt_text = String(d.get("prompt", "Enter"))
	door.collision_layer = 0
	door.collision_mask = InteriorDoor.PLAYER_TRIGGER_LAYER
	door.monitorable = false
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(2.4, 2.4, 2.0)
	shape.shape = bs
	shape.position.y = 1.1
	door.add_child(shape)
	root.add_child(door)
	door.global_position = _ground_at(root, d.get("at", [0, 0]))
	door.rotation.y = deg_to_rad(float(d.get("yaw", 0.0)))


## Snow drifts as one MultiMesh of squashed spheres (a barrier across Grimfen Pass without new art).
static func _mounds(root: Node3D, list: Array) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var sph := SphereMesh.new()
	sph.radius = 1.0
	sph.height = 2.0
	sph.radial_segments = 14
	sph.rings = 7
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.93, 0.96, 1.0)
	mat.roughness = 0.82
	mat.rim_enabled = true
	mat.rim = 0.25
	mat.rim_tint = 0.6
	sph.material = mat
	mm.mesh = sph
	mm.instance_count = list.size()
	for i in list.size():
		var m: Dictionary = list[i]
		var at: Array = m["at"]
		var g := _ground_at(root, at)
		var h := float(m["h"])
		var r := float(m["r"])
		var b := Basis(Vector3.UP, float(i) * 1.3).scaled(Vector3(r, h, r * 0.85))
		mm.set_instance_transform(i, Transform3D(b, Vector3(g.x, g.y - h * 0.18, g.z)))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "SnowDrifts"
	mmi.multimesh = mm
	mmi.top_level = true
	mmi.visibility_range_end = 400.0
	root.add_child(mmi)
