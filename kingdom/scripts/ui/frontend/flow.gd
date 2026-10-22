extends RefCounted
## Shared front-end state (no autoload needed: static vars live for the whole run).
## Preload:  const Flow := preload("res://scripts/ui/frontend/flow.gd")
##
## In-game hooks (owned by main.gd / hud.gd, see the front-end report):
##   Flow.exit_to_menu(get_tree())     - "Exit to Main Menu" (back to boot at the menu)
##   Flow.mode / Flow.creation         - the New Game choices for Life/main to read
##   Flow.wants_skip_intro()           - main.gd: skip the birth cutscene when loading a save

const BOOT_SCENE := "res://scenes/boot.tscn"
const MAIN_SCENE := "res://scenes/main.tscn"
const CHAR_CREATION := "res://scripts/ui/character_creation.gd"

## New Game choice: "story" | "sandbox" | "survival" | "custom".
static var mode := "story"
## Dictionary handed back by character creation ({} if skipped).
static var creation := {}
## Save slot id to load once the world exists ("" = none / new game).
static var pending_load := ""
## Boot goes straight to the main menu (after Exit to Main Menu).
static var skip_splash := false
## Tip index the front-end loading screen was showing, so the in-game world veil continues with the same tip.
static var handoff_tip := -1
## A world has been played in this run; Life/WorldSim hold its state.
static var world_dirty := false


## True when the game was launched by QA tooling / tests: boot must not show menus.
static func is_qa_launch() -> bool:
	if DisplayServer.get_name() == "headless":
		return true
	if not OS.get_cmdline_user_args().is_empty():
		return true
	for a in OS.get_cmdline_args():
		if a == "--headless" or a == "--skipintro" or a == "--skip-intro" or a == "--demo" or a == "--adult":
			return true
	return false


static func wants_skip_intro() -> bool:
	return pending_load != ""


static func version_text() -> String:
	var v := String(ProjectSettings.get_setting("application/config/version", ""))
	return v if v != "" else "0.1.0"


static func is_mobile() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")


## Kept for the boot flow: a new run no longer needs a snapshot of the untouched state,
## Life.reset() rebuilds it (see reset_world_state).
static func capture_pristine(_tree: SceneTree) -> void:
	pass


## After a world has been played (world_dirty): everything the run owned goes back to a fresh
## new game (Life.reset: Game, WorldSim, Frontier, Region 1, Life.realm and every Life system).
## Call before New Game / Load Game so they start from a clean state.
static func reset_world_state(tree: SceneTree) -> void:
	if not world_dirty:
		return
	var life := tree.root.get_node_or_null("Life")
	if life and life.has_method("reset"):
		life.call("reset")
	world_dirty = false


## Back to the boot scene, straight at the main menu.
static func exit_to_menu(tree: SceneTree) -> void:
	tree.paused = false
	skip_splash = true
	pending_load = ""
	world_dirty = true
	tree.change_scene_to_file(BOOT_SCENE)


## Called right before main.tscn is entered from the menus.
static func enter_game(tree: SceneTree) -> void:
	world_dirty = true
	if pending_load == "":
		return
	var w := Node.new()
	w.set_script(preload("res://scripts/ui/frontend/load_watcher.gd"))
	w.set("slot_id", pending_load)
	tree.root.add_child.call_deferred(w)


static func character_creation_available() -> bool:
	return ResourceLoader.exists(CHAR_CREATION)
