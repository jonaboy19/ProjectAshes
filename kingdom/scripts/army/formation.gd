extends RefCounted
## Formation shapes and what they do. Pure maths, no nodes: squad.gd asks for
## local slot offsets and turns them into world positions.
##
## Local space: x is to the formation's right, y is forward (toward the enemy).
## Slots come out in priority order: front rank first, centre outward, so when
## men are missing it is the rear and the far wings that stand empty, and the
## nearest-slot assignment pulls rear-rankers forward into the gaps.
##
## Effects (see STATS):
##   defence   multiplies a soldier's chance to catch a frontal blow on the shield
##   speed     multiplies march speed
##   flank / rear   how exposed the sides and back are (1 = a normal line):
##             extra damage from those directions and extra morale shock
##   missile   share of missile hits that land (loose order and shields help)
##   charge    shock bonus when charging
##   anti_cav  how well it stops horse (the square's reason to exist)
##   morale    cohesion: steadiness from standing shoulder to shoulder

enum Type { LINE, COLUMN, WEDGE, SQUARE, SKIRMISH, SHIELD_WALL }

const NAMES := ["Line", "Column", "Wedge", "Square", "Skirmish", "Shield Wall"]

## dx: spacing along a rank, dz: between ranks.
const STATS := {
	Type.LINE: {"dx": 1.8, "dz": 1.8, "defence": 1.0, "speed": 1.0, "flank": 1.0, "rear": 1.3,
		"missile": 1.0, "charge": 1.0, "anti_cav": 0.2, "morale": 2.0},
	Type.COLUMN: {"dx": 1.6, "dz": 1.6, "defence": 0.85, "speed": 1.25, "flank": 1.5, "rear": 1.2,
		"missile": 1.1, "charge": 0.7, "anti_cav": 0.0, "morale": -2.0},
	Type.WEDGE: {"dx": 1.7, "dz": 1.5, "defence": 0.8, "speed": 1.05, "flank": 1.2, "rear": 1.4,
		"missile": 1.0, "charge": 1.5, "anti_cav": 0.0, "morale": 0.0},
	Type.SQUARE: {"dx": 1.3, "dz": 1.3, "defence": 1.15, "speed": 0.45, "flank": 0.25, "rear": 0.25,
		"missile": 1.2, "charge": 0.3, "anti_cav": 1.0, "morale": 6.0},
	Type.SKIRMISH: {"dx": 3.4, "dz": 3.0, "defence": 0.7, "speed": 1.2, "flank": 0.8, "rear": 1.1,
		"missile": 0.45, "charge": 0.6, "anti_cav": 0.0, "morale": -6.0},
	Type.SHIELD_WALL: {"dx": 1.05, "dz": 1.2, "defence": 1.6, "speed": 0.5, "flank": 1.3, "rear": 1.6,
		"missile": 0.4, "charge": 0.4, "anti_cav": 0.5, "morale": 8.0},
}

## A wheel's outer file walks at most this fast, so wide lines turn slowly.
const WING_SPEED := 2.6
## Turns sharper than this are an about-face: men re-pick slots instead of wheeling.
const ABOUT_FACE := 2.2


static func stats(type: int) -> Dictionary:
	return STATS.get(type, STATS[Type.LINE])


static func type_name(type: int) -> String:
	return NAMES[type] if type >= 0 and type < NAMES.size() else "Line"


## "SHIELD_WALL", "Shield Wall" or "shield_wall" -> Type, -1 if unknown.
static func from_name(n: String) -> int:
	var key := n.to_upper().replace(" ", "_")
	return Type.keys().find(key)


## Files (men per rank) a formation of `count` would form with no width order.
static func default_cols(type: int, count: int) -> int:
	count = maxi(count, 1)
	match type:
		Type.COLUMN:
			return mini(count, 4)
		Type.SHIELD_WALL:
			return clampi(ceili(sqrt(count * 5.0)), 1, count)
		Type.SKIRMISH:
			return clampi(ceili(sqrt(count * 4.0)), 1, count)
		Type.WEDGE, Type.SQUARE:
			return 0    # shape fixed by count
	return clampi(ceili(sqrt(count * 3.0)), 1, count)


## Local slot offsets for `count` men. cols > 0 keeps a set frontage (so a line
## that takes losses thins from the back instead of narrowing).
static func slots(type: int, count: int, cols := 0) -> PackedVector2Array:
	if count <= 0:
		return PackedVector2Array()
	var st := stats(type)
	var dx: float = st["dx"]
	var dz: float = st["dz"]
	if cols <= 0:
		cols = default_cols(type, count)
	match type:
		Type.WEDGE:
			return _wedge(count, dx, dz)
		Type.SQUARE:
			if count < 4:    # too few to form a square: a knot facing out
				return _grid(count, count, dx, dz, false)
			return _square(count, dx)
		Type.SKIRMISH:
			return _grid(count, mini(cols, count), dx, dz, true)
	return _grid(count, mini(cols, count), dx, dz, false)


## Frontage in metres (for turn rate and banner placement).
static func width(local: PackedVector2Array) -> float:
	var lo := 0.0
	var hi := 0.0
	for p in local:
		lo = minf(lo, p.x)
		hi = maxf(hi, p.x)
	return hi - lo


## Which way the man in this slot faces, local. Everyone faces front except in
## the square, where each side faces out.
static func slot_facing(type: int, local: Vector2) -> Vector2:
	if type != Type.SQUARE or local.length_squared() < 0.01:
		return Vector2(0, 1)
	if absf(absf(local.x) - absf(local.y)) < 0.3:
		return Vector2(signf(local.x), signf(local.y)).normalized()
	if absf(local.y) >= absf(local.x):
		return Vector2(0, signf(local.y))
	return Vector2(signf(local.x), 0)


## Radians per second the formation may wheel.
static func turn_rate(local: PackedVector2Array) -> float:
	return clampf(WING_SPEED / maxf(width(local) * 0.5, 1.0), 0.35, 3.0)


## Damage multiplier for a blow arriving from `dir_to_attacker` (world, planar)
## on a formation facing `facing`.
static func incoming_multiplier(type: int, facing: Vector3, dir_to_attacker: Vector3) -> float:
	var st := stats(type)
	var d := Vector3(dir_to_attacker.x, 0, dir_to_attacker.z).normalized()
	var f := Vector3(facing.x, 0, facing.z).normalized()
	var dot := f.dot(d)
	if dot > 0.35:
		return 1.0
	if dot < -0.35:
		return 1.0 + 0.5 * float(st["rear"])
	return 1.0 + 0.25 * float(st["flank"])


## Nearest-slot assignment. men and slot positions are planar world points,
## slot_world in priority order. Returns, for each man, the index of his slot.
## Slots claim the nearest free man front-first (so the front rank is always
## filled), then a swap pass removes crossings; `refine` passes cost O(n²) each,
## so callers use them on orders and skip them for casualties.
static func assign(men: PackedVector2Array, slot_world: PackedVector2Array, refine := 2) -> PackedInt32Array:
	var n := men.size()
	var out := PackedInt32Array()
	out.resize(n)
	out.fill(-1)
	var taken := PackedByteArray()
	taken.resize(n)
	var slot_count := mini(slot_world.size(), n)
	for si in slot_count:
		var sp := slot_world[si]
		var best := -1
		var best_d := INF
		for mi in n:
			if taken[mi] == 0:
				var d := men[mi].distance_squared_to(sp)
				if d < best_d:
					best_d = d
					best = mi
		taken[best] = 1
		out[best] = si
	# More men than slots (shouldn't happen): extras share the last slot.
	for mi in n:
		if out[mi] < 0:
			out[mi] = maxi(slot_world.size() - 1, 0)
	for _pass in refine:
		var swapped := false
		for a in n:
			for b in range(a + 1, n):
				var sa := slot_world[out[a]]
				var sb := slot_world[out[b]]
				var now := men[a].distance_squared_to(sa) + men[b].distance_squared_to(sb)
				var alt := men[a].distance_squared_to(sb) + men[b].distance_squared_to(sa)
				if alt + 0.01 < now:
					var t := out[a]
					out[a] = out[b]
					out[b] = t
					swapped = true
		if not swapped:
			break
	return out


## Local offset -> world point.
static func to_world(local: Vector2, centre: Vector3, facing: Vector3) -> Vector3:
	var f := Vector3(facing.x, 0, facing.z).normalized()
	var right := f.cross(Vector3.UP)
	return centre + right * local.x + f * local.y


## Rotate planar `from` toward `to` by at most `max_angle` radians.
static func rotate_toward(from: Vector3, to: Vector3, max_angle: float) -> Vector3:
	var a := atan2(from.x, from.z)
	var b := atan2(to.x, to.z)
	var diff := wrapf(b - a, -PI, PI)
	var n := a + clampf(diff, -max_angle, max_angle)
	return Vector3(sin(n), 0, cos(n))


static func angle_between(a: Vector3, b: Vector3) -> float:
	return absf(wrapf(atan2(b.x, b.z) - atan2(a.x, a.z), -PI, PI))


# --- Shapes -----------------------------------------------------------------

static func _grid(count: int, cols: int, dx: float, dz: float, loose: bool) -> PackedVector2Array:
	var out := PackedVector2Array()
	var ranks := ceili(float(count) / cols)
	var front := (ranks - 1) * dz * 0.5
	var left := count
	for r in ranks:
		var m := mini(cols, left)
		left -= m
		var y := front - r * dz
		var stagger := (dx * 0.25 if r % 2 == 1 else -dx * 0.25) if loose and ranks > 1 else 0.0
		for x in _centre_out(m, dx):
			var p := Vector2(x + stagger, y)
			if loose:    # irregular but repeatable: a skirmish screen, not a parade
				var h := _hash(out.size())
				p += Vector2((h - 0.5) * dx * 0.3, (_hash(out.size() + 101) - 0.5) * dz * 0.3)
			out.append(p)
	return out


## Tip in front, each row one man wider, the interior filled.
static func _wedge(count: int, dx: float, dz: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var rows := 0
	var cap := 0
	while cap < count:
		rows += 1
		cap += rows
	var front := (rows - 1) * dz * 0.5
	var left := count
	for r in rows:
		var m := mini(r + 1, left)
		left -= m
		for x in _centre_out(m, dx):
			out.append(Vector2(x, front - r * dz))
	return out


## Hollow square, outer ring filled first, every side facing out. One ring
## under 16 men, two under 48, three above.
static func _square(count: int, dx: float) -> PackedVector2Array:
	var depth := 1 if count < 16 else (2 if count < 48 else 3)
	var m := 2
	while _square_capacity(m, depth) < count:
		m += 1
	var out := PackedVector2Array()
	var left := count
	for k in depth:
		var side := m - 2 * k
		if side <= 0 or left <= 0:
			break
		var ring := _ring(side, dx)
		# Front side first, then centre-out, so a short ring still guards the front.
		var order := range(ring.size())
		order.sort_custom(func(a: int, b: int) -> bool:
			var pa := ring[a]
			var pb := ring[b]
			if absf(pa.y - pb.y) > 0.01:
				return pa.y > pb.y
			return absf(pa.x) < absf(pb.x))
		for i: int in order:
			if left <= 0:
				break
			out.append(ring[i])
			left -= 1
	return out


static func _square_capacity(m: int, depth: int) -> int:
	var total := 0
	for k in depth:
		var side := m - 2 * k
		if side == 1:
			total += 1
		elif side >= 2:
			total += 4 * (side - 1)
	return total


static func _ring(side: int, dx: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	if side == 1:
		out.append(Vector2.ZERO)
		return out
	var h := (side - 1) * dx * 0.5
	for i in side:           # front and rear rows, corners included
		var x := -h + i * dx
		out.append(Vector2(x, h))
		out.append(Vector2(x, -h))
	for i in range(1, side - 1):   # the sides, corners excluded
		var y := -h + i * dx
		out.append(Vector2(-h, y))
		out.append(Vector2(h, y))
	return out


## m positions spaced dx, centred on 0, ordered centre outward.
static func _centre_out(m: int, dx: float) -> PackedFloat32Array:
	var xs := PackedFloat32Array()
	var mid := (m - 1) * 0.5
	var idx := range(m)
	idx.sort_custom(func(a: int, b: int) -> bool:
		var da := absf(a - mid)
		var db := absf(b - mid)
		return da < db if absf(da - db) > 0.01 else a < b)
	for i: int in idx:
		xs.append((i - mid) * dx)
	return xs


static func _hash(i: int) -> float:
	var h := (i * 73856093) ^ 0x5bd1e995
	h = (h ^ (h >> 13)) * 1274126177
	return float(h & 0xffff) / 65535.0
