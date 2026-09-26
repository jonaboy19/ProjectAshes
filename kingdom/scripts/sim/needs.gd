class_name RANeeds
extends RefCounted
## Hunger and fatigue. Both run 0..100 where 100 is fed / rested. They fall with
## in-game time; food and sleep restore them. Low values cost stamina recovery,
## top stamina and speed; starving hurts.

signal changed

const HUNGER_PER_HOUR := 2.8       # full to empty in ~36 in-game hours
const FATIGUE_PER_HOUR := 4.5      # rested to exhausted in ~22 awake hours
const SLEEP_PER_HOUR := 14.0       # ~7 hours to fully rest in a good bed

var food := 85.0
var rest := 90.0


func tick(hours: float) -> void:
	food = clampf(food - HUNGER_PER_HOUR * hours, 0.0, 100.0)
	rest = clampf(rest - FATIGUE_PER_HOUR * hours, 0.0, 100.0)
	changed.emit()


func eat(nutrition: float) -> void:
	food = clampf(food + nutrition, 0.0, 100.0)
	changed.emit()


## Sleep for `hours` in a bed of `quality` (0.5 on the ground .. 1.0 inn bed).
## Hunger still falls while asleep, at half rate.
func sleep(hours: float, quality := 1.0) -> void:
	rest = clampf(rest + SLEEP_PER_HOUR * quality * hours, 0.0, 100.0)
	food = clampf(food - HUNGER_PER_HOUR * 0.5 * hours, 0.0, 100.0)
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
	return f


## Multiplier on maximum stamina.
func stamina_cap() -> float:
	return lerpf(0.55, 1.0, clampf(rest / 30.0, 0.0, 1.0))


func speed() -> float:
	return 0.8 if rest < 10.0 else 1.0


## Health lost per in-game hour while starving.
func starvation() -> float:
	return 3.0 if food <= 0.0 else 0.0


func hunger_label() -> String:
	return "Starving" if food <= 0.0 else ("Hungry" if food < 25.0 else ("Peckish" if food < 55.0 else "Fed"))


func rest_label() -> String:
	return "Exhausted" if rest < 10.0 else ("Tired" if rest < 30.0 else ("Weary" if rest < 55.0 else "Rested"))


func serialize() -> Dictionary:
	return {"food": food, "rest": rest}


func deserialize(d: Dictionary) -> void:
	food = float(d.get("food", food))
	rest = float(d.get("rest", rest))
	changed.emit()
