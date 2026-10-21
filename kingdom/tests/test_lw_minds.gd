extends GdUnitTestSuite
## LW-8 (docs/design/LIVING_WORLD_SANDBOX.md section 11 and Part E): the five-layer decision of registry-upgraded characters, the actions they
## take through the same module APIs the player uses, the near/mid tiers and event-driven wake-ups, aggregate households far away,
## the life cycle, determinism by seed and the cost of a thousand of them.

const Hub := preload("res://scripts/realm/realm_hub.gd")
const Events := preload("res://scripts/realm/events.gd")

static var _ready_world := false


func _hub() -> RefCounted:
	if not _ready_world:
		WorldGen.setup(2024)
		_ready_world = true
	WorldSim.day = 600
	var h: RefCounted = Hub.new()
	var om: RefCounted = h.mod("organizations")
	om.auto_seed = false
	om.gold_ref = {"gold": 5000}
	h.mod("faith").auto_seed = false
	h.mod("minds").auto_seed = false
	h.mod("minds").set_focus(-1)
	for k in ["farming", "businesses", "homes"]:
		if h.mod(k).has_method("set_day"):
			h.mod(k).set_day(600)
	h.mod("businesses").set_population(0, 800)
	om.set_day(600)
	return h


func _ch(h: RefCounted, age := 30, sex := "m", cash := 500, sid := 0, prof := "smith", house := "") -> String:
	var ch: String = h.mod("registry").mint("ch")
	h.mod("organizations").ensure_char(ch, {"cash": cash, "sid": sid, "prof": prof, "npc": true, "amb": "found"})
	assert_bool(h.mod("minds").adopt(ch, age, sex, house)).is_true()
	return ch


func _day(h: RefCounted, d: int) -> void:
	WorldSim.day = d
	h.on_hour(6, d, {})
	h.drain()


func _norm(d: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(d)))


# --- identity and determinism ---------------------------------------------------------

func test_upgraded_rows_become_minds_with_ids_houses_and_belief() -> void:
	var h := _hub()
	var mn: RefCounted = h.mod("minds")
	var reg: RefCounted = h.mod("registry")
	var n: int = mn.seed_minds(120)
	assert_int(n).is_between(100, 125)
	assert_int(mn.count()).is_equal(n)
	assert_int(reg.upgraded_count()).is_equal(n)                       # each is a registry Character
	var spread := {}
	for ch: String in mn.ids():
		assert_str(ch).starts_with("ch:")
		assert_bool(reg.is_upgraded(ch)).is_true()
		assert_int(mn.age_of(ch)).is_between(16, 80)
		assert_bool(h.mod("organizations").has_char(ch)).is_true()
		assert_str(h.mod("dynasties").house_of(ch)).is_not_equal("")
		assert_float(h.mod("faith").belief_of(ch)).is_greater(0.0)
		spread[mn.town_of(ch)] = true
	assert_int(spread.size()).is_greater(10)                           # spread over the towns by population
	var row := 5
	var ch1: String = mn.ensure_row(row)
	assert_str(mn.ensure_row(row)).is_equal(ch1)                        # idempotent
	assert_str(reg.legacy_of(ch1)).is_equal("ws:%d" % row)
	assert_str(mn.ensure_row(-4)).is_equal("")
	# about half of the grown people start married, with children
	var married := 0
	for ch: String in mn.ids():
		if mn.spouse_of(ch) != "":
			married += 1
	assert_int(married).is_between(n / 5, n * 3 / 4)
	assert_int(h.mod("homes").household_count()).is_greater(10)


func test_the_cap_holds() -> void:
	var h := _hub()
	var mn: RefCounted = h.mod("minds")
	assert_int(mn.MIND_MAX).is_less_equal(h.mod("registry").CHAR_MAX - 20)
	for i in 40:
		mn.ensure_row(i * 7)
	var cap: int = mn.MIND_MAX
	mn.seed_minds(cap + 300)
	assert_int(mn.count()).is_less_equal(cap)


const LIVE := ["registry", "events", "news", "organizations", "businesses", "emergence", "faith", "dynasties", "homes", "minds", "rumours"]


## One day of only the modules this stage adds and the ones they talk to (the older realm modules draw some of their numbers from
## sources that are not seeded, so two whole-realm runs in one process are not byte-identical; these are).
func _day_live(h: RefCounted, d: int) -> void:
	WorldSim.day = d
	for k in LIVE:
		h.mod(k).tick_day(d, {})
	if d % 7 == 0:
		for k in LIVE:
			h.mod(k).tick_week(d / 7, {})


func test_two_worlds_with_the_same_seed_live_the_same_lives() -> void:
	var digests: Array = []
	for run in 2:
		var h := _hub()
		var mn: RefCounted = h.mod("minds")
		mn.seed_minds(90)
		for d in range(601, 681):
			_day_live(h, d)
		var s := {}
		for k in LIVE:
			s[k] = JSON.stringify(h.mod(k).serialize()).md5_text()          # small reports: a failing module shows by name
		digests.append(s)
		digests.append(mn.stats.duplicate())
	assert_dict(digests[0]).is_equal(digests[2])
	assert_dict(digests[1]).is_equal(digests[3])
	assert_int(int(digests[1]["decisions"])).is_greater(200)
	assert_int(int(digests[1]["wed"]) + int(digests[1]["org_join"]) + int(digests[1]["business"])).is_greater(0)


# --- the five layers ------------------------------------------------------------------

func test_layer_1_a_jobless_person_wants_work_and_a_well_off_one_does_not() -> void:
	var h := _hub()
	var mn: RefCounted = h.mod("minds")
	var a := _ch(h, 33, "m", 5)
	mn._m[a]["j"] = 1                                                  # lost the post
	mn._m[a]["sp"] = "ch:99999"                                        # (married, so marrying is not on their mind)
	assert_str(mn.intent(a)).is_equal("work")
	mn._m[a]["j"] = 0
	var b := _ch(h, 33, "m", 900)
	mn._m[b]["sp"] = "ch:99998"
	assert_str(mn.intent(b)).is_not_equal("work")


func test_layer_2_responsibilities_make_leaving_costly() -> void:
	var h := _hub()
	var mn: RefCounted = h.mod("minds")
	var em: RefCounted = h.mod("emergence")
	em.start("harvest_failure", 0)
	for d in range(600, 603):
		WorldSim.day = d
		em.tick_day(d, {})
	assert_float(float(mn.town_facts(0, 603)["hunger"])).is_greater(0.5)
	var free := _ch(h, 28, "m", 40, 0, "carpenter")
	mn._m[free]["sp"] = "ch:99997"
	var free_intents := {}
	var tied_intents := {}
	var tied := _ch(h, 28, "m", 900, 0, "merchant")
	mn._m[tied]["sp"] = "ch:99996"
	h.mod("businesses").found(tied, "shop", 0, "Tied Shop")
	mn._m[tied]["od"] = -99
	for d in range(603, 618):
		free_intents[mn.intent(free, d)] = true
		tied_intents[mn.intent(tied, d)] = true
	assert_bool(free_intents.has("move")).is_true()                       # hunger pushes the free to leave (or to petition for relief)
	assert_bool(tied_intents.has("move")).is_false()                      # the shop keeps its owner
	assert_bool(mn.perform(tied, "move")).is_false()                    # and even a forced move refuses
	var parent := _ch(h, 35, "m", 60, 0, "carpenter")
	var kid_home: String = h.mod("homes").ensure_household(parent, 0)
	for i in 4:
		h.mod("homes").add_child(kid_home, 600 - (i + 1) * 360)
	mn._m[parent]["sp"] = "ch:99995"
	assert_str(mn.intent(parent, 603)).is_not_equal("")


func test_layer_3_goals_follow_the_life_arc() -> void:
	var h := _hub()
	var mn: RefCounted = h.mod("minds")
	var young := _ch(h, 24, "m", 60, 0, "smith")
	var elder := _ch(h, 70, "m", 60, 0, "smith")
	h.mod("businesses").found(_ch(h, 40, "m", 900), "shop", 0, "Old Shop")
	var wid: String = h.mod("businesses").ids()[0]
	h.mod("businesses").hire(wid, elder)
	var intents := {}
	for d in range(600, 612):
		intents[mn.intent(young, d)] = true
	assert_bool(intents.has("wed")).is_true()                           # the young look for a partner
	mn._m[elder]["sp"] = "ch:99994"
	assert_str(mn.intent(elder)).is_equal("retire")                     # the old stop working
	var farmer := _ch(h, 30, "m", 300, 0, "farmer")
	mn._m[farmer]["sp"] = "ch:99993"
	var f_intents := {}
	for d in range(600, 612):
		f_intents[mn.intent(farmer, d)] = true
	assert_bool(f_intents.has("land")).is_true()                        # a farmer with savings wants land
	var rich := _ch(h, 38, "m", 1400, 0, "merchant")
	mn._m[rich]["sp"] = "ch:99992"
	h.mod("organizations")._c[rich]["amb"] = "found"
	var r_intents := {}
	for d in range(600, 624):
		r_intents[mn.intent(rich, d)] = true
	assert_bool(r_intents.has("business") or r_intents.has("org_found")).is_true()


func test_layer_4_relationships_decide_who_marries_whom() -> void:
	var h := _hub()
	var mn: RefCounted = h.mod("minds")
	var rm: RefCounted = h.mod("rumours")
	var groom := _ch(h, 27, "m", 200, 0, "smith", "Hale@0")
	var same_house := _ch(h, 25, "f", 900, 0, "smith", "Hale@0")        # kin, not a match
	var feud_bride := _ch(h, 25, "f", 900, 0, "smith", "Pike@0")
	var good := _ch(h, 26, "f", 100, 0, "smith", "Reed@0")
	var old := _ch(h, 51, "f", 900, 0, "smith", "Dunn@0")               # too far apart in age
	h.mod("dynasties").open_feud("Hale@0", "Pike@0", "debt", 80.0)
	rm.witness(good, "crime", groom, 30.0, 0, {"quiet": true})           # she thinks well of him
	var wed := false
	for d in range(600, 640):
		if mn.perform(groom, "wed", d):
			wed = true
			break
	assert_bool(wed).is_true()
	assert_str(mn.spouse_of(groom)).is_equal(good)
	assert_str(mn.spouse_of(good)).is_equal(groom)
	assert_str(mn.spouse_of(same_house)).is_equal("")
	assert_str(mn.spouse_of(feud_bride)).is_equal("")
	assert_str(mn.spouse_of(old)).is_equal("")
	assert_str(h.mod("homes").household_of(groom)).is_equal(h.mod("homes").household_of(good))
	assert_array(h.mod("events").of_kind("marriage", 5)).is_not_empty()
	assert_bool(mn.perform(groom, "wed", 650)).is_false()                # married men do not marry again


func test_layer_5_a_far_boom_is_unknown_until_its_news_arrives() -> void:
	var h := _hub()
	var mn: RefCounted = h.mod("minds")
	var nw: RefCounted = h.mod("news")
	nw.post("mine", 5, "A vein of ore is found near Eastmere.", 2.5, "", false, 600)
	nw._day = 600
	var before: Dictionary = mn.town_facts(0, 600)
	assert_int(int(before["boom_sid"])).is_equal(-1)                    # town 0 has not heard
	var heard_here: Dictionary = mn.town_facts(5, 600)
	assert_int(int(heard_here["boom_sid"])).is_equal(-1)                # the town itself does not "move to itself"
	var day := 600
	while int(mn.town_facts(0, day)["boom_sid"]) == -1 and day < 700:
		day += 1
	assert_int(day).is_greater(600)
	assert_int(int(mn.town_facts(0, day)["boom_sid"])).is_equal(5)      # it arrived by road, with its delay
	# and only then does a restless character think of going
	var free := _ch(h, 26, "m", 80, 0, "hunter")
	mn._m[free]["sp"] = "ch:99991"
	mn._m[free]["f"] = 3
	mn._m[free]["j"] = 1
	assert_str(mn.intent(free, day)).is_equal("move")
	var res: Dictionary = h.mod("homes").relocate(free, 5)
	assert_bool(res["ok"]).is_true()


# --- the actions go through the module APIs -------------------------------------------

func test_actions_work_and_marry_use_businesses_and_homes() -> void:
	var h := _hub()
	var mn: RefCounted = h.mod("minds")
	var om: RefCounted = h.mod("organizations")
	var boss := _ch(h, 45, "m", 1500, 0, "merchant")
	var bid: String = h.mod("businesses").found(boss, "shop", 0, "Hiring Shop")["bz"]
	var w := _ch(h, 30, "m", 5, 0, "laborer")
	mn._m[w]["j"] = 1
	assert_bool(mn.perform(w, "work")).is_true()
	assert_str(String(om.employment(w)["by"])).is_equal(bid)            # a post in the shop, through businesses.hire
	assert_int(int(mn._m[w]["j"]) & 1).is_equal(0)
	assert_int(mn.stats["work"]).is_equal(1)
	# retiring ends it
	mn._m[w]["b"] = 600 - 70 * 360
	assert_bool(mn.perform(w, "retire")).is_true()
	assert_bool(om.employment(w).is_empty()).is_true()
	assert_bool(h.mod("businesses").biz(bid)["staff"].is_empty()).is_true()


func test_actions_land_and_contract_use_farming() -> void:
	var h := _hub()
	var mn: RefCounted = h.mod("minds")
	var fm: RefCounted = h.mod("farming")
	var pid: String = fm.found_parcel(0, Vector2(20, 20), 3, "lord:crown", "Crown Acre")
	var tenant := _ch(h, 29, "m", 400, 0, "farmer")
	assert_bool(mn.perform(tenant, "land")).is_true()
	assert_bool(not fm.parcels_of(tenant).is_empty() or not fm.rented_by(tenant).is_empty()).is_true()
	assert_bool(fm.farmers().has(tenant)).is_true()
	var holder: String = String(fm.parcel(pid)["owner"]) if not fm.parcels_of(tenant).is_empty() else String(fm.parcel(pid)["ten"]["who"])
	assert_str(holder).is_equal(tenant)                                  # bought outright or let to them, through farming.gd
	assert_bool(mn.perform(_ch(h, 29, "m", 10, 0, "farmer"), "land")).is_false()   # no money, no farm
	fm._ct.append({"id": 9001, "buyer": 0, "item": "wheat", "qty": 10, "price": 3, "due": 640, "got": 0, "taker": "", "pid": "", "done": false})
	assert_bool(mn.perform(tenant, "contract")).is_true()
	assert_str(String(fm._ct[-1]["taker"])).is_equal(tenant)


func test_actions_business_and_organizations_use_the_same_calls_as_the_player() -> void:
	var h := _hub()
	var mn: RefCounted = h.mod("minds")
	var om: RefCounted = h.mod("organizations")
	var bz: RefCounted = h.mod("businesses")
	var rich := _ch(h, 36, "m", 1600, 0, "merchant")
	assert_bool(mn.perform(rich, "business")).is_true()
	assert_int(bz.owned_by(rich).size()).is_equal(1)
	assert_int(bz.stats["npc_founded"]).is_equal(1)
	var founder := _ch(h, 40, "m", 1500, 0, "smith")
	assert_bool(mn.perform(founder, "org_found")).is_true()
	assert_int(om.memberships(founder).size()).is_equal(1)
	assert_int(om.stats["founded"]).is_greater(0)
	assert_bool(mn.perform(_ch(h, 40, "m", 10, 0, "smith"), "org_found")).is_false()   # no money for the founding fee
	# joining: an active guild in town takes an applicant whose trade fits
	var lead := _ch(h, 45, "m", 3000, 1, "smith")
	var res: Dictionary = om.start_founding(lead, "craft_guild", "Smiths of Kingsreach", 1)
	assert_bool(res["ok"]).is_true()
	for i in 4:
		om.add_founder(String(res["org"]), lead, _ch(h, 30, "m", 100, 1, "smith"))
	for d in range(600, 660):
		om.tick_day(d, {})
	var joiner := _ch(h, 24, "m", 60, 1, "smith")
	var joined := false
	for d in range(600, 700):
		om.set_day(d)
		if mn.perform(joiner, "org_join", d):
			joined = true
			break
	if not om.orgs_in(1, "craft_guild").is_empty():
		assert_bool(joined).is_true()
		# the application goes in through organizations.apply; the guild's officers (or its own day tick) decide it
		var in_process: bool = not om.memberships(joiner).is_empty()
		for oid: String in om.orgs_in(1, "craft_guild"):
			in_process = in_process or (om.applicants(oid) as Array).has(joiner)
		assert_bool(in_process).is_true()


func test_actions_move_petition_and_enlist() -> void:
	var h := _hub()
	var mn: RefCounted = h.mod("minds")
	var om: RefCounted = h.mod("organizations")
	var au: RefCounted = h.mod("audiences")
	var ar: RefCounted = h.mod("armies")
	var mover := _ch(h, 26, "m", 120, 0, "hunter")
	assert_bool(mn.perform(mover, "move")).is_true()
	assert_int(mn.town_of(mover) if String(mn.mind(mover)["tp"]) == "" else int(h.mod("homes").party(String(mn.mind(mover)["tp"]))["to"])).is_not_equal(0)
	assert_int(mn.stats["move"]).is_equal(1)
	var petitioner := _ch(h, 40, "m", 80, 2, "farmer")
	om._c[petitioner]["rep"] = 40.0
	var filed0: int = au.stats["filed"] + au.stats["turned_away"]
	mn.perform(petitioner, "petition")
	assert_int(au.stats["filed"] + au.stats["turned_away"]).is_equal(filed0 + 1)    # through the audience gate (it may turn them away)
	# enlisting: a real row, an NPC army in the town
	var aid: String = ar.found("lord:crown", "garrison", "Ashford Garrison", 0, {"npc": true, "purse": 300})["id"]
	var row := 12
	var ch: String = mn.ensure_row(row)
	assert_str(ch).is_not_equal("")
	var before: int = ar.army(aid)["contracted"]
	var ok: bool = mn.perform(ch, "enlist")
	if mn.town_of(ch) == 0:
		assert_int(int(ar.army(aid)["contracted"])).is_equal(before + (1 if ok else 0))
	assert_bool(mn.perform(_ch(h, 22, "m", 10, 0, "mercenary"), "enlist")).is_false()    # no WorldSim row: cannot sign


func test_a_character_led_founding_is_walked_through_its_steps() -> void:
	var h := _hub()
	var mn: RefCounted = h.mod("minds")
	var om: RefCounted = h.mod("organizations")
	var lead := _ch(h, 41, "m", 1500, 0, "smith")
	om._c[lead]["npc"] = false                                          # (characters of this module are not in organizations.gd's own NPC list)
	var friends: Array = []
	for i in 6:
		friends.append(_ch(h, 30 + i, "m", 100, 0, "smith"))
	assert_bool(mn.perform(lead, "org_found")).is_true()
	var oid: String = om.memberships(lead)[0]
	assert_str(String(mn._m[lead]["fo"])).is_equal(oid)
	var steps: Array = []
	for d in range(600, 700):
		om.set_day(d)
		var step: String = mn.advance_founding(oid, d)
		if step != "":
			steps.append(step)
		om.tick_day(d, {})
	assert_array(steps).contains(["founder", "charter", "petition"])
	assert_int(om.member_count(oid)).is_greater_equal(2)
	assert_bool((om.org(oid)["charter"] as Dictionary).is_empty()).is_false()
	var asked := String(om.org(oid)["legal"]) != "none"                   # recognition was asked for: granted already, or still before the clerks
	for p: Dictionary in om.petitions():
		asked = asked or String(p.get("org", "")) == oid
	assert_bool(asked).is_true()
	# nothing happens for a finished founding or a stranger's organization
	om._o[oid]["stage"] = 3
	assert_str(mn.advance_founding(oid, 701)).is_equal("")
	assert_str(mn.advance_founding("org:404", 701)).is_equal("")
	# the NPC list of organizations.gd is untouched by these characters
	var n0: int = om.npc_count()
	mn.seed_minds(60)
	assert_int(om.npc_count()).is_equal(n0)


func test_the_hub_registers_the_stage_8_modules_last_and_saves_them_each_in_its_own_container() -> void:
	var h := _hub()
	var order: Array = Hub.ORDER
	var tail := order.slice(order.find("armies") + 1)
	assert_array(tail).is_equal(["emergence", "faith", "dynasties", "homes", "minds", "rumours"])
	var mn: RefCounted = h.mod("minds")
	mn.seed_minds(70)
	for d in range(601, 631):
		_day(h, d)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(h.serialize()))
	for k: String in tail:
		assert_bool(saved.has(k)).is_true()
	var h2 := _hub()
	h2.deserialize(saved)
	for k: String in tail:
		var a := JSON.stringify(h.mod(k).serialize())
		var b := JSON.stringify(h2.mod(k).serialize())
		assert_str(str(a.md5_text())).is_equal(str(b.md5_text()))
	# an old save without these containers still loads: the modules start empty and seed themselves
	var old: Dictionary = saved.duplicate()
	for k: String in tail:
		old.erase(k)
	var h3 := _hub()
	h3.deserialize(old)
	assert_int(h3.mod("minds").count()).is_equal(0)


func test_a_new_game_gets_its_first_characters_in_batches_not_in_one_job() -> void:
	var h := _hub()
	var mn: RefCounted = h.mod("minds")
	h.mod("organizations").auto_seed = true
	mn.auto_seed = true
	mn.seed_target = 200
	var counts: Array = []
	for d in range(601, 612):
		WorldSim.day = d
		for cb: Callable in mn.tick_day_chunks(d, {}):
			cb.call()
		counts.append(mn.count())
	assert_int(int(counts[0])).is_between(1, mn.SEED_PER_DAY + 1)       # the first day brings one batch
	for i in range(1, counts.size()):
		assert_int(int(counts[i]) - int(counts[i - 1])).is_less_equal(mn.SEED_PER_DAY + 3)
	assert_int(int(counts[-1])).is_between(190, 200)                     # and within a few days the world is populated
	assert_int(h.mod("homes").household_count()).is_greater(10)          # households were paired up town by town afterwards


# --- tiers, events, chunks ------------------------------------------------------------

func test_the_near_town_is_looked_at_daily_and_the_rest_every_third_day_or_less() -> void:
	var h := _hub()
	var mn: RefCounted = h.mod("minds")
	mn.seed_minds(150)
	mn.set_focus(0)
	var near: Array = mn.in_town(0)
	var far: Array = []
	for t in [1, 2, 3, 4]:
		far.append_array(mn.in_town(t))
	assert_int(near.size()).is_greater(2)
	assert_int(mn.tier_of(String(near[0]))).is_equal(1)
	assert_int(mn.tier_of(String(far[0]))).is_equal(2)
	var seen := {}
	var gaps_near := []
	var gaps_far := []
	for d in range(601, 625):
		_day(h, d)
		for ch: String in near:
			if mn.is_alive(ch):
				var n: int = int(mn._m[ch]["n"])
				if n > d and not seen.has(ch):
					seen[ch] = true
					gaps_near.append(n - d)
		for ch: String in far:
			if mn.is_alive(ch) and int(mn._m[ch]["n"]) > d and not seen.has(ch):
				seen[ch] = true
				gaps_far.append(int(mn._m[ch]["n"]) - d)
	assert_int(gaps_near.max()).is_less_equal(1 + 5)                    # near: next day (after backoff when an attempt failed)
	var near_mean := float(_sum(gaps_near)) / float(gaps_near.size())
	var far_mean := float(_sum(gaps_far)) / float(gaps_far.size())
	assert_float(far_mean).is_greater(near_mean)
	assert_float(far_mean).is_less(8.0)


func _sum(a: Array) -> int:
	var t := 0
	for x in a:
		t += int(x)
	return t


func test_a_change_in_the_world_wakes_a_sleeper_early() -> void:
	var h := _hub()
	var mn: RefCounted = h.mod("minds")
	var ch := _ch(h, 33)
	mn._m[ch]["n"] = 640
	mn._schedule(ch, 640)
	mn.poke(ch)
	assert_int(int(mn._m[ch]["n"])).is_equal(601)
	var woke: int = mn.poke_town(0, 5)
	assert_int(woke).is_equal(1)
	assert_int(mn.stats["pokes"]).is_greater(0)
	# unknown ids do nothing
	mn.poke("ch:404404")


func test_the_day_comes_in_small_chunks_and_each_stays_inside_its_time() -> void:
	var h := _hub()
	var mn: RefCounted = h.mod("minds")
	mn.seed_minds(300)
	var worst := 0
	var chunks := 0
	var total := 0
	for d in range(601, 616):
		WorldSim.day = d
		mn._day = d
		var jobs: Array = mn.tick_day_chunks(d, {})
		chunks += jobs.size()
		for cb: Callable in jobs:
			var t0 := Time.get_ticks_usec()
			cb.call()
			var dt := Time.get_ticks_usec() - t0
			total += dt
			worst = maxi(worst, dt)
	assert_int(chunks).is_greater(15 * 10)                              # many small jobs, not one big one
	assert_int(worst).is_less(12_000)                                   # no job near a frame (container noise allowed)
	assert_float(float(total) / float(chunks)).is_less(1200.0)          # about a millisecond or less on average even on this slow box
	# direct callers and the hub get the same result: tick_day runs the chunks in order
	var h2 := _hub()
	var m2: RefCounted = h2.mod("minds")
	m2.seed_minds(300)
	var h3 := _hub()
	var m3: RefCounted = h3.mod("minds")
	m3.seed_minds(300)
	WorldSim.day = 601
	m2.tick_day(601, {})
	for cb: Callable in m3.tick_day_chunks(601, {}):
		cb.call()
	assert_str(_norm(m2.serialize())).is_equal(_norm(m3.serialize()))


# --- aggregate households -------------------------------------------------------------

func test_far_idle_untied_people_fold_into_the_town_count_and_come_back_when_needed() -> void:
	var h := _hub()
	var mn: RefCounted = h.mod("minds")
	var reg: RefCounted = h.mod("registry")
	var far_sid := 21
	assert_float((WorldGen.settlements[far_sid]["pos"] as Vector2).distance_to(WorldGen.settlements[0]["pos"])).is_greater(mn.REGION_RADIUS)
	mn.aggregate_far = true
	var far_one := _ch(h, 50, "m", 75, far_sid, "laborer")
	var near_one := _ch(h, 50, "m", 75, 0, "laborer")
	var tied := _ch(h, 50, "m", 75, far_sid, "laborer")
	h.mod("businesses").found(_ch(h, 40, "m", 900, far_sid), "shop", far_sid, "Far Shop")
	h.mod("businesses").hire(h.mod("businesses").ids()[0], tied)
	mn.set_focus(0)
	var wealth0: int = mn.agg_wealth(far_sid)
	for d in range(601, 660):
		for c in [far_one, near_one, tied]:
			if mn.is_alive(c):
				mn._m[c]["g"] = 0
		_day(h, d)
	assert_bool(mn.is_alive(far_one)).is_false()                        # folded into the count
	assert_bool(mn.is_alive(near_one)).is_true()                        # near the player: still a person
	assert_bool(mn.is_alive(tied)).is_true()                            # employed: still a person
	assert_int(mn.stats["demoted"]).is_greater(0)
	assert_int(mn.agg_wealth(far_sid)).is_greater(wealth0)                   # its purse went to the households
	assert_bool(reg.is_upgraded(far_one)).is_false()                    # the record is freed for someone else
	assert_str(reg.lookup("ws:900")).is_equal("")
	# referencing a row brings a person back
	var back: String = mn.ensure_row(WorldSim.ranges[far_sid].x + 3)
	assert_str(back).is_not_equal("")
	assert_bool(mn.is_alive(back)).is_true()
	# and with no player at all nobody is "far"
	var h2 := _hub()
	var m2: RefCounted = h2.mod("minds")
	m2.aggregate_far = true
	m2.set_focus(-1)
	var c2 := _ch(h2, 50, "m", 75, far_sid, "laborer")
	for d in range(601, 660):
		m2._m[c2]["g"] = 0
		_day(h2, d)
	assert_bool(m2.is_alive(c2)).is_true()


func test_aggregate_wealth_moves_with_tithes_and_hardship() -> void:
	var h := _hub()
	var mn: RefCounted = h.mod("minds")
	var w0: int = mn.agg_wealth(3)
	var took: int = mn.agg_take(3, 100000)
	assert_int(took).is_equal(int(float(w0) * 0.03))                    # at most three percent at a time
	assert_int(mn.agg_wealth(3)).is_equal(w0 - took)
	mn.agg_add(3, 500)
	assert_int(mn.agg_wealth(3)).is_equal(w0 - took + 500)
	assert_int(mn.agg_households(3)).is_greater(10)
	for w in 30:
		mn.tick_week(w, {})
	assert_int(mn.agg_wealth(3)).is_greater(w0 - took)                  # households recover toward their level


# --- the life cycle -------------------------------------------------------------------

func test_death_settles_the_estate_frees_the_record_and_widows_the_spouse() -> void:
	var h := _hub()
	var mn: RefCounted = h.mod("minds")
	var reg: RefCounted = h.mod("registry")
	var hm: RefCounted = h.mod("homes")
	var husband := _ch(h, 62, "m", 700, 0, "smith", "Oakes@0")
	var wife := _ch(h, 55, "f", 50, 0, "smith")
	var res: Dictionary = hm.marry(husband, wife)
	var son := _ch(h, 28, "m", 20, 0, "smith", "Oakes@0")
	mn._m[son]["pa"] = husband
	mn._kids[husband] = [son]
	assert_bool(mn.die(husband, "illness")).is_true()
	assert_bool(reg.is_upgraded(husband)).is_false()
	assert_array(reg.history()).is_not_empty()
	assert_str(mn.spouse_of(wife)).is_equal("")
	assert_str(hm.household_of(husband)).is_equal("")
	assert_str(String(hm.household(String(res["hh"]))["head"])).is_equal(wife)
	assert_int(h.mod("organizations").purse(son)).is_greater(500)       # the son had the cash
	assert_str(mn.mind(son)["pa"] if mn.mind(son).has("pa") else "").is_equal("")
	assert_bool(mn.die(husband)).is_false()                             # once only
	assert_int(mn.stats["deaths"]).is_equal(1)
	assert_array(h.mod("events").of_kind("death", 5)).is_not_empty()


func test_age_decides_the_odds_of_dying_and_a_fever_raises_them() -> void:
	var Minds := preload("res://scripts/realm/minds.gd")
	assert_float(Minds.annual_death_risk(30)).is_less(Minds.annual_death_risk(50))
	assert_float(Minds.annual_death_risk(50)).is_less(Minds.annual_death_risk(70))
	assert_float(Minds.annual_death_risk(70)).is_less(Minds.annual_death_risk(80))
	var h := _hub()
	var mn: RefCounted = h.mod("minds")
	var calm := 0
	var sick := 0
	for i in 400:
		var c := _ch(h, 70, "m", 5, 3)
		mn._m[c]["y"] = 600                                              # birthday today
		var rec_before: bool = mn.is_alive(c)
		mn._birthday(c, mn._m[c], 600 + i % 7)
		calm += 0 if mn.is_alive(c) else 1
		assert_bool(rec_before).is_true()
	h.mod("emergence").start("epidemic", 3, {"data": {"sev": 1.4}})
	for d in range(600, 603):
		WorldSim.day = d
		h.mod("emergence").tick_day(d, {})
	for i in 400:
		var c := _ch(h, 70, "m", 5, 3)
		mn._m[c]["y"] = 600
		mn._birthday(c, mn._m[c], 603 + i % 7)
		sick += 0 if mn.is_alive(c) else 1
	assert_int(calm).is_between(15, 60)                                  # about 8% of 400 seventy-year-olds
	assert_int(sick).is_greater(calm)


func test_children_grow_up_into_minds_with_their_parents_trade_and_house() -> void:
	var h := _hub()
	var mn: RefCounted = h.mod("minds")
	var hm: RefCounted = h.mod("homes")
	var dn: RefCounted = h.mod("dynasties")
	dn.ensure_house("Marsh@1", 1)
	dn.set_specialty("Marsh@1", {"smith": 6})
	var dad := _ch(h, 44, "m", 500, 1, "smith", "Marsh@1")
	var mum := _ch(h, 41, "f", 100, 1, "smith")
	var hid: String = hm.marry(dad, mum, {"sid": 1})["hh"]
	var smiths := 0
	for i in 10:
		hm.add_child(hid, 600 - 16 * 360 - 3 * i)
	for d in range(601, 640):
		WorldSim.day = d
		hm.tick_day(d, {})
	assert_int(mn.children_of(dad).size()).is_greater(5)
	for k: Variant in mn.children_of(dad):
		assert_str(dn.house_of(String(k))).is_equal("Marsh@1")
		assert_int(mn.age_of(String(k))).is_equal(16)
		assert_int(mn.town_of(String(k))).is_equal(1)
		if h.mod("organizations").profession(String(k)) == "smith":
			smiths += 1
		assert_bool(h.mod("registry").is_upgraded(String(k))).is_true()
	assert_int(smiths).is_greater(2)                                     # the house steers its children to its trade


# --- save and budgets -----------------------------------------------------------------

func test_save_round_trip_and_the_save_stays_small() -> void:
	var h := _hub()
	var mn: RefCounted = h.mod("minds")
	mn.seed_minds(200)
	for d in range(601, 630):
		_day(h, d)
	var s1 := _norm(mn.serialize())
	var h2 := _hub()
	h2.mod("organizations").deserialize(JSON.parse_string(JSON.stringify(h.mod("organizations").serialize())))
	var m2: RefCounted = h2.mod("minds")
	m2.deserialize(JSON.parse_string(JSON.stringify(mn.serialize())))
	assert_str(_norm(m2.serialize())).is_equal(s1)
	assert_int(m2.count()).is_equal(mn.count())
	for t in 30:
		assert_int(m2.town_count(t)).is_equal(mn.town_count(t))
	assert_int(JSON.stringify(mn.serialize()).length()).is_less(45_000)  # about 200 B a person including the aggregate table
