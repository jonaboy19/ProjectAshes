extends RefCounted
## Subscriber for the player's combat signals: every VFX, audio, camera-shake, hit-stop and animation-cue
## call that used to sit inline in player.gd's _start_swing / _resolve_hit / _parry / take_damage lives
## here. Combat code only emits (swing_started, hit_confirmed, parried, blocked, clashed); add another
## listener instead of another inline call. Animation clips are only played by name, as before.

const SLASH_LEAD := 0.07
const SLASH_TILTS := [0.9, -0.9, 0.05, 0.0]

var _p: Node


func bind(player: Node) -> void:
	_p = player
	player.swing_started.connect(_on_swing_started)
	player.hit_confirmed.connect(_on_hit_confirmed)
	player.parried.connect(_on_parried)
	player.blocked.connect(_on_blocked)
	player.clashed.connect(_on_clashed)


func _on_swing_started(action: Resource, info: Dictionary) -> void:
	var p := _p
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


func _on_hit_confirmed(points: Array, finisher: bool) -> void:
	var p := _p
	for pt: Vector3 in points:
		VFX.sparks(p.get_parent(), pt, Color(1.0, 0.72, 0.35), 30 if finisher else 18)
	var fwd: Vector3 = p.forward() if p.view == p.View.FIRST else p.facing()
	if finisher:
		VFX.shockwave(p.get_parent(), p.global_position + fwd * 1.2, Color(1.0, 0.85, 0.45), 3.2)
		if not points.is_empty():
			VFX.impact_frame(p.get_parent(), points[0], 0.7)
	if not points.is_empty():
		Audio.sfx("hit")
		p._hit_stop(0.09 if finisher else 0.05)
		p._shake.add(0.45 if finisher else 0.22)


func _on_parried(_attacker: Node, at: Vector3, grade: String) -> void:
	var p := _p
	p._animator.play_upper("Block_Hit", 1.8)
	VFX.impact_frame(p.get_parent(), p.global_position + Vector3.UP * 1.2, 0.5)
	Audio.sfx("clash")
	VFX.sparks(p.get_parent(), at, Color(1.0, 0.97, 0.75), 60 if grade == "perfect" else 42)
	VFX.flash(p.get_parent(), at, Color(1.0, 0.9, 0.6), 3.0, 0.15, 5.0)
	p._shake.add(0.3)
	p._hit_stop(p.PARRY_HIT_STOP * (1.4 if grade == "perfect" else 1.0))


func _on_blocked(_attacker: Node, guard_broken: bool) -> void:
	var p := _p
	p._shake.add(0.15)
	if guard_broken:
		# Heavy stagger with both feet planted (CharacterAnimator.PREFERRED_CLIPS).
		p._animator.play_full("Hit_B", 1.3)
		Game.say("Guard broken!")
	else:
		p._animator.play_upper("Block_Hit", 1.5)
		Audio.sfx("clash")


func _on_clashed(_attacker: Node, won: bool) -> void:
	var p := _p
	Audio.sfx("clash")
	VFX.sparks(p.get_parent(), p.global_position + p.facing() * 1.0 + Vector3.UP * 1.2, Color(1.0, 0.95, 0.7), 36)
	p._shake.add(0.3 if won else 0.4)
	p._hit_stop(0.08)
