extends GdUnitTestSuite
## LW-8 (docs/design/LIVING_WORLD_SANDBOX.md sections 11 and 12): dynasties and families as institutions: inherited businesses and land,
## family reputation, family specialties, feuds, noble succession through succession.gd and the player's family through family.gd.

const Hub := preload("res://scripts/realm/realm_hub.gd")
const Events := preload("res://scripts/realm/events.gd")

static var _ready_world := false


func _hub() -> RefCounted:
	if not _ready_world:
		WorldGen.setup(2024)
		_ready_world = true
	WorldSim.day = 200
	var h: RefCounted = Hub.new()
	var om: RefCounted = h.mod("organizations")
	om.auto_seed = false
	om.gold_ref = {"gold": 5000}
	h.mod("faith").auto_seed = false
	h.mod("minds").auto_seed = false
	h.mod("minds").set_focus(-1)
	h.mod("farming").set_day(200)
	h.mod("businesses").set_day(200)
	return h


## A grown character who is a mind of house `house`.
func _ch(h: RefCounted, house: String, age := 40, sex := "m", cash := 500, sid := 0, parent := "") -> String:
	var ch: String = h.mod("registry").mint("ch")
	h.mod("organizations").ensure_char(ch, {"cash": cash, "sid": sid, "prof": "smith", "npc": true})
	assert_bool(h.mod("minds").adopt(ch, age, sex, house, parent)).is_true()
	return ch


func _norm(d: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(d)))


# --- estates --------------------------------------------------------------------------

func test_the_eldest_adult_child_inherits_business_land_and_cash() -> void:
	var h := _hub()
	var mn: RefCounted = h.mod("minds")
	var dn: RefCounted = h.mod("dynasties")
	var om: RefCounted = h.mod("organizations")
	var father := _ch(h, "Hale@0", 58, "m", 2000)
	var wife := _ch(h, "Hale@0", 52, "f", 100)
	var kid_a := _ch(h, "Hale@0", 17, "f", 10, 0, father)
	var kid_b := _ch(h, "Hale@0", 24, "m", 10, 0, father)
	h.mod("homes").marry(father, wife)
	var bid: String = h.mod("businesses").found(father, "shop", 0, "Hale Goods")["bz"]
	var pid: String = h.mod("farming").found_parcel(0, Vector2(10, 10), 3, father, "Hale Acre")
	var cash0: int = om.purse(father)
	assert_str(dn.heir_of(father)).is_equal(kid_b)                    # the eldest, not the spouse, not the younger
	assert_bool(mn.die(father, "illness")).is_true()
	assert_bool(mn.is_alive(father)).is_false()
	assert_int(int(h.mod("businesses").biz(bid)["sh"].get(kid_b, 0))).is_equal(100)
	assert_str(String(h.mod("farming").parcel(pid)["owner"])).is_equal(kid_b)
	assert_bool(h.mod("farming").farmers().has(kid_b)).is_true()      # so the farm does not fall idle
	assert_int(om.purse(kid_b)).is_equal(10 + int(cash0 * 0.75))      # taxed like family.gd's inheritance
	assert_str(dn.head_of("Hale@0")).is_equal(kid_b)
	assert_int(dn.stats["inherited_biz"]).is_equal(1)
	assert_int(dn.stats["inherited_land"]).is_equal(1)
	assert_array(h.mod("events").of_kind("succession", 3)).is_not_empty()
	assert_str(kid_a).is_not_equal("")


func test_without_children_the_spouse_then_the_house_then_the_crown() -> void:
	var h := _hub()
	var mn: RefCounted = h.mod("minds")
	var dn: RefCounted = h.mod("dynasties")
	var a := _ch(h, "Pike@0", 60, "m")
	var b := _ch(h, "Pike@0", 55, "f")
	h.mod("homes").marry(a, b)
	assert_str(dn.heir_of(a)).is_equal(b)
	var cousin := _ch(h, "Pike@0", 30, "m")
	var lone := _ch(h, "Pike@0", 70, "m")
	mn.die(a)
	mn.die(b)
	var pid: String = h.mod("farming").found_parcel(0, Vector2(3, 3), 2, lone, "Lone Farm")
	var bid: String = h.mod("businesses").found(lone, "shop", 0, "Lone Shop")["bz"]
	mn.die(lone)
	assert_str(dn.heir_of(cousin)).is_equal("")
	# the lone man's heir was found among the living of his house; with nobody left it would escheat
	assert_str(String(h.mod("farming").parcel(pid)["owner"])).is_not_equal(lone)
	assert_bool(h.mod("businesses").biz(bid)["sh"].has(lone)).is_false()
	var nobody := _ch(h, "Dunn@0", 80, "m")
	var pid2: String = h.mod("farming").found_parcel(0, Vector2(5, 5), 2, nobody, "Escheat Farm")
	var bid2: String = h.mod("businesses").found(nobody, "shop", 0, "Orphan Shop")["bz"]
	mn.die(nobody)
	assert_str(String(h.mod("farming").parcel(pid2)["owner"])).starts_with("lord:")   # back to the Crown's steward
	assert_str(String(h.mod("businesses").biz(bid2)["st"])).is_not_equal("active")     # the business is closed and sold up
	assert_int(dn.stats["heirless"]).is_greater(0)


# --- reputation and specialty ---------------------------------------------------------

func test_a_members_deeds_move_the_family_and_the_family_moves_its_members() -> void:
	var h := _hub()
	var dn: RefCounted = h.mod("dynasties")
	var a := _ch(h, "Reed@0")
	var b := _ch(h, "Reed@0", 30)
	var rep: RefCounted = h.mod("reputation")
	assert_float(dn.family_rep("Reed@0")).is_equal(0.0)
	dn.deed(a, "charity", 0, 2.0)
	dn.deed(a, "fair_ruling", 0, 2.0)
	var good: float = dn.family_rep("Reed@0")
	assert_float(good).is_greater(0.0)
	dn.deed(b, "murder", 0, 1.0)
	assert_float(dn.family_rep("Reed@0")).is_less(good)               # one member's crime costs the whole house
	# the house's name carries to a stranger of the house in a town that has only heard of the house
	assert_bool(rep.truth("h:Reed@0").is_empty()).is_false()


func test_specialty_steers_children_and_helps_in_the_trade() -> void:
	var h := _hub()
	var dn: RefCounted = h.mod("dynasties")
	dn.ensure_house("Stone@0", 0)
	assert_str(dn.set_specialty("Stone@0", {"smith": 4, "farmer": 1})).is_equal("smith")
	assert_str(dn.set_specialty("Stone@0", {"smith": 2, "farmer": 2, "hunter": 2})).is_equal("")   # no clear trade
	dn.set_specialty("Stone@0", {"smith": 5, "farmer": 1})
	var steered := 0
	for i in 200:
		if dn.steer_trade("Stone@0", "ch:%d" % (3000 + i), "farmer") == "smith":
			steered += 1
	assert_int(steered).is_between(95, 150)                           # about six in ten
	var m := _ch(h, "Stone@0")
	assert_float(dn.skill_bonus(m, "smith")).is_greater(0.0)
	assert_float(dn.skill_bonus(m, "farmer")).is_equal(0.0)


# --- feuds ----------------------------------------------------------------------------

func test_a_killing_starts_a_feud_that_cools_flares_and_can_be_bought_off() -> void:
	var h := _hub()
	var mn: RefCounted = h.mod("minds")
	var dn: RefCounted = h.mod("dynasties")
	var om: RefCounted = h.mod("organizations")
	var v := _ch(h, "Ashby@0", 30)
	var _k := _ch(h, "Marsh@0", 28, "m", 900)
	var kh := _ch(h, "Marsh@0", 50, "m", 900)
	mn.die(v, "murder")
	dn.on_death(_ch(h, "Ashby@0", 40), "murder", kh)
	assert_float(dn.feud_heat("Ashby@0", "Marsh@0")).is_equal(70.0)
	assert_float(dn.feud_heat("Marsh@0", "Ashby@0")).is_equal(70.0)   # both houses carry it
	assert_int(dn.feuds_of("Ashby@0").size()).is_equal(1)
	assert_str(String(dn.feuds_of("Ashby@0")[0]["cause"])).is_equal("killing")
	# while hot it flares into violence now and then
	var before: int = dn.stats["violence"]
	for w in 40:
		dn.tick_week(w + 1, {})
		if dn.feud_heat("Ashby@0", "Marsh@0") < 62.0:
			dn._h["Ashby@0"]["feud"]["Marsh@0"][0] = 80.0               # keep it hot for the test
			dn._h["Marsh@0"]["feud"]["Ashby@0"][0] = 80.0
	assert_int(dn.stats["violence"]).is_greater(before)
	assert_array(h.mod("events").of_kind("crime", 10)).is_not_empty()
	# blood price: too little only cools it; enough ends it
	var heads: String = dn.head_of("Marsh@0")
	om.earn(heads, 1000)
	var part: Dictionary = dn.end_feud("Marsh@0", "Ashby@0", "blood_price", 40)
	assert_bool(part["ended"]).is_false()
	assert_float(dn.feud_heat("Marsh@0", "Ashby@0")).is_less(80.0)
	var done: Dictionary = dn.end_feud("Marsh@0", "Ashby@0", "blood_price", 400)
	assert_bool(done["ended"]).is_true()
	assert_float(dn.feud_heat("Marsh@0", "Ashby@0")).is_equal(0.0)
	assert_bool(dn.end_feud("Marsh@0", "Ashby@0", "time")["ok"]).is_false()


func test_feuds_fade_by_themselves_and_a_marriage_into_a_feuding_house_waits() -> void:
	var h := _hub()
	var mn: RefCounted = h.mod("minds")
	var dn: RefCounted = h.mod("dynasties")
	var groom := _ch(h, "Thorne@0", 25, "m", 300)
	var bride := _ch(h, "Crane@0", 23, "f", 300)
	dn.open_feud("Thorne@0", "Crane@0", "insult", 90.0)
	assert_bool(mn.perform(groom, "wed")).is_false()                 # the houses are at feud
	for w in 30:
		dn.tick_week(w + 1, {})
		if dn.feud_heat("Thorne@0", "Crane@0") < 40.0:
			break
	assert_float(dn.feud_heat("Thorne@0", "Crane@0")).is_less(45.0)
	var wed := false
	for d in range(200, 230):                                         # she may take a few tries to be won
		if mn.perform(groom, "wed", d):
			wed = true
			break
	assert_bool(wed).is_true()                                        # cooled enough: the match is made
	assert_str(mn.spouse_of(groom)).is_equal(bride)
	assert_float(dn.feud_heat("Thorne@0", "Crane@0")).is_equal(0.0)  # and the marriage ends the feud
	assert_str(dn.house_of(bride)).is_equal("Thorne@0")              # the bride takes the groom's house
	# time alone also ends a small feud
	dn.open_feud("Hale@0", "Pike@0", "slight", 12.0)
	for w in 20:
		dn.tick_week(w + 1, {})
	assert_float(dn.feud_heat("Hale@0", "Pike@0")).is_equal(0.0)


# --- nobles, succession.gd ------------------------------------------------------------

func test_old_title_holders_die_and_succession_runs() -> void:
	var h := _hub()
	var dn: RefCounted = h.mod("dynasties")
	var su: RefCounted = h.mod("succession")
	assert_int(dn.watch_nobles()).is_greater_equal(14)                # thirteen crowns and the lord of the one castle
	var holders := {}
	for key: String in dn._nob.keys():
		holders[key] = su.holder(key)
	var deaths := 0
	for w in 260:                                                      # five years of weeks
		WorldSim.day = 200 + w * 7
		su._day = WorldSim.day
		dn.tick_week(w + 1, {})
		deaths = dn.stats["noble_deaths"]
		if deaths >= 3:
			break
	assert_int(deaths).is_greater(0)
	var changed := 0
	for key: String in holders:
		if su.holder(key) != holders[key]:
			changed += 1
	assert_int(changed).is_greater(0)                                 # a new holder (or a dispute) took the seat
	assert_int(su.stats["successions"] + su.stats["disputes"]).is_greater(0)
	assert_array(h.mod("events").of_kind("death", 20)).is_not_empty()
	assert_float(DynMort.annual_risk(30)).is_less(DynMort.annual_risk(60))
	assert_float(DynMort.annual_risk(60)).is_less(DynMort.annual_risk(80))


const DynMort := preload("res://scripts/realm/dynasties.gd")


# --- the player's family, family.gd ---------------------------------------------------

class FakeFamily extends RefCounted:
	var kids := [{"age": 3, "sex": "f", "id": 1}, {"age": 9, "sex": "m", "id": 2}]
	func children_list(_d: int) -> Array:
		return kids
	func is_married() -> bool:
		return true


func test_the_players_family_becomes_a_household_and_the_line_carries_on() -> void:
	var h := _hub()
	var dn: RefCounted = h.mod("dynasties")
	var hm: RefCounted = h.mod("homes")
	var reg: RefCounted = h.mod("registry")
	var pl: String = reg.ref("pl:player")
	assert_int(dn.sync_player_family(FakeFamily.new(), pl, 0)).is_equal(2)
	var hid: String = hm.household_of(pl)
	assert_int(hm.children(hid).size()).is_equal(2)
	assert_str(String(hm.children(hid)[1]["stage"])).is_equal("school")   # nine years old: in school
	assert_str(String(hm.children(hid)[0]["stage"])).is_equal("child")
	dn.ensure_house("Ashmark", 0)
	dn.open_feud("Ashmark", "Crane@0", "debt", 60.0)
	dn.set_house(pl, "Ashmark", 0)
	var heat0: float = dn.feud_heat("Ashmark", "Crane@0")
	# family.gd writes this event when the line passes to an heir
	Events.log_to(h, "succession", "", [pl], "heir", "The player passes the line to an heir", 7)
	dn.tick_day(201, {})
	assert_float(dn.feud_heat("Ashmark", "Crane@0")).is_less(heat0)  # the heir inherits a feud but a cooler one
	assert_int(dn.stats["successions"]).is_greater(0)
	assert_int(dn.house("Ashmark")["line"].size()).is_greater(1)


# --- save -----------------------------------------------------------------------------

func test_save_round_trip_is_exact() -> void:
	var h := _hub()
	var mn: RefCounted = h.mod("minds")
	var dn: RefCounted = h.mod("dynasties")
	mn.seed_minds(60)
	dn.open_feud("Hale@0", "Pike@0", "slight", 30.0)
	dn.watch_nobles()
	for w in 10:
		dn.tick_week(w + 1, {})
	var a := _norm(dn.serialize())
	var h2 := _hub()
	var dn2: RefCounted = h2.mod("dynasties")
	dn2.deserialize(JSON.parse_string(JSON.stringify(dn.serialize())))
	assert_str(_norm(dn2.serialize())).is_equal(a)
	assert_float(dn2.feud_heat("Hale@0", "Pike@0")).is_equal(dn.feud_heat("Hale@0", "Pike@0"))
	assert_int(JSON.stringify(dn.serialize()).length()).is_less(60_000)
