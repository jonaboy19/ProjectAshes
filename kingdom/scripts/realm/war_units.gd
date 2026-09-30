extends RefCounted
## War Map data tables and pure maths (docs/design/WAR_COMMAND_RULEBOOK.md §3-11, §25-28, §60).
## No state, no scene access: campaign.gd owns the armies and calls these. Everything is
## deterministic and JSON-safe (plain numbers / strings / arrays / dictionaries).

const MIN_UNIT := 5                  # smallest formation a split may leave (a squad)

## Unit kinds. power: fighting value of one man; speed: multiplier on ARMY_SPEED; vision: metres.
## exposure: share of casualties it draws (front line takes more than the rear).
const KINDS := {
	"infantry": {"name": "Infantry", "short": "INF", "power": 1.0, "speed": 1.0, "vision": 240.0, "ranged": false, "mounted": false, "exposure": 1.3, "front": 0},
	"spear": {"name": "Spearmen", "short": "SPR", "power": 0.95, "speed": 1.0, "vision": 240.0, "ranged": false, "mounted": false, "exposure": 1.3, "front": 0},
	"archer": {"name": "Archers", "short": "ARC", "power": 0.8, "speed": 1.0, "vision": 260.0, "ranged": true, "mounted": false, "exposure": 0.8, "front": 2},
	"heavy_cav": {"name": "Heavy Cavalry", "short": "HCV", "power": 2.2, "speed": 1.5, "vision": 300.0, "ranged": false, "mounted": true, "exposure": 1.1, "front": 1},
	"light_cav": {"name": "Light Cavalry", "short": "LCV", "power": 1.2, "speed": 1.8, "vision": 380.0, "ranged": false, "mounted": true, "exposure": 0.9, "front": 1},
	"mage": {"name": "Mages", "short": "MAG", "power": 3.0, "speed": 0.9, "vision": 260.0, "ranged": true, "mounted": false, "exposure": 0.5, "front": 3},
	"engineer": {"name": "Engineers", "short": "ENG", "power": 0.3, "speed": 0.7, "vision": 200.0, "ranged": false, "mounted": false, "exposure": 0.6, "front": 3},
	"scout": {"name": "Scouts", "short": "SCT", "power": 0.4, "speed": 1.9, "vision": 700.0, "ranged": false, "mounted": true, "exposure": 0.5, "front": 1},
	"medical": {"name": "Medical Train", "short": "MED", "power": 0.05, "speed": 0.8, "vision": 150.0, "ranged": false, "mounted": false, "exposure": 0.3, "front": 3},
}
const KIND_ORDER := ["infantry", "spear", "archer", "heavy_cav", "light_cav", "mage", "engineer", "scout", "medical"]

## Default composition of an army (name, kind, share), see rulebook §3.
const COMPOSITION := [
	["First Infantry", "infantry", 0.22], ["Second Infantry", "infantry", 0.18], ["Spear Battalion", "spear", 0.14],
	["Archers", "archer", 0.12], ["Heavy Cavalry", "heavy_cav", 0.08], ["Light Cavalry", "light_cav", 0.09],
	["Mage Company", "mage", 0.04], ["Engineers", "engineer", 0.035], ["Scouts", "scout", 0.03], ["Medical Train", "medical", 0.045],
]

## Behaviours (rulebook §5). needs: point | unit | none. engage: seek | accept | avoid.
const BEHAVIOURS := {
	"advance": {"name": "Advance", "needs": "point", "engage": "seek", "speed": 1.0, "atk": 1.0, "def": 0.95, "fatigue": 1.0, "moves": true},
	"hold": {"name": "Hold", "needs": "none", "engage": "accept", "speed": 0.0, "atk": 0.95, "def": 1.1, "fatigue": 0.0, "moves": false},
	"charge": {"name": "Charge", "needs": "point", "engage": "seek", "speed": 1.25, "atk": 1.2, "def": 0.85, "fatigue": 1.8, "moves": true},
	"harass": {"name": "Harass", "needs": "point", "engage": "avoid", "speed": 1.1, "atk": 0.9, "def": 0.9, "fatigue": 1.2, "moves": true},
	"flank": {"name": "Flank", "needs": "point", "engage": "seek", "speed": 0.95, "atk": 1.05, "def": 0.9, "fatigue": 1.3, "moves": true},
	"screen": {"name": "Screen", "needs": "point", "engage": "accept", "speed": 1.0, "atk": 0.9, "def": 1.0, "fatigue": 0.8, "moves": true},
	"escort": {"name": "Escort", "needs": "unit", "engage": "accept", "speed": 1.0, "atk": 0.95, "def": 1.05, "fatigue": 0.8, "moves": true},
	"ambush": {"name": "Ambush", "needs": "none", "engage": "accept", "speed": 0.0, "atk": 1.0, "def": 1.0, "fatigue": 0.0, "moves": false},
	"retreat": {"name": "Retreat", "needs": "point", "engage": "avoid", "speed": 1.0, "atk": 0.6, "def": 0.7, "fatigue": 1.2, "moves": true},
	"withdraw_fighting": {"name": "Withdraw Fighting", "needs": "point", "engage": "avoid", "speed": 0.6, "atk": 0.9, "def": 1.05, "fatigue": 1.0, "moves": true},
	"capture": {"name": "Capture", "needs": "point", "engage": "accept", "speed": 1.0, "atk": 1.0, "def": 1.0, "fatigue": 1.0, "moves": true},
	"defend": {"name": "Defend", "needs": "point", "engage": "accept", "speed": 1.0, "atk": 1.0, "def": 1.15, "fatigue": 0.4, "moves": true},
	"intercept": {"name": "Intercept", "needs": "unit", "engage": "seek", "speed": 1.15, "atk": 1.05, "def": 0.9, "fatigue": 1.3, "moves": true},
	"follow": {"name": "Follow", "needs": "unit", "engage": "accept", "speed": 1.0, "atk": 0.95, "def": 1.0, "fatigue": 0.8, "moves": true},
	"attack_if_attacked": {"name": "Attack If Attacked", "needs": "none", "engage": "accept", "speed": 0.0, "atk": 0.95, "def": 1.05, "fatigue": 0.0, "moves": false},
	"march": {"name": "March", "needs": "point", "engage": "accept", "speed": 1.0, "atk": 0.95, "def": 0.9, "fatigue": 1.0, "moves": true},
	"avoid": {"name": "Avoid Engagement", "needs": "none", "engage": "avoid", "speed": 1.0, "atk": 0.6, "def": 0.8, "fatigue": 1.0, "moves": true},
}
## Radial menu order: primary ring first, then the rest.
const MENU_PRIMARY := ["advance", "hold", "charge", "flank", "screen", "harass", "retreat", "defend"]
const MENU_MORE := ["withdraw_fighting", "ambush", "capture", "escort", "intercept", "follow", "attack_if_attacked", "avoid"]

## Terrain classes (rulebook §28). speed: movement; cav / ranged: fighting modifiers; def: defender's bonus;
## vision: sight range; fatigue: tiring; cap: men that can fight at once (frontage), the rest queue behind.
const TERRAIN := {
	"plain": {"name": "Open ground", "speed": 1.0, "cav": 1.15, "ranged": 1.1, "def": 1.0, "vision": 1.0, "fatigue": 1.0, "cap": 4000, "ambush": 0.0},
	"road": {"name": "Road", "speed": 1.25, "cav": 1.0, "ranged": 1.0, "def": 0.95, "vision": 1.0, "fatigue": 0.8, "cap": 1200, "ambush": 0.05},
	"forest": {"name": "Forest", "speed": 0.6, "cav": 0.7, "ranged": 0.8, "def": 1.1, "vision": 0.55, "fatigue": 1.3, "cap": 700, "ambush": 0.25},
	"hills": {"name": "Hills", "speed": 0.75, "cav": 0.85, "ranged": 1.05, "def": 1.15, "vision": 1.2, "fatigue": 1.3, "cap": 1500, "ambush": 0.1},
	"mountain": {"name": "Mountain", "speed": 0.5, "cav": 0.6, "ranged": 1.0, "def": 1.25, "vision": 1.3, "fatigue": 1.6, "cap": 400, "ambush": 0.2},
	"ford": {"name": "River ford", "speed": 0.3, "cav": 0.6, "ranged": 0.9, "def": 0.85, "vision": 0.9, "fatigue": 1.4, "cap": 500, "ambush": 0.05},
	"town": {"name": "Town", "speed": 0.9, "cav": 0.8, "ranged": 1.0, "def": 1.2, "vision": 0.7, "fatigue": 0.7, "cap": 800, "ambush": 0.1},
}

const ATTRS := ["tactics", "leadership", "discipline", "adaptability", "logistics", "scouting", "experience"]
## Personalities (rulebook §10). The first four are the campaign's original ones.
const PERSONALITIES := ["cautious", "aggressive", "loyal", "ambitious", "stubborn", "inventive", "independent"]
## Morale below which a side's commander gives the order to break.
const BREAK_MORALE := {"cautious": 0.32, "aggressive": 0.15, "loyal": 0.22, "ambitious": 0.2, "stubborn": 0.1, "inventive": 0.24, "independent": 0.2}
const PERS_ATTR := {"cautious": "logistics", "aggressive": "tactics", "loyal": "discipline", "ambitious": "adaptability",
	"stubborn": "discipline", "inventive": "adaptability", "independent": "scouting"}
const WEATHER := {"clear": {"all": 1.0, "ranged": 1.0}, "rain": {"all": 0.96, "ranged": 0.8}, "snow": {"all": 0.9, "ranged": 0.85}, "storm": {"all": 0.85, "ranged": 0.65}}


static func kind(k: String) -> Dictionary:
	return KINDS.get(k, KINDS["infantry"])


static func behaviour(b: String) -> Dictionary:
	return BEHAVIOURS.get(b, BEHAVIOURS["hold"])


static func terrain(k: String) -> Dictionary:
	return TERRAIN.get(k, TERRAIN["plain"])


## Splits `total` men into the default composition. Returns [[name, kind, men], ...] whose men sum to `total`.
## Formations that would be under MIN_UNIT are dropped and the rest are rescaled (largest remainder).
static func alloc_units(total: int) -> Array:
	var rows: Array = COMPOSITION.duplicate()
	var keep: Array = []
	while true:
		var sum_w := 0.0
		for r: Array in rows:
			sum_w += float(r[2])
		keep = []
		var dropped := false
		for r: Array in rows:
			if float(total) * float(r[2]) / sum_w >= float(MIN_UNIT):
				keep.append(r)
			else:
				dropped = true
		if not dropped or keep.is_empty():
			break
		rows = keep
	if keep.is_empty():
		return [["Levy", "infantry", total]] if total > 0 else []
	var sw := 0.0
	for r: Array in keep:
		sw += float(r[2])
	var out: Array = []
	var used := 0
	var fracs: Array = []
	for i in keep.size():
		var exact := float(total) * float((keep[i] as Array)[2]) / sw
		var n := int(floor(exact))
		out.append([(keep[i] as Array)[0], (keep[i] as Array)[1], n])
		used += n
		fracs.append([exact - float(n), i])
	fracs.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0] or (a[0] == b[0] and a[1] < b[1]))
	var left := total - used
	for j in left:
		(out[fracs[j % fracs.size()][1]] as Array)[2] = int((out[fracs[j % fracs.size()][1]] as Array)[2]) + 1
	return out


## Commander attributes 0..100 from the campaign's 1-4 skill, the personality and a seeded rng.
static func make_attrs(skill: int, personality: String, r: RandomNumberGenerator) -> Dictionary:
	var d := {}
	var base := 22.0 + float(skill) * 13.0
	for k: String in ATTRS:
		d[k] = int(clampf(base + r.randf_range(-14.0, 14.0), 5.0, 98.0))
	var fav: String = String(PERS_ATTR.get(personality, "leadership"))
	d[fav] = mini(98, int(d[fav]) + 10)
	d["capacity"] = capacity(d)
	return d


## Practical command capacity in men (rulebook §11): about 60-90 for a poor officer, a few hundred for a
## capable captain, 1-2 thousand for an experienced commander, several thousand for a great general.
static func capacity(attrs: Dictionary) -> int:
	var score := (float(attrs.get("leadership", 30)) + float(attrs.get("tactics", 30)) + float(attrs.get("discipline", 30))) / 3.0
	score += (float(attrs.get("experience", 30)) - 40.0) * 0.1
	return int(round(50.0 * pow(2.0, clampf(score, 0.0, 100.0) / 12.5)))


## Order slowdown / confusion from an overloaded commander (rulebook §11): 0 when within capacity.
static func overload(men_under: int, cap: int) -> float:
	return clampf(float(men_under) / maxf(1.0, float(cap)) - 1.0, 0.0, 2.0)


## Honest estimate range that always contains `men`: p is the imprecision, u1/u2 in 0..1 skew it.
static func est_range(men: int, p: float, u1: float, u2: float) -> Vector2i:
	var lo := int(floor(float(men) * (1.0 - p * (0.3 + 0.7 * u1))))
	var hi := int(ceil(float(men) * (1.0 + p * (0.3 + 0.7 * u2))))
	return Vector2i(maxi(0, lo), maxi(hi, men))


## A commander's reaction to an order (rulebook §10). sit: {foe_ratio (estimated enemy men / own, 0 = no foe near),
## morale, engaged}. Returns {behavior, note}.
static func personality_reaction(pers: String, behavior: String, sit: Dictionary, r: RandomNumberGenerator) -> Dictionary:
	var out := {"behavior": behavior, "note": ""}
	var ratio := float(sit.get("foe_ratio", 0.0))
	var morale := float(sit.get("morale", 0.7))
	match pers:
		"aggressive":
			if behavior in ["hold", "attack_if_attacked", "screen"] and ratio > 0.0 and ratio < 1.3:
				out["behavior"] = "advance"
				out["note"] = "exploited the opening and attacked instead of holding"
			elif behavior in ["retreat", "withdraw_fighting"] and morale > 0.35 and r.randf() < 0.4:
				out["behavior"] = "hold"
				out["note"] = "refused to give ground"
		"cautious":
			if behavior in ["advance", "charge", "intercept", "flank"] and ratio > 1.2:
				out["behavior"] = "hold"
				out["note"] = "waited for confirmation: the enemy looked too strong"
			elif behavior == "charge" and morale < 0.45:
				out["behavior"] = "advance"
				out["note"] = "would not charge with a wavering line"
		"stubborn":
			if behavior in ["retreat", "withdraw_fighting"] and morale > 0.25:
				out["behavior"] = "hold"
				out["note"] = "stubbornly refused to withdraw"
		"inventive":
			if behavior == "advance" and ratio > 0.0 and r.randf() < 0.5:
				out["behavior"] = "flank"
				out["note"] = "improvised a flanking move"
		"independent":
			if behavior in ["advance", "charge", "intercept"] and ratio > 2.0:
				out["behavior"] = "hold"
				out["note"] = "ignored an order he judged suicidal"
		"ambitious":
			if behavior in ["advance", "hold"] and ratio > 0.0 and ratio < 0.9 and r.randf() < 0.35:
				out["behavior"] = "charge"
				out["note"] = "went for glory"
	return out


## Fighting power of one side (rulebook §8). `units` are unit dictionaries; env holds the situation:
##   terrain: TERRAIN entry, role: "attack"|"defend", weather, supply (days), surprise (multiplier),
##   formation {atk, def}, leader {attrs}, confusion 0..1, foe_mounted (0..1 share of the enemy), high_ground -1|0|1
## Returns {power, men, eff_men, factors: {name: multiplier}} where every factor is a plain weighted average,
## so the record of an engagement shows why it went the way it did.
static func side_power(units: Array, env: Dictionary) -> Dictionary:
	var men := 0
	for u: Dictionary in units:
		men += int(u["men"])
	if men <= 0:
		return {"power": 0.0, "men": 0, "eff_men": 0.0, "factors": {}}
	var terr: Dictionary = env.get("terrain", TERRAIN["plain"])
	var cap := float(terr["cap"])
	var eff := minf(float(men), cap) + 0.35 * maxf(0.0, float(men) - cap)
	var numbers := eff / float(men)
	var role := String(env.get("role", "attack"))
	var form: Dictionary = env.get("formation", {"atk": 1.0, "def": 1.0})
	var leader: Dictionary = env.get("leader", {})
	var cmd_f := 1.0 + (float(leader.get("tactics", 50)) - 50.0) / 200.0 + (float(leader.get("leadership", 50)) - 50.0) / 400.0
	cmd_f *= 1.0 - minf(0.3, 0.2 * float(env.get("confusion", 0.0)))
	var supply := float(env.get("supply", 3.0))
	var sup_f := 0.6 + 0.4 * minf(supply, 3.0) / 3.0
	var wx: Dictionary = WEATHER.get(String(env.get("weather", "clear")), WEATHER["clear"])
	var season_f := 0.94 if String(env.get("season", "")) == "winter" else 1.0
	var surprise := float(env.get("surprise", 1.0))
	var foe_mounted := float(env.get("foe_mounted", 0.0))
	var high := float(env.get("high_ground", 0))
	var pos_f := 1.0 + 0.08 * high
	var form_f := float(form["def"] if role == "defend" else form["atk"])
	var terr_def := float(terr["def"]) if role == "defend" else 1.0
	var total := 0.0
	var acc := {"quality": 0.0, "morale": 0.0, "fatigue": 0.0, "terrain": 0.0, "counters": 0.0, "behaviour": 0.0}
	for u: Dictionary in units:
		var k := kind(String(u["kind"]))
		var m := float(u["men"]) * eff / float(men)
		var q := 0.6 + 0.8 * float(u["quality"])
		var mo := 0.55 + 0.9 * float(u["morale"])
		var fa := 1.0 - 0.45 * float(u["fatigue"])
		var tf := terr_def
		if bool(k["mounted"]):
			tf *= float(terr["cav"])
		if bool(k["ranged"]):
			tf *= float(terr["ranged"]) * float(wx["ranged"])
		var ct := 1.0
		if String(u["kind"]) == "spear":
			ct = 1.0 + 0.5 * foe_mounted
		elif String(u["kind"]) == "heavy_cav" and terr["name"] == "Open ground":
			ct = 1.1
		var bh := behaviour(String((u.get("order", {}) as Dictionary).get("behavior", "hold")))
		var beh := float(bh["def"] if role == "defend" else bh["atk"])
		var pu := m * float(k["power"]) * q * mo * fa * tf * ct * beh
		total += pu
		acc["quality"] = float(acc["quality"]) + q * pu
		acc["morale"] = float(acc["morale"]) + mo * pu
		acc["fatigue"] = float(acc["fatigue"]) + fa * pu
		acc["terrain"] = float(acc["terrain"]) + tf * pu
		acc["counters"] = float(acc["counters"]) + ct * pu
		acc["behaviour"] = float(acc["behaviour"]) + beh * pu
	var power: float = total * cmd_f * form_f * sup_f * wx["all"] * season_f * surprise * pos_f
	var factors := {}
	if total > 0.0:
		for key: String in acc:
			factors[key] = snappedf(float(acc[key]) / total, 0.001)
	factors["commander"] = snappedf(cmd_f, 0.001)
	factors["formation"] = snappedf(form_f, 0.001)
	factors["supply"] = snappedf(sup_f, 0.001)
	factors["weather"] = snappedf(float(wx["all"]) * season_f, 0.001)
	factors["surprise"] = snappedf(surprise, 0.001)
	factors["position"] = snappedf(pos_f, 0.001)
	factors["numbers"] = snappedf(numbers, 0.001)
	return {"power": power, "men": men, "eff_men": eff, "factors": factors}
