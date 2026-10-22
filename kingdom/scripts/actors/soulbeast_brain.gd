extends RefCounted
## F10 Soulbeast brain: all decisions, trust and save data for the one Soulbeast companion, with no scene access
## (soulbeast.gd is the body that moves, animates and fights). Pure data and scalars, so the tests replay it exactly.
##
## Wild life (temperament: nocturnal, it sleeps at its den by day):
##   IDLE -> ROAM -> EAT, SLEEP at the den, NOTICE the player, WARN (growls), LUNGE (a warning snap that never
##   damages), ATTACK, FLEE when badly hurt, RETURN to the den. How it treats the player depends on the trust stage:
##   WARY keeps its distance and growls, CURIOUS approaches and sniffs, ACCEPTING lets the player near, and BONDED
##   follows. Trust is 0..100 (gains and losses below).
## Companion: FOLLOW (formation offsets), STAY, WAIT outside an interior, FIGHT, EAT, SLEEP, DOWNED (0 HP, revived
##   by interacting or resting, never lost for good).
##
## No per-frame allocation: the body writes the senses (plain fields) and calls think_wild / think_ally at a few Hz;
## random choices come from a tiny integer generator (no randf, no Dictionary, no Array).

enum State { IDLE, ROAM, EAT, SLEEP, NOTICE, WARN, LUNGE, ATTACK, FLEE, RETURN, APPROACH, SNIFF, FOLLOW, STAY, FIGHT, DOWNED, WAIT }
enum Stage { WARY, CURIOUS, ACCEPTING, BONDED }
enum Cmd { FOLLOW, STAY, ATTACK }

const STATE_NAMES := ["idle", "roam", "eat", "sleep", "notice", "warn", "lunge", "attack", "flee", "return", "approach",
	"sniff", "follow", "stay", "fight", "downed", "wait"]
const STAGE_NAMES := ["wary", "curious", "accepting", "bonded"]

# --- trust -----------------------------------------------------------------------------------------
const STAGE_CURIOUS := 25.0
const STAGE_ACCEPTING := 50.0
const BOND_TRUST := 85.0           # from here the Bond interaction is offered
const PASSIVE_CAP := 70.0          # time nearby and calm approach never lift trust past this: food and help do
const GAIN_FOOD := 12.0            # leaving food at the den (meat is worth more than bread)
const GAIN_FOOD_REPEAT := 5.0      # a second offering inside OFFER_COOLDOWN
const OFFER_COOLDOWN := 90.0
const GAIN_HELP := 15.0            # helping it in a fight
const GAIN_DAY_PEACEFUL := 2.0     # a day without being attacked
const GAIN_NEAR := 0.08            # per second within NEAR_RANGE at any calm pace
const GAIN_CALM := 0.15            # per second walking slowly
const GAIN_CROUCH := 0.5           # per second crouched and slow
const LOSS_SPRINT := 1.2           # per second sprinting at it
const LOSS_DRAWN := 0.3            # per second with a weapon out inside DRAWN_RANGE
const LOSS_HIT := 25.0             # per blow
const LOSS_THREAT := 6.0           # a swing at it that missed
const DECAY_DAY := 1.0             # untended trust falls this much a day until bonded
const NEAR_RANGE := 12.0
const SPRINT_RANGE := 14.0
const DRAWN_RANGE := 10.0
const CALM_SPEED := 3.0
const CROUCH_SPEED := 1.6
const SPRINT_SPEED := 5.0

# --- wild ------------------------------------------------------------------------------------------
const FLEE_HP := 0.3               # fraction of max HP
const RECOVER_HP := 0.7            # it leaves the den to roam again above this
const FLEE_SAFE := 32.0
const FLEE_MAX := 9.0
const NOTICE_TIME := 1.2
const WARN_RANGE := 11.0
const BACK_OFF_RANGE := 6.0        # a wary beast backs away from anyone closer
const LUNGE_RANGE := 5.5
const LUNGE_AT := 3.0              # seconds of trespass before the warning lunge
const LUNGE_GRACE := 1.6           # seconds after the lunge before it bites for real
const SNIFF_DIST := 3.2
const ACCEPT_DIST := 1.8
const SNIFF_TIME := 3.0
const SNIFF_REST := 20.0           # seconds before it sniffs the same visitor again
const PROVOKED_TIME := 12.0
const CHASE_RANGE := 26.0
const SEEN_RANGE := 16.0           # hearing range at a walk (scaled by player noise)
const WAKE_FACTOR := 0.35          # a sleeper hears and sees only this much
const HUNGER_RATE := 1.0 / 900.0   # per second: hungry after about 11 minutes
const HUNGRY := 0.6
const EAT_SNIFF := 2.0
const EAT_TIME := 6.0
const SLEEP_FROM := 7.0            # nocturnal: asleep by day
const SLEEP_TO := 18.0

# --- companion -------------------------------------------------------------------------------------
const WALK_SPEED := 1.3
const RUN_SPEED := 6.6             # a touch over the player's 6.5 run
const CATCHUP_SPEED := 8.4
const CATCHUP_DIST := 10.0
const TELEPORT_DIST := 45.0
const TELEPORT_JUMP := 25.0        # the player moved this far in one frame: a fast travel
const LEASH := 28.0                # it will not chase a foe farther than this from the player
const STEAL_CHANCE := 0.15         # how often a killing blow is allowed to be its own
const IDLE_REST_AFTER := 25.0      # seconds of a still player before it lies down
const DOWNED_REVIVE_HP := 0.35
const ASSIST_RANGE := 15.0

# --- state -----------------------------------------------------------------------------------------
var state := State.IDLE
var trust := 0.0
var bonded := false
var soul_name := ""
var hp := 70
var max_hp := 70
var hunger := 0.2
var command := Cmd.FOLLOW
var den := Vector2.ZERO
var pos := Vector2.ZERO            # written by the body; saved
var downed := false
var steals := 0
var kills_assisted := 0
var last_offer := -1000.0
var hit_today := false

# senses, written by the body before each think
var dist := 99.0                   # to the player (metres)
var seen := false                  # Perception says the player is noticed (sight or hearing)
var player_speed := 0.0
var player_crouch := false
var player_armed := false
var player_inside := false         # the player is indoors
var player_teleported := false
var hour := 12.0
var at_den := false
var at_goal := false               # the body reached the target it was walking to
var food_near := false
var has_target := false            # a foe worth fighting beside the player
var provoked := 0.0                # seconds left of "it was attacked"
var now := 0.0                     # seconds, the body's clock

# outputs the body reads
var ate := false                   # set when a meal finished (the body clears it)
var lunged := false                # the warning lunge went off this think (the body clears it)
var changed := false               # state changed on the last think

var _t := 0.0                      # time in the current state
var _escalate := 0.0
var _lunge_done := false
var _grace := 0.0
var _sniff_rest := 0.0
var _still := 0.0
var _regen := 0.0
var _rng := 2463534242


func _init(seed_value := 1) -> void:
	_rng = 2463534242 ^ (seed_value * 2654435761 & 0x7fffffff)
	if _rng == 0:
		_rng = 1


# --- tiny deterministic generator -------------------------------------------------------------------
func rand() -> float:
	_rng ^= (_rng << 13) & 0xffffffff
	_rng ^= _rng >> 17
	_rng ^= (_rng << 5) & 0xffffffff
	_rng &= 0xffffffff
	return float(_rng) / 4294967296.0


# --- trust -----------------------------------------------------------------------------------------
func stage() -> int:
	if bonded:
		return Stage.BONDED
	if trust >= STAGE_ACCEPTING:
		return Stage.ACCEPTING
	if trust >= STAGE_CURIOUS:
		return Stage.CURIOUS
	return Stage.WARY


static func stage_for(t: float, is_bonded := false) -> int:
	if is_bonded:
		return Stage.BONDED
	if t >= STAGE_ACCEPTING:
		return Stage.ACCEPTING
	if t >= STAGE_CURIOUS:
		return Stage.CURIOUS
	return Stage.WARY


func add_trust(amount: float, cap := 100.0) -> float:
	if bonded:
		return trust
	if amount > 0.0:
		trust = maxf(trust, minf(trust + amount, cap))   # a cap never pulls down trust already above it
	else:
		trust += amount
	trust = clampf(trust, 0.0, 100.0)
	return trust


## Food left at the den (food_value 1 = bread and fruit, 2 = meat). Returns the trust gained.
func offer_food(food_value := 1.0, at_time := -1.0) -> float:
	var t := now if at_time < 0.0 else at_time
	var gain := GAIN_FOOD_REPEAT if t - last_offer < OFFER_COOLDOWN else GAIN_FOOD
	if food_value >= 1.5:
		gain *= 1.2
	last_offer = t
	hunger = maxf(0.0, hunger - 0.5 * clampf(food_value, 0.5, 2.0))
	var before := trust
	add_trust(gain)
	return trust - before


## Per-second passive trust from how the player moves near it. Called by the body each think with dt.
func tick_proximity(dt: float) -> void:
	if bonded:
		return
	if dist < SPRINT_RANGE and player_speed > SPRINT_SPEED:
		add_trust(-LOSS_SPRINT * dt)
		return
	if player_armed and dist < DRAWN_RANGE:
		add_trust(-LOSS_DRAWN * dt)
		return
	if dist > NEAR_RANGE:
		return
	var g := GAIN_NEAR
	if dist > 1.0:
		if player_crouch and player_speed < CROUCH_SPEED:
			g += GAIN_CROUCH
		elif player_speed < CALM_SPEED:
			g += GAIN_CALM
	add_trust(g * dt, PASSIVE_CAP)


## The player hit it (or struck at it and missed: `hit` false). A wild beast turns on the player.
func on_aggression(hit := true) -> void:
	hit_today = true
	if not bonded:
		add_trust(-(LOSS_HIT if hit else LOSS_THREAT))
		provoked = PROVOKED_TIME
		_lunge_done = true       # no more warnings
		_grace = 0.0


## The player helped it in a fight (killed or hurt something fighting it).
func on_helped() -> void:
	add_trust(GAIN_HELP)


func tick_day() -> void:
	var hit := hit_today
	hit_today = false
	if bonded:
		return
	if hit:
		add_trust(-DECAY_DAY)
	else:
		add_trust(GAIN_DAY_PEACEFUL, PASSIVE_CAP)


## Bonding: needs BOND_TRUST. The Soul Name (a RANaming ritual or the plain Bond interaction) is the body's call.
func can_bond() -> bool:
	return not bonded and not downed and trust >= BOND_TRUST


func bond(given_name: String) -> bool:
	if not can_bond():
		return false
	bonded = true
	trust = 100.0
	soul_name = given_name.strip_edges() if given_name.strip_edges() != "" else "Ash"
	hp = max_hp
	command = Cmd.FOLLOW
	provoked = 0.0
	_enter(State.FOLLOW)
	return true


# --- hp, downed, revive ----------------------------------------------------------------------------
func hp_frac() -> float:
	return float(hp) / float(maxi(max_hp, 1))


## Returns true when this blow downed it (bonded) or sent it fleeing (wild).
func hurt(amount: int) -> bool:
	if downed:
		return false
	hp = maxi(hp - amount, 0)
	if hp <= 0 and bonded:
		downed = true
		_enter(State.DOWNED)
		return true
	if hp <= 0:
		hp = 1                  # a wild Soulbeast is never killed outright: it flees at a sliver of health
	if not bonded and hp_frac() < FLEE_HP and state != State.RETURN:
		_enter(State.FLEE)      # even a sleeper bolts when badly hurt
	return false


func revive(frac := DOWNED_REVIVE_HP) -> bool:
	if not downed:
		return false
	downed = false
	hp = maxi(1, int(round(max_hp * frac)))
	_enter(State.FOLLOW if command != Cmd.STAY else State.STAY)
	return true


## The player rested or slept `hours`: it eats, sleeps, heals and gets back up.
func on_rest(hours: float) -> void:
	hunger = 0.0
	if downed:
		downed = false
		_enter(State.FOLLOW if command != Cmd.STAY else State.STAY)
	hp = mini(max_hp, hp + int(ceil(float(max_hp) * clampf(hours / 6.0, 0.25, 1.0))))
	if hours >= 6.0:
		hp = max_hp


# --- commands --------------------------------------------------------------------------------------
## Returns false when the command cannot be obeyed (attack with nothing to attack, not bonded, downed).
func give_command(c: int) -> bool:
	if not bonded or downed:
		return false
	if c == Cmd.ATTACK and not has_target:
		return false
	command = c
	match c:
		Cmd.STAY:
			_enter(State.STAY)
		Cmd.FOLLOW:
			_enter(State.FOLLOW)
		Cmd.ATTACK:
			_enter(State.FIGHT)
	return true


## The cycle the context button walks: attack (when the player has a foe) -> stay -> follow.
func next_command() -> int:
	if command == Cmd.STAY:
		return Cmd.FOLLOW
	if has_target and command != Cmd.ATTACK:
		return Cmd.ATTACK
	return Cmd.STAY


# --- companion geometry ----------------------------------------------------------------------------
## Formation slot `index` for a companion: (right, back) metres from the player. Even slots on one side, odd on
## the other, one row farther back every two.
static func slot_offset(index: int, moving: bool) -> Vector2:
	var side := -1.0 if index % 2 == 0 else 1.0
	var row := float(index / 2)
	if moving:
		return Vector2(1.6 * side, 2.4 + row * 1.8)
	return Vector2(1.9 * side, 0.8 + row * 1.8)


## World (x, z) of formation slot `index` around a player at `player_xz` facing `yaw` (rotation.y, +Z forward).
static func follow_point(player_xz: Vector2, yaw: float, moving: bool, index := 0) -> Vector2:
	var off := slot_offset(index, moving)
	var fwd := Vector2(sin(yaw), cos(yaw))
	var right := Vector2(fwd.y, -fwd.x)
	return player_xz + right * off.x - fwd * off.y


## Ground speed towards the formation point `gap` metres away, for a player moving at `speed`.
static func follow_speed(gap: float, speed: float) -> float:
	if gap < 0.5:
		return 0.0
	var cap := CATCHUP_SPEED if gap > CATCHUP_DIST else RUN_SPEED
	return clampf(maxf(speed, WALK_SPEED) + (gap - 1.0) * 0.9, WALK_SPEED, cap)


## True when walking is hopeless: far behind, or the player fast-travelled (jumped) while not indoors.
static func needs_teleport(distance: float, player_jump: float) -> bool:
	return distance > TELEPORT_DIST or player_jump > TELEPORT_JUMP


## A blow of `dmg` at a foe with `target_hp`: it never takes the kill, except STEAL_CHANCE of the time (`roll` 0..1).
func clamp_damage(dmg: int, target_hp: int, roll: float) -> int:
	if dmg < target_hp:
		return dmg
	if roll < STEAL_CHANCE:
		steals += 1
		return dmg
	return maxi(target_hp - 1, 0)


# --- wild thinking ---------------------------------------------------------------------------------
func is_sleep_hour() -> bool:
	return hour >= SLEEP_FROM and hour < SLEEP_TO


## Effective notice range: the body feeds `seen` from Perception; this is the hearing fallback and the
## sleeper's penalty (also used by tests).
func notice_range(noise_scale := 1.0) -> float:
	var r := SEEN_RANGE * clampf(noise_scale, 0.4, 1.6)
	if state == State.SLEEP:
		r *= WAKE_FACTOR
	return r


func _enter(s: int) -> void:
	if state != s:
		state = s
		_t = 0.0
		changed = true
		if s == State.SNIFF:
			_sniff_rest = SNIFF_REST


## One wild think. Reads the senses, advances timers and picks the state; returns it.
func think_wild(dt: float) -> int:
	changed = false
	if bonded:
		return think_ally(dt)
	_t += dt
	_sniff_rest = maxf(0.0, _sniff_rest - dt)
	if provoked > 0.0:
		provoked = maxf(0.0, provoked - dt)
	hunger = minf(1.0, hunger + dt * HUNGER_RATE)
	tick_proximity(dt)
	var st := stage()

	# Hurt: run, go home, lie up until healed.
	if state != State.FLEE and state != State.RETURN and state != State.SLEEP and hp_frac() < FLEE_HP:
		_enter(State.FLEE)
	if state == State.FLEE:
		if dist > FLEE_SAFE or _t > FLEE_MAX:
			_enter(State.RETURN)
		return state
	if state == State.RETURN:
		if at_den:
			_enter(State.SLEEP)
		return state

	# Attacked: it fights back until the player is far off or the anger passes.
	if provoked > 0.0:
		if dist < CHASE_RANGE:
			_enter(State.ATTACK)
		elif state == State.ATTACK:
			_enter(State.RETURN)
		return state
	if state == State.ATTACK:
		_enter(State.RETURN if dist > WARN_RANGE else State.NOTICE)
		return state
	# A hostile beast beside its den (the node scans for it): it fights that, not the player.
	if has_target:
		_enter(State.FIGHT)
		return state
	if state == State.FIGHT:
		_enter(State.IDLE)
		return state

	if state == State.SLEEP:
		if hp_frac() < RECOVER_HP:
			_regen += dt * 0.4
			if _regen >= 1.0:
				_regen -= 1.0
				hp = mini(max_hp, hp + 1)
		var wake := notice_range(maxf(player_speed / 3.0, 0.5))
		if seen and dist < wake:
			_enter(State.NOTICE)
		elif not is_sleep_hour() and hp_frac() >= RECOVER_HP and _t > 4.0:
			_enter(State.IDLE)
		return state

	if seen:
		_think_player(dt, st)
		return state
	# No player in mind.
	if state in [State.NOTICE, State.WARN, State.LUNGE, State.APPROACH, State.SNIFF]:
		_escalate = maxf(0.0, _escalate - dt)
		if _t > NOTICE_TIME:
			_enter(State.IDLE)
		return state
	_escalate = maxf(0.0, _escalate - dt * 2.0)
	_lunge_done = _lunge_done and _escalate > 0.0
	_grace = 0.0
	match state:
		State.IDLE:
			if is_sleep_hour() and _t > 2.0:
				_enter(State.SLEEP if at_den else State.RETURN)
			elif hunger > HUNGRY and food_near and _t > 1.0:
				_enter(State.EAT)
			elif _t > 3.0 + rand() * 4.0:
				_enter(State.ROAM)
		State.ROAM:
			if hunger > HUNGRY and food_near:
				_enter(State.EAT)
			elif at_goal or _t > 40.0:
				_enter(State.IDLE)
			elif is_sleep_hour() and _t > 12.0:
				_enter(State.RETURN)
		State.EAT:
			if at_goal and _t > EAT_SNIFF + EAT_TIME:
				hunger = 0.0
				ate = true
				_enter(State.IDLE)
			elif not food_near and not at_goal:
				_enter(State.IDLE)
		_:
			_enter(State.IDLE)
	return state


## Eating phases for the animation: 0 walking to the food, 1 sniffing, 2 eating.
func eat_phase() -> int:
	if state != State.EAT or not at_goal:
		return 0
	return 1 if _t < EAT_SNIFF else 2


func _think_player(dt: float, st: int) -> void:
	var calm := not player_armed and player_speed <= SPRINT_SPEED
	match st:
		Stage.WARY:
			_think_wary(dt)
		Stage.CURIOUS:
			if not calm or (dist < BACK_OFF_RANGE * 0.5 and player_speed > CALM_SPEED):
				_think_wary(dt)
			elif state == State.SNIFF:
				if _t > SNIFF_TIME:
					_enter(State.NOTICE)
			elif _sniff_rest > 0.0:
				_enter(State.NOTICE)               # has had its sniff: watches from where it is
			elif dist > SNIFF_DIST + 0.4:
				_enter(State.APPROACH if dist < SEEN_RANGE else State.NOTICE)
			else:
				_enter(State.SNIFF)
		_:
			if not calm:
				_think_wary(dt)
			elif dist > ACCEPT_DIST + 0.5:
				_enter(State.APPROACH if dist < SEEN_RANGE else State.NOTICE)
			else:
				_enter(State.SNIFF)


func _think_wary(dt: float) -> void:
	if state in [State.IDLE, State.ROAM, State.EAT, State.RETURN]:
		_enter(State.NOTICE)
		return
	if state == State.NOTICE and _t < NOTICE_TIME:
		return
	if dist >= WARN_RANGE + 3.0:
		_escalate = maxf(0.0, _escalate - dt)
		if state != State.NOTICE:
			_enter(State.NOTICE)
		return
	if dist < WARN_RANGE:
		var rate := 1.0
		if dist < LUNGE_RANGE:
			rate = 2.0
		elif player_crouch and player_speed < CROUCH_SPEED:
			rate = 0.3          # a calm, low approach buys time
		_escalate += dt * rate
	if state == State.LUNGE:
		_grace += dt
		if dist < LUNGE_RANGE and _grace > LUNGE_GRACE:
			provoked = PROVOKED_TIME * 0.5
			_enter(State.ATTACK)
		elif dist >= LUNGE_RANGE + 2.0 and _grace > 0.8:
			_enter(State.WARN)
		return
	if _escalate >= LUNGE_AT and dist < LUNGE_RANGE and not _lunge_done:
		_lunge_done = true
		_grace = 0.0
		lunged = true
		_enter(State.LUNGE)
		return
	if dist < WARN_RANGE:
		_enter(State.WARN)
	else:
		_enter(State.NOTICE)


# --- companion thinking ----------------------------------------------------------------------------
func think_ally(dt: float) -> int:
	changed = false
	_t += dt
	hunger = minf(1.0, hunger + dt * HUNGER_RATE * 0.5)
	if downed:
		_enter(State.DOWNED)
		return state
	if state == State.EAT and at_goal and _t > EAT_SNIFF + EAT_TIME:
		hunger = 0.0
		ate = true
		_enter(State.FOLLOW)
	if state == State.SLEEP:
		_regen += dt * 0.4
		if _regen >= 1.0:
			_regen -= 1.0
			hp = mini(max_hp, hp + 1)
	if player_speed < 0.3:
		_still += dt
	else:
		_still = 0.0
	if command == Cmd.STAY:
		_enter(State.STAY)
	elif player_inside:
		_enter(State.WAIT)
	elif has_target and (command == Cmd.ATTACK or dist < LEASH):
		_enter(State.FIGHT)
	elif command == Cmd.ATTACK and not has_target:
		command = Cmd.FOLLOW           # the foe is down: back to the player
		_enter(State.FOLLOW)
	elif _still > IDLE_REST_AFTER and dist < 6.0:
		if hunger > HUNGRY and food_near:
			_enter(State.EAT)
		elif hp_frac() < 1.0 or is_sleep_hour() or hunger > 0.3:
			_enter(State.SLEEP)
		else:
			_enter(State.FOLLOW)
	elif state == State.EAT and food_near and _still > 1.0:
		pass
	else:
		_enter(State.FOLLOW)
	if state == State.SLEEP and _still < 1.0:
		_enter(State.FOLLOW)
	return state


# --- save ------------------------------------------------------------------------------------------
## JSON-safe snapshot (trust, bonded, name, HP, position, den) following the followers.gd creature pattern.
func to_dict() -> Dictionary:
	return {"trust": snappedf(trust, 0.01), "bonded": bonded, "name": soul_name, "hp": hp, "max_hp": max_hp,
		"pos": [snappedf(pos.x, 0.01), snappedf(pos.y, 0.01)], "den": [snappedf(den.x, 0.01), snappedf(den.y, 0.01)],
		"command": int(command), "hunger": snappedf(hunger, 0.001), "downed": downed, "steals": steals,
		"assists": kills_assisted, "last_offer": snappedf(last_offer, 0.1), "hit_today": hit_today}


func from_dict(d: Dictionary) -> void:
	trust = clampf(float(d.get("trust", 0.0)), 0.0, 100.0)
	bonded = bool(d.get("bonded", false))
	soul_name = String(d.get("name", ""))
	max_hp = maxi(1, int(d.get("max_hp", max_hp)))
	hp = clampi(int(d.get("hp", max_hp)), 0, max_hp)
	var p: Array = d.get("pos", [pos.x, pos.y])
	pos = Vector2(float(p[0]), float(p[1])) if p.size() >= 2 else pos
	var dn: Array = d.get("den", [den.x, den.y])
	den = Vector2(float(dn[0]), float(dn[1])) if dn.size() >= 2 else den
	command = clampi(int(d.get("command", 0)), 0, 2)
	hunger = clampf(float(d.get("hunger", 0.2)), 0.0, 1.0)
	downed = bool(d.get("downed", false)) and bonded
	steals = int(d.get("steals", 0))
	kills_assisted = int(d.get("assists", 0))
	last_offer = float(d.get("last_offer", -1000.0))
	hit_today = bool(d.get("hit_today", false))
	provoked = 0.0
	state = State.DOWNED if downed else (State.STAY if bonded and command == Cmd.STAY else (State.FOLLOW if bonded else State.IDLE))
	_t = 0.0
