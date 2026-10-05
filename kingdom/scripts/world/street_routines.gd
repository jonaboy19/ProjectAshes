extends Node
## Daily work routine for the Ashford benchmark street (AAA pass 6, 2026-10-06). The micro-event director picks town
## vignettes by weight anywhere in town; this keeps THIS street's day legible: dawn farmers and water carriers, the morning
## delivery and sweeping, midday laundry and carts, an afternoon performer and hay wagon, farmers home at dusk, the night
## watch. Every TICK seconds, while the player is on the street and the director has room, it starts the next vignette of
## the hour (MicroEvents.spawn_now, which already respects actor budgets and its MAX_ACTIVE). Data only; no new actors.

const TICK := 22.0
const NEAR := 70.0
## [from hour, to hour, vignette ids in rotation]
const SCHEDULE := [
	[5.3, 8.0, ["farmers_out_dawn", "water_carriers"]],
	[8.0, 11.0, ["delivery_to_shops", "street_sweeper", "wood_cart"]],
	[11.0, 15.0, ["laundry_day", "cart_through", "water_carriers"]],
	[15.0, 17.5, ["street_performer", "hay_wagon", "laundry_day"]],
	[17.5, 20.5, ["farmers_return_dusk", "couple_stroll"]],
	[20.5, 29.3, ["night_watch_rounds"]],
]

var centre := Vector2.ZERO
var _micro: Node
var _acc := 0.0
var _turn := 0


static func ids_at(hour: float) -> Array:
	var h := hour if hour >= 5.3 else hour + 24.0
	for row: Array in SCHEDULE:
		if h >= float(row[0]) and h < float(row[1]):
			return row[2]
	return []


func _process(delta: float) -> void:
	_acc += delta
	if _acc < TICK:
		return
	_acc = 0.0
	var pl := get_tree().get_first_node_in_group("player") as Node3D
	if pl == null or Vector2(pl.global_position.x, pl.global_position.z).distance_to(centre) > NEAR:
		return
	if _micro == null or not is_instance_valid(_micro):
		for n in get_tree().root.find_children("*", "Node", true, false):
			if n.get("micro") != null and (n.get("micro") as Object).has_method("spawn_now"):
				_micro = n.get("micro")
				break
		if _micro == null:
			return
	if (_micro.get("active") as Array).size() >= 3:
		return
	var ids := ids_at(float(WorldSim.time_of_day))
	if ids.is_empty():
		return
	_turn += 1
	_micro.call("spawn_now", String(ids[_turn % ids.size()]))
