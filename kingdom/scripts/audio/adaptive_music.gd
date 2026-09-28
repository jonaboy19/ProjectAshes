extends Node
## Adaptive music: one AudioStreamPlayer playing the MusicBank's AudioStreamInteractive,
## plus one stinger player. The director tells it the mood and the threat intensity;
## this node picks clips, walks playlists with quiet gaps, and rides the layers.
##
## Streams alive at once: 1 base (+1 stem on layered clips) decoding, 2+2 only during
## a crossfade; the stinger is a short one-shot. Silence is a 4 KB looping WAV.
##
## Layering (vertical): on clips with a percussion stem, intensity 0..1 raises the
## drums from -60 dB to 0 dB and dips the base by up to DUCK_DB so the drums sit in.
## Clips without a stem only get the base dip; above the danger threshold the
## director moves to the "danger" clip, whose drums then carry the rise.
## The stems are synthesized drum tracks rendered on each base track's beat grid
## (own work, CC0), so the tracks themselves did not need to be stems.

const MusicBank := preload("res://scripts/audio/music_bank.gd")
const AudioBuses := preload("res://scripts/audio/audio_buses.gd")

const DUCK_DB := -2.5
const STINGER_DUCK_DB := -9.0
const LAYER_SMOOTH := 0.6          # seconds to cover ~63% of an intensity change
const GAP_RANGE := {&"town_day": Vector2(20, 45), &"wilderness": Vector2(25, 55),
	&"town_night": Vector2(40, 80), &"wild_night": Vector2(35, 70)}

var bank: RefCounted               # MusicBank instance, null until loaded
var mood: StringName = &"silence"
var intensity := 0.0               # target 0..1, set by the director
var enabled := true
var log_changes := false

var _player: AudioStreamPlayer
var _stinger: AudioStreamPlayer
var _playback: AudioStreamPlaybackInteractive
var _pending: Array[String] = []
var _clip: StringName = &"silence"
var _clip_end := 0.0               # _clock when the current one-shot clip will have ended
var _gap_until := -1.0             # while > _clock the playlist rests in silence
var _playlist_pos: Dictionary = {} # mood -> index of the last clip played
var _layer := 0.0                  # smoothed intensity
var _duck_db := 0.0                # stinger duck, tweened
var _duck_tween: Tween
var _clock := 0.0
var _gap_mood: StringName = &""    # the mood whose playlist is resting in silence
var _clip_layer: Dictionary = {}   # clip -> smoothed layer amount (fades out after a switch)
var _layer_timer := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player = AudioStreamPlayer.new()
	_player.name = "Score"
	_player.bus = AudioBuses.bus_or_master(AudioBuses.MUSIC)
	add_child(_player)
	_stinger = AudioStreamPlayer.new()
	_stinger.name = "Stinger"
	_stinger.bus = _player.bus
	add_child(_stinger)
	for p in MusicBank.paths():
		if ResourceLoader.exists(p):
			ResourceLoader.load_threaded_request(p, "AudioStream")
			_pending.append(p)


## True once the score is built and playing.
func is_ready() -> bool:
	return _playback != null


func current_clip() -> StringName:
	return _clip


## Mood names: town_day, town_night, wilderness, wild_night, danger, combat, boss,
## tavern, silence. Unknown names are ignored.
func set_mood(m: StringName) -> void:
	if not MusicBank.MOODS.has(m):
		return
	if not enabled:
		m = &"silence"
	mood = m


## One-shot over the score: "victory", "discovery" or "combat". The score dips under it.
func stinger(kind: StringName, volume_db := 0.0) -> bool:
	var path: String = MusicBank.STINGERS.get(kind, "")
	var s := MusicBank.load_stream(path)
	if s == null:
		return false
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = false
	_stinger.stream = s
	_stinger.volume_db = volume_db
	_stinger.play()
	var hold := maxf(0.5, s.get_length() - 1.5)
	if _duck_tween:
		_duck_tween.kill()
	_duck_tween = create_tween()
	_duck_tween.tween_property(self, "_duck_db", STINGER_DUCK_DB, 0.25)
	_duck_tween.tween_interval(hold)
	_duck_tween.tween_property(self, "_duck_db", 0.0, 2.0)
	if log_changes:
		print("[audio] stinger %s" % kind)
	return true


func _process(delta: float) -> void:
	_clock += delta
	if _playback == null:
		_try_build()
		return
	_layer = lerpf(_layer, clampf(intensity, 0.0, 1.0), 1.0 - exp(-delta / LAYER_SMOOTH))
	_update_clip()
	_layer_timer -= delta
	if _layer_timer <= 0.0:
		_layer_timer = 0.05
		_apply_layers(0.05)


func _try_build() -> void:
	for p in _pending:
		if ResourceLoader.load_threaded_get_status(p) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			return
	bank = MusicBank.build()
	if log_changes and not bank.missing.is_empty():
		print("[audio] music files missing: %s" % [bank.missing])
	_player.stream = bank.stream
	_player.play()
	_playback = _player.get_stream_playback() as AudioStreamPlaybackInteractive
	if _playback == null:
		# no audio driver output (some headless setups): keep the bank, drive clips anyway
		push_warning("AdaptiveMusic: no interactive playback; music stays silent")


func _update_clip() -> void:
	var wanted: Array = MusicBank.MOODS.get(mood, [&"silence"])
	var in_mood := wanted.has(_clip)
	var ended: bool = in_mood and float(bank.lengths.get(_clip, 0.0)) > 0.0 and _clock >= _clip_end
	if in_mood and not ended:
		return
	if in_mood and ended:
		# playlist: rest, then the next track in this mood
		var gap: Vector2 = GAP_RANGE.get(mood, Vector2(20, 40))
		_gap_until = _clock + randf_range(gap.x, gap.y)
		_switch(&"silence")
		return
	if _clip == &"silence" and _gap_until > _clock and _is_playlist_mood(mood) and _gap_mood == mood:
		return   # still resting between two tracks of the same mood
	_switch(_next_in(mood))


func _is_playlist_mood(m: StringName) -> bool:
	return GAP_RANGE.has(m)


func _next_in(m: StringName) -> StringName:
	var list: Array = MusicBank.MOODS.get(m, [&"silence"])
	if list.size() == 1:
		return list[0]
	var i: int = _playlist_pos.get(m, randi() % list.size())
	i = (i + 1) % list.size()
	_playlist_pos[m] = i
	return list[i]


func _switch(clip: StringName) -> void:
	if clip == _clip:
		return
	if clip == &"silence":
		_gap_mood = mood if _is_playlist_mood(mood) else &""
	else:
		_gap_mood = &""
		_gap_until = -1.0
	if log_changes:
		print("[audio] music %s -> %s (mood %s, intensity %.2f)" % [_clip, clip, mood, intensity])
	# worst case the switch waits one bar, then the clip starts from the top
	var bar := 4.0 * 60.0 / maxf(_bpm(_clip), 1.0) if _clip != &"silence" else 0.0
	_clip = clip
	_clip_end = _clock + bar + float(bank.lengths.get(clip, 0.0))
	if _playback:
		_playback.switch_to_clip_by_name(clip)


func _bpm(clip: StringName) -> float:
	var c: Array = MusicBank.CLIPS.get(clip, [])
	return float(c[2]) if c.size() > 2 else 0.0


func _apply_layers(dt: float) -> void:
	var k := 1.0 - exp(-dt / LAYER_SMOOTH)
	for n: StringName in bank.layers:
		var s: AudioStreamSynchronized = bank.layers[n]
		var target := _layer if n == _clip else 0.0
		var v: float = lerpf(float(_clip_layer.get(n, 0.0)), target, k)
		_clip_layer[n] = v
		var stem: bool = s.stream_count > 1
		var base: float = bank.base_db.get(n, 0.0)
		s.set_sync_stream_volume(0, base + DUCK_DB * v * (1.0 if stem else 0.6) + _duck_db)
		if stem:
			var db := MusicBank.LAYER_OFF_DB if v < 0.001 else maxf(linear_to_db(v), MusicBank.LAYER_OFF_DB)
			s.set_sync_stream_volume(1, db + _duck_db)


## Current layer amount of the playing clip (0..1), for tests and debug overlays.
func layer_amount() -> float:
	return float(_clip_layer.get(_clip, 0.0))
