extends GdUnitTestSuite
## Region 1: the Runeward Legion's recruiter at the Silverford (Ironmarch) Runecarvers' Guild. The Wardwright career used to be joinable only
## from the career screen; now a rostered resident enlists you through the talk menu (scripts/ui/wardwright_ui.gd, the Soldier captain pattern).

const Hub := preload("res://scripts/realm/realm_hub.gd")
const WardwrightUI := preload("res://scripts/ui/wardwright_ui.gd")
const TownData := preload("res://scripts/world/town_kit/town_data.gd")
const DialogueRunner := preload("res://scripts/sim/dialogue_runner.gd")

var _mods: Array = []


func after_test() -> void:
	WardwrightUI.trades_override = null
	WardwrightUI.age_override = -1
	_mods.clear()


func _trades() -> RefCounted:
	var hub: RefCounted = Hub.new()
	var m: RefCounted = hub.mod("trades")
	m.sync_life = false
	_mods.append(m)
	WardwrightUI.trades_override = m
	return m


func _recruiters() -> Array:
	var out: Array = []
	for tid: String in TownData.ids():
		for r: Dictionary in TownData.town(tid).get("residents", []):
			if String(r["role"]) == WardwrightUI.ROLE:
				out.append([tid, r])
	return out


func test_silverford_has_exactly_one_recruiter_at_the_guild_hall() -> void:
	var rec := _recruiters()
	assert_int(rec.size()).override_failure_message("recruiters: %s" % str(rec.map(func(x: Array) -> String: return String(x[1]["id"])))).is_equal(1)
	assert_str(rec[0][0]).is_equal("ironmarch")
	var r: Dictionary = rec[0][1]
	assert_str(String(r["work"])).is_equal("ironmarch_works")
	# the guild hall is the Silverford site (town data doors/sites)
	assert_bool((TownData.town("ironmarch")["lots"]["sites"] as Dictionary).has("ironmarch_works")).is_true()
	assert_bool(not (r["dialogue"]["greeting"] as Array).is_empty()).is_true()


func test_the_recruiters_dialogue_file_talks_about_the_legion() -> void:
	var rec: Dictionary = _recruiters()[0][1]
	var d := DialogueRunner.load_file("ironmarch/" + String(rec["id"]))
	assert_bool(DialogueRunner.node_exists(d, "legion")).is_true()
	var asks := false
	for c: Dictionary in DialogueRunner.choices(d, "greet", {"tier": "stranger"}):
		if String(c.get("goto", "")) == "legion":
			asks = true
	assert_bool(asks).override_failure_message("no 'tell me about the Legion' choice on the greeting").is_true()


func test_only_the_recruiter_offers_the_legion() -> void:
	_trades()
	var opts: Array = []
	WardwrightUI.add_options(opts, {"id": "x", "role": "blacksmith"})
	assert_array(opts).is_empty()
	WardwrightUI.add_options(opts, {"id": "y", "role": WardwrightUI.ROLE})
	assert_bool(opts.size() >= 1).is_true()


func test_a_child_is_turned_away_and_a_blessed_player_joins() -> void:
	var m := _trades()
	var opts: Array = []
	WardwrightUI.age_override = 9
	WardwrightUI.add_options(opts, {"id": "edlin", "role": WardwrightUI.ROLE})
	assert_str(String(opts[0][0])).contains("(refused)")
	assert_bool(opts[0][2]).is_false()
	assert_str(String(WardwrightUI._enlist(m))).contains("Blessing")
	assert_bool(m.call("is_member", "wardwright")).is_false()
	WardwrightUI.age_override = WardwrightUI.MIN_AGE
	opts.clear()
	WardwrightUI.add_options(opts, {"id": "edlin", "role": WardwrightUI.ROLE})
	assert_str(String(opts[0][0])).is_equal("Join the Runeward Legion")
	assert_bool(opts[0][2]).is_true()
	# the button's own callable: enrols the player on the first rung and quotes the terms
	var text: String = (opts[0][1] as Callable).call()
	assert_bool(m.call("is_member", "wardwright")).is_true()
	assert_str(text).contains("a week")
	# on the roll: the menu offers the terms only, and a second enlistment is refused
	opts.clear()
	WardwrightUI.add_options(opts, {"id": "edlin", "role": WardwrightUI.ROLE})
	assert_int(opts.size()).is_equal(1)
	assert_str(String(opts[0][0])).contains("terms")
	assert_str(WardwrightUI.enlist_refusal(m, 30)).contains("already")
	assert_str(String((opts[0][1] as Callable).call())).contains("on the roll")


func test_the_terms_come_from_the_wardwright_data() -> void:
	var t := WardwrightUI.terms_text()
	assert_str(t).contains("28g a week")
	assert_str(t).contains("126g")
