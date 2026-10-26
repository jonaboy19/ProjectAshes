class_name RANeeds
extends RefCounted
## Hunger, fatigue, thirst and body warmth. All run 0..100 where 100 is fed / rested. They fall with
## in-game time; food and sleep restore them. Low values cost stamina recovery,
## top stamina and speed; starving hurts.

signal changed

const HUNGER_PER_HOUR := 2.8       # full to empty in ~36 in-game hours
const FATIGUE_PER_HOUR := 4.5      # rested to exhausted in ~22 awake hours
const SLEEP_PER_HOUR := 14.0       # ~7 hours to fully rest in a good bed

const THIRST_PER_HOUR := 2.5       # full to parched in ~40 in-game hours (a day is 12 real minutes: ~20 min)
## Warmth drifts toward the exposure target at this rate (points per in-game hour).
const WARMTH_RATE := 12.0          # a cold night takes ~3 in-game hours (~1.5 real min) to chill you through

var food := 85.0
var rest := 90.0
var water := 85.0
var warmth := 80.0
## Exposure for the next tick, set by the world each life tick (see exposure()):
## {wet: 0..1 (rain / swimming), cold: 0..1 (night, snow, altitude), shelter: bool, fire: bool}
var env := {}
## Carried weight / carry capacity (Life sets it each tick from the inventory). Over 1 = overburdened.
var load_ratio := 0.0


func tick(hours: float) -> void:
	food = clampf(food - HUNGER_PER_HOUR * hours, 0.0, 100.0)
	rest = clampf(rest - FATIGUE_PER_HOUR * hours, 0.0, 100.0)
	water = clampf(water - THIRST_PER_HOUR * hours * (1.0 + 0.5 * float(env.get("exert", 0.0))), 0.0, 100.0)
	var target := warmth_target(env)
	warmth = move_toward(warmth, target, WARMTH_RATE * hours)
	changed.emit()


## Body warmth the conditions pull toward (0 freezing .. 100 warm).
static func warmth_target(e: Dictionary) -> float:
	if bool(e.get("fire", false)):
		return 95.0
	var t := 85.0 - 45.0 * float(e.get("cold", 0.0)) - 35.0 * float(e.get("wet", 0.0))
	if bool(e.get("shelter", false)):
		t = maxf(t, 70.0)
	return clampf(t, 0.0, 100.0)


## Exposure dictionary from plain world facts (pure; Life fills it every tick).
static func exposure(night: bool, raining: bool, snowing: bool, in_water: bool, altitude: float, sheltered: bool,
		near_fire: bool, running := false) -> Dictionary:
	var cold := (0.35 if night else 0.0) + (0.5 if snowing else 0.0) + clampf((altitude - 80.0) / 80.0, 0.0, 0.4)
	var wet := 1.0 if in_water else (0.6 if (raining and not sheltered) else 0.0)
	return {"cold": clampf(cold, 0.0, 1.0), "wet": wet, "shelter": sheltered, "fire": near_fire, "exert": 1.0 if running else 0.0}


func drink(amount := 35.0) -> void:
	water = clampf(water + amount, 0.0, 100.0)
	changed.emit()


func eat(nutrition: float) -> void:
	food = clampf(food + nutrition, 0.0, 100.0)
	changed.emit()


## Sleep for `hours` in a bed of `quality` (0.5 on the ground .. 1.0 inn bed).
## Hunger still falls while asleep, at half rate.
func sleep(hours: float, quality := 1.0) -> void:
	rest = clampf(rest + SLEEP_PER_HOUR * quality * hours, 0.0, 100.0)
	food = clampf(food - HUNGER_PER_HOUR * 0.5 * hours, 0.0, 100.0)
	water = clampf(water - THIRST_PER_HOUR * 0.5 * hours, 0.0, 100.0)   # you wake up thirsty, not parched
	warmth = maxf(warmth, lerpf(45.0, 80.0, clampf(quality, 0.0, 1.0)))  # a bed (or bedroll) warms you through
	changed.emit()


## After a death: nobody wakes up still starving, parched or frozen (that would loop straight back to death).
func revive_floor(level := 30.0) -> void:
	food = maxf(food, level)
	water = maxf(water, level)
	warmth = maxf(warmth, level + 20.0)
	rest = maxf(rest, level)
	changed.emit()


## Hours of sleep needed to be fully rested in a bed of `quality`.
func hours_to_rest(quality := 1.0) -> float:
	return ceilf((100.0 - rest) / (SLEEP_PER_HOUR * quality))


## Multiplier on stamina regeneration.
func stamina_regen() -> float:
	var f := 1.0
	if food < 25.0:
		f *= 0.5
	if rest < 20.0:
		f *= 0.6
	if water < 20.0:
		f *= 0.6
	if warmth < 25.0:
		f *= 0.7
	if load_ratio > 1.0:
		f *= 0.7
	return f


## Multiplier on maximum stamina.
func stamina_cap() -> float:
	return lerpf(0.55, 1.0, clampf(rest / 30.0, 0.0, 1.0))


func speed() -> float:
	var k := 0.8 if rest < 10.0 else 1.0
	if warmth < 15.0:
		k *= 0.85     # numb with cold
	return k * encumbrance_speed(load_ratio)


## Speed multiplier for carried load: free up to capacity, then 0.75 down to 0.45 at 150 %.
static func encumbrance_speed(ratio: float) -> float:
	if ratio <= 1.0:
		return 1.0
	return lerpf(0.75, 0.45, clampf((ratio - 1.0) / 0.5, 0.0, 1.0))


func load_label() -> String:
	return "Overburdened" if load_ratio > 1.0 else ""


## Health lost per in-game hour while starving.
func starvation() -> float:
	return (3.0 if food <= 0.0 else 0.0) + (4.0 if water <= 0.0 else 0.0) + (2.5 if warmth <= 5.0 else 0.0)


func hunger_label() -> String:
	return "Starving" if food <= 0.0 else ("Hungry" if food < 25.0 else ("Peckish" if food < 55.0 else "Fed"))


func rest_label() -> String:
	return "Exhausted" if rest < 10.0 else ("Tired" if rest < 30.0 else ("Weary" if rest < 55.0 else "Rested"))


func thirst_label() -> String:
	return "Parched" if water <= 0.0 else ("Thirsty" if water < 25.0 else ("Dry" if water < 55.0 else "Quenched"))


func warmth_label() -> String:
	return "Freezing" if warmth < 15.0 else ("Cold" if warmth < 35.0 else ("Cool" if warmth < 60.0 else "Warm"))


func serialize() -> Dictionary:
	return {"food": food, "rest": rest, "water": water, "warmth": warmth}


func deserialize(d: Dictionary) -> void:
	food = float(d.get("food", food))
	rest = float(d.get("rest", rest))
	water = float(d.get("water", water))
	warmth = float(d.get("warmth", warmth))
	changed.emit()
