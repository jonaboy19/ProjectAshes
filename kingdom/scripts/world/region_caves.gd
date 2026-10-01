extends RefCounted
## Caves, mines, hideouts, warrens and crypts across the 12 x 12 km region.
##
## TWO JOBS in one file (no class_name):
##  1. `RegionCavesScript.plan(seed, taken)` (static): the site entries appended at the very end of
##     RegionSites.plan on their own RNG stream, so every existing site id keeps its place. One call in
##     region_sites.gd: `out.append_array(preload("res://scripts/world/region_caves.gd").plan(seed_value, out))`.
##  2. The runtime (cave mouths, doors, hidden-entrance reveals) lives in region_caves_view.gd, which must stay
##     out of this file: WorldGen.setup preloads this planner, and the view pulls in InteriorDoor and Life.
##
## Site entry = the usual RegionSites dictionary plus:
##   dungeon: true, hidden: bool, cave: {dungeon_id, seed, theme, tier, rooms, reveal, lead, name, rumour}
## Hidden sites are skipped by Discovery.build (kind "hidden_cave", `hidden` true) and added on reveal.


const WATERFALL_AT := Vector2(-146.2, -915.5)
const WATERFALL_DIR := Vector2(0.235, -0.972)

## name, theme, hidden, reveal, distance band from Kingsreach (m), spawn rule
const SPECS := [
	["Hollin Falls Grotto", "flooded", true, "waterfall", Vector2(0, 0), "falls"],
	["Bramblewick Burrow", "cave", false, "", Vector2(350, 900), "hill"],
	["Foxlantern Cave", "cave", true, "vines", Vector2(500, 1300), "hill"],
	["Mereside Hollows", "flooded", false, "", Vector2(500, 1700), "water"],
	["Kestrel's Folly", "mine", false, "", Vector2(800, 1600), "hill"],
	["Ashen Hand Hideout", "hideout", false, "", Vector2(700, 1500), "road"],
	["Stonehollow Barrow", "crypt", true, "rockfall", Vector2(900, 1900), "hill"],
	["Ratfang Tunnels", "warren", false, "", Vector2(1000, 2100), "hill"],
	["Thornroot Den", "cave", true, "vines", Vector2(1300, 2300), "hill"],
	["The Weeping Crypt", "crypt", false, "", Vector2(1400, 2500), "ruin"],
	["Blackthorn Hideout", "hideout", false, "", Vector2(1800, 2900), "road"],
	["Deepvein Workings", "mine", true, "rockfall", Vector2(2200, 3300), "hill"],
	["Riftglass Cavern", "crystal", false, "", Vector2(0, 0), "rift1"],
	["Scarlight Grotto", "crystal", true, "night", Vector2(0, 0), "rift2"],
	["Skullpick Undercroft", "warren", false, "", Vector2(2600, 3700), "hill"],
	["The Sunken Vault", "crypt", true, "night", Vector2(3000, 4300), "hill"],
	["Gloamreach Cavern", "cave", false, "", Vector2(3200, 4700), "hill"],
	["Moonwell Hollow", "flooded", true, "night", Vector2(1600, 2800), "water"],
	# The 12 x 12 km world (2.25x the area): twenty-two more, deeper out (bands from Kingsreach reach 6.8 km).
	["Hollowfang Barrow", "crypt", true, "rockfall", Vector2(3400, 5200), "hill"],
	["Greywater Caverns", "cave", false, "", Vector2(2400, 3800), "hill"],
	["Ironroot Workings", "mine", false, "", Vector2(3000, 4600), "hill"],
	["Mudtooth Tunnels", "warren", false, "", Vector2(3600, 5400), "hill"],
	["Lantern Hollow", "flooded", true, "night", Vector2(2800, 4400), "water"],
	["The Drowned Chapel", "crypt", false, "", Vector2(2000, 3400), "ruin"],
	["Cragmouth Hideout", "hideout", false, "", Vector2(2600, 4200), "road"],
	["Shrike's Nest", "cave", true, "vines", Vector2(3800, 5600), "hill"],
	["Coldseam Delve", "mine", true, "rockfall", Vector2(3800, 5600), "hill"],
	["Wyrmbone Cavern", "cave", false, "", Vector2(4200, 6200), "hill"],
	["Ashfall Undercroft", "crypt", true, "night", Vector2(4200, 6200), "ruin"],
	["Black Rill Grotto", "flooded", false, "", Vector2(3000, 5000), "water"],
	["Gallows Hideout", "hideout", false, "", Vector2(3500, 5500), "road"],
	["Fenwick Burrows", "warren", false, "", Vector2(1800, 3200), "hill"],
	["The Sleeping Barrow", "crypt", true, "rockfall", Vector2(2600, 4200), "hill"],
	["Hushwater Hollows", "flooded", false, "", Vector2(4000, 6000), "water"],
	["Redtusk Mine", "mine", false, "", Vector2(4500, 6500), "hill"],
	["Stonewatch Cave", "cave", false, "", Vector2(1900, 3300), "hill"],
	["Moth-Eaten Crypt", "crypt", false, "", Vector2(4800, 6800), "ruin"],
	["Owlgrave Warren", "warren", false, "", Vector2(4400, 6400), "hill"],
	["Silverthread Vein", "mine", true, "vines", Vector2(3200, 5000), "hill"],
	["Thistle Gap Hideout", "hideout", false, "", Vector2(2200, 3800), "road"],
]
## visible dungeon index -> hidden dungeon index it points at (a journal inside carries the lead)
const LEADS := {1: 2, 3: 0, 4: 11, 5: 6, 7: 8, 9: 15, 12: 13, 10: 17, 19: 18, 20: 26, 23: 28, 24: 32, 27: 25, 29: 22, 31: 38}
const KIND_OF := {"cave": "cave", "flooded": "cave", "crystal": "cave", "mine": "old_mine", "hideout": "hideout", "warren": "warren_tunnels", "crypt": "crypt"}
const CAVE_KINDS := ["cave", "old_mine", "hideout", "warren_tunnels", "crypt", "hidden_cave"]
const RUMOURS := {
	"waterfall": "A herdsman swears the falls at Hollin hide a dry ledge behind the water, and a door in the rock.",
	"vines": "Children say a fox led them to a cave you can only see if you cut back the ivy.",
	"rockfall": "The old quarrymen sealed a gallery with a rockfall and never said why. A pick would clear it.",
	"night": "Travellers on the far roads talk of violet light seeping from a rock face after dark.",
}

static func tier_for(p: Vector2) -> int:
	var capital := Vector2.ZERO
	for s in WorldGen.settlements:
		if s["kind"] == "castle":
			capital = s["pos"]
	var d := p.distance_to(capital)
	return 1 if d < 1000.0 else (2 if d < 2000.0 else (3 if d < 3000.0 else 4))


# =============================================================================================
# planning

static func plan(seed_value: int, taken: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 61 + 23
	var capital := Vector2.ZERO
	for s in WorldGen.settlements:
		if s["kind"] == "castle":
			capital = s["pos"]
	var rifts: Array[Vector2] = []
	var ruins: Array[Vector2] = []
	for t in taken:
		if t["kind"] == "rift":
			rifts.append(t["pos"])
		elif t["kind"] in ["tower_ruin", "ruined_shrine"]:
			ruins.append(t["pos"])
	var all_taken: Array[Dictionary] = taken.duplicate()
	for i in SPECS.size():
		var sp: Array = SPECS[i]
		var pos := _find(sp, rng, capital, rifts, ruins, all_taken)
		if pos == Vector2.INF:
			continue
		var site := _make(i, sp, pos, seed_value)
		out.append(site)
		all_taken.append(site)
	# leads: a journal inside one dungeon points at a hidden place elsewhere
	var by_index := {}
	for s in out:
		by_index[int(s["cave"]["index"])] = s
	for vis: int in LEADS:
		var hid: int = LEADS[vis]
		if by_index.has(vis) and by_index.has(hid):
			by_index[vis]["cave"]["lead"] = by_index[hid]["cave"]["dungeon_id"]
	return out


static func _make(i: int, sp: Array, pos: Vector2, seed_value: int) -> Dictionary:
	var theme: String = sp[1]
	var hidden: bool = sp[2]
	var reveal: String = sp[3]
	var down := _downhill(pos)
	var yaw := atan2(down.x, down.y)
	if String(sp[5]) == "falls":
		yaw = atan2(-WATERFALL_DIR.x, -WATERFALL_DIR.y)
	var did := "cv%02d" % i
	var tier := tier_for(pos)
	var site := {"name": String(sp[0]), "kind": "hidden_cave" if hidden else String(KIND_OF[theme]), "pos": pos, "yaw": yaw,
		"clear": 9.0, "flatten": false, "parts": [], "lights": [], "dungeon": true, "hidden": hidden}
	site["cave"] = {"dungeon_id": did, "index": i, "seed": seed_value * 131 + i * 7919, "theme": theme, "tier": tier,
		"rooms": 0, "reveal": reveal, "lead": "", "name": String(sp[0]), "hidden": hidden,
		"rumour": String(RUMOURS.get(reveal, ""))}
	# set-dressing through the normal site parts (rocks) so the place exists even before the node builds its mouth
	if not hidden:
		if theme == "mine":
			site["parts"].append(["mine/mine_entrance", Vector2.ZERO, 0.0, true])
			site["parts"].append(["mine/mine_cart", Vector2(3.5, 5.0), 0.3, false])
			site["parts"].append(["mine/ore_pile_iron", Vector2(-4.0, 5.5), 0.5, false])
			site["lights"].append([Vector3(0, 2.2, 1.5), Color(1.0, 0.65, 0.35), 7.0, true])
		elif theme == "hideout":
			site["parts"].append(["ruins/bandit_lean_to", Vector2(6.0, 6.0), -0.4, true])
			site["parts"].append(["ruins/campfire", Vector2(-3.0, 6.0), 0.0, false])
			site["lights"].append([Vector3(-3, 1.4, 6.0), Color(1.0, 0.6, 0.3), 8.0, true])
		elif theme == "warren":
			site["parts"].append(["ruins/goblin_totem_a", Vector2(-3.5, 4.0), 0.3, true])
		site["parts"].append(["nature:boulder_large", Vector2(-6.5, -1.0), 0.8, true])
		site["parts"].append(["nature:rock_cluster", Vector2(6.0, -1.5), 2.1, false])
	return site


## A spot matching the spec's rule, or Vector2.INF.
static func _find(sp: Array, rng: RandomNumberGenerator, capital: Vector2, rifts: Array[Vector2], ruins: Array[Vector2], taken: Array[Dictionary]) -> Vector2:
	var rule: String = sp[5]
	if rule == "falls":
		var side := Vector2(-WATERFALL_DIR.y, WATERFALL_DIR.x)
		return WATERFALL_AT + WATERFALL_DIR * 3.2 + side * 2.2
	var band: Vector2 = sp[4]
	var lim := WorldGen.WORLD_HALF - 360.0
	var best := Vector2.INF
	var best_score := -INF
	var found := 0
	for i in 700:
		var q := Vector2.ZERO
		match rule:
			"rift1", "rift2":
				if rifts.is_empty():
					continue
				var rc: Vector2 = rifts[0] if rule == "rift1" else rifts[rifts.size() - 1]
				q = rc + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(160.0, 520.0)
			"ruin":
				if ruins.is_empty():
					continue
				var rr: Vector2 = ruins[rng.randi() % ruins.size()]
				q = rr + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(60.0, 260.0)
			_:
				q = capital + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(band.x, band.y)
		if absf(q.x) > lim or absf(q.y) > lim:
			continue
		var sl := _slope(q)
		var score := 0.0
		match rule:
			"hill", "rift1", "rift2", "ruin":
				if sl < 0.22 or sl > 0.55:       # steeper than this and the cave mouth hangs off the slope (world lint, seed 2024)
					continue
				score = minf(sl, 0.5) * 3.0 - WorldGen.forest_density(q.x, q.y) * 1.2
			"water":
				if sl > 0.5 or WorldGen.is_water(q.x, q.y) or WorldGen.near_water(q.x, q.y, 8.0) or not WorldGen.near_water(q.x, q.y, 60.0):
					continue
				score = 1.0 - WorldGen.shore_distance(q.x, q.y) / 60.0
			"road":
				var rd := WorldGen.road_distance(q.x, q.y)
				if rd < 45.0 or rd > 260.0 or sl > 0.4 or WorldGen.forest_density(q.x, q.y) < 0.3:
					continue
				score = WorldGen.forest_density(q.x, q.y) - rd / 400.0
		if not _spot_ok(q, 14.0, taken, rule != "water"):
			continue
		score += rng.randf() * 0.5
		found += 1
		if score > best_score:
			best_score = score
			best = q
		if found >= 10:
			break
	return best


static func _spot_ok(p: Vector2, r: float, taken: Array[Dictionary], dry: bool) -> bool:
	if absf(p.x) > WorldGen.WORLD_HALF - 300.0 or absf(p.y) > WorldGen.WORLD_HALF - 300.0:
		return false
	if dry and WorldGen.near_water(p.x, p.y, r + 4.0):
		return false
	if WorldGen.is_water(p.x, p.y) or WorldGen.road_distance(p.x, p.y) < r + 6.0:
		return false
	for s in WorldGen.settlements:
		if p.distance_to(s["pos"]) < float(s["radius"]) * 1.15 + r + 40.0:
			return false
	for g in WorldGen.camp_grounds:
		if p.distance_to(g["pos"]) < float(g["radius"]) * 1.6 + r:
			return false
	for t in taken:
		var reach := maxf(float(t["clear"]), 12.0) + 10.0
		if p.distance_to(t["pos"]) < r + reach:
			return false
	return true


static func _slope(p: Vector2) -> float:
	var e := 3.0
	var dx := WorldGen.height(p.x + e, p.y) - WorldGen.height(p.x - e, p.y)
	var dz := WorldGen.height(p.x, p.y + e) - WorldGen.height(p.x, p.y - e)
	return Vector2(dx, dz).length() / (2.0 * e)


static func _downhill(p: Vector2) -> Vector2:
	var e := 4.0
	var gr := Vector2(WorldGen.height(p.x + e, p.y) - WorldGen.height(p.x - e, p.y),
		WorldGen.height(p.x, p.y + e) - WorldGen.height(p.x, p.y - e))
	return -gr.normalized() if gr.length() > 0.001 else Vector2(0, 1)


static func cave_sites() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s in WorldGen.sites:
		if s.has("cave"):
			out.append(s)
	return out


static func site_for(dungeon_id: String) -> Dictionary:
	for s in WorldGen.sites:
		if s.has("cave") and String(s["cave"]["dungeon_id"]) == dungeon_id:
			return s
	return {}
