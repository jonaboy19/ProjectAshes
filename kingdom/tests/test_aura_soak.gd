extends GdUnitTestSuite
## AR-16 soak: two simulated years of the player doing big deeds and releasing in rotating towns. Invariants: event rings and legends stay capped,
## dread/awe stay in range, the price premium and refusal rules hold (every town keeps a fallback shop), flights are bounded and people return,
## the save stays small, the day tick stays cheap, and the whole run is deterministic.

const Hub := preload("res://scripts/realm/realm_hub.gd")
const CTX := {"season": "summer", "at_war": false, "abs_hours": 0, "gold": 500, "life": null}
const ME := "i:player"
const DAYS := 730
const DEEDS := ["siege_broken", "street_slaughter", "landmark_destroyed", "noble_assassinated", "monster_defeated", "bandit_camp_cleared", "spared_enemy", "survived_execution"]
const DAY_MODS := ["settlements", "camps", "civilization", "migration", "districts", "news", "aura_fallout"]

var worst_day_usec := 0
var total_usec := 0


func _run() -> Dictionary:
	WorldGen.setup(2024)
	WorldSim.day = 1
	var hub: RefCounted = Hub.new()
	hub.mod("organizations").auto_seed = false
	hub.mod("civilization")._ensure()
	hub.mod("migration")._ensure()
	hub.mod("districts")._ensure()
	var fo: RefCounted = hub.mod("aura_fallout")
	var towns := mini(WorldGen.settlements.size(), 12)
	var max_ring := 0
	var max_keys := 0
	var max_price := 1.0
	var max_dread := 0.0
	var max_away := 0
	var refusal_without_fallback := 0
	worst_day_usec = 0
	total_usec = 0
	for day in range(2, DAYS + 2):
		WorldSim.day = day
		if day % 17 == 0:
			var sid := (day / 17) % towns
			var deed: String = DEEDS[(day / 17) % DEEDS.size()]
			fo.on_deed(ME, deed, sid, 1.0 + float((day / 17) % 3) * 0.3)
			if (day / 17) % 3 == 0:
				fo.on_incident(ME, sid, "", 0.9, 0.5, 20, {"t3": 5, "t4": 3, "damage_gold": 40, "duration_s": 12.0,
					"witness_ids": ["ch:%d" % (500 + day % 40), "ch:%d" % (540 + day % 40)]})
			if (day / 17) % 5 == 0:
				fo.pay_bill(ME, sid)
		for k: String in DAY_MODS:
			var t := Time.get_ticks_usec()
			hub.mod(k).tick_day(day, CTX)
			if k == "aura_fallout":
				var dt := Time.get_ticks_usec() - t
				total_usec += dt
				worst_day_usec = maxi(worst_day_usec, dt)
		if day % 10 == 0:
			var s: Dictionary = fo.serialize()
			max_ring = maxi(max_ring, (s["inc"] as Array).size())
			max_keys = maxi(max_keys, (s["ax"] as Dictionary).size())
			var away_n := 0
			for sid2 in towns:
				max_price = maxf(max_price, fo.price_mult(sid2))
				max_dread = maxf(max_dread, fo.dread_felt(ME, sid2))
				away_n += fo.away(sid2)
				if fo.vendor_refuses(sid2) and not fo.fallback_shop(sid2):
					refusal_without_fallback += 1
				assert_bool(fo.fallback_shop(sid2)).is_true()
				assert_bool(not fo.vendor_refuses(sid2, {"fence": true})).is_true()
				assert_float(fo.dread(ME, sid2)).is_between(0.0, 100.0)
				assert_float(fo.awe(ME, sid2)).is_between(0.0, 100.0)
			max_away = maxi(max_away, away_n)
	var blob := JSON.stringify(fo.serialize())
	return {"hash": hash(blob), "bytes": blob.length(), "ring": max_ring, "keys": max_keys, "price": max_price, "dread": max_dread, "away": max_away,
		"legends": fo.legends().size(), "stats": fo.stats.duplicate(), "refusal_bad": refusal_without_fallback,
		"news": JSON.stringify(hub.mod("news").serialize()).length()}


func test_two_years_stay_bounded() -> void:
	var r := _run()
	assert_int(int(r["ring"])).is_less_equal(64)
	assert_int(int(r["legends"])).is_less_equal(20)
	assert_int(int(r["keys"])).is_less_equal(160)
	assert_float(float(r["price"])).is_less_equal(1.4001)
	assert_int(int(r["refusal_bad"])).is_equal(0)
	assert_int(int(r["bytes"])).is_less(6144)                           # design target: under 6 KB
	assert_int(int(r["news"])).is_less(200000)
	assert_int(int((r["stats"] as Dictionary)["incidents"])).is_greater(10)
	assert_int(int((r["stats"] as Dictionary)["witnessed"])).is_less_equal(int((r["stats"] as Dictionary)["incidents"]) * 12)
	assert_int(int(r["away"])).is_less_equal(12 * 40)                   # at most 40 per town in flight
	assert_float(float(r["dread"])).is_less_equal(100.0)
	assert_int(int((r["stats"] as Dictionary)["fled"])).is_greater(0)
	assert_int(int((r["stats"] as Dictionary)["scouted"])).is_greater(0)
	assert_int(int((r["stats"] as Dictionary)["fled"])).is_greater_equal(int((r["stats"] as Dictionary)["returned"]))


func test_per_day_cost_and_determinism() -> void:
	var a := _run()
	var avg := float(total_usec) / float(DAYS)
	assert_float(avg).is_less(1500.0)                                    # design 0.1 ms; loose for slow CI
	assert_int(worst_day_usec).is_less(40000)
	var b := _run()
	assert_int(int(a["hash"])).is_equal(int(b["hash"]))
	assert_int(int(a["bytes"])).is_equal(int(b["bytes"]))
