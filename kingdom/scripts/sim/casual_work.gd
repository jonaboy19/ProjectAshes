extends RefCounted
## Casual day-work wages (package C13, Region 1 balance). A work spot that pays a flat wage for a short hold (the field-hand spot at a
## farm site, 6 gold per 4 s) must not be a money tap: each spot kind pays its full wage for FULL_PER_DAY shifts a day, a third of it
## for the next REDUCED_PER_DAY, and nothing after that ("the farmer has no more work for you today"). The count restarts with the day.
## Pure static state keyed by spot kind; `reset()` for a new game and tests. Preload; no class_name.

const FULL_PER_DAY := 2
const REDUCED_PER_DAY := 1

static var _day := -1
static var _done: Dictionary = {}


static func reset() -> void:
	_day = -1
	_done.clear()


## Wage for the next shift at `key` on `day` (and counts it). 0 = no more work today.
static func pay_for(key: String, day: int, base: int) -> int:
	if day != _day:
		_day = day
		_done.clear()
	var n := int(_done.get(key, 0))
	_done[key] = n + 1
	if n < FULL_PER_DAY:
		return base
	if n < FULL_PER_DAY + REDUCED_PER_DAY:
		return maxi(1, int(round(float(base) / 3.0)))
	return 0


## Shifts already worked at `key` today (the prompt can say "enough for today").
static func done_today(key: String, day: int) -> int:
	return int(_done.get(key, 0)) if day == _day else 0
