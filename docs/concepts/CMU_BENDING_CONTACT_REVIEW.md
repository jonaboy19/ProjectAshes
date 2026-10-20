# CMU bending contact-sheet review

Base: 84e716eb. Reviewed 2026-10-05: front_sheet_00 and side_sheet_00 through side_sheet_03, plus the existing 36-row clips JSON. These are Claude's captures, not a new runtime recording. Sparse images support pose selection, not exact contact frames, continuous floor contact or clothing acceptance.

## First candidates

| Clip | Visible motion | Candidate use | Required integration |
|---|---|---|---|
| Earth_Lunge_R/L | Step into low stance, raised striking arm, return upright | Deliberate earth release | Full-body playback, contact measurement, recovery to stance |
| Earth_PunchSeq_Deep | Compact repeated guarded arm extension | Short earth combination | Individual strike events; do not use one damage event for several punches |
| Fire_Box_Combo_B | Short guarded punch sequence | Fire combo variant | Contact events and body travel; not a generic single jab |
| Water_SpinReach_L | Turn and extend arms, recover | Water redirect or wall | Direction/aim policy through the turn, measured release |
| Water_Dance_ArmsHigh | Gradual upward arm sweep, finish overhead | Charged water gathering | Charge/release transition; not the current 0.25-second Water Whip |

## Moves needing controller work

- Air_Evade_L/R: multiple running strides, not short rolls. Metadata travel is 4.00/3.42 metres. Disabling root travel alone makes the strides stationary. A dash needs collision-owned travel sampled from the clip.
- Air_Duck_Weave_L: lateral duck into travel; metadata travel 2.02 metres, minimum foot -0.06 metres. Needs collision path and floor review.
- Air_Handspring_Evade: hands touch the ground; travel 2.08 metres. Requires full-body action and hand/ground clearance.
- Air_Jump_Kick: launch, leg extension and landing; travel 2.19 metres, minimum foot -0.06 metres. Needs airborne movement and landing ownership, not an upper-body cast.
- Air_SpinJump_360, Air_Jump_Twist, Fire_Aerial_Flip: aerial poses require jump/landing integration. Do not add merely as a grounded attack preference.
- Cultivate_Yoga_Floor_Flow: hands-on-floor, prone and raised-hip poses. Needs explicit entry/exit and ground clearance; not standing breath circulation.

## Cleanup / unsuitable direct substitutions

- Earth_Punch_Hold_Deep ends low. Claude suggests trim at 4.6 seconds; do not assume that produces a neutral recovery without preview.
- Water_Lean_Sway_A/B and Water_Whirl visibly read as broad dance gestures. Keep as training/flow candidates until action-specific direction is authored.
- Lightning_Point_Snap is a broad pointing sequence. Lightning_Punch_Snap is compact but still a placeholder; neither is approved as final lightning action.
- Guard_Ready_Defensive moves into a crouched guard. It is not a clean looping sword/shield guard replacement.
- Fire_Stride_Strike_F visibly steps forward and has 1.04 metres travel in metadata. It needs capsule travel; Claude also flags floor cleanup.
- Fire_Box_Combo_A and Water_Whirl retain Claude's floor-cleanup warning. Metadata and sparse images do not disprove that warning.

## Timing contract

Current bn_water_whip, bn_stone_fist and bn_flame_jab have 0.25-second windups. The candidate clips last 1.4 to several seconds. A name-only preference replacement would desynchronize animation and damage. Measure contact, decide playback speed, and set windup/recovery from the chosen motion. Missing-library fallback must retain its own compatible timing. No candidate is mapped into live technique data yet.

Do not treat this review as phone performance or runtime acceptance. No tests or game runs were performed.
