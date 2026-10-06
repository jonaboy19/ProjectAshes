extends GdUnitTestSuite
## Regression: the hint pill drew inside the location banner (Coldharbor, Eastmere, Greywatch). Two hint views live in the
## HUD (the tutorial bridge's and the realm hints'); an idle one used to report height 0 under the shared "hint" id every
## frame and erase the live pill's lane slot, so the banner (stacked under the hint) was placed over it.

const HudLane := preload("res://scripts/ui/hud_lane.gd")
const PromptView := preload("res://scripts/region1/tutorial_prompt_view.gd")


func _view(host: Control) -> Control:
	var v: Control = PromptView.new()
	host.add_child(v)
	return v


func _host(size: Vector2i) -> Control:
	var vp := SubViewport.new()
	vp.size = size
	add_child(vp)
	auto_free(vp)
	var host := Control.new()
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	vp.add_child(host)
	return host


func _pill_rect(v: Control) -> Rect2:
	var pill: Control = v.get("_pill")
	return Rect2(pill.position, pill.get_combined_minimum_size())


func _banner_top(k: float) -> float:
	return HudLane.y_for("banner", HudLane.BANNER_Y * k)


func test_an_idle_hint_view_does_not_erase_the_live_pills_lane_slot() -> void:
	HudLane.reset()
	var host := _host(Vector2i(1280, 720))
	var live := _view(host)
	var idle := _view(host)                       # added last: processes after `live`
	# `idle` showed a hint earlier and has faded out.
	idle.call("show_prompt", &"old", {"text_en": "Old hint", "plain": true, "anchor": "center", "touch": ""})
	idle.call("hide_prompt", &"old", &"done")
	for i in 5:
		idle.call("_process", 0.5)
	live.call("show_prompt", &"yard", {"text_en": "Press the cart to deliver", "plain": true, "anchor": "center", "touch": ""})
	for i in 3:
		live.call("_process", 0.1)
		idle.call("_process", 0.1)
	var pill := _pill_rect(live)
	assert_float(pill.size.y).is_greater(10.0)
	assert_float(_banner_top(1.0)).is_greater_equal(pill.end.y + HudLane.GAP - 0.01)   # banner sits under the pill
	HudLane.reset()


func test_banner_clears_the_hint_at_phone_and_desktop_sizes_for_both_hint_kinds() -> void:
	for size: Vector2i in [Vector2i(1280, 720), Vector2i(2400, 1080), Vector2i(720, 1280)]:
		for plain: bool in [true, false]:
			HudLane.reset()
			var host := _host(size)
			var live := _view(host)
			var idle := _view(host)
			idle.call("show_prompt", &"a", {"text_en": "x", "plain": true, "anchor": "center", "touch": ""})
			idle.call("hide_prompt", &"a", &"done")
			for i in 5:
				idle.call("_process", 0.5)
			live.call("show_prompt", &"b", {"text_en": "Walk to the glowing yard", "plain": plain, "anchor": "center", "touch": "tap"})
			for i in 3:
				live.call("_process", 0.1)
				idle.call("_process", 0.1)
			var k := clampf(float(size.x) / 1280.0, 0.75, 1.4)
			var pill := _pill_rect(live)
			assert_float(_banner_top(k)).is_greater_equal(pill.end.y + HudLane.GAP - 0.01)
	HudLane.reset()


func test_a_view_that_leaves_the_tree_frees_its_slot() -> void:
	HudLane.reset()
	var host := _host(Vector2i(1280, 720))
	var v := _view(host)
	v.call("show_prompt", &"b", {"text_en": "Hello there", "plain": true, "anchor": "center", "touch": ""})
	v.call("_process", 0.1)
	assert_float(HudLane.bottom_of("hint")).is_greater(0.0)
	host.remove_child(v)
	v.queue_free()
	assert_float(HudLane.bottom_of("hint")).is_equal(-INF)
	HudLane.reset()


func test_lane_owners_clear_only_their_own_entry() -> void:
	HudLane.reset()
	HudLane.report("hint", 80.0, 40.0, 1)
	HudLane.report("hint", 0.0, 0.0, 2)
	assert_float(HudLane.y_for("banner", 58.0)).is_equal(80.0 + 40.0 + HudLane.GAP)
	HudLane.report("hint", 0.0, 0.0, 1)
	assert_float(HudLane.y_for("banner", 58.0)).is_equal(58.0)
	HudLane.reset()
