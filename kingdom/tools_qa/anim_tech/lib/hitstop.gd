extends Node
## Hitstop / impact freeze. Two flavours:
##
##   freeze_local(mixers, seconds)  -- pauses only the given AnimationPlayers / AnimationTrees
##                                     (attacker + victim); the rest of the world keeps moving.
##                                     This is the one to use in a multi-actor game.
##   freeze_global(seconds, scale)  -- Engine.time_scale dip (0.02 default) for a big finisher.
##                                     Timed in real time, so it always recovers; physics,
##                                     particles, tweens and audio pitch slow with it.
##
## Both are re-entrant: a new hit extends the freeze (max of end times) instead of stacking.
## Usage:
##   const Hitstop := preload("res://tools_qa/anim_tech/lib/hitstop.gd")
##   var hs := Hitstop.new(); add_child(hs)
##   hs.freeze_local([attacker_anim, victim_anim], 0.07)
##   hs.freeze_global(0.12)
## Recommended durations (60 fps): light 0.04-0.06 s, heavy 0.08-0.10 s, kill / finisher 0.12-0.18 s.
## Cost: one _process check per frame while a freeze is active, nothing otherwise.

var _locals: Dictionary = {}     # AnimationMixer -> [end_msec, previous speed_scale]
var _global_end := 0
var _prev_scale := 1.0
var _global_on := false


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)


func freeze_local(mixers: Array, seconds: float, speed := 0.0) -> void:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	for m: Variant in mixers:
		if not (m is AnimationMixer) or not is_instance_valid(m):
			continue
		var mixer := m as AnimationMixer
		if _locals.has(mixer):
			_locals[mixer][0] = maxi(_locals[mixer][0], end)
		else:
			_locals[mixer] = [end, _get_rate(mixer)]
			_set_rate(mixer, speed)
	set_process(true)


## AnimationPlayer has speed_scale; AnimationTree does not, so a tree is frozen by switching it inactive (it keeps its pose).
func _get_rate(m: AnimationMixer) -> float:
	if m is AnimationTree:
		return 1.0 if m.active else 0.0
	return (m as AnimationPlayer).speed_scale


func _set_rate(m: AnimationMixer, rate: float) -> void:
	if m is AnimationTree:
		m.active = rate > 0.001
	else:
		(m as AnimationPlayer).speed_scale = rate


func freeze_global(seconds: float, scale := 0.02) -> void:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	if not _global_on:
		_prev_scale = Engine.time_scale
		_global_on = true
	Engine.time_scale = scale
	_global_end = maxi(_global_end, end)
	set_process(true)


func is_frozen() -> bool:
	return _global_on or not _locals.is_empty()


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	for m: AnimationMixer in _locals.keys():
		if not is_instance_valid(m):
			_locals.erase(m)
		elif now >= _locals[m][0]:
			_set_rate(m, _locals[m][1])
			_locals.erase(m)
	if _global_on and now >= _global_end:
		Engine.time_scale = _prev_scale
		_global_on = false
	set_process(is_frozen())


func _exit_tree() -> void:
	if _global_on:
		Engine.time_scale = _prev_scale
	for m: AnimationMixer in _locals.keys():
		if is_instance_valid(m):
			_set_rate(m, _locals[m][1])
