extends GdUnitTestSuite
## READY_V1 C10 hunting loop: yield table by kind and hunting level, hide-tearing by skill, mastery gain from skinning,
## and the recipe chain (hide -> leather, game meat -> jerky). Pure rules run on a stand-in for Life; one test drives the
## real CorpseLoot action through the Life autoload.

const Crafting := preload("res://scripts/sim/crafting.gd")
const Mastery := preload("res://scripts/sim/mastery.gd")


## Stand-in for the Life autoload: mastery + an inventory.
class FakeLife extends RefCounted:
	var mastery := Mastery.new()
	var items := {}

	func give(id: String, n := 1) -> void:
		items[id] = count(id) + n

	func take(id: String, n := 1) -> bool:
		if count(id) < n:
			return false
		items[id] = count(id) - n
		return true

	func count(id: String) -> int:
		return int(items.get(id, 0))

	func item_name(id: String) -> String:
		return Crafting.item_name(id)


func _total(haul: Dictionary, id: String) -> int:
	var n := 0
	for e: Array in haul["items"]:
		if e[0] == id:
			n += int(e[1])
	return n


func test_yield_table_per_kind() -> void:
	# A master hunter never tears a hide, so the base table shows through.
	var deer := Hunting.roll("deer", 40, "t1")
	assert_int(_total(deer, "venison")).is_greater_equal(1)
	assert_int(_total(deer, "deer_hide")).is_equal(1)
	assert_int(_total(Hunting.roll("rabbit", 40, "t2"), "rabbit_meat")).is_greater_equal(1)
	assert_int(_total(Hunting.roll("fox", 40, "t3"), "fox_pelt")).is_equal(1)
	var boar := Hunting.roll("boar", 40, "t4")
	assert_int(_total(boar, "pork")).is_greater_equal(1)
	assert_int(_total(boar, "boar_tusk")).is_equal(1)
	assert_int(_total(Hunting.roll("stag", 40, "t5"), "venison")).is_greater_equal(2)
	assert_int(_total(Hunting.roll("bear", 60, "t6"), "bear_pelt")).is_equal(1)
	var wolf := Hunting.roll("wolf", 60, "t7")
	assert_int(wolf["items"].size()).is_greater(0)
	for kind in ["cow", "sheep", "horse", "dog", "chicken", "blight_rat"]:
		assert_bool(Hunting.can_skin(kind)).override_failure_message(kind).is_false()
		assert_array(Hunting.roll(kind, 40, "x")["items"]).is_empty()


func test_roll_is_deterministic() -> void:
	assert_dict(Hunting.roll("deer", 12, "same")).is_equal(Hunting.roll("deer", 12, "same"))


func test_stag_gives_antler_and_it_is_an_item() -> void:
	var antlers := 0
	for i in 60:
		antlers += _total(Hunting.roll("stag", 20, "a%d" % i), "antler")
	assert_int(antlers).is_greater(30)
	for id in ["antler", "wolf_meat", "venison", "deer_hide", "fox_pelt", "wolf_pelt", "bear_pelt", "pork", "boar_tusk", "rabbit_meat"]:
		assert_bool(Crafting.item_exists(id)).override_failure_message(id).is_true()


func test_skill_stops_hides_tearing() -> void:
	assert_float(Hunting.ruin_chance(1)).is_equal_approx(Hunting.RUIN_START, 0.0001)
	assert_float(Hunting.ruin_chance(10)).is_less(Hunting.ruin_chance(1))
	assert_float(Hunting.ruin_chance(19)).is_equal(0.0)
	var torn_novice := 0
	var torn_adept := 0
	for i in 400:
		torn_novice += (Hunting.roll("deer", 1, "n%d" % i)["ruined"] as Array).size()
		torn_adept += (Hunting.roll("deer", 25, "n%d" % i)["ruined"] as Array).size()
	assert_int(torn_novice).is_between(90, 190)     # ~35 %
	assert_int(torn_adept).is_equal(0)


func test_skill_adds_meat() -> void:
	var low := 0
	var high := 0
	for i in 400:
		low += _total(Hunting.roll("deer", 1, "m%d" % i), "venison")
		high += _total(Hunting.roll("deer", 50, "m%d" % i), "venison")
	assert_int(low).is_equal(400)               # no bonus portion at level 1
	assert_int(high).is_greater(400 + 150)      # +60 % bonus portions at level >= 51
	assert_float(Hunting.bonus_chance(500)).is_equal(Hunting.BONUS_CAP)


func test_skinning_trains_hunting() -> void:
	var life := FakeLife.new()
	assert_int(life.mastery.level("hunting")).is_equal(1)
	var leveled := false
	for i in 40:
		var r := Hunting.skin("stag", "k%d" % i, life, 10 + i)
		leveled = leveled or bool(r["level_up"])
		assert_str(String(r["text"])).contains("You skin the stag")
	assert_float(float(life.mastery.xp.get("hunting", 0.0))).is_equal_approx(40.0 * float(Hunting.XP["stag"]), 0.001)
	assert_int(life.mastery.level("hunting")).is_greater(1)
	assert_bool(leveled).is_true()
	assert_float(float(life.mastery.xp.get("beast_lore", 0.0))).is_greater(0.0)     # mastery overlap
	assert_int(life.count("venison")).is_greater_equal(80)


func test_recipe_chain_hide_to_leather_and_game_to_jerky() -> void:
	var c := Crafting.new()
	assert_array(Array(c.validate())).is_empty()
	var life := FakeLife.new()
	# Hunt: a master's skinning of deer + boar gives hide and meat.
	for i in 6:
		Hunting.skin("deer", "chain%d" % i, life, 5)
	# Without hides torn the stack builds up; guarantee the inputs the recipes need.
	life.give("deer_hide", 2)
	life.give("tannin", 1)
	life.give("salt", 1)
	assert_str(c.can_craft("tan_hide", life)).is_equal("")
	var tan := c.craft("tan_hide", life, null, {"roll": 0.5})
	assert_bool(bool(tan["ok"])).is_true()
	assert_int(life.count("leather")).is_equal(1)
	assert_str(c.can_craft("game_jerky", life, ["campfire"])).is_equal("")
	var jerky := c.craft("game_jerky", life, ["campfire"], {"roll": 0.5})
	assert_bool(bool(jerky["ok"])).is_true()
	assert_int(life.count("jerky")).is_equal(2)
	assert_int(life.count("salt")).is_equal(0)
	assert_str(c.can_craft("game_jerky", life, ["campfire"])).is_not_equal("")     # out of salt


func test_hunter_board_posts_are_real_items() -> void:
	for p: Dictionary in Life.HUNTER_POSTS:
		assert_bool(Crafting.item_exists(String(p["item"]))).is_true()
		assert_str(String(p["title"]) % 3).starts_with("Hunter:")


func test_corpse_action_pays_once() -> void:
	CorpseLoot.reset()
	var before := Life.count("venison")
	var xp0 := float(Life.mastery.xp.get("hunting", 0.0))
	var res := CorpseLoot.skin_animal("deer", "test/deer/1")
	assert_int(Life.count("venison")).is_equal(before + _total(res, "venison"))
	assert_float(float(Life.mastery.xp.get("hunting", 0.0))).is_greater(xp0)
	assert_dict(CorpseLoot.skin_animal("deer", "test/deer/1")).is_empty()     # a carcass is skinned once
	CorpseLoot.reset()


func test_carcass_prompt_follows_death_and_respawn() -> void:
	CorpseLoot.reset()
	var body: Node3D = auto_free(Node3D.new())
	body.set("dead", false)
	add_child(body)
	assert_object(CorpseLoot.attach_animal(body, "cow")).is_null()      # livestock is not game
	var c := CorpseLoot.attach_animal(body, "deer")
	assert_object(c).is_not_null()
	assert_str(c.verb).is_equal("Skin")
	assert_float(c.hold_time).is_greater(0.0)
	var first_id := c.id
	var again := CorpseLoot.attach_animal(body, "deer")      # a pooled body that died again: fresh component
	assert_object(again).is_not_null()
	assert_str(again.id).is_not_equal(first_id)
	CorpseLoot.reset()
