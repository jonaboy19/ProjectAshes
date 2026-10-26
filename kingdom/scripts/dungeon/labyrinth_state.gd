extends RefCounted
## Progress through one labyrinth: which floors are unlocked and what was cleared on each. A layout is never saved, only
## the labyrinth id + world seed + these flags (the generator rebuilds the floor from the seed). JSON-safe, no nodes.
##
## Floor numbers are 1-based here (floor 1 is index 0). Rules (Aincrad style):
##  - floor 1 is open; killing a floor's boss unlocks the next floor (and the stairs down on this one);
##  - the big boss door opens once the mid-boss is dead;
##  - touching the warp stone in a floor's safe room unlocks warping to that floor's safe room from any safe room;
##  - chests, traps, secret doors and monsters are tracked by their generator ids (f<n>_ch3, f<n>_t2, ...), so a reload
##    shows the same world; monsters come back after REPOPULATE_DAYS unless they are bosses.

const Data := preload("res://scripts/dungeon/labyrinth_data.gd")
const Gen := preload("res://scripts/dungeon/labyrinth_gen.gd")

const SAVE_VERSION := 1
const REPOPULATE_DAYS := 14

var labyrinth_id: String = Data.DEFAULT_ID
var world_seed: int = 0
var floors_unlocked: int = 1                # highest floor the player may enter
var deepest: int = 0                        # deepest floor ever entered
var _floors: Dictionary = {}                # floor number -> flag dictionary (see _floor)


func _init(id := Data.DEFAULT_ID, seed_value := 0) -> void:
	labyrinth_id = id
	world_seed = seed_value


func floor_count() -> int:
	return int(Data.DEFS[labyrinth_id]["floors"])


## Layout of floor `number` (1-based), rebuilt from the seed.
func layout(number: int) -> Dictionary:
	return Gen.generate_floor(labyrinth_id, world_seed, number - 1)


# --- progression ---------------------------------------------------------------------------------

func is_floor_unlocked(number: int) -> bool:
	return number >= 1 and number <= floor_count() and number <= floors_unlocked


## Enter floor `number` via the stairs; false when it is still locked.
func enter_floor(number: int, day := 0) -> bool:
	if not is_floor_unlocked(number):
		return false
	deepest = maxi(deepest, number)
	var fl := _floor(number)
	if not fl.has("entered_day"):
		fl["entered_day"] = day
	return true


func kill_midboss(number: int) -> void:
	_floor(number)["midboss"] = true


func midboss_dead(number: int) -> bool:
	return bool(_floor(number).get("midboss", false))


func can_open_boss_door(number: int) -> bool:
	return midboss_dead(number)


## The boss died: the stairs down open and the next floor unlocks. Returns the newly unlocked floor number, or 0.
func kill_boss(number: int) -> int:
	_floor(number)["boss"] = true
	var nxt := number + 1
	if nxt <= floor_count() and nxt > floors_unlocked:
		floors_unlocked = nxt
		return nxt
	return 0


func boss_dead(number: int) -> bool:
	return bool(_floor(number).get("boss", false))


func stairs_down_open(number: int) -> bool:
	return boss_dead(number)


func labyrinth_cleared() -> bool:
	return boss_dead(floor_count())


func touch_warp_stone(number: int) -> void:
	_floor(number)["warp"] = true


func can_warp_to(number: int) -> bool:
	return bool(_floor(number).get("warp", false)) and is_floor_unlocked(number)


## Floors the player can warp to from a safe room.
func warp_targets() -> Array:
	var out: Array = []
	for n in range(1, floor_count() + 1):
		if can_warp_to(n):
			out.append(n)
	return out


# --- per-floor world flags -----------------------------------------------------------------------

func open_chest(number: int, id: String) -> void:
	_set_add(number, "chests", id)


func chest_open(number: int, id: String) -> bool:
	return _set_has(number, "chests", id)


func disarm_trap(number: int, id: String) -> void:
	_set_add(number, "traps", id)


func trap_disarmed(number: int, id: String) -> bool:
	return _set_has(number, "traps", id)


func find_secret(number: int, edge_id: int) -> void:
	_set_add(number, "secrets", str(edge_id))


func secret_found(number: int, edge_id: int) -> bool:
	return _set_has(number, "secrets", str(edge_id))


func kill_creature(number: int, id: String, day := 0) -> void:
	var kills: Dictionary = _floor(number)["kills"]
	kills[id] = day


## True while a monster is dead: bosses stay dead, the rest come back REPOPULATE_DAYS later.
func creature_dead(number: int, id: String, today := 0) -> bool:
	var kills: Dictionary = _floor(number)["kills"]
	if not kills.has(id):
		return false
	if id.ends_with("boss") or id.ends_with("midboss"):
		return true
	return today - int(kills[id]) < REPOPULATE_DAYS


## Gate flags for labyrinth_gen.reachable(): which gated doors the player has opened on this floor.
func open_gates(number: int, lay: Dictionary) -> Dictionary:
	var secrets := false
	for e: Dictionary in lay["edges"]:
		if e["kind"] == "secret" and secret_found(number, e["id"]):
			secrets = true
	return {"secret": secrets, "boss_door": can_open_boss_door(number)}


# --- save / load ---------------------------------------------------------------------------------

func serialize() -> Dictionary:
	var fl := {}
	for n: int in _floors:
		var src: Dictionary = _floors[n]
		fl[str(n)] = {"entered_day": src.get("entered_day", 0), "midboss": src["midboss"], "boss": src["boss"], "warp": src["warp"],
			"chests": (src["chests"] as Dictionary).keys(), "traps": (src["traps"] as Dictionary).keys(),
			"secrets": (src["secrets"] as Dictionary).keys(), "kills": src["kills"].duplicate()}
	return {"version": SAVE_VERSION, "id": labyrinth_id, "seed": world_seed, "unlocked": floors_unlocked, "deepest": deepest, "floors": fl}


func deserialize(d: Dictionary) -> void:
	if int(d.get("version", 0)) != SAVE_VERSION or not Data.DEFS.has(String(d.get("id", ""))):
		return
	labyrinth_id = String(d["id"])
	world_seed = int(d["seed"])
	floors_unlocked = clampi(int(d.get("unlocked", 1)), 1, floor_count())
	deepest = int(d.get("deepest", 0))
	_floors.clear()
	var fl: Dictionary = d.get("floors", {})
	for k: String in fl:
		var src: Dictionary = fl[k]
		var f := _floor(int(k))
		f["entered_day"] = int(src.get("entered_day", 0))
		f["midboss"] = bool(src.get("midboss", false))
		f["boss"] = bool(src.get("boss", false))
		f["warp"] = bool(src.get("warp", false))
		for key in ["chests", "traps", "secrets"]:
			for id in src.get(key, []):
				(f[key] as Dictionary)[str(id)] = true
		var kills: Dictionary = src.get("kills", {})
		for id: String in kills:
			(f["kills"] as Dictionary)[id] = int(kills[id])


static func from_dict(d: Dictionary) -> RefCounted:
	var s: RefCounted = load("res://scripts/dungeon/labyrinth_state.gd").new(String(d.get("id", Data.DEFAULT_ID)), int(d.get("seed", 0)))
	s.deserialize(d)
	return s


# --- internals -----------------------------------------------------------------------------------

func _floor(number: int) -> Dictionary:
	if not _floors.has(number):
		_floors[number] = {"midboss": false, "boss": false, "warp": false, "chests": {}, "traps": {}, "secrets": {}, "kills": {}}
	return _floors[number]


func _set_add(number: int, key: String, id: String) -> void:
	(_floor(number)[key] as Dictionary)[id] = true


func _set_has(number: int, key: String, id: String) -> bool:
	return (_floor(number)[key] as Dictionary).has(id)
