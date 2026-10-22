extends RefCounted
## AR-1: the player's aura as a pure state machine (docs/design/AURA_RELEASE.md section 1). NPC bosses reuse it.
## No nodes, no randf: every roll is hash([seed, "aura", day, n]). Time comes in as dt. `aura_emit` is OUTPUT only:
## subject_view() hands {aura_emit, aura_suppress} to SocialPerception.magic_pressure.
##
## Driver (player.gd / a thin node, local or Antigravity-free): each frame `update(dt, AuraInput.held(), ctx)`;
## on a tap while RELEASED call surge(); `rein_in()` on the rein action; `flare(power)` from technique_caster.

const Data := preload("res://scripts/sim/aura_data.gd")

enum St { SEALED, LEAKING, RELEASED, SURGING, ECHO, STRAINED, SLIPPED }
const NAMES := ["sealed", "leaking", "released", "surging", "echo", "strained", "slipped"]

var seed_value := 1
var day := 0
var power := 0.0               # P 0..1 (derived by the caller, see set_power_from_tier)
var control := 0.0             # Aura Control skill 0..100
var control_cap := 100.0       # theory study lifts the cap, not the value
var discipline := 0.0          # path discipline 0..1
var mantle := 0.0              # worn sealing item 0..0.25
var warded := false            # sanctified ground / ward stone: +0.1 forced
var focus := 100.0
var signature := "warm_gold"
var emotion := {"anger": 0.0, "fear": 0.0, "grief": 0.0, "hurt": 0.0, "stress": 0.0, "drunk": false, "starving": false}

var held_s := 0.0
var emit_at_release := 0.0
var since_release := 1.0e9
var released_long := 0.0       # length of the last release (settling window rule)
var settle_t := 0.0
var after_n := 0
var after_age := 0.0
var strained := false
var surge_t := 0.0
var rein_t := 0.0
var slip_t := 0.0
var no_rein_t := 0.0
var forced_t := 0.0            # involuntary release (breakthrough, grief): seconds left
var forced_amt := 0.0
var forced_reach := 0.0
var flare_t := 0.0
var flare_amt := 0.0
var directed := false
var clock := 0.0
var holding := false
var _emit := 0.0
var _slips := 0
var _n := 0


static func p(key: String, dflt: float) -> float:
	return float(Data.curve().get(key, dflt))


## P from the soul tier index (0 based, 12 tiers), flat below the floor tier so early play is never penalised.
static func power_from_tier(tier_index: int, path_level := 0, layers := 0) -> float:
	var tbl: Array = Data.curve().get("power_by_tier", [])
	if tbl.is_empty() or tier_index < int(p("power_floor_tier", 2)):
		return 0.0
	var base := float(tbl[clampi(tier_index, 0, tbl.size() - 1)])
	return clampf(base + clampf(float(path_level) / 30.0, 0.0, 1.0) * 0.1 + clampf(float(layers) / 9.0, 0.0, 1.0) * 0.05, 0.0, 1.0)


func set_power_from_tier(tier_index: int, path_level := 0, layers := 0) -> void:
	power = power_from_tier(tier_index, path_level, layers)


# ------------------------------------------------------------------ suppression S

func emotional_load() -> float:
	return clampf(maxf(maxf(float(emotion["anger"]), float(emotion["fear"])), maxf(float(emotion["grief"]), float(emotion["hurt"]))) * 0.7 + float(emotion["stress"]) * 0.3, 0.0, 1.0)


func suppression() -> float:
	var s := clampf(control / 100.0, 0.0, 1.0) * p("control_skill_weight", 0.55) + discipline * p("discipline_weight", 0.25)
	if float(emotion["stress"]) < 0.3 and float(emotion["anger"]) < 0.3:
		s += p("calm_bonus", 0.1)
	s += clampf(mantle, 0.0, 0.25) + (0.1 if warded else 0.0)
	s -= emotional_load() * p("emotion_penalty_max", 0.35)
	if bool(emotion["drunk"]):
		s -= 0.2
	if bool(emotion["starving"]):
		s -= 0.1
	if rein_t > 0.0:
		s += p("rein_bonus", 0.25)
	if strained:
		s -= p("strained_suppress_loss", 0.3)
	return clampf(s, 0.0, 1.0)


# ------------------------------------------------------------------ curve

static func leak_of(h: float) -> float:
	return 1.0 - exp(-maxf(h, 0.0) / p("t_rise", 4.0))


func raw_emit() -> float:
	return power * pow(leak_of(held_s), p("leak_exp", 0.8))


func passive() -> float:
	var v := power * pow(1.0 - suppression(), 3.0) * p("passive_scale", 0.05)
	if settle_t > 0.0:
		v += p("settle_passive", 0.1) * minf(power * 4.0, 1.0)
	v += float(after_n) * p("afterglow_each", 0.05) * minf(power * 4.0, 1.0)
	return v


## The curve while the button is down: raw minus suppression of the not-yet-leaked part.
func held_emit() -> float:
	var lk := leak_of(held_s)
	return clampf(raw_emit() - suppression() * (1.0 - lk) * p("suppress_mix", 0.5), 0.0, 1.0)


func reach_m() -> float:
	var r := raw_emit() if holding else maxf(_emit, 0.0)
	var reach := p("reach_base_m", 6.0) + p("reach_span_m", 70.0) * pow(clampf(r, 0.0, 1.0), p("reach_exp", 1.3))
	if forced_t > 0.0:
		reach = maxf(reach, forced_reach)
	return reach * (1.0 + (0.0 if not directed else 0.25))


func current_emit() -> float:
	return _emit


func state() -> int:
	if slip_t > 0.0:
		return St.SLIPPED
	if strained:
		return St.STRAINED
	if surge_t > 0.0:
		return St.SURGING
	if holding:
		return St.LEAKING if held_s < 1.0 else St.RELEASED
	if _emit > passive() + 0.02:
		return St.ECHO
	return St.SEALED


func state_name() -> String:
	return NAMES[state()]


func _roll(n: int) -> float:
	return float(absi(hash([seed_value, "aura", day, n, _slips])) % 10000) / 10000.0


# ------------------------------------------------------------------ driving

## One call per frame. `pressed` is the release button. ctx: {in_combat, meditating, day}.
func update(dt: float, pressed: bool, ctx: Dictionary = {}) -> void:
	if dt <= 0.0:
		return
	day = int(ctx.get("day", day))
	if pressed:
		hold(dt, bool(ctx.get("directed", false)))
	else:
		if holding:
			release()
		idle(dt, ctx)


func hold(dt: float, is_directed := false) -> void:
	if not holding:
		holding = true
		held_s = 0.0
		directed = is_directed
		strained = false
	else:
		directed = is_directed
	clock += dt
	held_s += dt
	since_release = 0.0
	rein_t = maxf(rein_t - dt, 0.0)
	surge_t = maxf(surge_t - dt, 0.0)
	var raw := raw_emit()
	var cost := p("cost_base_s", 1.5) + p("cost_emit_s", 6.0) * raw * raw
	if directed:
		cost *= p("directed_mult", 1.25)
	if held_s > p("strain_after_s", 10.0):
		cost *= p("strained_mult", 2.0)
	focus = maxf(focus - cost * dt, 0.0)
	if focus <= 0.0 and not strained:
		strained = true
	if strained:
		var jitter := 0.8 + 0.4 * _roll(int(clock * 10.0))
		_emit = clampf(held_emit() * jitter, 0.0, 1.0)
	else:
		_emit = held_emit()
	if surge_t > 0.0:
		_emit = minf(1.0, _emit + p("surge_gain", 0.25) * power)
	_emit = maxf(_emit, _forced_floor())
	_tick_timers(dt)


func release() -> void:
	if not holding:
		return
	holding = false
	emit_at_release = _emit
	released_long = held_s
	since_release = 0.0
	if held_s > p("settle_after_s", 6.0):
		settle_t = p("settle_window_s", 20.0)
	# repeated releases inside the window stack afterglow
	if after_n > 0 and after_age > p("afterglow_window_s", 120.0):
		after_n = 0
	after_n = mini(after_n + 1, int(p("afterglow_max", 5)))
	after_age = 0.0
	held_s = 0.0


## Tap while released: a one-second spike.
func surge() -> bool:
	if not holding or held_s < 1.0:
		return false
	surge_t = p("surge_seconds", 1.0)
	return true


## Rein in: raises suppression for 10 s, costs Focus. Cannot be used while no_rein_t runs (a loved one wounded).
func rein_in() -> bool:
	if no_rein_t > 0.0 or focus < p("rein_cost", 8.0) * 0.25:
		return false
	focus = maxf(focus - p("rein_cost", 8.0), 0.0)
	rein_t = p("rein_seconds", 10.0)
	if slip_t > 0.0:
		slip_t = 0.0
	return true


## A cast technique flares the aura regardless of the button (a big spell is loud).
func flare(technique_power: float) -> void:
	flare_amt = clampf(technique_power, 0.0, 1.0) * power
	flare_t = 1.5
	_emit = maxf(_emit, flare_amt)


## Involuntary release: breakthrough (8 s, 150 m), grief (5 s), loved one wounded.
func force_release(seconds: float, scale: float, reach := 0.0, no_rein := 0.0) -> void:
	forced_t = maxf(forced_t, seconds)
	forced_amt = clampf(scale, 0.0, 1.0)
	forced_reach = reach
	no_rein_t = maxf(no_rein_t, no_rein)
	_emit = maxf(_emit, _forced_floor())


func breakthrough() -> void:
	force_release(8.0, 1.0, 150.0, 8.0)


func grief_surge(bond: float) -> void:
	force_release(5.0, clampf(bond, 0.0, 1.0) * 0.8, 0.0, 0.0)


func _forced_floor() -> float:
	var f := 0.0
	if forced_t > 0.0:
		f = maxf(f, forced_amt * maxf(power, 0.0))
	if slip_t > 0.0:
		f = maxf(f, p("slip_emit_of_power", 0.4) * power)
	if flare_t > 0.0:
		f = maxf(f, flare_amt)
	return f


func idle(dt: float, ctx: Dictionary = {}) -> void:
	clock += dt
	since_release += dt
	surge_t = 0.0
	strained = false if focus > 5.0 else strained
	rein_t = maxf(rein_t - dt, 0.0)
	# focus regen
	var rate := p("focus_regen_meditate_per_min", 3.0) if bool(ctx.get("meditating", false)) else (0.0 if bool(ctx.get("in_combat", false)) else p("focus_regen_per_min", 1.2))
	focus = minf(focus + rate * dt / 60.0, p("focus_max", 100.0))
	# the felt field decays by the echo, never below the passive leak
	var echo := emit_at_release * exp(-since_release / p("echo_half_life_s", 6.0))
	_emit = maxf(echo, passive())
	_slip_check(dt)
	_emit = maxf(_emit, _forced_floor())
	_tick_timers(dt)


func _slip_check(dt: float) -> void:
	if slip_t > 0.0 or power <= 0.0:
		return
	var stress_load := emotional_load()
	if stress_load <= 0.0:
		return
	var s := suppression()
	var chance := p("slip_base_per_s", 0.04) * stress_load * (1.0 - s)
	if float(emotion["anger"]) > p("slip_anger", 0.7) and s < p("slip_suppress_below", 0.5):
		chance *= 6.0
	if bool(emotion["drunk"]):
		chance *= 3.0
	_n += 1
	if _roll(_n) < chance * dt:
		slip_t = p("slip_seconds", 3.0)
		_slips += 1


func _tick_timers(dt: float) -> void:
	slip_t = maxf(slip_t - dt, 0.0)
	forced_t = maxf(forced_t - dt, 0.0)
	no_rein_t = maxf(no_rein_t - dt, 0.0)
	flare_t = maxf(flare_t - dt, 0.0)
	settle_t = maxf(settle_t - dt, 0.0)
	if not holding and after_n > 0:
		after_age += dt
		if after_age >= p("afterglow_decay_s", 3600.0):
			after_n = 0
	# NOTE: slip/forced floors apply on the next emit computation


## Skill use under pressure (a guard talks to you while you hold S; a crowded market at full control).
func train(seconds: float, pressure: float) -> void:
	control = minf(control + p("control_gain_per_s_pressure", 0.01) * seconds * clampf(pressure, 0.0, 1.0), control_cap)


# ------------------------------------------------------------------ view

func subject_view(_ctx: Dictionary = {}) -> Dictionary:
	return {"aura_emit": _emit, "aura_suppress": suppression() if holding or _emit > 0.0 else 0.0, "reach_m": reach_m(), "signature": signature,
		"cone": 60.0 if directed else 360.0, "state": state_name(), "power": power}


# ------------------------------------------------------------------ save (compact ints; transient states reset to SEALED)

func serialize() -> Dictionary:
	return {"c": int(round(control * 10.0)), "cc": int(round(control_cap * 10.0)), "f": int(round(focus * 10.0)), "ag": after_n, "agt": int(after_age),
		"sig": signature, "d": int(round(discipline * 100.0))}


func deserialize(d: Dictionary) -> void:
	control = float(d.get("c", 0)) / 10.0
	control_cap = float(d.get("cc", 1000)) / 10.0
	focus = float(d.get("f", 1000)) / 10.0
	after_n = int(d.get("ag", 0))
	after_age = float(d.get("agt", 0))
	signature = String(d.get("sig", "warm_gold"))
	discipline = float(d.get("d", 0)) / 100.0
	holding = false
	held_s = 0.0
	_emit = 0.0
	emit_at_release = 0.0
	since_release = 1.0e9
	strained = false
