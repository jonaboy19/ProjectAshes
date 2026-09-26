class_name RALifePath
extends RefCounted
## Life from birth: when the player was born, how old they are, their life
## stage, their parents and home, how close they are to their family, and a log
## of what they have done while growing up. Titles (RATitles), archetypes
## (RAArchetypes) and hidden triggers (RAHiddenTriggers) all read from this.
##
## Pure data (serializable). Nothing here touches the scene tree.
##
## Hooking it in (later, from the Life autoload):
##   var life_path := RALifePath.new()
##   # New game, at birth:
##   life_path.begin(WorldSim.day, WorldSim.time_of_day, "Aren", "Hale",
##       [{"id": mother_id, "name": WorldSim.person_name(mother_id), "role": "mother"},
##        {"id": father_id, "name": WorldSim.person_name(father_id), "role": "father"}],
##       0, Vector2(14, 9))
##   # Each in-game hour (WorldSim.hour_changed):
##   life_path.update(WorldSim.day, WorldSim.time_of_day)   # emits birthday / stage_changed
##   # Whenever the player does something meaningful:
##   life_path.record("hunted")          # or record("studied", 0.5), ...
##   # Save/load: include life_path.serialize() in the save dictionary.

signal birthday(age: int)
signal stage_changed(stage: int)
signal recorded(tag: String, total: float)

## In-game calendar. One year of life = this many in-game days. With WorldSim's
## 12-minute days that is ~2.4 real hours per year, so a player can live a
## childhood without it taking weeks. Change freely; everything derives from it.
const DAYS_PER_YEAR := 12
const HOURS_PER_DAY := 24.0

enum Stage { INFANT, CHILD, YOUTH, ADULT }
const STAGE_NAMES := ["Infant", "Child", "Youth", "Adult"]
## Age (whole years) at which each stage begins.
const STAGE_START := [0, 3, 12, 16]

## Bond with a family member, 0 (estranged) .. 100 (devoted).
const BOND_START := 60.0
## Max entries kept in the chronological log (totals are never trimmed).
const LOG_LIMIT := 256

var given_name := ""
var family_name := ""
## Absolute birth time: day number and hour (0..24) in WorldSim's calendar.
var birth_day := 1
var birth_hour := 0.0
## Parents: [{id: int (WorldSim person id, -1 if none), name: String, role: String}]
var parents: Array[Dictionary] = []
## Home: settlement index into WorldGen.settlements and the house's ground position.
var home_settlement := 0
var home_pos := Vector2.ZERO
## Family bonds by member key (parent role or name) -> 0..100.
var bonds: Dictionary = {}
## Action totals: tag -> accumulated weight. This is what archetypes/titles read.
var actions: Dictionary = {}
## Chronological log: [{tag, weight, day}], trimmed to LOG_LIMIT.
var history: Array[Dictionary] = []
## Story flags set by quests, triggers and choices: name -> true (or any value).
var flags: Dictionary = {}

var _last_age := -1
var _last_stage := -1


## Starts a new life. `parent_list` entries: {id, name, role}. Bonds start at BOND_START.
func begin(day: int, hour: float, first: String, family: String, parent_list: Array,
		settlement := 0, house := Vector2.ZERO) -> void:
	birth_day = day
	birth_hour = hour
	given_name = first
	family_name = family
	home_settlement = settlement
	home_pos = house
	parents.clear()
	bonds.clear()
	for p: Dictionary in parent_list:
		var entry := {"id": int(p.get("id", -1)), "name": String(p.get("name", "")),
			"role": String(p.get("role", "parent"))}
		parents.append(entry)
		bonds[_bond_key(entry)] = float(p.get("bond", BOND_START))
	actions.clear()
	history.clear()
	flags.clear()
	_last_age = 0
	_last_stage = Stage.INFANT


func full_name() -> String:
	return ("%s %s" % [given_name, family_name]).strip_edges()


## Moves the birth date so the character is `years` old at `day` (for tests,
## debug, or starting later in life).
func set_age(years: float, day: int, hour := 0.0) -> void:
	var total_hours := years * DAYS_PER_YEAR * HOURS_PER_DAY
	var now := day * HOURS_PER_DAY + hour
	var born := now - total_hours
	birth_day = int(floor(born / HOURS_PER_DAY))
	birth_hour = born - birth_day * HOURS_PER_DAY
	_last_age = age_years(day, hour)
	_last_stage = stage_for(_last_age)


# --- age -----------------------------------------------------------------------

## Age in in-game days (fractional).
func age_days(day: int, hour := 0.0) -> float:
	return maxf(0.0, (day - birth_day) + (hour - birth_hour) / HOURS_PER_DAY)


## Age in whole years.
func age_years(day: int, hour := 0.0) -> int:
	return int(floor(age_days(day, hour) / DAYS_PER_YEAR + 1e-6))


## Age as fractional years (for smooth growth, e.g. character scale).
func age_exact(day: int, hour := 0.0) -> float:
	return age_days(day, hour) / DAYS_PER_YEAR


static func stage_for(years: int) -> int:
	var s := 0
	for i in STAGE_START.size():
		if years >= int(STAGE_START[i]):
			s = i
	return s


func stage(day: int, hour := 0.0) -> int:
	return stage_for(age_years(day, hour))


func stage_name(day: int, hour := 0.0) -> String:
	return STAGE_NAMES[stage(day, hour)]


## Day on which the character turns `years` old.
func day_of_age(years: int) -> int:
	return birth_day + years * DAYS_PER_YEAR


## Call regularly (e.g. every in-game hour). Emits `birthday` for each year
## passed since the last call and `stage_changed` when the stage moves on.
func update(day: int, hour := 0.0) -> void:
	var a := age_years(day, hour)
	if _last_age < 0:
		_last_age = a
		_last_stage = stage_for(a)
		return
	while _last_age < a:
		_last_age += 1
		birthday.emit(_last_age)
	var s := stage_for(a)
	if s != _last_stage:
		_last_stage = s
		stage_changed.emit(s)


# --- family --------------------------------------------------------------------

func _bond_key(p: Dictionary) -> String:
	var role := String(p.get("role", ""))
	return role if role != "" and role != "parent" else String(p.get("name", ""))


func parent(role: String) -> Dictionary:
	for p in parents:
		if p["role"] == role:
			return p
	return {}


func bond(key: String) -> float:
	return float(bonds.get(key, 0.0))


func adjust_bond(key: String, delta: float) -> float:
	var v := clampf(float(bonds.get(key, BOND_START)) + delta, 0.0, 100.0)
	bonds[key] = v
	return v


## Mean bond across the family (0 if none).
func family_bond() -> float:
	if bonds.is_empty():
		return 0.0
	var sum := 0.0
	for k: String in bonds:
		sum += float(bonds[k])
	return sum / bonds.size()


# --- actions -------------------------------------------------------------------

## Records something the character did. Suggested tags (open set):
## hunted, stole, helped_farmer, farmed, trained_sword, trained_fist, meditated,
## explored_forest, explored, studied, traded, healed, gathered_herbs, sneaked,
## guarded, fought, killed_monster, crafted, fished, prayed, performed, helped_parent.
func record(tag: String, weight := 1.0, day := -1) -> float:
	var total := float(actions.get(tag, 0.0)) + weight
	actions[tag] = total
	history.append({"tag": tag, "weight": weight, "day": day})
	while history.size() > LOG_LIMIT:
		history.pop_front()
	recorded.emit(tag, total)
	return total


func count(tag: String) -> float:
	return float(actions.get(tag, 0.0))


func set_flag(flag: String, value: Variant = true) -> void:
	flags[flag] = value


func has_flag(flag: String) -> bool:
	return flags.has(flag) and flags[flag] != null and flags[flag] != false


# --- save ----------------------------------------------------------------------

func serialize() -> Dictionary:
	return {
		"given_name": given_name, "family_name": family_name,
		"birth_day": birth_day, "birth_hour": birth_hour,
		"parents": parents.duplicate(true),
		"home_settlement": home_settlement, "home_pos": [home_pos.x, home_pos.y],
		"bonds": bonds.duplicate(), "actions": actions.duplicate(),
		"log": history.duplicate(true), "flags": flags.duplicate(true),
		"last_age": _last_age, "last_stage": _last_stage,
	}


func deserialize(d: Dictionary) -> void:
	given_name = String(d.get("given_name", given_name))
	family_name = String(d.get("family_name", family_name))
	birth_day = int(d.get("birth_day", birth_day))
	birth_hour = float(d.get("birth_hour", birth_hour))
	parents.clear()
	var ps: Array = d.get("parents", [])
	for p: Dictionary in ps:
		parents.append({"id": int(p.get("id", -1)), "name": String(p.get("name", "")),
			"role": String(p.get("role", "parent"))})
	home_settlement = int(d.get("home_settlement", home_settlement))
	var hp: Array = d.get("home_pos", [home_pos.x, home_pos.y])
	home_pos = Vector2(float(hp[0]), float(hp[1]))
	bonds.clear()
	var b: Dictionary = d.get("bonds", {})
	for k: String in b:
		bonds[k] = float(b[k])
	actions.clear()
	var a: Dictionary = d.get("actions", {})
	for k: String in a:
		actions[k] = float(a[k])
	history.clear()
	var l: Array = d.get("log", [])
	for e: Dictionary in l:
		history.append({"tag": String(e.get("tag", "")), "weight": float(e.get("weight", 1.0)),
			"day": int(e.get("day", -1))})
	var f: Dictionary = d.get("flags", {})
	flags = f.duplicate(true)
	_last_age = int(d.get("last_age", -1))
	_last_stage = int(d.get("last_stage", -1))
