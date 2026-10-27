class_name MotionRules
extends RefCounted
## One motion layer every NPC body uses (docs/plans/NPC_MOTION_RULES.md). Pure, static, deterministic, no nodes:
##
##   var intent := MotionRules.evaluate(ctx, persona, tier)             # allocates one dictionary (tests, one-off callers)
##   MotionRules.evaluate_into(my_intent, ctx, persona, tier)           # refills a MotionIntent in place, no allocation
##
## ctx (all optional): now (s, game or frame clock), speed (m/s, else |velocity|), velocity (Vector3), motion_state
## (MotionRules.new_state(), owned by the body: enables min_hold_s hysteresis), plus whatever the rules read (heading, act, carrying,
## injured/tired/drunk, weather, hour, nearest stimuli, corridor width, group slot ...).
## persona: {archetype: "villager"|"child"|"elder"|"guard"|"bandit"|"follower"|"merchant"|"noble", ...}; any key that also exists
## in the archetype row of data/living_world/motion_rules.json overrides it for this person.
## tier: TIER_NEAR / TIER_MID / TIER_FAR / TIER_OUT (same numbers as CrowdAnimLOD.Tier).
##
## Arbitration. Rules are registered from the JSON (id, channels, priority, min_hold_s, tier). Every enabled, non-stub rule whose lowest
## tier covers the current tier is called; each one that returns true has written its fields into its own candidate. Per channel
## (BODY > LOCO > UPPER > HEAD, the ReactionRequest.Layer order) the highest priority wins, ties go to the earlier row. A BODY winner
## suppresses LOCO and UPPER (its row's `suppresses` overrides). With a motion_state, the winner of a channel is kept for its
## min_hold_s against equal or lower priority challengers, and when its trigger vanishes inside the hold its last output is latched
## until the hold ends. Without a motion_state evaluation is stateless.
## Tier degrade (applied last): NEAR everything; MID drops look and IK; FAR keeps steer and the base clip only, and a clip without
## a VAT bake (vat_bake.json clip set of the archetype) resolves to Walk/Idle; OUT returns nothing.
##
## Cost: one reset (~28 stores), one callable per active rule, four channel passes. Registry scratch is shared, so evaluate is not
## re-entrant (the game thread only).

const DATA := "res://data/living_world/motion_rules.json"
const VAT_DATA := "res://data/living_world/vat_bake.json"
const TIER_NEAR := 0
const TIER_MID := 1
const TIER_FAR := 2
const TIER_OUT := 3
const TIER_NAMES := ["NEAR", "MID", "FAR", "OUT"]
const MOVING_SPEED := 0.15
const DEFAULT_ARCHETYPE := "villager"
## A BODY winner silences LOCO and UPPER unless its row says otherwise.
const DEFAULT_SUPPRESS := (1 << MotionIntent.Channel.LOCO) | (1 << MotionIntent.Channel.UPPER)
const RULE_KEYS := ["head_rule", "upper_rule", "loco_rule", "body_rule"]
const CHANNELS_BY_PRECEDENCE := [MotionIntent.Channel.BODY, MotionIntent.Channel.LOCO, MotionIntent.Channel.UPPER, MotionIntent.Channel.HEAD]


## The registered rules, parallel arrays indexed by rule slot (only rules that can fire are slots; see add_rule).
class Registry extends RefCounted:
	var archetypes: Dictionary = {}
	var ids: Array[String] = []
	var fns: Array[Callable] = []
	var rows: Array[Dictionary] = []
	var cands: Array[Dictionary] = []
	var prio := PackedInt32Array()
	var hold := PackedFloat64Array()
	var mask := PackedInt32Array()
	var max_tier := PackedInt32Array()
	var suppress := PackedInt32Array()
	var count := 0
	# scratch for one evaluation
	var fired := PackedByteArray()
	var best := PackedInt32Array([-1, -1, -1, -1])
	var best_prio := PackedInt32Array([-1, -1, -1, -1])

	## Registers one rule. `row` is a motion_rules.json rule row. Disabled rows, stubs and rows without channels are not
	## evaluated (they can never change an intent), so they cost nothing per tick.
	func add_rule(id: String, fn: Callable, row: Dictionary) -> bool:
		if not bool(row.get("enabled", true)) or bool(row.get("stub", false)):
			return false
		var m := 0
		for c in row.get("channels", []):
			var ch := MotionIntent.CHANNEL_NAMES.find(String(c))
			if ch >= 0:
				m |= 1 << ch
		if m == 0:
			return false
		ids.append(id)
		fns.append(fn)
		rows.append(row)
		cands.append(MotionIntent.make())
		prio.append(int(row.get("priority", 1)))
		hold.append(float(row.get("min_hold_s", 0.0)))
		mask.append(m)
		max_tier.append(maxi(0, MotionRules.TIER_NAMES.find(String(row.get("tier", "NEAR")))))
		var sup := MotionRules.DEFAULT_SUPPRESS
		if row.has("suppresses"):
			sup = 0
			for c in row["suppresses"]:
				var sc := MotionIntent.CHANNEL_NAMES.find(String(c))
				if sc >= 0:
					sup |= 1 << sc
		suppress.append(sup)
		fired.resize(ids.size())
		count = ids.size()
		return true

	func archetype_of(persona: Dictionary) -> Dictionary:
		var a: Variant = archetypes.get(persona.get("archetype", MotionRules.DEFAULT_ARCHETYPE))
		if a == null:
			a = archetypes.get(MotionRules.DEFAULT_ARCHETYPE, {})
		return a


static var _default: Registry = null
static var _vat: Dictionary = {}          # clip set name -> {clip: true}
static var _vat_loaded := false


## The registry built from data/living_world/motion_rules.json (loaded once).
static func default_registry() -> Registry:
	if _default == null:
		_default = registry_from_file(DATA)
	return _default


static func registry_from_file(path: String) -> Registry:
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	return registry_from(d if typeof(d) == TYPE_DICTIONARY else {})


## Builds a registry from parsed JSON. Each rule id binds to the static function rule_<id lowercase> of this class unless
## `fns` maps the id to another Callable (tests).
static func registry_from(data: Dictionary, fns: Dictionary = {}) -> Registry:
	var r := Registry.new()
	r.archetypes = data.get("archetypes", {})
	var rules: Dictionary = data.get("rules", {})
	for id: String in rules:
		var fn: Callable = fns.get(id, Callable(MotionRules, "rule_" + id.to_lower()))
		if fn.is_valid():
			r.add_rule(id, fn, rules[id])
	return r


## Per-body hysteresis state: pass it as ctx["motion_state"].
static func new_state() -> Dictionary:
	return {"rule": PackedInt32Array([0, 0, 0, 0]), "until": PackedFloat64Array([0.0, 0.0, 0.0, 0.0]), "latch": MotionIntent.make()}


static func evaluate(ctx: Dictionary, persona: Dictionary, tier: int) -> Dictionary:
	var out := MotionIntent.make()
	evaluate_into(out, ctx, persona, tier)
	return out


## Archetype value overridden by the persona: persona[key] if present, else arch[key], else `fallback`.
static func param(arch: Dictionary, persona: Dictionary, key: String, fallback: Variant = 0.0) -> Variant:
	if persona.has(key):
		return persona[key]
	return arch.get(key, fallback)


static func evaluate_into(out: Dictionary, ctx: Dictionary, persona: Dictionary, tier: int, reg: Registry = null) -> void:
	var r: Registry = reg if reg != null else default_registry()
	MotionIntent.reset(out)
	out["tier"] = tier
	if tier >= TIER_OUT:
		return
	var arch := r.archetype_of(persona)
	var now := float(ctx.get("now", 0.0))
	var st: Variant = ctx.get("motion_state")
	if st != null and not (st as Dictionary).has("latch"):
		st = null

	var fired := r.fired
	var best := r.best
	var best_prio := r.best_prio
	best.fill(-1)
	best_prio.fill(-1)
	for i in r.count:
		fired[i] = 0
		if r.max_tier[i] < tier:
			continue
		var cand := r.cands[i]
		MotionIntent.reset_cand(cand)
		if not r.fns[i].call(ctx, arch, persona, r.rows[i], cand):
			continue
		fired[i] = 1
		var p := r.prio[i]
		var m := r.mask[i]
		for ch in 4:
			if (m >> ch) & 1 and p > best_prio[ch]:
				best_prio[ch] = p
				best[ch] = i

	var body_rule := -1
	for ch: int in CHANNELS_BY_PRECEDENCE:
		var chosen := best[ch]
		var from_latch := false
		if st != null:
			var s: Dictionary = st
			var rules_held: PackedInt32Array = s["rule"]
			var until: PackedFloat64Array = s["until"]
			var inc := rules_held[ch] - 1
			# an incumbent that cannot run at this tier loses its hold
			if inc >= 0 and now < until[ch] and r.max_tier[inc] >= tier and inc != chosen:
				if chosen < 0 or best_prio[ch] <= r.prio[inc]:
					chosen = inc
					from_latch = fired[inc] == 0
			if chosen != inc:
				rules_held[ch] = chosen + 1
				until[ch] = now + (r.hold[chosen] if chosen >= 0 else 0.0)
		if chosen < 0:
			continue
		if from_latch:
			MotionIntent.copy_channel(out, (st as Dictionary)["latch"], ch)
		else:
			MotionIntent.copy_channel(out, r.cands[chosen], ch)
			if st != null and r.hold[chosen] > 0.0:
				MotionIntent.copy_channel((st as Dictionary)["latch"], r.cands[chosen], ch)
		out[RULE_KEYS[ch]] = r.ids[chosen]
		if ch == MotionIntent.Channel.BODY:
			body_rule = chosen

	if body_rule >= 0:
		var sup := r.suppress[body_rule]
		for ch in 3:
			if (sup >> ch) & 1:
				MotionIntent.clear_channel_out(out, ch)
				out[RULE_KEYS[ch]] = ""
		if out["b_stop"] or out["b_speed_mul"] != 1.0 or out["b_steer_x"] != 0.0 or out["b_steer_z"] != 0.0:
			out["steer_x"] = out["b_steer_x"]
			out["steer_z"] = out["b_steer_z"]
			out["speed_mul"] = out["b_speed_mul"]
			out["stop"] = out["b_stop"]
	_compose_oneshot(out)
	_base_gait(out, ctx, arch, persona)
	if out["look_prio"] > 0:
		out["look_limit"] = float(param(arch, persona, "head_turn_deg", 70.0))
	_degrade(out, tier, arch, persona)


static func _compose_oneshot(out: Dictionary) -> void:
	if out["oneshot_clip"] != "":
		out["oneshot_channel"] = MotionIntent.Channel.BODY
	elif out["u_oneshot"] != "":
		out["oneshot_clip"] = out["u_oneshot"]
		out["oneshot_channel"] = MotionIntent.Channel.UPPER


## Every body always has a gait clip: the archetype idle or walk clip unless a LOCO rule picked one.
static func _base_gait(out: Dictionary, ctx: Dictionary, arch: Dictionary, persona: Dictionary) -> void:
	if out["gait_clip"] != "":
		return
	var gait: Dictionary = arch.get("gait", {})
	var persona_gait: Variant = persona.get("gait")
	if persona_gait is Dictionary:
		gait = persona_gait
	out["gait_clip"] = gait.get("walk", "Walk") if is_moving(ctx, out) else gait.get("idle", "Idle")


static func is_moving(ctx: Dictionary, out: Dictionary) -> bool:
	if out["stop"]:
		return false
	var spd: float = ctx.get("speed", -1.0)
	if spd < 0.0:
		var v: Variant = ctx.get("velocity")
		spd = (v as Vector3).length() if v is Vector3 else 0.0
	return spd > MOVING_SPEED


static func _degrade(out: Dictionary, tier: int, arch: Dictionary, persona: Dictionary) -> void:
	if tier <= TIER_NEAR:
		return
	MotionIntent.clear_channel_out(out, MotionIntent.Channel.HEAD)
	out["head_rule"] = ""
	out["look_limit"] = 0.0
	(out["ik"] as Array).clear()
	if tier == TIER_MID:
		return
	# FAR: steer and the base clip only
	out["upper_clip"] = ""
	out["upper_rule"] = ""
	out["u_oneshot"] = ""
	out["oneshot_clip"] = ""
	out["oneshot_channel"] = MotionIntent.NO_CHANNEL
	out["lean"] = 0.0
	out["reaction"] = 0
	var set_name := String(param(arch, persona, "vat_set", "adult"))
	if not vat_has(set_name, out["gait_clip"]):
		out["gait_clip"] = "Walk" if _is_walkish(out["gait_clip"]) else "Idle"


static func _is_walkish(clip: String) -> bool:
	return clip.contains("Walk") or clip.contains("Run") or clip.contains("March") or clip.contains("Jog")


## True when `clip` is baked for the FAR crowd in the named vat_bake.json clip set. Walk and Idle are always allowed (every set has them).
static func vat_has(set_name: String, clip: String) -> bool:
	if clip == "Walk" or clip == "Idle":
		return true
	if not _vat_loaded:
		_vat_loaded = true
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(VAT_DATA)) if FileAccess.file_exists(VAT_DATA) else null
		if typeof(d) == TYPE_DICTIONARY:
			var sets: Dictionary = (d as Dictionary).get("clip_sets", {})
			for s: String in sets:
				var m := {}
				for c: String in sets[s]:
					m[c] = true
				_vat[s] = m
	var m: Variant = _vat.get(set_name)
	return m != null and (m as Dictionary).has(clip)


# ---------------------------------------------------------------------------------------------------------------------
# Rule functions: one per section-3 row, bound by id (rule_<id lowercase>). Signature:
#   rule(ctx, arch, persona, row, cand) -> bool
# Read ctx / MotionRules.param(arch, persona, key) / row["params"]; write the fields of the channels the row declares into
# `cand` (MotionIntent keys; BODY steer goes in b_steer_x / b_steer_z / b_speed_mul / b_stop, an UPPER oneshot in u_oneshot);
# return true when the rule fired. Never allocate. Every function below is a stub (returns false, touches nothing): the package
# named in its comment replaces the body and flips "stub" to false in motion_rules.json.
# ---------------------------------------------------------------------------------------------------------------------

## S1 rvo_avoidance: stub, filled by package M4.
static func rule_s1(_ctx: Dictionary, _arch: Dictionary, _persona: Dictionary, _row: Dictionary, _cand: Dictionary) -> bool:
	return false


## S2 yield_give_way: stub, filled by package M4.
static func rule_s2(_ctx: Dictionary, _arch: Dictionary, _persona: Dictionary, _row: Dictionary, _cand: Dictionary) -> bool:
	return false


## S3 pass_right_shoulder_turn: stub, filled by package M4.
static func rule_s3(_ctx: Dictionary, _arch: Dictionary, _persona: Dictionary, _row: Dictionary, _cand: Dictionary) -> bool:
	return false


## S4 stop_for_carts_horses: stub, filled by package M4.
static func rule_s4(_ctx: Dictionary, _arch: Dictionary, _persona: Dictionary, _row: Dictionary, _cand: Dictionary) -> bool:
	return false


## S5 avoid_hazards: stub, filled by package M4.
static func rule_s5(_ctx: Dictionary, _arch: Dictionary, _persona: Dictionary, _row: Dictionary, _cand: Dictionary) -> bool:
	return false


## S6 walk_in_pairs: stub, filled by package M5.
static func rule_s6(_ctx: Dictionary, _arch: Dictionary, _persona: Dictionary, _row: Dictionary, _cand: Dictionary) -> bool:
	return false


## S7 queue: stub, filled by package M5.
static func rule_s7(_ctx: Dictionary, _arch: Dictionary, _persona: Dictionary, _row: Dictionary, _cand: Dictionary) -> bool:
	return false


## S8 lane_offset: stub, filled by package M4.
static func rule_s8(_ctx: Dictionary, _arch: Dictionary, _persona: Dictionary, _row: Dictionary, _cand: Dictionary) -> bool:
	return false


## A1 head_turn_budget: stub, filled by package M3.
static func rule_a1(_ctx: Dictionary, _arch: Dictionary, _persona: Dictionary, _row: Dictionary, _cand: Dictionary) -> bool:
	return false


## A2 glance_at_player: stub, filled by package M3.
static func rule_a2(_ctx: Dictionary, _arch: Dictionary, _persona: Dictionary, _row: Dictionary, _cand: Dictionary) -> bool:
	return false


## A3 eye_contact: stub, filled by package M3.
static func rule_a3(_ctx: Dictionary, _arch: Dictionary, _persona: Dictionary, _row: Dictionary, _cand: Dictionary) -> bool:
	return false


## A4 look_at_speaker: stub, filled by package M3.
static func rule_a4(_ctx: Dictionary, _arch: Dictionary, _persona: Dictionary, _row: Dictionary, _cand: Dictionary) -> bool:
	return false


## A5 look_at_noises: stub, filled by package M3.
static func rule_a5(_ctx: Dictionary, _arch: Dictionary, _persona: Dictionary, _row: Dictionary, _cand: Dictionary) -> bool:
	return false


## R1 flinch_loud_sound: stub, filled by package M6.
static func rule_r1(_ctx: Dictionary, _arch: Dictionary, _persona: Dictionary, _row: Dictionary, _cand: Dictionary) -> bool:
	return false


## R2 step_back_drawn_sword: stub, filled by package M6.
static func rule_r2(_ctx: Dictionary, _arch: Dictionary, _persona: Dictionary, _row: Dictionary, _cand: Dictionary) -> bool:
	return false


## R3 crowd_ripple_fight: stub, filled by package M6.
static func rule_r3(_ctx: Dictionary, _arch: Dictionary, _persona: Dictionary, _row: Dictionary, _cand: Dictionary) -> bool:
	return false


## R4 curiosity_gathering: stub, filled by package M6.
static func rule_r4(_ctx: Dictionary, _arch: Dictionary, _persona: Dictionary, _row: Dictionary, _cand: Dictionary) -> bool:
	return false


## R5 flee_with_dropped_load: stub, filled by package M6.
static func rule_r5(_ctx: Dictionary, _arch: Dictionary, _persona: Dictionary, _row: Dictionary, _cand: Dictionary) -> bool:
	return false


## R6 weather_hunch_shade: stub, filled by package M6.
static func rule_r6(_ctx: Dictionary, _arch: Dictionary, _persona: Dictionary, _row: Dictionary, _cand: Dictionary) -> bool:
	return false


## R7 cold_snow: stub, filled by package M6.
static func rule_r7(_ctx: Dictionary, _arch: Dictionary, _persona: Dictionary, _row: Dictionary, _cand: Dictionary) -> bool:
	return false


## O1 pick_by_need: stub, filled by package M7.
static func rule_o1(_ctx: Dictionary, _arch: Dictionary, _persona: Dictionary, _row: Dictionary, _cand: Dictionary) -> bool:
	return false


## O2 approach_arc: stub, filled by package M7.
static func rule_o2(_ctx: Dictionary, _arch: Dictionary, _persona: Dictionary, _row: Dictionary, _cand: Dictionary) -> bool:
	return false


## O3 side_aware_entry_exit: stub, filled by package M7.
static func rule_o3(_ctx: Dictionary, _arch: Dictionary, _persona: Dictionary, _row: Dictionary, _cand: Dictionary) -> bool:
	return false


## O4 hand_ik_on_props: stub, filled by package local.
static func rule_o4(_ctx: Dictionary, _arch: Dictionary, _persona: Dictionary, _row: Dictionary, _cand: Dictionary) -> bool:
	return false


## O5 occupancy_watchers: stub, filled by package M7.
static func rule_o5(_ctx: Dictionary, _arch: Dictionary, _persona: Dictionary, _row: Dictionary, _cand: Dictionary) -> bool:
	return false


## L1 slope_stairs_feet: stub, filled by package local.
static func rule_l1(_ctx: Dictionary, _arch: Dictionary, _persona: Dictionary, _row: Dictionary, _cand: Dictionary) -> bool:
	return false


## L2 lean_into_turns: stub, filled by package M8.
static func rule_l2(_ctx: Dictionary, _arch: Dictionary, _persona: Dictionary, _row: Dictionary, _cand: Dictionary) -> bool:
	return false


## L3 speed_matched_stride: stub, filled by package M8.
static func rule_l3(_ctx: Dictionary, _arch: Dictionary, _persona: Dictionary, _row: Dictionary, _cand: Dictionary) -> bool:
	return false


## L4 start_stop_turn: stub, filled by package M8.
static func rule_l4(_ctx: Dictionary, _arch: Dictionary, _persona: Dictionary, _row: Dictionary, _cand: Dictionary) -> bool:
	return false


## L5 carry_load_gait: stub, filled by package M8.
static func rule_l5(_ctx: Dictionary, _arch: Dictionary, _persona: Dictionary, _row: Dictionary, _cand: Dictionary) -> bool:
	return false


## L6 injured_tired_drunk_gaits: stub, filled by package M8.
static func rule_l6(_ctx: Dictionary, _arch: Dictionary, _persona: Dictionary, _row: Dictionary, _cand: Dictionary) -> bool:
	return false


## G1 conversation_circles: stub, filled by package M5.
static func rule_g1(_ctx: Dictionary, _arch: Dictionary, _persona: Dictionary, _row: Dictionary, _cand: Dictionary) -> bool:
	return false


## G2 families_walking: stub, filled by package M5.
static func rule_g2(_ctx: Dictionary, _arch: Dictionary, _persona: Dictionary, _row: Dictionary, _cand: Dictionary) -> bool:
	return false


## G3 guard_patrol_in_step: stub, filled by package M5.
static func rule_g3(_ctx: Dictionary, _arch: Dictionary, _persona: Dictionary, _row: Dictionary, _cand: Dictionary) -> bool:
	return false


## G4 kids_around_adults: stub, filled by package M5.
static func rule_g4(_ctx: Dictionary, _arch: Dictionary, _persona: Dictionary, _row: Dictionary, _cand: Dictionary) -> bool:
	return false


## C1 tagged_library: stub, filled by package M2.
static func rule_c1(_ctx: Dictionary, _arch: Dictionary, _persona: Dictionary, _row: Dictionary, _cand: Dictionary) -> bool:
	return false


## C2 variety_pick: stub, filled by package M2.
static func rule_c2(_ctx: Dictionary, _arch: Dictionary, _persona: Dictionary, _row: Dictionary, _cand: Dictionary) -> bool:
	return false


## C3 personality_offsets: stub, filled by package M2.
static func rule_c3(_ctx: Dictionary, _arch: Dictionary, _persona: Dictionary, _row: Dictionary, _cand: Dictionary) -> bool:
	return false


## B1 bystander_ring: stub, filled by package M6.
static func rule_b1(_ctx: Dictionary, _arch: Dictionary, _persona: Dictionary, _row: Dictionary, _cand: Dictionary) -> bool:
	return false


## B2 bandit_squad_flanks: stub, filled by package M9.
static func rule_b2(_ctx: Dictionary, _arch: Dictionary, _persona: Dictionary, _row: Dictionary, _cand: Dictionary) -> bool:
	return false


## B3 bumped_by_runner: stub, filled by package M6.
static func rule_b3(_ctx: Dictionary, _arch: Dictionary, _persona: Dictionary, _row: Dictionary, _cand: Dictionary) -> bool:
	return false

