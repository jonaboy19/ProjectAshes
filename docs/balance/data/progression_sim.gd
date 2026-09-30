extends SceneTree
## Progression / cultivation balance sim (headless, no world): 3 archetypes play N real hours.
## Run:  godot --headless --path kingdom -s res://../docs/balance/data/progression_sim.gd -- hours=150 seeds=5
## (copy this file to /tmp/claude-0/cultivation/ if the res:// path does not resolve)
## Model: 1 game day = 12 real minutes (WorldSim.DAY_LENGTH 720 s). A real minute spent on an activity yields
## its rate of events; finite content (quests, discoveries) is taken in level order; repeatable content decays.
const Cult := preload("res://scripts/realm/cultivation.gd")
const Prog := preload("res://scripts/sim/progression.gd")
const DAY_MIN := 12.0
# activity -> events per real minute
const RATE := {"kill": 0.8, "discovery": 0.12, "quest": 0.07, "job": 0.25, "craft": 2.0, "train": 0.5, "gather": 2.0, "build": 0.06}
# archetype -> {path, minutes share per activity, med hours per day, location list, trials}
const ARCH := {
	"brawler": {"path": "knight", "mix": {"kill": 0.55, "train": 0.12, "quest": 0.14, "discovery": 0.08, "job": 0.05, "gather": 0.03, "craft": 0.03},
		"med": 2.0, "trial": false},
	"explorer": {"path": "magic", "mix": {"discovery": 0.30, "quest": 0.30, "kill": 0.14, "craft": 0.10, "gather": 0.10, "build": 0.03, "job": 0.03},
		"med": 4.0, "trial": false},
	"cultivator": {"path": "sect", "mix": {"quest": 0.25, "kill": 0.25, "discovery": 0.20, "train": 0.12, "gather": 0.10, "craft": 0.05, "job": 0.03},
		"med": 8.0, "trial": true},
}
var done := false


func _process(_dt: float) -> bool:
	if done:
		return false
	done = true
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	var hours := int(args.get("hours", "160"))
	var seeds := int(args.get("seeds", "3"))
	var only := String(args.get("arch", ""))
	for name: String in ARCH:
		if only != "" and only != name:
			continue
		var sums := {}
		for sd in seeds:
			var r := run(name, hours, 1000 + sd * 17)
			for k: String in r:
				if not sums.has(k):
					sums[k] = []
				(sums[k] as Array).append(r[k])
		print("=== %s (%s), %d seeds, %d h ===" % [name, ARCH[name]["path"], seeds, hours])
		for k: String in sums:
			var arr: Array = sums[k]
			var mn: float = arr.min()
			var mx: float = arr.max()
			print("  %-24s min %8.1f  max %8.1f" % [k, mn, mx])
	OS.kill(OS.get_process_id())   # quit() can hang on leaked instances in headless -s runs
	return true


func run(name: String, hours: int, seed_: int) -> Dictionary:
	var A: Dictionary = ARCH[name]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var eff := rng.randf_range(0.85, 1.15)       # player efficiency
	var c: RefCounted = Cult.new()
	c.reseed(seed_)
	var prog: RefCounted = c.prog
	var path: String = A["path"]
	c.begin(path, "academy")
	c.set_flag("sect_access", false)
	# finite content pools: levels spread over 1..56
	var quests: Array = []
	for i in 45:
		quests.append(1 + int(round(float(i) * 55.0 / 44.0)))
	var discos: Array = []
	for i in 160:
		discos.append(1 + int(round(float(i) * 56.0 / 159.0)))
	var qi_ := 0
	var di_ := 0
	var carry := {}
	var marks := {}
	var minutes_total := 0.0
	var day := 1
	var next_mark := [10, 30, 50, 55]
	var att := 0
	var kills := 0
	var crafts := 0
	var med_eff := 0.0
	var res_uses := 0
	var succ := 0
	var out := {}
	var cult_at := {}
	var minute_budget := float(hours) * 60.0
	var herb := 0.0
	var core := 0.0
	var pill := 0.0
	while minutes_total < minute_budget:
		# ---- this game day
		var lvl: int = prog.level
		if lvl >= 8 and path == "sect":
			c.set_flag("sect_access", true)
		if lvl >= 15:
			c.set_flag("vale_found", true)
		if lvl >= 38:
			c.set_flag("rift_seen", true)
		var med_h: float = A["med"]
		var day_min := DAY_MIN - 0.25 * med_h
		minutes_total += day_min
		var region := "region1"
		var mix: Dictionary = A["mix"]
		for act: String in mix:
			var n_f: float = float(RATE[act.replace("job", "job")]) * day_min * float(mix[act]) * eff + float(carry.get(act, 0.0))
			var n := int(n_f)
			carry[act] = n_f - n
			for i in n:
				lvl = prog.level
				var cl := mini(lvl + 2, 58)
				match act:
					"kill":
						var sp := "sp%d" % (i % 4)
						kills += 1
						var elite := kills % 20 == 0
						prog.award("kill", {"subject": sp, "content_level": cl, "magnitude": 4.0 if elite else 1.0, "day": day, "region": region})
						if elite:
							core += 0.25
					"discovery":
						var pick := -1
						if di_ < discos.size() and int(discos[di_]) <= lvl + 4:
							pick = di_
							di_ += 1
						if pick >= 0:
							prog.award("discovery", {"id": "d%d" % pick, "content_level": int(discos[pick]), "day": day})
							c.add_insight(1.0, "discovery", "d%d" % pick)
						else:
							prog.award("kill", {"subject": "sp%d" % (i % 4), "content_level": cl, "day": day})   # nothing to find: walk and fight
					"quest":
						if qi_ < quests.size() and int(quests[qi_]) <= lvl + 4:
							prog.award("quest", {"id": "q%d" % qi_, "content_level": int(quests[qi_]), "day": day})
							c.add_insight(1.0, "quest", "q%d" % qi_)
							qi_ += 1
						else:
							prog.award("quest", {"subject": "radiant", "content_level": cl, "day": day, "magnitude": 0.5})
					"job":
						prog.award("job_shift", {"subject": "job%d" % (i % 2), "content_level": mini(lvl, 20), "day": day})
					"craft":
						prog.award("craft", {"subject": "r%d" % (i % 6), "content_level": cl, "day": day})
						crafts += 1
						if crafts % 25 == 0:
							pill += 1.0
					"train":
						prog.award("train", {"subject": "t%d" % (i % 2), "content_level": cl, "day": day})
					"gather":
						prog.award("gather", {"subject": "g%d" % (i % 3), "content_level": cl, "day": day})
						herb += 0.12
					"build":
						prog.award("build", {"subject": "b%d" % (i % 3), "content_level": cl, "day": day})
		# resources -> stock
		var g := clampi(1 + int(prog.level / 25), 1, 3)
		var hb := int(herb)
		if hb > 0:
			c.add_resource("herb", g, hb)
			herb -= hb
		var cr := int(core)
		if cr > 0:
			c.add_resource("core", g, cr)
			core -= cr
		var pl := int(pill)
		if pl > 0:
			c.add_resource("pill", g, pl)
			pill -= pl
		# ---- cultivation
		var loc := "wilds"
		var best := 0.0
		for l: String in c.open_locations():
			var d: float = c.density(l, path) - (0.6 if float(Cult.location(l).get("risk", 0.0)) > 0.1 else 0.0)
			if d > best:
				best = d
				loc = l
		c.tick_day(day, {})
		if A["trial"] and day % 3 == 0:
			c.add_insight(1.0, "teacher")      # a master's lesson every third day (cultivator archetype)
		var left := med_h
		while left > 0.0:
			var h := minf(4.0, left)
			var mr: Dictionary = c.meditate(path, h, loc, {"day": day})
			med_eff += float(mr.get("eff_hours", 0.0)) * c.density(loc, path)
			left -= h
		# use resources on the current stage (herbs + cores; keep catalysts)
		var sm: Dictionary = c.track(path)
		for k: Dictionary in c.stock_list():
			if float(sm["qi"]) >= 0.85:
				break
			var keep := 0
			if k["kind"] == "pill":
				keep = 0
			if int(k["n"]) > keep and int(k["grade"]) >= 1:
				if c.breakthrough_info(path, {"day": day})["major"] and (k["kind"] == "core" or k["kind"] == "herb"):
					var need := 0
					for cat: Dictionary in c.catalyst_needed(path):
						if cat["kind"] == k["kind"] and int(cat["grade"]) <= int(k["grade"]):
							need += int(cat["n"])
					if int(k["n"]) <= need:
						continue
				c.use_resource(path, String(k["kind"]), int(k["grade"]), {"day": day})
				res_uses += 1
		# attempts
		for t in 3:
			var info: Dictionary = c.breakthrough_info(path, {"day": day, "loc": loc})
			if not bool(info["ok"]):
				break
			var opts := {"day": day, "loc": loc, "master": prog.level >= 20}
			if A["trial"] and bool(info["major"]):
				opts["score"] = 0.65
			att += 1
			var r: Dictionary = c.attempt_breakthrough(path, opts)
			if bool(r["success"]):
				succ += 1
			else:
				break
		day += 1
		# marks
		while not next_mark.is_empty() and prog.level >= int(next_mark[0]):
			var lv: int = next_mark.pop_front()
			out["h_level_%d" % lv] = minutes_total / 60.0
			out["cult_pos_at_%d" % lv] = c.position(path)
			out["realm_at_%d" % lv] = c.realm_of(path)
	out["level_end"] = prog.level
	out["cult_pos_end"] = c.position(path)
	out["realm_end"] = c.realm_of(path)
	out["game_days"] = day
	out["bt_success_rate_pct"] = 100.0 * float(succ) / maxf(1.0, float(att))
	out["med_eff_density_hours"] = med_eff
	out["resource_uses"] = res_uses
	out["quests_done"] = qi_
	out["discoveries"] = di_
	return out
