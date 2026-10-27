extends GdUnitTestSuite
## Towns medieval pass: NPCs can walk out of the new alleys. For houses on alleys (CityPlanner._frontage) in several towns the
## street graph routes from the front door to the main gate road without a partial route and without crossing a building footprint.

const SG := preload("res://scripts/population/street_graph.gd")
const TOWNS := ["Ashford", "Kingsreach", "Stonehollow", "Thornfield", "Redwater", "Millbrook", "Highcliff"]


func before() -> void:
	WorldGen.setup(1066)


func test_alley_doors_route_to_the_plaza() -> void:
	var checked := 0
	var failed: Array = []
	for s in WorldGen.settlements:
		if not String(s["name"]) in TOWNS:
			continue
		var plan: Dictionary = s["plan"]
		var streets: Array = plan["streets"]
		var first := int(plan.get("alleys_from", streets.size()))
		var g: RefCounted = SG.for_settlement(int(s["id"]))
		var c: Vector2 = s["pos"]
		var n := 0
		for lot: Dictionary in plan["lots"]:
			if n >= 6 or not bool(lot.get("infill", false)):
				continue
			var door := CityPlanner.door_point(lot)
			var on_alley := false
			for i in range(first, streets.size()):
				var q := Geometry2D.get_closest_point_to_segment(door, streets[i]["a"], streets[i]["b"])
				if door.distance_to(q) < float(streets[i]["w"]) * 0.5 + 1.5:
					on_alley = true
					break
			if not on_alley:
				continue
			n += 1
			var start := door + Vector2(sin(float(lot["yaw"])), cos(float(lot["yaw"]))) * 1.2
			var goal: Vector2 = ((streets[0]["a"] as Vector2) + (streets[0]["b"] as Vector2)) * 0.5     # the main gate road
			var path: PackedVector2Array = g.route(start, goal)
			checked += 1
			var prev := start
			var why := "partial" if bool(g.get("last_route_partial")) or path.is_empty() else ""
			if g.inside(start, 0.2):
				why += " start-inside"
			var walked := 0.0
			for p: Vector2 in path:
				if walked < 30.0 and not g.clear_line(prev, p, 0.2):    # the alley stretch out of the door must be clear
					why += " cross@%s" % [p]
				walked += prev.distance_to(p)
				prev = p
			if why != "":
				failed.append("%s door %s: %s" % [s["name"], door, why])
	assert_int(checked).is_greater(5)
	assert_array(failed).override_failure_message("blocked alley routes: %s" % [failed]).is_empty()


## Save migration: a lot moved for a lane link (CityPlanner._move_blocker) keeps its planned identity.
func test_moved_lot_keeps_its_ids() -> void:
	for s in WorldGen.settlements:
		for lot: Dictionary in s["plan"]["lots"]:
			if lot.has("moved_from"):
				assert_bool(bool(lot.get("infill", false))).is_false()
				assert_float((lot["moved_from"] as Vector2).distance_to(lot["pos"])).is_less_equal(8.01)
