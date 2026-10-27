extends GdUnitTestSuite
## T-pose ship-blocker guard (2026-10-28): every actor builder, at every quality tier, ends with a clip playing (or an active
## AnimationTree) and its arms out of the rest pose; the AnimWatchdog starts an idle on any rig spawned without a clip.

const RoadTraffic := preload("res://scripts/world/road_traffic.gd")
const Watchdog := preload("res://scripts/living_world/anim_watchdog.gd")
const LOOKS := ["villager_man_a", "villager_man_b", "villager_woman_a", "villager_woman_b", "elder_man", "elder_woman",
	"villager_farmer", "villager_merchant", "villager_baker", "villager_healer", "villager_guard", "mother", "father",
	"child_boy", "child_girl", "guard"]

var _tier0 := 0


func before_test() -> void:
	_tier0 = int(Quality.tier)


func after_test() -> void:
	Quality.tier = _tier0


static func _in_rest(sk: Skeleton3D) -> bool:
	var ul := sk.find_bone("upperarm_l")
	var ur := sk.find_bone("upperarm_r")
	if ul < 0 or ur < 0:
		return false
	return sk.get_bone_pose_rotation(ul).angle_to(sk.get_bone_rest(ul).basis.get_rotation_quaternion()) < 0.02 \
		and sk.get_bone_pose_rotation(ur).angle_to(sk.get_bone_rest(ur).basis.get_rotation_quaternion()) < 0.02


## Every humanoid rig under `root` is animated: a playing clip or an active tree, and the arms moved off the rest pose.
func _assert_animated(root: Node, label: String) -> void:
	var n := 0
	for skn: Node in root.find_children("*", "Skeleton3D", true, false):
		var sk := skn as Skeleton3D
		if sk.find_bone("upperarm_l") < 0:
			continue
		n += 1
		var host: Node = sk.get_parent()
		var ap: AnimationPlayer = null
		var trees: Array = []
		for up in 4:          # the player / tree sit beside the armature on the model root (or one level up)
			if host == null:
				break
			var aps := host.find_children("*", "AnimationPlayer", true, false)
			trees = host.find_children("*", "AnimationTree", true, false)
			if not aps.is_empty():
				ap = aps[0]
				break
			host = host.get_parent()
		var tree_on := not trees.is_empty() and (trees[0] as AnimationTree).active
		assert_bool((ap != null and ap.is_playing()) or tree_on).override_failure_message("%s: %s plays no clip" % [label, sk.get_parent().name]).is_true()
		assert_bool(_in_rest(sk)).override_failure_message("%s: %s is in the rest (T) pose" % [label, sk.get_parent().get_parent().name]).is_false()
	assert_int(n).override_failure_message("%s: no humanoid rig built" % label).is_greater(0)


func test_road_traffic_groups_are_animated_at_every_tier() -> void:
	for tier in 4:
		Quality.tier = tier
		var rt: Node = auto_free(RoadTraffic.new())
		add_child(rt)
		for kind in ["patrol", "wagon"]:
			var node: Node3D = rt.call("_build_visual", kind)
			if node == null:
				continue
			add_child(node)
			await await_millis(200)
			_assert_animated(node, "tier %d %s" % [tier, kind])
			node.queue_free()
		var pil: Node3D = rt.call("_build_pilgrims")
		if pil != null:
			add_child(pil)
			await await_millis(200)
			_assert_animated(pil, "tier %d pilgrims" % tier)
			pil.queue_free()


func test_watchdog_animates_any_rig_spawned_without_a_clip() -> void:
	Watchdog.install(get_tree())
	await await_millis(50)
	for tier in [0, 3]:
		Quality.tier = tier
		var root := Node3D.new()
		add_child(root)
		for look: String in LOOKS:
			var body := Assets.mh_character(look, 1.7)
			if body != null:
				root.add_child(body)        # deliberately no play(): the spawner "forgot"
		await await_millis(900)
		_assert_animated(root, "tier %d watchdog" % tier)
		root.queue_free()
