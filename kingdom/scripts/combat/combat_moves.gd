extends RefCounted
## Move tables per weapon/style. The "sword" combo ports player.gd's old COMBO constant exactly:
## total = old "lock", hit_time() = old "hit", cancel window = last 22% of the lock (old SWING_CANCEL).
## Creature rows reproduce monster.gd / wolf.gd SPECIES timings for their default move and add
## 1-2 extra moves each. Clip names are roles/names only.

const Action := preload("res://scripts/combat/combat_action.gd")

const CANCEL_TAIL := 0.22          ## last fraction of a combo swing that the next swing may cut
const ACTIVE_LEAD := 0.03          ## active window opens this long before the contact frame (old ACTIVE_BEFORE)
const ACTIVE_LEN := 0.08           ## ACTIVE_BEFORE + ACTIVE_AFTER

## Player sword chain: [anim, damage, lock, hit, speed, cost, knockback]
const SWORD_ROWS := [
	["Sword_Light_1_Upper", 14, 0.42, 0.25, 1.2, 10.0, 1.5],
	["Sword_Light_2_Upper", 14, 0.39, 0.19, 1.2, 10.0, 1.5],
	["Sword_Light_3_Upper", 18, 0.42, 0.25, 1.2, 12.0, 1.5],
	["Sword_Light_4_Upper", 30, 0.64, 0.44, 1.2, 16.0, 7.0],
]

static var _cache := {}


static func _make(d: Dictionary) -> Resource:
	var a: Resource = Action.new()
	for k: String in d:
		a.set(k, d[k])
	return a


## A swing described the way the old table was (lock = whole swing, hit = contact time).
static func _combo_step(style: String, n: int, last: bool, row: Array, lane: int) -> Resource:
	var lock: float = row[2]
	var hit: float = row[3]
	var a := _make({"id": "%s_%d" % [style, n + 1], "style": style, "anim": row[0], "damage": row[1],
		"anim_speed": row[4], "cost": row[5], "knockback": row[6], "lane": lane,
		"windup": hit - ACTIVE_LEAD, "active": ACTIVE_LEN, "hit_at": ACTIVE_LEAD,
		"recovery": lock - hit - (ACTIVE_LEN - ACTIVE_LEAD),
		"poise_damage": float(row[1]) * (2.0 if last else 1.0), "finisher": last,
		"hitstop": 0.09 if last else 0.05, "reach": 2.6, "root_motion": true})
	if not last:
		a.cancel_windows = [{"tag": "attack", "from_t": lock * (1.0 - CANCEL_TAIL), "to_t": lock}]
	return a


## [dict] per creature style: default move first. rates are seconds at speed 1.0.
## windup/recovery/reach/damage follow the SPECIES rows (damage is the base; level adds on top).
const CREATURE := {
	"goblin": [
		{"id": "goblin_slash", "anim": "attack", "windup": 0.5, "active": 0.1, "recovery": 0.45 - 0.1, "damage": 6,
			"knockback": 2.0, "reach": 2.2, "poise_damage": 6.0, "weight": 3.0, "max_range": 2.2},
		{"id": "goblin_stab", "anim": "attack", "windup": 0.35, "active": 0.08, "recovery": 0.55, "damage": 4,
			"knockback": 1.0, "reach": 2.6, "poise_damage": 3.0, "weight": 1.5, "max_range": 2.6, "lane": 1},
		{"id": "goblin_hack", "anim": "attack", "windup": 0.7, "active": 0.1, "recovery": 0.6, "damage": 9,
			"knockback": 3.0, "reach": 2.2, "poise_damage": 14.0, "weight": 1.0, "max_range": 2.2, "lane": 0},
	],
	"orc": [
		{"id": "orc_chop", "anim": "attack", "windup": 0.85, "active": 0.12, "recovery": 0.6 - 0.12, "damage": 15,
			"knockback": 3.0, "reach": 2.6, "poise_damage": 20.0, "weight": 3.0, "max_range": 2.6},
		{"id": "orc_backhand", "anim": "attack", "windup": 0.55, "active": 0.1, "recovery": 0.7, "damage": 10,
			"knockback": 2.0, "reach": 2.8, "poise_damage": 12.0, "weight": 1.5, "lane": 1},
		{"id": "orc_overhead", "anim": "attack", "windup": 1.1, "active": 0.12, "recovery": 0.8, "damage": 22,
			"knockback": 5.0, "reach": 2.4, "poise_damage": 32.0, "weight": 1.0, "max_range": 2.4, "lane": 0, "parryable": false},
	],
	"troll": [
		{"id": "troll_smash", "anim": "attack", "windup": 1.1, "active": 0.15, "recovery": 0.8 - 0.15, "damage": 22,
			"knockback": 6.0, "reach": 3.2, "poise_damage": 40.0, "weight": 3.0},
		{"id": "troll_sweep", "anim": "attack", "windup": 0.9, "active": 0.2, "recovery": 0.9, "damage": 16,
			"knockback": 4.0, "reach": 3.6, "poise_damage": 26.0, "weight": 1.5, "lane": 2},
		{"id": "troll_slam", "anim": "attack", "windup": 1.4, "active": 0.15, "recovery": 1.1, "damage": 30,
			"knockback": 8.0, "reach": 3.0, "poise_damage": 60.0, "weight": 0.8, "lane": 0, "unblockable": true, "parryable": false},
	],
	"wolf": [
		{"id": "wolf_bite", "anim": "attack", "windup": 0.5, "active": 0.1, "recovery": 0.35, "damage": 9,
			"knockback": 1.5, "reach": 2.3, "poise_damage": 6.0, "weight": 3.0, "root_motion": false},
		{"id": "wolf_lunge", "anim": "attack", "windup": 0.55, "active": 0.14, "recovery": 0.6, "damage": 11,
			"knockback": 3.0, "reach": 3.2, "poise_damage": 10.0, "weight": 1.0, "max_range": 3.4, "root_motion": true, "lane": 1},
		{"id": "wolf_snap", "anim": "attack", "windup": 0.25, "active": 0.08, "recovery": 0.45, "damage": 5,
			"knockback": 1.0, "reach": 1.8, "poise_damage": 3.0, "weight": 1.5, "max_range": 1.8, "lane": 2, "root_motion": false},
	],
	"bandit": [
		{"id": "bandit_slash", "anim": "Sword_Light_1_Upper", "windup": 0.4, "active": 0.1, "recovery": 0.4, "damage": 10,
			"knockback": 1.5, "reach": 2.4, "poise_damage": 10.0, "weight": 3.0, "anim_speed": 1.0},
		{"id": "bandit_thrust", "anim": "Sword_Light_3_Upper", "windup": 0.3, "active": 0.08, "recovery": 0.5, "damage": 8,
			"knockback": 1.0, "reach": 2.8, "poise_damage": 6.0, "weight": 2.0, "min_range": 1.6, "lane": 1},
		{"id": "bandit_cleave", "anim": "Sword_Light_4_Upper", "windup": 0.65, "active": 0.1, "recovery": 0.6, "damage": 18,
			"knockback": 4.0, "reach": 2.4, "poise_damage": 24.0, "weight": 1.0, "lane": 0},
	],
	"guard": [
		{"id": "guard_cut", "anim": "Sword_Light_1_Upper", "windup": 0.35, "active": 0.1, "recovery": 0.35, "damage": 12,
			"knockback": 1.5, "reach": 2.6, "poise_damage": 12.0, "weight": 3.0},
		{"id": "guard_thrust", "anim": "Sword_Light_3_Upper", "windup": 0.28, "active": 0.08, "recovery": 0.45, "damage": 10,
			"knockback": 1.0, "reach": 3.0, "poise_damage": 8.0, "weight": 2.0, "min_range": 1.8, "lane": 1},
		{"id": "guard_bash", "anim": "Sword_Light_4_Upper", "windup": 0.55, "active": 0.1, "recovery": 0.6, "damage": 14,
			"knockback": 5.0, "reach": 2.2, "poise_damage": 30.0, "weight": 1.0, "lane": 0, "parryable": false},
	],
}


## Ordered combo chain for the player's weapon style ("sword").
static func combo(style: String) -> Array:
	var key := "combo:" + style
	if _cache.has(key):
		return _cache[key]
	var out: Array = []
	if style == "sword":
		for i in SWORD_ROWS.size():
			out.append(_combo_step(style, i, i == SWORD_ROWS.size() - 1, SWORD_ROWS[i],
				Action.Lane.HIGH if i == 0 else Action.Lane.MID))
	_cache[key] = out
	return out


## Move list for a creature/NPC style (default move first).
static func moves(style: String) -> Array:
	var key := "moves:" + style
	if _cache.has(key):
		return _cache[key]
	var out: Array = []
	if style == "sword":
		out = combo("sword")
	else:
		for d: Dictionary in CREATURE.get(style, []):
			var row := d.duplicate()
			row["style"] = style
			if not row.has("hit_at"):
				row["hit_at"] = 0.0    # creature blows land at the end of the windup
			var rec: Resource = _make(row)
			out.append(rec)
	_cache[key] = out
	return out


static func find(style: String, id: String) -> Resource:
	for a: Resource in moves(style):
		if a.id == id:
			return a
	return null


static func styles() -> Array:
	return ["sword"] + CREATURE.keys()
