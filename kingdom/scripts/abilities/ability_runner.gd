extends RefCounted
## AbilityRunner: ONE lifecycle for every ability, used by the player's technique caster and by NPC casters
## (docs/research/MINING_COMBAT_WORLD.md section 2; Ryzom evaluate -> validate -> update -> launch -> execute -> apply):
##
##   evaluate(id, opts)  look the ability up, work out its numbers, path gate, chant requirement (no side effects)
##   validate(ev, opts)  blocked / busy / not learned / cooldown / resources / chantless gate -> {ok, reason}
##   begin(id, opts)     evaluate + validate, then either a CHANT phase (seal pad or timed chant) or commit at once
##   chant_complete(ok)  the chant finished (or broke): commit, or fizzle with a short cooldown
##   commit              pay costs (on release, never while chanting), start the cooldown, enter WINDUP
##   update(dt)          advance chant / windup / recover; at the end of WINDUP the `execute` hook resolves it
##   apply_effects()     put an ability's riders (burn, stun, ward...) onto an EffectSet by family and stacking rule
##   interrupt()         break a chant (fizzle) or a windup (half the cost back, no effect)
##
## The runner never touches scenes. The host plugs in `hooks` (all optional, Callables):
##   lookup(id) -> def            default: AbilityLib.get_def
##   known(id) -> bool            default: true
##   blocked() -> String          "" when the actor may cast
##   pools(def) -> {resource: n}  what the actor can pay for this ability (the def argument is optional;
##                                ignored when costs_enabled is false)
##   pay(resource, amount)        pay one cost (default: nothing)
##   refund(resource, amount)
##   numbers(id, def) -> {costs, cooldown, damage}   overrides the numbers (the player uses skills.gd ranks/passives);
##                                {} keeps the defaults
##   commit(id, def, sealed, numbers, opts) -> {ok, reason, resource, cost, cooldown, damage}   replaces pay + cooldown
##                                (legacy skills.gd begin_cast, power_paths.use); {default: true} falls back to the default
##   fizzle(id, seconds)          a broken chant's rest period (default: set_cooldown)
##   cooldown_left(id) / cooldown_set(id, seconds)   default: the runner's own `cooldowns`
##   gate(def, opts) -> {ok, reason, power, cost_mult}  path rules (second-path penalty, injuries...)
##   chantless(def) -> {ok, reason}                  default: PowerTrees.chantless_check(profile()) when profile is set
##   profile() -> Dictionary                         the actor's power profile (PowerTrees format)
##   execute(def, cast)                              resolve: targeting query, damage, apply_effects (the scene part)
## NPCs set costs_enabled = false: abilities cost cooldown only (ashes-ability-system).

signal started(id: String, ability: Dictionary)
signal chant_started(id: String, info: Dictionary)
signal executed(id: String, ability: Dictionary, cast: Dictionary)
signal failed(id: String, reason: String)
signal interrupted(id: String, reason: String)

const AbilityDef := preload("res://scripts/abilities/ability_def.gd")
const EffectSet := preload("res://scripts/abilities/effect_set.gd")
const AbilityLib := preload("res://scripts/abilities/ability_lib.gd")
const PowerTrees := preload("res://scripts/abilities/power_trees.gd")

enum Phase { IDLE, CHANT, WINDUP, RECOVER }

const CAST_LOCK := AbilityDef.CAST_LOCK
const FIZZLE_COOLDOWN := 2.0
const CANCEL_REFUND := 0.5

var hooks: Dictionary = {}
var costs_enabled := true
var effects := EffectSet.new()          ## effects on the caster itself (buffs, wards)
var cooldowns: Dictionary = {}          ## id -> seconds left (used when no cooldown hooks are set)
var phase: int = Phase.IDLE
var clock := 0.0

## The player may start another technique while an earlier windup is still pending (the old caster allowed it, only
## the 0.3 s lockout applied); NPCs do one thing at a time.
var overlap_windups := false

var _lock := 0.0
var _t := 0.0                          # chant timer
var _rec := 0.0                        # recover timer
var _cur: Dictionary = {}              # the chant in progress
var _pending: Array = []               # windups in flight: [{t, cur}]


func _has(h: String) -> bool:
	return hooks.has(h) and hooks[h] is Callable and (hooks[h] as Callable).is_valid()


# --- lookups ----------------------------------------------------------------------

func lookup(id: String) -> Dictionary:
	if _has("lookup"):
		return hooks["lookup"].call(id)
	return AbilityLib.get_def(id)


func cooldown_left(id: String) -> float:
	if _has("cooldown_left"):
		return float(hooks["cooldown_left"].call(id))
	return float(cooldowns.get(id, 0.0))


func set_cooldown(id: String, seconds: float) -> void:
	if _has("cooldown_set"):
		hooks["cooldown_set"].call(id, seconds)
	else:
		cooldowns[id] = seconds


func ready(id: String) -> bool:
	return cooldown_left(id) <= 0.0


func is_idle() -> bool:
	return phase == Phase.IDLE


func is_casting() -> bool:
	return phase == Phase.CHANT or phase == Phase.WINDUP


func current_id() -> String:
	return String(_cur.get("id", ""))


func profile() -> Dictionary:
	if _has("profile"):
		return hooks["profile"].call()
	return {}


# --- evaluate ---------------------------------------------------------------------

## What the ability would do for this actor right now. -> {ok, reason, id, def, numbers, gate, chant}
func evaluate(id: String, opts := {}) -> Dictionary:
	var def := lookup(id)
	if def.is_empty():
		return {"ok": false, "reason": "Unknown ability.", "id": id, "def": {}}
	var gate := {"ok": true, "reason": "", "power": 1.0, "cost_mult": 1.0}
	if _has("gate"):
		gate.merge(hooks["gate"].call(def, opts), true)
	var numbers: Dictionary = {}
	if _has("numbers"):
		numbers = hooks["numbers"].call(id, def)
	if numbers.is_empty():
		var costs := {}
		for r: String in (def["costs"] as Dictionary):
			costs[r] = float(def["costs"][r]) * float(gate["cost_mult"])
		numbers = {"costs": costs, "cooldown": float(def["cooldown"]),
			"damage": int(round(float(def["damage"]) * float(gate["power"])))}
	return {"ok": true, "reason": "", "id": id, "def": def, "numbers": numbers, "gate": gate,
		"chant": _chant_info(def, opts)}


## Is chantless casting open to this actor for this ability? -> {ok, reason}
func chantless_allowed(def: Dictionary) -> Dictionary:
	if not AbilityDef.is_chant(def):
		return {"ok": true, "reason": ""}
	if _has("chantless"):
		return hooks["chantless"].call(def)
	var prof := profile()
	if prof.is_empty():
		return {"ok": false, "reason": "Beginners must chant."}
	var path := String((def["cast"] as Dictionary).get("chantless_req", "")) if (def["cast"] as Dictionary).get("chantless_req", "") != "" else String(def.get("path", "magic"))
	var c := PowerTrees.chantless_check(prof, path)
	return {"ok": bool(c["ok"]), "reason": "Chantless casting is beyond you: %s" % " ".join(PackedStringArray(c["reasons"])) if not bool(c["ok"]) else ""}


func _chant_info(def: Dictionary, opts: Dictionary) -> Dictionary:
	if not AbilityDef.is_chant(def):
		# Optional seals (sect, shadow): the seal pad may still be asked for, for the bonus.
		if bool(opts.get("force_chant", false)) and not ((def["cast"] as Dictionary)["seals"] as Array).is_empty():
			return {"required": true, "seals": ((def["cast"] as Dictionary)["seals"] as Array).duplicate(), "time": 3.5, "factor": 1.0}
		return {"required": false}
	var cast: Dictionary = def["cast"]
	if bool(opts.get("chantless", false)):
		var c := chantless_allowed(def)
		if bool(c["ok"]):
			return {"required": false, "chantless": true}
		if not bool(opts.get("fallback_chant", false)):
			return {"required": true, "denied": String(c["reason"]), "seals": cast["seals"], "time": 0.0}
	var prof := profile()
	var lvl := int((prof.get("levels", {}) as Dictionary).get(String(def.get("path", "")), int(opts.get("path_level", 1))))
	var k := PowerTrees.chant_factor(String(def.get("path", "")), lvl) if not prof.is_empty() or opts.has("path_level") else 1.0
	return {"required": true, "seals": (cast["seals"] as Array).duplicate(), "time": float(cast["chant_time"]) * k, "factor": k}


# --- validate ---------------------------------------------------------------------

func validate(ev: Dictionary, opts := {}) -> Dictionary:
	if not bool(ev.get("ok", false)):
		return {"ok": false, "reason": String(ev.get("reason", "Unknown ability."))}
	var def: Dictionary = ev["def"]
	var id := String(ev["id"])
	if _has("blocked"):
		var why := String(hooks["blocked"].call())
		if why != "":
			return {"ok": false, "reason": why}
	if phase == Phase.CHANT or (_lock > 0.0 and not bool(opts.get("ignore_lock", false))) \
			or (not overlap_windups and (not _pending.is_empty() or _rec > 0.0)):
		return {"ok": false, "reason": "Busy."}
	if _has("known") and not bool(hooks["known"].call(id)):
		return {"ok": false, "reason": "Not learned."}
	if String(def["kind"]) != "active":
		return {"ok": false, "reason": "Passive."}
	var left := cooldown_left(id)
	if left > 0.0:
		return {"ok": false, "reason": "%.1fs" % left}
	if costs_enabled:
		var pools: Dictionary = {}
		if _has("pools"):
			var pc: Callable = hooks["pools"]
			pools = pc.call(def) if pc.get_argument_count() >= 1 else pc.call()
		for r: String in (ev["numbers"]["costs"] as Dictionary):
			var cost := float(ev["numbers"]["costs"][r])
			if cost > 0.0 and float(pools.get(r, 0.0)) + 0.001 < cost:
				return {"ok": false, "reason": "Not enough %s." % r}
	var gate: Dictionary = ev["gate"]
	if not bool(gate["ok"]):
		return {"ok": false, "reason": String(gate["reason"])}
	var chant: Dictionary = ev["chant"]
	if chant.has("denied"):
		return {"ok": false, "reason": String(chant["denied"])}
	return {"ok": true, "reason": ""}


## Evaluate + validate without starting anything (the HUD's can-cast check).
func can_use(id: String, opts := {}) -> Dictionary:
	var ev := evaluate(id, opts)
	var v := validate(ev, opts)
	v["ev"] = ev
	return v


# --- begin / chant / commit -----------------------------------------------------------

## opts: target (Node or Dictionary, passed to execute), chantless (ask for it), fallback_chant (chant when
## chantless is denied), auto_chant (the chant times itself: NPCs), sealed (the seal pad already succeeded).
## -> {ok, reason, phase?, ...}; after a commit also resource, cost, cooldown, damage, def (flat), ability.
func begin(id: String, opts := {}) -> Dictionary:
	var ev := evaluate(id, opts)
	var v := validate(ev, opts)
	if not bool(v["ok"]):
		failed.emit(id, String(v["reason"]))
		return {"ok": false, "reason": String(v["reason"])}
	var chant: Dictionary = ev["chant"]
	if bool(chant.get("required", false)) and not bool(opts.get("sealed", false)):
		phase = Phase.CHANT
		_cur = {"id": id, "ev": ev, "opts": opts}
		_t = float(chant["time"]) if bool(opts.get("auto_chant", false)) else INF
		chant_started.emit(id, chant)
		return {"ok": true, "reason": "", "phase": "chant", "seals": chant["seals"], "chant_time": chant["time"]}
	return _commit(ev, opts, bool(opts.get("sealed", false)))


## The chant ended: success commits (sealed = the seal pad was completed, +15 percent), failure fizzles.
func chant_complete(success: bool, sealed := true) -> Dictionary:
	if phase != Phase.CHANT:
		return {"ok": false, "reason": "Not chanting."}
	var id := String(_cur["id"])
	var opts: Dictionary = _cur["opts"]
	phase = Phase.IDLE
	_cur = {}
	if not success:
		if _has("fizzle"):
			hooks["fizzle"].call(id, FIZZLE_COOLDOWN)
		else:
			set_cooldown(id, FIZZLE_COOLDOWN)
		failed.emit(id, "fizzle")
		return {"ok": false, "reason": "fizzle"}
	var ev := evaluate(id, opts)
	var v := validate(ev, {"ignore_lock": true})
	if not bool(v["ok"]):
		failed.emit(id, String(v["reason"]))
		return {"ok": false, "reason": String(v["reason"])}
	return _commit(ev, opts, sealed)


func _commit(ev: Dictionary, opts: Dictionary, sealed: bool) -> Dictionary:
	var def: Dictionary = ev["def"]
	var id := String(ev["id"])
	var res := {}
	var paid := {}
	if _has("commit"):
		res = hooks["commit"].call(id, def, sealed, ev["numbers"], opts)
		if not bool(res.get("ok", false)) and not bool(res.get("default", false)):
			failed.emit(id, String(res.get("reason", "")))
			return res
		if String(res.get("resource", "")) != "":
			paid[String(res["resource"])] = float(res.get("cost", 0.0))
	if res.is_empty() or bool(res.get("default", false)):
		var numbers: Dictionary = ev["numbers"]
		if costs_enabled:
			for r: String in (numbers["costs"] as Dictionary):
				var c := float(numbers["costs"][r])
				if c > 0.0:
					paid[r] = c
					if _has("pay"):
						hooks["pay"].call(r, c)
		set_cooldown(id, float(numbers["cooldown"]))
		var dmg := int(numbers["damage"])
		if sealed and not ((def["cast"] as Dictionary)["seals"] as Array).is_empty():
			dmg = int(round(dmg * (1.0 + AbilityDef.SEAL_BONUS)))
		var pc := AbilityDef.primary_cost(def)
		res = {"ok": true, "reason": "", "resource": String(pc["resource"]), "cost": float(pc["amount"]),
			"cooldown": float(numbers["cooldown"]), "damage": dmg}
	var windup := float(def["windup"])
	_lock = minf(float(def["lockout"]), windup + 0.1)
	res["def"] = AbilityDef.flat(def)
	res["ability"] = def
	res["power"] = float(ev["gate"]["power"])
	res["windup"] = windup
	var cur := {"id": id, "ev": ev, "opts": opts, "damage": int(res.get("damage", 0)), "sealed": sealed, "paid": paid,
		"power": float(ev["gate"]["power"])}
	_pending.append({"t": windup, "cur": cur})
	phase = Phase.WINDUP
	started.emit(id, def)
	if windup <= 0.0:
		_run_pending()
	return res


# --- update / execute -------------------------------------------------------------------

## Advance the lifecycle by `dt`. Returns the events of the caster's own effects (buff expiry, ticks).
func update(dt: float, action_dt: float = -1.0) -> Array:
	# Freeze animation-bound phases independently of cooldowns and effects.
	var step := dt if action_dt < 0.0 else maxf(action_dt, 0.0)
	clock += dt
	_lock = maxf(0.0, _lock - step)
	for id: String in cooldowns.keys():
		var left := float(cooldowns[id]) - dt
		if left <= 0.0:
			cooldowns.erase(id)
		else:
			cooldowns[id] = left
	if phase == Phase.CHANT and _t != INF:
		_t -= dt
		if _t <= 0.0:
			chant_complete(true, false)
	if not _pending.is_empty():
		for w: Dictionary in _pending:
			w["t"] = float(w["t"]) - step
		_run_pending()
	if _rec > 0.0:
		_rec -= step
	if phase != Phase.CHANT:
		phase = Phase.WINDUP if not _pending.is_empty() else (Phase.RECOVER if _rec > 0.0 else Phase.IDLE)
	return effects.tick(dt)


## Executes every windup that has run out, in the order they were started.
func _run_pending() -> void:
	var due: Array = []
	for w: Dictionary in _pending:
		if float(w["t"]) <= 0.0:
			due.append(w)
	for w: Dictionary in due:
		_pending.erase(w)
		_execute(w["cur"])
	if phase != Phase.CHANT:
		phase = Phase.WINDUP if not _pending.is_empty() else (Phase.RECOVER if _rec > 0.0 else Phase.IDLE)


func _execute(cur: Dictionary) -> void:
	var def: Dictionary = (cur["ev"] as Dictionary)["def"]
	_rec = float(def["recover"])
	var cast := {"id": cur["id"], "def": AbilityDef.flat(def), "ability": def, "damage": cur["damage"],
		"power": cur["power"], "sealed": cur["sealed"], "target": (cur["opts"] as Dictionary).get("target")}
	if _has("execute"):
		hooks["execute"].call(def, cast)
	executed.emit(String(cur["id"]), def, cast)


## Drop a chant without penalty (the player walked away from the seal pad).
func cancel() -> bool:
	if phase != Phase.CHANT:
		return false
	phase = Phase.IDLE
	_cur = {}
	return true


## Break the cast. A chant just fizzles (nothing was paid); a windup gives half the cost back and drops the effect.
func interrupt(reason := "interrupted") -> bool:
	if phase == Phase.CHANT:
		var id := String(_cur["id"])
		phase = Phase.IDLE
		_cur = {}
		set_cooldown(id, FIZZLE_COOLDOWN)
		interrupted.emit(id, reason)
		return true
	if phase == Phase.WINDUP and not _pending.is_empty():
		var w: Dictionary = _pending.pop_back()
		var cur: Dictionary = w["cur"]
		var paid: Dictionary = cur.get("paid", {})
		if costs_enabled and _has("refund"):
			for r: String in paid:
				hooks["refund"].call(r, float(paid[r]) * CANCEL_REFUND)
		phase = Phase.WINDUP if not _pending.is_empty() else Phase.IDLE
		interrupted.emit(String(cur["id"]), reason)
		return true
	return false


# --- apply ------------------------------------------------------------------------

## A body-level interruption replaces every pending cast animation, including
## overlapping windups. Use the ordinary interruption rules for each payment.
func interrupt_all(reason := "interrupted") -> bool:
	var changed := _rec > 0.0
	if phase == Phase.CHANT:
		changed = interrupt(reason) or changed
	while not _pending.is_empty():
		phase = Phase.WINDUP
		changed = interrupt(reason) or changed
	_lock = 0.0
	_rec = 0.0
	phase = Phase.IDLE
	return changed


## Puts the ability's riders for `which` ("enemy" or "self") onto `eset` by family and stacking rule.
## `amount` is the damage dealt (burn strength scales with it); `power` scales wards and heals.
## -> {actions: [{family, action}], statuses: [{status, duration}], heal: int, restore: {res: n}, requests: [...]}
func apply_effects(def: Dictionary, amount: int, eset: EffectSet, which := "enemy", power := 1.0, source := "") -> Dictionary:
	var out := {"actions": [], "statuses": [], "heal": 0, "restore": {}, "requests": []}
	for e: Dictionary in (def["effects"] as Array):
		if String(e["target"]) != which:
			continue
		var type := String(e["type"])
		match type:
			"dot", "hot":
				var mag := float(e.get("magnitude", 0.0))
				if mag <= 0.0:
					if amount <= 0:
						continue
					mag = float(maxi(1, int(round(float(amount) * float(e.get("dps_ratio", AbilityDef.BURN_DPS_RATIO))))))
				var row := e.duplicate(true)
				row["magnitude"] = mag * power
				var r := eset.apply(row, source)
				out["actions"].append({"family": e["family"], "action": r["action"]})
			"slow", "stun", "fear", "blind", "pull", "reveal":
				var r2 := eset.apply(e, source)
				out["actions"].append({"family": e["family"], "action": r2["action"]})
				(out["statuses"] as Array).append({"status": type, "duration": float(e.get("duration", 0.0))})
			"buff", "debuff", "aura", "ward", "absorb":
				var row2 := e.duplicate(true)
				if type == "ward" or type == "absorb":
					row2["magnitude"] = float(e.get("magnitude", 0.0)) * power
				var r3 := eset.apply(row2, source)
				out["actions"].append({"family": e["family"], "action": r3["action"]})
			"heal":
				out["heal"] = int(out["heal"]) + int(float(e.get("magnitude", 0.0)) * power)
			"restore":
				var k := String(e.get("resource", "stamina"))
				out["restore"][k] = float(out["restore"].get(k, 0.0)) + float(e.get("magnitude", 0.0)) * power
			_:
				(out["requests"] as Array).append(e.duplicate(true))
	return out


## Damage through the target's counters (damage_taken stat, wards, absorbs). -> {amount, absorbed}
static func mitigate(eset: EffectSet, amount: float, element := "") -> Dictionary:
	return eset.mitigate(amount, element)


# --- save -------------------------------------------------------------------------

func serialize() -> Dictionary:
	return {"cooldowns": cooldowns.duplicate(), "effects": effects.serialize()}


func deserialize(d: Dictionary) -> void:
	cooldowns = {}
	for id: String in d.get("cooldowns", {}):
		cooldowns[id] = float(d["cooldowns"][id])
	effects.deserialize(d.get("effects", []))
