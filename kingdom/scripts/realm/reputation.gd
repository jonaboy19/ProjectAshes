extends "res://scripts/realm/realm_module.gd"
## Multi-axis reputation (docs/design/LIVING_WORLD_SANDBOX.md section 7, LW-6.2).
## A subject (an individual, household, town, faction, religion, army or kingdom) has nine axes, -100..100:
##   competence reliability generosity cruelty legitimacy wealth strength influence trust
## There are two layers. The TRUTH is what the subject has actually done. A BELIEF is what one observer (a town, a faction, a
## kingdom ...) has heard. A deed is seen where it happens; everywhere else the news travels as a report through messengers
## (fast, accurate), traders (slow, fair) and rumours (slowest, garbled), so far-off towns are late and may be wrong:
## a rumour can be exaggerated, shrunk or even turned around. Nothing here is per frame; reports are a day-bucket queue.
##
## Keys are "<scope>:<id>" with scope i h t f r a k, e.g. "i:player", "t:3", "k:caldrenn".
##   record(subject, axis, delta, sid, channel, opts)   a deed; opts {groups: [observer keys], house: "h:..", channels: [..]}
##   on_deed(subject, deed, sid, magnitude, opts)       a named deed moves several axes at once
##   view(subject, observer) / standing(subject, sid)   what an observer believes

const PD := preload("res://scripts/realm/politics_data.gd")
const Events := preload("res://scripts/realm/events.gd")

const CHANNELS := {
	"messenger": {"speed": 220.0, "fid": 0.97, "reach": 12},
	"trader": {"speed": 90.0, "fid": 0.85, "reach": 6},
	"rumour": {"speed": 45.0, "fid": 0.6, "reach": 4},
}
const GROUP_DELAY := {"messenger": 1, "trader": 4, "rumour": 7, "witness": 0}
const SUBJECT_MAX := 400
const OBSERVER_MAX := 24
const PENDING_MAX := 800
const DELIVER_PER_DAY := 120
const AXIS_LIMIT := 100.0
## deed -> {axis: delta at magnitude 1}
const DEEDS := {
	"paid_debt": {"reliability": 4.0, "trust": 3.0},
	"broke_promise": {"reliability": -9.0, "trust": -6.0, "legitimacy": -2.0},
	"gift": {"generosity": 6.0, "influence": 1.0},
	"charity": {"generosity": 8.0, "trust": 2.0, "legitimacy": 1.0},
	"stole": {"reliability": -5.0, "legitimacy": -6.0, "trust": -5.0},
	"murder": {"cruelty": 14.0, "legitimacy": -12.0, "trust": -10.0},
	"executed": {"cruelty": 8.0, "strength": 2.0},
	"won_battle": {"strength": 8.0, "competence": 4.0, "influence": 3.0},
	"lost_battle": {"strength": -7.0, "competence": -4.0},
	"built": {"competence": 4.0, "wealth": 2.0},
	"kept_order": {"competence": 3.0, "legitimacy": 2.0, "trust": 2.0},
	"bribed": {"legitimacy": -8.0, "reliability": -3.0, "wealth": 2.0},
	"neglected_office": {"competence": -8.0, "reliability": -6.0, "legitimacy": -3.0},
	"fair_ruling": {"legitimacy": 5.0, "trust": 4.0, "competence": 2.0},
	"treaty_kept": {"reliability": 5.0, "trust": 4.0},
	"treaty_broken": {"reliability": -14.0, "trust": -10.0, "legitimacy": -4.0},
	"married_well": {"influence": 6.0, "wealth": 3.0},
	"seized": {"strength": 4.0, "cruelty": 4.0, "legitimacy": -9.0},
	"recognised": {"legitimacy": 10.0, "influence": 4.0},
	"hoarded": {"wealth": 5.0, "generosity": -5.0},
}

var _truth: Dictionary = {}     # subject -> {axis: v}
var _bel: Dictionary = {}       # subject -> {observer: {axis: v, d: day}}
var _in: Dictionary = {}        # str(day) -> [[subject, observer, axis, delta, channel, id], ...]
var _pending := 0
var _next := 1
var _day := 0
var _towns: Array = []          # [[sid, Vector2]] cache, not saved
var stats := {"recorded": 0, "delivered": 0, "garbled": 0, "dropped": 0}


static func key(scope: String, id: Variant) -> String:
	return "%s:%s" % [scope, str(id)]


func _now() -> int:
	return maxi(_day, 0)


func _town_list() -> Array:
	if _towns.is_empty():
		for s: Dictionary in WorldGen.settlements:
			_towns.append([int(s["id"]), s["pos"]])
	return _towns


func _empty_axes() -> Dictionary:
	var d := {}
	for a: String in PD.AXES:
		d[a] = 0.0
	return d


func _clampv(v: float) -> float:
	return snappedf(clampf(v, -AXIS_LIMIT, AXIS_LIMIT), 0.001)


# ------------------------------------------------------------------ writing

## A deed on one axis. It lands at once in the town where it happened (and the subject's truth), then travels.
func record(subject: String, axis: String, delta: float, sid: int, channel := "witness", opts: Dictionary = {}) -> int:
	if not (axis in PD.AXES) or subject == "" or is_zero_approx(delta):
		return 0
	_day = maxi(_day, PD.today())
	var t: Dictionary = _truth.get(subject, {})
	if t.is_empty():
		if _truth.size() >= SUBJECT_MAX:
			_evict()
		t = _empty_axes()
		_truth[subject] = t
	t[axis] = _clampv(float(t[axis]) + delta)
	var rid := _next
	_next += 1
	stats["recorded"] = int(stats["recorded"]) + 1
	if sid >= 0:
		_believe(subject, "t:%d" % sid, axis, delta)
	for g: Variant in opts.get("groups", []):
		_schedule(subject, String(g), axis, delta, channel if channel != "witness" else "messenger", GROUP_DELAY.get(channel if channel != "witness" else "messenger", 1), rid)
	var house := String(opts.get("house", ""))
	if house != "":
		_schedule(subject, house, axis, delta * 0.5, "messenger", 0, rid)
	var chans: Array = opts.get("channels", ["rumour", "trader"] if absf(delta) < 8.0 else ["rumour", "trader", "messenger"])
	if sid >= 0 and channel != "none":
		for c: String in chans:
			_spread(subject, axis, delta, sid, c, rid)
	return rid


func _spread(subject: String, axis: String, delta: float, from_sid: int, channel: String, rid: int) -> void:
	var spec: Dictionary = CHANNELS.get(channel, {})
	if spec.is_empty():
		return
	var here := Vector2.ZERO
	for t: Array in _town_list():
		if int(t[0]) == from_sid:
			here = t[1]
	var cands: Array = []
	for t: Array in _town_list():
		if int(t[0]) != from_sid:
			cands.append([here.distance_to(t[1]), int(t[0])])
	cands.sort()
	var n := mini(int(spec["reach"]), cands.size())
	for i in n:
		var d := float(cands[i][0])
		var arrive := _now() + maxi(1, int(ceil(d / float(spec["speed"]))))
		_schedule(subject, "t:%d" % int(cands[i][1]), axis, delta, channel, arrive - _now(), rid)


func _schedule(subject: String, observer: String, axis: String, delta: float, channel: String, delay: int, rid: int) -> void:
	if _pending >= PENDING_MAX:
		stats["dropped"] = int(stats["dropped"]) + 1
		return
	if delay <= 0:
		_deliver([subject, observer, axis, delta, channel, rid])
		return
	var k := str(_now() + delay)
	if not _in.has(k):
		_in[k] = []
	(_in[k] as Array).append([subject, observer, axis, delta, channel, rid])
	_pending += 1


## Hearsay is distorted by the channel: fidelity below 1 can shrink, inflate or even reverse the news.
func _distort(delta: float, channel: String, observer: String, rid: int) -> float:
	var fid := float((CHANNELS.get(channel, {"fid": 1.0}) as Dictionary)["fid"])
	if fid >= 1.0:
		return delta
	var h := absi(hash([WorldSim.SEED, "repn", rid, observer]))
	var u1 := float(h % 1000) / 1000.0
	var u2 := float((h / 1000) % 1000) / 1000.0
	var u3 := float((h / 1000000) % 1000) / 1000.0
	var out := delta
	if u1 < (1.0 - fid) * 0.9:
		out = delta * (0.4 + u2 * 1.3)
		stats["garbled"] = int(stats["garbled"]) + 1
	if u3 < (1.0 - fid) * 0.12:
		out = -out
		stats["garbled"] = int(stats["garbled"]) + 1
	return out


func _deliver(row: Array) -> void:
	var delta := _distort(float(row[3]), String(row[4]), String(row[1]), int(row[5]))
	_believe(String(row[0]), String(row[1]), String(row[2]), delta)
	stats["delivered"] = int(stats["delivered"]) + 1


func _believe(subject: String, observer: String, axis: String, delta: float) -> void:
	var by: Dictionary = _bel.get(subject, {})
	if by.is_empty():
		_bel[subject] = by
	var b: Dictionary = by.get(observer, {})
	if b.is_empty():
		if by.size() >= OBSERVER_MAX:
			var oldest := ""
			var od := 1 << 30
			for o: String in by:
				if int((by[o] as Dictionary)["d"]) < od:
					od = int((by[o] as Dictionary)["d"])
					oldest = o
			by.erase(oldest)
		b = _empty_axes()
		by[observer] = b
	b[axis] = _clampv(float(b[axis]) + delta)
	b["d"] = _now()


func _evict() -> void:
	var worst := ""
	var wv := INF
	for s: String in _truth:
		if s == "i:player":
			continue
		var m := 0.0
		for a: String in PD.AXES:
			m += absf(float(_truth[s][a]))
		if m < wv:
			wv = m
			worst = s
	if worst != "":
		_truth.erase(worst)
		_bel.erase(worst)


func on_deed(subject: String, deed: String, sid: int, magnitude := 1.0, opts: Dictionary = {}) -> int:
	var fx: Dictionary = DEEDS.get(deed, {})
	var n := 0
	for axis: String in fx:
		if record(subject, axis, float(fx[axis]) * magnitude, sid, "witness", opts) > 0:
			n += 1
	return n


# ------------------------------------------------------------------ reading

func truth(subject: String) -> Dictionary:
	var t: Dictionary = _truth.get(subject, {})
	return t.duplicate() if not t.is_empty() else _empty_axes()


## What `observer` believes. Empty when the news has not reached it yet.
func view(subject: String, observer: String) -> Dictionary:
	var b: Dictionary = (_bel.get(subject, {}) as Dictionary).get(observer, {})
	if b.is_empty():
		return {}
	var out := (b as Dictionary).duplicate()
	out.erase("d")
	return out


func knows(subject: String, observer: String) -> bool:
	return not view(subject, observer).is_empty()


func age_of(subject: String, observer: String) -> int:
	var b: Dictionary = (_bel.get(subject, {}) as Dictionary).get(observer, {})
	return _now() - int(b.get("d", _now())) if not b.is_empty() else -1


func axis_of(subject: String, axis: String, observer: String) -> float:
	return float(view(subject, observer).get(axis, 0.0))


## How far an observer's picture is from the truth (mean absolute axis error); 0 for an unknowing observer.
func error_of(subject: String, observer: String) -> float:
	var v := view(subject, observer)
	if v.is_empty():
		return 0.0
	var t := truth(subject)
	var e := 0.0
	for a: String in PD.AXES:
		e += absf(float(v[a]) - float(t[a]))
	return e / float(PD.AXES.size())


## The summary a gatekeeper or judge uses at one place: belief at the town, else at its kingdom, else nothing known (neutral).
func standing(subject: String, sid: int) -> Dictionary:
	var v := view(subject, "t:%d" % sid)
	var source := "town"
	if v.is_empty():
		v = view(subject, "k:%s" % PD.kingdom_of(sid))
		source = "kingdom"
	if v.is_empty():
		return {"known": false, "source": "none", "trust": 0.0, "reliability": 0.0, "legitimacy": 0.0, "generosity": 0.0, "cruelty": 0.0,
			"influence": 0.0, "favour": 0.0}
	var fav := (float(v["trust"]) + float(v["reliability"]) + float(v["legitimacy"])) / 3.0 + float(v["influence"]) * 0.2 - float(v["cruelty"]) * 0.15
	return {"known": true, "source": source, "trust": float(v["trust"]), "reliability": float(v["reliability"]), "legitimacy": float(v["legitimacy"]),
		"generosity": float(v["generosity"]), "cruelty": float(v["cruelty"]), "influence": float(v["influence"]), "favour": fav}


## One line in words for a subject at a place ("" when unknown).
func words(subject: String, sid: int) -> String:
	var s := standing(subject, sid)
	if not bool(s["known"]):
		return "nobody here has heard of them"
	var f := float(s["favour"])
	var base := "well thought of" if f > 25.0 else ("respected" if f > 8.0 else ("regarded warily" if f > -8.0 else ("distrusted" if f > -25.0 else "despised")))
	if float(s["cruelty"]) > 25.0:
		base += ", and feared as cruel"
	elif float(s["generosity"]) > 25.0:
		base += ", and known as generous"
	return base


func subjects() -> int:
	return _truth.size()


func pending() -> int:
	return _pending


# ------------------------------------------------------------------ ticks

func _deliver_due(day: int, unlimited := false) -> void:
	var keys: Array = []
	for k: String in _in:
		if int(k) <= day:
			keys.append(k)
	keys.sort_custom(func(a: String, b: String) -> bool: return int(a) < int(b))
	var budget := (1 << 30) if unlimited else DELIVER_PER_DAY
	for k: String in keys:
		var rows: Array = _in[k]
		while not rows.is_empty() and budget > 0:
			_deliver(rows.pop_front())
			_pending -= 1
			budget -= 1
		if rows.is_empty():
			_in.erase(k)
		else:
			break
	_pending = maxi(_pending, 0)


func tick_day_chunks(day: int, _ctx: Dictionary) -> Array:
	return [func() -> Array:
			_day = day
			_deliver_due(day)
			return [],
		func() -> Array:
			# Memory fades once a week per subject, spread over the seven days so no single day pays for all of it.
			var slot := day % 7
			for s: String in _truth:
				if s.hash() % 7 == slot:
					_decay_subject(s, 1.0)
			return []]


func tick_day(day: int, ctx: Dictionary) -> Array:
	return _run_chunks(day, ctx)


func tick_week(_week: int, _ctx: Dictionary) -> Array:
	return []


func _decay_subject(s: String, weeks: float) -> void:
	var kb := pow(0.985, weeks)
	var kt := pow(0.995, weeks)
	if _truth.has(s):
		for a: String in PD.AXES:
			_truth[s][a] = snappedf(float(_truth[s][a]) * kt, 0.001)
	if _bel.has(s):
		for o: String in _bel[s]:
			for a: String in PD.AXES:
				_bel[s][o][a] = snappedf(float(_bel[s][o][a]) * kb, 0.001)


func _decay(weeks: float) -> void:
	for s: String in _truth:
		_decay_subject(s, weeks)


func catch_up(days: int, _ctx: Dictionary) -> Array:
	_day += days
	_deliver_due(_day, true)
	_decay(float(days) / 7.0)
	return []


# ------------------------------------------------------------------ save

func serialize() -> Dictionary:
	return {"truth": _truth.duplicate(true), "bel": _bel.duplicate(true), "in": _in.duplicate(true), "next": _next, "day": _day, "stats": stats.duplicate()}


func deserialize(d: Dictionary) -> void:
	_truth = (d.get("truth", {}) as Dictionary).duplicate(true)
	_bel = (d.get("bel", {}) as Dictionary).duplicate(true)
	_in = (d.get("in", {}) as Dictionary).duplicate(true)
	_pending = 0
	for k: String in _in:
		for row: Array in _in[k]:
			row[5] = int(row[5])
			_pending += 1
	for s: String in _bel:
		for o: String in _bel[s]:
			_bel[s][o]["d"] = int(_bel[s][o]["d"])
	_next = int(d.get("next", 1))
	_day = int(d.get("day", 0))
	var st: Dictionary = d.get("stats", {})
	for k: String in stats:
		stats[k] = int(st.get(k, stats[k]))
