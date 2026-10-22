extends "res://scripts/realm/realm_module.gd"
## Career call-ups (docs/design/ACADEMY_PLAN.md "Everyone learns to fight").
##
## Whatever the player's trade, trouble finds it: the smithy's ore shipment is
## stolen, wolves reach a neighbour's farm, a caravan you supply goes missing, the
## militia levy is called in wartime. The employer, guild, neighbours or an
## authority ask the player for help. Who gets asked depends on the quality of the
## work (job performance, employment reputation), the local reputation and the
## fighting ability people KNOW you have (education.known_ability).
##
## Output is data only: offers {id, npc, npc_name, text, sid, reward, deadline, ...}
## that in-world NPC dialogue delivers later (mark_delivered). Never a marker.
##
## API: offers(), active(), accept(id), complete(id, quality), fail(id), decline(id),
## mark_delivered(id). Pure data, deterministic, JSON-safe, catch_up is O(offers).
##
## Cross-module (guarded): city_life.job()/accomplish, society (rep, npcs_in, add_rep),
## education (known_ability), settlements (emergencies, add_stock), ctx["life"].careers.
## Money rule: never touches the purse; Life calls take_pending_gold().

const MAX_OPEN := 3
const BASE_DAILY := 0.11
const COOLDOWN_DAYS := 3
const HISTORY_MAX := 24
const LEVY_EVERY := 30
const FIRST := ["Aldric", "Brenna", "Corin", "Dessa", "Edmar", "Fenna", "Gorm", "Hilda", "Ivo", "Jorun", "Kessa", "Lorn", "Mira", "Nils", "Orla", "Pell", "Quin", "Rhea", "Sten", "Tova"]
const LAST := ["Ashby", "Brook", "Crane", "Dunn", "Ember", "Fallow", "Gray", "Hale", "Ironside", "Marsh", "Nettle", "Oakes", "Pike", "Reed", "Stone", "Thorne"]

## city_life job template -> call-up group
const JOB_GROUPS := {
	"smith": "smith", "smith_apprentice": "smith", "harvest_hand": "farm", "clerk": "caravan", "caravan_guard": "caravan", "stall_hand": "caravan",
	"city_guard": "guard", "dockhand": "dock", "acolyte": "temple", "servant": "noble", "scribe": "noble", "weaver": "craft", "day_labour": "labour",
}
## Keywords for careers.gd seats when city_life has no job.
const SEAT_WORDS := {"smith": "smith", "guard": "guard", "soldier": "guard", "farm": "farm", "merchant": "caravan", "caravan": "caravan", "priest": "temple", "clerk": "caravan"}
## role in society for the asking NPC
const FROM_JOBS := {"employer": ["smith", "merchant", "master craftsman", "captain", "guildmaster"], "neighbour": ["farmhand", "labourer", "hunter", "weaver", "baker"],
	"authority": ["captain", "guard", "knight", "magistrate"], "guild": ["guildmaster", "master craftsman", "merchant"]}

## {groups, from, kind, danger 0..1, min_ability, reward{gold, rep, item}, deadline days, weight, war (only in war), text}
const TEMPLATES := {
	"stolen_ore": {"groups": ["smith"], "from": "employer", "kind": "recover", "danger": 0.45, "min_ability": 20.0, "reward": {"gold": 60, "rep": 3.0, "item": "ore"},
		"deadline": 6, "weight": 1.0, "war": false, "fail_stock": ["iron", -3.0],
		"text": "%s: \"The ore shipment never reached the forge. Bandits took it on the road. You can handle yourself; will you get it back?\"",
		"soft": "%s: \"The ore shipment was stolen. I need someone to track where it went; I will send others to fight.\""},
	"forge_rush": {"groups": ["smith"], "from": "employer", "kind": "work", "danger": 0.0, "min_ability": 0.0, "reward": {"gold": 30, "rep": 1.5, "item": ""},
		"deadline": 4, "weight": 0.7, "war": false, "text": "%s: \"A garrison order came in overnight. I need every hammer at the forge; will you stay late?\"", "soft": ""},
	"wolves_at_farm": {"groups": ["farm", "any"], "from": "neighbour", "kind": "hunt", "danger": 0.35, "min_ability": 15.0, "reward": {"gold": 25, "rep": 2.5, "item": "pelt"},
		"deadline": 4, "weight": 1.0, "war": false, "text": "%s: \"Wolves are at my farm and they took two lambs last night. You can use a blade. Will you help?\"",
		"soft": "%s: \"Wolves are at my farm. I cannot fight them but I can use another pair of eyes on the night watch.\""},
	"missing_caravan": {"groups": ["caravan"], "from": "employer", "kind": "search", "danger": 0.4, "min_ability": 18.0, "reward": {"gold": 55, "rep": 3.0, "item": ""},
		"deadline": 8, "weight": 1.0, "war": false, "fail_stock": ["tools", -2.0],
		"text": "%s: \"The caravan you helped stock is three days late. Find out what happened; be ready for trouble.\"",
		"soft": "%s: \"The caravan is late. Ask along the road and tell me what you hear.\""},
	"bandit_patrol": {"groups": ["guard"], "from": "authority", "kind": "patrol", "danger": 0.5, "min_ability": 25.0, "reward": {"gold": 45, "rep": 3.0, "item": ""},
		"deadline": 3, "weight": 1.0, "war": false, "text": "%s: \"Bandits have been robbing the road at dusk. You are on the patrol tonight.\"", "soft": ""},
	"smugglers": {"groups": ["dock"], "from": "employer", "kind": "watch", "danger": 0.4, "min_ability": 20.0, "reward": {"gold": 40, "rep": 2.0, "item": ""},
		"deadline": 4, "weight": 1.0, "war": false, "text": "%s: \"Cargo has been vanishing from the quay at night. Watch the warehouse with me.\"", "soft": ""},
	"relic_theft": {"groups": ["temple"], "from": "guild", "kind": "recover", "danger": 0.3, "min_ability": 12.0, "reward": {"gold": 35, "rep": 3.0, "item": ""},
		"deadline": 6, "weight": 1.0, "war": false, "text": "%s: \"A relic was stolen from the shrine. You know the faithful; help us find it.\"", "soft": ""},
	"escort_message": {"groups": ["noble"], "from": "employer", "kind": "escort", "danger": 0.25, "min_ability": 10.0, "reward": {"gold": 30, "rep": 2.0, "item": ""},
		"deadline": 5, "weight": 0.8, "war": false, "text": "%s: \"This letter must reach the next town by nightfall, and the road is not safe. Will you carry it?\"", "soft": ""},
	"fire_alarm": {"groups": ["craft", "labour", "any"], "from": "neighbour", "kind": "rescue", "danger": 0.2, "min_ability": 0.0, "reward": {"gold": 10, "rep": 3.5, "item": ""},
		"deadline": 1, "weight": 0.5, "war": false, "text": "%s: \"There is a fire in the row! Bring buckets!\"", "soft": ""},
	"wolves_near_village": {"groups": ["any"], "from": "neighbour", "kind": "hunt", "danger": 0.3, "min_ability": 15.0, "reward": {"gold": 20, "rep": 2.5, "item": ""},
		"deadline": 4, "weight": 0.8, "war": false, "text": "%s: \"Something has been taking dogs at the edge of the village. You have a steady hand; will you sit up tonight?\"",
		"soft": "%s: \"Something has been taking dogs from the village edge. Keep your eyes open for us?\""},
	"lost_child": {"groups": ["any"], "from": "neighbour", "kind": "search", "danger": 0.15, "min_ability": 0.0, "reward": {"gold": 5, "rep": 4.0, "item": ""},
		"deadline": 2, "weight": 0.6, "war": false, "text": "%s: \"My little one has not come home. Please help us look before dark.\"", "soft": ""},
	"stall_thief": {"groups": ["caravan", "guard"], "from": "employer", "kind": "recover", "danger": 0.25, "min_ability": 10.0, "reward": {"gold": 20, "rep": 2.0, "item": ""},
		"deadline": 3, "weight": 0.0, "war": false, "job": true, "text": "%s: \"A thief cleaned out the till and ran for the alleys. You saw his face; will you find him?\"",
		"soft": "%s: \"A thief took from the stall. Ask around the market and tell me what you hear.\""},
	"tavern_brawl": {"groups": ["guard", "any"], "from": "employer", "kind": "rescue", "danger": 0.3, "min_ability": 15.0, "reward": {"gold": 18, "rep": 2.5, "item": ""},
		"deadline": 2, "weight": 0.0, "war": false, "job": true, "text": "%s: \"The brawl spilled out; the ringleaders are still in the street. Help me lock them up.\"",
		"soft": "%s: \"The brawl left a mess and a hurt man. Help me get him to the healer and take names.\""},
	"sick_herd": {"groups": ["farm", "any"], "from": "neighbour", "kind": "work", "danger": 0.0, "min_ability": 0.0, "reward": {"gold": 22, "rep": 2.5, "item": ""},
		"deadline": 4, "weight": 0.0, "war": false, "job": true, "text": "%s: \"The sickness is spreading to my animals. Will you help me cull, isolate and burn the bedding?\"", "soft": ""},
	"plague_ward": {"groups": ["temple", "any"], "from": "authority", "kind": "work", "danger": 0.1, "min_ability": 0.0, "reward": {"gold": 30, "rep": 4.0, "item": ""},
		"deadline": 5, "weight": 0.0, "war": false, "job": true, "text": "%s: \"There is fever in the row. I need steady hands to carry water and keep the doors shut.\"", "soft": ""},
	"timber_theft": {"groups": ["labour", "any"], "from": "employer", "kind": "recover", "danger": 0.4, "min_ability": 18.0, "reward": {"gold": 35, "rep": 2.5, "item": ""},
		"deadline": 4, "weight": 0.0, "war": false, "job": true, "text": "%s: \"Strangers took a wagon of cut oak. Their tracks head for the ford; can you stop them?\"",
		"soft": "%s: \"Timber went missing. Ask at the mills who bought oak this week.\""},
	"cave_in": {"groups": ["labour", "any"], "from": "employer", "kind": "rescue", "danger": 0.3, "min_ability": 10.0, "reward": {"gold": 40, "rep": 4.5, "item": ""},
		"deadline": 1, "weight": 0.0, "war": false, "job": true, "text": "%s: \"The face came down with men behind it! Bring lamps and ropes!\"", "soft": ""},
	"militia_levy": {"groups": ["any"], "from": "authority", "kind": "levy", "danger": 0.6, "min_ability": 10.0, "reward": {"gold": 30, "rep": 4.0, "item": ""},
		"deadline": 3, "weight": 0.0, "war": true, "levy": true,
		"text": "%s: \"The crown has called the militia levy. Every able hand reports to the muster tomorrow at dawn.\"",
		"soft": "%s: \"The militia levy is called. Not everyone carries a spear: we need carters and cooks at the muster too.\""},
}

var player: Dictionary = {"sid": 0, "age": 20, "combat": 0.0, "gold": 0, "job_tpl": "", "performance": -1.0, "employer": "", "rep": 0.0}
var pending_gold: int = 0
var offers_list: Array = []
var history: Array = []
var _next_id := 1
var _day := 0
var _at_war := false
var _was_war := false
var _last_offer_day := -99
var _last_levy_day := -99


# ---------------------------------------------------------------- helpers

func _rng(tag: String, day: int, id: Variant) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash([WorldSim.SEED, tag, day, str(id)])
	return r


func _pick(r: RandomNumberGenerator, arr: Array) -> Variant:
	return arr[r.randi() % arr.size()]


func _new_id() -> String:
	var s := "cu%d" % _next_id
	_next_id += 1
	return s


func _mod(name: String) -> RefCounted:
	if hub != null:
		return hub.mod(name)
	return null


func _sname(sid: int) -> String:
	if sid >= 0 and sid < WorldGen.settlements.size():
		return WorldGen.display_name(String(WorldGen.settlements[sid]["name"]))
	return "the road"


func set_player(d: Dictionary) -> void:
	for k: String in d:
		player[k] = d[k]


## Test / UI override for the profile (job_tpl, performance, employer, combat...).
func set_profile(d: Dictionary) -> void:
	set_player(d)


func take_pending_gold() -> int:
	var g := pending_gold
	pending_gold = 0
	return g


func _sync(ctx: Dictionary) -> void:
	_at_war = bool(ctx.get("at_war", false))
	if ctx.has("gold"):
		player["gold"] = int(ctx["gold"])
	if ctx.get("stats") is Dictionary:
		for k: String in ctx["stats"]:
			player[k] = ctx["stats"][k]
	var pp: Variant = ctx.get("player_pos")
	if pp is Vector2 or pp is Vector3:
		var p2: Vector2 = Vector2(pp.x, pp.z) if pp is Vector3 else pp
		var n := _nearest(p2)
		if n >= 0:
			player["sid"] = n
	var life: Variant = ctx.get("life")
	if life != null and life is Object and (life as Object).has_method("age"):
		player["age"] = int((life as Object).call("age"))


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


# ---------------------------------------------------------------- who is the player (job, trust, ability)

## The player's job as {group, tpl, performance, employer, emp_rep, sid}. Falls back to careers seats.
func profile(ctx := {}) -> Dictionary:
	var out := {"group": "none", "tpl": "", "performance": 50.0, "employer": "", "emp_rep": 50.0, "sid": int(player["sid"])}
	var cl := _mod("city_life")
	var job := {}
	if cl != null and cl.has_method("job"):
		job = cl.call("job")
	if not job.is_empty():
		out["tpl"] = String(job.get("tpl", ""))
		out["group"] = String(JOB_GROUPS.get(String(job.get("tpl", "")), "labour"))
		out["performance"] = float(job.get("performance", 60.0))
		out["employer"] = String(job.get("employer", ""))
		out["sid"] = int(job.get("sid", out["sid"]))
		if cl.has_method("employment_reputation"):
			out["emp_rep"] = float(cl.call("employment_reputation"))
	elif String(player.get("job_tpl", "")) != "":
		var tpl := String(player["job_tpl"])
		out["tpl"] = tpl
		out["group"] = String(JOB_GROUPS.get(tpl, "labour"))
		out["performance"] = float(player["performance"]) if float(player["performance"]) >= 0.0 else 60.0
		out["employer"] = String(player.get("employer", ""))
	else:
		var life: Variant = ctx.get("life")
		if life != null and life is Object:
			var cr: Variant = (life as Object).get("careers")
			if cr != null and cr is Object and (cr as Object).has_method("player_seat"):
				var seat: Variant = (cr as Object).call("player_seat")
				if seat is Dictionary and not (seat as Dictionary).is_empty():
					var title := String((seat as Dictionary).get("title", "")).to_lower()
					for w: String in SEAT_WORDS:
						if title.contains(w):
							out["group"] = String(SEAT_WORDS[w])
							break
					if out["group"] == "none":
						out["group"] = "guard"
	if float(player["performance"]) >= 0.0 and String(player.get("job_tpl", "")) != "" and job.is_empty():
		out["performance"] = float(player["performance"])
	return out


func trust(ctx := {}) -> float:
	var pr := profile(ctx)
	var t := 0.15 + float(pr["performance"]) / 100.0 * 0.5 + (float(pr["emp_rep"]) - 50.0) / 100.0 * 0.3
	var soc := _mod("society")
	if soc != null and soc.has_method("rep"):
		t += float(soc.call("rep", "city:%d" % int(pr["sid"]))) / 100.0 * 0.4
	t += float(player.get("rep", 0.0)) / 100.0 * 0.2
	return clampf(t, 0.05, 1.0)


func known_ability(sid := -1) -> float:
	var edu := _mod("education")
	if edu != null and edu.has_method("known_ability"):
		return float(edu.call("known_ability", sid))
	var soc := _mod("society")
	if soc != null and soc.has_method("player_tier"):
		return float(int(soc.call("player_tier")) - 1) * 13.0
	return float(player.get("combat", 0.0))


func _world_pressure(sid: int) -> float:
	var p := 0.0
	if _at_war:
		p += 0.5
	var sm := _mod("settlements")
	if sm != null and sm.has_method("emergencies"):
		for e: Dictionary in sm.call("emergencies", sid):
			if String(e.get("kind", "")) in ["raid", "raid_aftermath"]:
				p += 0.4
	return p


# ---------------------------------------------------------------- generation

func _npc_for(from: String, sid: int, r: RandomNumberGenerator, employer: String) -> Array:
	if from == "employer" and employer != "":
		return ["", employer]
	var soc := _mod("society")
	if soc != null and soc.has_method("npcs_in"):
		var wanted: Array = FROM_JOBS.get(from, [])
		var cands: Array = []
		for id: String in soc.call("npcs_in", sid):
			var n: Dictionary = soc.call("npc", id)
			if n.is_empty() or int(n.get("age", 30)) < 18:
				continue
			if String(n.get("job", "")) in wanted:
				cands.append([id, String(n["name"])])
		if cands.is_empty():
			for id: String in soc.call("npcs_in", sid):
				var n2: Dictionary = soc.call("npc", id)
				if not n2.is_empty() and int(n2.get("age", 30)) >= 18:
					cands.append([id, String(n2["name"])])
		if not cands.is_empty():
			return cands[r.randi() % cands.size()]
	return ["", "%s %s" % [_pick(r, FIRST), _pick(r, LAST)]]


func _make_offer(tid: String, day: int, sid: int, pr: Dictionary, r: RandomNumberGenerator) -> Dictionary:
	var t: Dictionary = TEMPLATES[tid]
	var ability := known_ability(sid)
	var role := "combat"
	var text: String = String(t["text"])
	var reward: Dictionary = (t["reward"] as Dictionary).duplicate()
	if float(t["min_ability"]) > 0.0 and ability < float(t["min_ability"]):
		if String(t["soft"]) == "":
			return {}
		role = "support"
		text = String(t["soft"])
		reward["gold"] = int(round(float(reward["gold"]) * 0.5))
	elif float(t["min_ability"]) == 0.0:
		role = "support"
	var who := _npc_for(String(t["from"]), sid, r, String(pr["employer"]))
	var scale := 0.9 + 0.3 * r.randf()
	reward["gold"] = int(round(float(reward["gold"]) * scale))
	return {"id": _new_id(), "template": tid, "kind": String(t["kind"]), "from": String(t["from"]), "npc": String(who[0]), "npc_name": String(who[1]),
		"text": text % String(who[1]), "sid": sid, "place": _sname(sid), "reward": reward, "deadline": day + int(t["deadline"]), "day": day, "status": "open",
		"role": role, "danger": float(t["danger"]), "delivered": false, "accepted_day": -1}


func _open_count() -> int:
	var n := 0
	for o: Dictionary in offers_list:
		if String(o["status"]) in ["open", "accepted"]:
			n += 1
	return n


func _has_template(tid: String) -> bool:
	for o: Dictionary in offers_list:
		if String(o["template"]) == tid and String(o["status"]) in ["open", "accepted"]:
			return true
	return false


## One day's roll. Returns the new offers (also stored).
func roll_day(day: int, ctx := {}) -> Array:
	var made: Array = []
	var pr := profile(ctx)
	var sid := int(pr["sid"]) if int(pr["sid"]) >= 0 else int(player["sid"])
	# The militia levy is a call to everyone, not a chance event.
	if _at_war and (not _was_war or day - _last_levy_day >= LEVY_EVERY) and int(player["age"]) >= 16 and not _has_template("militia_levy"):
		var rl := _rng("levy", day, sid)
		var lo := _make_offer("militia_levy", day, sid, pr, rl)
		if not lo.is_empty():
			offers_list.append(lo)
			made.append(lo)
			_last_levy_day = day
	_was_war = _at_war
	if _open_count() >= MAX_OPEN or day - _last_offer_day < COOLDOWN_DAYS:
		return made
	var r := _rng("callup", day, sid)
	var employed := String(pr["group"]) != "none"
	var p := BASE_DAILY * (0.4 + trust(ctx) * 1.2) * (1.0 + _world_pressure(sid)) * (1.0 if employed else 0.5)
	if r.randf() >= p:
		return made
	var pool: Array = []
	var weights: Array = []
	for tid: String in TEMPLATES:
		var t: Dictionary = TEMPLATES[tid]
		if bool(t["war"]) and not _at_war:
			continue
		if float(t["weight"]) <= 0.0 or _has_template(tid):
			continue
		var g: Array = t["groups"]
		var fit := 0.0
		if String(pr["group"]) in g:
			fit = 1.0
		elif "any" in g:
			fit = 0.45
		if fit <= 0.0:
			continue
		pool.append(tid)
		weights.append(float(t["weight"]) * fit)
	if pool.is_empty():
		return made
	var tot := 0.0
	for w: float in weights:
		tot += w
	var roll := r.randf() * tot
	var chosen: String = String(pool[pool.size() - 1])
	for i in pool.size():
		roll -= float(weights[i])
		if roll <= 0.0:
			chosen = String(pool[i])
			break
	var o := _make_offer(chosen, day, sid, pr, r)
	if o.is_empty():
		return made
	offers_list.append(o)
	made.append(o)
	_last_offer_day = day
	return made


## A job-generated trigger (work.gd problems): raise a specific offer now instead of the daily
## roll. `employer` names the asker for employer templates. Returns the offer or {} when it is
## already open, the board is full, or the template does not exist.
func raise_offer(tid: String, day: int, sid: int, employer := "") -> Dictionary:
	if not TEMPLATES.has(tid) or _has_template(tid) or _open_count() >= MAX_OPEN + 1:
		return {}
	var pr := profile()
	pr["employer"] = employer if employer != "" else String(pr["employer"])
	var r := _rng("jobcallup", day, "%s%d" % [tid, sid])
	var o := _make_offer(tid, day, sid, pr, r)
	if o.is_empty():
		return {}
	o["job_trigger"] = true
	offers_list.append(o)
	_last_offer_day = day
	return o


# ---------------------------------------------------------------- API

func offers() -> Array:
	var out: Array = []
	for o: Dictionary in offers_list:
		if String(o["status"]) == "open":
			out.append(o.duplicate(true))
	return out


func active() -> Array:
	var out: Array = []
	for o: Dictionary in offers_list:
		if String(o["status"]) == "accepted":
			out.append(o.duplicate(true))
	return out


func offer(id: String) -> Dictionary:
	for o: Dictionary in offers_list:
		if String(o["id"]) == id:
			return o.duplicate(true)
	return {}


func _find(id: String) -> Dictionary:
	for o: Dictionary in offers_list:
		if String(o["id"]) == id:
			return o
	return {}


## NPC dialogue delivered it.
func mark_delivered(id: String) -> void:
	var o := _find(id)
	if not o.is_empty():
		o["delivered"] = true


func accept(id: String) -> Dictionary:
	var o := _find(id)
	if o.is_empty() or String(o["status"]) != "open":
		return {"ok": false, "reason": "That request is no longer open."}
	if _day > int(o["deadline"]):
		o["status"] = "expired"
		return {"ok": false, "reason": "It is too late."}
	o["status"] = "accepted"
	o["accepted_day"] = _day
	return {"ok": true, "offer": o.duplicate(true), "reason": ""}


func decline(id: String) -> bool:
	var o := _find(id)
	if o.is_empty() or String(o["status"]) != "open":
		return false
	o["status"] = "declined"
	_archive(o)
	if bool((TEMPLATES[String(o["template"])] as Dictionary).get("levy", false)):
		_rep_add(o, -2.0, "refused the levy")
	return true


func _rep_add(o: Dictionary, d: float, why: String) -> void:
	var soc := _mod("society")
	if soc != null and soc.has_method("add_rep"):
		soc.call("add_rep", "city:%d" % int(o["sid"]), d, why)


func _archive(o: Dictionary) -> void:
	history.append({"id": o["id"], "template": o["template"], "status": o["status"], "day": _day})
	if history.size() > HISTORY_MAX:
		history.pop_front()
	# Keep the live list short: drop finished offers older than a week.
	var keep: Array = []
	for x: Dictionary in offers_list:
		if String(x["status"]) in ["open", "accepted"] or _day - int(x["deadline"]) < 7:
			keep.append(x)
	offers_list = keep


## Report success. quality 0..1.2 scales the reward. Returns {ok, gold, rep}.
func complete(id: String, quality := 1.0) -> Dictionary:
	var o := _find(id)
	if o.is_empty() or String(o["status"]) != "accepted":
		return {"ok": false, "reason": "You never took that on."}
	var q := clampf(quality, 0.0, 1.2)
	o["status"] = "completed"
	var rw: Dictionary = o["reward"]
	var gold := int(round(float(rw["gold"]) * q))
	pending_gold += gold
	var rep := float(rw["rep"]) * q
	_rep_add(o, rep, "call-up")
	var cl := _mod("city_life")
	if cl != null and cl.has_method("accomplish") and String(o["from"]) in ["employer", "guild"]:
		cl.call("accomplish", "callup", 1.5 * q)
	_archive(o)
	return {"ok": true, "gold": gold, "rep": snappedf(rep, 0.01), "item": String(rw.get("item", "")), "reason": ""}


## The job went wrong or was abandoned. Trust with the asker drops and the world pays.
func fail(id: String) -> Dictionary:
	var o := _find(id)
	if o.is_empty() or not (String(o["status"]) in ["accepted", "open"]):
		return {"ok": false, "reason": "Nothing to fail."}
	o["status"] = "failed"
	var t: Dictionary = TEMPLATES[String(o["template"])]
	var pen := -float((o["reward"] as Dictionary)["rep"]) * 0.8
	_rep_add(o, pen, "call-up failed")
	var cl := _mod("city_life")
	if cl != null and cl.has_method("accomplish") and String(o["from"]) in ["employer", "guild"]:
		cl.call("accomplish", "callup_failed", -1.5)
	if t.has("fail_stock"):
		var sm := _mod("settlements")
		if sm != null and sm.has_method("add_stock"):
			sm.call("add_stock", int(o["sid"]), String(t["fail_stock"][0]), float(t["fail_stock"][1]))
	_archive(o)
	return {"ok": true, "rep": snappedf(pen, 0.01), "reason": "%s will remember this." % String(o["npc_name"])}


# ---------------------------------------------------------------- ticks

func tick_hour(_hour: int, _ctx: Dictionary) -> Array:
	return []


func tick_day(day: int, ctx: Dictionary) -> Array:
	_sync(ctx)
	_day = day
	var out: Array[String] = []
	for o: Dictionary in offers_list:
		if String(o["status"]) == "open" and day > int(o["deadline"]):
			o["status"] = "expired"
			_archive(o)
		elif String(o["status"]) == "accepted" and day > int(o["deadline"]) + 1:
			fail(String(o["id"]))
			out.append("You let %s down: the request went unanswered." % String(o["npc_name"]))
	for o: Dictionary in roll_day(day, ctx):
		if String(o["template"]) == "militia_levy":
			out.append("A levy notice is being read in %s." % String(o["place"]))
	return out


func tick_week(_week: int, _ctx: Dictionary) -> Array:
	return []


## Statistical resolution: expire, then at most a couple of expected requests. O(offers).
func catch_up(days: int, ctx: Dictionary) -> Array:
	_sync(ctx)
	var out: Array[String] = []
	if days < 1:
		return out
	var day := _day + days
	_day = day
	for o: Dictionary in offers_list:
		if String(o["status"]) == "open" and day > int(o["deadline"]):
			o["status"] = "expired"
		elif String(o["status"]) == "accepted" and day > int(o["deadline"]) + 1:
			o["status"] = "failed"
			_rep_add(o, -float((o["reward"] as Dictionary)["rep"]) * 0.8, "call-up failed")
			out.append("While you were away a request went unanswered.")
	var keep: Array = []
	for o: Dictionary in offers_list:
		if String(o["status"]) in ["open", "accepted"]:
			keep.append(o)
	offers_list = keep
	var pr := profile(ctx)
	var sid := int(pr["sid"]) if int(pr["sid"]) >= 0 else int(player["sid"])
	var expected := BASE_DAILY * (0.4 + trust(ctx) * 1.2) * (1.0 + _world_pressure(sid)) * float(mini(days, 20)) / float(COOLDOWN_DAYS + 1)
	var r := _rng("callup_cu", day, sid)
	var n := mini(2, int(expected) + (1 if r.randf() < expected - floorf(expected) else 0))
	for i in n:
		if _open_count() >= MAX_OPEN:
			break
		_last_offer_day = -99
		var made := roll_day(day - 1 - i, ctx)
		if made.is_empty():
			# Force one: the world did ask while you were gone.
			var pool: Array = []
			for tid: String in TEMPLATES:
				var t: Dictionary = TEMPLATES[tid]
				if float(t["weight"]) > 0.0 and not bool(t["war"]) and (String(pr["group"]) in (t["groups"] as Array) or "any" in (t["groups"] as Array)) and not _has_template(tid):
					pool.append(tid)
			if not pool.is_empty():
				var o := _make_offer(String(pool[r.randi() % pool.size()]), day, sid, pr, r)
				if not o.is_empty():
					o["deadline"] = day + int(TEMPLATES[String(o["template"])]["deadline"])
					offers_list.append(o)
					made = [o]
		if not made.is_empty():
			out.append("Word was left for you while you were away: %s" % String(made[0]["npc_name"]))
	if out.size() > 4:
		out.resize(4)
	return out


# ---------------------------------------------------------------- save

func serialize() -> Dictionary:
	return {"player": player.duplicate(true), "pending_gold": pending_gold, "offers": offers_list.duplicate(true), "history": history.duplicate(true),
		"next_id": _next_id, "day": _day, "war": _at_war, "was_war": _was_war, "last_offer": _last_offer_day, "last_levy": _last_levy_day}


func deserialize(d: Dictionary) -> void:
	player = (d.get("player", player) as Dictionary).duplicate(true)
	pending_gold = int(d.get("pending_gold", 0))
	offers_list = (d.get("offers", []) as Array).duplicate(true)
	history = (d.get("history", []) as Array).duplicate(true)
	_next_id = int(d.get("next_id", 1))
	_day = int(d.get("day", 0))
	_at_war = bool(d.get("war", false))
	_was_war = bool(d.get("was_war", false))
	_last_offer_day = int(d.get("last_offer", -99))
	_last_levy_day = int(d.get("last_levy", -99))
