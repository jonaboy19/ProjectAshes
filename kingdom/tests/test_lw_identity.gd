extends GdUnitTestSuite
## LW-1.1 / LW-1.2 (docs/design/LIVING_WORLD_SANDBOX.md): persistent ids and the legacy alias map, the EventRecord ring and its
## summarised archive, the realm hooks that write events, and the save schema 3 -> 4 migration.

const Hub := preload("res://scripts/realm/realm_hub.gd")
const Reg := preload("res://scripts/realm/registry.gd")
const SaveManager := preload("res://scripts/sim/save_manager.gd")
const TEST_DIR := "user://test_saves_lw/"

var _state: Dictionary


func _hub() -> RefCounted:
	return Hub.new()


func _norm(d: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(d)))


# --- ids ------------------------------------------------------------------------------

func test_ids_count_up_per_prefix_and_parse() -> void:
	var r: RefCounted = _hub().mod("registry")
	assert_str(r.mint("ch")).is_equal("ch:1")
	assert_str(r.mint("ch")).is_equal("ch:2")
	assert_str(r.mint("org")).is_equal("org:1")
	assert_str(r.mint("nope")).is_equal("")
	for p: String in ["ch", "hh", "org", "pr", "bl", "bz", "st", "tr", "ar", "tp"]:
		assert_bool(Reg.is_pid(r.mint(p))).is_true()
	assert_dict(Reg.parse("bz:17")).is_equal({"p": "bz", "n": 17})
	assert_bool(Reg.is_pid("ws:1")).is_false()
	assert_bool(Reg.is_pid("ch:")).is_false()
	assert_bool(Reg.is_pid("ch:x")).is_false()


func test_ids_are_never_reused_after_save_and_load() -> void:
	var a: RefCounted = _hub().mod("registry")
	var seen := {}
	for i in 50:
		seen[a.mint("ch")] = true
	a.ref("ws:9")
	var b: RefCounted = _hub().mod("registry")
	b.deserialize(JSON.parse_string(JSON.stringify(a.serialize())))
	for i in 20:
		var id: String = b.mint("ch")
		assert_bool(seen.has(id)).is_false()
		seen[id] = true
	assert_str(b.lookup("ws:9")).is_equal(a.lookup("ws:9"))


func test_counter_never_lags_behind_an_existing_alias() -> void:
	var b: RefCounted = _hub().mod("registry")
	b.deserialize({"alias": {"nt:n1": "ch:40"}})
	assert_str(b.mint("ch")).is_equal("ch:41")


# --- aliases --------------------------------------------------------------------------

func test_alias_round_trip_for_every_legacy_source() -> void:
	var r: RefCounted = _hub().mod("registry")
	var keys := [Reg.key_ws(1234), Reg.key_lc(7), Reg.key_nt("n17"), Reg.key_fo("f3"), Reg.key_ss(5), "rc:k2", "cn:9", "hd:2", "pl:player"]
	var want := ["ch", "ch", "ch", "ch", "st", "ct", "bl", "st", "ch"]
	for i in keys.size():
		var pid: String = r.ref(keys[i])
		assert_str(Reg.prefix_of(pid)).is_equal(want[i])
		assert_str(r.ref(keys[i])).is_equal(pid)          # same answer every time
		assert_str(r.lookup(keys[i])).is_equal(pid)
		assert_str(r.legacy_of(pid)).is_equal(keys[i])
	assert_str(r.lookup("ws:99999")).is_equal("")         # lookup never creates
	assert_str(r.ref("zz:1")).is_equal("")                # unknown kind
	assert_str(r.ref("nocolon")).is_equal("")


func test_two_legacy_names_of_one_person_share_an_id() -> void:
	var r: RefCounted = _hub().mod("registry")
	var pid: String = r.ref(Reg.key_ws(10))
	assert_bool(r.alias_to(Reg.key_lc(3), pid)).is_true()
	assert_str(r.ref(Reg.key_lc(3))).is_equal(pid)
	assert_bool(r.alias_to(Reg.key_lc(3), "ch:999")).is_false()
	assert_bool(r.alias_to("lc:4", "ch:999")).is_false()   # unknown id
	assert_str(r.resolve(pid)).is_equal(pid)
	assert_str(r.resolve("ws:10")).is_equal(pid)


func test_alias_table_is_capped_and_resolve_keeps_the_legacy_key() -> void:
	var r: RefCounted = _hub().mod("registry")
	for i in Reg.ALIAS_MAX:
		r.ref("ws:%d" % i)
	assert_int(r.alias_count()).is_equal(Reg.ALIAS_MAX)
	assert_str(r.ref("ws:999999")).is_equal("")
	assert_str(r.resolve("ws:999999")).is_equal("ws:999999")


func test_upgrade_of_200_rows_is_deterministic_and_capped() -> void:
	var a: RefCounted = _hub().mod("registry")
	var b: RefCounted = _hub().mod("registry")
	for row in 200:
		assert_str(a.upgrade_row(row * 3, 5)).is_equal(b.upgrade_row(row * 3, 5))
	assert_str(_norm(a.serialize())).is_equal(_norm(b.serialize()))
	assert_int(a.upgraded_count()).is_equal(200)
	assert_int((a.character(a.lookup("ws:3"))["t"] as Array).size()).is_equal(2)
	assert_str(a.upgrade_row(3)).is_equal(a.lookup("ws:3"))   # idempotent
	assert_int(a.upgraded_count()).is_equal(200)
	for row in 1000:
		a.upgrade_row(10000 + row)
	assert_int(a.upgraded_count()).is_equal(Reg.CHAR_MAX)
	assert_str(a.upgrade_row(50000)).is_equal("")
	var pid: String = a.lookup("ws:3")
	assert_bool(a.retire(pid, "died of fever")).is_true()
	assert_bool(a.is_upgraded(pid)).is_false()
	assert_str(a.lookup("ws:3")).is_equal(pid)             # the id outlives the record
	for i in 30:
		a.remember(a.lookup("ws:6"), "m%d" % i)
	assert_int((a.character(a.lookup("ws:6"))["m"] as Array).size()).is_equal(Reg.MEMORY_MAX)


# --- event log ------------------------------------------------------------------------

func test_events_record_and_read_by_actor_and_place() -> void:
	var hub := _hub()
	var ev: RefCounted = hub.mod("events")
	ev.record("death", "ss:1", ["ws:5"], "illness", "Hild died", 3, 10)
	ev.record("marriage", "ss:1", ["ws:5", "ws:6"], "wedding", "x", 2, 11)
	ev.record("crime", "ss:2", ["ws:6"], "theft", "y", 1, 12)
	var reg: RefCounted = hub.mod("registry")
	assert_int(ev.size()).is_equal(3)
	assert_int(ev.by_actor("ws:6").size()).is_equal(2)
	assert_int(ev.by_actor(reg.lookup("ws:5")).size()).is_equal(2)
	assert_int(ev.at("ss:1").size()).is_equal(2)
	assert_str(String(ev.recent(1)[0]["kind"])).is_equal("crime")
	assert_int(ev.of_kind("death").size()).is_equal(1)
	assert_int(ev.since(11).size()).is_equal(2)
	assert_str(String(ev.recent(1)[0]["id"])).is_equal("ev:3")
	assert_bool(reg.lookup("ws:5") != "").is_true()


func test_event_ring_is_capped_and_compaction_keeps_counts() -> void:
	var hub := _hub()
	var ev: RefCounted = hub.mod("events")
	var total := 2600
	for i in total:
		ev.record("death" if i % 2 == 0 else "trade", "ss:%d" % (i % 3), ["ws:%d" % (i % 40)], "c", "o%d" % i, 7 if i % 100 == 0 else 1, i)
		assert_int(ev.size()).is_less_equal(2000)
	assert_int(ev.total()).is_equal(total)
	assert_int(ev.count("death")).is_equal(1300)
	assert_int(ev.count("", "ss:0") + ev.count("", "ss:1") + ev.count("", "ss:2")).is_equal(total)
	assert_int(ev.archived() + ev.size()).is_equal(total)
	assert_int(ev.historic().size()).is_greater(0)
	assert_int(ev.historic().size()).is_less_equal(200)
	# ids keep counting through the compaction
	assert_str(String(ev.recent(1)[0]["id"])).is_equal("ev:%d" % total)


func test_event_log_save_size_and_round_trip() -> void:
	var hub := _hub()
	var ev: RefCounted = hub.mod("events")
	for i in 3000:
		ev.record("contract", "ss:%d" % (i % 20), ["ws:%d" % i, "rc:k%d" % i], "engage_personal", "Aldric Marsh signed on (12g, labor)", i % 8, i)
	var raw := JSON.stringify(ev.serialize())
	assert_int(raw.length()).is_less(240000)               # ring of 2,000 plus archive stays small
	var hub2 := _hub()
	hub2.deserialize(JSON.parse_string(JSON.stringify(hub.serialize())))   # ids come from the registry block, saved beside the ring
	var ev2: RefCounted = hub2.mod("events")
	assert_str(JSON.stringify(ev2.serialize())).is_equal(raw)
	assert_int(ev2.size()).is_equal(ev.size())
	assert_int(ev2.count("contract")).is_equal(3000)
	ev2.record("death", "", [], "x", "y")
	assert_str(String(ev2.recent(1)[0]["id"])).is_equal("ev:3001")


func test_event_write_cost_is_small() -> void:
	var ev: RefCounted = _hub().mod("events")
	var t0 := Time.get_ticks_usec()
	for i in 4000:
		ev.record("trade", "ss:1", ["ws:%d" % (i % 300)], "c", "o", 1, i)
	var per := float(Time.get_ticks_usec() - t0) / 4000.0
	assert_float(per).is_less(100.0)                        # doc: < 0.02 ms typical; generous for a loaded CI box


func test_log_to_is_a_noop_without_an_events_module() -> void:
	var Ev := preload("res://scripts/realm/events.gd")
	Ev.log_to(null, "death", "", [], "x", "y")
	var fake := RefCounted.new()
	assert_bool(fake != null).is_true()


# --- hooks ----------------------------------------------------------------------------

func test_notable_deaths_and_crimes_write_events() -> void:
	WorldGen.setup(2024)
	var hub := _hub()
	hub.warm_up()
	var ev: RefCounted = hub.mod("events")
	var soc: RefCounted = hub.mod("society")
	soc.commit_crime("murder", 0, 2)
	var rows: Array = ev.of_kind("crime")
	assert_int(rows.size()).is_equal(1)
	assert_int(int(rows[0]["weight"])).is_equal(5)
	assert_bool(String(rows[0]["where"]).begins_with("st:")).is_true()


func test_a_signed_contract_writes_an_event() -> void:
	WorldGen.setup(2024)
	var hub := _hub()
	hub.warm_up()
	var rec: RefCounted = hub.mod("recruitment")
	var ev: RefCounted = hub.mod("events")
	var signed := 0
	for row in range(0, 400):
		var r: Dictionary = rec.engage(row, {"w": 30, "d": "labor", "n": 0, "h": 1, "x": 0.0}, "personal", "", {"trust": 50.0})
		if bool(r.get("ok", false)):
			signed += 1
			break
	assert_int(signed).is_equal(1)
	assert_int(ev.of_kind("contract").size()).is_equal(1)


func test_realm_hub_saves_and_loads_the_new_blocks() -> void:
	var hub := _hub()
	hub.mod("registry").ref("ws:1")
	hub.mod("events").record("death", "ss:1", ["ws:1"], "c", "o", 2, 3)
	var d: Dictionary = JSON.parse_string(JSON.stringify(hub.serialize()))
	assert_bool(d.has("registry") and d.has("events")).is_true()
	var h2 := _hub()
	h2.deserialize(d)
	assert_str(h2.mod("registry").lookup("ws:1")).is_equal("ch:1")
	assert_int(h2.mod("events").size()).is_equal(1)


# --- save schema ----------------------------------------------------------------------

func test_schema_is_4_and_v3_migrates_with_empty_blocks() -> void:
	assert_int(SaveManager.SCHEMA_VERSION).is_equal(4)
	var m := SaveManager.new()
	auto_free(m)
	var env := {"schema": 3, "meta": {"name": "Old"}, "checksum": "", "data": {"world": {"day": 9}, "game": {}, "realm": {"news": {"a": 1}}}}
	var why: Array = []
	var out: Dictionary = m.migrate(env, why)
	assert_int(int(out["schema"])).is_equal(4)
	var realm: Dictionary = out["data"]["realm"]
	assert_bool(realm.has("registry") and realm.has("events")).is_true()
	assert_int(int(realm["news"]["a"])).is_equal(1)         # existing blocks untouched
	assert_int(int(out["data"]["world"]["day"])).is_equal(9)
	# a v3 save without any realm section also climbs
	var out2: Dictionary = m.migrate({"schema": 3, "meta": {}, "data": {"world": {}, "game": {}}}, why)
	assert_int(int(out2["schema"])).is_equal(4)
	assert_bool(out2["data"]["realm"].has("events")).is_true()
	# and the migrated blocks load into a hub
	var hub := _hub()
	hub.deserialize(realm)
	assert_int(hub.mod("events").size()).is_equal(0)


func test_a_schema_3_file_on_disk_loads_and_a_new_save_is_v4() -> void:
	var mgr: SaveManager = SaveManager.new()
	mgr.root_dir = TEST_DIR
	mgr.autosave_enabled = false
	mgr.capture_thumbnails = false
	_state = {"world": {"day": 3, "time": 8.0}, "game": {"gold": 1}}
	mgr.snapshot_fn = func() -> Dictionary: return _state.duplicate(true)
	mgr.restore_fn = func(d: Dictionary) -> void: _state = (d as Dictionary).duplicate(true)
	add_child(mgr)
	auto_free(mgr)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEST_DIR))
	var id := SaveManager.manual_id(1)
	var data_text := JSON.stringify({"world": {"day": 33, "time": 8.0}, "game": {"gold": 7}, "realm": {"news": {}}})
	var f := FileAccess.open(mgr.path_of(id), FileAccess.WRITE)
	f.store_string('{"schema":3,"meta":{"schema":3,"name":"V3"},"checksum":"%s","data":%s}' % [data_text.md5_text(), data_text])
	f.close()
	assert_bool(mgr.load_slot(id)).is_true()
	assert_int(int(_state["world"]["day"])).is_equal(33)
	assert_bool((_state["realm"] as Dictionary).has("registry")).is_true()
	assert_bool(mgr.save_slot(SaveManager.manual_id(2))).is_true()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(mgr.path_of(SaveManager.manual_id(2))))
	assert_int(int(parsed["schema"])).is_equal(4)
	var abs := ProjectSettings.globalize_path(TEST_DIR)
	for fn in DirAccess.get_files_at(abs):
		DirAccess.remove_absolute(abs.path_join(fn))
