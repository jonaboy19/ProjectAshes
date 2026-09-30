extends RefCounted
## Persistent player settings for the ONE settings screen (user://settings.cfg).
## Graphics tier + battery saver stay owned by `Quality` ([graphics]); everything
## else lives in [display] [audio] [gameplay] [access] [controls] and is applied
## by apply_all() (called at boot and after "Apply").
##   const SS := preload("res://scripts/ui/frontend/settings_store.gd")
##   SS.get_value("cam_sens")   # read from anywhere in game code

const PATH := "user://settings.cfg"

const RES_OPTIONS := ["1280 x 720", "1600 x 900", "1920 x 1080", "2560 x 1440"]
const LEVELS := ["Low", "Medium", "High", "Ultra"]
## View Distance / Shadows / Textures / Effects: 0 = follow the graphics preset, 1..4 = Low..Ultra
## (Quality.set_overrides). Saves from before the "Auto" entry stored 0..3 and are read as Auto.
const LEVEL_KEYS := ["view_distance", "shadows", "textures", "effects"]
const LEVEL_OPTIONS := ["Auto", "Low", "Medium", "High", "Ultra"]
const DEFAULTS := {
	"resolution": 0, "display_mode": 0, "vsync": 1, "aa": 1, "view_distance": 0, "shadows": 0,
	"textures": 0, "effects": 0, "fps_limit": 1,
	"vol_master": 80, "vol_music": 70, "vol_sfx": 80, "vol_ambience": 75, "vol_voice": 85,
	"difficulty": 1, "cam_sens": 50, "invert_y": false, "subtitles": true,
	"hud_minimap": true, "hud_quests": true, "hud_compass": true, "hud_damage": true,
	"language": 0, "text_size": 1, "colorblind": 0, "screen_shake": 2,
	"render_scale": 100, "joystick_size": 50, "vibration": true,
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
]


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


static func get_value(key: String) -> Variant:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return DEFAULTS.get(key)
	return cf.get_value(section_of(key), key, DEFAULTS.get(key))


## Reads every key (DEFAULTS + the Quality-owned preset) into one Dictionary.
static func read_all(tree: SceneTree) -> Dictionary:
	var cf := ConfigFile.new()
	cf.load(PATH)
	var out := {}
	for k: String in DEFAULTS:
		out[k] = cf.get_value(section_of(k), k, DEFAULTS[k])
	var lv := levels_from_config(cf)
	for i in LEVEL_KEYS.size():
		out[LEVEL_KEYS[i]] = lv[i] + 1
	var q := tree.root.get_node_or_null("Quality")
	if q:
		out["preset"] = int(q.get("choice")) + 1     # 0 Auto, 1..4 Low..Ultra
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
	cf.save(PATH)


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
	# Frame cap: 30 = battery saver (Quality), 60 / unlimited via Engine.max_fps.
	if q:
		var fps := int(vals["fps_limit"])
		q.call("set_battery_saver", fps == 0)
		apply_levels(tree, vals)
		if fps == 1:
			Engine.max_fps = 60
		elif fps == 2 and not is_mobile():
			Engine.max_fps = 0
	# Anti-aliasing on any 3D viewport.
	var aa := int(vals["aa"])
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


## Re-applies saved key rebinds ([controls] action = physical keycode).
static func apply_controls() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK or not cf.has_section("controls"):
		return
	for key: String in cf.get_section_keys("controls"):
		set_binding(key, int(cf.get_value("controls", key)), false)


static func binding_text(action: String) -> String:
	if not InputMap.has_action(action):
		return "-"
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			var k := ev as InputEventKey
			var code: Key = k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
			return OS.get_keycode_string(DisplayServer.keyboard_get_keycode_from_physical(code))
	return "-"


## Replaces the first keyboard binding of `action` with `keycode` (physical).
static func set_binding(action: String, keycode: int, save := true) -> void:
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
	if save:
		var cf := ConfigFile.new()
		cf.load(PATH)
		cf.set_value("controls", action, keycode)
		cf.save(PATH)


static func reset_controls() -> void:
	var cf := ConfigFile.new()
	cf.load(PATH)
	if cf.has_section("controls"):
		cf.erase_section("controls")
		cf.save(PATH)
