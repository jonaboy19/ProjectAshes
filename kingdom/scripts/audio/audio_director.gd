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
## Phone budget: max 12 positional SFX voices (oldest stolen), 2 ambience spot
## voices, 2 footstep voices, 4 UI voices, 2+2 ambience bed players (crossfade),
## 2 music players (crossfade). Streams are OGG Vorbis (decoded on the fly).

const ROOT := "res://assets/audio/"
const MAX_SFX_VOICES := 12
const MAX_UI_VOICES := 4
const MAX_DISTANCE := 45.0
const BED_FADE := 2.5
const MUSIC_FADE := 3.0

## Bed name -> volume offset (dB) on top of the -24 LUFS files.
const BEDS := {
	"village_day": 0.0, "village_night": 0.0, "meadow_day": -2.0, "forest_day": 0.0, "forest_night": 0.0,
	"creek": 0.0, "danger": 1.0, "camp": 1.0, "tavern": 0.0, "smithy": 3.0, "healer": -1.0,
	"house": -4.0, "guild": -5.0, "wind": 0.0,
}
## Which file plays for a bed (several beds share recordings).
const BED_FILE := {
	"village_day": "amb_village_day", "village_night": "amb_village_night", "meadow_day": "amb_meadow_day",
	"forest_day": "amb_forest_day", "forest_night": "amb_forest_night", "creek": "amb_creek",
	"danger": "amb_danger", "camp": "amb_camp", "tavern": "amb_tavern", "smithy": "amb_smithy",
	"healer": "amb_healer", "house": "amb_healer", "guild": "amb_tavern", "wind": "amb_wind",
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
const MUSIC := {
	"village": ["mus_village_day", "mus_village_day_02"],
	"explore": ["mus_explore", "mus_explore_02", "mus_explore_03"],
	"night": ["mus_night"],
	"tavern": ["mus_tavern"],
	"combat": ["mus_combat"],
}
const MUSIC_DB := {"village": -3.0, "explore": -4.0, "night": -7.0, "tavern": -4.0, "combat": -2.0}
## Tracks that loop without a pause; the rest leave a quiet gap before the next one.
const MUSIC_LOOPS := ["tavern", "combat"]
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
var _weather_a: AudioStreamPlayer
var _weather_b: AudioStreamPlayer
var _weather_now := ""
var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _music_ctx := ""
var _music_track := ""
var _music_gap := 0.0
var _combat_hold := 0.0

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
	_scan(ROOT)
	_bed_a = _player2d("Ambience")
	_bed_b = _player2d("Ambience")
	_weather_a = _player2d("Ambience")
	_weather_b = _player2d("Ambience")
	_music_a = _player2d("Music")
	_music_b = _player2d("Music")
	_music_a.finished.connect(_on_music_finished.bind(_music_a))
	_music_b.finished.connect(_on_music_finished.bind(_music_b))
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


# ------------------------------------------------------------------ public API
## Positional one-shot. `position` = Vector3 (world) or null (at the listener).
func play_sfx(sound: String, position: Variant = null, volume_db := 0.0, pitch_jitter := 0.06) -> void:
	var stream := _pick(sound)
	if stream == null or _cooling(sound, 0.05):
		return
	if position is Vector3 and _listener_ok():
		if listener.global_position.distance_to(position) > MAX_DISTANCE:
			return
		var p := _voice3d(_pool3d)
		if p == null:
			return
		p.global_position = position
		p.bus = "Interior" if _interior != "" else "SFX"
		_start(p, stream, volume_db, pitch_jitter)
	else:
		var falloff := 0.0
		if position is Vector3 and listener and is_instance_valid(listener):
			var d: float = listener.global_position.distance_to(position)
			if d > MAX_DISTANCE:
				return
			falloff = -d * 0.45
		var q := _voice2d(_pool2d)
		q.bus = "Interior" if _interior != "" else "SFX"
		_start(q, stream, volume_db + falloff, pitch_jitter)


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


## Weather layer: "", "rain" or "storm" (future weather system).
func set_weather(kind: String) -> void:
	weather = kind


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
				busy += 1 if p.playing else 0
			print("[audio] voices %d/%d, surface %s, played %s" % [busy, _pool3d.size(), _surface, _counts])
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
	var bed := ""
	var night := _is_night()
	if _interior != "":
		bed = _interior
	elif _player != null and not WorldGen.settlements.is_empty():
		var p := _player.global_position
		var p2 := Vector2(p.x, p.z)
		var near := WorldGen.nearest_settlement(p2)
		var in_town: bool = not near.is_empty() and p2.distance_to(near["pos"]) < float(near["radius"]) * 1.3
		var at_camp := false
		for c: Dictionary in WorldGen.camp_grounds:
			if p2.distance_to(c["pos"]) < float(c["radius"]) * 1.8:
				at_camp = true
				break
		var threat := float(Frontier.threat_at(p2).get("total", 0.0))
		if at_camp:
			bed = "camp"
		elif in_town:
			bed = "village_night" if night else "village_day"
		elif threat > 55.0:
			bed = "danger"
		elif WorldGen.forest_density(p.x, p.z) > 0.3:
			bed = "forest_night" if night else "forest_day"
		elif WorldGen.near_water(p.x, p.z, 22.0) and not night:
			bed = "creek"
		else:
			bed = "village_night" if night else "meadow_day"
	_set_bed(bed)
	_set_weather_layer("" if _interior != "" else weather)


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
		stream = _load(ROOT + "ambience/" + String(BED_FILE[bed]) + ".ogg", true)
	_crossfade(_bed_a, _bed_b, stream, float(BEDS.get(bed, 0.0)), BED_FADE)
	var t := _bed_a
	_bed_a = _bed_b
	_bed_b = t


func _set_weather_layer(kind: String) -> void:
	if kind == _weather_now:
		return
	_weather_now = kind
	var stream: AudioStream = null
	if kind != "":
		stream = _load(ROOT + "ambience/amb_" + kind + ".ogg", true)
	_crossfade(_weather_a, _weather_b, stream, 0.0, BED_FADE * 2.0)
	var t := _weather_a
	_weather_a = _weather_b
	_weather_b = t


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
	if _weather_now == "storm" and randf() < 0.35:
		list = [["thunder", 1, -2.0]]
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
				p.bus = "Ambience"
				_start(p, stream, float(e[2]) + 6.0, 0.05)
			else:
				var q := _voice2d(_pool2d)
				q.bus = "Ambience"
				_start(q, stream, float(e[2]), 0.05)
			return


func _on_hour(hour: int) -> void:
	# The town bell rings the day in, at noon and at dusk.
	if hour in [7, 12, 18] and _bed.begins_with("village"):
		play_ui("bell_tower", -12.0)


# ------------------------------------------------------------------ music
func _update_music(delta: float) -> void:
	var ctx := _music_context()
	if ctx == "combat":
		_combat_hold = 6.0
	elif _music_ctx == "combat" and _combat_hold > 0.0:
		_combat_hold -= delta
		ctx = "combat"
	if ctx != _music_ctx:
		var entering_combat := ctx == "combat"
		_music_ctx = ctx
		_music_gap = 0.0
		if entering_combat:
			_stinger()
		_next_track(entering_combat)
		return
	if _music_gap > 0.0:
		_music_gap -= delta
		if _music_gap <= 0.0:
			_next_track(false)


func _music_context() -> String:
	if not music_enabled:
		return ""
	if _now() < _mood_battle_until:
		return "combat"
	match _interior:
		"tavern":
			return "tavern"
		"smithy", "healer", "house", "guild":
			return ""
	if _is_night():
		return "night"
	if _bed.begins_with("village") or _mood == "town":
		return "village"
	return "explore"


func _next_track(delay_start: bool) -> void:
	var stream: AudioStream = null
	var db_target := 0.0
	if _music_ctx != "":
		var list: Array = MUSIC[_music_ctx]
		var name: String = list[randi() % list.size()]
		if list.size() > 1 and name == _music_track:
			name = list[(list.find(name) + 1) % list.size()]
		_music_track = name
		if _log:
			print("[audio] music %s -> %s" % [_music_ctx, name])
		stream = _load(ROOT + "music/" + name + ".ogg", _music_ctx in MUSIC_LOOPS)
		db_target = float(MUSIC_DB[_music_ctx])
	if stream != null and delay_start:
		# let the stinger speak first
		_crossfade(_music_a, _music_b, null, 0.0, 1.0)
		get_tree().create_timer(1.6).timeout.connect(func() -> void:
			if _music_ctx == "combat":
				_crossfade(_music_a, _music_b, stream, db_target, 1.0, false)
				_swap_music())
		return
	_crossfade(_music_a, _music_b, stream, db_target, MUSIC_FADE, false)
	_swap_music()


func _stinger() -> void:
	var s := _pick("mus_combat_stinger")
	if s == null:
		return
	var p := _ui[_ui_i]
	_ui_i = (_ui_i + 1) % _ui.size()
	p.bus = "Music"
	p.stream = s
	p.volume_db = -3.0
	p.play()
	p.finished.connect(func() -> void: p.bus = "UI", CONNECT_ONE_SHOT)


func _swap_music() -> void:
	var t := _music_a
	_music_a = _music_b
	_music_b = t


func _on_music_finished(p: AudioStreamPlayer) -> void:
	if p != _music_a or _music_ctx == "":
		return
	# a quiet stretch between tracks keeps the world from feeling like a jukebox
	_music_gap = randf_range(20.0, 50.0) if _music_ctx != "night" else randf_range(40.0, 90.0)


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
	if not footsteps_enabled or bool(_player.get("dead")):
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
	if not listener or not is_instance_valid(listener):
		return
	var lp := listener.global_position
	# player hurt / death
	if _player and is_instance_valid(_player):
		var hp: Variant = _player.get("health")
		if hp is int:
			if _last_player_hp >= 0 and int(hp) < _last_player_hp:
				play_sfx("player_death" if int(hp) <= 0 else "player_hurt", _player.global_position, -2.0)
			_last_player_hp = int(hp)
	var seen := {}
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
		var last: int = _health.get(id, int(hp))
		if int(hp) < last:
			var names: Array = CREATURES.get(sp, ["", "monster_hurt", "monster_death"])
			var dead := int(hp) <= 0 or bool(c.get("dead"))
			play_sfx(String(names[2]) if dead else String(names[1]), c.global_position + Vector3(0, 1, 0))
		_health[id] = int(hp)
	for id in _health.keys():
		if not seen.has(id):
			_health.erase(id)


func _creature_idle() -> void:
	if not listener or not is_instance_valid(listener):
		return
	var lp := listener.global_position
	if randf() < 0.6 and _animal_voice(lp):
		return
	var best: Node3D = null
	for n in get_tree().get_nodes_in_group("combatant"):
		var c := n as Node3D
		if c == null or _species(c) == "" or bool(c.get("dead")):
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
	for i in MAX_SFX_VOICES + 2:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 7.0
		p.max_distance = MAX_DISTANCE + 15.0
		p.attenuation_filter_cutoff_hz = 6000.0
		p.attenuation_filter_db = -18.0
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
	if s == null and ResourceLoader.exists(path):
		s = load(path) as AudioStream
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
