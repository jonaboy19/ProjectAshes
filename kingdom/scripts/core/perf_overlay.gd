extends CanvasLayer
## Performance overlay controller (autoload "PerfOverlay").
## Wraps Calinou's godot-debug-menu (addons/debug_menu, MIT) which is created lazily
## on first toggle so it costs nothing while hidden (release default = OFF).
## Desktop: F3 (handled by the addon: hidden -> compact -> detailed -> hidden).
## Mobile: hidden 3-finger tap cycles the same way.
## Adds a second label with draw calls / primitives / objects / process+physics ms / nodes.

var _menu: Node = null
var _label: Label = null
var _touches := {}
var _tap_start_ms := 0
var _acc := 0.0

func _ready() -> void:
	layer = 127
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
	for a in OS.get_cmdline_user_args():
		if a == "--perf":
			_toggle()


func _get_menu() -> Node:
	if _menu == null or not is_instance_valid(_menu):
		_menu = get_node_or_null("/root/DebugMenu")
		if _menu == null:
			_menu = load("res://addons/debug_menu/debug_menu.tscn").instantiate()
			get_tree().root.add_child.call_deferred(_menu)
	return _menu


func _toggle() -> void:
	var m := _get_menu()
	if m.is_inside_tree():
		m.style = wrapi(m.style + 1, 0, m.Style.MAX)
	else:
		m.ready.connect(func(): m.style = m.Style.VISIBLE_COMPACT, CONNECT_ONE_SHOT)
	_ensure_label()
	# Visibility is resolved next frame (menu may not be in tree yet).
	await get_tree().process_frame
	_label.visible = m.visible
	set_process(m.visible)


func _ensure_label() -> void:
	if _label:
		return
	_label = Label.new()
	_label.position = Vector2(8, 200)
	_label.add_theme_font_size_override("font_size", 12)
	_label.add_theme_color_override("font_color", Color(0.85, 1, 0.85))
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 4)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.visible = false
	add_child(_label)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		# The addon also reacts to F3 via its own action once instantiated; only bootstrap here.
		if _menu == null or not is_instance_valid(_menu):
			_toggle()
			get_viewport().set_input_as_handled()
		else:
			_sync_later()
	elif event is InputEventScreenTouch:
		if event.pressed:
			if _touches.is_empty():
				_tap_start_ms = Time.get_ticks_msec()
			_touches[event.index] = true
			if _touches.size() == 3 and Time.get_ticks_msec() - _tap_start_ms < 600:
				_toggle()
		else:
			_touches.erase(event.index)


func _sync_later() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if _menu and is_instance_valid(_menu):
		_ensure_label()
		_label.visible = _menu.visible
		set_process(_menu.visible)


func _process(delta: float) -> void:
	_acc += delta
	if _acc < 0.25 or _label == null:
		return
	_acc = 0.0
	var vp := get_viewport()
	_label.text = "draws %d  prims %dk  objs %d\nscript proc %.2f ms  phys %.2f ms\nnodes %d  skinned %d\nmem %.0f MB  vram %.0f MB" % [
		vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
		vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME) / 1000,
		vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_OBJECTS_IN_FRAME),
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		count_skinned(get_tree()),
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0]


## Count visible Skeleton3D users (skinned MeshInstance3D that are visible in tree).
static func count_skinned(tree: SceneTree) -> int:
	var n := 0
	var stack: Array[Node] = [tree.root]
	while not stack.is_empty():
		var nd: Node = stack.pop_back()
		if nd is Skeleton3D:
			if (nd as Skeleton3D).is_visible_in_tree() and _has_drawn_mesh(nd):
				n += 1
			continue
		for c in nd.get_children():
			stack.append(c)
	return n


static func _has_drawn_mesh(skel: Node) -> bool:
	for c in skel.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).is_visible_in_tree() and (c as MeshInstance3D).mesh != null:
			return true
	return false


## Debug: print who owns visible skeletons (used by `--census` on QA shots).
static func print_skeleton_census(tree: SceneTree) -> void:
	var by := {}
	for sk in tree.root.find_children("*", "Skeleton3D", true, false):
		var s := sk as Skeleton3D
		if not (s.is_visible_in_tree() and _has_drawn_mesh(s)):
			continue
		var a: Node = s
		var chain := ""
		for i in 5:
			a = a.get_parent()
			if a == null:
				break
			chain += "%s(%s)<" % [a.name, a.get_script().resource_path.get_file() if a.get_script() else a.get_class()]
		by[chain] = int(by.get(chain, 0)) + 1
	for k in by:
		print("[census] ", by[k], "  ", k)


## Debug: what is actually drawn this frame (used by `--drawcensus` on QA shots).
## Groups frustum-visible, in-range instances by owner/mesh and prints draws + tris.
static func print_draw_census(tree: SceneTree, vp: Viewport) -> void:
	var cam := vp.get_camera_3d()
	if cam == null:
		return
	var planes := cam.get_frustum()
	var rows := {}
	var tri_cache := {}
	for n in tree.root.find_children("*", "GeometryInstance3D", true, false):
		var g := n as GeometryInstance3D
		if not g.is_visible_in_tree():
			continue
		var d := cam.global_position.distance_to((g.global_transform * g.get_aabb()).get_center())
		if g.visibility_range_end > 0.0 and d > g.visibility_range_end:
			continue
		if d < g.visibility_range_begin:
			continue
		var mesh: Mesh = null
		var inst := 1
		if g is MeshInstance3D:
			mesh = (g as MeshInstance3D).mesh
		elif g is MultiMeshInstance3D and (g as MultiMeshInstance3D).multimesh:
			mesh = (g as MultiMeshInstance3D).multimesh.mesh
			inst = (g as MultiMeshInstance3D).multimesh.visible_instance_count
			if inst < 0:
				inst = (g as MultiMeshInstance3D).multimesh.instance_count
		elif g is CPUParticles3D or g is GPUParticles3D:
			pass
		if mesh == null:
			continue
		if not _aabb_in_frustum(g.global_transform * g.get_aabb(), planes):
			continue
		if not tri_cache.has(mesh):
			tri_cache[mesh] = mesh.get_faces().size() / 3 if mesh.get_surface_count() > 0 else 0
		var owner_n: Node = g.get_parent()
		var oname := String(owner_n.name) if owner_n else ""
		if not oname.begins_with("Skeleton"):
			oname = oname.rstrip("0123456789")
		var key := "%s | %s | %s%s%s" % [oname, g.get_class(), mesh.resource_path.get_file().get_slice("::", 0) if mesh.resource_path != "" else mesh.get_class(),
			" shadow" if g.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF else "",
			" vis[%d-%d] %dtri/inst" % [int(g.visibility_range_begin), int(g.visibility_range_end), int(tri_cache[mesh])] if g is MultiMeshInstance3D else ""]
		var r: Array = rows.get(key, [0, 0, 0])
		r[0] += mesh.get_surface_count()
		r[1] += int(tri_cache[mesh]) * inst
		r[2] += inst
		rows[key] = r
	var keys := rows.keys()
	keys.sort_custom(func(a, b): return rows[a][0] > rows[b][0])
	var td := 0
	var tt := 0
	for k in keys:
		td += rows[k][0]
		tt += rows[k][1]
	print("[draw] census total draws=%d tris=%d rows=%d" % [td, tt, keys.size()])
	for k in keys.slice(0, 45):
		print("[draw] draws=%d tris=%d inst=%d  %s" % [rows[k][0], rows[k][1], rows[k][2], k])


static func _aabb_in_frustum(box: AABB, planes: Array[Plane]) -> bool:
	for pl in planes:
		var p := box.position
		if pl.normal.x < 0.0:
			p.x += box.size.x
		if pl.normal.y < 0.0:
			p.y += box.size.y
		if pl.normal.z < 0.0:
			p.z += box.size.z
		if pl.distance_to(p) > 0.0:
			return false
	return true


## Debug (`--ablate`): hide each child of `root` in turn and print how many draw calls and
## primitives it was responsible for (measured 3 frames after hiding).
static func ablate(tree: SceneTree, vp: Viewport, root: Node) -> void:
	var base := _snap(vp)
	print("[ablate] base draws=%d prims=%d" % [base[0], base[1]])
	var groups := {}
	for c in root.get_children():
		if c is Node3D and (c as Node3D).visible:
			var key := "%s(%s)" % [String(c.name).rstrip("0123456789@"), c.get_script().resource_path.get_file() if c.get_script() else c.get_class()]
			if not groups.has(key):
				groups[key] = []
			groups[key].append(c)
	var out := []
	for key in groups:
		for c in groups[key]:
			(c as Node3D).visible = false
		for i in 3:
			await tree.process_frame
		var s := _snap(vp)
		for c in groups[key]:
			(c as Node3D).visible = true
		out.append([base[0] - s[0], base[1] - s[1], key, groups[key].size()])
	out.sort_custom(func(a, b): return a[0] + a[1] / 2000 > b[0] + b[1] / 2000)
	for r in out:
		print("[ablate] draws=%d prims=%d  x%d %s" % [r[0], r[1], r[3], r[2]])


static func _snap(vp: Viewport) -> Array:
	return [vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
		vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)]
