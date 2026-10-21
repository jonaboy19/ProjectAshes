extends "res://scripts/realm/realm_module.gd"
## MW-10 / MW-11: hidden per-quarter values and winners-and-losers for actions.
## Every settlement has quarters (noble, poor, merchant, military, other; see QUARTERS_BY_KIND). Each quarter carries ten hidden
## values 0..1 (F_*), stored as 10 bytes. They relax toward a target set by real causes (businesses opening/closing, payments,
## crime, garrison, investment, festivals, migration), kept as decaying "drivers". Closed form: `_step(n)` moves n days at once,
## so the day tick is `_step(1)` and catch_up is `_step(days)`.
## Feedback reads (no stereotypes: crime comes from individual need and the circumstances in `values`, never from the quarter's name):
## crime_opportunity, price_mult, rent_mult, guard_density, etiquette, mood, values. Save: 10 + 6 bytes-ish ints per quarter.

const Events := preload("res://scripts/realm/events.gd")

const F_PROS := 0
const F_POP := 1
const F_UNEMP := 2
const F_HOUSE := 3
const F_FOOD := 4
const F_SAFE := 5
const F_CORR := 6
const F_SUPP := 7
const F_CULT := 8
const F_TENS := 9
const FIELDS := ["prosperity", "population", "unemployment", "housing_cost", "food_security", "safety", "corruption", "political_support", "culture_mix", "tension"]
## Drivers (decaying causes): D_*.
const D_GARR := 0
const D_INV := 1
const D_CRIME := 2
const D_BIZ := 3      # net businesses opened (+) or closed (-) lately
const D_FEST := 4
const D_MIGR := 5
const D_PAY := 6      # steady payments (wages, rent paid, tax) minus defaults
const DECAY := [0.97, 0.985, 0.95, 0.98, 0.9, 0.97, 0.96]
const QUARTERS := ["noble", "poor", "merchant", "military", "other"]
const QUARTERS_BY_KIND := {
	"village": ["merchant", "other"], "frontier_town": ["merchant", "other", "poor", "military"],
	"town": ["merchant", "other", "poor", "military"], "castle": ["merchant", "other", "poor", "military", "noble"],
}
const BASE_WEALTH := {"noble": 0.85, "merchant": 0.65, "other": 0.45, "poor": 0.2, "military": 0.4}
const BIZ_QUARTER := {"shop": "merchant", "inn": "merchant", "caravan": "merchant", "workshop": "other"}
const RATE := 0.08          # fraction of the gap to target closed per day
const CHUNK := 6
const RIVAL_CAP := 24

var _v: Dictionary = {}      # "sid|q" -> Array[10] floats
var _d: Dictionary = {}      # "sid|q" -> Array[7] floats
var _biz: Dictionary = {}    # "sid|q" -> live business count last seen
var _opp: Dictionary = {}    # rival -> {actor: strength 0..1}
var _gain: Dictionary = {}   # actor -> net prosperity effect they caused (winners/losers ledger)
var _keys: Array = []        # sorted keys (derived)
var _ready := false


func _mod(n: String) -> RefCounted:
	return hub.mod(n) if hub != null else null


func _clamp01(x: float) -> float:
	return clampf(x, 0.0, 1.0)


# ------------------------------------------------------------------ setup

func quarters_of(sid: int) -> Array:
	var k := "village"
	if sid >= 0 and sid < WorldGen.settlements.size():
		k = String(WorldGen.settlements[sid].get("kind", "village"))
	return (QUARTERS_BY_KIND.get(k, ["merchant", "other"]) as Array).duplicate()


func _key(sid: int, q: String) -> String:
	return "%d|%s" % [sid, q]


func _ensure() -> void:
	if _ready:
		return
	_ready = true
	for sid in WorldGen.settlements.size():
		for q: String in quarters_of(sid):
			_seed(sid, q)
	_reindex()


func _seed(sid: int, q: String) -> void:
	var k := _key(sid, q)
	if _v.has(k):
		return
	var w: float = BASE_WEALTH[q]
	var r := RandomNumberGenerator.new()
	r.seed = hash([WorldSim.SEED, "dv", sid, q])
	var j := func(s: float) -> float: return r.randf_range(-s, s)
	_v[k] = [_clamp01(w + j.call(0.05)), _clamp01(0.3 + 0.4 * w + j.call(0.05)), _clamp01(0.45 - 0.35 * w + j.call(0.04)), _clamp01(0.25 + 0.5 * w),
		_clamp01(0.4 + 0.4 * w + j.call(0.05)), _clamp01(0.45 + 0.3 * w + (0.15 if q == "military" else 0.0)), _clamp01(0.15 + 0.2 * w + j.call(0.04)),
		_clamp01(0.5 + j.call(0.1)), _clamp01(0.3 + j.call(0.1)), _clamp01(0.2 + 0.2 * (1.0 - w))]
	_d[k] = [0.6 if q == "military" else 0.15, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]


func _reindex() -> void:
	_keys = _v.keys()
	_keys.sort()


func has_quarter(sid: int, q: String) -> bool:
	_ensure()
	return _v.has(_key(sid, q))


# ------------------------------------------------------------------ read API (perception, presence, prices)

func values(sid: int, q: String) -> Dictionary:
	_ensure()
	var a: Array = _v.get(_key(sid, q), [])
	var out := {}
	if a.is_empty():
		return out
	for i in FIELDS.size():
		out[FIELDS[i]] = snappedf(float(a[i]), 0.001)
	return out


func _f(sid: int, q: String, f: int) -> float:
	_ensure()
	var a: Array = _v.get(_key(sid, q), [])
	return float(a[f]) if not a.is_empty() else 0.5


func _dr(sid: int, q: String, i: int) -> float:
	var a: Array = _d.get(_key(sid, q), [])
	return float(a[i]) if not a.is_empty() else 0.0


## -1 (grim) .. 1 (cheerful): what a passer-by or NPC mood reads off the street.
func mood(sid: int, q: String) -> float:
	return clampf((_f(sid, q, F_PROS) + _f(sid, q, F_SAFE) + _f(sid, q, F_FOOD) + _f(sid, q, F_SUPP) - _f(sid, q, F_TENS) * 1.5
		- _f(sid, q, F_UNEMP) - 1.0) / 1.6, -1.0, 1.0)


## 0..1: how many guards walk here (patrol spawn weight for the presence layer).
func guard_density(sid: int, q: String) -> float:
	_ensure()
	return _clamp01(_dr(sid, q, D_GARR) * 0.8 + _f(sid, q, F_TENS) * 0.2 + _dr(sid, q, D_CRIME) * 0.1)


## 0..1 expected manners: wealth and order raise it, fear and tension lower it.
func etiquette(sid: int, q: String) -> float:
	return _clamp01(0.15 + 0.5 * _f(sid, q, F_PROS) + 0.25 * _f(sid, q, F_SAFE) - 0.2 * _f(sid, q, F_TENS))


## Shop price multiplier here: scarce food and prosperity raise it.
func price_mult(sid: int, q: String) -> float:
	return snappedf(0.85 + 0.25 * (1.0 - _f(sid, q, F_FOOD)) + 0.2 * _f(sid, q, F_PROS), 0.001)


func rent_mult(sid: int, q: String) -> float:
	return snappedf(0.6 + 0.9 * _f(sid, q, F_HOUSE), 0.001)


## 0..1 chance weight for one person to turn to crime on a given day. `who` carries individual traits
## {need, greed, honesty} 0..1 (defaults 0.3/0.3/0.6). The quarter's name is never read, only its current values:
## a wealthy man in a slum and a poor man in a palace see the same circumstances terms.
func crime_opportunity(sid: int, q: String, who: Dictionary = {}) -> float:
	var need := float(who.get("need", 0.3))
	var greed := float(who.get("greed", 0.3))
	var honesty := float(who.get("honesty", 0.6))
	var circ := 0.4 * _f(sid, q, F_UNEMP) + 0.3 * (1.0 - _f(sid, q, F_FOOD)) + 0.2 * _f(sid, q, F_CORR) + 0.1 * _f(sid, q, F_TENS)
	var guard := guard_density(sid, q)
	var drive := 0.45 * need + 0.25 * greed + 0.3 * circ
	return _clamp01(drive * (1.0 - 0.6 * honesty) * (1.0 - 0.6 * guard))


# ------------------------------------------------------------------ causes (push API)

func _nudge(sid: int, q: String, f: int, d: float) -> void:
	var a: Array = _v.get(_key(sid, q), [])
	if not a.is_empty():
		a[f] = _clamp01(float(a[f]) + d)


func _push(sid: int, q: String, i: int, amt: float) -> void:
	_ensure()
	var a: Array = _d.get(_key(sid, q), [])
	if not a.is_empty():
		a[i] = clampf(float(a[i]) + amt, -2.0, 2.0)


func on_business(sid: int, q: String, opened: bool) -> void:
	_push(sid, q, D_BIZ, 0.25 if opened else -0.35)


func on_crime(sid: int, q: String, severity := 1.0) -> void:
	_push(sid, q, D_CRIME, 0.3 * severity)
	_nudge(sid, q, F_SAFE, -0.03 * severity)


func garrison(sid: int, q: String, strength: float) -> void:
	_push(sid, q, D_GARR, strength)


func invest(sid: int, q: String, gold: int) -> void:
	_push(sid, q, D_INV, minf(float(gold) / 1000.0, 1.0))


func festival(sid: int, q: String) -> void:
	_push(sid, q, D_FEST, 1.0)


func migrants(sid: int, q: String, n: int) -> void:
	_push(sid, q, D_MIGR, clampf(float(n) / 50.0, -1.0, 1.0))


## A ledger payment lands in this quarter: kind "wage"/"rent"/"tax" paid on time (amt > 0) or defaulted (amt < 0).
func on_payment(sid: int, q: String, _kind: String, amt: int) -> void:
	_push(sid, q, D_PAY, clampf(float(amt) / 400.0, -0.5, 0.5))


# ------------------------------------------------------------------ MW-11 winners and losers

## One action, its per-actor and per-group effects. kinds: "workshop_opened", "market_tax", "garrison_posted", "festival_held", "bribe".
## `rivals` are owner ids hurt by it (they lose standing and may become opponents of `actor`).
## Returns [{who, group, field, delta}] and logs one event naming the groups.
func act(kind: String, sid: int, q: String, actor: String, magnitude := 1.0, rivals: Array = []) -> Array:
	_ensure()
	var fx: Array = []
	var m := clampf(magnitude, 0.0, 3.0)
	match kind:
		"workshop_opened":
			on_business(sid, q, true)
			if _biz.has(_key(sid, q)):
				_biz[_key(sid, q)] = int(_biz[_key(sid, q)]) + 1      # the day sync must not count the same opening again
			fx.append(_fx(actor, "owner", "prosperity", 0.02 * m))
			fx.append(_fx("", "residents", "unemployment", -0.03 * m))
			for r: String in rivals:
				fx.append(_fx(r, "rival", "income", -0.15 * m))
				_oppose(r, actor, 0.2 * m, sid)
		"market_tax":
			on_payment(sid, q, "tax", int(150 * m))
			fx.append(_fx(actor, "treasury", "prosperity", 0.0))
			fx.append(_fx("", "merchants", "prosperity", -0.015 * m))
			fx.append(_fx("", "poor", "support", -0.02 * m))
			_nudge(sid, q, F_SUPP, -0.02 * m)
			for r: String in rivals:
				_oppose(r, actor, 0.1 * m, sid)
		"garrison_posted":
			garrison(sid, q, 0.3 * m)
			fx.append(_fx("", "residents", "safety", 0.04 * m))
			fx.append(_fx("", "smugglers", "income", -0.2 * m))
			_nudge(sid, q, F_TENS, 0.02 * m)
		"festival_held":
			festival(sid, q)
			fx.append(_fx("", "residents", "support", 0.03 * m))
			fx.append(_fx(actor, "host", "gold", -0.1 * m))
		"bribe":
			_nudge(sid, q, F_CORR, 0.04 * m)
			fx.append(_fx(actor, "briber", "gold", -0.05 * m))
			fx.append(_fx("", "honest_traders", "prosperity", -0.01 * m))
			for r: String in rivals:
				_oppose(r, actor, 0.15 * m, sid)
		_:
			return fx
	for e: Dictionary in fx:
		if e["field"] == "prosperity" and e["who"] == actor:
			_gain[actor] = float(_gain.get(actor, 0.0)) + float(e["delta"])
	_nudge_fx(sid, q, fx)
	Events.log_to(hub, "district:" + kind, "ss:%d" % sid, [actor] + rivals, "quarter %s" % q, _groups(fx), 2)
	return fx


func _fx(who: String, group: String, field: String, delta: float) -> Dictionary:
	return {"who": who, "group": group, "field": field, "delta": snappedf(delta, 0.0001)}


func _nudge_fx(sid: int, q: String, fx: Array) -> void:
	for e: Dictionary in fx:
		match String(e["field"]):
			"prosperity":
				if e["group"] != "treasury" and e["group"] != "owner":
					_nudge(sid, q, F_PROS, float(e["delta"]))
			"unemployment":
				_nudge(sid, q, F_UNEMP, float(e["delta"]))
			"safety":
				_nudge(sid, q, F_SAFE, float(e["delta"]))
			"support":
				_nudge(sid, q, F_SUPP, float(e["delta"]))


func _groups(fx: Array) -> String:
	var parts: Array = []
	for e: Dictionary in fx:
		parts.append("%s:%s%+.2f" % [e["group"], e["field"], float(e["delta"])])
	return ", ".join(parts)


func _oppose(rival: String, actor: String, amt: float, sid: int) -> void:
	if rival == "" or actor == "" or rival == actor:
		return
	if not _opp.has(rival) and _opp.size() >= RIVAL_CAP:
		return
	var o: Dictionary = _opp.get(rival, {})
	o[actor] = _clamp01(float(o.get(actor, 0.0)) + amt)
	_opp[rival] = o
	var rep: RefCounted = _mod("reputation")
	if rep != null:
		rep.record(actor, "trust", -amt * 3.0, sid, "rumour")


## How hostile `rival` has become toward `actor` (0..1) because of what actor did to them.
func opposition(rival: String, actor: String) -> float:
	return float((_opp.get(rival, {}) as Dictionary).get(actor, 0.0))


func opponents_of(actor: String) -> Array:
	var out: Array = []
	for r: String in _opp:
		if (_opp[r] as Dictionary).has(actor):
			out.append(r)
	out.sort()
	return out


func net_effect(actor: String) -> float:
	return float(_gain.get(actor, 0.0))


# ------------------------------------------------------------------ dynamics

func _target(k: String, f: int, q: String) -> float:
	var v: Array = _v[k]
	var d: Array = _d[k]
	var w: float = BASE_WEALTH[q]
	match f:
		F_PROS:
			return _clamp01(w + 0.25 * float(d[D_INV]) + 0.2 * float(d[D_BIZ]) + 0.1 * float(d[D_FEST]) + 0.15 * float(d[D_PAY]) - 0.2 * float(d[D_CRIME]) - 0.15 * float(v[F_UNEMP]))
		F_POP:
			return _clamp01(0.3 + 0.4 * w + 0.4 * float(d[D_MIGR]) + 0.2 * float(v[F_SAFE]) - 0.1 * float(v[F_HOUSE]))
		F_UNEMP:
			return _clamp01(0.5 - 0.35 * w - 0.4 * float(d[D_BIZ]) - 0.2 * float(d[D_INV]) + 0.3 * float(d[D_MIGR]) - 0.1 * float(d[D_PAY]))
		F_HOUSE:
			return _clamp01(0.2 + 0.4 * w + 0.35 * (float(v[F_POP]) - 0.5) + 0.2 * (float(v[F_PROS]) - 0.5))
		F_FOOD:
			return _clamp01(0.45 + 0.35 * w + 0.15 * float(d[D_FEST]) - 0.25 * maxf(float(d[D_MIGR]), 0.0) + 0.1 * float(d[D_PAY]) - 0.2 * float(v[F_UNEMP]))
		F_SAFE:
			return _clamp01(0.55 + 0.4 * float(d[D_GARR]) - 0.5 * float(d[D_CRIME]) - 0.25 * float(v[F_UNEMP]) - 0.15 * float(v[F_CORR]))
		F_CORR:
			return _clamp01(0.15 + 0.2 * w + 0.1 * float(v[F_PROS]) - 0.25 * float(d[D_GARR]) * (1.0 - float(v[F_CORR])))
		F_SUPP:
			return _clamp01(0.5 + 0.3 * float(d[D_INV]) + 0.2 * float(d[D_FEST]) - 0.3 * float(v[F_TENS]) - 0.25 * float(v[F_CORR]) - 0.1 * float(v[F_HOUSE]))
		F_CULT:
			return _clamp01(0.3 + 0.5 * maxf(float(d[D_MIGR]), 0.0) + 0.1 * float(d[D_BIZ]))
		F_TENS:
			return _clamp01(0.15 + 0.3 * float(v[F_UNEMP]) + 0.25 * (1.0 - float(v[F_FOOD])) + 0.2 * float(v[F_CULT]) + 0.3 * float(d[D_CRIME]) - 0.2 * float(d[D_FEST]) - 0.1 * float(v[F_SUPP]))
	return 0.5


## Moves one quarter `n` days: drivers decay (their mean over the span moves the targets), values close the gap by 1-(1-RATE)^n.
func _step_one(k: String, n: int) -> void:
	var q: String = k.get_slice("|", 1)
	var v: Array = _v[k]
	var d: Array = _d[k]
	var avg: Array = []
	var dec: Array = []
	for i in d.size():
		var dc: float = DECAY[i]
		var dn := pow(dc, n)
		dec.append(dn)
		# mean of dc^t over t = 0..n-1 (the driver level while the values were moving)
		avg.append(float(d[i]) * (1.0 if n == 1 else (1.0 - dn) / (float(n) * (1.0 - dc))))
	var cur := d.duplicate()
	for i in d.size():
		d[i] = avg[i]
	var tg: Array = []
	for f in FIELDS.size():
		tg.append(_target(k, f, q))
	var g := 1.0 - pow(1.0 - RATE, n)
	for f in FIELDS.size():
		v[f] = _clamp01(float(v[f]) + (float(tg[f]) - float(v[f])) * g)
	for i in d.size():
		d[i] = snappedf(float(cur[i]) * float(dec[i]), 0.0001)
	if q == "military":
		d[D_GARR] = maxf(float(d[D_GARR]), 0.15)


func _sync_biz(sid: int) -> void:
	var bm: RefCounted = _mod("businesses")
	if bm == null:
		return
	var cnt: Dictionary = {}
	for bid: String in bm.ids():
		var b: Dictionary = bm.biz(bid)
		if int(b["sid"]) == sid and bm._live(b):
			var q: String = BIZ_QUARTER.get(String(b["kind"]), "other")
			cnt[q] = int(cnt.get(q, 0)) + 1
	for q: String in quarters_of(sid):
		var k := _key(sid, q)
		var now := int(cnt.get(q, 0))
		if _biz.has(k) and now != int(_biz[k]):
			on_business(sid, q, now > int(_biz[k]))
		_biz[k] = now


## A delegated governor (follower_will) shapes the quarters they rule: output moves payments, a skimming one raises corruption,
## unrest raises tension. Also read by stewardship.tax_yield().
func _sync_governor(sid: int) -> void:
	var wm: RefCounted = _mod("will")
	if wm == null:
		return
	var m: Dictionary = wm.settlement_modifier(sid)
	if String(m["governor"]) == "":
		return
	for q: String in quarters_of(sid):
		_push(sid, q, D_PAY, (float(m["output"]) - 1.0) * 0.1)
		_nudge(sid, q, F_CORR, float(m["leak"]) * 0.04)
		_nudge(sid, q, F_TENS, float(m["unrest"]) * 0.04)


func tick_day_chunks(_day: int, _ctx: Dictionary) -> Array:
	_ensure()
	var wm: RefCounted = _mod("will")
	if wm != null:
		for gsid: Variant in wm.governed():
			_sync_governor(int(gsid))
	var out: Array = []
	var i := 0
	while i < _keys.size():
		var part: Array = _keys.slice(i, i + CHUNK)
		out.append(func() -> Array:
			for k: String in part:
				_sync_biz(int(k.get_slice("|", 0)))
				_step_one(k, 1)
			return [])
		i += CHUNK
	return out


func tick_day(day: int, ctx: Dictionary) -> Array:
	return _run_chunks(day, ctx)


func catch_up(days: int, _ctx: Dictionary) -> Array:
	_ensure()
	if days <= 0:
		return []
	for k: String in _keys:
		_step_one(k, days)
	return []


# ------------------------------------------------------------------ save

func serialize() -> Dictionary:
	var v: Dictionary = {}
	var d: Dictionary = {}
	for k: String in _v:
		var row: Array = []
		for x in _v[k]:
			row.append(int(round(float(x) * 255.0)))
		v[k] = row
		var dr: Array = []
		var any := false
		for x in _d[k]:
			dr.append(int(round(float(x) * 100.0)))
			any = any or int(dr[-1]) != 0
		if any:
			d[k] = dr
	return {"v": v, "d": d, "o": _opp.duplicate(true), "g": _gain.duplicate(), "b": _biz.duplicate()}


func deserialize(s: Dictionary) -> void:
	_v = {}
	_d = {}
	_ready = true
	var sv: Dictionary = s.get("v", {})
	var sd: Dictionary = s.get("d", {})
	for k: String in sv:
		var row: Array = []
		for x in sv[k]:
			row.append(float(x) / 255.0)
		_v[k] = row
		var dr: Array = []
		for x in sd.get(k, [0, 0, 0, 0, 0, 0, 0]):
			dr.append(float(x) / 100.0)
		_d[k] = dr
	_opp = (s.get("o", {}) as Dictionary).duplicate(true)
	_gain = (s.get("g", {}) as Dictionary).duplicate()
	_biz = {}
	for k: String in s.get("b", {}):
		_biz[k] = int(s["b"][k])
	_reindex()
