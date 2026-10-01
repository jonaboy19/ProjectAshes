extends RefCounted
## One pure hit resolver. No scene access, no globals, no randf(): the caller passes a seeded
## RandomNumberGenerator, so duels and tests replay exactly. Clean-room, from the outcome list in
## docs/research/MINING_COMBAT_WORLD.md section 1 (HIT, BLOCKED, PARRIED, GUARD_BROKEN, CLASHED, DODGED).
##
## attack  = {damage, poise_damage, lane, parryable, unblockable, stat}
## defender = {
##   guarding: bool, guard_age: s since guard was raised (99 = parry window closed), guard_lane: lane or -1 (any),
##   guard_pool: stamina behind the guard, guard_cost: pool cost per point of damage (0.6; player uses 1.6),
##   poise: poise left, evading: true during dodge i-frames, from_front: bool,
##   swing: {} or {active_age: s since the defender's own active window opened (-99 when not active),
##            parryable, poise_damage, stat}  -> simultaneous strikes clash
## }
## Result keys: result (Outcome), grade (parry grade), damage (to defender), poise_damage (to defender),
##   guard_cost (pool), refund (to defender), attacker_stun / defender_stun (s), push (m on the attacker),
##   riposte (defender's next hit multiplier), winner ("attacker" / "defender" / "none" for clashes).

enum Outcome { HIT, BLOCKED, PARRIED, GUARD_BROKEN, CLASHED, DODGED }
const NAMES := ["HIT", "BLOCKED", "PARRIED", "GUARD_BROKEN", "CLASHED", "DODGED"]

const PERFECT_WINDOW := 0.07      # s: perfect parry
const PARRY_WINDOW := 0.18        # s: knockaway parry (same window as player.gd PARRY_WINDOW)
const CLASH_WINDOW := 0.12        # s between the two active windows for a clash beat
const BLOCK_CHIP := 0.15          # share of damage that gets through a block (matches player.gd)
const LANE_MISS_BLOCK := 0.55     # share of block efficiency kept on a lane mismatch
const GUARD_BREAK_STUN := 0.9
const CLASH_STUN := 0.45
const BROKEN_PARRY_RATIO := 1.6   # attack poise > defender poise * this turns a parry into a broken parry
const POISE_ON_BLOCK := 0.5       # share of the attack's poise damage a guard passes to poise


static func attack_from(a: Resource, stat := 0.0, dmg_scale := 1.0) -> Dictionary:
	return {"damage": int(a.damage * dmg_scale), "poise_damage": a.poise_damage, "lane": a.lane,
		"parryable": a.parryable, "unblockable": a.unblockable, "stat": stat}


static func _result(r: int) -> Dictionary:
	return {"result": r, "grade": "", "damage": 0, "poise_damage": 0.0, "guard_cost": 0.0, "refund": 0.0,
		"attacker_stun": 0.0, "defender_stun": 0.0, "push": 0.0, "riposte": 1.0, "winner": "none"}


static func resolve(attack: Dictionary, defender: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var dmg := int(attack.get("damage", 0))
	var pdmg := float(attack.get("poise_damage", dmg))
	var poise := float(defender.get("poise", 30.0))

	# 1. Dodge: i-frames beat everything.
	if bool(defender.get("evading", false)):
		return _result(Outcome.DODGED)

	# 2. Clash: both strikes active within CLASH_WINDOW and both parryable.
	var sw: Dictionary = defender.get("swing", {})
	if not sw.is_empty() and bool(attack.get("parryable", true)) and bool(sw.get("parryable", true)) \
			and absf(float(sw.get("active_age", -99.0))) <= CLASH_WINDOW:
		var a_score := pdmg + float(attack.get("stat", 0.0)) + rng.randf() * 6.0
		var d_score := float(sw.get("poise_damage", 10.0)) + float(sw.get("stat", 0.0)) + rng.randf() * 6.0
		var c := _result(Outcome.CLASHED)
		c["push"] = 1.5
		if absf(a_score - d_score) < 0.5:
			c["attacker_stun"] = CLASH_STUN * 0.5       # tie: both bounce
			c["defender_stun"] = CLASH_STUN * 0.5
		elif a_score > d_score:
			c["winner"] = "attacker"
			c["defender_stun"] = CLASH_STUN
		else:
			c["winner"] = "defender"
			c["attacker_stun"] = CLASH_STUN
		return c

	# 3. Guard.
	var front := bool(defender.get("from_front", true))
	if bool(defender.get("guarding", false)) and front and not bool(attack.get("unblockable", false)):
		var age := float(defender.get("guard_age", 99.0))
		if age <= PARRY_WINDOW and bool(attack.get("parryable", true)):
			var p := _result(Outcome.PARRIED)
			p["push"] = 3.5
			if pdmg > poise * BROKEN_PARRY_RATIO:
				p["grade"] = "broken"       # too heavy to turn aside: a third of it still hurts
				p["damage"] = int(dmg * 0.35)
				p["attacker_stun"] = 0.2
				p["poise_damage"] = pdmg * 0.5
				p["push"] = 1.0
			elif age <= PERFECT_WINDOW:
				p["grade"] = "perfect"
				p["attacker_stun"] = GUARD_BREAK_STUN
				p["refund"] = 14.0
				p["riposte"] = 1.75
			else:
				p["grade"] = "knockaway"
				p["attacker_stun"] = CLASH_STUN
				p["refund"] = 8.0           # same refund player.gd always gave
				p["riposte"] = 1.5
			return p
		var lane := int(defender.get("guard_lane", -1))
		var eff := 1.0 if lane < 0 or lane == int(attack.get("lane", 1)) else LANE_MISS_BLOCK
		var cost := dmg * float(defender.get("guard_cost", 0.6)) / eff
		var pool := float(defender.get("guard_pool", 100.0))
		if pool - cost <= 0.0 or pdmg * POISE_ON_BLOCK > poise:
			var g := _result(Outcome.GUARD_BROKEN)
			g["guard_cost"] = cost
			g["poise_damage"] = pdmg
			g["defender_stun"] = GUARD_BREAK_STUN
			return g
		var b := _result(Outcome.BLOCKED)
		b["guard_cost"] = cost
		b["damage"] = int(dmg * BLOCK_CHIP / eff)
		b["poise_damage"] = pdmg * POISE_ON_BLOCK
		return b

	# 4. Plain hit.
	var h := _result(Outcome.HIT)
	h["damage"] = dmg
	h["poise_damage"] = pdmg
	if pdmg >= poise:
		h["defender_stun"] = 0.35           # poise break: a stagger on top of the damage
	return h
