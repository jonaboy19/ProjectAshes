extends "res://scripts/realm/realm_module.gd"
## C§32-38 power paths: five paths with different resource models and limits.
##   magic    mana pool (wraps Life.magicules when ctx.life is given); exhausted casting
##            risks headaches, trembling, instability.
##   bending  elemental resonance; breath rhythm, stance quality, environment access
##            (water near rivers vs desert), leg/arm injuries change forms.
##   sect     internal energy; channel strain builds with use and injures muscle, joint
##            or channels; mastery reduces strain.
##   knight   stamina + trained reinforcement; armour load, conditioning; stays effective
##            (unreinforced) with empty energy.
##   beast    bond synchronisation; per-creature trust and a mental burden.
## Cross-training slows xp per extra path; prodigy only via unlock_prodigy() and never
## in ctx.region == "valencios_first" (a missing region is treated as the first region).
##
## ctx keys read (all optional): life, near_water, biome, element, injuries (Array of
## type strings), stance 0..1, complexity 0..1, concentration 0..1, armour_load 0..1,
## creature (id), region, abs_hours.
## Player hooks: call can_use() to show risk/reason, then use() when a skill fires.
##
## Power-tree layer (data/powers/*.json via scripts/abilities/power_trees.gd): per path milestones, spell-theory,
## sub-paths, learned manuals/teachers/techniques and per-technique mastery. Rules enforced here, not only in UI:
##   - chantless casting (ctx.chantless on the magic path): can_use refuses unless the advanced gate is met
##     (path level + spell-theory + milestones + cultivation realm), see chantless_ready();
##   - a second path is very hard to learn: can_learn()/learn_checked() apply PowerTrees.second_path_gate, and
##     ctx.path_penalty = true makes can_use/use scale power and cost by the path's rank (second path 0.75 power,
##     1.25 cost; third 0.55 / 1.5). Meditation speed for extra paths lives in cultivation.cross_step.

const PowerTrees := preload("res://scripts/abilities/power_trees.gd")
const PATHS := ["magic", "bending", "sect", "knight", "beast"]
const SOURCES := {"academy": 1.0, "teacher": 0.9, "manual": 0.7, "self": 0.5}
const FIRST_REGION := "valencios_first"
const PRODIGY_REASONS := ["ancient_technique", "rift_exposure", "unusual_ancestry", "exceptional_mentor", "extreme_training", "unique_experience"]
const CROSS_STEP := 0.6
const CROSS_MIN := 0.15
const XP_PER_LEVEL := 50.0
const MAX_LEVEL := 30
const OVERDRAW := 0.5
## path -> [base max, per level max, recover per hour]
const POOL := {
	"magic": [30.0, 4.0, 1.5], "bending": [40.0, 3.0, 2.0], "sect": [40.0, 4.0, 1.0],
	"knight": [60.0, 2.0, 5.0], "beast": [30.0, 3.0, 1.2],
}
const LEG_INJ := ["broken_leg", "sprained_ankle", "torn_leg_muscle"]
const ARM_INJ := ["broken_arm", "sprained_wrist"]
const SELF_HEAL_DAYS := 5

## path -> {src, xp, cur, exh, strain, breath, cond, burden, element, trust:{}}
var _p: Dictionary = {}
var _prodigy: Array = []
var _manuals: Array = []       # manuals read (power trees; cultivation keeps its own list)
var _teachers: Array = []      # teacher ids that have taught you
var _known: Array = []         # learned power-tree technique ids
var _primary := ""
var _own_inj: Array = []      # [{type, day}] used when no ctx.life
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.seed = 90210


# --------------------------------------------------------------- learning

func paths() -> Array:
	var out: Array = []
	for k: String in PATHS:
		if _p.has(k):
			out.append(k)
	return out


func knows(path: String) -> bool:
	return _p.has(path)


func learn(path: String, source: String) -> bool:
	if not PATHS.has(path) or not SOURCES.has(source) or _p.has(path):
		return false
	_p[path] = {"src": source, "xp": 0.0, "cur": 0.0, "exh": 0.0, "strain": 0.0, "breath": 0.7,
		"cond": 0.3, "burden": 0.0, "element": "water", "trust": {}, "theory": 0.0, "milestones": [], "subpaths": [],
		"uses": {}}
	_p[path]["cur"] = max_of(path)
	if _primary == "":
		_primary = path
	return true


func level(path: String) -> int:
	if not _p.has(path):
		return 0
	return mini(MAX_LEVEL, 1 + int(float(_p[path]["xp"]) / XP_PER_LEVEL))


func xp_multiplier(path: String) -> float:
	if not _p.has(path):
		return 0.0
	var n := _p.size()
	var cross := maxf(CROSS_MIN, pow(CROSS_STEP, n - 1))
	if not _prodigy.is_empty():
		cross = maxf(cross, 0.8)
	return cross * float(SOURCES[_p[path]["src"]])


func gain_xp(path: String, amount: float) -> float:
	if not _p.has(path):
		return 0.0
	var before := max_of(path)
	var got := amount * xp_multiplier(path)
	_p[path]["xp"] = float(_p[path]["xp"]) + got
	_p[path]["cur"] = float(_p[path]["cur"]) + (max_of(path) - before)
	return got


func unlock_prodigy(reason: String, ctx: Dictionary = {}) -> bool:
	if not PRODIGY_REASONS.has(reason) or _prodigy.has(reason):
		return false
	if String(ctx.get("region", FIRST_REGION)) == FIRST_REGION:
		return false
	_prodigy.append(reason)
	return true


func is_prodigy() -> bool:
	return not _prodigy.is_empty()


func prodigy_reasons() -> Array:
	return _prodigy.duplicate()


func set_element(element: String) -> void:
	if _p.has("bending"):
		_p["bending"]["element"] = element


# --------------------------------------------------------------- power trees

func primary_path() -> String:
	return _primary


func set_primary(path: String) -> bool:
	if not _p.has(path):
		return false
	_primary = path
	return true


## Spell-theory mastery 0..1 (study, academy lessons, treatises). Gates chantless casting and advanced spells.
func theory(path: String) -> float:
	return float(_p[path].get("theory", 0.0)) if _p.has(path) else 0.0


func study_theory(path: String, amount: float) -> float:
	if not _p.has(path):
		return 0.0
	_p[path]["theory"] = clampf(float(_p[path].get("theory", 0.0)) + amount, 0.0, 1.0)
	return float(_p[path]["theory"])


func milestones(path: String) -> Array:
	return (_p[path].get("milestones", []) as Array).duplicate() if _p.has(path) else []


func add_milestone(path: String, id: String) -> bool:
	if not _p.has(path) or (_p[path]["milestones"] as Array).has(id):
		return false
	(_p[path]["milestones"] as Array).append(id)
	return true


func subpaths(path: String) -> Array:
	return (_p[path].get("subpaths", []) as Array).duplicate() if _p.has(path) else []


## Follow a sub-path (an element, a school, a line). Limited by the realm's slot count.
func choose_subpath(path: String, id: String, realm := 1) -> bool:
	if not _p.has(path):
		return false
	var ok := false
	for s: Dictionary in PowerTrees.subpaths(path):
		if s["id"] == id:
			ok = true
	var chosen: Array = _p[path]["subpaths"]
	if not ok or chosen.has(id) or chosen.size() >= PowerTrees.subpath_slots(path, realm):
		return false
	chosen.append(id)
	if path == "bending":
		if chosen.size() == 1 and id in ["air", "fire", "earth", "water"]:
			_p["bending"]["element"] = id
	return true


func manuals() -> Array:
	return _manuals.duplicate()


## Read a power-tree manual. `ctx.realms` ({path: realm}) may enforce the "within one realm" rule like cultivation.
func learn_manual(id: String, ctx: Dictionary = {}) -> Dictionary:
	var m := PowerTrees.manual(id)
	if m.is_empty():
		return {"ok": false, "reason": "unknown"}
	if _manuals.has(id):
		return {"ok": false, "reason": "known"}
	var path := String(m["path"])
	if not _p.has(path):
		return {"ok": false, "reason": "not_cultivating"}
	var realms: Dictionary = ctx.get("realms", {})
	if realms.has(path) and int(realms[path]) < int(m["realm"]) - 1:
		return {"ok": false, "reason": "too_advanced"}
	_manuals.append(id)
	return {"ok": true, "reason": ""}


func teachers() -> Array:
	return _teachers.duplicate()


func add_teacher(id: String) -> bool:
	if _teachers.has(id):
		return false
	_teachers.append(id)
	return true


func known_techniques() -> Array:
	return _known.duplicate()


func knows_technique(id: String) -> bool:
	return _known.has(id)


## Per-technique mastery 0..1 from use (the first 40 uses reach 100 percent).
func technique_mastery(id: String) -> float:
	var path := PowerTrees.path_of(id)
	if path == "" or not _p.has(path):
		return 0.0
	return clampf(float((_p[path].get("uses", {}) as Dictionary).get(id, 0)) / 40.0, 0.0, 1.0)


func path_order(path: String) -> int:
	return PowerTrees.path_order(PowerTrees.profile_from(self), path)


func path_penalty(path: String) -> Dictionary:
	return PowerTrees.path_penalty(path_order(path)) if _p.has(path) else {"power": 0.0, "cost": 1.0, "xp": 0.0}


## The power-tree profile of this character (cultivation from the hub when present; `extra` overrides keys).
func profile(extra: Dictionary = {}) -> Dictionary:
	var cult: Variant = hub.mod("cultivation") if hub != null and hub.get("mods") is Dictionary and (hub.get("mods") as Dictionary).has("cultivation") else null
	return PowerTrees.profile_from(self, cult, extra)


## Chantless casting open to this character? -> PowerTrees.chantless_check
func chantless_ready(ctx: Dictionary = {}) -> Dictionary:
	return PowerTrees.chantless_check(ctx["profile"] if ctx.has("profile") else profile(ctx.get("profile_extra", {})), "magic")


## Learn a power-tree technique if every requirement is met. -> {ok, reasons}
func learn_technique(id: String, extra: Dictionary = {}) -> Dictionary:
	var st := PowerTrees.state(id, profile(extra))
	if st["state"] == "known":
		return {"ok": false, "reasons": ["Already known."]}
	if st["state"] != "ready":
		return {"ok": false, "reasons": st["reasons"]}
	_known.append(id)
	return {"ok": true, "reasons": []}


## Second and third paths are very hard to learn (PowerTrees.second_path_gate); the first path is free.
func can_learn(path: String, source: String, extra: Dictionary = {}) -> Dictionary:
	if not PATHS.has(path) or not SOURCES.has(source):
		return {"ok": false, "reasons": ["Unknown path or source."]}
	return PowerTrees.second_path_gate(profile(extra), path, source)


func learn_checked(path: String, source: String, extra: Dictionary = {}) -> Dictionary:
	var g := can_learn(path, source, extra)
	if bool(g["ok"]) and learn(path, source):
		return g
	if bool(g["ok"]):
		g["ok"] = false
		g["reasons"] = ["Could not learn."]
	return g


# --------------------------------------------------------------- resources

func max_of(path: String) -> float:
	var b: Array = POOL[path]
	var m := float(b[0]) + float(b[1]) * (level(path) - 1)
	if path == "sect":
		m *= 1.0
	return m


func _mag(ctx: Dictionary) -> Variant:
	var life: Variant = ctx.get("life")
	if life != null and life.get("magicules") != null:
		return life.magicules
	return null


func resource(path: String, ctx: Dictionary = {}) -> Dictionary:
	if not _p.has(path):
		return {"cur": 0.0, "max": 0.0}
	if path == "magic":
		var mg: Variant = _mag(ctx)
		if mg != null:
			return {"cur": mg.current, "max": mg.effective_max()}
	return {"cur": float(_p[path]["cur"]), "max": max_of(path)}


func _exhaustion(path: String, ctx: Dictionary) -> float:
	if path == "magic":
		var mg: Variant = _mag(ctx)
		if mg != null:
			return mg.exhaustion
	return float(_p[path]["exh"])


func strain(path: String) -> float:
	return float(_p[path]["strain"]) if _p.has(path) else 0.0


func burden() -> float:
	return float(_p["beast"]["burden"]) if _p.has("beast") else 0.0


func trust(creature: String) -> float:
	if not _p.has("beast"):
		return 0.0
	return float((_p["beast"]["trust"] as Dictionary).get(creature, 0.3))


func add_trust(creature: String, delta: float) -> float:
	if not _p.has("beast"):
		return 0.0
	var t := clampf(trust(creature) + delta, 0.0, 1.0)
	_p["beast"]["trust"][creature] = t
	return t


func mastery(path: String) -> float:
	return minf(0.6, float(level(path) - 1) * 0.04)


# --------------------------------------------------------------- injuries

func active_injuries(ctx: Dictionary = {}) -> Array:
	var out: Array = []
	for t: Variant in ctx.get("injuries", []):
		out.append(String(t))
	var life: Variant = ctx.get("life")
	if life != null and life.get("injuries") != null:
		for inj: Dictionary in life.injuries.active:
			out.append(String(inj["type"]))
	for e: Dictionary in _own_inj:
		out.append(String(e["type"]))
	return out


func _hurt(type: String, ctx: Dictionary) -> void:
	var day := int(ctx.get("abs_hours", 0)) / 24
	var life: Variant = ctx.get("life")
	if life != null and life.get("injuries") != null and RAInjuries.TYPES.has(type):
		if not life.injuries.has(type):
			life.injuries.add(type, day)
			if life.get("magicules") != null:
				life.magicules.apply_effects(life.injuries.effects())
		return
	for e: Dictionary in _own_inj:
		if e["type"] == type:
			return
	_own_inj.append({"type": type, "day": day})


func tick_day(day: int, _ctx: Dictionary) -> Array:
	var keep: Array = []
	var out: Array = []
	for e: Dictionary in _own_inj:
		if day - int(e["day"]) >= SELF_HEAL_DAYS:
			out.append("Your %s has healed." % String(e["type"]).replace("_", " "))
		else:
			keep.append(e)
	_own_inj = keep
	return out


# --------------------------------------------------------------- environment

func environment_factor(path: String, ctx: Dictionary = {}) -> float:
	if path != "bending" or not _p.has("bending"):
		return 1.0
	var el: String = String(ctx.get("element", _p["bending"]["element"]))
	var water: bool = bool(ctx.get("near_water", false))
	var biome := String(ctx.get("biome", ""))
	var f := 1.0
	match el:
		"water":
			if water:
				f = 1.2
			elif biome == "desert":
				f = 0.45
			elif biome == "":
				f = 1.0
			else:
				f = 0.9
		"fire":
			f = 1.15 if biome == "desert" else (0.85 if water else 1.0)
		"air":
			f = 1.1 if biome == "mountain" else 1.0
	var inj := active_injuries(ctx)
	for t: String in inj:
		if LEG_INJ.has(t):
			f *= 0.5 if el == "earth" else 0.85
		elif ARM_INJ.has(t):
			f *= 0.6 if el == "water" else 0.85
	return f


func _forms(ctx: Dictionary) -> Array:
	var el := String(ctx.get("element", _p["bending"]["element"] if _p.has("bending") else "water"))
	var out: Array = []
	for t: String in active_injuries(ctx):
		if LEG_INJ.has(t) and el == "earth":
			out.append("seated_forms_only")
		elif ARM_INJ.has(t) and el == "water":
			out.append("one_handed_forms")
	return out


# --------------------------------------------------------------- assess / use

## {ok, risk 0..1, reason, cost (effective), power 0..1+}
func _assess(path: String, cost: float, ctx: Dictionary) -> Dictionary:
	if not _p.has(path):
		return {"ok": false, "risk": 0.0, "reason": "You have not learned this path.", "cost": cost, "power": 0.0}
	var s: Dictionary = _p[path]
	var res := resource(path, ctx)
	var cur: float = res["cur"]
	var mx: float = res["max"]
	var cx := clampf(float(ctx.get("complexity", 0.3)), 0.0, 1.0)
	var conc := clampf(float(ctx.get("concentration", 1.0)), 0.0, 1.0)
	var out := {"ok": true, "risk": 0.0, "reason": "", "cost": cost, "power": 1.0}
	var rule := _rules(path, ctx)
	if not rule.is_empty():
		out["ok"] = false
		out["reason"] = rule["reason"]
		return out
	var pen := {"power": 1.0, "cost": 1.0}
	if bool(ctx.get("path_penalty", false)):
		pen = path_penalty(path)
		cost *= float(pen["cost"])
		out["cost"] = cost
	match path:
		"magic":
			var exh := _exhaustion("magic", ctx)
			var mg: Variant = _mag(ctx)
			var spendable: float = mg.spendable() if mg != null else cur + mx * OVERDRAW
			var exhausted: bool = (mg.is_exhausted() if mg != null else (exh >= 0.5 or cur < 0.0)) or cur < cost
			if cost > spendable:
				out["ok"] = false
				out["reason"] = "Not enough mana, even overdrawn."
			elif exhausted:
				out["risk"] = 0.25 + exh * 0.5 + cx * 0.2 + (1.0 - conc) * 0.3
				out["reason"] = "Casting while exhausted: headaches, trembling, instability."
			else:
				out["risk"] = cx * 0.05 + (1.0 - conc) * 0.2
			out["power"] = 1.0 - exh * 0.4
		"bending":
			var env := environment_factor(path, ctx)
			var stance := clampf(float(ctx.get("stance", 0.7)), 0.0, 1.0)
			var eff := maxf(0.15, env * (0.5 + 0.5 * float(s["breath"])) * (0.5 + 0.5 * stance))
			out["cost"] = cost / eff
			out["power"] = eff
			if out["cost"] > cur:
				out["ok"] = false
				out["reason"] = "Resonance too thin (poor breath, stance or place)."
			elif env < 0.7:
				out["reason"] = "The surroundings resist this element."
			out["risk"] = (1.0 - eff) * 0.25
		"sect":
			var st := float(s["strain"])
			out["cost"] = cost
			if cost > cur:
				out["ok"] = false
				out["reason"] = "Internal energy is spent."
			elif st > 0.5:
				out["reason"] = "Channels are strained."
			out["risk"] = clampf((st - 0.4) * 1.2 * (1.0 - mastery(path)) + cx * 0.03, 0.0, 0.95)
			out["power"] = 1.0 - st * 0.3
		"knight":
			var arm := clampf(float(ctx.get("armour_load", 0.0)), 0.0, 1.0)
			var cond := float(s["cond"])
			var real := cost * (1.0 + arm * (1.0 - cond * 0.5))
			out["cost"] = real
			out["power"] = (1.0 if cur >= real else 0.6) * (0.7 + 0.3 * cond) * (1.0 - arm * 0.2 * (1.0 - cond))
			if cur < real:
				out["reason"] = "Running on bare conditioning."
			out["risk"] = 0.0 if cur >= real else clampf(0.1 + (1.0 - cond) * 0.2, 0.0, 0.5)
		"beast":
			var cr := String(ctx.get("creature", ""))
			var tr := trust(cr)
			var b := float(s["burden"])
			out["cost"] = cost * (1.5 - tr * 0.7)
			if tr < 0.2:
				out["ok"] = false
				out["reason"] = "The creature does not trust you."
			elif out["cost"] > cur:
				out["ok"] = false
				out["reason"] = "The bond is too thin."
			elif b > 0.6:
				out["reason"] = "Your mind is overburdened."
			out["risk"] = clampf((1.0 - tr) * 0.2 + maxf(0.0, b - 0.5) * 0.8, 0.0, 0.95)
			out["power"] = (0.4 + 0.6 * tr) * (1.0 - b * 0.3)
	out["power"] = float(out["power"]) * float(pen["power"])
	out["risk"] = clampf(float(out["risk"]), 0.0, 0.95)
	return out


func can_use(path: String, cost: float, ctx: Dictionary = {}) -> Dictionary:
	var a := _assess(path, cost, ctx)
	return {"ok": a["ok"], "risk": a["risk"], "reason": a["reason"]}


## Path rules shared by can_use and use: chantless gate, second-path penalty. Returns {} when nothing applies.
func _rules(path: String, ctx: Dictionary) -> Dictionary:
	if bool(ctx.get("chantless", false)) and path == "magic" and _p.has("magic"):
		var c := chantless_ready(ctx)
		if not bool(c["ok"]):
			return {"ok": false, "reason": "Chantless casting is beyond you: %s" % " ".join(PackedStringArray(c["reasons"]))}
	return {}


func use(path: String, cost: float, ctx: Dictionary = {}) -> Dictionary:
	var a := _assess(path, cost, ctx)
	var effects: Array = []
	var msgs: Array = []
	if not a["ok"]:
		return {"ok": false, "effects": effects, "messages": [a["reason"]], "power": 0.0, "risk": a["risk"]}
	var s: Dictionary = _p[path]
	var roll := _rng.randf()
	var hit: bool = roll < float(a["risk"])
	var c: float = a["cost"]
	match path:
		"magic":
			var exhausted: bool = String(a["reason"]) != ""
			var mg: Variant = _mag(ctx)
			if mg != null:
				var r: Dictionary = mg.spend(c)
				if float(r["damage"]) > 0:
					effects.append({"type": "damage", "amount": int(r["damage"])})
				if String(r["text"]) != "":
					msgs.append(r["text"])
			else:
				var before_debt := maxf(0.0, -float(s["cur"]))
				s["cur"] = float(s["cur"]) - c
				var over := maxf(0.0, -float(s["cur"])) - before_debt
				if over > 0.0:
					s["exh"] = clampf(float(s["exh"]) + over / max_of(path) * 2.0, 0.0, 1.0)
			if hit and exhausted:
				var k := _rng.randi() % 3
				if k == 0:
					effects.append({"type": "headache", "concentration": -0.3})
					msgs.append("A headache splits your focus.")
				elif k == 1:
					effects.append({"type": "trembling", "accuracy": -0.25})
					msgs.append("Your hands tremble.")
				else:
					effects.append({"type": "instability", "power": 0.5})
					msgs.append("The spell destabilises.")
					_hurt("magicule_burn", ctx)
			elif hit:
				effects.append({"type": "concentration_slip", "power": 0.7})
				msgs.append("Your concentration slips.")
		"bending":
			s["cur"] = float(s["cur"]) - c
			s["breath"] = clampf(float(s["breath"]) - 0.03 - cost / max_of(path) * 0.1, 0.2, 1.0)
			for f: String in _forms(ctx):
				effects.append({"type": "form_change", "form": f})
			if float(a["power"]) < 0.5:
				msgs.append("The element answers weakly here.")
			if hit:
				effects.append({"type": "rhythm_break", "power": 0.7})
				msgs.append("Your breathing breaks rhythm.")
		"sect":
			s["cur"] = float(s["cur"]) - c
			s["strain"] = clampf(float(s["strain"]) + c / max_of(path) * 1.2 * (1.0 - mastery(path)), 0.0, 1.0)
			if hit:
				var kinds := ["bruised_ribs", "broken_arm", "torn_meridian"]
				var inj: String = kinds[_rng.randi() % kinds.size()]
				if inj == "broken_arm" and float(s["strain"]) < 0.8:
					inj = "bruised_ribs"
				_hurt(inj, ctx)
				effects.append({"type": "injury", "injury": inj})
				msgs.append("Strain tears something (%s)." % inj.replace("_", " "))
		"knight":
			var had := float(s["cur"])
			s["cur"] = maxf(0.0, had - c)
			s["cond"] = clampf(float(s["cond"]) + 0.002 * (1.0 + float(level(path)) * 0.05), 0.0, 1.0)
			if had < c:
				effects.append({"type": "unreinforced"})
				msgs.append("Reinforcement fails; you fight on muscle alone.")
			if hit:
				effects.append({"type": "winded", "stamina": -0.2})
		"beast":
			s["cur"] = float(s["cur"]) - c
			s["burden"] = clampf(float(s["burden"]) + c / max_of(path) * 0.4, 0.0, 1.0)
			add_trust(String(ctx.get("creature", "")), 0.01)
			if hit:
				effects.append({"type": "mental_strain", "concentration": -0.3})
				msgs.append("The link floods your mind.")
	s["cur"] = maxf(float(s["cur"]), -max_of(path) * OVERDRAW)
	var tech := String(ctx.get("technique", ""))
	if tech != "":
		var uses: Dictionary = s["uses"]
		uses[tech] = int(uses.get(tech, 0)) + 1
	gain_xp(path, 1.0 + c * 0.1)
	return {"ok": true, "effects": effects, "messages": msgs, "power": a["power"], "risk": a["risk"]}


# --------------------------------------------------------------- recovery

func _recover(hours: float, ctx: Dictionary, mult: float) -> void:
	for k: String in _p.keys():
		var s: Dictionary = _p[k]
		var mx := max_of(k)
		var h := hours * mult
		s["exh"] = maxf(0.0, float(s["exh"]) - 0.04 * h)
		s["strain"] = maxf(0.0, float(s["strain"]) - 0.03 * h)
		s["breath"] = minf(1.0, float(s["breath"]) + 0.03 * h)
		s["burden"] = maxf(0.0, float(s["burden"]) - 0.02 * h)
		if k == "magic" and _mag(ctx) != null:
			continue  # Life regenerates its own magicules
		var rate: float = float(POOL[k][2]) * (1.0 - float(s["exh"]) * 0.75)
		if k == "sect":
			rate *= 1.0 - float(s["strain"]) * 0.5
		s["cur"] = minf(mx, float(s["cur"]) + maxf(0.0, rate) * h)


func tick_hour(_hour: int, ctx: Dictionary) -> Array:
	_recover(1.0, ctx, 1.0)
	return []


## Resting recovers faster; also tops up a linked Life.magicules.
func rest(hours: float, ctx: Dictionary = {}) -> void:
	_recover(hours, ctx, 1.5)
	var mg: Variant = _mag(ctx)
	if mg != null and _p.has("magic"):
		mg.regenerate(hours)


func catch_up(days: int, ctx: Dictionary) -> Array:
	_recover(float(days) * 24.0, ctx, 1.0)
	return []


# --------------------------------------------------------------- save

func serialize() -> Dictionary:
	var ps := {}
	for k: String in _p:
		ps[k] = (_p[k] as Dictionary).duplicate(true)
	return {"p": ps, "prodigy": _prodigy.duplicate(), "inj": _own_inj.duplicate(true), "rng": str(_rng.state),
		"manuals": _manuals.duplicate(), "teachers": _teachers.duplicate(), "known": _known.duplicate(), "primary": _primary}


func deserialize(d: Dictionary) -> void:
	_p.clear()
	var ps: Dictionary = d.get("p", {})
	for k: String in ps:
		if not PATHS.has(k):
			continue
		var s: Dictionary = (ps[k] as Dictionary).duplicate(true)
		for f: String in ["xp", "cur", "exh", "strain", "breath", "cond", "burden"]:
			s[f] = float(s.get(f, 0.0))
		s["theory"] = float(s.get("theory", 0.0))
		s["milestones"] = (s.get("milestones", []) as Array).duplicate()
		s["subpaths"] = (s.get("subpaths", []) as Array).duplicate()
		var u: Dictionary = {}
		for tk: String in (s.get("uses", {}) as Dictionary):
			u[tk] = int(s["uses"][tk])
		s["uses"] = u
		s["src"] = String(s.get("src", "self"))
		s["element"] = String(s.get("element", "water"))
		if not (s.get("trust") is Dictionary):
			s["trust"] = {}
		_p[k] = s
	_prodigy = (d.get("prodigy", []) as Array).duplicate()
	_manuals = (d.get("manuals", []) as Array).duplicate()
	_teachers = (d.get("teachers", []) as Array).duplicate()
	_known = (d.get("known", []) as Array).duplicate()
	_primary = String(d.get("primary", ""))
	if _primary == "" or not _p.has(_primary):
		_primary = (_p.keys()[0] if not _p.is_empty() else "")
	_own_inj.clear()
	for e: Dictionary in d.get("inj", []):
		_own_inj.append({"type": String(e["type"]), "day": int(e["day"])})
	if d.has("rng"):
		_rng.state = String(d["rng"]).to_int()
