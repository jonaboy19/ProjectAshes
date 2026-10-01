extends Node3D
## One 12 x 12 m medieval street corner, built from the game's own assets with their ORIGINAL materials.
## Every node that a style may restyle carries meta "role" (house, wall, stall, goods, wood, lamp, tree, ground,
## skirt, hero_old, hero_new, villager) and "blob" (radius of its contact shadow, 0 = none).
## Layout (metres, +Z toward the camera): front cobbled street, left lane, house at the back, stone wall on the right.

const Chars := preload("res://scripts/style_lab/lab_chars.gd")
const Common := preload("res://scripts/style_lab/lab_common.gd")
const SIZE := 12.0

var lamp_top := Vector3.ZERO     # lantern flame position (for the light and glow)
var tri_note := {}


func build(style_id := "A") -> void:
	name = "Diorama"
	_ground()
	_building("house", "house_town_a", Vector3(0.2, 0, -3.5), 0.0, 0.5, 3.4)
	_building("wall", "wall", Vector3(5.4, 0, -2.3), -PI * 0.5, 0.5, 1.4)
	_building("wall", "wall", Vector3(5.4, 0, 1.75), -PI * 0.5, 0.5, 1.4)
	_building("stall", "market_stall_red", Vector3(3.0, 0, -0.3), -0.25, 1.0, 2.0)
	_goods(Vector3(3.0, 0, -0.3), -0.25)
	_building("wood", "well", Vector3(-4.4, 0, -1.6), 0.0, 1.0, 1.5)
	_building("wood", "hand_cart", Vector3(4.0, 0, 3.0), 0.9, 1.0, 1.0)
	_building("wood", "barrel_cluster", Vector3(-2.0, 0, -0.5), 0.3, 1.0, 0.9)
	_building("wood", "crate_stack", Vector3(1.9, 0, -0.45), 0.4, 1.0, 0.9)
	_building("wood", "sack_pile", Vector3(-2.8, 0, -0.2), 0.2, 1.0, 0.8)
	_building("wood", "flower_planter", Vector3(-0.9, 0, -0.6), 0.0, 1.0, 0.5)
	_building("wood", "banner_pole", Vector3(1.0, 0, -0.55), 0.0, 0.8, 0.0)
	var lamp := _building("lamp", "street_lamp", Vector3(-3.4, 0, 1.4), 0.0, 0.7, 0.5)
	var lb := (lamp.get_child(0) as MeshInstance3D).mesh.get_aabb()
	lamp_top = lamp.position + Vector3(0, lb.size.y * lamp.scale.y * 0.82, 0)
	# dressing: nothing sits on bare ground (ashes-art-style): flower strips at wall feet, beds, bunting
	for fp in [[Vector3(-1.4, 0, -0.75), 0.0], [Vector3(1.2, 0, -0.75), 0.0], [Vector3(4.6, 0, -2.4), PI * 0.5], [Vector3(4.6, 0, 2.2), PI * 0.5]]:
		_building("flowers", "flower_strip", fp[0], fp[1], 1.0, 0.0)
	_building("flowers", "flower_bed", Vector3(-5.0, 0, -4.2), 0.0, 1.0, 0.0)
	_building("flowers", "flower_bed", Vector3(2.4, 0, -5.0), 0.0, 1.0, 0.0)
	_tree(Vector3(3.8, 0, -4.9), 7.0)
	_char(Chars.hero_today(), Vector3(-0.75, 0, 1.9), 0.25)
	_char(Chars.hero_new(style_id), Vector3(0.75, 0, 1.9), -0.25)
	if style_id == "F":
		_backdrop()
	_char(Chars.villager(), Vector3(-2.6, 0, 0.6), 0.9)


func _ground() -> void:
	var g := MeshInstance3D.new()
	g.name = "Ground"
	g.mesh = Common.ground_mesh(SIZE, 60)
	g.set_meta("role", "ground")
	add_child(g)
	var s := MeshInstance3D.new()
	s.name = "Skirt"
	s.mesh = Common.skirt_mesh(SIZE, 0.8)
	s.set_meta("role", "skirt")
	add_child(s)


func _building(role: String, key: String, pos: Vector3, yaw: float, want_size: float, blob: float) -> Node3D:
	var root := Node3D.new()
	root.name = key
	root.position = pos
	root.rotation.y = yaw
	root.set_meta("role", role)
	var mi := MeshInstance3D.new()
	var mesh := Assets.building_mesh(key)
	mi.mesh = mesh
	root.add_child(mi)
	if mesh:
		var box := mesh.get_aabb()
		root.scale = Vector3.ONE * want_size
		tri_note[key] = [str(box.size), want_size]
	root.set_meta("blob", blob)
	add_child(root)
	return root


func _goods(pos: Vector3, yaw: float) -> void:
	if not MarketGoods.available():
		return
	var mesh := MarketGoods.layout("produce")
	if mesh == null:
		return
	var mi := MeshInstance3D.new()
	mi.name = "StallGoods"
	mi.mesh = mesh
	mi.position = pos
	mi.rotation.y = yaw
	mi.set_meta("role", "goods")
	add_child(mi)
	var st := get_node_or_null("market_stall_red")
	if st:
		mi.scale = st.scale


func _tree(pos: Vector3, height: float) -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Tree"
	var mesh := Assets.nature_mesh("CommonTree_1")
	mi.mesh = mesh
	if mesh:
		mi.scale = Vector3.ONE * (height / maxf(mesh.get_aabb().size.y, 0.1))
	mi.position = pos
	mi.set_meta("role", "tree")
	mi.set_meta("blob", 2.2)
	add_child(mi)


func _char(m: Node3D, pos: Vector3, yaw: float) -> void:
	m.position = pos
	m.rotation.y = yaw
	m.set_meta("blob", 0.55)
	add_child(m)


## Style F only: painted-looking far backdrop (meadow, mountains, a castle, tree line) so the box has depth
## and a horizon like the concept art. All meshes are cheap (a few hundred triangles each) and fog-tinted.
func _backdrop() -> void:
	var meadow := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(600, 600)
	meadow.mesh = pm
	meadow.position = Vector3(0, -0.78, -120)
	meadow.set_meta("role", "meadow")
	add_child(meadow)
	var peaks := [[Vector3(-90, -0.8, -230), 70.0, 90.0], [Vector3(10, -0.8, -260), 90.0, 120.0], [Vector3(120, -0.8, -220), 65.0, 80.0],
		[Vector3(-190, -0.8, -170), 55.0, 60.0], [Vector3(200, -0.8, -180), 60.0, 70.0]]
	for pk in peaks:
		var m := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 2.0
		cm.bottom_radius = pk[1]
		cm.height = pk[2]
		cm.radial_segments = 9
		cm.rings = 1
		m.mesh = cm
		m.position = pk[0] + Vector3(0, pk[2] * 0.5, 0)
		m.set_meta("role", "mountain")
		add_child(m)
	var castle := Assets.building_mesh("castle")
	if castle:
		var c := MeshInstance3D.new()
		c.mesh = castle
		var k := 34.0 / maxf(castle.get_aabb().size.y, 1.0)
		c.scale = Vector3.ONE * k
		c.position = Vector3(-34, -0.78, -105)
		c.rotation.y = 0.35
		c.set_meta("role", "backdrop")
		add_child(c)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var tm := Assets.nature_mesh("CommonTree_2")
	for i in 16:
		var t := MeshInstance3D.new()
		t.mesh = tm
		var ang := rng.randf_range(-0.9, 0.9)
		var dist := rng.randf_range(24.0, 70.0)
		t.position = Vector3(sin(ang) * dist * 1.4, -0.78, -cos(ang) * dist - 6.0)
		t.scale = Vector3.ONE * rng.randf_range(0.7, 1.3)
		t.set_meta("role", "tree")
		add_child(t)
