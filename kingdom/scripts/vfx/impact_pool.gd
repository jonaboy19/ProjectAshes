extends Node3D
## Pooled, layered melee impact: flash core, ground ring, slash quads, sparks / embers, dust and a ground
## splat, with an element variant (physical, fire, water, earth, wind, lightning, qi). MAX_ACTIVE slots are
## built once (a few quads and three one-shot GPUParticles each) and reused, so a flurry of hits never
## allocates and never exceeds the cap: when every slot is busy a light hit is dropped and a heavier one
## takes over the oldest slot. No lights; the additive layers run above the bloom threshold (Style G,
## glow_hdr_threshold 1.0) so only VFX glow. Preload, no class_name:
##   const ImpactPool := preload("res://scripts/vfx/impact_pool.gd")
##   ImpactPool.at(world_node).play(pos, "fire", 1, dir)

const K := preload("res://scripts/vfx/vfx_kit.gd")

const NODE_NAME := "ImpactPool"
const MAX_ACTIVE := 6
const SLASHES := 3
const SPARK_MAX := 28
const DUST_MAX := 8
## Per tier (light, heavy, finisher): overall size, spark share, slash count, seconds the slot is busy.
const TIER_SIZE := [0.8, 1.15, 1.6]
const TIER_SPARKS := [0.4, 0.7, 1.0]
const TIER_SLASHES := [1, 2, 3]
const BUSY := [0.55, 0.7, 0.85]

## Warm Style G palettes. pal: tint/hot/edge; rise: spark gravity y; v: spark speed; life: spark life;
## dust: dust colour (or null); splat: ground splat colour; ring: ring speed scale.
const VARIANTS := {
	"physical": {"pal": {"tint": Color(1.0, 0.72, 0.35), "hot": Color(1.0, 0.95, 0.8), "edge": Color(0.5, 0.2, 0.05)},
		"rise": -14.0, "v": Vector2(4.5, 9.0), "life": 0.35, "spread": 70.0, "dust": Color(0.5, 0.42, 0.33), "splat": Color(0.1, 0.07, 0.05), "ring": 1.0},
	"fire": {"pal": {"tint": Color(1.0, 0.45, 0.1), "hot": Color(1.0, 0.9, 0.62), "edge": Color(0.55, 0.06, 0.02)},
		"rise": 3.0, "v": Vector2(2.0, 5.5), "life": 0.7, "spread": 110.0, "dust": Color(0.18, 0.13, 0.1), "splat": Color(0.06, 0.03, 0.02), "ring": 0.9},
	"water": {"pal": {"tint": Color(0.35, 0.68, 0.95), "hot": Color(0.95, 0.96, 0.9), "edge": Color(0.06, 0.2, 0.45)},
		"rise": -12.0, "v": Vector2(3.0, 7.0), "life": 0.45, "spread": 100.0, "dust": null, "splat": Color(0.12, 0.2, 0.28), "ring": 1.2},
	"earth": {"pal": {"tint": Color(0.92, 0.62, 0.28), "hot": Color(1.0, 0.88, 0.62), "edge": Color(0.35, 0.18, 0.05)},
		"rise": -18.0, "v": Vector2(3.0, 6.5), "life": 0.55, "spread": 60.0, "dust": Color(0.45, 0.34, 0.22), "splat": Color(0.14, 0.1, 0.06), "ring": 0.8},
	"wind": {"pal": {"tint": Color(0.62, 0.95, 0.78), "hot": Color(0.97, 1.0, 0.92), "edge": Color(0.1, 0.4, 0.35)},
		"rise": 0.0, "v": Vector2(6.0, 12.0), "life": 0.3, "spread": 180.0, "dust": Color(0.55, 0.55, 0.48), "splat": null, "ring": 1.4},
	"lightning": {"pal": {"tint": Color(0.75, 0.78, 1.0), "hot": Color(1.0, 0.97, 0.88), "edge": Color(0.3, 0.14, 0.7)},
		"rise": 0.0, "v": Vector2(8.0, 15.0), "life": 0.2, "spread": 180.0, "dust": null, "splat": Color(0.07, 0.06, 0.1), "ring": 1.6},
	"qi": {"pal": {"tint": Color(1.0, 0.8, 0.3), "hot": Color(1.0, 0.98, 0.85), "edge": Color(0.6, 0.28, 0.02)},
		"rise": 1.5, "v": Vector2(2.5, 6.0), "life": 0.6, "spread": 180.0, "dust": null, "splat": null, "ring": 1.0},
}

var _slots: Array[Dictionary] = []
var _serial := 0


## The pool under `world` (built on first use).
static func at(world: Node) -> Node3D:
	var found := world.get_node_or_null(NODE_NAME)
	if found:
		return found
	var pool: Node3D = (load("res://scripts/vfx/impact_pool.gd") as GDScript).new()
	pool.name = NODE_NAME
	world.add_child(pool)
	return pool


static func variant(element: String) -> Dictionary:
	return VARIANTS.get(element, VARIANTS["physical"])


static func element_names() -> Array:
	return VARIANTS.keys()


func _ready() -> void:
	top_level = true
	for i in MAX_ACTIVE:
		_slots.append(_build_slot())


func slot_count() -> int:
	return _slots.size()


func active_count() -> int:
	var n := 0
	for s: Dictionary in _slots:
		if s["busy"]:
			n += 1
	return n


## Node count under the pool (a test asserts it never grows).
func node_count() -> int:
	return find_children("*", "", true, false).size()


func _build_slot() -> Dictionary:
	var root := Node3D.new()
	root.visible = false
	add_child(root)
	var neutral := {"tint": Color(1, 0.7, 0.3), "hot": Color(1, 0.95, 0.8), "edge": Color(0.5, 0.2, 0.05)}
	var s := {"root": root, "busy": false, "serial": 0, "tween": null}
	var flash_mat := K.sprite_mat(K.DOT, neutral, 4.0, {"particle": false, "billboard": true, "heat": 1.2})
	s["flash_mat"] = flash_mat
	s["flash"] = _quad(root, flash_mat, Vector2.ONE)
	var ring_mat := K.fx_mat(K.GROUND_RING, neutral, 3.0, {"progress": 0.2, "fade": 1.0, "width": 0.35, "noise_amt": 0.12})
	s["ring_mat"] = ring_mat
	var ring := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE
	ring.mesh = plane
	ring.material_override = ring_mat
	_prep(ring)
	root.add_child(ring)
	s["ring"] = ring
	var splat_mat := K.sprite_mat(K.SCORCH, neutral, 1.0, {"particle": false, "mix": true, "heat": 1.0, "cool": 0.0})
	s["splat_mat"] = splat_mat
	var splat := MeshInstance3D.new()
	var sp := PlaneMesh.new()
	sp.size = Vector2.ONE
	splat.mesh = sp
	splat.material_override = splat_mat
	_prep(splat)
	root.add_child(splat)
	s["splat"] = splat
	var slashes: Array = []
	var slash_mats: Array = []
	for i in SLASHES:
		var m := K.sprite_mat(K.STREAK, neutral, 3.0, {"particle": false, "heat": 1.2})
		slash_mats.append(m)
		slashes.append(_quad(root, m, Vector2(1.0, 0.16)))
	s["slashes"] = slashes
	s["slash_mats"] = slash_mats
	s["sparks"] = _emitter(root, {"amount": SPARK_MAX, "life": 0.4, "v": Vector2(4.0, 9.0), "spread": 70.0,
		"gravity": Vector3(0, -14, 0), "damping": Vector2(1, 3), "size": Vector2(0.05, 0.35), "stretch": true,
		"mat": K.sprite_mat(K.DOT, neutral, 5.0, {"heat": 1.5})})
	s["dust"] = _emitter(root, {"amount": DUST_MAX, "life": 0.6, "v": Vector2(0.6, 1.8), "spread": 80.0,
		"gravity": Vector3(0, 0.4, 0), "damping": Vector2(1, 2), "size": 0.7, "grow": "grow", "spin": true,
		"mat": K.sprite_mat(K.SMOKE_PUFF, neutral, 0.8, {"mix": true, "spin": true, "cool": 0.0})})
	return s


func _prep(mi: MeshInstance3D) -> void:
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED


func _quad(parent: Node3D, mat: Material, size: Vector2) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = size
	mi.mesh = q
	mi.material_override = mat
	_prep(mi)
	mi.visible = false
	parent.add_child(mi)
	return mi


func _emitter(parent: Node3D, cfg: Dictionary) -> GPUParticles3D:
	cfg["free"] = false
	cfg["fps"] = 30
	var p := K.emit(parent, parent.global_position, cfg)
	p.emitting = false
	p.amount_ratio = 1.0
	p.local_coords = false
	return p


## Plays one impact at world `pos`. `dir` points from the attacker to the victim (slashes fan across it).
## `landing` plays only the dust puff and ground splat (a body hitting the ground).
## -> true when it played, false when it was dropped by the cap (light hits only).
func play(pos: Vector3, element := "physical", tier := 0, dir := Vector3.ZERO, landing := false) -> bool:
	if _slots.is_empty():
		return false
	var slot := _take(tier)
	if slot.is_empty():
		return false
	tier = clampi(tier, 0, 2)
	var v := variant(element)
	var pal: Dictionary = v["pal"]
	var warm := {"tint": pal["tint"], "hot": (pal["hot"] as Color).lerp(Color(1.0, 0.93, 0.78), 0.35), "edge": pal["edge"]}
	var size: float = TIER_SIZE[tier]
	var root: Node3D = slot["root"]
	root.visible = true
	root.global_position = pos
	slot["busy"] = true
	_serial += 1
	slot["serial"] = _serial
	var old: Tween = slot["tween"]
	if old and old.is_valid():
		old.kill()
	var tw := create_tween().set_parallel(true)
	slot["tween"] = tw

	var flash: MeshInstance3D = slot["flash"]
	var fm: ShaderMaterial = slot["flash_mat"]
	_tint(fm, warm)
	flash.visible = not landing
	fm.set_shader_parameter("bb_scale", size * 0.5)
	fm.set_shader_parameter("fade", 1.0)
	tw.tween_property(fm, "shader_parameter/bb_scale", size * 1.7, 0.10).set_ease(Tween.EASE_OUT)
	tw.tween_property(fm, "shader_parameter/fade", 0.0, 0.12).set_delay(0.03)

	var ring: MeshInstance3D = slot["ring"]
	var rm: ShaderMaterial = slot["ring_mat"]
	_tint(rm, warm)
	ring.visible = not landing
	ring.position = Vector3(0, -0.72, 0)     # hit points sit ~0.8 m up: this puts the ring on the ground
	ring.scale = Vector3.ONE * (2.6 * size)
	var rs: float = v["ring"]
	rm.set_shader_parameter("progress", 0.15)
	rm.set_shader_parameter("fade", 1.0)
	tw.tween_property(rm, "shader_parameter/progress", 0.95, 0.30 / rs).set_ease(Tween.EASE_OUT)
	tw.tween_property(rm, "shader_parameter/fade", 0.0, 0.18).set_delay(0.14 / rs)

	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var n_sl: int = 0 if landing else TIER_SLASHES[tier]
	var slashes: Array = slot["slashes"]
	var smats: Array = slot["slash_mats"]
	var flat := Vector3(dir.x, 0.0, dir.z)
	var base := atan2(flat.z, flat.x) if flat.length() > 0.01 else 0.0
	for i in SLASHES:
		var q: MeshInstance3D = slashes[i]
		q.visible = i < n_sl
		if i >= n_sl:
			continue
		var m: ShaderMaterial = smats[i]
		_tint(m, warm)
		m.set_shader_parameter("fade", 1.0)
		var ang := (-0.6 + 0.6 * i) + (i % 2) * 0.5 + sin(float(slot["serial"]) * 1.7 + i) * 0.25
		q.position = Vector3.ZERO
		q.rotation = Vector3.ZERO
		if cam and cam.global_position.distance_squared_to(pos) > 0.01:
			q.look_at(cam.global_position, Vector3.UP)
		q.rotate_object_local(Vector3.BACK, ang)
		var len := (1.5 + 0.35 * i) * size
		q.scale = Vector3(len * 0.35, 1.0, 1.0)
		tw.tween_property(q, "scale", Vector3(len, 1.0, 1.0), 0.08).set_ease(Tween.EASE_OUT)
		tw.tween_property(m, "shader_parameter/fade", 0.0, 0.10).set_delay(0.04 + 0.02 * i)

	var sparks: GPUParticles3D = slot["sparks"]
	var spm := sparks.process_material as ParticleProcessMaterial
	spm.gravity = Vector3(0, float(v["rise"]), 0)
	var sv: Vector2 = v["v"]
	spm.initial_velocity_min = sv.x * (0.8 + 0.2 * tier)
	spm.initial_velocity_max = sv.y * (0.8 + 0.2 * tier)
	spm.spread = float(v["spread"])
	spm.direction = (flat.normalized() * 0.4 + Vector3.UP * 0.6).normalized() if flat.length() > 0.01 else Vector3.UP
	sparks.lifetime = float(v["life"])
	sparks.amount_ratio = TIER_SPARKS[tier]
	(sparks.draw_pass_1 as QuadMesh).material = K.sprite_mat(K.DOT, warm, 5.0, {"heat": 1.5})
	if landing:
		sparks.emitting = false
	else:
		sparks.restart()
		sparks.emitting = true

	var dust: GPUParticles3D = slot["dust"]
	var dcol: Variant = v["dust"]
	dust.visible = dcol != null and not K.lite()
	if dust.visible:
		var c: Color = dcol
		dust.position = Vector3(0, -0.05 if landing else -0.6, 0)
		(dust.draw_pass_1 as QuadMesh).material = K.sprite_mat(K.SMOKE_PUFF,
			{"tint": c, "hot": c.lightened(0.2), "edge": c.darkened(0.4)}, 0.8, {"mix": true, "spin": true, "cool": 0.0})
		dust.amount_ratio = 0.4 + 0.3 * tier
		dust.restart()
		dust.emitting = true

	var splat: MeshInstance3D = slot["splat"]
	var scol: Variant = v["splat"]
	splat.visible = scol != null and (tier >= 1 or landing)
	if splat.visible:
		var sm: ShaderMaterial = slot["splat_mat"]
		var c2: Color = scol
		_tint(sm, {"tint": c2, "hot": c2.lightened(0.15), "edge": c2.darkened(0.3)})
		sm.set_shader_parameter("fade", 0.85)
		splat.position = Vector3(0, -0.15 if landing else -0.74, 0)
		splat.scale = Vector3.ONE * (1.6 * size)
		splat.rotation.y = float(slot["serial"]) * 2.4
		tw.tween_property(sm, "shader_parameter/fade", 0.0, 0.7).set_delay(0.12)

	var serial: int = slot["serial"]
	var busy: float = BUSY[tier]
	var done := create_tween()
	slot["done"] = done
	done.tween_interval(busy)
	done.tween_callback(_release.bind(slot, serial))
	return true


func _tint(m: ShaderMaterial, pal: Dictionary) -> void:
	m.set_shader_parameter("tint", pal["tint"])
	m.set_shader_parameter("hot", pal["hot"])
	m.set_shader_parameter("edge", pal["edge"])


func _release(slot: Dictionary, serial: int) -> void:
	if int(slot["serial"]) != serial:
		return
	slot["busy"] = false
	(slot["root"] as Node3D).visible = false


## A free slot; else the oldest one for a heavier hit; light hits are dropped (the cap).
func _take(tier: int) -> Dictionary:
	var oldest: Dictionary = {}
	var oldest_serial := 1 << 60
	for s: Dictionary in _slots:
		if not s["busy"]:
			return s
		if int(s["serial"]) < oldest_serial:
			oldest_serial = int(s["serial"])
			oldest = s
	if tier <= 0:
		return {}
	return oldest
