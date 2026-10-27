extends GdUnitTestSuite
## Live raids on the player's settlement: staged only near it, after the grace period, once per raid; band size; defend_raid closes it.

const PR := preload("res://scripts/realm/player_raids.gd")
const Unify := preload("res://tests/test_v1_settlement_unify.gd")


func _setup() -> Array:
	var u: Node = auto_free(Unify.new())
	var hub: RefCounted = u._mk()
	var spots: Array = u._spots(hub, 1)
	var r: Dictionary = hub.mod("build_kit").claim(u._w(spots[0]), "squat", "Newhold")
	var fd: RefCounted = hub.mod("founding")
	var fid: int = fd.ids(true)[0]
	var f: Dictionary = fd.get_founding(fid)
	(f["probs"] as Array).append(["raid", 30, -1, 2])
	return [fd, fid, spots[0]]


func test_band_size() -> void:
	assert_int(PR.band_size(0, 1)).is_equal(4)
	assert_int(PR.band_size(2, 3)).is_equal(10)
	assert_int(PR.band_size(9, 3)).is_equal(14)


func test_due_only_near_after_grace_and_once() -> void:
	var a := _setup()
	var fd: RefCounted = a[0]
	var at: Vector2 = a[2]
	var born := int(fd.get_founding(a[1])["born"])
	assert_dict(PR.due(fd, at, born + 3, {})).is_empty()            # grace
	assert_dict(PR.due(fd, at + Vector2(900, 0), born + 30, {})).is_empty()   # far away
	var r := PR.due(fd, at, born + 30, {})
	assert_int(int(r["fid"])).is_equal(int(a[1]))
	assert_int(int(r["count"])).is_equal(PR.band_size(0, 2))
	assert_dict(PR.due(fd, at, born + 30, {String(r["key"]): true})).is_empty()


func test_defend_raid_closes_the_problem() -> void:
	var a := _setup()
	var fd: RefCounted = a[0]
	assert_bool(fd.defend_raid(a[1])).is_true()
	var open := false
	for p: Dictionary in fd.problems(a[1]):
		open = open or String(p["kind"]) == "raid"
	assert_bool(open).is_false()
	assert_bool(fd.defend_raid(a[1])).is_false()
