extends RefCounted
## Career ladders: ranks with real requirements (mastery, reputation, time
## served in the current rank, property, money, an open seat, wartime, and
## political sponsorship). Reads data/careers/ladders.json.
##
## Promotion never grants free experience: eligibility is checked purely from
## what mastery.gd and biography.gd already recorded, plus a handful of world
## facts the caller supplies (gold, an open seat, whether the realm is at war).
## Pure static queries plus one static promote() that writes a biography entry;
## nothing here owns state of its own, so it needs no save/load.
##
## ctx for check_promotion() / promote():
##   {career, rank, since_day, day, mastery (RAMastery), biography (RABiography),
##    careers (RACareers) optional, gold, at_war, sponsor_tier (Relationships
##    tier_rank; >= 4 is "friend"), org, place,
##    <property flag>: bool, e.g. "owns_plot": true}
## Property requirements are plain ctx boolean flags (the caller already knows
## whether the player leases or owns a plot, a cart, a shop...), so this file
## never has to reach into homestead.gd or careers.gd itself.

const LADDERS_PATH := "res://data/careers/ladders.json"
const SPONSOR_TIER_NEEDED := 4     # Relationships.tier_rank("friend")

## Soldier-ladder rank id -> military.gd rank id, so pay and formation queries
## go through the one ladder military.gd already defines instead of a second one.
const SOLDIER_TO_MILITARY := {
	"militia": "recruit", "recruit": "recruit", "soldier": "soldier", "veteran": "veteran",
	"squad_leader": "tenwarden", "junior_officer": "company_second", "captain": "captain",
	"commander": "standard_commander", "general": "field_general",
}
## Player company size cap at each soldier-ladder rank (0, 5, 20, 60, 200...).
const SOLDIER_TROOPS := {
	"militia": 0, "recruit": 0, "soldier": 5, "veteran": 5,
	"squad_leader": 20, "junior_officer": 20, "captain": 60, "commander": 200, "general": 200,
}

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(LADDERS_PATH))
		_data = d if d is Dictionary else {}
	return _data


static func careers() -> Array[String]:
	var out: Array[String] = []
	for k: String in data():
		out.append(k)
	return out


static func ladder(career: String) -> Array:
	return (data().get(career, []) as Array)


static func rank_index(career: String, rank_id: String) -> int:
	var l := ladder(career)
	for i in l.size():
		if String(l[i]["id"]) == rank_id:
			return i
	return -1


static func rank_def(career: String, rank_id: String) -> Dictionary:
	var i := rank_index(career, rank_id)
	var l := ladder(career)
	return l[i] if i >= 0 else {}


static func next_rank_def(career: String, rank_id: String) -> Dictionary:
	var l := ladder(career)
	var i := rank_index(career, rank_id)
	if i < 0 or i + 1 >= l.size():
		return {}
	return l[i + 1]


static func first_rank(career: String) -> String:
	var l := ladder(career)
	return String(l[0]["id"]) if not l.is_empty() else ""


static func title_for(career: String, rank_id: String) -> String:
	return String(rank_def(career, rank_id).get("title", rank_id.capitalize()))


## Player company size cap for a soldier-ladder rank id.
static func troops_for_rank(rank_id: String) -> int:
	return int(SOLDIER_TROOPS.get(rank_id, 0))


static func military_rank_for(soldier_rank_id: String) -> String:
	return String(SOLDIER_TO_MILITARY.get(soldier_rank_id, "recruit"))


## Why `req` isn't met yet, as human-readable lines ([] means it is met).
static func _missing(req: Dictionary, ctx: Dictionary) -> PackedStringArray:
	var missing := PackedStringArray()
	var mastery: Object = ctx.get("mastery")
	var need_m: Dictionary = req.get("mastery", {})
	for disc: String in need_m:
		var lvl := int(mastery.call("level", disc)) if mastery else 0
		if lvl < int(need_m[disc]):
			missing.append("%s mastery %d (have %d)" % [String(disc).capitalize(), int(need_m[disc]), lvl])
	var biography: Object = ctx.get("biography")
	var need_rep: Dictionary = req.get("reputation", {})
	for sphere: String in need_rep:
		var have := float(biography.call("rep", sphere)) if biography else 0.0
		if have < float(need_rep[sphere]):
			missing.append("%s reputation %d (have %d)" % [String(sphere).capitalize(), int(need_rep[sphere]), int(have)])
	if req.has("days_in_rank"):
		var need_days := int(req["days_in_rank"])
		if bool(req.get("wartime_speeds", false)) and bool(ctx.get("at_war", false)):
			need_days = int(round(need_days * 0.5))
		var elapsed := int(ctx.get("day", 0)) - int(ctx.get("since_day", 0))
		if elapsed < need_days:
			missing.append("%d days in the current rank (have %d)" % [need_days, maxi(0, elapsed)])
	if req.has("money") and int(ctx.get("gold", 0)) < int(req["money"]):
		missing.append("%d gold (have %d)" % [int(req["money"]), int(ctx.get("gold", 0))])
	if req.has("property"):
		var flag := String(req["property"])
		if not bool(ctx.get(flag, false)):
			missing.append("%s" % flag.replace("_", " ").capitalize())
	if req.has("seat"):
		var seat_req: Dictionary = req["seat"]
		var careers_obj: Object = ctx.get("careers")
		if careers_obj:
			var seat: Dictionary = careers_obj.call("seat", String(seat_req["org"]), String(seat_req["title"]))
			if seat.is_empty() or int(careers_obj.call("open_count", seat)) <= 0:
				missing.append("An open %s post" % String(seat_req["title"]))
	if bool(req.get("sponsor", false)) and int(ctx.get("sponsor_tier", 0)) < SPONSOR_TIER_NEEDED:
		missing.append("A sponsor's support (a friend among your betters)")
	return missing


## {eligible, next: {id, title} or {}, missing: PackedStringArray}
static func check_promotion(ctx: Dictionary) -> Dictionary:
	var career := String(ctx.get("career", ""))
	var rank := String(ctx.get("rank", ""))
	var nxt := next_rank_def(career, rank)
	if nxt.is_empty():
		return {"eligible": false, "next": {}, "missing": PackedStringArray()}
	var missing := _missing(nxt.get("requires", {}), ctx)
	return {"eligible": missing.is_empty(), "next": {"id": nxt["id"], "title": nxt["title"]}, "missing": missing}


## Promotes if eligible, writing a biography entry. {ok, text, rank, missing}.
static func promote(ctx: Dictionary) -> Dictionary:
	var check := check_promotion(ctx)
	if not bool(check["eligible"]):
		return {"ok": false, "text": "Not yet ready.", "rank": String(ctx.get("rank", "")), "missing": check["missing"]}
	var nxt: Dictionary = check["next"]
	var biography: Object = ctx.get("biography")
	if biography:
		biography.call("promote", String(ctx.get("career", "")), String(nxt["id"]), String(nxt["title"]),
			int(ctx.get("day", 0)), String(ctx.get("org", "")), String(ctx.get("place", "")))
	return {"ok": true, "text": "Promoted to %s." % nxt["title"], "rank": String(nxt["id"]), "missing": PackedStringArray()}
