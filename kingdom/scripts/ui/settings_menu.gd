class_name SettingsMenu
extends RefCounted
## Old Pack & Journal "Settings" page. There is now ONE settings screen
## (scripts/ui/frontend/settings_screen.gd, also used by the main menu and the
## pause menu); this page only forwards to it and to the Credits screen.

const SettingsScreen := preload("res://scripts/ui/frontend/settings_screen.gd")


static func menu(hud: HUD) -> Dictionary:
	var opts: Array = []
	opts.append(["Open Settings", func() -> String:
		hud.close_menu()
		SettingsScreen.open(hud, true)
		return ""])
	opts.append(["Credits & Licences", func() -> String:
		hud.close_menu()
		CreditsScreen.open(hud)
		return ""])
	var body := "Graphics: %s   ·   %s renderer\nGraphics, audio, gameplay, controls, language and accessibility live in the Settings screen." % [
		Quality.tier_name(), {"forward_plus": "Forward+", "mobile": "Mobile", "gl_compatibility": "Compatibility"}.get(Quality.renderer(), Quality.renderer())]
	return {"title": "Settings", "body": body, "options": opts}
