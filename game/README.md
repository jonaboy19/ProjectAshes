# Rising Ashes — Godot prototype

Playable vertical slice of the Aramori region. Screenshots are in `../docs/screenshots/`;
the design doc is `../docs/GDD.md`.

## Run it on your PC

1. Install **Godot 4.4** (standard build, not .NET): https://godotengine.org/download
2. Open Godot → **Import** → select `game/project.godot`.
3. Press **F5**.

Controls on PC: WASD move · Shift run · J strike · K bless · Space dodge · E talk.
Left-drag on the right half of the screen turns the camera (touch emulation is on).

## Put it on an Android phone

1. In Godot: **Editor → Manage Export Templates → Download**.
2. Install Android Studio (for the SDK) and set its path in
   **Editor Settings → Export → Android**.
3. **Project → Export → Android → Export Project** writes `build/RisingAshes.apk`.
4. Copy the APK to your phone and install it (allow "install unknown apps").

## Layout

```
autoload/   GameState (flags, save, input), Quests, Dialogue
data/       quests.json, blessings.json, dialogue/*.json  ← story content lives here
scenes/     main.tscn
scripts/
  world/    aramori.gd (region + story beats), terrain.gd, props.gd, interactable.gd
  player/   player.gd
  npc/      npc.gd
  combat/   rift_beast.gd, blessing_bolt.gd
  ui/       hud.gd, virtual_joystick.gd
```

## Art credits

Characters, buildings, trees, rocks, props and clouds are from **KayKit** by
Kay Lousberg (www.kaylousberg.com), released under **CC0**, so they're free for
commercial use:

- `assets/kaykit/characters/` — Adventurers Character Pack 1.0 (rigged, 76 animations)
- `assets/kaykit/medieval/` — Medieval Hexagon Pack 1.0 (curated subset)

The bell tower, Rift scar, Rift beasts and lanterns are still procedural
placeholders in `props.gd` / `rift_beast.gd`. Note: embedded textures in the
`.glb` files only extract when Godot imports with a renderer (not `--headless`).

## Preview screenshots (headless)

```
godot --path game --rendering-driver opengl3 -- --shot=gameplay --out=/tmp/shot.png
```
Shots: `gameplay`, `overview`, `dialogue`, `ceremony`, `beyond`, `title`.
