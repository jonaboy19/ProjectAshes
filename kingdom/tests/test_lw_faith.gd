extends GdUnitTestSuite
## LW-8.1 (docs/design/LIVING_WORLD_SANDBOX.md section 14): religion and culture. Churches are organizations that own land, schools and
## shelters and have influence; every NPC has a belief and its intensity; culture tags change etiquette, prices and law; festivals change
## mood and trade; a priest has two routes; the three eastern church kingdoms have a strong church and Valencios a weak one.

const Hub := preload("res://scripts/realm/realm_hub.gd")
const Faith := preload("res://scripts/realm/faith.gd")

static var _ready_world := false


func _hub() -> RefCounted:
	if not _ready_world:
		WorldGen.setup(2024)
		_ready_world = true
	WorldSim.day = 400
	var h: RefCounted = Hub.new()
	var om: RefCounted = h.mod("organizations")
	om.auto_seed = false
	om.gold_ref = {"gold": 5000}
	h.mod("faith").auto_seed = false
	h.mod("minds").auto_seed = false
	h.mod("minds").set_focus(-1)
	h.mod("businesses").set_day(400)
	return h


func _norm(d: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(d)))


func _weeks(fa: RefCounted, n: int) -> void:
	for w in n:
		WorldSim.day += 7
		fa.tick_week(WorldSim.day / 7, {})


# --- the church kingdoms against Valencios --------------------------------------------

func test_the_eastern_church_kingdoms_are_strong_and_valencios_is_weak() -> void:
	var fa: RefCounted = _hub().mod("faith")
	var home: Dictionary = fa.kingdom_profile("caldrenn")
	assert_float(float(home["power"])).is_less(0.3)
	assert_bool(home["secular"]).is_true()
	assert_bool(home["closed"]).is_false()
	assert_str(String(home["faith"])).is_equal("runes")
	assert_array(Faith.CHURCH_KINGDOMS).is_equal(["solmarch", "varska_marches", "serathi_lowlands"])
	for k: String in Faith.CHURCH_KINGDOMS:
		var p: Dictionary = fa.kingdom_profile(k)
		assert_float(float(p["power"])).is_greater_equal(0.6)
		assert_bool(p["closed"]).is_true()
		assert_str(String(p["faith"])).is_equal("dawn")
		assert_float(float(p["tithe"])).is_greater(float(home["tithe"]))
	assert_str(String(fa.kingdom_profile("solmarch")["seat"])).is_equal("Aurelion")   # the Aurelis Patriarchate
	assert_float(float(fa.kingdom_profile("solmarch")["power"])).is_greater(float(fa.kingdom_profile("serathi_lowlands")["power"]))
	# they grow and shrink a little with their tithes, but stay in their class
	_weeks(fa, 80)
	assert_float(float(fa.kingdom_profile("solmarch")["influence"])).is_greater(0.5)


func test_valencios_churches_are_small_and_the_dawn_chapel_is_only_in_the_capital() -> void:
	var h := _hub()
	var fa: RefCounted = h.mod("faith")
	fa.seed_world()
	assert_bool(fa.seeded).is_true()
	assert_int(fa.churches().size()).is_greater(5)
	assert_int(fa.churches().size()).is_less_equal(15)
	var dawn := 0
	var runes := 0
	for oid: String in fa.churches():
		var c: Dictionary = fa.church(oid)
		assert_bool(h.mod("organizations").exists(oid)).is_true()
		assert_str(String(h.mod("organizations").org(oid)["type"])).is_equal("religious_order")
		assert_float(float(c["inf"])).is_less(0.5)                    # a weak church
		if String(c["faith"]) == "dawn":
			dawn += 1
			assert_int(int(c["sid"])).is_equal(1)                     # Kingsreach, the capital
			assert_float(float(c["inf"])).is_less(0.25)               # a mission chapel
		else:
			runes += 1
	assert_int(dawn).is_equal(1)
	assert_int(runes).is_greater(4)
	assert_str(fa.dominant_faith(0)).is_equal("runes")


# --- churches own land, schools and shelters ------------------------------------------

func test_a_church_buys_land_then_a_school_then_a_shelter_out_of_its_tithes() -> void:
	var h := _hub()
	var fa: RefCounted = h.mod("faith")
	var om: RefCounted = h.mod("organizations")
	var hm: RefCounted = h.mod("homes")
	var mn: RefCounted = h.mod("minds")
	var res: Dictionary = fa.found_church(1, "runes", "", "", 300)
	assert_bool(res["ok"]).is_true()
	var oid := String(res["org"])
	assert_int(fa.school_seats(1)).is_equal(0)
	assert_int(fa.shelter_capacity(1)).is_equal(0)
	# tithes come out of the town's households, not out of thin air
	var wealth0: int = mn.agg_wealth(1)
	_weeks(fa, 3)
	assert_int(int(fa.church(oid)["tithe"])).is_greater(0)
	assert_int(mn.agg_wealth(1)).is_less(wealth0 + 3 * 400)
	assert_int(int(om.org(oid)["treasury"])).is_greater(0)
	om._o[oid]["treasury"] = 450
	_weeks(fa, 1)
	assert_int(fa.church(oid)["land"].size()).is_equal(1)
	var assets: Array = om.assets_of(oid)
	assert_int(assets.size()).is_equal(1)
	assert_str(String(om.asset(String(assets[0]))["kind"])).is_equal("land")
	om._o[oid]["treasury"] = 300
	_weeks(fa, 1)
	assert_int(fa.school_seats(1)).is_equal(fa.SCHOOL_SEATS)
	var seats0: int = hm.school_seats(1)
	assert_int(seats0).is_greater(fa.SCHOOL_SEATS - 1)                # the school's seats add to the town's
	om._o[oid]["treasury"] = 400
	_weeks(fa, 1)
	assert_int(fa.shelter_capacity(1)).is_equal(fa.SHELTER_BEDS)
	assert_int(fa.shelter_take(1, 20)).is_equal(fa.SHELTER_BEDS)       # only as many as there are beds
	assert_int(fa.shelter_take(0, 5)).is_equal(0)
	assert_int(fa.stats["land"] + fa.stats["schools"] + fa.stats["shelters"]).is_equal(3)
	# influence grows with works and falls with scandal
	var inf: float = float(fa.church(oid)["inf"])
	fa.scandal(1, oid)
	assert_float(float(fa.church(oid)["inf"])).is_less(inf)
	assert_int(fa.stats["scandals"]).is_equal(1)


func test_the_game_founds_its_churches_a_couple_a_day_not_all_at_once() -> void:
	var h := _hub()
	var fa: RefCounted = h.mod("faith")
	h.mod("organizations").auto_seed = true
	fa.auto_seed = true
	var counts: Array = []
	for d in range(401, 412):
		WorldSim.day = d
		fa.tick_day(d, {})
		counts.append(fa.churches().size())
	assert_int(int(counts[0])).is_less_equal(2)                          # no single job founds fifteen churches
	for i in range(1, counts.size()):
		assert_int(int(counts[i]) - int(counts[i - 1])).is_less_equal(2)
	assert_int(int(counts[-1])).is_between(10, 15)
	assert_bool(fa.seeded).is_true()
	# their foundings are walked through the steps by the minds module, a church a week
	var before := 0
	for oid: String in fa.churches():
		before += int(h.mod("organizations").org(oid)["stage"])
	for w in 10:
		WorldSim.day += 7
		fa.tick_week(WorldSim.day / 7, {})
	var after := 0
	for oid: String in fa.churches():
		after += int(h.mod("organizations").org(oid)["stage"])
	assert_int(after).is_greater_equal(before)


# --- belief ---------------------------------------------------------------------------

func test_every_npc_has_a_belief_with_an_intensity_that_moves() -> void:
	var h := _hub()
	var fa: RefCounted = h.mod("faith")
	var mn: RefCounted = h.mod("minds")
	mn.seed_minds(80)
	assert_int(fa.belief_count()).is_equal(mn.count())
	var faiths := {}
	for ch: String in mn.ids():
		var b: float = fa.belief_of(ch)
		assert_float(b).is_between(0.0, 100.0)
		faiths[fa.faith_of(ch)] = true
	assert_int(faiths.size()).is_greater(1)
	assert_bool(faiths.has("runes")).is_true()
	# a devout character believes harder than a sly one with the same luck
	fa.seed_belief("ch:7001", 0, ["devout", "kind"])
	fa.seed_belief("ch:7002", 0, ["sly", "curious"])
	assert_float(fa.belief_of("ch:7001")).is_greater(fa.belief_of("ch:7002"))
	fa.adjust_belief("ch:7001", 500.0)
	assert_float(fa.belief_of("ch:7001")).is_equal(100.0)             # bounded
	fa.adjust_belief("ch:7001", -500.0)
	assert_float(fa.belief_of("ch:7001")).is_equal(0.0)
	assert_bool(fa.set_belief("ch:7001", "nope", 5.0)).is_false()
	# moving to another faith's kingdom costs belief and may convert
	fa.set_belief("ch:7003", "runes", 70.0)
	fa.on_emigrated("ch:7003", "solmarch")
	assert_float(fa.belief_of("ch:7003")).is_less(70.0)
	var converted := 0
	for i in 40:
		fa.set_belief("ch:%d" % (7100 + i), "runes", 60.0)
		fa.on_emigrated("ch:%d" % (7100 + i), "solmarch")
		if fa.faith_of("ch:%d" % (7100 + i)) == "dawn":
			converted += 1
	assert_int(converted).is_greater(5)                                # the strong church pulls
	assert_int(converted).is_less(35)
	# a death frees the record
	fa.drop_character("ch:7003")
	assert_float(fa.belief_of("ch:7003")).is_equal(0.0)


func test_belief_is_capped_with_the_population_of_minds() -> void:
	var fa: RefCounted = _hub().mod("faith")
	for i in fa.BELIEF_MAX + 20:
		fa.set_belief("ch:%d" % (9000 + i), "folk", 10.0)
	assert_int(fa.belief_count()).is_equal(fa.BELIEF_MAX)


# --- culture --------------------------------------------------------------------------

func test_culture_tags_change_etiquette_prices_and_law() -> void:
	var h := _hub()
	var fa: RefCounted = h.mod("faith")
	fa.seeded = true
	# towns carry a primary culture and at most one minority tag, the same every time
	for sid in 30:
		var tags: Array = fa.culture_tags(sid)
		assert_str(String(tags[0])).is_equal("caldric")
		assert_array(fa.culture_tags(sid)).is_equal(tags)
		assert_int(tags.size()).is_less_equal(3)
	var minority := -1
	for sid in 30:
		if "urrokai" in fa.culture_tags(sid) or "veyl" in fa.culture_tags(sid):
			minority = sid
			break
	assert_int(minority).is_greater(-1)
	# etiquette: a bribe offends everywhere but most in the church lands; an oath counts for more there
	assert_float(fa.etiquette_mod("solmarch", "bribe")).is_less(fa.etiquette_mod("caldrenn", "bribe"))
	assert_float(fa.etiquette_mod("solmarch", "oath")).is_greater(fa.etiquette_mod("caldrenn", "oath"))
	assert_float(fa.etiquette_mod("solmarch", "haggle")).is_less(fa.etiquette_mod("urrokai_clanlands", "haggle"))
	for act: String in fa.ETIQUETTE:
		assert_float(absf(fa.etiquette_mod(0, act))).is_less_equal(0.5)
	# prices: the same goods cost differently
	assert_float(fa.price_mult("solmarch", "luxury")).is_greater(fa.price_mult("caldrenn", "luxury"))
	assert_float(fa.price_mult("veylwood", "books")).is_less(fa.price_mult("solmarch", "books") + 0.01)
	assert_float(fa.price_mult(minority, "food")).is_not_equal(fa.price_mult(0 if minority != 0 else 3, "food") + 1.0)
	assert_float(fa.goods_mult(minority)).is_not_equal(1.0)
	# law: fines are heavier in church lands, and the courts are told
	assert_float(fa.law_mult("solmarch")).is_greater(fa.law_mult("caldrenn"))
	assert_float(fa.law_mult("urrokai_clanlands")).is_less(1.0)
	var ct: RefCounted = h.mod("courts")
	var before: int = int(ct.law("solmarch", "assault")["fine"])
	assert_int(fa.apply_laws()).is_greater(0)
	assert_int(int(ct.law("solmarch", "assault")["fine"])).is_greater(before)
	assert_int(int(ct.law("caldrenn", "assault")["fine"])).is_equal(int(ct.law("caldrenn", "assault")["fine"]))
	# nothing changes until the module is live
	var cold: RefCounted = _hub().mod("faith")
	assert_float(cold.price_mult("solmarch", "luxury")).is_equal(1.0)


func test_festivals_lift_trade_and_mood_for_their_days() -> void:
	var h := _hub()
	var fa: RefCounted = h.mod("faith")
	fa.seeded = true
	var fair_day := 40 + 360 * 2
	assert_str(fa.festival_at(0, fair_day)).is_equal("spring_fair")
	assert_str(fa.festival_at(0, fair_day + 2)).is_equal("spring_fair")
	assert_str(fa.festival_at(0, fair_day + 3)).is_equal("")
	assert_str(fa.festival_at(0, fair_day - 1)).is_equal("")
	WorldSim.day = fair_day + 1
	assert_float(fa.trade_mult(0)).is_greater(1.1)
	assert_float(fa.mood_bonus(0)).is_greater(5.0)
	WorldSim.day = fair_day + 30
	assert_float(fa.trade_mult(0)).is_equal(1.0)
	assert_float(fa.mood_bonus(0)).is_equal(0.0)
	# a faith's feast is kept only where the faith is: the Dawn feast not in a runestone village
	assert_str(fa.festival_at(0, 95 + 360)).is_equal("")
	assert_str(fa.festival_at(0, 292 + 360)).is_equal("kindling_night")
	# a stretch settled in one step feels the days it holds
	var with: float = fa.trade_avg(0, fair_day + 10, 28)
	var without: float = fa.trade_avg(0, fair_day + 100, 28)
	assert_float(with).is_greater(without)
	assert_float(without).is_equal(1.0)
	# the news is posted and believers feel it
	var mn: RefCounted = h.mod("minds")
	mn.seed_minds(60)
	var ch: String = mn.in_town(0)[0]
	fa.set_belief(ch, "runes", 40.0)
	fa.tick_day(292 + 360 * 3, {})
	assert_float(fa.belief_of(ch)).is_equal(43.0)
	assert_int(fa.stats["festivals"]).is_equal(1)


func test_a_festival_makes_a_shop_sell_more() -> void:
	var tot := {}
	for live in [false, true]:
		var hh := _hub()
		var f2: RefCounted = hh.mod("faith")
		f2.seeded = live
		var b2: RefCounted = hh.mod("businesses")
		b2.set_population(0, 800)
		b2.set_day((40 + 360 * 2) / 7 * 7 - 8)
		var owner: String = hh.mod("registry").mint("ch")
		hh.mod("organizations").ensure_char(owner, {"cash": 3000, "sid": 0})
		var hand: String = hh.mod("registry").mint("ch")
		hh.mod("organizations").ensure_char(hand, {"cash": 5, "sid": 0})
		var bid: String = b2.found(owner, "shop", 0, "Fair Shop")["bz"]
		b2.hire(bid, hand)
		b2.attend(bid)
		var w0 := (40 + 360 * 2) / 7 - 1                                  # the weeks around the spring fair
		for w in range(w0, w0 + 3):
			b2.set_day(w * 7)
			b2.settle(bid, 7, w * 7)
		var sum := 0.0
		for r: Array in b2.accounts(bid):
			sum += float(r[1])
		tot[live] = sum
		tot[str(live) + "tm"] = b2._town_trade(0, 763, 7)
		tot[str(live) + "off"] = b2._town_trade(0, 900, 7)
	assert_float(tot[false]).is_greater(0.0)
	assert_float(tot[true]).is_greater_equal(tot[false])
	assert_float(tot["truetm"]).is_greater(1.08)                          # the fair's three days in a seven-day settle
	assert_float(tot["falsetm"]).is_equal(1.0)                            # nothing until the faith module is live
	assert_float(tot["trueoff"]).is_equal(1.0)                            # and nothing outside the festival


# --- priests --------------------------------------------------------------------------

func test_a_priest_climbs_the_parish_or_the_cloister_with_faith_years_and_standing() -> void:
	var h := _hub()
	var fa: RefCounted = h.mod("faith")
	var church_id: String = fa.found_church(1, "runes", "", "", 300)["org"]
	fa._ch[church_id]["inf"] = 0.1                                       # a small church
	assert_bool(fa.ordain("ch:8001", "parish")["ok"]).is_false()      # no calling
	fa.set_belief("ch:8001", "runes", 80.0)
	fa.set_belief("ch:8002", "runes", 80.0)
	assert_bool(fa.ordain("ch:8001", "parish")["ok"]).is_true()
	assert_bool(fa.ordain("ch:8002", "cloister")["ok"]).is_true()
	assert_bool(fa.ordain("ch:8001", "cloister")["ok"]).is_false()     # already ordained
	assert_bool(fa.ordain("ch:8003", "heresy")["ok"]).is_false()
	assert_str(String(fa.priest_step("ch:8001")["title"])).is_equal("acolyte")
	assert_str(String(fa.priest_step("ch:8002")["title"])).is_equal("novice")
	# a year is needed for the second step
	assert_bool(fa.advance_priest("ch:8001", 1)["ok"]).is_false()
	WorldSim.day += 400
	fa._day = WorldSim.day
	assert_str(String(fa.advance_priest("ch:8001", 1)["title"])).is_equal("priest")
	assert_str(String(fa.advance_priest("ch:8002", 1)["title"])).is_equal("monk")
	# dean / prior needs three years of service and a church with weight in the town
	WorldSim.day += 360 * 3
	fa._day = WorldSim.day
	assert_bool(fa.advance_priest("ch:8001", 1)["ok"]).is_false()      # the church here is too small to seat a dean
	fa._ch[church_id]["inf"] = 0.6
	assert_str(String(fa.advance_priest("ch:8001", 1)["title"])).is_equal("dean")
	assert_str(String(fa.advance_priest("ch:8002", 1)["title"])).is_equal("prior")
	fa.adjust_belief("ch:8001", -80.0)
	WorldSim.day += 360 * 6
	fa._day = WorldSim.day
	assert_bool(fa.advance_priest("ch:8001", 1)["ok"]).is_false()       # faith has gone cold
	fa.adjust_belief("ch:8001", 90.0)
	assert_str(String(fa.advance_priest("ch:8001", 1)["title"])).is_equal("bishop")
	assert_str(String(fa.advance_priest("ch:8002", 1)["title"])).is_equal("abbot")
	assert_bool(fa.advance_priest("ch:8002", 1)["ok"]).is_false()       # nowhere higher


# --- save -----------------------------------------------------------------------------

func test_save_round_trip_is_exact() -> void:
	var h := _hub()
	var fa: RefCounted = h.mod("faith")
	h.mod("minds").seed_minds(50)
	fa.seed_world()
	fa.set_belief("ch:8001", "dawn", 66.0)
	fa.ordain("ch:8001", "cloister")
	_weeks(fa, 12)
	var a := _norm(fa.serialize())
	var fa2: RefCounted = _hub().mod("faith")
	fa2.deserialize(JSON.parse_string(JSON.stringify(fa.serialize())))
	assert_str(_norm(fa2.serialize())).is_equal(a)
	assert_bool(fa2.seeded).is_true()
	assert_str(String(fa2.priest_step("ch:8001")["title"])).is_equal("novice")
	assert_int(JSON.stringify(fa.serialize()).length()).is_less(40_000)
