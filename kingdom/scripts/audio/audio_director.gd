extends Node
## AudioDirector: music, ambience beds, spot sounds, footsteps, creature voices and
## UI sounds for Rising Ashes, cheap enough for phones.
##
## Drop-in replacement for the old `Audio` autoload (same API: `listener`,
## `set_mood()`, `sfx()`), so it is wired with one line in project.godot:
##     Audio="*res://scripts/audio/audio_director.gd"
## Everything else it needs it finds by itself:
##   - location: InteriorDoor.active (inn / smithy / healer / guild / house), monster
##     camps (WorldGen.camp_grounds), settlements, forest density, water, threat;
##   - time of day: WorldSim.time_of_day (+ hour_changed for the town bell);
##   - footsteps: the "player" node's movement + WorldGen.color_at() ground weights
##     (cobble / dirt / rock / forest floor / grass), wood or stone inside interiors;
##   - creature voices: polls health of nearby combatants (hurt / death) and lets
##     them vocalise now and then (goblin chatter, wolf growl, orc roar...);
##   - UI: every BaseButton that enters the tree clicks; Game gold/rank changes
##     play coin / level-up.
## Sounds live in res://assets/audio/<category>/<name>_NN.ogg; a name without the
## _NN suffix picks a random variant ("hit_flesh" -> hit_flesh_01..05).
##
## Adaptive music (adaptive_music.gd + music_bank.gd): one AudioStreamInteractive
## with a clip per mood (town day / night, wilderness, wild night, danger, combat,
## boss, tavern, silence), bar- or beat-synced crossfades, and AudioStreamSynchronized
## percussion stems that rise with threat (Frontier threat, camps, stalking monsters).
## Stingers (combat, victory, discovery) play over the score while it dips.
## Environment (environment_audio.gd): wind / rain / thunder hooks for the weather
## system, birds by day and crickets by night by forest density, per-room reverb,
## muffled weather indoors, low-pass underwater. Buses: audio_buses.gd (runtime).
##
## Public hooks for other systems (all safe to call at any time):
##   weather: set_weather(kind), set_weather_intensity(0..1) / set_rain(0..1),
##            set_wind(strength, 1 = calm .. 2.4 = storm), thunder(delay_s),
##            play_sfx("thunder", null, vol) also works (near / far variant by vol).
##   combat:  set_mood("battle") every tick while fighting (main.gd does), set_boss(on),
##            play_victory(), play_discovery(), set_music_intensity(0..1) override.
##   misc:    set_underwater(on) override (auto-detected from the listener otherwise).
##
## Phone budget: max 12 positional SFX voices (oldest stolen), 3 ambience spot
## voices, 2 footstep voices, 4 UI voices. Long streams: 1-2 ambience bed (crossfade),
## music base + stem (2), wind or rain (1, 2 briefly), so ~4 decoding at once.
## Streams are OGG Vorbis (decoded on the fly); silence is a 4 KB WAV.

const AudioBuses := preload("res://scripts/audio/audio_buses.gd")
const MusicBank := preload("res://scripts/audio/music_bank.gd")
const AdaptiveMusic := preload("res://scripts/audio/adaptive_music.gd")
const EnvironmentAudio := preload("res://scripts/audio/environment_audio.gd")

const ROOT := "res://assets/audio/"
const MAX_SFX_VOICES := 12
const MAX_UI_VOICES := 4
const MAX_DISTANCE := 45.0
## Beyond this, one-shots go through the SFXFar bus (extra air-absorption low-pass).
const FAR_DISTANCE := 24.0
const BED_FADE := 2.5
## Music moods: threat (Frontier.threat_at total, 0..100) where the drums start / where
## the score moves to the danger clip.
const THREAT_LAYER_START := 15.0
const THREAT_DANGER := 50.0
const COMBAT_HOLD := 6.0
## A combatant this tough (or flagged is_boss / in group "boss") makes combat a boss fight.
const BOSS_HEALTH := 200

## Bed name -> volume offset (dB) on top of the -24 LUFS files.
const BEDS := {
	"village_day": 0.0, "village_night": 0.0, "meadow_day": -2.0, "forest_day": 0.0, "forest_night": 0.0,
	"creek": 0.0, "danger": 1.0, "camp": 1.0, "tavern": 0.0, "smithy": 3.0, "healer": -1.0,
	"house": -4.0, "guild": -5.0, "wind": 0.0, "scar_rift": 0.0,
}
## Which file plays for a bed (several beds share recordings).
const BED_FILE := {
	"village_day": "amb_village_day", "village_night": "amb_village_night", "meadow_day": "amb_meadow_day",
	"forest_day": "amb_forest_day", "forest_night": "amb_forest_night", "creek": "amb_creek",
	"danger": "amb_danger", "camp": "amb_camp", "tavern": "amb_tavern", "smithy": "amb_smithy",
	"healer": "amb_healer", "house": "amb_healer", "guild": "amb_tavern", "wind": "amb_wind",
	"scar_rift": "region1/amb_r1_scar_rift_loop",   # Region 1 (C12): the corrupted ground hums
}
## Spot sounds sprinkled around the listener per bed: [name, weight, volume_db].
const SPOTS := {
	"village_day": [["rooster", 1, -4.0], ["chicken_cluck", 3, -6.0], ["dog_distant", 2, -6.0],
		["hammer_distant", 3, -8.0], ["well_bucket", 2, -8.0], ["sheep", 1, -10.0], ["cow_far", 1, -12.0]],
	"meadow_day": [["bird_blackbird", 3, -6.0], ["sheep", 1, -12.0], ["cow_far", 1, -14.0]],
	"village_night": [["owl", 3, -6.0], ["dog_distant", 2, -10.0]],
	"forest_day": [["bird_blackbird", 4, -4.0], ["wolf_howl_distant", 1, -16.0]],
	"forest_night": [["owl", 3, -5.0], ["wolf_howl_distant", 2, -9.0]],
	"creek": [["bird_blackbird", 2, -6.0]],
	"danger": [["growl_distant", 3, -6.0], ["wolf_howl_distant", 2, -7.0]],
	"camp": [["growl_distant", 2, -8.0], ["goblin_chatter", 2, -14.0]],
	"tavern": [["glass_clink", 3, -8.0], ["mug_knock", 3, -6.0]],
	"smithy": [["anvil", 6, -2.0], ["bellows", 2, -6.0]],
	"healer": [["page_turn", 3, -6.0]],
	"house": [["page_turn", 1, -10.0]],
	"guild": [["page_turn", 2, -8.0], ["mug_knock", 1, -10.0]],
}
## Old Audio.sfx() kinds -> new sound names.
const LEGACY := {"swing": "swing", "hit": "hit_flesh", "clash": "block", "bell": "bell_tower"}
## Creature species -> idle, hurt, death sound names (falls back to monster_*).
const CREATURES := {
	"wolf": ["wolf_growl", "wolf_hurt", "wolf_death"],
	"goblin": ["goblin_chatter", "goblin_hurt", "goblin_death"],
	"orc": ["orc_roar", "orc_hurt", "monster_death"],
	"troll": ["bear_growl", "orc_hurt", "monster_death"],
	"boar": ["boar_grunt", "boar_squeal", "boar_squeal"],
	"bear": ["bear_growl", "bear_roar", "monster_death"],
	"spider": ["spider_hiss", "spider_hiss", "monster_death"],
	"wyvern": ["wyvern_screech", "wyvern_screech", "monster_death"],
}
## Village animals (Critter.kind) -> voices, picked at random now and then when close.
const ANIMALS := {
	"chicken": ["chicken_cluck", "chicken_01"], "rooster": ["rooster", "chicken_cluck"], "dog": ["dog_bark"],
	"sheepdog": ["dog_bark"], "cow": ["cow"], "ox": ["cow"], "sheep": ["sheep"], "pig": ["pig"], "goat": ["goat"],
	"horse": ["horse_neigh", "horse_snort", "horse_snort"], "horse_grey": ["horse_neigh", "horse_snort"],
	"horse_draft": ["horse_snort", "horse_neigh"], "donkey": ["donkey", "horse_snort"],
}
const SURFACES := ["grass", "dirt", "cobble", "stone", "wood", "leaves"]

## Region 1 (C12): area -> [day theme, night theme] (docs/regions/AUDIO_R1.md). The area comes from where the player
## stands (settlement kind, the keep, the glade, the Scar); combat, danger and interiors still override it, and a
## story cue (set_story_cue) overrides everything but combat for a while.
const R1_AREA_THEMES := {
	"village": [&"r1_village_day", &"r1_night"],
	"town": [&"r1_guild_town", &"r1_night"],
	"keep": [&"r1_highwatch_keep", &"r1_night"],
	"glade": [&"r1_forest_glade", &"r1_night"],
	"rift": [&"r1_rift_wilds", &"r1_rift_wilds"],
}
## Place-name words that decide the area when they are the nearest named place.
const R1_NAME_AREAS := {"highwatch": "keep", "highcliff": "keep", "greywatch": "keep", "silverford": "town", "stagborn": "glade",
	"ashen scar": "rift", "rift": "rift", "scar watch": "rift"}
const R1_AREA_HYSTERESIS := 8.0
## Story cue -> seconds it holds before the area theme returns (the finale is a one-shot of 146 s).
const R1_CUE_SECONDS := {&"r1_finale": 150.0, &"silence": 25.0}
const R1_CUE_DEFAULT_SECONDS := 140.0

## Set by Main to the active 3D camera (the SubViewport's camera = the 3D listener).
var listener: Node3D
## Extra weather layer on top of the bed: "", "rain" or "storm".
var weather := ""
## Master switches (a settings menu can flip these).
var music_enabled := true
var footsteps_enabled := true

var _lib: Dictionary = {}          # name -> Array[String] of paths (variants)
var _cache: Dictionary = {}        # path -> AudioStream
var _cooldowns: Dictionary = {}
var _mood := ""                    # last hint from main.gd (town / wild / night / battle)
var _mood_battle_until := 0.0

var _bed_a: AudioStreamPlayer
var _bed_b: AudioStreamPlayer
var _bed := ""
var _music: Node                   # adaptive_music.gd
var _env: Node                     # environment_audio.gd
var _music_mood: StringName = &"silence"
var _outdoor_mood: StringName = &"wilderness"   # kept (muffled) while inside a non-tavern room
var _combat_hold := 0.0
var _in_combat := false
var _boss_forced := false
var _boss_seen_until := 0.0
var _threat := 0.0                 # Frontier threat at the player, 0..100
var _in_town := false
var _at_camp := false
var _forest := 0.0
var _hostiles_near := 0            # living non-player combatants within 30 m
var _last_kill := -100.0
var _intensity_override := -1.0
var _underwater_forced := -1       # -1 auto, 0 / 1 forced by set_underwater()
var _water_timer := 0.0
var _music_walled := false

var _pool3d: Array[AudioStreamPlayer3D] = []
var _spots3d: Array[AudioStreamPlayer3D] = []
var _pool3d_root: Node3D
var _pool2d: Array[AudioStreamPlayer] = []   # fallback when there is no 3D listener
var _ui: Array[AudioStreamPlayer] = []
var _steps: Array[AudioStreamPlayer] = []
var _step_i := 0
var _ui_i := 0
var _started: Dictionary = {}      # player -> start time (for stealing the oldest voice)

var _ctx_timer := 0.0
var _spot_timer := 6.0
var _creature_timer := 0.0
var _idle_timer := 4.0
var _interior := ""                # "", "tavern", "smithy", "healer", "guild", "house"
var _surface := "grass"
var _player: Node3D
var _r1_area := ""                 # Region 1 area under the player ("" = none), see R1_AREA_THEMES
var _r1_area_since := 0.0
var _r1_area_pending := ""
var _story_cue: StringName = &""
var _story_cue_until := 0.0
var _last_pos := Vector3.INF
var _stride := 0.0
var _last_dodge := 0.0
var _last_player_hp := -1
var _health: Dictionary = {}       # instance id -> last health
var _critters: Array[Node3D] = []
var _gold := -1
var _rank := -1
## Debug builds print context changes and a play count every 30 s ("[audio] ...").
var _log := OS.is_debug_build()
var _counts: Dictionary = {}
var _log_timer := 30.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	AudioBuses.ensure_layout()
	_scan(ROOT)
	_alias_region1()
	_bed_a = _player2d("Ambience")
	_bed_b = _player2d("Ambience")
	_music = AdaptiveMusic.new()
	_music.name = "AdaptiveMusic"
	_music.log_changes = _log
	add_child(_music)
	_env = EnvironmentAudio.new()
	_env.name = "EnvironmentAudio"
	_env.spot_fn = _nature_spot
	_env.has_fn = has_sound
	_env.pick_fn = _pick
	add_child(_env)
	for i in MAX_UI_VOICES:
		_ui.append(_player2d("UI"))
	for i in 2:
		_steps.append(_player2d("SFX"))
	for i in 6:
		_pool2d.append(_player2d("SFX"))
	get_tree().node_added.connect(_on_node_added)
	_hook_autoloads.call_deferred()
	# Preload the short one-shots in the background so the first swing doesn't hitch.
	for key: String in _lib:
		for path: String in _lib[key]:
			if path.contains("/sfx/") or path.contains("/ui/"):
				ResourceLoader.load_threaded_request(path, "AudioStream")
	# Ambience beds too: each is a multi-MB loop, and loading one on the frame the
	# player walks into a new area was a 90-100 ms hitch (perf_visual run 2026-09-28).
	for bed: String in BED_FILE:
		var bed_path := ROOT + "ambience/" + String(BED_FILE[bed]) + ".ogg"
		if ResourceLoader.exists(bed_path):
			ResourceLoader.load_threaded_request(bed_path, "AudioStream")


# ------------------------------------------------------------------ public API
## Positional one-shot. `position` = Vector3 (world) or null (at the listener).
func play_sfx(sound: String, position: Variant = null, volume_db := 0.0, pitch_jitter := 0.06) -> void:
	if sound == "thunder" and _env:
		# weather.gd calls this after each strike's travel delay: near crack or far roll
		_env.play_thunder(volume_db, volume_db > -5.0)
		return
	var stream := _pick(sound)
	if stream == null or _cooling(sound, 0.05):
		return
	if position is Vector3 and _listener_ok():
		var d3: float = listener.global_position.distance_to(position)
		if d3 > MAX_DISTANCE:
			return
		var p := _voice3d(_pool3d)
		if p == null:
			return
		p.global_position = position
		p.bus = _sfx_bus(d3)
		_start(p, stream, volume_db, pitch_jitter)
	else:
		var falloff := 0.0
		var d := 0.0
		if position is Vector3 and listener and is_instance_valid(listener):
			d = listener.global_position.distance_to(position)
			if d > MAX_DISTANCE:
				return
			falloff = -d * 0.45
		var q := _voice2d(_pool2d)
		q.bus = _sfx_bus(d)
		_start(q, stream, volume_db + falloff, pitch_jitter)


## Wind bed level. `strength` uses weather.gd's scale: 1 = calm breeze, 2.4 = storm (0..3).
func set_wind(strength: float) -> void:
	if _env:
		_env.set_wind(strength)


## Rain bed level 0..1 (light rain bed, crossing into the heavy storm bed above ~0.8).
func set_rain(amount: float) -> void:
	if _env:
		_env.set_rain(amount)


## Same as set_rain(); weather.gd calls it with rain_amount().
func set_weather_intensity(amount: float) -> void:
	set_rain(amount)


## Thunder heard `delay` seconds from now (lightning distance / 343 m/s). Short
## delays give the close crack, long ones a soft low roll. Muffled indoors.
func thunder(delay := 0.0) -> void:
	if _env:
		_env.thunder(delay)


## Forces boss music while in combat (true) or returns to auto-detection (false).
func set_boss(on: bool) -> void:
	_boss_forced = on


## Victory stinger over the score (the director also plays it by itself when a fight
## ends right after a kill with nothing hostile left nearby).
func play_victory() -> void:
	if _music:
		_music.stinger(&"victory")


## Discovery swell (new place found). Skipped during combat.
func play_discovery() -> void:
	if _music and not _in_combat:
		_music.stinger(&"discovery", -2.0)


## Overrides the music threat intensity (0..1); a negative value returns to auto.
func set_music_intensity(amount: float) -> void:
	_intensity_override = amount


## Forces the underwater muffle on / off; call with `auto = true` to go back to
## detecting it from the listener's position against WorldGen water.
func set_underwater(on: bool, auto := false) -> void:
	_underwater_forced = -1 if auto else int(on)
	if not auto and _env:
		_env.set_underwater(on)


## Name of the music mood right now (for debug overlays and tests).
## Region 1 story cue (C12): switch the music bed to a clip (r1_lament, r1_kindling, r1_finale, r1_boss_warden or any
## R1 area theme; "silence" fades the bed out). Holds for a while, then the area theme returns. Combat still wins.
## Unknown or missing cues fall back to the area theme: nothing breaks if a file is absent.
func set_story_cue(cue: String, seconds := -1.0) -> void:
	var c := StringName(cue)
	if cue == "" or not MusicBank.MOODS.has(c):
		_story_cue = &""
		return
	_story_cue = c
	var hold := seconds if seconds > 0.0 else float(R1_CUE_SECONDS.get(c, R1_CUE_DEFAULT_SECONDS))
	_story_cue_until = _now() + hold
	if _log:
		print("[audio] story cue %s for %.0f s" % [cue, hold])


func story_cue() -> StringName:
	return _story_cue if _now() < _story_cue_until else &""


## Region 1 area under the player ("village", "town", "keep", "glade", "rift" or "").
func r1_area() -> String:
	return _r1_area


## Files named sfx_r1_ward_activate.ogg are also known as "r1_ward_activate" (the names in AUDIO_R1.md).
func _alias_region1() -> void:
	for key: String in _lib.keys():
		if key.begins_with("sfx_r1_") or key.begins_with("amb_r1_"):
			for path: String in _lib[key]:
				_add(key.substr(4) if key.begins_with("sfx_") else key, path)
		elif key.begins_with("vo_r1_"):
			# vo_r1_m_hurt -> r1_bark_hurt (male and female variants pooled)
			var parts := key.split("_")
			if parts.size() >= 4:
				for path2: String in _lib[key]:
					_add("r1_bark_" + parts[3], path2)


func music_mood() -> StringName:
	return _music_mood


## Interface sound, never positional, never pitched: tap, open, close, coin, error,
## level_up, quest_accepted, quest_complete, confirm, select, defeat, menu_open.
func play_ui(sound: String, volume_db := 0.0) -> void:
	var stream := _pick(sound)
	if stream == null or _cooling("ui:" + sound, 0.04):
		return
	var p := _ui[_ui_i]
	_ui_i = (_ui_i + 1) % _ui.size()
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = 1.0
	p.play()


## One footstep on a surface ("" = look it up at `position`).
func play_footstep(position: Vector3, surface := "", volume_db := 0.0) -> void:
	var s := surface if surface != "" else surface_at(position)
	_surface = s
	var stream := _pick("step_" + s)
	if stream == null:
		return
	var p := _steps[_step_i]
	_step_i = (_step_i + 1) % _steps.size()
	p.bus = "Interior" if _interior != "" else "SFX"
	_start(p, stream, volume_db - 4.0, 0.08)


## Weather bed: "", "rain", "storm" or "wind" (weather.gd calls this on changes).
func set_weather(kind: String) -> void:
	weather = kind
	if _env:
		_env.set_weather(kind)


## Old API (main.gd calls this every 0.2 s): "town", "wild", "night" or "battle".
## The director works out town / night itself; "battle" is used as the combat cue.
func set_mood(mood: String) -> void:
	_mood = mood
	if mood == "battle":
		_mood_battle_until = _now() + 1.0


## Old API: Audio.sfx("swing" | "hit" | "clash" | "bell", position_or_null, volume_db).
func sfx(kind: String, at: Variant = null, volume_db := 0.0) -> void:
	play_sfx(LEGACY.get(kind, kind), at, volume_db)


func has_sound(sound: String) -> bool:
	return _lib.has(sound)


## Ground under a world position: grass, dirt, cobble, stone, wood or leaves.
func surface_at(p: Vector3) -> String:
	if _interior != "":
		return "stone" if _interior == "smithy" else "wood"
	if WorldGen.settlements.is_empty():
		return "grass"
	var h := WorldGen.height(p.x, p.z)
	var slope := absf(WorldGen.height(p.x + 1.0, p.z) - h) + absf(WorldGen.height(p.x, p.z + 1.0) - h)
	var w := WorldGen.color_at(p.x, p.z, h, clampf(slope * 0.7, 0.0, 1.0))
	if w.b > 0.5:
		return "cobble"
	if w.g > 0.6:
		return "stone"
	if w.r > 0.45:
		return "dirt"
	if w.a > 0.45:
		return "leaves"
	return "grass"


# ------------------------------------------------------------------ frame loop
func _process(delta: float) -> void:
	_ctx_timer -= delta
	if _ctx_timer <= 0.0:
		_ctx_timer = 0.5
		_update_context()
		_env.nature_tick(0.5, _is_night(), WorldSim.time_of_day, _forest, _in_town)
	_water_timer -= delta
	if _water_timer <= 0.0:
		_water_timer = 0.1
		_update_underwater()
	_update_music(delta)
	_spot_timer -= delta
	if _spot_timer <= 0.0:
		_spot_timer = randf_range(4.0, 12.0)
		_play_spot()
	_creature_timer -= delta
	if _creature_timer <= 0.0:
		_creature_timer = 0.15
		_poll_creatures()
	if _log:
		_log_timer -= delta
		if _log_timer <= 0.0:
			_log_timer = 30.0
			var busy := 0
			for p in _pool3d:
				busy += 1 if is_instance_valid(p) and p.playing else 0
			print("[audio] voices %d/%d, long streams %d, music %s/%s threat %.0f, surface %s, played %s" % [
				busy, _pool3d.size(), long_streams(), _music_mood, _music.current_clip(), _threat, _surface, _counts])
			_counts.clear()
	_idle_timer -= delta
	if _idle_timer <= 0.0:
		_idle_timer = randf_range(3.0, 7.0)
		_creature_idle()


func _physics_process(_delta: float) -> void:
	_poll_player()


func _update_context() -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	_interior = _interior_kind()
	_env.set_indoors(_interior)
	var bed := ""
	var night := _is_night()
	if _interior != "":
		bed = _interior
	elif _player != null and not WorldGen.settlements.is_empty():
		var p := _player.global_position
		var p2 := Vector2(p.x, p.z)
		var near := WorldGen.nearest_settlement(p2)
		_in_town = not near.is_empty() and p2.distance_to(near["pos"]) < float(near["radius"]) * 1.3
		_at_camp = false
		for c: Dictionary in WorldGen.camp_grounds:
			if p2.distance_to(c["pos"]) < float(c["radius"]) * 1.8:
				_at_camp = true
				break
		_threat = float(Frontier.threat_at(p2).get("total", 0.0))
		_forest = WorldGen.forest_density(p.x, p.z)
		_update_r1_area(p2, near)
		if _r1_area == "rift" and has_sound("amb_r1_scar_rift_loop"):
			bed = "scar_rift"
		elif _at_camp:
			bed = "camp"
		elif _in_town:
			bed = "village_night" if night else "village_day"
		elif _threat > 55.0:
			bed = "danger"
		elif _forest > 0.3:
			bed = "forest_night" if night else "forest_day"
		elif WorldGen.near_water(p.x, p.z, 22.0) and not night:
			bed = "creek"
		else:
			bed = "village_night" if night else "meadow_day"
	_set_bed(bed)


## Which Region 1 area the player is in, with a few seconds of hysteresis so walking along a border does not
## flip the score back and forth. Uses the nearest settlement's kind, the nearest named place's words and the
## Scar Tide mask (corrupted ground is always the rift theme).
func _update_r1_area(p2: Vector2, near: Dictionary) -> void:
	var area := ""
	var scar: Variant = Region1State.sim(&"scar_tide")
	if scar != null and scar.intensity_at(p2) > 0.3:
		area = "rift"
	else:
		var d := INF
		for pl: Dictionary in Life.discovery.places:
			var nm := String(pl["name"]).to_lower()
			for key: String in R1_NAME_AREAS:
				if nm.contains(key):
					var dd := p2.distance_to(pl["pos"])
					if dd < maxf(float(pl.get("radius", 60.0)), 90.0) * 1.6 and dd < d:
						d = dd
						area = String(R1_NAME_AREAS[key])
		if area == "" and not near.is_empty() and p2.distance_to(near["pos"]) < float(near["radius"]) * 1.4:
			area = "town" if String(near.get("kind", "village")) in ["town", "castle", "capital", "frontier_town"] else "village"
		if area == "" and _forest > 0.72 and _threat < 40.0:
			area = "glade"
	if area == _r1_area:
		_r1_area_pending = ""
		return
	var now := _now()
	if area != _r1_area_pending:
		_r1_area_pending = area
		_r1_area_since = now
	if now - _r1_area_since >= R1_AREA_HYSTERESIS or _r1_area == "":
		_r1_area = area
		_r1_area_pending = ""


func _interior_kind() -> String:
	var door := InteriorDoor.active
	if door == null or not is_instance_valid(door):
		return ""
	var scene := door.interior_scene.get_file()
	if scene.begins_with("inn"):
		return "tavern"
	if scene.begins_with("blacksmith"):
		return "smithy"
	if scene.begins_with("healer"):
		return "healer"
	if scene.begins_with("guild"):
		return "guild"
	return "house"


func _is_night() -> bool:
	var t := WorldSim.time_of_day
	return t < 5.5 or t >= 21.0


# ------------------------------------------------------------------ ambience
func _set_bed(bed: String) -> void:
	if bed == _bed:
		return
	_bed = bed
	if _log:
		print("[audio] bed -> %s (interior=%s, t=%.1f h)" % [bed, _interior, WorldSim.time_of_day])
	var stream: AudioStream = null
	if bed != "":
		var file := String(BED_FILE[bed])
		stream = _load(ROOT + ("ambience/" + file if not file.begins_with("region1/") else file.replace("region1/", "region1/ambience/")) + ".ogg", true)
	_crossfade(_bed_a, _bed_b, stream, float(BEDS.get(bed, 0.0)), BED_FADE)
	var t := _bed_a
	_bed_a = _bed_b
	_bed_b = t


## Fades `out_p` down and `in_p` (the idle one) up with `stream`. Beds start at a
## random point so re-entering an area doesn't replay the same opening seconds.
func _crossfade(out_p: AudioStreamPlayer, in_p: AudioStreamPlayer, stream: AudioStream, db_target: float,
		time: float, random_start := true) -> void:
	if out_p.playing:
		var t := create_tween()
		t.tween_property(out_p, "volume_db", -60.0, time)
		t.tween_callback(out_p.stop)
	if stream == null:
		return
	in_p.stream = stream
	in_p.volume_db = -60.0
	in_p.play(randf() * maxf(0.0, stream.get_length() - 1.0) if random_start else 0.0)
	create_tween().tween_property(in_p, "volume_db", db_target, time)


func _play_spot() -> void:
	var list: Array = SPOTS.get(_bed, [])
	if list.is_empty():
		return
	var total := 0
	for e: Array in list:
		total += int(e[1])
	var r := randi() % total
	for e: Array in list:
		r -= int(e[1])
		if r < 0:
			var stream := _pick(String(e[0]))
			if stream == null:
				return
			if _listener_ok():
				var p := _voice3d(_spots3d)
				var a := randf() * TAU
				var d := randf_range(6.0, 18.0) if _interior != "" else randf_range(12.0, 30.0)
				p.global_position = listener.global_position + Vector3(cos(a) * d, randf_range(0.0, 4.0), sin(a) * d)
				p.bus = AudioBuses.INTERIOR if _interior != "" else AudioBuses.AMBIENCE
				_start(p, stream, float(e[2]) + 6.0, 0.05)
			else:
				var q := _voice2d(_pool2d)
				q.bus = AudioBuses.INTERIOR if _interior != "" else AudioBuses.AMBIENCE
				_start(q, stream, float(e[2]), 0.05)
			return


## Environment spot (birds, crickets) around the listener: `sound` at a random bearing,
## min_d..max_d metres away and min_h..max_h metres up. Uses the ambience spot voices.
func _nature_spot(sound: String, min_d: float, max_d: float, min_h: float, max_h: float, volume_db: float) -> void:
	var stream := _pick(sound)
	if stream == null:
		return
	if _listener_ok():
		var p := _voice3d(_spots3d)
		var a := randf() * TAU
		var d := randf_range(min_d, max_d)
		p.global_position = listener.global_position + Vector3(cos(a) * d, randf_range(min_h, max_h), sin(a) * d)
		p.bus = AudioBuses.AMBIENCE
		_start(p, stream, volume_db + 6.0, 0.08)
	else:
		var q := _voice2d(_pool2d)
		q.bus = AudioBuses.AMBIENCE
		_start(q, stream, volume_db - 2.0, 0.08)


func _on_hour(hour: int) -> void:
	# The town bell rings the day in, at noon and at dusk.
	if hour in [7, 12, 18] and _bed.begins_with("village"):
		play_ui("bell_tower", -12.0)


# ------------------------------------------------------------------ music
func _update_music(delta: float) -> void:
	var battle := _now() < _mood_battle_until
	if battle:
		_combat_hold = COMBAT_HOLD
	elif _combat_hold > 0.0:
		_combat_hold -= delta
	var fighting := battle or _combat_hold > 0.0
	if fighting != _in_combat:
		_in_combat = fighting
		if fighting:
			_music.stinger(&"combat", -3.0)
		elif _now() - _last_kill < COMBAT_HOLD + 4.0 and _hostiles_near == 0 and not _player_dead():
			_music.stinger(&"victory")
	var mood := _music_mood_now()
	if mood != _music_mood and _log:
		print("[audio] mood %s -> %s (threat %.0f, hostiles %d, interior %s)" % [_music_mood, mood, _threat, _hostiles_near, _interior])
	_music_mood = mood
	_music.enabled = music_enabled
	_music.set_mood(mood)
	_music.intensity = _music_intensity()
	# muffled "through the walls" score inside rooms that have no music of their own
	var through_walls := _interior != "" and mood != &"tavern" and mood != &"silence"
	if through_walls != _music_walled and not _underwater():
		_music_walled = through_walls
		AudioBuses.muffle(self, AudioBuses.MUSIC, 1100.0 if through_walls else AudioBuses.OPEN_HZ, -5.0 if through_walls else 0.0, 0.8)


func _music_mood_now() -> StringName:
	if not music_enabled:
		return &"silence"
	if _in_combat:
		if (_boss_forced or _now() < _boss_seen_until) and _r1_area == "glade":
			return &"r1_boss_warden"   # the Antlered Warden (C12); other bosses keep the old boss theme
		return &"boss" if _boss_forced or _now() < _boss_seen_until else &"combat"
	if _now() < _story_cue_until and _story_cue != &"" and _interior == "":
		return _story_cue
	if _interior == "tavern":
		return &"tavern"
	var night := _is_night()
	if _interior != "":
		return _outdoor_mood
	var mood: StringName
	var stalked := _hostiles_near > 0
	if not _in_town and (_threat >= THREAT_DANGER or _at_camp or stalked):
		mood = &"danger"
	elif _in_town or (_mood == "town" and _player == null):
		mood = &"town_night" if night else &"town_day"
	else:
		mood = &"wild_night" if night else &"wilderness"
	# what keeps playing (muffled) if the player steps into a house now
	if _r1_area != "" and mood != &"danger":
		mood = R1_AREA_THEMES[_r1_area][1 if night else 0]   # Region 1 themes replace the generic town / wild score
	_outdoor_mood = mood if mood != &"danger" else (&"wild_night" if night else &"wilderness")
	return mood


## 0..1 drum layer amount from the threat inputs: Frontier threat (dens, camps,
## wilderness, runestones, patrols), standing in a camp, monsters prowling nearby.
func _music_intensity() -> float:
	if _intensity_override >= 0.0:
		return clampf(_intensity_override, 0.0, 1.0)
	var k := smoothstep(THREAT_LAYER_START, THREAT_DANGER, _threat)
	if _music_mood == &"danger":
		# inside the danger clip: its own drums grow from half to full
		k = 0.45 + 0.55 * maxf(smoothstep(THREAT_DANGER, 85.0, _threat), minf(_hostiles_near * 0.3, 1.0))
		if _at_camp:
			k = maxf(k, 0.8)
	return k


func _player_dead() -> bool:
	return _player != null and is_instance_valid(_player) and (_player.get("dead") == true)


func _underwater() -> bool:
	return _env != null and _env.underwater


func _update_underwater() -> void:
	if _underwater_forced >= 0:
		return
	var under := false
	if _listener_ok() and _interior == "":
		var lp := listener.global_position
		var level := WorldGen.water_level_at(lp.x, lp.z)
		under = not is_nan(level) and lp.y < level - 0.05
	if under != _env.underwater:
		_env.set_underwater(under)


## Long streams currently decoding (beds, weather, music layers), for the budget log.
func long_streams() -> int:
	var n := 0
	for p: AudioStreamPlayer in [_bed_a, _bed_b]:
		n += 1 if p.playing else 0
	for c in _env.get_children():
		n += 1 if (c as AudioStreamPlayer).playing else 0
	if _music.current_clip() != &"silence":
		n += 1 + (1 if _music.bank and _music.bank.has_stem(_music.current_clip()) else 0)
	return n


# ------------------------------------------------------------------ footsteps & creatures
func _poll_player() -> void:
	if _player == null or not is_instance_valid(_player) or not _player.is_inside_tree():
		_last_pos = Vector3.INF
		return
	var pos := _player.global_position
	if _last_pos == Vector3.INF:
		_last_pos = pos
		return
	var moved := Vector2(pos.x - _last_pos.x, pos.z - _last_pos.z).length()
	_last_pos = pos
	# dodge whoosh (player._dodge goes > 0 when a dodge starts)
	var dodge: Variant = _player.get("_dodge")
	if dodge is float:
		if float(dodge) > 0.3 and _last_dodge <= 0.0:
			play_sfx("dodge", pos, -2.0)
		_last_dodge = float(dodge)
	if not footsteps_enabled or (_player.get("dead") == true):
		return
	var on_floor: bool = _player.call("is_on_floor") if _player.has_method("is_on_floor") else true
	if not on_floor or moved > 3.0:      # teleports (doors, respawn) don't make steps
		_stride = 0.0
		return
	var speed := moved / maxf(get_physics_process_delta_time(), 0.001)
	if speed < 0.6:
		_stride = minf(_stride, 0.4)
		return
	_stride += moved
	var stride_len := 2.1 if speed > 4.5 else 1.4
	if _stride >= stride_len:
		_stride = 0.0
		play_footstep(pos, "", 2.0 if speed > 4.5 else 0.0)


func _poll_creatures() -> void:
	if not listener or not is_instance_valid(listener) or not listener.is_inside_tree():
		return      # the listener is being freed with the old scene (Exit to Menu / reload)
	var lp := listener.global_position
	# player hurt / death
	if _player and is_instance_valid(_player):
		var hp: Variant = _player.get("health")
		if hp is int:
			if _last_player_hp >= 0 and int(hp) < _last_player_hp:
				play_sfx("player_death" if int(hp) <= 0 else "player_hurt", _player.global_position, -2.0)
			_last_player_hp = int(hp)
	var seen := {}
	var hostiles := 0
	for n in get_tree().get_nodes_in_group("combatant"):
		var c := n as Node3D
		if c == null or c == _player:
			continue
		var sp := _species(c)
		if sp == "":
			continue
		if c.global_position.distance_squared_to(lp) > 900.0:
			continue
		var id := c.get_instance_id()
		seen[id] = true
		var hp: Variant = c.get("health")
		if not hp is int:
			continue
		var dead: bool = int(hp) <= 0 or (c.get("dead") == true)
		if not dead:
			hostiles += 1
			if _in_combat and _is_boss(c):
				_boss_seen_until = _now() + 3.0
		var last: int = _health.get(id, int(hp))
		if int(hp) < last:
			var names: Array = CREATURES.get(sp, ["", "monster_hurt", "monster_death"])
			play_sfx(String(names[2]) if dead else String(names[1]), c.global_position + Vector3(0, 1, 0))
			if dead:
				_last_kill = _now()
		_health[id] = int(hp)
	for id in _health.keys():
		if not seen.has(id):
			_health.erase(id)
	_hostiles_near = hostiles


func _is_boss(c: Node) -> bool:
	var flag: Variant = c.get("is_boss")
	if c.is_in_group("boss") or bool(c.get_meta("is_boss", false)) or (flag is bool and flag):
		return true
	var mh: Variant = c.get("max_health")
	return mh is int and int(mh) >= BOSS_HEALTH


func _creature_idle() -> void:
	if not listener or not is_instance_valid(listener) or not listener.is_inside_tree():
		return
	var lp := listener.global_position
	if randf() < 0.6 and _animal_voice(lp):
		return
	var best: Node3D = null
	for n in get_tree().get_nodes_in_group("combatant"):
		var c := n as Node3D
		if c == null or _species(c) == "" or (c.get("dead") == true):
			continue
		var d := c.global_position.distance_to(lp)
		if d < 28.0 and (best == null or randf() < 0.4):
			best = c
	if best:
		var names: Array = CREATURES.get(_species(best), [])
		if not names.is_empty():
			play_sfx(String(names[0]), best.global_position + Vector3(0, 1, 0), -3.0, 0.1)


func _animal_voice(lp: Vector3) -> bool:
	var alive: Array[Node3D] = []
	var near: Array[Node3D] = []
	for c in _critters:
		if not is_instance_valid(c) or not c.is_inside_tree():
			continue
		alive.append(c)
		if c.is_visible_in_tree() and c.global_position.distance_squared_to(lp) < 625.0:
			near.append(c)
	_critters = alive
	if near.is_empty():
		return false
	var pick: Node3D = near[randi() % near.size()]
	var names: Array = ANIMALS.get(String(pick.get("kind")), [])
	if names.is_empty():
		return false
	var sound: String = names[randi() % names.size()]
	if sound == "rooster" and not (WorldSim.time_of_day > 4.5 and WorldSim.time_of_day < 10.0):
		sound = "chicken_cluck"
	play_sfx(sound, pick.global_position + Vector3(0, 0.5, 0), -4.0, 0.08)
	return true


func _species(n: Node) -> String:
	if n.is_in_group("player") or n.get_script() == null:
		return ""
	var sp: Variant = n.get("species")
	if sp is String and sp != "":
		return sp
	var cls := String(n.get_script().get_global_name()).to_lower()
	if cls == "wolf":
		return "wolf"
	return ""


# ------------------------------------------------------------------ UI & game hooks
func _on_node_added(n: Node) -> void:
	if n is BaseButton and not n.has_meta("no_click"):
		(n as BaseButton).pressed.connect(play_ui.bind("tap", -2.0))
	elif n is Critter:
		_critters.append(n as Node3D)
	elif n is InteriorDoor:
		var door := n as InteriorDoor
		door.interior_entered.connect(func(_i: Node3D) -> void: play_ui("door_open", -4.0))
		door.interior_exited.connect(func() -> void: play_ui("door_close", -4.0))


func _hook_autoloads() -> void:
	WorldSim.hour_changed.connect(_on_hour)
	_gold = Game.gold
	_rank = Game.rank
	Game.stats_changed.connect(_on_stats)


func _on_stats() -> void:
	if Game.rank > _rank and _rank >= 0:
		play_ui("level_up")
	elif Game.gold > _gold and _gold >= 0:
		play_ui("coin", -2.0)
	elif Game.gold < _gold:
		play_ui("coins", -4.0)
	_gold = Game.gold
	_rank = Game.rank


# ------------------------------------------------------------------ plumbing
func _listener_ok() -> bool:
	if listener == null or not is_instance_valid(listener) or not listener.is_inside_tree():
		return false
	var vp := listener.get_viewport()
	if _pool3d_root == null or not is_instance_valid(_pool3d_root) or _pool3d_root.get_viewport() != vp:
		_build_pool3d(vp)
	return true


func _build_pool3d(vp: Viewport) -> void:
	if _pool3d_root and is_instance_valid(_pool3d_root):
		_pool3d_root.queue_free()
	_pool3d.clear()
	_spots3d.clear()
	vp.audio_listener_enable_3d = true   # SubViewport cameras only hear 3D audio when enabled
	_pool3d_root = Node3D.new()
	_pool3d_root.name = "AudioDirectorVoices"
	vp.add_child(_pool3d_root)
	for i in MAX_SFX_VOICES + 3:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 7.0
		p.max_distance = MAX_DISTANCE + 15.0
		# distance low-pass per voice (air absorption); SFXFar adds more past FAR_DISTANCE
		p.attenuation_filter_cutoff_hz = 5000.0
		p.attenuation_filter_db = -24.0
		p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		p.bus = "SFX"
		_pool3d_root.add_child(p)
		if i < MAX_SFX_VOICES:
			_pool3d.append(p)
		else:
			_spots3d.append(p)


func _voice3d(pool: Array[AudioStreamPlayer3D]) -> AudioStreamPlayer3D:
	var oldest: AudioStreamPlayer3D = null
	var oldest_t := INF
	for p in pool:
		if not p.playing:
			return p
		var t: float = _started.get(p, 0.0)
		if t < oldest_t:
			oldest_t = t
			oldest = p
	return oldest    # voice stealing: the oldest sound makes room


func _voice2d(pool: Array[AudioStreamPlayer]) -> AudioStreamPlayer:
	var oldest: AudioStreamPlayer = pool[0]
	var oldest_t := INF
	for p in pool:
		if not p.playing:
			return p
		var t: float = _started.get(p, 0.0)
		if t < oldest_t:
			oldest_t = t
			oldest = p
	return oldest


func _start(p: Node, stream: AudioStream, volume_db: float, jitter: float) -> void:
	p.set("stream", stream)
	p.set("volume_db", volume_db)
	p.set("pitch_scale", randf_range(1.0 - jitter, 1.0 + jitter) if jitter > 0.0 else 1.0)
	p.call("play")
	_started[p] = _now()
	if _log:
		var key := String(stream.resource_path.get_file().get_basename())
		_counts[key] = int(_counts.get(key, 0)) + 1


## Bus for a one-shot `dist` metres away: the room reverb inside, the distance
## low-pass outside past FAR_DISTANCE, plain SFX otherwise.
func _sfx_bus(dist: float) -> String:
	if _interior != "":
		return AudioBuses.INTERIOR
	return AudioBuses.SFX_FAR if dist > FAR_DISTANCE else AudioBuses.SFX


func _player2d(bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus if AudioServer.get_bus_index(bus) >= 0 else "Master"
	add_child(p)
	return p


func _cooling(key: String, secs: float) -> bool:
	var now := _now()
	if float(_cooldowns.get(key, 0.0)) > now:
		return true
	_cooldowns[key] = now + secs
	return false


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _pick(sound: String) -> AudioStream:
	var list: Array = _lib.get(sound, [])
	if list.is_empty():
		return null
	return _load(list[randi() % list.size()], false)


func _load(path: String, loop: bool) -> AudioStream:
	if _cache.has(path):
		return _cache[path]
	var s: AudioStream = null
	if ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		s = ResourceLoader.load_threaded_get(path) as AudioStream
	if s == null:
		s = MusicBank.load_stream(path)   # also reads files the editor hasn't imported yet
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = loop
	_cache[path] = s
	return s


## Indexes res://assets/audio: "hit_flesh_03.ogg" is filed under both "hit_flesh"
## and "hit_flesh_03". Exported builds list "x.ogg.import" / "x.ogg.remap" instead.
func _scan(dir: String) -> void:
	for sub in DirAccess.get_directories_at(dir):
		_scan(dir + sub + "/")
	for f in DirAccess.get_files_at(dir):
		var file := f.trim_suffix(".import").trim_suffix(".remap")
		if not file.ends_with(".ogg"):
			continue
		var path := dir + file
		var stem := file.get_basename()
		_add(stem, path)
		var parts := stem.rsplit("_", true, 1)
		if parts.size() == 2 and parts[1].is_valid_int():
			_add(parts[0], path)


func _add(key: String, path: String) -> void:
	if not _lib.has(key):
		_lib[key] = []
	if not (_lib[key] as Array).has(path):
		(_lib[key] as Array).append(path)
