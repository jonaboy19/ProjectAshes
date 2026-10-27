extends RefCounted
## Full-motion weapon chains (item 2) built from the owner's Mixamo combat packs. Timing is DATA: every row's contact
## frame, active window and root travel come from data/combat/mx_combat_markers.json (tools_qa/combat/mx_combat_markers.gd
## measures the weapon hand and the root track of each clip), so nothing here is a guessed number except the feel targets.
##
## Per style: a light chain (each step's clip played at a rate that puts its contact at LIGHT_HIT s), a finisher, a heavy
## (hold) row, a kick, (no leaping clips: Mx_SnS_Attack jumps ~0.5 m and read as floating in review), and a directional pool: attack input + a direction picks the swing whose measured cut matches
## (left / right / overhead / thrust), For Honor style. Cancel windows: the next light from contact + CHAIN_CANCEL, a dodge
## any time outside the active frames (player.gd rule), a block from the end of the active window.
##
## Root motion: every row has root_motion = true; combat_motion.gd moves and warps the capsule along the clip's root track.

const Action := preload("res://scripts/combat/combat_action.gd")
const MARKERS := "res://data/combat/mx_combat_markers.json"

const LIGHT_HIT := 0.40        ## s from press to contact for a light (anticipation readable, still snappy)
const FINISH_HIT := 0.58
const HEAVY_HIT := 0.72
const KICK_HIT := 0.36
const MIN_RATE := 0.8
const MAX_RATE := 2.2
const CHAIN_CANCEL := 0.22     ## s after contact the next light may cut in
const RECOVER_CAP := 0.80      ## clip s after the contact the swing still owns the body (rest of the clip is cut)
const ACTIVE_MIN := 0.06

## style -> rows. light: chain order; dir: cut -> clip; extras: reach, arc_dot, damage scale.
const CHAINS := {
	"sword": {"light": ["Mx_SnS_Slash_5", "Mx_SnS_Slash", "Mx_SnS_Slash_3"], "finisher": "Mx_SnS_Slash_4",
		"heavy": "Mx_SnS_Attack_3", "kick": "Mx_SnS_Kick",
		"dir": {"left": "Mx_SnS_Slash_5", "right": "Mx_SnS_Attack_4", "overhead": "Mx_SnS_Attack_3", "thrust": "Mx_SnS_Slash_3"},
		"reach": 2.6, "arc_dot": 0.2, "dmg": [14, 14, 18, 30], "heavy_dmg": 34, "cost": 10.0},
	"greatsword": {"light": ["Mx_GS_Slash", "Mx_GS_Slash_5", "Mx_GS_Slash_3"], "finisher": "Mx_GS_High_Spin_Attack",
		"heavy": "Mx_GS_Slash_3", "kick": "Mx_GS_Kick",
		"dir": {"left": "Mx_GS_Slash", "right": "Mx_GS_Slash_5", "overhead": "Mx_GS_Slash_3", "thrust": "Mx_GS_Attack"},
		"reach": 3.0, "arc_dot": 0.0, "dmg": [20, 20, 26, 40], "heavy_dmg": 46, "cost": 15.0, "slow": 1.2},
	"axe": {"light": ["Mx_Axe_Attack_Horizontal", "Mx_Axe_Attack_Backhand", "Mx_Axe_Attack_Downward"],
		"finisher": "Mx_Axe_Attack_360_High", "heavy": "Mx_Axe_Combo_Attack_V_2", "kick": "Mx_Axe_Attack_Kick_V_2",
		"dir": {"left": "Mx_Axe_Attack_Horizontal", "right": "Mx_Axe_Attack_Backhand", "overhead": "Mx_Axe_Attack_Downward",
			"thrust": "Mx_Axe_Combo_Attack_V_3"},
		"reach": 2.5, "arc_dot": 0.1, "dmg": [16, 16, 20, 32], "heavy_dmg": 38, "cost": 12.0, "slow": 1.1},
}

static var _markers := {}
static var _cache := {}
static var enabled := true     ## A/B switch for before/after recordings (--classic-combat)


static func markers() -> Dictionary:
	if _markers.is_empty() and FileAccess.file_exists(MARKERS):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(MARKERS))
		if d is Dictionary:
			_markers = d
	return _markers


static func has_style(style: String) -> bool:
	return enabled and CHAINS.has(style) and markers().has(String(CHAINS[style]["light"][0]))


## One swing row from a measured clip: played at the rate that lands the contact at `want_hit` seconds.
static func row(style: String, id: String, clip: String, want_hit: float, damage: int, extra := {}) -> Resource:
	var m: Dictionary = markers().get(clip, {})
	if m.is_empty():
		return null
	var c: Dictionary = CHAINS.get(style, {})
	var hit := maxf(float(m["hit"]), 0.05)
	var act: Array = m.get("active", [hit - 0.03, hit + 0.05])
	var rate := clampf(hit / (want_hit * float(c.get("slow", 1.0))), MIN_RATE, MAX_RATE)
	var a0 := minf(float(act[0]), hit - 0.01) / rate
	var a1 := maxf(float(act[1]), hit + 0.02) / rate
	var hit_p := hit / rate
	var end := minf(float(m["len"]), hit + RECOVER_CAP) / rate
	var a := Action.new()
	a.id = id
	a.style = style
	a.anim = clip
	a.anim_speed = rate
	a.windup = a0
	a.active = maxf(a1 - a0, ACTIVE_MIN)
	a.hit_at = hit_p - a0
	a.recovery = maxf(end - a0 - a.active, 0.1)
	a.damage = damage
	a.poise_damage = float(damage)
	a.reach = float(c.get("reach", 2.6))
	a.arc_dot = float(c.get("arc_dot", 0.2))
	a.cost = float(c.get("cost", 10.0))
	a.root_motion = true
	a.knockback = 1.5
	a.hitstop = 0.05
	a.cancel_windows = [{"tag": "attack", "from_t": hit_p + CHAIN_CANCEL, "to_t": a.total()},
		{"tag": "block", "from_t": a1, "to_t": a.total()}]
	for k: String in extra:
		a.set(k, extra[k])
	return a


## Light chain + finisher (finisher last, no "attack" cancel: it commits to its recovery).
static func combo(style: String) -> Array:
	if not has_style(style):
		return []
	var key := "combo:" + style
	if _cache.has(key):
		return _cache[key]
	var c: Dictionary = CHAINS[style]
	var dmg: Array = c["dmg"]
	var out: Array = []
	var light: Array = c["light"]
	for i in light.size():
		var r := row(style, "%s_fm_%d" % [style, i + 1], String(light[i]), LIGHT_HIT, int(dmg[i]),
			{"lane": [0, 1, 1][i % 3]})
		if r != null:
			out.append(r)
	var fin := row(style, style + "_fm_finisher", String(c["finisher"]), FINISH_HIT, int(dmg[3]),
		{"finisher": true, "knockback": 6.0, "hitstop": 0.09})
	if fin != null:
		fin.poise_damage = float(dmg[3]) * 2.0
		fin.cancel_windows = [{"tag": "block", "from_t": fin.active_end(), "to_t": fin.total()}]
		out.append(fin)
	_cache[key] = out
	return out


static func heavy(style: String, hold_time: float) -> Resource:
	if not has_style(style):
		return null
	var key := "heavy:" + style
	if _cache.has(key):
		return _cache[key]
	var c: Dictionary = CHAINS[style]
	var h := row(style, style + "_fm_heavy", String(c["heavy"]), HEAVY_HIT, int(c["heavy_dmg"]),
		{"finisher": true, "guard_break": true, "knockback": 7.0, "hitstop": 0.12, "charge_time": hold_time,
			"cost": float(c.get("cost", 10.0)) * 2.0, "lane": 0})
	if h != null:
		h.poise_damage = float(c["heavy_dmg"]) * 2.4
		h.cancel_windows = []
	_cache[key] = h
	return h


static func kick(style: String) -> Resource:
	if not has_style(style):
		return null
	var key := "kick:" + style
	if not _cache.has(key):
		var k := row(style, style + "_fm_kick", String(CHAINS[style]["kick"]), KICK_HIT, 4,
			{"guard_break": true, "knockback": 4.5, "parryable": false, "lane": 2, "cost": 12.0, "reach": 2.0})
		if k != null:
			k.poise_damage = 30.0
		_cache[key] = k
	return _cache[key]


## Input direction relative to the body (x = right, y = forward, length > 0.5 = a deliberate direction) -> cut name.
static func cut_for(local_input: Vector2) -> String:
	if local_input.length() < 0.5:
		return ""
	if absf(local_input.x) > absf(local_input.y) * 1.2:
		return "right" if local_input.x > 0.0 else "left"
	return "thrust" if local_input.y > 0.0 else "overhead"


## The swing to play for chain step `step` with this input: a directional cut when the player holds a direction
## (and the pool has it), else the chain's own step. Finishers are never replaced.
static func pick(style: String, steps: Array, step: int, local_input: Vector2) -> Resource:
	var base: Resource = steps[step]
	if not has_style(style) or base.finisher:
		return base
	var cut := cut_for(local_input)
	var clip := String((CHAINS[style]["dir"] as Dictionary).get(cut, ""))
	if clip == "" or clip == base.anim:
		return base
	var key := "dir:%s:%s:%d" % [style, cut, step]
	if not _cache.has(key):
		var r := row(style, "%s_fm_%s" % [style, cut], clip, LIGHT_HIT, base.damage, {"lane": base.lane})
		_cache[key] = r if r != null else base
	return _cache[key]


static func clear_cache() -> void:
	_cache.clear()
