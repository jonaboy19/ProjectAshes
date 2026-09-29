class_name Region1TutorialDirector
extends RefCounted
## Contextual tutorial prompts (package L16). Pure logic: no scene tree, no autoloads, so it
## runs headless in tests. A view (tutorial_prompt_view.gd) draws the current prompt; the
## game (hook C8, docs/regions/HOOKS_FOR_CLOUD.md) feeds context and real actions.
##
## Rules
##   * A prompt shows only when its context holds (an enemy is close, the player is hungry,
##     a dim stone is in reach, ...) and its prerequisites are done. One prompt at a time,
##     highest priority first; urgent combat prompts pre-empt calm ones.
##   * A prompt is dismissed ONLY by doing the real action (notify(&"attack")), never by a
##     tap on the prompt. Doing the action before the prompt ever shows also counts, so the
##     game never teaches what the player already knows.
##   * Skip one (skip_current / skip), hide all (set_enabled(false)), replay one or all from
##     the hints list (replay / replay_all). Replayed prompts show even out of context.
##   * If the context goes away (the wolf fled), the prompt hides after a short grace and
##     comes back the next time the context returns.
##
##   var tut := Region1TutorialDirector.new()
##   tut.prompt_shown.connect(view.show_prompt); tut.prompt_hidden.connect(view.hide_prompt)
##   every frame or every few frames:  tut.update(ctx, delta)
##   on real input:                    tut.notify(&"move", delta)   # or notify(&"attack")
##
## ctx keys (all optional, missing = false/0): can_control, blocked (menu/cutscene/dialogue
## open), near_npc, near_interactable, food (0..100), rest (0..100), has_food, near_bed,
## is_night, enemy_near, enemy_winding_up, near_dim_stone, knows_glyph, new_marker,
## near_ash_site, touch (bool: phone layout; picks gesture text over key text).

signal prompt_shown(id: StringName, prompt: Dictionary)
signal prompt_hidden(id: StringName, reason: StringName)   # done | skipped | lost | preempted | disabled
signal prompt_done(id: StringName)

const SAVE_VERSION := 1
const GAP_SECONDS := 1.2        # quiet time between two prompts
const LOST_GRACE := 1.5         # context gone this long -> hide (stays pending)
const MIN_SHOW := 0.6           # a prompt stays at least this long before a calm swap

## The prompt table. Order does not matter; `priority` decides.
##   action   what notify() must report to dismiss it; amount = how much of it (seconds
##            of movement, or number of hits)
##   when     context rule: key: true/false must match; key_lt / key_gt compare numbers
##   after    prompts that must be done (or skipped) first
##   touch    gesture art id for the view; anchor = HUD element it points at
##   text     locale key (touch); text_kb = locale key (keyboard); en / en_kb = English fallbacks
const PROMPTS := {
	"move":     {"priority": 10, "action": "move", "amount": 1.0, "when": {"can_control": true},
				 "touch": "drag", "anchor": "left_stick", "keys": "WASD",
				 "text": "TUT_MOVE", "text_kb": "TUT_MOVE_KB", "en": "Drag to walk", "en_kb": "Walk with WASD"},
	"look":     {"priority": 12, "action": "look", "amount": 0.8, "when": {"can_control": true}, "after": ["move"],
				 "touch": "swipe", "anchor": "screen_right", "keys": "Mouse",
				 "text": "TUT_LOOK", "text_kb": "TUT_LOOK_KB", "en": "Swipe to look around", "en_kb": "Move the mouse to look"},
	"talk":     {"priority": 40, "action": "talk", "amount": 1, "when": {"near_npc": true}, "after": ["move"],
				 "touch": "tap", "anchor": "btn_interact", "keys": "E",
				 "text": "TUT_TALK", "text_kb": "TUT_TALK_KB", "en": "Tap to talk", "en_kb": "Press E to talk"},
	"interact": {"priority": 38, "action": "interact", "amount": 1, "when": {"near_interactable": true}, "after": ["move"],
				 "touch": "tap", "anchor": "btn_interact", "keys": "E",
				 "text": "TUT_INTERACT", "text_kb": "TUT_INTERACT_KB", "en": "Tap to use", "en_kb": "Press E to use"},
	"eat":      {"priority": 60, "action": "eat", "amount": 1, "when": {"food_lt": 35.0, "has_food": true},
				 "touch": "tap", "anchor": "btn_eat", "keys": "F",
				 "text": "TUT_EAT", "text_kb": "TUT_EAT_KB", "en": "Hungry? Tap to eat", "en_kb": "Hungry? Press F to eat"},
	"sleep":    {"priority": 55, "action": "sleep", "amount": 1, "when": {"near_bed": true, "rest_lt": 45.0},
				 "touch": "tap", "anchor": "btn_interact", "keys": "E",
				 "text": "TUT_SLEEP", "text_kb": "TUT_SLEEP_KB", "en": "Tired? Tap the bed", "en_kb": "Tired? Press E at the bed"},
	"fight":    {"priority": 80, "action": "attack", "amount": 2, "when": {"enemy_near": true},
				 "touch": "tap", "anchor": "btn_attack", "keys": "J",
				 "text": "TUT_FIGHT", "text_kb": "TUT_FIGHT_KB", "en": "Tap to strike", "en_kb": "Press J to strike"},
	"block":    {"priority": 90, "action": "block", "amount": 1, "when": {"enemy_winding_up": true}, "after": ["fight"],
				 "touch": "hold", "anchor": "btn_block", "keys": "L",
				 "text": "TUT_BLOCK", "text_kb": "TUT_BLOCK_KB", "en": "Hold to block", "en_kb": "Hold L to block"},
	"dodge":    {"priority": 88, "action": "dodge", "amount": 1, "when": {"enemy_winding_up": true}, "after": ["block"],
				 "touch": "tap", "anchor": "btn_dodge", "keys": "Space",
				 "text": "TUT_DODGE", "text_kb": "TUT_DODGE_KB", "en": "Tap to roll away", "en_kb": "Press Space to roll"},
	"carve":    {"priority": 50, "action": "carve", "amount": 1, "when": {"near_dim_stone": true, "knows_glyph": true},
				 "touch": "trace", "anchor": "center", "keys": "Drag",
				 "text": "TUT_CARVE", "text_kb": "TUT_CARVE_KB", "en": "Trace the glyph", "en_kb": "Drag to trace the glyph"},
	"map":      {"priority": 30, "action": "map", "amount": 1, "when": {"new_marker": true},
				 "touch": "tap", "anchor": "btn_map", "keys": "Tab",
				 "text": "TUT_MAP", "text_kb": "TUT_MAP_KB", "en": "Tap to open the map", "en_kb": "Press Tab for the map"},
	"ashsight": {"priority": 52, "action": "ashsight", "amount": 1, "when": {"near_ash_site": true},
				 "touch": "hold", "anchor": "btn_interact", "keys": "Hold E",
				 "text": "TUT_ASHSIGHT", "text_kb": "TUT_ASHSIGHT_KB", "en": "Hold to read the ash", "en_kb": "Hold E to read the ash"},
}

enum State { PENDING, DONE, SKIPPED }

## The game's director (set by hook C8 with make_main()); null in tests and sandboxes.
## Other Region 1 UIs report real actions without holding a reference:
##     Region1TutorialDirector.tell(&"carve")      # runecarve canvas accepted a glyph
static var main: Region1TutorialDirector

var enabled := true
var current: StringName = &""
var _state: Dictionary = {}       # id -> State
var _progress: Dictionary = {}    # id -> float
var _forced: Dictionary = {}      # id -> true (replayed: ignore context once)
var _gap := 0.0
var _shown_for := 0.0
var _lost_for := 0.0


func _init() -> void:
	for id: String in PROMPTS:
		_state[StringName(id)] = State.PENDING
		_progress[StringName(id)] = 0.0


func make_main() -> Region1TutorialDirector:
	main = self
	return self


static func tell(action: StringName, amount: float = 1.0) -> void:
	if main != null:
		main.notify(action, amount)


static func ids() -> PackedStringArray:
	var a := PackedStringArray()
	for id: String in PROMPTS:
		a.append(id)
	return a


func status(id: StringName) -> int:
	return int(_state.get(id, State.PENDING))


func is_done(id: StringName) -> bool:
	return status(id) == State.DONE


func is_settled(id: StringName) -> bool:
	return status(id) != State.PENDING


func pending() -> PackedStringArray:
	var a := PackedStringArray()
	for id: String in PROMPTS:
		if status(StringName(id)) == State.PENDING:
			a.append(id)
	return a


## Prompt data for the view: {id, text_key, text_en, touch, anchor, keys, touch_mode}.
func describe(id: StringName, touch := true) -> Dictionary:
	var p: Dictionary = PROMPTS.get(String(id), {})
	if p.is_empty():
		return {}
	return {"id": id, "text_key": String(p["text"] if touch else p["text_kb"]), "text_en": String(p["en"] if touch else p["en_kb"]),
		"touch": String(p["touch"]), "anchor": String(p["anchor"]), "keys": String(p["keys"]), "touch_mode": touch}


# --- driving ------------------------------------------------------------------------

## Call every frame (or every few frames) with the current context.
func update(ctx: Dictionary, delta: float) -> void:
	if not enabled:
		return
	var blocked := bool(ctx.get("blocked", false))
	if current != &"":
		_shown_for += delta
		if blocked:
			_hide(&"lost")
			return
		var ok := _forced.has(current) or _context_ok(current, ctx)
		_lost_for = 0.0 if ok else _lost_for + delta
		if _lost_for >= LOST_GRACE:
			_hide(&"lost")
			return
		# An urgent prompt (higher priority, in context) takes over a calm one.
		var best := _best(ctx)
		if best != &"" and best != current and _priority(best) >= 80 and _priority(best) > _priority(current) \
				and _shown_for >= MIN_SHOW:
			_hide(&"preempted")
			_show(best, ctx)
		return
	if blocked:
		return
	_gap = maxf(0.0, _gap - delta)
	if _gap > 0.0:
		return
	var next := _best(ctx)
	if next != &"":
		_show(next, ctx)


## The player really did something. `amount` is seconds (move, look) or a count.
func notify(action: StringName, amount: float = 1.0) -> void:
	for id: String in PROMPTS:
		var sid := StringName(id)
		if status(sid) != State.PENDING or String(PROMPTS[id]["action"]) != String(action):
			continue
		if not _after_ok(sid):
			continue   # the lesson before it isn't learnt yet; don't count ahead
		_progress[sid] = float(_progress[sid]) + amount
		if float(_progress[sid]) >= float(PROMPTS[id]["amount"]) - 0.001:   # summed frame deltas
			_state[sid] = State.DONE
			_forced.erase(sid)
			prompt_done.emit(sid)
			if current == sid:
				_hide(&"done")


## Skip the prompt on screen (the small x on the prompt).
func skip_current() -> void:
	if current != &"":
		skip(current)


func skip(id: StringName) -> void:
	if not PROMPTS.has(String(id)):
		return
	_state[id] = State.SKIPPED
	_forced.erase(id)
	if current == id:
		_hide(&"skipped")


## Settings toggle "Tutorial tips". Off hides the current prompt and stops new ones.
func set_enabled(on: bool) -> void:
	enabled = on
	if not on and current != &"":
		_hide(&"disabled")


## Show one prompt again (hints list in the game menu). It shows at the next update even
## out of context, and still waits for the real action.
func replay(id: StringName) -> void:
	if not PROMPTS.has(String(id)):
		return
	_state[id] = State.PENDING
	_progress[id] = 0.0
	_forced[id] = true
	enabled = true
	_gap = 0.0


func replay_all() -> void:
	for id: String in PROMPTS:
		_state[StringName(id)] = State.PENDING
		_progress[StringName(id)] = 0.0
	_forced.clear()
	enabled = true
	_gap = 0.0


# --- internals ------------------------------------------------------------------------

func _priority(id: StringName) -> int:
	return int((PROMPTS.get(String(id), {}) as Dictionary).get("priority", 0))


func _after_ok(id: StringName) -> bool:
	for dep: Variant in (PROMPTS[String(id)] as Dictionary).get("after", []):
		if not is_settled(StringName(dep)):
			return false
	return true


func _context_ok(id: StringName, ctx: Dictionary) -> bool:
	return rule_holds((PROMPTS[String(id)] as Dictionary).get("when", {}), ctx)


## key: value must equal (bool compare); key_lt / key_gt compare numbers. Missing keys read
## as false / 0.
static func rule_holds(rule: Dictionary, ctx: Dictionary) -> bool:
	for k: String in rule:
		var want: Variant = rule[k]
		if k.ends_with("_lt"):
			if not ctx.has(k.trim_suffix("_lt")) or float(ctx[k.trim_suffix("_lt")]) >= float(want):
				return false
		elif k.ends_with("_gt"):
			if float(ctx.get(k.trim_suffix("_gt"), 0.0)) <= float(want):
				return false
		elif bool(ctx.get(k, false)) != bool(want):
			return false
	return true


func _best(ctx: Dictionary) -> StringName:
	var best: StringName = &""
	var best_p := -1
	for id: String in PROMPTS:
		var sid := StringName(id)
		if status(sid) != State.PENDING or not _after_ok(sid):
			continue
		var p := _priority(sid) + (1000 if _forced.has(sid) else 0)
		if p > best_p and (_forced.has(sid) or _context_ok(sid, ctx)):
			best = sid
			best_p = p
	return best


func _show(id: StringName, ctx: Dictionary) -> void:
	current = id
	_shown_for = 0.0
	_lost_for = 0.0
	prompt_shown.emit(id, describe(id, bool(ctx.get("touch", true))))


func _hide(reason: StringName) -> void:
	var id := current
	current = &""
	_gap = GAP_SECONDS
	prompt_hidden.emit(id, reason)


# --- persistence ----------------------------------------------------------------------

func snapshot() -> Dictionary:
	var done: Array = []
	var skipped: Array = []
	for id: String in PROMPTS:
		match status(StringName(id)):
			State.DONE: done.append(id)
			State.SKIPPED: skipped.append(id)
	return {"done": done, "skipped": skipped, "enabled": enabled}


func restore(d: Dictionary) -> void:
	for id: String in PROMPTS:
		_state[StringName(id)] = State.PENDING
		_progress[StringName(id)] = 0.0
	for id: Variant in d.get("done", []):
		if PROMPTS.has(String(id)):
			_state[StringName(id)] = State.DONE
	for id: Variant in d.get("skipped", []):
		if PROMPTS.has(String(id)):
			_state[StringName(id)] = State.SKIPPED
	enabled = bool(d.get("enabled", true))
	_forced.clear()
	if current != &"":
		_hide(&"lost")


## Save through the Region 1 registry (hook H2 already stores it under "region1").
func register_save() -> void:
	Region1State.register(&"tutorial", snapshot, restore, SAVE_VERSION)
