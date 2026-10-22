extends GdUnitTestSuite
## Reactive Presence wired live: PresenceLive driving duck-typed bodies like Villager (sample in, abstract reactions out).

const Live := preload("res://scripts/population/presence_live.gd")
const RR := preload("res://scripts/population/reaction_request.gd")
const Presence := preload("res://scripts/population/presence.gd")


class FakeBody extends RefCounted:
	var id := 0
	var pos := Vector2.ZERO
	var facing := Vector2(0, 1)
	var got: Array = []
	var tol := 0.0

	func _init(i: int, p: Vector2, f: Vector2, t := 0.0) -> void:
		id = i
		pos = p
		facing = f
		tol = t

	func presence_sample() -> Dictionary:
		return {"id": id, "pos": pos, "facing": facing, "busy": 0.1,
			"opts": {"tolerance": tol, "persona": {"courage": 0.8}}}

	func presence_react(kind: int, _target: int, _info: Dictionary) -> void:
		got.append(kind)


class FakePlayer extends Node3D:
	var look := Vector3(0, 0, -1)
	var crouching := false

	func facing() -> Vector3:
		return look

	func forward() -> Vector3:
		return look


var live: RefCounted
var player: FakePlayer


func before_test() -> void:
	live = Live.new()
	player = auto_free(FakePlayer.new())
	add_child(player)
	player.global_position = Vector3(0, 0, 6)


func _run(secs: float, bodies: Array, start_ms := 0) -> int:
	var now := start_ms
	for i in int(secs * 20.0):          # 50 ms frames, presence steps at 10 Hz
		now += 50
		live.tick(0.05, now, bodies, player)
	return now


func test_staring_player_glances_only_from_facing_npc() -> void:
	var facing_npc := FakeBody.new(1, Vector2(0, 0), Vector2(0, 1))      # looks toward the player at z=6
	var away_npc := FakeBody.new(2, Vector2(3, 0), Vector2(0, -1))       # back turned
	_run(14.0, [facing_npc, away_npc])
	assert_bool(facing_npc.got.has(RR.Kind.GLANCE)).is_true()
	assert_int(away_npc.got.size()).is_equal(0)
	assert_int(live.presence.stage_of(2, Live.PLAYER_ID)).is_equal(0)


func test_drawn_weapon_indoors_escalates() -> void:
	var npc := FakeBody.new(1, Vector2(0, 0), Vector2(0, 1))
	player.set_meta("weapon_drawn", true)
	var door := InteriorDoor.new()
	InteriorDoor.active = door
	_run(6.0, [npc])
	InteriorDoor.active = null
	door.free()
	var escalated := false
	for k in npc.got:
		if k in [RR.Kind.CONFRONT, RR.Kind.WARN, RR.Kind.CALL_GUARD, RR.Kind.FLEE]:
			escalated = true
	assert_bool(escalated).is_true()
	assert_str(live.describe(1)).is_not_equal("unregistered")


func test_demoted_body_is_unregistered() -> void:
	var a := FakeBody.new(1, Vector2(0, 0), Vector2(0, 1))
	var b := FakeBody.new(2, Vector2(2, 0), Vector2(0, 1))
	_run(1.0, [a, b])
	assert_int(live.registered_count()).is_equal(2)
	_run(1.0, [a], 1000)
	assert_int(live.registered_count()).is_equal(1)
	assert_int(live.presence.slot_of(2)).is_equal(-1)


func test_perf_30_bodies_under_budget() -> void:
	var bodies: Array = []
	for i in 30:
		bodies.append(FakeBody.new(i + 1, Vector2(float(i % 6) * 3.0, float(i / 6) * 3.0), Vector2(0, 1), 0.5))
	var total := 0
	var syn := 0
	var n := 0
	var now := 0
	for i in 600:
		now += 100
		if live.tick(0.1, now, bodies, player):
			total += live.last_tick_usec
			syn += live.sync_usec
			n += 1
	print("PERF avg ", total / n, " sync ", syn / n)
	assert_int(n).is_greater(100)
	assert_float(float(total) / float(n)).is_less(1200.0)   # 0.6 ms target; 2x headroom for loaded CI runners
