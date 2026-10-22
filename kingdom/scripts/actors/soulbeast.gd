extends CharacterBody3D
## F10 the Soulbeast: ONE wolf-type companion (no species zoo, no evolution). The body half; every decision lives in
## soulbeast_brain.gd. It wears the wolf model and clips at a larger scale with an ashen Style G tint and a faint
## ember soul-mark, moves like wolf.gd (terrain-following steps, capsule only near the player) and fights through
## npc_fighter moves and creature_attack_tokens.gd.
##
## Wild: dens near Thornfield's forest edge, idles, roams, eats, sleeps by day, notices the player through
## Perception.vis plus hearing, warns (growl, then a harmless warning lunge) before it bites, and flees when badly hurt.
## Trust stages show in body language (wary / curious / accepting / bonded). Bonded: follows in formation, catches up
## or teleports, waits outside interiors, fights what the player fights, takes stay/follow/attack orders from the
## context button, is downed (not dead) at 0 HP, and eats and sleeps when the player rests.
##
## Phone cost: one AnimationTree (state machine + time scale), PopulationLOD distances for update rate and animation,
## and no allocation per frame (the senses are plain fields on the brain; the 2-4 Hz think scans groups).

signal bonded(beast: Node3D)
signal downed(beast: Node3D)
signal revived(beast: Node3D)

const Brain := preload("res://scripts/actors/soulbeast_brain.gd")
const Aura := preload("res://scripts/actors/soulbeast_aura.gd")
const Models := preload("res://scripts/actors/creature_models.gd")
const Tokens := preload("res://scripts/actors/creature_attack_tokens.gd")
const Fighter := preload("res://scripts/combat/npc_fighter.gd")
const CombatStats := preload("res://scripts/combat/combat_stats.gd")
const Perception := preload("res://scripts/population/perception.gd")
const NpcWorld := preload("res://scripts/population/npc_world.gd")
const LEGACY_MODEL := "res://assets/incoming/quaternius/ultimate-animated-animals/glTF/Wolf.gltf"
const LEGACY_CLIPS := {"idle": "Idle", "walk": "Walk", "run": "Gallop", "attack": "Attack", "hit": "Idle_HitReact1",
	"death": "Death"}

const BODY_SCALE := 1.2                       # slightly larger than a wolf
const ASH_TINT := Color(0.62, 0.72, 0.95)     # Style G ashen silver-blue coat
const EMBER := Color(1.0, 0.58, 0.24)         # the soul-mark glow
const NAMES := ["Ember", "Cinder", "Ashfang", "Vesper", "Rime", "Soot"]
const FOOD_MEAT := ["venison", "pork", "wolf_meat", "mutton", "rabbit_meat"]
const FOOD_PLAIN := ["bread", "apple", "cheese"]
const FOOD_GROUPS := ["carcass", "forage_spot", "soulbeast_food"]
const TERRITORY := 45.0
const ENEMY_LAYER := 4
const WORLD_LAYER := 1
const SOLID_RANGE := 16.0
const HIT_REACH := 2.4
const BASE_HP := 70
const ROLES := [&"idle", &"walk", &"run", &"attack", &"hit", &"death"]
const TS_PARAM := "parameters/ts/scale"

var brain: RefCounted = Brain.new()
var team := 1
var species := "wolf"
var health: int:
	get:
		return brain.hp
var max_health: int:
	get:
		return brain.max_hp
var dead: bool:
	get:
		return brain.downed

var _model: Node3D
var _anim: AnimationPlayer
var _tree: AnimationTree
var _pb: AnimationNodeStateMachinePlayback
var _clips := {}
var _walk_clip := 0.85
var _run_clip := 2.6
var _impact := 0.27
var _role := &""
var _rate := -1.0
var _shape: CollisionShape3D
var _fighter: RefCounted
var _stats := {}
var _label: Label3D
var _player: Node3D
var _goal := Vector3.ZERO
var _speed := 0.0
var _knock := Vector3.ZERO
var _think := 0.0
var _busy := 0.0
var _winding := 0.0
var _strike_cd := 0.0
var _cur_move: Resource
var _target: Node3D                 # foe (ally) or foe near the den (wild)
var _foe_seen := false
var _growl_cd := 0.0
var _lunge_t := 0.0
var _last_player := Vector3.INF
var _player_jump := 0.0
var _wait_pos := Vector3.INF
var _lod := 0
var _clock := 0.0
var _pitch := 0.0
var _squash := 1.0
var _yoff := 0.0
var _base_scale := Vector3.ONE
var _jump_pending := 0.0
var _roam_t := 0.0
var _label_text := ""
var _interactable: Node
var _food_node: Node3D
var _food_at := Vector3.INF
var _wait_set := false


func _ready() -> void:
	var fighter_ok := Fighter.has_archetype("wolf")
	if fighter_ok:
		_fighter = Fighter.make("wolf", int(brain.den.x * 31.0 + brain.den.y))
		_stats = _fighter.apply_level(CombatStats.player_level())
		if brain.max_hp == BASE_HP or brain.max_hp == 70:
			brain.max_hp = int(round(float(_stats.get("hp", BASE_HP)) * 1.5))
			brain.hp = brain.max_hp
	_make_body()
	_make_model()
	_apply_group_state()
	_goal = global_position
	_player = get_tree().get_first_node_in_group("player") as Node3D if is_inside_tree() else null
	_interactable = Interactable.attach(self, {"id": "soulbeast/companion", "verb": "Offer", "target": "Soulbeast",
		"range": 3.6, "priority": 3, "can": _can_interact, "do": _interact, "label": _label_fn})
	_sync_label()


func _exit_tree() -> void:
	Tokens.release(self)
	Aura.clear(self)


# --- construction ------------------------------------------------------------------------------
func _make_body() -> void:
	collision_layer = 0
	collision_mask = WORLD_LAYER
	floor_snap_length = 0.25
	safe_margin = 0.03
	_shape = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.2
	_shape.shape = cap
	_shape.position.y = cap.height * 0.5
	_shape.disabled = true
	add_child(_shape)


func _make_model() -> void:
	var model: Node3D = null
	if Models.has("wolf"):
		model = Models.instance("wolf")
		_clips = Models.clips("wolf")
		var info := Models.info("wolf")
		_walk_clip = float(info["walk"])
		_run_clip = float(info["run"])
		_impact = float(info["impact"])
		model.scale *= BODY_SCALE
	elif ResourceLoader.exists(LEGACY_MODEL):
		model = Assets.scene(LEGACY_MODEL).instantiate()
		var box := Assets.visual_aabb(model)
		model.scale = Vector3.ONE * (0.85 / maxf(box.size.y, 0.01)) * BODY_SCALE
		_clips = LEGACY_CLIPS
	if model == null:
		return                  # model not imported (headless tests): logic still runs, nothing is drawn
	add_child(model)
	_model = model
	_base_scale = model.scale
	_anim = Assets.animation_player(model)
	if _clips == LEGACY_CLIPS and _anim:
		for a in ["Idle", "Walk", "Gallop"]:
			if _anim.has_animation(a):
				_anim.get_animation(a).loop_mode = Animation.LOOP_LINEAR
	_tint(model)
	_build_tree()


## Style G marking: an ashen coat and a low ember glow, per surface (materials duplicated once, at spawn).
func _tint(root: Node) -> void:
	if root is MeshInstance3D:
		var mi := root as MeshInstance3D
		for i in mi.get_surface_override_material_count():
			var base := mi.get_active_material(i)
			var mat: StandardMaterial3D = (base.duplicate() if base is StandardMaterial3D else StandardMaterial3D.new()) as StandardMaterial3D
			mat.albedo_color = mat.albedo_color * ASH_TINT
			mat.emission_enabled = true
			mat.emission = EMBER
			mat.emission_energy_multiplier = 0.04
			mi.set_surface_override_material(i, mat)
	for c in root.get_children():
		_tint(c)


## The one AnimationTree: a state machine over the wolf clips under a time-scale node (locomotion rate).
func _build_tree() -> void:
	if _anim == null:
		return
	var sm := AnimationNodeStateMachine.new()
	var have: Array[StringName] = []
	for role in ROLES:
		var clip := String(_clips.get(String(role), String(role)))
		if _anim.has_animation(clip):
			var n := AnimationNodeAnimation.new()
			n.animation = StringName(clip)
			sm.add_node(role, n)
			have.append(role)
	for a in have:
		for b in have:
			if a != b:
				var tr := AnimationNodeStateMachineTransition.new()
				tr.xfade_time = 0.18
				tr.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE
				sm.add_transition(a, b, tr)
	if have.is_empty():
		return
	var root := AnimationNodeBlendTree.new()
	root.add_node(&"sm", sm)
	var ts := AnimationNodeTimeScale.new()
	root.add_node(&"ts", ts)
	root.connect_node(&"ts", 0, &"sm")
	root.connect_node(&"output", 0, &"ts")
	_tree = AnimationTree.new()
	_tree.name = "AnimationTree"
	add_child(_tree)
	_tree.anim_player = _tree.get_path_to(_anim)
	_tree.tree_root = root
	_tree.active = true
	_pb = _tree.get("parameters/sm/playback") as AnimationNodeStateMachinePlayback
	_anim.active = false      # the tree drives the skeleton
	_pb.start(&"idle")
	_role = &"idle"


func _apply_group_state() -> void:
	for g in ["team0", "team1", "combatant", "soulbeast"]:
		if is_in_group(g):
			remove_from_group(g)
	add_to_group("soulbeast")
	if brain.bonded and not brain.downed:
		add_to_group("team0")
		team = 0
	elif not brain.bonded:
		add_to_group("team1")
		add_to_group("combatant")
		team = 1
	_shape.set_deferred("disabled", brain.bonded)
	collision_layer = 0 if brain.bonded else ENEMY_LAYER
	Aura.set_companion(self, brain.bonded and not brain.downed)


# --- public API ----------------------------------------------------------------------------------
## Place the den and start the beast there (wild) or restore a saved state.
func setup(den_xz: Vector2, saved := {}) -> void:
	brain.den = den_xz
	brain.pos = den_xz
	if not saved.is_empty():
		brain.from_dict(saved)
		if brain.den == Vector2.ZERO:
			brain.den = den_xz
	global_position = Vector3(brain.pos.x, WorldGen.height(brain.pos.x, brain.pos.y), brain.pos.y)
	_goal = global_position


func lod_level() -> int:
	return _lod


## 0 full (animated, 4 Hz think), 1 far (frozen pose, 1 Hz), 2 hidden (0.25 Hz), at the PopulationLOD distances.
static func lod_for(distance: float) -> int:
	if distance <= PopulationLOD.FULL_RANGE:
		return 0
	if distance <= PopulationLOD.SPRITE_RANGE:
		return 1
	return 2


static func think_period(level: int) -> float:
	return 0.25 if level == 0 else (1.0 if level == 1 else 4.0)


func snapshot() -> Dictionary:
	if is_inside_tree():          # the director saves from its own _exit_tree, when the beast may already be out of the tree
		brain.pos = Vector2(global_position.x, global_position.z)
	return brain.to_dict()


## The context button / technique wheel entry: an order. Returns false when it cannot be obeyed.
func command(c: int) -> bool:
	_refresh_target()
	var ok: bool = brain.give_command(c)
	if ok:
		_wait_set = false
		_sync_label()
		Game.say("%s %s." % [brain.soul_name, ["follows", "stays", "attacks"][c]])
	return ok


func on_player_rest(hours: float) -> void:
	var was_down: bool = brain.downed
	brain.on_rest(hours)
	if was_down:
		_stand_up()
	_apply_group_state()


func on_day() -> void:
	brain.tick_day()


## Leaving food at the den (or in its hand when it is accepting). Returns the line for the player.
func offer_food(player: Node = null) -> String:
	var item := _pick_food()
	if item == "":
		return "You have nothing to offer."
	Life.take(item, 1)
	var meat := FOOD_MEAT.has(item)
	var gain: float = brain.offer_food(2.0 if meat else 1.0, _clock)
	_place_food(item)
	if brain.state == Brain.State.SLEEP or brain.state == Brain.State.IDLE or brain.state == Brain.State.ROAM:
		_goal = _food_at
	VFX.flash(get_parent(), global_position + Vector3.UP * 0.8, EMBER, 1.0, 0.1, 2.0)
	_sync_label()
	var _p := player
	return "The Soulbeast watches you leave the %s. (trust +%d)" % [item.replace("_", " "), int(round(gain))]


## Bond: the Soul Name ritual when the player's soul can bear it, else the plain Bond. Returns the line.
func bond_with(player: Node = null, use_ritual := true) -> String:
	if not brain.can_bond():
		return "It is not ready to trust you with its name."
	var given: String = NAMES[absi(int(brain.den.x * 7.0 + brain.den.y * 13.0)) % NAMES.size()]
	var text := ""
	if use_ritual:
		var tier: int = Life.soul.tier()
		if tier >= RANaming.MIN_SOUL_TIER and Life.naming.soul_bonds.size() < RANaming.bond_limit(tier):
			var r: Dictionary = Life.naming.soul_name_ritual(Life.magicules, tier,
				{"kind": "monster", "species": "wolf", "level": CombatStats.player_level(), "name": given}, given,
				WorldSim.day, {})
			if bool(r.get("ok", false)):
				text = String(r.get("text", ""))
	if not brain.bond(given):
		return ""
	if text == "":
		text = "The Soulbeast presses against your hand. You name it %s." % given
	_apply_group_state()
	_sync_label()
	_wait_set = false
	bonded.emit(self)
	var _p := player
	return text


# --- interaction ---------------------------------------------------------------------------------
func _can_interact(_player_node: Node) -> bool:
	if brain.bonded:
		return true
	if brain.downed:
		return false
	return brain.can_bond() or (brain.stage() >= Brain.Stage.ACCEPTING and _pick_food() != "")


func _label_fn() -> Dictionary:
	if brain.bonded:
		if brain.downed:
			return {"verb": "Revive", "target": brain.soul_name}
		match brain.next_command():
			Brain.Cmd.ATTACK:
				return {"verb": "Attack my target", "target": brain.soul_name}
			Brain.Cmd.FOLLOW:
				return {"verb": "Follow", "target": brain.soul_name}
		return {"verb": "Stay", "target": brain.soul_name}
	if brain.can_bond():
		return {"verb": "Bond", "target": "Soulbeast"}
	return {"verb": "Offer food", "target": "Soulbeast"}


func _interact(player_node: Node) -> void:
	if brain.bonded:
		if brain.downed:
			brain.revive()
			_stand_up()
			_apply_group_state()
			Game.say("%s struggles to its feet." % brain.soul_name)
			revived.emit(self)
			return
		command(brain.next_command())
		return
	if brain.can_bond():
		Game.say(bond_with(player_node))
		return
	Game.say(offer_food(player_node))


func _pick_food() -> String:
	for id in FOOD_MEAT:
		if Life.count(id) > 0:
			return id
	for id in FOOD_PLAIN:
		if Life.count(id) > 0:
			return id
	return ""


func _place_food(item: String) -> void:
	if _food_node == null or not is_instance_valid(_food_node):
		_food_node = MeshInstance3D.new()
		var m := SphereMesh.new()
		m.radius = 0.14
		m.height = 0.2
		(_food_node as MeshInstance3D).mesh = m
		_food_node.add_to_group("soulbeast_food")
		get_parent().add_child(_food_node)
	var at := Vector3(brain.den.x + 1.2, 0.0, brain.den.y + 0.4)
	at.y = WorldGen.height(at.x, at.z) + 0.1
	_food_node.global_position = at
	_food_node.set_meta("item", item)
	_food_at = at


# --- frame ---------------------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	_clock += delta
	brain.now = _clock
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	var here := global_position
	var d := 99.0
	if _player:
		d = here.distance_to(_player.global_position)
		var pp := _player.global_position
		if _last_player != Vector3.INF:
			var j := pp.distance_to(_last_player)
			if j >= Brain.TELEPORT_JUMP:
				_jump_pending = j       # one frame, this far: a fast travel or a door
		_last_player = pp
	var lod := lod_for(d) if not brain.bonded else mini(lod_for(d), 1)
	if lod != _lod:
		_set_lod(lod)
	if _lod == 2 and not brain.bonded:
		_think -= delta
		if _think <= 0.0:
			_think = think_period(2)
			_think_tick(think_period(2))
		return
	if brain.downed:
		_update_pose(delta)
		return
	if _knock.length_squared() > 0.0004:
		global_position += _knock * delta
		_knock *= exp(-delta / 0.1)
	_busy -= delta
	_strike_cd -= delta
	_growl_cd -= delta
	_think -= delta
	if _think <= 0.0:
		var dt := think_period(_lod)
		_think = dt
		_think_tick(dt)
	if _winding > 0.0:
		_winding -= delta
		if _winding <= 0.0:
			_impact_now()
	var want := _move_for_state(delta)
	if _busy > 0.0 or _winding > 0.0:
		want = 0.0
	_speed = lerpf(_speed, want, minf(6.0 * delta, 1.0))
	_step(delta)
	_update_pose(delta)
	_animate()


func _set_lod(level: int) -> void:
	_lod = level
	if _model:
		_model.visible = level < 2
	if _tree:
		_tree.active = level == 0
	set_physics_process(true)


# --- senses and thinking -------------------------------------------------------------------------
func _think_tick(dt: float) -> void:
	var b := brain
	var pl := _player
	var here := global_position
	b.pos = Vector2(here.x, here.z)
	if pl == null:
		b.seen = false
		b.dist = 99.0
	else:
		var pp := pl.global_position
		b.dist = here.distance_to(pp)
		var spd := 0.0
		var v: Variant = pl.get("velocity")
		if v is Vector3:
			spd = Vector2((v as Vector3).x, (v as Vector3).z).length()
		b.player_speed = spd
		b.player_crouch = bool(pl.get("crouching"))
		b.player_armed = _player_armed(pl)
		b.player_inside = InteriorDoor.active != null
		_player_jump = _jump_pending
		_jump_pending = 0.0
		b.player_teleported = _player_jump >= Brain.TELEPORT_JUMP
		b.hour = WorldSim.time_of_day
		b.seen = _perceive(pl, pp, spd, b.dist)
	b.at_den = Vector2(here.x, here.z).distance_to(b.den) < 3.0
	b.at_goal = Vector2(_goal.x - here.x, _goal.z - here.z).length() < 1.4
	_refresh_target()
	b.has_target = _target != null
	_find_food()
	var prev: int = b.state
	var new_state: int = b.think_wild(dt) if not b.bonded else b.think_ally(dt)
	_wild_helpers(prev, new_state)
	if b.bonded:
		_ally_geometry(here)
	if b.lunged:
		b.lunged = false
		_lunge_t = 0.45
		_growl()
	if b.ate:
		b.ate = false
		_finish_meal()
	if new_state != prev:
		_on_state_enter(new_state)
	Aura.set_companion(self, b.bonded and not b.downed)
	if b.bonded and pl:
		_sync_label()


## Perception.vis for sight (cone x distance x light x stance), plus hearing (the player's noise radius).
func _perceive(pl: Node3D, pp: Vector3, spd: float, d: float) -> bool:
	var asleep: bool = brain.state == Brain.State.SLEEP
	var noise := 10.0
	if pl.has_method("noise_radius"):
		noise = float(pl.call("noise_radius"))
	var hear := noise * 0.8 * (Brain.WAKE_FACTOR if asleep else 1.0)
	if d < hear:
		return true
	if asleep:
		return d < 3.0
	var p2 := Vector2(global_position.x, global_position.z)
	var q2 := Vector2(pp.x, pp.z)
	var face := Vector2(sin(rotation.y), cos(rotation.y))
	var stance := Perception.stance_term(bool(pl.get("crouching")), spd > Brain.SPRINT_SPEED, false)
	var vis := Perception.vis(p2, face, q2, Perception.light_at(q2), stance, spd < 0.3, 1.3)
	return vis > Perception.VIS_MIN


func _player_armed(pl: Node3D) -> bool:
	var w: Variant = pl.get("weapon_drawn")
	if w != null:
		return bool(w)
	return NpcWorld.player_armed()


## Picks the foe: the player's lock-on, else the nearest hostile near the player (ally) or near itself (wild).
func _refresh_target() -> void:
	if is_instance_valid(_target) and not (_target.get("dead") == true) and _target != self \
			and global_position.distance_to(_target.global_position) < Brain.LEASH:
		if brain.bonded or global_position.distance_to(_target.global_position) < 14.0:
			return
	_target = null
	if brain.downed or _player == null:
		return
	var anchor := _player.global_position if brain.bonded else global_position
	var reach := Brain.ASSIST_RANGE if brain.bonded else 10.0
	if brain.bonded:
		var lk: Variant = _player.get("_lock")
		if lk is Node3D and is_instance_valid(lk) and not (lk.get("dead") == true) and lk != self \
				and (lk as Node3D).is_in_group("team1"):
			_target = lk
			return
	var best := reach * reach
	for n in get_tree().get_nodes_in_group("team1"):
		if n == self or not (n is Node3D) or (n.get("dead") == true) or n.is_in_group("soulbeast"):
			continue
		var d2 := anchor.distance_squared_to((n as Node3D).global_position)
		if d2 < best:
			best = d2
			_target = n as Node3D


func _find_food() -> void:
	var b := brain
	b.food_near = false
	if b.hunger <= Brain.HUNGRY - 0.1 and b.state != Brain.State.EAT:
		return
	var best := 25.0 * 25.0
	for g in FOOD_GROUPS:
		for n in get_tree().get_nodes_in_group(g):
			if not (n is Node3D):
				continue
			var d2 := global_position.distance_squared_to((n as Node3D).global_position)
			if d2 < best:
				best = d2
				_food_at = (n as Node3D).global_position
				b.food_near = true
	if b.food_near and b.state != Brain.State.EAT:
		_goal = _food_at


func _wild_helpers(_prev: int, _now: int) -> void:
	if brain.bonded:
		return
	# helping it in a fight: the foe beside it falls while the player is close.
	if _target != null:
		_foe_seen = true
	elif _foe_seen:
		_foe_seen = false
		if _player and global_position.distance_to(_player.global_position) < 22.0:
			brain.on_helped()
			brain.kills_assisted += 1
			Game.say("The Soulbeast looks at you differently. (trust +%d)" % int(Brain.GAIN_HELP))


func _ally_geometry(here: Vector3) -> void:
	var b := brain
	if _player == null:
		return
	var inside: bool = b.player_inside
	if inside:
		if not _wait_set:
			_wait_set = true
			_wait_pos = here
		return
	_wait_set = false
	if b.command == Brain.Cmd.STAY:
		return
	if Brain.needs_teleport(b.dist, _player_jump) and b.dist > 12.0:
		_teleport_to_player()


func _teleport_to_player() -> void:
	var pp := _player.global_position
	var yaw := _player.rotation.y
	var p := Brain.follow_point(Vector2(pp.x, pp.z), yaw, false, 0) - Vector2(sin(yaw), cos(yaw)) * 1.5
	global_position = Vector3(p.x, WorldGen.height(p.x, p.y), p.y)
	_speed = 0.0
	_busy = 0.0
	brain.dist = global_position.distance_to(pp)


func _on_state_enter(s: int) -> void:
	match s:
		Brain.State.WARN, Brain.State.NOTICE:
			if s == Brain.State.WARN:
				_growl()
		Brain.State.ROAM:
			_pick_roam()
		Brain.State.RETURN:
			_goal = Vector3(brain.den.x, WorldGen.height(brain.den.x, brain.den.y), brain.den.y)
		Brain.State.FLEE:
			Tokens.release(self)
			_winding = 0.0
		Brain.State.DOWNED:
			_go_down()


func _growl() -> void:
	if _growl_cd > 0.0:
		return
	_growl_cd = 2.4
	if Audio.has_sound("wolf_growl"):
		Audio.play_sfx("wolf_growl", global_position + Vector3.UP * 0.6, -3.0, 0.1)


func _pick_roam() -> void:
	# deterministic ring around the den from the brain's generator (no randf)
	var a: float = brain.rand() * TAU
	var r: float = 8.0 + brain.rand() * (TERRITORY - 8.0)
	var p: Vector2 = brain.den + Vector2(cos(a), sin(a)) * r
	_goal = Vector3(p.x, WorldGen.height(p.x, p.y), p.y)


func _finish_meal() -> void:
	if _food_node and is_instance_valid(_food_node):
		_food_node.queue_free()
		_food_node = null
	_food_at = Vector3.INF


# --- movement ------------------------------------------------------------------------------------
## Writes _goal / facing for the state and returns the wanted ground speed.
func _move_for_state(delta: float) -> float:
	var b := brain
	var pp := _player.global_position if _player else global_position
	match b.state:
		Brain.State.ROAM:
			return 0.9
		Brain.State.RETURN:
			return 3.0
		Brain.State.EAT:
			if not b.at_goal:
				return 1.2
			_face_pos(_food_at, delta)
			return 0.0
		Brain.State.FLEE:
			var away := global_position - pp
			away.y = 0.0
			away = away.normalized() if away.length() > 0.1 else Vector3.FORWARD
			var home := Vector3(b.den.x - global_position.x, 0.0, b.den.y - global_position.z)
			if home.length() > 4.0 and home.normalized().dot(away) > -0.2:
				away = (away + home.normalized() * 0.6).normalized()
			_goal = global_position + away * 6.0
			return 5.4
		Brain.State.NOTICE, Brain.State.SNIFF:
			_face_pos(pp, delta)
			return 0.0
		Brain.State.WARN:
			_face_pos(pp, delta)
			if b.dist < Brain.BACK_OFF_RANGE:
				var away2 := global_position - pp
				away2.y = 0.0
				_goal = global_position + away2.normalized() * 3.0
				return -1.0         # backs away still facing the player
			return 0.0
		Brain.State.LUNGE:
			_face_pos(pp, delta)
			if _lunge_t > 0.0:
				_lunge_t -= delta
				_goal = pp
				if b.dist > 1.9:
					return 4.2
			return 0.0
		Brain.State.APPROACH:
			_goal = pp
			_face_pos(pp, delta)
			var stop := Brain.SNIFF_DIST if b.stage() == Brain.Stage.CURIOUS else Brain.ACCEPT_DIST
			return 1.1 if b.dist > stop else 0.0
		Brain.State.ATTACK:
			return _fight_move(_player, delta, 1)
		Brain.State.FIGHT:
			return _fight_move(_target, delta, 1)
		Brain.State.FOLLOW:
			return _follow_move(pp)
		Brain.State.WAIT:
			_goal = _wait_pos if _wait_pos != Vector3.INF else global_position
			return 0.0
		Brain.State.STAY, Brain.State.SLEEP, Brain.State.IDLE, Brain.State.DOWNED:
			return 0.0
	return 0.0


func _follow_move(pp: Vector3) -> float:
	var yaw := _player.rotation.y if _player else 0.0
	var moving: bool = brain.player_speed > 0.6
	var p := Brain.follow_point(Vector2(pp.x, pp.z), yaw, moving, 0)
	_goal = Vector3(p.x, 0.0, p.y)
	var gap := Vector2(_goal.x - global_position.x, _goal.z - global_position.z).length()
	return Brain.follow_speed(gap, brain.player_speed)


## Slot holders close in and strike; the rest hold a ring. Used against the player (wild) and foes (ally).
func _fight_move(tgt: Node3D, delta: float, slots: int) -> float:
	if tgt == null or not is_instance_valid(tgt):
		return 0.0
	var d := global_position.distance_to(tgt.global_position)
	Tokens.engage(self, tgt)
	_face_pos(tgt.global_position, delta)
	if not Tokens.holds(self, tgt):
		Tokens.request(self, tgt, slots)
	if not Tokens.holds(self, tgt):
		_goal = tgt.global_position + (global_position - tgt.global_position).normalized() * 4.5
		return 1.5 if d < 4.0 else 0.0
	_goal = tgt.global_position
	var reach := 1.9
	if d <= reach and _strike_cd <= 0.0 and _busy <= 0.0 and _winding <= 0.0 and Tokens.try_strike(tgt):
		_begin_strike(tgt)
	return 5.4 if d > reach * 0.9 else 0.0


func _begin_strike(tgt: Node3D) -> void:
	var windup := 0.5
	var total := 0.95
	_cur_move = null
	if _fighter != null:
		_cur_move = _fighter.choose_move(global_position.distance_to(tgt.global_position), "idle")
		if _cur_move != null:
			windup = _cur_move.windup
			total = _cur_move.total()
	_strike_cd = randf_range(1.5, 2.2) * float(_stats.get("cdm", 1.0))
	_winding = windup
	_busy = total
	_play(&"attack", true)
	_growl()


func _impact_now() -> void:
	var tgt: Node3D = _player if brain.state == Brain.State.ATTACK else _target
	if tgt == null or not is_instance_valid(tgt):
		return
	var reach := HIT_REACH
	var dmg := 11
	var knock := 1.5
	if _cur_move != null:
		reach = _cur_move.reach
		dmg = _cur_move.damage
		knock = _cur_move.knockback
	_cur_move = null
	dmg = int(round(float(dmg) * float(_stats.get("dmg", 1.0)) * (1.25 if brain.bonded else 0.9)))
	if not Tokens.can_hit(self, tgt, reach + 0.4, WORLD_LAYER) or not tgt.has_method("take_damage"):
		return
	if tgt != _player:
		var th: Variant = tgt.get("health")
		if th != null:
			dmg = brain.clamp_damage(dmg, int(th), brain.rand())
	if dmg <= 0:
		return
	var push := tgt.global_position - global_position
	push.y = 0.0
	tgt.take_damage(dmg, self, push.normalized() * knock)
	Audio.sfx("hit", global_position, -8.0)
	Tokens.yield_slot(self)


func _face_pos(at: Vector3, delta: float) -> void:
	var to := at - global_position
	if Vector2(to.x, to.z).length() > 0.1:
		rotation.y = lerp_angle(rotation.y, atan2(to.x, to.z), 1.0 - exp(-8.0 * delta))


func _step(delta: float) -> void:
	if absf(_speed) < 0.03:
		return
	var to := _goal - global_position
	to.y = 0.0
	var dir := to.normalized() if to.length() > 0.05 else Vector3.ZERO
	var s := _speed
	var facing_player: bool = brain.state in [Brain.State.WARN, Brain.State.LUNGE, Brain.State.FIGHT, Brain.State.ATTACK]
	if brain.state == Brain.State.WARN and s < 0.0:
		dir = to.normalized()      # goal is already behind it
		s = absf(s)
	elif not facing_player and dir != Vector3.ZERO:
		rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), 1.0 - exp(-6.0 * delta))
		var fwd := Vector3(sin(rotation.y), 0.0, cos(rotation.y))
		s *= clampf(0.55 + 0.45 * fwd.dot(dir), 0.35, 1.0)
		dir = (fwd * 0.65 + dir * 0.35).normalized()
	if dir == Vector3.ZERO:
		return
	if brain.state == Brain.State.FOLLOW and to.length() < 0.35:
		return
	var near := _player != null and _player.global_position.distance_squared_to(global_position) < SOLID_RANGE * SOLID_RANGE
	var want_solid: bool = near and not brain.bonded
	if _shape.disabled == want_solid:
		_shape.set_deferred("disabled", not want_solid)
	if want_solid:
		velocity = dir * s
		move_and_slide()
		global_position.y = WorldGen.height(global_position.x, global_position.z)
	else:
		var p := global_position + dir * s * delta
		p.y = WorldGen.height(p.x, p.z)
		global_position = p


# --- pose and animation ---------------------------------------------------------------------------
## Body language without extra clips: pitch (nose down), squash (crouch / curl up), height.
func _update_pose(delta: float) -> void:
	if _model == null:
		return
	var tp := 0.0
	var ts := 1.0
	var ty := 0.0
	match brain.state:
		Brain.State.SNIFF:
			tp = 0.38
		Brain.State.EAT:
			tp = 0.5 if brain.eat_phase() > 0 else 0.0
		Brain.State.WARN, Brain.State.LUNGE:
			tp = 0.16
			ts = 0.9
		Brain.State.APPROACH:
			tp = 0.1
			ts = 0.95
		Brain.State.SLEEP:
			ts = 0.62
			ty = -0.05
		Brain.State.DOWNED:
			ts = 0.5
			ty = -0.08
		Brain.State.NOTICE:
			tp = -0.08          # head up
	var k := 1.0 - exp(-5.0 * delta)
	_pitch = lerpf(_pitch, tp, k)
	_squash = lerpf(_squash, ts, k)
	_yoff = lerpf(_yoff, ty, k)
	_model.rotation.x = _pitch
	_model.position.y = _yoff
	_model.scale.y = _base_scale.y * _squash


func _animate() -> void:
	if _pb == null or _winding > 0.0 or _busy > 0.0:
		return
	var sp := absf(_speed)
	var running := sp > _walk_clip * 1.8 and _run_clip > _walk_clip * 1.2
	var role: StringName = &"run" if running else (&"walk" if sp > 0.2 else &"idle")
	var rate := 1.0
	if role != &"idle":
		rate = clampf(sp / (_run_clip if running else _walk_clip), 0.6, 1.9)
	elif brain.state == Brain.State.SLEEP:
		rate = 0.2
	_play(role, false, rate)


func _play(role: StringName, restart := false, rate := 1.0) -> void:
	if _pb == null:
		return
	if absf(rate - _rate) > 0.03:
		_rate = rate
		_tree.set(TS_PARAM, rate)
	if restart or role != _role:
		_role = role
		if restart:
			_pb.start(role, true)
		else:
			_pb.travel(role)


func _go_down() -> void:
	Tokens.release(self)
	_winding = 0.0
	_play(&"death", true, 1.0)
	_apply_group_state()
	downed.emit(self)


func _stand_up() -> void:
	_role = &""
	_play(&"idle", true, 1.0)


# --- being hit -----------------------------------------------------------------------------------
func take_damage(amount: int, from: Node = null, knockback := Vector3.ZERO) -> void:
	if brain.downed:
		return
	var by_player := from != null and from.is_in_group("player")
	if brain.bonded and by_player:
		return                      # never hurt by its own bond
	if by_player and not brain.bonded:
		brain.on_aggression(true)
	var went_down: bool = brain.hurt(amount)
	_knock += Vector3(knockback.x, 0.0, knockback.z) * 1.2
	if went_down:
		brain.state = Brain.State.DOWNED
		_go_down()
		Game.say("%s is down. Interact to revive, or rest." % brain.soul_name)
		return
	if _winding > 0.0 and amount < 8:
		return                      # hyper-armour on light blows
	_winding = 0.0
	_busy = 0.3
	_play(&"hit", true)


func _sync_label() -> void:
	if not brain.bonded or brain.soul_name == "":
		if _label:
			_label.visible = false
		return
	if _label == null:
		_label = Label3D.new()
		_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_label.font_size = 28
		_label.pixel_size = 0.006
		_label.position = Vector3(0, 1.7, 0)
		_label.modulate = Color(1.0, 0.82, 0.55)
		_label.no_depth_test = true
		add_child(_label)
	var txt: String = brain.soul_name + (" (down)" if brain.downed else "")
	if txt != _label_text:
		_label_text = txt
		_label.text = txt
	_label.visible = _lod == 0
