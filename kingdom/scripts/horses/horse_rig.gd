class_name HorseRig
extends Node3D
## The riding horse as one self-contained visual node (standalone: nothing in the game depends on it yet; wiring is in
## docs/anim/patches/P14_*). Owns the model (LOD0/1/2 of assets/generated/horses/horse_riding.glb), the coat, the tack,
## the 50-clip library (Horse_Anims.glb, hand-authored gaits with real footfall patterns), gait selection with speed
## matching, phase-aligned gait changes, one-shot actions, spring bones per quality tier and hoof events.
##
##   var horse := HorseRig.new(); horse.coat = "grey"; horse.tack = ["saddle", "bridle", "reins"]; add_child(horse)
##   horse.drive(speed_mps, turn_rate_rad_s, delta)   # every physics tick from the mount / AI controller
##   horse.play_action("Rear")                        # one-shots: Rear Buck Spook_L/R Hit_L/R Death Jump_Full ...
##   horse.set_mode("graze")                          # "", "graze", "drink", "swim", "cart", "rest"
##   horse.saddle_delta()                             # rigid motion of the saddle vs rest (RiderSync uses it)
##   signal hoof(leg, gait)                           # footfalls from the clip sidecar (sounds, dust, camera)
##
## Root motion: the clips carry travel on the `root` bone. The player consumes it (root_motion_track), so the model
## never drifts; controllers that want it call root_motion_delta(). Clips are otherwise played in place with
## speed_scale = speed / clip speed (the hooves then stay planted, see docs/anim/horses/HANDOFF.md).

signal hoof(leg: String, gait: String)
signal action_finished(action: String)
signal gait_changed(gait: String)

const DIR := "res://assets/generated/horses/"
const MODEL := DIR + "horse_riding.glb"
const ANIMS := DIR + "Horse_Anims.glb"
const SIDECAR := DIR + "Horse_Anims.glb.clips.json"
const LIB := "horse"
const COATS := ["bay", "chestnut", "grey", "black", "dappled", "warhorse"]
const TACK := ["saddle", "bridle", "reins", "saddlebags", "cart_harness", "barding"]

## Gait table: [name, clip (left lead / straight), min speed m/s, max speed m/s] with hysteresis in _pick_gait.
## Speeds are the clips' authored root-motion speeds; speed_scale stays inside SCALE_RANGE of them.
const GAITS := {
	"walk": {"clip": "Walk", "speed": 1.5, "from": 0.15, "to": 2.3},
	"trot": {"clip": "Trot", "speed": 3.6, "from": 2.3, "to": 4.6},
	"canter": {"clip": "Canter", "speed": 5.8, "from": 4.6, "to": 8.2},
	"gallop": {"clip": "Gallop", "speed": 11.0, "from": 8.2, "to": 99.0},
}
const HYST := 0.35               # m/s of hysteresis around every gait boundary
const SCALE_RANGE := Vector2(0.6, 1.45)
const TURN_ON := 0.35            # rad/s: switch to the leaning turn loop
const TURN_OFF := 0.2
const BLEND_GAIT := 0.28
const BLEND_TURN := 0.22

@export_enum("bay", "chestnut", "grey", "black", "dappled", "warhorse") var coat := "bay":
	set(v):
		coat = v
		if is_inside_tree():
			_apply_coat()
@export var tack: Array[String] = []:
	set(v):
		tack = v
		if is_inside_tree():
			_apply_tack()
## 0 LOW, 1 MEDIUM, 2 HIGH (springs, LOD ranges, shadow)
@export var quality := 2:
	set(v):
		quality = v
		if is_inside_tree():
			_apply_quality()

var model: Node3D
var skeleton: Skeleton3D
var anim: AnimationPlayer
var gait := "idle"
var mode := ""
var lead := "L"
var speed := 0.0
var turn_rate := 0.0
var clip := ""
var springs: Array[SpringBoneSimulator3D] = []
var _action := ""
var _turning := 0
var _tack_nodes := {}
var _lods: Array[MeshInstance3D] = []
var _saddle := -1
var _saddle_rest := Transform3D.IDENTITY
var _last_pos := 0.0
var _idle_t := 0.0
var _idle_next := 6.0
var _rng := RandomNumberGenerator.new()

static var _lib: AnimationLibrary
static var _meta := {}
static var _skel_path := ""


static func clip_info(name: String) -> Dictionary:
	_load_meta()
	return _meta.get(name, {})


static func _load_meta() -> void:
	if not _meta.is_empty():
		return
	var arr = JSON.parse_string(FileAccess.get_file_as_string(SIDECAR))
	if arr is Array:
		for e: Dictionary in arr:
			_meta[e["name"]] = e


## The shared clip library with track paths rewritten for `skel_path` (relative to the AnimationPlayer root).
static func library(skel_path: String) -> AnimationLibrary:
	if _lib and _skel_path == skel_path:
		return _lib
	var inst: Node = (load(ANIMS) as PackedScene).instantiate()
	var ap: AnimationPlayer = inst.find_children("*", "AnimationPlayer", true, false)[0]
	var lib := AnimationLibrary.new()
	for n in ap.get_animation_list():
		var a: Animation = ap.get_animation(n).duplicate(true)
		for t in a.get_track_count():
			var tp := String(a.track_get_path(t))
			var colon := tp.find(":")
			if colon > 0:
				a.track_set_path(t, NodePath(skel_path + tp.substr(colon)))
		lib.add_animation(n, a)
	inst.free()
	_lib = lib
	_skel_path = skel_path
	return lib


func _ready() -> void:
	_rng.randomize()
	_load_meta()
	model = (load(MODEL) as PackedScene).instantiate()
	add_child(model)
	skeleton = model.find_children("*", "Skeleton3D", true, false)[0]
	for mi: MeshInstance3D in skeleton.find_children("*", "MeshInstance3D", true, false):
		if mi.name.begins_with("Horse_LOD"):
			_lods.append(mi)
	_lods.sort_custom(func(a, b): return String(a.name) < String(b.name))
	anim = Assets.animation_player(model) if model.find_children("*", "AnimationPlayer", true, false).size() > 0 else null
	if anim == null:
		anim = AnimationPlayer.new()
		model.add_child(anim)
	anim.root_node = anim.get_path_to(model)
	var sp := String(model.get_path_to(skeleton))
	if not anim.has_animation_library(LIB):
		anim.add_animation_library(LIB, library(sp))
	anim.root_motion_track = NodePath(sp + ":root")
	anim.playback_default_blend_time = 0.2
	_saddle = skeleton.find_bone("saddle")
	_saddle_rest = skeleton.get_bone_global_rest(_saddle)
	_apply_coat()
	_apply_tack()
	_apply_quality()
	_play("Idle", 0.0)


# ------------------------------------------------------------------ public API
## Locomotion from the controller: planar speed along the horse's facing (negative = backing up) and yaw rate.
func drive(new_speed: float, new_turn: float, _delta: float) -> void:
	speed = new_speed
	turn_rate = new_turn
	if _action != "":
		return
	var g := _pick_gait(speed)
	if mode == "swim":
		_play("Swim", 0.3, clampf(absf(speed) / 1.1, 0.5, 1.4))
		return
	if g == "idle":
		_turning = 0
		var idle := {"graze": "Graze", "drink": "Drink", "rest": "Idle_RestHind"}.get(mode, "Idle") as String
		if absf(turn_rate) > 0.6:
			idle = "Turn_InPlace_L" if turn_rate > 0 else "Turn_InPlace_R"
		_play(idle, 0.3)
		gait = g
		return
	if g == "backup":
		_play("BackUp", 0.3, clampf(-speed / 0.7, 0.5, 1.6))
		gait = g
		return
	# turn loop hysteresis and canter/gallop lead toward the turn
	if _turning == 0 and absf(turn_rate) > TURN_ON:
		_turning = signi(int(signf(turn_rate)))
	elif _turning != 0 and (absf(turn_rate) < TURN_OFF or signf(turn_rate) != float(_turning)):
		_turning = 0
	if g in ["canter", "gallop"] and _turning != 0:
		lead = "L" if _turning > 0 else "R"
	var base: String = GAITS[g]["clip"]
	var c := base
	if mode == "cart" and g in ["walk", "trot"]:
		c = "Cart_Pull_Walk" if g == "walk" else "Cart_Pull_Trot"
	elif _turning != 0:
		c = base + "_Turn_" + ("L" if _turning > 0 else "R")
	elif g in ["canter", "gallop"]:
		c = base + "_" + lead
	var authored := float(clip_info(c).get("speed_mps", GAITS[g]["speed"]))
	var scale := clampf(absf(speed) / maxf(authored, 0.01), SCALE_RANGE.x, SCALE_RANGE.y)
	var blend := BLEND_GAIT if g != gait else BLEND_TURN
	if g != gait:
		gait_changed.emit(g)
	gait = g
	_play(c, blend, scale, true)


## One-shot action; locomotion resumes after it. Returns false if the clip does not exist.
func play_action(action: String, blend := 0.15) -> bool:
	if not anim.has_animation(LIB + "/" + action):
		return false
	_action = action
	anim.play(LIB + "/" + action, blend, 1.0)
	clip = action
	_last_pos = 0.0
	return true


func is_busy() -> bool:
	return _action != ""


## "", "graze", "drink", "rest", "swim", "cart". Graze/drink play their enter clip first.
func set_mode(m: String) -> void:
	if m == mode:
		return
	var old := mode
	mode = m
	if m in ["graze", "drink"] and speed < 0.15:
		play_action(("Graze" if m == "graze" else "Drink") + "_Enter")
	elif old in ["graze", "drink"] and m == "":
		play_action(("Graze" if old == "graze" else "Drink") + "_Exit")


## Rigid motion of the saddle relative to the rest pose, in the skeleton's space. RiderSync moves the rider by it.
func saddle_delta() -> Transform3D:
	return skeleton.get_bone_global_pose(_saddle) * _saddle_rest.affine_inverse()


## Global transform of a socket bone (saddle, stirrup_L/R, rein_grip_L/R, bit, tug_L/R, cart_hitch).
func socket(bone: String) -> Transform3D:
	return skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(bone))


## Normalized time (0..1) of the current clip: the rider clip plays at the same phase.
func phase() -> float:
	if anim == null or anim.current_animation == "":
		return 0.0
	var l := anim.current_animation_length
	return anim.current_animation_position / l if l > 0.0 else 0.0


func root_motion_delta() -> Vector3:
	return anim.get_root_motion_position()


# ------------------------------------------------------------------ internals
func _pick_gait(v: float) -> String:
	if v < -0.1:
		return "backup"
	var a := absf(v)
	var cur := gait
	if a < (0.25 if cur == "walk" else 0.12):
		return "idle"
	for g: String in ["walk", "trot", "canter", "gallop"]:
		var lo: float = GAITS[g]["from"]
		var hi: float = GAITS[g]["to"]
		if g == cur:
			lo -= HYST
			hi += HYST
		if a >= lo and a < hi:
			if g != cur and cur in GAITS:
				var clo: float = GAITS[cur]["from"] - HYST
				var chi: float = GAITS[cur]["to"] + HYST
				if a >= clo and a < chi:
					return cur
			return g
	return "walk"


func _play(c: String, blend: float, scale := 1.0, keep_phase := false) -> void:
	var full := LIB + "/" + c
	if not anim.has_animation(full):
		return
	anim.speed_scale = scale
	if clip == c and anim.is_playing():
		return
	var ph := phase()
	var was := clip
	clip = c
	anim.play(full, blend)
	if keep_phase and was != "" and _same_family(was, c):
		# gait-to-gait or straight-to-turn: keep the stride phase so the footfall rhythm continues
		anim.seek(ph * anim.current_animation_length, true)
	_last_pos = anim.current_animation_position


func _same_family(a: String, b: String) -> bool:
	return clip_info(a).get("footfall_phase", null) != null and clip_info(b).get("footfall_phase", null) != null


func _process(delta: float) -> void:
	if anim == null or clip == "":
		return
	var pos := anim.current_animation_position
	var info := clip_info(clip)
	var ev: Dictionary = info.get("events", {})
	var fps := float(info.get("fps", 30))
	var f0 := _last_pos * fps
	var f1 := pos * fps
	for k: String in ev:
		if not k.begins_with("hoof_"):
			continue
		for fr in ev[k]:
			var x := float(fr)
			if (f1 >= f0 and x > f0 and x <= f1) or (f1 < f0 and (x > f0 or x <= f1)):
				hoof.emit(k.substr(5), gait)
	_last_pos = pos
	if _action != "" and not anim.is_playing():
		var done := _action
		_action = ""
		clip = ""
		action_finished.emit(done)
		drive(speed, turn_rate, 0.0)
	elif _action == "" and gait == "idle" and mode == "":
		# idle variety: an ear flick, tail swish, weight shift, snort or head toss every 5-12 s
		_idle_t += delta
		if _idle_t > _idle_next:
			_idle_t = 0.0
			_idle_next = _rng.randf_range(5.0, 12.0)
			var pick := ["Idle_EarFlick", "Idle_TailSwish", "Idle_ShiftWeight", "Idle_Snort", "Idle_HeadToss", "Idle_EarFlick"]
			play_action(pick[_rng.randi() % pick.size()], 0.35)


func _apply_coat() -> void:
	var p := DIR + "horse_coat_%s.tres" % coat
	if not ResourceLoader.exists(p):
		return
	var mat: Material = load(p)
	for mi in _lods:
		mi.material_override = mat


func _apply_tack() -> void:
	for k: String in _tack_nodes.keys():
		if not tack.has(k):
			(_tack_nodes[k] as Node).queue_free()
			_tack_nodes.erase(k)
	for t: String in tack:
		if _tack_nodes.has(t):
			continue
		var p := DIR + "horse_tack_%s.glb" % t
		if not ResourceLoader.exists(p):
			push_warning("HorseRig: missing tack " + p)
			continue
		var inst: Node = (load(p) as PackedScene).instantiate()
		var holder := Node3D.new()
		holder.name = "Tack_" + t
		skeleton.add_child(holder)
		var tsk: Skeleton3D = null
		var found := inst.find_children("*", "Skeleton3D", true, false)
		if not found.is_empty():
			tsk = found[0]
		for mi: MeshInstance3D in inst.find_children("*", "MeshInstance3D", true, false):
			var dup := mi.duplicate() as MeshInstance3D
			holder.add_child(dup)
			dup.skeleton = dup.get_path_to(skeleton)
			dup.skin = _rebind(mi.skin, tsk)
			dup.transform = Transform3D.IDENTITY
			dup.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if quality >= 2 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		inst.free()
		_tack_nodes[t] = holder


## The tack GLBs carry their own copy of the skeleton, whose bone ORDER can differ from the model's: rebind every
## skin joint by bone name onto this rig's skeleton.
func _rebind(src: Skin, tsk: Skeleton3D) -> Skin:
	if src == null:
		return null
	var s := Skin.new()
	for b in src.get_bind_count():
		var nm := String(src.get_bind_name(b))
		if nm == "" and tsk:
			var bi := src.get_bind_bone(b)
			nm = tsk.get_bone_name(bi) if bi >= 0 else ""
		var idx := skeleton.find_bone(nm)
		s.add_bind(maxi(idx, 0), src.get_bind_pose(b))
		if idx < 0:
			push_warning("HorseRig: tack joint %s missing" % nm)
	return s


## LOD ranges and springs per tier. LOD0 near, LOD1 mid, LOD2 far (VAT/HorseHerd takes over beyond).
func _apply_quality() -> void:
	var ranges := [[0.0, 14.0], [14.0, 35.0], [35.0, 0.0]] if quality >= 2 else ([[0.0, 9.0], [9.0, 24.0], [24.0, 0.0]] if quality == 1 else [[0.0, 0.0], [0.0, 16.0], [16.0, 0.0]])
	for i in _lods.size():
		var mi := _lods[i]
		var r: Array = ranges[mini(i, 2)]
		mi.visible = not (quality == 0 and i == 0)
		mi.visibility_range_begin = r[0]
		mi.visibility_range_end = r[1]
		mi.visibility_range_begin_margin = 1.0 if r[0] > 0.0 else 0.0
		mi.visibility_range_end_margin = 1.0 if r[1] > 0.0 else 0.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if (i == 0 or quality == 0 and i == 1) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for s in springs:
		s.queue_free()
	springs = HorseSprings.setup(skeleton, quality)
