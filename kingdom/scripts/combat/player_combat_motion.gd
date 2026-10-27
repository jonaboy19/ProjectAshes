extends RefCounted
## Player-side full-motion combat (combat-motion worker; split agreed with the player worker 2026-10-27: the logic lives
## here, player.gd only calls it from the combat functions). Pure helpers + small player calls, no state of its own.
##   PlayerCombatMotion.react(self, from, knockback, heavy)   take_damage, flesh hit: the matching set-4 reaction
##   CombatChains.vary(...)                                    _start_swing: attack variety
## The rig's `attacking` flag follows CharacterAnimator.is_full_busy(), so a whole-body reaction already eases the foot lock.
## Dodges stay on the existing roll / back-step: the set-4 dodges are in-place (DodgeRight) or 2.7 s long (DodgeJumpBack)
## and would skate against the 0.5 s dodge travel; they wait for a root-motion dodge.

const Reactions := preload("res://scripts/combat/combat_reactions.gd")
const REACT_RATE := 1.2


## Plays the reaction that matches the blow (direction x strength). Returns false when the clip is missing (the caller
## keeps its old Hit_* clip).
static func react(p: Node, side: String, knockback: Vector3, heavy: bool) -> bool:
	var animator: Object = p.get("_animator")
	if animator == null:
		return false
	var kb := maxf(knockback.length(), Reactions.STAGGER_KNOCK if heavy else 0.0)
	var clip := Reactions.react(side, kb, false, randi())
	if not animator.call("has_clip", clip):
		return false
	if heavy:
		animator.call("play_full", clip, REACT_RATE)
	else:
		animator.call("play_upper", clip, REACT_RATE)     # light flinch: the legs keep the guard and the footwork
	return true


# --- root-motion dodge ----------------------------------------------------------------------------------------------

const CombatMotion := preload("res://scripts/combat/combat_motion.gd")
const DODGE_PLAY_S := 0.55          ## the trimmed clip plays in this long (the roll's travel, no lead-in)
## Metres the capsule covers per dodge clip (the clip's own travel is scaled to this, its speed curve is kept).
const DODGE_DIST := {"Mx4d_DodgeBack": 2.0, "Mx4d_RollForward": 2.7, "Mx4d_GuardDodgeBack": 1.8}


## The root-motion dodge clip for this dodge, or "" (the caller keeps its old roll).
static func dodge_clip(p: Node, backward: bool) -> String:
	var animator: Object = p.get("_animator")
	if backward:
		return back_dodge_clip(p)      # low longbow back-step, arms masked into the sword guard (Mx4d_DodgeBack hopped 0.5 m)
	var clip := "Mx4d_RollForward"
	return clip if animator != null and animator.call("has_clip", clip) else ""


static func dodge_rate(p: Node, clip: String) -> float:
	var animator: Object = p.get("_animator")
	return float(animator.call("clip_length", clip)) / DODGE_PLAY_S


## Capsule speed for `elapsed` seconds into the dodge: the clip's own root speed curve (accelerate, peak, settle), scaled
## to DODGE_DIST. `fallback` when the clip has no root track.
static func dodge_speed(p: Node, clip: String, elapsed: float, fallback: float) -> float:
	var animator: Object = p.get("_animator")
	var anim := CombatMotion.anim_of(animator, clip)
	if anim == null:
		return fallback
	return speed_from_profile(CombatMotion.profile(anim), float(animator.call("clip_length", clip)), float(DODGE_DIST.get(clip, 2.5)), elapsed)


## Pure (tests): horizontal root speed at `elapsed` of a clip played over DODGE_PLAY_S, scaled so the whole clip covers `dist`.
static func speed_from_profile(prof: PackedVector3Array, length: float, dist: float, elapsed: float) -> float:
	if prof.size() < 2 or length <= 0.0:
		return 0.0
	var total := Vector2(prof[prof.size() - 1].x, prof[prof.size() - 1].z).length()
	if total < 0.05:
		return 0.0
	var rate := length / DODGE_PLAY_S
	var t := clampf(elapsed * rate, 0.0, length)
	var dt := 1.0 / 30.0
	var a := CombatMotion.sample(prof, t)
	var b := CombatMotion.sample(prof, minf(t + dt, length))
	return Vector2(b.x - a.x, b.z - a.z).length() / dt * rate * (dist / total)


# --- masked back dodge ----------------------------------------------------------------------------------------------
## Mixamo has no sword / unarmed low back-dodge, only the longbow one. Built once at runtime into the shared clip library:
## the longbow dodge's legs, hips, spine and root travel (trimmed to its travel window) with the arms, clavicles, hands
## and fingers held in the sword-and-shield guard (Mx_SnS_Block_Idle frame 0): a data-level upper-body mask.
const BACK_SRC := "Mx_Bow_Dodge_Backward"
const BACK_GUARD := "Mx_SnS_Block_Idle"
const BACK_CLIP := "Mx4d_GuardDodgeBack"
const ARM_KEYS := ["clavicle", "upperarm", "lowerarm", "hand", "thumb", "index", "middle", "ring", "pinky", "weapon"]


static func back_dodge_clip(p: Node) -> String:
	var animator: Object = p.get("_animator")
	if animator == null:
		return ""
	var ap := animator.get("player") as AnimationPlayer
	if ap == null:
		return ""
	if ap.has_animation(BACK_CLIP):
		return BACK_CLIP
	if not ap.has_animation(BACK_SRC) or not ap.has_animation(BACK_GUARD):
		return ""
	var built := build_masked(ap.get_animation(BACK_SRC), ap.get_animation(BACK_GUARD))
	if built == null:
		return ""
	var lib := ap.get_animation_library("")
	if lib == null:
		return ""
	lib.add_animation(BACK_CLIP, built)
	return BACK_CLIP


## Pure (tests): `src` trimmed to its root-travel window (10 %..95 % of the horizontal travel, with 0.1 s lead-in), arm
## tracks replaced by `guard` at t = 0.
static func build_masked(src: Animation, guard: Animation) -> Animation:
	var prof := CombatMotion.profile(src)
	if prof.size() < 3:
		return null
	var total := Vector2(prof[prof.size() - 1].x, prof[prof.size() - 1].z).length()
	if total < 0.1:
		return null
	var t0 := -1.0
	var t1 := src.length
	for i in prof.size():
		var d := Vector2(prof[i].x, prof[i].z).length()
		if t0 < 0.0 and d >= total * 0.1:
			t0 = maxf(i / 30.0 - 0.1, 0.0)
		if d >= total * 0.95:
			t1 = minf(i / 30.0 + 0.1, src.length)
			break
	var out := Animation.new()
	out.length = t1 - t0
	for tr in src.get_track_count():
		var path := src.track_get_path(tr)
		var bone := String(path).get_slice(":", 1)
		var type := src.track_get_type(tr)
		if type != Animation.TYPE_POSITION_3D and type != Animation.TYPE_ROTATION_3D and type != Animation.TYPE_SCALE_3D:
			continue
		var nt := out.add_track(type)
		out.track_set_path(nt, path)
		out.track_set_enabled(nt, src.track_is_enabled(tr))
		var arm := ARM_KEYS.any(func(k: String) -> bool: return bone.begins_with(k))
		var gtr := guard.find_track(path, type) if arm else -1
		var f := 0
		while f / 30.0 <= out.length + 0.0001:
			var t := minf(f / 30.0, out.length)
			match type:
				Animation.TYPE_ROTATION_3D:
					var q := guard.rotation_track_interpolate(gtr, 0.0) if gtr >= 0 else src.rotation_track_interpolate(tr, t0 + t)
					out.rotation_track_insert_key(nt, t, q)
				Animation.TYPE_POSITION_3D:
					var v := guard.position_track_interpolate(gtr, 0.0) if gtr >= 0 else src.position_track_interpolate(tr, t0 + t)
					out.position_track_insert_key(nt, t, v)
				Animation.TYPE_SCALE_3D:
					out.scale_track_insert_key(nt, t, src.scale_track_interpolate(tr, t0 + t))
			f += 1
	return out
