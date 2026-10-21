extends GdUnitTestSuite
## Living World Stage 3: the farming career (scripts/realm/farming.gd + farming_fields.gd + farming_herd.gd).
## Ladder transitions, field fertility and rotation, pest spread and cure, livestock lifecycle (near, far, the fold between), a sale that
## keeps the debt and the tenant, worker-run work equal to manual, an NPC outbidding the player, NPC farmers (expand, bust), expansion
## through construction sites, market supply and garrison contracts, save round trip, per-tick cost.

const Hub := preload("res://scripts/realm/realm_hub.gd")
const D := preload("res://scripts/realm/farming_data.gd")
const FF := preload("res://scripts/realm/farming_fields.gd")
const FH := preload("res://scripts/realm/farming_herd.gd")
const Rec := preload("res://scripts/realm/recruitment.gd")
const FAR := Vector2(1e9, 1e9)
const CTX := {"season": "spring", "at_war": false, "abs_hours": 0, "gold": 1000, "player_pos": Vector2(1e9, 1e9), "life": null}

var _gold := {"gold": 2000}


func before() -> void:
	WorldGen.setup(2024)


func _farming(markets := true) -> Array:
	var hub: RefCounted = Hub.new()
	var f: RefCounted = hub.mod("farming")
	_gold = {"gold": 2000}
	f.gold_ref = _gold
	var mk := {}
	if markets:
		for sid in 3:
			var m := RAMarket.new()
			m.add_good("wheat", 2, 40, 0)
			m.add_good("milk", 3, 20, 0)
			m.add_good("wool", 5, 20, 0)
			m.add_good("barley", 2, 30, 0)
			m.purse = 5000
			mk[sid] = m
	f.market_ref = mk
	f.set_day(100)
	f._inited = true        # no world farms unless a test asks for them
	return [hub, f]


## One parcel with fields in a known state.
func _plot(f: RefCounted, owner := "lord:0", fields := 4, fert := 0.8) -> String:
	return f.found_parcel(0, Vector2(100, 100), fields, owner, "Test Farm", fert)


func _ctx(pos: Vector2) -> Dictionary:
	var c := CTX.duplicate()
	c["player_pos"] = pos
	return c


func _spring_env() -> Dictionary:
	return {"season": D.SPRING, "clim": 1, "irr_ok": true}


func _grow(F: Dictionary, crop: String, day: int) -> int:
	FF.sow(F, crop, day)
	F["irr"] = 1
	var n := 0
	while not FF.is_ready(F) and n < 200:
		FF.step(F, _spring_env(), 1.0, null)
		n += 1
	return FF.harvest_yield(F, 1)


# ---------------------------------------------------------------- ladder

func test_ladder_farmhand_to_estate() -> void:
	var a := _farming()
	var hub: RefCounted = a[0]
	var f: RefCounted = a[1]
	f.add_farmer("npc:9001", 0, 400, 0.5, -1, "Old Bram")
	var farm := _plot(f)
	assert_bool(hub.mod("registry").is_pid(farm)).is_true()           # a parcel is the identity layer's "pr:<n>"
	assert_str(farm.substr(0, 3)).is_equal("pr:")
	assert_str(f.rent_out(farm, "npc:9001", "rent", 20, 0.0, 112)).is_empty()
	assert_str(f.rung()).is_equal("")
	assert_array(f.jobs(0)).contains([farm])
	# Strangers cannot rent or buy.
	var vac := _plot(f)
	assert_str(f.take_tenancy(vac, "rent")).is_not_empty()
	assert_str(f.buy_direct(vac, "player")).is_not_empty()
	# Farmhand: wage work for the NPC farmer.
	assert_str(f.hire_on(farm)).is_empty()
	assert_str(f.rung()).is_equal("farmhand")
	var g0: int = f.gold_available()
	var cash0: int = int(f.farmer("npc:9001")["cash"])
	for d in 6:
		var r: Dictionary = f.farmhand_work(farm, 100 + d)
		assert_bool(r["ok"]).is_true()
	assert_int(f.gold_available() - g0).is_equal(6 * f.WAGE_HAND)
	assert_int(int(f.farmer("npc:9001")["cash"])).is_less(cash0)           # the farmer paid it
	assert_bool(f.farmhand_work(farm, 105)["ok"]).is_false()               # one workday a day
	assert_int(f.experience()).is_greater_equal(6)
	# Sharecropper, then tenant (the rent kind needs the experience).
	assert_str(f.take_tenancy(vac, "share")).is_empty()
	assert_str(f.rung()).is_equal("sharecropper")
	assert_str(f.end_tenancy(vac)).is_empty()
	assert_str(f.take_tenancy(vac, "rent")).is_empty()
	assert_str(f.rung()).is_equal("tenant")
	assert_int(int(f.parcel(vac)["ten"]["dep"])).is_greater(0)           # a deposit was taken
	# Owner needs a season behind a plough: the rent falls due and is paid.
	assert_str(f.buy_direct(_plot(f), "player")).is_not_empty()
	for d in range(101, 131):
		f.tick_day(d, CTX)
	assert_str(f.rung()).is_equal("tenant")
	var deed := _plot(f)
	assert_str(f.buy_direct(deed, "player")).is_empty()
	assert_str(f.rung()).is_equal("owner")
	assert_str(f.parcel(deed)["owner"]).is_equal("player")
	assert_str(f.legal_status(deed)).is_equal("freehold")
	# Estate: two farms, six fields, a steward.
	var deed2 := _plot(f)
	assert_str(f.buy_direct(deed2, "player")).is_empty()
	assert_str(f.rung()).is_equal("owner")
	var rec: RefCounted = hub.mod("recruitment")
	var row := _worker_row(rec, 0)
	var res: Dictionary = f.hire_worker(deed, row, 40)
	assert_bool(res["ok"]).override_failure_message(String(res.get("line", ""))).is_true()
	var st: Dictionary = f.appoint_steward(deed, String(res["fid"]))
	assert_bool(st["ok"]).is_true()
	assert_str(f.rung()).is_equal("estate")


func _worker_row(rec: RefCounted, skip: int) -> int:
	var rg: Vector2i = WorldSim.ranges[0]
	var seen := 0
	for i in range(rg.x, rg.y):
		if WorldSim.health[i] == 0:
			continue
		var p: Dictionary = rec.profile(i)
		var ev: Dictionary = rec.evaluate(i, Rec.make_terms(40, "labor", 0, true), {"trust": 30.0, "reputation": 50.0})
		if ev["verdict"] == "accept":
			if seen >= skip:
				return i
			seen += 1
		if p.is_empty():
			continue
	return rg.x


# ---------------------------------------------------------------- fields

func test_monoculture_falls_and_rotation_recovers() -> void:
	var mono := FF.new_field(0.8)
	var ys: Array = []
	for i in 4:
		var y := _grow(mono, "wheat", 10 + i * 30)
		FF.reap(mono, 1)
		ys.append(y)
	var ratio := float(ys[3]) / float(ys[0])
	assert_float(ratio).override_failure_message("4th wheat harvest at %.2f of the first (%s)" % [ratio, str(ys)]).is_between(0.60, 0.80)
	assert_float(float(mono["f"])).is_less(0.6)
	# Rotation: grain, legume, root, grain... keeps the soil.
	var rot := FF.new_field(0.8)
	var plan := ["wheat", "peas", "turnip", "wheat"]
	var ry: Array = []
	for i in 4:
		var y2 := _grow(rot, plan[i], 10 + i * 30)
		FF.reap(rot, 1)
		ry.append(y2)
	assert_float(float(rot["f"])).is_greater(float(mono["f"]) + 0.08)
	# The grain after the legume and the root crop yields close to the first grain, and well above the fourth monoculture one.
	assert_float(float(ry[3]) / float(ys[0])).override_failure_message(str(ry)).is_greater_equal(0.85)
	assert_int(int(ry[3])).is_greater(int(float(ys[3]) * 1.15))
	# The picker avoids the family just harvested and asks for a legume when the soil is tired.
	var tired := FF.new_field(0.5)
	assert_str(FF.rotation_pick(tired, D.SPRING, ["wheat", "barley"])).is_equal("peas")
	var after := FF.new_field(0.8)
	after["l1"] = "grain"
	assert_str(FF.rotation_pick(after, D.SPRING, ["wheat", "barley", "turnip"])).is_equal("turnip")


func test_crop_by_season_climate_and_water() -> void:
	assert_bool(D.can_sow("hops", D.SPRING)).is_false()
	assert_bool(D.can_sow("hops", D.SUMMER)).is_true()
	assert_float(D.growth_rate("wheat", D.WINTER, 1)).is_equal(0.0)
	assert_float(D.growth_rate("turnip", D.WINTER, 1)).is_greater(0.0)           # hardy
	assert_float(D.growth_rate("wheat", D.SUMMER, 0)).is_less(D.growth_rate("wheat", D.SUMMER, 1))   # cold climate
	# A dry spell stresses the crop and costs yield; irrigation prevents it.
	var dry := FF.new_field(0.8)
	var wet := FF.new_field(0.8)
	FF.sow(dry, "wheat", 1)
	FF.sow(wet, "wheat", 1)
	wet["irr"] = 1
	var env := {"season": D.SUMMER, "clim": 2, "irr_ok": true}
	for i in 30:
		FF.step(dry, env, 1.0, null)
		FF.step(wet, env, 1.0, null)
	assert_float(float(dry["st"])).is_greater(0.2)
	assert_float(float(wet["st"])).is_equal(0.0)
	assert_int(FF.harvest_yield(dry, 2)).is_less(FF.harvest_yield(wet, 2))
	# Watering by hand lifts the moisture.
	var m0: float = dry["m"]
	FF.water(dry)
	assert_float(float(dry["m"])).is_greater(m0)


func test_pests_spread_to_neighbours_reduce_yield_and_are_cured() -> void:
	var fields: Array = []
	for i in 6:
		var F := FF.new_field(0.8)
		FF.sow(F, "wheat", 1)
		F["irr"] = 1
		fields.append(F)
	var clean: int = FF.harvest_yield(fields[5].duplicate(), 1)
	fields[0]["p"] = 0.8
	for day in 12:
		for F: Dictionary in fields:
			F["m"] = 0.7
		FF.spread(fields, 3, 1.0)
		for j in range(1, 6):
			var G: Dictionary = fields[j]
			G["p"] = clampf(float(G["p"]) + float(G["p"]) * 0.10 * (1.0 - float(G["p"])), 0.0, 1.0)     # their own growth
	assert_float(float(fields[1]["p"])).is_greater(0.1)          # next in the row
	assert_float(float(fields[3]["p"])).is_greater(0.1)          # next in the column
	assert_float(float(fields[1]["p"])).is_greater(float(fields[5]["p"]))      # nearer is worse than far
	assert_int(FF.harvest_yield(fields[0], 1)).is_less(int(float(clean) * 0.75))
	FF.treat(fields[0])
	assert_float(float(fields[0]["p"])).is_less(0.35)
	FF.treat(fields[0])
	assert_float(float(fields[0]["p"])).is_equal(0.0)
	assert_int(FF.harvest_yield(fields[0], 1)).is_greater(int(float(clean) * 0.9))
	# Blight spreads the same way, and a field harvested clean of pests keeps none.
	var blight := FF.new_field(0.8)
	FF.sow(blight, "wheat", 1)
	blight["d"] = 0.7
	assert_int(FF.harvest_yield(blight, 1)).is_less(int(float(clean) * 0.75))


func test_outbreaks_start_by_themselves_in_the_near_farm() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 5
	var hit := 0
	for k in 40:
		var F := FF.new_field(0.8)
		FF.sow(F, "wheat", 1)
		F["m"] = 0.8
		for d in 24:
			FF.step(F, {"season": D.SUMMER, "clim": 1, "irr_ok": false}, 1.0, r)
		if float(F["p"]) > 0.02 or float(F["d"]) > 0.02:
			hit += 1
	assert_int(hit).is_greater(2)
	assert_int(hit).is_less(40)


# ---------------------------------------------------------------- livestock

func test_herd_lifecycle_near() -> void:
	var a := _farming()
	var f: RefCounted = a[1]
	var pid := _plot(f, "player")
	var P: Dictionary = f.parcel(pid)
	P["wt"] = true
	f.set_day(100)
	assert_str(f.buy_animals(pid, "cow", 4)).is_empty()
	assert_str(f.buy_animals(pid, "sheep", 5)).is_empty()
	assert_str(f.buy_animals(pid, "chicken", 6)).is_empty()
	var r := RandomNumberGenerator.new()
	r.seed = 77
	var n0: int = f.herd_total(pid)
	var born := 0
	var died := 0
	var milk := 0.0
	var eggs := 0.0
	var wool := 0.0
	var sick := 0
	var h: Array = f.herd(pid)
	for day in range(100, 100 + 224):
		P["store"]["hay"] = 400.0
		P["store"]["wheat"] = 100.0
		var env: Dictionary = f._herd_env(P, day, D.Seasons.season_of(day))
		env["day"] = day
		var rep: Dictionary = FH.step_near(h, env, P["store"], r)
		born += int(rep["born"])
		died += int(rep["died"])
		milk += float(rep["milk"])
		eggs += float(rep["egg"])
		wool += float(rep["wool"])
		sick += int(rep["sick"])
	assert_int(born).is_greater(4)
	assert_int(h.size()).is_greater(n0)                  # the herd grew
	assert_float(milk).is_greater(30.0)                  # calves came, cows gave milk
	assert_float(eggs).is_greater(20.0)
	assert_float(wool).is_greater(5.0)
	assert_int(sick).is_greater(0)                       # animals do fall sick
	# Ageing: every animal is older, and an old one eventually dies.
	for an: Array in h:
		assert_int(int(an[FH.A_AGE])).is_greater(0)


func test_herd_starves_without_feed_or_water() -> void:
	var a := _farming()
	var f: RefCounted = a[1]
	var pid := _plot(f, "player")
	var P: Dictionary = f.parcel(pid)
	f.buy_animals(pid, "cow", 3)
	P["store"].clear()
	var r := RandomNumberGenerator.new()
	r.seed = 3
	var h: Array = f.herd(pid)
	var env := {"day": 100, "season": D.WINTER, "graze": 0.0, "water": false, "shelter": 1.0, "spec": "", "treat": false}
	for day in 60:
		env["day"] = 100 + day
		FH.step_near(h, env, P["store"], r)
	assert_int(h.size()).is_less(3)


func test_far_herd_matches_near_herd_and_the_fold_keeps_counts() -> void:
	var near_tot := 0.0
	var far_tot := 0.0
	var seeds := 6
	for s in seeds:
		var H: Array = []
		var r := RandomNumberGenerator.new()
		r.seed = 100 + s
		for i in 6:
			H.append(FH.new_animal("cow", 120, i < 5, 0, r))
		for i in 8:
			H.append(FH.new_animal("sheep", 90, i < 6, 0, r))
		var C := FH.collapse(H.duplicate(true), 0)
		assert_int(FH.cohort_total(C)).is_equal(14)
		var store := {"hay": 1e6, "turnip": 1e6}
		var store2 := {"hay": 1e6, "turnip": 1e6}
		var env := {"day": 0, "season": D.SPRING, "graze": 30.0, "water": true, "shelter": 20.0, "spec": "", "treat": false}
		for day in 112:
			env["season"] = D.Seasons.season_of(day)
			env["day"] = day
			FH.step_near(H, env, store, r)
		for blk in 16:
			env["season"] = D.Seasons.season_of(blk * 7)
			FH.step_far(C, env, store2, 7.0)
		near_tot += float(H.size())
		far_tot += float(FH.cohort_total(C))
	var ratio := far_tot / near_tot
	assert_float(ratio).override_failure_message("far herd %.1f vs near %.1f" % [far_tot / seeds, near_tot / seeds]).is_between(0.7, 1.4)
	# Fold and unfold keep the counts, the pregnancies and the age.
	var rr := RandomNumberGenerator.new()
	rr.seed = 9
	var H2: Array = []
	for i in 10:
		H2.append(FH.new_animal("cow", 100 + i, i < 8, 0, rr))
	H2[0][FH.A_DUE] = 20
	H2[1][FH.A_DUE] = 25
	var C2 := FH.collapse(H2, 10)
	assert_float(float(C2["cow"]["pg"])).is_equal(2.0)
	var back := FH.expand(C2, 10, rr)
	assert_int(back.size()).is_equal(10)
	var pg := 0
	for an: Array in back:
		if int(an[FH.A_DUE]) >= 0:
			pg += 1
	assert_int(pg).is_equal(2)


func test_farm_folds_the_herd_when_far_and_unfolds_when_near() -> void:
	var a := _farming()
	var f: RefCounted = a[1]
	var pid := _plot(f, "player")
	f.buy_animals(pid, "cow", 5)
	f.buy_animals(pid, "sheep", 6)
	var P: Dictionary = f.parcel(pid)
	assert_int(P["lod"]).is_equal(0)
	f.player_pos = FAR
	P["last"] = 100
	for d in range(101, 108):
		P["store"]["hay"] = 500.0
		f.tick_day(d, CTX)
	assert_int(P["lod"]).is_equal(1)
	assert_int((P["herd"] as Array).size()).is_equal(0)
	assert_int(f.herd_total(pid)).is_greater(8)
	f.set_day(108)
	f.tick_day(108, _ctx(Vector2(100, 100)))
	assert_int(P["lod"]).is_equal(0)
	assert_int((P["herd"] as Array).size()).is_greater(8)


func test_theft_and_specialisation() -> void:
	var a := _farming()
	var f: RefCounted = a[1]
	var pid := _plot(f, "player")
	f.buy_animals(pid, "horse", 2)
	f.buy_animals(pid, "cow", 2)
	var P: Dictionary = f.parcel(pid)
	var r := RandomNumberGenerator.new()
	r.seed = 1
	assert_int(f._theft(P, r, 1, true)).is_equal(1)
	assert_int(f.herd_total(pid)).is_equal(3)
	assert_int(int(P["stolen"])).is_equal(1)
	# A fence and a night hand make thieves rarer (the guard value rises).
	var g0: float = f._guard(P)
	P["bld"].append({"k": "fence", "st": "done", "site": 0, "due": 0, "npc": false})
	assert_float(f._guard(P)).is_greater(g0)
	# Specialisations need their building; dairy cows give more milk.
	assert_str(f.set_specialisation(pid, "dairy")).is_not_empty()
	P["bld"].append({"k": "barn", "st": "done", "site": 0, "due": 0, "npc": false})
	assert_str(f.set_specialisation(pid, "dairy")).is_empty()
	var base := {"hay": 1e4}
	var spec := {"hay": 1e4}
	var H1: Array = []
	var H2: Array = []
	for i in 3:
		var c1 := FH.new_animal("cow", 200, true, 0)
		c1[FH.A_LACT] = 500
		H1.append(c1)
		H2.append(c1.duplicate())
	var rr := RandomNumberGenerator.new()
	rr.seed = 5
	FH.step_near(H1, {"day": 0, "season": D.SPRING, "graze": 10.0, "water": true, "shelter": 9.0, "spec": ""}, base, rr)
	rr.seed = 5
	FH.step_near(H2, {"day": 0, "season": D.SPRING, "graze": 10.0, "water": true, "shelter": 9.0, "spec": "dairy"}, spec, rr)
	assert_float(float(spec["milk"])).is_greater(float(base["milk"]))
	# Selling animals pays by value and shrinks the herd.
	var before_gold: int = f.gold_available()
	var sold: Dictionary = f.sell_animals(pid, "horse", 1)
	assert_int(sold["sold"]).is_equal(1)
	assert_int(f.gold_available()).is_greater(before_gold)


# ---------------------------------------------------------------- land: sale, mortgage, tenancy rights

func test_sale_keeps_the_debt_and_the_tenant() -> void:
	var a := _farming()
	var f: RefCounted = a[1]
	f.add_farmer("npc:9001", 0, 800, 0.8, -1, "Wat Tyler")
	f.add_farmer("npc:9002", 0, 900, 0.9, -1, "Hob")
	var pid := _plot(f, "npc:9001")
	assert_str(f.mortgage(pid, 100)).is_empty()
	assert_str(f.mortgage(pid, 9999)).is_not_empty()
	assert_str(f.legal_status(pid)).is_equal("mortgaged")
	f.add_farmer("npc:9003", 0, 900, 0.5, -1, "Tenant")
	assert_str(f.rent_out(pid, "npc:9003", "rent", 30, 0.0, 200)).is_empty()
	var P: Dictionary = f.parcel(pid)
	P["ten"]["arrears"] = 20
	P["wo"] = 15
	var cash_seller: int = f.farmer("npc:9001")["cash"]
	var cash_buyer: int = f.farmer("npc:9002")["cash"]
	var until: int = P["ten"]["until"]
	assert_str(f.sell_to(pid, "npc:9002", 400)).is_empty()
	assert_str(P["owner"]).is_equal("npc:9002")
	# The seller got the price less the lien; the buyer paid in full.
	assert_int(int(f.farmer("npc:9001")["cash"]) - cash_seller).is_equal(300)
	assert_int(cash_buyer - int(f.farmer("npc:9002")["cash"])).is_equal(400)
	# The lien, the lease, the arrears and the wages owed all came with the land.
	assert_int(f.debt_of(pid)).is_equal(100)
	assert_str(P["mort"]["lender"]).is_equal("bank:0")
	assert_str(P["ten"]["who"]).is_equal("npc:9003")
	assert_int(P["ten"]["until"]).is_equal(until)
	assert_int(P["ten"]["arrears"]).is_equal(20)
	assert_int(P["wo"]).is_equal(15)
	assert_int(f.rights(pid).size()).is_equal(3)
	# The new owner cannot throw the tenant out before the term, and cannot sell for less than the debt.
	assert_str(f.evict(pid, "npc:9002")).contains("until day")
	assert_str(f.sell_to(pid, "npc:9001", 60)).contains("debt")
	assert_str(P["owner"]).is_equal("npc:9002")
	# The arrears are now the new owner's to collect.
	for d in range(101, 135):
		f.tick_day(d, CTX)
	assert_int(P["ten"]["arrears"]).is_equal(0)


func test_mortgage_default_seizes_the_land_but_not_the_lease() -> void:
	var a := _farming()
	var f: RefCounted = a[1]
	var pid := _plot(f, "player")
	assert_str(f.mortgage(pid, 150)).is_empty()
	_gold["gold"] = 0          # the money is spent
	f.pending_gold = 0
	f.add_farmer("npc:9001", 0, 500, 0.5, -1, "Tenant")
	assert_str(f.rent_out(pid, "npc:9001", "rent", 0, 0.0, 400)).is_empty()      # a rent-free lease: no income to meet the lender
	for d in range(101, 101 + 28 * 5):
		f.tick_day(d, CTX)
		if int(f.stats["seized"]) > 0:
			break
	assert_int(f.stats["seized"]).is_equal(1)
	# The lender took the land, not the lease: the tenant is still there under the Crown.
	assert_str(f.parcel(pid)["owner"]).is_equal("lord:0")
	assert_str(f.parcel(pid)["ten"]["who"]).is_equal("npc:9001")
	assert_int(f.debt_of(pid)).is_equal(0)
	assert_str(f.legal_status(pid)).is_equal("let")
	assert_str(f.rung()).is_equal("")


func test_tenant_rent_arrears_eviction() -> void:
	var a := _farming()
	var f: RefCounted = a[1]
	f._pl["exp"] = 10
	var pid := _plot(f, "lord:0")
	assert_str(f.take_tenancy(pid, "rent")).is_empty()
	_gold["gold"] = 0
	f.pending_gold = 0
	var lost := false
	for d in range(101, 101 + 28 * 4):
		f.tick_day(d, CTX)
		if (f.parcel(pid)["ten"] as Dictionary).is_empty():
			lost = true
			break
	assert_bool(lost).is_true()
	assert_str(f.rung()).is_equal("")


func test_share_tenant_pays_landlord_in_kind() -> void:
	var a := _farming()
	var f: RefCounted = a[1]
	f.add_farmer("npc:9001", 0, 100, 0.5, -1, "Sharecropper")
	var pid := _plot(f, "player")
	f.rent_out(pid, "npc:9001", "share", 0, 0.4, 112)
	var P: Dictionary = f.parcel(pid)
	var F: Dictionary = P["fields"][0]
	F["c"] = "wheat"
	F["g"] = 30.0
	var qty: int = f.forecast(pid, 0)
	var res: Dictionary = f._task(P, F, "harvest", "", "worker", 100)
	assert_bool(res["ok"]).is_true()
	assert_int(res["cut"]).is_equal(int(round(float(qty) * 0.4)))
	assert_float(float(P["ls"]["wheat"])).is_equal(float(res["cut"]))
	# The sharecropper has no lease on a term: the landlord gives notice and he goes.
	assert_str(f.evict(pid, "player")).is_empty()
	for d in range(101, 120):
		f.tick_day(d, CTX)
	assert_bool((P["ten"] as Dictionary).is_empty()).is_true()


# ---------------------------------------------------------------- the auction: an NPC outbids the player

func test_an_npc_can_outbid_the_player() -> void:
	var a := _farming()
	var f: RefCounted = a[1]
	f._pl["exp"] = 40
	var pid := _plot(f, "lord:0")
	assert_str(f.list_for_sale(pid, 300)).is_empty()
	assert_str(f.bid(pid, "player", 200)).contains("at least")
	var gold0: int = f.gold_available()
	assert_str(f.bid(pid, "player", 320)).is_empty()
	assert_int(f.gold_available()).is_equal(gold0 - 320)          # escrowed
	f.add_farmer("npc:9001", 0, 2500, 1.0, -1, "Rich Hob")
	f.add_farmer("npc:9002", 0, 40, 1.0, -1, "Poor Tam")
	assert_int(f.npc_bid_round(pid)).is_greater(0)
	var hi: Dictionary = f.highest_bid(pid)
	assert_str(hi["who"]).is_equal("npc:9001")
	assert_int(hi["amt"]).is_greater(336)
	assert_int(f.gold_available()).is_equal(gold0)                # the player's offer came back
	assert_int(f.stats["outbid"]).is_equal(1)
	# The player may raise; the NPC's reply is capped by his cash.
	assert_str(f.bid(pid, "player", int(hi["amt"]) + 1)).contains("at least")
	assert_str(f.close_sale(pid)).is_equal("npc:9001")
	assert_str(f.parcel(pid)["owner"]).is_equal("npc:9001")
	assert_int(f.gold_available()).is_equal(gold0)
	# Another listing: a poorer NPC cannot beat the player's higher offer.
	var pid2 := _plot(f, "lord:0")
	f.farmer("npc:9001")["cash"] = 500
	f.list_for_sale(pid2, 300)
	f.bid(pid2, "player", 900)
	f.npc_bid_round(pid2)
	assert_str(f.highest_bid(pid2)["who"]).is_equal("player")
	assert_str(f.close_sale(pid2)).is_equal("player")
	assert_str(f.parcel(pid2)["owner"]).is_equal("player")


func test_the_day_tick_runs_auctions_and_lets() -> void:
	var a := _farming()
	var f: RefCounted = a[1]
	f.add_farmer("npc:9001", 0, 2500, 1.0, -1, "Rich Hob")
	f.add_farmer("npc:9004", 0, 90, 0.5, -1, "Landless Tam")
	var pid := _plot(f, "lord:0")
	f.list_for_sale(pid, 300)
	var vac := _plot(f, "lord:0")
	for d in range(101, 108):
		f.tick_day(d, CTX)
	assert_str(f.parcel(pid)["owner"]).is_equal("npc:9001")
	assert_bool((f.parcel(vac)["ten"] as Dictionary).is_empty()).is_false()      # the Crown let it
	assert_str(f.parcel(vac)["ten"]["who"]).is_equal("npc:9004")


func test_an_npc_can_outbid_the_player_for_a_tenancy() -> void:
	var a := _farming()
	var f: RefCounted = a[1]
	f._pl["exp"] = 10
	var vac := _plot(f, "lord:0")
	assert_str(f.list_for_let(vac, "rent", 100)).is_empty()
	assert_str(f.bid_tenancy(vac, "player", 50)).contains("at least")
	assert_str(f.bid_tenancy(vac, "player", 105)).is_empty()
	f.add_farmer("npc:9001", 0, 400, 1.0, -1, "Keen Tam")
	f._npc_let_bids(vac)                                   # the landless NPC bids by himself
	assert_int((f.parcel(vac)["let"]["bids"] as Array).size()).is_equal(2)
	assert_str(f.bid_tenancy(vac, "npc:9001", 160)).is_empty()
	assert_str(f.close_let(vac)).is_equal("npc:9001")
	assert_str(f.parcel(vac)["ten"]["who"]).is_equal("npc:9001")
	assert_int(f.parcel(vac)["ten"]["rent"]).is_equal(160)
	assert_str(f.rung()).is_equal("")


func test_a_player_tenant_farm_pays_better_than_wages_but_not_wildly() -> void:
	# Manual play: the tenant of a four-field farm sows, harvests and sells; compare the daily gold with the farmhand's wage.
	var a := _farming()
	var f: RefCounted = a[1]
	f.set_day(0)
	f._pl["exp"] = 10
	var pid := _plot(f, "lord:0", 4, 0.78)
	assert_str(f.take_tenancy(pid, "rent")).is_empty()
	var P: Dictionary = f.parcel(pid)
	P["last"] = 0
	var mk: Dictionary = f.market_ref
	var gold0: int = f.gold_available()
	var days := 224
	for d in range(1, days + 1):
		f.set_day(d)
		var season: int = D.Seasons.season_of(d)
		for i in 4:
			var F: Dictionary = P["fields"][i]
			if FF.is_ready(F):
				f.do_task(pid, i, "harvest")
			if String(F["c"]) == "":
				f.do_task(pid, i, "sow", FF.rotation_pick(F, season, P["plan"]))
			if float(F["p"]) > 0.15:
				f.do_task(pid, i, "treat")
		f.tick_day(d, CTX)
		if d % 7 == 0:
			for k: String in P["store"].keys():
				if not k.begins_with("seed_"):
					f.sell_goods(pid, k, 1000, 0.0)
		for sid in mk:
			(mk[sid] as RefCounted).tick_day(60)
	var per_day := float(f.gold_available() - gold0) / float(days)
	print("TENANT: %.2f gold a day after rent (farmhand wage %d)" % [per_day, f.WAGE_HAND])
	assert_float(per_day).is_between(1.5, 9.0)


func test_an_autonomous_farm_reinvests_and_sells_for_itself() -> void:
	var a := _farming()
	var hub: RefCounted = a[0]
	var f: RefCounted = a[1]
	var rec: RefCounted = hub.mod("recruitment")
	var pid := _plot(f, "player", 3, 0.8)
	var P: Dictionary = f.parcel(pid)
	assert_bool(f.hire_worker(pid, _worker_row(rec, 0), 40)["ok"]).is_true()
	f.set_mode(pid, "autonomous")
	_gold["gold"] = 2000
	var g0: int = f.gold_available()
	P["store"]["wheat"] = 40.0
	f.set_day(100)
	P["last"] = 100
	for d in range(101, 130):
		f.tick_day(d, CTX)
	assert_float(float(P["store"]["wheat"])).is_less(40.0)           # the steward-less autonomous farm sold its grain
	assert_int((P["bld"] as Array).size()).is_greater(0)              # and put money into the farm
	assert_int(f.gold_available()).is_less(g0 + 200)


# ---------------------------------------------------------------- work: manual == delegated == autonomous

func _ready_farm(f: RefCounted, owner := "player") -> String:
	var pid := _plot(f, owner, 4, 0.7)
	var P: Dictionary = f.parcel(pid)
	for i in 4:
		var F: Dictionary = P["fields"][i]
		F["c"] = ["wheat", "barley", "wheat", "turnip"][i]
		F["g"] = 60.0
		F["l1"] = ["grain", "root", "legume", "grain"][i]
		F["p"] = 0.1 * i
		F["w"] = 0.2
		F["st"] = 0.1
	return pid


func test_worker_harvest_equals_manual() -> void:
	var a := _farming()
	var hub: RefCounted = a[0]
	var f: RefCounted = a[1]
	var man := _ready_farm(f)
	var wrk := _ready_farm(f)
	var P1: Dictionary = f.parcel(man)
	var P2: Dictionary = f.parcel(wrk)
	# Manual: the player harvests each field.
	for i in 4:
		assert_bool(f.do_task(man, i, "harvest")["ok"]).is_true()
	# Worker: hired through the property chain; the day's labour harvests.
	var rec: RefCounted = hub.mod("recruitment")
	var res: Dictionary = f.hire_worker(wrk, _worker_row(rec, 0), 40)
	assert_bool(res["ok"]).override_failure_message(String(res.get("line", ""))).is_true()
	assert_int(f.workers_of(wrk).size()).is_equal(1)
	assert_str(rec.get_entry(String(res["fid"]))["chain"]).is_equal("property")
	assert_str(rec.group(P2["gid"])["ref"]).is_equal(wrk)
	f._labour(P2, 100, D.SPRING, 4.0, "worker")
	for crop in ["wheat", "barley", "turnip"]:
		assert_float(float(P2["store"].get(crop, 0.0))).override_failure_message(crop).is_equal(float(P1["store"].get(crop, 0.0)))
	for i in 4:
		assert_float(float(P2["fields"][i]["f"])).is_equal(float(P1["fields"][i]["f"]))
		assert_str(P2["fields"][i]["c"]).is_equal("")
	# Every mode the same: the same ready farm, worked by a worker for a day under each mode, ends with the same store.
	var outs: Array = []
	for mode in ["manual", "delegated", "autonomous"]:
		var pid := _ready_farm(f)
		var PP: Dictionary = f.parcel(pid)
		var wr: Dictionary = f.hire_worker(pid, _worker_row(rec, 1 + outs.size()), 40)
		assert_bool(wr["ok"]).override_failure_message(String(wr.get("line", ""))).is_true()
		assert_bool(f.set_mode(pid, mode)).is_true()
		f.market_ref = {}              # no selling: compare what the fields gave
		PP["last"] = 100
		f.tick_day(101, CTX)
		var snap := {}
		for k: String in PP["store"]:
			if not k.begins_with("seed_"):
				snap[k] = snappedf(float(PP["store"][k]), 0.01)
		outs.append(snap)
	assert_dict(outs[1]).is_equal(outs[0])
	assert_dict(outs[2]).is_equal(outs[0])


func test_delegated_farm_runs_a_season_like_a_manual_one() -> void:
	# Manual sowing and harvesting by the player on the day it is possible vs hired hands: same field maths, so the grain agrees.
	var a := _farming()
	var hub: RefCounted = a[0]
	var f: RefCounted = a[1]
	var rec: RefCounted = hub.mod("recruitment")
	f.market_ref = {}
	var pm := _plot(f, "player", 3, 0.8)
	var pd := _plot(f, "player", 3, 0.8)
	for q in [pm, pd]:
		for c: String in D.CROP_IDS:
			f.parcel(q)["store"]["seed_" + c] = 500.0
	var wr: Dictionary = f.hire_worker(pd, _worker_row(rec, 0), 40)
	assert_bool(wr["ok"]).is_true()
	f.set_mode(pd, "delegated")
	var Pm: Dictionary = f.parcel(pm)
	var Pd: Dictionary = f.parcel(pd)
	for d in range(101, 101 + 56):
		var season: int = D.Seasons.season_of(d)
		# the manual player sows every fallow field and harvests every ready one the same day it can
		for i in 3:
			var F: Dictionary = Pm["fields"][i]
			if FF.is_ready(F):
				f.do_task(pm, i, "harvest")
			if String(F["c"]) == "":
				f.do_task(pm, i, "sow", FF.rotation_pick(F, season, Pm["plan"]))
		f.set_day(d)
		f.tick_day(d, CTX)
	var gm := 0.0
	var gd := 0.0
	for k: String in ["wheat", "barley", "peas", "turnip"]:
		gm += float(Pm["store"].get(k, 0.0))
		gd += float(Pd["store"].get(k, 0.0))
	assert_float(gm).is_greater(20.0)
	assert_float(gd / gm).override_failure_message("delegated %.0f vs manual %.0f" % [gd, gm]).is_between(0.8, 1.25)


func test_steward_skimming_and_audit_use_the_property_chain() -> void:
	var a := _farming()
	var hub: RefCounted = a[0]
	var f: RefCounted = a[1]
	var rec: RefCounted = hub.mod("recruitment")
	var pid := _plot(f, "player")
	var res: Dictionary = f.hire_worker(pid, _worker_row(rec, 0), 40)
	var w2: Dictionary = f.hire_worker(pid, _worker_row(rec, 1), 40)
	assert_bool(w2["ok"]).is_true()
	assert_bool(f.hire_worker(pid, _worker_row(rec, 2), 40)["ok"]).is_false()        # no bed: a cottage is needed
	assert_bool(f.appoint_steward(pid, String(res["fid"]))["ok"]).is_true()
	assert_str(f.parcel(pid)["mode"]).is_equal("delegated")
	assert_str(rec.group(f.parcel(pid)["gid"])["mgr"]).is_equal(String(res["fid"]))
	var audit: Dictionary = rec.audit(f.parcel(pid)["gid"])
	assert_bool(audit["ok"]).is_true()
	# Selling through a steward credits the group's wage float first.
	var P: Dictionary = f.parcel(pid)
	P["store"]["wheat"] = 30.0
	var bud0: float = rec.group(P["gid"])["bud"]
	f.sell_goods(pid, "wheat", 20)
	assert_float(float(rec.group(P["gid"])["bud"])).is_greater_equal(bud0)
	# A sale of the farm lets the employees go with the property chain.
	assert_str(f.sell_to(pid, "lord:0", 100)).is_empty()
	assert_int(f.workers_of(pid).size()).is_equal(0)


# ---------------------------------------------------------------- expansion: construction staged sites

func test_expansion_goes_through_construction_sites() -> void:
	var a := _farming()
	var hub: RefCounted = a[0]
	var f: RefCounted = a[1]
	var cons: RefCounted = hub.mod("construction")
	cons.bag = {"plank": 100}
	var pid := _plot(f, "player", 3)
	var P: Dictionary = f.parcel(pid)
	var g0: int = f.gold_available()
	var r1: Dictionary = f.build(pid, "barn")
	assert_bool(r1["ok"]).override_failure_message(String(r1["line"])).is_true()
	assert_int(f.gold_available()).is_equal(g0 - int(D.BUILDINGS["barn"]["gold"]))
	var site: int = r1["site"]
	assert_bool(cons.sites.has(site)).is_true()
	assert_str(cons.sites[site]["kind"]).is_equal("kit_plan")
	assert_str(cons.sites[site]["state"]).is_equal("site")
	assert_float(shelter(f, P)).is_equal(D.SHELTER_BASE)             # not yet
	f.tick_day(101, CTX)
	assert_str(P["bld"][0]["st"]).is_equal("site")
	cons.sites[site]["state"] = "done"                               # the crew finished it
	f.tick_day(102, CTX)
	assert_str(P["bld"][0]["st"]).is_equal("done")
	assert_float(shelter(f, P)).is_greater(D.SHELTER_BASE + 10.0)
	assert_int(f.store_cap(P)).is_greater(D.STORE_BASE + 100)
	# A field adds a real field only when done.
	var nf: int = f.fields_count(pid)
	var r2: Dictionary = f.build(pid, "field")
	assert_int(f.fields_count(pid)).is_equal(nf)
	cons.sites[int(r2["site"])]["state"] = "done"
	f.tick_day(103, CTX)
	assert_int(f.fields_count(pid)).is_equal(nf + 1)
	# A granary, a pen, a cottage (beds for hands) and irrigation use the same path.
	for k in ["granary", "pen", "cottage", "irrigation"]:
		var rr: Dictionary = f.build(pid, k)
		assert_bool(rr["ok"]).override_failure_message("%s: %s" % [k, String(rr["line"])]).is_true()
		cons.sites[int(rr["site"])]["state"] = "done"
	f.tick_day(104, CTX)
	assert_int(f.housing_cap(P)).is_equal(4)
	for F: Dictionary in P["fields"]:
		assert_int(F["irr"]).is_equal(1)
	# Refused without the gold.
	_gold["gold"] = 0
	f.pending_gold = 0
	assert_bool(f.build(pid, "mill")["ok"]).is_false()


func shelter(f: RefCounted, P: Dictionary) -> float:
	return f.shelter_of(P)


func test_npc_farm_builds_with_npc_sites() -> void:
	var a := _farming()
	var hub: RefCounted = a[0]
	var f: RefCounted = a[1]
	var cons: RefCounted = hub.mod("construction")
	f.add_farmer("npc:9001", 0, 900, 0.9, -1, "Builder")
	var pid := _plot(f, "npc:9001", 3)
	var r: Dictionary = f.build(pid, "field", "npc:9001")
	assert_bool(r["ok"]).is_true()
	assert_bool(bool(cons.sites[int(r["site"])]["npc"])).is_true()
	for d in range(101, 116):
		f.tick_day(d, CTX)
	assert_int(f.fields_count(pid)).is_greater_equal(4)


# ---------------------------------------------------------------- economy

func test_produce_feeds_market_supply_and_price() -> void:
	var a := _farming()
	var f: RefCounted = a[1]
	var pid := _plot(f, "player")
	var m: RefCounted = f.market_ref[0]
	var stock0: int = m.stock["wheat"]
	var price0: int = m.price("wheat")
	var P: Dictionary = f.parcel(pid)
	P["store"]["wheat"] = 120.0
	var gold: int = f.sell_goods(pid, "wheat", 100)
	assert_int(gold).is_greater(0)
	assert_int(m.stock["wheat"]).is_greater(stock0)                 # the farm's wheat is now the town's supply
	assert_int(m.price("wheat")).is_less(price0)                    # and weighs on its price
	# A floor stops a farm dumping into a glut.
	P["store"]["wheat"] = 200.0
	var before: float = P["store"]["wheat"]
	f.sell_goods(pid, "wheat", 200, 0.9)
	assert_float(float(P["store"]["wheat"])).is_greater(before * 0.3)
	# Milk (a new good) is added to the market on first sale.
	P["store"]["cheese"] = 4.0
	assert_int(f.sell_goods(pid, "cheese", 4)).is_greater(0)
	assert_bool(m.base_price.has("cheese")).is_true()


func test_storage_spoils_and_a_granary_slows_it() -> void:
	var a := _farming()
	var f: RefCounted = a[1]
	var p1 := _plot(f, "player")
	var p2 := _plot(f, "player")
	var P1: Dictionary = f.parcel(p1)
	var P2: Dictionary = f.parcel(p2)
	P2["bld"].append({"k": "granary", "st": "done", "site": 0, "due": 0, "npc": false})
	for P: Dictionary in [P1, P2]:
		P["store"]["wheat"] = 30.0
		P["store"]["milk"] = 10.0
		P["store"]["cabbage"] = 20.0
	f._spoil(P1, 28)
	f._spoil(P2, 28)
	assert_float(float(P1["store"].get("milk", 0.0))).is_less(0.1)               # milk is gone in days
	assert_float(float(P1["store"]["cabbage"])).is_less(float(P1["store"]["wheat"]))
	assert_float(float(P2["store"]["wheat"])).is_greater(float(P1["store"]["wheat"]))
	# Over capacity rots faster.
	P1["store"]["wheat"] = 500.0
	f._spoil(P1, 5)
	assert_float(float(P1["store"]["wheat"])).is_less(480.0)


func test_garrison_supply_contract() -> void:
	var a := _farming()
	var hub: RefCounted = a[0]
	var f: RefCounted = a[1]
	var sh: RefCounted = hub.mod("strongholds")
	sh._ensure()
	f._gen_contracts(105)
	assert_int(f.contracts().size()).is_greater(0)
	var c: Dictionary = f.contracts()[0]
	var pid := _plot(f, "player")
	var P: Dictionary = f.parcel(pid)
	assert_str(f.accept_contract(int(c["id"]), pid)).is_empty()
	assert_str(f.accept_contract(int(c["id"]), pid)).is_not_empty()
	P["store"][c["item"]] = float(c["qty"]) + 3.0
	var s0: int = int(sh.stronghold(int(c["buyer"])).get("supply", 0))
	var g0: int = f.gold_available()
	var res: Dictionary = f.deliver_contract(int(c["id"]), pid, 106)
	assert_bool(res["ok"]).is_true()
	assert_int(f.gold_available() - g0).is_equal(int(c["qty"]) * int(c["price"]))
	assert_int(int(c["price"])).is_greater(D.base_price(String(c["item"])))       # a premium over the market
	assert_int(int(sh.stronghold(int(c["buyer"])).get("supply", 0))).is_equal(s0 + int(c["qty"]))
	# Late delivery lapses and costs reputation.
	f._gen_contracts(113)
	var c2: Dictionary = {}
	for k: Dictionary in f.contracts():
		if not bool(k.get("done", false)):
			c2 = k
			break
	if not c2.is_empty():
		f.accept_contract(int(c2["id"]), pid)
		P["store"][c2["item"]] = 99.0
		var rep0: int = f._pl["rep"]
		var late: Dictionary = f.deliver_contract(int(c2["id"]), pid, int(c2["due"]) + 5)
		assert_bool(late["ok"]).is_false()
		assert_int(f._pl["rep"]).is_equal(rep0 - 1)


# ---------------------------------------------------------------- NPC farmers

func _world_farms() -> Array:
	var a := _farming()
	var f: RefCounted = a[1]
	f._inited = false
	f.ensure()
	return a


func test_world_seeds_npc_farms_and_farmers() -> void:
	var a := _world_farms()
	var f: RefCounted = a[1]
	assert_int(f.parcels().size()).is_between(4, f.NPC_FARMS_MAX)
	var tenants := 0
	var owners := 0
	for pid: String in f.parcels():
		var P: Dictionary = f.parcel(pid)
		if not (P["ten"] as Dictionary).is_empty():
			tenants += 1
		elif String(P["owner"]).begins_with("npc:"):
			owners += 1
		assert_int((P["fields"] as Array).size()).is_greater_equal(3)
	assert_int(tenants).is_greater(0)
	assert_int(owners + tenants).is_equal(f.parcels().size())
	# Deterministic.
	var b := _world_farms()
	assert_array(b[1].parcels()).is_equal(f.parcels())


func test_npc_farmers_work_sell_and_expand_over_a_year() -> void:
	var a := _farming()
	var f: RefCounted = a[1]
	var mk := {}
	for s: Dictionary in WorldGen.settlements:
		var m := RAMarket.new()
		m.add_good("wheat", 2, 40, 8)
		m.add_good("barley", 2, 30, 4)
		m.add_good("turnip", 2, 30, 4)
		m.add_good("peas", 3, 20, 3)
		m.purse = 600
		mk[int(s["id"])] = m
	f.market_ref = mk
	f.set_day(0)
	f._inited = false
	f.ensure()
	var fields0 := 0
	for pid: String in f.parcels():
		fields0 += f.fields_count(pid)
	var n0: int = f.parcels().size()
	for d in range(1, 1 + 224):
		f.tick_day(d, CTX)
		for sid in mk:
			(mk[sid] as RefCounted).tick_day(60)
	assert_int(f.stats["harvests"]).is_greater(n0 * 3)
	var gold := 0
	var alive := 0
	for who: String in f.farmers():
		var w: Dictionary = f.farmer(who)
		gold += int(w["cash"])
		if int(w["cash"]) > 0:
			alive += 1
	var fields1 := 0
	for pid2: String in f.parcels():
		fields1 += f.fields_count(pid2)
	print("NPC year: farms %d fields %d -> %d busts %d built %d sales %d harvests %d cash %d" % [n0, fields0, fields1, f.stats["busts"], f.stats["built"], f.stats["sales"], f.stats["harvests"], gold])
	assert_int(alive).is_greater(f.farmers().size() / 2)           # most farmers get by
	assert_int(f.stats["busts"]).is_between(0, n0 / 2)             # some go under, not most
	assert_int(fields1).is_greater_equal(fields0)
	assert_int(f.stats["sales"]).is_greater(0)                     # land changes hands between NPCs
	assert_int(f.stats["built"]).is_greater(0)                     # and they expand


func test_npc_farmer_goes_bust_and_the_land_returns_to_the_crown() -> void:
	var a := _farming()
	var f: RefCounted = a[1]
	f.add_farmer("npc:9001", 0, 300, 0.5, -1, "Doomed Hob")
	var pid := _plot(f, "lord:0")
	f.rent_out(pid, "npc:9001", "rent", 20, 0.0, 200)
	f.farmer("npc:9001")["cash"] = -300
	f.farmer("npc:9001")["neg"] = 30
	f.parcel(pid)["last"] = 100
	f.tick_day(108, CTX)
	assert_int(f.stats["busts"]).is_equal(1)
	assert_bool((f.parcel(pid)["ten"] as Dictionary).is_empty()).is_true()
	assert_int(f.farmer("npc:9001")["busts"]).is_equal(1)
	assert_int(f.farmer("npc:9001")["bust"]).is_greater(108)
	# A busted owner's land is seized and relisted.
	f.add_farmer("npc:9002", 0, -300, 0.5, -1, "Doomed Owner")
	f.farmer("npc:9002")["neg"] = 30
	var own := _plot(f, "npc:9002")
	f.parcel(own)["last"] = 100
	f.tick_day(116, CTX)
	assert_str(f.parcel(own)["owner"]).is_equal("lord:0")
	assert_bool((f.parcel(own)["sale"] as Dictionary).is_empty()).is_false()


# ---------------------------------------------------------------- save, cost

func test_save_round_trip() -> void:
	var a := _world_farms()
	var f: RefCounted = a[1]
	var mine := _plot(f, "player", 4)
	f.buy_animals(mine, "cow", 3)
	f.buy_animals(mine, "sheep", 4)
	f.parcel(mine)["store"]["hay"] = 900.0
	f.add_farmer("npc:9001", 0, 300, 0.6, -1, "Tenant Tom")
	var vac := _plot(f, "lord:0")
	f.rent_out(vac, "npc:9001", "rent", 25, 0.0, 120)
	f.mortgage(mine, 90)
	f.list_for_sale(_plot(f, "lord:0"), 250)
	f.build(mine, "barn")
	f.player_pos = FAR
	for d in range(101, 130):
		f.tick_day(d, CTX)
	f.player_pos = Vector2(100, 100)
	f._pl["exp"] = 12
	var data: Dictionary = f.serialize()
	var text := JSON.stringify(data)
	var parsed: Variant = JSON.parse_string(text)
	assert_bool(parsed is Dictionary).is_true()
	var g: RefCounted = Hub.new().mod("farming")
	g.deserialize(parsed)
	assert_array(g.parcels()).is_equal(f.parcels())
	assert_str(JSON.stringify(g.serialize())).is_equal(text)
	assert_int(g.herd_total(mine)).is_equal(f.herd_total(mine))
	assert_int(g.debt_of(mine)).is_equal(90)
	assert_str(g.parcel(vac)["ten"]["who"]).is_equal("npc:9001")
	assert_int(g.experience()).is_equal(12)
	assert_int(g.farmers().size()).is_equal(f.farmers().size())
	# And through the hub's own save path.
	var hub2: RefCounted = a[0]
	var hd: Dictionary = JSON.parse_string(JSON.stringify(hub2.serialize()))
	var hub3: RefCounted = Hub.new()
	hub3.deserialize(hd)
	assert_array(hub3.mod("farming").parcels()).is_equal(f.parcels())
	# A far world farm costs this much save: print the numbers.
	var npc_farms := 0
	var npc_bytes := 0
	for pid: String in data["p"]:
		if pid == mine:
			continue
		npc_farms += 1
		npc_bytes += JSON.stringify(data["p"][pid]).length()
	print("SAVE: %d farms, %d B total, %d B per NPC farm, player farm %d B (%d fields, herd %d)" % [data["p"].size(), text.length(),
		npc_bytes / maxi(1, npc_farms), JSON.stringify(data["p"][mine]).length(), f.fields_count(mine), f.herd_total(mine)])
	assert_int(npc_bytes / maxi(1, npc_farms)).is_less(1400)


func test_day_tick_chunks_stay_inside_the_budget() -> void:
	var a := _world_farms()
	var f: RefCounted = a[1]
	var hub: RefCounted = a[0]
	var mk := {}
	for s: Dictionary in WorldGen.settlements:
		var m := RAMarket.new()
		m.add_good("wheat", 2, 40, 8)
		mk[int(s["id"])] = m
	f.market_ref = mk
	# Two player farms with herds, one of them near.
	for k in 2:
		var pid: String = f.found_parcel(0, Vector2(100 + k * 300, 100), 6, "player", "Mine %d" % k)
		f.buy_animals(pid, "cow", 6)
		f.buy_animals(pid, "sheep", 8)
		f.buy_animals(pid, "chicken", 6)
	hub.mod("strongholds")._ensure()            # the hub's warm_up does this behind the loading screen
	var times: Array = []
	var ctx := _ctx(Vector2(100, 100))
	var total_us := 0
	var days := 56
	for d in range(101, 101 + days):
		f.set_day(d)
		for p in f.parcels():
			if String(f.parcel(p)["owner"]) == "player":
				f.parcel(p)["store"]["hay"] = 300.0
		var chunks: Array = f.tick_day_chunks(d, ctx)
		for cb: Callable in chunks:
			var t0 := Time.get_ticks_usec()
			cb.call()
			var dt := Time.get_ticks_usec() - t0
			times.append(dt)
			total_us += dt
	var worst := 0
	var worst_i := 0
	for i in times.size():
		if int(times[i]) > worst:
			worst = int(times[i])
			worst_i = i
	print("WORST chunk #%d (%d us) of %d per day" % [worst_i, worst, times.size() / days])
	times.sort()
	var p95: int = times[int(times.size() * 0.95)]
	var mean := float(total_us) / float(times.size())
	var per_day := float(total_us) / float(days)
	print("COST: %d farms, %d chunks, mean %.0f us, p95 %d us, max %d us, whole day %.0f us" % [f.parcels().size(), times.size(), mean, p95, times[times.size() - 1], per_day])
	assert_int(p95).is_less(600)
	assert_int(times[int(times.size() * 0.99)]).is_less(900)
	assert_float(mean).is_less(300.0)
	assert_object(hub).is_not_null()


func test_tick_day_is_its_chunks_and_runs_through_the_hub() -> void:
	var a := _world_farms()
	var f: RefCounted = a[1]
	var b := _world_farms()
	var g: RefCounted = b[1]
	for d in range(1, 15):
		f.tick_day(d, CTX)
		for cb: Callable in g.tick_day_chunks(d, CTX):
			cb.call()
	assert_str(JSON.stringify(g.serialize())).is_equal(JSON.stringify(f.serialize()))
	# The hub queues the module's day tick and the pump runs it in pieces.
	var hub: RefCounted = Hub.new()
	var ff: RefCounted = hub.mod("farming")
	ff.market_ref = {}
	ff.gold_ref = {"gold": 100}
	ff.ensure()
	hub.on_hour(6, 3, CTX)
	var jobs := 0
	while hub._queue.size() > 0 and jobs < 5000:
		hub.pump()
		jobs += 1
	assert_int(ff.today()).is_equal(3)
	assert_bool(ff.parcels().size() > 0).is_true()


func test_catch_up_is_not_per_day() -> void:
	var a := _world_farms()
	var f: RefCounted = a[1]
	f.set_day(100)
	var t0 := Time.get_ticks_usec()
	f.catch_up(200, CTX)
	var us := Time.get_ticks_usec() - t0
	print("CATCHUP: 200 days in %d us for %d farms" % [us, f.parcels().size()])
	assert_int(f.today()).is_equal(300)
	assert_int(us).is_less(80000)
	for pid: String in f.parcels():
		for F: Dictionary in f.parcel(pid)["fields"]:
			assert_float(float(F["f"])).is_between(0.0, 1.0)
