extends RefCounted
## Small shared placement helpers for the F9 wilds (camp, hidden places, outpost, Rift mouth): one merged mesh per
## prop from the Style G generated set (Assets.merged_mesh restyles it), settled on the lowest ground under its
## footprint, with a plain box standing in when a model is missing so headless tests still get a node.
## `boxes_mesh` merges a few boxes into ONE mesh (one draw) for posts, decks and gates.

const GEN := "res://assets/generated/"
const MODELS := {
	"tent": GEN + "region/ruins/bandit_tent.glb",
	"palisade": GEN + "region/ruins/bandit_palisade.glb",
	"lean_to": GEN + "region/ruins/bandit_lean_to.glb",
	"stash": GEN + "region/ruins/bandit_stash.glb",
	"campfire": GEN + "region/ruins/campfire.glb",
	"shrine": GEN + "region/ruins/overgrown_shrine.glb",
	"ruin_tower": GEN + "region/ruins/collapsed_tower.glb",
	"log": GEN + "region/nature/log_mossy.glb",
	"log_branchy": GEN + "region/nature/log_branchy.glb",
	"boulder": GEN + "region/nature/boulder_large.glb",
	"flowers": GEN + "region/nature/flowers_cool.glb",
	"hazel": GEN + "region/nature/bush_hazel.glb",
	"fern": GEN + "region/nature/fern_a.glb",
	"snag": GEN + "region/nature/dead_snag.glb",
	"woodpile": GEN + "woodpile.glb",
	"palisade_post": GEN + "orc_palisade.glb",
	"scarecrow": GEN + "region/farm/scarecrow.glb",
	"crate_stack": GEN + "props/crate_stack.glb",
	"barrel": GEN + "props/barrel.glb",
	"weapon_rack": GEN + "props/weapon_rack.glb",
	"notice_board": GEN + "props/notice_board.glb",
	"signpost": GEN + "props/signpost.glb",
}

static var _meshes: Dictionary = {}


static func mesh(key: String) -> Mesh:
	if not _meshes.has(key):
		var path: String = MODELS.get(key, key)
		_meshes[key] = Assets.merged_mesh(path) if ResourceLoader.exists(path) else null
	return _meshes[key]


## Places `key` at world XZ `at`, yawed, scaled to `height` metres tall when > 0 (else `sc`). Returns the node (always one).
static func prop(parent: Node3D, key: String, at: Vector2, yaw := 0.0, sc := 1.0, height := 0.0, shadow := true) -> MeshInstance3D:
	var m := mesh(key)
	var mi := MeshInstance3D.new()
	mi.name = key.capitalize().replace(" ", "")
	if m == null:
		var bm := BoxMesh.new()
		bm.size = Vector3(1.0, maxf(height, 1.0), 1.0)
		m = bm
		mi.set_meta("stand_in", true)
	mi.mesh = m
	var box := m.get_aabb()
	var s := sc
	if height > 0.0 and box.size.y > 0.01:
		s = height / box.size.y
	var ext := maxf(box.size.x, box.size.z) * 0.5 * s
	var low := WorldGen.height(at.x, at.y)
	for k in 4:
		var a := TAU * k / 4.0 + yaw
		low = minf(low, WorldGen.height(at.x + cos(a) * ext, at.y + sin(a) * ext))
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_transform = Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s), Vector3(at.x, low - 0.05, at.y))
	return mi


## An invisible solid box under `node` (collision layer 1, the world layer).
static func solid(node: Node3D, size: Vector3, centre := Vector3.ZERO) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = size
	cs.shape = bx
	cs.position = centre + Vector3(0, size.y * 0.5, 0)
	body.add_child(cs)
	node.add_child(body)
	return body


static var _wood_mat: StandardMaterial3D = null


## Boxes merged into one mesh: parts are [centre Vector3 (local), size Vector3, yaw float, colour Color].
static func boxes_mesh(parts: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for p: Array in parts:
		var c: Vector3 = p[0]
		var h: Vector3 = (p[1] as Vector3) * 0.5
		var basis := Basis(Vector3.UP, float(p[2]))
		var col: Color = p[3]
		var faces := [
			[Vector3.UP, Vector3(-h.x, h.y, -h.z), Vector3(-h.x, h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(h.x, h.y, -h.z)],
			[Vector3.DOWN, Vector3(-h.x, -h.y, h.z), Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, -h.y, h.z)],
			[Vector3.FORWARD, Vector3(-h.x, -h.y, -h.z), Vector3(-h.x, h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, -h.y, -h.z)],
			[Vector3.BACK, Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z), Vector3(-h.x, -h.y, h.z)],
			[Vector3.LEFT, Vector3(-h.x, -h.y, h.z), Vector3(-h.x, h.y, h.z), Vector3(-h.x, h.y, -h.z), Vector3(-h.x, -h.y, -h.z)],
			[Vector3.RIGHT, Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, h.y, h.z), Vector3(h.x, -h.y, h.z)],
		]
		for f: Array in faces:
			var n: Vector3 = basis * (f[0] as Vector3)
			var q: Array[Vector3] = []
			for i in range(1, 5):
				q.append(c + basis * (f[i] as Vector3))
			for idx in [0, 1, 2, 0, 2, 3]:
				st.set_color(col)
				st.set_normal(n)
				st.add_vertex(q[idx])
	var m := st.commit()
	if _wood_mat == null:
		_wood_mat = StandardMaterial3D.new()
		_wood_mat.vertex_color_use_as_albedo = true
		_wood_mat.roughness = 0.95
		_wood_mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.surface_set_material(0, _wood_mat)
	return m


## A flickering fire light (cheap: no shadows) at a world position.
static func fire_light(parent: Node3D, at: Vector3, energy := 1.4, rng := 11.0) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.6, 0.3)
	l.light_energy = energy
	l.omni_range = rng
	l.shadow_enabled = false
	l.distance_fade_enabled = true
	l.distance_fade_begin = 40.0
	l.distance_fade_length = 20.0
	parent.add_child(l)
	l.global_position = at
	return l


## Draw calls of a node tree (visible MeshInstance3D surfaces + MultiMesh surfaces), for budgets and tests.
static func draws(n: Node) -> int:
	var d := 0
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null and (n as MeshInstance3D).visible:
		d += maxi((n as MeshInstance3D).mesh.get_surface_count(), 1)
	elif n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh != null and (n as MultiMeshInstance3D).multimesh.mesh != null:
		d += (n as MultiMeshInstance3D).multimesh.mesh.get_surface_count()
	for c in n.get_children():
		d += draws(c)
	return d
