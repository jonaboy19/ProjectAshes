extends Node
## QA: two of these (mode 0 = first in the frame, mode 1 = last) bracket every _process / _physics_process callback of the
## scene tree, so a harness can split a frame into "script/tree process", "physics ticks" and "engine rest" (render sync, idle).
static var proc_first := 0
static var proc_last := 0
static var span := 0               # last completed frame's first -> last _process callback (us)
static var phys_us := 0            # summed over the physics ticks since the last take()
static var phys_ticks := 0
static var _pf := 0
var mode := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = -2147483000 if mode == 0 else 2147483000
	process_physics_priority = process_priority


func _process(_d: float) -> void:
	if mode == 0:
		proc_first = Time.get_ticks_usec()
	else:
		proc_last = Time.get_ticks_usec()
		span = proc_last - proc_first


func _physics_process(_d: float) -> void:
	if mode == 0:
		_pf = Time.get_ticks_usec()
	else:
		phys_us += Time.get_ticks_usec() - _pf
		phys_ticks += 1


static func take() -> Array:
	var r := [span, phys_us, phys_ticks]
	phys_us = 0
	phys_ticks = 0
	return r
