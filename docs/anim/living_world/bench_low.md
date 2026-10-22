| tier | NPCs | main-thread process us / NPC | deferred + render-submit us / NPC | CPU total us / NPC | frame (wall) us / NPC | of which behaviour script | of which anim-LOD script |
|---|---:|---:|---:|---:|---:|---:|---:|
| NEAR full skeletal + look-at + behaviour | 40 | 28.7 | 38.2 | **67.0** | 68.0 | 3.5 | 2.0 |
| MID stepped skeletal + behaviour | 40 | 13.0 | 16.9 | **29.9** | 30.2 | 1.7 | 5.1 |
| FAR VAT twin (actor node kept) + behaviour | 40 | 6.3 | 0.7 | **6.9** | 7.6 | 0.4 | 4.3 |
| NEAR anim only | 40 | 33.4 | 21.7 | **55.1** | 56.4 | 0.0 | 2.2 |
| MID anim only | 40 | 15.1 | 13.7 | **28.8** | 29.4 | 0.0 | 4.8 |
| FAR anim only | 40 | 8.1 | 3.3 | **11.4** | 11.9 | 0.0 | 6.3 |
| data VAT (MultiMesh, no nodes) | 400 | 0.6 | -1.0 | **-0.5** | -0.4 | 0.0 | 0.0 |

Each row: best (lowest) of 3 paired runs of 240 frames with / without the NPCs; vsync off. Process = first to last _process of the frame (AnimationMixer + scripts); deferred = the rest of the main-thread frame (skeleton updates, render setup, GPU wait).
