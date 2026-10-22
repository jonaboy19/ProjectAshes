extends GdUnitTestSuite
## Region 1 blocker found by the story playtest: Act I's lone wolf (r1_safe, never kills) fled below 15 hp like any wolf, at the speed of a
## child's sprint, so a real player could never finish "kill the wolf" (the bot chased it for minutes at six metres). It now fights to the end.

func _wolf(safe: bool) -> Wolf:
	var w: Wolf = auto_free(Wolf.new())
	w.species = "wolf"
	if safe:
		w.set_meta("r1_safe", true)
	add_child(w)
	var player: Node3D = auto_free(Node3D.new())
	add_child(player)
	w.max_health = 45
	w.health = 10
	w.state = Wolf.State.ATTACK
	w._decide(player, 0.0)
	return w


func test_the_story_wolf_does_not_flee_when_hurt() -> void:
	assert_int(_wolf(true).state).override_failure_message("the r1_safe wolf is fleeing").is_not_equal(Wolf.State.FLEE)


func test_an_ordinary_hurt_wolf_still_flees() -> void:
	assert_int(_wolf(false).state).is_equal(Wolf.State.FLEE)


const Director := preload("res://scripts/region1/r1_story_director.gd")


func test_the_directors_wolf_ignores_the_ward_so_it_fights_inside_the_ring() -> void:
	WorldGen.setup(2024)
	var dir: Node = auto_free(Director.new())
	var world: Node3D = auto_free(Node3D.new())
	var player: Node3D = auto_free(Node3D.new())
	add_child(world)
	add_child(player)
	add_child(dir)
	dir.world = world
	dir.player = player
	dir._spawn_wolf(Vector2(100, 100))
	var w: Wolf = dir._wolf
	assert_bool(w != null and w.has_meta("r1_safe")).is_true()
	assert_str(String((w.get("_sp") as Dictionary)["ward"])).is_equal("ignore")
