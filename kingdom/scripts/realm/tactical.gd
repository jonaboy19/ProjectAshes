extends RefCounted
## Tactical battle map (docs/design/WAR_COMMAND_RULEBOOK.md §1, §25-40): a real place of the world reduced to a grid,
## two deployed armies, and a 10 second battle step. Pure data: no scene access, no global rng, no Vector2 in the
## saved state (JSON safe). Everything is deterministic from the seed, so a save can be resumed step for step.
##
## Hot state is kept as structure-of-arrays (PackedFloat32Array...) indexed by unit; serialize() turns it into plain
## arrays. Side 0 is "a", side 1 is "b". Coordinates are metres, local to the grid (0..n*cell), y down.
## The command AI for unplayed sides lives in tactical_ai.gd and uses this API like the player does: orders travel
## by banner, horn or runner (R§20-22) and so arrive late, or never.

const WarUnits := preload("res://scripts/realm/war_units.gd")

const VERSION := 1
const STEP := 10.0                  # seconds per battle step
const MAX_T := 21600.0              # six hours: nightfall
const SPD0 := 1.3                   # m/s of plain infantry at a march
const KILL := 0.0028                # men killed per step per point of effective power (even fight ~0.35 % a step)
const AMMO_STEPS := 110.0           # steps of continuous shooting an archer has
const MANA_STEPS := 34.0
const FLANK_ANG := 1.22             # rad: beyond this off the facing a hit is a flank hit
const REAR_ANG := 2.2
## Fair battles (war3 polish): an attacker picks its approach like the defender picks its ground; to pay for the walk
## in under fire and its piecemeal arrival it carries the initiative (ATTACK_EDGE on its damage, field battles only, not
## sieges); the defender's fortify bonus needs a unit that really holds ground above its attacker. Mirrored even
## 16 v 16 fights now go about 50/50 (they went 10/90 before).
const ATTACK_EDGE := 1.4
var _att_edge := 1.0
const HOLD_HEIGHT := 2.5            # metres above the attacker for the defender's fortify bonus
const STRIDE := 3                   # units take their turn every STRIDE steps (moving STRIDE steps at once)
const _ANGS := [0.6, -0.6, 1.2, -1.2, 1.8, -1.8]
const SEP_EVERY := 12
const ROUND := 3                    # combat resolves every ROUND steps (30 s); movement, sight and orders run every step

# --- terrain codes -------------------------------------------------------------------------------
const T_OPEN := 0
const T_FOREST := 1
const T_HILL := 2
const T_MOUNT := 3
const T_RIVER := 4
const T_FORD := 5
const T_ROAD := 6
const T_BRIDGE := 7
const T_TOWN := 8
const T_MARSH := 9
const T_WALL := 10
const T_GATE := 11
const T_BREACH := 12
const T_BARR := 13
const T_TOWER := 14
const T_RUIN := 15
const T_BLDG := 16
const T_LAND := 17                  # siege tower landing: a wall cell the attackers can cross
const CHARS := ".fhMwdrbtps#gxqTuBl"
const TNAMES := ["Open ground", "Forest", "Hills", "Mountain", "River", "Ford", "Road", "Bridge", "Town", "Marsh", "Wall", "Gate", "Breach", "Barricade", "Tower", "Ruins", "Buildings", "Siege tower"]
var SPEED_T := PackedFloat32Array([1.0, 0.6, 0.75, 0.45, 0.0, 0.3, 1.25, 1.1, 0.9, 0.45, 0.0, 0.0, 0.5, 0.45, 0.0, 0.6, 0.0, 0.3])
var OPAQ_T := PackedFloat32Array([0.0, 0.4, 0.05, 0.25, 0.0, 0.0, 0.0, 0.0, 0.18, 0.05, 1.0, 1.0, 0.0, 0.1, 0.3, 0.12, 0.85, 0.3])
var DEF_T := PackedFloat32Array([1.0, 1.1, 1.15, 1.25, 0.85, 0.85, 0.95, 0.95, 1.2, 0.9, 1.3, 1.3, 1.0, 1.3, 1.4, 1.15, 1.25, 1.0])
var CAV_T := PackedFloat32Array([1.15, 0.7, 0.85, 0.6, 0.5, 0.6, 1.0, 1.0, 0.8, 0.5, 0.3, 0.3, 0.6, 0.4, 0.3, 0.6, 0.3, 0.5])
var RNG_T := PackedFloat32Array([1.1, 0.8, 1.05, 1.0, 0.9, 0.9, 1.0, 1.0, 1.0, 0.9, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 0.9, 1.0])
var FAT_T := PackedFloat32Array([1.0, 1.3, 1.3, 1.6, 1.4, 1.4, 0.8, 0.8, 0.7, 1.5, 1.0, 1.0, 1.3, 1.1, 1.0, 1.1, 1.0, 1.4])
var VIS_T := PackedFloat32Array([1.0, 0.55, 1.2, 1.3, 1.0, 0.9, 1.0, 1.0, 0.7, 0.9, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 0.6, 1.0])
var CAP_T := PackedFloat32Array([1.0, 0.5, 0.7, 0.3, 0.35, 0.35, 0.4, 0.4, 0.4, 0.5, 0.3, 0.3, 0.4, 0.4, 0.3, 0.5, 0.25, 0.35])
var HIDE_T := PackedFloat32Array([0.0, 0.25, 0.1, 0.2, 0.0, 0.05, 0.05, 0.05, 0.1, 0.15, 0.0, 0.0, 0.05, 0.1, 0.0, 0.2, 0.3, 0.0])

# --- unit states ---------------------------------------------------------------------------------
const S_HOLD := 0
const S_MOVE := 1
const S_FIGHT := 2
const S_RETREAT := 3
const S_ROUT := 4
const S_RESERVE := 5
const S_DUEL := 6
const S_DEAD := 7
const S_EXIT := 8
const S_ARRIVE := 9
const STATE_NAMES := ["holding", "moving", "fighting", "retreating", "routing", "reserve", "duelling", "destroyed", "left the field", "arriving"]

const LAYERS := ["front", "second", "third", "rear", "flank_l", "flank_r", "reserve"]
const LAYER_NAMES := {"front": "Front line", "second": "Second line", "third": "Third line", "rear": "Rear", "flank_l": "Left flank", "flank_r": "Right flank", "reserve": "Reserve"}
const LAYER_DEPTH := {"front": 0.0, "second": 58.0, "third": 112.0, "rear": 175.0, "flank_l": 12.0, "flank_r": 12.0, "reserve": 250.0}

## Formations are not buffs (R§25): each one wins something and loses something. width: frontage multiplier.
const FORM := {
	"line": {"name": "Line", "atk": 1.0, "def": 1.0, "mob": 1.0, "vs_cav": 1.0, "vs_rng": 1.0, "width": 1.0, "allround": false, "flank": 1.0, "note": "Balanced; exposed on the flanks."},
	"deep_line": {"name": "Deep line", "atk": 0.95, "def": 1.1, "mob": 0.9, "vs_cav": 1.05, "vs_rng": 1.05, "width": 0.6, "allround": false, "flank": 1.0, "note": "Holds longer, covers less ground."},
	"column": {"name": "Column", "atk": 0.7, "def": 0.7, "mob": 1.35, "vs_cav": 0.7, "vs_rng": 0.9, "width": 0.25, "allround": false, "flank": 1.2, "note": "Fast on roads, helpless when hit."},
	"wedge": {"name": "Wedge", "atk": 1.25, "def": 0.85, "mob": 1.0, "vs_cav": 0.9, "vs_rng": 0.95, "width": 0.45, "allround": false, "flank": 1.15, "note": "Strong charge formation. Effective vs breaking lines."},
	"crescent": {"name": "Crescent", "atk": 1.0, "def": 0.95, "mob": 0.95, "vs_cav": 0.95, "vs_rng": 1.0, "width": 1.3, "allround": false, "flank": 0.9, "note": "Wraps the enemy centre; thin in the middle."},
	"shield": {"name": "Shield wall", "atk": 0.7, "def": 1.15, "mob": 0.55, "vs_cav": 1.1, "vs_rng": 1.6, "width": 0.5, "allround": false, "flank": 1.0, "note": "Shrugs off arrows; slow and weak to hit with."},
	"spear_wall": {"name": "Spear wall", "atk": 0.85, "def": 1.1, "mob": 0.6, "vs_cav": 1.7, "vs_rng": 1.0, "width": 0.9, "allround": false, "flank": 1.0, "note": "Breaks cavalry charges."},
	"loose": {"name": "Loose", "atk": 0.95, "def": 0.95, "mob": 1.25, "vs_cav": 0.8, "vs_rng": 1.3, "width": 1.4, "allround": false, "flank": 0.95, "note": "Skirmish order: fewer arrow losses, poor against horse."},
	"square": {"name": "Defensive square", "atk": 0.8, "def": 1.25, "mob": 0.6, "vs_cav": 1.5, "vs_rng": 1.0, "width": 0.5, "allround": true, "flank": 1.0, "note": "No flanks, no rear; cannot manoeuvre."},
	"circle": {"name": "Circle", "atk": 0.75, "def": 1.2, "mob": 0.6, "vs_cav": 1.3, "vs_rng": 1.05, "width": 0.45, "allround": true, "flank": 1.0, "note": "All-round defence for a cut-off force."},
	"layered": {"name": "Layered defence", "atk": 1.0, "def": 1.12, "mob": 0.85, "vs_cav": 1.1, "vs_rng": 1.05, "width": 1.0, "allround": false, "flank": 1.0, "note": "Lines behind lines; reserves stay close."},
	"encirclement": {"name": "Encirclement", "atk": 0.95, "def": 0.85, "mob": 1.0, "vs_cav": 0.9, "vs_rng": 1.0, "width": 2.0, "allround": false, "flank": 0.9, "note": "Needs numbers: rings the foe to cut off retreat."},
	"reserve_line": {"name": "Reserve line", "atk": 0.8, "def": 1.0, "mob": 1.1, "vs_cav": 1.0, "vs_rng": 1.0, "width": 0.8, "allround": false, "flank": 1.0, "note": "Held back, ready to commit."},
	"custom": {"name": "Custom", "atk": 1.0, "def": 1.0, "mob": 1.0, "vs_cav": 1.0, "vs_rng": 1.0, "width": 1.0, "allround": false, "flank": 1.0, "note": "Your own width, depth and spacing."},
}
const FORM_ORDER := ["line", "wedge", "square", "column", "layered", "loose", "circle", "custom"]
const FORM_ALIAS := {"skirmish": "loose"}

## Behaviours the tactical map adds on top of WarUnits.BEHAVIOURS. engage: seek | accept | avoid.
const EXTRA_BEH := {
	"focus_fire": {"name": "Focus Fire", "needs": "unit", "engage": "accept", "speed": 0.0, "atk": 1.0, "def": 1.0, "fatigue": 0.2, "moves": false},
	"reserve": {"name": "Reserve", "needs": "point", "engage": "accept", "speed": 1.0, "atk": 0.9, "def": 1.0, "fatigue": 0.0, "moves": true},
	"commit": {"name": "Commit Reserve", "needs": "point", "engage": "seek", "speed": 1.1, "atk": 1.05, "def": 0.95, "fatigue": 1.0, "moves": true},
	"feint": {"name": "Feint", "needs": "point", "engage": "avoid", "speed": 1.0, "atk": 0.8, "def": 1.0, "fatigue": 0.8, "moves": true},
	"false_retreat": {"name": "False Retreat", "needs": "point", "engage": "avoid", "speed": 1.05, "atk": 0.7, "def": 0.85, "fatigue": 1.0, "moves": true},
	"hide": {"name": "Hide", "needs": "point", "engage": "avoid", "speed": 0.6, "atk": 0.9, "def": 1.0, "fatigue": 0.6, "moves": true},
	"form_line": {"name": "Form Line", "needs": "none", "engage": "accept", "speed": 0.0, "atk": 1.0, "def": 1.0, "fatigue": 0.0, "moves": false},
	"fallback": {"name": "Fall Back", "needs": "point", "engage": "avoid", "speed": 0.6, "atk": 0.9, "def": 1.05, "fatigue": 1.0, "moves": true},
}
const QUICK_ORDERS := ["hold", "charge", "fallback", "focus_fire", "follow", "screen", "form_line", "advance"]

## Command traditions: near = range (m) at which banners, horns and drums are seen and heard; runner = m/s.
const DOCTRINE := {
	"valencios": {"name": "Valencios", "form": "line", "reserve": 1, "near": 420.0, "runner": 6.7, "fortify": 0.06, "horse_archers": false, "duel": false, "ambush": 0.0, "false_retreat": false,
		"note": "Disciplined infantry, fortifications and combined arms."},
	"steppe": {"name": "Steppe", "form": "loose", "reserve": 0, "near": 380.0, "runner": 8.0, "fortify": 0.0, "horse_archers": true, "duel": true, "ambush": 0.15, "false_retreat": true,
		"note": "Mobility, horse archery and false retreats."},
	"forest": {"name": "Forest", "form": "loose", "reserve": 0, "near": 300.0, "runner": 6.0, "fortify": 0.0, "horse_archers": false, "duel": false, "ambush": 0.5, "false_retreat": false,
		"note": "Ambush, small formations and terrain."},
	"eastern": {"name": "Eastern", "form": "layered", "reserve": 2, "near": 640.0, "runner": 7.2, "fortify": 0.03, "horse_archers": false, "duel": true, "ambush": 0.0, "false_retreat": false,
		"note": "Large coordinated formations, signals and layered reserves."},
}
const FACTION_DOCTRINE := {"caldrenn": "valencios", "seirune_isles": "valencios", "ongur_khanate": "steppe", "solmarch": "valencios", "urrokai_clanlands": "forest",
	"shenlu_peaks": "eastern", "veylwood": "forest", "hollowdeep": "valencios", "player": "valencios", "kingdom": "valencios", "independent": "forest", "bandits": "forest"}
const TIERS := ["weak", "moderate", "advanced", "elite", "legendary"]
const THINK_EVERY := [24, 18, 12, 9, 6]

## Elite individuals (R§39): one man that counts as many. power: men-equivalents; tough: hits it takes.
const ELITE := {
	"champion": {"name": "Champion", "short": "CHP", "power": 380.0, "speed": 1.0, "vision": 250.0, "ranged": false, "mounted": false, "exposure": 0.4, "tough": 55.0, "rng": 0.0},
	"knight": {"name": "Legendary Knight", "short": "KNT", "power": 420.0, "speed": 1.6, "vision": 300.0, "ranged": false, "mounted": true, "exposure": 0.4, "tough": 60.0, "rng": 0.0},
	"bender": {"name": "Master Bender", "short": "BND", "power": 330.0, "speed": 1.0, "vision": 280.0, "ranged": true, "mounted": false, "exposure": 0.3, "tough": 35.0, "rng": 110.0},
	"marksman": {"name": "Marksman", "short": "MRK", "power": 90.0, "speed": 1.0, "vision": 360.0, "ranged": true, "mounted": false, "exposure": 0.3, "tough": 25.0, "rng": 170.0},
}
const RANGE_OF := {"archer": 130.0, "mage": 110.0}


# =================================================================================================
# terrain generation from the real world
# =================================================================================================

static func _hash(a: int, b: int, c: int) -> float:
	var x: int = (a * 73856093) ^ (b * 19349663) ^ (c * 83492791)
	x = (x ^ (x >> 13)) * 1274126177
	x = x ^ (x >> 16)
	return float(x & 0xFFFF) / 65536.0


static func _angdiff(a: float, b: float) -> float:
	return absf(wrapf(a - b, -PI, PI))


## Builds the battlefield around a world position (WorldGen height, slope, roads, rivers, forest, settlements, sites).
## opts: ring {c: Vector2, r, gates: [angles], breaches: [angles], landings: [angles], inner: [{a, span, r}]} for a siege
## assault, street: bool for fighting between houses. Returns {n, cell, center: [x, y], rows: [String], h: [int dm],
## feats: [{kind, name, x, y}], name}. Deterministic for a given world.
static func gen_grid(center: Vector2, n: int, cell: float, opts: Dictionary = {}) -> Dictionary:
	var half := float(n) * cell * 0.5
	var ox := center.x - half
	var oy := center.y - half
	var have := not WorldGen.settlements.is_empty()
	var hs := PackedFloat32Array()
	hs.resize(n * n)
	var sum := 0.0
	if have:
		for j in n:
			for i in n:
				var hv := WorldGen.height(ox + (float(i) + 0.5) * cell, oy + (float(j) + 0.5) * cell)
				hs[j * n + i] = hv
				sum += hv
	var hmean := sum / float(n * n)
	var near_set: Array = []
	var feats: Array = []
	var bridges: Array = []
	var ruins: Array = []
	if have:
		for s: Dictionary in WorldGen.settlements:
			var sp: Vector2 = s["pos"]
			if absf(sp.x - center.x) < half + float(s["radius"]) * 1.3 and absf(sp.y - center.y) < half + float(s["radius"]) * 1.3:
				near_set.append(s)
				feats.append({"kind": String(s["kind"]), "name": String(s["name"]), "x": sp.x - ox, "y": sp.y - oy})
		for st: Dictionary in WorldGen.sites:
			var p2: Vector2 = st["pos"]
			if absf(p2.x - center.x) > half + 40.0 or absf(p2.y - center.y) > half + 40.0:
				continue
			var kd := String(st.get("kind", ""))
			if kd == "bridge":
				bridges.append(p2)
			elif kd in ["tower_ruin", "watchfort", "fort", "rift_outpost"]:
				ruins.append(p2)
			if kd in ["bridge", "tower_ruin", "watchfort", "fort", "rift_outpost", "mine", "bandit_camp", "academy", "shrine"]:
				feats.append({"kind": kd, "name": String(st.get("name", kd)), "x": p2.x - ox, "y": p2.y - oy})
	var fine := cell <= 20.0
	var chars := PackedStringArray()
	var rows: Array = []
	var counts := PackedInt32Array()
	counts.resize(CHARS.length())
	var ring: Dictionary = opts.get("ring", {})
	for j in n:
		chars.clear()
		for i in n:
			var x := ox + (float(i) + 0.5) * cell
			var y := oy + (float(j) + 0.5) * cell
			var code := T_OPEN
			if have:
				if absf(x) > 4096.0 or absf(y) > 4096.0:
					code = T_MOUNT
				else:
					code = _classify(x, y, i, j, n, cell, hs, hmean, near_set, bridges, fine)
				for rp: Vector2 in ruins:
					if absf(rp.x - x) < cell * 0.7 + 10.0 and absf(rp.y - y) < cell * 0.7 + 10.0 and code in [T_OPEN, T_FOREST, T_HILL]:
						code = T_RUIN
			if not ring.is_empty():
				code = _ring_code(code, x, y, cell, ring, i, j, bool(opts.get("street", true)))
			elif bool(opts.get("street", false)):
				code = _street_code(x, y, i, j)
			counts[code] += 1
			chars.append(CHARS[code])
		rows.append("".join(chars))
	var h: Array = []
	for k in n * n:
		h.append(int(round(hs[k] * 10.0)))
	var tot := float(n * n)
	var nm := "Open Field"
	var wet := float(counts[T_RIVER] + counts[T_FORD] + counts[T_BRIDGE]) / tot
	if float(counts[T_WALL] + counts[T_BREACH] + counts[T_GATE]) > 0.0:
		nm = "Walls and Breach" if counts[T_BREACH] > 0 else "Fortress Walls"
	elif float(counts[T_TOWN] + counts[T_BLDG]) / tot > 0.25:
		nm = "Town Streets"
	elif wet > 0.06 and (counts[T_FORD] + counts[T_BRIDGE]) > 0:
		nm = "River Crossing"
	elif float(counts[T_FOREST]) / tot > 0.3:
		nm = "Forest (Narrow)"
	elif float(counts[T_HILL] + counts[T_MOUNT]) / tot > 0.3:
		nm = "Hill Ground"
	elif float(counts[T_MARSH]) / tot > 0.12:
		nm = "Marshland"
	elif float(counts[T_FOREST]) / tot > 0.12:
		nm = "Open Field and Woods"
	var cc: Array = []
	for k2 in counts.size():
		cc.append(int(counts[k2]))
	return {"n": n, "cell": cell, "center": [center.x, center.y], "rows": rows, "h": h, "feats": feats, "name": nm, "counts": cc}


static func _classify(x: float, y: float, i: int, j: int, n: int, cell: float, hs: PackedFloat32Array, hmean: float, near_set: Array, bridges: Array, fine: bool) -> int:
	var p := Vector2(x, y)
	for s: Dictionary in near_set:
		var d := p.distance_to(s["pos"])
		if d < float(s["radius"]) * 1.1:
			var plan: Dictionary = s.get("plan", {})
			if bool(plan.get("walls", false)) and absf(d - float(plan.get("wall_radius", s["radius"]))) < cell * 0.5:
				var ang := atan2(y - float((s["pos"] as Vector2).y), x - float((s["pos"] as Vector2).x))
				for g in (plan.get("gates", []) as Array):
					if _angdiff(ang, float(g)) < maxf(0.12, cell / maxf(d, 1.0)):
						return T_GATE
				return T_WALL
			if fine and WorldGen.street_distance(x, y) > 6.0 and _hash(i, j, 7) < 0.55:
				return T_BLDG
			return T_TOWN
	var depth := WorldGen.water_depth(x, y)
	var rd := WorldGen.road_distance(x, y)
	if depth > 0.0:
		if rd < cell * 0.5:
			return T_BRIDGE
		for b: Vector2 in bridges:
			if absf(b.x - x) < cell * 0.9 and absf(b.y - y) < cell * 0.9:
				return T_BRIDGE
		return T_FORD if depth < 0.9 else T_RIVER
	if rd < cell * 0.55:
		return T_ROAD
	var il := maxi(i - 1, 0)
	var ir := mini(i + 1, n - 1)
	var jt := maxi(j - 1, 0)
	var jb := mini(j + 1, n - 1)
	var gx := (hs[j * n + ir] - hs[j * n + il]) / (cell * float(ir - il))
	var gy := (hs[jb * n + i] - hs[jt * n + i]) / (cell * float(jb - jt))
	var slope := sqrt(gx * gx + gy * gy)
	var hv := hs[j * n + i]
	if slope < 0.12 and hv < hmean + 3.0 and WorldGen.near_water(x, y, cell * 0.55):
		return T_MARSH
	if hv > 105.0 or slope > 1.05:
		return T_MOUNT
	if slope > 0.5 or hv > hmean + 14.0:
		return T_HILL
	if WorldGen.forest_density(x, y) > 0.5:
		return T_FOREST
	return T_OPEN


## Wall ring of a besieged place: walls, gates, breaches, landings, the town inside and the defenders' inner lines (R§45-46).
static func _ring_code(base: int, x: float, y: float, cell: float, ring: Dictionary, i: int, j: int, street: bool) -> int:
	var c := _v2(ring["c"])
	var r := float(ring["r"])
	var d := Vector2(x, y).distance_to(c)
	var ang := atan2(y - c.y, x - c.x)
	var w := maxf(cell * 0.65, 4.0)
	var tol := maxf(0.14, cell * 1.4 / maxf(r, 1.0))
	for inn in (ring.get("inner", []) as Array):
		var dd := inn as Dictionary
		if absf(d - float(dd["r"])) <= cell * 0.6 and _angdiff(ang, float(dd["a"])) < float(dd["span"]) and d < r - w:
			return T_BARR
	if absf(d - r) <= w:
		for b in (ring.get("breaches", []) as Array):
			if _angdiff(ang, float(b)) < tol * 1.3:
				return T_BREACH
		for l in (ring.get("landings", []) as Array):
			if _angdiff(ang, float(l)) < tol * 0.8:
				return T_LAND
		for g in (ring.get("gates", []) as Array):
			if _angdiff(ang, float(g)) < tol:
				return T_GATE
		var tw := int(round(ang / (TAU / 10.0)))
		if absf(ang - float(tw) * (TAU / 10.0)) < tol * 0.6:
			return T_TOWER
		return T_WALL
	if d < r - w:
		if street and base != T_BLDG and _hash(i, j, 11) < 0.42 and Vector2(x, y).distance_to(c) > r * 0.12:
			return T_BLDG
		return T_TOWN
	if base in [T_RIVER, T_FOREST, T_MOUNT]:
		return T_OPEN if d < r + cell * 5.0 else base
	return base


static func _street_code(x: float, y: float, i: int, j: int) -> int:
	var lane_x := (i % 5 == 2)
	var lane_y := (j % 5 == 2)
	if lane_x or lane_y or _hash(i, j, 3) < 0.12:
		return T_TOWN
	return T_BLDG


static func _v2(v: Variant) -> Vector2:
	if v is Vector2:
		return v
	var a: Array = v
	return Vector2(float(a[0]), float(a[1]))


# =================================================================================================
# state
# =================================================================================================

var seed := 0
var name := "Battle"
var phase := "deploy"               # deploy | battle | ended
var t := 0.0                        # battle seconds
var step_no := 0
var n := 40
var cell := 40.0
var world_c := Vector2.ZERO
var terrain_name := "Open Field"
var weather := "clear"
var season := "spring"
var hour := 10
var night := false
var attacker := 0
var feats: Array = []
var opts: Dictionary = {}
var rows: Array = []
var tc := PackedByteArray()
var hh := PackedFloat32Array()
var S: Array = [{}, {}]             # per side: faction, player, cmd, doctrine, tier, hq, axis, anchor, ...
var events: Array = []              # {t, kind, text, side}
var orders_log: Array = []          # what the issuer knows: {id, side, unit, label, sent, due, via, status}
var duels: Array = []
var incoming: Array = []            # reinforcements on the way: {side, units: [spec], due, edge}
var result := {}
var auto := [true, true]            # AI commands this side (false while the player is at the table)
var think := [9, 9]
var ctx_factors := {}               # campaign factor record at the start (same logic as WarUnits.side_power)

var u_side := PackedInt32Array()
var u_pw := PackedFloat32Array()
var u_spd := PackedFloat32Array()
var u_vis := PackedFloat32Array()
var u_rng := PackedFloat32Array()
var u_mnt := PackedInt32Array()
var u_rad := PackedFloat32Array()
var u_tough := PackedFloat32Array()
var u_men := PackedFloat32Array()
var u_men0 := PackedFloat32Array()
var u_q := PackedFloat32Array()
var u_mor := PackedFloat32Array()
var u_fat := PackedFloat32Array()
var u_ammo := PackedFloat32Array()
var u_x := PackedFloat32Array()
var u_y := PackedFloat32Array()
var u_face := PackedFloat32Array()
var u_tx := PackedFloat32Array()
var u_ty := PackedFloat32Array()
var u_st := PackedInt32Array()
var u_tgt := PackedInt32Array()
var u_bh := PackedInt32Array()
var u_fm := PackedInt32Array()
var u_hid := PackedInt32Array()
var u_chg := PackedInt32Array()
var u_seen := PackedInt32Array()
var u_cas := PackedFloat32Array()
var u_cid := PackedInt32Array()
var u_due := PackedFloat32Array()
var u_lsx := PackedFloat32Array()
var u_lsy := PackedFloat32Array()
var u_lst := PackedFloat32Array()
var u_rth := PackedFloat32Array()
var u_cls := PackedInt32Array()
var u_hitt := PackedFloat32Array()  # time of the last damage taken
var u_dq := PackedFloat32Array()    # defensive quality
var u_eq := PackedFloat32Array()    # offensive quality
var u_meta_surr := PackedInt32Array()
var u_acq := PackedInt32Array()     # step at which the unit looks for a new target
var u_v0 := PackedFloat32Array()    # metres per step of a march on open ground
var u_meta: Array = []              # {name, kind, layer, order, wp, elite, ...}

var _bh_names: Array = []
var _bh_atk := PackedFloat32Array()
var _bh_def := PackedFloat32Array()
var _bh_spd := PackedFloat32Array()
var _bh_fat := PackedFloat32Array()
var _bh_eng := PackedInt32Array()
var _bh_mov := PackedInt32Array()
var _bh_kind := PackedInt32Array()
var _al := [PackedInt32Array(), PackedInt32Array()]
var _fm_names: Array = []
var _fm_atk := PackedFloat32Array()
var _fm_def := PackedFloat32Array()
var _fm_mob := PackedFloat32Array()
var _fm_cav := PackedFloat32Array()
var _fm_rng := PackedFloat32Array()
var _fm_width := PackedFloat32Array()
var _fm_all := PackedInt32Array()
var _fm_flank := PackedFloat32Array()
var _b_hold := 0
var _b_ambush := 0
var _b_hide := 0
var _b_charge := 0
var _b_reserve := 0
var _b_focus := 0
var _b_intercept := 0
var _sig: Array = []
var _next_sig := 1
var _path_cache: Dictionary = {}
var _dk := PackedFloat32Array()
var _dm := PackedFloat32Array()
var _dflag := PackedInt32Array()
var _wx: Dictionary = {}
var _last_kill_t := 0.0
var _last_act_t := 0.0
var _ai: RefCounted = null


func _init() -> void:
	var all := {}
	for k: String in WarUnits.BEHAVIOURS:
		all[k] = WarUnits.BEHAVIOURS[k]
	for k2: String in EXTRA_BEH:
		all[k2] = EXTRA_BEH[k2]
	for k3: String in all:
		var b: Dictionary = all[k3]
		_bh_names.append(k3)
		_bh_atk.append(1.0 + 0.6 * (float(b["atk"]) - 1.0))
		_bh_def.append(1.0 + 0.6 * (float(b["def"]) - 1.0))
		_bh_spd.append(float(b["speed"]))
		_bh_fat.append(float(b["fatigue"]))
		_bh_eng.append(0 if String(b["engage"]) == "seek" else (1 if String(b["engage"]) == "accept" else 2))
		_bh_mov.append(1 if bool(b["moves"]) else 0)
		var kd := 6
		if k3 in ["hold", "attack_if_attacked", "focus_fire", "form_line", "ambush"]:
			kd = 0
		elif k3 in ["advance", "charge", "intercept", "commit"]:
			kd = 1
		elif k3 == "flank":
			kd = 2
		elif k3 in ["capture", "march", "defend", "screen", "reserve"]:
			kd = 3
		elif k3 in ["escort", "follow"]:
			kd = 4
		elif k3 == "harass":
			kd = 5
		elif k3 == "avoid":
			kd = 7
		_bh_kind.append(kd)
	for k4: String in FORM:
		var f: Dictionary = FORM[k4]
		_fm_names.append(k4)
		_fm_atk.append(float(f["atk"]))
		_fm_def.append(float(f["def"]))
		_fm_mob.append(float(f["mob"]))
		_fm_cav.append(float(f["vs_cav"]))
		_fm_rng.append(float(f["vs_rng"]))
		_fm_width.append(float(f["width"]))
		_fm_all.append(1 if bool(f["allround"]) else 0)
		_fm_flank.append(float(f["flank"]))
	for row: Array in PREF:
		for v in row:
			_pref.append(float(v))
	_b_hold = _bh_names.find("hold")
	_b_ambush = _bh_names.find("ambush")
	_b_hide = _bh_names.find("hide")
	_b_charge = _bh_names.find("charge")
	_b_reserve = _bh_names.find("reserve")
	_b_focus = _bh_names.find("focus_fire")
	_b_intercept = _bh_names.find("intercept")
	_ai = load("res://scripts/realm/tactical_ai.gd").new()


static func beh(b: String) -> Dictionary:
	if EXTRA_BEH.has(b):
		return EXTRA_BEH[b]
	return WarUnits.behaviour(b)


static func form_key(f: String) -> String:
	f = String(FORM_ALIAS.get(f, f))
	return f if FORM.has(f) else "line"


## Stats shown in the formation editor (R§25). custom derives from width (men per rank), depth and spacing.
static func formation_stats(f: String, width := 12, depth := 3, spacing := 1.0, ranged_behind := true, cav_support := true) -> Dictionary:
	var d: Dictionary = (FORM[form_key(f)] as Dictionary).duplicate()
	if form_key(f) == "custom":
		var dp := clampf(float(depth), 1.0, 8.0)
		var wd := clampf(float(width), 4.0, 40.0)
		var sp := clampf(spacing, 0.6, 2.5)
		d["def"] = clampf(0.85 + 0.06 * (dp - 1.0) - 0.05 * (sp - 1.0), 0.6, 1.4)
		d["atk"] = clampf(0.8 + 0.05 * minf(dp, 4.0) + 0.04 * minf(wd / 12.0, 2.0) - 0.05 * (sp - 1.0), 0.6, 1.4)
		d["mob"] = clampf(1.15 - 0.06 * (dp - 1.0) + 0.12 * (sp - 1.0), 0.4, 1.5)
		d["vs_cav"] = clampf(0.8 + 0.1 * dp - 0.2 * (sp - 1.0), 0.5, 1.6)
		d["vs_rng"] = clampf(0.85 + 0.25 * (sp - 1.0) * 0.0 + (0.3 if sp > 1.4 else 0.0) + (0.05 * dp if sp < 0.9 else 0.0), 0.6, 1.6)
		d["width"] = clampf(wd * sp / 12.0, 0.2, 2.5)
	d["ranged_behind"] = ranged_behind
	d["cav_support"] = cav_support
	return d


static func tier_of(attrs: Dictionary, skill := 2) -> int:
	var tac := float(attrs.get("tactics", 22.0 + 13.0 * float(skill)))
	var exp_ := float(attrs.get("experience", tac))
	var sc := tac * 0.7 + exp_ * 0.3
	if bool(attrs.get("legend", false)):
		return 4
	if sc < 42.0:
		return 0
	if sc < 56.0:
		return 1
	if sc < 68.0:
		return 2
	if sc < 82.0:
		return 3
	return 4


static func doctrine_of(faction: String) -> String:
	return String(FACTION_DOCTRINE.get(faction, "valencios"))


## Season decides the weather of the day (R§37); the same seed always gives the same sky.
static func roll_weather(season_: String, campaign_weather: String, sd: int) -> String:
	if campaign_weather != "" and campaign_weather != "clear":
		return campaign_weather
	var r := _hash(sd, 17, 3)
	match season_:
		"winter":
			return "snow" if r < 0.3 else ("fog" if r < 0.42 else ("storm" if r < 0.47 else "clear"))
		"autumn":
			return "rain" if r < 0.25 else ("fog" if r < 0.42 else ("storm" if r < 0.48 else "clear"))
		"summer":
			return "heat" if r < 0.18 else ("storm" if r < 0.23 else ("rain" if r < 0.3 else "clear"))
		_:
			return "rain" if r < 0.22 else ("fog" if r < 0.3 else "clear")


# --- creation --------------------------------------------------------------------------------------

## spec: {seed, name, center: [x, y] (world), n, cell, weather, season, hour, attacker: "a"|"b", surprise: ""|"a"|"b",
##        deploy: bool, opts: {...gen_grid opts}, sides: {a: side spec, b: side spec}, factors: {...}}
## side spec: {faction, player, name, cmd: {name, personality, skill, tactics, leadership, ...}, doctrine, supply,
##        axis (rad, optional), anchor ([x, y] local, optional), zone_w, dscale, formation, units: [...], elites: [...]}
## unit spec: {cid, name, kind, men, quality, morale, fatigue, wx, wy, layer, formation}
static func create(spec: Dictionary) -> RefCounted:
	var tt: RefCounted = load("res://scripts/realm/tactical.gd").new()
	tt.call("_setup", spec)
	return tt


func _setup(spec: Dictionary) -> void:
	seed = int(spec.get("seed", 1))
	name = String(spec.get("name", "Battle"))
	var ctr: Array = spec.get("center", [0.0, 0.0])
	world_c = Vector2(float(ctr[0]), float(ctr[1]))
	n = int(spec.get("n", 40))
	cell = float(spec.get("cell", 40.0))
	season = String(spec.get("season", "spring"))
	weather = roll_weather(season, String(spec.get("weather", "clear")), seed)
	hour = int(spec.get("hour", 10))
	night = hour < 5 or hour >= 21
	attacker = 0 if String(spec.get("attacker", "a")) == "a" else 1
	ctx_factors = (spec.get("factors", {}) as Dictionary).duplicate(true)
	_wx = WarUnits.WEATHER.get(weather, WarUnits.WEATHER["clear"])
	var go: Dictionary = (spec.get("opts", {}) as Dictionary).duplicate(true)
	var g := gen_grid(world_c, n, cell, go)
	_load_grid(g)
	opts = {}
	if go.has("ring"):
		var rg: Dictionary = (go["ring"] as Dictionary).duplicate(true)
		var c2 := _v2(rg["c"]) - (world_c - Vector2(float(n) * cell * 0.5, float(n) * cell * 0.5))
		rg["c"] = [c2.x, c2.y]
		opts["ring"] = rg
	if go.has("street"):
		opts["street"] = bool(go["street"])
	_att_edge = 1.0 if go.has("ring") else ATTACK_EDGE
	var sides: Dictionary = spec.get("sides", {})
	for k in 2:
		var key := "a" if k == 0 else "b"
		_setup_side(k, (sides.get(key, {}) as Dictionary))
	_compute_axes(sides)
	for k2 in 2:
		var key2 := "a" if k2 == 0 else "b"
		var sd: Dictionary = sides.get(key2, {})
		for us in (sd.get("units", []) as Array):
			add_unit(k2, us as Dictionary)
		for es in (sd.get("elites", []) as Array):
			add_unit(k2, es as Dictionary)
	var sur := String(spec.get("surprise", ""))
	if sur != "":
		S[0 if sur == "a" else 1]["surprise"] = 1.25
		S[1 if sur == "a" else 0]["surprise"] = 0.85
	for k3 in 2:
		auto_layers(k3)
		layout(k3)
	for k4 in 2:
		if not bool(S[k4]["player"]):
			_ai.call("deploy", self, k4)
	phase = "deploy" if bool(spec.get("deploy", true)) else "battle"
	if phase == "battle":
		begin()
	_log("Battle begins at %s. %s, %s." % [name, TNAMES[T_OPEN] if terrain_name == "" else terrain_name, weather], "start", -1)


func _load_grid(g: Dictionary) -> void:
	n = int(g["n"])
	cell = float(g["cell"])
	rows = (g["rows"] as Array).duplicate()
	feats = (g["feats"] as Array).duplicate(true)
	terrain_name = String(g["name"])
	tc.resize(n * n)
	hh.resize(n * n)
	for j in n:
		var row: String = rows[j]
		for i in n:
			var code := CHARS.find(row[i])
			tc[j * n + i] = maxi(code, 0)
	var hz: Array = g["h"]
	for k in n * n:
		hh[k] = float(hz[k]) * 0.1


func _setup_side(k: int, sd: Dictionary) -> void:
	var cmd: Dictionary = (sd.get("cmd", {}) as Dictionary).duplicate(true)
	var skill := int(cmd.get("skill", 2))
	for a: String in WarUnits.ATTRS:
		if not cmd.has(a):
			cmd[a] = 22 + 13 * skill
	var fac := String(sd.get("faction", "kingdom"))
	var doc := String(sd.get("doctrine", doctrine_of(fac)))
	var tier := int(sd.get("tier", tier_of(cmd, skill)))
	var dd: Dictionary = DOCTRINE.get(doc, DOCTRINE["valencios"])
	S[k] = {"faction": fac, "name": String(sd.get("name", fac)), "player": bool(sd.get("player", false)), "cmd": cmd, "doctrine": doc, "tier": tier,
		"hq": [0.0, 0.0], "hq_hp": 1.0, "axis": 0.0, "anchor": [0.0, 0.0], "zone_w": float(sd.get("zone_w", 420.0)), "dscale": float(sd.get("dscale", 1.0)),
		"supply": float(sd.get("supply", 3.0)), "surprise": 1.0, "retreat": false, "collapse": false, "exit": [0.0, 0.0], "formation": String(sd.get("formation", dd["form"])),
		"near": float(dd["near"]), "runner": float(dd["runner"]), "men0": 0, "ai": {}, "ranged_behind": bool(sd.get("ranged_behind", true)),
		"cav_support": bool(sd.get("cav_support", true)), "fixed_axis": sd.has("axis"), "fixed_anchor": sd.has("anchor"),
		"cmdf": WarUnits.command_factor(cmd), "supf": WarUnits.supply_factor(float(sd.get("supply", 3.0))), "duel_ok": bool(dd["duel"]), "fortify": float(dd["fortify"]), "name_short": String(sd.get("name", fac))}
	if sd.has("axis"):
		S[k]["axis"] = float(sd["axis"])
	if sd.has("anchor"):
		S[k]["anchor"] = (sd["anchor"] as Array).duplicate()
	auto[k] = not bool(S[k]["player"])
	think[k] = int(THINK_EVERY[clampi(tier, 0, 4)])


## Axis a -> b: from where the armies really came on the campaign map.
func _compute_axes(sides: Dictionary) -> void:
	var cen: Array = [Vector2.ZERO, Vector2.ZERO]
	var cnt := [0.0, 0.0]
	for k in 2:
		var sd: Dictionary = sides.get("a" if k == 0 else "b", {})
		for us in (sd.get("units", []) as Array):
			var u := us as Dictionary
			if u.has("wx"):
				cen[k] = (cen[k] as Vector2) + Vector2(float(u["wx"]), float(u["wy"])) * float(u.get("men", 1))
				cnt[k] = float(cnt[k]) + float(u.get("men", 1))
	var ax := 0.0
	var have := false
	if float(cnt[0]) > 0.0 and float(cnt[1]) > 0.0:
		var d := (cen[1] as Vector2) / float(cnt[1]) - (cen[0] as Vector2) / float(cnt[0])
		if d.length() > 40.0:
			ax = d.angle()
			have = true
	if not have:
		ax = _hash(seed, 5, 9) * TAU
	var half := float(n) * cell * 0.5
	var dep := minf(520.0, half * 0.66)
	var cc := Vector2(half, half)
	for k2 in 2:
		var dirv := Vector2.from_angle(ax + (PI if k2 == 1 else 0.0))   # toward the enemy
		if not bool(S[k2]["fixed_axis"]):
			S[k2]["axis"] = ax + (PI if k2 == 1 else 0.0)
		if not bool(S[k2]["fixed_anchor"]):
			var an := cc - dirv * dep
			an = _best_anchor(an, dirv, dep)
			S[k2]["anchor"] = [an.x, an.y]
		var axis_v := Vector2.from_angle(float(S[k2]["axis"]))
		var anc := _v2(S[k2]["anchor"])
		var hq := anc - axis_v * (260.0 * float(S[k2]["dscale"]) + 40.0)
		hq = _nudge(_clamp_in(hq), 6)
		S[k2]["hq"] = [hq.x, hq.y]
		var ex := _clamp_in(anc - axis_v * 4000.0)
		S[k2]["exit"] = [ex.x, ex.y]


func _clamp_in(p: Vector2) -> Vector2:
	var m := float(n) * cell - 12.0
	return Vector2(clampf(p.x, 12.0, m), clampf(p.y, 12.0, m))


## The defender picks the best ground within reach of its line: high, dry and open.
func _best_anchor(base: Vector2, dirv: Vector2, dep: float) -> Vector2:
	var best := base
	var bs := -1e9
	for off in [-140.0, -70.0, 0.0, 70.0, 140.0]:
		var p := _clamp_in(base + dirv * float(off))
		var code := int(tc[cell_idx(p.x, p.y)])
		var sc := h_at(p.x, p.y) + 6.0 * float(code == T_HILL) - 60.0 * float(SPEED_T[code] <= 0.0) - 18.0 * float(code in [T_MARSH, T_FORD]) - absf(float(off)) * 0.02
		if sc > bs:
			bs = sc
			best = p
	return best


func _army_label(k: int) -> String:
	var nm := String((S[k] as Dictionary)["name"])
	return nm if nm == "Your army" else nm + "'s army"


func _log(text: String, kind := "info", side := -1) -> void:
	events.append({"t": t, "kind": kind, "text": text, "side": side})
	if events.size() > 120:
		events.pop_front()


# --- grid access -----------------------------------------------------------------------------------

func size_m() -> float:
	return float(n) * cell


func cell_idx(x: float, y: float) -> int:
	var i := clampi(int(x / cell), 0, n - 1)
	var j := clampi(int(y / cell), 0, n - 1)
	return j * n + i


func code_at(x: float, y: float) -> int:
	return int(tc[cell_idx(x, y)])


func h_at(x: float, y: float) -> float:
	return hh[cell_idx(x, y)]


func passable(code: int) -> bool:
	return SPEED_T[code] > 0.0


## Nearest walkable spot to p (spiral over cells).
func _nudge(p: Vector2, rings: int) -> Vector2:
	if SPEED_T[code_at(p.x, p.y)] > 0.0:
		return p
	for r in range(1, rings + 1):
		for a in 8:
			var q := _clamp_in(p + Vector2.from_angle(float(a) * PI * 0.25) * float(r) * cell)
			if SPEED_T[code_at(q.x, q.y)] > 0.0:
				return q
	return p


# =================================================================================================
# units and deployment (R§25-27)
# =================================================================================================

func unit_count() -> int:
	return u_side.size()


func side_units(k: int, alive_only := true) -> Array:
	var out: Array = []
	for i in u_side.size():
		if u_side[i] == k and (not alive_only or u_st[i] < S_DEAD):
			out.append(i)
	return out


func _cls_of(kind: String) -> int:
	match kind:
		"infantry":
			return 0
		"spear":
			return 1
		"archer":
			return 2
		"heavy_cav", "light_cav":
			return 3
		"mage":
			return 6
		"champion", "knight", "bender", "marksman":
			return 5
	return 4


func add_unit(k: int, spec: Dictionary) -> int:
	var kind := String(spec.get("kind", "infantry"))
	var elite := ELITE.has(kind)
	var kd: Dictionary = ELITE[kind] if elite else WarUnits.kind(kind)
	var men := float(spec.get("men", 1 if elite else 100))
	var q := clampf(float(spec.get("quality", 0.6)), 0.05, 1.0)
	var doc: Dictionary = DOCTRINE.get(String((S[k] as Dictionary).get("doctrine", "valencios")), DOCTRINE["valencios"])
	var rng := float(kd.get("rng", RANGE_OF.get(kind, 0.0)))
	if kind == "light_cav" and bool(doc["horse_archers"]):
		rng = 75.0
	var form := form_key(String(spec.get("formation", "")))
	if not spec.has("formation") or String(spec.get("formation", "")) == "":
		form = form_key(String((S[k] as Dictionary)["formation"]))
		if kind in ["archer", "mage", "engineer", "medical", "scout", "light_cav"]:
			form = "loose"
		elif kind == "heavy_cav":
			form = "wedge"
		elif kind == "spear" and String((S[k] as Dictionary)["doctrine"]) == "valencios":
			form = "spear_wall"
	var rad := 5.0 if elite else minf(40.0, 5.0 + sqrt(maxf(men, 1.0)) * 0.8)
	u_side.append(k)
	u_pw.append(float(kd["power"]))
	u_spd.append(float(kd["speed"]))
	u_vis.append(float(kd["vision"]))
	u_rng.append(rng)
	u_mnt.append(1 if bool(kd["mounted"]) else 0)
	u_rad.append(rad)
	u_tough.append(float(kd.get("tough", 1.0)))
	u_men.append(men)
	u_men0.append(men)
	u_q.append(q)
	u_mor.append(clampf(float(spec.get("morale", 0.7)), 0.0, 1.0))
	u_fat.append(clampf(float(spec.get("fatigue", 0.0)), 0.0, 1.0))
	u_ammo.append(1.0)
	u_x.append(0.0)
	u_y.append(0.0)
	u_face.append(0.0)
	u_tx.append(0.0)
	u_ty.append(0.0)
	if elite:
		_has_elite = true
	var arrive := spec.has("due")
	u_st.append(S_ARRIVE if arrive else S_HOLD)
	u_tgt.append(-1)
	u_bh.append(_bh_names.find("hold"))
	u_fm.append(_fm_names.find(form))
	u_hid.append(0)
	u_chg.append(0)
	u_seen.append(0)
	u_cas.append(0.0)
	u_cid.append(int(spec.get("cid", 0)))
	u_due.append(float(spec.get("due", 0.0)))
	u_lsx.append(0.0)
	u_lsy.append(0.0)
	u_lst.append(-1.0)
	u_rth.append(0.04 if elite else clampf(0.22 - 0.08 * (q - 0.5), 0.12, 0.27))
	u_cls.append(_cls_of(kind))
	u_hitt.append(-999.0)
	u_acq.append(0)
	u_dq.append(pow(0.6 + 0.8 * q, 0.6))
	u_eq.append(0.6 + 0.8 * q)
	u_meta_surr.append(0)
	u_v0.append(SPD0 * float(kd["speed"]) * STEP)
	u_meta.append({"name": String(spec.get("name", kd["name"])), "kind": kind, "layer": String(spec.get("layer", "")), "order": {"behavior": "hold", "since": 0.0},
		"wp": [], "elite": elite, "wx": float(spec.get("wx", 0.0)), "wy": float(spec.get("wy", 0.0)), "note": "", "bait": false, "role": String(spec.get("role", "")), "hero": bool(spec.get("hero", false))})
	_dk.append(0.0)
	_dm.append(0.0)
	_dflag.append(0)
	(S[k] as Dictionary)["men0"] = int((S[k] as Dictionary)["men0"]) + int(round(men))
	return u_side.size() - 1


## Puts every unit of a side that has no layer yet into the rulebook's depth layers (R§26-27):
## shields in front, spears behind, archers third, mages and trains at the rear, cavalry on the flanks, veterans in reserve.
func auto_layers(k: int, force := false) -> void:
	var st: Dictionary = S[k]
	var doc: Dictionary = DOCTRINE.get(String(st["doctrine"]), DOCTRINE["valencios"])
	var inf: Array = []
	var spr: Array = []
	var cav: Array = []
	var ids := side_units(k, false)
	for i: int in ids:
		var m: Dictionary = u_meta[i]
		if not force and String(m["layer"]) != "":
			continue
		var kind := String(m["kind"])
		match kind:
			"infantry":
				inf.append(i)
			"spear":
				spr.append(i)
			"archer":
				m["layer"] = "third" if bool(st["ranged_behind"]) else "second"
			"mage", "engineer", "medical":
				m["layer"] = "rear"
			"heavy_cav", "light_cav":
				cav.append(i)
			"scout":
				m["layer"] = "flank_l"
			"champion":
				m["layer"] = "front"
			"knight":
				m["layer"] = "flank_r"
			"bender", "marksman":
				m["layer"] = "third"
			_:
				m["layer"] = "second"
	var q_desc := func(a: int, b: int) -> bool: return u_q[a] * u_men[a] > u_q[b] * u_men[b]
	inf.sort_custom(q_desc)
	spr.sort_custom(q_desc)
	var res_n := mini(int(doc["reserve"]), 2) if inf.size() + spr.size() >= 3 else 0
	var pool: Array = inf + spr
	var res_ids: Array = []
	if res_n > 0 and not pool.is_empty():
		for r in mini(res_n, pool.size()):
			res_ids.append(pool[r])
	for i2: int in res_ids:
		(u_meta[i2] as Dictionary)["layer"] = "reserve"
		u_fm[i2] = _fm_names.find("reserve_line")
	inf = inf.filter(func(x: int) -> bool: return not res_ids.has(x))
	spr = spr.filter(func(x: int) -> bool: return not res_ids.has(x))
	var nfront := maxi(1, int(ceil(0.55 * float(inf.size())))) if not inf.is_empty() else 0
	for r2 in inf.size():
		(u_meta[inf[r2]] as Dictionary)["layer"] = "front" if r2 < nfront else "second"
	for i3: int in spr:
		(u_meta[i3] as Dictionary)["layer"] = "second" if not inf.is_empty() else "front"
	var flip := 0
	for i4: int in cav:
		if not bool(st["cav_support"]):
			(u_meta[i4] as Dictionary)["layer"] = "reserve"
		else:
			(u_meta[i4] as Dictionary)["layer"] = "flank_l" if flip % 2 == 0 else "flank_r"
			flip += 1
	var has_front := false
	for i5: int in ids:
		if String((u_meta[i5] as Dictionary)["layer"]) == "front":
			has_front = true
	if not has_front and not ids.is_empty():
		var bi := -1
		for i6: int in ids:
			if int(u_cls[i6]) in [0, 1] and (bi < 0 or u_men[i6] > u_men[bi]):
				bi = i6
		if bi < 0:
			bi = ids[0]
		(u_meta[bi] as Dictionary)["layer"] = "front"


## Places a side's units on its deployment line by layer (R§26): centre-out, flanks outside, reserve far back.
func layout(k: int) -> void:
	var st: Dictionary = S[k]
	var ax := Vector2.from_angle(float(st["axis"]))
	var pv := Vector2(-ax.y, ax.x)
	var anc := _v2(st["anchor"])
	var dsc := float(st["dscale"])
	var zw := float(st["zone_w"])
	var by := {}
	for l: String in LAYERS:
		by[l] = []
	for i in u_side.size():
		if u_side[i] == k and u_st[i] < S_DEAD and u_st[i] != S_ARRIVE:
			var ly := String((u_meta[i] as Dictionary)["layer"])
			if not by.has(ly):
				ly = "second"
			(by[ly] as Array).append(i)
	var front_w := 0.0
	for layer: String in ["front", "second", "third", "rear", "reserve"]:
		var lst: Array = by[layer]
		if lst.is_empty():
			continue
		lst.sort_custom(func(a: int, b: int) -> bool: return u_q[a] * u_men[a] > u_q[b] * u_men[b])
		var order: Array = []
		for idx in lst.size():
			if idx % 2 == 0:
				order.push_back(lst[idx])
			else:
				order.push_front(lst[idx])
		var widths: Array = []
		var total := 0.0
		for i: int in order:
			var wd := 2.0 * u_rad[i] * clampf(_fm_width[u_fm[i]], 0.7, 1.5) + 8.0 * dsc
			widths.append(wd)
			total += wd
		var rows_n := int(ceil(total / maxf(2.0 * zw, 1.0)))
		rows_n = maxi(rows_n, 1)
		var per_row := int(ceil(float(order.size()) / float(rows_n)))
		var depth := float(LAYER_DEPTH[layer]) * dsc
		for r in rows_n:
			var sub: Array = order.slice(r * per_row, (r + 1) * per_row)
			var sw := 0.0
			for q in sub.size():
				sw += float(widths[r * per_row + q])
			if layer == "front":
				front_w = maxf(front_w, sw)
			var cur := -sw * 0.5
			for q2 in sub.size():
				var i2: int = sub[q2]
				var wd2: float = float(widths[r * per_row + q2])
				var lat := cur + wd2 * 0.5
				cur += wd2
				var p := anc - ax * (depth + float(r) * 52.0 * dsc) + pv * lat
				_place(i2, p, float(st["axis"]), layer == "reserve")
	var half := maxf(front_w * 0.5, 130.0 * dsc)
	for fl: String in ["flank_l", "flank_r"]:
		var lst2: Array = by[fl]
		var sgn := -1.0 if fl == "flank_l" else 1.0
		var off := half + 40.0 * dsc
		for i3: int in lst2:
			off += u_rad[i3] + 4.0
			var p2 := anc - ax * (float(LAYER_DEPTH[fl]) * dsc) + pv * sgn * off
			_place(i3, p2, float(st["axis"]), false)
			off += u_rad[i3] + 6.0


func _place(i: int, p: Vector2, face: float, reserve: bool) -> void:
	var q := _nudge(_clamp_in(p), 6)
	u_x[i] = q.x
	u_y[i] = q.y
	u_tx[i] = q.x
	u_ty[i] = q.y
	u_face[i] = face
	u_st[i] = S_RESERVE if reserve else S_HOLD
	u_tgt[i] = -1
	u_bh[i] = _bh_names.find("reserve" if reserve else "hold")
	(u_meta[i] as Dictionary)["order"] = {"behavior": "reserve" if reserve else "hold", "since": t}
	(u_meta[i] as Dictionary)["wp"] = []


## Drag during deployment: the piece may stand anywhere on its side of the field, behind its own line.
func deploy_move(i: int, x: float, y: float) -> bool:
	if phase != "deploy" or i < 0 or i >= u_side.size() or u_st[i] >= S_DEAD:
		return false
	var k := int(u_side[i])
	var st: Dictionary = S[k]
	var ax := Vector2.from_angle(float(st["axis"]))
	var pv := Vector2(-ax.y, ax.x)
	var anc := _v2(st["anchor"])
	var rel := Vector2(x, y) - anc
	var along := rel.dot(ax)
	var lat := rel.dot(pv)
	var dsc := float(st["dscale"])
	along = clampf(along, -420.0 * dsc, 20.0 * dsc)
	lat = clampf(lat, -float(st["zone_w"]) * 1.6, float(st["zone_w"]) * 1.6)
	var p := anc + ax * along + pv * lat
	if SPEED_T[code_at(p.x, p.y)] <= 0.0:
		return false
	_place(i, p, float(st["axis"]), String((u_meta[i] as Dictionary)["layer"]) == "reserve")
	return true


func set_layer(i: int, layer: String) -> void:
	if i < 0 or i >= u_side.size() or not LAYERS.has(layer):
		return
	(u_meta[i] as Dictionary)["layer"] = layer
	if phase == "deploy":
		layout(int(u_side[i]))


func set_formation(i: int, f: String) -> bool:
	if i < 0 or i >= u_side.size() or u_st[i] >= S_DEAD:
		return false
	var fk := form_key(f)
	var before := u_fm[i]
	u_fm[i] = _fm_names.find(fk)
	if phase == "battle" and before != u_fm[i]:
		u_fat[i] = minf(1.0, u_fat[i] + 0.03)
	(u_meta[i] as Dictionary)["custom"] = {} if fk != "custom" else (u_meta[i] as Dictionary).get("custom", {"width": 12, "depth": 3, "spacing": 1.0})
	return true


## Auto arrange: clears the layers and lays the side out again by the rulebook.
func auto_arrange(k: int) -> void:
	auto_layers(k, true)
	for i in side_units(k, false):
		if String((u_meta[i] as Dictionary)["kind"]) in ["archer"]:
			pass
	layout(k)


func _refresh_alive() -> void:
	var a0: PackedInt32Array = _al[0]
	var a1: PackedInt32Array = _al[1]
	a0.clear()
	a1.clear()
	for i in u_side.size():
		if u_st[i] < S_DEAD:
			if u_side[i] == 0:
				a0.append(i)
			else:
				a1.append(i)


func begin() -> void:
	if phase == "battle":
		return
	phase = "battle"
	t = 0.0
	step_no = 0
	for k in 2:
		auto[k] = not bool((S[k] as Dictionary)["player"]) or bool(auto[k])
	_refresh_alive()
	_vision()
	_log("The armies advance on %s." % terrain_name, "begin", -1)


# =================================================================================================
# the battle step (every 10 s): signals, vision, AI, movement, contact, morale, duels, end
# =================================================================================================

## Target preference: attacker class (row) x target class (column) -> multiplier on squared distance.
## 0 infantry, 1 spear, 2 archer, 3 cavalry, 4 support (scouts, engineers, medics), 5 elite, 6 mage.
const PREF := [
	[1.0, 1.0, 0.9, 0.85, 0.8, 0.8, 0.85],
	[1.0, 1.0, 1.0, 0.6, 1.0, 0.8, 1.0],
	[1.0, 1.0, 0.8, 0.9, 1.1, 0.4, 0.6],
	[1.1, 3.5, 0.55, 1.2, 0.4, 1.0, 0.5],
	[1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0],
	[1.0, 1.3, 0.8, 0.9, 0.7, 0.3, 0.7],
	[1.0, 1.0, 0.8, 0.9, 1.0, 0.4, 0.6],
]


var ui_attached := false            # the player is at the table: campaign hours do not advance this battle
var _has_elite := false
var profile := false
var perf: Dictionary = {}           # microseconds per phase when profile is on (diagnostics)


func _pf(key: String, t0: int) -> int:
	var now := Time.get_ticks_usec()
	perf[key] = int(perf.get(key, 0)) + now - t0
	return now


var _pref := PackedFloat32Array()


func step() -> void:
	if phase != "battle":
		return
	var p0 := Time.get_ticks_usec() if profile else 0
	t += STEP
	step_no += 1
	if not _sig.is_empty():
		_deliver()
	if step_no % ROUND == 1:
		_refresh_alive()
	if step_no % 18 == 1:
		_vision()
	if profile:
		p0 = _pf("sig+vision", p0)
	for k in 2:
		if bool(auto[k]) and (step_no + k * 2) % int(think[k]) == 0:
			_ai.call("think", self, k)
	if profile:
		p0 = _pf("ai", p0)
	var nu := u_side.size()
	_arrivals(nu)
	_units(nu)
	if profile:
		p0 = _pf("units", p0)
	if step_no % ROUND == 0:
		_combat(nu)
		if profile:
			p0 = _pf("combat", p0)
		_morale(nu)
		if profile:
			p0 = _pf("morale", p0)
	if step_no % 12 == 3:
		_encircle(nu)
	if _has_elite and (not duels.is_empty() or step_no % 3 == 0):
		_duel_step(nu)
	if step_no % 6 == 0:
		_check_end(nu)
	if profile:
		p0 = _pf("rest", p0)


func advance(steps: int) -> int:
	var done := 0
	while done < steps and phase == "battle":
		step()
		done += 1
	return done


## Plays the whole battle out with both commanders' AI (campaign hours the player is not at the table, tests).
func run_to_end(max_steps := 2200) -> Dictionary:
	if phase == "deploy":
		begin()
	var keep: Array = auto.duplicate()
	auto = [true, true]
	var k := 0
	while phase == "battle" and k < max_steps:
		step()
		k += 1
	auto = keep
	if phase == "battle":
		_finish(-1, "Both sides drew apart at nightfall.")
	return result


func _arrivals(nu: int) -> void:
	for i in nu:
		if u_st[i] == S_ARRIVE and u_due[i] <= t:
			var k := int(u_side[i])
			var st: Dictionary = S[k]
			var ax := Vector2.from_angle(float(st["axis"]))
			var pv := Vector2(-ax.y, ax.x)
			var hq := _v2(st["hq"])
			var lat := (float(i % 7) - 3.0) * 38.0
			var p := _nudge(_clamp_in(hq + pv * lat - ax * 20.0), 6)
			u_x[i] = p.x
			u_y[i] = p.y
			u_face[i] = float(st["axis"])
			u_st[i] = S_HOLD
			u_tx[i] = _v2(st["anchor"]).x
			u_ty[i] = _v2(st["anchor"]).y
			u_bh[i] = _bh_names.find("advance")
			(u_meta[i] as Dictionary)["order"] = {"behavior": "advance", "x": u_tx[i], "y": u_ty[i], "since": t}
			_log("%s has reached the field." % String((u_meta[i] as Dictionary)["name"]), "arrive", k)


func _units(nu: int) -> void:
	var wmove := float(_wx["move"]) * (0.85 if night else 1.0)
	var size_l := size_m()
	var sn := step_no
	var inv := 1.0 / cell
	var nn := n
	var stf := float(STRIDE)
	for i in range(sn % STRIDE, nu, STRIDE):
		var st := u_st[i]
		if st >= S_DEAD or st == S_DUEL:
			continue
		var x := u_x[i]
		var y := u_y[i]
		var code := int(tc[clampi(int(y * inv), 0, nn - 1) * nn + clampi(int(x * inv), 0, nn - 1)])
		if st == S_ROUT or st == S_RETREAT:
			_flee(i, st, x, y, code, wmove, size_l)
			continue
		var bh := u_bh[i]
		var bk: int = _bh_kind[bh]
		var eng: int = _bh_eng[bh]
		var side := u_side[i]
		if st == S_RESERVE and eng == 0:
			eng = 1
		var tg := u_tgt[i]
		if tg >= 0 and u_st[tg] >= S_DEAD:
			tg = -1
		if tg < 0 or sn >= u_acq[i]:
			tg = _acquire(i, side, x, y, eng, bh)
			u_acq[i] = sn + (8 if tg >= 0 else 2)
			u_tgt[i] = tg
		var ranged := u_rng[i] > 0.0 and u_ammo[i] > 0.0
		var dtg2 := 1.0e12
		var reach := 0.0
		var tdx := 0.0
		var tdy := 0.0
		if tg >= 0:
			tdx = u_x[tg] - x
			tdy = u_y[tg] - y
			dtg2 = tdx * tdx + tdy * tdy
			reach = u_rad[i] + u_rad[tg] + 8.0
			if st == S_FIGHT and (bk < 5) and (dtg2 <= reach * reach or (ranged and dtg2 <= u_rng[i] * u_rng[i])) and (bk != 2 or bh != _b_hide):
				# locked in combat: nothing to decide between rounds
				continue
		if bk == 0 and tg < 0:
			if u_hid[i] == 1 or bh == _b_ambush or bh == _b_hide:
				_cover(i, bh, false)
			if st != S_HOLD and st != S_RESERVE:
				u_st[i] = S_HOLD
			continue
		var dest_x := u_tx[i]
		var dest_y := u_ty[i]
		var stop := 10.0
		var go := _bh_mov[bh] == 1
		var speed_b := _bh_spd[bh]
		var away := false
		var meta: Dictionary
		var has_meta := false
		if bk == 1:
			if tg >= 0:
				dest_x = u_x[tg]
				dest_y = u_y[tg]
				stop = (u_rng[i] * 0.8) if ranged else reach * 0.85
				if bh == _b_charge and dtg2 < 67600.0 and u_mnt[i] == 1:
					speed_b *= 1.35
		elif bk == 2:
			meta = u_meta[i]
			has_meta = true
			if tg >= 0 and bool(meta.get("fl", false)):
				dest_x = u_x[tg]
				dest_y = u_y[tg]
				stop = (u_rng[i] * 0.8) if ranged else reach * 0.85
			else:
				var fdx := dest_x - x
				var fdy := dest_y - y
				if fdx * fdx + fdy * fdy < 1600.0 or (tg >= 0 and dtg2 < 28900.0):
					meta["fl"] = true
		elif bk == 3:
			if tg >= 0 and (dtg2 <= reach * reach or (ranged and dtg2 <= u_rng[i] * u_rng[i])):
				go = false
		elif bk == 4:
			meta = u_meta[i]
			has_meta = true
			var ot := int((meta["order"] as Dictionary).get("target", -1))
			if ot >= 0 and ot < nu and u_st[ot] < S_DEAD:
				dest_x = u_x[ot]
				dest_y = u_y[ot]
				stop = 70.0
			if tg >= 0 and (dtg2 <= reach * reach or (ranged and dtg2 <= u_rng[i] * u_rng[i])):
				go = false
		elif bk == 5:
			if tg >= 0:
				var dtg := sqrt(dtg2)
				if ranged:
					if dtg < u_rng[i] * 0.45:
						away = true
					elif dtg > u_rng[i] * 0.9:
						dest_x = u_x[tg]
						dest_y = u_y[tg]
						stop = u_rng[i] * 0.85
					else:
						go = false
				else:
					meta = u_meta[i]
					has_meta = true
					if t < float(meta.get("cool", 0.0)):
						away = true
					else:
						dest_x = u_x[tg]
						dest_y = u_y[tg]
						stop = reach * 0.9
		elif bk == 7:
			if tg >= 0 and dtg2 < 102400.0:
				away = true
		elif bk == 0:
			go = false
		var moved := false
		if go or away:
			var dx := dest_x - x
			var dy := dest_y - y
			if away and tg >= 0:
				dx = -tdx
				dy = -tdy
			var wpn := 0
			if not away and (bk != 1 or tg < 0):
				if not has_meta:
					meta = u_meta[i]
					has_meta = true
				var wp: Array = meta["wp"]
				wpn = wp.size()
				if wpn > 0:
					var w0: Vector2 = wp[0]
					dx = w0.x - x
					dy = w0.y - y
					if dx * dx + dy * dy < 400.0:
						wp.remove_at(0)
						if not wp.is_empty():
							w0 = wp[0]
							dx = w0.x - x
							dy = w0.y - y
					stop = minf(stop, 8.0) if not wp.is_empty() else stop
			var dd2 := dx * dx + dy * dy
			if dd2 > stop * stop or away:
				var dd := sqrt(dd2)
				var sp := SPEED_T[code]
				if u_mnt[i] == 1 and code != T_OPEN and code != T_ROAD:
					sp *= clampf(CAV_T[code], 0.5, 1.0)
				var v := stf * u_v0[i] * speed_b * sp * wmove * (1.0 - 0.35 * u_fat[i]) * _fm_mob[u_fm[i]]
				if dd > 0.001 and v > 0.0:
					var stepl := v if away else minf(v, dd - stop)
					if stepl > 0.0:
						var ux := dx / dd
						var uy := dy / dd
						var nx := x + ux * stepl
						var ny := y + uy * stepl
						var cxn := int(nx * inv)
						var cyn := int(ny * inv)
						var ok := nx > 4.0 and ny > 4.0 and nx < size_l - 4.0 and ny < size_l - 4.0 and SPEED_T[int(tc[cyn * nn + cxn])] > 0.0
						if not ok:
							for ang in _ANGS:
								var cs := cos(ang)
								var sn2 := sin(ang)
								var px := x + (ux * cs - uy * sn2) * stepl
								var py := y + (ux * sn2 + uy * cs) * stepl
								if px > 4.0 and py > 4.0 and px < size_l - 4.0 and py < size_l - 4.0 and SPEED_T[int(tc[cell_idx(px, py)])] > 0.0:
									nx = px
									ny = py
									ok = true
									break
						if ok:
							u_x[i] = nx
							u_y[i] = ny
							moved = true
							u_face[i] = atan2(ny - y, nx - x)
						elif wpn > 0:
							(u_meta[i] as Dictionary)["wp"].clear()
		var fighting := false
		if tg >= 0:
			var ddx := u_x[tg] - u_x[i]
			var ddy := u_y[tg] - u_y[i]
			var dn2 := ddx * ddx + ddy * ddy
			if dn2 <= reach * reach or (ranged and dn2 <= u_rng[i] * u_rng[i]):
				fighting = true
				if _fm_all[u_fm[i]] == 0 and not (bk == 5 and not ranged):
					u_face[i] = atan2(ddy, ddx)
		if fighting:
			if st != S_FIGHT and u_mnt[i] == 1 and (bk == 1 or bk == 2):
				u_chg[i] = 1
			if bk == 5 and u_rng[i] <= 0.0:
				(u_meta[i] as Dictionary)["cool"] = t + 50.0
			u_st[i] = S_FIGHT
		elif moved:
			u_st[i] = S_MOVE
		else:
			u_st[i] = S_RESERVE if (u_bh[i] == _b_reserve or (st == S_RESERVE and bk == 0)) else S_HOLD
		if u_hid[i] == 1 or bh == _b_ambush or bh == _b_hide:
			_cover(i, bh, fighting, tg, moved)
	if step_no % SEP_EVERY == 0:
		_separate(nu)


## Units told to ambush or hide vanish into forest, ruins and broken ground; attacking or marching breaks cover.
func _cover(i: int, bh: int, fighting: bool, tg := -1, moved := false) -> void:
	if bh == _b_ambush or bh == _b_hide:
		var cov := HIDE_T[code_at(u_x[i], u_y[i])] >= 0.1
		u_hid[i] = 1 if (cov and not (fighting and u_hid[i] == 0)) else 0
		if fighting and u_hid[i] == 1 and tg >= 0:
			u_hid[i] = 0
			if ((u_seen[i] >> (1 - int(u_side[i]))) & 1) == 0:
				_ambush_hit(i, tg)
	elif fighting or moved:
		u_hid[i] = 0


func _ambush_hit(i: int, tg: int) -> void:
	u_chg[i] = 3
	u_mor[tg] = maxf(0.0, u_mor[tg] - 0.07)
	_log("%s springs an ambush on %s." % [String((u_meta[i] as Dictionary)["name"]), String((u_meta[tg] as Dictionary)["name"])], "ambush", int(u_side[i]))


func _separate(nu: int) -> void:
	for i in nu:
		if u_st[i] != S_MOVE:
			continue
		for j in _al[u_side[i]]:
			if j == i or u_st[j] == S_FIGHT:
				continue
			var dx: float = u_x[j] - u_x[i]
			var dy: float = u_y[j] - u_y[i]
			var lim: float = (u_rad[i] + u_rad[j]) * 0.75
			var d2: float = dx * dx + dy * dy
			if d2 < lim * lim and d2 > 0.01:
				var d := sqrt(d2)
				var push := (lim - d) * 0.45
				var px := dx / d * push
				var py := dy / d * push
				if SPEED_T[code_at(u_x[i] - px, u_y[i] - py)] > 0.0:
					u_x[i] -= px
					u_y[i] -= py
				if SPEED_T[code_at(u_x[j] + px, u_y[j] + py)] > 0.0:
					u_x[j] += px
					u_y[j] += py


func _acquire(i: int, side: int, x: float, y: float, eng: int, bh: int) -> int:
	var ranged := u_rng[i] > 0.0 and u_ammo[i] > 0.0
	var lim: float
	if eng == 0:
		lim = minf(u_vis[i] * 1.3, 620.0)
	elif eng == 1:
		lim = (u_rng[i] + 10.0) if ranged else (u_rad[i] + 38.0)
	else:
		lim = u_rng[i] if ranged else u_rad[i] + 38.0
	if u_st[i] == S_RESERVE:
		lim = minf(lim, u_rad[i] + 60.0)
	if bh == _b_focus or bh == _b_intercept:
		var ft := int((u_meta[i]["order"] as Dictionary).get("target", -1))
		if ft >= 0 and ft < u_side.size() and u_st[ft] < S_DEAD and u_side[ft] != side:
			var fdx := u_x[ft] - x
			var fdy := u_y[ft] - y
			if fdx * fdx + fdy * fdy < 640000.0 and ((u_seen[ft] >> side) & 1) == 1:
				return ft
	var lim2 := lim * lim
	var best := -1
	var bs := 1.0e30
	var prow := int(u_cls[i]) * 7
	var bit := side
	var lst: PackedInt32Array = _al[1 - side]
	for j in lst:
		var dx := u_x[j] - x
		if dx > lim or dx < -lim:
			continue
		var dy := u_y[j] - y
		if dy > lim or dy < -lim:
			continue
		var d2 := dx * dx + dy * dy
		if d2 > lim2 or u_st[j] >= S_DEAD:
			continue
		if d2 > 8100.0 and ((u_seen[j] >> bit) & 1) == 0:
			continue
		var sc: float = d2 * _pref[prow + u_cls[j]]
		if sc < bs:
			bs = sc
			best = j
	return best


func _flee(i: int, st: int, x: float, y: float, code: int, wmove: float, size_l: float) -> void:
	var side := u_side[i]
	var ex: float
	var ey: float
	var meta: Dictionary = u_meta[i]
	var rout := st == S_ROUT
	if rout:
		var e := _v2((S[side] as Dictionary)["exit"])
		ex = e.x
		ey = e.y
	else:
		ex = u_tx[i]
		ey = u_ty[i]
	var dx := ex - x
	var dy := ey - y
	var d := sqrt(dx * dx + dy * dy)
	if d > 1.0:
		var sp := maxf(SPEED_T[code], 0.35)
		var v := float(STRIDE) * SPD0 * u_spd[i] * (1.3 if rout else _bh_spd[u_bh[i]]) * sp * wmove * (1.0 - 0.2 * u_fat[i]) * STEP
		var surr := bool(meta.get("surr", false))
		if surr:
			v *= 0.3
		var stepl := minf(v, d)
		var nx := x + dx / d * stepl
		var ny := y + dy / d * stepl
		if SPEED_T[int(tc[cell_idx(nx, ny)])] <= 0.0:
			for ang in [0.7, -0.7, 1.4, -1.4]:
				var cs := cos(ang)
				var sn := sin(ang)
				var px := x + (dx / d * cs - dy / d * sn) * stepl
				var py := y + (dx / d * sn + dy / d * cs) * stepl
				if SPEED_T[int(tc[cell_idx(px, py)])] > 0.0:
					nx = px
					ny = py
					break
		u_x[i] = clampf(nx, 2.0, size_l - 2.0)
		u_y[i] = clampf(ny, 2.0, size_l - 2.0)
		u_face[i] = atan2(dy, dx)
	var at_edge := u_x[i] < 22.0 or u_y[i] < 22.0 or u_x[i] > size_l - 22.0 or u_y[i] > size_l - 22.0
	var goal := d < 25.0 or (at_edge and (rout or d < 600.0))
	if goal and (rout or Vector2(ex, ey).distance_to(_v2((S[side] as Dictionary)["exit"])) < 30.0):
		u_st[i] = S_EXIT
		u_tgt[i] = -1
		_log("%s has left the field." % String(meta["name"]), "exit", int(side))
	elif goal:
		u_st[i] = S_HOLD
		u_bh[i] = _bh_names.find("hold")
	if rout and u_st[i] == S_ROUT and step_no % 2 == 0:
		var lst: PackedInt32Array = _al[1 - side]
		for j in lst:
			if u_st[j] == S_ROUT:
				continue
			var ddx := u_x[j] - u_x[i]
			var ddy := u_y[j] - u_y[i]
			if ddx * ddx + ddy * ddy < 2500.0 and (u_mnt[j] == 1 or _bh_eng[u_bh[j]] == 0):
				var loss := u_men[i] * (0.014 if u_mnt[j] == 1 else 0.005)
				u_men[i] = maxf(0.0, u_men[i] - loss)
				u_cas[i] += loss
				if u_men[i] < 0.5:
					u_st[i] = S_DEAD
				break
	if rout and u_st[i] == S_ROUT and step_no % 6 == 0 and u_mor[i] > 0.38 and not bool((S[side] as Dictionary)["retreat"]):
		var near_foe := false
		var lst2: PackedInt32Array = _al[1 - side]
		for j2 in lst2:
			var ex2 := u_x[j2] - u_x[i]
			var ey2 := u_y[j2] - u_y[i]
			if ex2 * ex2 + ey2 * ey2 < 48400.0:
				near_foe = true
				break
		if not near_foe:
			u_st[i] = S_HOLD
			u_bh[i] = _bh_names.find("hold")
			u_tx[i] = u_x[i]
			u_ty[i] = u_y[i]
			(u_meta[i] as Dictionary)["order"] = {"behavior": "hold", "since": t}
			_log("%s has rallied." % String(meta["name"]), "rally", int(side))


func _combat(nu: int) -> void:
	_dk.fill(0.0)
	_dflag.fill(0)
	var wall := float(_wx["all"])
	var wr := float(_wx["ranged"])
	var rm := float(ROUND)
	var sf := [0.0, 0.0]
	var fort := [0.0, 0.0]
	for k in 2:
		var sd: Dictionary = S[k]
		sf[k] = float(sd["cmdf"]) * float(sd["supf"]) * wall * (float(sd["surprise"]) if step_no <= 12 else 1.0) * (_att_edge if k == attacker else 1.0)
		fort[k] = float(sd["fortify"]) * minf(1.0, t / 900.0)
	for i0 in nu:
		if u_st[i0] == S_FIGHT and u_tgt[i0] >= 0 and _fm_all[u_fm[i0]] == 0 and _bh_kind[u_bh[i0]] != 5:
			var t0 := u_tgt[i0]
			u_face[i0] = atan2(u_y[t0] - u_y[i0], u_x[t0] - u_x[i0])
	for i in nu:
		if u_st[i] != S_FIGHT:
			continue
		var tg := u_tgt[i]
		if tg < 0 or u_st[tg] >= S_DEAD:
			continue
		var xi := u_x[i]
		var yi := u_y[i]
		var dx := u_x[tg] - xi
		var dy := u_y[tg] - yi
		var d2 := dx * dx + dy * dy
		var reach := u_rad[i] + u_rad[tg] + 8.0
		var shoot := false
		var rg := u_rng[i]
		if rg > 0.0 and u_ammo[i] > 0.0 and d2 > reach * reach and d2 <= rg * rg:
			shoot = true
			if d2 > 1600.0 and _blocked(xi, yi, u_x[tg], u_y[tg]):
				continue
		elif d2 > reach * reach:
			continue
		var ci := cell_idx(xi, yi)
		var code := int(tc[ci])
		var men := u_men[i]
		var fmi := u_fm[i]
		var fm := men
		if not shoot and u_cls[i] != 5:
			var capm := 350.0 * CAP_T[code]
			if men > capm:
				fm = capm + 0.35 * (men - capm)
		var eff: float = fm * u_pw[i] * u_eq[i] * (0.55 + 0.9 * u_mor[i]) * (1.0 - 0.45 * u_fat[i]) * _bh_atk[u_bh[i]] * _fm_atk[fmi] * sf[u_side[i]]
		var fmj := u_fm[tg]
		var defm := 1.0
		if u_mnt[i] == 1:
			eff *= CAV_T[code]
			defm *= _fm_cav[fmj]
			if u_chg[i] > 0:
				eff *= 2.0
				u_chg[i] -= 1
		if shoot:
			var d := sqrt(d2)
			eff *= RNG_T[code] * wr * (1.0 - 0.4 * d / rg)
			defm *= _fm_rng[fmj]
			u_ammo[i] = maxf(0.0, u_ammo[i] - rm / (MANA_STEPS if (u_cls[i] == 6 or u_cls[i] == 5) else AMMO_STEPS))
		elif rg > 0.0 and u_ammo[i] <= 0.0:
			eff *= 0.4
		if u_cls[i] == 1 and u_mnt[tg] == 1:
			eff *= 1.5
		var angm := 1.0
		var level := 1
		if not shoot and _fm_all[fmj] == 0:
			var diff := absf(wrapf(atan2(dy, dx) + PI - u_face[tg], -PI, PI))
			if diff > REAR_ANG:
				angm = 1.7 * _fm_flank[fmj]
				level = 3
			elif diff > FLANK_ANG:
				angm = 1.35 * _fm_flank[fmj]
				level = 2
		var cj := cell_idx(u_x[tg], u_y[tg])
		var hm := 1.0 + 0.08 * clampf((hh[ci] - hh[cj]) / 6.0, -1.0, 1.0)
		var dj: float = u_dq[tg] * _bh_def[u_bh[tg]] * _fm_def[fmj] * DEF_T[int(tc[cj])] * defm
		# the defender's ground bonus is earned: it needs a unit that stands its ground and really sits above its attacker
		if fort[u_side[tg]] > 0.0 and (u_st[tg] == S_HOLD or u_st[tg] == S_FIGHT) and hh[cj] - hh[ci] >= HOLD_HEIGHT:
			dj *= 1.0 + fort[u_side[tg]]
		var varn := 0.92 + 0.16 * _hash(step_no, i, seed)
		_last_act_t = t
		var kills: float = rm * KILL * eff * angm * hm * varn / maxf(dj, 0.2)
		if u_meta_surr[tg] == 1:
			kills *= 1.18
		_dk[tg] += kills
		if level > _dflag[tg]:
			_dflag[tg] = level


## Damage and morale, fatigue, rout and side collapse (once per combat round).
func _morale(nu: int) -> void:
	var fat_w := float(_wx["fatigue"])
	var rm := float(ROUND)
	var routed_now: Array = []
	# a hero (the player's champion) in the line steadies everyone within 200 m
	var heroes: Array = []
	if _has_elite:
		for h in nu:
			if u_st[h] < S_DEAD and bool((u_meta[h] as Dictionary).get("hero", false)):
				heroes.append(h)
	for i in nu:
		var st := u_st[i]
		if st >= S_DEAD:
			continue
		var k := _dk[i]
		var men := u_men[i]
		var frac := 0.0
		var elite := u_cls[i] == 5
		if k > 0.0:
			var loss := minf(men, k / u_tough[i])
			frac = loss / maxf(men, 0.001)
			u_men[i] = men - loss
			u_cas[i] += loss
			u_hitt[i] = t
			_last_kill_t = t
			if u_men[i] < (0.03 if elite else 0.5):
				_kill(i)
				continue
		var mor := u_mor[i] - (0.4 if elite else 2.4) * frac
		var fl := _dflag[i]
		if fl == 2:
			mor -= 0.004 * rm
		elif fl == 3:
			mor -= 0.012 * rm
		if u_meta_surr[i] == 1:
			mor -= 0.008 * rm
		if k <= 0.0 and st != S_FIGHT:
			mor += 0.003 * rm
		for h2: int in heroes:
			if u_side[h2] == u_side[i] and h2 != i:
				var hx := u_x[h2] - u_x[i]
				var hy := u_y[h2] - u_y[i]
				if hx * hx + hy * hy < 40000.0:
					mor += 0.0025 * rm
					break
		mor = clampf(mor, 0.0, 1.0)
		u_mor[i] = mor
		if st == S_FIGHT:
			u_fat[i] = minf(1.0, u_fat[i] + 0.0035 * maxf(_bh_fat[u_bh[i]], 0.5) * fat_w * rm)
		elif st == S_MOVE:
			u_fat[i] = minf(1.0, u_fat[i] + 0.0012 * _bh_fat[u_bh[i]] * FAT_T[int(tc[cell_idx(u_x[i], u_y[i])])] * fat_w * rm)
		elif st == S_HOLD or st == S_RESERVE:
			u_fat[i] = maxf(0.0, u_fat[i] - 0.0018 * rm)
		if mor < u_rth[i] and st != S_ROUT and st != S_RETREAT:
			routed_now.append(i)
	for r: int in routed_now:
		_rout(r)
	if step_no % (ROUND * 2) == 0:
		for k2 in 2:
			_check_break(k2, nu)
			_hq_step(k2, nu)


func _kill(i: int) -> void:
	u_st[i] = S_DEAD
	u_men[i] = 0.0
	u_tgt[i] = -1
	var m: Dictionary = u_meta[i]
	var k := int(u_side[i])
	if bool(m["elite"]):
		_log("%s has fallen." % String(m["name"]), "elite_dead", k)
		for j in u_side.size():
			if u_st[j] < S_DEAD:
				var dx := u_x[j] - u_x[i]
				var dy := u_y[j] - u_y[i]
				if dx * dx + dy * dy < 160000.0:
					u_mor[j] = clampf(u_mor[j] + (-0.07 if u_side[j] == k else 0.05), 0.0, 1.0)
	else:
		_log("%s has been destroyed." % String(m["name"]), "destroyed", k)
		for j2 in u_side.size():
			if u_st[j2] < S_DEAD and u_side[j2] == k:
				var dx2 := u_x[j2] - u_x[i]
				var dy2 := u_y[j2] - u_y[i]
				if dx2 * dx2 + dy2 * dy2 < 40000.0:
					u_mor[j2] = maxf(0.0, u_mor[j2] - 0.05)


func _rout(i: int) -> void:
	u_st[i] = S_ROUT
	u_tgt[i] = -1
	u_hid[i] = 0
	var k := int(u_side[i])
	_log("%s is routing!" % String((u_meta[i] as Dictionary)["name"]), "rout", k)
	for j in u_side.size():
		if u_st[j] >= S_DEAD or j == i:
			continue
		var dx := u_x[j] - u_x[i]
		var dy := u_y[j] - u_y[i]
		if dx * dx + dy * dy < 22500.0:
			u_mor[j] = clampf(u_mor[j] + (-0.05 if u_side[j] == k else 0.03), 0.0, 1.0)


func side_morale(k: int) -> float:
	var m := 0.0
	var men := 0.0
	for i in u_side.size():
		if u_side[i] == k and u_st[i] < S_DEAD and u_cls[i] != 5:
			m += u_mor[i] * u_men[i]
			men += u_men[i]
	return m / maxf(men, 1.0)


func side_men(k: int, include_routed := true) -> float:
	var men := 0.0
	for i in u_side.size():
		if u_side[i] == k and u_st[i] < S_DEAD and (include_routed or u_st[i] != S_ROUT):
			men += u_men[i]
	return men


func _check_break(k: int, _nu: int) -> void:
	var sd: Dictionary = S[k]
	if bool(sd["retreat"]) or phase != "battle":
		return
	var men := side_men(k)
	var mor := side_morale(k)
	var pers := String((sd["cmd"] as Dictionary).get("personality", "loyal"))
	var thr := float(WarUnits.BREAK_MORALE.get(pers, 0.2))
	if not bool(auto[k]):
		thr = 0.08
	if step_no < 18:
		return
	if mor < thr or men < 0.25 * float(sd["men0"]) - 0.001 * float(sd["men0"]):
		order_retreat(k, "%s's commander orders a general retreat." % String(sd["name"]))


func order_retreat(k: int, why := "") -> void:
	var sd: Dictionary = S[k]
	if bool(sd["retreat"]):
		return
	sd["retreat"] = true
	var e := _v2(sd["exit"])
	for i in u_side.size():
		if u_side[i] == k and u_st[i] < S_DEAD and u_st[i] != S_ROUT and u_st[i] != S_DUEL:
			u_bh[i] = _bh_names.find("retreat")
			u_st[i] = S_RETREAT
			u_tx[i] = e.x
			u_ty[i] = e.y
			u_tgt[i] = -1
			(u_meta[i] as Dictionary)["order"] = {"behavior": "retreat", "x": e.x, "y": e.y, "since": t}
			(u_meta[i] as Dictionary)["wp"] = []
	_log(why if why != "" else "General retreat.", "retreat", k)


func _hq_step(k: int, nu: int) -> void:
	var sd: Dictionary = S[k]
	if bool(sd["collapse"]):
		return
	var hq := _v2(sd["hq"])
	var threat := 0
	for j in nu:
		if u_side[j] != k and u_st[j] < S_DEAD and u_st[j] != S_ROUT and u_st[j] != S_RETREAT:
			var dx := u_x[j] - hq.x
			var dy := u_y[j] - hq.y
			if dx * dx + dy * dy < 4900.0:
				threat += 1
	if threat > 0:
		var guards := 0
		for j2 in nu:
			if u_side[j2] == k and u_st[j2] < S_DEAD and u_st[j2] != S_ROUT:
				var dx2 := u_x[j2] - hq.x
				var dy2 := u_y[j2] - hq.y
				if dx2 * dx2 + dy2 * dy2 < 14400.0:
					guards += 1
		sd["hq_hp"] = float(sd["hq_hp"]) - 0.06 * float(threat) / float(1 + guards)
		if float(sd["hq_hp"]) <= 0.0:
			sd["collapse"] = true
			_log("%s's commander has been struck down!" % String(sd["name"]), "commander_down", k)
			for i in nu:
				if u_side[i] == k and u_st[i] < S_DEAD:
					u_mor[i] = maxf(0.0, u_mor[i] - 0.22)
			order_retreat(k, "%s's army loses its commander and breaks." % String(sd["name"]))
	else:
		sd["hq_hp"] = minf(1.0, float(sd["hq_hp"]) + 0.01)


## A unit with enemies in three or four quadrants round it is surrounded: morale falls, retreat is hard (R§34).
func _encircle(nu: int) -> void:
	for i in nu:
		if u_st[i] >= S_DEAD:
			continue
		var xi := u_x[i]
		var yi := u_y[i]
		var fa := u_face[i]
		var cf := cos(fa)
		var sf := sin(fa)
		var quad := 0
		var cnt := 0
		var lst: PackedInt32Array = _al[1 - u_side[i]]
		for j in lst:
			if u_st[j] >= S_DEAD or u_st[j] == S_ROUT:
				continue
			var dx := u_x[j] - xi
			var dy := u_y[j] - yi
			if dx * dx + dy * dy > 28900.0:
				continue
			cnt += 1
			var fw := dx * cf + dy * sf
			var lt := -dx * sf + dy * cf
			if absf(lt) < fw:
				quad |= 1
			elif absf(fw) <= absf(lt):
				quad |= 4 if lt > 0.0 else 8
			else:
				quad |= 2
		var bits := (quad & 1) + ((quad >> 1) & 1) + ((quad >> 2) & 1) + ((quad >> 3) & 1)
		var surr := (quad & 2) != 0 and bits >= 3 and cnt >= 3 and u_cls[i] != 5
		var was := u_meta_surr[i] == 1
		if surr != was:
			var m: Dictionary = u_meta[i]
			m["surr"] = surr
			u_meta_surr[i] = 1 if surr else 0
			if surr:
				_log("%s is surrounded!" % String(m["name"]), "surrounded", int(u_side[i]))


func _check_end(nu: int) -> void:
	var live := [0, 0]
	var arriving := [0, 0]
	for i in nu:
		var s := u_st[i]
		if s == S_ARRIVE:
			arriving[u_side[i]] += 1
		elif s < S_DEAD and s != S_ROUT:
			live[u_side[i]] += 1
	if live[0] == 0 and arriving[0] == 0 or live[1] == 0 and arriving[1] == 0:
		var loser := -1
		if live[0] == 0 and arriving[0] == 0 and live[1] == 0 and arriving[1] == 0:
			loser = -2
		elif live[0] == 0 and arriving[0] == 0:
			loser = 0
		else:
			loser = 1
		if loser == -2:
			_finish(-1, "Both armies were shattered.")
		else:
			_finish(1 - loser, "%s is broken or has left the field." % _army_label(loser))
		return
	if t >= MAX_T:
		_finish(-1, "Both sides drew apart at nightfall.")
		return
	if t > 1800.0 and t - _last_act_t > 600.0:
		var near := false
		for i2 in nu:
			if u_st[i2] == S_FIGHT:
				near = true
				break
		if not near:
			var ms := [0.0, 0.0]
			for i3 in nu:
				if u_st[i3] < S_DEAD and u_st[i3] != S_ROUT and u_cls[i3] != 5:
					ms[u_side[i3]] += u_men[i3] * u_mor[i3]
			if float(ms[0]) > 1.7 * float(ms[1]):
				_finish(0, "%s held the field; the enemy drew off." % _army_label(0))
			elif float(ms[1]) > 1.7 * float(ms[0]):
				_finish(1, "%s held the field; the enemy drew off." % _army_label(1))
			else:
				_finish(-1, "Neither side would close; the armies drew apart.")


func _finish(winner: int, why: String) -> void:
	phase = "ended"
	var cas := [0, 0]
	var ul: Array = []
	for i in u_side.size():
		var k := int(u_side[i])
		var lost := maxf(0.0, u_men0[i] - u_men[i])
		if u_cls[i] != 5:
			cas[k] += int(round(lost))
		ul.append({"cid": int(u_cid[i]), "side": k, "name": String((u_meta[i] as Dictionary)["name"]), "kind": String((u_meta[i] as Dictionary)["kind"]),
			"men": int(round(u_men[i])), "men0": int(round(u_men0[i])), "morale": snappedf(u_mor[i], 0.001), "fatigue": snappedf(u_fat[i], 0.001),
			"cas": int(round(lost)), "state": STATE_NAMES[u_st[i]], "elite": bool((u_meta[i] as Dictionary)["elite"])})
	result = {"winner": "" if winner < 0 else ("a" if winner == 0 else "b"), "why": why, "t": t, "steps": step_no, "cas": {"a": cas[0], "b": cas[1]}, "units": ul,
		"morale": {"a": snappedf(side_morale(0), 0.001), "b": snappedf(side_morale(1), 0.001)}, "duels": duels.size(), "terrain": terrain_name, "weather": weather}
	_log(why, "end", winner)


# =================================================================================================
# sight lines and fog (R§23-24, R§28): forest blocks, hills see further, hidden units are hard to spot
# =================================================================================================

func _opacity_along(x0: float, y0: float, x1: float, y1: float) -> float:
	var dx := x1 - x0
	var dy := y1 - y0
	var steps := mini(int(sqrt(dx * dx + dy * dy) / cell), 6)
	if steps < 2:
		return 0.0
	var inv := 1.0 / cell
	var nn := n
	var c0 := clampi(int(y0 * inv), 0, nn - 1) * nn + clampi(int(x0 * inv), 0, nn - 1)
	var c1 := clampi(int(y1 * inv), 0, nn - 1) * nn + clampi(int(x1 * inv), 0, nn - 1)
	var ho := hh[c0] + 2.0
	var ht := hh[c1] + 1.5
	var sum := 0.0
	var last := -1
	var fs := 1.0 / float(steps)
	for s in range(1, steps):
		var f := float(s) * fs
		var ci := clampi(int((y0 + dy * f) * inv), 0, nn - 1) * nn + clampi(int((x0 + dx * f) * inv), 0, nn - 1)
		if ci == last or ci == c0 or ci == c1:
			continue
		last = ci
		sum += OPAQ_T[int(tc[ci])]
		if hh[ci] > ho + (ht - ho) * f + 2.5:
			return 10.0
		if sum >= 1.0:
			return sum
	return sum


func los_clear(x0: float, y0: float, x1: float, y1: float) -> bool:
	return _opacity_along(x0, y0, x1, y1) < 0.85


func _blocked(x0: float, y0: float, x1: float, y1: float) -> bool:
	return _opacity_along(x0, y0, x1, y1) >= 1.0


func _vision() -> void:
	var wv := float(_wx["vision"]) * (0.45 if night else 1.0)
	u_seen.fill(0)
	for si in 2:
		var obs: PackedInt32Array = _al[si]
		var tar: PackedInt32Array = _al[1 - si]
		var no := obs.size()
		var ovis := PackedFloat32Array()
		ovis.resize(no)
		var oscout := PackedByteArray()
		oscout.resize(no)
		for q in no:
			var oi := obs[q]
			ovis[q] = u_vis[oi] * wv * VIS_T[int(tc[cell_idx(u_x[oi], u_y[oi])])]
			oscout[q] = 1 if String((u_meta[oi] as Dictionary)["kind"]) == "scout" else 0
		for j in tar:
			if u_st[j] >= S_DEAD:
				continue
			var xj := u_x[j]
			var yj := u_y[j]
			var cj := cell_idx(xj, yj)
			var conceal := 1.0 + HIDE_T[int(tc[cj])] * 1.6
			var hid := u_hid[j] == 1
			for q2 in no:
				var i := obs[q2]
				var dx := xj - u_x[i]
				var dy := yj - u_y[i]
				var d2 := dx * dx + dy * dy
				var vis := ovis[q2]
				if d2 > vis * vis * 2.56 + 19600.0 or u_st[i] >= S_DEAD:
					continue
				var seen := false
				if hid:
					seen = d2 < (19600.0 if oscout[q2] == 1 else 5625.0)
				elif d2 < 19600.0:
					seen = true
				else:
					var v := vis * (1.0 + 0.01 * clampf(hh[cell_idx(u_x[i], u_y[i])] - hh[cj], -10.0, 30.0)) / conceal
					if d2 < v * v:
						seen = _opacity_along(u_x[i], u_y[i], xj, yj) < 0.85
				if seen:
					u_seen[j] |= 1 << si
					u_lsx[j] = xj
					u_lsy[j] = yj
					u_lst[j] = t
					break


## Cells the side can see right now: 2 visible, 0 unseen. For the fog overlay (computed on demand, not per step).
func visible_mask(k: int) -> PackedByteArray:
	var m := PackedByteArray()
	m.resize(n * n)
	var wv := float(_wx["vision"]) * (0.45 if night else 1.0)
	for i in u_side.size():
		if u_side[i] != k or u_st[i] >= S_DEAD:
			continue
		var ci := cell_idx(u_x[i], u_y[i])
		var vis := u_vis[i] * wv * VIS_T[int(tc[ci])]
		var rc := int(ceil(vis / cell))
		var cx := ci % n
		var cy := ci / n
		for j in range(maxi(cy - rc, 0), mini(cy + rc + 1, n)):
			for ii in range(maxi(cx - rc, 0), mini(cx + rc + 1, n)):
				var k2 := j * n + ii
				if m[k2] == 2:
					continue
				var px := (float(ii) + 0.5) * cell
				var py := (float(j) + 0.5) * cell
				var dx := px - u_x[i]
				var dy := py - u_y[i]
				var dd := dx * dx + dy * dy
				var lim := vis * (1.0 + 0.01 * clampf(hh[ci] - hh[k2], -10.0, 30.0))
				if dd <= lim * lim and (dd < 6400.0 or _opacity_along(u_x[i], u_y[i], px, py) < 0.85):
					m[k2] = 2
	return m


# =================================================================================================
# orders and signals (R§20-22)
# =================================================================================================

func _line_clear(x0: float, y0: float, x1: float, y1: float) -> bool:
	var d := Vector2(x1 - x0, y1 - y0).length()
	var steps := int(d / (cell * 0.5)) + 1
	for s in range(1, steps + 1):
		var f := float(s) / float(steps)
		if SPEED_T[code_at(x0 + (x1 - x0) * f, y0 + (y1 - y0) * f)] <= 0.0:
			return false
	return true


func _hpush(hi: PackedInt32Array, hf: PackedFloat32Array, id: int, f: float) -> void:
	hi.append(id)
	hf.append(f)
	var c := hi.size() - 1
	while c > 0:
		var p := (c - 1) >> 1
		if hf[p] <= hf[c]:
			break
		var ti := hi[p]
		var tf := hf[p]
		hi[p] = hi[c]
		hf[p] = hf[c]
		hi[c] = ti
		hf[c] = tf
		c = p


func _hpop(hi: PackedInt32Array, hf: PackedFloat32Array) -> int:
	var top := hi[0]
	var last := hi.size() - 1
	hi[0] = hi[last]
	hf[0] = hf[last]
	hi.resize(last)
	hf.resize(last)
	var c := 0
	var sz := last
	while true:
		var l := c * 2 + 1
		var r := l + 1
		var m := c
		if l < sz and hf[l] < hf[m]:
			m = l
		if r < sz and hf[r] < hf[m]:
			m = r
		if m == c:
			break
		var ti := hi[m]
		var tf := hf[m]
		hi[m] = hi[c]
		hf[m] = hf[c]
		hi[c] = ti
		hf[c] = tf
		c = m
	return top


## Route round rivers, walls and cliffs: A* over the cells, then string-pulled into a few waypoints.
func find_path(sx: float, sy: float, gx: float, gy: float, mounted := false) -> Array:
	var g2 := _nudge(_clamp_in(Vector2(gx, gy)), 8)
	var s := cell_idx(sx, sy)
	var g := cell_idx(g2.x, g2.y)
	if s == g or _line_clear(sx, sy, g2.x, g2.y):
		return [g2]
	var key := s * n * n + g + (n * n * n * n if mounted else 0)
	var cells: Array = []
	if _path_cache.has(key):
		cells = _path_cache[key]
	else:
		var nn := n * n
		var gs := PackedFloat32Array()
		gs.resize(nn)
		gs.fill(1.0e30)
		var came := PackedInt32Array()
		came.resize(nn)
		came.fill(-1)
		var closed := PackedByteArray()
		closed.resize(nn)
		var hi := PackedInt32Array()
		var hf := PackedFloat32Array()
		gs[s] = 0.0
		_hpush(hi, hf, s, 0.0)
		var gxi := g % n
		var gyi := g / n
		var found := false
		while hi.size() > 0:
			var cur := _hpop(hi, hf)
			if closed[cur] == 1:
				continue
			closed[cur] = 1
			if cur == g:
				found = true
				break
			var cx := cur % n
			var cy := cur / n
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					if dx == 0 and dy == 0:
						continue
					var nx: int = cx + dx
					var ny: int = cy + dy
					if nx < 0 or ny < 0 or nx >= n or ny >= n:
						continue
					var nb := ny * n + nx
					if closed[nb] == 1:
						continue
					var sp := SPEED_T[int(tc[nb])]
					if sp <= 0.0:
						continue
					if mounted and int(tc[nb]) in [T_FORD, T_MARSH, T_FOREST]:
						sp *= 0.5
					var ng: float = gs[cur] + (1.0 / maxf(sp, 0.2)) * (1.414 if dx != 0 and dy != 0 else 1.0)
					if ng < gs[nb]:
						gs[nb] = ng
						came[nb] = cur
						var ddx := absi(nx - gxi)
						var ddy := absi(ny - gyi)
						_hpush(hi, hf, nb, ng + 0.8 * (float(maxi(ddx, ddy)) + 0.414 * float(mini(ddx, ddy))))
		if not found:
			return [g2]
		var c := g
		while c != -1:
			cells.push_front(c)
			c = came[c]
		_path_cache[key] = cells
	var pts: Array = []
	for c2: int in cells:
		pts.append(Vector2((float(c2 % n) + 0.5) * cell, (float(c2 / n) + 0.5) * cell))
	var out: Array = []
	var anchor := Vector2(sx, sy)
	var idx := 0
	while idx < pts.size():
		var far := idx
		for q in range(idx, pts.size()):
			if _line_clear(anchor.x, anchor.y, (pts[q] as Vector2).x, (pts[q] as Vector2).y):
				far = q
		if far == idx and not _line_clear(anchor.x, anchor.y, (pts[idx] as Vector2).x, (pts[idx] as Vector2).y):
			far = idx
		out.append(pts[far])
		anchor = pts[far]
		idx = far + 1
	if out.is_empty() or (out[out.size() - 1] as Vector2).distance_to(g2) > 2.0:
		out.append(g2)
	return out


func _order_label(o: Dictionary, i: int) -> String:
	var b := String(o.get("behavior", "hold"))
	return "%s: %s" % [String((u_meta[i] as Dictionary)["name"]), String(beh(b)["name"])]


## How an order reaches a unit: banners and horns inside signal range arrive at the next step; beyond it a mounted
## runner carries it, takes time, and can be caught or lost. Returns {via, eta, lost}.
func signal_info(k: int, i: int) -> Dictionary:
	var sd: Dictionary = S[k]
	var hq := _v2(sd["hq"])
	var p := Vector2(u_x[i], u_y[i])
	var d := hq.distance_to(p)
	var near := float(sd["near"]) * float(_wx["signal"]) * (0.7 if night else 1.0)
	if bool(sd["collapse"]):
		near *= 0.4
	if d <= near:
		return {"via": "banner" if (not night and float(_wx["signal"]) >= 0.8) else "horn", "eta": STEP, "lost": false, "dist": d, "chance": 0.0}
	var avg := 0.0
	var danger := false
	for s in 5:
		var q := hq.lerp(p, float(s) / 4.0)
		avg += clampf(SPEED_T[code_at(q.x, q.y)], 0.45, 1.25)
	var seg := p - hq
	var seg2 := maxf(seg.length_squared(), 1.0)
	var lst: PackedInt32Array = _al[1 - k]
	for j in lst:
		if u_st[j] >= S_DEAD or u_st[j] == S_ROUT:
			continue
		var w := clampf(((Vector2(u_x[j], u_y[j]) - hq).dot(seg)) / seg2, 0.0, 1.0)
		if (hq + seg * w).distance_squared_to(Vector2(u_x[j], u_y[j])) < 16900.0:
			danger = true
			break
	avg /= 5.0
	var spd := float(sd["runner"]) * avg * (0.75 if night else 1.0)
	var eta := 20.0 + d / maxf(spd, 0.5)
	var chance := 0.04 + (0.22 if danger else 0.0) + (0.05 if weather == "storm" else 0.0)
	return {"via": "runner", "eta": eta, "lost": false, "dist": d, "chance": chance}


## Gives a unit an order from its side's commander. Returns {ok, reason, eta, via, id}.
func order(k: int, i: int, o: Dictionary) -> Dictionary:
	if i < 0 or i >= u_side.size() or u_side[i] != k:
		return {"ok": false, "reason": "Not your unit."}
	if u_st[i] >= S_DEAD:
		return {"ok": false, "reason": "That formation is gone."}
	var b := String(o.get("behavior", "hold"))
	if _bh_names.find(b) < 0:
		return {"ok": false, "reason": "Unknown order."}
	if phase != "battle":
		_apply_order(i, o)
		return {"ok": true, "reason": "", "eta": 0.0, "via": "drill", "id": 0}
	var info := signal_info(k, i)
	var id := _next_sig
	_next_sig += 1
	var lost := false
	if String(info["via"]) == "runner":
		lost = _hash(seed, id, k + 31) < float(info["chance"])
	var rec := {"id": id, "side": k, "unit": i, "order": o.duplicate(true), "sent": t, "due": t + float(info["eta"]), "via": info["via"], "lost": lost}
	_sig.append(rec)
	orders_log.append({"id": id, "side": k, "unit": i, "label": _order_label(o, i), "sent": t, "due": rec["due"], "via": info["via"], "status": "travelling", "lost": lost})
	if orders_log.size() > 40:
		orders_log.pop_front()
	return {"ok": true, "reason": "", "eta": float(info["eta"]), "via": info["via"], "id": id, "lost_chance": info["chance"]}


func order_many(k: int, ids: Array, o: Dictionary) -> Array:
	var out: Array = []
	for i in ids:
		out.append(order(k, int(i), o))
	return out


func _deliver() -> void:
	var keep: Array = []
	for rec: Dictionary in _sig:
		if float(rec["due"]) > t + 0.001:
			keep.append(rec)
			continue
		var i := int(rec["unit"])
		var id := int(rec["id"])
		var status := "delivered"
		if bool(rec["lost"]):
			status = "lost"
		elif u_st[i] >= S_DEAD or u_st[i] == S_ROUT:
			status = "failed"
		elif bool((S[int(rec["side"])] as Dictionary)["retreat"]) and String((rec["order"] as Dictionary).get("behavior", "")) != "retreat":
			status = "superseded"
		else:
			_apply_order(i, rec["order"] as Dictionary)
		for lg: Dictionary in orders_log:
			if int(lg["id"]) == id:
				lg["status"] = status
				break
	_sig = keep


func _apply_order(i: int, o: Dictionary) -> void:
	var b := String(o.get("behavior", "hold"))
	var bi := _bh_names.find(b)
	if bi < 0:
		return
	var meta: Dictionary = u_meta[i]
	var rec := o.duplicate(true)
	rec["since"] = t
	meta["order"] = rec
	meta["fl"] = false
	meta["wp"] = []
	meta["bait"] = b == "false_retreat"
	meta["feint"] = b == "feint"
	var bd := beh(b)
	var px := float(o.get("x", u_x[i]))
	var py := float(o.get("y", u_y[i]))
	if String(bd["needs"]) == "unit":
		var tg := int(o.get("target", -1))
		if tg >= 0 and tg < u_side.size():
			px = u_x[tg]
			py = u_y[tg]
			if b == "focus_fire":
				u_tgt[i] = tg
	if b in ["retreat"] and not o.has("x"):
		var e := _v2((S[int(u_side[i])] as Dictionary)["exit"])
		px = e.x
		py = e.y
	u_bh[i] = bi
	u_tx[i] = clampf(px, 6.0, size_m() - 6.0)
	u_ty[i] = clampf(py, 6.0, size_m() - 6.0)
	if o.has("formation"):
		set_formation(i, String(o["formation"]))
	if b == "form_line":
		set_formation(i, "line")
	if b == "retreat":
		u_st[i] = S_RETREAT
		u_tgt[i] = -1
	elif u_st[i] == S_RETREAT:
		u_st[i] = S_HOLD
	if b == "commit" or (b != "reserve" and u_st[i] == S_RESERVE and bool(bd["moves"])):
		u_st[i] = S_MOVE
		meta["layer"] = "front" if b == "commit" else meta["layer"]
	if bool(bd["moves"]) and String(bd["needs"]) != "none" and u_st[i] != S_RETREAT:
		if not _line_clear(u_x[i], u_y[i], u_tx[i], u_ty[i]):
			meta["wp"] = find_path(u_x[i], u_y[i], u_tx[i], u_ty[i], u_mnt[i] == 1)


## What the commander knows about his orders (R§21-22): travelling, delivered, no word yet, lost.
func orders_view(k: int) -> Array:
	var out: Array = []
	for lg: Dictionary in orders_log:
		if int(lg["side"]) != k:
			continue
		var v := lg.duplicate()
		var st := String(lg["status"])
		if st == "travelling":
			v["eta"] = maxf(0.0, float(lg["due"]) - t)
		elif st == "lost":
			v["status"] = "no word" if t < float(lg["due"]) + maxf(40.0, (float(lg["due"]) - float(lg["sent"])) * 0.6) else "lost"
			v["eta"] = 0.0
		out.append(v)
	return out


## Pending signals that have not arrived (for the map: runners and flags in transit).
func signals_in_flight(k: int) -> Array:
	var out: Array = []
	for rec: Dictionary in _sig:
		if int(rec["side"]) == k:
			var i := int(rec["unit"])
			var hq := _v2((S[k] as Dictionary)["hq"])
			var f := clampf((t - float(rec["sent"])) / maxf(float(rec["due"]) - float(rec["sent"]), 1.0), 0.0, 1.0)
			var p := hq.lerp(Vector2(u_x[i], u_y[i]), f)
			out.append({"id": int(rec["id"]), "unit": i, "x": p.x, "y": p.y, "via": rec["via"], "eta": maxf(0.0, float(rec["due"]) - t)})
	return out


# =================================================================================================
# champion duels (R§39-40)
# =================================================================================================

var pending_duel: Dictionary = {}


func _duel_willing(i: int) -> int:
	# 1 yes, 0 undecided (player must choose), -1 no
	var k := int(u_side[i])
	var m: Dictionary = u_meta[i]
	var pref := String(m.get("duel", ""))
	if pref == "accept":
		return 1
	if pref == "decline":
		return -1
	if bool(auto[k]):
		var pers := String(((S[k] as Dictionary)["cmd"] as Dictionary).get("personality", "loyal"))
		return 1 if (bool((S[k] as Dictionary)["duel_ok"]) or pers in ["aggressive", "ambitious", "independent"]) else -1
	return 0


func duel_respond(i: int, accept: bool) -> void:
	if i < 0 or i >= u_side.size():
		return
	(u_meta[i] as Dictionary)["duel"] = "accept" if accept else "decline"
	(u_meta[i] as Dictionary)["duel_t"] = t
	pending_duel = {}


## The player (or AI) challenges: the champion marches on the enemy's best fighter.
func challenge(k: int, i: int) -> Dictionary:
	var best := -1
	var bd := 1.0e18
	for j in u_side.size():
		if u_side[j] != k and u_cls[j] == 5 and u_st[j] < S_DEAD:
			var d := Vector2(u_x[j] - u_x[i], u_y[j] - u_y[i]).length_squared()
			if d < bd:
				bd = d
				best = j
	if best < 0:
		return {"ok": false, "reason": "No enemy champion is known."}
	(u_meta[i] as Dictionary)["duel"] = "accept"
	return order(k, i, {"behavior": "intercept", "target": best, "x": u_x[best], "y": u_y[best]})


func _duel_step(nu: int) -> void:
	for d: Dictionary in duels:
		if bool(d["done"]):
			continue
		var a := int(d["a"])
		var b := int(d["b"])
		d["round"] = int(d["round"]) + 1
		var ra := _hash(step_no, a, seed + 5)
		var rb := _hash(step_no, b, seed + 6)
		var sa := 0.5 * u_q[a] + 0.3 * u_mor[a] + 0.2 * (1.0 - u_fat[a])
		var sb := 0.5 * u_q[b] + 0.3 * u_mor[b] + 0.2 * (1.0 - u_fat[b])
		var pa := pow(u_pw[a] / 380.0, 0.3)
		var pb := pow(u_pw[b] / 380.0, 0.3)
		if ra < 0.72:
			u_men[b] -= 0.05 * (0.6 + sa) * pa * (0.55 + 0.9 * rb) * 55.0 / u_tough[b]
		if rb < 0.72:
			u_men[a] -= 0.05 * (0.6 + sb) * pb * (0.55 + 0.9 * ra) * 55.0 / u_tough[a]
		if u_men[a] <= 0.1 or u_men[b] <= 0.1:
			var win := a
			var lose := b
			if u_men[a] <= 0.1 and u_men[b] > 0.1 or (u_men[a] <= 0.1 and u_men[b] <= 0.1 and u_men[a] < u_men[b]):
				win = b
				lose = a
			d["done"] = true
			d["winner"] = win
			var dies := _hash(step_no, lose, seed + 9) < 0.6
			u_st[win] = S_HOLD
			u_men[win] = maxf(u_men[win], 0.12)
			if dies:
				u_men[lose] = 0.0
				u_st[lose] = S_DEAD
			else:
				u_men[lose] = 0.12
				u_st[lose] = S_EXIT
				(u_meta[lose] as Dictionary)["note"] = "yielded"
			_log("%s defeats %s in single combat%s." % [String((u_meta[win] as Dictionary)["name"]), String((u_meta[lose] as Dictionary)["name"]), "" if dies else " and takes the yield"], "duel_end", int(u_side[win]))
			d["log"] = "%s won after %d rounds." % [String((u_meta[win] as Dictionary)["name"]), int(d["round"])]
			for j in nu:
				if u_st[j] >= S_DEAD:
					continue
				var dx := u_x[j] - u_x[win]
				var dy := u_y[j] - u_y[win]
				if dx * dx + dy * dy < 122500.0:
					u_mor[j] = clampf(u_mor[j] + (0.1 if u_side[j] == u_side[win] else -0.14), 0.0, 1.0)
	if step_no % 3 != 0 or phase != "battle":
		return
	var es: Array = []
	for i in nu:
		if u_cls[i] == 5 and u_st[i] < S_DEAD and u_st[i] != S_ROUT and u_st[i] != S_DUEL and u_st[i] != S_RETREAT:
			es.append(i)
	for x in es.size():
		for y in range(x + 1, es.size()):
			var i2: int = es[x]
			var j2: int = es[y]
			if u_side[i2] == u_side[j2] or u_st[i2] == S_DUEL or u_st[j2] == S_DUEL:
				continue
			var dx2 := u_x[j2] - u_x[i2]
			var dy2 := u_y[j2] - u_y[i2]
			if dx2 * dx2 + dy2 * dy2 > 8100.0:
				continue
			var wi := _duel_willing(i2)
			var wj := _duel_willing(j2)
			if wi == 1 and wj == 1:
				duels.append({"a": i2, "b": j2, "round": 0, "t0": t, "done": false, "winner": -1, "log": ""})
				u_st[i2] = S_DUEL
				u_st[j2] = S_DUEL
				u_face[i2] = atan2(dy2, dx2)
				u_face[j2] = atan2(-dy2, -dx2)
				_log("%s and %s meet in single combat." % [String((u_meta[i2] as Dictionary)["name"]), String((u_meta[j2] as Dictionary)["name"])], "duel", -1)
			elif (wi == 0 or wj == 0) and pending_duel.is_empty() and wi + wj >= 0:
				var mine := i2 if wi == 0 else j2
				pending_duel = {"mine": mine, "theirs": j2 if mine == i2 else i2, "t": t, "side": int(u_side[mine])}
	if not pending_duel.is_empty() and t - float(pending_duel["t"]) > 90.0:
		duel_respond(int(pending_duel["mine"]), false)


# =================================================================================================
# views for the UI, the advisors and the campaign
# =================================================================================================

func time_text() -> String:
	var s := int(t)
	return "%02d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60]


func unit_view(i: int) -> Dictionary:
	var m: Dictionary = u_meta[i]
	var o: Dictionary = m["order"]
	return {"i": i, "id": i, "side": int(u_side[i]), "name": String(m["name"]), "kind": String(m["kind"]), "cls": int(u_cls[i]), "men": int(round(u_men[i])), "men0": int(round(u_men0[i])),
		"morale": u_mor[i], "fatigue": u_fat[i], "quality": u_q[i], "x": u_x[i], "y": u_y[i], "face": u_face[i], "rad": u_rad[i], "rng": u_rng[i], "ammo": u_ammo[i],
		"st": int(u_st[i]), "state": STATE_NAMES[u_st[i]], "behavior": String(_bh_names[u_bh[i]]), "formation": String(_fm_names[u_fm[i]]), "layer": String(m["layer"]),
		"hidden": u_hid[i] == 1, "elite": bool(m["elite"]), "cid": int(u_cid[i]), "tgt": int(u_tgt[i]), "tx": u_tx[i], "ty": u_ty[i], "order": o, "mounted": u_mnt[i] == 1,
		"cas": int(round(u_cas[i])), "note": String(m.get("note", "")), "surrounded": bool(m.get("surr", false)), "bait": bool(m.get("bait", false)), "wp": m["wp"]}


## What side `viewer` sees: own units truly; enemies only while seen, else a ghost of the last sighting.
func units_view(viewer: int) -> Array:
	var out: Array = []
	for i in u_side.size():
		if u_side[i] == viewer:
			if u_st[i] != S_EXIT and u_st[i] != S_DEAD:
				out.append(unit_view(i))
			continue
		if u_st[i] >= S_DEAD:
			continue
		if ((u_seen[i] >> viewer) & 1) == 1:
			var v := unit_view(i)
			v["seen"] = true
			v["age"] = 0.0
			out.append(v)
		elif u_lst[i] >= 0.0 and t - u_lst[i] < 2400.0 and phase == "battle":
			out.append({"i": i, "id": i, "side": int(u_side[i]), "name": "Unknown force", "kind": String((u_meta[i] as Dictionary)["kind"]), "cls": int(u_cls[i]), "ghost": true, "seen": false,
				"x": u_lsx[i], "y": u_lsy[i], "age": t - u_lst[i], "rad": u_rad[i], "men": 0, "face": u_face[i], "elite": bool((u_meta[i] as Dictionary)["elite"])})
	return out


## Honest range for the enemy: sized from units actually seen, widened for the ones never seen (R§23).
func enemy_intel(viewer: int) -> Dictionary:
	var enemy := 1 - viewer
	var seen_men := 0.0
	var seen_n := 0
	var total_n := 0
	var comp := {}
	var conf_units := 0
	for i in u_side.size():
		if u_side[i] != enemy or u_st[i] >= S_DEAD:
			continue
		total_n += 1
		if ((u_seen[i] >> viewer) & 1) == 1 or (u_lst[i] >= 0.0 and phase == "battle" and t - u_lst[i] < 2400.0):
			seen_n += 1
			seen_men += u_men[i]
			var kd := String((u_meta[i] as Dictionary)["kind"])
			comp[kd] = int(comp.get(kd, 0)) + int(round(u_men[i]))
			if ((u_seen[i] >> viewer) & 1) == 1:
				conf_units += 1
	var unknown := total_n - seen_n
	var avg := seen_men / maxf(1.0, float(seen_n))
	var lo := int(floor(seen_men * 0.85))
	var hi := int(ceil(seen_men * 1.15 + float(unknown) * maxf(avg, 120.0) * 1.3))
	return {"est_min": lo, "est_max": hi, "seen_units": seen_n, "total_units": total_n, "comp": comp, "exact": unknown == 0 and conf_units == total_n}


func forces(k: int) -> Dictionary:
	var men := 0
	var men0 := 0
	var alive := 0
	var routed := 0
	var fat := 0.0
	for i in u_side.size():
		if u_side[i] != k:
			continue
		men0 += int(round(u_men0[i])) if u_cls[i] != 5 else 0
		if u_st[i] < S_DEAD:
			if u_cls[i] != 5:
				men += int(round(u_men[i]))
			alive += 1
			fat += u_fat[i]
			if u_st[i] == S_ROUT:
				routed += 1
	return {"men": men, "men0": men0, "units": alive, "routed": routed, "morale": side_morale(k), "fatigue": fat / maxf(1.0, float(alive))}


## Units of one side that have reinforcements on the way: [{i, due (s)}].
func arrivals(k: int) -> Array:
	var out: Array = []
	for i in u_side.size():
		if u_side[i] == k and u_st[i] == S_ARRIVE:
			out.append({"i": i, "due": u_due[i], "eta": maxf(0.0, u_due[i] - t), "name": String((u_meta[i] as Dictionary)["name"]), "men": int(u_men[i])})
	return out


## Reinforcements: units marching in from the rear of `k`'s side, reaching the field `eta_s` seconds from now.
func send_reinforcements(k: int, specs: Array, eta_s: float) -> Array:
	var ids: Array = []
	for sp in specs:
		var d := (sp as Dictionary).duplicate()
		d["due"] = t + eta_s
		var i := add_unit(k, d)
		(u_meta[i] as Dictionary)["layer"] = String(d.get("layer", "second"))
		ids.append(i)
	_log("Reinforcements are coming for %s (%d min)." % [String((S[k] as Dictionary)["name"]), int(round(eta_s / 60.0))], "reinforce", k)
	return ids


func terrain_name_at(x: float, y: float) -> String:
	return String(TNAMES[code_at(x, y)])


func terrain_share() -> Dictionary:
	var cnt := {}
	for k in tc.size():
		var c := int(tc[k])
		cnt[c] = int(cnt.get(c, 0)) + 1
	var out := {}
	for c2: int in cnt:
		out[String(TNAMES[c2])] = float(cnt[c2]) / float(tc.size())
	return out


# =================================================================================================
# persistence (plain arrays, dictionaries, numbers: JSON safe)
# =================================================================================================

func serialize() -> Dictionary:
	var us: Array = []
	for i in u_side.size():
		var m: Dictionary = (u_meta[i] as Dictionary).duplicate(true)
		var wp: Array = []
		for p: Vector2 in (m["wp"] as Array):
			wp.append([p.x, p.y])
		m["wp"] = wp
		us.append({"side": int(u_side[i]), "pw": u_pw[i], "spd": u_spd[i], "vis": u_vis[i], "rng": u_rng[i], "mnt": int(u_mnt[i]), "rad": u_rad[i], "tough": u_tough[i],
			"men": u_men[i], "men0": u_men0[i], "q": u_q[i], "mor": u_mor[i], "fat": u_fat[i], "ammo": u_ammo[i], "x": u_x[i], "y": u_y[i], "face": u_face[i],
			"tx": u_tx[i], "ty": u_ty[i], "st": int(u_st[i]), "tgt": int(u_tgt[i]), "bh": int(u_bh[i]), "fm": int(u_fm[i]), "hid": int(u_hid[i]), "chg": int(u_chg[i]),
			"seen": int(u_seen[i]), "cas": u_cas[i], "cid": int(u_cid[i]), "due": u_due[i], "lsx": u_lsx[i], "lsy": u_lsy[i], "lst": u_lst[i], "rth": u_rth[i],
			"cls": int(u_cls[i]), "hitt": u_hitt[i], "acq": int(u_acq[i]), "meta": m})
	return {"v": VERSION, "seed": seed, "name": name, "phase": phase, "t": t, "step": step_no, "n": n, "cell": cell, "center": [world_c.x, world_c.y],
		"terrain_name": terrain_name, "weather": weather, "season": season, "hour": hour, "night": night, "attacker": attacker, "feats": feats.duplicate(true),
		"opts": opts.duplicate(true), "rows": rows.duplicate(), "h": _h_dm(), "S": (S as Array).duplicate(true), "events": events.duplicate(true),
		"orders_log": orders_log.duplicate(true), "duels": duels.duplicate(true), "result": result.duplicate(true), "auto": auto.duplicate(), "think": think.duplicate(),
		"ctx": ctx_factors.duplicate(true), "sig": _sig.duplicate(true), "next_sig": _next_sig, "last_kill": _last_kill_t, "last_act": _last_act_t, "pending_duel": pending_duel.duplicate(true), "units": us}


func _h_dm() -> Array:
	var h: Array = []
	for k in hh.size():
		h.append(int(round(hh[k] * 10.0)))
	return h


static func restore(d: Dictionary) -> RefCounted:
	var tt: RefCounted = load("res://scripts/realm/tactical.gd").new()
	tt.call("deserialize", d)
	return tt


func deserialize(d: Dictionary) -> void:
	seed = int(d["seed"])
	name = String(d["name"])
	phase = String(d["phase"])
	t = float(d["t"])
	step_no = int(d["step"])
	world_c = Vector2(float((d["center"] as Array)[0]), float((d["center"] as Array)[1]))
	weather = String(d["weather"])
	season = String(d["season"])
	hour = int(d["hour"])
	night = bool(d["night"])
	attacker = int(d["attacker"])
	_wx = WarUnits.WEATHER.get(weather, WarUnits.WEATHER["clear"])
	_load_grid({"n": d["n"], "cell": d["cell"], "rows": d["rows"], "feats": d["feats"], "name": d["terrain_name"], "h": d["h"]})
	opts = (d.get("opts", {}) as Dictionary).duplicate(true)
	_att_edge = 1.0 if opts.has("ring") else ATTACK_EDGE
	S = (d["S"] as Array).duplicate(true)
	for k in 2:
		var sd: Dictionary = S[k]
		sd["tier"] = int(sd["tier"])
		sd["men0"] = int(sd["men0"])
		sd["player"] = bool(sd["player"])
		(sd["cmd"] as Dictionary)["skill"] = int((sd["cmd"] as Dictionary).get("skill", 2))
	events = (d["events"] as Array).duplicate(true)
	orders_log = (d["orders_log"] as Array).duplicate(true)
	duels = (d["duels"] as Array).duplicate(true)
	result = (d["result"] as Dictionary).duplicate(true)
	auto = [bool((d["auto"] as Array)[0]), bool((d["auto"] as Array)[1])]
	think = [int((d["think"] as Array)[0]), int((d["think"] as Array)[1])]
	ctx_factors = (d["ctx"] as Dictionary).duplicate(true)
	_sig = (d["sig"] as Array).duplicate(true)
	_next_sig = int(d["next_sig"])
	_last_kill_t = float(d["last_kill"])
	_last_act_t = float(d.get("last_act", 0.0))
	pending_duel = (d.get("pending_duel", {}) as Dictionary).duplicate(true)
	for arr in [u_side, u_mnt, u_st, u_tgt, u_bh, u_fm, u_hid, u_chg, u_seen, u_cid, u_cls, u_acq, u_meta_surr]:
		(arr as PackedInt32Array).clear()
	for arr2 in [u_pw, u_spd, u_vis, u_rng, u_rad, u_tough, u_men, u_men0, u_q, u_mor, u_fat, u_ammo, u_x, u_y, u_face, u_tx, u_ty, u_cas, u_due, u_lsx, u_lsy, u_lst, u_rth, u_hitt, _dk, _dm, u_v0, u_dq, u_eq]:
		(arr2 as PackedFloat32Array).clear()
	_dflag.clear()
	u_meta = []
	for ud: Dictionary in (d["units"] as Array):
		u_side.append(int(ud["side"]))
		u_pw.append(float(ud["pw"]))
		u_spd.append(float(ud["spd"]))
		u_vis.append(float(ud["vis"]))
		u_rng.append(float(ud["rng"]))
		u_mnt.append(int(ud["mnt"]))
		u_rad.append(float(ud["rad"]))
		u_tough.append(float(ud["tough"]))
		u_men.append(float(ud["men"]))
		u_men0.append(float(ud["men0"]))
		u_q.append(float(ud["q"]))
		u_mor.append(float(ud["mor"]))
		u_fat.append(float(ud["fat"]))
		u_ammo.append(float(ud["ammo"]))
		u_x.append(float(ud["x"]))
		u_y.append(float(ud["y"]))
		u_face.append(float(ud["face"]))
		u_tx.append(float(ud["tx"]))
		u_ty.append(float(ud["ty"]))
		u_st.append(int(ud["st"]))
		u_tgt.append(int(ud["tgt"]))
		u_bh.append(int(ud["bh"]))
		u_fm.append(int(ud["fm"]))
		u_hid.append(int(ud["hid"]))
		u_chg.append(int(ud["chg"]))
		u_seen.append(int(ud["seen"]))
		u_cas.append(float(ud["cas"]))
		u_cid.append(int(ud["cid"]))
		u_due.append(float(ud["due"]))
		u_lsx.append(float(ud["lsx"]))
		u_lsy.append(float(ud["lsy"]))
		u_lst.append(float(ud["lst"]))
		u_rth.append(float(ud["rth"]))
		u_cls.append(int(ud["cls"]))
		u_hitt.append(float(ud["hitt"]))
		u_acq.append(int(ud["acq"]))
		u_dq.append(pow(0.6 + 0.8 * float(ud["q"]), 0.6))
		u_eq.append(0.6 + 0.8 * float(ud["q"]))
		u_meta_surr.append(1 if bool(((ud["meta"] as Dictionary)).get("surr", false)) else 0)
		u_v0.append(SPD0 * float(ud["spd"]) * STEP)
		var m: Dictionary = (ud["meta"] as Dictionary).duplicate(true)
		var wp: Array = []
		for p in (m["wp"] as Array):
			wp.append(Vector2(float((p as Array)[0]), float((p as Array)[1])))
		m["wp"] = wp
		u_meta.append(m)
		if bool(m["elite"]):
			_has_elite = true
		_dk.append(0.0)
		_dm.append(0.0)
		_dflag.append(0)
	_refresh_alive()
