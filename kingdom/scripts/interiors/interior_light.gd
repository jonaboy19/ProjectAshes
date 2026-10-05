extends RefCounted
## Interior light driver (package F6): what the light inside a building looks like at a given hour. Pure functions of
## the hour (WorldSim.time_of_day), so they are testable without a scene; scripts/interiors/modular_interior.gd applies
## the result to its window glass, lights and Environment, a couple of times per second and when the hour changes.
##
##   InteriorLight.state(hour, kind) -> {daylight, window_color, window_energy, hearth_lit, hearth_energy, lamp_on,
##                                      lamp_energy, ambient_color, ambient_energy, day_light_energy}
##
## Daylight rises from 05:30 to 08:00, holds to 16:30 and fades out by 19:30. Windows go from cool moonlight to
## warm dawn and dusk to bright day; the hearth is lit in the morning and from late afternoon (always in a tavern or
## bakery) and only embers otherwise; lamps come on when the daylight is thin. An unlit night room is dark.
## Preload this script; no class_name.

const DAWN := 5.5
const FULL_MORNING := 8.0
const FULL_EVENING := 16.5
const DUSK_END := 19.5

const NIGHT_WINDOW := Color(0.20, 0.27, 0.48)
const DAWN_WINDOW := Color(1.0, 0.66, 0.42)
const DAY_WINDOW := Color(1.0, 0.95, 0.82)
const NIGHT_AMBIENT := Color(0.34, 0.38, 0.55)
const DAY_AMBIENT := Color(1.0, 0.92, 0.80)
const FIRE_AMBIENT := Color(1.0, 0.78, 0.55)


## 0 at night, 1 in full day, smooth through dawn and dusk.
static func daylight(hour: float) -> float:
	var h := fposmod(hour, 24.0)
	if h < DAWN or h >= DUSK_END:
		return 0.0
	if h < FULL_MORNING:
		return smoothstep(DAWN, FULL_MORNING, h)
	if h <= FULL_EVENING:
		return 1.0
	return 1.0 - smoothstep(FULL_EVENING, DUSK_END, h)


## Is the hearth burning at this hour? `always` for taverns and bakeries (kitchens that never go cold).
static func hearth_lit(hour: float, always := false) -> bool:
	if always:
		return true
	var h := fposmod(hour, 24.0)
	return h < 9.0 or h >= 16.0


static func lamp_on(hour: float) -> bool:
	return daylight(hour) < 0.45


static func window_color(hour: float) -> Color:
	var h := fposmod(hour, 24.0)
	var dl := daylight(h)
	# Dawn and dusk are orange: the lower the sun, the warmer.
	var warm := pow(sin(PI * dl), 0.7) if dl > 0.0 and dl < 1.0 else 0.0
	var c := NIGHT_WINDOW.lerp(DAY_WINDOW, dl)
	return c.lerp(DAWN_WINDOW, clampf(warm * 1.2, 0.0, 0.9))


## Everything the room needs for `hour`. `kind` = the layout category ("house", "shop", "tavern") or a layout id.
static func state(hour: float, kind := "house") -> Dictionary:
	var dl := daylight(hour)
	var always := kind == "tavern" or kind == "alehouse" or kind == "tavern_inn" or kind == "bakery"
	var hearth := hearth_lit(hour, always)
	var lamp := lamp_on(hour)
	var fire_part := 0.0
	if hearth:
		fire_part += 0.15
	if lamp:
		fire_part += 0.10
	var ambient := lerpf(0.08, 0.62, dl) + fire_part
	return {
		"daylight": dl,
		"window_color": window_color(hour),
		"window_energy": lerpf(0.25, 1.5, dl),
		"day_light_energy": lerpf(0.0, 1.4, dl),
		"hearth_lit": hearth,
		"hearth_energy": 1.0 if hearth else 0.0,
		"fire_glow": 2.2 if hearth else 0.15,
		"lamp_on": lamp,
		"lamp_energy": 0.8 if lamp else 0.0,
		"ambient_color": NIGHT_AMBIENT.lerp(DAY_AMBIENT, dl).lerp(FIRE_AMBIENT, fire_part * 0.9),
		"ambient_energy": ambient,
	}


## A single comparable number for "how bright is this room" (used by the tests: it must change with the hour).
static func brightness(hour: float, kind := "house") -> float:
	var s := state(hour, kind)
	return float(s["ambient_energy"]) + float(s["day_light_energy"]) + float(s["hearth_energy"]) * 0.25 + float(s["lamp_energy"]) * 0.2
