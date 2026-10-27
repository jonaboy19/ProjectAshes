extends GdUnitTestSuite
## A discovery vista freezes the player while it plays; whatever happens to the cutscene it must give the player back
## (the age-12 story freeze: the player stood with process_mode DISABLED for minutes).

const Vista := preload("res://scripts/cinematic/discovery_vista.gd")


func _vista_with_frozen() -> Array:
	var host: Node3D = auto_free(Node3D.new())
	get_tree().root.add_child(host)
	var frozen := Node.new()
	host.add_child(frozen)
	var v: Node = Vista.new()
	host.add_child(v)
	var s: Dictionary = Vista.shot(Vector3(0, 300, 0), Vector3(0, 301, 0), Vector3(0, 300, 5), Vector3(0, 300, 6), 1.0)
	v.call("play", {"shots": [s], "freeze": [frozen]})
	return [v, frozen]


func test_overrun_restores_the_frozen_player() -> void:
	var r := _vista_with_frozen()
	var v: Node = r[0]
	var frozen: Node = r[1]
	assert_int(frozen.process_mode).is_equal(Node.PROCESS_MODE_DISABLED)
	v.call("advance", 5.0)          # past the shot plus the 3 s grace
	v.call("_process", 0.016)
	assert_int(frozen.process_mode).is_not_equal(Node.PROCESS_MODE_DISABLED)
	assert_bool(bool(v.get("running"))).is_false()


func test_freeing_the_vista_restores_the_frozen_player() -> void:
	var r := _vista_with_frozen()
	var v: Node = r[0]
	var frozen: Node = r[1]
	v.get_parent().remove_child(v)
	assert_int(frozen.process_mode).is_not_equal(Node.PROCESS_MODE_DISABLED)
	v.free()
