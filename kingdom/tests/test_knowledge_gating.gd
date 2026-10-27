extends GdUnitTestSuite
## WP-08: deciders and panels learn about distant events only through news / scouts, and the NPC inspector reads one character.

const Hub := preload("res://scripts/realm/realm_hub.gd")
const Knowledge := preload("res://scripts/realm/knowledge.gd")
const Inspector := preload("res://scripts/ui/npc_inspector.gd")
const CTX := {"season": "spring", "at_war": false, "abs_hours": 0.0, "gold": 0, "player_pos": Vector2.ZERO}


func _mk() -> RefCounted:
	WorldGen.setup(2024)
	var hub: RefCounted = Hub.new()
	hub.warm_up()
	return hub


func _far_pair(nw: RefCounted) -> Array:
	var best := [0, 1]
	var bd := 0.0
	for a in WorldGen.settlements.size():
		for b in WorldGen.settlements.size():
			var d: float = nw.road_distance(a, b)
			if d < 1.0e8 and d > bd:
				bd = d
				best = [a, b]
	return best


func test_hunger_elsewhere_is_unknown_until_news_arrives() -> void:
	var hub := _mk()
	var nw: RefCounted = hub.mod("news")
	var p := _far_pair(nw)
	var here := int(p[0])
	var there := int(p[1])
	nw.post("harvest_failure", there, "The harvest failed.", 2.0, "", false, 10)
	assert_float(Knowledge.heard_hunger(nw, here, there, 10)).is_equal(0.0)    # day 0 of the news: nothing has travelled
	assert_float(Knowledge.heard_hunger(nw, here, there, 10 + 100)).is_equal(0.0)  # too old to matter
	var heard := 0.0
	for d in range(11, 70):
		heard = maxf(heard, Knowledge.heard_hunger(nw, here, there, d))
	assert_float(heard).is_greater(0.0)                                         # it arrives eventually
	assert_float(Knowledge.heard_hunger(nw, here, here, 12)).is_equal(-1.0)     # local hunger is felt, not heard
	assert_float(Knowledge.heard_hunger(null, here, there)).is_equal(0.0)


func test_enemy_weariness_needs_a_scout_report() -> void:
	var hub := _mk()
	var wi: RefCounted = hub.mod("war_intel")
	assert_str(Knowledge.enemy_weariness_label(wi, "i:player", 0.9)).is_equal("")
	assert_str(Knowledge.enemy_weariness_label(null, "i:player", 0.9)).is_equal("")
	assert_str(wi.viewer_owner()).is_equal("")
	wi.set_viewer("acct", 0, "ruler", "i:player", [0])
	assert_str(wi.viewer_owner()).is_equal("i:player")


func test_war_lines_hidden_until_war_news_reaches_the_town() -> void:
	var hub := _mk()
	var nw: RefCounted = hub.mod("news")
	var p := _far_pair(nw)
	var lines := ["War rages against Caldrenn."]
	assert_array(Knowledge.war_lines_heard(nw, int(p[0]), lines, 5)).is_empty()
	nw.post("war", int(p[0]), "War declared.", 3.0, "", true, 5)
	assert_array(Knowledge.war_lines_heard(nw, int(p[0]), lines, 8)).is_equal(lines)


func test_minds_move_fallback_uses_heard_hunger_not_truth() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/realm/minds.gd")
	assert_bool(src.contains("Knowledge.heard_hunger(nw, from, t, day)")).is_true()
	assert_bool(src.contains("_town_facts(t, day)")).is_false()


func test_npc_inspector_snapshot() -> void:
	var hub := _mk()
	var minds: RefCounted = hub.mod("minds")
	for day in range(1, 4):
		for k: String in ["registry", "minds"]:
			hub.mod(k).tick_day(day, CTX)
	var ch := ""
	for k: Variant in minds._m.keys():
		ch = String(k)
		break
	assert_str(ch).is_not_empty()
	var s: Dictionary = Inspector.snapshot(hub, ch)
	assert_bool(bool(s["ok"])).is_true()
	assert_bool(s.has("goal") and s.has("needs") and s.has("memories") and s.has("plan")).is_true()
	assert_str(Inspector.format(s)).contains(ch)
	assert_str(Inspector.format(Inspector.snapshot(null, "x"))).contains("no data")
	assert_object(minds).is_not_null()
