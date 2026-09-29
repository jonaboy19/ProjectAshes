extends GdUnitTestSuite
## Realm tab (scripts/ui/gamemenu/tab_realm.gd): every sub-view builds from a fresh realm hub,
## the War Room shows known intel only, orders / summons / emergency responses work, and
## an absent realm degrades to "Nothing known yet.".

const Hub := preload("res://scripts/realm/realm_hub.gd")
const TabRealm := preload("res://scripts/ui/gamemenu/tab_realm.gd")
const ENEMY := "ongur_khanate"


class NoRealm extends RefCounted:
	func mod(_n: String) -> RefCounted:
		return null


func _hub() -> RefCounted:
	WorldGen.setup(1066)
	var h: RefCounted = Hub.new()
	var ctx := {"player_pos": Vector2.ZERO, "season": "spring", "at_war": false}
	for day in range(1, 4):
		for hour in [5, 6, 7]:
			h.on_hour(hour, day, ctx)
			h.drain()
	return h


func _tab(h: RefCounted) -> Control:
	var t: Control = TabRealm.new()
	t.set("realm_override", h)
	add_child(auto_free(t))
	t.call("build")
	t.call("on_show")
	return t


func _texts(n: Node, out: Array = []) -> Array:
	if n is Label:
		out.append((n as Label).text)
	elif n is Button:
		out.append((n as Button).text)
	for c in n.get_children():
		_texts(c, out)
	return out


func _joined(t: Control, view: String) -> String:
	t.call("set_view", view)
	return "\n".join(PackedStringArray(_texts((t.get("_boxes") as Dictionary)[view])))


func _far_node(cm: RefCounted) -> int:
	var best := 1
	var bl := -1.0
	for i in range(1, WorldGen.settlements.size()):
		var p: Array = cm.call("path", 0, i)
		if not p.is_empty() and float(cm.call("path_length", p)) > bl:
			bl = cm.call("path_length", p)
			best = i
	return best


func test_every_view_builds_on_a_fresh_hub() -> void:
	var h := _hub()
	var t := _tab(h)
	for v: Array in TabRealm.VIEWS:
		var s := _joined(t, String(v[0]))
		assert_int(((t.get("_boxes") as Dictionary)[v[0]] as Node).get_child_count()).is_greater(0)
		assert_str(s).is_not_empty()
	t.call("on_hide")


func test_war_room_shows_known_intel_only() -> void:
	var h := _hub()
	var cm: RefCounted = h.mod("campaign")
	cm.call("set_hq", 0)
	cm.call("tick_day", 4, {})
	var far := _far_node(cm)
	var mine: int = cm.call("spawn_army", "player", 0, 300, "loyal")
	var foe: int = cm.call("spawn_army", ENEMY, far, 500, "aggressive")
	var t := _tab(h)
	var s := _joined(t, "war")
	for e: Dictionary in t.call("overlay_entries"):
		assert_bool(e.get("army_id", -1) == foe).is_false()
	assert_bool(s.contains("Unknown force")).is_false()
	assert_bool(s.contains("Your Armies")).is_true()
	assert_int((t.call("intel_forces") as Array).size()).is_greater(0)   # our own report
	# Feed intel: now the enemy shows, with age and estimate labels.
	assert_bool(cm.call("add_intel", foe, "scout", 0.3, 0.8)).is_true()
	var seen := false
	for e: Dictionary in t.call("overlay_entries"):
		if e.get("army_id", -1) == foe:
			seen = true
			assert_int(int(e["est_max"])).is_greater_equal(int(e["est_min"]))
	assert_bool(seen).is_true()
	t.call("_rebuild", "war", true)
	s = "\n".join(PackedStringArray(_texts((t.get("_boxes") as Dictionary)["war"])))
	assert_bool(s.contains("Unknown force")).is_true()
	assert_bool(s.contains("seen")).is_true()
	assert_bool(s.contains("est.")).is_true()
	assert_int(mine).is_greater(0)


func test_orders_are_sent_by_courier_and_target_comes_from_a_tap() -> void:
	var h := _hub()
	var cm: RefCounted = h.mod("campaign")
	cm.call("set_hq", 0)
	cm.call("tick_day", 4, {})
	var id: int = cm.call("spawn_army", "player", 0, 300, "loyal")
	var t := _tab(h)
	t.call("set_view", "war")
	t.set("sel_army", id)
	t.call("map_tapped", cm.call("node_pos", 1))
	assert_int(int(t.get("sel_target"))).is_equal(1)
	t.set("sel_kind", "attack")
	var c: Dictionary = t.call("_send_order")
	assert_bool(c.is_empty()).is_false()
	assert_int((cm.call("couriers") as Array).size()).is_equal(1)
	var s := "\n".join(PackedStringArray(_texts((t.get("_boxes") as Dictionary)["war"])))
	assert_bool(s.contains("Arrives in about")).is_true()
	t.call("_follow", 0)
	assert_int((cm.call("couriers") as Array).size()).is_greater(1)


func test_land_emergency_respond_deducts_gold() -> void:
	var h := _hub()
	var se: RefCounted = h.mod("settlements")
	se.call("raid_aftermath", 0, 0.5)
	assert_int((se.call("emergencies") as Array).size()).is_greater(0)
	var t := _tab(h)
	var s := _joined(t, "land")
	assert_bool(s.contains("Respond (")).is_true()
	assert_bool(s.contains("Regions")).is_true()
	var e: Dictionary = (se.call("emergencies") as Array)[0]
	var cost := int(e["cost"]) - int(e["paid"])
	Game.gold = cost + 10
	t.call("_respond", int(e["id"]), cost)
	assert_int(Game.gold).is_equal(10)


func test_followers_summon_shows_answer() -> void:
	var h := _hub()
	var fo: RefCounted = h.mod("followers")
	var fid: String = fo.call("hire", "mercenary", "s1")
	var t := _tab(h)
	var s := _joined(t, "followers")
	assert_bool(s.contains("Summon")).is_true()
	t.call("_summon", fid)
	assert_bool((t.get("_msgs") as Dictionary).has(fid)).is_true()
	assert_str(String((t.get("_msgs") as Dictionary)[fid])).is_not_empty()


func test_diplomacy_lists_factions_and_paths() -> void:
	var t := _tab(_hub())
	var s := _joined(t, "diplomacy")
	assert_bool(s.contains("Trust") or s.contains(TabRealm.EMPTY)).is_true()
	assert_bool(s.contains("Paths to the Crown")).is_true()


func test_absent_realm_shows_nothing_known() -> void:
	var t := _tab(NoRealm.new())
	for v: Array in TabRealm.VIEWS:
		var s := _joined(t, String(v[0]))
		assert_bool(s.contains("empty") or s.contains(TabRealm.EMPTY)).is_true()
