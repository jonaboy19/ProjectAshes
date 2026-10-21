extends RefCounted
## AR-1: the aura input actions. Registered at runtime so project.godot is untouched and the player can rebind in the
## settings screen (InputMap.action_erase_events + add_event). Defaults: hold Q = release, Z = rein in.

const RELEASE := "aura_release"
const REIN := "aura_rein"


static func ensure_actions() -> void:
	_ensure(RELEASE, KEY_Q)
	_ensure(REIN, KEY_Z)


static func _ensure(action: String, key: Key) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action, 0.5)
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	InputMap.action_add_event(action, ev)


## Rebinds `action` to a single event (settings screen).
static func rebind(action: String, ev: InputEvent) -> void:
	ensure_actions()
	if not InputMap.has_action(action):
		return
	InputMap.action_erase_events(action)
	InputMap.action_add_event(action, ev)


static func held() -> bool:
	return InputMap.has_action(RELEASE) and Input.is_action_pressed(RELEASE)


static func rein_pressed() -> bool:
	return InputMap.has_action(REIN) and Input.is_action_just_pressed(REIN)
