extends SceneTree
## CIV-C living-ecology chronicle (headless, no rendering): runs realm/ecology.gd for N game years and prints a readable
## log plus three acceptance checks:
##   A1  removing the apex predator of a zone causes a prey boom, then a (worse) predator moves in;
##   A2  a seasonal migration reaches a village zone (villagers see a species they had not seen);
##   A3  a goblin / orc clan makes a trade-or-raid decision that shows in the world (and its intent stays hidden until learned).
## Run:  godot --headless --path kingdom -s res://../docs/balance/data/eco_sim.gd -- years=15 seed=1066
## (copy this file to /tmp/claude-0/civc/ if the res:// path does not resolve.) One game year = 112 days (4 x 28).
const Eco := preload("res://scripts/realm/ecology.gd")
const Stl := preload("res://scripts/realm/settlements.gd")
const SEASONS := ["spring", "summer", "autumn", "winter"]
var done := false
var eco: RefCounted
var stl: RefCounted


func _season(day: int) -> String:
	return SEASONS[(posmod(day - 1, 112)) / 28]


func _stamp(day: int) -> String:
	return "Y%02d %-6s d%02d" % [(day - 1) / 112 + 1, _season(day), posmod(day - 1, 28) + 1]


func _process(_dt: float) -> bool:
	if done:
		return false
	done = true
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	run(int(args.get("years", "15")), int(args.get("seed", "1066")))
	OS.kill(OS.get_process_id())
	return true


func _zname(zi: int) -> String:
	return String(eco._zones[zi]["name"])


func run(years: int, seed_: int) -> void:
	WorldGen.setup(seed_)
	var hub: RefCounted = load("res://scripts/realm/realm_hub.gd").new()
	eco = hub.mod("ecology")
	stl = hub.mod("settlements")
	stl._ensure()
	eco._ensure()
	var t0 := Time.get_ticks_usec()
	var days := years * 112
	var kill_day := 112 + 20           # the player slays an apex in year 2 spring
	var kill_zone := -1
	var kill_sp := ""
	var prey_before := 0.0
	var boom_peak := 0.0
	var boom_day := -1
	var new_pred := ""
	var new_pred_day := -1
	var first_seen := {}
	var news_seen := 0
	var chron: Array = []
	var known_demo := []
	var worst_chunk := 0
	var worst_idx := -1
	var kinds := {}
	var stats := {}
	print("=== eco_sim: %d years (%d days), seed %d, %d zones, %d clans ===" % [years, days, seed_, eco.zone_count(), eco._factions.list.size()])
	for day in range(1, days + 1):
		var ctx := {"season": _season(day), "player_pos": Vector2.ZERO, "life": null}
		stl.tick_day(day, ctx)
		var chunks: Array = eco.tick_day_chunks(day, ctx)
		var ci := 0
		for c: Callable in chunks:
			var t1 := Time.get_ticks_usec()
			c.call()
			var dt := Time.get_ticks_usec() - t1
			stats[ci] = stats.get(ci, []) + [dt]
			if dt > worst_chunk:
				worst_chunk = dt
				worst_idx = ci
			ci += 1
		if day == kill_day:
			# Pick the apex zone where prey is most suppressed (the clearest before/after).
			var best := -1.0
			for zi in eco.zone_count():
				if eco.apex_count_z(zi) > 0.4 and float(eco._zones[zi]["wild"]) >= 0.35:
					var sup: float = 1.0 - float(eco._prey_idx(zi))
					if sup > best:
						best = sup
						kill_zone = zi
			if kill_zone >= 0 and best > 0.0:
				prey_before = eco._prey_idx(kill_zone)
				kill_sp = eco.kill_apex(int(eco._zones[kill_zone]["sid"]))
				chron.append([day, "%s  >> THE PLAYER slays the %s above %s (prey index %.2f)" % [_stamp(day), kill_sp, _zname(kill_zone), prey_before]])
		if day == 112 * 5 + 60:
			# Second act: the hunters of the wildest apex-free zone wipe out its wolves (wolves gone -> deer everywhere, and a worse
			# predator may spread into the hole).
			var bz := -1
			var bw := 0.0
			for zi in eco.zone_count():
				var nn: Array = eco._st[zi]["n"]
				if eco.apex_count_z(zi) < 0.4 and float(eco._zones[zi]["wild"]) >= 0.5 and float(nn[2]) > bw:
					bw = float(nn[2])
					bz = zi
			if bz >= 0:
				eco.hunt(int(eco._zones[bz]["sid"]), "wolf", 99.0)
				chron.append([day, "%s  >> THE HUNTERS wipe out the %.0f wolves around %s" % [_stamp(day), bw, _zname(bz)]])
		if kill_zone >= 0 and day > kill_day and (new_pred_day < 0 or day <= new_pred_day):
			var idx: float = eco._prey_idx(kill_zone)
			if idx > boom_peak:
				boom_peak = idx
				boom_day = day
		if day % 7 == 0:
			var ev: Array = eco.news_events(0, 1)
			for e: Dictionary in ev:
				if int(e["id"]) > news_seen:
					news_seen = int(e["id"])
					kinds[String(e["kind"])] = int(kinds.get(String(e["kind"]), 0)) + 1
					chron.append([int(e["day"]), "%s  [%s] %s" % [_stamp(int(e["day"])), e["kind"], e["text"]]])
					if String(e["kind"]) == "apex_arrival" and kill_zone >= 0 and int(e["zone"]) == kill_zone and int(e["day"]) > kill_day and new_pred_day < 0:
						new_pred = String(e["species"])
						new_pred_day = int(e["day"])
		if day == 40:
			# A scout reports on the first clan's intent (hidden until learned).
			var f0: Dictionary = eco.faction_view(0)
			known_demo.append("%s before scouting: intent=%s hint='%s'" % [f0["name"], f0["intent"], f0["hint"]])
			eco.learn_intent(0, 2)
			var f1: Dictionary = eco.faction_view(0)
			known_demo.append("%s after scouting:  intent=%s target=%s" % [f1["name"], f1["intent"], f1["target"]])
		if day % 112 == 0:
			var wolves := 0.0
			var apex := 0
			var prey := 0.0
			var adv := 0.0
			for zi in eco.zone_count():
				var n2: Array = eco._st[zi]["n"]
				wolves += float(n2[2]) + float(n2[3])
				apex += int(round(float(n2[4]) + float(n2[5]) + float(n2[6])))
				prey += eco._prey_idx(zi)
				adv += float(eco._st[zi]["adv"])
			chron.append([day, "%s  -- year end: predators %.0f, apex %d, mean prey index %.2f, adventurers %.0f" % [_stamp(day), wolves, apex, prey / eco.zone_count(), adv]])
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	print("\n--- chronicle ---")
	chron.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for line: Array in chron:
		print(line[1])
	print("\n--- clans (intent hidden unless learned) ---")
	for v: Dictionary in eco.factions():
		print("  %s: %s, %s, status %s, known=%d intent=%s, hint '%s'" % [v["name"], v["species"], v["size"], v["status"], v["known"], v["intent"], v["hint"]])
	for l in known_demo:
		print("  ", l)
	print("\n--- adventurer economy (top 4 by prosperity) ---")
	var rows: Array = []
	for zi in eco.zone_count():
		rows.append(eco.adventurer_economy(int(eco._zones[zi]["sid"])))
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["prosperity"]) > float(b["prosperity"]))
	for k in 4:
		var r: Dictionary = rows[k]
		print("  %s: adventurers %.1f danger %.0f prosperity %.2f inn %.1f bounty %.1f" % [eco.sname(int(r["sid"])), r["adventurers"], r["danger"], r["prosperity"], r["services"]["inn"], r["services"]["bounty_office"]])
	print("\n--- domestication (best per use) ---")
	var best_dom := {}
	for zi in eco.zone_count():
		var sid := int(eco._zones[zi]["sid"])
		var dm: Dictionary = eco.domestication(sid)
		for sp: String in dm:
			if float(dm[sp]["familiarity"]) > float(best_dom.get(sp, [0.0, ""])[0]):
				best_dom[sp] = [float(dm[sp]["familiarity"]), eco.sname(sid), dm[sp]["level"], dm[sp]["use"]]
	for sp: String in best_dom:
		print("  %s (%s): %.2f %s at %s" % [sp, best_dom[sp][3], best_dom[sp][0], best_dom[sp][2], best_dom[sp][1]])
	print("\n--- acceptance ---")
	var boom_ok := kill_zone >= 0 and boom_peak >= maxf(1.5 * prey_before, 0.55)
	print("A1 apex removal -> prey boom: zone %s, prey index %.2f -> peak %.2f (day %d): %s" % [_zname(kill_zone) if kill_zone >= 0 else "none", prey_before, boom_peak, boom_day, "PASS" if boom_ok else "FAIL"])
	print("A1 ... then a new predator: %s" % (("%s at %s (day %d): PASS" % [new_pred, _zname(kill_zone), new_pred_day]) if new_pred_day > 0 else "none: FAIL"))
	var mig := int(kinds.get("migration", 0)) + int(kinds.get("sighting", 0))
	print("A2 seasonal migration / new species in villages: %d events: %s" % [mig, "PASS" if mig > 0 else "FAIL"])
	var dec := int(kinds.get("monster_trade", 0)) + int(kinds.get("monster_raid", 0))
	print("A3 clan trade-or-raid decisions: trade %d, raid %d, parley %d, march %d, settled %d: %s" % [kinds.get("monster_trade", 0), kinds.get("monster_raid", 0), kinds.get("monster_parley", 0), kinds.get("monster_march", 0), kinds.get("monster_settled", 0), "PASS" if dec > 0 else "FAIL"])
	print("event kinds: ", kinds)
	for ci2: int in stats:
		var arr: Array = stats[ci2]
		arr.sort()
		print("  chunk #%d: n=%d median %d us p99 %d us max %d us" % [ci2, arr.size(), arr[arr.size() / 2], arr[int(arr.size() * 0.99)], arr[arr.size() - 1]])
	print("sim %.0f ms total (%.2f ms/day incl. settlements), worst ecology chunk %d us (#%d), save %d bytes" % [ms, ms / days, worst_chunk, worst_idx, JSON.stringify(eco.serialize()).length()])
