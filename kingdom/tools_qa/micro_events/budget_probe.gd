extends Node
## Frame budget of the near-NPC layer in Thornfield: villagers (24 bodies), their utility brains, the street scenes
## (two forced) and the director, measured as script time per frame (NpcWorld.profile).
##
##   $G --headless --path . res://tools_qa/micro_events/budget_probe.tscn -- [--frames=900] [--town=Thornfield] [--hour=15]
## Prints "BUDGET villagers+events ms avg/p95/max per frame" and a baseline without scenes.

const MAIN := "res://scenes/main.tscn"
const NpcWorld := preload("res://scripts/population/npc_world.gd")
const MicroEvents := preload("res://scripts/population/micro_events.gd")
const TownMood := preload("res://scripts/population/town_mood.gd")

var main: Node
var player: Player
var frames := 900
var town := "Thornfield"
var hour := 15.0
var _frozen := false


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and "=" in arg:
			var kv := arg.substr(2).split("=", true, 1)
			match kv[0]:
				"frames": frames = int(kv[1])
				"town": town = kv[1]
				"hour": hour = float(kv[1])
	MicroEvents.verbose = true
	main = (load(MAIN) as PackedScene).instantiate()
	add_child(main)
	_run()


func _process(_delta: float) -> void:
	# freeze the clock: the measurement must see one situation, not a day going by at a few fps
	if _frozen:
		WorldSim.time_of_day = hour


func _measure(label: String, n: int) -> Dictionary:
	# Costs are normalised to one 60 Hz frame whatever the (software-rendered) frame rate: villager physics per
	# physics tick, micro actors + director per rendered frame, the LOD refresh per call / 15.
	var per: Array = []
	NpcWorld.profile = true
	NpcWorld.prof_usec = 0
	NpcWorld.prof_calls = 0
	NpcWorld.prof_frame_usec = 0
	NpcWorld.prof_lod_usec = 0
	NpcWorld.prof_lod_calls = 0
	var slice0: int = WorldSim.dbg_slice_usec
	var frames0: int = WorldSim.dbg_frames
	var phys0 := Engine.get_physics_frames()
	var tot_vill := 0.0
	var tot_other := 0.0
	var tot_lod := 0.0
	for i in n:
		await get_tree().process_frame
		var ticks := maxi(Engine.get_physics_frames() - phys0, 1)
		phys0 = Engine.get_physics_frames()
		var vill := float(NpcWorld.prof_usec) / float(ticks) / 1000.0
		var other := float(NpcWorld.prof_frame_usec) / 1000.0
		var lod := float(NpcWorld.prof_lod_usec) / 15.0 / 1000.0
		NpcWorld.prof_usec = 0
		NpcWorld.prof_frame_usec = 0
		NpcWorld.prof_lod_usec = 0
		tot_vill += vill
		tot_other += other
		tot_lod += lod
		per.append(vill + other + lod)
	NpcWorld.profile = false
	per.sort()
	var sum := 0.0
	for v: float in per:
		sum += v
	var out := {"avg": sum / float(n), "p95": per[int(float(n) * 0.95)], "max": per[n - 1]}
	var slice_ms := float(WorldSim.dbg_slice_usec - slice0) / 1000.0 / maxf(float(WorldSim.dbg_frames - frames0), 1.0)
	print("BUDGET worldsim slice ", label, ": %.3f ms/frame (limit 1.0)" % slice_ms)
	print("BUDGET ", label, " near-NPC script cost per 60Hz frame: avg=%.3f p95=%.3f max=%.3f ms (villager ticks %.3f + micro actors/director %.3f + LOD refresh %.3f), villagers=%d, micro actors=%d" % [
		out["avg"], out["p95"], out["max"], tot_vill / float(n), tot_other / float(n), tot_lod / float(n),
		main.population.full_count, main.population.micro.call("actors_alive")])
	return out


func _run() -> void:
	while not (main and main.get("player") != null and main.player.is_inside_tree() and main.get("hud") != null \
			and (not is_instance_valid(main.hud._loading) or not main.hud._loading.visible)):
		await get_tree().process_frame
	player = main.player
	Life.life_path.set_age(18, WorldSim.day, WorldSim.time_of_day)
	player.apply_age()
	var s: Dictionary = {}
	for t: Dictionary in WorldGen.settlements:
		if t["name"] == town:
			s = t
	Quality.npc_full = 24
	WorldSim.time_of_day = hour
	_frozen = true
	var c: Vector2 = s["pos"]
	main._teleport(c + Vector2(0.0, 6.0), 0.0)
	# let the crowd form (24 bodies) and settle
	for i in 300:
		await get_tree().process_frame
	print("BUDGET villagers=", main.population.full_count, " hour=", WorldSim.time_of_day)
	var micro: Node = main.population.micro
	for sc in (micro.get("active") as Array):
		if is_instance_valid(sc):
			sc.call("finish")
	print("BUDGET measuring baseline")
	var base := await _measure("baseline (no scenes)", frames)
	print("BUDGET spawning scenes")
	print("BUDGET spawn1 ", micro.call("spawn_now", "street_performer"))
	print("BUDGET spawn2 ", micro.call("spawn_now", "merchant_argument"))
	for i in 240:
		await get_tree().process_frame
	print("BUDGET scenes built, measuring")
	var with_events := await _measure("with 2 scenes", frames)
	print("BUDGET result baseline_avg=%.3f with_events_avg=%.3f with_events_p95=%.3f limit=2.0 ok=%s" % [base["avg"], with_events["avg"], with_events["p95"], str(with_events["avg"] <= 2.0)])
	get_tree().quit()
