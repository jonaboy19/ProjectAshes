extends SceneTree
## Living-world integration sim: EVERY realm module together through realm_hub for 15 years (civilization, migration, governance, notables,
## news, ecology, settlements, camps, factions, ...), hour ticks + day chunks drained job by job so the per-job cost is the real pump cost.
## Prints a combined chronicle, a yearly stats table and the targets-vs-actuals checks used by docs/balance/CIVILIZATION_BALANCE.md.
## Run (from kingdom/):
##   godot --headless --path . -s res://../docs/balance/data/world15_sim.gd -- seeds=1066,2024 years=15 verbose=1 out=/tmp/claude-0/civint/world15.txt
## (or pass the absolute path after -s). Seeds are WorldGen seeds (WorldSim.SEED is a const, so module RNG streams are shared).
## A year here is 365 days (civilization's year); governance / notables count 360-day years internally.
const YEAR := 365
const CAP := "s1"   # Kingsreach, the capital (WorldGen id 1)
const SEASONS := ["spring", "summer", "autumn", "winter"]
const SOURCES := ["civilization", "migration", "governance", "notables", "ecology"]
## Kinds shown in the chronicle (verbose 1); everything else only counts.
const SHOW := ["founded", "ruin", "resettled", "boom", "tier_up", "tier_down", "depleted", "route_lost", "quarter", "refugees", "master_arrived",
	"succession", "revolt", "strike", "embassy", "founded_org", "expedition_lost", "crisis_failed", "apex_arrival", "apex_slain", "species_gone",
	"monster_settled", "monster_march", "monster_raid", "law"]
var done := false
var out_lines: Array = []
var verbose := 1
var _last_waves := 0
var _last_moved := 0
var show: Array = SHOW.duplicate()
var probe_sid := -1
var probe_from := 0
var probe_net := {}
var watch := ""
var watch_every := 30


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
	watch = String(args.get("watch", ""))
	probe_sid = int(args.get("probe", "-1"))
	probe_from = int(args.get("probe_from", "0"))
	for k in String(args.get("kinds", "")).split(","):
		if k != "":
			show.append(k)
	watch_every = int(args.get("every", "30"))
	var all_ok := true
	for sd in String(args.get("seeds", "1066,2024")).split(","):
		if not run(int(sd), years):
			all_ok = false
	var path := String(args.get("out", "/tmp/claude-0/civint/world15.txt"))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(out_lines) + "\n")
		f.close()
	OS.kill(OS.get_process_id())   # quit() can hang on leaked instances in headless -s runs
	return all_ok


func say(line: String) -> void:
	out_lines.append(line)
	print(line)


func stamp(day: int) -> String:
	return "Y%02d d%03d" % [(day - 1) / YEAR + 1, (day - 1) % YEAR]


func run(seed_value: int, years: int) -> bool:
	WorldGen.setup(seed_value)
	var hub: RefCounted = load("res://scripts/realm/realm_hub.gd").new()
	var rs: RefCounted = load("res://scripts/sim/runestone_network.gd").new()
	rs.call("seed_road_stones")
	var home: Dictionary = WorldGen.settlements[0]
	for i in 6:
		var ang := TAU * i / 6.0 + 0.3
		rs.call("add_stone", (home["pos"] as Vector2) + Vector2(cos(ang), sin(ang)) * (float(home["radius"]) + 18.0), float(home["radius"]) * 1.45, 0, "Ring %d" % i)
	var civ: RefCounted = hub.mod("civilization")
	var mig: RefCounted = hub.mod("migration")
	var gov: RefCounted = hub.mod("governance")
	var nw: RefCounted = hub.mod("news")
	var eco: RefCounted = hub.mod("ecology")
	var stl: RefCounted = hub.mod("settlements")
	civ.set("runestones", rs)
	hub.warm_up()
	say("=== world15: seed %d, %d years, %d static settlements, %d modules ===" % [seed_value, years, WorldGen.settlements.size(), hub.mods.size()])
	_last_waves = 0
	_last_moved = 0
	var cur := {}
	for s in SOURCES:
		cur[s] = 0
	var yr := {}          # per year counters: kind -> n
	var tot := {}         # whole run
	var rows: Array = []  # yearly table rows
	var lines: Array = []
	var cost_all := PackedInt32Array()
	var cost_max := {}
	var day_all := PackedInt32Array()
	var day_by := {}      # module -> day-tick job costs (each chunk is one pump job)
	var famine_seen := {}
	var famines := 0
	var cap_start := int(civ.call("population", CAP))
	var pop_start := _total(civ)
	var ctx := {"season": "spring", "at_war": false, "abs_hours": 0.0, "gold": 0, "player_pos": Vector2.ZERO, "life": null}
	var t_wall := Time.get_ticks_msec()
	var cur_mod := ""
	var species0 := _species(eco)
	var dyn_first := -1
	var dyn_founded_by_year: Array = []
	var ruined_dyn := 0
	var peak_cap := cap_start
	var cap_min := cap_start
	var revolts_y1 := 0
	for day in range(1, years * YEAR + 1):
		ctx["season"] = SEASONS[((day - 1) % YEAR) / 92 % 4]
		ctx["at_war"] = day > 6 * YEAR and day <= 8 * YEAR
		for h in 24:
			ctx["abs_hours"] = float(day) * 24.0 + h
			hub.on_hour(h, day, ctx)
			while not (hub.get("_queue") as Array).is_empty():
				var j: Array = (hub.get("_queue") as Array).pop_front()
				var named := String(j[0]) != ""
				var is_day := j[1] is Callable or String(j[1]) == "tick_day"
				if named:
					cur_mod = String(j[0])
				var pg := 0.0
				if probe_sid >= 0 and day > probe_from:
					pg = float((stl.call("stock", probe_sid) as Dictionary).get("grain", 0.0))
				var t0 := Time.get_ticks_usec()
				var msgs: Array = hub.call("_run_job", j)
				var dt := Time.get_ticks_usec() - t0
				cost_all.append(dt)
				if probe_sid >= 0 and day > probe_from:
					var dg := float((stl.call("stock", probe_sid) as Dictionary).get("grain", 0.0)) - pg
					probe_net[cur_mod] = float(probe_net.get(cur_mod, 0.0)) + dg
				if is_day:
					day_all.append(dt)
					var arr: PackedInt32Array = day_by.get(cur_mod, PackedInt32Array())
					arr.append(dt)
					day_by[cur_mod] = arr   # packed arrays copy on read: store it back
				cost_max[cur_mod] = maxi(int(cost_max.get(cur_mod, 0)), dt)
				for m: Variant in msgs:
					var ms := String(m)
					if ms.contains("running out of food"):
						var key := ms
						if not famine_seen.has(key) or day - int(famine_seen[key]) > 120:
							famines += 1
							lines.append("%s  [sett] %s" % [stamp(day), ms])
							yr["famine"] = int(yr.get("famine", 0)) + 1
						famine_seen[key] = day
		# events of the day
		for src: String in SOURCES:
			var m: RefCounted = hub.mod(src)
			var evs: Array = m.call("news_events", int(cur[src]))
			for e: Dictionary in evs:
				var sq := int(e["seq"])
				if sq <= int(cur[src]):
					continue
				cur[src] = sq
				var k := String(e["kind"])
				yr[src + ":" + k] = int(yr.get(src + ":" + k, 0)) + 1
				tot[src + ":" + k] = int(tot.get(src + ":" + k, 0)) + 1
				if k == "founded" and src == "civilization":
					yr["founded"] = int(yr.get("founded", 0)) + 1
					if dyn_first < 0:
						dyn_first = day
				if k == "ruin" and src == "civilization":
					yr["ruin"] = int(yr.get("ruin", 0)) + 1
					if bool((civ.call("place", String(e["node"])) as Dictionary).get("dyn", false)):
						ruined_dyn += 1
				if k == "wave" and src == "migration":
					var tx := String(e["text"])
					var cz := tx.substr(tx.rfind("(") + 1).trim_suffix(").") if tx.contains("(") else "outsiders"
					tot["cause:" + cz] = int(tot.get("cause:" + cz, 0)) + 1
				if k == "failed" and src == "civilization":
					yr["failed"] = int(yr.get("failed", 0)) + 1
				if k == "revolt" and day <= YEAR:
					revolts_y1 += 1
				if verbose >= 1 and show.has(k) and not (k == "tier_up" and src == "civilization" and int(tot.get("civilization:tier_up", 0)) % 3 != 0 and verbose < 2):
					lines.append("%s  [%s] %s" % [stamp(int(e["day"]) if int(e["day"]) > 0 else day), src.substr(0, 4), e["text"]])
		if watch != "" and day % watch_every == 0 and civ.call("has_place", watch):
			var w: Dictionary = civ.call("place", watch)
			var inp: Dictionary = civ.call("_inputs", w, day)
			say("  [watch %s %s] pop %d popf %.0f tier %d | S %.2f F %.2f J %.2f R %.2f H %.2f A %.2f ref %.2f | unrest %.2f mon %.2f war %.2f famine %.0f cut %.0f | Kf %.0f Kj %.0f housing %.0f fimp %.0f lead %.2f | push %.2f pull %.2f | shortage %s" % [
				watch, stamp(day), int(civ.call("population", watch)), float(w["popf"]), int(w["tier"]), float(w["S"]), float(w["F"]), float(w["J"]), float(w["R"]), float(w["H"]), float(w["attr"]),
				float(w["ref"]), float(w["unrest"]), float(w["monster"]), float(w["war"]), float(w["famine"]), float(w["cut"]), float(inp["Kf"]), float(inp["Kj"]), float(w["housing"]), float(w["fimp"]),
				float(w["lead"]), float(w["push"]), float(w["pull"]), JSON.stringify(stl.call("shortages", int(w["sid"])) if not bool(w["dyn"]) else {})])
			if not bool(w["dyn"]):
				var stk: Dictionary = stl.call("stock", int(w["sid"]))
				say("      stock grain %.0f flour %.0f bread %.0f fish %.0f | chains %s | need/day %.1f" % [float(stk.get("grain", 0)), float(stk.get("flour", 0)), float(stk.get("bread", 0)), float(stk.get("fish", 0)),
					JSON.stringify(stl.call("chains", int(w["sid"]))), float(stl.call("population", int(w["sid"]))) * 0.04])
		var cp := int(civ.call("population", CAP))
		cap_min = mini(cap_min, cp)
		peak_cap = maxi(peak_cap, cp)
		if day % YEAR == 0:
			rows.append(_year_row(day / YEAR, civ, mig, gov, nw, eco, yr))
			yr = {}
	# ---------------------------------------------------------------- report
	var wall := float(Time.get_ticks_msec() - t_wall) / 1000.0
	if probe_sid >= 0:
		say("grain probe at settlement %d after day %d: net change by module %s" % [probe_sid, probe_from, JSON.stringify(probe_net)])
	say("")
	say("--- chronicle (seed %d) ---" % seed_value)
	for l in lines:
		say(l)
	say("")
	say("--- yearly stats (seed %d) ---" % seed_value)
	say("species order: " + str(_species(eco).keys()))
	say("yr | dyn alive/founded/ruin | Kingsreach | realm pop | famine | waves moved | quarters | succ law deleg emb revolt strike | orgs | apex sp_min")
	for r: String in rows:
		say(r)
	say("")
	say("--- dynamic camps (seed %d) ---" % seed_value)
	for node in civ.call("place_ids"):
		var pp: Dictionary = civ.call("place", String(node))
		if bool(pp["dyn"]):
			say("%-12s founded %s  pop %4d (peak %4d)  %-9s %s%s" % [pp["name"], stamp(int(pp["founded"])), int(civ.call("population", String(node))), int(pp["peak"]),
				civ.call("tier_name", String(node)), "RUIN day %s  " % stamp(int(pp["ruin_day"])) if bool(pp["ruin"]) else "", ""])
	say("--- largest static places: ---")
	var big: Array = []
	for node in civ.call("place_ids"):
		var pq: Dictionary = civ.call("place", String(node))
		if not bool(pq["dyn"]):
			big.append("%s %d->%d" % [pq["name"], int(pq["pop_seed"]), int(civ.call("population", String(node)))])
	say(", ".join(big))
	var st: Dictionary = mig.call("stats")
	var dyn_alive := int(civ.call("dynamic_count"))
	var founded := int(tot.get("civilization:founded", 0))
	var quarters := _quarters(mig, civ)
	var succ := int(tot.get("governance:succession", 0))
	var inst_n := (gov.call("institutions") as Array).size()
	var laws := int(tot.get("governance:law", 0))
	var revolts := int(tot.get("governance:revolt", 0))
	var dip: Dictionary = nw.call("stats")["dip_total"]
	var emb := (nw.call("embassies") as Array).size()
	var deleg := int(dip.get("delegation", 0))
	var save_bytes := JSON.stringify(hub.call("serialize")).length()
	var sp1 := _species(eco)
	var extinct: Array = []
	for k: String in sp1:
		if float(sp1[k]) < 0.5 and float(species0.get(k, 0.0)) >= 0.5:
			extinct.append(k)
	var med_all := _pct(day_all, 0.5)
	var worst_med := 0
	var worst_med_mod := ""
	for k: String in day_by:
		var md := _pct(day_by[k], 0.5)
		if md > worst_med:
			worst_med = md
			worst_med_mod = k
	say("")
	say("--- pump job cost, us: median / p99 / max  (day-tick chunks per module; hour ticks all modules: median %d p99 %d max %d) ---" % [_pct(cost_all, 0.5), _pct(cost_all, 0.99), _pct(cost_all, 1.0)])
	var ks: Array = day_by.keys()
	ks.sort()
	var line := ""
	for k: String in ks:
		line += "%s %d/%d/%d   " % [k, _pct(day_by[k], 0.5), _pct(day_by[k], 0.99), int(cost_max[k])]
	say(line)
	var kr_end := int(civ.call("population", CAP))
	var res := {
		"founded_total": founded, "dyn_alive": dyn_alive, "ruined_dyn": ruined_dyn, "first_found_day": dyn_first,
		"kingsreach": "%d -> %d (peak %d, min %d)" % [cap_start, kr_end, peak_cap, cap_min], "famines": famines,
		"waves": int(st["waves"]), "quarters": quarters, "succ": succ, "institutions": inst_n, "laws": laws, "deleg": deleg, "emb": emb, "revolts": revolts,
		"revolts_y1": revolts_y1, "extinct": extinct, "save_bytes": save_bytes, "med_us": med_all, "worst_med_us": worst_med, "worst_med_mod": worst_med_mod, "wall_s": wall}
	say("")
	say("--- results (seed %d) ---" % seed_value)
	say(JSON.stringify(res))
	var by_year_founded: Array = []
	for r2: String in rows:
		by_year_founded.append(int(r2.split("|")[1].strip_edges().split("/")[1]))
	var causes := {}
	for k: String in tot:
		if k.begins_with("cause:"):
			causes[k.substr(6)] = tot[k]
	say("wave causes: " + JSON.stringify(causes) + "  failed camps: " + str(int(tot.get("civilization:failed", 0))))
	say("founded per year: %s   pop total %d -> %d   waves/yr %.1f" % [by_year_founded, pop_start, _total(civ), float(st["waves"]) / float(years)])
	var ok := founded >= 6 and kr_end >= cap_start * 0.95 and famines <= 2 and revolts_y1 == 0 and revolts <= 2 and extinct.is_empty() and save_bytes < 1000000 and worst_med < 600
	say("WORLD15 seed %d: %s" % [seed_value, "PASS" if ok else "FAIL"])
	return ok


func _quarters(mig: RefCounted, civ: RefCounted) -> int:
	var n := 0
	for node in civ.call("place_ids"):
		n += (mig.call("quarters", String(node)) as Array).size()
	return n


func _total(civ: RefCounted) -> int:
	var t := 0
	for node in civ.call("place_ids"):
		t += int(civ.call("population", String(node)))
	return t


func _species(eco: RefCounted) -> Dictionary:
	var out := {}
	for s in WorldGen.settlements:
		var pops: Dictionary = eco.call("populations", int(s["id"]))
		for k: String in pops:
			out[k] = float(out.get(k, 0.0)) + float(pops[k])
	return out


func _pct(a: PackedInt32Array, q: float) -> int:
	if a.is_empty():
		return 0
	var b := a.duplicate()
	b.sort()
	return int(b[mini(b.size() - 1, int(float(b.size()) * q))])


func _year_row(y: int, civ: RefCounted, mig: RefCounted, gov: RefCounted, nw: RefCounted, eco: RefCounted, yr: Dictionary) -> String:
	var st: Dictionary = mig.call("stats")
	var sp := _species(eco)
	var mn := INF
	var apex := 0.0
	for k: String in sp:
		mn = minf(mn, float(sp[k]))
		if k in ["troll", "wyvern", "bear"]:
			apex += float(sp[k])
	var dip: Dictionary = nw.call("stats")["dip_total"]
	var q := _quarters(mig, civ)
	var dw := int(st["waves"]) - _last_waves
	var dm := int(st["moved"]) - _last_moved
	_last_waves = int(st["waves"])
	_last_moved = int(st["moved"])
	var spl: Array = []
	for k: String in sp:
		spl.append(int(round(float(sp[k]))))
	return "%2d | %d/%d/%d | %4d | %5d | %d | %d %d | %d | %d %d %d %d %d %d | %d | %d %.0f" % [y, int(civ.call("dynamic_count")), int(yr.get("founded", 0)), int(yr.get("ruin", 0)),
		int(civ.call("population", CAP)), _total(civ), int(yr.get("famine", 0)), dw, dm, q, int(yr.get("governance:succession", 0)),
		int(yr.get("governance:law", 0)), int(dip.get("delegation", 0)), (nw.call("embassies") as Array).size(), int(yr.get("governance:revolt", 0)), int(yr.get("governance:strike", 0)),
		int(yr.get("notables:founded_org", 0)), int(apex), mn] + " | sp " + str(spl)
