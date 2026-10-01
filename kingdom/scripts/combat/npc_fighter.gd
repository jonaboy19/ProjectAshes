extends RefCounted
## NPC fighter decision model: cheap, rank-weighted dice on a 4 Hz think. One instance per fighting NPC;
## a pure RefCounted with its own seeded RNG (no scene access) so the duel arena and tests replay exactly.
## It decides WHAT to do (intent + which CombatAction); the body (monster.gd, wolf.gd, a humanoid actor)
## still moves, animates and asks creature_attack_tokens.gd whether it may close in. Tokens gate who
## strikes; this model picks how. Sources: docs/research/MINING_COMBAT_WORLD.md section 1, own numbers.
##
## Guards: feed `sees_target` from Perception (scripts/population/perception.gd): call
## Perception.vis(...) on the think tick and pass `vis > Perception.VIS_MIN`; when false the fighter
## holds and never picks an attack move (acquire first, fight second).

const Moves := preload("res://scripts/combat/combat_moves.gd")
const CombatStats := preload("res://scripts/combat/combat_stats.gd")

enum Intent { HOLD, APPROACH, CIRCLE, POKE, COMBO, GUARD, RETREAT, FEINT }
const INTENT_NAMES := ["hold", "approach", "circle", "poke", "combo", "guard", "retreat", "feint"]

const THINK_HZ := 4.0
const REACT_GAP := 1.2           # never react twice inside this
const FEINT_RANK := 6
const FEINT_CANCEL := 0.4        # a feint backs out at this fraction of the windup
const AGGRO_STEP := 0.2
const AGGRO_TIMER := Vector2(2.0, 5.0)

## hp/dmg/cdm here are duel-calibrated "matching level" values (tools_qa/combat/duel_arena.gd; targets in
## docs below): dmg multiplies move damage, cdm multiplies the cooldown row. Real SPECIES hp is untouched.
## style = key in CombatMoves; rank 0..10; poise; guard_pool = block stamina; tags free-form.
## Stat table: data/combat/archetypes.json (via combat_stats.gd), at matching level.
static var ARCHETYPES: Dictionary = CombatStats.archetypes()

var archetype := ""
var style := ""
var rank := 3
var poise_max := 30.0
var can_guard := false
var aggression := 0.5
var base_aggression := 0.5
var moves: Array = []
var rng := RandomNumberGenerator.new()

var _aggro_timer := 0.0
var _last_react := -99.0
var _think_acc := 0.0
## Poise: every blow chips it; at 0 the fighter staggers, refills to POISE_RESET and is immune to
## further staggers for STAGGER_IMMUNE seconds (no infinite stun-lock). Below the break a blow
## never interrupts a windup (hyper-armour). Regenerates POISE_REGEN/s after POISE_IDLE seconds.
const POISE_RESET := 0.6
const STAGGER_IMMUNE := 1.6
const POISE_REGEN := 8.0
const POISE_IDLE := 1.5
var poise := -1.0
var cd_mult := 1.0              # scales the cooldown row: lower = more pressure
var _last_hit := -99.0
var _immune_until := -99.0


static func has_archetype(name: String) -> bool:
	return ARCHETYPES.has(name)


static func make(arch: String, seed_value := 1, rank_override := -1) -> RefCounted:
	var f: RefCounted = (load("res://scripts/combat/npc_fighter.gd") as GDScript).new()
	f.setup(arch, seed_value, rank_override)
	return f


func setup(arch: String, seed_value := 1, rank_override := -1) -> void:
	archetype = arch
	var d: Dictionary = ARCHETYPES.get(arch, ARCHETYPES["goblin"])
	style = String(d["style"])
	rank = clampi(rank_override if rank_override >= 0 else int(d["rank"]), 0, 10)
	poise_max = float(d["poise"])
	can_guard = bool(d["guard"])
	base_aggression = clampf(float(d["base"]) + (rank - 4) * 0.02, 0.1, 0.95)
	aggression = base_aggression
	moves = Moves.moves(style)
	poise = poise_max
	cd_mult = float(d.get("cdm", 1.0))
	rng.seed = seed_value
	_aggro_timer = rng.randf_range(AGGRO_TIMER.x, AGGRO_TIMER.y)


## Seconds between attack starts (the SPECIES cooldown rows; soldiers use their 1.1-1.5 s).
func cooldown() -> float:
	var d: Dictionary = ARCHETYPES.get(archetype, ARCHETYPES["goblin"])
	return rng.randf_range(float(d["cd"][0]), float(d["cd"][1])) * cd_mult


func default_move() -> Resource:
	return moves[0]


## Reaction chance and delay for a target winding up inside reach (rank sets both).
func react_chance() -> float:
	return clampf(rank * 0.07, 0.0, 0.7)


func react_delay() -> float:
	return maxf(0.25 - rank * 0.015, 0.05)


## Called when the target enters WINDUP within reach. Returns {} or {kind: "guard"|"dodge", delay}.
## `now` is the caller's clock in seconds.
func consider_reaction(now: float, chance := -1.0) -> Dictionary:
	if now - _last_react < REACT_GAP:
		return {}
	_last_react = now
	if rng.randf() >= (react_chance() if chance < 0.0 else chance):
		return {}
	var kind := "guard" if (can_guard and rng.randf() < 0.7) else "dodge"
	return {"kind": kind, "delay": react_delay()}


## After a clash or guard-break win: press the advantage straight away with chance rank/30.
func press_after_win() -> bool:
	return rng.randf() < float(rank) / 30.0


## Nudge aggression on its own 2-5 s timer. ctx: target_recovering, target_tired, target_ranged_idle,
## own_hp_frac.
func _tick_aggression(dt: float, ctx: Dictionary) -> void:
	_aggro_timer -= dt
	if _aggro_timer > 0.0:
		return
	_aggro_timer = rng.randf_range(AGGRO_TIMER.x, AGGRO_TIMER.y)
	var a := base_aggression
	if bool(ctx.get("target_recovering", false)) or bool(ctx.get("target_tired", false)):
		a += AGGRO_STEP
	if bool(ctx.get("target_ranged_idle", false)):
		a += AGGRO_STEP
	if float(ctx.get("own_hp_frac", 1.0)) < 0.3:
		a -= AGGRO_STEP
	aggression = clampf(a, 0.05, 1.0)


## Weighted move choice among the moves usable at `dist`. Heavier moves gain weight against a guarding
## target, quick ones against a recovering one. Returns null if nothing reaches.
func choose_move(dist: float, target_state := "idle") -> Resource:
	var total := 0.0
	var weights: Array = []
	for m: Resource in moves:
		var w := 0.0
		if dist >= m.min_range and dist <= maxf(m.max_range, m.reach):
			w = m.weight
			if target_state == "blocking":
				w *= 1.0 + float(rank) * 0.06 * (m.poise_damage / 12.0)
				if m.unblockable:
					w *= 1.5
			elif target_state == "recovery":
				w *= 1.0 + float(rank) * 0.04 * (1.0 / maxf(m.windup, 0.2))
		weights.append(w)
		total += w
	if total <= 0.0:
		return null
	var roll := rng.randf() * total
	for i in moves.size():
		roll -= float(weights[i])
		if roll <= 0.0 and float(weights[i]) > 0.0:
			return moves[i]
	return moves[0]


## One think. ctx: dist, target_state ("idle"|"windup"|"active"|"recovery"|"blocking"|"staggered"),
## has_token, own_hp_frac, sees_target (default true), strike_range (default = default move reach),
## target_recovering/target_tired/target_ranged_idle (optional aggression inputs).
## Returns {intent, move, feint_at}. Without a token the fighter circles (tokens still gate strikes).
func think(dt: float, ctx: Dictionary) -> Dictionary:
	_tick_aggression(dt, ctx)
	var out := {"intent": Intent.HOLD, "move": null, "feint_at": 0.0}
	if not bool(ctx.get("sees_target", true)):
		return out
	var dist := float(ctx.get("dist", 99.0))
	var tstate := String(ctx.get("target_state", "idle"))
	var hp := float(ctx.get("own_hp_frac", 1.0))
	var strike := float(ctx.get("strike_range", default_move().reach))
	if hp < 0.2 and rank >= 3 and rng.randf() < 0.5:
		out["intent"] = Intent.RETREAT
		return out
	if dist > strike:
		out["intent"] = Intent.APPROACH if bool(ctx.get("has_token", true)) else Intent.CIRCLE
		return out
	if not bool(ctx.get("has_token", true)):
		out["intent"] = Intent.CIRCLE
		return out
	if tstate == "windup" and can_guard and aggression < 0.6 and rng.randf() < react_chance():
		out["intent"] = Intent.GUARD
		return out
	# Aggression gates whether we commit this think (staggered/recovering targets always invite it).
	var open := tstate == "staggered" or tstate == "recovery"
	if not open and rng.randf() > aggression:
		out["intent"] = Intent.GUARD if (can_guard and rng.randf() < 0.4) else Intent.CIRCLE
		return out
	var move := choose_move(dist, tstate)
	if move == null:
		out["intent"] = Intent.APPROACH
		return out
	out["move"] = move
	if rank >= FEINT_RANK and tstate == "blocking" and rng.randf() < 0.1 * float(rank - FEINT_RANK + 1):
		out["intent"] = Intent.FEINT
		out["feint_at"] = move.windup * FEINT_CANCEL
		return out
	var heavy: bool = moves.size() > 1 and move != moves[0] and move.poise_damage > moves[0].poise_damage
	out["intent"] = Intent.COMBO if (heavy or (open and rng.randf() < aggression)) else Intent.POKE
	return out


## A blow of `pdmg` poise damage lands at clock `now`. True when it staggers the fighter.
func absorb(pdmg: float, now: float) -> bool:
	if now - _last_hit > POISE_IDLE:
		poise = minf(poise_max, poise + POISE_REGEN * (now - _last_hit - POISE_IDLE))
	_last_hit = now
	if now < _immune_until:
		return false
	poise -= pdmg
	if poise > 0.0:
		return false
	poise = poise_max * POISE_RESET
	_immune_until = now + STAGGER_IMMUNE
	return true


## Scales this fighter's table stats for an enemy of `enemy_level` meeting the player (poise, cooldown mult);
## returns the full stats dict ({hp, dmg, cdm, poise, rank}) for the body to take its HP and damage from.
func apply_level(enemy_level: int, player_level := -1) -> Dictionary:
	var st: Dictionary = CombatStats.stats(archetype, enemy_level, player_level)
	poise_max = float(st["poise"])
	poise = poise_max
	cd_mult = float(st["cdm"])
	return st
