extends Node3D
## W6 region lock (docs/world/REAL_WORLD.md): outside the 16 x 16 km Valencious box the real world is region-locked for now.
## Diegetic: warden posts (a banner pole, a barrier bar and a lantern) stand on the border every 400 m, and walking past the
## last post turns the player back with a line from the border wardens. RealWorld.unlocked (settings [world] unlock_outer or
## --unlock_outer) lifts it for later content. Cheap: one rect test 4x a second; posts are one MultiMesh per part.

const CHECK_EVERY := 0.25
const POST_STEP := 400.0
const PUSH_IN := 18.0
const LINES := ["Border warden: \"No further, traveller. The road beyond is closed by order of the Council of Wardens.\"",
	"Border warden: \"The marches past this post are not ours to guard. Turn back.\"",
	"A warden's horn sounds: the frontier is shut. You turn back toward Valencious."]

var _t := 0.0
var _line := 0


func _ready() -> void:
	name = "RegionLock"
	if RealWorld.active() and not RealWorld.unlocked:
		_build_posts()


func _process(delta: float) -> void:
	if not RealWorld.active() or RealWorld.unlocked:
		return
	_t += delta
	if _t < CHECK_EVERY:
		return
	_t = 0.0
	var pl: Node3D = Life.player if "player" in Life else null
	if pl == null or not is_instance_valid(pl):
		return
	var p := Vector2(pl.global_position.x, pl.global_position.z)
	if RealWorld.in_realm(p):
		return
	var b := RealWorld.box().grow(-PUSH_IN)
	var q := Vector2(clampf(p.x, b.position.x, b.end.x), clampf(p.y, b.position.y, b.end.y))
	pl.global_position = Vector3(q.x, WorldGen.height(q.x, q.y) + 0.5, q.y)
	if "velocity" in pl:
		pl.set("velocity", Vector3.ZERO)
	Game.toast.emit(LINES[_line % LINES.size()])
	_line += 1


## Border posts as three MultiMeshes (pole, bar, lantern), skipped on water.
func _build_posts() -> void:
	var b := RealWorld.box()
	var spots: Array[Vector2] = []
	var x := b.position.x
	while x <= b.end.x:
		spots.append(Vector2(x, b.position.y))
		spots.append(Vector2(x, b.end.y))
		x += POST_STEP
	var z := b.position.y + POST_STEP
	while z < b.end.y:
		spots.append(Vector2(b.position.x, z))
		spots.append(Vector2(b.end.x, z))
		z += POST_STEP
	var keep: Array[Vector2] = []
	for s in spots:
		if not WorldGen.is_water(s.x, s.y):
			keep.append(s)
	_mm(_box_mesh(Vector3(0.35, 4.2, 0.35), Color(0.32, 0.22, 0.14)), keep, Vector3(0, 2.1, 0))
	_mm(_box_mesh(Vector3(3.2, 0.22, 0.22), Color(0.62, 0.12, 0.1)), keep, Vector3(0, 1.1, 0))
	_mm(_box_mesh(Vector3(1.1, 0.7, 0.05), Color(0.7, 0.12, 0.12)), keep, Vector3(0, 3.6, 0))
	var lamp := _box_mesh(Vector3(0.3, 0.35, 0.3), Color(1.0, 0.7, 0.3))
	(lamp.material as StandardMaterial3D).emission_enabled = true
	(lamp.material as StandardMaterial3D).emission = Color(1.0, 0.6, 0.25)
	(lamp.material as StandardMaterial3D).emission_energy_multiplier = 3.0
	_mm(lamp, keep, Vector3(0.4, 3.0, 0))
	_warden_camps(b)


## Warden camps where the old roads left the realm (the four map-edge exits, projected onto the border): a tent, a brazier and two
## spear-carrying wardens in Valencious red. Set pieces only (the turn-back line is spoken by the lock itself).
func _warden_camps(b: Rect2) -> void:
	var cloth := _box_mesh(Vector3(1, 1, 1), Color(0.55, 0.12, 0.1)).material
	var steel := _box_mesh(Vector3(1, 1, 1), Color(0.55, 0.56, 0.6)).material
	for id: String in ["edge:to_the_aurelis_patriarchate", "edge:to_the_frostcrown_holds", "edge:to_the_solkar_dominion", "site:The Eastern Gate:3772:481"]:
		var p: Variant = RealWorld.place(id)
		if p == null:
			continue
		var q := Vector2(clampf(p.x, b.position.x, b.end.x), clampf(p.y, b.position.y, b.end.y))
		var inward := (b.get_center() - q).normalized()
		q += inward * 14.0
		var g := Vector3(q.x, WorldGen.height(q.x, q.y), q.y)
		var tent := PrismMesh.new()
		tent.size = Vector3(4.5, 3.0, 5.0)
		tent.material = cloth
		_one(tent, g + Vector3(inward.x * 6.0, 1.5, inward.y * 6.0))
		var fire := SphereMesh.new()
		fire.radius = 0.5
		fire.height = 0.8
		var fm := StandardMaterial3D.new()
		fm.albedo_color = Color(1.0, 0.55, 0.2)
		fm.emission_enabled = true
		fm.emission = Color(1.0, 0.5, 0.15)
		fm.emission_energy_multiplier = 4.0
		fire.material = fm
		_one(fire, g + Vector3(0, 1.0, 0))
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.6, 0.3)
		l.omni_range = 18.0
		l.light_energy = 2.0
		l.position = g + Vector3(0, 2.0, 0)
		l.distance_fade_enabled = true
		l.distance_fade_begin = 400.0
		add_child(l)
		for s in [-1.0, 1.0]:
			var side: Vector2 = Vector2(-inward.y, inward.x) * 3.0 * float(s)
			var at := Vector3(q.x + side.x, WorldGen.height(q.x + side.x, q.y + side.y), q.y + side.y)
			var body := CapsuleMesh.new()
			body.radius = 0.35
			body.height = 1.8
			body.material = cloth
			_one(body, at + Vector3(0, 0.9, 0))
			var helm := SphereMesh.new()
			helm.radius = 0.2
			helm.height = 0.4
			helm.material = steel
			_one(helm, at + Vector3(0, 1.95, 0))
			var spear := CylinderMesh.new()
			spear.top_radius = 0.03
			spear.bottom_radius = 0.03
			spear.height = 2.6
			spear.material = steel
			_one(spear, at + Vector3(0.45, 1.3, 0))


func _one(mesh: Mesh, at: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = at
	mi.visibility_range_end = 700.0
	add_child(mi)


static func _box_mesh(size: Vector3, col: Color) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = 0.85
	m.material = mat
	return m


func _mm(mesh: Mesh, spots: Array[Vector2], off: Vector3) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = spots.size()
	for i in spots.size():
		var s := spots[i]
		mm.set_instance_transform(i, Transform3D(Basis(), Vector3(s.x, WorldGen.height(s.x, s.y), s.y) + off))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.visibility_range_end = 900.0
	add_child(mi)
