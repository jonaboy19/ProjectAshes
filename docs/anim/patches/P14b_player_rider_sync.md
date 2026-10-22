# P14b — player.gd: ride with RiderSync + RiderIK (mount, dismount, mounted combat)

Owner: Codex. Needs P14a. Clips: `assets/generated/horses/UAL_Horse_Rider.glb` (+ `.clips.json`), all named `Horse_Ride_*`.
RiderSync installs them into its own AnimationPlayer/AnimationTree on the rider model and disables the rider's normal
player/tree while attached (character_animator keeps running but has no effect; see step 5).

## 1. State

```gdscript
var _rsync: RiderSync
var _rik: RiderIK
enum Ride { NONE, MOUNTING, RIDING, DISMOUNTING }
var _ride := Ride.NONE
```

## 2. toggle_mount(): mount from the side the player stands on

After `_mount = MountController.new(horse)`:
```gdscript
	var rig := _mount._rig()
	if rig:
		var side := "L" if (global_position - horse.global_position).dot(horse.global_basis.x) > 0.0 else "R"   # +X = horse's left
		_rsync = RiderSync.new(); add_child(_rsync); _rsync.attach(rig, _model)
		_rik = RiderIK.new(); add_child(_rik); _rik.setup(rig, _rsync.skeleton, Quality.tier)
		_rik.feet = 0.0; _rik.hands = Vector2.ZERO
		_ride = Ride.MOUNTING
		var t := _rsync.play_full("Horse_Ride_Mount_" + side)                # 2.2 s, starts standing at the stirrup
		get_tree().create_timer(t).timeout.connect(func():
			if _rsync:
				_rik.feet = 1.0; _rik.hands = Vector2.ONE; _rik.calibrate(); _ride = Ride.RIDING)
```
Block stick input while `_ride == Ride.MOUNTING` (the horse stands). The model position is set by RiderSync every frame, so
**remove** `_model.position = _mount.rider_offset(k)` in `_physics_mounted` when `_rsync` exists (keep the rotation line off too:
RiderSync sets the full transform).

## 3. _dismount(): clip first, then hand the body back

```gdscript
func _dismount() -> void:
	if _rsync and _ride == Ride.RIDING:
		_ride = Ride.DISMOUNTING
		_rik.feet = 0.0; _rik.hands = Vector2.ZERO
		var fast := _mount.speed > 3.0                                   # moving: jump off
		var c := "Horse_Ride_Dismount_Jump" if fast else "Horse_Ride_Dismount_" + ("L" if _dismount_left() else "R")
		get_tree().create_timer(_rsync.play_full(c)).timeout.connect(_finish_dismount)
		return
	_finish_dismount()
```
`_finish_dismount()` = the current body of `_dismount()` plus `_rsync.detach(); _rsync.queue_free(); _rik.queue_free()`.
Use the clip's end point (sidecar `end_ground_point`, horse-root space) as `spot` when it is clear, else `dismount_point()`.

## 4. Riding layers

| input / event | call | notes |
|---|---|---|
| steer hard (|yaw rate| > 0.8 rad/s) at walk/trot | `_rsync.play_upper("Horse_Ride_Rein_Turn_" + ("L" if left else "R"))` | open rein |
| stick released above 3 m/s | `_rsync.play_upper("Horse_Ride_Stop_Pull")` | with P14a's stop |
| gait up-shift / gallop request | `_rsync.play_full("Horse_Ride_Spur")` then back | 0.8 s, legs give the aid |
| light attack while mounted | `_rsync.play_upper("Horse_Ride_Sword_Swing_" + side)`; `_rik.hands = Vector2(1, 0)` | side = where the target is; hit frame 14 (0.47 s) in the sidecar; reins stay in the left hand |
| aim / fire bow | `Horse_Ride_Bow_Draw` → `Horse_Ride_Bow_Aim` (loop) → `Horse_Ride_Bow_Release` | `_rik.hands = Vector2.ZERO` (reins on the neck, ReinFollow drops them); release frame in sidecar |
| idle while stopped 6 s | `_rsync.play_upper("Horse_Ride_Idle_LookAround")` | |
| player hit while mounted | `_rsync.play_upper("Horse_Ride_Hit_React_" + side)` | stays seated |
| player dies / horse bucks the rider off | `_rsync.play_full("Horse_Ride_FallOff")`, then detach and ragdoll/`Death01` at `end_ground_point` | synced to the horse's Buck |
| horse dies | `rig.play_action("Death")` + `_rsync` follows automatically (`Horse_Ride_Death`) | rider rolls clear |

After any upper action set `_rik.hands = Vector2.ONE` again. Everything synced to a horse clip (Rear, Buck, Spook, Jump, Swim,
Graze, Drink, turns, stops) needs NO call: RiderSync picks `Horse_Ride_<horse clip>` at the same phase automatically.

## 5. character_animator.gd

While `is_mounted()` and `_rsync != null`, skip `_animator.update()` and `set_stance("ride")` (the old "Driving"/"Sitting_Idle"
stand-ins); foot IK already turns itself off for the ride stance.

## 6. Camera

See HANDOFF.md "Camera": pivot from the saddle socket (`rig.socket("saddle").origin + UP * 0.75`), distance 5.5 walk → 7.5 gallop,
FOV +6° at gallop, 0.35 s lag in position, look-ahead into turns.
