extends RefCounted
## Region 1 fill sites: small unnamed roadside clusters (filler houses, farm sheds, market-street stalls, wells, outskirt
## fences) placed beside settlements and Region 1 places so the meshy_free pack's unused models stand in the world
## (docs/qa/ASSET_AUDIT.md section A, "use the unused models"). Preload; no class_name.
##
## Data: data/region1/world/fill_sites.json, same spec format as sites.json (search block, parts, lights) with kind "roadside"
## (Discovery never lists those, RegionDressing bakes clusters of 12+ parts into a few merged meshes).
## Planned LAST in RegionSites.plan, after every other planner, so no existing site id or position moves.

const R1World := preload("res://scripts/world/region1_world.gd")
const FillStyle := preload("res://scripts/world/fill_style.gd")
## Meshy batch 3 yards ("dl3:" models: town houses, wagons, tents, horses, a garrison keep), same spec format as fill_sites.json.
const MESHY3_FILE := "meshy3_sites.json"


static func sites(_seed_value: int, out: Array[Dictionary]) -> Array[Dictionary]:
	var res: Array[Dictionary] = []
	if OS.get_cmdline_user_args().has("--r1worldoff") or OS.get_cmdline_user_args().has("--r1filloff"):
		return res
	var all: Array[Dictionary] = []
	all.append_array(out)
	var raws: Array = R1World.data("fill_sites.json").get("sites", []).duplicate()
	if not OS.get_cmdline_user_args().has("--meshy3off"):         # QA A/B for the Meshy batch 3 yards
		raws.append_array(R1World.data(MESHY3_FILE).get("sites", []))
	for raw: Dictionary in raws:
		var spec := _expand(raw)
		var site: Dictionary = R1World._place(spec, all)
		if site.is_empty():
			site = R1World._place(spec, all, true)
		if site.is_empty():
			continue
		site["fill"] = true
		site["fill_id"] = site["r1id"]
		site.erase("r1id")          # not a canon site: the Region 1 tests and lookups key on r1id
		res.append(site)
		all.append(site)
	return res


## Placement notes: parts are yaw-only (RegionDressing never tilts a part, so structures stay upright on slopes) and settle on
## the lowest ground sampled over the footprint (RegionDressing._footprint_ground: corners, edge midpoints and centre).
## search.outside [a, b] (settlement centres): metres beyond the settlement's wall ring, the same inner distance the
## settlement landmarks use (radius * 1.15 + clear + 4).
static func _expand(raw: Dictionary) -> Dictionary:
	var sr: Dictionary = raw["search"]
	var spec := raw.duplicate(true)
	# Style G pass: models that stay off-style after treatment (FillStyle.DROPPED) are never placed, even if a data edit lists them.
	var kept: Array = []
	for part: Array in spec.get("parts", []):
		if not FillStyle.is_dropped(FillStyle.model_of(String(part[0]))):
			kept.append(part)
	spec["parts"] = kept
	if not sr.has("outside"):
		return spec
	var s: Dictionary = R1World._settlement_named(String(sr["center"]).trim_prefix("settlement:"))
	if s.is_empty():
		return spec
	var base := float(s["radius"]) * 1.15 + float(raw["clear"]) + 4.0
	var o: Array = sr["outside"]
	(spec["search"] as Dictionary)["d"] = [base + float(o[0]), base + float(o[1])]
	return spec
