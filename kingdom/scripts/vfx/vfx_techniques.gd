extends RefCounted
## Effects for the technique ids in data/skills/*.json (their "vfx" field), built
## from the spell and martial parts. technique_caster.gd calls VFX.<id> with
## (world, from, to, radius | power); the wrappers in vfx.gd forward here.
## Convention: `from` = caster's chest, `to` = ground point (aoe centre, target).

const K := preload("res://scripts/vfx/vfx_kit.gd")
const Spells := preload("res://scripts/vfx/vfx_spells.gd")
const Martial := preload("res://scripts/vfx/vfx_martial.gd")


static func _flat(v: Vector3, y: float) -> Vector3:
	return Vector3(v.x, y, v.z)


static func _yaw(from: Vector3, to: Vector3) -> float:
	return atan2(to.x - from.x, to.z - from.z)


static func _smoke(p: Dictionary) -> ShaderMaterial:
	return K.sprite_mat(K.SMOKE_PUFF, p, 1.0, {"mix": true, "spin": true, "cool": 0.0})


static func _dark() -> Dictionary:
	return {"tint": Color(0.16, 0.1, 0.22), "hot": Color(0.35, 0.25, 0.5), "edge": Color(0.05, 0.03, 0.08)}


static func _ring(parent: Node, at: Vector3, p: Dictionary, radius: float, secs := 0.45, energy := 2.5, width := 0.35) -> void:
	var rm := K.fx_mat(K.GROUND_RING, p, energy, {"width": width, "noise_amt": 0.2})
	var ring := K.ground(parent, at, rm, radius * 2.0)
	K.anim(ring, rm, "progress", 0.08, 0.92, secs, 0.0, Tween.EASE_OUT, Tween.TRANS_CUBIC)
	K.anim(ring, rm, "fade", 1.0, 0.0, secs * 0.6, secs * 0.4)
	K.free_after(ring, secs + 0.05)


# --- command -------------------------------------------------------------------

static func rally(parent: Node, to: Vector3, radius: float) -> void:
	var p := K.pal("holy")
	Spells.magic_circle(parent, to, "holy", 1.4, 1.2)
	_ring(parent, to, p, minf(radius, 8.0), 0.7, 2.0)
	K.emit(parent, to + Vector3(0, 0.2, 0), {"amount": 20, "life": 1.2, "shape": "disc", "radius": 1.0, "explosive": 0.5,
		"v": Vector2(2.0, 4.0), "spread": 10.0, "size": Vector2(0.05, 0.5), "stretch": true, "alpha": "inout",
		"mat": K.sprite_mat(K.DOT, p, 4.0, {"heat": 1.3})})
	K.glow(parent, to + Vector3(0, 1.2, 0), p, 2.5, 0.5, K.STAR, 3.0)


static func war_cry(parent: Node, from: Vector3, to: Vector3, radius: float) -> void:
	var p := K.pal("war")
	for i in 3:
		var tw := parent.create_tween()
		tw.tween_interval(i * 0.12)
		tw.tween_callback(_ring.bind(parent, to, p, minf(radius, 8.0) * (0.6 + i * 0.2), 0.5, 2.2))
	K.glow(parent, from, p, 3.0, 0.3, K.RADIAL, 3.0)
	Martial.impact_frame(parent, from, 0.8, 0.14, Color(1.0, 0.8, 0.6))


# --- earth ---------------------------------------------------------------------

static func stone_bullet(parent: Node, from: Vector3, to: Vector3, power := 1.0, speed := 24.0) -> Node3D:
	var root := Spells.missile(parent, from, to)
	var rock := BoxMesh.new()
	rock.size = Vector3(0.28, 0.24, 0.34) * power
	rock.material = Spells._rock_mat()
	var mi := MeshInstance3D.new()
	mi.mesh = rock
	root.add_child(mi)
	mi.create_tween().set_loops().tween_property(mi, "rotation", Vector3(TAU, TAU * 0.5, 0), 0.35).from(Vector3.ZERO)
	var dust := {"tint": Color(0.62, 0.52, 0.4), "hot": Color(0.8, 0.72, 0.6), "edge": Color(0.35, 0.28, 0.2)}
	var trails := [Spells.trail(root, parent, {"amount": 12, "life": 0.5, "v": Vector2(0.1, 0.4), "spread": 180.0, "size": 0.45,
		"grow": "grow", "alpha": "inout", "spin": true, "mat": _smoke(dust)})]
	Spells.arm(root, parent, from, to, speed, "earth", 0.7 * power, trails)
	return root


static func stone_skin(parent: Node, to: Vector3) -> void:
	var p := K.pal("earth")
	Spells.magic_circle(parent, to, "earth", 1.2, 1.2)
	var pts: Array[Vector3] = []
	var hs: Array[float] = []
	for i in 6:
		var a := TAU * i / 6.0
		pts.append(to + Vector3(cos(a), 0, sin(a)) * 0.9)
		hs.append(0.9)
	Spells.spikes(parent, pts, hs, 0.02, 0.8, 0.35)
	K.emit(parent, to + Vector3(0, 0.3, 0), {"amount": 14, "life": 0.9, "shape": "ring", "radius": 0.9, "inner": 0.6,
		"v": Vector2(1.5, 3.0), "spread": 10.0, "gravity": Vector3(0, -1, 0), "tangent": Vector2(3, 5), "size": 0.3,
		"spin": true, "grow": "flat", "alpha": "late", "mat": K.sprite_mat(K.DEBRIS, Spells._debris_pal(), 1.0, {"mix": true, "spin": true, "cool": 0.0})})
	K.glow(parent, to + Vector3(0, 1.0, 0), p, 2.2, 0.5, K.DOT, 2.0)


## A wall of stone rising across the aim line, `radius` wide.
static func stone_wall(parent: Node, from: Vector3, to: Vector3, radius: float) -> void:
	var fwd := _flat(to - from, 0.0).normalized()
	var side := fwd.cross(Vector3.UP).normalized()
	var c := to
	var half := clampf(radius * 0.5, 1.5, 4.0)
	var pts: Array[Vector3] = []
	var hs: Array[float] = []
	var n := int(half * 2.5)
	for i in n:
		pts.append(c + side * lerpf(-half, half, float(i) / maxf(n - 1, 1)) + fwd * randf_range(-0.2, 0.2))
		hs.append(randf_range(1.8, 2.6))
	Spells.spikes(parent, pts, hs, 0.015, 1.3, 1.6)
	Spells._crack(parent, c, K.pal("earth"), half * 2.4, 0.2)


# --- farming / wood -------------------------------------------------------------

static func leaves(parent: Node, to: Vector3, radius: float) -> void:
	var p := K.pal("wood")
	K.emit(parent, to + Vector3(0, 0.3, 0), {"amount": 30, "life": 2.0, "shape": "ring", "radius": minf(radius, 6.0) * 0.6,
		"inner": 0.3, "explosive": 0.4, "v": Vector2(1.0, 2.5), "spread": 30.0, "gravity": Vector3(0, 0.4, 0),
		"tangent": Vector2(2.0, 4.0), "size": 0.35, "spin": true, "angular": Vector2(-200, 200), "alpha": "inout", "grow": "flat",
		"mat": K.sprite_mat(K.CRESCENT, p, 2.2, {"spin": true, "cool": 0.3})})
	_ring(parent, to, p, minf(radius, 6.0), 0.8, 1.6)


static func rain(parent: Node, to: Vector3, radius: float, seconds := 3.0) -> void:
	var p := K.pal("water")
	var r := minf(radius, 10.0)
	var drops := K.emit(parent, to + Vector3(0, 9, 0), {"amount": 60, "life": 0.7, "one_shot": false, "shape": "box",
		"extents": Vector3(r, 0.5, r), "dir": Vector3.DOWN, "spread": 3.0, "v": Vector2(12.0, 15.0), "size": Vector2(0.03, 0.7),
		"stretch": true, "alpha": "inout", "mat": K.sprite_mat(K.DOT, {"tint": Color(0.7, 0.85, 1.0), "hot": Color(0.95, 1.0, 1.0), "edge": Color(0.3, 0.45, 0.7)}, 1.5)})
	var splash := K.emit(parent, to + Vector3(0, 0.1, 0), {"amount": 24, "life": 0.35, "one_shot": false, "shape": "box",
		"extents": Vector3(r, 0.05, r), "v": Vector2(0.5, 1.5), "spread": 40.0, "gravity": Vector3(0, -6, 0),
		"size": 0.12, "mat": K.sprite_mat(K.DOT, p, 2.0)})
	Spells._stop_later(parent, seconds, [drops, splash])


static func vines(parent: Node, to: Vector3, radius: float) -> void:
	var p := K.pal("wood")
	var r := minf(radius, 6.0)
	for k in 5:
		var a := TAU * k / 5.0 + randf() * 0.5
		var base := to + Vector3(cos(a), 0, sin(a)) * r * randf_range(0.3, 0.8)
		var pts := K.helix_points(0.35, 0.1, randf_range(1.6, 2.4), 1.5, 24)
		for i in pts.size():
			pts[i] += base
		var m := K.fx_mat(K.SMEAR, p, 2.0, {"tail": 1.0, "noise_amt": 0.2})
		var mi := K.world_mesh(parent, K.path_mesh(pts, 0.16, Vector3.ZERO, true, base), m)
		K.anim(mi, m, "progress", 0.0, 1.05, 0.45, k * 0.06)
		K.anim(mi, m, "dissolve", 0.0, 1.0, 0.5, 1.2)
		K.free_after(mi, 1.8)
	leaves(parent, to, r)


# --- fire ----------------------------------------------------------------------

## A rolling wall of flame from `from` toward `to` (also the ember-step dash trail).
static func flame_wave(parent: Node, from: Vector3, to: Vector3, radius: float) -> void:
	var p := K.pal("fire")
	var a := _flat(from, to.y - 0.1)
	var d := _flat(to - a, 0.0)
	var n := clampi(int(d.length() / 0.8), 3, 9)
	for i in n:
		var t := float(i + 1) / n
		var at := a.lerp(Vector3(to.x, to.y - 0.1, to.z), t)
		K.emit(parent, at, {"amount": 10, "life": 0.7, "shape": "disc", "radius": 0.4 + t * 0.6, "v": Vector2(2.0, 4.0),
			"spread": 15.0, "gravity": Vector3(0, 2, 0), "size": 0.9 + t * 0.4, "delay": i * 0.05, "explosive": 0.7,
			"mat": K.sprite_mat(K.FLAME, p, 3.0, {"distort": 0.3, "cool": 0.9, "heat": 1.3})})
	K.emit(parent, a.lerp(to, 0.5), {"amount": 20, "life": 0.8, "shape": "box", "extents": d.abs() * 0.5 + Vector3(0.6, 0.1, 0.6),
		"v": Vector2(2.0, 5.0), "spread": 20.0, "size": Vector2(0.05, 0.3), "stretch": true, "mat": K.sprite_mat(K.DOT, p, 5.0, {"heat": 1.4})})
	K.light(parent, a.lerp(to, 0.5) + Vector3.UP, p["tint"], 3.0, 0.6, 7.0)


static func fire_nova(parent: Node, to: Vector3, radius: float) -> void:
	var p := K.pal("fire")
	var r := minf(radius, 7.0)
	Spells.magic_circle(parent, to, "fire", 1.8, 0.9)
	_ring(parent, to, p, r, 0.5, 3.0, 0.5)
	K.emit(parent, to + Vector3(0, 0.3, 0), {"amount": 36, "life": 0.7, "shape": "ring", "radius": 0.6, "inner": 0.4,
		"v": Vector2(1.0, 2.0), "radial": Vector2(r * 2.0, r * 2.6), "spread": 20.0, "gravity": Vector3(0, 1, 0),
		"damping": Vector2(1, 2), "size": 1.1, "spin": true, "grow": "pop",
		"mat": K.sprite_mat(K.FIRE, p, 3.0, {"spin": true, "cool": 0.9, "heat": 1.3})})
	Spells.impact(parent, to + Vector3(0, 0.9, 0), "fire", 1.3)


# --- sword / iaido -------------------------------------------------------------

static func sword_arc(parent: Node, from: Vector3, to: Vector3, radius: float, color := Color(0.8, 0.9, 1.0)) -> void:
	Martial.slash_arc(parent, from, _yaw(from, to), randf_range(-0.9, 0.9), K.pal_from(color), clampf(radius * 0.6, 1.6, 3.5))


## Quick-draw flash: a blinding straight cut. Long (dash) -> a streak along the
## path; short (melee) -> a fast slash; wide (aoe) -> a flurry of cuts.
static func iaido_flash(parent: Node, from: Vector3, to: Vector3, radius: float) -> void:
	var p := K.pal("metal")
	var flat := _flat(to - from, 0.0).length()
	if flat > 3.5:
		var m := K.fx_mat(K.BEAM, p, 3.5, {"speed": 4.0})
		var mi := K.world_mesh(parent, K.bolt_mesh(from, to, 0.0, 0.06, 2), m)
		K.anim(mi, m, "fade", 1.0, 0.0, 0.3, 0.05, Tween.EASE_IN)
		K.free_after(mi, 0.4)
		Martial.slash_arc(parent, to, _yaw(from, to), 1.0, p, 2.0, 0.08)
		Martial.slash_arc(parent, to, _yaw(from, to), -1.0, p, 2.0, 0.08)
		Martial.impact_frame(parent, to, 0.9, 0.12, Color(0.9, 0.95, 1.0))
	elif radius >= 4.0 and flat < 0.5:
		for i in 6:
			var tw := parent.create_tween()
			tw.tween_interval(i * 0.06)
			var c := to + Vector3(randf_range(-1, 1) * radius * 0.5, 1.0 + randf() * 0.6, randf_range(-1, 1) * radius * 0.5)
			tw.tween_callback(Martial.slash_arc.bind(parent, c, randf() * TAU, randf_range(-1.3, 1.3), p, 1.8, 0.07))
		Martial.impact_frame(parent, to + Vector3.UP, 0.7, 0.15, Color(0.9, 0.95, 1.0))
	else:
		Martial.slash_arc(parent, from, _yaw(from, to), randf_range(-0.2, 0.2), p, 2.2, 0.07)
		Martial.impact_frame(parent, from.lerp(to, 0.6), 0.7, 0.1, Color(0.9, 0.95, 1.0))


static func sword_qi(parent: Node, from: Vector3, to: Vector3, power := 1.0, speed := 24.0) -> Node3D:
	return Spells.crescent(parent, from, to, "qi", power, speed)


# --- lightning -----------------------------------------------------------------

static func lightning_trail(parent: Node, from: Vector3, to: Vector3) -> void:
	var p := K.pal("lightning")
	Spells._bolt(parent, from, to, p, 0.12, false)
	K.emit(parent, from.lerp(to, 0.5), {"amount": 24, "life": 0.4, "shape": "box", "extents": (to - from).abs() * 0.5 + Vector3(0.3, 0.3, 0.3),
		"v": Vector2(1.0, 4.0), "spread": 180.0, "size": Vector2(0.03, 0.25), "stretch": true, "mat": K.sprite_mat(K.DOT, p, 5.0, {"heat": 1.5})})
	K.glow(parent, to, p, 2.0, 0.25, K.STAR, 4.0)


static func thunder_strike(parent: Node, to: Vector3, radius: float) -> void:
	var p := K.pal("lightning")
	Spells.magic_circle(parent, to, "lightning", minf(radius, 4.0), 0.9)
	var tw := parent.create_tween()
	tw.tween_interval(0.25)
	tw.tween_callback(Spells._strike.bind(parent, to + Vector3(0, 12, 0), to, p))
	tw.tween_interval(0.07)
	tw.tween_callback(Spells._bolt.bind(parent, to + Vector3(randf_range(-2, 2), 12, randf_range(-2, 2)), to, p, 0.12, false))
	tw.tween_callback(Martial.impact_frame.bind(parent, to, 1.0, 0.12, Color(0.85, 0.9, 1.0)))


# --- qi ------------------------------------------------------------------------

static func qi_aura(parent: Node, to: Vector3) -> void:
	var p := K.pal("qi")
	Spells.magic_circle(parent, to, "qi", 1.3, 1.6)
	var f := K.emit(parent, to + Vector3(0, 0.1, 0), {"amount": 22, "life": 0.9, "one_shot": false, "shape": "ring", "radius": 0.5,
		"inner": 0.2, "v": Vector2(1.6, 2.6), "spread": 6.0, "size": Vector2(0.55, 0.9), "alpha": "inout",
		"mat": K.sprite_mat(K.FLAME, p, 2.6, {"distort": 0.3, "cool": 0.7, "heat": 1.2})})
	Spells._stop_later(parent, 1.2, [f])


static func qi_bolt(parent: Node, from: Vector3, to: Vector3, power := 1.0, speed := 20.0) -> Node3D:
	var p := K.pal("qi")
	var root := Spells.missile(parent, from, to)
	K.quad(root, from, K.fx_mat(K.ORB, p, 3.0, {"twist": 1.5, "noise_amt": 0.4, "speed": 2.0}), 0.6 * power)
	var trails := [Spells.trail(root, parent, {"amount": 16, "life": 0.4, "v": Vector2(0.1, 0.5), "spread": 180.0,
		"size": 0.35, "mat": K.sprite_mat(K.DOT, p, 3.5, {"heat": 1.2})})]
	Spells.arm(root, parent, from, to, speed, "qi", 0.7 * power, trails)
	return root


static func qi_shield(parent: Node, to: Vector3, radius: float) -> void:
	var p := K.pal("qi")
	var r := clampf(radius, 1.5, 4.0)
	var dome := SphereMesh.new()
	dome.radius = r
	dome.height = r * 2.0
	dome.is_hemisphere = true
	dome.radial_segments = 24
	dome.rings = 8
	var m := K.shader_mat(K.GHOST)
	m.set_shader_parameter("tint", p["tint"])
	m.set_shader_parameter("hot", p["hot"])
	m.set_shader_parameter("rim_power", 3.0)
	var mi := K.mesh_node(parent, dome, m, to)
	mi.scale = Vector3.ONE * 0.3
	mi.create_tween().tween_property(mi, "scale", Vector3.ONE, 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	K.anim(mi, m, "fade", 1.0, 0.0, 0.6, 1.2, Tween.EASE_IN)
	K.free_after(mi, 1.85)
	Spells.magic_circle(parent, to, "qi", r, 1.8)


static func qi_nova(parent: Node, to: Vector3, radius: float) -> void:
	var p := K.pal("qi")
	var r := minf(radius, 8.0)
	_ring(parent, to, p, r, 0.55, 3.0, 0.4)
	_ring(parent, to, p, r * 0.6, 0.4, 2.0, 0.6)
	K.glow(parent, to + Vector3(0, 1.0, 0), p, 5.0, 0.45, K.RADIAL, 3.0)
	Spells.impact(parent, to + Vector3(0, 1.0, 0), "qi", 1.5)
	Martial.impact_frame(parent, to + Vector3.UP, 1.0, 0.14)


# --- shadow --------------------------------------------------------------------

static func shuriken(parent: Node, from: Vector3, to: Vector3, power := 1.0, speed := 28.0) -> Node3D:
	var p := K.pal("shadow")
	var root := Spells.missile(parent, from, to)
	var m := K.sprite_mat(K.STAR, p, 4.0, {"particle": false, "heat": 1.3})
	var star := K.quad(root, from, m, 0.9 * power)
	star.rotation.x = -PI * 0.5
	star.create_tween().set_loops().tween_property(star, "rotation:y", TAU, 0.2).from(0.0)
	var trails := [Spells.trail(root, parent, {"amount": 10, "life": 0.3, "v": Vector2.ZERO, "size": 0.3,
		"mat": K.sprite_mat(K.DOT, p, 2.5)})]
	Spells.arm(root, parent, from, to, speed, "", power, trails)
	return root


static func smoke_bomb(parent: Node, to: Vector3, radius: float) -> void:
	var r := clampf(radius, 2.0, 5.0)
	K.emit(parent, to + Vector3(0, 0.5, 0), {"amount": 18, "life": 2.2, "shape": "sphere", "radius": 0.5, "v": Vector2(1.0, r),
		"spread": 180.0, "damping": Vector2(2, 3), "gravity": Vector3(0, 0.3, 0), "size": r * 0.9, "grow": "grow", "alpha": "inout",
		"spin": true, "mat": _smoke(_dark())})
	K.emit(parent, to + Vector3(0, 0.5, 0), {"amount": 14, "life": 0.4, "v": Vector2(4, 8), "spread": 180.0,
		"size": Vector2(0.04, 0.3), "stretch": true, "mat": K.sprite_mat(K.DOT, K.pal("shadow"), 4.0)})


static func shadow_step(parent: Node, from: Vector3, to: Vector3) -> void:
	var p := K.pal("shadow")
	K.emit(parent, from, {"amount": 10, "life": 0.7, "shape": "sphere", "radius": 0.4, "v": Vector2(0.5, 1.5), "spread": 180.0,
		"size": 1.0, "grow": "grow", "alpha": "inout", "spin": true, "mat": _smoke(_dark())})
	K.glow(parent, from, p, 1.8, 0.25, K.STAR, 3.0)
	if from.distance_to(to) > 0.3:
		Martial.slash_arc(parent, from, _yaw(from, to), 0.9, p, 1.6, 0.08)


static func shadow_clone(parent: Node, to: Vector3, radius: float) -> void:
	var p := K.pal("shadow")
	for i in 3:
		var a := TAU * i / 3.0 + 0.5
		var at := to + Vector3(cos(a), 0.9, sin(a)) * minf(radius, 3.0) * 0.5
		shadow_step(parent, at, at)
		K.emit(parent, at, {"amount": 8, "life": 0.8, "shape": "box", "extents": Vector3(0.25, 0.8, 0.25), "v": Vector2(0.3, 1.0),
			"spread": 30.0, "size": 0.2, "spin": true, "mat": K.sprite_mat(K.SPARKLE, p, 3.0, {"spin": true})})


# --- water ---------------------------------------------------------------------

static func water_heal(parent: Node, to: Vector3, radius: float) -> void:
	var p := K.pal("water")
	Spells.magic_circle(parent, to, "water", minf(radius, 5.0) * 0.5, 1.4)
	K.emit(parent, to + Vector3(0, 0.2, 0), {"amount": 22, "life": 1.3, "shape": "disc", "radius": 0.8, "explosive": 0.3,
		"v": Vector2(0.8, 2.0), "spread": 10.0, "size": 0.3, "spin": true, "alpha": "inout", "grow": "pop",
		"mat": K.sprite_mat(K.SPARKLE, p, 3.5, {"spin": true})})
	Martial.heal(parent, to, 0.8)


static func ice_lance(parent: Node, from: Vector3, to: Vector3, power := 1.0, speed := 26.0) -> Node3D:
	var p := K.pal("frost")
	Spells.cast_sigil(parent, from, to - from, "water", power)
	var root := Spells.missile(parent, from, to)
	for k in 2:
		var m := K.sprite_mat(K.SHARD, p, 3.0, {"particle": false, "heat": 1.2})
		var q := K.quad(root, from, m, 1.0)
		q.scale = Vector3(0.5, 1.6, 1.0) * power
		q.rotation = Vector3(-PI * 0.5, 0, k * PI * 0.5)
	var trails := [Spells.trail(root, parent, {"amount": 14, "life": 0.5, "v": Vector2(0.1, 0.3), "spread": 180.0,
		"size": 0.2, "spin": true, "mat": K.sprite_mat(K.SPARKLE, p, 3.5, {"spin": true})}),
		Spells.trail(root, parent, {"amount": 8, "life": 0.7, "v": Vector2(0.0, 0.2), "size": 0.6, "grow": "grow", "alpha": "inout",
		"spin": true, "mat": K.sprite_mat(K.SMOKE_PUFF, p, 0.8, {"spin": true, "cool": 0.3})})]
	Spells.arm(root, parent, from, to, speed, "water", 0.8 * power, trails)
	return root


static func water_ring(parent: Node, to: Vector3, radius: float) -> void:
	var p := K.pal("water")
	_ring(parent, to, p, minf(radius, 12.0), 1.4, 1.4, 0.25)
	_ring(parent, to, p, minf(radius, 12.0) * 0.6, 1.0, 1.2, 0.25)


## A cresting wave that rolls from the caster toward `to`.
static func tidal_wave(parent: Node, from: Vector3, to: Vector3, radius: float) -> void:
	var p := K.pal("water")
	var a := _flat(from, to.y)
	var end := a + _flat(to - a, 0.0).normalized() * maxf(radius, 4.0)
	var root := Node3D.new()
	K.add(parent, root, a)
	root.rotation.y = _yaw(a, end)
	var m := K.fx_mat(K.SMEAR, p, 2.6, {"tail": 1.2, "progress": 1.0, "noise_amt": 0.6, "speed": 3.0})
	var wave := K.mesh_node(root, K.arc_mesh(2.4, 120.0, 0.6), m, a)
	wave.position = Vector3(0, 1.0, -1.6)
	wave.rotation = Vector3(-PI * 0.5 + 0.35, PI, 0)
	var secs := a.distance_to(end) / 10.0
	var tw := root.create_tween()
	tw.tween_property(root, "global_position", end, secs)
	K.anim(wave, m, "dissolve", 0.0, 1.0, 0.3, secs - 0.15)
	K.free_after(root, secs + 0.2)
	var spray := Spells.trail(root, parent, {"amount": 30, "life": 0.6, "shape": "box", "extents": Vector3(1.5, 0.3, 0.3),
		"v": Vector2(2.0, 5.0), "spread": 30.0, "gravity": Vector3(0, -12, 0), "size": Vector2(0.07, 0.3), "stretch": true,
		"mat": K.sprite_mat(K.DOT, p, 3.0, {"heat": 1.3})})
	Spells._stop_later(parent, secs, [spray])
	var tw2 := parent.create_tween()
	tw2.tween_interval(secs)
	tw2.tween_callback(Spells.tidal_ring.bind(parent, end, 2.5))


static func whirlpool(parent: Node, to: Vector3, radius: float) -> void:
	var p := K.pal("water")
	var r := minf(radius, 5.0)
	Spells.magic_circle(parent, to, "water", r, 2.0)
	var sm := K.sprite_mat(K.SWIRL, p, 2.2, {"particle": false})
	var swirl := K.ground(parent, to + Vector3(0, 0.04, 0), sm, r * 2.2)
	swirl.create_tween().tween_property(swirl, "rotation:y", TAU * 2.0, 2.0)
	K.anim(swirl, sm, "fade", 1.0, 0.0, 0.5, 1.5)
	K.free_after(swirl, 2.05)
	K.emit(parent, to + Vector3(0, 0.2, 0), {"amount": 30, "life": 1.2, "shape": "ring", "radius": r, "inner": r * 0.5,
		"v": Vector2(0.5, 1.5), "spread": 10.0, "gravity": Vector3(0, 0.8, 0), "tangent": Vector2(6, 9), "radial": Vector2(-3, -2),
		"size": Vector2(0.06, 0.4), "stretch": true, "explosive": 0.2, "mat": K.sprite_mat(K.DOT, p, 3.0, {"heat": 1.3})})
	Spells.tidal_ring(parent, to, r * 0.7)


# --- wind ----------------------------------------------------------------------

static func wind_trail(parent: Node, from: Vector3, to: Vector3) -> void:
	var p := K.pal("wind")
	var d := to - from
	K.emit(parent, from.lerp(to, 0.5), {"amount": 20, "life": 0.45, "shape": "box", "extents": d.abs() * 0.5 + Vector3(0.4, 0.5, 0.4),
		"dir": d.normalized(), "spread": 5.0, "v": Vector2(4.0, 9.0), "damping": Vector2(6, 9), "size": Vector2(0.05, 1.0),
		"stretch": true, "mat": K.sprite_mat(K.STREAK, p, 2.6)})
	K.emit(parent, from.lerp(to, 0.5), {"amount": 8, "life": 0.6, "shape": "box", "extents": d.abs() * 0.5 + Vector3(0.3, 0.3, 0.3),
		"v": Vector2(0.5, 1.5), "spread": 180.0, "size": 0.9, "spin": true, "angular": Vector2(300, 600), "grow": "grow",
		"mat": K.sprite_mat(K.TWIRL, p, 2.0, {"spin": true, "cool": 0.5})})
