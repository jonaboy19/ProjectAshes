"""Build the LOCAL-ONLY Sonniss sound set into kingdom/assets/audio/licensed_local/ (git-ignored).

The Sonniss #GameAudioGDC licence (https://sonniss.com/gdc-bundle-license/) allows these sounds in the game but forbids
redistributing the raw (or edited) files, and the repository is public: the WAVs stay in
Documents/ProjectAshes_art_staging/downloads/audio/sonniss/raw/ and the OGGs this script writes stay out of git.
The director prefers these over the CC0 set by name (audio_director.gd _prefer_licensed / LICENSED beds).

Same processing and loudness targets as tools/audio/build_audio.py (whose helpers this imports):
  one-shots   mono 44.1 kHz, trimmed / sliced, matched on max momentary loudness per group, peak <= -3 dBFS
  emitter loops (amb_forge, amb_walla_*, ...)  MONO (3D voices), seamless crossfaded loop, -24 LUFS integrated
  beds (amb_village_day, ...)                  stereo, seamless loop, -24 LUFS integrated
Run:  py tools/audio/build_licensed.py [name prefix]     (needs ffmpeg + numpy)
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_audio as B  # noqa: E402

RAW = Path(os.environ.get("SONNISS_RAW", r"C:\Users\Jonna\Documents\ProjectAshes_art_staging\downloads\audio\sonniss\raw"))
OUTDIR = "licensed_local/"
_files = None


def R(part: str) -> str:
    """Absolute path of the one raw WAV whose path contains `part`."""
    global _files
    if _files is None:
        _files = [p for p in RAW.rglob("*") if p.suffix.lower() == ".wav"]
    hits = [p for p in _files if part.lower() in p.as_posix().lower()]
    if len({h.name for h in hits}) > 1:      # "ring - 1" also matches "ring - 13": prefer the stem that ends with it
        hits = [h for h in hits if h.stem.lower().endswith(part.lower())] or hits
    if len({h.name for h in hits}) > 1:
        raise ValueError(f"{part!r} is ambiguous: {[h.name for h in hits]}")
    # the same file can sit in two bundle copies of a library ("Just Whoosh 3 _" / "p"): take either.
    # Not downloaded yet: the job fails at build time, the others still run.
    return str(hits[0]) if hits else "/missing/" + part


def dur(path: str) -> float:
    r = B.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", path])
    return float(r.stdout.decode().strip() or 0)


# ------------------------------------------------------------------------- recipes
JOBS: list[tuple] = []   # (kind, out, args)


def sliced(out, group, src, n, start=None, d=None, pitch=None, extra_db=0.0, first=21, **kw):
    """n events from one take -> out_<first>, out_<first+1> ... (one base name per sound, several sources)."""
    JOBS.append(("sliced", out, dict(group=group, src=src, n=n, start=start, dur=d, pitch=pitch, extra_db=extra_db, kw=kw,
                                     first=first)))


def one(out, group, src, start=None, d=None, pitch=None, extra_db=0.0, rel_db=-45.0):
    JOBS.append(("sfx", out, dict(group=group, src=src, start=start, dur=d, pitch=pitch, extra_db=extra_db, rel_db=rel_db)))


def loop(out, layers, length, mono=False, xfade=4.0, lufs=-24.0):
    JOBS.append(("amb", out, dict(layers=layers, length=length, mono=mono, xfade=xfade, lufs=lufs)))


def Ly(src, gain=0.0, start=None, d=None, af=None, off=7.0):
    return dict(src=src, gain=gain, start=start, dur=d, af=af, off=off)


def recipes() -> None:
    # --- footsteps (group footstep, -21 LUFS-M): numbered from 21 so they never shadow a CC0 file name
    sliced("sfx/footsteps/step_dirt", "footstep", R("PM_SDNG_Stereo_Walk_Seamless_Loop_1"), 8, max_len=0.6, post=0.18)
    one("sfx/footsteps/step_dirt_31", "footstep", R("PM_SDNG_Single_Step_Footstep_19"))
    one("sfx/footsteps/step_dirt_32", "footstep", R("PM_SDNG_Single_Step_Footstep_46"))
    sliced("sfx/footsteps/step_dirt", "footstep", R("FS Ground Civilian Walk N03"), 4, max_len=0.6, first=41)
    sliced("sfx/footsteps/step_cobble", "footstep", R("015_Foley_Footsteps_Asphalt_Boot"), 10, max_len=0.5, post=0.15)
    sliced("sfx/footsteps/step_stone", "footstep", R("FS Concrete Soldier Crouch N02"), 4, max_len=0.6)
    sliced("sfx/footsteps/step_stone", "footstep", R("FS Concrete Soldier Crouch N05"), 4, max_len=0.6, first=41)
    sliced("sfx/footsteps/step_grass", "footstep", R("169_Foley_Footsteps_Grass"), 10, max_len=0.6, post=0.18)
    sliced("sfx/footsteps/step_wood", "footstep", R("FS Wood Civilian Crouch N03"), 4, max_len=0.6)
    sliced("sfx/footsteps/step_wood", "footstep", R("FS Wood Civilian Crouch N05"), 4, max_len=0.6, first=41)
    sliced("sfx/footsteps/step_leaves", "footstep", R("FX3280 Walking Faster Leaves"), 10, max_len=0.6, post=0.15)
    sliced("sfx/footsteps/step_scuff", "footstep", R("289_Foley_Footsteps_Rocks"), 3, max_len=0.8, extra_db=2.0)
    # --- movement foley (group foley, -18)
    one("sfx/foley/foley_gear_21", "foley", R("foley_soldier_gear_equipment"))
    sliced("sfx/foley/foley_gear", "foley", R("PR ARMY GEAR ROOM_WALK"), 6, max_len=0.9)
    sliced("sfx/foley/foley_gear", "foley", R("PR CHAINS_SCRAPE"), 3, max_len=1.0, extra_db=-3.0, first=41)
    one("sfx/foley/foley_gear_31", "foley", R("LeatherArmor_Rustle_03"))
    sliced("sfx/foley/foley_cloth", "foley", R("Cloth 29"), 4, max_len=2.0, rel_db=-20.0)
    sliced("sfx/foley/foley_cloth", "foley", R("Cloth 61"), 4, max_len=2.0, rel_db=-20.0, first=41)
    # --- combat (group combat, -14)
    for i, k in enumerate(["metal knife swing - 4", "metal knife swing - 5", "metal knife swing - 17"]):
        one(f"sfx/combat/whoosh_light_{21 + i}", "combat", R(k), pitch=0.84, extra_db=-3.0)
        one(f"sfx/combat/whoosh_heavy_{21 + i}", "combat", R(k), pitch=0.7, extra_db=-1.0)
    one("sfx/combat/whoosh_light_24", "combat", R("whoosh_weapon_knife_swing_04"), pitch=0.85, extra_db=-3.0)
    sliced("sfx/combat/whoosh_light", "combat", R("ROPE WHOOSH Fast Light"), 3, max_len=0.8, pitch=0.9, extra_db=-3.0, first=41)
    one("sfx/combat/whoosh_heavy_24", "combat", R("Whoosh_Cloth_Leather_Fight_174"))
    one("sfx/combat/whoosh_heavy_25", "combat", R("Whoosh,Organic,Fabric,Glove"), pitch=0.85)
    for i, k in enumerate(["wet stab slash and remove from flesh - hard - 1", "wet stab slash and remove from flesh - hard - 4",
                           "wet stab slash and remove from flesh - medium - 14", "wet impact in to flesh and removed - 6"]):
        one(f"sfx/combat/hit_blade_flesh_{21 + i}", "combat", R(k), d=0.7, extra_db=-1.0)
    one("sfx/combat/hit_body_21", "combat", R("Deep Punch 02"), pitch=0.85)
    one("sfx/combat/hit_body_22", "combat", R("punch_general_body_impact_03"), pitch=0.8)
    one("sfx/combat/hit_body_23", "combat", R("punch_blocked_02"), pitch=0.85)
    sliced("sfx/combat/hit_leather", "combat", R("FLOG Leather Hit Smack"), 4, max_len=0.7)
    one("sfx/combat/hit_armor_metal_21", "combat", R("Plate_Impact_Hard_02"))
    one("sfx/combat/hit_armor_metal_22", "combat", R("Chainmail_Impact_Hard_03"))
    one("sfx/combat/hit_armor_metal_23", "combat", R("Metal plate bang 01"), d=1.2)
    one("sfx/combat/hit_armor_metal_24", "combat", R("heavy_metal_impact_metal_plate_medium"), d=1.2)
    one("sfx/combat/clash_steel_21", "combat", R("Weapon_Impact_Parry_01"))
    sliced("sfx/combat/clash_steel", "combat", R("Knife_Sword_Hit_Multiple"), 3, max_len=1.2, post=0.3, first=41)
    one("sfx/combat/clash_steel_31", "combat", R("Knife_Sword_Shing"))
    one("sfx/combat/blade_ring_21", "combat", R("large metal knife ring - 8"), extra_db=-4.0)
    one("sfx/combat/blade_ring_22", "combat", R("large metal knife muted ring - 1"), extra_db=-4.0)
    one("sfx/combat/blade_ring_23", "combat", R("Sword Ring Scrape Gleam 02"), d=1.6, extra_db=-4.0)
    one("sfx/combat/block_wood_21", "combat", R("Impacts Hard - Short Wobbly Tail 01"))
    one("sfx/combat/block_wood_22", "combat", R("Impacts Soft - Short, Crack"))
    one("sfx/combat/block_wood_23", "combat", R("STICK HIT-07 - DEFEND"), pitch=0.8)
    one("sfx/combat/block_wood_24", "combat", R("STICK HIT-13 - WILD"), pitch=0.8)
    one("sfx/combat/block_wood_25", "combat", R("WOODEN SWORD HIT-11"), pitch=0.75)
    one("sfx/combat/guard_break_21", "combat", R("Impacts Hard - Short Wobbly Tail 01"), pitch=0.72, extra_db=2.0)
    one("sfx/combat/body_fall_21", "combat", R("Body Slam Floor 08"), extra_db=-2.0)
    one("sfx/combat/sword_draw_21", "combat", R("Sword Slide Swish"), extra_db=-4.0)
    one("sfx/combat/sword_draw_22", "combat", R("Knife_Sword_Shing"), pitch=0.9, extra_db=-4.0)
    # --- world one-shots
    sliced("sfx/world/anvil_strike", "foley", R("Anvil hits - Tree hits"), 8, max_len=1.4, post=0.5)
    one("sfx/world/anvil_strike_31", "foley", R("hammer,anvil,strike,loose"))
    one("sfx/world/door_open_21", "foley", R("Door - Medieval Open 16"), d=2.5)
    one("sfx/world/door_close_21", "foley", R("door_big_close_001"))
    one("sfx/animals/horse_snort_21", "animal", R("HORSES - Snort 03"))
    one("sfx/animals/horse_neigh_21", "animal", R("HORSES - Whinny distant 01"))
    sliced("sfx/animals/cow", "animal", R("Cow moo, variety"), 3, max_len=3.0, post=0.4)
    # --- positional emitter loops (mono, soundscape.gd)
    loop("ambience/loops/amb_forge", [Ly(R("Bellows - Fire, oven accent"), 0.0, 36.0, 34.0), Ly(R("lighthammer,anvil,hotiron"), -12.0)], 30.0, mono=True)
    loop("ambience/loops/amb_walla_market", [Ly(R("CHIL Market Village"), 0.0, 30.0), Ly(R("Unrest Murmur 01"), -7.0, 10.0),
                                             Ly(R("Village medium in a canyon"), -8.0, 20.0)], 50.0, mono=True)
    loop("ambience/loops/amb_walla_tavern", [Ly(R("RA_06_Restaurant_Dinner"), 0.0, 40.0), Ly(R("sm-fire-firewood-small-03"), -10.0)], 45.0, mono=True)
    loop("ambience/loops/amb_well", [Ly(R("water river Guber small stream"), 0.0, 15.0, af="highpass=f=300")], 30.0, mono=True)
    loop("ambience/loops/amb_fire_small", [Ly(R("sm-fire-firewood-small-03"), 0.0)], 30.0, mono=True)
    loop("ambience/loops/amb_campfire", [Ly(R("sm-fire-cotton-02"), 0.0, 5.0), Ly(R("sm-fire-firewood-small-03"), -4.0)], 40.0, mono=True)
    loop("ambience/loops/loop_cart", [Ly(R("HORSES - Walking on stone 03")), Ly(R("wood_creaking_tree_005"), -6.0)], 24.0, mono=True, xfade=2.0)
    # --- beds (stereo; override the CC0 beds of the same name)
    loop("ambience/amb_village_day", [Ly(R("countryside bird morning chorus"), 0.0, 30.0), Ly(R("Rural background, birdsong"), -6.0),
                                      Ly(R("Unrest Murmur 01"), -16.0, 40.0)], 60.0)
    loop("ambience/amb_meadow_day", [Ly(R("Amb_Countryside_Day_Flying_Insects"), 0.0, 10.0), Ly(R("Breeze,Grass,Tall"), -7.0, 20.0)], 60.0)
    loop("ambience/amb_forest_day", [Ly(R("wind robin blackbird"), 0.0, 20.0), Ly(R("soft wind chaffinch"), -5.0, 10.0)], 60.0)
    loop("ambience/amb_forest_night", [Ly(R("05 Crickets_owls"), 0.0, 30.0)], 60.0)
    loop("ambience/amb_village_night", [Ly(R("Amb_Countryside_Night_Birds_Cow_Cricket"), 0.0, 40.0), Ly(R("05 Crickets_owls"), -6.0, 90.0)], 60.0)
    loop("ambience/amb_tavern", [Ly(R("RA_06_Restaurant_Dinner"), 0.0, 120.0), Ly(R("sm-fire-cotton-02"), -9.0)], 50.0)
    loop("ambience/amb_camp", [Ly(R("sm-fire-cotton-02"), 0.0, 20.0), Ly(R("Gust,Grasslands"), -8.0, 30.0)], 45.0)
    loop("ambience/amb_wind", [Ly(R("Gust,Grasslands"), 0.0, 60.0)], 55.0)
    loop("ambience/amb_creek", [Ly(R("Calm small river flow"), 0.0, 5.0), Ly(R("Rural background, birdsong"), -8.0)], 55.0)
    loop("ambience/amb_rain", [Ly(R("RATH - Rain Hard Loop 08"), -2.0)], 40.0)
    loop("ambience/amb_storm", [Ly(R("RATH - Rain Hard Loop 08"), 0.0), Ly(R("RATH - Rain and Distant Thunder Loop 01"), -3.0, 10.0)], 40.0)


# ------------------------------------------------------------------------- build
def tile(x: np.ndarray, n: int, edge: float = 1.0, xf: float = 2.5) -> np.ndarray:
    """Repeat a recording to n frames without the drop-outs B.fit leaves: the recorder's own fade-in / fade-out
    (`edge` s at each end) is cut first, and the copies meet in `xf` s equal-power crossfades."""
    e = int(edge * B.SR)
    if len(x) > 4 * e:
        x = x[e:-e]
    if len(x) >= n:
        return x[:n]
    X = min(int(xf * B.SR), len(x) // 3)
    t = np.linspace(0, 1, X)[:, None]
    out = x.copy()
    while len(out) < n:
        out = np.concatenate([out[:-X], out[-X:] * np.sqrt(1 - t) + x[:X] * np.sqrt(t), x[X:]])
    return out[:n]


def build_loop(a: dict) -> np.ndarray:
    need = a["length"] + a["xfade"]
    parts = []
    for ly in a["layers"]:
        avail = dur(ly["src"]) - (ly["start"] or 0.0)
        ly_d = ly["dur"] or min(avail, need + 30.0)
        x = B.decode(ly["src"], B.channels(ly["src"]), B.SR, ly["start"], ly_d, ly["af"])
        parts.append((tile(B.to_stereo(x, ly["off"]), int(need * B.SR)), ly["gain"]))
    mix = B.layer(parts, int(need * B.SR))
    if a["mono"]:
        mix = mix.mean(axis=1, keepdims=True)
    mix = B.compress(mix)
    lp = B.make_loop(mix, a["length"], a["xfade"])
    lp, _ = B.normalise_integrated(lp, a["lufs"])
    return lp


def main(prefix: str = "") -> None:
    recipes()
    ok = err = 0
    for kind, out, a in JOBS:
        if not out.startswith(prefix):
            continue
        try:
            if kind == "amb":
                B.encode(build_loop(a), OUTDIR + out, B.SR, q=4, limit_db=-3.4)
            else:
                first = a.pop("first", 21)
                e = dict(type=kind, out=OUTDIR + out, sr=B.SR, af=None, **a)
                a["first"] = first
                for i, (name, y, sr) in enumerate(B.build_sfx_like(e)):
                    if kind == "sliced":
                        name = f"{OUTDIR + out}_{first + i:02d}"
                    B.encode(y, name, sr, q=4, limit_db=-3.4)
            ok += 1
            print("ok ", out, flush=True)
        except Exception as ex:  # keep going, report at the end
            err += 1
            print("ERR", out, ex, flush=True)
    tot = sum(p.stat().st_size for p in (B.OUT / OUTDIR).rglob("*.ogg"))
    n = len(list((B.OUT / OUTDIR).rglob("*.ogg")))
    print(f"{ok} ok, {err} errors; licensed_local: {n} files, {tot / 1048576:.1f} MB")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "")
