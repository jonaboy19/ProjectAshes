extends RefCounted
## Runtime bus layout for the audio director. default_bus_layout.tres already has
## Master (limiter), Music, Ambience, SFX, UI and Interior (reverb, sends to SFX);
## this adds what the adaptive / environmental audio needs, idempotently, so it
## works whether or not the .tres was updated and survives AudioServer layout swaps:
##
##   Master
##   ├─ Music      + LowPass "Muffle"   (underwater)
##   ├─ Ambience   + LowPass "Muffle"   (underwater)
##   │   └─ Weather  + LowPass "Muffle" (indoors: rain on the roof, wind behind walls)
##   ├─ SFX        + LowPass "Muffle"   (underwater)
##   │   ├─ Interior + Reverb           (preset per room: tavern, smithy, healer, house, guild)
##   │   └─ SFXFar   + LowPass 2.4 kHz  (sounds beyond FAR_DISTANCE: distance air absorption)
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
const OPEN_HZ := 20000.0

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
	for b in [MUSIC, AMBIENCE, SFX, UI]:
		_bus(b, "Master")
	_bus(WEATHER, AMBIENCE)
	_bus(INTERIOR, SFX)
	_bus(SFX_FAR, SFX)
	for b in [MUSIC, AMBIENCE, WEATHER, SFX]:
		_lowpass(b, "Muffle", OPEN_HZ, false)
	var far := _lowpass(SFX_FAR, "Distance", 2400.0, true)
	far.resonance = 0.5
	if _effect(INTERIOR, "AudioEffectReverb") == null:
		var r := AudioEffectReverb.new()
		r.resource_name = "Reverb"
		AudioServer.add_bus_effect(AudioServer.get_bus_index(INTERIOR), r)
		set_room("tavern")


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
