extends GdUnitTestSuite
## Deposit definitions of the world gather nodes (forage, build resources, fishing) are sane and regrow
## on the same schedule as the old per-node timers.

const Forage := preload("res://scripts/world/forage_nodes.gd")
const BuildRes := preload("res://scripts/world/build_resources.gd")
const Fishing := preload("res://scripts/world/fishing_spot.gd")
const Gathering := preload("res://scripts/sim/gathering_items.gd")
const D := preload("res://scripts/realm/construction_data.gd")
const Deposits := preload("res://scripts/world/deposits.gd")
const WorldState := preload("res://scripts/world/world_state.gd")


func test_forage_defs_regrow_in_respawn_days() -> void:
	var dep: RefCounted = Deposits.new(WorldState.new())
	for kind: String in Gathering.FORAGE:
		var def: Dictionary = Forage.dep_def(kind)
		assert_bool(def.is_empty()).is_false()
		var id: String = Forage.dep_id(Vector2i(3, 4), kind)
		dep.consume(id, def, int(def["cap"]), 10)
		assert_bool(dep.is_depleted(id, def, 10)).is_true()
		assert_int(dep.units(id, def, 10 + int(Gathering.FORAGE[kind]["respawn_days"]))).is_equal(int(def["cap"]))


func test_build_defs_regrow_with_construction_days() -> void:
	var dep: RefCounted = Deposits.new(WorldState.new())
	for kind: String in D.NODES:
		var def: Dictionary = BuildRes.dep_def(kind)
		assert_str(String(def["item"])).is_equal(String(D.NODES[kind]["item"]))
		dep.consume("b/%s" % kind, def, int(def["cap"]), 5)
		assert_int(dep.units("b/%s" % kind, def, 5 + int(D.NODES[kind]["regrow"]))).is_equal(int(def["cap"]))


func test_fishing_stock_def() -> void:
	var def: Dictionary = Fishing.dep_def()
	assert_str(String(def["kind"])).is_equal("fish")
	assert_int(int(def["cap"])).is_greater(0)


func test_plunge_pool_is_a_rare_fish_spot() -> void:
	# Hollin Falls (Region 1 look pass): no perch, the emberfin rise at any hour, other waters are unchanged.
	var w: Dictionary = Gathering.fish_weights(9.0, true, "plunge")
	assert_float(float(w["perch"])).is_equal(0.0)
	assert_float(float(w["emberfin"])).is_greater(20.0)
	assert_float(float(Gathering.fish_weights(9.0, true)["emberfin"])).is_equal(0.0)     # a river at 9:00 has none
	var seen := {}
	for i in 100:
		seen[Gathering.roll_fish(i / 100.0, 9.0, true, "plunge")] = true
	assert_bool(seen.has("emberfin")).is_true()
	assert_bool(seen.has("perch")).is_false()
	assert_str(Gathering.roll_fish(0.0, 9.0, true)).is_equal("perch")
	# The spot data lives in the landmark file and names a known pool.
	var lm: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/region1/landmarks.json"))
	var found := false
	for l: Dictionary in lm["landmarks"]:
		for f: Dictionary in l.get("fishing", []):
			found = true
			assert_bool(Gathering.POOLS.has(String(f["pool"]))).is_true()
	assert_bool(found).is_true()
