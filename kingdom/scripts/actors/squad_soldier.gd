extends Node3D
## F11 squad body: one named soldier of the player's squad. Decisions come from scripts/sim/soldier_squad.gd
## (follow_slot for where to stand, an NpcFighter per member for what to do in a fight); this node only moves,
## animates, strikes and reports wounds back to the soldier module. It follows the leader in a staggered column,
## engages hostiles (group "team1") near the leader, and stands down when wounded.
##
## No per-frame allocation beyond the move vector; the foe scan runs at THINK_HZ.

const Nameplates := preload("res://scripts/core/nameplates.gd")
const Fighter := preload("res://scripts/combat/npc_fighter.gd")

const THINK_HZ := 4.0
const SCAN_RANGE := 16.0
const LEASH := 24.0            # farther than this from the leader and the soldier stops fighting and returns
const WALK := 3.2
const RUN := 6.4
const TELEPORT := 50.0

var member_id := ""
var module: RefCounted = null
var leader: Node3D = null
var _foe: Node3D = null
var _think := 0.0
var _cool := 0.0
var _anim: AnimationPlayer = null
var _tag: Label3D = null


func setup(p_module: RefCounted, p_member_id: String, p_leader: Node3D) -> void:
	module = p_module
	member_id = p_member_id
	leader = p_leader


func _ready() -> void:
	add_to_group("squad_soldier")
	add_to_group("team0")
	add_to_group("combatant")
	var model := Assets.character("Guard", 1.8, ["Knight_Helmet", "1H_Sword"])
	add_child(model)
	_anim = Assets.animation_player(model)
	_tag = Label3D.new()
	Nameplates.style(_tag, Color("9ad0ff"))
	_tag.position.y = 2.2
	add_child(_tag)
	_refresh_tag()


func _idx() -> int:
	return int(module.squad.find(member_id)) if module != null else -1


func _member() -> Dictionary:
	return module.squad.member(_idx()) if module != null else {}


func _refresh_tag() -> void:
	var m := _member()
	if _tag != null and not m.is_empty():
		_tag.text = "%s%s" % [String(m["name"]), " (hurt)" if String(m["state"]) == "wounded" else ""]


func _play(clip: String) -> void:
	if _anim != null and _anim.has_animation(clip) and _anim.current_animation != clip:
		_anim.play(clip)


## Foes call this like any combatant. Reports to the module (wound or death) and removes the body on death.
func take_damage(amount: int, _from: Node = null, _knockback := Vector3.ZERO) -> void:
	var i := _idx()
	if i < 0 or module == null:
		return
	var st: String = module.squad_damage(i, amount, int(WorldSim.day))
	_refresh_tag()
	if st == "dead":
		queue_free()
	elif st == "wounded":
		_foe = null


func _process(delta: float) -> void:
	if leader == null or not is_instance_valid(leader) or module == null:
		return
	var i := _idx()
	var m := _member()
	if i < 0 or m.is_empty() or String(m["state"]) == "dead":
		queue_free()
		return
	_cool = maxf(0.0, _cool - delta)
	_think -= delta
	var lp := Vector2(leader.global_position.x, leader.global_position.z)
	var me := Vector2(global_position.x, global_position.z)
	var fwd3 := -leader.global_transform.basis.z
	var slot: Vector2 = module.squad.follow_slot(i, lp, Vector2(fwd3.x, fwd3.z))
	var ready := String(m["state"]) == "ready"
	if ready and _think <= 0.0:
		_think = 1.0 / THINK_HZ
		_foe = _scan(lp, me) if _foe == null or not is_instance_valid(_foe) else _foe
	var goal := slot
	var speed := WALK
	if ready and _foe != null and is_instance_valid(_foe) and me.distance_to(lp) < LEASH:
		var fp := Vector2(_foe.global_position.x, _foe.global_position.z)
		var dist := me.distance_to(fp)
		var ctx := {"dist": dist, "target_state": "idle", "has_token": true, "sees_target": true}
		var out: Dictionary = module.squad.think(i, delta, ctx)
		var intent: int = int(out["intent"])
		if intent == Fighter.Intent.APPROACH or intent == Fighter.Intent.CIRCLE or dist > 2.4:
			goal = fp
			speed = RUN
		if dist <= 2.6 and _cool <= 0.0 and out["move"] != null and intent in [Fighter.Intent.POKE, Fighter.Intent.COMBO]:
			_strike(i, out["move"])
		elif dist <= 2.6:
			goal = me
	elif _foe != null:
		_foe = null
	var to := goal - me
	if me.distance_to(lp) > TELEPORT:
		global_position = Vector3(slot.x, WorldGen.height(slot.x, slot.y), slot.y)
	elif to.length() > float(module.squad.cfg()["follow_gap"]) * 0.5:
		var step := to.normalized() * minf(to.length(), (RUN if to.length() > 8.0 else speed) * delta)
		var np := me + step
		global_position = Vector3(np.x, WorldGen.height(np.x, np.y), np.y)
		rotation.y = atan2(-to.x, -to.y)
		_play("Run" if speed >= RUN or to.length() > 8.0 else "Walk")
	else:
		_play("Idle")


func _scan(lp: Vector2, me: Vector2) -> Node3D:
	var best: Node3D = null
	var best_d := SCAN_RANGE
	for n: Node in get_tree().get_nodes_in_group("team1"):
		var e := n as Node3D
		if e == null or not is_instance_valid(e) or not e.is_in_group("combatant"):
			continue
		var d := minf(me.distance_to(Vector2(e.global_position.x, e.global_position.z)), lp.distance_to(Vector2(e.global_position.x, e.global_position.z)))
		if d < best_d:
			best_d = d
			best = e
	return best


func _strike(i: int, move: Resource) -> void:
	_cool = maxf(0.6, module.squad.fighter(i).cooldown())
	_play("1H_Melee_Attack_Slice_Diagonal")
	if _foe != null and _foe.has_method("take_damage"):
		var dmg := maxi(1, int(round(float(move.damage) * 0.8)))
		var was := int(_foe.get("health")) if _foe.get("health") != null else 1
		_foe.call("take_damage", dmg, self)
		if was > 0 and _foe.get("health") != null and int(_foe.get("health")) <= 0:
			module.squad_credit_kill(i)
			QuestBus.shared().emit_event(&"kill", {"target": String(_foe.get("species")) if _foe.get("species") != null else "enemy", "amount": 1})
			_foe = null
