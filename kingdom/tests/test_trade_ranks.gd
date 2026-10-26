extends GdUnitTestSuite
## Independent trade ranks: by mastery + times done, announced once, rows for the career screen, save round-trip.

const TR := preload("res://scripts/sim/trade_ranks.gd")
const Mastery := preload("res://scripts/sim/mastery.gd")


func test_rank_for() -> void:
	assert_int(TR.rank_for("fisher", 0, 0)).is_equal(-1)
	assert_int(TR.rank_for("fisher", 0, 1)).is_equal(0)
	assert_int(TR.rank_for("fisher", 8, 24)).is_equal(0)
	assert_int(TR.rank_for("fisher", 8, 25)).is_equal(1)
	assert_int(TR.rank_for("fisher", 100, 9999)).is_equal(3)


func test_update_announces_promotions_once_and_rows() -> void:
	var t := TR.new()
	var m := Mastery.new()
	m.gain("mining", 400.0, 1)
	var acts := {"mined": 40.0}
	var lines := t.update(m, acts)
	assert_int(lines.size()).is_equal(1)
	assert_str(String(lines[0])).contains("Miner")
	assert_int(t.update(m, acts).size()).is_equal(0)
	var rows := t.rows(m, acts)
	assert_int(rows.size()).is_equal(1)
	assert_str(String(rows[0]["next"])).is_equal("Master Miner")


func test_save() -> void:
	var t := TR.new()
	t.ranks = {"cook": 2}
	var u := TR.new()
	u.deserialize(t.serialize())
	assert_int(int(u.ranks["cook"])).is_equal(2)


func test_career_screen_compiles() -> void:
	var s: GDScript = load("res://scripts/ui/career_screen.gd")
	assert_bool(s != null and s.can_instantiate()).is_true()


func test_nobility_screen_compiles() -> void:
	var s: GDScript = load("res://scripts/ui/nobility_screen.gd")
	assert_bool(s != null and s.can_instantiate()).is_true()


func test_player_decrees_need_the_claim() -> void:
	WorldGen.setup(WorldSim.SEED)
	var hub: RefCounted = preload("res://scripts/realm/realm_hub.gd").new()
	var gov: RefCounted = hub.mod("governance")
	gov.call("_ensure")
	var sid := 1
	assert_bool(gov.set_law_by_player(sid, "curfew", 2)).is_false()
	assert_bool(gov.claim_for_player(sid)).is_true()
	var before := int(gov.law_level(sid, "curfew"))
	var want := 2 if before != 2 else 0
	assert_bool(gov.set_law_by_player(sid, "curfew", want)).is_true()
	assert_int(int(gov.law_level(sid, "curfew"))).is_equal(want)
	var s: GDScript = load("res://scripts/ui/lord_council.gd")
	assert_bool(s.can_instantiate()).is_true()


func test_thief_ranks_by_unseen_thefts() -> void:
	var t := TR.new()
	assert_array(t.update(null, {"stole_unseen": 30.0})).contains(["You are now a Thief."])


func test_named_heir_goes_first_and_saves() -> void:
	var Fam := preload("res://scripts/sim/family.gd")
	var f: RefCounted = Fam.new()
	f.designated_heir = 7
	var g: RefCounted = Fam.new()
	g.deserialize(f.serialize())
	assert_int(g.designated_heir).is_equal(7)
	var s: GDScript = load("res://scripts/ui/family_screen.gd")
	assert_bool(s.can_instantiate()).is_true()
