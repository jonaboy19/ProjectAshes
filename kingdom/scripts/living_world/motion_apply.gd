extends RefCounted
## Node-side half of the NPC motion layer (docs/plans/NPC_MOTION_RULES.md section 2, L-1): shared helpers for the per-body
## adapters (villager.gd, micro_actor.gd, follower_body.gd, soldier.gd). Each adapter keeps one MotionIntent + one motion
## state, refills them at its think rate with MotionRules.evaluate_into(), and applies a channel ONLY when a rule won it
## (intent "<channel>_rule" != ""): with every rule a stub the body behaves exactly as before the hook.
##   const MotionApply := preload("res://scripts/living_world/motion_apply.gd")

const LEAN_RATE := 3.0          # rad/s toward the intent's lean
const ARCH_GUARD_JOB := 3       # WorldSim.job index of guards (NpcWorld.WORK_IDS)
const ARCH_MERCHANT_JOB := 2


## Persona for MotionRules / ClipPicker from what a villager already knows about itself.
static func villager_persona(person: int, child: bool, elder: bool, job: int, gesture: float, mood: float) -> Dictionary:
	var arch := "villager"
	if child:
		arch = "child"
	elif elder:
		arch = "elder"
	elif job == ARCH_GUARD_JOB:
		arch = "guard"
	elif job == ARCH_MERCHANT_JOB:
		arch = "merchant"
	return {"archetype": arch, "id": person, "gesture": gesture, "mood": mood}


## Did any rule (not the base gait / defaults) write this channel?
static func won(intent: Dictionary, channel_rule: String) -> bool:
	return String(intent.get(channel_rule, "")) != ""


## Model-root roll toward the intent lean (no skeleton update). Returns the new roll.
static func lean(model: Node3D, target: float, delta: float) -> float:
	if model == null:
		return 0.0
	var r := move_toward(model.rotation.z, clampf(target, -0.35, 0.35), LEAN_RATE * delta)
	model.rotation.z = r
	return r


## Look target of the intent (Vector3.INF when no rule asked for one).
static func look_target(intent: Dictionary) -> Vector3:
	if int(intent.get("look_prio", 0)) <= 0:
		return Vector3.INF
	return Vector3(float(intent["look_x"]), float(intent["look_y"]), float(intent["look_z"]))


## Steering contribution: [offset (world XZ m/s), speed multiplier, stop]. Neutral unless a LOCO or BODY rule won.
static func steer(intent: Dictionary) -> Array:
	if not won(intent, "loco_rule") and not won(intent, "body_rule"):
		return [Vector2.ZERO, 1.0, false]
	return [Vector2(float(intent["steer_x"]), float(intent["steer_z"])), float(intent["speed_mul"]), bool(intent["stop"])]


## One body's motion state for the lighter adapters (micro_actor, follower_body, soldier): intent + rule state + ctx +
## persona + think timer, and the "only when a rule won" getters.
##   var _mr := MotionApply.Body.new({"archetype": "follower", "id": fid})
##   if _mr.due(delta):  _mr.ctx["speed"] = ...;  _mr.evaluate(MotionRules.TIER_NEAR)
##   var g := _mr.gait(anim)   # "" = keep the body's own clip
class Body extends RefCounted:
	var intent := MotionIntent.make()
	var state := MotionRules.new_state()
	var ctx := {}
	var persona := {}
	var _t := 0.0
	var _period := 0.3

	func _init(p: Dictionary, period := 0.3) -> void:
		persona = p
		_period = period
		_t = fmod(float(absi(int(p.get("id", 0)))) * 0.618034, 1.0) * period     # stagger the thinks

	func due(delta: float) -> bool:
		_t -= delta
		if _t > 0.0:
			return false
		_t += _period
		return true

	func evaluate(tier: int) -> void:
		ctx["now"] = Time.get_ticks_msec() * 0.001
		ctx["motion_state"] = state
		MotionRules.evaluate_into(intent, ctx, persona, tier)

	func gait(anim: AnimationPlayer) -> String:
		var g := String(intent["gait_clip"])
		return g if String(intent["loco_rule"]) != "" and anim != null and anim.has_animation(g) else ""

	func upper(anim: AnimationPlayer) -> String:
		var u := String(intent["upper_clip"])
		return u if String(intent["upper_rule"]) != "" and anim != null and anim.has_animation(u) else ""

	func stop() -> bool:
		return String(intent["body_rule"]) != "" and bool(intent["stop"]) or String(intent["loco_rule"]) != "" and bool(intent["stop"])

	func lean() -> float:
		return float(intent["lean"])

	func look() -> Vector3:
		if int(intent["look_prio"]) <= 0:
			return Vector3.INF
		return Vector3(float(intent["look_x"]), float(intent["look_y"]), float(intent["look_z"]))
