extends GdUnitTestSuite
## READY_V1 C14, whole-state save soak: a late-game state is built through the real modules (a Village-tier player settlement with a 40+ piece
## grid, three followers one of them Down, a tamed wolf, an open raid on the settlement, the founded lordship and its title, Act 3 progress
## with the found-a-camp step done), written with the real SaveManager (JSON envelope, zstd when big), read back into a FRESH hub, and every
## module is deep-compared through realm_hub serialisation. Zero diffs; the file stays under 2 MB.
##
## Modules that are not on this branch yet (taming UI, live raids) are skipped and named in the report, not failed.

const Sim := preload("res://tools_qa/v1/settlement_sim.gd")
const Lordship := preload("res://scripts/sim/lordship.gd")
const FoundedLord := preload("res://scripts/sim/founded_lord.gd")
const SaveManager := preload("res://scripts/sim/save_manager.gd")
const StoryQuest := preload("res://scripts/region1/story_quest.gd")
const State := preload("res://scripts/region1/region1_state.gd")
const MAIN := "res://data/region1/quests/r1_main.json"
const TEST_DIR := "user://test_saves_v1_full/"

const MAX_BYTES := 2 * 1024 * 1024
const MAX_DIFFS := 12

var _mgr: SaveManager
var _state: Dictionary
var _skipped: Array[String] = []


func before_test() -> void:
	State.clear()
	_clear_dir()


func after_test() -> void:
	State.clear()
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


# ------------------------------------------------------------------------------------------ the late-game state

## {hub, gid, lord, titles, story, fid_down, wolf, day}
func _late_game() -> Dictionary:
	var hub: RefCounted = Sim.make_hub()
	var lord: RefCounted = Lordship.new()
	var titles := RATitles.new()
	FoundedLord.bind(hub, lord, titles)
	var res: Dictionary = Sim.run(100, 3, hub)
	var gid := int(res["gid"])
	assert_int(int(res["village_day"])).is_between(1, 100)      # a Village by day 100 (the C4 curve is 60-90)
	_grow_grid(hub, gid, 40)
	var fm: RefCounted = hub.mod("followers")
	# 3 followers, one Down (30 s timer running)
	var fids: Array = []
	for f: Dictionary in fm.list("present"):
		fids.append(String(f["id"]))
	assert_int(fids.size()).is_greater_equal(3)
	var down_fid := String(fids[0])
	assert_bool(fm.mark_down(down_fid, 30.0)).is_true()
	assert_bool(fm.is_down(down_fid)).is_true()
	# one tamed wolf (trust curve through the real attempts)
	var wolf_id := "wolf_soak"
	assert_bool(fm.start_taming(wolf_id, "wolf", false, "s0")).is_true()
	var tries := 0
	while String(fm.creature(wolf_id)["status"]) != "tamed" and tries < 20:
		fm.attempt_taming(wolf_id, "feed", 100 + tries)
		tries += 1
	assert_str(String(fm.creature(wolf_id)["status"])).is_equal("tamed")
	assert_bool(fm.assign_role(wolf_id, "guarding", "s0")).is_true()
	# an active raid on the settlement (the problem the live raid reads)
	var fnd: RefCounted = hub.mod("founding")
	var raid_open := _open_raid(fnd, 100)
	if not raid_open:
		_skipped.append("raid (no player founding record)")
	# Act 3 progress: the story quest with the ledger and found-a-camp steps done, the next one active
	var q := StoryQuest.new()
	q.setup(1)
	assert_bool(q.load_quest(MAIN)).is_true()
	for sid: String in ["a3_silverford", "a3_found_camp", "a3_council"]:
		if q.step(sid).is_empty():
			continue
		q.status[sid] = "done"
	if not q.step("a3_scar_front").is_empty():
		q.status["a3_scar_front"] = "active"
		q.progress["a3_scar_front"] = {"news": true}
	q.flags["a3_found_camp"] = true
	return {"hub": hub, "gid": gid, "lord": lord, "titles": titles, "story": q, "fid_down": down_fid, "wolf": wolf_id, "day": 100}


## Lays cottages and props around the grid until it holds `want` pieces (the C4 sim already placed ~20).
func _grow_grid(hub: RefCounted, gid: int, want: int) -> void:
	var kit: RefCounted = hub.mod("build_kit")
	var growth: RefCounted = hub.mod("growth")
	var offsets := [[-8, -8], [8, -8], [-8, 8], [8, 8], [-12, 0], [12, 0], [0, -12], [0, 12], [-12, -12], [12, 12], [-12, 12], [12, -12]]
	for o: Array in offsets:
		if int(growth.ledger(gid)["structures"]["pieces"]) >= want:
			break
		kit.place_blueprint(gid, "cottage", int(o[0]), int(o[1]))
	var props := ["table_bench", "meshy_banner_stand_iron_frame"]
	var k := 0
	while int(growth.ledger(gid)["structures"]["pieces"]) < want and k < 30:
		var kind: String = props[k % props.size()]
		var s: Dictionary = kit.snap_local(gid, kind, Vector3(-4.0 + float(k % 6) * 2.0, 0.0, -4.0 + float(k / 6) * 2.0), 0, 0)
		kit.place(gid, s, true)
		k += 1
	assert_int(int(growth.ledger(gid)["structures"]["pieces"])).is_greater_equal(want)


## Appends an open "raid" problem to the player's founding record. True if the record exists.
func _open_raid(fnd: RefCounted, day: int) -> bool:
	var ids: Array = fnd.call("ids", true)
	for id: int in ids:
		var f: Dictionary = fnd.call("get_founding", id)
		if String(f.get("who", "")) != "player":
			continue
		var raw: Dictionary = (fnd.get("_f") as Dictionary).get(id, {})
		if raw.is_empty():
			continue
		(raw["probs"] as Array).append(["raid", day, -1, 2])
		assert_bool(fnd.call("has_problem", id, "raid")).is_true()
		return true
	return false


func _whole(c: Dictionary) -> Dictionary:
	return {
		"realm": (c["hub"] as RefCounted).serialize(),
		"lordship": (c["lord"] as RefCounted).serialize(),
		"titles": (c["titles"] as RATitles).serialize(),
		"story": (c["story"] as StoryQuest)._save_state(),
		"world": {"day": c["day"], "time": 8.0},
		"game": {"gold": 270},
	}


# ------------------------------------------------------------------------------------------ the soak

func test_whole_late_game_state_round_trips_with_zero_diffs() -> void:
	var c: Dictionary = _late_game()
	var before: Dictionary = _whole(c)
	var slot := SaveManager.manual_id(3)
	_mgr = SaveManager.new()
	_mgr.root_dir = TEST_DIR
	_mgr.autosave_enabled = false
	_mgr.capture_thumbnails = false
	_mgr.snapshot_fn = func() -> Dictionary: return before.duplicate(true)
	_mgr.restore_fn = func(d: Dictionary) -> void: _state = (d as Dictionary).duplicate(true)
	add_child(_mgr)
	auto_free(_mgr)
	assert_bool(_mgr.save_slot(slot, "manual", false)).is_true()
	var bytes := FileAccess.get_file_as_bytes(_mgr.path_of(slot)).size()
	assert_int(bytes).is_less(MAX_BYTES)
	_state = {}
	assert_bool(_mgr.load_slot(slot)).is_true()
	assert_str(_mgr.last_error).is_equal("")

	# a FRESH world takes the loaded state back in
	var hub2: RefCounted = Sim.make_hub()
	var lord2: RefCounted = Lordship.new()
	var titles2 := RATitles.new()
	hub2.deserialize(_state["realm"])
	lord2.deserialize(_state["lordship"])
	titles2.deserialize(_state["titles"])
	var q2 := StoryQuest.new()
	q2.setup(1)
	assert_bool(q2.load_quest(MAIN)).is_true()
	q2._load_state(_state["story"])
	var after: Dictionary = {"realm": hub2.serialize(), "lordship": lord2.serialize(), "titles": titles2.serialize(), "story": q2._save_state(), "world": _state["world"], "game": _state["game"]}

	# deep compare, module by module (both sides through JSON: the file has no int/float distinction)
	var diffs: Array[String] = []
	var compared: Array[String] = []
	var b_json: Variant = JSON.parse_string(JSON.stringify(before))
	var a_json: Variant = JSON.parse_string(JSON.stringify(after))
	for top: String in (b_json as Dictionary):
		if top == "realm":
			for mod: String in (b_json["realm"] as Dictionary):
				compared.append("realm." + mod)
				_diff(b_json["realm"][mod], (a_json["realm"] as Dictionary).get(mod), "realm." + mod, diffs)
		else:
			compared.append(top)
			_diff(b_json[top], (a_json as Dictionary).get(top), top, diffs)
	print("[v1_full_save] %d bytes (%s), %d modules compared, skipped: %s" % [bytes, "zstd" if FileAccess.get_file_as_string(_mgr.path_of(slot)).contains('"enc":"zstd"') else "plain", compared.size(), str(_skipped)])
	if not diffs.is_empty():
		print("[v1_full_save] DIFFS:\n  " + "\n  ".join(diffs))
	assert_int(diffs.size()).is_equal(0)

	# what the soak was about actually survived (not just equal-because-empty)
	var fm2: RefCounted = hub2.mod("followers")
	assert_bool(fm2.is_down(String(c["fid_down"]))).is_true()
	assert_float(fm2.down_left(String(c["fid_down"]))).is_greater(0.0)
	assert_str(String(fm2.creature(String(c["wolf"]))["status"])).is_equal("tamed")
	assert_int(int(hub2.mod("growth").ledger(int(c["gid"]))["structures"]["pieces"])).is_greater_equal(40)
	assert_bool(lord2.is_lord_of(Lordship.founded_idx(int(c["gid"])))).is_true()
	assert_bool(titles2.has(FoundedLord.title_id(int(c["gid"])))).is_true()
	assert_bool(q2.is_done("a3_found_camp")).is_true()


## Deep compare; appends "path: before != after" lines (capped).
func _diff(a: Variant, b: Variant, path: String, out: Array[String]) -> void:
	if out.size() >= MAX_DIFFS:
		return
	if a is Dictionary and b is Dictionary:
		var da: Dictionary = a
		var db: Dictionary = b
		for k: Variant in da:
			if not db.has(k):
				out.append("%s.%s: missing after load" % [path, str(k)])
			else:
				_diff(da[k], db[k], "%s.%s" % [path, str(k)], out)
		for k: Variant in db:
			if not da.has(k):
				out.append("%s.%s: appeared after load" % [path, str(k)])
	elif a is Array and b is Array:
		var xa: Array = a
		var xb: Array = b
		if xa.size() != xb.size():
			out.append("%s: array size %d != %d" % [path, xa.size(), xb.size()])
			return
		for i in xa.size():
			_diff(xa[i], xb[i], "%s[%d]" % [path, i], out)
	elif typeof(a) != typeof(b) or a != b:
		if (a is float or a is int) and (b is float or b is int) and is_equal_approx(float(a), float(b)):
			return
		out.append("%s: %s != %s" % [path, str(a).left(60), str(b).left(60)])
