class_name MotionRules
extends RefCounted
## One rule layer between "the brain decided" and "the body plays" (docs/plans/NPC_MOTION_RULES.md sections 2-3).
## Pure and static: evaluate(ctx, persona, tier) -> MotionIntent dictionary. No nodes, no randf (use h01()), and the
## per-tick path allocates nothing when the caller reuses an intent through evaluate_into().
##
##   var state := MotionIntent.new_state()                      # one per body, kept by the caller
##   var intent := MotionRules.evaluate({"clip": "Walk", "speed": 1.2, "time": t, "state": state},
##                                      {"archetype": "guard", "person": id}, MotionIntent.Tier.NEAR)
##
## ctx keys read here: clip, rate (base gait from the brain), speed, moving, time (game seconds), state (hysteresis memory).
## Everything else in ctx is for the rule functions (position, heading, act, carrying, weather, stimuli ...).
##
## Arbitration. Every active rule returns a payload (any subset of MotionIntent.KEYS) or NOOP. Per channel the highest
## row priority wins (ties: first row). A winner stays for min_hold_s unless a STRICTLY higher priority preempts it.
## Channels: BODY > LOCO > UPPER > HEAD. A BODY winner suppresses LOCO and UPPER (flee, kneel, a full-body oneshot);
## HEAD stays free so a fleeing body can still look at the threat. Payloads of lower channels are applied first, so on
## a shared key the higher channel wins. Payload dictionaries must not be mutated after a rule returns them
## (the hold keeps a reference).
##
## Tier degrade (applied last, so it holds even if a rule misbehaves):
##   NEAR  everything.
##   MID   no look, no IK.
##   FAR   steer + base gait clip only; a clip without a VAT bake resolves to Walk/Idle.
##   OUT   empty intent.
##
## Packages fill the stubs: MotionRules.register("S2", Callable(SteerRules, "yield_rule")).

const MotionIntent := preload("res://scripts/living_world/motion_intent.gd")
const DATA_PATH := "res://data/living_world/motion_rules.json"
const NOOP := {}
const CH_HEAD := 0
const CH_UPPER := 1
const CH_LOCO := 2
const CH_BODY := 3

static var _ready_flag := false
static var _ids: Array[String] = []
static var _chan := PackedInt32Array()
static var _prio := PackedInt32Array()
static var _hold := PackedFloat32Array()
static var _tier := PackedInt32Array()
static var _enabled := PackedByteArray()
static var _stub := PackedByteArray()
static var _params: Array = []
static var _funcs: Array = []
static var _by_tier: Array = []
static var _arch: Dictionary = {}
static var _vat: Dictionary = {}
static var _fb_move := "Walk"
static var _fb_idle := "Idle"
# scratch for one evaluation (single-threaded by design)
static var _bi := PackedInt32Array([-1, -1, -1, -1])
static var _bp := PackedInt32Array([-1, -1, -1, -1])
static var _bpay: Array = [null, null, null, null]


## Deterministic 0..1 from a person id and a salt (no RNG state).
static func h01(person: int, salt: int) -> float:
	return float(absi(hash([person, salt])) % 10000) / 10000.0


static func archetype(persona: Dictionary) -> Dictionary:
	_ensure()
	var a: Variant = _arch.get(String(persona.get("archetype", "villager")))
	return a if a != null else _arch["villager"]


static func archetype_names() -> Array:
	_ensure()
	return _arch.keys()


static func rule_ids() -> Array[String]:
	_ensure()
	return _ids


static func index_of(id: String) -> int:
	_ensure()
	return _ids.find(id)


static func is_stub(id: String) -> bool:
	var i := index_of(id)
	return i >= 0 and _stub[i] == 1


static func params_of(id: String) -> Dictionary:
	var i := index_of(id)
	return _params[i] if i >= 0 else NOOP


## Replace a stub (or any rule) with a real function: (ctx, persona, params) -> Dictionary payload or NOOP.
static func register(id: String, fn: Callable) -> bool:
	var i := index_of(id)
	if i < 0:
		return false
	_funcs[i] = fn
	_stub[i] = 0
	_rebuild_index()
	return true


## Test hook: swap the whole registry for these rows ({id, channel, priority, min_hold_s, tier, params, enabled}).
## funcs maps id -> Callable; rows without a func stay stubs. Archetypes and VAT list are kept.
static func load_rows(rows: Array, funcs: Dictionary = {}) -> void:
	_ensure()
	_clear_rows()
	for r: Dictionary in rows:
		var id := String(r["id"])
		_add_row(r, funcs.get(id, Callable()))
	_rebuild_index()


## Back to data/living_world/motion_rules.json and the shipped stubs.
static func reload() -> void:
	_ready_flag = false
	_ensure()


static func _ensure() -> void:
	if _ready_flag:
		return
	var f := FileAccess.open(DATA_PATH, FileAccess.READ)
	var doc: Dictionary = JSON.parse_string(f.get_as_text()) if f != null else {}
	_arch = doc.get("archetypes", {"villager": {}})
	_vat.clear()
	for c: String in doc.get("vat_clips", []):
		_vat[c] = true
	var fb: Dictionary = doc.get("fallback_clips", {})
	_fb_move = String(fb.get("moving", "Walk"))
	_fb_idle = String(fb.get("idle", "Idle"))
	_clear_rows()
	var stubs := _stub_table()
	for r: Dictionary in doc.get("rules", []):
		_add_row(r, stubs.get(String(r["id"]), Callable()))
	_ready_flag = true
	_rebuild_index()


static func _clear_rows() -> void:
	_ids.clear()
	_chan.resize(0)
	_prio.resize(0)
	_hold.resize(0)
	_tier.resize(0)
	_enabled.resize(0)
	_stub.resize(0)
	_params.clear()
	_funcs.clear()


static func _add_row(r: Dictionary, fn: Callable) -> void:
	_ids.append(String(r["id"]))
	_chan.append(MotionIntent.CHANNEL_NAMES.find(String(r.get("channel", "loco"))))
	_prio.append(int(r.get("priority", 1)))
	_hold.append(float(r.get("min_hold_s", 0.0)))
	_tier.append(MotionIntent.TIER_NAMES.find(String(r.get("tier", "near"))))
	_enabled.append(1 if bool(r.get("enabled", true)) else 0)
	var real := fn.is_valid() and not bool(r.get("stub", false))
	_stub.append(0 if real else 1)
	_params.append(r.get("params", {}))
	_funcs.append(fn if fn.is_valid() else Callable())


## Active rows (enabled, not a stub) per evaluation tier: a row runs at tier t when t <= its lowest tier.
static func _rebuild_index() -> void:
	_by_tier.clear()
	for t in 4:
		var list := PackedInt32Array()
		for i in _ids.size():
			if _enabled[i] == 1 and _stub[i] == 0 and _tier[i] >= t:
				list.append(i)
		_by_tier.append(list)


static func evaluate(ctx: Dictionary, persona: Dictionary, tier: int) -> Dictionary:
	return evaluate_into(ctx, persona, tier, MotionIntent.make())


static func evaluate_into(ctx: Dictionary, persona: Dictionary, tier: int, out: Dictionary) -> Dictionary:
	_ensure()
	MotionIntent.reset(out)
	out["tier"] = tier
	if tier < 0 or tier >= MotionIntent.Tier.OUT:
		return out
	var gait: Dictionary = out["gait"]
	gait["clip"] = String(ctx.get("clip", ""))
	gait["rate"] = float(ctx.get("rate", 1.0))
	for c in 4:
		_bi[c] = -1
		_bp[c] = -1
		_bpay[c] = null
	var list: PackedInt32Array = _by_tier[tier]
	for i in list:
		var pay: Dictionary = (_funcs[i] as Callable).call(ctx, persona, _params[i])
		if pay.is_empty():
			continue
		var c := _chan[i]
		if _prio[i] > _bp[c]:
			_bi[c] = i
			_bp[c] = _prio[i]
			_bpay[c] = pay
	var st: Variant = ctx.get("state")
	if st is Dictionary and not (st as Dictionary).is_empty():
		var now := float(ctx.get("time", 0.0))
		for c in 4:
			_hold_channel(st, c, now, tier)
	var winners: Array = out["winners"]
	var suppress := _bi[CH_BODY] >= 0
	for c in 4:   # HEAD, UPPER, LOCO, BODY: higher channels overwrite shared keys
		var i := _bi[c]
		if i < 0 or (suppress and (c == CH_LOCO or c == CH_UPPER)):
			continue
		winners[c] = _ids[i]
		_apply_channel(out, _bpay[c], c, _prio[i])
	_degrade(out, ctx, tier)
	return out


static func _hold_channel(st: Dictionary, c: int, now: float, tier: int) -> void:
	var rule: PackedInt32Array = st["rule"]
	var prio: PackedInt32Array = st["prio"]
	var until: PackedFloat32Array = st["until"]
	var pay: Array = st["payload"]
	var held := rule[c]
	if held >= _ids.size() or (held >= 0 and (_tier[held] < tier or _chan[held] != c)):
		held = -1
		rule[c] = -1
	if held >= 0 and now < until[c]:
		if _bi[c] >= 0 and _bp[c] > prio[c]:
			pass   # strictly higher priority preempts, falls through to take it
		elif _bi[c] == held:
			pay[c] = _bpay[c]
			return
		else:
			_bi[c] = held
			_bp[c] = prio[c]
			_bpay[c] = pay[c]
			return
	if _bi[c] >= 0:
		rule[c] = _bi[c]
		prio[c] = _bp[c]
		until[c] = now + _hold[_bi[c]]
		pay[c] = _bpay[c]
	else:
		rule[c] = -1
		prio[c] = 0
		pay[c] = null


static func _apply_channel(out: Dictionary, pay: Dictionary, c: int, prio: int) -> void:
	MotionIntent.apply(out, pay)
	var lk: Dictionary = out["look"]
	if pay.has("look") and int(lk["priority"]) == 0:
		lk["priority"] = prio
	var o: Dictionary = out["oneshot"]
	if pay.has("oneshot") and String(o["clip"]) != "" and int(o["channel"]) < 0:
		o["channel"] = c


static func _degrade(out: Dictionary, ctx: Dictionary, tier: int) -> void:
	if tier == MotionIntent.Tier.NEAR:
		return
	var lk: Dictionary = out["look"]
	lk["target"] = null
	lk["priority"] = 0
	lk["hold_s"] = 0.0
	(out["ik"] as Array).clear()
	if tier == MotionIntent.Tier.MID:
		return
	out["upper"] = ""
	var o: Dictionary = out["oneshot"]
	o["clip"] = ""
	o["channel"] = -1
	out["lean"] = 0.0
	out["reaction"] = 0
	var g: Dictionary = out["gait"]
	var clip := String(g["clip"])
	if clip == "" or not _vat.has(clip):
		var steer: Dictionary = out["steer"]
		var moving: bool = ctx.get("moving", float(ctx.get("speed", 0.0)) > 0.1) and not bool(steer["stop"])
		g["clip"] = _fb_move if moving else _fb_idle


static func _stub_table() -> Dictionary:
	return {
		"S1": rule_s1,
		"S2": rule_s2,
		"S3": rule_s3,
		"S4": rule_s4,
		"S5": rule_s5,
		"S6": rule_s6,
		"S7": rule_s7,
		"S8": rule_s8,
		"A1": rule_a1,
		"A2": rule_a2,
		"A3": rule_a3,
		"A4": rule_a4,
		"A5": rule_a5,
		"R1": rule_r1,
		"R2": rule_r2,
		"R3": rule_r3,
		"R4": rule_r4,
		"R5": rule_r5,
		"R6": rule_r6,
		"R7": rule_r7,
		"O1": rule_o1,
		"O2": rule_o2,
		"O3": rule_o3,
		"O4": rule_o4,
		"O5": rule_o5,
		"L1": rule_l1,
		"L2": rule_l2,
		"L3": rule_l3,
		"L4": rule_l4,
		"L5": rule_l5,
		"L6": rule_l6,
		"G1": rule_g1,
		"G2": rule_g2,
		"G3": rule_g3,
		"G4": rule_g4,
		"C1": rule_c1,
		"C2": rule_c2,
		"C3": rule_c3,
		"B1": rule_b1,
		"B2": rule_b2,
		"B3": rule_b3,
	}


## Stubs: every rule ID of section 3. They are skipped by evaluate() while marked stub in the JSON.
## The owning package replaces one with MotionRules.register(id, callable); the signature stays.
static func rule_s1(_ctx: Dictionary, _persona: Dictionary, _p: Dictionary) -> Dictionary:   # rvo_avoidance
	return NOOP


static func rule_s2(_ctx: Dictionary, _persona: Dictionary, _p: Dictionary) -> Dictionary:   # yield_give_way
	return NOOP


static func rule_s3(_ctx: Dictionary, _persona: Dictionary, _p: Dictionary) -> Dictionary:   # pass_right_shoulder_turn
	return NOOP


static func rule_s4(_ctx: Dictionary, _persona: Dictionary, _p: Dictionary) -> Dictionary:   # stop_for_mover
	return NOOP


static func rule_s5(_ctx: Dictionary, _persona: Dictionary, _p: Dictionary) -> Dictionary:   # avoid_hazards
	return NOOP


static func rule_s6(_ctx: Dictionary, _persona: Dictionary, _p: Dictionary) -> Dictionary:   # pair_walk
	return NOOP


static func rule_s7(_ctx: Dictionary, _persona: Dictionary, _p: Dictionary) -> Dictionary:   # queue
	return NOOP


static func rule_s8(_ctx: Dictionary, _persona: Dictionary, _p: Dictionary) -> Dictionary:   # road_lane
	return NOOP


static func rule_a1(_ctx: Dictionary, _persona: Dictionary, _p: Dictionary) -> Dictionary:   # head_turn_budget
	return NOOP


static func rule_a2(_ctx: Dictionary, _persona: Dictionary, _p: Dictionary) -> Dictionary:   # glance_at_player
	return NOOP


static func rule_a3(_ctx: Dictionary, _persona: Dictionary, _p: Dictionary) -> Dictionary:   # eye_contact
	return NOOP


static func rule_a4(_ctx: Dictionary, _persona: Dictionary, _p: Dictionary) -> Dictionary:   # look_at_speaker
	return NOOP


static func rule_a5(_ctx: Dictionary, _persona: Dictionary, _p: Dictionary) -> Dictionary:   # look_at_noise
	return NOOP


static func rule_r1(_ctx: Dictionary, _persona: Dictionary, _p: Dictionary) -> Dictionary:   # flinch_loud_sound
	return NOOP


static func rule_r2(_ctx: Dictionary, _persona: Dictionary, _p: Dictionary) -> Dictionary:   # step_back_drawn_sword
	return NOOP


static func rule_r3(_ctx: Dictionary, _persona: Dictionary, _p: Dictionary) -> Dictionary:   # crowd_ripple
	return NOOP


static func rule_r4(_ctx: Dictionary, _persona: Dictionary, _p: Dictionary) -> Dictionary:   # curiosity_gather
	return NOOP


static func rule_r5(_ctx: Dictionary, _persona: Dictionary, _p: Dictionary) -> Dictionary:   # flee_drop_load
	return NOOP


static func rule_r6(_ctx: Dictionary, _persona: Dictionary, _p: Dictionary) -> Dictionary:   # weather_rain_sun
	return NOOP


static func rule_r7(_ctx: Dictionary, _persona: Dictionary, _p: Dictionary) -> Dictionary:   # cold_snow
	return NOOP


static func rule_o1(_ctx: Dictionary, _persona: Dictionary, _p: Dictionary) -> Dictionary:   # pick_by_need
	return NOOP


static func rule_o2(_ctx: Dictionary, _persona: Dictionary, _p: Dictionary) -> Dictionary:   # approach_arc
	return NOOP


static func rule_o3(_ctx: Dictionary, _persona: Dictionary, _p: Dictionary) -> Dictionary:   # side_aware_entry
	return NOOP


static func rule_o4(_ctx: Dictionary, _persona: Dictionary, _p: Dictionary) -> Dictionary:   # hand_ik_on_props
	return NOOP


static func rule_o5(_ctx: Dictionary, _persona: Dictionary, _p: Dictionary) -> Dictionary:   # occupancy_watchers
	return NOOP


static func rule_l1(_ctx: Dictionary, _persona: Dictionary, _p: Dictionary) -> Dictionary:   # slope_stairs_feet
	return NOOP


static func rule_l2(_ctx: Dictionary, _persona: Dictionary, _p: Dictionary) -> Dictionary:   # lean_into_turns
	return NOOP


static func rule_l3(_ctx: Dictionary, _persona: Dictionary, _p: Dictionary) -> Dictionary:   # stride_band
	return NOOP


static func rule_l4(_ctx: Dictionary, _persona: Dictionary, _p: Dictionary) -> Dictionary:   # start_stop_turn
	return NOOP


static func rule_l5(_ctx: Dictionary, _persona: Dictionary, _p: Dictionary) -> Dictionary:   # carry_gait
	return NOOP


static func rule_l6(_ctx: Dictionary, _persona: Dictionary, _p: Dictionary) -> Dictionary:   # injured_tired_drunk
	return NOOP


static func rule_g1(_ctx: Dictionary, _persona: Dictionary, _p: Dictionary) -> Dictionary:   # conversation_circle
	return NOOP


static func rule_g2(_ctx: Dictionary, _persona: Dictionary, _p: Dictionary) -> Dictionary:   # family_walk
	return NOOP


static func rule_g3(_ctx: Dictionary, _persona: Dictionary, _p: Dictionary) -> Dictionary:   # guard_patrol_phase_lock
	return NOOP


static func rule_g4(_ctx: Dictionary, _persona: Dictionary, _p: Dictionary) -> Dictionary:   # children_orbit
	return NOOP


static func rule_c1(_ctx: Dictionary, _persona: Dictionary, _p: Dictionary) -> Dictionary:   # tagged_library
	return NOOP


static func rule_c2(_ctx: Dictionary, _persona: Dictionary, _p: Dictionary) -> Dictionary:   # variety_pick
	return NOOP


static func rule_c3(_ctx: Dictionary, _persona: Dictionary, _p: Dictionary) -> Dictionary:   # personality_offsets
	return NOOP


static func rule_b1(_ctx: Dictionary, _persona: Dictionary, _p: Dictionary) -> Dictionary:   # bystander_ring
	return NOOP


static func rule_b2(_ctx: Dictionary, _persona: Dictionary, _p: Dictionary) -> Dictionary:   # bandit_squad_hooks
	return NOOP


static func rule_b3(_ctx: Dictionary, _persona: Dictionary, _p: Dictionary) -> Dictionary:   # bumped_by_runner
	return NOOP
