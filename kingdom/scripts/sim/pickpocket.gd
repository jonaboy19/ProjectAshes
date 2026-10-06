extends RefCounted
## Picking a villager's pocket (package F5): sneak (crouch) up behind someone who has not noticed you and hold the
## interact button for HOLD_TIME. The chance comes from stealth against perception: your stealth skill, the light,
## the victim's acuity and whether you are really behind them. Pure maths; crime_watch.gd wires the hold
## interaction and `resolve` applies the outcome.
##
## Success: a few coins (and the purse is "taken": the same person can only be robbed once a day), still possibly
## seen by bystanders (witness path, pickpocket). Failure: the victim catches your hand; they are a witness
## for certain and the offence is an assault/robbery report. Preload; no class_name.

const HOLD_TIME := 1.6
const REACH := 1.6
## Perception classes (perception.gd Cls): only a CALM or NOTICE victim can be robbed.
const MAX_VICTIM_CLASS := 1
const BASE := 0.5
const MIN_CHANCE := 0.05
const MAX_CHANCE := 0.92

## person -> day last robbed (a purse is only full once a day).
static var _robbed := {}
## C13 (docs/regions/BALANCE_R1.md): word gets round. Every purse lifted today makes the next harder (the chance falls to 1/(1 + 0.3 n))
## and lighter (the purse to 1/(1 + 0.35 n)), so a day's pickpocketing tops out around twenty-five gold, not the hundred and eighty a
## 40-purse run paid before. The count restarts with the day.
const HEAT_CHANCE := 0.3
const HEAT_PURSE := 0.35
static var _heat_day := -1
static var _heat_n := 0


static func reset() -> void:
	_robbed.clear()
	_heat_day = -1
	_heat_n = 0


## Purses lifted on `day` so far.
static func heat_today(day: int) -> int:
	return _heat_n if _heat_day == day else 0


## Success probability 0..1. `stealth` skill 0..10, `acuity` the victim's (1 = ordinary), `light` 0..1 at the
## player, `behind` whether the player stands behind the victim's facing, `victim_class` perception class.
## Zero when the player is not crouched or the victim already noticed something.
static func chance(stealth: float, acuity: float, light: float, behind: bool, victim_class := 0, crouching := true, heat_n := 0) -> float:
	if not crouching or victim_class > MAX_VICTIM_CLASS:
		return 0.0
	var c := BASE + 0.04 * clampf(stealth, 0.0, 10.0)
	c -= 0.25 * (clampf(acuity, 0.3, 2.0) - 1.0)
	c += 0.18 * (1.0 - clampf(light, 0.0, 1.0))
	c -= 0.0 if behind else 0.35
	c -= 0.1 * float(victim_class)
	c /= 1.0 + HEAT_CHANCE * float(heat_n)
	return clampf(c, MIN_CHANCE, MAX_CHANCE)


## {ok} from a probability and a roll in 0..1 (the roll is a parameter so tests are exact).
static func attempt(p: float, roll: float) -> Dictionary:
	return {"ok": p > 0.0 and roll < p, "chance": p}


## Coins in the victim's pocket: 2..14 by a deterministic mix of person and day.
static func purse_of(person: int, day: int) -> int:
	return 2 + absi(hash([person, day, "purse"])) % 13


static func already_robbed(person: int, day: int) -> bool:
	return int(_robbed.get(person, -1)) == day


static func mark_robbed(person: int, day: int) -> void:
	_robbed[person] = day


## Applies an attempt. `ok` true: coins go to the player (`give_gold` Callable(int)) and the victim is marked.
## Returns {ok, gold, crime, text}: `crime` is the kind to report through the witness path ("pickpocket" on
## success, "robbery" on a caught hand), "" when nothing is reported.
static func resolve(ok: bool, person: int, day: int, give_gold: Callable) -> Dictionary:
	if already_robbed(person, day):
		return {"ok": false, "gold": 0, "crime": "", "text": "Their pockets are already empty."}
	if ok:
		var g := maxi(1, int(round(float(purse_of(person, day)) / (1.0 + HEAT_PURSE * float(heat_today(day))))))
		mark_robbed(person, day)
		if _heat_day != day:
			_heat_day = day
			_heat_n = 0
		_heat_n += 1
		if give_gold.is_valid():
			give_gold.call(g)
		return {"ok": true, "gold": g, "crime": "pickpocket", "text": "You lift %d gold without a sound." % g}
	return {"ok": false, "gold": 0, "crime": "robbery", "text": "A hand clamps on your wrist. \"Thief!\""}
