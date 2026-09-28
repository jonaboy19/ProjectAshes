extends RefCounted
## Martial arts: smear slash arcs, screen-space impact frames, dash afterimages,
## qi aura flames and the heal glow. Called through VFX (scripts/vfx/vfx.gd).

const K := preload("res://scripts/vfx/vfx_kit.gd")
const Spells := preload("res://scripts/vfx/vfx_spells.gd")


## Brush-stroke crescent that sweeps in 0.12 s, leaves a smear tail and burns away.
## `tilt` rolls the arc (0 = horizontal, ±1.2 = diagonal). `p` is a palette dictionary.
static func slash_arc(parent: Node, pos: Vector3, yaw: float, tilt: float, p: Dictionary, radius := 1.6, sweep := 0.12) -> void:
	var root := Node3D.new()
	K.add(parent, root, pos)
	root.rotation = Vector3(0, yaw, tilt)
	for k in 2:
		var r := radius * (1.0 - k * 0.12)
		var m := K.fx_mat(K.SMEAR, p, 2.4 + k * 1.6, {"tail": 0.75 - k * 0.3, "noise_amt": 0.45, "speed": 2.5})
		var mi := K.mesh_node(root, K.arc_mesh(r, 165.0, 0.5 - k * 0.3), m, pos)
		mi.rotation = Vector3.ZERO
		K.anim(mi, m, "progress", 0.0, 1.0, sweep, 0.0, Tween.EASE_OUT, Tween.TRANS_CUBIC)
		K.anim(mi, m, "dissolve", 0.0, 1.0, 0.22, sweep * 0.8, Tween.EASE_IN)
	# Sparks peeling off the leading tip at the end of the swing.
	var arc := deg_to_rad(165.0)
	var tip := root.global_transform * (Vector3(sin(arc * 0.5), 0, cos(arc * 0.5)) * radius)
	K.emit(parent, tip, {"amount": 10, "life": 0.35, "v": Vector2(2.0, 6.0), "spread": 60.0,
		"dir": (root.global_basis * Vector3(1, 0, -0.2)).normalized(), "gravity": Vector3(0, -6, 0),
		"size": Vector2(0.04, 0.28), "stretch": true, "delay": sweep * 0.7, "mat": K.sprite_mat(K.DOT, p, 4.0, {"heat": 1.4})})
	K.free_after(root, sweep + 0.5)


## A brief manga-style burst of radial speed lines centred on the hit in screen space.
static func impact_frame(parent: Node, at: Vector3, strength := 1.0, seconds := 0.12, color := Color(1.0, 0.96, 0.88)) -> void:
	var vp := parent.get_viewport()
	if vp == null:
		return
	var layer := CanvasLayer.new()
	layer.layer = 40
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := K.shader_mat(K.IMPACT)
	m.set_shader_parameter("noise_tex", K.NOISE)
	m.set_shader_parameter("tint", color)
	m.set_shader_parameter("strength", strength)
	m.set_shader_parameter("seed", randf())
	var size := vp.get_visible_rect().size
	m.set_shader_parameter("aspect", size.x / maxf(size.y, 1.0))
	var cam := vp.get_camera_3d()
	if cam and not cam.is_position_behind(at):
		m.set_shader_parameter("center", cam.unproject_position(at) / size)
	rect.material = m
	layer.add_child(rect)
	parent.add_child(layer)
	var tw := layer.create_tween()
	tw.tween_property(m, "shader_parameter/progress", 1.0, seconds).from(0.0)
	tw.tween_callback(layer.queue_free)


## Ghost copies of `character`'s meshes left behind every `interval` s, fading out.
static func afterimage(parent: Node, character: Node3D, color := Color(0.45, 0.8, 1.0), count := 4, interval := 0.05, life := 0.35) -> void:
	if K.lite():
		count = mini(count, 2)
	var tw := character.create_tween()
	for i in count:
		tw.tween_callback(ghost.bind(parent, character, color, life))
		tw.tween_interval(interval)


## One frozen, fading silhouette of `character` in its current pose.
static func ghost(parent: Node, character: Node3D, color := Color(0.45, 0.8, 1.0), life := 0.35) -> void:
	if not is_instance_valid(character) or not character.is_inside_tree():
		return
	var m := K.shader_mat(K.GHOST)
	m.set_shader_parameter("tint", color)
	m.set_shader_parameter("hot", color.lerp(Color.WHITE, 0.7))
	var root := Node3D.new()
	parent.add_child(root)
	for node in character.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if not mi.is_visible_in_tree() or mi.mesh == null or mi.material_override is ShaderMaterial and (mi.material_override as ShaderMaterial).shader == K.GHOST:
			continue
		var mesh: Mesh = mi.mesh
		if mi.skin != null and not mi.skeleton.is_empty():
			mesh = mi.bake_mesh_from_current_skeleton_pose()
		var g := MeshInstance3D.new()
		g.mesh = mesh
		g.material_override = m
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(g)
		g.global_transform = mi.global_transform
	var tw := root.create_tween()
	tw.tween_property(m, "shader_parameter/fade", 0.0, life).from(1.0).set_ease(Tween.EASE_IN)
	tw.tween_callback(root.queue_free)


## Looping qi flames around a character (power-up, cultivation, martial stance).
## Returns the container; pass it to VFX.stop() to fade it out.
static func qi_flames(node: Node3D, p: Dictionary, height := 1.8) -> Node3D:
	var root := Node3D.new()
	root.name = "QiFlames"
	node.add_child(root)
	K.emit(root, root.global_position + Vector3(0, 0.1, 0), {"amount": 26, "life": 0.8, "one_shot": false, "local": true,
		"shape": "ring", "radius": 0.6, "inner": 0.4, "v": Vector2(height * 1.0, height * 1.5), "spread": 6.0,
		"damping": Vector2(0.5, 1.0), "size": Vector2(0.9, 1.4), "scale": Vector2(0.7, 1.0), "alpha": "inout", "grow": "pop",
		"mat": K.sprite_mat(K.BLOB, p, 1.8, {"distort": 0.3, "cool": 0.8, "heat": 0.95})})
	K.emit(root, root.global_position + Vector3(0, 0.9, 0), {"amount": 6, "life": 0.9, "one_shot": false, "local": true,
		"v": Vector2(0.1, 0.3), "spread": 180.0, "size": height * 1.1, "grow": "pop", "alpha": "inout",
		"mat": K.sprite_mat(K.DOT, p, 0.8, {"cool": 0.2})})
	K.emit(root, root.global_position + Vector3(0, 0.2, 0), {"amount": 14, "life": 1.2, "one_shot": false, "local": true,
		"shape": "ring", "radius": 0.6, "inner": 0.3, "v": Vector2(height * 0.6, height * 1.1), "spread": 10.0,
		"size": Vector2(0.04, 0.4), "stretch": true, "alpha": "inout", "mat": K.sprite_mat(K.DOT, p, 4.0, {"heat": 1.4})})
	var rm := K.fx_mat(K.GROUND_RING, p, 2.0, {"progress": 0.6, "width": 0.4, "noise_amt": 0.25, "speed": 1.5})
	var ring := K.ground(root, root.global_position, rm, 2.2)
	K.anim(ring, rm, "fade", 0.0, 1.0, 0.3)
	return root


## Soft rising green-gold glow with a rune ring and sparkles.
static func heal(parent: Node, pos: Vector3, power := 1.0) -> void:
	var p := K.pal("heal")
	Spells.magic_circle(parent, pos, "heal", 1.2 * power, 1.4)
	var c := CylinderMesh.new()
	c.top_radius = 0.7 * power
	c.bottom_radius = 0.6 * power
	c.height = 2.4
	c.cap_top = false
	c.cap_bottom = false
	c.radial_segments = 16
	var m := K.fx_mat(K.COLUMN, p, 1.4, {"speed": 0.8, "noise_amt": 0.3})
	var col := K.mesh_node(parent, c, m, pos + Vector3(0, 1.2, 0))
	K.anim(col, m, "fade", 0.0, 1.0, 0.25)
	K.anim(col, m, "dissolve", 0.0, 1.0, 0.5, 0.8)
	K.free_after(col, 1.35)
	K.emit(parent, pos + Vector3(0, 0.2, 0), {"amount": 22, "life": 1.3, "shape": "disc", "radius": 0.7 * power, "explosive": 0.3,
		"v": Vector2(0.8, 2.0), "spread": 10.0, "size": 0.3, "spin": true, "alpha": "inout", "grow": "pop",
		"mat": K.sprite_mat(K.SPARKLE, p, 3.5, {"spin": true, "heat": 1.2})})
	K.emit(parent, pos + Vector3(0, 0.2, 0), {"amount": 16, "life": 1.1, "shape": "disc", "radius": 0.6 * power, "explosive": 0.4,
		"v": Vector2(1.0, 2.5), "spread": 5.0, "size": Vector2(0.05, 0.35), "stretch": true, "alpha": "inout",
		"mat": K.sprite_mat(K.DOT, p, 4.0, {"heat": 1.3})})
	K.glow(parent, pos + Vector3(0, 1.0, 0), p, 2.2 * power, 0.8, K.DOT, 2.0)
	K.light(parent, pos + Vector3(0, 1.0, 0), p["tint"], 1.5, 1.0, 5.0)
