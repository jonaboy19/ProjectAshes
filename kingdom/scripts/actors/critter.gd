class_name Critter
extends Node3D
const ContactBlobS := preload("res://scripts/actors/contact_blob.gd")
## An ordinary animal (CC0, incoming/animals): wanders around a home spot,
## grazes or pecks, and the skittish ones bolt when the player comes close.
## No physics or navigation: it follows the terrain, like wolves and soldiers,
## so dozens cost almost nothing.
##
## Hunting: wild game (Gathering.GAME_HEALTH: rabbit, fox, deer, stag) can be
## hurt. It joins "team1" only while the player is within HUNT_REACH and
## swinging, so the player's melee (player.gd sweeps team1 and duck-types
## take_damage) lands without battle music or follower aggro firing. Hit
## game bolts; killed game plays its Death clip (or tips over) and its drops go
## straight into the pack. Livestock, pets and horses ignore damage entirely.
## Wary kinds stop and stare when the player is just outside notice range; if
## the player has noise_radius(), notice range scales with it (crouch to stalk).

const Gathering := preload("res://scripts/sim/gathering_items.gd")
const NodePool := preload("res://scripts/core/node_pool.gd")
const DIR := "res://assets/incoming/animals/"
## Game joins team1 inside this distance to the player (melee reach is 2.6 m,
## target assist 3.8 m in player.gd).
const HUNT_REACH := 4.2
## Kinds that pause and watch before they bolt -> how keenly they hear.
const WARY := {"deer": 1.0, "stag": 1.0, "fox": 0.9, "rabbit": 0.8}
## player.noise_radius() at which game notices at its full skittish distance
## (the player's running noise); quieter gaits scale it down, never below
## MIN_NOTICE. Walking gets a deer to ~9 m, a crouched stalk to ~3.6 m.
const NOISE_FULL := 18.0
const MIN_NOTICE := 2.0
## Stare band beyond notice range (x notice).
const ALERT_BAND := 1.35
const CORPSE_SECONDS := 25.0
const MOVE_ACCELERATION := 3.2
const MOVE_BRAKING := 5.5
## Reliable ground speeds from docs/qa/anim_qa_report.md. Entries with a zero
## measurement are intentionally omitted: the tiny, stylized cycles need visual
## authoring rather than a misleading speed inferred from bad foot contacts.
const ANIM_GROUND_SPEEDS := {
	"dog": {"Walk": 0.70, "Run": 1.71},
	"sheepdog": {"Walk": 0.71, "Run": 1.73},
	"cow": {"Walk": 1.06, "Run": 4.99},
	"ox": {"Walk": 1.01, "Run": 4.64},
	"sheep": {"Run": 1.92},
	"pig": {"Run": 1.29},
	"horse": {"Walk": 1.41, "Run": 5.86},
	"horse_grey": {"Walk": 1.36, "Run": 5.68},
	"horse_draft": {"Walk": 1.53, "Run": 6.41},
	"donkey": {"Walk": 1.30},
	"deer": {"Walk": 1.06, "Run": 2.4},
	"stag": {"Walk": 1.31, "Run": 2.8},
	"fox": {"Walk": 0.44, "Run": 1.87},
	"goat": {"Walk": 0.76},
}
## Deer/stag Run: planted-foot probe of the Run clip (2026-09-28), scaled by the
## same factor that maps the probe's Walk onto the QA report's Walk value.
## kind -> [file, walk speed, run speed, wander radius, skittish distance (0 = tame)]
## Flee bursts last two seconds. Deer and stag bolt at 6.0 / 6.2 m/s, just under
## the player's 6.5 m/s run (player.gd), so a hunter who keeps after them closes
## in slowly between bursts; everything else is slower still.
const KINDS := {
	"chicken": ["procedural/chicken.glb", 0.6, 2.2, 5.0, 2.5],
	"rooster": ["procedural/rooster.glb", 0.6, 2.2, 5.0, 2.5],
	"duck": ["procedural/duck.glb", 0.5, 1.8, 8.0, 4.0],
	"goose": ["procedural/goose.glb", 0.55, 1.8, 8.0, 3.0],
	"pigeon": ["procedural/pigeon.glb", 0.4, 1.6, 6.0, 3.0],
	"crow": ["procedural/crow.glb", 0.4, 1.6, 8.0, 5.0],
	"rabbit": ["procedural/rabbit.glb", 0.7, 5.0, 10.0, 7.0],
	"dog": ["quaternius/dog.glb", 1.1, 4.0, 12.0, 0.0],
	"sheepdog": ["quaternius/sheepdog.glb", 1.1, 4.0, 14.0, 0.0],
	"cat": ["quaternius/cat.glb", 0.5, 2.5, 6.0, 1.5],
	"cat_ginger": ["quaternius/cat_ginger.glb", 0.5, 2.5, 6.0, 1.5],
	"cow": ["quaternius/cow.glb", 0.7, 2.0, 9.0, 0.0],
	"ox": ["quaternius/ox.glb", 0.7, 2.0, 7.0, 0.0],
	"sheep": ["quaternius/sheep.glb", 0.6, 2.4, 9.0, 3.0],
	"pig": ["quaternius/pig.glb", 0.6, 2.2, 6.0, 2.0],
	"goat": ["quaternius/goat.glb", 0.7, 2.8, 8.0, 3.0],
	"horse": ["quaternius/horse_riding.glb", 0.9, 5.0, 4.0, 0.0],
	"horse_grey": ["quaternius/horse_grey.glb", 0.9, 5.0, 4.0, 0.0],
	"horse_draft": ["quaternius/horse_draft.glb", 0.8, 4.0, 4.0, 0.0],
	"donkey": ["quaternius/donkey.glb", 0.7, 3.0, 4.0, 0.0],
	"deer": ["quaternius/deer.glb", 0.9, 6.0, 18.0, 16.0],
	"stag": ["quaternius/stag.glb", 0.9, 6.2, 18.0, 18.0],
	"fox": ["res://assets/generated/animals/fox_gallop.glb", 0.8, 5.0, 14.0, 9.0],
	# Meshy free pack farm animals (rigged: lowercase idle/walk/eat clips, aliased to the Idle/Walk/Eat names below) and two Quaternius
	# originals that had no converted copy (clips Idle/Walk/Gallop/Eating, aliased): docs/qa/ASSET_AUDIT.md "use the unused models".
	"cow_brown_a": ["res://assets/incoming/meshy_free/farm/rigged/cow_brown_a_rigged.glb", 0.7, 2.0, 9.0, 0.0],
	"cow_brown_b": ["res://assets/incoming/meshy_free/farm/rigged/cow_brown_b_rigged.glb", 0.7, 2.0, 9.0, 0.0],
	"cow_spotted": ["res://assets/incoming/meshy_free/farm/rigged/cow_spotted_rigged.glb", 0.7, 2.0, 9.0, 0.0],
	"hen_meshy": ["res://assets/incoming/meshy_free/farm/rigged/chicken_hen_rigged.glb", 0.6, 2.2, 5.0, 2.5],
	"rooster_meshy": ["res://assets/incoming/meshy_free/farm/rigged/chicken_rooster_rigged.glb", 0.6, 2.2, 5.0, 2.5],
	"horse_white": ["res://assets/incoming/quaternius/ultimate-animated-animals/glTF/Horse_White.gltf", 0.9, 5.0, 4.0, 0.0],
	"husky": ["res://assets/incoming/quaternius/ultimate-animated-animals/glTF/Husky.gltf", 1.1, 4.0, 12.0, 0.0],
}
## Clip names of the pieces above -> the names this script plays.
const CLIP_ALIASES := {"Idle": ["idle"], "Walk": ["walk"], "Run": ["run", "Gallop", "walk"], "Eat": ["eat", "Eating"], "Death": ["death"], "Hit": ["hit", "Idle_HitReact1"]}

var kind := "chicken"
var home := Vector2.ZERO
var _anim: AnimationPlayer
## AAA pass 2026-10-06: town horses are the textured riding horse (HorseRig: painted coat, bridle, 50 real gaits) instead of
## the flat-shaded Quaternius low-poly ones. The Quaternius entries above stay as the fallback when the rig assets are absent.
const RIG_COATS := {"horse": "bay", "horse_grey": "grey", "horse_white": "dappled"}
var _rig: Node3D
var _model: Node3D
## Visual cull (perf pass 2026-09-29): a city has 100+ hens; beyond CULL_SMALL /
## CULL_BIG (scaled by the tier's visibility-range multiplier) the model is hidden
## and its AnimationPlayer paused, so nobody pays skinning or clip sampling for
## animals too small to see. Behaviour keeps running at the far LOD rate.
const SMALL := ["chicken", "rooster", "duck", "goose", "pigeon", "crow", "rabbit", "cat", "cat_ginger", "hen_meshy", "rooster_meshy"]
const CULL_SMALL := 40.0   # round 2: was 60 (LOW 22 m)
const CULL_BIG := 100.0
var _culled := false
var _target := Vector2.ZERO
var _pause := 0.0
var _fleeing := 0.0
var _cfg: Array
var _move_speed := 0.0
var _idle_clip := "Idle"
## Hunting state (only wild game ever changes these).
var health := 0
var dead := false
var huntable := false
var _stagger := 0.0
var _flee_speed := 0.0
## Riding (mount_controller.gd): a claimed horse stops wandering and is placed
## by its rider. A rider-owned copy is not tracked by AmbientLife, so once
## released it removes itself when the player is far away.
const RIDER_DESPAWN := 250.0
var claimed := false
var rider_owned := false
var _death_tweens: Array[Tween] = []   # F12 pooling: killed by reset()


func _ready() -> void:
	_cfg = KINDS[kind]
	var path := String(_cfg[0])
	if not path.begins_with("res://"):
		path = DIR + path
	if not ResourceLoader.exists(path):
		queue_free()
		return
	if RIG_COATS.has(kind) and ResourceLoader.exists("res://assets/generated/horses/horse_riding.glb"):
		_rig = HorseRig.new()
		_rig.set("coat", RIG_COATS[kind])
		var tack: Array[String] = ["bridle"]
		_rig.set("tack", tack)
		add_child(_rig)
		_model = _rig
		var blob: MeshInstance3D = ContactBlobS.attach(self, 0.9)
		blob.scale = Vector3(1.0, 1.0, 2.4)
		_anim = null
		huntable = false
		add_to_group("interactable")
		rotation.y = randf() * TAU
		_pause = randf_range(0.0, 4.0)
		_pick()
		return
	var model: Node3D = Assets.scene(path).instantiate()
	add_child(model)
	_model = model
	_anim = Assets.animation_player(model)
	if _anim:
		_alias_clips()
		for a in ["Idle", "Walk", "Run", "Eat", "Walk_Slow"]:
			if _anim.has_animation(a):
				_anim.get_animation(a).loop_mode = Animation.LOOP_LINEAR
		for a in ["Death", "Hit"]:
			if _anim.has_animation(a):
				_anim.get_animation(a).loop_mode = Animation.LOOP_NONE
	huntable = Gathering.is_game(kind)
	health = int(Gathering.GAME_HEALTH.get(kind, 0))
	if rideable():
		add_to_group("interactable")
	rotation.y = randf() * TAU
	_pause = randf_range(0.0, 4.0)
	_pick()


# --- pooling (F12, scripts/core/node_pool.gd) -----------------------------------------------------------

func on_acquire() -> void:
	pass


func on_release() -> void:
	pass


## Back to a freshly spawned animal of the same kind: alive, unclaimed, unculled, upright, full size.
func reset() -> void:
	if _model == null:
		return
	for t in _death_tweens:
		if t != null and t.is_valid():
			t.kill()
	_death_tweens.clear()
	if is_in_group("team1"):
		remove_from_group("team1")
	dead = false
	claimed = false
	rider_owned = false
	huntable = Gathering.is_game(kind)
	health = int(Gathering.GAME_HEALTH.get(kind, 0))
	_stagger = 0.0
	_fleeing = 0.0
	_flee_speed = 0.0
	_move_speed = 0.0
	_idle_clip = "Idle"
	_lod_tick = -1
	_lod_acc = 0.0
	home = Vector2.ZERO
	scale = Vector3.ONE
	rotation = Vector3(0.0, randf() * TAU, 0.0)
	_culled = false
	_model.visible = true
	if _anim:
		_anim.active = true
		_anim.speed_scale = 1.0
	_pause = randf_range(0.0, 4.0)
	_target = Vector2.ZERO
	_play("Idle")


func _pick() -> void:
	var r: float = _cfg[3]
	var a := randf() * TAU
	_target = home + Vector2(cos(a), sin(a)) * randf_range(0.5, r)


## Update-rate LOD (performance, not behaviour): the brain of an animal far from the
## player runs every Nth physics frame with the accumulated delta, staggered per
## instance. Near ones (where anyone would notice) run every frame. Capital profile
## 2026-09-28: all ambient animals cost ~9 ms/frame at full rate.
const LOD_NEAR := 30.0
const LOD_MID := 70.0
static var _player_ref: Node3D
var _lod_acc := 0.0
var _lod_tick := -1


static func _the_player(tree: SceneTree) -> Node3D:
	if not is_instance_valid(_player_ref):
		_player_ref = tree.get_first_node_in_group("player") as Node3D
	return _player_ref


func _physics_process(delta: float) -> void:
	if dead or claimed:
		return
	if _lod_tick < 0:
		_lod_tick = get_instance_id() % 6
	var pl := _the_player(get_tree())
	if pl and not rider_owned and _stagger <= 0.0:
		var d2 := pl.global_position.distance_squared_to(global_position)
		var every := 1 if d2 < LOD_NEAR * LOD_NEAR else (3 if d2 < LOD_MID * LOD_MID else 6)
		_lod_tick += 1
		_lod_acc += delta
		if every > 1 and _lod_tick % every != 0:
			return
		delta = _lod_acc
	_lod_acc = 0.0
	if pl and not rider_owned:
		_update_visual_lod(pl.global_position.distance_to(global_position))
	if rider_owned:
		var rider := _the_player(get_tree())
		if rider and rider.global_position.distance_squared_to(global_position) > RIDER_DESPAWN * RIDER_DESPAWN:
			NodePool.recycle(self)
			return
	var here := Vector2(global_position.x, global_position.z)
	var shy: float = _cfg[4]
	var player: Node3D = null
	var to_player := INF
	if shy > 0.0 or huntable:
		player = _the_player(get_tree())
		if player:
			to_player = here.distance_to(Vector2(player.global_position.x, player.global_position.z))
	if huntable:
		_update_hunt_group(to_player)
	if _stagger > 0.0:
		_stagger -= delta
		return
	if shy > 0.0 and _fleeing <= 0.0 and player:
		var notice := _notice_distance(player, shy)
		if to_player < notice:
			_flee_from(Vector2(player.global_position.x, player.global_position.z), shy * 1.6, 2.0)
		elif WARY.has(kind) and to_player < notice * ALERT_BAND:
			# Heads up: stop and watch the intruder before deciding to run.
			_pause = maxf(_pause, 0.6)
			_idle_clip = "Idle"
			var look := Vector2(player.global_position.x, player.global_position.z) - here
			rotation.y = lerp_angle(rotation.y, atan2(look.x, look.y), 1.0 - exp(-4.0 * delta))
	_fleeing -= delta
	if _fleeing <= 0.0:
		_flee_speed = 0.0
	if _pause > 0.0:
		_pause = maxf(_pause - delta, 0.0)
		if _pause == 0.0:
			_pick()
	var to := _target - here
	var distance := to.length()
	if _pause <= 0.0 and distance < 0.15:
		# Arrived: idle or graze a while.
		_pause = randf_range(2.0, 7.0)
		_idle_clip = "Eat" if randf() < 0.5 else "Idle"
	var wants_to_move := _pause <= 0.0 and distance >= 0.15
	var target_speed: float = 0.0
	if wants_to_move:
		target_speed = maxf(_cfg[2], _flee_speed) if _fleeing > 0.0 else _cfg[1]
	var response := MOVE_ACCELERATION if target_speed > _move_speed else MOVE_BRAKING
	_move_speed = move_toward(_move_speed, target_speed, response * delta)
	if _move_speed > 0.02 and distance > 0.02:
		var step_speed := minf(_move_speed, distance / maxf(delta, 0.001))
		var step := to / distance * step_speed * delta
		var p := here + step
		global_position = Vector3(p.x, WorldGen.height(p.x, p.y), p.y)
		rotation.y = lerp_angle(rotation.y, atan2(to.x, to.y), 1.0 - exp(-8.0 * delta))
		var gait := "Run" if _fleeing > 0.0 else "Walk"
		var authored_speed := float(ANIM_GROUND_SPEEDS.get(kind, {}).get(gait, 0.0))
		var rate := step_speed / authored_speed if authored_speed > 0.0 else 1.0
		_play(gait, clampf(rate, 0.35, 2.5))
	elif _move_speed <= 0.02:
		_play(_idle_clip)


func _update_visual_lod(dist: float) -> void:
	if _model == null:
		return
	var limit := (CULL_SMALL if kind in SMALL else CULL_BIG) * clampf(Quality.value("range"), 0.5, 1.0)
	var want_cull := dist > limit * 0.9 if _culled else dist > limit * 1.1
	if want_cull == _culled:
		return
	_culled = want_cull
	_model.visible = not _culled
	if _rig != null:
		var ap: AnimationPlayer = _rig.get("anim")
		if ap:
			ap.active = not _culled
	if _anim:
		_anim.active = not _culled


## Pieces whose clips are named differently (Meshy rigs, Quaternius originals) get the Idle/Walk/Run/Eat names played here.
func _alias_clips() -> void:
	var lib := _anim.get_animation_library(&"")
	if lib == null:
		return
	for want: String in CLIP_ALIASES:
		if lib.has_animation(want):
			continue
		for have: String in CLIP_ALIASES[want]:
			if lib.has_animation(have):
				lib.add_animation(want, lib.get_animation(have).duplicate())
				break


func _play(n: String, rate := 1.0) -> void:
	if _rig != null:
		if _culled:
			return
		var mps := float(ANIM_GROUND_SPEEDS.get(kind, ANIM_GROUND_SPEEDS["horse"]).get(n, 0.0)) * rate
		_rig.call("set_mode", "graze" if n == "Eat" else "")
		_rig.call("drive", mps, 0.0, 0.0)
		return
	if _anim == null or _culled:
		return
	_anim.speed_scale = rate
	if _anim.has_animation(n) and _anim.current_animation != n:
		_anim.play(n, 0.2)
	elif n == "Eat" and not _anim.has_animation("Eat") and _anim.has_animation("Idle"):
		_anim.play("Idle", 0.2)


# --- riding (mount_controller.gd) ------------------------------------------------

func rideable() -> bool:
	return kind.begins_with("horse") and not dead


## Interact prompt (HUD and player.nearest_interactable).
func prompt() -> String:
	return "Dismount" if claimed else "Ride"


## A rider takes over: no wandering, fleeing or grazing until release().
func claim() -> void:
	claimed = true
	_move_speed = 0.0
	_fleeing = 0.0


## Back to ambient life where it stands: graze a moment, then wander around here.
func release() -> void:
	claimed = false
	home = Vector2(global_position.x, global_position.z)
	_target = home
	_pause = randf_range(3.0, 6.0)
	_idle_clip = "Idle"
	_play("Idle")


## Measured ground speed (m/s at rate 1) of a gait clip, 0 when unmeasured.
func ground_speed(gait: String) -> float:
	return float(ANIM_GROUND_SPEEDS.get(kind, {}).get(gait, 0.0))


func play_gait(clip: String, rate := 1.0) -> void:
	_play(clip, rate)


# --- hunting --------------------------------------------------------------------

## How far off this animal notices the player: its skittish distance, scaled by
## player.noise_radius() when the player has it.
func _notice_distance(player: Node3D, shy: float) -> float:
	if not player.has_method("noise_radius"):
		return shy
	var loud := clampf(float(player.call("noise_radius")) / NOISE_FULL, 0.0, 1.3)
	return maxf(MIN_NOTICE, shy * loud * float(WARY.get(kind, 1.0)))


func _flee_from(from: Vector2, dist: float, seconds: float, speed := 0.0) -> void:
	var here := Vector2(global_position.x, global_position.z)
	var away := here - from
	away = away.normalized() if away.length() > 0.01 else Vector2(cos(rotation.y), sin(rotation.y))
	_target = here + away.rotated(randf_range(-0.35, 0.35)) * dist
	_fleeing = seconds
	_flee_speed = speed
	_pause = 0.0


## Game is reachable by the player's sweep (team1) only when close and, when
## player.gd exposes its swing timer, only while a swing is in the air. That
## keeps squads, followers and the battle-music check from treating a grazing
## deer as an enemy.
func _update_hunt_group(to_player: float) -> void:
	var near := to_player < HUNT_REACH
	if near:
		var player := _the_player(get_tree())
		var swing: Variant = player.get("_swing") if player else null
		if swing is float and float(swing) <= 0.0:
			near = false
	if near and not is_in_group("team1"):
		add_to_group("team1")
	elif not near and is_in_group("team1"):
		remove_from_group("team1")


## Duck-typed like Wolf.take_damage. Livestock, pets and horses are untouchable.
func take_damage(amount: int, from: Node = null, knockback := Vector3.ZERO) -> void:
	if dead or not huntable or amount <= 0:
		return
	health -= amount
	var p := global_position + Vector3(knockback.x, 0.0, knockback.z) * 0.1
	global_position = Vector3(p.x, WorldGen.height(p.x, p.z), p.z)
	if health <= 0:
		_die(from)
		return
	# Wounded: a short flinch, then bolt away from the attacker, faster than usual.
	var src := from as Node3D
	var from2 := Vector2(src.global_position.x, src.global_position.z) if src else \
		Vector2(global_position.x, global_position.z) - Vector2(sin(rotation.y), cos(rotation.y))
	_flee_from(from2, float(_cfg[3]) * 1.5 + 12.0, 4.5, float(_cfg[2]) * 1.15)
	if _anim and _anim.has_animation("Hit"):
		_stagger = 0.25
		_anim.speed_scale = 1.0
		_anim.play("Hit", 0.05)


func _die(from: Node) -> void:
	dead = true
	_move_speed = 0.0
	if is_in_group("team1"):
		remove_from_group("team1")
	if _anim and _anim.has_animation("Death"):
		_anim.speed_scale = 1.0
		_anim.play("Death", 0.1)
	else:
		# No death clip: tip over onto the side and stay there.
		if _anim:
			_anim.pause()
		var t := create_tween()
		_death_tweens.append(t)
		t.tween_property(self, "rotation:z", PI * 0.5, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	var by_player := from != null and (from.is_in_group("player") or from.is_in_group("team0"))
	if by_player:
		var got := Gathering.give_drops(Life, kind)
		Life.record("hunted")
		if got != "":
			Game.say("%s down. %s" % [kind.capitalize(), got])
	var fade := create_tween()
	_death_tweens.append(fade)
	fade.tween_interval(CORPSE_SECONDS)
	fade.tween_property(self, "scale", Vector3(1, 0.01, 1), 0.6)
	fade.tween_callback(NodePool.recycle.bind(self))
