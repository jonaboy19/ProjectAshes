extends RefCounted
## READY_V1 C5, the lordship milestone: when a camp you founded grows into a Village (scripts/realm/settlement_growth.gd tier_reached),
## the realm makes you its lord, once. The grant goes through sim/lordship.gd with reason "founded" under a synthetic settlement index
## (FOUNDED_BASE + the build-kit grid id), so the Steward's Post (world/lord_hall.gd), the Lord's Council (ui/lord_council.gd), taxes
## and projects all work on it like on a granted village. The title "Lord of <name>" goes to Life.titles.
##   FoundedLord.bind(Life.realm, Life.lordship, Life.titles)     once, at startup
##   FoundedLord.sync_titles(Life.lordship, Life.titles)           after a load (title definitions are not saved, the grants are)

const Lordship := preload("res://scripts/sim/lordship.gd")
const TITLE_PREFIX := "lord_of_camp_"


static func bind(hub: RefCounted, lordship: RefCounted, titles: RefCounted) -> void:
	var growth: RefCounted = hub.mod("growth")
	if growth == null:
		return
	lordship.pop_source = func(idx: int) -> int:
		return int(growth.state_of(idx - Lordship.FOUNDED_BASE).get("pop", 0))
	growth.tier_reached.connect(func(gid: int, tier: int, _n: String) -> void:
		if tier >= 2:
			on_village(hub, lordship, titles, gid))


## Grants the lordship of grid `gid` (a no-op when already held). Returns the village row, {} when the grid is gone.
static func on_village(hub: RefCounted, lordship: RefCounted, titles: RefCounted, gid: int) -> Dictionary:
	var kit: RefCounted = hub.mod("build_kit")
	if kit == null or not kit.grids.has(gid):
		return {}
	var idx := Lordship.founded_idx(gid)
	if lordship.is_lord_of(idx):
		return lordship.village(idx)
	var g: Dictionary = kit.grids[gid]
	var o: Array = g["origin"]
	var info := {"name": String(g["name"]), "pos": Vector2(float(o[0]), float(o[2])), "radius": 40.0,
		"population": int(hub.mod("growth").state_of(gid).get("pop", 0))}
	var v: Dictionary = lordship.grant(idx, "founded", info)
	grant_title(titles, gid, String(g["name"]))
	return v


static func title_id(gid: int) -> String:
	return TITLE_PREFIX + str(gid)


static func grant_title(titles: RefCounted, gid: int, camp_name: String) -> void:
	titles.add({"id": title_id(gid), "name": "Lord of %s" % camp_name, "desc": "The camp you founded grew into a village, and its people look to you.",
		"effect": {}, "grant_only": true})
	titles.grant(title_id(gid), WorldSim.day)


## Title definitions are data the save does not keep; the held founded villages say which ones to bring back.
static func sync_titles(lordship: RefCounted, titles: RefCounted) -> void:
	for idx: int in lordship.held_settlements():
		if Lordship.is_founded_idx(idx):
			var v: Dictionary = lordship.village(idx)
			titles.add({"id": title_id(idx - Lordship.FOUNDED_BASE), "name": "Lord of %s" % String(v.get("name", "the camp")),
				"desc": "The camp you founded grew into a village, and its people look to you.", "effect": {}, "grant_only": true})
