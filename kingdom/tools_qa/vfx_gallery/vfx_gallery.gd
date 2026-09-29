extends Node3D
## VFX / shader gallery for the free (CC0 / MIT) effect assets in assets/incoming/vfx_free and shaders/free.
## Everything is built in code so the .tscn stays tiny. Not wired into gameplay; open the scene and press F6.
##
## Keys: 1 = effects row view, 2 = scenery view, K = painterly (Kuwahara) post, G = god rays, F = toggle fps label.
## Capture mode (used for docs/art/vfx_free screenshots + fps table):
##   Godot --path kingdom --rendering-method mobile res://tools_qa/vfx_gallery/vfx_gallery.tscn -- --capture=<absolute dir>
##
## Mobile notes: every emitter is a GPUParticles3D with 8-32 particles, one small billboard quad each,
## additive or alpha blended, 256-512 px textures. On the Compatibility renderer GPUParticles3D works too,
## but for the LOW tier swap to CPUParticles3D (`GPUParticles3D.convert_from_particles` -> `CPUParticles3D`
## via the editor "Convert to CPUParticles3D" menu) and keep amounts <= 12.

const K := "res://assets/incoming/vfx_free/kenney_particle_pack/"
const R := "res://assets/incoming/vfx_free/rpicster_vfx_textures/"
const GodRayScript := preload("res://assets/incoming/vfx_free/simplest_godray/simplest_god_ray_3d.gd")

var groups: Dictionary = {}          # name -> Node3D (toggle for the per-effect fps table)
var cam: Camera3D
var painterly: CanvasLayer
var fps_label: Label
var godrays: Array[Node3D] = []
var _view := 1
var _only := ""
var _row_count := 0
var effect_names: Array[String] = []
var scenery_names: Array[String] = []
var _capture_dir := ""
var _leaf_tex: ImageTexture

const ROW_Z := 0.0
const SCENE_Z := -18.0

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--capture="):
			_capture_dir = a.substr(10)
		if a.begins_with("--only="):
			_only = a.substr(7)
	_build_environment()
	_build_ground()
	_build_effects_row()
	_build_scenery()
	_build_ui()
	_set_view(1)
	if _capture_dir != "":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
		_run_capture.call_deferred()

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		match e.keycode:
			KEY_1: _set_view(1)
			KEY_2: _set_view(2)
			KEY_K: painterly.visible = not painterly.visible
			KEY_G:
				for g in godrays:
					g.visible = not g.visible
			KEY_F: fps_label.visible = not fps_label.visible

func _process(_d: float) -> void:
	fps_label.text = "%d fps | view %d | K painterly: %s | G god rays | 1/2 views" % [Engine.get_frames_per_second(), _view, "ON" if painterly.visible else "off"]

# ---------------------------------------------------------------- environment
func _build_environment() -> void:
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = _make_sky_shader()
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.70, 0.95)   # cool blue-violet fill
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.1
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.15
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.86, 0.66)
	sun.light_energy = 1.5
	sun.rotation_degrees = Vector3(-38, -35, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	add_child(sun)
	cam = Camera3D.new()
	cam.fov = 55.0
	add_child(cam)

func _make_sky_shader() -> Shader:
	return load("res://shaders/free/storybook_sky.gdshader")

func _build_ground() -> void:
	var m := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	m.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.24, 0.40, 0.17)
	mat.roughness = 1.0
	m.material_override = mat
	m.position = Vector3(0, 0, -6)
	add_child(m)

# ---------------------------------------------------------------- particle helpers
func _ramp(cols: Array, offs: Array = []) -> GradientTexture1D:
	var g := Gradient.new()
	g.colors = PackedColorArray(cols)
	if offs.is_empty():
		var o := PackedFloat32Array()
		for i in cols.size():
			o.append(float(i) / float(cols.size() - 1))
		g.offsets = o
	else:
		g.offsets = PackedFloat32Array(offs)
	var t := GradientTexture1D.new()
	t.gradient = g
	return t

func _emitter(parent: Node3D, tex_path: String, amount: int, life: float, ramp: GradientTexture1D, o: Dictionary) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.explosiveness = o.get("explosiveness", 0.0)
	p.randomness = 0.4
	p.local_coords = o.get("local", false)
	p.visibility_aabb = AABB(Vector3(-4, -1, -4), Vector3(8, 8, 8))
	var pm := ParticleProcessMaterial.new()
	pm.direction = o.get("dir", Vector3(0, 1, 0))
	pm.spread = o.get("spread", 15.0)
	pm.initial_velocity_min = o.get("v_min", 0.5)
	pm.initial_velocity_max = o.get("v_max", 1.0)
	pm.gravity = o.get("gravity", Vector3.ZERO)
	pm.scale_min = o.get("s_min", 0.5)
	pm.scale_max = o.get("s_max", 1.0)
	pm.color_ramp = ramp
	pm.angle_min = o.get("ang_min", 0.0)
	pm.angle_max = o.get("ang_max", 0.0)
	pm.damping_min = o.get("damp", 0.0)
	pm.damping_max = o.get("damp", 0.0)
	if o.has("box"):
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		pm.emission_box_extents = o["box"]
	elif o.has("sphere"):
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm.emission_sphere_radius = o["sphere"]
	elif o.has("ring"):
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
		pm.emission_ring_axis = Vector3(0, 0, 1)
		pm.emission_ring_radius = o["ring"]
		pm.emission_ring_inner_radius = o["ring"] * 0.85
		pm.emission_ring_height = 0.0
	if o.has("orbit"):
		pm.orbit_velocity_min = o["orbit"]
		pm.orbit_velocity_max = o["orbit"]
	if o.has("turb"):
		pm.turbulence_enabled = true
		pm.turbulence_noise_strength = o["turb"]
		pm.turbulence_influence_min = 0.05
		pm.turbulence_influence_max = 0.15
	if o.has("scale_curve"):
		var c := Curve.new()
		for pt in o["scale_curve"]:
			c.add_point(pt)
		var ct := CurveTexture.new()
		ct.curve = c
		pm.scale_curve = ct
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.vertex_color_use_as_albedo = true
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if o.get("additive", true) else BaseMaterial3D.BLEND_MODE_MIX
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = false
	mat.disable_receive_shadows = true
	mat.albedo_texture = o["tex_obj"] if o.has("tex_obj") else load(tex_path)
	mat.billboard_keep_scale = true
	mat.particles_anim_h_frames = 1
	mat.particles_anim_v_frames = 1
	q.material = mat
	p.draw_pass_1 = q
	parent.add_child(p)
	return p

func _group(name_: String, x: float, z: float = ROW_Z) -> Node3D:
	var n := Node3D.new()
	n.name = name_
	if z == ROW_Z:
		var idx := _row_count
		_row_count += 1
		n.position = Vector3((idx % 5 - 2) * 2.4, 0, 1.2 - (idx / 5) * 3.4)
		effect_names.append(name_)
	else:
		n.position = Vector3(x, 0, z)
		scenery_names.append(name_)
	add_child(n)
	groups[name_] = n
	var l := Label3D.new()
	l.text = name_
	l.font_size = 40
	l.pixel_size = 0.0045
	l.position = Vector3(0, 0.05, 0.9)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED

	l.modulate = Color(1, 1, 1, 0.9)
	l.outline_size = 12
	l.no_depth_test = false
	n.add_child(l)
	return n

# ---------------------------------------------------------------- effects row
func _build_effects_row() -> void:
	var x := -10.8
	var step := 2.7
	# 1 campfire: logs + flame + embers + smoke + flickering light
	var g := _group("campfire", x)
	x += step
	for i in 3:
		var log_ := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.07; cm.bottom_radius = 0.07; cm.height = 0.7
		log_.mesh = cm
		var lm := StandardMaterial3D.new()
		lm.albedo_color = Color(0.36, 0.22, 0.12)
		log_.material_override = lm
		log_.position = Vector3(0, 0.08, 0)
		log_.rotation_degrees = Vector3(80, i * 60.0, 90)
		g.add_child(log_)
	var fire_ramp := _ramp([Color(1, 0.95, 0.6, 0.0), Color(1, 0.85, 0.35, 0.9), Color(1, 0.45, 0.1, 0.7), Color(0.8, 0.15, 0.05, 0.0)], [0.0, 0.15, 0.6, 1.0])
	var fl := _emitter(g, K + "flame_05.png", 14, 0.9, fire_ramp, {"dir": Vector3(0, 1, 0), "spread": 8.0, "v_min": 0.5, "v_max": 0.9, "s_min": 1.0, "s_max": 1.5, "sphere": 0.12, "scale_curve": [Vector2(0, 0.6), Vector2(0.3, 1.0), Vector2(1, 0.2)]})
	fl.position = Vector3(0, 0.25, 0)
	var em_ramp := _ramp([Color(1, 0.9, 0.5, 1), Color(1, 0.4, 0.1, 0.8), Color(1, 0.2, 0.05, 0)])
	var em := _emitter(g, K + "circle_05.png", 8, 1.4, em_ramp, {"dir": Vector3(0, 1, 0), "spread": 25.0, "v_min": 0.8, "v_max": 1.8, "s_min": 0.12, "s_max": 0.22, "gravity": Vector3(0, 0.3, 0), "sphere": 0.1, "turb": 1.0})
	em.position = Vector3(0, 0.4, 0)
	var sm_ramp := _ramp([Color(0.35, 0.33, 0.4, 0.0), Color(0.5, 0.48, 0.55, 0.35), Color(0.7, 0.72, 0.8, 0.0)], [0.0, 0.25, 1.0])
	var sm := _emitter(g, K + "smoke_04.png", 10, 3.0, sm_ramp, {"additive": false, "dir": Vector3(0, 1, 0), "spread": 10.0, "v_min": 0.5, "v_max": 0.8, "s_min": 0.6, "s_max": 1.0, "ang_min": -90, "ang_max": 90, "gravity": Vector3(0.15, 0.1, 0), "scale_curve": [Vector2(0, 0.3), Vector2(1, 1.8)]})
	sm.position = Vector3(0, 1.0, 0)
	var lt := OmniLight3D.new()
	lt.light_color = Color(1, 0.6, 0.25)
	lt.omni_range = 5.0
	lt.position = Vector3(0, 0.7, 0)
	lt.name = "FlickerLight"
	lt.set_script(_flicker_script())
	g.add_child(lt)

	# 2-4 magic sparks in three colours
	for spec in [["magic sparks purple", Color(0.75, 0.4, 1.0)], ["magic sparks cyan", Color(0.3, 0.9, 1.0)], ["magic sparks gold", Color(1.0, 0.85, 0.3)]]:
		var gm := _group(spec[0], x)
		x += step
		var c: Color = spec[1]
		var r := _ramp([Color(c.r, c.g, c.b, 0), c.lightened(0.5), Color(c.r, c.g, c.b, 0.8), Color(c.r, c.g, c.b, 0)], [0.0, 0.12, 0.5, 1.0])
		var sp := _emitter(gm, K + "star_04.png", 20, 1.6, r, {"additive": false, "dir": Vector3(0, 1, 0), "spread": 180.0, "v_min": 0.2, "v_max": 0.8, "s_min": 0.35, "s_max": 0.65, "sphere": 0.35, "gravity": Vector3(0, 0.25, 0), "turb": 1.5, "ang_min": -180, "ang_max": 180})
		sp.position = Vector3(0, 0.9, 0)
		var glow := _emitter(gm, R + "effect_1.png", 3, 2.0, _ramp([Color(c.r, c.g, c.b, 0), Color(c.r, c.g, c.b, 0.35), Color(c.r, c.g, c.b, 0)]), {"dir": Vector3(0, 0, 0), "spread": 0.0, "v_min": 0.0, "v_max": 0.0, "s_min": 1.3, "s_max": 1.6})
		glow.position = Vector3(0, 0.9, 0)

	# 5 portal swirl
	var gp := _group("portal swirl", x)
	x += step
	var portal := Node3D.new()
	portal.position = Vector3(0, 1.3, 0)
	gp.add_child(portal)
	var disc := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(2.0, 2.0)
	disc.mesh = qm
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.albedo_texture = load(K + "twirl_03.png")
	dm.albedo_color = Color(0.55, 0.3, 1.0, 1.0)
	dm.cull_mode = BaseMaterial3D.CULL_DISABLED
	disc.material_override = dm
	disc.set_script(_spin_script())
	portal.add_child(disc)
	var disc2 := disc.duplicate()
	var dm2 := dm.duplicate() as StandardMaterial3D
	dm2.albedo_texture = load(K + "twirl_01.png")
	dm2.albedo_color = Color(1.0, 0.6, 1.0, 0.8)
	disc2.material_override = dm2
	disc2.set("speed", -1.6)
	disc2.scale = Vector3(0.7, 0.7, 0.7)
	disc2.position = Vector3(0, 0, 0.02)
	portal.add_child(disc2)
	var pr := _emitter(portal, K + "star_04.png", 24, 1.4, _ramp([Color(0.6, 0.5, 1, 0), Color(0.9, 0.8, 1, 1), Color(0.6, 0.4, 1, 0)]), {"dir": Vector3(0, 0, 1), "spread": 30.0, "v_min": 0.2, "v_max": 0.5, "s_min": 0.22, "s_max": 0.4, "ring": 0.95, "orbit": 0.15, "local": true})

	# 6 hit sparks (bursts)
	var gh := _group("hit sparks", x)
	x += step
	var hr := _ramp([Color(1, 1, 0.8, 1), Color(1, 0.7, 0.2, 1), Color(1, 0.3, 0.05, 0)], [0.0, 0.35, 1.0])
	var hs := _emitter(gh, K + "star_06.png", 18, 0.55, hr, {"explosiveness": 1.0, "dir": Vector3(0, 1, 0), "spread": 180.0, "v_min": 2.0, "v_max": 4.5, "s_min": 0.4, "s_max": 0.75, "gravity": Vector3(0, -6, 0), "damp": 1.5, "ang_min": -180, "ang_max": 180})
	hs.position = Vector3(0, 0.8, 0)
	var flash := _emitter(gh, K + "flare_01.png", 1, 0.55, _ramp([Color(1, 0.9, 0.6, 0.9), Color(1, 0.5, 0.2, 0)]), {"explosiveness": 1.0, "v_min": 0.0, "v_max": 0.0, "spread": 0.0, "s_min": 1.0, "s_max": 1.0, "scale_curve": [Vector2(0, 0.4), Vector2(1, 1.3)]})
	flash.position = Vector3(0, 0.8, 0)

	# 7 dust puff
	var gd := _group("dust puff", x)
	x += step
	var dr := _ramp([Color(0.85, 0.72, 0.5, 0.0), Color(0.85, 0.72, 0.5, 0.55), Color(0.8, 0.7, 0.55, 0.0)], [0.0, 0.2, 1.0])
	var dp := _emitter(gd, K + "smoke_07.png", 10, 1.6, dr, {"additive": false, "explosiveness": 0.9, "dir": Vector3(0, 1, 0), "spread": 70.0, "v_min": 0.6, "v_max": 1.4, "s_min": 0.7, "s_max": 1.1, "damp": 1.8, "gravity": Vector3(0, 0.05, 0), "ang_min": -90, "ang_max": 90, "scale_curve": [Vector2(0, 0.4), Vector2(1, 1.6)], "sphere": 0.15})
	dp.position = Vector3(0, 0.15, 0)

	# 8 falling leaves
	var gl := _group("falling leaves", x)
	x += step
	var lr := _ramp([Color(0.55, 0.75, 0.2, 1), Color(0.85, 0.7, 0.2, 1), Color(0.8, 0.4, 0.15, 1), Color(0.8, 0.4, 0.15, 0)], [0.0, 0.4, 0.8, 1.0])
	# CPUParticles3D on purpose: this is also the Compatibility / LOW-tier fallback pattern.
	var lp := CPUParticles3D.new()
	lp.amount = 12
	lp.lifetime = 5.0
	lp.local_coords = false
	lp.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	lp.emission_box_extents = Vector3(0.9, 0.05, 0.9)
	lp.direction = Vector3(0.3, -1, 0)
	lp.spread = 20.0
	lp.initial_velocity_min = 0.2
	lp.initial_velocity_max = 0.5
	lp.gravity = Vector3(0.15, -0.25, 0)
	lp.damping_min = 0.6
	lp.damping_max = 0.6
	lp.angle_min = -180.0
	lp.angle_max = 180.0
	lp.angular_velocity_min = -120.0
	lp.angular_velocity_max = 120.0
	lp.scale_amount_min = 0.22
	lp.scale_amount_max = 0.32
	lp.color_ramp = lr.gradient
	var lq := QuadMesh.new()
	lq.size = Vector2(1, 1)
	var lmat := StandardMaterial3D.new()
	lmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	lmat.billboard_keep_scale = true
	lmat.particles_anim_h_frames = 1
	lmat.particles_anim_v_frames = 1
	lmat.vertex_color_use_as_albedo = true
	lmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	lmat.albedo_texture = _leaf_texture()
	lq.material = lmat
	lp.mesh = lq
	gl.add_child(lp)
	lp.position = Vector3(0, 2.6, 0)

	# 9 fireflies
	var gf := _group("fireflies", x)
	x += step
	var fr := _ramp([Color(0.8, 1, 0.3, 0), Color(0.9, 1, 0.4, 1), Color(0.8, 1, 0.3, 0)])
	var ff := _emitter(gf, K + "circle_05.png", 14, 4.0, fr, {"box": Vector3(1.0, 0.6, 1.0), "dir": Vector3(0, 1, 0), "spread": 180.0, "v_min": 0.05, "v_max": 0.2, "s_min": 0.22, "s_max": 0.34, "turb": 2.0})
	ff.position = Vector3(0, 1.0, 0)

func _leaf_texture() -> ImageTexture:
	if _leaf_tex:
		return _leaf_tex
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var u := (x - 15.5) / 15.5
			var v := (y - 15.5) / 15.5
			var a := 1.0 if (u * u / 0.35 + v * v / 1.0 < 0.9) else 0.0
			if abs(u) < 0.05 and abs(v) < 0.9:
				a = 1.0
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_leaf_tex = ImageTexture.create_from_image(img)
	return _leaf_tex

func _flicker_script() -> GDScript:
	var s := GDScript.new()
	s.source_code = "extends OmniLight3D\nvar t := randf() * 10.0\nfunc _process(d: float) -> void:\n\tt += d\n\tlight_energy = 1.6 + sin(t * 17.0) * 0.25 + sin(t * 7.3) * 0.3\n"
	s.reload()
	return s

func _spin_script() -> GDScript:
	var s := GDScript.new()
	s.source_code = "extends MeshInstance3D\nvar speed := 1.2\nfunc _process(d: float) -> void:\n\trotate_z(speed * d)\n"
	s.reload()
	return s

# ---------------------------------------------------------------- scenery
func _noise_tex(freq: float, seed_: int, size: int = 128) -> ImageTexture:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	n.seed = seed_
	n.fractal_octaves = 3
	var img := n.get_image(size, size, false, false, false)
	img.convert(Image.FORMAT_RGBA8)
	return ImageTexture.create_from_image(img)

func _build_scenery() -> void:
	# --- grass patch
	var gg := _group("stylized grass", -6.0, SCENE_Z)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var blade := QuadMesh.new()
	blade.size = Vector2(0.14, 0.55)
	blade.center_offset = Vector3(0, 0.275, 0)
	var gmat := ShaderMaterial.new()
	gmat.shader = load("res://shaders/free/stylized_grass.gdshader")
	blade.material = gmat
	mm.mesh = blade
	mm.instance_count = 1800
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in mm.instance_count:
		var t := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.7, 1.4)), Vector3(rng.randf_range(-3, 3), 0, rng.randf_range(-2.5, 2.5)))
		mm.set_instance_transform(i, t)
	var gi := MultiMeshInstance3D.new()
	gi.multimesh = mm
	gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gg.add_child(gi)
	# daisies: few white dots
	var dm := MultiMesh.new()
	dm.transform_format = MultiMesh.TRANSFORM_3D
	var ds := SphereMesh.new()
	ds.radius = 0.04; ds.height = 0.05; ds.radial_segments = 6; ds.rings = 3
	var dmat := StandardMaterial3D.new()
	dmat.albedo_color = Color(1, 0.98, 0.85)
	dmat.emission_enabled = true
	dmat.emission = Color(1, 0.95, 0.6)
	dmat.emission_energy_multiplier = 0.3
	ds.material = dmat
	dm.mesh = ds
	dm.instance_count = 60
	for i in 60:
		dm.set_instance_transform(i, Transform3D(Basis(), Vector3(rng.randf_range(-3, 3), 0.42, rng.randf_range(-2.5, 2.5))))
	var di := MultiMeshInstance3D.new()
	di.multimesh = dm
	gg.add_child(di)

	# --- fluffy tree
	var gt := _group("fluffy tree", 0.5, SCENE_Z)
	var trunk := MeshInstance3D.new()
	var tc := CylinderMesh.new()
	tc.top_radius = 0.16; tc.bottom_radius = 0.26; tc.height = 2.2
	trunk.mesh = tc
	var tm := StandardMaterial3D.new()
	tm.albedo_color = Color(0.45, 0.3, 0.18)
	trunk.material_override = tm
	trunk.position = Vector3(0, 1.1, 0)
	gt.add_child(trunk)
	var lmat := ShaderMaterial.new()
	lmat.shader = load("res://shaders/free/fluffy_leaves.gdshader")
	lmat.set_shader_parameter("leaf_mask", _noise_tex(0.06, 3))
	for c in [[Vector3(0, 3.0, 0), 1.5], [Vector3(-1.0, 2.6, 0.3), 1.0], [Vector3(1.0, 2.7, -0.2), 1.05], [Vector3(0.2, 3.9, 0.1), 0.95], [Vector3(0.1, 2.5, 1.0), 0.85]]:
		var s := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = c[1]; sm.height = c[1] * 2.0; sm.radial_segments = 20; sm.rings = 10
		s.mesh = sm
		s.material_override = lmat
		s.position = c[0]
		gt.add_child(s)

	# --- water
	var gw := _group("stylized water", 7.5, SCENE_Z)
	var w := MeshInstance3D.new()
	var wm := PlaneMesh.new()
	wm.size = Vector2(6, 5)
	wm.subdivide_width = 24
	wm.subdivide_depth = 20
	w.mesh = wm
	var wmat := ShaderMaterial.new()
	wmat.shader = load("res://shaders/free/stylized_water.gdshader")
	w.material_override = wmat
	w.position = Vector3(0, 0.12, 0)
	gw.add_child(w)
	for i in 6:
		var rk := MeshInstance3D.new()
		var rs := SphereMesh.new()
		rs.radius = 0.25 + 0.1 * (i % 3); rs.height = rs.radius * 1.4; rs.radial_segments = 8; rs.rings = 4
		rk.mesh = rs
		var rm := StandardMaterial3D.new()
		rm.albedo_color = Color(0.7, 0.66, 0.6)
		rk.material_override = rm
		rk.position = Vector3(-3.0 + i * 1.0 + (i % 2) * 0.2, 0.08, 2.6 if i % 2 == 0 else -2.6)
		gw.add_child(rk)

	# --- god rays (MIT SimplestGodRay3D)
	var gr := _group("god rays", 0.5, SCENE_Z)
	for i in 3:
		var ray := Node3D.new()
		ray.set_script(GodRayScript)
		ray.set("width", 0.9)
		ray.set("height", 5.5)
		ray.set("spread", 1.8)
		ray.set("intensity", 0.35)
		ray.set("transparency", 0.35)
		ray.set("fade_distance", 1.6)
		ray.position = Vector3(-1.5 + i * 1.6, 5.6, 1.0 - i * 0.4)
		ray.rotation_degrees = Vector3(0, 0, 18 + i * 3)
		gr.add_child(ray)
		godrays.append(ray)
	# make the ray quad pivot at the top: quad is centred, so leave it (looks like a shaft from the canopy)

func _build_ui() -> void:
	var cl := CanvasLayer.new()
	cl.layer = 5
	add_child(cl)
	fps_label = Label.new()
	fps_label.position = Vector2(12, 8)
	fps_label.add_theme_font_size_override("font_size", 20)
	fps_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	fps_label.add_theme_constant_override("outline_size", 6)
	cl.add_child(fps_label)
	painterly = CanvasLayer.new()
	painterly.layer = 1
	painterly.visible = false
	add_child(painterly)
	var cr := ColorRect.new()
	cr.set_anchors_preset(Control.PRESET_FULL_RECT)
	cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var km := ShaderMaterial.new()
	km.shader = load("res://shaders/free/kuwahara_post.gdshader")
	cr.material = km
	painterly.add_child(cr)

func _set_view(v: int) -> void:
	_view = v
	for k in groups:
		groups[k].visible = (v == 1) == effect_names.has(k)
	if v == 1:
		cam.position = Vector3(0, 3.2, 7.0)
		cam.look_at(Vector3(0, 0.9, -0.4))
		cam.fov = 60.0
	else:
		cam.position = Vector3(1.0, 3.0, SCENE_Z + 11.0)
		cam.look_at(Vector3(1.0, 2.0, SCENE_Z))
		cam.fov = 62.0

# ---------------------------------------------------------------- capture + fps
func _shot(name_: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_capture_dir.path_join(name_ + ".png"))

func _measure(frames: int = 240) -> Dictionary:
	# CPU = wall-clock ms per frame, GPU = RenderingServer measured render time of the main viewport.
	var vp := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	for i in 30:
		await get_tree().process_frame
	var t0 := Time.get_ticks_usec()
	var gpu := 0.0
	var cpu := 0.0
	for i in frames:
		await get_tree().process_frame
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp)
	var dt := (Time.get_ticks_usec() - t0) / 1000.0 / frames
	return {"frame": dt, "gpu": gpu / frames, "cpu": cpu / frames}

func _fmt(label: String, m: Dictionary, base: Dictionary = {}) -> String:
	var s := "%s | frame %.2f ms (%.0f fps) | GPU %.2f ms | render-CPU %.2f ms" % [label, m["frame"], 1000.0 / m["frame"], m["gpu"], m["cpu"]]
	if not base.is_empty():
		s += " | GPU delta %+.2f ms" % (m["gpu"] - base["gpu"])
	return s

func _set_only(names: Array) -> void:
	for k in groups:
		groups[k].visible = names.has(k)

func _run_capture() -> void:
	DirAccess.make_dir_recursive_absolute(_capture_dir)
	var lines: PackedStringArray = []
	lines.append("renderer=%s adapter=%s window=%s" % [RenderingServer.get_current_rendering_method(), RenderingServer.get_video_adapter_name(), get_window().size])
	await get_tree().create_timer(3.0).timeout
	if _only != "":
		_set_view(1 if effect_names.has(_only) else 2)
		_set_only([_only])
		await get_tree().create_timer(2.0).timeout
		await _shot("only_" + _only.replace(" ", "_"))
		get_tree().quit()
		return
	for view in [1, 2]:
		_set_view(view)
		for g in godrays:
			g.visible = true
		for p in [false, true]:
			painterly.visible = p
			await get_tree().create_timer(1.5).timeout
			await _shot("view%d_%s" % [view, "painterly" if p else "plain"])
	painterly.visible = false
	for g in godrays:
		g.visible = false
	await get_tree().create_timer(0.5).timeout
	await _shot("view2_no_godrays")
	for g in godrays:
		g.visible = true
	lines.append("Per-effect cost. 240 frames each, vsync off, 1280x720, project autoloads running (frame time includes them; GPU column is the effect cost).")
	# effects row
	_set_view(1)
	_set_only([])
	var base1 := await _measure()
	lines.append(_fmt("view1 baseline (sky + ground only)", base1))
	for k in effect_names:
		_set_only([k])
		lines.append(_fmt(k + " alone", await _measure(), base1))
	_set_only(effect_names)
	lines.append(_fmt("view1 ALL 9 effects", await _measure(), base1))
	painterly.visible = true
	lines.append(_fmt("view1 ALL 9 effects + painterly Kuwahara r=2", await _measure(), base1))
	painterly.visible = false
	# scenery
	_set_view(2)
	_set_only([])
	var base2 := await _measure()
	lines.append(_fmt("view2 baseline (sky + ground only)", base2))
	for k in scenery_names:
		_set_only([k])
		lines.append(_fmt(k + " alone", await _measure(), base2))
	_set_only(scenery_names)
	lines.append(_fmt("view2 ALL scenery", await _measure(), base2))
	painterly.visible = true
	lines.append(_fmt("view2 ALL scenery + painterly Kuwahara r=2", await _measure(), base2))
	var f := FileAccess.open(_capture_dir.path_join("fps.txt"), FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	print("\n".join(lines))
	get_tree().quit()
