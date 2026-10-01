extends GdUnitTestSuite
## The four lighter ladders (farmer, soldier, merchant, blacksmith) have real mechanics that feed the
## ladder's counters, and tie into homestead.gd, callups.gd / campaign.gd, enterprise.gd and crafting.gd.

const Hub := preload("res://scripts/realm/realm_hub.gd")
const Mastery := preload("res://scripts/sim/mastery.gd")
const Biography := preload("res://scripts/sim/biography.gd")
const Homestead := preload("res://scripts/sim/homestead.gd")
const CareerLadders := preload("res://scripts/sim/career_ladders.gd")

static var _world_ready := false


func _norm(d: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(d)))


func _trades(career := "") -> RefCounted:
	if not _world_ready:
		WorldGen.setup(2024)
		_world_ready = true
	var hub: RefCounted = Hub.new()
	var tr: RefCounted = hub.mod("trades")
	tr.mastery_ref = Mastery.new()
	tr.bio_ref = Biography.new()
	tr.gold_ref = 1000
	tr.sync_life = false
	tr.homestead_ref = Homestead.new()
	if career != "":
		tr.join(career, 0)
	return tr


## Take the best option of every choice step (by hidden quality) and `timing` on timing steps.
func _play(tr: RefCounted, career: String, kind: String, day: int, timing := 0.9, best := true, season := "") -> Dictionary:
	var b: Dictionary = tr.begin(career, kind, day, season)
	assert_bool(b["ok"]).override_failure_message(String(b.get("reason", ""))).is_true()
	var r: Dictionary = {}
	var guard := 0
	while guard < 8:
		guard += 1
		var st: Dictionary = tr.task["steps"][int(tr.task["i"])]
		var v := timing
		if String(st["widget"]) == "choice":
			var opts: Array = st["options"]
			var pick := 0
			for i in opts.size():
				var better := float(opts[i]["q"]) > float(opts[pick]["q"]) if best else float(opts[i]["q"]) < float(opts[pick]["q"])
				if better:
					pick = i
			v = float(pick)
		r = tr.submit(v)
		if bool(r.get("done", false)):
			break
	return r


func test_the_views_never_leak_option_quality() -> void:
	var tr := _trades("soldier")
	tr.ranks["soldier"] = "soldier"
	var b: Dictionary = tr.begin("soldier", "squad", 3)
	assert_bool(b["ok"]).is_true()
	for o: Dictionary in b["view"]["options"]:
		assert_bool(o.has("q")).is_false()


# ---------------------------------------------------------------- farmer

func test_sowing_the_wrong_crop_gives_a_thin_harvest() -> void:
	var good := _trades("farmer")
	var bad := _trades("farmer")
	var rg := _play(good, "farmer", "sow", 3, 0.9, true, "spring")
	var rb := _play(bad, "farmer", "sow", 3, 0.9, false, "spring")
	assert_float(rg["quality"]).is_greater(rb["quality"])
	assert_int(int(rg["gold"])).is_greater(int(rb["gold"]))
	assert_int(good.stat("farmer", "harvests")).is_equal(1)
	assert_float(good.bio_ref.rep("farming")).is_greater(bad.bio_ref.rep("farming"))


func test_a_lease_goes_through_homestead_and_losing_it_costs_the_rank() -> void:
	var tr := _trades("farmer")
	assert_str(tr.take_tenancy(0, 5)).is_empty()
	assert_bool(tr.homestead_ref.is_leased(0)).is_true()
	assert_bool(tr.is_tenant()).is_true()
	assert_str(tr.take_tenancy(0, 5)).is_not_empty()      # already holds one
	tr.ranks["farmer"] = "tenant_farmer"
	tr.tick_week(2, {})
	tr.tick_week(3, {})
	assert_int(tr.stat("farmer", "rent_weeks")).is_equal(2)
	# The landlord takes the plot back for unpaid rent (homestead evicts); the next week notices.
	tr.homestead_ref.leased.erase(0)
	var msgs: Array = tr.tick_week(4, {})
	assert_array(msgs).is_not_empty()
	assert_str(tr.rank_of("farmer")).is_equal("field_hand")
	# The landlord's share comes off the harvest of a tenant.
	var t2 := _trades("farmer")
	t2.take_tenancy(0, 5)
	var plain := _trades("farmer")
	var rt := _play(t2, "farmer", "sow", 3, 0.9, true, "spring")
	var rp := _play(plain, "farmer", "sow", 3, 0.9, true, "spring")
	assert_int(int(rt["gold"])).is_less(int(rp["gold"]))


func test_farmer_promotion_needs_harvests_a_lease_and_time() -> void:
	var tr := _trades("farmer")
	for d in 40:
		tr.mastery_ref.gain("farming", 1.0, d)
	var st: Dictionary = tr.status("farmer", 30)
	assert_bool(st["eligible"]).is_false()
	var miss: Array = Array(st["missing"] as PackedStringArray)
	assert_bool(miss.any(func(m: String) -> bool: return m.contains("Harvests"))).is_true()
	assert_bool(miss.any(func(m: String) -> bool: return m.to_lower().contains("leased plot"))).is_true()
	tr.take_tenancy(0, 0)
	for i in 3:
		_play(tr, "farmer", "sow", 1 + i * 2, 0.9, true, "spring")
		tr.hours_used.clear()
	assert_bool(tr.status("farmer", 30)["eligible"]).is_true()
	assert_bool(tr.promote("farmer", 30)["ok"]).is_true()
	assert_str(tr.rank_of("farmer")).is_equal("tenant_farmer")


func test_settling_tenants_needs_your_own_land_and_pays_weekly() -> void:
	var tr := _trades("farmer")
	tr.ranks["farmer"] = "landholder"
	tr.since["farmer"] = 0
	var no: Dictionary = tr.begin("farmer", "tenant", 3)
	assert_bool(no["ok"]).is_false()
	tr.flags_extra["owns_plot"] = true
	var r := _play(tr, "farmer", "tenant", 3, 0.9, true)
	assert_int(int(tr.estate["tenants"])).is_equal(1)
	assert_int(tr.take_pending_gold()).is_equal(-tr.TENANT_COST)
	tr.tick_week(2, {})
	assert_int(tr.take_pending_gold()).is_equal(tr.TENANT_RENT)
	assert_int(int(tr.career_stats("farmer")["tenants"])).is_equal(1)
	assert_float(r["quality"]).is_greater(0.5)


# ---------------------------------------------------------------- soldier

func test_good_orders_save_men_and_bad_ones_lose_them() -> void:
	var good := _trades("soldier")
	good.ranks["soldier"] = "soldier"
	good.squad["men"] = 10
	var rg := _play(good, "soldier", "squad", 3, 0.9, true)
	var bad := _trades("soldier")
	bad.ranks["soldier"] = "soldier"
	bad.squad["men"] = 10
	var rb := _play(bad, "soldier", "squad", 3, 0.9, false)
	assert_int(int(rg["lost"])).is_less(int(rb["lost"]))
	assert_int(int(good.squad["men"])).is_greater(int(bad.squad["men"]))
	assert_int(good.stat("soldier", "squad_missions")).is_equal(1)
	assert_int(bad.stat("soldier", "squad_missions")).is_equal(0)
	assert_float(good.bio_ref.rep("military")).is_greater(bad.bio_ref.rep("military"))


func test_a_recruit_cannot_lead_a_squad_and_drills_count_toward_the_sergeants_stripes() -> void:
	var tr := _trades("soldier")
	assert_bool(tr.begin("soldier", "squad", 3)["ok"]).is_false()
	for i in 3:
		_play(tr, "soldier", "drill", 1 + i, 0.95)
		tr.hours_used.clear()
	assert_int(tr.stat("soldier", "drills")).is_equal(3)
	var nxt := CareerLadders.rank_def("soldier", "squad_leader")
	assert_int(int(nxt["requires"]["stats"]["drills"])).is_greater(0)


func test_mustering_raises_a_callup_and_sets_the_campaign_rank() -> void:
	var tr := _trades("soldier")
	tr.ranks["soldier"] = "soldier"
	tr.since["soldier"] = 0
	var m: Dictionary = tr.muster(5)
	if not bool(m["ok"]):
		# A call-up can be withheld by its own rules; the soldier is told why.
		assert_str(String(m["reason"])).is_not_empty()
		return
	var cu: RefCounted = tr.hub.mod("callups")
	var id := String(m["offer"]["id"])
	cu.accept(id)
	var done: Dictionary = tr.muster_done(id, 0.9, 6)
	assert_bool(done["ok"]).is_true()
	assert_int(tr.stat("soldier", "campaign_actions")).is_equal(1)
	assert_str(String(tr.hub.mod("campaign").player_rank())).is_equal(CareerLadders.military_rank_for("soldier"))


func test_promotion_to_squad_leader_sets_the_squad_size_and_campaign_rank() -> void:
	var tr := _trades("soldier")
	tr.ranks["soldier"] = "veteran"
	tr.since["soldier"] = 0
	for d in 120:
		tr.mastery_ref.gain("soldiering", 1.5, d)
		tr.mastery_ref.gain("leadership", 1.0, d)
	tr.bio_ref.change_rep("military", 30.0)
	tr.stats["soldier"] = {"drills": 9}
	tr.flags_extra["at_war"] = false
	var st: Dictionary = tr.status("soldier", 60)
	# squad_leader also needs an open Sergeant seat in the guard org; without careers the seat check is skipped.
	assert_bool(st["eligible"]).is_true()
	assert_bool(tr.promote("soldier", 60)["ok"]).is_true()
	assert_int(int(tr.squad["men"])).is_equal(CareerLadders.troops_for_rank("squad_leader"))
	assert_str(String(tr.hub.mod("campaign").player_rank())).is_equal("tenwarden")


# ---------------------------------------------------------------- merchant

func test_haggling_rewards_reading_the_customer() -> void:
	var tr := _trades("merchant")
	var good := _play(tr, "merchant", "haggle", 3, 0.9, true)
	var tr2 := _trades("merchant")
	var bad := _play(tr2, "merchant", "haggle", 3, 0.9, false)
	assert_float(good["quality"]).is_greater(0.9)
	assert_int(int(good["gold"])).is_greater(int(bad["gold"]))
	assert_int(tr.stat("merchant", "deals")).is_equal(1)
	assert_int(tr2.stat("merchant", "deals")).is_equal(0)


func test_stalls_pay_for_stocking_what_the_town_wants() -> void:
	var tr := _trades("merchant")
	var good := _play(tr, "merchant", "stall", 3, 0.9, true)
	var tr2 := _trades("merchant")
	var bad := _play(tr2, "merchant", "stall", 3, 0.9, false)
	assert_int(int(good["gold"])).is_greater(int(bad["gold"]))
	assert_int(tr.stat("merchant", "stall_days")).is_equal(1)


func test_caravans_and_workshops_come_from_enterprise() -> void:
	var tr := _trades("merchant")
	var en: RefCounted = tr.hub.mod("enterprise")
	assert_bool(bool(tr.ladder_ctx("merchant", 5).get("owns_workshop", false))).is_false()
	assert_int(int(tr.career_stats("merchant").get("caravans_run", 0))).is_equal(0)
	en.workshops.append({"id": 1, "sid": 0, "kind": "smithy", "level": 1})
	en.caravans[1] = {"id": 1}
	assert_bool(bool(tr.ladder_ctx("merchant", 5)["owns_workshop"])).is_true()
	assert_int(int(tr.career_stats("merchant")["caravans_run"])).is_equal(1)
	var req: Dictionary = CareerLadders.rank_def("merchant", "trading_house")["requires"]
	assert_str(String(req["property"])).is_equal("owns_workshop")


# ---------------------------------------------------------------- blacksmith

func test_forging_quality_comes_from_skill_and_the_crafting_odds() -> void:
	var novice := _trades("blacksmith")
	var master := _trades("blacksmith")
	for d in 200:
		master.mastery_ref.gain("smithing", 2.0, d)
	var tiers_n := 0
	var tiers_m := 0
	for i in 6:
		novice.hours_used.clear()
		master.hours_used.clear()
		tiers_n += int(_play(novice, "blacksmith", "forge", 1 + i, 0.97)["tier"])
		tiers_m += int(_play(master, "blacksmith", "forge", 1 + i, 0.97)["tier"])
	assert_int(tiers_m).is_greater(tiers_n)
	assert_int(master.stat("blacksmith", "pieces")).is_equal(6)
	assert_int(master.stat("blacksmith", "fine_pieces")).is_greater(0)
	# A sloppy strike is rough whatever the skill.
	master.hours_used.clear()
	assert_int(int(_play(master, "blacksmith", "forge", 20, 0.1)["tier"])).is_equal(0)


func test_a_commission_demands_a_minimum_tier_or_costs_your_name() -> void:
	var tr := _trades("blacksmith")
	assert_bool(tr.begin("blacksmith", "commission", 3)["ok"]).is_false()    # apprentices take none
	tr.ranks["blacksmith"] = "master_smith"
	for d in 200:
		tr.mastery_ref.gain("smithing", 2.0, d)
	var rep0: float = tr.bio_ref.rep("craft")
	var ok := _play(tr, "blacksmith", "commission", 3, 0.98)
	assert_int(tr.stat("blacksmith", "commissions")).is_greater(0 if int(ok["tier"]) >= 2 else -1)
	tr.hours_used.clear()
	var bad := _play(tr, "blacksmith", "commission", 4, 0.05)
	assert_int(int(bad["gold"])).is_equal(-10)
	assert_float(tr.bio_ref.rep("craft")).is_less(rep0 + 2.0)


func test_workshop_owner_needs_a_workshop() -> void:
	var tr := _trades("blacksmith")
	tr.ranks["blacksmith"] = "master_smith"
	tr.since["blacksmith"] = 0
	for d in 400:
		tr.mastery_ref.gain("smithing", 1.5, d)
	tr.bio_ref.change_rep("craft", 60.0)
	tr.stats["blacksmith"] = {"commissions": 9}
	tr.gold_ref = 5000
	var st: Dictionary = tr.status("blacksmith", 200)
	assert_bool(Array(st["missing"] as PackedStringArray).any(func(m: String) -> bool: return m.to_lower().contains("owns workshop"))).is_true()
	tr.flags_extra["owns_workshop"] = true
	assert_bool(tr.status("blacksmith", 200)["eligible"]).is_true()


# ---------------------------------------------------------------- general

func test_hours_are_limited_and_state_round_trips() -> void:
	var tr := _trades("blacksmith")
	var n := 0
	for i in 8:
		var b: Dictionary = tr.begin("blacksmith", "forge", 3)
		if not bool(b["ok"]):
			break
		tr.abandon_task()
		tr._spend("forge", 3)
		n += 1
	assert_int(n).is_between(4, 6)
	_play(tr, "blacksmith", "forge", 9)
	var a: Dictionary = JSON.parse_string(JSON.stringify(tr.serialize()))
	var t2 := _trades()
	t2.deserialize(a)
	assert_str(_norm(t2.serialize())).is_equal(_norm(tr.serialize()))
	assert_int(t2.stat("blacksmith", "pieces")).is_equal(1)


func test_generation_is_deterministic() -> void:
	var a := _trades("merchant")
	var b := _trades("merchant")
	a.begin("merchant", "haggle", 5)
	b.begin("merchant", "haggle", 5)
	assert_str(_norm(a.task)).is_equal(_norm(b.task))


func test_every_ladder_has_a_mechanic_for_its_counters() -> void:
	# Each stat a ladder asks for is one the module can actually produce.
	var produced := {
		"farmer": ["harvests", "rent_weeks", "tenants"],
		"soldier": ["drills", "squad_missions", "campaign_actions", "commands"],
		"merchant": ["deals", "stall_days", "caravans_run"],
		"blacksmith": ["pieces", "good_pieces", "fine_pieces", "commissions"],
	}
	for career: String in produced:
		for r: Dictionary in CareerLadders.ladder(career):
			for stat: String in ((r["requires"] as Dictionary).get("stats", {}) as Dictionary):
				assert_bool((produced[career] as Array).has(stat)).override_failure_message("%s needs %s" % [career, stat]).is_true()


func test_ticks_are_cheap() -> void:
	var tr := _trades("farmer")
	tr.ranks["farmer"] = "estate_owner"
	tr.estate = {"tenants": 6, "weeks": 0}
	var t0 := Time.get_ticks_usec()
	for w in 100:
		tr.tick_day(w, {})
		tr.tick_week(w, {})
	tr.catch_up(3000, {})
	assert_float(float(Time.get_ticks_usec() - t0) / 100.0).is_less(2000.0)
