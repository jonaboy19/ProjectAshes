# Region 1 hooks: exact code for the cloud session (H1 and H2)

Scaffold is in (package L0): `kingdom/scripts/region1/`, tests `kingdom/tests/test_region1_scaffold.gd`, guide `kingdom/data/region1/README.md`.
Each hook is one small commit with the comment `# Region1 hook (docs/regions/REGION_1_PLAN.md)`. Merge origin first.

## H1: `kingdom/scripts/core/main.gd`, in `_ready`
Paste right after the `world.add_child(frontier)` / `Frontier.frontier_event.connect(...)` lines (any point after `world` exists and before the loading screen ends is fine; the node only reads the `WorldSim` autoload, so order does not matter):

```gdscript
	# Region1 hook (docs/regions/REGION_1_PLAN.md)
	world.add_child(preload("res://scripts/region1/region1_root.gd").new())
```
Cost: one `Timer` (1 s) and nothing per frame. With no rows in `data/region1/modules.json` it does nothing.

## H2: `kingdom/autoload/life.gd`
In `snapshot()`, just before `if player and is_instance_valid(player):`:

```gdscript
	# Region1 hook (docs/regions/REGION_1_PLAN.md)
	d["region1"] = Region1State.snapshot()
```

In `restore(d)`, just before `inventory_changed.emit()`:

```gdscript
	# Region1 hook (docs/regions/REGION_1_PLAN.md)
	Region1State.restore(d.get("region1", {}))
```
Old saves without `region1` are fine (modules reset to defaults). `Region1State` is a global `class_name`; if the class cache is stale, open the editor once (or use `preload("res://scripts/region1/region1_state.gd")`).

## Save/load round-trip test for C-H
Add to a Life test (or a new `tests/test_region1_hooks.gd`):

```gdscript
func test_life_snapshot_keeps_region1_block() -> void:
	var State := preload("res://scripts/region1/region1_state.gd")
	var Demo := preload("res://scripts/region1/demo_sim.gd")
	State.clear()
	var s := Demo.new().setup(5) as Region1Sim
	for i in 10: s.tick(0.5)
	State.register_sim(s)
	var before := s.digest()
	var snap: Dictionary = JSON.parse_string(JSON.stringify(Life.snapshot()))
	assert_bool(snap.has("region1")).is_true()
	s.tick(3.0)   # diverge
	Life.restore(snap)
	assert_str(s.digest()).is_equal(before)
	State.clear()
```
(The pure registry round trip already passes in `test_region1_scaffold.gd`.)

## Later hooks (H3 to H7)
Unchanged from the plan. Sims will expose plain functions/Callables for them; each package adds its exact snippet to this file when it lands.

## H3: coverage override for Wardlines (package L7)
`Wardlines.coverage_at(p)` is a drop-in for `RARunestoneNetwork.coverage(p)` (same 0..1 falloff). Every consumer (`RAThreatMap.evaluate`, `ecology.tick_day(runestones.coverage, ...)`, the Frontier spawn loops) already goes through `runestones.coverage`, so the smallest hook is inside that one function, `kingdom/scripts/sim/runestone_network.gd` (4 lines):

```gdscript
## Region1 hook (docs/regions/REGION_1_PLAN.md): Wardlines takes over coverage when set.
var coverage_override: Callable = Callable()

func coverage(p: Vector2) -> float:
	if coverage_override.is_valid():   # Region1 hook
		return coverage_override.call(p)
	... (existing body)
```
Wiring (package C3, in `main.gd` next to hook H1 or in `Frontier._ready` after `_seed_frontier()`; keep it guarded so old saves work):
```gdscript
	# Region1 hook (docs/regions/REGION_1_PLAN.md)
	var wl := Region1State.sim(&"wardlines") as Wardlines
	if wl:
		if wl.layout_source != "network":        # a loaded save already carries its own layout
			wl.bind_network(Frontier.runestones)  # stone id = network id; picks 5 Elder Stones (or pass ids)
		Frontier.runestones.coverage_override = wl.coverage_callable()
```
and add the row `{"name": "wardlines", "script": "res://scripts/region1/wardlines.gd", "enabled": true}` to `data/region1/modules.json`. While the override is on, do not call `runestones.tick_day` decay for wear (Wardlines owns wear); if you still want the old "X is failing" events, call `wl.push_to_network(Frontier.runestones)` once a day. Rumours: `wl.rumours()` has the same voice as `RARunestoneNetwork.rumours()`; every change also arrives as a `Region1Sim.event` (`road_rumour`, `road_clear`, `stone_dark`, `stone_lit`, `link_cut`, `glyph_carved`, `alarm`, `elder_strained`) with a ready `data.rumour` string.
Player-facing calls for C3/L13: `carve(stone_id, "ward"|"lure"|"alarm"|"bless"|"none")`, `add_link(a, b)`, `cut_link(a, b)`, `mend_link`, `set_pinned`, `repair`, `notify_threat(pos)` (alarm stones), `bless_at(pos)` (crop yield multiplier), `lure_points()` (for the ecology), `pressure(pos, r, amount)` (Scar Tide), `elder_status()`, `budget_report()`.
The recognizer for the carve canvas: `RuneGesture.new().recognize(strokes)` returns `{glyph, score, accepted, ...}`; pass `glyph` to `carve`.

## C8: onboarding with the tutorial director (package L16)
Files: `scripts/region1/tutorial_director.gd` (pure rules, 12 prompts), `tutorial_prompt_view.gd` (draws a prompt on the HUD), `tutorial_game_bridge.gd` (reads the running game and places the prompts). Prompt text lives in `locale/strings.csv` (`TUT_*`, en and nl). The demo sheet is `docs/regions/tutorial_demo_sheet.jpg`, and the sandbox is `tools_qa/region1/tutorial_sandbox.tscn`.

**Hook (3 lines), `kingdom/scripts/core/main.gd` `_ready`**, anywhere after `hud` and `player` exist (for example right after H1):
```gdscript
	# Region1 hook (docs/regions/REGION_1_PLAN.md) C8: contextual tutorial prompts
	var tutorial := Region1TutorialBridge.new()
	add_child(tutorial)
	tutorial.setup(player, hud)
```
That is all that's needed for move, look, talk, interact, eat, sleep, fight, block, dodge and map. The bridge:
- polls the input actions (the HUD's TouchScreenButtons press the same ones);
- watches `Life.needs` food and rest going up, the camera yaw and the player's velocity;
- finds enemies in group `team1`; wind-up is read from `is_winding_up()` if an enemy has it, else from `wolf.gd`'s `_winding` (X4: please add `is_winding_up()` to humanoids);
- blocks prompts while `hud.is_menu_open()`, the tree is paused, or a `cutscene_active` player is playing;
- saves through `Region1State` (key `tutorial`, rides on H2).

**The rest of the prompts** come from other packages. Each is one line:
```gdscript
Region1TutorialDirector.tell(&"carve")      # C3/L13: the runecarve canvas accepted a glyph
Region1TutorialDirector.tell(&"ashsight")   # C6: the player held Ashsight at a site
Region1TutorialDirector.tell(&"map")        # the Map tab opened (the Tab key already counts)
```
Context providers tell the bridge when those prompts are relevant (each is a `Callable(player_pos: Vector3) -> bool`):
```gdscript
tutorial.providers["near_dim_stone"] = func(p: Vector3) -> bool:   # C3
	var id := wl.nearest_stone(Vector2(p.x, p.z), 6.0)
	return id >= 0 and wl.stone_band(id) < Wardlines.BAND_GLOWING
tutorial.providers["knows_glyph"]   = func(_p: Vector3) -> bool: return story.has_flag("r1.a1.taught")                    # C7
tutorial.providers["near_ash_site"] = func(p: Vector3) -> bool: return ash_memory.has_site_near(p, 8.0)                  # C6 (L11 API)
tutorial.providers["new_marker"]    = func(_p: Vector3) -> bool: return quest_marker_unseen                              # C7
```
**Settings and menu:**
- Settings toggle "Tutorial tips" (`TUT_TIPS`): `tutorial.director.set_enabled(on)`.
- Game menu "Show all tips again" (`TUT_REPLAY_ALL`): `tutorial.director.replay_all()`.
- Replay a single tip (`TUT_REPLAY`): `tutorial.director.replay(&"block")`.
- The small x on a prompt skips it (`TUT_SKIP`).

**First 20 minutes (C8 flow):** birth → childhood → at age 8, quest step `a1_dark_stone` (C7 wiring below) → the Miller's Stone (`carve` prompt, first glyph, story flag `r1.a1.first_glyph` = the metric) → `a1_hesks_ember` emits `["spawn", "wolf", "ashford_ring", 1]`. That is the safe first fight: one lone wolf at dusk at the ring edge, which the fight, block and dodge prompts teach against. Make that wolf non-lethal (knockdown, not death) until `a1_wolf_at_dusk` is done.

## C7: story quest runtime (package L14)
Runtime: `scripts/region1/story_quest.gd` (`Region1StoryQuest extends Region1Sim`). Data: `data/region1/quests/r1_main.json` (schema in `data/region1/quests/README.md`). Story and cutscene beats: `docs/regions/STORY_R1.md`.

**Create and save** (next to H1, or as a manifest row once C7 wires the events). Loading happens in code because the quest needs its data file:
```gdscript
	# Region1 hook (docs/regions/REGION_1_PLAN.md) C7: main quest
	var story := Region1StoryQuest.new()
	story.setup(WorldSim.SEED)
	story.load_quest("res://data/region1/quests/r1_main.json")
	Region1State.register_sim(story)   # saves under "story_quest"; Region1Root ticks it (no-op)
```
**Context** for every call: `{"age": Life.age, "flags": <life_path flags as {name: true}>, "items": <inventory counts>, "vars": {"family": ..., "stone_name": ...}}`. Call `story.refresh(ctx)` once a second (Region1Root's tick is fine) and after loading.

**Events to feed** (from existing emitters; each is one line where the thing happens). `notify(type, params, ctx)`:
| When | Call |
|---|---|
| Player enters a registry place (C1 radius) | `story.notify(&"enter_area", {"place": id}, ctx)` |
| Kill (`wolf.gd`, `monster.gd`, X4 bandits) | `story.notify(&"kill", {"target": kind, "place": nearest_place_id, "amount": 1}, ctx)` |
| Boss or trial beaten | `story.notify(&"defeat", {"target": "antlered_warden"}, ctx)` |
| Wardlines `glyph_carved` event | `story.notify(&"carve", {"glyph": d.glyph, "stone": story_stone_id(d.id)}, ctx)` (map the network id to the registry stone by place) |
| Wardlines `link_made` | `story.notify(&"wardline_link", {"from": story_stone_id(d.a), "to": place_or_stone(d.b)}, ctx)` |
| Wardlines Elder Stone lit (`elder_calm` after a relight, or a `stone_lit` on an elder id) | `story.notify(&"relight_elder", {"stone": "elder_glade"}, ctx)` |
| Scar Tide cells contained or harvested (L9/C4) | `story.notify(&"scar_contain", {"place": id, "amount": cells}, ctx)` and `&"scar_harvest"` |
| Ashsight used at a site (C6) | `story.notify(&"ashsight", {"site": place_id}, ctx)` |
| Ember choice radial (C5/L13) | `story.notify(&"ember_choice", {"who": "rowan", "choice": "stone"}, ctx)` (choice: stone, heir or heirloom) |
| Cutscene finished (C9) | `story.notify(&"cutscene_done", {"cutscene": id}, ctx)` |

**Conversations:**
- `story.dialogue_entries(step_id)` → `[{file, node, speaker}]` lists what the step's giver offers now.
- Show them with `DialogueRunner.load_file(file, "res://data/region1/dialogue")`, passing `story.condition_ctx(ctx)` as the runner ctx.
- Hand each shown line's and chosen option's `do` to `story.apply_dialogue_actions(do, ctx, step_id)`.
- Call `story.notify(&"talk", {"node": node}, ctx)` for every node shown.

**Returned events:**
- `step_started` / `step_completed`: tracker pin, Journal and toasts.
- `action` events for you to apply:
  - `give` → `Life` inventory
  - `rep` → reputation
  - `gold`
  - `cutscene` → C9
  - `marker` → compass
  - `spawn` → Frontier
  - `tutorial` → `tutorial.director.replay(id)`
- `quest_completed`: the Region 1 complete card.

Tracker text is `story.step(id)["objective"]`; the Journal uses `title` and `journal`.

**Test:** `Godot --headless --path kingdom -s res://tools_qa/region1/lint_quests.gd` must stay at 0 errors. `tests/test_region1_story.gd` shows the calls step by step.
