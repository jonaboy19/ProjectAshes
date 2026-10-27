extends RefCounted
## Knowledge gating (WP-08): what a decider or a panel may know about somewhere else comes from news.gd / rumours.gd /
## war_intel.gd (road delay, sharpening, scouts), never from the truth held by sim modules. Pure static helpers over the
## hub modules passed in, so deciders and UI can call them without owning state.

const HUNGER_KINDS := ["harvest_failure", "famine"]
const HUNGER_MAX_AGE := 60            # days a famine report keeps a town off a mover's list
const WEARY_BANDS := ["fresh", "tiring", "weary", "spent"]


## True when `observer_sid` has heard of hunger in `town` (a famine item that originated there and has already arrived). Local hunger is felt, not heard.
static func heard_hunger(news: Variant, observer_sid: int, town: int, day := -1) -> float:
	if news == null:
		return 0.0
	if town == observer_sid:
		return -1.0                    # caller must use the local fact instead
	var best := 0.0
	for it: Array in news.heard_kinds(observer_sid, HUNGER_KINDS, day, 12):
		if int(it[0]) == town and int(it[3]) <= HUNGER_MAX_AGE:
			best = maxf(best, clampf(0.4 + 0.3 * float(it[1]), 0.0, 1.0))
	return best


## The enemy's war weariness as the viewer can know it: "" (nothing known) until a scout report has reached them, then a vague band.
static func enemy_weariness_label(war_intel: Variant, owner: String, enemy_exhaustion: float) -> String:
	if war_intel == null or owner == "":
		return ""
	var arrived := 0
	for r: Dictionary in war_intel.reports(owner):
		if String(r.get("fate", "")) != "lost":
			arrived += 1
	if arrived == 0:
		return ""
	var i := clampi(int(enemy_exhaustion * float(WEARY_BANDS.size())), 0, WEARY_BANDS.size() - 1)
	return String(WEARY_BANDS[i])


## Front/war lines a listener at `sid` may repeat: the war exists only for them once a news item of kind "war" has reached the town.
static func war_lines_heard(news: Variant, sid: int, lines: Array, day := -1) -> Array:
	if news == null or sid < 0:
		return lines
	if (news.heard_kinds(sid, ["war", "war_front", "battle"], day, 1) as Array).is_empty():
		return []
	return lines


## What a character knows of a distant subject, from their own remembered claims only (rumours.gd memories): [{kind, mag, conf}].
static func known_of(rumours: Variant, ch: String, subject: String) -> Array:
	var out: Array = []
	if rumours == null:
		return out
	for m: Dictionary in rumours.memories(ch):
		if String(m["subject"]) == subject:
			out.append({"kind": m["kind"], "mag": m["mag"], "conf": m["conf"]})
	return out
