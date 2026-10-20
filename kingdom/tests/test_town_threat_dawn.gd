extends GdUnitTestSuite
## Region 1 blocker found by the story playtest: the birth cutscene stages a night shot, a town's probe wolves come out in that "night",
## and the clock is then set straight back to the morning (no hour_changed at dawn): the child woke to wolves at the family door.
## By day nothing prowls the town, whatever the clock did.

const TownThreat := preload("res://scripts/world/town_kit/town_threat.gd")


class StubWolf extends Node3D:
	var dead := false


func _threat() -> Node:
	var t: Node = auto_free(TownThreat.new())
	t.tid = "ashford"
	return t


func after_test() -> void:
	WorldSim.time_of_day = 12.0


func test_probe_creatures_left_over_from_a_staged_night_go_at_morning() -> void:
	var t := _threat()
	var w: StubWolf = StubWolf.new()
	add_child(w)
	t.probe_wolves.append(w)
	WorldSim.time_of_day = 8.2       # the cutscene gave the morning back without the clock passing dawn
	t.tick(Vector2(1000, 1000))
	assert_int(t.probe_wolves.size()).override_failure_message("a probe wolf still prowls at 8 o'clock").is_equal(0)


func test_they_stay_while_it_is_night() -> void:
	var t := _threat()
	var w: StubWolf = auto_free(StubWolf.new())
	add_child(w)
	t.probe_wolves.append(w)
	WorldSim.time_of_day = 23.0
	t.tick(Vector2(1000, 1000))
	assert_int(t.probe_wolves.size()).is_equal(1)
