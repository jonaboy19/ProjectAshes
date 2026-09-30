extends RefCounted
## The player's own family across generations: courtship, marriage, children,
## parents ageing and dying, and succession to an heir.
## (docs/RISING_ASHES_LIFE_SIM_DESIGN.md, "Living world simulation" >
## "Families ... generations, inheritance, bloodlines ... succession"; Pillar 3,
## "The world never waits.")
##
## Courtship: an NPC Relationships has at "close_friend" tier, of age, can be
## courted (gifts, dates) through stages interested -> courting -> betrothed.
## Marriage (on top of betrothal) needs a home: Life.property.home() or an
## owned/leased homestead plot with a cottage built.
##
## Children are born while married and housed: a Caldric given name, a sex, a
## birth day, tendencies averaged from both parents (plus noise), and an
## elemental affinity (60% chance of one parent's element, 10% chance of a
## dual of both parents' elements, else the usual random/none odds — see
## RAAwakening). They age purely from their birth day (RALifePath.DAYS_PER_YEAR).
##
## Parents (already in Life.life_path) are given a hidden, seeded age at the
## player's birth the first time they're checked, and past PARENT_DEATH_AGE
## face a rising yearly chance of death: a small inheritance and a biography
## note, never removed from life_path.parents (their name lives on there).
##
## Succession (see succeed_to()): when the player dies of old age or retires
## (50+), heir_candidates() offers the eldest living adult child, or the
## spouse if there is no child, or none at all ("the story ends"). The
## outgoing life's biography is archived into chronicles() as "Chronicles of
## your family" before the swap. Gold (minus INHERITANCE_TAX), properties,
## the homestead, lordship, a fraction of noble standing and of biography
## reputation, and the family name carry over, along with the heir's OWN
## tendencies and affinity (not the outgoing character's). Mastery only
## carries a small fraction ("learned at the parent's knee") and personal
## titles do not carry at all. Only player-owned fields move: WorldSim, the
## economy and nobility's own state are untouched.
##
## Uses Life.get("life_courses") (has_method-guarded) for a real NPC's name,
## sex, culture, tendencies and affinity when that notable-NPC life
## simulation exists; otherwise falls back to Life.relationships' own NPC
## record (scripts/sim/relationships.gd), filling in anything missing with a
## seeded, deterministic guess.
##
## Pure data (RefCounted, serialisable). Reads and writes Life., Game. and
## WorldSim. directly, the same way scripts/sim/property.gd and nobility.gd do.

const RALifePath := preload("res://scripts/sim/life_path.gd")
const RATendencies := preload("res://scripts/sim/tendencies.gd")
const RAAwakening := preload("res://scripts/sim/awakening.gd")

## Courtship point thresholds to advance a stage.
const COURT_POINTS_COURTING := 20.0
const COURT_POINTS_BETROTHED := 50.0
const DATE_POINTS := 10.0
const GIFT_POINTS := 6.0

## Children.
const MAX_CHILDREN := 6
const CHILD_DAILY_CHANCE := 0.02
const CHILD_MIN_PLAYER_AGE := 16
const CHILD_MAX_PLAYER_AGE := 45
## Chance the child gets one parent's single element / a dual of both / (the
## remainder) the usual random-or-none Blessing odds.
const AFFINITY_SINGLE_CHANCE := 0.60
const AFFINITY_DUAL_CHANCE := 0.10

## Parents (see RALifePath.parents; ages are never stored there, only here).
const PARENT_MIN_AGE_AT_BIRTH := 22
const PARENT_MAX_AGE_AT_BIRTH := 40
const PARENT_DEATH_START_AGE := 60
const PARENT_DEATH_CHANCE_AT_START := 0.02     # per year, once past PARENT_DEATH_START_AGE
const PARENT_DEATH_CHANCE_GROWTH := 0.015      # extra per year beyond that
const PARENT_LEGACY_GOLD_MIN := 40
const PARENT_LEGACY_GOLD_MAX := 200

## Player old age / retirement / succession.
const PLAYER_OLD_AGE_START := 70
const PLAYER_DEATH_CHANCE_AT_START := 0.04
const PLAYER_DEATH_CHANCE_GROWTH := 0.02
const RETIRE_MIN_AGE := 50
const HEIR_MIN_AGE := 16
const INHERITANCE_TAX := 0.25
const MASTERY_INHERIT_FRACTION := 0.05
const REPUTATION_INHERIT_FRACTION := 0.3
const NOBLE_INHERIT_FRACTION := 0.5

## npc_id -> {stage: "interested"/"courting"/"betrothed", points: float, since_day: int}
var courtships: Dictionary = {}
## {} or {id, name, sex, culture, occupation, tendencies: {key: float}, affinity:
##  {element, dual, none}, opinion: 0..100, needs: 0..100, age_at_marriage: int, since_day: int}
var spouse: Dictionary = {}
## [{id, name, sex, birth_day, tendencies: {}, affinity: {}, alive, dead_day}]
var children: Array[Dictionary] = []
## role ("mother"/"father"/...) -> {age_at_birth: int, alive: bool, death_day: int}
var parent_state: Dictionary = {}
## Archived past lives: [{name, family_name, summary: [String], day}]
var chronicles: Array[Dictionary] = []

var next_child_id := 1
var _last_tick_day := -1


# --- small helpers ---------------------------------------------------------------

func _now() -> float:
	return WorldSim.day + WorldSim.time_of_day / 24.0


func _seed_rng(parts: Array) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([WorldSim.SEED] + parts)
	return rng


func _npc_name(npc_id: String) -> String:
	return String(_npc_profile(npc_id).get("name", npc_id))


## Best-known facts about an NPC being courted: name, sex, culture, role,
## whether they're a child, tendencies and affinity. Prefers the notable-NPC
## life simulation (scripts/sim/life_courses.gd, if that system exists and
## exposes `profile(npc_id)`), else Life.relationships' own record, filling
## in the rest with a seeded, deterministic guess so results are repeatable.
func _npc_profile(npc_id: String) -> Dictionary:
	var lc: Object = Life.get("life_courses")
	if lc != null and lc.has_method("profile"):
		var p: Variant = lc.profile(npc_id)
		if p is Dictionary and not (p as Dictionary).is_empty():
			return p
	var e: Dictionary = {}
	var rel: Object = Life.get("relationships")
	if rel != null and "npcs" in rel:
		e = (rel.npcs as Dictionary).get(npc_id, {})
	var sex_rng := _seed_rng(["npc_sex", npc_id])
	return {
		"name": String(e.get("name", npc_id)), "culture": String(e.get("culture", "caldric")),
		"role": String(e.get("role", "villager")), "is_child": false,
		"sex": "male" if sex_rng.randf() < 0.5 else "female",
		"tendencies": _random_tendencies(_seed_rng(["npc_tendencies", npc_id])),
		"affinity": _random_affinity(_seed_rng(["npc_affinity", npc_id])),
	}


func _random_tendencies(rng: RandomNumberGenerator) -> Dictionary:
	var out := {}
	for k: String in RATendencies.KEYS:
		out[k] = rng.randf_range(0.2, 0.6)
	return out


func _random_affinity(rng: RandomNumberGenerator) -> Dictionary:
	if rng.randf() < RAAwakening.NONE_CHANCE:
		return {"element": "", "dual": "", "none": true}
	var el: String = RAAwakening.ELEMENTS[rng.randi() % RAAwakening.ELEMENTS.size()]
	var dual := ""
	if rng.randf() < RAAwakening.DUAL_CHANCE:
		var rest: Array = RAAwakening.ELEMENTS.filter(func(e: String) -> bool: return e != el)
		dual = String(rest[rng.randi() % rest.size()])
	return {"element": el, "dual": dual, "none": false}


# --- courtship ---------------------------------------------------------------------

func stage(npc_id: String) -> String:
	return String(courtships.get(npc_id, {}).get("stage", ""))


func _has_marriage_home() -> bool:
	if not Life.property.home().is_empty():
		return true
	return Life.homestead.has_piece("cottage")


func can_court(npc_id: String) -> String:
	if not Life.is_adult():
		return "You're not old enough to court anyone."
	if is_married():
		return "You're already married."
	if stage(npc_id) != "":
		return ""
	var rel: Object = Life.get("relationships")
	if rel == null or rel.tier(npc_id, _now()) != "close_friend":
		return "You're not close enough with them yet."
	if bool(_npc_profile(npc_id).get("is_child", false)):
		return "They're not old enough."
	return ""


func court(npc_id: String) -> String:
	if stage(npc_id) != "":
		return "You're already courting %s." % _npc_name(npc_id)
	var why := can_court(npc_id)
	if why != "":
		return why
	courtships[npc_id] = {"stage": "interested", "points": 0.0, "since_day": WorldSim.day,
		"last_date_day": -1}
	return "You let %s know you're interested." % _npc_name(npc_id)


func _advance_stage(npc_id: String) -> void:
	var c: Dictionary = courtships[npc_id]
	var pts := float(c["points"])
	if String(c["stage"]) == "interested" and pts >= COURT_POINTS_COURTING:
		c["stage"] = "courting"


func add_courtship_points(npc_id: String, amount: float) -> void:
	if not courtships.has(npc_id):
		return
	var c: Dictionary = courtships[npc_id]
	c["points"] = float(c["points"]) + amount
	_advance_stage(npc_id)


## Gives a gift toward courtship (wraps Life.relationships.give_gift): {ok, delta, reaction, text}.
func give_courtship_gift(npc_id: String, item: String) -> Dictionary:
	var rel: Object = Life.get("relationships")
	var r: Dictionary = rel.give_gift(npc_id, item, _now()) if rel != null else {"ok": false, "text": ""}
	if bool(r.get("ok", false)) and courtships.has(npc_id):
		var mult: float = {"loves": 1.5, "likes": 1.0, "neutral": 0.4, "dislikes": 0.0}.get(String(r.get("reaction", "")), 0.5)
		add_courtship_points(npc_id, GIFT_POINTS * float(mult))
	return r


## A date at the inn, a festival, or wherever the caller names. Costs no time
## here (the caller advances WorldSim if it wants to).
func date(npc_id: String, at := "the inn") -> String:
	if stage(npc_id) == "":
		return "You're not courting %s." % _npc_name(npc_id)
	var courtship: Dictionary = courtships[npc_id]
	if int(courtship.get("last_date_day", -1)) == WorldSim.day:
		return "You've already spent time with %s today." % _npc_name(npc_id)
	add_courtship_points(npc_id, DATE_POINTS)
	var rel: Object = Life.get("relationships")
	if rel != null:
		rel.add_modifier(npc_id, "date", "A date together", 4.0, _now(), 10.0)
	courtship["last_date_day"] = WorldSim.day
	return "You spend time with %s at %s." % [_npc_name(npc_id), at]


func can_propose(npc_id: String) -> String:
	var st := stage(npc_id)
	if st != "courting":
		return "You need to court them a while longer first."
	if float(courtships[npc_id].get("points", 0.0)) < COURT_POINTS_BETROTHED:
		return "You need to court them a while longer first."
	if not _has_marriage_home():
		return "You'll need a home of your own first."
	return ""


func propose(npc_id: String) -> String:
	var why := can_propose(npc_id)
	if why != "":
		return why
	courtships[npc_id]["stage"] = "betrothed"
	Life.life_path.set_flag("engaged")
	return "%s says yes. You're betrothed!" % _npc_name(npc_id)


func can_marry(npc_id: String) -> String:
	if is_married():
		return "You're already married."
	if stage(npc_id) != "betrothed":
		return "You need to be betrothed first."
	if not _has_marriage_home():
		return "You'll need a home of your own to marry."
	return ""


func marry(npc_id: String) -> String:
	var why := can_marry(npc_id)
	if why != "":
		return why
	var info := _npc_profile(npc_id)
	var rng := _seed_rng(["spouse_age", npc_id, WorldSim.day])
	spouse = {
		"id": npc_id, "name": String(info.get("name", "Your spouse")), "sex": String(info.get("sex", "female")),
		"culture": String(info.get("culture", "caldric")), "occupation": String(info.get("role", "villager")),
		"tendencies": info.get("tendencies", _random_tendencies(rng)).duplicate(true),
		"affinity": (info.get("affinity", _random_affinity(rng)) as Dictionary).duplicate(),
		"opinion": 70.0, "needs": 80.0, "age_at_marriage": rng.randi_range(18, 35), "since_day": WorldSim.day,
	}
	courtships.erase(npc_id)
	Life.life_path.set_flag("married")
	Life.biography.add_highlight("Married %s" % String(spouse["name"]), WorldSim.day)
	return "You marry %s." % String(spouse["name"])


func is_married() -> bool:
	return not spouse.is_empty()


## A working spouse's daily contribution to the household, by occupation.
const _SPOUSE_WAGE := {"farmer": 6, "blacksmith": 9, "merchant": 8, "guard": 7, "innkeeper": 7,
	"healer": 8, "trader": 8, "laborer": 4, "noble": 12, "villager": 5}

func spouse_income() -> int:
	if not is_married():
		return 0
	return int(_SPOUSE_WAGE.get(String(spouse.get("occupation", "villager")), 5))


func spouse_age() -> int:
	if not is_married():
		return -1
	var years := int((WorldSim.day - int(spouse.get("since_day", WorldSim.day))) / float(RALifePath.DAYS_PER_YEAR))
	return int(spouse.get("age_at_marriage", 25)) + years


# --- arranged marriages (nobility) --------------------------------------------------

## A noble house may offer one of its heirs in marriage once its opinion of the
## player is friendly (Life.nobility exists and SPONSOR_OPINION is met).
## {ok, house_id, name, sex, text}. nobility.gd has no dedicated
## "offer_marriage"/"form_alliance" hook yet, so this reads its public
## `houses`/`opinion()` and, on acceptance, falls back to change_opinion() plus
## appending to its `alliances` array directly (see accept_arranged_marriage).
func offer_arranged_marriage(house_id: String) -> Dictionary:
	if is_married():
		return {"ok": false, "text": "You are already married."}
	var nobility: Object = Life.get("nobility")
	if nobility == null:
		return {"ok": false, "text": "No noble houses exist yet."}
	if float(nobility.opinion(house_id)) < 30.0:   # RANobility.SPONSOR_OPINION
		return {"ok": false, "text": "%s doesn't think well enough of you to offer a match." % String(nobility.house_name(house_id))}
	var h: Dictionary = nobility.house_by_id(house_id)
	if h.is_empty():
		return {"ok": false, "text": "No such house."}
	var heirs: Array = h.get("heirs", [])
	if heirs.is_empty():
		return {"ok": false, "text": "%s has no heir to offer." % String(h["name"])}
	var candidate: Dictionary = heirs[0]
	return {"ok": true, "house_id": house_id, "name": String(candidate["name"]),
		"sex": String(candidate.get("gender", "female")),
		"text": "%s offers %s's hand in marriage, an alliance with your family." % [String(h["name"]), String(candidate["name"])]}


func accept_arranged_marriage(offer: Dictionary) -> String:
	if is_married():
		return "You are already married."
	if not _has_marriage_home():
		return "You'll need a home of your own to marry."
	var house_id := String(offer.get("house_id", ""))
	var rng := _seed_rng(["arranged_spouse", house_id, WorldSim.day])
	spouse = {
		"id": "noble:%s" % house_id, "name": String(offer.get("name", "Your spouse")),
		"sex": String(offer.get("sex", "female")), "culture": "caldric", "occupation": "noble",
		"tendencies": _random_tendencies(rng), "affinity": _random_affinity(rng),
		"opinion": 60.0, "needs": 80.0, "age_at_marriage": rng.randi_range(18, 35), "since_day": WorldSim.day,
		"house_id": house_id,
	}
	Life.life_path.set_flag("married")
	var nobility: Object = Life.get("nobility")
	var house_name := house_id
	if nobility != null:
		house_name = String(nobility.house_name(house_id))
		if nobility.has_method("form_alliance"):
			nobility.form_alliance(house_id, "player")
		else:
			nobility.change_opinion(house_id, 25.0)
			if "alliances" in nobility:
				(nobility.alliances as Array).append([house_id, "player", WorldSim.day])
	Life.biography.add_highlight("Married into %s, sealing an alliance" % house_name, WorldSim.day)
	return "You marry %s, sealing an alliance with %s." % [String(spouse["name"]), house_name]


# --- children ------------------------------------------------------------------------

func child_age(c: Dictionary, day := -1) -> int:
	var d := day if day >= 0 else WorldSim.day
	return int(floor((d - int(c["birth_day"])) / float(RALifePath.DAYS_PER_YEAR)))


## Living children with a computed `age`, eldest first.
func children_list(day := -1) -> Array:
	var out := []
	for c: Dictionary in children:
		if not bool(c.get("alive", true)):
			continue
		var e := c.duplicate(true)
		e["age"] = child_age(c, day)
		out.append(e)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["age"]) > int(b["age"]))
	return out


func _find_child(id: int) -> Dictionary:
	for c: Dictionary in children:
		if int(c["id"]) == id:
			return c
	return {}


func _can_conceive() -> bool:
	if not is_married() or children.size() >= MAX_CHILDREN:
		return false
	if not _has_marriage_home():
		return false
	var age := Life.age()
	return age >= CHILD_MIN_PLAYER_AGE and age <= CHILD_MAX_PLAYER_AGE


## {} or the affinity {element, dual, none} of the player's own Blessing.
func _player_affinity() -> Dictionary:
	if Life.awakening.has_happened():
		return {"element": Life.awakening.element, "dual": Life.awakening.dual, "none": Life.awakening.none}
	return {"element": "", "dual": "", "none": true}


func _inherit_affinity(rng: RandomNumberGenerator) -> Dictionary:
	var pa := _player_affinity()
	var sa: Dictionary = spouse.get("affinity", {"element": "", "dual": "", "none": true})
	var roll := rng.randf()
	if roll < AFFINITY_SINGLE_CHANCE:
		var pick: Dictionary = pa if rng.randf() < 0.5 else sa
		var other: Dictionary = sa if pick == pa else pa
		if bool(pick.get("none", true)) and not bool(other.get("none", true)):
			pick = other
		if bool(pick.get("none", true)):
			return _random_affinity(rng)
		return {"element": String(pick["element"]), "dual": "", "none": false}
	elif roll < AFFINITY_SINGLE_CHANCE + AFFINITY_DUAL_CHANCE:
		if not bool(pa.get("none", true)) and not bool(sa.get("none", true)) and String(pa["element"]) != String(sa["element"]):
			return {"element": String(pa["element"]), "dual": String(sa["element"]), "none": false}
		return _random_affinity(rng)
	return _random_affinity(rng)


func _blend_tendencies(rng: RandomNumberGenerator) -> Dictionary:
	var out := {}
	var pt: Dictionary = Life.tendencies.values
	var st: Dictionary = spouse.get("tendencies", {})
	for k: String in RATendencies.KEYS:
		var avg := (float(pt.get(k, 0.35)) + float(st.get(k, 0.35))) / 2.0
		out[k] = clampf(avg + rng.randf_range(-0.12, 0.12), 0.0, 1.0)
	return out


func _birth_child(day: int, rng: RandomNumberGenerator) -> Dictionary:
	var sex := "male" if rng.randf() < 0.5 else "female"
	var given := Life.lore.random_name("caldric", rng, sex).get_slice(" ", 0)
	var child := {
		"id": next_child_id, "name": given, "sex": sex, "birth_day": day,
		"tendencies": _blend_tendencies(rng), "affinity": _inherit_affinity(rng),
		"alive": true, "dead_day": -1,
	}
	next_child_id += 1
	children.append(child)
	Life.biography.add_highlight("%s %s was born" % [given, Life.life_path.family_name], day)
	return child


func _maybe_conceive(day: int) -> Dictionary:
	if not _can_conceive():
		return {}
	var rng := _seed_rng(["conceive", day])
	if rng.randf() >= CHILD_DAILY_CHANCE:
		return {}
	return _birth_child(day, rng)


# --- parents -------------------------------------------------------------------------

func _ensure_parent_state() -> void:
	for p: Dictionary in Life.life_path.parents:
		var role := String(p["role"])
		if not parent_state.has(role):
			var rng := _seed_rng(["parent_age", role])
			parent_state[role] = {"age_at_birth": rng.randi_range(PARENT_MIN_AGE_AT_BIRTH, PARENT_MAX_AGE_AT_BIRTH),
				"alive": true, "death_day": -1}


func parent_age(role: String) -> int:
	_ensure_parent_state()
	if not parent_state.has(role):
		return -1
	return int(parent_state[role]["age_at_birth"]) + Life.age()


func parent_alive(role: String) -> bool:
	_ensure_parent_state()
	return bool(parent_state.get(role, {}).get("alive", false))


func _parent_funeral(role: String, day: int) -> String:
	var p := Life.life_path.parent(role)
	var name := String(p.get("name", role.capitalize()))
	var rng := _seed_rng(["legacy", role, day])
	var legacy := rng.randi_range(PARENT_LEGACY_GOLD_MIN, PARENT_LEGACY_GOLD_MAX)
	Game.add_gold(legacy)
	Life.biography.add_highlight("%s passed away; you inherit %d gold." % [name, legacy], day)
	Life.life_path.set_flag("parent_dead:" + role)
	return "%s has died. A family funeral; you inherit %d gold from their savings." % [name, legacy]


func _tick_parents(day: int) -> Array[String]:
	_ensure_parent_state()
	var out: Array[String] = []
	for role: String in parent_state.keys().duplicate():
		var st: Dictionary = parent_state[role]
		if not bool(st["alive"]):
			continue
		var age := int(st["age_at_birth"]) + Life.age()
		if age < PARENT_DEATH_START_AGE:
			continue
		var yearly := PARENT_DEATH_CHANCE_AT_START + float(age - PARENT_DEATH_START_AGE) * PARENT_DEATH_CHANCE_GROWTH
		var daily := clampf(yearly / float(RALifePath.DAYS_PER_YEAR), 0.0, 0.9)
		var rng := _seed_rng(["parent_death", role, day])
		if rng.randf() < daily:
			st["alive"] = false
			st["death_day"] = day
			out.append(_parent_funeral(role, day))
	return out


# --- old age, retirement, succession --------------------------------------------------

func check_old_age_death(age: int, day: int) -> bool:
	if age < PLAYER_OLD_AGE_START:
		return false
	var yearly := PLAYER_DEATH_CHANCE_AT_START + float(age - PLAYER_OLD_AGE_START) * PLAYER_DEATH_CHANCE_GROWTH
	var daily := clampf(yearly / float(RALifePath.DAYS_PER_YEAR), 0.0, 0.95)
	return _seed_rng(["old_age_death", day]).randf() < daily


func can_retire(age := -1) -> bool:
	return (age if age >= 0 else Life.age()) >= RETIRE_MIN_AGE


## Who could take up the story: the eldest living child 16+, else the spouse,
## else none (the story ends). [{kind: "child"/"spouse", id, name, age, sex}]
func heir_candidates(day := -1) -> Array:
	var d := day if day >= 0 else WorldSim.day
	var out := []
	for c: Dictionary in children_list(d):
		if int(c["age"]) >= HEIR_MIN_AGE:
			out.append({"kind": "child", "id": int(c["id"]), "name": "%s %s" % [c["name"], Life.life_path.family_name],
				"age": int(c["age"]), "sex": String(c["sex"])})
	if out.is_empty() and is_married():
		out.append({"kind": "spouse", "id": spouse["id"], "name": String(spouse["name"]),
			"age": spouse_age(), "sex": String(spouse.get("sex", ""))})
	return out


## Everything a past life is remembered by, once archived (see succeed_to()).
func chronicles_list() -> Array:
	return chronicles.duplicate(true)


## Swaps Life's player-owned state to the chosen heir; keeps the world as it
## is. {ok, text}. See the file header for exactly what does and doesn't carry.
func succeed_to(heir_id: Variant) -> Dictionary:
	var chosen := {}
	for c: Dictionary in heir_candidates():
		if str(c["id"]) == str(heir_id):
			chosen = c
			break
	if chosen.is_empty():
		return {"ok": false, "text": "No such heir."}
	var old_name := Life.life_path.full_name()
	var old_age := Life.age()
	var family_name := Life.life_path.family_name
	var home_settlement := Life.life_path.home_settlement
	var home_pos := Life.life_path.home_pos
	# Archive the outgoing life before anything else changes.
	chronicles.append({"name": old_name, "family_name": family_name,
		"summary": Life.biography.summary(WorldSim.day), "day": WorldSim.day})
	# Gold, taxed.
	Game.gold = int(round(float(Game.gold) * (1.0 - INHERITANCE_TAX)))
	# Noble standing: only a fraction survives the change of hands.
	var nobility: Object = Life.get("nobility")
	if nobility != null and "houses" in nobility:
		for h: Dictionary in (nobility.houses as Array):
			var hid := String(h["id"])
			var op := float(nobility.opinion(hid))
			nobility.change_opinion(hid, -op * (1.0 - NOBLE_INHERIT_FRACTION))
	# Biography: a fraction of reputation carries, the chapter log is archived above.
	var bio := Life.biography
	for s: String in bio.reputation.keys().duplicate():
		bio.reputation[s] = float(bio.reputation[s]) * REPUTATION_INHERIT_FRACTION
	bio.chapters.clear()
	# Mastery only a small fraction ("learned at the parent's knee").
	for disc: String in Life.mastery.xp.keys().duplicate():
		Life.mastery.xp[disc] = float(Life.mastery.xp[disc]) * MASTERY_INHERIT_FRACTION
	Life.mastery.days_practised.clear()
	# Personal titles do not carry at all.
	Life.titles.earned_ids.clear()
	# The heir's own tendencies and affinity.
	var heir_tendencies: Dictionary
	var heir_affinity: Dictionary
	var heir_age: int
	var heir_sex: String
	var heir_given: String
	if String(chosen["kind"]) == "child":
		var c := _find_child(int(chosen["id"]))
		heir_tendencies = c.get("tendencies", {})
		heir_affinity = c.get("affinity", {"element": "", "dual": "", "none": true})
		heir_age = child_age(c)
		heir_sex = String(c["sex"])
		heir_given = String(c["name"])
		children.erase(c)
	else:
		heir_tendencies = spouse.get("tendencies", {})
		heir_affinity = spouse.get("affinity", {"element": "", "dual": "", "none": true})
		heir_age = maxi(HEIR_MIN_AGE, spouse_age())
		heir_sex = String(spouse.get("sex", "female"))
		heir_given = String(spouse.get("name", "Heir")).get_slice(" ", 0)
	# New parents, for the child heir: the outgoing player and (if any) their
	# spouse. The spouse-fallback heir's own parents are unknown and untracked.
	var new_parents: Array = []
	parent_state.clear()
	if String(chosen["kind"]) == "child":
		var mother_name := old_name
		var father_name := ""
		var mother_age_at_birth := old_age - heir_age
		var father_age_at_birth := -1
		if is_married():
			father_name = String(spouse.get("name", ""))
			var f_age_now := spouse_age()
			father_age_at_birth = (f_age_now - heir_age) if f_age_now >= 0 else -1
		# The outgoing player is recorded as "mother" here regardless of sex
		# (life.gd/main.gd track no player sex field yet — see the reported hooks).
		new_parents.append({"id": -1, "name": mother_name, "role": "mother"})
		if father_name != "":
			new_parents.append({"id": -1, "name": father_name, "role": "father"})
			parent_state["father"] = {"age_at_birth": maxi(16, father_age_at_birth), "alive": true, "death_day": -1}
		parent_state["mother"] = {"age_at_birth": maxi(16, mother_age_at_birth), "alive": true, "death_day": -1}
		# The former spouse is parentage input only; they are not the new heir's spouse.
		spouse = {}
	courtships.clear()
	var new_day := WorldSim.day - heir_age * RALifePath.DAYS_PER_YEAR
	Life.life_path.begin(new_day, WorldSim.time_of_day, heir_given, family_name, new_parents, home_settlement, home_pos)
	Life.life_path.set_age(heir_age, WorldSim.day, WorldSim.time_of_day)
	Life.life_path.set_flag("succeeded_generation")
	# Tendencies: the heir's own.
	for k: String in RATendencies.KEYS:
		Life.tendencies.values[k] = float(heir_tendencies.get(k, 0.35))
	# Affinity: the heir's own Blessing outcome, already settled at their birth.
	Life.awakening.done = true
	Life.awakening.none = bool(heir_affinity.get("none", true))
	Life.awakening.element = String(heir_affinity.get("element", ""))
	Life.awakening.dual = String(heir_affinity.get("dual", ""))
	Life.awakening.tier = "common"
	Life.awakening.day = WorldSim.day
	if not Life.awakening.none:
		for f: String in Life.awakening.flags():
			Life.life_path.set_flag(f)
	else:
		Life.life_path.set_flag("blessing:none")
	return {"ok": true, "text": "%s steps up to carry on the %s family." % [heir_given, family_name],
		"heir_sex": heir_sex, "heir_age": heir_age}


# --- daily tick ------------------------------------------------------------------------

## Once a day: parents age/die, a married household earns and may conceive.
## Call from life.gd's daily tick (see the hook lines this task reports).
func daily_tick(day: int) -> Array[String]:
	if day == _last_tick_day:
		return []
	_last_tick_day = day
	var out: Array[String] = []
	out.append_array(_tick_parents(day))
	if is_married():
		var wage := spouse_income()
		if wage > 0:
			Game.add_gold(wage)
		var child := _maybe_conceive(day)
		if not child.is_empty():
			out.append("%s %s is born." % [String(child["name"]), Life.life_path.family_name])
	return out


# --- save / load -------------------------------------------------------------------------

func serialize() -> Dictionary:
	return {
		"courtships": courtships.duplicate(true),
		"spouse": spouse.duplicate(true),
		"children": children.duplicate(true),
		"parent_state": parent_state.duplicate(true),
		"chronicles": chronicles.duplicate(true),
		"next_child_id": next_child_id,
		"last_tick_day": _last_tick_day,
	}


func deserialize(d: Dictionary) -> void:
	courtships.clear()
	var co: Dictionary = d.get("courtships", {})
	for k: String in co:
		var e: Dictionary = co[k]
		courtships[k] = {"stage": String(e.get("stage", "interested")), "points": float(e.get("points", 0.0)),
			"since_day": int(e.get("since_day", 0)), "last_date_day": int(e.get("last_date_day", -1))}
	spouse = (d.get("spouse", {}) as Dictionary).duplicate(true)
	children.clear()
	for c: Variant in d.get("children", []):
		var cd: Dictionary = c
		children.append({"id": int(cd.get("id", 0)), "name": String(cd.get("name", "")),
			"sex": String(cd.get("sex", "female")), "birth_day": int(cd.get("birth_day", 0)),
			"tendencies": (cd.get("tendencies", {}) as Dictionary).duplicate(),
			"affinity": (cd.get("affinity", {}) as Dictionary).duplicate(),
			"alive": bool(cd.get("alive", true)), "dead_day": int(cd.get("dead_day", -1))})
	parent_state.clear()
	var ps: Dictionary = d.get("parent_state", {})
	for role: String in ps:
		var e2: Dictionary = ps[role]
		parent_state[role] = {"age_at_birth": int(e2.get("age_at_birth", 30)), "alive": bool(e2.get("alive", true)),
			"death_day": int(e2.get("death_day", -1))}
	chronicles.clear()
	for ch: Variant in d.get("chronicles", []):
		var chd: Dictionary = ch
		chronicles.append({"name": String(chd.get("name", "")), "family_name": String(chd.get("family_name", "")),
			"summary": (chd.get("summary", []) as Array).duplicate(), "day": int(chd.get("day", 0))})
	next_child_id = int(d.get("next_child_id", 1))
	_last_tick_day = int(d.get("last_tick_day", -1))
