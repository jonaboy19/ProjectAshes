extends Node
## Player sitting on the living world's SmartObjects (WP-01, blueprint §3 "sit"): benches, tavern tables, desks... that the NPCs
## use (scripts/living_world/smart_objects.gd, NpcWorld.smart). Once a second the slots with a "seat" within RANGE of the player
## get a Seat interactable (scripts/interaction/kinds/seat.gd, no visual: the furniture is already there) at the slot's root
## transform; slots out of range lose theirs. While the player sits the slot is claimed for PLAYER_ID so no villager sits in
## the same place, and an occupied slot offers nothing. Owned by main.gd next to the player (attach(player)).

const NpcWorld := preload("res://scripts/population/npc_world.gd")
const SeatK := preload("res://scripts/interaction/kinds/seat.gd")
const RANGE := 14.0
const PLAYER_ID := -7         ## SmartObjects person id used for the player's claims
const TICK := 1.0

var player: Node3D
var _seats := {}              # "spot:slot" -> Seat
var _t := 0.0


static func attach(p: Node3D) -> Node:
	var n: Node = (load("res://scripts/interaction/player_seats.gd") as GDScript).new()
	n.name = "PlayerSeats"
	n.set("player", p)
	p.add_child(n)
	return n


func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0 or player == null or not is_instance_valid(player):
		return
	_t = TICK
	refresh()


## Pure: the seated slots of a SmartObjects type ([slot index, seat height]).
static func seat_slots(type_def: Dictionary) -> Array:
	var out: Array = []
	var slots: Array = type_def.get("slots", [])
	for i in slots.size():
		var sl: Dictionary = slots[i]
		if sl.has("seat"):
			out.append([i, float(sl["seat"])])
	return out


func refresh() -> void:
	var so: Variant = NpcWorld.smart
	if so == null:
		return
	var p := player.global_position
	var want := {}
	for spot: int in _near(so, p):
		var sp: Dictionary = so.spots[spot]
		var td: Dictionary = so.types.get(sp["type"], {})
		for e: Array in seat_slots(td):
			var key := "%d:%d" % [spot, int(e[0])]
			want[key] = true
			if _seats.has(key) and is_instance_valid(_seats[key]):
				continue
			var xf: Transform3D = so.stand_xform(spot, int(e[0]))
			var kind := "bench" if String(sp["type"]).contains("bench") else "chair"
			# the slot's root is laid out for the pelvis SEAT_REF behind it; Seat puts the root SIT_BACK in front of itself
			var seat_pos := xf.origin - xf.basis.z.normalized() * SeatK.SIT_BACK
			var s: Node3D = SeatK.spawn(player.get_parent(), seat_pos, xf.basis.get_euler().y, kind, false)
			s.set_meta(&"so_key", [spot, int(e[0])])
			(s as Object).connect("sat", _on_sat.bind(spot, int(e[0])))
			(s as Object).connect("stood", _on_stood)
			var ic: Variant = s.get_node_or_null("Interactable")
			if ic != null:
				var holders: Array = sp["holders"]
				var slot_i := int(e[0])
				ic.set("can_fn", func(pl: Node) -> bool:
					var h: int = holders[slot_i]
					return (h == -1 or h == PLAYER_ID) and (s.get("occupant") == null or s.get("occupant") == pl))
			_seats[key] = s
	for key: String in _seats.keys():
		if not want.has(key):
			var s: Variant = _seats[key]
			if is_instance_valid(s) and (s as Node3D).get("occupant") == null:
				(s as Node).queue_free()
				_seats.erase(key)
			elif not is_instance_valid(s):
				_seats.erase(key)


func _near(so: Object, p: Vector3) -> Array:
	var out: Array = []
	var spots: Array = so.get("spots")
	for i in spots.size():
		var o: Vector3 = (spots[i]["xform"] as Transform3D).origin
		if absf(o.x - p.x) < RANGE and absf(o.z - p.z) < RANGE and o.distance_to(p) < RANGE:
			out.append(i)
	return out


func _on_sat(_who: Node, spot: int, slot: int) -> void:
	if NpcWorld.smart != null:
		NpcWorld.smart.claim(spot, slot, PLAYER_ID)


func _on_stood(_who: Node) -> void:
	if NpcWorld.smart != null:
		NpcWorld.smart.release(PLAYER_ID)
