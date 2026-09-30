class_name CrowdAnimLOD
extends Node
## Animation level of detail for embodied (skeletal) villagers, per distance and quality tier.
##
##   NEAR  (< near_dist, nearest `near_max`): AnimationPlayer every frame, LookAtModifier3D on, shadows on.
##   MID   (< mid_dist): the AnimationPlayer is processed on 1 frame in `step` (2/3/4 by distance, 8 off screen)
##         with its speed multiplied by `step`, so the clip PHASE keeps real time; the skeleton and skin only
##         update on those frames; look-at off; shadows off beyond shadow_dist. Steps are bucketed by id so the
##         same number of rigs update every frame (no spikes).
##         Mechanism (measured, tools_qa/living_world/anim_cost_probe.gd, Godot 4.6.3): the player stays in IDLE
##         callback mode and is switched on/off with Node.process_mode. AnimationPlayer.advance() in MANUAL mode
##         costs ~320 us per call on the villager rig vs ~24 us for the engine's own processing (13x), so manual
##         stepping at 1/3 rate is ~4x MORE expensive than full rate. Toggling `active` or callback_mode_process
##         never processes at all (the change lands after the frame's process list is built).
##   FAR   (< far_dist): the skeletal model is hidden and not animated at all; the person is drawn by VatCrowd
##         (vertex animation texture) with the SAME clip at the SAME clip time (seamless hand-off both ways).
##   OUT   (>= far_dist): nothing drawn here; population_lod's sprites / impostors take over.
## Hysteresis (`margin` m) stops chatter at every boundary. Re-tiering runs on 1/6 of the agents per frame.
##
##   var lod := CrowdAnimLOD.new(); add_child(lod); lod.vat = crowd; lod.camera = cam
##   lod.register(id, body_node, model_root, anim_player, look_at_modifier_or_null, "villager_man_a")
##   lod.unregister(id)
## Contract with the body's controller (villager.gd, see docs/anim/patches/P13_*): while registered, the body
## may call anim.play()/seek() and set speed_scale freely (CrowdAnimLOD multiplies it on step frames and restores
## it after) but must NOT touch process_mode / callback_mode_process / advance() of the player, nor the model's
## visibility.

enum Tier { NEAR, MID, FAR, OUT }

## Per quality tier (Quality.tier: 0 LOW, 1 MEDIUM, 2 HIGH, 3 ULTRA).
const BUDGETS := [
	{"near_max": 3, "near_dist": 10.0, "mid_dist": 26.0, "far_dist": 110.0, "shadow_dist": 10.0, "steps": [3, 4, 5]},
	{"near_max": 5, "near_dist": 12.0, "mid_dist": 32.0, "far_dist": 130.0, "shadow_dist": 14.0, "steps": [2, 3, 4]},
	{"near_max": 8, "near_dist": 14.0, "mid_dist": 40.0, "far_dist": 150.0, "shadow_dist": 18.0, "steps": [2, 3, 4]},
	{"near_max": 12, "near_dist": 18.0, "mid_dist": 50.0, "far_dist": 180.0, "shadow_dist": 24.0, "steps": [1, 2, 3]},
]
const OFFSCREEN_STEP := 8
const RETIER_SLICES := 6

var vat: VatCrowd
var camera: Camera3D
var tier_index := 2
var margin := 2.5
var enabled := true
## Stats (read by the demo overlay / bench).
var counts := [0, 0, 0, 0]
var skeleton_updates := 0           # players processed this frame (NEAR + stepped MID + FAR bookkeeping)
var cpu_usec := 0                   # this node's own GDScript time this frame (the animation work runs in the engine)
var advance_usec := 0               # of which: the step / pulse loop
var retier_usec := 0                # of which: distance / frustum / budget pass
var cfg: Dictionary = BUDGETS[2]
## QA / bench: >= 0 puts every agent in that tier regardless of distance and budget.
var force_tier := -1

var _agents: Array = []             # Array[Agent]
var _by_id: Dictionary = {}
var _frame := 0
var _slice := 0


class Agent:
	var id := 0
	var node: Node3D                 # the moving body (position source)
	var model: Node3D                # the visual root (hidden in FAR)
	var anchor: Node3D               # the node whose transform the VAT mesh is baked in (model's imported scene root)
	var anim: AnimationPlayer
	var skeleton: Skeleton3D
	var look: SkeletonModifier3D
	var meshes: Array = []
	var vat_look := ""
	var tier := -1
	var step := 1
	var bucket := 0
	var slot60 := 0
	var onscreen := true
	var dist := 0.0
	var vat_clip := ""
	var vat_speed := 1.0
	var shadows := true
	var base_speed := 1.0            # the controller's speed_scale (restored after a step frame)
	var written := -1.0              # the speed_scale this node wrote on the last step frame (-1 = none)
	var on := true                   # player process_mode currently INHERIT


func _ready() -> void:
	var q := get_node_or_null("/root/Quality")
	if q and q.get("tier") != null:
		tier_index = clampi(int(q.tier), 0, BUDGETS.size() - 1)
	set_tier(tier_index)


func set_tier(t: int) -> void:
	tier_index = clampi(t, 0, BUDGETS.size() - 1)
	cfg = BUDGETS[tier_index]


func register(id: int, node: Node3D, model: Node3D, anim: AnimationPlayer, look: SkeletonModifier3D = null, vat_look := "") -> Agent:
	unregister(id)
	var a := Agent.new()
	a.id = id
	a.node = node
	a.model = model
	a.anchor = model.get_child(0) as Node3D if model.get_child_count() > 0 else model
	a.anim = anim
	var sks := model.find_children("*", "Skeleton3D", true, false)
	a.skeleton = sks[0] if not sks.is_empty() else null
	a.look = look
	a.vat_look = vat_look
	a.bucket = absi(hash(id)) % 12
	a.slot60 = absi(hash(id * 31 + 7)) % 60
	for m in model.find_children("*", "GeometryInstance3D", true, false):
		a.meshes.append(m)
	_agents.append(a)
	_by_id[id] = a
	_set_tier(a, Tier.MID)
	return a


func unregister(id: int) -> void:
	var a: Agent = _by_id.get(id)
	if a == null:
		return
	if vat and vat.has(id):
		vat.remove(id)
	if is_instance_valid(a.anim):
		_restore_speed(a)
		_pulse(a, true)
	if is_instance_valid(a.model):
		a.model.visible = true
	_skel_mode(a, true)
	_agents.erase(a)
	_by_id.erase(id)


func agent(id: int) -> Agent:
	return _by_id.get(id)


func tier_of(id: int) -> int:
	var a: Agent = _by_id.get(id)
	return a.tier if a else Tier.OUT


func _process(delta: float) -> void:
	if not enabled or camera == null:
		return
	var t0 := Time.get_ticks_usec()
	_frame += 1
	skeleton_updates = 0
	advance_usec = 0
	var n := _agents.size()
	var tr := Time.get_ticks_usec()
	if n > 0:
		_retier_slice()
	retier_usec = Time.get_ticks_usec() - tr
	var tp := Time.get_ticks_usec()
	for a: Agent in _agents:
		if not is_instance_valid(a.anim):
			continue
		match a.tier:
			Tier.NEAR:
				skeleton_updates += 1
			Tier.MID:
				# only the step frame (switch on) and the frame after it (switch off, restore speed) do any work
				var ph := (_frame + a.bucket) % a.step
				if ph == 0:
					_step_frame(a, a.step, true)
				elif a.on:
					_step_frame(a, a.step, false)
			Tier.FAR, Tier.OUT:
				# 1 Hz bookkeeping pulse: the hidden player keeps its clock (a controller waiting for a one-shot
				# to end still sees it end); a hidden mesh's skin is never drawn.
				var ph60 := (_frame + a.slot60) % 60
				if ph60 == 0:
					_step_frame(a, 60, true)
				elif a.on:
					_step_frame(a, 60, false)
				if a.tier == Tier.FAR:
					_far_tick(a)
	advance_usec = Time.get_ticks_usec() - tp
	cpu_usec = Time.get_ticks_usec() - t0


## Distance / frustum / budget for 1/RETIER_SLICES of the agents; the NEAR budget is ranked over everyone.
func _retier_slice() -> void:
	var cam := camera.global_position
	_slice = (_slice + 1) % RETIER_SLICES
	var near_d: float = cfg["near_dist"]
	var mid_d: float = cfg["mid_dist"]
	var far_d: float = cfg["far_dist"]
	for i in range(_slice, _agents.size(), RETIER_SLICES):
		var a: Agent = _agents[i]
		if not is_instance_valid(a.node):
			continue
		var p := a.node.global_position
		a.dist = p.distance_to(cam)
		a.onscreen = camera.is_position_in_frustum(p + Vector3(0, 1.0, 0)) or a.dist < 3.0
	# the ranking and tier pass runs once per RETIER_SLICES frames, after every distance has been refreshed
	if _slice != 0:
		return
	# NEAR budget: nearest on-screen agents inside near_dist (hysteresis keeps current NEAR ones a bit longer)
	var near_rank := []
	for a: Agent in _agents:
		var lim := near_d + (margin if a.tier == Tier.NEAR else 0.0)
		if a.dist < lim and a.onscreen:
			near_rank.append(a)
	near_rank.sort_custom(func(x: Agent, y: Agent) -> bool: return x.dist < y.dist)
	var near_set := {}
	for k in mini(near_rank.size(), int(cfg["near_max"])):
		near_set[near_rank[k]] = true
	var steps: Array = cfg["steps"]
	for a: Agent in _agents:
		var want := Tier.MID
		if force_tier >= 0:
			want = force_tier
		elif near_set.has(a):
			want = Tier.NEAR
		else:
			var m := margin if a.tier == Tier.FAR or a.tier == Tier.OUT else -margin
			if a.dist >= far_d + (margin if a.tier == Tier.OUT else -margin):
				want = Tier.OUT
			elif a.dist >= mid_d + m and a.vat_look != "" and vat != null and vat.assets.has(a.vat_look):
				want = Tier.FAR
		if want != a.tier:
			_set_tier(a, want)
		if a.tier == Tier.MID:
			var s: int = steps[0] if a.dist < mid_d * 0.55 else (steps[1] if a.dist < mid_d * 0.8 else steps[2])
			a.step = s if a.onscreen else OFFSCREEN_STEP
		var sh := a.tier == Tier.NEAR or (a.tier == Tier.MID and a.dist < float(cfg["shadow_dist"]))
		if sh != a.shadows:
			a.shadows = sh
			for m: GeometryInstance3D in a.meshes:
				if is_instance_valid(m):
					m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if sh else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	counts = [0, 0, 0, 0]
	for a: Agent in _agents:
		counts[a.tier] += 1


func _set_tier(a: Agent, t: int) -> void:
	var was := a.tier
	a.tier = t
	if is_instance_valid(a.node) and "lod_tier" in a.node:
		a.node.set("lod_tier", t)
	if not is_instance_valid(a.anim):
		return
	# leaving FAR: pick the pose up exactly where the VAT twin is
	if was == Tier.FAR and vat and vat.has(a.id):
		var ct := vat.clip_time(a.id)
		if a.anim.current_animation == a.vat_clip and a.anim.current_animation != "":
			a.anim.seek(ct, false)       # position only; the next processed frame poses it
		vat.remove(a.id)
	# A Skeleton3D that owns SkeletonModifier3Ds (the head look-at) re-runs its modifier stack and re-poses every
	# frame even when the modifiers are inactive and nothing was animated (P6). Only NEAR needs modifiers, so every
	# other tier switches the skeleton's modifier processing to MANUAL: it then updates only when its
	# AnimationPlayer is advanced (MID steps) or never (FAR/OUT, model hidden).
	_skel_mode(a, t == Tier.NEAR)
	match t:
		Tier.NEAR:
			_restore_speed(a)
			_pulse(a, true)
			a.model.visible = true
			if a.look:
				a.look.active = true
		Tier.MID:
			a.model.visible = true
			if a.look:
				a.look.active = false
		Tier.FAR:
			if a.look:
				a.look.active = false
			a.model.visible = false
			_vat_enter(a)
		Tier.OUT:
			if a.look:
				a.look.active = false
			a.model.visible = false


## One frame of a stepped player: on its step frame it runs (process_mode INHERIT) at speed x k, otherwise it
## is DISABLED. The controller's own speed_scale is recovered every frame, so walk speed matching still works.
func _step_frame(a: Agent, k: int, run: bool) -> void:
	var cur := a.anim.speed_scale
	if a.written >= 0.0 and is_equal_approx(cur, a.written):
		cur = a.base_speed          # nobody touched it since our step frame: restore the controller value
	a.base_speed = cur
	if run:
		a.anim.speed_scale = cur * k
		a.written = a.anim.speed_scale
		_pulse(a, true)
		skeleton_updates += 1
	else:
		if a.written >= 0.0:
			a.anim.speed_scale = cur
			a.written = -1.0
		_pulse(a, false)


func _restore_speed(a: Agent) -> void:
	if a.written >= 0.0 and is_equal_approx(a.anim.speed_scale, a.written):
		a.anim.speed_scale = a.base_speed
	a.written = -1.0


func _pulse(a: Agent, on: bool) -> void:
	if a.on == on:
		return
	a.on = on
	a.anim.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED


func _skel_mode(a: Agent, full: bool) -> void:
	if a.skeleton == null or not is_instance_valid(a.skeleton):
		return
	a.skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_IDLE if full 		else Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL


func _vat_clip_for(a: Agent, clip: String) -> String:
	var asset: VatAsset = vat.assets[a.vat_look]
	if asset.has_clip(clip):
		return clip
	# nearest stand-in: anything walking -> Walk, sitting -> Sitting_Idle, else Idle
	var l := clip.to_lower()
	if l.contains("walk") or l.contains("jog") or l.contains("run"):
		return "Walk" if asset.has_clip("Walk") else "Idle"
	if l.contains("sit") and asset.has_clip("Sitting_Idle"):
		return "Sitting_Idle"
	if (l.contains("talk") or l.contains("argue")) and asset.has_clip("Idle_Talking"):
		return "Idle_Talking"
	return "Idle"


func _vat_enter(a: Agent) -> void:
	if vat == null or not vat.assets.has(a.vat_look):
		return
	var clip := a.anim.current_animation
	var vc := _vat_clip_for(a, clip)
	a.vat_clip = clip
	a.vat_speed = a.base_speed
	var phase := a.anim.current_animation_position if vc == clip else -1.0
	vat.put(a.id, a.vat_look, a.anchor.global_transform, vc, phase, a.base_speed)


func _far_tick(a: Agent) -> void:
	if vat == null or not vat.has(a.id):
		return
	# alternate halves of the crowd each frame: 30 Hz transforms at 60 fps; clip changes checked at 15 Hz
	var ph := (_frame + a.bucket) % 4
	if ph == 0 or ph == 2:
		vat.move(a.id, a.anchor.global_transform)
	if ph != 1:
		return
	var clip := a.anim.current_animation
	if clip != a.vat_clip or not is_equal_approx(a.base_speed, a.vat_speed):
		var vc := _vat_clip_for(a, clip)
		var same := vc == vat.clip_of(a.id)
		a.vat_clip = clip
		a.vat_speed = a.base_speed
		vat.play(a.id, vc, vat.clip_time(a.id) if same else 0.0, a.base_speed)
