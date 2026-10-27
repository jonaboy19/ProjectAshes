extends RefCounted
## Surface-matched melee contact VFX (combat-motion worker; AAA gap audit: "combat VFX read generic/toon").
## GPUParticles3D through vfx_kit, alpha-blended (not additive) for anything that is not hot metal, believable scale:
##   flesh / cloth / leather : a few dark-red droplets falling fast + a small ground stain decal (pooled, fades)
##   metal                   : short hot steel streaks (parry_contact.steel_sparks)
##   wood                    : brown splinter chips + a puff of dust
## Effekseer was evaluated and not used: it needs authored .efk effects (none medieval/CC0 in the project), adds a GDExtension
## and per-effect cost; the pooled GPUParticles3D path is cheaper on iGPU and already in the combat pipeline.

const K := preload("res://scripts/vfx/vfx_kit.gd")
const ParryContact := preload("res://scripts/combat/parry_contact.gd")
const MAX_STAINS := 12
const STAIN_LIFE := 25.0

static var _stains: Array = []


static func play(parent: Node, pos: Vector3, dir: Vector3, surface: String, tier: int) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	match surface:
		"metal":
			ParryContact.steel_sparks(parent, pos, 6 + tier * 4)
		"wood":
			_chips(parent, pos, dir, Color(0.42, 0.29, 0.16), 6 + tier * 3)
		_:
			_blood(parent, pos, dir, tier, surface)


static func _blood(parent: Node, pos: Vector3, dir: Vector3, tier: int, surface: String) -> void:
	var c := Color(0.32, 0.03, 0.02) if surface == "flesh" else Color(0.26, 0.04, 0.03)
	var p := {"tint": c, "hot": c.lightened(0.15), "edge": c.darkened(0.5)}
	var d := dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD
	K.emit(parent, pos, {"amount": 5 + tier * 4, "life": 0.45, "v": Vector2(1.5, 3.5), "spread": 35.0, "dir": d,
		"gravity": Vector3(0, -12, 0), "damping": Vector2(0, 1), "size": Vector2(0.015, 0.035), "stretch": true,
		"mat": K.sprite_mat(K.DOT, p, 0.6, {"mix": true, "cool": 0.0})})
	if tier >= 1:
		_stain(parent, pos + d * 0.4, c)


static func _chips(parent: Node, pos: Vector3, dir: Vector3, c: Color, n: int) -> void:
	var p := {"tint": c, "hot": c.lightened(0.2), "edge": c.darkened(0.4)}
	var d := dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD
	K.emit(parent, pos, {"amount": n, "life": 0.5, "v": Vector2(1.5, 4.0), "spread": 60.0, "dir": d,
		"gravity": Vector3(0, -10, 0), "damping": Vector2(0, 1), "size": Vector2(0.02, 0.04), "spin": true,
		"mat": K.sprite_mat(K.DOT, p, 0.6, {"mix": true, "cool": 0.0})})


## A small dark stain on the ground under the blow (Decal, pooled, fades out).
static func _stain(parent: Node, at: Vector3, c: Color) -> void:
	var space := (parent as Node3D).get_world_3d().direct_space_state if parent is Node3D else null
	var ground := at
	if space != null:
		var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.5, at + Vector3.DOWN * 3.0, 1)
		var r := space.intersect_ray(q)
		if r.is_empty():
			return
		ground = r["position"]
	var dcl: Decal
	if _stains.size() >= MAX_STAINS:
		dcl = _stains.pop_front()
		if not is_instance_valid(dcl):
			dcl = null
	if dcl == null:
		dcl = Decal.new()
		var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
		for y in 32:
			for x in 32:
				var r2 := (Vector2(x, y) - Vector2(15.5, 15.5)).length() / 16.0
				img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - r2 * r2, 0.0, 1.0) * 0.85))
		dcl.texture_albedo = ImageTexture.create_from_image(img)
		parent.add_child(dcl)
	_stains.append(dcl)
	dcl.modulate = c
	dcl.size = Vector3(0.35, 0.4, 0.35) * randf_range(0.8, 1.3)
	dcl.global_position = ground
	dcl.rotation.y = randf() * TAU
	dcl.albedo_mix = 0.85
	dcl.visible = true
	var tw := dcl.create_tween()
	tw.tween_interval(STAIN_LIFE)
	tw.tween_property(dcl, "albedo_mix", 0.0, 3.0)
