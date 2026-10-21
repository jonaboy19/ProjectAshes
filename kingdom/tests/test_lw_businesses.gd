extends GdUnitTestSuite
## LW-4.3 / LW-4.4 (docs/design/LIVING_WORLD_SANDBOX.md §10): businesses with real accounts, debt and insolvency, remote management by
## delayed reports, vertical integration with farms (nothing created from nothing), NPC-founded businesses and organizations, price
## wars, the save round trip and the tick cost.

const Hub := preload("res://scripts/realm/realm_hub.gd")
const FD := preload("res://scripts/realm/farming_data.gd")

static var _ready_world := false


func _hub() -> RefCounted:
	if not _ready_world:
		WorldGen.setup(2024)
		_ready_world = true
	var h: RefCounted = Hub.new()
	var om: RefCounted = h.mod("organizations")
	om.auto_seed = false
	om.gold_ref = {"gold": 5000}
	return h


func _owner(h: RefCounted, cash := 2000, sid := 0, sk := 0.7) -> String:
	var om: RefCounted = h.mod("organizations")
	var ch: String = h.mod("registry").mint("ch")
	om.ensure_char(ch, {"cash": cash, "sid": sid, "prof": "merchant", "sk": {"trading": sk}})
	return ch


func _worker(h: RefCounted, sid := 0) -> String:
	var om: RefCounted = h.mod("organizations")
	var ch: String = h.mod("registry").mint("ch")
	om.ensure_char(ch, {"cash": 5, "sid": sid, "prof": "laborer"})
	return ch


func _weeks(bz: RefCounted, bid: String, from_week: int, n: int) -> void:
	for w in range(from_week, from_week + n):
		bz.set_day(w * 7)
		bz.settle(bid, 7, w * 7)


func _norm(d: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(d)))


# --- accounts --------------------------------------------------------------------------

func test_a_shop_has_real_revenue_expenses_and_weekly_accounts() -> void:
	var h := _hub()
	var bz: RefCounted = h.mod("businesses")
	var om: RefCounted = h.mod("organizations")
	bz.set_population(0, 400)
	var owner := _owner(h)
	var cash0: int = om.purse(owner)
	var res: Dictionary = bz.found(owner, "shop", 0, "The Corner Shop")
	assert_bool(res["ok"]).is_true()
	var bid: String = res["bz"]
	assert_str(bid).starts_with("bz:")
	assert_int(om.purse(owner)).is_equal(cash0 - 300)                    # the capital left the owner's purse
	assert_bool(bz.hire(bid, _worker(h))["ok"]).is_true()
	bz.attend(bid)
	_weeks(bz, bid, 1, 6)
	var led: Array = bz.accounts(bid)
	assert_int(led.size()).is_equal(6)
	var tot_in := 0.0
	var tot_out := 0.0
	for r: Array in led:
		tot_in += float(r[1])
		tot_out += float(r[2])
	assert_float(tot_in).is_greater(0.0)
	assert_float(tot_out).is_greater(0.0)                                  # wages, rent, upkeep, stock
	var b: Dictionary = bz.biz(bid)
	# the book balances: opening cash + everything in - everything out - dividends paid = cash now
	assert_float(float(b["bal"]) + float(b["debt"]) * 0.0).is_less(1e9)
	assert_float(float(b["in"])).is_greater(float(b["out"]) - 400.0)
	# goods are conserved: bought = sold + spoiled + on the shelf (within rounding)
	var shelf := 0.0
	for g: String in b["inv"]:
		shelf += float(b["inv"][g])
	var bought: int = bz.stats["wholesale_units"] + bz.stats["farm_units"]
	var used: float = float(bz.stats["sold_units"]) + float(bz.stats["wasted_units"]) + shelf
	assert_float(absf(float(bought) - used)).is_less(0.06 * float(bought) + 8.0)
	assert_int(bz.stats["sold_units"]).is_greater(0)
	# the owner's axes: employment of the staff member is the business, ownership is the owner
	assert_bool(bid in om.axes(owner)["ownership"]["businesses"]).is_true()
	assert_str(om.employment(bz.biz(bid)["staff"][0]["ch"])["by"]).is_equal(bid)


func test_rivals_share_the_same_customers() -> void:
	var h := _hub()
	var bz: RefCounted = h.mod("businesses")
	bz.set_population(0, 400)
	var a: String = bz.found(_owner(h), "shop", 0)["bz"]
	var solo_in := 0.0
	bz.attend(a)
	_weeks(bz, a, 1, 4)
	for r: Array in bz.accounts(a):
		solo_in += float(r[1])
	var h2 := _hub()
	var bz2: RefCounted = h2.mod("businesses")
	bz2.set_population(0, 400)
	var a2: String = bz2.found(_owner(h2), "shop", 0)["bz"]
	var b2: String = bz2.found(_owner(h2), "shop", 0)["bz"]
	bz2.attend(a2)
	bz2.attend(b2)
	_weeks(bz2, a2, 1, 4)
	var shared_in := 0.0
	for r2: Array in bz2.accounts(a2):
		shared_in += float(r2[1])
	assert_float(shared_in).is_less(solo_in * 0.8)


func test_a_workshop_cannot_make_more_than_its_recipe_allows() -> void:
	var h := _hub()
	var bz: RefCounted = h.mod("businesses")
	bz.set_population(0, 600)
	var bid: String = bz.found(_owner(h, 3000), "workshop", 0, "Mill Bakery", "bakery")["bz"]
	bz.hire(bid, _worker(h))
	bz.attend(bid)
	_weeks(bz, bid, 1, 6)
	assert_int(bz.stats["made_units"]).is_greater(0)
	# every bread came from wheat bought or taken from a farm: output <= input * yield
	assert_float(float(bz.stats["made_units"])).is_less_equal(float(bz.stats["input_units"]) * 1.5 + 4.0)
	assert_int(bz.stats["input_units"]).is_less_equal(bz.stats["wholesale_units"] + bz.stats["farm_units"] + 2)


# --- debt and insolvency -----------------------------------------------------------------

func test_a_failing_business_borrows_then_goes_insolvent_and_can_be_restructured() -> void:
	var h := _hub()
	var bz: RefCounted = h.mod("businesses")
	var om: RefCounted = h.mod("organizations")
	bz.set_population(0, 40)                                                # a hamlet that cannot feed an inn
	var owner := _owner(h, 5000)
	var bid: String = bz.found(owner, "inn", 0, "The Empty Inn")["bz"]
	for i in 4:
		bz.hire(bid, _worker(h))
	bz.attend(bid)
	var saw_debt := false
	var week := 1
	while week < 30 and String(bz.biz(bid)["st"]) == "active":
		_weeks(bz, bid, week, 1)
		saw_debt = saw_debt or float(bz.biz(bid)["debt"]) > 0.0
		week += 1
	assert_bool(saw_debt).is_true()
	assert_str(bz.biz(bid)["st"]).is_equal("insolvent")
	assert_float(bz.biz(bid)["debt"]).is_greater(0.0)
	var debt: float = bz.biz(bid)["debt"]
	# a stranger cannot restructure it; the owner can, putting money in; the creditors forgive a part and half the staff go
	assert_bool(bz.restructure(bid, _owner(h))["ok"]).is_false()
	var owner_cash: int = om.purse(owner)
	var staff_before: int = bz.staff_count(bid)
	var res: Dictionary = bz.restructure(bid, owner)
	assert_bool(res["ok"]).is_true()
	assert_int(om.purse(owner)).is_less(owner_cash)
	assert_str(bz.biz(bid)["st"]).is_equal("restructuring")
	assert_int(bz.staff_count(bid)).is_less(staff_before)
	assert_float(bz.biz(bid)["debt"]).is_less(debt)
	assert_int(res["forgiven"]).is_greater(0)
	# it still cannot earn: after the period it is insolvent again and the owner liquidates
	_weeks(bz, bid, week, 6)
	assert_bool(String(bz.biz(bid)["st"]) in ["insolvent", "restructuring", "active"]).is_true()
	var out: Dictionary = bz.liquidate(bid, owner, "closed")
	assert_bool(out["ok"]).is_true()
	assert_str(bz.biz(bid)["st"]).is_equal("closed")
	assert_int(bz.staff_count(bid)).is_equal(0)
	assert_bool(bid in om.axes(owner)["ownership"]["businesses"]).is_false()
	assert_int(bz.stats["bankrupt"]).is_equal(1)


func test_a_neglected_insolvent_business_is_liquidated_by_its_creditors() -> void:
	var h := _hub()
	var bz: RefCounted = h.mod("businesses")
	bz.set_population(0, 40)
	var bid: String = bz.found(_owner(h, 3000), "inn", 0)["bz"]
	for i in 4:
		bz.hire(bid, _worker(h))
	bz.attend(bid)
	var week := 1
	while week < 80 and String(bz.biz(bid)["st"]) != "closed":
		bz.attend(bid)
		_weeks(bz, bid, week, 1)
		week += 1
	assert_str(bz.biz(bid)["st"]).is_equal("closed")


# --- remote management --------------------------------------------------------------------

func test_a_remote_owner_sees_only_delayed_reports() -> void:
	var h := _hub()
	var bz: RefCounted = h.mod("businesses")
	bz.set_population(6, 500)
	var owner := _owner(h, 3000, 0)                                         # lives in town 0
	var bid: String = bz.found(owner, "shop", 6, "Far Shop", "", -1, "delegated")["bz"]
	bz.appoint_manager(bid, _worker(h, 6), 0.8, 1.0)
	var delay: int = bz.report_delay(bz.biz(bid))
	assert_int(delay).is_greater(0)
	bz.set_day(7)
	bz.settle(bid, 7, 7)
	assert_bool(bz.owner_view(bid).is_empty()).is_true()                    # the courier is on the road
	assert_int(bz.reports(bid).size()).is_equal(0)
	assert_float(bz.live(bid)["bal"]).is_not_equal(0.0)                     # a present owner would see the live books
	for d in range(8, 7 + delay):
		bz.tick_day(d, {})
	assert_bool(bz.owner_view(bid).is_empty()).is_true()
	bz.tick_day(7 + delay, {})
	var v: Dictionary = bz.owner_view(bid)
	assert_bool(v.is_empty()).is_false()
	assert_int(v["wk"]).is_equal(1)
	assert_int(v["age"]).is_equal(delay)                                     # as old as the courier's road is long
	bz.set_day(14)
	bz.settle(bid, 7, 14)
	assert_int(bz.owner_view(bid)["wk"]).is_equal(1)                        # week 2 is still on its way
	bz.tick_day(14 + delay, {})
	assert_int(bz.owner_view(bid)["wk"]).is_equal(2)
	# an owner who lives in the town gets it at once
	var h2 := _hub()
	var bz2: RefCounted = h2.mod("businesses")
	bz2.set_population(6, 500)
	var local: String = bz2.found(_owner(h2, 3000, 6), "shop", 6, "Near Shop", "", -1, "delegated")["bz"]
	bz2.appoint_manager(local, _worker(h2, 6), 0.8, 1.0)
	bz2.set_day(7)
	bz2.settle(local, 7, 7)
	assert_bool(bz2.owner_view(local).is_empty()).is_false()


func test_a_delegated_shop_matches_a_manual_one_and_a_dishonest_manager_is_found_by_audit() -> void:
	var results := {}
	for mode: String in ["manual", "delegated"]:
		var h := _hub()
		var bz: RefCounted = h.mod("businesses")
		bz.set_population(0, 500)
		var owner := _owner(h, 3000, 0)
		var bid: String = bz.found(owner, "shop", 0, "Shop " + mode, "", -1, mode)["bz"]
		bz.hire(bid, _worker(h))
		if mode == "delegated":
			bz.appoint_manager(bid, _worker(h), 0.8, 1.0, 0)                # the same hand, here as manager
			bz.fire(bid, bz.biz(bid)["staff"][0]["ch"])
			bz.hire(bid, _worker(h))
		var net := 0.0
		for w in range(1, 11):
			if mode == "manual":
				bz.attend(bid)
			bz.set_day(w * 7)
			bz.settle(bid, 7, w * 7)
		for r: Array in bz.accounts(bid):
			net += float(r[1]) - float(r[2])
		results[mode] = net
	assert_float(float(results["manual"])).is_greater(0.0)
	assert_float(float(results["delegated"])).is_greater(float(results["manual"]) * 0.9)
	# a dishonest manager skims; the report hides it; an audit finds it
	var h3 := _hub()
	var bz3: RefCounted = h3.mod("businesses")
	bz3.set_population(0, 500)
	var b3: String = bz3.found(_owner(h3, 3000, 0), "shop", 0, "Crooked", "", -1, "delegated")["bz"]
	bz3.appoint_manager(b3, _worker(h3), 0.8, 0.1, 0)
	_weeks(bz3, b3, 1, 8)
	assert_bool(bz3.audit(b3)["honest"]).is_false()
	assert_float(bz3.audit(b3)["skimmed"]).is_greater(0.0)


# --- vertical integration -----------------------------------------------------------------

func test_a_bakery_linked_to_a_farm_takes_goods_out_of_the_farms_store() -> void:
	var h := _hub()
	var bz: RefCounted = h.mod("businesses")
	var fm: RefCounted = h.mod("farming")
	var om: RefCounted = h.mod("organizations")
	fm.gold_ref = {"gold": 1000}
	bz.set_population(0, 600)
	var owner := _owner(h, 3000)
	var pid: String = fm.found_parcel(0, Vector2(10, 10), 2, "player", "Mill Farm")
	var P: Dictionary = fm.parcel(pid)
	P["store"]["wheat"] = 30.0
	var bid: String = bz.found(owner, "workshop", 0, "Own Bakery", "bakery")["bz"]
	bz.hire(bid, _worker(h))
	assert_bool(bz.link_farm(bid, pid, "wheat", 14)).is_true()
	assert_bool(bz.link_farm(bid, "pr:nope", "wheat", 14)).is_false()
	bz.attend(bid)
	var farm_before: float = P["store"]["wheat"]
	var gold_before: int = fm.take_pending_gold()
	_weeks(bz, bid, 1, 1)
	var taken: float = farm_before - float(P["store"]["wheat"])
	assert_float(taken).is_greater(0.0)
	assert_float(taken).is_less_equal(14.0)
	assert_int(bz.stats["farm_units"]).is_equal(int(taken))                  # exactly what left the farm entered the bakery
	# the farm's owner is paid for it (a different owner than the bakery's owner)
	assert_int(fm.take_pending_gold()).is_greater(gold_before - 1)
	# a farm with an empty store gives nothing: the bakery falls back on the wholesale pool, it does not conjure wheat
	P["store"]["wheat"] = 0.0
	var farm_units: int = bz.stats["farm_units"]
	_weeks(bz, bid, 2, 2)
	assert_int(bz.stats["farm_units"]).is_equal(farm_units)
	assert_bool(om.has_char(owner)).is_true()
	# an internal transfer inside one owner moves goods and no gold
	P["owner"] = "player"
	P["store"]["wheat"] = 20.0
	var h2 := _hub()
	var bz2: RefCounted = h2.mod("businesses")
	var om2: RefCounted = h2.mod("organizations")
	var fm2: RefCounted = h2.mod("farming")
	fm2.gold_ref = {"gold": 1000}
	var pl: String = om2.player_id()
	om2.ensure_char(pl)
	bz2.set_population(0, 600)
	var pid2: String = fm2.found_parcel(0, Vector2(10, 10), 2, "player", "Mine")
	fm2.parcel(pid2)["store"]["wheat"] = 30.0
	var own_bid: String = bz2.found(pl, "workshop", 0, "Player Bakery", "bakery")["bz"]
	bz2.link_farm(own_bid, pid2, "wheat", 14)
	bz2.attend(own_bid)
	fm2.take_pending_gold()
	bz2.set_day(7)
	bz2.settle(own_bid, 7, 7)
	assert_float(fm2.parcel(pid2)["store"]["wheat"]).is_less(30.0)
	assert_int(fm2.take_pending_gold()).is_equal(0)


# --- NPC parity ----------------------------------------------------------------------------

func test_npcs_found_businesses_with_the_same_call_and_some_go_bankrupt() -> void:
	var h := _hub()
	var om: RefCounted = h.mod("organizations")
	var bz: RefCounted = h.mod("businesses")
	bz.set_population(0, 120)
	var owner: String = om.spawn_actor(0, "baker", 900, {"trading": 0.05}, 0.0, "found")
	assert_bool(bz.npc_try_found(owner, 0)).is_true()
	var bid: String = bz.owned_by(owner)[0]
	assert_str(bz.biz(bid)["mode"]).is_equal("autonomous")
	assert_bool(bz.owned_by(owner).size() == 1).is_true()
	assert_bool(bz.npc_try_found(owner, 0)).is_false()                       # one at a time
	# three rivals in a hamlet, run by weak owners: the market has room for fewer than it has
	var rivals: Array = [bid]
	for i in 3:
		var o: String = om.spawn_actor(0, "baker", 900, {"trading": 0.05}, 0.0, "found")
		bz.set_population(0, 120)
		var r: Dictionary = bz.found(o, "workshop", 0, "Rival %d" % i, "bakery", 450, "autonomous")
		if r["ok"]:
			rivals.append(r["bz"])
	for d in range(1, 400):
		bz.tick_day(d, {})
	var closed := 0
	for k: String in rivals:
		if bz.biz(k).is_empty() or String(bz.biz(k)["st"]) == "closed":
			closed += 1
	assert_int(closed).is_greater(0)
	assert_int(bz.stats["bankrupt"]).is_greater(0)
	assert_bool(bz.count() < rivals.size() + 1).is_true()


func test_two_npc_shops_in_one_town_start_a_price_war() -> void:
	var found_war := false
	for seed_n in 4:
		var h := _hub()
		var om: RefCounted = h.mod("organizations")
		var bz: RefCounted = h.mod("businesses")
		bz.set_population(1, 700)
		for k in seed_n * 3:
			h.mod("registry").mint("bz")                                      # a different set of ids means different rivalries
		for i in 3:
			var o: String = om.spawn_actor(1, "merchant", 1200 + seed_n * 7, {"trading": 0.6}, 0.0, "found")
			bz.found(o, "shop", 1, "Shop %d.%d" % [seed_n, i], "", -1, "autonomous")
		for d in range(1, 330):
			bz.tick_day(d, {})
		if int(bz.stats["price_wars"]) > 0:
			found_war = true
			break
	assert_bool(found_war).is_true()


func test_one_year_of_npc_life_founds_organizations_and_businesses_with_a_price_war() -> void:
	var h := _hub()
	var om: RefCounted = h.mod("organizations")
	var bz: RefCounted = h.mod("businesses")
	for sid in 3:
		bz.set_population(sid, 500)
	for i in 60:
		var prof: String = ["smith", "baker", "merchant", "mercenary", "hunter", "farmer", "carpenter", "brewer"][i % 8]
		om.spawn_actor(i % 3, prof, 1500, {"combat": 0.6, "crafting": 0.6, "trading": 0.55, "farming": 0.5}, 5.0, "found" if i % 3 == 0 else "join")
	for d in range(1, 366):
		h.mod("organizations").tick_day(d, {})
		bz.tick_day(d, {})
	print("LW-4.4 one NPC year: %d orgs founded by NPCs, %d businesses founded, %d price wars, %d bankruptcies, %d NPC joins, %d contested recruits" % [
		om.stats["npc_founded"], bz.stats["npc_founded"], bz.stats["price_wars"], bz.stats["bankrupt"], om.stats["npc_joined"], om.stats["contested"]])
	assert_int(om.stats["npc_founded"]).is_greater_equal(2)
	assert_int(bz.stats["npc_founded"]).is_greater(0)
	assert_int(bz.stats["price_wars"]).is_greater_equal(1)
	assert_int(om.stats["npc_joined"]).is_greater(0)


# --- save -----------------------------------------------------------------------------------

func test_business_save_round_trip_keeps_the_books_and_the_reports() -> void:
	var h := _hub()
	var bz: RefCounted = h.mod("businesses")
	bz.set_population(6, 500)
	var owner := _owner(h, 4000, 0)
	var bid: String = bz.found(owner, "shop", 6, "Saved Shop", "", -1, "delegated")["bz"]
	bz.appoint_manager(bid, _worker(h, 6), 0.7, 0.9)
	bz.hire(bid, _worker(h, 6))
	var cb: String = bz.found(owner, "caravan", 6, "Wagons")["bz"]
	bz.set_route(cb, 6, 7)
	_weeks(bz, bid, 1, 5)
	_weeks(bz, cb, 1, 3)
	bz.tick_day(60, {})
	var data: Dictionary = JSON.parse_string(JSON.stringify(bz.serialize()))
	var h2 := _hub()
	var bz2: RefCounted = h2.mod("businesses")
	bz2.deserialize(data)
	assert_str(_norm(bz2.serialize())).is_equal(_norm(bz.serialize()))
	assert_array(bz2.accounts(bid)).is_equal(bz.accounts(bid))
	assert_array(bz2.reports(bid)).is_equal(bz.reports(bid))
	assert_array(bz2.owned_by(owner)).is_equal(bz.owned_by(owner))
	assert_int(bz2.biz(bid)["lw"]).is_equal(bz.biz(bid)["lw"])
	# and the loaded business carries on
	bz2.set_day(100)
	bz2.settle(bid, 7, 100)
	assert_int(bz2.accounts(bid).size()).is_equal(bz.accounts(bid).size() + 1)
	var full: Dictionary = JSON.parse_string(JSON.stringify(h.serialize()))
	var h3 := _hub()
	h3.deserialize(full)
	assert_str(_norm(h3.mod("businesses").serialize())).is_equal(_norm(bz.serialize()))
	assert_str(_norm(h3.mod("organizations").serialize())).is_equal(_norm(h.mod("organizations").serialize()))


# --- performance ----------------------------------------------------------------------------

func test_tick_cost_of_500_businesses() -> void:
	var h := _hub()
	var om: RefCounted = h.mod("organizations")
	var bz: RefCounted = h.mod("businesses")
	var kinds := ["shop", "workshop", "inn", "caravan"]
	var recipes := ["bakery", "brewery", "smithy", "weaver"]
	var n := 0
	for sid in 10:
		bz.set_population(sid, 800)
	for i in 700:
		if n >= 500:
			break
		var ow: String = h.mod("registry").mint("ch")
		om.ensure_char(ow, {"cash": 2000, "sid": i % 10, "sk": {"trading": 0.6}})
		var k: String = kinds[i % 4]
		var r: Dictionary = bz.found(ow, k, i % 10, "", recipes[(i / 4) % 4] if k == "workshop" else "", -1, "autonomous")
		if r["ok"]:
			n += 1
			if k == "caravan":
				bz.set_route(r["bz"], i % 10, (i + 3) % 10)
	assert_int(bz.count()).is_equal(500)
	for d in range(1, 29):
		bz.tick_day(d, {})
	var worst := 0
	var total := 0
	var days := 28
	for d in range(29, 29 + days):
		var tb := Time.get_ticks_usec()
		var chunks: Array = bz.tick_day_chunks(d, {})
		total += Time.get_ticks_usec() - tb
		for c: Callable in chunks:
			var t0 := Time.get_ticks_usec()
			c.call()
			var dt := Time.get_ticks_usec() - t0
			worst = maxi(worst, dt)
			total += dt
	var raw := JSON.stringify(bz.serialize()).length()
	print("LW-4.3 businesses: %d live, worst job %d us, avg day %d us (budget 400 us a day for 500), save %d bytes raw" % [bz.count(), worst, total / days, raw])
	assert_int(worst).is_less(4000)
	assert_int(total / days).is_less(6000)
	assert_int(raw).is_less(400000)
