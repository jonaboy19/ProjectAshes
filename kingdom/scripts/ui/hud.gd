class_name HUD
extends CanvasLayer
const GameMenu := preload("res://scripts/ui/gamemenu/game_menu.gd")
const Nameplates := preload("res://scripts/core/nameplates.gd")
## Full-resolution UI drawn over the low-resolution pixel render, in the user's
## dark-gold style: character card with portrait and crest, quest tracker, compass,
## minimap, place / day / time, hotbar, round action buttons, notification popups,
## event banners and the dialogue screen.
##
## Navigation: a compass strip (top centre), a circular minimap (top right), place
## discovery with a cinematic banner, a full-screen world map with fast travel, and
## photo mode. The map and photo mode are children of this layer but not of the HUD
## root, so hiding the root (photo mode) keeps them on screen.
##
## Wiring for main.gd: `hud.fast_travel_requested.connect(func(p: Vector2) -> void: _teleport(p, 0.0))`.
## More touch buttons: `hud.add_action_button("ride", "Ride", "ride", "walk")`.
##
## Popups and banners (all safe to call any time):
##   hud.notify("item", "Item Acquired", "Fresh Bread x3", "bread")   # quest|item|location|reputation|level|gold|info
##   hud.show_event("quest", "Quest Completed", "A Farmer's Problem")    # location|quest|level
## Game.say() text is classified into these automatically (see _say).
## Menus: hud.show_menu(source) - a dict with "speaker" (see dialogue_ui.gd) opens the
## conversation screen, anything else the gold panel.

## Fast travel confirmed on the map. The screen is already black and the clock
## advanced; teleport the player to `pos` (x/z) synchronously in the handler.
signal fast_travel_requested(pos: Vector2)
signal place_discovered(place: Dictionary)

const InventoryScreen := preload("res://scripts/ui/inventory_screen.gd")
const CraftingScreen := preload("res://scripts/ui/crafting_screen.gd")
const TechniqueButtons := preload("res://scripts/ui/technique_buttons.gd")
const SkillsScreen := preload("res://scripts/ui/skills_screen.gd")
var skills_screen: Control
const Discovery := preload("res://scripts/sim/discovery.gd")
const CompassBar := preload("res://scripts/ui/compass.gd")
const WorldMap := preload("res://scripts/ui/world_map.gd")
const TravelRules := preload("res://scripts/world/travel_rules.gd")
const PhotoMode := preload("res://scripts/ui/photo_mode.gd")
const PauseMenu := preload("res://scripts/ui/frontend/pause_menu.gd")
const DiscoveryBanner := preload("res://scripts/ui/discovery_banner.gd")
const MapIcons := preload("res://scripts/ui/map_icons.gd")
const AF := preload("res://scripts/ui/ashes_frame.gd")
const HudArt := preload("res://scripts/ui/hud_art.gd")
const HudCard := preload("res://scripts/ui/hud_card.gd")
const Hotbar := preload("res://scripts/ui/hotbar.gd")
const Minimap := preload("res://scripts/ui/minimap.gd")
const NotifyStack := preload("res://scripts/ui/notify_stack.gd")
const DialogueUI := preload("res://scripts/ui/dialogue_ui.gd")
const Portrait := preload("res://scripts/ui/portrait.gd")
const SkillsSim := preload("res://scripts/sim/skills.gd")
const HudMode := preload("res://scripts/ui/hud_mode.gd")
const InteractLabel := preload("res://scripts/ui/interact_label.gd")

const DISCOVERY_RATE := 0.25       # s between discovery checks
const MARKER_RATE := 1.0           # s between compass marker rebuilds
const EVENT_RATE := 0.5            # s between gold / level / inventory checks for popups
const COMPASS_RANGE := 400.0       # discovered places shown on the compass
const HOSTILE_RANGE := 250.0       # camps shown (red) even before they are found
const COMBAT_RANGE := 45.0         # enemies this close block fast travel (same as the battle music)
const DOCK_SIZE := 52
const DOCK_STEP := 72              # button + caption
const ABILITY_DASH_COLOR := Color("6d5cff")   # violet: distinct from the teal plain dodge
const LEFT := 12.0                 # left / right screen margin of the HUD cards
const MINIMAP_SIZE := 100.0
const MENU_AUTO_CLOSE := 7.0        # s the button fan stays open
const FAN_RINGS := [[3, 92.0], [4, 168.0], [5, 244.0], [6, 320.0]]   # [items, radius] of the menu fan, nearest ring first
const DANGER_SHOWN := 20.0          # the danger badge appears from this threat

var player: Player
var controls: Control
var _perf: Label
var _toast: Label
var _toast_tween: Tween
var _interact: TouchScreenButton
var _interact_label: Label
var _interact_small: TouchScreenButton        # the interact button as a context action (combat, or no room)
var _attack_small: TouchScreenButton          # attack as a context action while a target owns the primary slot
var _eat_button: TouchScreenButton
var _menu_button: TouchScreenButton
var _pill: Control                            # HudCard.ActionPill: "Talk — Roland Ward"
var _techniques: Control
var mode := HudMode.new()                     # exploration / combat layout state (tests read it)
var target: Node3D                            # the current interactable (null when nothing is in reach)
var target_label: Dictionary = {}             # InteractLabel.resolve(target)
var _menu_open_t := 0.0                       # >0: seconds left until the fan closes itself
var fan_open := false
var _fan: Array[TouchScreenButton] = []
var _goal: Dictionary = {}                    # TouchScreenButton -> goal position
var _fade_goal: Dictionary = {}               # TouchScreenButton -> goal alpha
var _snap := true
var _safe := Rect2(0, 0, 1280, 720)
var _combat_timer := 0.0
var _dash_cooling := false
var _food_low := false
var _danger_total := 0.0
var _prev_health := -1
var _pill_a := 0.0
var stick: VirtualJoystick
var _dash_cooldown_label: Label
var _order_buttons: Array[TouchScreenButton] = []
var _buttons: Dictionary = {}
var _loading: Control      # WorldLoading while the world is generated
var _toast_box: PanelContainer
var _menu: PanelContainer
var _menu_source: Callable
var _pack_button: TouchScreenButton
var _pause_button: TouchScreenButton
var _root: Control
var _chrome: Control                # the HUD furniture (card, compass, minimap...): hidden during a conversation
var card: Control                   # HudCard.Card
var tracker: Control                # HudCard.QuestTracker
var info: Control                   # HudCard.InfoBlock
var danger_badge: Control           # HudCard.DangerBadge
var hotbar: Control                 # hotbar.gd
var minimap: Control                # minimap.gd
var notifications: Control          # notify_stack.gd
var dialogue: Control               # dialogue_ui.gd
var portrait: Control               # the card's round portrait (portrait.gd)
var compass: Control               # scripts/ui/compass.gd
var banner: Control                # scripts/ui/discovery_banner.gd
var world_map: Control             # scripts/ui/world_map.gd
var parchment: Control             # Region1 hook H6: scripts/ui/map_parchment_layer.gd
var photo_mode: Control            # scripts/ui/photo_mode.gd
var discovery: RefCounted          # scripts/sim/discovery.gd (Life.discovery when Life owns one)
## The fps / chunk line: hidden unless this is on (`--debug-hud`, or project setting ashes/debug/show_stats).
var _plate_timer := 0.0
var debug_stats := false:
	set(v):
		debug_stats = v
		if _perf:
			_perf.visible = v
var _fade: ColorRect
var _dock: Array[TouchScreenButton] = []     # auto-placed action buttons, in order
var _anchored: Dictionary = {}               # TouchScreenButton -> offset from the bottom-right corner
var _nav_timer := 0.0
var _marker_timer := 0.0
var _event_timer := 0.0
var _quest_override: Variant = null
var _dlg_options: Array = []
var _last_gold := -1
var _last_level := -1
var _inv_snapshot: Dictionary = {}
var _inv_dirty := false
var _quest_titles: Dictionary = {}           # title -> true, for classifying "Title: stage text" messages
var _soldiers := 0
var _stack_sig := ""
var _portrait_ready := false
var _touch := false
## Anything with active_objective_position() -> Vector2|null (e.g. the radiant
## quest tracker: `hud.quest_source = services.radiant()`). Life.radiant is used
## automatically when Life owns one.
var quest_source: Object
## Region1 hook C7 (docs/regions/REGION_1_PLAN.md): the story quest. `story_tracker` returns {title, objectives: [{text, state}]}
## (or {} to hide), `story_target` returns a Vector2 compass hint or null. Both are optional and the player can hide the tracker.
var story_tracker: Callable = Callable()
var story_target: Callable = Callable()


func _init(p: Player) -> void:
	player = p
	layer = 10


func _ready() -> void:
	_touch = HudArt.touch_mode()
	debug_stats = "--debug-hud" in OS.get_cmdline_user_args() or bool(ProjectSettings.get_setting("ashes/debug/show_stats", false))
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_root = root
	controls = Control.new()
	controls.set_anchors_preset(Control.PRESET_FULL_RECT)
	controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(controls)

	var look := Control.new()
	look.anchor_left = 0.4
	look.anchor_right = 1.0
	look.anchor_bottom = 1.0
	look.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventScreenDrag:
			player.add_look(e.relative * App.look_scale))
	controls.add_child(look)
	stick = VirtualJoystick.new()
	stick.anchor_right = 0.4
	stick.anchor_top = 0.3
	stick.anchor_bottom = 1.0
	stick.size_scale = App.joystick_scale
	stick.moved.connect(func(v: Vector2) -> void: player.touch_move = v)
	controls.add_child(stick)

	_buttons["attack"] = _button("attack", "", 128, UITheme.ACTION_ATTACK, "broadsword")
	_buttons["jump"] = _button("jump", "Jump", 72, UITheme.ACTION_UTIL, "")
	(_buttons["jump"].shape as CircleShape2D).radius = 44.0 # 88 dp target, 72 dp face
	_buttons["dodge"] = _button("dodge", "", 84, UITheme.ACTION_DODGE, "dodge")
	_buttons["block"] = _button("block", "", 84, UITheme.ACTION_BLOCK, "checked-shield")
	# Shadow Dash: a separate ability button (cooldown, own icon tint) so it
	# never gets confused with the plain dodge above.
	_buttons["ability_dash"] = _button("ability_dash", "", 72, ABILITY_DASH_COLOR, "dodge")
	_dash_cooldown_label = Label.new()
	_dash_cooldown_label.position = Vector2(-36, -36)
	_dash_cooldown_label.size = Vector2(72, 72)
	_dash_cooldown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dash_cooldown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_dash_cooldown_label.add_theme_font_size_override("font_size", 22)
	_dash_cooldown_label.add_theme_color_override("font_color", Color.WHITE)
	_dash_cooldown_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	_dash_cooldown_label.add_theme_constant_override("shadow_outline_size", 4)
	_dash_cooldown_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_buttons["ability_dash"].add_child(_dash_cooldown_label)
	_buttons["view"] = _button("view_cycle", "Look", DOCK_SIZE, UITheme.ACTION_UTIL, "eye-target")
	_buttons["zoom_out"] = _button("zoom_out", "−", 44, UITheme.ACTION_UTIL, "")
	_buttons["zoom_in"] = _button("zoom_in", "+", 44, UITheme.ACTION_UTIL, "")
	_interact = _button("interact", "", 128, UITheme.ACTION_TALK, "hand")
	_interact_small = _button("interact", "Talk", 72, UITheme.ACTION_TALK, "hand")
	_attack_small = _button("attack", "", 72, UITheme.ACTION_ATTACK, "broadsword")
	_eat_button = _button("eat", "Eat", 72, Color("5fae6b"), "hand")
	_menu_button = _make_button("", "", 60, UITheme.ACTION_UTIL, UITheme.glyph("menu"), true)
	_menu_button.pressed.connect(toggle_fan)
	_buttons["menu"] = _menu_button
	_buttons["skills"] = _button("", "Skills", DOCK_SIZE, UITheme.ACTION_UTIL, "glyph:star")
	(_buttons["skills"] as TouchScreenButton).pressed.connect(func() -> void: GameMenu.open(self, "skills"))
	_buttons["quickbar"] = _button("", "Slots", DOCK_SIZE, UITheme.ACTION_UTIL, "glyph:slots")
	(_buttons["quickbar"] as TouchScreenButton).pressed.connect(func() -> void:
		mode.hotbar_pinned = not mode.hotbar_pinned)
	_pack_button = _button("journal", "Pack", DOCK_SIZE, UITheme.ACTION_UTIL, "knapsack")
	_pause_button = _make_button("", "", 52, UITheme.ACTION_UTIL, UITheme.glyph("pause"))
	_pause_button.pressed.connect(open_pause)
	_interact_label = _interact.get_child(0)
	_interact.visible = false
	_interact_small.visible = false
	_attack_small.visible = false
	_eat_button.visible = false
	for extra: Array in [["order_retreat", KEY_G], ["order_formation", KEY_B], ["ability_dash", KEY_R]]:
		if not InputMap.has_action(extra[0]):
			InputMap.add_action(extra[0])
			var ev := InputEventKey.new()
			ev.physical_keycode = extra[1]
			InputMap.action_add_event(extra[0], ev)
	for pair in [["order_follow", "Follow", "walk"], ["order_hold", "Hold", "flag-objective"], ["order_charge", "Charge", "charging-bull"],
			["order_retreat", "Retreat", "dodge"], ["order_formation", "Form", "checked-shield"]]:
		var b := _button(pair[0], pair[1], 56, Color("5fae6b"), pair[2])
		b.visible = false
		_order_buttons.append(b)
	var techniques := TechniqueButtons.new()
	techniques.visible = _touch or "--technique-ring" in OS.get_cmdline_user_args()
	techniques.fade = 0.0
	controls.add_child(techniques)
	_techniques = techniques
	techniques.open_skills_requested.connect(func() -> void: GameMenu.open(self, "skills"))
	_pill = HudCard.ActionPill.new()
	_pill.modulate.a = 0.0
	_pill.visible = false
	controls.add_child(_pill)

	_chrome = Control.new()
	_chrome.set_anchors_preset(Control.PRESET_FULL_RECT)
	_chrome.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_chrome)

	# Character card top left (portrait, crest, title, job, gold / merit, bars), quest tracker,
	# danger badge and the popup stack hang below it.
	card = HudCard.Card.new()
	_chrome.add_child(card)
	tracker = HudCard.QuestTracker.new()
	_chrome.add_child(tracker)
	danger_badge = HudCard.DangerBadge.new()
	danger_badge.visible = false
	_chrome.add_child(danger_badge)
	info = HudCard.InfoBlock.new()
	_chrome.add_child(info)
	minimap = Minimap.new()
	minimap.size = Vector2(MINIMAP_SIZE, MINIMAP_SIZE)
	minimap.player = player
	minimap.tapped.connect(toggle_map)
	_chrome.add_child(minimap)
	hotbar = Hotbar.new()
	hotbar.player = player
	hotbar.open_skills_requested.connect(func() -> void: GameMenu.open(self, "skills"))
	_chrome.add_child(hotbar)
	(card as HudCard.Card).toggled.connect(_on_card_toggled)
	card.resized.connect(_layout_left)
	(tracker as HudCard.QuestTracker).toggled.connect(func(_e: bool) -> void: _layout_left())
	(card.health as Meter).max_value = player.max_health
	(card.health as Meter).value = player.health
	(card.stamina as Meter).max_value = Player.MAX_STAMINA
	(card.stamina as Meter).value = Player.MAX_STAMINA
	_perf = Label.new()
	HudArt.outline_label(_perf, 12, Color(1, 1, 1, 0.7), null, 3)
	_perf.anchor_left = 0.5
	_perf.anchor_right = 0.5
	_perf.offset_left = -300
	_perf.offset_right = 300
	_perf.offset_top = 72
	_perf.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_perf.visible = debug_stats
	_chrome.add_child(_perf)
	notifications = NotifyStack.new()
	notifications.custom_minimum_size = Vector2(NotifyStack.CARD_W, 0)
	notifications.size = Vector2(NotifyStack.CARD_W, (NotifyStack.CARD_H + 6.0) * NotifyStack.MAX_VISIBLE)
	root.add_child(notifications)

	_toast_box = PanelContainer.new()
	var tb := HudArt.card_box(0.9, 10)
	tb.content_margin_left = 22
	tb.content_margin_right = 22
	_toast_box.add_theme_stylebox_override("panel", tb)
	_toast_box.anchor_left = 0.5
	_toast_box.anchor_right = 0.5
	_toast_box.offset_top = 80
	_toast_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_box.modulate.a = 0.0
	root.add_child(_toast_box)
	_toast = Label.new()
	_toast.add_theme_font_override("font", AF.font())
	_toast.add_theme_font_size_override("font_size", 19)
	_toast.add_theme_color_override("font_color", HudArt.IVORY)
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_box.add_child(_toast)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast.custom_minimum_size.x = 420

	_build_navigation(root)

	dialogue = DialogueUI.new()
	dialogue.option_picked.connect(_on_dialogue_pick)
	dialogue.leave_requested.connect(close_menu)
	root.add_child(dialogue)
	root.move_child(dialogue, _toast_box.get_index())      # under the toast, over the HUD furniture

	_menu = PanelContainer.new()
	_menu.theme = AF.theme()
	_menu.add_theme_stylebox_override("panel", _menu_style())
	_menu.anchor_left = 0.5
	_menu.anchor_right = 0.5
	_menu.anchor_top = 0.5
	_menu.anchor_bottom = 0.5
	_menu.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_menu.grow_vertical = Control.GROW_DIRECTION_BOTH
	_menu.custom_minimum_size = Vector2(520, 0)
	_menu.visible = false
	root.add_child(_menu)

	# World-generation veil (backdrop, tips, progress bar; see world_loading.gd).
	_loading = WorldLoading.new()
	root.add_child(_loading)

	player.stamina_changed.connect(func(c: float, _m: float) -> void: (card.stamina as Meter).value = c)
	player.health_changed.connect(func(c: int, m: int) -> void:
		if c < int((card.health as Meter).value):
			App.vibrate(35)
			mode.engage()      # taking damage is combat: the full cluster comes up
		(card.health as Meter).max_value = m
		(card.health as Meter).value = c)
	Game.toast.connect(_say)
	if Life.has_signal("inventory_changed"):
		Life.inventory_changed.connect(func() -> void: _inv_dirty = true)
	_build_overlays()
	get_viewport().size_changed.connect(_on_resized)
	_layout()
	_snap = false


func _on_resized() -> void:
	_snap = true
	_layout()
	_snap = false


## True while the world-generation veil is up (it frees itself after fading out).
func _veil() -> bool:
	return is_instance_valid(_loading) and _loading.visible


func hide_loading() -> void:
	WorldLoading.finish()
	world_map.start_bake()      # paint the map terrain in the background now the world exists
	_snapshot_events()
	refresh_portrait()


func set_loading_text(text: String, progress := -1.0) -> void:
	if _loading is WorldLoading:
		(_loading as WorldLoading).set_progress(progress, text)


## (Re)renders the round portrait on the card: the character-creator look in
## `Life.appearance` when there is one, else the default young player model.
func refresh_portrait() -> void:
	if portrait == null:
		portrait = Portrait.new()
		portrait.setup(Vector2i(200, 200), "face", false)
		portrait.set_circle(true, HudCard.circle_mask())
		card.set_portrait(portrait)
	var model: Node3D = null
	var look: Variant = Life.get("appearance")
	if look is Dictionary and not (look as Dictionary).is_empty() and ResourceLoader.exists("res://scripts/ui/character_creation.gd"):
		model = (load("res://scripts/ui/character_creation.gd") as GDScript).call("build_model", look, 1.75)
	if model == null:
		model = Assets.mh_character("player_young", 1.75)
	portrait.set_model(model)
	_portrait_ready = true


# --- buttons ------------------------------------------------------------------------

## Dark face colour for a button, hinted by its accent colour (red attack, teal dodge, violet block...).
func _fill_for(color: Color) -> Color:
	return Color(0.07, 0.06, 0.055).lerp(color.darkened(0.35), 0.5)


func _button(action: String, text: String, size: int, color: Color, icon_name := "") -> TouchScreenButton:
	var res := HudArt.resolve_icon(icon_name)
	return _make_button(action, text, size, color, res[0], res[1])


func _make_button(action: String, text: String, size: int, color: Color, ic: Texture2D, tint := false) -> TouchScreenButton:
	var b := TouchScreenButton.new()
	b.action = action
	var face := HudArt.round_face(size, _fill_for(color), ic, tint, 0.66 if size >= 96 else 0.62)
	b.texture_normal = face
	b.texture_pressed = face
	b.pressed.connect(func() -> void: b.modulate = Color(1.35, 1.25, 1.05, b.modulate.a))
	b.released.connect(func() -> void: b.modulate = Color(1, 1, 1, b.modulate.a))
	var circle := CircleShape2D.new()
	circle.radius = size * 0.5
	b.shape = circle
	b.shape_centered = true
	var l := Label.new()
	l.text = text
	l.size = Vector2(size, size) if ic == null else Vector2(size, 22)
	l.position = Vector2.ZERO if ic == null else Vector2(0, size + 1)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	HudArt.outline_label(l, 26 if ic == null else 14, HudArt.IVORY, AF.font(), 4)
	b.add_child(l)
	controls.add_child(b)
	return b


## Insets of the screen's safe area (notch, rounded corners, gesture bar) in HUD units, as Vector4(left, top, right, bottom).
## `win` is the window in pixels, `safe` the OS safe rectangle in pixels, `view` the HUD viewport in units.
static func safe_insets(win: Vector2, safe: Rect2, view: Vector2) -> Vector4:
	if win.x <= 0.0 or win.y <= 0.0 or safe.size.x <= 0.0 or safe.size.y <= 0.0:
		return Vector4.ZERO
	var k := view.y / win.y
	return Vector4(clampf(safe.position.x * k, 0.0, 120.0), clampf(safe.position.y * k, 0.0, 80.0),
		clampf((win.x - safe.end.x) * k, 0.0, 120.0), clampf((win.y - safe.end.y) * k, 0.0, 80.0))


func _safe_rect(s: Vector2) -> Rect2:
	var ins := Vector4.ZERO
	if OS.has_feature("mobile"):
		ins = safe_insets(Vector2(DisplayServer.window_get_size()), DisplayServer.get_display_safe_area(), s)
	var l := maxf(LEFT, ins.x)
	var tp := maxf(8.0, ins.y)
	var r := maxf(LEFT, ins.z)
	var bt := maxf(LEFT, ins.w)
	return Rect2(l, tp, s.x - l - r, s.y - tp - bt)


## A bottom-right offset in the old "s - offset" convention, moved inside the safe area.
func _at(off: Vector2) -> Vector2:
	return _safe.end - (off - Vector2(LEFT, LEFT))


## Sets where a button should be and how visible; it eases there (or jumps while `_snap`).
func _pose(b: TouchScreenButton, pos: Vector2, alpha := 1.0) -> void:
	_goal[b] = pos
	_fade_goal[b] = alpha
	if _snap:
		b.position = pos
		b.modulate.a = alpha
		b.visible = alpha > 0.03


func _ease_buttons(delta: float) -> void:
	var k := 1.0 - exp(-delta * 15.0)
	for b: TouchScreenButton in _goal.keys():
		if not is_instance_valid(b):
			_goal.erase(b)
			_fade_goal.erase(b)
			continue
		var goal: Vector2 = _goal[b]
		var ag := float(_fade_goal[b])
		if b == _buttons.get("ability_dash") and _dash_cooling:
			ag *= 0.35
		b.position = goal if b.position.distance_squared_to(goal) < 0.25 else b.position.lerp(goal, k)
		var a := lerpf(b.modulate.a, ag, k)
		b.modulate.a = ag if absf(a - ag) < 0.01 else a
		b.visible = b.modulate.a > 0.03


func _layout() -> void:
	var s := get_viewport().get_visible_rect().size
	_safe = _safe_rect(s)
	var combat := mode.in_combat()
	var has_target := target != null
	var talk := has_target and not combat
	# Bottom right: ONE big primary button (interact when something is in reach, else attack) and a few
	# context actions; the rest of the combat cluster only exists while fighting.
	_pose(_buttons["attack"], _at(Vector2(168, 168)), 0.0 if talk else 1.0)
	_pose(_interact, _at(Vector2(168, 168)), 1.0 if talk else 0.0)
	# Jump sits above Attack; in combat with a target the small Interact takes that slot.
	_pose(_buttons["jump"], _at(Vector2(168, 300)), 0.0 if (has_target and combat) else 1.0)
	_pose(_buttons["dodge"], _at(Vector2(270, 112)), 1.0)
	_pose(_buttons["block"], _at(Vector2(240, 226)), 1.0 if combat else 0.0)
	_pose(_attack_small, _at(Vector2(352, 104)), 1.0 if talk else 0.0)
	_pose(_buttons["ability_dash"], _at(Vector2(357, 96)), 1.0 if combat else 0.0)
	_pose(_eat_button, _at(Vector2(436, 96)), 1.0 if (_food_low and not combat) else 0.0)
	_pose(_interact_small, _at(Vector2(150, 300)), 1.0 if (has_target and combat) else 0.0)
	if _techniques:
		_techniques.inset = Vector2(s.x - _safe.end.x - LEFT, s.y - _safe.end.y - LEFT).max(Vector2.ZERO)
	for i in _order_buttons.size():
		_order_buttons[i].position = Vector2(s.x * 0.5 - 150 + i * 62, s.y - 176)
	for b: TouchScreenButton in _anchored:
		b.position = _safe.end + Vector2(LEFT, LEFT) - (_anchored[b] as Vector2)
	# The pill with the verb and target sits on top of the primary button, right-aligned with it.
	_place_pill()
	# Top right: the small minimap with the place / time block to its left, the menu button below it.
	minimap.position = Vector2(_safe.end.x - MINIMAP_SIZE, _safe.position.y)
	info.size = Vector2(290, 58)
	info.position = Vector2(minimap.position.x - 10.0 - info.size.x, _safe.position.y + 2.0)
	_pose_fan()
	if compass:
		var w := clampf(s.x - 2.0 * 450.0, 240.0, 460.0)
		compass.size = Vector2(w, compass.custom_minimum_size.y)
		compass.position = Vector2((s.x - w) * 0.5, _safe.position.y + 2.0)
	# The hotbar only exists when it is relevant: slides up from the bottom edge.
	var hb := mode.hotbar_wanted()
	hotbar.position = Vector2((s.x - hotbar.size.x) * 0.5, _safe.end.y - hotbar.size.y + (0.0 if hb else 36.0))
	if stick:
		stick.offset_left = maxf(0.0, _safe.position.x - LEFT)
		stick.offset_bottom = -maxf(0.0, s.y - _safe.end.y - LEFT)
	_layout_left()


func _place_pill() -> void:
	var pr := _at(Vector2(40, 0)).x
	_pill.position = Vector2(pr - _pill.size.x, _at(Vector2(0, 168)).y - _pill.size.y - 10.0 + (1.0 - _pill_a) * 12.0)


## The menu button and the radial fan of utility buttons that opens from it: Pack, Map, Skills, Look, Lock,
## Sneak, camera zoom, quick slots, Pause and any button other code added to the dock.
func _pose_fan() -> void:
	var centre := Vector2(_safe.end.x - 30.0, _safe.position.y + MINIMAP_SIZE + 42.0)
	var bsz := 60.0
	_pose(_menu_button, centre - Vector2(bsz, bsz) * 0.5, 1.0)
	var items: Array[TouchScreenButton] = []
	for key: String in ["pack", "map", "skills", "view", "lock_on", "crouch", "zoom_in", "zoom_out", "quickbar"]:
		var b: TouchScreenButton = _pack_button if key == "pack" else _buttons.get(key)
		if b != null and not items.has(b):
			items.append(b)
	items.append(_pause_button)
	for b in _dock:
		if not items.has(b):
			items.append(b)
	_fan = items
	var idx := 0
	for ring: Array in FAN_RINGS:
		var n := mini(int(ring[0]), items.size() - idx)
		for k in n:
			var b := items[idx]
			idx += 1
			if not b.has_meta("fan_wired"):
				b.set_meta("fan_wired", true)
				b.pressed.connect(_on_fan_pressed.bind(b))
			var a := deg_to_rad(95.0 + (80.0 * k / maxf(n - 1, 1.0) if n > 1 else 40.0))
			var p := centre + Vector2(cos(a), sin(a)) * float(ring[1])
			var half := Vector2(b.texture_normal.get_size()) * 0.5
			var at := p - half
			at.x = clampf(at.x, _safe.position.x, _safe.end.x - half.x * 2.0)
			_pose(b, at if fan_open else centre - half, 1.0 if fan_open else 0.0)
		if idx >= items.size():
			break


## The left stack: card, quest tracker, danger badge, then the notification popups.
func _layout_left() -> void:
	var y := _safe.position.y + 2.0
	var x := _safe.position.x
	card.position = Vector2(x, y)
	y += card.size.y + 8.0
	if tracker.visible:
		tracker.position = Vector2(x, y)
		y += tracker.get_combined_minimum_size().y + 8.0
	if danger_badge.visible:
		danger_badge.position = Vector2(x, y)
		y += danger_badge.size.y + 10.0
	notifications.position = Vector2(x, y)


func show_toast(text: String) -> void:
	_toast.text = text
	if _toast_tween:
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_box.modulate.a = 0.0
	_toast_box.scale = Vector2.ONE
	_toast_tween.tween_property(_toast_box, "modulate:a", 1.0, 0.18)
	_toast_tween.tween_interval(3.2)
	_toast_tween.tween_property(_toast_box, "modulate:a", 0.0, 0.45)


# --- popups, banners and message classification ---------------------------------------

## A stacked popup on the left edge. kind: quest | item | location | reputation | level | gold | info.
## `icon` is an item id for "item" (its painted icon is used).
func notify(kind: String, title: String, subtitle := "", icon := "") -> void:
	notifications.push(kind, title, subtitle, icon)


## A centre-screen banner. kind: "location" | "quest" | "level".
func show_event(kind: String, title: String, subtitle := "", kicker := "") -> void:
	banner.show_event(kind, title, subtitle, kicker)


## Every Game.say() lands here: typed messages become popups / banners (the raw text is
## then not shown twice), everything else is the plain message pill.
func _say(text: String) -> void:
	var t := text.strip_edges()
	# "Quest complete: <title>  (rewards)" -> banner + popup
	if t.begins_with("Quest complete: "):
		var title := t.trim_prefix("Quest complete: ").split("  ")[0].strip_edges()
		var rest := t.trim_prefix("Quest complete: ").trim_prefix(title).strip_edges()
		show_event("quest", "Quest Completed", title)
		notify("quest", "Quest Completed", title)
		if rest != "":
			show_toast(rest.trim_prefix("(").trim_suffix(")"))
		return
	if t.begins_with("Quest failed: "):
		notify("quest", "Quest Failed", t.trim_prefix("Quest failed: ").trim_suffix(" (out of time)."))
		return
	if t.begins_with("Accepted: "):
		var body := t.trim_prefix("Accepted: ")
		var q_title := body.split(". ")[0]
		notify("quest", "Quest Accepted", q_title)
		return
	if t.begins_with("Commission ready to turn in: "):
		notify("quest", "Commission Ready", t.trim_prefix("Commission ready to turn in: "))
		return
	if t.begins_with("Tracking: "):
		notify("quest", "Quest Tracked", t.trim_prefix("Tracking: "))
		return
	for qt: String in _known_quest_titles():
		if t.begins_with(qt + ": "):
			notify("quest", "Quest Updated", qt)
			return
	# "+5 merit: wolf slain"
	var merit_re := RegEx.create_from_string("^\\+(\\d+) merit: (.*)$")
	var m := merit_re.search(t)
	if m:
		notify("reputation", "Reputation Increased", "+%s merit · %s" % [m.get_string(1), m.get_string(2)])
		return
	if t.begins_with("Title earned: "):
		notify("reputation", "Title Earned", t.trim_prefix("Title earned: "))
		return
	if t.begins_with("Promoted to "):
		notify("level", "Promoted", t.trim_prefix("Promoted to ").split(".")[0])
		return
	if t.begins_with("Guild rank up: "):
		notify("level", "Guild Rank Up", t.trim_prefix("Guild rank up: ").trim_suffix("!"))
		return
	# The item popup (inventory diff) and the gold popup (gold diff) already say these.
	if t.begins_with("Picked ") or t.begins_with("Sold ") or t.begins_with("Bought "):
		return
	show_toast(t)


func _known_quest_titles() -> Array:
	var out: Array = []
	var rq: Variant = Life.get("radiant")
	if rq is Object and rq.get("active") is Array:
		for q: Dictionary in rq.active:
			out.append(String(q.get("title", "")))
	return out.filter(func(s: String) -> bool: return s != "")


func _snapshot_events() -> void:
	_last_gold = Game.gold
	_last_level = Life.player_level()
	_inv_snapshot = _inventory_counts()
	_inv_dirty = false


func _inventory_counts() -> Dictionary:
	var out := {}
	for it in Life.inventory.get_items():
		var id: String = it.get_prototype().get_prototype_id()
		if not out.has(id):
			out[id] = Life.count(id)
	return out


## Popups that come from state changes rather than messages: gold earned, items picked up,
## level gained. Polled at EVENT_RATE, and quiet until the world has loaded.
func _poll_events() -> void:
	if _last_gold < 0:
		return
	var g := Game.gold
	if g > _last_gold:
		notifications.push_gold(g - _last_gold)
	_last_gold = g
	if _inv_dirty:
		_inv_dirty = false
		var now := _inventory_counts()
		for id: String in now:
			var gained := int(now[id]) - int(_inv_snapshot.get(id, 0))
			if gained > 0:
				notify("item", "Item Acquired", "%s%s" % [Life.item_name(id), " ×%d" % gained if gained > 1 else ""], id)
		_inv_snapshot = now
	var lv := Life.player_level()
	if lv > _last_level and _last_level >= 1:
		var pts := SkillsSim.points_for_level(lv) - SkillsSim.points_for_level(_last_level)
		var detail := "Level %d" % lv
		if pts > 0:
			detail += "  ·  +%d Skill Point%s" % [pts, "" if pts == 1 else "s"]
		show_event("level", "Level Up", detail)
		notify("level", "Level Up", "Level %d" % lv)
	_last_level = lv


# --- status -------------------------------------------------------------------------

func update_status(soldiers: int, order_name: String, target_node: Node3D, perf: String) -> void:
	_soldiers = soldiers
	hotbar.soldiers = soldiers
	var c := Life.careers
	var job_line := "Unemployed"
	if c.is_employed():
		var duty := ""
		if c.is_on_shift(WorldSim.time_of_day):
			var p2 := Vector2(player.global_position.x, player.global_position.z)
			duty = "  · ON DUTY" if c.at_post(p2) else "  · AWAY FROM POST"
		job_line = "%s, %s%s" % [c.player["seat"], c.player_org()["name"], duty]
	var n := Life.needs
	var soldiers_text := ""
	if Game.max_soldiers() > 0 or soldiers > 0:
		soldiers_text = "Soldiers %d / %d%s" % [soldiers, Game.max_soldiers(), ("  ·  " + order_name) if soldiers > 0 else ""]
	var mag: Variant = Life.get("magicules")
	var soul_frac := -1.0
	var aw: Variant = Life.get("awakening")
	if mag is Object and aw is Object and bool(aw.get("done")):
		soul_frac = clampf(float(mag.current) / maxf(float(mag.effective_max()), 1.0), 0.0, 1.0)
	(card as HudCard.Card).set_state(Game.rank_name(), Game.rank, job_line, Game.gold, Game.merit,
		"%s  ·  %s" % [n.hunger_label(), n.rest_label()], n.food >= 25.0 and n.rest >= 30.0, soldiers_text, soul_frac,
		clampf(n.food / 100.0, 0.0, 1.0))
	var low := n.food < 40.0 and Life.best_food() != ""
	if low != _food_low:
		_food_low = low
		_layout()
	var p := Vector2(player.global_position.x, player.global_position.z)
	var near := WorldGen.nearest_settlement(p)
	var place := "Wilderness"
	if not near.is_empty():
		var d := p.distance_to(near["pos"])
		place = near["name"] if d < near["radius"] * 1.6 else "Road to %s  (%dm)" % [near["name"], int(d)]
		var named := Life.place_at(p)
		if d >= near["radius"] * 1.6 and not named.is_empty():
			place = "%s  ·  %s %dm" % [named["name"], near["name"], int(d)]
	var t := WorldSim.time_of_day
	(info as HudCard.InfoBlock).show_realm = (card as HudCard.Card).expanded
	(info as HudCard.InfoBlock).set_info(place, "Day %d · %s" % [WorldSim.day, String(WorldSim.season).capitalize()],
		"%02d:%02d" % [int(t), int(fmod(t, 1.0) * 60.0)], t < 6.0 or t >= 20.0,
		"Realm  %s souls" % _thousands(WorldSim.population()))
	_perf.text = perf
	_set_target(target_node)
	for b in _order_buttons:
		b.visible = soldiers > 0
	_update_tracker()


## The quest under the card: the tracked radiant quest (its stages as objectives), else the
## first accepted guild commission.
func _update_tracker() -> void:
	var quest := {}
	var rq: Variant = Life.get("radiant")
	if quest_source != null and is_instance_valid(quest_source) and quest_source.has_method("tracked_quest"):
		rq = quest_source
	if rq is Object and (rq as Object).has_method("tracked_quest"):
		var q: Dictionary = (rq as Object).call("tracked_quest")
		if not q.is_empty():
			quest = _radiant_objectives(q)
	if quest.is_empty() and story_tracker.is_valid():   # Region1 hook C7
		quest = story_tracker.call()
	if quest.is_empty():
		for c: Dictionary in Life.guild.active_for(RAAdventurerGuild.PLAYER):
			var req := int(c.get("required", 1))
			var prog := int(c.get("progress", 0))
			quest = {"title": String(c["title"]), "objectives": [{
				"text": "Progress %d / %d" % [prog, req] if req > 1 else "Complete the commission",
				"state": "current"}]}
			break
	var was := tracker.visible
	(tracker as HudCard.QuestTracker).set_quest(quest)
	var sig := "%s|%d" % [tracker.visible, int(tracker.get_combined_minimum_size().y)]
	if sig != _stack_sig or was != tracker.visible:
		_stack_sig = sig
		_layout_left()


static func _radiant_objectives(q: Dictionary) -> Dictionary:
	var stages: Array = q.get("stages", [])
	var cur := int(q.get("stage", 0))
	var rows: Array = []
	for i in stages.size():
		var s: Dictionary = stages[i]
		var txt := String(s.get("text", ""))
		if i == cur:
			match String(s.get("type", "")):
				"gather":
					txt += " (%d/%d)" % [int(q.get("progress", 0)), int(s.get("amount", 1))]
				"kill_den":
					txt += " (%d/%d)" % [int(q.get("progress", 0)), int(s.get("kills", 1))]
		rows.append({"text": txt, "state": "done" if i < cur else ("current" if i == cur else "todo")})
	# Show at most three: the step before, the current one, what follows.
	var start := clampi(cur - 1, 0, maxi(0, rows.size() - 3))
	return {"title": String(q.get("title", "")), "objectives": rows.slice(start, start + 3)}


# --- menus ---------------------------------------------------------------------------

func _menu_style() -> StyleBoxFlat:
	var s := AF.panel(Color(0.043, 0.039, 0.035, 0.95), AF.GOLD, 5, 22)
	s.shadow_size = 24
	return s


## Opens a menu. `source` returns {title, body, options: [[label, Callable() -> String, enabled?]]};
## it is called again after every choice so prices and stock stay current. A dict that also
## has "speaker" is shown as a conversation (dialogue_ui.gd).
func show_menu(source: Callable) -> void:
	if not is_menu_open():
		Audio.play_ui("open")
	_menu_source = source
	_rebuild_menu()


func close_menu() -> void:
	if is_menu_open():
		Audio.play_ui("close")
	_menu.visible = false
	dialogue.visible = false
	_set_chrome_visible(true)


func is_menu_open() -> bool:
	return _menu.visible or dialogue.visible


func _set_chrome_visible(v: bool) -> void:
	_chrome.visible = v
	controls.visible = v
	notifications.visible = v


func _on_dialogue_pick(i: int) -> void:
	if i < 0 or i >= _dlg_options.size():
		return
	var opt: Array = _dlg_options[i]
	var action: Callable = opt[1]
	var msg: Variant = action.call()
	if msg is String and msg != "":
		_say(msg)
	if is_menu_open():
		_rebuild_menu()


func _rebuild_menu() -> void:
	var data: Dictionary = _menu_source.call()
	if data.has("speaker"):
		for child in _menu.get_children():
			child.visible = false
			child.queue_free()
		_menu.visible = false
		_dlg_options = data.get("options", [])
		var was_dialogue_visible := dialogue.visible
		dialogue.set_page(data)
		dialogue.visible = true
		if not was_dialogue_visible:
			dialogue.present()
		_set_chrome_visible(false)
		return
	dialogue.visible = false
	_set_chrome_visible(true)
	for child in _menu.get_children():
		child.visible = false     # stop the outgoing page from sizing the panel
		child.queue_free()
	# Controls grow but never shrink: without this the panel keeps the height of the
	# tallest page shown before and ends up mostly off screen (playtest 03_interact).
	_fit_menu.call_deferred()
	var vw := get_viewport().get_visible_rect().size
	var width := clampf(vw.x * 0.9, 340.0, 560.0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_menu.add_child(box)
	box.add_child(AF.heading(String(data.get("title", "")), 24))
	var body := AF.label(String(data.get("body", "")), 17, AF.TEXT_DIM)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size.x = width
	box.add_child(body)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(width, 0)
	box.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	var options: Array = data.get("options", [])
	for opt: Array in options:
		var btn := Button.new()
		btn.text = opt[0]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(width, 46)
		btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		btn.add_theme_stylebox_override("normal", _menu_row(false))
		btn.add_theme_stylebox_override("hover", _menu_row(true))
		btn.add_theme_stylebox_override("focus", _menu_row(true))
		btn.disabled = opt.size() > 2 and not opt[2]
		var action: Callable = opt[1]
		btn.pressed.connect(func() -> void:
			var msg: Variant = action.call()
			if msg is String and msg != "":
				_say(msg)
			if is_menu_open():
				_rebuild_menu())
		list.add_child(btn)
	scroll.custom_minimum_size.y = minf(options.size() * 52.0, vw.y * 0.45)
	var close := AF.gold_button("Close")
	close.custom_minimum_size = Vector2(width, 44)
	close.pressed.connect(close_menu)
	box.add_child(close)
	_menu.visible = true


func _menu_row(gold: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	if gold:
		s.bg_color = Color(AF.GOLD.r, AF.GOLD.g, AF.GOLD.b, 0.22)
		s.border_color = AF.GOLD
	else:
		s.bg_color = Color(1, 1, 1, 0.035)
		s.border_color = Color(AF.GOLD, 0.25)
	s.set_border_width_all(1)
	s.set_corner_radius_all(3)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s


## Shrink the (centre-anchored) menu panel to its content and keep it centred.
func _fit_menu() -> void:
	# Wait for layout: the autowrapped body label first measures at zero width (one word
	# per line, a very tall minimum) and only settles once it has its real width.
	for i in 2:
		await get_tree().process_frame
	var s := _menu.get_combined_minimum_size()
	# The panel can hold a stale size that its offsets no longer describe, so assigning the
	# same offsets again would be a no-op: set the size itself too.
	_menu.size = s
	_menu.offset_left = -s.x * 0.5
	_menu.offset_right = s.x * 0.5
	_menu.offset_top = -s.y * 0.5
	_menu.offset_bottom = s.y * 0.5


## Compact danger badge: "Safe · Runestone protection", or "Dangerous 41 · Wolf den" when it matters.
func update_danger(t: Dictionary) -> void:
	var total: float = t["total"]
	var lines: Array = t["lines"].duplicate()
	lines.sort_custom(func(a: Array, b: Array) -> bool: return absf(a[1]) > absf(b[1]))
	var label := RAThreatMap.describe(total)
	if total >= 20.0:
		label += " %d" % int(total)
	if not lines.is_empty():
		label += "  ·  " + String(lines[0][0])
	var c := Color("7be0a0").lerp(Color("ff7b5c"), clampf(total / 70.0, 0.0, 1.0))
	(danger_badge as HudCard.DangerBadge).set_danger(label, c)
	_danger_total = total
	_refresh_danger_visibility()


## "Safe" is noise: the badge only shows when the area is dangerous or the status card is open.
func _refresh_danger_visibility() -> void:
	var show := _danger_total >= DANGER_SHOWN or (card as HudCard.Card).expanded
	if show != danger_badge.visible:
		danger_badge.visible = show
		_layout_left()


func _on_card_toggled(expanded: bool) -> void:
	if expanded:
		(tracker as HudCard.QuestTracker).reveal()
	_refresh_danger_visibility()
	_layout_left()


static func _thousands(n: int) -> String:
	var s := str(n)
	var out := ""
	for i in s.length():
		if i > 0 and (s.length() - i) % 3 == 0:
			out += ","
		out += s[i]
	return out


# --- action buttons ----------------------------------------------------------------

## Adds a round touch button and returns it (also kept in the button table under
## `button_name`). `action` is an InputMap action name (the button presses it, like
## the attack button) or a Callable run on press. `icon_name` is an SVG in
## assets/ui/icons/, a PNG in assets/art/icons/ or "glyph:<name>" for a UITheme.glyph
## ("map", "camera", "compass"). By default the button joins the dock next to the utility column;
## pass `anchor` (offset from the bottom-right corner, like the attack cluster)
## to place it yourself. Call after the HUD is in the tree.
##   hud.add_action_button("ride", "Ride", "ride", "walk")
##   hud.add_action_button("lock_on", "Lock", "lock_on", "glyph:lock", UITheme.ACTION_BLOCK, 72, Vector2(330, 200))
func add_action_button(button_name: String, label: String, action: Variant, icon_name := "",
		color := UITheme.ACTION_UTIL, size := DOCK_SIZE, anchor := Vector2.INF) -> TouchScreenButton:
	var res := HudArt.resolve_icon(icon_name)
	var ic: Texture2D = res[0]
	var b := _make_button(action if action is String else "", label, size, color, ic, res[1])
	if action is Callable:
		b.pressed.connect(action)
	if ic != null:
		var cap: Label = b.get_child(0)
		cap.add_theme_font_size_override("font_size", 14)
	var old: Variant = _buttons.get(button_name)
	if old is TouchScreenButton and (_dock.has(old) or _anchored.has(old)):
		remove_action_button(button_name)   # re-adding replaces; built-in buttons are never replaced
	_buttons[button_name] = b
	if anchor == Vector2.INF:
		_dock.append(b)
	else:
		_anchored[b] = anchor
	_layout()
	return b


func remove_action_button(button_name: String) -> void:
	var b: TouchScreenButton = _buttons.get(button_name)
	if b == null:
		return
	_buttons.erase(button_name)
	_dock.erase(b)
	_anchored.erase(b)
	b.queue_free()
	_layout()


func get_action_button(button_name: String) -> TouchScreenButton:
	return _buttons.get(button_name)


# --- navigation: discovery, compass, map, photo mode ---------------------------------

func _build_navigation(root: Control) -> void:
	for pair: Array in [["world_map", KEY_M], ["photo_mode", KEY_P]]:
		if not InputMap.has_action(pair[0]):
			InputMap.add_action(pair[0])
			var ev := InputEventKey.new()
			ev.physical_keycode = pair[1]
			InputMap.action_add_event(pair[0], ev)
	compass = CompassBar.new()
	compass.player = player
	compass.tapped.connect(toggle_map)
	_chrome.add_child(compass)
	banner = DiscoveryBanner.new()
	root.add_child(banner)
	add_action_button("map", "Map", "world_map", "glyph:map", UITheme.ACTION_TALK.darkened(0.15))
	# Photo mode, inventory, crafting and the arts live in the Pack menu (the dock stays
	# short so it never crowds the combat cluster); keys P, K and the pack key still work.


## Map, photo mode and the travel fade sit above the HUD root (not hidden with it).
func _build_overlays() -> void:
	skills_screen = SkillsScreen.new()
	add_child(skills_screen)
	world_map = WorldMap.new()
	world_map.player = player
	world_map.travel_check = _travel_block_reason
	world_map.travel_requested.connect(_on_travel_requested)
	add_child(world_map)
	# Region1 hook H6 (docs/regions/REGION_1_PLAN.md): painted parchment map layer
	parchment = preload("res://scripts/ui/map_parchment_layer.gd").new()
	world_map.add_layer(parchment)
	world_map.closed.connect(parchment.release)      # frees the texture (VRAM) while the map is closed
	photo_mode = PhotoMode.new()
	photo_mode.closed.connect(func() -> void: _root.visible = true)
	photo_mode.screenshot_saved.connect(func(path: String) -> void: print("[photo] saved ", path))
	add_child(photo_mode)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.process_mode = Node.PROCESS_MODE_ALWAYS
	_fade.visible = false
	add_child(_fade)


## The discovery tracker: Life's when Life owns one (so it is saved), else the HUD's.
func get_discovery() -> RefCounted:
	if discovery == null:
		var owned: Variant = Life.get("discovery")
		discovery = owned if owned is RefCounted else Discovery.new()
	if discovery.places.is_empty() and not WorldGen.settlements.is_empty():
		discovery.build_from_world(Life.lore.places_in_region())
	return discovery


## Overrides the compass/map quest marker (Vector2 x/z), or null to go back to
## the accepted guild commission's target.
func set_quest_target(pos: Variant) -> void:
	_quest_override = pos
	_marker_timer = 0.0


func _unhandled_input(event: InputEvent) -> void:
	if _veil() or not visible:
		return
	if event.is_action_pressed("ui_cancel") and fan_open:
		close_fan()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel") and not is_menu_open() and not world_map.visible and not photo_mode.is_active() \
			and not _fade.visible and get_node_or_null("PauseMenu") == null:
		open_pause()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel") and fan_open:
		close_fan()
		get_viewport().set_input_as_handled()
		return
	if not is_menu_open() and event is InputEventKey and not hotbar.visible:
		hotbar.refresh()
	if not is_menu_open() and hotbar.handle_key(event):
		mode.reveal_hotbar()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("menu_inventory") and not (event is InputEventKey and event.echo):
		GameMenu.toggle(self, "inventory")
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("menu_skills") and not (event is InputEventKey and event.echo):
		GameMenu.toggle(self, "skills")
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("world_map"):
		toggle_map()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("photo_mode"):
		open_photo_mode()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		# Esc, gamepad B and the Android back button: close the open list, else pause.
		get_viewport().set_input_as_handled()
		if _menu.visible:
			close_menu()
		else:
			open_pause()


## The pause menu (resume, save, load, settings, photo mode, exit to main menu). Esc, the pause button,
## the Android back button and returning to the app all come here.
func open_pause() -> void:
	if _veil() or not visible or _fade.visible or photo_mode.is_active() or world_map.visible \
			or get_tree().paused or has_node("PauseMenu"):
		return
	close_menu()
	PauseMenu.open(self, open_photo_mode)


func toggle_map() -> void:
	if world_map.visible:
		world_map.close()
		return
	if photo_mode.is_active() or _veil() or _fade.visible:
		return
	close_menu()
	world_map.discovery = get_discovery()
	world_map.quest_target = _quest_target()
	world_map.open()


func open_photo_mode() -> void:
	if photo_mode.is_active() or world_map.visible or _veil() or _fade.visible:
		return
	close_menu()
	_root.visible = false
	photo_mode.open(player)


func _process(delta: float) -> void:
	_plate_timer -= delta
	if _plate_timer <= 0.0:
		_plate_timer = 0.1
		# In-world nameplates hide while a dialogue / menu / GameMenu is up.
		Nameplates.set_suppressed(get_tree(), is_menu_open() or GameMenu.is_open(self))
	if not visible or _veil() or player == null or not player.is_inside_tree():
		return
	_nav_timer -= delta
	if _nav_timer <= 0.0:
		_nav_timer = DISCOVERY_RATE
		_check_discovery()
	_marker_timer -= delta
	if _marker_timer <= 0.0:
		_marker_timer = MARKER_RATE
		_refresh_markers()
	_event_timer -= delta
	if _event_timer <= 0.0:
		_event_timer = EVENT_RATE
		_poll_events()
	_update_dash_button()
	_update_modes(delta)


# --- layout modes: exploration / combat, menu fan, contextual primary action ---------------

var _hostile_near := false
var _hostile_scan := 0.0
var _hb_a := 0.0
var _hb_refresh := 0.0


func _scan_hostiles() -> bool:
	var p := player.global_position
	var range2 := HudMode.ENGAGE_RANGE * HudMode.ENGAGE_RANGE
	for e in get_tree().get_nodes_in_group("team1"):
		if e is Node3D and is_instance_valid(e) and e.get("dead") != true \
				and (e as Node3D).global_position.distance_squared_to(p) < range2:
			return true
	return false


func _update_modes(delta: float) -> void:
	_hostile_scan -= delta
	if _hostile_scan <= 0.0:
		_hostile_scan = 0.2
		_hostile_near = _scan_hostiles()
	var weapon := Input.is_action_pressed("attack") or Input.is_action_pressed("block") or player.blocking
	var was := mode.in_combat()
	mode.update(delta, _hostile_near, weapon)
	if mode.in_combat() != was:
		if mode.in_combat():
			(card as HudCard.Card).set_expanded(false)
			fan_open = false
		_layout()
	var k := 1.0 - exp(-delta * 12.0)
	if _techniques:
		_techniques.fade = mode.eased()
	# Hotbar: only in combat, while building, pinned from the menu, or just after a slot key.
	var want_hb := mode.hotbar_wanted()
	_hb_a = lerpf(_hb_a, 1.0 if want_hb else 0.0, k)
	if absf(_hb_a - (1.0 if want_hb else 0.0)) < 0.01:
		_hb_a = 1.0 if want_hb else 0.0
	hotbar.modulate.a = _hb_a
	hotbar.mouse_filter = Control.MOUSE_FILTER_STOP if _hb_a > 0.5 else Control.MOUSE_FILTER_IGNORE
	hotbar.position.y = _safe.end.y - hotbar.size.y + (1.0 - _hb_a) * 36.0
	hotbar.visible = _hb_a > 0.02
	if not hotbar.visible:
		_hb_refresh -= delta
		if _hb_refresh <= 0.0:
			_hb_refresh = 0.5
			hotbar.refresh()      # keeps the number keys working while the bar is hidden
	# The action pill rides above the primary button.
	var talk := target != null and not mode.in_combat() and not is_menu_open()
	_pill_a = lerpf(_pill_a, 1.0 if talk else 0.0, k)
	if absf(_pill_a - (1.0 if talk else 0.0)) < 0.01:
		_pill_a = 1.0 if talk else 0.0
	_pill.modulate.a = _pill_a
	_pill.visible = _pill_a > 0.03
	_place_pill()
	_ease_buttons(delta)
	if fan_open:
		_menu_open_t -= delta
		if _menu_open_t <= 0.0:
			close_fan()


func _set_target(n: Node3D) -> void:
	var changed := n != target
	target = n
	if n != null:
		var lab := InteractLabel.resolve(n)
		if lab != target_label:
			target_label = lab
			_apply_label()
	if changed:
		_layout()


func _apply_label() -> void:
	_pill.set_label(String(target_label.get("verb", "")), String(target_label.get("target", "")))
	var res := HudArt.resolve_icon(String(target_label.get("icon", "hand")))
	var big := HudArt.round_face(128, _fill_for(UITheme.ACTION_TALK), res[0], res[1], 0.66)
	_interact.texture_normal = big
	_interact.texture_pressed = big
	var small := HudArt.round_face(72, _fill_for(UITheme.ACTION_TALK), res[0], res[1], 0.62)
	_interact_small.texture_normal = small
	_interact_small.texture_pressed = small
	(_interact_small.get_child(0) as Label).text = String(target_label.get("verb", "")).left(9)
	_place_pill()


func toggle_fan() -> void:
	if fan_open:
		close_fan()
	else:
		fan_open = true
		_menu_open_t = MENU_AUTO_CLOSE
		_layout()


func close_fan() -> void:
	if fan_open:
		fan_open = false
		_layout()


func _on_fan_pressed(b: TouchScreenButton) -> void:
	if b == _buttons.get("zoom_in") or b == _buttons.get("zoom_out") or b == _buttons.get("quickbar"):
		_menu_open_t = MENU_AUTO_CLOSE
	else:
		close_fan.call_deferred()


## Shadow Dash cooldown: dim the button and show the seconds left while it
## recharges, like the technique slots' cooldown dim.
func _update_dash_button() -> void:
	var left: float = player.dash_cooldown
	_dash_cooling = left > 0.05
	_dash_cooldown_label.text = "%d" % ceili(left) if _dash_cooling else ""


func _player_xz() -> Vector2:
	return Vector2(player.global_position.x, player.global_position.z)


func _check_discovery() -> void:
	if InteriorDoor.active != null:
		return
	var d := get_discovery()
	for pl: Dictionary in d.update(_player_xz(), WorldSim.day):
		banner.show_place(pl["name"], Discovery.kind_label(String(pl["kind"])))
		if pl["category"] != "settlement":
			notify("location", "Location Discovered", String(pl["name"]))
		place_discovered.emit(pl)
		Life.award_progress("discovery", {"id": String(pl["id"])})   # progression hook
		_reward_discovery(pl)
		_marker_timer = 0.0


## A little experience for finding a place: Life's XP API if it has one, else
## merit (which drives Life.player_level), granted after the banner so the
## "+merit" toast does not talk over it.
func _reward_discovery(pl: Dictionary) -> void:
	var amount := 5 if pl["category"] == "settlement" else 3
	var reason := "discovered %s" % pl["name"]
	get_tree().create_timer(DiscoveryBanner.DURATION * 0.8, false).timeout.connect(func() -> void:
		if Life.has_method("add_xp"):
			Life.call("add_xp", amount * 10, reason)
		elif Life.has_method("add_merit"):
			Life.add_merit(amount, reason))


func _refresh_markers() -> void:
	var d := get_discovery()
	var p := _player_xz()
	var list := []
	var seen := {}
	for pl: Dictionary in d.nearby(p, COMPASS_RANGE):
		seen[pl["id"]] = true
		list.append({"pos": pl["pos"], "kind": pl["kind"], "color": MapIcons.color_for(pl), "hostile": pl["hostile"]})
	for pl: Dictionary in d.nearby(p, HOSTILE_RANGE, true):
		if pl["hostile"] and not seen.has(pl["id"]):
			list.append({"pos": pl["pos"], "kind": pl["kind"], "color": MapIcons.HOSTILE, "hostile": true})
	compass.markers = list
	minimap.markers = list
	var qt: Variant = _quest_target()
	compass.quest_target = qt
	compass.visible = qt != null and not mode.in_combat()      # the minimap covers the rest
	minimap.quest_target = qt


## Where the active objective is: an override, the tracked radiant quest's stage,
## else the first accepted guild
## commission with a place (cull -> its den, deliver/escort -> the destination
## settlement, investigate -> the rumour's location). null when there is none.
func _quest_target() -> Variant:
	if _quest_override is Vector2:
		return _quest_override
	for src: Variant in [quest_source, Life.get("radiant")]:
		if src is Object and is_instance_valid(src) and (src as Object).has_method("active_objective_position"):
			var qp: Variant = (src as Object).call("active_objective_position")
			if qp is Vector2:
				return qp
	if story_target.is_valid():   # Region1 hook C7: a compass hint, never a world marker
		var sp: Variant = story_target.call()
		if sp is Vector2:
			return sp
	for c: Dictionary in Life.guild.active_for(RAAdventurerGuild.PLAYER):
		var t: Dictionary = c.get("target", {})
		match String(c.get("type", "")):
			"cull":
				for den: Dictionary in Frontier.ecology.dens:
					if int(den["id"]) == int(t.get("den", -1)) and den.get("alive", true):
						return den["pos"]
			"deliver", "escort":
				for s: Dictionary in WorldGen.settlements:
					if s["name"] == String(t.get("to", "")):
						return s["pos"]
			"investigate":
				for m: Dictionary in Frontier.threat.modifiers:
					if str(hash(m.get("label", ""))) == String(t.get("rumour", "")) and m.has("pos"):
						return m["pos"]
	return null


## "" when fast travel is allowed, else why not.
func _travel_block_reason() -> String:
	if player.dead:
		return "You cannot travel now."
	if InteriorDoor.active != null:
		return "Step outside first."
	var p := player.global_position
	for e in get_tree().get_nodes_in_group("team1"):
		if e is Node3D and (e as Node3D).global_position.distance_to(p) < COMBAT_RANGE:
			return "Enemies are near. You cannot fast travel during combat."
	return ""


func _on_travel_requested(pos: Vector2, hours: float, place: Dictionary) -> void:
	# The coach (travel_rules.gd): the fare is paid at the stop, and it only runs from a waystation.
	var here := Vector2(player.global_position.x, player.global_position.z)
	var fare := TravelRules.fare(here.distance_to(pos))
	var why := TravelRules.ride_block_reason(TravelRules.waystation_at(here, WorldGen.sites), fare, Game.gold)
	if why != "":
		show_toast(why)
		return
	Game.add_gold(-fare)
	_fade.visible = true
	_fade.color.a = 0.0
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.45)
	await tw.finished
	WorldSim.advance_hours(hours)
	if fast_travel_requested.get_connections().is_empty():
		# Not wired yet: move the player directly (terrain streams in around them).
		player.global_position = Vector3(pos.x, WorldGen.height(pos.x, pos.y) + 0.5, pos.y)
		player.velocity = Vector3.ZERO
	else:
		fast_travel_requested.emit(pos)
	for i in 3:
		await get_tree().process_frame
	_nav_timer = 0.0
	_marker_timer = 0.0
	var tw2 := create_tween()
	tw2.tween_property(_fade, "color:a", 0.0, 0.7)
	await tw2.finished
	_fade.visible = false
	show_toast("Arrived at %s  ·  %s by coach  ·  %d gold" % [place.get("name", "your destination"), WorldMap.fmt_hours(hours), fare])
