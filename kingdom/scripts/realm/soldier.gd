extends "res://scripts/realm/realm_module.gd"
## The Soldier career at the depth of the Scribe (F11): recruit -> private -> corporal -> sergeant -> lieutenant.
##
## Enlist at a Captain or guard post: kit issued through the equipment system, a post (a military outpost near
## Thornfield, else the town watch; the location is data) and a commanding officer. Muster at a set hour each
## morning is attendance. Duties are generated from data into library quests (scripts/quests) and run by a
## private QuestRunner: patrol (GoTo), gate watch (Wait + Protect), escort, clear a camp or den (Kill), deliver
## orders, investigate a crime report. Merit comes from duties, kills on duty, commendations and attendance;
## promotion also needs minimum service time, and rank grants pay, better kit and a squad (corporal and up).
## Crimes (from Society) cost merit and can demote; missing N musters is desertion: struck off, a bounty is left
## in Society and wages stop. Leave can be requested. All state is JSON-safe (serialize/deserialize).
##
## Pure rules live in scripts/sim/soldier_career.gd, the squad in scripts/sim/soldier_squad.gd.
## Money rule: never touches the purse; Life drains take_pending_gold() (the weekly wage and duty pay).
## RNG: hash([WorldSim.SEED, tag, day, id]).

const Career := preload("res://scripts/sim/soldier_career.gd")
const Squad := preload("res://scripts/sim/soldier_squad.gd")
const CareerLadders := preload("res://scripts/sim/career_ladders.gd")

const CAREER := "soldier"
const DISCIPLINE := "soldiering"
const SPHERE := "military"
const LOG_MAX := 24
const XP_DUTY := 0.6
const XP_MUSTER := 0.05
const SOUL_PER_DUTY := 3.2

var mastery_ref: RefCounted = null      # tests inject one; otherwise Life.mastery
var bio_ref: RefCounted = null          # likewise Life.biography
var gold_ref := -1                      # tests inject; otherwise Game.gold
var life_ref: Object = null             # kit issue: needs give/take/count and `equipment` (tests inject a stub)
var bus_ref: QuestBus = null            # tests inject their own; otherwise QuestBus.shared()
var settlements_ref: Array = []         # tests may inject; otherwise WorldGen.settlements
var sync_life := true                   # mirror rank into Life.career_id / career_rank (tests turn it off)

var pending_gold := 0
var active := false
var rank := 0
var since_day := 0                      # day the current rank began
var enlisted_day := 0
var merit := 0.0
var post: Dictionary = {}               # {id, name, kind, pos [x, y], radius, sid, places}
var officer: Dictionary = {}            # {id, name, title}
var attended: Dictionary = {}           # str(day) -> true (muster attended)
var missed_run := 0                     # consecutive missed musters
var missed_week := 0                    # missed musters since the last pay day (docks the wage)
var missed_total := 0
var leave_until := -1
var leave_ready := 0                    # first day another leave may be requested
var deserter := false
var struck_off := ""                    # "" | "desertion" | "discipline" (why the last service ended)
var banned_until := -1
var crimes_in_rank := 0
var crimes_total := 0
var demotions := 0
var crimes_seen: Array = []             # society crime ids already judged
var kit: Dictionary = {}                # slot -> item id issued so far
var stats: Dictionary = {}              # duties, kills, commendations, musters, patrols, <kind>...
var duty: Dictionary = {}               # today's duty: {kind, id, def, merit, gold, hours, text, day, state, kills, casualties}
var duty_log: Array = []                # recent {day, kind, text, result}
var squad := Squad.new()
var log_lines: Array = []
var _runner: QuestRunner = null
var _day := 0


# ---------------------------------------------------------------- helpers

func _rng(tag: String, day: int, id: Variant) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash([WorldSim.SEED, tag, day, str(id)])
	return r


func _mod(name: String) -> RefCounted:
	return hub.mod(name) if hub != null else null


func _mastery() -> RefCounted:
	if mastery_ref != null:
		return mastery_ref
	return Life.mastery if Life != null else null


func _bio() -> RefCounted:
	if bio_ref != null:
		return bio_ref
	return Life.biography if Life != null else null


func _gold() -> int:
	if gold_ref >= 0:
		return gold_ref
	return int(Game.gold) if Game != null else 0


func _settlements() -> Array:
	return settlements_ref if not settlements_ref.is_empty() else WorldGen.settlements


func _say(text: String) -> void:
	log_lines.append(text)
	if log_lines.size() > LOG_MAX:
		log_lines.pop_front()


func take_pending_gold() -> int:
	var g := pending_gold
	pending_gold = 0
	return g


func bump(stat: String, n := 1) -> void:
	stats[stat] = int(stats.get(stat, 0)) + n


func stat(name: String) -> int:
	return int(stats.get(name, 0))


func _gain(amount: float, day: int) -> void:
	var m := _mastery()
	if m != null and amount > 0.0:
		m.call("gain", DISCIPLINE, amount, day)


func _rep(delta: float) -> void:
	var b := _bio()
	if b != null and absf(delta) > 0.0001:
		b.call("change_rep", SPHERE, delta)


func military_rep() -> float:
	var b := _bio()
	return float(b.call("rep", SPHERE)) if b != null else 0.0


func rank_id() -> String:
	return Career.rank_id(rank)


func rank_title() -> String:
	return Career.rank_title(rank)


func ladder_rank_id() -> String:
	return Career.ladder_id(rank)


func days_in_rank(day: int) -> int:
	return day - since_day


func is_on_leave(day: int) -> bool:
	return active and leave_until >= day


func post_pos() -> Vector2:
	var p: Array = post.get("pos", [0.0, 0.0])
	return Vector2(float(p[0]), float(p[1]))


func at_post(p: Vector2) -> bool:
	return active and not post.is_empty() and p.distance_to(post_pos()) <= float(post.get("radius", 20.0))


## Troop cap the shared ladder table gives this rank (the company the old recruiter hands out).
func troops_cap() -> int:
	return Career.troops_for_rank(rank)


func weekly_wage() -> int:
	return Career.weekly_wage(rank) if active else 0


# ---------------------------------------------------------------- enlisting

## Why the player cannot enlist now, or "".
func enlist_refusal(day: int) -> String:
	if active:
		return "You already serve as %s." % rank_title()
	if sync_life and Life != null and Life.has_method("is_adult") and not Life.is_adult():
		return "The Guard takes no children. Grow strong, and come back at %d." % Life.ADULT_AGE
	if banned_until > day:
		return "You are struck off the rolls. No post will take you before day %d." % banned_until
	if _settlements().is_empty():
		return "There is no garrison here."
	return ""


## Enlist at a Captain or guard post ("captain" | "guard_post"). {ok, reason, text}.
func enlist(day: int, source := "captain") -> Dictionary:
	var why := enlist_refusal(day)
	if why != "":
		return {"ok": false, "reason": why}
	active = true
	rank = 0
	since_day = day
	enlisted_day = day
	merit = 0.0
	deserter = false
	struck_off = ""
	attended.clear()
	missed_run = 0
	missed_week = 0
	crimes_in_rank = 0
	leave_until = -1
	var p := Career.resolve_post(_settlements())
	var pp: Vector2 = p["pos"]
	post = {"id": p["id"], "name": p["name"], "kind": p["kind"], "pos": [pp.x, pp.y], "radius": p["radius"], "sid": p["sid"], "places": p["places"]}
	officer = Career.make_officer(hash([WorldSim.SEED, "cmd", day, String(p["id"])]))
	_release_other_posts()
	issue_kit(day)
	squad.clear()
	bump("enlistments")
	_say("You enlist at %s (%s) and report to %s %s." % [source.replace("_", " "), String(post["name"]), String(officer["title"]), String(officer["name"])])
	_sync_life(day, true)
	todays_duty(day)
	return {"ok": true, "reason": "", "text": "You are %s, posted to %s under %s %s." % [rank_title(), String(post["name"]), String(officer["title"]), String(officer["name"])]}


## The old Guard seat (careers.gd) pays by the day; one post at a time, so leave it.
func _release_other_posts() -> void:
	var cr: Variant = Life.get("careers") if sync_life and Life != null else null
	if cr is RefCounted and (cr as RefCounted).call("is_employed") and String((cr as RefCounted).get("player").get("org", "")) == "guard":
		(cr as RefCounted).call("resign")


## Issues what the current rank's kit lists and the soldier does not already have, through the equipment system.
## Returns the item ids issued this call.
func issue_kit(_day: int) -> Array:
	var want := Career.kit_for(rank)
	var issued: Array = []
	var life: Object = life_ref if life_ref != null else (Life if Life != null else null)
	for slot: String in want:
		var id := String(want[slot])
		if String(kit.get(slot, "")) == id:
			continue
		kit[slot] = id
		issued.append(id)
		if life != null:
			life.call("give", id, 1)
			var eq: Variant = life.get("equipment")
			if eq is Object:
				(eq as Object).call("equip_from", life, id, -1, true)    # issued kit: exempt from the gear level rule (equipment.gd)
	return issued


# ---------------------------------------------------------------- merit, promotion

func add_merit(n: float, why := "") -> void:
	merit += n
	if why != "":
		_say("%s%d merit (%s)." % ["+" if n >= 0.0 else "", int(n), why])


func promotion_status(day: int) -> Dictionary:
	return Career.promotion(rank, merit, days_in_rank(day))


func _promote_bookkeeping(day: int) -> void:
	since_day = day
	crimes_in_rank = 0
	issue_kit(day)
	squad.set_rank(rank, day, WorldSim.SEED)
	var b := _bio()
	if b != null:
		b.call("promote", CAREER, ladder_rank_id(), rank_title(), day, "soldier_post", String(post.get("name", "")))
	_sync_life(day, false)


## Promote when merit and service time allow. {ok, text (the ceremony line), missing}.
func petition(day: int) -> Dictionary:
	if not active:
		return {"ok": false, "text": "You hold no commission.", "missing": PackedStringArray()}
	if is_on_leave(day):
		return {"ok": false, "text": "You are on leave.", "missing": PackedStringArray()}
	var st := promotion_status(day)
	if not bool(st["eligible"]):
		return {"ok": false, "text": "%s %s says you are not ready." % [String(officer.get("title", "")), String(officer.get("name", "the officer"))], "missing": st["missing"]}
	rank += 1
	_promote_bookkeeping(day)
	_rep(1.5)
	var line := String(Career.rank_def(rank)["ceremony"])
	_say("Promoted to %s. %s" % [rank_title(), line])
	return {"ok": true, "text": line, "missing": PackedStringArray()}


func _demote(day: int, reason: String) -> String:
	if rank <= 0:
		return _discharge(day, "discipline", reason)
	var lost := rank_title()
	rank -= 1
	demotions += 1
	merit = float(Career.rank_def(rank)["merit"])
	_promote_bookkeeping(day)
	var text := "Reduced from %s to %s (%s)." % [lost, rank_title(), reason]
	_say(text)
	return text


# ---------------------------------------------------------------- discipline

## A crime by the soldier while enlisted: costs merit by severity; repeat offences or a ruined record demote.
## `sev` < 0 looks the kind up in Society.CRIMES. Returns {merit, demoted, discharged, text}.
func report_crime(kind: String, day: int, sev := -1) -> Dictionary:
	if not active:
		return {"merit": 0, "demoted": false, "discharged": false, "text": ""}
	if sev < 0:
		var soc := _mod("society")
		sev = int((soc.CRIMES.get(kind, {"sev": 1}) as Dictionary)["sev"]) if soc != null else 1
	var dc: Dictionary = Career.data()["discipline"]
	var cost := float(dc["crime_merit_per_severity"]) * float(sev)
	merit += cost
	crimes_in_rank += 1
	crimes_total += 1
	bump("crimes")
	_rep(-float(sev))
	var text := "%s: %d merit lost for %s." % [rank_title(), int(cost), kind.replace("_", " ")]
	_say(text)
	var res := {"merit": int(cost), "demoted": false, "discharged": false, "text": text}
	if sev >= int(dc["heinous_severity"]):
		res["discharged"] = true
		res["text"] = _discharge(day, "discipline", "a crime too grave for the colours")
		return res
	var floor_m := float(Career.rank_def(rank)["merit"]) * float(dc["demote_merit_floor_fraction"])
	var ruined := merit < floor_m and (rank > 0 or merit <= float(dc["demote_below_merit"]))
	if crimes_in_rank >= int(dc["demote_after_crimes"]) or ruined:
		var was_rank := rank
		res["text"] = _demote(day, "conduct")
		res["demoted"] = rank < was_rank or not active
		res["discharged"] = not active
	return res


## Looks over Society's crime record for new crimes the player was identified for since enlisting.
func scan_society(day: int) -> Array:
	var out: Array = []
	var soc := _mod("society")
	if soc == null or not active:
		return out
	for c: Dictionary in (soc.get("crimes") as Array):
		var cid := String(c.get("id", ""))
		if cid == "" or crimes_seen.has(cid):
			continue
		crimes_seen.append(cid)
		if crimes_seen.size() > 60:
			crimes_seen.pop_front()
		if int(c.get("day", 0)) >= enlisted_day and int(c.get("identified", 0)) > 0 and active:
			out.append(String(report_crime(String(c["kind"]), day)["text"]))
	return out


func _discharge(day: int, why: String, reason: String) -> String:
	var text := "You are struck off the rolls (%s)." % reason
	_end_service(day, why)
	_say(text)
	return text


## Leaving the colours honourably: no ban, no bounty.
func resign(day: int) -> String:
	if not active:
		return ""
	_end_service(day, "resigned")
	var text := "You hand back your commission. The captain nods once."
	_say(text)
	return text


func _end_service(day: int, why: String) -> void:
	active = false
	struck_off = why if why != "resigned" else ""
	banned_until = day + int(Career.data()["discipline"]["reenlist_ban_days"]) if why != "resigned" else -1
	merit = 0.0
	rank = 0
	abandon_duty(day, false)
	duty = {}
	squad.clear()
	leave_until = -1
	_sync_life(day, false)


## Desertion: struck off, a bounty left in Society, wages stop.
func _desert(day: int) -> String:
	var dc: Dictionary = Career.data()["discipline"]
	deserter = true
	var sid := int(post.get("sid", 0))
	var soc := _mod("society")
	if soc != null:
		var b: Dictionary = soc.get("bounties")
		b[str(sid)] = int(b.get(str(sid), 0)) + int(dc["desertion_bounty"])
	_rep(float(dc["desertion_rep"]))
	bump("desertions")
	_end_service(day, "desertion")
	var text := "You are struck off as a deserter. %d gold is on your head." % int(dc["desertion_bounty"])
	_say(text)
	return text


## Deserter's bounty still owed in the post's settlement.
func bounty_owed() -> int:
	var soc := _mod("society")
	return int(soc.call("bounty", int(post.get("sid", 0)))) if soc != null and not post.is_empty() else 0


# ---------------------------------------------------------------- muster

## Standing at the post inside the muster window counts as attendance. True when counted (once a day).
func muster_attend(day: int, hour: float, pos: Vector2) -> bool:
	if not active or is_on_leave(day) or attended.has(str(day)):
		return false
	if not Career.in_muster(hour) or not at_post(pos):
		return false
	attended[str(day)] = true
	bump("musters")
	missed_run = 0
	add_merit(float(Career.muster()["attend_merit"]))
	_gain(XP_MUSTER, day)
	_say("You answer muster.")
	# Keep the record short.
	if attended.size() > 14:
		var keys := attended.keys()
		keys.sort_custom(func(a: Variant, b: Variant) -> bool: return int(a) < int(b))
		attended.erase(keys[0])
	return true


func attended_on(day: int) -> bool:
	return attended.has(str(day))


## Settles a day's muster once the day is over: attended, on leave (excused) or missed.
## Returns "attended" | "leave" | "missed" | "desertion" | "".
func _settle_muster(day: int) -> String:
	if not active or day <= enlisted_day:
		return ""
	if leave_until >= day:
		return "leave"
	if attended.has(str(day)):
		return "attended"
	missed_run += 1
	missed_week += 1
	missed_total += 1
	bump("missed_musters")
	add_merit(float(Career.muster()["miss_merit"]))
	_say("You missed muster (%d in a row)." % missed_run)
	if missed_run >= int(Career.muster()["desert_after"]):
		return "desertion"
	return "missed"


func request_leave(day: int, days: int) -> Dictionary:
	var lc: Dictionary = Career.data()["leave"]
	if not active:
		return {"ok": false, "reason": "You hold no post."}
	if is_on_leave(day):
		return {"ok": false, "reason": "You are already on leave."}
	if day < leave_ready:
		return {"ok": false, "reason": "Leave was only just granted. Ask again on day %d." % leave_ready}
	if rank < int(lc["min_rank"]):
		return {"ok": false, "reason": "Recruits do not get leave."}
	if not duty.is_empty() and String(duty.get("state", "")) == "active":
		return {"ok": false, "reason": "Finish or give up your duty first."}
	var n := clampi(days, 1, int(lc["max_days"]))
	leave_until = day + n
	leave_ready = leave_until + int(lc["cooldown_days"])
	bump("leaves")
	_say("%s %s grants you %d days leave." % [String(officer.get("title", "")), String(officer.get("name", "")), n])
	return {"ok": true, "reason": "", "days": n, "until": leave_until}


# ---------------------------------------------------------------- duties (library quests)

func runner() -> QuestRunner:
	if _runner == null:
		_runner = QuestRunner.new(bus_ref if bus_ref != null else QuestBus.shared())
		_runner.awards_xp = false          # duties are job shifts (above), not unique quests
		_runner.reward_fn = _reward
		_runner.clock_fn = func() -> float: return float(_day)
		_runner.quest_event.connect(_on_quest_event)
		_runner.bus.fired.connect(_on_bus)
	return _runner


## Detach from the bus (tests and a new game).
func release() -> void:
	if _runner != null:
		_runner.unbind()
		if _runner.bus != null and _runner.bus.fired.is_connected(_on_bus):
			_runner.bus.fired.disconnect(_on_bus)
	_runner = null


func _reward(r: Dictionary) -> String:
	var m := float(r.get("merit", 0))
	var g := int(r.get("gold", 0))
	if m != 0.0:
		merit += m
	if g > 0:
		pending_gold += g
	var parts := PackedStringArray()
	if m != 0.0:
		parts.append("%+d merit" % int(m))
	if g > 0:
		parts.append("%dg" % g)
	return ", ".join(parts)


## Generates (once) and returns today's duty offer. {} when not serving, on leave, or already off duty.
func todays_duty(day: int) -> Dictionary:
	if not active or is_on_leave(day):
		return {}
	if not duty.is_empty() and int(duty.get("day", -1)) == day:
		return duty
	return offer_duty(day, "")


## Builds a duty of `kind` ("" = weighted pick for the rank) as today's offer, replacing an unstarted one.
func offer_duty(day: int, kind: String) -> Dictionary:
	if not active:
		return {}
	if not duty.is_empty() and String(duty.get("state", "")) == "active":
		return duty
	var r := _rng("duty", day, rank)
	var k := kind if kind != "" else Career.pick_kind(r, rank)
	var d := Career.gen_duty(k, day, {"id": post.get("id", ""), "name": post.get("name", ""), "pos": post_pos(), "places": post.get("places", {})}, r)
	if d.is_empty():
		return {}
	d["state"] = "offered"
	d["kills"] = 0
	d["casualties"] = 0
	duty = d
	return duty


## Take today's duty: starts its quest in the runner. {ok, reason}.
func accept_duty(day: int) -> Dictionary:
	var d := todays_duty(day)
	if d.is_empty():
		return {"ok": false, "reason": "No duty is posted today."}
	if String(d["state"]) != "offered":
		return {"ok": false, "reason": "You have already taken this duty." if String(d["state"]) == "active" else "Today's duty is finished."}
	var run := runner()
	if run.def(String(d["id"])) == null:
		run.add_def(QuestDef.from_dict(d["def"] as Dictionary))
	var why := run.start(String(d["id"]))
	if why != "":
		return {"ok": false, "reason": why}
	d["state"] = "active"
	_say("Duty: %s." % String(d["text"]))
	return {"ok": true, "reason": ""}


func abandon_duty(day: int, penalty := true) -> void:
	if duty.is_empty() or String(duty.get("state", "")) != "active":
		return
	if _runner != null:
		_runner.abandon(String(duty["id"]))
	duty["state"] = "failed"
	duty_log.append({"day": day, "kind": String(duty["kind"]), "text": String(duty["text"]), "result": "abandoned"})
	if penalty:
		merit += float(Career.data()["merit"]["duty_abandoned"])
		bump("duties_abandoned")


## Current objective lines of an active duty: [{text, progress, done}].
func duty_lines() -> Array:
	var out: Array = []
	if duty.is_empty() or _runner == null or String(duty.get("state", "")) != "active":
		return out
	for o: RefCounted in _runner.objectives_of(String(duty["id"])):
		out.append({"text": o.describe(), "progress": o.progress(), "done": o.is_done()})
	return out


func _on_quest_event(e: Dictionary) -> void:
	if duty.is_empty() or String(e.get("quest", "")) != String(duty.get("id", "")):
		return
	var t := String(e.get("type", ""))
	if t == "completed":
		_duty_done()
	elif t == "failed":
		duty["state"] = "failed"
		bump("duties_failed")
		duty_log.append({"day": _day, "kind": String(duty["kind"]), "text": String(duty["text"]), "result": "failed"})
		_say("Duty failed: %s." % String(duty["text"]))


func _duty_done() -> void:
	var day := int(duty.get("day", _day))
	duty["state"] = "done"
	bump("duties")
	bump(String(duty["kind"]))
	if String(duty["kind"]) == "patrol":
		bump("patrols")
	_gain(XP_DUTY, day)
	_rep(0.5)
	# Progression hook (docs/balance/PROGRESSION_R1.md section 5): a finished duty is a work shift of the soldier's trade.
	if sync_life and Life != null and Life.has_method("award_progress"):
		Life.award_progress("job_shift", {"subject": "soldier_" + String(duty["kind"])})
		if Life.get("soul") != null:
			(Life.soul as RefCounted).call("gain", "combat", SOUL_PER_DUTY, day)       # a duty is drilled, disciplined work for the soul too
	var res := "done"
	# A clean duty (nobody in the squad hurt) may earn a commendation.
	if int(duty.get("casualties", 0)) == 0 and _rng("commend", day, duty["id"]).randf() < float(Career.data()["merit"]["commendation_chance_clean"]):
		commend(day, "a duty well done")
		res = "commended"
	duty_log.append({"day": day, "kind": String(duty["kind"]), "text": String(duty["text"]), "result": res})
	if duty_log.size() > 12:
		duty_log.pop_front()
	_say("Duty done: %s." % String(duty["text"]))


## A commendation from the officer: merit and a line in the log.
func commend(day: int, why: String) -> void:
	bump("commendations")
	add_merit(float(Career.data()["merit"]["commendation"]), "commendation: " + why)
	_rep(1.0)
	_gain(XP_DUTY * 0.5, day)


func _on_bus(type: StringName, ev: Dictionary) -> void:
	if String(type) != "kill" or not active or duty.is_empty() or String(duty.get("state", "")) != "active":
		return
	var n := int(ev.get("amount", 1))
	var cap := int(Career.data()["merit"]["kill_cap_per_duty"])
	var have := int(duty.get("kills", 0))
	var credit := clampi(n, 0, maxi(0, cap - have))
	duty["kills"] = have + n
	bump("kills", n)
	if credit > 0:
		merit += float(Career.data()["merit"]["kill"]) * float(credit)


# ---------------------------------------------------------------- squad

## A blow on squad member `i` (the body calls this). Returns the member's state afterwards.
func squad_damage(i: int, amount: int, day: int) -> String:
	var st := squad.damage(i, amount, day)
	if st == "wounded" or st == "dead":
		if not duty.is_empty() and String(duty.get("state", "")) == "active":
			duty["casualties"] = int(duty.get("casualties", 0)) + 1
		var nm := String(squad.member(i).get("name", "A soldier"))
		_say("%s is %s." % [nm, "killed" if st == "dead" else "wounded"])
		if st == "dead":
			bump("squad_lost")
	return st


func squad_credit_kill(i: int) -> void:
	squad.credit_kill(i)


func has_squad() -> bool:
	return active and Career.squad_size(rank) > 0


# ---------------------------------------------------------------- life and ladder sync

func _sync_life(day: int, new_career: bool) -> void:
	if not sync_life or Life == null or Life.get("career_id") == null:
		return
	if active:
		if String(Life.career_id) != CAREER or new_career:
			Life.career_id = CAREER
			Life.career_rank = ladder_rank_id()
			Life.career_since_day = since_day
			var b := _bio()
			if b != null:
				b.call("start_chapter", CAREER, "soldier_post", ladder_rank_id(), String(post.get("name", "")), day)
		else:
			Life.career_rank = ladder_rank_id()
			Life.career_since_day = since_day
	elif String(Life.career_id) == CAREER:
		Life.career_id = ""
		Life.career_rank = ""


func career_stats() -> Dictionary:
	return stats.duplicate()


## Everything the career screen shows, as plain data.
func status_view(day: int) -> Dictionary:
	var st := promotion_status(day)
	var wk := Career.pay_for_week(rank, missed_week, is_on_leave(day), deserter) if active else 0
	return {"active": active, "rank": rank_title(), "rank_idx": rank, "merit": int(merit), "post": String(post.get("name", "")),
		"officer": "%s %s" % [String(officer.get("title", "")), String(officer.get("name", ""))] if not officer.is_empty() else "",
		"next": st["next"], "next_lines": st["lines"], "ready": bool(st["eligible"]), "wage": weekly_wage(), "wage_this_week": wk,
		"missed_week": missed_week, "missed_run": missed_run, "desert_after": int(Career.muster()["desert_after"]),
		"on_leave": is_on_leave(day), "leave_until": leave_until, "deserter": deserter, "struck_off": struck_off, "banned_until": banned_until,
		"duty": {} if duty.is_empty() else {"text": String(duty["text"]), "state": String(duty["state"]), "kind": String(duty["kind"]),
			"merit": int(duty["merit"]), "gold": int(duty["gold"]), "lines": duty_lines()},
		"squad": squad_view(), "squad_size": squad.size(), "attended_today": attended_on(day)}


func squad_view() -> Array:
	var out: Array = []
	for m: Dictionary in squad.members:
		out.append({"name": String(m["name"]), "state": String(m["state"]), "hp": int(m["hp"]), "max_hp": int(m["max_hp"]), "kills": int(m["kills"])})
	return out


# ---------------------------------------------------------------- ticks

func tick_hour(hour: int, ctx: Dictionary) -> Array:
	if not active:
		return []
	var day := int(WorldSim.day) if WorldSim != null else _day
	if ctx.has("player_pos") and Career.in_muster(float(hour)):
		muster_attend(day, float(hour), ctx["player_pos"])
	return []


func tick_day(day: int, _ctx: Dictionary) -> Array:
	_day = day
	var out: Array = []
	if not active:
		return out
	# Yesterday's muster is settled now.
	var m := _settle_muster(day - 1)
	if m == "desertion":
		out.append(_desert(day))
		return out
	if leave_until >= 0 and leave_until < day:
		leave_until = -1
		out.append("Your leave is over. Report for muster.")
	# An unfinished duty from an earlier day lapses.
	if not duty.is_empty() and int(duty.get("day", day)) < day:
		if String(duty.get("state", "")) == "active":
			abandon_duty(day)
			out.append("The duty went unfinished and is struck from the roll.")
		duty = {}
	out.append_array(scan_society(day))
	if not active:
		return out
	out.append_array(squad.tick_day(day, WorldSim.SEED))
	var pr := petition(day)
	if bool(pr["ok"]):
		out.append(String(pr["text"]))
	if not is_on_leave(day):
		todays_duty(day)
	return out


## Weekly pay through the wage ledger: docked for missed musters, half on leave, nothing for a deserter.
func tick_week(week: int, _ctx: Dictionary) -> Array:
	var out: Array = []
	var day := week * 7
	if active:
		var pay := Career.pay_for_week(rank, missed_week, is_on_leave(day), false)
		pending_gold += pay
		var full := Career.weekly_wage(rank)
		if pay < full:
			out.append("Pay day: %d of %d gold (docked for missed muster or leave)." % [pay, full])
		else:
			out.append("Pay day: %d gold." % pay)
		bump("weeks_paid")
	missed_week = 0
	return out


## Statistical sleep: time away from the post counts as missed musters beyond one night's grace.
func catch_up(days: int, _ctx: Dictionary) -> Array:
	var out: Array = []
	if days <= 0:
		return out
	_day += days
	if not active:
		return out
	var grace := int(Career.muster()["catchup_grace_days"])
	var away := maxi(0, days - grace)
	if leave_until >= 0:
		var excused := clampi(leave_until - (_day - days), 0, away)
		away -= excused
		if leave_until < _day:
			leave_until = -1
	if away > 0:
		missed_run += away
		missed_week += mini(away, 7)
		missed_total += away
		bump("missed_musters", away)
		merit += float(Career.muster()["miss_merit"]) * float(away)
		if missed_run >= int(Career.muster()["desert_after"]):
			out.append(_desert(_day))
			return out
	var weeks := days / 7
	if weeks > 0:
		pending_gold += Career.pay_for_week(rank, 0, false, false) * weeks
	return out


# ---------------------------------------------------------------- save

func serialize() -> Dictionary:
	return {"pending_gold": pending_gold, "active": active, "rank": rank, "since_day": since_day, "enlisted_day": enlisted_day, "merit": merit,
		"post": post.duplicate(true), "officer": officer.duplicate(true), "attended": attended.duplicate(), "missed_run": missed_run,
		"missed_week": missed_week, "missed_total": missed_total, "leave_until": leave_until, "leave_ready": leave_ready,
		"deserter": deserter, "struck_off": struck_off, "banned_until": banned_until, "crimes_in_rank": crimes_in_rank,
		"crimes_total": crimes_total, "demotions": demotions, "crimes_seen": crimes_seen.duplicate(), "kit": kit.duplicate(),
		"stats": stats.duplicate(), "duty": duty.duplicate(true), "duty_log": duty_log.duplicate(true), "squad": squad.serialize(),
		"runner": _runner.serialize() if _runner != null else {}, "log": log_lines.duplicate(), "day": _day}


func deserialize(d: Dictionary) -> void:
	pending_gold = int(d.get("pending_gold", 0))
	active = bool(d.get("active", false))
	rank = int(d.get("rank", 0))
	since_day = int(d.get("since_day", 0))
	enlisted_day = int(d.get("enlisted_day", 0))
	merit = float(d.get("merit", 0.0))
	post = (d.get("post", {}) as Dictionary).duplicate(true)
	if post.has("sid"):
		post["sid"] = int(post["sid"])
	officer = (d.get("officer", {}) as Dictionary).duplicate(true)
	attended = (d.get("attended", {}) as Dictionary).duplicate()
	missed_run = int(d.get("missed_run", 0))
	missed_week = int(d.get("missed_week", 0))
	missed_total = int(d.get("missed_total", 0))
	leave_until = int(d.get("leave_until", -1))
	leave_ready = int(d.get("leave_ready", 0))
	deserter = bool(d.get("deserter", false))
	struck_off = String(d.get("struck_off", ""))
	banned_until = int(d.get("banned_until", -1))
	crimes_in_rank = int(d.get("crimes_in_rank", 0))
	crimes_total = int(d.get("crimes_total", 0))
	demotions = int(d.get("demotions", 0))
	crimes_seen = (d.get("crimes_seen", []) as Array).duplicate()
	kit = (d.get("kit", {}) as Dictionary).duplicate()
	stats = {}
	for k: String in (d.get("stats", {}) as Dictionary):
		stats[k] = int(d["stats"][k])
	duty = (d.get("duty", {}) as Dictionary).duplicate(true)
	for k2: String in ["day", "kills", "casualties", "merit", "gold"]:
		if duty.has(k2):
			duty[k2] = int(duty[k2])
	duty_log = (d.get("duty_log", []) as Array).duplicate(true)
	squad.deserialize(d.get("squad", {}))
	log_lines = (d.get("log", []) as Array).duplicate()
	_day = int(d.get("day", 0))
	# The duty's quest comes back with its definition (the runner saves progress, the duty keeps the def).
	var rs: Dictionary = d.get("runner", {})
	if not rs.is_empty():
		var run := runner()
		if not duty.is_empty() and run.def(String(duty.get("id", ""))) == null:
			run.add_def(QuestDef.from_dict(duty["def"] as Dictionary))
		run.deserialize(rs)
