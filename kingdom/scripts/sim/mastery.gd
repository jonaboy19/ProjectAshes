extends RefCounted
## Per-discipline experience that only grows by doing. There is no free
## experience: gain(discipline, amount, day) is the only way a level moves, so
## switching careers never grants a level in the new one — only in whatever a
## person actually practised.
##
## Levels run 1..100 on a diminishing curve (each level needs more practice
## than the last): with LEVEL_K = 0.05, one unit of practice a day reaches
## level 50 in about ten in-game years (RALifePath.DAYS_PER_YEAR days each) and
## level 100 (Grandmaster) only after a lifetime of it. The curve is one
## constant, so it can be retuned without touching callers.
##
## Overlaps feed a fraction of xp sideways into a related discipline (hunting's
## beast anatomy helps Soulbeast processing, a soldier's discipline makes a
## leader, a trader picks up letters and numbers). Overlap gains don't count
## toward the fed discipline's days-practised total: you can't buy "years of
## experience" by proxy, only the craft you actually stood over.
##
## Pure data (RefCounted, serialisable); autoload/life.gd drives it from
## record() and from crafting/military/careers xp events.

const RALifePath := preload("res://scripts/sim/life_path.gd")

const MAX_LEVEL := 100
## xp needed to go from level l to l+1, summed: xp_for_level(L) = K*(L-1)*L.
const LEVEL_K := 0.05

const DISCIPLINES: Array[String] = [
	"farming", "soldiering", "trading", "smithing", "hunting", "fishing", "herbalism",
	"alchemy", "carpentry", "leatherwork", "cooking", "scholarship", "faith", "leadership",
	"swordsmanship", "archery", "beast_lore", "mining", "healing", "command", "masonry",
]

## discipline -> {fed discipline -> fraction of the xp also credited there}.
const OVERLAPS := {
	"hunting": {"beast_lore": 0.30},
	"soldiering": {"leadership": 0.25},
	"trading": {"scholarship": 0.10},
}

const RANK_WORDS := ["Novice", "Apprentice", "Journeyman", "Expert", "Master", "Grandmaster"]
## Level at which each word starts (Grandmaster only at the very top).
const RANK_THRESHOLDS := [1, 17, 34, 51, 68, 85]

## discipline -> total xp.
var xp: Dictionary = {}
## discipline -> number of distinct in-game days practice was recorded.
var days_practised: Dictionary = {}
## discipline -> last day a gain was counted toward days_practised.
var _last_day: Dictionary = {}


static func xp_for_level(level: int) -> float:
	var l := clampi(level, 1, MAX_LEVEL) - 1
	return LEVEL_K * l * (l + 1)


static func level_from_xp(total: float) -> int:
	var l := 1
	while l < MAX_LEVEL and total >= xp_for_level(l + 1):
		l += 1
	return l


func level(discipline: String) -> int:
	return level_from_xp(float(xp.get(discipline, 0.0)))


## x = xp into the current level, y = xp the level needs (0, 0 at the cap).
func xp_progress(discipline: String) -> Vector2:
	var total := float(xp.get(discipline, 0.0))
	var l := level_from_xp(total)
	if l >= MAX_LEVEL:
		return Vector2.ZERO
	return Vector2(total - xp_for_level(l), xp_for_level(l + 1) - xp_for_level(l))


func years_practised(discipline: String) -> int:
	return int(int(days_practised.get(discipline, 0)) / float(RALifePath.DAYS_PER_YEAR))


static func rank_word(level: int) -> String:
	var word := RANK_WORDS[0]
	for i in RANK_THRESHOLDS.size():
		if level >= RANK_THRESHOLDS[i]:
			word = RANK_WORDS[i]
	return word


func rank_word_for(discipline: String) -> String:
	return rank_word(level(discipline))


## Records a day's practice. Returns {discipline, level, level_up, days_practised}
## for the primary discipline; overlaps are credited silently (call again with
## the fed discipline if the caller also needs its own result).
func gain(discipline: String, amount: float, day: int) -> Dictionary:
	if amount <= 0.0 or not DISCIPLINES.has(discipline):
		return {"discipline": discipline, "level": level(discipline), "level_up": false,
			"days_practised": int(days_practised.get(discipline, 0))}
	var before := level(discipline)
	xp[discipline] = float(xp.get(discipline, 0.0)) + amount
	if int(_last_day.get(discipline, -999999)) != day:
		_last_day[discipline] = day
		days_practised[discipline] = int(days_practised.get(discipline, 0)) + 1
	var after := level(discipline)
	for fed: String in (OVERLAPS.get(discipline, {}) as Dictionary):
		var frac: float = OVERLAPS[discipline][fed]
		xp[fed] = float(xp.get(fed, 0.0)) + amount * frac
	return {"discipline": discipline, "level": after, "level_up": after > before,
		"days_practised": int(days_practised.get(discipline, 0))}


## Top disciplines by level: [{discipline, level, word}], highest first.
func top(n := 3) -> Array:
	var rows := []
	for d: String in DISCIPLINES:
		var lvl := level(d)
		if lvl > 1:
			rows.append({"discipline": d, "level": lvl, "word": rank_word(lvl)})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["level"]) > int(b["level"]))
	return rows.slice(0, n)


func serialize() -> Dictionary:
	return {"xp": xp.duplicate(), "days_practised": days_practised.duplicate(), "last_day": _last_day.duplicate()}


func deserialize(d: Dictionary) -> void:
	xp.clear()
	days_practised.clear()
	_last_day.clear()
	var x: Dictionary = d.get("xp", {})
	for k: String in x:
		xp[k] = float(x[k])
	var dp: Dictionary = d.get("days_practised", {})
	for k: String in dp:
		days_practised[k] = int(dp[k])
	var ld: Dictionary = d.get("last_day", {})
	for k: String in ld:
		_last_day[k] = int(ld[k])
