# P14a — mount_controller.gd: drive the new HorseRig (gaits, speeds, turns, hooves)

Owner: Codex. Standalone modules already in the repo: `scripts/horses/horse_rig.gd` (HorseRig), `horse_springs.gd`,
`rider_sync.gd`, `rider_ik.gd`, `rein_follow.gd`. Nothing calls them yet. Handoff: `docs/anim/horses/HANDOFF.md`.
Apply P14c first (ambient horses become HorseRigs) or create the HorseRig on mount (step 1b).

## 1. Speeds (match the authored clips: hooves stay planted at speed_scale 1.0)

```gdscript
const WALK_SPEED := 1.5          # was 1.7   (clip Walk 1.50 m/s, stride 1.70 m)
const TROT_SPEED := 3.6          # NEW       (clip Trot 3.60 m/s, stride 2.64 m)
const CANTER_SPEED := 5.8        # unchanged (clip Canter_L/R 5.80 m/s)
const GALLOP_SPEED := 11.0       # unchanged (clip Gallop_L/R 11.0 m/s)
const BACK_SPEED := 0.7          # NEW       (clip BackUp, stick pulled back while standing)
const WALK_STICK := 0.35         # was 0.5: <= walk, <= TROT_STICK trot, above canter
const TROT_STICK := 0.72         # NEW
```

In `drive()` replace the target selection:

```gdscript
		target = WALK_SPEED if push <= WALK_STICK else (TROT_SPEED if push <= TROT_STICK else CANTER_SPEED)
		if push > TROT_STICK and (sprint or _full_push > GALLOP_HOLD):
			target = GALLOP_SPEED
```

and let a stick pulled toward the camera while standing back up: `if speed < 0.2 and facing().dot(want) < -0.7: target = -BACK_SPEED`
(`move_toward` already handles the sign; clamp `speed` to `[-BACK_SPEED, GALLOP_SPEED]`).

## 2. Visual sync (replaces `play_gait` + the distance hoof counter)

```gdscript
var _prev_yaw := 0.0
var _hoof_hit := false

func _init(h: Node3D) -> void:
	horse = h
	yaw = h.rotation.y
	_prev_yaw = yaw
	seat = _measure_seat(h)
	var rig := _rig()
	if rig:
		rig.hoof.connect(func(_leg: String, _gait: String) -> void: _hoof_hit = true)

func _rig() -> HorseRig:
	return horse if horse is HorseRig else horse.get_node_or_null("HorseRig") as HorseRig

func sync(at: Vector3, delta: float) -> bool:
	if not is_instance_valid(horse):
		return false
	horse.global_position = at
	horse.rotation.y = yaw
	var rig := _rig()
	if rig:
		var yaw_rate := wrapf(yaw - _prev_yaw, -PI, PI) / maxf(delta, 1e-4)
		rig.drive(speed, yaw_rate, delta)          # gait, lead, leaning turn loop, speed_scale, phase-kept blends
		rig.set_mode("swim" if WorldGen.water_depth(at.x, at.z) > WADE_LIMIT else "")
	_prev_yaw = yaw
	var hit := _hoof_hit                           # real footfalls from the clip sidecar (hoof_FL/FR/HL/HR events)
	_hoof_hit = false
	return hit
```

`HorseRig.drive()` does all gait logic: bands with 0.35 m/s hysteresis (walk < 2.3 < trot < 4.6 < canter < 8.2 < gallop), the
leaning `*_Turn_L/R` loops above 0.35 rad/s of yaw rate (lead flips to the turn side for canter/gallop), `speed_scale =
speed / clip speed` clamped to 0.6–1.45, and when the gait changes it keeps the stride phase so the rhythm continues.

## 3. Swimming instead of refusing deep water (optional)

The Swim clip is authored with the root at the WATER SURFACE. To let the horse swim: drop the "refuse deep water" block, keep
`speed <= 1.1` while `water_depth > WADE_LIMIT`, and position the horse at the surface height (`WorldGen.water_level` or the
depth-corrected ground + depth). `HorseRig.set_mode("swim")` (step 2) picks the clip.

## 4. Remove what the new rig makes obsolete

- `RUN_GAIT_FROM`, `HOOF_SPACING`, `_hoof` and the Critter `ground_speed` lookups.
- `rider_offset()` / `SEAT_HIP` / `BACK_THICKNESS` / `_measure_seat()`: the rider is placed by RiderSync (P14b); keep
  `rider_offset()` only as a fallback for non-HorseRig mounts (donkeys etc. still on Critter).

## 5. Actions the controller can trigger

`rig.play_action("Rear" | "Buck" | "Spook_L" | "Spook_R" | "Hit_L" | "Hit_R" | "Death" | "Jump_Full" | "Walk_Stop" | "Gallop_Stop")`.
While `rig.is_busy()`, keep calling `drive()` (it is ignored) and ignore stick input except steering. `Jump_Full` carries its
arc in the root motion (root Y up to 1.05 m): either apply `rig.root_motion_delta()` to the body or play it purely visually.
Stops: when the stick is released above 7 m/s, play `Gallop_Stop` (2.0 s, 11 → 0 m/s, sits the horse on its hocks) and brake with
its sidecar speed curve instead of `BRAKE`.
