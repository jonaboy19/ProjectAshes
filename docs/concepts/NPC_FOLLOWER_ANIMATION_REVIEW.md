# Near-NPC follower and gait-state review

**Status:** source-level diagnosis with an interactive arithmetic model; game code was not changed.  
**Gameplay source checked:** `claude/focused-curie-m09hbd` at `e3563fc4`.  
**Related current evidence:** the local autoplay HUD reports 5,280 total simulated souls; see the [current screenshot review](CURRENT_RUN_VISUAL_REVIEW.md). Refresh that number after future world-generation changes.

Open [NPC_FOLLOWER_ANIMATION_REVIEW.html](NPC_FOLLOWER_ANIMATION_REVIEW.html), choose population and frame rate, then run the short trace. It models the source update cadence and shows how often the full villager selects `Walking_A` versus `Idle` while the simulation moves.

## What the source does

`WorldSim._simulate_slice()` advances at most 1,500 population rows per rendered process frame. A resident's row is revisited once the cursor cycles around the full population. With 5,280 residents, the average revisit cadence is 5,280 / 1,500 = 3.52 rendered frames. At 60 FPS, an average visit moves the data position about 1.3 × 3.52 / 60 = 0.076 m; individual intervals alternate around three and four frames.

`Villager._process()` follows that data position every frame at 1.6 m/s, but selects `Walking_A` only when the current body-to-data gap is greater than 0.15 m. Because 1.6 m/s is faster than the data simulation's 1.3 m/s, the full body can close each small update pulse before the next one. At 5,280 residents and 60 FPS, both three- and four-frame data steps are less than 0.15 m, so the source conditions allow the character to move while the animation state remains `Idle`. At lower frame rates or larger populations, some pulses cross 0.15 m and can trigger brief walk/idle changes instead. This makes the gait decision depend on population size and frame rate rather than simply on sustained travel.

This is a source-derived, falsifiable risk, not a claim that a video has already proven every active full NPC is idle while moving. Frame order, animation crossfade, target distance, catch-up mode, and additional time spent away from the data position affect the visible result. Capture one resident's actual `WorldSim.pos` delta, body delta, gap, selected clip, and playback speed to confirm it in game.

## The same follower still cannot solve collision

The full villager is a `Node3D`; it chases the simulation's direct position and has no body collision or navigation. `WorldSim` itself moves each population row toward the selected goal in a straight line. A smoother follower curve can improve presentation but cannot route around a Meshy wall or prevent player/NPC penetration. Those require a reachable route and a physical near-body controller, as specified in the [NPC life-loop design](NPC_LIFE_LOOP_DESIGN.md).

There is a second frame-rate-dependent detail: `rotation.y` is eased with `lerp_angle(..., 0.15)` once per rendered frame. A constant per-frame interpolation factor turns faster in wall-clock time at higher FPS. The game should use a delta-aware exponential factor or a bounded turn rate, then compare the same turn capture at LOW and HIGH frame rates.

`_play()` crossfades with a fixed 0.2-second blend. At the inspected population and 60 FPS, that is over three times the average row-revisit interval (~0.059 seconds). If the gait threshold is crossed at lower frame rates or larger populations, rapid walk/idle state changes can interrupt one another before the blend settles.

## Recommended implementation direction for Claude

1. Add a QA trace for one travelling full villager at 30, 60, and uncapped FPS. Log time, simulation position, resolved body position, body-to-data gap, body velocity, chosen animation, and animation playback scale.
2. Drive locomotion state and playback rate from the **resolved body velocity**, with separate enter/exit thresholds or a short state hold to avoid idle/walk chatter. Use the animation QA's measured per-rig clip ground speeds; do not infer walking from lag behind a simulation point.
3. Make visible travel continuous between low-detail simulation updates, either by interpolating timestamped simulation samples or by transferring movement ownership to the near physics actor and reporting its resolved position back at explicit handoffs. Do not let both tiers integrate the same actor.
4. Make turning delta-aware and cap angular speed; compare turn-in-place, start, stop, and route-corner footage at different render rates.
5. Keep routing/collision as a separate acceptance gate. The near body must still use safe paths and physical world/player collision; animation smoothness is not a substitute.

## Acceptance evidence

- A resident travelling steadily plays a locomotion clip instead of standing idle, at 30/60 FPS and at the actual current population.
- A resident who stops transitions to idle once, without repeated clip restarts during simulation position updates.
- Measured character ground speed and chosen clip playback speed match the animation QA band across each rig family.
- Turn duration in seconds stays within the same authored range at 30 and 60 FPS.
- A separate collision/path test confirms the same resident routes around a solid building and cannot pass through the player.

## Source map

- `kingdom/autoload/world_sim.gd`: `UPDATES_PER_FRAME`, `WALK_SPEED`, `_simulate_slice()` and `_cursor` cadence.
- `kingdom/scripts/population/villager.gd`: per-frame follow speed, 0.15 m animation-state threshold, and per-frame turn interpolation.
- `kingdom/scripts/population/population_lod.gd`: the representation budget and near model promotion.
- `docs/qa/anim_qa_report.md` in Claude's active local checkout: measured per-rig motion and playback-speed findings; it remains Claude's current animation QA work.
