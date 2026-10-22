extends Node
## Full-game headless probe for the perception / witness work (docs/research/MINING_PERCEPTION_INTERACTION.md):
##  1. cost of Villager._perceive per 60 Hz frame for the 24 near bodies (Perception.profile),
##  2. the scenario: a theft in daylight (walking) vs at night (crouched) gives different witness counts, and a
##     witness silenced before reaching a guard leaves the crime unrecorded.
##
##   $G --headless --path . res://tools_qa/perception/perception_probe.tscn -- [--town=Thornfield] [--frames=600]
## Prints lines starting with "PROBE".

const MAIN := "res://scenes/main.tscn"
const NpcWorld := preload("res://scripts/population/npc_world.gd")
const Perception := preload("res://scripts/population/perception.gd")
const Witness := preload("res://scripts/population/witness.gd")
const Evidence := preload("res://scripts/population/evidence.gd")

var main: Node
var player: Node3D
var frames := 600
var town := "Thornfield"
var hour := 13.0
var _frozen := false
var _sid := 0
var _centre := Vector2.ZERO


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and "=" in arg:
			var kv := arg.substr(2).split("=", true, 1)
			match kv[0]:
				"frames": frames = int(kv[1])
				"town": town = kv[1]
	main = (load(MAIN) as PackedScene).instantiate()
	add_child(main)
	_run()


func _process(_delta: float) -> void:
	if _frozen:
		WorldSim.time_of_day = hour


func _soc() -> RefCounted:
	return NpcWorld._society()


func _crimes() -> int:
	var s := _soc()
	return (s.get("crimes") as Array).size() if s != null else -1


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _measure_cost(label: String) -> void:
	Perception.profile = true
	Perception.prof_usec = 0
	Perception.prof_calls = 0
	var phys0 := Engine.get_physics_frames()
	await _frames(frames)
	var ticks := maxi(Engine.get_physics_frames() - phys0, 1)
	Perception.profile = false
	var per_call := float(Perception.prof_usec) / maxf(float(Perception.prof_calls), 1.0)
	var per_frame_ms := float(Perception.prof_usec) / float(ticks) / 1000.0
	print("PROBE cost %s: %d perceive calls, %.1f us/call, %.4f ms per 60Hz physics frame (budget 0.5), villagers=%d ok=%s" % [
		label, Perception.prof_calls, per_call, per_frame_ms, get_tree().get_nodes_in_group("villager").size(), str(per_frame_ms <= 0.5)])


func _theft(label: String, at_hour: float, crouch: bool) -> Dictionary:
	hour = at_hour
	WorldSim.time_of_day = hour
	player.set("crouching", crouch)
	await _frames(40)       # NpcWorld.refresh picks up stance + environment
	var here := Vector2(player.global_position.x, player.global_position.z)
	Witness.reset()
	var before := _crimes()
	var r := NpcWorld.report_crime(get_tree(), "robbery", here, _sid, true)
	print("PROBE theft %s (hour %.0f, crouched=%s): seen_by=%d heard_by=%d pending=%s light=%.2f" % [
		label, hour, str(crouch), int(r.get("seen_by", 0)), int(r.get("heard_by", 0)), str(r.get("pending", false)), Perception.light_at(here)])
	return {"seen": int(r.get("seen_by", 0)), "before": before, "case": int(r.get("case", 0))}


func _run() -> void:
	while not (main and main.get("player") != null and main.player.is_inside_tree() and main.get("hud") != null \
			and (not is_instance_valid(main.hud._loading) or not main.hud._loading.visible)):
		await get_tree().process_frame
	player = main.player
	Life.life_path.set_age(18, WorldSim.day, WorldSim.time_of_day)
	player.call("apply_age")
	var s: Dictionary = {}
	for t: Dictionary in WorldGen.settlements:
		if t["name"] == town:
			s = t
	_sid = int(s["id"])
	_centre = s["pos"]
	Quality.npc_full = 24
	WorldSim.time_of_day = hour
	_frozen = true
	main._teleport(_centre + Vector2(0.0, 6.0), 0.0)
	await _frames(300)
	print("PROBE villagers=", get_tree().get_nodes_in_group("villager").size(), " guards among them=",
		get_tree().get_nodes_in_group("villager").filter(func(v: Node) -> bool: return WorldSim.job[int(v.get("person"))] == 3).size())
	await _measure_cost("daylight standing")
	player.set("crouching", true)
	hour = 1.0
	await _measure_cost("night crouched")
	player.set("crouching", false)
	# A witness stopped before reaching a guard: silence every running reporter -> unreported, nothing recorded.
	hour = 13.0
	await _frames(40)
	var here := Vector2(player.global_position.x, player.global_position.z)
	var before := _crimes()
	var r := NpcWorld.report_crime(get_tree(), "robbery", here, _sid, true)
	var cid := int(r.get("case", 0))
	var ws_states: Array = (Witness.case_of(cid).get("ws", []) as Array).map(func(w: Dictionary) -> String: return Witness.WNAMES[int(w["state"])])
	print("PROBE silence scenario case ", cid, " witness states at start: ", ws_states)
	var silenced := 0
	for v in get_tree().get_nodes_in_group("villager"):
		if bool(v.get("_reporter")):
			v.call("silence")
			silenced += 1
	Witness.tick(Time.get_ticks_msec() + 60000, _soc())
	print("PROBE silenced %d witnesses: case=%s crimes %d -> %d recorded_none=%s" % [
		silenced, Witness.status(cid), before, _crimes(), str(_crimes() == before)])
	# Scenario: the same theft in daylight vs at night, crouched.
	var day := await _theft("daylight", 13.0, false)
	var day_case := Witness.status(int(day["case"]))
	await get_tree().create_timer(6.0).timeout
	print("PROBE daylight case after 6 s: ", Witness.status(int(day["case"])), " (was ", day_case, "), crimes ", day["before"], " -> ", _crimes())
	var night := await _theft("night crouched", 1.0, true)
	print("PROBE witnesses: daylight=%d night_crouched=%d differ=%s" % [int(day["seen"]), int(night["seen"]), str(int(day["seen"]) != int(night["seen"]))])
	print("PROBE evidence entries after crimes: ", Evidence.count)
	get_tree().quit()
