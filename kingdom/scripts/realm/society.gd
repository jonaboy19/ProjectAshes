extends "res://scripts/realm/realm_module.gd"
## Society (docs/design/LIVING_WORLD.md L§20-34, L§36-41, L§46, L§48).
##
## Pure data, deterministic (seed = hash([WorldSim.SEED, tag, day, id])) and
## JSON-safe. Only ~200 notable NPCs get full records; everyone else is a
## statistic (witness counts, crowds). Notable NPCs are generated lazily.
##
## Money rule: like city_life, this module never touches the real purse. It
## adds to a signed ledger and the game calls take_pending_gold().
##
## Reputation is per group ("city:<sid>", "district:<sid>:<name>", "guild:<id>",
## "faction:<id>") and public; criminal reputation ("underworld", "city:<sid>")
## is a separate ledger: a feared assassin can be a stranger to the law.
##
## Cross-module (guarded): city_life.note_activity / on_fact, factions.on_marriage,
## life.relationships.reputation (mirrored read-only into "faction:<id>").

const NPC_COUNT := 200
const TIER_NAMES := ["commoner", "trained", "veteran", "elite", "master", "grandmaster", "champion", "legend"]
const REP_TIERS := [[-60.0, "Reviled"], [-30.0, "Distrusted"], [-10.0, "Suspect"], [10.0, "Unknown"], [30.0, "Known"],
	[60.0, "Respected"], [85.0, "Renowned"], [1000.0, "Revered"]]
const DIMS := ["trust", "affection", "respect", "fear", "attraction", "loyalty", "resentment", "familiarity", "debt"]
const OCCUPATIONS := [["farmhand", "labourer", "peddler", "fisher"], ["smith", "weaver", "baker", "guard", "hunter", "scribe"],
	["merchant", "captain", "priest", "physician", "master craftsman"], ["knight", "magistrate", "guildmaster", "landed gentry"], ["lord", "lady", "prince"]]
const CULTURES := {
	"martial": {"combat": 0.35, "wealth": 0.1, "fame": 0.2, "title": 0.1, "family": 0.1, "occupation": 0.15, "duels": "celebrated"},
	"mercantile": {"combat": 0.05, "wealth": 0.4, "fame": 0.1, "title": 0.15, "family": 0.1, "occupation": 0.2, "duels": "forbidden"},
	"pious": {"combat": 0.1, "wealth": 0.05, "fame": 0.1, "title": 0.1, "family": 0.3, "occupation": 0.35, "duels": "forbidden"},
	"courtly": {"combat": 0.1, "wealth": 0.2, "fame": 0.15, "title": 0.35, "family": 0.15, "occupation": 0.05, "duels": "allowed"},
}
const RELIGIONS := ["dawn", "old_gods", "none"]
const LIFESTYLES := ["homebody", "adventurous", "scholarly", "martial", "social"]
const ACTIVITIES := ["meal", "festival", "walk", "hunt", "boat ride", "training session", "religious ceremony", "market trip"]
const DEED_TEXT := {
	"monster_kill": ["%s slew %s beasts near the road", "%s hunted down about %s monsters", "%s killed a horde of %s monsters single-handed"],
	"rescue": ["%s pulled %s travellers from trouble", "%s saved about %s people", "%s saved whole villages, %s of them"],
	"donation": ["%s gave %s gold to the poor", "%s handed out about %s gold in alms", "%s gave away a fortune, %s gold or more"],
	"duel_won": ["%s won a duel over %s gold", "%s beat a famed swordsman for about %s gold", "%s cut down a champion, %s gold on the wager"],
	"crime": ["%s was seen doing something ugly (%s witnesses)", "%s is said to have broken the law, with about %s witnesses", "%s is a terror; %s people swear it"],
	"generic": ["%s did a great thing (%s)", "%s did something remarkable (about %s)", "%s did a legend's work (%s)"],
}
const CRIMES := {
	"pickpocket": {"sev": 1, "report": 0.35, "fine": 15, "evidence": ["witness_statement"], "under": 1.0},
	"robbery": {"sev": 3, "report": 0.7, "fine": 60, "evidence": ["witness_statement", "footprints", "stolen_goods"], "under": 2.0},
	"fraud": {"sev": 2, "report": 0.45, "fine": 45, "evidence": ["forged_document"], "under": 1.5},
	"smuggling": {"sev": 2, "report": 0.3, "fine": 70, "evidence": ["contraband"], "under": 3.0},
	"burglary": {"sev": 3, "report": 0.6, "fine": 55, "evidence": ["footprints", "stolen_goods"], "under": 2.0},
	"murder": {"sev": 6, "report": 0.95, "fine": 400, "evidence": ["blood", "weapon", "witness_statement", "footprints"], "under": 4.0},
	"black_market": {"sev": 2, "report": 0.2, "fine": 40, "evidence": ["contraband"], "under": 2.5},
	"assault": {"sev": 2, "report": 0.6, "fine": 30, "evidence": ["blood", "witness_statement"], "under": 0.5},
}
const EVIDENCE_DECAY := {"blood": 0.03, "footprints": 0.2, "stolen_goods": 0.006, "witness_statement": 0.03, "weapon": 0.01,
	"forged_document": 0.01, "contraband": 0.01}
const OUTFITS := {
	"rags": {"class": 0}, "travel": {"class": 1}, "common": {"class": 1}, "merchant": {"class": 2}, "guild_uniform": {"class": 2},
	"military": {"class": 2}, "religious": {"class": 2}, "noble": {"class": 3}, "royal": {"class": 4}, "mask": {"class": 1},
}
const GOALS := ["become_wealthy", "join_army", "find_someone", "become_master", "protect_family", "gain_power", "travel", "kill_monster", "revenge"]
const GOAL_STEPS := {"become_wealthy": 4, "join_army": 3, "find_someone": 4, "become_master": 5, "protect_family": 3, "gain_power": 5,
	"travel": 2, "kill_monster": 3, "revenge": 3}
const DEED_WEIGHT := {"helped": 4.0, "robbed": -6.0, "saved_child": 9.0, "killed_kin": -10.0, "abandoned": -5.0, "paid_debt": 3.0,
	"trained_together": 2.5, "insulted": -2.0, "gifted": 1.5, "betrayed": -8.0, "threatened": -3.0}
const INTERACT := {
	"talk": {"familiarity": 2.0, "trust": 0.5},
	"gift": {"affection": 3.0, "familiarity": 1.0, "debt": -2.0},
	"help": {"trust": 4.0, "respect": 2.0, "affection": 2.0, "debt": -5.0},
	"insult": {"resentment": 9.0, "respect": -4.0, "affection": -4.0},
	"threaten": {"fear": 9.0, "resentment": 6.0, "trust": -6.0},
	"flirt": {"attraction": 4.0, "familiarity": 1.0},
	"save_child": {"trust": 20.0, "affection": 15.0, "loyalty": 12.0, "debt": -25.0},
	"betray": {"trust": -30.0, "resentment": 20.0, "affection": -15.0, "loyalty": -20.0},
	"pay_debt": {"trust": 6.0, "respect": 4.0, "debt": 30.0},
	"train_together": {"respect": 5.0, "familiarity": 3.0, "affection": 2.0},
	"abandon": {"trust": -12.0, "resentment": 8.0, "loyalty": -10.0},
	"kill_kin": {"resentment": 40.0, "affection": -30.0, "trust": -20.0, "fear": 15.0},
}
const KIND_DEED := {"help": "helped", "save_child": "saved_child", "betray": "betrayed", "pay_debt": "paid_debt", "abandon": "abandoned",
	"kill_kin": "killed_kin", "insult": "insulted", "threaten": "threatened", "gift": "gifted", "train_together": "trained_together"}
const FAMILY_REQUESTS := ["a brother is in debt", "a cousin has been jailed", "an old feud has flared", "a father is sick", "a sister needs a dowry"]
const MASTER_TERMS := ["money", "respect", "service", "talent", "recommendation"]
const PROBLEM_FIX := {"absence": "spend_time", "money": "gift", "jealousy": "apologize", "danger": "change_job", "ambition": "compromise",
	"religion": "compromise", "war": "spend_time"}
const RUMOUR_SPEED := 25.0     # world units per rumour-hour (carriers wait for company)
const RUMOUR_FANOUT := 2
const RUMOUR_TTL_H := 24.0 * 60.0
const SYL_A := ["Al", "Bre", "Cor", "Dar", "El", "Fen", "Gil", "Har", "Ise", "Jor", "Kel", "Lor", "Mar", "Nor", "Ori", "Pel", "Ren", "Sel", "Tor", "Ulf"]
const SYL_B := ["ric", "na", "dan", "wen", "mund", "la", "gar", "ith", "os", "ra", "vin", "el", "bert", "ly"]
const SURN := ["Ashby", "Brook", "Crane", "Dunn", "Ember", "Fallow", "Gray", "Hale", "Ironside", "Marsh", "Nettle", "Oakes", "Pike", "Reed", "Stone", "Thorne"]

var player: Dictionary = {"combat": 10, "gold": 0, "fame": 0, "title": 0, "family": 0, "class": 1, "age": 20, "sex": "m",
	"values": {"honor": 0.5, "wealth": 0.5, "tradition": 0.5, "freedom": 0.5}, "personality": {"kindness": 0.5, "temper": 0.5, "ambition": 0.5, "openness": 0.5},
	"lifestyle": "adventurous", "religion": "none", "culture": "martial", "career": "", "politics": "crown", "wants_children": true,
	"land": false, "wealth_score": 0, "refs": 0, "skills": {}, "dangerous": true, "achievements": 0, "sid": 0}
var pending_gold: int = 0
var reputation: Dictionary = {}
var crim: Dictionary = {}
var _rep_log: Array = []
var npcs: Dictionary = {}          # id -> record
var houses: Dictionary = {}        # id -> {id, name, head, members, class, sid}
var feuds: Array = []              # [[house, house]]
var courtship: Dictionary = {}     # npc -> {dates, stage, last_date}
var marriage: Dictionary = {}      # {} or {spouse, day, happiness, problems, status, children, last_together}
var in_law_requests: Array = []
var outfit: Dictionary = {"kind": "travel", "dirty": true, "disguise": 0.0}
var crimes: Array = []             # crime records
var evidence_items: Array = []
var investigations: Array = []
var bounties: Dictionary = {}      # str(sid) -> amount
var rumour_list: Array = []
var _hops: Array = []
var stories: Array = []
var _pending_msgs: Array = []
var knowledge: Dictionary = {}     # fact -> {day, text}
var offers_list: Array = []
var apprenticeship: Dictionary = {}
var students: Array = []
var student_requests_list: Array = []
var _next_id: int = 1
var _day: int = 0
var _hour: int = 8
var _now: float = 0.0
var _season: String = "spring"
var _at_war: bool = false
var _near_sid: int = -1
var _gold_seen: int = 0
var _nbrs: Dictionary = {}
var _nbr_sig: int = -1
var _fame_cache: Dictionary = {}
var _has_npcs: bool = false
var _school: bool = false
var _taught_today: bool = false
var _attended_today: bool = false


# ---------------------------------------------------------------- helpers

func _rng(tag: String, day: int, id: Variant) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash([WorldSim.SEED, tag, day, id])
	return r


func _city() -> RefCounted:
	if hub != null:
		var m: RefCounted = hub.mod("city_life")
		if m != null:
			return m
	return null


func _pick(r: RandomNumberGenerator, arr: Array) -> Variant:
	return arr[r.randi() % arr.size()]


func set_player(d: Dictionary) -> void:
	for k: String in d:
		player[k] = d[k]


func take_pending_gold() -> int:
	var g := pending_gold
	pending_gold = 0
	return g


func _gold() -> int:
	return int(player.get("gold", 0)) + pending_gold


func _sname(sid: int) -> String:
	if sid >= 0 and sid < WorldGen.settlements.size():
		return String(WorldGen.settlements[sid]["name"])
	return "the road"


func _new_id(prefix: String) -> String:
	var s := "%s%d" % [prefix, _next_id]
	_next_id += 1
	return s


func _sync(ctx: Dictionary) -> void:
	_now = float(ctx.get("abs_hours", _now))
	_at_war = bool(ctx.get("at_war", false))
	_season = String(ctx.get("season", _season))
	if ctx.has("gold"):
		player["gold"] = int(ctx["gold"])
	if ctx.get("stats") is Dictionary:
		for k: String in ctx["stats"]:
			player[k] = ctx["stats"][k]
	var pp: Variant = ctx.get("player_pos")
	if pp is Vector2 or pp is Vector3:
		var p2: Vector2 = Vector2(pp.x, pp.z) if pp is Vector3 else pp
		_near_sid = _nearest(p2)
		player["sid"] = maxi(0, _near_sid)


func _nearest(p: Vector2) -> int:
	var best := -1
	var bd := INF
	for s: Dictionary in WorldGen.settlements:
		var d: float = (s["pos"] as Vector2).distance_squared_to(p)
		if d < bd:
			bd = d
			best = int(s["id"])
	if best >= 0 and bd > pow(float(WorldGen.settlements[best].get("radius", 100.0)) * 2.5, 2.0):
		return -1
	return best


func _mirror_life(ctx: Dictionary) -> void:
	var life: Variant = ctx.get("life")
	if life == null or not (life is Object):
		return
	var rel: Variant = life.get("relationships")
	if rel == null or not (rel is Object):
		return
	var rmap: Variant = rel.get("reputation")
	if rmap is Dictionary:
		for f: Variant in rmap:
			reputation["faction:" + String(f)] = clampf(float(rmap[f]), -100.0, 100.0)


func _flush() -> Array:
	var out := _pending_msgs.duplicate()
	_pending_msgs.clear()
	return out


func _say(msgs: Array, t: String) -> void:
	msgs.append(t)


# ------------------------------------------------- L§21 reputation tiers

func rep(group: String) -> float:
	return float(reputation.get(group, 0.0))


func rep_tier(group: String) -> String:
	var v := rep(group)
	for t: Array in REP_TIERS:
		if v < float(t[0]):
			return String(t[1])
	return "Revered"


func add_rep(group: String, delta: float, reason: String = "") -> float:
	var v := clampf(rep(group) + delta, -100.0, 100.0)
	reputation[group] = v
	if group.begins_with("district:"):
		var parts := group.split(":")
		if parts.size() >= 3:
			var cg := "city:" + parts[1]
			reputation[cg] = clampf(rep(cg) + delta * 0.3, -100.0, 100.0)
	_rep_log.append({"g": group, "d": delta, "why": reason, "day": _day})
	if _rep_log.size() > 20:
		_rep_log.pop_front()
	return v


func rep_log() -> Array:
	return _rep_log.duplicate(true)


func crim_rep(group: String = "underworld") -> float:
	return float(crim.get(group, 0.0))


func add_crim_rep(group: String, delta: float, _reason: String = "") -> float:
	crim[group] = clampf(crim_rep(group) + delta, -100.0, 100.0)
	if group.begins_with("city:") and delta > 0.0:
		crim["underworld"] = clampf(crim_rep("underworld") + delta * 0.5, -100.0, 100.0)
	return float(crim[group])


func crim_tier(group: String = "underworld") -> String:
	var v := crim_rep(group)
	if v < 5.0:
		return "nobody"
	if v < 20.0:
		return "petty name"
	if v < 45.0:
		return "known operator"
	if v < 75.0:
		return "feared"
	return "legendary"


func fame_at(sid: int) -> float:
	if _fame_cache.has(sid):
		return float(_fame_cache[sid])
	var f := float(player.get("fame", 0)) * 0.5
	for r: Dictionary in rumour_list:
		if r["subject"] == "player" and (r["heard"] as Dictionary).has(str(sid)):
			f += float(r["mag"]) * float(r["tone"]) * float(r["heard"][str(sid)]["f"]) * 0.5
	_fame_cache[sid] = f
	return f


# --------------------------------------------------- L§20 NPC tiers

func tier_name(t: int) -> String:
	return TIER_NAMES[clampi(t, 1, 8) - 1]


func player_tier() -> int:
	return clampi(1 + int(float(player.get("combat", 0)) / 13.0), 1, 8)


func npc_tier(npc: String) -> int:
	_ensure_npcs()
	return int(npcs.get(npc, {}).get("tier", 1))


func tier_access(npc: String) -> Dictionary:
	## What a gap in power means socially: teaching, duels, respect.
	_ensure_npcs()
	var n: Dictionary = npcs.get(npc, {})
	if n.is_empty():
		return {}
	var gap := int(n["tier"]) - player_tier()
	return {"gap": gap, "will_teach": gap < 3 or _rel_dim(npc, "respect") >= 30.0, "will_duel": gap <= 2,
		"respect_for_player": gap <= 0, "access": "open" if gap < 3 else "guarded", "npc_tier": tier_name(int(n["tier"]))}


func npc_regard(npc: String) -> float:
	## How much this NPC's culture rates the player (0..100): combat, wealth, fame...
	_ensure_npcs()
	var n: Dictionary = npcs.get(npc, {})
	if n.is_empty():
		return 0.0
	var w: Dictionary = CULTURES[n["culture"]]
	var achieved := clampf(float(player.get("achievements", 0)) / 10.0, 0.0, 1.0)
	var s := 0.0
	s += float(w["combat"]) * clampf(float(player.get("combat", 0)) / 100.0, 0.0, 1.0)
	s += float(w["wealth"]) * clampf(float(player.get("wealth_score", player.get("gold", 0))) / 1000.0, 0.0, 1.0)
	s += float(w["fame"]) * clampf(fame_at(int(n["sid"])) / 100.0, 0.0, 1.0)
	s += float(w["title"]) * clampf(float(player.get("title", 0)) / 4.0, 0.0, 1.0)
	s += float(w["family"]) * clampf(float(player.get("family", 0)) / 3.0, 0.0, 1.0)
	s += float(w["occupation"]) * (0.7 if String(player.get("career", "")) != "" else 0.2)
	s += 0.1 * achieved
	return snappedf(s * 100.0, 0.1)


# ------------------------------------------------------------- NPC roster

func _npc_name(r: RandomNumberGenerator, surname: String) -> String:
	return "%s%s %s" % [_pick(r, SYL_A), _pick(r, SYL_B), surname]


func _ensure_npcs() -> void:
	if _has_npcs:
		return
	_has_npcs = true
	var sett: Array = WorldGen.settlements
	if sett.is_empty():
		return
	var total := 0
	for s: Dictionary in sett:
		total += int(s.get("population", 100))
	var hi := 0
	var house_left := 0
	var cur_house := ""
	for i in NPC_COUNT:
		var r := _rng("npc", 0, i)
		# Settlement weighted by population (deterministic ladder over the roll).
		var roll := r.randi() % maxi(1, total)
		var sid := 0
		var acc := 0
		for s: Dictionary in sett:
			acc += int(s.get("population", 100))
			if roll < acc:
				sid = int(s["id"])
				break
		if house_left <= 0:
			hi += 1
			cur_house = "h%d" % hi
			house_left = 2 + r.randi() % 3
			var sn: String = _pick(r, SURN)
			houses[cur_house] = {"id": cur_house, "name": sn, "head": "", "members": [], "sid": sid, "class": 0}
		house_left -= 1
		var h: Dictionary = houses[cur_house]
		var klass := 0
		var cr := r.randf()
		klass = 0 if cr < 0.45 else (1 if cr < 0.8 else (2 if cr < 0.93 else (3 if cr < 0.985 else 4)))
		if int(h["class"]) < klass:
			h["class"] = klass
		var id := "n%d" % i
		var tier := clampi(1 + klass + (r.randi() % 3) - 1, 1, 8)
		if r.randf() < 0.03:
			tier = mini(8, tier + 3)
		var cul: String = _pick(r, CULTURES.keys())
		var occ_list: Array = OCCUPATIONS[mini(klass, 4)]
		npcs[id] = {"id": id, "name": _npc_name(r, String(h["name"])), "sid": int(h["sid"]), "sex": "f" if r.randf() < 0.5 else "m",
			"age": 16 + r.randi() % 55, "class": klass, "job": _pick(r, occ_list), "tier": tier, "culture": cul,
			"religion": _pick(r, RELIGIONS), "lifestyle": _pick(r, LIFESTYLES), "house": cur_house, "spouse": "",
			"pers": {"kindness": snappedf(r.randf(), 0.01), "temper": snappedf(r.randf(), 0.01), "loyalty": snappedf(r.randf(), 0.01),
				"ambition": snappedf(r.randf(), 0.01), "honor": snappedf(r.randf(), 0.01), "jealousy": snappedf(r.randf(), 0.01),
				"forgiveness": snappedf(r.randf(), 0.01), "piety": snappedf(r.randf(), 0.01), "openness": snappedf(r.randf(), 0.01)},
			"likes": [_pick(r, ACTIVITIES), _pick(r, ACTIVITIES)], "goals": [], "memory": [], "rel": {}, "alive": true}
		(npcs[id]["goals"] as Array).append(_new_goal(r, id))
		(h["members"] as Array).append(id)
		if String(h["head"]) == "":
			h["head"] = id
	# A few standing feuds between houses.
	var hkeys: Array = houses.keys()
	var fr := _rng("feud", 0, 0)
	for i in mini(6, hkeys.size() / 2):
		var a: String = hkeys[fr.randi() % hkeys.size()]
		var b: String = hkeys[fr.randi() % hkeys.size()]
		if a != b:
			feuds.append([a, b])


func _new_goal(r: RandomNumberGenerator, _npc: String) -> Dictionary:
	var g: String = _pick(r, GOALS)
	return {"type": g, "step": 0, "steps": int(GOAL_STEPS[g]), "target": "" if g != "find_someone" else "n%d" % (r.randi() % NPC_COUNT)}


func npc(id: String) -> Dictionary:
	_ensure_npcs()
	return (npcs.get(id, {}) as Dictionary).duplicate(true)


func npcs_in(sid: int) -> Array:
	_ensure_npcs()
	var out: Array = []
	for k: String in npcs:
		if int(npcs[k]["sid"]) == sid and bool(npcs[k]["alive"]):
			out.append(k)
	out.sort()
	return out


func notable_count() -> int:
	_ensure_npcs()
	return npcs.size()


# ------------------------------------------------- L§24 relationships

func _rel_dim(npc_id: String, dim: String) -> float:
	var n: Dictionary = npcs.get(npc_id, {})
	if n.is_empty():
		return 0.0
	return float((n["rel"] as Dictionary).get(dim, 0.0))


func relation(npc_id: String) -> Dictionary:
	_ensure_npcs()
	var out := {}
	for d: String in DIMS:
		out[d] = _rel_dim(npc_id, d)
	out["label"] = _rel_label(out)
	out["known"] = npcs.has(npc_id) and not (npcs[npc_id]["rel"] as Dictionary).is_empty()
	return out


func _rel_label(r: Dictionary) -> String:
	if float(r["respect"]) >= 30.0 and float(r["affection"]) < 0.0:
		return "respects you but dislikes you"
	if float(r["affection"]) >= 40.0 and float(r["trust"]) < 0.0:
		return "cares for you but does not trust you"
	if float(r["fear"]) >= 30.0 and float(r["loyalty"]) >= 20.0:
		return "fears you and stays loyal"
	if float(r["resentment"]) >= 40.0:
		return "resents you deeply"
	if float(r["attraction"]) >= 35.0 and float(r["affection"]) >= 25.0:
		return "is drawn to you"
	if float(r["affection"]) >= 40.0 and float(r["trust"]) >= 30.0:
		return "a true friend"
	if float(r["familiarity"]) >= 10.0:
		return "an acquaintance"
	return "a stranger"


func interact(npc_id: String, kind: String) -> Dictionary:
	_ensure_npcs()
	if not npcs.has(npc_id) or not INTERACT.has(kind):
		return {"ok": false, "text": "Nothing happens."}
	var n: Dictionary = npcs[npc_id]
	var rel: Dictionary = n["rel"]
	var pers: Dictionary = n["pers"]
	var eff: Dictionary = INTERACT[kind]
	var deltas := {}
	for d: String in eff:
		var v := float(eff[d])
		# Personality shapes reaction: hot tempers resent more, forgiving ones less.
		if d == "resentment" and v > 0.0:
			v *= 0.6 + float(pers["temper"]) * 0.8 - float(pers["forgiveness"]) * 0.3
		if d == "affection" and v > 0.0:
			v *= 0.6 + float(pers["kindness"]) * 0.8
		if d == "fear" and v > 0.0:
			v *= 1.3 - float(pers["honor"]) * 0.6
		rel[d] = clampf(float(rel.get(d, 0.0)) + v, -100.0, 100.0)
		deltas[d] = v
	if KIND_DEED.has(kind):
		remember(npc_id, String(KIND_DEED[kind]), float(DEED_WEIGHT[KIND_DEED[kind]]))
	if kind == "flirt":
		player["_flirted"] = int(player.get("_flirted", 0)) + 1
	return {"ok": true, "text": "%s: %s" % [n["name"], _rel_label(relation(npc_id))], "deltas": deltas}


func remember(npc_id: String, deed: String, weight: float) -> void:
	_ensure_npcs()
	if not npcs.has(npc_id):
		return
	var mem: Array = npcs[npc_id]["memory"]
	mem.append({"deed": deed, "w": weight, "day": _day, "heavy": absf(weight) >= 8.0})
	if mem.size() > 10:
		# Keep the most weighty deeds.
		var weakest := 0
		for i in mem.size():
			if absf(float(mem[i]["w"])) < absf(float(mem[weakest]["w"])):
				weakest = i
		mem.remove_at(weakest)


func memory_of(npc_id: String) -> Array:
	_ensure_npcs()
	return (npcs.get(npc_id, {}).get("memory", []) as Array).duplicate(true)


func attitude(npc_id: String) -> float:
	## Memory-weighted stance toward the player: deeds matter more than points.
	var s := 0.0
	for m: Dictionary in memory_of(npc_id):
		s += float(m["w"])
	return s


# ----------------------------------------------- L§22/23 provocation, duels

func provoke(npc_id: String, kind: String) -> Dictionary:
	## kind: insult | challenge | threaten | insult_family | attack_reputation
	_ensure_npcs()
	if not npcs.has(npc_id):
		return {"reaction": "nothing", "text": ""}
	var n: Dictionary = npcs[npc_id]
	var p: Dictionary = n["pers"]
	var r := _rng("prov", _day, [npc_id, kind, int(_now)])
	var sev: float = {"insult": 1.0, "challenge": 0.8, "threaten": 1.3, "insult_family": 2.0, "attack_reputation": 1.6}.get(kind, 1.0)
	var heat := float(p["temper"]) * sev + (1.0 - float(p["forgiveness"])) * 0.4 * sev + r.randf() * 0.4
	var tier_gap := int(n["tier"]) - player_tier()
	var reaction := "laughs"
	var text := "%s laughs it off." % n["name"]
	if heat > 2.2 and int(n["tier"]) >= 5 and float(p["ambition"]) > 0.4:
		reaction = "assassins"
		text = "%s smiles thinly. You do not think the matter is over." % n["name"]
		_pending_msgs.append("__event:assassins:%s:%d" % [npc_id, _day + 6 + r.randi() % 10])
	elif heat > 1.5:
		reaction = "punches"
		text = "%s hits you before you can finish the sentence." % n["name"]
	elif heat > 0.9 and float(p["forgiveness"]) < 0.5:
		reaction = "remembers"
		text = "%s says nothing, and looks at you the way people look at a debt." % n["name"]
	if tier_gap >= 3 and reaction == "laughs":
		text = "%s barely notices you; a stranger of your standing is beneath a reply." % n["name"]
	interact(npc_id, "insult" if kind in ["insult", "insult_family", "attack_reputation"] else ("threaten" if kind == "threaten" else "talk"))
	if reaction != "laughs":
		remember(npc_id, "insulted", -2.0 * sev)
	return {"reaction": reaction, "text": text, "heat": snappedf(heat, 0.01)}


func duel_rule(culture: String) -> String:
	return String((CULTURES.get(culture, {}) as Dictionary).get("duels", "allowed"))


func challenge_duel(npc_id: String, terms: Dictionary) -> Dictionary:
	## terms: {stake: money|rank|honor|weapon|guild_position|territory, amount, to: first_blood|yield|death}
	_ensure_npcs()
	if not npcs.has(npc_id):
		return {"accepted": false, "reason": "Nobody by that name."}
	var n: Dictionary = npcs[npc_id]
	var rule := duel_rule(String(n["culture"]))
	var to := String(terms.get("to", "first_blood"))
	if rule == "forbidden":
		return {"accepted": false, "reason": "Duels are forbidden where %s comes from; the offer is an insult." % n["name"]}
	if rule == "allowed" and to == "death":
		return {"accepted": false, "reason": "%s will fight, but not to the death." % n["name"]}
	var gap := int(n["tier"]) - player_tier()
	if gap >= 3:
		return {"accepted": false, "reason": "%s will not lower themselves to fight a %s." % [n["name"], tier_name(player_tier())]}
	if gap <= -3 and float((n["pers"] as Dictionary)["honor"]) > 0.5:
		return {"accepted": false, "reason": "%s will not duel someone so far beneath them; there is no honour in it." % n["name"]}
	if String(terms.get("stake", "honor")) == "money" and _gold() < int(terms.get("amount", 0)):
		return {"accepted": false, "reason": "You cannot cover the stake."}
	return {"accepted": true, "reason": "%s accepts, %s." % [n["name"], "with a smile" if rule == "celebrated" else "coldly"], "culture_rule": rule}


func resolve_duel(npc_id: String, terms: Dictionary, player_power: float) -> Dictionary:
	_ensure_npcs()
	if not npcs.has(npc_id):
		return {"won": false}
	var n: Dictionary = npcs[npc_id]
	var npc_power := float(n["tier"]) * 13.0 + float((n["pers"] as Dictionary)["honor"]) * 4.0
	var r := _rng("duel", _day, [npc_id, int(_now)])
	var p_win := clampf(0.5 + (player_power - npc_power) / 60.0, 0.05, 0.95)
	var won := r.randf() < p_win
	var stake := String(terms.get("stake", "honor"))
	var amount := int(terms.get("amount", 0))
	var out := {"won": won, "stake": stake, "p_win": snappedf(p_win, 0.01)}
	if stake == "money":
		pending_gold += amount if won else -amount
	add_rep("faction:duellists", 3.0 if won else -1.0, "duel")
	if won:
		interact(npc_id, "train_together")
		remember(npc_id, "trained_together", 1.0)
		add_rumour("duel_won", int(n["sid"]), 1.0 + amount / 50.0, "player", 1.0)
		player["achievements"] = int(player.get("achievements", 0)) + 1
	else:
		remember(npc_id, "helped", 0.0)
	if String(terms.get("to", "first_blood")) == "death" and won:
		remember(npc_id, "killed_kin", -10.0)
		n["alive"] = false
		add_crim_rep("underworld", 1.0)
		out["killed"] = true
	return out


# ------------------------------------ L§25-30 compatibility, dating, marriage

func compatibility(npc_id: String) -> Dictionary:
	_ensure_npcs()
	var n: Dictionary = npcs.get(npc_id, {})
	if n.is_empty():
		return {"score": 0.0, "willing": false, "blockers": ["Unknown person."], "factors": {}}
	var pp: Dictionary = player["personality"]
	var np: Dictionary = n["pers"]
	var f := {}
	f["personality"] = 1.0 - (absf(float(pp["kindness"]) - float(np["kindness"])) + absf(float(pp["temper"]) - float(np["temper"]) ) * 0.7 + absf(float(pp["openness"]) - float(np["openness"])) * 0.5) / 2.2
	f["status"] = clampf(1.0 - absf(float(int(player["class"]) - int(n["class"]))) * 0.3 + (0.0 if int(player["class"]) >= int(n["class"]) else -0.1), 0.0, 1.0)
	f["money"] = clampf(float(player.get("wealth_score", player.get("gold", 0))) / (200.0 + 300.0 * float(n["class"])), 0.0, 1.0)
	f["religion"] = 1.0 if n["religion"] == player["religion"] else (0.6 if n["religion"] == "none" or player["religion"] == "none" else 0.15)
	f["culture"] = 1.0 if n["culture"] == player["culture"] else 0.5
	f["family"] = clampf(float(player.get("family", 0)) / 3.0 + 0.3 + float(_house_regard(n["house"])) * 0.3, 0.0, 1.0)
	f["career"] = 0.4 if bool(player.get("dangerous", false)) and float(np["jealousy"]) > 0.5 else 0.8
	f["ambition"] = 1.0 - absf(float((player["personality"] as Dictionary)["ambition"]) - float(np["ambition"]))
	f["age"] = clampf(1.0 - maxf(0.0, absf(float(int(player["age"]) - int(n["age"]))) - 6.0) / 20.0, 0.0, 1.0)
	f["lifestyle"] = 1.0 if n["lifestyle"] == player["lifestyle"] else 0.55
	f["politics"] = 0.8
	f["children"] = 1.0 if bool(player.get("wants_children", true)) else 0.5
	var w := {"personality": 3.0, "status": 1.0 + float(n["class"]) * 0.6, "money": 1.0 + float(np["ambition"]), "religion": 0.5 + float(np["piety"]) * 2.0,
		"culture": 1.0, "family": 1.0 + float(n["class"]) * 0.5, "career": 1.0, "ambition": 1.0, "age": 1.0, "lifestyle": 1.0, "politics": 0.5, "children": 0.7}
	var tot := 0.0
	var sum := 0.0
	for k: String in f:
		f[k] = snappedf(clampf(float(f[k]), 0.0, 1.0), 0.01)
		sum += float(f[k]) * float(w[k])
		tot += float(w[k])
	var score := sum / tot
	var blockers: Array = []
	if String(n["spouse"]) != "":
		blockers.append("%s is already married." % n["name"])
	if int(n["class"]) >= 3 and int(player["class"]) < 2 and int(player.get("title", 0)) < 1:
		blockers.append("Their family would never approve of a commoner.")
	if float(np["piety"]) > 0.7 and n["religion"] != player["religion"]:
		blockers.append("Their faith forbids marrying outside it.")
	if absf(float(int(player["age"]) - int(n["age"]))) > 20.0:
		blockers.append("The age gap is too great for their family.")
	if _house_regard(n["house"]) < -1.0:
		blockers.append("Their family regards you as an enemy.")
	return {"score": snappedf(score, 0.001), "factors": f, "blockers": blockers, "willing": score >= 0.55 and blockers.is_empty()}


func _house_regard(house_id: String) -> float:
	## Family opinion: mean attitude of members toward the player, feuds subtract.
	if not houses.has(house_id):
		return 0.0
	var s := 0.0
	var members: Array = houses[house_id]["members"]
	for m: String in members:
		s += clampf(attitude(m) / 10.0, -2.0, 2.0)
	var v := s / maxf(1.0, float(members.size()))
	if in_law_of(house_id):
		v += 0.5
	return v


func in_law_of(house_id: String) -> bool:
	if marriage.is_empty() or not npcs.has(String(marriage.get("spouse", ""))):
		return false
	return String(npcs[marriage["spouse"]]["house"]) == house_id


func family_of(npc_id: String) -> Array:
	_ensure_npcs()
	if not npcs.has(npc_id):
		return []
	var out: Array = []
	for m: String in houses[npcs[npc_id]["house"]]["members"]:
		if m != npc_id:
			out.append(m)
	return out


func date(npc_id: String, activity: String) -> Dictionary:
	_ensure_npcs()
	if not npcs.has(npc_id) or not ACTIVITIES.has(activity):
		return {"ok": false, "text": "They look puzzled."}
	var n: Dictionary = npcs[npc_id]
	var c: Dictionary = courtship.get(npc_id, {"dates": 0, "stage": "acquainted", "last_date": -100})
	if int(c["last_date"]) == _day:
		return {"ok": false, "text": "You already spent today with them."}
	if String(n["spouse"]) != "":
		return {"ok": false, "text": "%s is married." % n["name"]}
	var enjoy := 0.0
	if (n["likes"] as Array).has(activity):
		enjoy += 1.0
	if activity == "hunt" and n["lifestyle"] == "martial":
		enjoy += 0.6
	if activity == "religious ceremony":
		enjoy += float((n["pers"] as Dictionary)["piety"]) - 0.4
	if activity == "training session" and n["culture"] == "martial":
		enjoy += 0.4
	if activity == "festival" and n["lifestyle"] == "social":
		enjoy += 0.5
	if activity == "walk" and n["lifestyle"] == "homebody":
		enjoy += 0.3
	if activity == "boat ride" and n["culture"] == "courtly":
		enjoy += 0.3
	var comp := float(compatibility(npc_id)["score"])
	var rel: Dictionary = n["rel"]
	rel["familiarity"] = clampf(float(rel.get("familiarity", 0.0)) + 5.0, 0.0, 100.0)
	rel["affection"] = clampf(float(rel.get("affection", 0.0)) + 3.0 + enjoy * 4.0 + comp * 3.0, -100.0, 100.0)
	rel["attraction"] = clampf(float(rel.get("attraction", 0.0)) + comp * 4.0 + enjoy * 2.0, -100.0, 100.0)
	rel["trust"] = clampf(float(rel.get("trust", 0.0)) + 2.5, -100.0, 100.0)
	c["dates"] = int(c["dates"]) + 1
	c["last_date"] = _day
	if int(c["dates"]) >= 2 and float(rel["affection"]) >= 25.0:
		c["stage"] = "courting"
	courtship[npc_id] = c
	if not marriage.is_empty() and marriage.get("spouse") != npc_id:
		marriage["jealous_events"] = int(marriage.get("jealous_events", 0)) + 1
	var verdict := "enjoys it" if enjoy >= 0.8 else ("is politely pleased" if enjoy > 0.0 else "seems bored")
	return {"ok": true, "text": "%s %s." % [n["name"], verdict], "enjoy": snappedf(enjoy, 0.01), "stage": c["stage"]}


func noble_requirements(npc_id: String) -> Array:
	_ensure_npcs()
	var out: Array = []
	var n: Dictionary = npcs.get(npc_id, {})
	if n.is_empty() or int(n["class"]) < 3:
		return out
	if int(player.get("title", 0)) < 1:
		out.append("a title")
	if not bool(player.get("land", false)) and int(player.get("wealth_score", player.get("gold", 0))) < 500:
		out.append("land or wealth")
	if rep("city:%d" % int(n["sid"])) < 10.0:
		out.append("a good name in %s" % _sname(int(n["sid"])))
	if _house_regard(String(n["house"])) < 0.0:
		out.append("the family's approval")
	return out


func propose(npc_id: String) -> Dictionary:
	_ensure_npcs()
	if not npcs.has(npc_id):
		return {"ok": false, "reason": "Nobody by that name."}
	if not marriage.is_empty():
		return {"ok": false, "reason": "You are already married."}
	var n: Dictionary = npcs[npc_id]
	var c: Dictionary = courtship.get(npc_id, {})
	if c.is_empty() or String(c["stage"]) != "courting":
		return {"ok": false, "reason": "You have not courted them long enough."}
	var rel: Dictionary = n["rel"]
	if float(rel.get("affection", 0.0)) < 45.0 or float(rel.get("trust", 0.0)) < 15.0:
		return {"ok": false, "reason": "%s likes you, but not enough for that." % n["name"]}
	var comp := compatibility(npc_id)
	if not (comp["blockers"] as Array).is_empty():
		return {"ok": false, "reason": String((comp["blockers"] as Array)[0]), "blockers": comp["blockers"]}
	if float(comp["score"]) < 0.55:
		return {"ok": false, "reason": "%s says you want different lives." % n["name"], "score": comp["score"]}
	var need := noble_requirements(npc_id)
	if not need.is_empty():
		return {"ok": false, "reason": "The family requires " + ", ".join(need) + ".", "requirements": need}
	n["spouse"] = "player"
	marriage = {"spouse": npc_id, "day": _day, "happiness": 75.0, "problems": [], "status": "married", "children": 0,
		"last_together": _day, "home": "", "jealous_events": 0, "career_continues": true}
	c["stage"] = "married"
	# Family: in-laws warm to you, family enemies become yours.
	for m: String in family_of(npc_id):
		var rr: Dictionary = npcs[m]["rel"]
		rr["trust"] = clampf(float(rr.get("trust", 0.0)) + 10.0, -100.0, 100.0)
		rr["familiarity"] = clampf(float(rr.get("familiarity", 0.0)) + 15.0, 0.0, 100.0)
	for f: Array in feuds:
		var mine: String = n["house"]
		if f[0] == mine or f[1] == mine:
			var enemy: String = f[1] if f[0] == mine else f[0]
			for m2: String in houses[enemy]["members"]:
				var re: Dictionary = npcs[m2]["rel"]
				re["resentment"] = clampf(float(re.get("resentment", 0.0)) + 15.0, -100.0, 100.0)
	add_rep("faction:%s" % n["house"], 10.0, "marriage")
	if hub != null:
		var fm: RefCounted = hub.mod("factions")
		if fm != null and fm.has_method("on_marriage"):
			fm.on_marriage(String(n["house"]), int(n["class"]), int(n["sid"]))
	return {"ok": true, "reason": "%s says yes. You are married." % n["name"], "in_laws": family_of(npc_id)}


func spouse() -> Dictionary:
	if marriage.is_empty():
		return {}
	return npc(String(marriage["spouse"]))


func in_laws() -> Array:
	if marriage.is_empty():
		return []
	return family_of(String(marriage["spouse"]))


func spend_time(npc_id: String = "") -> void:
	if not marriage.is_empty() and (npc_id == "" or npc_id == marriage["spouse"]):
		marriage["last_together"] = _day


func marriage_state() -> Dictionary:
	return marriage.duplicate(true)


func resolve_problem(kind: String, action: String) -> Dictionary:
	if marriage.is_empty():
		return {"ok": false}
	var probs: Array = marriage["problems"]
	for i in probs.size():
		if probs[i]["kind"] == kind:
			if String(PROBLEM_FIX.get(kind, "compromise")) == action:
				marriage["happiness"] = minf(100.0, float(marriage["happiness"]) + 12.0 + float(probs[i]["severity"]) * 2.0)
				probs.remove_at(i)
				if action == "spend_time":
					marriage["last_together"] = _day
				return {"ok": true, "text": "You talk it through, and it helps."}
			marriage["happiness"] = float(marriage["happiness"]) - 2.0
			return {"ok": true, "text": "That does not address the real problem."}
	return {"ok": false}


func _tick_marriage(msgs: Array) -> void:
	var m := marriage
	if m.is_empty() or String(m["status"]) == "divorced":
		return
	var r := _rng("marr", _day, m["spouse"])
	var spouse_n: Dictionary = npcs.get(String(m["spouse"]), {})
	var jealous := float((spouse_n.get("pers", {}) as Dictionary).get("jealousy", 0.3))
	var probs: Array = m["problems"]
	var have := {}
	for p: Dictionary in probs:
		have[p["kind"]] = true
	if _day - int(m["last_together"]) > 10 and not have.has("absence"):
		probs.append({"kind": "absence", "severity": 2, "day": _day})
		_say(msgs, "%s feels neglected; you have hardly been home." % spouse_n.get("name", "Your spouse"))
	if int(player.get("gold", 0)) < 15 and not have.has("money") and r.randf() < 0.25:
		probs.append({"kind": "money", "severity": 2, "day": _day})
		_say(msgs, "Money is short and it is souring things at home.")
	if int(m.get("jealous_events", 0)) > 0 and not have.has("jealousy") and r.randf() < 0.3 + jealous * 0.4:
		probs.append({"kind": "jealousy", "severity": 3, "day": _day})
		m["jealous_events"] = 0
		_say(msgs, "%s has heard whispers about you and someone else." % spouse_n.get("name", "Your spouse"))
	if bool(player.get("dangerous", false)) and not have.has("danger") and r.randf() < 0.01:
		probs.append({"kind": "danger", "severity": 2, "day": _day})
	if _at_war and not have.has("war") and r.randf() < 0.05:
		probs.append({"kind": "war", "severity": 2, "day": _day})
	var loss := 0.0
	for p: Dictionary in probs:
		loss += 0.35 * float(p["severity"])
	m["happiness"] = clampf(float(m["happiness"]) - loss + (0.3 if probs.is_empty() else 0.0), 0.0, 100.0)
	if float(m["happiness"]) < 15.0 and String(m["status"]) == "married":
		m["status"] = "estranged"
		_say(msgs, "%s has moved out for now. The marriage is in trouble." % spouse_n.get("name", "Your spouse"))
		log_failure("marriage", "Your marriage has broken down; a rival for their affection, or a debt, waits in the wings.", int(spouse_n.get("sid", 0)))
	elif float(m["happiness"]) <= 0.0 and String(m["status"]) == "estranged":
		m["status"] = "divorced"
		if npcs.has(String(m["spouse"])):
			npcs[m["spouse"]]["spouse"] = ""
		_say(msgs, "The marriage is over.")
	elif float(m["happiness"]) > 40.0 and String(m["status"]) == "estranged":
		m["status"] = "married"
	# Children: slow closed-form chance per day.
	if String(m["status"]) == "married" and bool(player.get("wants_children", true)) and r.randf() < 0.0012 and int(m["children"]) < 4:
		m["children"] = int(m["children"]) + 1
		_say(msgs, "A child is born to your household.")


# ------------------------------------------------ L§31/32 class and clothing

func set_outfit(kind: String, dirty: bool = false, disguise: float = 0.0) -> bool:
	if not OUTFITS.has(kind):
		return false
	outfit = {"kind": kind, "dirty": dirty, "disguise": clampf(disguise, 0.0, 1.0)}
	return true


func perceived_class() -> int:
	var c := int(OUTFITS[outfit["kind"]]["class"])
	if bool(outfit["dirty"]):
		c = maxi(0, c - 1)
	if int(player.get("class", 1)) >= 3 and float(player.get("fame", 0)) >= 30.0 and float(outfit["disguise"]) < 0.5:
		c = maxi(c, 2)
	return c


func treatment(sid: int = -1) -> Dictionary:
	var c := perceived_class()
	var price: float = [1.25, 1.0, 0.95, 0.9, 0.85][c]
	var patience: float = [0.3, 0.6, 0.8, 1.0, 1.2][c]
	var k := String(outfit["kind"])
	if k == "religious":
		patience += 0.2
	if k == "military":
		patience += 0.1
	if bool(outfit["dirty"]):
		price *= 1.1
	if sid >= 0:
		price *= 1.0 - clampf(rep("city:%d" % sid) / 400.0, -0.2, 0.2)
	return {"class": c, "price_mult": snappedf(price, 0.01), "patience": patience, "welcome": c >= 2,
		"guard_suspicion": 0.0 if c >= 2 else (0.25 if k != "mask" else 0.6)}


func place_access(place: String, hour: int = 12) -> Dictionary:
	var c := perceived_class()
	var need: int = {"noble": 2, "temple": 0, "market": 0, "craft": 0, "docks": 0, "slums": 0, "military": 2, "guildhall": 1}.get(place, 0)
	if place == "noble" and (hour >= 21 or hour < 5):
		need = 3
	var k := String(outfit["kind"])
	if place == "temple" and hour >= 21 and k != "religious":
		return {"ok": false, "reason": "The temple is shut for the night vigil."}
	if place == "military" and k != "military" and k != "noble":
		return {"ok": false, "reason": "The sentries ask for your orders."}
	if c < int(need):
		return {"ok": false, "reason": "The guards look at your %s clothes and turn you away." % ("filthy" if bool(outfit["dirty"]) else "plain")}
	return {"ok": true, "reason": ""}


func disguise_check(npc_id: String) -> bool:
	## True if this NPC sees through the disguise.
	var d := float(outfit["disguise"])
	if d <= 0.0:
		return true
	var fam := _rel_dim(npc_id, "familiarity") / 100.0
	var r := _rng("disg", _day, [npc_id, int(_now)])
	return r.randf() < clampf(0.15 + fam * 0.7 - d * 0.5, 0.02, 0.98)


# ----------------------------------------------------------- L§33/34 crime

func commit_crime(kind: String, sid: int, witnesses_near: Variant = 0) -> Dictionary:
	if not CRIMES.has(kind):
		return {"ok": false, "reason": "Unknown crime."}
	_ensure_npcs()
	var def: Dictionary = CRIMES[kind]
	var id := _new_id("c")
	var night := _hour >= 21 or _hour < 5
	var r := _rng("crime", _day, [id, kind, sid])
	var wlist: Array = []
	if witnesses_near is Array:
		wlist = (witnesses_near as Array).duplicate()
	else:
		for i in int(witnesses_near):
			wlist.append("")
	var disguise := float(outfit["disguise"]) + (0.3 if outfit["kind"] == "mask" else 0.0)
	var noticed := 0
	var identified := 0
	var reported := 0
	var slums := 0.25 if String(player.get("district", "")) == "slums" else 0.0
	for w: Variant in wlist:
		var wid := String(w)
		var see := 0.55 if night else 0.9
		if r.randf() > see:
			continue
		noticed += 1
		var recog := clampf(0.65 - disguise * 0.6 + fame_at(sid) * 0.004, 0.05, 0.95)
		if wid != "" and npcs.has(wid):
			recog = clampf(recog + _rel_dim(wid, "familiarity") / 250.0, 0.05, 0.98)
			if disguise_check(wid):
				recog = maxf(recog, 0.5)
		var will := float(def["report"]) - slums
		var fear_of := 0.0
		if wid != "" and npcs.has(wid):
			var np: Dictionary = npcs[wid]["pers"]
			will += (float(np["honor"]) - 0.5) * 0.4
			fear_of = _rel_dim(wid, "fear") / 100.0
			will -= (_rel_dim(wid, "affection") + _rel_dim(wid, "loyalty")) / 250.0
			if String(npcs[wid]["job"]) == "guard":
				will = 1.0
		will -= fear_of * 0.5 + crim_rep("city:%d" % sid) / 400.0
		var knows_you := r.randf() < recog
		if knows_you:
			identified += 1
		if r.randf() < clampf(will, 0.0, 1.0):
			reported += 1
			if knows_you and wid != "":
				remember(wid, "robbed" if kind in ["robbery", "pickpocket", "burglary"] else "betrayed", -6.0)
	var ev_ids: Array = []
	for et: String in def["evidence"]:
		if et == "witness_statement" and reported == 0:
			continue
		var eid := _new_id("e")
		evidence_items.append({"id": eid, "crime": id, "type": et, "strength": snappedf(0.3 + r.randf() * 0.6, 0.01), "sid": sid, "day": _day})
		ev_ids.append(eid)
	var crime := {"id": id, "kind": kind, "sid": sid, "day": _day, "witnesses": wlist.size(), "noticed": noticed, "identified": identified,
		"reported": reported, "solved": false}
	crimes.append(crime)
	if crimes.size() > 60:
		crimes.pop_front()
	# Criminal reputation grows with success; public reputation only with exposure.
	var under := float(def["under"]) * (1.0 if reported == 0 else 0.4)
	add_crim_rep("city:%d" % sid, under)
	if identified > 0 and reported > 0:
		add_rep("city:%d" % sid, -float(def["sev"]) * 2.5, "crime:" + kind)
	if reported > 0 or kind == "murder":
		var start := 0.0
		if identified > 0:
			start = 0.4
		investigations.append({"crime": id, "sid": sid, "day": _day, "progress": start, "identified": identified > 0})
		if investigations.size() > 40:
			investigations.pop_front()
		add_rumour("crime", sid, float(maxi(1, noticed)), "player" if identified > 0 else "unknown", -1.0, kind)
	var city := _city()
	if city != null and city.has_method("note_activity"):
		city.note_activity("crime_" + kind, sid, 1.0)
		if kind == "murder":
			city.note_activity("crime_violence", sid, 1.0)
	return {"ok": true, "id": id, "kind": kind, "sid": sid, "witnesses": wlist.size(), "noticed": noticed, "identified": identified,
		"reported": reported, "evidence": ev_ids, "heat": snappedf(float(def["sev"]) * (0.5 + 0.5 * float(reported)), 0.1)}


func evidence(sid: int = -1) -> Array:
	var out: Array = []
	for e: Dictionary in evidence_items:
		if sid < 0 or int(e["sid"]) == sid:
			out.append(e.duplicate())
	return out


func destroy_evidence(eid: String) -> bool:
	for i in evidence_items.size():
		if evidence_items[i]["id"] == eid:
			evidence_items.remove_at(i)
			return true
	return false


func bribe_witness(crime_id: String, gold: int) -> Dictionary:
	for c: Dictionary in crimes:
		if c["id"] == crime_id and int(c["reported"]) > 0:
			if _gold() < gold:
				return {"ok": false, "reason": "You cannot afford it."}
			pending_gold -= gold
			var chance := clampf(float(gold) / (30.0 * float(CRIMES[c["kind"]]["sev"])), 0.0, 0.9)
			if _rng("bribe", _day, crime_id).randf() < chance:
				c["reported"] = int(c["reported"]) - 1
				if int(c["reported"]) <= 0:
					for inv in investigations:
						if inv["crime"] == crime_id:
							inv["progress"] = minf(float(inv["progress"]), 0.2)
				return {"ok": true, "reason": "A witness suddenly remembers nothing."}
			return {"ok": true, "reason": "The witness takes the coin and talks anyway."}
	return {"ok": false, "reason": "Nobody to bribe."}


func bounty(sid: int = -1) -> int:
	if sid >= 0:
		return int(bounties.get(str(sid), 0))
	var t := 0
	for k: String in bounties:
		t += int(bounties[k])
	return t


func pay_bounty(sid: int) -> Dictionary:
	var b := bounty(sid)
	if b <= 0:
		return {"ok": true, "cost": 0}
	if _gold() < b:
		return {"ok": false, "cost": b, "reason": "You cannot cover %d gold." % b}
	pending_gold -= b
	bounties.erase(str(sid))
	return {"ok": true, "cost": b}


func _tick_crime_day(msgs: Array) -> void:
	# Evidence decays; weak evidence vanishes.
	for i in range(evidence_items.size() - 1, -1, -1):
		var e: Dictionary = evidence_items[i]
		e["strength"] = float(e["strength"]) - float(EVIDENCE_DECAY.get(e["type"], 0.02))
		if float(e["strength"]) <= 0.05:
			evidence_items.remove_at(i)
	# Investigations advance with the strength of remaining evidence and the watch.
	for i in range(investigations.size() - 1, -1, -1):
		var inv: Dictionary = investigations[i]
		var s := 0.0
		for e: Dictionary in evidence_items:
			if e["crime"] == inv["crime"]:
				s += float(e["strength"])
		inv["progress"] = float(inv["progress"]) + 0.04 + s * 0.06 + (0.05 if inv["identified"] else 0.0)
		if s <= 0.0 and not inv["identified"]:
			inv["progress"] = float(inv["progress"]) - 0.06
		if float(inv["progress"]) <= -0.3:
			investigations.remove_at(i)
			continue
		if float(inv["progress"]) >= 1.0:
			var crime: Dictionary = {}
			for c: Dictionary in crimes:
				if c["id"] == inv["crime"]:
					crime = c
			investigations.remove_at(i)
			if crime.is_empty() or not (inv["identified"] or s > 0.4):
				continue
			crime["solved"] = true
			var amt := int(CRIMES[crime["kind"]]["fine"]) * 2
			bounties[str(inv["sid"])] = int(bounties.get(str(inv["sid"]), 0)) + amt
			add_rep("city:%d" % int(inv["sid"]), -float(CRIMES[crime["kind"]]["sev"]) * 3.0, "wanted")
			_say(msgs, "The watch in %s names you for a %s. There is a price of %d gold on you." % [_sname(int(inv["sid"])), crime["kind"], amt])
	# Bounty hunters (rare, only for serious prices).
	if bounty() >= 150 and _rng("hunter", _day, 0).randf() < 0.05:
		_say(msgs, "A hard-looking stranger has been asking after you on the roads.")
	# Slow forgiveness: bounties fade if nothing new appears.
	for k: String in bounties.keys():
		if _day % 10 == 0:
			bounties[k] = int(float(bounties[k]) * 0.97)
			if int(bounties[k]) < 5:
				bounties.erase(k)
	# Crime log stays bounded.
	while crimes.size() > 60:
		crimes.pop_front()


# ------------------------------------------------------ L§36 rumours

func _road_nbrs() -> Dictionary:
	var sig := hash([WorldGen.roads.size(), WorldGen.settlements.size(), WorldGen.settlements[0]["pos"] if not WorldGen.settlements.is_empty() else 0])
	if sig == _nbr_sig:
		return _nbrs
	_nbr_sig = sig
	_nbrs.clear()
	for e: Vector2i in WorldGen.roads:
		var d := float((WorldGen.settlements[e.x]["pos"] as Vector2).distance_to(WorldGen.settlements[e.y]["pos"]))
		if not _nbrs.has(e.x):
			_nbrs[e.x] = []
		if not _nbrs.has(e.y):
			_nbrs[e.y] = []
		(_nbrs[e.x] as Array).append([e.y, d])
		(_nbrs[e.y] as Array).append([e.x, d])
	return _nbrs


func add_rumour(deed: String, sid: int, magnitude: float = 1.0, subject: String = "player", tone: float = 1.0, detail: String = "") -> String:
	var id := _new_id("r")
	var r := {"id": id, "deed": deed, "detail": detail, "subject": subject, "origin": sid, "day": _day, "mag": magnitude, "tone": tone,
		"heard": {str(sid): {"h": _now, "f": 1.0, "hops": 0}}, "expires": _now + RUMOUR_TTL_H}
	rumour_list.append(r)
	if rumour_list.size() > 40:
		rumour_list.pop_front()
	_fame_cache.clear()
	_schedule_hops(r, sid, 1.0, 0, _now)
	return id


func _schedule_hops(r: Dictionary, from_sid: int, fid: float, hops: int, at: float) -> void:
	var nb: Array = (_road_nbrs().get(from_sid, []) as Array).duplicate()
	nb.sort_custom(func(a: Array, b: Array) -> bool: return float(a[1]) < float(b[1]))
	var n := 0
	for e: Array in nb:
		if (r["heard"] as Dictionary).has(str(e[0])):
			continue
		if n >= RUMOUR_FANOUT:
			break
		n += 1
		# Carriers (merchants, soldiers, bards, priests) take a day or more.
		var delay := maxf(6.0, float(e[1]) / RUMOUR_SPEED) + _rng("hop", int(at), [r["id"], e[0]]).randf() * 8.0
		_hops.append({"r": r["id"], "to": int(e[0]), "from": from_sid, "at": at + delay, "f": fid, "hops": hops + 1})


func _rumour_by_id(id: String) -> Dictionary:
	for r: Dictionary in rumour_list:
		if r["id"] == id:
			return r
	return {}


func _step_rumours() -> void:
	if _hops.is_empty():
		return
	var due: Array = []
	var keep: Array = []
	for h: Dictionary in _hops:
		if float(h["at"]) <= _now:
			due.append(h)
		else:
			keep.append(h)
	_hops = keep
	for h: Dictionary in due:
		var r := _rumour_by_id(String(h["r"]))
		if r.is_empty() or (r["heard"] as Dictionary).has(str(h["to"])):
			continue
		if float(r["expires"]) <= _now:
			continue
		var f := float(h["f"]) * _rng("dist", int(_now), [h["r"], h["to"]]).randf_range(0.86, 0.97)
		r["heard"][str(h["to"])] = {"h": float(h["at"]), "f": f, "hops": int(h["hops"])}
		_fame_cache.erase(int(h["to"]))
		if r["subject"] == "player":
			add_rep("city:%d" % int(h["to"]), float(r["tone"]) * minf(6.0, float(r["mag"]) * 1.5) * f, "rumour")
		if hops_left(f):
			_schedule_hops(r, int(h["to"]), f, int(h["hops"]), float(h["at"]))


static func hops_left(f: float) -> bool:
	return f > 0.25


func _rumour_text(r: Dictionary, sid: int) -> String:
	var hd: Dictionary = (r["heard"] as Dictionary).get(str(sid), {})
	if hd.is_empty():
		return ""
	var f := float(hd["f"])
	var lines: Array = DEED_TEXT.get(r["deed"], DEED_TEXT["generic"])
	var who := "The adventurer" if r["subject"] == "player" else "Someone"
	var mag := float(r["mag"])
	var count := str(int(round(mag)))
	var line: String = lines[0]
	if f < 0.85:
		who = "A stranger with a scar" if r["subject"] == "player" else "Somebody"
		count = str(int(round(mag / 2.0)) * 2)
		line = lines[1]
	if f < 0.6:
		who = "Some say a devil" if r["subject"] == "player" else "They say a monster"
		count = str(int(round(mag * (1.0 + (1.0 - f) * 4.0))))
		line = lines[2]
	var detail := ""
	if r["deed"] == "crime" and String(r["detail"]) != "" and f >= 0.7:
		detail = " (%s)" % String(r["detail"]).replace("_", " ")
	return (line % [who, count]) + detail + "."


func rumours(sid: int) -> Array:
	var out: Array = []
	for r: Dictionary in rumour_list:
		if (r["heard"] as Dictionary).has(str(sid)) and float(r["expires"]) > _now:
			out.append(_rumour_text(r, sid))
	return out


func rumour_reach(id: String) -> Array:
	var r := _rumour_by_id(id)
	var out: Array = []
	if r.is_empty():
		return out
	for k: String in r["heard"]:
		out.append(int(k))
	out.sort()
	return out


# ------------------------------------ L§37/38 memory (above) and goals

func _tick_goals(msgs: Array) -> void:
	var r := _rng("goals", _day, 0)
	var shown := 0
	for i in NPC_COUNT:
		var id := "n%d" % i
		if not npcs.has(id):
			continue
		var n: Dictionary = npcs[id]
		if not bool(n["alive"]):
			continue
		if r.randf() > 0.09:
			continue
		var goals: Array = n["goals"]
		if goals.is_empty():
			goals.append(_new_goal(r, id))
			continue
		var g: Dictionary = goals[0]
		# Revenge: grudges against the player focus the goal.
		if attitude(id) <= -8.0 and String(g["type"]) != "revenge":
			g = {"type": "revenge", "step": 0, "steps": 3, "target": "player"}
			goals[0] = g
		g["step"] = int(g["step"]) + 1
		if int(g["step"]) < int(g["steps"]):
			continue
		var known := not (n["rel"] as Dictionary).is_empty()
		match String(g["type"]):
			"become_wealthy":
				n["class"] = mini(4, int(n["class"]) + (1 if r.randf() < 0.3 else 0))
			"join_army":
				n["job"] = "soldier"
				n["tier"] = mini(8, int(n["tier"]) + 1)
			"become_master":
				n["tier"] = mini(8, int(n["tier"]) + 1)
				n["job"] = "master " + String(n["job"]) if not String(n["job"]).begins_with("master") else n["job"]
			"gain_power":
				n["class"] = mini(4, int(n["class"]) + 1)
				n["tier"] = mini(8, int(n["tier"]) + 1)
			"travel":
				var nb: Array = _road_nbrs().get(int(n["sid"]), [])
				if not nb.is_empty():
					n["sid"] = int((nb[r.randi() % nb.size()] as Array)[0])
					if known:
						_say(msgs, "%s has left for %s." % [n["name"], _sname(int(n["sid"]))])
						known = false
			"kill_monster":
				n["tier"] = mini(8, int(n["tier"]) + 1)
				add_rumour("monster_kill", int(n["sid"]), 2.0 + r.randi() % 4, id, 1.0)
			"revenge":
				if String(g["target"]) == "player":
					_pending_msgs.append("__event:ambush:%s:%d" % [id, _day + 2])
					if known:
						_say(msgs, "%s was seen buying rope and hiring knuckles. Watch your back." % n["name"])
						known = false
			"find_someone":
				var t: String = g["target"]
				if npcs.has(t):
					(npcs[t]["rel"] as Dictionary)["familiarity"] = float((npcs[t]["rel"] as Dictionary).get("familiarity", 0.0)) + 5.0
		if known and shown < 2:
			shown += 1
			_say(msgs, "%s has achieved a long-held goal (%s)." % [n["name"], String(g["type"]).replace("_", " ")])
		goals[0] = _new_goal(r, id)


func goals_of(npc_id: String) -> Array:
	_ensure_npcs()
	return (npcs.get(npc_id, {}).get("goals", []) as Array).duplicate(true)


func _tick_offers() -> void:
	## L§39: the world approaches the player.
	if _near_sid < 0 or offers_list.size() >= 3:
		return
	var r := _rng("offer", _day, _near_sid)
	if r.randf() > 0.12:
		return
	var here := npcs_in(_near_sid)
	if here.is_empty():
		return
	var id: String = here[r.randi() % here.size()]
	var n: Dictionary = npcs[id]
	var g: String = "travel"
	if not (n["goals"] as Array).is_empty():
		g = String(n["goals"][0]["type"])
	var text := ""
	match g:
		"kill_monster":
			text = "\"I'm hunting the same creature you are. Want to split the reward?\""
		"become_wealthy":
			text = "\"I've heard you know the northern road. Want to escort my caravan?\""
		"revenge":
			text = "\"We could make money together, if you can keep a secret.\""
		_:
			text = "\"You have the look of someone who gets things done. Do you have a moment?\""
	offers_list.append({"id": _new_id("o"), "npc": id, "text": text, "goal": g, "day": _day})


func offers() -> Array:
	return offers_list.duplicate(true)


func accept_offer(offer_id: String) -> Dictionary:
	for i in offers_list.size():
		if offers_list[i]["id"] == offer_id:
			var o: Dictionary = offers_list[i]
			offers_list.remove_at(i)
			interact(String(o["npc"]), "help")
			learn("contact:" + String(o["npc"]), "You made a contact through an offer.")
			return {"ok": true}
	return {"ok": false}


# --------------------------------------- L§40/41 apprenticeships and teaching

func master_terms(npc_id: String) -> String:
	_ensure_npcs()
	return String(MASTER_TERMS[hash([npc_id, WorldSim.SEED]) % MASTER_TERMS.size()])


func apply_apprenticeship(npc_id: String, craft: String) -> Dictionary:
	_ensure_npcs()
	if not apprenticeship.is_empty():
		return {"ok": false, "reason": "You are already apprenticed."}
	if not npcs.has(npc_id):
		return {"ok": false, "reason": "No such master."}
	var n: Dictionary = npcs[npc_id]
	if int(n["tier"]) < 3:
		return {"ok": false, "reason": "%s is not yet a master of anything." % n["name"]}
	var gap := int(n["tier"]) - player_tier()
	if gap >= 3 and _rel_dim(npc_id, "respect") < 30.0:
		return {"ok": false, "reason": "%s does not take strangers of your standing." % n["name"]}
	var term := master_terms(npc_id)
	var fee := 30 + int(n["tier"]) * 20
	match term:
		"money":
			if _gold() < fee:
				return {"ok": false, "reason": "%s asks %d gold up front." % [n["name"], fee], "term": term}
			pending_gold -= fee
		"respect":
			if _rel_dim(npc_id, "respect") < 20.0:
				return {"ok": false, "reason": "%s wants to see what you are made of first." % n["name"], "term": term}
		"service":
			if not bool(player.get("_served_" + npc_id, false)):
				return {"ok": false, "reason": "%s wants a season of errands before teaching you anything." % n["name"], "term": term}
		"talent":
			if float((player["skills"] as Dictionary).get(craft, 0.0)) < 10.0:
				return {"ok": false, "reason": "%s sees no talent in your hands yet." % n["name"], "term": term}
		"recommendation":
			if int(player.get("refs", 0)) < 1:
				return {"ok": false, "reason": "%s only takes pupils someone has vouched for." % n["name"], "term": term}
	apprenticeship = {"master": npc_id, "craft": craft, "days": 0, "need": 40, "skill": 0.0, "missed": 0}
	return {"ok": true, "reason": "%s takes you on." % n["name"], "term": term}


func do_service(npc_id: String) -> void:
	player["_served_" + npc_id] = true
	interact(npc_id, "help")


func attend_lesson() -> bool:
	if apprenticeship.is_empty():
		return false
	_attended_today = true
	return true


func teach_lesson() -> bool:
	if students.is_empty():
		return false
	_taught_today = true
	return true


func student_requests() -> Array:
	return student_requests_list.duplicate(true)


func take_student(npc_id: String, craft: String) -> Dictionary:
	_ensure_npcs()
	if float((player["skills"] as Dictionary).get(craft, 0.0)) < 50.0:
		return {"ok": false, "reason": "You are not yet a master of %s." % craft}
	if students.size() >= (3 if _school else 1):
		return {"ok": false, "reason": "You have no room for more pupils; a school would help."}
	for s: Dictionary in students:
		if s["npc"] == npc_id:
			return {"ok": false, "reason": "Already your pupil."}
	if not npcs.has(npc_id):
		return {"ok": false, "reason": "No such person."}
	students.append({"npc": npc_id, "craft": craft, "days": 0, "need": 50, "missed": 0})
	for i in student_requests_list.size():
		if student_requests_list[i]["npc"] == npc_id:
			student_requests_list.remove_at(i)
			break
	return {"ok": true, "reason": ""}


func found_school(kind: String = "school") -> bool:
	if _school or _gold() < 300:
		return false
	pending_gold -= 300
	_school = true
	learn("school:" + kind)
	return true


func _tick_teaching(msgs: Array) -> void:
	if not apprenticeship.is_empty():
		var a := apprenticeship
		if _attended_today:
			a["days"] = int(a["days"]) + 1
			a["skill"] = minf(100.0, float(a["skill"]) + 100.0 / float(a["need"]))
			a["missed"] = 0
		else:
			a["missed"] = int(a["missed"]) + 1
			if int(a["missed"]) >= 6:
				_say(msgs, "Your master is done waiting; the apprenticeship is over.")
				log_failure("apprenticeship", "You drifted from your master and lost the place. Others may take you, but reputations travel.", int(player.get("sid", 0)))
				apprenticeship = {}
		if not apprenticeship.is_empty() and int(a["days"]) >= int(a["need"]):
			var craft := String(a["craft"])
			var sk: Dictionary = player["skills"]
			sk[craft] = maxf(float(sk.get(craft, 0.0)), 55.0)
			learn("skill:" + craft, "Learned %s from a master." % craft)
			_say(msgs, "Your master says you have learned all they can teach: %s." % craft)
			interact(String(a["master"]), "train_together")
			remember(String(a["master"]), "trained_together", 3.0)
			apprenticeship = {}
	_attended_today = false
	for i in range(students.size() - 1, -1, -1):
		var s: Dictionary = students[i]
		if _taught_today:
			s["days"] = int(s["days"]) + 1
			s["missed"] = 0
		else:
			s["missed"] = int(s["missed"]) + 1
			if int(s["missed"]) >= 8:
				students.remove_at(i)
				continue
		if int(s["days"]) >= int(s["need"]):
			students.remove_at(i)
			var n: Dictionary = npcs.get(String(s["npc"]), {})
			if not n.is_empty():
				n["tier"] = mini(8, int(n["tier"]) + 2)
				n["job"] = "%s (trained by you)" % s["craft"]
				var rl: Dictionary = n["rel"]
				rl["respect"] = clampf(float(rl.get("respect", 0.0)) + 30.0, -100.0, 100.0)
				rl["loyalty"] = clampf(float(rl.get("loyalty", 0.0)) + 25.0, -100.0, 100.0)
				_say(msgs, "%s has finished their training with you and goes out into the world." % n["name"])
				player["achievements"] = int(player.get("achievements", 0)) + 1
	_taught_today = false
	# Pupils ask YOU once you are a master of something.
	var top := 0.0
	var top_craft := ""
	for k: String in (player["skills"] as Dictionary):
		if float(player["skills"][k]) > top:
			top = float(player["skills"][k])
			top_craft = k
	if top >= 50.0 and student_requests_list.size() < 2 and _near_sid >= 0:
		var r := _rng("stud", _day, _near_sid)
		if r.randf() < 0.1:
			var here := npcs_in(_near_sid)
			if not here.is_empty():
				var id: String = here[r.randi() % here.size()]
				student_requests_list.append({"npc": id, "craft": top_craft, "text": "%s asks you to teach them %s." % [npcs[id]["name"], top_craft]})


# ------------------------------------------------------- L§46 stories

func log_failure(kind: String, text: String, sid: int = -1) -> void:
	var hooks := {"evicted": "Look for a cheaper room in the slums; people there pay for favours.",
		"fired": "Without pay, the day-labour gangs and the back-alley jobs are the only doors open.",
		"inn_theft": "Somebody in the taproom knows who did it. Ask around, or make a name in the underworld.",
		"marriage": "Someone will be glad to console a lonely spouse; or a debt is behind it.",
		"guild_expelled": "The hall's doors are shut, but a rival guild may have use for you.",
		"hidden_trial": "The people in the dark remember failure; they may give you one more chance, or a warning.",
		"apprenticeship": "Old masters talk. Find a humbler teacher and prove yourself."}
	stories.append({"id": _new_id("s"), "day": _day, "kind": kind, "text": text, "sid": sid,
		"hook": String(hooks.get(kind, "A door closes; another opens.")), "resolved": false})
	if stories.size() > 30:
		stories.pop_front()
	_pending_msgs.append("Story: " + text)


func story_hooks(include_resolved: bool = false) -> Array:
	var out: Array = []
	for s: Dictionary in stories:
		if include_resolved or not s["resolved"]:
			out.append(s.duplicate())
	return out


func resolve_story(id: String) -> bool:
	for s: Dictionary in stories:
		if s["id"] == id:
			s["resolved"] = true
			return true
	return false


# ------------------------------------------------------ L§48 knowledge

func learn(fact: String, text: String = "") -> bool:
	if knowledge.has(fact):
		return false
	knowledge[fact] = {"day": _day, "text": text}
	var city := _city()
	if city != null and city.has_method("on_fact"):
		city.on_fact(fact)
	return true


func knows(fact: String) -> bool:
	return knowledge.has(fact)


func known_count(prefix: String = "") -> int:
	if prefix == "":
		return knowledge.size()
	var n := 0
	for k: String in knowledge:
		if k.begins_with(prefix):
			n += 1
	return n


func knowledge_level(sid: int) -> String:
	var n := known_count("place:%d:" % sid) + known_count("contact:") / 3
	if n >= 8:
		return "native"
	if n >= 4:
		return "local"
	if n >= 1:
		return "newcomer"
	return "stranger"


func dialogue_unlocks() -> Array:
	## "topic:<x>" facts open "ask about x"; "secret:<x>" opens leverage lines.
	var out: Array = []
	for k: String in knowledge:
		if k.begins_with("topic:"):
			out.append("Ask about %s" % k.substr(6).replace("_", " "))
		elif k.begins_with("secret:"):
			out.append("Confront them about %s" % k.substr(7).replace("_", " "))
		elif k.begins_with("place:"):
			var parts := k.split(":")
			if parts.size() >= 3:
				out.append("Give directions to the %s" % parts[2])
	out.sort()
	return out


func leads() -> Array:
	var out: Array = []
	for k: String in knowledge:
		var has_text := String(knowledge[k]["text"]) != ""
		if k.begins_with("lead:") or (has_text and (k.begins_with("secret:") or k.begins_with("contact:"))):
			out.append({"fact": k, "text": String(knowledge[k]["text"])})
	return out


# ------------------------------------------------------------------ ticks

func tick_hour(hour: int, ctx: Dictionary) -> Array:
	_sync(ctx)
	_hour = hour
	_step_rumours()
	var out := _flush()
	return _filter_events(out)


func _filter_events(msgs: Array) -> Array:
	var out: Array = []
	for m: Variant in msgs:
		var s := String(m)
		if s.begins_with("__event:"):
			var p := s.split(":")
			events_due.append({"kind": p[1], "npc": p[2], "day": int(p[3])})
		else:
			out.append(s)
	return out


## Delayed consequences waiting for their day ("assassins", "ambush").
var events_due: Array = []


func tick_day(day: int, ctx: Dictionary) -> Array:
	var msgs: Array = []
	_sync(ctx)
	_day = day
	_ensure_npcs()
	_mirror_life(ctx)
	_decay_reputation()
	_tick_crime_day(msgs)
	_tick_marriage(msgs)
	_tick_goals(msgs)
	_tick_offers()
	_tick_teaching(msgs)
	_tick_memory()
	_run_events(msgs)
	# Expire rumours.
	for i in range(rumour_list.size() - 1, -1, -1):
		if float(rumour_list[i]["expires"]) <= _now:
			rumour_list.remove_at(i)
	_fame_cache.clear()
	msgs.append_array(_filter_events(_flush()))
	return msgs


func _run_events(msgs: Array) -> void:
	for i in range(events_due.size() - 1, -1, -1):
		var e: Dictionary = events_due[i]
		if int(e["day"]) <= _day:
			events_due.remove_at(i)
			var n: Dictionary = npcs.get(String(e["npc"]), {})
			if n.is_empty() or not bool(n["alive"]):
				continue
			match String(e["kind"]):
				"assassins":
					_say(msgs, "Hired blades were sent for you by %s. They found you, or they will." % n["name"])
					add_rumour("crime", int(n["sid"]), 1.0, "unknown", -1.0, "assault")
				"ambush":
					_say(msgs, "%s and some friends ambush you in a lane." % n["name"])
			remember(String(e["npc"]), "insulted", -1.0)


func _decay_reputation() -> void:
	for k: String in reputation.keys():
		var v := float(reputation[k])
		if absf(v) > 1.0:
			reputation[k] = v * 0.998
	for k: String in crim.keys():
		var v2 := float(crim[k])
		if absf(v2) > 1.0:
			crim[k] = v2 * 0.9985


func _tick_memory() -> void:
	## Memories fade slowly; the heavy ones (kin, children) barely at all.
	for id: String in npcs:
		var mem: Array = npcs[id]["memory"]
		if mem.is_empty():
			continue
		for i in range(mem.size() - 1, -1, -1):
			var w := float(mem[i]["w"])
			var k := 0.997 if bool(mem[i].get("heavy", false)) else 0.985
			mem[i]["w"] = w * k
			if absf(float(mem[i]["w"])) < 0.15:
				mem.remove_at(i)


func tick_week(week: int, ctx: Dictionary) -> Array:
	_sync(ctx)
	# Family requests: relatives' problems become yours.
	var msgs: Array = []
	if not marriage.is_empty() and String(marriage["status"]) == "married" and in_law_requests.size() < 3:
		var r := _rng("inlaw", week, 0)
		if r.randf() < 0.3:
			var req: String = _pick(r, FAMILY_REQUESTS)
			var fam := in_laws()
			if not fam.is_empty():
				var who: String = fam[r.randi() % fam.size()]
				in_law_requests.append({"id": _new_id("f"), "npc": who, "text": "%s: %s" % [npcs[who]["name"], req]})
				_say(msgs, "Family trouble: %s." % in_law_requests[-1]["text"])
	return msgs


func help_family(request_id: String) -> bool:
	for i in in_law_requests.size():
		if in_law_requests[i]["id"] == request_id:
			var npc_id: String = in_law_requests[i]["npc"]
			in_law_requests.remove_at(i)
			interact(npc_id, "help")
			if not marriage.is_empty():
				marriage["happiness"] = minf(100.0, float(marriage["happiness"]) + 6.0)
			return true
	return false


func catch_up(days: int, ctx: Dictionary) -> Array:
	var msgs: Array = []
	if days <= 0:
		return msgs
	_sync(ctx)
	_ensure_npcs()
	_day += days
	# Reputation, memory, criminal reputation: closed-form exponential decay.
	var fr := pow(0.998, float(days))
	for k: String in reputation.keys():
		reputation[k] = float(reputation[k]) * fr
	var cr := pow(0.9985, float(days))
	for k: String in crim.keys():
		crim[k] = float(crim[k]) * cr
	# Evidence: linear decay by type; investigations resolve by expected value.
	for i in range(evidence_items.size() - 1, -1, -1):
		var e: Dictionary = evidence_items[i]
		e["strength"] = float(e["strength"]) - float(EVIDENCE_DECAY.get(e["type"], 0.02)) * float(days)
		if float(e["strength"]) <= 0.05:
			evidence_items.remove_at(i)
	for i in range(investigations.size() - 1, -1, -1):
		var inv: Dictionary = investigations[i]
		var s := 0.0
		for e: Dictionary in evidence_items:
			if e["crime"] == inv["crime"]:
				s += float(e["strength"])
		var gain := (0.04 + s * 0.06 + (0.05 if inv["identified"] else 0.0)) * float(days)
		inv["progress"] = float(inv["progress"]) + gain
		if float(inv["progress"]) >= 1.0 and (inv["identified"] or s > 0.4):
			var amt := 60
			for c: Dictionary in crimes:
				if c["id"] == inv["crime"]:
					amt = int(CRIMES[c["kind"]]["fine"]) * 2
					c["solved"] = true
			bounties[str(inv["sid"])] = int(bounties.get(str(inv["sid"]), 0)) + amt
			_say(msgs, "While you were away the watch in %s put a price of %d gold on you." % [_sname(int(inv["sid"])), amt])
			investigations.remove_at(i)
		elif float(inv["progress"]) >= 1.0:
			investigations.remove_at(i)
	# Bounties fade slightly.
	for k: String in bounties.keys():
		bounties[k] = int(float(bounties[k]) * pow(0.997, float(days)))
		if int(bounties[k]) < 5:
			bounties.erase(k)
	# Memory decays in one multiplication per record.
	for id: String in npcs:
		var mem: Array = npcs[id]["memory"]
		for i in range(mem.size() - 1, -1, -1):
			var w := float(mem[i]["w"])
			mem[i]["w"] = w * pow(0.997 if bool(mem[i].get("heavy", false)) else 0.985, float(days))
			if absf(float(mem[i]["w"])) < 0.15:
				mem.remove_at(i)
	# Rumours travel: fast-forward every pending hop that fits in the elapsed time.
	_now += float(days) * 24.0
	var guard := 0
	while not _hops.is_empty() and guard < 200:
		guard += 1
		_step_rumours()
	# Goals: one expected completion per NPC at most.
	var cr2 := _rng("gcatch", _day, 0)
	for i in NPC_COUNT:
		var id := "n%d" % i
		if not npcs.has(id):
			continue
		var n: Dictionary = npcs[id]
		if (n["goals"] as Array).is_empty():
			continue
		var g: Dictionary = n["goals"][0]
		var p := 1.0 - pow(1.0 - 0.09, float(days))
		if cr2.randf() < p:
			g["step"] = mini(int(g["steps"]) - 1, int(g["step"]) + maxi(1, days / 12))
	# Marriage: neglect accrues in closed form.
	if not marriage.is_empty() and String(marriage["status"]) == "married":
		var away := _day - int(marriage["last_together"])
		if away > 10:
			marriage["happiness"] = maxf(0.0, float(marriage["happiness"]) - float(mini(days, away - 10)) * 0.7)
			if float(marriage["happiness"]) < 15.0:
				marriage["status"] = "estranged"
				_say(msgs, "Your spouse grew tired of waiting; the marriage is in trouble.")
	# Apprenticeships stall while you are gone.
	if not apprenticeship.is_empty() and days >= 6:
		apprenticeship = {}
		_say(msgs, "Your master gave your place to someone else while you were gone.")
	if days >= 12:
		students.clear()
	_fame_cache.clear()
	msgs.append_array(_filter_events(_flush()))
	if days >= 3 and not msgs.is_empty():
		msgs.push_front("While you were away, the realm's people went on with their lives.")
	return msgs


# ---------------------------------------------------------------- save/load

func serialize() -> Dictionary:
	return {"player": player.duplicate(true), "pending": pending_gold, "rep": reputation.duplicate(), "crim": crim.duplicate(),
		"rep_log": _rep_log.duplicate(true), "npcs": npcs.duplicate(true), "houses": houses.duplicate(true), "feuds": feuds.duplicate(true),
		"courtship": courtship.duplicate(true), "marriage": marriage.duplicate(true), "in_law_requests": in_law_requests.duplicate(true),
		"outfit": outfit.duplicate(), "crimes": crimes.duplicate(true), "evidence": evidence_items.duplicate(true),
		"investigations": investigations.duplicate(true), "bounties": bounties.duplicate(), "rumours": rumour_list.duplicate(true),
		"hops": _hops.duplicate(true), "stories": stories.duplicate(true), "msgs": _pending_msgs.duplicate(), "knowledge": knowledge.duplicate(true),
		"offers": offers_list.duplicate(true), "apprenticeship": apprenticeship.duplicate(true), "students": students.duplicate(true),
		"student_requests": student_requests_list.duplicate(true), "next_id": _next_id, "day": _day, "hour": _hour, "now": _now,
		"has_npcs": _has_npcs, "school": _school, "events": events_due.duplicate(true)}


static func _intify(v: Variant) -> Variant:
	if v is Dictionary:
		var out := {}
		for k: Variant in v:
			out[k] = _intify(v[k])
		return out
	if v is Array:
		var a: Array = []
		for x: Variant in v:
			a.append(_intify(x))
		return a
	if v is float and is_equal_approx(v, round(v)) and absf(v) < 1.0e12:
		return int(v)
	return v


func deserialize(d: Dictionary) -> void:
	var n: Dictionary = _intify(d)
	var base := {"combat": 10, "gold": 0, "fame": 0, "title": 0, "family": 0, "class": 1, "age": 20, "sex": "m",
		"values": {"honor": 0.5, "wealth": 0.5, "tradition": 0.5, "freedom": 0.5}, "personality": {"kindness": 0.5, "temper": 0.5, "ambition": 0.5, "openness": 0.5},
		"lifestyle": "adventurous", "religion": "none", "culture": "martial", "career": "", "politics": "crown", "wants_children": true,
		"land": false, "wealth_score": 0, "refs": 0, "skills": {}, "dangerous": true, "achievements": 0, "sid": 0}
	player = base
	for k: String in n.get("player", {}):
		player[k] = n["player"][k]
	pending_gold = int(n.get("pending", 0))
	reputation = n.get("rep", {})
	crim = n.get("crim", {})
	_rep_log = n.get("rep_log", [])
	npcs = n.get("npcs", {})
	houses = n.get("houses", {})
	feuds = n.get("feuds", [])
	courtship = n.get("courtship", {})
	marriage = n.get("marriage", {})
	in_law_requests = n.get("in_law_requests", [])
	outfit = n.get("outfit", {"kind": "travel", "dirty": true, "disguise": 0.0})
	crimes = n.get("crimes", [])
	evidence_items = n.get("evidence", [])
	investigations = n.get("investigations", [])
	bounties = n.get("bounties", {})
	rumour_list = n.get("rumours", [])
	_hops = n.get("hops", [])
	stories = n.get("stories", [])
	_pending_msgs = n.get("msgs", [])
	knowledge = n.get("knowledge", {})
	offers_list = n.get("offers", [])
	apprenticeship = n.get("apprenticeship", {})
	students = n.get("students", [])
	student_requests_list = n.get("student_requests", [])
	_next_id = int(n.get("next_id", 1))
	_day = int(n.get("day", 0))
	_hour = int(n.get("hour", 8))
	_now = float(n.get("now", 0.0))
	_has_npcs = bool(n.get("has_npcs", false))
	_school = bool(n.get("school", false))
	events_due = n.get("events", [])
	_fame_cache.clear()
	_nbr_sig = -1
