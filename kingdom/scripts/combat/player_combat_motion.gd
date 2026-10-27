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
const DODGE_DIST := {"Mx4d_DodgeBack": 2.0, "Mx4d_RollForward": 2.7}


## The root-motion dodge clip for this dodge, or "" (the caller keeps its old roll).
static func dodge_clip(p: Node, backward: bool) -> String:
	var animator: Object = p.get("_animator")
	if backward:
		return ""      # Mx4d_DodgeBack is a 0.5 m high hop: read as floating in review; the old back-step stays
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
