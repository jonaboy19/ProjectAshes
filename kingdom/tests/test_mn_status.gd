extends GdUnitTestSuite
## MN-6/7: the Status model (monotonic components, company clamp, culture differences, legitimacy) and town gates (every verdict path,
## options, bribe price vs corruption, forged permits, disguises, curfew, forecast lines, determinism).

const Status := preload("res://scripts/realm/status.gd")
const Gate := preload("res://scripts/realm/entry_law.gd")
const Hub := preload("res://scripts/realm/realm_hub.gd")


func _orc(extra := {}) -> Dictionary:
	var c := {"species": "orc", "kind": "monster", "speech": 2, "civility": 0.6, "named": true, "power": 3, "form": 2, "bond_id": 1}
	c.merge(extra, true)
	return c


func _s(sub: Dictionary, culture: String, kingdom := "") -> Dictionary:
	return Status.of(sub, {"culture": culture, "kingdom": kingdom})


func test_each_component_is_monotonic() -> void:
	var base := {"title_rank": 1, "wealth": 0.3, "rep": {"trust": 0, "reliability": 0, "legitimacy": 0, "cruelty": 0}, "faith_standing": 0.0, "guild_rank": 0.2, "fame": 10, "infamy": 10}
	var v0: float = _s(base, "caldric")["value"]
	for k in [["title_rank", 4], ["wealth", 0.9], ["faith_standing", 0.8], ["guild_rank", 0.9], ["fame", 80]]:
		var s := base.duplicate(true)
		s[k[0]] = k[1]
		assert_float(_s(s, "caldric")["value"]).is_greater(v0)
	var hi := base.duplicate(true)
	hi["rep"] = {"trust": 80, "reliability": 80, "legitimacy": 80, "cruelty": 0}
	assert_float(_s(hi, "caldric")["value"]).is_greater(v0)
	var inf := base.duplicate(true)
	inf["infamy"] = 90
	assert_float(_s(inf, "caldric")["value"]).is_less(v0)
	var cruel := base.duplicate(true)
	cruel["rep"] = {"trust": 0, "reliability": 0, "legitimacy": 0, "cruelty": 80}
	assert_float(_s(cruel, "caldric")["value"]).is_less(v0)


func test_company_is_clamped_and_never_buys_nobility() -> void:
	var pack: Array = []
	for i in 12:
		pack.append(_orc())
	var neg := _s({"companions": pack}, "solenne")
	assert_float(neg["company"]).is_equal_approx(-0.25, 0.0001)
	var wolves: Array = []
	for i in 12:
		wolves.append({"species": "wolf", "kind": "beast", "speech": 2, "civility": 1.0, "named": true})
	var pos := _s({"companions": wolves}, "urrokai")
	assert_float(pos["company"]).is_equal_approx(0.25, 0.0001)
	assert_float(pos["value"]).is_less(0.6)     # a monster court cannot buy a noble


func test_cultures_read_the_same_orc_differently() -> void:
	var sub := {"title_rank": 2, "wealth": 0.5, "companions": [_orc()]}
	var church: Dictionary = _s(sub, "solenne")
	var secular: Dictionary = _s(sub, "caldric")
	var frontier: Dictionary = _s(sub, "frontier")
	assert_float(church["value"]).is_less(secular["value"])
	assert_float(frontier["value"]).is_greater(secular["value"])
	assert_float(church["company"]).is_less(0.0)
	assert_float(frontier["company"]).is_greater(0.0)
	# A church seal flips the attitude one step; a guild sponsor helps in the secular culture.
	var sealed := sub.duplicate(true)
	sealed["church_seal"] = true
	assert_float(_s(sealed, "solenne")["value"]).is_greater(church["value"])
	var gob := {"companions": [{"species": "goblin", "kind": "monster", "speech": 2, "civility": 0.7, "named": true}]}
	var sponsored := gob.duplicate(true)
	sponsored["guild_sponsored"] = true
	assert_float(_s(sponsored, "caldric")["value"]).is_greater(_s(gob, "caldric")["value"])


func test_named_monsters_cost_faith_standing_in_church_lands_only() -> void:
	var sub := {"companions": [_orc(), _orc()], "faith_standing": 0.0}
	assert_float(_s(sub, "solenne")["parts"]["faith"]).is_less(0.5)
	assert_float(_s(sub, "caldric")["parts"]["faith"]).is_equal_approx(0.5, 0.0001)


func test_title_honour_follows_legitimacy() -> void:
	var lord := {"title_rank": 5, "origin": "caldrenn"}
	var home: Dictionary = Status.of(lord, {"culture": "caldric", "kingdom": "caldrenn"})
	var east: Dictionary = Status.of(lord, {"culture": "solenne", "kingdom": "solmarch"})
	assert_float(home["parts"]["title"]).is_equal(1.0)
	assert_float(east["parts"]["title"]).is_equal(0.0)
	assert_str(home["lines"][0]).contains("in ")


func test_bands_and_monster_town_penalty() -> void:
	assert_str(Status.band_of(0.1)).is_equal("outcast")
	assert_str(Status.band_of(0.3)).is_equal("low")
	assert_str(Status.band_of(0.5)).is_equal("common")
	assert_str(Status.band_of(0.7)).is_equal("respected")
	assert_str(Status.band_of(0.85)).is_equal("noble")
	assert_str(Status.band_of(0.99)).is_equal("exalted")
	var plain: Dictionary = _s({"title_rank": 3, "wealth": 0.6}, "monster_town")
	var folk: Dictionary = _s({"title_rank": 3, "wealth": 0.6}, "folk")
	assert_float(plain["value"]).is_less(folk["value"])


func _town(culture: String, extra := {}) -> Dictionary:
	var t := {"sid": 7, "name": "Testhaven", "culture": culture, "corruption": 0.5}
	t.merge(extra, true)
	return t


func test_dawn_throne_turns_back_a_low_status_orc_and_offers_options() -> void:
	var r: Dictionary = Gate.check([_orc()], _town("solenne"), 0.45, {"hour": 12, "day": 3, "seed": 5})
	assert_str(r["verdict"]).is_equal("turn_back")
	assert_float(r["required"]).is_greater_equal(0.6)
	var ids: Array = (r["options"] as Array).map(func(o: Dictionary) -> String: return o["id"])
	for id in ["leave_outside", "bribe", "sponsor", "permit", "cleansing", "talk"]:
		assert_bool(id in ids).is_true()
	assert_bool("disguise" in ids).is_false()           # Form 2 cannot pass as a servant
	assert_int(r["bribe_price"]).is_greater(0)
	var ok: Dictionary = Gate.check([_orc()], _town("solenne"), 0.8, {"hour": 12, "day": 3, "seed": 5})
	assert_str(ok["verdict"]).is_equal("admit_with_terms")
	var sealed: Dictionary = Gate.check([_orc()], _town("solenne"), 0.2, {"hour": 12, "day": 3, "seed": 5, "permits": [{"kind": "church_seal", "heads": 3, "expires": 99}]})
	assert_str(sealed["verdict"]).is_equal("admit_with_terms")
	assert_bool("seal_inspected" in sealed["terms"]).is_true()


func test_registry_admits_with_a_fee_and_a_collar() -> void:
	var gob := {"species": "goblin", "kind": "monster", "speech": 2, "civility": 0.7, "named": true, "power": 1, "form": 1}
	var r: Dictionary = Gate.check([gob], _town("caldric"), 0.35, {"hour": 12, "day": 1, "seed": 1})
	assert_str(r["verdict"]).is_equal("admit_with_terms")
	assert_int(r["fee"]).is_equal(3)
	assert_bool("collar_tag" in r["terms"]).is_true()
	var alone: Dictionary = Gate.check([{"species": "human", "kind": "human"}], _town("caldric"), 0.1, {})
	assert_str(alone["verdict"]).is_equal("admit")
	var wolf := {"species": "wolf", "kind": "beast", "speech": 1, "civility": 0.5, "named": true, "power": 1}
	var rw: Dictionary = Gate.check([wolf], _town("caldric"), 0.4, {"hour": 12})
	assert_bool("muzzle" in rw["terms"]).is_true()


func test_open_ban_quarantine_escort_reserve_laws() -> void:
	var ctx := {"hour": 12, "day": 1, "seed": 2}
	assert_str(Gate.check([_orc()], _town("urrokai"), 0.3, ctx)["verdict"]).is_equal("admit")
	var ban: Dictionary = Gate.check([_orc()], _town("solenne", {"kingdom": "varska_marches"}), 0.95, ctx)
	assert_str(ban["verdict"]).is_equal("bar")
	assert_str(ban["law"]).is_equal("ban")
	var ban_ids: Array = (ban["options"] as Array).map(func(o: Dictionary) -> String: return o["id"])
	assert_bool("sponsor" in ban_ids).is_false()
	assert_bool("bribe" in ban_ids).is_true()
	var q: Dictionary = Gate.check([_orc()], _town("caldric", {"quarantine": true}), 0.9, ctx)
	assert_str(q["verdict"]).is_equal("turn_back")
	var esc: Dictionary = Gate.check([_orc()], _town("frontier"), 0.3, ctx)
	assert_str(esc["verdict"]).is_equal("turn_back")
	assert_str(Gate.check([_orc()], _town("frontier"), 0.6, ctx)["verdict"]).is_equal("admit_with_terms")
	var res: Dictionary = Gate.check([_orc()], _town("monster_town"), 0.5, ctx)
	assert_bool("monster_quarter_only" in res["terms"]).is_true()
	var dead := {"species": "undead", "kind": "undead", "named": false, "power": 1}
	assert_str(Gate.check([dead], _town("urrokai"), 1.0, ctx)["verdict"]).is_equal("bar")


func test_strict_curfew_bars_monsters_after_dusk_even_with_permits() -> void:
	var permits := [{"kind": "church_seal", "heads": 3, "expires": 99}]
	var day: Dictionary = Gate.check([_orc()], _town("solenne"), 0.9, {"hour": 12, "permits": permits})
	var night: Dictionary = Gate.check([_orc()], _town("solenne"), 0.9, {"hour": 22, "permits": permits})
	assert_str(day["verdict"]).is_equal("admit_with_terms")
	assert_str(night["verdict"]).is_equal("bar")
	assert_str(" ".join(night["reasons"])).contains("bell")
	assert_str(Gate.check([_orc()], _town("caldric"), 0.9, {"hour": 22})["verdict"]).is_not_equal("bar")


func test_bribe_price_scales_with_corruption() -> void:
	var lo := Gate.bribe_price([_orc()], _town("solenne", {"corruption": 0.1}))
	var hi := Gate.bribe_price([_orc()], _town("solenne", {"corruption": 0.9}))
	assert_int(hi).is_greater(lo)
	var big := Gate.bribe_price([_orc(), _orc({"power": 8})], _town("solenne", {"corruption": 0.5}))
	assert_int(big).is_greater(Gate.bribe_price([_orc()], _town("solenne", {"corruption": 0.5})))
	var r: Dictionary = Gate.apply_option([_orc()], _town("solenne", {"corruption": 0.9}), "bribe", 0.3, {"hour": 12, "day": 4, "seed": 1})
	assert_bool(r["ok"]).is_true()
	assert_int(r["gold"]).is_equal(-hi)
	assert_float(r["infamy_delta"]).is_greater(0.0)


func test_forged_permit_sometimes_fails_with_arrest() -> void:
	var arrests := 0
	var passes := 0
	for d in 40:
		var r: Dictionary = Gate.apply_option([_orc()], _town("solenne"), "permit", 0.3,
			{"hour": 12, "day": d, "seed": 3, "permits": [{"kind": "church_seal", "forged": true, "heads": 3, "expires": 999}]})
		if bool(r["arrest"]):
			arrests += 1
		elif bool(r["ok"]):
			passes += 1
	assert_int(arrests).is_greater(5)
	assert_int(passes).is_greater(5)
	var honest: Dictionary = Gate.apply_option([_orc()], _town("solenne"), "permit", 0.3,
		{"hour": 12, "day": 2, "seed": 3, "permits": [{"kind": "noble_letter", "heads": 3, "expires": 999}]})
	assert_bool(honest["ok"]).is_true()
	assert_bool(honest["arrest"]).is_false()
	var none: Dictionary = Gate.apply_option([_orc()], _town("solenne"), "permit", 0.3, {"hour": 12, "day": 2, "seed": 3})
	assert_bool(none["ok"]).is_false()


func test_disguise_needs_form_three_and_a_dull_guard() -> void:
	var lizard := _orc({"species": "lizardfolk", "form": 3, "speech": 4})
	var ids: Array = (Gate.check([lizard], _town("solenne"), 0.3, {"hour": 12})["options"] as Array).map(func(o: Dictionary) -> String: return o["id"])
	assert_bool("disguise" in ids).is_true()
	var good := 0
	var bad := 0
	for d in 30:
		var a: Dictionary = Gate.apply_option([lizard], _town("solenne"), "disguise", 0.3, {"hour": 12, "day": d, "seed": 4, "quality": 1.0, "guard": {"perception": 0.1}})
		var b: Dictionary = Gate.apply_option([lizard], _town("solenne"), "disguise", 0.3, {"hour": 12, "day": d, "seed": 4, "quality": 0.1, "guard": {"perception": 1.0}})
		good += 1 if bool(a["ok"]) else 0
		bad += 1 if bool(b["arrest"]) else 0
	assert_int(good).is_equal(30)
	assert_int(bad).is_between(6, 28)


func test_talk_sponsor_and_leave_options() -> void:
	var lizard := _orc({"species": "lizardfolk", "form": 3, "speech": 4})
	assert_float(Gate.talk_chance(4)).is_equal_approx(0.55, 0.0001)
	var wins := 0
	for d in 60:
		if bool(Gate.apply_option([lizard], _town("solenne"), "talk", 0.3, {"hour": 12, "day": d, "seed": 9})["ok"]):
			wins += 1
	assert_int(wins).is_between(15, 50)
	var dumb: Dictionary = Gate.apply_option([_orc({"speech": 1})], _town("solenne"), "talk", 0.3, {"hour": 12, "day": 1, "seed": 9})
	assert_bool(dumb["ok"]).is_false()
	assert_bool(Gate.apply_option([_orc()], _town("solenne"), "sponsor", 0.3, {"hour": 12, "sponsor_status": 0.7})["ok"]).is_true()
	assert_str(Gate.apply_option([_orc()], _town("solenne"), "sponsor", 0.3, {"hour": 12, "sponsor_status": 0.2})["result"]).is_equal("sponsor_too_low")
	var lv: Dictionary = Gate.apply_option([_orc()], _town("solenne"), "leave_outside", 0.3, {"hour": 12})
	assert_int(lv["loyalty_delta"]).is_equal(-1)
	var cl: Dictionary = Gate.apply_option([_orc()], _town("solenne"), "cleansing", 0.3, {"hour": 12})
	assert_bool(cl["ok"]).is_true()
	assert_int(cl["gold"]).is_equal(-9)
	assert_bool(Gate.apply_option([_orc()], _town("caldric"), "cleansing", 0.1, {"hour": 12})["ok"]).is_false()


func test_forecast_reads_in_plain_words() -> void:
	var wolf := {"species": "wolf", "kind": "beast", "speech": 1, "civility": 0.5, "named": true, "power": 1}
	var towns := [_town("caldric", {"sid": 1, "name": "Wolfhaven"}), _town("solenne", {"sid": 2, "name": "Caldrenn"})]
	var f: Array = Gate.forecast([wolf], towns, {1: 0.4, 2: 0.2}, {"hour": 12})
	assert_str(f[0]["line"]).contains("Wolfhaven would admit you")
	assert_str(f[0]["line"]).contains("muzzle")
	assert_str(f[1]["line"]).contains("Caldrenn would turn you away")
	assert_str(f[1]["verdict"]).is_equal("turn_back")


func test_gate_is_deterministic() -> void:
	var ctx := {"hour": 12, "day": 9, "seed": 11}
	var a: Dictionary = Gate.apply_option([_orc()], _town("solenne"), "bribe", 0.3, ctx)
	var b: Dictionary = Gate.apply_option([_orc()], _town("solenne"), "bribe", 0.3, ctx)
	assert_dict(a).is_equal(b)


func test_society_glue_uses_hub_and_logs() -> void:
	var hub = Hub.new()
	var ms: Object = hub.mod("monster_society")
	var mb: Object = hub.mod("monster_bonds")
	var party: Array = [_orc()]
	var town := _town("solenne")
	var r: Dictionary = ms.gate("player", party, town, 12, 3)
	assert_str(r["verdict"]).is_equal("turn_back")
	assert_str(r["status_band"]).is_not_empty()
	ms.issue_permit("player", "church_seal", "bishop", ["orc"], 3, 30, false, 3)
	assert_str(ms.gate("player", party, town, 12, 4)["verdict"]).is_equal("admit_with_terms")
	assert_int(ms.permits_of("player", 4).size()).is_equal(1)
	assert_int(ms.permits_of("player", 40).size()).is_equal(0)
	var b: Dictionary = ms.take_option("player", party, town, "bribe", 12, 5, {})
	assert_bool(b["ok"]).is_true()
	assert_int(ms.bribes_of("player").size()).is_equal(1)
	assert_float(ms.infamy_of("player", 7)).is_greater(0.0)
	assert_object(mb).is_not_null()
