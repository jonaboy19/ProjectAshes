class_name SoldierAaa
extends RefCounted
## Soldier / bandit use of the AAA mocap clips (docs/anim/aaa_wiring/). Pure helpers so soldier.gd keeps only call sites.
## Every function falls back ("" or an empty Dictionary) when the clip is not in the library, so the old behaviour stays.

const Moves := preload("res://scripts/combat/combat_moves.gd")
const Markers := preload("res://scripts/actors/combat_markers.gd")


static func _has(soldier: Node, clip: String) -> bool:
	var ap: Variant = soldier.get("_anim")
	return clip != "" and ap is AnimationPlayer and (ap as AnimationPlayer).has_animation(clip)


## {clip, contact (s at rate 1)} for the move the soldier is about to swing, or {} for the legacy Sword_Light_n path.
## After a block the riposte replaces the pick (within 1.5 s).
static func swing(soldier: Node, move: Resource, keep: Array, after_block: bool, pick: int) -> Dictionary:
	if move == null:
		return {}
	var two_hand := keep.has("2H_Sword")
	var clip := String(Moves.DUEL["riposte"]) if (after_block and not two_hand) else Moves.npc_swing(String(move.id), two_hand, pick)
	if not _has(soldier, clip):
		return {}
	var hits := Markers.hits_s(clip, 1.0)
	if hits.is_empty():
		return {}
	return {"clip": clip, "contact": hits[0]}


## Upper-body clip for a successful block: the duel parry (two-hand guard for greatsword carriers).
static func block_clip(soldier: Node, keep: Array) -> String:
	var clip := String(Moves.DUEL["two_hand_guard"] if keep.has("2H_Sword") else Moves.DUEL["parry"])
	return clip if _has(soldier, clip) else "Block_Hit"


## Light hit: a head-snap flinch 40 % of the time on a left or right hit, else the authored directional clip.
static func light_hit(soldier: Node, side: String, rng_value: float) -> String:
	if (side == "Left" or side == "Right") and rng_value < 0.4:
		var clip := "Hit_Head_L" if side == "Left" else "Hit_Head_R"
		if _has(soldier, clip):
			return clip
	return "Hit_Light_" + side


## Guard broken (a heavy blow): the stumble replaces the block flinch. Returns the seconds the soldier is staggered, or 0.
static func guard_break(soldier: Node, seconds: float) -> float:
	if not _has(soldier, String(Moves.DUEL["guard_break"])):
		return 0.0
	var animator: Variant = soldier.get("_animator")
	if animator != null:
		animator.call("play_full", String(Moves.DUEL["guard_break"]), 1.0)
	return maxf(seconds, 0.6)
