extends "res://scripts/realm/realm_module.gd"
## Territory layers (Living World section 8, LW-6.1). The map is a grid of 300 m cells with ten independent layers, because who rules a place,
## who owns it, who polices it and who merely stands on it are different questions:
##   sovereignty   which kingdom the ground belongs to
##   ownership     who holds the title (land.gd deeds)
##   jurisdiction  whose courts and laws apply
##   occupation    who is physically there with arms (a captor, a squatter)
##   claims        who says it should be theirs
##   influence     whose banner, tax collectors and custom reach it
##   trade         road and market coverage
##   religion      which faith's temples serve it
##   patrol        how often guards pass (0..1)
##   runestone     ward coverage (0..1)
## Defaults are derived from the settlements, roads and runestones on demand (no storage); only changes are stored, as sparse overrides capped at
## CELL_CAP entries (under 9 KB). CAPTURE IS NOT LAWFUL LORDSHIP: capturing a castle sets only occupation, keeps the deed and sovereignty, and the
## captor stays an unlawful occupier (unrest, no taxes) until a document or a treaty confirms it (confirm_sid).

const PD := preload("res://scripts/realm/politics_data.gd")
const Events := preload("res://scripts/realm/events.gd")
const Founding := preload("res://scripts/realm/founding.gd")

const CELL := 300.0
const CELL_CAP := 280
const LAYERS := ["sovereignty", "ownership", "jurisdiction", "occupation", "claims", "influence", "trade", "religion", "patrol", "runestone"]
const REACH := {"village": 420.0, "town": 700.0, "castle": 900.0, "capital": 1100.0, "frontier_town": 650.0}
const FRONTIER := 1400.0
const PATROL_BASE := {"village": 0.2, "town": 0.5, "castle": 0.8, "capital": 0.9, "frontier_town": 0.4}
const GROWTH_STAGES := ["unseen", "camp", "claim", "holding", "domain"]

var _ov: Dictionary = {}        # "<layer index>|<cx>,<cy>" -> value; insertion order is the eviction order (oldest first)
var _capt: Dictionary = {}      # str(sid) -> {by, day, lawful, doc}
var _grown: Dictionary = {}     # faction -> cell count at last growth (visible growth)
var _day := 0
var stats := {"captures": 0, "confirmed": 0, "evicted": 0}


func _now() -> int:
	return maxi(_day, PD.today())


func _mod(n: String) -> Variant:
	return hub.mod(n) if hub != null else null


static func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(int(floor(p.x / CELL)), int(floor(p.y / CELL)))


static func ckey(c: Vector2i) -> String:
	return "%d,%d" % [c.x, c.y]


static func _okey(layer: String, c: Vector2i) -> String:
	return "%d|%d,%d" % [LAYERS.find(layer), c.x, c.y]


static func center_of(c: Vector2i) -> Vector2:
	return Vector2((float(c.x) + 0.5) * CELL, (float(c.y) + 0.5) * CELL)


func _near(p: Vector2) -> Dictionary:
	var best := {"sid": -1, "dist": INF, "kind": "village"}
	for s: Dictionary in WorldGen.settlements:
		var d := p.distance_to(s["pos"])
		if d < float(best["dist"]):
			best = {"sid": int(s["id"]), "dist": d, "kind": String(s.get("kind", "village"))}
	return best


# ------------------------------------------------------------------ reading

func _default(layer: String, p: Vector2) -> Variant:
	var n := _near(p)
	var reach := float(REACH.get(String(n["kind"]), 420.0))
	var d := float(n["dist"])
	var inside := d <= reach
	match layer:
		"sovereignty":
			return PD.kingdom_of(int(n["sid"])) if d <= FRONTIER else ""
		"ownership":
			if inside:
				var ld: Variant = _mod("land")
				if ld != null:
					var dd: Dictionary = ld.deed(int(n["sid"]))
					return String(dd.get("holder", "crown"))
				return "crown"
			return ""
		"jurisdiction":
			return "s:%d" % int(n["sid"]) if inside else ("k:" + PD.kingdom_of(int(n["sid"])) if d <= FRONTIER else "")
		"occupation", "claims":
			return ""
		"influence":
			return PD.kingdom_of(int(n["sid"])) if d <= FRONTIER else ""
		"trade":
			var rd: float = WorldGen.road_distance(p.x, p.y)
			return "road" if rd != INF and rd < 60.0 else ("market" if inside else "")
		"religion":
			return "dawn" if d <= FRONTIER else ""
		"patrol":
			return snappedf(clampf(float(PATROL_BASE.get(String(n["kind"]), 0.2)) * (1.0 - d / (reach * 1.6)), 0.0, 1.0), 0.01)
		"runestone":
			var cv: Variant = _mod("civilization")
			if cv != null and cv.get("runestones") != null:
				return snappedf(float(cv.runestones.coverage(p)), 0.01)
			return 0.0
	return ""


func at(layer: String, p: Vector2) -> Variant:
	var k := _okey(layer, cell_of(p))
	if _ov.has(k):
		return _ov[k]
	return _default(layer, center_of(cell_of(p)))


func layers_at(p: Vector2) -> Dictionary:
	var out := {}
	for l: String in LAYERS:
		out[l] = at(l, p)
	return out


## The cells of one layer inside a rectangle, as [[cx, cy, value]] -- what the map draws (no per-frame use; the UI caches it).
func map_layer(layer: String, rect: Rect2) -> Array:
	var out: Array = []
	var a := cell_of(rect.position)
	var b := cell_of(rect.end)
	for cx in range(a.x, b.x + 1):
		for cy in range(a.y, b.y + 1):
			var v: Variant = at(layer, center_of(Vector2i(cx, cy)))
			if (v is String and String(v) != "") or (v is float and float(v) > 0.0):
				out.append([cx, cy, v])
	return out


# ------------------------------------------------------------------ writing

func set_layer(layer: String, p: Vector2, value: Variant) -> bool:
	if not (layer in LAYERS):
		return false
	var k := _okey(layer, cell_of(p))
	if not _ov.has(k) and _ov.size() >= CELL_CAP:
		_ov.erase(_ov.keys()[0])
		stats["evicted"] = int(stats["evicted"]) + 1
	_ov[k] = value
	return true


func _ring(center: Vector2, radius: float) -> Array:
	var out: Array = []
	var a := cell_of(center - Vector2(radius, radius))
	var b := cell_of(center + Vector2(radius, radius))
	for cx in range(a.x, b.x + 1):
		for cy in range(a.y, b.y + 1):
			var c := center_of(Vector2i(cx, cy))
			if c.distance_to(center) <= radius + CELL * 0.5:
				out.append(c)
	return out


func claim(faction: String, center: Vector2, radius: float) -> int:
	var n := 0
	for c: Vector2 in _ring(center, radius):
		var cur := String(at("claims", c))
		var names: Array = cur.split("|") if cur != "" else []
		if not (faction in names):
			names.append(faction)
			if set_layer("claims", c, "|".join(PackedStringArray(names))):
				n += 1
		set_layer("influence", c, faction)
	return n


## A growing settlement widens its claim: 1 + pop/40 cells (capped); the map shows it as it happens.
func grow(faction: String, center: Vector2, pop: int) -> int:
	var cells := clampi(1 + pop / 40, 1, 14)
	var radius := CELL * (0.35 + sqrt(float(cells)) * 0.45)
	claim(faction, center, radius)
	_grown[faction] = maxi(int(_grown.get(faction, 0)), cells)
	return cells


func claimed_cells(faction: String) -> int:
	var n := 0
	var pre := "%d|" % LAYERS.find("claims")
	for k: String in _ov:
		if k.begins_with(pre) and faction in String(_ov[k]).split("|"):
			n += 1
	return n


func visible_growth(faction: String) -> Dictionary:
	var n := claimed_cells(faction)
	var stage := 0 if n == 0 else (1 if n <= 2 else (2 if n <= 6 else (3 if n <= 14 else 4)))
	return {"faction": faction, "cells": n, "stage": String(GROWTH_STAGES[stage]), "stage_n": stage, "visible": stage >= 2}


# ------------------------------------------------------------------ capture is not lordship

func _sid_pos(sid: int) -> Vector2:
	return PD.settlement(sid).get("pos", Vector2.ZERO)


func capture(sid: int, by: String, day := -1) -> Dictionary:
	var s := PD.settlement(sid)
	if s.is_empty() or by == "":
		return {"ok": false}
	var dd := day if day >= 0 else _now()
	var lawful := String(lawful_holder(sid))
	var reach := float(REACH.get(PD.kind_of(sid), 420.0))
	for c: Vector2 in _ring(_sid_pos(sid), reach * 0.8):
		set_layer("occupation", c, by)
	_capt[str(sid)] = {"by": by, "day": dd, "lawful": false, "doc": "", "from": lawful}
	stats["captures"] = int(stats["captures"]) + 1
	var ld: Variant = _mod("land")
	if ld != null:
		ld.conquer(sid, by, dd)
	Events.log_to(hub, "battle", "ss:%d" % sid, [by], "captured", "%s takes %s but is no lawful lord" % [by, String(s["name"])], 5)
	return {"ok": true, "lawful": false, "holder": lawful, "occupier": by}


func lawful_holder(sid: int) -> String:
	var p := _sid_pos(sid)
	var o := String(at("ownership", p))
	return o if o != "" else "crown"


func occupier(sid: int) -> String:
	var c: Dictionary = _capt.get(str(sid), {})
	return String(c.get("by", ""))


func is_lawful_lord(sid: int, who: String) -> bool:
	var c: Dictionary = _capt.get(str(sid), {})
	if not c.is_empty() and String(c["by"]) == who:
		return bool(c["lawful"])
	return lawful_holder(sid) == who


func occupation_days(sid: int) -> int:
	var c: Dictionary = _capt.get(str(sid), {})
	return _now() - int(c["day"]) if not c.is_empty() and not bool(c["lawful"]) else 0


## A charter, grant or treaty turns an occupier into the lawful lord. `doc` is an audiences document id or "treaty:<id>".
func confirm_sid(sid: int, who: String, doc: String) -> Dictionary:
	var c: Dictionary = _capt.get(str(sid), {})
	if c.is_empty() or String(c["by"]) != who:
		return {"ok": false, "reason": "%s does not occupy it." % who}
	var legal := doc.begins_with("treaty:")
	var aud: Variant = _mod("audiences")
	if not legal and aud != null:
		var d: Dictionary = aud.doc(doc)
		legal = not d.is_empty() and String(d["state"]) == "valid" and String(d["holder"]) == who and String(d["type"]) in ["land", "title", "settlement_recognition", "office"] \
			and (int(d["sid"]) == sid or int(d["level"]) >= 2)
	if not legal:
		return {"ok": false, "reason": "Only a valid charter, grant or treaty makes a captor the lawful lord."}
	c["lawful"] = true
	c["doc"] = doc
	var ld: Variant = _mod("land")
	if ld != null:
		ld.legitimise(sid, _now())
	var reach := float(REACH.get(PD.kind_of(sid), 420.0))
	for cc: Vector2 in _ring(_sid_pos(sid), reach * 0.8):
		set_layer("ownership", cc, who)
		set_layer("jurisdiction", cc, "s:%d" % sid)
		set_layer("occupation", cc, "")
	stats["confirmed"] = int(stats["confirmed"]) + 1
	Events.log_to(hub, "succession", "ss:%d" % sid, [who], "confirmed", "%s is confirmed lord of %s" % [who, PD.sname(sid)], 4)
	return {"ok": true}


func confirm_pos(p: Vector2, who: String, doc: String, cells: int) -> void:
	var r := CELL * (0.35 + sqrt(float(maxi(cells, 1))) * 0.45)
	for c: Vector2 in _ring(p, r):
		set_layer("jurisdiction", c, "f:" + who)
		set_layer("ownership", c, who)
	_grown[who] = maxi(int(_grown.get(who, 0)), cells)


# ------------------------------------------------------------------ ticks

## Stage 7 (armies.gd): armed men over the legal limit make the ground around a settlement uneasy. Derived state: armies.gd re-pushes it after a load.
var _susp: Dictionary = {}      # sid -> 0..1


func note_suspicion(sid: int, value: float) -> void:
	if value <= 0.0:
		_susp.erase(sid)
	else:
		_susp[sid] = clampf(value, 0.0, 1.0)


func suspicion_at(sid: int) -> float:
	return float(_susp.get(sid, 0.0))


func tick_week(_week: int, _ctx: Dictionary) -> Array:
	_day = maxi(_day, PD.today())
	var ld: Variant = _mod("land")
	for k: String in _capt:
		var c: Dictionary = _capt[k]
		if not bool(c["lawful"]) and ld != null:
			ld.adjust_loyalty(int(k), -0.8)
	var fd: Variant = _mod("founding")
	if fd != null:
		for fid: int in fd.ids(true):
			var f: Dictionary = fd.get_founding(fid)
			if String(f.get("who", "")) != "player" or int(f["st"]) < 2:
				continue
			var pop := int(Founding.SCALE_POP[clampi(int(f["sc"]), 0, 4)]) + 6
			grow("player", Vector2(float(f["pos"][0]), float(f["pos"][1])), pop)
	return []


func tick_day(day: int, _ctx: Dictionary) -> Array:
	_day = day
	return []


func catch_up(days: int, ctx: Dictionary) -> Array:
	_day += days
	tick_week(0, ctx)
	return []


func serialize() -> Dictionary:
	return {"ov": _ov.duplicate(true), "capt": _capt.duplicate(true), "grown": _grown.duplicate(), "day": _day, "stats": stats.duplicate()}


func deserialize(d: Dictionary) -> void:
	_ov = (d.get("ov", {}) as Dictionary).duplicate(true)
	_capt = (d.get("capt", {}) as Dictionary).duplicate(true)
	for k: String in _capt:
		PD.fix_ints(_capt[k], ["day"])
	_grown = (d.get("grown", {}) as Dictionary).duplicate()
	for k: String in _grown:
		_grown[k] = int(_grown[k])
	_susp = {}
	_day = int(d.get("day", 0))
	var st: Dictionary = d.get("stats", {})
	for k: String in stats:
		stats[k] = int(st.get(k, stats[k]))
