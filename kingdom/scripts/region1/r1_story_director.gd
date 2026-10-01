extends Node
## Package C7: the story quest runtime in the running game ("The Stones Are Dimming", Acts I-V).
##
## Region1StoryQuest (scripts/region1/story_quest.gd) is the pure data machine; this node is its body:
##   * builds the context the quest reads (age, flags, items, text tokens) and refreshes it once a second;
##   * feeds it the world's events: area entries (registry places, resolved by region1_places.gd),
##     kills, carves, relights, festivals, ember choices, Ashsight, Scar actions, cutscene stand-ins;
##   * puts the quest's givers in the world as talkable characters (r1_quest_npc.gd, a Station), spawned by
##     distance and freed again, and runs their conversations through the game's dialogue screen;
##   * applies the actions the quest hands back (give, rep, gold, marker, spawn, tutorial, cutscene);
##   * shows it: the HUD tracker rows (a text lead plus a compass hint, NEVER a glowing world marker),
##     Quests tab entry, Journal page and toasts.
##
## Freedom first: nothing is locked behind a step. The quest only ever starts things; every other
## system works the same with the story ignored, the tracker can be hidden, and steps that name a big
## creature also offer a non-combat route (`parley`, below).
##
## Cutscenes: only the opening ones are wanted. The quest's `cutscene` actions become short in-world
## staging (banner, music cue, a small camera nudge) that completes itself; the Blessing runs the
## game's own age-12 ceremony popup (skippable).

const Places := preload("res://scripts/region1/region1_places.gd")
const NPC := preload("res://scripts/region1/r1_quest_npc.gd")
const DialogueRunner := preload("res://scripts/sim/dialogue_runner.gd")
const QUEST_PATH := "res://data/region1/quests/r1_main.json"
const CAST_PATH := "res://data/region1/quests/cast.json"
const SS := preload("res://scripts/ui/frontend/settings_store.gd")
const STATE_KEY := &"story_director"

signal step_started(step_id: String)
signal step_completed(step_id: String)
signal quest_completed
signal staging_cue(cue: String, step_id: String)   ## C12 switches the music bed
signal changed

const SPAWN_DIST := 140.0
const FREE_DIST := 240.0
const TICK := 1.0
const HIDE_TRACKER_KEY := "tracker_hidden"

## cast id -> Assets look.
const LOOKS := {
	"mother": "Mother", "father": "Father", "maren_coldbrook": "Elder_Woman", "bram_hollis": "Guard", "idra_vell": "Herbalist",
	"odrin_thale": "Noble", "rowan_ashby": "Knight", "lucan": "Monk", "harrok_ashmaw": "Orc_Warchief", "snikkit": "Rogue",
	"imra_solvane": "Trader", "tamsin_reeve": "Guard", "wren_coldbrook": "Child_Girl", "corin_vesk": "Rogue_Hooded",
	"gilda_pennick": "Innkeeper", "king_aldric": "Noble",
}
## Short in-world staging that replaces the full cutscenes: [title, subtitle, banner kind].
const STAGING := {
	"elder_relight": ["An Elder Stone wakes", "Blue light races out along the ward-lines.", "location"],
	"rowan_ember": ["Rowan's ember", "It rises slowly, the colour of the keep's first fire.", "quest"],
	"finale_seal": ["The Rift closes", "For now. Beyond the light, two other colours wait.", "quest"],
	"region_complete": ["Region 1 complete", "The lanterns of Ashford, a year on. The stones are lit.", "quest"],
	"herd_crossing": ["Dawn on the Greenhollow road", "The Stagborn herd walks the old ward-line. Thistle lifts her head.", "location"],
	"maren_last_stand": ["Maren holds the ring", "Her ember sinks into the heart-stone and the circle turns gold.", "quest"],
}
const STAGING_SECONDS := 3.2
## Spawns tied to an objective of a step: dropped when the step finishes without them (Act I's wolf and fawn come on completion).
const FIGHT_SPAWNS := ["rift_wolf", "scarbound_troll", "ashen_hand_saboteur"]
## The living world hears what the player does: step id -> [home settlement, news kind, text, magnitude, official, deed or ""].
## Posted once, when the step completes, through the realm news module (rumours travel the roads at road speed) and
## the player's fame ledger (deeds become a nickname in time). Nothing here changes the story; it only makes the Vale talk.
const ECHOES := {
	"a2_greenhollow": ["Oakvale", "crisis", "The Pennick barn at Greenhollow burned. The Captain's patrol had checked its stone a week before.", 1.0, false, ""],
	"a2_duskbriar": ["Ashford", "crisis_resolved", "Raiders of the Ashen Hand were driven off their camp by Ashford's young stone-carver.", 1.0, false, "bandits_broken"],
	"a3_council": ["Kingsreach", "petition", "The Council of Wardens heard the Dawn relics argued, and a child of Ashford was asked to speak.", 1.2, true, ""],
	"a3_scar_front": ["Oakvale", "crisis", "The Scar has reached the south fields of Greenhollow.", 1.5, false, "defended"],
	"a3_ring_falls": ["Ashford", "crisis_failed", "Maren Coldbrook held Ashford's heart-stone alight by hand until it took her. The ring burns gold.", 2.0, false, "defended"],
	"a3_the_ledger": ["Kingsreach", "crisis_resolved", "Captain Bram Hollis of the Guard is named for selling the Vale's failing stones.", 1.8, true, ""],
	"a4_glade_trial": ["Oakvale", "migration", "The Stagborn herd walks the Glade again, and the Elder Stone there is lit.", 1.0, false, "discovery"],
	"a4_highwatch": ["Highcliff", "succession", "Sir Rowan Ashby of Highwatch is dead at his gate, and his ember is placed.", 1.5, true, ""],
	"a4_five_hearts": ["Kingsreach", "crisis_resolved", "All five Elder Stones of the Vale burn again.", 2.0, true, "defended"],
	"a5_scarbound": ["Kingsreach", "apex_slain", "The Scarbound Troll fell at the Scar Mouth.", 2.0, false, "beast_slain"],
	"a5_seal": ["Kingsreach", "crisis_resolved", "The Scar Mouth is sealed. Travellers speak of a light that did not come from the sun.", 3.0, true, "rift_sealed"],
	"a5_homecoming": ["Ashford", "founded", "Ashford lights its lanterns a year on, and the heart-stone hums.", 1.0, false, ""],
}
## Creature species the game reports -> the story's big-creature target (defeat objectives).
const BOSS_ALIAS := {"stagborn_warden": "antlered_warden", "scarbound_troll": "scarbound_troll"}

var story: Region1StoryQuest
var hud: Node
var player: Node3D
var world: Node3D
var glue: Node
var cast: Dictionary = {}
var tracker_hidden := false
var enabled := true

var _timer: Timer
var _npcs: Dictionary = {}           ## "<npc>@<place>" -> r1_quest_npc
var _inside: Dictionary = {}         ## place id -> true while the player is in it
var _talked: Dictionary = {}         ## dialogue node -> true (first unseen node is offered first)
var _conv: Dictionary = {}           ## the open conversation
var _pending_spawns: Array = []      ## [{target, place, n}] waiting for the player to come near
var _marked: String = ""             ## place id of the latest "marker" action (compass hint)
var _staging: Dictionary = {}        ## cutscene id -> seconds left
var _toast_log: Array[String] = []
var _rng := RandomNumberGenerator.new()
var _item_ids: PackedStringArray = PackedStringArray()
var _last_sig := ""
var _wolf: Node
var _boss: Node
## Tests: Callable(target, at, n, place) replaces the real spawns (no models needed).
var spawn_override: Callable = Callable()
var _ancestor_name := ""
var _stone_name := "the stone"


func setup(p_glue: Node, p_hud: Node, p_player: Node3D, p_world: Node3D) -> Region1StoryQuest:
	glue = p_glue
	hud = p_hud
	player = p_player
	world = p_world
	_rng.seed = hash([WorldSim.SEED, "r1_story"])
	story = Region1StoryQuest.new()
	story.setup(WorldSim.SEED)
	story.load_quest(QUEST_PATH)
	Region1State.register_sim(story)   # saves under "story_quest"
	var c: Variant = Region1StoryQuest._read_json(CAST_PATH)
	cast = (c as Dictionary).get("speakers", {}) if c is Dictionary else {}
	for s: Dictionary in story.steps:
		for o: Dictionary in s.get("objectives", []):
			if String(o.get("type", "")) == "item":
				_item_ids.append(String(o["item"]))
	Region1State.register(STATE_KEY, _snapshot, _restore, 1)
	# Hooks into the HUD and the game menu.
	if hud != null:
		hud.set("story_tracker", Callable(self, "tracked_quest"))
		hud.set("story_target", Callable(self, "compass_target"))
	var MD := preload("res://scripts/ui/gamemenu/menu_data.gd")
	MD.extra_quests.append(Callable(self, "quest_entries"))
	MD.extra_journal.append(Callable(self, "journal_page"))
	if Life.has_signal("region1_kill"):
		Life.region1_kill.connect(_on_kill)
	_timer = Timer.new()
	_timer.wait_time = TICK
	_timer.timeout.connect(_on_tick)
	add_child(_timer)
	_timer.start()
	return story


func _exit_tree() -> void:
	var MD := preload("res://scripts/ui/gamemenu/menu_data.gd")
	MD.extra_quests.erase(Callable(self, "quest_entries"))
	MD.extra_journal.erase(Callable(self, "journal_page"))
	if Region1State.has(STATE_KEY):
		Region1State.unregister(STATE_KEY)


# --- save ------------------------------------------------------------------------------

func _snapshot() -> Dictionary:
	return {"talked": _talked.keys(), "hidden": tracker_hidden, "marked": _marked, "pending": _pending_spawns.duplicate(true),
		"ancestor": _ancestor_name, "stone": _stone_name}


func _restore(d: Dictionary) -> void:
	_talked = {}
	for n: Variant in d.get("talked", []):
		_talked[String(n)] = true
	tracker_hidden = bool(d.get("hidden", false))
	_marked = String(d.get("marked", ""))
	_pending_spawns = []
	for p: Variant in d.get("pending", []):
		if p is Dictionary:
			_pending_spawns.append({"target": String(p.get("target", "")), "place": String(p.get("place", "")), "n": int(p.get("n", 1)), "step": String(p.get("step", ""))})
	_ancestor_name = String(d.get("ancestor", ""))
	_stone_name = String(d.get("stone", "the stone"))
	_inside.clear()
	_clear_npcs()
	_conv = {}
	call_deferred("_after_restore")


func _after_restore() -> void:
	if story != null and is_inside_tree():
		_handle(story.refresh(ctx()))


# --- context ---------------------------------------------------------------------------

func ctx() -> Dictionary:
	var lp = Life.life_path
	var flags := {}
	for f: Variant in lp.flags:
		var v: Variant = lp.flags[f]
		if v != null and v != false:
			flags[String(f)] = true
	var items := {}
	for id in _item_ids:
		var n: int = Life.count(id)
		if n > 0:
			items[id] = n
	var mother := String(lp.parent("mother").get("name", "Mother")) if lp.has_method("parent") else "Mother"
	var father := String(lp.parent("father").get("name", "Father")) if lp.has_method("parent") else "Father"
	var weather := "clear"
	var wn := get_tree().get_first_node_in_group("weather") if is_inside_tree() else null
	if wn != null and wn.get("_state") != null:
		weather = String(wn.get("_state"))
	var age: int = Life.age()
	return {"age": age, "flags": flags, "items": items,
		"vars": {"family": lp.family_name, "player": lp.given_name, "mother": mother, "father": father,
			"ancestor": _ancestor_name if _ancestor_name != "" else "your ancestor", "stone_name": _stone_name},
		"player": lp.given_name, "time": DialogueRunner.time_bucket(WorldSim.time_of_day), "weather": weather,
		"child": age < 13, "mother": mother, "father": father}


# --- the 1 Hz tick ---------------------------------------------------------------------

func _on_tick() -> void:
	if not enabled or story == null or not is_instance_valid(player):
		return
	_handle(story.refresh(ctx()))
	_area_events()
	_manage_npcs()
	_process_pending_spawns()
	_tick_staging()
	var sig := _signature()
	if sig != _last_sig:
		_last_sig = sig
		changed.emit()


func _signature() -> String:
	return "%s|%s|%s" % [story.active_steps(), _marked, tracker_hidden]


func _pp() -> Vector2:
	return Vector2(player.global_position.x, player.global_position.z)


func _area_events() -> void:
	var pp := _pp()
	var reg: Dictionary = Places.registry().get("places", {})
	for id: String in reg:
		var r := Places.resolve(id)
		if r.is_empty():
			continue
		var inside: bool = pp.distance_to(r["pos"]) <= float(r["radius"])
		if inside and not _inside.has(id):
			_inside[id] = true
			_handle(story.notify(&"enter_area", {"place": id}, ctx()))
		elif not inside and _inside.has(id) and pp.distance_to(r["pos"]) > float(r["radius"]) * 1.25:
			_inside.erase(id)
	# An objective that asks to enter a place the player is already standing in counts at once (no need to step out and back).
	for sid: String in story.active_steps():
		var o := story.current_objective(sid)
		if String(o.get("type", "")) == "enter_area":
			var r2 := Places.resolve(String(o.get("place", "")))
			if not r2.is_empty() and pp.distance_to(r2["pos"]) <= float(r2["radius"]):
				_handle(story.notify(&"enter_area", {"place": String(o["place"])}, ctx()))


# --- public event entry points (the glue calls these) ----------------------------------

func notify(type: StringName, params: Dictionary = {}) -> void:
	if story == null:
		return
	_handle(story.notify(type, params, ctx()))


func set_flag(f: String) -> void:
	if story != null:
		_handle(story.set_flag(f, ctx()))


func note_ancestor(name: String, stone_name: String) -> void:
	_ancestor_name = name
	_stone_name = stone_name


func _on_kill(species: String, where: Vector3) -> void:
	if story == null:
		return
	var p := Vector2(where.x, where.z)
	# One kill notification per registry place around the kill (a generous radius), plus a place-less one.
	var places: Array[String] = [""]
	var reg: Dictionary = Places.registry().get("places", {})
	for id: String in reg:
		var r := Places.resolve(id)
		if not r.is_empty() and p.distance_to(r["pos"]) <= float(r["radius"]) * 2.0 + 20.0:
			places.append(id)
	for pl in places:
		_handle(story.notify(&"kill", {"target": species, "place": pl, "amount": 1}, ctx()))
	# The great creatures count as beaten when they fall, the same as the parley route (never a hard gate).
	var boss: String = String(BOSS_ALIAS.get(species, ""))
	if boss != "":
		_handle(story.notify(&"defeat", {"target": boss}, ctx()))
	if species == "wolf" and _wolf != null and is_instance_valid(_wolf):
		_wolf = null


# --- events from the quest -------------------------------------------------------------

func _handle(events: Array) -> void:
	for e: Dictionary in events:
		match String(e["type"]):
			"step_started":
				var id := String(e["step"])
				var s := story.step(id)
				_toast("quest", "New: %s" % String(s.get("title", id)), String(s.get("objective", "")))
				_stage_step(id)
				step_started.emit(id)
			"step_completed":
				var cid := String(e["step"])
				_toast("quest", "Done: %s" % String(story.step(cid).get("title", cid)), "")
				Life.award_progress("quest", {"id": "r1_" + cid})
				_echo(cid)
				step_completed.emit(cid)
			"objective_done":
				pass
			"action":
				_apply_action(e["action"] as Array, String(e["step"]))
			"quest_completed":
				_toast("quest", "Region 1 complete", "The stones of the Ashford Vale are lit.")
				quest_completed.emit()
	if not events.is_empty():
		changed.emit()


func _toast(kind: String, title: String, sub: String) -> void:
	_toast_log.append(title)
	if hud != null and hud.has_method("notify"):
		hud.notify(kind, title, sub)


## Step staging: the music bed (C12) and a one-line text lead. C9 cutscene needs are covered by `_do_cutscene`.
func _stage_step(id: String) -> void:
	var st: Dictionary = story.step(id).get("staging", {})
	var cue := String(st.get("music", ""))
	var sil: Variant = st.get("silence", false)
	if (sil is bool and sil or (sil is String and sil != "") or (sil is float and sil != 0.0)) and cue == "":
		cue = "silence"
	if cue != "":
		staging_cue.emit(cue, id)


func _apply_action(a: Array, step_id: String) -> void:
	match String(a[0]):
		"give":
			Life.give(String(a[1]), int(a[2]) if a.size() > 2 else 1)
			_toast("item", "Received", "%s x%d" % [Life.item_name(String(a[1])), int(a[2]) if a.size() > 2 else 1])
		"rep":
			if Life.relationships != null:
				Life.relationships.change_rep(String(a[1]), float(a[2]))
		"gold":
			Game.add_gold(int(a[1]))
			_toast("item", "Paid", "%d gold" % int(a[1]))
		"marker":
			_marked = String(a[1])
		"spawn":
			_pending_spawns.append({"target": String(a[1]), "place": String(a[2]) if a.size() > 2 else "", "n": int(a[3]) if a.size() > 3 else 1, "step": step_id})
		"tutorial":
			if glue != null and glue.get("tutorial") != null:
				var t: Variant = glue.get("tutorial")
				if t.director != null:
					t.director.replay(StringName(String(a[1])))
		"cutscene":
			_do_cutscene(String(a[1]))
		"record":
			if Life.tendencies != null:
				Life.record(String(a[1]), float(a[2]) if a.size() > 2 else 1.0)
		"opinion", "bond", "gift", "chores", "quests", "turn_in", "tell_hint":
			pass
		"close":
			_end_conv()


func _echo(step_id: String) -> void:
	if not ECHOES.has(step_id) or Life.realm == null:
		return
	var e: Array = ECHOES[step_id]
	var sid := 0
	for st: Dictionary in WorldGen.settlements:
		if String(st["name"]) == String(e[0]):
			sid = int(st["id"])
			break
	var news: Variant = Life.realm.mod("news")
	if news != null and news.has_method("post"):
		news.call("post", String(e[1]), sid, String(e[2]), float(e[3]), "", bool(e[4]))
		if String(e[5]) != "" and news.has_method("record_deed"):
			news.call("record_deed", "player", Life.life_path.given_name, String(e[5]), sid, float(e[3]))


# --- cutscene stand-ins -----------------------------------------------------------------

func _do_cutscene(id: String) -> void:
	if id == "blessing":
		# The game's own age-12 Blessing (popup + magic circle); done when it has happened.
		_staging[id] = 0.0
		return
	var info: Array = STAGING.get(id, ["", "", "quest"])
	if hud != null and hud.has_method("show_event") and String(info[0]) != "":
		hud.show_event(String(info[2]), String(info[0]), String(info[1]), "")
	_camera_nudge()
	_staging[id] = STAGING_SECONDS


## A short in-world beat without a story hook (banner, nudge): the relight of an Elder Stone and the like.
func show_staging(id: String) -> void:
	var info: Array = STAGING.get(id, ["", "", "quest"])
	if hud != null and hud.has_method("show_event") and String(info[0]) != "":
		hud.show_event(String(info[2]), String(info[0]), String(info[1]), "")
	_camera_nudge()


func _tick_staging() -> void:
	for id: String in _staging.keys():
		if id == "blessing":
			if Life.awakening.has_happened():
				_staging.erase(id)
				_handle(story.notify(&"cutscene_done", {"cutscene": id}, ctx()))
			elif Life.age() >= 12 and WorldSim.time_of_day >= 7.0 and not get_tree().paused:
				Life.call("_run_awakening")   # the ceremony runs at 7:00 on the 12th birthday; later it runs as soon as the quest asks
			continue
		_staging[id] = float(_staging[id]) - TICK
		if float(_staging[id]) <= 0.0:
			_staging.erase(id)
			_handle(story.notify(&"cutscene_done", {"cutscene": id}, ctx()))


func _camera_nudge() -> void:
	var cam: Variant = player.get("camera") if is_instance_valid(player) else null
	if cam is Camera3D and is_instance_valid(cam):
		var c := cam as Camera3D
		var base := c.fov
		var tw := create_tween()
		tw.tween_property(c, "fov", base - 6.0, 0.9).set_trans(Tween.TRANS_SINE)
		tw.tween_property(c, "fov", base, 1.4).set_trans(Tween.TRANS_SINE)


# --- spawns ------------------------------------------------------------------------------

func _process_pending_spawns() -> void:
	if _pending_spawns.is_empty():
		return
	var pp := _pp()
	for sp: Dictionary in _pending_spawns.duplicate():
		if String(sp["target"]) in FIGHT_SPAWNS and String(sp.get("step", "")) != "" and story.is_done(String(sp["step"])):
			_pending_spawns.erase(sp)   # the step moved on without the creature: it never shows up late
			continue
		var r := Places.resolve(String(sp["place"]))
		if r.is_empty() or pp.distance_to(r["pos"]) > 110.0:
			continue          # the creature waits for the player to come by: nothing is forced on a far traveller
		_pending_spawns.erase(sp)
		_spawn(String(sp["target"]), r["pos"], int(sp["n"]), String(sp["place"]))


func _spawn(target: String, at: Vector2, n: int, place: String) -> void:
	if spawn_override.is_valid():
		spawn_override.call(target, at, n, place)   # tests and the headless autoplay
		return
	match target:
		"wolf":
			_spawn_wolf(at)
		"stagborn_fawn":
			var cr := Critter.new()
			cr.kind = "deer"
			cr.home = at
			cr.huntable = false
			cr.add_to_group("r1_fawn")
			world.add_child(cr)
			var q := at + Vector2(-4, 3)
			cr.global_position = Vector3(q.x, WorldGen.height(q.x, q.y), q.y)
			cr.scale = Vector3.ONE * 0.55
		"rift_wolf":
			_spawn_rift_wolves(at, n)
		"ashen_hand_saboteur":
			var cr2: Node = get_tree().get_first_node_in_group("r1_creatures") if is_inside_tree() else null
			if cr2 != null and cr2.has_method("wake_camp"):
				cr2.call("wake_camp", at)   # the camp's own Ashen Hand roster fills again; its deaths are the quest's kills
		"scarbound_troll":
			_spawn_troll(at)
		_:
			push_warning("Region1: no spawn for %s yet" % target)


## The safe first fight: one lone wolf at the ring's edge that can knock the player down but never kill
## (it cannot take the last point of health while `r1_safe` is set). Dies like any wolf.
func _spawn_wolf(ring: Vector2) -> void:
	var w := Wolf.new()
	w.species = "wolf"
	w.home = ring
	w.territory = 60.0
	w.set_meta("r1_safe", true)
	world.add_child(w)
	var away := (ring - _pp()).normalized() if (ring - _pp()).length() > 1.0 else Vector2(0, -1)
	var q := ring + away * 32.0
	w.global_position = Vector3(q.x, WorldGen.height(q.x, q.y), q.y)
	w.died.connect(func(dead: Wolf) -> void: Life.on_wolf_killed(dead.global_position, -1))
	_wolf = w
	_toast("quest", "Something at the ring's edge", "A lone wolf. Keep your guard up.")


## Rift wolves out of the dark at the ring (Act III) and the Highwatch gate (Act IV): violet-furred, in a loose circle.
func _spawn_rift_wolves(at: Vector2, n: int) -> void:
	for i in n:
		var w := Wolf.new()
		w.species = "wolf"
		w.home = at
		w.territory = 70.0
		w.scale = Vector3.ONE * 1.2
		w.set_meta("rift", true)
		world.add_child(w)
		var q := at + Vector2(30.0, 0.0).rotated(TAU * float(i) / float(maxi(n, 1)) + 0.4)
		w.global_position = Vector3(q.x, WorldGen.height(q.x, q.y), q.y)
		RiftVariants.apply_creature(w, "wolf")
		w.died.connect(func(dead: Wolf) -> void: Life.on_wolf_killed(dead.global_position, -1, "rift_wolf"))
	_toast("quest", "Rift wolves", "They came out of the dark between the stones.")


## The Scarbound Troll at the Scar Mouth (Act V): an optional big creature (the quest also offers a parley).
func _spawn_troll(at: Vector2) -> void:
	if is_instance_valid(_boss):
		return
	var t := CampMonster.new()
	t.species = "troll"
	t.home = at
	t.home_radius = 28.0
	t.named = "Scarbound Troll"
	world.add_child(t)
	if t.is_queued_for_deletion():
		return   # model not available
	t.scale = Vector3.ONE * 1.25
	var q := at + Vector2(12.0, -6.0)
	t.global_position = Vector3(q.x, WorldGen.height(q.x, q.y), q.y)
	t.died.connect(func(_m: CampMonster) -> void:
		_handle(story.notify(&"defeat", {"target": "scarbound_troll"}, ctx())))
	_boss = t
	_toast("quest", "It was a troll, once", "The ground at the Scar Mouth shakes.")


# --- characters in the world -------------------------------------------------------------

func _step_place_pos(step: Dictionary, giver: String) -> Variant:
	var pid := String(step.get("place", ""))
	if giver in ["mother", "father"] and pid in ["ashford", "ashford_ring"]:
		var hp: Vector2 = Life.life_path.home_pos
		return hp + Vector2(0, 5.5) + Vector2(2.5 if giver == "father" else -2.5, 0)
	var r := Places.resolve(pid)
	return r["pos"] if not r.is_empty() else null


## Who offers a dialogue entry: the speaker of its first node when that is a character who can stand there
## (the fawn, the mother...), else the step's giver. Narration and runestone voices belong to the giver.
func _entry_host(step: Dictionary, entry: Dictionary) -> String:
	var sp := String(entry.get("speaker", ""))
	if sp != "" and sp != "narrator" and sp != "ancestor_stone" and (LOOKS.has(sp) or sp == "thistle"):
		return sp
	return String(step.get("giver", ""))


func _manage_npcs() -> void:
	var pp := _pp()
	var wanted: Dictionary = {}
	var idx := 0
	for id: String in story.active_steps():
		var s := story.step(id)
		for e: Dictionary in story.dialogue_entries(id):
			var host := _entry_host(s, e)
			if host == "":
				continue
			var at: Variant = _step_place_pos(s, host)
			if at == null:
				continue
			var key := "%s@%s" % [host, String(s.get("place", ""))]
			if wanted.has(key):
				continue
			wanted[key] = true
			var apos: Vector2 = at
			# Stand beside the place centre, fanned out so characters do not overlap.
			apos += Vector2(3.2, 0.0).rotated(1.3 * float(idx) + 0.6) if not (host in ["mother", "father"]) else Vector2.ZERO
			idx += 1
			var dist := pp.distance_to(apos)
			if _npcs.has(key):
				if dist > FREE_DIST:
					_free_npc(key)
			elif dist < SPAWN_DIST:
				_spawn_npc(key, host, apos, pp)
	for key: String in _npcs.keys():
		if not wanted.has(key):
			_free_npc(key)


func _spawn_npc(key: String, giver: String, at: Vector2, face_to: Vector2) -> void:
	var display := _display_name(giver)
	var npc := NPC.new().setup(giver, display, String(LOOKS.get(giver, "critter:deer" if giver == "thistle" else "Rogue_Hooded")), Callable(self, "npc_menu"))
	npc.spawned_for = key
	_hide_world_twin(_display_name(giver), at, true)
	world.add_child(npc)
	(npc as Node3D).call("place", at, face_to)
	_npcs[key] = npc


func _free_npc(key: String) -> void:
	var n: Variant = _npcs.get(key)
	if is_instance_valid(n):
		_hide_world_twin(_display_name(String(key).get_slice("@", 0)), Vector2((n as Node3D).global_position.x, (n as Node3D).global_position.z), false)
	if is_instance_valid(n):
		(n as Node).queue_free()
	_npcs.erase(key)


## The world may already stand a named person where the quest wants them (Sir Rowan at Highwatch Keep): only one is ever there.
## The world's Station is hidden and switched off while the quest's character is out, and comes back when it is freed.
func _hide_world_twin(display: String, at: Vector2, hide: bool) -> void:
	if not is_inside_tree():
		return
	for st: Node in get_tree().get_nodes_in_group("r1_world_npc"):
		if String(st.get_meta("npc_name", "")) != display or not (st is Node3D):
			continue
		var q := Vector2((st as Node3D).global_position.x, (st as Node3D).global_position.z)
		if q.distance_to(at) > 90.0:
			continue
		(st as Node3D).visible = not hide
		st.process_mode = Node.PROCESS_MODE_DISABLED if hide else Node.PROCESS_MODE_INHERIT


func _clear_npcs() -> void:
	for k: String in _npcs.keys():
		_free_npc(k)


func npc_count() -> int:
	return _npcs.size()


func _display_name(speaker: String) -> String:
	var d := String((cast.get(speaker, {}) as Dictionary).get("display", speaker.capitalize()))
	return DialogueRunner.fill(d, ctx()) if d != "" else ""


# --- conversation --------------------------------------------------------------------------

## The page for one character. Starts a conversation when none is open for them.
func npc_menu(npc_id: String) -> Dictionary:
	if _conv.is_empty() or String(_conv["npc"]) != npc_id:
		_start_conv(npc_id)
	if _conv.is_empty():
		return {"speaker": _display_name(npc_id), "role": "", "line": "Nothing to say just now.", "title": _display_name(npc_id),
			"body": "", "options": [["Farewell", _leave]], "relationship": "", "rel_value": 0.0, "portrait_key": "r1_" + npc_id}
	var opts: Array = []
	for o: Dictionary in _conv["options"]:
		opts.append([String(o["text"]), _pick.bind(o)])
	opts.append_array(_lore_options(npc_id))
	if glue != null and glue.has_method("npc_extra_options") and String(_conv["node"]) != "":
		for extra: Array in glue.call("npc_extra_options", npc_id):
			opts.append(extra)
	var sp := String(_conv["speaker"])
	return {"title": _display_name(sp), "body": String(_conv["line"]), "speaker": _display_name(sp),
		"role": String((cast.get(sp, {}) as Dictionary).get("role", "")).get_slice(";", 0), "line": String(_conv["line"]),
		"options": opts, "relationship": "", "rel_value": 0.0, "portrait_key": "r1_" + sp}


func _start_conv(npc_id: String) -> void:
	_conv = {}
	var best: Dictionary = {}
	var fallback: Dictionary = {}
	for id: String in story.active_steps():
		var s := story.step(id)
		for e: Dictionary in story.dialogue_entries(id):
			if _entry_host(s, e) != npc_id:
				continue
			var cand := {"step": id, "file": String(e["file"]), "node": String(e["node"])}
			fallback = cand
			if not _talked.has(String(e["node"])) and best.is_empty():
				best = cand
	var pick := best if not best.is_empty() else fallback
	if pick.is_empty():
		return
	_conv = {"npc": npc_id, "step": String(pick["step"]), "file": String(pick["file"]), "node": "", "speaker": npc_id, "line": "", "options": []}
	_enter(String(pick["node"]))


func _cctx() -> Dictionary:
	return story.condition_ctx(ctx())


func _enter(node: String) -> void:
	var d: Dictionary = story.load_dialogue(String(_conv["file"]))
	var c := _cctx()
	var line := DialogueRunner.pick_line(d, node, c, _rng)
	var n: Dictionary = (d.get("nodes", {}) as Dictionary).get(node, {})
	_conv["node"] = node
	_conv["speaker"] = String(n.get("speaker", _conv["npc"]))
	_conv["line"] = String(line.get("text", "..."))
	# The node is shown: talk trigger first, then the line's own actions.
	_talked[node] = true
	var ev := story.notify(&"talk", {"node": node}, ctx())
	ev.append_array(story.apply_dialogue_actions(line.get("do", []), ctx(), String(_conv["step"])))
	_handle(ev)
	# Refresh the choice list after the actions (flags may open or close options).
	var opts := DialogueRunner.choices(d, node, _cctx())
	if opts.is_empty():
		opts = [{"text": "Farewell.", "goto": "@end", "do": []}]
	_conv["options"] = opts


func _pick(o: Dictionary) -> String:
	if _conv.is_empty():
		return ""
	var ev := story.apply_dialogue_actions(o.get("do", []), ctx(), String(_conv["step"]))
	_handle(ev)
	if _conv.is_empty():
		return ""
	var g := String(o.get("goto", ""))
	if g == "@end":
		_leave()
	elif g != "":
		_enter(g)
	return ""


func _leave() -> String:
	_end_conv()
	if hud != null and hud.has_method("close_menu"):
		hud.close_menu()
	return ""


func _end_conv() -> void:
	_conv = {}


func in_conversation() -> bool:
	return not _conv.is_empty()


## Headless access for tests and the autoplay: talk to a character as the game does, auto-picking choices.
## `picker` Callable(options: Array) -> int chooses the option (default: first). Returns lines shown.
func talk_through(npc_id: String, picker: Callable = Callable(), max_turns := 24) -> Array[String]:
	var shown: Array[String] = []
	_conv = {}
	var page := npc_menu(npc_id)
	var turns := 0
	while not _conv.is_empty() and turns < max_turns:
		turns += 1
		shown.append(String(page.get("line", "")))
		var opts: Array = _conv["options"]
		var i := int(picker.call(opts)) if picker.is_valid() else 0
		i = clampi(i, 0, opts.size() - 1)
		_pick(opts[i])
		if _conv.is_empty():
			break
		page = npc_menu(npc_id)
	_conv = {}
	return shown


## Who has a conversation on offer right now, as [{npc, step, place}] (for the autoplay and tests).
func hosts_with_talk() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: String in story.active_steps():
		var s := story.step(id)
		for e: Dictionary in story.dialogue_entries(id):
			var h := _entry_host(s, e)
			out.append({"npc": h, "step": id, "place": String(s.get("place", ""))})
	return out


## Optional side leads, offered as extra rows (never required): Harrok knows the caves under Greyseam; Wren has hunters' tales
## from the Glade that point toward the Hidden Vale. Text only, no markers.
func _lore_options(npc_id: String) -> Array:
	var out: Array = []
	if npc_id == "harrok_ashmaw" and (story.is_active("a4_greyseam") or story.is_done("a4_greyseam")):
		out.append(["Ask about caves in the hills", Callable(self, "_lead_cave")])
	if npc_id == "wren_coldbrook" and (story.is_active("a4_glade_trial") or story.is_done("a4_glade_trial")):
		out.append(["Ask about the hunters' old tales", Callable(self, "_lead_vale")])
	return out


func _lead_cave() -> String:
	var ex: Variant = Life.realm.mod("exploration") if Life.realm != null else null
	if ex == null:
		return "Harrok shrugs. Nothing he will say."
	var r: Dictionary = ex.call("rumour_for", _pp(), 4411)
	if r.is_empty():
		return "Harrok grunts. All the caves he knew, you have already heard of."
	ex.call("learn_lead", String(r["site_id"]), int(WorldSim.day))
	return "Harrok scratches a line in the dirt. %s (added to your leads)" % String(r["text"])


func _lead_vale() -> String:
	var HV := preload("res://scripts/world/hidden_valley.gd")
	var soc: Variant = Life.realm.mod("society") if Life.realm != null else null
	if soc != null:
		soc.call("learn", "lead:hidden_vale_hunters", String(HV.HUNTER_LINES[0]))
	return String(HV.HUNTER_LINES[0])


# --- parley: non-combat routes for the big creatures ------------------------------------

## Steps that end in a fight (`defeat`) also offer a way around it. The player makes the offering or
## the argument at the place and the quest counts it as beaten ("subdue"): nobody is forced to fight.
func parley_targets() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: String in story.active_steps():
		var o := story.current_objective(id)
		if String(o.get("type", "")) == "defeat":
			out.append({"step": id, "target": String(o.get("target", "")), "place": String(story.step(id).get("place", ""))})
	return out


func parley(target: String) -> bool:
	for t: Dictionary in parley_targets():
		if String(t["target"]) == target:
			_handle(story.notify(&"defeat", {"target": target}, ctx()))
			return true
	return false


# --- display -------------------------------------------------------------------------------

func _nearest_active() -> String:
	var best := ""
	var best_d := INF
	var pp := _pp()
	for id: String in story.active_steps():
		var r := Places.resolve(String(story.step(id).get("place", "")))
		var d: float = pp.distance_to(r["pos"]) if not r.is_empty() else 1.0e9
		if d < best_d or best == "":
			best_d = d
			best = id
	return best


## HUD tracker: the quest title and up to three active steps; the nearest carries a text lead.
func tracked_quest() -> Dictionary:
	if story == null or tracker_hidden or not enabled or not bool(SS.get_value("hud_quests")):
		return {}
	var active := story.active_steps()
	if active.is_empty() or story.is_complete():
		return {}
	var near := _nearest_active()
	var rows: Array = []
	var pp := _pp() if is_instance_valid(player) else Vector2.ZERO
	for id: String in active:
		if rows.size() >= 3:
			break
		var s := story.step(id)
		var o := story.current_objective(id)
		var text := String(s.get("objective", s.get("title", id)))
		rows.append({"text": text, "state": "current" if id == near else "todo"})
		if id == near:
			var lead := _lead(s, pp)
			if lead != "":
				rows.append({"text": lead, "state": "todo"})
	return {"title": String(story.quest.get("title", "The Stones Are Dimming")), "objectives": rows}


## The text lead for a step: who and where, in words (no marker).
func _lead(s: Dictionary, pp: Vector2) -> String:
	var pid := String(s.get("place", ""))
	var where := Places.lead_text(pp, pid)
	if where == "":
		return ""
	var giver := _display_name(String(s.get("giver", "")))
	if where == "You are here":
		return "%s is here." % giver if giver != "" else ""
	var nm := Places.place_name(pid)
	return "%s, %s (%s)" % [nm, where, giver] if giver != "" else "%s, %s" % [nm, where]


## A compass bearing hint for the step the player is nearest to, or null (hidden with the tracker).
func compass_target() -> Variant:
	if story == null or tracker_hidden or not enabled or not is_instance_valid(player):
		return null
	var id := _nearest_active()
	var pid := _marked if _marked != "" and id == "" else String(story.step(id).get("place", "")) if id != "" else _marked
	var r := Places.resolve(pid)
	return r["pos"] if not r.is_empty() else null


func set_tracker_hidden(on: bool) -> void:
	tracker_hidden = on
	_last_sig = ""
	changed.emit()


## Entries for the Quests tab: the main quest as one row with its steps as objectives.
func quest_entries() -> Dictionary:
	var out := {"active": [], "completed": [], "failed": []}
	if story == null:
		return out
	var objs: Array[Dictionary] = []
	var any_started := false
	for s: Dictionary in story.steps:
		var id := String(s["id"])
		if story.is_done(id):
			objs.append({"text": String(s.get("title", id)), "done": true})
			any_started = true
		elif story.is_active(id):
			var o := story.current_objective(id)
			objs.append({"text": "%s: %s" % [String(s.get("title", id)), String(s.get("objective", ""))], "done": false})
			any_started = true
	if not any_started:
		return out
	var pos: Variant = compass_target() if is_instance_valid(player) else null
	var entry := {"id": "r1_main", "title": String(story.quest.get("title", "The Stones Are Dimming")),
		"subtitle": "Main Quest · Act %d" % _current_act(), "desc": _act_blurb(),
		"group": "main", "state": "done" if story.is_complete() else "active", "objectives": objs,
		"rewards": [], "pos": pos, "tracked": not tracker_hidden, "source": "region1"}
	out["completed" if story.is_complete() else "active"].append(entry)
	return out


func _current_act() -> int:
	var act := 1
	for id: String in story.active_steps():
		act = maxi(act, int(story.step(id).get("act", 1)))
	if story.active_steps().is_empty():
		for s: Dictionary in story.steps:
			if story.is_done(String(s["id"])):
				act = maxi(act, int(s.get("act", 1)))
	return act


func _act_blurb() -> String:
	for a: Dictionary in story.quest.get("acts", []):
		if int(a.get("act", -1)) == _current_act():
			return String(a.get("title", ""))
	return ""


## The story journal page: each step's first-person line once it has started.
func journal_page() -> Dictionary:
	var entries: Array = []
	if story != null:
		var act := 0
		for s: Dictionary in story.steps:
			var id := String(s["id"])
			if not (story.is_done(id) or story.is_active(id)):
				continue
			var head := ""
			if int(s.get("act", 0)) != act:
				act = int(s["act"])
				head = "Act %d" % act
				for a: Dictionary in story.quest.get("acts", []):
					if int(a.get("act", -1)) == act:
						head += ": " + String(a.get("title", ""))
			entries.append({"head": head, "text": "%s. %s" % [String(s.get("title", "")), String(s.get("journal", ""))], "done": story.is_done(id)})
	return {"title": String(story.quest.get("title", "The Stones Are Dimming")) if story != null else "Story",
		"sub": "Your own account, as you write it", "entries": entries,
		"actions": [{"label": "Show the tracker" if tracker_hidden else "Hide the tracker", "call": Callable(self, "_toggle_tracker")},
			{"label": "Show all tips again", "call": Callable(self, "_replay_tips")}]}


func _replay_tips() -> void:
	if glue != null and glue.get("tutorial") != null:
		var t: Variant = glue.get("tutorial")
		if t.director != null:
			t.director.replay_all()
			Game.say("All tips will show again as they come up.")


func _toggle_tracker() -> void:
	set_tracker_hidden(not tracker_hidden)
