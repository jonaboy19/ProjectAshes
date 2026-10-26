extends RefCounted
## Entrance hooks: which existing world sites open onto a labyrinth, and the per-save registry of labyrinth states.
## Pure data + statics. The world side (a door at the site) only needs `labyrinth_for_site(site)` and then
## `registry.enter(id)`; nothing here edits RegionSites, so no existing site id moves.
##
##   Deepdark (camp "Deepdark Warren", Dunhallow uplands)      -> "deepdark"
##   Ironmarch mines (Deepvein/Ironroot/Coldseam/Silverthread/Skullpick/Redtusk)  -> "ironmarch_deeps"
##   Rift ruins (Riftglass Cavern, Scarlight Grotto, kind rift_ruins)             -> "rift_ruins"

const Data := preload("res://scripts/dungeon/labyrinth_data.gd")
const State := preload("res://scripts/dungeon/labyrinth_state.gd")

var states: Dictionary = {}                 # labyrinth id -> LabyrinthState
var world_seed: int = 0


func _init(seed_value := 0) -> void:
	world_seed = seed_value


## Labyrinth id a world site (a RegionSites / WorldGen site dictionary: name, kind, optionally id) opens onto, or "".
static func labyrinth_for_site(site: Dictionary) -> String:
	var name := str(site.get("name", "")).to_lower()
	var kind := str(site.get("kind", ""))
	for id: String in Data.DEFS:
		var def: Dictionary = Data.DEFS[id]
		if (def["kinds"] as Array).has(kind):
			return id
		for frag: String in def["sites"]:
			if name.contains(frag):
				return id
	return ""


## All (site, labyrinth id) matches in a site list, in list order. One entrance per labyrinth: the first match wins.
static func plan(sites: Array) -> Array:
	var out: Array = []
	var taken := {}
	for s: Dictionary in sites:
		var id := labyrinth_for_site(s)
		if id != "" and not taken.has(id):
			taken[id] = true
			out.append({"labyrinth": id, "site": str(s.get("id", s.get("name", ""))), "name": str(s.get("name", "")), "pos": s.get("pos", Vector2.ZERO)})
	return out


## Player-facing entrance card.
static func entrance_info(id: String) -> Dictionary:
	var d := Data.def_of(id)
	if d.is_empty():
		return {}
	return {"id": id, "name": d["name"], "blurb": d["blurb"], "floors": d["floors"], "level_min": Data.level_for(d, 0),
		"level_max": Data.level_for(d, int(d["floors"]) - 1), "region": d["region"]}


## State of a labyrinth, created on first use (floor 1 unlocked).
func state(id: String) -> RefCounted:
	if not states.has(id):
		states[id] = State.new(id, world_seed + int(Data.DEFS[id]["seed_salt"]))
	return states[id]


## Enter a labyrinth at floor `number` (default: floor 1, or the deepest unlocked warp). Returns the floor number entered, 0 if refused.
func enter(id: String, number := 1, day := 0) -> int:
	if not Data.DEFS.has(id):
		return 0
	var st: RefCounted = state(id)
	return number if st.enter_floor(number, day) else 0


func serialize() -> Dictionary:
	var out := {}
	for id: String in states:
		out[id] = (states[id] as RefCounted).serialize()
	return {"version": 1, "seed": world_seed, "labyrinths": out}


func deserialize(d: Dictionary) -> void:
	states.clear()
	if int(d.get("version", 0)) != 1:
		return
	world_seed = int(d.get("seed", world_seed))
	var l: Dictionary = d.get("labyrinths", {})
	for id: String in l:
		if Data.DEFS.has(id):
			states[id] = State.from_dict(l[id])
