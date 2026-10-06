extends GdUnitTestSuite
## CPU pass 2026-10-06 (cloud lane: script cost only, nothing the player sees): the tutorial bridge builds its context at a
## fixed rate and goes idle when nothing is left to teach, the prompt view sleeps while nothing is shown, WorldSim's far loop
## is paced by time instead of burning its budget every frame, and the perf probe is free while off.

const Bridge := preload("res://scripts/region1/tutorial_game_bridge.gd")
const Director := preload("res://scripts/region1/tutorial_director.gd")
const View := preload("res://scripts/region1/tutorial_prompt_view.gd")
const Probe := preload("res://scripts/core/perf_probe.gd")


class FakePlayer extends Node3D:
	var velocity := Vector3.ZERO
	var dead := false
	var camera: Node3D
	func nearest_interactable() -> Node:
		return null


func _bridge() -> Array:
	var p := FakePlayer.new()
	var hud := CanvasLayer.new()
	add_child(p)
	add_child(hud)
	var b := Bridge.new()
	add_child(b)
	b.setup(p, hud)
	return [b, p, hud]


func _cleanup(parts: Array) -> void:
	for n: Node in parts:
		n.queue_free()


func test_bridge_builds_its_context_at_a_fixed_rate() -> void:
	var parts := _bridge()
	var b: Region1TutorialBridge = parts[0]
	var calls := [0]
	b.providers["near_dim_stone"] = func(_p: Vector3) -> bool:
		calls[0] += 1
		return false
	for i in 100:                       # 1.6 s of 60 fps frames
		b._process(0.016)
	assert_int(calls[0]).is_between(8, 12)       # one context per CTX_RATE (0.15 s), not one per frame
	_cleanup(parts)


func test_bridge_is_idle_when_every_prompt_is_settled() -> void:
	var parts := _bridge()
	var b: Region1TutorialBridge = parts[0]
	for id in Director.ids():
		b.director.skip(StringName(id))
	var calls := [0]
	b.providers["near_dim_stone"] = func(_p: Vector3) -> bool:
		calls[0] += 1
		return false
	for i in 200:
		b._process(0.05)
	assert_int(calls[0]).is_equal(0)
	# a replay brings it back to life
	b.director.replay(&"move")
	for i in 10:
		b._process(0.05)
	assert_int(calls[0]).is_greater(0)
	_cleanup(parts)


func test_bridge_timers_see_the_same_total_time() -> void:
	var parts := _bridge()
	var b: Region1TutorialBridge = parts[0]
	(parts[1] as FakePlayer).velocity = Vector3(3, 0, 0)
	for i in 90:                        # walking is counted per frame, whatever the context rate
		b._process(0.01)
	assert_float(float(b.director._progress[&"move"])).is_between(0.85, 0.95)
	_cleanup(parts)


func test_prompt_view_sleeps_when_nothing_is_shown_and_wakes_for_a_prompt() -> void:
	var d := Director.new()
	var v: Region1TutorialPromptView = auto_free(View.new())
	add_child(v)
	v.size = Vector2(1200, 540)
	v.bind(d)
	v._process(0.016)
	assert_bool(v.is_processing()).is_false()
	v.show_prompt(&"move", d.describe(&"move", true))
	assert_bool(v.is_processing()).is_true()
	for i in 20:
		v._process(0.05)
	assert_bool(v.is_processing()).is_true()
	v.hide_prompt(&"move", &"done")
	for i in 40:
		v._process(0.05)
	assert_bool(v._pill.visible).is_false()
	assert_bool(v.is_processing()).is_false()


func test_world_sim_far_loop_still_reaches_every_resident() -> void:
	var n: int = WorldSim.population()
	assert_int(n).is_greater(1000)
	WorldSim._clock = 5000.0
	var frame := 1.0 / 30.0
	var missed := n
	var frames := 0
	# One pass takes about FAR_PERIOD seconds (longer while the first steps of a fresh clock are expensive: the per-frame
	# time budget still caps them), so everyone is reached within a few periods of game time.
	while missed > 0 and frames < int(WorldSim.FAR_PERIOD * 4.0 / frame):
		for i in 15:
			WorldSim._clock += frame
			WorldSim._simulate_slice(frame)
		frames += 15
		missed = 0
		for i in n:
			if WorldSim.health[i] != 0 and WorldSim.last_update[i] <= 5000.0:
				missed += 1
	assert_int(missed).is_equal(0)


func test_world_sim_far_loop_steps_only_what_the_time_asks_for() -> void:
	var n: int = WorldSim.population()
	var frame := 1.0 / 30.0
	WorldSim._clock = 9000.0
	WorldSim._simulate_slice(frame)
	var stepped := 0
	for i in n:
		if WorldSim.health[i] != 0 and WorldSim.last_update[i] >= 9000.0:
			stepped += 1
	# the old loop stepped residents until its 500 us budget was gone (thousands per frame); now one frame's share of FAR_PERIOD
	assert_int(stepped).is_greater(0)
	assert_int(stepped).is_less_equal(ceili(float(n) * frame / WorldSim.FAR_PERIOD) + 64)


func test_probe_is_a_no_op_while_off() -> void:
	Probe.on = false
	Probe.reset()
	var t0 := Probe.t()
	assert_int(t0).is_equal(0)
	Probe.add("x", t0)
	assert_bool(Probe.us.has("x")).is_false()
	Probe.on = true
	Probe.add("x", Probe.t())
	assert_bool(Probe.us.has("x")).is_true()
	Probe.on = false
	Probe.reset()
