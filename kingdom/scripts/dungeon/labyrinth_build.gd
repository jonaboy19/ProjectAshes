extends RefCounted
## Turns a labyrinth layout (labyrinth_gen.gd) into cheap placeholder geometry: ONE floor mesh and ONE wall mesh (merged
## boxes, two draw calls), a few StaticBody3D colliders tagged with SurfaceQuery material tags, markers for creatures,
## chests, traps and stairs, gate nodes for the boss door and secret doors, and a baked navigation mesh.
## Art plan: replace the box meshes with the KayKit Dungeon Remastered CC0 kit (assets/incoming/kaykit/dungeon-remastered,
## see docs/plans/DUNGEONS_LABYRINTH.md); colliders and markers stay as they are.
##
##   build_floor(layout, opts) -> Node3D   opts: "nav" (bool, default true), "lights" (bool, default true)
##   bake_navmesh(layout) -> NavigationMesh
##   collision_boxes(layout) -> [{pos, size, wall}]   (also used by the tests: no GPU needed)
##
## The builder works headless: it creates nodes and resources only, nothing that needs a renderer.

const Gen := preload("res://scripts/dungeon/labyrinth_gen.gd")
const Data := preload("res://scripts/dungeon/labyrinth_data.gd")

const CELL := 3.0
const WALL_H := 5.0
const FLOOR_T := 0.4
const WORLD_LAYER := 1


## Merged axis-aligned rectangles (in cells) covering every cell for which `pred` is true. Greedy row-run + vertical merge.
static func merge_rects(layout: Dictionary, pred: Callable) -> Array[Rect2i]:
	var w: int = layout["w"]
	var h: int = layout["h"]
	var used := PackedByteArray()
	used.resize(w * h)
	var out: Array[Rect2i] = []
	for y in h:
		var x := 0
		while x < w:
			if used[y * w + x] == 0 and pred.call(Vector2i(x, y)):
				var x2 := x
				while x2 + 1 < w and used[y * w + x2 + 1] == 0 and pred.call(Vector2i(x2 + 1, y)):
					x2 += 1
				var y2 := y
				var grow := true
				while grow and y2 + 1 < h:
					for xx in range(x, x2 + 1):
						if used[(y2 + 1) * w + xx] != 0 or not pred.call(Vector2i(xx, y2 + 1)):
							grow = false
							break
					if grow:
						y2 += 1
				for yy in range(y, y2 + 1):
					for xx in range(x, x2 + 1):
						used[yy * w + xx] = 1
				out.append(Rect2i(x, y, x2 - x + 1, y2 - y + 1))
				x = x2 + 1
			else:
				x += 1
	return out


## Wall cells: rock or pillar cells touching walkable floor (8-neighbourhood), plus every pillar / brazier cell.
static func is_wall_shell(layout: Dictionary, c: Vector2i) -> bool:
	var w: int = layout["w"]
	var h: int = layout["h"]
	if c.x < 0 or c.y < 0 or c.x >= w or c.y >= h:
		return false
	var k: int = (layout["cells"] as PackedByteArray)[c.y * w + c.x]
	if k == Gen.PILLAR:
		return true
	if k != Gen.ROCK:
		return false
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if Gen.is_passable(layout, c + Vector2i(dx, dy)):
				return true
	return false


static func rect_center(layout: Dictionary, r: Rect2i) -> Vector3:
	var a := Gen.cell_to_local(layout, r.position)
	var b := Gen.cell_to_local(layout, r.end - Vector2i.ONE)
	return (a + b) * 0.5


static func rect_size(r: Rect2i) -> Vector3:
	return Vector3(float(r.size.x) * CELL, 1.0, float(r.size.y) * CELL)


static func collision_boxes(layout: Dictionary) -> Array:
	var out: Array = []
	for r in merge_rects(layout, func(c: Vector2i) -> bool: return Gen.is_passable(layout, c)):
		var s := rect_size(r)
		s.y = FLOOR_T
		var p := rect_center(layout, r)
		p.y = -FLOOR_T * 0.5
		out.append({"pos": p, "size": s, "wall": false})
	for r in merge_rects(layout, func(c: Vector2i) -> bool: return is_wall_shell(layout, c)):
		var s := rect_size(r)
		s.y = WALL_H
		var p := rect_center(layout, r)
		p.y = WALL_H * 0.5
		out.append({"pos": p, "size": s, "wall": true})
	return out


# ---------------------------------------------------------------------------------------------
# navigation

static func bake_navmesh(layout: Dictionary) -> NavigationMesh:
	var nm := NavigationMesh.new()
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	nm.agent_radius = 0.4
	nm.agent_height = 1.8
	nm.agent_max_climb = 0.3
	nm.agent_max_slope = 45.0
	var verts := PackedVector3Array()
	for r in merge_rects(layout, func(c: Vector2i) -> bool: return Gen.is_passable(layout, c)):
		var s := rect_size(r)
		var p := rect_center(layout, r)
		var hx := s.x * 0.5
		var hz := s.z * 0.5
		var a := Vector3(p.x - hx, 0, p.z - hz)
		var b := Vector3(p.x + hx, 0, p.z - hz)
		var c := Vector3(p.x + hx, 0, p.z + hz)
		var d := Vector3(p.x - hx, 0, p.z + hz)
		verts.append_array([a, b, c, a, c, d])
	var src := NavigationMeshSourceGeometryData3D.new()
	src.add_faces(verts, Transform3D.IDENTITY)
	NavigationServer3D.bake_from_source_geometry_data(nm, src)
	return nm


## True if world point `p` (x, z used) lies inside a polygon of the baked mesh.
static func nav_contains(nm: NavigationMesh, p: Vector3) -> bool:
	var vs := nm.get_vertices()
	for i in nm.get_polygon_count():
		var poly := nm.get_polygon(i)
		var pts := PackedVector2Array()
		for idx in poly:
			pts.append(Vector2(vs[idx].x, vs[idx].z))
		if Geometry2D.is_point_in_polygon(Vector2(p.x, p.z), pts):
			return true
	return false


# ---------------------------------------------------------------------------------------------
# scene

static func build_floor(layout: Dictionary, opts := {}) -> Node3D:
	var theme: Dictionary = Data.THEMES[layout["theme"]]
	var root := Node3D.new()
	root.name = "Labyrinth_%s_F%d" % [layout["labyrinth"], layout["number"]]
	root.set_meta(&"layout_seed", layout["seed"])
	# one body for floors, one for walls; two merged meshes
	var floor_body := StaticBody3D.new()
	floor_body.name = "Floor"
	floor_body.collision_layer = WORLD_LAYER
	SurfaceQuery.tag(floor_body, theme["surface"])
	var wall_body := StaticBody3D.new()
	wall_body.name = "Walls"
	wall_body.collision_layer = WORLD_LAYER
	SurfaceQuery.tag(wall_body, theme["wall_surface"])
	var floor_st := SurfaceTool.new()
	floor_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wall_st := SurfaceTool.new()
	wall_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for b: Dictionary in collision_boxes(layout):
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = b["size"]
		cs.shape = bs
		cs.position = b["pos"]
		if b["wall"]:
			wall_body.add_child(cs)
			_add_box(wall_st, b["pos"], b["size"])
		else:
			floor_body.add_child(cs)
			_add_box(floor_st, b["pos"], b["size"])
	root.add_child(floor_body)
	root.add_child(wall_body)
	root.add_child(_mesh_node("FloorMesh", floor_st, theme["floor"]))
	root.add_child(_mesh_node("WallMesh", wall_st, theme["wall"]))
	root.add_child(_markers(layout, theme, opts))
	for e: Dictionary in layout["edges"]:
		var g := _gate(layout, e, theme)
		if g != null:
			root.add_child(g)
	if opts.get("nav", true):
		var region := NavigationRegion3D.new()
		region.name = "Nav"
		region.navigation_mesh = bake_navmesh(layout)
		root.add_child(region)
	return root


static func _mesh_node(node_name: String, st: SurfaceTool, col: Color) -> MeshInstance3D:
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = 0.95
	mi.material_override = mat
	return mi


static func _markers(layout: Dictionary, theme: Dictionary, opts: Dictionary) -> Node3D:
	var m := Node3D.new()
	m.name = "Markers"
	var cr := Node3D.new()
	cr.name = "Creatures"
	m.add_child(cr)
	for c: Dictionary in layout["content"]["creatures"]:
		var mk := Marker3D.new()
		mk.name = String(c["id"])
		mk.position = Gen.cell_to_local(layout, c["cell"])
		mk.set_meta(&"spawn", c)
		cr.add_child(mk)
	var chs := Node3D.new()
	chs.name = "Chests"
	m.add_child(chs)
	for c: Dictionary in layout["content"]["chests"]:
		var mk := Marker3D.new()
		mk.name = String(c["id"])
		mk.position = Gen.cell_to_local(layout, c["cell"])
		mk.set_meta(&"chest", c)
		chs.add_child(mk)
	var trs := Node3D.new()
	trs.name = "Traps"
	m.add_child(trs)
	for t: Dictionary in layout["content"]["traps"]:
		var a := Area3D.new()
		a.name = String(t["id"])
		a.position = Gen.cell_to_local(layout, t["cell"])
		a.collision_layer = 0
		a.collision_mask = 2
		a.set_meta(&"trap", t)
		var cs := CollisionShape3D.new()
		var sh := CylinderShape3D.new()
		sh.radius = float(t["radius"]) * 0.5
		sh.height = 1.0
		cs.shape = sh
		cs.position.y = 0.5
		a.add_child(cs)
		trs.add_child(a)
	for key in ["stairs_up", "stairs_down", "warp_cell"]:
		var mk := Marker3D.new()
		mk.name = key
		mk.position = Gen.cell_to_local(layout, layout[key])
		m.add_child(mk)
	if opts.get("lights", true):
		var ls := Node3D.new()
		ls.name = "Lights"
		m.add_child(ls)
		for l: Dictionary in layout["content"]["lights"]:
			var o := OmniLight3D.new()
			o.position = Gen.cell_to_local(layout, l["cell"]) + Vector3(0, 2.2, 0)
			o.light_color = theme["accent"]
			o.omni_range = 9.0
			o.light_energy = 1.2
			o.shadow_enabled = false
			ls.add_child(o)
	return m


## Boss door (a tall double door, shut until the mid-boss dies) and secret doors (a wall block that looks like the wall).
static func _gate(layout: Dictionary, e: Dictionary, theme: Dictionary) -> Node3D:
	if e["kind"] != "boss_door" and e["kind"] != "secret":
		return null
	var cell: Vector2i = e["gate"]
	var body := StaticBody3D.new()
	body.name = "Gate_e%d" % e["id"]
	body.collision_layer = WORLD_LAYER
	body.position = Gen.cell_to_local(layout, cell)
	body.add_to_group(&"labyrinth_gate")
	body.set_meta(&"gate", {"edge": e["id"], "kind": e["kind"]})
	var big: bool = e["kind"] == "boss_door"
	var size := Vector3(CELL, WALL_H * (1.15 if big else 1.0), CELL)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position.y = size.y * 0.5
	body.add_child(cs)
	SurfaceQuery.tag(body, &"metal" if big else theme["wall_surface"])
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position.y = size.y * 0.5
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.12, 0.10) if big else theme["wall"]
	mi.material_override = mat
	body.add_child(mi)
	return body


static func _add_box(st: SurfaceTool, c: Vector3, s: Vector3) -> void:
	var h := s * 0.5
	var x0 := c.x - h.x
	var x1 := c.x + h.x
	var y0 := c.y - h.y
	var y1 := c.y + h.y
	var z0 := c.z - h.z
	var z1 := c.z + h.z
	var p := [Vector3(x0, y0, z0), Vector3(x1, y0, z0), Vector3(x1, y1, z0), Vector3(x0, y1, z0),
		Vector3(x0, y0, z1), Vector3(x1, y0, z1), Vector3(x1, y1, z1), Vector3(x0, y1, z1)]
	# quads listed counter-clockwise seen from outside; Godot's front face is clockwise, so they are emitted reversed
	for q: Array in [[0, 3, 2, 1], [4, 5, 6, 7], [0, 4, 7, 3], [1, 2, 6, 5], [3, 7, 6, 2], [0, 1, 5, 4]]:
		st.add_vertex(p[q[0]])
		st.add_vertex(p[q[2]])
		st.add_vertex(p[q[1]])
		st.add_vertex(p[q[0]])
		st.add_vertex(p[q[3]])
		st.add_vertex(p[q[2]])
