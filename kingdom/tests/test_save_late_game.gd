extends GdUnitTestSuite
## WP-09 late-game save round-trip (READY_V1 M12). A headless game two in-game years old, with three followers, a founded settlement and a
## war on, is saved through SaveManager (zstd envelope) and loaded back; every section of Life.snapshot() (and so every realm module's
## serialize()) must come back identical, and the loaded game must go on from the same state as the one that never saved.

const SaveManager := preload("res://scripts/sim/save_manager.gd")
const LandClaim := preload("res://scripts/realm/land_claim.gd")
const HV := preload("res://scripts/world/hidden_valley.gd")
const TEST_DIR := "user://test_saves_late_game/"
const YEARS_DAYS := 730
const FULL_TICK_DAYS := 21         # days run through the real hourly path (queue, pump, drain); the rest of the span is closed-form catch_up

var _mgr: SaveManager


func before_test() -> void:
	_clear_dir()


func after_test() -> void:
	_clear_dir()


func _clear_dir() -> void:
	var abs := ProjectSettings.globalize_path(TEST_DIR)
	var d := DirAccess.open(abs)
	if d == null:
		return
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if not d.current_is_dir():
			d.remove(f)
		f = d.get_next()
	d.list_dir_end()
	DirAccess.remove_absolute(abs)


func _manager() -> SaveManager:
	var m := SaveManager.new()
	m.root_dir = TEST_DIR
	m.autosave_enabled = false
	m.capture_thumbnails = false
	m.snapshot_fn = func() -> Dictionary: return Life.snapshot()
	m.restore_fn = func(d: Dictionary) -> void: Life.restore(d)
	add_child(m)
	auto_free(m)
	return m


func _norm(d: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(d))


## Section keys whose JSON differs (the texts are megabytes: never hand them to assert_str).
func _differing(a: Dictionary, b: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var keys := {}
	for k in a:
		keys[k] = true
	for k in b:
		keys[k] = true
	var ks: Array = keys.keys()
	ks.sort()
	for k: String in ks:
		if JSON.stringify(a.get(k)).md5_text() != JSON.stringify(b.get(k)).md5_text():
			out.append(k)
	return out


## Paths (up to `limit`) where two JSON trees differ, for a readable failure.
func _paths(a: Variant, b: Variant, path := "", out: PackedStringArray = PackedStringArray(), limit := 12) -> PackedStringArray:
	if out.size() >= limit:
		return out
	if a is Dictionary and b is Dictionary:
		var keys := {}
		for k in a:
			keys[k] = true
		for k in b:
			keys[k] = true
		for k in keys:
			if not a.has(k) or not b.has(k):
				out.append("%s/%s (missing on one side)" % [path, str(k)])
			else:
				_paths(a[k], b[k], "%s/%s" % [path, str(k)], out, limit)
	elif a is Array and b is Array:
		if a.size() != b.size():
			out.append("%s (size %d vs %d)" % [path, a.size(), b.size()])
		else:
			for i in a.size():
				_paths(a[i], b[i], "%s[%d]" % [path, i], out, limit)
	elif typeof(a) != typeof(b) or a != b:
		out.append("%s (%s vs %s)" % [path, str(a).left(40), str(b).left(40)])
	return out


func _settle_spot() -> Vector2:
	var fd: RefCounted = Life.realm.mod("founding")
	var rng := RandomNumberGenerator.new()
	rng.seed = 91
	for _i in 4000:
		var s: Dictionary = WorldGen.settlements[rng.randi() % WorldGen.settlements.size()]
		var p: Vector2 = (s["pos"] as Vector2) + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(400.0, 1500.0)
		if absf(p.x) > 5500.0 or absf(p.y) > 5500.0 or LandClaim.block_reason(p) != "" or HV.in_valley(p) or HV.protected_ground(p):
			continue
		var ev: Dictionary = fd.evaluate_site(p)
		if float(ev["overall"]) >= 0.3 and float(ev["camp"]) >= 0.26:
			return p
	return Vector2.INF


func _advance_days(n: int) -> void:
	for _d in n:
		for _h in 24:
			WorldSim.advance_hours(1.0)
			Life.realm.drain()


## The late-game state: two years, three followers, a settlement of the player's, a war.
func _build_late_game() -> Dictionary:
	var info := {}
	var realm: RefCounted = Life.realm
	_advance_days(FULL_TICK_DAYS)
	var fl: RefCounted = realm.mod("followers")
	var ids: Array = []
	for occ: String in ["hunter", "healer", "smith"]:
		ids.append(fl.hire(occ if fl.OCCUPATIONS.has(occ) else String(fl.OCCUPATIONS.keys()[0]), "s0", true))
	info["followers"] = ids
	var spot := _settle_spot()
	info["spot"] = spot
	if spot != Vector2.INF:
		var fd: RefCounted = realm.mod("founding")
		var r: Dictionary = fd.begin(spot, "Ashfall", "player")
		info["founded"] = bool(r.get("ok", false))
		info["fid"] = int(r.get("fid", 0))
	var rest := YEARS_DAYS - FULL_TICK_DAYS
	WorldSim.day += rest
	realm.catch_up(rest, Life.call("_realm_ctx"))
	realm.drain()
	Life.war.add_tension("ongur_khanate", 80.0, "late-game test")
	Life.war.call("_declare_war", "ongur_khanate", WorldSim.day)
	info["war"] = Life.war.is_at_war()
	_advance_days(2)
	return info


func test_late_game_save_round_trips_every_module() -> void:
	var info := _build_late_game()
	assert_int(WorldSim.day).is_greater(YEARS_DAYS)
	assert_int((info["followers"] as Array).size()).is_equal(3)
	assert_bool(info["spot"] != Vector2.INF).override_failure_message("no founding site found on this seed").is_true()
	assert_bool(bool(info.get("founded", false))).is_true()
	assert_bool(bool(info["war"]) and Life.war.is_at_war()).is_true()
	_mgr = _manager()
	var id := SaveManager.manual_id(2)
	var before: Dictionary = _norm(Life.snapshot())
	assert_bool(_mgr.save_slot(id)).is_true()
	assert_bool(_mgr.load_slot(id)).is_true()
	assert_str(_mgr.last_error).is_equal("")
	var after: Dictionary = _norm(Life.snapshot())
	var diff := _differing(before, after)
	var detail := PackedStringArray()
	for k: String in diff:
		detail.append("%s: %s" % [k, ", ".join(_paths(before.get(k), after.get(k)))])
	assert_array(diff).override_failure_message("drifted sections after save/load:\n" + "\n".join(detail)).is_empty()
	# the war, the followers and the settlement survived as themselves, not just as equal bytes
	assert_bool(Life.war.is_at_war()).is_true()
	assert_int(Life.realm.mod("followers").serialize().size()).is_greater(0)
	assert_int((Life.realm.mod("founding").ids() as Array).size()).is_greater(0)


## A loaded late-game keeps running (ten more days) and a second save/load of that game is again lossless: nothing the load
## rebuilt (ints, floats, ordering) drifts on the way through the next save.
func test_loaded_late_game_runs_on_and_saves_again_losslessly() -> void:
	_build_late_game()
	_mgr = _manager()
	var id := SaveManager.manual_id(3)
	assert_bool(_mgr.save_slot(id)).is_true()
	assert_bool(_mgr.load_slot(id)).is_true()
	var day0 := int(WorldSim.day)
	_advance_days(10)
	assert_int(int(WorldSim.day)).is_equal(day0 + 10)
	var before: Dictionary = _norm(Life.snapshot())
	var id2 := SaveManager.manual_id(2)
	assert_bool(_mgr.save_slot(id2)).is_true()
	assert_bool(_mgr.load_slot(id2)).is_true()
	var after: Dictionary = _norm(Life.snapshot())
	var diff := _differing(before, after)
	var detail := PackedStringArray()
	for k: String in diff:
		detail.append("%s: %s" % [k, ", ".join(_paths(before.get(k), after.get(k)))])
	assert_array(diff).override_failure_message("second round trip drifted:\n" + "\n".join(detail)).is_empty()
