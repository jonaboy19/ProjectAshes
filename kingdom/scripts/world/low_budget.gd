extends RefCounted
## LOW-tier budget for the decorative world content the cloud session added (Meshy batch 3 yards, the fill pass, the Thornfield wilds
## extras, the re-rigged Meshy villager looks). Phone audit 2026-10-06: LOW over budget on draws and triangles, and most of these Meshy
## models cannot be decimated by the engine (unique flat-shaded vertices: no generated LOD) while their LOD0 is 2-15k tris. A 2 m
## picket fence section is 2.5-3k tris, a yard has 8-15 of them.
##
## Rules (all of them only when `low()` and only for decorative content, never for doors, colliders, clues, quest props or lights):
##   proxy      Meshy fence pieces become the Style G generated rail / picket fence (60-190 tris), scaled to the same length and height.
##   thin       heavy loose clutter with no LOD1 (bouquets, banners, kegs, hay, bushes...) keeps 1 of every N pieces per site.
##   lod        LOD0 -> LOD1 switch at half the distance (kit pieces), LOD1 (when it exists) for the wilds extras and the re-rigged
##              Meshy characters (7.0k -> 2.9k tris, 1024 -> 512 px texture).
##   extras     wilds extras that are heavy, small and have no LOD1 are left out (stalls, carts' tables...).
## `model_tris.json` (tools: the audit in docs/LOCAL_SESSION_HANDOFF.md) lists [lod0 tris, lod1 tris] per referenced Meshy model, so tests
## and budgets work on data alone. Preload; no class_name.

const FillStyle := preload("res://scripts/world/fill_style.gd")
const TRIS_FILE := "res://data/region1/world/model_tris.json"
const REGION := "res://assets/generated/region/"

## Meshy fence model -> [generated piece, length in metres of one section]. Nothing else is substituted (walls with colliders stay).
const FENCE_PROXY := {
	"fences/fence_picket_tall": ["farm/fence_picket", 2.0], "fences/fence_picket_low": ["farm/fence_picket", 2.0],
	"fences/fence_plank_panel": ["farm/fence_picket", 2.0], "fences/fence_palisade": ["farm/fence_picket", 2.0],
	"fences/fence_rail_grass_a": ["farm/fence_rail", 1.98], "fences/fence_rail_grass_b": ["farm/fence_rail", 1.98],
}
## Loose decorative clutter without a LOD1: keep 1 piece in N (per site, in list order). Everything here is 1.8-4k tris.
const THIN := {
	"flora/bouquet_wild": 4, "flora/bush_raspberry": 2, "banners/banner_stand_iron_frame": 2, "banners/banner_gold_finials": 2,
	"farm/hay_bale_round": 2, "farm/hay_bale_rect_a": 2, "dl3/props/keg_big": 3, "castle/wall_battlement_block": 3,
	"dl3/furniture/table_bench_set": 2,
}
## A wilds extra with no LOD1 and more than this many tris, shorter than SMALL_M, is left out on LOW.
const EXTRA_MAX_TRIS := 3000
const SMALL_M := 3.0
## Test hook: -1 follow `enabled` + Quality, 0 force off, 1 force on.
static var force_low := -1
## OFF by default (owner, 2026-10-06): "don't do anything that ruins the quality" - none of these cuts may change what the player sees.
## Phone performance is the local PC session's job and is reached by quality-neutral means (real LODs, merging, baking, culling).
## Kept only as an opt-in switch for that work.
static var enabled := false
static var _tris: Dictionary = {}


static func low() -> bool:
	if force_low >= 0:
		return force_low == 1
	return enabled and int(Quality.tier) <= Quality.LOW


static func tris_table() -> Dictionary:
	if _tris.is_empty():
		var f := FileAccess.open(TRIS_FILE, FileAccess.READ)
		if f != null:
			var d: Variant = JSON.parse_string(f.get_as_text())
			if d is Dictionary:
				_tris = d
	return _tris


## [lod0 tris, lod1 tris] of a model key ("dl3/props/keg_big" or "fences/fence_picket_low"); [0, 0] when unknown.
static func model_tris(model: String) -> Array:
	var v: Variant = tris_table().get(model, [0, 0])
	return v if v is Array else [0, 0]


## The generated stand-in for a Meshy fence piece: {"path": generated asset, "length": m}, {} when the asset is not a proxied fence or
## the tier is not LOW. `asset` is a part key ("free:fences/fence_picket_low@0.76").
static func proxy_for(asset: String) -> Dictionary:
	if not low():
		return {}
	var m := FillStyle.model_of(asset)
	if not FENCE_PROXY.has(m):
		return {}
	var p: Array = FENCE_PROXY[m]
	return {"path": String(p[0]), "length": float(p[1])}


## True when part `part` of a fill / Meshy3 `site` is left out on LOW (thinned clutter). Parts with a collider are never left out.
static func skip_part(site: Dictionary, part: Array) -> bool:
	if not low() or not bool(site.get("fill", false)) or (part.size() > 3 and int(part[3]) != 0):
		return false
	var m := FillStyle.model_of(String(part[0]))
	var n: int = int(THIN.get(m, 0))
	if n <= 1:
		return false
	var seen := 0
	for q: Array in site.get("parts", []):
		if q == part:
			break
		if FillStyle.model_of(String(q[0])) == m and (q.size() <= 3 or int(q[3]) == 0):
			seen += 1
	return seen % n != 0


## Distance at which a kit piece swaps LOD0 for LOD1: half on LOW.
static func lod_distance(dist: float) -> float:
	return dist * 0.5 if low() else dist


## 1 when a "dl3/..." model should use its LOD1 (LOW and the file exists), else 0.
static func dl3_lod(model: String) -> int:
	if low() and model_tris(model)[1] > 0:
		return 1
	return 0


## True when a wilds extra is not worth its triangles on LOW (see EXTRA_MAX_TRIS).
static func skip_extra(model: String, height: float) -> bool:
	if not low():
		return false
	var t := model_tris(model)
	return int(t[1]) == 0 and int(t[0]) > EXTRA_MAX_TRIS and height > 0.0 and height < SMALL_M


## Gear list of a camp / outpost squad: no shield attachments on LOW (each is 4 surfaces = 4 draws per fighter, ~650 tris, purely visual).
static func gear(keep: Array[String]) -> Array[String]:
	if not low():
		return keep
	var out: Array[String] = []
	for k: String in keep:
		if not k.contains("Shield"):
			out.append(k)
	return out


## Estimated LOW triangles of a site's parts (LOD0, what the baked mesh draws while the site is in range) for budgets and tests:
## fence pieces count as their proxy, thinned and skipped parts as nothing. `lowtier` false gives the all-tiers figure.
static func site_tris(site: Dictionary, lowtier: bool) -> int:
	var prev := force_low
	force_low = 1 if lowtier else 0
	var total := 0
	for part: Array in site.get("parts", []):
		var asset := String(part[0])
		if skip_part(site, part):
			continue
		var px := proxy_for(asset)
		if not px.is_empty():
			total += 192 if String(px["path"]).ends_with("picket") else 72
			continue
		total += int(model_tris(FillStyle.model_of(asset))[0])
	force_low = prev
	return total
