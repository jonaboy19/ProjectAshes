class_name RACareerPosts
extends RefCounted
## WP-16: the healer, scholar, priest and assassin careers. Each has a JOIN path (a seat in an org, an
## enrolment, an ordination, a guild contract board) and an INDEPENDENT path earned by doing the work.
## Pure static helpers over RACareers, RAInjuries, the education/faith realm modules and trade_ranks.gd;
## nothing here owns state, so nothing needs saving.
##
## HEALER  join: the village herbalist's seats (register_healer_org + careers.apply). Seat holders treat
##         at half price (HEALER_STAFF_DISCOUNT). Independent: the "healer" ladder (herbalism + healing).
## SCHOLAR join: education.apply to a school. Independent: scholarship mastery makes a self-taught scholar.
## PRIEST  join: faith.ordain. Independent: a hedge priest (belief, no ordination) may only do the
##         PERMITTED_MINOR rites. Orders are PERMITTED or FORBIDDEN; breaking one costs belief + a scandal.
## ASSASSIN join: the guild's contract board (Knife seat + thief rank Master Thief). Independent: freelance
##         contracts from a fixer (thief rank Thief), paying 60%. Contracts are deterministic per day.

const CareerLadders := preload("res://scripts/sim/career_ladders.gd")

const HEALER_ORG := "herbalist"
const HEALER_STAFF_DISCOUNT := 0.5
const GUILD_ORG := "thieves_guild"
const THIEF_MASTER_RANK := 2     # index into trade_ranks.gd TRADES.thief.ranks
const THIEF_FREELANCE_RANK := 1
const SELF_TAUGHT_SCHOLARSHIP := 12

const PERMITTED_ORDERS := ["bless", "bury", "preach", "heal_prayer", "shelter", "wed", "hear_confession"]
const PERMITTED_MINOR := ["bless", "bury", "preach"]
const FORBIDDEN_ORDERS := ["kill_innocent", "steal_tithe", "take_bribe", "break_oath", "desecrate"]
const FORBIDDEN_BELIEF_LOSS := 12
const HEALER_RANKS := ["herbalist", "healer", "master_healer", "royal_physician"]
const CONTRACT_KINDS := ["rival_merchant", "corrupt_reeve", "deserter", "smuggler_snitch", "noble_agent"]


# ------------------------------------------------------------------ healer

## The village herbalist as an org with real seats (apprentice, then the post itself).
static func register_healer_org(careers: RACareers, settlement: int, post: Vector3) -> Dictionary:
	if not careers.org(HEALER_ORG).is_empty():
		return careers.org(HEALER_ORG)
	return careers.add_org(HEALER_ORG, "the Village Herbalist", settlement, "Herbalist", post, Vector2(8, 16), 0, [
		{"title": "Village Herbalist", "wage": 9, "count": 1, "command": 1, "merit": 8},
		{"title": "Herbalist's Apprentice", "wage": 4, "count": 2, "merit": 0},
	])


static func holds_healer_seat(careers: RACareers) -> bool:
	return careers.is_employed() and String(careers.player["org"]) == HEALER_ORG


## Healer rank id from the independent ladder (mastery and reputation only; time in rank is not checked).
static func healer_rank(mastery: Object, biography: Object = null) -> String:
	var rank: String = HEALER_RANKS[0]
	for i in range(1, HEALER_RANKS.size()):
		var req: Dictionary = CareerLadders.rank_def("healer", HEALER_RANKS[i]).get("requires", {})
		var ok := true
		for l: Dictionary in CareerLadders.lines(req, {"mastery": mastery, "biography": biography, "day": 9999, "since_day": 0}):
			var t := String(l["text"])
			if not bool(l["met"]) and not t.contains("sponsor"):
				ok = false
		if not ok:
			break
		rank = HEALER_RANKS[i]
	return rank


## Can this player run a treatment table? Seat holders and independent healers both can.
static func can_practise(careers: RACareers, mastery: Object) -> bool:
	return holds_healer_seat(careers) or healer_rank(mastery) != HEALER_RANKS[0]


## The menu for treating `injuries` at the herbalist's table. Seat holders get the staff discount.
static func healer_menu(injuries: RAInjuries, careers: RACareers) -> Array:
	var menu := injuries.healer_menu("herbalist")
	if holds_healer_seat(careers):
		for m: Dictionary in menu:
			if bool(m.get("ok", false)):
				m["cost"] = maxi(1, int(ceil(float(m["cost"]) * HEALER_STAFF_DISCOUNT)))
	return menu


# ------------------------------------------------------------------ scholar

## Join path: apply to a school (education.gd). Returns education.apply's result.
static func scholar_join(edu: Object, inst_id: String, route: String, ctx := {}) -> Dictionary:
	return edu.call("apply", inst_id, route, ctx)


static func is_scholar(edu: Object, mastery: Object) -> Dictionary:
	if edu != null:
		if bool(edu.call("is_student")):
			return {"scholar": true, "path": "student"}
		if String((edu.call("student_state") as Dictionary).get("status", "")) == "graduated":
			return {"scholar": true, "path": "graduate"}
	if mastery != null and int(mastery.call("level", "scholarship")) >= SELF_TAUGHT_SCHOLARSHIP:
		return {"scholar": true, "path": "self_taught"}
	return {"scholar": false, "path": ""}


# ------------------------------------------------------------------ priest

## Join path: ordain into a route (parish/cloister).
static func priest_join(faith: Object, ch: String, route: String) -> Dictionary:
	return faith.call("ordain", ch, route)


## May this person do `act`? Ordained clergy do every permitted order; a hedge priest only the minor ones.
static func check_order(faith: Object, ch: String, act: String) -> Dictionary:
	if act in FORBIDDEN_ORDERS:
		return {"ok": false, "forbidden": true, "reason": "Your order forbids it."}
	if not act in PERMITTED_ORDERS:
		return {"ok": false, "forbidden": false, "reason": "That is not a priest's work."}
	if not (faith.call("priest_step", ch) as Dictionary).is_empty():
		return {"ok": true, "forbidden": false, "reason": ""}
	var hedge := float(faith.call("belief_of", ch)) >= 20.0 and String(faith.call("faith_of", ch)) != "folk"
	if hedge and act in PERMITTED_MINOR:
		return {"ok": true, "forbidden": false, "reason": "A hedge priest, unordained."}
	return {"ok": false, "forbidden": false, "reason": "Only ordained clergy may do that."}


## Do a forbidden order anyway: belief falls and the town hears of it. Returns the belief lost.
static func break_order(faith: Object, ch: String, act: String, sid: int) -> int:
	if not act in FORBIDDEN_ORDERS:
		return 0
	var before := float(faith.call("belief_of", ch))
	faith.call("adjust_belief", ch, -float(FORBIDDEN_BELIEF_LOSS))
	faith.call("scandal", sid)
	return int(before - float(faith.call("belief_of", ch)))


# ------------------------------------------------------------------ assassin

static func register_guild_org(careers: RACareers, settlement: int, post: Vector3) -> Dictionary:
	if not careers.org(GUILD_ORG).is_empty():
		return careers.org(GUILD_ORG)
	return careers.add_org(GUILD_ORG, "the Shadow Guild", settlement, "Fence", post, Vector2(20, 28), 0, [
		{"title": "Knife", "wage": 12, "count": 2, "merit": 0},
	])


## Contracts open to the player on `day`: [{id, kind, target, pay, path}]. `ranks` is a trade_ranks.gd instance.
static func contracts(ranks: RefCounted, careers: RACareers, day: int, world_seed := 1066) -> Array:
	var r := int(ranks.ranks.get("thief", -1))
	var in_guild := careers.is_employed() and String(careers.player["org"]) == GUILD_ORG
	var path := ""
	if in_guild and r >= THIEF_MASTER_RANK:
		path = "guild"
	elif r >= THIEF_FREELANCE_RANK:
		path = "freelance"
	else:
		return []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([world_seed, day, "assassin"])
	var out: Array = []
	for i in 2 + (1 if path == "guild" else 0):
		var kind: String = CONTRACT_KINDS[rng.randi() % CONTRACT_KINDS.size()]
		var pay := 80 + rng.randi() % 120 + 40 * r
		if path == "freelance":
			pay = int(pay * 0.6)
		out.append({"id": "c%d_%d" % [day, i], "kind": kind, "target": kind.replace("_", " "), "pay": pay, "path": path})
	return out


## "" if the contract is open to the player, else the refusal.
static func can_take_contract(ranks: RefCounted, careers: RACareers, contract_id: String, day: int, world_seed := 1066) -> String:
	for c: Dictionary in contracts(ranks, careers, day, world_seed):
		if c["id"] == contract_id:
			return ""
	return "That contract is not open to you."
