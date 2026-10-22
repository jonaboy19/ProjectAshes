extends RefCounted
## AR-2/3/4: what an observer FEELS from an aura and what they do about it (docs/design/AURA_RELEASE.md sections 2, 6, 7).
## Reuses SocialPerception.magic_pressure (never a second sensitivity model) and the persona/psyche values the caller passes
## read-only. Deterministic (hash, no randf). Scratch dictionaries are reused, so a felt() call allocates nothing.
##
## NO MIND CONTROL (design section 3): reaction_for() only ever returns the body-fear kinds in ALLOWED. Nothing here changes an
## allegiance, an order or a secret; aura only picks a reaction request.

const SP := preload("res://scripts/realm/social_perception.gd")
const RR := preload("res://scripts/population/reaction_request.gd")
const Data := preload("res://scripts/sim/aura_data.gd")
const Faith := preload("res://scripts/realm/faith.gd")

## The only reactions aura may request.
const ALLOWED := [RR.Kind.GLANCE, RR.Kind.LOOK_AWAY, RR.Kind.STEP_BACK, RR.Kind.FLINCH, RR.Kind.BOW, RR.Kind.WARN, RR.Kind.CALL_GUARD,
	RR.Kind.FLEE, RR.Kind.KNEEL, RR.Kind.FAINT, RR.Kind.HIDE, RR.Kind.FLEE_WITH_CHILD]
const ROLES := ["clearer", "parent", "elder", "beggar", "merchant", "looter", "devotee", "fanatic", "rival_mage", "child", "guard", "drunk", "healer", "gawker"]

var sp: RefCounted = SP.new()
var felts := 0
var _o := {"id": "", "magic_sense": 0.1, "intelligence": 0.5, "stress": 0.0}
var _s := {"id": "", "aura_emit": 0.0, "aura_suppress": 0.0}


static func culture_of(o: Dictionary) -> String:
	var c := String(o.get("culture", ""))
	if c != "":
		return c
	var k := String(o.get("kingdom", SP.HOME))
	if k in Faith.CHURCH_KINGDOMS:
		return "church"
	if k == SP.HOME or k == "":
		return "valencios"
	return "other"


## "holy", "demonic", "neutral" (from the visual signature) for faith cultures, "secular" otherwise.
static func reading(o: Dictionary, signature: String) -> String:
	var cul: Dictionary = (Data.table("aura_culture").get("cultures", {}) as Dictionary).get(culture_of(o), {})
	if String(cul.get("reads", "")) != "faith":
		return "secular"
	return String((Data.table("aura_culture").get("signatures", {}) as Dictionary).get(signature, "neutral"))


## sens(o) = base * K_species * K_state * K_faith * K_training * (1 + age_term), design 2.2.
static func sens(o: Dictionary, read := "secular") -> float:
	var c := Data.curve()
	var t := Data.table("aura_species")
	var base := float(c.get("sens_floor", 0.7)) + float(c.get("sens_span", 0.3)) * clampf(float(o.get("magic_sense", 0.1)), 0.0, 1.0)
	var ks := float((t.get("species", {}) as Dictionary).get(String(o.get("species", "human")), 1.0))
	var kst := float((t.get("state", {}) as Dictionary).get(String(o.get("state", "normal")), 1.0))
	var kt := float((t.get("training", {}) as Dictionary).get(String(o.get("training", "civilian")), 1.0))
	var kf := 1.0
	if clampf(float((o.get("persona", {}) as Dictionary).get("pious", 0.3)), 0.0, 1.0) > 0.5:
		kf = float((t.get("faith_read", {}) as Dictionary).get(read, 1.0))
	var age := float((t.get("age", {}) as Dictionary).get(String(o.get("age_group", "adult")), 0.0))
	return base * ks * kst * kf * kt * (1.0 + age)


static func courage_of(o: Dictionary) -> float:
	if String(o.get("age_group", "adult")) in ["child", "infant"]:
		return float(Data.table("aura_roles").get("child_courage", 0.9))
	return clampf(float((o.get("persona", {}) as Dictionary).get("courage", 0.5)), 0.0, 1.0)


## Felt value 0..1 at distance d (metres). `wall` is the wall factor (1 open air). Uses SocialPerception.magic_pressure.
func felt(o: Dictionary, subject: Dictionary, d: float, wall := 1.0, signature := "") -> float:
	var emit := float(subject.get("aura_emit", 0.0))
	if emit <= 0.0:
		return 0.0
	var reach := float(subject.get("reach_m", 6.0 + 70.0 * pow(emit, 1.3)))
	if d >= reach:
		return 0.0
	felts += 1
	var c := Data.curve()
	var fall := pow(1.0 - d / reach, float(c.get("falloff_exp", 1.5)))
	var k := sens(o, reading(o, String(subject.get("signature", signature))))
	_o["id"] = o.get("id", o.get("aura_id", ""))
	_o["magic_sense"] = clampf(k, 0.0, 1.0)
	_o["intelligence"] = o.get("intelligence", 0.5)
	_o["stress"] = o.get("stress", 0.0)
	_s["id"] = subject.get("id", "")
	_s["aura_emit"] = emit * fall * wall
	_s["aura_suppress"] = float(subject.get("aura_suppress", 0.0)) * fall * wall
	var mp: float = sp.magic_pressure(_o, _s, {"day": int(subject.get("day", 0))})
	# magic_sense is clamped to 1; sensitivities above 1 (animals) scale the result back up
	return clampf(mp * maxf(k, 1.0) * float(c.get("felt_gain", 2.2)), 0.0, 1.0)


## fear_felt = felt * (1.2 - courage), scaled by the culture's fear multiplier (monster towns read aura as a language).
static func fear_of(o: Dictionary, felt_v: float) -> float:
	var cul: Dictionary = (Data.table("aura_culture").get("cultures", {}) as Dictionary).get(culture_of(o), {})
	return felt_v * (float(Data.table("aura_roles").get("courage_bias", 1.2)) - courage_of(o)) * float(cul.get("fear_mult", 1.0))


## Tier 0..5 from fear_felt, with a hysteresis band below the previous tier (no flicker at a threshold).
static func tier_of(fear: float, prev := 0) -> int:
	var th: Array = Data.table("aura_roles").get("tiers", [0.12, 0.3, 0.55, 0.8, 1.0])
	var t := 0
	for i in th.size():
		if fear >= float(th[i]):
			t = i + 1
	if prev > t and prev >= 1 and fear >= float(th[prev - 1]) - float(Data.table("aura_roles").get("hysteresis", 0.03)):
		return prev
	return t


# ------------------------------------------------------------------ roles and reactions

## Crowd role (design 7). o: {persona, age_group, has_child, guard, profession, culture, magic_sense, drunk, stall_owner, chaos}.
static func role_of(o: Dictionary, tier: int, read := "secular") -> String:
	var pe: Dictionary = o.get("persona", {})
	var pious := clampf(float(pe.get("pious", 0.3)), 0.0, 1.0)
	var courage := courage_of(o)
	if bool(o.get("guard", false)):
		return "guard"
	if String(o.get("age_group", "adult")) in ["child", "infant"]:
		return "child"
	if bool(o.get("has_child", false)) and tier >= 2:
		return "parent"
	if String(o.get("age_group", "adult")) == "elder":
		return "elder"
	if bool(o.get("drunk", false)):
		return "drunk"
	if float(o.get("magic_sense", 0.1)) >= 0.7 and bool(o.get("mage", false)):
		return "rival_mage"
	if String(o.get("profession", "")) in ["healer", "priest"]:
		return "healer"
	if pious > 0.6 and read == "holy":
		return "devotee"
	if pious > 0.6 and read == "demonic":
		return "fanatic"
	if bool(o.get("stall_owner", false)) and tier >= 2:
		return "merchant"
	if float(o.get("chaos", 0.0)) >= float(((Data.table("aura_roles").get("chaos", {}) as Dictionary).get("looters_at", 0.6))) and float(pe.get("greedy", 0.3)) >= 0.8 and courage >= 0.8:
		return "looter"
	if String(o.get("profession", "")) == "beggar":
		return "beggar"
	if float(o.get("curiosity", 0.0)) > 0.7 and tier <= 2:
		return "gawker"
	return "clearer"


## Chaos index (design 7): abandoned stalls, unguarded, collapsed, minus guards near. 0..1.
static func chaos_index(stalls: int, unguarded: bool, collapsed: int, guards_near: int) -> float:
	var c: Dictionary = Data.table("aura_roles").get("chaos", {})
	return clampf(float(stalls) * float(c.get("stall", 0.1)) + (float(c.get("unguarded", 0.2)) if unguarded else 0.0) + float(collapsed) * float(c.get("collapsed", 0.1)) - float(guards_near) * float(c.get("guard", 0.3)), 0.0, 1.0)


static func _h(o: Dictionary, tag: String) -> int:
	return absi(hash([tag, int(o.get("id_n", 0)), int(o.get("day", 0))]))


## The reaction request an observer at `tier` makes. Always one of ALLOWED. `signature` decides holy/demonic reads in church kingdoms.
static func reaction_for(tier: int, o: Dictionary, signature := "warm_gold") -> int:
	var K := RR.Kind
	if tier <= 0:
		return 0
	var read := reading(o, signature)
	var cul: Dictionary = (Data.table("aura_culture").get("cultures", {}) as Dictionary).get(culture_of(o), {})
	var pe: Dictionary = o.get("persona", {})
	var courage := courage_of(o)
	var pious := clampf(float(pe.get("pious", 0.3)), 0.0, 1.0)
	var guard := bool(o.get("guard", false))
	var gnear := bool(o.get("guard_near", false)) and bool(cul.get("calls_guard", true))
	var child := bool(o.get("has_child", false))
	var frail := bool(o.get("frail", false)) or String(o.get("age_group", "adult")) in ["elder", "infant"]
	var can_hide := bool(o.get("can_hide", false))
	var h := _h(o, "aura")
	match tier:
		1:
			return K.GLANCE if h % 2 == 0 else K.LOOK_AWAY
		2:
			if pious > 0.6 and read == "holy":
				return K.KNEEL
			if pious > 0.6 and read == "demonic":
				return K.CALL_GUARD if gnear else K.WARN
			if guard:
				return K.STEP_BACK
			if child:
				return K.HIDE
			if bool(cul.get("licence", false)) and gnear and courage < 0.8:
				return K.CALL_GUARD
			return K.STEP_BACK if h % 3 != 0 else K.FLINCH
		3:
			if guard:
				return K.CALL_GUARD if bool(cul.get("calls_guard", true)) else K.STEP_BACK
			if child:
				return K.FLEE_WITH_CHILD
			if frail:
				return K.KNEEL
			if pious > 0.6 and read == "holy":
				return K.KNEEL
			if can_hide and courage < 0.6:
				return K.HIDE
			if gnear and courage > 0.4:
				return K.CALL_GUARD
			return K.FLEE
		4:
			if frail:
				return K.FAINT
			return K.KNEEL
		_:
			if guard and courage >= 0.8:
				return K.KNEEL
			return K.FAINT
	return K.GLANCE


## Street repulsion cost for an edge midpoint (design 7): grows with fear and falls with distance, so crowds flow around the
## player instead of teleporting. Zero outside reach*0.5.
static func repulsion_cost(edge_pos: Vector2, player_pos: Vector2, reach: float, fear: float) -> float:
	var r := reach * 0.5
	var d := edge_pos.distance_to(player_pos)
	if d >= r or r <= 0.0:
		return 0.0
	return clampf(fear, 0.0, 1.0) * 6.0 * (1.0 - d / r)
