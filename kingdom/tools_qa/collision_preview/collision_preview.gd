extends Node3D
## Small asset viewer for the collision boxes actually used by Assets.building_node().
## Run from the repository root with the companion run.ps1 or run.sh script.

const OUT_DIR := "res://../docs/qa/collision_preview"
const ASSETS := [
	"mhouse_peasant_a", "mhouse_peasant_b", "mhouse_family", "mhouse_trader", "mhouse_manor",
	"inn", "blacksmith", "adventurer_guild", "healer_house",
	"market_stand_1", "market_stand_2", "market_stand_3", "market_stand_4",
	"stable", "chapel", "bell_tower", "castle", "temple", "wall_gate",
]

var _stage: Node3D
var _camera: Camera3D
var _status: Label
var _assets: Array[Dictionary] = []
var _index := 0
var _yaw := 0.7
var _pitch := 0.18
var _dragging := false
var _capture := false
var _proxy_size := Vector3.ZERO


func _ready() -> void:
	_capture = OS.get_cmdline_user_args().has("--capture")
	_stage = Node3D.new()
	add_child(_stage)
	_add_lighting()
	_add_camera()
	_add_hud()
	for key in ASSETS:
		var mesh := Assets.building_mesh(key)
		if mesh == null:
			_assets.append({"key": key, "mesh": null, "size": Vector3.ZERO})
		else:
			_assets.append({"key": key, "mesh": mesh, "size": mesh.get_aabb().size})
	await _show_asset(0)
	if _capture:
		_capture_all()


func _add_lighting() -> void:
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("202832")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("a9b7c7")
	environment.ambient_light_energy = 0.65
	env.environment = environment
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -30, 0)
	sun.light_energy = 2.0
	add_child(sun)


func _add_camera() -> void:
	_camera = Camera3D.new()
	_camera.current = true
	add_child(_camera)


func _add_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(16, 16)
	panel.custom_minimum_size = Vector2(520, 106)
	layer.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 20)
	box.add_child(_status)
	var hint := Label.new()
	hint.text = "← / → change asset · drag to orbit · Esc to close · blue outline = solid proxy"
	box.add_child(hint)


func _show_asset(index: int) -> void:
	_index = posmod(index, _assets.size())
	_status.text = ""
	_proxy_size = Vector3.ZERO
	for child in _stage.get_children():
		child.free()
	var entry: Dictionary = _assets[_index]
	var key: String = entry["key"]
	var mesh: Mesh = entry["mesh"]
	if mesh == null:
		_status.text = "%s — MISSING MESH" % key
		return
	var model := MeshInstance3D.new()
	model.mesh = mesh
	_stage.add_child(model)
	var holder := Assets.building_node(key, true)
	for child in holder.get_children():
		if child is StaticBody3D:
			var body := child as StaticBody3D
			for shape_node in body.get_children():
				if shape_node is CollisionShape3D and shape_node.shape is BoxShape3D:
					_show_box(shape_node as CollisionShape3D, body)
					var box_shape := shape_node.shape as BoxShape3D
					var extents := box_shape.size
					_proxy_size = extents
					var size: Vector3 = entry["size"]
					_status.text = "%s   mesh %.2f × %.2f × %.2f m   proxy %.2f × %.2f × %.2f m" % [
						key, size.x, size.y, size.z, extents.x, extents.y, extents.z]
	holder.free()
	if _status.text.is_empty():
		_status.text = "%s — no BoxShape3D found" % key
	var extent: Vector3 = entry["size"]
	var radius := maxf(maxf(extent.x, extent.z) * 0.5, extent.y * 0.35)
	_update_camera(maxf(radius, 1.0))
	await RenderingServer.frame_post_draw


func _show_box(shape_node: CollisionShape3D, body: StaticBody3D) -> void:
	if not shape_node.shape is BoxShape3D:
		return
	var box := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = (shape_node.shape as BoxShape3D).size
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.15, 0.75, 1.0, 0.16)
	material.no_depth_test = true
	var wire := ImmediateMesh.new()
	var h := mesh.size * 0.5
	var corners := [Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z),
		Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z),
		Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z),
		Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z)]
	var edges := [[0, 1], [1, 2], [2, 3], [3, 0], [4, 5], [5, 6], [6, 7], [7, 4], [0, 4], [1, 5], [2, 6], [3, 7]]
	wire.surface_begin(Mesh.PRIMITIVE_LINES, material)
	for edge in edges:
		wire.surface_add_vertex(corners[edge[0]])
		wire.surface_add_vertex(corners[edge[1]])
	wire.surface_end()
	box.mesh = wire
	box.transform = body.transform * shape_node.transform
	box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_stage.add_child(box)


func _update_camera(radius: float) -> void:
	var distance := radius * 2.7
	_camera.position = Vector3(sin(_yaw) * distance, radius * (0.45 + _pitch), cos(_yaw) * distance)
	_camera.look_at(Vector3(0, radius * 0.45, 0), Vector3.UP)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_RIGHT:
			_show_asset(_index + 1)
		elif event.keycode == KEY_LEFT:
			_show_asset(_index - 1)
		elif event.keycode == KEY_ESCAPE:
			get_tree().quit()
	elif event is InputEventMouseButton:
		_dragging = event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	elif event is InputEventMouseMotion and _dragging:
		_yaw -= event.relative.x * 0.008
		_pitch = clampf(_pitch - event.relative.y * 0.004, -0.2, 0.8)
		var size: Vector3 = _assets[_index]["size"]
		_update_camera(maxf(maxf(size.x, size.z) * 0.5, size.y * 0.35))


func _capture_all() -> void:
	var out_path := ProjectSettings.globalize_path(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(out_path)
	var cards: Array[String] = []
	for i in _assets.size():
		await _show_asset(i)
		var entry: Dictionary = _assets[i]
		var key: String = entry["key"]
		var file := key + ".png"
		if entry["mesh"] == null:
			cards.append("<article><h2>%s</h2><p class='missing'>MESH NOT FOUND</p></article>" % key)
			continue
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		image.save_png(out_path.path_join(file))
		var size: Vector3 = entry["size"]
		cards.append("<article><a href='%s'><img src='%s' alt='%s mesh with its physics proxy'></a><h2>%s</h2><p>Mesh AABB: %.2f × %.2f × %.2f m<br>Box proxy: %.2f × %.2f × %.2f m</p></article>" % [file, file, key, key, size.x, size.y, size.z, _proxy_size.x, _proxy_size.y, _proxy_size.z])
	_build_html(out_path, cards)
	print("COLLISION_PREVIEW_DONE assets=%d output=%s" % [_assets.size(), out_path])
	get_tree().quit()


func _build_html(out_path: String, cards: Array[String]) -> void:
	var html := """
<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Rising Ashes collider gallery</title>
<style>body{margin:0;background:#111923;color:#e7edf4;font:16px system-ui}header{padding:26px 4vw;background:#1c2937;position:sticky;top:0}h1{margin:0 0 8px}p{color:#bac8d6}main{padding:22px 4vw;display:grid;grid-template-columns:repeat(auto-fit,minmax(340px,1fr));gap:18px}article{background:#202c39;border-radius:12px;overflow:hidden;padding-bottom:12px}img{width:100%;display:block}h2,p{margin:10px 16px}.missing{color:#ff7777}</style>
<header><h1>Meshy and landmark collision proxies</h1><p>Rendered from the game's actual Assets.building_node() mesh and BoxShape3D. Blue wireframe is the solid physics proxy. The settlement builder uses the same 92% horizontal AABB footprint for city lots.</p></header><main>
"""
	for card in cards:
		html += card + "\n"
	html += "</main>"
	var file := FileAccess.open(out_path.path_join("index.html"), FileAccess.WRITE)
	if file:
		file.store_string(html)
