extends RefCounted
## Style Lab characters: today's hero (as player.gd builds it), the improved hero (CC0 System G6 modular human,
## already on the UAL skeleton) and one villager. Idle pose only; animation code is untouched (Codex owns it).

const CC := "res://scripts/ui/character_creation.gd"
const PROPS: Array[String] = []   # idle pose only, hands free (the game attaches sword+shield; see docs)
## Improved hero: villager tunic outfit, head 3, brown hair. See docs/design/STYLE_LAB.md for the candidates.
const NEW_LOOK := {"sex": "male", "head": 2, "hair": 3, "hair_color": 1, "body": 0, "skin": 1}


## Style F: traveller gear (dark leather jerkin + gloves), like the hooded traveller of docs/art/reference/02.
const NEW_LOOK_F := {"sex": "male", "head": 2, "hair": 3, "hair_color": 0, "body": 4, "skin": 1}


## Style G hero base: Villager Tunic tinted green + short brown hair (G6 hair 3, colour 3).
const HERO_LOOK := {"sex": "male", "head": 2, "hair": 3, "hair_color": 3, "body": 0, "skin": 1}


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
## G6 Hunter's Leathers + HeroOutfit (skinned tunic skirt, hood collar, bracers, belt, satchel + strap, pouch).
static func hero_g() -> Node3D:
	var look := HERO_LOOK
	var m: Node3D = (load(CC) as GDScript).call("build_model", look, 1.78, PROPS)
	m.set_meta("role", "hero_new")
	(load("res://scripts/actors/hero_outfit.gd") as GDScript).call("tint_tunic", m)
	var ap := Assets.animation_player(m)
	if ap and ap.has_animation("Walk"):
		ap.play("Walk")
		ap.advance(0.3)
		ap.speed_scale = 0.0
	(load("res://scripts/actors/hero_outfit.gd") as GDScript).call("dress", m)
	return m
