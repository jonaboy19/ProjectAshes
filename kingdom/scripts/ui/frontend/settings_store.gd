extends RefCounted
## Persistent player settings for the ONE settings screen (user://settings.cfg).
## Graphics tier + battery saver stay owned by `Quality` ([graphics]); everything
## else lives in [display] [audio] [gameplay] [access] [controls] and is applied
## by apply_all() (called at boot and after "Apply").
##   const SS := preload("res://scripts/ui/frontend/settings_store.gd")
##   SS.get_value("cam_sens")   # read from anywhere in game code

const PATH := "user://settings.cfg"
## Tests point the [controls] section at a scratch file (set back to "" afterwards).
static var controls_path_override := ""
## Keys a rebind may never take: Esc cancels the capture and always opens the pause menu.
const RESERVED_KEYS := [KEY_ESCAPE]
## Actions that share digit keys on purpose (hotbar / army orders / hand seals; see tests/test_controls_scheme.gd).
const CONTEXTUAL_PREFIXES := ["order_", "seal_"]

const RES_OPTIONS := ["1280 x 720", "1600 x 900", "1920 x 1080", "2560 x 1440"]
const LEVELS := ["Low", "Medium", "High", "Ultra"]
## View Distance / Shadows / Textures / Effects: 0 = follow the graphics preset, 1..4 = Low..Ultra
## (Quality.set_overrides). Saves from before the "Auto" entry stored 0..3 and are read as Auto.
const LEVEL_KEYS := ["view_distance", "shadows", "textures", "effects"]
const LEVEL_OPTIONS := ["Auto", "Low", "Medium", "High", "Ultra"]
const DEFAULTS := {
	"resolution": 0, "display_mode": 0, "vsync": 1, "aa": 1, "view_distance": 0, "shadows": 0,
	"textures": 0, "effects": 0, "fps_limit": 3,
	"vol_master": 80, "vol_music": 70, "vol_sfx": 80, "vol_ambience": 75, "vol_voice": 85,
	"difficulty": 1, "cam_sens": 50, "invert_y": false, "subtitles": true,
	"hud_minimap": true, "hud_quests": true, "hud_compass": true, "hud_damage": true,
	"language": 0, "text_size": 1, "colorblind": 0, "screen_shake": 2,
	"render_scale": 100, "joystick_size": 50, "vibration": true, "tutorial_tips": true,
	"cast_camera": true, "dev_sim_overlay": false, "talk_camera": true, "wheel_slow": true, "auto_vault": true,
}
const SECTION := {
	"resolution": "display", "display_mode": "display", "vsync": "display", "aa": "display",
	"view_distance": "display", "shadows": "display", "textures": "display", "effects": "display",
	"fps_limit": "display", "render_scale": "display", "language": "gameplay", "text_size": "access", "colorblind": "access",
	"screen_shake": "access",
}
const BUSES := {"vol_master": "Master", "vol_music": "Music", "vol_sfx": "SFX", "vol_ambience": "Ambience",
	"vol_voice": "Voice"}
const TEXT_SCALE := [0.9, 1.0, 1.15, 1.3]

## Rebindable actions: [action, label].
const ACTIONS := [
	["move_forward", "Move Forward"], ["move_back", "Move Back"], ["move_left", "Move Left"],
	["move_right", "Move Right"], ["sprint", "Sprint"], ["jump", "Jump"], ["dodge", "Dodge"], ["attack", "Attack"],
	["block", "Block"], ["interact", "Interact / Talk"], ["eat", "Eat"], ["view_cycle", "Change View"],
	["journal", "Menu / Journal"], ["world_map", "World Map"], ["photo_mode", "Photo Mode"],
	["quick_save", "Quick Save"], ["quick_load", "Quick Load"], ["lock_on", "Lock On"], ["crouch", "Crouch / Sneak"],
	["ability_dash", "Shadow Dash"], ["menu_inventory", "Inventory"], ["menu_skills", "Skills"],
	["menu_treasury", "Treasury"], ["menu_followers", "Followers"], ["menu_court", "Court"], ["menu_letters", "Letters"],
	["technique_wheel", "Technique Wheel"], ["technique_1", "Technique 1"], ["technique_2", "Technique 2"],
	["technique_3", "Technique 3"], ["technique_4", "Technique 4"], ["zoom_in", "Camera Zoom In"], ["zoom_out", "Camera Zoom Out"],
]
## Section headers of the Controls tab: the first action of each block -> its title.
const ACTION_GROUPS := {
	"move_forward": "Movement", "attack": "Combat", "interact": "World", "journal": "Menus", "technique_wheel": "Techniques",
}


## The four level rows from a loaded config as Quality overrides (-1 = follow the preset).
static func levels_from_config(cf: ConfigFile) -> Array[int]:
	var out: Array[int] = []
	var fresh := bool(cf.get_value("display", "levels_v2", false))
	for k: String in LEVEL_KEYS:
		var v := int(cf.get_value("display", k, 0)) if fresh else 0
		out.append(clampi(v, 0, 4) - 1)
	return out


static func section_of(key: String) -> String:
	if BUSES.has(key):
		return "audio"
	return String(SECTION.get(key, "gameplay"))


## get_value() is called from per-physics-tick code (the chase camera asks three settings every tick), so it must not parse
## the cfg from disk each call (measured: 3.7 ms per tick, ~220 ms of every second at 60 Hz). The parsed file is cached and
## re-checked against its modified time at most every 250 ms (other writers, e.g. Quality, are picked up); our own writers
## drop the cache at once.
static var _cache: ConfigFile = null
static var _cache_ok := false
static var _cache_check_ms := -100000
static var _cache_mtime := -1
static var _cache_lock := Mutex.new()      # get_value is also reached from worker threads: one reader/reloader at a time


static func invalidate_cache() -> void:
	_cache_lock.lock()
	_cache = null
	_cache_check_ms = -100000
	_cache_lock.unlock()


static func _cached() -> ConfigFile:
	var now := Time.get_ticks_msec()
	if _cache == null or now - _cache_check_ms >= 250:
		_cache_check_ms = now
		var mt := FileAccess.get_modified_time(PATH)
		if _cache == null or mt != _cache_mtime:
			_cache_mtime = mt
			_cache = ConfigFile.new()
			_cache_ok = _cache.load(PATH) == OK
	return _cache if _cache_ok else null


static func get_value(key: String) -> Variant:
	if preload("res://scripts/core/perf_probe.gd").legacy:
		var old := ConfigFile.new()
		if old.load(PATH) != OK:
			return DEFAULTS.get(key)
		return old.get_value(section_of(key), key, DEFAULTS.get(key))
	_cache_lock.lock()
	var cf := _cached()
	var v: Variant = DEFAULTS.get(key) if cf == null else cf.get_value(section_of(key), key, DEFAULTS.get(key))
	_cache_lock.unlock()
	return v


## Reads every key (DEFAULTS + the Quality-owned preset) into one Dictionary.
static func read_all(tree: SceneTree) -> Dictionary:
	var cf := ConfigFile.new()
	cf.load(PATH)
	var out := {}
	for k: String in DEFAULTS:
		out[k] = cf.get_value(section_of(k), k, DEFAULTS[k])
	# fps_limit 3 = Auto (tier cap + thermal guard), the default since 2026-10-05. Older saves
	# stored the old default 1 (60), which overrode LOW's 30 cap on phones: read those as Auto.
	if not bool(cf.get_value("display", "fps_v2", false)) and int(out["fps_limit"]) == 1:
		out["fps_limit"] = 3
	var lv := levels_from_config(cf)
	for i in LEVEL_KEYS.size():
		out[LEVEL_KEYS[i]] = lv[i] + 1
	var q := tree.root.get_node_or_null("Quality")
	if q:
		out["preset"] = int(q.get("choice")) + 1     # 0 Auto, 1..4 Low..Ultra
		# PC: the AA row is Auto/FXAA/TAA/FSR 2. Saves from before it (default 1 = FXAA, 2/3 = MSAA) read as Auto.
		if bool(q.call("is_pc")) and not bool(cf.get_value("display", "aa_pc", false)):
			out["aa"] = 0
	else:
		out["preset"] = 0
	return out


static func write_all(vals: Dictionary) -> void:
	var cf := ConfigFile.new()
	cf.load(PATH)                     # keep [graphics] and any other sections
	for k: String in DEFAULTS:
		if vals.has(k):
			cf.set_value(section_of(k), k, vals[k])
	cf.set_value("display", "levels_v2", true)
	cf.set_value("display", "aa_pc", true)
	cf.set_value("display", "fps_v2", true)
	cf.save(PATH)
	invalidate_cache()


## Applies everything that can be applied outside a running world.
static func apply_all(tree: SceneTree, vals := {}, with_preset := false) -> void:
	if vals.is_empty():
		vals = read_all(tree)
	for k: String in BUSES:
		apply_volume(k, int(vals.get(k, DEFAULTS[k])))
	var win := tree.root
	if not is_mobile():
		match int(vals["display_mode"]):
			0:
				win.mode = Window.MODE_WINDOWED
				win.borderless = false
			1:
				win.mode = Window.MODE_EXCLUSIVE_FULLSCREEN
			2:
				win.mode = Window.MODE_FULLSCREEN
		if win.mode == Window.MODE_WINDOWED and DisplayServer.get_name() != "headless":
			var parts := String(RES_OPTIONS[int(vals["resolution"])]).split(" x ")
			win.size = Vector2i(int(parts[0]), int(parts[1]))
	DisplayServer.window_set_vsync_mode([DisplayServer.VSYNC_DISABLED, DisplayServer.VSYNC_ENABLED,
		DisplayServer.VSYNC_ADAPTIVE][clampi(int(vals["vsync"]), 0, 2)])
	win.content_scale_factor = float(TEXT_SCALE[clampi(int(vals["text_size"]), 0, 3)])
	var q := tree.root.get_node_or_null("Quality")
	if with_preset and q and vals.has("preset"):
		q.call("set_choice", int(vals["preset"]) - 1)
	# Frame cap: 30 = battery saver (Quality), 60 / unlimited via Engine.max_fps, 3 = Auto
	# (the tier's own cap: LOW 30, MEDIUM/HIGH 60). The thermal guard runs for 60 and Auto.
	if q:
		var fps := int(vals["fps_limit"])
		q.set("thermal_guard", fps == 1 or fps == 3)
		q.call("set_battery_saver", fps == 0)
		apply_levels(tree, vals)
		if fps == 1:
			Engine.max_fps = 60
		elif fps == 2 and not is_mobile():
			Engine.max_fps = 0
	# Anti-aliasing on any 3D viewport.
	var aa := int(vals["aa"])
	if q and bool(q.call("is_pc")):
		q.call("set_aa_mode", aa)     # PC: FSR2 / TAA / FXAA live in Quality; never write MSAA over FSR 2
	else:
		for v in tree.root.find_children("*", "SubViewport", true, false):
			var sv := v as SubViewport
			sv.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if aa == 1 else Viewport.SCREEN_SPACE_AA_DISABLED
			sv.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][clampi(aa, 0, 3)]
	apply_controls()
	var app := tree.root.get_node_or_null("App")
	if app:
		app.call("refresh", vals)


## View distance, shadows, textures and effects rows -> Quality (live, also at boot).
static func apply_levels(tree: SceneTree, vals: Dictionary) -> void:
	var q := tree.root.get_node_or_null("Quality")
	if q == null:
		return
	var l: Array[int] = []
	for k: String in LEVEL_KEYS:
		l.append(clampi(int(vals.get(k, DEFAULTS[k])), 0, 4) - 1)
	q.call("set_overrides", l[0], l[1], l[2], l[3])


static func is_mobile() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")


static func apply_volume(key: String, pct: int) -> void:
	var idx := AudioServer.get_bus_index(String(BUSES[key]))
	if idx < 0:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(clampf(pct / 100.0, 0.0, 1.0)) if pct > 0 else -80.0)
	AudioServer.set_bus_mute(idx, pct <= 0)


## Re-applies saved key rebinds ([controls] action = physical keycode). Saved rebinds were validated when made, so a
## swap (A takes B's key, B takes A's) loads without tripping the conflict check.
static func apply_controls() -> void:
	var cf := ConfigFile.new()
	var path := controls_path()
	if cf.load(path) != OK or not cf.has_section("controls"):
		return
	for key: String in cf.get_section_keys("controls"):
		_apply_binding(key, int(cf.get_value("controls", key)))


static func controls_path() -> String:
	return controls_path_override if controls_path_override != "" else PATH


## First keyboard key of the action as text ("E"), "-" when it has none.
static func binding_text(action: String) -> String:
	if not InputMap.has_action(action):
		return "-"
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			var k := ev as InputEventKey
			return preload("res://scripts/ui/input_glyphs.gd").key_text(k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode)
	return "-"


## The other action that already owns `keycode` ("" = free). Hotbar / order / seal digits may be shared.
static func conflict_for(action: String, keycode: int) -> String:
	for a: Array in ACTIONS + [["order_follow", ""], ["order_hold", ""], ["order_charge", ""], ["order_retreat", ""],
			["order_formation", ""], ["seal_1", ""], ["seal_2", ""], ["seal_3", ""], ["seal_4", ""], ["seal_5", ""], ["seal_6", ""]]:
		var other := String(a[0])
		if other == action or not InputMap.has_action(other):
			continue
		if _contextual(action) and _contextual(other):
			continue
		for ev in InputMap.action_get_events(other):
			if ev is InputEventKey:
				var k := ev as InputEventKey
				if (k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode) == keycode:
					return other
	return ""


static func _contextual(action: String) -> bool:
	for p: String in CONTEXTUAL_PREFIXES:
		if action.begins_with(p):
			return true
	return false


## Why `keycode` cannot go on `action`: "" = it can, "reserved", or "conflict:<other action>".
static func bind_problem(action: String, keycode: int) -> String:
	if not InputMap.has_action(action):
		return "unknown"
	if RESERVED_KEYS.has(keycode):
		return "reserved"
	var other := conflict_for(action, keycode)
	return "conflict:" + other if other != "" else ""


## Rebinds the action's first keyboard key and saves it. Returns "" on success, else bind_problem()'s reason (nothing changes).
## `swap` moves the key's old owner onto this action's old key instead of refusing.
static func try_bind(action: String, keycode: int, swap := false) -> String:
	var problem := bind_problem(action, keycode)
	if problem.begins_with("conflict:") and swap:
		var other := problem.substr(9)
		var mine := _first_key(action)
		_apply_binding(action, keycode)
		_save_binding(action, keycode)
		if mine != KEY_NONE:
			_apply_binding(other, mine)
			_save_binding(other, mine)
		return ""
	if problem != "":
		return problem
	_apply_binding(action, keycode)
	_save_binding(action, keycode)
	return ""


static func _first_key(action: String) -> int:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			var k := ev as InputEventKey
			return k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
	return KEY_NONE


## Replaces the first keyboard binding of `action` with `keycode` (physical); no checks.
static func _apply_binding(action: String, keycode: int) -> void:
	if not InputMap.has_action(action):
		return
	var replaced := false
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey and not replaced:
			InputMap.action_erase_event(action, ev)
			replaced = true
	var nk := InputEventKey.new()
	nk.physical_keycode = keycode as Key
	InputMap.action_add_event(action, nk)


static func _save_binding(action: String, keycode: int) -> void:
	var cf := ConfigFile.new()
	var path := controls_path()
	cf.load(path)
	cf.set_value("controls", action, keycode)
	cf.save(path)
	invalidate_cache()


## Back to the shipped defaults (Game.KEYS / Game.PADS): drops the saved rebinds and re-creates every action.
static func reset_controls() -> void:
	var cf := ConfigFile.new()
	var path := controls_path()
	cf.load(path)
	if cf.has_section("controls"):
		cf.erase_section("controls")
		cf.save(path)
		invalidate_cache()
	Engine.get_main_loop().root.get_node("Game").call("_setup_input")
