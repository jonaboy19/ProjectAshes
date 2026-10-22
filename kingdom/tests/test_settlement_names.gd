extends GdUnitTestSuite
## One canonical player-facing name per settlement (Region 1 canon, docs/regions/WORLD_R1.md: Ironmarch is shown as Silverford,
## Oakvale as Greenhollow; the WorldGen name stays the id for saves, door ids, town-kit files and `settlement:<name>` place ids).
## Bug: the HUD location line printed the WorldGen name while the discovery banner and the map printed the poster name.

const Identity := preload("res://scripts/world/region1_identity.gd")
const HudScript := preload("res://scripts/ui/hud.gd")
const TOWNS := "res://data/region1/towns/"
const QUESTS := "res://data/quests/"
const DIALOGUE := "res://dialogue/"


func before() -> void:
	WorldGen.setup(1066)


func _aliases() -> Dictionary:
	var out := {}
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/region1/world/settlements.json"))
	for st: Dictionary in d["settlements"]:
		if String(st.get("alias", "")) != "":
			out[String(st["name"])] = String(st["alias"])
	return out


func test_every_settlement_has_one_name_across_hud_banner_map_and_discovery() -> void:
	var disc = preload("res://scripts/sim/discovery.gd").new()
	disc.build_from_world([])
	assert_int(WorldGen.settlements.size()).is_greater(10)
	for s: Dictionary in WorldGen.settlements:
		var raw := String(s["name"])
		var canon := WorldGen.display_name(raw)
		assert_str(Identity.display_name(raw)).override_failure_message("identity " + raw).is_equal(canon)
		assert_str(disc.display_name(raw)).override_failure_message("discovery " + raw).is_equal(canon)
		assert_str(HudScript.town_label(s)).override_failure_message("HUD location " + raw).is_equal(canon)
		var pl: Dictionary = disc.place("settlement:%s" % raw)
		assert_dict(pl).override_failure_message("no discovery place for " + raw).is_not_empty()
		assert_str(String(pl["name"])).override_failure_message("banner / map name of " + raw).is_equal(canon)


func test_the_two_renamed_towns_use_the_canon_names() -> void:
	assert_str(WorldGen.display_name("Ironmarch")).is_equal("Silverford")
	assert_str(WorldGen.display_name("Oakvale")).is_equal("Greenhollow")
	assert_str(WorldGen.display_name("Ashford")).is_equal("Ashford")
	assert_str(WorldGen.display_name("Nowhere")).is_equal("Nowhere")
	var a := _aliases()
	assert_int(a.size()).is_equal(2)
	# The poster places in first_region.json carry the same names and point at the same town.
	var fr: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/world/first_region.json"))
	var found := {}
	for pl: Dictionary in fr.get("places", []):
		found[String(pl.get("name", ""))] = true
	for raw: String in a:
		assert_bool(found.has(a[raw])).override_failure_message("first_region.json lacks poster place " + a[raw]).is_true()


func test_aliases_never_collide_with_another_settlement_name() -> void:
	var raw_names := {}
	for s: Dictionary in WorldGen.settlements:
		raw_names[String(s["name"])] = true
	var seen := {}
	var a := _aliases()
	for raw: String in a:
		assert_bool(raw_names.has(raw)).is_true()
		assert_bool(raw_names.has(a[raw])).override_failure_message("alias %s is also a WorldGen name" % a[raw]).is_false()
		assert_bool(seen.has(a[raw])).is_false()
		seen[a[raw]] = true


func _strip_ids(text: String, raw: String) -> String:
	# the WorldGen name is allowed as an id: "settlement": "X", "town": "X", `_doc`, file / quest ids and paths
	var t := text
	for pat: String in ['"settlement": "%s"' % raw, '"town": "%s"' % raw, 'for %s. Edit freely' % raw, '"place": "%s"' % raw.to_lower()]:
		t = t.replace(pat, "")
	return t


func test_town_kit_text_prints_the_canon_name_not_the_worldgen_name() -> void:
	var a := _aliases()
	for raw: String in a:
		var tid := raw.to_lower()
		var paths: Array[String] = [TOWNS + tid + ".json"]
		for dir: String in [QUESTS + tid + "/", DIALOGUE + tid + "/"]:
			for f in DirAccess.get_files_at(dir):
				if f.ends_with(".json"):
					paths.append(dir + f)
		assert_int(paths.size()).is_greater(5)
		var greets := 0
		for p in paths:
			var text := _strip_ids(FileAccess.get_file_as_string(p), raw)
			assert_bool(text.contains(raw)).override_failure_message("%s still prints the WorldGen name %s" % [p, raw]).is_false()
			if text.contains(a[raw]):
				greets += 1
		assert_int(greets).override_failure_message("no town-kit file of %s mentions %s" % [raw, a[raw]]).is_greater(3)


func test_data_text_does_not_use_the_old_names() -> void:
	var fr := FileAccess.get_file_as_string("res://data/world/first_region.json")
	for raw: String in _aliases():
		# "(WorldGen's Ironmarch)" in a poster place's description and its `alias_of` id link are the documented mentions
		fr = fr.replace("WorldGen's %s" % raw, "").replace('"alias_of": "%s"' % raw, "")      # the id link back to the WorldGen town
	for raw: String in _aliases():
		assert_bool(fr.contains(raw)).override_failure_message("first_region.json prints " + raw).is_false()
