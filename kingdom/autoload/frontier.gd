extends Node
## The frontier simulation: runestone network + monster ecology + threat map,
## advanced once per in-game day. Seeds the starting village's ring of stones,
## the waystones along its safe road, and wolf dens in the surrounding forests.

signal day_advanced(day: int)
signal frontier_event(text: String, pos: Vector2)

var runestones := RARunestoneNetwork.new()
var ecology := RAMonsterEcology.new()
var threat: RAThreatMap
## 0..1: how restless the Rift is this season (raised by Rift events later).
var rift_instability := 0.1

var _last_day := -1


func _ready() -> void:
	_new_state()
	WorldSim.hour_changed.connect(_on_hour)


func _new_state() -> void:
	threat = RAThreatMap.new(runestones, ecology)
	_seed_frontier()
	ecology.migration.connect(func(den: Dictionary, from_pos: Vector2, to_pos: Vector2) -> void:
		frontier_event.emit("Wolves are moving %s." % _compass(to_pos - from_pos), to_pos))


## Back to the freshly seeded frontier of a new game (runestones, dens, threat map).
func reset() -> void:
	runestones = RARunestoneNetwork.new()
	ecology = RAMonsterEcology.new()
	rift_instability = 0.1
	_last_day = -1
	_new_state()


func _seed_frontier() -> void:
	var home: Dictionary = WorldGen.settlements[0]
	var c: Vector2 = home["pos"]
	var r: float = home["radius"]
	# Ring of stones around the village.
	for i in 6:
		var ang := TAU * i / 6.0 + 0.3
		runestones.add_stone(c + Vector2(cos(ang), sin(ang)) * (r + 18.0), r * 1.45, 0,
			["North", "Northeast", "Southeast", "South", "Southwest", "Northwest"][i] + " Stone")
	# Waystones along the safe road toward the nearest neighbour.
	var gates := WorldGen.gate_angles(home)
	if not gates.is_empty():
		var dir := Vector2(cos(gates[0]), sin(gates[0]))
		for k in 3:
			var p := c + dir * (r + 140.0 + k * 170.0)
			runestones.add_stone(p, 110.0, 0, "Waystone %d" % (k + 1))
	# Stones along every kingdom and rural road, spaced so their radii overlap;
	# frontier (village-to-village) roads get wide, weak gaps.
	runestones.seed_road_stones()
	# Wolf dens in forest, outside the protected ring.
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var placed := 0
	var tries := 0
	while placed < 8 and tries < 600:
		tries += 1
		var ang := rng.randf() * TAU
		var p := c + Vector2(cos(ang), sin(ang)) * rng.randf_range(320.0, 1100.0)
		if WorldGen.forest_density(p.x, p.y) < 0.45 or runestones.coverage(p) > 0.05:
			continue
		ecology.add_den("wolf", p, rng.randi_range(4, 9))
		placed += 1
	_seed_far_dens()


## The rest of the 8 x 8 km map: dens in the far woods, more of them and deadlier the further
## they sit from Kingsreach (bands of [min, max] metres, den count, species, pack size).
## Their own RNG stream, so the valley's eight dens above are exactly where they always were.
const FAR_DEN_BANDS := [
	[1400.0, 2500.0, 6, "wolf", Vector2i(5, 10)],
	[2500.0, 3400.0, 6, "wolf", Vector2i(8, 13)],
	[3400.0, 6000.0, 5, "corrupted_wolf", Vector2i(4, 8)],
]


func _seed_far_dens() -> void:
	var capital := Vector2.ZERO
	for s: Dictionary in WorldGen.settlements:
		if s["kind"] == "castle":
			capital = s["pos"]
			break
	var rng := RandomNumberGenerator.new()
	rng.seed = 78
	var lim := WorldGen.WORLD_HALF - 300.0
	for band: Array in FAR_DEN_BANDS:
		var placed := 0
		var tries := 0
		while placed < int(band[2]) and tries < 3000:
			tries += 1
			var p := Vector2(rng.randf_range(-lim, lim), rng.randf_range(-lim, lim))
			var d := p.distance_to(capital)
			if d < float(band[0]) or d >= float(band[1]) or WorldGen.forest_density(p.x, p.y) < 0.45 or runestones.coverage(p) > 0.05:
				continue
			var near := WorldGen.nearest_settlement(p)
			if not near.is_empty() and p.distance_to(near["pos"]) < float(near["radius"]) * 1.8 + 150.0:
				continue
			var pack: Vector2i = band[4]
			ecology.add_den(String(band[3]), p, rng.randi_range(pack.x, pack.y))
			placed += 1


func _on_hour(_hour: int) -> void:
	if WorldSim.day != _last_day:
		_last_day = WorldSim.day
		advance_day(WorldSim.day)


func advance_day(day: int) -> void:
	runestones.tick_day(day)
	ecology.tick_day(runestones.coverage, rift_instability, WorldSim.season == "winter")
	_maybe_apex_moves_in(day)
	threat.expire(day)
	for s in runestones.stones:
		if s["condition"] < 0.35:
			frontier_event.emit("%s is failing (%d%%)." % [s["name"], int(s["condition"] * 100)], s["pos"])
	day_advanced.emit(day)


## Now and then a bear or troll claims territory deep in the forest, starting the
## chain: wolves displaced toward farms, livestock lost, hunters find the real cause.
func _maybe_apex_moves_in(day: int) -> void:
	if day < 10:
		return
	for d: Dictionary in ecology.dens:
		if d["alive"] and bool(d.get("apex", false)):
			return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([WorldSim.SEED, "apex", day])
	if rng.randf() > 1.0 / 30.0:
		return
	var c: Vector2 = WorldGen.settlements[0]["pos"]
	for _t in 60:
		var ang := rng.randf() * TAU
		var p := c + Vector2(cos(ang), sin(ang)) * rng.randf_range(900.0, 2600.0)
		if WorldGen.forest_density(p.x, p.y) < 0.4 or runestones.coverage(p) > 0.02:
			continue
		ecology.spawn_apex("troll" if rng.randf() < 0.4 else "bear", p, ecology.current_day())
		return


## World event hooks used by gameplay (patrol killed, nest destroyed, etc.).
func report(label: String, pos: Vector2, radius: float, value: float, days: int) -> void:
	threat.add_modifier(label, pos, radius, value, WorldSim.day + days)
	frontier_event.emit(label, pos)


func threat_at(p: Vector2) -> Dictionary:
	return threat.evaluate(p)


## How much more dangerous the wilds are at this hour (0..24): day, dusk,
## night, then the loneliest stretch before dawn. Monster aggression range,
## ambush frequency and the rare apex encounter all scale with this.
func danger_mult(hour: float) -> float:
	var h := fposmod(hour, 24.0)
	if h >= 6.0 and h < 17.0:
		return 1.0
	elif h >= 17.0 and h < 20.0:
		return 1.5
	elif h >= 20.0 or h < 2.0:
		return 2.5
	return 3.0


func serialize() -> Dictionary:
	# "eco" already carries the dens (deserialize falls back to a legacy top-level "dens" list only when "eco" is absent).
	return {"runestones": runestones.serialize(), "eco": ecology.serialize_state(), "rift": rift_instability}


func deserialize(d: Dictionary) -> void:
	runestones.deserialize(d.get("runestones", []))
	if d.has("eco"):
		ecology.deserialize_state(d["eco"])
	else:
		ecology.deserialize(d.get("dens", []))
	rift_instability = float(d.get("rift", rift_instability))
	_last_day = WorldSim.day


static func _compass(v: Vector2) -> String:
	var dirs := ["east", "southeast", "south", "southwest", "west", "northwest", "north", "northeast"]
	return "toward the " + dirs[int(round(fposmod(atan2(v.y, v.x), TAU) / (TAU / 8.0))) % 8]
