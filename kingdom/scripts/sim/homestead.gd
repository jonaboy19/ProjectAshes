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

const GRID := 2.0                 # metres per cell
const PLOT_CELLS := Vector2i(11, 11)
const PRICES := [150, 300, 600]

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
	"well": {"name": "Well", "gold": 40, "mats": {"iron_ingot": 1}, "footprint": Vector2i(1, 1), "asset": "props/well"},
	"woodpile": {"name": "Woodpile", "gold": 15, "mats": {}, "footprint": Vector2i(1, 1), "asset": "props/woodpile"},
	"lamp_post": {"name": "Lamp post", "gold": 20, "mats": {"iron_ingot": 1}, "footprint": Vector2i(1, 1), "asset": "props/lamp_post"},
	"bench": {"name": "Bench", "gold": 10, "mats": {"plank": 2}, "footprint": Vector2i(1, 1), "asset": "props/bench"},
}

## crop item id -> {days (to grow, or with watering), asset}.
const CROPS := {
	"wheat": {"days": 4, "asset": "farm/crop_wheat"},
	"cabbage": {"days": 5, "asset": "farm/crop_cabbage"},
}
## Watering speeds growth (a quarter off the total, at least a day).
const WATERED_MULT := 0.75

var owned: Dictionary = {}              # plot index -> true
var pieces: Array[Dictionary] = []
var crops: Array[Dictionary] = []

var _plots_cache: Array[Dictionary] = []
var _next_uid := 1


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


func can_buy(plot: int) -> String:
	if plot < 0 or plot >= plots().size():
		return "No such plot."
	if is_owned(plot):
		return "You already own this plot."
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
	if not is_owned(plot):
		return "You don't own this plot."
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
		crops.append({"uid": uid, "plot": plot, "cell": cell, "crop": "", "planted_day": -1, "watered": false})
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

func plant(plot: int, cell: Vector2i, crop: String) -> String:
	if not CROPS.has(crop):
		return "You can't grow that."
	var cr := crop_at(plot, cell)
	if cr.is_empty():
		return "There's no tilled plot there."
	if String(cr.get("crop", "")) != "":
		return "Already planted."
	cr["crop"] = crop
	cr["planted_day"] = WorldSim.day
	cr["watered"] = false
	return ""


func water(plot: int, cell: Vector2i) -> String:
	var cr := crop_at(plot, cell)
	if cr.is_empty() or String(cr.get("crop", "")) == "":
		return "Nothing planted there."
	if bool(cr.get("watered", false)):
		return "Already watered."
	cr["watered"] = true
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


## Harvests a ready crop plot: gives 2-4 of its item, tills the plot again ("").
func harvest(plot: int, cell: Vector2i) -> String:
	var cr := crop_at(plot, cell)
	if cr.is_empty() or String(cr.get("crop", "")) == "":
		return "Nothing planted there."
	if not is_ready(cr):
		return "Not ready yet."
	var crop := String(cr["crop"])
	var n := 2 + (1 if bool(cr.get("watered", false)) else 0) + (hash([plot, cell, WorldSim.day]) % 2)
	Life.give(crop, n)
	cr["crop"] = ""
	cr["planted_day"] = -1
	cr["watered"] = false
	return "Harvested %d %s." % [n, Life.item_name(crop)]


# --- save / load -----------------------------------------------------------------

func serialize() -> Dictionary:
	var po := {}
	for k in owned:
		po[str(int(k))] = true
	var pieces_out: Array = []
	for pc: Dictionary in pieces:
		pieces_out.append({"uid": int(pc["uid"]), "plot": int(pc["plot"]), "kind": String(pc["kind"]),
			"cell": [(pc["cell"] as Vector2i).x, (pc["cell"] as Vector2i).y], "rot": int(pc["rot"])})
	var crops_out: Array = []
	for cr: Dictionary in crops:
		crops_out.append({"uid": int(cr["uid"]), "plot": int(cr["plot"]),
			"cell": [(cr["cell"] as Vector2i).x, (cr["cell"] as Vector2i).y], "crop": String(cr.get("crop", "")),
			"planted_day": int(cr.get("planted_day", -1)), "watered": bool(cr.get("watered", false))})
	return {"owned": po, "pieces": pieces_out, "crops": crops_out, "next_uid": _next_uid}


func deserialize(d: Dictionary) -> void:
	owned.clear()
	for k in (d.get("owned", {}) as Dictionary):
		owned[int(k)] = true
	pieces.clear()
	for p: Dictionary in d.get("pieces", []):
		var cell: Array = p["cell"]
		pieces.append({"uid": int(p.get("uid", 0)), "plot": int(p["plot"]), "kind": String(p["kind"]),
			"cell": Vector2i(int(cell[0]), int(cell[1])), "rot": int(p.get("rot", 0))})
	crops.clear()
	for c: Dictionary in d.get("crops", []):
		var cell2: Array = c["cell"]
		crops.append({"uid": int(c.get("uid", 0)), "plot": int(c["plot"]), "cell": Vector2i(int(cell2[0]), int(cell2[1])),
			"crop": String(c.get("crop", "")), "planted_day": int(c.get("planted_day", -1)), "watered": bool(c.get("watered", false))})
	_next_uid = maxi(int(d.get("next_uid", 1)), _max_uid_seen() + 1)


func _max_uid_seen() -> int:
	var m := 0
	for pc: Dictionary in pieces:
		m = maxi(m, int(pc["uid"]))
	for cr: Dictionary in crops:
		m = maxi(m, int(cr["uid"]))
	return m
