# Region 1 quest data (schema 1)

Authored quests for Region 1: the main quest `r1_main.json` ("The Stones Are Dimming", L14), and later the side quests (L15, same schema). The story is in `docs/regions/STORY_R1.md` and the cast in `docs/regions/CAST_R1.md`.

| File | What |
|---|---|
| `r1_main.json` | Main quest: 5 acts, 38 steps (story v2; curve in `docs/regions/EMOTION_MAP_R1.md`) |
| `r1_registry.json` | Every id a step may name: places, stones, glyphs, targets, cutscenes, festivals, factions, new items, choice groups, external and exported flags, text tokens |
| `cast.json` | Speakers: 12 principal plus supporting ones, each with display name, role and a one-line voice note |
| `../dialogue/r1_act1..5.json` | Conversations in the `dialogue_runner.gd` format, plus a `speaker` key on each node |

Runtime: `scripts/region1/story_quest.gd` (`Region1StoryQuest`, a `Region1Sim` that saves through `Region1State`). Lint: `tools_qa/region1/lint_quests.gd`. Quest ids are save data: never rename a shipped step, objective or flag.

## Quest file
```json
{"id": "r1_main", "schema": 1, "title": "...", "registry": "res://...", "cast": "res://...",
 "dialogue_dir": "res://data/region1/dialogue", "complete_flag": "r1.complete",
 "acts": [{"act": 1, "title": "...", "dialogue": "r1_act1", "ages": "8-12", "teaches": ["wardwright"]}],
 "steps": [ ... ]}
```

## Step
| Key | Req | Meaning |
|---|---|---|
| `id` | yes | `a<act>_<name>`, unique |
| `act` | yes | 1..5 |
| `title` | yes | Journal heading, ≤ 32 chars |
| `objective` | yes | HUD tracker pin, ≤ 48 chars |
| `journal` | yes | First-person journal line, ≤ 160 chars |
| `giver` | yes | cast id; who offers the step's conversations |
| `place` | yes | registry place id (compass marker) |
| `objectives` | yes | Ordered list (below). Only the first open objective listens to events |
| `requires` | no | `{"steps": [ids], "if": {dialogue_runner condition}}`. A step starts when every listed step is done and the condition holds. Several steps can be active at once (Act IV hubs) |
| `dialogue` | no | `[{"node": id, "after": objective_id?, "file": dialogue_file?}]`. Conversations the giver offers. With `after`, only once that objective is done. `file` defaults to the act's dialogue file |
| `mechanics` | no | `{"wardwright" \| "scar_tide" \| "ember_legacy" \| "ashsight": "teach" \| "use"}` |
| `tutorial` | no | Tutorial prompt ids (`tutorial_director.gd`) this step is likely to need; C8 may `replay()` them |
| `on_start`, `on_complete` | no | Actions (below) |
| `staging` | no | Emotional staging for C7/C9/C12/Codex: `intensity` (-5..+5, required when staging is present), `emotion`, `music` (a registry `music` cue), `sfx`, `camera`, `anim`, `vfx`, `silence`, `weather`, `time`, `needs` (subset of `c9`, `codex`, `vfx`). The lint warns when a step has none, and when 4 steps in a row stay within 1 point (a flat stretch) |

## Objective (trigger) types
Every objective has `id` and `type`. Optional on all: `do` (actions when it completes) and `sets` (a flag set when it completes; used on `any` branches).

| type | Keys | Done when |
|---|---|---|
| `flag` | `flag` | the flag is set (story flags via `set_flag` / dialogue `do`, or game flags in ctx) |
| `choice` | `group` | any flag of the registry choice group is set |
| `talk` | `node` | the dialogue node is shown (`notify(&"talk", {node})`) |
| `age` | `min` | `ctx.age >= min` |
| `item` | `item`, `count`? | `ctx.items[item] >= count` or `notify(&"item", {item, amount})` |
| `enter_area` | `place`, `radius`? | `notify(&"enter_area", {place})` |
| `kill` | `target`, `place`?, `count`? | `notify(&"kill", {target, place, amount})` sums to count |
| `defeat` | `target`, `subdue`? | `notify(&"defeat", {target})`; subdue = beaten, not killed |
| `carve` | `glyph`, `stone`, `count`? | `notify(&"carve", {glyph, stone, amount})` |
| `relight_elder` | `stone` (kind elder) | `notify(&"relight_elder", {stone})` |
| `wardline_link` | `to`, `from`?, `count`? | `notify(&"wardline_link", {from, to, amount})` |
| `scar_contain` | `place`, `cells` | `notify(&"scar_contain", {place, amount})` sums to cells |
| `scar_harvest` | `place`, `crystals` | `notify(&"scar_harvest", {place, amount})` |
| `ashsight` | `site` | `notify(&"ashsight", {site})` |
| `ember_choice` | `who`, `group` | `notify(&"ember_choice", {who, choice})`; sets `ember.<who>.<choice>` |
| `cutscene_done` | `cutscene` | `notify(&"cutscene_done", {cutscene})` |
| `festival` | `festival` | `notify(&"festival", {festival})` |
| `any` | `of: [objectives]` | the first branch that completes (no nesting) |

An event matches when every key the objective sets (except the counters) is equal. The `amount` default is 1.

## Actions
Used in `on_start`, `on_complete` and objective `do`. `flag` is applied by the runtime; the rest come back as `{"type": "action", "action": [...]}` events for the game:
`["flag", name]`, `["give", item, n]`, `["rep", faction, delta]`, `["gold", n]`, `["cutscene", id]`, `["marker", place]`, `["spawn", target, place, n]`, `["tutorial", prompt_id]`.

## Dialogue
Plain `dialogue_runner.gd` JSON (conditions, priorities, `do` actions, `@end`). Load with `DialogueRunner.load_file("r1_act1", "res://data/region1/dialogue")`. Additions:
- `speaker` on every node (a `cast.json` id) for the name plate and portrait. The runner ignores it.
- Lines ≤ 120 characters and choices ≤ 40 (phone). Spoken lines have no quote marks; the narrator's lines are stage directions.
- Text tokens: `{player} {mother} {father} {family} {ancestor} {stone_name}` via `ctx.vars` (see the registry).
- Pass `quest.condition_ctx(ctx)` as the runner's ctx so story flags count, and hand each shown line's and chosen option's `do` to `quest.apply_dialogue_actions(...)`.

## Flags
Story flags use `r1.` (and `ember.<who>.<choice>` for Ember Legacy choices). The lint fails when:
- a read flag is never set (outside `external_flags`);
- a set flag has no namespace;
- a choice group's flag has no setter.

## Lint
```
Godot --headless --path kingdom -s res://tools_qa/region1/lint_quests.gd              # sampled autoplay, ~10 s
Godot --headless --path kingdom -s res://tools_qa/region1/lint_quests.gd -- --exhaustive   # all 10368 choice combinations, ~25 min (measured 25.2 min)
```
It checks schema, lengths, speakers, places, stones, glyphs, targets, items, cutscenes, tutorial ids, actions, conditions, tokens, flags, step order, mechanic coverage (each taught before use, in 2+ acts) and dialogue reachability. It then **plays the quest to the end** with the real runtime and dialogue runner, across choice combinations, Blessing results, times of day and weather. It reports:
- any step that gets stuck;
- any node with no line to show;
- any node or line never reached.
