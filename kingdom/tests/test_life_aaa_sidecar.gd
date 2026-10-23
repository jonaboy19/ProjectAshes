extends GdUnitTestSuite
## UAL_Life_AAA.glb sidecar: the 3 reviewed sit clips are in LifeLibrary with a category and the stool enter / exit pair.


func test_sit_idle_has_category_enter_and_exit() -> void:
	var i := LifeLibrary.info("Life_AAA_Sit_Idle")
	assert_str(String(i.get("category", ""))).is_equal("rest/sit")
	assert_bool(bool(i.get("loop", false))).is_true()
	assert_str(String(i["enter"])).is_equal("Life_Mocap_Sit_Stool_Enter")
	assert_str(String(i["exit"])).is_equal("Life_Mocap_Sit_Stool_Exit")
	assert_bool(LifeLibrary.info(String(i["enter"])).is_empty()).is_false()      # the pair exists


func test_all_three_sit_clips_are_listed() -> void:
	var sits := LifeLibrary.clips_in("rest/sit")
	for n in ["Life_AAA_Sit_Idle", "Life_AAA_Sit_LegSwing", "Life_AAA_Sit_Ponder"]:
		assert_bool(sits.has(n)).is_true()


func test_life_clips_are_not_in_the_shared_library() -> void:
	var lib: AnimationLibrary = Assets._ual_for(NodePath("Probe/Skeleton3D"))
	assert_bool(lib.has_animation("Life_AAA_Sit_Idle")).is_false()
