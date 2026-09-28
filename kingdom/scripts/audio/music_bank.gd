extends RefCounted
## Builds the adaptive score as one Godot 4.6 `AudioStreamInteractive`.
##
## Every mood is a clip; the clips that have a percussion stem are an
## `AudioStreamSynchronized` (base track + drums, sample-locked). The director turns
## the stem up with threat through `set_sync_stream_volume()`, which the playback
## reads live, so layering costs no restarts.
##
## Transitions are explicit per clip pair (no CLIP_ANY wildcard): in 4.6 a wildcard
## transition stops clip auto-advance from working, and the director sequences the
## exploration playlists itself anyway (track, quiet gap, next track).
##
## Nothing here is a saved .tres on purpose: new OGGs dropped in by the pipeline may
## not be imported yet, and bpm / loop are import options. `load_stream()` falls back
## to `AudioStreamOggVorbis.load_from_file()` for files the editor hasn't imported.
##
## Usage: var bank := MusicBank.build(); player.stream = bank.stream; ...
##   bank.clips: name -> index, bank.layers: name -> AudioStreamSynchronized,
##   bank.lengths: name -> seconds (0 = loops), bank.paths: every file used.

const MUSIC := "res://assets/audio/music/"
const MI := "res://assets/audio/music_interactive/"
const SILENCE := &"silence"

## name: [base file, stem file or "", bpm, loops, loop_offset_s, volume_db]
## bpm comes from an onset analysis of each file (see music_interactive/CREDITS.md);
## stems were rendered on that grid, so they only exist where the grid was stable.
const CLIPS := {
	&"town_day_a": [MUSIC + "mus_village_day.ogg", "", 73.96, false, 0.0, -3.0],
	&"town_day_b": [MUSIC + "mus_village_day_02.ogg", "", 86.58, false, 0.0, -3.0],
	&"town_night": [MUSIC + "mus_night.ogg", "", 110.0, false, 0.0, -7.0],
	&"wild_a": [MUSIC + "mus_explore.ogg", MI + "perc_explore.ogg", 109.32, false, 0.0, -4.0],
	&"wild_b": [MUSIC + "mus_explore_02.ogg", "", 71.54, false, 0.0, -4.0],
	&"wild_c": [MUSIC + "mus_explore_03.ogg", MI + "perc_explore_03.ogg", 101.98, false, 0.0, -4.0],
	&"wild_night": [MUSIC + "mus_night.ogg", MI + "perc_night.ogg", 110.0, false, 0.0, -7.0],
	&"danger": [MI + "mus_danger_stalk.ogg", MI + "perc_danger.ogg", 78.26, true, 0.0, -3.0],
	&"combat": [MUSIC + "mus_combat.ogg", "", 145.98, true, 0.0, -2.0],
	&"boss": [MI + "mus_boss.ogg", "", 114.0, true, 14.7508, -2.0],
	&"tavern": [MUSIC + "mus_tavern.ogg", "", 86.5, true, 0.0, -4.0],
}
## Mood -> clips it may play (a playlist is walked in order, starting at random).
const MOODS := {
	&"town_day": [&"town_day_a", &"town_day_b"],
	&"town_night": [&"town_night"],
	&"wilderness": [&"wild_a", &"wild_b", &"wild_c"],
	&"wild_night": [&"wild_night"],
	&"danger": [&"danger"],
	&"combat": [&"combat"],
	&"boss": [&"boss"],
	&"tavern": [&"tavern"],
	&"silence": [&"silence"],
}
const STINGERS := {
	&"victory": MI + "stinger_victory.ogg",
	&"discovery": MI + "stinger_discovery.ogg",
	&"combat": MUSIC + "mus_combat_stinger.ogg",
}
const LAYER_OFF_DB := -60.0

## Fade lengths in beats of the clip being left (the destination's bpm when the
## source has none, e.g. silence).
const FADE_DEFAULT := 4.0
const FADE_INTO_FIGHT := 1.0
const FADE_OUT_OF_FIGHT := 8.0
const FADE_DOOR := 2.0
const FADE_CREEP := 8.0

var stream: AudioStreamInteractive
var clips: Dictionary = {}       # StringName -> index
var layers: Dictionary = {}      # StringName -> AudioStreamSynchronized
var base_db: Dictionary = {}     # StringName -> clip volume (applied through layer 0 or the player)
var lengths: Dictionary = {}     # StringName -> seconds, 0 = loops forever
var missing: Array[String] = []


## Paths the bank needs, for ResourceLoader.load_threaded_request().
static func paths() -> Array[String]:
	var out: Array[String] = []
	for c: Array in CLIPS.values():
		for p: String in [c[0], c[1]]:
			if p != "" and not out.has(p):
				out.append(p)
	for p: String in STINGERS.values():
		out.append(p)
	return out


## Loads an audio file whether or not the editor has imported it yet.
static func load_stream(path: String) -> AudioStream:
	if path == "":
		return null
	if ResourceLoader.exists(path):
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_LOADED or status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			var s := ResourceLoader.load_threaded_get(path) as AudioStream
			if s:
				return s
		return load(path) as AudioStream
	if FileAccess.file_exists(path):
		if path.ends_with(".ogg"):
			return AudioStreamOggVorbis.load_from_file(path)
		if path.ends_with(".mp3"):
			return AudioStreamMP3.load_from_file(path)
		if path.ends_with(".wav"):
			return AudioStreamWAV.load_from_file(path)
	return null


static func build() -> RefCounted:
	var b = new()
	b._build()
	return b


func _build() -> void:
	stream = AudioStreamInteractive.new()
	var names: Array[StringName] = [SILENCE]
	for n: StringName in CLIPS:
		names.append(n)
	stream.clip_count = names.size()
	for i in names.size():
		var n := names[i]
		stream.set_clip_name(i, n)
		stream.set_clip_auto_advance(i, AudioStreamInteractive.AUTO_ADVANCE_DISABLED)
		clips[n] = i
		if n == SILENCE:
			stream.set_clip_stream(i, _silence())
			lengths[n] = 0.0
			base_db[n] = 0.0
			continue
		var c: Array = CLIPS[n]
		var base := _ogg(String(c[0]), float(c[2]), bool(c[3]), float(c[4]))
		if base == null:
			missing.append(String(c[0]))
			stream.set_clip_stream(i, _silence())
			lengths[n] = 0.0
			base_db[n] = 0.0
			continue
		lengths[n] = 0.0 if bool(c[3]) else base.get_length()
		base_db[n] = float(c[5])
		var stem := _ogg(String(c[1]), float(c[2]), bool(c[3]), 0.0) if String(c[1]) != "" else null
		if String(c[1]) != "" and stem == null:
			missing.append(String(c[1]))
		# Every music clip goes through a Synchronized so its level can be set per clip
		# (layer 0 = base, layer 1 = percussion when there is one). Cheap: it is just a mixer.
		var sync := AudioStreamSynchronized.new()
		sync.stream_count = 2 if stem else 1
		sync.set_sync_stream(0, base)
		sync.set_sync_stream_volume(0, float(c[5]))
		if stem:
			sync.set_sync_stream(1, stem)
			sync.set_sync_stream_volume(1, LAYER_OFF_DB)
			layers[n] = sync
		stream.set_clip_stream(i, sync)
		if not layers.has(n):
			layers[n] = sync   # volume-only (no stem); layer_count() tells them apart
	_add_transitions(names)
	stream.initial_clip = clips[SILENCE]


## True when the clip has a percussion stem.
func has_stem(clip: StringName) -> bool:
	var s: AudioStreamSynchronized = layers.get(clip)
	return s != null and s.stream_count > 1


func _add_transitions(names: Array[StringName]) -> void:
	for from in names:
		for to in names:
			if from == to:
				continue
			var from_time := AudioStreamInteractive.TRANSITION_FROM_TIME_NEXT_BAR
			var fade := AudioStreamInteractive.FADE_CROSS
			var beats := FADE_DEFAULT
			if to == &"combat" or to == &"boss":
				from_time = AudioStreamInteractive.TRANSITION_FROM_TIME_NEXT_BEAT
				beats = FADE_INTO_FIGHT
			elif from == &"combat" or from == &"boss":
				beats = FADE_OUT_OF_FIGHT
			elif to == &"tavern" or from == &"tavern":
				from_time = AudioStreamInteractive.TRANSITION_FROM_TIME_IMMEDIATE
				beats = FADE_DOOR
			elif to == &"danger":
				beats = FADE_CREEP
			if from == SILENCE:
				from_time = AudioStreamInteractive.TRANSITION_FROM_TIME_IMMEDIATE
				fade = AudioStreamInteractive.FADE_IN
			elif to == SILENCE:
				fade = AudioStreamInteractive.FADE_OUT
			stream.add_transition(clips[from], clips[to], from_time, AudioStreamInteractive.TRANSITION_TO_TIME_START, fade, beats)


func _ogg(path: String, bpm: float, loop: bool, loop_offset: float) -> AudioStream:
	var s := load_stream(path)
	if s is AudioStreamOggVorbis:
		var o := s as AudioStreamOggVorbis
		o.loop = loop
		o.loop_offset = loop_offset
		o.bpm = bpm
		o.bar_beats = 4
		# beat_count makes the OGG playback loop on the beat grid instead of at the file
		# end, so it is only set for one-shot tracks (the loops are cut sample-exact).
		o.beat_count = 0 if loop else int(o.get_length() * bpm / 60.0)
	return s


## One second of looping silence (8-bit, 4 kHz): 4 KB, costs nothing to mix.
static func _silence() -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_8_BITS
	w.mix_rate = 4000
	w.stereo = false
	var d := PackedByteArray()
	d.resize(4000)
	d.fill(0)
	w.data = d
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = 4000
	return w
