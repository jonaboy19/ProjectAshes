class_name LifeActor
extends Node3D
## Reference body for the living world: one embodied villager that walks, uses smart objects (SmartObjects.Session:
## approach -> align -> enter -> loop/between -> exit), carries things (composite walk + upper-body clip),
## fidgets, glances (LifeAmbience + LivingEvents), talks in groups and shows the right props (LifeProps.Holder).
## Used by the demo (tools_qa/living_world) and meant as the worked example for wiring the same pieces into
## villager.gd (docs/anim/living_world/HANDOFF.md). Animation LOD is NOT handled here: register the actor with
## CrowdAnimLOD (it owns the AnimationPlayer's process mode and the model's visibility).
##
##   var a := LifeActor.create(id, "villager_smith", 1.72)
##   add_child(a); a.global_position = p
##   a.use_spot(smart_objects, spot, slot)      # or a.walk_to(point), a.carry_to(point, "Life_Carry_Bucket_Upper")
##   a.chat_with(center, face_yaw, speaking_fn)  # a conversation group member
##   a.set_routine([...])                         # a looping list of tasks: {"spot": [s, k]}, {"to": Vector3}, ...

const THINK := 0.3
const WALK_CLIP_SPEED := 0.98       # UAL Walk ground speed (docs/qa/anim_qa_report.md)
const TURN_RATE := 5.0

var person := 0
var look_file := ""
var is_child := false
var base_height := 1.72
var model: Node3D
var anim: AnimationPlayer
var skeleton: Skeleton3D
var look_mod: LookAtModifier3D
var props: LifeProps.Holder
var amb: LifeAmbience
var so: SmartObjects
var session: SmartObjects.Session
var weather := "clear"
var hour := 10.0
var player: Node3D
var routine: Array = []
var routine_i := 0
var paused := false

var _look_target: Node3D
var _look_want: Variant = null
var _target: Variant = null        # Vector3 walk target
var _upper := ""                   # carry layer while walking
var _speed := 0.0
var _yaw := 0.0
var _think := 0.0
var _clip := ""
var _last_pos := 0.0
var _clip_done := false
var _fidget := ""
var _chat: Dictionary = {}         # {center, face, speaking: Callable, turn}
var _wait := 0.0
var _task: Dictionary = {}
var _deferred_command: Dictionary = {}
var _snap: Variant = null
var _weather_upper := ""


static func create(id: int, file: String, height := 1.72, child := false) -> LifeActor:
	var a := LifeActor.new()
	a.person = id
	a.look_file = file
	a.base_height = height
	a.is_child = child
	return a


func _ready() -> void:
	amb = LifeAmbience.new(person, is_child, 0.9 if look_file.begins_with("elder") else 0.4)
	model = Assets.mh_character(look_file, base_height * amb.height, [], false, true)
	model.set_meta("lw_model_root", true)
	add_child(model)
	anim = Assets.animation_player(model)
	LifeLibrary.install(anim)
	skeleton = model.find_children("*", "Skeleton3D", true, false)[0]
	props = LifeProps.Holder.new(skeleton)
	_add_look()
	_yaw = rotation.y
	_think = fmod(float(person) * 0.137, THINK)
	_play("Idle", 0.0)
	anim.seek(fmod(float(person) * 0.618, 1.0) * anim.current_animation_length, true)


func _add_look() -> void:
	if skeleton.find_bone("Head") < 0:
		return
	_look_target = Node3D.new()
	add_child(_look_target)
	_look_target.position = Vector3(0, 1.5, 3.0)
	look_mod = LookAtModifier3D.new()
	look_mod.bone_name = "Head"
	look_mod.forward_axis = SkeletonModifier3D.BONE_AXIS_PLUS_Z
	look_mod.use_angle_limitation = true
	look_mod.symmetry_limitation = true
	look_mod.primary_limit_angle = deg_to_rad(110)
	look_mod.secondary_limit_angle = deg_to_rad(50)
	look_mod.duration = 0.35
	look_mod.influence = 0.8
	skeleton.add_child(look_mod)
	look_mod.target_node = look_mod.get_path_to(_look_target)


# ---------------------------------------------------------------- commands
func set_routine(tasks: Array) -> void:
	routine = tasks
	routine_i = 0
	_next_task()


func walk_to(p: Vector3, upper := "") -> void:
	if _end_session({"kind": "walk", "point": p, "upper": upper}):
		_chat = {}
		return
	_chat = {}
	_target = p
	_upper = upper


func use_spot(o: SmartObjects, spot: int, slot: int) -> bool:
	if _end_session({"kind": "spot", "objects": o, "spot": spot, "slot": slot}):
		_chat = {}
		return true  # accepted; the new slot is claimed after the old exit completes
	_chat = {}
	if not o.claim(spot, slot, person):
		return false
	so = o
	session = o.session(person, spot, slot)
	return true


func chat_with(center: Vector3, face_yaw: float, speaking: Callable) -> void:
	if _end_session({"kind": "chat", "center": center, "face": face_yaw, "speaking": speaking}):
		_chat = {}
		return
	_chat = {"center": center, "face": face_yaw, "speaking": speaking, "turn": -1, "stand": global_position}


## Interrupt an activity. If it has an exit clip, retain its lease and actor
## session until that clip ends, then apply the replacement command.
func _end_session(next_command: Dictionary = {}) -> bool:
	if session:
		session.interrupt()
		if session.phase != SmartObjects.Session.DONE:
			_deferred_command = next_command.duplicate()
			_target = null
			return true
		session = null
		props.clear()
	_snap = null
	_deferred_command = {}
	return false


func _apply_deferred_command() -> void:
	var command := _deferred_command
	_deferred_command = {}
	match String(command.get("kind", "")):
		"walk":
			walk_to(command["point"], String(command.get("upper", "")))
		"spot":
			if not use_spot(command["objects"], int(command["spot"]), int(command["slot"])):
				_wait = 1.5
		"chat":
			chat_with(command["center"], float(command["face"]), command["speaking"])


func _exit_tree() -> void:
	# The actor cannot finish a visible exit after removal, so release its lease
	# immediately rather than leaving the spot occupied forever.
	if session:
		session.cancel_now()
	session = null


func _next_task() -> void:
	if routine.is_empty():
		return
	_task = routine[routine_i % routine.size()]
	routine_i += 1
	if _task.has("spot"):
		var sp: Array = _task["spot"]
		if not use_spot(_task["so"], sp[0], sp[1]):
			_wait = 2.0
	elif _task.has("to"):
		walk_to(_task["to"], _task.get("carry", ""))
	elif _task.has("wait"):
		_target = null
		_wait = float(_task["wait"])


# ---------------------------------------------------------------- frame
## Behaviour LOD: CrowdAnimLOD writes lod_tier (0 NEAR, 1 MID, 2 FAR, 3 OUT). A person standing at a work spot
## in MID, or anyone FAR, runs this body every few physics ticks with the accumulated time (same result,
## a fraction of the GDScript cost). Walkers near the camera always tick every frame (smooth feet).
var lod_tier := 0
var _acc := 0.0
var _tick_i := 0
static var usec_total := 0      # QA: summed behaviour time of all actors (reset by the reader)


func _physics_process(delta: float) -> void:
	if paused:
		return
	_acc += delta
	_tick_i += 1
	var stride := 1
	match lod_tier:
		1:
			stride = 1 if _speed > 0.05 else 3
		2:
			stride = 4
		3:
			stride = 8
	if (_tick_i + person) % stride != 0:
		return
	var t0 := Time.get_ticks_usec()
	_body(_acc)
	_acc = 0.0
	usec_total += Time.get_ticks_usec() - t0


func _body(delta: float) -> void:
	_think -= delta
	if _think <= 0.0:
		_think += THINK
		_think_tick()
	_track_clip()
	var want_speed := 0.0
	var face: Variant = null
	if session:
		var out := session.update(delta, global_position, _clip_done)
		_clip_done = false
		if out["move_to"] != null:
			_target = out["move_to"]
		else:
			_target = null
		if not is_nan(float(out["face"])):
			face = float(out["face"])
		if out["clip"] != "":
			if out["restart"] or _clip != out["clip"]:
				_play(out["clip"], float(LifeLibrary.info(out["clip"]).get("blend_in", 0.25)), true)
			props.show_props(out["props"])
			anim.speed_scale = amb.anim_rate if LifeLibrary.info(out["clip"]).get("loop", false) else 1.0
		if out.get("snap") != null:
			_snap = out["snap"]
		if out["event"] != null:
			var ev: Dictionary = out["event"]
			LivingEvents.emit(String(ev.get("kind", "work")), global_position, float(ev.get("radius", 10.0)), 2.0)
		if session.phase == SmartObjects.Session.DONE:
			session = null
			_snap = null
			props.clear()
			if not _deferred_command.is_empty():
				_apply_deferred_command()
			else:
				_next_task()
	elif not _chat.is_empty():
		_target = null
		face = float(_chat["face"])
	if _target != null:
		var to: Vector3 = (_target as Vector3) - global_position
		to.y = 0.0
		var d := to.length()
		var arrive := 0.08 if session else 0.3
		if d > arrive:
			want_speed = minf(1.2 * amb.walk_speed * _pace(), d * 1.6 + 0.25)
			face = atan2(to.x, to.z)
		else:
			_target = null
			if session == null and _chat.is_empty():
				_upper = "" if not _task.has("keep_carry") else _upper
				_next_task_after_arrive()
	_speed = move_toward(_speed, want_speed, (1.6 if want_speed > _speed else 2.8) * delta)
	if face != null:
		_yaw = rotate_toward(_yaw, float(face), TURN_RATE * delta * (0.6 if _speed > 0.1 else 1.0))
	rotation.y = _yaw
	if _speed > 0.01:
		global_position += Vector3(sin(_yaw), 0, cos(_yaw)) * _speed * delta
	elif _snap != null:
		# settle exactly onto the slot while using it (the approach ends within a few cm)
		var sx: Transform3D = _snap
		global_position = global_position.lerp(sx.origin, 1.0 - exp(-8.0 * delta))
	_update_locomotion_clip()
	if _look_target and _look_want != null:
		_look_target.global_position = _look_target.global_position.lerp(_look_want, 1.0 - exp(-6.0 * delta))
	elif _look_target:
		var ahead := global_position + Vector3(sin(_yaw), 0, cos(_yaw)) * 3.0 + Vector3(0, 1.5, 0)
		_look_target.global_position = _look_target.global_position.lerp(ahead, 1.0 - exp(-4.0 * delta))


func _next_task_after_arrive() -> void:
	if _wait <= 0.0:
		_next_task()


func _pace() -> float:
	return 1.3 if weather == "rain" else 1.0


func _think_tick() -> void:
	if _wait > 0.0:
		_wait -= THINK
		if _wait <= 0.0 and session == null and _target == null and _chat.is_empty():
			_next_task()
	var idle := session == null and _target == null and _speed < 0.05
	var ctx := {"idle": idle and _chat.is_empty(), "walking": _speed > 0.1, "pos": global_position,
		"fwd": Vector3(sin(_yaw), 0, cos(_yaw)), "hour": hour, "weather": weather,
		"player_pos": player.global_position if player else null,
		"partner_pos": _chat.get("center") if not _chat.is_empty() else null}
	var d := amb.think(THINK, ctx)
	_look_want = d["look"]
	_weather_upper = d["upper"]
	if d["fidget"] != "" and _fidget == "" and anim.has_animation(d["fidget"]):
		_fidget = d["fidget"]
		_play(_fidget, 0.25, true)
	if not _chat.is_empty():
		var speaking: bool = (_chat["speaking"] as Callable).call(person)
		var turn := int(Time.get_ticks_msec() / 5000)
		if turn != int(_chat["turn"]) or (_clip_done and _fidget == ""):
			_chat["turn"] = turn
			var c := amb.talk_clip(speaking, turn + person)
			if not anim.has_animation(c):
				c = "Idle_Talking" if speaking else "Idle_Listening"
			_play(c, 0.35, true)
			props.clear()
	if _speed > 0.1:
		props.show_props(LifeLibrary.info(_upper).get("props", []) if _upper != "" else [])
	elif session == null and _chat.is_empty() and _upper == "":
		props.clear()


## Loop wrap / one-shot end detection (the Session and fidgets need "the clip finished a cycle").
func _track_clip() -> void:
	if anim == null or _clip == "":
		return
	var p := anim.current_animation_position
	var a := anim.get_animation(_clip) if anim.has_animation(_clip) else null
	if a == null:
		return
	if a.loop_mode != Animation.LOOP_NONE:
		if p + 0.0001 < _last_pos:
			_clip_done = true
	elif not anim.is_playing() or p >= a.length - 0.02:
		_clip_done = true
	_last_pos = p
	if _clip_done and _fidget != "" and _clip == _fidget:
		_fidget = ""
		_clip_done = false
		_play("Idle", 0.3)


func _update_locomotion_clip() -> void:
	if session and session.phase in [SmartObjects.Session.ENTER, SmartObjects.Session.LOOP, SmartObjects.Session.BETWEEN, SmartObjects.Session.EXIT]:
		return
	if _speed > 0.08:
		_fidget = ""
		var w := _walk_clip()
		var clip := w
		var up := _upper if _upper != "" else _weather_upper
		if up != "" and anim.has_animation(up):
			clip = LifeLibrary.composite(anim, w, up)
		if _clip != clip:
			_play(clip, 0.25)
		var cs := float(LifeLibrary.info(w).get("speed_mps", 0.0))
		if cs <= 0.01:
			cs = WALK_CLIP_SPEED
		anim.speed_scale = clampf(_speed / cs, 0.4, 1.8)
	elif session == null and _chat.is_empty() and _fidget == "":
		if _clip != "Idle" and not _clip.begins_with("Life_Talk") and not _clip.begins_with("Idle_"):
			_play("Idle", 0.3)
		if _clip == "Idle":
			anim.speed_scale = amb.anim_rate


func _walk_clip() -> String:
	var w := amb.walk_style
	if weather == "rain" and not is_child:
		w = "Life_Walk_Brisk"
	if not anim.has_animation(w):
		w = "Walk"
	return w


func _play(clip: String, blend := 0.25, restart := false) -> void:
	if not anim.has_animation(clip):
		return
	if clip == _clip and not restart:
		return
	anim.play(clip, blend)
	if restart and clip == _clip:
		anim.seek(0.0, true)
	_clip = clip
	_last_pos = 0.0
	_clip_done = false
