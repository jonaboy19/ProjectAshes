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
var doors: Array = []                 # door points (Vector2) for the work sounds
## Street sound layer (AAA pass 7): a positional murmur of voices by day, work one-shots (hammer, well bucket, rope
## creak of a cart) from the doors, birds by day and owls at night. Existing CC0 sounds only (assets/audio/ambience).
const DIR := "res://assets/audio/ambience/"
var _murmur: AudioStreamPlayer3D
var _one: AudioStreamPlayer3D
var _sfx_acc := 0.0
var _sfx_next := 6.0
var _micro: Node
var _acc := 0.0
var _turn := 0


static func ids_at(hour: float) -> Array:
	var h := hour if hour >= 5.3 else hour + 24.0
	for row: Array in SCHEDULE:
		if h >= float(row[0]) and h < float(row[1]):
			return row[2]
	return []


func _ready() -> void:
	_murmur = AudioStreamPlayer3D.new()
	_murmur.stream = load(DIR + "amb_tavern.ogg")      # voices and mugs: far, low-passed it reads as a street murmur
	_murmur.unit_size = 9.0
	_murmur.max_distance = 45.0
	_murmur.attenuation_filter_cutoff_hz = 2400.0
	_murmur.volume_db = -60.0
	_murmur.bus = &"Ambience" if AudioServer.get_bus_index("Ambience") >= 0 else &"Master"
	add_child(_murmur)
	_one = AudioStreamPlayer3D.new()
	_one.unit_size = 6.0
	_one.max_distance = 40.0
	_one.bus = _murmur.bus
	add_child(_one)


func _sound(delta: float, here: Vector2) -> void:
	var h := float(WorldSim.time_of_day)
	var day := h >= 7.0 and h < 19.5
	_murmur.global_position = Vector3(centre.x, WorldGen.height(centre.x, centre.y) + 1.6, centre.y)
	var want := -14.0 if day and here.distance_to(centre) < NEAR else -60.0
	_murmur.volume_db = move_toward(_murmur.volume_db, want, 12.0 * delta)
	if _murmur.volume_db > -55.0 and not _murmur.playing:
		_murmur.play(randf() * 20.0)
	elif _murmur.volume_db <= -59.0 and _murmur.playing:
		_murmur.stop()
	_sfx_acc += delta
	if _sfx_acc < _sfx_next or doors.is_empty() or here.distance_to(centre) > NEAR:
		return
	_sfx_acc = 0.0
	_sfx_next = randf_range(4.0, 11.0)
	var pick: String
	if day:
		pick = ["spots/hammer_distant_0%d.ogg" % randi_range(1, 3), "spots/well_bucket_0%d.ogg" % randi_range(1, 3),
			"spots/rope_creak.ogg", "spots/bird_blackbird.ogg", "spots/mug_knock_0%d.ogg" % randi_range(1, 2)].pick_random()
	else:
		pick = ["spots/owl_0%d.ogg" % randi_range(1, 3), "spots/dog_distant_0%d.ogg" % randi_range(1, 3)].pick_random()
	if not ResourceLoader.exists(DIR + pick):
		return
	var dp: Vector2 = doors.pick_random()
	_one.stream = load(DIR + pick)
	_one.volume_db = randf_range(-12.0, -6.0)
	_one.pitch_scale = randf_range(0.94, 1.06)
	_one.global_position = Vector3(dp.x, WorldGen.height(dp.x, dp.y) + 1.5, dp.y)
	_one.play()


func _process(delta: float) -> void:
	var plr := get_tree().get_first_node_in_group("player") as Node3D
	if plr != null:
		_sound(delta, Vector2(plr.global_position.x, plr.global_position.z))
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
