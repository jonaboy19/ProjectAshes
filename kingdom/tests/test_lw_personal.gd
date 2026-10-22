extends GdUnitTestSuite
## LW-8.3 (docs/design/LIVING_WORLD_SANDBOX.md section 12): homes (rent, buy, several, upkeep), households, education ages, relocation inside a
## kingdom and between kingdoms (titles not recognised, licences, history), and travel parties (provisions, escorts, protected and dangerous roads).

const Hub := preload("res://scripts/realm/realm_hub.gd")
const Homes := preload("res://scripts/realm/homes.gd")

static var _ready_world := false


func _hub() -> RefCounted:
	if not _ready_world:
		WorldGen.setup(2024)
		_ready_world = true
	WorldSim.day = 300
	var h: RefCounted = Hub.new()
	var om: RefCounted = h.mod("organizations")
	om.auto_seed = false
	om.gold_ref = {"gold": 5000}
	h.mod("faith").auto_seed = false
	h.mod("minds").auto_seed = false
	h.mod("minds").set_focus(-1)
	for k in ["homes", "farming", "businesses", "rumours", "dynasties"]:
		if h.mod(k).has_method("set_day"):
			h.mod(k).set_day(300)
	return h


func _pl(h: RefCounted) -> String:
	return h.mod("registry").ref("pl:player")


func _ch(h: RefCounted, age := 30, sex := "m", cash := 500, sid := 0, house := "") -> String:
	var ch: String = h.mod("registry").mint("ch")
	h.mod("organizations").ensure_char(ch, {"cash": cash, "sid": sid, "prof": "smith", "npc": true})
	assert_bool(h.mod("minds").adopt(ch, age, sex, house)).is_true()
	return ch


func _weeks(h: RefCounted, n: int) -> void:
	var hm: RefCounted = h.mod("homes")
	for w in n:
		WorldSim.day += 7
		hm.tick_week(WorldSim.day / 7, {})


func _days(h: RefCounted, n: int) -> void:
	var hm: RefCounted = h.mod("homes")
	for i in n:
		WorldSim.day += 1
		hm.tick_day(WorldSim.day, {})


## The id of a listing of `kind` in the town, else the dearest one on offer (not every town has every kind this month).
func _offer(hm: RefCounted, sid: int, kind: String) -> String:
	var best: Dictionary = {}
	for l: Dictionary in hm.listings(sid):
		if String(l["kind"]) == kind:
			return String(l["id"])
		if best.is_empty() or int(l["price"]) > int(best["price"]):
			best = l
	return String(best["id"])


func _norm(d: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(d)))


# --- homes ----------------------------------------------------------------------------

func test_listings_are_a_function_of_seed_town_and_month() -> void:
	var hm: RefCounted = _hub().mod("homes")
	var a: Array = hm.listings(2)
	assert_array(a).is_not_empty()
	assert_array(hm.listings(2)).is_equal(a)
	assert_bool(str(hm.listings(2, 300 + 31)) != str(a)).is_true()    # next month, other offers
	for l: Dictionary in a:
		assert_int(int(l["rent"])).is_greater(0)
		assert_int(int(l["price"])).is_greater(int(l["rent"]) * 20)
	var capital := 1
	assert_int(int(hm.listings(capital, 300)[0]["price"])).is_greater(0)


func test_renting_pays_a_deposit_and_weekly_rent_to_the_end_of_the_tenancy() -> void:
	var h := _hub()
	var hm: RefCounted = h.mod("homes")
	var om: RefCounted = h.mod("organizations")
	var pl := _pl(h)
	var purse0: int = om.purse("player")
	var r: Dictionary = hm.rent_home(pl, 1, "cottage", _offer(hm, 1, "cottage"))
	assert_bool(r["ok"]).is_true()
	assert_str(String(r["home"])).starts_with("pr:")
	assert_int(om.purse("player")).is_equal(purse0 - int(r["deposit"]))
	assert_str(hm.primary_home(pl)).is_equal(String(r["home"]))
	assert_int(hm.residence_sid(pl)).is_equal(1)
	_weeks(h, 3)
	assert_int(om.purse("player")).is_equal(purse0 - int(r["deposit"]) - 3 * int(r["rent"]))
	var end: Dictionary = hm.end_tenancy(String(r["home"]), pl)
	assert_bool(end["ok"]).is_true()
	assert_int(int(end["gold"])).is_equal(int(r["deposit"]))
	assert_str(hm.primary_home(pl)).is_equal("")


func test_a_tenant_who_cannot_pay_is_evicted_after_four_weeks() -> void:
	var h := _hub()
	var hm: RefCounted = h.mod("homes")
	var poor := _ch(h, 30, "m", 40)
	var r: Dictionary = hm.rent_home(poor, 0, "cottage", _offer(hm, 0, "cottage"))
	if not bool(r["ok"]):
		r = hm.rent_home(poor, 0, "hovel", _offer(hm, 0, "hovel"))
	assert_bool(r["ok"]).is_true()
	var om: RefCounted = h.mod("organizations")
	om.pay(poor, om.purse(poor))                                      # skint
	_weeks(h, 3)
	assert_bool(hm.home(String(r["home"])).is_empty()).is_false()
	assert_int(int(hm.home(String(r["home"]))["weeks"])).is_equal(3)
	_weeks(h, 1)
	assert_bool(hm.home(String(r["home"])).is_empty()).is_true()       # out on the street
	assert_int(hm.stats["evictions"]).is_equal(1)
	assert_array(h.mod("events").of_kind("crime", 5)).is_not_empty()


func test_owning_several_homes_costs_upkeep_and_neglect_condemns_the_empty_ones() -> void:
	var h := _hub()
	var hm: RefCounted = h.mod("homes")
	var om: RefCounted = h.mod("organizations")
	var pl := _pl(h)
	om.gold_ref = {"gold": 60000}
	var ids: Array = []
	for sid in [0, 1, 2]:
		var b: Dictionary = hm.buy_home(pl, sid, "house", _offer(hm, sid, "house"))
		assert_bool(b["ok"]).is_true()
		ids.append(String(b["home"]))
	assert_int(hm.homes_of(pl).size()).is_equal(3)
	assert_str(hm.primary_home(pl)).is_equal(ids[0])
	var due: int = hm.upkeep_due(pl)
	assert_int(due).is_greater(10)
	var before: int = om.purse("player")
	_weeks(h, 1)
	assert_int(om.purse("player")).is_equal(before - due)
	# the primary home is lived in; the other two stand empty and decay faster
	_weeks(h, 45)
	assert_float(float(hm.home(ids[0])["cond"])).is_greater(float(hm.home(ids[1])["cond"]))
	assert_float(float(hm.home(ids[1])["cond"])).is_less(25.0)
	assert_int(hm.stats["condemned"]).is_greater(0)                    # left to rot, it is condemned
	# a house that is let out earns more than it costs (not the owner's: he lives elsewhere)
	assert_bool(hm.let_out(ids[2], pl)).is_true()
	assert_int(int(hm.home(ids[2])["let"])).is_equal(1)
	var h2 := _hub()
	var hm2: RefCounted = h2.mod("homes")
	h2.mod("organizations").gold_ref = {"gold": 60000}
	var tenant_house: Dictionary = hm2.buy_home(_pl(h2), 1, "house", _offer(hm2, 1, "house"))
	hm2.let_out(String(tenant_house["home"]), _pl(h2))
	var purse0: int = h2.mod("organizations").purse("player")
	_weeks(h2, 20)
	assert_int(h2.mod("organizations").purse("player")).is_greater(purse0)   # rent from the town's families outweighs upkeep
	# selling gives most of the price, less for a worn house
	var sold: Dictionary = hm.sell_home(ids[0], pl)
	assert_bool(sold["ok"]).is_true()
	assert_str(hm.primary_home(pl)).is_not_equal(ids[0])
	assert_bool(hm.sell_home(ids[0], pl)["ok"]).is_false()


func test_an_owner_who_stops_paying_loses_the_house() -> void:
	var h := _hub()
	var hm: RefCounted = h.mod("homes")
	var om: RefCounted = h.mod("organizations")
	var rich := _ch(h, 40, "m", 4000)
	var b: Dictionary = hm.buy_home(rich, 0, "cottage", _offer(hm, 0, "cottage"))
	assert_bool(b["ok"]).is_true()
	om.pay(rich, om.purse(rich))
	_weeks(h, 7)
	assert_bool(hm.home(String(b["home"])).is_empty()).is_false()
	_weeks(h, 1)
	assert_bool(hm.home(String(b["home"])).is_empty()).is_true()
	assert_int(hm.stats["seized"]).is_equal(1)


func test_the_player_cannot_keep_more_than_six_homes() -> void:
	var h := _hub()
	var hm: RefCounted = h.mod("homes")
	h.mod("organizations").gold_ref = {"gold": 90000}
	var pl := _pl(h)
	for i in 6:
		assert_bool(hm.buy_home(pl, i % 5, "hovel", _offer(hm, i % 5, "hovel"))["ok"]).is_true()
	assert_bool(hm.buy_home(pl, 0, "hovel", _offer(hm, 0, "hovel"))["ok"]).is_false()


# --- households and education ---------------------------------------------------------

func test_marriage_makes_a_household_and_children_follow_the_education_ages() -> void:
	var h := _hub()
	var hm: RefCounted = h.mod("homes")
	var mn: RefCounted = h.mod("minds")
	var dad := _ch(h, 38, "m", 800, 1, "Hale@1")
	var mum := _ch(h, 34, "f", 100, 1, "Brook@1")
	var res: Dictionary = hm.marry(dad, mum, {"sid": 1})
	assert_bool(res["ok"]).is_true()
	var hid := String(res["hh"])
	assert_str(hm.household_of(mum)).is_equal(hid)
	assert_str(mn.spouse_of(dad)).is_equal(mum)
	assert_bool(hm.marry(dad, _ch(h, 30, "f"))["ok"]).is_false()      # already married
	assert_int(hm.dependents(dad)).is_equal(1)
	var now := WorldSim.day
	hm.add_child(hid, now - 3 * 360, "f")
	hm.add_child(hid, now - 7 * 360 - 5, "m")
	hm.add_child(hid, now - 13 * 360, "f")
	hm.add_child(hid, now - 16 * 360 - 10, "m")
	var st := []
	for c: Dictionary in hm.children(hid):
		st.append(String(c["stage"]))
	assert_array(st).is_equal(["child", "school", "apprentice", "adult"])
	assert_int(hm.dependents(dad)).is_equal(5)
	# the monthly sweep: the 7-year-old is enrolled and paid for; the 16-year-old becomes a grown character with a parent
	var n0: int = mn.count()
	for d in 31:
		WorldSim.day += 1
		hm.tick_day(WorldSim.day, {})
	assert_int(hm.stats["enrolled"]).is_equal(1)
	assert_int(hm.stats["graduated"]).is_equal(1)
	assert_int(mn.count()).is_equal(n0 + 1)
	var grown: Array = mn.children_of(dad)
	assert_int(grown.size()).is_equal(1)
	assert_int(mn.age_of(String(grown[0]))).is_equal(16)
	assert_str(h.mod("dynasties").house_of(String(grown[0]))).is_equal("Hale@1")   # the child carries the father's house
	assert_int(hm.children(hid).size()).is_equal(3)
	# a family that cannot pay sends the child to work instead
	var poor1 := _ch(h, 30, "m", 3, 2)
	var poor2 := _ch(h, 28, "f", 0, 2)
	var ph: String = hm.marry(poor1, poor2, {"sid": 2})["hh"]
	hm.add_child(ph, WorldSim.day - 8 * 360, "m")
	for d in 31:
		WorldSim.day += 1
		hm.tick_day(WorldSim.day, {})
	assert_str(String(hm.children(ph)[0]["stage"])).is_equal("working")


func test_a_noble_child_goes_to_the_academy_at_nine() -> void:
	assert_str(Homes.stage_of(8, true, 1)).is_equal("school")
	assert_str(Homes.stage_of(9, true, 1)).is_equal("academy")
	assert_str(Homes.stage_of(9, false, 1)).is_equal("school")
	assert_str(Homes.stage_of(6, false, 0)).is_equal("child")
	assert_str(Homes.stage_of(12, false, 1)).is_equal("apprentice")
	assert_str(Homes.stage_of(16, true, 1)).is_equal("adult")


func test_couples_have_children_over_the_years() -> void:
	var h := _hub()
	var hm: RefCounted = h.mod("homes")
	for i in 30:
		var a := _ch(h, 26 + i % 6, "m", 600, i % 5)
		var b := _ch(h, 24 + i % 6, "f", 100, i % 5)
		hm.marry(a, b, {"sid": i % 5})
	for d in 360:
		WorldSim.day += 1
		hm.tick_day(WorldSim.day, {})
	assert_int(hm.stats["births"]).is_between(5, 30)                  # a few percent a month, not a flood
	var kids := 0
	for hid in hm._hh:
		kids += (hm._hh[hid]["kids"] as Array).size()
	assert_int(kids).is_equal(hm.stats["births"])
	for hid in hm._hh:
		assert_int((hm._hh[hid]["kids"] as Array).size()).is_less_equal(hm.KIDS_MAX)


# --- relocation inside the kingdom ----------------------------------------------------

func test_relocating_moves_the_household_ends_the_job_lets_homes_and_keeps_property() -> void:
	var h := _hub()
	var hm: RefCounted = h.mod("homes")
	var om: RefCounted = h.mod("organizations")
	var pl := _pl(h)
	om.ensure_char(pl, {"cash": 0, "sid": 0, "prof": "merchant"})
	om.gold_ref = {"gold": 20000}
	var own: Dictionary = hm.buy_home(pl, 0, "house", _offer(hm, 0, "house"))
	var rent: Dictionary = hm.rent_home(pl, 0, "hovel", _offer(hm, 0, "hovel"))
	var bid: String = h.mod("businesses").found(pl, "shop", 0, "Home Shop")["bz"]
	h.mod("businesses").hire(bid, _ch(h, 25))                         # someone else's job is not ours
	var emp: String = h.mod("businesses").found(_ch(h, 40, "m", 900), "shop", 0, "Employer")["bz"]
	h.mod("businesses").hire(emp, pl)
	assert_bool(om.employment(pl).is_empty()).is_false()
	var pid: String = h.mod("farming").found_parcel(0, Vector2(1, 1), 2, pl, "My Acre")
	var res: Dictionary = hm.relocate(pl, 2)
	assert_bool(res["ok"]).is_true()
	assert_int(hm.residence_sid(pl)).is_equal(2)
	var hh: Dictionary = hm.household(hm.household_of(pl))
	assert_int(int(hh["sid"])).is_equal(2)
	assert_bool(om.employment(pl).is_empty()).is_true()               # the job ended
	assert_int(int(om.char_rec(pl)["sid"])).is_equal(2)
	assert_bool(hm.home(String(rent["home"])).is_empty()).is_true()   # the rented hovel was given up
	assert_int(int(hm.home(String(own["home"]))["let"])).is_equal(1)  # the owned house is let out
	var kept := []
	for p: Dictionary in res["property"]:
		kept.append(String(p["kind"]))
	assert_array(kept).contains(["business", "farm", "home"])
	assert_str(String(h.mod("farming").parcel(pid)["owner"])).is_equal(pl)   # farms stay owned and run from afar
	assert_str(String(h.mod("businesses").biz(bid)["owner"])).is_equal(pl)
	assert_bool(hm.relocate(pl, 2)["ok"]).is_false()                  # already there
	assert_bool(hm.relocate(pl, 99)["ok"]).is_false()


func test_a_family_that_moves_by_road_is_a_party_and_arrives_later() -> void:
	var h := _hub()
	var hm: RefCounted = h.mod("homes")
	var mn: RefCounted = h.mod("minds")
	var dad := _ch(h, 35, "m", 300)
	var mum := _ch(h, 33, "f", 40)
	var hid: String = hm.marry(dad, mum, {"sid": 0})["hh"]
	var res: Dictionary = hm.relocate(dad, 5, {"travel": true, "buy_provisions": 80})
	assert_bool(res["ok"]).is_true()
	assert_str(String(res["tp"])).starts_with("tp:")
	assert_int(int(hm.household(hid)["sid"])).is_equal(0)             # still on the road
	assert_str(String(mn.mind(dad)["tp"])).is_equal(String(res["tp"]))
	var eta: int = hm.party(String(res["tp"]))["eta"]
	for d in range(WorldSim.day + 1, eta + 40):
		WorldSim.day = d
		hm.tick_day(d, {})
		if String(hm.party(String(res["tp"]))["st"]) != "travelling":
			break
	assert_str(String(hm.party(String(res["tp"]))["st"])).is_equal("arrived")
	assert_int(int(hm.household(hid)["sid"])).is_equal(5)
	assert_int(mn.town_of(dad)).is_equal(5)
	assert_int(mn.town_of(mum)).is_equal(5)
	assert_str(String(mn.mind(dad)["tp"])).is_equal("")


# --- relocation between kingdoms ------------------------------------------------------

func test_the_church_kingdoms_keep_a_closed_border_that_a_writ_opens() -> void:
	var h := _hub()
	var hm: RefCounted = h.mod("homes")
	var pl := _pl(h)
	h.mod("organizations").gold_ref = {"gold": 3000}
	var no: Dictionary = hm.emigrate(pl, "solmarch", "pilgrimage")
	assert_bool(no["ok"]).is_false()
	assert_str(String(no["reason"])).contains("closed")
	assert_int(hm.stats["turned_back"]).is_equal(1)
	assert_bool(hm.buy_passage(pl, "solmarch")["ok"]).is_true()
	var yes: Dictionary = hm.emigrate(pl, "solmarch", "pilgrimage")
	assert_bool(yes["ok"]).is_true()
	assert_str(hm.kingdom_of(pl)).is_equal("solmarch")
	# an open kingdom needs no writ
	var other := _ch(h, 30, "m", 500)
	assert_bool(hm.emigrate(other, "veylwood", "trade")["ok"]).is_true()
	assert_bool(hm.emigrate(other, "veylwood", "again")["ok"]).is_false()
	assert_bool(hm.emigrate(other, "nowhere", "")["ok"]).is_false()


func test_abroad_titles_are_not_recognised_licences_are_needed_and_history_is_kept() -> void:
	var h := _hub()
	var hm: RefCounted = h.mod("homes")
	var au: RefCounted = h.mod("audiences")
	var pl := _pl(h)
	h.mod("organizations").gold_ref = {"gold": 3000}
	au._rank[pl] = {"r": 3}                                             # a titled knight of Valencios
	assert_int(hm.rank_in(pl)).is_equal(3)
	assert_bool(hm.has_licence(pl, "trade")).is_true()                # at home nothing is asked
	assert_bool(hm.emigrate(pl, "seirune_isles", "to trade")["ok"]).is_true()
	assert_int(hm.rank_in(pl)).is_equal(0)                            # an unknown foreigner
	assert_bool(hm.has_licence(pl, "trade")).is_false()
	assert_bool(hm.apply_licence(pl, "trade")["ok"]).is_false()       # not resident long enough
	WorldSim.day += 25
	hm._day = WorldSim.day
	var lic: Dictionary = hm.apply_licence(pl, "trade")
	assert_bool(lic["ok"]).is_true()
	assert_bool(hm.has_licence(pl, "trade")).is_true()
	assert_bool(hm.has_licence(pl, "arms")).is_false()
	# an alliance between the two crowns lifts the title
	var dp: RefCounted = h.mod("diplomacy")
	dp._ag["pa1"] = {"id": "pa1", "type": "alliance", "a": "caldrenn", "b": "seirune_isles", "state": "active"}
	assert_bool(hm.title_recognised("caldrenn", "seirune_isles")).is_true()
	assert_int(hm.rank_in(pl)).is_equal(3)
	dp._ag.erase("pa1")
	# moving on keeps the history of every residence, and the new land's licences start over
	WorldSim.day += 40
	hm._day = WorldSim.day
	assert_bool(hm.emigrate(pl, "veylwood", "war at home")["ok"]).is_true()
	var hist: Array = hm.history(pl)
	assert_int(hist.size()).is_equal(2)
	assert_str(String((hist[0] as Array)[0])).is_equal("caldrenn")
	assert_str(String((hist[1] as Array)[0])).is_equal("seirune_isles")
	assert_bool(hm.has_licence(pl, "trade")).is_false()
	# a priest's practice licence is refused to the unbelieving in a church kingdom
	var heathen := _ch(h, 30, "m", 900)
	h.mod("faith").set_belief(heathen, "folk", 5.0)
	hm.buy_passage(heathen, "varska_marches")
	hm.emigrate(heathen, "varska_marches", "work")
	WorldSim.day += 25
	hm._day = WorldSim.day
	assert_bool(hm.apply_licence(heathen, "practice")["ok"]).is_false()


# --- travel parties -------------------------------------------------------------------

func test_a_party_needs_provisions_and_escorts_cost_gold() -> void:
	var h := _hub()
	var hm: RefCounted = h.mod("homes")
	var om: RefCounted = h.mod("organizations")
	var pl := _pl(h)
	om.gold_ref = {"gold": 1000}
	var need: int = hm.provisions_needed(0, 4, 3)
	assert_int(need).is_greater(3 * 60)                               # a long road: a few days each
	assert_int(hm.provisions_needed(0, 1, 3)).is_less(need)
	var before: int = om.purse("player")
	var r: Dictionary = hm.form_party(pl, ["ch:900", "ch:901"], 0, 4, {"escorts": 2, "buy_provisions": need, "escort_wage": 3})
	assert_bool(r["ok"]).is_true()
	assert_str(String(r["tp"])).starts_with("tp:")
	assert_int(int(r["paid"])).is_equal(before - om.purse("player"))
	assert_int(int(r["paid"])).is_greater(need * 2)
	var poor: Dictionary = hm.form_party(_ch(h, 30, "m", 5), [], 0, 4, {"escorts": 4})
	assert_bool(poor["ok"]).is_false()
	assert_bool(hm.form_party(pl, [], 0, 0)["ok"]).is_false()


func test_roads_are_protected_ordinary_or_dangerous() -> void:
	var h := _hub()
	var hm: RefCounted = h.mod("homes")
	var ar: RefCounted = h.mod("armies")
	assert_str(hm.road_status(0, 1)).is_equal("ordinary")
	hm.set_road_mod(0, 1, 0.45, WorldSim.day + 40)
	assert_str(hm.road_status(0, 1)).is_equal("dangerous")
	assert_float(hm.road_danger(0, 1)).is_greater(0.4)
	hm.set_road_mod(0, 1, 0.0, WorldSim.day + 40)
	ar.set_defence(0, {"patrols": 14, "per_shift": 6, "shifts": 2})
	ar.set_defence(1, {"patrols": 14, "per_shift": 6, "shifts": 2})
	assert_float(hm.road_protection(0, 1)).is_greater(0.1)
	assert_str(hm.road_status(0, 1)).is_equal("protected")
	assert_float(hm.road_danger(0, 1)).is_less(hm.road_danger(3, 4))
	# the danger fades with its date
	hm.set_road_mod(0, 2, 0.5, WorldSim.day + 3)
	var d0: float = hm.road_danger(0, 2)
	WorldSim.day += 5
	assert_float(hm.road_danger(0, 2)).is_less(d0)


func test_escorts_cut_the_losses_on_a_dangerous_road_and_hunger_slows_a_party() -> void:
	var h := _hub()
	var hm: RefCounted = h.mod("homes")
	hm.set_road_mod(0, 6, 0.8, WorldSim.day + 400)
	var plain := 0
	var escorted := 0
	var parties_plain: Array = []
	var parties_guard: Array = []
	for i in 12:
		var a: Dictionary = hm.form_party("ch:%d" % (500 + i), ["ch:%d" % (600 + i)], 0, 6, {"buy_provisions": 0, "provisions": 60, "gold": 0})
		parties_plain.append(a["tp"])
		var b: Dictionary = hm.form_party("ch:%d" % (700 + i), ["ch:%d" % (800 + i)], 0, 6, {"provisions": 400, "escorts": 6, "escort_wage": 0})
		parties_guard.append(b["tp"])
	for d in 25:
		WorldSim.day += 1
		hm.tick_day(WorldSim.day, {})
	for tp: String in parties_plain:
		plain += (hm.party(tp)["lost"] as Array).size()
	for tp: String in parties_guard:
		escorted += (hm.party(tp)["lost"] as Array).size()
	assert_int(hm.stats["robbed"]).is_greater(0)
	assert_int(plain).is_greater(escorted)                             # guards save lives
	# hunger: no rations at all
	var hungry: Dictionary = hm.form_party("ch:990", [], 0, 4, {"provisions": 0})
	var fed: Dictionary = hm.form_party("ch:991", [], 0, 4, {"provisions": 200})
	for d in 20:
		WorldSim.day += 1
		hm.tick_day(WorldSim.day, {})
	assert_float(float(hm.party(String(hungry["tp"]))["pos"])).is_less(float(hm.party(String(fed["tp"]))["pos"]))
	assert_int(int(hm.party(String(hungry["tp"]))["hurt"])).is_greater(0)
	assert_bool(hm.buy_rations(String(hungry["tp"]), 5)).is_false()                  # nothing to buy them with: no gold on the road


func test_parties_are_capped_and_a_party_can_turn_back() -> void:
	var h := _hub()
	var hm: RefCounted = h.mod("homes")
	var first := ""
	for i in hm.PARTY_MAX:
		var r: Dictionary = hm.form_party("ch:%d" % (1000 + i), [], 0, 4, {"provisions": 99})
		assert_bool(r["ok"]).is_true()
		if i == 0:
			first = String(r["tp"])
	assert_bool(hm.form_party("ch:2000", [], 0, 4, {"provisions": 99})["ok"]).is_false()
	assert_bool(hm.turn_back(first)).is_true()
	assert_bool(hm.turn_back(first)).is_false()
	assert_bool(hm.form_party("ch:2000", [], 0, 4, {"provisions": 99})["ok"]).is_true()
	assert_array(hm.party_history()).is_not_empty()


# --- save -----------------------------------------------------------------------------

func test_save_round_trip_is_exact_mid_journey() -> void:
	var h := _hub()
	var hm: RefCounted = h.mod("homes")
	var pl := _pl(h)
	h.mod("organizations").gold_ref = {"gold": 40000}
	hm.buy_home(pl, 0, "house", _offer(hm, 0, "house"))
	hm.rent_home(pl, 1, "cottage", _offer(hm, 1, "cottage"))
	var a := _ch(h, 33, "m")
	var b := _ch(h, 31, "f")
	var hid: String = hm.marry(a, b)["hh"]
	hm.add_child(hid, WorldSim.day - 5 * 360)
	hm.add_child(hid, WorldSim.day - 9 * 360)
	hm.form_party(pl, [a], 0, 4, {"provisions": 40, "escorts": 1})
	hm.set_road_mod(0, 4, 0.2, WorldSim.day + 30)
	hm.buy_passage(pl, "solmarch")
	hm.emigrate(pl, "solmarch", "test")
	_weeks(h, 3)
	_days(h, 6)
	var s := _norm(hm.serialize())
	var hm2: RefCounted = _hub().mod("homes")
	hm2.deserialize(JSON.parse_string(JSON.stringify(hm.serialize())))
	assert_str(_norm(hm2.serialize())).is_equal(s)
	assert_int(hm2.household_count()).is_equal(hm.household_count())
	assert_str(hm2.kingdom_of(pl)).is_equal("solmarch")
	assert_int(hm2.active_parties().size()).is_equal(hm.active_parties().size())
	assert_int(JSON.stringify(hm.serialize()).length()).is_less(20_000)
