extends GdUnitTestSuite
## CPU pass 2026-10-06: the economy's hourly tick is spread over frames (queue_hour_jobs), skips idle goods, caches its
## price modifiers and the daily trade only walks goods somebody makes. All of that must be invisible: the state after
## days of ticking equals the old algorithm (a reference copy of it below), through both the synchronous tick_hour and the
## queued jobs, and a save taken halfway through an hour is complete.

const RAEconomy := preload("res://scripts/sim/economy.gd")
const RAMarket := preload("res://scripts/sim/market.gd")


func before() -> void:
	WorldGen.setup(1066)


func _eco() -> RAEconomy:
	var e := RAEconomy.new()
	e.setup(0)
	e.bind_home_market(0, RAMarket.new())
	e.road_risk = {1: 0.4, 3: 0.9}
	e.civ_price_mult = {2: 1.3}
	return e


## A second economy with exactly the same goods and stock as `src` (building one stocks some markets from random rolls, so two
## fresh economies are not guaranteed to be twins; the test needs identical starting states).
func _twin(src: RAEconomy) -> RAEconomy:
	var e := _eco()
	for id in src.markets:
		var a: RAMarket = src.markets[id]
		var b := RAMarket.new()
		b.base_price = a.base_price.duplicate()
		b.stock = a.stock.duplicate()
		b.target = a.target.duplicate()
		b.produce = a.produce.duplicate()
		b.imports = a.imports.duplicate()
		b.demand_scale = a.demand_scale.duplicate()
		b.purse = a.purse
		b._carry = a._carry.duplicate()
		b._purse_carry = a._purse_carry
		b.modifiers = a.modifiers.duplicate()
		e.markets[id] = b
	return e


func _ctx(h: int) -> Dictionary:
	var day := h / 24
	var seasons := ["spring", "summer", "autumn", "winter"]
	return {"season": seasons[(day / 2) % 4], "festival": day % 3 == 1, "at_war": day % 4 >= 2, "mine_opened": day >= 3,
		"abs_hours": float(h)}


# --- the pre-optimisation algorithm, verbatim ---------------------------------------------------------------------

func _ref_market_tick(m: RAMarket, dh: float, population: int) -> void:
	var frac := clampf(dh, 0.0, 24.0) / 24.0
	var k := clampf(population / 60.0, 0.3, 2.0)
	for item: String in m.stock:
		var cur := int(m.stock[item])
		var acc := float(m._carry.get(item, 0.0)) + (float(m.produce[item]) - RAMarket.DEMAND_RATE * float(m.demand_scale.get(item, 1.0)) * k * float(cur)) * frac     # C13: gear and tools see a tenth of the food demand (market.gd demand_scale)
		var whole := floori(acc)
		var cap := int(m.target[item]) * 3
		var nxt := clampi(cur + whole, 0, cap)
		m._carry[item] = acc - float(whole) if nxt == cur + whole else 0.0
		m.stock[item] = nxt
	if m.purse >= 600:
		m.purse = 600
		m._purse_carry = 0.0
	else:
		var income := 15.0 * frac + m._purse_carry
		var whole_income := floori(income)
		m.purse = mini(m.purse + whole_income, 600)
		m._purse_carry = income - float(whole_income) if m.purse < 600 else 0.0


func _ref_population(id: int) -> int:
	for s: Dictionary in WorldGen.settlements:
		if int(s["id"]) == id:
			return int(s.get("population", 100))
	return 100


func _ref_capital(id: int) -> bool:
	for s: Dictionary in WorldGen.settlements:
		if int(s["id"]) == id:
			return String(s.get("kind", "")) == "castle"
	return false


func _ref_modifiers(e: RAEconomy, id: int, m: RAMarket, ctx: Dictionary) -> void:
	var risk := clampf(float(e.road_risk.get(id, 0.0)), 0.0, 1.0)
	var civ_mult := clampf(float(e.civ_price_mult.get(id, 1.0)), 0.5, 2.0)
	var season := String(ctx["season"])
	for item: String in m.base_price:
		var mult := civ_mult
		if int(m.produce.get(item, 0)) <= 0:
			mult *= 1.0 + risk * RAEconomy.IMPORT_RISK_MULT
		if season == "winter" and item in RAEconomy.FOOD_ITEMS:
			mult *= RAEconomy.WINTER_FOOD_MULT
		if season == "autumn" and item == "wheat":
			mult *= RAEconomy.HARVEST_GRAIN_MULT
		if bool(ctx["festival"]) and item in RAEconomy.FESTIVAL_GOODS:
			mult *= RAEconomy.FESTIVAL_MULT
		if bool(ctx["at_war"]) and item in RAEconomy.WAR_GOODS:
			mult *= RAEconomy.WAR_MULT
		if bool(ctx["mine_opened"]) and item == RAEconomy.MINE_GOOD:
			mult *= RAEconomy.MINE_OPENED_MULT
		if RAEconomy.SCAR_GOODS.has(item):
			mult *= e.scar_price_mult
		m.set_modifier(item, mult)


func _ref_trade_surplus(e: RAEconomy) -> void:
	var items := {}
	for id in e.markets:
		for item: String in (e.markets[id] as RAMarket).base_price:
			items[item] = true
	for item: String in items:
		var donors: Array = []
		var needy: Array = []
		for id in e.markets:
			var m: RAMarket = e.markets[id]
			var t := float(m.target.get(item, 0))
			if t <= 0.0:
				continue
			var ratio := float(m.stock.get(item, 0)) / t
			if ratio > RAEconomy.TRADE_SURPLUS_RATIO and int(m.produce.get(item, 0)) > 0:
				donors.append([id, ratio])
			elif ratio < RAEconomy.TRADE_SHORT_RATIO:
				needy.append([id, ratio])
		if donors.is_empty() or needy.is_empty():
			continue
		donors.sort_custom(func(a: Array, b: Array) -> bool: return float(a[1]) > float(b[1]))
		needy.sort_custom(func(a: Array, b: Array) -> bool: return float(a[1]) < float(b[1]))
		var di := 0
		for n: Array in needy:
			var nm: RAMarket = e.markets[n[0]]
			var want := (RAEconomy.TRADE_SURPLUS_RATIO - 0.25 - float(n[1])) * float(nm.target[item]) * 0.5
			var keep := 1.0 - RAEconomy.IMPORT_RISK_CUT * clampf(float(e.road_risk.get(n[0], 0.0)), 0.0, 1.0)
			while want >= 0.5 and di < donors.size():
				var dm: RAMarket = e.markets[donors[di][0]]
				var surplus := float(dm.stock[item]) - RAEconomy.TRADE_SURPLUS_RATIO * float(dm.target[item]) * 0.9
				var give := minf(want, surplus * 0.5)
				if give < 0.5:
					di += 1
					continue
				dm.add_stock(item, -give)
				nm.add_stock(item, give * keep)
				want -= give
				donors[di][1] = float(dm.stock[item]) / float(dm.target[item])


func _ref_tick_hour(e: RAEconomy, dh: float, ctx: Dictionary) -> void:
	for id in e.markets:
		var m: RAMarket = e.markets[id]
		_ref_market_tick(m, dh, _ref_population(id))
		if _ref_capital(id):
			e._extra_capital_food_drain(m, dh)
		_ref_modifiers(e, id, m, ctx)
	if int(float(ctx["abs_hours"])) % 24 == 6:
		for id in e.markets:
			var m2: RAMarket = e.markets[id]
			var risk := clampf(float(e.road_risk.get(id, 0.0)), 0.0, 1.0)
			for item: String in m2.imports:
				m2.add_stock(item, float(m2.imports[item]) * (1.0 - RAEconomy.IMPORT_RISK_CUT * risk))
		_ref_trade_surplus(e)


func _state(e: RAEconomy) -> Dictionary:
	var out := {}
	for id in e.markets:
		var m: RAMarket = e.markets[id]
		var carry := {}
		for item: String in m._carry:
			if float(m._carry[item]) != 0.0:       # a zero carry and no entry mean the same thing
				carry[item] = m._carry[item]
		out[id] = {"stock": m.stock.duplicate(), "carry": carry, "purse": m.purse, "pc": m._purse_carry,
			"mods": m.modifiers.duplicate()}
	return out


func _assert_same(a: RAEconomy, b: RAEconomy, why: String) -> void:
	var sa := _state(a)
	var sb := _state(b)
	assert_int(sa.size()).is_equal(sb.size())
	for id in sa:
		for key: String in ["stock", "carry", "purse", "pc", "mods"]:
			if sa[id][key] != sb[id][key]:
				var detail := ""
				if sa[id][key] is Dictionary:
					for item in sa[id][key]:
						if not (sb[id][key] as Dictionary).has(item) or sa[id][key][item] != sb[id][key][item]:
							detail = " (first: %s %s vs %s)" % [item, str(sa[id][key][item]), str((sb[id][key] as Dictionary).get(item))]
							break
				fail("%s: market %s differs in %s%s" % [why, str(id), key, detail])
				return


func test_synchronous_tick_matches_the_old_algorithm() -> void:
	var fast := _eco()
	var ref := _twin(fast)
	for h in range(1, 24 * 5):
		fast.tick_hour(1.0, _ctx(h))
		_ref_tick_hour(ref, 1.0, _ctx(h))
		if h % 19 == 0:
			_assert_same(fast, ref, "hour %d" % h)
	_assert_same(fast, ref, "after 5 days")


func test_queued_jobs_match_the_synchronous_tick() -> void:
	var queued := _eco()
	var ref := _twin(queued)
	for h in range(1, 24 * 4):
		var jobs := queued.queue_hour_jobs(1.0, _ctx(h))
		assert_bool(queued.has_pending_hour_jobs()).is_true()
		for cb in jobs:
			cb.call()
		assert_bool(queued.has_pending_hour_jobs()).is_false()
		_ref_tick_hour(ref, 1.0, _ctx(h))
	_assert_same(queued, ref, "queued vs reference")


func test_a_save_halfway_through_an_hour_is_complete() -> void:
	var queued := _eco()
	var ref := _twin(queued)
	for h in range(1, 30):
		queued.queue_hour_jobs(1.0, _ctx(h))
		_ref_tick_hour(ref, 1.0, _ctx(h))
		var data := queued.serialize()      # nothing has run yet: serialize finishes the pending jobs
		assert_bool(queued.has_pending_hour_jobs()).is_false()
		assert_bool(data.has("markets")).is_true()
	_assert_same(queued, ref, "serialize flush")
	# the hub-side callables that are left over are harmless no-ops
	var cbs := queued.queue_hour_jobs(1.0, _ctx(40))
	queued.serialize()
	for cb in cbs:
		cb.call()
	_ref_tick_hour(ref, 1.0, _ctx(40))
	_assert_same(queued, ref, "late callables")


func test_modifiers_follow_changed_inputs_and_new_goods() -> void:
	var fast := _eco()
	var ref := _twin(fast)
	for h in range(1, 6):
		fast.tick_hour(1.0, _ctx(h))
		_ref_tick_hour(ref, 1.0, _ctx(h))
	# road danger, a civilisation price swing, the Scar and a good added later all change the modifiers
	for e: RAEconomy in [fast, ref]:
		e.road_risk[2] = 0.7
		e.civ_price_mult[4] = 0.6
		e.scar_price_mult = 1.5
		(e.markets[0] as RAMarket).add_good("test_good", 5, 10, 0)
	for h in range(6, 10):
		fast.tick_hour(1.0, _ctx(h))
		_ref_tick_hour(ref, 1.0, _ctx(h))
	_assert_same(fast, ref, "inputs changed")
	# a save/load clears the cached signature: the next tick rebuilds the same values the reference computes
	for id in fast.markets:
		var m: RAMarket = fast.markets[id]
		m.deserialize(m.serialize())
		assert_array(m.mods_sig).is_empty()
	fast.tick_hour(1.0, _ctx(10))
	_ref_tick_hour(ref, 1.0, _ctx(10))
	_assert_same(fast, ref, "after a reload")
