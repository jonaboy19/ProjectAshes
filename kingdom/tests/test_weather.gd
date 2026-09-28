extends GdUnitTestSuite
## Weather: each state grades the environment in the right direction, blends are
## gradual, the daily Markov schedule is deterministic and snow stays region-gated.

const Weather := preload("res://scripts/world/weather.gd")

var env: Environment
var sun: DirectionalLight3D


func _make() -> Weather:
	var host: Node3D = auto_free(Node3D.new())
	add_child(host)
	env = Environment.new()
	env.fog_enabled = true
	env.fog_density = 0.0006
	env.fog_light_color = Color("c9d4e6")
	env.fog_sky_affect = 0.4
	env.volumetric_fog_density = 0.0025
	env.ambient_light_energy = 0.7
	env.tonemap_exposure = 1.2
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.28
	sun = DirectionalLight3D.new()
	sun.light_energy = 1.7
	host.add_child(sun)
	var cam := Camera3D.new()
	host.add_child(cam)
	var w: Weather = Weather.new()
	w.auto = false
	w.play_thunder_audio = false
	w.ground_height = func(_x: float, _z: float) -> float: return 0.0
	host.add_child(w)
	w.setup(env, sun, cam)
	return w


## Snap to a state and let one 10 Hz update apply it.
func _force(w: Weather, state: String) -> void:
	w.set_weather(state, 0.0)
	w.step(0.1)


func test_every_state_moves_fog_and_sun_the_right_way() -> void:
	var w := _make()
	_force(w, "clear")
	var fog0 := env.fog_density
	var sun0 := sun.light_energy
	var sky0 := env.fog_sky_affect
	assert_float(fog0).is_equal_approx(0.0006, 0.00001)
	assert_float(sun0).is_equal_approx(1.7, 0.001)
	var last_fog := fog0
	var last_sun := sun0
	# Clear -> cloudy -> overcast -> rain -> storm gets steadily foggier and darker.
	for s: String in ["cloudy", "overcast", "rain", "storm"]:
		_force(w, s)
		assert_str(w.current_name()).is_equal(s)
		assert_float(env.fog_density).override_failure_message("%s fog" % s).is_greater(last_fog)
		assert_float(sun.light_energy).override_failure_message("%s sun" % s).is_less(last_sun)
		assert_float(env.fog_sky_affect).is_greater(sky0)
		last_fog = env.fog_density
		last_sun = sun.light_energy
	# Morning mist: the densest fog of all, but the sun still shows through.
	_force(w, "fog")
	assert_float(env.fog_density).is_greater(last_fog)
	assert_float(sun.light_energy).is_less(sun0)
	assert_float(sun.light_energy).is_greater(last_sun)
	assert_float(env.fog_height_density).is_greater(0.0)
	# Back to clear restores the scene's own values exactly (no compounding).
	_force(w, "clear")
	assert_float(env.fog_density).is_equal_approx(fog0, 0.000001)
	assert_float(sun.light_energy).is_equal_approx(sun0, 0.0001)
	assert_float(env.fog_sky_affect).is_equal_approx(sky0, 0.0001)
	assert_float(env.fog_height_density).is_equal_approx(0.0, 0.000001)


func test_base_values_follow_the_day_night_cycle() -> void:
	var w := _make()
	_force(w, "overcast")
	var dim := sun.light_energy
	# main.gd rewrites the sun every frame; the weather multiplier applies to the new base.
	sun.light_energy = 0.42
	w.step(0.1)
	assert_float(sun.light_energy).is_less(0.42)
	assert_float(sun.light_energy).is_less(dim)
	w.step(0.1)
	w.step(0.1)
	assert_float(sun.light_energy).is_equal_approx(0.42 * 0.42, 0.001)


func test_rain_and_storm() -> void:
	var w := _make()
	_force(w, "clear")
	assert_bool(w.is_raining()).is_false()
	assert_float(w.noise_mult()).is_equal(1.0)
	_force(w, "rain")
	assert_bool(w.is_raining()).is_true()
	assert_float(w.noise_mult()).is_less(1.0)
	assert_float(w.fire_mult()).is_less(1.0)
	assert_bool(w.get_node("Rain").visible).is_true()
	assert_int(w.rain_particle_amount()).is_between(400, 1500)
	var light_noise: float = w.noise_mult()
	_force(w, "storm")
	assert_float(w.noise_mult()).is_less(light_noise)
	assert_float(Weather.wind_strength).is_greater(2.0)
	# The ground soaks slowly, and dries again even more slowly.
	var before: float = Weather.wetness
	for i in 100:
		w.step(0.1)
	assert_float(Weather.wetness).is_greater(before)
	var soaked: float = Weather.wetness
	_force(w, "clear")
	for i in 100:
		w.step(0.1)
	assert_float(Weather.wetness).is_less(soaked)
	assert_float(Weather.wetness).is_greater(0.0)
	assert_float(Weather.wind_strength).is_equal(1.0)


func test_lightning_emits_thunder_with_sound_delay() -> void:
	var w := _make()
	_force(w, "storm")
	var delays: Array[float] = []
	w.thunder.connect(func(d: float) -> void: delays.append(d))
	w.strike(1715.0)
	assert_int(delays.size()).is_equal(1)
	assert_float(delays[0]).is_equal_approx(5.0, 0.01)
	assert_bool(w.get_node("LightningFlash").visible).is_true()


func test_blend_is_gradual_and_signals_once() -> void:
	var w := _make()
	_force(w, "clear")
	var names: Array[String] = []
	w.weather_changed.connect(func(n: String) -> void: names.append(n))
	var fog0 := env.fog_density
	w.set_weather("storm", 10.0)
	for i in 50:     # halfway
		w.step(0.1)
	var mid := env.fog_density
	for i in 60:
		w.step(0.1)
	var full := env.fog_density
	assert_float(mid).is_greater(fog0)
	assert_float(mid).is_less(full)
	assert_array(names).is_equal(["storm"])
	w.set_weather("light_rain", 0.0)
	assert_str(w.current_name()).is_equal("rain")


func test_daily_schedule_is_deterministic_and_snow_is_gated() -> void:
	var a := _make()
	var b := _make()
	var seen := {}
	for d in range(1, 121):
		var s: String = a.weather_for_day(d)
		assert_str(b.weather_for_day(d)).is_equal(s)
		assert_str(s).is_not_equal("snow")
		assert_bool(Weather.PROFILES.has(s)).is_true()
		seen[s] = true
		for h: float in [3.0, 7.0, 12.0, 18.0]:
			assert_bool(Weather.PROFILES.has(a.scheduled_state(d, h))).is_true()
	assert_str(a.weather_for_day(1)).is_equal("clear")
	assert_int(seen.size()).is_greater_equal(4)
	# Forcing snow outside a snow region falls back to overcast; inside it snows.
	a.set_weather("snow", 0.0)
	assert_str(a.current_name()).is_equal("overcast")
	a.set_snow_region(true)
	_force(a, "snow")
	assert_str(a.current_name()).is_equal("snow")
	assert_bool(a.is_snowing()).is_true()
	assert_bool(a.is_raining()).is_false()
	var snow_days := 0
	for d in range(1, 121):
		var s: String = a.weather_for_day(d)
		assert_bool(s == "rain" or s == "storm").is_false()
		snow_days += 1 if s == "snow" else 0
	assert_int(snow_days).is_greater(0)
