class_name StreetLanes
extends RefCounted
## Corridor width and lane offset helpers for NPC steering (S3, S8 in docs/plans/NPC_MOTION_RULES.md). Static, pure, allocation-free.
## They live here rather than in population/street_graph.gd; the graph is only used through its public `inside(p, r)`.
##
## Plane convention: Vector2(x, z) of the world. `right_of(dir)` is the walker's right-hand side seen from above with +Y up
## (forward -Z gives +X), the same side the pass-right rule keeps.

const PROBE_STEP := 0.2
const PROBE_MAX := 3.2
const LANE_MIN_EDGE_WIDTH := 3.0
const LANE_FRAC_LO := 0.3
const LANE_FRAC_HI := 0.45
## Clearance from a lane centre line to the road edge kept for the body (m).
const LANE_EDGE_MARGIN := 0.15


## Deterministic 0..1 value from an id and a salt (integer mixing; hash([..]) would allocate an Array per call).
static func hash01(key: int, salt: int) -> float:
	var x := (key * 0x45d9f3b + salt * 0x27d4eb2d + 0x165667b1) & 0xFFFFFFFF
	x = ((x >> 16) ^ x) * 0x45d9f3b & 0xFFFFFFFF
	x = ((x >> 16) ^ x) * 0x45d9f3b & 0xFFFFFFFF
	x = (x >> 16) ^ x
	return float(x & 0xFFFF) / 65535.0


## The walker's right-hand unit vector for a (unit) heading.
static func right_of(dir: Vector2) -> Vector2:
	return Vector2(-dir.y, dir.x)


## Free distance from `p` along `dir` (unit) until a footprint is hit, up to `max_dist`.
static func clearance(graph: Object, p: Vector2, dir: Vector2, max_dist := PROBE_MAX, step := PROBE_STEP) -> float:
	var d := step
	while d <= max_dist:
		if graph.inside(p + dir * d, 0.0):
			return d - step
		d += step
	return max_dist


## Width of the street corridor at `p` across the heading `dir` (unit): left clearance + right clearance, each probed up to
## `max_half`. 0 when `p` is inside a footprint, `2 * max_half` in the open. Cost: at most 2 * max_half / PROBE_STEP inside() calls.
static func corridor_width(graph: Object, p: Vector2, dir: Vector2, max_half := PROBE_MAX * 0.5) -> float:
	if graph == null or graph.inside(p, 0.0):
		return 0.0
	var r := right_of(dir)
	return clearance(graph, p, r, max_half) + clearance(graph, p, -r, max_half)


## S8: signed lateral offset (m, positive = toward the right edge) a person walks off the street centre line, from the
## per-person hash `key`: LANE_FRAC_LO..LANE_FRAC_HI of the street width, never closer to the edge than the body radius.
## Streets under `min_width` have one lane (0).
static func lane_offset(width: float, key: int, body_radius := 0.35, min_width := LANE_MIN_EDGE_WIDTH,
		frac_lo := LANE_FRAC_LO, frac_hi := LANE_FRAC_HI) -> float:
	if width < min_width:
		return 0.0
	var h := hash01(key, 0x1a4e)
	var off := lerpf(frac_lo, frac_hi, h) * width
	return minf(off, width * 0.5 - body_radius - LANE_EDGE_MARGIN)


## Where the lane line is at `centre` (street centre point), `dir` the travel heading (unit).
static func lane_point(centre: Vector2, dir: Vector2, width: float, key: int, body_radius := 0.35) -> Vector2:
	return centre + right_of(dir) * lane_offset(width, key, body_radius)


## Signed lateral position (m, positive = right of travel) of `p` relative to the centre line through `centre` with heading `dir`.
static func lateral_of(p: Vector2, centre: Vector2, dir: Vector2) -> float:
	return (p - centre).dot(right_of(dir))
