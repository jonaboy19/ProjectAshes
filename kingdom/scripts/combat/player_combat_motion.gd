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
