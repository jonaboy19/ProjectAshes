extends RefCounted
## Region 1 balance probes (package L18): the static and Monte-Carlo checks the 100-day runs cannot show, all through the real code.
##   quests    town-kit quest rewards of all 30 towns: totals, outliers, corrupt-path premium, gold per objective
##   wages     what each career pays per day at each rank (Soldier against the others)
##   loops     money loops: same-market buy/sell, cross-market arbitrage (oracle merchant, no travel time), crafting arbitrage,
##             the fence against the market, pickpocket yield against the bounty it earns
## Each probe returns a Dictionary and a list of text lines for docs/regions/BALANCE_R1.md. Needs the autoloads (run as a Node).

const ItemsDB := preload("res://scripts/sim/items_db.gd")
const Crafting := preload("res://scripts/sim/crafting.gd")
const SoldierCareer := preload("res://scripts/sim/soldier_career.gd")
const Guild := preload("res://scripts/sim/adventurer_guild.gd")
const Pickpocket := preload("res://scripts/sim/pickpocket.gd")
const Theft := preload("res://scripts/sim/theft.gd")
const Trades := preload("res://scripts/realm/career_trades.gd")


# =============================================================================================== quests

## Gold of one quest path: the quest-level reward plus the end stage's own.
static func _path_gold(def: QuestDef, stage: Dictionary) -> int:
	return int((def.rewards() as Dictionary).get("gold", 0)) + int((stage.get("rewards", {}) as Dictionary).get("gold", 0))


static func probe_quests() -> Dictionary:
	var towns: Dictionary = {}                      # town -> {quests: [{id, honest, corrupt, objectives, kills}], total}
	var all_honest: Array = []
	var rows: Array = []
	for sub in DirAccess.get_directories_at("res://data/quests"):
		for f in DirAccess.get_files_at("res://data/quests/" + sub):
			if not f.ends_with(".json"):
				continue
			var q: QuestDef = QuestDef.load_json("res://data/quests/%s/%s" % [sub, f])
			if q == null:
				continue
			var ends: Array = []
			for st: Dictionary in q.stages:
				if bool(st.get("end", false)):
					ends.append(st)
			if ends.is_empty():
				ends.append(q.stages[q.stages.size() - 1])
			var honest: Dictionary = ends[0]
			var best_rep := -999
			for st: Dictionary in ends:
				var rp := int(((st.get("rewards", {}) as Dictionary).get("rep", {}) as Dictionary).get(sub, 0))
				if rp > best_rep:
					best_rep = rp
					honest = st
			var hg := _path_gold(q, honest)
			var cg := 0
			for st: Dictionary in ends:
				if st != honest:
					cg = maxi(cg, _path_gold(q, st))
			var nobj := 0
			var kills := 0
			for st: Dictionary in q.stages:
				for o: Dictionary in st.get("objectives", []):
					nobj += 1
					if String(o.get("type", "")) == "kill":
						kills += int(o.get("count", 1))
			rows.append({"town": sub, "id": q.id, "honest": hg, "corrupt": cg, "objectives": nobj, "kills": kills})
			if not towns.has(sub):
				towns[sub] = {"total": 0, "n": 0}
			towns[sub]["total"] = int(towns[sub]["total"]) + hg
			towns[sub]["n"] = int(towns[sub]["n"]) + 1
			all_honest.append(float(hg))
	var totals: Array = []
	for t: String in towns:
		totals.append(float(towns[t]["total"]))
	var mean_t := _mean(totals)
	var sd_t := _sd(totals)
	var sorted_t := totals.duplicate()
	sorted_t.sort()
	var median_t := float(sorted_t[sorted_t.size() / 2]) if not sorted_t.is_empty() else 0.0
	var outliers: Array = []
	for t: String in towns:
		var z := (float(towns[t]["total"]) - mean_t) / maxf(sd_t, 0.001)
		towns[t]["z"] = z
		# An outlier is a town paying a quarter more than the median town (z is reported for information).
		if float(towns[t]["total"]) > 1.25 * median_t or float(towns[t]["total"]) < 0.75 * median_t:
			outliers.append("%s %d gold (median %d, z %+.1f)" % [t, int(towns[t]["total"]), int(median_t), z])
	var worst_premium := 0.0
	var worst_q := ""
	var max_q := 0
	var max_q_id := ""
	var gold_per_obj: Array = []
	for r: Dictionary in rows:
		if int(r["corrupt"]) > 0 and int(r["honest"]) > 0:
			var pr := float(r["corrupt"]) / float(r["honest"])
			if pr > worst_premium:
				worst_premium = pr
				worst_q = String(r["id"])
		if int(r["honest"]) > max_q:
			max_q = int(r["honest"])
			max_q_id = String(r["id"])
		gold_per_obj.append(float(r["honest"]) / float(maxi(int(r["objectives"]), 1)))
	return {"town_median": median_t, "towns": towns, "rows": rows, "quests": rows.size(), "town_count": towns.size(), "town_mean": mean_t, "town_sd": sd_t,
		"outliers": outliers, "worst_premium": worst_premium, "worst_premium_quest": worst_q, "max_quest": max_q, "max_quest_id": max_q_id,
		"gold_per_objective_mean": _mean(gold_per_obj), "gold_per_objective_max": gold_per_obj.max() if not gold_per_obj.is_empty() else 0.0,
		"honest_mean": _mean(all_honest), "honest_max": all_honest.max() if not all_honest.is_empty() else 0.0}


# =============================================================================================== wages

## Gold per day each career pays at each rank, excluding loot and sales: {career: [per-rank gold/day]}.
static func probe_wages() -> Dictionary:
	var out: Dictionary = {}
	# Soldier: weekly wage / 7 plus the duty gold a day (average over the duty weights open to the rank).
	var sol: Array = []
	for i in SoldierCareer.rank_count():
		var kinds := SoldierCareer.kinds_for(i)
		var tw := 0.0
		var g := 0.0
		for k: String in kinds:
			var d := SoldierCareer.duty_def(k)
			tw += float(d["weight"])
			g += float(d["weight"]) * float(d["gold"])
		sol.append(snappedf(float(SoldierCareer.weekly_wage(i)) / 7.0 + g / maxf(tw, 1.0), 0.1))
	out["soldier"] = sol
	# Wardwright: stipend / 7 + the daily round + a typical need-scaled mend + two glyphs a day at skill 0.7.
	var wd: Dictionary = Trades.ward_data() if ResourceLoader.exists("res://data/careers/wardwright.json") else {}
	if not wd.is_empty():
		var q := 0.7
		var war: Array = []
		for i in (wd["stipend_week"] as Array).size():
			var day_g := float(wd["stipend_week"][i]) / 7.0 + float(wd["mend"]["daily_base"]) * (0.4 + q) + 0.3 * float(wd["mend"]["need_base"]) * (0.4 + q)
			day_g += 2.0 * float(wd["carve"]["base"]) * (0.4 + q)
			war.append(snappedf(day_g, 0.1))
		out["wardwright"] = war
	# Farmer / merchant: the career_trades tasks at skill 0.7 (quality about 0.7): three sow tasks (3 h each of the 10 working hours), or one
	# stall (6 h) and two haggles (2 h each).
	var q2 := 0.7
	var farm: Array = []
	for lv in [1, 10, 20, 30, 40]:
		farm.append(snappedf(3.0 * (4.0 + float(mini(lv, 40)) / 10.0) * (0.4 + q2) + 12.0 + 2.0, 0.1))   # + the farm spot: 2 full shifts and 1 third
	out["farmer_by_mastery_1_10_20_30_40"] = farm
	var mer: Array = []
	for lv in [1, 10, 20, 30, 40]:
		mer.append(snappedf(1.0 * (11.0 + float(mini(lv, 40)) * 0.2) * (0.3 + 1.2 * q2) + 2.0 * (8.0 + float(mini(lv, 40)) * 0.15) * (0.3 + 1.2 * q2), 0.1))
	out["merchant_by_mastery_1_10_20_30_40"] = mer
	# The old Guard seat and the other seats of careers.gd (a flat daily wage).
	out["guard_seats_daily"] = {"Guard": 9, "Sergeant": 18, "Captain": 30}
	out["guild_commission_gold_by_rank_F_to_S"] = Guild.RANK_GOLD
	return out


# =============================================================================================== loops

## Same-market round trip: buy a unit and sell it straight back. Returns the loss share (positive = you lose).
static func _round_trip_loss() -> Dictionary:
	var m: RefCounted = Life.economy.markets[0]
	var worst := 0.0
	var gains := 0
	var checked := 0
	for item: String in m.base_price:
		if int(m.stock.get(item, 0)) < 2 or int(m.purse) < 50:
			continue
		var buy := int(m.price(item))
		# After the purchase the stock is one lower, then the sell price is read off the new stock.
		var s_after := float(m.stock[item]) - 1.0
		var f := clampf(float(m.target.get(item, 1)) / maxf(s_after + 1.0, 0.5), 0.5, 3.0)       # price at stock+1 when selling back
		var sell := maxi(1, int(floor(float(maxi(1, int(round(float(m.base_price[item]) * f * m.modifier(item))))) * m.SELL_SHARE)))
		checked += 1
		if sell > buy:
			gains += 1
		worst = maxf(worst, float(sell - buy) / maxf(float(buy), 1.0))
	return {"checked": checked, "profitable_items": gains, "best_gain_share": worst}


## Crafting arbitrage: inputs bought at list price, the product sold at the market share.
static func probe_crafting() -> Dictionary:
	var crafting: RefCounted = Life.crafting
	var rows: Array = []
	var positive := 0
	var checked := 0
	for r: Dictionary in crafting.recipes:
		if bool(r.get("repair", false)) or not r.has("output"):
			continue
		var out_item := String((r["output"] as Dictionary)["item"])
		var out_n := int((r["output"] as Dictionary)["count"])
		var out_price := float(Crafting.item_info(out_item).get("price", 0))
		if out_price <= 0.0:
			continue
		var cost := 0.0
		var ok := true
		for inp: Dictionary in r.get("inputs", []):
			var spec := String(inp["item"])
			var alts: PackedStringArray = Crafting.alternatives(spec)
			var cheapest := 1.0e9
			for a: String in alts:
				var p := float(Crafting.item_info(a).get("price", 0))
				if p > 0.0:
					cheapest = minf(cheapest, p)
			if cheapest > 1.0e8:
				ok = false
				break
			cost += cheapest * float(inp["count"])
		if not ok:
			continue
		checked += 1
		var revenue := out_price * float(out_n) * 0.6
		var margin := revenue - cost
		if margin > 0.0:
			positive += 1
		rows.append({"recipe": String(r["id"]), "margin": snappedf(margin, 0.1), "cost": snappedf(cost, 0.1), "revenue": snappedf(revenue, 0.1),
			"margin_share": snappedf(margin / maxf(cost, 1.0), 0.01), "xp_hours": float(r.get("time", 1.5))})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["margin"]) > float(b["margin"]))
	return {"checked": checked, "positive": positive, "top": rows.slice(0, 8), "best_margin": rows[0]["margin"] if not rows.is_empty() else 0.0}


## The fence against the honest market: for every priced item, FENCE_SHARE x value against the market's SELL_SHARE x price.
static func probe_fence() -> Dictionary:
	var m: RefCounted = Life.economy.markets[0]
	var better := 0
	var n := 0
	var list: Array = []
	for item: String in m.base_price:
		var v := int(Life.item_prop(item, "price", 0))
		if v <= 0:
			continue
		n += 1
		var fp: int = Theft.fence_price(item)
		var mp: int = m.sell_price(item)
		if fp > mp:
			better += 1
			list.append("%s fence %d vs market %d (market base %d, item value %d)" % [item, fp, mp, int(m.base_price[item]), v])
	return {"fence_share": Theft.FENCE_SHARE, "market_share": m.SELL_SHARE, "items": n, "fence_pays_more": better,
		"petty_value_limit": Theft.PETTY_VALUE, "examples": list.slice(0, 8)}


## Pickpocketing a town for `days` days (40 attempts a day, 8 s each in a 540 s day with walking): gold stolen against the bounty
## and the criminal standing it earns through the real Society. Returns the totals.
static func probe_pickpocket(days: int, stealth: float, witnesses_avg: float) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4711
	var soc: RefCounted = Life.realm.mod("society")
	var stolen := [0]
	var attempts := 0
	var successes := 0
	var caught := 0
	var sid := 0
	var rng_people: Vector2i = WorldSim.ranges[0]
	for d in days:
		var day := WorldSim.day + d
		for a in 40:
			attempts += 1
			var person := rng_people.x + rng.randi() % maxi(1, rng_people.y - rng_people.x)
			var victim_class := 0 if rng.randf() < 0.7 else 1
			var heat: int = Pickpocket.heat_today(day)
			var p := Pickpocket.chance(stealth, 1.0, 0.6, rng.randf() < 0.8, victim_class, true, heat)
			var res := Pickpocket.resolve(rng.randf() < p, person, day, func(g: int) -> void: stolen[0] += g)
			var wit := 0
			var wf := witnesses_avg
			while wf > 0.0:
				wit += 1 if rng.randf() < minf(wf, 1.0) else 0
				wf -= 1.0
			if bool(res["ok"]):
				successes += 1
			if String(res["crime"]) == "robbery":
				wit = maxi(wit, 1)           # the victim certainly saw
			if String(res["crime"]) != "" and soc != null:
				soc.call("commit_crime", String(res["crime"]), sid, wit)
			if String(res["crime"]) == "robbery":
				caught += 1
		# Society runs its daily investigation tick (bounties come out of it).
		for h in range(0, 24):
			WorldSim.day = day
			WorldSim.time_of_day = float(h)
			WorldSim.hour_changed.emit(h)
			Life.realm.drain()
	var bounty := int(soc.call("bounty")) if soc != null else 0
	return {"days": days, "attempts": attempts, "successes": successes, "caught_hand": caught, "gold_stolen": stolen[0], "gold_per_day": float(stolen[0]) / float(days),
		"bounty": bounty, "success_rate": float(successes) / float(maxi(attempts, 1)), "crim_rep": float(soc.call("crim_rep", "city:0")) if soc != null else 0.0}


## Oracle merchant: every day, with no travel time, up to `runs` trades chosen by marginal profit across ALL sources and destinations
## (the sim's _plan_trade). The best a trader who knew every price could do against the real price curves and purses.
static func probe_oracle_merchant(sim: RefCounted, days: int, runs: int) -> Dictionary:
	var gold0 := Game.gold
	var best_day := 0
	var daily: Array = []
	for d in days:
		var g0 := Game.gold
		sim.day = 1 + d
		for r in runs:
			var best: Dictionary = {}
			var best_profit := 0
			for sid in Life.economy.markets:
				sim._pos_sid = int(sid)
				sim._secs_left = 1.0e6
				var plan: Dictionary = sim._plan_trade(maxi(Game.gold, 2000), 60)
				if not plan.is_empty() and int(plan["profit"]) > best_profit:
					best_profit = int(plan["profit"])
					best = plan.duplicate()
					best["from"] = int(sid)
			if best.is_empty():
				break
			var eco: RefCounted = Life.economy
			var bought := 0
			for k in int(best["units"]):
				var paid: int = eco.buy(int(best["from"]), String(best["item"]), 1 << 20)
				if paid < 0:
					break
				Game.add_gold(-paid)
				bought += 1
			for k in bought:
				var got: int = eco.sell(int(best["to"]), String(best["item"]))
				if got < 0:
					break
				Game.add_gold(got)
		var gain := Game.gold - g0
		daily.append(gain)
		best_day = maxi(best_day, gain)
		for h in range(0, 24):
			WorldSim.day = 1 + d
			WorldSim.time_of_day = float(h)
			WorldSim.hour_changed.emit(h)
			Life.realm.drain()
	var first := 0
	var last := 0
	for i in mini(10, daily.size()):
		first += int(daily[i])
		last += int(daily[daily.size() - 1 - i])
	return {"days": days, "runs_per_day": runs, "gold_gained": Game.gold - gold0, "per_day": float(Game.gold - gold0) / float(days), "best_day": best_day,
		"first10_avg": float(first) / 10.0, "last10_avg": float(last) / 10.0}


## Buy-sell round trips of the merchant between two markets as the plan sees them: how much of the displayed margin survives slippage.
static func probe_loops() -> Dictionary:
	return {"round_trip": _round_trip_loss(), "crafting": probe_crafting(), "fence": probe_fence()}


## Crafting loop through the real systems: for each recipe with a positive list-price margin whose inputs and product the home market
## trades, buy the inputs at the market's price, craft (Life.crafting.craft, real quality rolls) and sell the product, up to `per_day`
## crafts (15 s each in a 540 s day) for `days` days with the market ticking between. Returns {recipe: gold per day} and the best.
static func probe_craft_loop(days: int, per_day: int) -> Dictionary:
	var eco: RefCounted = Life.economy
	var m: RefCounted = eco.markets[0]
	var crafting: RefCounted = Life.crafting
	var results: Dictionary = {}
	var best_rate := -1.0e9
	var best := ""
	var cands: Array = []
	for r: Dictionary in crafting.recipes:
		if bool(r.get("repair", false)) or not r.has("output"):
			continue
		var out_item := String((r["output"] as Dictionary)["item"])
		if not m.base_price.has(out_item):
			continue
		var ok := true
		for inp: Dictionary in r.get("inputs", []):
			var found := false
			for a: String in Crafting.alternatives(String(inp["item"])):
				if m.base_price.has(a):
					found = true
			ok = ok and found
		if ok:
			cands.append(r)
	for r: Dictionary in cands:
		Game.gold = 2000
		var g0 := Game.gold
		var crafted := 0
		for d in days:
			for k in per_day:
				# Buy the inputs.
				var spent := 0
				var good := true
				for inp: Dictionary in r["inputs"]:
					var need := int(inp["count"])
					var picked := ""
					var pick_price := 1 << 30
					for a: String in Crafting.alternatives(String(inp["item"])):
						if m.base_price.has(a) and int(m.stock.get(a, 0)) >= need and m.price(a) < pick_price:
							picked = a
							pick_price = m.price(a)
					if picked == "":
						good = false
						break
					for n in need:
						var paid: int = eco.buy(0, picked, Game.gold)
						if paid < 0:
							good = false
							break
						Game.add_gold(-paid)
						spent += paid
						Life.give(picked, 1)
				if not good:
					break
				var res: Dictionary = crafting.craft(String(r["id"]), Life, null, {})
				if not bool(res.get("ok", false)):
					break
				crafted += 1
				var out_item := String(res.get("item", ""))
				var got_total := 0
				for n in int(res.get("count", 0)):
					var got: int = eco.sell(0, out_item)
					if got < 0:
						break
					Game.add_gold(got)
					Life.take(out_item, 1)
					got_total += got
				if got_total - spent < 1:
					break          # no profit left at the going price: a sensible crafter stops
			for h in range(0, 24):
				WorldSim.day += 0
				WorldSim.time_of_day = float(h)
				WorldSim.hour_changed.emit(h)
				Life.realm.drain()
		var rate := float(Game.gold - g0) / float(days)
		results[String(r["id"])] = snappedf(rate, 0.1)
		if rate > best_rate:
			best_rate = rate
			best = String(r["id"])
	return {"recipes_tried": cands.size(), "best_recipe": best, "best_gold_per_day": snappedf(best_rate, 0.1), "per_day_cap": per_day,
		"top": _top_n(results, 6)}


static func _top_n(d: Dictionary, n: int) -> Array:
	var arr: Array = []
	for k: String in d:
		arr.append([k, d[k]])
	arr.sort_custom(func(a: Array, b: Array) -> bool: return float(a[1]) > float(b[1]))
	return arr.slice(0, n)


# =============================================================================================== helpers

static func _mean(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var s := 0.0
	for v: Variant in a:
		s += float(v)
	return s / float(a.size())


static func _sd(a: Array) -> float:
	if a.size() < 2:
		return 0.0
	var m := _mean(a)
	var s := 0.0
	for v: Variant in a:
		s += (float(v) - m) * (float(v) - m)
	return sqrt(s / float(a.size()))
