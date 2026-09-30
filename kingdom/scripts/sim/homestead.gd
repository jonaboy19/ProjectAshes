extends RefCounted
## A homestead the player can buy and build on: three fixed plots on free, flat
## ground outside Ashford, bought with gold, built up on a 2 m grid from a small
## catalogue of pieces, with wheat and cabbage crops that grow over a few
## in-game days. Pure data (RefCounted, serialisable); scripts/world/homestead_view.gd
## gives it a body near the player, scripts/ui/build_menu.gd lets the player edit it.
##
## Plot positions are fixed and deterministic for a given world seed (found once,
## the same way RegionSites finds its farmstead: free, dry, flat ground clear of
## roads and other sites, outside the village ring). Each plot has its own local
## grid: cell (0,0) is the plot's south-west corner; `cell_world` / `world_to_cell`
## convert between a cell and its world position.
##
## pieces: [{uid, plot, kind, cell: Vector2i, rot (0-3, quarter turns)}]
## crops:  [{uid, plot, cell: Vector2i, crop ("" = tilled but empty, else an item
##          id like "wheat"), planted_day, watered}]

const RegionSites := preload("res://scripts/world/region_sites.gd")
const ItemsDB := preload("res://scripts/sim/items_db.gd")
const SeasonsScript := preload("res://scripts/sim/seasons.gd")

const GRID := 2.0                 # metres per cell
const PLOT_CELLS := Vector2i(11, 11)
const PRICES := [150, 300, 600]

## Leasing: a tenant farmer works a landlord's plot instead of buying it. Rent
## is charged once per in-game season (Seasons.DAYS_PER_SEASON days) and the
## landlord (the village Lord) takes a share of every harvest while leased.
const LEASE_RENT := 30
const LEASE_SHARE := 0.25

## Hired hands: a daily wage, a 0..1 skill (a little extra yield) and 0..1
## loyalty (unused for now, room for events later). Unpaid HANDS_QUIT_DAYS in
## a row and they quit.
const HAND_WAGE_MIN := 4
const HAND_WAGE_MAX := 9
const HANDS_QUIT_DAYS := 3
const HANDS_BASE_CAP := 5
## Extra hands allowed per estate level above smallholding (0/1/2).
const HANDS_PER_LEVEL := 4

## Estate level thresholds: {level -> {plots, workers, granary, mill_or_orchard}}.
## 0 smallholding, 1 farm, 2 estate. A requirement of 0/false is always met.
const ESTATE_LEVELS := [
	{"plots": 0, "workers": 0, "granary": false, "grown": false},
	{"plots": 1, "workers": 2, "granary": false, "grown": false},
	{"plots": 2, "workers": 4, "granary": true, "grown": true},
]
const ESTATE_NAMES := ["Smallholding", "Farm", "Estate"]

## Storage: a shared farmstead granary (not the player's Inventory) that the
## player's hired hands fill from the fields and livestock, sold in bulk via
## sell_storage() or fulfilling a bulk contract quest.
const STORAGE_CAP_BASE := 60
const STORAGE_CAP_PER_GRANARY := 80

## Livestock daily yield (deterministic, seeded per plot/day so saves replay
## the same rolls): a coop gives an egg most days, a sty pork every few.
const EGG_CHANCE := 0.85
const PORK_PERIOD := 4

## piece id -> {name, gold, mats: {item: count}, footprint: Vector2i (cells, unrotated), asset}
## asset "" means no mesh (crop_plot: tilled ground, shown by homestead_view without a model).
const CATALOG := {
	"cottage": {"name": "Cottage", "gold": 200, "mats": {"plank": 20, "iron_ingot": 4}, "footprint": Vector2i(4, 4), "asset": "building:mhouse_peasant_a"},
	"barn": {"name": "Barn", "gold": 140, "mats": {"plank": 16}, "footprint": Vector2i(3, 3), "asset": "farm/barn"},
	"fence": {"name": "Fence rail", "gold": 4, "mats": {"plank": 2}, "footprint": Vector2i(1, 1), "asset": "farm/fence_rail"},
	"gate": {"name": "Fence gate", "gold": 10, "mats": {"plank": 3, "iron_ingot": 1}, "footprint": Vector2i(1, 1), "asset": "farm/fence_gate"},
	"crop_plot": {"name": "Crop plot", "gold": 8, "mats": {}, "footprint": Vector2i(1, 1), "asset": ""},
	"chicken_coop": {"name": "Chicken coop", "gold": 60, "mats": {"plank": 8}, "footprint": Vector2i(2, 2), "asset": "farm/chicken_coop"},
	"pig_sty": {"name": "Pig sty", "gold": 60, "mats": {"plank": 8}, "footprint": Vector2i(2, 2), "asset": "farm/pig_sty"},
	"granary": {"name": "Granary", "gold": 220, "mats": {"plank": 24, "iron_ingot": 2}, "footprint": Vector2i(2, 2), "asset": "farm/granary"},
	"mill": {"name": "Mill", "gold": 260, "mats": {"plank": 20, "iron_ingot": 6}, "footprint": Vector2i(2, 2), "asset": "farm/windmill"},
	"orchard": {"name": "Orchard tree", "gold": 45, "mats": {}, "footprint": Vector2i(1, 1), "asset": ""},
	"well": {"name": "Well", "gold": 40, "mats": {"iron_ingot": 1}, "footprint": Vector2i(1, 1), "asset": "props/well"},
	"woodpile": {"name": "Woodpile", "gold": 15, "mats": {}, "footprint": Vector2i(1, 1), "asset": "props/woodpile"},
	"lamp_post": {"name": "Lamp post", "gold": 20, "mats": {"iron_ingot": 1}, "footprint": Vector2i(1, 1), "asset": "props/lamp_post"},
	"bench": {"name": "Bench", "gold": 10, "mats": {"plank": 2}, "footprint": Vector2i(1, 1), "asset": "props/bench"},
}

## crop item id -> {days (to grow, or with watering), asset,
##   seasons: Seasons.SPRING/.../WINTER indices this can be *planted* in
##   (omitted or empty = any season, keeps wheat/cabbage exactly as before),
##   winter_hardy: true survives a frost roll in winter (turnips)}.
## Real choices: grain (wheat, barley), a hardy root (turnips), veg (cabbage),
## flax for cloth, hops for ale.
const BASE_CROPS := {
	"wheat": {"days": 4, "asset": "farm/crop_wheat"},
	"cabbage": {"days": 5, "asset": "farm/crop_cabbage"},
	"barley": {"days": 4, "asset": "farm/crop_wheat", "seasons": [SeasonsScript.SPRING, SeasonsScript.SUMMER]},
	"turnip": {"days": 4, "asset": "farm/crop_cabbage", "seasons": [SeasonsScript.SPRING, SeasonsScript.SUMMER, SeasonsScript.AUTUMN, SeasonsScript.WINTER], "winter_hardy": true},
	"flax": {"days": 5, "asset": "", "seasons": [SeasonsScript.SPRING, SeasonsScript.SUMMER]},
	"hops": {"days": 6, "asset": "", "seasons": [SeasonsScript.SUMMER]},
}

## BASE_CROPS plus every crop of the Region 1 item set (data/items/crops.json: carrots, onions, peas, pumpkins, herbs ...).
static var CROPS: Dictionary = _merged_crops()


static func _merged_crops() -> Dictionary:
	var out: Dictionary = BASE_CROPS.duplicate(true)
	var extra: Dictionary = ItemsDB.crops()
	for crop: String in extra:
		if out.has(crop):
			continue
		var d: Dictionary = extra[crop]
		var seasons: Array = []
		for sname: String in d.get("seasons", []):
			seasons.append({"SPRING": SeasonsScript.SPRING, "SUMMER": SeasonsScript.SUMMER, "AUTUMN": SeasonsScript.AUTUMN, "WINTER": SeasonsScript.WINTER}.get(sname, SeasonsScript.SPRING))
		var e := {"days": int(d.get("days", 4)), "asset": String(d.get("asset", ""))}
		if not seasons.is_empty():
			e["seasons"] = seasons
		if bool(d.get("winter_hardy", false)):
			e["winter_hardy"] = true
		out[crop] = e
	return out


## Watering speeds growth (a quarter off the total, at least a day).
const WATERED_MULT := 0.75
## Weeding adds a little to the harvest, the same way watering does.
const WEEDED_BONUS := 1

var owned: Dictionary = {}              # plot index -> true
## plot index -> {since_day, last_rent_day}. A leased plot is not owned; the
## landlord (the village Lord) is paid rent each season and takes a share of
## every harvest. leased and owned are mutually exclusive.
var leased: Dictionary = {}
var pieces: Array[Dictionary] = []
var crops: Array[Dictionary] = []
## {uid, plot, name, wage, skill (0..1), unpaid_days}.
var workers: Array[Dictionary] = []
## item id -> count, the farmstead's own granary (separate from Life's Inventory).
var storage: Dictionary = {}

var _plots_cache: Array[Dictionary] = []
var _soil_cache: Dictionary = {}        # plot index -> float 0.6..1.2
var _next_uid := 1
var _next_worker_uid := 1


# --- plots -----------------------------------------------------------------------

## The three plots, found once on free ground outside Ashford (WorldGen.settlements[0])
## and cached for the life of this object. Empty before WorldGen has set up the world.
func plots() -> Array[Dictionary]:
	if not _plots_cache.is_empty():
		return _plots_cache
	if WorldGen.settlements.is_empty():
		return []
	var home: Dictionary = WorldGen.settlements[0]
	var c: Vector2 = home["pos"]
	var min_r: float = float(home["radius"]) * 1.3
	var rng := RandomNumberGenerator.new()
	rng.seed = WorldSim.SEED + 5150
	var taken: Array[Dictionary] = WorldGen.sites.duplicate()
	var plot_r := 16.0   # covers an 11x11 cell (22x22 m) plot's half-diagonal
	for i in PRICES.size():
		var best := Vector2.INF
		var best_score := INF
		var dist := min_r + 24.0 + float(i) * 34.0
		for a_i in 48:
			var a := TAU * a_i / 48.0 + rng.randf() * 0.05 + float(i) * 1.7
			var p := c + Vector2(cos(a), sin(a)) * dist
			if not RegionSites._free(p, plot_r, taken, 8.0):
				continue
			var score := RegionSites._slope(p) * 10.0 + rng.randf() * 0.3
			if score < best_score:
				best_score = score
				best = p
		if best == Vector2.INF:
			best = c + Vector2(cos(float(i) * 2.1), sin(float(i) * 2.1)) * (dist + 20.0)
		var face := (c - best).normalized()
		var plot := {"id": i, "pos": best, "yaw": RegionSites._yaw_to(face), "price": PRICES[i], "cells": PLOT_CELLS}
		_plots_cache.append(plot)
		taken.append({"pos": best, "clear": plot_r})
	return _plots_cache


func plot_name(plot: int) -> String:
	return "Homestead Plot %d" % (plot + 1)


## The plot index whose bounds contain a world position, or -1.
func plot_at(world: Vector2) -> int:
	for i in plots().size():
		if _cell_in_bounds(i, world_to_cell(i, world)):
			return i
	return -1


func is_owned(plot: int) -> bool:
	return bool(owned.get(plot, false))


## A leased plot (tenant farmer): not owned, rent due each season, a share of
## every harvest goes to the landlord.
func is_leased(plot: int) -> bool:
	return leased.has(plot)


## Owned or leased: the flag can_place() and most farm actions actually care about.
func owns_or_leases(plot: int) -> bool:
	return is_owned(plot) or is_leased(plot)


## Deterministic soil quality for a plot, 0.6 (poor) .. 1.2 (rich), seeded from
## the world seed so it's the same every session without needing to be saved.
func soil_quality(plot: int) -> float:
	if _soil_cache.has(plot):
		return _soil_cache[plot]
	var rng := RandomNumberGenerator.new()
	rng.seed = WorldSim.SEED + 90210 + plot * 733
	var q := rng.randf_range(0.6, 1.2)
	_soil_cache[plot] = q
	return q


func can_buy(plot: int) -> String:
	if plot < 0 or plot >= plots().size():
		return "No such plot."
	if is_owned(plot):
		return "You already own this plot."
	if is_leased(plot):
		return "You lease this plot; end the lease before buying it."
	return ""


func buy(plot: int) -> String:
	var why := can_buy(plot)
	if why != "":
		return why
	var price := int(plots()[plot]["price"])
	if Game.gold < price:
		return "Needs %d gold (have %d)." % [price, Game.gold]
	Game.add_gold(-price)
	owned[plot] = true
	return "You now own %s (%d gold)." % [plot_name(plot), price]


func can_lease(plot: int) -> String:
	if plot < 0 or plot >= plots().size():
		return "No such plot."
	if is_owned(plot):
		return "You already own this plot."
	if is_leased(plot):
		return "You already lease this plot."
	return ""


## Leases a plot from its landlord: no purchase price, but rent (LEASE_RENT
## gold) falls due every season and the landlord keeps LEASE_SHARE of every
## harvest. Backward compatible: `owned` is untouched, so old saves with no
## `leased` key still deserialize fine.
func lease(plot: int) -> String:
	var why := can_lease(plot)
	if why != "":
		return why
	leased[plot] = {"since_day": WorldSim.day, "last_rent_day": WorldSim.day}
	return "You now lease %s. Rent is %d gold every season." % [plot_name(plot), LEASE_RENT]


## Gives the plot back to the landlord (no refund; simply stops rent and the
## harvest share, and can_place stops working there until leased/bought again).
func end_lease(plot: int) -> String:
	if not is_leased(plot):
		return "You don't lease this plot."
	leased.erase(plot)
	return "You give up the lease on %s." % plot_name(plot)


# --- grid geometry -----------------------------------------------------------------

static func _rotate(v: Vector2, yaw: float) -> Vector2:
	return Vector2(v.x * cos(yaw) + v.y * sin(yaw), -v.x * sin(yaw) + v.y * cos(yaw))


static func _unrotate(v: Vector2, yaw: float) -> Vector2:
	return _rotate(v, -yaw)


## Local offset (unrotated, plot-relative) of a cell's centre.
func cell_local(plot: int, cell: Vector2i) -> Vector2:
	var cells: Vector2i = plots()[plot]["cells"]
	return Vector2((cell.x - cells.x / 2.0 + 0.5) * GRID, (cell.y - cells.y / 2.0 + 0.5) * GRID)


func cell_world(plot: int, cell: Vector2i) -> Vector2:
	var p: Dictionary = plots()[plot]
	return (p["pos"] as Vector2) + _rotate(cell_local(plot, cell), float(p["yaw"]))


func world_to_cell(plot: int, world: Vector2) -> Vector2i:
	var p: Dictionary = plots()[plot]
	var local := _unrotate(world - (p["pos"] as Vector2), float(p["yaw"]))
	var cells: Vector2i = p["cells"]
	return Vector2i(int(floor(local.x / GRID + cells.x / 2.0)), int(floor(local.y / GRID + cells.y / 2.0)))


func _cell_in_bounds(plot: int, cell: Vector2i) -> bool:
	var cells: Vector2i = plots()[plot]["cells"]
	return cell.x >= 0 and cell.y >= 0 and cell.x < cells.x and cell.y < cells.y


## Cells a piece occupies at `cell` with a quarter-turn rotation (footprint swaps
## width/depth on an odd rotation).
func footprint_cells(kind: String, cell: Vector2i, rot: int) -> Array[Vector2i]:
	var fp: Vector2i = (CATALOG.get(kind, {}).get("footprint", Vector2i.ONE))
	if rot % 2 == 1:
		fp = Vector2i(fp.y, fp.x)
	var out: Array[Vector2i] = []
	for dx in fp.x:
		for dy in fp.y:
			out.append(cell + Vector2i(dx, dy))
	return out


func in_bounds(plot: int, cells: Array[Vector2i]) -> bool:
	for c in cells:
		if not _cell_in_bounds(plot, c):
			return false
	return true


## Cells already occupied by a piece or a crop plot on `plot` (optionally
## ignoring one piece uid, e.g. while checking whether it could rotate in place).
func occupied_cells(plot: int, ignore_uid := -1) -> Dictionary:
	var occ := {}
	for pc: Dictionary in pieces:
		if int(pc["plot"]) != plot or int(pc["uid"]) == ignore_uid:
			continue
		for c in footprint_cells(String(pc["kind"]), pc["cell"], int(pc["rot"])):
			occ[c] = true
	for cr: Dictionary in crops:
		if int(cr["plot"]) == plot:
			occ[cr["cell"]] = true
	return occ


func overlaps(plot: int, cells: Array[Vector2i], ignore_uid := -1) -> bool:
	var occ := occupied_cells(plot, ignore_uid)
	for c in cells:
		if occ.has(c):
			return true
	return false


# --- building ------------------------------------------------------------------

func can_afford(kind: String) -> String:
	if not CATALOG.has(kind):
		return "Unknown piece."
	var c: Dictionary = CATALOG[kind]
	if Game.gold < int(c.get("gold", 0)):
		return "Needs %d gold." % int(c["gold"])
	for item: String in (c.get("mats", {}) as Dictionary):
		var need := int(c["mats"][item])
		if Life.count(item) < need:
			return "Needs %d %s (have %d)." % [need, Life.item_name(item), Life.count(item)]
	return ""


func can_place(plot: int, kind: String, cell: Vector2i, rot: int) -> String:
	if not owns_or_leases(plot):
		return "You don't own or lease this plot."
	if not CATALOG.has(kind):
		return "Unknown piece."
	var cells := footprint_cells(kind, cell, rot)
	if not in_bounds(plot, cells):
		return "Outside the plot."
	if overlaps(plot, cells):
		return "Something is already there."
	return ""


## Places `kind` at `cell`, paying its cost. crop_plot goes into `crops` (tilled,
## unplanted); everything else goes into `pieces`. Returns "" on success.
func place(plot: int, kind: String, cell: Vector2i, rot := 0) -> String:
	var why := can_place(plot, kind, cell, rot)
	if why != "":
		return why
	var afford := can_afford(kind)
	if afford != "":
		return afford
	var c: Dictionary = CATALOG[kind]
	Game.add_gold(-int(c.get("gold", 0)))
	for item: String in (c.get("mats", {}) as Dictionary):
		Life.take(item, int(c["mats"][item]))
	var uid := _next_uid
	_next_uid += 1
	if kind == "crop_plot":
		crops.append({"uid": uid, "plot": plot, "cell": cell, "crop": "", "planted_day": -1, "watered": false, "weeded": false})
	elif kind == "orchard":
		pieces.append({"uid": uid, "plot": plot, "kind": kind, "cell": cell, "rot": rot, "planted_day": WorldSim.day})
	else:
		pieces.append({"uid": uid, "plot": plot, "kind": kind, "cell": cell, "rot": rot})
	return ""


## Removes whatever piece or crop plot occupies `cell` on `plot`. "" on success.
func remove_at(plot: int, cell: Vector2i) -> String:
	for i in range(pieces.size() - 1, -1, -1):
		var pc: Dictionary = pieces[i]
		if int(pc["plot"]) == plot and footprint_cells(String(pc["kind"]), pc["cell"], int(pc["rot"])).has(cell):
			pieces.remove_at(i)
			return ""
	for i in range(crops.size() - 1, -1, -1):
		var cr: Dictionary = crops[i]
		if int(cr["plot"]) == plot and (cr["cell"] as Vector2i) == cell:
			crops.remove_at(i)
			return ""
	return "Nothing there."


func piece_at(plot: int, cell: Vector2i) -> Dictionary:
	for pc: Dictionary in pieces:
		if int(pc["plot"]) == plot and footprint_cells(String(pc["kind"]), pc["cell"], int(pc["rot"])).has(cell):
			return pc
	return {}


func crop_at(plot: int, cell: Vector2i) -> Dictionary:
	for cr: Dictionary in crops:
		if int(cr["plot"]) == plot and (cr["cell"] as Vector2i) == cell:
			return cr
	return {}


# --- crops -----------------------------------------------------------------------

## Seasons the crop can be planted in this calendar day (all four when the
## crop declares no "seasons" list, so wheat/cabbage are unrestricted as before).
func can_plant_now(crop: String) -> bool:
	if not CROPS.has(crop):
		return false
	var seasons: Array = CROPS[crop].get("seasons", [])
	if seasons.is_empty():
		return true
	var cal_day: int = WorldSim.seasons.current_day() if WorldSim.seasons else int(WorldSim.day)
	return seasons.has(SeasonsScript.season_of(cal_day))


func plant(plot: int, cell: Vector2i, crop: String) -> String:
	if not CROPS.has(crop):
		return "You can't grow that."
	var cr := crop_at(plot, cell)
	if cr.is_empty():
		return "There's no tilled plot there."
	if String(cr.get("crop", "")) != "":
		return "Already planted."
	if not can_plant_now(crop):
		return "%s can't be planted this season." % Life.item_name(crop)
	cr["crop"] = crop
	cr["planted_day"] = WorldSim.day
	cr["watered"] = false
	cr["weeded"] = false
	return ""


func water(plot: int, cell: Vector2i) -> String:
	var cr := crop_at(plot, cell)
	if cr.is_empty() or String(cr.get("crop", "")) == "":
		return "Nothing planted there."
	if bool(cr.get("watered", false)):
		return "Already watered."
	cr["watered"] = true
	return ""


func weed(plot: int, cell: Vector2i) -> String:
	var cr := crop_at(plot, cell)
	if cr.is_empty() or String(cr.get("crop", "")) == "":
		return "Nothing planted there."
	if bool(cr.get("weeded", false)):
		return "Already weeded."
	cr["weeded"] = true
	return ""


## Days needed to finish growing (fewer once watered).
func grow_days(cr: Dictionary) -> float:
	var crop := String(cr.get("crop", ""))
	if crop == "" or not CROPS.has(crop):
		return 0.0
	var days := float(CROPS[crop]["days"])
	return maxf(1.0, days * (WATERED_MULT if bool(cr.get("watered", false)) else 1.0))


## 0 (just planted) .. 1 (ready to harvest); 0 if nothing is planted.
func growth_stage(cr: Dictionary) -> float:
	var crop := String(cr.get("crop", ""))
	if crop == "":
		return 0.0
	var need := grow_days(cr)
	if need <= 0.0:
		return 1.0
	var elapsed := float(WorldSim.day - int(cr.get("planted_day", WorldSim.day)))
	return clampf(elapsed / need, 0.0, 1.0)


func is_ready(cr: Dictionary) -> bool:
	return String(cr.get("crop", "")) != "" and growth_stage(cr) >= 1.0


## Harvests a ready crop plot: gives its item (base 2-4, plus watering/weeding,
## scaled by the plot's soil quality), tills the plot again (""). A leased
## plot's landlord takes LEASE_SHARE of the harvest first.
func harvest(plot: int, cell: Vector2i) -> String:
	var cr := crop_at(plot, cell)
	if cr.is_empty() or String(cr.get("crop", "")) == "":
		return "Nothing planted there."
	if not is_ready(cr):
		return "Not ready yet."
	var crop := String(cr["crop"])
	var base := 2 + (1 if bool(cr.get("watered", false)) else 0) + (WEEDED_BONUS if bool(cr.get("weeded", false)) else 0) \
		+ (hash([plot, cell, WorldSim.day]) % 2)
	var n := maxi(1, int(round(float(base) * soil_quality(plot))))
	var landlord_share := 0
	if is_leased(plot):
		landlord_share = mini(n - 1, int(floor(float(n) * LEASE_SHARE)))
		n -= landlord_share
	Life.give(crop, n)
	cr["crop"] = ""
	cr["planted_day"] = -1
	cr["watered"] = false
	cr["weeded"] = false
	if landlord_share > 0:
		return "Harvested %d %s (the landlord took %d)." % [n, Life.item_name(crop), landlord_share]
	return "Harvested %d %s." % [n, Life.item_name(crop)]


# --- hired hands -------------------------------------------------------------------

## Extra hands allowed once the estate has grown (HANDS_BASE_CAP, then more
## per estate level: smallholding 5, farm 9, estate 13).
func max_workers() -> int:
	return HANDS_BASE_CAP + estate_level() * HANDS_PER_LEVEL


func can_hire(plot: int) -> String:
	if not owns_or_leases(plot):
		return "You don't own or lease this plot."
	if workers.size() >= max_workers():
		return "You can't manage more than %d hands yet." % max_workers()
	return ""


## Hires a hand at `plot` for a daily wage (clamped to the usual range if unset).
func hire(plot: int, name: String, wage := -1, skill := 0.5) -> String:
	var why := can_hire(plot)
	if why != "":
		return why
	var w := clampi(wage, HAND_WAGE_MIN, HAND_WAGE_MAX) if wage >= 0 else HAND_WAGE_MIN
	var uid := _next_worker_uid
	_next_worker_uid += 1
	workers.append({"uid": uid, "plot": plot, "name": name, "wage": w, "skill": clampf(skill, 0.0, 1.0), "unpaid_days": 0})
	return "%s joins your farm for %d gold a day." % [name, w]


func fire(uid: int) -> String:
	for i in workers.size():
		if int(workers[i]["uid"]) == uid:
			var name := String(workers[i]["name"])
			workers.remove_at(i)
			return "%s leaves your service." % name
	return "No such hand."


func workers_on(plot: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for w: Dictionary in workers:
		if int(w["plot"]) == plot:
			out.append(w)
	return out


# --- storage, buildings, estate level -----------------------------------------------

func granary_count(plot := -1) -> int:
	var n := 0
	for pc: Dictionary in pieces:
		if String(pc["kind"]) == "granary" and (plot < 0 or int(pc["plot"]) == plot):
			n += 1
	return n


func has_piece(kind: String, plot := -1) -> bool:
	for pc: Dictionary in pieces:
		if String(pc["kind"]) == kind and (plot < 0 or int(pc["plot"]) == plot):
			return true
	return false


func storage_cap() -> int:
	return STORAGE_CAP_BASE + granary_count() * STORAGE_CAP_PER_GRANARY


func storage_used() -> int:
	var n := 0
	for item: String in storage:
		n += int(storage[item])
	return n


## Adds `n` of `item` to the shared farm storage, clamped to storage_cap();
## returns how much actually fit.
func add_storage(item: String, n: int) -> int:
	if n <= 0:
		return 0
	var room := maxi(0, storage_cap() - storage_used())
	var put := mini(n, room)
	if put > 0:
		storage[item] = int(storage.get(item, 0)) + put
	return put


## Sells up to `amount` of `item` from farm storage at the village market
## (Life.market.sell, the same price curve player sales use). {sold, gold}.
func sell_storage(item: String, amount: int) -> Dictionary:
	var sold := 0
	var gold := 0
	while sold < amount and int(storage.get(item, 0)) > 0:
		var got := Life.market.sell(item)
		if got < 0:
			break
		storage[item] = int(storage[item]) - 1
		gold += got
		sold += 1
	if gold > 0:
		Game.add_gold(gold)
	return {"sold": sold, "gold": gold}


## The number of plots the player currently works, owned or leased.
func worked_plot_count() -> int:
	var n := 0
	for i in plots().size():
		if owns_or_leases(i):
			n += 1
	return n


## 0 smallholding, 1 farm, 2 estate — from plots worked, hands employed and
## whether a granary and a mill or orchard have been built. Monotonic: once
## the level's requirements are met at any point they stay met until the
## player sells off plots or lets hands go.
func estate_level() -> int:
	var plots_n := worked_plot_count()
	var workers_n := workers.size()
	var has_granary := has_piece("granary")
	var has_grown := has_piece("mill") or has_piece("orchard")
	var level := 0
	for i in range(ESTATE_LEVELS.size() - 1, -1, -1):
		var req: Dictionary = ESTATE_LEVELS[i]
		if plots_n >= int(req["plots"]) and workers_n >= int(req["workers"]) \
				and (not bool(req["granary"]) or has_granary) and (not bool(req["grown"]) or has_grown):
			level = i
			break
	return level


func estate_level_name() -> String:
	return ESTATE_NAMES[estate_level()]


# --- the daily tick -----------------------------------------------------------------

## Called once a day (life.gd's midnight tick — see the hook this task adds).
## Charges lease rent, pays and works hired hands, rolls crop failure, and
## collects livestock and mill produce into storage. Returns messages worth
## telling the player.
func daily_tick(day: int) -> Array[String]:
	var out: Array[String] = []
	out.append_array(_tick_rent(day))
	out.append_array(_tick_workers(day))
	_tick_crop_failure(day)
	_tick_livestock(day)
	_tick_mill(day)
	return out


func _tick_rent(day: int) -> Array[String]:
	var out: Array[String] = []
	for plot: int in leased.keys().duplicate():
		var info: Dictionary = leased[plot]
		if day - int(info["last_rent_day"]) < SeasonsScript.DAYS_PER_SEASON:
			continue
		info["last_rent_day"] = day
		if Game.gold >= LEASE_RENT:
			Game.add_gold(-LEASE_RENT)
			out.append("Paid %d gold rent on %s." % [LEASE_RENT, plot_name(plot)])
		else:
			leased.erase(plot)
			out.append("Unable to pay rent: the landlord takes back %s." % plot_name(plot))
	return out


## Each hand waters, weeds and harvests (into storage) on their plot, then
## gets paid; unpaid HANDS_QUIT_DAYS running and they quit. A little chance to
## slack the day after going unpaid.
func _tick_workers(day: int) -> Array[String]:
	var out: Array[String] = []
	for i in range(workers.size() - 1, -1, -1):
		var w: Dictionary = workers[i]
		var plot := int(w["plot"])
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([int(w["uid"]), day])
		var slacking := int(w.get("unpaid_days", 0)) > 0 and rng.randf() < 0.5
		if not slacking and owns_or_leases(plot):
			_work_plot(plot, float(w.get("skill", 0.5)))
		if Game.gold >= int(w["wage"]):
			Game.add_gold(-int(w["wage"]))
			w["unpaid_days"] = 0
		else:
			w["unpaid_days"] = int(w.get("unpaid_days", 0)) + 1
			if int(w["unpaid_days"]) >= HANDS_QUIT_DAYS:
				out.append("%s quits, unpaid too long." % String(w["name"]))
				workers.remove_at(i)
				continue
		workers[i] = w
	return out


## One hand's daily round on a plot: water and weed whatever needs it, harvest
## whatever is ready into farm storage (not the player's own Inventory).
func _work_plot(plot: int, skill: float) -> void:
	for cr: Dictionary in crops:
		if int(cr["plot"]) != plot or String(cr.get("crop", "")) == "":
			continue
		if not bool(cr.get("watered", false)):
			cr["watered"] = true
		elif not bool(cr.get("weeded", false)):
			cr["weeded"] = true
		if is_ready(cr):
			var crop := String(cr["crop"])
			var base := 2 + 1 + WEEDED_BONUS + int(round(skill * 2.0))
			var n := maxi(1, int(round(float(base) * soil_quality(plot))))
			if is_leased(plot):
				n -= mini(n - 1, int(floor(float(n) * LEASE_SHARE)))
			add_storage(crop, n)
			cr["crop"] = ""
			cr["planted_day"] = -1
			cr["watered"] = false
			cr["weeded"] = false


## A small seeded chance a growing crop is lost to frost (near winter, or any
## non winter-hardy crop caught out when winter starts) or drought (unwatered
## in summer). Deterministic per plot/cell/day so a save replays identically.
func _tick_crop_failure(day: int) -> void:
	var cal_day: int = WorldSim.seasons.current_day() if WorldSim.seasons else day
	var season := SeasonsScript.season_of(cal_day)
	for cr: Dictionary in crops:
		if String(cr.get("crop", "")) == "":
			continue
		var crop := String(cr["crop"])
		var hardy := bool(CROPS.get(crop, {}).get("winter_hardy", false))
		var risk := 0.0
		if season == SeasonsScript.WINTER and not hardy:
			risk = 0.35
		elif season == SeasonsScript.SUMMER and not bool(cr.get("watered", false)):
			risk = 0.06
		if risk <= 0.0:
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([int(cr["plot"]), (cr["cell"] as Vector2i).x, (cr["cell"] as Vector2i).y, day, 4242])
		if rng.randf() < risk:
			cr["crop"] = ""
			cr["planted_day"] = -1
			cr["watered"] = false
			cr["weeded"] = false


## Coops and sties on worked plots feed the farm storage every day.
func _tick_livestock(day: int) -> void:
	for pc: Dictionary in pieces:
		var plot := int(pc["plot"])
		if not owns_or_leases(plot):
			continue
		var kind := String(pc["kind"])
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([int(pc["uid"]), day, 771])
		if kind == "chicken_coop" and rng.randf() < EGG_CHANCE:
			add_storage("egg", 1 + int(rng.randf() < 0.3))
		elif kind == "pig_sty" and day % PORK_PERIOD == 0:
			add_storage("pork", 1)
		elif kind == "orchard" and day - int(pc.get("planted_day", day)) >= 10:
			add_storage("apple", 1)


## A mill turns stored wheat into flour, a little at a time, worth more at market.
func _tick_mill(_day: int) -> void:
	if not has_piece("mill"):
		return
	var have := int(storage.get("wheat", 0))
	var grind := mini(have, 4)
	if grind <= 0:
		return
	storage["wheat"] = have - grind
	add_storage("flour", grind)


# --- save / load -----------------------------------------------------------------

func serialize() -> Dictionary:
	var po := {}
	for k in owned:
		po[str(int(k))] = true
	var lo := {}
	for k in leased:
		var info: Dictionary = leased[k]
		lo[str(int(k))] = {"since_day": int(info["since_day"]), "last_rent_day": int(info["last_rent_day"])}
	var pieces_out: Array = []
	for pc: Dictionary in pieces:
		var po_entry := {"uid": int(pc["uid"]), "plot": int(pc["plot"]), "kind": String(pc["kind"]),
			"cell": [(pc["cell"] as Vector2i).x, (pc["cell"] as Vector2i).y], "rot": int(pc["rot"])}
		if pc.has("planted_day"):
			po_entry["planted_day"] = int(pc["planted_day"])
		pieces_out.append(po_entry)
	var crops_out: Array = []
	for cr: Dictionary in crops:
		crops_out.append({"uid": int(cr["uid"]), "plot": int(cr["plot"]),
			"cell": [(cr["cell"] as Vector2i).x, (cr["cell"] as Vector2i).y], "crop": String(cr.get("crop", "")),
			"planted_day": int(cr.get("planted_day", -1)), "watered": bool(cr.get("watered", false)),
			"weeded": bool(cr.get("weeded", false))})
	var workers_out: Array = []
	for w: Dictionary in workers:
		workers_out.append({"uid": int(w["uid"]), "plot": int(w["plot"]), "name": String(w["name"]),
			"wage": int(w["wage"]), "skill": float(w["skill"]), "unpaid_days": int(w.get("unpaid_days", 0))})
	return {"owned": po, "leased": lo, "pieces": pieces_out, "crops": crops_out, "workers": workers_out,
		"storage": storage.duplicate(), "next_uid": _next_uid, "next_worker_uid": _next_worker_uid}


func deserialize(d: Dictionary) -> void:
	owned.clear()
	for k in (d.get("owned", {}) as Dictionary):
		owned[int(k)] = true
	leased.clear()
	for k: String in (d.get("leased", {}) as Dictionary):
		var info: Dictionary = d["leased"][k]
		leased[int(k)] = {"since_day": int(info.get("since_day", 0)), "last_rent_day": int(info.get("last_rent_day", 0))}
	pieces.clear()
	for p: Dictionary in d.get("pieces", []):
		var cell: Array = p["cell"]
		var entry := {"uid": int(p.get("uid", 0)), "plot": int(p["plot"]), "kind": String(p["kind"]),
			"cell": Vector2i(int(cell[0]), int(cell[1])), "rot": int(p.get("rot", 0))}
		if p.has("planted_day"):
			entry["planted_day"] = int(p["planted_day"])
		pieces.append(entry)
	crops.clear()
	for c: Dictionary in d.get("crops", []):
		var cell2: Array = c["cell"]
		crops.append({"uid": int(c.get("uid", 0)), "plot": int(c["plot"]), "cell": Vector2i(int(cell2[0]), int(cell2[1])),
			"crop": String(c.get("crop", "")), "planted_day": int(c.get("planted_day", -1)), "watered": bool(c.get("watered", false)),
			"weeded": bool(c.get("weeded", false))})
	workers.clear()
	for w: Dictionary in d.get("workers", []):
		workers.append({"uid": int(w.get("uid", 0)), "plot": int(w["plot"]), "name": String(w.get("name", "Hand")),
			"wage": int(w.get("wage", HAND_WAGE_MIN)), "skill": float(w.get("skill", 0.5)), "unpaid_days": int(w.get("unpaid_days", 0))})
	storage.clear()
	for item: String in (d.get("storage", {}) as Dictionary):
		storage[item] = int(d["storage"][item])
	_next_uid = maxi(int(d.get("next_uid", 1)), _max_uid_seen() + 1)
	_next_worker_uid = maxi(int(d.get("next_worker_uid", 1)), _max_worker_uid_seen() + 1)


func _max_uid_seen() -> int:
	var m := 0
	for pc: Dictionary in pieces:
		m = maxi(m, int(pc["uid"]))
	for cr: Dictionary in crops:
		m = maxi(m, int(cr["uid"]))
	return m


func _max_worker_uid_seen() -> int:
	var m := 0
	for w: Dictionary in workers:
		m = maxi(m, int(w["uid"]))
	return m
