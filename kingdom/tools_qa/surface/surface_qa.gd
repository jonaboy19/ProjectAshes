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
	for k: String in spots:
		await _visit(k, spots[k])
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
