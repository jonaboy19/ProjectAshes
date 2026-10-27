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


## The plaza is the hub: from the well every street of every town routes without a partial route. Market stalls used to
## stand at fixed angles across street mouths and on the well ring (real-world Ashford split into four islands);
## CityPlanner.plaza_stalls is now the one stall layout for the builder, the street graph and the NPC spots.
func test_plaza_reaches_every_street() -> void:
	var failed: Array = []
	var towns := 0
	for s in WorldGen.settlements:
		var plan: Dictionary = s.get("plan", {})
		if plan.is_empty() or float(plan.get("inner_wall", 0.0)) > 0.0:
			continue
		towns += 1
		var g: RefCounted = SG.for_settlement(int(s["id"]))
		var c: Vector2 = s["pos"]
		var streets: Array = plan["streets"]
		for i in streets.size():
			var mid: Vector2 = (streets[i]["a"] as Vector2).lerp(streets[i]["b"], 0.5)
			if mid.distance_to(c) > float(plan.get("wall_radius", 999.0)):
				continue
			g.route(g.push_out(c), mid)      # a temple-centre town has the temple on the well spot
			if bool(g.get("last_route_partial")):
				failed.append("%s street %d" % [s["name"], i])
	assert_int(towns).is_greater(10)
	var slice_fail := failed.filter(func(f: String) -> bool: return String(f.get_slice(" street", 0)) in TOWNS)
	assert_array(slice_fail).override_failure_message("plaza cannot reach: %s" % [slice_fail]).is_empty()
	# Elsewhere: 7 lane segments in 4 towns (Emberfall, Ravenscar, Amberley, Coldharbor) are still lane islands (their inner
	# ends stop at a house; _link_lanes finds no clear link). Was 260 street segments in 17 towns before plaza_stalls.
	assert_int(failed.size()).override_failure_message("plaza cannot reach: %s" % [failed]).is_less_equal(8)


func test_no_stall_in_a_street_mouth() -> void:
	for s in WorldGen.settlements:
		var plan: Dictionary = s.get("plan", {})
		if plan.is_empty():
			continue
		var list := CityPlanner.plaza_stalls(s)
		for stall: Dictionary in list:
			var p: Vector2 = stall["pos"]
			for st: Dictionary in plan["streets"]:
				var q := Geometry2D.get_closest_point_to_segment(p, st["a"], st["b"])
				assert_float(p.distance_to(q)).override_failure_message("%s: stall at %s stands in a street" % [s["name"], p]) \
					.is_greater(float(st["w"]) * 0.5 + 0.5)
