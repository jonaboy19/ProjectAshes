extends RefCounted
## A running log of life chapters: {start_day, end_day, role, org, rank, place,
## highlights: []}. Switching careers keeps this and reputation; nothing here
## is ever erased by a career change, only added to.
##
## Reputation is tracked per sphere (military, trade, craft, farming, faith,
## underworld) and, unlike a chapter, is not tied to any one career: a
## blacksmith-turned-soldier keeps what the guild thinks of their steel.
##
## Pure data (RefCounted, serialisable). autoload/life.gd drives it: opens a
## chapter on hiring/apprenticing, calls add_highlight() for notable deeds
## (a named kill, a masterwork sale, property bought) and promote() whenever
## career_ladders.gd promotes the player.

const RALifePath := preload("res://scripts/sim/life_path.gd")

const SPHERES: Array[String] = ["military", "trade", "craft", "farming", "faith", "underworld"]
## Chronological log kept in full; only the highlight list per chapter is capped.
const MAX_HIGHLIGHTS_PER_CHAPTER := 12

var chapters: Array[Dictionary] = []
var reputation: Dictionary = {}
var _current := -1


func _init() -> void:
	for s: String in SPHERES:
		reputation[s] = 0.0


func rep(sphere: String) -> float:
	return float(reputation.get(sphere, 0.0))


func change_rep(sphere: String, delta: float) -> float:
	if not reputation.has(sphere):
		reputation[sphere] = 0.0
	var v := clampf(rep(sphere) + delta, -100.0, 100.0)
	reputation[sphere] = v
	return v


func current_chapter() -> Dictionary:
	return chapters[_current] if _current >= 0 and _current < chapters.size() else {}


## Opens a new chapter, closing whatever was open. A call that matches the
## current chapter's role and org is a no-op (nothing changed about the life).
func start_chapter(role: String, org: String, rank: String, place: String, day: int) -> void:
	var cur := current_chapter()
	if not cur.is_empty() and String(cur["role"]) == role and String(cur["org"]) == org:
		return
	if not cur.is_empty() and int(cur["end_day"]) < 0:
		cur["end_day"] = day
	chapters.append({"start_day": day, "end_day": -1, "role": role, "org": org, "rank": rank,
		"place": place, "highlights": []})
	_current = chapters.size() - 1


## Ends the current chapter without opening a new one (retirement, dismissal).
func close_chapter(day: int) -> void:
	var cur := current_chapter()
	if not cur.is_empty() and int(cur["end_day"]) < 0:
		cur["end_day"] = day


func add_highlight(text: String, day: int) -> void:
	var cur := current_chapter()
	if cur.is_empty():
		return
	var h: Array = cur["highlights"]
	h.append({"text": text, "day": day})
	if h.size() > MAX_HIGHLIGHTS_PER_CHAPTER:
		h.pop_front()


## Records a promotion in the current chapter for `role` (opens one first if
## there is none, or the current one is a different role).
func promote(role: String, rank_id: String, rank_title: String, day: int, org := "", place := "") -> void:
	var cur := current_chapter()
	if cur.is_empty() or String(cur["role"]) != role:
		start_chapter(role, org, rank_id, place, day)
		cur = current_chapter()
	cur["rank"] = rank_id
	add_highlight("Promoted to %s" % rank_title, day)


## Whole in-game years spent (across every chapter) with this role.
func years_in_role(role: String, today: int) -> int:
	var total_days := 0
	for c: Dictionary in chapters:
		if String(c["role"]) != role:
			continue
		var end: int = int(c["end_day"]) if int(c["end_day"]) >= 0 else today
		total_days += maxi(0, end - int(c["start_day"]))
	return int(total_days / float(RALifePath.DAYS_PER_YEAR))


func all_highlights() -> Array:
	var out := []
	for c: Dictionary in chapters:
		for h: Dictionary in c.get("highlights", []):
			out.append({"text": h["text"], "day": h["day"], "role": c["role"]})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["day"]) < int(b["day"]))
	return out


## 3-6 lines summarising a life: time spent in its longest-held roles, its
## standout deeds, and how the world regards it.
func summary(today := -1) -> Array[String]:
	var out: Array[String] = []
	if chapters.is_empty():
		out.append("No life has been lived yet.")
		return out
	var day := today if today >= 0 else int(current_chapter().get("start_day", 0))
	var totals := {}
	for c: Dictionary in chapters:
		var role := String(c["role"])
		var end: int = int(c["end_day"]) if int(c["end_day"]) >= 0 else day
		totals[role] = int(totals.get(role, 0)) + maxi(0, end - int(c["start_day"]))
	var roles: Array = totals.keys()
	roles.sort_custom(func(a: String, b: String) -> bool: return int(totals[a]) > int(totals[b]))
	for role: String in roles.slice(0, 2):
		var yrs := years_in_role(role, day)
		out.append(("%d years as a %s." % [yrs, role.capitalize()]) if yrs > 0 else
			"A season spent as a %s." % role.capitalize())
	var cur := current_chapter()
	if not cur.is_empty():
		out.append("Now: %s of %s, rank %s." % [String(cur["role"]).capitalize(),
			String(cur["org"]) if String(cur["org"]) != "" else "no one", String(cur["rank"]).capitalize()])
	var deeds := all_highlights()
	for h: Dictionary in deeds.slice(maxi(0, deeds.size() - 2), deeds.size()):
		out.append(String(h["text"]) + ".")
	var best_sphere := ""
	var best_val := 0.0
	for s: String in SPHERES:
		if absf(rep(s)) > absf(best_val):
			best_val = rep(s)
			best_sphere = s
	if best_sphere != "" and absf(best_val) >= 10.0:
		var word := "well-regarded" if best_val > 0.0 else "distrusted"
		out.append("%s in %s circles." % [word.capitalize(), best_sphere])
	return out.slice(0, 6)


func serialize() -> Dictionary:
	return {"chapters": chapters.duplicate(true), "reputation": reputation.duplicate(), "current": _current}


func deserialize(d: Dictionary) -> void:
	chapters.clear()
	for c: Variant in d.get("chapters", []):
		var cc: Dictionary = c
		var hl: Array = []
		for h: Variant in cc.get("highlights", []):
			if h is Dictionary:
				hl.append({"text": String(h["text"]), "day": int(h["day"])})
			else:
				hl.append({"text": String(h), "day": int(cc.get("start_day", 0))})
		chapters.append({"start_day": int(cc.get("start_day", 0)), "end_day": int(cc.get("end_day", -1)),
			"role": String(cc.get("role", "")), "org": String(cc.get("org", "")),
			"rank": String(cc.get("rank", "")), "place": String(cc.get("place", "")), "highlights": hl})
	reputation.clear()
	for s: String in SPHERES:
		reputation[s] = 0.0
	var r: Dictionary = d.get("reputation", {})
	for s: String in r:
		reputation[s] = float(r[s])
	_current = int(d.get("current", chapters.size() - 1))
