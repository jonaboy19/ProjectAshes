extends RefCounted
## Input glyphs for PC prompts: the text of the key / mouse button / gamepad button that triggers an action *right now*
## (read from the live InputMap, so a rebind shows up everywhere), for the device the player used last.
##   const IG := preload("res://scripts/ui/input_glyphs.gd")
##   IG.note_event(event)                       # from _input: returns true when keyboard <-> gamepad flipped
##   IG.glyph("interact")                       # "E" on keyboard, "Y" on a pad
##   IG.fill("Press {interact} to talk")        # -> "Press E to talk"
##   IG.combo(IG.MOVE_ACTIONS)                  # "WASD" / "Left Stick"
## Pure statics, no nodes: used by the HUD hint strip, world_prompt_icon.gd, interact_label.gd and
## tutorial_prompt_view.gd.

enum Device { KEYBOARD, GAMEPAD }

const MOVE_ACTIONS := ["move_forward", "move_left", "move_back", "move_right"]
const MOUSE_NAMES := {
	MOUSE_BUTTON_LEFT: "LMB", MOUSE_BUTTON_RIGHT: "RMB", MOUSE_BUTTON_MIDDLE: "MMB",
	MOUSE_BUTTON_WHEEL_UP: "Wheel Up", MOUSE_BUTTON_WHEEL_DOWN: "Wheel Down",
}
## Xbox naming (docs/controls.md); the pad layout is Game.PADS.
const PAD_BUTTONS := {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_BACK: "Back", JOY_BUTTON_START: "Start",
	JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_DPAD_UP: "D-pad Up", JOY_BUTTON_DPAD_DOWN: "D-pad Down",
	JOY_BUTTON_DPAD_LEFT: "D-pad Left", JOY_BUTTON_DPAD_RIGHT: "D-pad Right",
}
const PAD_AXES := {
	JOY_AXIS_LEFT_X: "Left Stick", JOY_AXIS_LEFT_Y: "Left Stick",
	JOY_AXIS_RIGHT_X: "Right Stick", JOY_AXIS_RIGHT_Y: "Right Stick",
	JOY_AXIS_TRIGGER_LEFT: "LT", JOY_AXIS_TRIGGER_RIGHT: "RT",
}
const KEY_OVERRIDES := {KEY_EQUAL: "=", KEY_MINUS: "-", KEY_QUOTELEFT: "`"}
## Bottom-right hint strip: [action, word], in order. Attack / block show the mouse button on keyboard.
const HINT_ACTIONS := [["attack", "attack"], ["block", "block"], ["jump", "jump"], ["dodge", "dodge"],
	["interact", "interact"], ["journal", "pack"]]

## The device the player used last (the HUD flips it from _input).
static var device: int = Device.KEYBOARD


## Feeds one input event; returns true when the active device changed.
static func note_event(e: InputEvent) -> bool:
	var next := device
	if e is InputEventJoypadButton or (e is InputEventJoypadMotion and absf((e as InputEventJoypadMotion).axis_value) > 0.5):
		next = Device.GAMEPAD
	elif e is InputEventKey or e is InputEventMouseButton \
			or (e is InputEventMouseMotion and (e as InputEventMouseMotion).relative.length() > 2.0):
		next = Device.KEYBOARD
	if next == device:
		return false
	device = next
	return true


## "E" / "LMB" / "Y" / "Left Stick" for the action on `dev` (-1 = the active device). "-" when nothing is bound.
static func glyph(action: String, dev := -1, prefer_mouse := false) -> String:
	if dev < 0:
		dev = device
	if not InputMap.has_action(action):
		return "-"
	return _pad_glyph(action) if dev == Device.GAMEPAD else _keyboard_glyph(action, prefer_mouse)


## One label for a group of actions: "WASD" when every key is a single character, else "Up/Left/Down/Right"; a pad shows the shared control.
static func combo(actions: Array, dev := -1) -> String:
	if dev < 0:
		dev = device
	var parts: Array[String] = []
	for a: String in actions:
		var g := glyph(a, dev)
		if not parts.has(g):
			parts.append(g)
	if dev == Device.GAMEPAD:
		return "/".join(parts)
	var joined := "".join(parts)
	for p in parts:
		if p.length() != 1:
			return "/".join(parts)
	return joined


## Replaces every {action} token ("Press {interact} to talk") with that action's glyph.
static func fill(text: String, dev := -1) -> String:
	var re := RegEx.new()
	re.compile("\\{([a-z_0-9]+)\\}")
	var out := text
	for m in re.search_all(text):
		out = out.replace(m.get_string(0), glyph(m.get_string(1), dev))
	return out


## The hint strip text: "LMB attack   |   RMB block   |   Space jump ...".
static func hint_line(dev := -1) -> String:
	var parts: Array[String] = []
	for h: Array in HINT_ACTIONS:
		parts.append("%s %s" % [glyph(String(h[0]), dev, true), h[1]])
	return "   |   ".join(parts)


## Replaces the default key words of a hard-coded English / Dutch tutorial line ("Press E to talk") with the live glyph.
## `tokens` are the words that stand for the key in the text; whole words only.
static func relabel(text: String, tokens: Array, replacement: String) -> String:
	var out := text
	for t: String in tokens:
		var re := RegEx.new()
		re.compile("(?<![A-Za-z0-9])" + t + "(?![A-Za-z0-9])")
		var m := re.search(out)
		if m:
			return out.substr(0, m.get_start()) + replacement + out.substr(m.get_end())
	return out


static func key_text(code: int) -> String:
	if KEY_OVERRIDES.has(code):
		return KEY_OVERRIDES[code]
	var shown := code as Key
	if DisplayServer.get_name() != "headless":      # the layout lookup is unsupported (and logs an error) on the headless server
		shown = DisplayServer.keyboard_get_keycode_from_physical(code as Key)
		if shown == KEY_NONE:
			shown = code as Key
	return OS.get_keycode_string(shown)


static func _keyboard_glyph(action: String, prefer_mouse: bool) -> String:
	var key_text_s := ""
	var mouse_text := ""
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey and key_text_s == "":
			var k := ev as InputEventKey
			key_text_s = key_text(k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode)
		elif ev is InputEventMouseButton and mouse_text == "":
			var b := (ev as InputEventMouseButton).button_index
			mouse_text = String(MOUSE_NAMES.get(b, "Mouse %d" % b))
	if prefer_mouse and mouse_text != "":
		return mouse_text
	if key_text_s != "":
		return key_text_s
	return mouse_text if mouse_text != "" else "-"


static func _pad_glyph(action: String) -> String:
	var axis_text := ""
	for ev in InputMap.action_get_events(action):
		if ev is InputEventJoypadButton:
			var b := (ev as InputEventJoypadButton).button_index
			return String(PAD_BUTTONS.get(b, "Button %d" % b))
		if ev is InputEventJoypadMotion and axis_text == "":
			var a := (ev as InputEventJoypadMotion).axis
			axis_text = String(PAD_AXES.get(a, "Axis %d" % a))
	return axis_text if axis_text != "" else "-"
