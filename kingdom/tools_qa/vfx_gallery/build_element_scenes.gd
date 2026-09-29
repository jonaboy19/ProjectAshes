extends SceneTree
## Generates every scene in scenes/vfx/elements/ (charge, aura, projectile, beam, impact, aoe,
## status per element + generic slash / sparks / dash / level up) as real .tscn files.
## Regenerate after editing this file:
##   Godot --headless --path kingdom --script res://tools_qa/vfx_gallery/build_element_scenes.gd
## Optional: `-- fire,ice` builds only those elements (generic scenes always build with `generic`).
## Conventions: effects point along -Z; aoe scenes are 3 m radius at scale 1; beam scenes are 1 m long
## (scaled in z by ElementFX.aim_beam); everything is built from el_add / el_mix / el_solid meshes,
## el_sprite glows and a few small GPUParticles3D emitters (see docs/art/vfx_elements/README.md).

const EF := preload("res://scripts/vfx/element_fx.gd")
const EE := preload("res://scripts/vfx/element_effect.gd")
const K := preload("res://scripts/vfx/vfx_kit.gd")
const TEXDIR := "res://assets/incoming/vfx_free/kenney_particle_pack/"
const RTEXDIR := "res://assets/incoming/vfx_free/rpicster_vfx_textures/"
const OUT := "res://scenes/vfx/elements/"
const SHADERS := {
	"add": "res://shaders/vfx_elements/el_add.gdshader",
	"mix": "res://shaders/vfx_elements/el_mix.gdshader",
	"solid": "res://shaders/vfx_elements/el_solid.gdshader",
	"fire": "res://shaders/vfx_elements/el_fire.gdshader",
	"shimmer": "res://shaders/vfx_elements/el_shimmer.gdshader",
}
const SPRITE := "res://shaders/vfx_elements/el_sprite.gdshader"

var _pm_cache := {}
var _count := 0


func _init() -> void:
	var only := ""
	for a in OS.get_cmdline_user_args():
		only = a
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + "_shared"))
	var els := ["fire", "water", "earth", "wind", "lightning", "ice", "light", "dark"]
	for el in els:
		if only != "" and not only.split(",").has(el):
			continue
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + el))
		call("build_" + el)
	if only == "" or only.split(",").has("generic"):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + "generic"))
		build_generic()
	print("built %d scenes" % _count)
	quit()


# ---------------------------------------------------------------- helpers
func pal(el: String) -> Dictionary:
	return EF.PAL[StringName(el)]


func A(p: String, a: Variant, b: Variant, t0 := 0.0, t1 := 1.0, e := "lin") -> Dictionary:
	return {"p": p, "a": a, "b": b, "t0": t0, "t1": t1, "e": e}


func fxmat(blend: String, el: String, prm := {}) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(SHADERS["add" if blend == "glow" else ("mix" if blend == "add" else blend)])
	var p := pal(el)
	m.set_shader_parameter("col_core", p["core"])
	m.set_shader_parameter("col_mid", p["mid"])
	m.set_shader_parameter("col_edge", p["edge"])
	for k in prm:
		m.set_shader_parameter(k, prm[k])
	return m


## Camera-facing glow sprite (el_sprite). `tint` may be a Color; `tex` a Kenney/RPicster name.
func spr_mat(tex: String, tint: Color, intensity := 1.0, spin := 0.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(SPRITE)
	var path := (RTEXDIR + tex + ".png") if tex.begins_with("effect_") or tex.begins_with("spotlight_") else (TEXDIR + tex + ".png")
	m.set_shader_parameter("tex", load(path))
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("intensity", intensity)
	m.set_shader_parameter("spin", spin)
	return m


func node(par: Node, nm: String, pos := Vector3.ZERO) -> Node3D:
	var n := Node3D.new()
	n.name = nm
	n.position = pos
	par.add_child(n)
	return n


func mesh(par: Node, nm: String, m: Mesh, mat: Material, pos := Vector3.ZERO, rot := Vector3.ZERO, scl := Vector3.ONE, anims: Array = [], tier := 0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = nm
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot
	mi.scale = scl
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mi.extra_cull_margin = 2.0
	if not anims.is_empty():
		mi.set_meta("anims", anims)
	if tier > 0:
		mi.set_meta("tier_min", tier)
	par.add_child(mi)
	return mi


func spr(par: Node, nm: String, tex: String, size: float, tint: Color, intensity := 1.0, pos := Vector3.ZERO, anims: Array = [], spin := 0.0, tier := 0) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	return mesh(par, nm, q, spr_mat(tex, tint, intensity, spin), pos, Vector3.ZERO, Vector3.ONE, anims, tier)


func cyl(rt: float, rb: float, h: float, seg := 16, caps := false) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = rt
	c.bottom_radius = rb
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	c.cap_top = caps
	c.cap_bottom = caps
	return c


func sph(r: float, seg := 16, rings := 8) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = seg
	s.rings = rings
	return s


## Flat ground quad, radius r (shader mesh_r must equal r).
func grd(r: float) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(r * 2.0, r * 2.0)
	q.orientation = PlaneMesh.FACE_Y
	return q


## Flame tongue placement: n tongues scattered between radii r0..r1 (golden-angle spread + jitter), each w x h metres
## (+-`var_` random size), growth delay d0..d1 (fraction of the `grow` animation). Feed to flame_mesh().
func fire_ring(n: int, r0: float, r1: float, w: float, h: float, seed_: int, d0 := 0.0, d1 := 0.3, var_ := 0.35) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1000 + seed_
	var out: Array = []
	for i in n:
		var a := i * 2.39996 + rng.randf_range(-0.3, 0.3)
		var rr := lerpf(r0, r1, sqrt((i + rng.randf_range(0.0, 0.8)) / float(n)))
		var k := 1.0 + rng.randf_range(-var_, var_)
		out.append({"x": cos(a) * rr, "z": sin(a) * rr, "w": w * (0.85 + 0.3 * rng.randf()), "h": h * k, "ph": rng.randf(), "d": rng.randf_range(d0, d1)})
	return out


## One mesh holding every flame tongue (el_fire.gdshader mode 0 billboards them around Y in the vertex shader).
## Vertex xy = offset inside the tongue, UV = tongue space (y 0 base .. 1 tip), UV2 = base xz, COLOR = phase, -, delay.
## The AABB is set by hand because the vertex shader moves the tongues far from their vertices.
func flame_mesh(tongues: Array, aabb_r := 3.5, aabb_h := 3.5) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for t: Dictionary in tongues:
		var w: float = t["w"]
		var h: float = t["h"]
		var col := Color(t["ph"], 1.0, t["d"], 1.0)
		var b2 := Vector2(t["x"], t["z"])
		var q := [[-w * 0.5, 0.0, 0.0, 0.0], [w * 0.5, 0.0, 1.0, 0.0], [w * 0.5, h, 1.0, 1.0], [-w * 0.5, 0.0, 0.0, 0.0], [w * 0.5, h, 1.0, 1.0], [-w * 0.5, h, 0.0, 1.0]]
		for v: Array in q:
			st.set_color(col)
			st.set_uv(Vector2(v[2], v[3]))
			st.set_uv2(b2)
			st.add_vertex(Vector3(v[0], v[1], 0.0))
	var am := st.commit()
	am.custom_aabb = AABB(Vector3(-aabb_r, -0.2, -aabb_r), Vector3(aabb_r * 2.0, aabb_h + 0.4, aabb_r * 2.0))
	return am


func light(par: Node, col: Color, energy: float, rng: float, decay: float, pos := Vector3.ZERO, delay := 0.0) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.name = "Flash"
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng
	l.shadow_enabled = false
	l.position = pos
	l.set_meta("flash", {"e": energy, "t": decay, "d": delay})
	l.set_meta("tier_min", 2)
	par.add_child(l)
	return l


func pmat(tex: String, blend := "add") -> Material:
	var key := tex + "_" + blend
	if _pm_cache.has(key):
		return _pm_cache[key]
	var path := OUT + "_shared/p_%s.tres" % key
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if blend == "add" else BaseMaterial3D.BLEND_MODE_MIX
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	m.disable_fog = true
	m.albedo_texture = load((RTEXDIR + tex + ".png") if tex.begins_with("effect_") or tex.begins_with("spotlight_") else (TEXDIR + tex + ".png"))
	ResourceSaver.save(m, path)
	m = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
	_pm_cache[key] = m
	return m


var _fill := {}


## Fraction of the texture (w, h) covered by the visible shape (alpha > 0.35), so `size` in ps() means real metres.
func tex_fill(tex: String) -> Vector2:
	if _fill.has(tex):
		return _fill[tex]
	var path := (RTEXDIR + tex + ".png") if tex.begins_with("effect_") or tex.begins_with("spotlight_") else (TEXDIR + tex + ".png")
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	var x0 := img.get_width()
	var x1 := 0
	var y0 := img.get_height()
	var y1 := 0
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.35:
				x0 = mini(x0, x)
				x1 = maxi(x1, x)
				y0 = mini(y0, y)
				y1 = maxi(y1, y)
	var f := Vector2(clampf(float(x1 - x0 + 1) / img.get_width(), 0.06, 1.0), clampf(float(y1 - y0 + 1) / img.get_height(), 0.06, 1.0))
	_fill[tex] = f
	return f


func ramp(cols: Array) -> GradientTexture1D:
	var g := Gradient.new()
	var offs := PackedFloat32Array()
	var cs := PackedColorArray()
	for i in cols.size():
		var it: Variant = cols[i]
		if it is Array:
			offs.append(it[0])
			cs.append(it[1])
		else:
			offs.append(float(i) / float(cols.size() - 1))
			cs.append(it)
	g.offsets = offs
	g.colors = cs
	var t := GradientTexture1D.new()
	t.gradient = g
	return t


func curve(pts: Array) -> CurveTexture:
	var c := Curve.new()
	for p in pts:
		c.add_point(p)
	var t := CurveTexture.new()
	t.curve = c
	return t


## Colour-over-life ramp from a palette: fades in fast, holds the body colour, cools to the edge colour.
func life_cols(el: String, alpha := 1.0, hot := true) -> Array:
	var p := pal(el)
	var core: Color = p["core"]
	var mid: Color = p["mid"]
	var edge: Color = p["edge"]
	if hot:
		return [[0.0, Color(core, 0.0)], [0.1, Color(core, alpha)], [0.4, Color(mid, alpha * 0.9)], [0.78, Color(edge, alpha * 0.5)], [1.0, Color(edge, 0.0)]]
	return [[0.0, Color(mid, 0.0)], [0.15, Color(mid, alpha)], [0.7, Color(edge, alpha * 0.7)], [1.0, Color(edge, 0.0)]]


## GPU particle emitter. cfg keys: tex, blend, n, life, once, expl, local, shape (point|sphere|ring|box), radius, inner, ext,
## axis, dir, spread, v [min,max], grav, damp [min,max], radial [min,max], tangent [min,max], orbit, scale [min,max],
## size (float|Vector2), curve (shrink|grow|pop|flat|mid), cols (life ramp), stretch, spin, angvel, delay, tier, tint, aabb, pos.
func ps(par: Node, nm: String, c: Dictionary) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = nm
	p.amount = int(c.get("n", 12))
	p.lifetime = float(c.get("life", 0.8))
	p.one_shot = bool(c.get("once", true))
	p.explosiveness = float(c.get("expl", 0.9 if p.one_shot else 0.0))
	p.randomness = 0.4
	p.local_coords = bool(c.get("local", false))
	p.fixed_fps = 30
	p.interpolate = true
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	p.emitting = false
	var pm := ParticleProcessMaterial.new()
	var r := float(c.get("radius", 0.2))
	match String(c.get("shape", "point")):
		"sphere":
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
			pm.emission_sphere_radius = r
		"ring":
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
			pm.emission_ring_axis = c.get("axis", Vector3.UP)
			pm.emission_ring_radius = r
			pm.emission_ring_inner_radius = float(c.get("inner", r * 0.8))
			pm.emission_ring_height = float(c.get("height", 0.05))
		"box":
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
			pm.emission_box_extents = c.get("ext", Vector3.ONE * r)
	pm.direction = c.get("dir", Vector3.UP)
	pm.spread = float(c.get("spread", 30.0))
	var v: Array = c.get("v", [0.5, 1.5])
	pm.initial_velocity_min = v[0]
	pm.initial_velocity_max = v[1]
	pm.gravity = c.get("grav", Vector3.ZERO)
	var d: Array = c.get("damp", [0.0, 0.5])
	pm.damping_min = d[0]
	pm.damping_max = d[1]
	if c.has("radial"):
		pm.radial_accel_min = c["radial"][0]
		pm.radial_accel_max = c["radial"][1]
	if c.has("tangent"):
		pm.tangential_accel_min = c["tangent"][0]
		pm.tangential_accel_max = c["tangent"][1]
	if c.has("orbit"):
		pm.orbit_velocity_min = c["orbit"][0]
		pm.orbit_velocity_max = c["orbit"][1]
	var sc: Array = c.get("scale", [0.7, 1.0])
	pm.scale_min = sc[0]
	pm.scale_max = sc[1]
	match String(c.get("curve", "shrink")):
		"grow":
			pm.scale_curve = curve([Vector2(0, 0.35), Vector2(1, 1.0)])
		"pop":
			pm.scale_curve = curve([Vector2(0, 0.2), Vector2(0.15, 1.0), Vector2(1, 0.55)])
		"mid":
			pm.scale_curve = curve([Vector2(0, 0.3), Vector2(0.3, 1.0), Vector2(1, 0.15)])
		"flat":
			pass
		_:
			pm.scale_curve = curve([Vector2(0, 1.0), Vector2(1, 0.0)])
	pm.color_ramp = ramp(c["cols"])
	if c.get("spin", false):
		pm.angle_min = -180.0
		pm.angle_max = 180.0
	if c.has("angvel"):
		pm.angular_velocity_min = c["angvel"][0]
		pm.angular_velocity_max = c["angvel"][1]
	if c.has("mesh"):
		p.draw_pass_1 = c["mesh"]
		p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_DISABLED
		pm.angular_velocity_min = -240.0
		pm.angular_velocity_max = 240.0
		pm.angle_min = -180.0
		pm.angle_max = 180.0
	else:
		var q := QuadMesh.new()
		var s: Variant = c.get("size", 0.3)
		q.size = s if s is Vector2 else Vector2.ONE * float(s)
		# `size` is the VISIBLE size: divide by the fraction of the texture the shape really covers.
		q.size = q.size / tex_fill(String(c.get("tex", "circle_05")))
		q.material = pmat(String(c.get("tex", "circle_05")), String(c.get("blend", "mix")))
		p.draw_pass_1 = q
	if c.has("mesh"):
		pass
	elif c.get("stretch", false):
		pm.particle_flag_align_y = true
		p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	else:
		p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD
	p.process_material = pm
	var ab := float(c.get("aabb", 6.0))
	p.visibility_aabb = AABB(Vector3(-ab, -ab * 0.5, -ab), Vector3(ab * 2, ab * 1.6, ab * 2))
	p.position = c.get("pos", Vector3.ZERO)
	if c.get("delay", 0.0) > 0.0:
		p.set_meta("emit_delay", float(c["delay"]))
	if c.get("tier", 0) > 0:
		p.set_meta("tier_min", int(c["tier"]))
	if c.get("tint", false):
		p.set_meta("tint", true)
		p.set_meta("tint_white", float(c.get("tint_white", 0.0)))
	par.add_child(p)
	return p


func set_owners(n: Node, root: Node) -> void:
	for ch in n.get_children():
		ch.owner = root
		set_owners(ch, root)


func begin(el: String, kind: String, duration: float, fade := 0.25) -> Node3D:
	var root := EE.new() as Node3D
	root.name = "%s_%s" % [el.capitalize(), kind.capitalize()]
	root.set("duration", duration)
	root.set("fade_out", fade)
	root.set("kind", StringName(kind))
	root.set("element", StringName(el))
	return root


func save(root: Node3D, el: String, kind: String) -> void:
	set_owners(root, root)
	var ps_ := PackedScene.new()
	ps_.pack(root)
	var path := OUT + el + "/" + kind + ".tscn"
	var err := ResourceSaver.save(ps_, path)
	if err != OK:
		push_error("save failed %s: %d" % [path, err])
	_count += 1
	root.free()


# Shader parameter presets shared by several recipes.
func P_orb(extra := {}) -> Dictionary:
	var d := {"shape_mode": 2, "noise_amt": 0.55, "noise_scale": Vector3(3.5, 3.5, 3.5), "scroll": Vector3(0, -2.5, 0),
		"fresnel_pow": 1.6, "core_facing": 0.9, "rim_alpha": 0.25, "wobble": 0.05, "bands": 3.0, "cel": 0.7, "intensity": 1.0, "heat_scale": 0.6}
	d.merge(extra, true)
	return d


func P_col(extra := {}) -> Dictionary:
	var d := {"shape_mode": 0, "noise_amt": 0.85, "noise_scale": Vector3(3.0, 2.2, 3.0), "scroll": Vector3(0, -2.2, 0),
		"fade_y": Vector2(0.12, 0.55), "bands": 3.0, "cel": 0.7, "intensity": 0.95, "alpha_mul": 0.85, "heat_scale": 0.7, "soft_edge": 0.85}
	d.merge(extra, true)
	return d


func P_ring(extra := {}) -> Dictionary:
	var d := {"shape_mode": 1, "noise_amt": 0.5, "noise_scale": Vector3(4, 4, 4), "scroll": Vector3(0.6, 0, 0.6),
		"ring_r": 0.8, "ring_w": 0.2, "ring_fill": 0.0, "bands": 3.0, "cel": 0.7, "intensity": 1.0, "heat_scale": 0.75, "ring_soft": 0.7}
	d.merge(extra, true)
	return d


# ---------------------------------------------------------------- more helpers
## Lightning bolt ribbon (crossed strips) from a to b. Material comes from fxmat(.. P_bolt ..).
func bolt(par: Node, nm: String, a: Vector3, b: Vector3, jag: float, width: float, mat: Material, segs := 10, seed_ := 1, anims: Array = [], tier := 0) -> MeshInstance3D:
	seed(seed_)
	return mesh(par, nm, K.bolt_mesh(a, b, jag, width, segs), mat, Vector3.ZERO, Vector3.ZERO, Vector3.ONE, anims, tier)


func P_bolt(extra := {}) -> Dictionary:
	var d := {"shape_mode": 3, "noise_amt": 0.15, "noise_scale": Vector3(8, 8, 8), "scroll": Vector3(0, 0, 0), "flicker": 0.5, "tail_len": 1.0, "cel": 0.5, "bands": 3.0,
		"intensity": 1.1, "heat_scale": 1.0}
	d.merge(extra, true)
	return d


## Cone spike (tip up) standing on `base` (local), tilted `tilt` degrees toward `yaw`. It erupts from below the
## ground over `rise` s starting at t0 and (optionally) sinks back during sink = [t0, t1].
func spike(par: Node, nm: String, mat: Material, base: Vector3, r: float, h: float, yaw: float, tilt: float, t0 := 0.0, rise := 0.18, sink: Array = [], seg := 6) -> MeshInstance3D:
	var pivot := node(par, nm + "_p", base)
	pivot.rotation_degrees = Vector3(tilt, yaw, 0)
	var anims: Array = []
	if rise > 0.0:
		anims.append(A("y", -h * 0.55, h * 0.5, t0, t0 + rise, "out"))
	if sink.size() == 2:
		anims.append(A("y", h * 0.5, -h * 0.55, sink[0], sink[1], "in"))
	return mesh(pivot, nm, cyl(0.0, r, h, seg, true), mat, Vector3(0, h * 0.5, 0), Vector3.ZERO, Vector3.ONE, anims)


func solid_params(extra := {}) -> Dictionary:
	var d := {"shape_mode": 2, "noise_amt": 0.35, "noise_scale": Vector3(4, 4, 4), "scroll": Vector3.ZERO, "fake_light": 0.9, "flat_shade": 1.0, "cel": 0.85,
		"bands": 3.0, "core_facing": 0.0, "heat_scale": 0.55, "fresnel_pow": 1.0}
	d.merge(extra, true)
	return d


func rock_mesh(r: float) -> Mesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 1.7
	s.radial_segments = 6
	s.rings = 3
	return s


func shard_mesh(r: float, h: float, mat: Material) -> Mesh:
	var c := cyl(0.0, r, h, 5, true)
	c.material = mat
	return c


func lit_mat(col: Color, rough := 0.9, emis := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	if emis > 0.0:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = emis
	return m


func smoke_cols(c: Color, a := 0.4) -> Array:
	return [[0.0, Color(c, 0.0)], [0.2, Color(c, a)], [1.0, Color(c.lightened(0.15), 0.0)]]


func white_cols(a := 1.0) -> Array:
	return [[0.0, Color(1, 1, 1, 0)], [0.1, Color(1, 1, 1, a)], [0.7, Color(1, 1, 1, a * 0.7)], [1.0, Color(1, 1, 1, 0)]]


# ---------------------------------------------------------------- FIRE
func build_fire() -> void:
	var el := "fire"
	var p := pal(el)
	var mid: Color = p["mid"]
	var core: Color = p["core"]
	# charge (at the hand)
	var r := begin(el, "charge", 0.0)
	mesh(r, "Orb", sph(0.15), fxmat("add", el, P_orb({"mesh_r": 0.15, "wobble": 0.06, "heat_scale": 0.42})))
	spr(r, "Glow", "spotlight_3", 0.9, Color(mid, 0.55), 0.8)
	ps(r, "Flames", {"tex": "flame_05", "n": 8, "life": 0.6, "once": false, "local": true, "shape": "sphere", "radius": 0.1, "v": [0.3, 0.8],
		"spread": 25, "size": Vector2(0.28, 0.42), "cols": life_cols(el), "curve": "mid", "aabb": 2.0})
	ps(r, "Embers", {"tex": "circle_05", "n": 10, "life": 0.9, "once": false, "shape": "sphere", "radius": 0.15, "v": [0.3, 0.9],
		"spread": 60, "grav": Vector3(0, 1.0, 0), "size": 0.06, "cols": life_cols(el), "aabb": 2.0})
	light(r, mid, 1.2, 4.0, 9999.0)
	save(r, el, "charge")
	# aura (body)
	r = begin(el, "aura", 0.0, 0.4)
	mesh(r, "Shell", cyl(0.3, 0.5, 1.9, 14), fxmat("add", el, P_col({"mesh_h": 1.9})), Vector3(0, 0.95, 0))
	ps(r, "Flames", {"tex": "flame_05", "n": 12, "life": 0.9, "once": false, "local": true, "shape": "ring", "radius": 0.5, "inner": 0.3, "v": [0.8, 1.6],
		"spread": 10, "size": Vector2(0.4, 0.6), "cols": life_cols(el, 0.8), "curve": "mid", "aabb": 3.0})
	ps(r, "Embers", {"tex": "circle_05", "n": 10, "life": 1.3, "once": false, "shape": "ring", "radius": 0.5, "v": [0.6, 1.4],
		"spread": 25, "grav": Vector3(0, 0.8, 0), "size": 0.06, "cols": life_cols(el), "tier": 1, "aabb": 3.0})
	save(r, el, "aura")
	# projectile
	r = begin(el, "projectile", 0.0, 0.15)
	mesh(r, "Orb", sph(0.24), fxmat("add", el, P_orb({"mesh_r": 0.24, "wobble": 0.08, "scroll": Vector3(0, 0, 3.0), "heat_scale": 0.45})))
	mesh(r, "Trail", cyl(0.0, 0.27, 1.5, 12), fxmat("add", el, P_col({"mesh_h": 1.5, "fade_y": Vector2(0.05, 0.6), "scroll": Vector3(0, -4.0, 0), "noise_scale": Vector3(3.5, 2.5, 3.5)})),
		Vector3(0, 0, 0.75), Vector3(90, 0, 0))
	spr(r, "Glow", "spotlight_3", 1.4, Color(mid, 0.6), 0.8)
	ps(r, "TrailFlames", {"tex": "flame_05", "n": 8, "life": 0.5, "once": false, "shape": "sphere", "radius": 0.1, "v": [0.1, 0.4], "spread": 90,
		"size": Vector2(0.35, 0.5), "cols": life_cols(el, 0.8), "curve": "mid", "aabb": 4.0})
	ps(r, "Embers", {"tex": "circle_05", "n": 14, "life": 0.7, "once": false, "shape": "sphere", "radius": 0.15, "v": [0.3, 1.2], "spread": 90,
		"grav": Vector3(0, 1.2, 0), "size": 0.06, "cols": life_cols(el), "tier": 1, "aabb": 4.0})
	light(r, mid, 1.6, 5.0, 9999.0)
	save(r, el, "projectile")
	# beam (flamethrower), 1 m long along -Z
	r = begin(el, "beam", 0.0, 0.2)
	mesh(r, "Cone", cyl(0.5, 0.06, 1.0, 14), fxmat("add", el, P_col({"mesh_h": 1.0, "fade_y": Vector2(0.06, 0.4), "scroll": Vector3(0, 3.0, 0), "noise_scale": Vector3(3.0, 1.6, 3.0), "alpha_mul": 0.85})),
		Vector3(0, 0, -0.5), Vector3(-90, 0, 0))
	mesh(r, "Core", cyl(0.2, 0.03, 1.0, 10), fxmat("add", el, P_col({"mesh_h": 1.0, "fade_y": Vector2(0.05, 0.5), "scroll": Vector3(0, 4.0, 0), "noise_scale": Vector3(3.0, 1.4, 3.0), "intensity": 1.2})),
		Vector3(0, 0, -0.5), Vector3(-90, 0, 0))
	spr(r, "Muzzle", "spotlight_3", 1.0, Color(mid, 0.7), 0.9)
	spr(r, "Tip", "spotlight_3", 1.6, Color(mid, 0.4), 0.7, Vector3(0, 0, -1.0))
	ps(r, "Puffs", {"tex": "flame_05", "n": 8, "life": 0.45, "once": false, "local": true, "shape": "sphere", "radius": 0.06, "dir": Vector3(0, 0, -1), "v": [2.0, 4.0],
		"spread": 12, "size": Vector2(0.4, 0.55), "cols": life_cols(el, 0.8), "curve": "mid", "aabb": 8.0})
	save(r, el, "beam")
	# impact
	r = begin(el, "impact", 1.0)
	# soft flame burst: tongues shoot out of the hit point, hot core, dissolve into smoke (no solid shell)
	mesh(r, "Burst", flame_mesh(fire_ring(14, 0.05, 0.55, 0.75, 1.5, 1, 0.0, 0.25, 0.4), 2.0), fxmat("fire", el, {"mode": 0, "glow": 0.9, "lean": 0.3}), Vector3(0, 0.05, 0), Vector3.ZERO, Vector3.ONE,
		[A("grow", 0.0, 1.0, 0.0, 0.3, "out"), A("spread", 0.3, 1.0, 0.0, 0.3, "out"), A("progress", 0.0, 1.0, 0.25, 0.85, "in")])
	mesh(r, "Crown", flame_mesh(fire_ring(7, 0.0, 0.2, 0.9, 1.9, 2, 0.0, 0.1, 0.4), 2.4), fxmat("fire", el, {"mode": 0, "glow": 1.1}), Vector3(0, 0.05, 0), Vector3.ZERO, Vector3.ONE,
		[A("grow", 0.0, 1.0, 0.0, 0.25, "out"), A("progress", 0.0, 1.0, 0.2, 0.7, "in")])
	spr(r, "Ring", "light_01", 3.4, Color(mid, 0.9), 0.9, Vector3(0, 0.2, 0), [A("scale", 0.2, 1.0, 0.0, 0.4, "out"), A("master", 1.0, 0.0, 0.12, 0.45)])
	ps(r, "Puffs", {"tex": "fire_02", "n": 8, "life": 0.6, "shape": "sphere", "radius": 0.25, "v": [1.5, 3.5], "spread": 180, "grav": Vector3(0, 2.0, 0),
		"damp": [2, 3], "size": 0.9, "spin": true, "cols": life_cols(el, 0.9), "curve": "grow"})
	ps(r, "Burst", {"tex": "muzzle_03", "n": 4, "life": 0.3, "shape": "sphere", "radius": 0.1, "v": [1.0, 2.0], "spread": 180, "size": 1.3, "spin": true,
		"cols": life_cols(el, 0.9), "curve": "grow"})
	ps(r, "Sparks", {"tex": "trace_02", "n": 14, "life": 0.55, "shape": "sphere", "radius": 0.1, "v": [3.0, 7.0], "spread": 180, "grav": Vector3(0, -8, 0), "damp": [0.5, 1.5],
		"size": Vector2(0.06, 0.5), "stretch": true, "cols": life_cols(el), "tier": 1})
	ps(r, "Smoke", {"tex": "smoke_04", "blend": "mix", "n": 6, "life": 1.0, "shape": "sphere", "radius": 0.3, "v": [0.5, 1.2], "spread": 40, "grav": Vector3(0, 0.6, 0),
		"size": 1.1, "spin": true, "curve": "grow", "cols": [[0.0, Color(0.3, 0.22, 0.18, 0.0)], [0.2, Color(0.32, 0.24, 0.2, 0.45)], [1.0, Color(0.4, 0.33, 0.3, 0.0)]], "tier": 2, "delay": 0.1})
	light(r, mid, 4.0, 6.0, 0.25, Vector3(0, 0.5, 0))
	save(r, el, "impact")
	# aoe: fire nova (3 m radius). Soft, noise-eroded flame tongues + ground glow + soot; no solid ring / cylinder.
	r = begin(el, "aoe", 1.9)
	mesh(r, "Soot", grd(3.4), fxmat("fire", el, {"mode": 2, "mesh_r": 3.4, "col_edge": Color(0.16, 0.09, 0.06), "body_alpha": 0.5}), Vector3(0, 0.03, 0), Vector3.ZERO, Vector3.ONE,
		[A("radius_frac", 0.1, 1.0, 0.0, 0.5, "out"), A("master", 0.0, 1.0, 0.0, 0.2), A("progress", 0.0, 1.0, 1.15, 1.9)])
	mesh(r, "Glow", grd(3.4), fxmat("fire", el, {"mode": 1, "mesh_r": 3.4, "glow": 1.0, "intensity": 1.1}), Vector3(0, 0.05, 0), Vector3.ZERO, Vector3.ONE,
		[A("radius_frac", 0.05, 1.0, 0.0, 0.55, "out"), A("master", 0.0, 1.0, 0.0, 0.1), A("progress", 0.0, 1.0, 0.85, 1.85, "in")])
	var wave := fire_ring(26, 0.5, 3.0, 0.85, 1.35, 3, 0.0, 0.3, 0.4)
	mesh(r, "Nova", flame_mesh(wave, 3.5, 1.6), fxmat("fire", el, {"mode": 0, "glow": 0.8, "lean": 0.2}), Vector3(0, 0.04, 0), Vector3.ZERO, Vector3.ONE,
		[A("spread", 0.1, 1.0, 0.0, 0.55, "out"), A("grow", 0.0, 1.0, 0.0, 0.6), A("progress", 0.0, 1.0, 0.85, 1.65, "in")])
	var mid_ring := fire_ring(12, 0.6, 1.7, 1.0, 2.0, 4, 0.05, 0.4, 0.4)
	mesh(r, "Mid", flame_mesh(mid_ring, 2.0, 2.5), fxmat("fire", el, {"mode": 0, "glow": 0.9, "lean": 0.1}), Vector3(0, 0.04, 0), Vector3.ZERO, Vector3.ONE,
		[A("grow", 0.0, 1.0, 0.05, 0.6), A("progress", 0.0, 1.0, 0.8, 1.55, "in")])
	var pillar := fire_ring(9, 0.0, 0.45, 1.3, 3.0, 5, 0.0, 0.3, 0.35)
	mesh(r, "Pillar", flame_mesh(pillar, 0.8, 4.0), fxmat("fire", el, {"mode": 0, "glow": 1.1, "lean": 0.0, "speed": 1.3}), Vector3(0, 0.04, 0), Vector3.ZERO, Vector3.ONE,
		[A("grow", 0.0, 1.0, 0.02, 0.45, "out"), A("progress", 0.0, 1.0, 0.65, 1.4, "in")])
	# heat shimmer over the fire (screen-space wobble, HIGH+ only)
	var sq := QuadMesh.new()
	sq.size = Vector2(6.2, 4.4)
	mesh(r, "Shimmer", sq, fxmat("shimmer", el, {"strength": 0.011}), Vector3(0, 1.9, 0), Vector3.ZERO, Vector3.ONE,
		[A("strength", 0.0, 0.011, 0.1, 0.5), A("master", 1.0, 0.0, 1.3, 1.85)], 2)
	spr(r, "Flash", "spotlight_5", 5.0, Color(core, 0.7), 1.0, Vector3(0, 0.5, 0), [A("scale", 0.3, 1.4, 0.0, 0.3, "out"), A("master", 1.0, 0.0, 0.05, 0.4)])
	ps(r, "Flames", {"tex": "flame_05", "n": 14, "life": 0.9, "shape": "ring", "radius": 1.6, "inner": 0.1, "radial": [3.0, 6.0], "damp": [2, 3], "dir": Vector3.UP, "v": [0.8, 2.0], "spread": 20,
		"size": Vector2(0.55, 0.8), "spin": true, "cols": life_cols(el, 0.7), "curve": "mid", "delay": 0.1, "aabb": 5.0, "grav": Vector3(0, 1.5, 0)})
	ps(r, "Embers", {"tex": "circle_05", "blend": "add", "n": 44, "life": 1.7, "shape": "ring", "radius": 1.6, "inner": 0.1, "radial": [1.0, 4.0], "v": [1.5, 4.5], "spread": 40, "grav": Vector3(0, 1.4, 0),
		"damp": [0.3, 0.8], "size": 0.075, "cols": [[0.0, Color(1.0, 0.85, 0.4, 0.0)], [0.1, Color(1.0, 0.8, 0.35, 1.0)], [0.6, Color(1.0, 0.45, 0.1, 0.9)], [1.0, Color(0.7, 0.15, 0.05, 0.0)]],
		"tier": 1, "aabb": 6.0, "delay": 0.1})
	ps(r, "Smoke", {"tex": "smoke_04", "blend": "mix", "n": 12, "life": 1.7, "shape": "ring", "radius": 2.0, "inner": 0.3, "v": [0.6, 1.5], "spread": 25, "grav": Vector3(0, 0.9, 0),
		"size": 1.5, "spin": true, "curve": "grow", "cols": [[0.0, Color(0.22, 0.16, 0.13, 0.0)], [0.25, Color(0.25, 0.19, 0.16, 0.42)], [1.0, Color(0.42, 0.37, 0.36, 0.0)]], "tier": 1, "delay": 0.35, "aabb": 6.0})
	light(r, mid, 4.5, 9.0, 0.5, Vector3(0, 0.6, 0))
	save(r, el, "aoe")
	# status: burning
	r = begin(el, "status", 0.0, 0.4)
	ps(r, "Flames", {"tex": "flame_05", "n": 9, "life": 0.7, "once": false, "local": true, "shape": "box", "ext": Vector3(0.28, 0.6, 0.2), "pos": Vector3(0, 1.0, 0), "v": [0.4, 1.0],
		"spread": 15, "size": Vector2(0.3, 0.45), "cols": life_cols(el, 0.85), "curve": "mid", "aabb": 3.0})
	ps(r, "Embers", {"tex": "circle_05", "n": 8, "life": 1.1, "once": false, "shape": "box", "ext": Vector3(0.3, 0.6, 0.25), "pos": Vector3(0, 1.0, 0), "v": [0.4, 1.0],
		"spread": 40, "grav": Vector3(0, 0.9, 0), "size": 0.05, "cols": life_cols(el), "tier": 1, "aabb": 3.0})
	ps(r, "Smoke", {"tex": "smoke_04", "blend": "mix", "n": 4, "life": 1.4, "once": false, "shape": "box", "ext": Vector3(0.25, 0.4, 0.2), "pos": Vector3(0, 1.5, 0), "v": [0.3, 0.6], "spread": 20,
		"size": 0.5, "spin": true, "curve": "grow", "cols": [[0.0, Color(0.25, 0.2, 0.18, 0.0)], [0.3, Color(0.28, 0.22, 0.2, 0.3)], [1.0, Color(0.35, 0.3, 0.28, 0.0)]], "tier": 2, "aabb": 3.0})
	save(r, el, "status")




# ---------------------------------------------------------------- WATER
func build_water() -> void:
	var el := "water"
	var p := pal(el)
	var mid: Color = p["mid"]
	var core: Color = p["core"]
	var drop := life_cols(el, 0.95, false)
	var r := begin(el, "charge", 0.0)
	mesh(r, "Orb", sph(0.15), fxmat("mix", el, P_orb({"mesh_r": 0.15, "wobble": 0.06, "scroll": Vector3(0, -1.2, 0), "rim_alpha": 0.5, "alpha_mul": 0.95})))
	mesh(r, "Swirl", cyl(0.26, 0.26, 0.34, 14), fxmat("mix", el, P_col({"mesh_h": 0.34, "spiral": Vector3(3, 6, 6), "spiral_amt": 1.0, "noise_amt": 0.3, "fade_y": Vector2(0.25, 0.25), "alpha_mul": 0.6, "spin": 2.0})), Vector3.ZERO, Vector3(35, 0, 20))
	spr(r, "Glow", "spotlight_3", 0.8, Color(mid, 0.3), 0.7, Vector3.ZERO, [], 0.0)
	ps(r, "Drops", {"tex": "circle_05", "n": 10, "life": 1.0, "once": false, "local": true, "shape": "ring", "radius": 0.4, "inner": 0.3, "radial": [-2.5, -3.5], "tangent": [2.0, 3.0], "v": [0.0, 0.2],
		"size": 0.07, "cols": drop, "aabb": 2.0, "curve": "flat"})
	save(r, el, "charge")
	r = begin(el, "aura", 0.0, 0.4)
	mesh(r, "Swirl", cyl(0.4, 0.6, 1.9, 16), fxmat("mix", el, P_col({"mesh_h": 1.9, "spiral": Vector3(2, 10, 3), "spiral_amt": 0.95, "noise_amt": 0.35, "spin": 1.5, "fade_y": Vector2(0.18, 0.3), "alpha_mul": 0.55, "heat_scale": 0.9})), Vector3(0, 0.95, 0))
	mesh(r, "Pool", grd(1.0), fxmat("mix", el, P_ring({"mesh_r": 1.0, "ring_r": 0.85, "ring_w": 0.14, "ring_fill": 0.3, "alpha_mul": 0.6})), Vector3(0, 0.03, 0))
	ps(r, "Bubbles", {"tex": "circle_05", "n": 12, "life": 1.5, "once": false, "local": true, "shape": "ring", "radius": 0.5, "inner": 0.3, "v": [0.4, 0.9], "spread": 10, "size": 0.09, "cols": drop, "aabb": 3.0, "curve": "flat"})
	ps(r, "Glints", {"tex": "star_04", "n": 6, "life": 1.0, "once": false, "local": true, "shape": "ring", "radius": 0.5, "v": [0.3, 0.6], "size": 0.16, "cols": life_cols(el, 1.0), "tier": 1, "aabb": 3.0, "spin": true})
	save(r, el, "aura")
	r = begin(el, "projectile", 0.0, 0.15)
	mesh(r, "Orb", sph(0.23), fxmat("mix", el, P_orb({"mesh_r": 0.23, "wobble": 0.1, "rim_alpha": 0.6, "scroll": Vector3(0, 0, 2.0)})))
	mesh(r, "Trail", cyl(0.0, 0.25, 1.5, 12), fxmat("mix", el, P_col({"mesh_h": 1.5, "fade_y": Vector2(0.05, 0.6), "spiral": Vector3(4, 8, -9), "spiral_amt": 0.8, "noise_amt": 0.4, "alpha_mul": 0.7})), Vector3(0, 0, 0.75), Vector3(90, 0, 0))
	ps(r, "Drops", {"tex": "circle_05", "n": 14, "life": 0.6, "once": false, "shape": "sphere", "radius": 0.15, "v": [0.3, 1.0], "spread": 90, "grav": Vector3(0, -4, 0), "size": 0.09, "cols": drop, "aabb": 4.0})
	spr(r, "Glow", "spotlight_3", 0.9, Color(mid, 0.3), 0.6)
	save(r, el, "projectile")
	r = begin(el, "beam", 0.0, 0.2)
	mesh(r, "Jet", cyl(0.3, 0.14, 1.0, 14), fxmat("mix", el, P_col({"mesh_h": 1.0, "spiral": Vector3(3, 14, 12), "spiral_amt": 1.0, "noise_amt": 0.35, "fade_y": Vector2(0.03, 0.05), "alpha_mul": 0.85, "heat_scale": 0.9})), Vector3(0, 0, -0.5), Vector3(-90, 0, 0))
	mesh(r, "Core", cyl(0.1, 0.05, 1.0, 10), fxmat("glow", el, P_col({"mesh_h": 1.0, "spiral": Vector3(2, 20, 16), "spiral_amt": 0.6, "noise_amt": 0.3, "fade_y": Vector2(0.03, 0.05), "alpha_mul": 0.55, "intensity": 0.7})), Vector3(0, 0, -0.5), Vector3(-90, 0, 0))
	spr(r, "Muzzle", "spotlight_3", 0.8, Color(mid, 0.35), 0.7)
	spr(r, "Tip", "spotlight_3", 1.5, Color(mid, 0.3), 0.6, Vector3(0, 0, -1.0))
	ps(r, "Spray", {"tex": "circle_05", "n": 10, "life": 0.5, "once": false, "local": true, "shape": "sphere", "radius": 0.05, "dir": Vector3(0, 0, -1), "v": [3.0, 6.0], "spread": 14, "grav": Vector3(0, -2, 0), "size": 0.08, "cols": drop, "aabb": 8.0})
	save(r, el, "beam")
	r = begin(el, "impact", 1.0)
	mesh(r, "Crown", cyl(0.95, 0.15, 0.8, 16), fxmat("mix", el, P_col({"mesh_h": 0.8, "fade_y": Vector2(0.02, 0.1), "noise_scale": Vector3(4, 3, 4), "scroll": Vector3(0, -2, 0), "alpha_mul": 0.9, "heat_scale": 0.9})), Vector3(0, 0.1, 0), Vector3.ZERO, Vector3(0.4, 0.2, 0.4),
		[A("scale", Vector3(0.4, 0.2, 0.4), Vector3(1.1, 1.0, 1.1), 0.0, 0.3, "out"), A("progress", 0.0, 1.0, 0.2, 0.7, "in")])
	spr(r, "Flash", "spotlight_5", 2.0, Color(core, 0.5), 0.8, Vector3(0, 0.2, 0), [A("scale", 0.4, 1.3, 0.0, 0.2, "out"), A("master", 1.0, 0.0, 0.03, 0.25)])
	spr(r, "Ring", "light_01", 3.2, Color(mid, 0.8), 0.7, Vector3(0, 0.2, 0), [A("scale", 0.2, 1.0, 0.0, 0.4, "out"), A("master", 1.0, 0.0, 0.1, 0.45)])
	ps(r, "Drops", {"tex": "circle_05", "n": 24, "life": 0.85, "shape": "sphere", "radius": 0.15, "v": [3.0, 6.5], "spread": 60, "grav": Vector3(0, -12, 0), "size": Vector2(0.1, 0.1), "cols": drop, "curve": "flat"})
	ps(r, "Foam", {"tex": "smoke_04", "n": 5, "life": 0.7, "shape": "sphere", "radius": 0.3, "v": [0.5, 1.5], "spread": 180, "size": 0.9, "spin": true, "curve": "grow",
		"cols": [[0.0, Color(0.9, 0.97, 1, 0.0)], [0.2, Color(0.9, 0.97, 1, 0.5)], [1.0, Color(0.9, 0.97, 1, 0.0)]], "tier": 1})
	ps(r, "Glints", {"tex": "star_04", "n": 6, "life": 0.6, "shape": "sphere", "radius": 0.3, "v": [1, 3], "spread": 180, "size": 0.2, "cols": life_cols(el, 1.0), "tier": 1, "spin": true})
	save(r, el, "impact")
	r = begin(el, "aoe", 1.9)
	mesh(r, "Wave", grd(3.2), fxmat("mix", el, P_ring({"mesh_r": 3.2, "ring_w": 0.32, "ring_fill": 0.35, "alpha_mul": 0.9, "ticks": 40.0, "tick_amt": 0.0})), Vector3(0, 0.05, 0), Vector3.ZERO, Vector3.ONE,
		[A("ring_r", 0.1, 0.9, 0.0, 0.7, "out"), A("progress", 0.0, 1.0, 0.45, 1.0)])
	mesh(r, "Puddle", grd(3.2), fxmat("mix", el, P_ring({"mesh_r": 3.2, "ring_r": 0.9, "ring_fill": 1.0, "noise_amt": 0.6, "scroll": Vector3(0.3, 0, 0.3), "alpha_mul": 0.5, "heat_scale": 1.0})), Vector3(0, 0.03, 0), Vector3.ZERO, Vector3.ONE,
		[A("scale", 0.2, 1.0, 0.0, 0.6, "out"), A("progress", 0.0, 1.0, 1.1, 1.9)])
	mesh(r, "Geyser", cyl(0.55, 0.85, 4.0, 16), fxmat("mix", el, P_col({"mesh_h": 4.0, "spiral": Vector3(3, 6, 6), "spiral_amt": 0.9, "noise_amt": 0.4, "scroll": Vector3(0, -3, 0), "fade_y": Vector2(0.05, 0.4), "alpha_mul": 0.85, "heat_scale": 0.9})),
		Vector3(0, 0.2, 0), Vector3.ZERO, Vector3(1, 0.05, 1), [A("scale", Vector3(1, 0.05, 1), Vector3(1, 1, 1), 0.1, 0.4, "out"), A("y", 0.2, 2.0, 0.1, 0.4, "out"), A("progress", 0.0, 1.0, 0.9, 1.6, "in")])
	ps(r, "Splash", {"tex": "circle_05", "n": 36, "life": 1.1, "shape": "ring", "radius": 1.2, "inner": 0.0, "v": [3.0, 7.0], "spread": 25, "grav": Vector3(0, -9, 0), "size": 0.12, "cols": drop, "curve": "flat", "delay": 0.15, "aabb": 6.0})
	ps(r, "Mist", {"tex": "smoke_04", "n": 8, "life": 1.0, "shape": "ring", "radius": 1.5, "inner": 0.3, "v": [0.5, 1.5], "spread": 40, "size": 1.3, "spin": true, "curve": "grow",
		"cols": [[0.0, Color(0.9, 0.97, 1, 0.0)], [0.25, Color(0.9, 0.97, 1, 0.4)], [1.0, Color(0.9, 0.97, 1, 0.0)]], "tier": 1, "delay": 0.2, "aabb": 6.0})
	spr(r, "Flash", "spotlight_5", 4.0, Color(core, 0.4), 0.7, Vector3(0, 0.6, 0), [A("scale", 0.3, 1.2, 0.0, 0.3, "out"), A("master", 1.0, 0.0, 0.05, 0.4)])
	save(r, el, "aoe")
	r = begin(el, "status", 0.0, 0.4)
	ps(r, "Drips", {"tex": "circle_05", "n": 10, "life": 1.0, "once": false, "local": true, "shape": "box", "ext": Vector3(0.26, 0.4, 0.2), "pos": Vector3(0, 1.4, 0), "v": [0.0, 0.2], "spread": 180, "grav": Vector3(0, -3.5, 0), "size": 0.07, "cols": drop, "aabb": 3.0, "curve": "flat"})
	ps(r, "Glints", {"tex": "star_04", "n": 4, "life": 0.9, "once": false, "local": true, "shape": "box", "ext": Vector3(0.3, 0.6, 0.25), "pos": Vector3(0, 1.0, 0), "v": [0.0, 0.2], "size": 0.16, "cols": life_cols(el, 1.0), "tier": 1, "aabb": 3.0, "spin": true})
	mesh(r, "Puddle", grd(0.8), fxmat("mix", el, P_ring({"mesh_r": 0.8, "ring_r": 0.8, "ring_fill": 0.5, "ring_w": 0.2, "alpha_mul": 0.5})), Vector3(0, 0.03, 0), Vector3.ZERO, Vector3.ONE, [], 1)
	save(r, el, "status")


# ---------------------------------------------------------------- EARTH
func build_earth() -> void:
	var el := "earth"
	var p := pal(el)
	var mid: Color = p["mid"]
	var core: Color = p["core"]
	var dust := [[0.0, Color(0.72, 0.58, 0.4, 0.0)], [0.2, Color(0.72, 0.58, 0.4, 0.55)], [1.0, Color(0.6, 0.48, 0.34, 0.0)]]
	var deb := [[0.0, Color(0.8, 0.62, 0.4, 0.0)], [0.08, Color(0.85, 0.66, 0.42, 1.0)], [0.85, Color(0.6, 0.44, 0.28, 1.0)], [1.0, Color(0.5, 0.36, 0.22, 0.0)]]
	var sp := solid_params()
	var r := begin(el, "charge", 0.0)
	var piv := node(r, "Orbit")
	piv.set_meta("anims", [A("rot_y", 0.0, 188.0, 0.0, 30.0)])
	for i in 3:
		var a := TAU * i / 3.0
		mesh(piv, "Rock%d" % i, rock_mesh(0.07), fxmat("solid", el, sp), Vector3(cos(a) * 0.26, 0.05 * (i - 1), sin(a) * 0.26), Vector3(i * 40, i * 70, 0))
	spr(r, "Glow", "spotlight_3", 0.7, Color(1.0, 0.85, 0.5, 0.35), 0.7)
	ps(r, "Dust", {"tex": "dirt_01", "n": 6, "life": 1.0, "once": false, "local": true, "shape": "ring", "radius": 0.35, "v": [0.0, 0.2], "size": 0.16, "cols": deb, "aabb": 2.0, "curve": "flat", "tint": false})
	ps(r, "Motes", {"tex": "circle_05", "n": 8, "life": 1.0, "once": false, "shape": "sphere", "radius": 0.3, "v": [0.1, 0.4], "grav": Vector3(0, 0.3, 0), "size": 0.05, "cols": life_cols(el, 1.0), "aabb": 2.0})
	save(r, el, "charge")
	r = begin(el, "aura", 0.0, 0.4)
	mesh(r, "Ring", grd(1.1), fxmat("mix", el, P_ring({"mesh_r": 1.1, "ring_r": 0.85, "ring_w": 0.12, "ticks": 8.0, "tick_amt": 1.0, "spin": 0.6, "alpha_mul": 0.85})), Vector3(0, 0.04, 0))
	for i in 5:
		spike(r, "Stone%d" % i, fxmat("solid", el, sp), Vector3(cos(TAU * i / 5.0) * 0.75, 0, sin(TAU * i / 5.0) * 0.75), 0.11, 0.42, rad_to_deg(-TAU * i / 5.0) + 90.0, 14.0, 0.05 * i, 0.25)
	ps(r, "Dust", {"tex": "dirt_01", "n": 8, "life": 1.4, "once": false, "local": true, "shape": "ring", "radius": 0.6, "v": [0.4, 0.9], "spread": 10, "size": 0.16, "cols": deb, "aabb": 3.0, "curve": "flat"})
	ps(r, "Motes", {"tex": "circle_05", "n": 10, "life": 1.5, "once": false, "local": true, "shape": "ring", "radius": 0.6, "v": [0.5, 1.2], "spread": 10, "size": 0.06, "cols": life_cols(el, 1.0), "tier": 1, "aabb": 3.0})
	save(r, el, "aura")
	r = begin(el, "projectile", 0.0, 0.15)
	piv = node(r, "Spin")
	piv.set_meta("anims", [A("rot_y", 0.0, 900.0, 0.0, 30.0)])
	mesh(piv, "Rock", rock_mesh(0.26), fxmat("solid", el, sp))
	mesh(r, "Dust", cyl(0.0, 0.3, 1.3, 10), fxmat("mix", el, P_col({"mesh_h": 1.3, "fade_y": Vector2(0.05, 0.6), "scroll": Vector3(0, -3, 0), "alpha_mul": 0.55, "heat_scale": 0.8})), Vector3(0, 0, 0.7), Vector3(90, 0, 0))
	ps(r, "Chips", {"tex": "dirt_02", "n": 8, "life": 0.6, "once": false, "shape": "sphere", "radius": 0.2, "v": [0.3, 1.0], "spread": 90, "grav": Vector3(0, -5, 0), "size": 0.22, "cols": deb, "aabb": 4.0, "curve": "flat"})
	ps(r, "Puff", {"tex": "smoke_04", "n": 6, "life": 0.7, "once": false, "shape": "sphere", "radius": 0.2, "v": [0.1, 0.5], "spread": 90, "size": 0.6, "cols": dust, "spin": true, "curve": "grow", "tier": 1, "aabb": 4.0})
	save(r, el, "projectile")
	# beam: a line of spikes erupting away from the caster (designed 6 m long, scaled uniformly)
	r = begin(el, "beam", 1.7, 0.3)
	r.set_meta("beam_len", 6.0)
	for i in 9:
		var z := -0.5 - i * 0.62
		var hh := 0.9 + 0.5 * sin(i * 2.1) + 0.25
		var side := 0.12 * (1 if i % 2 == 0 else -1)
		spike(r, "S%d" % i, fxmat("solid", el, sp), Vector3(side, 0, z), 0.3 - i * 0.012, hh, randf_range(0, 360), 8.0, i * 0.055, 0.2, [1.25 + i * 0.03, 1.55 + i * 0.03])
	ps(r, "Dust", {"tex": "smoke_04", "n": 14, "life": 0.9, "shape": "box", "ext": Vector3(0.4, 0.1, 2.8), "pos": Vector3(0, 0.2, -3.0), "v": [0.5, 1.4], "spread": 50, "size": 0.9, "cols": dust, "spin": true, "curve": "grow", "aabb": 8.0, "tier": 1})
	ps(r, "Chips", {"tex": "dirt_02", "n": 18, "life": 0.9, "shape": "box", "ext": Vector3(0.3, 0.1, 2.8), "pos": Vector3(0, 0.2, -3.0), "v": [2.0, 5.0], "spread": 40, "grav": Vector3(0, -12, 0), "size": 0.2, "cols": deb, "aabb": 8.0, "curve": "flat"})
	save(r, el, "beam")
	r = begin(el, "impact", 1.1)
	spr(r, "Flash", "spotlight_5", 2.0, Color(1.0, 0.85, 0.5, 0.5), 0.8, Vector3.ZERO, [A("scale", 0.4, 1.3, 0.0, 0.2, "out"), A("master", 1.0, 0.0, 0.03, 0.25)])
	spr(r, "Ring", "light_01", 3.0, Color(0.85, 0.65, 0.4, 0.8), 0.7, Vector3.ZERO, [A("scale", 0.2, 1.0, 0.0, 0.4, "out"), A("master", 1.0, 0.0, 0.1, 0.45)])
	ps(r, "Dust", {"tex": "smoke_04", "n": 8, "life": 0.9, "shape": "sphere", "radius": 0.2, "v": [1.0, 3.0], "spread": 180, "damp": [2, 3], "size": 1.1, "cols": dust, "spin": true, "curve": "grow"})
	ps(r, "Chips", {"tex": "dirt_01", "n": 12, "life": 0.9, "shape": "sphere", "radius": 0.1, "v": [3.0, 7.0], "spread": 180, "grav": Vector3(0, -14, 0), "size": 0.22, "cols": deb, "curve": "flat"})
	ps(r, "Rocks", {"mesh": rock_mesh(0.09), "n": 6, "life": 0.9, "shape": "sphere", "radius": 0.1, "v": [3.0, 6.0], "spread": 180, "grav": Vector3(0, -15, 0), "cols": [[0.0, Color(0.75, 0.55, 0.35)], [1.0, Color(0.6, 0.42, 0.26)]], "curve": "shrink", "tier": 1})
	save(r, el, "impact")
	r = begin(el, "aoe", 1.9)
	mesh(r, "Crack", grd(3.2), fxmat("mix", el, P_ring({"mesh_r": 3.2, "ring_r": 0.9, "ring_fill": 1.0, "noise_amt": 0.9, "noise_scale": Vector3(5, 5, 5), "scroll": Vector3.ZERO,
		"col_core": Color(0.42, 0.3, 0.2), "col_mid": Color(0.3, 0.2, 0.13), "col_edge": Color(0.2, 0.13, 0.08), "alpha_mul": 0.6, "cel": 0.9, "bands": 3.0, "heat_scale": 1.0})), Vector3(0, 0.03, 0), Vector3.ZERO, Vector3.ONE,
		[A("scale", 0.3, 1.0, 0.0, 0.3, "out"), A("progress", 0.0, 1.0, 1.3, 1.9)])
	mesh(r, "Rune", grd(3.2), fxmat("glow", el, P_ring({"mesh_r": 3.2, "ring_r": 0.94, "ring_w": 0.07, "ticks": 16.0, "tick_amt": 0.7, "noise_amt": 0.3, "intensity": 0.7, "alpha_mul": 0.8})), Vector3(0, 0.05, 0), Vector3.ZERO, Vector3.ONE,
		[A("master", 0.0, 1.0, 0.0, 0.2), A("progress", 0.0, 1.0, 1.3, 1.9)])
	seed(7)
	spike(r, "Core", fxmat("solid", el, sp), Vector3.ZERO, 0.55, 2.6, 0.0, 0.0, 0.0, 0.2, [1.4, 1.8])
	var idx := 0
	for ring in [[1.3, 6, 1.7, 0.36, 0.1], [2.3, 8, 1.3, 0.3, 0.2]]:
		for i in ring[1]:
			var a: float = TAU * (i + 0.5 * idx) / ring[1]
			var hh: float = ring[2] * randf_range(0.8, 1.25)
			spike(r, "S%d" % idx, fxmat("solid", el, sp), Vector3(cos(a) * ring[0], 0, sin(a) * ring[0]), ring[3] * randf_range(0.85, 1.1), hh, rad_to_deg(-a) + 90.0, randf_range(8, 18), ring[4] + randf() * 0.08, 0.2, [1.4 + randf() * 0.15, 1.8 + randf() * 0.1])
			idx += 1
	ps(r, "Dust", {"tex": "smoke_04", "n": 14, "life": 1.1, "shape": "ring", "radius": 1.0, "inner": 0.2, "radial": [3.0, 6.0], "damp": [2, 3], "v": [0.5, 1.2], "spread": 30, "size": 1.4, "cols": dust, "spin": true, "curve": "grow", "aabb": 6.0, "tier": 1, "delay": 0.05})
	ps(r, "Chips", {"tex": "dirt_02", "n": 26, "life": 1.0, "shape": "ring", "radius": 2.0, "inner": 0.0, "v": [3.0, 7.0], "spread": 25, "grav": Vector3(0, -14, 0), "size": 0.2, "cols": deb, "curve": "flat", "aabb": 6.0, "delay": 0.05})
	ps(r, "Motes", {"tex": "star_04", "n": 16, "life": 1.4, "shape": "ring", "radius": 2.0, "v": [0.6, 1.6], "spread": 15, "size": 0.16, "cols": life_cols(el, 1.0), "tier": 1, "aabb": 6.0, "spin": true, "delay": 0.2})
	save(r, el, "aoe")
	r = begin(el, "status", 0.0, 0.4)
	var green := sp.duplicate()
	green["col_core"] = Color(0.75, 0.85, 0.4)
	green["col_mid"] = Color(0.45, 0.58, 0.24)
	green["col_edge"] = Color(0.22, 0.3, 0.12)
	for i in 6:
		var a := TAU * i / 6.0
		spike(r, "Root%d" % i, fxmat("solid", el, green), Vector3(cos(a) * 0.5, 0, sin(a) * 0.5), 0.07, 0.5 + 0.12 * (i % 2), rad_to_deg(-a) + 90.0, -18.0, 0.04 * i, 0.3)
	mesh(r, "Ring", grd(0.8), fxmat("mix", el, P_ring({"mesh_r": 0.8, "ring_r": 0.7, "ring_w": 0.2, "ring_fill": 0.5, "alpha_mul": 0.5, "col_mid": Color(0.4, 0.5, 0.22), "col_core": Color(0.6, 0.72, 0.3), "col_edge": Color(0.2, 0.28, 0.1)})), Vector3(0, 0.03, 0))
	ps(r, "Dust", {"tex": "dirt_01", "n": 4, "life": 1.2, "once": false, "local": true, "shape": "ring", "radius": 0.5, "v": [0.2, 0.5], "spread": 10, "size": 0.12, "cols": deb, "aabb": 2.0, "curve": "flat", "tier": 1})
	save(r, el, "status")


# ---------------------------------------------------------------- WIND
func build_wind() -> void:
	var el := "wind"
	var p := pal(el)
	var mid: Color = p["mid"]
	var core: Color = p["core"]
	var streak := [[0.0, Color(core, 0.0)], [0.15, Color(core, 0.9)], [0.7, Color(mid, 0.6)], [1.0, Color(mid, 0.0)]]
	var leaf := [[0.0, Color(0.55, 0.8, 0.3, 0.0)], [0.1, Color(0.6, 0.85, 0.32, 1.0)], [0.85, Color(0.45, 0.7, 0.25, 1.0)], [1.0, Color(0.4, 0.6, 0.2, 0.0)]]
	var W := {"spiral_amt": 1.0, "noise_amt": 0.3, "heat_scale": 1.0, "intensity": 0.95}
	var r := begin(el, "charge", 0.0)
	mesh(r, "BandA", cyl(0.24, 0.24, 0.34, 14), fxmat("mix", el, P_col(W.merged({"mesh_h": 0.34, "spiral": Vector3(3, 6, 8), "spin": 3.0, "fade_y": Vector2(0.25, 0.25), "alpha_mul": 0.7}))))
	mesh(r, "BandB", cyl(0.2, 0.2, 0.3, 14), fxmat("mix", el, P_col(W.merged({"mesh_h": 0.3, "spiral": Vector3(2, 5, -9), "spin": -3.0, "fade_y": Vector2(0.25, 0.25), "alpha_mul": 0.7}))), Vector3.ZERO, Vector3(60, 0, 30))
	spr(r, "Glow", "spotlight_3", 0.6, Color(core, 0.45), 0.7)
	ps(r, "Streaks", {"tex": "trace_02", "n": 12, "life": 0.6, "once": false, "local": true, "shape": "ring", "radius": 0.4, "inner": 0.3, "radial": [-2.0, -3.0], "tangent": [4.0, 6.0], "v": [0, 0.2], "size": Vector2(0.04, 0.3), "stretch": true, "cols": streak, "aabb": 2.0, "curve": "flat"})
	save(r, el, "charge")
	r = begin(el, "aura", 0.0, 0.4)
	mesh(r, "Gust", cyl(0.4, 0.62, 1.9, 16), fxmat("mix", el, P_col(W.merged({"mesh_h": 1.9, "spiral": Vector3(2, 9, -4), "spin": 2.0, "fade_y": Vector2(0.15, 0.3), "alpha_mul": 0.5}))), Vector3(0, 0.95, 0))
	mesh(r, "Ring", grd(1.0), fxmat("mix", el, P_ring({"mesh_r": 1.0, "ring_r": 0.85, "ring_w": 0.1, "ticks": 6.0, "tick_amt": 1.0, "spin": 1.5, "alpha_mul": 0.8})), Vector3(0, 0.04, 0))
	ps(r, "Streaks", {"tex": "trace_02", "n": 14, "life": 0.9, "once": false, "local": true, "shape": "ring", "radius": 0.55, "v": [1.2, 2.4], "spread": 6, "size": Vector2(0.04, 0.45), "stretch": true, "cols": streak, "aabb": 3.0, "curve": "flat"})
	ps(r, "Leaves", {"tex": "circle_05", "n": 6, "life": 1.4, "once": false, "local": true, "shape": "ring", "radius": 0.6, "v": [0.5, 1.0], "tangent": [2.0, 3.0], "size": 0.09, "cols": leaf, "tier": 1, "aabb": 3.0, "curve": "flat"})
	save(r, el, "aura")
	r = begin(el, "projectile", 0.0, 0.15)
	mesh(r, "Blade", K.arc_mesh(0.75, 140.0, 0.5, 20, 0.3), fxmat("mix", el, {"shape_mode": 3, "noise_amt": 0.3, "noise_scale": Vector3(5, 5, 5), "scroll": Vector3(2, 0, 0), "tail_len": 0.35, "cel": 0.7, "heat_scale": 1.0, "intensity": 1.0}), Vector3.ZERO, Vector3(0, 180, 70))
	mesh(r, "BladeCore", K.arc_mesh(0.72, 120.0, 0.16, 20, 0.3), fxmat("glow", el, {"shape_mode": 3, "noise_amt": 0.1, "tail_len": 0.3, "cel": 0.5, "heat_scale": 1.2, "intensity": 0.8, "col_mid": core, "col_edge": core}), Vector3.ZERO, Vector3(0, 180, 70))
	ps(r, "Streaks", {"tex": "trace_02", "n": 14, "life": 0.5, "once": false, "shape": "ring", "radius": 0.5, "axis": Vector3(0, 0, 1), "v": [0.0, 0.5], "size": Vector2(0.04, 0.6), "dir": Vector3(0, 0, 1), "stretch": true, "cols": streak, "aabb": 4.0, "curve": "flat"})
	ps(r, "Leaves", {"tex": "circle_05", "n": 6, "life": 0.6, "once": false, "shape": "ring", "radius": 0.5, "axis": Vector3(0, 0, 1), "v": [0.2, 0.8], "size": 0.09, "cols": leaf, "tier": 1, "aabb": 4.0, "curve": "flat"})
	save(r, el, "projectile")
	r = begin(el, "beam", 0.0, 0.25)
	mesh(r, "Gust", cyl(0.75, 0.06, 1.0, 16), fxmat("mix", el, P_col(W.merged({"mesh_h": 1.0, "spiral": Vector3(3, 12, 14), "spin": 3.0, "fade_y": Vector2(0.04, 0.15), "alpha_mul": 0.6}))), Vector3(0, 0, -0.5), Vector3(-90, 0, 0))
	mesh(r, "Inner", cyl(0.4, 0.04, 1.0, 12), fxmat("mix", el, P_col(W.merged({"mesh_h": 1.0, "spiral": Vector3(2, 9, -16), "spin": -4.0, "fade_y": Vector2(0.04, 0.15), "alpha_mul": 0.6, "col_mid": core}))), Vector3(0, 0, -0.5), Vector3(-90, 0, 0))
	ps(r, "Streaks", {"tex": "trace_02", "n": 14, "life": 0.5, "once": false, "local": true, "shape": "sphere", "radius": 0.08, "dir": Vector3(0, 0, -1), "v": [4.0, 8.0], "spread": 14, "size": Vector2(0.04, 0.5), "stretch": true, "cols": streak, "aabb": 8.0, "curve": "flat"})
	ps(r, "Leaves", {"tex": "circle_05", "n": 6, "life": 0.6, "once": false, "local": true, "shape": "sphere", "radius": 0.08, "dir": Vector3(0, 0, -1), "v": [3.0, 6.0], "spread": 20, "size": 0.09, "cols": leaf, "tier": 1, "aabb": 8.0, "curve": "flat"})
	save(r, el, "beam")
	r = begin(el, "impact", 1.0)
	mesh(r, "Shell", sph(0.8, 14, 8), fxmat("mix", el, P_orb({"mesh_r": 0.8, "core_facing": 0.0, "rim_alpha": 1.2, "noise_amt": 0.5, "spiral": Vector3(3, 6, 10), "spiral_amt": 0.6, "alpha_mul": 0.8, "heat_scale": 1.0})), Vector3.ZERO, Vector3.ZERO, Vector3.ONE * 0.3,
		[A("scale", 0.3, 1.5, 0.0, 0.4, "out"), A("progress", 0.0, 1.0, 0.1, 0.5)])
	spr(r, "Flash", "spotlight_5", 1.8, Color(core, 0.5), 0.8, Vector3.ZERO, [A("scale", 0.4, 1.3, 0.0, 0.2, "out"), A("master", 1.0, 0.0, 0.03, 0.25)])
	spr(r, "Ring", "light_01", 3.4, Color(mid, 0.8), 0.7, Vector3.ZERO, [A("scale", 0.2, 1.0, 0.0, 0.4, "out"), A("master", 1.0, 0.0, 0.1, 0.45)])
	ps(r, "Streaks", {"tex": "trace_02", "n": 16, "life": 0.5, "shape": "sphere", "radius": 0.15, "v": [4.0, 8.0], "spread": 180, "damp": [1, 2], "size": Vector2(0.04, 0.55), "stretch": true, "cols": streak, "curve": "flat"})
	ps(r, "Leaves", {"tex": "circle_05", "n": 10, "life": 0.9, "shape": "sphere", "radius": 0.2, "v": [2.0, 5.0], "spread": 180, "damp": [1, 2], "tangent": [2, 4], "size": 0.1, "cols": leaf, "tier": 1, "curve": "flat"})
	ps(r, "Dust", {"tex": "smoke_04", "n": 4, "life": 0.7, "shape": "sphere", "radius": 0.2, "v": [1.0, 2.5], "spread": 180, "size": 0.8, "cols": [[0.0, Color(0.9, 1, 0.95, 0.0)], [0.2, Color(0.9, 1, 0.95, 0.35)], [1.0, Color(0.9, 1, 0.95, 0.0)]], "spin": true, "curve": "grow", "tier": 1})
	save(r, el, "impact")
	r = begin(el, "aoe", 2.5)
	mesh(r, "Ring", grd(3.2), fxmat("mix", el, P_ring({"mesh_r": 3.2, "ring_r": 0.94, "ring_w": 0.08, "ticks": 12.0, "tick_amt": 1.0, "spin": 1.2, "alpha_mul": 0.85})), Vector3(0, 0.04, 0), Vector3.ZERO, Vector3.ONE,
		[A("master", 0.0, 1.0, 0.0, 0.2), A("progress", 0.0, 1.0, 1.9, 2.5)])
	mesh(r, "Funnel", cyl(1.6, 0.25, 4.6, 20), fxmat("mix", el, P_col(W.merged({"mesh_h": 4.6, "spiral": Vector3(3, 8, -7), "spin": 4.0, "twist": 1.2, "fade_y": Vector2(0.05, 0.25), "alpha_mul": 0.75, "noise_amt": 0.4}))),
		Vector3(0, 0.5, 0), Vector3.ZERO, Vector3(0.2, 0.1, 0.2), [A("scale", Vector3(0.2, 0.1, 0.2), Vector3(1, 1, 1), 0.0, 0.5, "out"), A("y", 0.5, 2.3, 0.0, 0.5, "out"), A("progress", 0.0, 1.0, 1.8, 2.5, "in")])
	mesh(r, "Core", cyl(0.9, 0.12, 4.4, 16), fxmat("mix", el, P_col(W.merged({"mesh_h": 4.4, "spiral": Vector3(2, 6, 10), "spin": -5.0, "twist": -1.0, "fade_y": Vector2(0.05, 0.25), "alpha_mul": 0.7, "col_mid": core, "noise_amt": 0.4}))),
		Vector3(0, 0.5, 0), Vector3.ZERO, Vector3(0.2, 0.1, 0.2), [A("scale", Vector3(0.2, 0.1, 0.2), Vector3(1, 1, 1), 0.05, 0.55, "out"), A("y", 0.5, 2.2, 0.05, 0.55, "out"), A("progress", 0.0, 1.0, 1.8, 2.5, "in")])
	ps(r, "Debris", {"tex": "dirt_01", "n": 20, "life": 1.6, "shape": "ring", "radius": 1.2, "inner": 0.6, "v": [0.5, 1.5], "spread": 20, "tangent": [6.0, 9.0], "radial": [-2.0, -1.0], "grav": Vector3(0, 1.0, 0),
		"size": 0.16, "cols": [[0.0, Color(0.7, 0.6, 0.4, 0.0)], [0.15, Color(0.7, 0.6, 0.4, 0.9)], [0.85, Color(0.6, 0.5, 0.35, 0.9)], [1.0, Color(0.6, 0.5, 0.35, 0.0)]], "curve": "flat", "aabb": 6.0, "delay": 0.2})
	ps(r, "Leaves", {"tex": "circle_05", "n": 18, "life": 1.6, "shape": "ring", "radius": 1.0, "inner": 0.3, "v": [1.0, 2.5], "spread": 20, "tangent": [6.0, 9.0], "radial": [-1.5, 0.0], "size": 0.1, "cols": leaf, "curve": "flat", "tier": 1, "aabb": 6.0, "delay": 0.2})
	ps(r, "Dust", {"tex": "smoke_04", "n": 10, "life": 1.4, "shape": "ring", "radius": 1.6, "inner": 0.5, "v": [0.3, 0.8], "spread": 30, "size": 1.3, "cols": [[0.0, Color(0.85, 0.85, 0.75, 0.0)], [0.25, Color(0.85, 0.85, 0.75, 0.3)], [1.0, Color(0.85, 0.85, 0.75, 0.0)]], "spin": true, "curve": "grow", "tier": 1, "aabb": 6.0, "delay": 0.2})
	save(r, el, "aoe")
	r = begin(el, "status", 0.0, 0.4)
	mesh(r, "Ankles", cyl(0.42, 0.42, 0.3, 14), fxmat("mix", el, P_col(W.merged({"mesh_h": 0.3, "spiral": Vector3(3, 5, 8), "spin": 4.0, "fade_y": Vector2(0.3, 0.3), "alpha_mul": 0.7}))), Vector3(0, 0.22, 0))
	mesh(r, "Waist", cyl(0.4, 0.4, 0.3, 14), fxmat("mix", el, P_col(W.merged({"mesh_h": 0.3, "spiral": Vector3(3, 5, -8), "spin": -4.0, "fade_y": Vector2(0.3, 0.3), "alpha_mul": 0.6}))), Vector3(0, 1.0, 0), Vector3.ZERO, Vector3.ONE, [], 1)
	ps(r, "Streaks", {"tex": "trace_02", "n": 8, "life": 0.7, "once": false, "local": true, "shape": "ring", "radius": 0.5, "pos": Vector3(0, 0.6, 0), "v": [0.0, 0.3], "tangent": [4.0, 6.0], "size": Vector2(0.04, 0.4), "stretch": true, "cols": streak, "aabb": 3.0, "curve": "flat"})
	save(r, el, "status")


# ---------------------------------------------------------------- LIGHTNING
func build_lightning() -> void:
	var el := "lightning"
	var p := pal(el)
	var mid: Color = p["mid"]
	var core: Color = p["core"]
	var edge: Color = p["edge"]
	var spark := [[0.0, Color(core, 0.0)], [0.08, Color(core, 1.0)], [0.6, Color(mid, 0.9)], [1.0, Color(edge, 0.0)]]
	var B := P_bolt()
	var r := begin(el, "charge", 0.0)
	mesh(r, "Orb", sph(0.13), fxmat("glow", el, P_orb({"noise_scale": Vector3(6, 6, 6), "scroll": Vector3(3, 5, 3), "core_facing": 1.0, "heat_scale": 0.9, "intensity": 0.9, "wobble": 0.03})))
	spr(r, "Glow", "spotlight_5", 0.9, Color(mid, 0.45), 0.8)
	for i in 4:
		var d := Vector3.RIGHT.rotated(Vector3.UP, i * 1.6).rotated(Vector3.FORWARD, i * 0.7 - 0.8) * 0.36
		bolt(r, "Arc%d" % i, Vector3.ZERO, d, 0.09, 0.025, fxmat("glow", el, P_bolt({"flicker": 0.55 + 0.05 * i, "intensity": 1.0})), 6, 11 + i)
	ps(r, "Sparks", {"tex": "trace_02", "n": 8, "life": 0.25, "once": false, "local": true, "shape": "sphere", "radius": 0.08, "v": [1.5, 3.5], "spread": 180, "size": Vector2(0.03, 0.25), "stretch": true, "cols": spark, "aabb": 2.0, "curve": "flat"})
	light(r, mid, 1.0, 4.0, 9999.0)
	save(r, el, "charge")
	r = begin(el, "aura", 0.0, 0.3)
	var pos := [[Vector3(0.35, 0.3, 0.1), Vector3(0.25, 1.0, -0.1)], [Vector3(-0.3, 0.9, 0.15), Vector3(-0.4, 1.6, 0.0)], [Vector3(0.2, 1.4, -0.2), Vector3(-0.15, 1.9, 0.05)], [Vector3(-0.2, 0.2, -0.15), Vector3(0.1, 0.8, 0.2)]]
	for i in pos.size():
		bolt(r, "Arc%d" % i, pos[i][0], pos[i][1], 0.14, 0.03, fxmat("glow", el, P_bolt({"flicker": 0.7 + 0.03 * i})), 8, 21 + i)
	mesh(r, "Ring", grd(1.0), fxmat("mix", el, P_ring({"mesh_r": 1.0, "ring_r": 0.85, "ring_w": 0.1, "ticks": 10.0, "tick_amt": 1.0, "spin": 2.0, "flicker": 0.3, "alpha_mul": 0.85})), Vector3(0, 0.04, 0))
	ps(r, "Sparks", {"tex": "trace_02", "n": 10, "life": 0.3, "once": false, "local": true, "shape": "box", "ext": Vector3(0.35, 0.9, 0.3), "pos": Vector3(0, 1.0, 0), "v": [1.0, 3.0], "spread": 180, "size": Vector2(0.03, 0.3), "stretch": true, "cols": spark, "aabb": 3.0, "curve": "flat"})
	save(r, el, "aura")
	r = begin(el, "projectile", 0.0, 0.12)
	mesh(r, "Orb", sph(0.2), fxmat("glow", el, P_orb({"noise_scale": Vector3(5, 5, 5), "scroll": Vector3(3, 5, 3), "core_facing": 1.0, "heat_scale": 0.9, "intensity": 0.9, "wobble": 0.05})))
	spr(r, "Glow", "spotlight_5", 1.4, Color(mid, 0.5), 0.8)
	for i in 5:
		var d := Vector3(0, 0.45, 0).rotated(Vector3.FORWARD, i * 1.25).rotated(Vector3.UP, i * 0.6)
		bolt(r, "Arc%d" % i, Vector3.ZERO, d, 0.1, 0.03, fxmat("glow", el, P_bolt({"flicker": 0.6})), 6, 31 + i)
	bolt(r, "Tail", Vector3.ZERO, Vector3(0, 0, 1.6), 0.12, 0.06, fxmat("glow", el, P_bolt({"flicker": 0.4, "tail_len": 1.0})), 10, 41)
	ps(r, "Sparks", {"tex": "trace_02", "n": 12, "life": 0.3, "once": false, "shape": "sphere", "radius": 0.1, "v": [0.5, 2.0], "spread": 180, "size": Vector2(0.03, 0.25), "stretch": true, "cols": spark, "aabb": 4.0, "curve": "flat"})
	light(r, mid, 1.6, 5.0, 9999.0)
	save(r, el, "projectile")
	r = begin(el, "beam", 0.0, 0.15)
	# bold beam: a wide violet halo/outline (alpha-blended, so it reads on the bright ground), a saturated body and a white-hot core
	var VI := {"col_core": Color(0.56, 0.5, 1.0), "col_mid": Color(0.34, 0.24, 0.92), "col_edge": Color(0.16, 0.08, 0.55)}
	bolt(r, "Halo", Vector3.ZERO, Vector3(0, 0, -1), 0.16, 0.5, fxmat("mix", el, P_bolt({"flicker": 0.3, "intensity": 1.0, "alpha_mul": 0.75, "cel": 0.3, "heat_scale": 0.55}.merged(VI, true))), 16, 54)
	bolt(r, "Outer", Vector3.ZERO, Vector3(0, 0, -1), 0.14, 0.3, fxmat("mix", el, P_bolt({"flicker": 0.35, "intensity": 1.1, "alpha_mul": 0.95, "heat_scale": 0.75}.merged(VI, true))), 16, 51)
	bolt(r, "Main", Vector3.ZERO, Vector3(0, 0, -1), 0.1, 0.17, fxmat("glow", el, P_bolt({"flicker": 0.4, "intensity": 1.5, "heat_scale": 1.3})), 16, 52)
	bolt(r, "Fork", Vector3.ZERO, Vector3(0, 0, -1), 0.26, 0.09, fxmat("glow", el, P_bolt({"flicker": 0.6, "intensity": 1.3, "heat_scale": 1.3})), 12, 53)
	spr(r, "Muzzle", "spotlight_5", 0.9, Color(mid, 0.5), 0.8)
	spr(r, "Tip", "spotlight_5", 1.4, Color(mid, 0.45), 0.8, Vector3(0, 0, -1.0))
	ps(r, "Sparks", {"tex": "trace_02", "n": 10, "life": 0.25, "once": false, "local": true, "shape": "sphere", "radius": 0.06, "v": [2.0, 5.0], "spread": 180, "size": Vector2(0.03, 0.3), "stretch": true, "cols": spark, "aabb": 4.0, "curve": "flat", "pos": Vector3(0, 0, -1.0)})
	save(r, el, "beam")
	r = begin(el, "impact", 0.7)
	spr(r, "Star", "star_06", 4.2, Color(core, 1.0), 1.3, Vector3.ZERO, [A("scale", 0.3, 1.3, 0.0, 0.18, "out"), A("master", 1.0, 0.0, 0.08, 0.34)])
	spr(r, "Flash", "spotlight_5", 3.0, Color(mid, 0.7), 1.0, Vector3.ZERO, [A("scale", 0.4, 1.3, 0.0, 0.2, "out"), A("master", 1.0, 0.0, 0.08, 0.34)])
	spr(r, "Ring", "light_01", 3.6, Color(mid, 1.0), 0.9, Vector3.ZERO, [A("scale", 0.2, 1.0, 0.0, 0.3, "out"), A("master", 1.0, 0.0, 0.1, 0.4)])
	var VI2 := {"col_core": Color(0.56, 0.5, 1.0), "col_mid": Color(0.34, 0.24, 0.92), "col_edge": Color(0.16, 0.08, 0.55)}
	for i in 9:
		var d := Vector3(0, 0, -1.3 - 0.25 * (i % 3)).rotated(Vector3.UP, i * 0.7).rotated(Vector3.RIGHT, 0.6 * (i % 2) - 0.3)
		bolt(r, "Halo%d" % i, Vector3.ZERO, d, 0.18, 0.17, fxmat("mix", el, P_bolt({"flicker": 0.25, "alpha_mul": 0.85, "heat_scale": 0.7}.merged(VI2, true))), 7, 61 + i, [A("progress", 0.0, 1.0, 0.16, 0.48)])
		bolt(r, "Arc%d" % i, Vector3.ZERO, d, 0.18, 0.09, fxmat("glow", el, P_bolt({"flicker": 0.3, "intensity": 1.4, "heat_scale": 1.3})), 7, 61 + i, [A("progress", 0.0, 1.0, 0.16, 0.48)])
	ps(r, "Sparks", {"tex": "trace_02", "n": 18, "life": 0.4, "shape": "sphere", "radius": 0.1, "v": [4.0, 9.0], "spread": 180, "damp": [1, 2], "size": Vector2(0.04, 0.45), "stretch": true, "cols": spark, "curve": "flat"})
	light(r, mid, 5.0, 6.0, 0.18)
	save(r, el, "impact")
	r = begin(el, "aoe", 1.6)
	mesh(r, "Warn", grd(3.2), fxmat("glow", el, P_ring({"mesh_r": 3.2, "ring_r": 0.94, "ring_w": 0.08, "ticks": 20.0, "tick_amt": 0.7, "noise_amt": 0.3, "flicker": 0.2, "intensity": 0.8})), Vector3(0, 0.04, 0), Vector3.ZERO, Vector3.ONE,
		[A("master", 0.0, 1.0, 0.0, 0.2), A("progress", 0.0, 1.0, 1.1, 1.6)])
	mesh(r, "Disc", grd(3.2), fxmat("mix", el, P_ring({"mesh_r": 3.2, "ring_r": 0.9, "ring_fill": 0.6, "ring_w": 0.5, "noise_amt": 0.8, "scroll": Vector3.ZERO, "col_core": Color(0.7, 0.72, 1.0), "col_mid": Color(0.4, 0.4, 0.8), "col_edge": Color(0.2, 0.18, 0.45), "alpha_mul": 0.5, "heat_scale": 1.0})), Vector3(0, 0.03, 0), Vector3.ZERO, Vector3.ONE,
		[A("vis", 0, 0, 0.28, 1.6), A("progress", 0.0, 1.0, 0.9, 1.6)])
	mesh(r, "Wave", grd(3.2), fxmat("glow", el, P_ring({"mesh_r": 3.2, "ring_w": 0.3, "ring_fill": 0.3, "intensity": 0.9, "flicker": 0.2})), Vector3(0, 0.06, 0), Vector3.ZERO, Vector3.ONE,
		[A("vis", 0, 0, 0.28, 1.6), A("ring_r", 0.1, 0.9, 0.28, 0.75, "out"), A("progress", 0.0, 1.0, 0.5, 0.95)])
	var VI3 := {"col_core": Color(0.56, 0.5, 1.0), "col_mid": Color(0.34, 0.24, 0.92), "col_edge": Color(0.16, 0.08, 0.55)}
	bolt(r, "SkyHalo", Vector3(0, 12, 0), Vector3.ZERO, 0.8, 0.95, fxmat("mix", el, P_bolt({"flicker": 0.2, "alpha_mul": 0.8, "heat_scale": 0.7}.merged(VI3, true))), 16, 71, [A("vis", 0, 0, 0.28, 0.62)])
	bolt(r, "Sky", Vector3(0, 12, 0), Vector3.ZERO, 0.8, 0.55, fxmat("glow", el, P_bolt({"flicker": 0.25, "intensity": 1.5, "heat_scale": 1.3})), 16, 71, [A("vis", 0, 0, 0.28, 0.62)])
	bolt(r, "Sky2", Vector3(0.2, 12, 0), Vector3(0, 0, 0.1), 1.0, 0.26, fxmat("glow", el, P_bolt({"flicker": 0.35, "intensity": 1.5, "heat_scale": 1.3})), 16, 72, [A("vis", 0, 0, 0.3, 0.6)])
	spr(r, "Star", "star_06", 6.0, Color(core, 1.0), 1.0, Vector3(0, 0.8, 0), [A("vis", 0, 0, 0.28, 1.0), A("scale", 0.4, 1.3, 0.28, 0.5, "out"), A("master", 1.0, 0.0, 0.32, 0.7)])
	spr(r, "Flash", "spotlight_5", 6.0, Color(mid, 0.6), 0.9, Vector3(0, 0.8, 0), [A("vis", 0, 0, 0.28, 1.0), A("scale", 0.4, 1.2, 0.28, 0.5, "out"), A("master", 1.0, 0.0, 0.32, 0.8)])
	ps(r, "Sparks", {"tex": "trace_02", "n": 26, "life": 0.6, "shape": "ring", "radius": 1.0, "v": [3.0, 8.0], "spread": 40, "grav": Vector3(0, -6, 0), "size": Vector2(0.04, 0.5), "stretch": true, "cols": spark, "curve": "flat", "delay": 0.28, "aabb": 6.0})
	ps(r, "Dust", {"tex": "smoke_04", "n": 8, "life": 1.0, "shape": "ring", "radius": 1.0, "radial": [3.0, 5.0], "damp": [2, 3], "v": [0.5, 1.2], "spread": 30, "size": 1.3, "cols": [[0.0, Color(0.8, 0.8, 0.9, 0.0)], [0.2, Color(0.8, 0.8, 0.9, 0.35)], [1.0, Color(0.8, 0.8, 0.9, 0.0)]], "spin": true, "curve": "grow", "tier": 1, "delay": 0.28, "aabb": 6.0})
	light(r, mid, 6.0, 10.0, 0.4, Vector3(0, 1.0, 0), 0.28)
	save(r, el, "aoe")
	r = begin(el, "status", 0.0, 0.3)
	var arcs := [[Vector3(0.3, 0.4, 0.1), Vector3(0.2, 0.9, 0.2)], [Vector3(-0.3, 1.0, 0.0), Vector3(-0.1, 1.5, 0.2)], [Vector3(0.1, 1.3, -0.2), Vector3(0.35, 1.7, 0.0)]]
	for i in arcs.size():
		bolt(r, "Arc%d" % i, arcs[i][0], arcs[i][1], 0.1, 0.025, fxmat("glow", el, P_bolt({"flicker": 0.75})), 6, 81 + i)
	ps(r, "Sparks", {"tex": "trace_02", "n": 8, "life": 0.3, "once": false, "local": true, "shape": "box", "ext": Vector3(0.3, 0.8, 0.25), "pos": Vector3(0, 1.0, 0), "v": [0.5, 2.0], "spread": 180, "size": Vector2(0.03, 0.22), "stretch": true, "cols": spark, "aabb": 3.0, "curve": "flat"})
	save(r, el, "status")


# ---------------------------------------------------------------- ICE
func build_ice() -> void:
	var el := "ice"
	var p := pal(el)
	var mid: Color = p["mid"]
	var core: Color = p["core"]
	var sp := solid_params({"noise_amt": 0.4, "fake_light": 1.0})
	var glint := [[0.0, Color(core, 0.0)], [0.12, Color(core, 1.0)], [0.7, Color(mid, 0.8)], [1.0, Color(mid, 0.0)]]
	var mist := [[0.0, Color(0.86, 0.95, 1.0, 0.0)], [0.25, Color(0.86, 0.95, 1.0, 0.4)], [1.0, Color(0.8, 0.92, 1.0, 0.0)]]
	var r := begin(el, "charge", 0.0)
	var piv := node(r, "Orbit")
	piv.set_meta("anims", [A("rot_y", 0.0, 190.0, 0.0, 30.0)])
	for i in 6:
		var d := Vector3(cos(i * 1.047), 0.4 * (1 if i % 2 == 0 else -1), sin(i * 1.047)).normalized()
		var m := mesh(piv, "Shard%d" % i, cyl(0.0, 0.05, 0.28, 5, true), fxmat("solid", el, sp), d * 0.2)
		m.basis = Basis(Quaternion(Vector3.UP, d))
	mesh(r, "Core", sph(0.1, 8, 4), fxmat("mix", el, P_orb({"mesh_r": 0.1, "core_facing": 0.9, "alpha_mul": 0.9, "wobble": 0.0})))
	spr(r, "Glow", "spotlight_3", 0.7, Color(mid, 0.35), 0.7)
	ps(r, "Snow", {"tex": "star_04", "n": 10, "life": 1.0, "once": false, "local": true, "shape": "sphere", "radius": 0.3, "v": [0.05, 0.3], "grav": Vector3(0, -0.4, 0), "size": 0.12, "cols": glint, "aabb": 2.0, "spin": true, "curve": "mid"})
	save(r, el, "charge")
	r = begin(el, "aura", 0.0, 0.4)
	mesh(r, "Ring", grd(1.1), fxmat("mix", el, P_ring({"mesh_r": 1.1, "ring_r": 0.85, "ring_w": 0.16, "ring_fill": 0.25, "ticks": 6.0, "tick_amt": 0.5, "alpha_mul": 0.75, "noise_amt": 0.6})), Vector3(0, 0.04, 0))
	for i in 6:
		var a := TAU * i / 6.0
		spike(r, "Crystal%d" % i, fxmat("solid", el, sp), Vector3(cos(a) * 0.75, 0, sin(a) * 0.75), 0.09, 0.4 + 0.15 * (i % 2), rad_to_deg(-a) + 90.0, 16.0, 0.04 * i, 0.25, [], 5)
	ps(r, "Mist", {"tex": "smoke_04", "n": 8, "life": 1.6, "once": false, "local": true, "shape": "ring", "radius": 0.7, "v": [0.1, 0.4], "spread": 20, "size": 0.9, "cols": mist, "spin": true, "curve": "grow", "aabb": 3.0, "pos": Vector3(0, 0.15, 0)})
	ps(r, "Glints", {"tex": "star_04", "n": 12, "life": 1.4, "once": false, "local": true, "shape": "ring", "radius": 0.6, "v": [0.4, 1.0], "spread": 10, "size": 0.14, "cols": glint, "aabb": 3.0, "spin": true, "curve": "mid"})
	save(r, el, "aura")
	r = begin(el, "projectile", 0.0, 0.15)
	var lance := mesh(r, "Lance", cyl(0.0, 0.11, 1.1, 5, true), fxmat("solid", el, sp), Vector3(0, 0, -0.1), Vector3(-90, 0, 0))
	for i in 2:
		mesh(r, "Side%d" % i, cyl(0.0, 0.05, 0.4, 5, true), fxmat("solid", el, sp), Vector3(0.09 * (1 if i == 0 else -1), 0, 0.25), Vector3(-90, 0, 0)).rotation_degrees = Vector3(-90, 0, 20 * (1 if i == 0 else -1))
	mesh(r, "Frost", cyl(0.0, 0.22, 1.3, 10), fxmat("mix", el, P_col({"mesh_h": 1.3, "fade_y": Vector2(0.05, 0.6), "scroll": Vector3(0, -3, 0), "alpha_mul": 0.55, "heat_scale": 1.0, "col_mid": Color(0.75, 0.92, 1.0)})), Vector3(0, 0, 0.9), Vector3(90, 0, 0))
	spr(r, "Glow", "spotlight_3", 0.9, Color(mid, 0.3), 0.6)
	ps(r, "Glints", {"tex": "star_04", "n": 10, "life": 0.6, "once": false, "shape": "sphere", "radius": 0.15, "v": [0.1, 0.5], "spread": 180, "size": 0.14, "cols": glint, "aabb": 4.0, "spin": true, "curve": "mid"})
	ps(r, "Mist", {"tex": "smoke_04", "n": 6, "life": 0.7, "once": false, "shape": "sphere", "radius": 0.1, "v": [0.1, 0.4], "spread": 180, "size": 0.5, "cols": mist, "spin": true, "curve": "grow", "tier": 1, "aabb": 4.0})
	save(r, el, "projectile")
	r = begin(el, "beam", 0.0, 0.25)
	mesh(r, "Ray", cyl(0.42, 0.06, 1.0, 12), fxmat("mix", el, P_col({"mesh_h": 1.0, "fade_y": Vector2(0.04, 0.2), "scroll": Vector3(0, 3, 0), "noise_scale": Vector3(4, 1.6, 4), "alpha_mul": 0.6, "heat_scale": 0.95, "cel": 0.9})), Vector3(0, 0, -0.5), Vector3(-90, 0, 0))
	mesh(r, "Core", cyl(0.14, 0.03, 1.0, 10), fxmat("glow", el, P_col({"mesh_h": 1.0, "fade_y": Vector2(0.04, 0.2), "scroll": Vector3(0, 4, 0), "alpha_mul": 0.6, "intensity": 0.7})), Vector3(0, 0, -0.5), Vector3(-90, 0, 0))
	spr(r, "Muzzle", "spotlight_3", 0.8, Color(mid, 0.35), 0.7)
	spr(r, "Tip", "spotlight_3", 1.4, Color(mid, 0.3), 0.6, Vector3(0, 0, -1.0))
	ps(r, "Snow", {"tex": "star_04", "n": 12, "life": 0.7, "once": false, "local": true, "shape": "sphere", "radius": 0.06, "dir": Vector3(0, 0, -1), "v": [3.0, 6.0], "spread": 14, "size": 0.14, "cols": glint, "aabb": 8.0, "spin": true, "curve": "mid"})
	save(r, el, "beam")
	r = begin(el, "impact", 1.0)
	spr(r, "Star", "star_06", 2.4, Color(core, 1.0), 0.9, Vector3.ZERO, [A("scale", 0.3, 1.2, 0.0, 0.18, "out"), A("master", 1.0, 0.0, 0.05, 0.3)])
	spr(r, "Ring", "light_01", 3.2, Color(mid, 0.9), 0.8, Vector3.ZERO, [A("scale", 0.2, 1.0, 0.0, 0.4, "out"), A("master", 1.0, 0.0, 0.1, 0.45)])
	for i in 6:
		var a := TAU * i / 6.0
		var d := Vector3(cos(a), 0.6 * (1 if i % 2 == 0 else 0.2), sin(a)).normalized()
		var m := mesh(r, "Burst%d" % i, cyl(0.0, 0.1, 0.7, 5, true), fxmat("solid", el, sp.merged({"noise_amt": 0.6})), d * 0.3, Vector3.ZERO, Vector3.ONE * 0.2,
			[A("scale", 0.2, 1.0, 0.0, 0.1, "out"), A("progress", 0.0, 1.0, 0.25, 0.7, "in")])
		m.basis = Basis(Quaternion(Vector3.UP, d)) * Basis.from_scale(Vector3.ONE * 0.2)
	ps(r, "Shards", {"mesh": shard_mesh(0.05, 0.22, lit_mat(Color(0.75, 0.92, 1.0), 0.25, 0.4)), "n": 10, "life": 0.7, "shape": "sphere", "radius": 0.1, "v": [3.0, 6.5], "spread": 180, "grav": Vector3(0, -10, 0), "cols": [[0.0, Color.WHITE], [1.0, Color.WHITE]], "curve": "shrink"})
	ps(r, "Mist", {"tex": "smoke_04", "n": 6, "life": 0.9, "shape": "sphere", "radius": 0.3, "v": [0.5, 1.5], "spread": 180, "size": 1.1, "cols": mist, "spin": true, "curve": "grow", "tier": 1})
	ps(r, "Glints", {"tex": "star_04", "n": 14, "life": 0.8, "shape": "sphere", "radius": 0.3, "v": [1.0, 3.5], "spread": 180, "damp": [1, 2], "size": 0.16, "cols": glint, "spin": true, "curve": "mid"})
	light(r, mid, 3.0, 6.0, 0.25)
	save(r, el, "impact")
	r = begin(el, "aoe", 2.0)
	mesh(r, "Frost", grd(3.2), fxmat("mix", el, P_ring({"mesh_r": 3.2, "ring_r": 0.92, "ring_fill": 1.0, "noise_amt": 0.85, "noise_scale": Vector3(4, 4, 4), "scroll": Vector3.ZERO, "col_core": Color(0.95, 1, 1), "col_mid": Color(0.7, 0.9, 1.0), "col_edge": Color(0.45, 0.7, 0.95),
		"alpha_mul": 0.6, "cel": 0.9, "heat_scale": 0.55})), Vector3(0, 0.03, 0), Vector3.ZERO, Vector3.ONE, [A("scale", 0.2, 1.0, 0.0, 0.4, "out"), A("progress", 0.0, 1.0, 1.4, 2.0)])
	mesh(r, "Wave", grd(3.2), fxmat("glow", el, P_ring({"mesh_r": 3.2, "ring_w": 0.3, "ring_fill": 0.3, "intensity": 0.8, "noise_amt": 0.6})), Vector3(0, 0.06, 0), Vector3.ZERO, Vector3.ONE,
		[A("ring_r", 0.1, 0.9, 0.0, 0.5, "out"), A("progress", 0.0, 1.0, 0.3, 0.75)])
	seed(9)
	spike(r, "Core", fxmat("solid", el, sp), Vector3.ZERO, 0.5, 3.0, 0.0, 0.0, 0.0, 0.14, [1.4, 1.9], 6)
	var idx := 0
	for ring in [[1.2, 6, 2.0, 0.26, 0.05], [2.2, 9, 1.6, 0.22, 0.12]]:
		for i in ring[1]:
			var a: float = TAU * (i + 0.5 * idx) / ring[1]
			var hh: float = ring[2] * randf_range(0.8, 1.3)
			var s := spike(r, "S%d" % idx, fxmat("solid", el, sp), Vector3(cos(a) * ring[0], 0, sin(a) * ring[0]), ring[3] * randf_range(0.85, 1.1), hh, rad_to_deg(-a) + 90.0, randf_range(8, 22), ring[4] + randf() * 0.07, 0.14, [], 5)
			var an: Array = s.get_meta("anims", [])
			an.append(A("progress", 0.0, 1.0, 1.4 + randf() * 0.2, 2.0, "in"))
			s.set_meta("anims", an)
			idx += 1
	ps(r, "Mist", {"tex": "smoke_04", "n": 12, "life": 1.3, "shape": "ring", "radius": 1.0, "inner": 0.2, "radial": [3.0, 6.0], "damp": [2, 3], "v": [0.3, 0.9], "spread": 30, "size": 1.4, "cols": mist, "spin": true, "curve": "grow", "aabb": 6.0, "tier": 1})
	ps(r, "Glints", {"tex": "star_04", "n": 24, "life": 1.4, "shape": "ring", "radius": 2.0, "v": [0.5, 2.0], "spread": 20, "size": 0.16, "cols": glint, "aabb": 6.0, "spin": true, "curve": "mid", "delay": 0.1})
	ps(r, "Shards", {"mesh": shard_mesh(0.05, 0.2, lit_mat(Color(0.75, 0.92, 1.0), 0.25, 0.4)), "n": 12, "life": 1.0, "shape": "ring", "radius": 1.6, "v": [2.0, 5.0], "spread": 30, "grav": Vector3(0, -10, 0), "cols": [[0.0, Color.WHITE], [1.0, Color.WHITE]], "aabb": 6.0, "tier": 1, "delay": 1.35})
	spr(r, "Flash", "spotlight_5", 5.0, Color(mid, 0.4), 0.8, Vector3(0, 0.5, 0), [A("scale", 0.3, 1.2, 0.0, 0.3, "out"), A("master", 1.0, 0.0, 0.05, 0.4)])
	light(r, mid, 3.5, 9.0, 0.5, Vector3(0, 0.6, 0))
	save(r, el, "aoe")
	r = begin(el, "status", 0.0, 0.4)
	mesh(r, "Coat", cyl(0.4, 0.44, 1.8, 14, false), fxmat("mix", el, P_orb({"shape_mode": 2, "noise_amt": 0.5, "scroll": Vector3.ZERO, "core_facing": -0.5, "rim_alpha": 0.9, "alpha_mul": 0.4, "heat_scale": 1.0, "wobble": 0.0, "cel": 0.9, "fresnel_pow": 1.4})), Vector3(0, 0.9, 0))
	var cr := [[Vector3(0.3, 1.4, 0.05), 25.0], [Vector3(-0.32, 1.1, 0.0), -30.0], [Vector3(0.05, 1.7, 0.28), 60.0], [Vector3(0.28, 0.5, 0.1), 40.0], [Vector3(-0.25, 0.4, 0.2), -45.0], [Vector3(0.0, 1.0, -0.3), 70.0]]
	for i in cr.size():
		var m := mesh(r, "Crystal%d" % i, cyl(0.0, 0.07, 0.35, 5, true), fxmat("solid", el, sp), cr[i][0])
		m.rotation_degrees = Vector3(cr[i][1] * (1 if i % 2 == 0 else -0.6), i * 60.0, cr[i][1])
	mesh(r, "Ring", grd(0.8), fxmat("mix", el, P_ring({"mesh_r": 0.8, "ring_r": 0.75, "ring_w": 0.2, "ring_fill": 0.5, "alpha_mul": 0.6, "col_mid": Color(0.7, 0.9, 1.0), "heat_scale": 1.0})), Vector3(0, 0.03, 0))
	ps(r, "Mist", {"tex": "smoke_04", "n": 5, "life": 1.4, "once": false, "local": true, "shape": "ring", "radius": 0.45, "v": [0.1, 0.3], "spread": 20, "size": 0.7, "cols": mist, "spin": true, "curve": "grow", "aabb": 3.0, "pos": Vector3(0, 0.15, 0), "tier": 1})
	ps(r, "Glints", {"tex": "star_04", "n": 6, "life": 1.0, "once": false, "local": true, "shape": "box", "ext": Vector3(0.3, 0.8, 0.25), "pos": Vector3(0, 1.0, 0), "v": [0, 0.2], "size": 0.13, "cols": glint, "aabb": 3.0, "spin": true, "curve": "mid"})
	save(r, el, "status")


# ---------------------------------------------------------------- LIGHT
func build_light() -> void:
	var el := "light"
	var p := pal(el)
	var mid: Color = p["mid"]
	var core: Color = p["core"]
	var edge: Color = p["edge"]
	var mote := [[0.0, Color(core, 0.0)], [0.12, Color(core, 1.0)], [0.6, Color(mid, 0.9)], [1.0, Color(edge, 0.0)]]
	var r := begin(el, "charge", 0.0)
	mesh(r, "Orb", sph(0.14), fxmat("mix", el, P_orb({"mesh_r": 0.14, "noise_amt": 0.3, "core_facing": 1.0, "heat_scale": 0.8, "wobble": 0.02, "scroll": Vector3(0, -1, 0)})))
	spr(r, "Rays", "effect_2", 1.5, Color(mid, 0.55), 0.8, Vector3.ZERO, [], 0.8)
	spr(r, "Star", "star_06", 0.8, Color(core, 0.9), 0.9, Vector3.ZERO, [], -0.5)
	ps(r, "Motes", {"tex": "star_04", "n": 10, "life": 0.9, "once": false, "local": true, "shape": "sphere", "radius": 0.5, "radial": [-3.0, -4.0], "v": [0, 0.1], "size": 0.14, "cols": mote, "aabb": 2.0, "spin": true, "curve": "mid"})
	light(r, mid, 1.2, 4.0, 9999.0)
	save(r, el, "charge")
	r = begin(el, "aura", 0.0, 0.4)
	mesh(r, "Column", cyl(0.5, 0.55, 2.0, 16), fxmat("mix", el, P_col({"mesh_h": 2.0, "noise_amt": 0.5, "scroll": Vector3(0, -1.0, 0), "fade_y": Vector2(0.15, 0.4), "alpha_mul": 0.4, "heat_scale": 0.9})), Vector3(0, 1.0, 0))
	mesh(r, "Halo", grd(0.32), fxmat("glow", el, P_ring({"mesh_r": 0.32, "ring_r": 0.7, "ring_w": 0.22, "noise_amt": 0.2, "intensity": 0.9, "scroll": Vector3.ZERO})), Vector3(0, 2.05, 0))
	mesh(r, "Ring", grd(1.0), fxmat("glow", el, P_ring({"mesh_r": 1.0, "ring_r": 0.85, "ring_w": 0.08, "ticks": 12.0, "tick_amt": 0.6, "spin": 0.6, "intensity": 0.8})), Vector3(0, 0.04, 0))
	ps(r, "Motes", {"tex": "star_04", "n": 12, "life": 1.5, "once": false, "local": true, "shape": "ring", "radius": 0.55, "v": [0.5, 1.2], "spread": 8, "size": 0.14, "cols": mote, "aabb": 3.0, "spin": true, "curve": "mid"})
	save(r, el, "aura")
	r = begin(el, "projectile", 0.0, 0.15)
	mesh(r, "Orb", sph(0.2), fxmat("mix", el, P_orb({"mesh_r": 0.2, "noise_amt": 0.3, "core_facing": 1.0, "heat_scale": 0.85, "wobble": 0.03})))
	spr(r, "Rays", "effect_2", 1.6, Color(mid, 0.55), 0.8, Vector3.ZERO, [], 1.2)
	spr(r, "Star", "star_06", 1.0, Color(core, 0.9), 0.9, Vector3.ZERO, [], -0.8)
	mesh(r, "Trail", cyl(0.0, 0.2, 1.4, 12), fxmat("mix", el, P_col({"mesh_h": 1.4, "fade_y": Vector2(0.05, 0.6), "scroll": Vector3(0, -3, 0), "alpha_mul": 0.6, "heat_scale": 0.9})), Vector3(0, 0, 0.75), Vector3(90, 0, 0))
	ps(r, "Motes", {"tex": "star_04", "n": 12, "life": 0.7, "once": false, "shape": "sphere", "radius": 0.15, "v": [0.1, 0.6], "spread": 180, "size": 0.14, "cols": mote, "aabb": 4.0, "spin": true, "curve": "mid"})
	light(r, mid, 1.8, 5.0, 9999.0)
	save(r, el, "projectile")
	r = begin(el, "beam", 0.0, 0.25)
	mesh(r, "Ray", cyl(0.24, 0.2, 1.0, 14), fxmat("mix", el, P_col({"mesh_h": 1.0, "fade_y": Vector2(0.02, 0.05), "scroll": Vector3(0, 2, 0), "noise_scale": Vector3(3, 1.5, 3), "noise_amt": 0.45, "alpha_mul": 0.75, "heat_scale": 0.6})), Vector3(0, 0, -0.5), Vector3(-90, 0, 0))
	mesh(r, "Core", cyl(0.09, 0.08, 1.0, 10), fxmat("glow", el, P_col({"mesh_h": 1.0, "fade_y": Vector2(0.02, 0.05), "scroll": Vector3(0, 3, 0), "noise_amt": 0.3, "alpha_mul": 0.9, "intensity": 0.8, "col_mid": core})), Vector3(0, 0, -0.5), Vector3(-90, 0, 0))
	spr(r, "Muzzle", "star_06", 1.0, Color(core, 0.9), 0.9, Vector3.ZERO, [], 0.5)
	spr(r, "Tip", "spotlight_5", 1.8, Color(mid, 0.5), 0.8, Vector3(0, 0, -1.0))
	ps(r, "Motes", {"tex": "star_04", "n": 12, "life": 0.8, "once": false, "local": true, "shape": "sphere", "radius": 0.1, "dir": Vector3(0, 0, -1), "v": [2.0, 4.0], "spread": 12, "size": 0.14, "cols": mote, "aabb": 8.0, "spin": true, "curve": "mid"})
	save(r, el, "beam")
	r = begin(el, "impact", 1.0)
	spr(r, "Star", "star_06", 3.6, Color(core, 1.0), 1.0, Vector3.ZERO, [A("scale", 0.3, 1.3, 0.0, 0.2, "out"), A("master", 1.0, 0.0, 0.1, 0.5)])
	spr(r, "Rays", "effect_2", 4.2, Color(mid, 0.7), 0.9, Vector3.ZERO, [A("scale", 0.3, 1.2, 0.0, 0.3, "out"), A("master", 1.0, 0.0, 0.1, 0.6)], 0.6)
	spr(r, "Ring", "light_01", 3.4, Color(mid, 0.9), 0.8, Vector3.ZERO, [A("scale", 0.2, 1.0, 0.0, 0.4, "out"), A("master", 1.0, 0.0, 0.1, 0.45)])
	ps(r, "Motes", {"tex": "star_04", "n": 16, "life": 0.9, "shape": "sphere", "radius": 0.2, "v": [1.5, 4.0], "spread": 180, "damp": [1, 2], "size": 0.2, "cols": mote, "spin": true, "curve": "mid"})
	light(r, mid, 3.5, 6.0, 0.3)
	save(r, el, "impact")
	r = begin(el, "aoe", 2.0)
	mesh(r, "Sigil", grd(3.2), fxmat("glow", el, P_ring({"mesh_r": 3.2, "ring_r": 0.94, "ring_w": 0.07, "ticks": 12.0, "tick_amt": 0.6, "spin": 0.5, "noise_amt": 0.25, "intensity": 0.85, "ring_fill": 0.0})), Vector3(0, 0.04, 0), Vector3.ZERO, Vector3.ONE,
		[A("master", 0.0, 1.0, 0.0, 0.25), A("progress", 0.0, 1.0, 1.5, 2.0)])
	mesh(r, "Inner", grd(3.2), fxmat("mix", el, P_ring({"mesh_r": 3.2, "ring_r": 0.9, "ring_fill": 1.0, "ring_w": 0.5, "noise_amt": 0.6, "alpha_mul": 0.45, "heat_scale": 1.0})), Vector3(0, 0.03, 0), Vector3.ZERO, Vector3.ONE,
		[A("scale", 0.2, 1.0, 0.0, 0.4, "out"), A("progress", 0.0, 1.0, 1.3, 2.0)])
	mesh(r, "Wave", grd(3.2), fxmat("glow", el, P_ring({"mesh_r": 3.2, "ring_w": 0.28, "ring_fill": 0.2, "intensity": 0.85})), Vector3(0, 0.06, 0), Vector3.ZERO, Vector3.ONE,
		[A("ring_r", 0.1, 0.9, 0.05, 0.65, "out"), A("progress", 0.0, 1.0, 0.35, 0.9)])
	mesh(r, "Pillar", cyl(1.25, 1.25, 8.0, 20), fxmat("mix", el, P_col({"mesh_h": 8.0, "noise_amt": 0.45, "noise_scale": Vector3(2, 0.6, 2), "scroll": Vector3(0, -1.5, 0), "fade_y": Vector2(0.03, 0.55), "alpha_mul": 0.5, "heat_scale": 0.6})),
		Vector3(0, 4.0, 0), Vector3.ZERO, Vector3(0.2, 1, 0.2), [A("scale", Vector3(0.2, 1, 0.2), Vector3(1, 1, 1), 0.05, 0.5, "out"), A("progress", 0.0, 1.0, 1.2, 1.9, "in")])
	mesh(r, "PillarCore", cyl(0.55, 0.55, 8.0, 14), fxmat("glow", el, P_col({"mesh_h": 8.0, "noise_amt": 0.35, "scroll": Vector3(0, -2, 0), "fade_y": Vector2(0.03, 0.6), "alpha_mul": 0.35, "intensity": 0.6, "col_mid": core})),
		Vector3(0, 4.0, 0), Vector3.ZERO, Vector3(0.2, 1, 0.2), [A("scale", Vector3(0.2, 1, 0.2), Vector3(1, 1, 1), 0.1, 0.5, "out"), A("progress", 0.0, 1.0, 1.1, 1.8, "in")])
	spr(r, "Rays", "effect_2", 6.0, Color(mid, 0.5), 0.8, Vector3(0, 0.6, 0), [A("scale", 0.3, 1.1, 0.0, 0.5, "out"), A("master", 1.0, 0.0, 0.8, 1.7)], 0.4)
	ps(r, "Motes", {"tex": "star_04", "n": 40, "life": 1.6, "shape": "ring", "radius": 1.5, "inner": 0.0, "v": [2.0, 4.5], "spread": 8, "grav": Vector3(0, 0.3, 0), "size": 0.2, "cols": mote, "spin": true, "curve": "mid", "delay": 0.1, "aabb": 8.0})
	light(r, mid, 4.0, 10.0, 0.9, Vector3(0, 1.0, 0))
	save(r, el, "aoe")
	r = begin(el, "status", 0.0, 0.4)
	mesh(r, "Halo", grd(0.28), fxmat("glow", el, P_ring({"mesh_r": 0.28, "ring_r": 0.7, "ring_w": 0.22, "noise_amt": 0.2, "intensity": 0.9, "scroll": Vector3.ZERO, "pulse": 0.15})), Vector3(0, 2.05, 0))
	mesh(r, "Ring", grd(0.9), fxmat("glow", el, P_ring({"mesh_r": 0.9, "ring_r": 0.8, "ring_w": 0.1, "ticks": 12.0, "tick_amt": 0.6, "spin": 0.7, "intensity": 0.7})), Vector3(0, 0.04, 0))
	ps(r, "Motes", {"tex": "star_04", "n": 8, "life": 1.4, "once": false, "local": true, "shape": "box", "ext": Vector3(0.3, 0.1, 0.25), "pos": Vector3(0, 0.3, 0), "v": [0.5, 1.0], "spread": 10, "size": 0.14, "cols": mote, "aabb": 3.0, "spin": true, "curve": "mid"})
	save(r, el, "status")


# ---------------------------------------------------------------- DARK
func build_dark() -> void:
	var el := "dark"
	var p := pal(el)
	var mid: Color = p["mid"]
	var core: Color = p["core"]
	var edge: Color = p["edge"]
	var void_orb := P_orb({"noise_amt": 0.5, "core_facing": -1.2, "rim_alpha": 0.9, "heat_scale": 0.9, "wobble": 0.05, "scroll": Vector3(0, -1.0, 0), "alpha_mul": 1.0, "fresnel_pow": 1.3})
	var wisp := [[0.0, Color(0.25, 0.1, 0.4, 0.0)], [0.2, Color(0.22, 0.08, 0.36, 0.6)], [1.0, Color(0.12, 0.04, 0.2, 0.0)]]
	var vio := [[0.0, Color(core, 0.0)], [0.1, Color(core, 1.0)], [0.6, Color(mid, 0.9)], [1.0, Color(mid, 0.0)]]
	var r := begin(el, "charge", 0.0)
	mesh(r, "Orb", sph(0.15), fxmat("mix", el, void_orb.merged({"mesh_r": 0.15})))
	spr(r, "Glow", "spotlight_3", 0.7, Color(mid, 0.3), 0.6)
	ps(r, "Wisps", {"tex": "smoke_04", "n": 8, "life": 0.9, "once": false, "local": true, "shape": "sphere", "radius": 0.5, "radial": [-3.0, -4.0], "v": [0, 0.1], "size": 0.4, "cols": wisp, "spin": true, "curve": "shrink", "aabb": 2.0})
	ps(r, "Sparks", {"tex": "star_04", "n": 6, "life": 0.8, "once": false, "local": true, "shape": "sphere", "radius": 0.4, "radial": [-2.0, -3.0], "v": [0, 0.1], "size": 0.1, "cols": vio, "spin": true, "curve": "shrink", "tier": 1, "aabb": 2.0})
	save(r, el, "charge")
	r = begin(el, "aura", 0.0, 0.4)
	mesh(r, "Veil", cyl(0.45, 0.55, 1.9, 16), fxmat("mix", el, P_orb({"shape_mode": 2, "noise_amt": 0.6, "core_facing": -0.6, "rim_alpha": 1.0, "alpha_mul": 0.3, "heat_scale": 1.0, "wobble": 0.0, "scroll": Vector3(0, -1.2, 0), "fresnel_pow": 1.4})), Vector3(0, 0.95, 0))
	mesh(r, "Shadow", grd(1.0), fxmat("mix", el, P_ring({"mesh_r": 1.0, "ring_r": 0.85, "ring_w": 0.2, "ring_fill": 0.8, "alpha_mul": 0.55, "noise_amt": 0.6, "heat_scale": 0.8})), Vector3(0, 0.03, 0))
	ps(r, "Wisps", {"tex": "smoke_04", "n": 12, "life": 1.4, "once": false, "local": true, "shape": "ring", "radius": 0.5, "v": [0.6, 1.3], "spread": 12, "size": 0.7, "cols": wisp, "spin": true, "curve": "grow", "aabb": 3.0})
	ps(r, "Sparks", {"tex": "star_04", "n": 8, "life": 1.4, "once": false, "local": true, "shape": "ring", "radius": 0.5, "v": [0.5, 1.2], "spread": 12, "size": 0.12, "cols": vio, "tier": 1, "spin": true, "curve": "mid", "aabb": 3.0})
	save(r, el, "aura")
	r = begin(el, "projectile", 0.0, 0.15)
	mesh(r, "Orb", sph(0.23), fxmat("mix", el, void_orb.merged({"mesh_r": 0.23, "wobble": 0.09})))
	mesh(r, "Swirl", cyl(0.0, 0.26, 1.4, 12), fxmat("mix", el, P_col({"mesh_h": 1.4, "fade_y": Vector2(0.05, 0.6), "spiral": Vector3(3, 8, -8), "spiral_amt": 0.7, "noise_amt": 0.5, "alpha_mul": 0.7, "heat_scale": 0.8})), Vector3(0, 0, 0.75), Vector3(90, 0, 0))
	spr(r, "Glow", "spotlight_3", 0.9, Color(mid, 0.3), 0.6)
	ps(r, "Wisps", {"tex": "smoke_04", "n": 10, "life": 0.8, "once": false, "shape": "sphere", "radius": 0.15, "v": [0.1, 0.5], "spread": 180, "size": 0.5, "cols": wisp, "spin": true, "curve": "grow", "aabb": 4.0})
	ps(r, "Sparks", {"tex": "star_04", "n": 8, "life": 0.6, "once": false, "shape": "sphere", "radius": 0.2, "v": [0.1, 0.6], "spread": 180, "size": 0.12, "cols": vio, "tier": 1, "spin": true, "curve": "mid", "aabb": 4.0})
	save(r, el, "projectile")
	r = begin(el, "beam", 0.0, 0.25)
	mesh(r, "Drain", cyl(0.2, 0.14, 1.0, 14), fxmat("mix", el, P_col({"mesh_h": 1.0, "spiral": Vector3(2, 18, 10), "spiral_amt": 1.0, "noise_amt": 0.4, "fade_y": Vector2(0.03, 0.05), "alpha_mul": 0.9, "heat_scale": 0.9, "scroll": Vector3(0, 3, 0)})), Vector3(0, 0, -0.5), Vector3(-90, 0, 0))
	mesh(r, "Glow", cyl(0.07, 0.05, 1.0, 10), fxmat("glow", el, P_col({"mesh_h": 1.0, "spiral": Vector3(2, 24, -12), "spiral_amt": 0.6, "fade_y": Vector2(0.03, 0.05), "alpha_mul": 0.6, "intensity": 0.7, "scroll": Vector3(0, 3, 0)})), Vector3(0, 0, -0.5), Vector3(-90, 0, 0))
	spr(r, "Muzzle", "spotlight_3", 0.8, Color(mid, 0.3), 0.6)
	spr(r, "Tip", "spotlight_3", 1.4, Color(mid, 0.3), 0.6, Vector3(0, 0, -1.0))
	ps(r, "Drain", {"tex": "star_04", "n": 10, "life": 0.6, "once": false, "local": true, "shape": "sphere", "radius": 0.15, "pos": Vector3(0, 0, -1.0), "dir": Vector3(0, 0, 1), "v": [4.0, 8.0], "spread": 8, "size": 0.12, "cols": vio, "spin": true, "curve": "flat", "aabb": 8.0})
	save(r, el, "beam")
	r = begin(el, "impact", 1.0)
	mesh(r, "Implode", sph(0.9, 14, 8), fxmat("mix", el, void_orb.merged({"mesh_r": 0.9})), Vector3.ZERO, Vector3.ZERO, Vector3.ONE,
		[A("scale", 1.0, 0.25, 0.0, 0.22, "in"), A("vis", 0, 0, 0.0, 0.24)])
	spr(r, "Flash", "spotlight_5", 2.4, Color(mid, 0.6), 0.9, Vector3.ZERO, [A("vis", 0, 0, 0.2, 1.0), A("scale", 0.3, 1.4, 0.2, 0.45, "out"), A("master", 1.0, 0.0, 0.22, 0.55)])
	spr(r, "Star", "star_06", 2.6, Color(core, 0.9), 0.9, Vector3.ZERO, [A("vis", 0, 0, 0.2, 1.0), A("scale", 0.3, 1.2, 0.2, 0.4, "out"), A("master", 1.0, 0.0, 0.22, 0.5)])
	spr(r, "Ring", "light_01", 3.4, Color(mid, 0.9), 0.8, Vector3.ZERO, [A("vis", 0, 0, 0.2, 1.0), A("scale", 0.2, 1.0, 0.2, 0.6, "out"), A("master", 1.0, 0.0, 0.3, 0.65)])
	ps(r, "Wisps", {"tex": "smoke_04", "n": 8, "life": 0.8, "shape": "sphere", "radius": 0.2, "v": [1.5, 3.5], "spread": 180, "damp": [1, 2], "size": 0.9, "cols": wisp, "spin": true, "curve": "grow", "delay": 0.2})
	ps(r, "Sparks", {"tex": "trace_02", "n": 14, "life": 0.5, "shape": "sphere", "radius": 0.1, "v": [3.0, 7.0], "spread": 180, "damp": [1, 2], "size": Vector2(0.04, 0.4), "stretch": true, "cols": vio, "curve": "flat", "delay": 0.2})
	save(r, el, "impact")
	r = begin(el, "aoe", 2.2)
	mesh(r, "Hole", grd(3.2), fxmat("mix", el, P_ring({"mesh_r": 3.2, "ring_r": 0.9, "ring_fill": 1.0, "noise_amt": 0.7, "noise_scale": Vector3(3, 3, 3), "scroll": Vector3(0.2, 0, 0.2), "alpha_mul": 0.85, "cel": 0.9, "heat_scale": 0.35})), Vector3(0, 0.03, 0), Vector3.ZERO, Vector3.ONE,
		[A("scale", 0.2, 1.0, 0.0, 0.5, "out"), A("progress", 0.0, 1.0, 1.6, 2.2)])
	mesh(r, "Rim", grd(3.2), fxmat("glow", el, P_ring({"mesh_r": 3.2, "ring_r": 0.94, "ring_w": 0.07, "ticks": 18.0, "tick_amt": 0.6, "spin": -0.8, "noise_amt": 0.3, "intensity": 0.75})), Vector3(0, 0.05, 0), Vector3.ZERO, Vector3.ONE,
		[A("master", 0.0, 1.0, 0.0, 0.25), A("progress", 0.0, 1.0, 1.6, 2.2)])
	mesh(r, "Orb", sph(0.7), fxmat("mix", el, void_orb.merged({"mesh_r": 0.7})), Vector3(0, 1.3, 0), Vector3.ZERO, Vector3.ONE * 0.01,
		[A("scale", 0.01, 1.0, 0.1, 0.55, "back"), A("progress", 0.0, 1.0, 1.7, 2.2)])
	seed(5)
	for i in 7:
		var a := TAU * i / 7.0 + 0.3
		var rad := 1.6 + 0.8 * (i % 2)
		var m := mesh(r, "Tendril%d" % i, cyl(0.0, 0.2, 2.8, 8, false), fxmat("mix", el, P_col({"mesh_h": 2.8, "fade_y": Vector2(0.05, 0.3), "noise_amt": 0.6, "wobble": 0.3, "wobble_scale": 1.5, "scroll": Vector3(0, -1.5, 0), "alpha_mul": 0.9, "heat_scale": 0.8})),
			Vector3(cos(a) * rad, 1.4, sin(a) * rad), Vector3.ZERO, Vector3(1, 0.05, 1))
		m.rotation = Basis(Quaternion(Vector3.UP, Vector3(-cos(a) * 0.35, 1, -sin(a) * 0.35).normalized())).get_euler()
		m.set_meta("anims", [A("scale", Vector3(1, 0.05, 1), Vector3(1, 1, 1), 0.1 + i * 0.05, 0.6 + i * 0.05, "out"), A("y", 0.1, 1.4, 0.1 + i * 0.05, 0.6 + i * 0.05, "out"), A("progress", 0.0, 1.0, 1.6, 2.2)])
	ps(r, "Wisps", {"tex": "smoke_04", "n": 20, "life": 1.4, "shape": "ring", "radius": 2.6, "inner": 0.5, "radial": [-3.0, -1.5], "v": [0.3, 1.0], "spread": 30, "size": 0.9, "cols": wisp, "spin": true, "curve": "grow", "aabb": 6.0, "delay": 0.1})
	ps(r, "Sparks", {"tex": "star_04", "n": 20, "life": 1.3, "shape": "ring", "radius": 2.6, "inner": 0.5, "radial": [-3.5, -2.0], "v": [0.3, 1.0], "spread": 30, "size": 0.14, "cols": vio, "spin": true, "curve": "mid", "tier": 1, "aabb": 6.0, "delay": 0.15})
	save(r, el, "aoe")
	r = begin(el, "status", 0.0, 0.4)
	mesh(r, "Ring", grd(0.9), fxmat("mix", el, P_ring({"mesh_r": 0.9, "ring_r": 0.8, "ring_w": 0.2, "ring_fill": 0.6, "ticks": 8.0, "tick_amt": 0.5, "spin": 1.5, "alpha_mul": 0.7, "heat_scale": 0.9})), Vector3(0, 0.03, 0))
	spr(r, "Sigil", "magic_02", 0.5, Color(mid, 0.9), 0.9, Vector3(0, 2.1, 0), [], 0.9)
	ps(r, "Wisps", {"tex": "smoke_04", "n": 8, "life": 1.4, "once": false, "local": true, "shape": "ring", "radius": 0.35, "v": [0.5, 1.0], "spread": 10, "size": 0.55, "cols": wisp, "spin": true, "curve": "grow", "aabb": 3.0})
	ps(r, "Sparks", {"tex": "star_04", "n": 5, "life": 1.2, "once": false, "local": true, "shape": "ring", "radius": 0.35, "v": [0.4, 0.9], "size": 0.1, "cols": vio, "spin": true, "curve": "mid", "tier": 1, "aabb": 3.0})
	save(r, el, "status")
# ---------------------------------------------------------------- GENERIC
func build_generic() -> void:
	var el := "light"
	var p := pal(el)
	var mid: Color = p["mid"]
	var core: Color = p["core"]
	# sword slash
	var r := begin(el, "slash_sword", 0.6)
	var am := K.arc_mesh(1.6, 170.0, 0.5, 24, 0.5)
	mesh(r, "Arc", am, fxmat("add", el, {"shape_mode": 3, "noise_amt": 0.35, "noise_scale": Vector3(6, 6, 6), "scroll": Vector3(3, 0, 0), "cel": 0.6, "bands": 3.0, "tail_len": 0.65, "intensity": 1.15}),
		Vector3.ZERO, Vector3(0, 180, 0), Vector3.ONE, [A("reveal", 0.0, 1.0, 0.0, 0.11, "out"), A("progress", 0.0, 1.0, 0.1, 0.42, "inout")])
	mesh(r, "Arc2", K.arc_mesh(1.45, 150.0, 0.22, 24, 0.5), fxmat("add", el, {"shape_mode": 3, "noise_amt": 0.2, "cel": 0.5, "bands": 2.0, "tail_len": 0.5, "intensity": 1.5,
		"col_edge": core, "col_mid": core, "col_core": Color.WHITE}), Vector3.ZERO, Vector3(0, 180, 0), Vector3.ONE, [A("reveal", 0.0, 1.0, 0.02, 0.12, "out"), A("progress", 0.0, 1.0, 0.08, 0.3)])
	ps(r, "Sparks", {"tex": "trace_02", "n": 10, "life": 0.4, "shape": "point", "pos": Vector3(-1.55, 0, -0.14), "v": [2.0, 6.0], "dir": Vector3(-1, 0.2, -0.3), "spread": 55,
		"grav": Vector3(0, -6, 0), "size": Vector2(0.05, 0.4), "stretch": true, "cols": [[0.0, Color(1, 1, 1, 0)], [0.1, Color.WHITE], [1.0, Color(1, 1, 1, 0)]], "tint": true, "tint_white": 0.2, "delay": 0.07, "aabb": 4.0})
	save(r, "generic", "slash_sword")
	# fist slash: short, thick, with an impact star
	r = begin(el, "slash_fist", 0.5)
	mesh(r, "Arc", K.arc_mesh(1.1, 110.0, 0.65, 18, 0.4), fxmat("add", el, {"shape_mode": 3, "noise_amt": 0.4, "noise_scale": Vector3(5, 5, 5), "scroll": Vector3(3, 0, 0), "cel": 0.6, "tail_len": 0.55, "intensity": 1.2}),
		Vector3(0, 0, 0.2), Vector3(0, 180, 0), Vector3.ONE, [A("reveal", 0.0, 1.0, 0.0, 0.08, "out"), A("progress", 0.0, 1.0, 0.07, 0.36, "inout")])
	spr(r, "Star", "star_06", 1.3, Color(core, 0.9), 1.0, Vector3(0, 0, -1.05), [A("scale", 0.3, 1.2, 0.05, 0.2, "out"), A("master", 1.0, 0.0, 0.1, 0.32)], 0.0)
	ps(r, "Sparks", {"tex": "trace_02", "n": 8, "life": 0.35, "pos": Vector3(0, 0, -1.05), "v": [2.0, 5.0], "dir": Vector3(0, 0, -1), "spread": 70, "grav": Vector3(0, -6, 0),
		"size": Vector2(0.05, 0.35), "stretch": true, "cols": [[0.0, Color(1, 1, 1, 0)], [0.1, Color.WHITE], [1.0, Color(1, 1, 1, 0)]], "tint": true, "tint_white": 0.2, "delay": 0.06, "aabb": 3.0})
	save(r, "generic", "slash_fist")
	# hit sparks
	r = begin(el, "hit_sparks", 0.55)
	spr(r, "Star", "star_06", 1.2, Color(core, 1.0), 1.1, Vector3.ZERO, [A("scale", 0.3, 1.3, 0.0, 0.14, "out"), A("master", 1.0, 0.0, 0.04, 0.2)], 0.0)
	spr(r, "Flash", "spotlight_5", 1.5, Color(mid, 0.8), 0.9, Vector3.ZERO, [A("scale", 0.5, 1.2, 0.0, 0.18, "out"), A("master", 1.0, 0.0, 0.03, 0.22)])
	ps(r, "Sparks", {"tex": "trace_02", "n": 14, "life": 0.45, "shape": "sphere", "radius": 0.05, "v": [3.0, 7.0], "spread": 180, "grav": Vector3(0, -9, 0), "damp": [1, 3],
		"size": Vector2(0.05, 0.4), "stretch": true, "cols": [[0.0, Color(1, 1, 1, 0)], [0.08, Color.WHITE], [1.0, Color(1, 1, 1, 0)]], "tint": true, "tint_white": 0.25, "aabb": 3.0})
	ps(r, "Motes", {"tex": "circle_05", "n": 8, "life": 0.5, "shape": "sphere", "radius": 0.05, "v": [1.0, 3.0], "spread": 180, "grav": Vector3(0, -4, 0),
		"size": 0.07, "cols": [[0.0, Color(1, 1, 1, 0)], [0.1, Color.WHITE], [1.0, Color(1, 1, 1, 0)]], "tint": true, "tint_white": 0.3, "tier": 1, "aabb": 3.0})
	light(r, mid, 2.0, 4.0, 0.15)
	save(r, "generic", "hit_sparks")
	# dash: horizontal speed ribbons behind (+Z) + streak sparks + dust
	r = begin(el, "dash", 0.7)
	# bold dash: a tapered speed cone behind the body (the readable silhouette), fat ribbons, streaks and dust
	mesh(r, "Cone", cyl(0.0, 0.5, 2.8, 14), fxmat("mix", el, P_col({"mesh_h": 2.8, "fade_y": Vector2(0.1, 0.55), "scroll": Vector3(0, 6.0, 0), "noise_scale": Vector3(3.0, 1.4, 3.0), "alpha_mul": 0.85, "intensity": 1.05, "soft_edge": 0.7, "noise_amt": 0.55})),
		Vector3(0, 0.9, 1.6), Vector3(90, 0, 0), Vector3(1.0, 0.35, 1.7),
		[A("scale", Vector3(1.0, 0.35, 1.7), Vector3(1.0, 1.0, 1.7), 0.0, 0.14, "out"), A("progress", 0.0, 1.0, 0.1, 0.55, "in")])
	for i in 5:
		var pts := PackedVector3Array()
		var y: float = [0.3, 0.7, 1.05, 1.4, 1.7][i]
		var zl: float = [2.2, 3.0, 3.4, 2.7, 2.0][i]
		var xo: float = [0.25, -0.2, 0.15, -0.1, 0.1][i]
		for k in 9:
			var t := float(k) / 8.0
			pts.append(Vector3(xo, y, lerpf(zl, 0.2, t)))
		mesh(r, "Ribbon%d" % i, K.path_mesh(pts, 0.3, Vector3.UP, true), fxmat("add", el, {"shape_mode": 3, "noise_amt": 0.3, "noise_scale": Vector3(4, 4, 4), "scroll": Vector3(-6, 0, 0),
			"tail_len": 0.9, "cel": 0.6, "intensity": 1.15, "alpha_mul": 0.95}), Vector3.ZERO, Vector3.ZERO, Vector3.ONE, [A("progress", 0.0, 1.0, 0.06 + i * 0.03, 0.5, "in")])
	ps(r, "Streaks", {"tex": "trace_02", "n": 14, "life": 0.4, "shape": "box", "ext": Vector3(0.35, 0.7, 0.1), "pos": Vector3(0, 0.95, 0.1), "dir": Vector3(0, 0, 1), "v": [5.0, 9.0], "spread": 6,
		"size": Vector2(0.11, 1.1), "stretch": true, "cols": [[0.0, Color(1, 1, 1, 0)], [0.1, Color(1, 1, 1, 0.95)], [1.0, Color(1, 1, 1, 0)]], "tint": true, "tint_white": 0.3, "aabb": 4.0})
	ps(r, "Dust", {"tex": "smoke_04", "blend": "mix", "n": 6, "life": 0.7, "shape": "box", "ext": Vector3(0.2, 0.02, 0.4), "pos": Vector3(0, 0.1, 0.3), "dir": Vector3(0, 0.4, 1), "v": [0.6, 1.5], "spread": 35,
		"size": 0.6, "spin": true, "curve": "grow", "cols": [[0.0, Color(0.85, 0.78, 0.65, 0.0)], [0.2, Color(0.85, 0.78, 0.65, 0.35)], [1.0, Color(0.85, 0.78, 0.65, 0.0)]], "tier": 1, "aabb": 3.0})
	save(r, "generic", "dash")
	# level up / awakening burst
	r = begin(el, "level_up", 2.4)
	mesh(r, "Pillar", cyl(1.0, 1.0, 6.0, 20), fxmat("add", el, P_col({"mesh_h": 6.0, "noise_amt": 0.5, "noise_scale": Vector3(2.0, 0.7, 2.0), "scroll": Vector3(0, -2.2, 0), "fade_y": Vector2(0.06, 0.5),
		"intensity": 0.8, "alpha_mul": 0.45, "heat_scale": 0.6})), Vector3(0, 3.0, 0), Vector3.ZERO, Vector3.ONE,
		[A("scale", Vector3(0.2, 1, 0.2), Vector3(1, 1, 1), 0.0, 0.45, "out"), A("progress", 0.0, 1.0, 1.3, 2.3)])
	mesh(r, "Ring", grd(3.0), fxmat("add", el, P_ring({"mesh_r": 3.0, "ring_w": 0.22, "intensity": 1.1})), Vector3(0, 0.05, 0), Vector3.ZERO, Vector3.ONE,
		[A("ring_r", 0.15, 0.92, 0.0, 0.8, "out"), A("progress", 0.0, 1.0, 0.5, 1.2)])
	mesh(r, "Ring2", grd(3.0), fxmat("add", el, P_ring({"mesh_r": 3.0, "ring_w": 0.12, "ticks": 16.0, "tick_amt": 0.7})), Vector3(0, 0.08, 0), Vector3.ZERO, Vector3.ONE,
		[A("ring_r", 0.1, 0.6, 0.15, 1.0, "out"), A("progress", 0.0, 1.0, 0.8, 1.6)])
	spr(r, "Rays", "effect_2", 4.5, Color(mid, 0.6), 0.9, Vector3(0, 1.1, 0), [A("scale", 0.3, 1.2, 0.0, 0.6, "out"), A("master", 1.0, 0.0, 0.9, 1.9)], 0.5)
	spr(r, "Star", "star_06", 3.0, Color(core, 1.0), 1.2, Vector3(0, 1.1, 0), [A("scale", 0.2, 1.4, 0.0, 0.3, "out"), A("master", 1.0, 0.0, 0.3, 0.9)])
	ps(r, "Motes", {"tex": "star_04", "n": 30, "life": 1.7, "shape": "ring", "radius": 1.3, "inner": 0.3, "v": [1.2, 3.0], "spread": 12, "grav": Vector3(0, 0.6, 0),
		"size": 0.22, "cols": [[0.0, Color(1, 1, 1, 0)], [0.15, Color.WHITE], [0.7, Color(1, 1, 1, 0.7)], [1.0, Color(1, 1, 1, 0)]], "tint": true, "tint_white": 0.25, "delay": 0.1, "aabb": 6.0, "curve": "mid", "spin": true})
	ps(r, "Sparks", {"tex": "circle_05", "n": 24, "life": 1.2, "shape": "sphere", "radius": 0.3, "pos": Vector3(0, 1.0, 0), "v": [2.0, 5.0], "spread": 180, "grav": Vector3(0, -1.5, 0), "damp": [0.5, 1.0],
		"size": 0.08, "cols": [[0.0, Color(1, 1, 1, 0)], [0.1, Color.WHITE], [1.0, Color(1, 1, 1, 0)]], "tint": true, "tint_white": 0.3, "tier": 1, "delay": 0.15, "aabb": 6.0})
	light(r, mid, 3.5, 8.0, 0.8, Vector3(0, 1.2, 0))
	save(r, "generic", "level_up")
