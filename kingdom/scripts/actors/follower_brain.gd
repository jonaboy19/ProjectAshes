extends RefCounted
## Embodied recruits (Living World §2, stage 3): the pure decisions behind scripts/actors/follower_body.gd and
## follower_manager.gd, with no scene access so the tests replay them exactly.
##
## A recruit is a WorldSim row recorded as a follower (scripts/realm/followers.gd + recruitment.gd). Near the player
## it gets a body, within a small budget. Which orders keep a body, where it stands, when it hurries, teleports or
## waits, and who is embodied when there are more recruits than bodies are all decided here.
##
## Orders (recruitment.gd ORDERS): follow, wait, home, work. Fighters (guard / escort / campaign duty, or a
## fighting occupation) strike beside the player with an NpcFighter, like scripts/actors/squad_soldier.gd.

enum Mode { FOLLOW, CATCHUP, TELEPORT, WAIT, WAIT_OUTSIDE, HOME, WORK, FIGHT }
const MODE_NAMES := ["follow", "catchup", "teleport", "wait", "wait_outside", "home", "work", "fight"]

## Bodies at once (the phone budget); Quality.npc_full can only lower it.
const MAX_EMBODIED := 6
const MIN_EMBODIED := 2
## Followers within this of the formation point stand; farther they walk, then hurry, then teleport.
const FOLLOW_START := 2.2          # metres off the formation slot before a standing follower sets off
const FOLLOW_STOP := 0.9
const CATCHUP_DIST := 9.0          # farther than this from the PLAYER: run
const TELEPORT_DIST := 40.0
const TELEPORT_JUMP := 25.0        # the player moved this far in one frame: fast travel or a door
const TELEPORT_MIN := 12.0         # a jump only teleports someone who is at least this far away
const WALK_SPEED := 2.6
const RUN_SPEED := 6.2             # a touch under the player's 6.5 run
const CATCHUP_SPEED := 8.0
const LEASH := 22.0                # a fighter will not chase a foe farther than this from the player
const SCAN_RANGE := 14.0
const STRIKE_RANGE := 2.4
## Followers on work / home / wait orders keep a body only while the player is this close to where they are.
const LOCAL_RANGE := 45.0
const KEEP_NEAR := 25.0            # an embodied waiter / worker this close to the player always keeps its body
const LOCAL_KEEP := 1.25           # hysteresis: an embodied one is kept to LOCAL_RANGE * LOCAL_KEEP
const FIGHT_DUTIES := ["guard", "escort", "campaign"]
const FIGHT_OCC := ["knight", "mercenary", "cavalry"]
## followers.gd occupation -> PopulationLOD look id (JOB_LOOK / LOOK_MODEL) and SmartObjects job index.
const LOOK := {"hunter": "peasant", "knight": "guard", "scout": "peasant", "cavalry": "guard", "healer": "merchant",
	"smith": "worker", "priest": "merchant", "mercenary": "guard", "builder": "worker"}
const SMART_JOB := {"hunter": 5, "knight": 3, "scout": 5, "cavalry": 3, "healer": 2, "smith": 1, "priest": 2, "mercenary": 3, "builder": 4}


## How many bodies the tier allows: the cap, lowered when the tier's full-model budget is small.
static func budget(npc_full: int) -> int:
	return clampi(npc_full - 2, MIN_EMBODIED, MAX_EMBODIED)


static func is_fighter(duty: String, occupation: String) -> bool:
	return duty in FIGHT_DUTIES or occupation in FIGHT_OCC


## Formation slot `index` as (right, back) metres from the player. Even slots left, odd right, a row further back
## every two; wider and further back when the player is moving so nobody is trodden on.
static func slot_offset(index: int, moving: bool) -> Vector2:
	var side := -1.0 if index % 2 == 0 else 1.0
	var row := float(index / 2)
	if moving:
		return Vector2(1.5 * side, 2.2 + row * 1.7)
	return Vector2(1.8 * side, 1.0 + row * 1.7)


## World (x, z) of formation slot `index` for a player at `player_xz` facing `yaw` (rotation.y, +Z forward).
static func follow_point(player_xz: Vector2, yaw: float, moving: bool, index := 0) -> Vector2:
	var off := slot_offset(index, moving)
	var fwd := Vector2(sin(yaw), cos(yaw))
	var right := Vector2(fwd.y, -fwd.x)
	return player_xz + right * off.x - fwd * off.y


static func needs_teleport(dist: float, player_jump: float) -> bool:
	return dist > TELEPORT_DIST or (player_jump >= TELEPORT_JUMP and dist >= TELEPORT_MIN)


## Ground speed towards the formation slot `gap` metres away for a player moving at `player_speed` and `dist`
## metres from the player. 0 inside FOLLOW_STOP.
static func follow_speed(gap: float, player_speed: float, dist: float) -> float:
	if gap < FOLLOW_STOP:
		return 0.0
	var cap := CATCHUP_SPEED if dist > CATCHUP_DIST else RUN_SPEED
	return clampf(maxf(player_speed, WALK_SPEED) + (gap - 1.0) * 0.8, WALK_SPEED, cap)


## The mode of one embodied recruit. ctx: dist (to the player), player_inside (an interior is open), jump (the
## player's move last frame), fighter, foe (a foe is near the player and inside the leash), was_standing.
static func decide(order: String, ctx: Dictionary) -> int:
	match order:
		"wait":
			return Mode.WAIT
		"home":
			return Mode.HOME
		"work":
			return Mode.WORK
	if bool(ctx.get("player_inside", false)):
		return Mode.WAIT_OUTSIDE
	var dist := float(ctx.get("dist", 0.0))
	if needs_teleport(dist, float(ctx.get("jump", 0.0))):
		return Mode.TELEPORT
	if bool(ctx.get("fighter", false)) and bool(ctx.get("foe", false)) and dist < LEASH:
		return Mode.FIGHT
	if dist > CATCHUP_DIST:
		return Mode.CATCHUP
	return Mode.FOLLOW


## Should a standing follower start walking? Hysteresis between FOLLOW_START and FOLLOW_STOP.
static func should_move(gap: float, moving_now: bool) -> bool:
	return gap > (FOLLOW_STOP if moving_now else FOLLOW_START)


## Which recruits get a body. cands: [{fid, order, fighter, d}] where d is the distance from the player to the
## recruit's anchor (followers: to the player). `have` is the set of fids that already have a body (kept with
## hysteresis). Followers first (fighters before the rest, then by id), then local workers nearest first. Returns
## fids in the order they should be slotted.
static func select(cands: Array, cap: int, have := {}) -> Array:
	var follow: Array = []
	var local: Array = []
	for c: Dictionary in cands:
		if String(c["order"]) == "follow":
			follow.append(c)
		elif String(c["order"]) == "home" and not have.has(c["fid"]):
			continue                     # sent home with no body: the village schedule takes the row
		else:
			var lim := LOCAL_RANGE * (LOCAL_KEEP if have.has(c["fid"]) else 1.0)
			if float(c["d"]) <= lim:
				local.append(c)
	follow.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if bool(a["fighter"]) != bool(b["fighter"]):
			return bool(a["fighter"])
		return _num(a["fid"]) < _num(b["fid"]))
	local.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var da := float(a["d"]) * (0.8 if have.has(a["fid"]) else 1.0)
		var db := float(b["d"]) * (0.8 if have.has(b["fid"]) else 1.0)
		if absf(da - db) > 0.001:
			return da < db
		return _num(a["fid"]) < _num(b["fid"]))
	var out: Array = []
	# Someone standing close by (waiting, working) with a body keeps it: it must not vanish in front of the player.
	var rest: Array = []
	for c: Dictionary in local:
		if have.has(c["fid"]) and float(c["d"]) <= KEEP_NEAR and out.size() < cap:
			out.append(c["fid"])
		else:
			rest.append(c)
	for c: Dictionary in follow:
		if out.size() >= cap:
			break
		out.append(c["fid"])
	for c: Dictionary in rest:
		if out.size() >= cap:
			break
		out.append(c["fid"])
	return out


static func _num(fid: Variant) -> int:
	return int(String(fid).substr(1))


## A fighter's rank (NpcFighter 0..10) from the recruit's combat skill.
static func fighter_rank(combat_skill: float) -> int:
	return clampi(int(round(1.0 + combat_skill * 7.0)), 1, 9)


## Hit points of a recruit's body: sturdier with combat skill. They are knocked out, never killed, by the body.
static func max_hp(combat_skill: float) -> int:
	return 40 + int(round(combat_skill * 40.0))
