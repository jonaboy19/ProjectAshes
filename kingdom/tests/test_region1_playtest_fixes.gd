extends GdUnitTestSuite
## Region 1 blocker found by the story playtest: the "Kneel at the ashes" / "Face the Scar" prompts sit on the player (distance 0), so the
## interact picker chose them over a person standing beside the player: Mother, then Idra at the Pennick farm, could not be talked to.

const FollowStation := preload("res://scripts/region1/r1_follow_station.gd")
const Picker := preload("res://scripts/interaction/interaction_picker.gd")


func test_an_on_player_prompt_ranks_as_a_passer_by() -> void:
	var player: Node3D = auto_free(Node3D.new())
	player.add_to_group("player")
	add_child(player)
	var st: Node3D = auto_free(FollowStation.new("Test"))
	st.finder = func(pp: Vector2) -> Dictionary: return {"pos": pp, "at_player_height": true, "verb": "Kneel", "menu": func() -> Dictionary: return {}}
	add_child(st)
	st._process(1.0)
	assert_bool(st.has_meta("low_priority")).is_true()
	# the picker: the ashes (low priority, on the player) against a person 1.8 m ahead, faced
	var pos := Vector3.ZERO
	var facing := Vector3(0, 0, -1)
	var ash := {"id": "ash", "pos": pos, "low_priority": true}
	var npc := {"id": "npc", "pos": Vector3(0, 0, -1.8)}
	assert_str(String(Picker.pick(pos, facing, [ash, npc]).get("id", ""))).is_equal("npc")
	# alone, the ashes still work
	assert_str(String(Picker.pick(pos, facing, [ash]).get("id", ""))).is_equal("ash")


func test_a_stone_prompt_keeps_its_priority() -> void:
	var player: Node3D = auto_free(Node3D.new())
	player.add_to_group("player")
	add_child(player)
	var st: Node3D = auto_free(FollowStation.new("Test2"))
	st.finder = func(pp: Vector2) -> Dictionary: return {"pos": pp + Vector2(2, 0), "verb": "Read", "menu": func() -> Dictionary: return {}}
	add_child(st)
	WorldGen.setup(2024)
	st._process(1.0)
	assert_bool(st.has_meta("low_priority")).is_false()


const StoryDirector := preload("res://scripts/region1/r1_story_director.gd")


class StubGlue extends Node:
	var tutorial = null
	func npc_extra_options(_id: String) -> Array:
		return []


## Found by the story playtest: a choice that finishes a step mid-conversation made the director free the speaker's Station, and the open
## sheet then called a freed Station's menu on every rebuild.
func test_the_director_keeps_the_person_you_are_talking_to() -> void:
	var world: Node3D = auto_free(Node3D.new())
	var player: Node3D = auto_free(Node3D.new())
	player.add_to_group("player")
	add_child(world)
	add_child(player)
	var glue: Node = auto_free(StubGlue.new())
	add_child(glue)
	var dir: Node = auto_free(StoryDirector.new())
	add_child(dir)
	dir.setup(glue, null, player, world)
	dir.story.status.clear()
	var npc: Node3D = auto_free(Node3D.new())
	world.add_child(npc)
	dir._npcs["speaker@nowhere"] = npc
	dir._conv = {"npc": "speaker", "step": "x", "file": "", "node": "", "speaker": "speaker", "line": "", "options": []}
	dir._manage_npcs()
	assert_bool(dir._npcs.has("speaker@nowhere") and not npc.is_queued_for_deletion()).override_failure_message("freed mid-conversation").is_true()
	dir._conv = {}
	dir._manage_npcs()
	assert_bool(dir._npcs.has("speaker@nowhere")).is_false()
