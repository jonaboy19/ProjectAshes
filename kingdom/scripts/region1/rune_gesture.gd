class_name RuneGesture
extends RefCounted
## Rune gesture recognizer (N1 Wardwright, package L8): finger strokes -> ward / lure / alarm / bless.
##
## Method: a Protractor-style point-cloud matcher, extended to several strokes.
##   1. Each stroke is cleaned, resampled by arc length (equal points per stroke, N in total),
##      all strokes are joined, the cloud is centred on its centroid and scaled to unit length.
##      That makes it translation and scale invariant, so a big or tiny drawing is the same shape.
##   2. Two shapes are compared by the best rotation, in closed form (no search): with
##      a = sum(t . c) and b = sum(t x c), the best cosine similarity is sqrt(a^2 + b^2).
##      That makes it rotation invariant (limit it with recognizer.max_rotation_deg).
##   3. Every glyph is pre-expanded into templates for every stroke order and direction (and,
##      for closed shapes, every start point; for `mirror` glyphs, the mirror image), so the
##      player may draw a glyph however they like. About 36 templates, well under 1 ms a match.
##   4. Templates with the same stroke count are tried first; the others only when that
##      best is weaker than `fast_accept`.
## Result: {glyph, score, sim, margin, accepted, reason, scores, strokes, runner_up, us}.
## `score` is the 0..1 confidence to show to the player; `sim` is the raw cosine similarity.
## `assist` (0..1) relaxes the acceptance threshold (the accessibility auto-complete setting).
## Personal style: `learn(id, strokes)` stores the player's own way of drawing a glyph as an
## extra template (max `max_user_samples` per glyph); `register_state()` saves them through
## Region1State (key "rune_gesture").
##
## Pure and deterministic (no scene tree, no randf; `synthesize` takes the RNG you give it).

const DATA_PATH := "res://data/region1/glyphs.json"
const STATE_KEY := &"rune_gesture"
const RegistryScript := preload("res://scripts/region1/region1_state.gd")

var opts := {
	"points": 24, "min_size": 16.0, "min_sim": 0.86, "min_margin": 0.012, "confidence_floor": 0.7,
	"fast_accept": 0.94, "max_strokes": 3, "max_rotation_deg": 180.0, "closed_starts": 8,
	"assist_relax": 0.06, "max_user_samples": 6,
}
var glyph_ids := PackedStringArray()
var glyph_defs: Array[Dictionary] = []

var _n := 24
var _tv: Array[PackedVector2Array] = []   # template vectors
var _tg := PackedInt32Array()             # template -> glyph index
var _tk := PackedInt32Array()             # template -> stroke count
var _tuser := PackedByteArray()           # 1 = learned from the player
var _by_k: Dictionary = {}                # stroke count -> PackedInt32Array of template indices
var _user: Dictionary = {}                # glyph id -> Array of normalized stroke sets (JSON-safe)
var _rot_limit := PI


func _init(auto_load := true) -> void:
	if auto_load:
		load_glyphs()


## Load glyph shapes and recognizer options. Returns the number of glyphs.
func load_glyphs(path: String = DATA_PATH) -> int:
	glyph_ids = PackedStringArray()
	glyph_defs = []
	if not FileAccess.file_exists(path):
		push_warning("RuneGesture: missing " + path)
		return 0
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return 0
	for k in (parsed.get("recognizer", {}) as Dictionary):
		if not String(k).begins_with("_"):
			opts[k] = parsed["recognizer"][k]
	for g: Dictionary in parsed.get("glyphs", []):
		glyph_ids.append(String(g["id"]))
		glyph_defs.append(g)
	rebuild()
	return glyph_ids.size()


func rebuild() -> void:
	_n = maxi(6, int(int(opts["points"]) / 6) * 6)
	_rot_limit = deg_to_rad(clampf(float(opts["max_rotation_deg"]), 0.0, 180.0))
	_tv = []
	_tg = PackedInt32Array()
	_tk = PackedInt32Array()
	_tuser = PackedByteArray()
	_by_k = {}
	for gi in glyph_defs.size():
		var g: Dictionary = glyph_defs[gi]
		var base: Array[PackedVector2Array] = []
		for s: Array in g["strokes"]:
			var pv := PackedVector2Array()
			for p: Array in s:
				pv.append(Vector2(float(p[0]), float(p[1])))
			base.append(pv)
		for variant in _variants(base, bool(g.get("closed", false)), bool(g.get("mirror", false))):
			_add_template(gi, variant, 0)
	for id: String in _user:
		var gi := glyph_ids.find(id)
		if gi < 0:
			continue
		for set: Array in _user[id]:
			var strokes: Array[PackedVector2Array] = []
			for s: Array in set:
				var pv := PackedVector2Array()
				for p: Array in s:
					pv.append(Vector2(float(p[0]), float(p[1])))
				strokes.append(pv)
			_add_template(gi, strokes, 1)


func template_count() -> int:
	return _tv.size()


func _add_template(gi: int, strokes: Array[PackedVector2Array], user: int) -> void:
	var v := _vectorize(strokes)
	if v.is_empty():
		return
	var idx := _tv.size()
	_tv.append(v)
	_tg.append(gi)
	_tk.append(strokes.size())
	_tuser.append(user)
	if not _by_k.has(strokes.size()):
		_by_k[strokes.size()] = PackedInt32Array()
	var arr: PackedInt32Array = _by_k[strokes.size()]
	arr.append(idx)
	_by_k[strokes.size()] = arr


# ============================================================================ geometry

## Every drawing order and direction, plus start points for closed shapes and the mirror.
func _variants(base: Array[PackedVector2Array], closed: bool, mirror: bool) -> Array:
	var out: Array = []
	var k := base.size()
	if closed and k == 1:
		var ring := PackedVector2Array(base[0])
		if ring.size() > 2 and ring[0].distance_to(ring[ring.size() - 1]) < 1e-4:
			ring.resize(ring.size() - 1)
		var dense := resample(_close(ring), 96)
		dense.resize(95)   # drop the duplicated closing point
		var starts := int(opts["closed_starts"])
		for s in starts:
			var off := s * 95 / starts
			for dir in 2:
				var st := PackedVector2Array()
				for i in 95:
					st.append(dense[(off + (i if dir == 0 else -i) + 95 * 2) % 95])
				st.append(st[0])
				out.append([st] as Array[PackedVector2Array])
				if mirror:
					out.append([_mirror(st)] as Array[PackedVector2Array])
		return out
	for order in _permutations(k):
		for mask in (1 << k):
			var strokes: Array[PackedVector2Array] = []
			for j in k:
				var s: PackedVector2Array = base[order[j]]
				if (mask >> j) & 1 == 1:
					s = _reversed(s)
				strokes.append(s)
			out.append(strokes)
			if mirror:
				var m: Array[PackedVector2Array] = []
				for s in strokes:
					m.append(_mirror(s))
				out.append(m)
	return out


static func _permutations(k: int) -> Array:
	if k <= 1:
		return [[0]]
	var out: Array = []
	for first in k:
		var rest: Array = []
		for i in k:
			if i != first:
				rest.append(i)
		for tail: Array in _permutations_of(rest):
			out.append([first] + tail)
	return out


static func _permutations_of(items: Array) -> Array:
	if items.size() <= 1:
		return [items.duplicate()]
	var out: Array = []
	for i in items.size():
		var rest := items.duplicate()
		rest.remove_at(i)
		for tail: Array in _permutations_of(rest):
			out.append([items[i]] + tail)
	return out


static func _reversed(s: PackedVector2Array) -> PackedVector2Array:
	var r := PackedVector2Array()
	for i in range(s.size() - 1, -1, -1):
		r.append(s[i])
	return r


static func _mirror(s: PackedVector2Array) -> PackedVector2Array:
	var r := PackedVector2Array()
	for p in s:
		r.append(Vector2(1.0 - p.x, p.y))
	return r


static func _close(ring: PackedVector2Array) -> PackedVector2Array:
	var r := PackedVector2Array(ring)
	if r.size() > 0:
		r.append(r[0])
	return r


static func path_length(pts: PackedVector2Array) -> float:
	var d := 0.0
	for i in range(1, pts.size()):
		d += pts[i - 1].distance_to(pts[i])
	return d


## Equal arc-length resampling to exactly `n` points.
static func resample(pts: PackedVector2Array, n: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	if pts.is_empty():
		return out
	var total := path_length(pts)
	if total < 1e-9:
		out.resize(n)
		out.fill(pts[0])
		return out
	var step := total / float(n - 1)
	out.append(pts[0])
	var acc := 0.0
	var prev := pts[0]
	var i := 1
	while i < pts.size() and out.size() < n:
		var cur := pts[i]
		var seg := prev.distance_to(cur)
		if seg > 1e-12 and acc + seg >= step:
			var q := prev + (cur - prev) * ((step - acc) / seg)
			out.append(q)
			prev = q
			acc = 0.0
		else:
			acc += seg
			prev = cur
			i += 1
	while out.size() < n:
		out.append(pts[pts.size() - 1])
	return out


## Cloud vector of a stroke set: `_n` points, centroid at the origin, unit length. Empty = unusable.
func _vectorize(strokes: Array[PackedVector2Array]) -> PackedVector2Array:
	var k := strokes.size()
	if k == 0 or k > 3:
		return PackedVector2Array()
	var per := _n / k
	var all := PackedVector2Array()
	for s in strokes:
		if s.size() < 2:
			return PackedVector2Array()
		all.append_array(resample(s, per))
	var c := Vector2.ZERO
	for p in all:
		c += p
	c /= float(all.size())
	var ss := 0.0
	for i in all.size():
		all[i] -= c
		ss += all[i].length_squared()
	if ss < 1e-12:
		return PackedVector2Array()
	var inv := 1.0 / sqrt(ss)
	for i in all.size():
		all[i] *= inv
	return all


# ============================================================================ recognition

## strokes: Array of PackedVector2Array (or Array of Array[Vector2]), in any pixel units.
func recognize(strokes: Array, assist := 0.0) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var res := {"glyph": &"", "id": "", "score": 0.0, "sim": 0.0, "margin": 0.0, "accepted": false,
		"reason": "", "scores": {}, "strokes": 0, "runner_up": "", "us": 0}
	# clean the input
	var min_size := float(opts["min_size"])
	var kept: Array[PackedVector2Array] = []
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for s in strokes:
		var pv := _clean(PackedVector2Array(s))
		for p in pv:
			lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
			hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
		if pv.size() >= 2 and path_length(pv) >= min_size * 0.25:
			kept.append(pv)
	res["strokes"] = kept.size()
	if kept.is_empty():
		res["reason"] = "no_strokes"
		res["us"] = Time.get_ticks_usec() - t0
		return res
	if maxf(hi.x - lo.x, hi.y - lo.y) < min_size:
		res["reason"] = "too_small"
		res["us"] = Time.get_ticks_usec() - t0
		return res
	if kept.size() > int(opts["max_strokes"]):
		res["reason"] = "too_many_strokes"
		res["us"] = Time.get_ticks_usec() - t0
		return res
	var vec := _vectorize(kept)
	if vec.is_empty():
		res["reason"] = "degenerate"
		res["us"] = Time.get_ticks_usec() - t0
		return res
	# match: same stroke count first, the rest only if that is not convincing
	var best := PackedFloat32Array()
	best.resize(glyph_ids.size())
	best.fill(-1.0)
	var k := kept.size()
	var first: PackedInt32Array = _by_k.get(k, PackedInt32Array())
	var top := _scan(vec, first, best)
	if top < float(opts["fast_accept"]):
		for k2: int in _by_k:
			if k2 != k:
				top = maxf(top, _scan(vec, _by_k[k2], best))
	# rank
	var bi := -1
	var b1 := -1.0
	var b2 := -1.0
	var bj := -1
	for gi in best.size():
		var s := best[gi]
		res["scores"][glyph_ids[gi]] = snappedf(maxf(s, 0.0), 0.0001)
		if s > b1:
			b2 = b1
			bj = bi
			b1 = s
			bi = gi
		elif s > b2:
			b2 = s
			bj = gi
	if bi < 0:
		res["reason"] = "no_templates"
		res["us"] = Time.get_ticks_usec() - t0
		return res
	var thr := float(glyph_defs[bi].get("min_sim", opts["min_sim"])) - float(opts["assist_relax"]) * clampf(assist, 0.0, 1.0)
	var margin := b1 - maxf(b2, 0.0)
	var floor_s := float(opts["confidence_floor"])
	res["sim"] = b1
	res["margin"] = margin
	res["score"] = clampf((b1 - floor_s) / (1.0 - floor_s), 0.0, 1.0)
	res["id"] = glyph_ids[bi]
	res["runner_up"] = glyph_ids[bj] if bj >= 0 else ""
	if b1 < thr:
		res["reason"] = "low"
	elif margin < float(opts["min_margin"]) and bj >= 0:
		res["reason"] = "ambiguous"
	else:
		res["accepted"] = true
		res["glyph"] = StringName(glyph_ids[bi])
	res["us"] = Time.get_ticks_usec() - t0
	return res


## Best similarity per glyph over the given templates (writes into `best`); returns the max.
func _scan(vec: PackedVector2Array, idx: PackedInt32Array, best: PackedFloat32Array) -> float:
	var top := -1.0
	var n := vec.size()
	var clamp_rot := _rot_limit < PI - 1e-6
	for ti in idx:
		var tv: PackedVector2Array = _tv[ti]
		var a := 0.0
		var b := 0.0
		for i in n:
			var t := tv[i]
			var c := vec[i]
			a += t.dot(c)
			b += t.cross(c)
		var sim: float
		if clamp_rot:
			var th := atan2(-b, a)
			th = clampf(th, -_rot_limit, _rot_limit)
			sim = a * cos(th) - b * sin(th)
		else:
			sim = sqrt(a * a + b * b)
		var gi := _tg[ti]
		if sim > best[gi]:
			best[gi] = sim
			if sim > top:
				top = sim
	return top


## Drop repeated points and tiny wiggles (finger jitter under 0.75 px).
func _clean(s: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in s:
		if out.is_empty() or out[out.size() - 1].distance_to(p) >= 0.75:
			out.append(p)
	return out


# ============================================================================ glyph info

func glyph_index(id: String) -> int:
	return glyph_ids.find(id)


func glyph_info(id: String) -> Dictionary:
	var gi := glyph_ids.find(id)
	return glyph_defs[gi] if gi >= 0 else {}


func glyph_color(id: String) -> Color:
	return Color.html(String(glyph_info(id).get("color", "#66c2ff")))


## Canonical strokes of a glyph in the unit square (for ghost guides and the carved rune).
func glyph_strokes(id: String) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	var g := glyph_info(id)
	for s: Array in g.get("strokes", []):
		var pv := PackedVector2Array()
		for p: Array in s:
			pv.append(Vector2(float(p[0]), float(p[1])))
		out.append(pv)
	return out


# ============================================================================ learning and saves

## Store the player's own way of drawing `id` (only if it already looks like that glyph).
func learn(id: String, strokes: Array) -> bool:
	var gi := glyph_ids.find(id)
	if gi < 0:
		return false
	var r := recognize(strokes)
	if float(r["scores"].get(id, 0.0)) < 0.75:
		return false
	var norm := _normalized(strokes)
	if norm.is_empty():
		return false
	var list: Array = _user.get(id, [])
	list.append(norm)
	while list.size() > int(opts["max_user_samples"]):
		list.pop_front()
	_user[id] = list
	rebuild()
	return true


func forget_user_samples() -> void:
	_user.clear()
	rebuild()


func user_sample_count() -> int:
	var c := 0
	for id in _user:
		c += (_user[id] as Array).size()
	return c


## Strokes scaled to fit a unit box (longest side 1), resampled to 12 points, 3 decimals: small JSON.
func _normalized(strokes: Array) -> Array:
	var kept: Array[PackedVector2Array] = []
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for s in strokes:
		var pv := _clean(PackedVector2Array(s))
		if pv.size() < 2:
			continue
		kept.append(pv)
		for p in pv:
			lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
			hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	var size := maxf(hi.x - lo.x, hi.y - lo.y)
	if kept.is_empty() or size < 1e-6 or kept.size() > 3:
		return []
	var out: Array = []
	for pv in kept:
		var rs := resample(pv, 12)
		var arr: Array = []
		for p in rs:
			var q := (p - lo) / size
			arr.append([snappedf(q.x, 0.001), snappedf(q.y, 0.001)])
		out.append(arr)
	return out


func snapshot() -> Dictionary:
	return {"user": _user.duplicate(true)}


func restore(d: Dictionary) -> void:
	_user = (d.get("user", {}) as Dictionary).duplicate(true)
	rebuild()


## Save the learned samples with the rest of Region 1 (Life snapshot, hook H2).
func register_state() -> void:
	RegistryScript.register(STATE_KEY, snapshot, restore, 1)


# ============================================================================ synthetic hand-drawn strokes

## A fake finger drawing of glyph `id` for tests and the scripted canvas demo. Every option is
## a fraction of the glyph size unless noted:
##   jitter (0.035)   per-point noise;   wobble (0.04)   slow hand drift;
##   overshoot (0.07) strokes start/end early or late;   offset (0.05) each stroke drifts a bit;
##   aniso (0.12)     uneven width/height;   scale (px) 60..360;   rotation (rad) any;
##   origin           where to draw (default random in a 1000x1000 area).
## Returns Array[PackedVector2Array] in pixels, points unevenly spaced like a real finger.
func synthesize(id: String, rng: RandomNumberGenerator, o := {}) -> Array:
	var gi := glyph_ids.find(id)
	if gi < 0:
		return []
	var g: Dictionary = glyph_defs[gi]
	var base: Array[PackedVector2Array] = glyph_strokes(id)
	var closed := bool(g.get("closed", false))
	var jitter := float(o.get("jitter", 0.035))
	var wobble := float(o.get("wobble", 0.04))
	var overshoot := float(o.get("overshoot", 0.07))
	var offset := float(o.get("offset", 0.05))
	var aniso := float(o.get("aniso", 0.12))
	var scale_px := float(o.get("scale", rng.randf_range(60.0, 360.0)))
	var rot := float(o.get("rotation", rng.randf_range(-PI, PI)))
	var origin: Vector2 = o.get("origin", Vector2(rng.randf_range(100.0, 900.0), rng.randf_range(100.0, 900.0)))
	var sx := scale_px * (1.0 + rng.randf_range(-aniso, aniso))
	var sy := scale_px * (1.0 + rng.randf_range(-aniso, aniso))
	var mirrored := bool(g.get("mirror", false)) and rng.randf() < 0.5
	# order and direction
	var order := range(base.size())
	if not bool(o.get("keep_order", false)):
		for i in range(order.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var tmp: int = order[i]
			order[i] = order[j]
			order[j] = tmp
	var strokes: Array = []
	for si: int in order:
		var s: PackedVector2Array = base[si]
		if mirrored:
			s = _mirror(s)
		var flip := rng.randf() < 0.5 and not bool(o.get("keep_direction", false))
		if closed and base.size() == 1:
			var ring := PackedVector2Array(s)
			ring.resize(ring.size() - 1)
			var shift := rng.randi_range(0, ring.size() - 1)
			var rolled := PackedVector2Array()
			for q in ring.size():
				rolled.append(ring[(shift + q) % ring.size()])
			rolled.append(rolled[0])
			s = rolled
		if flip:
			s = _reversed(s)
		strokes.append(s)
	var out: Array = []
	var cs := cos(rot)
	var sn := sin(rot)
	for s: PackedVector2Array in strokes:
		var len := path_length(s)
		# uneven finger speed: random gaps, then walk the path
		var count := rng.randi_range(16, 64)
		var gaps := PackedFloat32Array()
		var sum := 0.0
		for i in count:
			var gp := rng.randf_range(0.3, 1.7)
			gaps.append(gp)
			sum += gp
		var dense := resample(s, 200)
		var trim_a := rng.randf_range(-overshoot, overshoot)
		var trim_b := rng.randf_range(-overshoot, overshoot)
		var drift := Vector2(rng.randfn(0.0, offset), rng.randfn(0.0, offset))
		var ph1 := rng.randf() * TAU
		var ph2 := rng.randf() * TAU
		var f1 := rng.randf_range(0.7, 1.6)
		var f2 := rng.randf_range(1.8, 3.4)
		var acc := 0.0
		var pts := PackedVector2Array()
		for i in count:
			acc += gaps[i]
			var t := clampf(acc / sum, 0.0, 1.0)
			var tt := clampf(trim_a + t * (1.0 - trim_a - trim_b), -0.2, 1.2)
			var p := _at(dense, tt)
			p += drift * t
			p += Vector2(sin(ph1 + TAU * f1 * t), cos(ph2 + TAU * f2 * t)) * wobble * 0.5
			p += Vector2(rng.randfn(0.0, jitter), rng.randfn(0.0, jitter))
			p -= Vector2(0.5, 0.5)
			p = Vector2(p.x * sx, p.y * sy)
			p = Vector2(p.x * cs - p.y * sn, p.x * sn + p.y * cs) + origin
			pts.append(p)
		if len > 0.0:
			out.append(pts)
	return out


static func _at(dense: PackedVector2Array, t: float) -> Vector2:
	var f := t * float(dense.size() - 1)
	if f <= 0.0:
		return dense[0] + (dense[0] - dense[1]) * (-f)
	if f >= dense.size() - 1:
		var e := dense.size() - 1
		return dense[e] + (dense[e] - dense[e - 1]) * (f - e)
	var i := int(f)
	return dense[i].lerp(dense[i + 1], f - i)
