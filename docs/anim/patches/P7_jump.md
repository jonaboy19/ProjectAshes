# P7 - Jump design (the game has no jump; FEEL_AUDIT scorecard: "jump/land do not apply")

Clips exist (`UAL_Loco_Transitions.glb`, see P5 section 0 for the `UAL_FILES` order: this library must come before UAL1 because UAL1 also has `Jump_Start`).
This note is the design Codex wires into `player.gd`; numbers are starting values tuned against the existing constants (`GRAVITY` 24, `COYOTE_TIME` 0.12, `AIR_CONTROL` 0.3, `RUN` 6.5).

## 1. Input on mobile

* **Jump button**: right thumb cluster, directly above the attack button, 88 dp touch target (visual 72 dp), 24 dp gap to attack. Press = jump, hold = full height, release early = short hop.
  Buffered for 0.12 s (a press just before landing jumps on touch-down, a press just after walking off a ledge still jumps: coyote).
* **Contextual vault / jump**: when the stick pushes into an obstacle whose top is 0.4-1.0 m high and 1.0 m away, the same button shows a vault glyph and plays `Vault_Low` / `Vault_Low_B`
  (traversal_authored) instead of a jump. Above 1.0 m it plays the climb clips. Below 0.4 m the character just steps up (existing foot IK), no jump.
* **Alternative**: swipe up on the right half of the screen (only if the button is hidden by the layout option "one-handed"). Never use double-tap on the stick.
* Sprint + jump = running jump. Crouch + jump = no jump (stand up first). Blocking / attacking: jump is ignored, buffered for 0.12 s.
* Haptic: 10 ms tick on take-off, 20 ms on a hard landing, 35 ms + double tick on a roll landing.

## 2. Physics values

| Value | Standing / walk jump | Running jump (>= 4.5 m/s) | Note |
|---|---|---|---|
| Apex height | 1.10 m | 1.25 m | `v0 = sqrt(2 g h)`: 7.27 m/s with g 24 (rise 0.30 s) |
| Gravity up / down | 24 / 32 m/s2 (x1.35 on the way down) | same | snappier fall, apex hangs for ~0.08 s (halve gravity when `abs(vy) < 1.5`) |
| Short hop | release before apex cuts `vy` to 45 % once | same | min height 0.35 m |
| Air time, flat ground | 0.66 s | 0.71 s | rise 0.30 + fall 0.36 |
| Horizontal | keep the take-off speed, air control 0.3 (existing) | keep 100 % of run speed, air control 0.2 | jump distance at RUN 6.5 m/s = 4.6 m |
| Terminal fall speed | 24 m/s | | above it, no more speed-up |
| Coyote time | 0.12 s (existing) | 0.12 s | starts when the floor ray leaves the ground without a jump |
| Jump buffer | 0.12 s | 0.12 s | |
| Stamina | 6 (standing), 10 (running) | | jump needs >= 6, refunds nothing |

## 3. States and clips

| State | Clip | Exit | Notes |
|---|---|---|---|
| `JUMP_START` (standing) | `Jump_Start` (0.333 s, take-off = frame 9 = 0.30 s) | launch at frame 9 | crouch + arm swing. Latency: play it at rate 2.0 (launch after 0.15 s); on a joystick tap the crouch is the anticipation. Blend in 0.05 s |
| `JUMP_START` (running) | `Jump_Running_Start` (0.400 s, take-off = frame 12) | launch immediately at press | start the clip at frame 6 (already in the plant) at rate 1.5 so the launch is at 0.13 s; body speed unchanged |
| `AIR_RISE` | `Jump_Rise` (loop 0.8 s, hover pose, arms forward, legs long) | `vy <= 0.5` | blend 0.08 s |
| `AIR_FALL` | `Jump_Fall` (loop 0.8 s, arms out, knees soft) | ground contact | blend 0.12 s; from a ledge walk-off go straight to it (0.15 s) |
| `LAND_SOFT` | `Jump_Land_Soft` (0.867 s, touch-down frame 4) | 0.25 s, then locomotion | fall height < 1.2 m (impact speed < 7 m/s) or stick held and speed > 3 |
| `LAND_HARD` | `Jump_Land_Hard` (1.367 s, touch-down frame 6) | 0.45 s lock, then idle | 1.2-3.0 m (7-11 m/s). Movement damped to 30 % for 0.35 s, one hand on the ground (knee absorb) |
| `LAND_ROLL` | `Jump_Land_Roll` (1.667 s, touch-down frame 4, roll starts at frame 12) | 0.9 s | fall 3-6 m **or** a fall > 1.2 m with the stick held forward: no damage, keeps 60 % of the horizontal speed along the roll (root travel is only 0.21 m, move the capsule with `ROLL` speed of the dodge) |
| `LAND_RUNNING` | `Jump_Land_Running` (0.767 s, touch-down frame 2) | blends into `Jog_Fwd_Loop` at phase 0.86 | landing while sprinting / running: no speed loss, no lock |
| Fall damage | > 6 m without roll: `(h - 6) * 8` HP, `Hit_Chest` + `LAND_HARD` | | roll always cancels it |

Landing pick: `h = fall height`, `v = impact speed`, `roll = stick_forward and h > 1.2`. `if v < 7: soft; elif roll or h >= 3: roll; else: hard`; running (speed > 4.5): running land unless `h > 3`.

## 4. VFX hooks (ElementFX.play / dust)

Frame numbers are in the sidecar `events` (30 fps, before the play rate):

| Hook | Where | Effect |
|---|---|---|
| Take-off dust | `Jump_Start` frame 9, `Jump_Running_Start` frame 12 | small ring at the feet, radius 0.4 m (0.6 running), 3 short puffs backwards, `vfx_free` "dust" tone (warm ochre) |
| Touch-down dust | `Jump_Land_Soft` frame 4, `Jump_Land_Hard` frame 6, `Jump_Land_Roll` frame 4, `Jump_Land_Running` frame 2 | ring radius `0.35 + 0.05 * v` (max 1.4 m), leaves + grass tuft on grass, splash on water |
| Roll | `Jump_Land_Roll` frame 12 | dust trail along the roll (0.6 s) |
| Skid | `Loco_Sprint_Stop_Skid` frames 11-20 | continuous small dust from the braking foot |
| Footfalls | `events.footstep_frames` of the start / stop / turn clips | footstep sound + tiny puff (existing footsteps addon) |
| Air trail | `AIR_FALL` when `v > 14` | speed lines at the screen edge, 8 % opacity |

## 5. Camera

* Take-off: nothing (do not follow the vertical arc 1:1). Chase camera height follows the character with a lag of 0.25 s and only 60 % of the vertical rise (`Phantom Camera` follow damping y).
* Landing dip: pivot y offset `-0.10 m` (soft), `-0.22 m` (hard), `-0.30 m` (roll), 0.06 s down, 0.25 s ease back. FOV +2 deg for 0.15 s on a hard landing. No shake below 7 m/s impact.
* Fall > 8 m/s: pull the camera back 4 % and pitch up 3 deg so the ground stays visible.
* First-person view: dip only (no roll).

## 6. What to test in the game

1. Stand jump from idle: crouch reads, launch at 0.15 s, apex 1.1 m, soft landing, no foot slide on touch-down.
2. Run jump over a 2 m gap: distance 4.6 m, `Jump_Running_Start` -> `Jump_Rise` -> `Jump_Fall` -> `Jump_Land_Running` without a speed dip.
3. Walk off a 2 m ledge: coyote grace, `Jump_Fall` after 0.15 s, hard landing with the dip.
4. Drop of 5 m with the stick forward: roll, no damage.
5. Jump button spam on the 0.12 s buffer: no double jump, no stuck state.
