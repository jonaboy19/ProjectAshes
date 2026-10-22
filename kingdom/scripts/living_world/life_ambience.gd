class_name LifeAmbience
extends RefCounted
## Ambient behaviour variety for villagers: personality, idle fidgets, cheap glances (at the player, at nearby
## events, at a chat partner), weather and time-of-day reactions. One instance per embodied person; it only
## DECIDES (clip names, a look target); the body plays them. Cost: one update() per think tick (~0.3 s), a few
## comparisons, no allocation.
##
##   var amb := LifeAmbience.new(person_id, is_child, age01)
##   var d := amb.think(dt_since_last, ctx)   # ctx: {idle, walking, pos, fwd, hour, weather, player_pos, partner_pos}
##   d.fidget      -> one-shot clip to play now over the idle ("" = none)
##   d.look        -> Vector3 world point for the head (or null = look ahead)
##   d.walk        -> the walk clip for this person in this weather / mood
##   d.upper       -> an upper-body layer clip to composite over locomotion ("" = none), e.g. the rain hunch
##   d.pace        -> walk speed multiplier (rain hurries people)
## LivingEvents.emit("clang", pos, 14.0) anywhere (anvil strike, cart, shout, the player sprinting past)
## makes people in range glance at it.

## Stable per-person traits from the id (no RNG state, same person = same traits every visit).
var person := 0
var child := false
var walk_speed := 1.0      # x WALK speed
var anim_rate := 1.0       # playback rate of loops (no two people in sync)
var height := 1.0          # x standing height
var gesture := 1.0         # amplitude bias (pick emphatic vs calm talk clips)
var curiosity := 0.5       # chance to glance at the player / events
var restless := 0.5        # fidget frequency
var mood := 0.5            # 0 gloomy .. 1 cheerful: walk style, laughs
var walk_style := "Walk"

var _fidget_t := 5.0
var _look_t := 0.0
var _look: Variant = null
var _cool := 0.0
var _last_event := -1


func _init(id: int, is_child := false, age01 := 0.4) -> void:
	person = id
	child = is_child
	walk_speed = 0.88 + 0.24 * _h(1)
	anim_rate = 0.93 + 0.14 * _h(2)
	height = 0.95 + 0.10 * _h(3)
	gesture = 0.8 + 0.4 * _h(4)
	curiosity = 0.25 + 0.6 * _h(5)
	restless = 0.2 + 0.8 * _h(6)
	mood = _h(7)
	if is_child:
		walk_style = "Life_Kid_Skip" if mood > 0.75 else "Walk"
		walk_speed *= 1.15
	elif age01 > 0.75:
		walk_style = "Life_Walk_Cane" if _h(8) > 0.5 else "Life_Walk_Elder"
		walk_speed *= 0.72
	elif mood > 0.8:
		walk_style = "Life_Walk_Happy"
	elif mood < 0.12:
		walk_style = "Life_Walk_Sad"
	elif restless > 0.85:
		walk_style = "Life_Walk_Brisk"
	_fidget_t = 3.0 + 10.0 * _h(9)


func _h(k: int) -> float:
	return float(absi(hash(person * 92821 + k * 68917)) % 10000) / 10000.0


## ctx keys: idle (bool: standing without an activity), walking, pos (Vector3), fwd (Vector3), hour (0-24),
## weather ("clear" | "rain" | "hot" | "cold"), player_pos (Vector3 or null), partner_pos (Vector3 or null), tired (bool)
func think(dt: float, ctx: Dictionary) -> Dictionary:
	var out := {"fidget": "", "look": null, "walk": walk_style, "upper": "", "pace": 1.0}
	var weather := String(ctx.get("weather", "clear"))
	var hour := float(ctx.get("hour", 12.0))
	var pos: Vector3 = ctx.get("pos", Vector3.ZERO)
	var fwd: Vector3 = ctx.get("fwd", Vector3.FORWARD)
	# weather / time of day
	if weather == "rain":
		out["upper"] = "Life_Ambient_Rain_Hunch_Upper"
		out["pace"] = 1.3
		out["walk"] = "Walk" if child else "Life_Walk_Brisk"
	elif ctx.get("tired", false) or (hour >= 21.0 or hour < 5.0):
		if not child and walk_style == "Walk":
			out["walk"] = "Life_Walk_Tired"
		out["pace"] = 0.9
	# glances: events first, then the player, then the partner
	_cool = maxf(_cool - dt, 0.0)
	_look_t = maxf(_look_t - dt, 0.0)
	if _look_t <= 0.0:
		_look = null
	if _cool <= 0.0:
		var ev := LivingEvents.nearest(pos, _last_event)
		if not ev.is_empty() and _h(20 + int(ev["serial"]) % 7) < curiosity + 0.3:
			_last_event = int(ev["serial"])
			_look = (ev["pos"] as Vector3) + Vector3(0, 1.0, 0)
			_look_t = 1.2 + curiosity
			_cool = 2.5
		elif ctx.get("player_pos") != null:
			var pp: Vector3 = ctx["player_pos"]
			var to := pp - pos
			var d := to.length()
			if d < 7.0 and d > 0.3 and fwd.dot(to / d) > -0.3 and _h(40 + int(Time.get_ticks_msec() / 4000)) < curiosity:
				_look = pp + Vector3(0, 1.55, 0)
				_look_t = 2.0 + 2.0 * curiosity
				_cool = 4.0 + 6.0 * (1.0 - curiosity)
	if _look == null and ctx.get("partner_pos") != null:
		out["look"] = (ctx["partner_pos"] as Vector3) + Vector3(0, 1.5, 0)
	else:
		out["look"] = _look
	# fidgets only while idle and not in the rain (people hurry instead)
	if ctx.get("idle", false) and weather != "rain":
		_fidget_t -= dt
		if _fidget_t <= 0.0:
			_fidget_t = lerpf(14.0, 5.0, restless) * (0.7 + 0.6 * _h(60 + int(Time.get_ticks_msec() / 1000) % 13))
			out["fidget"] = _pick_fidget(hour, weather)
	return out


func _pick_fidget(hour: float, weather: String) -> String:
	var pool: Array = []
	if child:
		pool = ["Life_Kid_Clap_Jump", "Life_Ambient_Look_Around", "Life_Ambient_Scratch_Head"]
	else:
		pool = ["Life_Ambient_Look_Around", "Life_Ambient_Shift_Weight", "Life_Ambient_Scratch_Head", "Life_Ambient_Check_Sky"]
		if hour >= 5.5 and hour < 9.0:
			pool.append_array(["Life_Ambient_Stretch_Morning", "Life_Ambient_Stretch_Morning", "Life_Mocap_Stretch_Yawn"])
		elif hour >= 20.0 or hour < 2.0:
			pool.append_array(["Life_Ambient_Yawn", "Life_Ambient_Yawn"])
		if weather == "hot" or (weather == "clear" and hour >= 11.0 and hour < 16.0):
			pool.append_array(["Life_Ambient_Shade_Eyes", "Life_Ambient_Wipe_Brow"])
		elif weather == "cold":
			pool.append_array(["Life_Ambient_Rub_Arms", "Life_Ambient_Rub_Arms", "Life_Mocap_Cold"])
	var k := absi(hash(person * 31 + int(Time.get_ticks_msec() / 997))) % pool.size()
	return pool[k]


## Talk clip for a conversation turn, biased by temperament.
func talk_clip(speaking: bool, turn: int) -> String:
	var k := absi(hash(person * 13 + turn))
	if speaking:
		var s := ["Life_Talk_Casual", "Life_Talk_Explain", "Life_Talk_Gossip", "Life_Talk_Emphatic"]
		return s[mini(k % 3 + (1 if gesture > 1.1 else 0), 3)]
	var l := ["Life_Talk_Listen_Nod", "Life_Talk_Listen_Hips", "Idle_Listening"]
	return l[k % 3]
