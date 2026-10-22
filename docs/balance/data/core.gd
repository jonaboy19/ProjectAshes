extends RefCounted
## Shared driver: fine hourly ticking of Life + realm without the 3D world.
var life: Node
var ws: Node
var hub: RefCounted
var job_max_us := {}   # "module.method" -> max usec
var job_tot_us := {}
var errors := 0

func _init(root: Node) -> void:
	life = root.get_node("Life")
	ws = root.get_node("WorldSim")
	hub = life.realm

func drain_timed() -> void:
	while not hub._queue.is_empty():
		var j: Array = hub._queue.pop_front()
		var t0 := Time.get_ticks_usec()
		hub._run_job(j)
		var dt := Time.get_ticks_usec() - t0
		var key: String = (str(j[0]) + "." + str(j[1])) if not (j[1] is Callable) else "chunk"
		if j[1] is Callable:
			key = "chunk"
		job_max_us[key] = maxi(int(job_max_us.get(key, 0)), dt)
		job_tot_us[key] = int(job_tot_us.get(key, 0)) + dt

func hour(day: int, h: int) -> void:
	ws.day = day
	ws.time_of_day = float(h)
	ws.hour_changed.emit(h)
	drain_timed()

func days(from_day: int, n: int) -> void:
	for d in range(from_day, from_day + n):
		for h in range(0, 24):
			hour(d, h)
