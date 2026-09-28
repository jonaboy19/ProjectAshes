extends Node
## Music, ambience and sound effects (OpenGameArt CC0 music/SFX, BigSoundBank CC0).
## Music follows the situation: town tunes near settlements, a battle theme when
## enemies are close, silence-plus-crickets at night.

const IN := "res://assets/incoming/"
const MUSIC := {
	"town": [IN + "opengameart/music/randommind_Market_Day.ogg", IN + "opengameart/music/randommind_Minstrel_Dance_0.ogg",
		IN + "opengameart/music/randommind_The_Old_Tower_Inn.ogg"],
	"wild": [IN + "opengameart/music/randommind_The_Bards_Tale.ogg", IN + "opengameart/music/randommind_Kings_Feast_0.ogg"],
	"battle": [IN + "opengameart/music/cynicmusic_battleThemeA.mp3"],
}
const AMBIENCE := {
	"day": IN + "opengameart/ambience/tinyworlds_forest_ambience.mp3",
	"night": IN + "opengameart/ambience/wolfgang_crickets_loop.mp3",
}
const SFX := {
	"swing": ["bigsoundbank/whoosh_1_s1795.ogg", "bigsoundbank/whoosh_3_s1797.ogg", "bigsoundbank/whoosh_5_s1799.ogg",
		"bigsoundbank/sword_through_air_s0128.ogg"],
	"hit": ["bigsoundbank/sword_cut_s0127.ogg", "bigsoundbank/sword_s0129.ogg"],
	"clash": ["opengameart/sfx/sword-clashes-starninjas/sword_clash.1.ogg", "opengameart/sfx/sword-clashes-starninjas/sword_clash.3.ogg",
		"opengameart/sfx/sword-clashes-starninjas/sword_clash.5.ogg", "opengameart/sfx/sword-clashes-starninjas/sword_clash.7.ogg"],
	"step_grass": ["kenney/impact-sounds/Audio/footstep_grass_000.ogg", "kenney/impact-sounds/Audio/footstep_grass_001.ogg",
		"kenney/impact-sounds/Audio/footstep_grass_002.ogg", "kenney/impact-sounds/Audio/footstep_grass_003.ogg", "kenney/impact-sounds/Audio/footstep_grass_004.ogg"],
	"step_stone": ["kenney/impact-sounds/Audio/footstep_concrete_000.ogg", "kenney/impact-sounds/Audio/footstep_concrete_001.ogg",
		"kenney/impact-sounds/Audio/footstep_concrete_002.ogg", "kenney/impact-sounds/Audio/footstep_concrete_003.ogg", "kenney/impact-sounds/Audio/footstep_concrete_004.ogg"],
	"bell": ["bigsoundbank/church_bell_s0135.ogg"],
}

var _music: AudioStreamPlayer
var _ambience: AudioStreamPlayer
var _mood := ""
## Plain players with manual distance falloff: the 3D world lives in a SubViewport,
## so positional players here wouldn't hear its camera.
var _pool: Array[AudioStreamPlayer] = []
## Set by Main to the active 3D camera.
var listener: Node3D
var _pool_index := 0
var _cache: Dictionary = {}
var _cooldowns: Dictionary = {}


func _ready() -> void:
	_music = AudioStreamPlayer.new()
	_music.volume_db = -10.0
	_music.finished.connect(func() -> void: _play_music(_mood))
	add_child(_music)
	_ambience = AudioStreamPlayer.new()
	_ambience.volume_db = -14.0
	add_child(_ambience)
	for i in 12:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)


## "town", "wild", "battle" or "night".
func set_mood(mood: String) -> void:
	if mood == _mood:
		return
	_mood = mood
	var amb: String = AMBIENCE["night" if mood == "night" else "day"]
	var amb_stream := _load(amb)
	if amb_stream and _ambience.stream != amb_stream:
		_ambience.stream = amb_stream
		_ambience.play()
	if mood == "night":
		var t := create_tween()
		t.tween_property(_music, "volume_db", -40.0, 3.0)
		t.tween_callback(_music.stop)
	else:
		_music.volume_db = -10.0
		_play_music(mood)


func _play_music(mood: String) -> void:
	if not MUSIC.has(mood):
		return
	var list: Array = MUSIC[mood]
	var stream := _load(list[randi() % list.size()])
	if stream:
		_music.stream = stream
		_music.play()


## Plays a random variant of `kind`, positioned in 3D when `at` is given.
## Rate-limited per kind so a big melee doesn't turn into noise.
func sfx(kind: String, at: Variant = null, volume_db := 0.0) -> void:
	var now := Time.get_ticks_msec()
	if _cooldowns.get(kind, 0) > now:
		return
	_cooldowns[kind] = now + 45
	var list: Array = SFX.get(kind, [])
	if list.is_empty():
		return
	var stream := _load(IN + list[randi() % list.size()])
	if stream == null:
		return
	var falloff := 0.0
	if at is Vector3 and listener and is_instance_valid(listener):
		var d: float = listener.global_position.distance_to(at)
		if d > 60.0:
			return
		falloff = -d * 0.45
	var p := _pool[_pool_index]
	_pool_index = (_pool_index + 1) % _pool.size()
	p.stream = stream
	p.volume_db = volume_db + falloff
	p.pitch_scale = randf_range(0.92, 1.08)
	p.play()


func _load(path: String) -> AudioStream:
	if _cache.has(path):
		return _cache[path]
	var s: AudioStream = load(path) if ResourceLoader.exists(path) else null
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = path.contains("ambience") or path.contains("crickets")
	elif s is AudioStreamMP3:
		(s as AudioStreamMP3).loop = path.contains("ambience") or path.contains("crickets")
	_cache[path] = s
	return s
