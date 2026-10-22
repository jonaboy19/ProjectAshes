extends SceneTree
## Headless duel arena: N seeded 1v1 duels per matchup on a 0.05 s fixed step, using the real data
## (CombatMoves tables), the real decision model (NpcFighter) and the real HitResolver. No scenes, no
## physics: distance is one axis. Prints win rate, mean time-to-kill, parry/clash/dodge rates for balance.
##
## Run:  $G --headless --path . -s res://tools_qa/combat/duel_arena.gd -- [--n=200] [--seed=1] [--only=a,b]
## Same seed, same numbers. Matchups use "bot" (a scripted player: combo, parry/dodge by skill) or an
## NpcFighter archetype. Tunables live in MATCHUPS and the player constants below.

const Moves := preload("res://scripts/combat/combat_moves.gd")
const Resolver := preload("res://scripts/combat/hit_resolver.gd")
const Fighter := preload("res://scripts/combat/npc_fighter.gd")

const DT := 0.05
const MAX_TIME := 60.0
const START_DIST := 3.0
const CLOSE_SPEED := 3.0
const PLAYER_HP := 120
const PLAYER_STAMINA := 100.0
const STAMINA_REGEN := 16.0
const STAMINA_DELAY := 1.0    # s after a spend before stamina regenerates (player _stamina_delay)
const COMBO_WINDOW := 0.45
const DODGE_COST := 15.0
const DODGE_TIME := 0.35
const REACT_BASE := 0.10      # player-bot reaction chance = BASE + SKILL * skill
const REACT_SKILL := 0.5
const BEAT_MIN := 0.2        # s between a bot's decisions (human beat), more when unskilled
const WHIFF_BASE := 0.25     # chance an unskilled swing misses entirely
const CLASH_RANK := 1.2      # clash stat per fighter rank
const DODGE_NOISE := 0.30     # s of timing error on an unskilled dodge

enum St { IDLE, WINDUP, RECOVER, STUN, GUARD, DODGE }

## [label, a, b, a_skill(0..1 bot only), hp_a, hp_b] ; names: "bot" or an NpcFighter archetype.
const MATCHUPS := [
	["bot_vs_goblin", "bot", "goblin", 0.5],
	["bot_vs_orc", "bot", "orc", 0.5],
	["bot_vs_troll", "bot", "troll", 0.5],
	["bot_vs_wolf", "bot", "wolf", 0.5],
	["bot_vs_bandit", "bot", "bandit", 0.5],
	["bot_vs_guard", "bot", "guard", 0.5],
	["skilled_bot_vs_goblin", "bot", "goblin", 0.9],
	["skilled_bot_vs_troll", "bot", "troll", 0.9],
	["skilled_bot_vs_bandit", "bot", "bandit", 0.9],
	["skilled_bot_vs_guard", "bot", "guard", 0.9],
	["bot_vs_3_goblins", "bot", "goblin", 0.5, 3],
	["bot_vs_2_wolves", "bot", "wolf", 0.5, 2],
	["bot_vs_3_bandits", "bot", "bandit", 0.5, 3],
	["skilled_bot_vs_3_bandits", "bot", "bandit", 0.9, 3],
	["guard_vs_2_wolves", "guard", "wolf", 0.0, 2],
	["guard_vs_wolf", "guard", "wolf", 0.0],
	["guard_vs_bandit", "guard", "bandit", 0.0],
	["bandit_vs_goblin", "bandit", "goblin", 0.0],
]


class Fx:
	var name := ""
	var bot := false
	var skill := 0.5
	var fighter: RefCounted
	var moves: Array = []
	var hp := 100
	var max_hp := 100
	var stamina := 100.0
	var poise := 30.0
	var poise_max := 30.0
	var guard_pool := 100.0
	var st := St.IDLE
	var t := 0.0
	var cur: Resource
	var resolved := false
	var cancelled := false
	var stun := 0.0
	var guard_age := 99.0
	var guard_left := 0.0
	var level := 0
	var serial := 0            # increments per swing started
	var reacted_to := -1       # foe swing serial already rolled for
	var stam_delay := 0.0
	var dmg := 1.0
	var parry_ok := true       # NPC guard counts as a timed parry this time
	var dodge_left := 0.0
	var pending := {}          # scheduled reaction {kind, at}
	var combo := -1
	var combo_t := 0.0
	var weak := false
	var rate := 1.0
	var think := 0.0
	var cooldown := 0.0
	var poise_idle := 0.0
	var last_hit := -99.0
	var immune_until := -99.0
	var riposte := 1.0
	var riposte_t := 0.0
	var press := false
	var cur_whiff := false
	# stats
	var strikes_at_me := 0
	var parries := 0
	var perfect := 0
	var clashes := 0
	var dodges := 0
	var blocks := 0
	var breaks := 0
	var hits_landed := 0
	var killed_at := 0.0


## --set=bandit.hp=90,bandit.dmg=1.8,goblin.rank=3 overrides archetype numbers for balance sweeps.
static var _OVER := {}


static func _mk(kind: String, skill: float, seed_value: int) -> Fx:
	var f := Fx.new()
	f.name = kind
	if kind == "bot":
		f.bot = true
		f.skill = skill
		f.moves = Moves.combo("sword")
		f.hp = PLAYER_HP
		f.max_hp = PLAYER_HP
		f.poise = 40.0
		f.poise_max = 40.0
	else:
		var ov: Dictionary = _OVER.get(kind, {})
		f.fighter = Fighter.make(kind, seed_value, int(ov.get("rank", -1)))
		f.fighter.cd_mult = float(ov.get("cd", f.fighter.cd_mult))
		f.dmg = float(ov.get("dmg", Fighter.ARCHETYPES[kind].get("dmg", 1.0)))
		f.moves = f.fighter.moves
		var d: Dictionary = Fighter.ARCHETYPES[kind]
		f.hp = int(ov.get("hp", d["hp"]))
		f.level = int(d.get("level", 0))
		f.max_hp = f.hp
		f.poise = float(ov.get("poise", d["poise"]))
		f.poise_max = f.poise
		f.fighter.poise_max = f.poise
		f.fighter.poise = f.poise
		f.skill = clampf(f.fighter.rank / 10.0 * 0.5, 0.0, 0.5)   # share of guards that land as timed parries
	return f


var _rng := RandomNumberGenerator.new()
var _time := 0.0
var _dist := START_DIST


func _init() -> void:
	var n := 200
	var seed_base := 1
	var only := ""
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--n="):
			n = int(a.substr(4))
		elif a.begins_with("--seed="):
			seed_base = int(a.substr(7))
		elif a.begins_with("--set="):
			for kv: String in a.substr(6).split(","):
				var parts := kv.split("=")
				var left := parts[0].split(".")
				if not _OVER.has(left[0]):
					_OVER[left[0]] = {}
				_OVER[left[0]][left[1]] = float(parts[1])
		elif a.begins_with("--only="):
			only = a.substr(7)
	print("duel arena: n=%d seed=%d dt=%.2f" % [n, seed_base, DT])
	print("%-24s %6s %7s %7s %7s %7s %7s %7s %7s" % ["matchup", "A win%", "B win%", "draw%", "TTK(s)", "parry%A", "clash/d", "dodge/d", "A hp%"])
	var report := {}
	for m: Array in MATCHUPS:
		if only != "" and not (String(m[0]) in only.split(",")):
			continue
		report[m[0]] = _run_matchup(m, n, seed_base)
	quit(0)


func _run_matchup(m: Array, n: int, seed_base: int) -> Dictionary:
	var aw := 0
	var bw := 0
	var dr := 0
	var ttk := 0.0
	var ttk_n := 0
	var strikes := 0
	var parries := 0
	var perfect := 0
	var clashes := 0
	var dodges := 0
	var hp_left := 0.0
	for i in n:
		var s := seed_base * 100003 + i * 7919 + hash(String(m[0])) % 9973
		_rng.seed = s
		var a := _mk(String(m[1]), float(m[3]), s + 1)
		var count: int = m[4] if m.size() > 4 else 1
		var pack: Array = []
		for k in count:
			pack.append(_mk(String(m[2]), 0.5, s + 2 + k))
		var w := _duel(a, pack)
		if w == 1:
			aw += 1
			hp_left += float(a.hp) / a.max_hp
			ttk += a.killed_at
			ttk_n += 1
		elif w == 2:
			bw += 1
			ttk += _time
			ttk_n += 1
		else:
			dr += 1
		strikes += a.strikes_at_me
		parries += a.parries
		perfect += a.perfect
		clashes += a.clashes
		dodges += a.dodges
	var res := {"a_win": 100.0 * aw / n, "b_win": 100.0 * bw / n, "draw": 100.0 * dr / n,
		"ttk": ttk / maxf(ttk_n, 1), "parry": 100.0 * parries / maxf(strikes, 1),
		"clash": float(clashes) / n, "dodge": float(dodges) / n, "hp": 100.0 * hp_left / maxf(aw, 1)}
	print("%-24s %6.1f %7.1f %7.1f %7.1f %7.1f %7.2f %7.2f %7.1f" % [m[0], res["a_win"], res["b_win"], res["draw"],
		res["ttk"], res["parry"], res["clash"], res["dodge"], res["hp"]])
	return res


## 0 draw, 1 a wins, 2 b wins (b is a pack; tokens cap how many may be mid-swing at once).
func _duel(a: Fx, pack: Array) -> int:
	_time = 0.0
	_dist = START_DIST
	_pack = pack
	while _time < MAX_TIME:
		_time += DT
		var foe := _first_alive(pack)
		if foe == null:
			a.killed_at = _time
			return 1
		_step(a, foe)
		for f: Fx in pack:
			if f.hp > 0:
				_step(f, a)
		if a.hp <= 0:
			return 0 if _first_alive(pack) == null else 2
	return 0


var _pack: Array = []


func _first_alive(pack: Array) -> Fx:
	for f: Fx in pack:
		if f.hp > 0:
			return f
	return null


## creature_attack_tokens.gd rule: 1 slot alone, 2 while up to four are engaged, 3 beyond.
func _token_free(me: Fx) -> bool:
	var alive := 0
	var busy := 0
	for f: Fx in _pack:
		if f.hp > 0:
			alive += 1
			if f != me and f.cur != null and (f.st == St.WINDUP or f.st == St.RECOVER):
				busy += 1
	var cap := 1 if alive <= 1 else (2 if alive <= 4 else 3)
	return busy < cap


func _reach(f: Fx) -> float:
	return (f.cur if f.cur != null else f.moves[0]).reach * 0.85


func _step(me: Fx, foe: Fx) -> void:
	if me.bot:
		me.stam_delay -= DT
		if me.stam_delay <= 0.0:
			me.stamina = minf(me.stamina + STAMINA_REGEN * DT, PLAYER_STAMINA)
	me.cooldown -= DT
	me.combo_t -= DT
	me.riposte_t -= DT
	if me.riposte_t <= 0.0:
		me.riposte = 1.0
	me.guard_pool = minf(me.guard_pool + 10.0 * DT, 100.0) if me.st != St.GUARD else me.guard_pool
	me.t += DT * me.rate
	match me.st:
		St.STUN:
			me.stun -= DT
			if me.stun <= 0.0:
				me.st = St.IDLE
			return
		St.WINDUP, St.RECOVER:
			if me.cur != null:
				if me.st == St.WINDUP and me.cancelled and me.t >= me.cur.windup * Fighter.FEINT_CANCEL:
					me.st = St.IDLE
					me.cur = null
					me.cooldown = 0.35
					return
				if me.st == St.WINDUP and not me.resolved and me.t >= me.cur.hit_time():
					me.resolved = true
					_strike(me, foe)
					if me.cur == null:
						return        # the strike got us stunned (parry / clash)
				if me.t >= me.cur.total():
					me.st = St.IDLE
					me.cooldown = maxf(me.cooldown, 0.0)
				elif me.t > me.cur.hit_time():
					me.st = St.RECOVER
		St.GUARD:
			me.guard_age += DT
			me.guard_left -= DT
			if me.guard_left <= 0.0:
				me.st = St.IDLE
			return
		St.DODGE:
			me.dodge_left -= DT
			if me.dodge_left <= 0.0:
				me.st = St.IDLE
			return
	if me.st == St.WINDUP or me.st == St.RECOVER:
		# A bot may press the next swing inside the cancel window.
		if me.bot and me.cur != null and me.st == St.RECOVER and me.cur.can_cancel("attack", me.t) \
				and me.cooldown <= 0.0 and _dist <= _reach(me) and not me.cur.finisher:
			_bot_swing(me, foe)
		_react(me, foe)
		return
	# Idle.
	if _react(me, foe):
		return
	if me.bot:
		_bot_think(me, foe)
	else:
		_npc_think(me, foe)


func _foe_threat(foe: Fx) -> bool:
	return foe.st == St.WINDUP and foe.cur != null and not foe.resolved


## Scheduled guard/dodge: queue one reaction when the foe winds up; fire it at its time.
func _react(me: Fx, foe: Fx) -> bool:
	if not me.pending.is_empty():
		if _time >= float(me.pending["at"]) and (me.st == St.IDLE):
			var kind := String(me.pending["kind"])
			me.pending = {}
			if _foe_threat(foe):
				if kind == "dodge":
					if me.stamina >= DODGE_COST or not me.bot:
						me.stamina -= DODGE_COST if me.bot else 0.0
						me.st = St.DODGE
						me.dodge_left = DODGE_TIME
						return true
				else:
					me.st = St.GUARD
					me.guard_age = 0.0
					me.guard_left = 0.7
					me.parry_ok = true
					if not me.bot:
						me.parry_ok = _rng.randf() < me.skill
					return true
		elif not _foe_threat(foe):
			me.pending = {}
		return false
	if not _foe_threat(foe) or _dist > foe.cur.reach + 0.3 or me.st != St.IDLE:
		return false
	var untill: float = foe.cur.hit_time() - foe.t       # time left to the foe's contact
	if me.bot and me.reacted_to == foe.serial:
		return false                                      # one reaction roll per enemy swing
	if me.bot:
		me.reacted_to = foe.serial
		# Player-bot reaction: skill sets the chance and how tight the timing lands.
		if _rng.randf() < REACT_BASE + REACT_SKILL * me.skill and untill > 0.1:
			var parry := _rng.randf() < 0.65
			var jitter := (1.0 - me.skill) * 0.16
			var lead := 0.03 + _rng.randf_range(0.0, 0.1 + jitter)
			var dodge_noise := _rng.randf_range(-1.0, 1.0) * (1.0 - me.skill * 0.7) * DODGE_NOISE
			me.pending = {"kind": "guard" if parry else "dodge", "at": _time + maxf(untill - (lead if parry else 0.2 + dodge_noise), 0.0)}
	else:
		var r: Dictionary = me.fighter.consider_reaction(_time)
		if not r.is_empty() and untill > float(r["delay"]):
			var at := _time + float(r["delay"])
			me.pending = {"kind": r["kind"], "at": at}
	return false


func _bot_swing(me: Fx, foe: Fx) -> void:
	var steps := me.moves
	me.combo = (me.combo + 1) % steps.size() if me.combo_t > 0.0 else 0
	var act: Resource = steps[me.combo]
	me.weak = me.stamina < act.cost
	me.stamina = maxf(me.stamina - act.cost, 0.0)
	me.stam_delay = STAMINA_DELAY
	me.rate = 0.7 if me.weak else 1.0
	_begin(me, act)
	me.combo_t = act.total() / me.rate + COMBO_WINDOW


func _begin(me: Fx, act: Resource) -> void:
	me.cur = act
	me.serial += 1
	me.st = St.WINDUP
	me.t = 0.0
	me.resolved = false
	me.cancelled = false
	me.cooldown = 0.0


func _bot_think(me: Fx, foe: Fx) -> void:
	if _dist > _reach(me) + 0.2:
		_dist = maxf(_dist - CLOSE_SPEED * DT, 0.5)
		return
	if _foe_threat(foe) and me.pending.is_empty() and _rng.randf() < 0.3 + 0.6 * me.skill:
		return    # hold and wait for the parry/dodge window instead of trading
	if me.think > 0.0:
		me.think -= DT
		return
	if foe.st == St.STUN or foe.st == St.RECOVER or foe.st == St.IDLE or not _foe_threat(foe):
		# Human beat: a short decision delay, longer and sloppier at low skill (also whiffs).
		me.think = _rng.randf_range(BEAT_MIN, BEAT_MIN + 0.25 + (1.0 - me.skill) * 0.6)
		_bot_swing(me, foe)
		if _rng.randf() < WHIFF_BASE * (1.0 - me.skill) + 0.05:
			me.cur_whiff = true


func _npc_think(me: Fx, foe: Fx) -> void:
	if me.cooldown > 0.0:
		return
	if not _token_free(me):
		return
	me.think -= DT
	if me.think > 0.0:
		return
	me.think = 1.0 / Fighter.THINK_HZ
	var tstate := "idle"
	if foe.st == St.WINDUP:
		tstate = "windup"
	elif foe.st == St.RECOVER:
		tstate = "recovery"
	elif foe.st == St.GUARD:
		tstate = "blocking"
	elif foe.st == St.STUN:
		tstate = "staggered"
	var ctx := {"dist": _dist, "target_state": tstate, "has_token": true, "own_hp_frac": float(me.hp) / me.max_hp,
		"strike_range": me.moves[0].reach * 0.85, "target_tired": foe.bot and foe.stamina < 15.0,
		"target_recovering": foe.st == St.RECOVER}
	var d: Dictionary = me.fighter.think(0.25, ctx)
	match int(d["intent"]):
		Fighter.Intent.APPROACH:
			_dist = maxf(_dist - CLOSE_SPEED * 0.8 * 0.25, 0.5)
		Fighter.Intent.RETREAT:
			_dist = minf(_dist + CLOSE_SPEED * 0.8 * 0.25, 5.0)
		Fighter.Intent.GUARD:
			me.st = St.GUARD
			me.guard_age = 99.0
			me.guard_left = 0.5
			me.parry_ok = false
		Fighter.Intent.POKE, Fighter.Intent.COMBO, Fighter.Intent.FEINT:
			var act: Resource = d["move"]
			me.rate = 1.0
			_begin(me, act)
			if int(d["intent"]) == Fighter.Intent.FEINT:
				me.cancelled = true
			me.cooldown = me.fighter.cooldown() * (0.5 if int(d["intent"]) == Fighter.Intent.COMBO else 1.0)
		_:
			pass


func _strike(me: Fx, foe: Fx) -> void:
	var act := me.cur
	if me.cancelled:
		return
	if me.cur_whiff:
		me.cur_whiff = false
		return
	if _dist > act.reach:
		return
	foe.strikes_at_me += 1
	var dmg_scale := (0.5 if me.weak else 1.0) * me.riposte
	me.riposte = 1.0
	var atk := Resolver.attack_from(act, _stat(me), dmg_scale)
	atk["damage"] = int(round(float(atk["damage"]) * me.dmg)) + me.level     # monster.gd adds its level to every blow
	var def := {"guarding": foe.st == St.GUARD, "from_front": true, "guard_age": foe.guard_age if foe.parry_ok else 99.0,
		"guard_pool": foe.guard_pool if not foe.bot else foe.stamina, "guard_cost": 1.6 if foe.bot else 0.6,
		"poise": foe.poise, "evading": foe.st == St.DODGE, "guard_lane": -1}
	if foe.st == St.WINDUP and foe.cur != null and not foe.resolved:
		# measured against the defender's own contact frame (player.gd passes the same quantity)
		def["swing"] = {"active_age": foe.t - foe.cur.hit_time(), "parryable": foe.cur.parryable,
			"poise_damage": foe.cur.poise_damage, "stat": _stat(foe)}
	var r := Resolver.resolve(atk, def, _rng)
	match int(r["result"]):
		Resolver.Outcome.HIT:
			_damage(foe, int(r["damage"]), float(r["poise_damage"]))
			me.hits_landed += 1
		Resolver.Outcome.BLOCKED:
			foe.blocks += 1
			if foe.bot:
				foe.stamina -= float(r["guard_cost"])
			else:
				foe.guard_pool -= float(r["guard_cost"])
			_damage(foe, int(r["damage"]), float(r["poise_damage"]))
		Resolver.Outcome.PARRIED:
			foe.parries += 1
			if r["grade"] == "perfect":
				foe.perfect += 1
			foe.stamina = minf(foe.stamina + float(r["refund"]), PLAYER_STAMINA)
			foe.riposte = float(r["riposte"])
			foe.riposte_t = 1.0
			_stun(me, float(r["attacker_stun"]))
			if int(r["damage"]) > 0:
				_damage(foe, int(r["damage"]), float(r["poise_damage"]))
			foe.st = St.IDLE
		Resolver.Outcome.GUARD_BROKEN:
			foe.breaks += 1
			_damage(foe, int(atk["damage"]), float(r["poise_damage"]))
			_stun(foe, float(r["defender_stun"]))
		Resolver.Outcome.CLASHED:
			me.clashes += 1
			foe.clashes += 1
			_stun_cancel(me, float(r["attacker_stun"]))
			if float(r["defender_stun"]) > 0.0:
				_stun_cancel(foe, float(r["defender_stun"]))
			if me.st != St.STUN:
				me.t = maxf(me.t, me.cur.hit_time())   # winner skips ahead into a shorter recovery
		Resolver.Outcome.DODGED:
			foe.dodges += 1
	var won: bool = int(r["result"]) == Resolver.Outcome.GUARD_BROKEN or (int(r["result"]) == Resolver.Outcome.CLASHED and r["winner"] == "attacker")
	if won and me.fighter != null and me.fighter.press_after_win():
		me.cooldown = 0.0        # press the advantage (rank/30)
		me.think = 0.0


## Clash stat: rank-weighted for fighters, a fixed mid value for the player-bot.
func _stat(f: Fx) -> float:
	return 4.0 if f.bot else float(f.fighter.rank) * CLASH_RANK


func _damage(f: Fx, dmg: int, poise_dmg: float) -> void:
	f.hp -= dmg
	if f.fighter != null:
		var broke: bool = f.fighter.absorb(poise_dmg, _time)
		f.poise = f.fighter.poise
		if broke:
			_stun(f, 0.5)
		return
	# the bot follows the same rule: break, refill to 60%, 1.6 s immune
	if _time - f.last_hit > Fighter.POISE_IDLE:
		f.poise = minf(f.poise_max, f.poise + Fighter.POISE_REGEN * (_time - f.last_hit - Fighter.POISE_IDLE))
	f.last_hit = _time
	if _time < f.immune_until:
		return
	f.poise -= poise_dmg
	if f.poise <= 0.0:
		f.poise = f.poise_max * Fighter.POISE_RESET
		f.immune_until = _time + Fighter.STAGGER_IMMUNE
		_stun(f, 0.5)


func _stun(f: Fx, secs: float) -> void:
	if secs <= 0.0:
		return
	_stun_cancel(f, secs)


func _stun_cancel(f: Fx, secs: float) -> void:
	if secs <= 0.0:
		return
	f.st = St.STUN
	f.stun = secs
	f.cur = null
	f.pending = {}
