extends RefCounted
## ToonVfx: the shared VFX language (docs/research/VIDEO_STUDY_B2 #1, takeaways a + b).
##   * toon noise-threshold shell   shaders/vfx/toon_mask.gdshader   (swirling shield / aura / glow)
##   * 1 s ease-out ring + burst    shaders/vfx/toon_burst.gdshader  (ground rings, impact, parry, shockwave)
##   * cheap screen flash           shaders/vfx/screen_flash.gdshader
## Everything is pooled (a node is reused after its tween ends), unlit, one draw call per mesh, and coloured from
## ElementLanguage. Noise is one 128 px seamless texture baked at first use (no asset file).
##
##   ToonVfx.ring(parent, pos, element, radius, secs := 1.0)       flat ground ring, ease-out, noise-cut edge
##   ToonVfx.burst(parent, pos, element, radius, secs := 1.0)      ring(s) + shape-language particles
##   ToonVfx.shell(parent, element, radius, secs, node := null)    toon swirl shell at pos / glued to `node`
##   ToonVfx.glow_limb(node, element, size) -> MeshInstance3D      looping glow shell on a bone attachment; release()
##   ToonVfx.screen_flash(element, secs := 0.14, strength := 0.8)  full-screen radial flash (blur on HIGH tiers)
##   ToonVfx.release(node)                                         fade a looping node out and return it to the pool
##   ToonVfx.live_count()                                          active pooled nodes (tests / budgets)

const Lang := preload("res://scripts/vfx/element_language.gd")
const MASK_SHADER := preload("res://shaders/vfx/toon_mask.gdshader")
const BURST_SHADER := preload("res://shaders/vfx/toon_burst.gdshader")
const FLASH_SHADER := preload("res://shaders/vfx/screen_flash.gdshader")

const MAX_LIVE := 24                  ## active pooled meshes at once (rings + shells + limb glows)
const PARTICLE_TIER := [0.35, 0.6, 1.0, 1.0]
const NOISE_SIZE := 128

static var _noise: ImageTexture
static var _pool: Dictionary = {}     # kind -> Array[Node]
static var _live: Array = []
static var _quad: QuadMesh
static var _sphere: SphereMesh
static var _flash_node: Node
static var _pmats: Dictionary = {}


static func noise_tex() -> ImageTexture:
	if _noise == null:
		var n := FastNoiseLite.new()
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.frequency = 0.045
		n.fractal_type = FastNoiseLite.FRACTAL_FBM
		n.fractal_octaves = 3
		n.seed = 4711
		var img := n.get_seamless_image(NOISE_SIZE, NOISE_SIZE)
		img.convert(Image.FORMAT_L8)
		_noise = ImageTexture.create_from_image(img)
	return _noise


static func tier() -> int:
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		var q := (ml as SceneTree).root.get_node_or_null("Quality")
		if q:
			return int(q.get("tier"))
	return 2


static func live_count() -> int:
	_prune()
	return _live.size()


static func _prune() -> void:
	var keep: Array = []
	for n: Variant in _live:
		if is_instance_valid(n) and (n as Node).visible:
			keep.append(n)
	_live = keep


# --- pool -------------------------------------------------------------------------

static func _take(kind: String, parent: Node) -> MeshInstance3D:
	_prune()
	if _live.size() >= MAX_LIVE:
		var oldest: Variant = _live.pop_front()     # recycle the oldest rather than refuse (the newest effect matters)
		_free(oldest)
	var arr: Array = _pool.get(kind, [])
	var mi: MeshInstance3D = null
	while not arr.is_empty() and mi == null:
		var c: Variant = arr.pop_back()
		if is_instance_valid(c) and not (c as Node).is_queued_for_deletion():
			mi = c
	if mi == null:
		mi = MeshInstance3D.new()
		mi.mesh = _get_sphere() if kind == "shell" else _get_quad()
		mi.material_override = _new_mat(MASK_SHADER if kind == "shell" else BURST_SHADER)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.set_meta("kind", kind)
	_kill_tween(mi)
	if mi.get_parent() != parent:
		if mi.get_parent():
			mi.reparent(parent, false)
		else:
			parent.add_child(mi)
	mi.visible = true
	_live.append(mi)
	return mi


static func _free(n: Variant) -> void:
	if not is_instance_valid(n):
		return
	var mi := n as Node3D
	mi.visible = false
	_kill_tween(mi)
	_live.erase(mi)
	var kind := String(mi.get_meta("kind", "ring"))
	var arr: Array = _pool.get(kind, [])
	if arr.size() < 8:
		arr.append(mi)
		_pool[kind] = arr
	else:
		mi.queue_free()


static func _kill_tween(n: Node) -> void:
	if n.has_meta("tw"):
		var tw: Variant = n.get_meta("tw")
		if tw is Tween and (tw as Tween).is_valid():
			(tw as Tween).kill()


static func release(node: Node, fade := 0.2) -> void:
	if not is_instance_valid(node):
		return
	var mi := node as MeshInstance3D
	if mi == null or not mi.visible:
		return
	_kill_tween(mi)
	if not mi.is_inside_tree() or fade <= 0.0:
		_free(mi)
		return
	var mat := mi.material_override as ShaderMaterial
	var t := mi.create_tween()
	mi.set_meta("tw", t)
	t.tween_property(mat, "shader_parameter/fade", 0.0, fade)
	t.tween_callback(_free.bind(mi))


static func _get_quad() -> QuadMesh:
	if _quad == null:
		_quad = QuadMesh.new()
		_quad.size = Vector2(2, 2)
	return _quad


static func _get_sphere() -> SphereMesh:
	if _sphere == null:
		_sphere = SphereMesh.new()
		_sphere.radius = 1.0
		_sphere.height = 2.0
		_sphere.radial_segments = 14
		_sphere.rings = 8
	return _sphere


static func _new_mat(shader: Shader) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter("noise_tex", noise_tex())
	return m


static func _tint(m: ShaderMaterial, lang: Dictionary) -> void:
	m.set_shader_parameter("core_color", lang["core"])
	m.set_shader_parameter("mid_color", lang["mid"])
	m.set_shader_parameter("edge_color", lang["edge"])


# --- ring / burst -------------------------------------------------------------------

## A flat ground ring: ease-out growth over `secs` (default 1 s), thinning edge, fades over the last 45 percent.
static func ring(parent: Node, pos: Vector3, element: Variant, radius: float, secs := 1.0, delay := 0.0) -> MeshInstance3D:
	if parent == null or not parent.is_inside_tree():
		return null
	var lang := Lang.get_lang(element)
	var mi := _take("ring", parent)
	var mat := mi.material_override as ShaderMaterial
	_tint(mat, lang)
	mat.set_shader_parameter("progress", 0.0)
	mat.set_shader_parameter("fade", 1.0)
	mat.set_shader_parameter("energy", float(lang["glow"]) * 1.1)
	mat.set_shader_parameter("teeth", float(lang.get("stripes", 4)) + 2.0)
	mat.set_shader_parameter("seed", randf())
	mi.global_position = pos + Vector3(0, 0.04, 0)
	mi.global_basis = Basis(Vector3.RIGHT, -PI * 0.5).scaled(Vector3.ONE * maxf(radius, 0.1))
	mi.visible = delay <= 0.0
	var tw := mi.create_tween()
	mi.set_meta("tw", tw)
	if delay > 0.0:
		tw.tween_callback(func() -> void: mi.visible = true).set_delay(delay)
	tw.tween_property(mat, "shader_parameter/progress", 1.0, secs).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.parallel().tween_property(mat, "shader_parameter/fade", 0.0, secs * 0.45).set_delay(secs * 0.55)
	tw.tween_callback(_free.bind(mi))
	return mi


## Ring(s) plus the element's particle recipe at `pos` (ground point). The one-second burst preset.
static func burst(parent: Node, pos: Vector3, element: Variant, radius: float, secs := 1.0) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var lang := Lang.get_lang(element)
	var rings := int(lang.get("rings", 1))
	if tier() == 0:
		rings = 1
	for i in rings:
		ring(parent, pos, element, radius * (1.0 - 0.22 * i), secs, 0.07 * i)
	particles(parent, pos + Vector3(0, 0.15, 0), lang, radius)


static func _particle_mat(lang: Dictionary) -> StandardMaterial3D:
	var id := String(lang["id"])
	if _pmats.has(id):
		return _pmats[id]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color.WHITE
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if String(lang["shape"]) in ["chunks", "shards"]:
		m.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	else:
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.billboard_keep_scale = true
	_pmats[id] = m
	return m


static func _particle_mesh(lang: Dictionary) -> Mesh:
	match String(lang["shape"]):
		"chunks":
			var b := BoxMesh.new()
			b.size = Vector3(1, 0.7, 0.9)
			b.material = _particle_mat(lang)
			return b
		"shards":
			var p := PrismMesh.new()
			p.size = Vector3(0.6, 1.2, 0.6)
			p.material = _particle_mat(lang)
			return p
		"tongues", "forks":
			var q := QuadMesh.new()
			q.size = Vector2(0.5, 1.2)
			q.material = _particle_mat(lang)
			return q
	var q2 := QuadMesh.new()
	q2.size = Vector2(1, 1)
	q2.material = _particle_mat(lang)
	return q2


static func particles(parent: Node, pos: Vector3, lang: Dictionary, radius: float) -> CPUParticles3D:
	if parent == null or not parent.is_inside_tree():
		return null
	var spec: Dictionary = lang.get("burst", {})
	var count := maxi(2, int(round(float(spec.get("count", 8)) * float(PARTICLE_TIER[clampi(tier(), 0, 3)]))))
	var key := "p_" + String(lang["id"])
	var arr: Array = _pool.get(key, [])
	var p: CPUParticles3D = null
	while not arr.is_empty() and p == null:
		var c: Variant = arr.pop_back()
		if is_instance_valid(c) and not (c as Node).is_queued_for_deletion():
			p = c
	if p == null:
		p = CPUParticles3D.new()
		p.one_shot = true
		p.explosiveness = 0.9
		p.mesh = _particle_mesh(lang)
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		p.set_meta("key", key)
		p.finished.connect(_particles_done.bind(p))
	if p.get_parent() != parent:
		if p.get_parent():
			p.reparent(parent, false)
		else:
			parent.add_child(p)
	p.amount = count
	p.lifetime = float(spec.get("life", 0.8))
	p.global_position = pos
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = clampf(radius * 0.18, 0.1, 0.8)
	p.direction = Vector3.UP
	p.spread = 70.0
	var up := float(spec.get("up", 1.0))
	p.initial_velocity_min = up * 1.2
	p.initial_velocity_max = up * (2.6 + radius * 0.3)
	p.gravity = Vector3(0, -float(spec.get("grav", 2.0)), 0)
	var sz := float(spec.get("size", 0.12))
	p.scale_amount_min = sz * 1.2
	p.scale_amount_max = sz * 2.6
	var ramp := Gradient.new()
	ramp.set_color(0, lang["core"])
	ramp.set_color(1, Color((lang["edge"] as Color), 0.0))
	ramp.add_point(0.35, lang["mid"])
	p.color_ramp = ramp
	p.restart()
	p.emitting = true
	return p


static func _particles_done(p: CPUParticles3D) -> void:
	if not is_instance_valid(p):
		return
	var key := String(p.get_meta("key", "p_qi"))
	var arr: Array = _pool.get(key, [])
	if arr.size() < 4 and not arr.has(p):
		arr.append(p)
		_pool[key] = arr
	else:
		p.queue_free()


# --- shells / limb glow ---------------------------------------------------------------

static func _shell_setup(mi: MeshInstance3D, lang: Dictionary, radius: float, stretch := 1.0) -> ShaderMaterial:
	var mat := mi.material_override as ShaderMaterial
	_tint(mat, lang)
	mat.set_shader_parameter("threshold", float(lang["threshold"]))
	mat.set_shader_parameter("band", 0.06)
	mat.set_shader_parameter("stripes", float(lang["stripes"]))
	mat.set_shader_parameter("swirl", float(lang["swirl"]))
	mat.set_shader_parameter("spin", float(lang["spin"]))
	mat.set_shader_parameter("scroll", float(lang["scroll"]))
	mat.set_shader_parameter("energy", float(lang["glow"]) * 0.5)
	mat.set_shader_parameter("fade", 1.0)
	mat.set_shader_parameter("time_offset", randf() * 10.0)
	mi.scale = Vector3(radius, radius * stretch, radius)
	return mat


## Swirl shell round `pos` (or, with `node`, a child of it) that swells with an ease-out and loses its mask.
static func shell(parent: Node, element: Variant, radius: float, secs := 0.7, node: Node3D = null, pos := Vector3.ZERO, stretch := 1.0) -> MeshInstance3D:
	var host: Node = node if node != null else parent
	if host == null or not host.is_inside_tree():
		return null
	var lang := Lang.get_lang(element)
	var mi := _take("shell", host)
	var mat := _shell_setup(mi, lang, radius * 0.5, stretch)
	if node != null:
		mi.position = pos
	else:
		mi.global_position = pos
	var thr := float(lang["threshold"])
	mat.set_shader_parameter("threshold", thr - 0.1)
	var tw := mi.create_tween()
	mi.set_meta("tw", tw)
	tw.tween_property(mi, "scale", Vector3(radius, radius * stretch, radius), secs).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.parallel().tween_property(mat, "shader_parameter/threshold", thr + 0.22, secs)
	tw.parallel().tween_property(mat, "shader_parameter/fade", 0.0, secs * 0.4).set_delay(secs * 0.6)
	tw.tween_callback(_free.bind(mi))
	return mi


## Looping glow on a limb / body node (a BoneAttachment3D). Fades in; stop it with release().
static func glow_limb(node: Node3D, element: Variant, size := 0.2, path := "") -> MeshInstance3D:
	if node == null or not node.is_inside_tree():
		return null
	var lang := Lang.get_lang(element, path)
	var mi := _take("shell", node)
	var mat := _shell_setup(mi, lang, size * 0.6, 1.0 if String(lang["limb"]) != "body" else 1.6)
	mi.position = Vector3.ZERO
	mat.set_shader_parameter("fade", 0.0)
	mat.set_shader_parameter("threshold", float(lang["threshold"]) - 0.06)
	var tw := mi.create_tween()
	mi.set_meta("tw", tw)
	tw.tween_property(mi, "scale", Vector3(size, size * (1.0 if String(lang["limb"]) != "body" else 1.6), size), 0.18).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.parallel().tween_property(mat, "shader_parameter/fade", 1.0, 0.18)
	return mi


# --- screen flash ---------------------------------------------------------------------

static func screen_flash(element: Variant, secs := 0.14, strength := 0.8, center := Vector2(0.5, 0.5)) -> void:
	var ml := Engine.get_main_loop()
	if not (ml is SceneTree):
		return
	var tree := ml as SceneTree
	if tree.root == null:
		return
	var rect: ColorRect = null
	if is_instance_valid(_flash_node):
		rect = _flash_node.get_child(0) as ColorRect
	if rect == null:
		var layer := CanvasLayer.new()
		layer.name = "ToonScreenFlash"
		layer.layer = 40
		rect = ColorRect.new()
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		var m := ShaderMaterial.new()
		m.shader = FLASH_SHADER
		m.set_shader_parameter("noise_tex", noise_tex())
		rect.material = m
		layer.add_child(rect)
		tree.root.add_child(layer)
		_flash_node = layer
	var lang := Lang.get_lang(element)
	var mat := rect.material as ShaderMaterial
	mat.set_shader_parameter("flash_color", (lang["core"] as Color).lerp(lang["mid"], 0.25))
	mat.set_shader_parameter("center", center)
	mat.set_shader_parameter("amount", 0.0)
	mat.set_shader_parameter("blur", 0.18 if tier() >= 2 else 0.0)      # radial blur only where the screen copy is cheap
	rect.visible = true
	var tw := rect.create_tween()
	tw.tween_property(mat, "shader_parameter/amount", clampf(strength, 0.0, 1.0), secs * 0.25)
	tw.tween_property(mat, "shader_parameter/amount", 0.0, secs * 0.75).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_callback(func() -> void: rect.visible = false)
