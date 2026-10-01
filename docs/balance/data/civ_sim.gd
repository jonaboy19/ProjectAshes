extends SceneTree
## CIV-A headless 15-year civilization sim (docs/design/CIVILIZATION.md acceptance), progression_sim.gd style: no world, no player.
## It ticks only the modules civilization depends on (settlements, camps, civilization, migration, construction), day by day, and prints
## a readable chronicle (tier changes, booms, routes lost, waves, refugees, quarters, masters, ruins) and the acceptance checks:
##   1. a frontier camp with iron and a runestone extension grows to a town
##   2. a cut-off mining town shrinks
##   3. at least one migration wave
## Run:   godot --headless --path kingdom -s res://../docs/balance/data/civ_sim.gd -- years=15 verbose=1 out=/tmp/claude-0/civa/chronicle.txt
## (copy this file to /tmp/claude-0/civa/ if the res:// path does not resolve). Autoloads are fetched at runtime, never named.
const SEASONS := ["spring", "summer", "autumn", "winter"]
var done := false
var hub: RefCounted
var civ: RefCounted
var mig: RefCounted
var out_lines: Array = []
var verbose := 1
var seen_civ := 0
var seen_mig := 0
var job_max := {}
var dump_days: Array = []
var slow: Array = []
var chunk_us: Array = []
var mig_us: Array = []
var wave_causes := {}
var wave_people := {}


func _process(_dt: float) -> bool:
	if done:
		return false
	done = true
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	var years := int(args.get("years", "15"))
	verbose = int(args.get("verbose", "1"))
	for d in String(args.get("dump", "")).split(","):
		if d.is_valid_int():
			dump_days.append(int(d))
	var ok := run(years)
	var path := String(args.get("out", "/tmp/claude-0/civa/chronicle.txt"))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(out_lines) + "\n")
		f.close()
	OS.kill(OS.get_process_id())   # quit() can hang on leaked instances in headless -s runs
	return ok


func say(line: String) -> void:
	out_lines.append(line)
	print(line)


func stamp(day: int) -> String:
	return "Y%02d D%03d" % [day / 365 + 1, day % 365]


func run(years: int) -> bool:
	var ws: Node = root.get_node("WorldSim")
	WorldGen.setup(int(ws.get("SEED")))
	hub = load("res://scripts/realm/realm_hub.gd").new()
	civ = hub.mod("civilization")
	mig = hub.mod("migration")
	var rs: RefCounted = load("res://scripts/sim/runestone_network.gd").new()
	rs.call("seed_road_stones")
	# Ashford's ring of stones, as Frontier seeds it
	var home: Dictionary = WorldGen.settlements[0]
	for i in 6:
		var ang := TAU * i / 6.0 + 0.3
		rs.call("add_stone", (home["pos"] as Vector2) + Vector2(cos(ang), sin(ang)) * (float(home["radius"]) + 18.0), float(home["radius"]) * 1.45, 0, "Ring %d" % i)
	civ.set("prof_on", true)
	civ.set("runestones", rs)   # before warm_up: static places calibrate their patrols against this network
	hub.warm_up()
	civ.call("_ensure")
	say("=== CIV-A civilization sim: %d years, %d static settlements ===" % [years, WorldGen.settlements.size()])
	# --- scenario -----------------------------------------------------------------------------------------------
	var camp := ""
	var at_a: Vector2 = WorldGen.settlements[0]["pos"]
	var at_b: Vector2 = WorldGen.settlements[8]["pos"]
	for t in [0.5, 0.45, 0.55, 0.4, 0.6, 0.35]:
		for lat in [70.0, -70.0, 120.0, -120.0]:
			if camp == "":
				var dir := (at_b - at_a).normalized()
				camp = civ.call("found_place", at_a.lerp(at_b, t) + dir.orthogonal() * lat, "Ironwatch", "a prospector and her crew", 0, 12)
	if camp == "":
		say("could not found the frontier camp")
		return false
	# Iron is found within the first month; the road stones thin out on this frontier road, so the town must extend the line itself.
	var mine_town := ""
	var stl: RefCounted = hub.mod("settlements")
	for node in civ.call("place_ids"):
		var p: Dictionary = civ.call("place", String(node))
		if not bool(p["dyn"]) and not (p["res"] as Array).is_empty() and String(node) != "s0":
			mine_town = String(node)
			break
	if mine_town != "":
		(civ.get("no_finds") as Dictionary)[mine_town] = true   # scenario control: nothing rescues the cut-off town
	var pop0_camp := int(civ.call("population", camp))
	var pop0_mine := int(civ.call("population", mine_town)) if mine_town != "" else 0
	say("Frontier camp %s founded (pop %d). Cut-off test town: %s (pop %d, mine %d workers)." % [civ.call("name_of", camp), pop0_camp, civ.call("name_of", mine_town) if mine_town != "" else "-", pop0_mine,
		int((civ.call("place", mine_town)["res"][0] as Dictionary)["wcap"]) if mine_town != "" else 0])
	var tiers0 := {}
	for node in civ.call("place_ids"):
		tiers0[String(node)] = int(civ.call("tier", String(node)))
	var peak := {}
	var pop_start := {}
	var t_start := Time.get_ticks_msec()
	var days := years * 365
	for day in range(1, days + 1):
		if day == 30:
			civ.call("discover", camp, "iron", 0.85, day)
		if day == 60 and mine_town != "":
			var n: int = civ.call("isolate", mine_town, 99999)
			say("%s  The roads to %s are cut (%d); nobody repairs them." % [stamp(day), civ.call("name_of", mine_town), n])
		var at_war := day >= 6 * 365 and day < 8 * 365
		tick(day, {"season": SEASONS[(day % 365) / 92 % 4], "at_war": at_war, "abs_hours": day * 24 + 6, "gold": 0, "player_pos": Vector3.ZERO, "life": null}, rs)
		for ev in civ.call("news_events"):
			if int(ev["id"]) > seen_civ:
				seen_civ = int(ev["id"])
				if verbose >= 1 and String(ev["kind"]) in ["tier_up", "tier_down", "boom", "founded", "ruin", "route_lost", "depleted", "resettled"] or (verbose >= 2):
					say("%s  %s" % [stamp(int(ev["day"])), ev["text"]])
		for ev in mig.call("news_events"):
			if int(ev["id"]) > seen_mig:
				seen_mig = int(ev["id"])
				if String(ev["kind"]) == "wave":
					var txt := String(ev["text"])
					var cause := txt.substr(txt.rfind("(") + 1).trim_suffix(").") if txt.contains("(") else "?"
					wave_causes[cause] = int(wave_causes.get(cause, 0)) + 1
					wave_people[cause] = int(wave_people.get(cause, 0)) + int(txt.split(" ")[3])
				if verbose >= 1 and String(ev["kind"]) in ["refugees", "quarter", "master_arrived", "master_left", "tradition"] or (verbose >= 2 and String(ev["kind"]) != "arrival") or (verbose >= 3):
					say("%s  %s" % [stamp(int(ev["day"])), ev["text"]])
				elif verbose >= 1 and String(ev["kind"]) == "wave" and int(ev["id"]) % 4 == 0:
					say("%s  %s" % [stamp(int(ev["day"])), ev["text"]])
		if verbose >= 4 and day % 60 == 0 and day <= 730:
			var w: Dictionary = civ.call("place", camp if verbose != 5 or mine_town == "" else mine_town)
			var inp: Dictionary = civ.call("_inputs", w, day)
			var prs: Array = []
			for pr in civ.call("projects", camp):
				prs.append("%s:%s" % [pr["kind"], String(pr["state"]).substr(0, 1)])
			say("  [%s d%d cut %.0f R %.2f popreal %d] pop %.1f tier %d housing %.0f Kf %.0f Kj %.0f farms %d jobs_x %.0f S %.2f A %.2f ref %.2f $%d refugees %d push %.2f proj %s" % [w["name"], day, float(w["cut"]), float(w["R"]), int(civ.call("population", String(w["node"]))), float(w["popf"]), int(w["tier"]), float(w["housing"]), float(inp["Kf"]), float(inp["Kj"]), int(w["farms"]), float(w["jobs_x"]), float(w["S"]), float(w["attr"]), float(w["ref"]), int(w["treasury"]), int(w["refugees"]), float(w["push"]), ",".join(prs)])
		if dump_days.has(day):
			say("--- dump day %d: place tier pop  S F J R H attr ref unrest crime push pull treasury ---" % day)
			for node in civ.call("place_ids"):
				var q: Dictionary = civ.call("place", String(node))
				say("%-12s t%d %5d  S%.2f F%.2f J%.2f R%.2f H%.2f A%.2f ref%.2f un%.2f cr%.2f push%.2f pull%.2f $%d cov%.2f pat%.2f wall%d mon%.2f war%.2f" % [q["name"], int(q["tier"]), int(civ.call("population", String(node))), float(q["S"]), float(q["F"]), float(q["J"]), float(q["R"]), float(q["H"]), float(q["attr"]), float(q["ref"]), float(q["unrest"]), float(q["crime"]), float(q["push"]), float(q["pull"]), int(q["treasury"]), float(civ.call("_coverage", civ.call("pos_of", String(node)))), float(q["patrol"]), int(q["walls"]), float(q["monster"]), float(q["war"])])
		if day % 365 == 0:
			var tot := 0
			for node in civ.call("place_ids"):
				tot += int(civ.call("population", String(node)))
			say("%s  -- year end: camp %s pop %d (%s), mine town pop %d, total %d, dynamic places %d, waves in flight %d --" % [stamp(day), civ.call("name_of", camp), int(civ.call("population", camp)),
				civ.call("tier_name", camp), int(civ.call("population", mine_town)) if mine_town != "" else 0, tot, int(civ.call("dynamic_count")), (mig.call("active_waves") as Array).size()])
		for node in civ.call("place_ids"):
			peak[String(node)] = maxi(int(peak.get(String(node), 0)), int(civ.call("population", String(node))))
			if not pop_start.has(String(node)):
				pop_start[String(node)] = int(civ.call("population", String(node)))
	say("")
	say("=== after %d years (%.1f s wall) ===" % [years, float(Time.get_ticks_msec() - t_start) / 1000.0])
	say("%-14s %-9s %6s -> %6s  %-10s  %s" % ["place", "kind", "pop0", "pop", "tier", "note"])
	for node in civ.call("place_ids"):
		var p2: Dictionary = civ.call("place", String(node))
		var nd := String(node)
		var note := ""
		if bool(p2["dyn"]):
			note = "founded %s by %s" % [stamp(int(p2["founded"])), p2["founder"]]
		if bool(p2["ruin"]):
			note += " RUIN"
		var dep: Array = p2["res"]
		if not dep.is_empty():
			var d0: Dictionary = dep[0]
			note += "  %s %d%% left" % [d0["kind"], int(100.0 * float(d0["reserve"]) / maxf(1.0, float(d0["reserve0"])))]
		say("%-14s %-9s %6d -> %6d  %-10s  %s" % [p2["name"], "dynamic" if bool(p2["dyn"]) else WorldGen.settlements[int(p2["sid"])]["kind"], int(pop_start.get(nd, 0)),
			int(civ.call("population", nd)), civ.call("tier_name", nd), note])
	var camp_tier := int(civ.call("tier", camp))
	var mine_pop := int(civ.call("population", mine_town)) if mine_town != "" else 0
	var st: Dictionary = mig.call("stats")
	say("")
	say("migration: %d waves sent, %d people moved in, %d became refugees; %d masters; %d refugee camps now" % [int(st["waves"]), int(st["moved"]), int(st["refugees"]), (mig.call("specialists") as Array).size(), (mig.call("refugee_camps") as Array).size()])
	say("frontier camp %s: pop %d -> %d, tier %s (peak %d)" % [civ.call("name_of", camp), pop0_camp, int(civ.call("population", camp)), civ.call("tier_name", camp), int(peak.get(camp, 0))])
	say("cut-off %s: pop %d -> %d (peak %d)" % [civ.call("name_of", mine_town), pop0_mine, mine_pop, int(peak.get(mine_town, 0))])
	say("waves by cause: %s   people: %s" % [JSON.stringify(wave_causes), JSON.stringify(wave_people)])
	for pair in [["civilization", chunk_us], ["migration", mig_us]]:
		var arr: Array = pair[1]
		arr.sort()
		if not arr.is_empty():
			say("%s chunk cost us: median %d  p99 %d  p99.9 %d  max %d  (%d chunks)" % [pair[0], arr[arr.size() / 2], arr[int(arr.size() * 0.99)], arr[int(arr.size() * 0.999)], arr[-1], arr.size()])
	slow.sort_custom(func(a: String, b: String) -> bool: return int(a.split(": ")[1]) > int(b.split(": ")[1]))
	say("slow chunks (>1.5 ms): %d; worst: %s" % [slow.size(), "; ".join(slow.slice(0, 8))])
	for k in (civ.get("prof") as Dictionary).keys():
		var e: Array = civ.get("prof")[k]
		say("  profile civ %-12s %7d calls  %6.1f us/call  %7.2f s total" % [k, int(e[0]), float(e[1]) / maxf(1.0, float(e[0])), float(e[1]) / 1e6])
	say("cost (max single chunk, us): " + JSON.stringify(job_max))
	say("civ+mig save size: %d bytes" % (JSON.stringify(civ.call("serialize")).length() + JSON.stringify(mig.call("serialize")).length()))
	var pass1 := camp_tier >= 3
	var pass2 := mine_town != "" and mine_pop < int(0.85 * float(pop0_mine))
	var pass3 := int(st["waves"]) >= 1
	say("ACCEPT frontier camp -> town:   %s" % ("PASS" if pass1 else "FAIL"))
	say("ACCEPT cut-off mining shrinks:  %s" % ("PASS" if pass2 else "FAIL"))
	say("ACCEPT at least one wave:       %s" % ("PASS" if pass3 else "FAIL"))
	return pass1 and pass2 and pass3


## One game day of the modules this sim needs (06:00 day ticks run through their chunks so the cost is the real per-job cost).
func tick(day: int, ctx: Dictionary, rs: RefCounted) -> void:
	rs.call("tick_day", day)
	var stl: RefCounted = hub.mod("settlements")
	var cm: RefCounted = hub.mod("camps")
	for h in 24:
		stl.call("tick_hour", h, ctx)
	cm.call("tick_day", day, ctx)
	for k in ["settlements", "civilization", "migration", "construction"]:
		var m: RefCounted = hub.mod(k)
		var chunks: Array = m.call("tick_day_chunks", day, ctx)
		if chunks.is_empty():
			var t0 := Time.get_ticks_usec()
			m.call("tick_day", day, ctx)
			job_max[k] = maxi(int(job_max.get(k, 0)), Time.get_ticks_usec() - t0)
		else:
			var ci := 0
			for c: Callable in chunks:
				var t1 := Time.get_ticks_usec()
				c.call()
				var dt := Time.get_ticks_usec() - t1
				job_max[k] = maxi(int(job_max.get(k, 0)), dt)
				if k == "civilization":
					chunk_us.append(dt)
				elif k == "migration":
					mig_us.append(dt)
				if dt > 1500:
					slow.append("%s day %d chunk %d/%d: %d us" % [k, day, ci, chunks.size(), dt])
				ci += 1
