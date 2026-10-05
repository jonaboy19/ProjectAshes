extends RefCounted
## F3 glue for the player, kept out of player.gd: attack press/release (tap = light combo, hold past the data
## hold_time = charged heavy, bow = draw and release), the equipped weapon -> move table mapping, bow arrows
## from the projectile pool with aim assist, and the player's knockdown / get-up / roll-out. The rules are pure
## and live in weapon_rules.gd and knockdown_state.gd; this class only touches the player and plays clips.
## player.gd calls: attack_press / attack_release (input), tick (each physics frame), take_forced (a heavy
## swaps into _start_swing), on_hit_taken (take_damage) and knock_dodge (dodge).

const WeaponRules := preload("res://scripts/combat/weapon_rules.gd")
const Knockdown := preload("res://scripts/combat/knockdown_state.gd")
const CombatMoves := preload("res://scripts/combat/combat_moves.gd")
const ProjectilePool := preload("res://scripts/vfx/projectile_pool.gd")
const Equipment := preload("res://scripts/sim/equipment.gd")
const ItemsDB := preload("res://scripts/sim/items_db.gd")

signal arrow_shot(info: Dictionary)
signal knocked_down(kind: String)
signal got_up(rolled: bool)
signal charge_changed(mode: String, fraction: float)

## Charge-pose clips per style [start, hold]: stand-ins from the loaded UAL sets (see the F3 report).
const CHARGE_CLIPS := {
	"sword": ["Sword_Heavy_Charge_Start", "Sword_Heavy_Charge_Hold", 0.33, 1.0],
	"spear": ["Souls_Thrust_Idle", "Souls_Thrust_Idle", 1.3, 1.3],
	"staff": ["Souls_Heavy_Idle", "Souls_Heavy_Idle", 1.3, 1.3],
}
const BOW_DRAW_CLIP_LEN := 0.53
const BOW_HOLD_CLIP_LEN := 1.15
const HEAVY_PENDING_LIFE := 0.35       ## a released heavy that could not start yet waits this long for an opening
const PRESS_BUFFER_LIFE := 6.0         ## a press (or hold) lost to a bite / knockdown waits this long for control to return

var player: Node3D
var life: Object
var kd := Knockdown.new()
var style := "sword"
var input_held := false
var held := 0.0
var charging := false
var drawing := false

var _real_input := true
var _clip_t := 0.0
var _heavy: Resource
var _heavy_life := 0.0
var _pending_press := false            # the button went down (or was held) while staggered / floored: starts when control returns
var _pending_real := true
var _pending_age := 0.0
var _charge_mult := 1.0
static var _ammo_ids := {}


func _init(p: Node3D, l: Object = null) -> void:
	player = p
	life = l if l != null else Engine.get_main_loop().root.get_node_or_null("Life")
	if life != null:
		var eq: Object = life.get("equipment")
		if eq != null and eq.has_signal("changed"):
			eq.connect("changed", _on_equipment_changed)
	if player.has_signal("swing_started"):
		player.connect("swing_started", _on_swing_started)
	sync_style()


# --- weapon type -> move table -------------------------------------------------------------------

func _on_equipment_changed(slot: String, _item: String) -> void:
	if slot == "main_hand":
		sync_style()


## combat_style follows the main-hand item's weapon_type (data/combat/player_weapons.json style_of_type).
func sync_style() -> void:
	var id := ""
	var eq: Object = life.get("equipment") if life != null else null
	if eq != null and eq.has_method("item_in"):
		id = String(eq.call("item_in", "main_hand"))
	var s := WeaponRules.style_for_item(id, Equipment.item_info(id))
	if s != style:
		cancel_hold()
	style = s
	player.set("combat_style", s)


func weapon_type() -> String:
	var eq: Object = life.get("equipment") if life != null else null
	if eq == null:
		return ""
	var id := String(eq.call("item_in", "main_hand"))
	var info := Equipment.item_info(id)
	return String(info.get("weapon_type", info.get("type", "")))


# --- input: press / release ------------------------------------------------------------------------

func press(real_input := true) -> void:
	if bool(player.get("dead")) or player.get("_mount") != null or bool(player.get("swimming")):
		return
	if kd.is_active() or _control_lost():
		_buffer_press(real_input)      # floored / staggered: remember the press, it starts when control returns
		return
	if input_held:
		return
	input_held = true
	_real_input = real_input
	held = 0.0
	charging = false
	if style == "bow":
		_begin_draw()


## Staggered by a hit or rolling: the player cannot start a swing or a charge.
func _control_lost() -> bool:
	return float(player.get("_stunned")) > 0.0 or float(player.get("_dodge")) > 0.0


## Remembers a press that could not start (not for the bow: a string drawn on its own would surprise).
func _buffer_press(real_input: bool) -> void:
	if style == "bow" or input_held:
		return
	_pending_press = true
	_pending_real = real_input
	_pending_age = 0.0


func has_pending_press() -> bool:
	return _pending_press


func release() -> void:
	if _pending_press and not input_held:
		_pending_press = false         # let go before control came back: nothing to start
		return
	if not input_held:
		return
	input_held = false
	var h := held
	held = 0.0
	if style == "bow":
		if drawing:
			fire_bow(h)
		return
	var heavy: Resource = CombatMoves.heavy(style)
	if (charging or h >= WeaponRules.hold_time()) and heavy != null:
		_stop_charge_pose()
		charging = false
		_heavy = heavy
		_heavy_life = HEAVY_PENDING_LIFE
		_charge_mult = WeaponRules.charge_mult(h)
		charge_changed.emit("", 0.0)
		player.call("attack")
		return
	charging = false
	player.call("attack")


func cancel_hold() -> void:
	_pending_press = false
	if charging:
		_stop_charge_pose()
	if drawing:
		_stop_charge_pose()
	input_held = false
	charging = false
	drawing = false
	held = 0.0
	charge_changed.emit("", 0.0)


func _stop_charge_pose() -> void:
	var anim: Object = player.get("_animator")
	if anim != null and bool(player.get("_swing") <= 0.0):
		anim.call("stop_upper")


## player.gd _start_swing: the heavy released from a charge replaces the combo step (once).
func take_forced(step: Resource) -> Resource:
	if _heavy != null:
		var h := _heavy
		_heavy = null
		player.set("_combo", 0)
		return h
	_charge_mult = 1.0
	return step


func take_charge_mult() -> float:
	var m := _charge_mult
	_charge_mult = 1.0
	return m


# --- per-frame ---------------------------------------------------------------------------------------

func tick(delta: float) -> void:
	if _heavy != null:
		_heavy_life -= delta
		if _heavy_life <= 0.0:
			_heavy = null
			_charge_mult = 1.0
	_tick_knockdown(delta)
	if _pending_press and not input_held:
		_tick_pending(delta)
		return
	if not input_held:
		return
	if bool(player.get("dead")) or kd.is_active():
		cancel_hold()
		return
	if float(player.get("_stunned")) > 0.0 or float(player.get("_dodge")) > 0.0:
		if style == "bow":
			cancel_hold()                  # the string is let down
		else:
			charging = false               # staggered / rolling: no heavy, but the press still counts as a tap
			held = 0.0
		return
	if _real_input and not Input.is_action_pressed("attack"):
		release()           # the release event was swallowed (a menu opened mid-hold)
		return
	held += delta
	if style == "bow":
		_tick_draw(delta)
		return
	if CombatMoves.heavy(style) == null:
		return
	if not charging and held >= WeaponRules.hold_time() and float(player.get("_swing")) <= 0.0:
		charging = true
		_play_charge(0)
		_clip_t = float(CHARGE_CLIPS[style][2])
	elif charging:
		_clip_t -= delta
		if _clip_t <= 0.0:
			_play_charge(1)
			_clip_t = float(CHARGE_CLIPS[style][3]) - 0.05
		charge_changed.emit("charge", WeaponRules.charge_fraction(held))


## A buffered press: drop it when the button is up, the player died, or it has waited too long; start it the moment the
## stun / knockdown / roll is over (press() then begins the hold as if the button had just gone down).
func _tick_pending(delta: float) -> void:
	_pending_age += delta
	if bool(player.get("dead")) or _pending_age > PRESS_BUFFER_LIFE \
			or (_pending_real and not Input.is_action_pressed("attack")):
		_pending_press = false
		return
	if kd.is_active() or _control_lost():
		return
	_pending_press = false
	press(_pending_real)


func _play_charge(which: int) -> void:
	var anim: Object = player.get("_animator")
	if anim != null:
		anim.call("play_upper", String((CHARGE_CLIPS.get(style, CHARGE_CLIPS["sword"]) as Array)[which]), 1.0)


# --- bow --------------------------------------------------------------------------------------------

## Best arrow stack in the pack for the equipped bow ("" = none): the strongest ammo_damage of the right ammo_type.
func ammo_id() -> String:
	if life == null:
		return ""
	var want := WeaponRules.ammo_type_for(weapon_type())
	if not _ammo_ids.has(want):
		var ids: Array = []
		for id: String in ItemsDB.ids_in_category("ammo"):
			if String(ItemsDB.info(id).get("ammo_type", "")) == want:
				ids.append(id)
		ids.sort_custom(func(a: String, b: String) -> bool:
			return float(ItemsDB.info(a).get("ammo_damage", 0)) > float(ItemsDB.info(b).get("ammo_damage", 0)))
		_ammo_ids[want] = ids
	for id: String in _ammo_ids[want]:
		if int(life.call("count", id)) > 0:
			return id
	return ""


func _begin_draw() -> void:
	if ammo_id() == "":
		input_held = false
		_say("No arrows.")
		return
	drawing = true
	var clips: Dictionary = WeaponRules.cfg("bow")["clips"]
	var anim: Object = player.get("_animator")
	if anim != null:
		anim.call("play_upper", String(clips["draw"]), 1.0)
	_clip_t = BOW_DRAW_CLIP_LEN


func _tick_draw(delta: float) -> void:
	_clip_t -= delta
	if _clip_t <= 0.0:
		var anim: Object = player.get("_animator")
		if anim != null:
			anim.call("play_upper", String(WeaponRules.cfg("bow")["clips"]["hold"]), 1.0)
		_clip_t = BOW_HOLD_CLIP_LEN
	charge_changed.emit("draw", WeaponRules.draw_fraction(held))


## Releases the string after `draw_time` seconds. {} when it could not shoot, else {damage, speed, dir, assisted, ammo}.
func fire_bow(draw_time: float) -> Dictionary:
	drawing = false
	charge_changed.emit("", 0.0)
	var ammo := ammo_id()
	if ammo == "":
		_say("No arrows.")
		return {}
	if float(player.get("stamina")) < 1.0:
		_say("Too winded to draw.")
		return {}
	var t := maxf(draw_time, 0.0)
	var weak := t < float(WeaponRules.cfg("bow")["draw_min"])
	player.call("_spend", WeaponRules.bow_stamina(t))
	life.call("take", ammo, 1)
	var eq: Object = life.get("equipment")
	var weapon_damage := float(eq.call("stats").get("damage", 0.0)) if eq != null else 0.0
	var ammo_damage := float(ItemsDB.info(ammo).get("ammo_damage", 1))
	var dmg := WeaponRules.bow_damage(weapon_damage, ammo_damage, t)
	var face := _aim_forward()
	var origin: Vector3 = (player.get("global_position") as Vector3) + Vector3(0, 1.4, 0) + face * 0.5
	var pos: Array = []
	for e in player.get_tree().get_nodes_in_group("team1"):
		var n := e as Node3D
		if n != null and not bool(n.get("dead")):
			pos.append(n.global_position)
	var lock: Variant = null
	var locked_node: Variant = player.get("_lock")
	if locked_node is Node3D and is_instance_valid(locked_node):
		lock = (locked_node as Node3D).global_position
	var aim := WeaponRules.aim_direction(origin, face, pos, lock)
	var dir: Vector3 = aim["dir"]
	var speed := WeaponRules.arrow_speed(t)
	var pool := ProjectilePool.at(player.get_parent() if player.get_parent() != null else player)
	pool.call("fire_arrow", origin, dir, speed, {"damage": dmg, "shooter": player,
		"knockback": float(WeaponRules.cfg("bow")["knockback_full"]) * WeaponRules.bow_power(t)})
	var model: Node3D = player.get("_model")
	if model != null:
		model.rotation.y = atan2(dir.x, dir.z)
	var anim: Object = player.get("_animator")
	if anim != null:
		anim.call("play_upper", String(WeaponRules.cfg("bow")["clips"]["loose"]), 1.0)
	var info := {"damage": dmg, "speed": speed, "dir": dir, "assisted": aim["assisted"], "ammo": ammo, "weak": weak, "draw": t}
	arrow_shot.emit(info)
	return info


func _aim_forward() -> Vector3:
	if int(player.get("view")) == 0:         # View.FIRST: the camera, not the body
		return player.call("forward")
	return player.call("facing")


## attack() on a bow: a tap is a quick, weak shot (no draw clip, release at once).
func bow_tap() -> bool:
	if style != "bow":
		return false
	if not drawing:
		if ammo_id() == "":
			_say("No arrows.")
			return true
		fire_bow(0.0)
	return true


# --- staff heavy: the equipped technique ---------------------------------------------------------------

func _on_swing_started(action: Resource, info: Dictionary) -> void:
	if action == null or not bool(action.get("technique")):
		return
	var timer := player.get_tree().create_timer(float(info.get("hit_t", 0.3)))
	timer.timeout.connect(_cast_equipped_technique)


func _cast_equipped_technique() -> void:
	if not is_instance_valid(player) or bool(player.get("dead")):
		return
	var caster := player.get_node_or_null("TechniqueCaster")
	if caster == null:
		return
	var sk: Variant = caster.get("skills")
	if sk == null:
		return
	var loadout: Array = (sk as Object).get("loadout")
	for slot in loadout.size():
		if String(loadout[slot]) != "":
			if bool((caster.call("can_cast_slot", slot) as Dictionary).get("ok", false)):
				caster.call("cast_slot", slot)
			return


# --- knockdown / get-up ---------------------------------------------------------------------------------

## take_damage hook: a landed blow (resolver outcome HIT / GUARD_BROKEN) cancels any hold and may floor the player.
## result is HitResolver.Outcome as int; returns the knockdown kind ("" = stayed up).
func on_hit_taken(result: int, poise_damage: float, knockback: float, from: Node) -> String:
	var was_held := input_held and style != "bow"
	var was_real := _real_input
	cancel_hold()
	if was_held:
		_buffer_press(was_real)        # still holding the button through the bite: the hold starts again when control returns
	if result != 0 and result != 3:          # HIT, GUARD_BROKEN
		return ""
	if bool(player.get("dead")) or player.get("_mount") != null or bool(player.get("swimming")):
		return ""
	var kind := kd.try_begin(poise_damage, knockback)
	if kind == "":
		return ""
	_start_fall(kind, from, knockback)
	return kind


func _start_fall(kind: String, from: Node, knockback: float) -> void:
	var k := WeaponRules.cfg("knockdown")
	player.set("_swing", 0.0)
	player.set("_swing_id", int(player.get("_swing_id")) + 1)
	player.set("_attack_buffer", 0.0)
	player.set("_dodge_buffer", 0.0)
	player.set("_stunned", Knockdown.total_time())
	var trail: Object = player.get("_trail")
	if trail != null:
		trail.call("stop")
	var anim: Object = player.get("_animator")
	var used_ragdoll := false
	if kind == "ragdoll":
		var rd: Object = player.get("_ragdoll")
		if rd != null:
			var from_pos: Vector3 = (from as Node3D).global_position if from is Node3D else Vector3.INF
			var away: Vector3 = Vector3.ZERO
			if from is Node3D:
				away = ((player.get("global_position") as Vector3) - from_pos) * Vector3(1, 0, 1)
			used_ragdoll = bool(rd.call("knock_down", away.normalized() * knockback, from_pos))
	if not used_ragdoll and anim != null:
		anim.call("play_full", String(k["clips"]["fall"]), float(k["clips"]["fall_rate"]))
	knocked_down.emit(kind)


func _tick_knockdown(delta: float) -> void:
	if bool(player.get("dead")):
		if kd.is_active():
			kd.reset()
		return
	var ev := kd.tick(delta)
	if kd.iframes > 0.0:
		player.set("_invulnerable", maxf(float(player.get("_invulnerable")), kd.iframes))
	match ev:
		"down":
			if kd.take_queued_roll():
				_roll_out()
		"getup":
			var k := WeaponRules.cfg("knockdown")
			var anim: Object = player.get("_animator")
			if anim != null:
				anim.call("play_full", String(k["clips"]["getup"]), float(k["clips"]["getup_rate"]))
		"done":
			got_up.emit(false)


## dodge(): while floored the press is ours. True = handled (the normal dodge must not run).
func knock_dodge() -> bool:
	if not kd.is_down():
		return false
	var need := float((player.get_script() as GDScript).get_script_constant_map().get("DODGE_STAMINA", 15.0))
	if float(player.get("stamina")) < need:
		return true
	if kd.dodge_pressed() == "roll":
		_roll_out()
	return true


func _roll_out() -> void:
	player.set("_stunned", 0.0)
	player.call("_start_dodge", false)
	player.set("_invulnerable", maxf(float(player.get("_invulnerable")), kd.iframes))
	got_up.emit(true)


func _say(text: String) -> void:
	var g: Object = Engine.get_main_loop().root.get_node_or_null("Game")
	if g != null and g.has_method("say"):
		g.call("say", text)
