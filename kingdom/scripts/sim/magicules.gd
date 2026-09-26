class_name RAMagicules
extends RefCounted
## A magicule pool (the ambient power that fuels naming, techniques and magic).
## It regenerates per in-game hour. You may overdraw below zero, down to
## -OVERDRAW_LIMIT of the pool, but overdrawing piles on exhaustion (slower
## regeneration, weaker stamina) and may tear the body: a damage roll that grows
## with how deep you went.
##
## Deterministic: its own seeded RNG (serialized).
##
## INTEGRATION (for Life; not wired yet):
## - Life owns `var magicules := RAMagicules.new(40.0, 1.5)`; in `_process`
##   alongside `needs.tick(dh)` call `magicules.regenerate(dh)`.
## - Each day (and after treatment) apply injuries:
##   `magicules.apply_effects(injuries.effects())` so a Fractured Core shrinks the pool.
## - When a spend returns damage > 0: `player.take_damage(r.damage, null)`.
## - Stamina: multiply the player's stamina regen by `magicules.stamina_factor()`
##   together with `needs.stamina_regen()`.
## - Save: snapshot["magicules"] = magicules.serialize().

## You may go this far below zero, as a share of the effective maximum.
const OVERDRAW_LIMIT := 0.5
## Exhaustion gained per full pool overdrawn (exhaustion runs 0..1).
const EXHAUSTION_PER_POOL := 2.0
const EXHAUSTION_RECOVERY_PER_HOUR := 0.04
## Damage roll: chance = depth * DAMAGE_CHANCE (depth = overdraw / max, 0..0.5),
## damage = depth * DAMAGE_AT_FULL hp (at least 1).
const DAMAGE_CHANCE := 1.4
const DAMAGE_AT_FULL := 80.0

var max_pool := 40.0
var current := 40.0
var regen_per_hour := 1.5
var exhaustion := 0.0
## Multipliers from injuries (RAInjuries.effects(): magicule_max, magicule_regen).
var max_modifier := 1.0
var regen_modifier := 1.0

var _rng := RandomNumberGenerator.new()


func _init(pool := 40.0, regen := 1.5, seed_value := 31337) -> void:
	max_pool = pool
	current = pool
	regen_per_hour = regen
	_rng.seed = seed_value


func effective_max() -> float:
	return maxf(1.0, max_pool * max_modifier)


func overdraw_capacity() -> float:
	return effective_max() * OVERDRAW_LIMIT


## Magicules that can still be spent, counting the overdraw margin.
func spendable() -> float:
	return current + overdraw_capacity()


func can_afford(amount: float) -> bool:
	return amount <= current


func is_overdrawn() -> bool:
	return current < 0.0


func is_exhausted() -> bool:
	return exhaustion >= 0.5 or current < 0.0


## Multiplier for stamina regeneration and cap while exhausted.
func stamina_factor() -> float:
	return clampf(1.0 - exhaustion * 0.6, 0.3, 1.0)


## Spend `amount`. Refused (nothing spent) beyond the overdraw margin.
## Returns {ok, spent, overdraw, depth, exhaustion, damage, text}.
func spend(amount: float) -> Dictionary:
	if amount > spendable():
		return {"ok": false, "spent": 0.0, "overdraw": 0.0, "depth": 0.0, "exhaustion": exhaustion, "damage": 0,
			"text": "Not enough magicules (%d needed, %d at most)." % [int(ceil(amount)), int(floor(spendable()))]}
	var before_debt := maxf(0.0, -current)
	current -= amount
	var overdraw := maxf(0.0, -current) - before_debt
	var depth := maxf(0.0, -current) / effective_max()
	var damage := 0
	var text := ""
	if overdraw > 0.0:
		exhaustion = clampf(exhaustion + overdraw / effective_max() * EXHAUSTION_PER_POOL, 0.0, 1.0)
		if _rng.randf() < depth * DAMAGE_CHANCE:
			damage = maxi(1, int(round(depth * DAMAGE_AT_FULL)))
		text = "You draw on magicules you do not have. Exhaustion floods you."
		if damage > 0:
			text += " Something tears inside (-%d health)." % damage
	return {"ok": true, "spent": amount, "overdraw": overdraw, "depth": depth, "exhaustion": exhaustion,
		"damage": damage, "text": text}


func regenerate(hours: float) -> void:
	exhaustion = maxf(0.0, exhaustion - EXHAUSTION_RECOVERY_PER_HOUR * hours)
	var rate := regen_per_hour * regen_modifier * (1.0 - exhaustion * 0.75)
	current = minf(effective_max(), current + maxf(0.0, rate) * hours)


## Hours until the pool is full again at the current rates (approximate).
func hours_to_full() -> float:
	var rate := maxf(0.01, regen_per_hour * regen_modifier * (1.0 - exhaustion * 0.75))
	return maxf(0.0, (effective_max() - current) / rate)


## Take injury effects (RAInjuries.effects()) into account.
func apply_effects(effects: Dictionary) -> void:
	max_modifier = clampf(1.0 + float(effects.get("magicule_max", 0.0)), 0.1, 3.0)
	regen_modifier = clampf(1.0 + float(effects.get("magicule_regen", 0.0)), 0.0, 3.0)
	current = minf(current, effective_max())


## Training, evolution or titles raise the pool.
func grow(extra_max: float, extra_regen := 0.0) -> void:
	max_pool += extra_max
	regen_per_hour += extra_regen


func serialize() -> Dictionary:
	return {"max": max_pool, "current": current, "regen": regen_per_hour, "exhaustion": exhaustion,
		"max_mod": max_modifier, "regen_mod": regen_modifier, "rng": str(_rng.state)}


func deserialize(d: Dictionary) -> void:
	max_pool = float(d.get("max", max_pool))
	current = float(d.get("current", current))
	regen_per_hour = float(d.get("regen", regen_per_hour))
	exhaustion = float(d.get("exhaustion", exhaustion))
	max_modifier = float(d.get("max_mod", max_modifier))
	regen_modifier = float(d.get("regen_mod", regen_modifier))
	if d.has("rng"):
		_rng.state = String(d["rng"]).to_int()
