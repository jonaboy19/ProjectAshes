extends GdUnitTestSuite
## WP-13: the hidden underground trading post under dungeon floor 1 (Kestrel's Folly).

const Hub := preload("res://scripts/realm/realm_hub.gd")
const CTX := {"season": "summer", "at_war": false, "abs_hours": 0, "gold": 0, "player_pos": Vector3.ZERO, "life": null}


func _hub() -> RefCounted:
	WorldGen.setup(2024)
	return Hub.new()


func test_kind_and_six_registry_characters() -> void:
	var hub := _hub()
	var s: RefCounted = hub.mod("settlements")
	assert_str(s.post_kind()).is_equal("underground")
	var chars: Array = s.post_characters()
	assert_int(chars.size()).is_equal(6)
	var seen := {}
	for c: Dictionary in chars:
		assert_str(String(c["pid"])).starts_with("ch:")
		assert_bool(hub.mod("registry").is_upgraded(String(c["pid"]))).is_true()
		seen[c["pid"]] = true
	assert_int(seen.size()).is_equal(6)
	# Same keys, same persistent ids.
	assert_str(String(hub.mod("registry").lookup("sn:ug_marra_vesk"))).is_equal(String(chars[0]["pid"]))


func test_attached_to_floor_one_at_kestrels_folly() -> void:
	var s: RefCounted = _hub().mod("settlements")
	assert_int(int(s.post()["floor"])).is_equal(1)
	var e: Vector2 = s.post_entrance()
	var a := RealWorld.slice_anchor("cave_entrance")
	if a != Vector2.INF:
		assert_vector(e).is_equal(a)
	else:
		assert_vector(e).is_equal(Vector2(790, -1155))
	assert_bool(s.near_entrance(e)).is_true()
	assert_bool(s.near_entrance(e + Vector2(500, 0))).is_false()


func test_hidden_until_discovered() -> void:
	var hub := _hub()
	var s: RefCounted = hub.mod("settlements")
	assert_bool(s.post_discovered()).is_false()
	assert_dict(s.post_marker()).is_empty()
	assert_bool(hub.mod("exploration").post_known(String(s.post()["id"]))).is_false()
	assert_bool(s.post_buy("iron_ingot", 1, 100)["ok"]).is_false()
	assert_bool(s.post_sell("bread", 1)["ok"]).is_false()
	assert_bool(s.discover_post(4)).is_true()
	assert_bool(s.discover_post(5)).is_false()
	assert_str(String(s.post_marker()["kind"])).is_equal("underground")
	assert_bool(hub.mod("exploration").post_known(String(s.post()["id"]))).is_true()


func test_not_among_overworld_settlements() -> void:
	var s: RefCounted = _hub().mod("settlements")
	s.post()
	assert_int(s.settlement_ids().size()).is_equal(WorldGen.settlements.size())


func test_sells_iron_buys_food() -> void:
	var s: RefCounted = _hub().mod("settlements")
	s.discover_post(1)
	assert_int(s.post_ask("iron_ingot")).is_greater(0)
	assert_int(s.post_ask("bread")).is_equal(0)       # food is not for sale
	assert_int(s.post_bid("bread")).is_greater(0)
	assert_int(s.post_bid("iron_ingot")).is_equal(0)  # iron is not bought
	var buy: Dictionary = s.post_buy("iron_ingot", 5, 1000)
	assert_bool(buy["ok"]).is_true()
	assert_int(buy["qty"]).is_equal(5)
	assert_int(buy["cost"]).is_equal(5 * s.post_ask("iron_ingot"))
	var poor: Dictionary = s.post_buy("iron_ingot", 5, 5)
	assert_bool(poor["ok"]).is_false()
	var sold: Dictionary = s.post_sell("bread", 10)
	assert_bool(sold["ok"]).is_true()
	assert_int(sold["paid"]).is_greater(0)


func test_food_pays_more_when_the_post_is_hungry() -> void:
	var s: RefCounted = _hub().mod("settlements")
	s.discover_post(1)
	var full: int = s.post_bid("bread")
	for k in ["bread", "grain", "smoked_fish", "flour"]:
		s.post()["stock"][k] = 0.0
	assert_int(s.post_bid("bread")).is_greater(full - 1)


func test_ticks_produce_iron_and_eat_food() -> void:
	var s: RefCounted = _hub().mod("settlements")
	var before := float(s.post()["stock"]["iron_ingot"])
	var food := float(s.post()["stock"]["bread"]) + float(s.post()["stock"]["grain"])
	for d in 10:
		s.tick_day(d, CTX)
	assert_float(float(s.post()["stock"]["iron_ingot"])).is_greater(before)
	assert_float(float(s.post()["stock"]["bread"]) + float(s.post()["stock"]["grain"])).is_less(food)
	s.catch_up(20, CTX)
	assert_float(float(s.post()["stock"]["iron_ingot"])).is_greater(before + 30.0)


func test_save_roundtrip() -> void:
	var hub := _hub()
	var s: RefCounted = hub.mod("settlements")
	s.discover_post(3)
	s.post_sell("bread", 4)
	s.tick_day(3, CTX)
	var snap := JSON.stringify(s.serialize())
	var ex_snap := JSON.stringify(hub.mod("exploration").serialize())
	var hub2 := _hub()
	hub2.mod("exploration").deserialize(JSON.parse_string(ex_snap))
	var s2: RefCounted = hub2.mod("settlements")
	s2.deserialize(JSON.parse_string(snap))
	assert_bool(s2.post_discovered()).is_true()
	assert_int(s2.post_characters().size()).is_equal(6)
	assert_str(JSON.stringify(s2.serialize()["post"])).is_equal(JSON.stringify(JSON.parse_string(snap)["post"]))
	assert_bool(hub2.mod("exploration").post_known(String(s2.post()["id"]))).is_true()
	assert_dict(s2.post_marker()).is_not_empty()
