class_name AshGhostClips
extends RefCounted
## Which animation clip an Ashsight ghost plays. Locomotion comes from the game's UAL library
## (the `Assets` character carries it: UAL1/UAL2 + extra CC0 libraries); the fight / hurt / fall /
## work clips come from the free CC0 packs in `assets/incoming/animations_free*` (docs/anim/
## free_library/HANDOFF_CODEX.md) and are copied into a small "ash" library on the ghost's own
## AnimationPlayer (`ensure_library`, once per skeleton path, root motion off).
##
## Locomotion clips are driven by DISTANCE (`ref` = the metres one second of the clip covers), so
## the feet stay planted whatever the replay speed. Act clips are aligned so their `hit` second
## lands on the recorded instant; `len` is the clip length, `hold` keeps the last pose (a fall),
## `span` repeats a work clip for that many seconds after the instant. Data only.

const LOCO := {
	"idle": {"clip": "Idle", "ref": 0.0},
	"walk": {"clip": "Walk", "ref": 1.45},
	"jog": {"clip": "Jog_Fwd", "ref": 3.4},
	"sprint": {"clip": "Sprint", "ref": 5.6},
}
## Speed (m/s) at which the next gait starts / the previous one comes back (hysteresis).
const UP := {"idle": 0.55, "walk": 2.7, "jog": 5.2}
const DOWN := {"walk": 0.3, "jog": 2.2, "sprint": 4.6}

const FREE_FILES := [
	"res://assets/incoming/animations_free/weapons/UAL_Free_Weapons.glb",
	"res://assets/incoming/animations_free2/kaykit_combat_reactions/UAL_Kay_combat_reactions.glb",
	"res://assets/incoming/animations_free2/kaykit_life_sim/UAL_Kay_life_sim.glb",
]
const LIB := "ash"

## role -> act -> [variants]. `hit` = second of the clip where the blow lands / the recoil peaks.
const ACTS := {
	"bandit": {
		&"attack": [
			{"clip": "ash/Weapon_1H_Chop", "hit": 0.57, "len": 1.07},
			{"clip": "ash/Weapon_1H_Slice_Horizontal", "hit": 0.30, "len": 1.37},
			{"clip": "ash/Weapon_1H_Slice_Diagonal", "hit": 0.47, "len": 1.0},
		],
		&"hit": [{"clip": "ash/Kay_Hit_React_B", "hit": 0.23, "len": 0.87}, {"clip": "ash/Kay_Hit_React_A", "hit": 0.10, "len": 0.67}],
		&"death": [{"clip": "ash/Kay_Death_Fall_B", "hit": 0.05, "len": 2.1, "hold": true}],
		&"chisel": [{"clip": "ash/Kay_Work_Hammer_Repeat", "hit": 0.0, "len": 2.67, "span": 6.0}],
	},
	"villager": {
		&"attack": [{"clip": "ash/Weapon_1H_Chop", "hit": 0.57, "len": 1.07}],
		&"hit": [{"clip": "ash/Kay_Hit_React_B", "hit": 0.23, "len": 0.87}, {"clip": "ash/Kay_Hit_React_A", "hit": 0.10, "len": 0.67}],
		&"death": [{"clip": "ash/Kay_Death_Fall_B", "hit": 0.05, "len": 2.1, "hold": true}],
		&"chisel": [{"clip": "ash/Kay_Work_Hammer_Repeat", "hit": 0.0, "len": 2.67, "span": 6.0}],
	},
}

static var _libs: Dictionary = {}   # skeleton path -> AnimationLibrary


## Every clip name the ghosts can play (for pre-warming the animation caches).
static func all_clips() -> Array[String]:
	var out: Array[String] = []
	for c in GAIT_CLIP:
		out.append(c)
	for role: String in ACTS:
		for act: StringName in ACTS[role]:
			for v: Dictionary in ACTS[role][act]:
				if not out.has(String(v["clip"])):
					out.append(String(v["clip"]))
	return out


## Pick a clip for an act; `variant` (an actor id hash) chooses between alternatives so two
## bandits do not swing in lockstep.
static func act_clip(role: String, act: StringName, variant: int = 0) -> Dictionary:
	var table: Dictionary = ACTS.get(role, ACTS["villager"])
	var list: Array = table.get(act, [])
	if list.is_empty():
		return {}
	return list[absi(variant) % list.size()]


## Copy the free-pack clips this table uses into an "ash" library on `ap` (no-op when present).
static func ensure_library(ap: AnimationPlayer) -> void:
	if ap == null or ap.has_animation_library(LIB):
		return
	var root := ap.get_node_or_null(ap.root_node)
	if root == null:
		return
	var skels := root.find_children("*", "Skeleton3D", true, false)
	if skels.is_empty():
		return
	var sk := String(root.get_path_to(skels[0]))
	if not _libs.has(sk):
		_libs[sk] = _build(sk)
	ap.add_animation_library(LIB, _libs[sk])


## clip name -> true when the clip repeats (a work clip with a `span`)
static func _wanted() -> Dictionary:
	var out := {}
	for role: String in ACTS:
		for act: StringName in ACTS[role]:
			for v: Dictionary in ACTS[role][act]:
				var key := String(v["clip"]).trim_prefix(LIB + "/")
				out[key] = bool(out.get(key, false)) or float(v.get("span", 0.0)) > 0.0
	return out


static func _build(sk: String) -> AnimationLibrary:
	var lib := AnimationLibrary.new()
	var want := _wanted()
	for file: String in FREE_FILES:
		if not ResourceLoader.exists(file):
			push_warning("Ashsight: missing clip pack " + file)
			continue
		var inst: Node = (load(file) as PackedScene).instantiate()
		var found := inst.find_children("*", "AnimationPlayer", true, false)
		if not found.is_empty():
			var src: AnimationPlayer = found[0]
			for name_: StringName in src.get_animation_list():
				if not want.has(String(name_)) or lib.has_animation(name_):
					continue
				var a: Animation = src.get_animation(name_).duplicate(true)
				if bool(want[String(name_)]):
					a.loop_mode = Animation.LOOP_LINEAR   # a work clip repeats natively (no reseek at the wrap)
				for t in a.get_track_count():
					var tp := String(a.track_get_path(t))
					var colon := tp.find(":")
					if colon > 0:
						a.track_set_path(t, NodePath(sk + tp.substr(colon)))
						# in place: the recorded path moves the ghost, not the clip
						if tp.substr(colon) == ":root" and a.track_get_type(t) == Animation.TYPE_POSITION_3D:
							a.track_set_enabled(t, false)
				lib.add_animation(name_, a)
		inst.free()
	return lib


const GAIT_CLIP: Array[String] = ["Idle", "Walk", "Jog_Fwd", "Sprint"]
const GAIT_REF: Array[float] = [0.0, 1.45, 3.4, 5.6]
const GAIT_UP: Array[float] = [0.55, 2.7, 5.2, 1.0e9]      ## speed at which gait i gives way to i + 1
const GAIT_DOWN: Array[float] = [-1.0, 0.3, 2.2, 4.6]      ## speed at which gait i gives way to i - 1


## Next gait (0 idle, 1 walk, 2 jog, 3 sprint) with hysteresis, so the legs do not flicker.
static func next_gait(gait: int, speed: float) -> int:
	var g := gait
	while g < 3 and speed >= GAIT_UP[g]:
		g += 1
	while g > 0 and speed < GAIT_DOWN[g]:
		g -= 1
	return g


## Gait for a speed, with hysteresis around the thresholds so the legs do not flicker between
## clips. `current` is the clip playing now.
static func locomotion(_role: String, speed: float, current: String) -> Dictionary:
	var gait := "idle"
	var cur := ""
	for k: String in LOCO:
		if String(LOCO[k]["clip"]) == current:
			cur = k
	match cur:
		"", "idle":
			gait = "idle" if speed < float(UP["idle"]) else ("walk" if speed < float(UP["walk"]) else ("jog" if speed < float(UP["jog"]) else "sprint"))
		"walk":
			gait = "idle" if speed < float(DOWN["walk"]) else ("walk" if speed < float(UP["walk"]) else ("jog" if speed < float(UP["jog"]) else "sprint"))
		"jog":
			gait = ("walk" if speed < float(DOWN["jog"]) else ("jog" if speed < float(UP["jog"]) else "sprint"))
		"sprint":
			gait = ("jog" if speed < float(DOWN["sprint"]) else "sprint")
	return LOCO[gait]
