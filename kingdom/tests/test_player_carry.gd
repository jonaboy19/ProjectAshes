extends GdUnitTestSuite
## Player carry (WP-01, scripts/interaction/kinds/carryable.gd): the load sits in front of the chest, every kind has a size
## and a mass, carrying it turns its collision off and putting it down turns it back on.

const CarryK := preload("res://scripts/interaction/kinds/carryable.gd")


func test_hold_offset_is_in_front_of_the_chest() -> void:
	var off: Vector3 = CarryK.hold_offset(1.32, Vector3(0.5, 0.4, 0.4))
	assert_float(off.z).is_greater(0.3)
	assert_float(off.y).is_between(0.9, 1.3)
	assert_float(off.x).is_equal(0.0)


func test_kinds_have_size_and_mass() -> void:
	for k: String in CarryK.KINDS:
		var c: Node3D = auto_free(CarryK.new())
		c.set("kind", k)
		assert_float((c.call("size") as Vector3).length()).is_greater(0.2)
		assert_float(float(c.call("mass"))).is_greater(5.0)


func test_carried_load_has_no_collision() -> void:
	var c: Node3D = CarryK.spawn(get_tree().root, Vector3(0, 300, 0), "sack")
	var body: StaticBody3D = c.get("_body")
	assert_int(body.collision_layer).is_equal(1)
	var dummy: Node3D = auto_free(Node3D.new())
	c.call("set_carried", dummy)
	assert_int(body.collision_layer).is_equal(0)
	c.call("set_carried", null)
	assert_int(body.collision_layer).is_equal(1)
	c.free()
