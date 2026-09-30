extends GdUnitTestSuite
## Living world crowd tech: smart object claims / stand points / sessions, the prop grip frame,
## VAT custom-data packing and the LivingEvents bus.


func test_smart_object_claim_release() -> void:
	var so := SmartObjects.new()
	var id := so.add("bench", Transform3D.IDENTITY)
	assert_int(id).is_equal(0)
	var pick := so.find(Vector3(1, 0, 1), {"act": "rest", "hour": 10.0}, 20.0, 7)
	assert_array(pick).has_size(2)
	assert_bool(so.claim(pick[0], pick[1], 7)).is_true()
	assert_bool(so.claim(pick[0], pick[1], 8)).is_false()
	assert_int(so.occupancy(id)).is_equal(1)
	# the second seat is still free for person 8
	var p2 := so.find(Vector3(1, 0, 1), {"act": "rest", "hour": 10.0}, 20.0, 8)
	assert_int(p2[1]).is_not_equal(pick[1])
	so.release(7)
	assert_int(so.occupancy(id)).is_equal(0)


func test_smart_object_filters() -> void:
	var so := SmartObjects.new()
	so.add("anvil", Transform3D.IDENTITY)
	assert_array(so.find(Vector3.ZERO, {"act": "work", "job": "Farmer", "hour": 10.0})).is_empty()
	assert_array(so.find(Vector3.ZERO, {"act": "work", "job": 1, "hour": 10.0})).has_size(2)
	assert_array(so.find(Vector3.ZERO, {"act": "work", "job": "Blacksmith", "hour": 23.0})).is_empty()
	so.add("hopscotch", Transform3D(Basis(), Vector3(2, 0, 0)))
	assert_array(so.find(Vector3.ZERO, {"act": "play", "kid": false})).is_empty()
	assert_array(so.find(Vector3.ZERO, {"act": "play", "kid": true})).has_size(2)


func test_stand_faces_object_and_approach_is_behind() -> void:
	var so := SmartObjects.new()
	var yaw := deg_to_rad(90.0)
	var id := so.add("well", Transform3D(Basis(Vector3.UP, yaw), Vector3(10, 0, 5)))
	var sx := so.stand_xform(id, 0)
	# slot 0 stands 1.25 m in front (+Z of the object = world +X for yaw 90) and faces the well
	assert_vector(sx.origin).is_equal_approx(Vector3(11.25, 0, 5), Vector3(0.01, 0.01, 0.01))
	var fwd := sx.basis.z
	assert_float(fwd.dot((Vector3(10, 0, 5) - sx.origin).normalized())).is_greater(0.99)
	var ap := so.approach_point(id, 0)
	assert_float(ap.distance_to(Vector3(10, 0, 5))).is_greater(sx.origin.distance_to(Vector3(10, 0, 5)))


func test_session_runs_to_done_and_releases() -> void:
	var so := SmartObjects.new()
	var id := so.add("bench", Transform3D.IDENTITY)
	assert_bool(so.claim(id, 0, 3)).is_true()
	var s := so.session(3, id, 0)
	var pos := so.approach_point(id, 0)
	var out := s.update(0.1, pos, false)
	assert_int(s.phase).is_equal(SmartObjects.Session.ALIGN)
	pos = so.stand_xform(id, 0).origin
	for i in 400:
		out = s.update(0.5, pos, true)
		if s.phase == SmartObjects.Session.DONE:
			break
	assert_int(s.phase).is_equal(SmartObjects.Session.DONE)
	assert_int(so.occupancy(id)).is_equal(0)


func test_session_interrupt_plays_exit() -> void:
	var so := SmartObjects.new()
	var id := so.add("anvil", Transform3D.IDENTITY)
	so.claim(id, 0, 1)
	var s := so.session(1, id, 0)
	s.update(0.1, so.stand_xform(id, 0).origin, false)   # -> ALIGN
	s.update(0.1, so.stand_xform(id, 0).origin, false)   # -> ENTER
	assert_int(s.phase).is_equal(SmartObjects.Session.ENTER)
	s.interrupt()
	assert_int(s.phase).is_equal(SmartObjects.Session.EXIT)
	assert_str(s.clip).is_equal("Life_Smith_Hammer_Exit")


func test_grip_frame_is_orthonormal_and_in_the_fist() -> void:
	var model := Assets.mh_character("villager_man_a", 1.75, [], true)
	add_child(model)
	auto_free(model)
	var sk: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
	for side: String in ["r", "l"]:
		var t := LifeProps.grip_transform(sk, side, Vector3(0, 1, 0), Vector3(0, 0, 1))
		assert_float(absf(t.basis.determinant() - 1.0)).is_less(0.01)
		# fist centre 5-12 cm from the wrist
		assert_float(t.origin.length()).is_between(0.04, 0.14)


func test_vat_custom_packing() -> void:
	var a := VatAsset.new()
	a.clips = {"Walk": {"row": 37, "frames": 13, "loop": true, "length": 1.3}, "Wave": {"row": 50, "frames": 20, "loop": false, "length": 1.9}}
	var c := a.custom_for("Walk", 0.5, 1.1)
	assert_float(c.r).is_equal(37.0)
	var w := a.custom_for("Wave", 0.0)
	assert_float(w.g).is_less(0.0)


func test_living_events_nearest() -> void:
	LivingEvents.clear()
	LivingEvents.emit("clang", Vector3(0, 0, 0), 10.0, 5.0)
	LivingEvents.emit("shout", Vector3(100, 0, 0), 10.0, 5.0)
	var e := LivingEvents.nearest(Vector3(3, 0, 0))
	assert_str(String(e["kind"])).is_equal("clang")
	assert_dict(LivingEvents.nearest(Vector3(3, 0, 0), int(e["serial"]))).is_empty()
	assert_dict(LivingEvents.nearest(Vector3(50, 0, 0))).is_empty()


func test_ambience_is_stable_per_person() -> void:
	var a := LifeAmbience.new(42)
	var b := LifeAmbience.new(42)
	var c := LifeAmbience.new(43)
	assert_float(a.walk_speed).is_equal(b.walk_speed)
	assert_float(a.anim_rate).is_between(0.93, 1.07)
	assert_bool(a.walk_speed != c.walk_speed or a.anim_rate != c.anim_rate).is_true()
