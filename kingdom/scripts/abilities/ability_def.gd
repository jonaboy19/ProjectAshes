extends RefCounted
## AbilityDef: one data row per technique, for every path (magic, bending, sect, knight, beast) and for the
## legacy skills.gd trees. Pure static helpers (no nodes), see docs/research/MINING_COMBAT_WORLD.md section 2.
##
## Shape of a normalised ability (a Dictionary):
##   id, name, desc, path, subpath, tree, tier, kind (active|passive), element
##   cast      {kind: instant|chant|channel|charge, seals: [...], chant_time, seal_optional, chantless_req, charge_time}
##   costs     {resource: amount}   resource: stamina | qi | magicules | bending | beast  (see RESOURCE_KEYS)
##   cooldown, lockout, windup (seconds from commit to resolve), recover
##   targeting {kind, range, radius, angle, max_targets, speed, count, spread, pierce, chains, chain_range,
##              hits, hit_interval, knockback}
##   damage    base direct damage (0 = none)
##   effects   [{type, family, rule, max_stacks, duration, magnitude, stats, target, ...}]  riders, see EffectSet
##   action    optional CombatAction id; vfx / anim / anims / anim_mode / anim_speed / audio roles
##   strain    channel strain per use (sect), `flat` = the skills.gd style flat dictionary the caster executes
##
## Legacy techniques are converted with from_technique() so the caster keeps its exact numbers (the original
## normalised technique is kept in `flat`). Path-tree rows (data/powers) are authored in the structured form and
## get a derived `flat` by normalise().

const PATHS := ["magic", "bending", "sect", "knight", "beast"]
const CAST_KINDS := ["instant", "chant", "channel", "charge"]
## Legacy shapes plus the design-doc kinds (self, target, line) so both vocabularies validate.
const TARGET_KINDS := ["melee", "projectile", "aoe", "target_aoe", "cone", "chain", "dash", "blink", "buff", "utility",
	"self", "target", "line", "command"]
const EFFECT_TYPES := ["dot", "hot", "slow", "stun", "fear", "blind", "pull", "reveal", "buff", "debuff", "ward", "absorb",
	"aura", "heal", "restore", "cultivate", "utility", "command", "summon", "damage"]
const STATUS_TYPES := ["stun", "slow", "fear", "blind", "pull", "reveal"]
const RULES := ["refresh", "replace_if_stronger", "stack"]
const RESOURCE_KEYS := ["stamina", "qi", "magicules", "bending", "beast"]
## Path -> resource its techniques may cost (stamina is always allowed for knights and as a fallback for melee arts).
const PATH_RESOURCES := {"magic": ["magicules"], "bending": ["bending"], "sect": ["qi", "stamina"],
	"knight": ["stamina"], "beast": ["beast", "stamina"]}
## power_paths.POOL name -> the actor resource that pays for it in-game.
const POOL_TO_RESOURCE := {"magic": "magicules", "sect": "qi", "knight": "stamina", "bending": "bending", "beast": "beast"}
const CAST_LOCK := 0.3
const SEAL_BONUS := 0.15
const BURN_DPS_RATIO := 0.08
const BURN_TICK := 0.5
const BURN_MAX_STACKS := 8
## Statuses and stats that only mean something to the actor that owns the effect.
const SELF_TYPES := ["buff", "ward", "absorb", "aura", "hot", "heal", "restore", "cultivate", "utility", "summon", "command"]
const DEFAULT_RULE := {"dot": "stack", "hot": "refresh", "slow": "replace_if_stronger", "stun": "refresh", "fear": "refresh",
	"blind": "refresh", "pull": "refresh", "reveal": "refresh", "buff": "refresh", "debuff": "replace_if_stronger",
	"ward": "replace_if_stronger", "absorb": "replace_if_stronger", "aura": "refresh"}
## Legacy tree -> power path when the technique's own resource does not decide it.
const TREE_PATHS := {"fire": "magic", "water": "magic", "wind": "magic", "earth": "magic", "lightning": "magic",
	"qi": "sect", "fist_palm": "sect", "swordsmanship": "knight"}


static func path_of_technique(t: Dictionary) -> String:
	var res := String(t.get("resource", "stamina"))
	if res == "magicules":
		return "magic"
	if res == "qi":
		return "sect"
	return String(TREE_PATHS.get(String(t.get("tree", "")), ""))


# --- legacy (skills.gd) -> AbilityDef --------------------------------------------

static func effects_from_legacy(id: String, fx: Dictionary) -> Array:
	var out: Array = []
	if fx.has("burn"):
		out.append({"type": "dot", "family": "burn", "target": "enemy", "duration": float(fx["burn"]),
			"dps_ratio": BURN_DPS_RATIO, "tick": BURN_TICK, "rule": "stack", "max_stacks": BURN_MAX_STACKS,
			"tags": ["fire"]})
	for s: String in STATUS_TYPES:
		if fx.has(s):
			out.append({"type": s, "family": s, "target": "enemy", "duration": float(fx[s]), "magnitude": 1.0,
				"rule": "refresh"})
	if fx.has("buff"):
		out.append({"type": "buff", "family": "buff:" + id, "target": "self", "duration": float(fx.get("duration", 6.0)),
			"stats": (fx["buff"] as Dictionary).duplicate(), "rule": "refresh"})
	if fx.has("heal"):
		out.append({"type": "heal", "target": "self", "magnitude": float(fx["heal"])})
	for r: String in ["stamina", "qi"]:
		if fx.has(r):
			out.append({"type": "restore", "target": "self", "resource": r, "magnitude": float(fx[r])})
	if fx.has("cultivate"):
		out.append({"type": "cultivate", "target": "self", "magnitude": float(fx["cultivate"])})
	for k: String in ["harvest", "repair", "water_crops"]:
		if fx.has(k):
			out.append({"type": "utility", "target": "self", "key": k, "magnitude": float(fx[k])})
	for e: Dictionary in out:
		if not e.has("family"):
			e["family"] = e["type"]
		if not e.has("rule"):
			e["rule"] = String(DEFAULT_RULE.get(String(e["type"]), "refresh"))
	return out


static func from_technique(t: Dictionary) -> Dictionary:
	var seals: Array = (t.get("seals", []) as Array).duplicate()
	var path := path_of_technique(t)
	var chant := not seals.is_empty() and path == "magic"
	var d := {
		"id": String(t["id"]), "name": String(t.get("name", t["id"])), "desc": String(t.get("desc", "")), "path": path,
		"subpath": String(t.get("tree", "")), "tree": String(t.get("tree", "")), "tier": int(t.get("tier", 1)),
		"kind": String(t.get("kind", "active")), "element": String(t.get("element", "qi")),
		"cast": {"kind": "chant" if chant else "instant", "seals": seals, "chant_time": 3.5 if chant else 0.0,
			"seal_optional": not chant and not seals.is_empty(), "chantless_req": "magic" if chant else "",
			"charge_time": 0.0},
		"costs": {String(t.get("resource", "stamina")): float(t.get("cost", 0.0))},
		"cooldown": float(t.get("cooldown", 1.0)), "lockout": CAST_LOCK, "windup": float(t.get("hit_time", 0.25)),
		"recover": 0.0,
		"targeting": {"kind": String(t.get("shape", "melee")), "range": float(t.get("range", 2.8)),
			"radius": float(t.get("radius", 0.0)), "angle": float(t.get("angle", 60.0)), "max_targets": 0,
			"speed": float(t.get("speed", 20.0)), "count": int(t.get("count", 1)), "spread": float(t.get("spread", 0.0)),
			"pierce": bool(t.get("pierce", false)), "chains": int(t.get("chains", 0)),
			"chain_range": float(t.get("chain_range", 6.0)), "hits": int(t.get("hits", 1)),
			"hit_interval": float(t.get("hit_interval", 0.15)), "knockback": float(t.get("knockback", 1.5))},
		"damage": int(t.get("damage", 0)),
		"effects": effects_from_legacy(String(t["id"]), t.get("effect", {})),
		"action": "", "vfx": String(t.get("vfx", "")), "anim": String(t.get("anim", "Spell_Simple_Shoot")),
		"anims": (t.get("anims", [t.get("anim", "Spell_Simple_Shoot")]) as Array).duplicate(),
		"anim_mode": String(t.get("anim_mode", "upper")), "anim_speed": float(t.get("anim_speed", 1.0)), "audio": "",
		"strain": 0.0, "passive": (t.get("passive", {}) as Dictionary).duplicate(),
		"source": "legacy", "flat": t.duplicate(true),
	}
	return d


# --- structured row -> normalised ----------------------------------------------------

static func normalise(row: Dictionary, defaults := {}) -> Dictionary:
	var d := row.duplicate(true)
	var element := String(d.get("element", defaults.get("element", "qi")))
	var cast := _merge({"kind": "instant", "seals": [], "chant_time": 0.0, "seal_optional": false, "chantless_req": "",
		"charge_time": 0.0}, d.get("cast", {}))
	var tgt := _merge({"kind": "melee", "range": 2.8, "radius": 0.0, "angle": 60.0, "max_targets": 0, "speed": 20.0,
		"count": 1, "spread": 0.0, "pierce": false, "chains": 0, "chain_range": 6.0, "hits": 1, "hit_interval": 0.15,
		"knockback": 1.5}, d.get("targeting", {}))
	var effects: Array = []
	var damage := int(d.get("damage", 0))
	for e: Variant in d.get("effects", []):
		var ef: Dictionary = (e as Dictionary).duplicate(true)
		var typ := String(ef.get("type", ""))
		if typ == "damage":
			damage += int(ef.get("magnitude", 0))
			continue
		if not ef.has("family"):
			ef["family"] = typ
		if not ef.has("rule"):
			ef["rule"] = String(DEFAULT_RULE.get(typ, "refresh"))
		if not ef.has("target"):
			ef["target"] = "self" if typ in SELF_TYPES else "enemy"
		effects.append(ef)
	d["cast"] = cast
	d["targeting"] = tgt
	d["effects"] = effects
	d["damage"] = damage
	d["id"] = String(d["id"])
	d["name"] = String(d.get("name", d["id"]))
	d["desc"] = String(d.get("desc", ""))
	d["path"] = String(d.get("path", defaults.get("path", "")))
	d["subpath"] = String(d.get("subpath", ""))
	d["tree"] = String(d.get("tree", d["path"]))
	d["tier"] = int(d.get("tier", 1))
	d["kind"] = String(d.get("kind", "active"))
	d["element"] = element
	d["costs"] = _floats(d.get("costs", {}))
	d["cooldown"] = float(d.get("cooldown", 1.0))
	d["lockout"] = float(d.get("lockout", CAST_LOCK))
	d["windup"] = float(d.get("windup", 0.25))
	d["recover"] = float(d.get("recover", 0.0))
	d["action"] = String(d.get("action", ""))
	d["vfx"] = String(d.get("vfx", ""))
	d["audio"] = String(d.get("audio", ""))
	d["strain"] = float(d.get("strain", 0.0))
	d["anim_mode"] = String(d.get("anim_mode", "upper"))
	d["anim_speed"] = float(d.get("anim_speed", 1.0))
	var anims: Array = []
	var a: Variant = d.get("anim", "Spell_Simple_Shoot")
	if a is Array:
		for c: Variant in a:
			anims.append(String(c))
	else:
		anims.append(String(a))
	d["anims"] = anims
	d["anim"] = anims[0] if not anims.is_empty() else "Spell_Simple_Shoot"
	d["passive"] = (d.get("passive", {}) as Dictionary).duplicate()
	d["source"] = String(d.get("source", "path"))
	d["flat"] = to_flat(d)
	return d


static func _merge(base: Dictionary, over: Variant) -> Dictionary:
	var out := base.duplicate(true)
	if over is Dictionary:
		for k: String in over:
			out[k] = (over[k] as Array).duplicate() if over[k] is Array else over[k]
	return out


static func _floats(src: Variant) -> Dictionary:
	var out := {}
	if src is Dictionary:
		for k: String in src:
			out[k] = float(src[k])
	return out


## The flat, skills.gd style dictionary the technique caster executes (resource, cost, shape, hit_time, effect...).
static func to_flat(d: Dictionary) -> Dictionary:
	var tg: Dictionary = d["targeting"]
	var cast: Dictionary = d["cast"]
	var res := "stamina"
	var cost := 0.0
	for k: String in (d["costs"] as Dictionary):
		res = String(POOL_TO_RESOURCE.get(k, k))
		cost = float(d["costs"][k])
		break
	var fx := {}
	for e: Dictionary in (d["effects"] as Array):
		match String(e["type"]):
			"dot":
				fx["burn"] = float(e.get("duration", 3.0))
			"slow", "stun", "fear", "blind", "pull", "reveal":
				fx[String(e["type"])] = float(e.get("duration", 1.0))
			"buff", "aura", "ward", "absorb":
				var stats: Dictionary = e.get("stats", {})
				if not stats.is_empty():
					fx["buff"] = stats.duplicate()
					fx["duration"] = float(e.get("duration", 6.0))
			"heal":
				fx["heal"] = float(e.get("magnitude", 0.0))
			"restore":
				fx[String(e.get("resource", "stamina"))] = float(e.get("magnitude", 0.0))
			"cultivate":
				fx["cultivate"] = float(e.get("magnitude", 0.0))
			"utility":
				fx[String(e.get("key", "utility"))] = float(e.get("magnitude", 0.0))
	# Design-doc kinds the legacy resolver does not know map onto its shapes.
	var shape := String({"self": "buff", "command": "utility", "target": "target_aoe", "line": "cone"}.get(String(tg["kind"]), String(tg["kind"])))
	return {
		"id": d["id"], "name": d["name"], "desc": d["desc"], "kind": d["kind"], "tree": d["tree"], "tier": d["tier"],
		"col": 0, "points": 1, "max_rank": 1, "requires": [], "needs": {}, "hidden": false,
		"resource": res, "cost": cost, "cooldown": float(d["cooldown"]), "damage": int(d["damage"]), "shape": shape,
		"range": float(tg["range"]), "radius": float(tg["radius"]), "angle": float(tg["angle"]), "speed": float(tg["speed"]),
		"knockback": float(tg["knockback"]), "hits": int(tg["hits"]), "hit_interval": float(tg["hit_interval"]),
		"hit_time": float(d["windup"]), "count": int(tg["count"]), "spread": float(tg["spread"]), "chains": int(tg["chains"]),
		"chain_range": float(tg["chain_range"]), "pierce": bool(tg["pierce"]), "effect": fx, "passive": d.get("passive", {}),
		"anim": d.get("anim", "Spell_Simple_Shoot"), "anims": (d.get("anims", []) as Array).duplicate(),
		"anim_mode": d["anim_mode"], "anim_speed": float(d["anim_speed"]), "vfx": d["vfx"], "element": d["element"],
		"seals": (cast["seals"] as Array).duplicate(),
	}


## The flat dictionary of any normalised ability.
static func flat(d: Dictionary) -> Dictionary:
	return d.get("flat", {})


static func primary_cost(d: Dictionary) -> Dictionary:
	for k: String in (d.get("costs", {}) as Dictionary):
		return {"resource": k, "amount": float(d["costs"][k])}
	return {"resource": "", "amount": 0.0}


static func is_chant(d: Dictionary) -> bool:
	return String((d.get("cast", {}) as Dictionary).get("kind", "instant")) == "chant"


## Data problems as readable strings (empty = sound).
static func validate(d: Dictionary) -> Array[String]:
	var errs: Array[String] = []
	var id := String(d.get("id", "?"))
	var path := String(d.get("path", ""))
	if path != "" and not PATHS.has(path):
		errs.append("%s has unknown path %s" % [id, path])
	if String(d.get("kind", "active")) != "active":
		return errs
	var cast: Dictionary = d["cast"]
	if not String(cast["kind"]) in CAST_KINDS:
		errs.append("%s has unknown cast kind %s" % [id, cast["kind"]])
	if String(cast["kind"]) == "chant" and (cast["seals"] as Array).is_empty() and float(cast["chant_time"]) <= 0.0:
		errs.append("%s is a chant without seals or chant_time" % id)
	if not String((d["targeting"] as Dictionary)["kind"]) in TARGET_KINDS:
		errs.append("%s has unknown targeting kind %s" % [id, (d["targeting"] as Dictionary)["kind"]])
	for r: String in (d["costs"] as Dictionary):
		if not r in RESOURCE_KEYS:
			errs.append("%s has unknown resource %s" % [id, r])
		elif d["source"] != "legacy" and PATH_RESOURCES.has(path) and not r in (PATH_RESOURCES[path] as Array):
			errs.append("%s (%s) may not cost %s" % [id, path, r])
	if float(d["cooldown"]) <= 0.0:
		errs.append("%s has no cooldown" % id)
	elif d["source"] != "legacy" and float(d["cooldown"]) + 0.001 < float(d["windup"]) + float(d["recover"]):
		errs.append("%s cooldown is shorter than windup + recover" % id)
	for e: Dictionary in (d["effects"] as Array):
		if not String(e["type"]) in EFFECT_TYPES:
			errs.append("%s has unknown effect type %s" % [id, e["type"]])
		if not String(e["rule"]) in RULES:
			errs.append("%s has unknown stacking rule %s" % [id, e["rule"]])
	return errs
