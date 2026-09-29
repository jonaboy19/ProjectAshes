class_name AshReplayView
extends Node3D
## The Ashsight presenter: plays an AshMemory incident with pooled ghosts.
##   view.show_incident(mem, incident_id)      start (1x; change `view.cursor.speed`)
##   view.cursor.seek(t)                       scrub bar
##   view.stop()                               leave Ashsight
## `grade` (0..1) is how far the world should be drained to grey: it eases in while a replay
## runs and out when it ends. The HUD or environment reads it (nothing here touches the
## environment). `ground` is an optional Callable(Vector2) -> float that gives terrain height.
## Cost per frame: one positions_at() plus a transform per ghost, measured in
## `last_frame_ms` / `worst_frame_ms` (budget 0.3 ms).

signal finished
signal ghost_tapped(actor_id: String)

const GRADE_IN := 2.2   # per second
const GRADE_OUT := 1.6

var pool: AshGhostPool
var mem: AshMemory
var cursor: AshMemory.Replay
var ground: Callable = Callable()
var grade := 0.0
var ground_offset := 0.0
var last_frame_ms := 0.0
var worst_frame_ms := 0.0
var max_active := 0

var _active: Dictionary = {}   # actor id -> AshGhost
var _stamp := 0
var _playing := false


func _ready() -> void:
	_ensure_pool()


func _ensure_pool() -> void:
	if pool == null:
		pool = AshGhostPool.new()
		add_child(pool)


func show_incident(memory: AshMemory, incident_id: int, speed: float = 1.0) -> bool:
	_ensure_pool()
	var rp := memory.replay(incident_id, speed)
	if rp == null:
		return false
	stop()
	mem = memory
	cursor = rp
	_playing = true
	max_active = 0
	worst_frame_ms = 0.0
	step(0.0)
	return true


func stop() -> void:
	_playing = false
	for id in _active:
		pool.release(_active[id])
	_active.clear()
	cursor = null


func is_playing() -> bool:
	return _playing


func _process(delta: float) -> void:
	if _playing or grade > 0.0:
		var t0 := Time.get_ticks_usec()
		step(delta)
		last_frame_ms = float(Time.get_ticks_usec() - t0) / 1000.0
		worst_frame_ms = maxf(worst_frame_ms, last_frame_ms)


## Advance by `dt` seconds (public so tests and the demo can drive it deterministically).
func step(dt: float) -> void:
	if _playing and cursor != null:
		cursor.advance(dt)
		grade = minf(1.0, grade + GRADE_IN * dt)
		_stamp += 1
		for e: Dictionary in cursor.frame():
			var id := String(e["id"])
			var g: AshGhost = _active.get(id)
			if g == null:
				g = pool.acquire(String(e["role"]))
				if g == null:
					continue   # pool exhausted: skip this actor rather than allocate
				_active[id] = g
			g.stamp = _stamp
			var p: Vector2 = e["pos"]
			var y := ground_offset
			if ground.is_valid():
				y += float(ground.call(p))
			g.place(Vector3(p.x, y, p.y), float(e["heading"]), float(e["alpha"]))
		var gone: Array = []
		for id in _active:
			if (_active[id] as AshGhost).stamp != _stamp:
				gone.append(id)
		for id in gone:
			pool.release(_active[id])
			_active.erase(id)
		max_active = maxi(max_active, _active.size())
		if cursor.finished():
			_playing = false
			for id in _active:
				pool.release(_active[id])
			_active.clear()
			finished.emit()
	elif grade > 0.0:
		grade = maxf(0.0, grade - GRADE_OUT * dt)


## Nearest active ghost to a view ray (tap a ghost to pin its trail on the compass).
## Returns the actor id or "".
func pick(ray_origin: Vector3, ray_dir: Vector3, max_dist: float = 0.9) -> String:
	var best := ""
	var bd := max_dist
	for id in _active:
		var g: AshGhost = _active[id]
		var c := g.position + Vector3(0, 0.9, 0)
		var t := maxf(0.0, (c - ray_origin).dot(ray_dir))
		var d := c.distance_to(ray_origin + ray_dir * t)
		if d < bd:
			bd = d
			best = String(id)
	if best != "":
		ghost_tapped.emit(best)
	return best
