extends SceneTree
## Headless CPU cost of the pooled combat-feel nodes (no GPU numbers: xvfb/headless render nothing meaningful).
## Run: $G --headless --path . -s res://tools_qa/combat/feel_cost.gd
const ImpactPool := preload("res://scripts/vfx/impact_pool.gd")
const Rings := preload("res://scripts/vfx/telegraph_rings.gd")
const Highlight := preload("res://scripts/combat/enemy_highlight.gd")
const Feel := preload("res://scripts/combat/combat_feel.gd")


func _initialize() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var pool := ImpactPool.at(world)
	var rings := Rings.at(world)
	var hl := Highlight.at(world)
	var actor := Node3D.new()
	world.add_child(actor)
	for i in 3:
		var mi := MeshInstance3D.new()
		mi.mesh = BoxMesh.new()
		actor.add_child(mi)
	await process_frame
	var n := 600
	var spent := 0
	for i in n:
		var a := Time.get_ticks_usec()
		pool.play(Vector3(0, 1, 0), ImpactPool.element_names()[i % 7], i % 3, Vector3.FORWARD)
		spent += Time.get_ticks_usec() - a
		if i % 6 == 0:
			await process_frame            # awaited frames are not counted
	var play_us := float(spent) / n
	var t0 := Time.get_ticks_usec()
	for i in n:
		rings.begin(actor, 2.4, 0.5)
		hl.strike(actor, 0.5)
		hl.clear(actor)
		rings.end(actor)
	var tele_us := float(Time.get_ticks_usec() - t0) / n
	var b := Feel.Budget.new()
	t0 = Time.get_ticks_usec()
	for i in 100000:
		b.request_stop(0.05, float(i) * 0.01)
		Feel.tier_for(i % 5 == 0, false, 2.0, 14, 14.0)
	var budget_us := float(Time.get_ticks_usec() - t0) / 100000.0
	var idle := Time.get_ticks_usec()
	for i in 600:
		await process_frame
	await create_timer(1.0).timeout
	print("FEELCOST impact.play %.1f us/hit | telegraph begin+end %.1f us | budget+tier %.2f us | pool nodes %d | rings nodes %d | active after settle %d"
		% [play_us, tele_us, budget_us, pool.node_count(), rings.node_count(), pool.active_count()])
	quit()
