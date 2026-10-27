extends RefCounted
## Contextual in-world labels (UI restraint, ref 14 = Bellwright: almost nothing floats in the world).
## A name/station plate shows only when the player is close AND roughly facing it (or it is the interaction
## target), is never drawn over a crowd, fades in/out over FADE_TIME, and at most MAX_VISIBLE show at once.
## Everything here is pure; nameplates.gd feeds it from its 10 Hz pass and drives the fade.
##
## Setting "world_labels": 0 = always (legacy behaviour), 1 = contextual (default), 2 = off.

const MODE_ALWAYS := 0
const MODE_CONTEXTUAL := 1
const MODE_OFF := 2

const NEAR := 4.5             # m from the player
const NEAR_FADE := 1.5        # m over which alpha eases out before NEAR
const FOCUS_REACH := 6.0      # the current interaction target keeps its name a little further out
const FACING_DOT := 0.7       # cos(~45 deg) between the view direction and the direction to the label
const CROWD_RADIUS := 2.5     # m around a label that counts as "the same crowd"
const CROWD_MAX := 3          # this many other labelled things inside CROWD_RADIUS hide it (unless it is the focus)
const MAX_VISIBLE := 2
const FADE_TIME := 0.25       # s


## Dot product of the (flat) view direction and the (flat) direction from the viewer to the label. 1 = dead ahead.
static func facing_dot(view_dir: Vector3, from: Vector3, to: Vector3) -> float:
	var v := Vector2(view_dir.x, view_dir.z)
	var d := Vector2(to.x - from.x, to.z - from.z)
	if v.length_squared() < 0.0001 or d.length_squared() < 0.0001:
		return 1.0       # standing on it / looking straight down: do not hide on a degenerate direction
	return v.normalized().dot(d.normalized())


## Target alpha 0..1 for one label under `mode`. -1 = "not governed by this rule" (mode always): the caller keeps its own fade.
static func target_alpha(mode: int, dist: float, dot: float, is_focus: bool, crowd: int) -> float:
	if mode == MODE_ALWAYS:
		return -1.0
	if mode == MODE_OFF:
		return 0.0
	if is_focus:
		return clampf((FOCUS_REACH - dist) / NEAR_FADE, 0.0, 1.0)
	if crowd >= CROWD_MAX:
		return 0.0
	if dot < FACING_DOT:
		return 0.0
	return clampf((NEAR - dist) / NEAR_FADE, 0.0, 1.0)


## Other labelled things within CROWD_RADIUS of `pos` (points: Array[Vector3] of every candidate, `pos` itself included once). Pure.
static func crowd_count(pos: Vector3, points: Array) -> int:
	var n := 0
	for p: Vector3 in points:
		if p.distance_to(pos) <= CROWD_RADIUS:
			n += 1
	return maxi(n - 1, 0)


## rows: [{id, alpha, dist, focus}] -> the ids allowed to show: the focus first, then the closest, at most `n`; alpha <= 0 never counts. Pure.
static func pick_visible(rows: Array, n := MAX_VISIBLE) -> Array:
	var live: Array = rows.filter(func(r: Dictionary) -> bool: return float(r["alpha"]) > 0.0)
	live.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if bool(a.get("focus", false)) != bool(b.get("focus", false)):
			return bool(a.get("focus", false))
		return float(a["dist"]) < float(b["dist"]))
	var out: Array = []
	for r: Dictionary in live:
		if out.size() >= n:
			break
		out.append(r["id"])
	return out


## Linear fade step toward `target` so a full 0 -> 1 swing takes FADE_TIME. Pure.
static func step_alpha(cur: float, target: float, dt: float) -> float:
	return move_toward(cur, target, dt / FADE_TIME)
