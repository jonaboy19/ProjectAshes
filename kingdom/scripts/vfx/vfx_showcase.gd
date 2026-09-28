extends RefCounted
## VFX.showcase(): fires every effect of the library once, laid out in a grid of
## rows facing -Z from `origin` (columns 6 m apart, rows 8 m apart). For visual
## review and screenshots; everything frees itself after `seconds`.

const K := preload("res://scripts/vfx/vfx_kit.gd")
const Spells := preload("res://scripts/vfx/vfx_spells.gd")
const Martial := preload("res://scripts/vfx/vfx_martial.gd")
const Status := preload("res://scripts/vfx/vfx_status.gd")
const Tech := preload("res://scripts/vfx/vfx_techniques.gd")

const ELEMENTS := ["fire", "water", "wind", "earth", "lightning", "qi"]
const COL := 6.0
const ROW := 8.0


static func _cell(origin: Vector3, col: int, row: int) -> Vector3:
	return origin + Vector3((col - 2.5) * COL, 0, -row * ROW)


## A grey stand-in character (capsule, 1.75 m) for status / aura / afterimage.
static func dummy(parent: Node, pos: Vector3, seconds: float) -> Node3D:
	var root := Node3D.new()
	K.add(parent, root, pos)
	var cap := CapsuleMesh.new()
	cap.radius = 0.3
	cap.height = 1.75
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.55, 0.5, 0.48)
	m.roughness = 0.8
	cap.material = m
	var mi := MeshInstance3D.new()
	mi.mesh = cap
	root.add_child(mi)
	mi.position = Vector3(0, 0.875, 0)
	K.free_after(root, seconds)
	return root


## Returns how long the showcase runs.
static func showcase(parent: Node, origin: Vector3, seconds := 8.0) -> float:
	# Row 0: rune circles per element.
	for i in ELEMENTS.size():
		Spells.magic_circle(parent, _cell(origin, i, 0), ELEMENTS[i], 2.0, seconds)
	# Row 1: projectiles flying toward the camera side, slowed so they're caught mid-air.
	var shots := ["fireball", "water_whip", "wind_blade", "earth_spike", "lightning_chain", "qi_palm"]
	for i in shots.size():
		var c := _cell(origin, i, 1)
		var from := c + Vector3(0, 1.2, -3.0)
		var to := c + Vector3(0, 1.2, 3.0)
		match shots[i]:
			"fireball":
				Spells.fireball(parent, from, to, 1.0, 5.0)
			"water_whip":
				Spells.water_whip(parent, from, to, 1.0)
			"wind_blade":
				Spells.wind_blade(parent, from, to, 1.0, 5.0)
			"earth_spike":
				Spells.earth_spike(parent, from, c + Vector3(0, 0, 3.0), 1.0)
			"lightning_chain":
				Spells.lightning_chain(parent, from, [c + Vector3(-1.5, 1.0, 0.5), c + Vector3(1.5, 1.0, 2.5)], 1.0)
			"qi_palm":
				Spells.qi_palm(parent, from, to, 1.0, 5.0)
	# Row 2: area effects and the Rift.
	Spells.fire_pillar(parent, _cell(origin, 0, 2), 1.0, seconds)
	Spells.whirlwind(parent, _cell(origin, 1, 2), 1.3, seconds)
	Spells.tidal_ring(parent, _cell(origin, 2, 2), 2.8)
	Spells.earthquake(parent, _cell(origin, 3, 2), 2.8, seconds)
	Spells.thunderstorm(parent, _cell(origin, 4, 2), 2.5, 6, minf(seconds, 3.0))
	Status.rift(parent, _cell(origin, 5, 2), 2.4, seconds)
	# Row 3: martial arts and the naming rite.
	var c0 := _cell(origin, 0, 3)
	Martial.slash_arc(parent, c0 + Vector3(0, 1.2, 0), PI, 0.8, K.pal("metal"), 2.0, 0.12)
	Martial.slash_arc(parent, c0 + Vector3(0, 1.0, 0), PI, -0.5, K.pal("fire"), 1.6, 0.18)
	var d1 := dummy(parent, _cell(origin, 1, 3), seconds)
	Martial.qi_flames(d1, K.pal("qi"), 1.8)
	var d2 := dummy(parent, _cell(origin, 2, 3) + Vector3(-1.5, 0, 0), seconds)
	d2.create_tween().tween_property(d2, "global_position", _cell(origin, 2, 3) + Vector3(1.5, 0, 0), 0.5)
	Martial.afterimage(parent, d2, Color(0.45, 0.8, 1.0), 5, 0.08, 1.2)
	Martial.heal(parent, _cell(origin, 3, 3), 1.0)
	var d4 := dummy(parent, _cell(origin, 4, 3), seconds)
	Status.naming(parent, d4.global_position, 1.6)
	Martial.impact_frame(parent, _cell(origin, 5, 3) + Vector3(0, 1.0, 0), 1.0, 0.25)
	Spells.impact(parent, _cell(origin, 5, 3) + Vector3(0, 1.0, 0), "qi", 1.2)
	# Row 4: status effects.
	for i in Status.KINDS.size():
		var d := dummy(parent, _cell(origin, i, 4), seconds)
		Status.status(d, Status.KINDS[i], seconds - 0.5)
	var d5 := dummy(parent, _cell(origin, 5, 4), seconds)
	Martial.qi_flames(d5, K.pal("lightning"), 1.8)
	return seconds
