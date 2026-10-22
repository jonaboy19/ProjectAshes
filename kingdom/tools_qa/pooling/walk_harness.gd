extends Node
## F12 measurement: a headless player walks 2 km from Thornfield into the forest while the real spawners (ambient
## life, monster camps, frontier wolf packs) stream bodies in and out, wolves are killed along the way and VFX bursts
## fire. Prints one JSON object (and writes it to --out=...).
##   godot --headless --fixed-fps 20 res://tools_qa/pooling/walk_harness.tscn -- --pool=on|off --cells=on|off --out=/path.json [--scale=12]
## pool=off: NodePool.enabled = false (plain new / queue_free, the "before" numbers); cells=off: the cell manager is
## never fed, so every spawner keeps its own distance check.

const NodePool := preload("res://scripts/core/node_pool.gd")
const CreaturePool := preload("res://scripts/core/creature_pool.gd")
const CellStreamer := preload("res://scripts/core/cell_streamer.gd")
const Sites := preload("res://scripts/world/thornfield/sites.gd")

const PATH_LENGTH := 2000.0
const SPEED := 6.5
const SAMPLE := 1.0

var _pool_on := true
var _cells_on := true
var _out := ""
var _scale := 1.0
var _player: Node3D
var _world: Node3D
var _ambient: Node3D
var _camps: Node3D
var _frontier: Node3D
var _from := Vector2.ZERO
var _dir := Vector2.RIGHT
var _walked := 0.0
var _clock := 0.0
var _next_sample := 0.0
var _next_kill := 10.0
var _next_fx := 2.0
var _samples: Array = []
var _last_alloc := 0
var _booted := false
var _frames := 0
var _peak_nodes := 0
var _peak_alloc_s := 0
var _peak_alloc_steady := 0     # after the first STEADY_FROM seconds (the town's first fill is a load-time cost)
const STEADY_FROM := 20.0
var _kills := 0
var _fx := 0
var _wall0 := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--pool=off":
			_pool_on = false
		elif a == "--cells=off":
			_cells_on = false
		elif a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--scale="):
			_scale = float(a.substr(8))
	NodePool.enabled = _pool_on


func _boot() -> void:
	_booted = true
	seed(4242)
	var th := Sites.settlement()
	_from = th["pos"] if not th.is_empty() else Vector2(0, 0)
	# Head the way with the most forest in the next 2 km.
	var best := -1.0
	for i in 16:
		var d := Vector2.from_angle(TAU * i / 16.0)
		var dens := 0.0
		for k in 40:
			var q := _from + d * (60.0 + k * 50.0)
			dens += WorldGen.forest_density(q.x, q.y)
		if dens > best:
			best = dens
			_dir = d
	_world = Node3D.new()
	get_tree().root.add_child(_world)
	_player = Node3D.new()
	_player.add_to_group("player")
	_world.add_child(_player)
	_ambient = (load("res://scripts/world/ambient_life.gd") as GDScript).new()
	_world.add_child(_ambient)
	_camps = (load("res://scripts/world/monster_camps.gd") as GDScript).new()
	_world.add_child(_camps)
	_frontier = (load("res://scripts/world/frontier_presence.gd") as GDScript).new()
	_world.add_child(_frontier)
	_place_player(0.0)
	Engine.time_scale = _scale
	_wall0 = Time.get_ticks_msec()
	_last_alloc = NodePool.total_allocations()


func _place_player(walked: float) -> void:
	var p := _from + _dir * walked
	_player.global_position = Vector3(p.x, WorldGen.height(p.x, p.y), p.y)
	for n: Variant in [_ambient, _camps, _frontier]:
		(n as Node3D).set("focus", _player.global_position)
	if _cells_on:
		CellStreamer.shared().update(_player.global_position)


func _process(delta: float) -> void:
	_frames += 1
	if _frames < 3:
		return
	if not _booted:
		_boot()
		return
	var dt := delta * Engine.time_scale
	_clock += dt
	_walked += SPEED * dt
	_place_player(_walked)
	if _clock >= _next_fx:
		_next_fx += 2.0
		_fx += 1
		var at := _player.global_position + Vector3(2, 1, 3)
		(load("res://scripts/vfx/vfx.gd") as GDScript).call("sparks", _world, at, Color(1, 0.7, 0.3), 14)
		(load("res://scripts/vfx/vfx.gd") as GDScript).call("burst", _world, at, "qi", 0.8)
	if _clock >= _next_kill:
		_next_kill += 12.0
		_kill_nearest()
	if _clock >= _next_sample:
		_next_sample += SAMPLE
		_sample()
	if _walked >= PATH_LENGTH:
		_finish()
		get_tree().quit()


func _kill_nearest() -> void:
	var best: Node3D = null
	var bd := 90.0
	for n in get_tree().get_nodes_in_group("combatant"):
		var b := n as Node3D
		if b == null or b == _player or not b.has_method("take_damage") or b.get("dead") == true:
			continue
		var d := b.global_position.distance_to(_player.global_position)
		if d < bd:
			bd = d
			best = b
	if best != null:
		_kills += 1
		best.call("take_damage", 100000, _player, Vector3.ZERO)


func _sample() -> void:
	var nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	_peak_nodes = maxi(_peak_nodes, nodes)
	var alloc := NodePool.total_allocations()
	var per_s := alloc - _last_alloc
	_last_alloc = alloc
	_peak_alloc_s = maxi(_peak_alloc_s, per_s)
	if _clock > STEADY_FROM:
		_peak_alloc_steady = maxi(_peak_alloc_steady, per_s)
	var t := CreaturePool.totals()
	_samples.append({"t": snappedf(_clock, 0.1), "walked": int(_walked), "nodes": nodes, "allocs": per_s,
		"creature_live": t["live"], "creature_idle": t["idle"]})


func _alloc_after(t: float) -> int:
	var n := 0
	for s: Dictionary in _samples:
		if float(s["t"]) > t:
			n += int(s["allocs"])
	return n


func _finish() -> void:
	var t := CreaturePool.totals()
	var emitter := 0
	var em_stats := {}
	if NodePool.shared_pools().has("vfx_emitter"):
		em_stats = NodePool.shared_pools()["vfx_emitter"].stats()
		emitter = int(em_stats["total"])
	var avg_nodes := 0.0
	for s: Dictionary in _samples:
		avg_nodes += float(s["nodes"])
	avg_nodes /= maxf(1.0, _samples.size())
	var result := {
		"pool": _pool_on, "cells": _cells_on, "path_m": int(_walked), "sim_seconds": snappedf(_clock, 0.1),
		"wall_seconds": snappedf((Time.get_ticks_msec() - _wall0) / 1000.0, 0.1),
		"peak_nodes": _peak_nodes, "avg_nodes": snappedf(avg_nodes, 0.1), "final_nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"total_allocations": NodePool.total_allocations(), "peak_allocations_per_s": _peak_alloc_s, "peak_allocations_per_s_after_20s": _peak_alloc_steady,
		"allocs_after_20s": _alloc_after(STEADY_FROM),
		"creature_pools": t, "emitter_pool": em_stats, "emitter_nodes": emitter,
		"kills": _kills, "fx_calls": _fx,
		"awake_sites": {"ambient": CellStreamer.shared().site_count("ambient"), "camps": CellStreamer.shared().site_count("camps")},
		"cell_updates": CellStreamer.shared().updates, "cell_notifications": CellStreamer.shared().notifications,
	}
	var json := JSON.stringify(result, "  ")
	print("POOLING_RESULT ", json)
	if _out != "":
		var f := FileAccess.open(_out, FileAccess.WRITE)
		if f:
			f.store_string(json)
			f.close()
	NodePool.clear_all()
