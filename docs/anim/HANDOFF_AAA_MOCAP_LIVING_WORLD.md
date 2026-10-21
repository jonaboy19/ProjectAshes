# Complete AAA Mocap, Combat, Avatar Bending, Parkour & Magic Suite (136 Clips)

**Recipient:** Claude (Project Ashes Core Developer)  
**Author:** Antigravity (Animation & Pipeline Specialist)  
**Target Repository:** `jonaboy19/ProjectAshes`  
**Dedicated Branch:** `antigravity/aaa-mocap-animations`  
**Date:** October 2026  
**Status:** Complete / Fully Baked, Retargeted, Articulated & Delivered (Zero modifications to Claude's `kingdom/scripts/`)

---

## 1. Executive Summary

This massive expansion elevates *Project Ashes* to full AAA gameplay breadth across **combat, magic, parkour, martial arts, and living world simulation**.
- **136 Authentic Motion Capture Clips** retargeted to the Quaternius UAL 65-bone skeleton.
- **Rooftop Parkour & Vertical City Traversal:** Full wall mantling, rooftop gap leaps with recovery rolls, sloped tile sliding, roof ridge tightrope balancing, and vertical ladder climbing.
- **Specialized Classes & Stances:**
  - **Knights:** Upright greatshield guard stances, shield rush charges, pommel strikes, and execution cleaves.
  - **Assassins:** Low shadow crouch creeping, sneak throat-slit assassinations, ledge drag-down takedowns, aerial drop impales, and smoke bomb vanish drops.
- **Chantless Arcane Magic:** Instant open-palm force blasts, telekinetic levitation lifts, aegis barrier conjuration, ground sigil eruption fissures, life/mana siphon drain, and dimensional blink steps.
- **Bending Mastery & Authentic Martial Arts:** Wing Chun centerline chain punching, Muay Thai clinch and knee strikes, Capoeira sweeping ground kicks, Lightning redirection and discharge, Earth metalbending stomps, Water whip flurries, and Air vortex vacuums.
- **Natural Impact & Knockback Physics:** Directional heavy sliding brake knockbacks, violent airborne blowbacks, 3-step stumble recoils, and heavy guard impact staggers.
- **Dynamic Natural Finger Articulation:** Procedurally driven finger flexes and curls tied to arm swing inertia, climbing rungs, tool strikes, and casting gestures.
- **Compact Footprint:** Douglas-Peucker & quaternion geodesic compression (`glb_reduce_anim.py`) keeps all 13 binary packages **under 5.5 MB total**.

---

## 2. Complete Animation Package Directory (13 GLBs, 136 Clips)

```
res://assets/incoming/animations/aaa/
├── UAL_AAA_Locomotion.glb         (748 KB, 15 clips) - Grounded locomotion, weighted plants, banking, hurdles, ladder
├── UAL_AAA_LivingWorld.glb        (1.22 MB, 28 clips) - Medieval settlement simulation, taverns, crafts, trades, bards
├── UAL_AAA_Combat_Chains.glb      (475 KB, 14 clips) - 4-hit light combos, heavy charged strikes, sprint/roll attacks, parries
├── UAL_AAA_Combat_Weapons.glb     (323 KB, 11 clips) - 2H Greatsword, Polearms, Dual Wield Daggers, Archery Bow
├── UAL_AAA_Combat_Reactions.glb   (315 KB,  8 clips) - Head flinches (L/R), gut punch, sweeps, knockdowns, get-ups, wall splat
├── UAL_AAA_Combat_Knockbacks.glb  (163 KB,  4 clips) - Heavy sliding knockback, airborne blowback, 3-step recoil, guard stagger
├── UAL_AAA_Combat_Classes.glb     (303 KB,  9 clips) - Knight shield rush & pommel strike, Assassin stealth & assassinations
├── UAL_AAA_Combat_Adv.glb         (260 KB,  6 clips) - High deflect parry, sword riposte, fencing lunge, shield bash, slip dodges
├── UAL_AAA_Magic_Chantless.glb    (212 KB,  6 clips) - Chantless palm blast, telekinesis, barrier conjure, blink step, siphon
├── UAL_AAA_Traversal_Rooftops.glb (267 KB,  7 clips) - Wall climb mantle, rooftop gap leap & roll, ridge balance, tile slide
├── UAL_AAA_Bending_Avatar.glb     (606 KB, 13 clips) - Avatar martial katas (Water Tai Chi, Earth Hung Gar, Fire Shaolin, Air Ba Gua)
├── UAL_AAA_Bending_Advanced.glb   (270 KB,  8 clips) - Air Scooter ride, shockwave blast, Earth wave surf, boulder toss, Fire jet dash
└── UAL_AAA_Bending_Mastery.glb    (278 KB,  7 clips) - Wing Chun punches, Muay Thai knee, Capoeira sweep, Lightning redirection
```

---

### A. Rooftop Parkour & City Traversal (`UAL_AAA_Traversal_Rooftops.glb` — 7 Clips)

| Clip Name | Movement Description | Loop | Calibrated Speed |
| :--- | :--- | :---: | :---: |
| `Wall_Climb_Mantle` | Jumping up to high stone wall or ledge and mantling to rooftop | No | One-shot |
| `Roof_Gap_Leap_Roll` | Athletic leap over rooftop alleyway with forward shoulder roll | No | 3.2 m/s |
| `Roof_Ridge_Balance_Walk`| Walking along narrow rooftop ridge / wooden beam with balance arms | Yes | 0.85 m/s |
| `Sloped_Roof_Tile_Slide` | Controlled boot slide down steep ceramic roof shingles | Yes | 3.5 m/s |
| `Ladder_Climb_Down_Loop` | Hand-over-hand continuous downward vertical ladder descent | Yes | 0.70 m/s |
| `Ledge_Shimmy_L` | Hanging from building ledge and shimmying horizontally to the left | Yes | 0.50 m/s |
| `Ledge_Shimmy_R` | Hanging from building ledge and shimmying horizontally to the right | Yes | 0.50 m/s |

---

### B. Knight & Assassin Specialization (`UAL_AAA_Combat_Classes.glb` — 9 Clips)

| Clip Name | Class | Movement Description | Loop |
| :--- | :--- | :--- | :---: |
| `Knight_Greatshield_Guard_Stance`| **Knight** | Upright, grounded stance holding greatshield locked at shoulder height | Yes |
| `Knight_Shield_Rush_Charge` | **Knight** | Full sprint charge driving shield forward to trample frontline lines | Yes |
| `Knight_Pommel_Strike_Stun` | **Knight** | Sudden upward sword pommel strike to the jaw for heavy stun | No |
| `Knight_Decapitation_Execution` | **Knight** | Heavy two-handed execution swing capitalizing on staggered foes | No |
| `Assassin_Shadow_Crouch_Creep` | **Assassin**| Low-profile stalking creep, silent foot placement | Yes |
| `Assassin_Throat_Slit_Sneak` | **Assassin**| Reaching around standing guard from behind and drawing blade across | No |
| `Assassin_Ledge_Pull_Down` | **Assassin**| Hanging below roof parapet, grabbing guard's boots, dragging off edge | No |
| `Assassin_Aerial_Drop_Impale` | **Assassin**| Plunging downward from rooftop or beam, driving dual blades into target | No |
| `Assassin_Smoke_Vanish_Drop` | **Assassin**| Dropping smoke bomb at feet and slipping into evasion roll | No |

---

### C. Chantless Arcane Magic (`UAL_AAA_Magic_Chantless.glb` — 6 Clips)

| Clip Name | Spell Category | Movement Description | Loop |
| :--- | :--- | :--- | :---: |
| `Cast_Chantless_Palm_Blast` | Force / Push | Instantaneous open-palm kinetic release hurling enemies back | No |
| `Cast_Chantless_Telekinesis_Lift`| Arcane Gravity | Raising both hands upward with splayed fingers levitating objects | No |
| `Cast_Chantless_Barrier_Conjure`| Abjuration | Thrusting dual hands forward summoning glowing arcane barrier | No |
| `Cast_Chantless_Ground_Eruption`| Geomancy | Stomping ground sending glowing magical fissure erupting forward | No |
| `Cast_Chantless_Siphon_Drain` | Necromancy / Dark | Reaching out open hand channeling continuous life/mana drain | Yes |
| `Cast_Chantless_Blink_Step` | Conjuration / Teleport| Instant dimensional slip step vanishing and reappearing forward | No |

---

### D. Martial Arts & Bending Mastery (`UAL_AAA_Bending_Mastery.glb` — 7 Clips)

| Clip Name | Discipline / Element | Movement Description | Loop |
| :--- | :--- | :--- | :---: |
| `Martial_WingChun_ChainPunch` | **Wing Chun Kung Fu** | High-cadence centerline rolling chain punches to the chest | No |
| `Martial_MuayThai_Knee_Thrust`| **Muay Thai** | Clinching opponent's head and driving upward knee into ribs | No |
| `Martial_Capoeira_Sweep_Kick` | **Capoeira** | Ground hand-plant 360° sweeping low crescent leg sweep | No |
| `Bending_Lightning_Redirection`| **Fire / Lightning** | Guiding incoming electrical strike through chi path and discharging | No |
| `Bending_Earth_Metal_Stomp` | **Earth / Metal** | Heavy grounded double stomp commanding metal and stone barriers | No |
| `Bending_Water_Whip_Flurry` | **Water** | Rapid 3-hit alternating liquid whip lacerations | No |
| `Bending_Air_Vortex_Vacuum` | **Air** | Swirling arms in a vortex drawing distant enemies inward | Yes |

---

### E. Realistic Combat Knockbacks (`UAL_AAA_Combat_Knockbacks.glb` — 4 Clips)

| Clip Name | Impact Type | Physics Description | Recovery |
| :--- | :--- | :--- | :---: |
| `Knockback_Heavy_Slide_Brake` | Heavy Ground Slide | Hurled back 2 meters, boots digging into stone to brake | 1.6s |
| `Knockback_Airborne_Blowback` | Explosive Blowback | Blown entirely off feet, flying through air landing hard on back | 2.0s |
| `Knockback_3Step_Stumble_Recoil`| Stumble Recoil | Taking 3 rapid backward stumbles fighting to regain balance | 1.6s |
| `Guard_Impact_Heavy_Stagger` | Guard Shockwave | Shield struck by colossal weapon; arms shoved wide open | 1.6s |

---

## 3. Drop-in Godot 4.6 Engine Wiring Recipe

Whenever you are ready to wire these into the gameplay scripts:

### In `kingdom/scripts/world/assets.gd`:

```gdscript
const UAL_FILES := [
    # Traversal & Locomotion
    UAL_ANIM_DIR + "aaa/UAL_AAA_Locomotion.glb",
    UAL_ANIM_DIR + "aaa/UAL_AAA_Traversal_Rooftops.glb",
    UAL_ANIM_DIR + "aaa/UAL_AAA_LivingWorld.glb",

    # Combat Systems & Classes
    UAL_ANIM_DIR + "aaa/UAL_AAA_Combat_Adv.glb",
    UAL_ANIM_DIR + "aaa/UAL_AAA_Combat_Chains.glb",
    UAL_ANIM_DIR + "aaa/UAL_AAA_Combat_Weapons.glb",
    UAL_ANIM_DIR + "aaa/UAL_AAA_Combat_Classes.glb",
    UAL_ANIM_DIR + "aaa/UAL_AAA_Combat_Reactions.glb",
    UAL_ANIM_DIR + "aaa/UAL_AAA_Combat_Knockbacks.glb",

    # Magic & Bending Systems
    UAL_ANIM_DIR + "aaa/UAL_AAA_Magic_Chantless.glb",
    UAL_ANIM_DIR + "aaa/UAL_AAA_Bending_Avatar.glb",
    UAL_ANIM_DIR + "aaa/UAL_AAA_Bending_Advanced.glb",
    UAL_ANIM_DIR + "aaa/UAL_AAA_Bending_Mastery.glb",
]

const UAL_ALIASES := {
    # Rooftop Parkour
    "Wall_Mantle": "Wall_Climb_Mantle",
    "Roof_Jump_Roll": "Roof_Gap_Leap_Roll",
    "Roof_Balance": "Roof_Ridge_Balance_Walk",
    "Roof_Slide": "Sloped_Roof_Tile_Slide",
    "Ladder_Down": "Ladder_Climb_Down_Loop",
    "Shimmy_L": "Ledge_Shimmy_L",
    "Shimmy_R": "Ledge_Shimmy_R",

    # Knight Archetype
    "Knight_Stance": "Knight_Greatshield_Guard_Stance",
    "Knight_Charge": "Knight_Shield_Rush_Charge",
    "Knight_Pommel": "Knight_Pommel_Strike_Stun",
    "Knight_Execute": "Knight_Decapitation_Execution",

    # Assassin Archetype
    "Assassin_Creep": "Assassin_Shadow_Crouch_Creep",
    "Assassin_Throat_Slit": "Assassin_Throat_Slit_Sneak",
    "Assassin_Ledge_Kill": "Assassin_Ledge_Pull_Down",
    "Assassin_Aerial_Kill": "Assassin_Aerial_Drop_Impale",
    "Assassin_Smoke": "Assassin_Smoke_Vanish_Drop",

    # Chantless Magic
    "Cast_Push": "Cast_Chantless_Palm_Blast",
    "Cast_Levitate": "Cast_Chantless_Telekinesis_Lift",
    "Cast_Barrier": "Cast_Chantless_Barrier_Conjure",
    "Cast_Eruption": "Cast_Chantless_Ground_Eruption",
    "Cast_Siphon": "Cast_Chantless_Siphon_Drain",
    "Cast_Blink": "Cast_Chantless_Blink_Step",

    # Martial Arts & Mastery
    "Wing_Chun": "Martial_WingChun_ChainPunch",
    "Muay_Thai_Knee": "Martial_MuayThai_Knee_Thrust",
    "Capoeira_Sweep": "Martial_Capoeira_Sweep_Kick",
    "Lightning_Redirect": "Bending_Lightning_Redirection",
    "Metal_Stomp": "Bending_Earth_Metal_Stomp",
    "Water_Flurry": "Bending_Water_Whip_Flurry",
    "Air_Vacuum": "Bending_Air_Vortex_Vacuum",

    # Natural Knockback Physics
    "Knockback_Slide": "Knockback_Heavy_Slide_Brake",
    "Knockback_Airborne": "Knockback_Airborne_Blowback",
    "Knockback_Stumble": "Knockback_3Step_Stumble_Recoil",
    "Guard_Stagger": "Guard_Impact_Heavy_Stagger",
}
```

---

## 4. Delivery Status

- **Branch:** `antigravity/aaa-mocap-animations`
- **Total Clips Delivered:** 136 AAA Mocap Clips across 13 Specialized Packages
- **Keyframe Footprint:** Compressed with Douglas-Peucker (< 5.5 MB for all 136 clips)
- **Claude's Workspace:** `claude/focused-curie-m09hbd` remains completely clean and untouched.
