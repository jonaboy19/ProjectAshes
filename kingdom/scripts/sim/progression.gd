extends RefCounted
## The progression spine: character level 1-500 across the whole game.
##
## XP is awarded per activity (kill, discovery, quest, job_shift, craft, build, train, breakthrough, meditate,
## gather, lore, rift). An award is
##     xp_to_next(content_level) * activity.frac * magnitude
##        * diff_factor(player level vs content level)      (over-levelled content pays little)
##        * repetition decay (same activity+subject today; fades with days)
##        * region saturation (Region 1 pays sharply less past ~55 and nothing at its hard cap)
## so XP is always "a share of a level of the content you are doing", and a player cannot shortcut a region
## by grinding one thing. Numbers live in data/progression/levels.json. Level matters less than
## cultivation and gear: level only adds modest base stats + attribute points (power_share()).
##
## Pure data (RefCounted, serialisable, no RNG). Owned by the `cultivation` realm module
## (hub.mod("cultivation").prog) so it saves with the realm; Life hooks call award().

signal level_up(new_level: int)

const DATA_PATH := "res://data/progression/levels.json"
const ATTRS := ["strength", "dexterity", "endurance", "intelligence", "wisdom", "charisma"]

static var _data: Dictionary = {}
static var _cum: PackedFloat64Array = PackedFloat64Array()

var xp: float = 0.0
var level: int = 1
var spent: Dictionary = {}          # attribute id -> points spent
var _rep: Dictionary = {}           # "activity|subject" -> [count, day]
var _seen: Dictionary = {}          # one-time ids already paid
var last_region: String = "region1"
var earned_by: Dictionary = {}      # activity -> total xp (for the UI / balance)


static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open(DATA_PATH, FileAccess.READ)
		_data = JSON.parse_string(f.get_as_text()) if f != null else {}
		var t: Array = _data.get("xp_to_next", [])
		_cum = PackedFloat64Array()
		_cum.resize(t.size() + 2)
		var run := 0.0
		for i in t.size():
			_cum[i + 1] = run     # _cum[L] = total xp needed to *be* level L  (L>=1)
			run += float(t[i])
		_cum[t.size() + 1] = run
	return _data


static func max_level() -> int:
	return int(data().get("max_level", 500))


## XP needed to go from `lv` to `lv`+1 (0 at the cap).
static func xp_to_next(lv: int) -> float:
	var t: Array = data().get("xp_to_next", [])
	if lv < 1:
		lv = 1
	if lv > t.size():
		return 0.0
	return float(t[lv - 1])


## Total XP at which level `lv` begins.
static func total_xp(lv: int) -> float:
	data()
	lv = clampi(lv, 1, max_level())
	return _cum[lv]


static func level_for_xp(total: float) -> int:
	data()
	var lo := 1
	var hi := max_level()
	while lo < hi:
		var mid := (lo + hi + 1) / 2
		if total >= _cum[mid]:
			lo = mid
		else:
			hi = mid - 1
	return lo


static func region(id: String) -> Dictionary:
	for r: Dictionary in data().get("regions", []):
		if r["id"] == id:
			return r
	return (data().get("regions", [{}]) as Array)[0]


## 1.0 up to soft_start, easing to 0.6 at soft_cap, then a sharp fall; 0 at the hard cap.
static func region_saturation(region_id: String, lv: int) -> float:
	var r := region(region_id)
	var s0 := int(r.get("soft_start", 50))
	var s1 := int(r.get("soft_cap", 55))
	var hard := int(r.get("hard_cap", 60))
	if lv >= hard:
		return 0.0
	if lv <= s0:
		return 1.0
	if lv <= s1:
		return lerpf(1.0, 0.6, float(lv - s0) / float(maxi(1, s1 - s0)))
	return maxf(float(r.get("sat_floor", 0.01)), 0.6 * pow(float(r.get("sat_step", 0.25)), float(lv - s1)))


## Pace curve: xp multiplier by content level, so early levels come quicker and each later level takes more hours.
static func pace_mult(content_level: int) -> float:
	var p: Dictionary = data().get("pace", {})
	var end_l := float(p.get("end_level", 55))
	var l := float(content_level)
	if l <= end_l:
		return lerpf(float(p.get("start", 1.0)), float(p.get("end", 1.0)), (l - 1.0) / maxf(1.0, end_l - 1.0))
	return float(p.get("end", 1.0)) * pow(end_l / l, float(p.get("beyond_exp", 0.5)))


## Over-levelled content pays less, content above your level pays a little more.
static func diff_factor(player_level: int, content_level: int) -> float:
	var d: Dictionary = data().get("diff", {})
	var gap := player_level - content_level
	if gap > 0:
		return maxf(float(d.get("over_floor", 0.05)), 1.0 - float(d.get("over_per_level", 0.1)) * gap)
	return minf(float(d.get("under_max", 1.4)), 1.0 + float(d.get("under_bonus_per_level", 0.04)) * -gap)


## Base stats a level gives. Deliberately modest: gear and cultivation are the big multipliers.
static func stats_for(lv: int, attrs: Dictionary = {}) -> Dictionary:
	var s: Dictionary = data().get("stats", {})
	var l := float(maxi(1, lv) - 1)
	var end := float(attrs.get("endurance", 0))
	var str_ := float(attrs.get("strength", 0))
	return {
		"hp": int(float(s.get("hp_base", 100)) + float(s.get("hp_per_level", 7)) * l + end * 4.0),
		"stamina": int(float(s.get("stamina_base", 80)) + float(s.get("stamina_per_level", 1.5)) * l + end * 2.0),
		"attack": snappedf(6.0 + float(s.get("attack_per_level", 0.6)) * l + str_ * 0.8, 0.1),
		"defense": snappedf(2.0 + float(s.get("defense_per_level", 0.45)) * l + end * 0.3, 0.1),
	}


## Total attribute points a character has earned by level `lv`.
static func points_earned(lv: int) -> int:
	var s: Dictionary = data().get("stats", {})
	var every := int(s.get("attr_bonus_every", 5))
	return (maxi(1, lv) - 1) * int(s.get("attr_points_per_level", 1)) + int(s.get("attr_bonus", 2)) * (lv / every)


## Small multiplier a level adds to power (cultivation and gear multiply on top).
static func power_share(lv: int) -> float:
	return 1.0 + float(data().get("stats", {}).get("power_per_level", 0.006)) * float(maxi(1, lv) - 1)


static func title_for(lv: int) -> String:
	var out := "Newcomer"
	for t: Array in data().get("titles", []):
		if lv >= int(t[0]):
			out = String(t[1])
	return out


# ------------------------------------------------------------------ instance ----

func points_unspent() -> int:
	var used := 0
	for a: String in spent:
		used += int(spent[a])
	return points_earned(level) - used


func spend_point(attr: String) -> bool:
	if not ATTRS.has(attr) or points_unspent() <= 0:
		return false
	spent[attr] = int(spent.get(attr, 0)) + 1
	return true


func stats() -> Dictionary:
	return stats_for(level, spent)


## {level, into, needed, ratio, title, total}
func info() -> Dictionary:
	var lo := total_xp(level)
	var need := xp_to_next(level)
	var into := xp - lo
	return {"level": level, "into": into, "needed": need, "total": xp, "title": title_for(level),
		"ratio": 1.0 if need <= 0.0 else clampf(into / need, 0.0, 1.0)}


## The repetition factor the next award of (activity, subject) would get on `day`, without recording it.
func repetition_factor(activity: String, subject: String, day: int) -> float:
	var a: Dictionary = data().get("activities", {}).get(activity, {})
	if a.is_empty():
		return 0.0
	var e: Array = _rep.get(activity + "|" + subject, [0.0, day])
	var count := float(e[0]) * pow(1.0 - float(a.get("recover", 0.5)), maxf(0.0, float(day - int(e[1]))))
	return maxf(float(a.get("floor", 0.05)), pow(float(a.get("decay", 1.0)), count))


## Pay XP for an activity. ctx: region (default region1), content_level (default = player level),
## subject (what you did it to: species, recipe, job...), id (one-time id: quest/place), magnitude, day, mult.
## -> {xp, factors:{...}, levels_gained, level, capped, reason}
func award(activity: String, ctx: Dictionary = {}) -> Dictionary:
	var acts: Dictionary = data().get("activities", {})
	var res := {"xp": 0.0, "levels_gained": 0, "level": level, "capped": false, "reason": "", "factors": {}}
	if not acts.has(activity):
		res["reason"] = "unknown"
		return res
	var a: Dictionary = acts[activity]
	var day := int(ctx.get("day", 0))
	var region_id := String(ctx.get("region", "region1"))
	last_region = region_id
	var subject := String(ctx.get("subject", ""))
	var id := String(ctx.get("id", ""))
	var fresh := id != "" and not _seen.has(activity + "#" + id)
	if id != "" and not fresh and bool(a.get("once", false)):
		res["reason"] = "already_done"
		return res
	var content := clampi(int(ctx.get("content_level", level)), 1, max_level())
	var sat := region_saturation(region_id, level)
	var diff := diff_factor(level, content)
	var rep := 1.0 if fresh else repetition_factor(activity, subject, day)
	if not fresh or id == "":
		_bump(activity, subject, day)
	if fresh:
		_seen[activity + "#" + id] = true
	res["factors"] = {"saturation": sat, "diff": diff, "repeat": rep}
	if level >= max_level():
		res["capped"] = true
		res["reason"] = "max_level"
		return res
	if sat <= 0.0:
		res["capped"] = true
		res["reason"] = "region_cap"
		return res
	var gain := xp_to_next(content) * float(a.get("frac", 0.0)) * float(ctx.get("magnitude", 1.0)) \
		* diff * rep * sat * pace_mult(content) * float(data().get("global_scale", 1.0)) * float(ctx.get("mult", 1.0))
	gain = maxf(0.0, gain)
	var before := level
	_add(gain)
	earned_by[activity] = float(earned_by.get(activity, 0.0)) + gain
	res["xp"] = gain
	res["level"] = level
	res["levels_gained"] = level - before
	return res


func _bump(activity: String, subject: String, day: int) -> void:
	var a: Dictionary = data().get("activities", {}).get(activity, {})
	var key := activity + "|" + subject
	var e: Array = _rep.get(key, [0.0, day])
	var count := float(e[0]) * pow(1.0 - float(a.get("recover", 0.5)), maxf(0.0, float(day - int(e[1]))))
	_rep[key] = [count + 1.0, day]


## Raw XP (quests that name an amount, tests). Bypasses the activity model but not the level cap.
func _add(amount: float) -> void:
	xp += amount
	var before := level
	level = level_for_xp(xp)
	if level > before:
		for l in range(before + 1, level + 1):
			level_up.emit(l)


func grant_raw(amount: float) -> void:
	if level < max_level():
		_add(maxf(0.0, amount))


func prune(day: int) -> void:
	for k: String in _rep.keys():
		var e: Array = _rep[k]
		if day - int(e[1]) > 14:
			_rep.erase(k)


func serialize() -> Dictionary:
	return {"xp": xp, "level": level, "spent": spent.duplicate(), "rep": _rep.duplicate(true), "seen": _seen.duplicate(),
		"region": last_region, "earned": earned_by.duplicate()}


func deserialize(d: Dictionary) -> void:
	xp = float(d.get("xp", 0.0))
	level = level_for_xp(xp)
	spent = {}
	for k in (d.get("spent", {}) as Dictionary):
		if ATTRS.has(String(k)):
			spent[String(k)] = int(d["spent"][k])
	_rep = {}
	for k in (d.get("rep", {}) as Dictionary):
		var e: Array = d["rep"][k]
		_rep[String(k)] = [float(e[0]), int(e[1])]
	_seen = (d.get("seen", {}) as Dictionary).duplicate()
	last_region = String(d.get("region", "region1"))
	earned_by = (d.get("earned", {}) as Dictionary).duplicate()
