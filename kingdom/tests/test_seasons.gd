extends GdUnitTestSuite
## scripts/sim/seasons.gd: calendar mapping, blend, day length, festivals, save round trip.

const Seasons := preload("res://scripts/sim/seasons.gd")


func test_day_to_season_mapping() -> void:
	assert_str(Seasons.season_name_of(1)).is_equal("spring")
	assert_str(Seasons.season_name_of(28)).is_equal("spring")
	assert_str(Seasons.season_name_of(29)).is_equal("summer")
	assert_str(Seasons.season_name_of(56)).is_equal("summer")
	assert_str(Seasons.season_name_of(57)).is_equal("autumn")
	assert_str(Seasons.season_name_of(84)).is_equal("autumn")
	assert_str(Seasons.season_name_of(85)).is_equal("winter")
	assert_str(Seasons.season_name_of(112)).is_equal("winter")
	# Wraps into year 2.
	assert_str(Seasons.season_name_of(113)).is_equal("spring")
	assert_int(Seasons.year_of(1)).is_equal(1)
	assert_int(Seasons.year_of(112)).is_equal(1)
	assert_int(Seasons.year_of(113)).is_equal(2)
	assert_int(Seasons.year_of(224)).is_equal(2)


func test_day_of_season() -> void:
	assert_int(Seasons.day_of_season_of(1)).is_equal(1)
	assert_int(Seasons.day_of_season_of(28)).is_equal(28)
	assert_int(Seasons.day_of_season_of(29)).is_equal(1)
	assert_int(Seasons.day_of_season_of(113)).is_equal(1)


func test_first_day_of() -> void:
	assert_int(Seasons.first_day_of(Seasons.SPRING)).is_equal(1)
	assert_int(Seasons.first_day_of(Seasons.SUMMER)).is_equal(29)
	assert_int(Seasons.first_day_of(Seasons.AUTUMN)).is_equal(57)
	assert_int(Seasons.first_day_of(Seasons.WINTER)).is_equal(85)
	assert_int(Seasons.first_day_of(Seasons.SPRING, 2)).is_equal(113)


func test_blend_is_zero_until_the_last_days_then_rises_to_one() -> void:
	# Well before the last BLEND_DAYS of the season: no blend yet.
	assert_float(Seasons.blend_of(1, 12.0)).is_equal(0.0)
	assert_float(Seasons.blend_of(20, 12.0)).is_equal(0.0)
	# Rising through the last 3 days (blend starts exactly at day 26 = 28 - BLEND_DAYS + 1).
	assert_float(Seasons.blend_of(26, 12.0)).is_greater(0.0)
	assert_float(Seasons.blend_of(26, 12.0)).is_less(1.0)
	# Fully blended by the very end of the season (last hour of day 28).
	assert_float(Seasons.blend_of(28, 24.0)).is_equal_approx(1.0, 0.001)
	# Monotonic: later in the blend window is never less blended.
	assert_bool(Seasons.blend_of(27, 12.0) >= Seasons.blend_of(25, 12.0)).is_true()


func test_day_length_differs_per_season_and_blends_at_the_boundary() -> void:
	var spring_mid := Seasons.daylight_of(14, 12.0)
	var summer_mid := Seasons.daylight_of(29 + 14, 12.0)
	# Summer days are longer than spring days (later sunset, earlier sunrise).
	var spring_len := spring_mid.y - spring_mid.x
	var summer_len := summer_mid.y - summer_mid.x
	assert_float(summer_len).is_greater(spring_len)
	# At the very start of a season (no blend yet) daylight matches that season's own value.
	assert_vector(Seasons.daylight_of(1, 0.0)).is_equal(Seasons.DAYLIGHT[Seasons.SPRING])
	# Deep in the transition, daylight sits between the two seasons' values.
	var transition := Seasons.daylight_of(28, 24.0)
	assert_vector(transition).is_equal_approx(Seasons.DAYLIGHT[Seasons.SUMMER], Vector2(0.01, 0.01))


func test_festival_today_and_next_festival() -> void:
	var planting := Seasons.festival_on(7)
	assert_bool(planting.is_empty()).is_false()
	assert_str(String(planting["id"])).is_equal("planting")
	# A day with no festival.
	assert_bool(Seasons.festival_on(1).is_empty()).is_true()
	# next_festival_from finds the very next one, including across a season boundary.
	var nxt := Seasons.next_festival_from(1)
	assert_str(String(nxt["id"])).is_equal("planting")
	assert_int(int(nxt["in_days"])).is_equal(6)
	var after_harvest := Seasons.next_festival_from(Seasons.first_day_of(Seasons.AUTUMN) + 21)
	assert_str(String(after_harvest["id"])).is_equal("solstice")


func test_forage_in_season() -> void:
	assert_bool(Seasons.forage_in_season("berries", Seasons.first_day_of(Seasons.SUMMER))).is_true()
	assert_bool(Seasons.forage_in_season("berries", Seasons.first_day_of(Seasons.AUTUMN))).is_true()
	assert_bool(Seasons.forage_in_season("berries", Seasons.first_day_of(Seasons.WINTER))).is_false()
	assert_bool(Seasons.forage_in_season("mushroom", Seasons.first_day_of(Seasons.AUTUMN))).is_true()
	assert_bool(Seasons.forage_in_season("mushroom", Seasons.first_day_of(Seasons.SPRING))).is_false()
	# Unlisted kinds default to available in every season.
	assert_bool(Seasons.forage_in_season("firewood", Seasons.first_day_of(Seasons.WINTER))).is_true()


func test_crop_growth_and_field_look() -> void:
	assert_float(Seasons.crop_growth_of(Seasons.first_day_of(Seasons.WINTER))).is_equal(0.0)
	assert_float(Seasons.crop_growth_of(Seasons.first_day_of(Seasons.SUMMER))).is_greater(0.0)
	assert_str(Seasons.field_look_of(Seasons.first_day_of(Seasons.SPRING))).is_equal("sprouting")
	assert_str(Seasons.field_look_of(Seasons.first_day_of(Seasons.WINTER))).is_equal("fallow")


func test_visuals_are_neutral_in_summer_and_change_in_other_seasons() -> void:
	var summer := Seasons.visuals_of(Seasons.first_day_of(Seasons.SUMMER) + 10, 12.0)
	assert_vector(summer["tint"] as Vector3).is_equal_approx(Vector3.ONE, Vector3.ONE * 0.001)
	assert_float(summer["autumn"]).is_equal(0.0)
	assert_float(summer["winter"]).is_equal(0.0)
	assert_float(summer["snow"]).is_equal(0.0)
	var winter := Seasons.visuals_of(Seasons.first_day_of(Seasons.WINTER) + 10, 12.0)
	assert_float(winter["winter"]).is_greater(0.0)
	assert_float(winter["snow"]).is_greater(0.0)
	var autumn := Seasons.visuals_of(Seasons.first_day_of(Seasons.AUTUMN) + 10, 12.0)
	assert_float(autumn["autumn"]).is_greater(0.0)


func test_serialize_round_trip() -> void:
	var s := Seasons.new()
	s.day_offset = 41
	var d: Dictionary = s.serialize()
	assert_int(int(d["offset"])).is_equal(41)
	var s2 := Seasons.new()
	s2.deserialize(d)
	assert_int(s2.day_offset).is_equal(41)
	s.free()
	s2.free()


func test_global_shader_params_are_registered() -> void:
	# Registering is idempotent and safe to call again. global_shader_parameter_get()
	# always reads back null under the headless dummy renderer (no GPU backend to
	# hold the value), so presence is checked with global_shader_parameter_get_type,
	# which reports the declared type instead (GLOBAL_VAR_TYPE_MAX means unknown).
	Seasons.ensure_globals()
	Seasons.ensure_globals()
	var max_type := RenderingServer.GLOBAL_VAR_TYPE_MAX
	assert_bool(RenderingServer.global_shader_parameter_get_type(Seasons.G_AUTUMN) != max_type).is_true()
	assert_bool(RenderingServer.global_shader_parameter_get_type(Seasons.G_SNOW) != max_type).is_true()
	assert_bool(RenderingServer.global_shader_parameter_get_type(Seasons.G_BLOOM) != max_type).is_true()
	assert_bool(RenderingServer.global_shader_parameter_get_type(Seasons.G_TINT) != max_type).is_true()
	# A fresh instance's defaults, before any live visuals are pushed, are neutral.
	var v := Seasons._season_look(Seasons.SUMMER, 0.0)
	assert_vector(v["tint"] as Vector3).is_equal(Vector3.ONE)
	assert_float(v["autumn"]).is_equal(0.0)
	assert_float(v["winter"]).is_equal(0.0)
	assert_float(v["snow"]).is_equal(0.0)
	assert_float(v["bloom"]).is_equal(0.0)
