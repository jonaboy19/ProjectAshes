extends RefCounted
## Where land may be claimed for a player settlement (docs/design/RETINUE_SETTLEMENT_ASCENSION.md 4.1 "Where claiming is allowed").
## Pure static rules over WorldGen, so the claim flow (C16) and build mode ask the same question:
##   LandClaim.block_reason(Vector2(x, z)) -> "" when the ground may be claimed, else the words the player sees.
## Implemented now: distance from settlements (350 m villages, 600 m towns and the capital, which also keeps the Crown's
## ring free), water, and the road centreline. Not yet (need modules that do not exist): Scar cells, monster dens, owner
## stones, Crownstead, the legal ladder (charter, ward claim); see HOOKS_FOR_CLOUD.md "Cloud status (2026-10-06)".

const VILLAGE_GAP := 350.0
const TOWN_GAP := 600.0
const ROAD_GAP := 6.0
const BIG_KINDS := ["town", "castle", "capital", "frontier_town"]


static func gap_for(kind: String) -> float:
	return TOWN_GAP if kind in BIG_KINDS else VILLAGE_GAP


static func block_reason(p: Vector2) -> String:
	if WorldGen.is_water(p.x, p.y):
		return "You cannot claim land in the water."
	for s: Dictionary in WorldGen.settlements:
		var gap := gap_for(String(s.get("kind", "village")))
		if p.distance_to(s["pos"]) < gap:
			return "Too close to %s. Claim land at least %d m from a settlement." % [String(s["name"]), int(gap)]
	if WorldGen.road_distance(p.x, p.y) < ROAD_GAP:
		return "Not on the road. Step %d m aside to claim this ground." % int(ROAD_GAP)
	return ""
