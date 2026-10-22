extends RefCounted
## Trespass (package F5): being inside somebody's private space where you have no business.
##
##  - `evaluate`: is this interior private to the player right now? A home that is not yours at night or when its
##    lock is shut; a shop or inn outside its opening hours (shop_hours.gd) or in a back room. Shops and the inn
##    are public during open hours. The player's own property never counts.
##  - `step`: a tiny state machine fed every tick. Nobody has to be near you: the occupant notices you at a rate set
##    by your stance (crouching is slow, running is fast). When you are noticed you get ONE warning ("You shouldn't
##    be here"), and if you linger GRACE seconds after it the offence is a crime ("trespass" in Society).
## Pure static data, no nodes; crime_watch.gd drives it. Preload; no class_name.

const Ownership := preload("res://scripts/sim/ownership.gd")
const ShopHours := preload("res://scripts/sim/shop_hours.gd")

## Night hours when a home is shut to outsiders.
const NIGHT_FROM := 21.0
const NIGHT_TO := 6.0
## Seconds you may linger after the warning.
const GRACE := 8.0
## Awareness per second by stance (1.0 = noticed): crouch, walk, run.
const RATE_CROUCH := 0.08
const RATE_WALK := 0.22
const RATE_RUN := 0.45
const WARNING := "You shouldn't be here."


static func is_night(hour: float) -> bool:
	return hour >= NIGHT_FROM or hour < NIGHT_TO


## Does standing in an interior of `owner` count as trespass? `locked`: its lock is shut; `back_room`: a private
## part of an otherwise public building (the room behind the counter); `hour` 0..24 (game clock).
static func evaluate(owner: String, locked: bool, hour: float, player: Variant = null, back_room := false) -> bool:
	match Ownership.kind_of(owner):
		Ownership.Kind.PUBLIC, Ownership.Kind.PLAYER:
			return false
		Ownership.Kind.HOUSEHOLD:
			if not Ownership.is_theft(owner, player):
				return false
			return locked or is_night(hour)
		Ownership.Kind.SHOP:
			var kind := Ownership.hours_kind_of(owner)
			return locked or back_room or not ShopHours.is_open(kind, hour)
		Ownership.Kind.NPC:
			return locked
	return false


static func new_state() -> Dictionary:
	return {"aware": 0.0, "t": 0.0, "warned": false, "crime": false}


static func rate_for(crouching: bool, running: bool) -> float:
	if crouching:
		return RATE_CROUCH
	return RATE_RUN if running else RATE_WALK


## One tick of `dt` seconds. `trespassing` from evaluate(); `rate` from rate_for(); `occupied` false when nobody is
## there to notice. Returns "" (nothing), "warn" (the one warning) or "crime" (lingered past the warning).
static func step(st: Dictionary, dt: float, trespassing: bool, rate: float, occupied := true) -> String:
	if not trespassing:
		st["aware"] = 0.0
		st["t"] = 0.0
		st["warned"] = false
		st["crime"] = false
		return ""
	if not occupied:
		return ""
	st["aware"] = float(st["aware"]) + dt * rate
	if float(st["aware"]) < 1.0:
		return ""
	if not bool(st["warned"]):
		st["warned"] = true
		st["t"] = 0.0
		return "warn"
	st["t"] = float(st["t"]) + dt
	if float(st["t"]) >= GRACE and not bool(st["crime"]):
		st["crime"] = true
		return "crime"
	return ""


## Files the offence with Society (the occupant is the witness). Returns commit_crime's result, {} without society.
static func commit(soc: Object, sid: int, vis := 0.8) -> Dictionary:
	if soc == null or sid < 0:
		return {}
	return soc.call("commit_crime", "trespass", sid, ["occupant"], {"vis": [vis]})
