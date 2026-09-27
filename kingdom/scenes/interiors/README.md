# Building interiors

Five enterable interiors, each a self-contained scene. They're built by Blender scripts and ready to
wire into the world with one door node per building.

| Scene | Room | Tris (room + props) | NPC markers |
|---|---|---|---|
| `inn_interior.tscn` | Tavern hall 12 × 10 m (bar, fireplace, three long tables, stairs), plus a guest bedroom upstairs | see `assets/generated/interiors/interior_inn.json` | `NPC_Innkeeper` behind the bar, `NPC_Patron` by the fire, plus a `BedSpawn` marker in the bedroom |
| `blacksmith_interior.tscn` | Forge 10 × 8 m (coal forge, bellows, anvil, quench trough, racks, workbench) | `interior_blacksmith.json` | `NPC_Blacksmith` at the anvil |
| `guild_interior.tscn` | Guild hall 12 × 10 m (reception desk, quest board, banners, tables, hearth) | `interior_guild.json` | `NPC_Receptionist` behind the desk, `NPC_Adventurer` at the quest board |
| `healer_interior.tscn` | Healer 8 × 7 m (potion shelves, herbs, two beds, work table with mortar, cauldron) | `interior_healer.json` | `NPC_Healer` behind the work table |
| `house_interior.tscn` | Generic house 7 × 6 m (hearth, table, two beds, chest, shelves). Use it for all 5 house types | `interior_house.json` | `NPC_Resident` by the hearth |

Every interior stays under 60k triangles and uses 4 materials: `RA_Wood`, `RA_Plaster` (the shared
village textures), `RA_Ember` (fire and candle glow) and `RA_Props` (the shared props atlas). Lighting is
baked into the vertex colours. Each scene adds at most two unshadowed OmniLights (they flicker) and a warm
ambient `WorldEnvironment`.

## Scene layout (the same in every interior)

```
<Name>Interior (Node3D, interior_room.gd)
├── Room          the GLB (res://assets/generated/interiors/interior_<name>.glb)
├── Colliders     StaticBody3D, box shapes (walls, floor, ceiling, furniture, stair ramp)
├── PlayerSpawn   Marker3D just inside the entrance, facing into the room (-Z forward)
├── ExitDoor      Area3D + interior_door.gd (is_exit = true, prompt "Leave") at the entrance
├── NPCs          Marker3D "NPC_<Role>" (metadata: look, height, anim, role)
├── FireLight …   OmniLight3D (at most 2, shadows off, metadata/flicker = true)
├── WorldEnvironment   only used standalone. The door moves it onto the player camera
└── PreviewCamera      only used standalone. The door frees it
```

The entrance is always in the room's +Z wall. The origin is the centre of the ground floor at floor
height. Open any scene and press F6 to see it on its own.

## Wiring a building door (cloud session)

Add one `Area3D` with `res://scripts/interiors/interior_door.gd` and a `CollisionShape3D`
(a 2 × 2.2 × 2 m box) in front of each enterable building's door. Point its local +Z out into the street.

```gdscript
const InteriorDoorScript := preload("res://scripts/interiors/interior_door.gd")

func add_interior_door(building: Node3D, door_local: Vector3, facing_yaw: float, scene: String, label: String) -> Area3D:
	var door := Area3D.new()
	door.set_script(InteriorDoorScript)
	door.name = "InteriorDoor"
	door.interior_scene = scene                 # e.g. "res://scenes/interiors/inn_interior.tscn"
	door.prompt_text = label                    # e.g. "Enter the inn"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 2.2, 2.0)
	shape.shape = box
	shape.position.y = 1.1
	door.add_child(shape)
	building.add_child(door)
	door.position = door_local                  # on the ground, just outside the door
	door.rotation.y = facing_yaw                # +Z of the door node = out of the building
	return door
```

Scene per building key (`Assets.BUILDINGS`):

| Building | `interior_scene` |
|---|---|
| `inn` | `res://scenes/interiors/inn_interior.tscn` |
| `blacksmith` | `res://scenes/interiors/blacksmith_interior.tscn` |
| `adventurer_guild` | `res://scenes/interiors/guild_interior.tscn` |
| `healer_house` | `res://scenes/interiors/healer_interior.tscn` |
| `mhouse_peasant_a`, `mhouse_peasant_b`, `mhouse_family`, `mhouse_trader`, `mhouse_manor` (and the old `house_*`) | `res://scenes/interiors/house_interior.tscn` |

### What the door does

1. When the player (group `player`) is inside the area, the door joins the `interactable` group and
   answers `prompt()`. The HUD then shows its button like a station. main.gd's interact handler ignores
   unknown targets, so nothing else needs to change.
2. On `interact` (it polls `Input.is_action_just_pressed`, and only when it's the player's
   `nearest_interactable()`), `enter(player)` runs:
   - It instances the interior as a sibling of the player (under `World`), `interior_offset`
     (default 300 m) straight above the door. Above rather than below is on purpose: `player.gd` and the
     camera clamp to `WorldGen.height()`, so a room underground would get the player snapped out.
   - It hides every other child of `World` (terrain, settlements, sun, population...). Set
     `pause_exterior = true` to also stop their processing.
   - It takes the scene's `WorldEnvironment` and sets it as `player.camera.environment`, then restores it
     afterwards. The world's own environment is never touched.
   - It forces the third-person view and restores the previous view on exit. Every physics frame it pulls
     the chase camera in front of walls with a ray (`camera_collision`).
   - It moves the player to `PlayerSpawn`, facing into the room.
3. The interior's `ExitDoor` emits `exit_requested`. The entrance door then frees the interior, shows the
   world again and puts the player at `return_offset` (1.6 m in front of the door), facing away from it.

Only one interior exists at a time (`InteriorDoor.active`), and it is freed on exit.

Signals on the entrance door: `interior_entered(interior)`, `interior_exited()`,
`player_in_range_changed(bool)`. Use them for music (`Audio.set_mood("town")`), for pausing raids, or to
give the NPCs their menus.

### NPCs

By default `interior_room.gd` spawns one character per `NPC_*` marker with
`Assets.character(look, height)` and plays its `anim` (falls back to `Idle`). They're in the group
`interior_npc`, with `metadata/role` set (`innkeeper`, `blacksmith`, `receptionist`, `healer`, `patron`,
`adventurer`, `resident`).

To give them menus, connect to the door's `interior_entered` signal and add a `Station` at the NPC's
position:

```gdscript
door.interior_entered.connect(func(room: Node3D) -> void:
	for npc in room.get_tree().get_nodes_in_group("interior_npc"):
		if npc.get_meta("role") == "innkeeper":
			var st := Station.new("Innkeeper", "Talk", services.inn_menu)   # your menu Callable
			room.add_child(st)
			st.global_position = npc.global_position)
```

To use your own villagers instead, set `spawn_npcs = false` on the scene root and read
`room.npc_markers()`.

### Things to know

- If the player dies inside, `player.gd` respawns them at `spawn_point` outside while the room is still
  loaded. Call `InteriorDoor.active.leave()` from your death handler, or connect `player.health_changed`.
- The inn bedroom is upstairs in the same scene (stairs along the back wall, ramp collider). `BedSpawn`
  is a marker for "sleep here".
- House interiors are generic. Vary them per house type by toggling props in code if you like.

## Rebuilding

```bash
B="/c/Program Files/Blender Foundation/Blender 5.2/blender.exe"
cd kingdom/tools/blender
"$B" -b --python make_interior_inn.py          # add "-- --no-preview" to skip the renders
"$B" -b --python make_interior_blacksmith.py
"$B" -b --python make_interior_guild.py
"$B" -b --python make_interior_healer.py
"$B" -b --python make_interior_house.py
```

Each script rewrites the GLB, its `.import` (RA_Wood / RA_Plaster mapped to the shared `village_tex/*.tres`),
the `.tscn` and the previews in `docs/kingdom/blender_previews/interior_<name>_*.png`. The shared code is
`kingdom/tools/blender/interior_kit.py`. Don't hand-edit the `.tscn` files, because the next rebuild
overwrites them. Put gameplay nodes in code (door signals) or in a scene that instances these.

Sources: the shell and most furniture are procedural (`ra_kit`). Barrels, crates, sacks, woodpile, weapon
rack, anvil stump, water trough and flower planter come from `assets/generated/props` (shared atlas). The
tables, benches, chairs, cabinet, cauldron, workbench, grinding wheel, weapon stand, shields, swords, books
and coins come from Quaternius Fantasy Props MegaKit (CC0, `assets/incoming/quaternius/fantasy-props-megakit`),
with their colours baked into vertex colours and warm-graded.
