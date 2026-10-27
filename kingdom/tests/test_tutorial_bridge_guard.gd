extends GdUnitTestSuite
## Region1TutorialBridge.context() used to call String(null) when an interactable's `verb` was unset (37 errors per slice run).

class WithVerb extends Node:
	var verb := "Sleep"

class NullVerb extends Node:
	var verb: Variant = null

class NoVerb extends Node:
	pass


func test_interact_verb_reads_strings_and_survives_null_and_missing() -> void:
	var a: Node = auto_free(WithVerb.new())
	var b: Node = auto_free(NullVerb.new())
	var c: Node = auto_free(NoVerb.new())
	assert_str(Region1TutorialBridge.interact_verb(a)).is_equal("Sleep")
	assert_str(Region1TutorialBridge.interact_verb(b)).is_equal("")
	assert_str(Region1TutorialBridge.interact_verb(c)).is_equal("")
	assert_str(Region1TutorialBridge.interact_verb(null)).is_equal("")
