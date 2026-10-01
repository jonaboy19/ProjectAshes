extends RefCounted
## Style Lab characters: today's hero (as player.gd builds it), the improved hero (CC0 System G6 modular human,
## already on the UAL skeleton) and one villager. Idle pose only; animation code is untouched (Codex owns it).

const CC := "res://scripts/ui/character_creation.gd"
const PROPS: Array[String] = []   # idle pose only, hands free (the game attaches sword+shield; see docs)
## Improved hero: villager tunic outfit, head 3, brown hair. See docs/design/STYLE_LAB.md for the candidates.
const NEW_LOOK := {"sex": "male", "head": 2, "hair": 3, "hair_color": 1, "body": 0, "skin": 1}


## Style F: traveller gear (dark leather jerkin + gloves), like the hooded traveller of docs/art/reference/02.
const NEW_LOOK_F := {"sex": "male", "head": 2, "hair": 3, "hair_color": 0, "body": 4, "skin": 1}


static func hero_today() -> Node3D:
	var m: Node3D = Assets.character("Player", 1.8, PROPS)
	m.set_meta("role", "hero_old")
	return _idle(m)


static func hero_new(style_id := "A") -> Node3D:
	if style_id == "G":
		return hero_g()
	var look := NEW_LOOK_F if style_id == "F" else NEW_LOOK
	var m: Node3D = (load(CC) as GDScript).call("build_model", look, 1.78, PROPS)
	m.set_meta("role", "hero_new")
	return _idle(m)


static func villager() -> Node3D:
	var m: Node3D = Assets.mh_character("villager_woman_a", 1.62)
	m.set_meta("role", "villager")
	return _idle(m)


static func _idle(m: Node3D) -> Node3D:
	var ap := Assets.animation_player(m)
	if ap:
		for clip in ["Idle", "Idle_Loop", "Idle_No_Loop"]:
			if ap.has_animation(clip):
				ap.play(clip)
				ap.advance(0.35)
				break
	return m


## Style G / target 03: "brown-haired young man, green tunic, hooded brown leather vest, satchel, bracers, boots".
## G6 Hunter's Leathers (vest + boots + bracer gloves) + a green tunic skirt + satchel and strap (simple meshes).
## Static props sit in model space (the pose is frozen), so they do not follow animation.
static func hero_g() -> Node3D:
	var look := {"sex": "male", "head": 2, "hair": 5, "hair_color": 3, "body": 2, "skin": 1}
	var m: Node3D = (load(CC) as GDScript).call("build_model", look, 1.78, PROPS)
	m.set_meta("role", "hero_new")
	var ap := Assets.animation_player(m)
	if ap and ap.has_animation("Walk"):
		ap.play("Walk")
		ap.advance(0.3)
		ap.speed_scale = 0.0
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		if (mi as MeshInstance3D).visible and (mi as MeshInstance3D).mesh:
			for si in (mi as MeshInstance3D).mesh.get_surface_count():
				var am: Material = (mi as MeshInstance3D).get_active_material(si)
				if am is BaseMaterial3D:
					print("HEROMAT ", mi.name, " tex=", (am as BaseMaterial3D).albedo_texture, " col=", (am as BaseMaterial3D).albedo_color, " vcol=", (am as BaseMaterial3D).vertex_color_use_as_albedo)
	var green := StandardMaterial3D.new()
	green.albedo_color = Color(0.30, 0.46, 0.22)
	green.roughness = 0.95
	var leather := StandardMaterial3D.new()
	leather.albedo_color = Color(0.36, 0.22, 0.12)
	leather.roughness = 0.7
	var hem := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.17
	cm.bottom_radius = 0.265
	cm.height = 0.34
	cm.radial_segments = 14
	cm.rings = 1
	cm.cap_top = false
	cm.cap_bottom = false
	hem.mesh = cm
	hem.position = Vector3(0, 0.86 / m.scale.y * 1.0, 0.0)
	hem.material_override = green
	hem.set_meta("role", "hero_new")
	hem.set_meta("keep_material", true)
	m.add_child(hem)
	var bag := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.12, 0.22, 0.28)
	bag.mesh = bm
	bag.position = Vector3(0.27, 0.86, -0.02)
	bag.material_override = leather
	bag.set_meta("keep_material", true)
	m.add_child(bag)
	var strap := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.05, 0.68, 0.27)
	strap.mesh = sm
	strap.position = Vector3(0.04, 1.2, 0.0)
	strap.rotation.z = 0.62
	strap.material_override = leather
	strap.set_meta("keep_material", true)
	m.add_child(strap)
	return m
