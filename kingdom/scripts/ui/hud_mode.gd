extends RefCounted
## Which HUD layout is up: EXPLORE (calm: joystick, one primary action, a few context actions) or
## COMBAT (the full combat cluster, techniques, hotbar). Pure logic so it can be tested without a scene:
## HUD feeds it `update(delta, hostile_near, weapon_active)` a few times a second; `combat_t` eases 0..1 for
## fades and slides. Combat ends COLLAPSE_DELAY seconds after the last hostile left / the last strike.

enum Mode { EXPLORE, COMBAT }

const COLLAPSE_DELAY := 6.0
const FADE_TIME := 0.35
const HOTBAR_REVEAL := 6.0
const ENGAGE_RANGE := 22.0

var mode := Mode.EXPLORE
var combat_t := 0.0                 # 0 = explore layout, 1 = combat layout (eased by the HUD)
var building := false               # a build / placement tool is active: the hotbar stays up
var hotbar_pinned := false          # the menu's "Quick slots" switch
var hotbar_reveal := 0.0            # seconds left after a slot key / tap / item selection
var _quiet := 99.0                  # seconds since the last hostile / strike


func engage() -> void:
	_quiet = 0.0
	mode = Mode.COMBAT


func update(delta: float, hostile_near: bool, weapon_active: bool) -> void:
	if hostile_near or weapon_active:
		_quiet = 0.0
	else:
		_quiet += delta
	mode = Mode.COMBAT if _quiet < COLLAPSE_DELAY else Mode.EXPLORE
	combat_t = move_toward(combat_t, 1.0 if mode == Mode.COMBAT else 0.0, delta / FADE_TIME)
	hotbar_reveal = maxf(0.0, hotbar_reveal - delta)


func in_combat() -> bool:
	return mode == Mode.COMBAT


func reveal_hotbar(seconds := HOTBAR_REVEAL) -> void:
	hotbar_reveal = maxf(hotbar_reveal, seconds)


func hotbar_wanted() -> bool:
	return mode == Mode.COMBAT or building or hotbar_pinned or hotbar_reveal > 0.0


## Smoothstep of combat_t for animations.
func eased() -> float:
	return combat_t * combat_t * (3.0 - 2.0 * combat_t)
