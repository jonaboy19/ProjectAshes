extends "res://scripts/realm/realm_module.gd"
## Job work mechanics (docs/design/LIVING_WORLD.md L§7-11, L§49; ACADEMY_PLAN "Everyone learns
## to fight"). city_life decides WHO has a job and what it pays; this module decides what a shift
## FEELS like: a short sequence of tasks at real spots in the workplace, each a tiny mobile
## interaction (tap timing / hold-and-release / choice) that yields a quality 0..1.
##
## Flow (all pure data, deterministic from hash([WorldSim.SEED, tag, day, ...]), JSON-safe):
##   begin(job, sid, day, season, hour) -> shift            one shift per job per day
##   current_task() -> task + spot + zone width              what to walk to and do next
##   resolve_task(quality | choice_idx) -> {quality, problem?, hours, comment?, done}
##   pending_problem() / resolve_problem(option)             normal-speed beats between tasks
##   finish(ctx) -> {quality, gold, mastery, comment, ...}   wage, mastery, reputation, hooks
## Routine tasks return `hours` (the presenter runs the clock faster over them); problems and the
## open decision return 0 so the game stays at normal speed.
##
## Effects: mastery.gain(discipline) per task; wages through city_life.work_shift(quality) when the
## player's employed job matches, careers attendance/tips for the seat orgs (guard, smithy, inn,
## woodcutters), tips for freelance "odd work"; employer standing; society city reputation;
## problems can raise a call-up (callups.raise_offer) or a story hook (society.log_failure).
## Money rule: never touches the purse, the presenter calls take_pending_gold().

const Jobs := preload("res://scripts/realm/work_jobs.gd")
const RAMastery := preload("res://scripts/sim/mastery.gd")

const XP_PER_TASK := 0.25
const PROBLEM_BASE := 0.16
const PROBLEM_MAX_PER_SHIFT := 2
const WORK_RADIUS := 15.0
const SPOT_REACH := 3.4
const STANDING_START := 50.0
const LOG_MAX := 20

## city_life job template -> work job id (job jobs outside the list are not shift-modelled).
const TPL_TO_WORK := {
	"smith": "blacksmith", "smith_apprentice": "blacksmith", "stall_hand": "merchant", "clerk": "scribe", "scribe": "scribe",
	"caravan_guard": "guard", "city_guard": "guard", "dockhand": "laborer", "day_labour": "laborer", "harvest_hand": "farmer",
	"servant": "innkeeper", "acolyte": "healer",
}
## careers.gd org id -> work job id.
const ORG_TO_WORK := {"guard": "guard", "smithy": "blacksmith", "inn": "innkeeper", "woodcutters": "woodcutter"}
const FIRST := ["Aldric", "Brenna", "Corin", "Dessa", "Edmar", "Fenna", "Gorm", "Hilda", "Ivo", "Jorun", "Kessa", "Lorn", "Mira", "Nils", "Orla", "Pell", "Quin", "Rhea", "Sten", "Tova"]
const LAST := ["Ashby", "Brook", "Crane", "Dunn", "Ember", "Fallow", "Gray", "Hale", "Ironside", "Marsh", "Nettle", "Oakes", "Pike", "Reed", "Stone", "Thorne"]

var mastery_ref: RefCounted = null     # tests inject one; otherwise Life.mastery
var pending_gold: int = 0
var shift: Dictionary = {}             # the running shift ({} when off duty)
var standing: Dictionary = {}          # employer -> 0..100 regard for the player's work
var last_done: Dictionary = {}         # job -> day of the last finished shift
var stats: Dictionary = {}             # job -> {shifts, total_q, best}
var log_lines: Array = []              # recent text ("The smith nods.")
var orders_done: Dictionary = {}       # order id -> true
var _day := 0
var _layout_cache: Dictionary = {}     # sid -> Array of workplaces (rebuilt from the seed)


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
	return Life.mastery


func _sname(sid: int) -> String:
	if sid >= 0 and sid < WorldGen.settlements.size():
		return String(WorldGen.settlements[sid]["name"])
	return "the road"


func _say(text: String) -> void:
	log_lines.append(text)
	if log_lines.size() > LOG_MAX:
		log_lines.pop_front()


func take_pending_gold() -> int:
	var g := pending_gold
	pending_gold = 0
	return g


# ---------------------------------------------------------------- static data / minigame maths

func job_ids() -> Array:
	var out: Array = []
	for k: String in Jobs.data():
		out.append(k)
	return out


func job_def(job: String) -> Dictionary:
	return Jobs.data().get(job, {})


## Task ids of a shift for `season` (farmers work by season; everyone else has a fixed round).
func task_ids(job: String, season: String) -> Array:
	var jd := job_def(job)
	if jd.is_empty():
		return []
	var bs: Dictionary = jd["by_season"]
	if not bs.is_empty():
		return (bs.get(season, bs.get("spring", [])) as Array).duplicate()
	return (jd["seq"] as Array).duplicate()


## Width of the good zone (0..1 of the bar): harder tasks are tighter, mastery widens it.
static func zone_width(diff: float, level: int) -> float:
	return clampf(0.34 - 0.22 * diff + float(level - 1) * 0.0025, 0.08, 0.42)


## Tap timing: marker `pos` vs zone centre `target`, both 0..1. Inside the zone is >= 0.6, dead
## centre 1.0, far outside 0.
static func timing_quality(pos: float, target: float, width: float) -> float:
	var off := absf(pos - target)
	var half := width * 0.5
	if off <= half:
		return lerpf(1.0, 0.6, off / maxf(half, 0.001))
	return clampf(0.6 - (off - half) / maxf(width, 0.05) * 0.6, 0.0, 0.6)


## Hold and release: the same scoring on the fill level.
static func hold_quality(fill: float, target: float, width: float) -> float:
	return timing_quality(fill, target, width)


func mastery_level(job: String) -> int:
	var m := _mastery()
	var jd := job_def(job)
	if m == null or jd.is_empty():
		return 1
	return int(m.call("level", String(jd["discipline"])))


# ---------------------------------------------------------------- who is the player working as

## {job, employed, employer, sid, via ("city_life"|"careers"|"")} for the player's current work.
func player_work() -> Dictionary:
	var out := {"job": "", "employed": false, "employer": "", "sid": -1, "via": ""}
	var cl := _mod("city_life")
	if cl != null and cl.has_method("job"):
		var j: Dictionary = cl.call("job")
		if not j.is_empty():
			var w := String(TPL_TO_WORK.get(String(j.get("tpl", "")), ""))
			if w != "":
				return {"job": w, "employed": true, "employer": String(j["employer"]), "sid": int(j["sid"]), "via": "city_life"}
	if Life != null:
		var cr: Variant = Life.careers
		if cr is RefCounted and (cr as RefCounted).call("is_employed"):
			var o: Dictionary = (cr as RefCounted).call("player_org")
			var w2 := String(ORG_TO_WORK.get(String(o.get("id", "")), ""))
			if w2 != "":
				return {"job": w2, "employed": true, "employer": String(o.get("recruiter", o.get("name", ""))), "sid": int(o.get("settlement", 0)), "via": "careers"}
	return out


# ---------------------------------------------------------------- workplaces (layout)

## The workplaces of a settlement: one per job, deterministic. Each has a centre, a radius and its
## spots (kind, label, position). In-town trades sit on two rings; outdoor trades outside the walls.
func workplaces(sid: int) -> Array:
	if _layout_cache.has(sid):
		return _layout_cache[sid]
	var out: Array = []
	if sid < 0 or sid >= WorldGen.settlements.size():
		return out
	var st: Dictionary = WorldGen.settlements[sid]
	var c: Vector2 = st["pos"]
	var rad := float(st.get("radius", 60.0))
	var town: Array = []
	var edge: Array = []
	for j: String in job_ids():
		(edge if bool(job_def(j)["edge"]) else town).append(j)
	var r0 := _rng("worklayout", 0, sid)
	var ang0 := r0.randf() * TAU
	for i in town.size():
		var ring := 0.34 if i % 2 == 0 else 0.68
		var a := ang0 + TAU * float(i) / float(town.size()) * 1.0
		out.append(_make_place(String(town[i]), sid, c + Vector2.from_angle(a) * rad * ring))
	for i in edge.size():
		var a2 := ang0 + PI * 0.3 + TAU * float(i) / float(edge.size())
		out.append(_make_place(String(edge[i]), sid, c + Vector2.from_angle(a2) * rad * 1.3))
	_layout_cache[sid] = out
	return out


func _make_place(job: String, sid: int, center: Vector2) -> Dictionary:
	var jd := job_def(job)
	var r := _rng("workspots", 0, "%d:%s" % [sid, job])
	var spots: Array = []
	var specs: Array = jd["spots"]
	var a0 := r.randf() * TAU
	for i in specs.size():
		var sp: Dictionary = specs[i]
		var a := a0 + TAU * float(i) / float(specs.size())
		var dist := minf(float(sp["r"]) + 1.5 + r.randf() * 1.5, WORK_RADIUS - 2.0)
		spots.append({"kind": String(sp["kind"]), "label": String(sp["label"]), "pos": center + Vector2.from_angle(a) * dist})
	return {"id": "%d:%s" % [sid, job], "job": job, "sid": sid, "title": "%s work" % String(jd["title"]), "center": center, "radius": WORK_RADIUS, "spots": spots}


func workplace_at(p: Vector2, sid: int) -> Dictionary:
	for w: Dictionary in workplaces(sid):
		if p.distance_to(w["center"]) <= float(w["radius"]):
			return w
	return {}


func spot_pos(place: Dictionary, kind: String) -> Vector2:
	for s: Dictionary in place.get("spots", []):
		if String(s["kind"]) == kind:
			return s["pos"]
	return place.get("center", Vector2.ZERO)


# ---------------------------------------------------------------- starting a shift

func on_shift() -> bool:
	return not shift.is_empty()


## Why the player cannot begin `job` now, or "".
func start_refusal(job: String, hour: float, day: int) -> String:
	var jd := job_def(job)
	if jd.is_empty():
		return "There is no such work."
	if on_shift():
		return "You are already in the middle of a shift."
	if int(last_done.get(job, -99)) == day:
		return "You have done your work here today."
	var sh: Array = jd["shift"]
	if hour < float(sh[0]) or hour >= float(sh[1]):
		return "Work here runs %d:00 to %d:00." % [int(sh[0]), int(sh[1])]
	return ""


func begin(job: String, sid: int, day: int, season: String, hour: float) -> Dictionary:
	var why := start_refusal(job, hour, day)
	if why != "":
		return {"ok": false, "reason": why}
	var pw := player_work()
	var employed := bool(pw["employed"]) and String(pw["job"]) == job
	var employer := String(pw["employer"]) if employed else ""
	shift = {"job": job, "sid": sid, "day": day, "season": season, "seq": task_ids(job, season), "step": 0, "results": [],
		"hours": 0.0, "problems": 0, "employed": employed, "employer": employer, "via": String(pw["via"]) if employed else "",
		"pending": {}, "events": []}
	_day = day
	return {"ok": true, "reason": "", "shift": shift.duplicate(true)}


func abandon() -> Dictionary:
	if shift.is_empty():
		return {"ok": false}
	# Walking off mid-shift counts the remaining tasks as failed.
	while int(shift["step"]) < (shift["seq"] as Array).size():
		shift["results"].append({"task": (shift["seq"] as Array)[int(shift["step"])], "q": 0.0})
		shift["step"] = int(shift["step"]) + 1
	return finish({"abandoned": true})


# ---------------------------------------------------------------- tasks

func task_def(job: String, id: String) -> Dictionary:
	return (job_def(job).get("tasks", {}) as Dictionary).get(id, {})


## The next task to do, with zone width and the spot label, or {} when the round is complete.
func current_task() -> Dictionary:
	if shift.is_empty() or not shift["pending"].is_empty():
		return {}
	var seq: Array = shift["seq"]
	var i := int(shift["step"])
	if i >= seq.size():
		return {}
	var t: Dictionary = task_def(String(shift["job"]), String(seq[i])).duplicate(true)
	t["step"] = i
	t["of"] = seq.size()
	t["zone"] = zone_width(float(t["diff"]), mastery_level(String(shift["job"])))
	t["zone_at"] = 0.3 + _rng("zoneat", int(shift["day"]), "%s%d" % [shift["job"], i]).randf() * 0.5
	if String(t["widget"]) == "hold":
		t["zone_at"] = 0.55 + float(t["zone_at"] - 0.3) * 0.6
	return t


func pending_problem() -> Dictionary:
	return {} if shift.is_empty() else (shift["pending"] as Dictionary).duplicate(true)


## Finish the current task. Timing/hold tasks pass `quality`; choice tasks pass `choice` (the
## option's own q is used). Returns {ok, task, quality, hours, tip, problem (or {}), comment, done}.
func resolve_task(quality: float, choice := -1) -> Dictionary:
	var t := current_task()
	if t.is_empty():
		return {"ok": false, "reason": "No task is waiting."}
	var job := String(shift["job"])
	var q := clampf(quality, 0.0, 1.0)
	var tip := 0
	var regard := 0.0
	if String(t["widget"]) == "choice":
		var opts: Array = t["options"]
		var o: Dictionary = opts[clampi(choice, 0, opts.size() - 1)]
		q = float(o["q"])
		tip = int(o.get("tip", 0))
		regard = float(o.get("regard", 0.0))
	(shift["results"] as Array).append({"task": String(t["id"]), "q": q})
	shift["step"] = int(shift["step"]) + 1
	shift["hours"] = float(shift["hours"]) + float(t["hours"])
	_apply_tip(tip)
	_apply_regard(regard, int(shift["sid"]))
	_gain(job, XP_PER_TASK * (0.4 + 0.6 * q))
	var res := {"ok": true, "task": String(t["id"]), "label": String(t["label"]), "quality": q, "hours": float(t["hours"]), "tip": tip,
		"problem": {}, "comment": "", "done": false}
	# A non-routine beat may interrupt the round.
	var p := _roll_problem(job, int(shift["step"]) - 1, q)
	if not p.is_empty():
		shift["pending"] = p
		shift["problems"] = int(shift["problems"]) + 1
		res["problem"] = p.duplicate(true)
		res["hours"] = 0.0     # problems run at normal speed
	res["done"] = int(shift["step"]) >= (shift["seq"] as Array).size() and p.is_empty()
	return res


func _gain(job: String, amount: float) -> void:
	var m := _mastery()
	if m != null and amount > 0.0:
		m.call("gain", String(job_def(job)["discipline"]), amount, int(shift.get("day", _day)))


func _apply_tip(tip: int) -> void:
	pending_gold += tip


func _apply_regard(delta: float, sid: int) -> void:
	if absf(delta) < 0.001:
		return
	var soc := _mod("society")
	if soc != null and soc.has_method("add_rep"):
		soc.call("add_rep", "city:%d" % sid, delta, "work")


func _roll_problem(job: String, step: int, q: float) -> Dictionary:
	if int(shift["problems"]) >= PROBLEM_MAX_PER_SHIFT:
		return {}
	var r := _rng("wprob", int(shift["day"]), "%s%d%d" % [job, int(shift["sid"]), step])
	var chance := PROBLEM_BASE + 0.22 * (1.0 - q)
	if r.randf() >= chance:
		return {}
	var probs: Array = job_def(job)["problems"]
	var tot := 0.0
	for p: Dictionary in probs:
		if not _has_event(String(p["id"])):
			tot += float(p["weight"])
	if tot <= 0.0:
		return {}
	var roll := r.randf() * tot
	for p: Dictionary in probs:
		if _has_event(String(p["id"])):
			continue
		roll -= float(p["weight"])
		if roll <= 0.0:
			return p.duplicate(true)
	return {}


func _has_event(pid: String) -> bool:
	return pid in (shift["events"] as Array)


## Choose how to handle the open problem. Returns {ok, quality, callup (offer or {}), story, text}.
func resolve_problem(option: int) -> Dictionary:
	if shift.is_empty() or (shift["pending"] as Dictionary).is_empty():
		return {"ok": false, "reason": "Nothing needs deciding."}
	var p: Dictionary = shift["pending"]
	var opts: Array = p["options"]
	var o: Dictionary = opts[clampi(option, 0, opts.size() - 1)]
	var q := float(o["q"])
	var sid := int(shift["sid"])
	var day := int(shift["day"])
	(shift["results"] as Array).append({"task": "problem:%s" % String(p["id"]), "q": q})
	(shift["events"] as Array).append(String(p["id"]))
	_apply_tip(int(o.get("tip", 0)))
	_apply_regard(float(o.get("regard", 0.0)), sid)
	_gain(String(shift["job"]), XP_PER_TASK * 0.5 * (0.4 + 0.6 * q))
	var out := {"ok": true, "quality": q, "callup": {}, "story": "", "text": "", "problem": String(p["id"]), "injured": 0}
	if int(o.get("injure", 0)) > 0:
		var cl := _mod("city_life")
		if cl != null and cl.has_method("injure"):
			cl.call("injure", int(o["injure"]))
		out["injured"] = int(o["injure"])
	# Trouble that grows out of the work: an explicit follow-up, or the problem's default when it went badly.
	var tid := String(o.get("callup", ""))
	if tid == "" and q < 0.4:
		tid = String(p.get("callup", ""))
	if tid != "":
		var cu := _mod("callups")
		if cu != null and cu.has_method("raise_offer"):
			out["callup"] = cu.call("raise_offer", tid, day, sid, String(shift["employer"]))
	var story := String(o.get("story", ""))
	if story == "" and q < 0.3:
		story = String(p.get("story", ""))
	if story != "":
		var soc := _mod("society")
		if soc != null and soc.has_method("log_failure"):
			soc.call("log_failure", story, _story_text(story, String(shift["job"]), sid), sid)
		out["story"] = story
	shift["pending"] = {}
	out["text"] = "%s: %s" % [String(p["id"]).replace("_", " ").capitalize(), String(o["text"])]
	out["done"] = int(shift["step"]) >= (shift["seq"] as Array).size()
	return out


func _story_text(kind: String, job: String, sid: int) -> String:
	var place := _sname(sid)
	var lines := {
		"farm_blight": "The sickness in %s's flocks was not stopped in time; neighbours are looking at you." % place,
		"shoddy_work": "A piece of work you passed in %s failed; people there will not forget the name on it." % place,
		"stall_theft": "A boy stole from the stall in %s, and hunger might have a name." % place,
		"guard_lapse": "You left your post while a purse was cut in %s." % place,
		"guard_bribed": "You looked away for coin in %s. Someone remembers your face." % place,
		"coward_labour": "You ran when the trench fell in %s; men were dug out without you." % place,
		"timber_theft": "Timber walked out of the yard in %s while you watched." % place,
		"mine_collapse": "You kept digging when the props groaned in %s." % place,
		"bad_goods": "Spoiled goods you sold in %s made someone ill." % place,
		"bakery_fire": "The bakery fire in %s started on your watch." % place,
		"plague_unchecked": "You waved away the rash in %s. It has not stopped there." % place,
		"forged_deed": "A forged deed passed through your hands in %s." % place,
		"leaked_letter": "You sold a lord's letter's secrets in %s." % place,
		"tavern_wreck": "You hid while the tavern in %s was wrecked." % place,
		"sick_animal": "A mare in %s went lame because nobody heeded the signs." % place,
	}
	return String(lines.get(kind, "Something went wrong at work in %s (%s)." % [place, job]))


# ---------------------------------------------------------------- end of shift

## Average quality over everything done this shift (0 with nothing done).
func shift_quality() -> float:
	if shift.is_empty() or (shift["results"] as Array).is_empty():
		return 0.0
	var tot := 0.0
	for r: Dictionary in shift["results"]:
		tot += float(r["q"])
	return tot / float((shift["results"] as Array).size())


func _is_done() -> bool:
	return not shift.is_empty() and int(shift["step"]) >= (shift["seq"] as Array).size() and (shift["pending"] as Dictionary).is_empty()


## Close the shift and pay: city_life.work_shift for matching employment, seat orgs get attendance
## and a quality tip, freelance work pays tips only. ctx: {careers, attendance_auto, abandoned}.
func finish(ctx := {}) -> Dictionary:
	if shift.is_empty():
		return {"ok": false, "reason": "You are not on a shift."}
	var job := String(shift["job"])
	var jd := job_def(job)
	var sid := int(shift["sid"])
	var day := int(shift["day"])
	var q := shift_quality()
	var done := _is_done()
	var res := {"ok": true, "job": job, "quality": q, "hours": float(shift["hours"]), "gold": 0, "wage_via": "", "comment": "", "order": {},
		"promoted": false, "tasks": (shift["results"] as Array).size(), "problems": int(shift["problems"]), "employer": String(shift["employer"])}
	var wage_gold := 0
	if bool(shift["employed"]) and String(shift["via"]) == "city_life":
		var cl := _mod("city_life")
		var ws: Dictionary = cl.call("work_shift", q) if cl != null and cl.has_method("work_shift") else {"ok": false}
		res["wage_via"] = "city_life"
		if bool(ws.get("ok", false)):
			if q >= 0.75 and cl.has_method("accomplish"):
				cl.call("accomplish", "shift", q)
			elif q < 0.3 and cl.has_method("accomplish"):
				cl.call("accomplish", "botched", -0.5)
		else:
			res["wage_via"] = "refused"
			res["reason"] = String(ws.get("reason", ""))
	elif bool(shift["employed"]) and String(shift["via"]) == "careers":
		var cr: Variant = ctx.get("careers")
		res["wage_via"] = "careers"
		if cr is RefCounted:
			if not bool(ctx.get("attendance_auto", false)):
				(cr as RefCounted).call("log_attendance", float(shift["hours"]))
			var seat: Dictionary = (cr as RefCounted).call("player_seat")
			wage_gold = int(round(float(seat.get("wage", 0)) * 0.5 * maxf(0.0, q - 0.5) * 2.0))
		else:
			wage_gold = int(round(float(jd["wage"]) * 0.5 * maxf(0.0, q - 0.5) * 2.0))
	else:
		res["wage_via"] = "freelance"
		wage_gold = int(round(float(jd["wage"]) * clampf(q, 0.0, 1.2) * (0.6 if not done else 1.0)))
	# Work orders on the board: a good finished shift fills the first open one.
	if done and q >= 0.6:
		for o: Dictionary in board(sid, job, day):
			if not orders_done.has(String(o["id"])):
				orders_done[String(o["id"])] = true
				wage_gold += int(o["reward"])
				res["order"] = o
				break
	pending_gold += wage_gold
	res["gold"] = wage_gold
	# Employer standing and city reputation.
	var employer := String(shift["employer"])
	if employer != "":
		standing[employer] = clampf(float(standing.get(employer, STANDING_START)) + (q - 0.55) * 8.0, 0.0, 100.0)
	if done and q >= 0.8:
		_apply_regard(0.5, sid)
	elif q < 0.3:
		_apply_regard(-0.5, sid)
	res["comment"] = comment(job, q, sid, day, employer)
	res["standing"] = float(standing.get(employer, STANDING_START)) if employer != "" else -1.0
	_say(String(res["comment"]))
	if bool(ctx.get("abandoned", false)):
		res["comment"] = "You walked off the job."
	var st: Dictionary = stats.get(job, {"shifts": 0, "total_q": 0.0, "best": 0.0})
	st["shifts"] = int(st["shifts"]) + 1
	st["total_q"] = float(st["total_q"]) + q
	st["best"] = maxf(float(st["best"]), q)
	stats[job] = st
	last_done[job] = day
	shift = {}
	return res


func standing_with(employer: String) -> float:
	return float(standing.get(employer, STANDING_START))


# ---------------------------------------------------------------- board, coworkers, comments

func coworker(sid: int, job: String, day: int) -> String:
	var r := _rng("coworker", day / 30, "%d%s" % [sid, job])
	return "%s %s" % [FIRST[r.randi() % FIRST.size()], LAST[r.randi() % LAST.size()]]


func employer_name(sid: int, job: String, day: int) -> String:
	if shift.get("employer", "") != "" and String(shift.get("job", "")) == job:
		return String(shift["employer"])
	var pw := player_work()
	if String(pw["job"]) == job and String(pw["employer"]) != "":
		return String(pw["employer"])
	return "Master " + coworker(sid, job, day).split(" ")[1]


## What the employer (or the nearest coworker) says about the work.
func comment(job: String, q: float, sid: int, day: int, employer := "") -> String:
	var jd := job_def(job)
	if jd.is_empty():
		return ""
	var who := employer if employer != "" else employer_name(sid, job, day)
	var tier := "great" if q >= 0.75 else ("ok" if q >= 0.4 else "poor")
	var lines: Array = jd["say"][tier]
	var r := _rng("comment", day, "%s%d%d" % [job, sid, int(q * 10.0)])
	return String(lines[r.randi() % lines.size()]) % who


## Work orders posted at this workplace today (text only): [{id, text, reward}].
func board(sid: int, job: String, day: int) -> Array:
	var jd := job_def(job)
	var out: Array = []
	if jd.is_empty():
		return out
	var tpl: Array = jd["orders"]
	var r := _rng("workboard", day, "%d%s" % [sid, job])
	var n := 2 + r.randi() % 2
	for i in mini(n, tpl.size()):
		var k := (r.randi() + i) % tpl.size()
		var qty := 2 + r.randi() % 6
		var reward := int(round(float(jd["wage"]) * (0.8 + r.randf() * 0.7) * (1.0 + float(qty) * 0.05)))
		out.append({"id": "%d:%s:%d:%d" % [sid, job, day, i], "text": String(tpl[k]) % [qty, reward], "reward": reward})
	return out


# ---------------------------------------------------------------- ticks / save

func tick_day(day: int, _ctx: Dictionary) -> Array:
	_day = day
	# An unfinished shift from yesterday is closed as walked-off; standing drifts back to neutral.
	var out: Array = []
	if not shift.is_empty() and int(shift["day"]) < day:
		abandon()
	for e: String in standing.keys():
		standing[e] = float(standing[e]) + (STANDING_START - float(standing[e])) * 0.02
	if orders_done.size() > 60:
		orders_done.clear()
	return out


func catch_up(days: int, ctx: Dictionary) -> Array:
	if days > 0:
		tick_day(_day + days, ctx)
	return []


func serialize() -> Dictionary:
	return {"pending_gold": pending_gold, "shift": shift.duplicate(true), "standing": standing.duplicate(), "last_done": last_done.duplicate(),
		"stats": stats.duplicate(true), "log": log_lines.duplicate(), "orders_done": orders_done.duplicate(), "day": _day}


func deserialize(d: Dictionary) -> void:
	pending_gold = int(d.get("pending_gold", 0))
	shift = (d.get("shift", {}) as Dictionary).duplicate(true)
	if not shift.is_empty():
		shift["step"] = int(shift["step"])
		shift["sid"] = int(shift["sid"])
		shift["day"] = int(shift["day"])
		shift["problems"] = int(shift["problems"])
	standing = (d.get("standing", {}) as Dictionary).duplicate()
	last_done = {}
	for k: String in (d.get("last_done", {}) as Dictionary):
		last_done[k] = int(d["last_done"][k])
	stats = (d.get("stats", {}) as Dictionary).duplicate(true)
	log_lines = (d.get("log", []) as Array).duplicate()
	orders_done = (d.get("orders_done", {}) as Dictionary).duplicate()
	_day = int(d.get("day", 0))
	_layout_cache.clear()
