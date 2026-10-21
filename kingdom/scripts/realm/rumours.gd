extends "res://scripts/realm/realm_module.gd"
## Memory and rumour (LW-8, docs/design/LIVING_WORLD_SANDBOX.md section 11, "memory and rumour").
##
## Characters remember significant events about the player and about each other. The memory is bounded (MEM_MAX lines each, the least
## striking and the oldest are forgotten first). What happens somewhere becomes a CLAIM: a short statement about a subject with a
## magnitude (-100..100 good/bad). A claim travels from the town where it started to every other town by road distance, at the rumour pace of reputation.gd (45 units a day: the slowest channel,
## slower than news.gd's items); on arrival in a town its magnitude is garbled by a deterministic hash of (claim, town) -- bigger the further it
## went, sometimes exaggerated, shrunk or even turned round -- so a far town can believe something false. A believer takes it into memory
## with a confidence lower than a witness has. A claim can be INVESTIGATED: a skilled investigator finds out what really happened, the
## claim is marked corrected, the towns' and believers' versions are replaced by the truth, and the liar (if there was one) pays in
## reliability through reputation.gd. Nothing here is per frame: claims arrive from a day-bucket queue, events are read once a day from
## the EventRecord ring, and a believer is looked at only when a claim reaches its town.
##
##   var rm = hub.mod("rumours")
##   rm.witness(ch, "crime", subject, -40.0, sid)        # first-hand memory, and a claim starts to travel
##   rm.say("gossip", subject, sid, -30.0, {"wrong": true})  # a false story (the truth is -30, what is told is garbled)
##   rm.opinion(ch, subject)                               # what ch thinks of subject (-100..100)
##   rm.heard_in(sid, subject)                             # what the town says, true or not
##   rm.investigate(claim_id, ch)                          # find out and correct

const PD := preload("res://scripts/realm/politics_data.gd")
const Events := preload("res://scripts/realm/events.gd")

const _EMPTY: Array = []
const _EMPTY_D: Dictionary = {}
const MEM_MAX := 4
const CLAIM_MAX := 160
const TOWN_CLAIMS := 10
const HOLDERS_MAX := 12
const SPEED := 45.0                  # road units a rumour travels in a day
const REACH := 4200.0                # beyond this a story never arrives
const ADOPT_PER_ARRIVAL := 3         # believers a claim finds in a town the day it arrives
const SCAN_MIN_WEIGHT := 3
const EVENT_KINDS := ["death", "marriage", "crime", "battle", "succession", "founding", "trade", "emergency", "build", "birth"]
## Event kind -> how good (+) or bad (-) the story is, at weight 5.
const KIND_MAG := {"death": -30.0, "marriage": 25.0, "crime": -45.0, "battle": 20.0, "succession": 15.0, "founding": 22.0, "trade": 12.0,
	"emergency": -35.0, "build": 18.0, "birth": 20.0}
const CORRECTED := 2
## What a story about a person moves in reputation.gd (the multi-axis opinion of towns, which has its own delay and garbling): kind -> axis.
const KIND_AXIS := {"crime": "trust", "marriage": "influence", "battle": "strength", "trade": "wealth", "founding": "competence", "build": "competence",
	"succession": "legitimacy", "emergency": "reliability", "birth": "generosity", "death": "influence", "moved": "influence"}
const REP_SCALE := 0.08

var _claims: Dictionary = {}     # id -> {k, s, sid, m, t, d, o, c, by, ev}
var _town: Dictionary = {}       # sid -> {claim id -> [heard magnitude, day]}
var _mem: Dictionary = {}        # ch -> [[day, subject, kind, magnitude, confidence, claim id], ...]
var _hold: Dictionary = {}       # claim id -> [ch, ...] (who took it into memory; bounded)
var _due: Dictionary = {}        # day -> [[claim id, sid], ...]
var _next := 1
var _day := 0
var _last_ev := 0
var _cm_hub: Variant = null
var _cm_ps: Variant = null
var _cm_bo: Variant = null
var _tmp := {}
## NI-5 word of mouth: a story told along trusted ties arrives the next day and is believed more. day -> [[listener, teller, claim id, depth, magnitude, trust]]
var _tells: Dictionary = {}
var _tell_depth := 0
const TELL_MAX_DEPTH := 2
const TELLS_PER_MEMORY := 3
const TELL_PER_DAY := 24
var stats := {"tells": 0, "claims": 0, "arrived": 0, "adopted": 0, "wrong": 0, "investigated": 0, "corrected": 0, "forgotten": 0, "witnessed": 0}


func _now() -> int:
	return maxi(_day, PD.today())


func _mod(n: String) -> Variant:
	return hub.mod(n) if hub != null else null


func _player() -> String:
	var reg: Variant = _mod("registry")
	return String(reg.lookup("pl:player")) if reg != null else ""


# ------------------------------------------------------------------ claims

func _dist(a: int, b: int) -> float:
	var nw: Variant = _mod("news")
	if nw == null:
		return 100.0 * absf(float(a - b))
	return float(nw.road_distance(a, b))


## The magnitude a town hears: the original, bent by distance. Deterministic.
func _garble(cid: int, m: float, dist: float) -> float:
	if dist <= 0.0:
		return m
	var h := absi(hash([WorldSim.SEED, "garble", cid, int(dist)]))
	var far := clampf(dist / 2400.0, 0.0, 1.0)
	var roll := float(h % 1000) / 1000.0
	if roll < 0.04 + 0.16 * far:
		return -m * (0.4 + 0.4 * float((h / 1000) % 100) / 100.0)      # turned round
	var swing := 0.25 + 0.5 * far
	var f := 1.0 + swing * (float((h / 7) % 200) / 100.0 - 1.0)
	return clampf(m * f, -100.0, 100.0)


## A story begins in town `sid` about `subject`. `truth` is what really happened; opts: wrong (the teller got it wrong or lied: what travels is
## the opposite-leaning version), by (who tells it), ev (EventRecord number), origin ("witness", "gossip", "malice").
func say(kind: String, subject: String, sid: int, truth: float, opts: Dictionary = {}) -> int:
	if subject == "":
		return 0
	if _claims.size() >= CLAIM_MAX:
		_prune()
	var cid := _next
	_next += 1
	var told := truth
	var origin := String(opts.get("origin", "gossip"))
	if bool(opts.get("wrong", false)):
		told = clampf(-truth * 0.8 if absf(truth) > 10.0 else truth + 40.0, -100.0, 100.0)
		origin = "malice" if origin == "gossip" else origin
		stats["wrong"] = int(stats["wrong"]) + 1
	_claims[cid] = {"k": kind, "s": subject, "sid": sid, "m": snappedf(told, 0.1), "t": snappedf(truth, 0.1), "d": _now(), "o": origin, "c": 0,
		"by": String(opts.get("by", "")), "ev": int(opts.get("ev", 0))}
	stats["claims"] = int(stats["claims"]) + 1
	_town_hear(sid, cid, told, _now())
	# The telling also moves what the towns think of the person (reputation.gd carries it on, late and garbled, by its own channels);
	# a false story therefore harms a good name until somebody investigates.
	var rep: Variant = _mod("reputation")
	if rep != null and KIND_AXIS.has(kind) and sid >= 0 and (subject.begins_with("ch:") or subject.begins_with("h:")):
		rep.record(("i:" + subject) if subject.begins_with("ch:") else subject, String(KIND_AXIS[kind]), told * REP_SCALE, sid, "rumour", {"channels": ["rumour"]})
	var n := WorldGen.settlements.size()
	for t in n:
		if t == sid:
			continue
		var dist := _dist(sid, t)
		if dist >= REACH:
			continue
		var arr := _now() + 1 + int(dist / SPEED)
		if not _due.has(arr):
			_due[arr] = []
		(_due[arr] as Array).append([cid, t])
	return cid


func _prune() -> void:
	var ids: Array = _claims.keys()
	ids.sort()
	var drop := maxi(1, ids.size() / 5)
	for i in drop:
		_forget_claim(int(ids[i]))


func _forget_claim(cid: int) -> void:
	_claims.erase(cid)
	_hold.erase(cid)
	for sid: Variant in _town:
		(_town[sid] as Dictionary).erase(cid)
	stats["forgotten"] = int(stats["forgotten"]) + 1


func claim(cid: int) -> Dictionary:
	return (_claims.get(cid, {}) as Dictionary).duplicate()


func claim_count() -> int:
	return _claims.size()


func _town_hear(sid: int, cid: int, m: float, day: int) -> void:
	var t: Dictionary = _town.get(sid, {})
	if t.is_empty():
		_town[sid] = t
	t[cid] = [snappedf(m, 0.1), day]
	if t.size() > TOWN_CLAIMS:
		var oldest := -1
		var od := 1 << 30
		for k: Variant in t:
			var dd := int((t[k] as Array)[1])
			if dd < od or (dd == od and int(k) < oldest):
				od = dd
				oldest = int(k)
		t.erase(oldest)


## What the town of `sid` says about `subject`, newest first: [{id, kind, said, day, true}] (`true` only once the claim is corrected --
## nobody in the town knows otherwise before).
func heard_in(sid: int, subject: String) -> Array:
	var out: Array = []
	var t: Dictionary = _town.get(sid, {})
	var ids: Array = t.keys()
	ids.sort()
	ids.reverse()
	for k: Variant in ids:
		var c: Dictionary = _claims.get(int(k), {})
		if c.is_empty() or String(c["s"]) != subject:
			continue
		var row := {"id": int(k), "kind": c["k"], "said": float((t[k] as Array)[0]), "day": int((t[k] as Array)[1]), "corrected": int(c["c"]) == CORRECTED}
		if int(c["c"]) == CORRECTED:
			row["true"] = float(c["t"])
		out.append(row)
	return out


## The town's overall view of `subject` from what it has heard (-100..100; 0 when it has heard nothing).
func town_view(sid: int, subject: String) -> float:
	var s := 0.0
	var w := 0.0
	var t: Dictionary = _town.get(sid, {})
	for k: Variant in t:
		var c: Dictionary = _claims.get(int(k), {})
		if c.is_empty() or String(c["s"]) != subject:
			continue
		var age := float(_now() - int((t[k] as Array)[1]))
		var wt := 1.0 / (1.0 + age / 30.0)
		s += float((t[k] as Array)[0]) * wt
		w += wt
	return clampf(s / w, -100.0, 100.0) if w > 0.0 else 0.0


# ------------------------------------------------------------------ memory

func memories(ch: String) -> Array:
	var out: Array = []
	for m: Array in _mem.get(ch, []):
		out.append({"day": int(m[0]), "subject": m[1], "kind": m[2], "mag": float(m[3]), "conf": int(m[4]), "claim": int(m[5])})
	return out


func memory_count() -> int:
	return _mem.size()


func _remember(ch: String, subject: String, kind: String, mag: float, conf: int, cid: int) -> void:
	var m: Array
	var mv: Variant = _mem.get(ch)
	if mv == null:
		m = []
		_mem[ch] = m
	else:
		m = mv
	if cid > 0:
		for row: Array in m:                      # the same story again strengthens it instead of piling up
			if row[5] == cid:
				row[4] = maxi(int(row[4]), conf)
				return
	m.append([_now(), subject, kind, snappedf(mag, 0.1), conf, cid])
	if m.size() > MEM_MAX:
		var worst := 0
		var ws := 1.0e9
		for i in m.size():
			var r: Array = m[i]
			var sc: float = absf(r[3]) * r[4] / 100.0 + r[0] / 100000.0   # rows hold a float magnitude and int confidence/day (see deserialize)
			if sc < ws:
				ws = sc
				worst = i
		m.remove_at(worst)
		stats["forgotten"] = int(stats["forgotten"]) + 1
	if cid > 0:
		var h: Array
		var hv: Variant = _hold.get(cid)
		if hv == null:
			h = []
			_hold[cid] = h
		else:
			h = hv
		if h.size() < HOLDERS_MAX and not h.has(ch):
			h.append(ch)
	if hub != _cm_hub:                             # module references are kept per hub (this runs for every memory)
		_cm_hub = hub
		_cm_ps = null
		_cm_bo = null
	var ps: Variant = _cm_ps
	if ps == null:
		ps = _mod("psyche")
		_cm_ps = ps
	if ps != null:                                 # NI-4: the same memory moves this person's mood, weighted by who they are
		ps.on_memory(ch, kind, mag, conf, (_hold[cid] as Array).size() if cid > 0 else 1)
	if cid > 0 and conf >= 45 and _tell_depth < TELL_MAX_DEPTH:
		_spread(ch, cid, mag)


## NI-5: `ch` now holds a story; the people who trust `ch` hear it from them tomorrow (the road carries it at 45 units a day), up to
## TELLS_PER_MEMORY of them, two hops at most. Deterministic: a hash decides who is told.
func _spread(ch: String, cid: int, mag: float) -> void:
	var bo: Variant = _cm_bo
	if bo == null:
		bo = _mod("bonds")
		_cm_bo = bo
		if bo == null:
			return
	var due := _now() + 1
	var n := 0
	var held: Array = _hold.get(cid, _EMPTY)
	for t: Array in bo.listeners(ch, TELLS_PER_MEMORY):
		if held.has(String(t[0])) or absi(hash([WorldSim.SEED, "tl", cid, ch, String(t[0])])) % 100 >= 75:
			continue
		var row: Array = _tells.get(due, [])
		if row.is_empty():
			_tells[due] = row
		row.append([String(t[0]), ch, cid, _tell_depth + 1, snappedf(mag, 0.1), int(t[1])])
		n += 1


func _hear_tells(day: int) -> void:
	var done := 0
	for d: Variant in _tells.keys():
		if int(d) > day:
			continue
		for e: Array in _tells[d]:
			if done >= TELL_PER_DAY:
				break
			var c: Dictionary = _claims.get(int(e[2]), _EMPTY_D)
			var who := String(e[0])
			var mn: Variant = _mod("minds")
			if c.is_empty() or mn == null or not mn.is_mind(who) or (_hold.get(int(e[2]), _EMPTY) as Array).has(who):
				continue
			# trust in the teller lends belief: 45 as for any rumour, up to 85 for someone they trust completely
			var conf := clampi(45 + int(float(e[5]) * 0.4), 45, 85)
			_tell_depth = int(e[3])
			_remember(who, String(c["s"]), String(c["k"]), float(e[4]), conf, int(e[2]))
			_tell_depth = 0
			stats["tells"] = int(stats["tells"]) + 1
			done += 1
		_tells.erase(d)


## First-hand: `ch` saw it. The memory is certain and the story starts to travel.
func witness(ch: String, kind: String, subject: String, mag: float, sid: int, opts: Dictionary = {}) -> int:
	stats["witnessed"] = int(stats["witnessed"]) + 1
	var cid := 0
	if not bool(opts.get("quiet", false)):
		var o := opts.duplicate()
		o["origin"] = "witness"
		o["by"] = ch
		cid = say(kind, subject, sid, mag, o)
	_remember(ch, subject, kind, mag, 100, cid)
	return cid


## What `ch` itself remembers, in one allocation-free pass (the decision layers call this every decision):
## Vector3(personal opinion of `subject` -100..100, 1 when it remembers anything about `subject` else 0, dread 0..1 = how much bad news of any
## subject it holds, weighted by confidence and fading with age).
func felt(ch: String, subject: String) -> Vector3:
	var m: Variant = _mem.get(ch)
	if m == null:
		return Vector3.ZERO
	var now := _now()
	var s := 0.0
	var w := 0.0
	var bad := 0.0
	for r: Array in m:
		var wt := float(r[4]) / 100.0 / (1.0 + float(now - int(r[0])) / 120.0)
		if String(r[1]) == subject:
			s += float(r[3]) * wt
			w += wt
		if float(r[3]) < 0.0:
			bad -= float(r[3]) * wt
	return Vector3(clampf(s / (w + 0.25), -100.0, 100.0) if w > 0.0 else 0.0, 1.0 if w > 0.0 else 0.0, clampf(bad / 100.0, 0.0, 1.0))


## A decision-maker's opinion of `subject`: what it remembers (weighted by confidence and fading with age) plus what its town says.
func opinion(ch: String, subject: String, sid := -1) -> float:
	var s := 0.0
	var w := 0.0
	for r: Array in _mem.get(ch, []):
		if String(r[1]) != subject:
			continue
		var age := float(_now() - int(r[0]))
		var wt := float(r[4]) / 100.0 / (1.0 + age / 120.0)
		s += float(r[3]) * wt
		w += wt
	var personal := s / (w + 0.25) if w > 0.0 else 0.0
	if sid < 0:
		return clampf(personal, -100.0, 100.0)
	var tv := town_view(sid, subject)
	return clampf(personal * 0.7 + tv * 0.3 if w > 0.0 else tv * 0.5, -100.0, 100.0)


## Does `ch` hold a false belief about `subject` right now? (a held claim whose truth differs in sign or by a wide margin)
func believes_falsely(ch: String, subject: String) -> bool:
	for r: Array in _mem.get(ch, []):
		if String(r[1]) != subject or int(r[5]) <= 0:
			continue
		var c: Dictionary = _claims.get(int(r[5]), {})
		if c.is_empty() or int(c["c"]) == CORRECTED:
			continue
		if absf(float(r[3]) - float(c["t"])) > 30.0 or (float(r[3]) * float(c["t"]) < 0.0):
			return true
	return false


# ------------------------------------------------------------------ investigation

## `by` looks into a claim: skill (0..1) decides whether the truth comes out. Costs the investigator `gold` (optional). Returns
## {ok, found, was_wrong, true_mag}.
func investigate(cid: int, by: String, skill := 0.5, gold := 0) -> Dictionary:
	var c: Dictionary = _claims.get(cid, {})
	if c.is_empty():
		return {"ok": false, "reason": "Nobody remembers that story."}
	stats["investigated"] = int(stats["investigated"]) + 1
	if int(c["c"]) == CORRECTED:
		return {"ok": true, "found": true, "was_wrong": absf(float(c["m"]) - float(c["t"])) > 15.0, "true_mag": float(c["t"]), "reason": "Already settled."}
	var om: Variant = _mod("organizations")
	if gold > 0 and om != null:
		if not om.pay(by, gold):
			return {"ok": false, "reason": "Digging costs gold."}
	var chance := clampf(0.25 + 0.6 * skill + float(gold) / 400.0, 0.05, 0.95)
	var roll := float(absi(hash([WorldSim.SEED, "inv", cid, by, _now()])) % 1000) / 1000.0
	if roll > chance:
		return {"ok": true, "found": false, "was_wrong": false, "true_mag": 0.0, "reason": "Nothing certain comes of it."}
	c["c"] = CORRECTED
	stats["corrected"] = int(stats["corrected"]) + 1
	var wrong := absf(float(c["m"]) - float(c["t"])) > 15.0 or float(c["m"]) * float(c["t"]) < 0.0
	for sid: Variant in _town:
		var tt: Dictionary = _town[sid]
		if tt.has(cid):
			tt[cid] = [float(c["t"]), _now()]
	for ch: Variant in _hold.get(cid, []):
		for r: Array in _mem.get(String(ch), []):
			if int(r[5]) == cid:
				r[3] = float(c["t"])
				r[4] = 85
	if wrong:
		var rep: Variant = _mod("reputation")
		if rep != null and String(c["by"]) != "":
			rep.record("i:" + String(c["by"]), "reliability", -6.0, int(c["sid"]), "none")
		# and the name the false story damaged is mended by the same measure
		if rep != null and KIND_AXIS.has(String(c["k"])) and String(c["s"]).begins_with("ch:"):
			rep.record("i:" + String(c["s"]), String(KIND_AXIS[String(c["k"])]), (float(c["t"]) - float(c["m"])) * REP_SCALE, int(c["sid"]), "messenger")
		var nw: Variant = _mod("news")
		if nw != null:
			nw.post("rumour_false", int(c["sid"]), "The tale about %s turns out to be wrong." % String(c["s"]), 1.0)
		Events.log_to(hub, "emergency", "ss:%d" % int(c["sid"]) if int(c["sid"]) >= 0 else "", [by, String(c["s"])], "rumour_refuted", "A false rumour is refuted", 2)
	return {"ok": true, "found": true, "was_wrong": wrong, "true_mag": float(c["t"]), "reason": ""}


# ------------------------------------------------------------------ the player

## Something the player did, told as news and remembered by whoever was there (`witnesses` are character ids).
func note_player(kind: String, sid: int, mag: float, witnesses: Array = []) -> int:
	var pl := _player()
	if pl == "":
		return 0
	var cid := say(kind, pl, sid, mag, {"origin": "witness"})
	for w: Variant in witnesses:
		_remember(String(w), pl, kind, mag, 100, cid)
	return cid


# ------------------------------------------------------------------ the day

func _scan_events() -> void:
	var ev: Variant = _mod("events")
	if ev == null:
		return
	var rows: Array = ev.after(_last_ev, SCAN_MIN_WEIGHT, EVENT_KINDS)
	_last_ev = maxi(_last_ev, int(ev.newest()))
	var reg: Variant = _mod("registry")
	var told: Array = []
	for r: Dictionary in rows:
		_last_ev = maxi(_last_ev, int(r["n"]))
		if int(r["weight"]) >= SCAN_MIN_WEIGHT and String(r["kind"]) in EVENT_KINDS and not (r["actors"] as Array).is_empty():
			told.append(r)
	# The day's talk is the few weightiest happenings (a killing outweighs a wedding), not every one.
	told.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["weight"]) > int(b["weight"]) or (int(a["weight"]) == int(b["weight"]) and int(a["n"]) < int(b["n"])))
	var made := 0
	for r2: Dictionary in told:
		if made >= 3:
			break
		var n := int(r2["n"])
		var sid := _sid_of(String(r2["where"]), reg)
		if sid < 0:
			continue
		var subject := String((r2["actors"] as Array)[0])
		var mag: float = float(KIND_MAG.get(r2["kind"], 10.0)) * float(int(r2["weight"])) / 5.0
		# An honest account of what happened; one in nine is told wrongly by someone with a grudge.
		var wrong := absi(hash([WorldSim.SEED, "tw", n])) % 9 == 0
		say(String(r2["kind"]), subject, sid, clampf(mag, -100.0, 100.0), {"ev": n, "wrong": wrong})
		made += 1
		var mn: Variant = _mod("minds")
		if mn != null and bool(mn.has_method("witnesses_at")):
			for w: Variant in mn.witnesses_at(sid, 2, n):
				_remember(String(w), subject, String(r2["kind"]), clampf(mag, -100.0, 100.0), 90, 0)


func _sid_of(where: String, reg: Variant) -> int:
	if where == "":
		return -1
	if where.begins_with("ss:"):
		return int(where.substr(3))
	if reg != null:
		var lg: String = reg.legacy_of(where)
		if lg.begins_with("ss:") or lg.begins_with("cp:") or lg.begins_with("hd:"):
			return int(lg.substr(3)) if lg.begins_with("ss:") else -1
	return -1


func _arrivals(day: int) -> void:
	var list: Array = _due.get(day, [])
	_due.erase(day)
	var mn: Variant = _mod("minds")
	for pair: Array in list:
		var cid := int(pair[0])
		var sid := int(pair[1])
		var c: Dictionary = _claims.get(cid, _EMPTY_D)
		if c.is_empty():
			continue
		var m := float(c["m"]) if int(c["c"]) != CORRECTED else float(c["t"])
		if int(c["c"]) != CORRECTED:
			m = _garble(cid, m, _dist(int(c["sid"]), sid))
		_town_hear(sid, cid, m, day)
		stats["arrived"] = int(stats["arrived"]) + 1
		if mn != null and bool(mn.has_method("believers_at")):
			for b: Variant in mn.believers_at(sid, ADOPT_PER_ARRIVAL, cid):
				_remember(String(b), String(c["s"]), String(c["k"]), m, 45 if String(c["o"]) != "witness" else 60, cid)
				stats["adopted"] = int(stats["adopted"]) + 1


func tick_day(day: int, _ctx: Dictionary) -> Array:
	_day = day
	_scan_events()
	_arrivals(day)
	_hear_tells(day)
	# Forget what is old and was never checked.
	if day % 30 == 0:
		for cid: Variant in _claims.keys():
			if day - int((_claims[cid] as Dictionary)["d"]) > 360:
				_forget_claim(int(cid))
		for ch: Variant in _mem.keys():
			var m: Array = _mem[ch]
			m = m.filter(func(r: Array) -> bool: return day - int(r[0]) < 720)
			if m.is_empty():
				_mem.erase(ch)
			else:
				_mem[ch] = m
	return []


## Once a week the towns look into a few stories that are doing harm and are probably wrong: the first resident with any lore of the town
## where it began does the asking (a clerk, a priest, an elder). So false stories are corrected without the player.
func tick_week(week: int, _ctx: Dictionary) -> Array:
	_day = maxi(_day, PD.today())
	var mn: Variant = _mod("minds")
	if mn == null:
		return []
	var done := 0
	var ids: Array = _claims.keys()
	ids.sort()
	for cid: Variant in ids:
		var c: Dictionary = _claims[cid]
		if int(c["c"]) == CORRECTED or _now() - int(c["d"]) < 10 or absf(float(c["m"]) - float(c["t"])) < 30.0:
			continue
		if absi(hash([WorldSim.SEED, "inq", int(cid), week])) % 100 >= 35:
			continue
		var who: Array = mn.witnesses_at(int(c["sid"]), 1, int(cid))
		if who.is_empty():
			continue
		var om: Variant = _mod("organizations")
		var skill: float = float(om.skill_of(String(who[0]), "lore")) if om != null else 0.4
		investigate(int(cid), String(who[0]), skill)
		done += 1
		if done >= 3:
			break
	return []


func catch_up(days: int, _ctx: Dictionary) -> Array:
	# Everything that was in flight has arrived by now.
	_day += days
	for d: Variant in _due.keys():
		if int(d) <= _day:
			_arrivals(int(d))
	return []


func drop_character(ch: String) -> void:
	_mem.erase(ch)
	var ps: Variant = _mod("psyche")
	if ps != null:
		ps.drop(ch)


# ------------------------------------------------------------------ save

func serialize() -> Dictionary:
	var cl: Array = []
	for cid: Variant in _claims:
		var c: Dictionary = _claims[cid]
		cl.append([int(cid), c["k"], c["s"], int(c["sid"]), float(c["m"]), float(c["t"]), int(c["d"]), c["o"], int(c["c"]), c["by"], int(c["ev"])])
	var tw: Dictionary = {}
	for sid: Variant in _town:
		var rows: Array = []
		for cid: Variant in _town[sid]:
			var e: Array = (_town[sid] as Dictionary)[cid]
			rows.append([int(cid), float(e[0]), int(e[1])])
		if not rows.is_empty():
			tw[str(sid)] = rows
	var due: Dictionary = {}
	for d: Variant in _due:
		due[str(d)] = _due[d]
	var tl: Dictionary = {}
	for d2: Variant in _tells:
		tl[str(d2)] = _tells[d2]
	return {"tl": tl, "cl": cl, "tw": tw, "mem": _mem.duplicate(true), "hold": _hold.duplicate(true), "due": due, "n": _next, "day": _day, "le": _last_ev, "st": stats.duplicate()}


func deserialize(d: Dictionary) -> void:
	_claims = {}
	_town = {}
	_mem = {}
	_hold = {}
	_due = {}
	for r: Variant in d.get("cl", []):
		var a: Array = r
		if a.size() >= 11:
			_claims[int(a[0])] = {"k": String(a[1]), "s": String(a[2]), "sid": int(a[3]), "m": float(a[4]), "t": float(a[5]), "d": int(a[6]), "o": String(a[7]),
				"c": int(a[8]), "by": String(a[9]), "ev": int(a[10])}
	var tw: Dictionary = d.get("tw", {})
	for k: Variant in tw:
		var t: Dictionary = {}
		for e: Variant in tw[k]:
			t[int((e as Array)[0])] = [float((e as Array)[1]), int((e as Array)[2])]
		_town[int(k)] = t
	var mem: Dictionary = d.get("mem", {})
	for k: Variant in mem:
		var rows: Array = []
		for r2: Variant in mem[k]:
			var a2: Array = r2
			rows.append([int(a2[0]), String(a2[1]), String(a2[2]), float(a2[3]), int(a2[4]), int(a2[5])])
		_mem[String(k)] = rows
	var hold: Dictionary = d.get("hold", {})
	for k: Variant in hold:
		var hs: Array = []
		for x: Variant in hold[k]:
			hs.append(String(x))
		_hold[int(k)] = hs
	var due: Dictionary = d.get("due", {})
	for k: Variant in due:
		var rows2: Array = []
		for p: Variant in due[k]:
			rows2.append([int((p as Array)[0]), int((p as Array)[1])])
		_due[int(k)] = rows2
	_tells = {}
	for k: Variant in (d.get("tl", {}) as Dictionary):
		var tr: Array = []
		for e2: Variant in d["tl"][k]:
			var a3: Array = e2
			if a3.size() == 6:
				tr.append([String(a3[0]), String(a3[1]), int(a3[2]), int(a3[3]), float(a3[4]), int(a3[5])])
		_tells[int(k)] = tr
	_next = int(d.get("n", 1))
	_day = int(d.get("day", 0))
	_last_ev = int(d.get("le", 0))
	var st: Dictionary = d.get("st", {})
	for k: String in stats:
		stats[k] = int(st.get(k, stats[k]))
