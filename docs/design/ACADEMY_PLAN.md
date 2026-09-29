# Childhood, academies and power paths: implementation plan

Spec: `CHILDHOOD_ACADEMIES.md` (C§n). Timing rules: `SIM_HIERARCHY.md`. The work extends what already exists and doesn't replace it:

| Existing | Role now | Extended by |
|---|---|---|
| `sim/childhood_events.gd`, `sim/tendencies.gd` | ages 4–8 activities become invisible tendencies (C§2) | new activity kinds: watch soldiers, healer, hunters, benders; imitate magic; fights |
| `sim/scouts.gd` | scout offers (currently ages 12–24) | **Scout Season at age 9** (C§3–5) with a visiting org mix by geography, war and wealth; tests on many axes; corruption; being overlooked opens late routes |
| `sim/family.gd` | parents and heirs | **household economy** (C§1, 18, 19): parents' jobs, food, tax, debt, bad harvest, injury; autonomous sacrifice (extra job, selling items, skipping meals) that the player can discover |
| `sim/awakening.gd`, `sim/soul.gd`, `sim/skills.gd` | power growth | **power paths** (C§32–38): five resource models with their own fatigue |
| `realm/society.gd`, `realm/city_life.gd` | relationships, jobs, guilds | classmates and teachers as notable NPCs; student jobs; adventuring contracts |
| `realm/factions.gd` (church) | church influence | church-funded schools and curriculum loyalty (C§47/48) |

## New modules (realm hub modules, same interface)

1. **`realm/education.gd`**: covers C§6–31 and C§44–49.
   - **Institutions:** magic academy, bending school, martial sect, knight academy, plus specialist schools (C§10). Each has a culture, region, church alignment, rival schools, prestige, tuition and a campus site id.
   - **Admission:** via the scout season, an exam, sponsorship, a private teacher, military entry or a tournament.
   - **Student life:**
     - Schedule blocks with the ×5 time acceleration flag, and interrupt events that bring normal speed back (C§12).
     - Truancy leads to detention, loss of privileges, suspension and expulsion (C§13).
     - Performance has several dimensions: combat, theory, practical, leadership, discipline (C§14).
     - Rankings attract recruiters and rivals (C§15).
   - **People:**
     - A class roster of about 30 named classmates whose **future careers are simulated later** (C§16/49).
     - Social class inside the school (C§17).
     - Expenses (C§18).
     - Sponsors with obligations (C§22).
     - Student factions and clubs (C§23/24).
     - Dynamic rivals that can later turn into allies (C§25).
     - Teachers with their own personalities, and mentorship requirements (C§26/27).
   - **Events:** tournaments that give fame (C§28), field exercises that can go wrong (C§29), graduation offers that can be refused (C§30), dropping out (C§31), and school reputation that follows the player (C§45).
2. **`realm/power_paths.gd`**: covers C§32–38. Each path has its own resource model:

   | Path | Resource | Fatigue |
   |---|---|---|
   | Magic | mana | concentration, exhaustion and instability risk |
   | Bending | resonance | breath, stance and environment access (water near rivers) |
   | Sect | internal energy | channel strain and injuries |
   | Knight | stamina | armour load and conditioning |
   | Beast | bond | trust and mental burden |

   Cross-training slows each path down. Prodigy conditions unlock only through rare events, and never in the first region.
3. **`realm/household.gd`**: covers C§1, C§18/19 and C§39–43.
   - The family economy, with parental sacrifice discovered through clues.
   - Family travel that the world simulation can turn dangerous: raids, kidnapping, displacement far away, forced labour, escape or rescue.
   - The search for missing family is **optional**: no main-quest marker, only leads in society knowledge.
   - Parents can die from believable causes.

## Guidance instead of cutscenes (user direction)

- Keep the opening cutscenes: birth and "four years later".
- After the opening, **don't add new cutscenes**. Guide the player with the region-1 tutorial director (`region1/tutorial_director.gd`, `tutorial_prompt_view.gd`) and text hints in the HUD notify stack.
- Scout Season, admission, kidnapping and graduation play out **in the world**: NPCs walk up and talk (dialogue_ui), with a short banner (event banner), then a hint of what to do next.

## War map: the real area, click-through (user direction)

- The War Room map has **zoom levels**:
  1. **World**, using the world map texture.
  2. **Region**, where the war front sits.
  3. **Local area**, a battle site or city, using the city map or local terrain render.
- Tapping a front, stronghold or city zooms in, and a Back button zooms out.
- **Troop dots:** each army is drawn as a cluster of dots, one dot per 25 men (capped at 40, with a count label). Enemy dots are drawn from the **estimated** range: scattered and fading with confidence.
- In the local view, dots group by formation (line, wedge, square) and supply lines are dotted paths.
- Orders are given by tapping dots, then a target, in any view. They are still delivered by courier with a delay.
- It builds on `world_map.gd` (embedded, zoom_by) and `tab_realm.gd`.

## Work packages (Sonnet executes, Opus reviews)

- **P1:** `education.gd` + `household.gd` + tests. Scout Season at age 9 in `scouts.gd` or `childhood_events.gd` through a small hook.
- **P2:** `power_paths.gd` + tests, plus a hook so the player's skill use drains the right resource.
- **P3:** War map zoom levels and troop dots in `tab_realm.gd`, with screenshots.
- **P4:** In-world presentation of academy scouting and campus (first region: one academy campus site near Kingsreach, built from existing assets), and tutorial prompts in place of cutscenes.

## Everyone learns to fight (user direction)

- Whatever the role (blacksmith, farmer, merchant, scholar), the player can always train combat: at the village drill yard, with guards, with hunters, or self-taught. Combat skill is never locked behind a career.
- Careers generate **call-ups**. When something goes wrong, your employer, guild or neighbours come to you. Examples:
  - The smithy's ore shipment is stolen.
  - Wolves are at the farm.
  - The caravan you supply goes missing.
  - The militia levy is called in wartime.
- These become quests offered in the world by the NPC walking up to you, never by a marker. Quality of work, reputation and known fighting ability decide who gets asked.
- Implemented in `education.gd` (training access) and `city_life.gd`/careers (call-up generator), hooked through `hub.mod`.

## War map (after everything else)

The full spec is in `WAR_COMMAND_RULEBOOK.md`, with the UI reference `war_ui_reference.webp`. Live 3D battles are **paused** (`realm_presence.gd` `LIVE_BATTLES_ENABLED := false`), so war is played on the map only, like chess:

- pieces per formation, split and merge
- drag to move
- courier delay and fog of war
- command authority by rank

## Power systems: deferred until the world is built (user direction)

- **Martial arts, two traditions:**
  - Sects follow **donghua-style martial arts**: internal energy, cultivation, techniques and manuals.
  - Knights have their **own knight martial arts**, in the anime and fantasy-knight style: aura, reinforced sword forms, charge techniques and armour arts. It is a separate tree, not a copy of the sect one.
- **Chantless magic** is advanced only. It needs a high magic level, spell-theory mastery and several path milestones. Beginners must chant.
- Every path gets full **levels, sub-paths and technique trees**, built on `realm/power_paths.gd`.
- **Order of work:** the world and the living mechanics per job come first. Power comes after the world is built properly.
