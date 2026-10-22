class_name InteractionPicker
extends RefCounted
## Pure scoring of "what would the interact button do right now?". No scene tree, no Input, no globals, so it is
## unit-testable with plain dictionaries.
##
## A candidate is a Dictionary:
##   id: String, pos: Vector3, priority: int (higher wins, default 0), range: float (default DEFAULT_RANGE),
##   low_priority: bool (a passer-by's "Talk": loses to doors/services/pickups), mount: bool (the player's horse).
## Any other keys ride along untouched (verb, target, interact Callable, source...), so a provider can hand
## back self-contained candidates and the picker never needs to know what they are.
##
## Providers are Callables `(player_pos: Vector3, facing: Vector3) -> Array` returning more candidates. Traversal
## (vault / climb, package F2) plugs in here without touching this file.
##
## Higher score wins:  score = -effective_distance + priority * PRIORITY_STEP + facing_dot * FACING_WEIGHT
## Outside its own range a candidate never scores. While mounted, the mount candidate wins outright.

const DEFAULT_RANGE := 3.2
const LOW_PRIORITY_PENALTY := 1.6    # metres added to a low-priority candidate's distance
const PRIORITY_STEP := 1.5           # metres of distance one priority point is worth
const FACING_WEIGHT := 0.6           # metres of distance a perfectly faced candidate is worth
const FACING_MIN_DIST := 0.6         # closer than this the facing term fades out (standing on it)


## The best candidate, or {} when nothing is in reach. `providers` are extra candidate sources;
## `mounted` makes a mount candidate win outright.
static func pick(player_pos: Vector3, facing: Vector3, candidates: Array, providers: Array = [], mounted := false) -> Dictionary:
	var all: Array = candidates.duplicate()
	for p in providers:
		if p is Callable and (p as Callable).is_valid():
			var extra: Variant = (p as Callable).call(player_pos, facing)
			if extra is Array:
				all.append_array(extra)
	if mounted:
		for c in all:
			if c is Dictionary and bool((c as Dictionary).get("mount", false)):
				return c
	var best: Dictionary = {}
	var best_score := -INF
	for c in all:
		if not (c is Dictionary):
			continue
		var s := score(player_pos, facing, c)
		if s == -INF:
			continue
		if s > best_score or (s == best_score and String(c.get("id", "")) < String(best.get("id", ""))):
			best_score = s
			best = c
	return best


## Score of one candidate, -INF when out of range. Exposed for tests.
static func score(player_pos: Vector3, facing: Vector3, c: Dictionary) -> float:
	var pos: Vector3 = c.get("pos", Vector3.ZERO)
	var rng := float(c.get("range", DEFAULT_RANGE))
	var d := player_pos.distance_to(pos)
	if d >= rng:
		return -INF
	if bool(c.get("low_priority", false)):
		d = minf(d + LOW_PRIORITY_PENALTY, rng - 0.01)
	var s := -d + float(int(c.get("priority", 0))) * PRIORITY_STEP
	s += facing_dot(player_pos, facing, pos) * FACING_WEIGHT * clampf(d / FACING_MIN_DIST, 0.0, 1.0)
	return s


## Cosine between the (horizontal) facing and the direction to `pos`; 0 when degenerate.
static func facing_dot(player_pos: Vector3, facing: Vector3, pos: Vector3) -> float:
	var to := pos - player_pos
	to.y = 0.0
	var f := facing
	f.y = 0.0
	if to.length_squared() < 0.0001 or f.length_squared() < 0.0001:
		return 0.0
	return f.normalized().dot(to.normalized())
