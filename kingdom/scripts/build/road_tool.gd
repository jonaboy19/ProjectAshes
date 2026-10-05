extends RefCounted
## Finger roads (docs/design/RETINUE_SETTLEMENT_ASCENSION.md 4.4, L36): a stroke is resampled every 4 m, simplified
## (Ramer-Douglas-Peucker, eps 1.5 m), smoothed (Catmull-Rom), its ends snapped to existing road ends within 8 m, and drawn
## as our own ribbon mesh that hugs the terrain (the road-generator runtime build was too heavy for phones: one ribbon is one
## draw call and < 1 ms for 200 m).

const RESAMPLE := 4.0
const RDP_EPS := 1.5
const SNAP_ENDS := 8.0
const SUBDIV := 4
const LIFT := 0.06


static func resample(pts: Array, step := RESAMPLE) -> Array:
	if pts.size() < 2:
		return pts.duplicate()
	var out: Array = [pts[0]]
	var acc := 0.0
	for i in range(1, pts.size()):
		var a: Vector3 = pts[i - 1]
		var b: Vector3 = pts[i]
		var seg := a.distance_to(b)
		var t := step - acc
		while t <= seg:
			out.append(a.lerp(b, t / seg))
			t += step
		acc = seg - (t - step)
	if (out[-1] as Vector3).distance_to(pts[-1]) > step * 0.25:
		out.append(pts[-1])
	return out


static func rdp(pts: Array, eps := RDP_EPS) -> Array:
	if pts.size() < 3:
		return pts.duplicate()
	var a: Vector3 = pts[0]
	var b: Vector3 = pts[-1]
	var dmax := 0.0
	var idx := 0
	for i in range(1, pts.size() - 1):
		var d := _dist_seg(pts[i], a, b)
		if d > dmax:
			dmax = d
			idx = i
	if dmax <= eps:
		return [a, b]
	var left := rdp(pts.slice(0, idx + 1), eps)
	var right := rdp(pts.slice(idx), eps)
	left.pop_back()
	return left + right


static func _dist_seg(p: Vector3, a: Vector3, b: Vector3) -> float:
	var p2 := Vector2(p.x, p.z)
	var a2 := Vector2(a.x, a.z)
	var b2 := Vector2(b.x, b.z)
	var ab := b2 - a2
	var t := 0.0 if ab.length_squared() < 1e-6 else clampf((p2 - a2).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p2.distance_to(a2 + ab * t)


static func catmull(pts: Array, subdiv := SUBDIV) -> Array:
	if pts.size() < 3:
		return pts.duplicate()
	var out: Array = []
	for i in pts.size() - 1:
		var p0: Vector3 = pts[maxi(i - 1, 0)]
		var p1: Vector3 = pts[i]
		var p2: Vector3 = pts[i + 1]
		var p3: Vector3 = pts[mini(i + 2, pts.size() - 1)]
		for s in subdiv:
			var t := float(s) / subdiv
			var t2 := t * t
			var t3 := t2 * t
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	out.append(pts[-1])
	return out


## Moves the stroke's first/last point onto an existing road end within SNAP_ENDS metres.
static func snap_ends(pts: Array, ends: Array) -> Array:
	var out := pts.duplicate()
	for which in [0, out.size() - 1]:
		var best := SNAP_ENDS
		for e: Vector3 in ends:
			var d := Vector2(e.x - out[which].x, e.z - out[which].z).length()
			if d < best:
				best = d
				out[which] = e
	return out


## Stroke (world points from the finger) -> the road's centre line.
static func process(stroke: Array, ends: Array = []) -> Array:
	return catmull(rdp(snap_ends(resample(stroke), ends)))


## A ribbon `width` wide that follows the centre line and the ground (height_fn(x, z) -> y), UVs in metres / 4.
static func ribbon(centre: Array, width: float, height_fn: Callable, origin := Vector3.ZERO) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var along := 0.0
	var prev_l := Vector3.ZERO
	var prev_r := Vector3.ZERO
	var prev_v := 0.0
	for i in centre.size():
		var c: Vector3 = centre[i]
		var dir: Vector3 = ((centre[mini(i + 1, centre.size() - 1)] as Vector3) - (centre[maxi(i - 1, 0)] as Vector3))
		dir.y = 0.0
		dir = dir.normalized() if dir.length() > 0.001 else Vector3.FORWARD
		var side := Vector3(-dir.z, 0, dir.x) * width * 0.5
		var l := c - side
		var r := c + side
		l.y = float(height_fn.call(l.x + origin.x, l.z + origin.z)) - origin.y + LIFT
		r.y = float(height_fn.call(r.x + origin.x, r.z + origin.z)) - origin.y + LIFT
		if i > 0:
			along += (c - (centre[i - 1] as Vector3)).length()
			var v := along / 4.0
			for tri: Array in [[prev_l, Vector2(0, prev_v)], [r, Vector2(width / 4.0, v)], [prev_r, Vector2(width / 4.0, prev_v)],
					[prev_l, Vector2(0, prev_v)], [l, Vector2(0, v)], [r, Vector2(width / 4.0, v)]]:
				st.set_normal(Vector3.UP)
				st.set_uv(tri[1])
				st.add_vertex(tri[0])
			prev_v = v
		prev_l = l
		prev_r = r
	return st.commit()
