class_name RAMilitary
extends RefCounted
## Military rank ladder, unit hierarchy and special divisions.
##
## The structure follows the depth of historical Chinese military organisation:
## a Hand of five, a Squad of ten, a Banner of fifty, a Company of a hundred,
## Battalions of five hundred, Regiments of 2,500 and Armies of 12,500. The rank
## titles are this world's own.
##
## Rank is earned by merit (see the War Merit Ledger). Merit only makes you
## *eligible*: an actual promotion still needs a vacancy and a superior who
## signs for it (RACareers handles seats). Pay is in gold per day, balanced
## against the village economy: a Sworn Soldier earns what a village guard earns
## (9), a Banner Sergeant what a sergeant earns (18), a Captain of a Hundred what
## the guard captain earns (30).
##
## The ladder queries are static. An instance is a nation's roster: who serves,
## their merit, rank and division. It serializes for save/load.

## Unit sizes, smallest first. "leader" is the lowest rank that commands one.
const UNITS: Array[Dictionary] = [
	{"id": "five", "name": "Hand", "size": 5, "leader": "hand_leader"},
	{"id": "ten", "name": "Squad", "size": 10, "leader": "tenwarden"},
	{"id": "fifty", "name": "Banner", "size": 50, "leader": "banner_sergeant"},
	{"id": "hundred", "name": "Company", "size": 100, "leader": "captain"},
	{"id": "battalion", "name": "Battalion", "size": 500, "leader": "battalion_warden"},
	{"id": "regiment", "name": "Regiment", "size": 2500, "leader": "standard_commander"},
	{"id": "army", "name": "Army", "size": 12500, "leader": "field_general"},
]
## Above one army the formation root is a Host of several armies.
const HOST := {"id": "host", "name": "Host", "size": 0, "leader": "grand_marshal"}

## The ladder, lowest first. Merit, pay and command never decrease going up.
## grade: "enlisted" | "nco" | "officer" | "general".
const RANKS: Array[Dictionary] = [
	{"id": "recruit", "title": "Levy Recruit", "grade": "enlisted", "command": 1, "merit": 0, "pay": 7},
	{"id": "soldier", "title": "Sworn Soldier", "grade": "enlisted", "command": 1, "merit": 25, "pay": 9},
	{"id": "veteran", "title": "Seasoned Blade", "grade": "enlisted", "command": 1, "merit": 60, "pay": 11},
	{"id": "hand_leader", "title": "Leader of Five", "grade": "nco", "command": 5, "merit": 90, "pay": 13},
	{"id": "tenwarden", "title": "Tenwarden", "grade": "nco", "command": 10, "merit": 130, "pay": 15},
	{"id": "banner_sergeant", "title": "Banner Sergeant", "grade": "nco", "command": 50, "merit": 190, "pay": 18},
	{"id": "company_second", "title": "Second of the Hundred", "grade": "officer", "command": 100, "merit": 280, "pay": 24},
	{"id": "captain", "title": "Captain of a Hundred", "grade": "officer", "command": 100, "merit": 400, "pay": 30},
	{"id": "battalion_second", "title": "Battalion Second", "grade": "officer", "command": 500, "merit": 600, "pay": 38},
	{"id": "battalion_warden", "title": "Warden of Five Hundred", "grade": "officer", "command": 500, "merit": 850, "pay": 48},
	{"id": "regiment_second", "title": "Standard Second", "grade": "officer", "command": 2500, "merit": 1200, "pay": 62},
	{"id": "standard_commander", "title": "Standard Commander", "grade": "officer", "command": 2500, "merit": 1600, "pay": 80},
	{"id": "army_second", "title": "Vice General", "grade": "general", "command": 12500, "merit": 2400, "pay": 105},
	{"id": "field_general", "title": "Field General", "grade": "general", "command": 12500, "merit": 3200, "pay": 140},
	{"id": "grand_marshal", "title": "Grand Marshal", "grade": "general", "command": 25000, "merit": 6000, "pay": 240},
]

## Per-nation overrides: local titles and a pay multiplier. Command sizes and
## merit thresholds stay the same so formations and promotion stay comparable.
const NATION_OVERRIDES := {
	"caldrenn": {"pay_mult": 1.0, "titles": {}},
	"seirune_isles": {"pay_mult": 1.1, "titles": {
		"soldier": "Sworn Retainer", "hand_leader": "Five-Blade", "tenwarden": "Ten-Blade",
		"banner_sergeant": "Banner Retainer", "captain": "House Captain",
		"battalion_warden": "Tide Commander", "standard_commander": "Sea Wall Commander",
		"field_general": "Admiral-General", "grand_marshal": "Regent's Marshal"}},
	"ongur_khanate": {"pay_mult": 0.8, "titles": {
		"soldier": "Rider", "hand_leader": "Hearth-Rider", "tenwarden": "Tenrider",
		"banner_sergeant": "Fifty-Rider", "captain": "Hundred-Khanling",
		"battalion_warden": "Horsetail Lord", "standard_commander": "Standard Khanling",
		"field_general": "Wind General", "grand_marshal": "Khan's Right Hand"}},
	"solmarch": {"pay_mult": 0.9, "titles": {
		"recruit": "Postulant-at-Arms", "soldier": "Faithful", "tenwarden": "Decurion of the Flame",
		"captain": "Knight-Captain", "battalion_warden": "Knight-Commander",
		"standard_commander": "Lord Preceptor", "field_general": "Crusade General",
		"grand_marshal": "Sword of the Hierarch"}},
	"urrokai_clanlands": {"pay_mult": 0.5, "titles": {
		"recruit": "Whelp", "soldier": "Tusk", "veteran": "Scarred", "tenwarden": "Fist-Leader",
		"banner_sergeant": "Boar-Leader", "captain": "War-Band Chief", "battalion_warden": "Clan Warlord",
		"field_general": "Warchief's Axe", "grand_marshal": "Warchief"}},
	"shenlu_peaks": {"pay_mult": 1.2, "titles": {
		"recruit": "Lowland Levy", "soldier": "Guard Disciple", "captain": "Peak Captain",
		"battalion_warden": "Summit Warden", "standard_commander": "Covenant Commander",
		"field_general": "Heaven General", "grand_marshal": "Covenant Marshal"}},
	"veylwood": {"pay_mult": 1.0, "titles": {
		"soldier": "Thorn", "tenwarden": "Branch-Warden", "captain": "Grove Captain",
		"battalion_warden": "Warden of Groves", "grand_marshal": "Warden of Thorns"}},
	"hollowdeep": {"pay_mult": 1.3, "titles": {
		"soldier": "Shieldbearer", "tenwarden": "Tunnel-Warden", "captain": "Hold Captain",
		"battalion_warden": "Gate Warden", "field_general": "Thane-General", "grand_marshal": "High Thane of War"}},
}

## Elite divisions. Entry needs the listed rank and merit plus any extra
## requirements (a sect background, a bloodline, a bond, a race...).
## "pay_bonus" is added to the member's rank pay per day.
const SPECIAL_DIVISIONS := {
	"runeward_legion": {"nation": "caldrenn", "name": "Runeward Legion", "role": "runestone defence and frontier garrisons",
		"size": 2500, "pay_bonus": 3,
		"requires": {"min_rank": "soldier", "min_merit": 40, "skills": {"runecraft": 10}}},
	"ember_lancers": {"nation": "caldrenn", "name": "Ember Lancers", "role": "royal heavy cavalry",
		"size": 500, "pay_bonus": 8,
		"requires": {"min_rank": "veteran", "min_merit": 150, "skills": {"riding": 30, "spear": 30}, "owns_warhorse": true}},
	"royal_soulbeast_riders": {"nation": "caldrenn", "name": "Royal Soulbeast Riders", "role": "elite bonded riders of the crown",
		"size": 50, "pay_bonus": 25,
		"requires": {"min_rank": "banner_sergeant", "min_merit": 400, "soulbeast_bond": true, "sect_any": ["royal_ember_academy"]}},
	"veiled_lantern_corps": {"nation": "seirune_isles", "name": "Veiled Lantern Corps", "role": "shadow warfare: infiltration, sabotage, assassination",
		"size": 500, "pay_bonus": 12,
		"requires": {"min_rank": "soldier", "min_merit": 100, "sect_any": ["hollow_moon_school"], "skills": {"stealth": 40}}},
	"oathblade_retinue": {"nation": "seirune_isles", "name": "Oathblade Retinue", "role": "sworn house swordsmen who fight under the house banner",
		"size": 2500, "pay_bonus": 6,
		"requires": {"min_rank": "soldier", "min_merit": 60, "skills": {"blade": 35}, "sworn_to_house": true}},
	"thousand_winds_horde": {"nation": "ongur_khanate", "name": "Thousand Winds Horde", "role": "horse archers",
		"size": 12500, "pay_bonus": 2,
		"requires": {"min_rank": "recruit", "min_merit": 0, "skills": {"riding": 25, "bow": 20}}},
	"skyhawk_riders": {"nation": "ongur_khanate", "name": "Skyhawk Riders", "role": "scouts and messengers who fly hawks and read the wind",
		"size": 100, "pay_bonus": 10,
		"requires": {"min_rank": "veteran", "min_merit": 180, "skills": {"riding": 50, "beast_taming": 30}, "affinity": "wind"}},
	"dawnflame_paladins": {"nation": "solmarch", "name": "Dawnflame Paladins", "role": "armoured holy knights wielding the Dawnflame",
		"size": 2500, "pay_bonus": 10,
		"requires": {"min_rank": "veteran", "min_merit": 200, "sect_any": ["dawnflame_seminary"], "affinity": "fire"}},
	"penitent_host": {"nation": "solmarch", "name": "Penitent Host", "role": "criminals and heretics serving to earn absolution",
		"size": 2500, "pay_bonus": -4,
		"requires": {"min_rank": "recruit", "min_merit": 0}},
	"bloodtusk_berserkers": {"nation": "urrokai_clanlands", "name": "Bloodtusk Berserkers", "role": "shock infantry of the Bloodroar",
		"size": 500, "pay_bonus": 4,
		"requires": {"min_rank": "soldier", "min_merit": 80, "race_any": ["orc"], "skills": {"axe": 30}}},
	"ninefold_sword_guard": {"nation": "shenlu_peaks", "name": "Ninefold Sword Guard", "role": "sect disciples lent to the Covenant in war",
		"size": 500, "pay_bonus": 15,
		"requires": {"min_rank": "soldier", "min_merit": 120, "sect_any": ["ninefold_sword_pavilion", "iron_lotus_monastery"]}},
	"thornwarden_rangers": {"nation": "veylwood", "name": "Thornwarden Rangers", "role": "forest wardens and archers",
		"size": 500, "pay_bonus": 6,
		"requires": {"min_rank": "soldier", "min_merit": 70, "skills": {"bow": 40}}},
	"anvil_guard": {"nation": "hollowdeep", "name": "Anvil Guard", "role": "heavy tunnel infantry in masterwork plate",
		"size": 500, "pay_bonus": 9,
		"requires": {"min_rank": "veteran", "min_merit": 120, "race_any": ["durrow"], "skills": {"hammer": 30}}},
}


## Battlefield troop types, after the classic Chinese arms: the dao swordsman
## with his round shield (pai), the spearman (qiang), the crossbowman (nu) and
## the horseman (qi). Squads read these (scripts/army/squad.gd).
## formations: the ones the troop drills, first is the default (Formation.Type
## names). morale: base steadiness 0..100. defence/damage/speed multiply the
## soldier's block chance, blow and march speed. anti_cavalry and charge scale
## the square/wedge effects. "requires": "horses" means cavalry only exists
## where the army can mount it. keep: character props (placeholders where the
## asset set has no spear or crossbow yet).
const UNIT_TYPES := {
	"sabre": {"name": "Dao Swordsmen", "short": "Sabres", "role": "line infantry with sabre and round shield",
		"formations": ["LINE", "SHIELD_WALL", "COLUMN", "WEDGE", "SQUARE", "SKIRMISH"],
		"morale": 70, "defence": 1.0, "damage": 1.0, "speed": 1.0, "anti_cavalry": 0.6, "charge": 1.0,
		"ranged": false, "keep": ["Knight_Helmet", "1H_Sword", "Round_Shield"]},
	"spear": {"name": "Spearmen", "short": "Spears", "role": "close-order pikes, the answer to horse",
		"formations": ["LINE", "SQUARE", "SHIELD_WALL", "COLUMN", "WEDGE"],
		"morale": 68, "defence": 1.1, "damage": 0.9, "speed": 0.95, "anti_cavalry": 1.5, "charge": 0.8,
		"ranged": false, "keep": ["Knight_Helmet", "2H_Sword"]},
	"crossbow": {"name": "Crossbowmen", "short": "Crossbows", "role": "massed crossbow volleys from loose order",
		"formations": ["SKIRMISH", "LINE", "COLUMN"],
		"morale": 55, "defence": 0.7, "damage": 0.7, "speed": 1.05, "anti_cavalry": 0.3, "charge": 0.5,
		"ranged": true, "range": 60.0, "keep": ["Knight_Helmet", "1H_Sword"]},
	"cavalry": {"name": "Horsemen", "short": "Cavalry", "role": "shock horse that breaks wavering lines",
		"formations": ["WEDGE", "LINE", "COLUMN", "SKIRMISH"],
		"morale": 75, "defence": 0.9, "damage": 1.3, "speed": 1.9, "anti_cavalry": 0.2, "charge": 1.8,
		"ranged": false, "requires": "horses", "keep": ["Knight_Helmet", "1H_Sword", "Round_Shield"]},
}

## How much a present officer of this rank steadies men near him (morale
## points). NCOs steady their file, officers their company, generals the army.
const OFFICER_STEADINESS := {"nco": 6.0, "officer": 14.0, "general": 22.0}
## And how far his voice carries, metres.
const OFFICER_RADIUS := {"nco": 10.0, "officer": 20.0, "general": 35.0}


static func unit_type(type_id: String) -> Dictionary:
	return UNIT_TYPES.get(type_id, UNIT_TYPES["sabre"])


## Troop types an army can field: cavalry needs horses.
static func available_unit_types(has_horses: bool) -> Array[String]:
	var out: Array[String] = []
	for id: String in UNIT_TYPES:
		if UNIT_TYPES[id].get("requires", "") == "horses" and not has_horses:
			continue
		out.append(id)
	return out


## Morale an officer of this rank adds to men within officer_radius(). Enlisted
## soldiers add nothing.
static func steadiness(rank_id: String) -> float:
	return float(OFFICER_STEADINESS.get(str(rank(rank_id).get("grade", "")), 0.0))


static func officer_radius(rank_id: String) -> float:
	return float(OFFICER_RADIUS.get(str(rank(rank_id).get("grade", "")), 0.0))


# --- Ladder queries (static) -------------------------------------------------

static func rank_index(rank_id: String) -> int:
	for i in RANKS.size():
		if RANKS[i]["id"] == rank_id:
			return i
	return -1


static func rank(rank_id: String) -> Dictionary:
	var i := rank_index(rank_id)
	return RANKS[i] if i >= 0 else {}


## Highest rank whose merit requirement is met.
static func rank_for_merit(merit: int) -> Dictionary:
	var best: Dictionary = RANKS[0]
	for r: Dictionary in RANKS:
		if merit >= int(r["merit"]):
			best = r
	return best


## The rank above, or {} at the top.
static func next_rank(rank_id: String) -> Dictionary:
	var i := rank_index(rank_id)
	if i < 0 or i + 1 >= RANKS.size():
		return {}
	return RANKS[i + 1]


## Merit still needed for the next rank (0 at the top).
static func merit_to_next(rank_id: String, merit: int) -> int:
	var n := next_rank(rank_id)
	return 0 if n.is_empty() else maxi(0, int(n["merit"]) - merit)


static func command_size(rank_id: String) -> int:
	var r := rank(rank_id)
	return int(r.get("command", 0))


## Daily pay in gold, after the nation's multiplier (and a division bonus).
static func pay(rank_id: String, nation := "", division := "") -> int:
	var r := rank(rank_id)
	if r.is_empty():
		return 0
	var mult := 1.0
	if NATION_OVERRIDES.has(nation):
		mult = float(NATION_OVERRIDES[nation]["pay_mult"])
	var bonus := 0
	if SPECIAL_DIVISIONS.has(division):
		bonus = int(SPECIAL_DIVISIONS[division]["pay_bonus"])
	return maxi(1, int(round(float(r["pay"]) * mult)) + bonus)


## The rank's title as a given nation says it.
static func title(rank_id: String, nation := "") -> String:
	if NATION_OVERRIDES.has(nation):
		var t: Dictionary = NATION_OVERRIDES[nation]["titles"]
		if t.has(rank_id):
			return t[rank_id]
	return str(rank(rank_id).get("title", ""))


static func divisions_of(nation: String) -> Array[String]:
	var out: Array[String] = []
	for id: String in SPECIAL_DIVISIONS:
		if SPECIAL_DIVISIONS[id]["nation"] == nation:
			out.append(id)
	return out


## Why a candidate cannot join a division ("" means they can).
## candidate: {rank, merit, nation, race, sects: [], skills: {}, affinity,
## soulbeast_bond, owns_warhorse, sworn_to_house}
static func check_division(division: String, candidate: Dictionary) -> String:
	if not SPECIAL_DIVISIONS.has(division):
		return "No such division."
	var d: Dictionary = SPECIAL_DIVISIONS[division]
	var req: Dictionary = d["requires"]
	if str(candidate.get("nation", d["nation"])) != d["nation"]:
		return "The %s only takes subjects of its own nation." % d["name"]
	if rank_index(str(candidate.get("rank", "recruit"))) < rank_index(req["min_rank"]):
		return "Needs the rank of %s." % title(req["min_rank"], d["nation"])
	if int(candidate.get("merit", 0)) < int(req["min_merit"]):
		return "Needs %d merit." % int(req["min_merit"])
	if req.has("race_any") and not (req["race_any"] as Array).has(candidate.get("race", "human")):
		return "Only %s may join." % ", ".join(req["race_any"])
	if req.has("sect_any"):
		var ok := false
		for s: Variant in candidate.get("sects", []):
			if (req["sect_any"] as Array).has(s):
				ok = true
		if not ok:
			return "Needs training at %s." % " or ".join(req["sect_any"])
	if req.has("affinity") and str(candidate.get("affinity", "")) != req["affinity"]:
		return "Needs a %s affinity." % req["affinity"]
	var skills: Dictionary = candidate.get("skills", {})
	var need: Dictionary = req.get("skills", {})
	for sk: String in need:
		if int(skills.get(sk, 0)) < int(need[sk]):
			return "Needs %s %d." % [sk, int(need[sk])]
	for flag: String in ["soulbeast_bond", "owns_warhorse", "sworn_to_house"]:
		if req.get(flag, false) and not candidate.get(flag, false):
			return "Needs %s." % flag.replace("_", " ")
	return ""


# --- Formations --------------------------------------------------------------

## Unit table index for a unit id (-1 for the host).
static func unit_index(unit_id: String) -> int:
	for i in UNITS.size():
		if UNITS[i]["id"] == unit_id:
			return i
	return -1


## Formation tree for a troop count. Every node is
## {unit, name, troops, leader_rank, leader_title, children: [...]}. Leaves are
## Hands of at most five. Each node's troops is the sum of its children, so the
## leaves sum to the total. A partial unit (the remainder) keeps its unit type.
static func build_formation(troops: int, nation := "") -> Dictionary:
	troops = maxi(troops, 0)
	var army_size: int = UNITS[UNITS.size() - 1]["size"]
	if troops > army_size:
		var host := _node(HOST, troops, nation)
		var left := troops
		while left > 0:
			var n := mini(left, army_size)
			host["children"].append(_build(UNITS.size() - 1, n, nation))
			left -= n
		return host
	# Smallest unit type that can hold everyone.
	var level := 0
	while level < UNITS.size() - 1 and int(UNITS[level]["size"]) < troops:
		level += 1
	return _build(level, troops, nation)


static func _build(level: int, troops: int, nation: String) -> Dictionary:
	var node := _node(UNITS[level], troops, nation)
	if level == 0:
		return node
	var child_size: int = UNITS[level - 1]["size"]
	var left := troops
	while left > 0:
		var n := mini(left, child_size)
		node["children"].append(_build(level - 1, n, nation))
		left -= n
	return node


static func _node(unit: Dictionary, troops: int, nation: String) -> Dictionary:
	var children: Array[Dictionary] = []
	return {
		"unit": unit["id"], "name": unit["name"], "troops": troops,
		"leader_rank": unit["leader"], "leader_title": title(unit["leader"], nation),
		"children": children,
	}


## Sum of troops in the leaves of a formation tree.
static func formation_troops(node: Dictionary) -> int:
	var kids: Array = node["children"]
	if kids.is_empty():
		return int(node["troops"])
	var total := 0
	for c: Dictionary in kids:
		total += formation_troops(c)
	return total


## How many of each unit type a formation contains, e.g. {"five": 4, "ten": 2}.
static func formation_counts(node: Dictionary, into: Dictionary = {}) -> Dictionary:
	into[node["unit"]] = int(into.get(node["unit"], 0)) + 1
	for c: Dictionary in node["children"]:
		formation_counts(c, into)
	return into


# --- Roster (instance) -------------------------------------------------------

var home_nation := "caldrenn"
## person id -> {merit: int, rank: String, division: String}
var members: Dictionary = {}


func _init(nation_id := "caldrenn") -> void:
	home_nation = nation_id


func enlist(person: int, merit := 0) -> Dictionary:
	var r := rank_for_merit(merit)
	members[person] = {"merit": merit, "rank": "recruit" if merit <= 0 else str(r["id"]), "division": ""}
	return members[person]


## Records merit. Returns the rank the person is now *eligible* for (their
## held rank only changes through promote(), which needs a vacancy).
func add_merit(person: int, amount: int) -> Dictionary:
	if not members.has(person):
		enlist(person)
	members[person]["merit"] = int(members[person]["merit"]) + amount
	return rank_for_merit(int(members[person]["merit"]))


func eligible_for_promotion(person: int) -> bool:
	if not members.has(person):
		return false
	var m: Dictionary = members[person]
	var n := next_rank(m["rank"])
	return not n.is_empty() and int(m["merit"]) >= int(n["merit"])


## Promote one step if merit allows. Returns "" on success or the reason.
func promote(person: int) -> String:
	if not members.has(person):
		return "Not enlisted."
	var m: Dictionary = members[person]
	var n := next_rank(m["rank"])
	if n.is_empty():
		return "Already at the top of the ladder."
	if int(m["merit"]) < int(n["merit"]):
		return "Needs %d merit for %s." % [int(n["merit"]), title(n["id"], home_nation)]
	m["rank"] = n["id"]
	return ""


func join_division(person: int, division: String, candidate: Dictionary = {}) -> String:
	if not members.has(person):
		return "Not enlisted."
	var c := candidate.duplicate()
	c["rank"] = members[person]["rank"]
	c["merit"] = members[person]["merit"]
	c["nation"] = home_nation
	var why := check_division(division, c)
	if why.is_empty():
		members[person]["division"] = division
	return why


func daily_pay(person: int) -> int:
	if not members.has(person):
		return 0
	var m: Dictionary = members[person]
	return pay(m["rank"], home_nation, m["division"])


func serialize() -> Dictionary:
	var out := {}
	for p: int in members:
		out[str(p)] = members[p].duplicate()
	return {"nation": home_nation, "members": out}


func deserialize(data: Dictionary) -> void:
	home_nation = str(data.get("nation", home_nation))
	members.clear()
	var m: Dictionary = data.get("members", {})
	for k: String in m:
		var e: Dictionary = m[k]
		members[int(k)] = {"merit": int(e.get("merit", 0)), "rank": str(e.get("rank", "recruit")),
			"division": str(e.get("division", ""))}
