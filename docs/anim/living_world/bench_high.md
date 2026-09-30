| tier | NPCs | main-thread process us / NPC | deferred + render-submit us / NPC | CPU total us / NPC | frame (wall) us / NPC | of which behaviour script | of which anim-LOD script |
|---|---:|---:|---:|---:|---:|---:|---:|
| NEAR full skeletal + look-at + behaviour | 40 | 31.2 | 39.5 | **70.6** | 71.5 | 2.5 | 1.8 |
| MID stepped skeletal + behaviour | 40 | 18.5 | 16.6 | **35.1** | 35.8 | 0.7 | 3.8 |
| FAR VAT twin (actor node kept) + behaviour | 40 | 6.2 | -2.5 | **3.7** | 4.2 | 0.5 | 5.2 |
| NEAR anim only | 40 | 33.6 | 31.2 | **64.8** | 66.1 | 0.0 | 1.7 |
| MID anim only | 40 | 21.4 | 14.2 | **35.6** | 36.5 | 0.0 | 3.9 |
| FAR anim only | 40 | 5.6 | -5.2 | **0.3** | 0.2 | 0.0 | 5.0 |
| data VAT (MultiMesh, no nodes) | 400 | 0.4 | -2.0 | **-1.6** | -1.6 | 0.0 | 0.0 |

Each row: best (lowest) of 3 paired runs of 240 frames with / without the NPCs; vsync off. Process = first to last _process of the frame (AnimationMixer + scripts); deferred = the rest of the main-thread frame (skeleton updates, render setup, GPU wait).
