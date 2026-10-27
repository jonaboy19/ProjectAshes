# Benchmark slice — visual issues per lane (video QA)

Route: `tools/qa/video/record_slice.sh` (bot stage `slice_route`, Movie Maker 1280x720 30 fps, 11:00, quality LOW).
Each entry: recording, timestamp, what is wrong, owner lane.

## Recording slice_2026-10-27_0727_f5437f344_low (sheets docs/qa/video/slice/0727_low/)
Config the owner gets (sidecar .txt): forward_plus, tier LOW (scale 0.75 FSR1, no SDFGI/SSAO/SSR, fog on), **terrain3d=false** (legacy noise ground: the bot/Play Game path passes no terrain flags).

| t | issue | lane |
|---|---|---|
| 3.0-3.5 s | HUD (quest popups, minimap, "Steward" nameplate) visible for the first frames before the bot hides it; world-space labels ("Adventurer Guild", "Notice Board", "Market Trader", "Ashford Inn") stay on during the whole street walk: UI restraint fails | towns (in-town markers) / player (HUD) |
| 19-46 s | player shield on the back: a large flat brown slab with a pink blob, no texture (flat-colour prop) | player |
| 26.5-30 s | conversation segment: the camera ends inside NPC heads (faces fill the frame) - route standpoint too close (video QA, fixing) and the follow camera does not avoid characters | video QA (route) / player (camera collision vs NPCs) |
| 31-36 s | "house" segment teleports inside a building frame (camera in the walls, hayloft beams): route used the lot centre, not the door (video QA, fixing) | video QA |
| 37-46 s | "countryside" segment is still Ashford main street (town radius smaller than the built area): no field wall / copse / camp reached (video QA, fixing) | video QA |
| HIGH | Movie Maker at --quality=high crashes (signal 11) right after the first frames with "BUG, indexing did not unpair geometries from light"; LOW records fine. Without --write-movie HIGH runs the whole route. | world/lighting (SDFGI + movie) |
