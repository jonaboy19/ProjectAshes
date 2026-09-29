extends Node3D
## Octahedral impostor baker (own code; technique after Shaderbits' article, MIT-licensed reference: wojtekpil/Godot-Octahedral-Impostors).
## Renders a GLB/scene from grid x grid directions over the upper hemisphere into one albedo+alpha atlas and writes
## <name>_octa.png, <name>_octa_mat.tres (ShaderMaterial using impostor_octa.gdshader), <name>_octa.tscn (a ready-to-place
## quad) and <name>_octa.json (radius/centre/tri counts).
##
## Needs a real GPU (not --headless):
##   Godot --path kingdom --rendering-method mobile res://tools/impostors/impostor_baker.tscn -- \
##       --jobs=oak:res://assets/incoming/quaternius/stylized-nature-megakit/glTF/CommonTree_1.gltf,hut:res://... \
##       [--grid=8] [--tile=128] [--out=res://assets/generated/impostors]

const SHADER := "res://assets/generated/impostors/impostor_octa.gdshader"

var grid := 8
var tile := 128
var out_dir := "res://assets/generated/impostors"
var jobs: Array = []

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--grid="): grid = int(a.substr(7))
		elif a.begins_with("--tile="): tile = int(a.substr(7))
		elif a.begins_with("--out="): out_dir = a.substr(6)
		elif a.begins_with("--jobs="):
			for j in a.substr(7).split(","):
				var kv := j.split(":", true, 1)
				jobs.append([kv[0], kv[1]])
	DisplayServer.window_set_size(Vector2i(320, 240))
	for j in jobs:
		await _bake(j[0], j[1])
	get_tree().quit()

static func hemi_oct_decode(uv: Vector2) -> Vector3:
	var e := uv * 2.0 - Vector2.ONE
	var p := Vector2((e.x + e.y) * 0.5, (e.x - e.y) * 0.5)
	var y := 1.0 - absf(p.x) - absf(p.y)
	return Vector3(p.x, y, p.y).normalized()

func _collect(n: Node, out: Array) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		out.append(n)
	for c in n.get_children():
		_collect(c, out)

func _tris(meshes: Array) -> int:
	var t := 0
	for mi: MeshInstance3D in meshes:
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var idx = arr[Mesh.ARRAY_INDEX]
			t += (idx.size() if idx != null and idx.size() > 0 else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	return t

func _bake(name_: String, path: String) -> void:
	var ps := load(path) as PackedScene
	var vp := SubViewport.new()
	vp.size = Vector2i(tile, tile)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.debug_draw = Viewport.DEBUG_DRAW_UNSHADED   # albedo only; light is applied at runtime by the impostor shader
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var inst := ps.instantiate() as Node3D
	vp.add_child(inst)
	var meshes: Array = []
	_collect(inst, meshes)
	var aabb := AABB()
	var first := true
	for mi: MeshInstance3D in meshes:
		var b: AABB = mi.global_transform * mi.get_aabb()
		aabb = b if first else aabb.merge(b)
		first = false
	var center := aabb.get_center()
	var radius := aabb.size.length() * 0.5
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = radius * 2.0
	cam.near = 0.05
	cam.far = radius * 4.0 + 2.0
	vp.add_child(cam)
	var atlas := Image.create_empty(tile * grid, tile * grid, false, Image.FORMAT_RGBA8)
	for iy in grid:
		for ix in grid:
			var d := hemi_oct_decode(Vector2(ix, iy) / float(grid - 1))
			var up := Vector3(0, 0, -1) if absf(d.y) > 0.999 else Vector3.UP
			cam.look_at_from_position(center + d * (radius * 2.0 + 1.0), center, up)
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			var img := vp.get_texture().get_image()
			img.convert(Image.FORMAT_RGBA8)
			_fill_transparent(img)
			atlas.blit_rect(img, Rect2i(0, 0, tile, tile), Vector2i(ix * tile, iy * tile))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var base := "%s/%s_octa" % [out_dir, name_]
	atlas.save_png(ProjectSettings.globalize_path(base + ".png"))
	var tris := _tris(meshes)
	_write(base + "_mat.tres", """[gd_resource type="ShaderMaterial" format=3]

[ext_resource type="Shader" path="%s" id="1"]
[ext_resource type="Texture2D" path="%s.png" id="2"]

[resource]
shader = ExtResource("1")
shader_parameter/atlas = ExtResource("2")
shader_parameter/grid = %d
shader_parameter/center = Vector3(%f, %f, %f)
shader_parameter/radius = %f
""" % [SHADER, base, grid, center.x, center.y, center.z, radius])
	_write(base + ".tscn", """[gd_scene format=3]

[ext_resource type="Material" path="%s_mat.tres" id="1"]

[sub_resource type="QuadMesh" id="q"]
size = Vector2(%f, %f)
center_offset = Vector3(%f, %f, %f)

[node name="%s_Octa" type="MeshInstance3D"]
extra_cull_margin = %f
cast_shadow = 0
mesh = SubResource("q")
material_override = ExtResource("1")
""" % [base, radius * 2.0, radius * 2.0, center.x, center.y, center.z, name_.capitalize().replace(" ", ""), radius])
	_write(base + ".json", JSON.stringify({"source": path, "grid": grid, "tile": tile, "center": [center.x, center.y, center.z], "radius": radius, "source_tris": tris, "impostor_tris": 2, "atlas_px": tile * grid}, "\t"))
	print("BAKED %s: source %d tris -> 2 tris, radius %.2f m, atlas %dx%d" % [name_, tris, radius, tile * grid, tile * grid])
	vp.queue_free()
	await get_tree().process_frame

func _write(p: String, s: String) -> void:
	var f := FileAccess.open(ProjectSettings.globalize_path(p), FileAccess.WRITE)
	f.store_string(s)
	f.close()

## Transparent pixels get the tile's mean opaque colour so mip/bilinear filtering never bleeds black into the leaf edges.
func _fill_transparent(img: Image) -> void:
	var d := img.get_data()
	var n := d.size()
	var r := 0
	var g := 0
	var b := 0
	var cnt := 0
	var i := 0
	while i < n:
		if d[i + 3] > 127:
			r += d[i]
			g += d[i + 1]
			b += d[i + 2]
			cnt += 1
		i += 16
	if cnt == 0:
		return
	r /= cnt
	g /= cnt
	b /= cnt
	i = 0
	while i < n:
		if d[i + 3] == 0:
			d[i] = r
			d[i + 1] = g
			d[i + 2] = b
		i += 4
	img.set_data(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8, d)
