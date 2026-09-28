extends Node
## Environmental audio for the director: wind and rain beds, synced thunder, bird
## and insect spots by forest density and time of day, indoor muffling + room
## reverb, underwater muffling.
##
## Public (via the Audio autoload, which forwards here):
##   set_wind(strength)     weather.gd scale: 1 = calm breeze, 2.4 = storm; 0..3.
##   set_rain(amount)       0..1 rain bed level (alias: set_weather_intensity).
##   set_weather(kind)      "", "rain", "storm", "wind": picks the bed and a default level.
##   thunder(delay)         thunder heard `delay` s from now (sound travel time).
## All are safe at any time, from any state, before the tree is ready, in any order.
##
## Budget: wind 1 stream, rain 1 (2 only while crossing from light to heavy rain;
## heavy rain also fades the wind out, the storm bed has its own), thunder 1-2
## transient. Idle beds are stopped, not muted.

const AudioBuses := preload("res://scripts/audio/audio_buses.gd")
const MusicBank := preload("res://scripts/audio/music_bank.gd")
const AMB := "res://assets/audio/ambience/"
const TICK := 0.1
const FADE_RATE := 0.6             # gain units per second
const THUNDER_DEBOUNCE := 1.0

## Director-provided: func(sound, min_dist, max_dist, min_h, max_h, volume_db) -> void
var spot_fn: Callable
## Director-provided: func(sound) -> bool
var has_fn: Callable
## Director-provided stream picker: func(sound) -> AudioStream (random variant)
var pick_fn: Callable

var wind_strength := 1.0
var rain_amount := 0.0
var weather_kind := ""
var indoors := ""
var underwater := false

var _wind: AudioStreamPlayer
var _rain_light: AudioStreamPlayer
var _rain_heavy: AudioStreamPlayer
var _thunder: Array[AudioStreamPlayer] = []
var _gain := {}                    # player -> current linear gain
var _tick := 0.0
var _clock := 0.0
var _last_thunder := -100.0
var _nature_timer := 5.0
var _ready_done := false
var _rain_explicit := false        # set_rain() was called: set_weather() stops guessing levels
var _wind_explicit := false
var _thunder_started := {}         # player -> _clock at start


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_wind = _bed("Wind")
	_rain_light = _bed("RainLight")
	_rain_heavy = _bed("RainHeavy")
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.name = "Thunder%d" % i
		p.bus = AudioBuses.bus_or_master(AudioBuses.WEATHER)
		add_child(p)
		_thunder.append(p)
	_ready_done = true


# ------------------------------------------------------------------ public
func set_wind(strength: float) -> void:
	_wind_explicit = true
	wind_strength = clampf(strength if is_finite(strength) else 1.0, 0.0, 3.0)


func set_rain(amount: float) -> void:
	_rain_explicit = true
	rain_amount = clampf(amount if is_finite(amount) else 0.0, 0.0, 1.0)


func set_weather(kind: String) -> void:
	weather_kind = kind
	var rain := {"rain": 0.55, "storm": 1.0}.get(kind, 0.0) as float
	var wind := {"storm": 2.4, "wind": 2.2}.get(kind, 1.0) as float
	if not _rain_explicit:
		rain_amount = rain
	if not _wind_explicit:
		wind_strength = wind


## Thunder `delay` seconds from now (a strike ~343 m away per second of delay).
## Short delays play the close crack, long ones a low, soft roll.
func thunder(delay := 0.0) -> void:
	var d := clampf(delay if is_finite(delay) else 0.0, 0.0, 30.0)
	var vol := lerpf(0.0, -12.0, clampf(d / 12.0, 0.0, 1.0))
	if d <= 0.02 or not is_inside_tree():
		play_thunder(vol, d < 3.0)
		return
	get_tree().create_timer(d, true).timeout.connect(play_thunder.bind(vol, d < 3.0))


## Thunder right now. `near` = the crack variant; otherwise the distant roll.
func play_thunder(volume_db := 0.0, near := true) -> void:
	if not _ready_done or _clock - _last_thunder < THUNDER_DEBOUNCE or not pick_fn.is_valid():
		return
	_last_thunder = _clock
	var s: AudioStream = pick_fn.call("thunder_near" if near else "thunder_far")
	if s == null:
		s = pick_fn.call("thunder")
	if s == null:
		return
	var p := _thunder[0]
	for q in _thunder:
		if not q.playing:
			p = q
			break
		if float(_thunder_started.get(q, 0.0)) < float(_thunder_started.get(p, 0.0)):
			p = q
	_thunder_started[p] = _clock
	p.stream = s
	p.volume_db = volume_db
	p.pitch_scale = randf_range(0.94, 1.04)
	p.play()


## "" outdoors, otherwise the room kind (tavern, smithy, healer, house, guild).
func set_indoors(kind: String) -> void:
	if kind == indoors:
		return
	indoors = kind
	if kind != "":
		AudioBuses.set_room(kind)
		AudioBuses.muffle(self, AudioBuses.WEATHER, 650.0, -6.0, 0.6)
	else:
		AudioBuses.muffle(self, AudioBuses.WEATHER, AudioBuses.OPEN_HZ, 0.0, 0.8)


func set_underwater(on: bool) -> void:
	if on == underwater:
		return
	underwater = on
	var t := 0.25 if on else 0.6
	AudioBuses.muffle(self, AudioBuses.SFX, 520.0 if on else AudioBuses.OPEN_HZ, -3.0 if on else 0.0, t)
	AudioBuses.muffle(self, AudioBuses.AMBIENCE, 380.0 if on else AudioBuses.OPEN_HZ, -6.0 if on else 0.0, t)
	AudioBuses.muffle(self, AudioBuses.MUSIC, 900.0 if on else AudioBuses.OPEN_HZ, -4.0 if on else 0.0, t)


## Target gains (0..1) of the three beds, for tests / debug.
func targets() -> Dictionary:
	var heavy := 1.0 if weather_kind == "storm" else smoothstep(0.7, 0.9, rain_amount)
	var gust := 0.85 + 0.15 * sin(_clock * 0.37) * sin(_clock * 0.13 + 1.0)
	var wind := smoothstep(1.05, 2.5, wind_strength) * gust * (1.0 - 0.85 * heavy * rain_amount)
	return {"wind": wind, "rain_light": rain_amount * sqrt(1.0 - heavy), "rain_heavy": rain_amount * sqrt(heavy)}


# ------------------------------------------------------------------ loop
func _process(delta: float) -> void:
	_clock += delta
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = TICK
	var t := targets()
	_drive(_wind, "amb_wind", float(t["wind"]), 2.0, 0.94 + 0.1 * float(t["wind"]))
	_drive(_rain_light, "amb_rain", float(t["rain_light"]), 3.0, 1.0)
	_drive(_rain_heavy, "amb_storm", float(t["rain_heavy"]), 1.0, 1.0)


func _drive(p: AudioStreamPlayer, file: String, target: float, top_db: float, pitch: float) -> void:
	var g: float = move_toward(float(_gain.get(p, 0.0)), target, FADE_RATE * TICK)
	_gain[p] = g
	if g < 0.01:
		if p.playing:
			p.stop()
		return
	if not p.playing:
		if p.stream == null:
			var s := MusicBank.load_stream(AMB + file + ".ogg")
			if s is AudioStreamOggVorbis:
				(s as AudioStreamOggVorbis).loop = true
			p.stream = s
		if p.stream == null:
			return
		p.play(randf() * maxf(0.0, p.stream.get_length() - 1.0))
	p.volume_db = linear_to_db(g) + top_db
	p.pitch_scale = pitch


## Bird / insect spots. The director calls this every context tick (0.5 s) with the
## listener's surroundings; the rate follows forest density and time of day.
func nature_tick(dt: float, night: bool, hour: float, forest: float, in_town: bool) -> void:
	_nature_timer -= dt
	if _nature_timer > 0.0:
		return
	if indoors != "" or underwater or rain_amount > 0.45 or wind_strength > 2.2 or not spot_fn.is_valid():
		_nature_timer = 4.0
		return
	var d := clampf(forest, 0.0, 1.0)
	if night:
		# crickets: loudest in meadows and forest edges, sparser under a closed canopy
		_nature_timer = (8.0 if in_town else lerpf(2.5, 7.0, d)) * randf_range(0.7, 1.3)
		spot_fn.call("cricket", 3.0, 12.0, 0.0, 0.3, -4.0 + (1.0 - d) * 3.0)
	else:
		var dawn := hour >= 5.0 and hour < 8.5
		var dusk := hour >= 18.5 and hour < 20.5
		_nature_timer = (25.0 if in_town else lerpf(14.0, 3.5, d)) * (0.6 if dawn or dusk else 1.0) * randf_range(0.7, 1.3)
		var sound := "bird_chirp" if randf() < 0.6 or not (has_fn.is_valid() and bool(has_fn.call("bird_blackbird"))) else "bird_blackbird"
		var high := d > 0.2
		spot_fn.call(sound, 6.0, 22.0, 3.0 if high else 1.0, 9.0 if high else 3.5, -6.0 + 4.0 * d)


func _bed(n: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.name = n
	p.bus = AudioBuses.bus_or_master(AudioBuses.WEATHER)
	add_child(p)
	_gain[p] = 0.0
	return p
