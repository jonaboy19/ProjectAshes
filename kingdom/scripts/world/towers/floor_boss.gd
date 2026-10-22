extends CharacterBody3D
## Floor boss and floor mobs of the dungeon towers (docs/design/DUNGEON_TOWERS.md). Built on the project's creature models
## (creature_models.gd: troll, orc, wolf, boar, spider, wyvern, ...) scaled up and tinted for bosses.
##
## Bosses run a pattern loop: pick a pattern -> telegraph on the floor (a ring/cone/line that FILLS over the wind-up) ->
## strike -> rest. Phases at 66% / 33% health unlock more of the boss's patterns and speed; below 15% health or after
## ENRAGE_TIME seconds it enrages (hits harder, rests less, glows red). Patterns the player has learned (towers.gd
## known_patterns) show their name while winding up and give a longer warning; unknown ones show "?".
## Mobs use a single quick bite pattern.
##
## Lives in group "team1" so the player's swings and lock-on treat it like any enemy: take_damage(amount, from, knockback).
## Targets: the player and "tower_ally" followers (group "team0").
## No scene access beyond the tree; all combat numbers come from `setup()`.

signal died(who: Node3D)
signal hp_changed(hp: int, max_hp: int)
signal phase_changed(phase: int)
signal pattern_started(pattern_id: String, known: bool)
signal summon_requested(count: int, at: Vector3)
signal enraged

const Models := preload("res://scripts/actors/creature_models.gd")
const Nameplates := preload("res://scripts/core/nameplates.gd")
const TowerData := preload("res://scripts/world/towers/tower_data.gd")

const ENRAGE_TIME := 160.0
const ENRAGE_HP := 0.15
const GRAVITY := 24.0
const AGGRO_RANGE := 15.0
const MOB_PATTERN := {"name": "Bite", "kind": "cone", "windup": 0.7, "radius": 2.6, "dmg": 1.0, "cd": 0.9}

## Set by tower_run.gd while the player stands in the floor's safe zone: nothing aggroes, mobs drop the chase.
static var safe_zone := false

enum S { IDLE, CHASE, WINDUP, STRIKE, STAGGER, DEAD }

var is_boss := false
var floor_n := 1
var tower_id := ""
var display_name := ""
var title := ""
var level := 1
var max_health := 100
var health := 100
var base_damage := 10
var patterns: Array = []
var known: Array = []              # pattern ids the player has learned
var phase := 1
var is_enraged := false
var dead := false
var active := false
var kind := "troll"
var body_scale := 1.0
var home := Vector3.ZERO
var leash := 30.0
var state := S.IDLE
var fight_time := 0.0
var team := 1

var _model: Node3D
var _anim: AnimationPlayer
var _clips := {}
var _impact := 0.4
var _walk_clip := 1.0
var _run_clip := 3.0
var _speed_walk := 2.0
var _speed_run := 5.0
var _timer := 0.0
var _pattern := ""
var _pdef := {}
var _last_pattern := ""
var _target: Node3D
var _label: Label3D
var _tele_root: Node3D
var _tele_fill: MeshInstance3D
var _tele_edge: MeshInstance3D
var _tele_mats: Array[StandardMaterial3D] = []
var _struck := false
var _wave_r := 0.0
var _wave_hit := {}
var _dash_dir := Vector3.ZERO
var _knock := Vector3.ZERO
var _rest := 0.0
var _height := 2.0
var _tint := Color.WHITE
var _hits_taken := 0
var _rng := RandomNumberGenerator.new()


## info: {name, title, kind, scale, tint, patterns, hp, damage, level} (tower_data floor_info()["boss"] for bosses)
func setup(info: Dictionary, is_boss_: bool, floor_: int, tower_: String, known_: Array = [], seed_ := 1) -> void:
	is_boss = is_boss_
	floor_n = floor_
	tower_id = tower_
	display_name = String(info.get("name", "Monster"))
	title = String(info.get("title", ""))
	kind = String(info.get("kind", "goblin"))
	body_scale = float(info.get("scale", 1.0))
	_tint = info.get("tint", Color.WHITE)
	patterns = (info.get("patterns", []) as Array).duplicate()
	known = known_.duplicate()
	max_health = int(info.get("hp", 100))
	health = max_health
	base_damage = int(info.get("damage", 10))
	level = int(info.get("level", 1))
	_rng.seed = seed_
	name = "Boss" if is_boss else "Mob"


func _ready() -> void:
	collision_layer = 4
	collision_mask = 1
	floor_snap_length = 0.4
	safe_margin = 0.03
	var info := {}
	var humanoid := kind.begins_with("h:")
	if humanoid:
		_model = Assets.character(kind.substr(2), 1.85)
		info = {"impact": 0.5, "walk": 1.5, "run": 4.4}
		_clips = {"idle": "Sword_Idle", "walk": "Walking_A", "run": "Running_A", "attack": "Sword_Regular_A", "hit": "Hit_A", "death": "Death_A"}
		var hap := Assets.animation_player(_model)
		if hap:
			for a in ["Sword_Idle", "Walking_A", "Running_A"]:
				if hap.has_animation(a):
					hap.get_animation(a).loop_mode = Animation.LOOP_LINEAR
	else:
		if Models.has(kind):
			_model = Models.instance(kind)
		if _model == null:
			_model = Models.instance("goblin")
		info = Models.info(kind)
		_clips = Models.clips(kind if Models.has(kind) else "goblin")
	add_child(_model)
	_model.scale *= body_scale
	_anim = Assets.animation_player(_model)
	_impact = float(info.get("impact", 0.4))
	_walk_clip = float(info.get("walk", 1.0)) * body_scale
	_run_clip = float(info.get("run", 3.0)) * body_scale
	_speed_walk = clampf(_walk_clip, 0.8, 3.0)
	_speed_run = clampf(_run_clip, 2.2, 5.4)
	var native := {"wolf": 0.9, "boar": 0.9, "bear": 1.6, "goblin": 1.1, "orc": 2.05, "troll": 3.0, "spider": 1.0, "wyvern": 2.5,
		"giant_rat": 0.6, "blight_rat": 0.6, "fungal_brute": 2.2, "blackcap_brute": 2.2}
	_height = (1.85 if humanoid else float(native.get(kind, 1.5))) * body_scale
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = clampf(_height * 0.2, 0.3, 1.6)
	cap.height = maxf(_height * 0.85, cap.radius * 2.0 + 0.1)
	shape.shape = cap
	shape.position.y = cap.height * 0.5
	add_child(shape)
	if _tint != Color.WHITE:
		_apply_tint(_tint)
	_label = Label3D.new()
	Nameplates.style(_label, Color("ff8f6b") if is_boss else Color.WHITE, 30 if is_boss else 24, 60.0 if is_boss else 26.0)
	_label.position.y = _height + 0.5
	_label.text = "%s  Lv %d" % [display_name, level]
	add_child(_label)
	_build_telegraph()
	add_to_group("team1")
	add_to_group("combatant")
	add_to_group("tower_enemy")
	if is_boss:
		add_to_group("tower_boss")
	home = global_position
	_play("idle")


func _apply_tint(t: Color) -> void:
	if _model == null:
		return
	for mi: MeshInstance3D in _model.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var m := mi.get_active_material(s)
			if m is BaseMaterial3D:
				var d := (m as BaseMaterial3D).duplicate() as BaseMaterial3D
				d.albedo_color = d.albedo_color * t
				mi.set_surface_override_material(s, d)


# ------------------------------------------------------------------ telegraph visuals

func _tele_material(a: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1.0, 0.18, 0.12, a)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	_tele_mats.append(m)
	return m


func _build_telegraph() -> void:
	_tele_root = Node3D.new()
	_tele_root.top_level = true
	_tele_root.visible = false
	add_child(_tele_root)
	_tele_edge = MeshInstance3D.new()
	_tele_fill = MeshInstance3D.new()
	_tele_root.add_child(_tele_edge)
	_tele_root.add_child(_tele_fill)
	_tele_edge.material_override = _tele_material(0.22)
	_tele_fill.material_override = _tele_material(0.5)
	_tele_edge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_tele_fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


static func _disc_mesh(sides := 40, start := 0.0, sweep := TAU, inner := 0.0) -> ArrayMesh:
	var v := PackedVector3Array()
	var idx := PackedInt32Array()
	var nrm := PackedVector3Array()
	var steps := maxi(2, int(ceil(float(sides) * sweep / TAU)))
	for i in steps + 1:
		var a := start + sweep * float(i) / float(steps)
		v.append(Vector3(sin(a) * inner, 0.0, cos(a) * inner))
		v.append(Vector3(sin(a), 0.0, cos(a)))
		nrm.append(Vector3.UP)
		nrm.append(Vector3.UP)
	for i in steps:
		var b := i * 2
		idx.append_array([b, b + 1, b + 3, b, b + 3, b + 2])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = nrm
	arr[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return am


func _show_telegraph(pdef: Dictionary) -> void:
	var r := float(pdef["radius"]) * (body_scale if _pattern != "" and not is_boss else 1.0)
	var ground := global_position
	ground.y += 0.06
	_tele_root.visible = true
	_tele_root.global_position = ground
	_tele_root.global_rotation = Vector3(0, rotation.y, 0)
	match String(pdef["kind"]):
		"circle", "summon":
			var rr := maxf(r, 2.0)
			_tele_edge.mesh = _disc_mesh(40, 0.0, TAU, 0.94)
			_tele_fill.mesh = _disc_mesh(40)
			_tele_edge.scale = Vector3(rr, 1, rr)
			_tele_fill.scale = Vector3(0.01, 1, 0.01)
			_tele_fill.set_meta("full", Vector3(rr, 1, rr))
			_tele_fill.position = Vector3.ZERO
			_tele_edge.position = Vector3.ZERO
		"cone":
			var half := deg_to_rad(62.0)
			_tele_edge.mesh = _disc_mesh(28, -half, half * 2.0, 0.94)
			_tele_fill.mesh = _disc_mesh(28, -half, half * 2.0)
			_tele_edge.scale = Vector3(r, 1, r)
			_tele_fill.scale = Vector3(0.01, 1, 0.01)
			_tele_fill.set_meta("full", Vector3(r, 1, r))
			_tele_fill.position = Vector3.ZERO
			_tele_edge.position = Vector3.ZERO
		"line":
			var bm := BoxMesh.new()
			bm.size = Vector3(1, 0.04, 1)
			_tele_edge.mesh = bm
			_tele_fill.mesh = bm
			var w := maxf(2.4, _height * 0.55)
			_tele_edge.scale = Vector3(w, 1, r)
			_tele_edge.position = Vector3(0, 0, r * 0.5)
			_tele_fill.scale = Vector3(w * 0.96, 1, 0.01)
			_tele_fill.set_meta("full", Vector3(w * 0.96, 1, r))
			_tele_fill.position = Vector3(0, 0, 0)
		"ring":
			_tele_edge.mesh = _disc_mesh(48, 0.0, TAU, 0.97)
			_tele_fill.mesh = _disc_mesh(48, 0.0, TAU, 0.0)
			_tele_edge.scale = Vector3(r, 1, r)
			_tele_fill.scale = Vector3(0.01, 1, 0.01)
			_tele_fill.set_meta("full", Vector3(r, 1, r))
			_tele_fill.position = Vector3.ZERO
			_tele_edge.position = Vector3.ZERO
	for m in _tele_mats:
		m.albedo_color = Color(1.0, 0.18, 0.12, m.albedo_color.a)


func _update_telegraph(progress: float) -> void:
	if not _tele_root.visible:
		return
	var full: Vector3 = _tele_fill.get_meta("full", Vector3.ONE)
	var p := clampf(progress, 0.0, 1.0)
	if String(_pdef.get("kind", "")) == "line":
		_tele_fill.scale = Vector3(full.x, 1, maxf(0.01, full.z * p))
		_tele_fill.position = Vector3(0, 0, full.z * p * 0.5)
	else:
		_tele_fill.scale = Vector3(maxf(0.01, full.x * p), 1, maxf(0.01, full.z * p))
	# blink faster as the strike nears
	var blink := 0.5 + 0.5 * sin(progress * 24.0)
	_tele_mats[1].albedo_color.a = 0.35 + 0.35 * blink * p


func _hide_telegraph() -> void:
	if _tele_root:
		_tele_root.visible = false


# ------------------------------------------------------------------ public

func engage(target: Node3D) -> void:
	if dead:
		return
	active = true
	_target = target
	if state == S.IDLE:
		state = S.CHASE
		_rest = 0.4 if is_boss else 0.0


func hp_fraction() -> float:
	return float(health) / maxf(1.0, float(max_health))


func is_pattern_known(pid: String) -> bool:
	return known.has(pid)


func learn(pid: String) -> void:
	if not known.has(pid):
		known.append(pid)


func take_damage(amount: int, from: Node = null, knockback := Vector3.ZERO) -> void:
	if dead or amount <= 0:
		return
	if not active:
		engage(from as Node3D if from is Node3D else null)
	health = maxi(0, health - amount)
	hp_changed.emit(health, max_health)
	_hits_taken += 1
	var kb := 0.12 if is_boss else 1.0
	_knock += Vector3(knockback.x, 0.0, knockback.z) * kb * 1.2
	if health <= 0:
		_die()
		return
	if is_boss:
		_check_phase()
	elif state != S.WINDUP and state != S.STAGGER:
		state = S.STAGGER
		_timer = 0.3
		_play("hit", true)


func _check_phase() -> void:
	var f := hp_fraction()
	var want := 1 if f > 0.66 else (2 if f > 0.33 else 3)
	if want > phase:
		phase = want
		phase_changed.emit(phase)
		_hide_telegraph()
		state = S.STAGGER
		_timer = 1.3
		_play("idle", true)
		_roar()
	if not is_enraged and f <= ENRAGE_HP:
		_enrage()


func _enrage() -> void:
	is_enraged = true
	enraged.emit()
	_apply_tint(Color(1.25, 0.55, 0.5))
	_roar()


func _roar() -> void:
	if not is_inside_tree():
		return
	if get_parent() != null:
		VFX.shockwave(get_parent(), global_position + Vector3(0, 0.3, 0), Color(1.0, 0.4, 0.25), 6.0 + body_scale * 2.0, 0.6)
	if Audio.has_sound("orc_roar"):
		Audio.play_sfx("orc_roar", global_position + Vector3.UP * _height * 0.8, -2.0, 0.08)


func _die() -> void:
	dead = true
	state = S.DEAD
	_hide_telegraph()
	for g in ["team1", "combatant", "tower_enemy"]:
		if is_in_group(g):
			remove_from_group(g)
	collision_layer = 0
	_play("death", true)
	if _label:
		_label.visible = false
	died.emit(self)


# ------------------------------------------------------------------ brain

func _physics_process(delta: float) -> void:
	if dead:
		velocity = Vector3.ZERO
		return
	if not active:
		_idle_scan()
		_gravity(delta)
		return
	if safe_zone and not is_boss and _target != null and _target.is_in_group("player"):
		active = false
		state = S.IDLE
		_target = null
		_hide_telegraph()
		return
	fight_time += delta
	if is_boss and not is_enraged and fight_time > ENRAGE_TIME:
		_enrage()
	_rest -= delta
	if not is_instance_valid(_target) or (_target is Node and "dead" in _target and bool(_target.get("dead"))):
		_target = _pick_target()
		if _target == null:
			# nobody left to fight: back to sleep at home
			if is_boss:
				_reset_fight()
			else:
				active = false
				state = S.IDLE
			return
	match state:
		S.CHASE:
			_chase(delta)
		S.WINDUP:
			_windup(delta)
		S.STRIKE:
			_timer -= delta
			_wave_update(delta)
			_dash_update(delta)
			if _timer <= 0.0:
				state = S.CHASE
				_rest = float(_pdef.get("cd", 1.0)) * (0.6 if is_enraged else 1.0) * (0.85 if phase >= 3 else 1.0)
				_pattern = ""
		S.STAGGER:
			_timer -= delta
			_face_target(delta, 2.0)
			if _timer <= 0.0:
				state = S.CHASE
	_slide(delta)


func _idle_scan() -> void:
	if safe_zone:
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null or (("dead" in player) and bool(player.get("dead"))):
		return
	var d := global_position.distance_to(player.global_position)
	if d < AGGRO_RANGE * (1.25 if is_boss else 1.0) and absf(player.global_position.y - global_position.y) < 4.0:
		engage(player)


func _reset_fight() -> void:
	active = false
	state = S.IDLE
	health = max_health
	phase = 1
	fight_time = 0.0
	is_enraged = false
	hp_changed.emit(health, max_health)
	_hide_telegraph()
	_play("idle")


func _pick_target() -> Node3D:
	var best: Node3D = null
	var bd := INF
	for n in get_tree().get_nodes_in_group("team0"):
		if not (n is Node3D):
			continue
		if "dead" in n and bool(n.get("dead")):
			continue
		if "downed" in n and bool(n.get("downed")):
			continue
		var d := global_position.distance_to((n as Node3D).global_position)
		# the player is preferred, allies draw some attention when they are the closest body
		var w := d * (1.0 if n.is_in_group("player") else 1.25)
		if w < bd:
			bd = w
			best = n as Node3D
	return best


func _face_target(delta: float, rate := 6.0) -> void:
	if not is_instance_valid(_target):
		return
	var to := _target.global_position - global_position
	to.y = 0.0
	if to.length() > 0.05:
		rotation.y = lerp_angle(rotation.y, atan2(to.x, to.z), clampf(rate * delta, 0.0, 1.0))


func _reach(pdef: Dictionary) -> float:
	var r := float(pdef["radius"])
	match String(pdef["kind"]):
		"cone":
			return r * 0.8
		"line":
			return r * 0.55
		"ring", "circle":
			return minf(r * 0.75, 7.0)
	return r


func _available() -> Array:
	if not is_boss:
		return ["bite"]
	var n := patterns.size()
	var count := mini(n, 2 + (phase - 1) * maxi(1, int(ceil(float(n - 2) / 2.0))))
	if phase >= 3:
		count = n
	var out: Array = []
	for i in count:
		out.append(patterns[i])
	return out


func _pick_pattern() -> String:
	var avail := _available()
	if avail.size() > 1 and avail.has(_last_pattern):
		avail = avail.duplicate()
		avail.erase(_last_pattern)
	var d := 99.0
	if is_instance_valid(_target):
		d = global_position.distance_to(_target.global_position)
	# prefer what can reach the target now, with a summon when the room is empty of adds
	var reachable: Array = []
	for p: String in avail:
		if p == "bite":
			reachable.append(p)
			continue
		var pd: Dictionary = TowerData.PATTERNS[p]
		if String(pd["kind"]) == "summon":
			if get_tree().get_nodes_in_group("tower_enemy").size() < 6:
				reachable.append(p)
		elif d <= _reach(pd) + 2.0 or String(pd["kind"]) == "line" or String(pd["kind"]) == "ring":
			reachable.append(p)
	if reachable.is_empty():
		reachable = avail
	return reachable[_rng.randi() % reachable.size()]


func _chase(delta: float) -> void:
	_face_target(delta)
	var to := _target.global_position - global_position
	to.y = 0.0
	var dist := to.length()
	if _rest <= 0.0 and state == S.CHASE:
		var pid := _pick_pattern()
		var pd: Dictionary = MOB_PATTERN if pid == "bite" else TowerData.PATTERNS[pid]
		if dist <= _reach(pd) + 0.5 or String(pd["kind"]) in ["summon", "ring", "line"] and dist < 22.0:
			_begin(pid, pd)
			return
	var want := 0.0
	var stop_at := maxf(1.8, _height * 0.55) if is_boss else 1.7 * body_scale
	if dist > stop_at:
		want = (_speed_run if dist > 9.0 else _speed_walk * 1.5) * (1.12 if phase >= 2 else 1.0) * (1.15 if is_enraged else 1.0)
		if not is_boss:
			want = _speed_run * 0.9
	var dir := to.normalized() if dist > 0.01 else Vector3.ZERO
	velocity.x = lerpf(velocity.x, dir.x * want, clampf(8.0 * delta, 0.0, 1.0))
	velocity.z = lerpf(velocity.z, dir.z * want, clampf(8.0 * delta, 0.0, 1.0))
	var spd := Vector2(velocity.x, velocity.z).length()
	if spd > 0.3:
		var running := spd > _walk_clip * 1.8 and _run_clip > _walk_clip * 1.2
		_play("run" if running else "walk", false, clampf(spd / (_run_clip if running else _walk_clip), 0.6, 2.0))
	else:
		_play("idle")


func _begin(pid: String, pd: Dictionary) -> void:
	_pattern = pid
	_pdef = pd.duplicate()
	if pid != "bite":
		_last_pattern = pid
	var known_p := pid == "bite" or known.has(pid)
	var wind := float(pd["windup"]) * (1.25 if known_p and is_boss else 1.0) * (0.85 if is_enraged else 1.0)
	_pdef["windup_real"] = wind
	state = S.WINDUP
	_timer = wind
	_struck = false
	velocity.x = 0.0
	velocity.z = 0.0
	# lock the strike direction now for lines: the telegraph shows where it will go
	if is_instance_valid(_target):
		var to := _target.global_position - global_position
		to.y = 0.0
		if to.length() > 0.05:
			rotation.y = atan2(to.x, to.z)
	_dash_dir = Vector3(sin(rotation.y), 0, cos(rotation.y))
	_show_telegraph(_pdef)
	if is_boss:
		pattern_started.emit(pid, known_p)
		_label.text = "%s  Lv %d\n%s" % [display_name, level, ("%s!" % String(pd["name"])) if known_p else "?"]
	var rate := clampf(_impact / maxf(wind, 0.2), 0.3, 1.5)
	_play("attack", true, rate)


func _windup(delta: float) -> void:
	_timer -= delta
	var wind := float(_pdef.get("windup_real", 1.0))
	_update_telegraph(1.0 - _timer / wind)
	if String(_pdef["kind"]) != "line":
		_face_target(delta, 2.5 if is_boss else 4.0)
		_tele_root.global_rotation = Vector3(0, rotation.y, 0)
		_tele_root.global_position = Vector3(global_position.x, _tele_root.global_position.y, global_position.z)
	if _timer <= 0.0:
		_strike()


func _strike() -> void:
	state = S.STRIKE
	_timer = 0.55
	_hide_telegraph()
	if is_boss:
		_label.text = "%s  Lv %d" % [display_name, level]
	var dmg := int(round(float(base_damage) * float(_pdef["dmg"]) * (1.5 if is_enraged else 1.0)))
	var fwd := Vector3(sin(rotation.y), 0, cos(rotation.y))
	var victims := _bodies()
	match String(_pdef["kind"]):
		"circle":
			var r := float(_pdef["radius"])
			if get_parent():
				VFX.shockwave(get_parent(), global_position + Vector3(0, 0.3, 0), Color(1.0, 0.6, 0.3), r, 0.45)
			for v in victims:
				if _flat(v.global_position - global_position).length() <= r + 0.5:
					_hurt(v, dmg, 1.0)
			_shake()
		"cone":
			var r := float(_pdef["radius"]) * (1.0 if is_boss else body_scale)
			for v in victims:
				var to := _flat(v.global_position - global_position)
				if to.length() <= r + 0.4 and (to.length() < 1.2 or fwd.dot(to.normalized()) > 0.42):
					_hurt(v, dmg, 0.7)
			if get_parent():
				VFX.slash(get_parent(), global_position + fwd * 1.2 + Vector3(0, _height * 0.5, 0), rotation.y, 0.0, Color(1.0, 0.5, 0.4), 2.2 + body_scale)
		"line":
			_timer = 0.5
			_wave_hit.clear()
		"ring":
			_wave_r = 0.6
			_wave_hit.clear()
			_timer = float(_pdef["radius"]) / 14.0 + 0.4
			if get_parent():
				VFX.shockwave(get_parent(), global_position + Vector3(0, 0.3, 0), Color(1.0, 0.35, 0.3), 5.0, 0.5)
		"summon":
			var n := 2 if floor_n < 10 else 3
			summon_requested.emit(n, global_position)
			_roar()
			_timer = 0.8
	_play("idle")


func _flat(v: Vector3) -> Vector3:
	v.y = 0.0
	return v


func _bodies() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for n in get_tree().get_nodes_in_group("team0"):
		if n is Node3D and not (("dead" in n) and bool(n.get("dead"))) and not (("downed" in n) and bool(n.get("downed"))):
			out.append(n as Node3D)
	return out


func _hurt(v: Node3D, dmg: int, knock: float) -> void:
	var push := _flat(v.global_position - global_position).normalized() * knock * 4.0
	if v.has_method("take_damage"):
		v.call("take_damage", dmg, self, push)
	if get_parent():
		VFX.sparks(get_parent(), v.global_position + Vector3(0, 0.9, 0), Color(1.0, 0.45, 0.3), 14)


func _shake() -> void:
	var p := get_tree().get_first_node_in_group("player")
	if p != null and "_shake" in p and p.get("_shake") != null:
		p.get("_shake").add(0.35)


func _dash_update(delta: float) -> void:
	if String(_pdef.get("kind", "")) != "line" or state != S.STRIKE:
		return
	var speed := float(_pdef["radius"]) / 0.45
	velocity.x = _dash_dir.x * speed
	velocity.z = _dash_dir.z * speed
	var dmg := int(round(float(base_damage) * float(_pdef["dmg"]) * (1.5 if is_enraged else 1.0)))
	for v in _bodies():
		if _wave_hit.has(v.get_instance_id()):
			continue
		if _flat(v.global_position - global_position).length() < maxf(1.8, _height * 0.6):
			_wave_hit[v.get_instance_id()] = true
			_hurt(v, dmg, 1.4)
	_play("run", false, 1.6)


func _wave_update(delta: float) -> void:
	if String(_pdef.get("kind", "")) != "ring" or _wave_r <= 0.0:
		return
	_wave_r += 14.0 * delta
	var dmg := int(round(float(base_damage) * float(_pdef["dmg"]) * (1.5 if is_enraged else 1.0)))
	for v in _bodies():
		if _wave_hit.has(v.get_instance_id()):
			continue
		var d := _flat(v.global_position - global_position).length()
		if absf(d - _wave_r) < 1.1 and v.global_position.y - global_position.y < 1.2:
			_wave_hit[v.get_instance_id()] = true
			_hurt(v, dmg, 1.2)
	if _wave_r > float(_pdef["radius"]) + 2.0:
		_wave_r = 0.0


func _gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = -0.5
	velocity.x = lerpf(velocity.x, 0.0, clampf(8.0 * delta, 0.0, 1.0))
	velocity.z = lerpf(velocity.z, 0.0, clampf(8.0 * delta, 0.0, 1.0))
	move_and_slide()


func _slide(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = -0.5
	if state in [S.WINDUP, S.STAGGER] or (state == S.STRIKE and String(_pdef.get("kind", "")) != "line"):
		velocity.x = lerpf(velocity.x, 0.0, clampf(10.0 * delta, 0.0, 1.0))
		velocity.z = lerpf(velocity.z, 0.0, clampf(10.0 * delta, 0.0, 1.0))
	if _knock.length_squared() > 0.001:
		velocity.x += _knock.x
		velocity.z += _knock.z
		_knock = Vector3.ZERO
	# keep bosses inside their arena, everything inside its leash
	var off := global_position - home
	off.y = 0.0
	if off.length() > leash:
		velocity.x -= off.normalized().x * 6.0
		velocity.z -= off.normalized().z * 6.0
	move_and_slide()


func _play(role: String, restart := false, rate := 1.0) -> bool:
	var anim_name := String(_clips.get(role, ""))
	if _anim == null or not _anim.has_animation(anim_name):
		return false
	_anim.speed_scale = rate
	if restart or _anim.current_animation != anim_name:
		_anim.play(anim_name, 0.15)
	return true
