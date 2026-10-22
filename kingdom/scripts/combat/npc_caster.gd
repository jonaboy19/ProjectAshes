extends RefCounted
## NpcCaster: an NPC that casts through the SAME AbilityRunner as the player. Composition, not inheritance:
##   - NpcFighter (scripts/combat/npc_fighter.gd) decides the melee side (intent, moves, reactions, poise) and
##     keeps the seeded dice, so duels replay exactly;
##   - AbilityRunner runs the casts with costs OFF (cooldown only, ashes-ability-system) and auto-timed chants;
##   - the power profile (PowerTrees.npc_profile) decides chant vs chantless exactly as it does for the player.
## Data: data/powers/npc_casters.json (bandit_mage, sect_disciple, knight_captain, veteran_mage).
##
## The body (monster/humanoid actor, or the headless arena) calls, every think tick (4 Hz):
##   var d := caster.think(dt, ctx)       # {intent, ability, fight}; ability != "" means "start this cast now"
##   if d.ability != "": caster.cast(d.ability, target)
## and every frame caster.update(dt). It resolves executed casts by connecting runner.executed (or the
## `execute` hook) and calls caster.deal(...) / caster.apply_to(...) so wards and stacking families apply.
## A stagger of the fighter breaks a chant (`on_blow`).

const Fighter := preload("res://scripts/combat/npc_fighter.gd")
const Runner := preload("res://scripts/abilities/ability_runner.gd")
const EffectSet := preload("res://scripts/abilities/effect_set.gd")
const AbilityLib := preload("res://scripts/abilities/ability_lib.gd")
const AbilityDef := preload("res://scripts/abilities/ability_def.gd")
const PowerTrees := preload("res://scripts/abilities/power_trees.gd")
const DATA_PATH := "res://data/powers/npc_casters.json"

const WHEN := ["attack", "gap", "guard", "heal", "buff"]

## Active casters in the world are capped (mobile budget: each one ticks a runner and effect sets).
const MAX_ACTIVE := 6
const THINK := 0.25

static var _rows: Dictionary = {}
static var active := 0

var id := ""
var row: Dictionary = {}
var fighter: RefCounted
var runner: RefCounted
var profile: Dictionary = {}
var rng := RandomNumberGenerator.new()
var abilities: Array = []            ## [{id, weight, when, def}]
var chantless := false               ## the profile passes the chantless gate
var last_cast := ""
var casts := 0
var chants_broken := 0

var _target: Variant = null


static func rows() -> Dictionary:
	if _rows.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH)) if FileAccess.file_exists(DATA_PATH) else null
		_rows = (parsed as Dictionary).get("casters", {}) if parsed is Dictionary else {}
	return _rows


static func try_acquire() -> bool:
	if active >= MAX_ACTIVE:
		return false
	active += 1
	return true


static func release() -> void:
	active = maxi(0, active - 1)


static func ids() -> Array:
	return rows().keys()


static func has(caster_id: String) -> bool:
	return rows().has(caster_id)


static func make(caster_id: String, seed_value := 1) -> RefCounted:
	var c: RefCounted = (load("res://scripts/combat/npc_caster.gd") as GDScript).new()
	c.setup(caster_id, seed_value)
	return c


func setup(caster_id: String, seed_value := 1) -> void:
	id = caster_id
	row = rows().get(caster_id, {})
	fighter = Fighter.make(String(row.get("fighter", "bandit")), seed_value, int(row.get("rank", -1)))
	rng.seed = seed_value * 7919 + 13
	profile = PowerTrees.npc_profile(row)
	runner = Runner.new()
	runner.costs_enabled = false
	runner.hooks = {"profile": func() -> Dictionary: return profile}
	abilities = []
	for a: Dictionary in row.get("abilities", []):
		var def := AbilityLib.get_def(String(a["id"]))
		if def.is_empty():
			continue
		abilities.append({"id": String(a["id"]), "weight": float(a.get("weight", 1.0)), "when": String(a.get("when", "attack")), "def": def})
	# What the NPC knows: its abilities and every prerequisite below them (so its own requirements hold).
	var known: Array = []
	var queue: Array = []
	for a: Dictionary in abilities:
		queue.append(String(a["id"]))
	while not queue.is_empty():
		var tid := String(queue.pop_back())
		if known.has(tid):
			continue
		known.append(tid)
		for q: Variant in (PowerTrees.technique(tid).get("req", {}) as Dictionary).get("prereq", []):
			queue.append(String(q))
	profile["known"] = known
	var path := String(row.get("path", "magic"))
	chantless = bool(PowerTrees.chantless_check(profile, path)["ok"]) if not PowerTrees.chantless_gate(path).is_empty() else false


func effects() -> EffectSet:
	return runner.effects


func is_casting() -> bool:
	return runner.is_casting()


## The ability's longest reach (self-targeted casts count as 0).
func reach_of(def: Dictionary) -> float:
	var t: Dictionary = def["targeting"]
	match String(t["kind"]):
		"self", "buff", "utility":
			return 0.0
		"aoe":
			return maxf(float(t["radius"]), 1.0)
		_:
			return float(t["range"])


## One think. ctx as NpcFighter.think plus: family_active (Array of the caster's active effect families, defaults to
## runner.effects.families()). -> {intent: "cast"|"kite"|"fight"|"hold", ability: String, fight: fighter decision}
func think(dt: float, ctx: Dictionary) -> Dictionary:
	var fight: Dictionary = fighter.think(dt, ctx)
	var out := {"intent": "fight", "ability": "", "fight": fight}
	if runner.is_casting():
		out["intent"] = "cast"
		return out
	if not bool(ctx.get("sees_target", true)):
		out["intent"] = "hold"
		return out
	var dist := float(ctx.get("dist", 99.0))
	var hp := float(ctx.get("own_hp_frac", 1.0))
	var tstate := String(ctx.get("target_state", "idle"))
	var fams: Array = ctx.get("family_active", runner.effects.families())
	var kite := float(row.get("kite_range", 0.0))
	var pick := _pick(dist, hp, tstate, fams)
	if pick != "" and rng.randf() < float(row.get("cast_bias", 0.8)):
		out["intent"] = "cast"
		out["ability"] = pick
		return out
	if kite > 0.0 and dist < kite:
		out["intent"] = "kite"
	return out


## Weighted choice among the abilities that are ready and make sense right now ("" = none).
func _pick(dist: float, hp: float, tstate: String, fams: Array) -> String:
	var total := 0.0
	var opts: Array = []
	for a: Dictionary in abilities:
		if not runner.ready(String(a["id"])):
			continue
		var def: Dictionary = a["def"]
		var reach := reach_of(def)
		var w := 0.0
		match String(a["when"]):
			"attack":
				if dist <= reach + 0.2 and dist >= 0.0:
					w = float(a["weight"])
					if tstate == "recovery" or tstate == "staggered":
						w *= 1.6
			"gap":
				if dist > 3.0 and dist <= reach:
					w = float(a["weight"])
			"guard":
				var fam := _family_of(def)
				if not fams.has(fam) and (tstate == "windup" or hp < 0.7):
					w = float(a["weight"]) * (2.0 if hp < 0.5 else 1.0)
			"heal":
				if hp < 0.6:
					w = float(a["weight"]) * (1.0 + (0.6 - hp) * 3.0)
			"buff":
				if not fams.has(_family_of(def)) and dist > 3.0:
					w = float(a["weight"]) * 3.0
		if w > 0.0:
			opts.append([String(a["id"]), w])
			total += w
	if total <= 0.0:
		return ""
	var roll := rng.randf() * total
	for o: Array in opts:
		roll -= float(o[1])
		if roll <= 0.0:
			return String(o[0])
	return String((opts[opts.size() - 1] as Array)[0])


static func _family_of(def: Dictionary) -> String:
	for e: Dictionary in (def["effects"] as Array):
		if String(e["target"]) == "self":
			return String(e["family"])
	return String(def["id"])


## Starts a cast. Chant is timed automatically (the profile decides if it is needed at all).
## -> the runner's begin() result.
func cast(ability_id: String, target: Variant = null) -> Dictionary:
	_target = target
	var def := AbilityLib.get_def(ability_id)
	var opts := {"auto_chant": true, "target": target}
	if AbilityDef.is_chant(def):
		opts["chantless"] = true
		opts["fallback_chant"] = true
	var r: Dictionary = runner.begin(ability_id, opts)
	if bool(r.get("ok", false)):
		last_cast = ability_id
		casts += 1
	return r


func update(dt: float) -> Array:
	return runner.update(dt)


## A blow landed (`pdmg` poise damage, `dmg` hit points, clock `now`). True when the fighter staggers; a stagger
## or a big enough blow breaks a chant.
func on_blow(pdmg: float, dmg: float, now: float) -> bool:
	var stag: bool = fighter.absorb(pdmg, now)
	var brk := float(row.get("chant_break", 10.0))
	if runner.phase == Runner.Phase.CHANT and (stag or (brk > 0.0 and dmg >= brk)):
		if runner.interrupt("broken"):
			chants_broken += 1
	elif stag and runner.phase == Runner.Phase.WINDUP:
		runner.interrupt("staggered")
	return stag


## Damage through the target caster's counters. -> {amount, absorbed}
func deal(amount: float, element := "") -> Dictionary:
	return runner.effects.mitigate(amount, element)


## Convenience for the arena/body: applies the executed ability's riders. `which` "self" puts them on this caster,
## "enemy" on `eset`. -> Runner.apply_effects result.
func apply(def: Dictionary, amount: int, eset: EffectSet, which := "enemy") -> Dictionary:
	return runner.apply_effects(def, amount, eset, which, 1.0, id)
