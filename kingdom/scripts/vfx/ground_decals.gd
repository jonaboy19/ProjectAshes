extends RefCounted
## GroundDecals: pooled, fading ground marks for technique residue - scorch, frost, cracks, dust, footprints, splash.
## Textures are drawn once in code (96 px, noise-threshold hard edges to match the toon VFX; no asset files).
##
##   GroundDecals.spawn(parent, "scorch", pos, size := 2.0, life := 6.0, yaw := 0.0) -> Node3D
##   GroundDecals.for_element("fire") -> "scorch"      (the element table's decal kind)
##   GroundDecals.active_count() / cap()
##
## Budget: at most cap() decals alive (LOW 6, MEDIUM 10, HIGH+ 14); the oldest is recycled when full. Mobile and
## Forward+ renderers use a real Decal node (note the Mobile renderer's 8 decals per mesh: keep sizes modest, they
## fade out in `life`); the Compatibility renderer (LOW phones) and LOW tier use a projected quad, a flat unlit
## alpha quad just above the ground, which needs no decal support. Quads are used when `force_quad` is set (tests).

const Lang := preload("res://scripts/vfx/element_language.gd")
const KINDS := ["scorch", "frost", "cracks", "dust", "footprints", "splash"]
const TEX_SIZE := 96
const CAP_BY_TIER := [6, 10, 14, 14]
const FADE_IN := 0.12

static var force_quad := false
static var _tex: Dictionary = {}
static var _live: Array = []            # [{node, t, life, kind, quad}]
static var _pool: Dictionary = {}       # "decal"/"quad" -> Array[Node3D]
static var _hooked := false


static func for_element(element: Variant) -> String:
	return String(Lang.get_lang(element).get("decal", "dust"))


static func uses_quad() -> bool:
	if force_quad:
		return true
	if RenderingServer.get_current_rendering_method() == "gl_compatibility":
		return true
	return _tier() == 0


static func _tier() -> int:
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		var q := (ml as SceneTree).root.get_node_or_null("Quality")
		if q:
			return int(q.get("tier"))
	return 2


static func cap() -> int:
	return int(CAP_BY_TIER[clampi(_tier(), 0, 3)])


static func active_count() -> int:
	_sweep()
	return _live.size()


static func _sweep() -> void:
	var keep: Array = []
	for e: Dictionary in _live:
		if is_instance_valid(e["node"]) and (e["node"] as Node3D).visible:
			keep.append(e)
	_live = keep


# --- textures ---------------------------------------------------------------------------

static func texture(kind: String) -> ImageTexture:
	if _tex.has(kind):
		return _tex[kind]
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 0.06
	n.seed = KINDS.find(kind) * 37 + 5
	var img := Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGBA8)
	var c := (TEX_SIZE - 1) * 0.5
	for y in TEX_SIZE:
		for x in TEX_SIZE:
			var dx := (x - c) / c
			var dy := (y - c) / c
			var d := sqrt(dx * dx + dy * dy)
			var nv := n.get_noise_2d(x, y) * 0.5 + 0.5
			img.set_pixel(x, y, _px(kind, dx, dy, d, nv))
	_tex[kind] = ImageTexture.create_from_image(img)
	return _tex[kind]


static func _px(kind: String, dx: float, dy: float, d: float, nv: float) -> Color:
	var a := 0.0
	var col := Color.WHITE
	match kind:
		"scorch":     # black blot with a hard noisy edge and an ember rim
			var edge := 0.78 - 0.35 * nv
			if d < edge:
				a = 0.88
				col = Color(0.07, 0.05, 0.04)
				if d > edge - 0.07:
					col = Color(0.62, 0.22, 0.08)
					a = 0.9
		"frost":      # pale disc with six crystalline spokes cut by the noise
			var ang := atan2(dy, dx)
			var spoke := absf(cos(ang * 3.0))
			var edge2 := 0.55 + 0.35 * spoke * (0.6 + 0.4 * nv)
			if d < edge2:
				a = 0.78 - 0.25 * d
				col = Color(0.82, 0.95, 1.0) if nv > 0.45 else Color(0.62, 0.84, 0.98)
		"cracks":     # jagged radial cracks: thin bands where the angle noise passes a threshold
			var ang2 := atan2(dy, dx)
			var k := absf(sin(ang2 * 5.0 + nv * 3.0))
			if d < 0.92 and k < 0.09 + 0.1 * (1.0 - d) and d > 0.06:
				a = 0.9
				col = Color(0.1, 0.07, 0.05)
		"dust":       # soft tan ring that thins outward, hard noisy outer edge
			var ring := absf(d - 0.62)
			if ring < 0.2 * (0.4 + nv) and d < 0.95:
				a = 0.55 * (1.0 - ring / 0.3)
				col = Color(0.78, 0.67, 0.5)
		"footprints": # two offset oval soles + toes
			for s in [-1.0, 1.0]:
				var fx: float = (dx - s * 0.32) / 0.2
				var fy: float = (dy + s * 0.12) / 0.5
				if fx * fx + fy * fy < 1.0:
					a = 0.8
					col = Color(0.25, 0.17, 0.1)
				var tx: float = (dx - s * 0.32) / 0.22
				var ty: float = (dy + s * 0.12 + 0.58) / 0.15
				if tx * tx + ty * ty < 1.0:
					a = 0.8
					col = Color(0.25, 0.17, 0.1)
		"splash":     # ring plus drops
			var r2 := absf(d - 0.55)
			if r2 < 0.08 + 0.08 * nv and d < 0.9:
				a = 0.7
				col = Color(0.6, 0.85, 1.0)
			elif d < 0.4 and nv > 0.56:
				a = 0.6
				col = Color(0.72, 0.9, 1.0)
	col.a = a
	return col


# --- spawn -------------------------------------------------------------------------------

static func _make(quad: bool, kind: String) -> Node3D:
	if quad:
		var mi := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(1, 1)
		mi.mesh = qm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.no_depth_test = false
		m.render_priority = -1
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		return mi
	var d := Decal.new()
	d.cull_mask = 1                       # the default visual layer only: ground chunks, never the town wall layers
	d.upper_fade = 0.6
	d.lower_fade = 0.6
	return d


static func spawn(parent: Node, kind: String, pos: Vector3, size := 2.0, life := 6.0, yaw := 0.0) -> Node3D:
	if parent == null or not parent.is_inside_tree() or not KINDS.has(kind):
		return null
	_sweep()
	while _live.size() >= cap():
		_retire(_live.pop_front())
	var quad := uses_quad()
	var pk := "quad" if quad else "decal"
	var arr: Array = _pool.get(pk, [])
	var node: Node3D = null
	while not arr.is_empty() and node == null:
		var c: Variant = arr.pop_back()
		if is_instance_valid(c) and not (c as Node).is_queued_for_deletion():
			node = c
	if node == null:
		node = _make(quad, kind)
	if node.get_parent() != parent:
		if node.get_parent():
			node.reparent(parent, false)
		else:
			parent.add_child(node)
	var tex := texture(kind)
	node.visible = true
	if quad:
		var mi := node as MeshInstance3D
		(mi.material_override as StandardMaterial3D).albedo_texture = tex
		(mi.material_override as StandardMaterial3D).albedo_color = Color(1, 1, 1, 0.0)
		mi.global_transform = Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -PI * 0.5).scaled(Vector3(size, size, size)), pos + Vector3(0, 0.03, 0))
	else:
		var d := node as Decal
		d.texture_albedo = tex
		d.size = Vector3(size, 1.6, size)
		d.modulate = Color(1, 1, 1, 0.0)
		d.global_transform = Transform3D(Basis(Vector3.UP, yaw), pos)
	_live.append({"node": node, "t": 0.0, "life": life, "kind": kind, "quad": quad})
	var tw := node.create_tween()
	node.set_meta("tw", tw)
	tw.tween_method(_set_alpha.bind(node, quad), 0.0, 1.0, FADE_IN)
	tw.tween_interval(maxf(life * 0.45, 0.1))
	tw.tween_method(_set_alpha.bind(node, quad), 1.0, 0.0, maxf(life * 0.55 - FADE_IN, 0.2))
	tw.tween_callback(_expire.bind(node))
	return node


static func _set_alpha(a: float, node: Node3D, quad: bool) -> void:
	if not is_instance_valid(node):
		return
	if quad:
		var m := (node as MeshInstance3D).material_override as StandardMaterial3D
		m.albedo_color = Color(1, 1, 1, a)
	else:
		(node as Decal).modulate = Color(1, 1, 1, a)


static func _expire(node: Node3D) -> void:
	for e: Dictionary in _live:
		if e["node"] == node:
			_live.erase(e)
			break
	_retire({"node": node, "quad": node is MeshInstance3D})


static func _retire(e: Dictionary) -> void:
	var nv: Variant = e["node"]
	if not is_instance_valid(nv):
		return
	var node: Node3D = nv
	if node.has_meta("tw"):
		var tw: Variant = node.get_meta("tw")
		if tw is Tween and (tw as Tween).is_valid():
			(tw as Tween).kill()
	node.visible = false
	var pk := "quad" if node is MeshInstance3D else "decal"
	var arr: Array = _pool.get(pk, [])
	if arr.size() < 12:
		arr.append(node)
		_pool[pk] = arr
	else:
		node.queue_free()


## Drop everything (scene change, tests).
static func clear() -> void:
	for e: Dictionary in _live.duplicate():
		_retire(e)
	_live.clear()
