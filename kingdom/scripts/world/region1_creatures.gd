extends Node
## Region 1 creature placement and ecology tuning (package C11, docs/regions/REGION_1_PLAN.md). Placement only:
## animation and combat behaviour stay with Codex (X3 Stagborn, X4 humanoids); this node decides WHERE things live.
##   * seeds dens into Frontier.ecology, once per species: Stagborn herds and the Antlered Warden at the Glade and the
##     upper Ashrun, ghoul dens at the ruins, giant-wasp nests, bog-toad dens by the marshes and the Mere, rift slimes and
##     wraiths at the Ashen Scar, the Rift and the Greyseam seam (data/region1/world/creatures.json). FrontierPresence
##     already gives every den bodies near the player, from the creature_models + Wolf.SPECIES rows this package added;
##     the den species key IS the model key. Rift variants of ordinary species are the Scar-tide hook H4, not here.
##   * moves the Stagborn herds with the seasons (spring and summer to the summer range, autumn and winter home) and logs
##     a "herd_migration" ecology event the gossip and quests can read;
##   * gives every bandit camp its roster (Squad of raiders, a captain-named band) while the player is near, and brings
##     a wiped-out camp back after a few days.
## Everything is optional content: nothing here gates the story. Cost: one 1 s timer; the day step touches a handful of dens.

const Squad := preload("res://scripts/army/squad.gd")
const CasterSpawns := preload("res://scripts/combat/caster_spawns.gd")
const PathPatrols := preload("res://scripts/world/path_patrols.gd")
const FILE := "res://data/region1/world/creatures.json"
const KEEP: Array[String] = ["1H_Axe", "Barbarian_Round_Shield", "Barbarian_Hat"]

var focus := Vector3.ZERO
var _eco: RAMonsterEcology
var _timer := 0.0
var _camps: Array[Dictionary] = []          # {site, n, band, squad (or null), dead_day}
var _connected: Node = null

static var _cache: Dictionary = {}


static func data() -> Dictionary:
	if _cache.is_empty():
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(FILE)) if FileAccess.file_exists(FILE) else {}
		_cache = d if d is Dictionary else {}
	return _cache


func _ready() -> void:
	name = "Region1Creatures"
	add_to_group("r1_creatures")
	if OS.get_cmdline_user_args().has("--r1worldoff"):
		set_process(false)
		return
	var cfg := data()
	for s in WorldGen.sites:
		if String(s.get("kind", "")) == "bandit_camp":
			var r: Dictionary = (cfg.get("camps", {}) as Dictionary).get(String(s["name"]), cfg.get("camp_default", {}))
			_camps.append({"site": s, "n": int(r.get("n", 4)), "band": String(r.get("band", "Outlaws")), "squad": null, "dead_day": -999})
	_timer = 0.5
	add_child(PathPatrols.new())          # sect-hall disciples and garrison knight captains (budgeted)


func _process(delta: float) -> void:
	var p := get_parent()
	if p and "focus" in p:
		focus = p.focus
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 1.0
	if Frontier.ecology != _eco:
		_eco = Frontier.ecology          # a new game or a load replaces the ecology object
		seed_ecology(_eco)
	if _connected != Frontier:
		_connected = Frontier
		Frontier.day_advanced.connect(_on_day)
	_update_camps(Vector2(focus.x, focus.z))


func _on_day(day: int) -> void:
	if _eco != null:
		herd_step(_eco, String(WorldSim.season), day)


# --- seeding (pure: tests call these) ---------------------------------------------------

## Seeds every species of creatures.json that has no den yet. Returns how many dens were added.
static func seed_ecology(eco: RAMonsterEcology) -> int:
	var present := {}
	for d: Dictionary in eco.dens:
		present[String(d["species"])] = true
	var added := 0
	for spec: Dictionary in data().get("dens", []):
		var species := String(spec["species"])
		if present.has(species):
			continue
		if not RAMonsterEcology.SPECIES.has(species):
			continue
		var pos := den_position(spec)
		if pos == Vector2.INF:
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("r1c:" + String(spec["tag"]))
		var pop: Array = spec.get("pop", [3, 4])
		eco.add_den(species, pos, rng.randi_range(int(pop[0]), int(pop[1])))
		added += 1
	return added


static func _center(near: Variant) -> Vector2:
	if near is Array:
		return Vector2(float(near[0]), float(near[1]))
	var t := String(near)
	if t == "lake":
		return WorldGen.lake_center
	if t.begins_with("settlement:"):
		for s in WorldGen.settlements:
			if String(s["name"]) == t.substr(11):
				return s["pos"]
	if t.begins_with("site:"):
		for s in WorldGen.sites:
			if String(s["name"]) == t.substr(5):
				return s["pos"]
	return Vector2.INF


## Dry, off-road ground at the spec's distance band from its anchor (deterministic per tag); INF when the anchor is missing.
static func den_position(spec: Dictionary) -> Vector2:
	var c := _center(spec.get("near", ""))
	if c == Vector2.INF:
		return Vector2.INF
	var d: Array = spec.get("d", [20, 80])
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("r1p:" + String(spec["tag"]))
	var want_water := bool(spec.get("water", false))
	var best := Vector2.INF
	for i in 90:
		var q := c + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(float(d[0]), float(d[1]))
		if absf(q.x) > WorldGen.WORLD_HALF - 200.0 or absf(q.y) > WorldGen.WORLD_HALF - 200.0 or WorldGen.is_water(q.x, q.y):
			continue
		if WorldGen.road_distance(q.x, q.y) < 18.0 or _in_settlement(q):
			continue
		if want_water and i < 70 and not WorldGen.near_water(q.x, q.y, 16.0):
			continue
		best = q
		break
	return best


static func _in_settlement(q: Vector2) -> bool:
	for s in WorldGen.settlements:
		if q.distance_to(s["pos"]) < float(s["radius"]) * 1.4:
			return true
	return false


# --- herds --------------------------------------------------------------------------------

## Where a herd wants to be this season: the summer range in spring and summer, home otherwise (snapped to dry ground).
static func season_target(spec: Dictionary, season: String) -> Vector2:
	var goal: Variant = spec.get("summer") if season in ["spring", "summer"] else spec.get("home")
	var c := _center(goal)
	if c == Vector2.INF:
		return Vector2.INF
	for k in 12:
		var q := c + Vector2.from_angle(float(k) * 2.4) * (float(k) * 14.0)
		if not WorldGen.is_water(q.x, q.y):
			return q
	return c


## One game day of migration: each herd walks toward its seasonal target. Returns the herds that moved.
static func herd_step(eco: RAMonsterEcology, season: String, day: int) -> int:
	var herds: Array = data().get("herds", [])
	var dens_by_species := {}
	for d: Dictionary in eco.dens:
		var sp := String(d["species"])
		if not dens_by_species.has(sp):
			dens_by_species[sp] = []
		(dens_by_species[sp] as Array).append(d)
	# Herd specs map to the species' dens in seeding order (ids are stable across saves).
	var seen := {}
	var moved := 0
	for spec: Dictionary in data().get("dens", []):
		var tag := String(spec["tag"])
		var hs: Dictionary = {}
		for h: Dictionary in herds:
			if String(h["tag"]) == tag:
				hs = h
		var species := String(spec["species"])
		var k := int(seen.get(species, 0))
		seen[species] = k + 1
		if hs.is_empty() or not dens_by_species.has(species) or k >= (dens_by_species[species] as Array).size():
			continue
		var den: Dictionary = (dens_by_species[species] as Array)[k]
		if not bool(den["alive"]):
			continue
		var home := _center(hs["home"])
		var goal := season_target(hs, season)
		if goal == Vector2.INF or home == Vector2.INF:
			continue
		var pos: Vector2 = den["pos"]
		var to := goal - pos
		if to.length() < 6.0:
			continue
		var step := minf(to.length(), float(hs.get("speed", 60.0)))
		den["pos"] = pos + to.normalized() * step
		moved += 1
		if String(den.get("r1_dir", "")) != season:
			den["r1_dir"] = season
			eco._log_event({"day": day, "type": "herd_migration", "species": species, "den_id": int(den["id"]), "pos": den["pos"],
				"toward": "summer range" if season in ["spring", "summer"] else "home"})
	return moved


# --- bandit camps --------------------------------------------------------------------------

func _update_camps(p: Vector2) -> void:
	var cfg := data()
	var build := float(cfg.get("camp_build", 170.0))
	var free := float(cfg.get("camp_free", 330.0))
	var respawn := int(cfg.get("camp_respawn_days", 6))
	for c: Dictionary in _camps:
		var site: Dictionary = c["site"]
		var d := p.distance_to(site["pos"])
		var squad: Variant = c["squad"]
		if squad != null and not is_instance_valid(squad):
			c["squad"] = null
			squad = null
		if squad != null:
			# Story hook: each raider of the Ashen Hand that falls is a kill the main quest can count (never required to fight).
			var alive: int = (squad as Squad).alive()
			var prev: int = int(c.get("alive", alive))
			if alive < prev and String(c["band"]) == "The Ashen Hand":
				for k in prev - alive:
					Life.region1_kill.emit("ashen_hand_saboteur", Vector3(site["pos"].x, 0.0, site["pos"].y))
			c["alive"] = alive
			if alive <= 0:
				c["dead_day"] = int(WorldSim.day)
				(squad as Squad).queue_free()
				c["squad"] = null
			elif d > free:
				for s in (squad as Squad).soldiers.duplicate():
					if is_instance_valid(s):
						s.queue_free()
				(squad as Squad).queue_free()
				c["squad"] = null
		elif d < build and int(WorldSim.day) - int(c["dead_day"]) >= respawn:
			c["squad"] = _spawn_roster(site, int(c["n"]))
			c["alive"] = int(c["n"])


func _spawn_roster(site: Dictionary, n: int) -> Squad:
	var pos: Vector2 = site["pos"]
	var yaw := float(site.get("yaw", 0.0))
	var at := pos + Vector2(sin(yaw), cos(yaw)) * 5.0          # in front of the camp fire, not inside a tent
	var base := Vector3(at.x, WorldGen.height(at.x, at.y), at.y)
	var squad := Squad.new().setup(1, "raider", "Barbarian", KEEP)
	squad.anchor = base
	squad.aggro_radius = 26.0
	add_child(squad)
	squad.add_soldiers(n, base, CasterSpawns.mix("bandit_camp", n, hash(String(site.get("name", ""))) + int(WorldSim.day)))
	return squad


## Story hook (r1_story_director.gd): a camp the player has emptied fills again at once when the quest needs its band.
func wake_camp(at: Vector2) -> void:
	for c: Dictionary in _camps:
		if (c["site"]["pos"] as Vector2).distance_to(at) < 90.0 and c["squad"] == null:
			c["dead_day"] = -999
