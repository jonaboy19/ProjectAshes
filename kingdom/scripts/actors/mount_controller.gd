extends RefCounted
## Horse riding. The player owns one of these while mounted (player.gd
## `_mount`). The player's CharacterBody3D still does the physics (walls,
## slopes, other bodies), driven by the velocity this controller asks for; the
## horse Critter is claimed (stops wandering) and becomes the visual, placed
## under the rider every tick.
##
## Gaits: stick past half pushes a canter, half or less walks, and a gallop
## builds from a canter when the sprint key is held or the stick stays fully
## pushed for GALLOP_HOLD seconds (phones have no sprint button). The horse only
## moves along its own facing: it turns toward the stick at a rate that drops
## with speed, and slows while the stick points well off its nose, so it arcs
## instead of strafing. Playback rate follows ground speed through the clips'
## measured stride (Critter.ANIM_GROUND_SPEEDS).
##
## Ambient horses belong to AmbientLife, which frees whole groups when the
## player rides away. `take()` therefore swaps the ambient horse for an
## identical rider-owned Critter that nothing else frees; once released it
## despawns on its own when the player is far away (critter.gd).

const WALK_SPEED := 1.7
const CANTER_SPEED := 5.8
const GALLOP_SPEED := 11.0
const ACCEL := 4.5               # m/s² up to a canter
const GALLOP_ACCEL := 2.6        # m/s² from canter to gallop: a gallop has to build
const BRAKE := 6.5               # m/s² reins pulled / stick released
const TURN_STAND := 1.9          # rad/s turning on the spot
const TURN_WALK := 2.3
const TURN_GALLOP := 1.05
const GALLOP_HOLD := 0.8         # s of full stick before a canter opens into a gallop
## Stick magnitude at and below which the horse walks.
const WALK_STICK := 0.5
## Deepest water the horse wades into (m).
const WADE_LIMIT := 1.15
## Pelvis height of the seated rider clip above its own soles (m, full-size body).
const SEAT_HIP := 0.5
## Distance from the horse's spine to the saddle's top surface (m).
const BACK_THICKNESS := 0.13
const RUN_GAIT_FROM := 3.2       # m/s where the Walk clip hands over to Run
const HOOF_SPACING := 1.5        # m between hoof sounds at a walk (scaled up at speed)

var horse: Node3D
var yaw := 0.0
var speed := 0.0
## Saddle in the horse's local space: height of the seat surface and its offset along the spine.
var seat := Vector3(0.0, 1.45, -0.2)
## Cleared by the rider when the horse has galloped too long (travel_rules.gd GALLOP_FREE_S): it canters until it recovers.
var gallop_allowed := true
var _full_push := 0.0
var _hoof := 0.0


func _init(h: Node3D) -> void:
	horse = h
	yaw = h.rotation.y
	seat = _measure_seat(h)


## Swaps an ambient horse for a rider-owned copy (see the class doc) and claims it.
static func take(c: Node3D, parent: Node) -> Node3D:
	if c.get("rider_owned"):
		c.call("claim")
		return c
	var fresh: Node3D = (c.get_script() as GDScript).new()
	fresh.set("kind", c.get("kind"))
	fresh.set("home", Vector2(c.global_position.x, c.global_position.z))
	fresh.set("rider_owned", true)
	parent.add_child(fresh)
	fresh.global_position = c.global_position
	fresh.rotation.y = c.rotation.y
	fresh.call("claim")
	c.queue_free()
	return fresh


## Seat from the horse's spine bones (Quaternius rigs: Torso2 sits mid-back);
## falls back to the model's bounds.
func _measure_seat(h: Node3D) -> Vector3:
	var skeletons := h.find_children("*", "Skeleton3D", true, false)
	if not skeletons.is_empty():
		var sk := skeletons[0] as Skeleton3D
		var bone := sk.find_bone("Torso2")
		if bone < 0:
			bone = sk.find_bone("Torso")
		if bone >= 0:
			var xf := Transform3D.IDENTITY
			var cur: Node = sk
			while cur != null and cur != h:
				if cur is Node3D:
					xf = (cur as Node3D).transform * xf
				cur = cur.get_parent()
			var p := xf * sk.get_bone_global_rest(bone).origin
			return Vector3(0.0, p.y + BACK_THICKNESS, p.z)
	var box := Assets.visual_aabb(h)
	return Vector3(0.0, box.size.y * 0.62, 0.0)


func facing() -> Vector3:
	return Vector3(sin(yaw), 0.0, cos(yaw))


## One tick of riding. `input` is the camera-relative stick (length 0–1);
## returns the planar velocity the rider's body should move with.
func drive(delta: float, input: Vector3, sprint: bool, at: Vector3) -> Vector3:
	var push := minf(input.length(), 1.0)
	var target := 0.0
	if push > 0.08:
		var want := input / maxf(push, 0.001)
		var t := clampf(speed / GALLOP_SPEED, 0.0, 1.0)
		var rate := TURN_STAND if speed < 0.5 else lerpf(TURN_WALK, TURN_GALLOP, t)
		var angle := facing().signed_angle_to(want, Vector3.UP)
		yaw += clampf(angle, -rate * delta, rate * delta)
		_full_push = _full_push + delta if push > 0.92 else 0.0
		target = WALK_SPEED if push <= WALK_STICK else CANTER_SPEED
		if target == CANTER_SPEED and gallop_allowed and (sprint or _full_push > GALLOP_HOLD):
			target = GALLOP_SPEED
		# Stick well off the nose: collect and turn instead of charging on.
		var align := facing().dot(want)
		target *= clampf((align + 0.35) / 1.35, 0.12, 1.0)
	else:
		_full_push = 0.0
	# Refuse deep water a body length ahead.
	if target > 0.0:
		var ahead := at + facing() * (1.6 + speed * 0.25)
		if WorldGen.water_depth(ahead.x, ahead.z) > WADE_LIMIT:
			target = 0.0
	if target > speed:
		speed = move_toward(speed, target, (ACCEL if speed < CANTER_SPEED else GALLOP_ACCEL) * delta)
	else:
		speed = move_toward(speed, target, BRAKE * delta)
	return facing() * speed


## Walls: keep the gait honest when the body is stopped by something.
func blocked(real_speed: float) -> void:
	speed = minf(speed, real_speed + 0.4)


## Places the horse under the rider and matches its clip to the ground speed.
## Returns true on a hoof beat (for step sounds).
func sync(at: Vector3, delta: float) -> bool:
	if not is_instance_valid(horse):
		return false
	horse.global_position = at
	horse.rotation.y = yaw
	var gait := "Idle"
	var rate := 1.0
	if speed > 0.15:
		gait = "Walk" if speed < RUN_GAIT_FROM else "Run"
		var authored: float = horse.call("ground_speed", gait)
		if authored > 0.0:
			rate = clampf(speed / authored, 0.5 if gait == "Walk" else 0.6, 2.2 if gait == "Walk" else 2.0)
	horse.call("play_gait", gait, rate)
	_hoof += speed * delta
	var spacing := HOOF_SPACING * (1.0 if gait != "Run" else 1.6)
	if speed > 0.3 and _hoof > spacing:
		_hoof = 0.0
		return true
	return false


## Rider model offset from the body origin (which stays on the ground under the horse).
func rider_offset(body_scale: float) -> Vector3:
	return Basis(Vector3.UP, yaw) * Vector3(0.0, seat.y - SEAT_HIP * body_scale, seat.z)


## A clear spot beside the horse: left side first, then right, then behind.
func dismount_point(space: PhysicsDirectSpaceState3D, at: Vector3, exclude: Array[RID]) -> Vector3:
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	for offset: Vector3 in [-right * 1.25, right * 1.25, -facing() * 1.9]:
		var p := at + offset
		p.y = WorldGen.height(p.x, p.z)
		if WorldGen.water_depth(p.x, p.z) > 1.0:
			continue
		var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP, p + Vector3.UP, 1)
		q.exclude = exclude
		if space.intersect_ray(q).is_empty():
			return p + Vector3.UP * 0.05
	return at + Vector3.UP * 0.05


## Hands the horse back to its own wandering where it stands.
func release() -> void:
	if is_instance_valid(horse):
		horse.call("release")
	horse = null
