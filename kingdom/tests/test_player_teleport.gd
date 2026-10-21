extends GdUnitTestSuite
## Found by the story playtest (Act IV): teleporting (fast travel, QA hooks, door exits) from a place high above the destination left the
## player's fall apex behind, and the first landing there read as a long drop: fall damage, a dead player at full health.

const PlayerScript := preload("res://scripts/actors/player.gd")

var _p: Node3D


func before_test() -> void:
	WorldGen.setup(2024)
	_p = auto_free(PlayerScript.new())
	add_child(_p)
	_p.global_position = Vector3(0.0, 10.0, 0.0)
	# the state of a player who was in the air 140 m up when the teleport happened
	_p._fall_apex_y = 140.0
	_p._air_visual = true
	_p._jump_active = true


func test_a_stale_apex_without_the_reset_is_a_deadly_landing() -> void:
	# (the failure the fix removes: documents why teleported() exists)
	var hp: int = _p.health
	_p._land_jump(8.0, Vector3.ZERO)
	assert_int(_p.health).is_less(hp)


func test_a_teleport_forgets_the_fall() -> void:
	var hp: int = _p.health
	_p.teleported()
	_p._land_jump(8.0, Vector3.ZERO)
	assert_int(_p.health).is_equal(hp)
	assert_bool(_p.dead).is_false()
