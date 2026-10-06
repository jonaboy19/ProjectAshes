extends Node
## Executes the equipped techniques (scripts/sim/skills.gd) for the player.
## Add it as a child of the player; it reads the loadout, checks cost and
## cooldown, pays stamina / qi / magicules, plays the clip on the player's
## CharacterAnimator (play_upper / play_full), spawns VFX and projectiles, and
## damages nodes in `enemy_group` through duck-typed
## `take_damage(amount, from, knockback)` like player.gd's melee.
##
##   player.add_child(preload("res://scripts/actors/technique_caster.gd").new())
##
## Keys: technique_1..4 (U, I, O, H unless the project binds them first).
## Touch: scripts/ui/technique_buttons.gd calls cast_slot().
##
## VFX: a technique's "vfx" id is called on scripts/vfx/vfx.gd when that static
## method exists (VFX.fireball, VFX.water_whip, ...). Arguments are matched by
## name and type: the world parent, origin / from / pos (Vector3), to / target
## (Vector3), dir (Vector3), radius / range / size (float), power / scale
## (float), speed (float, the technique's projectile speed), color (Color),
## element (String). Unmatched optional arguments keep
## their defaults. A projectile VFX may return the Node3D to fly: the caster
## moves it and frees it on impact (return null if it animates itself).
## Missing methods fall back to VFX.burst / VFX.slash.
##
## Orchestration lives in scripts/abilities/ability_runner.gd (the same runner NPC casters use): evaluate ->
## validate -> chant (seal pad) -> pay on release + cooldown -> windup -> execute (_resolve below) -> apply
## (effects by family on scripts/abilities/effect_set.gd). This node keeps what is scene-bound: input, the seal
## pad, animation, targeting queries, projectiles, VFX. Legacy techniques (data/skills) still pay and cool down
## through skills.gd (begin_cast) so every number is unchanged; path-tree techniques (data/powers) pay through
## power_paths.use (strain, risk, mastery). Chant-gated spells (magic path, with seals) open the seal pad unless the
## caster qualifies for chantless casting (PowerTrees.chantless_check), see cast_technique().

signal cast(id: String, def: Dictionary)
signal failed(id: String, reason: String)
## Utility techniques (harvest, repair, rain...) for other systems to act on.
signal technique_effect(id: String, effect: Dictionary, at: Vector3)
## Hand seals: a sealed technique waits for its sequence on the seal pad.
signal seals_started(id: String, sequence: Array)
signal seal_entered(index: int, seal: String, correct: bool)
signal seals_ended(id: String, success: bool)

const Skills := preload("res://scripts/sim/skills.gd")
const AbilityDef := preload("res://scripts/abilities/ability_def.gd")
const AbilityLib := preload("res://scripts/abilities/ability_lib.gd")
const Runner := preload("res://scripts/abilities/ability_runner.gd")
const EffectSet := preload("res://scripts/abilities/effect_set.gd")
const PowerTrees := preload("res://scripts/abilities/power_trees.gd")
const UtilityBrain := preload("res://scripts/population/utility_brain.gd")
const VFX_PATH := "res://scripts/vfx/vfx.gd"
const TechniqueVfx := preload("res://scripts/vfx/technique_vfx.gd")
const BendingLibrary := preload("res://scripts/actors/bending_library.gd")
const ProjectilePool := preload("res://scripts/vfx/projectile_pool.gd")
const SPECTACLE_SHAPES := ["projectile", "chain", "dash", "blink", "melee", "cone", "aoe", "target_aoe"]
const KEYS := {"technique_1": KEY_U, "technique_2": KEY_Y, "technique_3": KEY_O, "technique_4": KEY_H,
	"seal_1": KEY_4, "seal_2": KEY_5, "seal_3": KEY_6, "seal_4": KEY_7, "seal_5": KEY_8, "seal_6": KEY_9}
## Seconds to finish a whole seal sequence.
const SEAL_TIME := 3.5
## Arms-only loop shown while forming seals (first clip the rig has).
const SEAL_CLIPS := ["Magic_Casting", "Spell_Simple_Idle", "G6_channel_unarmed_magic"]
const HIT_RADIUS := 0.9          # projectile contact distance (m)
const DASH_DECEL := 12.0         # player.gd IMPULSE_DECEL: kick speed = sqrt(2 * decel * distance)
const DASH_WIDTH := 1.6
const BURN_TICK := 0.5
const CAST_LOCK := 0.3           # s between casts so taps do not stack (the runner's lockout)
const ELEMENT_COLORS := {
	"fire": Color(1.0, 0.45, 0.12), "water": Color(0.35, 0.75, 1.0), "wind": Color(0.85, 1.0, 0.95),
	"earth": Color(0.75, 0.55, 0.3), "lightning": Color(0.7, 0.8, 1.0), "qi": Color(1.0, 0.85, 0.35),
	"metal": Color(0.92, 0.94, 1.0), "shadow": Color(0.55, 0.4, 1.0), "wood": Color(0.55, 0.9, 0.4),
	"none": Color(1.0, 0.9, 0.7),
}
## Life-path action tags recorded per tree (archetypes read them).
const TRAINING_TAGS := {"swordsmanship": "trained_sword", "iaido": "trained_sword", "fist_palm": "trained_fist",
	"qi": "meditated", "shadow": "sneaked", "command": "patrolled", "crafting": "crafted", "farming": "farmed"}

var player: Node3D
var skills: RefCounted
var enemy_group := "team1"
var ally_group := "team0"

var _vfx_info: Dictionary = {}   # method name -> script method info
## Loaded untyped so calls to methods the VFX agent adds later resolve at runtime.
var _vfx_script: Script
var _projectiles: Array = []
## The one lifecycle shared with NPC casters (hooks wired in _init).
var runner: RefCounted
## Effects on targets we hit (burns...): instance id -> {node, set}.
var _boards: Dictionary = {}
var _ability_cache: Dictionary = {}
var _seal_target: Node3D
var _seal_id := ""
var _seal_seq: Array = []
var _seal_pos := 0
var _seal_time := 0.0
var _body_action_id := 0   # Invalidates delayed strikes when the body action is replaced.
var _body_followups: Array[Dictionary] = []


func _init() -> void:
	name = "TechniqueCaster"
	runner = Runner.new()
	# One body, one cast pose: never release an older technique beneath a new clip.
	runner.overlap_windups = false
	runner.hooks = {
		"lookup": _lookup, "known": _hook_known, "blocked": _blocked, "pools": _hook_pools,
		"numbers": _hook_numbers, "commit": _hook_commit, "cooldown_left": _hook_cooldown_left,
		"cooldown_set": _hook_cooldown_set, "fizzle": _hook_fizzle, "profile": _hook_profile,
		"execute": _hook_execute,
	}


func _ready() -> void:
	if player == null:
		player = get_parent() as Node3D
	if skills == null:
		skills = find_skills(self)
	_vfx_script = load(VFX_PATH)
	for m: Dictionary in _vfx_script.get_script_method_list():
		_vfx_info[String(m["name"])] = m
	_bind_technique_vfx()
	for action: String in KEYS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var ev := InputEventKey.new()
			ev.physical_keycode = KEYS[action]
			InputMap.action_add_event(action, ev)


## The shared technique timing template (anticipation, flash, limb glow, travel, impact, residue) listens to the
## runner; techniques with their own VFX method keep their bespoke travel and impact (scripts/vfx/technique_vfx.gd).
func _bind_technique_vfx() -> void:
	var tv: Node = TechniqueVfx.new()
	tv.name = "TechniqueVfx"
	add_child(tv)
	tv.bind_runner(runner, {
		"origin": _origin, "aim": _aim, "world": _world,
		"is_player": func() -> bool: return player != null and player == Life.player,
		"skeleton_root": player,
		"action_paused": _action_paused,
		"bespoke": func(def: Dictionary) -> bool:
			var v := String(def.get("vfx", ""))
			return v != "" and _vfx_info.has(v),
	})


## Life's skills when Life owns them (so they are saved), else a fresh set.
static func find_skills(from: Node) -> RefCounted:
	var life := from.get_node_or_null("/root/Life") if from.is_inside_tree() else null
	if life:
		var s: Variant = life.get("skills")
		if s is RefCounted:
			return s
	return Skills.new()


func _unhandled_input(event: InputEvent) -> void:
	if is_sealing():
		for i in Skills.SEALS.size():
			if event.is_action_pressed("seal_%d" % (i + 1)):
				input_seal(Skills.SEALS[i])
				get_viewport().set_input_as_handled()
				return
	for i in Skills.ACTIVE_SLOTS:
		if event.is_action_pressed("technique_%d" % (i + 1)):
			cast_slot(i)
			get_viewport().set_input_as_handled()
			return


## Ask the impact-pause owner; an inactive tree can have other causes.
func _action_paused() -> bool:
	if not is_instance_valid(player):
		return false
	var pause_owner: Variant = player.get("_impact_pause")
	var animator: Variant = player.get("_animator")
	if not is_instance_valid(pause_owner) or not is_instance_valid(animator):
		return false
	var mixer: Variant = animator.get("tree")
	return mixer is AnimationMixer and pause_owner.has_method("is_paused") and bool(pause_owner.call("is_paused", mixer))


func _physics_process(delta: float) -> void:
	if is_sealing():
		_seal_time -= delta
		if _seal_time <= 0.0:
			runner.chant_complete(false)       # fizzle: the technique rests briefly (skills.fizzle)
			_say("The seals slip apart.")
			_end_seals(false)
	if skills:
		skills.tick(delta)
	var action_delta := 0.0 if _action_paused() else delta
	# Advance existing strikes first: a release in runner.update starts at time zero.
	_update_body_followups(action_delta)
	for ev: Dictionary in runner.update(delta, action_delta):    # effects on the caster itself
		if String(ev["kind"]) == "hot" and player != null and player.has_method("heal"):
			player.call("heal", int(ev["amount"]))
	_update_projectiles(delta)
	_update_boards(delta)


# --- casting -------------------------------------------------------------------

## What the player can pay right now (qi lives in skills).
func pools() -> Dictionary:
	var out := {"stamina": 0.0, "magicules": 0.0}
	if player and player.get("stamina") != null:
		out["stamina"] = float(player.get("stamina"))
	var mag := _magicules()
	if mag:
		out["magicules"] = float(mag.call("spendable"))
	if skills:
		out["qi"] = skills.qi
	return out


func can_cast_slot(slot: int) -> Dictionary:
	var id := String(skills.loadout[slot]) if skills and slot >= 0 and slot < skills.loadout.size() else ""
	if id == "":
		return {"ok": false, "reason": "Empty slot."}
	return runner.can_use(id)


## `with_seals`: sealed techniques open the seal pad first (touch); without it
## they fire at once and miss the seal bonus (keyboard).
func cast_slot(slot: int, with_seals := false) -> Dictionary:
	if skills == null or slot < 0 or slot >= skills.loadout.size():
		return {"ok": false, "reason": "No technique."}
	var id := String(skills.loadout[slot])
	if with_seals and id != "" and skills.needs_seals(id):
		return begin_seals(id)
	return cast_technique(id)


# --- hand seals ----------------------------------------------------------------

func is_sealing() -> bool:
	return _seal_id != ""


func seal_sequence() -> Array:
	return _seal_seq.duplicate()


func seal_progress() -> int:
	return _seal_pos


func seal_time_left() -> float:
	return maxf(0.0, _seal_time)


func begin_seals(id: String) -> Dictionary:
	if is_sealing():
		cancel_seals()
	var ab := _lookup(id)
	var target := _pick_target(AbilityDef.flat(ab)) if not ab.is_empty() else null
	var r: Dictionary = runner.begin(id, {"force_chant": true, "chantless": false, "target": target})
	if not r["ok"]:
		failed.emit(id, String(r["reason"]))
		return r
	if String(r.get("phase", "")) != "chant":
		_after_commit(id, r, target)         # nothing to chant: it fired
		return r
	_seal_id = id
	_seal_seq = (r.get("seals", []) as Array).duplicate()
	_seal_pos = 0
	_seal_time = SEAL_TIME
	_seal_target = target
	var anim: Variant = player.get("_animator")
	var ap: Variant = (anim as Object).get("player") if anim != null else null
	if ap is AnimationPlayer:
		for clip: String in SEAL_CLIPS:
			if (ap as AnimationPlayer).has_animation(clip):
				anim.call("play_upper", clip, 1.0)
				break
	seals_started.emit(id, _seal_seq.duplicate())
	return {"ok": true, "reason": "", "sealing": true}


## One seal from the pad or keys 4-9. A wrong seal breaks the sequence.
func input_seal(seal: String) -> void:
	if not is_sealing():
		return
	var correct := _seal_pos < _seal_seq.size() and String(_seal_seq[_seal_pos]) == seal
	seal_entered.emit(_seal_pos, seal, correct)
	if not correct:
		runner.chant_complete(false)
		_say("Wrong seal. The technique fizzles.")
		_end_seals(false)
		return
	_seal_pos += 1
	if _seal_pos >= _seal_seq.size():
		var id := _seal_id
		var target := _seal_target
		_end_seals(true)
		var r: Dictionary = runner.chant_complete(true, true)
		if r["ok"]:
			_after_commit(id, r, target)
		else:
			failed.emit(id, String(r["reason"]))


func cancel_seals() -> void:
	if is_sealing():
		runner.cancel()
		_end_seals(false)


func _end_seals(success: bool) -> void:
	var id := _seal_id
	_seal_id = ""
	_seal_seq = []
	_seal_pos = 0
	_seal_time = 0.0
	_seal_target = null
	seals_ended.emit(id, success)


## Called when a hit reaction, guard break or death takes control of the body.
## Released projectiles and existing target effects remain independent.
func interrupt_cast(reason := "interrupted") -> void:
	_body_action_id += 1
	_body_followups.clear()
	var changed: bool = runner.interrupt_all(reason)
	if changed and is_instance_valid(player):
		var animator: Variant = player.get("_animator")
		if is_instance_valid(animator):
			animator.call("stop_upper")
			animator.call("stop_full")
	if is_sealing():
		_end_seals(false)


## Casts a technique (legacy skills.gd tree or data/powers path tree). Chant-gated spells (magic path, seals) need
## the chant unless the caster qualifies for chantless casting: then they fire at once, otherwise the seal pad opens.
func cast_technique(id: String, sealed := false) -> Dictionary:
	if id == "":
		failed.emit(id, "Empty slot.")
		return {"ok": false, "reason": "Empty slot."}
	var ab := _lookup(id)
	if ab.is_empty():
		failed.emit(id, "Not learned.")
		return {"ok": false, "reason": "Not learned."}
	var opts := {"sealed": sealed}
	if AbilityDef.is_chant(ab) and not sealed:
		if not bool(runner.chantless_allowed(ab)["ok"]):
			return begin_seals(id)
		opts["chantless"] = true
	var flat := AbilityDef.flat(ab)
	var target := _pick_target(flat)
	opts["target"] = target
	var r: Dictionary = runner.begin(id, opts)
	if not r["ok"]:
		failed.emit(id, String(r["reason"]))
		return r
	if String(r.get("phase", "")) == "chant":
		return r
	_after_commit(id, r, target)
	return r


## Same entry point under the path-tree name.
func cast_ability(id: String, sealed := false) -> Dictionary:
	return cast_technique(id, sealed)


## What the legacy cast did after paying: face the target, play the clip, train, announce.
func _after_commit(id: String, r: Dictionary, target: Node3D) -> void:
	# Zero-windup casts already executed inside runner.begin; keep their new strikes.
	if float(r.get("windup", 0.0)) > 0.0:
		_body_action_id += 1
		_body_followups.clear()
	var def: Dictionary = r["def"]
	if target:
		_face(target.global_position)
	_play_clip(def)
	if String((r["ability"] as Dictionary).get("source", "")) == "legacy":
		_train(def)
	cast.emit(id, def)
	if player != null and player == Life.player:
		Life.on_technique_cast(id, def, target != null)


func _blocked() -> String:
	if player == null or not is_instance_valid(player):
		return "No body."
	if _flag(player, "dead"):
		return "Dead."
	for state: String in ["_stunned", "_flinch"]:
		var remaining: Variant = player.get(state)
		if remaining != null and float(remaining) > 0.0:
			return "Recovering from a hit."
	for state: String in ["_swing", "_dodge", "_land_time"]:
		var remaining: Variant = player.get(state)
		if remaining != null and float(remaining) > 0.0:
			return "Finish the current action."
	if _flag(player, "_jump_starting") or _flag(player, "_jump_active"):
		return "Jumping."
	if _flag(player, "swimming"):
		return "Swimming."
	if player.has_method("is_mounted") and player.call("is_mounted"):
		return "Mounted."
	return ""


# --- runner hooks ---------------------------------------------------------------

## The ability for an id: the live skills.gd trees first (so runtime add_tree works), else the path trees.
func _lookup(id: String) -> Dictionary:
	if skills != null and skills.techniques.has(id):
		var t: Dictionary = skills.techniques[id]
		var c: Variant = _ability_cache.get(id)
		if c == null or not is_same((c as Dictionary)["t"], t):
			c = {"t": t, "ab": AbilityDef.from_technique(t)}
			_ability_cache[id] = c
		return (c as Dictionary)["ab"]
	return PowerTrees.ability(id)


func _is_legacy(def: Dictionary) -> bool:
	return String(def.get("source", "")) == "legacy"


func _life() -> Node:
	return get_node_or_null("/root/Life")


func _pp() -> Object:
	var life := _life()
	if life == null or life.get("realm") == null:
		return null
	var hub: Variant = life.get("realm")
	if hub is Object and (hub as Object).has_method("mod") and (hub.get("mods") as Dictionary).has("power_paths"):
		return hub.mod("power_paths")
	return null


func _hook_known(id: String) -> bool:
	if skills != null and skills.techniques.has(id):
		return skills.is_learned(id)
	var pp := _pp()
	return pp != null and bool(pp.call("knows_technique", id))


func _hook_pools(def: Dictionary) -> Dictionary:
	if _is_legacy(def):
		return pools()
	# Path-tree techniques are checked and paid by power_paths itself (commit).
	var out := {}
	for r: String in (def["costs"] as Dictionary):
		out[r] = 1.0e9
	return out


func _hook_numbers(id: String, def: Dictionary) -> Dictionary:
	if not _is_legacy(def) or skills == null:
		return {}
	var res := String(AbilityDef.flat(def)["resource"])
	return {"costs": {res: skills.cost_of(id)}, "cooldown": skills.cooldown_of(id), "damage": skills.damage_of(id)}


## Legacy: skills.gd pays qi, starts the cooldown and computes damage; the caster pays stamina / magicules.
## Path tree: power_paths.use (pool, strain, risk, mastery, second-path penalty).
func _hook_commit(id: String, def: Dictionary, sealed: bool, _numbers: Dictionary, opts: Dictionary) -> Dictionary:
	if _is_legacy(def):
		var r: Dictionary = skills.begin_cast(id, pools(), sealed)
		if r["ok"]:
			_pay(String(r["resource"]), float(r["cost"]))
		return r
	var pp := _pp()
	if pp == null:
		return {"ok": false, "reason": "You walk no power path."}
	var path := String(def.get("path", ""))
	var pc := AbilityDef.primary_cost(def)
	var ctx := {"life": _life(), "technique": id, "path_penalty": true,
		"chantless": bool(opts.get("chantless", false)), "element": String(def.get("element", ""))}
	var chk: Dictionary = pp.call("can_use", path, float(pc["amount"]), ctx)
	if not chk["ok"]:
		return {"ok": false, "reason": String(chk["reason"])}
	var res: Dictionary = pp.call("use", path, float(pc["amount"]), ctx)
	if not res["ok"]:
		return {"ok": false, "reason": String((res["messages"] as Array)[0]) if not (res["messages"] as Array).is_empty() else "Cannot cast."}
	for m: Variant in res["messages"]:
		_say(String(m))
	for e: Dictionary in res["effects"]:
		if String(e.get("type", "")) == "damage" and player != null and player.has_method("set_health"):
			player.call("set_health", int(player.get("health")) - int(e["amount"]))
	skills.cooldowns[id] = float(def["cooldown"])
	var dmg := int(round(float(def["damage"]) * float(res["power"])))
	if sealed and not ((def["cast"] as Dictionary)["seals"] as Array).is_empty():
		dmg = int(round(dmg * (1.0 + AbilityDef.SEAL_BONUS)))
	return {"ok": true, "reason": "", "resource": String(pc["resource"]), "cost": float(chk.get("cost", pc["amount"])),
		"cooldown": float(def["cooldown"]), "damage": dmg}


func _hook_cooldown_left(id: String) -> float:
	return skills.cooldown_left(id) if skills != null else 0.0


func _hook_cooldown_set(id: String, seconds: float) -> void:
	if skills != null:
		skills.cooldowns[id] = seconds


func _hook_fizzle(id: String, seconds: float) -> void:
	if skills != null:
		skills.fizzle(id, seconds)


func _hook_profile() -> Dictionary:
	var pp := _pp()
	return pp.call("profile") if pp != null else {}


func _hook_execute(_def: Dictionary, cast_info: Dictionary) -> void:
	_body_action_id += 1
	_body_followups.clear()
	_resolve(String(cast_info["id"]), cast_info["def"], int(cast_info["damage"]), cast_info["target"] as Node3D)


func _pay(resource: String, cost: float) -> void:
	if cost <= 0.0:
		return
	match resource:
		"stamina":
			player.set("stamina", maxf(0.0, float(player.get("stamina")) - cost))
			if player.get("_stamina_delay") != null:
				player.set("_stamina_delay", 0.8)
		"magicules":
			var mag := _magicules()
			if mag == null:
				return
			var res: Dictionary = mag.call("spend", cost)
			if int(res.get("damage", 0)) > 0 and player.has_method("set_health"):
				player.call("set_health", int(player.get("health")) - int(res["damage"]))
			if String(res.get("text", "")) != "":
				_say(String(res["text"]))


func _magicules() -> Object:
	var life := get_node_or_null("/root/Life")
	if life == null:
		return null
	var m: Variant = life.get("magicules")
	return m if m is Object and (m as Object).has_method("spend") else null


func _train(def: Dictionary) -> void:
	# Using techniques is also cultivation.
	if def["resource"] != "stamina":
		skills.cultivate(0.5)
	var tag: String = TRAINING_TAGS.get(String(def["tree"]), "")
	var life := get_node_or_null("/root/Life")
	if tag != "" and life and life.has_method("record"):
		life.call("record", tag, 0.2)


static func _flag(o: Object, prop: String) -> bool:
	var v: Variant = o.get(prop)
	return v is bool and v


func _say(text: String) -> void:
	var game := get_node_or_null("/root/Game")
	if game and game.has_method("say"):
		game.call("say", text)


# --- animation -----------------------------------------------------------------

func _play_clip(def: Dictionary) -> void:
	var anim: Variant = player.get("_animator")
	if anim == null:
		return
	var ap: Variant = (anim as Object).get("player")
	if ap is AnimationPlayer:
		# First clip of the preference list the rig has (bending clips install on demand, new imports first,
		# stock UAL last). BendingLibrary.play_cast uses the same upper / full OneShot slots as before and
		# only retimes the clip so its strike lands on the technique's windup.
		BendingLibrary.play_cast(anim, def, _fallback_clip(def))
		return
	var speed := float(def["anim_speed"])
	if String(def["anim_mode"]) == "full":
		anim.call("play_full", String(def["anim"]), speed)
	else:
		anim.call("play_upper", String(def["anim"]), speed)


func _fallback_clip(def: Dictionary) -> String:
	match String(def["tree"]):
		"swordsmanship", "iaido":
			return "Sword_Attack"
		"fist_palm":
			return "Punch_Cross"
		"crafting", "farming", "command":
			return "Interact"
	return "Spell_Simple_Shoot"


# --- targeting -----------------------------------------------------------------

func _origin() -> Vector3:
	var k := 1.0
	var life := get_node_or_null("/root/Life")
	if life and life.has_method("body_scale"):
		k = float(life.call("body_scale"))
	return player.global_position + Vector3(0, 1.2 * k, 0)


func _aim() -> Vector3:
	var fwd := Vector3.FORWARD
	if int(player.get("view") if player.get("view") != null else 1) == 0 and player.has_method("forward"):
		fwd = player.call("forward")
	elif player.has_method("facing"):
		fwd = player.call("facing")
	fwd.y = 0.0
	return fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD


func enemies() -> Array[Node3D]:
	var out: Array[Node3D] = []
	if not is_inside_tree():
		return out
	for n in get_tree().get_nodes_in_group(enemy_group):
		if n is Node3D and is_instance_valid(n) and n.has_method("take_damage") and not _flag(n, "dead"):
			out.append(n)
	return out


## Lock-on target, else the nearest enemy in range roughly in front, else the
## nearest in range at all (for targeted shapes).
func _pick_target(def: Dictionary) -> Node3D:
	var lock: Variant = player.get("_lock")
	var reach := float(def["range"]) * 1.2
	if lock is Node3D and is_instance_valid(lock) and (lock as Node3D).global_position.distance_to(player.global_position) <= maxf(reach, 4.0):
		return lock
	var fwd := _aim()
	var best: Node3D = null
	var best_d := reach
	var any: Node3D = null
	var any_d := reach
	for e in enemies():
		var to := e.global_position - player.global_position
		to.y = 0.0
		var d := to.length()
		if d < best_d and fwd.dot(to / maxf(d, 0.01)) > 0.3:
			best_d = d
			best = e
		if d < any_d:
			any_d = d
			any = e
	if best:
		return best
	return any if String(def["shape"]) in ["target_aoe", "chain", "blink"] else null


func _face(p: Vector3) -> void:
	var model: Variant = player.get("_model")
	var to := p - player.global_position
	if model is Node3D and Vector2(to.x, to.z).length() > 0.05:
		(model as Node3D).rotation.y = atan2(to.x, to.z)


# --- resolution ----------------------------------------------------------------

func _resolve(id: String, def: Dictionary, dmg: int, target: Node3D) -> void:
	if not is_inside_tree() or player == null or not is_instance_valid(player) or _flag(player, "dead"):
		return
	if target != null and not is_instance_valid(target):
		target = null
	var shape := String(def["shape"])
	var hits := maxi(1, int(def["hits"]))
	match shape:
		"projectile":
			_launch(def, dmg, target)
		"chain":
			_chain(def, dmg, target)
		"dash":
			_dash(def, dmg)
		"blink":
			_blink(def, dmg, target)
		"buff", "utility":
			_support(id, def)
		_:
			for h in hits:
				if h == 0:
					_area(def, dmg, target, h == hits - 1)
				elif shape in ["melee", "cone"]:
					_body_followups.append({"left": float(def["hit_interval"]) * h,
						"def": def, "damage": dmg, "target": target, "last": h == hits - 1, "action": _body_action_id})
				else:
					get_tree().create_timer(float(def["hit_interval"]) * h).timeout.connect(
						_area_followup.bind(def, dmg, target, h == hits - 1, _body_action_id))
	if SPECTACLE_SHAPES.has(shape):
		# The flash/projectile is an explicit local spectacle, not proof that a
		# particular villager saw the caster or identified a target.
		var here := player.global_position
		UtilityBrain.notice(Vector2(here.x, here.z), 0.72, 6.0)
		# This resolved combat action is also loud enough to be heard nearby;
		# the acoustic event carries no caster/target identity.
		var sound_level := 0.85
		var sound_radius := 28.0
		var sound_lifetime := 4.5
		match shape:
			"melee":
				sound_level = 0.55
				sound_radius = 12.0
				sound_lifetime = 2.2
			"dash":
				sound_level = 0.75
				sound_radius = 22.0
				sound_lifetime = 3.5
			"blink":
				sound_level = 0.65
				sound_radius = 18.0
				sound_lifetime = 2.5
			"aoe", "target_aoe", "cone":
				sound_level = 0.95
				sound_radius = 32.0
				sound_lifetime = 5.0
		UtilityBrain.sound_notice(Vector2(here.x, here.z), sound_level, sound_radius, sound_lifetime)
	if shape in ["aoe", "target_aoe", "cone"] and def["effect"].has("buff"):
		_support(id, def)


## melee / cone / aoe / target_aoe: one volley of hits.
func _update_body_followups(delta: float) -> void:
	if delta <= 0.0 or _body_followups.is_empty():
		return
	var due: Array[Dictionary] = []
	for strike: Dictionary in _body_followups:
		strike["left"] = float(strike["left"]) - delta
		if float(strike["left"]) <= 0.0:
			due.append(strike)
	for strike: Dictionary in due:
		_body_followups.erase(strike)
		var target: Variant = strike["target"]
		_area_followup(strike["def"], int(strike["damage"]), target if is_instance_valid(target) else null,
			bool(strike["last"]), int(strike["action"]))


func _area_followup(def: Dictionary, dmg: int, target: Node3D, last: bool, action_id: int) -> void:
	if not is_instance_valid(player) or _flag(player, "dead"):
		return
	# Remote released area effects are independent; close-range combo strikes
	# still belong to the body animation that launched them.
	if String(def["shape"]) in ["melee", "cone"] and action_id != _body_action_id:
		return
	_area(def, dmg, target if is_instance_valid(target) else null, last)


## melee / cone / aoe / target_aoe: one volley of hits.
func _area(def: Dictionary, dmg: int, target: Node3D, last: bool) -> void:
	if not is_inside_tree() or not is_instance_valid(player):
		return
	var shape := String(def["shape"])
	var fwd := _aim()
	var here := player.global_position
	var center := here
	var radius := float(def["radius"])
	var min_dot := -2.0
	match shape:
		"melee":
			radius = float(def["range"])
			min_dot = 0.2
		"cone":
			radius = float(def["range"])
			min_dot = cos(deg_to_rad(float(def["angle"]) * 0.5))
		"target_aoe":
			if target and is_instance_valid(target):
				center = target.global_position
			else:
				center = here + fwd * minf(float(def["range"]), 6.0)
	var to_vfx := center if shape == "target_aoe" else here + fwd * minf(radius, 4.0)
	if shape == "aoe":
		to_vfx = here
	if last or int(def["hits"]) <= 1 or shape != "target_aoe":
		_vfx(def, _origin(), to_vfx + Vector3(0, 0.1, 0), maxf(radius, 1.0), 1.0 if last else 0.6)
	for e in enemies():
		var to := e.global_position - center
		to.y = 0.0
		var d := to.length()
		if d > radius + 0.4:
			continue
		if min_dot > -1.5 and fwd.dot(to / maxf(d, 0.01)) < min_dot and d > 0.8:
			continue
		var push := to / maxf(d, 0.01) if d > 0.05 else fwd
		_hit(e, dmg, push, def)


func _launch(def: Dictionary, dmg: int, target: Node3D) -> void:
	var origin := _origin() + _aim() * 0.6
	var dir := _aim()
	if target and is_instance_valid(target):
		var aim_at := target.global_position + Vector3(0, 0.9, 0)
		dir = (aim_at - origin).normalized()
	var n := maxi(1, int(def["count"]))
	var spread := deg_to_rad(float(def["spread"]))
	for i in n:
		var off := 0.0 if n == 1 else lerpf(-spread, spread, i / float(n - 1))
		var d := dir.rotated(Vector3.UP, off)
		var to := origin + d * float(def["range"])
		var visual: Variant = _vfx(def, origin, to, float(def["radius"]), 1.0, true)
		var node: Node3D = visual if visual is Node3D else _orb(def)
		if node != null:
			node.global_position = origin     # null: every pooled orb is in flight, the cast still travels and hits unseen
		_projectiles.append({"node": node, "pos": origin, "dir": d, "left": float(def["range"]),
			"speed": float(def["speed"]), "def": def, "dmg": dmg, "hit": {}})


## Plain glowing orb when the VFX library has no projectile for this id: a pooled node (projectile_pool.gd),
## null when the pool's orbs are all in flight.
func _orb(def: Dictionary) -> Node3D:
	var col: Color = ELEMENT_COLORS.get(String(def["element"]), ELEMENT_COLORS["qi"])
	return ProjectilePool.at(_world()).acquire_orb(col)


## Pool nodes go back to the pool; VFX-library nodes are freed as before.
func _free_projectile(node: Node3D) -> void:
	if not is_instance_valid(node):
		return
	if is_inside_tree() and ProjectilePool.at(_world()).release_node(node):
		return
	node.queue_free()


func _update_projectiles(delta: float) -> void:
	for p: Dictionary in _projectiles.duplicate():
		var def: Dictionary = p["def"]
		var step := float(p["speed"]) * delta
		var pos: Vector3 = p["pos"] + (p["dir"] as Vector3) * step
		p["pos"] = pos
		p["left"] = float(p["left"]) - step
		var node: Node3D = p["node"]
		if is_instance_valid(node):
			node.global_position = pos
		var done := float(p["left"]) <= 0.0
		for e in enemies():
			if (p["hit"] as Dictionary).has(e.get_instance_id()):
				continue
			var c := e.global_position + Vector3(0, 0.8, 0)
			if Vector2(c.x - pos.x, c.z - pos.z).length() <= HIT_RADIUS and absf(c.y - pos.y) < 1.6:
				p["hit"][e.get_instance_id()] = true
				_hit(e, int(p["dmg"]), p["dir"], def)
				if not bool(def["pierce"]):
					done = true
					break
		if done:
			_projectiles.erase(p)
			if float(def["radius"]) > 0.0:
				_explode(def, int(p["dmg"]), pos, p["hit"])
			elif is_inside_tree():
				VFX.sparks(_world(), pos, ELEMENT_COLORS.get(String(def["element"]), ELEMENT_COLORS["qi"]), 14)
			_free_projectile(node)


func _explode(def: Dictionary, dmg: int, at: Vector3, already: Dictionary) -> void:
	if not is_inside_tree():
		return
	VFX.burst(_world(), at - Vector3(0, 0.6, 0), _burst_element(def), 0.6)
	for e in enemies():
		if already.has(e.get_instance_id()):
			continue
		var to := e.global_position - at
		to.y = 0.0
		if to.length() <= float(def["radius"]):
			_hit(e, int(dmg * 0.7), to.normalized(), def)


func _chain(def: Dictionary, dmg: int, target: Node3D) -> void:
	var first := target
	if first == null or not is_instance_valid(first):
		return
	var from := _origin()
	var hit := {}
	var cur := first
	var amount := float(dmg)
	for i in int(def["chains"]) + 1:
		var to := cur.global_position + Vector3(0, 0.9, 0)
		_vfx(def, from, to, 1.0, 1.0)
		hit[cur.get_instance_id()] = true
		_hit(cur, int(amount), (to - from).normalized(), def)
		amount *= 0.85
		from = to
		var nxt: Node3D = null
		var best := float(def["chain_range"])
		for e in enemies():
			if hit.has(e.get_instance_id()):
				continue
			var d := e.global_position.distance_to(cur.global_position)
			if d < best:
				best = d
				nxt = e
		if nxt == null:
			break
		cur = nxt


func _dash(def: Dictionary, dmg: int) -> void:
	var fwd := _aim()
	var start := player.global_position
	var dist := float(def["range"])
	if player.has_method("_kick"):
		player.call("_kick", fwd * sqrt(2.0 * DASH_DECEL * dist))
	if player.get("_invulnerable") != null:
		player.set("_invulnerable", maxf(float(player.get("_invulnerable")), 0.3))
	_vfx(def, start + Vector3(0, 0.8, 0), start + fwd * dist + Vector3(0, 0.8, 0), DASH_WIDTH, 1.0)
	if dmg <= 0:
		return
	for e in enemies():
		var p := e.global_position
		var closest := Geometry3D.get_closest_point_to_segment(p, start, start + fwd * dist)
		if Vector2(p.x - closest.x, p.z - closest.z).length() <= DASH_WIDTH:
			_hit(e, dmg, fwd, def)


func _blink(def: Dictionary, dmg: int, target: Node3D) -> void:
	if target == null or not is_instance_valid(target):
		_dash(def, dmg)
		return
	var away := target.global_position - player.global_position
	away.y = 0.0
	var dir := away.normalized() if away.length() > 0.05 else _aim()
	var from := player.global_position
	_vfx(def, from + Vector3(0, 0.9, 0), from + Vector3(0, 0.9, 0), 1.2, 0.6)
	player.global_position = target.global_position + dir * 1.3
	_face(target.global_position)
	var mult := 1.0 + float(skills.effects().get("backstab", 0.0))
	_vfx(def, player.global_position + Vector3(0, 0.9, 0), target.global_position + Vector3(0, 0.9, 0), 1.2, 1.0)
	_hit(target, int(dmg * mult), dir, def)


## buff / utility: heal, stamina, qi, timed buffs, allies in radius, events.
func _support(id: String, def: Dictionary) -> void:
	var fx: Dictionary = def["effect"]
	var here := player.global_position
	if String(def["shape"]) in ["buff", "utility"]:
		_vfx(def, _origin(), here, maxf(float(def["radius"]), 1.5), 1.0)
	var rank := maxi(1, int(skills.rank_of(id)))
	var k := 1.0 + Skills.RANK_DAMAGE * (rank - 1)
	var targets: Array[Node] = [player]
	if float(def["radius"]) > 0.0 and is_inside_tree():
		for a in get_tree().get_nodes_in_group(ally_group):
			if a != player and a is Node3D and (a as Node3D).global_position.distance_to(here) <= float(def["radius"]):
				targets.append(a)
	for t in targets:
		if fx.has("heal") and t.has_method("heal"):
			t.call("heal", int(float(fx["heal"]) * k))
		if fx.has("stamina") and t.get("stamina") != null:
			var cap := float(t.get("MAX_STAMINA")) if t.get("MAX_STAMINA") != null else 100.0
			t.set("stamina", minf(cap, float(t.get("stamina")) + float(fx["stamina"]) * k))
	if fx.has("buff") and not (fx["buff"] as Dictionary).is_empty():
		skills.add_buff(fx["buff"], float(fx.get("duration", 6.0)), id)
	var ab := _lookup(id)
	if not ab.is_empty() and not _is_legacy(ab):
		# Path-tree techniques keep wards, auras and heal-over-time as effects on the caster (by family).
		runner.apply_effects(ab, 0, runner.effects, "self", 1.0, id)
	if String(def["shape"]) == "utility" or fx.has("harvest") or fx.has("repair") or fx.has("water_crops") or fx.has("reveal"):
		technique_effect.emit(id, fx, here)


func _hit(e: Node3D, amount: int, dir: Vector3, def: Dictionary) -> void:
	if not is_instance_valid(e) or not e.has_method("take_damage"):
		return
	var fx: Dictionary = def["effect"]
	if amount > 0:
		var crit := randf() < float(skills.effects().get("crit_chance", 0.0))
		var dmg := int(amount * (1.5 if crit else 1.0))
		var push := Vector3(dir.x, 0.0, dir.z).normalized() * float(def["knockback"])
		e.call("take_damage", dmg, player, push)
		if is_inside_tree():
			VFX.sparks(_world(), e.global_position + Vector3(0, 0.9, 0),
				ELEMENT_COLORS.get(String(def["element"]), ELEMENT_COLORS["qi"]), 22 if crit else 12)
		var shake: Variant = player.get("_shake")
		if shake is Object and (shake as Object).has_method("add"):
			shake.call("add", 0.12)
	# Riders (burn, stun, slow...) go on the target's effect board by family and stacking rule; crowd control is
	# also passed to actors that support it (duck-typed; ignored otherwise).
	var ab := _lookup(String(def.get("id", "")))
	if ab.is_empty() or (ab["effects"] as Array).is_empty():
		return
	var res: Dictionary = runner.apply_effects(ab, amount, _board(e), "enemy", 1.0, String(def.get("id", "")))
	if e.has_method("apply_status"):
		for st: Dictionary in res["statuses"]:
			e.call("apply_status", String(st["status"]), float(st["duration"]))


## The effect set of a hit target (created on first use, dropped when empty or the target is gone).
func _board(e: Node) -> EffectSet:
	var iid := e.get_instance_id()
	if not _boards.has(iid):
		_boards[iid] = {"node": e, "set": EffectSet.new()}
	return (_boards[iid] as Dictionary)["set"]


func effects_on(e: Node) -> EffectSet:
	return _board(e)


func _update_boards(delta: float) -> void:
	for iid: int in _boards.keys():
		var b: Dictionary = _boards[iid]
		var t: Variant = b["node"]
		if not is_instance_valid(t):
			_boards.erase(iid)
			continue
		var set: EffectSet = b["set"]
		for ev: Dictionary in set.tick(delta):
			if String(ev["kind"]) == "dot" and not _flag(t, "dead"):
				(t as Node).call("take_damage", int(ev["amount"]), player, Vector3.ZERO)
		if set.active.is_empty():
			_boards.erase(iid)


## Incoming damage through the caster's own counters (wards, absorbs, damage_taken from path-tree techniques).
## player.gd can call this before applying a blow: `amount = caster.mitigate(amount)`.
func mitigate(amount: int, element := "") -> int:
	return int((runner.effects as EffectSet).mitigate(float(amount), element)["amount"])


# --- VFX -----------------------------------------------------------------------

func _world() -> Node:
	return player.get_parent() if player and player.get_parent() else self


func _burst_element(def: Dictionary) -> String:
	var e := String(def["element"])
	if VFX.ELEMENTS.has(e):
		return e
	return {"wood": "earth", "metal": "qi", "shadow": "qi"}.get(e, "qi")


## Calls VFX.<def.vfx> when it exists, else a generic effect. Returns what the
## VFX method returned (a Node3D for self-flying projectiles), or null.
func _vfx(def: Dictionary, from: Vector3, to: Vector3, radius: float, power: float, projectile := false) -> Variant:
	if not is_inside_tree():
		return null
	var world := _world()
	var id := String(def["vfx"])
	if id != "" and _vfx_info.has(id):
		var args: Variant = _vfx_args(_vfx_info[id], world, from, to, radius, power, def)
		if args is Array:
			return _vfx_script.callv(id, args)
	if projectile:
		return null      # the caster's own orb flies instead
	var col: Color = ELEMENT_COLORS.get(String(def["element"]), ELEMENT_COLORS["qi"])
	var yaw := atan2(to.x - from.x, to.z - from.z)
	if String(def["tree"]) in ["swordsmanship", "iaido"] and String(def["shape"]) in ["melee", "cone", "dash"]:
		VFX.slash(world, player.global_position + Vector3(0, 1.1, 0), yaw, randf_range(-0.8, 0.8), col, maxf(1.6, minf(radius, 4.0)))
		return null
	if String(def["shape"]) == "chain":
		VFX.flash(world, to, col, 3.0, 0.2, 5.0)
		VFX.sparks(world, to, col, 20)
		return null
	var at := Vector3(to.x, player.global_position.y, to.z)
	VFX.burst(world, at, _burst_element(def), clampf(power * (0.6 + radius / 8.0), 0.4, 1.6))
	return null


## Builds the argument list for a VFX static method from its signature, or
## null when a required argument cannot be matched.
func _vfx_args(info: Dictionary, world: Node, from: Vector3, to: Vector3, radius: float, power: float, def: Dictionary) -> Variant:
	var params: Array = info.get("args", [])
	var required := params.size() - (info.get("default_args", []) as Array).size()
	var col: Color = ELEMENT_COLORS.get(String(def["element"]), ELEMENT_COLORS["qi"])
	var args := []
	var vec_used := 0
	for i in params.size():
		var a: Dictionary = params[i]
		var nm := String(a.get("name", "")).to_lower()
		var t := int(a.get("type", TYPE_NIL))
		var kind := _arg_kind(nm, t, i)
		var v: Variant = null
		match kind:
			"world":
				v = world
			"dir":
				v = (to - from).normalized()
			"to":
				v = to
				vec_used += 1
			"from":
				v = from
				vec_used += 1
			"vec":
				v = from if vec_used == 0 else to
				vec_used += 1
			"color":
				v = col
			"element":
				v = _burst_element(def)
			"radius":
				v = radius
			"power":
				v = power
			"yaw":
				v = atan2(to.x - from.x, to.z - from.z)
			"speed":
				v = float(def["speed"])
		if v != null and t == TYPE_INT:
			v = int(round(float(v)))
		if v == null:
			if i >= required:
				break
			return null
		args.append(v)
	return args


static func _arg_kind(nm: String, t: int, i: int) -> String:
	if i == 0 and (t == TYPE_OBJECT or t == TYPE_NIL):
		return "world"
	if t == TYPE_COLOR or nm.contains("color") or nm.contains("colour"):
		return "color"
	if t == TYPE_STRING or t == TYPE_STRING_NAME or nm.contains("element"):
		return "element"
	if t in [TYPE_FLOAT, TYPE_INT, TYPE_NIL]:
		for k: String in ["radius", "range", "size", "length", "width", "reach"]:
			if nm.contains(k):
				return "radius"
		for k: String in ["power", "scale", "intensity", "strength"]:
			if nm.contains(k):
				return "power"
		if nm.contains("yaw") or nm.contains("angle"):
			return "yaw"
		if nm == "speed" or nm.ends_with("_speed"):
			return "speed"
		if t != TYPE_NIL:
			return ""
	if t in [TYPE_VECTOR3, TYPE_NIL]:
		if nm.contains("dir"):
			return "dir"
		for k: String in ["to", "target", "end", "dest"]:
			if nm == k or nm.begins_with(k + "_") or nm.ends_with("_" + k):
				return "to"
		for k: String in ["from", "origin", "start", "src"]:
			if nm == k or nm.begins_with(k) or nm.ends_with("_" + k):
				return "from"
		if t == TYPE_VECTOR3 or nm.contains("pos") or nm == "at" or nm.contains("center") or nm.contains("centre"):
			return "vec"
	return ""
