extends RefCounted
## Depletable, regrowing gather deposits (ore veins, herb patches, trees, fishing spots).
##
## The static definition (cap, regrow per day, level, quality range) lives in DATA next to the node's
## spawn code; the SAVED part is only an overlay in the WorldState delta store (scripts/world/world_state.gd)
## under the id "<site>/dep/<kind>/<n>": {"q": units left (float), "d": game day the figure was taken}.
## An untouched or fully regrown deposit has no entry at all. Regrowth is closed form:
##     units(day) = min(cap, q + (day - d) * regrow_per_day)
## so a far region catches up by arithmetic the moment a node asks, with no per-node ticking and no per-node save.
##
## def: {cap: int, regrow: float units/day, level: int, qmin: int, qmax: int, kind: String, item: String}
## Clean-room; the pattern (finite source that regrows) is common to many games.

const WorldState := preload("res://scripts/world/world_state.gd")
const GatherSession := preload("res://scripts/sim/gather_session.gd")

## Ready-made definitions by kind; sites override fields per node.
const DEFAULTS := {
	"ore": {"cap": 8, "regrow": 2.0, "level": 1, "qmin": 30, "qmax": 70},
	"herb": {"cap": 6, "regrow": 3.0, "level": 1, "qmin": 30, "qmax": 80},
	"tree": {"cap": 10, "regrow": 1.5, "level": 1, "qmin": 30, "qmax": 70},
	"fish": {"cap": 5, "regrow": 2.5, "level": 1, "qmin": 30, "qmax": 80},
}

var store: RefCounted


func _init(p_store: RefCounted = null) -> void:
	store = p_store if p_store != null else WorldState.shared()


## A full definition: DEFAULTS[kind] overlaid with `over`.
static func make_def(kind: String, item: String, over: Dictionary = {}) -> Dictionary:
	var d: Dictionary = (DEFAULTS.get(kind, DEFAULTS["ore"]) as Dictionary).duplicate()
	d["kind"] = kind
	d["item"] = item
	for k: Variant in over:
		d[k] = over[k]
	return d


static func key(site: String, kind: String, n: int) -> String:
	return "%s/dep/%s/%d" % [site, kind, n]


## Units available on `day` (closed form).
func units(id: String, def: Dictionary, day: int) -> int:
	return int(floorf(_exact(id, def, day) + 0.0001))


func _exact(id: String, def: Dictionary, day: int) -> float:
	var cap := float(def["cap"])
	if not store.call("has_state", id):
		return cap
	var s: Dictionary = store.call("get_state", id)
	var q := float(s.get("q", cap))
	var d := int(s.get("d", day))
	return minf(cap, q + float(maxi(0, day - d)) * float(def.get("regrow", 0.0)))


func is_depleted(id: String, def: Dictionary, day: int) -> bool:
	return units(id, def, day) <= 0


## Fixed quality (0..100) of this deposit, from its id so it never changes between visits.
static func quality(id: String, def: Dictionary) -> int:
	var lo := int(def.get("qmin", 30))
	var hi := maxi(lo, int(def.get("qmax", 70)))
	return lo + int(absi(hash(id)) % (hi - lo + 1))


## The node dictionary a GatherSession takes.
func node(id: String, def: Dictionary, day: int) -> Dictionary:
	return {"kind": def["kind"], "item": def["item"], "level": int(def.get("level", 1)),
		"qty": units(id, def, day), "quality": quality(id, def)}


## Removes up to `n` units on `day`; returns how many were taken. Writes only this id's overlay.
func consume(id: String, def: Dictionary, n: int, day: int) -> int:
	var have := _exact(id, def, day)
	var take := mini(maxi(0, n), int(floorf(have + 0.0001)))
	if take <= 0:
		return 0
	var left := have - float(take)
	if left >= float(def["cap"]) - 0.0001:
		store.call("erase", id)
	else:
		store.call("set_state", id, {"q": snappedf(left, 0.001), "d": day})
	return take


## Gathers through a session result: consumes what the session took. Returns the units actually removed.
func commit(id: String, def: Dictionary, result: Dictionary, day: int) -> int:
	return consume(id, def, int(result.get("consumed", 0)), day)


## Drops overlay entries of `site` that have fully regrown by `day` (keeps the delta store small).
## Returns how many were dropped.
func prune(site: String, defs: Dictionary, day: int) -> int:
	var dropped := 0
	for id: String in store.call("ids_with_prefix", site + "/dep/"):
		var def: Variant = defs.get(id)
		if def is Dictionary and _exact(id, def, day) >= float((def as Dictionary)["cap"]) - 0.0001:
			store.call("erase", id)
			dropped += 1
	return dropped
