class_name SocialPerception
extends RefCounted
## MW-5 (+ data side of MW-9): what an OBSERVER reads off a SUBJECT. Pure, deterministic, derived and never stored.
## Dict inputs, every key optional (absence = neutral):
##  observer: {id, kingdom, perception 0..1, magic_sense 0..1, intelligence 0..1, stress 0..1, status 0..1,
##             persona {courage, pious, greedy, sociable, lazy}, rep {axes of reputation.view}, knows_true_id: bool}
##  subject:  {id, origin (kingdom of their title), title_rank 0..5, insignia 0..1, gear_value 0..1, outfit {kind,dirty},
##             weapons 0..1, companions int, injury 0..1, aura_emit 0..1, aura_suppress 0..1, protection 0..1,
##             influence 0..1, disguise {identity {title_rank, origin, gear_value, id}, quality 0..1}, evidence 0..1}
## ctx: {allied: ["a|b"...] or kingdoms allied with origin, day, hour, reputation (obj with view(subject, observer))}.
## Aura only shifts scores; it never forces behaviour.

const Faith := preload("res://scripts/realm/faith.gd")
const HOME := "caldrenn"
const TTL_HOURS := 1
const CACHE_MAX := 512
const REACTIONS := ["ignore", "apologise", "bow", "insult", "demand_apology", "flee", "exploit"]
const OUTFIT_WEALTH := {"rags": 0.05, "travel": 0.25, "peasant": 0.2, "work": 0.25, "merchant": 0.6, "noble": 0.9, "armor": 0.6, "mask": 0.3}

var _cache: Dictionary = {}
var seed_value := 1
var reads := 0
var hits := 0


## How far a title from `origin` is honoured in `kingdom`: 1 own/allied, 0.5 neutral foreign, 0 for Valencios titles in church kingdoms.
static func legitimacy(origin: String, kingdom: String, ctx: Dictionary = {}) -> float:
	if kingdom == "" or origin == "" or origin == kingdom:
		return 1.0
	var al: Variant = ctx.get("allied", [])
	if al is Array and (kingdom in al or ("%s|%s" % [origin, kingdom]) in al):
		return 1.0
	if kingdom in Faith.CHURCH_KINGDOMS:
		return 0.0 if origin == HOME or origin not in Faith.CHURCH_KINGDOMS else 0.6
	return 0.5


static func _f(d: Dictionary, k: String, dflt := 0.0) -> float:
	return clampf(float(d.get(k, dflt)), 0.0, 1.0)


func _roll(tag: String, o: Dictionary, s: Dictionary, ctx: Dictionary) -> float:
	return float(absi(hash([seed_value, tag, str(o.get("id", "")), str(s.get("id", "")), int(ctx.get("day", 0))])) % 10000) / 10000.0


## The identity the observer takes the subject to be, and whether they see through it.
func identity(o: Dictionary, s: Dictionary, ctx: Dictionary = {}) -> Dictionary:
	var dg: Dictionary = s.get("disguise", {})
	if dg.is_empty():
		return {"disguised": false, "exposed": false, "chance": 0.0, "perceived": s, "true": s}
	var q := _f(dg, "quality", 0.5)
	var chance := clampf(_f(o, "perception", 0.3) * 0.6 + _f(s, "evidence") * 0.5 + (0.3 if o.get("knows_true_id", false) else 0.0) - q * 0.6, 0.0, 0.98)
	var exposed := _roll("expose", o, s, ctx) < chance
	var fake: Dictionary = (dg.get("identity", {}) as Dictionary)
	var shown := s.duplicate()
	shown.erase("disguise")
	if not exposed:
		for k: String in fake:
			shown[k] = fake[k]
		shown["id"] = fake.get("id", s.get("id", ""))
	return {"disguised": true, "exposed": exposed, "chance": chance, "perceived": shown, "true": s}


## The seven scores plus identity info. Cached per observer-subject pair for TTL_HOURS of game time.
func read(o: Dictionary, s: Dictionary, ctx: Dictionary = {}) -> Dictionary:
	reads += 1
	var ck := "%s|%s>%s@%d" % [o.get("kingdom", ""), o.get("id", ""), s.get("id", ""), int(ctx.get("hour", 0)) / TTL_HOURS]
	if _cache.has(ck):
		hits += 1
		return _cache[ck]
	var idn := identity(o, s, ctx)
	var p: Dictionary = idn["perceived"]
	var kingdom := String(o.get("kingdom", HOME))
	var outfit: Dictionary = p.get("outfit", {})
	var wealth := clampf(maxf(_f(p, "gear_value", -1.0) if p.has("gear_value") else float(OUTFIT_WEALTH.get(String(outfit.get("kind", "")), 0.2)), 0.0) - (0.1 if outfit.get("dirty", false) else 0.0), 0.0, 1.0)
	var leg := legitimacy(String(p.get("origin", kingdom)), kingdom, ctx)
	var authority := clampf(float(p.get("title_rank", 0)) / 5.0 * (0.4 + 0.6 * _f(p, "insignia", 0.5)) * leg, 0.0, 1.0)
	var rep := 0.0
	var rv: Dictionary = o.get("rep", {})
	var rs: Variant = ctx.get("reputation")
	if rv.is_empty() and rs != null:
		rv = rs.view(String(p.get("id", "")), String(o.get("id", "")))
	if not rv.is_empty():
		rep = clampf((float(rv.get("trust", 0.0)) + float(rv.get("reliability", 0.0)) + float(rv.get("generosity", 0.0)) - float(rv.get("cruelty", 0.0))) / 200.0, -1.0, 1.0)
	var threat := clampf(_f(p, "weapons") * 0.6 + minf(float(p.get("companions", 0)), 4.0) * 0.1 + _f(p, "strength") * 0.3 - _f(p, "injury") * 0.4, 0.0, 1.0)
	var out := {"wealth": wealth, "authority": authority, "legitimacy": leg, "reputation": rep, "threat": threat,
		"magic_pressure": magic_pressure(o, s, ctx), "protection": clampf(_f(p, "protection") + minf(float(p.get("companions", 0)), 4.0) * 0.05, 0.0, 1.0),
		"local_influence": _f(p, "influence"), "disguised": idn["disguised"], "exposed": idn["exposed"], "expose_chance": idn["chance"],
		"perceived_id": String(p.get("id", "")), "true_id": String(s.get("id", ""))}
	if _cache.size() >= CACHE_MAX:
		_cache.clear()
	_cache[ck] = out
	return out


## Aura felt by the observer: (emission - suppression) x sensitivity, plus an error from low intelligence / high stress (can misjudge).
func magic_pressure(o: Dictionary, s: Dictionary, ctx: Dictionary = {}) -> float:
	var net := maxf(_f(s, "aura_emit") - _f(s, "aura_suppress"), 0.0)
	var sens := _f(o, "magic_sense", 0.1)
	var err := (_roll("aura", o, s, ctx) * 2.0 - 1.0) * (0.15 + 0.5 * (1.0 - _f(o, "intelligence", 0.5)) + 0.3 * _f(o, "stress"))
	return clampf(net * sens * 1.5 + err * sens * 0.6, 0.0, 1.0)


## Deterministic bump-into-stranger reaction of `o` (the bumped) towards `s` (the bumper). Read-only; persona optional.
func bump_reaction(o: Dictionary, s: Dictionary, ctx: Dictionary = {}) -> String:
	var r := read(o, s, ctx)
	var pe: Dictionary = o.get("persona", {})
	var courage := _f(pe, "courage", 0.5)
	var pious := _f(pe, "pious", 0.3)
	var greedy := _f(pe, "greedy", 0.3)
	var mine := _f(o, "status", 0.2)
	var fear: float = maxf(float(r["threat"]), float(r["magic_pressure"])) * (1.2 - courage) + float(r["protection"]) * 0.3
	if fear > 0.75 or (r["magic_pressure"] > 0.6 and courage < 0.5):
		return "flee"
	if r["authority"] >= 0.5 and r["authority"] > mine:
		return "bow" if pious > 0.5 or r["authority"] > 0.8 else "apologise"
	if fear > 0.45 or r["local_influence"] > 0.6:
		return "apologise"
	if r["wealth"] > 0.6 and greedy > 0.45 and r["authority"] < 0.3:
		return "exploit"
	if r["reputation"] < -0.4 and r["threat"] < 0.3:
		return "insult"
	if mine > r["wealth"] + r["authority"] + 0.2 and courage >= 0.4:
		return "demand_apology" if _f(pe, "sociable", 0.5) < 0.6 else "insult"
	return "ignore"


func clear() -> void:
	_cache.clear()
