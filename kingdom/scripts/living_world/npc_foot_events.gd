extends RefCounted
## NPC foot-contact events for audio / VFX (AAA gap audit 2026-10-28). Villagers near the player detect each foot landing
## from the skeleton (villager.gd _foot_contacts: foot bone drops to its own resting height, with hysteresis) and emit here.
##   const NpcFootEvents := preload("res://scripts/living_world/npc_foot_events.gd")
##   NpcFootEvents.listen(func(body: Node3D, foot: StringName, surface: String, pos: Vector3, speed: float) -> void: ...)
## foot: &"l" / &"r"; surface: SurfaceQuery footstep family (grass, dirt, cobble, stone, wood, water, snow ...); pos: the foot
## on the ground; speed: body ground speed m/s. Each villager also has `signal foot_contact(foot, surface, pos, speed)`.

static var _listeners: Array[Callable] = []


static func listen(cb: Callable) -> void:
	if not _listeners.has(cb):
		_listeners.append(cb)


static func unlisten(cb: Callable) -> void:
	_listeners.erase(cb)


static func emit(body: Node3D, foot: StringName, surface: String, pos: Vector3, speed: float) -> void:
	for i in range(_listeners.size() - 1, -1, -1):
		var cb := _listeners[i]
		if not cb.is_valid():
			_listeners.remove_at(i)
			continue
		cb.call(body, foot, surface, pos, speed)
