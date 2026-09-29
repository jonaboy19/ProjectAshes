extends RefCounted
## Foot-phase synced locomotion blend space: idle -> walk -> jog -> sprint on ONE speed axis (m/s).
##
## Blending gait clips only looks right when their feet are in the same phase. Three things make that so here:
##  1. every gait clip is stretched onto the same 1 s timeline (use_custom_timeline + stretch_time_scale), so
##     one normalized phase drives all of them, and a TimeScale node sets the cadence (cycles / s) from the speed;
##  2. each clip gets a start_offset so its LEFT foot reaches its forward-most point at phase 0 (measured from
##     the clip itself, so new clips need no manual tuning);
##  3. the idle sits on the same axis but is never phase-blended (weight ramps 0 -> walk over the first 0.6 m/s).
## Mode 0 (`SYNC_NONE`) builds the naive tree (natural clip lengths, no offsets) for comparison in the demo.
##
##   const Loco := preload("res://tools_qa/anim_tech/lib/loco_tree.gd")
##   var l := Loco.attach(model, Loco.SYNC_PHASE)
##   l.set_speed(2.2)                    # each frame; blends and sets the cadence
## Root motion is not used: the clips are in place and the controller moves the body at `speed`.

const U := preload("res://tools_qa/anim_tech/lib/at_util.gd")
const SYNC_NONE := 0
const SYNC_TIMELINE := 1
const SYNC_PHASE := 2
## [axis speed m/s, clip candidates]
const GAITS := [
	[1.4, ["Walk", "Walking_A"]],
	[3.2, ["Jog_Fwd", "Running_A"]],
	[5.4, ["Sprint", "G6_run"]],
]

var tree: AnimationTree
var mode := SYNC_PHASE
var clips: Array[String] = []
var lens: Array[float] = []
var offsets: Array[float] = []
var _speeds: Array[float] = []


static func attach(model: Node3D, sync_mode := SYNC_PHASE) -> RefCounted:
	var l: RefCounted = (load("res://tools_qa/anim_tech/lib/loco_tree.gd") as GDScript).new()
	l.call("_setup", model, sync_mode)
	return l


func _setup(model: Node3D, sync_mode: int) -> void:
	mode = sync_mode
	var ap := Assets.animation_player(model)
	var sk := U.skeleton_of(model)
	for g: Array in GAITS:
		var c := U.find_clip(ap, g[1])
		clips.append(c)
		lens.append(ap.get_animation(c).length)
		_speeds.append(g[0])
		# phase 0 = left foot furthest forward
		var path := U.sample_bone(ap, sk, c, "foot_l")
		var best := -INF
		var best_t := 0.0
		for i in path.size():
			if path[i].z > best:
				best = path[i].z
				best_t = i / 30.0
		offsets.append(best_t)
	var space := AnimationNodeBlendSpace1D.new()
	space.min_space = 0.0
	space.max_space = _speeds[-1] + 0.5
	space.sync = true
	for i in clips.size():
		var n := AnimationNodeAnimation.new()
		n.animation = clips[i]
		n.loop_mode = Animation.LOOP_LINEAR
		if mode != SYNC_NONE:
			n.use_custom_timeline = true
			n.timeline_length = 1.0
			n.stretch_time_scale = true
			n.start_offset = (offsets[i] / lens[i]) if mode == SYNC_PHASE else 0.0   # timeline seconds = phase (timeline is 1 s)
		space.add_blend_point(n, _speeds[i])
	var idle := AnimationNodeAnimation.new()
	idle.animation = U.find_clip(ap, ["Idle", "Idle_Subtle"])
	var root := AnimationNodeBlendTree.new()
	root.add_node("gait", space, Vector2(-400, 0))
	root.add_node("rate", AnimationNodeTimeScale.new(), Vector2(-200, 0))
	root.add_node("idle", idle, Vector2(-400, -200))
	var mix := AnimationNodeBlend2.new()
	mix.sync = true
	root.add_node("mix", mix, Vector2(0, 0))
	root.connect_node("rate", 0, "gait")
	root.connect_node("mix", 0, "idle")
	root.connect_node("mix", 1, "rate")
	root.connect_node("output", 0, "mix")
	tree = AnimationTree.new()
	tree.tree_root = root
	model.add_child(tree)
	tree.anim_player = tree.get_path_to(ap)
	tree.root_node = tree.get_path_to(ap.get_node(ap.root_node))
	tree.active = true
	set_speed(0.0)


## Cycles per second at `speed`: linear between the clips' natural cadences.
func cadence(speed: float) -> float:
	if speed <= _speeds[0]:
		return speed / _speeds[0] / lens[0]
	for i in range(1, _speeds.size()):
		if speed <= _speeds[i]:
			var k := inverse_lerp(_speeds[i - 1], _speeds[i], speed)
			return lerpf(1.0 / lens[i - 1], 1.0 / lens[i], k)
	return 1.0 / lens[-1]


func set_speed(speed: float) -> void:
	tree.set("parameters/gait/blend_position", speed)
	tree.set("parameters/mix/blend_amount", smoothstep(0.0, 0.6, speed))
	# sync modes: timeline is 1 s, so the scale IS the cadence; naive: natural lengths, plain 1x
	tree.set("parameters/rate/scale", cadence(speed) if mode != SYNC_NONE else 1.0)
