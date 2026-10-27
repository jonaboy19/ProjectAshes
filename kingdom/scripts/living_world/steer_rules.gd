class_name SteerRules
extends RefCounted
## S1-S8 steering for the NPC motion layer (docs/plans/NPC_MOTION_RULES.md section 3.1). Pure, static, deterministic, no
## allocation in the per-tick paths (a body keeps one SteerRules.Result and refills it).
##
##   var res := SteerRules.Result.new()                                  # once per body (or use the rule_* wrappers via MotionRules)
##   var v := SteerRules.desired_velocity(res, ctx, arch, persona, tier) # Vector2 world XZ m/s: route velocity + S2..S8
##   body.velocity = Vector3(v.x, 0, v.y)                                # or feed it to the RVO agent as its preferred velocity
##
## ctx keys read (all optional; a rule whose inputs are absent does nothing):
##   position Vector3, velocity Vector3 (the route velocity), carrying bool, age float (years)
##   corridor_width float (StreetLanes.corridor_width), edge_width float + edge_lateral float (S8: street width, signed offset
##     of the body from the street centre line, positive = right of travel)
##   oncoming_pos / oncoming_vel Vector3, oncoming_rank float (effective rank, see effective_rank), oncoming_id int,
##     oncoming_radius float: the one neighbour the body chose to worry about (nearest on a collision course)
##   mover_pos / mover_vel Vector3: the nearest cart, horse or rider (NpcWorld movers)
##   pair_pos / pair_vel Vector3 + pair_side float (+1 right, -1 left): S6 partner slot owner (the leader)
##   running bool (else speed >= RUN_SPEED), tier (int, MotionRules.TIER_*): S3 shoulder turn is NEAR only
## Hazards (S5) come from HazardField. The persona gives id (hashing); the archetype gives yield_rank and rvo_radius_m.
##
## Sides: "right" is StreetLanes.right_of(heading). Every pass convention here keeps right.

const TIER_NEAR := 0
const RUN_SPEED := 3.0                  # m/s: runners splash through hazards and skip the polite rules
const MAX_STEER := 2.5                  # m/s cap on the summed lateral offset
const DEFAULT_RADIUS := 0.5

# S2
const YIELD_HORIZON_S := 2.5
const YIELD_SLOW_MUL := 0.4
const YIELD_STEP_M := 0.6
const YIELD_HOLD_FRAC := 0.15           # the higher rank still leans this much of the step (barely deviates)
const LOADED_RANK_BONUS := 1.0
const ELDER_AGE := 60.0
# S3
const PASS_CORRIDOR_MAX_M := 1.6
const PASS_ONCOMING_M := 3.0
const PASS_TURN_M := 1.6                # the shoulder turn starts when the other is this close
const PASS_BIAS_SPEED := 0.5
const PASS_SLOW_MUL := 0.85
const PASS_TURN_DEG_LO := 30.0
const PASS_TURN_DEG_HI := 40.0
const PASS_TURN_CLIP := "Life_Pass_Shoulder_Turn_Upper"
# S4
const MOVER_LOOKAHEAD_S := 3.0
const MOVER_STOP_M := 2.6
const MOVER_LANE_HALF_M := 1.3
const MOVER_MIN_SPEED := 0.6
const MOVER_STEP_SPEED := 2.2
const MOVER_PASSED_M := 1.5             # resume only once the mover's centre is this far past the walker
# S5
const HAZARD_BODY_M := 0.35
const HAZARD_LOOK_M := 1.5
const HAZARD_GAIN := 1.2
# S6
const PAIR_OFFSET_M := 0.7
const PAIR_GAIN := 2.0
const PAIR_MAX_STEER := 1.2
const PAIR_DEADBAND_M := 0.08
# S8
const LANE_GAIN := 1.5
const LANE_MAX_STEER := 0.5

# RVO (S1)
const MAX_SPEED := 6.0
const TIME_HORIZON_AGENTS_S := 1.5
const TIME_HORIZON_OBSTACLES_S := 1.0
const MAX_NEIGHBORS := 6
const NEIGHBOR_DISTANCE_M := 5.0
const AGENT_HEIGHT_M := 1.8
const LOADED_PRIORITY_BONUS := 0.15
## One avoidance layer bit per archetype; vehicles get their own bit. Everyone avoids everyone and vehicles by default.
const ARCH_LAYER := {"villager": 1, "child": 2, "elder": 4, "guard": 8, "bandit": 16, "follower": 32, "merchant": 64, "noble": 128}
const LAYER_VEHICLE := 256
const MASK_WALKERS := 255
const MASK_ALL := 511
## Vehicle obstacle radius by kind (m).
const VEHICLE_RADIUS := {"cart": 1.2, "wagon": 1.4, "horse": 0.7, "rider": 0.8, "player_mount": 0.8}
## Fallback when data/living_world/motion_rules.json is unavailable: [rvo_radius_m, rvo_priority, yield_rank].
const FALLBACK := {"villager": [0.5, 0.5, 2.0], "child": [0.3, 0.2, 1.0], "elder": [0.5, 0.6, 4.0], "guard": [0.9, 0.8, 5.0],
	"bandit": [0.6, 0.6, 3.0], "follower": [0.5, 0.5, 3.0], "merchant": [0.55, 0.5, 3.0], "noble": [0.8, 0.9, 6.0]}


## Reusable output of one steering evaluation. A body owns one; reset() before each use.
class Result extends RefCounted:
	var steer := Vector2.ZERO          # world XZ offset on top of the route velocity (m/s)
	var speed_mul := 1.0               # multiplier on the route velocity
	var stop := false                  # hold still (the route velocity contributes nothing)
	var turn := false                  # S3: play the shoulder-turn upper clip
	var turn_deg := 0.0                # S3: torso yaw magnitude (30..40)
	var turn_side := 0.0               # S3: +1 = toward the left shoulder (the oncoming walker is on the left when both keep right)
	var fired := 0                     # bit n = rule S(n+1) contributed

	func reset() -> void:
		steer = Vector2.ZERO
		speed_mul = 1.0
		stop = false
		turn = false
		turn_deg = 0.0
		turn_side = 0.0
		fired = 0

	## The final velocity for a route velocity.
	func velocity(route: Vector2) -> Vector2:
		return (Vector2.ZERO if stop else route * speed_mul) + steer


static var _rvo := {}
static var _scratch := Result.new()


# ---------------------------------------------------------------------------------------------------------------------
# S1: RVO parameters, avoidance agents and vehicle obstacles (NavigationServer3D). Routing stays on StreetGraph; the server only
# bends the velocity.
# ---------------------------------------------------------------------------------------------------------------------

## Avoidance parameters of an archetype: radius, priority (0..1, higher = others give way), layers, mask, time_horizon_agents,
## time_horizon_obstacles, max_neighbors, neighbor_distance, max_speed, yield_rank. The same Dictionary every call (do not edit).
## Numbers come from data/living_world/motion_rules.json (rvo_radius_m, rvo_priority, yield_rank).
static func rvo_params(archetype: String) -> Dictionary:
	var cached: Variant = _rvo.get(archetype)
	if cached != null:
		return cached
	var key := archetype if FALLBACK.has(archetype) else MotionRules.DEFAULT_ARCHETYPE
	var f: Array = FALLBACK[key]
	var arch: Dictionary = MotionRules.default_registry().archetypes.get(key, {})
	var p := {
		"archetype": key,
		"radius": float(arch.get("rvo_radius_m", f[0])),
		"priority": float(arch.get("rvo_priority", f[1])),
		"yield_rank": float(arch.get("yield_rank", f[2])),
		"layers": ARCH_LAYER[key],
		"mask": MASK_ALL,
		"time_horizon_agents": TIME_HORIZON_AGENTS_S,
		"time_horizon_obstacles": TIME_HORIZON_OBSTACLES_S,
		"max_neighbors": MAX_NEIGHBORS,
		"neighbor_distance": NEIGHBOR_DISTANCE_M,
		"max_speed": MAX_SPEED,
	}
	_rvo[archetype] = p
	return p


## Avoidance priority of a body: its archetype priority, raised when it carries a load (others give way).
static func rvo_priority(archetype: String, loaded: bool) -> float:
	var pr: float = rvo_params(archetype)["priority"]
	return minf(pr + LOADED_PRIORITY_BONUS, 1.0) if loaded else pr


## Creates and configures a NavigationServer3D avoidance agent for one body on `map` (2D avoidance in the XZ plane).
## `callback` receives the safe velocity (Vector3) after each map step; pass Callable() to read it elsewhere.
## `mask` excludes layers (e.g. a walking partner); -1 uses the archetype default.
static func create_agent(map: RID, archetype: String, at: Vector3, callback := Callable(), loaded := false, mask := -1) -> RID:
	var p := rvo_params(archetype)
	var agent := NavigationServer3D.agent_create()
	NavigationServer3D.agent_set_map(agent, map)
	NavigationServer3D.agent_set_avoidance_enabled(agent, true)
	NavigationServer3D.agent_set_use_3d_avoidance(agent, false)
	NavigationServer3D.agent_set_radius(agent, p["radius"])
	NavigationServer3D.agent_set_height(agent, AGENT_HEIGHT_M)
	NavigationServer3D.agent_set_avoidance_priority(agent, rvo_priority(archetype, loaded))
	NavigationServer3D.agent_set_avoidance_layers(agent, p["layers"])
	NavigationServer3D.agent_set_avoidance_mask(agent, p["mask"] if mask < 0 else mask)
	NavigationServer3D.agent_set_time_horizon_agents(agent, p["time_horizon_agents"])
	NavigationServer3D.agent_set_time_horizon_obstacles(agent, p["time_horizon_obstacles"])
	NavigationServer3D.agent_set_max_neighbors(agent, p["max_neighbors"])
	NavigationServer3D.agent_set_neighbor_distance(agent, p["neighbor_distance"])
	NavigationServer3D.agent_set_max_speed(agent, p["max_speed"])
	NavigationServer3D.agent_set_position(agent, at)
	if callback.is_valid():
		NavigationServer3D.agent_set_avoidance_callback(agent, callback)
	return agent


## Per-think update: the preferred (target) velocity and current position of an agent. The callback gets the safe velocity.
static func agent_update(agent: RID, at: Vector3, preferred: Vector2) -> void:
	NavigationServer3D.agent_set_position(agent, at)
	NavigationServer3D.agent_set_velocity(agent, Vector3(preferred.x, 0.0, preferred.y))


static func destroy_agent(agent: RID) -> void:
	if agent.is_valid():
		NavigationServer3D.free_rid(agent)


## A moving vehicle (cart, horse, rider) as an avoidance obstacle with a velocity: walkers on the vehicle layer's mask route
## around where it will be. `kind` picks the radius from VEHICLE_RADIUS.
static func create_vehicle_obstacle(map: RID, kind: String, at: Vector3, velocity := Vector3.ZERO) -> RID:
	var ob := NavigationServer3D.obstacle_create()
	NavigationServer3D.obstacle_set_map(ob, map)
	NavigationServer3D.obstacle_set_use_3d_avoidance(ob, false)
	NavigationServer3D.obstacle_set_radius(ob, float(VEHICLE_RADIUS.get(kind, 1.0)))
	NavigationServer3D.obstacle_set_height(ob, AGENT_HEIGHT_M)
	NavigationServer3D.obstacle_set_avoidance_layers(ob, LAYER_VEHICLE)
	NavigationServer3D.obstacle_set_position(ob, at)
	NavigationServer3D.obstacle_set_velocity(ob, velocity)
	NavigationServer3D.obstacle_set_avoidance_enabled(ob, true)
	return ob


static func update_vehicle_obstacle(ob: RID, at: Vector3, velocity: Vector3) -> void:
	NavigationServer3D.obstacle_set_position(ob, at)
	NavigationServer3D.obstacle_set_velocity(ob, velocity)


static func destroy_obstacle(ob: RID) -> void:
	if ob.is_valid():
		NavigationServer3D.free_rid(ob)


# ---------------------------------------------------------------------------------------------------------------------
# Geometry helpers
# ---------------------------------------------------------------------------------------------------------------------

## Seconds until two discs (relative position `rel` = other - me, relative velocity `relv` = other - me, summed radius `rsum`)
## touch, or INF when they never do. 0 when already overlapping.
static func collision_time(rel: Vector2, relv: Vector2, rsum: float) -> float:
	var c := rel.length_squared() - rsum * rsum
	if c <= 0.0:
		return 0.0
	var a := relv.length_squared()
	if a < 1e-6:
		return INF
	var b := rel.dot(relv)
	if b >= 0.0:
		return INF
	var disc := b * b - a * c
	if disc < 0.0:
		return INF
	return (-b - sqrt(disc)) / a


## Unit heading of a velocity, or `fallback` when it is (nearly) zero.
static func heading_of(v: Vector2, fallback: Vector2) -> Vector2:
	var l := v.length()
	return v / l if l > 0.1 else fallback


## +1 / -1 from an id: deterministic side choice for symmetric cases.
static func side_of(key: int, salt: int) -> float:
	return 1.0 if StreetLanes.hash01(key, salt) >= 0.5 else -1.0


# ---------------------------------------------------------------------------------------------------------------------
# S2: yield / give way (rank x load x age)
# ---------------------------------------------------------------------------------------------------------------------

## Effective yield rank: the archetype rank, plus a bonus for a load, plus one for age (elders and loaded people get way).
static func effective_rank(base_rank: float, loaded: bool, age_years := 0.0) -> float:
	var r := base_rank
	if loaded:
		r += LOADED_RANK_BONUS
	if age_years >= ELDER_AGE:
		r += 1.0
	return r


## Who gives way: +1 = I yield, -1 = I hold (the other yields), 0 = nobody (equal rank and equal key).
static func yield_role(my_rank: float, other_rank: float, my_key: int, other_key: int) -> int:
	if my_rank < other_rank:
		return 1
	if my_rank > other_rank:
		return -1
	if my_key == other_key:
		return 0
	return 1 if my_key < other_key else -1


## S2. A neighbour on a collision course within `horizon`: the lower rank slows to `slow` x and steps `step` m to its pass side
## (right), the higher rank barely deviates. Writes into res (steer, speed_mul); true when it fired.
static func yield_step(res: Result, here: Vector2, route: Vector2, my_rank: float, my_key: int, my_r: float,
		o_pos: Vector2, o_vel: Vector2, o_rank: float, o_key: int, o_r: float,
		horizon := YIELD_HORIZON_S, slow := YIELD_SLOW_MUL, step := YIELD_STEP_M) -> bool:
	var rel := o_pos - here
	var t := collision_time(rel, o_vel - route, my_r + o_r + 0.1)
	if t > horizon:
		return false
	var role := yield_role(my_rank, o_rank, my_key, o_key)
	if role == 0:
		return false
	var dir := heading_of(route, rel.normalized() if rel.length_squared() > 0.0001 else Vector2(0.0, 1.0))
	var right := StreetLanes.right_of(dir)
	if role > 0:
		res.speed_mul = minf(res.speed_mul, slow)
		res.steer += right * step
	else:
		res.steer += right * (step * YIELD_HOLD_FRAC)
	res.fired |= 2
	return true


# ---------------------------------------------------------------------------------------------------------------------
# S3: pass on the right + shoulder turn in narrow alleys
# ---------------------------------------------------------------------------------------------------------------------

## True when the narrow-alley pass applies: corridor under `corridor_max`, the other within `oncoming_m`, ahead of me and closing.
static func pass_applies(width: float, here: Vector2, route: Vector2, o_pos: Vector2, o_vel: Vector2,
		corridor_max := PASS_CORRIDOR_MAX_M, oncoming_m := PASS_ONCOMING_M) -> bool:
	if width >= corridor_max:
		return false
	var rel := o_pos - here
	var d := rel.length()
	if d > oncoming_m or d < 0.001:
		return false
	var dir := heading_of(route, rel / d)
	if dir.dot(rel) <= 0.0:
		return false
	return rel.dot(o_vel - route) < 0.0


## S3. Keep right: a side bias (m/s along my right) that ramps up as the other closes, a slight slow-down, and, at NEAR,
## the shoulder turn (torso yaw 30..40 degrees by hash) once the other is within `turn_m`.
static func pass_right(res: Result, width: float, here: Vector2, route: Vector2, o_pos: Vector2, o_vel: Vector2,
		key: int, tier: int, corridor_max := PASS_CORRIDOR_MAX_M, oncoming_m := PASS_ONCOMING_M, turn_m := PASS_TURN_M) -> bool:
	if not pass_applies(width, here, route, o_pos, o_vel, corridor_max, oncoming_m):
		return false
	var rel := o_pos - here
	var d := rel.length()
	var dir := heading_of(route, rel / d)
	var ramp := clampf((oncoming_m - d) / maxf(oncoming_m - 1.0, 0.1), 0.3, 1.0)
	res.steer += StreetLanes.right_of(dir) * (PASS_BIAS_SPEED * ramp)
	res.speed_mul = minf(res.speed_mul, PASS_SLOW_MUL)
	if tier <= TIER_NEAR and d <= turn_m:
		res.turn = true
		res.turn_deg = lerpf(PASS_TURN_DEG_LO, PASS_TURN_DEG_HI, StreetLanes.hash01(key, 0x5170))
		res.turn_side = 1.0
	res.fired |= 4
	return true


# ---------------------------------------------------------------------------------------------------------------------
# S4: stop for carts and horses
# ---------------------------------------------------------------------------------------------------------------------

## S4. The mover is predicted (within `lookahead` s) to pass closer than `stop_m`: a walker outside the lane stops at the
## kerb and watches it go; one already inside the lane (`lane_half` m of the line) steps out sideways. Once the mover is
## MOVER_PASSED_M beyond the walker (moving away) or far, nothing fires and the walker resumes. Mirrors NpcWorld.mover_push geometry, but stops
## instead of pushing.
static func mover_stop(res: Result, here: Vector2, m_pos: Vector2, m_vel: Vector2, key: int,
		lookahead := MOVER_LOOKAHEAD_S, stop_m := MOVER_STOP_M, lane_half := MOVER_LANE_HALF_M) -> bool:
	var speed2 := m_vel.length_squared()
	if speed2 < MOVER_MIN_SPEED * MOVER_MIN_SPEED:
		return false
	var rel := here - m_pos
	if rel.length_squared() > 400.0:
		return false
	var along := rel.dot(m_vel)
	if along <= -MOVER_PASSED_M * sqrt(speed2):
		return false                       # the mover has gone well past
	var t := clampf(along / speed2, 0.0, lookahead)
	var d := (rel - m_vel * t).length()
	if d >= stop_m:
		return false
	var right := StreetLanes.right_of(m_vel / sqrt(speed2))
	var lat := rel.dot(right)
	if absf(lat) < lane_half:
		var side := signf(lat) if absf(lat) > 0.05 else side_of(key, 0x4d0e)
		res.stop = true
		res.steer += right * (side * MOVER_STEP_SPEED)
	else:
		res.stop = true
	res.fired |= 8
	return true


# ---------------------------------------------------------------------------------------------------------------------
# S5: hazards
# ---------------------------------------------------------------------------------------------------------------------

## S5. Steer sideways around puddles, mud, fire and dung registered in HazardField that lie on the way (a corridor ahead of
## the heading). Runners (speed >= RUN_SPEED) splash through. Adds a lateral offset only; the route velocity is untouched.
static func avoid_hazards(res: Result, here: Vector2, route: Vector2, key: int, running := false) -> bool:
	if running or HazardField.count() == 0:
		return false
	var speed := route.length()
	if speed < 0.1 or speed >= RUN_SPEED:
		return false
	var dir := route / speed
	var right := StreetLanes.right_of(dir)
	var n := HazardField.query(here + dir * (HAZARD_LOOK_M * 0.5), HAZARD_LOOK_M * 0.5 + HAZARD_BODY_M, HazardField.scratch)
	var push := Vector2.ZERO
	for k in n:
		var i := HazardField.scratch[k]
		var to := Vector2(HazardField.slot_x(i), HazardField.slot_z(i)) - here
		var rr := HazardField.slot_radius(i) + HAZARD_BODY_M
		var along := to.dot(dir)
		var lat := to.dot(right)
		if along < -rr or along > rr + HAZARD_LOOK_M or absf(lat) >= rr:
			continue
		var side := -signf(lat) if absf(lat) > 0.05 else side_of(key, 0x6a2b + i)
		var need := clampf((rr - absf(lat)) / rr, 0.0, 1.0)
		var near := 1.0 - clampf(maxf(along, 0.0) / (rr + HAZARD_LOOK_M), 0.0, 1.0)
		push += right * (side * need * (0.4 + 0.6 * near) * speed * HAZARD_GAIN)
	if push == Vector2.ZERO:
		return false
	res.steer += push.limit_length(MAX_STEER)
	res.fired |= 16
	return true


# ---------------------------------------------------------------------------------------------------------------------
# S6: walk in pairs
# ---------------------------------------------------------------------------------------------------------------------

## The partner's slot beside the leader: `side` +1 on the leader's right, -1 on the left; `offset` m abeam.
static func pair_slot(leader_pos: Vector2, leader_dir: Vector2, side: float, offset := PAIR_OFFSET_M) -> Vector2:
	return leader_pos + StreetLanes.right_of(leader_dir) * (side * offset)


## The pair walks at the pace of the slower one.
static func pair_speed(my_pref: float, partner_pref: float) -> float:
	return minf(my_pref, partner_pref)


## S6. Partner steering: a velocity offset toward the slot beside the leader (deadband PAIR_DEADBAND_M).
static func pair_steer(res: Result, here: Vector2, slot: Vector2, gain := PAIR_GAIN) -> bool:
	var err := slot - here
	if err.length() < PAIR_DEADBAND_M:
		return false
	res.steer += (err * gain).limit_length(PAIR_MAX_STEER)
	res.fired |= 32
	return true


# ---------------------------------------------------------------------------------------------------------------------
# S8: road edge lanes
# ---------------------------------------------------------------------------------------------------------------------

## S8. Drift toward this person's lane (StreetLanes.lane_offset) on a street wider than 3 m. `lateral` is the body's signed
## offset from the street centre line (right positive). Carts keep the centre because nobody is steered toward it.
static func lane_steer(res: Result, route: Vector2, width: float, lateral: float, key: int, body_radius := 0.35,
		min_width := StreetLanes.LANE_MIN_EDGE_WIDTH) -> bool:
	var speed := route.length()
	if speed < 0.1 or width < min_width:
		return false
	var err := StreetLanes.lane_offset(width, key, body_radius, min_width) - lateral
	if absf(err) < 0.05:
		return false
	res.steer += StreetLanes.right_of(route / speed) * clampf(err * LANE_GAIN, -LANE_MAX_STEER, LANE_MAX_STEER)
	res.fired |= 128
	return true


# ---------------------------------------------------------------------------------------------------------------------
# Composition
# ---------------------------------------------------------------------------------------------------------------------

static func _v2(v: Variant) -> Vector2:
	return Vector2((v as Vector3).x, (v as Vector3).z)


static func _key(persona: Dictionary) -> int:
	return int(persona.get("id", 0))


## The desired velocity (world XZ) of a body: the route velocity from ctx, plus S2 yield, S3 pass-right, S4 mover stop,
## S5 hazards, S6 pair offset and S8 lane offset, each only when its inputs are in ctx. `res` is refilled.
static func desired_velocity(res: Result, ctx: Dictionary, arch: Dictionary, persona: Dictionary, tier: int) -> Vector2:
	res.reset()
	var route := Vector2.ZERO
	var rv: Variant = ctx.get("velocity")
	if rv is Vector3:
		route = _v2(rv)
	var pv: Variant = ctx.get("position")
	if not (pv is Vector3):
		return route
	var here := _v2(pv)
	var key := _key(persona)
	var running: bool = ctx.get("running", route.length() >= RUN_SPEED)
	var my_r: float = MotionRules.param(arch, persona, "rvo_radius_m", DEFAULT_RADIUS)
	# S4 first: it can stop the walker outright
	var mp: Variant = ctx.get("mover_pos")
	if mp is Vector3 and ctx.get("mover_vel") is Vector3:
		mover_stop(res, here, _v2(mp), _v2(ctx["mover_vel"]), key)
	var op: Variant = ctx.get("oncoming_pos")
	if op is Vector3 and ctx.get("oncoming_vel") is Vector3:
		var ov := _v2(ctx["oncoming_vel"])
		var op2 := _v2(op)
		if not running:
			var rank := effective_rank(float(MotionRules.param(arch, persona, "yield_rank", 2.0)), bool(ctx.get("carrying", false)),
				float(ctx.get("age", persona.get("age", 0.0))))
			yield_step(res, here, route, rank, key, my_r, op2, ov, float(ctx.get("oncoming_rank", 2.0)),
				int(ctx.get("oncoming_id", key + 1)), float(ctx.get("oncoming_radius", DEFAULT_RADIUS)))
		if ctx.has("corridor_width"):
			pass_right(res, float(ctx["corridor_width"]), here, route, op2, ov, key, tier)
	avoid_hazards(res, here, route, key, running)
	var pp: Variant = ctx.get("pair_pos")
	if pp is Vector3 and ctx.get("pair_vel") is Vector3:
		var lv := _v2(ctx["pair_vel"])
		pair_steer(res, here, pair_slot(_v2(pp), heading_of(lv, heading_of(route, Vector2(0.0, 1.0))), float(ctx.get("pair_side", 1.0))))
	if ctx.has("edge_width"):
		lane_steer(res, route, float(ctx["edge_width"]), float(ctx.get("edge_lateral", 0.0)), key)
	res.steer = res.steer.limit_length(MAX_STEER)
	return res.velocity(route)


# ---------------------------------------------------------------------------------------------------------------------
# MotionRules bindings (motion_rules.gd rule_s2..rule_s8 delegate here). Each writes its LOCO (and S3 UPPER) fields into the
# rule candidate. Row params override the defaults above. Scratch is shared, so these are not re-entrant.
# ---------------------------------------------------------------------------------------------------------------------

static func _emit(cand: Dictionary, res: Result) -> bool:
	cand["steer_x"] = res.steer.x
	cand["steer_z"] = res.steer.y
	cand["speed_mul"] = res.speed_mul
	cand["stop"] = res.stop
	return true


static func _pf(row: Dictionary, key: String, fallback: float) -> float:
	var p: Variant = row.get("params")
	return float((p as Dictionary).get(key, fallback)) if p is Dictionary else fallback


static func _here_route(ctx: Dictionary, out: PackedVector2Array) -> bool:
	var pv: Variant = ctx.get("position")
	var rv: Variant = ctx.get("velocity")
	if not (pv is Vector3):
		return false
	out[0] = _v2(pv)
	out[1] = _v2(rv) if rv is Vector3 else Vector2.ZERO
	return true


static var _hr := PackedVector2Array([Vector2.ZERO, Vector2.ZERO])


static func rule_s2(ctx: Dictionary, arch: Dictionary, persona: Dictionary, row: Dictionary, cand: Dictionary) -> bool:
	if not (ctx.get("oncoming_pos") is Vector3 and ctx.get("oncoming_vel") is Vector3 and _here_route(ctx, _hr)):
		return false
	if ctx.get("running", _hr[1].length() >= RUN_SPEED):
		return false
	var key := _key(persona)
	_scratch.reset()
	var rank := effective_rank(float(MotionRules.param(arch, persona, "yield_rank", 2.0)), bool(ctx.get("carrying", false)),
		float(ctx.get("age", persona.get("age", 0.0))))
	if not yield_step(_scratch, _hr[0], _hr[1], rank, key, float(MotionRules.param(arch, persona, "rvo_radius_m", DEFAULT_RADIUS)),
			_v2(ctx["oncoming_pos"]), _v2(ctx["oncoming_vel"]), float(ctx.get("oncoming_rank", 2.0)),
			int(ctx.get("oncoming_id", key + 1)), float(ctx.get("oncoming_radius", DEFAULT_RADIUS)),
			_pf(row, "horizon_s", YIELD_HORIZON_S), _pf(row, "slow_mul", YIELD_SLOW_MUL), _pf(row, "step_aside_m", YIELD_STEP_M)):
		return false
	return _emit(cand, _scratch)


static func rule_s3(ctx: Dictionary, _arch: Dictionary, persona: Dictionary, row: Dictionary, cand: Dictionary) -> bool:
	if not (ctx.has("corridor_width") and ctx.get("oncoming_pos") is Vector3 and ctx.get("oncoming_vel") is Vector3 and _here_route(ctx, _hr)):
		return false
	_scratch.reset()
	if not pass_right(_scratch, float(ctx["corridor_width"]), _hr[0], _hr[1], _v2(ctx["oncoming_pos"]), _v2(ctx["oncoming_vel"]),
			_key(persona), int(ctx.get("tier", TIER_NEAR)), _pf(row, "corridor_max_m", PASS_CORRIDOR_MAX_M),
			_pf(row, "oncoming_m", PASS_ONCOMING_M), PASS_TURN_M):
		return false
	_emit(cand, _scratch)
	if _scratch.turn:
		var p: Variant = row.get("params")
		cand["upper_clip"] = String((p as Dictionary).get("upper_clip", PASS_TURN_CLIP)) if p is Dictionary else PASS_TURN_CLIP
	return true


static func rule_s4(ctx: Dictionary, _arch: Dictionary, persona: Dictionary, row: Dictionary, cand: Dictionary) -> bool:
	if not (ctx.get("mover_pos") is Vector3 and ctx.get("mover_vel") is Vector3 and ctx.get("position") is Vector3):
		return false
	_scratch.reset()
	if not mover_stop(_scratch, _v2(ctx["position"]), _v2(ctx["mover_pos"]), _v2(ctx["mover_vel"]), _key(persona),
			_pf(row, "lookahead_s", MOVER_LOOKAHEAD_S), _pf(row, "stop_dist_m", MOVER_STOP_M)):
		return false
	return _emit(cand, _scratch)


static func rule_s5(ctx: Dictionary, _arch: Dictionary, persona: Dictionary, _row: Dictionary, cand: Dictionary) -> bool:
	if not _here_route(ctx, _hr):
		return false
	_scratch.reset()
	if not avoid_hazards(_scratch, _hr[0], _hr[1], _key(persona), bool(ctx.get("running", _hr[1].length() >= RUN_SPEED))):
		return false
	return _emit(cand, _scratch)


static func rule_s8(ctx: Dictionary, _arch: Dictionary, persona: Dictionary, row: Dictionary, cand: Dictionary) -> bool:
	if not (ctx.has("edge_width") and _here_route(ctx, _hr)):
		return false
	_scratch.reset()
	if not lane_steer(_scratch, _hr[1], float(ctx["edge_width"]), float(ctx.get("edge_lateral", 0.0)), _key(persona), 0.35,
			_pf(row, "min_edge_width_m", StreetLanes.LANE_MIN_EDGE_WIDTH)):
		return false
	return _emit(cand, _scratch)
