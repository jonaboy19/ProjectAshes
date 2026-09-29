class_name AshMemory
extends Region1Sim
## N4 Ashsight (package L11): the world remembers. Significant events (raids, sabotage,
## fires, deaths) near FLAGGED SITES (stones, farms, ambush spots) are recorded together with
## the paths of the actors involved, sampled at 1 Hz within 60 m of the event. The evidence
## COOLS with game time (a raid stays readable for days, a fire for less); once cold, it is
## gone. Kneel at a site and Ashsight replays what really happened, from this record, not
## from a script.
##
## Pure data (RefCounted, JSON-safe, no scene tree). Times passed in (`now_s`) are plain
## seconds on any monotonic clock the emitter likes (WorldSim clock, `Time`, a test clock).
## Cooling runs in game days through the normal `tick(dt_days)`.
##
## Recording (emitters, hook code for C6 is in docs/regions/HOOKS_FOR_CLOUD.md):
##   AshMemory.flag_site_static(name, pos)                    once per stone / farm / ambush spot
##   var id := mem.begin_incident(&"raid", pos, now_s)         when a raid / sabotage starts
##   mem.sample(now_s, [{"id": "b1", "role": "bandit", "pos": Vector2}, ...])   every second
##   mem.mark(id, now_s, "chisel")                             optional labelled beat
##   mem.end_incident(id, now_s)
##   mem.record_event(&"fire", pos, now_s, actors)             one-shot (fire, death)
## Replaying:
##   mem.incidents_near(pos, 40.0)  ->  [ids], strongest heat first
##   var rp := mem.replay(id)       ->  AshMemory.Replay (advance(dt), seek(t), frame())
##   mem.positions_at(id, t)        ->  [{id, role, pos, heading, alpha}], stateless

const KINDS := [&"raid", &"sabotage", &"fire", &"death"]
## Days a kind stays readable (heat goes 1 -> 0 linearly).
const COOL_DAYS := {&"raid": 3.0, &"sabotage": 5.0, &"fire": 2.0, &"death": 4.0}
const SITE_FLAG_RADIUS := 80.0      ## an incident must start within this of a flagged site
const SAMPLE_RADIUS := 60.0         ## actors within this of the incident centre are sampled
const SAMPLE_INTERVAL := 1.0        ## seconds between path samples (1 Hz)
const MAX_INCIDENTS := 24           ## ring buffer size
const MAX_EVENTS := 128             ## light log of every reported event, for rumours / UI
const MAX_ACTORS := 12              ## per incident
const MAX_SAMPLES := 180            ## per actor (three minutes of 1 Hz)
const RECORD_WINDOW_S := 180.0      ## an open incident stops recording after this long
const GAP_S := 2.6                  ## a hole in the samples longer than this = actor out of sight
const FADE_S := 0.7                 ## ghost fade in/out around its first/last sample
const SAVE_STATE_VERSION := 1

signal incident_started(id: int, kind: StringName)
signal incident_cooled(id: int)

## [{id, name, x, z, radius}]
var sites: Array[Dictionary] = []
## Ring buffer of every reported event: [{kind, x, z, day, incident}]
var events: Array[Dictionary] = []
## [{id, kind, x, z, born_day, cool_days, open, t0, dur, site, actors: {aid: {role, t: [], x: [], z: []}}, marks: [{t, label}]}]
var incidents: Array[Dictionary] = []

var _next_id := 1
var _next_site := 1
var _last_sample_s := -1.0e9


func _init() -> void:
	module_name = &"ash_memory"
	state_version = SAVE_STATE_VERSION


# --- sites ---------------------------------------------------------------------------

func flag_site(site_name: String, pos: Vector2, radius: float = SITE_FLAG_RADIUS) -> int:
	for s in sites:
		if String(s["name"]) == site_name:
			s["x"] = _q(pos.x)
			s["z"] = _q(pos.y)
			return int(s["id"])
	var id := _next_site
	_next_site += 1
	sites.append({"id": id, "name": site_name, "x": _q(pos.x), "z": _q(pos.y), "radius": radius})
	return id


func unflag_site(id: int) -> void:
	for s in sites:
		if int(s["id"]) == id:
			sites.erase(s)
			return


## The flagged site covering `pos`, or {}.
func site_near(pos: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var bd := 1.0e18
	for s in sites:
		var d := pos.distance_to(Vector2(float(s["x"]), float(s["z"])))
		if d <= float(s["radius"]) and d < bd:
			bd = d
			best = s
	return best


## Static shortcut for emitters: flag a site on the live module. False when it is not running.
static func flag_site_static(site_name: String, pos: Vector2) -> bool:
	var m := Region1State.sim(&"ash_memory") as AshMemory
	if m == null:
		return false
	m.flag_site(site_name, pos)
	return true


## Static shortcut for emitters that only know "something happened here" (C6 hooks).
## Returns the incident id or -1.
static func report(kind: StringName, pos: Vector2, now_s: float, actors: Array = []) -> int:
	var m := Region1State.sim(&"ash_memory") as AshMemory
	if m == null:
		return -1
	return m.record_event(kind, pos, now_s, actors)


## Seconds on a monotonic clock for emitters that have no better one. Incidents only use
## differences, and open incidents are closed when a save loads, so this need not persist.
static func clock() -> float:
	return float(Time.get_ticks_msec()) / 1000.0


## C6 emitter API on the live module (all no-ops returning -1/false when it is not running):
##   var id := AshMemory.open(&"raid", pos)          a raid / sabotage starts (needs a flagged site near)
##   AshMemory.sample_now(actors)                    from a 1 Hz timer, actors = [{id, role, pos: Vector2}]
##   AshMemory.close(id)                             it is over
static func open(kind: StringName, pos: Vector2, meta: Dictionary = {}) -> int:
	var m := Region1State.sim(&"ash_memory") as AshMemory
	return m.begin_incident(kind, pos, clock(), meta) if m != null else -1


static func sample_now(actors: Array) -> bool:
	var m := Region1State.sim(&"ash_memory") as AshMemory
	return m.sample(clock(), actors) if m != null else false


static func close(id: int) -> void:
	var m := Region1State.sim(&"ash_memory") as AshMemory
	if m != null:
		m.end_incident(id, clock())


# --- recording -----------------------------------------------------------------------

## Open an incident. Refused (-1) unless a flagged site is near, or `force`. Joins an
## already open incident of the same kind within 30 m instead of duplicating it.
func begin_incident(kind: StringName, pos: Vector2, now_s: float, meta: Dictionary = {}, force := false) -> int:
	var site := site_near(pos)
	_log_event(kind, pos, -1)
	if site.is_empty() and not force:
		return -1
	for inc in incidents:
		if bool(inc["open"]) and StringName(inc["kind"]) == kind \
				and pos.distance_to(Vector2(float(inc["x"]), float(inc["z"]))) < 30.0:
			return int(inc["id"])
	var id := _next_id
	_next_id += 1
	incidents.append({"id": id, "kind": String(kind), "x": _q(pos.x), "z": _q(pos.y), "born_day": day_f,
		"cool_days": float(COOL_DAYS.get(kind, 3.0)), "open": true, "t0": now_s, "dur": 0.0,
		"site": String(site.get("name", meta.get("site", ""))), "actors": {}, "marks": []})
	events[events.size() - 1]["incident"] = id
	while incidents.size() > MAX_INCIDENTS:
		_evict_coldest()
	incident_started.emit(id, kind)
	emit_event(&"incident", {"id": id, "kind": String(kind)})
	return id


## Sample actors for every open incident. Call about once per second; extra calls inside the
## sample interval are ignored, so emitters may call it from a per-frame or timer callback.
## actors: [{id: String|int, role: String, pos: Vector2}]. Returns true when samples were taken.
func sample(now_s: float, actors: Array) -> bool:
	if now_s - _last_sample_s < SAMPLE_INTERVAL - 0.001:
		return false
	_last_sample_s = now_s
	var any := false
	for inc in incidents:
		if not bool(inc["open"]):
			continue
		var t := now_s - float(inc["t0"])
		if t > RECORD_WINDOW_S:
			_close(inc, now_s)
			continue
		var c := Vector2(float(inc["x"]), float(inc["z"]))
		var rec: Dictionary = inc["actors"]
		for a: Dictionary in actors:
			var p: Vector2 = a["pos"]
			if p.distance_squared_to(c) > SAMPLE_RADIUS * SAMPLE_RADIUS:
				continue
			var aid := str(a["id"])
			if not rec.has(aid):
				if rec.size() >= MAX_ACTORS:
					continue
				rec[aid] = {"role": String(a.get("role", "")), "t": [], "x": [], "z": []}
			var tr: Dictionary = rec[aid]
			if (tr["t"] as Array).size() >= MAX_SAMPLES:
				continue
			(tr["t"] as Array).append(_q3(t))
			(tr["x"] as Array).append(_q(p.x))
			(tr["z"] as Array).append(_q(p.y))
			any = true
		inc["dur"] = maxf(float(inc["dur"]), t)
	return any


func mark(id: int, now_s: float, label: String) -> void:
	var inc := incident(id)
	if inc.is_empty():
		return
	(inc["marks"] as Array).append({"t": _q3(now_s - float(inc["t0"])), "label": label})


func end_incident(id: int, now_s: float) -> void:
	var inc := incident(id)
	if not inc.is_empty() and bool(inc["open"]):
		_close(inc, now_s)


## One-shot for events with no motion (a fire, a death): opens, samples once, closes.
func record_event(kind: StringName, pos: Vector2, now_s: float, actors: Array = [], force := false) -> int:
	var id := begin_incident(kind, pos, now_s, {}, force)
	if id < 0:
		return -1
	_last_sample_s = -1.0e9   # force a sample now
	sample(now_s, actors)
	end_incident(id, now_s + 1.0)
	return id


func _close(inc: Dictionary, now_s: float) -> void:
	inc["open"] = false
	inc["dur"] = maxf(float(inc["dur"]), now_s - float(inc["t0"]))


func _log_event(kind: StringName, pos: Vector2, incident_id: int) -> void:
	events.append({"kind": String(kind), "x": _q(pos.x), "z": _q(pos.y), "day": day_f, "incident": incident_id})
	if events.size() > MAX_EVENTS:
		events.pop_front()


func _evict_coldest() -> void:
	var worst := -1
	var wh := 2.0
	for i in incidents.size():
		var h := heat(int(incidents[i]["id"]))
		if not bool(incidents[i]["open"]) and h < wh:
			wh = h
			worst = i
	if worst < 0:
		worst = 0
	var id := int(incidents[worst]["id"])
	incidents.remove_at(worst)
	emit_event(&"evicted", {"id": id})


# --- cooling & queries ---------------------------------------------------------------

## 1.0 fresh ... 0.0 cold. 0 for an unknown id.
func heat(id: int) -> float:
	var inc := incident(id)
	if inc.is_empty():
		return 0.0
	return clampf(1.0 - (day_f - float(inc["born_day"])) / maxf(0.01, float(inc["cool_days"])), 0.0, 1.0)


func readable(id: int) -> bool:
	return heat(id) > 0.0


func incident(id: int) -> Dictionary:
	for inc in incidents:
		if int(inc["id"]) == id:
			return inc
	return {}


## Readable incidents within `radius` of `pos`, hottest first.
func incidents_near(pos: Vector2, radius: float = 40.0) -> Array[int]:
	var out: Array[int] = []
	for inc in incidents:
		var id := int(inc["id"])
		if pos.distance_to(Vector2(float(inc["x"]), float(inc["z"]))) <= radius and heat(id) > 0.0:
			out.append(id)
	out.sort_custom(func(a: int, b: int) -> bool: return heat(a) > heat(b))
	return out


## Strongest heat of any incident within its own sample radius of `pos` (for the compass and
## the "ashes still warm" hint).
func heat_at(pos: Vector2) -> float:
	var best := 0.0
	for inc in incidents:
		if pos.distance_to(Vector2(float(inc["x"]), float(inc["z"]))) <= SAMPLE_RADIUS:
			best = maxf(best, heat(int(inc["id"])))
	return best


func _step(_dt_days: float) -> void:
	var i := incidents.size() - 1
	while i >= 0:
		var id := int(incidents[i]["id"])
		if heat(id) <= 0.0 and not bool(incidents[i]["open"]):
			incidents.remove_at(i)
			incident_cooled.emit(id)
			emit_event(&"cooled", {"id": id})
		i -= 1


# --- replay --------------------------------------------------------------------------

## Static facts for the UI: {kind, site, center: Vector2, duration, heat, marks, actors: [{id, role, first, last}]}.
func replay_info(id: int) -> Dictionary:
	var inc := incident(id)
	if inc.is_empty():
		return {}
	var actors: Array = []
	for aid: String in inc["actors"]:
		var tr: Dictionary = inc["actors"][aid]
		var ts: Array = tr["t"]
		if ts.is_empty():
			continue
		actors.append({"id": aid, "role": String(tr["role"]), "first": float(ts[0]), "last": float(ts[ts.size() - 1])})
	return {"kind": StringName(inc["kind"]), "site": String(inc["site"]),
		"center": Vector2(float(inc["x"]), float(inc["z"])), "duration": float(inc["dur"]),
		"heat": heat(id), "marks": (inc["marks"] as Array).duplicate(true), "actors": actors}


## Raw samples of one actor as a path (for the ember trail and the compass pin).
func trail(id: int, actor_id: Variant) -> PackedVector2Array:
	var out := PackedVector2Array()
	var inc := incident(id)
	if inc.is_empty():
		return out
	var tr: Dictionary = (inc["actors"] as Dictionary).get(str(actor_id), {})
	if tr.is_empty():
		return out
	var xs: Array = tr["x"]
	var zs: Array = tr["z"]
	for i in xs.size():
		out.append(Vector2(float(xs[i]), float(zs[i])))
	return out


## Where everyone was at time `t` (seconds since the incident began). Stateless.
## Entry: {id, role, pos: Vector2, heading: float (radians, yaw for -Z forward models), alpha: 0..1}.
## Actors that are out of sight at `t` (before the first sample, after the last, or inside a
## gap longer than GAP_S) are left out. Uses a Catmull-Rom curve through the 1 Hz samples.
func positions_at(id: int, t: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var inc := incident(id)
	if inc.is_empty():
		return out
	var actors: Dictionary = inc["actors"]
	for aid: String in actors:
		var tr: Dictionary = actors[aid]
		var e := _eval_track(tr, t)
		if e.is_empty():
			continue
		e["id"] = aid
		e["role"] = String(tr["role"])
		out.append(e)
	return out


static func _eval_track(tr: Dictionary, t: float) -> Dictionary:
	var ts: Array = tr["t"]
	var n := ts.size()
	if n == 0:
		return {}
	var t_first := float(ts[0])
	var t_last := float(ts[n - 1])
	if t < t_first - FADE_S or t > t_last + FADE_S:
		return {}
	var xs: Array = tr["x"]
	var zs: Array = tr["z"]
	# segment index i with ts[i] <= t <= ts[i+1] (binary search)
	var tc := clampf(t, t_first, t_last)
	var lo := 0
	var hi := n - 1
	while hi - lo > 1:
		var mid := (lo + hi) >> 1
		if float(ts[mid]) <= tc:
			lo = mid
		else:
			hi = mid
	if n == 1:
		return {"pos": Vector2(float(xs[0]), float(zs[0])), "heading": 0.0, "alpha": _fade(t, t_first, t_last)}
	var t0 := float(ts[lo])
	var t1 := float(ts[lo + 1])
	if t1 - t0 > GAP_S and t > t0 and t < t1:
		# a hole in the record: out of sight, except the fade tails of the two ends
		if t - t0 <= FADE_S:
			return {"pos": Vector2(float(xs[lo]), float(zs[lo])), "heading": _heading(xs, zs, lo, lo), "alpha": 1.0 - (t - t0) / FADE_S}
		if t1 - t <= FADE_S:
			return {"pos": Vector2(float(xs[lo + 1]), float(zs[lo + 1])), "heading": _heading(xs, zs, lo + 1, lo + 1), "alpha": 1.0 - (t1 - t) / FADE_S}
		return {}
	var p0 := Vector2(float(xs[lo]), float(zs[lo]))
	var p1 := Vector2(float(xs[lo + 1]), float(zs[lo + 1]))
	var pm := p0 if lo == 0 else Vector2(float(xs[lo - 1]), float(zs[lo - 1]))
	var tm := t0 if lo == 0 else float(ts[lo - 1])
	var pp := p1 if lo + 2 >= n else Vector2(float(xs[lo + 2]), float(zs[lo + 2]))
	var tp := t1 if lo + 2 >= n else float(ts[lo + 2])
	# neighbours across a gap must not bend the curve
	if t0 - tm > GAP_S:
		pm = p0
		tm = t0
	if tp - t1 > GAP_S:
		pp = p1
		tp = t1
	var h := t1 - t0
	var u := clampf((tc - t0) / maxf(h, 0.0001), 0.0, 1.0)
	var m0 := (p1 - pm) / maxf(t1 - tm, 0.0001) * h if tm < t0 else (p1 - p0)
	var m1 := (pp - p0) / maxf(tp - t0, 0.0001) * h if tp > t1 else (p1 - p0)
	var u2 := u * u
	var u3 := u2 * u
	var pos := (2.0 * u3 - 3.0 * u2 + 1.0) * p0 + (u3 - 2.0 * u2 + u) * m0 \
		+ (-2.0 * u3 + 3.0 * u2) * p1 + (u3 - u2) * m1
	var vel := ((6.0 * u2 - 6.0 * u) * p0 + (3.0 * u2 - 4.0 * u + 1.0) * m0 \
		+ (-6.0 * u2 + 6.0 * u) * p1 + (3.0 * u2 - 2.0 * u) * m1)
	var heading := atan2(-vel.x, -vel.y) if vel.length_squared() > 0.0004 else _heading(xs, zs, lo, lo + 1)
	return {"pos": pos, "heading": heading, "alpha": _fade(t, t_first, t_last)}


static func _heading(xs: Array, zs: Array, a: int, b: int) -> float:
	var i0 := maxi(0, mini(a, b) - 1)
	var i1 := mini(xs.size() - 1, maxi(a, b) + 1)
	var d := Vector2(float(xs[i1]) - float(xs[i0]), float(zs[i1]) - float(zs[i0]))
	return atan2(-d.x, -d.y) if d.length_squared() > 0.0004 else 0.0


static func _fade(t: float, t_first: float, t_last: float) -> float:
	return clampf(minf((t - (t_first - FADE_S)) / FADE_S, ((t_last + FADE_S) - t) / FADE_S), 0.0, 1.0)


## A playback cursor (not saved): advance(dt) each frame, frame() -> positions_at(t).
func replay(id: int, speed: float = 1.0) -> Replay:
	if not readable(id):
		return null
	var r := Replay.new()
	r.mem = self
	r.incident_id = id
	r.duration = float(incident(id).get("dur", 0.0))
	r.speed = speed
	return r


class Replay extends RefCounted:
	var mem: AshMemory
	var incident_id := -1
	var t := 0.0
	var duration := 0.0
	var speed := 1.0
	var playing := true
	var looping := false
	## Extra seconds shown after the last sample so the last ghost can fade out.
	var tail := AshMemory.FADE_S

	func advance(dt: float) -> void:
		if not playing:
			return
		t += dt * speed
		var end := duration + tail
		if t >= end:
			if looping:
				t = fposmod(t, maxf(end, 0.001))
			else:
				t = end
				playing = false

	func seek(seconds: float) -> void:
		t = clampf(seconds, 0.0, duration + tail)

	func progress() -> float:
		return t / maxf(duration + tail, 0.001)

	func finished() -> bool:
		return t >= duration + tail - 1e-6 and not playing

	func frame() -> Array[Dictionary]:
		return mem.positions_at(incident_id, t)


# --- persistence ---------------------------------------------------------------------

func _save_state() -> Dictionary:
	return {"sites": sites.duplicate(true), "events": events.duplicate(true),
		"incidents": incidents.duplicate(true), "next_id": _next_id, "next_site": _next_site}


func _load_state(d: Dictionary) -> void:
	sites.clear()
	for s: Dictionary in d.get("sites", []):
		sites.append({"id": int(s["id"]), "name": String(s["name"]), "x": float(s["x"]), "z": float(s["z"]),
			"radius": float(s.get("radius", SITE_FLAG_RADIUS))})
	events.clear()
	for e: Dictionary in d.get("events", []):
		events.append({"kind": String(e["kind"]), "x": float(e["x"]), "z": float(e["z"]),
			"day": float(e["day"]), "incident": int(e.get("incident", -1))})
	incidents.clear()
	for i: Dictionary in d.get("incidents", []):
		var actors := {}
		for aid: String in i.get("actors", {}):
			var tr: Dictionary = i["actors"][aid]
			var ts: Array = []
			var xs: Array = []
			var zs: Array = []
			for v: Variant in tr["t"]: ts.append(float(v))
			for v: Variant in tr["x"]: xs.append(float(v))
			for v: Variant in tr["z"]: zs.append(float(v))
			actors[aid] = {"role": String(tr.get("role", "")), "t": ts, "x": xs, "z": zs}
		var marks: Array = []
		for m: Dictionary in i.get("marks", []):
			marks.append({"t": float(m["t"]), "label": String(m["label"])})
		incidents.append({"id": int(i["id"]), "kind": String(i["kind"]), "x": float(i["x"]), "z": float(i["z"]),
			"born_day": float(i["born_day"]), "cool_days": float(i["cool_days"]), "open": false,   # a loaded save never resumes recording
			"t0": float(i["t0"]), "dur": float(i["dur"]), "site": String(i.get("site", "")),
			"actors": actors, "marks": marks})
	_next_id = int(d.get("next_id", 1))
	_next_site = int(d.get("next_site", 1))
	_last_sample_s = -1.0e9


func summary() -> String:
	return "%s sites=%d incidents=%d events=%d" % [super.summary(), sites.size(), incidents.size(), events.size()]


func debug_image(px: int = 256) -> Image:
	# Top-down plot of every incident's paths (bandit = warm, villager = blue), for the sandbox.
	var img := Image.create(px, px, false, Image.FORMAT_RGB8)
	img.fill(Color(0.16, 0.15, 0.17))
	if incidents.is_empty():
		return img
	var scale := float(px) / (SAMPLE_RADIUS * 2.4)
	for inc in incidents:
		var c := Vector2(float(inc["x"]), float(inc["z"]))
		var origin := Vector2(px * 0.5, px * 0.5)
		for aid: String in inc["actors"]:
			var tr: Dictionary = inc["actors"][aid]
			var col := Color(1.0, 0.62, 0.3) if String(tr["role"]) == "bandit" else Color(0.6, 0.78, 1.0)
			for i in (tr["t"] as Array).size():
				var p := (Vector2(float(tr["x"][i]), float(tr["z"][i])) - c) * scale + origin
				if p.x >= 0.0 and p.y >= 0.0 and p.x < px and p.y < px:
					img.set_pixelv(Vector2i(p), col)
		break   # one incident per picture is readable enough
	return img


# --- helpers -------------------------------------------------------------------------

## Quantise to centimetres / milliseconds: keeps saves small and JSON round trips exact.
static func _q(v: float) -> float:
	return roundf(v * 100.0) / 100.0


static func _q3(v: float) -> float:
	return roundf(v * 1000.0) / 1000.0
