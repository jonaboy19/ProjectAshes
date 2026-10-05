extends RefCounted
## Subscriber for the player's combat signals: every VFX, audio, camera-shake, hit-stop and animation-cue
## call that used to sit inline in player.gd's _start_swing / _resolve_hit / _parry / take_damage lives
## here. Combat code only emits (swing_started, hit_confirmed, parried, blocked, clashed); add another
## listener instead of another inline call. Animation clips are only played by name, as before.

const Feel := preload("res://scripts/combat/combat_feel.gd")
const ImpactPool := preload("res://scripts/vfx/impact_pool.gd")

const SLASH_LEAD := 0.07
const SLASH_TILTS := [0.9, -0.9, 0.05, 0.0]
const FLASH_LAYER := 60

var _p: Node
var _budget := Feel.Budget.new()      # hit-stop and flash never stack past combat_feel.gd's limits
var _swing: Dictionary = {}           # info of the swing in progress (combo index, riposte)
var _flash_layer: CanvasLayer
var _flash_rect: ColorRect


func bind(player: Node) -> void:
	_p = player
	player.swing_started.connect(_on_swing_started)
	player.hit_confirmed.connect(_on_hit_confirmed)
	player.parried.connect(_on_parried)
	player.blocked.connect(_on_blocked)
	player.clashed.connect(_on_clashed)


func _on_swing_started(action: Resource, info: Dictionary) -> void:
	var p := _p
	_swing = info
	Audio.sfx("swing", null, -4.0)
	var vm: Node3D = p._viewmodel
	if vm.visible:
		var t := p.create_tween()
		var combo: int = info["combo"]
		t.tween_property(vm, "rotation", Vector3(-0.35, 1.2 * (1 if combo % 2 == 0 else -1), 0.5), 0.1)
		t.tween_property(vm, "rotation", p.VIEWMODEL_REST, 0.25)
	var weak: bool = info["weak"]
	var arc_col := Color(1.0, 0.9, 0.7) if not weak else Color(0.7, 0.7, 0.75)
	if info["riposte"]:
		arc_col = Color(1.0, 0.97, 0.55)
	var id: int = info["id"]
	var hit_t: float = info["hit_t"]
	var yaw: float = info["yaw"]
	var combo_i: int = info["combo"]
	if p._trail and not vm.visible:
		# Blade-synced ribbon from the clip's marker window (COMBAT_AUDIT C4).
		p._trail.swing(action.anim, info["anim_speed"])
	else:
		p.get_tree().create_timer(maxf(hit_t - SLASH_LEAD, 0.02)).timeout.connect(func() -> void:
			if is_instance_valid(p) and p.is_inside_tree() and id == p.swing_id():
				VFX.slash(p.get_parent(), p.global_position + Vector3(0, 1.15 * Life.body_scale(), 0), yaw,
					SLASH_TILTS[combo_i % SLASH_TILTS.size()], arc_col, 1.6))


func _on_hit_confirmed(points: Array, finisher: bool, mixers: Array) -> void:
	var p := _p
	var action: Resource = p.get("_action")
	var knock: float = float(action.knockback) if action else 0.0
	var dmg := int(action.damage) if action else 0
	var poise := float(action.poise_damage) if action else 0.0
	var tier := Feel.tier_for(finisher, false, knock, dmg, poise, bool(_swing.get("riposte", false)))
	var element := _element_of(action)
	var world: Node = p.get_parent()
	var fwd: Vector3 = p.forward() if p.view == p.View.FIRST else p.facing()
	var pool: Node3D = ImpactPool.at(world)
	for i in points.size():
		var pt: Vector3 = points[i]
		var dir: Vector3 = pt - p.global_position
		dir.y = 0.0
		pool.play(pt, element, tier if i < 2 else Feel.Tier.LIGHT, dir.normalized() if dir.length() > 0.01 else fwd)
	if finisher:
		VFX.shockwave(world, p.global_position + fwd * 1.2, Color(1.0, 0.85, 0.45), 3.2)
		if not points.is_empty():
			VFX.impact_frame(world, points[0], 0.7)
	if not points.is_empty():
		Audio.sfx("hit")
		var side := 1.0 if int(_swing.get("combo", 0)) % 2 == 0 else -1.0
		_cues(tier, side, mixers)


## Tiered contact cues: hit-stop frames (mixer-aware, budgeted), FOV punch, camera roll, shake and the
## one-frame finisher flash. Every one is capped and merged by max, so flurries and guard breaks never stack past
## the limits in combat_feel.gd.
func _cues(tier: int, side: float, mixers: Array) -> void:
	var p := _p
	var now := Time.get_ticks_msec() * 0.001
	var stop := _budget.request_stop(Feel.hit_stop_seconds(tier), now)
	if stop > 0.0:
		p._hit_stop(stop, mixers)
	p._add_camera_shake(Feel.SHAKE[tier])
	if Feel.fov_punch(tier) > 0.0:
		p._fov_punch(Feel.fov_punch(tier))
	if Feel.roll(tier) > 0.0:
		p._camera_roll(Feel.roll(tier) * side)
	if Feel.FLASH[tier] > 0.0 and _budget.request_flash(now):
		_flash_one_frame(Feel.FLASH[tier])


## White full-screen flash for exactly one rendered frame (scaled by the screen-feedback setting; off at 0).
func _flash_one_frame(alpha: float) -> void:
	var p := _p
	var strength: float = p._screen_feedback_strength()
	if strength <= 0.0 or not p.is_inside_tree():
		return
	if _flash_rect == null or not is_instance_valid(_flash_rect):
		_flash_layer = CanvasLayer.new()
		_flash_layer.layer = FLASH_LAYER
		_flash_rect = ColorRect.new()
		_flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_flash_rect.visible = false
		_flash_layer.add_child(_flash_rect)
		p.add_child(_flash_layer)
	_flash_rect.color = Color(1.0, 0.97, 0.88, alpha * strength)
	_flash_rect.visible = true
	RenderingServer.frame_post_draw.connect(_end_flash, CONNECT_ONE_SHOT)


func _end_flash() -> void:
	if _flash_rect != null and is_instance_valid(_flash_rect):
		_flash_rect.visible = false


func _element_of(action: Resource) -> String:
	if action != null:
		var e: Variant = action.get("element")
		if e is String and ImpactPool.VARIANTS.has(e):
			return e
	return "physical"


func _on_parried(_attacker: Node, at: Vector3, grade: String) -> void:
	var p := _p
	p._animator.play_upper("Block_Hit", 1.8)
	VFX.impact_frame(p.get_parent(), p.global_position + Vector3.UP * 1.2, 0.5)
	Audio.sfx("clash")
	VFX.sparks(p.get_parent(), at, Color(1.0, 0.97, 0.75), 60 if grade == "perfect" else 42)
	VFX.flash(p.get_parent(), at, Color(1.0, 0.9, 0.6), 3.0, 0.15, 5.0)
	ImpactPool.at(p.get_parent()).play(at, "physical", Feel.Tier.HEAVY, -p.facing())
	p._add_camera_shake(0.3)
	p._fov_punch(4.0)
	p._hit_stop(p.PARRY_HIT_STOP * (1.4 if grade == "perfect" else 1.0))


func _on_blocked(_attacker: Node, guard_broken: bool) -> void:
	var p := _p
	p._add_camera_shake(0.15)
	if guard_broken:
		# Heavy stagger with both feet planted (CharacterAnimator.PREFERRED_CLIPS).
		p._kick(-p.facing() * 2.2)
		p._animator.play_full("Stagger_Back", 1.0)
		Game.say("Guard broken!")
		ImpactPool.at(p.get_parent()).play(p.global_position + p.facing() * 0.8 + Vector3.UP * 1.2, "physical", Feel.Tier.FINISHER, p.facing())
		_cues(Feel.Tier.FINISHER, -1.0, [])
	else:
		p._animator.play_upper("Block_Hit", 1.5)
		Audio.sfx("clash")


func _on_clashed(_attacker: Node, won: bool) -> void:
	var p := _p
	Audio.sfx("clash")
	VFX.sparks(p.get_parent(), p.global_position + p.facing() * 1.0 + Vector3.UP * 1.2, Color(1.0, 0.95, 0.7), 36)
	p._add_camera_shake(0.3 if won else 0.4)
	p._hit_stop(0.08)
