class_name Region1TutorialBridge
extends Node
## Hook C8: connects the tutorial director (tutorial_director.gd) to the running game
## without editing hot files beyond the 3-line hook in main.gd (docs/regions/HOOKS_FOR_CLOUD.md).
##
## Every frame it
##   * builds the director's context from the player, HUD, Life needs and nearby things;
##   * detects the real actions by polling Input actions (keyboard and the HUD's
##     TouchScreenButtons both press them) and by watching state change (food and rest go up =
##     ate / slept; the camera yaw turns = looked; the player moves = walked);
##   * places prompts on the real HUD buttons.
## Other systems report their own actions with Region1TutorialDirector.tell(&"carve") etc.
## Duck-typed on purpose (get()/has_method()), so it loads in the sparse test project too.
##
##   var tut := Region1TutorialBridge.new()
##   add_child(tut)
##   tut.setup(player, hud)
##
## Optional context providers (set by the systems that know the answer; each is a
## Callable(player_pos: Vector3) -> bool): near_dim_stone (C3), near_ash_site (C6),
## new_marker (C7), knows_glyph (C7: story flag r1.a1.taught).

var director: Region1TutorialDirector
var view: Region1TutorialPromptView
var player: Node3D
var hud: Node
var providers: Dictionary = {}     # context key -> Callable(Vector3) -> bool
var _last_food := -1.0
var _last_rest := -1.0
var _last_yaw := INF
var _anchor_timer := 0.0
var _ctx_acc := 0.0
var _life: Node
## CPU pass 2026-10-06: the context (interaction picker, group scans, providers) is built at this rate, not every frame;
## the director gets the summed delta, so its timers are unchanged and a prompt shows at most this late.
const CTX_RATE := 0.15


func setup(p_player: Node3D, p_hud: Node) -> Region1TutorialBridge:
	player = p_player
	hud = p_hud
	director = Region1TutorialDirector.new().make_main()
	director.register_save()
	view = Region1TutorialPromptView.new()
	view.name = "TutorialPrompts"
	hud.add_child(view)
	view.bind(director)
	return self


func _exit_tree() -> void:
	if Region1TutorialDirector.main == director:
		Region1TutorialDirector.main = null


func _process(delta: float) -> void:
	if director == null or not is_instance_valid(player):
		return
	_detect_actions(delta)
	_ctx_acc += delta
	if _ctx_acc < CTX_RATE:
		return
	var step := _ctx_acc
	_ctx_acc = 0.0
	# Nothing left to teach (all done / skipped / switched off): no context to build at all.
	if not director.enabled or (director.current == &"" and director.pending().is_empty()):
		return
	director.update(context(), step)
	_anchor_timer -= step
	if _anchor_timer <= 0.0:
		_anchor_timer = 1.0
		_place_anchors()


## The context dictionary the director reads (see tutorial_director.gd).
func context() -> Dictionary:
	var ctx := {}
	var menu_open := hud != null and hud.has_method("is_menu_open") and bool(hud.is_menu_open())
	var dead := bool(player.get("dead")) if "dead" in player else false
	ctx["blocked"] = menu_open or get_tree().paused or _cutscene_playing()
	ctx["can_control"] = not dead and not ctx["blocked"]
	ctx["touch"] = DisplayServer.is_touchscreen_available()
	var near: Node = player.nearest_interactable() if player.has_method("nearest_interactable") else null
	ctx["near_npc"] = near != null and near.is_in_group("villager")
	ctx["near_bed"] = near != null and String(near.get("verb") if "verb" in near else "") == "Sleep"
	ctx["near_interactable"] = near != null and not ctx["near_npc"] and not ctx["near_bed"]
	var life := get_node_or_null("/root/Life")
	if life != null and life.get("needs") != null:
		ctx["food"] = float(life.needs.food)
		ctx["rest"] = float(life.needs.rest)
		ctx["has_food"] = life.has_method("best_food") and String(life.best_food()) != ""
	var ws := get_node_or_null("/root/WorldSim")
	if ws != null:
		var t := float(ws.get("time_of_day"))
		ctx["is_night"] = t < 5.5 or t >= 21.0
	var here := player.global_position
	var enemy := _nearest_enemy(here, 9.0)
	ctx["enemy_near"] = enemy != null
	ctx["enemy_winding_up"] = enemy != null and _winding_up(enemy)
	for k: String in providers:
		var cb: Callable = providers[k]
		ctx[k] = cb.is_valid() and bool(cb.call(here))
	return ctx


func _detect_actions(delta: float) -> void:
	# Walking: real ground speed, in seconds.
	var v: Vector3 = player.get("velocity") if "velocity" in player else Vector3.ZERO
	if Vector2(v.x, v.z).length() > 0.8:
		director.notify(&"move", delta)
	# Looking: camera yaw turned (radians count as "seconds" of looking).
	var cam: Node3D = player.get("camera") if "camera" in player else null
	if cam != null and is_instance_valid(cam):
		var yaw := cam.global_rotation.y
		if _last_yaw != INF:
			var d := absf(wrapf(yaw - _last_yaw, -PI, PI))
			if d > 0.002 and d < 1.0:
				director.notify(&"look", d)
		_last_yaw = yaw
	# Buttons (keys and HUD TouchScreenButtons press the same actions).
	if Input.is_action_just_pressed("attack"):
		director.notify(&"attack")
	if Input.is_action_just_pressed("dodge"):
		director.notify(&"dodge")
	if Input.is_action_just_pressed("block"):
		director.notify(&"block")
	if Input.is_action_just_pressed("journal"):
		director.notify(&"map")
	if Input.is_action_just_pressed("interact"):
		var near: Node = player.nearest_interactable() if player.has_method("nearest_interactable") else null
		if near != null:
			director.notify(&"talk" if near.is_in_group("villager") else &"interact")
	# Eating and sleeping: whatever path the player used (key, menu, bed station).
	if _life == null or not is_instance_valid(_life):
		_life = get_node_or_null("/root/Life")
	var life := _life
	if life != null and life.get("needs") != null:
		var food := float(life.needs.food)
		var rest := float(life.needs.rest)
		if _last_food >= 0.0 and food > _last_food + 4.0:
			director.notify(&"eat")
		if _last_rest >= 0.0 and rest > _last_rest + 10.0:
			director.notify(&"sleep")
		_last_food = food
		_last_rest = rest


func _nearest_enemy(here: Vector3, radius: float) -> Node3D:
	var best: Node3D = null
	var best_d := radius
	for n in get_tree().get_nodes_in_group("team1"):
		if not (n is Node3D) or not is_instance_valid(n):
			continue
		if "dead" in n and bool(n.get("dead")):
			continue
		var d := here.distance_to((n as Node3D).global_position)
		if d < best_d:
			best_d = d
			best = n
	return best


func _winding_up(e: Node) -> bool:
	if e.has_method("is_winding_up"):
		return bool(e.is_winding_up())
	return "_winding" in e and float(e.get("_winding")) > 0.0   # wolf.gd today


func _cutscene_playing() -> bool:
	for n in get_tree().get_nodes_in_group("cutscene_active"):   # cutscene_player.gd play()
		if "playing" in n and bool(n.get("playing")):
			return true
	return false


## Point prompts at the real HUD buttons (hud._buttons: action -> TouchScreenButton).
func _place_anchors() -> void:
	if hud == null or view == null:
		return
	var buttons: Variant = hud.get("_buttons")
	if not (buttons is Dictionary):
		return
	for pair: Array in [["attack", &"btn_attack"], ["block", &"btn_block"], ["dodge", &"btn_dodge"],
			["interact", &"btn_interact"], ["eat", &"btn_eat"], ["journal", &"btn_map"]]:
		var b: Variant = (buttons as Dictionary).get(pair[0])
		if b is TouchScreenButton and (b as TouchScreenButton).is_visible_in_tree():
			var tb := b as TouchScreenButton
			var sz := tb.texture_normal.get_size() * tb.global_scale if tb.texture_normal else Vector2.ZERO
			view.set_hud_anchor(pair[1], tb.global_position + sz * 0.5)
