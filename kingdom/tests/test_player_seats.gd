extends GdUnitTestSuite
## Player sitting on SmartObjects (WP-01): PlayerSeats puts a Seat on every seated slot near the player, sitting claims the
## slot for the player (no villager takes it) and standing releases it; a slot an NPC holds offers nothing.

const NpcWorld := preload("res://scripts/population/npc_world.gd")
const Bridge := preload("res://scripts/interaction/player_seats.gd")


func test_seat_slots_lists_only_seated_slots() -> void:
	var td := {"slots": [{"stand": [0, 0, 0.4], "seat": 0.45}, {"stand": [1, 0, 0]}, {"stand": [0, 0, -0.4], "seat": 0.45}]}
	var s: Array = Bridge.seat_slots(td)
	assert_int(s.size()).is_equal(2)
	assert_int(int(s[0][0])).is_equal(0)
	assert_int(int(s[1][0])).is_equal(2)


func test_bench_near_the_player_gets_seats_and_claims() -> void:
	var keep: Variant = NpcWorld.smart
	var so := SmartObjects.new()
	NpcWorld.smart = so
	var spot := so.add("bench", Transform3D(Basis(), Vector3(2, 400, 0)))
	var host: Node3D = auto_free(Node3D.new())
	get_tree().root.add_child(host)
	var gs := GDScript.new()
	gs.source_code = "extends Node3D
var dead := false
var touch_move := Vector2.ZERO
"
	gs.reload()
	var pl: Node3D = gs.new()
	host.add_child(pl)
	pl.global_position = Vector3(0, 400, 0)
	var b: Node = Bridge.attach(pl)
	b.call("refresh")
	var seats: Dictionary = b.get("_seats")
	assert_int(seats.size()).is_equal(2)
	var seat: Node3D = seats.values()[0]
	var key: Array = seat.get_meta(&"so_key")
	assert_bool(seat.call("sit", pl)).is_true()
	assert_int(int(so.spots[spot]["holders"][key[1]])).is_equal(Bridge.PLAYER_ID)
	seat.call("stand", pl)
	assert_int(int(so.spots[spot]["holders"][key[1]])).is_equal(-1)
	NpcWorld.smart = keep
