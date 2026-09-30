extends SceneTree
## CIV-B chronicle: a 15-year headless run of government, notables and news, printing what happened.
## Run (from kingdom/):
##   godot --headless --path . -s /home/user/ProjectAshes/docs/balance/data/gov_sim.gd -- years=15 seed=2024 verbose=1
## Day ticks only (no player): settlements, factions, city_life, society, governance, notables, news, exploration, education.
## Acceptance printed at the end: a leader succession, an NPC-founded organisation, a lost expedition, a social title.
const RUN := ["settlements", "factions", "city_life", "society", "governance", "notables", "news", "exploration", "education"]
const SHOW := ["succession", "founded_org", "org_failed", "expedition_out", "expedition_return", "expedition_missing", "expedition_lost",
	"expedition_rescued", "relic_lead", "research_done", "research_fail", "crisis_failed", "crisis_resolved", "revolt", "strike", "petition",
	"title", "nickname", "embassy", "marriage", "delegation", "inherit", "notable_gone"]
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
	var years := int(args.get("years", "15"))
	var sd := int(args.get("seed", "2024"))
	var verbose := int(args.get("verbose", "1")) != 0
	WorldGen.setup(sd)
	var hub: RefCounted = load("res://scripts/realm/realm_hub.gd").new()   # runtime load: autoloads exist by now
	hub.warm_up()
	var gov: RefCounted = hub.mod("governance")
	var nb: RefCounted = hub.mod("notables")
	var nw: RefCounted = hub.mod("news")
	var ctx := {"player_pos": Vector2.ZERO, "season": "spring", "at_war": false, "abs_hours": 0.0, "gold": 0}
	var cur := {"governance": 0, "notables": 0, "news": 0}
	var counts := {}
	var lines: Array = []
	var t0 := Time.get_ticks_usec()
	var worst := 0
	for day in range(1, years * 360 + 1):
		ctx["abs_hours"] = float(day) * 24.0
		for k: String in RUN:
			var t1 := Time.get_ticks_usec()
			var m: RefCounted = hub.mod(k)
			var chunks: Array = m.tick_day_chunks(day, ctx)
			if chunks.is_empty():
				m.tick_day(day, ctx)
			else:
				for c: Callable in chunks:
					c.call()
			worst = maxi(worst, Time.get_ticks_usec() - t1)
		for src: String in ["governance", "notables"]:
			for e: Dictionary in (hub.mod(src).news_events() as Array):
				if int(e["seq"]) > int(cur[src]):
					cur[src] = int(e["seq"])
					counts[e["kind"]] = int(counts.get(e["kind"], 0)) + 1
					if SHOW.has(String(e["kind"])):
						lines.append("Y%02d d%03d  %s" % [(day - 1) / 360 + 1, (day - 1) % 360 + 1, e["text"]])
		# Formal titles and nicknames come from news.gd.
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	print("=== CIV-B chronicle: %d years, seed %d ===" % [years, sd])
	if verbose:
		for l in lines:
			print(l)
	print("--- nicknames ---")
	var nicks: Dictionary = nw.nicknames()
	for s: String in nicks:
		var n: Dictionary = nicks[s]
		print("  %s -> \"%s\" (%s, from %s)" % [s, n["nick"], n["state"], n["deed"]])
	print("--- diplomacy (news.gd data events) ---")
	var dk: Dictionary = nw.stats()["dip_total"]
	print("  ", dk, " embassies: ", nw.embassies().size(), " | nb research done: ", nb.tech("agriculture") + nb.tech("medicine") + nb.tech("runestone_design") + nb.tech("rift_gear"))
	print("  tavern at Kingsreach: ", nw.news_for(0, "tavern", 3).map(func(x): return x["text"]))
	print("  notice board at Emberfall: ", nw.news_for(1, "board", 2).map(func(x): return x["text"]))
	print("--- dead notables (history) ---")
	for h in (nb.chronicle() as Array).slice(-8):
		print("  ", h)
	print("--- leaders lost ---")
	for h in (gov.chronicle() as Array).slice(-6):
		print("  ", h)
	var st_c := int(counts.get("succession", 0))
	var orgs_n := int(counts.get("founded_org", 0))
	var lost := int(counts.get("expedition_lost", 0))
	var titles := nicks.size()
	print("--- counts ---")
	print(counts)
	var laws_changed := int(counts.get("law", 0))
	print("laws changed: %d | notables %d | orgs %d | sim time %.0f ms (day-ticks, slowest module-day %.2f ms)" % [laws_changed, nb.active_count(), nb.orgs().size(), ms, float(worst) / 1000.0])
	print("save sizes (bytes): governance %d notables %d news %d" % [JSON.stringify(gov.serialize()).length(), JSON.stringify(nb.serialize()).length(), JSON.stringify(nw.serialize()).length()])
	var ok := st_c > 0 and orgs_n > 0 and lost > 0 and titles > 0
	print("ACCEPTANCE succession=%d npc_orgs=%d lost_expeditions=%d social_titles=%d -> %s" % [st_c, orgs_n, lost, titles, "PASS" if ok else "FAIL"])
	OS.kill(OS.get_process_id())
	return true
