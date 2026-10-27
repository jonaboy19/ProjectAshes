extends RefCounted
## Root-motion attacks with motion warping (full-motion combat, item 1).
##
## Clip travel lives in the disabled `root` position track (mixamo_to_ual.py --root-motion keep; Assets._ual_for turns the
## track off so the skeleton plays in place). This reads that track as DATA (Animation.position_track_interpolate, the
## same built-in CharacterAnimator.pivot_position uses) and turns it into capsule velocity, so a swing steps, lunges and
## plants where the clip's feet do instead of standing still. Built-in AnimationMixer.root_motion_track is not used:
## the mixer is shared with locomotion (which must stay in place) and the CharacterBody3D needs a velocity anyway.
##
## Warping (closed loop, every physics frame, until the contact frame):
##   * translation: the clip's remaining forward travel up to the hit frame is scaled so the body ends `standoff` metres
##     from the target (scale clamped [MIN_SCALE, MAX_SCALE]); an in-place clip gets an added step of at most MAX_ADD m.
##   * rotation: the body turns toward the target at most MAX_TURN rad/s (so it reads as a step-and-turn, not a snap).
##   * never closer than MIN_GAP to the target (no clipping into the victim), never past the contact frame.
## After the contact frame the clip's own travel plays 1:1 (follow-through, recovery steps).
##
## Pure logic: no scene access except the Animation passed in, so the warp maths runs headless (tests/test_combat_motion.gd).

const FPS := 30.0
const MIN_SCALE := 0.15
const MAX_SCALE := 1.6            ## beyond this the planted feet visibly skate
const MAX_ADD := 1.0            ## m an in-place clip may be pulled toward the target
const MAX_ADD_SPEED := 5.5      ## m/s cap of that added step
const MAX_TURN := 9.0           ## rad/s turn toward the target during the warp window
const MIN_GAP := 0.95           ## m between centres: never warp closer (bodies must not interpenetrate)
const MAX_WARP_RANGE := 6.0     ## m: further targets are not chased (the clip plays 1:1)
const FWD := Vector3(0, 0, 1)   ## UAL model forward (+Z, player.gd faces with atan2(x, z))

static var enabled := true     ## A/B switch for before/after recordings (--classic-combat)
static var _profiles := {}      ## Animation -> PackedVector3Array root offset per 1/30 s (model space, unscaled)

var active := false
var t := 0.0                    ## clip seconds (rate applied)
var rate := 1.0
var hit_t := 0.0                ## clip seconds of the contact frame
var standoff := 1.2
var body_scale := 1.0
var scale_used := 1.0           ## debug / telemetry
var warped_m := 0.0             ## total forward metres moved by this action
var _prof := PackedVector3Array()
var _added := 0.0


## Root offset per frame of `anim` (relative to frame 0), cached. Empty when the clip has no root position track.
static func profile(anim: Animation) -> PackedVector3Array:
	if anim == null:
		return PackedVector3Array()
	if _profiles.has(anim):
		return _profiles[anim]
	var out := PackedVector3Array()
	var tr := -1
	for i in anim.get_track_count():
		if anim.track_get_type(i) == Animation.TYPE_POSITION_3D and String(anim.track_get_path(i)).ends_with(":root"):
			tr = i
			break
	if tr >= 0:
		var p0 := anim.position_track_interpolate(tr, 0.0)
		var n := ceili(anim.length * FPS)
		for f in n + 1:
			var p := anim.position_track_interpolate(tr, minf(f / FPS, anim.length)) - p0
			out.append(Vector3(p.x, 0.0, p.z))
	_profiles[anim] = out
	return out


## The Animation a CharacterAnimator would play for `clip` (aliases resolved), only when it carries real root travel
## (> 5 cm), else null so callers keep their old lunge.
static func anim_of(animator: Object, clip: String) -> Animation:
	if animator == null or not enabled:
		return null
	var ap := animator.get("player") as AnimationPlayer
	if ap == null:
		return null
	var name := String(animator.call("_clip", clip)) if animator.has_method("_clip") else clip
	if not ap.has_animation(name):
		return null
	var a := ap.get_animation(name)
	var p := profile(a)
	if p.size() < 2:
		return null
	var most := 0.0
	for v in p:
		most = maxf(most, v.length())
	return a if most > 0.05 else null


static func sample(prof: PackedVector3Array, at: float) -> Vector3:
	if prof.is_empty():
		return Vector3.ZERO
	var x := clampf(at * FPS, 0.0, prof.size() - 1.0)
	var i := floori(x)
	return prof[i].lerp(prof[mini(i + 1, prof.size() - 1)], x - i)


## Forward metres the clip travels between clip times a and b.
static func forward_between(prof: PackedVector3Array, a: float, b: float) -> float:
	return (sample(prof, b) - sample(prof, a)).dot(FWD)


## Travel scale so `remaining` clip metres cover `need` metres. In-place clips (remaining ~0) report 1.0
## (the added step handles them).
static func warp_scale(remaining: float, need: float) -> float:
	if remaining < 0.05:
		return 1.0
	return clampf(need / remaining, MIN_SCALE, MAX_SCALE)


## Rate-limited yaw step toward `want`.
static func turn_step(yaw: float, want: float, dt: float, max_rate := MAX_TURN) -> float:
	var d := angle_difference(yaw, want)
	return yaw + clampf(d, -max_rate * dt, max_rate * dt)


## Start an action. `anim` may be null (no root track: the added step still pulls toward the target).
func begin(anim: Animation, play_rate: float, contact_t: float, body_s: float, stand := 1.2) -> void:
	_prof = profile(anim)
	rate = maxf(play_rate, 0.05)
	hit_t = maxf(contact_t, 0.0)
	body_scale = maxf(body_s, 0.05)
	standoff = stand
	t = 0.0
	_added = 0.0
	warped_m = 0.0
	scale_used = 1.0
	active = true


func stop() -> void:
	active = false


## Advance `dt` real seconds. `yaw` = the body's current facing, `to_target` = flat vector to the target (ZERO = none).
## Returns {"vel": world velocity (m/s, horizontal), "yaw": new facing}.
func step(dt: float, yaw: float, to_target: Vector3) -> Dictionary:
	if not active or dt <= 0.0:
		return {"vel": Vector3.ZERO, "yaw": yaw}
	var t0 := t
	t += dt * rate
	var length := (_prof.size() - 1) / FPS if _prof.size() > 1 else hit_t
	var flat := Vector3(to_target.x, 0.0, to_target.z)
	var dist := flat.length()
	var has_target := dist > 0.01 and dist < MAX_WARP_RANGE
	var new_yaw := yaw
	var warping := t0 < hit_t
	if has_target and warping:
		new_yaw = turn_step(yaw, atan2(flat.x, flat.z), dt)
	var basis := Basis(Vector3.UP, new_yaw)
	var clip_d := (sample(_prof, minf(t, length)) - sample(_prof, t0)) * body_scale
	var fwd_d := clip_d.dot(FWD)
	var side_d := clip_d - FWD * fwd_d
	var s := 1.0
	var extra := 0.0
	if has_target and warping:
		var need := dist - standoff
		var remaining := forward_between(_prof, t0, hit_t) * body_scale
		if remaining >= 0.05:
			s = warp_scale(remaining, need)
		elif need > 0.0 and _added < MAX_ADD:
			# in-place clip: a smooth added step that arrives by the contact frame
			var left := maxf((hit_t - t0) / rate, dt)
			extra = minf(minf(need, MAX_ADD - _added) / left, MAX_ADD_SPEED) * dt
			_added += extra
	var move_fwd := fwd_d * s + extra
	if has_target and move_fwd > 0.0:
		move_fwd = minf(move_fwd, maxf(dist - MIN_GAP, 0.0))      # never into the victim
	scale_used = s
	warped_m += move_fwd
	if t >= length and t >= hit_t:
		active = false
	var local := FWD * move_fwd + side_d
	return {"vel": (basis * local) / dt, "yaw": new_yaw}
