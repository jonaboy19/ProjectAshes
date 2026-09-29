extends Node3D
## Region 1 L4 render check: normal vs rift-touched, side by side, in a sunny scene.
##
##   Godot --path kingdom res://tools_qa/region1/rift_sheet.tscn --resolution 1600x900 -- \
##       --sheet=flora|fauna|vignette --out=<png> [--quality=high]
##
## Never pass --headless (no GPU output). Left = normal, right = rift. The scene builds the game's own look
## (warm sun, blue sky, ACES, bloom) so the rift tint is judged against the sunny storybook reference.

const NAT := "region/nature/"
const CREA := "res://assets/incoming/ai3d/meshy/creatures/"
const MON := "res://assets/incoming/monsters/quaternius/"
const CRYS := "res://assets/incoming/region1/rift/crystals/"
const DECAL_DIR := "res://assets/incoming/region1/rift/decals/"

var sheet := "flora"
var out_path := ""
var frames := 0
var cam: Camera3D


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--sheet="): sheet = a.substr(8)
		elif a.begins_with("--out="): out_path = a.substr(6)
	_env()
	match sheet:
		"flora": _flora()
		"fauna": _fauna()
		"silverford": _silverford()
		_: _vignette()


func _env() -> void:
	var we := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.12, 0.38, 0.92)
	sm.sky_horizon_color = Color(0.62, 0.8, 1.0)
	sm.ground_horizon_color = Color(0.62, 0.8, 1.0)
	sm.ground_bottom_color = Color(0.45, 0.6, 0.3)
	sm.sun_angle_max = 25.0
	sky.sky_material = sm
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.8
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_white = 6.0
	e.adjustment_enabled = true
	e.adjustment_saturation = 1.15
	e.adjustment_contrast = 1.04
	e.glow_enabled = true
	e.glow_intensity = 0.6
	e.glow_bloom = 0.06
	e.glow_hdr_threshold = 1.0
	e.fog_enabled = true
	e.fog_light_color = Color(0.78, 0.89, 1.0)
	e.fog_density = 0.0015
	we.environment = e
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -38, 0)
	sun.light_color = Color(1.0, 0.92, 0.76)
	sun.light_energy = 1.7
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 80.0
	add_child(sun)
	cam = Camera3D.new()
	cam.fov = 40.0
	cam.far = 400.0
	add_child(cam)


func _ground(center: Vector3, size: Vector2, col: Color) -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = size
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 1.0
	pm.material = m
	mi.mesh = pm
	mi.position = center
	add_child(mi)


func _nature(key: String, pos: Vector3, rift: bool, yaw := 0.0, scale := 1.0) -> Node3D:
	var mi := MeshInstance3D.new()
	mi.mesh = Assets.nature_mesh(NAT + key)
	if mi.mesh == null:
		push_warning("missing nature mesh " + key)
		return mi
	mi.position = pos
	mi.rotation.y = yaw
	mi.scale = Vector3.ONE * scale
	add_child(mi)
	if rift:
		RiftVariants.apply(mi, key.contains("grass") or key.contains("flower") or key.contains("fern"))
	return mi


func _glb(path: String, pos: Vector3, yaw := 0.0, scale := 1.0) -> Node3D:
	var ps := load(path) as PackedScene
	if ps == null:
		push_warning("missing " + path)
		return null
	var n := ps.instantiate() as Node3D
	n.position = pos
	n.rotation.y = yaw
	n.scale = Vector3.ONE * scale
	add_child(n)
	# decals must not paint creatures or crystals: they live on render layer 2, decals cull to layer 1 only
	for vi in n.find_children("*", "VisualInstance3D", true, false):
		(vi as VisualInstance3D).layers = 2
	for ap in n.find_children("*", "AnimationPlayer", true, false):
		for a in ["idle", "Idle", "idle_loop"]:
			if (ap as AnimationPlayer).has_animation(a):
				(ap as AnimationPlayer).play(a)
				break
	return n


func _decal(kind: String, pos: Vector3, size: float, yaw := 0.0) -> void:
	var d := Decal.new()
	d.size = Vector3(size, 3.0, size)
	d.texture_albedo = load(DECAL_DIR + "rift_decal_%s.png" % kind)
	d.texture_emission = load(DECAL_DIR + "rift_decal_%s_em.png" % kind)
	d.emission_energy = 1.1
	d.albedo_mix = 0.95
	d.cull_mask = 1
	d.position = pos + Vector3(0, 0.5, 0)
	d.rotation.y = yaw
	add_child(d)


func _flora() -> void:
	_ground(Vector3(-24, 0, 0), Vector2(48, 60), Color(0.42, 0.62, 0.22))
	_ground(Vector3(24, 0, 0), Vector2(48, 60), Color(0.42, 0.62, 0.22))
	var rows := [
		[["oak_a", -14.5, -9.0, 1.0], ["beech_a", -8.0, -9.5, 1.0], ["young_oak", -2.6, -7.0, 1.0]],
		[["spruce_a", -11.5, -2.0, 1.0], ["bush_round", -6.5, -1.0, 1.0], ["rock_cluster", -2.0, -1.0, 1.0]],
		[["fern_a", -13.5, 4.0, 1.4], ["grass_tall", -10.0, 4.5, 1.4], ["flowers_warm", -6.5, 4.5, 1.4], ["stump_mossy", -3.0, 4.0, 1.0]],
	]
	for side in [0, 1]:
		var dx := 0.0 if side == 0 else 19.0
		for row in rows:
			for it in row:
				var k: String = it[0]
				var p := Vector3(float(it[1]) + dx, 0, float(it[2]))
				var sc: float = it[3]
				var count := 1
				if k.contains("grass") or k.contains("fern") or k.contains("flower"):
					count = 3
				for c in count:
					_nature(k, p + Vector3(c * 1.3 - 1.3, 0, (c % 2) * 0.7), side == 1, c * 0.9, sc)
	cam.position = Vector3(2.5, 7.5, 24.0)
	cam.look_at(Vector3(2.5, 3.2, -2.0))


func _fauna() -> void:
	_ground(Vector3(-24, 0, 0), Vector2(48, 60), Color(0.42, 0.62, 0.22))
	_ground(Vector3(24, 0, 0), Vector2(48, 60), Color(0.42, 0.62, 0.22))
	# left: normal wolf and boar
	_glb(CREA + "wolf_lod1.glb", Vector3(-6.0, 0, 1.0), 0.6)
	_glb(CREA + "boar_lod1.glb", Vector3(-2.5, 0, 1.5), -0.4)
	# right: rift wolf, boar, slime, wraith
	var w := _glb(CREA + "wolf_lod1.glb", Vector3(2.5, 0, 1.0), 0.6)
	if w: RiftVariants.apply_creature(w, "wolf", true)
	var b := _glb(CREA + "boar_lod1.glb", Vector3(6.0, 0, 1.5), -0.4)
	if b: RiftVariants.apply_creature(b, "boar", true)
	_glb(MON + "rift_slime_lod1.glb", Vector3(9.5, 0, 2.2), -0.3, 1.4)
	_glb(MON + "rift_wraith_lod1.glb", Vector3(13.0, 0, 0.5), -0.4, 1.0)
	for i in 3:
		_glb(CRYS + "scar_crystal_%s_lod0.glb" % ["a", "b", "c"][i], Vector3(3.5 + i * 4.0, 0, -5.0), i * 1.2)
	_decal("patch_a", Vector3(4.0, 0, 1.2), 7.0, 0.3)
	_decal("patch_b", Vector3(11.0, 0, 1.2), 6.0, 1.0)
	_decal("crack", Vector3(8.0, 0, 5.0), 8.0, 0.2)
	cam.position = Vector3(3.5, 3.2, 15.0)
	cam.look_at(Vector3(3.5, 0.9, 0.0))


func _silverford() -> void:
	## L3 exteriors in the sun: Silverford guild hall (left) and the Dawn Throne chapel (right) on cobbles with the
	## region's own trees and flowers around them, seen from the road like the gate-market reference.
	_ground(Vector3(0, 0, 0), Vector2(140, 140), Color(0.45, 0.63, 0.24))
	_ground(Vector3(0, 0.03, 8), Vector2(8, 60), Color(0.78, 0.68, 0.5))         # cobbled road
	var sd := "res://assets/incoming/region1/silverford/"
	_glb(sd + "guildhall_silverford_lod0.glb", Vector3(-10.0, 0, -4.0), 0.55)
	_glb(sd + "chapel_dawn_throne_lod0.glb", Vector3(11.0, 0, -8.0), -0.5)
	_nature("oak_a", Vector3(-19.0, 0, -12.0), false, 0.4)
	_nature("beech_a", Vector3(21.0, 0, -18.0), false, 1.1)
	_nature("young_oak", Vector3(2.0, 0, -16.0), false, 2.0)
	_nature("bush_round", Vector3(-5.0, 0, 1.0), false, 0.3)
	_nature("bush_round", Vector3(6.5, 0, 0.0), false, 1.3)
	for i in 18:
		var x := -16.0 + fmod(i * 5.3, 32.0)
		var z := 2.0 + fmod(i * 3.7, 9.0)
		if absf(x) < 4.5 and z > -4.0:
			continue
		_nature("flowers_warm" if i % 2 == 0 else "flowers_cool", Vector3(x, 0, z), false, i * 0.8, 1.6)
	cam.position = Vector3(1.0, 2.2, 26.0)
	cam.look_at(Vector3(1.0, 4.0, -4.0))
	cam.fov = 52.0


func _vignette() -> void:
	## A meadow at the edge of the Scar: normal oaks and flowers on the left, rift trees, crystals, decals and
	## a rift wolf on the right. Player-height view, like the main reference.
	_ground(Vector3(0, 0, 0), Vector2(120, 120), Color(0.44, 0.63, 0.23))
	_ground(Vector3(20, 0.02, -4), Vector2(30, 60), Color(0.52, 0.56, 0.42))
	var lin := [["oak_a", -12.0, -14.0, 1.0], ["beech_a", -5.0, -18.0, 1.0], ["young_oak", -16.0, -6.0, 1.0],
		["bush_round", -4.0, -4.0, 1.0], ["oak_b", -20.0, -20.0, 1.0]]
	for it in lin:
		_nature(it[0], Vector3(it[1], 0, it[2]), false, float(it[1]) * 0.3, it[3])
	var rin := [["oak_a", 9.0, -12.0, 1.1], ["beech_a", 15.0, -18.0, 1.0], ["young_oak", 5.0, -6.0, 1.0],
		["oak_b", 21.0, -9.0, 1.1], ["bush_round", 8.0, -3.0, 1.0], ["spruce_a", 26.0, -15.0, 1.0],
		["dead_snag", 12.0, -5.0, 1.0], ["rock_cluster", 16.0, -4.0, 1.0]]
	for it in rin:
		_nature(it[0], Vector3(it[1], 0, it[2]), true, float(it[1]) * 0.3, it[3])
	for i in 14:
		var x := -10.0 + fmod(i * 4.7, 20.0)
		var z := 2.0 + fmod(i * 3.1, 8.0)
		_nature("flowers_warm" if i % 2 == 0 else "grass_tall", Vector3(x, 0, z), x > 3.0, i * 0.8, 1.5)
	for i in 3:
		_glb(CRYS + "scar_crystal_%s_lod0.glb" % ["a", "b", "c"][i], Vector3(6.5 + i * 3.6, 0, -1.5 - i * 1.6), i * 1.4, 1.4)
	_decal("patch_a", Vector3(9.0, 0, 0.5), 9.0, 0.2)
	_decal("patch_b", Vector3(15.0, 0, 2.0), 7.0, 0.9)
	_decal("crack", Vector3(5.0, 0, 4.5), 10.0, 0.1)
	var w := _glb(CREA + "wolf_lod1.glb", Vector3(6.0, 0, 3.5), -0.9, 1.0)
	if w: RiftVariants.apply_creature(w, "wolf", true)
	_glb(MON + "rift_slime_lod1.glb", Vector3(11.0, 0, 3.0), 0.4, 1.4)
	cam.position = Vector3(1.5, 1.7, 12.0)
	cam.look_at(Vector3(6.0, 2.4, -6.0))
	cam.fov = 58.0


func _process(_dt: float) -> void:
	frames += 1
	if frames == 90:
		var img := get_viewport().get_texture().get_image()
		if out_path == "":
			out_path = "user://rift_%s.png" % sheet
		DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
		img.save_png(out_path)
		print("SAVED ", out_path, " ", img.get_size())
		get_tree().quit()
