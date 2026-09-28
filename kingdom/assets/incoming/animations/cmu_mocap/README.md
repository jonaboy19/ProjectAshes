# CMU mocap: karate, tai chi, swordplay, swimming, chores, lying down

`UAL_CMU_Mocap.glb`: **23 clips, 255 s**, retargeted from 20 BVH takes of the CMU Graphics
Lab Motion Capture Database onto the Quaternius **UAL 65-bone skeleton**. Registered in
`Assets.UAL_FILES`. 2.0 MB. Details of each clip are in `UAL_CMU_Mocap.glb.clips.json`.

| | |
|---|---|
| Source | http://mocap.cs.cmu.edu/ via the BVH conversion by Bruce Hahne (cgspeed), mirrored at https://github.com/una-dinosauria/cmu-mocap |
| Licence | CMU: "free for use in research and commercial projects worldwide"; Hahne adds no restrictions. Terms are copied verbatim in `LICENSE`. These are the same terms as the accepted Mesh2Motion CMU clips |
| Credit | "Motion capture data from the CMU Graphics Lab Motion Capture Database (mocap.cs.cmu.edu), created with funding from NSF EIA-0196217." (in CREDITS.md) |
| Raw data | not committed; `tools/anim/fetch_sources.sh` downloads exactly these takes |

Clean-up applied (`tools/anim/retarget_clips_to_ual.py`):
- 120 fps data is lightly Gaussian-smoothed (σ 10–30 ms), then resampled to 30 fps.
- Techniques are trimmed to one repetition, and still heads and tails of kata and swordplay are trimmed.
- Clips are in place: travel goes on the optional `root` track.
- A floor fix plants the lowest foot.
- A contact lift keeps knees, hands and head above the floor in the lying and get-up clips.
- Loop clips get the best loop points plus a crossfade.
- Constant finger poses are taken from UAL clips (mocap has no fingers): fists for karate and swordplay, relaxed hands otherwise, flat hands for shuto-uke and swimming.
- Douglas-Peucker key reduction is applied (0.35°, 2 mm).

| clip | s | loop | source take (CMU index name), trim |
|---|---:|---|---|
| `Karate_Mae_Geri` | 1.70 |  | 135_04 "Front Kick", 2.6–4.3 s (right front kick) |
| `Karate_Mawashi_Geri` | 1.80 |  | 135_07 "Mawashigeri", 0.4–2.2 s (right roundhouse) |
| `Karate_Yoko_Geri` | 2.20 |  | 135_11 "Yokogeri", 2.2–4.4 s (right side kick) |
| `Karate_Oi_Zuki` | 2.00 |  | 135_09 "Oiduki", 1.9–3.9 s (stepping punch) |
| `Karate_Gedan_Barai` | 1.90 |  | 135_05 "Gedanbarai", 0.5–2.4 s (low block) |
| `Karate_Shuto_Uke` | 1.80 |  | 135_10 "Syutouuke", 1.5–3.3 s (knife-hand block) |
| `Kata_Heian_Shodan` | 24.47 |  | 135_06 "Heiansyodan", whole kata |
| `Kata_Bassai` | 50.03 |  | 135_01 "Bassai", whole kata |
| `Kata_Empi` | 40.40 |  | 135_02 "Empi", whole kata |
| `Taichi_Idle` | 12.70 | loop | 12_04 "tai chi", 5–21 s (the opening "commencement": arms rise and sink, feet planted); **cultivation / meditation idle** |
| `Taichi_Form` | 40.00 |  | 12_04, 21–61 s (flowing form, for a training scene) |
| `Swordplay_A` | 18.43 |  | 02_07 "swordplay" |
| `Swordplay_B` | 12.20 |  | 02_08 "swordplay" |
| `Swordplay_C` | 8.30 |  | 02_09 "swordplay" |
| `Swim_Breaststroke` | 4.77 | loop | 125_01 "Breast Stroke", 8–16 s |
| `Swim_Freestyle` | 5.00 | loop | 125_06 "Free Style", 12–22 s |
| `Swim_Backstroke` | 5.23 | loop | 126_01 "Back Stroke", 4–14 s |
| `Chore_Sweep` | 1.73 | loop | 143_28 "Sweeping, Push Broom", 0.4–4.2 s (walking push-broom cycle) |
| `Chore_Stool_Sit_Stand` | 3.80 |  | 143_19 "Sit On Stool And Get Up", 0.5–4.3 s (stool seat ~0.45 m) |
| `Chore_Pick_Up_Box` | 2.40 |  | 143_11 "Walk And Pick up Box", 1.2–3.6 s |
| `Lie_Down` | 5.70 |  | 113_08 "Lay down and get up", 0.3–6.0 s |
| `Lie_Down_Idle` | 2.43 | loop | 113_08, 5.5–9.3 s (lying on the back) |
| `Lie_Down_Get_Up` | 6.00 |  | 113_08, 9.0–15.0 s |

Notes
- The swim takes were captured lying on a bench, so the body is horizontal with the hips
  about 0.6 m above the character origin. Place the character at the water surface minus
  about 0.6 m (or offset the model) while swimming.
- 111_12 "Lay down" was tried and dropped: its knee markers flip, the shin goes 21 cm
  into the floor and the knee bends 170°. All three lie-down clips come from the clean
  113_08 take.
- The kata and swordplay clips turn the body (yaw is kept); the character ends facing
  another direction. Use them as performances or cut-scenes, not as looping idles.
