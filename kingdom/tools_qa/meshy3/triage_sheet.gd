extends SceneTree
## Triage contact sheet of the Meshy batch 3 models (assets/incoming/meshy_dl3) with the Style G treatment applied:
## Assets.static_model (role materials) + FillStyle.apply (per-model desaturate/matte from fill_style.gd TREAT, "dl3/<cat>/<name>").
## Each model is fitted to a cell (real size in the label). Not the game camera, but the game lighting (StyleG daylight).
##   xvfb-run -a -s "-screen 0 1920x1080x24" Godot --path kingdom --rendering-driver vulkan --resolution 1920x1080 \
##       -s res://tools_qa/meshy3/triage_sheet.gd -- --out=<abs png> --cols=8 --cat=buildings,castle [--raw] [--only=a,b]
## --raw skips FillStyle.apply (before/after). Needs a GPU/lavapipe context, never --headless.
const FillStyle := preload("res://scripts/world/fill_style.gd")
const ROOT := "res://assets/incoming/meshy_dl3/"
var out := ""
var cols := 8
var cats: PackedStringArray = []
var only: PackedStringArray = []
var raw := false
var frame := 0
var world: Node3D
var cam: Camera3D


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
		elif a.begins_with("--cols="): cols = int(a.substr(7))
		elif a.begins_with("--cat="): cats = a.substr(6).split(",", false)
		elif a.begins_with("--only="): only = a.substr(7).split(",", false)
		elif a == "--raw": raw = true
	world = Node3D.new()
	root.add_child.call_deferred(world)


func _process(_dt: float) -> bool:
	frame += 1
	if frame == 10:
		_build()
	elif frame == 50:
		root.get_viewport().get_texture().get_image().save_png(out)
		print("saved ", out)
		quit()
	return false


func _paths() -> Array[String]:
	var res: Array[String] = []
	var dirs := DirAccess.get_directories_at(ROOT)
	dirs.sort()
	for d in dirs:
		if not cats.is_empty() and not cats.has(d):
			continue
		var files := Array(DirAccess.get_files_at(ROOT + d))
		files.sort()
		for f: String in files:
			if f.ends_with("_lod0.glb"):
				if only.is_empty() or only.has(f.get_basename().trim_suffix("_lod0")):
					res.append(ROOT + d + "/" + f)
	return res


func _build() -> void:
	WorldGen.setup(WorldSim.SEED)
	var SG: GDScript = load("res://scripts/style_g.gd")
	var env: Environment = SG.make_environment("low")
	var sun: DirectionalLight3D = SG.make_sun("low")
	var fill: DirectionalLight3D = SG.make_fill()
	world.add_child(sun)
	world.add_child(fill)
	SG.apply_daylight(env, sun, fill, 15.0)
	env.fog_enabled = false
	env.volumetric_fog_enabled = false
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(2000, 2000)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.36, 0.42, 0.24)
	fm.roughness = 1.0
	floor_mi.material_override = fm
	floor_mi.position.y = -0.02
	world.add_child(floor_mi)
	var paths := _paths()
	var rows := int(ceil(paths.size() / float(cols)))
	var cell := 10.0
	for i in paths.size():
		var p := paths[i]
		var n := Assets.static_model(p)
		if n == null:
			continue
		var model := p.trim_prefix(ROOT).trim_suffix("_lod0.glb")
		if not raw:
			FillStyle.apply(n, "dl3:" + model)
		var holder := Node3D.new()
		world.add_child(holder)
		holder.add_child(n)
		var box := Assets.visual_aabb(n)
		var skels := n.find_children("*", "Skeleton3D", true, false)
		if not skels.is_empty():        # skinned: the mesh AABB is in bind space, so size by the head bone through the node scales
			var sk := skels[0] as Skeleton3D
			var hb := sk.find_bone("Head")
			var xf := Transform3D.IDENTITY
			var cur: Node = sk
			while cur != null and cur != n.get_parent():
				if cur is Node3D:
					xf = (cur as Node3D).transform * xf
				cur = cur.get_parent()
			var top := (xf * sk.get_bone_global_rest(hb).origin).y * 1.12 if hb >= 0 else 1.8
			box = AABB(Vector3(-top * 0.5, 0, -top * 0.25), Vector3(top, top, top * 0.5))
			var ap := n.find_children("*", "AnimationPlayer", true, false)
			if not ap.is_empty() and (ap[0] as AnimationPlayer).get_animation_list().size() > 0:
				(ap[0] as AnimationPlayer).play((ap[0] as AnimationPlayer).get_animation_list()[0])
				(ap[0] as AnimationPlayer).seek(0.0, true)
				(ap[0] as AnimationPlayer).pause()
		var k := 7.0 / maxf(maxf(box.size.x, box.size.z), box.size.y)
		if not skels.is_empty():
			k = 6.0 / maxf(box.size.y, 0.01)
		holder.scale = Vector3.ONE * k
		var c := Vector3((i % cols) * cell, 0, (i / cols) * cell * 1.1)
		holder.position = c - Vector3(box.get_center().x, box.position.y, box.get_center().z) * k
		var tris := 0
		for mi in n.find_children("*", "MeshInstance3D", true, false) + ([n] if n is MeshInstance3D else []):
			var m := (mi as MeshInstance3D).mesh
			if m:
				tris += m.get_faces().size() / 3
		var l := Label3D.new()
		l.text = "%s\n%.1fx%.1fx%.1fm %.1fk" % [model, box.size.x, box.size.y, box.size.z, tris / 1000.0]
		l.font_size = 36
		l.pixel_size = 0.01
		l.outline_size = 10
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.position = c + Vector3(0, 0.3, 4.2)
		world.add_child(l)
	cam = Camera3D.new()
	cam.environment = env
	world.add_child(cam)
	var w := cols * cell
	var h := rows * cell * 1.1
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = maxf(h * 0.95, w * 0.56) + 4.0
	var mid := Vector3((cols - 1) * cell * 0.5, 2.0, (rows - 1) * cell * 0.55)
	cam.position = mid + Vector3(0, 45, 70)
	cam.look_at(mid)
	cam.current = true
