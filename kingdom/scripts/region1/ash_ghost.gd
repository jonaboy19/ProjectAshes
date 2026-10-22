class_name AshGhost
extends Node3D
## One pooled Ashsight ghost (scene `scenes/region1/ash_ghost.tscn`): a real humanoid (a UAL
## character) drawn as a warm ember-grey translucent silhouette, playing real animation clips,
## with ash flaking off it and an ember halo on the ground. All the look comes from
## `shaders/region1/ash_ghost.gdshader` (+ an optional depth pre-pass), no textures, no lights.
## The robed-blob placeholder in the scene stays as a fallback until `set_model()` swaps a
## character in (the pool does that for you).
##
## Animation (see AshGhostClips): the replay gives the ghost its speed and the nearest recorded
## beat (attack / hit / death / chisel). Locomotion clips are driven by DISTANCE travelled, so
## the feet never slide at any replay speed, in slow motion, or while scrubbing. Act clips are
## aligned so their hit frame lands on the recorded instant. `lod` thins out animation updates.
##
## Cost: `apply()` is a transform, a few shader parameters and one AnimationPlayer.advance().

const ROLE_STYLE := {
	"bandit": {"ash": Color(0.90, 0.80, 0.70), "core": Color(0.26, 0.21, 0.20), "ember": Color(1.0, 0.44, 0.14), "crack": 1.2},
	"villager": {"ash": Color(0.98, 0.94, 0.86), "core": Color(0.40, 0.38, 0.40), "ember": Color(1.0, 0.76, 0.38), "crack": 0.85},
}
const DEFAULT_STYLE := {"ash": Color(0.90, 0.85, 0.78), "core": Color(0.55, 0.50, 0.48), "ember": Color(1.0, 0.60, 0.26), "crack": 1.0}
const DEPTH_SHADER := preload("res://shaders/region1/ash_ghost_depth.gdshader")
const RATIO := [0.3, 0.6, 1.0]

## Visual detail: 0 LOW (single pass, cheap noise, few particles), 1 MEDIUM, 2 HIGH (+depth pre-pass).
var detail := 2
var role := ""
var active := false
## Scratch value for the owner (the replay view stamps the frame it last saw this ghost).
var stamp := 0
## Animation LOD: 0 every frame, 1 every 2nd, 2 every 4th, 3 every 8th.
var lod := 0

var _mat: ShaderMaterial
var _depth_mat: ShaderMaterial
var _alpha := -1.0
var _dissolve := -1.0
var _ash: GPUParticles3D
var _steps: GPUParticles3D
var _sparks: GPUParticles3D
var _model: Node3D
var _halo_mat: ShaderMaterial
var _beacon: MeshInstance3D
var _beacon_mat: ShaderMaterial
var _ap: AnimationPlayer
var _prev_pos := Vector3.ZERO
var _prev_valid := false
var _clip := ""
var _clip_kind := 0        # 1 loop (locomotion), 2 act
var _lod_frame := 0
var _acc_dt := 0.0
var _acc_moved := 0.0
var _last_act_dt := 0.0
var _last_act := &""
var _height := 1.8
var _variant := 0
var _variant_id: Variant = null
var _fresh := true
var _gait := 0
var _has: Dictionary = {}   # clip name -> bool (AnimationPlayer.has_animation, cached)
## Profiling counters (microseconds, summed over all ghosts; only counted while `profile` is on: the
## sandbox bench switches it on, the game never pays for the timers).
static var profile := false
static var prof_anim_us := 0
static var prof_look_us := 0
static var prof_part_us := 0
static var prof_adv_us := 0
static var prof_adv_n := 0


func _ready() -> void:
	_ash = get_node_or_null("Ash")
	_steps = get_node_or_null("Steps")
	_sparks = get_node_or_null("Sparks")
	_model = get_node_or_null("Model")
	_beacon = get_node_or_null("Beacon")
	var halo := get_node_or_null("Halo") as MeshInstance3D
	if halo != null and halo.material_override is ShaderMaterial:
		_halo_mat = (halo.material_override as ShaderMaterial).duplicate()
		halo.material_override = _halo_mat
	if _beacon != null and _beacon.material_override is ShaderMaterial:
		_beacon_mat = (_beacon.material_override as ShaderMaterial).duplicate()
		_beacon.material_override = _beacon_mat
	# every ghost gets its own materials so roles and fades do not leak between pooled ghosts
	var first := _first_mesh(self)
	if first != null and first.material_override is ShaderMaterial:
		_mat = (first.material_override as ShaderMaterial).duplicate()
		var sd := float(get_instance_id() % 97) / 97.0
		_mat.set_shader_parameter(&"seed", sd)
		_depth_mat = ShaderMaterial.new()
		_depth_mat.shader = DEPTH_SHADER
		_depth_mat.set_shader_parameter(&"seed", sd)
		_apply_material(_model)
	for p: GPUParticles3D in [_ash, _steps, _sparks]:
		if p != null and p.process_material != null:
			p.process_material = p.process_material.duplicate()
	deactivate()


func _first_mesh(n: Node) -> MeshInstance3D:
	for c in n.find_children("*", "MeshInstance3D", true, false):
		return c
	return null


func _apply_material(root: Node) -> void:
	if root == null or _mat == null:
		return
	var m: Material = _mat
	if detail >= 2 and _depth_mat != null:
		_depth_mat.next_pass = _mat
		m = _depth_mat
	elif _depth_mat != null:
		_depth_mat.next_pass = null
	_mat.set_shader_parameter(&"cheap", 1.0 if detail <= 0 else 0.0)
	# LOW has no grade pass and one crack octave: lift the rim and the body a little so the figure still reads
	_mat.set_shader_parameter(&"rim_strength", 2.7 if detail <= 0 else 2.1)
	_mat.set_shader_parameter(&"base_opacity", 0.82 if detail <= 0 else 0.74)
	for c in root.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED


## Set the visual detail tier (0 LOW, 1 MEDIUM, 2 HIGH). Safe to call any time.
func set_detail(d: int) -> void:
	detail = clampi(d, 0, 2)
	_apply_material(_model)
	if _ash != null:
		_ash.amount_ratio = RATIO[detail]
	if _steps != null:
		_steps.amount_ratio = 0.5 if detail == 0 else 1.0


## Swap the placeholder body for a character (a Node3D with a Skeleton3D, MeshInstance3D
## descendants and, when it should move, an AnimationPlayer). Feet at y = 0. The model is
## turned to face the ghost's -Z (glTF models look down +Z).
func set_model(model: Node3D, height: float = 1.8) -> void:
	if _model == null:
		return
	for c in _model.get_children():
		c.queue_free()
	model.rotation.y = PI
	_model.add_child(model)
	_height = height
	_apply_material(_model)
	for shader_mat: ShaderMaterial in [_mat, _depth_mat]:
		if shader_mat != null:
			shader_mat.set_shader_parameter(&"model_height", height)
	var found := model.find_children("*", "AnimationPlayer", true, false)
	_ap = found[0] if not found.is_empty() else null
	if _ap != null:
		_ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		AshGhostClips.ensure_library(_ap)
	_clip = ""
	_clip_kind = 0
	if _beacon != null:
		_beacon.scale = Vector3(1, height / 1.8, 1)


func has_character() -> bool:
	return _ap != null


## Play every clip once for zero time so the AnimationPlayer builds its track caches now, not on
## the first blow of the first replay (a multi-millisecond hitch per clip otherwise).
func prewarm_clips() -> void:
	if _ap == null:
		return
	for clip in AshGhostClips.all_clips():
		if _ap.has_animation(clip):
			_ap.play(clip)
			_ap.advance(0.0)
	_ap.stop()
	_clip = ""


func set_role(r: String) -> void:
	role = r
	var st: Dictionary = ROLE_STYLE.get(r, DEFAULT_STYLE)
	if _mat != null:
		_mat.set_shader_parameter(&"ash_color", st["ash"])
		_mat.set_shader_parameter(&"core_color", st["core"])
		_mat.set_shader_parameter(&"ember_color", st["ember"])
		_mat.set_shader_parameter(&"crack_amount", float(st["crack"]))
	if _halo_mat:
		_halo_mat.set_shader_parameter(&"ember_color", st["ember"])
	if _beacon_mat:
		_beacon_mat.set_shader_parameter(&"ember_color", st["ember"])
	if _ash != null and _ash.process_material is ParticleProcessMaterial:
		(_ash.process_material as ParticleProcessMaterial).color = (st["ash"] as Color).lerp(Color.WHITE, 0.25)
	if _steps != null and _steps.process_material is ParticleProcessMaterial:
		(_steps.process_material as ParticleProcessMaterial).color = (st["ember"] as Color).lerp(Color.WHITE, 0.15)
	if _sparks != null and _sparks.process_material is ParticleProcessMaterial:
		(_sparks.process_material as ParticleProcessMaterial).color = (st["ember"] as Color).lerp(Color.WHITE, 0.3)


func activate(r: String = "") -> void:
	active = true
	visible = true
	set_role(r)
	_alpha = -1.0
	_dissolve = -1.0
	_prev_valid = false
	_clip = ""
	_clip_kind = 0
	_last_act = &""
	_last_act_dt = 0.0
	_acc_dt = 0.0
	_acc_moved = 0.0
	_fresh = true
	if _ash:
		_ash.emitting = true
		_ash.restart()
	if _steps:
		_steps.emitting = true
		_steps.restart()


func stop_particles() -> void:
	for p: GPUParticles3D in [_ash, _steps, _sparks]:
		if p != null:
			p.emitting = false


func deactivate() -> void:
	active = false
	visible = false
	if _ash:
		_ash.emitting = false
	if _steps:
		_steps.emitting = false
	if _sparks:
		_sparks.emitting = false
	_clip = ""


## The one per-frame call. `e` is an AshMemory.positions_at() entry (heading, alpha, ash,
## speed, act, act_dt); `world` is where to stand; `dt` is the wall-clock frame time and
## `replay_speed` the cursor's speed (0 while paused), so slow motion slows the clips too.
func apply(e: Dictionary, world: Vector3, dt: float, replay_speed: float) -> void:
	if _variant_id == null or _variant_id != e.get("id"):
		_variant_id = e.get("id")
		_variant = String(_variant_id).hash() if _variant_id != null else 0
	transform = Transform3D(Basis(Vector3.UP, float(e["heading"])), world)   # one transform update, not two
	var ash := float(e.get("ash", 0.0))
	var alpha := float(e["alpha"])
	# forming (arrival) and crumbling (end) both run through the dissolve parameter
	var dis := _smooth(ash) if ash > 0.001 else 1.0 - _smooth(alpha)
	var vis := clampf((1.0 - ash) * 6.0, 0.0, 1.0) * (1.0 if ash > 0.001 else clampf(alpha * 5.0, 0.0, 1.0))
	var t0 := Time.get_ticks_usec() if profile else 0
	_push_look(world, vis, dis)
	if profile:
		prof_look_us += Time.get_ticks_usec() - t0
	var moved := 0.0
	if _prev_valid:
		moved = Vector2(world.x - _prev_pos.x, world.z - _prev_pos.z).length()
		if moved > 4.0:   # a scrub jump, not a step
			moved = 0.0
	_prev_pos = world
	_prev_valid = true
	if _ap != null:
		if profile:
			t0 = Time.get_ticks_usec()
		_animate(dt * replay_speed, moved, float(e.get("speed", 0.0)), StringName(e.get("act", &"")), float(e.get("act_dt", 0.0)))
		if profile:
			prof_anim_us += Time.get_ticks_usec() - t0
	# particles: a heavier shower while the figure is crumbling or forming
	if profile:
		t0 = Time.get_ticks_usec()
	if _ash != null:
		var base := float(RATIO[detail])
		var ratio := clampf(base * (0.35 + 0.65 * clampf(dis * 3.0, 0.0, 1.0)), 0.05, 1.0)
		if absf(ratio - _ash.amount_ratio) > 0.02:
			_ash.amount_ratio = ratio
	if _steps != null:
		var want_steps := float(e.get("speed", 0.0)) > 0.6 and ash < 0.5
		if want_steps != _steps.emitting:
			_steps.emitting = want_steps
	if profile:
		prof_part_us += Time.get_ticks_usec() - t0


static func _smooth(x: float) -> float:
	var c := clampf(x, 0.0, 1.0)
	return c * c * (3.0 - 2.0 * c)


func _push_look(_world: Vector3, vis: float, dis: float) -> void:
	if _mat == null:
		return
	if absf(vis - _alpha) > 0.01 or absf(dis - _dissolve) > 0.004:
		_alpha = vis
		_dissolve = dis
		for m: ShaderMaterial in [_mat, _depth_mat]:
			if m != null:
				m.set_shader_parameter(&"alpha", vis)
				m.set_shader_parameter(&"dissolve", dis)
		if _halo_mat:
			_halo_mat.set_shader_parameter(&"alpha", vis * (1.0 - dis * 0.7))
		if _beacon_mat:
			_beacon_mat.set_shader_parameter(&"alpha", vis * (1.0 - dis))


# --- animation ---------------------------------------------------------------------------

func _animate(dt_in: float, moved_in: float, speed: float, act: StringName, act_dt: float) -> void:
	# LOD: far ghosts only pick a clip and step the pose every 2nd / 4th / 8th frame; the skipped
	# time and distance are handed over, so the motion stays exact (just sampled less often)
	_acc_dt += dt_in
	_acc_moved += moved_in
	_lod_frame += 1
	if lod > 0 and _clip != "" and _lod_frame % (1 << clampi(lod, 0, 3)) != 0:
		return
	var dt_play := _acc_dt
	var moved := _acc_moved
	_acc_dt = 0.0
	_acc_moved = 0.0
	var want := ""
	var want_kind := 1
	var seek_to := 0.0
	var ref := 0.0
	var spec: Dictionary = AshGhostClips.act_clip(role, act, _variant) if act != &"" else {}
	if not spec.is_empty():
		var pos: float = act_dt + float(spec["hit"])
		var length: float = float(spec["len"])
		var span := float(spec.get("span", 0.0))
		if span > 0.0:
			if pos >= 0.0 and act_dt <= span:   # a work clip that repeats for `span` seconds
				want = String(spec["clip"])
				want_kind = 2
				seek_to = minf(fposmod(pos, length), length - 0.03)
		elif pos >= 0.0 and (pos <= length or bool(spec.get("hold", false))):
			want = String(spec["clip"])
			want_kind = 2
			seek_to = minf(pos, length - 0.03)
	if want == "":
		_gait = AshGhostClips.next_gait(_gait, speed)
		want = AshGhostClips.GAIT_CLIP[_gait]
		ref = AshGhostClips.GAIT_REF[_gait]
	var ok = _has.get(want)
	if ok == null:
		ok = _ap.has_animation(want)
		_has[want] = ok
	if not ok:
		return
	var switched := want != _clip
	if switched:
		_clip = want
		_clip_kind = want_kind
		_ap.play(want, 0.0 if _fresh else (0.18 if want_kind == 1 else 0.10))
		_fresh = false
		if want_kind == 2:
			_ap.seek(seek_to, false)
	# advance the pose
	var step := dt_play
	if _clip_kind == 1 and ref > 0.0:
		step = moved / ref   # one cycle per stride travelled: feet follow the ground
	if not switched and step <= 0.0 and _clip_kind == 1:
		pass   # paused or standing still: the pose does not change
	else:
		var ta := Time.get_ticks_usec() if profile else 0
		if _clip_kind == 2:
			# stay locked to the recorded instant (scrubbing, slow motion, pause)
			if absf(_ap.current_animation_position - seek_to) > 0.12:
				_ap.seek(seek_to, true)
			else:
				_ap.advance(step)
		else:
			_ap.advance(step)
		if profile:
			prof_adv_us += Time.get_ticks_usec() - ta
			prof_adv_n += 1
	# ember burst on the instant of a blow or a hit
	if _sparks != null and (act == &"attack" or act == &"hit") and dt_play > 0.0:
		if _last_act == act and _last_act_dt < 0.0 and act_dt >= 0.0 and act_dt < 0.35:
			_sparks.restart()
			_sparks.emitting = true
	_last_act = act
	_last_act_dt = act_dt


func material() -> ShaderMaterial:
	return _mat


func height() -> float:
	return _height


## Compatibility: the old placement call (no animation). `fade` 0..1.
func place(pos: Vector3, heading: float, fade: float) -> void:
	apply({"heading": heading, "alpha": fade, "ash": 0.0, "speed": 0.0}, pos, 0.0, 0.0)
