extends Node
## Windowed QA for SurfaceQuery / SurfaceFeedback / survival needs:
##   Godot --path kingdom -- --adult --qa=res://tools_qa/surface/surface_qa.gd --out=<dir>
## Visits a paved plaza, open grass, a forest floor, a shore and shallow water; at each spot it fires footsteps
## (sound + puff) and a hard landing, prints the SurfaceQuery result and saves <out>/surface_<name>.png.

const SQ := preload("res://scripts/world/surface_query.gd")
const FX := preload("res://scripts/world/surface_feedback.gd")
var main: Node
var out := "user://"
var _label: Label


func run(m: Node) -> void:
	main = m
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 22)
	_label.position = Vector2(20, 20)
	var cl := CanvasLayer.new()
	cl.layer = 100
	cl.add_child(_label)
	add_child(cl)
	var home: Vector2 = WorldGen.settlements[0]["pos"]
	var spots := {"plaza": home}
	var found := {}
	for r in range(60, 1400, 20):
		for a in range(0, 360, 10):
			var p := home + Vector2(cos(deg_to_rad(a)), sin(deg_to_rad(a))) * r
			var m2 := String(SQ.terrain_material(p.x, p.y))
			var d := WorldGen.water_depth(p.x, p.y)
			if m2 == "water" and d < 0.6 and not found.has("water"):
				found["water"] = p
			elif m2 in ["grass", "leaves", "sand", "dirt", "mud", "snow"] and not found.has(m2):
				found[m2] = p
	spots.merge(found)
	print("SURFQA spots ", spots)
	var only_prints := OS.get_cmdline_user_args().has("--prints")
	for k: String in spots:
		if not only_prints:
			await _visit(k, spots[k])
	await _prints_demo(spots.get("dirt", home + Vector2(20, 0)))
	print("SURFQA needs water=%.1f warmth=%.1f env=%s" % [Life.needs.water, Life.needs.warmth, Life.needs.env])
	get_tree().quit(0)


func _visit(name: String, p: Vector2) -> void:
	main.call("_teleport", p, 0.0)
	await get_tree().create_timer(2.5).timeout
	var pl: Node3D = main.player
	var g: Dictionary = {}
	for i in 6:
		g = FX.footstep(pl, pl.global_position + pl.global_transform.basis.x * (0.15 if i % 2 == 0 else -0.15), 0.0, 4.0)
		await get_tree().create_timer(0.08).timeout
	FX.land(pl, pl.global_position, 10.0)
	var txt := "%s: kind=%s material=%s footstep=%s slope=%.0f water=%.2f" % [name, g["kind"], g["material"], g["footstep"],
		g["slope_deg"], g["water_depth"]]
	_label.text = txt + "\nneeds: %s / %s / %s / %s" % [Life.needs.hunger_label(), Life.needs.thirst_label(),
		Life.needs.rest_label(), Life.needs.warmth_label()]
	print("SURFQA ", txt)
	await get_tree().create_timer(0.12).timeout
	main.get_viewport().get_texture().get_image().save_png(out.path_join("surface_%s.png" % name))


## Footprints: an invisible snow-tagged slab on the ground, a line of 12 steps, one screenshot.
func _prints_demo(p: Vector2) -> void:
	main.call("_teleport", p, 0.0)
	await get_tree().create_timer(2.5).timeout
	var pl: Node3D = main.player
	var slab := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(12, 0.1, 12)
	cs.shape = box
	slab.add_child(cs)
	slab.collision_layer = 0x80000   # a layer the player does not stand on
	SQ.tag(slab, &"mud")
	main.world.add_child(slab)
	slab.global_position = pl.global_position + Vector3(0, 0.06, 0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var fwd := -pl.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	for i in 12:
		var at := pl.global_position + fwd * (0.4 + i * 0.35) + Vector3(fwd.z, 0, -fwd.x) * 1.6
		var gg: Dictionary = FX.footstep(pl, at, -10.0, 3.0)
		print("SURFQA step ", at, " -> ", gg["position"], " ", gg["material"], " ", gg["collider"])
		await get_tree().create_timer(0.05).timeout
	_label.text = "footprints: %d pooled decals (mud)" % FX.print_count()
	for d: Decal in FX._prints:
		print("SURFQA decal ", d.global_position, " in_tree=", d.is_inside_tree(), " mix=", d.albedo_mix, " vis=", d.is_visible_in_tree())
	var cam := pl.get_viewport().get_camera_3d()
	print("SURFQA cam ", cam.global_position, " player ", pl.global_position, " fwd ", fwd)
	print("SURFQA prints ", FX.print_count())
	await get_tree().create_timer(0.3).timeout
	main.get_viewport().get_texture().get_image().save_png(out.path_join("surface_prints.png"))
	await _survival_demo()


## Campfire (heat + cooking station), a well use, a sword-on-stone impact: one screenshot each.
func _survival_demo() -> void:
	var pl: Node3D = main.player
	var fwd := -pl.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var fire: Node3D = load("res://scripts/world/campfire.gd").new()
	main.world.add_child(fire)
	var fp := pl.global_position + fwd * 2.2
	fire.global_position = Vector3(fp.x, WorldGen.height(fp.x, fp.z), fp.z)
	Life.needs.warmth = 30.0
	await get_tree().create_timer(2.0).timeout
	Life.call("_update_exposure")
	_label.text = "campfire: fire=%s warmth target=%.0f" % [Life.needs.env.get("fire"), RANeeds.warmth_target(Life.needs.env)]
	print("SURFQA campfire env ", Life.needs.env)
	await get_tree().create_timer(0.2).timeout
	main.get_viewport().get_texture().get_image().save_png(out.path_join("surface_campfire.png"))
	var SI := load("res://scripts/combat/surface_impact.gd")
	for i in 3:
		SI.play(pl, fire.global_position + Vector3(0, 0.3, 0), -fwd, &"stone")
		await get_tree().create_timer(0.03).timeout
	main.get_viewport().get_texture().get_image().save_png(out.path_join("surface_impact.png"))
	var wells := get_tree().root.find_children("WaterSource", "", true, false)
	print("SURFQA wells ", wells.size())
	if not wells.is_empty():
		Life.needs.water = 20.0
		var w: Node3D = wells[0]
		var m1: String = w.call("use")
		Life.needs.water = 95.0
		var m2: String = w.call("use")
		print("SURFQA well ", m1, " | ", m2, " flasks=", Life.count("clean_water"))
		print("SURFQA drink flask: ", Life.use_item("clean_water"))
