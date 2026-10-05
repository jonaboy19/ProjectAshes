extends CharacterBody3D
## One creature (or boss) inside a dungeon. CampMonster snaps to WorldGen.height, which cannot work in a room
## that floats 300 m above the door, so dungeons use this small body instead: same Meshy/Quaternius models
## and clips (creature_models.gd), same combat interface (take_damage, groups "combatant"/"team1"), flat
## gravity + move_and_slide, and steering by the dungeon's flow field (dungeon_root.gd) so it can follow
## you round corners.
##
## Sleeping creatures (bats, dens, the boss) wake by noise: a crouching player passes a sleeper at about
## 2 m, a runner wakes it at 7 m. Every swing has a telegraph: the name tag turns orange with a "!" and
## the clip is slowed so contact lands after `windup`. The boss adds two heavy moves: a ground slam
## (a red ring grows under it) and a charge (a red lane), and gets faster below half health.

signal died(creature: Node)

const Models := preload("res://scripts/actors/creature_models.gd")
const Nameplates := preload("res://scripts/core/nameplates.gd")
const QUAT := "res://assets/incoming/monsters/quaternius/"
## KayKit Character Pack: Skeletons (CC0): rigged, each file carries its own 95 clips (Idle, Walking_A, Running_A, Hit_A, Death_A, melee and spell attacks).
const KAY := "res://assets/kaykit/skeletons/"      # copies of the CC0 KayKit pack (assets/incoming/kaykit is .gdignore: Godot never imports it)
const KAY_GEAR_DIR := "res://assets/kaykit/skeletons/gear/"
## Weapons and shields the skeletons carry: [file, bone slot].
const KAY_GEAR := {
	"skeleton_minion": [["Skeleton_Axe", "handslot.r"], ["Skeleton_Shield_Small_A", "handslot.l"]],
	"skeleton_warrior": [["Skeleton_Blade", "handslot.r"], ["Skeleton_Shield_Large_A", "handslot.l"]],
	"skeleton_rogue": [["Skeleton_Blade", "handslot.r"], ["Skeleton_Shield_Small_B", "handslot.l"]],
	"skeleton_mage": [["Skeleton_Staff", "handslot.r"]],
}
## Quaternius Ultimate Monsters (CC0) that were never converted: loaded straight from their glTF (clips named Idle/Walk/Run/Punch/HitReact/Death ...).
const UM := "res://assets/incoming/monsters/quaternius/ultimate/"      # copies of two CC0 Ultimate Monsters glTFs (their pack dir is .gdignore)
const KAY_CLIPS := {"idle": "Idle", "walk": "Walking_A", "run": "Running_A", "attack": "1H_Melee_Attack_Slice_Horizontal", "hit": "Hit_A", "death": "Death_A"}
const WORLD_LAYER := 1
const ENEMY_LAYER := 4

## kind -> stats. hp/dmg are base values: hp += level * 4.5, dmg += level * 0.55 (boss: x5 hp, x1.5 dmg).
const KINDS := {
	"bat": {"fly": true, "hp": 6, "dmg": 3, "walk": 2.2, "run": 4.6, "reach": 1.3, "windup": 0.35, "recover": 0.9, "h": 0.4, "hear": 9.0},
	"giant_rat": {"model": "giant_rat", "hp": 14, "dmg": 4, "walk": 0.8, "run": 3.4, "reach": 1.4, "windup": 0.35, "recover": 0.8, "h": 0.6, "hear": 11.0},
	"blight_rat": {"model": "blight_rat", "hp": 18, "dmg": 5, "walk": 0.8, "run": 3.4, "reach": 1.4, "windup": 0.35, "recover": 0.8, "h": 0.6, "hear": 11.0},
	"spider": {"model": "spider", "hp": 22, "dmg": 6, "walk": 0.9, "run": 2.6, "reach": 1.8, "windup": 0.55, "recover": 0.9, "h": 0.9, "hear": 8.0, "clip_run": "walk"},
	"wolf": {"model": "wolf", "hp": 30, "dmg": 7, "walk": 1.3, "run": 4.2, "reach": 1.9, "windup": 0.45, "recover": 0.8, "h": 1.0, "hear": 13.0},
	"bear": {"model": "bear", "hp": 80, "dmg": 12, "walk": 1.3, "run": 3.8, "reach": 2.3, "windup": 0.8, "recover": 0.9, "h": 1.6, "hear": 10.0},
	"goblin": {"model": "goblin", "hp": 28, "dmg": 6, "walk": 1.0, "run": 2.8, "reach": 1.9, "windup": 0.5, "recover": 0.5, "h": 1.1, "hear": 11.0},
	"orc": {"model": "orc", "hp": 90, "dmg": 14, "walk": 1.3, "run": 3.6, "reach": 2.4, "windup": 0.85, "recover": 0.7, "h": 2.0, "hear": 11.0},
	"troll": {"model": "troll", "hp": 200, "dmg": 20, "walk": 1.2, "run": 3.0, "reach": 3.0, "windup": 1.1, "recover": 0.9, "h": 3.0, "hear": 9.0},
	"ghoul": {"quat": "ghoul", "hp": 55, "dmg": 10, "walk": 1.0, "run": 3.0, "reach": 2.0, "windup": 0.6, "recover": 0.8, "h": 1.8, "hear": 10.0},
	"rift_slime": {"quat": "rift_slime", "hp": 40, "dmg": 8, "walk": 0.7, "run": 1.9, "reach": 1.6, "windup": 0.6, "recover": 0.9, "h": 0.8, "hear": 7.0},
	"rift_wraith": {"quat": "rift_wraith", "hp": 70, "dmg": 13, "walk": 1.2, "run": 3.0, "reach": 2.2, "windup": 0.7, "recover": 0.9, "h": 1.9, "hear": 12.0, "float": 0.5},
	"bog_toad": {"quat": "bog_toad", "hp": 45, "dmg": 8, "walk": 0.8, "run": 2.6, "reach": 1.8, "windup": 0.65, "recover": 0.9, "h": 0.7, "hear": 9.0},
	"blackcap_brute": {"quat": "blackcap_brute", "hp": 120, "dmg": 16, "walk": 1.2, "run": 2.6, "reach": 2.6, "windup": 0.9, "recover": 0.9, "h": 1.8, "hear": 9.0},
	"bandit": {"human": "Rogue_Hooded", "hp": 40, "dmg": 8, "walk": 1.3, "run": 3.6, "reach": 2.0, "windup": 0.55, "recover": 0.6, "h": 1.8, "hear": 12.0},
	"mushroom_king": {"gltf": UM + "MushroomKing.gltf", "gclips": {"idle": "Idle", "walk": "Walk", "run": "Run", "attack": "Punch", "hit": "HitReact", "death": "Death"},
		"hp": 120, "dmg": 15, "walk": 1.2, "run": 3.0, "reach": 2.6, "windup": 0.8, "recover": 0.9, "h": 2.2, "hear": 9.0},
	"ghost_skull": {"gltf": UM + "Ghost_Skull.gltf", "gclips": {"idle": "Flying_Idle", "walk": "Flying_Idle", "run": "Fast_Flying", "attack": "Headbutt", "hit": "HitReact", "death": "Death"},
		"hp": 48, "dmg": 11, "walk": 1.5, "run": 3.4, "reach": 1.8, "windup": 0.5, "recover": 0.8, "h": 1.0, "hear": 12.0, "float": 0.9},
	"skeleton_minion": {"kay": "Skeleton_Minion", "hp": 30, "dmg": 6, "walk": 1.0, "run": 2.8, "reach": 1.9, "windup": 0.5, "recover": 0.6, "h": 1.7, "hear": 9.0},
	"skeleton_warrior": {"kay": "Skeleton_Warrior", "hp": 50, "dmg": 10, "walk": 1.0, "run": 2.9, "reach": 2.1, "windup": 0.6, "recover": 0.7, "h": 1.9, "hear": 10.0},
	"skeleton_rogue": {"kay": "Skeleton_Rogue", "hp": 38, "dmg": 9, "walk": 1.3, "run": 3.6, "reach": 1.9, "windup": 0.4, "recover": 0.5, "h": 1.8, "hear": 12.0, "clip_attack": "1H_Melee_Attack_Stab"},
	"skeleton_mage": {"kay": "Skeleton_Mage", "hp": 34, "dmg": 11, "walk": 0.9, "run": 2.5, "reach": 2.0, "windup": 0.7, "recover": 0.8, "h": 1.8, "hear": 10.0, "clip_attack": "Spellcast_Shoot"},
}
## kind -> [[item, chance, min, max], ...]; "gold" goes to Game.add_gold.
const DROPS := {
	"bat": [], "spider": [["gold", 0.3, 1, 3]],
	"giant_rat": [["gold", 0.2, 1, 2]], "blight_rat": [["gold", 0.25, 1, 3]],
	"wolf": [["wolf_meat", 0.8, 1, 1], ["wolf_pelt", 0.6, 1, 1]],
	"bear": [["wolf_meat", 1.0, 2, 3], ["leather", 0.8, 1, 2]],
	"goblin": [["gold", 0.7, 2, 6], ["arrowheads", 0.2, 1, 3]],
	"orc": [["gold", 0.8, 6, 16], ["iron_ore", 0.3, 1, 2]],
	"troll": [["gold", 1.0, 20, 50], ["hides", 0.7, 1, 2]],
	"ghoul": [["gold", 0.5, 3, 9], ["old_relic", 0.06, 1, 1]],
	"rift_slime": [["rift_crystal", 0.2, 1, 1]], "rift_wraith": [["rift_crystal", 0.5, 1, 2]],
	"bog_toad": [["cave_pearl", 0.15, 1, 1]], "blackcap_brute": [["gold", 0.8, 8, 20], ["coal", 0.5, 1, 3]],
	"bandit": [["gold", 0.9, 4, 14], ["bandage", 0.3, 1, 1], ["apple", 0.3, 1, 1]],
	"skeleton_minion": [["gold", 0.5, 2, 6]], "skeleton_warrior": [["gold", 0.7, 4, 10], ["old_relic", 0.05, 1, 1]],
	"mushroom_king": [["gold", 0.9, 10, 24], ["glowcap", 1.0, 2, 4]], "ghost_skull": [["rift_crystal", 0.3, 1, 1], ["ancient_coin", 0.15, 1, 1]],
	"skeleton_rogue": [["gold", 0.8, 4, 12], ["ancient_coin", 0.1, 1, 1]], "skeleton_mage": [["gold", 0.7, 4, 12], ["old_relic", 0.08, 1, 1]],
}

## F9: element tints for Rift-touched variants of the ordinary monster kinds (multiplied into the albedo).
const ELEMENT_TINT := {"rift": Color(0.72, 0.5, 1.15)}
const Rings := preload("res://scripts/vfx/telegraph_rings.gd")

enum State { SLEEP, IDLE, CHASE, ATTACK, RETURN, DEAD }

var kind := "goblin"
var cid := ""
var level := 1
var boss := false
var asleep := false
var display_name := ""
var trophy := ""
var body_scale := 1.0
var element := ""                 # F9: "rift" = Rift-touched (violet tint, rift crystal drops); "" = plain
var hp_mul := 0.0                 # F9: > 0 overrides the boss x5 health multiplier (hand-made mini-bosses)
var root: Node = null             # dungeon_root.gd (flow field, light, drops)
var home := Vector3.ZERO

var species := "goblin"           # read by the player's combat code
var health := 30
var max_health := 30
var dead := false
var hostile := true

var state := State.IDLE
var _info: Dictionary = {}
var _model: Node3D
var _anim: AnimationPlayer
var _clips := {}
var _label: Label3D
var _think := 0.0
var _cool := 1.0
var _busy := 0.0
var _winding := 0.0
var _move := "swing"              # current boss move: swing | slam | charge
var _charge_dir := Vector3.ZERO
var _charge_t := 0.0
var _wander_to := Vector3.ZERO
var _lost := 0.0
var _telegraph: MeshInstance3D
var _rings_on := false
var _enraged := false
var _hover := 0.0
var _t := 0.0
var _hit_flash := 0.0


func _ready() -> void:
	species = kind
	_info = KINDS.get(kind, KINDS["goblin"])
	collision_layer = ENEMY_LAYER
	collision_mask = WORLD_LAYER
	floor_snap_length = 0.3
	safe_margin = 0.03
	var h := float(_info["h"]) * body_scale
	var cap := CapsuleShape3D.new()
	cap.height = maxf(0.6, h * 0.9)
	cap.radius = clampf(h * 0.22, 0.2, 0.9)
	var cs := CollisionShape3D.new()
	cs.shape = cap
	cs.position.y = cap.height * 0.5 if not bool(_info.get("fly", false)) else 1.6
	add_child(cs)
	_model = _make_model()
	if _model == null:
		queue_free()
		return
	_model.scale *= body_scale
	add_child(_model)
	_anim = Assets.animation_player(_model)
	var hp_scale := hp_mul if hp_mul > 0.0 else (5.0 if boss else 1.0)
	max_health = int((float(_info["hp"]) + level * 4.5) * hp_scale)
	health = max_health
	_label = Label3D.new()
	Nameplates.style(_label, Color.WHITE, 20, 26.0)   # same screen-constant, fading, nearest-N plate as the open-world monsters (it was a world-scale label: a speck at 8 m, a banner at 2 m)
	_label.position.y = h + 0.45
	add_child(_label)
	_refresh_label()
	add_to_group("combatant")
	add_to_group("team1")
	home = global_position
	state = State.SLEEP if asleep else State.IDLE
	if bool(_info.get("fly", false)):
		_hover = 1.7 + randf() * 0.6
	_pick_wander()
	_play("idle")


func _make_model() -> Node3D:
	var m: Node3D = null
	if _info.has("model") and Models.has(String(_info["model"])):
		m = Models.instance(String(_info["model"]))
		_clips = Models.clips(String(_info["model"]))
		if _info.has("clip_run"):
			_clips["run"] = _info["clip_run"]
	elif _info.has("quat"):
		var p: String = QUAT + String(_info["quat"]) + ".glb"
		if ResourceLoader.exists(p):
			m = Assets.scene(p).instantiate()
			_clips = Models.DEFAULT_CLIPS.duplicate()
			var ap := Assets.animation_player(m)
			if ap:
				for c in ["idle", "walk", "run"]:
					if ap.has_animation(c):
						ap.get_animation(c).loop_mode = Animation.LOOP_LINEAR
	elif _info.has("kay"):
		var kp: String = KAY + String(_info["kay"]) + ".glb"
		if ResourceLoader.exists(kp):
			m = Assets.scene(kp).instantiate()
			_clips = KAY_CLIPS.duplicate()
			if _info.has("clip_attack"):
				_clips["attack"] = _info["clip_attack"]
			var kap := Assets.animation_player(m)
			if kap:
				for c in ["Idle", "Walking_A", "Running_A"]:
					if kap.has_animation(c):
						kap.get_animation(c).loop_mode = Animation.LOOP_LINEAR
			_kay_gear(m)
	elif _info.has("gltf"):
		var gp: String = _info["gltf"]
		if ResourceLoader.exists(gp):
			m = Assets.scene(gp).instantiate()
			_clips = (_info["gclips"] as Dictionary).duplicate()
			var gap := Assets.animation_player(m)
			if gap:
				for gc: String in _clips.values():
					if gap.has_animation(gc) and not ["Death", "HitReact", "Punch", "Headbutt"].has(gc):
						gap.get_animation(gc).loop_mode = Animation.LOOP_LINEAR
	elif _info.has("human"):
		m = Assets.character(String(_info["human"]), float(_info["h"]))
		_clips = {"idle": "Idle", "walk": "Walk", "run": "Jog_Fwd", "attack": "Sword_Regular_A", "hit": "Hit_Chest", "death": "Death01"}
		var ap2 := Assets.animation_player(m)
		if ap2:
			for c in ["Idle", "Walk", "Jog_Fwd"]:
				if ap2.has_animation(c):
					ap2.get_animation(c).loop_mode = Animation.LOOP_LINEAR
	elif bool(_info.get("fly", false)):
		m = _bat_model()
		_clips = {}
	if m != null and bool(_info.get("float", 0.0)):
		m.position.y = float(_info["float"])
	if m != null and kind == "goblin" and boss:
		_tint(m, Color(1.0, 0.85, 0.45))
	elif m != null and kind == "troll" and boss:
		_tint(m, Color(0.75, 0.78, 0.85))
	elif m != null and kind == "orc" and boss:
		_tint(m, Color(0.9, 0.5, 0.45))
	if m != null and ELEMENT_TINT.has(element):
		_tint(m, ELEMENT_TINT[element])
	return m


## Hangs the skeleton's weapon and shield on its hand slots (BoneAttachment3D, KayKit convention: handslot.l / handslot.r).
func _kay_gear(m: Node3D) -> void:
	var skels := m.find_children("*", "Skeleton3D", true, false)
	if skels.is_empty() or not KAY_GEAR.has(kind):
		return
	var sk := skels[0] as Skeleton3D
	for g: Array in KAY_GEAR[kind]:
		var gp: String = KAY_GEAR_DIR + String(g[0]) + ".gltf"
		if sk.find_bone(String(g[1])) < 0 or not ResourceLoader.exists(gp):
			continue
		var att := BoneAttachment3D.new()
		att.bone_name = String(g[1])
		sk.add_child(att)
		att.add_child(Assets.scene(gp).instantiate())


func _tint(n: Node, col: Color) -> void:
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var inst := mi as MeshInstance3D
		inst.material_overlay = null
		for s in inst.get_surface_override_material_count():
			var base := inst.get_active_material(s)
			if base is StandardMaterial3D:
				var dup := (base as StandardMaterial3D).duplicate() as StandardMaterial3D
				dup.albedo_color = dup.albedo_color * col
				inst.set_surface_override_material(s, dup)


static var _bat_mesh: ArrayMesh = null


func _bat_model() -> Node3D:
	if _bat_mesh == null:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_color(Color(0.12, 0.1, 0.12))
		# body + two wings as flat triangles (double sided by emitting both windings)
		var pts := [
			[Vector3(0, 0, 0.18), Vector3(-0.08, 0, -0.12), Vector3(0.08, 0, -0.12)],
			[Vector3(-0.06, 0, 0.1), Vector3(-0.6, 0.12, -0.05), Vector3(-0.06, 0, -0.14)],
			[Vector3(0.06, 0, 0.1), Vector3(0.06, 0, -0.14), Vector3(0.6, 0.12, -0.05)],
		]
		for t: Array in pts:
			for i in 3:
				st.add_vertex(t[i])
			for i in [2, 1, 0]:
				st.add_vertex(t[i])
		st.generate_normals()
		_bat_mesh = st.commit()
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.albedo_color = Color(0.2, 0.17, 0.2)
		_bat_mesh.surface_set_material(0, mat)
	var n := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = _bat_mesh
	mi.scale = Vector3.ONE * 1.4
	n.add_child(mi)
	return n


func _refresh_label() -> void:
	var nm := display_name if display_name != "" else kind.capitalize().replace("_", " ")
	if element == "rift" and display_name == "":
		nm = "Rift-touched " + nm
	_label.text = "%s  Lv %d" % [nm, level]
	_label.modulate = Color(1.0, 0.85, 0.5) if boss else Color(1, 1, 1)
	_label.outline_modulate = Color(0, 0, 0)


func prompt() -> String:
	return ""


# ---------------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if dead:
		return
	_t += delta
	_think -= delta
	_cool -= delta
	_busy -= delta
	if _hit_flash > 0.0:
		_hit_flash -= delta
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if _think <= 0.0:
		_think = 0.3
		_decide(player)
	var want := Vector3.ZERO
	var speed := 0.0
	var fly := bool(_info.get("fly", false))
	if _charge_t > 0.0:
		_charge_t -= delta
		want = _charge_dir
		speed = float(_info["run"]) * 2.6 * body_scale
		if _charge_t <= 0.0:
			_charge_impact(player)
	elif _busy <= 0.0 and _winding <= 0.0:
		match state:
			State.IDLE:
				speed = float(_info["walk"]) * body_scale
				var to := _wander_to - global_position
				to.y = 0.0
				if to.length() < 1.0:
					_pick_wander()
				want = to.normalized()
			State.CHASE:
				speed = float(_info["run"]) * body_scale * (1.25 if _enraged else 1.0)
				want = _steer_to(player)
			State.ATTACK:
				if player != null:
					_face(player.global_position, delta)
				want = Vector3.ZERO
			State.RETURN:
				speed = float(_info["walk"]) * body_scale * 1.5
				var back := home - global_position
				back.y = 0.0
				want = back.normalized()
				if back.length() < 1.2:
					state = State.IDLE
	elif _winding > 0.0:
		_winding -= delta
		if player != null and _move == "swing":
			_face(player.global_position, delta * 0.5)
		if _winding <= 0.0:
			_impact(player)
	if fly:
		var tgt_y := _hover + sin(_t * 3.0 + hash(cid) % 7) * 0.25
		if state == State.CHASE or state == State.ATTACK:
			tgt_y = 1.1
		velocity = want * speed
		velocity.y = (tgt_y - (global_position.y - _floor_y())) * 3.0
	else:
		velocity.x = want.x * speed
		velocity.z = want.z * speed
		velocity.y = velocity.y - 24.0 * delta if not is_on_floor() else -0.5
	if want.length() > 0.1 and _charge_t <= 0.0 and state != State.ATTACK:
		rotation.y = lerp_angle(rotation.y, atan2(want.x, want.z), 7.0 * delta)
	elif _charge_t > 0.0:
		rotation.y = atan2(want.x, want.z)
	move_and_slide()
	if fly and _model != null:
		_model.get_child(0).rotation.z = sin(_t * 22.0) * 0.45
	var moving := Vector2(velocity.x, velocity.z).length()
	if _busy <= 0.0 and _winding <= 0.0 and state != State.SLEEP:
		_play("run" if moving > float(_info["walk"]) * body_scale * 1.8 else ("walk" if moving > 0.2 else "idle"))


func _floor_y() -> float:
	return root.get("floor_y") if root != null and root.get("floor_y") != null else global_position.y - _hover


func _steer_to(player: Node3D) -> Vector3:
	if player == null:
		return Vector3.ZERO
	var d := player.global_position - global_position
	d.y = 0.0
	if d.length() < 3.0 or root == null or not root.has_method("flow_dir"):
		return d.normalized()
	var f: Vector3 = root.call("flow_dir", global_position)
	return f if f.length() > 0.1 else d.normalized()


func _face(at: Vector3, delta: float) -> void:
	var d := at - global_position
	d.y = 0.0
	if d.length() > 0.05:
		rotation.y = lerp_angle(rotation.y, atan2(d.x, d.z), clampf(10.0 * delta, 0.0, 1.0))


func _pick_wander() -> void:
	var a := randf() * TAU
	_wander_to = home + Vector3(cos(a), 0, sin(a)) * randf_range(1.0, 3.5)


## Noise the player makes: crouch 4 m, walk 10 m, run 18 m (player.noise_radius()).
func _hear_range(player: Node3D) -> float:
	var noise := 10.0
	if player != null and player.has_method("noise_radius"):
		noise = float(player.call("noise_radius"))
	return float(_info["hear"]) * clampf(noise / 10.0, 0.4, 1.7)


func _decide(player: Node3D) -> void:
	if player == null or (player.get("dead") == true):
		if state in [State.CHASE, State.ATTACK]:
			state = State.RETURN
		return
	var d := global_position.distance_to(player.global_position)
	var hear := _hear_range(player)
	match state:
		State.SLEEP:
			# sleepers only wake for noise close by (sneaking past works)
			if d < hear * 0.45 and _sees(player):
				_wake()
		State.IDLE, State.RETURN:
			if d < hear and _sees(player):
				state = State.CHASE
				_lost = 0.0
		State.CHASE:
			if d < float(_info["reach"]) * body_scale * 0.95 and _cool <= 0.0:
				state = State.ATTACK
			elif d > hear * 2.2 or not _sees(player):
				_lost += 0.3
				if _lost > 6.0:
					state = State.RETURN
			else:
				_lost = 0.0
		State.ATTACK:
			if d > float(_info["reach"]) * body_scale * 1.6:
				state = State.CHASE
	if state == State.ATTACK and _cool <= 0.0 and _busy <= 0.0 and _winding <= 0.0:
		_begin_attack(player, d)
	elif state == State.CHASE and boss and _cool <= 0.0 and _busy <= 0.0 and d > 5.0 and d < 14.0 and randf() < 0.5:
		_begin_attack(player, d)


func _sees(player: Node3D) -> bool:
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3(0, 1.0, 0)
	var to := player.global_position + Vector3(0, 1.0, 0)
	var q := PhysicsRayQueryParameters3D.create(from, to, WORLD_LAYER)
	q.exclude = [get_rid()]
	return space.intersect_ray(q).is_empty()


func _wake() -> void:
	state = State.CHASE
	_lost = 0.0
	if boss:
		_say("%s wakes." % display_name)
		if root != null and root.has_method("on_boss_awake"):
			root.call("on_boss_awake", self)


func _begin_attack(player: Node3D, dist: float) -> void:
	var windup := float(_info["windup"])
	_move = "swing"
	if boss:
		var pick := randf()
		var slam_p := 0.35 if _enraged else 0.25
		if dist > 5.0:
			_move = "charge"
		elif pick < slam_p:
			_move = "slam"
		match _move:
			"slam":
				windup = 1.35
			"charge":
				windup = 1.0
			_:
				windup = float(_info["windup"]) * 1.15
	if _enraged:
		windup *= 0.8
	_winding = windup
	_busy = windup + float(_info["recover"])
	_cool = randf_range(1.3, 2.2) * (0.75 if _enraged else 1.0)
	_show_telegraph(true)
	_play("attack", true, clampf(0.35 / windup, 0.3, 1.5))
	if _move == "charge" and player != null:
		_charge_dir = player.global_position - global_position
		_charge_dir.y = 0.0
		_charge_dir = _charge_dir.normalized()
		rotation.y = atan2(_charge_dir.x, _charge_dir.z)


func _impact(player: Node3D) -> void:
	_show_telegraph(false)
	if _anim:
		_anim.speed_scale = 1.0
	if player == null or dead:
		return
	if _move == "charge":
		_charge_t = 0.75
		_busy = 0.75 + float(_info["recover"])
		return
	var dmg := _damage()
	var d := global_position.distance_to(player.global_position)
	if _move == "slam":
		if d < 4.8 * body_scale and player.has_method("take_damage"):
			player.call("take_damage", int(dmg * 1.2), self, (player.global_position - global_position).normalized() * 7.0)
	else:
		var to := player.global_position - global_position
		var facing := Vector3(sin(rotation.y), 0, cos(rotation.y))
		if d < float(_info["reach"]) * body_scale * 1.25 and facing.dot(to.normalized()) > 0.2 and player.has_method("take_damage"):
			player.call("take_damage", dmg, self, to.normalized() * 3.0)
	state = State.CHASE


func _charge_impact(player: Node3D) -> void:
	if player != null and global_position.distance_to(player.global_position) < 2.6 * body_scale and player.has_method("take_damage"):
		player.call("take_damage", int(_damage() * 1.3), self, _charge_dir * 8.0)


func _damage() -> int:
	return int((float(_info["dmg"]) + level * 0.55) * (1.5 if boss else 1.0) * (1.25 if _enraged else 1.0))


func _show_telegraph(on: bool) -> void:
	if _label == null:
		return
	if on:
		_label.text = "!  " + _label.text.trim_prefix("!  ")
		_label.modulate = Color(1.0, 0.45, 0.15)
		if boss and _move != "swing":
			_spawn_telegraph()
	else:
		_refresh_label()
		if _rings_on and get_parent() != null:
			Rings.at(get_parent()).end(self)
			_rings_on = false
		if _telegraph != null:
			_telegraph.queue_free()
			_telegraph = null


## A red ring under a slam, a red lane in front of a charge; both grow/fill during the wind-up.
func _spawn_telegraph() -> void:
	if _telegraph != null:
		_telegraph.queue_free()
	if _move == "slam" and is_inside_tree() and get_parent() != null:
		# F9: the shared pooled ground telegraph (vfx/telegraph_rings.gd): a rim at the strike radius, an inner ring swelling to it.
		_rings_on = Rings.at(get_parent()).begin(self, 4.8 * body_scale, _winding, "", true)
		if _rings_on:
			return
	var mi := MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.15, 0.08, 0.45)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = false
	if _move == "slam":
		var cyl := CylinderMesh.new()
		cyl.top_radius = 4.8 * body_scale
		cyl.bottom_radius = 4.8 * body_scale
		cyl.height = 0.05
		cyl.radial_segments = 24
		mi.mesh = cyl
		mi.position = Vector3(0, 0.08, 0)
		mi.scale = Vector3(0.15, 1, 0.15)
		var tw := create_tween()
		tw.tween_property(mi, "scale", Vector3.ONE, _winding)
	else:
		var box := BoxMesh.new()
		box.size = Vector3(2.4 * body_scale, 0.05, 12.0)
		mi.mesh = box
		mi.position = Vector3(0, 0.08, 6.0)
		mi.scale = Vector3(1, 1, 0.1)
		var tw2 := create_tween()
		tw2.tween_property(mi, "scale", Vector3.ONE, _winding)
		mi.top_level = false
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_telegraph = mi


func take_damage(amount: int, from: Node = null, knockback := Vector3.ZERO) -> void:
	if dead:
		return
	health -= amount
	_hit_flash = 0.15
	if state == State.SLEEP:
		_wake()
	elif state in [State.IDLE, State.RETURN]:
		state = State.CHASE
	if boss and not _enraged and health <= max_health / 2 and health > 0:
		_enraged = true
		_say("%s roars and fights harder." % display_name)
	if health <= 0:
		_die()
		return
	if not boss or _winding <= 0.0:
		var push := Vector3(knockback.x, 0.0, knockback.z)
		if not boss:
			move_and_collide(push * 0.12)
		if not boss and _winding > 0.0:
			_winding = 0.0
			_show_telegraph(false)
		if not boss:
			_busy = 0.3
			_play("hit", true)


func _die() -> void:
	dead = true
	state = State.DEAD
	_show_telegraph(false)
	remove_from_group("combatant")
	remove_from_group("team1")
	collision_layer = 0
	if not _play("death", true):
		var t0 := create_tween()
		t0.tween_property(_model, "scale", Vector3(0.01, 0.01, 0.01), 0.6)
	if _label:
		_label.visible = false
	_drops()
	died.emit(self)
	var life := get_node_or_null("/root/Life")
	if life != null and kind != "bat":
		life.call("on_monster_killed", kind)
	var t := create_tween()
	t.tween_interval(6.0 if not boss else 12.0)
	t.tween_property(_model, "scale", _model.scale * Vector3(1, 0.01, 1), 0.5)
	t.tween_callback(queue_free)


func _drops() -> void:
	var life := get_node_or_null("/root/Life")
	var game := get_node_or_null("/root/Game")
	if life == null:
		return
	var parts := PackedStringArray()
	for e: Array in DROPS.get(kind, []):
		if randf() > float(e[1]):
			continue
		var n := randi_range(int(e[2]), int(e[3]))
		if e[0] == "gold":
			if game != null:
				game.call("add_gold", n)
				parts.append("%d gold" % n)
		else:
			life.call("give", String(e[0]), n)
			parts.append("%d %s" % [n, String(e[0]).replace("_", " ")])
	if not parts.is_empty() and game != null and not boss:
		game.call("say", "Found: %s." % ", ".join(parts))


func _say(text: String) -> void:
	var game := get_node_or_null("/root/Game")
	if game != null:
		game.call("say", text)


func _play(role: String, restart := false, rate := 1.0) -> bool:
	if _anim == null:
		return false
	var nm := String(_clips.get(role, ""))
	if nm == "" or not _anim.has_animation(nm):
		return false
	_anim.speed_scale = rate
	if restart or _anim.current_animation != nm:
		_anim.play(nm, 0.2)
	return true


## Wake or alert from the dungeon (an ally was hit, the boss shouted).
func alert() -> void:
	if not dead and state in [State.SLEEP, State.IDLE]:
		state = State.CHASE
