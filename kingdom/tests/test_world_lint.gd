extends GdUnitTestSuite
## Headless world lint (tools_qa/lint_world): builds a small subset of the world's dressing exactly like the game does and
## asserts there is no SEVERE placement bug (prop floating > 1 m, building overlap, solid prop on a road).
## Full world: godot --headless --path . -s res://tools_qa/lint_world/world_lint.gd   (see .claude/skills/ashes-world-lint)
## Known non-trivial issues are allowlisted with a TODO in tools_qa/lint_world/lint_config.gd.

const Core := preload("res://tools_qa/lint_world/lint_core.gd")

var _core: RefCounted = null
var _reseeded := false


func after() -> void:
	if _core != null:
		_core.restore()          # frees the nodes the linter built and un-patches the builder scripts
		_core = null
	if _reseeded:
		_reseeded = false
		WorldGen.setup(WorldSim.SEED)    # other suites assume the game seed


func _lint(seed_value: int, sites: Array) -> void:
	_core = Core.new()
	_core.set_logger(func(_s: String) -> void: pass)
	_reseeded = seed_value != WorldSim.SEED
	_core.run(get_tree(), seed_value, sites)


func _report_if_any() -> String:
	var lines: Array[String] = []
	for i: Dictionary in _core.severe_issues():
		lines.append("[%s] %s %s @%s %s (%s)" % [i["type"], i["site"], i["path"], i["pos"], i["detail"], i["builder"]])
	return "\n".join(lines)


## The game seed: hand-placed region sites, caves, the dungeon tower and the Hidden Vale with its cliff boulders.
func test_game_seed_subset_has_no_severe_issues() -> void:
	_lint(1066, ["waystation", "bandit_camp", "hidden_vale", "caves", "vale", "tower"])
	assert_int(int(_core.stats["units"])).override_failure_message("the linter saw no props at all").is_greater(200)
	assert_int(int(_core.stats["instances"])).override_failure_message("MultiMesh transforms were not captured (mm_shim patch failed?)").is_greater(500)
	assert_int(_core.severe_issues().size()).override_failure_message("severe world-lint issues:\n" + _report_if_any()).is_equal(0)


## Procedural placement on another seed: farms and road-side sites snap to different terrain.
func test_other_seed_farms_and_roadside_have_no_severe_issues() -> void:
	_lint(2024, ["roadside", "mine", "farm"])
	assert_int(int(_core.stats["units"])).is_greater(100)
	assert_int(_core.severe_issues().size()).override_failure_message("severe world-lint issues:\n" + _report_if_any()).is_equal(0)


## The linter itself: a prop floated 3 m above the ground must be reported as severe (guards against a silent no-op linter).
func test_linter_catches_a_floating_prop() -> void:
	_core = Core.new()
	_core.set_logger(func(_s: String) -> void: pass)
	var c := Vector2(0.0, 0.0)
	var root := Node3D.new()
	add_child(root)
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(2.0, 2.0, 2.0)
	mi.mesh = box
	root.add_child(mi)
	mi.global_position = Vector3(c.x, WorldGen.height(c.x, c.y) + 4.0, c.y)    # base 3 m above the ground
	var g: Dictionary = _core._add_group("test:floater", "farm", "Floater", c, [root], [], "tests/test_world_lint.gd", false, false)
	_core._lint_group(g)
	var found := false
	for i: Dictionary in _core.issues:
		found = found or (i["type"] == "float" and i["severity"] == "severe")
	root.free()
	assert_bool(found).override_failure_message("a prop 3 m above the ground was not reported").is_true()
