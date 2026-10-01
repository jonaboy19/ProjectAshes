extends Node
## Headless career sim: a scribe plays day after day with a skill-driven model of the mini-tasks and we
## print when each rank arrives (in-game days and weeks), what the player earned and what went wrong.
##   godot --headless --path . res://tools_qa/careers/career_sim.tscn -- --days=420 --out=/tmp/x.txt
## Three players: "honest" (competent, reports secrets), "careless" (sloppy pen, snoops, takes bribes),
## "schemer" (competent but blackmails and skims). Same world seed for all.

const Hub := preload("res://scripts/realm/realm_hub.gd")
const Mastery := preload("res://scripts/sim/mastery.gd")
const Biography := preload("res://scripts/sim/biography.gd")
const Data := preload("res://scripts/realm/scribe_data.gd")

var lines: Array = []


func _ready() -> void:
	var days := 420
	var out_path := "/tmp/claude-0/careers/sim.txt"
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--days="):
			days = int(a.substr(7))
		elif a.begins_with("--out="):
			out_path = a.substr(6)
	WorldGen.setup(2024)
	for who: Array in [["honest", 0.0, 0.93], ["careless", 1.0, 0.62], ["schemer", 2.0, 0.93]]:
		_run(String(who[0]), int(who[1]), float(who[2]), days)
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	print("\n".join(lines))
	get_tree().quit()


func _p(s: String) -> void:
	lines.append(s)


func _run(label: String, mode: int, base_acc: float, days: int) -> void:
	var hub: RefCounted = Hub.new()
	var sc: RefCounted = hub.mod("scribe")
	sc.mastery_ref = Mastery.new()
	sc.bio_ref = Biography.new()
	sc.sync_life = false
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var gold := 0
	sc.gold_ref = 0
	_p("=== %s scribe (pen accuracy %.2f) ===" % [label, base_acc])
	# Join: the entrance copy test.
	var joined := false
	var day := 1
	var events: Array = []
	var last_rank := -1
	var jailed_days := 0
	var seen_log := 0
	for d in range(1, days + 1):
		day = d
		hub.mod("governance").tick_day(d, {})
		sc.tick_day(d, {})
		if d % 7 == 0:
			sc.tick_week(d / 7, {})
			hub.mod("land").tick_week(d / 7, {})
		gold += sc.take_pending_gold()
		sc.gold_ref = maxi(gold, 0)
		for ll in range(seen_log, sc.log_lines.size()):
			var t := String(sc.log_lines[ll])
			if t.contains("dismiss") or t.contains("jailed") or t.contains("Promoted") and false:
				events.append("day %3d: %s" % [d, t])
		seen_log = sc.log_lines.size()
		if sc.is_jailed(d):
			jailed_days += 1
		if not sc.active and not sc.is_jailed(d) and not sc.is_banned(d):
			var q := _play_copy(sc, d, base_acc, rng)
			if not joined or true:
				var ap: Dictionary = sc.apply(0, d, q)
				if bool(ap["ok"]) and not joined:
					joined = true
					events.append("day %3d (week %2d): hired as %s under %s" % [d, d / 7 + 1, sc.rank_title(), sc.patron["name"]])
				elif bool(ap["ok"]):
					events.append("day %3d (week %2d): hired again as %s" % [d, d / 7 + 1, sc.rank_title()])
			gold += sc.take_pending_gold()
		if sc.active:
			_workday(sc, d, base_acc, rng, mode, events)
			gold += sc.take_pending_gold()
			sc.gold_ref = maxi(gold, 0)
		if sc.rank != last_rank and sc.active:
			if last_rank >= 0:
				events.append("day %3d (week %2d): promoted to %s (scholarship %d, letters %d, patron regard %d)" % [d, d / 7 + 1, sc.rank_title(), sc.level(), int(sc.letters_rep()), int(sc.patron_regard())])
			last_rank = sc.rank
		elif sc.rank < last_rank:
			events.append("day %3d (week %2d): demoted to %s" % [d, d / 7 + 1, CareerLadders_title(sc)])
			last_rank = sc.rank
	for e: String in events:
		_p(e)
	_p("final: %s, scholarship %d, letters rep %d, gold earned %d, dismissals %d, jailed days %d, stats %s" % [sc.rank_title() if sc.active else "no post (%s)" % CareerLadders_title(sc), sc.level(), int(sc.letters_rep()), gold, sc.dismissals, jailed_days, JSON.stringify(sc.stats)])
	_p("")


func CareerLadders_title(sc: RefCounted) -> String:
	return String(sc.rank_title())


func _acc(base: float, level: int) -> float:
	return clampf(base + float(level) * 0.0015, 0.3, 0.99)


func _play_copy(sc: RefCounted, d: int, base_acc: float, rng: RandomNumberGenerator) -> float:
	var b: Dictionary = sc.begin("copy", d)
	if not bool(b["ok"]):
		return 0.0
	var acc := _acc(base_acc, sc.level())
	var picks: Array = []
	for l: Dictionary in sc.task["doc"]["lines"]:
		picks.append(int(l["correct"]) if rng.randf() < acc else (int(l["correct"]) + 1 + rng.randi() % 2) % 3)
	var steady := clampf(acc * 0.95 + rng.randf_range(-0.2, 0.08), 0.0, 1.0)
	var r: Dictionary = sc.submit_copy(picks, steady)
	return float(r["quality"])


## One day of work: what the next rank still needs decides what the scribe does, then piece work.
func _workday(sc: RefCounted, d: int, base_acc: float, rng: RandomNumberGenerator, mode: int, events: Array) -> void:
	var acc := _acc(base_acc, sc.level())
	var guard := 0
	while guard < 8 and sc.active:
		guard += 1
		var kind := _choose(sc, d, rng)
		if kind == "":
			break
		match kind:
			"copy":
				_play_copy(sc, d, base_acc, rng)
			"exam":
				var b: Dictionary = sc.begin("exam", d)
				if not bool(b["ok"]):
					break
				var ans: Array = []
				for q: Dictionary in sc.task["questions"]:
					ans.append(int(q["a"]) if rng.randf() < acc else (int(q["a"]) + 1) % 4)
				var r: Dictionary = sc.submit_exam(ans)
				events.append("day %3d: %s" % [d, r["text"]])
			"forgery":
				var b2: Dictionary = sc.begin("forgery", d)
				if not bool(b2["ok"]):
					break
				var seen: Array = []
				var lens := 1
				for ch: String in Data.CHANNELS:
					var use_lens := lens > 0 and seen.is_empty() and ch == "date"
					if use_lens:
						lens -= 1
					var ex: Dictionary = Data.examine(sc.task["doc"], ch, sc.level(), use_lens)
					if bool(ex["seen_flaw"]) and rng.randf() < acc:
						seen.append(ch)
				var verdict := "forged" if not seen.is_empty() else "genuine"
				var bribe := mode == 1 and int(sc.task["bribe"]) > 0 and rng.randf() < 0.7
				var r2: Dictionary = sc.submit_forgery("genuine" if bribe else verdict, [] if bribe else seen, bribe)
				if bribe:
					events.append("day %3d: took a bribe to pass a forgery" % d)
			"translate":
				var b3: Dictionary = sc.begin("translate", d)
				if not bool(b3["ok"]):
					break
				var guesses: Array = []
				for c: Dictionary in sc.task["text"]["choices"]:
					guesses.append(int(c["correct"]) if rng.randf() < 0.45 + 0.5 * acc else (int(c["correct"]) + 1) % 3)
				sc.submit_translation(guesses)
			"tax":
				var b4: Dictionary = sc.begin("tax", d)
				if not bool(b4["ok"]):
					break
				var marks: Array = []
				var rows: Array = sc.task["ledger"]["rows"]
				for i in rows.size():
					var bad: bool = String(rows[i]["err"]) != ""
					if (bad and rng.randf() < acc) or (not bad and rng.randf() < 0.05):
						marks.append(i)
				sc.submit_tax(marks)
			"study":
				sc.study_glyphs(d)
			"restricted":
				var r3: Dictionary = sc.read_restricted(d, mode == 1)
				if bool(r3.get("caught", false)):
					events.append("day %3d: caught in the sealed archive" % d)
				var s: Dictionary = r3.get("secret", {})
				if not s.is_empty():
					var act := "report"
					if mode == 2:
						act = "blackmail" if rng.randf() < 0.6 else "keep"
					elif mode == 1:
						act = "sell"
					var u: Dictionary = sc.use_secret(String(s["id"]), act, d)
					if bool(u.get("jailed", false)):
						events.append("day %3d: arrested for extortion" % d)
					elif act != "report" and int(u.get("gold", 0)) > 0:
						events.append("day %3d: %s paid %dg" % [d, act, int(u["gold"])])
			"audience":
				pass
		var jailed_msg := ""
		if sc.is_jailed(d):
			jailed_msg = "jailed"
		if jailed_msg != "":
			events.append("day %3d: in the cells until day %d (%s)" % [d, sc.jail_until, ""])
			break
	if sc.rank_id() == "steward" or sc.rank_id() == "envoy":
		if mode == 2 and not sc.estate.is_empty() and int(sc.estate["treasury"]) >= 60 and d % 14 == 0:
			sc.estate_skim(60)
	if sc.rank_id() == "envoy" and d % 7 == 3:
		var ms: Array = sc.missions(d)
		if not ms.is_empty():
			var m: Dictionary = ms[0]
			var fa: RefCounted = sc.hub.mod("factions")
			var want: Array = sc.wanted_tones(fa.relation("caldrenn", String(m["target"])), float(m["diff"]), hash([WorldSim.SEED, "env", String(m["id"])]))
			var tones: Array = want.map(func(t: String) -> String: return t if rng.randf() < acc else "press")
			var res: Dictionary = sc.run_mission(m, tones, d)
			if bool(res.get("ok", false)):
				events.append("day %3d: embassy to %s %s" % [d, String(m["target_name"]), res["outcome"]])


## What to do next: the next rank's missing counters first, exams when due, secrets when allowed, else copy.
func _choose(sc: RefCounted, d: int, rng: RandomNumberGenerator) -> String:
	var avail := {}
	for o: Dictionary in sc.offers(d):
		if bool(o["available"]):
			avail[String(o["kind"])] = true
	if avail.is_empty():
		return ""
	var nxt: Dictionary = sc.promotion_status(d)
	var missing: Array = Array(nxt.get("missing", PackedStringArray()))
	var want: Array = []
	for m: String in missing:
		if m.begins_with("Pass:") and avail.has("exam"):
			want.append("exam")
		elif m.begins_with("Forgeries caught") and avail.has("forgery"):
			want.append("forgery")
		elif m.begins_with("Tax audits") and avail.has("tax"):
			want.append("tax")
		elif m.begins_with("Translations") and avail.has("translate"):
			if int(sc.stats.get("translations", 0)) < 3 and sc.glyphs_known_list().size() < 6 and avail.has("study"):
				want.append("study")
			want.append("translate")
		elif m.begins_with("Restricted reads") and avail.has("restricted"):
			want.append("restricted")
		elif m.begins_with("Copies") and avail.has("copy"):
			want.append("copy")
	if not want.is_empty():
		return String(want[0]) if rng.randf() < 0.8 else _pick_other(avail, rng)
	if avail.has("restricted") and d % 4 == 0:
		return "restricted"
	return _pick_other(avail, rng)


func _pick_other(avail: Dictionary, rng: RandomNumberGenerator) -> String:
	var pool: Array = []
	for k in ["copy", "tax", "forgery", "translate"]:
		if avail.has(k):
			pool.append(k)
	return String(pool[rng.randi() % pool.size()]) if not pool.is_empty() else ""
