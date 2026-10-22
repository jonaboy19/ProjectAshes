class_name AshReplayView
extends Node3D
## The Ashsight presenter: plays an AshMemory incident with pooled ghosts.
##   view.show_incident(mem, incident_id)      start (1x; change `view.cursor.speed`)
##   view.cursor.seek(t)                       scrub bar
##   view.stop()                               leave Ashsight
## `grade` (0..1) is how far the world should be drained to grey: it eases in while a replay
## runs and out when it ends. The HUD or environment reads it (nothing here touches the
## environment). `ground` is an optional Callable(Vector2) -> float that gives terrain height.
## Ghosts are real humanoids playing real clips (see AshGhost / AshGhostClips). `set_speed()`
## gives slow motion; `seek()` / `cursor.playing` drive the scrub bar.
## Cost per frame: one positions_at() plus a transform, a few shader parameters and one
## animation step per ghost, measured in `last_frame_ms` / `worst_frame_ms` (budget 0.3 ms
## for 6 ghosts on HIGH).

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
## Facts about the incident being shown (replay_info), for the scrub bar and captions.
var info: Dictionary = {}

var _active: Dictionary = {}   # actor id -> AshGhost
var _stamp := 0
var _playing := false
## Profiling (microseconds, summed): positions_at, and the terrain height callable.
static var prof_frame_us := 0
static var prof_ground_us := 0
var cam: Camera3D


func _ready() -> void:
	_ensure_pool()


func _ensure_pool() -> void:
	if pool == null:
		pool = AshGhostPool.new()
	if pool.get_parent() == null:
		add_child(pool)


func show_incident(memory: AshMemory, incident_id: int, speed: float = 1.0) -> bool:
	_ensure_pool()
	var rp := memory.replay(incident_id, speed)
	if rp == null:
		return false
	stop()
	mem = memory
	cursor = rp
	info = memory.replay_info(incident_id)
	_playing = true
	max_active = 0
	worst_frame_ms = 0.0
	step(0.0)
	return true


## Wait for the pool to build the ghosts' bodies (optional; ghosts without one show the placeholder).
func warm() -> void:
	_ensure_pool()
	await pool.warm()


## Replay speed multiplier (0.25 slow motion .. 1). The clips follow it.
func set_speed(s: float) -> void:
	if cursor != null:
		cursor.speed = clampf(s, 0.05, 4.0)


func seek(t: float) -> void:
	if cursor != null:
		cursor.seek(t)
		if not cursor.playing:
			step(0.0)   # refresh the pose while paused


## Where an actor's ghost stands now (Vector3.INF when it is not visible).
func ghost_position(actor_id: String) -> Vector3:
	var g: AshGhost = _active.get(actor_id)
	return g.position if g != null else Vector3.INF


## World positions of the ghosts that are visible now (for the camera framing).
func ghost_points(role: String = "") -> Array[Vector3]:
	var out: Array[Vector3] = []
	for id in _active:
		var g: AshGhost = _active[id]
		if role == "" or g.role == role:
			out.append(g.position)
	return out


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
	if is_inside_tree():
		cam = get_viewport().get_camera_3d()
	if _playing and cursor != null:
		cursor.advance(dt)
		grade = minf(1.0, grade + GRADE_IN * dt)
		_stamp += 1
		var tp := Time.get_ticks_usec() if AshGhost.profile else 0
		var frame := cursor.frame()
		if AshGhost.profile:
			prof_frame_us += Time.get_ticks_usec() - tp
		for e: Dictionary in frame:
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
				var tg := Time.get_ticks_usec() if AshGhost.profile else 0
				y += float(ground.call(p))
				if AshGhost.profile:
					prof_ground_us += Time.get_ticks_usec() - tg
			var w := Vector3(p.x, y, p.y)
			if cam != null:
				var d := cam.global_position.distance_to(w)
				# animation LOD: 60 Hz close up, 30 Hz mid, 15 Hz far, 7 Hz very far (one tier less on LOW)
				g.lod = clampi((0 if d < 3.0 else (1 if d < 12.0 else (2 if d < 30.0 else 3))) + (1 if pool.detail == 0 else 0), 0, 3)
			g.apply(e, w, dt, cursor.speed if cursor.playing else 0.0)
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
