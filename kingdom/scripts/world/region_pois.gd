extends RefCounted
## Exploration rewards across the region: 26 small points of interest that pay for wandering (docs/design/REALM_PLAN.md
## "Freedom and exploration first"). Vistas, hidden shrines, lore stones, abandoned camps with notes, rare herb patches,
## caches under landmarks, old battlefields, a fishing secret, a hermit, a hunter who knows a rumour, and Rift anomalies
## that only show at night.
##
## This file is DATA + a planner, like region_caves.gd: `plan(seed, taken)` returns WorldGen.sites entries (kind "poi_*",
## {"secret": true} so Discovery keeps them off the map until found), on its own RNG stream; `landmarks()` turns the
## planned POIs into Region1Look-format landmark dicts (parts, scatter, lights) for scripts/world/exploration_director.gd,
## which also handles finding them, the interactions and the rewards.
## Hook (one line in region_sites.gd, last before the ids are set):
##   out.append_array(preload("res://scripts/world/region_pois.gd").plan(seed_value, out))

const HV := preload("res://scripts/world/hidden_valley.gd")
const FREE := "free:"
const REGION := "region/nature/"
const SPACING := 240.0
const EDGE := 500.0

## kind -> [interact prompt, repeat days (0 = once, -1 = not a pickup), trigger radius m]
const KINDS := {
	"poi_vista": ["Take in the view", -1, 24.0],
	"poi_shrine": ["Make an offering", 0, 18.0],
	"poi_lore": ["Read the stone", 0, 18.0],
	"poi_camp": ["Search the camp", 0, 22.0],
	"poi_herbs": ["Gather moonpetal", 10, 16.0],
	"poi_cache": ["Dig", 0, 16.0],
	"poi_battlefield": ["Search the relics", 0, 28.0],
	"poi_fishing": ["Cast a line", 1, 16.0],
	"poi_hermit": ["Talk", -1, 26.0],
	"poi_rift": ["Touch the shimmer", 0, 26.0],
	"poi_hunter": ["Talk", -1, 26.0],
}

## Extra items the POIs and the vale hand out (registered like gathering_items.gd; ids are plain so saves stay readable).
const ITEMS := {
	"moonpetal": {"name": "Moonpetal", "category": "healing", "price": 38, "heal": 45, "max_stack_size": 20,
		"description": "A pale flower that only opens in the dark. Potent in a salve."},
	"spring_crystal": {"name": "Spring Crystal", "category": "material", "price": 60, "max_stack_size": 20,
		"description": "A sliver of blue crystal grown in sweet water. Alchemists pay well."},
	"heartwood": {"name": "Heartwood Timber", "category": "material", "price": 34, "max_stack_size": 20,
		"description": "Dense, honey-coloured wood from an old-growth oak. It never warps."},
	"spirit_dew": {"name": "Spirit Dew", "category": "healing", "price": 26, "heal": 40, "max_stack_size": 10,
		"description": "Dew gathered from a hidden shrine. It tastes of rain and iron."},
	"battlefield_relic": {"name": "Battlefield Relic", "category": "material", "price": 48, "max_stack_size": 10,
		"description": "A dented buckle, an arrowhead, a ring. Collectors want the names scratched on them."},
	"silverfin": {"name": "Silverfin", "category": "food", "price": 22, "nutrition": 34, "heal": 10, "max_stack_size": 10,
		"description": "A trout that has never seen a net."},
	"rift_shard": {"name": "Rift Shard", "category": "material", "price": 75, "max_stack_size": 10,
		"description": "A violet sliver, warm to the touch, humming when nobody is near."},
	"burnt_map_fragment": {"name": "Burnt Map Fragment", "category": "document", "price": 0, "max_stack_size": 1,
		"description": "Half a map, scorched at the edges. A ring of stones is drawn in a bowl of ridges."},
}

## The 26 POIs. name, kind, lore (journal text), reward: items [[id, n]], gold, know (construction facts), reveal (map
## radius m), lead [fact, text] (Society knowledge, text only), xp. Order fixes the planner's cell choice.
const DEFS: Array[Dictionary] = [
	{"id": "kestrel", "kind": "poi_vista", "name": "Kestrel's Perch", "reveal": 700.0, "xp": 12,
		"lore": "From this shelf of rock the whole country lies flat: fields like a patchwork quilt, a river like a dropped ribbon, and far off, smoke from somebody's hearth."},
	{"id": "longlook", "kind": "poi_vista", "name": "The Long Look", "reveal": 700.0, "xp": 12,
		"lore": "Shepherds call this knoll the Long Look. On a clear morning you can count three roads from it and lose count of the hills."},
	{"id": "shoulder", "kind": "poi_vista", "name": "Saint's Shoulder", "reveal": 700.0, "xp": 12,
		"lore": "A pilgrim carved a shallow seat into the stone here, facing west. Nobody remembers which saint, but the view is worth the walk."},
	{"id": "windward", "kind": "poi_vista", "name": "Windward Crown", "reveal": 700.0, "xp": 12,
		"lore": "The wind never stops on the Windward Crown, and the grass lies over like combed hair. Below, the land unrolls toward the sea that nobody here has seen."},
	{"id": "hind_shrine", "kind": "poi_shrine", "name": "Shrine of the Quiet Hind", "xp": 15, "items": [["spirit_dew", 2]], "reveal": 350.0,
		"lore": "A tiny shrine, hidden in the trees, where hunters leave a feather before the season. A hind is scratched into the stone, looking back over her shoulder."},
	{"id": "moss_altar", "kind": "poi_shrine", "name": "Mossbound Altar", "xp": 15, "items": [["spirit_dew", 1], ["healing_herb", 3]], "reveal": 350.0,
		"lore": "Moss has swallowed half of the altar and all of its name. Someone still leaves fresh berries on it."},
	{"id": "wren_stone", "kind": "poi_shrine", "name": "The Wren's Offering Stone", "xp": 15, "items": [["spirit_dew", 2]], "gold": 15, "reveal": 350.0,
		"lore": "Travellers press a coin into the crack in the Wren's Stone for a safe road. Somebody has been collecting them, but not all."},
	{"id": "builders_stone", "kind": "poi_lore", "name": "The Builders' Stone", "xp": 20, "know": ["build:masonry"], "reveal": 300.0,
		"lore": "Lines of tiny pictures cover the stone: a mason fitting a block, a wall rising, a keystone dropped into an arch. The last picture is a house with smoke from its chimney."},
	{"id": "ash_oath", "kind": "poi_lore", "name": "Stone of the First Fires", "xp": 20, "know": ["build:fire"], "reveal": 300.0,
		"lore": "Before the ash, the valley families lit a fire at this stone on the first frost and kept it burning until the thaw. The hollow at its foot is still black."},
	{"id": "carpenter_stone", "kind": "poi_lore", "name": "The Wright's Marker", "xp": 20, "know": ["build:carpentry"], "reveal": 300.0,
		"lore": "Joints are cut into this marker like a lesson: mortise and tenon, dovetail, scarf. A wright's mark repeats down one side, the same three strokes."},
	{"id": "surveyor", "kind": "poi_camp", "name": "The Surveyor's Camp", "xp": 18, "items": [["bandage", 2]], "gold": 30,
		"lead": ["lead:companion_ranger", "A ranger named Veyl winters near the old pass road and needs someone to cover her back. A note in the surveyor's camp says she is good with a bow and bad with crowds."],
		"lore": "A survey tent, a cold fire, a slate of measurements. The last entry reads: 'Gone to ask the ranger about the ridge. Back by dusk.' The slate is thick with dust."},
	{"id": "deserter", "kind": "poi_camp", "name": "The Deserter's Lean-to", "xp": 18, "items": [["iron_dagger", 1], ["cheese", 2]], "know": ["build:carpentry"],
		"lore": "A lean-to, well hidden, with a soldier's cloak folded under it. A note: 'I could not hold the line. I hope somebody finds a better use for this than I did.'"},
	{"id": "cartographer", "kind": "poi_camp", "name": "The Cartographer's Last Fire", "xp": 22, "items": [["burnt_map_fragment", 1]], "gold": 20,
		"lore": "A scorched bedroll and a satchel singed at the edges. Most of the maps are ash, but one scrap survived, tucked against the ground."},
	{"id": "moon_hollow", "kind": "poi_herbs", "name": "Moonpetal Hollow", "xp": 12, "items": [["moonpetal", 3]], "reveal": 250.0,
		"lore": "A hollow where pale flowers crowd the roots of an old birch. They only open after dark, and the ground smells of rain."},
	{"id": "dewcup", "kind": "poi_herbs", "name": "Dewcup Glade", "xp": 12, "items": [["moonpetal", 2], ["healing_herb", 3]], "reveal": 250.0,
		"lore": "Dewcup Glade holds water in its leaves until noon. A herbalist's knife lies in the grass, rusted shut."},
	{"id": "thrush_bank", "kind": "poi_herbs", "name": "Thrush Bank Patch", "xp": 12, "items": [["moonpetal", 2], ["mushroom", 3]], "reveal": 250.0,
		"lore": "Thrushes nest along this bank and drop seeds wherever they please. The patch has grown rich and strange."},
	{"id": "leaning_oak", "kind": "poi_cache", "name": "Under the Leaning Oak", "xp": 18, "gold": 90, "items": [["copper_ring", 1]],
		"lore": "Something was buried where the oak's shadow lies at noon on the longest day. Whoever did it never came back for it."},
	{"id": "watchstone_cache", "kind": "poi_cache", "name": "Beneath the Toppled Watchstone", "xp": 18, "gold": 140, "items": [["healing_salve", 2]],
		"lore": "When the watchstone fell, it covered a cavity. The cavity held a strongbox. The strongbox held a tired pile of coin and a salve tin."},
	{"id": "tinker", "kind": "poi_cache", "name": "The Tinker's Buried Box", "xp": 18, "gold": 60, "items": [["tools", 2], ["horseshoe", 3]],
		"lore": "A tinker's box, buried quickly and marked with a cairn of three stones. He must have planned to return in spring."},
	{"id": "broken_lances", "kind": "poi_battlefield", "name": "Field of Broken Lances", "xp": 22, "items": [["battlefield_relic", 3]], "gold": 40, "reveal": 400.0,
		"lore": "Lance butts stand in the grass like a second crop. Old quarrels over a border nobody draws any more ended here, and the grass has not forgiven it."},
	{"id": "ash_ford", "kind": "poi_battlefield", "name": "The Ash Ford Skirmish", "xp": 22, "items": [["battlefield_relic", 2], ["iron_ingot", 2]], "reveal": 400.0,
		"lore": "A little battle, long ago, over a ford. Shields still lie where they fell, rusted to the colour of the soil."},
	{"id": "silent_pool", "kind": "poi_fishing", "name": "The Silent Pool", "xp": 15, "items": [["silverfin", 1]], "reveal": 300.0,
		"lore": "A pool so still that the clouds seem to lie on the bottom. Fishermen say the trout here are the colour of coin and twice as shy."},
	{"id": "hermit", "kind": "poi_hermit", "name": "Brother Anselm's Hut", "xp": 20, "reveal": 400.0,
		"lore": "A hermit lives here, with herbs drying from every beam and a pot that is never quite empty. He listens more than he talks, and he has been listening for a long time."},
	{"id": "shimmer_fen", "kind": "poi_rift", "name": "The Shimmer in the Fen", "xp": 25, "items": [["rift_shard", 1]], "reveal": 300.0,
		"lore": "After dark the air over the fen folds like cloth. Nothing comes through, but the reeds lean toward it all night."},
	{"id": "breathing_stone", "kind": "poi_rift", "name": "The Breathing Stone", "xp": 25, "items": [["rift_shard", 2]], "reveal": 300.0,
		"lore": "A stone that breathes at night: a slow violet glow, in and out, like something sleeping under it."},
	{"id": "corwen", "kind": "poi_hunter", "name": "Old Corwen's Camp", "xp": 15, "reveal": 350.0,
		"lore": "An old hunter keeps a camp here, in the lee of the ridge. He knows every animal track within a day's walk and talks about them to anyone who will sit still."},
]

## Filled by plan(): poi id -> {pos: Vector2, yaw: float}.
static var placed: Dictionary = {}
## The sites planned so far (WorldGen.sites is not assigned yet while RegionSites.plan runs).
static var _ctx: Array[Dictionary] = []


static func def(id: String) -> Dictionary:
	for d: Dictionary in DEFS:
		if d["id"] == id:
			return d
	return {}


static func prompt_of(kind: String) -> String:
	return String((KINDS.get(kind, ["Use"]) as Array)[0])


static func repeat_days(kind: String) -> int:
	return int((KINDS.get(kind, ["", 0, 0]) as Array)[1])


static func trigger_radius(kind: String) -> float:
	return float((KINDS.get(kind, ["", 0, 20.0]) as Array)[2])


## Adds ITEMS to the live protoset (same approach as gathering_items.gd). Safe to repeat.
static func register_items(life: Node) -> void:
	if life == null:
		return
	var inv: Variant = life.get("inventory")
	if inv == null or inv.protoset == null:
		return
	var json: JSON = inv.protoset
	var tree: Variant = inv.get_prototree()
	var data: Variant = json.data
	for id: String in ITEMS:
		var entry: Dictionary = ITEMS[id]
		if data is Dictionary and not (data as Dictionary).has(id):
			(data as Dictionary)[id] = entry.duplicate()
		if tree.has_prototype(id):
			continue
		var proto: Variant = tree.get_root().inherit(id)
		for key: String in entry:
			proto.set_property(key, entry[key])


# --- Planner -------------------------------------------------------------------------------------------------

static func poi_id_of(site: Dictionary) -> String:
	return String(site.get("poi", ""))


## WorldGen.sites entries for every POI, placed on stratified cells of the whole region (own RNG stream).
static func plan(seed_value: int, taken: Array[Dictionary]) -> Array[Dictionary]:
	placed.clear()
	_ctx = taken
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 97 + 41
	var out: Array[Dictionary] = []
	# 7 x 7 cells of the +-3.5 km land; shuffled, each POI takes the next cell that yields a good spot.
	var cells: Array[Vector2] = []
	var half := WorldGen.WORLD_HALF - EDGE
	var cs := half * 2.0 / 7.0
	for j in 7:
		for i in 7:
			cells.append(Vector2(-half + i * cs, -half + j * cs))
	_shuffle(cells, rng)
	var ci := 0
	var all: Array[Dictionary] = taken.duplicate()
	for d: Dictionary in DEFS:
		var pos := Vector2.INF
		var tries := 0
		while pos == Vector2.INF and tries < cells.size():
			var cell := cells[ci % cells.size()]
			ci += 1
			tries += 1
			pos = _spot(String(d["kind"]), String(d["id"]), cell, cs, rng, all)
		if pos == Vector2.INF:
			continue
		var yaw := rng.randf() * TAU
		placed[d["id"]] = {"pos": pos, "yaw": yaw}
		var kind := String(d["kind"])
		var site := {"name": String(d["name"]), "kind": kind, "pos": pos, "yaw": yaw, "clear": 7.0, "flatten": false,
			"parts": [], "lights": [], "secret": true, "radius": trigger_radius(kind), "poi": String(d["id"])}
		out.append(site)
		all.append(site)
	return out


static func _shuffle(a: Array, rng: RandomNumberGenerator) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t: Variant = a[i]
		a[i] = a[j]
		a[j] = t


## Best of a few random candidates in the cell for the kind, or INF.
static func _spot(kind: String, id: String, cell: Vector2, cs: float, rng: RandomNumberGenerator, taken: Array[Dictionary]) -> Vector2:
	var best := Vector2.INF
	var best_s := -1.0
	var n := 40
	var fixed := _fixed_area(id)
	for i in n:
		var p := cell + Vector2(rng.randf(), rng.randf()) * cs
		if fixed.x > 0.0:
			p = Vector2(fixed.y, fixed.z) + Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * fixed.x
		if not _free(p, taken, kind):
			continue
		var s := _score(kind, p, rng)
		if s > best_s:
			best_s = s
			best = p
	return best if best_s >= 0.0 else Vector2.INF


## (radius, x, z) for POIs that must sit in one region: the hunter west of Cindermoor toward the vale; the hermit far from roads.
static func _fixed_area(id: String) -> Vector3:
	if id == "corwen":
		var c := HV.w(800.0, 120.0)
		return Vector3(240.0, c.x, c.y)
	if id == "shimmer_fen" or id == "breathing_stone":
		var riftn := 0
		for s in _ctx:
			if String(s.get("kind", "")) == "rift":
				if riftn == (0 if id == "shimmer_fen" else 1):
					var p: Vector2 = s["pos"]
					return Vector3(520.0, p.x, p.y)
				riftn += 1
	return Vector3.ZERO


static func _free(p: Vector2, taken: Array[Dictionary], kind: String) -> bool:
	if absf(p.x) > WorldGen.WORLD_HALF - 350.0 or absf(p.y) > WorldGen.WORLD_HALF - 350.0:
		return false
	if HV.protected_ground(p) or p.distance_to(HV.CENTER) < 720.0:
		return false
	if kind != "poi_fishing" and WorldGen.near_water(p.x, p.y, 10.0):
		return false
	if WorldGen.is_water(p.x, p.y) or WorldGen.road_distance(p.x, p.y) < 14.0:
		return false
	for s in WorldGen.settlements:
		if p.distance_to(s["pos"]) < float(s["radius"]) * 1.6 + 40.0:
			return false
	for g in WorldGen.camp_grounds:
		if p.distance_to(g["pos"]) < float(g["radius"]) * 1.8 + 30.0:
			return false
	for t in taken:
		var d := p.distance_to(t["pos"])
		if String(t.get("kind", "")).begins_with("poi_"):
			if d < SPACING:
				return false
		elif d < float(t.get("clear", 0.0)) + 40.0:
			return false
	return slope_at(p) < 0.55


static func slope_at(p: Vector2) -> float:
	var e := 3.0
	var dx := WorldGen.height(p.x + e, p.y) - WorldGen.height(p.x - e, p.y)
	var dz := WorldGen.height(p.x, p.y + e) - WorldGen.height(p.x, p.y - e)
	return Vector2(dx, dz).length() / (2.0 * e)


static func _prominence(p: Vector2) -> float:
	var h := WorldGen.height(p.x, p.y)
	var sum := 0.0
	for k in 8:
		var a := TAU * k / 8.0
		sum += WorldGen.height(p.x + cos(a) * 70.0, p.y + sin(a) * 70.0)
	return h - sum / 8.0


## Kind-specific suitability (>= 0 valid, higher is better).
static func _score(kind: String, p: Vector2, rng: RandomNumberGenerator) -> float:
	var wood := WorldGen.woodland(p.x, p.y)
	var rd := WorldGen.road_distance(p.x, p.y)
	var h := WorldGen.height(p.x, p.y)
	match kind:
		"poi_vista":
			return _prominence(p) + h * 0.05 if h > 25.0 else -1.0
		"poi_shrine", "poi_herbs":
			return wood * 10.0 + rng.randf() if wood > 0.35 else -1.0
		"poi_hermit":
			return (wood * 6.0 + minf(rd, 600.0) * 0.01 + rng.randf()) if wood > 0.3 and rd > 200.0 else -1.0
		"poi_camp":
			return (5.0 - absf(wood - 0.45) * 6.0 - absf(rd - 120.0) * 0.01 + rng.randf()) if rd < 500.0 and rd > 40.0 else -1.0
		"poi_battlefield":
			return (5.0 - wood * 5.0 + rng.randf()) if wood < 0.25 and rd > 80.0 and slope_at(p) < 0.25 else -1.0
		"poi_cache":
			return _landmark_bonus(p) + rng.randf()
		"poi_fishing":
			var sd := WorldGen.shore_distance(p.x, p.y)
			return (10.0 - absf(sd - 7.0) + rng.randf()) if sd > 3.0 and sd < 14.0 else -1.0
		"poi_rift":
			return (rng.randf() + _rift_bonus(p)) if _rift_bonus(p) > 0.0 else -1.0
		"poi_hunter":
			return wood * 4.0 + rng.randf()
		_:
			return rng.randf() + (2.0 if _prominence(p) > 6.0 else 0.0)


static func _landmark_bonus(p: Vector2) -> float:
	var best := 0.0
	for s in _ctx:
		if String(s.get("kind", "")) in ["tower_ruin", "ruins", "standing_stones", "wayshrine", "watchfort", "old_bridge"] and p.distance_to(s["pos"]) < 420.0:
			best = maxf(best, 5.0 - p.distance_to(s["pos"]) * 0.01)
	return best


static func _rift_bonus(p: Vector2) -> float:
	var best := 0.0
	for s in _ctx:
		if String(s.get("kind", "")) == "rift":
			var d := p.distance_to(s["pos"])
			if d > 160.0 and d < 950.0:
				best = maxf(best, 3.0 - d * 0.002)
	return best


# --- Bodies (Region1Look landmarks) ------------------------------------------------------------------------------

static func _p(a: String, at: Vector2, h: float, yaw := 0.0, extra := {}) -> Dictionary:
	var d := {"a": a, "w": [at.x, at.y], "h": h, "yaw": rad_to_deg(yaw)}
	d.merge(extra, true)
	return d


static func _sc(kind: String, at: Vector2, r: float, n: int, r0 := 0.0, smin := 0.85, smax := 1.4, end := 90.0) -> Dictionary:
	return {"kind": kind, "w": [at.x, at.y], "r": r, "r0": r0, "n": n, "s": [smin, smax], "end": end}


static func _light(at: Vector2, y: float, color: String, rng_m: float) -> Dictionary:
	return {"w": [at.x, at.y], "y": y, "color": color, "range": rng_m}


## Landmark dicts for the director's Region1Look-style presenter.
static func landmarks() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for d: Dictionary in DEFS:
		if not placed.has(d["id"]):
			continue
		var pl: Dictionary = placed[d["id"]]
		out.append(_landmark(d, pl["pos"], float(pl["yaw"])))
	return out


static func _landmark(d: Dictionary, c: Vector2, yaw: float) -> Dictionary:
	var kind := String(d["kind"])
	var parts: Array = []
	var scatter: Array = []
	var lights: Array = []
	var f := Vector2(sin(yaw), cos(yaw))       # facing
	var r := Vector2(f.y, -f.x)                # right
	match kind:
		"poi_vista":
			parts.append(_p(FREE + "nature/rock_limestone_tall", c + r * 3.0, 3.2, yaw))
			parts.append(_p("res://assets/generated/props/bench.glb", c + f * 2.2, 1.0, yaw + PI, {"collide": true}))
			parts.append(_p(FREE + "nature/rocks_mossy_mushroom", c - r * 3.5 + f, 1.2, yaw + 1.0))
			scatter.append(_sc(REGION + "flowers_warm", c, 9.0, 70, 2.0))
			scatter.append(_sc(REGION + "grass_tall", c, 12.0, 60, 3.0))
		"poi_shrine":
			parts.append(_p("gen:ruins/overgrown_shrine", c, 3.0, yaw))
			parts.append(_p(FREE + "magic/runestone_verdant", c + r * 3.2 + f, 1.9, yaw + 0.5))
			parts.append(_p(FREE + "lighting/candle_stand", c + f * 2.6, 1.0, yaw))
			scatter.append(_sc(REGION + "fern_a", c, 10.0, 60, 2.0))
			scatter.append(_sc(REGION + "flowers_cool", c, 7.0, 40, 2.0))
			lights.append(_light(c + f * 2.6, 1.3, "ffb870", 7.0))
		"poi_lore":
			parts.append(_p("r1:stones/road_stone_a_slab", c, 3.0, yaw, {"collide": true}))
			for i in 3:
				var a := yaw + TAU * i / 3.0 + 0.7
				parts.append(_p(FREE + "magic/runestone_face_moss", c + Vector2(sin(a), cos(a)) * 5.0, 1.5, a + PI))
			scatter.append(_sc(REGION + "flowers_cool", c, 8.0, 50, 2.0))
			scatter.append(_sc(REGION + "fern_b", c, 12.0, 50, 4.0))
		"poi_camp":
			parts.append(_p(FREE + "camp/tent_camp_a", c, 2.6, yaw, {"collide": true}))
			parts.append(_p("gen:ruins/campfire", c + f * 3.6, 0.6, yaw))
			parts.append(_p(FREE + "props/barrels_crates_stack", c - r * 3.2 + f, 1.2, yaw + 0.6, {"collide": true}))
			parts.append(_p(FREE + "props/crate_planks", c + r * 3.0 - f, 0.7, yaw + 2.0))
			scatter.append(_sc(REGION + "fern_a", c, 11.0, 70, 3.0))
			scatter.append(_sc(REGION + "bush_hazel", c, 13.0, 18, 6.0))
		"poi_herbs":
			for i in 7:
				var a := TAU * i / 7.0
				parts.append(_p(FREE + "flora/bellflower_purple", c + Vector2(cos(a), sin(a)) * 2.6, 0.9, a))
			parts.append(_p(FREE + "flora/mushrooms_blue_glow", c + f * 1.5, 0.5, yaw))
			scatter.append(_sc(REGION + "flowers_cool", c, 8.0, 140, 0.0, 0.9, 1.5, 70.0))
			scatter.append(_sc(REGION + "fern_b", c, 10.0, 40, 3.0))
			lights.append(_light(c, 0.8, "9cc8ff", 6.0))
		"poi_cache":
			parts.append(_p(FREE + "nature/tree_old_rocks", c, 11.0, yaw, {"collide": true}))
			parts.append(_p(FREE + "props/chest_orange_wood", c + f * 2.4, 0.8, yaw + PI, {"sink": 0.3, "tilt": [8, 10]}))
			scatter.append(_sc(REGION + "bush_hazel", c, 9.0, 12, 3.0))
			scatter.append(_sc(REGION + "fern_a", c, 9.0, 40, 2.0))
		"poi_battlefield":
			for i in 5:
				var a := yaw + i * 1.3
				var at := c + Vector2(sin(a), cos(a)) * (4.0 + i * 3.0)
				parts.append(_p(FREE + "props/shield_dragon_heraldic", at, 1.0, a, {"tilt": [70, 10], "sink": 0.1}))
			parts.append(_p(FREE + "props/axe_battle_upright", c + r * 2.0, 1.3, yaw, {"tilt": [6, 14]}))
			parts.append(_p(FREE + "props/cannon_wooden", c - f * 7.0, 1.4, yaw + 0.3, {"tilt": [0, 12]}))
			parts.append(_p("nature:dead_snag", c + r * 9.0, 4.0, yaw))
			parts.append(_p("nature:dead_snag", c - r * 11.0 + f * 6.0, 3.4, yaw + 2.0))
			scatter.append(_sc(REGION + "grass_tall", c, 18.0, 100, 4.0))
		"poi_fishing":
			parts.append(_p(FREE + "flora/stump_cut", c, 0.9, yaw))
			parts.append(_p("res://assets/generated/props/basket_produce.glb", c + r * 1.1, 0.5, yaw))
			parts.append(_p("nature:log_mossy", c - r * 4.0 + f * 2.0, 1.4, yaw + 1.0))
			scatter.append(_sc(REGION + "grass_tall", c, 8.0, 50, 2.0))
		"poi_hermit":
			parts.append(_p(FREE + "camp/tent_hide_hut", c, 3.0, yaw, {"collide": true}))
			parts.append(_p("gen:ruins/campfire", c + f * 4.0, 0.6, yaw))
			parts.append(_p("res://assets/generated/props/woodpile.glb", c - r * 3.5, 1.1, yaw + 1.5))
			parts.append(_p(FREE + "lighting/lantern_post_wood", c + r * 4.0 + f * 2.0, 2.3, yaw))
			parts.append(_p(FREE + "props/barrels_crates_stack", c + r * 3.6 - f * 2.0, 1.1, yaw + 0.4))
			scatter.append(_sc(REGION + "flowers_cool", c, 12.0, 70, 3.0))
			scatter.append(_sc(REGION + "fern_a", c, 14.0, 60, 5.0))
			lights.append(_light(c + r * 4.0 + f * 2.0, 2.2, "ffb060", 9.0))
		"poi_hunter":
			parts.append(_p(FREE + "camp/tent_camp_b", c, 2.6, yaw, {"collide": true}))
			parts.append(_p("gen:ruins/campfire", c + f * 3.6, 0.6, yaw))
			parts.append(_p("res://assets/generated/props/woodpile.glb", c - r * 3.4, 1.1, yaw + 1.2))
			scatter.append(_sc(REGION + "fern_a", c, 12.0, 50, 3.0))
		"poi_rift":
			parts.append(_p(FREE + "magic/runestone_carved_red", c, 2.4, yaw))
			parts.append(_p(FREE + "magic/crystal_purple_pedestal", c + f * 3.0, 1.2, yaw))
			scatter.append(_sc(REGION + "fern_b", c, 9.0, 30, 3.0))
			lights.append(_light(c + f * 1.2, 1.4, "b07cff", 10.0))
	return {"id": "poi_" + String(d["id"]), "name": String(d["name"]), "kind": kind, "pos": [c.x, c.y], "near": 240.0, "yaw": 0.0,
		"parts": parts, "scatter": scatter, "lights": lights, "waterfalls": []}


# --- Journal and map ---------------------------------------------------------------------------------------------

## Extra fog-of-war reveal sources [[Vector2 pos, radius m]]: every found POI's own area, the vale, the map fragment.
## (world_map.gd calls this from _fog_sources; `discovery` is Life.discovery.)
static func reveal_sources(discovery: Object) -> Array:
	var out: Array = []
	if discovery == null or not discovery.has_method("secret_ids"):
		return out
	for id: String in discovery.call("secret_ids"):
		if not bool(discovery.call("is_discovered", id)):
			continue
		var pl: Dictionary = discovery.call("secret_place", id)
		var d := def(String(pl.get("poi", "")))
		var r := float(d.get("reveal", 0.0))
		if String(pl.get("poi", "")) == "hidden_vale":
			r = 420.0
		if r > 0.0:
			out.append([pl["pos"], r])
	for key: String in (discovery.get("found") as Dictionary):
		if key.begins_with("reveal:"):
			var parts := key.split(":")
			if parts.size() >= 4:
				out.append([Vector2(float(parts[1]), float(parts[2])), float(parts[3])])
	return out


## What the journal's Discoveries page shows: found ones by name (with their lore), a bare count for the rest.
## {vale: bool, found: [{name, kind, lore, day}], unfound: int, total: int}
static func journal(discovery: Object) -> Dictionary:
	var res := {"vale": false, "found": [], "unfound": 0, "total": 0}
	if discovery == null or not discovery.has_method("secret_ids"):
		return res
	for id: String in discovery.call("secret_ids"):
		res["total"] = int(res["total"]) + 1
		if not bool(discovery.call("is_discovered", id)):
			res["unfound"] = int(res["unfound"]) + 1
			continue
		var pl: Dictionary = discovery.call("secret_place", id)
		var pid := String(pl.get("poi", ""))
		if pid == "hidden_vale":
			res["vale"] = true
			(res["found"] as Array).append({"name": String(pl["name"]), "kind": "hidden_vale", "lore": HV.LORE_TEXT, "day": int(discovery.get("found")[id])})
			continue
		(res["found"] as Array).append({"name": String(pl["name"]), "kind": String(pl["kind"]), "lore": String(def(pid).get("lore", "")),
			"day": int((discovery.get("found") as Dictionary)[id])})
	(res["found"] as Array).sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if (a["kind"] == "hidden_vale") != (b["kind"] == "hidden_vale"):
			return a["kind"] == "hidden_vale"
		return int(a["day"]) > int(b["day"]))      # the vale first, then the newest finds
	return res
