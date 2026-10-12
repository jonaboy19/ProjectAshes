extends RefCounted
## Pure face logic shared by the hero (shader uniforms) and the villager FaceCard (instance uniforms). No scene access.
## Inputs: set_mood(name), say(seconds) / say_loop(on); step(dt) -> {brow, lids, mouth_open, mouth_curve}.
## brow: + raised / - lowered (inner-down); lids: + half-closed (squint), - wide open, blink forces 1.0; mouth_curve: + smile / - frown.
## docs/art/FACES.md

## UtilityBrain.Act values (a test pins them, so this script stays loadable without the sim autoloads).
const A_INN := 6
const A_FLEE := 10
const A_PROTEST := 17
const A_ALARM := 18
const A_MOURN := 22
const A_FESTIVE := 23

const MOODS := ["neutral", "happy", "sad", "angry", "fear", "surprise"]
## mood -> [brow, lids, mouth_curve]
const TABLE := {
	"neutral": [0.0, 0.0, 0.0],
	"happy": [0.35, 0.15, 0.8],
	"sad": [-0.25, 0.35, -0.7],
	"angry": [-0.8, 0.45, -0.4],
	"fear": [0.6, -0.2, -0.3],
	"surprise": [0.9, -0.4, 0.2],
}
## resting mouth opening per mood (fear / surprise show an open mouth; speech flaps on top)
const MOUTH_OPEN := {"fear": 0.3, "surprise": 0.6}
const BLINK_TIME := 0.28
const EASE_SPEED := 5.0          # units per second: a full swing (<= 1.3) settles in 0.26 s

var mood := "neutral"
var brow := 0.0
var lids := 0.0
var curve := 0.0
var open := 0.0
var _blink_t := 2.0
var _blink_ph := -1.0
var _double := false
var _say_left := 0.0
var _loop := false
var _flap_ph := 0.0


func _init() -> void:
	_blink_t = randf_range(1.0, 3.0)


func set_mood(m: String) -> void:
	mood = m if TABLE.has(m) else "neutral"


func say(seconds: float) -> void:
	_say_left = maxf(seconds, 0.0)


func say_loop(on: bool) -> void:
	_loop = on


func is_talking() -> bool:
	return _loop or _say_left > 0.0


## Forces the blink to a phase 0..1 (QA).
func force_blink(phase: float) -> void:
	_blink_ph = clampf(phase, 0.0, 1.0)
	_blink_t = 99.0


func step(dt: float) -> Dictionary:
	var t: Array = TABLE[mood]
	var d := EASE_SPEED * dt
	brow = move_toward(brow, t[0], d)
	lids = move_toward(lids, t[1], d)
	curve = move_toward(curve, t[2], d)
	open = move_toward(open, float(MOUTH_OPEN.get(mood, 0.0)), d)
	if _blink_ph < 0.0:
		_blink_t -= dt
		if _blink_t <= 0.0:
			_blink_ph = 0.0
	if _blink_ph >= 0.0 and _blink_t < 90.0:
		_blink_ph += dt / BLINK_TIME
		if _blink_ph >= 1.0:
			_blink_ph = -1.0
			_double = not _double and randf() < 0.2
			_blink_t = 0.12 if _double else randf_range(2.0, 6.0)
	var l := lids
	if _blink_ph >= 0.0:
		l = maxf(lids, clampf((1.0 - absf(_blink_ph * 2.0 - 1.0)) * 2.0, 0.0, 1.0))
	var flap := open
	if _say_left > 0.0 or _loop:
		_say_left = maxf(_say_left - dt, 0.0)
		_flap_ph += dt * randf_range(6.0, 9.0) * TAU
		flap = maxf(open, (sin(_flap_ph) * 0.5 + 0.5) * 0.7)
	return {"brow": brow, "lids": l, "mouth_open": flap, "mouth_curve": curve}


static func say_seconds(text: String) -> float:
	return clampf(0.9 + 0.045 * text.length(), 1.2, 6.0)


## Mood of an NPC: a tag on the line wins, then what it is doing, then the town, then its opinion of the hero.
static func mood_for(act: int, town_mood: Dictionary, opinion: int, line_mood: String) -> String:
	if MOODS.has(line_mood):
		return line_mood
	match act:
		A_FLEE, A_ALARM:
			return "fear"
		A_MOURN:
			return "sad"
		A_PROTEST:
			return "angry"
		A_FESTIVE, A_INN:
			return "happy"
	if float(town_mood.get("mourning", 0.0)) >= 0.5:
		return "sad"
	if float(town_mood.get("war", 0.0)) >= 0.5 or float(town_mood.get("monster", 0.0)) >= 0.5 or bool(town_mood.get("curfew", false)):
		return "fear"
	if float(town_mood.get("scarcity", 0.0)) >= 0.6:
		return "sad"
	if String(town_mood.get("festival", "")) != "":
		return "happy"
	if opinion <= -10:
		return "angry"
	if opinion >= 25:
		return "happy"
	return "neutral"


static func cards_enabled(tier: int, renderer: String) -> bool:
	return tier >= 1 and renderer != "gl_compatibility"
