extends "res://scripts/realm/realm_module.gd"
## The Scribe career, played as skill, not as a button (docs/design/VERTICAL_SLICE.md, P1 real careers).
## copyist -> clerk -> registrar -> steward's secretary -> steward -> envoy.
##
## Mini-tasks (generators and scoring live in scribe_data.gd and are pure):
##   copy       accuracy: choose the faithful line among near-identical ones; quality sets pay and standing
##   forgery    compare seal, hand, date and ink with the archive specimen; rule genuine or forged
##   translate  old script: glyphs the player already knows (society knowledge "glyph:x") read for free
##   tax        audit a settlement's tax ledger against governance's rate; errors and skimming are noticed
##   restricted sealed archives (registrar+) reveal noble secrets: blackmail, report, sell, or keep
##   exam       the registrar's and steward's examinations
##   estate     steward: rents, repairs and stores of a noble estate (land.gd loyalty and memory)
##   embassy    envoy: negotiate pacts between nations (factions relations, news delegations)
##
## Promotion needs mastery, "letters" reputation, time in rank, counters of things done, sometimes an
## exam and a patron (a governance leader whose regard grows with good work). Consequences are real:
## blots lead to dismissal; a forgery you passed (or took a bribe for) is traced back to your desk
## and jails you (society crime hooks); blackmail is a crime.
##
## Money rule: never touches the purse; the presenter calls take_pending_gold().
## RNG: hash([WorldSim.SEED, tag, day, id]). All state is JSON-safe.

const Data := preload("res://scripts/realm/scribe_data.gd")
const CareerLadders := preload("res://scripts/sim/career_ladders.gd")
const RAMastery := preload("res://scripts/sim/mastery.gd")

const CAREER := "scribe"
const DISCIPLINE := "scholarship"
const RANKS := ["copyist", "clerk", "registrar", "stewards_secretary", "steward", "envoy"]
## Piece rate per task by rank (gold at quality 1.0 is about 1.4x this).
const PIECE := [6, 9, 14, 20, 30, 45]
## Weekly stipend of the post.
const STIPEND := [8, 18, 35, 55, 90, 140]
const TASK_HOURS := {"copy": 2.0, "forgery": 1.5, "translate": 2.0, "tax": 2.0, "restricted": 1.5, "exam": 3.0, "audience": 1.0, "estate": 1.0, "embassy": 6.0, "study": 2.0}
const MAX_HOURS := 10.0
const BLOTS_TO_FIRE := 5
const PATRON_FRIEND := 60.0
const XP_BASE := 0.35
const BAN_DAYS := 21
const RECORD_DAYS := 80
const HOME_NATION := "caldrenn"
const RENT := [4.0, 7.0, 11.0]
const LOG_MAX := 24

var mastery_ref: RefCounted = null     # tests inject one; otherwise Life.mastery
var bio_ref: RefCounted = null         # likewise Life.biography
var gold_ref := -1                     # tests inject; otherwise Game.gold
var sync_life := true                  # mirror rank into Life.career_id / career_rank (tests turn it off)

var pending_gold := 0
var active := false
var rank := 0
var since_day := 0
var home_sid := 0
var standing := 50.0
var blots := 0
var patron: Dictionary = {}
var exams: Dictionary = {}             # exam id -> day passed
var banned_until := -1
var jail_until := -1
var record_until := -1
var dismissals := 0
var stats: Dictionary = {}
var secrets: Array = []                # {id, kind, house, text, sev, about_patron, state, day}
var estate: Dictionary = {}
var traced: Array = []                 # forgeries you passed: {day, bribed, traced, kind}
var task: Dictionary = {}              # the open task (answers included; see task_view)
var hours_used: Dictionary = {}        # str(day) -> hours
var glyphs_known: Array = []
var missions_done: Array = []
var log_lines: Array = []
var _day := 0
var _counter := 0


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


func _say(text: String) -> void:
	log_lines.append(text)
	if log_lines.size() > LOG_MAX:
		log_lines.pop_front()


func take_pending_gold() -> int:
	var g := pending_gold
	pending_gold = 0
	return g


func level() -> int:
	var m := _mastery()
	return int(m.call("level", DISCIPLINE)) if m != null else 1


func _gain(amount: float, day: int) -> void:
	var m := _mastery()
	if m != null and amount > 0.0:
		m.call("gain", DISCIPLINE, amount, day)


func _gain_other(discipline: String, amount: float, day: int) -> void:
	var m := _mastery()
	if m != null:
		m.call("gain", discipline, amount, day)


func _letters(delta: float) -> void:
	var b := _bio()
	if b != null and absf(delta) > 0.0001:
		b.call("change_rep", "letters", delta)


func letters_rep() -> float:
	var b := _bio()
	return float(b.call("rep", "letters")) if b != null else 0.0


func _sname(sid: int) -> String:
	if sid >= 0 and sid < WorldGen.settlements.size():
		return WorldGen.display_name(String(WorldGen.settlements[sid]["name"]))
	return "the road"


func bump(stat: String, n := 1) -> void:
	stats[stat] = int(stats.get(stat, 0)) + n


func rank_id() -> String:
	return String(RANKS[clampi(rank, 0, RANKS.size() - 1)])


func rank_title() -> String:
	return CareerLadders.title_for(CAREER, rank_id())


func is_jailed(day: int) -> bool:
	return jail_until > day


func is_banned(day: int) -> bool:
	return banned_until > day


func clean_record(day: int) -> bool:
	return record_until <= day


func hours_left(day: int) -> float:
	return MAX_HOURS - float(hours_used.get(str(day), 0.0))


# ---------------------------------------------------------------- joining, patron

func _leader(sid: int) -> Dictionary:
	var gov := _mod("governance")
	if gov != null and gov.has_method("leader_of_settlement"):
		return gov.call("leader_of_settlement", sid)
	return {}


func _make_patron(sid: int, regard: float) -> Dictionary:
	var l := _leader(sid)
	var pid := String(l.get("id", "")) if not l.is_empty() else ""
	var nm := String(l.get("n", "Steward Aldric")) if not l.is_empty() else "Steward Aldric"
	var house: String = Data.HOUSES[hash([pid, nm, sid]) % Data.HOUSES.size()]
	return {"pid": pid, "name": nm, "sid": sid, "regard": regard, "house": house}


func patron_regard() -> float:
	return float(patron.get("regard", 0.0))


func _patron_add(delta: float) -> void:
	if patron.is_empty():
		return
	patron["regard"] = clampf(float(patron["regard"]) + delta, 0.0, 100.0)


## Relationships tier rank the ladder expects: 4 is "friend".
func sponsor_tier() -> int:
	if patron_regard() >= PATRON_FRIEND:
		return CareerLadders.SPONSOR_TIER_NEEDED
	return int(patron_regard() / 20.0)


## Why the player cannot take a post here, or "".
func apply_refusal(sid: int, day: int, literacy := 20.0) -> String:
	if active:
		return "You already serve as %s." % rank_title()
	if is_jailed(day):
		return "You are in the cells until day %d." % jail_until
	if is_banned(day):
		return "The scriptorium will not hear you before day %d." % banned_until
	if literacy < 15.0:
		return "You cannot read and write well enough."
	if dismissals >= 3 and day < banned_until + 60 * (dismissals - 2):
		return "Three scriptoria have dismissed you. None will take you on before day %d." % (banned_until + 60 * (dismissals - 2))
	if sid < 0 or sid >= WorldGen.settlements.size():
		return "There is no scriptorium here."
	return ""


## Entrance test: a copy of a short text (quality from the copy task) of at least 0.5 earns the desk.
func apply(sid: int, day: int, test_quality: float, literacy := 20.0) -> Dictionary:
	var why := apply_refusal(sid, day, literacy)
	if why != "":
		return {"ok": false, "reason": why}
	if test_quality < 0.5:
		return {"ok": false, "reason": "The master finds your copy too poor. Practise piece work and come back."}
	active = true
	home_sid = sid
	since_day = day
	standing = 50.0
	blots = 0
	var prior := rank > 0   # a returning scribe keeps the post he was demoted to
	if not prior:
		rank = 0
	patron = _make_patron(sid, 25.0 if patron.is_empty() else float(patron.get("regard", 25.0)) * 0.6)
	_sync_life(day)
	_say("You take a desk at the scriptorium of %s as %s." % [_sname(sid), rank_title()])
	return {"ok": true, "reason": "", "text": "You are now a %s in %s, under %s." % [rank_title(), _sname(sid), String(patron["name"])]}


func _sync_life(day: int) -> void:
	if not sync_life or Life == null:
		return
	if Life.get("career_id") == null:
		return
	if String(Life.career_id) != CAREER:
		Life.career_id = CAREER
		var b := _bio()
		if b != null:
			b.call("start_chapter", CAREER, "scriptorium", rank_id(), _sname(home_sid), day)
	Life.career_rank = rank_id()
	Life.career_since_day = since_day
	Life.career_sponsor_tier = sponsor_tier()


func _refresh_patron() -> void:
	if not active or patron.is_empty():
		return
	var l := _leader(home_sid)
	if l.is_empty():
		return
	if String(l.get("id", "")) != String(patron.get("pid", "")):
		var old := patron_regard()
		patron = _make_patron(home_sid, old * 0.5)
		_say("%s now holds %s. Your old patron's goodwill carries only partway." % [String(patron["name"]), _sname(home_sid)])


# ---------------------------------------------------------------- what can be done

func offers(day: int) -> Array:
	var out: Array = []
	var employed := active and not is_jailed(day) and not is_banned(day)
	var rk := rank if active else 0
	var defs := [
		["copy", "Copy a document", "Accuracy: pick the faithful line each time. Quality sets pay and standing.", 0],
		["forgery", "Examine a seal", "Compare seal, hand, date and ink with the archive specimen.", 1],
		["translate", "Read old script", "Glyphs you have learned read themselves; guess the rest from context.", 1],
		["tax", "Audit the tax ledger", "Check receipts against the roll and the settlement's rate. Errors are noticed.", 1],
		["restricted", "Open the sealed archive", "Restricted records hold noble secrets. What you do with them is the question.", 2],
		["study", "Study the glyph tables", "Learn old script from the archive.", 0],
		["exam", "Sit an examination", "Required before the next promotion.", 0],
		["audience", "Petition your patron", "Ask to be promoted when you are ready.", 0],
		["estate", "Manage the estate", "Set rents, repairs and stores for the week.", 4],
		["embassy", "Carry an embassy", "Negotiate between nations.", 5],
	]
	for d: Array in defs:
		var kind := String(d[0])
		var why := ""
		if kind != "copy" and (not employed):
			why = "Needs a post at the scriptorium."
		elif rk < int(d[3]) and kind != "copy":
			why = "Needs rank: %s." % CareerLadders.title_for(CAREER, String(RANKS[int(d[3])]))
		elif kind == "exam" and _next_exam() == "":
			why = "No examination stands before your next rank."
		elif kind == "estate" and estate.is_empty():
			why = "No estate has been entrusted to you."
		elif hours_left(day) < float(TASK_HOURS[kind]) and kind not in ["audience"]:
			why = "You have worked enough today."
		elif is_jailed(day):
			why = "You are in the cells."
		out.append({"kind": kind, "label": String(d[1]), "text": String(d[2]), "hours": float(TASK_HOURS[kind]), "rank_min": int(d[3]), "available": why == "", "why": why})
	return out


func _next_exam() -> String:
	var nxt := CareerLadders.next_rank_def(CAREER, rank_id())
	if nxt.is_empty():
		return ""
	var ex := String((nxt["requires"] as Dictionary).get("exam", ""))
	return ex if ex != "" and not exams.has(ex) else ""


func _spend(kind: String, day: int) -> void:
	hours_used[str(day)] = float(hours_used.get(str(day), 0.0)) + float(TASK_HOURS.get(kind, 1.0))
	if hours_used.size() > 6:
		var keys: Array = hours_used.keys()
		keys.sort_custom(func(a: String, b: String) -> bool: return int(a) < int(b))
		hours_used.erase(keys[0])


## Opens a task. Returns {ok, reason, view}. Only one task is open at a time.
func begin(kind: String, day: int) -> Dictionary:
	_day = maxi(_day, day)
	var off: Dictionary = {}
	for o: Dictionary in offers(day):
		if String(o["kind"]) == kind:
			off = o
	if off.is_empty():
		return {"ok": false, "reason": "Nothing like that to do."}
	if not bool(off["available"]):
		return {"ok": false, "reason": String(off["why"])}
	if not task.is_empty() and int(task.get("day", -1)) == day:
		return {"ok": false, "reason": "Finish the work in front of you first."}
	_counter += 1
	var r := _rng("stask", day, "%s%d" % [kind, _counter])
	var lv := level()
	var t := {"kind": kind, "day": day, "n": _counter, "level": lv, "employed": active}
	match kind:
		"copy":
			t["doc"] = Data.gen_copy(r, lv)
			t["blot_line"] = r.randi() % (t["doc"]["lines"] as Array).size()
		"forgery":
			t["doc"] = Data.gen_forgery(r, lv, day)
			t["examined"] = {}
			t["lens"] = 1
			t["bribe"] = 40 + 20 * rank if not (t["doc"]["flaws"] as Dictionary).is_empty() and rank >= 1 else 0
		"translate":
			t["text"] = Data.gen_translation(r, lv)
		"tax":
			var gov := _mod("governance")
			var rate := float(gov.call("tax", home_sid)) if gov != null and gov.has_method("tax") else 0.15
			var greed := 0.4
			var l := _leader(home_sid)
			if not l.is_empty() and (l.get("tr", {}) as Dictionary).has("greed"):
				greed = float(l["tr"]["greed"])
			t["ledger"] = Data.gen_tax(r, rate, greed, lv)
			t["sid"] = home_sid
		"exam":
			t["exam"] = _next_exam()
			t["questions"] = Data.exam_questions(String(t["exam"]), hash([WorldSim.SEED, day, _counter]))
		"restricted":
			pass
		_:
			pass
	task = t
	return {"ok": true, "reason": "", "view": task_view()}


## The open task with every answer stripped, safe to hand to a screen.
func task_view() -> Dictionary:
	if task.is_empty():
		return {}
	var v := task.duplicate(true)
	match String(task["kind"]):
		"copy":
			for l: Dictionary in (v["doc"] as Dictionary)["lines"]:
				l.erase("correct")
		"forgery":
			# Only issuer, kind and date are shown; seal, hand and ink reach the player through examine_channel().
			for k: String in ["flaws", "worn", "seal", "wax", "hand", "ink", "specimen"]:
				(v["doc"] as Dictionary).erase(k)
		"translate":
			for c: Dictionary in (v["text"] as Dictionary)["choices"]:
				c.erase("correct")
			(v["text"] as Dictionary).erase("fact")
			(v["text"] as Dictionary).erase("fact_text")
			v["known"] = glyphs_known_list()
		"tax":
			for row: Dictionary in (v["ledger"] as Dictionary)["rows"]:
				row.erase("err")
			(v["ledger"] as Dictionary).erase("skims")
			(v["ledger"] as Dictionary).erase("errors")
		"exam":
			for q: Dictionary in v["questions"]:
				q.erase("a")
	return v


func abandon_task() -> void:
	task = {}


# ---------------------------------------------------------------- shared effects

## Pay, mastery, reputation, standing and blots for one finished task. Returns {pay, ...}.
func _finish_task(kind: String, q: float, day: int, pay_scale := 1.0) -> Dictionary:
	_spend(kind, day)
	var res := {"quality": q, "pay": 0, "fired": false, "blot": false, "texts": []}
	_gain(XP_BASE * (0.4 + 0.6 * q), day)
	var piece := float(PIECE[clampi(rank, 0, PIECE.size() - 1)])
	var pay := 0
	if active:
		pay = int(round(piece * (0.4 + 1.0 * q) * pay_scale))
		_letters(0.16 * q - (0.5 if q < 0.3 else 0.0))
		standing = clampf(standing + (q - 0.5) * 6.0, 0.0, 100.0)
		_patron_add((q - 0.55) * 0.7)
		if q < 0.3:
			blots += 1
			res["blot"] = true
			(res["texts"] as Array).append("A blot against your name: %d of %d." % [blots, BLOTS_TO_FIRE])
		if blots >= BLOTS_TO_FIRE or standing <= 5.0:
			_fire(day, "poor_work")
			res["fired"] = true
			(res["texts"] as Array).append("You are dismissed for slipshod work.")
	else:
		pay = int(round(piece * 0.6 * (0.4 + 1.0 * q))) if kind == "copy" else 0   # freelance piece work
		_letters(0.15 * q)
	pending_gold += pay
	res["pay"] = pay
	task = {}
	return res


func _fire(day: int, reason: String) -> void:
	if not active:
		return
	active = false
	dismissals += 1
	banned_until = day + BAN_DAYS
	standing = 0.0
	blots = 0
	rank = maxi(0, rank - 1)
	since_day = day
	_patron_add(-15.0)
	_letters(-4.0)
	var soc := _mod("society")
	if soc != null and soc.has_method("log_failure"):
		soc.call("log_failure", "fired", "Dismissed from the scriptorium of %s (%s)." % [_sname(home_sid), reason.replace("_", " ")], home_sid)
	_say("You are dismissed from the scriptorium (%s)." % reason.replace("_", " "))
	_sync_life(day)


func _arrest(day: int, crime: String, witnesses := 2) -> void:
	var days := 10 + 5 * rank
	jail_until = day + days
	record_until = jail_until + RECORD_DAYS
	var was_active := active
	active = false
	banned_until = jail_until + BAN_DAYS
	rank = maxi(0, rank - 2)
	since_day = day
	standing = 0.0
	_patron_add(-40.0)
	_letters(-15.0)
	var soc := _mod("society")
	if soc != null:
		if soc.has_method("commit_crime"):
			soc.call("commit_crime", crime, home_sid, witnesses)
		if soc.has_method("log_failure"):
			soc.call("log_failure", "jailed", "Jailed in %s for %s. The ink on your fingers will not wash off in a cell." % [_sname(home_sid), crime], home_sid)
	pending_gold -= clampi(int(40 + 10 * rank), 0, maxi(0, _gold() + pending_gold))   # the fine never takes more than you have
	if was_active:
		dismissals += 1
	_say("You are jailed for %s until day %d." % [crime, jail_until])
	_sync_life(day)


# ---------------------------------------------------------------- copy

func submit_copy(picks: Array, steady: float) -> Dictionary:
	if task.is_empty() or String(task["kind"]) != "copy":
		return {"ok": false, "reason": "No copying in hand."}
	var day := int(task["day"])
	var doc: Dictionary = task["doc"]
	var sc := Data.score_copy(doc, picks, steady, int(task.get("blot_line", 0)))
	var q := float(sc["quality"])
	var res := _finish_task("copy", q, day)
	res.merge({"ok": true, "kind": "copy", "errors": sc["errors"], "crit_errors": sc["crit_errors"], "blot_ink": sc["blot"]})
	bump("copies")
	if q >= 0.9:
		bump("fair_copies")
	# An inspector reads critical lines; a slip in a sum, name or date is noticed more often as you rise.
	if active and int(sc["crit_errors"]) > 0:
		var r := _rng("inspect", day, _counter)
		if r.randf() < 0.3 + 0.05 * rank:
			standing = clampf(standing - 5.0, 0.0, 100.0)
			_patron_add(-1.5)
			blots += 1
			res["blot"] = true
			(res["texts"] as Array).append("The inspector finds a slip in a sum or a name. A blot against you (%d of %d)." % [blots, BLOTS_TO_FIRE])
			if blots >= BLOTS_TO_FIRE and not bool(res["fired"]):
				_fire(day, "repeated errors")
				res["fired"] = true
		else:
			bump("unnoticed_errors")
			(res["texts"] as Array).append("A slip passed unnoticed. It may surface later.")
	res["text"] = "%s: %d%% faithful. %dg." % [String(doc["title"]), int(q * 100.0), int(res["pay"])]
	return res


# ---------------------------------------------------------------- forgery

func examine_channel(channel: String, lens := false) -> Dictionary:
	if task.is_empty() or String(task["kind"]) != "forgery":
		return {"ok": false, "reason": "Nothing to examine."}
	if lens:
		if int(task["lens"]) <= 0:
			return {"ok": false, "reason": "The lens is used up; each examination spends an hour."}
		task["lens"] = int(task["lens"]) - 1
	var ex := Data.examine(task["doc"], channel, int(task["level"]), lens)
	(task["examined"] as Dictionary)[channel] = {"text": ex["text"], "lens": lens}
	return {"ok": true, "text": ex["text"], "channel": channel}


## verdict "forged"/"genuine"; named = channels the player points to. take_bribe: let a forgery through for coin.
func submit_forgery(verdict: String, named: Array, take_bribe := false) -> Dictionary:
	if task.is_empty() or String(task["kind"]) != "forgery":
		return {"ok": false, "reason": "No document before you."}
	var day := int(task["day"])
	var doc: Dictionary = task["doc"]
	var forged := not (doc["flaws"] as Dictionary).is_empty()
	var bribe := int(task.get("bribe", 0))
	var jr := Data.judge_forgery(doc, verdict, named)
	var outcome := String(jr["outcome"])
	var q := float(jr["quality"])
	var texts: Array = []
	var bribed := false
	if take_bribe and forged and bribe > 0:
		bribed = true
		outcome = "bribed"
		q = 0.0
		pending_gold += bribe
		texts.append("You pass it for %dg. If it is traced, the pen that passed it is yours." % bribe)
	# A miss is not known to you yet: the work looks fine today and the penalty comes when it is traced.
	var res := _finish_task("forgery", 0.5 if outcome in ["missed", "bribed"] else q, day, 1.3 if outcome == "caught" else 1.0)
	res["quality"] = q
	res["ok"] = true
	res["kind"] = "forgery"
	res["outcome"] = outcome
	res["bribe_taken"] = bribed
	(res["texts"] as Array).append_array(texts)
	match outcome:
		"caught":
			bump("forgeries_caught")
			_letters(0.6)
			_patron_add(0.8)
			var soc := _mod("society")
			if soc != null and soc.has_method("add_evidence"):
				soc.call("add_evidence", "forged_%s" % String(doc["kind"]).replace(" ", "_"), "forged_document", 0.7, home_sid)
			(res["texts"] as Array).append("The forgery is set aside and the issuer's house is informed. The magistrate is pleased.")
		"missed", "bribed":
			bump("forgeries_missed")
			traced.append({"day": day, "bribed": bribed, "traced": false, "kind": String(doc["kind"]), "house": String(doc["house"])})
			if traced.size() > 12:
				traced.pop_front()
			if not bribed:
				(res["texts"] as Array).append("You pass it as genuine. Something about it nags at you.")
		"false_alarm":
			bump("false_alarms")
			standing = clampf(standing - 6.0, 0.0, 100.0)
			_patron_add(-6.0)
			_letters(-1.0)
			(res["texts"] as Array).append("It was genuine. %s is offended by the accusation." % String(doc["house"]))
		"cleared":
			bump("documents_cleared")
	res["flaws"] = (doc["flaws"] as Dictionary).keys()
	res["text"] = {"caught": "Forgery caught.", "cleared": "Document cleared.", "false_alarm": "A genuine document wrongly accused.",
		"missed": "A forgery passed.", "bribed": "A forgery passed for coin."}.get(outcome, outcome)
	return res


# ---------------------------------------------------------------- translation

func glyphs_known_list() -> Array:
	var out: Array = glyphs_known.duplicate()
	var soc := _mod("society")
	if soc != null:
		for g: String in Data.GLYPHS:
			if not out.has(g) and soc.call("knows", "glyph:" + g):
				out.append(g)
	return out


func learn_glyph(g: String) -> bool:
	if not Data.GLYPHS.has(g) or glyphs_known_list().has(g):
		return false
	glyphs_known.append(g)
	var soc := _mod("society")
	if soc != null:
		soc.call("learn", "glyph:" + g, "%s means %s in the old script." % [g, Data.GLYPHS[g]])
	return true


## Study the archive's glyph tables: teaches one or two glyphs (needs time, no pay).
func study_glyphs(day: int) -> Dictionary:
	var why := ""
	for o: Dictionary in offers(day):
		if String(o["kind"]) == "study" and not bool(o["available"]):
			why = String(o["why"])
	if why != "":
		return {"ok": false, "reason": why}
	var known := glyphs_known_list()
	var pool: Array = []
	for g: String in Data.GLYPHS:
		if not known.has(g):
			pool.append(g)
	if pool.is_empty():
		return {"ok": false, "reason": "You have nothing left to learn from the tables."}
	_counter += 1
	var r := _rng("study", day, _counter)
	var learned: Array = []
	for i in mini(1 + (1 if level() >= 15 else 0), pool.size()):
		var g: String = pool.pop_at(r.randi() % pool.size())
		learn_glyph(g)
		learned.append(g)
	_spend("study", day)
	_gain(XP_BASE * 0.5, day)
	return {"ok": true, "learned": learned, "text": "You learn: %s." % ", ".join(learned.map(func(g: String) -> String: return "%s (%s)" % [g, Data.GLYPHS[g]]))}


func submit_translation(guesses: Array) -> Dictionary:
	if task.is_empty() or String(task["kind"]) != "translate":
		return {"ok": false, "reason": "Nothing to translate."}
	var day := int(task["day"])
	var t: Dictionary = task["text"]
	var sc := Data.score_translation(t, glyphs_known_list(), guesses)
	var q := float(sc["quality"])
	var res := _finish_task("translate", q, day, 1.2)
	res["ok"] = true
	res["kind"] = "translate"
	res["learned"] = sc["learned"]
	for g: String in sc["learned"]:
		learn_glyph(g)
	if q >= 0.6:
		bump("translations")
		var soc := _mod("society")
		if soc != null:
			soc.call("learn", String(t["fact"]), String(t["fact_text"]))
		res["fact"] = String(t["fact"])
		res["meaning"] = String(t["meaning"])
		(res["texts"] as Array).append("You read it: \"%s\"" % String(t["meaning"]))
		if String(t["fact"]).begins_with("secret:"):
			(res["texts"] as Array).append("Some things were sealed in old script for a reason.")
	else:
		(res["texts"] as Array).append("The sense escapes you. Too many glyphs are strange.")
	res["text"] = "%s: %d%% understood. %dg." % [String(t["title"]), int(q * 100.0), int(res["pay"])]
	return res


# ---------------------------------------------------------------- tax

func submit_tax(marked: Array) -> Dictionary:
	if task.is_empty() or String(task["kind"]) != "tax":
		return {"ok": false, "reason": "No ledger open."}
	var day := int(task["day"])
	var led: Dictionary = task["ledger"]
	var sc := Data.score_tax(led, marked)
	var q := float(sc["quality"])
	var res := _finish_task("tax", q, day, 1.1)
	res["ok"] = true
	res["kind"] = "tax"
	res["found"] = sc["found"]
	res["missed"] = sc["missed"]
	res["false_flags"] = sc["false_flags"]
	res["causes"] = sc["causes"]
	res["rows"] = (led["rows"] as Array).duplicate(true)
	if q >= 0.5:
		bump("tax_audits")
	bump("errors_found", int(sc["found"]))
	var sid := int(task.get("sid", home_sid)) if not task.is_empty() else home_sid
	var gov := _mod("governance")
	if int(sc["skim_found"]) > 0:
		var sec := _new_secret("skim", day, sid, false)
		res["secret"] = sec["id"]
		(res["texts"] as Array).append("Receipts exceed the roll. Someone is skimming. You note the name in your private book.")
		if gov != null and gov.has_method("shock"):
			gov.call("shock", sid, {"poor": 0.02, "merchants": 0.02}, "a tax audit finds a skimming collector")
	if int(sc["missed"]) > 0 and active:
		bump("errors_on_roll", int(sc["missed"]))
		var r := _rng("audit", day, _counter)
		if r.randf() < 0.3 + 0.1 * rank:
			standing = clampf(standing - 4.0, 0.0, 100.0)
			_patron_add(-2.0)
			(res["texts"] as Array).append("A later audit finds the error you let through. Your name is on the roll.")
	if gov != null and q >= 0.7:
		(res["texts"] as Array).append("The roll for %s is corrected at %d%%." % [_sname(sid), int(round(float(led["rate"]) * 100.0))])
	res["text"] = "Ledger audit: %d of %d errors found, %d wrongly flagged. %dg." % [int(sc["found"]), int(led["errors"]), int(sc["false_flags"]), int(res["pay"])]
	return res


# ---------------------------------------------------------------- exams and promotion

func submit_exam(answers: Array) -> Dictionary:
	if task.is_empty() or String(task["kind"]) != "exam":
		return {"ok": false, "reason": "No examination in hand."}
	var day := int(task["day"])
	var qs: Array = task["questions"]
	var ok := 0
	for i in qs.size():
		if i < answers.size() and int(answers[i]) == int(qs[i]["a"]):
			ok += 1
	var frac := float(ok) / float(maxi(qs.size(), 1))
	var ex := String(task["exam"])
	var need := float(Data.EXAMS[ex]["pass"])
	var passed := frac >= need
	_spend("exam", day)
	_gain(XP_BASE * 0.8, day)
	task = {}
	if passed:
		exams[ex] = day
		_letters(1.5)
		_patron_add(3.0)
	return {"ok": true, "kind": "exam", "passed": passed, "score": frac, "exam": ex, "text": "%s: %d of %d. %s" % [String(Data.EXAMS[ex]["title"]), ok, qs.size(),
		"Passed." if passed else "You may sit it again tomorrow."], "pay": 0}


func ladder_ctx(day: int) -> Dictionary:
	return {"career": CAREER, "rank": rank_id(), "since_day": since_day, "day": day, "mastery": _mastery(), "biography": _bio(),
		"gold": _gold(), "at_war": false, "sponsor_tier": sponsor_tier(), "career_stats": stats, "exams": exams,
		"clean_record": clean_record(day), "org": "scriptorium", "place": _sname(home_sid)}


func promotion_status(day: int) -> Dictionary:
	return CareerLadders.check_promotion(ladder_ctx(day))


## Petition the patron. Promotes when every requirement is met. {ok, text, missing}.
func petition(day: int) -> Dictionary:
	if not active:
		return {"ok": false, "text": "You hold no post.", "missing": PackedStringArray()}
	if is_jailed(day):
		return {"ok": false, "text": "You are in the cells.", "missing": PackedStringArray()}
	var r := CareerLadders.promote(ladder_ctx(day))
	if not bool(r["ok"]):
		return {"ok": false, "text": "%s is not yet ready to sign for you." % String(patron.get("name", "Your patron")), "missing": r["missing"]}
	rank = mini(rank + 1, RANKS.size() - 1)
	since_day = day
	standing = clampf(standing + 8.0, 0.0, 100.0)
	_patron_add(2.0)
	_letters(1.0)
	_say("Promoted to %s." % rank_title())
	if rank_id() == "steward":
		assign_estate(day)
	_spend("audience", day)
	_sync_life(day)
	return {"ok": true, "text": "Promoted to %s. %s" % [rank_title(), "An estate is put in your charge." if rank_id() == "steward" else ""], "missing": PackedStringArray()}


# ---------------------------------------------------------------- restricted records, secrets

func _new_secret(kind: String, day: int, sid: int, about_patron: bool) -> Dictionary:
	_counter += 1
	var r := _rng("secret", day, "%s%d" % [kind, _counter])
	var house: String = patron.get("house", Data.HOUSES[0]) if about_patron else Data.HOUSES[r.randi() % Data.HOUSES.size()]
	if not about_patron and house == String(patron.get("house", "")):
		house = Data.HOUSES[(Data.HOUSES.find(house) + 1) % Data.HOUSES.size()]
	var def: Dictionary = Data.SECRETS[kind]
	var s := {"id": "%s_%d_%d" % [kind, sid, day], "kind": kind, "house": house, "text": String(def["text"]) % house, "sev": int(def["sev"]),
		"about_patron": about_patron, "state": "held", "day": day, "sid": sid}
	for e: Dictionary in secrets:
		if String(e["id"]) == String(s["id"]):
			return e
	secrets.append(s)
	if secrets.size() > 16:
		secrets.pop_front()
	var soc := _mod("society")
	if soc != null:
		soc.call("learn", "secret:" + String(s["id"]), String(s["text"]))
	return s


## Read the sealed volumes. Below registrar this is snooping: caught, you are dismissed (or worse).
func read_restricted(day: int, sneak := false) -> Dictionary:
	if is_jailed(day):
		return {"ok": false, "reason": "You are in the cells."}
	if hours_left(day) < float(TASK_HOURS["restricted"]):
		return {"ok": false, "reason": "You have worked enough today."}
	if int(stats.get("_last_read", -99)) > day - 3 and int(stats.get("_last_read", -99)) <= day:
		return {"ok": false, "reason": "The sealed shelves were disturbed too recently. Wait a few days."}
	var allowed := active and rank >= 2
	if not allowed and not sneak:
		return {"ok": false, "reason": "Only a registrar may open the sealed archive."}
	_counter += 1
	var r := _rng("restr", day, _counter)
	if not allowed:
		if r.randf() < 0.55:
			if r.randf() < 0.4:
				_arrest(day, "burglary", 1)
				return {"ok": true, "caught": true, "secret": {}, "text": "You are caught in the archive and dragged to the cells."}
			if active:
				_fire(day, "caught in the sealed archive")
			return {"ok": true, "caught": true, "secret": {}, "text": "You are caught with a sealed volume open and shown the door."}
	_spend("restricted", day)
	stats["_last_read"] = day
	var kinds: Array = Data.SECRETS.keys()
	var kind := String(Data.pick(r, kinds))
	var about := r.randf() < 0.18 and not patron.is_empty()
	var s := _new_secret(kind, day, home_sid, about)
	bump("restricted_reads")
	_gain(XP_BASE * 0.6, day)
	return {"ok": true, "caught": false, "secret": s, "text": "In the sealed volumes: %s" % String(s["text"])}


func secret(id: String) -> Dictionary:
	for s: Dictionary in secrets:
		if String(s["id"]) == id:
			return s
	return {}


## action: "blackmail" | "report" | "sell" | "keep". Returns {ok, text, gold, crime, jailed}.
func use_secret(id: String, action: String, day: int) -> Dictionary:
	var s := secret(id)
	if s.is_empty() or String(s["state"]) not in ["held"]:
		return {"ok": false, "reason": "That secret is spent."}
	if is_jailed(day):
		return {"ok": false, "reason": "You are in the cells."}
	var sev := int(s["sev"])
	var r := _rng("usesecret", day, "%s%s" % [id, action])
	var soc := _mod("society")
	var out := {"ok": true, "gold": 0, "crime": "", "jailed": false, "text": ""}
	match action:
		"blackmail":
			var chance := clampf(0.7 + 0.05 * float(rank) - 0.1 * float(sev), 0.2, 0.9)
			out["crime"] = "extortion"
			if r.randf() < chance:
				var gold := sev * 55 + r.randi_range(0, 40)
				pending_gold += gold
				out["gold"] = gold
				s["state"] = "blackmailed"
				s["pay_day"] = day
				if soc != null:
					soc.call("commit_crime", "extortion", home_sid, 0)
				out["text"] = "%s pays %dg for your silence. It will not be the last request." % [String(s["house"]), gold]
				bump("blackmailed")
				_letters(-2.0)
			else:
				s["state"] = "exposed"
				out["text"] = "%s refuses, and sends for the watch." % String(s["house"])
				_arrest(day, "extortion", 2)
				out["jailed"] = true
		"report":
			var reward := sev * 30
			pending_gold += reward
			out["gold"] = reward
			s["state"] = "reported"
			_letters(2.0)
			if bool(s["about_patron"]):
				_patron_add(-35.0)
				out["text"] = "The magistrate thanks you with %dg. Your patron's house will remember who read its secrets." % reward
			else:
				_patron_add(4.0)
				out["text"] = "The magistrate thanks you with %dg. Your patron approves of an honest pen." % reward
			if String(s["kind"]) == "forged_title" and soc != null:
				soc.call("add_evidence", "forged_title", "forged_document", 0.8, int(s["sid"]))
			bump("secrets_reported")
		"sell":
			var gold2 := sev * 45 + r.randi_range(0, 30)
			pending_gold += gold2
			out["gold"] = gold2
			s["state"] = "sold"
			_letters(-4.0)
			var b := _bio()
			if b != null:
				b.call("change_rep", "underworld", 3.0)
			if soc != null:
				soc.call("add_crim_rep", "city:%d" % int(s["sid"]), 1.5, "sold a secret")
			out["text"] = "A man with no name pays %dg for the page's contents." % gold2
			if r.randf() < 0.15:
				out["text"] += " Word gets out."
				_fire(day, "selling archive secrets")
			bump("secrets_sold")
		_:
			s["state"] = "held"
			out["text"] = "You keep it, folded small, for a day when it matters."
			s["kept"] = day
			bump("secrets_kept")
	return out


# ---------------------------------------------------------------- estate (steward)

func assign_estate(day: int) -> void:
	var land := _mod("land")
	var region := str(home_sid)
	var house: String = patron.get("house", Data.HOUSES[0])
	var nm := _sname(home_sid)
	if land != null:
		var regs: Array = land.call("regions")
		var pick_r := ""
		for rg: Variant in regs:
			var d: Dictionary = land.call("deed", rg)
			if String(d.get("kind", "")) == "noble_estate" and (pick_r == "" or str(rg) == str(home_sid)):
				pick_r = str(rg)
		if pick_r != "":
			region = pick_r
			var dd: Dictionary = land.call("deed", pick_r)
			nm = String(dd.get("name", nm))
			house = String(dd.get("holder", house))
	var r := _rng("estate", day, region)
	estate = {"region": region, "name": nm, "house": house, "tenants": 8 + r.randi_range(0, 8), "rent": 1, "repairs": 1, "stores": 40,
		"treasury": 0, "owner_share": 0, "weeks": 0, "skimmed": 0, "last": {}, "since": day}


func set_estate_policy(rent: int, repairs: int) -> bool:
	if estate.is_empty():
		return false
	estate["rent"] = clampi(rent, 0, 2)
	estate["repairs"] = clampi(repairs, 0, 2)
	return true


## One week of estate management: income, costs, loyalty on land.gd. Returns the report.
func estate_week(day: int) -> Dictionary:
	if estate.is_empty():
		return {}
	var land := _mod("land")
	var skill := 0.85 + 0.3 * clampf(float(level()) / 60.0, 0.0, 1.0)
	var tenants := int(estate["tenants"])
	var income := int(round(float(tenants) * float(RENT[int(estate["rent"])]) * skill))
	var cost := int(round(float(tenants) * 1.2 * float(int(estate["repairs"]))))
	var net := income - cost
	var pay := maxi(0, int(round(float(net) * 0.1)))
	estate["treasury"] = int(estate["treasury"]) + int(round(float(net) * 0.9)) - pay
	estate["owner_share"] = int(estate["owner_share"]) + int(round(float(net) * 0.6))
	estate["stores"] = clampi(int(estate["stores"]) + 4 + int(estate["repairs"]) - (2 if int(estate["rent"]) == 2 else 0), 0, 120)
	var dl: float = [1.2, 0.2, -1.6][int(estate["rent"])] + 0.5 * float(int(estate["repairs"])) - 0.3
	var loyalty := 55.0
	if land != null:
		land.call("adjust_loyalty", estate["region"], dl)
		if int(estate["rent"]) == 0:
			land.call("remember", estate["region"], "relief", 0.1, day)
		elif int(estate["rent"]) == 2:
			land.call("remember", estate["region"], "tax_burden", 0.12, day)
		if int(estate["repairs"]) == 0:
			land.call("remember", estate["region"], "neglect", 0.08, day)
		loyalty = float(land.call("loyalty", estate["region"]))
	estate["weeks"] = int(estate["weeks"]) + 1
	pending_gold += pay
	bump("estate_weeks")
	_gain_other("leadership", 0.8, day)
	var rep := {"income": income, "cost": cost, "net": net, "pay": pay, "loyalty": loyalty, "text": ""}
	if loyalty > 55.0 and net > 0:
		_patron_add(1.2)
	elif loyalty < 35.0:
		_patron_add(-2.5)
		rep["text"] = "Unrest on %s: the tenants mutter about the steward." % String(estate["name"])
	# Audit: skimming is eventually found; honest books earn the lord's trust.
	var r := _rng("eaudit", day, estate["weeks"])
	var chance := 0.05 + float(int(estate["skimmed"])) / 300.0
	if r.randf() < chance:
		if int(estate["skimmed"]) > 0:
			rep["text"] = "The lord's auditors find %dg missing from the estate. You are arrested." % int(estate["skimmed"])
			_arrest(day, "fraud", 2)
			estate = {}
			rep["arrested"] = true
		else:
			_patron_add(3.0)
			rep["text"] = "The lord's auditors find the estate books in perfect order."
	estate["last"] = rep.duplicate()
	return rep


## Take estate money for yourself. Returns {ok, gold}.
func estate_skim(amount: int) -> Dictionary:
	if estate.is_empty() or amount <= 0 or int(estate["treasury"]) < amount:
		return {"ok": false, "gold": 0}
	estate["treasury"] = int(estate["treasury"]) - amount
	estate["skimmed"] = int(estate["skimmed"]) + amount
	pending_gold += amount
	return {"ok": true, "gold": amount}


# ---------------------------------------------------------------- envoy

func home_nation() -> String:
	return HOME_NATION


func missions(day: int) -> Array:
	var fa := _mod("factions")
	var out: Array = []
	if fa == null:
		return out
	var week := day / 7
	var nations: Array = []
	for f: Dictionary in fa.call("factions"):
		if String(f["kind"]) == "nation" and String(f["id"]) != HOME_NATION:
			nations.append(f)
	if nations.is_empty():
		return out
	var purposes: Array = Data.MISSIONS.keys()
	for i in mini(3, nations.size()):
		var r := _rng("mission", week, i)
		var f: Dictionary = nations[r.randi() % nations.size()]
		var purpose := String(purposes[r.randi() % purposes.size()])
		var rel: Dictionary = fa.call("relation", HOME_NATION, String(f["id"]))
		var def: Dictionary = Data.MISSIONS[purpose]
		out.append({"id": "%d:%d" % [week, i], "target": String(f["id"]), "target_name": String(f["name"]), "purpose": purpose,
			"diff": float(def["diff"]), "pay": int(def["pay"]), "stance": String(rel["stance"]), "trust": float(rel["trust"]), "grievance": float(rel["grievance"]),
			"hint": envoy_hint(rel)})
	return out


## The tone each of three rounds wants, from the relation: "flatter" (wounded pride), "bargain" (trust), "press" (they fear you).
static func wanted_tones(rel: Dictionary, diff: float, seed_value: int) -> Array:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	var base := "bargain"
	if float(rel.get("grievance", 0.0)) >= 25.0:
		base = "flatter"
	elif float(rel.get("fear", 0.0)) >= 30.0:
		base = "press"
	var tones := ["flatter", "bargain", "press"]
	var out: Array = []
	for i in 3:
		out.append(base if r.randf() < 1.0 - diff * 0.6 else String(tones[r.randi() % 3]))
	return out


static func envoy_hint(rel: Dictionary) -> String:
	if float(rel.get("grievance", 0.0)) >= 25.0:
		return "Their court nurses an old wound. Pride must be soothed."
	if float(rel.get("fear", 0.0)) >= 30.0:
		return "They fear us; firmness will be heard."
	return "They are open to a fair trade of favours."


## tones: three picks from "flatter"/"bargain"/"press". Returns {ok, score, outcome, text, pay}.
func run_mission(mission: Dictionary, tones: Array, day: int) -> Dictionary:
	if not active or rank < 5:
		return {"ok": false, "reason": "Only an envoy may carry an embassy."}
	if hours_left(day) < float(TASK_HOURS["embassy"]):
		return {"ok": false, "reason": "You have worked enough today."}
	var fa := _mod("factions")
	if fa == null:
		return {"ok": false, "reason": "There is no court to send you to."}
	var rel: Dictionary = fa.call("relation", HOME_NATION, String(mission["target"]))
	var want := wanted_tones(rel, float(mission["diff"]), hash([WorldSim.SEED, "env", String(mission["id"])]))
	var match_n := 0
	for i in 3:
		if i < tones.size() and String(tones[i]) == String(want[i]):
			match_n += 1
	var skill := clampf(float(level()) / 70.0, 0.0, 1.0)
	var score := clampf(float(match_n) / 3.0 * 0.7 + 0.3 * skill - float(mission["diff"]) * 0.2 + 0.1, 0.0, 1.0)
	var def: Dictionary = Data.MISSIONS[String(mission["purpose"])]
	_spend("embassy", day)
	_gain(XP_BASE * 1.2, day)
	_gain_other("leadership", 0.8, day)
	var out := {"ok": true, "score": score, "wanted": want, "matches": match_n, "pay": 0, "outcome": "", "text": ""}
	var nm := String(mission["target_name"])
	if score >= 0.6:
		fa.call("change_relation", HOME_NATION, String(mission["target"]), "trust", float(def["trust"]) * score)
		fa.call("change_relation", HOME_NATION, String(mission["target"]), "trade", float(def["trade"]) * score)
		var pay := int(round(float(mission["pay"]) * score))
		pending_gold += pay
		out["pay"] = pay
		out["outcome"] = "success"
		out["text"] = "Your embassy to %s succeeds: you %s. Pay %dg." % [nm, String(mission["purpose"]), pay]
		_letters(2.0)
		_patron_add(4.0)
		bump("missions")
		var news := _mod("news")
		if news != null:
			var txt := "An envoy from Caldrenn, %s, concludes talks at the court of %s to %s." % [String(patron.get("name", "the steward's secretary")), nm, String(mission["purpose"])]
			if news.has_method("_dip_add"):
				news.call("_dip_add", "envoy", HOME_NATION, String(mission["target"]), home_sid, 4, txt)
			if news.has_method("post"):
				news.call("post", "envoy", home_sid, txt, 1.5, "", true, day)
	elif score >= 0.3:
		fa.call("change_relation", HOME_NATION, String(mission["target"]), "trust", -1.0)
		out["outcome"] = "stalled"
		out["text"] = "The talks at %s stall. Nothing is signed; nothing is lost." % nm
		_patron_add(-1.0)
	else:
		fa.call("change_relation", HOME_NATION, String(mission["target"]), "grievance", 4.0)
		out["outcome"] = "insult"
		out["text"] = "Your manner offends the court of %s. Relations cool." % nm
		_patron_add(-5.0)
		_letters(-1.0)
	missions_done.append({"day": day, "target": String(mission["target"]), "outcome": String(out["outcome"])})
	if missions_done.size() > 12:
		missions_done.pop_front()
	return out


# ---------------------------------------------------------------- ticks

func tick_hour(_hour: int, _ctx: Dictionary) -> Array:
	return []


func tick_day(day: int, _ctx: Dictionary) -> Array:
	_day = day
	var out: Array = []
	if is_jailed(day) == false and jail_until >= 0 and jail_until <= day:
		jail_until = -1
		out.append("You are released from the cells.")
	if not task.is_empty() and int(task.get("day", day)) < day:
		task = {}
	if not active:
		return out
	_refresh_patron()
	if day % 4 == 0 and blots > 0:
		blots -= 1
	standing += (50.0 - standing) * 0.02
	# Slip for the day: auto-petition when everything is in order (the patron presents your name).
	var st := promotion_status(day)
	if bool(st["eligible"]) and rank < RANKS.size() - 1:
		var pr := petition(day)
		if bool(pr["ok"]):
			out.append(String(pr["text"]))
	return out


func tick_week(week: int, _ctx: Dictionary) -> Array:
	var out: Array = []
	var day := week * 7
	if jail_until > day:
		return out
	if active:
		pending_gold += int(STIPEND[rank])
		# A patron's goodwill is kept up by service; left alone it cools toward indifference.
		if not patron.is_empty():
			patron["regard"] = clampf(float(patron["regard"]) + (30.0 - float(patron["regard"])) * 0.03, 0.0, 100.0)
	# Forgeries you passed come back to the desk that passed them.
	for t: Dictionary in traced:
		if bool(t["traced"]):
			continue
		var r := _rng("trace", day, "%d%s" % [int(t["day"]), t["house"]])
		var p := 0.45 if bool(t["bribed"]) else 0.2
		if day - int(t["day"]) >= 7 and r.randf() < p:
			t["traced"] = true
			if bool(t["bribed"]):
				out.append("A forged %s you passed for coin is traced back to your desk. You are arrested." % String(t["kind"]))
				_arrest(day, "fraud", 2)
			elif active:
				standing = clampf(standing - 15.0, 0.0, 100.0)
				_patron_add(-10.0)
				blots += 2
				out.append("A forged %s you passed as genuine is traced to your desk. Your patron is displeased (blots: %d)." % [String(t["kind"]), blots])
				if blots >= BLOTS_TO_FIRE:
					_fire(day, "negligence over a forgery")
					out.append("You are dismissed for negligence.")
	# Held secrets leak; blackmailed houses retaliate.
	for s: Dictionary in secrets:
		var st := String(s["state"])
		var r2 := _rng("sleak", day, s["id"])
		if st == "held" and day - int(s["day"]) > 30 and r2.randf() < 0.05:
			s["state"] = "leaked"
			_patron_add(-12.0)
			out.append("Word spreads that someone read the sealed archive of %s. Suspicion falls on the scriptorium." % String(s["house"]))
		elif st == "blackmailed" and day - int(s.get("pay_day", day)) < 28 and r2.randf() < 0.1:
			s["state"] = "exposed"
			out.append("%s has gone to the magistrate about the blackmail." % String(s["house"]))
			if active or rank > 0:
				_arrest(day, "extortion", 2)
				out.append("You are arrested.")
	if active and not estate.is_empty():
		var rep := estate_week(day)
		if String(rep.get("text", "")) != "":
			out.append(String(rep["text"]))
	return out


## Statistical sleep: stipend weeks, blots healing, jail time served, estate weeks on auto policy.
func catch_up(days: int, _ctx: Dictionary) -> Array:
	if days <= 0:
		return []
	var weeks := days / 7
	_day += days
	if jail_until >= 0 and jail_until <= _day:
		jail_until = -1
	if active:
		blots = maxi(0, blots - weeks)
		standing += (50.0 - standing) * (1.0 - pow(0.98, float(days)))
		pending_gold += int(STIPEND[rank]) * weeks
		if not estate.is_empty():
			stats["estate_weeks"] = int(stats.get("estate_weeks", 0)) + weeks
			estate["weeks"] = int(estate["weeks"]) + weeks
	return []


func serialize() -> Dictionary:
	return {"pending_gold": pending_gold, "active": active, "rank": rank, "since_day": since_day, "home_sid": home_sid, "standing": standing, "blots": blots,
		"patron": patron.duplicate(true), "exams": exams.duplicate(), "banned_until": banned_until, "jail_until": jail_until, "record_until": record_until,
		"dismissals": dismissals, "stats": stats.duplicate(), "secrets": secrets.duplicate(true), "estate": estate.duplicate(true), "traced": traced.duplicate(true),
		"task": task.duplicate(true), "hours_used": hours_used.duplicate(), "glyphs": glyphs_known.duplicate(), "missions": missions_done.duplicate(true),
		"log": log_lines.duplicate(), "day": _day, "counter": _counter}


func deserialize(d: Dictionary) -> void:
	pending_gold = int(d.get("pending_gold", 0))
	active = bool(d.get("active", false))
	rank = int(d.get("rank", 0))
	since_day = int(d.get("since_day", 0))
	home_sid = int(d.get("home_sid", 0))
	standing = float(d.get("standing", 50.0))
	blots = int(d.get("blots", 0))
	patron = (d.get("patron", {}) as Dictionary).duplicate(true)
	if patron.has("sid"):
		patron["sid"] = int(patron["sid"])
	exams = {}
	for k: String in (d.get("exams", {}) as Dictionary):
		exams[k] = int(d["exams"][k])
	banned_until = int(d.get("banned_until", -1))
	jail_until = int(d.get("jail_until", -1))
	record_until = int(d.get("record_until", -1))
	dismissals = int(d.get("dismissals", 0))
	stats = {}
	for k2: String in (d.get("stats", {}) as Dictionary):
		stats[k2] = int(d["stats"][k2])
	secrets = (d.get("secrets", []) as Array).duplicate(true)
	for s: Dictionary in secrets:
		s["sev"] = int(s["sev"])
		s["day"] = int(s["day"])
		s["sid"] = int(s["sid"])
	estate = (d.get("estate", {}) as Dictionary).duplicate(true)
	for k3: String in ["tenants", "rent", "repairs", "stores", "treasury", "owner_share", "weeks", "skimmed", "since"]:
		if estate.has(k3):
			estate[k3] = int(estate[k3])
	traced = (d.get("traced", []) as Array).duplicate(true)
	for t: Dictionary in traced:
		t["day"] = int(t["day"])
	task = (d.get("task", {}) as Dictionary).duplicate(true)
	hours_used = (d.get("hours_used", {}) as Dictionary).duplicate()
	glyphs_known = (d.get("glyphs", []) as Array).duplicate()
	missions_done = (d.get("missions", []) as Array).duplicate(true)
	log_lines = (d.get("log", []) as Array).duplicate()
	_day = int(d.get("day", 0))
	_counter = int(d.get("counter", 0))
