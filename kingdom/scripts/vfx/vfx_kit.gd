extends RefCounted
## Building blocks shared by the VFX library (vfx.gd and its vfx_* parts):
## materials for the atlas/mesh/circle shaders, a GPUParticles3D builder, ribbon
## meshes, and tween helpers that animate shader parameters engine-side (no
## per-frame GDScript). Everything here is static. Preload it, don't instance it.

const SPRITE := preload("res://shaders/vfx_sprite.gdshader")
const SMOKE := preload("res://shaders/vfx_smoke.gdshader")
const FX := preload("res://shaders/vfx_fx.gdshader")
const CIRCLE := preload("res://shaders/vfx_circle.gdshader")
const GHOST := preload("res://shaders/vfx_ghost.gdshader")
const IMPACT := preload("res://shaders/vfx_impact.gdshader")
const ATLAS := preload("res://assets/incoming/vfx/atlas/vfx_atlas.png")
const NOISE := preload("res://assets/incoming/vfx/atlas/vfx_noise.png")

# Atlas cells (assets/incoming/vfx/README.md).
const FLAME := 0
const BLOB := 1
const SMOKE_PUFF := 2
const FIRE := 3
const BOLT := 4
const BRANCH := 5
const STAR := 6
const SPARKLE := 7
const TWIRL := 8
const CRESCENT := 9
const SCORCH := 10
const DEBRIS := 11
const STREAK := 12
const RING := 13
const RADIAL := 14
const SWIRL := 15
const DOT := -1
const SHARD := -2
const SOFT_RING := -3

# FX shader modes
const SMEAR := 0
const COLUMN := 1
const CRACK := 2
const ORB := 3
const GROUND_RING := 4
const BEAM := 5
const TEAR := 6

## Per-element palette: tint (body), hot (core), edge (rim), plus circle layout.
const PAL := {
	"fire": {"tint": Color(1.0, 0.42, 0.08), "hot": Color(1.0, 0.93, 0.62), "edge": Color(0.55, 0.06, 0.02), "sides": 6, "skip": 2},
	"water": {"tint": Color(0.2, 0.62, 1.0), "hot": Color(0.85, 0.97, 1.0), "edge": Color(0.02, 0.15, 0.5), "sides": 8, "skip": 3},
	"wind": {"tint": Color(0.45, 1.0, 0.78), "hot": Color(0.93, 1.0, 0.96), "edge": Color(0.05, 0.4, 0.35), "sides": 5, "skip": 2},
	"earth": {"tint": Color(0.95, 0.62, 0.25), "hot": Color(1.0, 0.9, 0.62), "edge": Color(0.35, 0.18, 0.05), "sides": 4, "skip": 1},
	"lightning": {"tint": Color(0.55, 0.62, 1.0), "hot": Color(0.95, 0.96, 1.0), "edge": Color(0.28, 0.12, 0.75), "sides": 5, "skip": 2},
	"qi": {"tint": Color(1.0, 0.78, 0.25), "hot": Color(1.0, 0.98, 0.85), "edge": Color(0.6, 0.28, 0.02), "sides": 8, "skip": 3},
	"heal": {"tint": Color(0.45, 1.0, 0.5), "hot": Color(0.95, 1.0, 0.85), "edge": Color(0.05, 0.4, 0.15), "sides": 6, "skip": 1},
	"poison": {"tint": Color(0.55, 0.95, 0.15), "hot": Color(0.9, 1.0, 0.6), "edge": Color(0.2, 0.05, 0.3), "sides": 7, "skip": 3},
	"frost": {"tint": Color(0.55, 0.85, 1.0), "hot": Color(0.95, 1.0, 1.0), "edge": Color(0.1, 0.3, 0.7), "sides": 6, "skip": 1},
	"holy": {"tint": Color(1.0, 0.85, 0.45), "hot": Color(1.0, 1.0, 0.92), "edge": Color(0.7, 0.45, 0.1), "sides": 12, "skip": 5},
	"shadow": {"tint": Color(0.5, 0.25, 0.85), "hot": Color(0.9, 0.8, 1.0), "edge": Color(0.1, 0.02, 0.2), "sides": 6, "skip": 2},
	"metal": {"tint": Color(0.7, 0.85, 1.0), "hot": Color(1.0, 1.0, 1.0), "edge": Color(0.2, 0.35, 0.6), "sides": 8, "skip": 3},
	"wood": {"tint": Color(0.5, 0.9, 0.3), "hot": Color(0.92, 1.0, 0.7), "edge": Color(0.1, 0.3, 0.05), "sides": 5, "skip": 2},
	"war": {"tint": Color(1.0, 0.35, 0.15), "hot": Color(1.0, 0.9, 0.7), "edge": Color(0.4, 0.05, 0.02), "sides": 8, "skip": 3},
	"rift": {"tint": Color(0.68, 0.28, 1.0), "hot": Color(0.98, 0.85, 1.0), "edge": Color(0.2, 0.02, 0.45), "sides": 7, "skip": 2},
}


# Shared resources: particle materials, curves and ramps are cached so a spell
# doesn't rebuild textures or materials on the CPU every cast.
static var _mat_cache := {}
static var _tex_cache := {}


static func pal(element: String) -> Dictionary:
	return PAL.get(element, PAL["qi"])


## A palette from any single colour: darker, saturated rim and a near-white core.
static func pal_from(c: Color) -> Dictionary:
	return {"tint": c, "hot": c.lerp(Color(1, 1, 1), 0.75), "edge": Color(c.r * 0.35, c.g * 0.25, c.b * 0.4), "sides": 6, "skip": 2}


# --- quality -------------------------------------------------------------------
# GPUParticles3D amounts are already scaled by the Quality autoload (amount_ratio).
# These gates drop whole optional layers (lights, smoke, secondary emitters).

static func _quality() -> Node:
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		return (ml as SceneTree).root.get_node_or_null("Quality")
	return null


static func tier() -> int:
	var q := _quality()
	return int(q.get("tier")) if q else 2


## Low tier: skip lights and secondary layers.
static func lite() -> bool:
	return tier() <= 0


## High tier and up: extra flourishes (dynamic lights on every impact).
static func rich() -> bool:
	return tier() >= 2


# --- materials ------------------------------------------------------------------

static func _apply_pal(m: ShaderMaterial, p: Dictionary) -> void:
	m.set_shader_parameter("tint", p["tint"])
	m.set_shader_parameter("hot", p["hot"])
	m.set_shader_parameter("edge", p["edge"])


## A ShaderMaterial with every uniform set to its shader default, so tweens on
## any parameter are valid from the start (unset parameters read back as null).
static func shader_mat(shader: Shader) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader
	for u: Dictionary in shader.get_shader_uniform_list():
		var n := String(u["name"])
		var d: Variant = RenderingServer.shader_get_parameter_default(shader.get_rid(), n)
		if d == null:
			# Headless / dummy renderer: no defaults. Cover the tweened ones.
			d = {"fade": 1.0, "dissolve": 0.0, "bb_scale": 1.0, "progress": 0.0 if shader == IMPACT else 1.0,
				"strength": 1.0, "energy": 3.0}.get(n, null)
		if d != null:
			m.set_shader_parameter(n, d)
	if shader != IMPACT:
		m.set_shader_parameter("noise_tex", NOISE)
	return m


## Atlas sprite material. Particle materials (the default) are cached and shared;
## pass {"particle": false} for a unique one you can tween.
static func sprite_mat(cell: int, p: Dictionary, energy := 3.0, opts := {}) -> ShaderMaterial:
	var shared: bool = opts.get("particle", true)
	var key := ""
	if shared:
		key = "%d|%s|%s|%s|%.2f|%s" % [cell, p["tint"], p["hot"], p["edge"], energy, opts]
		if _mat_cache.has(key):
			return _mat_cache[key]
	var m := _new_sprite_mat(cell, p, energy, opts)
	if shared:
		_mat_cache[key] = m
	return m


static func _new_sprite_mat(cell: int, p: Dictionary, energy: float, opts: Dictionary) -> ShaderMaterial:
	var m := shader_mat(SMOKE if opts.get("mix", false) else SPRITE)
	m.set_shader_parameter("atlas", ATLAS)
	m.set_shader_parameter("cell", cell)
	m.set_shader_parameter("energy", energy)
	_apply_pal(m, p)
	for k in ["heat", "cool", "spin", "distort", "particle", "billboard", "bb_scale", "fade"]:
		if opts.has(k):
			m.set_shader_parameter(k, opts[k])
	return m


static func fx_mat(mode: int, p: Dictionary, energy := 3.0, opts := {}) -> ShaderMaterial:
	var m := shader_mat(FX)
	m.set_shader_parameter("mode", mode)
	m.set_shader_parameter("energy", energy)
	m.set_shader_parameter("seed", randf() * 10.0)
	_apply_pal(m, p)
	for k: String in opts:
		m.set_shader_parameter(k, opts[k])
	return m


# --- nodes ----------------------------------------------------------------------

static func free_after(node: Node, seconds: float) -> void:
	var tw := node.create_tween()
	tw.tween_interval(seconds)
	tw.tween_callback(node.queue_free)


static func add(parent: Node, node: Node3D, pos: Vector3) -> Node3D:
	parent.add_child(node)
	node.global_position = pos
	return node


## Tween a shader parameter on `mat`, bound to `owner` (dies with it).
static func anim(owner: Node, mat: ShaderMaterial, param: String, from: Variant, to: Variant, seconds: float,
		delay := 0.0, ease := Tween.EASE_OUT, trans := Tween.TRANS_QUAD) -> Tween:
	mat.set_shader_parameter(param, from)
	var tw := owner.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_property(mat, "shader_parameter/" + param, to, seconds).set_ease(ease).set_trans(trans)
	return tw


static func mesh_node(parent: Node, mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add(parent, mi, pos)
	return mi


## Mesh whose vertices are already in world space (bolts, whips, spirals).
static func world_mesh(parent: Node, mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := mesh_node(parent, mesh, mat, Vector3.ZERO)
	mi.global_transform = Transform3D.IDENTITY
	return mi


static func quad(parent: Node, pos: Vector3, mat: Material, size: float) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = Vector2.ONE * size
	return mesh_node(parent, q, mat, pos)


## Flat quad lying on the ground (XZ), slightly lifted against z-fighting.
static func ground(parent: Node, pos: Vector3, mat: Material, size: float) -> MeshInstance3D:
	var q := PlaneMesh.new()
	q.size = Vector2.ONE * size
	return mesh_node(parent, q, mat, pos + Vector3(0, 0.06, 0))


## Camera-facing glow sprite that swells in and fades out.
static func glow(parent: Node, pos: Vector3, p: Dictionary, size: float, seconds: float, cell := DOT, energy := 3.0) -> MeshInstance3D:
	var mat := sprite_mat(cell, p, energy, {"particle": false, "billboard": true, "heat": 1.15})
	var mi := quad(parent, pos, mat, 1.0)
	anim(mi, mat, "bb_scale", size * 0.35, size, seconds * 0.35)
	anim(mi, mat, "fade", 1.0, 0.0, seconds * 0.8, seconds * 0.2, Tween.EASE_IN)
	free_after(mi, seconds + 0.05)
	return mi


static func light(parent: Node, pos: Vector3, color: Color, energy := 2.0, seconds := 0.25, light_range := 5.0) -> void:
	if lite():
		return
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = light_range
	l.shadow_enabled = false
	add(parent, l, pos)
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, seconds).set_ease(Tween.EASE_IN)
	tw.tween_callback(l.queue_free)


# --- particles ------------------------------------------------------------------

static func _curve(points: Array) -> CurveTexture:
	var key := str(points)
	if _tex_cache.has(key):
		return _tex_cache[key]
	var c := Curve.new()
	for pt: Vector2 in points:
		c.add_point(pt)
	var ct := CurveTexture.new()
	ct.width = 64
	ct.curve = c
	_tex_cache[key] = ct
	return ct


static func _alpha_ramp(kind: String) -> GradientTexture1D:
	if _tex_cache.has("ramp_" + kind):
		return _tex_cache["ramp_" + kind]
	var g := Gradient.new()
	match kind:
		"inout":
			g.offsets = PackedFloat32Array([0.0, 0.15, 0.7, 1.0])
			g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0.8), Color(1, 1, 1, 0)])
		"late":
			g.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
			g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0)])
		_:
			g.offsets = PackedFloat32Array([0.0, 1.0])
			g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var gt := GradientTexture1D.new()
	gt.width = 64
	gt.gradient = g
	_tex_cache["ramp_" + kind] = gt
	return gt


## One GPUParticles3D from a config dictionary. Keys (all optional):
##  amount, life, one_shot (true), explosive (0.9), local (false), delay,
##  shape "point"|"sphere"|"ring"|"box"|"disc", radius, inner, extents (Vector3), axis,
##  dir (Vector3.UP), spread, v (Vector2 min/max speed), gravity (Vector3),
##  damping (Vector2), radial (Vector2 accel), tangent (Vector2 accel, around gravity axis),
##  scale (Vector2), size (float or Vector2 quad), grow "shrink"|"grow"|"pop"|"flat",
##  alpha "out"|"inout"|"late", stretch (align to velocity), spin (random angle),
##  angular (Vector2 deg/s), mat (Material), free (auto-free, default true when one_shot).
static func emit(parent: Node, pos: Vector3, cfg: Dictionary) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	var one_shot: bool = cfg.get("one_shot", true)
	p.amount = maxi(1, int(cfg.get("amount", 16)))
	p.lifetime = float(cfg.get("life", 0.8))
	p.one_shot = one_shot
	p.explosiveness = float(cfg.get("explosive", 0.9 if one_shot else 0.0))
	p.randomness = float(cfg.get("randomness", 0.3))
	p.local_coords = bool(cfg.get("local", false))
	p.fixed_fps = int(cfg.get("fps", 30))
	p.interpolate = true
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	var pm := ParticleProcessMaterial.new()
	var r := float(cfg.get("radius", 0.2))
	match String(cfg.get("shape", "point")):
		"sphere":
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
			pm.emission_sphere_radius = r
		"ring", "disc":
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
			pm.emission_ring_axis = cfg.get("axis", Vector3.UP)
			pm.emission_ring_radius = r
			pm.emission_ring_inner_radius = float(cfg.get("inner", r * 0.85 if cfg.get("shape") == "ring" else 0.0))
			pm.emission_ring_height = float(cfg.get("height", 0.05))
		"box":
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
			pm.emission_box_extents = cfg.get("extents", Vector3.ONE * r)
	pm.direction = cfg.get("dir", Vector3.UP)
	pm.spread = float(cfg.get("spread", 45.0))
	var v: Vector2 = cfg.get("v", Vector2(1.0, 3.0))
	pm.initial_velocity_min = v.x
	pm.initial_velocity_max = v.y
	pm.gravity = cfg.get("gravity", Vector3.ZERO)
	var damp: Vector2 = cfg.get("damping", Vector2(0.5, 1.5))
	pm.damping_min = damp.x
	pm.damping_max = damp.y
	if cfg.has("radial"):
		pm.radial_accel_min = (cfg["radial"] as Vector2).x
		pm.radial_accel_max = (cfg["radial"] as Vector2).y
	if cfg.has("tangent"):
		pm.tangential_accel_min = (cfg["tangent"] as Vector2).x
		pm.tangential_accel_max = (cfg["tangent"] as Vector2).y
	var sc: Vector2 = cfg.get("scale", Vector2(0.6, 1.0))
	pm.scale_min = sc.x
	pm.scale_max = sc.y
	match String(cfg.get("grow", "shrink")):
		"grow":
			pm.scale_curve = _curve([Vector2(0, 0.35), Vector2(1, 1)])
		"pop":
			pm.scale_curve = _curve([Vector2(0, 0.2), Vector2(0.15, 1), Vector2(1, 0.6)])
		"flat":
			pass
		_:
			pm.scale_curve = _curve([Vector2(0, 1), Vector2(1, 0)])
	pm.color_ramp = _alpha_ramp(String(cfg.get("alpha", "out")))
	if cfg.get("spin", false):
		pm.angle_min = -180.0
		pm.angle_max = 180.0
	if cfg.has("angular"):
		pm.angular_velocity_min = (cfg["angular"] as Vector2).x
		pm.angular_velocity_max = (cfg["angular"] as Vector2).y
	var quad_mesh := QuadMesh.new()
	var size: Variant = cfg.get("size", 0.3)
	quad_mesh.size = size if size is Vector2 else Vector2.ONE * float(size)
	quad_mesh.material = cfg.get("mat", null)
	p.draw_pass_1 = quad_mesh
	if cfg.get("stretch", false):
		pm.particle_flag_align_y = true
		p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	else:
		p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD
	p.process_material = pm
	var delay := float(cfg.get("delay", 0.0))
	p.emitting = delay <= 0.0
	add(parent, p, pos)
	var cull := float(cfg.get("cull", 0.0))
	if cull > 0.0:
		p.visibility_aabb = AABB(Vector3.ONE * -cull, Vector3.ONE * cull * 2.0)
	else:
		p.visibility_aabb = AABB(Vector3(-8, -4, -8), Vector3(16, 14, 16))
	if delay > 0.0:
		var tw := p.create_tween()
		tw.tween_interval(delay)
		tw.tween_callback(p.set_emitting.bind(true))
	if one_shot and cfg.get("free", true):
		free_after(p, delay + p.lifetime * 1.3 + 0.2)
	return p


## Stop a looping emitter and free it once its last particles have faded.
static func stop(p: Variant) -> void:
	if not is_instance_valid(p) or not (p is GPUParticles3D):
		return
	var e := p as GPUParticles3D
	e.emitting = false
	free_after(e, e.lifetime + 0.1)


# --- meshes ---------------------------------------------------------------------

## Crescent ribbon in the XZ plane opening toward +Z. UV.x 0 (tail) .. 1 (head),
## UV.y 0 (inner) .. 1 (outer). Thicker in the middle like a brush stroke.
## `bowl` drops the inner edge (fraction of the band width) so the stroke is a
## shallow cone and still reads when the camera sees the swing nearly edge-on.
static func arc_mesh(radius: float, arc_deg := 160.0, thickness := 0.45, segs := 24, bowl := 0.6) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var arc := deg_to_rad(arc_deg)
	for i in segs:
		var t0 := float(i) / segs
		var t1 := float(i + 1) / segs
		var verts: Array = []
		for tt: float in [t0, t1]:
			var ang := -arc * 0.5 + arc * tt
			var th := thickness * (0.25 + 0.75 * sin(PI * clampf(tt * 0.85 + 0.15, 0.0, 1.0)))
			var ri := radius * (1.0 - th)
			verts.append([Vector3(sin(ang) * ri, -(radius - ri) * bowl, cos(ang) * ri), Vector2(tt, 0)])
			verts.append([Vector3(sin(ang) * radius, 0, cos(ang) * radius), Vector2(tt, 1)])
		for k: int in [0, 1, 3, 0, 3, 2]:
			st.set_uv(verts[k][1])
			st.add_vertex(verts[k][0])
	return st.commit()


## Flat ribbon through `pts` (world or local points), `width` across, facing `up`.
## UV.x runs 0..1 along, UV.y 0..1 across. `up` = Vector3.ZERO makes the ribbon
## stand radially around the Y axis through `center` (spirals).
static func path_mesh(pts: PackedVector3Array, width: float, up := Vector3.UP, taper := true, center := Vector3.ZERO) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := pts.size()
	var rows: Array = []
	for i in n:
		var a := pts[maxi(i - 1, 0)]
		var b := pts[mini(i + 1, n - 1)]
		var fwd := (b - a).normalized()
		var u := up
		if u == Vector3.ZERO:
			u = Vector3(pts[i].x - center.x, 0.0, pts[i].z - center.z).normalized()
		var side := fwd.cross(u).normalized()
		if side.length() < 0.01:
			side = fwd.cross(Vector3.RIGHT).normalized()
		var t := float(i) / (n - 1)
		var w := width * (sin(PI * clampf(t, 0.05, 0.95)) if taper else 1.0)
		rows.append([pts[i] - side * w * 0.5, pts[i] + side * w * 0.5, t])
	for i in n - 1:
		var r0: Array = rows[i]
		var r1: Array = rows[i + 1]
		var quad_v := [[r0[0], Vector2(r0[2], 0)], [r0[1], Vector2(r0[2], 1)], [r1[1], Vector2(r1[2], 1)],
			[r0[0], Vector2(r0[2], 0)], [r1[1], Vector2(r1[2], 1)], [r1[0], Vector2(r1[2], 0)]]
		for vv: Array in quad_v:
			st.set_uv(vv[1])
			st.add_vertex(vv[0])
	return st.commit()


## Jagged lightning ribbon from `a` to `b` (world points), camera-agnostic cross
## ribbon (two perpendicular strips) so it reads from any angle.
static func bolt_mesh(a: Vector3, b: Vector3, jag := 0.6, width := 0.14, segs := 10) -> ArrayMesh:
	var pts := PackedVector3Array()
	var dir := (b - a)
	var side1 := dir.cross(Vector3.UP).normalized()
	if side1.length() < 0.01:
		side1 = Vector3.RIGHT
	var side2 := dir.cross(side1).normalized()
	for i in segs + 1:
		var t := float(i) / segs
		var off := Vector3.ZERO
		if i > 0 and i < segs:
			off = side1 * randf_range(-jag, jag) + side2 * randf_range(-jag, jag)
		pts.append(a.lerp(b, t) + off)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side: Vector3 in [side1, side2]:
		for i in segs:
			var p0 := pts[i]
			var p1 := pts[i + 1]
			var w0 := width * (1.0 - 0.5 * float(i) / segs)
			var w1 := width * (1.0 - 0.5 * float(i + 1) / segs)
			var t0 := float(i) / segs
			var t1 := float(i + 1) / segs
			for vv: Array in [[p0 - side * w0, Vector2(t0, 0)], [p0 + side * w0, Vector2(t0, 1)], [p1 + side * w1, Vector2(t1, 1)],
					[p0 - side * w0, Vector2(t0, 0)], [p1 + side * w1, Vector2(t1, 1)], [p1 - side * w1, Vector2(t1, 0)]]:
				st.set_uv(vv[1])
				st.add_vertex(vv[0])
	return st.commit()


## Helix ribbon around +Y from 0 to `height`, `turns` times, radius shrinking to `r1`.
static func helix_points(r0: float, r1: float, height: float, turns: float, n := 48) -> PackedVector3Array:
	var pts := PackedVector3Array()
	for i in n:
		var t := float(i) / (n - 1)
		var a := t * turns * TAU
		var r := lerpf(r0, r1, t)
		pts.append(Vector3(cos(a) * r, t * height, sin(a) * r))
	return pts
