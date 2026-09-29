extends Node
## Brief, local animation pause for ordinary weapon impacts. The world clock,
## camera, physics, particles and actors outside the hit keep running.

var _until: Dictionary = {} # AnimationMixer -> [deadline_msec, previous state]


func _ready() -> void:
	set_process(false)


func pause(mixers: Array, seconds: float) -> void:
	var deadline := Time.get_ticks_msec() + roundi(seconds * 1000.0)
	for value: Variant in mixers:
		if not (value is AnimationMixer) or not is_instance_valid(value):
			continue
		var mixer := value as AnimationMixer
		if _until.has(mixer):
			_until[mixer][0] = maxi(int(_until[mixer][0]), deadline)
		elif mixer is AnimationTree:
			if mixer.active:
				_until[mixer] = [deadline, true]
				mixer.active = false
		elif mixer is AnimationPlayer:
			var player := mixer as AnimationPlayer
			if player.active:
				_until[player] = [deadline, player.speed_scale]
				player.speed_scale = 0.0
	set_process(not _until.is_empty())


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	for mixer: AnimationMixer in _until.keys():
		if not is_instance_valid(mixer):
			_until.erase(mixer)
		elif now >= int(_until[mixer][0]):
			_restore(mixer)
			_until.erase(mixer)
	set_process(not _until.is_empty())


func _restore(mixer: AnimationMixer) -> void:
	if mixer is AnimationTree:
		mixer.active = bool(_until[mixer][1])
	elif mixer is AnimationPlayer:
		(mixer as AnimationPlayer).speed_scale = float(_until[mixer][1])


func _exit_tree() -> void:
	for mixer: AnimationMixer in _until.keys():
		if is_instance_valid(mixer):
			_restore(mixer)
	_until.clear()
