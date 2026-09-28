extends RefCounted
## Noble houses of Caldrenn: who owns the land, and who is winning.
## (docs/RISING_ASHES_LIFE_SIM_DESIGN.md, "Property, nobility, lordship" /
## "Phase 3: nobility and lordship")
##
## About HOUSE_COUNT noble houses are generated deterministically from the
## world seed, named from the Caldric culture (data/world/cultures.json via
## Life.lore), each with a head, heirs, a few other members, sigil colour,
## wealth, influence and standing with the Crown.
##
## Holdings: every non-capital settlement is a house's fief (a few are kept as
## crown land); the mine (WorldGen.sites kind "mine"), every farm's windmill/
## mill (kind "farm"), every bridge (kind "bridge"), Duskbriar Wood and fishing
## rights on Emberglass Mere and the Ashrun are also held by a house. Toll
## rights on every road that doesn't touch the capital belong to whichever
## house holds its non-capital end.
##
## Politics run once a day (see `daily`): houses drift in wealth and influence,
## may feud (raising border risk near their lands, `border_risk_bonus`), may
## marry into alliance, and a struggling house may sell a village, a mill or
## its forest holding to a richer house or the Crown. An event log
## (`event_log`, `MAX_EVENTS_PER_DAY` a day) and `rumours()` describe it all.
##
## The player's standing with a house is opinion (-100..100) via
## `Life.relationships`'s faction reputation (one faction per house, "house_
## <id>") when available, falling back to a small table of our own. High
## opinion unlocks sponsorship (`sponsor`, feeds career_ladders.gd's
## sponsor_tier via Life.career_sponsor_tier), a discounted lease
## (`lease_offer`), a gold loan (`request_loan`), an arranged introduction
## (`arrange_introduction`) and land for military service (
## `grant_land_for_service`, captain rank and up). Low opinion is hostile
## (`is_hostile`): higher taxes (`tax_multiplier`) and, rarely, the house
## "sends men" (an event only, for now -- other systems can read `is_hostile`).
##
## Buying a struggling house's holding (`buy_holding`) or being granted one
## for service marks that settlement's owner as "player" and, if
## `Life.lordship` exists (another system), calls its `grant(idx, reason)`.
##
## Pure data (RefCounted, serialisable): house identity and the initial
## (base) holding layout are regenerated deterministically from the seed every
## run, like property.gd's registry; only what changes over play (wealth,
## influence, standing, feuds, alliances, ownership changes, the event log,
## player standing, loans) is serialized.

const RAWorldLore := preload("res://scripts/sim/world_lore.gd")

const HOUSE_COUNT := 6
const CROWN := "crown"
const PLAYER := "player"
const CROWN_LAND_COUNT := 2
const TRAITS: Array[String] = ["ambitious", "honourable", "greedy", "pious", "martial"]
const FALLBACK_FAMILIES: Array[String] = ["Ashdown", "Barrowby", "Coldbrook", "Fairweather", "Hollins", "Marlowe"]
const FALLBACK_FIRST := {"male": ["Aldric", "Bram", "Corwin", "Edric", "Garrett", "Osric"],
	"female": ["Ailsa", "Brenna", "Elspeth", "Maren", "Rosalind", "Wenna"]}
const FALLBACK_SIGILS := ["#A23B24", "#5E6B3A", "#3B4C6B", "#8B1E14", "#6B4F36", "#5A5F66"]

const START_WEALTH_MIN := 2000
const START_WEALTH_MAX := 9000
const START_INFLUENCE_MIN := 20.0
const START_INFLUENCE_MAX := 70.0
const STRUGGLE_WEALTH := 800
const SPONSOR_OPINION := 30.0        # Relationships.FRIEND_AT
const CLOSE_OPINION := 65.0          # Relationships.CLOSE_FRIEND_AT
const HOSTILE_OPINION := -25.0       # Relationships.RIVAL_AT
const MAX_EVENTS_PER_DAY := 3
const MAX_LOG := 200
const FEUD_DAILY_CHANCE := 0.012
const MARRIAGE_DAILY_CHANCE := 0.006
const SALE_DAILY_CHANCE := 0.05
const HOSTILE_SEND_MEN_CHANCE := 0.02
const TOLL_BASE := 6
const LOAN_INTEREST := 0.2
const LOAN_TERM_DAYS := 56
const SOLDIER_RANKS_FOR_LAND: Array[String] = ["captain", "commander", "general"]

## houses[i]: {id, name, sigil_color, head: {name, gender, age, traits},
##             heirs: [{name, gender, age}], members: [{name, gender, age, role}], traits}
var houses: Array[Dictionary] = []
var _house_index: Dictionary = {}    # id -> index into houses

var wealth: Dictionary = {}          # house_id -> int
var influence: Dictionary = {}       # house_id -> float (0..100)
var crown_standing: Dictionary = {}  # house_id -> float (-100..100)

## String(settlement idx) -> house_id ("crown", "player" or a house id).
var _settlement_owner: Dictionary = {}
## String(WorldGen.sites id) -> house_id, for kind == "farm" (the windmill/mill).
var _mill_owner: Dictionary = {}
var _forest_owner := ""
## Static once generated (not sold): site id -> house_id.
var _bridge_owner: Dictionary = {}
## Static: "mere" / "ashrun" -> house_id.
var _fishing_owner: Dictionary = {"mere": "", "ashrun": ""}
## Static: "a,b" (sorted settlement ids) -> house_id owed toll ("" = none / crown road).
var _toll_owner: Dictionary = {}
var _mine_owner := ""
var _capital_id := -1

var feuds_list: Array[Dictionary] = []      # {house_a, house_b, since_day, cause}
var alliances: Array = []                   # [house_a, house_b, since_day]
var event_log: Array[Dictionary] = []       # {day, text}
var player_standing: Dictionary = {}        # house_id -> float, used only if Relationships is unavailable
var loans: Array[Dictionary] = []           # {house_id, amount, owed, due_day}

var _seed_value := 0
var _last_day := -1
var _events_today := 0


func _init(seed_value := -1) -> void:
	_seed_value = seed_value if seed_value >= 0 else WorldSim.SEED
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed_value * 7919 + 4021
	_generate_houses(rng)
	_generate_holdings(rng)
	for h: Dictionary in houses:
		wealth[h["id"]] = rng.randi_range(START_WEALTH_MIN, START_WEALTH_MAX)
		influence[h["id"]] = rng.randf_range(START_INFLUENCE_MIN, START_INFLUENCE_MAX)
		crown_standing[h["id"]] = rng.randf_range(-20.0, 40.0)


# --- generation --------------------------------------------------------------------

static func _seeded_shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


## The Caldric culture, read straight from the data file: houses are generated while
## the Life autoload itself is still being built, so Life.lore may not exist yet.
func _culture() -> Dictionary:
	var path := "res://data/world/cultures.json"
	if not FileAccess.file_exists(path):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if data is Dictionary:
		for c: Variant in (data as Dictionary).get("cultures", []):
			if c is Dictionary and String((c as Dictionary).get("id", "")) == "caldric":
				return c
	return {}


func _person_name(firsts: Dictionary, family: String, rng: RandomNumberGenerator, gender: String) -> String:
	var list: Array = firsts.get(gender, firsts.get("male", ["Aldric"]))
	var given: String = list[rng.randi() % list.size()]
	return "%s %s" % [given, family]


func _generate_houses(rng: RandomNumberGenerator) -> void:
	houses.clear()
	_house_index.clear()
	var culture := _culture()
	var families: Array = culture.get("family_names", FALLBACK_FAMILIES.duplicate())
	var firsts: Dictionary = culture.get("first_names", FALLBACK_FIRST)
	var palette: Array = culture.get("clothing_palette", [])
	var pool := families.duplicate()
	_seeded_shuffle(pool, rng)
	var n := mini(HOUSE_COUNT, pool.size())
	for i in n:
		var family: String = pool[i]
		var house_id := "house_%s" % family.to_lower().replace(" ", "_").replace("'", "")
		var head_gender := "male" if rng.randi() % 2 == 0 else "female"
		var head := {"name": _person_name(firsts, family, rng, head_gender), "gender": head_gender,
			"age": rng.randi_range(38, 62), "traits": _pick_traits(rng)}
		var heirs: Array = []
		for _k in rng.randi_range(1, 2):
			var g := "male" if rng.randi() % 2 == 0 else "female"
			heirs.append({"name": _person_name(firsts, family, rng, g), "gender": g,
				"age": rng.randi_range(6, int(head["age"]) - 18) if int(head["age"]) > 26 else rng.randi_range(2, 16)})
		var members: Array = []
		for _k in rng.randi_range(1, 3):
			var g2 := "male" if rng.randi() % 2 == 0 else "female"
			var roles := ["sibling", "cousin", "steward", "aunt", "uncle"]
			members.append({"name": _person_name(firsts, family, rng, g2), "gender": g2,
				"age": rng.randi_range(20, 70), "role": roles[rng.randi() % roles.size()]})
		var sigil := "#%06X" % (rng.randi() % 0xFFFFFF) if palette.is_empty() else \
			String(palette[rng.randi() % palette.size()].get("hex", FALLBACK_SIGILS[i % FALLBACK_SIGILS.size()]))
		houses.append({"id": house_id, "name": "House %s" % family, "sigil_color": sigil,
			"head": head, "heirs": heirs, "members": members, "traits": _pick_traits(rng)})
		_house_index[house_id] = houses.size() - 1


func _pick_traits(rng: RandomNumberGenerator) -> Array[String]:
	var pool := TRAITS.duplicate()
	_seeded_shuffle(pool, rng)
	var out: Array[String] = []
	for i in rng.randi_range(1, 3):
		out.append(pool[i])
	return out


func _nearest_settlement_id(pos: Vector2) -> int:
	var best := -1
	var best_d := INF
	for s: Dictionary in WorldGen.settlements:
		var d: float = pos.distance_squared_to(s["pos"])
		if d < best_d:
			best_d = d
			best = int(s["id"])
	return best


func _find_sites(kind: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for site: Dictionary in WorldGen.sites:
		if String(site.get("kind", "")) == kind:
			out.append(site)
	return out


static func _road_key(a: int, b: int) -> String:
	return "%d,%d" % [mini(a, b), maxi(a, b)]


func _random_house_id(rng: RandomNumberGenerator) -> String:
	return String(houses[rng.randi() % houses.size()]["id"]) if not houses.is_empty() else CROWN


func _generate_holdings(rng: RandomNumberGenerator) -> void:
	_settlement_owner.clear()
	_mill_owner.clear()
	_bridge_owner.clear()
	_toll_owner.clear()
	_capital_id = -1
	var non_capital: Array[int] = []
	for s: Dictionary in WorldGen.settlements:
		if String(s["kind"]) == "castle":
			_capital_id = int(s["id"])
		else:
			non_capital.append(int(s["id"]))
	_seeded_shuffle(non_capital, rng)
	var crown_take := mini(CROWN_LAND_COUNT, maxi(0, non_capital.size() - houses.size()))
	for i in crown_take:
		_settlement_owner[str(non_capital[i])] = CROWN
	for i in range(crown_take, non_capital.size()):
		var house_i := (i - crown_take) % maxi(1, houses.size())
		_settlement_owner[str(non_capital[i])] = _random_house_id_at(house_i)
	if _capital_id >= 0:
		_settlement_owner[str(_capital_id)] = CROWN
	# Mine: one house holds the mine.
	_mine_owner = _random_house_id(rng) if not _find_sites("mine").is_empty() else ""
	# Mills follow whoever holds the village the windmill serves.
	for site: Dictionary in _find_sites("farm"):
		var near := _nearest_settlement_id(site["pos"])
		_mill_owner[str(int(site["id"]))] = String(_settlement_owner.get(str(near), CROWN))
	# Bridges: whoever holds the nearer settlement (kingdom roads default to the Crown).
	for site: Dictionary in _find_sites("bridge"):
		var near := _nearest_settlement_id(site["pos"])
		var owner := String(_settlement_owner.get(str(near), ""))
		_bridge_owner[str(int(site["id"]))] = owner if owner != "" and owner != CROWN else _random_house_id(rng)
	# Forest (Duskbriar Wood) and fishing rights (Emberglass Mere, the Ashrun).
	_forest_owner = _random_house_id(rng)
	_fishing_owner["mere"] = _random_house_id(rng)
	_fishing_owner["ashrun"] = _random_house_id(rng)
	# Tolls: any road that doesn't touch the capital is taxed by whoever holds
	# its lower-id (non-capital) end.
	for r: Vector2i in WorldGen.roads:
		if r.x == _capital_id or r.y == _capital_id:
			continue
		var low := mini(r.x, r.y)
		_toll_owner[_road_key(r.x, r.y)] = String(_settlement_owner.get(str(low), ""))


func _random_house_id_at(i: int) -> String:
	return String(houses[i]["id"]) if i >= 0 and i < houses.size() else CROWN


# --- lookups -------------------------------------------------------------------------

func house_by_id(house_id: String) -> Dictionary:
	if _house_index.has(house_id):
		return houses[int(_house_index[house_id])]
	return {}


func house_name(house_id: String) -> String:
	if house_id == "" or house_id == CROWN:
		return "the Crown"
	if house_id == PLAYER:
		return "you"
	var h := house_by_id(house_id)
	return String(h.get("name", "the Crown")) if not h.is_empty() else "the Crown"


## {house_id, name}: name is ready to show as a landlord (property.gd reads this).
func landlord_for_settlement(idx: int) -> Dictionary:
	var hid := String(_settlement_owner.get(str(idx), CROWN))
	return {"house_id": hid, "name": house_name(hid)}


func settlement_owner(idx: int) -> String:
	return String(_settlement_owner.get(str(idx), CROWN))


## Settlement indices currently held by `house_id` (village/town fiefs only).
func fiefs_of(house_id: String) -> Array[int]:
	var out: Array[int] = []
	for k: String in _settlement_owner:
		if String(_settlement_owner[k]) == house_id:
			out.append(int(k))
	out.sort()
	return out


## The house's biggest fief (by population), or -1 if it holds none.
func primary_fief(house_id: String) -> int:
	var best := -1
	var best_pop := -1
	for idx: int in fiefs_of(house_id):
		var pop := int(WorldGen.settlements[idx]["population"])
		if pop > best_pop:
			best_pop = pop
			best = idx
	return best


func mills_of(house_id: String) -> Array[int]:
	var out: Array[int] = []
	for k: String in _mill_owner:
		if String(_mill_owner[k]) == house_id:
			out.append(int(k))
	return out


func holds_mine(house_id: String) -> bool:
	return _mine_owner == house_id


func holds_forest(house_id: String) -> bool:
	return _forest_owner == house_id


func bridges_of(house_id: String) -> Array[int]:
	var out: Array[int] = []
	for k: String in _bridge_owner:
		if String(_bridge_owner[k]) == house_id:
			out.append(int(k))
	return out


func fishing_rights_of(house_id: String) -> Array[String]:
	var out: Array[String] = []
	for water: String in _fishing_owner:
		if String(_fishing_owner[water]) == house_id:
			out.append(water)
	return out


## {settlements, mills, bridges, forest, mine, fishing, toll_roads} -- everything
## a house holds, for the Nobility screen and rumours.
func holdings_of(house_id: String) -> Dictionary:
	var tolls: Array = []
	for key: String in _toll_owner:
		if String(_toll_owner[key]) == house_id:
			var ab := key.split(",")
			tolls.append(Vector2i(int(ab[0]), int(ab[1])))
	return {"settlements": fiefs_of(house_id), "mills": mills_of(house_id), "bridges": bridges_of(house_id),
		"forest": holds_forest(house_id), "mine": holds_mine(house_id),
		"fishing": fishing_rights_of(house_id), "toll_roads": tolls}


## Every non-capital settlement has some landlord: a house, the Crown or the player.
func all_settlements_have_landlords() -> bool:
	for s: Dictionary in WorldGen.settlements:
		if String(s["kind"]) == "castle":
			continue
		if not _settlement_owner.has(str(int(s["id"]))):
			return false
	return true


## Toll charged to the player on the road between settlements a and b (0 if
## the road is unowned, a crown road, or no house holds it). economy.gd's
## toll_for_road() calls this when Life.nobility exists.
func toll_for_road(a: int, b: int) -> int:
	var owner := String(_toll_owner.get(_road_key(a, b), ""))
	if owner == "" or owner == CROWN or owner == PLAYER:
		return 0
	var h := house_by_id(owner)
	var mult := 1.5 if (h.get("traits", []) as Array).has("greedy") else 1.0
	return int(round(TOLL_BASE * mult))


# --- player standing -----------------------------------------------------------------

static func _faction_id(house_id: String) -> String:
	return "house_%s" % house_id


func opinion(house_id: String) -> float:
	var rel: Object = Life.get("relationships")
	if rel != null and rel.has_method("rep"):
		var fid := _faction_id(house_id)
		if not (rel.faction_names as Dictionary).has(fid):
			rel.add_faction(fid, house_name(house_id), 0.0)
		return rel.rep(fid)
	return float(player_standing.get(house_id, 0.0))


func change_opinion(house_id: String, delta: float) -> float:
	var rel: Object = Life.get("relationships")
	if rel != null and rel.has_method("change_rep"):
		return rel.change_rep(_faction_id(house_id), delta)
	var v := clampf(float(player_standing.get(house_id, 0.0)) + delta, -100.0, 100.0)
	player_standing[house_id] = v
	return v


func is_hostile(house_id: String) -> bool:
	return opinion(house_id) <= HOSTILE_OPINION


## Raised taxes from a house that thinks poorly of you.
func tax_multiplier(house_id: String) -> float:
	return 1.5 if is_hostile(house_id) else 1.0


func is_struggling(house_id: String) -> bool:
	return int(wealth.get(house_id, 0)) < STRUGGLE_WEALTH


# --- services --------------------------------------------------------------------

## Relationships.tier_rank equivalent, from opinion alone (>= 4 is "friend").
func sponsor_tier(house_id: String) -> int:
	var op := opinion(house_id)
	if op >= CLOSE_OPINION:
		return 5
	if op >= SPONSOR_OPINION:
		return 4
	if op <= HOSTILE_OPINION:
		return 0
	return 2


## {ok, tier, text}: on success the caller sets
## Life.career_sponsor_tier = maxi(Life.career_sponsor_tier, tier).
func sponsor(house_id: String) -> Dictionary:
	if opinion(house_id) < SPONSOR_OPINION:
		return {"ok": false, "tier": 0, "text": "\"I don't yet know you well enough to vouch for you.\""}
	return {"ok": true, "tier": sponsor_tier(house_id), "text": "%s agrees to sponsor your advancement." % house_name(house_id)}


## A discount on a lease worth `base_price` gold, offered only at friendly opinion.
func lease_offer(house_id: String, base_price: int) -> Dictionary:
	if opinion(house_id) < SPONSOR_OPINION:
		return {"ok": false, "price": base_price, "text": "\"Full price, same as anyone.\""}
	var price := int(round(base_price * 0.7))
	return {"ok": true, "price": price, "text": "%s offers you a lease at a friendly rate: %d gold." % [house_name(house_id), price]}


## A gold loan against the house's own coffers, at LOAN_INTEREST, due in
## LOAN_TERM_DAYS. Adds gold immediately; daily() collects or penalises it.
func request_loan(house_id: String, amount: int) -> Dictionary:
	if opinion(house_id) < SPONSOR_OPINION:
		return {"ok": false, "text": "\"I extend credit to my friends, not to strangers.\""}
	if amount <= 0 or int(wealth.get(house_id, 0)) < amount:
		return {"ok": false, "text": "%s doesn't have that much to lend." % house_name(house_id)}
	Game.add_gold(amount)
	wealth[house_id] = int(wealth[house_id]) - amount
	var owed := int(round(amount * (1.0 + LOAN_INTEREST)))
	loans.append({"house_id": house_id, "amount": amount, "owed": owed, "due_day": WorldSim.day + LOAN_TERM_DAYS})
	return {"ok": true, "owed": owed, "text": "%s lends you %d gold; %d gold is owed in %d days." %
		[house_name(house_id), amount, owed, LOAN_TERM_DAYS]}


## A favour spent: a word put in for you at court or with another faction.
func arrange_introduction(house_id: String) -> Dictionary:
	if opinion(house_id) < SPONSOR_OPINION:
		return {"ok": false, "text": "\"I have no introductions to spare for you.\""}
	change_opinion(house_id, -2.0)
	var rel: Object = Life.get("relationships")
	if rel != null and rel.has_method("change_rep"):
		rel.change_rep("crown_caldrenn", 3.0)
	return {"ok": true, "text": "%s arranges an introduction at court on your behalf." % house_name(house_id)}


## Grants the player one of the house's fiefs for military service (captain
## rank and up, and only at friendly opinion). Calls Life.lordship.grant() if
## that system exists.
func grant_land_for_service(house_id: String, soldier_rank_id: String) -> Dictionary:
	if not SOLDIER_RANKS_FOR_LAND.has(soldier_rank_id):
		return {"ok": false, "text": "That rank isn't yet trusted with land."}
	if opinion(house_id) < SPONSOR_OPINION:
		return {"ok": false, "text": "%s does not think well enough of you yet." % house_name(house_id)}
	var candidates := fiefs_of(house_id)
	if candidates.is_empty():
		return {"ok": false, "text": "%s has no land left to grant." % house_name(house_id)}
	var idx: int = candidates[0]
	_settlement_owner[str(idx)] = PLAYER
	var lordship: Object = Life.get("lordship")
	if lordship != null and lordship.has_method("grant"):
		lordship.call("grant", idx, "military_service")
	var name := String(WorldGen.settlements[idx]["name"])
	_log(WorldSim.day, "%s grants you %s for your service." % [house_name(house_id), name])
	if Life.get("biography") != null:
		Life.biography.add_highlight("Granted the settlement of %s for military service" % name, WorldSim.day)
	return {"ok": true, "settlement": idx, "text": "You are granted %s." % name}


## Only a struggling house sells. kind: "settlement", "mill" or "forest"; ref
## is a settlement idx, a mill site id, or ignored for "forest".
func can_buy_holding(house_id: String, kind: String, ref: int) -> String:
	if not is_struggling(house_id):
		return "%s isn't willing to sell; they aren't struggling." % house_name(house_id)
	match kind:
		"settlement":
			if String(_settlement_owner.get(str(ref), "")) != house_id:
				return "%s doesn't hold that." % house_name(house_id)
		"mill":
			if String(_mill_owner.get(str(ref), "")) != house_id:
				return "%s doesn't hold that." % house_name(house_id)
		"forest":
			if _forest_owner != house_id:
				return "%s doesn't hold that." % house_name(house_id)
		_:
			return "Unknown holding."
	return ""


func _holding_price(kind: String, ref: int) -> int:
	match kind:
		"settlement":
			return 400 + int(WorldGen.settlements[ref]["population"]) * 2
		"mill":
			return 350
		_:
			return 300


## Buys a struggling house's holding outright. {ok, text}.
func buy_holding(house_id: String, kind: String, ref: int) -> Dictionary:
	var why := can_buy_holding(house_id, kind, ref)
	if why != "":
		return {"ok": false, "text": why}
	var price := _holding_price(kind, ref)
	if Game.gold < price:
		return {"ok": false, "text": "Needs %d gold (have %d)." % [price, Game.gold]}
	Game.add_gold(-price)
	wealth[house_id] = int(wealth.get(house_id, 0)) + price
	var label := ""
	match kind:
		"settlement":
			_settlement_owner[str(ref)] = PLAYER
			label = String(WorldGen.settlements[ref]["name"])
			var lordship: Object = Life.get("lordship")
			if lordship != null and lordship.has_method("grant"):
				lordship.call("grant", ref, "purchase")
		"mill":
			_mill_owner[str(ref)] = PLAYER
			label = "a mill"
		"forest":
			_forest_owner = PLAYER
			label = "the forest holding"
	_log(WorldSim.day, "You bought %s from %s." % [label, house_name(house_id)])
	if Life.get("biography") != null:
		Life.biography.add_highlight("Bought %s from %s" % [label, house_name(house_id)], WorldSim.day)
	return {"ok": true, "text": "You now hold %s (%d gold)." % [label, price]}


# --- feuds -------------------------------------------------------------------------

func feuds() -> Array[Dictionary]:
	return feuds_list.duplicate(true)


func feud_between(a: String, b: String) -> bool:
	for f: Dictionary in feuds_list:
		if (String(f["house_a"]) == a and String(f["house_b"]) == b) or (String(f["house_a"]) == b and String(f["house_b"]) == a):
			return true
	return false


func allied(a: String, b: String) -> bool:
	for al: Array in alliances:
		if (String(al[0]) == a and String(al[1]) == b) or (String(al[0]) == b and String(al[1]) == a):
			return true
	return false


## Extra danger near a settlement whose house is in an active feud (other
## systems -- bandit activity, border skirmishes -- can add this in).
func border_risk_bonus(settlement_idx: int) -> float:
	var owner := settlement_owner(settlement_idx)
	if owner == CROWN or owner == PLAYER or owner == "":
		return 0.0
	var bonus := 0.0
	for f: Dictionary in feuds_list:
		if String(f["house_a"]) == owner or String(f["house_b"]) == owner:
			bonus += 0.15
	return bonus


# --- rumours -----------------------------------------------------------------------

func rumours() -> Array[String]:
	var out: Array[String] = []
	for f: Dictionary in feuds_list:
		out.append("%s and %s are feuding over %s." % [house_name(f["house_a"]), house_name(f["house_b"]), f["cause"]])
	for al: Array in alliances:
		out.append("%s and %s have married into alliance." % [house_name(al[0]), house_name(al[1])])
	for h: Dictionary in houses:
		if is_struggling(String(h["id"])):
			out.append("%s is said to be short on coin." % h["name"])
	return out


# --- daily politics ------------------------------------------------------------------

func _log(day: int, text: String) -> void:
	if _events_today >= MAX_EVENTS_PER_DAY:
		return
	_events_today += 1
	event_log.append({"day": day, "text": text})
	if event_log.size() > MAX_LOG:
		event_log.pop_front()


func _income_for(house_id: String) -> int:
	var income := 0
	for idx: int in fiefs_of(house_id):
		income += 40 if String(WorldGen.settlements[idx]["kind"]) == "town" else 18
	income += mills_of(house_id).size() * 10
	income += bridges_of(house_id).size() * 6
	if holds_forest(house_id):
		income += 14
	if holds_mine(house_id):
		income += 30
	income += fishing_rights_of(house_id).size() * 6
	for key: String in _toll_owner:
		if String(_toll_owner[key]) == house_id:
			income += 4
	return income


func _pick_holding_name(house_id: String, rng: RandomNumberGenerator) -> String:
	var mills := mills_of(house_id)
	if not mills.is_empty() and rng.randf() < 0.4:
		var site_id: int = mills[rng.randi() % mills.size()]
		for site: Dictionary in WorldGen.sites:
			if int(site["id"]) == site_id:
				return "the mill at %s" % String(site["name"]).replace(" Farm", "")
	var fiefs := fiefs_of(house_id)
	if not fiefs.is_empty():
		return "the lands of %s" % String(WorldGen.settlements[fiefs[rng.randi() % fiefs.size()]]["name"])
	return "their holdings"


func _maybe_feud(rng: RandomNumberGenerator, day: int) -> void:
	if _events_today >= MAX_EVENTS_PER_DAY or houses.size() < 2 or rng.randf() > FEUD_DAILY_CHANCE:
		return
	var a: Dictionary = houses[rng.randi() % houses.size()]
	var b: Dictionary = houses[rng.randi() % houses.size()]
	if String(a["id"]) == String(b["id"]):
		return
	if feud_between(a["id"], b["id"]) or allied(a["id"], b["id"]):
		return
	var causes := ["a border dispute", "an insult at court", "rival claims to grazing rights", "stolen tolls on the road"]
	var cause: String = causes[rng.randi() % causes.size()] if rng.randf() < 0.5 else _pick_holding_name(String(b["id"]), rng)
	feuds_list.append({"house_a": String(a["id"]), "house_b": String(b["id"]), "since_day": day, "cause": cause})
	_log(day, "%s and %s are feuding over %s." % [a["name"], b["name"], cause])


func _maybe_marriage(rng: RandomNumberGenerator, day: int) -> void:
	if _events_today >= MAX_EVENTS_PER_DAY or houses.size() < 2 or rng.randf() > MARRIAGE_DAILY_CHANCE:
		return
	var a: Dictionary = houses[rng.randi() % houses.size()]
	var b: Dictionary = houses[rng.randi() % houses.size()]
	if String(a["id"]) == String(b["id"]) or allied(a["id"], b["id"]):
		return
	alliances.append([String(a["id"]), String(b["id"]), day])
	var kept: Array[Dictionary] = []
	for f: Dictionary in feuds_list:
		var matches: bool = (String(f["house_a"]) == a["id"] and String(f["house_b"]) == b["id"]) or \
			(String(f["house_a"]) == b["id"] and String(f["house_b"]) == a["id"])
		if not matches:
			kept.append(f)
	feuds_list = kept
	influence[a["id"]] = clampf(float(influence.get(a["id"], 30.0)) + 4.0, 0.0, 100.0)
	influence[b["id"]] = clampf(float(influence.get(b["id"], 30.0)) + 4.0, 0.0, 100.0)
	_log(day, "%s and %s have married into alliance." % [a["name"], b["name"]])


func _solvent_house_other_than(house_id: String, rng: RandomNumberGenerator) -> String:
	if rng.randf() < 0.35:
		return CROWN
	var others: Array = houses.filter(func(h: Dictionary) -> bool: return String(h["id"]) != house_id)
	if others.is_empty():
		return CROWN
	return String(others[rng.randi() % others.size()]["id"])


func _maybe_sale(rng: RandomNumberGenerator, day: int) -> void:
	for h: Dictionary in houses:
		if _events_today >= MAX_EVENTS_PER_DAY:
			return
		var hid := String(h["id"])
		if not is_struggling(hid) or rng.randf() > SALE_DAILY_CHANCE:
			continue
		var choices: Array = []
		for idx: int in fiefs_of(hid):
			choices.append(["settlement", idx])
		for site_id: int in mills_of(hid):
			choices.append(["mill", site_id])
		if holds_forest(hid):
			choices.append(["forest", -1])
		if choices.is_empty():
			continue
		var pick: Array = choices[rng.randi() % choices.size()]
		var buyer := _solvent_house_other_than(hid, rng)
		var price := 300 + rng.randi_range(0, 400)
		match String(pick[0]):
			"settlement":
				var idx: int = pick[1]
				_settlement_owner[str(idx)] = buyer
				_log(day, "%s sold %s to %s, struggling to pay its debts." %
					[h["name"], String(WorldGen.settlements[idx]["name"]), house_name(buyer)])
			"mill":
				var site_id: int = pick[1]
				_mill_owner[str(site_id)] = buyer
				_log(day, "%s sold a mill to %s." % [h["name"], house_name(buyer)])
			"forest":
				_forest_owner = buyer
				_log(day, "%s sold its forest holding to %s." % [h["name"], house_name(buyer)])
		wealth[hid] = int(wealth.get(hid, 0)) + price
		wealth[buyer] = maxi(0, int(wealth.get(buyer, 0)) - price)


func _collect_loans(day: int) -> void:
	for loan: Dictionary in loans.duplicate():
		if day < int(loan["due_day"]):
			continue
		var owed := int(loan["owed"])
		var hid := String(loan["house_id"])
		if Game.gold >= owed:
			Game.add_gold(-owed)
			_log(day, "You repay %s's loan (%d gold)." % [house_name(hid), owed])
			loans.erase(loan)
		else:
			change_opinion(hid, -10.0)
			_log(day, "%s is furious: their loan went unpaid." % house_name(hid))
			loans.erase(loan)


## Once a day: house economics, feuds, marriages, struggling sales, loan
## collection and (rarely) a hostile house sending men. Call from life.gd's
## daily tick, e.g. `Life.nobility.daily(WorldSim.day)`.
func daily(day: int) -> Array[String]:
	if day == _last_day:
		return []
	_last_day = day
	_events_today = 0
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed_value * 977 + day * 131 + 17
	for h: Dictionary in houses:
		var hid := String(h["id"])
		wealth[hid] = maxi(0, int(wealth.get(hid, 0)) + _income_for(hid) + rng.randi_range(-40, 60))
		influence[hid] = clampf(float(influence.get(hid, 30.0)) + rng.randf_range(-1.0, 1.2), 0.0, 100.0)
		crown_standing[hid] = clampf(float(crown_standing.get(hid, 0.0)) + rng.randf_range(-0.5, 0.5), -100.0, 100.0)
	_maybe_feud(rng, day)
	_maybe_marriage(rng, day)
	_maybe_sale(rng, day)
	_collect_loans(day)
	for h: Dictionary in houses:
		if is_hostile(String(h["id"])) and rng.randf() < HOSTILE_SEND_MEN_CHANCE:
			_log(day, "%s sends men to collect what they say you owe." % h["name"])
	var out: Array[String] = []
	for e: Dictionary in event_log:
		if int(e["day"]) == day:
			out.append(String(e["text"]))
	return out


# --- save / load -------------------------------------------------------------------------

func serialize() -> Dictionary:
	return {
		"wealth": wealth.duplicate(),
		"influence": influence.duplicate(),
		"crown_standing": crown_standing.duplicate(),
		"settlement_owner": _settlement_owner.duplicate(),
		"mill_owner": _mill_owner.duplicate(),
		"forest_owner": _forest_owner,
		"feuds": feuds_list.duplicate(true),
		"alliances": alliances.duplicate(true),
		"event_log": event_log.duplicate(true),
		"player_standing": player_standing.duplicate(),
		"loans": loans.duplicate(true),
		"last_day": _last_day,
	}


func deserialize(d: Dictionary) -> void:
	if d.has("wealth"):
		wealth.clear()
		for k: String in (d["wealth"] as Dictionary):
			wealth[k] = int(d["wealth"][k])
	if d.has("influence"):
		influence.clear()
		for k: String in (d["influence"] as Dictionary):
			influence[k] = float(d["influence"][k])
	if d.has("crown_standing"):
		crown_standing.clear()
		for k: String in (d["crown_standing"] as Dictionary):
			crown_standing[k] = float(d["crown_standing"][k])
	if d.has("settlement_owner"):
		for k: String in (d["settlement_owner"] as Dictionary):
			_settlement_owner[k] = String(d["settlement_owner"][k])
	if d.has("mill_owner"):
		for k: String in (d["mill_owner"] as Dictionary):
			_mill_owner[k] = String(d["mill_owner"][k])
	_forest_owner = String(d.get("forest_owner", _forest_owner))
	feuds_list.clear()
	for f: Variant in d.get("feuds", []):
		var fd: Dictionary = f
		feuds_list.append({"house_a": String(fd["house_a"]), "house_b": String(fd["house_b"]),
			"since_day": int(fd.get("since_day", 0)), "cause": String(fd.get("cause", ""))})
	alliances.clear()
	for a: Variant in d.get("alliances", []):
		var ad: Array = a
		alliances.append([String(ad[0]), String(ad[1]), int(ad[2])])
	event_log.clear()
	for e: Variant in d.get("event_log", []):
		var ed: Dictionary = e
		event_log.append({"day": int(ed.get("day", 0)), "text": String(ed.get("text", ""))})
	player_standing.clear()
	for k: String in (d.get("player_standing", {}) as Dictionary):
		player_standing[k] = float(d["player_standing"][k])
	loans.clear()
	for l: Variant in d.get("loans", []):
		var ld: Dictionary = l
		loans.append({"house_id": String(ld["house_id"]), "amount": int(ld.get("amount", 0)),
			"owed": int(ld.get("owed", 0)), "due_day": int(ld.get("due_day", 0))})
	_last_day = int(d.get("last_day", _last_day))
