class_name SettingsMenu
extends RefCounted
## Settings page for HUD.show_menu(): graphics tier (Auto / Low / Medium / High /
## Ultra), the 30 fps battery saver, and the Credits & Licences screen.
## Opened from the Pack & Journal menu.


static func menu(hud: HUD) -> Dictionary:
	var q := Quality
	var auto_label := "Auto (%s)" % Quality.NAMES[q.tier] if q.choice == Quality.AUTO else "Auto"
	var opts: Array = []
	opts.append([_mark(q.choice == Quality.AUTO) + auto_label, func() -> String:
		Quality.set_choice(Quality.AUTO)
		return "Graphics: Auto picks the best setting for this device."])
	for t in Quality.NAMES.size():
		opts.append([_mark(q.choice == t) + Quality.NAMES[t], func() -> String:
			Quality.set_choice(t)
			return "Graphics: %s" % Quality.NAMES[t]])
	opts.append([("☑ " if q.battery_saver else "☐ ") + "Battery saver (30 fps)", func() -> String:
		Quality.set_battery_saver(not Quality.battery_saver)
		return "Battery saver on: 30 fps." if Quality.battery_saver else "Battery saver off."])
	opts.append(["Credits & Licences", func() -> String:
		hud.close_menu()
		CreditsScreen.open(hud)
		return ""])
	var body := "Graphics: %s   ·   %s renderer\nLow suits older phones; Ultra is the full desktop look." % [
		Quality.tier_name(), {"forward_plus": "Forward+", "mobile": "Mobile", "gl_compatibility": "Compatibility"}.get(Quality.renderer(), Quality.renderer())]
	return {"title": "Settings", "body": body, "options": opts}


static func _mark(on: bool) -> String:
	return "● " if on else "○ "
