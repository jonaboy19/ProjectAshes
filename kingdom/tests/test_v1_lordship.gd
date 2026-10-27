extends GdUnitTestSuite
## READY_V1 C5, the lordship milestone: a camp that grows into a Village (C4 growth module) makes the player its lord exactly once, under a
## synthetic settlement index; the Lord's Council opens for it, taxes and projects work, the title "Lord of <camp>" is granted, and
## lordship + title survive a save.

const Sim := preload("res://tools_qa/v1/settlement_sim.gd")
const Lordship := preload("res://scripts/sim/lordship.gd")
const FoundedLord := preload("res://scripts/sim/founded_lord.gd")
const LordCouncil := preload("res://scripts/ui/lord_council.gd")


func _grown() -> Dictionary:
	var hub: RefCounted = Sim.make_hub()
	var lord: RefCounted = Lordship.new()
	var titles := RATitles.new()
	FoundedLord.bind(hub, lord, titles)
	var res: Dictionary = Sim.run(120, 3, hub)
	res["lord"] = lord
	res["titles"] = titles
	return res


func test_a_village_makes_you_its_lord_once() -> void:
	var granted: Array = []
	var hub: RefCounted = Sim.make_hub()
	var lord: RefCounted = Lordship.new()
	var titles := RATitles.new()
	FoundedLord.bind(hub, lord, titles)
	lord.village_changed.connect(func(i: int) -> void: granted.append(i))
	var early: Dictionary = Sim.run(40, 3, hub)      # a Hamlet by now, no Village yet: nobody is lord
	assert_bool(lord.is_lord_of(Lordship.founded_idx(int(early["gid"])))).is_false()
	assert_array(granted).is_empty()
	var res: Dictionary = _grown()
	var l2: RefCounted = res["lord"]
	var gid := int(res["gid"])
	var idx := Lordship.founded_idx(gid)
	assert_int(int(res["village_day"])).is_between(60, 90)
	assert_bool(l2.is_lord_of(idx)).is_true()
	var v: Dictionary = l2.village(idx)
	assert_str(String(v["reason"])).is_equal("founded")
	assert_str(String(v["name"])).is_equal("Simhold")
	# a second report or a direct call does not grant again
	var again: Dictionary = FoundedLord.on_village(res["hub"], l2, res["titles"], gid)
	assert_int(int(again["granted_day"])).is_equal(int(v["granted_day"]))
	assert_int(l2.held_settlements().size()).is_equal(1)
	var t: RATitles = res["titles"]
	assert_bool(t.has(FoundedLord.title_id(gid))).is_true()
	assert_str(String(t.get_def(FoundedLord.title_id(gid))["name"])).is_equal("Lord of Simhold")
	assert_float(Lordship.BASE_TAX_PER_POP).is_equal(0.045)


func test_the_founded_village_pays_taxes_and_takes_its_people_from_the_growth_module() -> void:
	var res: Dictionary = _grown()
	var lord: RefCounted = res["lord"]
	var idx := Lordship.founded_idx(int(res["gid"]))
	var pop: int = int((res["hub"] as RefCounted).mod("growth").ledger(int(res["gid"]))["pop"])
	var t0 := int(lord.village(idx)["treasury"])
	for d in 10:
		lord.daily_tick(200 + d, {"season": "summer", "at_war": false})
	var v: Dictionary = lord.village(idx)
	assert_int(int(v["population"])).is_equal(pop)
	assert_int(int(v["treasury"])).is_not_equal(t0)                      # taxes in, militia wages out
	assert_int(int(v["ledger"]["income"])).is_greater(0)
	assert_str(lord.set_tax_rate(idx, "high")).is_not_empty()
	assert_str(lord.start_project(idx, "well")).is_not_empty()


func test_the_council_opens_for_the_founded_index() -> void:
	var gid := 3
	var idx := Lordship.founded_idx(gid)
	Life.lordship.villages.erase(idx)
	Life.lordship.grant(idx, "founded", {"name": "Councilhold", "pos": Vector2(100, 100), "radius": 40.0, "population": 20})
	var council: Control = (load("res://scripts/ui/lord_council.gd") as GDScript).new()
	add_child(council)
	auto_free(council)
	council.call("open", idx)
	var heads: Array = []
	_collect(council, heads)
	assert_str("\n".join(heads)).contains("The Lord's Council — Councilhold")
	assert_str("\n".join(heads)).contains("Tax rate")
	council.call("close_screen")
	Life.lordship.villages.erase(idx)


func _collect(n: Node, out: Array) -> void:
	if n is Label:
		out.append((n as Label).text)
	elif n is Button:
		out.append((n as Button).text)
	for c in n.get_children():
		_collect(c, out)


func test_lordship_and_title_survive_a_save() -> void:
	var res: Dictionary = _grown()
	var lord: RefCounted = res["lord"]
	var gid := int(res["gid"])
	var idx := Lordship.founded_idx(gid)
	var l2: RefCounted = Lordship.new()
	l2.deserialize(JSON.parse_string(JSON.stringify(lord.serialize())))
	assert_bool(l2.is_lord_of(idx)).is_true()
	assert_str(l2.settlement_name(idx)).is_equal("Simhold")
	assert_str(String(l2.village(idx)["reason"])).is_equal("founded")
	var t1: RATitles = res["titles"]
	var t2 := RATitles.new()
	t2.deserialize(JSON.parse_string(JSON.stringify(t1.serialize())))
	assert_bool(t2.has(FoundedLord.title_id(gid))).is_true()
	assert_dict(t2.get_def(FoundedLord.title_id(gid))).is_empty()      # the definition is not saved ...
	FoundedLord.sync_titles(l2, t2)
	assert_str(String(t2.get_def(FoundedLord.title_id(gid))["name"])).is_equal("Lord of Simhold")   # ... the held village brings it back
	# and the daily tick still runs after a load
	l2.daily_tick(300, {"season": "autumn", "at_war": false})
