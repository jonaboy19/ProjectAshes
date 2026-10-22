extends GdUnitTestSuite
## F5 ownership, theft, trespass, shop hours and the arrest flow: owner strings and resolution, seen vs unseen theft,
## the stolen flag (honest merchants refuse, a fence buys), pickpocket success and failure, trespass after the
## warning, opening hours and the real shop stock, the three arrest choices, and the save round-trip of taken /
## opened / stolen state.

const Ownership := preload("res://scripts/sim/ownership.gd")
const Theft := preload("res://scripts/sim/theft.gd")
const Pickpocket := preload("res://scripts/sim/pickpocket.gd")
const Trespass := preload("res://scripts/population/trespass.gd")
const ShopHours := preload("res://scripts/sim/shop_hours.gd")
const Arrest := preload("res://scripts/sim/arrest.gd")
const WorldState := preload("res://scripts/world/world_state.gd")
const Society := preload("res://scripts/realm/society.gd")
const Container_ := preload("res://scripts/interaction/kinds/container.gd")
const NpcWorld := preload("res://scripts/population/npc_world.gd")
const Perception := preload("res://scripts/population/perception.gd")
const Witness := preload("res://scripts/population/witness.gd")
const Evidence := preload("res://scripts/population/evidence.gd")
const ItemsDB := preload("res://scripts/sim/items_db.gd")
const InteractLabel := preload("res://scripts/ui/interact_label.gd")

var _clock := 8.0
var _gold := 0


# --- helpers ----------------------------------------------------------------------------------------

func _reset_pack() -> void:
	for it: InventoryItem in Life.inventory.get_items().duplicate():
		Life.inventory.remove_item(it)


func before_test() -> void:
	_reset_pack()
	Life.world_state.call("clear")
	Theft.reporter = Callable()
	Theft.last = {}
	Pickpocket.reset()
	Arrest.reset()
	ShopHours.reset()
	NpcWorld.reset()
	Perception.reset()
	Witness.reset()
	Evidence.reset()
	_clock = WorldSim.time_of_day
	_gold = Game.gold


func after_test() -> void:
	_reset_pack()
	Life.world_state.call("clear")
	Theft.reporter = Callable()
	WorldSim.time_of_day = _clock
	Game.gold = _gold


class FakePlayer extends Node3D:
	var dead := false
	var velocity := Vector3.ZERO
	func facing() -> Vector3:
		return Vector3(0, 0, 1)


## A villager the witness path can ask: faces `look` and records what it was told.
class FakeVillager extends Node3D:
	var person := 5
	var look := Vector2(0, -1)
	var told: Array = []
	func _ready() -> void:
		add_to_group("villager")
	func witness(_pos: Vector2, kind: String, saw: bool, _by_player: bool) -> bool:
		told.append([kind, saw])
		return true
	func perception_facing() -> Vector2:
		return look
	func perception_acuity() -> float:
		return 1.0


## A merchant's "come back later" wording (any of the data file's lines mentions morning, dawn, first light or tomorrow).
func _is_closed_line(t: String) -> bool:
	var l := t.to_lower()
	for w in ["morning", "dawn", "first light", "tomorrow"]:
		if l.contains(w):
			return true
	return false


func _player(at := Vector3.ZERO) -> FakePlayer:
	var p := FakePlayer.new()
	add_child(p)
	p.global_position = at
	auto_free(p)
	return p


# --- ownership resolution ---------------------------------------------------------------------------

func test_owner_strings_parse() -> void:
	assert_int(Ownership.kind_of("")).is_equal(Ownership.Kind.PUBLIC)
	assert_int(Ownership.kind_of("public")).is_equal(Ownership.Kind.PUBLIC)
	assert_int(Ownership.kind_of("player")).is_equal(Ownership.Kind.PLAYER)
	assert_int(Ownership.kind_of(Ownership.npc("farmer_joe"))).is_equal(Ownership.Kind.NPC)
	var h := Ownership.household(2, 7)
	assert_str(h).is_equal("household:2:7")
	assert_int(Ownership.sid_of(h)).is_equal(2)
	assert_str(Ownership.lot_id_of(h)).is_equal("s2:l7")
	var s := Ownership.shop(1, "blacksmith")
	assert_int(Ownership.kind_of(s)).is_equal(Ownership.Kind.SHOP)
	assert_int(Ownership.sid_of(s)).is_equal(1)
	assert_str(Ownership.hours_kind_of(s)).is_equal("blacksmith")
	assert_str(Ownership.hours_kind_of(Ownership.shop(0, "healer_house"))).is_equal("healer")
	assert_str(Ownership.hours_kind_of(h)).is_equal("")


func test_is_theft_rules_and_own_property() -> void:
	var mine := {"lots": ["s0:l3"]}
	assert_bool(Ownership.is_theft("", mine)).is_false()
	assert_bool(Ownership.is_theft("public", mine)).is_false()
	assert_bool(Ownership.is_theft("player", mine)).is_false()
	assert_bool(Ownership.is_theft(Ownership.npc(4), mine)).is_true()
	assert_bool(Ownership.is_theft(Ownership.shop(0, "inn"), mine)).is_true()
	assert_bool(Ownership.is_theft(Ownership.household(0, 9), mine)).is_true()
	assert_bool(Ownership.is_theft(Ownership.household(0, 3), mine)).is_false()   # your own house or rented lot
	assert_str(Ownership.building_owner(0, 3, "house_1", mine)).is_equal("player")
	assert_str(Ownership.building_owner(0, 9, "house_1", mine)).is_equal("household:0:9")
	assert_str(Ownership.building_owner(0, 1, "inn", mine)).is_equal("shop:0:inn")
	assert_str(Ownership.building_owner(0, 1, "well", mine)).is_equal("public")


func test_owner_of_node_meta_then_building() -> void:
	var room := Node3D.new()
	add_child(room)
	auto_free(room)
	var chest := Node3D.new()
	room.add_child(chest)
	assert_str(Ownership.owner_of(chest)).is_equal("public")
	room.set_meta("building_owner", "household:0:9")
	assert_str(Ownership.owner_of(chest)).is_equal("household:0:9")      # defaults to the building's owner
	chest.set_meta("owner", "npc:3")
	assert_str(Ownership.owner_of(chest)).is_equal("npc:3")              # its own owner wins


func test_container_defaults_to_building_owner_and_verbs() -> void:
	var room := Node3D.new()
	add_child(room)
	auto_free(room)
	room.set_meta("building_owner", "shop:0:inn")
	var c: Node3D = Container_.spawn(room, Vector3(0, 0, 1), "test/own/c1", "Crate", [{"item": "bread", "qty": 2}])
	assert_str(c.owner_key()).is_equal("shop:0:inn")
	var rows: Array = c._menu()["options"]
	assert_bool(String(rows[0][0]).begins_with("Steal ")).is_true()
	var mine: Node3D = Container_.spawn(room, Vector3(2, 0, 1), "test/own/c2", "Crate", [{"item": "bread", "qty": 1}], "", "player")
	assert_bool(String((mine._menu()["options"] as Array)[0][0]).begins_with("Withdraw ")).is_true()


func test_ground_item_label_steal_is_red_and_take_is_not() -> void:
	var owned := GroundItem.spawn(self, Vector3(40, 0, 40), "bread", 1, "npc:12")
	auto_free(owned)
	var lab := InteractLabel.resolve(owned)
	assert_str(lab["verb"]).is_equal("Steal")
	assert_bool(bool(lab["danger"])).is_true()
	var free := GroundItem.spawn(self, Vector3(42, 0, 40), "bread", 1)
	auto_free(free)
	assert_str(InteractLabel.resolve(free)["verb"]).is_equal("Take")
	assert_bool(bool(InteractLabel.resolve(free)["danger"])).is_false()


# --- theft: seen vs unseen --------------------------------------------------------------------------

func test_assess_scales_the_crime_by_value_and_source() -> void:
	var cheap := Theft.assess("npc:1", "bread", 1, "ground", {"lots": []})
	assert_bool(bool(cheap["theft"])).is_true()
	var v := Ownership.value_of("bread")
	assert_str(String(cheap["kind"])).is_equal("pickpocket" if v < Theft.PETTY_VALUE else "robbery")
	var big := Theft.assess("npc:1", "bread", 50, "ground", {"lots": []})
	assert_str(String(big["kind"])).is_equal("robbery")
	var box := Theft.assess("household:0:4", "bread", 50, "container", {"lots": []})
	assert_str(String(box["kind"])).is_equal("burglary")
	assert_bool(bool(Theft.assess("public", "bread")["theft"])).is_false()
	assert_bool(bool(Theft.assess("household:0:3", "bread", 1, "container", {"lots": ["s0:l3"]})["theft"])).is_false()


func test_stealing_flags_the_goods_and_reports() -> void:
	var calls: Array = []
	Theft.reporter = func(_t: SceneTree, kind: String, pos: Vector2, sid: int) -> Dictionary:
		calls.append([kind, pos, sid])
		return {"seen_by": 2}
	var r := Theft.steal(get_tree(), "shop:3:blacksmith", "bread", 3, "container", Vector2(5, 6), 3, {"lots": []})
	assert_bool(bool(r["theft"])).is_true()
	assert_bool(bool(r["stolen"])).is_true()
	assert_int(int(r["seen_by"])).is_equal(2)
	assert_int(calls.size()).is_equal(1)
	assert_str(String(calls[0][0])).is_equal("burglary")
	assert_int(Life.count("bread")).is_equal(3)
	assert_int(Theft.stolen_count("bread")).is_equal(3)
	assert_int(Theft.stolen_count("bread", 3)).is_equal(3)
	assert_int(Theft.stolen_count("bread", 1)).is_equal(0)
	# Taking what is yours (or nobody's) is not a theft: no report, no flag.
	calls.clear()
	var ok := Theft.steal(get_tree(), "public", "apple", 1, "ground", Vector2.ZERO, 0, {"lots": []})
	assert_bool(bool(ok["theft"])).is_false()
	assert_int(calls.size()).is_equal(0)
	assert_int(Theft.stolen_count("apple")).is_equal(0)


func test_unseen_theft_leaves_evidence_only_and_seen_theft_opens_a_case() -> void:
	WorldSim.time_of_day = 12.0
	var thief_at := Vector2(100.0, 100.0)
	# Unseen: the only villager faces AWAY from the culprit, well inside sight range.
	var far := FakeVillager.new()
	add_child(far)
	auto_free(far)
	far.global_position = Vector3(thief_at.x, 0, thief_at.y + 9.0)
	far.look = Vector2(0, 1)                      # facing +z, away from the thief at -z of him
	var before_ev := Evidence.serialize().size()
	var res := Theft.report(get_tree(), "robbery", thief_at, 0)
	assert_int(int(res["seen_by"])).is_equal(0)
	assert_bool(bool(res.get("pending", false))).is_false()            # nobody saw: no case, no Society crime
	assert_int(int(res.get("case", 0))).is_equal(0)
	assert_int(Evidence.serialize().size()).is_greater(before_ev)                 # but the missing item is on the ground
	far.queue_free()
	await get_tree().process_frame
	# Seen: a villager a few metres away looking straight at the culprit.
	NpcWorld.reset()
	var near := FakeVillager.new()
	add_child(near)
	auto_free(near)
	near.global_position = Vector3(thief_at.x, 0, thief_at.y + 4.0)
	near.look = Vector2(0, -1)                    # looking at the thief
	var res2 := Theft.report(get_tree(), "robbery", thief_at, 0)
	assert_int(int(res2["seen_by"])).is_equal(1)
	assert_int(int(res2.get("case", 0))).is_greater(0)                 # a witness case: the crime will be reported
	assert_bool(bool((near.told[0] as Array)[1])).is_true()


# --- stolen flag: merchants refuse, fences buy ------------------------------------------------------

func test_honest_merchant_refuses_stolen_goods_of_its_town() -> void:
	Theft.give_stolen("bread", 2, 0)
	assert_str(Theft.sale_gate("bread", 0)).is_not_empty()             # the victim's town refuses
	assert_str(Theft.sale_gate("bread", 4)).is_equal("")               # another town does not know
	Life.give("bread", 1)                                              # one clean loaf
	assert_str(Theft.sale_gate("bread", 0)).is_equal("")               # may sell the clean one...
	assert_bool(Theft.take_one_for_sale("bread", 0)).is_true()
	assert_int(Theft.stolen_count("bread")).is_equal(2)                # ...and it is the clean one that goes
	assert_str(Theft.sale_gate("bread", 0)).is_not_empty()
	assert_bool(Theft.take_one_for_sale("bread", 0)).is_false()
	assert_str(Life.sell("bread")).is_not_empty()                      # the real sell path refuses too
	assert_int(Life.count("bread")).is_equal(2)


func test_fence_buys_stolen_goods_first_at_a_cut_price() -> void:
	Theft.give_stolen("bread", 1, 0)
	Life.give("bread", 1)
	assert_bool(Theft.fence_available()).is_true()
	Game.gold = 10
	var price := Theft.fence_price("bread")
	assert_int(price).is_equal(maxi(1, int(floor(float(Ownership.value_of("bread")) * Theft.FENCE_SHARE))))
	var r := Theft.fence_sell("bread", 0)
	assert_bool(bool(r["ok"])).is_true()
	assert_int(Game.gold).is_equal(10 + price)
	assert_int(Theft.stolen_count("bread")).is_equal(0)                # the stolen unit went first
	assert_int(Life.count("bread")).is_equal(1)
	assert_bool(bool(Theft.fence_sell("pearl_of_nothing", 0)["ok"])).is_false()


func test_jail_confiscation_only_takes_stolen() -> void:
	Theft.give_stolen("bread", 2, 0)
	Life.give("apple", 3)
	var taken := Theft.confiscate()
	assert_int(taken.size()).is_equal(1)
	assert_int(Life.count("bread")).is_equal(0)
	assert_int(Life.count("apple")).is_equal(3)


# --- pickpocket -------------------------------------------------------------------------------------

func test_pickpocket_chance_inputs() -> void:
	assert_float(Pickpocket.chance(0.0, 1.0, 1.0, true, 0, false)).is_equal(0.0)        # standing: no
	assert_float(Pickpocket.chance(0.0, 1.0, 1.0, true, 2)).is_equal(0.0)               # already suspicious: no
	var behind := Pickpocket.chance(0.0, 1.0, 1.0, true)
	var front := Pickpocket.chance(0.0, 1.0, 1.0, false)
	assert_float(behind).is_greater(front)
	assert_float(Pickpocket.chance(8.0, 1.0, 1.0, true)).is_greater(behind)             # skill helps
	assert_float(Pickpocket.chance(0.0, 1.0, 0.1, true)).is_greater(behind)             # darkness helps
	assert_float(Pickpocket.chance(0.0, 1.8, 1.0, true)).is_less(behind)                # sharp eyes hurt
	assert_float(behind).is_between(Pickpocket.MIN_CHANCE, Pickpocket.MAX_CHANCE)


func test_pickpocket_success_pays_once_a_day() -> void:
	var p := Pickpocket.chance(2.0, 1.0, 0.5, true)
	assert_bool(bool(Pickpocket.attempt(p, 0.0)["ok"])).is_true()
	assert_bool(bool(Pickpocket.attempt(p, 0.999)["ok"])).is_false()
	var got: Array = []
	var r := Pickpocket.resolve(true, 11, 4, func(g: int) -> void: got.append(g))
	assert_bool(bool(r["ok"])).is_true()
	assert_str(String(r["crime"])).is_equal("pickpocket")           # bystanders may still see it
	assert_int(got.size()).is_equal(1)
	assert_int(int(got[0])).is_between(2, 14)
	var again := Pickpocket.resolve(true, 11, 4, func(g: int) -> void: got.append(g))
	assert_bool(bool(again["ok"])).is_false()                       # their purse is empty today
	assert_int(got.size()).is_equal(1)
	assert_bool(bool(Pickpocket.resolve(true, 11, 5, func(g: int) -> void: got.append(g))["ok"])).is_true()


func test_pickpocket_failure_is_caught_and_reported_as_robbery() -> void:
	var got: Array = []
	var r := Pickpocket.resolve(false, 3, 2, func(g: int) -> void: got.append(g))
	assert_bool(bool(r["ok"])).is_false()
	assert_str(String(r["crime"])).is_equal("robbery")
	assert_int(got.size()).is_equal(0)
	assert_bool(Pickpocket.already_robbed(3, 2)).is_false()         # a failed try does not empty the purse


# --- trespass ---------------------------------------------------------------------------------------

func test_trespass_rules() -> void:
	var other := Ownership.household(0, 9)
	assert_bool(Trespass.evaluate(other, false, 12.0, {"lots": []})).is_false()   # a neighbour's open house by day
	assert_bool(Trespass.evaluate(other, false, 23.0, {"lots": []})).is_true()    # at night
	assert_bool(Trespass.evaluate(other, true, 12.0, {"lots": []})).is_true()     # or locked
	assert_bool(Trespass.evaluate(other, false, 2.0, {"lots": ["s0:l9"]})).is_false()   # your own house
	assert_bool(Trespass.evaluate("player", true, 2.0)).is_false()
	assert_bool(Trespass.evaluate("public", true, 2.0)).is_false()
	# Shops and the inn are public in their open hours.
	var smith := Ownership.shop(0, "blacksmith")
	assert_bool(Trespass.evaluate(smith, false, 10.0, {"lots": []})).is_false()
	assert_bool(Trespass.evaluate(smith, false, 22.0, {"lots": []})).is_true()
	assert_bool(Trespass.evaluate(smith, false, 10.0, {"lots": []}, true)).is_true()   # the back room
	assert_bool(Trespass.evaluate(Ownership.shop(0, "inn"), false, 3.0, {"lots": []})).is_false()


func test_trespass_warns_once_then_crime_after_lingering() -> void:
	var st := Trespass.new_state()
	var events: Array = []
	var rate := Trespass.RATE_WALK
	for i in 60:                                   # 0.5 s ticks, 30 s
		var ev := Trespass.step(st, 0.5, true, rate)
		if ev != "":
			events.append([ev, i])
	assert_int(events.size()).is_equal(2)
	assert_str(String((events[0] as Array)[0])).is_equal("warn")
	assert_str(String((events[1] as Array)[0])).is_equal("crime")
	var gap := (int((events[1] as Array)[1]) - int((events[0] as Array)[1])) * 0.5
	assert_float(gap).is_greater_equal(Trespass.GRACE - 0.5)
	assert_float(gap).is_less_equal(Trespass.GRACE + 0.6)
	# Leaving in time (after the warning, before the grace runs out) is no crime, and it resets.
	var st2 := Trespass.new_state()
	var seen: Array = []
	for i in 40:
		var ev2 := Trespass.step(st2, 0.5, true, Trespass.RATE_RUN)
		if ev2 != "":
			seen.append(ev2)
		if ev2 == "warn":
			break
	assert_array(seen).is_equal(["warn"])
	assert_str(Trespass.step(st2, 0.5, false, 0.0)).is_equal("")
	assert_bool(bool(st2["warned"])).is_false()
	# Crouching is noticed far later than running.
	assert_float(Trespass.rate_for(true, false)).is_less(Trespass.rate_for(false, true))
	# Nobody home: never noticed.
	var st3 := Trespass.new_state()
	for i in 100:
		assert_str(Trespass.step(st3, 1.0, true, Trespass.RATE_RUN, false)).is_equal("")


func test_trespass_commits_a_crime_to_society() -> void:
	assert_bool(Society.CRIMES.has("trespass")).is_true()
	var soc := Society.new()
	var res := Trespass.commit(soc, 0)
	assert_bool(bool(res.get("ok", false))).is_true()
	assert_str(String(res["kind"])).is_equal("trespass")
	assert_int(int(res["noticed"])).is_equal(1)
	assert_bool(Trespass.commit(null, 0).is_empty()).is_true()


# --- shop hours -------------------------------------------------------------------------------------

func test_shop_hours_open_and_closed() -> void:
	assert_bool(ShopHours.is_open("blacksmith", 7.0)).is_true()
	assert_bool(ShopHours.is_open("blacksmith", 6.9)).is_false()
	assert_bool(ShopHours.is_open("blacksmith", 18.9)).is_true()
	assert_bool(ShopHours.is_open("blacksmith", 19.0)).is_false()
	assert_bool(ShopHours.is_open("general_store", 8.0)).is_true()
	assert_bool(ShopHours.is_open("general_store", 20.0)).is_false()
	assert_bool(ShopHours.is_open("inn", 3.0)).is_true()
	assert_bool(ShopHours.is_always("inn")).is_true()
	assert_bool(ShopHours.is_open("temple", 5.9)).is_false()
	assert_bool(ShopHours.is_open("temple", 6.0)).is_true()
	assert_bool(ShopHours.is_open("temple", 21.0)).is_false()
	assert_bool(ShopHours.is_open("black_market", 23.0)).is_true()        # wraps past midnight
	assert_bool(ShopHours.is_open("black_market", 3.0)).is_true()
	assert_bool(ShopHours.is_open("black_market", 12.0)).is_false()
	assert_bool(ShopHours.is_open("unlisted_kind", 12.0)).is_true()       # default 8-20
	assert_bool(ShopHours.is_open("unlisted_kind", 23.0)).is_false()
	assert_bool(ShopHours.is_open("", 3.0)).is_true()


func test_closed_shop_refuses_with_a_line() -> void:
	assert_str(ShopHours.refusal("blacksmith", 12.0)).is_equal("")
	var line := ShopHours.refusal("blacksmith", 3.0)
	assert_str(line).is_not_empty()
	assert_bool(_is_closed_line(line)).is_true()
	assert_str(ShopHours.refusal("inn", 3.0)).is_equal("")
	assert_str(ShopHours.hours_text("blacksmith")).is_equal("Open 07:00 - 19:00")
	assert_str(ShopHours.hours_text("inn")).is_equal("Always open")


func test_station_prompt_shows_closed() -> void:
	var st := Station.new("Blacksmith", "Talk")
	st.hours_kind = "blacksmith"
	add_child(st)
	auto_free(st)
	WorldSim.time_of_day = 3.0
	assert_str(st.prompt()).is_equal("Closed")
	assert_str(InteractLabel.resolve(st)["verb"]).is_equal("Closed")
	WorldSim.time_of_day = 10.0
	assert_str(st.prompt()).is_equal("Talk")
	assert_str(InteractLabel.resolve(st)["verb"]).is_equal("Talk")
	var plain := Station.new("Innkeeper", "Food & bed")
	add_child(plain)
	auto_free(plain)
	WorldSim.time_of_day = 3.0
	assert_str(plain.prompt()).is_equal("Food & bed")


func test_merchant_menu_is_the_markets_real_stock() -> void:
	var m := RAMarket.new()
	ItemsDB.stock_market(m, ["general_store"], 1, 7)
	var lines := ShopHours.stock_lines(m, "general_store", 1, 100)
	assert_int(lines.size()).is_greater(5)
	var goods := {}
	for g: Dictionary in ItemsDB.shop_goods("general_store", 1):
		goods[String(g["item"])] = true
	for l: Dictionary in lines:
		assert_bool(goods.has(String(l["item"]))).is_true()
		assert_int(int(l["stock"])).is_greater(0)
		assert_int(int(l["price"])).is_equal(m.price(String(l["item"])))
	var first := String(lines[0]["item"])
	m.stock[first] = 0
	for l: Dictionary in ShopHours.stock_lines(m, "general_store", 1, 100):
		assert_str(String(l["item"])).is_not_equal(first)               # sold out is not listed
	assert_int(ShopHours.stock_lines(m, "general_store", 1, 3).size()).is_equal(3)
	assert_int(ShopHours.stock_lines(null, "general_store").size()).is_equal(0)


func test_closed_gate_replaces_the_merchant_menu() -> void:
	var sv := VillageServices.new()
	auto_free(sv)
	var opened := [0]
	var gate: Callable = sv._hours_gate("blacksmith", "Smith", func() -> Dictionary:
		opened[0] += 1
		return {"title": "Smith", "body": "open", "options": [["x", func() -> String: return ""]]})
	WorldSim.time_of_day = 12.0
	assert_int((gate.call()["options"] as Array).size()).is_equal(1)
	WorldSim.time_of_day = 2.0
	var closed: Dictionary = gate.call()
	assert_int((closed["options"] as Array).size()).is_equal(0)
	assert_bool(_is_closed_line(String(closed["body"]))).is_true()
	assert_int(opened[0]).is_equal(1)


# --- arrest -----------------------------------------------------------------------------------------

func test_arrest_choices_follow_gold() -> void:
	var poor := Arrest.choices(80, 10)
	assert_str(String(poor[0]["id"])).is_equal("pay")
	assert_bool(bool(poor[0]["enabled"])).is_false()
	assert_bool(bool(poor[1]["enabled"])).is_true()
	assert_bool(bool(poor[2]["enabled"])).is_true()
	assert_bool(bool(Arrest.choices(80, 80)[0]["enabled"])).is_true()
	assert_float(Arrest.jail_hours(0)).is_equal(Arrest.MIN_JAIL_HOURS)
	assert_float(Arrest.jail_hours(100000)).is_equal(Arrest.MAX_JAIL_HOURS)
	assert_bool(Arrest.can_offer(0, 0)).is_false()
	assert_bool(Arrest.can_offer(10, 100000)).is_true()
	Arrest.note_offer(100000)
	assert_bool(Arrest.can_offer(10, 100500)).is_false()
	assert_bool(Arrest.can_offer(10, 100000 + Arrest.COOLDOWN_MS)).is_true()


func test_arrest_pay_clears_the_bounty() -> void:
	var soc := Society.new()
	soc.bounties["0"] = 50
	var spent: Array = []
	var broke := Arrest.pay(soc, 0, 20, func(n: int) -> void: spent.append(n))
	assert_bool(bool(broke["ok"])).is_false()
	assert_int(soc.bounty(0)).is_equal(50)
	var r := Arrest.pay(soc, 0, 120, func(n: int) -> void: spent.append(n))
	assert_bool(bool(r["ok"])).is_true()
	assert_int(int(r["cost"])).is_equal(50)
	assert_int(soc.bounty(0)).is_equal(0)
	assert_array(spent).is_equal([50])


func test_arrest_jail_skips_time_confiscates_stolen_and_wipes_bounty() -> void:
	var soc := Society.new()
	soc.bounties["0"] = 100
	Theft.give_stolen("bread", 2, 0)
	Life.give("apple", 1)
	var skipped: Array = []
	var r := Arrest.jail(soc, 0, func(h: float) -> void: skipped.append(h))
	assert_bool(bool(r["ok"])).is_true()
	assert_array(skipped).is_equal([Arrest.jail_hours(100)])
	assert_int(soc.bounty(0)).is_equal(0)
	assert_int(Life.count("bread")).is_equal(0)
	assert_int(Life.count("apple")).is_equal(1)
	assert_int((r["confiscated"] as Array).size()).is_equal(1)


func test_arrest_resist_raises_bounty_and_alarm() -> void:
	var soc := Society.new()
	soc.bounties["0"] = 30
	var alarms: Array = []
	var r := Arrest.resist(soc, 0, func(levels: int) -> void: alarms.append(levels))
	assert_int(soc.bounty(0)).is_equal(30 + int(r["added"]))
	assert_int(int(r["added"])).is_greater(Arrest.RESIST_SURCHARGE - 1)
	assert_array(alarms).is_equal([2])


func test_arrest_menu_runs_each_choice() -> void:
	var soc := Society.new()
	soc.bounties["0"] = 40
	var done: Array = []
	var ctx := {"soc": soc, "sid": 0, "gold": 100, "advance": func(_h: float) -> void: pass,
		"take_gold": func(_n: int) -> void: pass, "alarm": func(_l: int) -> void: pass,
		"on_done": func(c: String) -> void: done.append(c)}
	var menu := Arrest.menu(ctx)
	assert_int((menu["options"] as Array).size()).is_equal(3)
	assert_str(String(menu["body"])).contains("40 gold")
	var opts: Array = menu["options"]
	var msg: String = (opts[1][1] as Callable).call()
	assert_str(msg).contains("hours")
	assert_int(soc.bounty(0)).is_equal(0)
	soc.bounties["0"] = 40
	(Arrest.menu(ctx)["options"] as Array)[0][1].call()
	assert_int(soc.bounty(0)).is_equal(0)
	assert_array(done).is_equal(["jail", "pay"])


# --- save round-trips -------------------------------------------------------------------------------

func test_taken_and_opened_state_round_trips_world_state() -> void:
	var a := WorldState.new()
	Ownership.mark_taken("ground/bread/10_20", a)
	Ownership.save_container("container/inn/crate/1", [{"item": "rope", "qty": 1}], a)
	var data: Dictionary = a.snapshot()
	var b := WorldState.new()
	b.restore(JSON.parse_string(JSON.stringify(data)))             # through real JSON, as a save file would
	assert_bool(Ownership.state_taken("ground/bread/10_20", b)).is_true()
	assert_bool(Ownership.state_taken("ground/bread/99_99", b)).is_false()
	var st := Ownership.container_state("container/inn/crate/1", b)
	assert_bool(bool(st["opened"])).is_true()
	assert_int((st["contents"] as Array).size()).is_equal(1)
	assert_str(String((st["contents"] as Array)[0]["item"])).is_equal("rope")
	assert_bool(Ownership.container_state("container/never", b)["contents"] == null).is_true()


func test_taken_ground_item_stays_gone_and_container_remembers() -> void:
	var g := GroundItem.spawn(self, Vector3(60, 0, 60), "bread", 1)
	assert_bool(g.take()).is_true()
	var snap: Dictionary = Life.world_state.call("snapshot")
	Life.world_state.call("restore", JSON.parse_string(JSON.stringify(snap)))
	var again := GroundItem.spawn(self, Vector3(60, 0, 60), "bread", 1)
	assert_bool(again.take()).is_false()                           # a fresh node at the same spot is already taken
	var room := Node3D.new()
	add_child(room)
	auto_free(room)
	var c: Node3D = Container_.spawn(room, Vector3(0, 0, 2), "test/own/save", "Crate", [{"item": "bread", "qty": 2}], "", "player")
	c._withdraw("bread", 1)
	var snap2: Dictionary = Life.world_state.call("snapshot")
	Life.world_state.call("restore", JSON.parse_string(JSON.stringify(snap2)))
	var c2: Node3D = Container_.spawn(room, Vector3(0, 0, 4), "test/own/save", "Crate", [{"item": "bread", "qty": 2}], "", "player")
	assert_int((c2.contents[0] as Dictionary)["qty"]).is_equal(1)   # the withdrawn loaf is still gone


func test_stolen_flag_survives_the_inventory_round_trip() -> void:
	Theft.give_stolen("bread", 2, 3)
	Life.give("bread", 1)
	var data: Dictionary = JSON.parse_string(JSON.stringify(Life.inventory.serialize()))
	_reset_pack()
	assert_int(Life.count("bread")).is_equal(0)
	Life.inventory.deserialize(data)
	assert_int(Life.count("bread")).is_equal(3)
	assert_int(Theft.stolen_count("bread")).is_equal(2)
	assert_int(Theft.stolen_count("bread", 3)).is_equal(2)
	assert_str(Theft.sale_gate("bread", 3)).is_equal("")           # the clean loaf can still be sold
	assert_bool(Theft.take_one_for_sale("bread", 3)).is_true()
	assert_str(Theft.sale_gate("bread", 3)).is_not_empty()
