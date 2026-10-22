class_name TerrainBackend
extends RefCounted
## Which ground and vegetation pipeline the world uses.
##   "legacy"    (default) TerrainStreamer's own 64 m chunk meshes + MultiMesh trees/undergrowth + GrassField. Untouched.
##   "terrain3d" Terrain3D (TokisanGames, MIT) draws the ground from heightmaps generated out of WorldGen, and ProtonScatter
##               (HungryProton, MIT) places the forest, undergrowth and rocks. WorldGen stays the single source of truth for
##               height, so navigation, building, founding, collision and saves are unchanged.
## Resolution order: `override` (tests) -> command line `--terrain_backend=terrain3d` -> env ASHES_TERRAIN_BACKEND ->
## user://settings.cfg [world] terrain_backend -> "legacy". Falls back to legacy when the Terrain3D GDExtension is not loaded.
## Docs: docs/LOCAL_SESSION_HANDOFF.md ("Terrain3D + ProtonScatter backend").

const LEGACY := "legacy"
const TERRAIN3D := "terrain3d"
const SETTINGS_PATH := "user://settings.cfg"

## Tests set this ("" = off). Not saved.
static var override := ""
static var _cached := ""


static func mode() -> String:
	var want := override
	if want == "":
		if _cached == "":
			_cached = _resolve()
		want = _cached
	if want == TERRAIN3D and not available():
		return LEGACY
	return want if want == TERRAIN3D else LEGACY


static func is_terrain3d() -> bool:
	return mode() == TERRAIN3D


## True when the Terrain3D GDExtension and the ProtonScatter scripts are present and loaded.
static func available() -> bool:
	return ClassDB.class_exists("Terrain3D") and ResourceLoader.exists("res://addons/proton_scatter/src/scatter.gd")


static func set_mode(m: String) -> void:
	_cached = TERRAIN3D if m == TERRAIN3D else LEGACY
	var cf := ConfigFile.new()
	cf.load(SETTINGS_PATH)
	cf.set_value("world", "terrain_backend", _cached)
	cf.save(SETTINGS_PATH)


static func _resolve() -> String:
	for a in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if a.begins_with("--terrain_backend="):
			return a.get_slice("=", 1).strip_edges().to_lower()
	var env := OS.get_environment("ASHES_TERRAIN_BACKEND").strip_edges().to_lower()
	if env != "":
		return env
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) == OK:
		return String(cf.get_value("world", "terrain_backend", LEGACY)).to_lower()
	return LEGACY
