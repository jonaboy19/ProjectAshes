# Autoplay playtest bot

Boots the real game (`res://scenes/main.tscn`, instanced as a child, so `main.gd` needs no changes),
windowed on the real GPU, and plays a scripted scenario like a phone player would.

## Run it (one command, from the repo root)

```bash
kingdom/tools_qa/autoplay/run_autoplay.sh            # game's own fps cap (what players get)
kingdom/tools_qa/autoplay/run_autoplay.sh --uncapped # vsync off, no fps cap: shows GPU headroom
```

Set `GODOT=/path/to/Godot_console.exe` if Godot isn't at the default path. A full run takes about
4 to 5 minutes. Don't touch the mouse over the game window while it runs.

Output goes to `docs/qa/playtest/`:

| File | What |
|---|---|
| `NN_<step>.jpg` | 1280×720 screenshot at every step |
| `log.txt` | timestamped actions, a perf line every 0.5 s (fps, frame time, CPU ms, 3D GPU ms, draw calls, primitives, objects, nodes, VRAM), per-step summaries, `FINDING` lines, and engine errors caught in-process (`OS.add_logger`) |
| `summary.json` | per-step perf aggregates plus the findings, machine readable |
| `godot_stdout.txt` / `errors.txt` | raw console output, and its SCRIPT ERROR / ERROR / WARNING lines |

## Input path

Everything goes through `Input.parse_input_event`, the same path as real hardware:

- **Move**: touches and drags on the HUD `VirtualJoystick` (`InputEventScreenTouch/Drag`, index 0).
- **Camera**: drags on the HUD look area (index 1), which calls `Player.add_look`. The bot steers by
  swiping toward its target each frame.
- **Actions**: `InputEventKey` with the physical keys from `Game._setup_input` (E, J, L, Space, F5, F9),
  plus taps on the HUD's `TouchScreenButton`s (Talk, Attack).
- **Menus**: mouse clicks on the menu `Button`s.
- **Cutscene**: a double tap, as the "Tap again to skip" hint asks.

Shortcuts a player can't take are logged as `[HOOK]`: ageing the child to 18 after the first
playable frame, fast travel to the wolf den and the goblin warren, setting the clock for the night
check, giving 2 wolf pelts to test selling, and (while interior doors aren't wired in the world) a
test `InteriorDoor` at the inn built exactly as `scenes/interiors/README.md` describes.

## Scenario

1. Boot: birth cutscene, double-tap skip, time to the first playable frame, a few steps as the child.
2. Ashford: walk to the plaza, 360° look, guild hall, inn, blacksmith, healer, houses, stall; walk up
   to the innkeeper, the Captain of the Guard and a villager or guard.
3. Interact: notice board (E), guild (Talk button, Join), trader (buy bread, sell a pelt, gold checked),
   Captain.
4. Interior: enter the inn through an `InteriorDoor`, walk and look around, leave through `ExitDoor`.
5. Combat: leave the runestone protection (danger logged), fight the wolf pack at the nearest den,
   then the Mossfang goblin warren: attack, block, dodge, with screenshots of contact, block, dodge,
   being hurt and the death animations.
6. Night: rent a bed at the inn (time must advance), then 22:30 at the plaza (lamps must be lit).
7. Save/load: F5, change position, gold, health, time and inventory, F9, and compare every field.

To add a step, write a `_step_x()` coroutine in `autoplay.gd` using `walk_to`, `face`, `look_around`,
`interact_with`, `click_menu`, `fight`, `shot` and `finding`, and call it from `_run()`.
