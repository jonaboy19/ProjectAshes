# Controls

One scheme, defined in one place: `Game.KEYS` / `Game.PADS` (`kingdom/autoload/game.gd`, `_setup_input`).
No two world actions share a key, and "Reset controls" in Settings re-creates every action from that table.
`tests/test_controls_scheme.gd` fails if two actions share a key or a menu key shadows one.

## In the world (no menu open)

| Key | Action | Touch equivalent |
|---|---|---|
| W A S D / arrows | move | left stick |
| Shift | sprint | stick pushed fully |
| Space | jump | Jump button |
| K | dodge | Dodge button |
| **J** | attack | Attack button |
| **L** | block | Block button |
| **C** | crouch / sneak | Sneak button |
| Q (or middle mouse) | lock on | Lock button (target reticle icon) |
| R | shadow dash | Dash button |
| E | interact / talk | Talk button |
| F | eat | (Pack menu) |
| V | change view | Look button (eye icon) |
| + / - / wheel | camera zoom | zoom buttons |
| 1-4 | hotbar skills (army orders 1-3 while you lead soldiers) | hotbar / order buttons |
| 5-8 | hotbar items | hotbar |
| G / B | army retreat / formation | order buttons |
| U, Y, O, H | techniques 1-4 (same as hotbar 1-4) | technique ring |
| 4-9 | hand seals (only while a seal sequence is running) | seal pad |
| **Tab** | Pack menu (last tab) | Pack button |
| **I** | Pack menu, Inventory tab | Pack button |
| **F2** | Pack menu, Skills tab | hotbar empty slot / technique ring |
| M | world map | Map button |
| P | photo mode | pause menu |
| Esc | pause menu | pause button / Android back |
| F5 / F9 | quick save / quick load | pause menu |
| F3 | performance overlay | - |

C, J, K and L used to be both combat keys and menu-tab keys (and K opened a second, older skills
screen). Now **J, K, L and C are only ever combat keys**; F2 opens the Skills tab.

## Inside the Pack menu (Tab / I / F2)

The menu pauses the game and owns the keyboard, so its keys are page-local and never reach the world.

| Key | Action |
|---|---|
| Q / E | previous / next tab (gamepad LB / RB) |
| 1-7 | jump to a tab in bar order: Inventory, Character, Skills, Quests, Map, Journal, Realm |
| I / F2 / M | jump to Inventory / Skills / Map (pressing the tab's own key again closes the menu) |
| Tab / X / Esc | close |
| arrows, Enter | move / choose inside a page |
| page keys | Inventory F G V U; Quests T; Map L (legend) F (focus) P (marker) +/- (zoom) |

Touch: the tab bar buttons, the E/X chips and every HUD button work exactly as before; nothing here
depends on a keyboard.

## Rebinding

Settings > Controls lists the actions in `SettingsStore.ACTIONS` and saves them to `[controls]` in
`user://settings.cfg`. Saved rebinds are re-applied at boot (`SettingsStore.apply_controls`).
