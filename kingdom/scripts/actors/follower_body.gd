extends Node3D
## The body of one embodied recruit (Living World §2, stage 3). It is the villager's own model, tint, clips and
## gait (Assets.character + the PopulationLOD look of their trade, Walking_A / Running_A, smart-object work), but it
## takes its orders from scripts/actors/follower_brain.gd instead of a UtilityBrain:
##   follow   a formation slot beside and behind the player; runs to catch up; teleports after a fast travel or
##            when far behind; waits outside while the player is in an interior
##   fight    guard / escort / campaign duty (or a fighting trade) strikes foes near the player through an
##            NpcFighter, like scripts/actors/squad_soldier.gd; hurt, they are knocked out for a while, never killed
##   wait     holds where it stands
##   home     walks home, then hands itself back to the village (`finished`)
##   work     walks to the assigned property / group and works at a smart-object spot (SmartObjects session), or
##            at the spot itself with the trade's work clip when there is no spot
## The manager (follower_manager.gd) owns the budget, the WorldSim row ownership and the shared per-frame context.
## No per-frame allocation beyond the move vector; decisions run at THINK_HZ.

const Brain := preload("res://scripts/actors/follower_brain.gd")
const Fighter := preload("res://scripts/combat/npc_fighter.gd")
const Nameplates := preload("res://scripts/core/nameplates.gd")
const ContactBlobS := preload("res://scripts/actors/contact_blob.gd")
const TownIdentity := preload("res://scripts/world/town_identity.gd")
const StreetGraph := preload("res://scripts/population/street_graph.gd")
const Villager := preload("res://scripts/population/villager.gd")
const NpcWorld := preload("res://scripts/population/npc_world.gd")

const THINK_HZ := 4.0
const SESSION_HZ := 10.0
const DOWN_SECONDS := 40.0
const WORK_RANGE := 30.0
const ARRIVE := 0.7
const TURN_RATE := 6.0

var fid := ""
var row := -1
var order := "follow"
var order_arg := ""
## follower_will.will_of(): the answer to the last order. A following body whose will is in Brain.WILL_HOLD holds position.
var will := ""
var slot := 0
var anchor := Vector2.INF          # where work / home is (the manager resolves it)
var finished := false              # a home walk is done: the manager hands the body back to the village
var mode := Brain.Mode.FOLLOW
var hp := 60
var max_hp := 60
var fighter_on := false

var _ctx: Dictionary = {}
var _occ := "mercenary"
var _name := ""
var _look := "peasant"
var _anim: AnimationPlayer
var _skeleton: Skeleton3D
var _tag: Label3D
var _fighter: RefCounted
var _foe: Node3D
var _think := 0.0
var _cool := 0.0
var _down := 0.0
var _heading := 0.0
var _speed := 0.0
var _walking := false
var _running := false
var _hold := Vector2.INF           # where WAIT stands
var _moving_slot := false
var _graph: RefCounted
var _props: Variant = null
var _so: SmartObjects.Session = null
var _so_phase := -1
var _so_acc := 0.0
var _so_clip := ""
var _so_clip_done := false
var _so_last_pos := 0.0
var _so_face := NAN
var _so_move := Vector3.INF
var _so_snap := false
var _so_snap_to := Vector3.ZERO
var _work_pause := 0.0
var _work_clip := ""
var _work_spot_asked := false


## ctx is the manager's shared dictionary (player, pos, yaw, speed, inside, jump, owner).
func setup(p_fid: String, p_row: int, p_ctx: Dictionary, f: Dictionary, duty: String) -> void:
	fid = p_fid
	row = p_row
	_ctx = p_ctx
	_occ = String(f.get("occupation", "mercenary"))
	_name = String(f.get("name", "Follower"))
	_look = String(Brain.LOOK.get(_occ, "peasant"))
	var combat := float((f.get("skills", {}) as Dictionary).get("combat", 0.3))
	fighter_on = Brain.is_fighter(duty, _occ)
	max_hp = Brain.max_hp(combat)
	hp = max_hp
	if fighter_on:
		_fighter = Fighter.make("guard", hash([WorldSim.SEED, p_fid]) & 0x7fffffff, Brain.fighter_rank(combat))


func _ready() -> void:
	add_to_group("follower_body")
	if fighter_on:
		add_to_group("team0")
		add_to_group("combatant")
	var model_def: Array = PopulationLOD.LOOK_MODEL[_look]
	var keep: Array[String] = []
	keep.assign(model_def[1])
	var model := Assets.character(String(model_def[0]), 1.7, keep)
	if row >= 0 and row < WorldSim.home.size():
		var tt: Array = TownIdentity.person_tint(WorldSim.home[row], row, _look == "guard")
		TownIdentity.tint_model(model, tt[0], float(tt[1]))
	add_child(model)
	_anim = Assets.animation_player(model)
	if _anim != null:
		LifeLibrary.install(_anim)
	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	if not skeletons.is_empty():
		_skeleton = skeletons[0] as Skeleton3D
		_props = LifeProps.Holder.new(_skeleton)
	_tag = Label3D.new()
	Nameplates.style(_tag, Color("ffe9b8"), 18, 14.0)
	_tag.position.y = 1.95
	_tag.text = _name
	add_child(_tag)
	ContactBlobS.attach(self, 0.42)
	_graph = StreetGraph.for_person(row) if row >= 0 else null
	_think = float(absi(hash(fid)) % 250) / 1000.0
	_heading = rotation.y
	_play("Idle")


func _exit_tree() -> void:
	_so_release()


# --------------------------------------------------------------------------- state the manager reads

func sim_position() -> Vector2:
	return Vector2(global_position.x, global_position.z)


func is_down() -> bool:
	return _down > 0.0


func set_order(o: String, arg: String) -> void:
	if o == order and arg == order_arg:
		return
	order = o
	order_arg = arg
	finished = false
	_so_leave()
	_work_spot_asked = false
	if o == "wait":
		_hold = sim_position()


## Foes call this like any combatant. Hurt, a recruit is knocked out for a while and then gets up; never killed.
func take_damage(amount: int, _from: Node = null, _knockback := Vector3.ZERO) -> void:
	if _down > 0.0:
		return
	hp -= maxi(amount, 0)
	if hp <= 0:
		hp = 0
		_down = DOWN_SECONDS
		_foe = null
		_so_leave()
		_play("Lie_Down_Idle" if _anim != null and _anim.has_animation("Lie_Down_Idle") else "Idle_Hurt")


func place_at(p: Vector2) -> void:
	global_position = Vector3(p.x, WorldGen.height(p.x, p.y), p.y)
	_speed = 0.0
	_walking = false


# --------------------------------------------------------------------------- frame

func _physics_process(delta: float) -> void:
	if _ctx.is_empty() or _ctx.get("player") == null:
		return
	var here := sim_position()
	var pp: Vector2 = _ctx["pos"]
	var dist := here.distance_to(pp)
	_cool = maxf(0.0, _cool - delta)
	if _down > 0.0:
		_down -= delta
		if _down <= 0.0:
			hp = maxi(1, max_hp / 2)
			_play("Idle")
		return
	# A fast travel is one frame: act on it now, not at the next think.
	if order == "follow" and not bool(_ctx["inside"]) and Brain.needs_teleport(dist, float(_ctx["jump"])):
		_teleport()
		here = sim_position()
		dist = here.distance_to(pp)
	_think -= delta
	if _think <= 0.0:
		_think = 1.0 / THINK_HZ
		_decide(here, dist)
	var goal := Vector2.INF
	var speed := 0.0
	match mode:
		Brain.Mode.FOLLOW, Brain.Mode.CATCHUP:
			var fp := Brain.follow_point(pp, float(_ctx["yaw"]), float(_ctx["speed"]) > 0.6, slot)
			var gap := here.distance_to(fp)
			_moving_slot = Brain.should_move(gap, _moving_slot)
			if _moving_slot:
				goal = fp
				speed = Brain.follow_speed(gap, float(_ctx["speed"]), dist)
		Brain.Mode.FIGHT:
			var r := _fight(here, pp, delta)
			goal = r[0]
			speed = r[1]
		Brain.Mode.HOME:
			if anchor != Vector2.INF:
				if here.distance_to(anchor) > 2.0:
					goal = anchor
					speed = Brain.WALK_SPEED * 0.8
				else:
					finished = true
		Brain.Mode.WORK:
			var w := _work(here, delta)
			goal = w[0]
			speed = w[1]
		Brain.Mode.WAIT, Brain.Mode.WAIT_OUTSIDE:
			pass
	_move(goal, speed, here, delta)
	_animate(delta)


func _decide(here: Vector2, dist: float) -> void:
	var foe := false
	if fighter_on and _down <= 0.0:
		if _foe == null or not is_instance_valid(_foe) or _dead(_foe):
			_foe = _scan(_ctx["pos"], here)
		foe = _foe != null
		if foe and _foe.global_position.distance_to(Vector3(_ctx["pos"].x, _foe.global_position.y, _ctx["pos"].y)) > Brain.LEASH:
			_foe = null
			foe = false
	var m := Brain.decide(order, {"dist": dist, "player_inside": bool(_ctx["inside"]), "jump": 0.0, "fighter": fighter_on, "foe": foe, "will": will})
	if m != mode:
		if mode == Brain.Mode.WORK:
			_so_leave()
		mode = m
		if m in [Brain.Mode.WAIT, Brain.Mode.WAIT_OUTSIDE] and _hold == Vector2.INF:
			_hold = here
	if m not in [Brain.Mode.WAIT, Brain.Mode.WAIT_OUTSIDE]:
		_hold = Vector2.INF if order != "wait" else _hold
	if _graph != null:
		var q: Vector2 = _graph.push_out(here, 0.4)
		if q.distance_squared_to(here) > 0.0004:
			place_at(q)


func _teleport() -> void:
	var yaw := float(_ctx["yaw"])
	var p := Brain.follow_point(_ctx["pos"], yaw, false, slot) - Vector2(sin(yaw), cos(yaw)) * 0.8
	place_at(p)
	_foe = null


# --------------------------------------------------------------------------- fighting

func _scan(pp: Vector2, here: Vector2) -> Node3D:
	var best: Node3D = null
	var best_d := Brain.SCAN_RANGE
	for n: Node in get_tree().get_nodes_in_group("team1"):
		var e := n as Node3D
		if e == null or not is_instance_valid(e) or not e.is_in_group("combatant") or _dead(e):
			continue
		var ep := Vector2(e.global_position.x, e.global_position.z)
		var d := minf(here.distance_to(ep), pp.distance_to(ep))
		if d < best_d:
			best_d = d
			best = e
	return best


func _dead(n: Node) -> bool:
	var h: Variant = n.get("health")
	return h != null and int(h) <= 0


## Returns [goal, speed]; strikes when in reach.
func _fight(here: Vector2, pp: Vector2, delta: float) -> Array:
	if _foe == null or not is_instance_valid(_foe) or _fighter == null:
		return [Vector2.INF, 0.0]
	var fp := Vector2(_foe.global_position.x, _foe.global_position.z)
	var dist := here.distance_to(fp)
	var out: Dictionary = _fighter.think(delta, {"dist": dist, "target_state": "idle", "has_token": true, "sees_target": true})
	var intent: int = int(out["intent"])
	var goal := Vector2.INF
	var speed := 0.0
	if intent == Fighter.Intent.APPROACH or intent == Fighter.Intent.CIRCLE or dist > Brain.STRIKE_RANGE:
		goal = fp
		speed = Brain.RUN_SPEED
	if dist <= Brain.STRIKE_RANGE and _cool <= 0.0 and out["move"] != null and intent in [Fighter.Intent.POKE, Fighter.Intent.COMBO]:
		_strike(out["move"] as Resource)
	if dist <= Brain.STRIKE_RANGE:
		goal = Vector2.INF
		_face(fp, delta)
	return [goal, speed]


func _strike(move: Resource) -> void:
	_cool = maxf(0.6, _fighter.cooldown())
	var clip := "1H_Melee_Attack_Slice_Diagonal"
	if _anim != null and _anim.has_animation(clip):
		_anim.play(clip, 0.1)
		_walking = false
	if _foe != null and _foe.has_method("take_damage"):
		var dmg := maxi(1, int(round(float(move.get("damage")) * 0.8)))
		_foe.call("take_damage", dmg, self)


# --------------------------------------------------------------------------- work (smart objects)

## Returns [goal, speed]. Walks to the assigned place, claims a work spot near it and runs its session.
func _work(here: Vector2, delta: float) -> Array:
	if anchor == Vector2.INF:
		return [Vector2.INF, 0.0]
	if _so == null and _work_pause > 0.0:
		_work_pause -= delta
		_play("Idle")
		return [Vector2.INF, 0.0]
	if _so == null and not _work_spot_asked and here.distance_to(anchor) < WORK_RANGE:
		_work_spot_asked = true
		_so_begin(anchor)
	if _so != null:
		return _work_session(here, delta)
	# no spot: stand at the place and work the trade's own clip
	if here.distance_to(anchor) > ARRIVE + 0.5:
		return [anchor, Brain.WALK_SPEED * 0.8]
	_idle_work(delta)
	return [Vector2.INF, 0.0]


func _so_begin(at: Vector2) -> void:
	var so := NpcWorld.spots()
	var job: int = int(Brain.SMART_JOB.get(_occ, 4))
	var filter := {"act": "work", "job": job, "job_required": true, "exclude_types": ["market_stall"]}
	if job == 3:
		filter["tags"] = ["guard"]
	var pick: Array = so.find(Vector3(at.x, WorldGen.height(at.x, at.y), at.y), filter, WORK_RANGE, row)
	if pick.is_empty() or not so.claim(pick[0], pick[1], row):
		return
	_so = so.session(row, pick[0], pick[1])
	_so_phase = SmartObjects.Session.APPROACH
	_so_acc = 0.0


func _so_leave() -> void:
	if _so == null:
		return
	_so_release()


func _so_release() -> void:
	if NpcWorld.smart != null and row >= 0:
		NpcWorld.smart.release(row)
	_so = null
	_so_phase = -1
	_so_move = Vector3.INF
	_so_snap = false
	_so_clip = ""
	if _props != null:
		(_props as LifeProps.Holder).clear()


func _work_session(here: Vector2, delta: float) -> Array:
	var ap := NpcWorld.spots().approach_point(_so.spot, _so.slot)
	var apv := Vector2(ap.x, ap.z)
	if _so_phase < SmartObjects.Session.ALIGN and here.distance_to(apv) > ARRIVE:
		return [apv, Brain.WALK_SPEED * 0.8]
	_so_acc += delta
	_so_track()
	if _so_acc >= 1.0 / SESSION_HZ:
		var out := _so.update(_so_acc, global_position, _so_clip_done)
		_so_acc = 0.0
		_so_clip_done = false
		_so_apply(out)
		if _so == null:
			_work_spot_asked = false         # session over: look for the next spot after a pause
			_work_pause = 4.0
			return [Vector2.INF, 0.0]
	if _so == null:
		return [Vector2.INF, 0.0]
	if not is_nan(_so_face):
		_heading = rotate_toward(_heading, _so_face, TURN_RATE * delta)
		rotation.y = _heading
	if _so_move != Vector3.INF:
		var to := _so_move - global_position
		to.y = 0.0
		var d := to.length()
		if d > 0.02:
			var p := global_position + to / d * minf(0.9 * delta, d)
			place_at(Vector2(p.x, p.z))
	elif _so_snap:
		var q := global_position.lerp(_so_snap_to, 1.0 - exp(-8.0 * delta))
		place_at(Vector2(q.x, q.z))
	return [Vector2.INF, 0.0]


func _so_apply(out: Dictionary) -> void:
	_so_phase = int(out["phase"])
	var clip: String = out["clip"]
	if clip != "" and _anim != null and _anim.has_animation(clip):
		if bool(out["restart"]) or _so_clip != clip:
			_anim.play(clip, float(LifeLibrary.info(clip).get("blend_in", 0.25)))
			if bool(out["restart"]) and clip == _so_clip:
				_anim.seek(0.0, true)
			_so_clip = clip
			_so_last_pos = 0.0
			_so_clip_done = false
		_walking = false
	if _props != null and _so_phase >= SmartObjects.Session.ENTER and _so_phase <= SmartObjects.Session.EXIT:
		(_props as LifeProps.Holder).show_props(out["props"])
	_so_face = float(out["face"])
	_so_move = out["move_to"] if out["move_to"] != null else Vector3.INF
	var snap: Variant = out.get("snap")
	_so_snap = snap != null
	if _so_snap:
		_so_snap_to = (snap as Transform3D).origin
	var ev: Variant = out["event"]
	if ev != null:
		LivingEvents.emit(String((ev as Dictionary).get("kind", "work")), global_position, float((ev as Dictionary).get("radius", 10.0)), 2.0)
	if _so_phase == SmartObjects.Session.DONE:
		_so_release()


func _so_track() -> void:
	if _anim == null or _so_clip == "" or _anim.current_animation != _so_clip:
		return
	var pos := _anim.current_animation_position
	var a := _anim.get_animation(_so_clip)
	if a == null:
		return
	if a.loop_mode != Animation.LOOP_NONE:
		if pos + 0.0001 < _so_last_pos:
			_so_clip_done = true
	elif not _anim.is_playing() or pos >= a.length - 0.02:
		_so_clip_done = true
	_so_last_pos = pos


## No work spot: the trade's own clip at the place, with a pause between.
func _idle_work(_delta: float) -> void:
	if _anim == null:
		return
	if _work_clip == "":
		var job: int = int(Brain.SMART_JOB.get(_occ, 4))
		for n: String in Villager.JOB_CLIPS[job]:
			if _anim.has_animation(n):
				_work_clip = n
				break
	if _work_clip == "":
		_play("Idle")
		return
	if not _anim.is_playing() or _anim.current_animation != _work_clip:
		if _anim.current_animation == _work_clip:
			_work_pause = 1.2
			_play("Idle")
		else:
			_anim.play(_work_clip, 0.2)
	_walking = false


# --------------------------------------------------------------------------- movement and animation

func _move(goal: Vector2, speed: float, here: Vector2, delta: float) -> void:
	if goal == Vector2.INF or speed <= 0.0:
		_speed = move_toward(_speed, 0.0, 12.0 * delta)
		return
	var to := goal - here
	var d := to.length()
	if d < 0.05:
		_speed = 0.0
		return
	_speed = move_toward(_speed, speed, 14.0 * delta)
	var step := minf(d, _speed * delta)
	var np := here + to / d * step
	global_position = Vector3(np.x, WorldGen.height(np.x, np.y), np.y)
	_heading = rotate_toward(_heading, atan2(to.x, to.y), TURN_RATE * delta)
	rotation.y = _heading


func _face(p: Vector2, delta: float) -> void:
	var to := p - sim_position()
	if to.length_squared() > 0.01:
		_heading = rotate_toward(_heading, atan2(to.x, to.y), TURN_RATE * delta)
		rotation.y = _heading


func _animate(_delta: float) -> void:
	if _anim == null:
		return
	if _speed > 0.3:
		var running := _speed > 3.6
		var clip := "Running_A" if running else "Walking_A"
		var clip_speed := Villager.RUN_CLIP_SPEED if running else Villager.WALK_CLIP_SPEED
		if _anim.current_animation != clip:
			_anim.play(clip, 0.2)
			var length := _anim.current_animation_length
			if length > 0.0:
				_anim.seek(fmod(float(row) * 0.618, 1.0) * length)
		_anim.speed_scale = clampf(_speed / clip_speed, 0.3, 1.8)
		_walking = true
		_running = running
		return
	if _walking:
		_walking = false
		_anim.speed_scale = 1.0
		_play("Idle")
		return
	# standing: face the player when following, keep any work / fight one-shot playing
	if mode in [Brain.Mode.FOLLOW, Brain.Mode.WAIT_OUTSIDE] and _anim.current_animation in ["Idle", ""]:
		var to: Vector2 = _ctx["pos"] - sim_position()
		if to.length_squared() > 4.0:
			_heading = rotate_toward(_heading, atan2(to.x, to.y), TURN_RATE * 0.4 * _delta)
			rotation.y = _heading
	if _anim.current_animation == "" or (not _anim.is_playing() and mode != Brain.Mode.WORK):
		_play("Idle")
	elif _anim.current_animation == "Idle":
		_anim.speed_scale = 0.9 + 0.2 * fmod(float(row) * 0.618034, 1.0)


func _play(clip: String) -> void:
	if _anim != null and _anim.has_animation(clip) and _anim.current_animation != clip:
		_anim.play(clip, 0.2)
