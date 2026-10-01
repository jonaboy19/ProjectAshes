extends Node3D
## One extra body of a micro event (scripts/population/micro_events.gd): a person, an animal, a cart with its
## horse, or a bare prop. It owns no schedule and no AI: the scene queues small actions and this node plays
## them one after another (wait, walk a path, play a clip, say a line, call back, leave).
##
## People use the same models and animation libraries as villagers (Assets.character + LifeLibrary), so they
## look and move like everyone else; carrying uses LifeLibrary.composite (walk legs + a carry upper body) and
## LifeProps for the held thing. Animals use the Critter models. A vehicle is a root node that moves while its
## parts (cart prop, draught animal) ride along; it sits in group "vehicle", so NpcWorld.mover_push makes
## villagers step out of its way.
##
## Cost: the model is built lazily, at most one per frame across all actors (a scene with eight people
## appears over eight frames instead of one hitch); afterwards one _process doing a few vector ops. Skinned
## animation is the engine's. Actors are capped by the director (about 10 at once) and freed with their scene.

const NpcWorld := preload("res://scripts/population/npc_world.gd")

const WALK_SPEED_BASE := 0.98     # measured ground speed of Walking_A (villager.gd WALK_CLIP_SPEED)
const RUN_SPEED_BASE := 5.82
const TURN_RATE := 5.0
const BUBBLE_SECONDS := 3.4
## An actor this far from the camera for a while is freed (its scene notices and ends when all are gone).
const CULL_DIST := 95.0

static var _build_frame := -1

var kind := "human"                # human | animal | vehicle | prop
var scene: Node                    # the MicroScene that owns this actor (bookkeeping only)
var anim: AnimationPlayer
var skeleton: Skeleton3D
var animal_kind := ""
var child := false
var speed_now := 0.0               # current ground speed (m/s)
var done := false
var built := false

var _spec := {}
var _q: Array = []
var _cur: Dictionary = {}
var _t := 0.0
var _path := PackedVector2Array()
var _pi := 0
var _heading := 0.0
var _clip := ""
var _props: LifeProps.Holder
var _part_anims: Array = []        # [AnimationPlayer, animal kind] riding on a vehicle
var _bubble: Label3D
var _bubble_until := 0
var _face_to := Vector2.INF
var _age := 0.0
var _far_t := 3.0


# ================================================================ construction (the model comes later)
static func _make(k: String, spec: Dictionary, at: Vector2, yaw: float) -> Node3D:
	var a := (load("res://scripts/population/micro_actor.gd") as GDScript).new() as Node3D
	a.set("kind", k)
	a.set("_spec", spec)
	a.set("_heading", yaw)
	a.position = Vector3(at.x, WorldGen.height(at.x, at.y), at.y)
	a.rotation.y = yaw
	return a


static func human(look: String, height: float, at: Vector2, yaw := 0.0) -> Node3D:
	return _make("human", {"look": look, "h": height}, at, yaw)


static func animal(animal_kind_name: String, at: Vector2, yaw := 0.0, scale := 1.0) -> Node3D:
	return _make("animal", {"animal": animal_kind_name, "scale": scale}, at, yaw)


## A vehicle root: `body` is the building key of the cart/wagon prop; draught animals (kind names) stand ahead.
static func vehicle(body: String, animals: Array, at: Vector2, yaw := 0.0, hitch := 2.4) -> Node3D:
	return _make("vehicle", {"body": body, "animals": animals, "hitch": hitch}, at, yaw)


## A prop that moves or stands: `body` is a building key (Assets.building_node) or a Callable returning a Node3D.
static func prop(body: Variant, at: Vector2, yaw := 0.0) -> Node3D:
	return _make("prop", {"body": body}, at, yaw)


func _build() -> void:
	built = true
	match kind:
		"human":
			var model := Assets.character(String(_spec["look"]), float(_spec["h"]), [])
			add_child(model)
			anim = Assets.animation_player(model)
			if anim != null:
				LifeLibrary.install(anim)
			var sk := model.find_children("*", "Skeleton3D", true, false)
			if not sk.is_empty():
				skeleton = sk[0] as Skeleton3D
				_props = LifeProps.Holder.new(skeleton)
			child = float(_spec["h"]) < 1.5
			_play_idle()
		"animal":
			var model2 := _animal_model(String(_spec["animal"]), float(_spec["scale"]))
			if model2 != null:
				add_child(model2)
				anim = Assets.animation_player(model2)
				animal_kind = String(_spec["animal"])
				_play_idle()
		"vehicle":
			var body := Assets.building_node(String(_spec["body"]), false)
			if body != null:
				add_child(body)
			var k := 0
			var animals: Array = _spec["animals"]
			for ak: String in animals:
				var h := _animal_model(ak, 1.0)
				if h == null:
					continue
				var lateral := (float(k) - float(animals.size() - 1) * 0.5) * 1.1
				h.position = Vector3(lateral, 0.0, float(_spec["hitch"]))
				add_child(h)
				_part_anims.append([Assets.animation_player(h), ak])
				k += 1
			_apply_part_anims(speed_now)
		"prop":
			var b: Variant = _spec["body"]
			var node: Node3D = (b as Callable).call() if b is Callable else Assets.building_node(String(b), false)
			if node != null:
				add_child(node)
	if scene != null and scene.has_method("on_actor_built"):
		scene.call("on_actor_built", self)


static func _animal_model(animal_kind_name: String, scale: float) -> Node3D:
	var critter: GDScript = load("res://scripts/actors/critter.gd")
	var kinds: Dictionary = critter.get("KINDS")
	if not kinds.has(animal_kind_name):
		return null
	var path := String((kinds[animal_kind_name] as Array)[0])
	if not path.begins_with("res://"):
		path = String(critter.get("DIR")) + path
	if not ResourceLoader.exists(path):
		return null
	var model: Node3D = Assets.scene(path).instantiate()
	model.scale = Vector3.ONE * scale
	var ap := Assets.animation_player(model)
	if ap != null:
		for n in ["Idle", "Walk", "Run", "Eat", "Walk_Slow"]:
			if ap.has_animation(n):
				ap.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	return model


# ================================================================ the action queue
func wait(seconds: float) -> Node3D:
	_q.append({"a": "wait", "t": seconds})
	return self


## Walk `path` at `speed` m/s with a walk clip ("Walking_A", "Running_A", "Life_Walk_Drunk" ...), optionally with
## an upper-body carry clip layered over the legs ("Life_Carry_Crate_Upper": its props are held too).
func walk(path: PackedVector2Array, speed := 1.15, clip := "Walking_A", upper := "") -> Node3D:
	_q.append({"a": "walk", "path": path, "speed": speed, "clip": clip, "upper": upper})
	return self


## Play `clips` (a clip name or an Array of candidates, first the rig has wins) for `seconds`, turned towards a point.
func play(clips: Variant, seconds: float, face_at := Vector2.INF) -> Node3D:
	_q.append({"a": "play", "clips": clips, "t": seconds, "face": face_at})
	return self


func say(text: String, seconds := BUBBLE_SECONDS) -> Node3D:
	_q.append({"a": "say", "text": text, "t": seconds})
	return self


func call_later(c: Callable) -> Node3D:
	_q.append({"a": "call", "c": c})
	return self


func face(p: Vector2) -> Node3D:
	_q.append({"a": "face", "p": p})
	return self


## Hold the props `list` ([{id, hand}], LifeProps) from now on ([] puts them away).
func hold(list: Array) -> Node3D:
	_q.append({"a": "hold", "l": list})
	return self


## Walk away along `path` and disappear.
func leave(path: PackedVector2Array, speed := 1.15, clip := "Walking_A") -> Node3D:
	_q.append({"a": "walk", "path": path, "speed": speed, "clip": clip, "upper": ""})
	_q.append({"a": "free"})
	return self


func vanish() -> Node3D:
	_q.append({"a": "free"})
	return self


func idle_now() -> bool:
	return _cur.is_empty() and _q.is_empty()


func clear_queue() -> void:
	_q.clear()
	_cur = {}
	_path = PackedVector2Array()
	speed_now = 0.0


## Where on the ground this actor stands.
func xz() -> Vector2:
	return Vector2(global_position.x, global_position.z)


# ================================================================ playing
func _ready() -> void:
	if kind == "vehicle":
		add_to_group("vehicle")


func _process(delta: float) -> void:
	if NpcWorld.profile:
		var t0 := Time.get_ticks_usec()
		_tick(delta)
		NpcWorld.prof_frame_usec += Time.get_ticks_usec() - t0
	else:
		_tick(delta)


func _tick(delta: float) -> void:
	if not built:
		var frame := Engine.get_process_frames()
		if frame == _build_frame:
			return           # another actor was built this frame: wait for the next one
		_build_frame = frame
		_build()
	if _bubble != null and _bubble.visible and Time.get_ticks_msec() >= _bubble_until:
		_bubble.visible = false
		NpcWorld.bubbles_shown = maxi(NpcWorld.bubbles_shown - 1, 0)
	_age += delta
	_far_t -= delta
	if _far_t <= 0.0:
		# Out of sight, out of mind: an actor far behind the player (a cart that walked on) is freed.
		_far_t = 1.5
		var cam := get_viewport().get_camera_3d()
		if cam != null and _age > 10.0 and cam.global_position.distance_squared_to(global_position) > CULL_DIST * CULL_DIST:
			done = true
			queue_free()
			return
	if _cur.is_empty():
		if _q.is_empty():
			speed_now = 0.0
			_face_step(delta)
			return
		_cur = _q.pop_front()
		_start(_cur)
		if _cur.is_empty():
			return
	match String(_cur["a"]):
		"wait", "play":
			_t -= delta
			_face_step(delta)
			if _t <= 0.0:
				_cur = {}
		"walk":
			_walk_step(delta)
		_:
			_cur = {}


func _start(a: Dictionary) -> void:
	match String(a["a"]):
		"wait":
			_t = float(a["t"])
			_face_to = Vector2.INF
			_play_idle()
		"play":
			_t = float(a["t"])
			_face_to = a["face"]
			var clip := _first_clip(a["clips"])
			if clip == "":
				_play_idle()
			else:
				_play_clip(clip, 1.0)
				if _props != null:
					var info: Dictionary = LifeLibrary.info(clip)
					var pr: Array = info.get("props", [])
					if not pr.is_empty():
						_props.show_props(pr)
		"walk":
			_path = a["path"]
			_pi = 0
			_face_to = Vector2.INF
			var speed := float(a["speed"])
			var clip2 := String(a["clip"])
			var upper := String(a["upper"])
			if kind == "animal" or kind == "vehicle":
				clip2 = "Run" if speed > 3.0 else "Walk"
			else:
				clip2 = _first_clip(clip2)
				if upper != "" and anim != null:
					clip2 = LifeLibrary.composite(anim, clip2, upper)
					if _props != null:
						_props.show_props(LifeLibrary.info(upper).get("props", []))
			_play_clip(clip2, clampf(speed / maxf(_ground_speed(clip2), 0.05), 0.3, 2.4))
			_apply_part_anims(speed)
			if _path.is_empty():
				_cur = {}
		"say":
			_say(String(a["text"]), float(a["t"]))
			_cur = {}
		"call":
			var c: Callable = a["c"]
			if c.is_valid():
				c.call()
			_cur = {}
		"face":
			_face_to = a["p"]
			_cur = {}
		"hold":
			if _props != null:
				if (a["l"] as Array).is_empty():
					_props.clear()
				else:
					_props.show_props(a["l"])
			_cur = {}
		"free":
			done = true
			queue_free()
			_cur = {}
		_:
			_cur = {}


func _walk_step(delta: float) -> void:
	if _pi >= _path.size():
		_cur = {}
		speed_now = 0.0
		_play_idle()
		_apply_part_anims(0.0)
		return
	var here := Vector2(global_position.x, global_position.z)
	var to := _path[_pi] - here
	var d := to.length()
	if d < 0.35:
		_pi += 1
		return
	_heading = lerp_angle(_heading, atan2(to.x, to.y), clampf(TURN_RATE * delta, 0.0, 1.0))
	var speed := float(_cur["speed"])
	var move := to / d * minf(speed * delta, d)
	global_position += Vector3(move.x, 0.0, move.y)
	global_position.y = WorldGen.height(global_position.x, global_position.z)
	rotation.y = _heading
	speed_now = speed


func _face_step(delta: float) -> void:
	if _face_to == Vector2.INF:
		return
	var to := _face_to - Vector2(global_position.x, global_position.z)
	if to.length_squared() < 0.01:
		return
	_heading = lerp_angle(_heading, atan2(to.x, to.y), clampf(TURN_RATE * delta, 0.0, 1.0))
	rotation.y = _heading


func _play_idle() -> void:
	if anim == null:
		return
	var clip := "Idle" if anim.has_animation("Idle") else ("Idle_Loop" if anim.has_animation("Idle_Loop") else "")
	if clip != "":
		_play_clip(clip, 1.0)
	if _props != null and kind == "human" and _cur.is_empty():
		pass


func _play_clip(clip: String, rate: float) -> void:
	if anim == null or clip == "" or not anim.has_animation(clip):
		return
	if _clip != clip or not anim.is_playing():
		anim.play(clip, 0.25)
		_clip = clip
		var length := anim.current_animation_length
		if length > 0.0:
			anim.seek(fmod(float(get_instance_id() % 97) * 0.0618, 1.0) * length)
	anim.speed_scale = rate


func _apply_part_anims(speed: float) -> void:
	for pa: Array in _part_anims:
		var ap := pa[0] as AnimationPlayer
		if ap == null:
			continue
		var clip := ("Run" if speed > 3.0 else "Walk") if speed > 0.05 else "Idle"
		if ap.has_animation(clip):
			if ap.current_animation != clip:
				ap.play(clip, 0.25)
			ap.speed_scale = clampf(speed / _animal_speed(String(pa[1]), clip), 0.3, 2.0) if speed > 0.05 else 1.0


static func _animal_speed(animal_name: String, clip: String) -> float:
	var table: Dictionary = (load("res://scripts/actors/critter.gd") as GDScript).get("ANIM_GROUND_SPEEDS")
	var sp: Dictionary = table.get(animal_name, {})
	return float(sp.get(clip, 1.3 if clip == "Walk" else 5.0))


func _ground_speed(clip: String) -> float:
	if kind == "animal":
		return _animal_speed(animal_kind, clip)
	if kind == "vehicle":
		return 1.4
	var base := clip.split("+")[0]
	if base == "Walking_A" or base == "Walk":
		return WALK_SPEED_BASE
	if base == "Running_A":
		return RUN_SPEED_BASE
	var sp := float(LifeLibrary.info(base).get("speed_mps", 0.0))
	return sp if sp > 0.05 else WALK_SPEED_BASE


func _first_clip(clips: Variant) -> String:
	if anim == null:
		return ""
	if clips is String:
		return clips if anim.has_animation(clips) else ""
	for n: String in clips:
		if anim.has_animation(n):
			return n
	return ""


func _say(text: String, seconds: float) -> void:
	if text == "" or kind != "human":
		return
	var showing := _bubble != null and _bubble.visible
	if not showing and NpcWorld.bubbles_shown >= NpcWorld.MAX_BUBBLES:
		return
	if _bubble == null:
		_bubble = Label3D.new()
		_bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_bubble.double_sided = true
		_bubble.pixel_size = 0.0042
		_bubble.font_size = 34
		_bubble.outline_size = 10
		_bubble.modulate = Color(1.0, 0.96, 0.82)
		_bubble.outline_modulate = Color(0.08, 0.06, 0.05, 0.95)
		_bubble.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_bubble.width = 360.0
		_bubble.position.y = 2.25 if not child else 1.85
		_bubble.visible = false
		add_child(_bubble)
	_bubble.text = text
	if not showing:
		NpcWorld.bubbles_shown += 1
		_bubble.visible = true
	_bubble_until = Time.get_ticks_msec() + int(seconds * 1000.0)


func _exit_tree() -> void:
	if _bubble != null and _bubble.visible:
		NpcWorld.bubbles_shown = maxi(NpcWorld.bubbles_shown - 1, 0)
	if _props != null:
		_props.clear()
