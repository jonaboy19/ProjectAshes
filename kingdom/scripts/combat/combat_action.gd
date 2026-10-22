extends Resource
## One attack as data: windup / active / recovery seconds at speed 1.0, cancel windows, lane,
## poise damage, reach, root-motion flag and the animation clip NAME only (clips and blends belong
## to the animation owner). Clean-room design from docs/research/MINING_COMBAT_WORLD.md section 1.
## Built from dictionaries by CombatMoves; pure data, no scene access, so it runs headless.

enum Lane { HIGH, MID, LOW }

@export var id := ""
@export var style := ""
@export var anim := ""             ## clip name only
@export var anim_speed := 1.0
@export var windup := 0.2          ## s from start to the first active frame
@export var active := 0.08         ## s the blade can hurt
@export var recovery := 0.15       ## s after the active window
@export var hit_at := 0.03         ## s into the active window at which damage lands (the contact frame)
@export var damage := 10
@export var poise_damage := 10.0
@export var knockback := 1.5
@export var hitstop := 0.05
@export var cost := 0.0            ## stamina
@export var reach := 2.6
@export var lane := Lane.MID
@export var root_motion := true    ## true: the body lunges toward the target during the swing
@export var parryable := true
@export var unblockable := false
@export var finisher := false
@export var weight := 1.0          ## NPC move-choice weight
@export var min_range := 0.0       ## NPC: only chosen when the target is within [min_range, max_range]
@export var max_range := 99.0
@export var telegraph := true
## F3: seconds the attack input must be held before this row fires (0 = a tap). Heavy rows use data hold_time.
@export var charge_time := 0.0
@export var guard_break := false   ## breaks a guard (duck-typed break_guard() on the victim) instead of being blocked
@export var arc_dot := 0.2         ## player melee cone: victim must satisfy forward.dot(to) > arc_dot (staff/sweeps go lower)
@export var technique := false     ## staff heavy: also casts the equipped technique on release
@export var ranged := false        ## bow shot row: no melee hit, the arrow flies from the pool
## [{tag, from_t, to_t}] in seconds since swing start. Tag "attack" = the next swing may start.
@export var cancel_windows: Array = []


func total() -> float:
	return windup + active + recovery


## When damage lands, seconds after the swing starts.
func hit_time() -> float:
	return windup + hit_at


func active_start() -> float:
	return windup


func active_end() -> float:
	return windup + active


func is_active(t: float) -> bool:
	return t >= windup and t <= windup + active


## Time (since start) at which `tag` may cut this action, or -1.0 when it never may.
func cancel_from(tag: String, at := -1.0) -> float:
	for w: Dictionary in cancel_windows:
		if String(w["tag"]) == tag and (at < 0.0 or (at >= float(w["from_t"]) and at <= float(w["to_t"]))):
			return float(w["from_t"])
	return -1.0


func can_cancel(tag: String, t: float) -> bool:
	return cancel_from(tag, t) >= 0.0


## Seconds of the swing that must still be left for `tag` to cut it (0.0 = only when over).
## player.gd compares this with its remaining-time counter.
func cancel_remaining(tag: String) -> float:
	var f := cancel_from(tag)
	return 0.0 if f < 0.0 else total() - f
