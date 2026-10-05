extends GdUnitTestSuite
## Alert sharing (scripts/population/alert_net.gd): an alarmed guard's shout reaches nearby guards (SEARCHING at the last
## known position, alert x0.6, no chain), hearing is occluded by walls, citizens are rattled and hide, each event id is
## handled once, settlement guard_alert -> lockdown (TownMood + micro_events shutters), and the alert glyph picker.

const AlertNet := preload("res://scripts/population/alert_net.gd")
const Perception := preload("res://scripts/population/perception.gd")
const NpcWorld := preload("res://scripts/population/npc_world.gd")
const Search := preload("res://scripts/population/search.gd")
const TownMood := preload("res://scripts/population/town_mood.gd")
const MicroEvents := preload("res://scripts/population/micro_events.gd")
const AlertGlyphs := preload("res://scripts/ui/alert_glyphs.gd")
const Schedule := preload("res://scripts/population/schedule.gd")
const Cls := Perception.Cls


## A StreetGraph stand-in: everything with x > 100 is "inside a building".
class FakeGraph extends RefCounted:
	func inside(p: Vector2, _r := 0.0) -> bool:
		return p.x > 100.0


func before_test() -> void:
	NpcWorld.reset()
	Perception.reset()
	AlertNet.reset()
	TownMood.reset()


func _listener(person: int, pos: Vector2, guard: bool) -> Dictionary:
	Perception.bind(person, 1.0, guard)
	return {"person": person, "pos": pos, "guard": guard}


func _shout(listeners: Array, event_id := 1, now := 10000, graph: RefCounted = null) -> Dictionary:
	Perception.bind(1, 1.2, true)
	return AlertNet.shout(1, Vector2.ZERO, Vector2(5, 5), 20.0, event_id, 0, now, listeners, graph)


func test_call_for_help_incident_kind_is_the_one_alert_net_files() -> void:
	assert_int(NpcWorld.Kind.CALL_FOR_HELP).is_equal(7)
	_shout([])
	var found := false
	for i in NpcWorld.SLOTS:
		if NpcWorld.incident_alive(i) and NpcWorld.incident_kind(i) == NpcWorld.Kind.CALL_FOR_HELP:
			found = true
	assert_bool(found).is_true()


# ---------------------------------------------------------------- who is told, and what they do
func test_nearby_guards_switch_to_searching_at_the_last_known_position() -> void:
	var near := _listener(10, Vector2(12, 0), true)
	var far := _listener(11, Vector2(90, 0), true)
	var res := _shout([near, far])
	assert_bool(res["shouted"]).is_true()
	assert_array(res["told"]).is_equal([10])
	var s := Perception.slot_of(10)
	assert_int(Perception.class_of(s)).is_equal(Cls.SEARCHING)
	assert_vector(Perception.point_of(s)).is_equal(Vector2(5, 5))
	assert_int(Perception.class_of(Perception.slot_of(11))).is_equal(Cls.CALM)


func test_telling_degrades_alert_so_a_relay_never_reaches_alarmed_and_cannot_chain() -> void:
	var g := _listener(10, Vector2(12, 0), true)
	_shout([g])
	var a := Perception.alert[Perception.slot_of(10)]
	assert_float(a).is_less(Perception.T_ALARMED)
	assert_float(a).is_greater_equal(Perception.T_SEARCHING)
	assert_float(a).is_less_equal(20.0 * AlertNet.TELL_DEGRADE + 0.6)
	# only ALARMED guards shout (villager.gd), so the searcher does not pass it on
	assert_int(Perception.class_of(Perception.slot_of(10))).is_not_equal(Cls.ALARMED)


func test_citizens_are_rattled_not_hunting_and_get_the_hide_callback() -> void:
	var c := _listener(20, Vector2(8, 0), false)
	var res := _shout([c])
	assert_int(res["citizens"]).is_equal(1)
	assert_int(res["guards"]).is_equal(0)
	var s := Perception.slot_of(20)
	assert_int(Perception.class_of(s)).is_equal(Cls.SUSPICIOUS)
	assert_float(Perception.alert[s]).is_less_equal(AlertNet.CIVILIAN_CAP + 0.01)


func test_each_event_id_is_handled_once() -> void:
	var g := _listener(10, Vector2(12, 0), true)
	_shout([g], 5, 10000)
	var s := Perception.slot_of(10)
	var a1 := Perception.alert[s]
	# the same event again after the shout cooldown: already known, no re-reaction
	var res2 := _shout([g], 5, 10000 + AlertNet.SHOUT_COOLDOWN_MS + 100)
	assert_array(res2["told"]).is_empty()
	assert_float(Perception.alert[s]).is_equal_approx(a1, 0.001)
	# a NEW event id is news
	var res3 := _shout([g], 6, 10000 + 2 * AlertNet.SHOUT_COOLDOWN_MS + 200)
	assert_array(res3["told"]).is_equal([10])


func test_shout_cooldown_per_caller() -> void:
	var g := _listener(10, Vector2(12, 0), true)
	assert_bool(_shout([g], 1, 10000)["shouted"]).is_true()
	assert_bool(AlertNet.can_shout(1, 10000 + AlertNet.SHOUT_COOLDOWN_MS - 1)).is_false()
	assert_bool(_shout([g], 2, 10000 + 100)["shouted"]).is_false()
	assert_bool(AlertNet.can_shout(1, 10000 + AlertNet.SHOUT_COOLDOWN_MS)).is_true()


# ---------------------------------------------------------------- hearing occlusion
func test_walls_shrink_the_shout_radius_in_the_usual_class_order() -> void:
	var graph := FakeGraph.new()
	var open := AlertNet.hearing_radius(null, Vector2.ZERO, Vector2(10, 0))
	var through_wall := AlertNet.hearing_radius(graph, Vector2.ZERO, Vector2(110, 0))     # listener inside a building
	assert_float(open).is_equal(AlertNet.SHOUT_RADIUS)
	assert_float(through_wall).is_equal_approx(AlertNet.SHOUT_RADIUS * Perception.OCC_MULT[Perception.Occ.OTHER_BUILDING], 0.001)
	assert_float(through_wall).is_less(open)
	# the same 11 m: carried in the open, stopped by a wall (6.4 m); 6 m still gets through
	var in_building := {"person": 33, "pos": Vector2(101, 0), "guard": true}          # x > 100: inside
	assert_int(AlertNet.reached(Vector2(90, 0), [in_building], 1, null).size()).is_equal(1)     # no graph: open air
	assert_int(AlertNet.reached(Vector2(90, 0), [in_building], 1, graph).size()).is_equal(0)
	assert_int(AlertNet.reached(Vector2(95, 0), [in_building], 1, graph).size()).is_equal(1)
	# beyond the open-air radius nobody hears it
	assert_int(AlertNet.reached(Vector2.ZERO, [{"person": 35, "pos": Vector2(40, 0), "guard": true}], 1).size()).is_equal(0)


func test_the_caller_does_not_hear_itself() -> void:
	var me := {"person": 1, "pos": Vector2(1, 0), "guard": true}
	assert_int(AlertNet.reached(Vector2.ZERO, [me], 1).size()).is_equal(0)


# ---------------------------------------------------------------- guard_alert, lockdown, shops
func test_guard_alert_levels_decay_and_lockdown() -> void:
	assert_int(AlertNet.level(0, 0)).is_equal(0)
	AlertNet.raise(0, 1000)
	assert_int(AlertNet.level(0, 1000)).is_equal(1)
	assert_bool(AlertNet.lockdown(0, 1000)).is_false()
	AlertNet.raise(0, 2000)
	assert_int(AlertNet.level(0, 2000)).is_equal(2)
	assert_bool(AlertNet.lockdown(0, 2000)).is_true()
	AlertNet.raise(0, 3000)
	AlertNet.raise(0, 3100)
	assert_int(AlertNet.level(0, 3100)).is_equal(AlertNet.MAX_LEVEL)
	# one level falls per DECAY_MS without news
	assert_int(AlertNet.level(0, 3100 + AlertNet.DECAY_MS)).is_equal(2)
	assert_bool(AlertNet.lockdown(0, 3100 + AlertNet.DECAY_MS)).is_true()
	assert_bool(AlertNet.lockdown(0, 3100 + 2 * AlertNet.DECAY_MS)).is_false()
	assert_bool(AlertNet.post_lockdown(0, 3100 + 2 * AlertNet.DECAY_MS + 1000)).is_true()
	assert_bool(AlertNet.post_lockdown(0, 3100 + 2 * AlertNet.DECAY_MS + AlertNet.POST_LOCKDOWN_MS + 1000)).is_false()
	assert_int(AlertNet.level(0, 10000000)).is_equal(0)
	assert_int(AlertNet.level(5, 0)).is_equal(0)                 # another town is unaffected


func test_two_shouts_lock_the_town_down_and_mood_and_shutters_follow() -> void:
	var g := _listener(10, Vector2(12, 0), true)
	var now := Time.get_ticks_msec()
	Perception.bind(1, 1.2, true)
	AlertNet.shout(1, Vector2.ZERO, Vector2(5, 5), 20.0, 1, 0, now, [g])
	assert_bool(AlertNet.lockdown(0, now)).is_false()
	assert_bool(bool(TownMood.read(0)["lockdown"])).is_false()
	AlertNet.shout(1, Vector2.ZERO, Vector2(5, 5), 20.0, 2, 0, now + AlertNet.SHOUT_COOLDOWN_MS + 1, [g])
	assert_bool(AlertNet.lockdown(0, now + AlertNet.SHOUT_COOLDOWN_MS + 1)).is_true()
	# TownMood: lockdown flag and the curfew schedule flag (people go home)
	var m := TownMood.read(0)
	assert_bool(bool(m["lockdown"])).is_true()
	assert_int(int(m["flags"]) & Schedule.F_CURFEW).is_not_equal(0)
	# micro_events: the shutters scene is eligible only during the lockdown, the reopen scene only after it
	var ctx := MicroEvents.make_context(13.0, 3, "market", false, m)
	assert_bool(ctx["lockdown"]).is_true()
	assert_float(MicroEvents.weight_of(MicroEvents.entry_of("lockdown_shutters"), ctx)).is_greater(0.0)
	assert_float(MicroEvents.weight_of(MicroEvents.entry_of("lockdown_reopen"), ctx)).is_equal(0.0)
	var calm := MicroEvents.make_context(13.0, 3, "market", false, {}, "town", {"shutters_down": true, "post_lockdown": true})
	assert_float(MicroEvents.weight_of(MicroEvents.entry_of("lockdown_shutters"), calm)).is_equal(0.0)
	assert_float(MicroEvents.weight_of(MicroEvents.entry_of("lockdown_reopen"), calm)).is_greater(0.0)
	var shut_no_lock := MicroEvents.make_context(13.0, 3, "market", false, {}, "town", {"shutters_down": true})
	assert_float(MicroEvents.weight_of(MicroEvents.entry_of("lockdown_reopen"), shut_no_lock)).is_equal(0.0)


func test_shout_opens_one_search_for_the_told_guards() -> void:
	var g1 := _listener(10, Vector2(12, 0), true)
	var g2 := _listener(11, Vector2(14, 3), true)
	_shout([g1, g2], 42)
	assert_int(Search.active_count(Time.get_ticks_msec())).is_equal(1)
	assert_int(Search.begin(Vector2(5, 5), 0, Time.get_ticks_msec(), 42)).is_equal(Search.searches[0]["id"])


# ---------------------------------------------------------------- alert glyphs
func test_glyph_look_by_class() -> void:
	assert_bool(AlertGlyphs.glyph_for(Cls.CALM).is_empty()).is_true()
	assert_str(AlertGlyphs.glyph_for(Cls.NOTICE)["glyph"]).is_equal("?")
	assert_str(AlertGlyphs.glyph_for(Cls.SUSPICIOUS)["glyph"]).is_equal("?")
	assert_str(AlertGlyphs.glyph_for(Cls.SEARCHING)["glyph"]).is_equal("?")
	assert_str(AlertGlyphs.glyph_for(Cls.ALARMED)["glyph"]).is_equal("!")
	assert_float(AlertGlyphs.glyph_for(Cls.ALARMED)["scale"]).is_greater(AlertGlyphs.glyph_for(Cls.NOTICE)["scale"])
	assert_bool(AlertGlyphs.glyph_for(Cls.NOTICE)["color"] != AlertGlyphs.glyph_for(Cls.ALARMED)["color"]).is_true()


func test_glyphs_are_capped_hidden_beyond_25m_and_prefer_the_most_alert() -> void:
	var rows: Array = []
	for i in 10:
		rows.append([3.0 + float(i) * 2.0, Cls.NOTICE + (i % 3), 100 + i])
	rows.append([26.0, Cls.ALARMED, 200])             # beyond 25 m: never
	rows.append([4.0, Cls.CALM, 201])                  # calm: never
	var chosen := AlertGlyphs.pick(rows)
	assert_int(chosen.size()).is_equal(AlertGlyphs.MAX_GLYPHS)
	for r: Array in chosen:
		assert_int(int(r[2])).is_not_equal(200)
		assert_int(int(r[2])).is_not_equal(201)
		assert_float(float(r[0])).is_less_equal(AlertGlyphs.SHOW_RANGE)
	assert_int(int(chosen[0][1])).is_equal(Cls.SEARCHING)         # most alert first
	assert_int(AlertGlyphs.pick([[AlertGlyphs.SHOW_RANGE, Cls.NOTICE, 1]]).size()).is_equal(1)
	assert_int(AlertGlyphs.pick([[AlertGlyphs.SHOW_RANGE + 0.1, Cls.NOTICE, 1]]).size()).is_equal(0)


func test_one_shared_atlas_for_every_sprite() -> void:
	var a := AlertGlyphs.atlas()
	assert_object(a).is_not_null()
	assert_object(AlertGlyphs.atlas()).is_same(a)
	assert_int(a.get_width()).is_equal(AlertGlyphs.CELL * 2)
	var node: Node = auto_free(AlertGlyphs.new())
	var s1: Sprite3D = node._make_sprite()
	var s2: Sprite3D = node._make_sprite()
	auto_free(s1)
	auto_free(s2)
	assert_object(s1.texture).is_same(s2.texture)
	assert_bool(s1.billboard == BaseMaterial3D.BILLBOARD_ENABLED and s1.shaded == false).is_true()
	assert_float(s1.visibility_range_end).is_less_equal(AlertGlyphs.SHOW_RANGE + 2.1)
	# the atlas really has pixels in both cells
	var img := a.get_image()
	var lit := [0, 0]
	for y in AlertGlyphs.CELL:
		for x in AlertGlyphs.CELL * 2:
			if img.get_pixel(x, y).a > 0.5:
				lit[x / AlertGlyphs.CELL] += 1
	assert_int(lit[0]).is_greater(20)
	assert_int(lit[1]).is_greater(20)
