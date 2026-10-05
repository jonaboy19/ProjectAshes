class_name Squad
extends Node3D
## Formation-level AI. The squad decides where the block of men stands, how it
## is drawn up and which way it faces; each soldier walks to his slot and
## fights the man the squad pairs him with. One brain per hundred men, not a
## hundred brains.
##
## Cost model (the local session owns frame rate):
##   every 0.1 s  march / wheel the block, write slot targets, banner
##   every 0.5 s  enemy scan, morale, melee pairing (grid-bucketed), aggro
##   every 3 s    officer scan
##   on orders    slot assignment with crossing removal, coarse water-avoiding
##                route (A* on an 8 m grid, only if the straight line is wet),
##                ghost markers
## Nothing here runs per soldier per frame.
##
## Orders: FOLLOW, HOLD, CHARGE, MOVE (move_to), RETREAT (retreat), plus
## face_toward() and set_formation(). Routed squads ignore orders.

const Formation := preload("res://scripts/army/formation.gd")
const Morale := preload("res://scripts/army/morale.gd")

signal wiped_out(squad: Squad)
signal strength_changed(alive: int)
signal routed(squad: Squad)
signal rallied(squad: Squad)
signal order_changed(squad: Squad)

## FOLLOW, HOLD, CHARGE keep their old values (main.gd indexes names by order).
enum Order { FOLLOW, HOLD, CHARGE, MOVE, RETREAT }
const ORDER_NAMES := ["Follow", "Hold", "Charge", "Move", "Retreat"]

const SPACING := 1.8
const SLOT_TICK := 0.1
const THINK_TICK := 0.5
const OFFICER_SCAN := 3.0
## March speed of the block, m/s, before formation and troop multipliers.
const MARCH := 2.2
const CHARGE_SPEED := 4.6
const RETREAT_SPEED := 3.0
const RETREAT_DISTANCE := 40.0
## A soldier locks onto an enemy within this range of him (charge: anywhere near).
const LOCK_RANGE := 9.0
const CHARGE_LOCK := 60.0
const PAIR_CAP := 2
const CHARGE_CAP := 3
## Enemies this close to the block's edge count toward flank/rear pressure.
const CONTACT := 14.0
## ...and this close toward being outnumbered.
const NEAR := 25.0
const FLEE_DISTANCE := 70.0
const SHOCK_WINDOW := 10.0
## Water deeper than this blocks a route; fords stay passable.
const WADE_DEPTH := 0.9
const PATH_CELL := 8.0
const PATH_MAX_CELLS := 80

var team := 0
var order := Order.HOLD
var soldiers: Array[Soldier] = []
## Where the centre of the block stands now (moves while marching).
var anchor := Vector3.ZERO
## Current facing. Wheels toward the ordered facing; soldiers read it.
var facing := Vector3.FORWARD
## FOLLOW keeps the block behind this node (the player).
var leader: Player
## Enemy squads charge when a hostile comes this close to the anchor.
var aggro_radius := 0.0
var formation: int = Formation.Type.LINE
## RAMilitary.UNIT_TYPES id.
var unit_type := "sabre"
var morale := Morale.new()

var banner: Label3D
var _look := ""
var _file := ""
var _keep: Array[String] = []

var _clock := 0.0
var _slot_acc := 0.0
var _think_acc := 0.0
var _officer_acc := 0.0
var _face_goal := Vector3.FORWARD
var _final_face := Vector3.ZERO
var _path := PackedVector3Array()
var _local := PackedVector2Array()
var _slot_of := PackedInt32Array()
var _front_y := 0.0
var _cols := 0
var _reassign := true
var _reassign_at := 0.0
var _refine := true
var _about_face_cd := 0.0
var _peak := 0
var _deaths := PackedFloat32Array()
var _centre := Vector3.ZERO
var _lag := 0.0
var _enemies: Array[Node3D] = []
var _targets := {}       # Soldier -> Node3D
var _face_of := {}       # Soldier -> Vector3 (square only)
var _engaged := false
var _charge_point: Variant = null
var _officers: Array[Node] = []
var _officer_bonus := 0.0
var _officer_among := false
var _flee_dir := Vector3.BACK
var _disperse_t := 0.0
var _speed_mult := 1.0

var _standard: Node3D
var _banner_pos := Vector3.ZERO
var _banner_text := ""
var _ghost: MultiMeshInstance3D
var _ghost_arrow: MeshInstance3D
var _ghost_mat: StandardMaterial3D
var _ghost_tween: Tween


func setup(team_id: int, look: String, file: String, keep: Array[String]) -> Squad:
	team = team_id
	_look = look
	_file = file
	_keep = keep
	return self


func _ready() -> void:
	add_to_group("squad")
	# Screen-constant banner so formations stay readable in town/command view.
	banner = Label3D.new()
	banner.fixed_size = true
	banner.pixel_size = 0.0022
	banner.font_size = 36
	banner.outline_size = 10
	banner.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	banner.no_depth_test = true
	banner.modulate = _team_color()
	banner.visible = false
	add_child(banner)
	_standard = _build_standard()
	_standard.visible = false
	add_child(_standard)
	facing = _planar(facing, Vector3.FORWARD)
	_face_goal = facing
	morale.value = float(RAMilitary.unit_type(unit_type)["morale"])
	# Stagger ticks so several squads don't think on the same frame.
	_slot_acc = randf() * SLOT_TICK
	_think_acc = randf() * THINK_TICK
	_officer_acc = OFFICER_SCAN


## `casters`: NpcCaster ids (CasterSpawns.mix) for the first soldiers; the rest are plain fighters.
func add_soldiers(count: int, near: Vector3, casters: Array = []) -> void:
	for i in count:
		var s := Soldier.create(team, _look, _file, _keep)
		if i < casters.size():
			s.caster_id = String(casters[i])
		s.squad = self
		get_parent().add_child(s)
		var p := near + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3))
		p.y = WorldGen.height(p.x, p.z)
		s.global_position = p
		s.died.connect(_on_soldier_died)
		soldiers.append(s)
		_apply_stats(s)
	_peak += count
	_cols = Formation.default_cols(formation, soldiers.size())
	_request_assign(true)
	strength_changed.emit(soldiers.size())


func alive() -> int:
	return soldiers.size()


# --- Orders ------------------------------------------------------------------

## FOLLOW / HOLD / CHARGE (and RETREAT, MOVE-in-place). Returns false when the
## men won't listen (routed).
func command(new_order: Order) -> bool:
	if morale.is_broken():
		return false
	if new_order == Order.RETREAT:
		return retreat()
	if new_order == Order.MOVE:
		return move_to(_formation_centre())
	order = new_order
	_path.clear()
	if order == Order.HOLD:
		if leader:
			anchor = leader.global_position
			_face_goal = _planar(leader.forward(), facing)
		else:
			anchor = _formation_centre()
		_request_assign(true)
	order_changed.emit(self)
	return true


## March the block to `point` (tap in command view). `face` sets the facing on
## arrival; by default it keeps the direction of travel.
func move_to(point: Vector3, face := Vector3.ZERO) -> bool:
	if morale.is_broken() or soldiers.is_empty():
		return false
	var start := _formation_centre()
	anchor = start
	point.y = WorldGen.height(point.x, point.z)
	var dir := point - start
	dir.y = 0.0
	if face.length_squared() > 0.0001:
		_final_face = _planar(face, facing)
	elif dir.length() > 1.0:
		_final_face = dir.normalized()
	else:
		_final_face = facing
	_path = _plan_path(start, point)
	order = Order.MOVE
	_targets.clear()
	_request_assign(true)
	var end: Vector3 = _path[_path.size() - 1] if not _path.is_empty() else point
	_show_ghost(end, _final_face, true)
	order_changed.emit(self)
	return true


## Turn the block to face `dir` where it stands.
func face_toward(dir: Vector3) -> bool:
	if morale.is_broken():
		return false
	dir = _planar(dir, facing)
	_final_face = dir
	_face_goal = dir
	if order == Order.FOLLOW:
		order = Order.HOLD
		anchor = _formation_centre()
		order_changed.emit(self)
	_show_ghost(anchor, dir, true)
	return true


## Orderly withdrawal away from the nearest enemies, then turn and face them.
func retreat() -> bool:
	if morale.is_broken() or soldiers.is_empty():
		return false
	var c := _formation_centre()
	var away := _away_from_enemies(c, 60.0)
	if away == Vector3.ZERO:
		away = -facing
	if not move_to(c + away * RETREAT_DISTANCE, -away):
		return false
	order = Order.RETREAT
	order_changed.emit(self)
	return true


func set_formation(type: int) -> void:
	if type < 0 or type >= Formation.NAMES.size():
		return
	formation = type
	_speed_mult = float(Formation.stats(formation)["speed"]) * float(RAMilitary.unit_type(unit_type)["speed"])
	_cols = Formation.default_cols(formation, soldiers.size())
	for s in soldiers:
		_apply_stats(s)
	_request_assign(true)
	if not soldiers.is_empty():
		_show_ghost(anchor, _face_goal, true)
	order_changed.emit(self)


## Next formation this troop type drills. Returns its name.
func cycle_formation() -> String:
	var drill: Array = RAMilitary.unit_type(unit_type)["formations"]
	var types: Array[int] = []
	for n: String in drill:
		types.append(Formation.from_name(n))
	var i := types.find(formation)
	set_formation(types[(i + 1) % types.size()])
	return Formation.type_name(formation)


## Troop type from RAMilitary.UNIT_TYPES; switches to its default formation.
func set_unit_type(type_id: String) -> void:
	unit_type = type_id if RAMilitary.UNIT_TYPES.has(type_id) else "sabre"
	var u := RAMilitary.unit_type(unit_type)
	morale.value = float(u["morale"])
	set_formation(Formation.from_name((u["formations"] as Array)[0]))


## Ghost markers for an order being aimed (drag in command view).
func preview_order(point: Vector3, face := Vector3.ZERO) -> void:
	if soldiers.is_empty():
		return
	var dir := face if face.length_squared() > 0.0001 else point - _formation_centre()
	_show_ghost(point, _planar(dir, facing), false)


func clear_preview() -> void:
	if _ghost:
		_ghost.visible = false
		_ghost_arrow.visible = false


## HUD text, e.g. "Hold · Shield Wall" or "Routed".
func order_name() -> String:
	if morale.is_broken():
		return morale.state_name()
	var s: String = ORDER_NAMES[order]
	if morale.state == Morale.State.WAVERING:
		s += " (wavering)"
	return "%s · %s" % [s, Formation.type_name(formation)]


# --- Queries soldiers use (see hook lines in the report) ----------------------

func is_routed() -> bool:
	return morale.is_broken()


## The enemy the squad paired this man with, or null: wait in your slot.
func target_for(s: Soldier) -> Node3D:
	var e: Variant = _targets.get(s)
	if e != null and is_instance_valid(e) and not (e as Node).get("dead"):
		if (e as Node).is_in_group("player") and not _sees_player(s, e as Node3D):
			return null            # acquisition: a man only fights what Perception says he can see
		return e
	return null


const _Perception := preload("res://scripts/population/perception.gd")
const SIGHT_MEMORY := 3.0          # s a seen player stays acquired after sight is lost
const CLOSE_SIGHT := 6.0           # m: inside this he has noticed you regardless
var _seen_until := {}


func _sees_player(s: Soldier, p: Node3D) -> bool:
	var now := Time.get_ticks_msec() * 0.001
	var d := s.global_position.distance_to(p.global_position)
	if d < CLOSE_SIGHT:
		_seen_until[s] = now + SIGHT_MEMORY
		return true
	var fwd := s.global_transform.basis.z
	var pos := Vector2(s.global_position.x, s.global_position.z)
	var tp := Vector2(p.global_position.x, p.global_position.z)
	var stance: float = _Perception.STANCE_CROUCH if bool(p.get("crouching")) else _Perception.STANCE_WALK
	var vis: float = _Perception.vis(pos, Vector2(fwd.x, fwd.z), tp, _Perception.light_at(tp), stance, false, 1.0)
	if vis > _Perception.VIS_MIN:
		_seen_until[s] = now + SIGHT_MEMORY
		return true
	return float(_seen_until.get(s, 0.0)) > now


## Walking/running speed multiplier from formation and troop type (cached:
## soldiers may call this every frame).
func speed_mult() -> float:
	return 1.15 if morale.is_broken() else _speed_mult


## Damage multiplier for a blow landing on `s` from `from` (flank and rear hurt).
func incoming_mult(s: Soldier, from: Node) -> float:
	if morale.is_broken():
		return 1.5
	if from is Node3D:
		return Formation.incoming_multiplier(formation, facing, (from as Node3D).global_position - s.global_position)
	return 1.0


## Which way this man faces at rest (the square faces out).
func facing_for(s: Soldier) -> Vector3:
	if formation != Formation.Type.SQUARE or morale.is_broken():
		return facing
	return _face_of.get(s, facing)


## Ground point under a screen position (command-view tap). Marches the ray
## against WorldGen.height, so it works where no terrain collider is loaded.
static func pick_ground(cam: Camera3D, screen: Vector2) -> Variant:
	if cam == null:
		return null
	var o := cam.project_ray_origin(screen)
	var d := cam.project_ray_normal(screen)
	if d.y > -0.01:
		return null
	var t := 0.0
	var step := 2.0
	while t < 1500.0:
		var p := o + d * (t + step)
		if p.y <= WorldGen.height(p.x, p.z):
			var lo := t
			var hi := t + step
			for i in 10:
				var mid := (lo + hi) * 0.5
				var q := o + d * mid
				if q.y <= WorldGen.height(q.x, q.z):
					hi = mid
				else:
					lo = mid
			var hit := o + d * hi
			hit.y = WorldGen.height(hit.x, hit.z)
			return hit
		t += step
		step = maxf(2.0, t * 0.03)
	return null


# --- Ticks --------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_clock += delta
	_about_face_cd -= delta
	if soldiers.is_empty():
		return
	_slot_acc += delta
	if _slot_acc >= SLOT_TICK:
		_slot_tick(_slot_acc)
		_slot_acc = 0.0
	_think_acc += delta
	if _think_acc >= THINK_TICK:
		_think(_think_acc)
		_think_acc = 0.0


func _process(delta: float) -> void:
	if banner.visible:
		var k := clampf(delta * 6.0, 0.0, 1.0)
		_standard.global_position = _standard.global_position.lerp(_banner_pos, k)
		banner.global_position = _standard.global_position + Vector3(0, 4.9 * _standard.scale.y, 0)


func _slot_tick(dt: float) -> void:
	_centre = _formation_centre()
	if morale.is_broken():
		_update_banner()
		return
	match order:
		Order.FOLLOW:
			_follow(dt)
		Order.MOVE:
			_march(dt, MARCH * speed_mult())
		Order.RETREAT:
			_march(dt, RETREAT_SPEED * speed_mult())
		Order.CHARGE:
			_charge(dt)
	_wheel(dt)
	if _reassign and _clock >= _reassign_at:
		_assign()
	_write_slots()
	_update_banner()


func _follow(dt: float) -> void:
	if leader == null:
		return
	var fwd := _planar(leader.forward(), facing)
	var want := leader.global_position - fwd * 4.5
	anchor = anchor.lerp(want, clampf(dt * 3.0, 0.0, 1.0)) if anchor.distance_to(want) < 30.0 else want
	_face_goal = fwd


func _march(dt: float, speed: float) -> void:
	if _path.is_empty():
		_arrive()
		return
	# Wait for stragglers: the block never outruns its men.
	var lag_f := 1.0 if _lag < 4.0 else (0.5 if _lag < 8.0 else 0.15)
	var step := speed * lag_f * dt
	var goal := _path[0]
	var to := Vector3(goal.x - anchor.x, 0, goal.z - anchor.z)
	var dist := to.length()
	if dist <= step:
		anchor.x = goal.x
		anchor.z = goal.z
		_path.remove_at(0)
		if _path.is_empty():
			_arrive()
			return
	else:
		anchor += to / dist * step
	var remaining := dist
	for i in range(1, _path.size()):
		remaining += _path[i - 1].distance_to(_path[i])
	if remaining > 4.0 and dist > 0.01:
		_face_goal = to / dist
	elif _final_face != Vector3.ZERO:
		_face_goal = _final_face


func _arrive() -> void:
	_path.clear()
	if _final_face != Vector3.ZERO:
		_face_goal = _final_face
	if order == Order.MOVE or order == Order.RETREAT:
		order = Order.HOLD
		order_changed.emit(self)


func _charge(dt: float) -> void:
	if _charge_point == null:
		return
	var cp: Vector3 = _charge_point
	var to := Vector3(cp.x - anchor.x, 0, cp.z - anchor.z)
	var dist := to.length()
	if dist < 0.5:
		return
	_face_goal = to / dist
	# Stop with the front rank on the enemy, not the centre.
	var stop := maxf(dist - _front_y - 1.0, 0.0)
	anchor += to / dist * minf(stop, CHARGE_SPEED * speed_mult() * dt)


## Pivot around the centre at a rate the outer file can walk; a sharp reversal
## is an about-face instead (men re-pick the nearest slots).
func _wheel(dt: float) -> void:
	var ang := Formation.angle_between(facing, _face_goal)
	if ang < 0.001:
		return
	if ang > Formation.ABOUT_FACE and _about_face_cd <= 0.0:
		facing = _face_goal
		_about_face_cd = 1.0
		_request_assign(false)
		_reassign_at = 0.0
	else:
		facing = Formation.rotate_toward(facing, _face_goal, Formation.turn_rate(_local) * dt)


## refine: an order (assign now, remove crossings). Otherwise a casualty:
## batched, at most one plain reassignment per 0.4 s however many fall.
func _request_assign(refine: bool) -> void:
	if refine:
		_refine = true
		_reassign_at = 0.0
	elif not _reassign:
		_reassign_at = _clock + 0.4
	_reassign = true


func _assign() -> void:
	var n := soldiers.size()
	_local = Formation.slots(formation, n, _cols)
	_front_y = -INF
	var sw := PackedVector2Array()
	for l in _local:
		_front_y = maxf(_front_y, l.y)
		var w := Formation.to_world(l, anchor, facing)
		sw.append(Vector2(w.x, w.z))
	var men := PackedVector2Array()
	for s in soldiers:
		men.append(Vector2(s.global_position.x, s.global_position.z))
	_slot_of = Formation.assign(men, sw, 2 if _refine and n <= 150 else 0)
	_reassign = false
	_refine = false


func _write_slots() -> void:
	if _slot_of.size() != soldiers.size() or _local.is_empty():
		_assign()
	# Engaged: the rear ranks close up behind the fighting front and push.
	var press := 0.7 if _engaged else 1.0
	var square := formation == Formation.Type.SQUARE
	var right := facing.cross(Vector3.UP).normalized()
	for i in soldiers.size():
		var si := _slot_of[i]
		if si >= _local.size():
			continue
		var l := _local[si]
		if press < 1.0:
			l.y = _front_y - (_front_y - l.y) * press
		soldiers[i].slot_target = anchor + right * l.x + facing * l.y
		if square:
			var f := Formation.slot_facing(formation, _local[si])
			_face_of[soldiers[i]] = right * f.x + facing * f.y


func _think(dt: float) -> void:
	var group := "team%d" % (1 - team)
	_enemies.clear()
	for e in get_tree().get_nodes_in_group(group):
		if e is Node3D and not e.get("dead"):
			_enemies.append(e)
	_centre = _formation_centre()
	var lag := 0.0
	for s in soldiers:
		lag += Vector2(s.global_position.x - s.slot_target.x, s.global_position.z - s.slot_target.z).length()
	_lag = lag / soldiers.size()
	_officer_acc += dt
	if _officer_acc >= OFFICER_SCAN:
		_officer_acc = 0.0
		_scan_officers()
	if aggro_radius > 0.0 and order != Order.CHARGE and not morale.is_broken():
		for enemy in _enemies:
			if enemy.global_position.distance_to(anchor) < aggro_radius:
				order = Order.CHARGE
				order_changed.emit(self)
				break
	var sit := _assess()
	var was_broken := morale.is_broken()
	morale.update(dt, sit["inputs"], sit["pursued"], _officer_among)
	if not was_broken and morale.is_broken():
		_begin_rout()
	elif was_broken and not morale.is_broken():
		_rally(sit["away"])
	if morale.is_broken():
		_targets.clear()
		_engaged = false
		# An enemy band that got away scatters for good: at once if shattered,
		# otherwise if it hasn't found the nerve to rally in 25 s. (Keeps raid
		# camps clearable: wiped_out fires either way.)
		if team != 0 and not sit["pursued"]:
			_disperse_t += dt
			if _disperse_t > (6.0 if morale.state == Morale.State.SHATTERED else 25.0):
				_disperse()
		else:
			_disperse_t = 0.0
		return
	_engage()


## Pressure on the block this tick -> morale inputs.
func _assess() -> Dictionary:
	var half := Formation.width(_local) * 0.5 + 2.0
	var front := 0
	var flank := 0
	var rear := 0
	var near := 0
	var cav := 0
	var nearest := INF
	var sum := Vector3.ZERO
	var sum_n := 0
	for e in _enemies:
		var d := e.global_position - _centre
		d.y = 0.0
		var dist := d.length()
		nearest = minf(nearest, dist)
		if dist < 60.0:
			sum += d
			sum_n += 1
		if dist < half + NEAR:
			near += 1
		if dist < half + CONTACT and dist > 0.01:
			var dot := facing.dot(d / dist)
			if dot > 0.35:
				front += 1
			elif dot < -0.35:
				rear += 1
			else:
				flank += 1
			var sq: Variant = e.get("squad")
			if sq != null and is_instance_valid(sq) and (sq as Node).get("unit_type") == "cavalry":
				cav += 1
	var contact := maxi(front + flank + rear, 1)
	var u := RAMilitary.unit_type(unit_type)
	var st := Formation.stats(formation)
	var recent := 0
	for t in _deaths:
		if _clock - t < SHOCK_WINDOW:
			recent += 1
	var inputs := {
		"base": float(u["morale"]),
		"casualties": 1.0 - float(soldiers.size()) / maxf(_peak, 1.0),
		"shock": float(recent) / maxf(soldiers.size() + recent, 1.0),
		"flank": float(flank) / contact,
		"rear": float(rear) / contact,
		"exposure_flank": st["flank"],
		"exposure_rear": st["rear"],
		"outnumber": float(near) / maxf(soldiers.size(), 1.0),
		"cavalry": float(cav) / contact,
		"anti_cav": float(st["anti_cav"]) + float(u["anti_cavalry"]) * 0.5,
		"officer": _officer_bonus,
		"cohesion": st["morale"],
		"charging": order == Order.CHARGE,
	}
	var away := -(sum / sum_n).normalized() if sum_n > 0 else Vector3.ZERO
	return {"inputs": inputs, "pursued": nearest < Morale.SAFE_DISTANCE, "away": away}


## Front-line pairs lock in melee; the ranks behind wait in their slots until
## the men in front fall and the reassignment walks them forward.
func _engage() -> void:
	var charging := order == Order.CHARGE
	var lock := CHARGE_LOCK if charging else LOCK_RANGE
	var cap := CHARGE_CAP if charging else PAIR_CAP
	if order == Order.RETREAT or _enemies.is_empty():
		_targets.clear()
		_engaged = false
		_charge_point = null
		return
	var half := Formation.width(_local) * 0.5 + 2.0
	var reach := half + lock + 2.0
	var near: Array[Node3D] = []
	var nearest_d := INF
	_charge_point = null
	for e in _enemies:
		var d := Vector2(e.global_position.x - _centre.x, e.global_position.z - _centre.z).length()
		if d < reach:
			near.append(e)
		if d < nearest_d and d < CHARGE_LOCK + half:
			nearest_d = d
			_charge_point = e.global_position
	if near.is_empty():
		_targets.clear()
		_engaged = false
		return
	if charging:
		var c0 := _centre
		near.sort_custom(func(a: Node3D, b: Node3D) -> bool:
			return a.global_position.distance_squared_to(c0) < b.global_position.distance_squared_to(c0))
	# Keep pairs that still stand and are still in reach: melee stays locked.
	var count := {}
	var keep := {}
	var lock_sq := lock * lock * 1.7
	for s: Variant in _targets:
		var e: Variant = _targets[s]
		if is_instance_valid(s) and not (s as Soldier).dead and e != null and is_instance_valid(e) and not (e as Node).get("dead") \
				and (s as Soldier).global_position.distance_squared_to((e as Node3D).global_position) < lock_sq:
			keep[s] = e
			count[e] = int(count.get(e, 0)) + 1
	_targets = keep
	# Enemy buckets on a LOCK_RANGE grid: each free man only looks next door.
	var grid := {}
	for e in near:
		var c := Vector2i(floori(e.global_position.x / LOCK_RANGE), floori(e.global_position.z / LOCK_RANGE))
		if not grid.has(c):
			grid[c] = []
		(grid[c] as Array).append(e)
	# Pass 1 locks one man per enemy, pass 2 lets men already in contact double
	# up (wrapping a flank); in a charge everyone goes in.
	for pass_i in 2:
		var pass_cap := 1 if pass_i == 0 else cap
		var pass_range := LOCK_RANGE if pass_i == 0 or not charging else lock
		if pass_i == 1 and not charging:
			pass_range = LOCK_RANGE * 0.6
		for s in soldiers:
			if _targets.has(s):
				continue
			var best: Node3D = null
			var best_d := pass_range * pass_range
			var c := Vector2i(floori(s.global_position.x / LOCK_RANGE), floori(s.global_position.z / LOCK_RANGE))
			for gx in range(-1, 2):
				for gz in range(-1, 2):
					var bucket: Variant = grid.get(c + Vector2i(gx, gz))
					if bucket == null:
						continue
					for e: Node3D in bucket:
						if int(count.get(e, 0)) >= pass_cap:
							continue
						var d := s.global_position.distance_squared_to(e.global_position)
						if d < best_d:
							best_d = d
							best = e
			if best == null and pass_i == 1 and charging:
				# Beyond the next cell: head for the nearest of the enemy front.
				for e in near.slice(0, 8):
					if int(count.get(e, 0)) >= pass_cap:
						continue
					var d := s.global_position.distance_squared_to(e.global_position)
					if d < best_d:
						best_d = d
						best = e
			if best:
				_targets[s] = best
				count[best] = int(count.get(best, 0)) + 1
	_engaged = not _targets.is_empty()


func _scan_officers() -> void:
	_officers.clear()
	for n in get_tree().get_nodes_in_group("interactable"):
		if n is Captain:
			_officers.append(n)
	for n in get_tree().get_nodes_in_group("officer"):
		if n != self and not _officers.has(n):
			_officers.append(n)
	_officer_bonus = 0.0
	_officer_among = false
	var best := 0.0
	var total := 0.0
	var half := Formation.width(_local) * 0.5
	for o in _officers:
		if not is_instance_valid(o) or not (o is Node3D) or o.get("dead"):
			continue
		var ot: Variant = o.get("team")
		if (ot == null and team != 0) or (ot != null and int(ot) != team):
			continue
		var rank_id := str(o.get("rank_id")) if o.get("rank_id") != null else "captain"
		var d := (o as Node3D).global_position.distance_to(_centre)
		if d < RAMilitary.officer_radius(rank_id) + half:
			var b := RAMilitary.steadiness(rank_id)
			best = maxf(best, b)
			total += b
			_officer_among = _officer_among or d < 12.0
	# The commander leading his own men steadies them by his rank.
	if team == 0 and leader and is_instance_valid(leader):
		var d := leader.global_position.distance_to(_centre)
		if d < 25.0 + half:
			var b := minf(6.0 + 4.0 * Game.rank, 22.0)
			best = maxf(best, b)
			total += b
			_officer_among = _officer_among or d < 12.0
	_officer_bonus = minf(best + 0.25 * (total - best), Morale.OFFICER_CAP)


# --- Rout and rally -------------------------------------------------------------

func _begin_rout() -> void:
	_disperse_t = 0.0
	_targets.clear()
	_path.clear()
	_engaged = false
	clear_preview()
	var away := _away_from_enemies(_centre, 60.0)
	if away == Vector3.ZERO:
		away = -facing
	# Run for dry ground: try the straight way, then swing off either side.
	for swing: float in [0.0, 0.6, -0.6, 1.2, -1.2, 1.8, -1.8]:
		var dir := away.rotated(Vector3.UP, swing)
		var p := _centre + dir * FLEE_DISTANCE
		if WorldGen.water_depth(p.x, p.z) < WADE_DEPTH:
			away = dir
			break
	_flee_dir = away
	var side := away.cross(Vector3.UP)
	for s in soldiers:
		var p := s.global_position + away * FLEE_DISTANCE + side * randf_range(-18.0, 18.0)
		p.y = s.global_position.y
		s.slot_target = p
		s.combat_target = null
	routed.emit(self)


## away: direction away from the enemies still in sight (zero if none).
func _rally(away: Vector3) -> void:
	anchor = _formation_centre()
	var face := -away if away != Vector3.ZERO else -_flee_dir
	facing = _planar(face, facing)
	_face_goal = facing
	_final_face = facing
	_path.clear()
	order = Order.FOLLOW if leader else Order.HOLD
	_request_assign(true)
	rallied.emit(self)
	order_changed.emit(self)


func _disperse() -> void:
	var men := soldiers.duplicate()
	soldiers.clear()
	_slot_of.clear()
	_targets.clear()
	for s in men:
		if is_instance_valid(s):
			s.queue_free()
	banner.visible = false
	_standard.visible = false
	clear_preview()
	strength_changed.emit(0)
	wiped_out.emit(self)


# --- Helpers ----------------------------------------------------------------

func _formation_centre() -> Vector3:
	if soldiers.is_empty():
		return anchor
	var c := Vector3.ZERO
	for s in soldiers:
		c += s.global_position
	return c / soldiers.size()


func _away_from_enemies(from: Vector3, radius: float) -> Vector3:
	var sum := Vector3.ZERO
	var n := 0
	var list: Array = _enemies if not _enemies.is_empty() else get_tree().get_nodes_in_group("team%d" % (1 - team))
	for e in list:
		if not is_instance_valid(e) or e.get("dead"):
			continue
		var d: Vector3 = (e as Node3D).global_position - from
		d.y = 0.0
		if d.length() < radius:
			sum += d
			n += 1
	if n == 0 or sum.length() < 0.01:
		return Vector3.ZERO
	return -sum.normalized()


func _apply_stats(s: Soldier) -> void:
	if not s.has_meta("base_block"):
		s.set_meta("base_block", s.block_chance)
		s.set_meta("base_damage", s.damage)
	var u := RAMilitary.unit_type(unit_type)
	var st := Formation.stats(formation)
	s.block_chance = clampf(float(s.get_meta("base_block")) * float(st["defence"]) * float(u["defence"]), 0.02, 0.85)
	s.damage = maxi(1, roundi(float(s.get_meta("base_damage")) * float(u["damage"])))


func _on_soldier_died(s: Soldier) -> void:
	var i := soldiers.find(s)
	if i >= 0:
		soldiers.remove_at(i)
		if i < _slot_of.size():
			_slot_of.remove_at(i)
	_targets.erase(s)
	_face_of.erase(s)
	_deaths.append(_clock)
	while _deaths.size() > 0 and _clock - _deaths[0] > SHOCK_WINDOW:
		_deaths.remove_at(0)
	_request_assign(false)
	strength_changed.emit(soldiers.size())
	if soldiers.is_empty():
		banner.visible = false
		_standard.visible = false
		clear_preview()
		wiped_out.emit(self)


static func _planar(v: Vector3, fallback: Vector3) -> Vector3:
	v.y = 0.0
	return v.normalized() if v.length_squared() > 0.0001 else fallback


func _team_color() -> Color:
	return Color("7fb2ff") if team == 0 else Color("ff6b5b")


# --- Route planning (on orders only) --------------------------------------------

func _wet(x: float, z: float) -> bool:
	return WorldGen.water_depth(x, z) > WADE_DEPTH


func _clear_line(a: Vector3, b: Vector3) -> bool:
	var d := Vector2(b.x - a.x, b.z - a.z)
	var steps := maxi(1, ceili(d.length() / 4.0))
	for i in range(1, steps + 1):
		var t := float(i) / steps
		if _wet(a.x + d.x * t, a.z + d.y * t):
			return false
	return true


## Straight there if the way is dry; otherwise A* round the water on a coarse
## grid, string-pulled to a few waypoints. Runs once per order.
func _plan_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	if _clear_line(from, to):
		out.append(to)
		return out
	var lo := Vector2(minf(from.x, to.x), minf(from.z, to.z)) - Vector2(80, 80)
	var hi := Vector2(maxf(from.x, to.x), maxf(from.z, to.z)) + Vector2(80, 80)
	var cell := maxf(PATH_CELL, maxf(hi.x - lo.x, hi.y - lo.y) / PATH_MAX_CELLS)
	var w := ceili((hi.x - lo.x) / cell) + 1
	var h := ceili((hi.y - lo.y) / cell) + 1
	var state := PackedByteArray()   # 0 unknown, 1 dry, 2 wet
	state.resize(w * h)
	var g := PackedFloat32Array()
	g.resize(w * h)
	g.fill(INF)
	var came := PackedInt32Array()
	came.resize(w * h)
	came.fill(-1)
	var to_cell := func(p: Vector3) -> int:
		return clampi(roundi((p.z - lo.y) / cell), 0, h - 1) * w + clampi(roundi((p.x - lo.x) / cell), 0, w - 1)
	var start: int = to_cell.call(from)
	var goal: int = to_cell.call(to)
	# A wet destination: stop at the last dry ground on the way.
	if _wet(to.x, to.z):
		var d := to - from
		for k in range(20, -1, -1):
			var p := from + d * (k / 20.0)
			if not _wet(p.x, p.z):
				to = p
				break
		goal = to_cell.call(to)
	var heap: Array = []
	g[start] = 0.0
	_heap_push(heap, 0.0, start)
	var gx := goal % w
	var gz := goal / w
	var expansions := 0
	var found := false
	while not heap.is_empty() and expansions < 5000:
		var cur := _heap_pop(heap)
		if cur == goal:
			found = true
			break
		expansions += 1
		var cx := cur % w
		var cz := cur / w
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				if dx == 0 and dz == 0:
					continue
				var nx := cx + dx
				var nz := cz + dz
				if nx < 0 or nz < 0 or nx >= w or nz >= h:
					continue
				var ni := nz * w + nx
				if state[ni] == 0:
					state[ni] = 2 if _wet(lo.x + nx * cell, lo.y + nz * cell) else 1
				if state[ni] == 2 and ni != goal:
					continue
				var ng := g[cur] + (1.4142 if dx != 0 and dz != 0 else 1.0)
				if ng < g[ni]:
					g[ni] = ng
					came[ni] = cur
					var ddx := absi(nx - gx)
					var ddz := absi(nz - gz)
					_heap_push(heap, ng + maxi(ddx, ddz) + 0.4142 * mini(ddx, ddz), ni)
	if not found:
		out.append(to)
		return out
	var cells := PackedVector3Array()
	var c := goal
	while c != -1 and c != start:
		var p := Vector3(lo.x + (c % w) * cell, 0, lo.y + (c / w) * cell)
		cells.append(p)
		c = came[c]
	cells.reverse()
	if not cells.is_empty():
		cells[cells.size() - 1] = to
	# String-pull: keep a waypoint only where the straight line gets wet.
	var at := from
	var i := 0
	while i < cells.size():
		var j := cells.size() - 1
		while j > i and not _clear_line(at, cells[j]):
			j -= 1
		var wp := cells[j]
		wp.y = WorldGen.height(wp.x, wp.z)
		out.append(wp)
		at = wp
		i = j + 1
	return out


static func _heap_push(heap: Array, f: float, i: int) -> void:
	heap.append(Vector2(f, i))
	var k := heap.size() - 1
	while k > 0:
		var parent := (k - 1) / 2
		if (heap[parent] as Vector2).x <= (heap[k] as Vector2).x:
			break
		var t: Vector2 = heap[parent]
		heap[parent] = heap[k]
		heap[k] = t
		k = parent


static func _heap_pop(heap: Array) -> int:
	var top: Vector2 = heap[0]
	var last: Vector2 = heap.pop_back()
	if not heap.is_empty():
		heap[0] = last
		var k := 0
		var n := heap.size()
		while true:
			var l := k * 2 + 1
			var r := l + 1
			var m := k
			if l < n and (heap[l] as Vector2).x < (heap[m] as Vector2).x:
				m = l
			if r < n and (heap[r] as Vector2).x < (heap[m] as Vector2).x:
				m = r
			if m == k:
				break
			var t: Vector2 = heap[m]
			heap[m] = heap[k]
			heap[k] = t
			k = m
	return int(top.y)


# --- Visuals ------------------------------------------------------------------

func _update_banner() -> void:
	if soldiers.is_empty():
		return
	var center := _centre
	_banner_pos = Vector3(center.x, WorldGen.height(center.x, center.z), center.z)
	var cam := get_viewport().get_camera_3d()
	var dist := cam.global_position.distance_to(center) if cam else 0.0
	# A formation marker for command view: not in cutscenes, not through the whole world.
	var vis := cam != null and cam.current and cam.get_parent() is not CutscenePlayer \
		and dist > 22.0 and dist < 260.0 and not get_tree().get_nodes_in_group("cutscene_active").size()
	# Our own army's standard only shows in the command / overview cameras, not over the
	# plaza while it follows us around town (playtest: "12 · Line" hanging over Ashford).
	# Every squad's standard (bandits, garrisons, ours) is a command-view tool only: in the normal
	# third-person view "☠ 4 · Line" floated over bandit camps and the Watch Post (POI review 2026-10-05).
	var viewer: Node = leader if leader and is_instance_valid(leader) else get_tree().get_first_node_in_group("player")
	if vis:
		vis = viewer != null and viewer.get("view") != null and int(viewer.get("view")) >= 2
	if vis and not banner.visible:
		_standard.global_position = _banner_pos    # appear in place, don't slide in
	banner.visible = vis
	_standard.visible = vis
	if not vis:
		return
	# The standard grows with distance so it still reads from command height.
	_standard.scale = Vector3.ONE * clampf(dist / 45.0, 1.0, 3.5)
	var trail := -facing
	_standard.rotation.y = atan2(-trail.z, trail.x)
	var text := "%s %d · %s" % ["⚑" if team == 0 else "☠", soldiers.size(), Formation.type_name(formation)]
	var col := _team_color()
	if morale.is_broken():
		text = "%s %d · %s" % ["⚑" if team == 0 else "☠", soldiers.size(), morale.state_name().to_upper()]
		col = Color(0.75, 0.75, 0.75, 0.55 + 0.45 * absf(sin(_clock * 5.0)))
	elif morale.state == Morale.State.WAVERING:
		text += " !"
		col = col.lerp(Color(0.7, 0.7, 0.7), 0.5)
	if text != _banner_text:
		_banner_text = text
		banner.text = text
	banner.modulate = col


## Pole with a Chinese-style war banner: a tall cloth hung from the pole with a
## flame-tooth trim along its free edge. Built once, unshaded, no shadow.
func _build_standard() -> Node3D:
	var root := Node3D.new()
	root.top_level = true
	var col := _team_color()
	var pole := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.035
	cyl.bottom_radius = 0.045
	cyl.height = 4.6
	cyl.radial_segments = 6
	cyl.rings = 1
	pole.mesh = cyl
	pole.position.y = 2.3
	pole.material_override = _flat(Color("3a2a1c"))
	pole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(pole)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cloth := col.darkened(0.15)
	var trim := Color("e8c060") if team == 0 else Color("2a1a14")
	var top := 4.4
	var bottom := 2.5
	var wid := 1.1
	_quad(st, Vector3(0, bottom, 0), Vector3(wid, bottom, 0), Vector3(wid, top, 0), Vector3(0, top, 0), cloth)
	var teeth := 5
	var th := (top - bottom) / teeth
	for i in teeth:
		var y0 := bottom + i * th
		st.set_color(trim)
		st.add_vertex(Vector3(wid, y0, 0))
		st.add_vertex(Vector3(wid, y0 + th, 0))
		st.add_vertex(Vector3(wid + 0.28, y0 + th * 0.5, 0))
	# Trim along the bottom hem.
	_quad(st, Vector3(0, bottom - 0.12, 0), Vector3(wid, bottom - 0.12, 0), Vector3(wid, bottom, 0), Vector3(0, bottom, 0), trim)
	var flag := MeshInstance3D.new()
	flag.mesh = st.commit()
	var mat := _flat(Color.WHITE)
	mat.vertex_color_use_as_albedo = true
	flag.material_override = mat
	flag.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(flag)
	var tip := MeshInstance3D.new()
	var spike := PrismMesh.new()
	spike.size = Vector3(0.12, 0.3, 0.12)
	tip.mesh = spike
	tip.position.y = 4.75
	tip.material_override = _flat(Color("e8c060"))
	tip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(tip)
	return root


func _ensure_ghost() -> void:
	if _ghost:
		return
	_ghost_mat = _flat(_team_color().lightened(0.25))
	_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_mat.vertex_color_use_as_albedo = false
	# Small pennant: a peg and a triangular flag. One draw call for the whole block.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c := Color.WHITE
	var pw := 0.03
	_quad(st, Vector3(-pw, 0, 0), Vector3(pw, 0, 0), Vector3(pw, 0.9, 0), Vector3(-pw, 0.9, 0), c)
	_quad(st, Vector3(0, 0, -pw), Vector3(0, 0, pw), Vector3(0, 0.9, pw), Vector3(0, 0.9, -pw), c)
	st.set_color(c)
	st.add_vertex(Vector3(0, 0.62, 0))
	st.add_vertex(Vector3(0, 0.9, 0))
	st.add_vertex(Vector3(0, 0.76, -0.38))    # flag streams to the rear (-forward)
	# Ground tick: a flat diamond so the slot reads from straight above.
	var r := 0.28
	_quad(st, Vector3(0, 0.03, r), Vector3(r, 0.03, 0), Vector3(0, 0.03, -r), Vector3(-r, 0.03, 0), c)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = st.commit()
	_ghost = MultiMeshInstance3D.new()
	_ghost.multimesh = mm
	_ghost.top_level = true
	_ghost.material_override = _ghost_mat
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost.visible = false
	add_child(_ghost)
	# Facing chevron in front of the block.
	var ast := SurfaceTool.new()
	ast.begin(Mesh.PRIMITIVE_TRIANGLES)
	for v: Vector3 in [Vector3(0, 0, 1.4), Vector3(1.2, 0, -0.4), Vector3(0, 0, 0.2),
			Vector3(0, 0, 1.4), Vector3(0, 0, 0.2), Vector3(-1.2, 0, -0.4)]:
		ast.set_color(c)
		ast.add_vertex(v)
	_ghost_arrow = MeshInstance3D.new()
	_ghost_arrow.mesh = ast.commit()
	_ghost_arrow.top_level = true
	_ghost_arrow.material_override = _ghost_mat
	_ghost_arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost_arrow.visible = false
	add_child(_ghost_arrow)


## Where each man will stand: pennants on the ground at the destination slots.
func _show_ghost(centre: Vector3, face: Vector3, fade: bool) -> void:
	_ensure_ghost()
	face = _planar(face, facing)
	var n := maxi(soldiers.size(), 1)
	var local := Formation.slots(formation, n, _cols)
	var mm := _ghost.multimesh
	mm.instance_count = local.size()
	var front := -INF
	for i in local.size():
		front = maxf(front, local[i].y)
		var p := Formation.to_world(local[i], centre, face)
		p.y = WorldGen.height(p.x, p.z) + 0.02
		var lf := Formation.slot_facing(formation, local[i])
		var right := face.cross(Vector3.UP)
		var f := right * lf.x + face * lf.y
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, atan2(f.x, f.z)), p))
	var tip := Formation.to_world(Vector2(0, front + 2.2), centre, face)
	tip.y = WorldGen.height(tip.x, tip.z) + 0.08
	_ghost_arrow.global_transform = Transform3D(Basis(Vector3.UP, atan2(face.x, face.z)), tip)
	_ghost.visible = true
	_ghost_arrow.visible = true
	if _ghost_tween:
		_ghost_tween.kill()
	_ghost_mat.albedo_color.a = 0.85
	if fade:
		_ghost_tween = create_tween()
		_ghost_tween.tween_interval(1.2)
		_ghost_tween.tween_property(_ghost_mat, "albedo_color:a", 0.0, 1.8)
		_ghost_tween.tween_callback(clear_preview)


static func _flat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = c
	return m


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	for v: Vector3 in [a, b, c, a, c, d]:
		st.set_color(col)
		st.add_vertex(v)
