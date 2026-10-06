extends RefCounted
## The notable population: every named NPC the player has met or heard of —
## childhood friends and rivals, career superiors, keepers, noble house
## members, guild adventurers — plus a seeded handful of region residents
## (about 150), each with a real life that keeps moving whether the player is
## watching or not. This is *not* the ~20,000-person WorldSim database; it is
## the small set of people whose names the player might recognise.
##
## Every in-game year (RALifePath.DAYS_PER_YEAR days) each living person rolls
## their life forward: coming of age, enlisting and rising in rank (or
## deserting), apprenticing and mastering a trade, opening a shop or inn,
## marrying, having children, moving towns, turning to crime, becoming
## famous, falling ill, and dying — of age, illness, war or monsters. New
## children are added to the pool, so generations build up over a save.
##
## Pure data (serialisable). No scene tree. May reference the WorldGen static
## class (settlement positions/names) and the Life autoload (RAWorldLore
## names) exactly as other sim scripts (nobility.gd, economy.gd) already do,
## but every dependency that matters for a test (careers, nobility) is also
## accepted as an explicit argument so tests never need the full game booted.
##
## Usage (Life autoload, once — see the hook lines given in the task report):
##   var life_courses := preload("res://scripts/sim/life_courses.gd").new()
##   life_courses.seed_from(WorldSim.SEED)
##   life_courses.populate_region(150, WorldSim.day)
##   careers.vacancy_opened.connect(life_courses.on_vacancy)
##   # once per day (Life._on_hour, hour == 6):
##   for msg in life_courses.tick_day(WorldSim.day, {"at_war": ..., "frontier_threat": ...}):
##       Game.say(msg)
##   # save/load: life_courses.serialize() / deserialize(d)

const RALifePath := preload("res://scripts/sim/life_path.gd")

const TRAITS := ["ambitious", "kind", "reckless", "pious", "greedy", "brave"]
const TRADES := ["blacksmith", "weaver", "cooper", "tanner", "baker", "carpenter", "fisher", "potter"]
const JOBS_POOL := ["farmer", "laborer", "blacksmith", "merchant", "guard", "woodcutter", "hunter", "healer", "innkeeper", "trader"]
const MILITARY_RANKS := ["recruit", "soldier", "sergeant", "captain", "commander"]
const BUSINESS_OCCUPATIONS := ["shopkeeper", "innkeeper"]
const CAUSE_TEXT := {
	"old_age": "of old age", "illness": "of illness", "war": "in the war",
	"monsters": "to monsters", "bandits": "to bandits",
}
## Two settlements count as "nearby" for marriage within this world distance.
const NEARBY_DIST := 900.0
## Career-seat holders life_courses supplies are negative ids far below any
## real WorldSim index or the player's PLAYER (-1), so they never collide.
const CAREERS_ID_BASE := -1000000
const MAX_NEWS := 400
const MAX_EVENTS_PER_PERSON := 24
## The people table is a rolling window: once it holds more than MAX_PEOPLE rows, the longest-dead residents
## nobody has met (and who aren't famous) are forgotten first. It used to keep every birth and death forever
## (150 -> 780 rows, +350 KB of save in two simulated years). Living people, the met and the famous stay.
const MAX_PEOPLE := 320

## id (int) -> {id, name, birth_day, sex, settlement, culture, occupation,
##   rank, trade, traits: Array[String], spouse (-1 none), children: Array[int],
##   parents: Array[int], alive, cause_of_death, death_day, famous, met,
##   source, career_org, career_seat, events: [{day, text}], _last_age}
var people: Dictionary = {}
## Chronological world news: [{day, text, people: Array[int]}], trimmed FIFO.
var _news: Array = []
var _next_id := 1
var _rng := RandomNumberGenerator.new()


func seed_from(world_seed: int) -> void:
	_rng.seed = hash([world_seed, "life_courses"])


# --- creation --------------------------------------------------------------------

func _new_id() -> int:
	var id := _next_id
	_next_id += 1
	return id


func _random_traits() -> Array[String]:
	var pool := TRAITS.duplicate()
	for i in range(pool.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp: String = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	var out: Array[String] = []
	for i in _rng.randi_range(1, 3):
		out.append(pool[i])
	return out


func _inherit_traits(mother: Dictionary, father: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for t: String in (mother.get("traits", []) as Array):
		if out.size() < 3 and _rng.randf() < 0.35 and not out.has(t):
			out.append(t)
	for t: String in (father.get("traits", []) as Array):
		if out.size() < 3 and _rng.randf() < 0.35 and not out.has(t):
			out.append(t)
	if out.is_empty():
		out = _random_traits()
	return out


func _random_name(culture: String, sex: String) -> String:
	var n := ""
	var lore: Object = Life.get("lore") if Life != null else null
	if lore != null:
		n = String(lore.random_name(culture, _rng, sex))
	if n == "":
		n = "%s %s" % [["Aldric", "Edda", "Osric", "Wynn", "Bertram", "Maud"][_rng.randi() % 6],
			["Smith", "Cooper", "Fletcher", "Thatcher", "Miller", "Ward"][_rng.randi() % 6]]
	return n


func _new_person(name: String, birth_day: int, sex: String, settlement: int, culture: String,
		occupation: String, source: String, parents: Array[int] = []) -> int:
	var id := _new_id()
	people[id] = {
		"id": id, "name": name, "birth_day": birth_day, "sex": sex, "settlement": settlement,
		"culture": culture, "occupation": occupation, "rank": "", "trade": "",
		"traits": _random_traits(), "spouse": -1, "children": [] as Array[int],
		"parents": parents.duplicate(), "alive": true, "cause_of_death": "", "death_day": -1,
		"famous": false, "met": false, "source": source, "career_org": "", "career_seat": "",
		"events": [], "_last_age": -1,
	}
	return id


## Seeds `count` region residents around the settlements the player might
## someday hear of. `origin_day` is WorldSim.day at the time of seeding, so
## their ages are relative to "now".
func populate_region(count := 150, origin_day := 0) -> void:
	var n_settlements := maxi(1, WorldGen.settlements.size())
	for _i in count:
		var settlement := _rng.randi_range(0, n_settlements - 1)
		var sex := "male" if _rng.randf() < 0.5 else "female"
		var age := _rng.randi_range(16, 70)
		var culture := "caldric"
		var name := _random_name(culture, sex)
		var birth_day := origin_day - age * RALifePath.DAYS_PER_YEAR - _rng.randi_range(0, RALifePath.DAYS_PER_YEAR - 1)
		var occupation := String(JOBS_POOL[_rng.randi() % JOBS_POOL.size()])
		var id := _new_person(name, birth_day, sex, settlement, culture, occupation, "seeded")
		people[id]["_last_age"] = age


## Registers a childhood friend or rival (childhood_events.gd), the same age
## as the player, so they grow up alongside the player and can reappear as
## adults. `relation`: "childhood_friend" or "childhood_rival". `name` may be
## "" to have one generated (childhood_events.gd doesn't need to invent names
## itself); returns the same id if called again for an already-named peer.
func register_childhood_peer(name: String, relation: String, settlement: int, culture: String,
		birth_day: int, sex := "") -> int:
	if name != "":
		var existing := find_by_name(name)
		if not existing.is_empty():
			return int(existing["id"])
	var s := sex if sex in ["male", "female"] else ("male" if _rng.randf() < 0.5 else "female")
	var nm := name if name != "" else _random_name(culture, s)
	var id := _new_person(nm, birth_day, s, settlement, culture, "child", relation)
	people[id]["met"] = true
	return id


## Registers someone the player meets in play (a superior, a guild member...)
## if not already known. Returns the existing or new id.
func ensure_person(name: String, role: String, settlement: int, sex := "", culture := "caldric") -> int:
	var existing := find_by_name(name)
	if not existing.is_empty():
		return int(existing["id"])
	var s := sex if sex in ["male", "female"] else ("male" if _rng.randf() < 0.5 else "female")
	var age := _rng.randi_range(18, 55)
	var birth_day := -age * RALifePath.DAYS_PER_YEAR
	var id := _new_person(name, birth_day, s, settlement, culture, role, "met")
	people[id]["met"] = true
	return id


func on_player_met(id: int) -> void:
	if people.has(id):
		people[id]["met"] = true


## Changes what a peer is on record as (e.g. a rival who was befriended).
func update_peer_relation(id: int, relation: String) -> void:
	if people.has(id):
		people[id]["source"] = relation


# --- reads -------------------------------------------------------------------

func person(id: int) -> Dictionary:
	return people.get(id, {})


func find_by_name(name: String) -> Dictionary:
	for id: int in people:
		if String(people[id]["name"]) == name:
			return people[id]
	return {}


func age_years(id: int, day: int) -> int:
	if not people.has(id):
		return 0
	return _age_years(people[id], day)


func _age_years(p: Dictionary, day: int) -> int:
	return maxi(0, int(floor(float(day - int(p["birth_day"])) / RALifePath.DAYS_PER_YEAR)))


## Everyone the player has met or heard of, alive or dead.
func known_people() -> Array[int]:
	var out: Array[int] = []
	for id: int in people:
		if bool(people[id]["met"]):
			out.append(id)
	return out


## {person, parents: [Dictionary], spouse: Dictionary, children: [Dictionary]}
func family_tree(id: int) -> Dictionary:
	if not people.has(id):
		return {}
	var p: Dictionary = people[id]
	var parents: Array = []
	for pid: int in (p["parents"] as Array):
		if people.has(pid):
			parents.append(people[pid])
	var children: Array = []
	for cid: int in (p["children"] as Array):
		if people.has(cid):
			children.append(people[cid])
	var spouse := {}
	if int(p["spouse"]) >= 0 and people.has(int(p["spouse"])):
		spouse = people[int(p["spouse"])]
	return {"person": p, "parents": parents, "spouse": spouse, "children": children}


func _settlement_name(idx: int) -> String:
	if idx >= 0 and idx < WorldGen.settlements.size():
		return WorldGen.display_name(String(WorldGen.settlements[idx]["name"]))
	return "the village"


func _settlement_near(a: int, b: int) -> bool:
	if a == b:
		return true
	if a >= 0 and a < WorldGen.settlements.size() and b >= 0 and b < WorldGen.settlements.size():
		var pa: Vector2 = WorldGen.settlements[a]["pos"]
		var pb: Vector2 = WorldGen.settlements[b]["pos"]
		return pa.distance_to(pb) <= NEARBY_DIST
	return false


func _trait(p: Dictionary, name: String) -> bool:
	return (p["traits"] as Array).has(name)


# --- news / rumours -----------------------------------------------------------

func _event(p: Dictionary, day: int, text: String, extra_people: Array[int] = []) -> void:
	var events: Array = p["events"]
	events.append({"day": day, "text": text})
	while events.size() > MAX_EVENTS_PER_PERSON:
		events.pop_front()
	var involved: Array[int] = [int(p["id"])]
	for e: int in extra_people:
		involved.append(e)
	_news.append({"day": day, "text": text, "people": involved})
	while _news.size() > MAX_NEWS:
		_news.pop_front()


func _news_add(day: int, text: String, involved: Array[int]) -> void:
	_news.append({"day": day, "text": text, "people": involved})
	while _news.size() > MAX_NEWS:
		_news.pop_front()


## Notable events about people the player knows, since `day` (exclusive),
## oldest first — e.g. "Tomas Reed, whom you knew as a boy, was made captain
## at Greywatch."
func news_since(day: int) -> Array[String]:
	var out: Array[String] = []
	for n: Dictionary in _news:
		if int(n["day"]) <= day:
			continue
		var known := false
		for pid: int in (n["people"] as Array):
			if people.has(pid) and bool(people[pid]["met"]):
				known = true
				break
		if known:
			out.append(String(n["text"]))
	return out


## Village gossip drawn from the wider notable population, regardless of
## whether the player has met them — for village_services._pick_rumour.
func rumours(limit := 8) -> Array[String]:
	var out: Array[String] = []
	var i := _news.size() - 1
	while i >= 0 and out.size() < limit:
		out.append(String(_news[i]["text"]))
		i -= 1
	return out


# --- careers integration -------------------------------------------------------

static func careers_holder_id(pid: int) -> int:
	return CAREERS_ID_BASE - pid


static func careers_person_id(holder: int) -> int:
	return CAREERS_ID_BASE - holder


func assign_to_seat(pid: int, careers: Object, org_id: String, title: String) -> bool:
	if careers == null or not people.has(pid):
		return false
	var ok: bool = careers.fill_vacancy_with(org_id, title, careers_holder_id(pid))
	if ok:
		people[pid]["career_org"] = org_id
		people[pid]["career_seat"] = title
	return ok


func _vacate_career_seat(pid: int, careers: Object) -> void:
	if careers == null or not people.has(pid):
		return
	var p: Dictionary = people[pid]
	if String(p["career_org"]) != "":
		if careers.has_method("remove_person"):
			careers.remove_person(careers_holder_id(pid))
		p["career_org"] = ""
		p["career_seat"] = ""


## A seat opened up (careers.vacancy_opened). Finds or creates a suitable
## notable NPC from this settlement and seats them, so the post is never
## empty for long. Connect from Life:
##   careers.vacancy_opened.connect(life_courses.on_vacancy)
func on_vacancy(org: Dictionary, seat: Dictionary, careers: Object = null) -> void:
	if careers == null:
		careers = Life.get("careers") if Life != null else null
	if careers == null:
		return
	var settlement := int(org.get("settlement", 0))
	var candidate := _find_or_create_worker(settlement, String(seat.get("title", "worker")))
	assign_to_seat(candidate, careers, String(org["id"]), String(seat["title"]))


func _find_or_create_worker(settlement: int, _title: String) -> int:
	for id: int in people:
		var p: Dictionary = people[id]
		if bool(p["alive"]) and int(p["settlement"]) == settlement \
			and String(p["career_org"]) == "" and _age_years(p, WorldSim.day) >= 16:
			return id
	var culture := "caldric"
	var sex := "male" if _rng.randf() < 0.5 else "female"
	var name := _random_name(culture, sex)
	var age := _rng.randi_range(18, 40)
	var birth_day := WorldSim.day - age * RALifePath.DAYS_PER_YEAR
	var id := _new_person(name, birth_day, sex, settlement, culture, "laborer", "career")
	return id


# --- marriage / children -------------------------------------------------------

## Old saves or externally constructed rows may have a missing or malformed
## parent array. Only actual nonnegative integer entries represent kinship IDs.
func _valid_parent_ids(person: Dictionary) -> Array[int]:
	var raw_parents: Variant = person.get("parents", [])
	var valid: Array[int] = []
	if not raw_parents is Array:
		return valid
	for parent_id: Variant in raw_parents:
		if parent_id is int and int(parent_id) >= 0:
			valid.append(int(parent_id))
	return valid


## Pairs `pid` with an eligible unmarried adult in the same or a nearby
## settlement. Returns the spouse id, or -1 if nobody eligible was found.
func try_marry(pid: int, day: int) -> int:
	if not people.has(pid):
		return -1
	var p: Dictionary = people[pid]
	if not bool(p.get("alive", false)) or int(p.get("spouse", -1)) >= 0 \
		or _age_years(p, day) < 16:
		return -1
	var p_parents := _valid_parent_ids(p)
	var candidates: Array[int] = []
	for oid: int in people:
		if oid == pid:
			continue
		var o: Dictionary = people[oid]
		if not bool(o.get("alive", false)) or int(o.get("spouse", -1)) >= 0:
			continue
		if String(o["sex"]) == String(p["sex"]):
			continue
		if _age_years(o, day) < 16:
			continue
		var o_parents := _valid_parent_ids(o)
		if p_parents.has(oid) or o_parents.has(pid):
			continue
		var shares_parent := false
		for parent_id: int in p_parents:
			if o_parents.has(parent_id):
				shares_parent = true
				break
		if shares_parent:
			continue
		if not _settlement_near(int(o["settlement"]), int(p["settlement"])):
			continue
		candidates.append(oid)
	if candidates.is_empty():
		return -1
	var chosen: int = candidates[_rng.randi() % candidates.size()]
	p["spouse"] = chosen
	people[chosen]["spouse"] = pid
	_event(p, day, "%s married %s." % [p["name"], people[chosen]["name"]], [chosen])
	return chosen


## A child is born to `mother_id` and her spouse. Returns the new id, or -1.
func have_child(mother_id: int, day: int) -> int:
	if not people.has(mother_id):
		return -1
	var mother: Dictionary = people[mother_id]
	var father_id := int(mother["spouse"])
	if father_id < 0 or not people.has(father_id):
		return -1
	var father: Dictionary = people[father_id]
	var sex := "male" if _rng.randf() < 0.5 else "female"
	var culture := String(mother["culture"])
	var name := _random_name(culture, sex)
	var id := _new_person(name, day, sex, int(mother["settlement"]), culture, "child", "born",
		[mother_id, father_id])
	people[id]["traits"] = _inherit_traits(mother, father)
	(mother["children"] as Array).append(id)
	(father["children"] as Array).append(id)
	_event(mother, day, "%s and %s had a child, %s, in %s." %
		[mother["name"], father["name"], name, _settlement_name(int(mother["settlement"]))], [father_id, id])
	return id


# --- yearly life course --------------------------------------------------------

func _next_military_rank(rank: String) -> String:
	var i := MILITARY_RANKS.find(rank)
	if i == -1:
		return "soldier"
	return MILITARY_RANKS[mini(i + 1, MILITARY_RANKS.size() - 1)]


func _military_year(p: Dictionary, pid: int, day: int, ctx: Dictionary, careers: Object) -> void:
	var at_war := bool(ctx.get("at_war", false))
	if _trait(p, "reckless") and _rng.randf() < (0.06 if at_war else 0.03):
		p["occupation"] = "laborer"
		p["rank"] = ""
		_event(p, day, "%s deserted." % p["name"])
		_vacate_career_seat(pid, careers)
		return
	var promote_chance := 0.08 + (0.05 if _trait(p, "ambitious") else 0.0) + \
		(0.03 if _trait(p, "brave") else 0.0) + (0.05 if at_war else 0.0)
	if _rng.randf() < promote_chance:
		var next_rank := _next_military_rank(String(p["rank"]))
		if next_rank != String(p["rank"]):
			p["rank"] = next_rank
			if next_rank in ["captain", "commander"]:
				p["occupation"] = "officer"
			_event(p, day, "%s was made %s at %s." %
				[p["name"], next_rank.capitalize(), _settlement_name(int(p["settlement"]))])
	if String(p["rank"]) == "captain" and _trait(p, "ambitious") and _rng.randf() < 0.02:
		p["rank"] = "commander"
		p["occupation"] = "officer"
		p["famous"] = true
		_event(p, day, "%s was made a commander, and word of it travelled far." % p["name"])


func _civilian_year(p: Dictionary, pid: int, day: int, ctx: Dictionary, careers: Object) -> void:
	var occ := String(p["occupation"])
	if occ == "apprentice":
		if int(p["birth_day"]) >= 0 and _rng.randf() < 0.05 + (0.05 if _trait(p, "brave") else 0.0) + (0.03 if _trait(p, "ambitious") else 0.0):
			p["occupation"] = "soldier"
			p["rank"] = "recruit"
			_event(p, day, "%s enlisted as a recruit." % p["name"])
			return
		if _rng.randf() < 0.12 + (0.05 if _trait(p, "ambitious") else 0.0):
			var trade := String(p["trade"])
			if trade == "":
				trade = TRADES[_rng.randi() % TRADES.size()]
				p["trade"] = trade
			p["occupation"] = "master %s" % trade
			_event(p, day, "%s became a master %s." % [p["name"], trade])
		return
	if occ.begins_with("master "):
		if _rng.randf() < 0.10 + (0.05 if _trait(p, "ambitious") else 0.0):
			var as_inn := _rng.randf() < 0.3
			p["occupation"] = "innkeeper" if as_inn else "shopkeeper"
			_event(p, day, "%s opened %s in %s." % [p["name"], "an inn" if as_inn else "a shop",
				_settlement_name(int(p["settlement"]))])
		return
	if occ in ["laborer", "farmer", "woodcutter", "unemployed"] and (_trait(p, "greedy") or _trait(p, "reckless")):
		if _rng.randf() < 0.05:
			var as_bandit := _rng.randf() < 0.4
			p["occupation"] = "bandit" if as_bandit else "criminal"
			_event(p, day, "%s turned to %s." % [p["name"], "banditry" if as_bandit else "crime"])
			return
	if occ == "adventurer" and _trait(p, "ambitious") and _trait(p, "brave") and _rng.randf() < 0.015:
		p["occupation"] = "adventurer"
		p["rank"] = "S-rank"
		p["famous"] = true
		_event(p, day, "%s was raised to S-rank at the Adventurer Guild." % p["name"])


func _yearly_choices(p: Dictionary, pid: int, day: int, age: int, ctx: Dictionary, careers: Object) -> void:
	if age < 16:
		return
	if age == 16 and String(p["occupation"]) == "child":
		p["occupation"] = "apprentice"
		_event(p, day, "%s came of age." % p["name"])
		return
	if String(p["occupation"]) in ["soldier", "officer"]:
		_military_year(p, pid, day, ctx, careers)
	else:
		_civilian_year(p, pid, day, ctx, careers)
	if int(p["spouse"]) < 0 and _rng.randf() < 0.18:
		try_marry(pid, day)
	elif String(p["sex"]) == "female" and age <= 45 and int(p["spouse"]) >= 0 and _rng.randf() < 0.22:
		have_child(pid, day)
	if _rng.randf() < 0.02 and WorldGen.settlements.size() > 1:
		var to := _rng.randi_range(0, WorldGen.settlements.size() - 1)
		if to != int(p["settlement"]):
			p["settlement"] = to
			_event(p, day, "%s moved to %s." % [p["name"], _settlement_name(to)])


func _roll_death(p: Dictionary, pid: int, day: int, age: int, ctx: Dictionary, careers: Object, nobility: Object) -> void:
	var causes := {}
	if age >= 60:
		causes["old_age"] = clampf(float(age - 60) / 20.0, 0.0, 1.0) * 0.55
	if age >= 85:
		causes["old_age"] = 0.9
	causes["illness"] = 0.01 + float(age) / 100.0 * 0.02
	var occ := String(p["occupation"])
	var at_war := bool(ctx.get("at_war", false))
	if at_war and occ in ["soldier", "officer"]:
		causes["war"] = 0.05 + (0.03 if String(p["rank"]) == "recruit" else 0.0) + (0.02 if _trait(p, "reckless") else 0.0)
	var threat := clampf(float(ctx.get("frontier_threat", 0.0)) / 100.0, 0.0, 1.0)
	if threat > 0.0 and occ in ["hunter", "guard", "adventurer", "bandit", "laborer", "woodcutter"]:
		causes["monsters"] = threat * 0.04
	if occ in ["bandit", "criminal"]:
		causes["bandits"] = 0.05
	var total := 0.0
	for c: String in causes:
		total += float(causes[c])
	total = clampf(total, 0.0, 0.97)
	if total <= 0.0 or _rng.randf() >= total:
		return
	var r := _rng.randf() * total
	var acc := 0.0
	var chosen := "illness"
	for c: String in causes:
		acc += float(causes[c])
		if r <= acc:
			chosen = c
			break
	kill(pid, day, chosen, ctx, careers, nobility)


func _transfer_business(p: Dictionary, day: int) -> void:
	var occ := String(p["occupation"])
	if not (occ in BUSINESS_OCCUPATIONS or occ.begins_with("master ")):
		return
	var heir_id := -1
	for cid: int in (p["children"] as Array):
		if people.has(cid) and bool(people[cid]["alive"]) and _age_years(people[cid], day) >= 16:
			heir_id = cid
			break
	if heir_id == -1 and int(p["spouse"]) >= 0 and people.has(int(p["spouse"])) and bool(people[int(p["spouse"])]["alive"]):
		heir_id = int(p["spouse"])
	if heir_id != -1:
		var heir: Dictionary = people[heir_id]
		heir["occupation"] = occ
		_event(heir, day, "%s took over %s's business in %s." %
			[heir["name"], p["name"], _settlement_name(int(p["settlement"]))], [int(p["id"])])
	else:
		_news_add(day, "%s's business in %s stands empty, its owner gone." %
			[p["name"], _settlement_name(int(p["settlement"]))], [int(p["id"])])


## Kills `pid` for `cause` ("old_age", "illness", "war", "monsters",
## "bandits", or any custom string). Opens their career seat, hands their
## business to an heir, and — for a noble house member — calls
## nobility.on_member_died(name) if that hook exists.
func kill(pid: int, day: int, cause: String, ctx: Dictionary = {}, careers: Object = null, nobility: Object = null) -> void:
	if not people.has(pid):
		return
	var p: Dictionary = people[pid]
	if not bool(p["alive"]):
		return
	p["alive"] = false
	p["death_day"] = day
	p["cause_of_death"] = cause
	var phrase: String = String(CAUSE_TEXT.get(cause, cause))
	_event(p, day, "%s died %s." % [p["name"], phrase])
	_transfer_business(p, day)
	if careers == null:
		careers = Life.get("careers") if Life != null else null
	_vacate_career_seat(pid, careers)
	if nobility == null:
		nobility = Life.get("nobility") if Life != null else null
	if nobility != null and nobility.has_method("on_member_died"):
		nobility.on_member_died(String(p["name"]))
	if int(p["spouse"]) >= 0 and people.has(int(p["spouse"])):
		people[int(p["spouse"])]["spouse"] = -1


## Advances everyone whose age-in-years has increased since the last call,
## running their life course for each year crossed. Call once per in-game
## day (Life._on_hour, hour == 6). Returns lines worth telling the player
## about (famous deaths and promotions); the full record is in news_since().
## `ctx`: {at_war: bool, frontier_threat: float (0..100), careers, nobility}.
func tick_day(day: int, ctx: Dictionary = {}) -> Array[String]:
	var careers: Object = ctx.get("careers", null)
	if careers == null:
		careers = Life.get("careers") if Life != null else null
	var nobility: Object = ctx.get("nobility", null)
	if nobility == null:
		nobility = Life.get("nobility") if Life != null else null
	var out: Array[String] = []
	var before_news := _news.size()
	for pid: int in people.keys().duplicate():
		var p: Dictionary = people[pid]
		if not bool(p["alive"]):
			continue
		var age_now := _age_years(p, day)
		if int(p["_last_age"]) < 0:
			p["_last_age"] = age_now
			continue
		while int(p["_last_age"]) < age_now and bool(p["alive"]):
			p["_last_age"] = int(p["_last_age"]) + 1
			_yearly_choices(p, pid, day, int(p["_last_age"]), ctx, careers)
			if bool(p["alive"]):
				_roll_death(p, pid, day, int(p["_last_age"]), ctx, careers, nobility)
	for i in range(before_news, _news.size()):
		var n: Dictionary = _news[i]
		if bool(people.get(int((n["people"] as Array)[0]), {}).get("famous", false)):
			out.append(String(n["text"]))
	_forget_the_dead(day)
	return out


## Trims the table back to MAX_PEOPLE, oldest unmet non-famous dead first. Every lookup here is
## people.has()-guarded, so dangling parent/child/spouse ids are harmless.
func _forget_the_dead(_day: int) -> void:
	if people.size() <= MAX_PEOPLE:
		return
	var dead: Array = []
	for pid: int in people:
		var p: Dictionary = people[pid]
		if not bool(p["alive"]) and not bool(p["met"]) and not bool(p["famous"]):
			dead.append([int(p["death_day"]), pid])
	dead.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) < int(b[0]))
	var over := people.size() - MAX_PEOPLE
	for i in mini(over, dead.size()):
		people.erase(int(dead[i][1]))


# --- save ----------------------------------------------------------------------

func serialize() -> Dictionary:
	var ppl := {}
	for id: int in people:
		ppl[str(id)] = people[id].duplicate(true)
	return {"people": ppl, "next_id": _next_id, "news": _news.duplicate(true), "rng": str(_rng.state)}


func deserialize(d: Dictionary) -> void:
	people.clear()
	var ppl: Dictionary = d.get("people", {})
	for k: String in ppl:
		var p: Dictionary = ppl[k]
		var traits: Array[String] = []
		for t: Variant in p.get("traits", []):
			traits.append(String(t))
		var children: Array[int] = []
		for c: Variant in p.get("children", []):
			children.append(int(c))
		var parents: Array[int] = []
		for pa: Variant in p.get("parents", []):
			parents.append(int(pa))
		var events: Array = []
		for e: Dictionary in p.get("events", []):
			events.append({"day": int(e.get("day", 0)), "text": String(e.get("text", ""))})
		people[int(k)] = {
			"id": int(k), "name": String(p.get("name", "")), "birth_day": int(p.get("birth_day", 0)),
			"sex": String(p.get("sex", "male")), "settlement": int(p.get("settlement", 0)),
			"culture": String(p.get("culture", "caldric")), "occupation": String(p.get("occupation", "")),
			"rank": String(p.get("rank", "")), "trade": String(p.get("trade", "")), "traits": traits,
			"spouse": int(p.get("spouse", -1)), "children": children, "parents": parents,
			"alive": bool(p.get("alive", true)), "cause_of_death": String(p.get("cause_of_death", "")),
			"death_day": int(p.get("death_day", -1)), "famous": bool(p.get("famous", false)),
			"met": bool(p.get("met", false)), "source": String(p.get("source", "")),
			"career_org": String(p.get("career_org", "")), "career_seat": String(p.get("career_seat", "")),
			"events": events, "_last_age": int(p.get("_last_age", -1)),
		}
	_next_id = int(d.get("next_id", 1))
	_news.clear()
	for n: Dictionary in d.get("news", []):
		var involved: Array[int] = []
		for pid: Variant in n.get("people", []):
			involved.append(int(pid))
		_news.append({"day": int(n.get("day", 0)), "text": String(n.get("text", "")), "people": involved})
	if d.has("rng"):
		_rng.state = String(d["rng"]).to_int()
