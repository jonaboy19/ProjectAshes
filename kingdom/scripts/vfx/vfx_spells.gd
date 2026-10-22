extends RefCounted
## Spells: rune circles, projectiles (cast -> travel -> impact) and area effects.
## Called through VFX (scripts/vfx/vfx.gd); every function is static, spawns
## under `parent` (the world node) and frees itself. Projectiles return their
## travel time in seconds so gameplay can apply damage when the impact lands.

const K := preload("res://scripts/vfx/vfx_kit.gd")
const Decals := preload("res://scripts/vfx/ground_decals.gd")


# --- rune circles ---------------------------------------------------------------

static func _circle_mat(element: String, energy := 2.4) -> ShaderMaterial:
	var p := K.pal(element)
	var m := K.shader_mat(K.CIRCLE)
	m.set_shader_parameter("tint", p["tint"])
	m.set_shader_parameter("hot", p["hot"])
	m.set_shader_parameter("edge", p["edge"])
	m.set_shader_parameter("energy", energy)
	m.set_shader_parameter("sides", p["sides"])
	m.set_shader_parameter("skip", p["skip"])
	m.set_shader_parameter("glyph_seed", randf() * 100.0)
	m.set_shader_parameter("waves", 1.0 if element == "water" else 0.0)
	m.set_shader_parameter("spiral", 1.0 if element == "wind" else 0.0)
	m.set_shader_parameter("spin", {"earth": 0.06, "lightning": 0.4, "wind": 0.3, "fire": 0.2}.get(element, 0.12))
	return m


## Animated rune circle on the ground. `seconds` <= 0 keeps it until freed.
static func magic_circle(parent: Node, pos: Vector3, element := "qi", radius := 1.6, seconds := 1.4) -> MeshInstance3D:
	var p := K.pal(element)
	var m := _circle_mat(element)
	var mi := K.ground(parent, pos, m, radius * 2.0)
	var draw := 0.45 if seconds <= 0.0 else minf(0.45, seconds * 0.35)
	K.anim(mi, m, "progress", 0.0, 1.0, draw, 0.0, Tween.EASE_OUT, Tween.TRANS_SINE)
	mi.scale = Vector3.ONE * 0.7
	mi.create_tween().tween_property(mi, "scale", Vector3.ONE, draw).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	# Motes rising off the rim.
	K.emit(mi, pos + Vector3(0, 0.05, 0), {"amount": int(10 * radius), "life": 1.1, "one_shot": false, "local": true,
		"shape": "ring", "radius": radius * 0.92, "inner": radius * 0.7, "dir": Vector3.UP, "spread": 8.0,
		"v": Vector2(0.6, 1.6), "size": 0.14, "scale": Vector2(0.5, 1.0), "alpha": "inout",
		"mat": K.sprite_mat(K.DOT, p, 3.0, {"heat": 1.2})})
	if seconds > 0.0:
		K.anim(mi, m, "fade", 1.0, 0.0, 0.35, seconds - 0.35, Tween.EASE_IN)
		K.free_after(mi, seconds)
	return mi


## Small circle standing up in front of the hand, facing `dir`: the cast flourish.
static func cast_sigil(parent: Node, pos: Vector3, dir: Vector3, element := "qi", size := 1.0) -> void:
	var p := K.pal(element)
	var m := _circle_mat(element, 3.0)
	m.set_shader_parameter("spin", 0.6)
	var mi := K.ground(parent, pos, m, size * 1.4)
	mi.global_position = pos
	var d := dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD
	var up := Vector3.UP if absf(d.y) < 0.95 else Vector3.RIGHT
	# PlaneMesh faces +Y: turn +Y to point along the cast direction.
	mi.global_basis = Basis.looking_at(d, up) * Basis(Vector3.RIGHT, -PI * 0.5)
	K.anim(mi, m, "progress", 0.0, 1.0, 0.18)
	K.anim(mi, m, "fade", 1.0, 0.0, 0.3, 0.3, Tween.EASE_IN)
	mi.scale = Vector3.ONE * 0.5
	mi.create_tween().tween_property(mi, "scale", Vector3.ONE * 1.15, 0.6).set_ease(Tween.EASE_OUT)
	K.free_after(mi, 0.65)
	K.glow(parent, pos, p, 1.2 * size, 0.3, K.STAR, 3.5)
	K.emit(parent, pos, {"amount": 10, "life": 0.35, "v": Vector2(2.0, 5.0), "spread": 40.0, "dir": d,
		"size": Vector2(0.05, 0.3), "stretch": true, "damping": Vector2(4, 6),
		"mat": K.sprite_mat(K.DOT, p, 4.0)})


# --- shared impacts -------------------------------------------------------------

static func impact(parent: Node, pos: Vector3, element := "qi", power := 1.0) -> void:
	var p := K.pal(element)
	K.glow(parent, pos, p, 2.6 * power, 0.35, K.STAR, 4.0)
	K.glow(parent, pos, p, 3.4 * power, 0.25, K.RADIAL, 3.0)
	K.light(parent, pos, p["tint"], 3.0 * power, 0.3, 7.0 * power)
	# Ground ring
	var ground := pos
	ground.y -= 0.9
	var rm := K.fx_mat(K.GROUND_RING, p, 2.5, {"width": 0.35, "noise_amt": 0.15})
	var ring := K.ground(parent, ground, rm, 5.0 * power)
	K.anim(ring, rm, "progress", 0.1, 0.9, 0.4)
	K.anim(ring, rm, "fade", 1.0, 0.0, 0.3, 0.15)
	K.free_after(ring, 0.5)
	match element:
		"fire":
			K.emit(parent, pos, {"amount": 18, "life": 0.7, "v": Vector2(1.5, 4.5), "spread": 180.0, "gravity": Vector3(0, 3, 0),
				"damping": Vector2(3, 5), "size": 1.1 * power, "grow": "pop", "spin": true, "shape": "sphere", "radius": 0.3,
				"mat": K.sprite_mat(K.FIRE, p, 3.0, {"spin": true, "cool": 0.9, "heat": 1.3})})
			K.emit(parent, pos, {"amount": 24, "life": 0.6, "v": Vector2(5.0, 11.0), "spread": 180.0, "gravity": Vector3(0, -9, 0),
				"damping": Vector2(1, 2), "size": Vector2(0.06, 0.4), "stretch": true, "mat": K.sprite_mat(K.DOT, p, 5.0, {"heat": 1.5})})
			if not K.lite():
				K.emit(parent, pos + Vector3(0, 0.3, 0), {"amount": 8, "life": 1.6, "v": Vector2(0.5, 1.5), "spread": 60.0,
					"gravity": Vector3(0, 1.0, 0), "size": 1.6 * power, "grow": "grow", "alpha": "inout", "spin": true,
					"mat": K.sprite_mat(K.SMOKE_PUFF, {"tint": Color(0.22, 0.19, 0.18), "hot": Color(0.45, 0.4, 0.35), "edge": Color(0.1, 0.09, 0.09)}, 1.0, {"mix": true, "spin": true, "cool": 0.0})})
			_scorch(parent, ground, 2.2 * power)
		"water":
			K.emit(parent, pos, {"amount": 30, "life": 0.8, "v": Vector2(3.0, 7.0), "spread": 70.0, "gravity": Vector3(0, -14, 0),
				"size": Vector2(0.08, 0.35), "stretch": true, "damping": Vector2(0.2, 0.6), "mat": K.sprite_mat(K.DOT, p, 3.5, {"heat": 1.3})})
			K.emit(parent, pos, {"amount": 8, "life": 0.9, "v": Vector2(0.5, 1.5), "spread": 180.0, "size": 1.6 * power,
				"grow": "grow", "alpha": "inout", "mat": K.sprite_mat(K.DOT, p, 0.7, {"cool": 0.5})})
		"wind":
			K.emit(parent, pos, {"amount": 10, "life": 0.5, "v": Vector2(2.0, 5.0), "spread": 180.0, "size": 1.3 * power,
				"grow": "grow", "spin": true, "angular": Vector2(300, 600), "mat": K.sprite_mat(K.TWIRL, p, 2.5, {"spin": true, "cool": 0.5})})
			K.emit(parent, pos, {"amount": 16, "life": 0.4, "v": Vector2(6.0, 12.0), "spread": 180.0, "size": Vector2(0.06, 0.6),
				"stretch": true, "damping": Vector2(8, 12), "mat": K.sprite_mat(K.STREAK, p, 3.0)})
		"lightning":
			K.emit(parent, pos, {"amount": 8, "life": 0.2, "shape": "sphere", "radius": 0.6, "v": Vector2(0, 0.5),
				"size": 1.2 * power, "spin": true, "grow": "flat", "mat": K.sprite_mat(K.BRANCH, p, 4.0, {"spin": true, "cool": 0.0})})
			K.emit(parent, pos, {"amount": 20, "life": 0.35, "v": Vector2(6.0, 14.0), "spread": 180.0, "gravity": Vector3(0, -6, 0),
				"size": Vector2(0.04, 0.35), "stretch": true, "damping": Vector2(3, 6), "mat": K.sprite_mat(K.DOT, p, 5.0, {"heat": 1.5})})
		"earth":
			K.emit(parent, pos, {"amount": 14, "life": 1.0, "v": Vector2(3.0, 7.0), "spread": 50.0, "gravity": Vector3(0, -16, 0),
				"size": 0.5 * power, "spin": true, "angular": Vector2(-400, 400), "grow": "flat", "alpha": "late",
				"mat": K.sprite_mat(K.DEBRIS, {"tint": Color(0.45, 0.33, 0.22), "hot": Color(0.7, 0.55, 0.38), "edge": Color(0.2, 0.14, 0.1)}, 1.0, {"mix": true, "spin": true, "cool": 0.0})})
			_dust(parent, ground, 1.8 * power)
		_:
			K.emit(parent, pos, {"amount": 22, "life": 0.7, "v": Vector2(3.0, 8.0), "spread": 180.0, "damping": Vector2(3, 5),
				"size": 0.35, "spin": true, "mat": K.sprite_mat(K.SPARKLE, p, 4.0, {"spin": true, "heat": 1.3})})


static func _scorch(parent: Node, ground: Vector3, size: float) -> void:
	var m := K.sprite_mat(K.SCORCH, {"tint": Color(0.08, 0.05, 0.04), "hot": Color(0.15, 0.08, 0.04), "edge": Color(0.02, 0.02, 0.02)}, 1.0,
		{"mix": true, "particle": false, "cool": 0.0})
	var mi := K.ground(parent, ground, m, size)
	mi.rotation.y = randf() * TAU
	K.anim(mi, m, "fade", 0.7, 0.0, 1.5, 2.5, Tween.EASE_IN)
	K.free_after(mi, 4.1)


static func _dust(parent: Node, ground: Vector3, radius: float) -> void:
	if K.lite():
		return
	K.emit(parent, ground + Vector3(0, 0.2, 0), {"amount": 10, "life": 1.4, "shape": "ring", "radius": radius * 0.5, "inner": 0.1,
		"dir": Vector3.UP, "spread": 80.0, "v": Vector2(1.0, 2.5), "radial": Vector2(1.0, 2.0), "gravity": Vector3(0, 0.3, 0),
		"damping": Vector2(1, 2), "size": 1.6, "grow": "grow", "alpha": "inout", "spin": true,
		"mat": K.sprite_mat(K.SMOKE_PUFF, {"tint": Color(0.62, 0.52, 0.4), "hot": Color(0.8, 0.72, 0.6), "edge": Color(0.35, 0.28, 0.2)}, 1.0, {"mix": true, "spin": true, "cool": 0.0})})


# --- projectiles ----------------------------------------------------------------

## Missiles: `missile()` makes the flying root, `trail()` adds a world-space
## emitter that follows it (RemoteTransform3D, no per-frame script), `arm()`
## wires the impact. Whoever holds the returned root may fly it (the technique
## caster moves it every physics frame and frees it on impact). If nobody has
## moved it 0.06 s after the cast, it flies itself to `to` at `speed`. The impact
## plays wherever the root is when it leaves the tree.

static func missile(parent: Node, from: Vector3, to: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = "Missile"
	K.add(parent, root, from)
	var d := to - from
	if d.length() > 0.01:
		root.global_basis = Basis.looking_at(d.normalized(), Vector3.UP if absf(d.normalized().y) < 0.95 else Vector3.RIGHT)
	return root


static func trail(root: Node3D, parent: Node, cfg: Dictionary) -> GPUParticles3D:
	var c := cfg.duplicate()
	c["one_shot"] = false
	c["local"] = false
	var e := K.emit(parent, root.global_position, c)
	var rt := RemoteTransform3D.new()
	rt.update_rotation = false
	rt.update_scale = false
	root.add_child(rt)
	rt.remote_path = rt.get_path_to(e)
	return e


static func arm(root: Node3D, parent: Node, from: Vector3, to: Vector3, speed: float, element: String, power: float, trails: Array) -> void:
	root.tree_exiting.connect(_missile_gone.bind(root, parent, element, power, trails), CONNECT_ONE_SHOT)
	var tw := root.create_tween()
	tw.tween_interval(0.06)
	tw.tween_callback(_self_fly.bind(root, from, to, speed))
	K.free_after(root, 12.0)


static func _self_fly(root: Node3D, from: Vector3, to: Vector3, speed: float) -> void:
	if root.global_position.distance_to(from) > 0.01:
		return    # someone else is flying it
	var secs := maxf(from.distance_to(to) / maxf(speed, 0.1), 0.05)
	var tw := root.create_tween()
	tw.tween_property(root, "global_position", to, secs)
	tw.tween_callback(root.queue_free)


static func _missile_gone(root: Node3D, parent: Node, element: String, power: float, trails: Array) -> void:
	var at := root.global_position
	for e: Variant in trails:
		if is_instance_valid(e) and (e as Node).is_inside_tree() and not (e as Node).is_queued_for_deletion():
			K.stop(e)
	if element != "":
		_impact_later.call_deferred(parent, at, element, power)


static func _impact_later(parent: Variant, at: Vector3, element: String, power: float) -> void:
	if is_instance_valid(parent) and (parent as Node).is_inside_tree():
		impact(parent as Node, at, element, power)


static func _trail_light(root: Node3D, color: Color, energy := 1.5) -> void:
	if not K.rich():
		return
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = 4.0
	root.add_child(l)


static func _smoke_pal() -> Dictionary:
	return {"tint": Color(0.25, 0.2, 0.18), "hot": Color(0.4, 0.33, 0.28), "edge": Color(0.1, 0.08, 0.08)}


## Fireball: cast sigil, a churning orb shedding flames, embers and smoke, and a
## fiery blast with a scorch mark. Returns the missile root (see missile()).
static func fireball(parent: Node, from: Vector3, to: Vector3, power := 1.0, speed := 16.0) -> Node3D:
	var p := K.pal("fire")
	cast_sigil(parent, from, to - from, "fire", power)
	var root := missile(parent, from, to)
	K.quad(root, from, K.fx_mat(K.ORB, p, 3.2, {"twist": 1.0, "noise_amt": 0.6, "speed": 1.5}), 1.15 * power)
	var trails := [
		trail(root, parent, {"amount": 30, "life": 0.5, "shape": "sphere", "radius": 0.2 * power, "v": Vector2(0.2, 0.8),
			"spread": 180.0, "gravity": Vector3(0, 2.5, 0), "size": 1.2 * power, "scale": Vector2(0.5, 1.0), "spin": true,
			"mat": K.sprite_mat(K.FIRE, p, 3.0, {"distort": 0.2, "cool": 0.9, "heat": 1.4, "spin": true})}),
		trail(root, parent, {"amount": 14, "life": 0.6, "shape": "sphere", "radius": 0.25, "v": Vector2(0.5, 1.5),
			"spread": 180.0, "gravity": Vector3(0, 1.5, 0), "size": Vector2(0.05, 0.22), "stretch": true,
			"mat": K.sprite_mat(K.DOT, p, 5.0, {"heat": 1.4})})]
	if not K.lite():
		trails.append(trail(root, parent, {"amount": 10, "life": 1.0, "v": Vector2(0.1, 0.4), "spread": 180.0,
			"gravity": Vector3(0, 0.8, 0), "size": 0.8 * power, "grow": "grow", "alpha": "inout", "spin": true,
			"mat": K.sprite_mat(K.SMOKE_PUFF, _smoke_pal(), 1.0, {"mix": true, "spin": true, "cool": 0.0})}))
	_trail_light(root, p["tint"], 2.0)
	arm(root, parent, from, to, speed, "fire", power, trails)
	return root


## Wind blade: a pair of crescent air blades, convex edge first, trailing streaks.
static func wind_blade(parent: Node, from: Vector3, to: Vector3, power := 1.0, speed := 22.0) -> Node3D:
	return crescent(parent, from, to, "wind", power, speed)


## Flying crescent (wind blade, sword qi). Returns the missile root.
static func crescent(parent: Node, from: Vector3, to: Vector3, element := "wind", power := 1.0, speed := 22.0) -> Node3D:
	var p := K.pal(element)
	if element == "wind":
		cast_sigil(parent, from, to - from, element, power)
	var root := missile(parent, from, to)
	for k in 2:
		var r := (1.3 - k * 0.35) * power
		var m := K.fx_mat(K.SMEAR, p, 2.6 + k, {"tail": 1.2, "progress": 1.0, "noise_amt": 0.4, "speed": 4.0})
		var mi := K.mesh_node(root, K.arc_mesh(r, 150.0, 0.5), m, from)
		# Convex edge leads: flip the arc to face -Z (forward) and centre its apex.
		mi.position = Vector3(0, 0, r * 0.8)
		mi.rotation = Vector3(0, PI, 0.25 - k * 0.5)
	var trails := [trail(root, parent, {"amount": 16, "life": 0.35, "shape": "box", "extents": Vector3(0.9, 0.2, 0.9) * power,
		"v": Vector2(0.2, 0.6), "spread": 180.0, "size": Vector2(0.05, 0.9), "stretch": true, "mat": K.sprite_mat(K.STREAK, p, 2.5)})]
	arm(root, parent, from, to, speed, element, power * 0.8, trails)
	return root


## Qi palm: a swirling golden orb inside a halo, shedding rings of force.
static func qi_palm(parent: Node, from: Vector3, to: Vector3, power := 1.0, speed := 14.0) -> Node3D:
	var p := K.pal("qi")
	cast_sigil(parent, from, to - from, "qi", 1.2 * power)
	var root := missile(parent, from, to)
	K.quad(root, from, K.fx_mat(K.ORB, p, 3.0, {"twist": 2.0, "noise_amt": 0.4, "speed": 2.0}), 1.3 * power)
	K.quad(root, from, K.sprite_mat(K.RING, p, 2.5, {"particle": false, "billboard": true, "bb_scale": 1.9 * power}), 1.0)
	var trails := [
		trail(root, parent, {"amount": 18, "life": 0.5, "shape": "sphere", "radius": 0.45 * power, "v": Vector2(0.3, 1.0),
			"spread": 180.0, "size": 0.25, "spin": true, "mat": K.sprite_mat(K.SPARKLE, p, 4.0, {"spin": true})}),
		trail(root, parent, {"amount": 6, "life": 0.35, "v": Vector2.ZERO, "size": 2.2 * power, "grow": "grow",
			"mat": K.sprite_mat(K.RING, p, 2.0, {"cool": 0.5})})]
	_trail_light(root, p["tint"], 1.5)
	arm(root, parent, from, to, speed, "qi", power * 1.2, trails)
	return root


static func water_whip(parent: Node, from: Vector3, to: Vector3, power := 1.0) -> float:
	var p := K.pal("water")
	var dir := to - from
	cast_sigil(parent, from, dir, "water", power)
	var side := dir.cross(Vector3.UP).normalized()
	if side.length() < 0.01:
		side = Vector3.RIGHT
	var pts := PackedVector3Array()
	var n := 28
	var phase := randf() * TAU
	for i in n:
		var t := float(i) / (n - 1)
		var wave := sin(t * 9.0 + phase) * 0.45 * sin(PI * t) * power
		pts.append(from.lerp(to, t) + side * wave + Vector3.UP * sin(PI * t) * 0.8)
	var secs := 0.22
	for up: Vector3 in [Vector3.UP, side]:
		var m := K.fx_mat(K.SMEAR, p, 2.8, {"tail": 1.2, "noise_amt": 0.5, "speed": 3.0})
		var mi := K.world_mesh(parent, K.path_mesh(pts, 0.35 * power, up), m)
		K.anim(mi, m, "progress", 0.0, 1.05, secs, 0.0, Tween.EASE_OUT, Tween.TRANS_CUBIC)
		K.anim(mi, m, "dissolve", 0.0, 1.0, 0.35, secs + 0.1)
		K.free_after(mi, secs + 0.5)
	# Droplets flung along the lash.
	var mid := from.lerp(to, 0.5) + Vector3.UP * 0.6
	K.emit(parent, mid, {"amount": 16, "life": 0.6, "shape": "box", "extents": Vector3(0.3, 0.3, 0.3) + side.abs() * 0.1 + dir.abs() * 0.45,
		"v": Vector2(1.0, 3.0), "spread": 180.0, "gravity": Vector3(0, -12, 0), "size": Vector2(0.06, 0.22), "stretch": true,
		"delay": secs * 0.5, "mat": K.sprite_mat(K.DOT, p, 3.0, {"heat": 1.3})})
	var tw := parent.create_tween()
	tw.tween_interval(secs)
	tw.tween_callback(impact.bind(parent, to, "water", power))
	return secs


## Rock spikes erupt from the ground in a line from under `from` to `to`, or,
## when the two are (nearly) the same spot, in a ring of `radius` around `to`.
## Returns the time until the last spike is up.
static func earth_spike(parent: Node, from: Vector3, to: Vector3, power := 1.0, radius := 2.5) -> float:
	var p := K.pal("earth")
	var a := Vector3(from.x, to.y, from.z)
	var pts: Array[Vector3] = []
	var hs: Array[float] = []
	var flat := Vector2(to.x - a.x, to.z - a.z).length()
	if flat < 1.2:
		var n := clampi(int(radius * 3.0), 6, 14)
		for i in n:
			var ang := TAU * i / n + randf_range(-0.15, 0.15)
			pts.append(to + Vector3(cos(ang), 0, sin(ang)) * radius * randf_range(0.75, 1.0))
			hs.append(randf_range(1.2, 2.0) * power)
		magic_circle(parent, to, "earth", radius * 0.8, 1.0)
		spikes(parent, pts, hs, 0.02, power)
		_crack(parent, to, p, radius * 2.4, 0.3)
		return 0.3
	var dir := to - a
	var count := clampi(int(dir.length() / 1.1), 2, 10)
	var side := dir.cross(Vector3.UP).normalized()
	for i in count:
		var t := float(i + 1) / count
		pts.append(a.lerp(to, t) + side * randf_range(-0.35, 0.35))
		hs.append(lerpf(0.9, 2.2, t) * power * randf_range(0.8, 1.15))
	magic_circle(parent, a, "earth", 1.1 * power, 1.0)
	spikes(parent, pts, hs, 0.06, power)
	_crack(parent, a.lerp(to, 0.55), p, dir.length() * 1.1 + 1.0, count * 0.06 + 0.1)
	return count * 0.06


static func _crack(parent: Node, at: Vector3, p: Dictionary, size: float, spread: float) -> void:
	var cm := K.fx_mat(K.CRACK, p, 2.5, {"width": 0.6})
	var crack := K.ground(parent, at, cm, size)
	K.anim(crack, cm, "progress", 0.0, 1.0, spread)
	K.anim(crack, cm, "fade", 1.0, 0.0, 0.6, 0.9)
	K.free_after(crack, 1.6)


static func _rock_mat() -> StandardMaterial3D:
	var rock := StandardMaterial3D.new()
	rock.albedo_color = Color(0.36, 0.3, 0.25)
	rock.roughness = 1.0
	rock.emission_enabled = true
	rock.emission = Color(1.0, 0.5, 0.15)
	rock.emission_energy_multiplier = 0.04
	return rock


static func _debris_pal() -> Dictionary:
	return {"tint": Color(0.45, 0.33, 0.22), "hot": Color(0.7, 0.55, 0.38), "edge": Color(0.2, 0.14, 0.1)}


## Stone cones that punch up out of the ground at `pts`, hold, then sink.
static func spikes(parent: Node, pts: Array[Vector3], heights: Array[float], step: float, power := 1.0, hold := 0.7) -> void:
	var rock := _rock_mat()
	var dust := {"tint": Color(0.62, 0.52, 0.4), "hot": Color(0.8, 0.72, 0.6), "edge": Color(0.35, 0.28, 0.2)}
	for i in pts.size():
		var at := pts[i]
		var h := heights[i]
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.2 * power + h * 0.12
		cone.height = h
		cone.radial_segments = 5
		cone.rings = 1
		cone.material = rock
		var mi := MeshInstance3D.new()
		mi.mesh = cone
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		K.add(parent, mi, at - Vector3(0, h * 0.5, 0))
		mi.rotation = Vector3(randf_range(-0.25, 0.25), randf() * TAU, randf_range(-0.25, 0.25))
		var delay := i * step
		var tw := mi.create_tween()
		tw.tween_interval(delay)
		tw.tween_property(mi, "global_position", at + Vector3(0, h * 0.45, 0), 0.09).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tw.tween_interval(hold)
		tw.tween_property(mi, "global_position", at - Vector3(0, h * 0.55, 0), 0.4).set_ease(Tween.EASE_IN)
		tw.tween_callback(mi.queue_free)
		K.emit(parent, at + Vector3(0, 0.1, 0), {"amount": 6, "life": 0.8, "v": Vector2(2.0, 5.0), "spread": 40.0, "gravity": Vector3(0, -16, 0),
			"size": 0.3, "spin": true, "grow": "flat", "alpha": "late", "delay": delay, "angular": Vector2(-300, 300),
			"mat": K.sprite_mat(K.DEBRIS, _debris_pal(), 1.0, {"mix": true, "spin": true, "cool": 0.0})})
		if i % 2 == 0 and not K.lite():
			K.emit(parent, at + Vector3(0, 0.2, 0), {"amount": 4, "life": 1.0, "v": Vector2(0.5, 1.5), "spread": 70.0, "size": 1.3,
				"grow": "grow", "alpha": "inout", "spin": true, "delay": delay,
				"mat": K.sprite_mat(K.SMOKE_PUFF, dust, 1.0, {"mix": true, "spin": true, "cool": 0.0})})


## Lightning jumps from `from` through each point in `targets`, 0.07 s per hop.
static func lightning_chain(parent: Node, from: Vector3, targets: Array, power := 1.0) -> float:
	var p := K.pal("lightning")
	if targets.is_empty():
		return 0.0
	cast_sigil(parent, from, (targets[0] as Vector3) - from, "lightning", power)
	var hop := 0.07
	var prev := from
	for i in targets.size():
		var at: Vector3 = targets[i]
		var tw := parent.create_tween()
		tw.tween_interval(i * hop)
		tw.tween_callback(_bolt.bind(parent, prev, at, p, 0.13 * power, true))
		prev = at
	return targets.size() * hop


static func _bolt(parent: Node, a: Vector3, b: Vector3, p: Dictionary, width: float, hit: bool) -> void:
	var len := a.distance_to(b)
	for k in (2 if K.lite() else 3):
		var w := width * (1.0 if k == 0 else 0.45)
		var m := K.fx_mat(K.BEAM, p, 3.5 if k == 0 else 2.5, {"speed": 3.0})
		var bb := b if k == 0 else a.lerp(b, randf_range(0.4, 0.8)) + Vector3(randf_range(-1, 1), randf_range(-0.5, 0.5), randf_range(-1, 1)) * len * 0.2
		var mi := K.world_mesh(parent, K.bolt_mesh(a, bb, clampf(len * 0.08, 0.15, 0.8), w, clampi(int(len * 1.5), 5, 14)), m)
		var tw := mi.create_tween()
		tw.tween_property(m, "shader_parameter/fade", 0.25, 0.05)
		tw.tween_property(m, "shader_parameter/fade", 1.0, 0.03)
		tw.tween_property(m, "shader_parameter/fade", 0.0, 0.16)
		tw.tween_callback(mi.queue_free)
	if hit:
		K.glow(parent, b, p, 2.2, 0.25, K.STAR, 4.5)
		K.light(parent, b, p["tint"], 4.0, 0.2, 8.0)
		K.emit(parent, b, {"amount": 14, "life": 0.3, "v": Vector2(5.0, 11.0), "spread": 180.0, "gravity": Vector3(0, -8, 0),
			"size": Vector2(0.04, 0.3), "stretch": true, "damping": Vector2(3, 6), "mat": K.sprite_mat(K.DOT, p, 5.0, {"heat": 1.5})})
		K.emit(parent, b, {"amount": 4, "life": 0.18, "shape": "sphere", "radius": 0.5, "v": Vector2.ZERO, "size": 1.0,
			"spin": true, "grow": "flat", "mat": K.sprite_mat(K.BRANCH, p, 4.0, {"spin": true, "cool": 0.0})})


# --- area effects ---------------------------------------------------------------

static func _column(parent: Node, pos: Vector3, p: Dictionary, r_bottom: float, r_top: float, height: float, opts: Dictionary, energy := 2.6) -> Array:
	var cyl := CylinderMesh.new()
	cyl.bottom_radius = r_bottom
	cyl.top_radius = r_top
	cyl.height = height
	cyl.cap_top = false
	cyl.cap_bottom = false
	cyl.radial_segments = 20
	cyl.rings = 2
	var m := K.fx_mat(K.COLUMN, p, energy, opts)
	var mi := K.mesh_node(parent, cyl, m, pos + Vector3(0, height * 0.5, 0))
	return [mi, m]


static func fire_pillar(parent: Node, pos: Vector3, radius := 1.2, seconds := 1.8) -> void:
	var p := K.pal("fire")
	magic_circle(parent, pos, "fire", radius * 1.7, seconds + 0.3)
	var h := 6.0 * radius
	for k in 2:
		var c := _column(parent, pos, p, radius * (1.0 - k * 0.45), radius * (0.8 - k * 0.3), h * (1.0 - k * 0.15),
			{"speed": 1.6 + k, "twist": 0.3, "noise_amt": 0.4}, 2.4 + k * 1.2)
		var mi: MeshInstance3D = c[0]
		var m: ShaderMaterial = c[1]
		mi.scale = Vector3(1, 0.05, 1)
		var tw := mi.create_tween()
		tw.tween_property(mi, "scale", Vector3.ONE, 0.18).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		K.anim(mi, m, "dissolve", 0.0, 1.0, 0.45, seconds - 0.45, Tween.EASE_IN)
		K.free_after(mi, seconds + 0.05)
	var flames := K.emit(parent, pos, {"amount": 30, "life": 0.9, "one_shot": false, "shape": "disc", "radius": radius * 0.8,
		"v": Vector2(4.0, 8.0), "spread": 8.0, "size": 1.2 * radius, "gravity": Vector3(0, 2, 0),
		"mat": K.sprite_mat(K.FLAME, p, 3.0, {"distort": 0.3, "cool": 0.9, "heat": 1.3})})
	var embers := K.emit(parent, pos, {"amount": 24, "life": 1.2, "one_shot": false, "shape": "disc", "radius": radius,
		"v": Vector2(5.0, 10.0), "spread": 15.0, "size": Vector2(0.06, 0.3), "stretch": true, "damping": Vector2(1, 2),
		"mat": K.sprite_mat(K.DOT, p, 5.0, {"heat": 1.4})})
	_stop_later(parent, seconds - 0.4, [flames, embers])
	impact(parent, pos + Vector3(0, 0.9, 0), "fire", radius)
	K.light(parent, pos + Vector3(0, 2, 0), p["tint"], 4.0, seconds, 10.0)


## Stop looping emitters (created by this module) after `delay`.
static func _stop_later(owner: Node, delay: float, emitters: Array) -> void:
	var tw := owner.create_tween()
	tw.tween_interval(maxf(delay, 0.01))
	for e: GPUParticles3D in emitters:
		tw.tween_callback(K.stop.bind(e))


static func whirlwind(parent: Node, pos: Vector3, radius := 1.5, seconds := 2.5) -> void:
	var p := K.pal("wind")
	magic_circle(parent, pos, "wind", radius * 1.6, seconds)
	var h := 4.5 * radius
	for k in 2:
		var c := _column(parent, pos, p, radius * (0.35 + k * 0.25), radius * (1.3 + k * 0.4), h * (1.0 - k * 0.2),
			{"speed": 2.0, "twist": 1.6 - k * 3.0, "noise_amt": 0.5}, 1.8 + k * 0.6)
		var mi: MeshInstance3D = c[0]
		var m: ShaderMaterial = c[1]
		var tw := mi.create_tween()
		tw.tween_property(mi, "rotation:y", TAU * seconds * (1.2 if k == 0 else -0.8), seconds)
		mi.scale = Vector3(0.2, 1.0, 0.2)
		mi.create_tween().tween_property(mi, "scale", Vector3.ONE, 0.3).set_ease(Tween.EASE_OUT)
		K.anim(mi, m, "fade", 0.0, 1.0, 0.25)
		K.anim(mi, m, "dissolve", 0.0, 1.0, 0.5, seconds - 0.5, Tween.EASE_IN)
		K.free_after(mi, seconds + 0.05)
	# Dust and leaves swept around the vertical axis (tangent accel needs gravity).
	var swirl := K.emit(parent, pos + Vector3(0, 0.3, 0), {"life": 1.4, "one_shot": false, "shape": "ring",
		"radius": radius, "inner": radius * 0.4, "v": Vector2(1.5, 3.0), "spread": 10.0, "gravity": Vector3(0, 1.5, 0),
		"tangent": Vector2(8.0, 12.0), "radial": Vector2(-2.0, -1.0), "size": 0.6, "spin": true, "angular": Vector2(200, 500),
		"alpha": "inout", "amount": 18, "mat": K.sprite_mat(K.TWIRL, p, 1.6, {"spin": true, "cool": 0.4})})
	var dust: GPUParticles3D = null
	if not K.lite():
		dust = K.emit(parent, pos + Vector3(0, 0.2, 0), {"amount": 10, "life": 1.6, "one_shot": false, "shape": "ring",
			"radius": radius * 1.2, "inner": radius * 0.5, "v": Vector2(1.0, 2.0), "spread": 20.0, "gravity": Vector3(0, 1.0, 0),
			"tangent": Vector2(5.0, 8.0), "size": 1.6, "grow": "grow", "alpha": "inout", "spin": true,
			"mat": K.sprite_mat(K.SMOKE_PUFF, {"tint": Color(0.7, 0.66, 0.55), "hot": Color(0.85, 0.82, 0.72), "edge": Color(0.4, 0.37, 0.3)}, 1.0, {"mix": true, "spin": true, "cool": 0.0})})
	_stop_later(parent, seconds - 0.5, [swirl, dust] if dust else [swirl])


## A ring of water that crashes outward (tidal splash).
static func tidal_ring(parent: Node, pos: Vector3, radius := 4.0) -> void:
	var p := K.pal("water")
	var secs := 0.7
	var rm := K.fx_mat(K.GROUND_RING, p, 3.5, {"width": 0.8, "noise_amt": 0.25, "speed": 2.0})
	var ring := K.ground(parent, pos, rm, radius * 2.0)
	K.anim(ring, rm, "progress", 0.05, 0.95, secs, 0.0, Tween.EASE_OUT, Tween.TRANS_CUBIC)
	K.anim(ring, rm, "fade", 1.0, 0.0, 0.4, secs - 0.2)
	K.free_after(ring, secs + 0.3)
	var c := _column(parent, pos, p, 1.0, 1.05, 1.4, {"speed": 3.0, "noise_amt": 0.6}, 2.2)
	var wall: MeshInstance3D = c[0]
	var wm: ShaderMaterial = c[1]
	wall.scale = Vector3(0.1, 1.0, 0.1)
	var tw := wall.create_tween().set_parallel()
	tw.tween_property(wall, "scale", Vector3(radius * 0.95, 0.3, radius * 0.95), secs).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	K.anim(wall, wm, "dissolve", 0.0, 1.0, secs * 0.8, secs * 0.3)
	K.free_after(wall, secs + 0.1)
	K.emit(parent, pos + Vector3(0, 0.2, 0), {"amount": 40, "life": 0.9, "shape": "ring", "radius": 0.6, "inner": 0.3,
		"dir": Vector3.UP, "spread": 50.0, "v": Vector2(4.0, 8.0), "radial": Vector2(4.0, 8.0), "gravity": Vector3(0, -14, 0),
		"size": Vector2(0.08, 0.35), "stretch": true, "damping": Vector2(0.2, 0.5), "mat": K.sprite_mat(K.DOT, p, 3.5, {"heat": 1.3})})
	if not K.lite():
		K.emit(parent, pos + Vector3(0, 0.3, 0), {"amount": 12, "life": 1.0, "shape": "ring", "radius": 0.8, "inner": 0.2,
			"spread": 70.0, "v": Vector2(1.0, 2.0), "radial": Vector2(4.0, 6.0), "size": 1.6, "grow": "grow", "alpha": "inout",
			"mat": K.sprite_mat(K.DOT, p, 0.6, {"cool": 0.5})})
	K.glow(parent, pos + Vector3(0, 0.5, 0), p, 3.0, 0.35, K.STAR, 3.0)


static func earthquake(parent: Node, pos: Vector3, radius := 4.0, seconds := 2.0) -> void:
	var p := {"tint": Color(1.0, 0.45, 0.1), "hot": Color(1.0, 0.85, 0.5), "edge": Color(0.45, 0.08, 0.02)}
	var cm := K.fx_mat(K.CRACK, p, 3.0, {"width": 1.0, "speed": 1.0})
	var crack := K.ground(parent, pos, cm, Decals.crack_size(radius))     # a few metres across, not the whole AoE disc
	K.anim(crack, cm, "progress", 0.05, 1.0, 0.45, 0.0, Tween.EASE_OUT, Tween.TRANS_CUBIC)
	K.anim(crack, cm, "fade", 1.0, 0.0, 0.7, seconds - 0.7, Tween.EASE_IN)
	K.free_after(crack, seconds + 0.05)
	var shock := K.fx_mat(K.GROUND_RING, K.pal("earth"), 2.0, {"width": 0.3, "noise_amt": 0.3})
	var ring := K.ground(parent, pos, shock, radius * 2.4)
	K.anim(ring, shock, "progress", 0.05, 0.95, 0.5)
	K.anim(ring, shock, "fade", 1.0, 0.0, 0.3, 0.3)
	K.free_after(ring, 0.65)
	K.emit(parent, pos + Vector3(0, 0.2, 0), {"amount": 24, "life": 1.2, "shape": "disc", "radius": radius * 0.7,
		"v": Vector2(3.0, 8.0), "spread": 25.0, "gravity": Vector3(0, -16, 0), "size": 0.45, "spin": true, "grow": "flat",
		"alpha": "late", "angular": Vector2(-400, 400), "explosive": 0.6,
		"mat": K.sprite_mat(K.DEBRIS, {"tint": Color(0.45, 0.33, 0.22), "hot": Color(0.7, 0.55, 0.38), "edge": Color(0.2, 0.14, 0.1)}, 1.0, {"mix": true, "spin": true, "cool": 0.0})})
	K.emit(parent, pos + Vector3(0, 0.1, 0), {"amount": 16, "life": 0.8, "shape": "disc", "radius": radius * 0.6,
		"v": Vector2(1.0, 3.0), "spread": 20.0, "size": Vector2(0.05, 0.3), "stretch": true, "mat": K.sprite_mat(K.DOT, p, 4.0, {"heat": 1.3})})
	_dust(parent, pos, radius)
	K.light(parent, pos + Vector3(0, 0.5, 0), p["tint"], 2.0, seconds * 0.5, radius * 2.0)


static func thunderstorm(parent: Node, pos: Vector3, radius := 4.0, strikes := 5, seconds := 2.0) -> void:
	var p := K.pal("lightning")
	magic_circle(parent, pos, "lightning", radius, seconds + 0.4)
	if not K.lite():
		var cloud := K.emit(parent, pos + Vector3(0, 11, 0), {"amount": 14, "life": 1.6, "one_shot": false, "shape": "disc",
			"radius": radius * 1.1, "v": Vector2(0.1, 0.4), "spread": 180.0, "size": 5.0, "grow": "grow", "alpha": "inout", "spin": true,
			"mat": K.sprite_mat(K.SMOKE_PUFF, {"tint": Color(0.18, 0.16, 0.26), "hot": Color(0.4, 0.38, 0.6), "edge": Color(0.08, 0.07, 0.12)}, 1.0, {"mix": true, "spin": true, "cool": 0.0})})
		_stop_later(parent, seconds, [cloud])
	for i in strikes:
		var a := randf() * TAU
		var r := sqrt(randf()) * radius * 0.85
		var at := pos + Vector3(cos(a) * r, 0, sin(a) * r)
		var sky := at + Vector3(randf_range(-1.5, 1.5), 11.0, randf_range(-1.5, 1.5))
		var tw := parent.create_tween()
		tw.tween_interval(0.25 + (float(i) / maxf(strikes, 1)) * (seconds - 0.4) + randf() * 0.1)
		tw.tween_callback(_strike.bind(parent, sky, at, p))


static func _strike(parent: Node, sky: Vector3, at: Vector3, p: Dictionary) -> void:
	_bolt(parent, sky, at, p, 0.22, true)
	var rm := K.fx_mat(K.GROUND_RING, p, 3.0, {"width": 0.3, "noise_amt": 0.2})
	var ring := K.ground(parent, at, rm, 3.5)
	K.anim(ring, rm, "progress", 0.1, 0.9, 0.3)
	K.anim(ring, rm, "fade", 1.0, 0.0, 0.25, 0.1)
	K.free_after(ring, 0.4)
	_scorch(parent, at, 1.6)
