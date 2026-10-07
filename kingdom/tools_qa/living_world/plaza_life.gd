extends Node
## Town plaza life check (living-world P13): stand at the Kingsreach market plaza and either measure or record.
##   godot --path kingdom --rendering-method mobile --resolution 1280x720 -- --adult --quality=low \
##       --qa=res://tools_qa/living_world/plaza_life.gd [--mode=bench|capture] [--seconds=20] [--hour=10] [--view=wide|near]
## bench: uncapped; after a settle, median / p95 frame ms, draw calls, villager script ms/frame and tier counts.
## capture: run under --write-movie (fixed fps); the camera slowly orbits the plaza centre, or --view=near stays on the
## nearest villager group. Prints a PLAZA line every second with tier counts.
var main: Node
var mode := "bench"
var seconds := 20.0
var view := "wide"
var t := 0.0
var centre := Vector2.ZERO
var plaza_r := 10.0
var buf := PackedFloat32Array()
var draws := PackedFloat32Array()
var frames0 := 0
var prof_on := false
var _last_print := 0.0
const NpcWorld := preload("res://scripts/population/npc_world.gd")
const SETTLE := 12.0


func run(m: Node) -> void:
	main = m
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--mode="):
			mode = s.get_slice("=", 1)
		elif s.begins_with("--seconds="):
			seconds = float(s.get_slice("=", 1))
		elif s.begins_with("--view="):
			view = s.get_slice("=", 1)
		elif s.begins_with("--hour="):
			WorldSim.time_of_day = float(s.get_slice("=", 1))
	if not OS.get_cmdline_user_args().has("--hour=") and WorldSim.time_of_day == 0.0:
		WorldSim.time_of_day = 10.0
	var st: Dictionary = WorldGen.settlements[1]
	centre = st["pos"]
	plaza_r = float(st["plan"]["plaza_r"])
	var p := centre + Vector2(plaza_r + 3.0, 0.0)
	main.call("_teleport", p, PI * 0.5)
	_aim(0.0)


func _aim(a: float) -> void:
	var r := plaza_r + (3.0 if view == "wide" else -1.0)
	var p := centre + Vector2(cos(a), sin(a)) * r
	main.call("_teleport", p, a)
	var to := centre - p
	main.player.set_camera(atan2(-to.x, -to.y), -0.10 if view == "wide" else -0.05)


var _placed := false


## Stand 5 m from the densest cluster of embodied villagers (once), so the recording shows them close up.
func _place_near_crowd() -> void:
	_placed = true
	var vs: Array = main.population.get("_villagers")
	if vs == null or vs.size() < 2:
		return
	var best: Node3D = null
	var best_n := -1
	for a in vs:
		var k := 0
		for b in vs:
			if (a as Node3D).global_position.distance_to((b as Node3D).global_position) < 8.0:
				k += 1
		if k > best_n:
			best_n = k
			best = a
	var c: Vector3 = best.global_position
	var to2 := Vector2(centre.x - c.x, centre.y - c.z)
	var off := to2.normalized() * (3.5 if view == "near" else 9.0)
	main.call("_teleport", Vector2(c.x, c.z) + off, 0.0)


func _look_at_crowd() -> void:
	if not _placed:
		_place_near_crowd()
	# The player stands still at the plaza; the camera follows the centroid of the embodied villagers.
	var vs: Array = main.population.get("_villagers")
	if vs == null or vs.is_empty():
		return
	var c := Vector3.ZERO
	var n := 0
	for v in vs:
		if is_instance_valid(v):
			c += (v as Node3D).global_position
			n += 1
	if n == 0:
		return
	c /= n
	var to: Vector3 = c - (main.player as Node3D).global_position
	main.player.set_camera(atan2(-to.x, -to.z), -0.12)


func _process(delta: float) -> void:
	if main == null:
		return
	t += delta
	if mode == "bench":
		Engine.max_fps = 0
	if t < SETTLE:
		return
	if mode == "capture":
		_look_at_crowd()
		if t - _last_print > 1.0:
			_last_print = t
			_print_state()
		if t > SETTLE + seconds:
			get_tree().quit(0)
		return
	if not prof_on:
		prof_on = true
		NpcWorld.profile = true
		NpcWorld.prof_usec = 0
		NpcWorld.prof_calls = 0
		frames0 = Engine.get_process_frames()
	buf.append(delta * 1000.0)
	draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	if t > SETTLE + seconds:
		NpcWorld.profile = false
		var fr := maxi(1, Engine.get_process_frames() - frames0)
		var sorted := buf.duplicate()
		sorted.sort()
		var dsorted := draws.duplicate()
		dsorted.sort()
		var pl: Node = main.population
		print("PLAZA_BENCH tier=%d frame_med=%.2f frame_p95=%.2f frame_mean=%.2f draws_med=%d villager_script=%.3f ms/frame calls=%d full=%d sprites=%d" % [
			int(Quality.tier), sorted[sorted.size() / 2], sorted[int(sorted.size() * 0.95)], _mean(buf), int(dsorted[dsorted.size() / 2]),
			NpcWorld.prof_usec / 1000.0 / fr, NpcWorld.prof_calls, pl.full_count, pl.sprite_count])
		_print_state()
		get_tree().quit(0)


func _print_state() -> void:
	var pl: Node = main.population
	var extra := ""
	if pl.get("_anim_lod") != null:
		var l = pl.get("_anim_lod")
		extra = " tiers=%s anim_lod_us=%d" % [str(l.counts), l.cpu_usec]
	var v = pl.get("_vat")
	if v != null:
		extra += " vat=%d" % v.crowd.count() if v.crowd.has_method("count") else ""
	print("PLAZA t=%.0f full=%d sprites=%d draws=%d%s" % [t, pl.full_count, pl.sprite_count,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), extra])


func _mean(a: PackedFloat32Array) -> float:
	var s := 0.0
	for x in a:
		s += x
	return s / maxf(1.0, a.size())
