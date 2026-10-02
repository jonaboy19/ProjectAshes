extends RefCounted
## Validated observation payload. This module never reads live army state.
## The host must establish witness legitimacy and deliver it at the correct hour.
static func build(army_id: int, faction: String, source: String, position: Vector2,
		observed_hour: int, receipt_hour: int, retention_hours: int,
		minimum: int, maximum: int) -> Dictionary:
	if army_id <= 0 or faction.is_empty() or faction == "player" or faction.length() > 96:
		return {}
	if source.is_empty() or source.length() > 96 or not position.is_finite():
		return {}
	if observed_hour < 0 or receipt_hour < observed_hour or receipt_hour - observed_hour > retention_hours:
		return {}
	if minimum < 0 or maximum < minimum or maximum > 1000000:
		return {}
	return {"key": "a%d" % army_id, "army_id": army_id, "unit_id": 0,
		"faction": faction, "x": position.x, "y": position.y, "hour": observed_hour,
		"received_hour": receipt_hour, "min": minimum, "max": maximum, "exact": false,
		"comp": {}, "comp_hour": -1, "mounted": false, "source": source, "terrain": "unknown"}
