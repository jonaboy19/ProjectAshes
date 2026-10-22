extends GdUnitTestSuite
## Gap closure: real kingdom_of, weather into armies, theft into presence, monster departures/rent/quarter, aura awe/dread, gossip size.

const Hub := preload("res://scripts/realm/realm_hub.gd")
const PD := preload("res://scripts/realm/politics_data.gd")
const Armies := preload("res://scripts/realm/armies.gd")
const SP := preload("res://scripts/realm/social_perception.gd")
const Presence := preload("res://scripts/population/presence.gd")
const PresenceLive := preload("res://scripts/population/presence_live.gd")
const Theft := preload("res://scripts/sim/theft.gd")

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


func test_kingdom_of_resolves_by_position_and_settlement() -> void:
	_hub()
	assert_str(PD.kingdom_of(0)).is_equal("caldrenn")
	assert_str(PD.kingdom_of(99999)).is_equal("caldrenn")
	assert_str(PD.kingdom_of(Vector2(100, 100))).is_equal("caldrenn")
	assert_str(PD.kingdom_of(Vector2(0, -7000))).is_equal("frostcrown_holds")
	assert_str(PD.kingdom_of(Vector2(0, 7000))).is_equal("solkar_dominion")
	assert_str(PD.kingdom_of(Vector2(-7000, 500))).is_equal("veylwood")
	assert_str(PD.kingdom_of(Vector2(7000, 500))).is_equal("solmarch")
	# A settlement placed abroad (or tagged) lies in that kingdom, and the church-court path follows it.
	WorldGen.settlements[0]["kingdom"] = "solmarch"
	assert_str(PD.kingdom_of(0)).is_equal("solmarch")
	WorldGen.settlements[0].erase("kingdom")
	WorldGen.settlements[0]["pos"] = Vector2(7000, 0)
	var k := PD.kingdom_of(0)
	WorldGen.settlements[0]["pos"] = Vector2.ZERO
	assert_str(k).is_equal("solmarch")


func test_weather_maps_and_feeds_armies() -> void:
	assert_str(Armies.field_weather("overcast")).is_equal("clear")
	assert_str(Armies.field_weather("storm")).is_equal("storm")
	assert_str(Armies.field_weather("snow")).is_equal("snow")
	var seen := {}
	for d in 400:
		seen[Armies.season_weather("winter", d)] = true
	assert_bool(seen.has("snow")).is_true()
	assert_bool(Armies.season_weather("summer", 5) in Armies.WEATHER_FIELD).is_true()
	var h := _hub()
	var ar: RefCounted = h.mod("armies")
	ar.tick_hour(1, {"weather": "storm"})
	assert_str(ar.weather).is_equal("storm")
	var cx: Dictionary = Life._realm_ctx()
	assert_bool(Armies.WEATHER_FIELD.has(String(cx["weather"]))).is_true()


func test_theft_reports_to_presence() -> void:
	var pl := PresenceLive.new()
	var before := pl.presence.ticks
	var r := Theft.steal(null, "ch:owner", "bread", 1, "ground", Vector2.ZERO, -1)
	assert_bool(r.has("presence")).is_equal(bool(r["theft"]))
	assert_int(before).is_equal(pl.presence.ticks)
	PresenceLive.current = null
	var r2 := Theft.steal(null, "ch:owner", "bread", 1, "ground", Vector2.ZERO, -1)
	if bool(r2["theft"]):
		assert_int(int(r2["presence"])).is_equal(0)


func test_monster_departures_become_refugee_waves() -> void:
	var h := _hub()
	var ms: RefCounted = h.mod("monster_society")
	var mig: RefCounted = h.mod("migration")
	mig._ensure()
	ms._departures.append({"sid": 0, "hid": "hh:1", "day": 3, "reason": "monsters", "n": 2})
	var waves: Array = mig._day_core(3)
	assert_int(ms.take_departures().size()).is_equal(0)
	var found := false
	for w: Dictionary in mig.active_waves():
		if String(w["cause"]) == "monsters":
			found = true
			assert_str(String(w["kind"])).is_equal("refugees")
	assert_bool(found or waves.is_empty()).is_true()
	assert_bool(found).is_true()


func test_monster_rent_and_quarter() -> void:
	var h := _hub()
	var hm: RefCounted = h.mod("homes")
	var dv: RefCounted = h.mod("districts")
	var ch: String = h.mod("registry").mint("ch")
	h.mod("organizations").ensure_char(ch, {"cash": 500, "sid": 0, "prof": "baker"})
	assert_bool(dv.has_quarter(0, "monster")).is_false()
	assert_bool("monster" in dv.quarters_of(0)).is_false()
	var res: Dictionary = hm.rent_den(ch, 0, "wolf", "caldric")
	assert_bool(res["ok"]).is_true()
	assert_str(String(res["kind"])).is_equal("den")
	assert_bool(dv.has_quarter(0, "monster")).is_true()
	assert_bool("monster" in dv.quarters_of(0)).is_true()
	assert_float(float(dv.values(0, "monster")["culture_mix"])).is_greater(0.5)
	# Prejudice raises rent.
	var ms: RefCounted = h.mod("monster_society")
	ms._set_prej(0, "caldric", "wolf", 1.0)
	var ch2: String = h.mod("registry").mint("ch")
	h.mod("organizations").ensure_char(ch2, {"cash": 500, "sid": 0, "prof": "baker"})
	var res2: Dictionary = hm.rent_den(ch2, 0, "wolf", "caldric")
	assert_int(int(res2["rent"])).is_greater_equal(int(res["rent"]))
	# Save round trip keeps the quarter.
	var h2 := _hub()
	h2.mod("districts").deserialize(dv.serialize())
	assert_bool(h2.mod("districts").has_quarter(0, "monster")).is_true()
	assert_bool("monster" in h2.mod("districts").quarters_of(0)).is_true()
	hm.tick_week(7, {})


func test_aura_awe_and_dread_move_legitimacy_within_bounds() -> void:
	var sp := SP.new()
	var subj := {"id": "s", "origin": "caldrenn", "title_rank": 3, "insignia": 1.0, "aura_emit": 1.0}
	var calm := {"id": "o1", "kingdom": "solmarch", "magic_sense": 1.0, "intelligence": 1.0, "persona": {"pious": 0.0, "courage": 1.0}}
	var devout := {"id": "o2", "kingdom": "veylwood", "magic_sense": 1.0, "intelligence": 1.0, "persona": {"pious": 1.0, "courage": 0.5}}
	var timid := {"id": "o3", "kingdom": "veylwood", "magic_sense": 1.0, "intelligence": 1.0, "persona": {"pious": 0.0, "courage": 0.0}}
	var base := SP.legitimacy("caldrenn", "veylwood")
	var rd: Dictionary = sp.read(devout, subj)
	var rt: Dictionary = sp.read(timid, subj)
	assert_float(float(rd["legitimacy"])).is_greater(base)
	assert_float(float(rt["legitimacy"])).is_less(base)
	assert_float(float(rd["legitimacy"]) - base).is_less_equal(SP.AWE_LEGIT + 0.0001)
	assert_float(base - float(rt["legitimacy"])).is_less_equal(SP.DREAD_LEGIT + 0.0001)
	var rc: Dictionary = sp.read(calm, {"id": "s", "origin": "caldrenn", "title_rank": 3, "aura_emit": 0.0})
	assert_float(float(rc["legitimacy"])).is_equal(SP.legitimacy("caldrenn", "solmarch"))
	assert_float(float(rc["awe"])).is_equal(0.0)


func test_gossip_table_is_large_and_has_every_band() -> void:
	var lines: Array = Data_lines()
	assert_int(lines.size()).is_greater_equal(120)
	var bands := {}
	for l: Dictionary in lines:
		bands[l["b"]] = true
	assert_int(bands.size()).is_equal(6)


func Data_lines() -> Array:
	var f := FileAccess.open("res://data/world/barks_status.json", FileAccess.READ)
	return (JSON.parse_string(f.get_as_text()) as Dictionary)["lines"]
