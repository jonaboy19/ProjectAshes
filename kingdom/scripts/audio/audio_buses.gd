extends RefCounted
## Runtime bus layout for the audio director. default_bus_layout.tres already has
## Master (limiter), Music, Ambience, SFX, UI and Interior (reverb, sends to SFX);
## this adds what the adaptive / environmental audio needs, idempotently, so it
## works whether or not the .tres was updated and survives AudioServer layout swaps:
##
##   Master
##   ├─ Music      + LowPass "Muffle"   (underwater) + Compressor "Duck" (sidechain: Voice)
##   ├─ Ambience   + LowPass "Muffle"   (underwater) + Compressor "Duck" (sidechain: Voice, gentler)
##   │   ├─ Weather  + LowPass "Muffle" (indoors: rain on the roof, wind behind walls)
##   │   └─ AmbOccluded + LowPass 1.1 kHz (positional emitters behind a wall: soundscape.gd occlusion)
##   ├─ SFX        + LowPass "Muffle"   (underwater)
##   │   ├─ Interior + Reverb           (preset per room: tavern, smithy, healer, house, guild)
##   │   ├─ SFXFar   + LowPass 2.4 kHz  (sounds beyond FAR_DISTANCE: distance air absorption)
##   │   └─ Zone     + Reverb (wet only) (Area3D reverb sends: alley, street, room, church, forest; soundscape.gd)
##   ├─ Voice      (dialogue, barks: ducks Music and Ambience through the sidechain compressors)
##   └─ UI
##
## A low-pass that is fully open is disabled, so the idle cost is zero; muffle()
## enables it and sweeps the cutoff.

const MUSIC := "Music"
const AMBIENCE := "Ambience"
const WEATHER := "Weather"
const SFX := "SFX"
const SFX_FAR := "SFXFar"
const INTERIOR := "Interior"
const UI := "UI"
const VOICE := "Voice"
const ZONE := "Zone"
const AMB_OCCLUDED := "AmbOccluded"
const OPEN_HZ := 20000.0

## Zone reverb (Area3D reverb sends into the wet-only Zone bus) per acoustic space; amount = the Area3D send level.
## alley: tight slap between close walls; street: light early reflections; room / tavern / church: interiors;
## forest: soft diffuse tail. "open" = no send.
const ZONES := {
	"alley": {"room_size": 0.28, "damping": 0.35, "predelay_msec": 9.0, "spread": 0.9, "hipass": 0.25, "amount": 0.32},
	"street": {"room_size": 0.36, "damping": 0.55, "predelay_msec": 16.0, "spread": 1.0, "hipass": 0.3, "amount": 0.16},
	"room": {"room_size": 0.2, "damping": 0.75, "predelay_msec": 6.0, "spread": 0.6, "hipass": 0.12, "amount": 0.22},
	"tavern": {"room_size": 0.42, "damping": 0.62, "predelay_msec": 14.0, "spread": 0.8, "hipass": 0.15, "amount": 0.26},
	"church": {"room_size": 0.86, "damping": 0.25, "predelay_msec": 42.0, "spread": 1.0, "hipass": 0.1, "amount": 0.45},
	"forest": {"room_size": 0.55, "damping": 0.8, "predelay_msec": 28.0, "spread": 1.0, "hipass": 0.35, "amount": 0.14},
}

static var _tweens: Dictionary = {}   # bus -> running muffle Tween

## Interior reverb per room kind (AudioEffectReverb fields).
const ROOMS := {
	"tavern": {"room_size": 0.45, "damping": 0.6, "wet": 0.15, "predelay_msec": 22.0, "spread": 0.8, "hipass": 0.15},
	"smithy": {"room_size": 0.38, "damping": 0.3, "wet": 0.2, "predelay_msec": 14.0, "spread": 0.6, "hipass": 0.2},
	"healer": {"room_size": 0.26, "damping": 0.7, "wet": 0.12, "predelay_msec": 12.0, "spread": 0.6, "hipass": 0.15},
	"house": {"room_size": 0.18, "damping": 0.8, "wet": 0.08, "predelay_msec": 8.0, "spread": 0.5, "hipass": 0.1},
	"guild": {"room_size": 0.62, "damping": 0.5, "wet": 0.18, "predelay_msec": 30.0, "spread": 0.9, "hipass": 0.15},
}


static func bus_or_master(bus: String) -> String:
	return bus if AudioServer.get_bus_index(bus) >= 0 else "Master"


## Creates missing buses / effects. Safe to call any number of times.
static func ensure_layout() -> void:
	for b in [MUSIC, AMBIENCE, SFX, VOICE, UI]:
		_bus(b, "Master")
	_bus(WEATHER, AMBIENCE)
	_bus(AMB_OCCLUDED, AMBIENCE)
	_bus(INTERIOR, SFX)
	_bus(SFX_FAR, SFX)
	_bus(ZONE, SFX)
	for b in [MUSIC, AMBIENCE, WEATHER, SFX]:
		_lowpass(b, "Muffle", OPEN_HZ, false)
	var far := _lowpass(SFX_FAR, "Distance", 2400.0, true)
	far.resonance = 0.5
	if _effect(INTERIOR, "AudioEffectReverb") == null:
		var r := AudioEffectReverb.new()
		r.resource_name = "Reverb"
		AudioServer.add_bus_effect(AudioServer.get_bus_index(INTERIOR), r)
		set_room("tavern")
	var occ := _lowpass(AMB_OCCLUDED, "Occlusion", 1100.0, true)
	occ.resonance = 0.4
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(AMB_OCCLUDED), -4.0)
	if _effect(ZONE, "AudioEffectReverb") == null:
		var z := AudioEffectReverb.new()
		z.resource_name = "ZoneReverb"
		z.dry = 0.0          # Area3D sends only the reflections here; the dry signal stays on its own bus
		z.wet = 0.5
		AudioServer.add_bus_effect(AudioServer.get_bus_index(ZONE), z)
	# SFX trim (+4 dB): one-shots are matched on max momentary loudness (build_audio.py), which left blows and feet
	# only 1-5 dB over music + bed in the fm01 duel; the master limiter (-1 dB) catches the rare stack.
	if _effect_slot(SFX, "MixTrim") < 0:
		var trim := AudioEffectAmplify.new()
		trim.resource_name = "MixTrim"
		trim.volume_db = 4.0
		AudioServer.add_bus_effect(AudioServer.get_bus_index(SFX), trim)
	# Combat duck: an Amplify per bus that the director tweens while fighting (bus volumes stay the player's settings).
	for b in [MUSIC, AMBIENCE]:
		if _effect_slot(b, "CombatDuck") < 0:
			var amp := AudioEffectAmplify.new()
			amp.resource_name = "CombatDuck"
			AudioServer.add_bus_effect(AudioServer.get_bus_index(b), amp)
	# Dialogue ducking (built-in sidechain): Voice pushes Music down ~6 dB and the ambience ~3 dB while a line plays.
	_duck(MUSIC, 0.06, 4.0)
	_duck(AMBIENCE, 0.1, 2.5)


static func _duck(bus: String, threshold: float, ratio: float) -> void:
	if _effect_slot(bus, "Duck") >= 0:
		return
	var c := AudioEffectCompressor.new()
	c.resource_name = "Duck"
	c.threshold = linear_to_db(threshold)
	c.ratio = ratio
	c.attack_us = 20000.0
	c.release_ms = 450.0
	c.gain = 0.0
	c.sidechain = VOICE
	AudioServer.add_bus_effect(AudioServer.get_bus_index(bus), c)


## Fighting: music and ambience -3 dB so blades and blows read (0.4 s in, 2.5 s back out).
static func combat_duck(host: Node, on: bool) -> void:
	for pair in [[MUSIC, -3.0], [AMBIENCE, -3.0]]:
		var idx := AudioServer.get_bus_index(pair[0])
		var slot := _effect_slot(pair[0], "CombatDuck")
		if idx < 0 or slot < 0:
			continue
		var amp := AudioServer.get_bus_effect(idx, slot) as AudioEffectAmplify
		var key: String = pair[0] + ":duck"
		var old: Tween = _tweens.get(key)
		if old and old.is_valid():
			old.kill()
		var t := host.create_tween()
		_tweens[key] = t
		t.tween_property(amp, "volume_db", float(pair[1]) if on else 0.0, 0.4 if on else 2.5)


## Zone reverb character (ZONES key); returns the Area3D send amount (0 for "open" / unknown).
static func set_zone(kind: String) -> float:
	var r := _effect(ZONE, "AudioEffectReverb") as AudioEffectReverb
	if r == null or not ZONES.has(kind):
		return 0.0
	var p: Dictionary = ZONES[kind]
	for k: String in p:
		if k != "amount":
			r.set(k, p[k])
	return float(p["amount"])


## Applies a room's reverb character to the Interior bus ("" leaves it as is).
static func set_room(kind: String) -> void:
	var r := _effect(INTERIOR, "AudioEffectReverb") as AudioEffectReverb
	if r == null or not ROOMS.has(kind):
		return
	var p: Dictionary = ROOMS[kind]
	for k: String in p:
		r.set(k, p[k])


## Sweeps a bus's "Muffle" low-pass to `hz` (OPEN_HZ = off) over `time` seconds and
## sets the bus level to `db`. Uses a tween on `host` (any node in the tree).
static func muffle(host: Node, bus: String, hz: float, db := 0.0, time := 0.5) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx < 0:
		return
	var slot := _effect_slot(bus, "Muffle")
	if slot < 0:
		return
	var lp := AudioServer.get_bus_effect(idx, slot) as AudioEffectLowPassFilter
	var closing := hz < OPEN_HZ - 1.0
	if closing:
		AudioServer.set_bus_effect_enabled(idx, slot, true)
	var old: Tween = _tweens.get(bus)
	if old and old.is_valid():
		old.kill()
	var t := host.create_tween().set_parallel()
	_tweens[bus] = t
	# sweep in the log domain so the ear hears an even close / open
	t.tween_method(func(v: float) -> void: lp.cutoff_hz = pow(2.0, v), log(maxf(lp.cutoff_hz, 20.0)) / log(2.0), log(hz) / log(2.0), time)
	t.tween_method(func(v: float) -> void: AudioServer.set_bus_volume_db(idx, v), AudioServer.get_bus_volume_db(idx), db, time)
	if not closing:
		t.chain().tween_callback(func() -> void:
			if lp.cutoff_hz >= OPEN_HZ - 1.0:
				AudioServer.set_bus_effect_enabled(idx, slot, false))


static func muffle_cutoff(bus: String) -> float:
	var idx := AudioServer.get_bus_index(bus)
	var slot := _effect_slot(bus, "Muffle")
	if idx < 0 or slot < 0 or not AudioServer.is_bus_effect_enabled(idx, slot):
		return OPEN_HZ
	return (AudioServer.get_bus_effect(idx, slot) as AudioEffectLowPassFilter).cutoff_hz


static func _bus(name: String, send: String) -> int:
	var idx := AudioServer.get_bus_index(name)
	if idx < 0:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, name)
		AudioServer.set_bus_send(idx, send)
	return idx


static func _lowpass(bus: String, label: String, hz: float, enabled: bool) -> AudioEffectLowPassFilter:
	var idx := AudioServer.get_bus_index(bus)
	var slot := _effect_slot(bus, label)
	if slot >= 0:
		return AudioServer.get_bus_effect(idx, slot) as AudioEffectLowPassFilter
	var lp := AudioEffectLowPassFilter.new()
	lp.resource_name = label
	lp.cutoff_hz = hz
	AudioServer.add_bus_effect(idx, lp)
	AudioServer.set_bus_effect_enabled(idx, AudioServer.get_bus_effect_count(idx) - 1, enabled)
	return lp


static func _effect_slot(bus: String, label: String) -> int:
	var idx := AudioServer.get_bus_index(bus)
	if idx < 0:
		return -1
	for i in AudioServer.get_bus_effect_count(idx):
		if AudioServer.get_bus_effect(idx, i).resource_name == label:
			return i
	return -1


static func _effect(bus: String, cls: String) -> AudioEffect:
	var idx := AudioServer.get_bus_index(bus)
	if idx < 0:
		return null
	for i in AudioServer.get_bus_effect_count(idx):
		var e := AudioServer.get_bus_effect(idx, i)
		if e.is_class(cls):
			return e
	return null
