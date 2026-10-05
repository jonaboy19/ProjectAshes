extends RefCounted
## Headless caster duel: seeded 1v1 fights on one axis at 0.05 s steps between NPC casters (NpcCaster: bandit mage,
## sect disciple, knight captain...) and plain melee archetypes (NpcFighter), using the REAL data and decision code:
## data/powers abilities through the shared AbilityRunner (chant, windup, cooldown, effect families, wards), the
## CombatMoves tables and the fighter think. No scenes, no physics. Used by caster_duel.gd (CLI) and
## tests/test_npc_casting.gd (sanity band).
##
## Model notes (sanity run, not a balance spec): spells resolve at the end of the windup when the foe is in reach
## (projectiles fly at their speed), a blow that staggers breaks a chant, stuns stop all action, slows cut speed,
## wards soak damage first, melee fighters close at 3 m/s, casters kite at 2.4 m/s.

const NpcCaster := preload("res://scripts/combat/npc_caster.gd")
const Fighter := preload("res://scripts/combat/npc_fighter.gd")
const CombatStats := preload("res://scripts/combat/combat_stats.gd")
const EffectSet := preload("res://scripts/abilities/effect_set.gd")

const DT := 0.05
const THINK := 0.25
const MAX_TIME := 90.0
const START_DIST := 9.0
const MAX_DIST := 18.0
const CLOSE_SPEED := 3.0
const KITE_SPEED := 2.4
const STAGGER_STUN := 0.5
const GUARD_TIME := 0.6
const GUARD_REDUCE := 0.35


class Combatant:
	var name := ""
	var level := 12
	var hp := 100.0
	var max_hp := 100.0
	var dmg_mult := 1.0
	var caster: RefCounted = null
	var fighter: RefCounted = null
	var effects: EffectSet = EffectSet.new()
	var think_t := 0.0
	var stun_t := 0.0
	var guard_t := 0.0
	var move: Resource = null
	var move_t := 0.0
	var move_hit := false
	var move_cd := 0.0
	var intent := 0
	var casts := {}
	var chants_broken := 0
	var damage_done := 0.0
	var blows_absorbed := 0

	func alive() -> bool:
		return hp > 0.0

	func state() -> String:
		if stun_t > 0.0:
			return "staggered"
		if move != null:
			return "windup" if not move_hit else "recovery"
		if caster != null and caster.is_casting():
			return "windup"
		if guard_t > 0.0:
			return "blocking"
		return "idle"


var rng := RandomNumberGenerator.new()
var time := 0.0
var dist := START_DIST
var _shots: Array = []         # projectiles in flight: {t, from, dmg, ability, cast_power}


static func make_side(id: String, seed_value: int, level_override := -1) -> Combatant:
	var s := Combatant.new()
	s.name = id
	if NpcCaster.has(id):
		s.caster = NpcCaster.make(id, seed_value)
		s.fighter = s.caster.fighter
		s.effects = s.caster.effects()
		var row: Dictionary = s.caster.row
		s.level = int(row.get("level", 12))
		s.dmg_mult = float(row.get("dmg_mult", 1.0))
		var st: Dictionary = CombatStats.stats(String(row.get("fighter", "bandit")), s.level, s.level)
		s.max_hp = float(st["hp"]) * float(row.get("hp_mult", 1.0))
		s.fighter.apply_level(s.level, s.level)
	else:
		s.fighter = Fighter.make(id, seed_value)
		var d: Dictionary = Fighter.ARCHETYPES[id]
		s.level = int(d.get("level", 12)) if level_override < 0 else level_override
		var st2: Dictionary = CombatStats.stats(id, s.level, s.level)
		s.max_hp = float(st2["hp"])
		s.dmg_mult = float(st2["dmg"])
		s.fighter.apply_level(s.level, s.level)
	s.hp = s.max_hp
	return s


## One duel. -> {winner: 0 draw | 1 a | 2 b, time, a_hp, b_hp, a_casts, b_casts, a_broken, b_broken, a_dmg, b_dmg}
func duel(a: Combatant, b: Combatant, seed_value: int) -> Dictionary:
	rng.seed = seed_value
	time = 0.0
	dist = START_DIST
	_shots.clear()
	for pair: Array in [[a, b], [b, a]]:
		var me: Combatant = pair[0]
		var foe: Combatant = pair[1]
		if me.caster != null:
			me.caster.runner.executed.connect(_on_executed.bind(me, foe))
	var winner := 0
	while time < MAX_TIME:
		time += DT
		_tick_side(a)
		_tick_side(b)
		_update_shots(a, b)
		_step(a, b)
		_step(b, a)
		if not a.alive() or not b.alive():
			winner = 0 if (not a.alive() and not b.alive()) else (2 if not a.alive() else 1)
			break
	for s: Combatant in [a, b]:
		if s.caster != null:
			for c: Dictionary in s.caster.runner.get_signal_connection_list("executed"):
				s.caster.runner.executed.disconnect(c["callable"])
	return {"winner": winner, "time": time, "a_hp": maxf(a.hp, 0.0) / a.max_hp, "b_hp": maxf(b.hp, 0.0) / b.max_hp,
		"a_casts": a.casts.duplicate(), "b_casts": b.casts.duplicate(), "a_broken": a.chants_broken, "b_broken": b.chants_broken,
		"a_dmg": a.damage_done, "b_dmg": b.damage_done}


func _tick_side(s: Combatant) -> void:
	s.stun_t = maxf(0.0, s.stun_t - DT)
	s.guard_t = maxf(0.0, s.guard_t - DT)
	s.move_cd = maxf(0.0, s.move_cd - DT)
	# Runner timers plus the actor's own effect events (burns hurt casters too, heal-over-time heals them).
	var events: Array = s.caster.update(DT) if s.caster != null else s.effects.tick(DT)
	for ev: Dictionary in events:
		if String(ev["kind"]) == "dot":
			s.hp -= float(ev["amount"])
		elif String(ev["kind"]) == "hot":
			s.hp = minf(s.max_hp, s.hp + float(ev["amount"]))
	if s.effects.is_stunned() and s.stun_t < 0.2:
		s.stun_t = 0.2
	if s.stun_t > 0.0 and s.caster != null and s.caster.is_casting():
		s.caster.runner.interrupt("stunned")
	if s.stun_t > 0.0:
		s.move = null


func _speed(s: Combatant, base: float) -> float:
	return base * s.effects.speed_factor()


func _step(me: Combatant, foe: Combatant) -> void:
	if not me.alive() or not foe.alive() or me.stun_t > 0.0:
		return
	if me.move != null:
		me.move_t += DT
		if not me.move_hit and me.move_t >= me.move.hit_time():
			me.move_hit = true
			if dist <= me.move.reach + 0.2:
				_melee_hit(me, foe, me.move)
		if me.move_t >= me.move.total():
			me.move = null
			me.move_cd = me.fighter.cooldown()
		return
	if me.caster != null and me.caster.is_casting():
		return                              # planted: chanting or winding up
	me.think_t -= DT
	if me.think_t <= 0.0:
		me.think_t = THINK
		var ctx := {"dist": dist, "target_state": foe.state(), "has_token": true, "own_hp_frac": maxf(me.hp, 0.0) / me.max_hp,
			"strike_range": me.fighter.default_move().reach, "sees_target": true}
		if me.caster != null:
			var d: Dictionary = me.caster.think(THINK, ctx)
			me.intent = -1
			if String(d["ability"]) != "":
				var r: Dictionary = me.caster.cast(String(d["ability"]), foe)
				if bool(r.get("ok", false)):
					me.casts[d["ability"]] = int(me.casts.get(d["ability"], 0)) + 1
					return
			elif String(d["intent"]) == "kite":
				me.intent = Fighter.Intent.RETREAT
				_move_away(me)
				return
			me.intent = int((d["fight"] as Dictionary)["intent"])
			_act(me, foe, d["fight"])
		else:
			var f: Dictionary = me.fighter.think(THINK, ctx)
			me.intent = int(f["intent"])
			_act(me, foe, f)
	else:
		_drift(me)


func _act(me: Combatant, foe: Combatant, f: Dictionary) -> void:
	match int(f["intent"]):
		Fighter.Intent.POKE, Fighter.Intent.COMBO, Fighter.Intent.FEINT:
			if f["move"] != null and me.move_cd <= 0.0 and dist <= (f["move"] as Resource).reach + 0.2:
				me.move = f["move"]
				me.move_t = 0.0
				me.move_hit = false
		Fighter.Intent.GUARD:
			if me.fighter.can_guard:
				me.guard_t = GUARD_TIME
		_:
			pass


func _drift(me: Combatant) -> void:
	match me.intent:
		Fighter.Intent.APPROACH, Fighter.Intent.POKE, Fighter.Intent.COMBO, Fighter.Intent.CIRCLE, Fighter.Intent.FEINT:
			if dist > me.fighter.default_move().reach * 0.85:
				dist = maxf(dist - _speed(me, CLOSE_SPEED) * DT, 0.8)
		Fighter.Intent.RETREAT:
			_move_away(me)


func _move_away(me: Combatant) -> void:
	dist = minf(dist + _speed(me, KITE_SPEED) * DT, MAX_DIST)


func _melee_hit(me: Combatant, foe: Combatant, move: Resource) -> void:
	_blow(me, foe, float(move.damage) * me.dmg_mult, float(move.poise_damage), "", true)


## Damage through guard, wards and stagger. `melee` blows can be blocked.
func _blow(me: Combatant, foe: Combatant, amount: float, poise: float, element: String, melee: bool) -> void:
	var dmg := amount
	if melee and foe.guard_t > 0.0:
		dmg *= GUARD_REDUCE
		foe.blows_absorbed += 1
		poise *= 0.3
	var m := foe.effects.mitigate(dmg, element)
	foe.hp -= float(m["amount"])
	me.damage_done += float(m["amount"])
	var stag := false
	if foe.caster != null:
		var before: int = foe.caster.chants_broken
		stag = foe.caster.on_blow(poise, float(m["amount"]), time)
		foe.chants_broken += foe.caster.chants_broken - before
	else:
		stag = foe.fighter.absorb(poise, time)
	if stag:
		foe.stun_t = STAGGER_STUN
		foe.move = null


func _on_executed(_id: String, ab: Dictionary, cast: Dictionary, me: Combatant, foe: Combatant) -> void:
	if not me.alive():
		return
	var t: Dictionary = ab["targeting"]
	var dmg := float(int(cast["damage"])) * me.dmg_mult
	var kind := String(t["kind"])
	var runner: RefCounted = me.caster.runner
	# Riders on the caster itself (wards, buffs, heals).
	var own: Dictionary = runner.apply_effects(ab, int(dmg), me.effects, "self", float(cast["power"]), me.name)
	me.hp = minf(me.max_hp, me.hp + float(own["heal"]))
	if int(dmg) <= 0 and kind in ["self", "buff", "utility", "command"]:
		return
	match kind:
		"projectile":
			_shots.append({"t": time + dist / maxf(float(t["speed"]), 1.0), "me": me, "foe": foe, "dmg": dmg, "ab": ab,
				"power": float(cast["power"])})
		"dash":
			if dist <= float(t["range"]) + 1.0:
				dist = maxf(dist - float(t["range"]), 1.0)
				if dist <= 3.0:
					_spell_hit(me, foe, dmg, ab)
		"melee", "cone", "chain", "target_aoe", "aoe", "line", "target":
			var reach := float(t["radius"]) if kind == "aoe" else float(t["range"])
			if dist <= maxf(reach, 1.0) + 0.2:
				_spell_hit(me, foe, dmg, ab)
		_:
			pass


func _update_shots(_a: Combatant, _b: Combatant) -> void:
	for s: Dictionary in _shots.duplicate():
		if time >= float(s["t"]):
			_shots.erase(s)
			var me: Combatant = s["me"]
			var foe: Combatant = s["foe"]
			if me.alive() and foe.alive() and dist <= float((s["ab"]["targeting"] as Dictionary)["range"]) + 1.0:
				_spell_hit(me, foe, float(s["dmg"]), s["ab"])


func _spell_hit(me: Combatant, foe: Combatant, dmg: float, ab: Dictionary) -> void:
	_blow(me, foe, dmg, dmg * 0.6, String(ab["element"]), false)
	if foe.alive():
		me.caster.runner.apply_effects(ab, int(dmg), foe.effects, "enemy", 1.0, me.name)
		if foe.effects.is_stunned():
			foe.stun_t = maxf(foe.stun_t, 0.3)
			foe.move = null


## Runs `n` duels of a vs b (ids: NpcCaster or Fighter archetype names).
func run(a_id: String, b_id: String, n: int, seed_base := 1) -> Dictionary:
	var aw := 0
	var bw := 0
	var dr := 0
	var ttk := 0.0
	var a_hp := 0.0
	var b_hp := 0.0
	var a_broken := 0
	var b_broken := 0
	var a_casts := 0
	var b_casts := 0
	var used := {}
	for i in n:
		var s := seed_base * 100003 + i * 7919
		var a := make_side(a_id, s + 1)
		var b := make_side(b_id, s + 2)
		var r := duel(a, b, s + 3)
		match int(r["winner"]):
			1:
				aw += 1
			2:
				bw += 1
			_:
				dr += 1
		ttk += float(r["time"])
		a_hp += float(r["a_hp"])
		b_hp += float(r["b_hp"])
		a_broken += int(r["a_broken"])
		b_broken += int(r["b_broken"])
		for k: String in r["a_casts"]:
			a_casts += int(r["a_casts"][k])
			used[k] = int(used.get(k, 0)) + int(r["a_casts"][k])
		for k: String in r["b_casts"]:
			b_casts += int(r["b_casts"][k])
			used[k] = int(used.get(k, 0)) + int(r["b_casts"][k])
	return {"a": a_id, "b": b_id, "n": n, "a_win": 100.0 * aw / n, "b_win": 100.0 * bw / n, "draw": 100.0 * dr / n,
		"ttk": ttk / n, "a_hp": 100.0 * a_hp / n, "b_hp": 100.0 * b_hp / n, "a_casts": float(a_casts) / n,
		"b_casts": float(b_casts) / n, "a_broken": float(a_broken) / n, "b_broken": float(b_broken) / n, "abilities": used}
