extends GdUnitTestSuite
## Headless world lint (tools_qa/lint_world): builds a small subset of the world's dressing exactly like the game does and
## asserts there is no SEVERE placement bug (prop floating > 1 m, building overlap, solid prop on a road).
## Full world: godot --headless --path . -s res://tools_qa/lint_world/world_lint.gd   (see .claude/skills/ashes-world-lint)
## Known non-trivial issues are allowlisted with a TODO in tools_qa/lint_world/lint_config.gd.

const Core := preload("res://tools_qa/lint_world/lint_core.gd")
const KitLint := preload("res://tools_qa/lint_world/kit_lint.gd")
const Ground := preload("res://scripts/world/town_kit/town_ground.gd")
const TownLivestock := preload("res://scripts/world/town_kit/town_livestock.gd")
const TownPlaces := preload("res://scripts/world/town_kit/town_places.gd")

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


## All 30 Region 1 settlements through SettlementBuilder: no severe or major finding and every town inside its draw budget.
func test_all_thirty_settlements_have_no_severe_or_major_issues() -> void:
	_lint(1066, ["settlement"])
	var towns := {}
	for g: Dictionary in _core.groups:
		if String(g["kind"]) == "settlement":
			towns[String(g["name"])] = true
	assert_int(towns.size()).override_failure_message("expected 30 settlements in the lint, got %d" % towns.size()).is_equal(30)
	assert_int(_core.severe_issues().size()).override_failure_message("severe world-lint issues:\n" + _report_if_any()).is_equal(0)
	var majors: Array[String] = []
	for i: Dictionary in _core.issues:
		if i["severity"] == "major" or (i["type"] == "draws"):
			majors.append("[%s] %s %s %s" % [i["type"], i["site"], i["path"], i["detail"]])
	assert_array(majors).override_failure_message("major world-lint issues:\n" + "\n".join(majors)).is_empty()


## The town kit's hand-placed props in all 30 towns: clues, stashes, livestock, pens, dens (kit_lint.gd). Pens and props on steep ground
## are moved or skipped by town_ground.gd; nothing stands in water, inside a building, on the road, or draws more than the hub budget.
func test_kit_props_of_all_thirty_towns_are_on_sane_ground() -> void:
	var lint := KitLint.new()
	var holder := Node3D.new()
	add_child(holder)
	lint.run(holder)
	holder.free()
	assert_int(int(lint.stats["towns"])).is_equal(30)
	assert_int(int(lint.stats["clues"])).is_greater(90)
	assert_int(int(lint.stats["pens"])).is_greater(25)
	assert_int(lint.issues.size()).override_failure_message(lint.text()).is_equal(0)


## Skarholm's pen used to sit on about 10 m of slope. The kit must not build a rail fence over that much relief.
func test_skarholm_pen_is_on_level_dry_ground() -> void:
	var doc: Dictionary = preload("res://scripts/world/town_kit/town_data.gd").town("skarholm")
	var pens: Array = (doc.get("livestock", {}) as Dictionary).get("pens", [])
	assert_array(pens).is_not_empty()
	for p: Dictionary in pens:
		var spot := TownLivestock.pen_spot("skarholm", p)
		if spot.is_empty():
			continue            # skipping a pen is allowed; standing on a slope is not
		var size := Vector2(float(p["size"][0]), float(p["size"][1]))
		assert_float(Ground.relief_rect(spot["pos"], size, float(spot["yaw"]))).is_less_equal(Ground.PEN_MAX_RELIEF)
		assert_bool(Ground.rect_wet(spot["pos"], size, float(spot["yaw"]))).is_false()
	for xf: Transform3D in TownLivestock.pen_transforms("skarholm"):
		assert_float(TownLivestock.piece_drop(xf)).is_less_equal(Ground.PEN_MAX_PIECE_DROP)


## The ground checks themselves: a spot on a slope is moved, a level one stays; a ring search never returns a spot that fails the check.
func test_town_ground_moves_props_off_steep_ground() -> void:
	# find a steep patch and a level one near the Thornfield settlement and one far into the hills
	var steep := Vector2.INF
	for k in 4000:
		var p := Vector2(float(k % 80) * 37.0 - 1500.0, float(k / 80) * 41.0 - 800.0)
		if Ground.relief_ring(p, Ground.PROP_RING) > 2.0 and not WorldGen.near_water(p.x, p.y, 3.0):
			steep = p
			break
	assert_bool(steep != Vector2.INF).override_failure_message("no steep ground found to test with").is_true()
	assert_bool(Ground.prop_ok(steep)).is_false()
	var moved := Ground.settle("", steep, Ground.prop_ok, 0.0, 2.0, 12)
	if moved != Vector2.INF:
		assert_bool(Ground.prop_ok(moved)).is_true()
	var best := Ground.settle_prop("", steep)
	assert_bool(best != Vector2.INF).is_true()
	var flat := best if Ground.prop_ok(best) else moved
	if flat != Vector2.INF:
		assert_vector(Ground.settle("", flat, Ground.prop_ok)).is_equal(flat)       # an acceptable spot stays put
