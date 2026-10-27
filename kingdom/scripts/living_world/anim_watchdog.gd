extends Node
## No actor ever renders in its rest pose (T-pose ship-blocker, 2026-10-28). Listens to SceneTree.node_added: every new
## AnimationPlayer that drives a Skeleton3D is checked CHECK_AFTER seconds later (its spawner has had time to start a clip);
## when nothing plays and no active AnimationTree drives it, the rig's idle starts and the owner is logged once
## (ANIM_WATCHDOG ...) so the spawner can be fixed at the source. Installed once by PopulationLOD (install()).
## Cost: one type check per added node, one deferred check per new AnimationPlayer.

const CHECK_AFTER := 0.5
const IDLES := ["Idle", "Idle_Loop", "Idle_Subtle", "Sword_Idle", "Walking_A", "Walk"]

static var _installed: Node = null
var _pending: Array = []          # [AnimationPlayer, due_ms, retries]
const RECHECK_MS := 1000          # a hidden rig (LOD-parked critter, pooled body) is re-checked until it shows
const MAX_RETRIES := 600
static var fixed := 0             # QA counter


static func install(tree: SceneTree) -> void:
	if _installed != null and is_instance_valid(_installed):
		return
	var w := preload("res://scripts/living_world/anim_watchdog.gd").new()
	w.name = "AnimWatchdog"
	tree.root.add_child.call_deferred(w)
	_installed = w


func _ready() -> void:
	get_tree().node_added.connect(_on_added)


func _on_added(n: Node) -> void:
	if n is AnimationPlayer:
		_pending.append([n, Time.get_ticks_msec() + int(CHECK_AFTER * 1000.0), 0])


func _process(_delta: float) -> void:
	if _pending.is_empty():
		return
	var now := Time.get_ticks_msec()
	var keep: Array = []
	for e: Array in _pending:
		var ap: AnimationPlayer = e[0] if is_instance_valid(e[0]) else null
		if ap == null:
			continue
		if now < int(e[1]):
			keep.append(e)
			continue
		if ap.is_inside_tree() and not _check(ap) and int(e[2]) < MAX_RETRIES:
			keep.append([ap, now + RECHECK_MS, int(e[2]) + 1])     # hidden for now: look again when it may be on screen
	_pending = keep


## true = settled (playing, tree-driven, not a humanoid rig, or fixed now); false = hidden, check again later.
func _check(ap: AnimationPlayer) -> bool:
	if ap.is_playing():
		return true
	var host := ap.get_parent()
	if host == null or host.find_children("*", "Skeleton3D", true, false).is_empty():
		return true
	if not ap.can_process() or (host is Node3D and not (host as Node3D).is_visible_in_tree()):
		return false              # parked / hidden: no T-pose can be seen, and its owner may start a clip when it shows
	# a tree-driven rig (CharacterAnimator, combat) is animated by its AnimationTree, not by the player itself
	var scope: Node = host.get_parent() if host.get_parent() != null else host
	for t: Node in scope.find_children("*", "AnimationTree", true, false):
		if (t as AnimationTree).active:
			return true
	# terminal / deliberately held poses (death, ragdoll) set a meta on the player or keep a clip assigned
	if ap.assigned_animation != "" or ap.has_meta("hold_pose"):
		return true
	for c: String in IDLES:
		if ap.has_animation(c):
			var a := ap.get_animation(c)
			if a.loop_mode == Animation.LOOP_NONE:
				a.loop_mode = Animation.LOOP_LINEAR
			ap.play(c)
			ap.seek(fmod(float(ap.get_instance_id() % 997) * 0.618034, 1.0) * a.length, true)
			fixed += 1
			var owner_node: Node = host
			while owner_node != null and owner_node.get_script() == null:
				owner_node = owner_node.get_parent()
			print("ANIM_WATCHDOG started %s on %s (%s): it was spawned without a clip" % [c, host.name,
				(owner_node.get_script() as Script).resource_path if owner_node and owner_node.get_script() else "?"])
			return true
	return true
