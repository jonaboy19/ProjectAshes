class_name QuestBus
extends RefCounted
## The shared event bus every library objective listens to. Anything that happens in the world is one
## `emit_event(type, data)`; Region 1's story events keep their names and parameters, so the story director's
## notifications (enter_area, kill, defeat, talk, item, ...) reach library quests unchanged
## (Region1StoryQuest.notify forwards them here).
##
## Event types the library understands (data keys in braces):
##   enter_area {place}            position {x, y}              talk {npc, node}
##   kill {target, place, amount}  item {item, amount}          inventory {counts: {item: n}}
##   deliver {item, to, amount}    arrive {actor, place}        actor_pos {actor, x, y}
##   died {actor}                  hours {amount, hour}         interact {id}
##   observe {target, dist, unseen, dt, hour}                   choose {choice, option}
##   (any other type is carried through for Protect's `until`.)

signal fired(type: StringName, data: Dictionary)

static var _shared: QuestBus = null


## The game-wide bus (tests build their own with QuestBus.new()).
static func shared() -> QuestBus:
	if _shared == null:
		_shared = QuestBus.new()
	return _shared


static func reset_shared() -> void:
	_shared = null


func emit_event(type: StringName, data: Dictionary = {}) -> void:
	fired.emit(type, data)
