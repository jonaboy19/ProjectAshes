extends SceneTree
## Balance harness. Args after `--`: days=730 tag=before mode=run|catchup
var done := false
var args := {}
var C
var out_dir := "/tmp/claude-0/balance/"
var tag := "run"
var f_metrics: FileAccess
var f_sizes: FileAccess
var f_fac: FileAccess
var f_reg: FileAccess
var f_prices: FileAccess
var f_events: FileAccess
var init_pop := {}
var init_price := {}
var war_state := false
var war_start := 0
var war_count := 0
var war_days_total := 0
var war_enemy := ""
var prev_counters := {}
var callup_week_log := []
var last_callup_next := 1
var sample_hdr := false

func _process(_dt: float) -> bool:
	if done: return false
	done = true
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.split("=")
		if kv.size() == 2: args[kv[0]] = kv[1]
	tag = args.get("tag", "run")
	C = load("/tmp/claude-0/balance/core.gd").new(root)
	C.life.realm.warm_up()
	var mode: String = args.get("mode", "run")
	if mode == "run":
		run_full(int(args.get("days", "730")))
	elif mode == "catchup":
		run_catchup()
	quit()
	return false

func life_mod(n: String):
	return C.life.get(n)

func gi(d, k, def = 0):
	if d is Dictionary and d.has(k): return d[k]
	return def

# ---- metrics ------------------------------------------------------------------
func econ_rows(day: int) -> Dictionary:
	var eco = C.life.economy
	var goods := {}
	var idx_sum := 0.0
	var idx_n := 0
	for id in eco.markets:
		var m = eco.markets[id]
		for item in m.base_price:
			var p: int = m.price(item)
			var g = goods.get(item, {"p": 0.0, "n": 0, "stock": 0.0, "target": 0.0, "base": float(m.base_price[item])})
			g["p"] += p; g["n"] += 1
			g["stock"] += float(m.stock.get(item, 0)); g["target"] += float(m.target.get(item, 0))
			goods[item] = g
			idx_sum += float(p) / maxf(1.0, float(m.base_price[item])); idx_n += 1
	return {"goods": goods, "index": idx_sum / maxf(1.0, idx_n)}

func realm_ser() -> Dictionary:
	return C.hub.serialize()

func sample(day: int, wall: float) -> void:
	var rs: Dictionary = realm_ser()
	var L = C.life
	var row := {}
	row["day"] = day
	row["wall_s"] = snappedf(wall, 0.1)
	# economy
	var e: Dictionary = econ_rows(day)
	row["price_index"] = snappedf(e["index"], 0.001)
	var gs: Dictionary = e["goods"]
	var purse := 0.0
	for id in L.economy.markets: purse += float(L.economy.markets[id].purse)
	row["market_purse_total"] = int(purse)
	for item in gs:
		var g = gs[item]
		var mp: float = g["p"] / g["n"]
		if not init_price.has(item): init_price[item] = mp
		f_prices.store_line("%d,%s,%.2f,%.3f,%.1f,%.1f,%d" % [day, item, mp, mp / maxf(0.01, init_price[item]), g["stock"], g["target"], g["n"]])
	# settlements
	var sd: Dictionary = gi(gi(rs, "settlements", {}), "s", {})
	var pops := []
	var tot_pop := 0; var shortages := 0; var stock_tot := 0.0; var collapsed := 0; var exploded := 0
	var ident := {}
	for sid in sd:
		var s: Dictionary = sd[sid]
		var p := int(s.get("pop", 0))
		tot_pop += p
		if not init_pop.has(sid): init_pop[sid] = maxi(1, p)
		if p < 0.5 * init_pop[sid]: collapsed += 1
		if p > 2.0 * init_pop[sid]: exploded += 1
		shortages += (s.get("shortage", {}) as Dictionary).size()
		for k in (s.get("stock", {}) as Dictionary): stock_tot += float(s["stock"][k])
		var best := ""; var bv := -1.0
		for k in (s.get("identity", {}) as Dictionary):
			if float(s["identity"][k]) > bv: bv = float(s["identity"][k]); best = k
		ident[best] = int(ident.get(best, 0)) + 1
		pops.append(p)
	pops.sort()
	row["pop_total"] = tot_pop
	row["pop_min"] = pops[0] if pops.size() else 0
	row["pop_max"] = pops[-1] if pops.size() else 0
	row["sett_collapsed_lt50pct"] = collapsed
	row["sett_exploded_gt200pct"] = exploded
	row["shortage_entries"] = shortages
	row["sett_stock_total"] = int(stock_tot)
	var ist := []
	for k in ident: ist.append("%s:%d" % [k, ident[k]])
	ist.sort()
	row["identity_dominant"] = "|".join(ist)
	row["emerg_pending"] = (gi(gi(rs, "settlements", {}), "emerg", []) as Array).size()
	# factions
	var fs: Dictionary = gi(gi(rs, "factions", {}), "factions", {})
	var nat_pow := 0.0; var nat_max := 0.0; var nat_max_id := ""; var treas := 0.0; var house_wealth := 0.0; var house_n := 0
	var wealth_max := 0.0
	for id in fs:
		var f: Dictionary = fs[id]
		f_fac.store_line("%d,%s,%s,%.2f,%.2f" % [day, id, f.get("kind", ""), float(f.get("power", 0)), float(f.get("wealth", 0))])
		var kind: String = f.get("kind", "")
		if kind == "nation":
			nat_pow += float(f["power"])
			if float(f["power"]) > nat_max: nat_max = float(f["power"]); nat_max_id = id
		if kind == "house": house_wealth += float(f["wealth"]); house_n += 1
		wealth_max = maxf(wealth_max, float(f.get("wealth", 0)))
		treas += float(f.get("wealth", 0))
	row["nation_power_top_share"] = snappedf(nat_max / maxf(1.0, nat_pow), 0.001)
	row["nation_power_top"] = nat_max_id
	row["faction_wealth_sum"] = snappedf(treas, 0.1)
	row["faction_wealth_max"] = snappedf(wealth_max, 0.1)
	row["house_wealth_avg"] = snappedf(house_wealth / maxf(1, house_n), 0.1)
	var fac: Dictionary = gi(rs, "factions", {})
	row["fac_log_n"] = (gi(fac, "log", []) as Array).size()
	row["fac_ties_n"] = (gi(fac, "ties", []) as Array).size()
	row["fac_marriages_n"] = (gi(fac, "marriages", []) as Array).size()
	row["fac_sects_n"] = (gi(fac, "sects", []) as Array).size()
	var grv := 0.0; var grv_max := 0.0
	var rel: Dictionary = gi(fac, "rel", {})
	for k in rel:
		grv += float(rel[k].get("grievance", 0)); grv_max = maxf(grv_max, float(rel[k].get("grievance", 0)))
	row["rel_grievance_avg"] = snappedf(grv / maxf(1, rel.size()), 0.01)
	row["rel_grievance_max"] = snappedf(grv_max, 0.01)
	# land
	var land: Dictionary = gi(rs, "land", {})
	var loy: Dictionary = gi(land, "loyalty", {})
	var lmin := 999.0; var lmax := -1.0; var lsum := 0.0; var unrest_n := 0
	for r in loy:
		var v := float(loy[r])
		f_reg.store_line("%d,%s,%.2f" % [day, r, v])
		lmin = minf(lmin, v); lmax = maxf(lmax, v); lsum += v
		if v < 25.0: unrest_n += 1
	row["loyalty_avg"] = snappedf(lsum / maxf(1, loy.size()), 0.1)
	row["loyalty_min"] = snappedf(lmin, 0.1)
	row["loyalty_max"] = snappedf(lmax, 0.1)
	row["regions_low_loyalty"] = unrest_n
	var rb_act := 0; var rb_tot := 0
	for rb in gi(land, "rebels", []):
		rb_tot += 1
		if rb.get("status", "") in ["brewing", "open"]: rb_act += 1
	var rebel_held := 0
	for rg in gi(land, "deeds", {}):
		if land["deeds"][rg].get("occupier", "") == "rebels": rebel_held += 1
	row["rebels_active"] = rb_act
	row["rebel_records_n"] = rb_tot
	row["regions_held_by_rebels"] = rebel_held
	row["rebellions_total"] = int(gi(land, "next_rebel", 1)) - 1
	row["land_memory_n"] = _count(gi(land, "memory", {}))
	row["land_claims_n"] = (gi(land, "claims", {}) as Dictionary).size()
	# wars
	row["war_now"] = 1 if L.war.is_at_war() else 0
	row["wars_started"] = war_count
	row["war_days_total"] = war_days_total + ((day - war_start) if war_state else 0)
	row["war_tension_max"] = snappedf(maxf(float(L.war.tension.get("ongur_khanate", 0)), float(L.war.tension.get("urrokai_clanlands", 0))), 0.1)
	row["war_chronicle_n"] = L.war.chronicle.size()
	# campaign / strongholds
	var cam: Dictionary = gi(rs, "campaign", {})
	var armies: Array = gi(cam, "armies", [])
	var strength := 0.0
	for a in armies:
		if a is Dictionary:
			for k in ["size", "strength", "troops", "men"]:
				if a.has(k) and (a[k] is float or a[k] is int): strength += float(a[k]); break
	row["armies"] = armies.size()
	row["army_strength"] = int(strength)
	for k in ["couriers", "reports", "battles", "evidence", "orders_log", "advisors", "engs"]:
		row["camp_" + k] = (gi(cam, k, []) as Array).size()
	row["camp_intel_n"] = _count(gi(cam, "intel", {}))
	row["camp_sight_n"] = _count(gi(cam, "sight", {}))
	var sh: Dictionary = gi(rs, "strongholds", {})
	row["raids_total"] = int(gi(sh, "next_raid", 1)) - 1
	row["raids_active"] = (gi(sh, "raids", []) as Array).size()
	row["raid_results_n"] = (gi(sh, "results", []) as Array).size()
	var gar := 0; var gmax := 0
	for s in gi(sh, "sh", []): gar += int(s.get("garrison", 0)); gmax += int(s.get("garrison_max", 0))
	row["garrison_frac"] = snappedf(float(gar) / maxf(1, gmax), 0.001)
	var swealth := 0
	for s in gi(sh, "sh", []): swealth += int(s.get("wealth", 0))
	row["stronghold_wealth_total"] = swealth
	# society
	var soc: Dictionary = gi(rs, "society", {})
	var npcs: Dictionary = gi(soc, "npcs", {})
	row["npcs"] = npcs.size()
	var alive := 0; var goals := 0
	for k in npcs:
		var n: Dictionary = npcs[k]
		if n.get("alive", true): alive += 1
		goals += (n.get("goals", []) as Array).size()
	row["npcs_alive"] = alive
	row["npc_goals"] = goals
	row["rumours"] = (gi(soc, "rumours", []) as Array).size()
	row["rumour_hops"] = (gi(soc, "hops", []) as Array).size()
	row["houses"] = (gi(soc, "houses", {}) as Dictionary).size()
	row["feuds"] = (gi(soc, "feuds", []) as Array).size()
	row["soc_events_n"] = (gi(soc, "events", []) as Array).size()
	row["soc_crimes_n"] = (gi(soc, "crimes", []) as Array).size()
	row["soc_stories_n"] = (gi(soc, "stories", []) as Array).size()
	row["soc_offers_n"] = (gi(soc, "offers", []) as Array).size()
	row["soc_rep_log_n"] = (gi(soc, "rep_log", []) as Array).size()
	# city life
	var cl: Dictionary = gi(rs, "city_life", {})
	var jobs := 0; var boards := 0
	for sid in gi(cl, "cities", {}):
		var c: Dictionary = cl["cities"][sid]
		jobs += (c.get("jobs", []) as Array).size()
		for d in (c.get("boards", {}) as Dictionary): boards += (c["boards"][d] as Array).size()
	row["cl_jobs"] = jobs
	row["cl_board_posts"] = boards
	var leaders := 0; var ghist := 0; var treasury := 0
	for gid in gi(cl, "guilds", {}):
		var g: Dictionary = cl["guilds"][gid]
		if (g.get("leader", {}) as Dictionary).size() > 0: leaders += 1
		ghist += (g.get("history", []) as Array).size()
		treasury += int(g.get("treasury", 0))
	row["guilds"] = (gi(cl, "guilds", {}) as Dictionary).size()
	row["guild_leaders"] = leaders
	row["guild_history_n"] = ghist
	row["guild_treasury_total"] = treasury
	row["cl_log_n"] = (gi(cl, "log", []) as Array).size()
	row["cl_history_n"] = (gi(cl, "history", []) as Array).size()
	# education
	var ed: Dictionary = gi(rs, "education", {})
	row["edu_cohorts"] = _count(gi(ed, "cohorts", {}))
	row["edu_insts"] = (gi(ed, "insts", {}) as Dictionary).size()
	row["edu_history_n"] = (gi(ed, "history", []) as Array).size()
	row["edu_tournaments_n"] = (gi(ed, "tournaments", []) as Array).size()
	row["edu_rivals_n"] = (gi(ed, "rivals", []) as Array).size()
	var infl := 0.0
	for k in gi(ed, "insts", {}): infl = maxf(infl, float(ed["insts"][k].get("inflation", 1.0)))
	row["edu_inflation_max"] = snappedf(infl, 0.001)
	# callups
	var cu: Dictionary = gi(rs, "callups", {})
	var nxt := int(gi(cu, "next_id", 1))
	row["callups_total"] = nxt - 1
	row["callups_per_week_30d"] = snappedf(float(nxt - last_callup_next) / (30.0 / 7.0), 0.01)
	last_callup_next = nxt
	row["callup_offers_n"] = (gi(cu, "offers", []) as Array).size()
	row["callup_history_n"] = (gi(cu, "history", []) as Array).size()
	# household / work / followers / camps
	row["household_deaths_n"] = (gi(gi(rs, "household", {}), "deaths", []) as Array).size()
	row["household_trip_log_n"] = (gi(gi(rs, "household", {}), "trip_log", []) as Array).size()
	row["work_log_n"] = (gi(gi(rs, "work", {}), "log", []) as Array).size()
	row["followers"] = (gi(gi(rs, "followers", {}), "f", {}) as Dictionary).size()
	row["camps"] = (gi(gi(rs, "camps", {}), "camps", {}) as Dictionary).size()
	var cond := 0.0; var en := 0
	for k in gi(gi(rs, "camps", {}), "edges", {}): cond += float(rs["camps"]["edges"][k].get("cond", 0)); en += 1
	row["road_cond_avg"] = snappedf(cond / maxf(1, en), 0.001)
	if rs.has("enterprise"): row["has_enterprise"] = 1
	# Life-side
	row["life_courses_people"] = (gi(L.life_courses.serialize(), "people", {}) as Dictionary).size()
	row["life_courses_news"] = (gi(L.life_courses.serialize(), "news", []) as Array).size()
	row["feud_count_nobility"] = L.nobility.feuds().size()
	row["contracts"] = L.economy.contracts.size()
	row["gold_player"] = root.get_node("Game").gold
	var lcs: Dictionary = L.life_courses.serialize()
	var lc_alive := 0
	for k in gi(lcs, "people", {}):
		if lcs["people"][k].get("alive", true): lc_alive += 1
	row["lc_alive"] = lc_alive
	row["lc_dead_kept"] = (gi(lcs, "people", {}) as Dictionary).size() - lc_alive
	var eco = root.get_node("Frontier").ecology
	var dn := 0; var dalive := 0; var dpop := 0
	for dd in eco.dens:
		dn += 1
		if dd["alive"]: dalive += 1; dpop += int(dd["population"])
	row["dens_total"] = dn
	row["dens_alive"] = dalive
	row["dens_pop"] = dpop
	row["eco_events_n"] = eco._events.size()
	row["eco_hunts_n"] = eco._pending_hunts.size()
	row["ashford_bread_stock"] = L.market.stock.get("bread", -1)
	row["ashford_bread_price"] = L.market.price("bread")
	row["ashford_wheat_like_stock_sum"] = int(L.market.stock.get("apple", 0)) + int(L.market.stock.get("cheese", 0)) + int(L.market.stock.get("firewood", 0))
	# save size
	var realm_b := JSON.stringify(rs).length()
	var snap: Dictionary = L.snapshot()
	var snap_b := JSON.stringify(snap).length()
	row["save_realm_bytes"] = realm_b
	row["save_total_bytes"] = snap_b
	# sizes.csv (per module / key)
	for k in snap:
		var v = snap[k]
		var b := JSON.stringify(v).length()
		f_sizes.store_line("%d,%s,%d,%d" % [day, k, (v.size() if (v is Array or v is Dictionary) else -1), b])
		if k == "realm":
			for m in v:
				var mv = v[m]
				f_sizes.store_line("%d,realm.%s,%d,%d" % [day, m, (mv.size() if (mv is Array or mv is Dictionary) else -1), JSON.stringify(mv).length()])
				if mv is Dictionary:
					for kk in mv:
						var vv = mv[kk]
						if vv is Array or vv is Dictionary:
							f_sizes.store_line("%d,realm.%s.%s,%d,%d" % [day, m, kk, vv.size(), JSON.stringify(vv).length()])
		elif v is Dictionary and k in ["life_courses", "nobility", "lordship", "family", "economy", "war", "world_events", "guild", "careers", "relationships", "property", "market", "biography", "world"]:
			for kk in v:
				var vv = v[kk]
				if vv is Array or vv is Dictionary:
					f_sizes.store_line("%d,%s.%s,%d,%d" % [day, k, kk, vv.size(), JSON.stringify(vv).length()])
	# job timing
	var maxj := 0; var maxk := ""
	for k in C.job_max_us:
		if C.job_max_us[k] > maxj: maxj = C.job_max_us[k]; maxk = k
		row["jobms_" + k] = snappedf(C.job_max_us[k] / 1000.0, 0.01)
	row["job_max_ms"] = snappedf(maxj / 1000.0, 0.01)
	row["job_max_name"] = maxk
	C.job_max_us = {}
	write_row(row)

func _count(v) -> int:
	var n := 0
	if v is Dictionary:
		for k in v:
			var x = v[k]
			n += (x.size() if (x is Array or x is Dictionary) else 1)
	elif v is Array:
		n = v.size()
	return n

var hdr_keys := []
func write_row(row: Dictionary) -> void:
	if not sample_hdr:
		sample_hdr = true
		hdr_keys = row.keys()
		f_metrics.store_line(",".join(hdr_keys))
	var cells := []
	for k in hdr_keys: cells.append(str(row.get(k, "")))
	f_metrics.store_line(",".join(cells))
	f_metrics.flush(); f_sizes.flush(); f_fac.flush(); f_reg.flush(); f_prices.flush()

func track_war(day: int) -> void:
	var w: bool = C.life.war.is_at_war()
	if w and not war_state:
		war_state = true; war_start = day; war_count += 1; war_enemy = C.life.war.enemy_id()
		f_events.store_line("%d,war_start,%s" % [day, war_enemy])
	elif not w and war_state:
		war_state = false; war_days_total += day - war_start
		f_events.store_line("%d,war_end,%s,duration=%d" % [day, war_enemy, day - war_start])

func open_files() -> void:
	f_metrics = FileAccess.open(out_dir + tag + "_metrics.csv", FileAccess.WRITE)
	f_sizes = FileAccess.open(out_dir + tag + "_sizes.csv", FileAccess.WRITE)
	f_fac = FileAccess.open(out_dir + tag + "_factions.csv", FileAccess.WRITE)
	f_reg = FileAccess.open(out_dir + tag + "_regions.csv", FileAccess.WRITE)
	f_prices = FileAccess.open(out_dir + tag + "_prices.csv", FileAccess.WRITE)
	f_events = FileAccess.open(out_dir + tag + "_events.csv", FileAccess.WRITE)
	f_sizes.store_line("day,path,n,bytes"); f_fac.store_line("day,id,kind,power,wealth"); f_reg.store_line("day,region,loyalty")
	f_prices.store_line("day,good,mean_price,ratio_vs_day0,stock_total,target_total,markets")

func run_full(total: int) -> void:
	open_files()
	var t0 := Time.get_ticks_msec()
	sample(1, 0.0)
	var day := 1
	while day < 1 + total:
		var n := mini(30, 1 + total - day)
		for d in range(day, day + n):
			for h in 24: C.hour(d, h)
			track_war(d)
			if d % 7 == 0: pass
		day += n
		sample(day, (Time.get_ticks_msec() - t0) / 1000.0)
		print("day ", day, " wall ", (Time.get_ticks_msec() - t0) / 1000.0)
	print("TOTAL wall ", (Time.get_ticks_msec() - t0) / 1000.0, " wars ", war_count)

# ---- catch_up comparison --------------------------------------------------------
func brief(rs: Dictionary) -> Dictionary:
	var r := {}
	var sd: Dictionary = gi(gi(rs, "settlements", {}), "s", {})
	var pop := 0; var grain := 0.0
	for sid in sd:
		pop += int(sd[sid].get("pop", 0))
		grain += float(sd[sid].get("stock", {}).get("grain", 0))
	r["pop"] = pop; r["grain"] = int(grain)
	var fs: Dictionary = gi(gi(rs, "factions", {}), "factions", {})
	var pw := 0.0; var we := 0.0
	for id in fs: pw += float(fs[id].get("power", 0)); we += float(fs[id].get("wealth", 0))
	r["fac_power"] = int(pw); r["fac_wealth"] = int(we)
	var loy: Dictionary = gi(gi(rs, "land", {}), "loyalty", {})
	var ls := 0.0
	for k in loy: ls += float(loy[k])
	r["loyalty_avg"] = snappedf(ls / maxf(1, loy.size()), 0.1)
	r["rebellions"] = int(gi(gi(rs, "land", {}), "next_rebel", 1)) - 1
	r["raids"] = int(gi(gi(rs, "strongholds", {}), "next_raid", 1)) - 1
	var sh := 0
	for s in gi(gi(rs, "strongholds", {}), "sh", []): sh += int(s.get("garrison", 0))
	r["garrison"] = sh
	var soc: Dictionary = gi(rs, "society", {})
	r["npcs"] = (gi(soc, "npcs", {}) as Dictionary).size()
	r["rumours"] = (gi(soc, "rumours", []) as Array).size()
	var cl: Dictionary = gi(rs, "city_life", {})
	var jobs := 0
	for sid in gi(cl, "cities", {}): jobs += (cl["cities"][sid].get("jobs", []) as Array).size()
	r["cl_jobs"] = jobs
	r["callups"] = int(gi(gi(rs, "callups", {}), "next_id", 1)) - 1
	r["bytes"] = JSON.stringify(rs).length()
	return r

func run_catchup() -> void:
	var f := FileAccess.open(out_dir + tag + "_catchup.csv", FileAccess.WRITE)
	var keys: Array = []
	var day := 1
	for d in range(1, 91):
		for h in 24: C.hour(d, h)
	day = 91
	var base_json := JSON.stringify(realm_ser())
	var spans := [1, 7, 30, 90, 365]
	f.store_line("span,mode," + "metric,value")
	for n in spans:
		# restore base
		C.hub.deserialize(JSON.parse_string(base_json))
		var ctx: Dictionary = C.life._realm_ctx()
		var b0 := brief(realm_ser())
		# fine
		var t0 := Time.get_ticks_msec()
		for d in range(day, day + n):
			for h in 24: C.hour(d, h)
		var tf := Time.get_ticks_msec() - t0
		var fine := brief(realm_ser())
		# catch-up from the same base
		C.hub.deserialize(JSON.parse_string(base_json))
		t0 = Time.get_ticks_msec()
		C.ws.day = day + n
		C.hub.catch_up(n, C.life._realm_ctx())
		var tc := Time.get_ticks_msec() - t0
		var cu := brief(realm_ser())
		for k in b0:
			f.store_line("%d,base,%s,%s" % [n, k, b0[k]])
			f.store_line("%d,fine,%s,%s" % [n, k, fine[k]])
			f.store_line("%d,catchup,%s,%s" % [n, k, cu[k]])
		f.store_line("%d,fine,ms,%d" % [n, tf]); f.store_line("%d,catchup,ms,%d" % [n, tc])
		print("span ", n, " fine ", fine, " catchup ", cu, " ms ", tf, "/", tc)
	f.close()
