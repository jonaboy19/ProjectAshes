"""Build the game-ready audio set for Rising Ashes (kingdom/assets/audio/).

Reads the licence-checked source packs under kingdom/assets/incoming/ (see
kingdom/assets/audio/README.md for every source, licence and credit), then per sound:
decode -> trim / slice / pitch / layer -> seamless loop (ambience beds) ->
loudness-normalise -> OGG Vorbis. Finally measures every output with ffmpeg's EBU R128
meter and writes kingdom/assets/audio/loudness.csv.

Targets (mobile):
  music     stereo 44.1 kHz, q4, integrated -18 LUFS, true peak <= -1 dBTP
  ambience  stereo 44.1 kHz, q4, integrated -24 LUFS, crossfaded loop point
  sfx       mono, 44.1 kHz (creatures/animals 32 kHz), q4, silence trimmed,
            loudness matched per group on max momentary loudness, peak <= -3 dBFS

Needs ffmpeg/ffprobe on PATH and Python 3 with numpy.
Run:  py tools/audio/build_audio.py            (everything)
      py tools/audio/build_audio.py sfx/ui     (only outputs whose path starts with it)
"""
from __future__ import annotations

import csv
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
IN = ROOT / "kingdom/assets/incoming"
OUT = ROOT / "kingdom/assets/audio"
SR = 44100
TMP = Path(tempfile.gettempdir()) / "ashes_audio_build"
TMP.mkdir(exist_ok=True)

BSB = "audio/bigsoundbank/"          # new BigSoundBank downloads (this pass)
BSB0 = "bigsoundbank/"               # BigSoundBank files already in the repo
OGA = "opengameart/"
RD = OGA + "sfx/80-creature-rubberduck/"
RD1 = OGA + "sfx/100-sfx-rubberduck/"
RDW = OGA + "sfx/100-wood-metal-rubberduck/"
ART = OGA + "sfx/rpg-sound-pack-artisticdude/RPG Sound Pack/"
LRSF = OGA + "cc-by/fantasy-sound-library-littlerobotsoundfactory/Fantasy Sound Library/Mp3/"
KI = "kenney/impact-sounds/Audio/"
KR = "kenney/rpg-audio/Audio/"
KU = "kenney/interface-sounds/Audio/"
KUA = "kenney/ui-audio/Audio/"
KJ = "kenney/music-jingles/Audio/"
VOX = OGA + "sfx/voice-clip-pack-male-adventurer-rpg/RPG Male Adventurer/"
CB = OGA + "cc-by/footsteps-congusbongus/footsteps/"

# Loudness targets for one-shots: max momentary loudness (LUFS) per group.
SFX_TARGET = {
    "combat": -14.0, "creature": -14.0, "voice": -16.0, "animal": -17.0, "foley": -18.0,
    "spot": -20.0, "footstep": -21.0, "ui": -19.0, "jingle": -16.0,
}
SFX_PEAK_DB = -3.4


# ----------------------------------------------------------------------------- io
def run(cmd: list[str], data: bytes | None = None) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, input=data, capture_output=True, check=False)


def decode(src: str, ch: int = 1, sr: int = SR, start: float | None = None,
           dur: float | None = None, af: str | None = None) -> np.ndarray:
    """Decode (a part of) a source file to float32 frames x channels."""
    path = src if os.path.isabs(src) or src.startswith("anoisesrc") else str(IN / src)
    cmd = ["ffmpeg", "-v", "error"]
    if start:
        cmd += ["-ss", str(start)]
    if dur:
        cmd += ["-t", str(dur)]
    if src.startswith("anoisesrc"):
        cmd += ["-f", "lavfi", "-i", src]
    else:
        if not Path(path).exists():
            raise FileNotFoundError(path)
        cmd += ["-i", path]
    filters = ["aresample=%d" % sr]
    if af:
        filters.append(af)
    cmd += ["-af", ",".join(filters), "-f", "f32le", "-ac", str(ch), "-ar", str(sr), "-"]
    r = run(cmd)
    if r.returncode != 0:
        raise RuntimeError(f"decode failed {src}: {r.stderr.decode(errors='ignore')[-400:]}")
    return np.frombuffer(r.stdout, dtype=np.float32).reshape(-1, ch).copy()


def channels(src: str) -> int:
    r = run(["ffprobe", "-v", "error", "-select_streams", "a:0", "-show_entries", "stream=channels",
             "-of", "csv=p=0", str(IN / src)])
    return 2 if r.stdout.decode().strip().startswith("2") else 1


def pitch_af(f: float) -> str:
    """Varispeed pitch (and length) change: f < 1 = lower and slower (bigger creature)."""
    return f"asetrate={int(SR * f)},aresample={SR}"


def measure(x: np.ndarray, sr: int) -> dict:
    """EBU R128 via ffmpeg: integrated, max momentary, true peak."""
    ch = x.shape[1]
    r = run(["ffmpeg", "-v", "info", "-nostats", "-f", "f32le", "-ar", str(sr), "-ac", str(ch), "-i", "-",
             "-af", "apad=pad_dur=0.6,ebur128=peak=true:framelog=info", "-f", "null", "-"], x.astype(np.float32).tobytes())
    return parse_ebur(r.stderr.decode(errors="ignore"))


def measure_file(path: Path) -> dict:
    r = run(["ffmpeg", "-v", "info", "-nostats", "-i", str(path),
             "-af", "apad=pad_dur=0.6,ebur128=peak=true:framelog=info", "-f", "null", "-"])
    return parse_ebur(r.stderr.decode(errors="ignore"))


def parse_ebur(txt: str) -> dict:
    ms = [float(m) for m in re.findall(r"M:\s*(-?[\d.]+|-inf)", txt) if m != "-inf"]
    summ = txt[txt.rfind("Summary:"):] if "Summary:" in txt else txt
    i = re.search(r"I:\s*(-?[\d.]+|-inf) LUFS", summ)
    lra = re.search(r"LRA:\s*(-?[\d.]+) LU", summ)
    pk = re.search(r"Peak:\s*(-?[\d.]+|-inf) dBFS", summ)
    f = lambda m: float(m.group(1)) if m and m.group(1) != "-inf" else -99.0
    return {"I": f(i), "M": max(ms) if ms else -99.0, "LRA": f(lra), "TP": f(pk)}


def encode(x: np.ndarray, out_rel: str, sr: int = SR, q: float = 4.0, limit_db: float = -1.0) -> Path:
    out = OUT / (out_rel + ".ogg")
    out.parent.mkdir(parents=True, exist_ok=True)
    ch = x.shape[1]
    lim = 10 ** (limit_db / 20)
    af = f"alimiter=limit={lim:.4f}:attack=3:release=40:level=disabled:asc=1:latency=1"
    r = run(["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(sr), "-ac", str(ch), "-i", "-",
             "-af", af, "-c:a", "libvorbis", "-q:a", str(q), "-map_metadata", "-1", str(out)],
            x.astype(np.float32).tobytes())
    if r.returncode != 0:
        raise RuntimeError(r.stderr.decode(errors="ignore")[-400:])
    return out


# ------------------------------------------------------------------------ editing
def db(g: float) -> float:
    return 10 ** (g / 20)


def trim(x: np.ndarray, sr: int = SR, rel_db: float = -45.0, pre: float = 0.004, fade_out: float = 0.04) -> np.ndarray:
    """Cut leading/trailing silence (relative to the peak) and add tiny fades."""
    a = np.abs(x).max(axis=1)
    pk = a.max()
    if pk <= 0:
        return x
    idx = np.where(a > pk * db(rel_db))[0]
    s = max(0, idx[0] - int(pre * sr))
    e = min(len(x), idx[-1] + int(0.03 * sr))
    y = x[s:e].copy()
    fi = min(len(y), int(0.003 * sr))
    y[:fi] *= np.linspace(0, 1, fi)[:, None]
    fo = min(len(y), int(fade_out * sr))
    y[-fo:] *= np.linspace(1, 0, fo)[:, None]
    return y


def envelope(x: np.ndarray, sr: int, win: float = 0.01) -> np.ndarray:
    m = np.abs(x).mean(axis=1)
    n = max(1, int(win * sr))
    return np.sqrt(np.convolve(m * m, np.ones(n) / n, mode="same"))


def slice_events(x: np.ndarray, sr: int, n: int, min_len: float = 0.08, max_len: float = 1.5,
                 gap: float = 0.10, rel_db: float = -26.0, pre: float = 0.015, post: float = 0.12,
                 fixed: float | None = None) -> list[np.ndarray]:
    """Split a take with several events (steps, barks, hits) into single events.
    Picks the n strongest events of a sensible length, returned in time order."""
    env = envelope(x, sr)
    thr = np.percentile(env, 99.5) * db(rel_db)
    act = env > thr
    edges = np.flatnonzero(np.diff(np.concatenate([[0], act.astype(np.int8), [0]])))
    runs = list(zip(edges[::2], edges[1::2]))
    merged: list[list[int]] = []
    for s, e in runs:
        if merged and s - merged[-1][1] < gap * sr:
            merged[-1][1] = e
        else:
            merged.append([s, e])
    cands = []
    for s, e in merged:
        ln = (e - s) / sr
        if ln < min_len or ln > max_len:
            continue
        a = max(0, s - int(pre * sr))
        b = min(len(x), (s + int(fixed * sr)) if fixed else e + int(post * sr))
        cands.append((float(env[s:e].max()), a, b))
    # strongest events, but skip outliers (the loudest 10 % tend to be bumps)
    cands.sort(key=lambda c: -c[0])
    if len(cands) > n * 2:
        cands = cands[len(cands) // 10:]
    pick = sorted(cands[:n], key=lambda c: c[1])
    out = []
    for _, a, b in pick:
        y = x[a:b].copy()
        fo = min(len(y), int(0.03 * sr))
        y[-fo:] *= np.linspace(1, 0, fo)[:, None]
        out.append(y)
    return out


def to_stereo(x: np.ndarray, offset_s: float = 0.0, sr: int = SR) -> np.ndarray:
    """Mono -> wide stereo by reading the right channel `offset_s` later (decorrelated but natural)."""
    if x.shape[1] == 2:
        return x
    off = int(offset_s * sr)
    m = x[:, 0]
    if off <= 0:
        return np.stack([m, m], axis=1)
    return np.stack([m[:-off], m[off:]], axis=1)


def fit(x: np.ndarray, n: int) -> np.ndarray:
    """Tile or cut to n frames (tiling with 0.5 s crossfades)."""
    if len(x) >= n:
        return x[:n]
    X = int(0.5 * SR)
    out = x.copy()
    while len(out) < n:
        t = np.linspace(0, 1, X)[:, None]
        head = out[:-X]
        mid = out[-X:] * np.sqrt(1 - t) + x[:X] * np.sqrt(t)
        out = np.concatenate([head, mid, x[X:]])
    return out[:n]


def make_loop(x: np.ndarray, length_s: float, xfade_s: float = 3.0, sr: int = SR) -> np.ndarray:
    """Seamless loop: the tail after `length_s` is equal-power crossfaded into the head,
    so sample L-1 flows straight into sample 0."""
    L, X = int(length_s * sr), int(xfade_s * sr)
    if len(x) < L + X:
        raise ValueError(f"loop source too short: {len(x)/sr:.1f}s < {length_s + xfade_s:.1f}s")
    seg = x[:L + X]
    out = seg[:L].copy()
    t = np.linspace(0, 1, X)[:, None]
    out[:X] = seg[L:L + X] * np.sqrt(1 - t) + seg[:X] * np.sqrt(t)
    return out


def layer(parts: list[tuple[np.ndarray, float]], n: int) -> np.ndarray:
    y = np.zeros((n, 2), dtype=np.float32)
    for p, g in parts:
        y += fit(to_stereo(p) if p.shape[1] == 1 else p, n) * db(g)
    return y


def compress(x: np.ndarray, sr: int = SR) -> np.ndarray:
    """Gentle bed compression: tames laughs, crackle spikes and thunder so a quiet
    ambience never jumps out on phone speakers (applied before the loop is cut)."""
    ch = x.shape[1]
    r = run(["ffmpeg", "-v", "error", "-f", "f32le", "-ar", str(sr), "-ac", str(ch), "-i", "-",
             "-af", "acompressor=threshold=0.05:ratio=3:attack=15:release=400:makeup=1",
             "-f", "f32le", "-ac", str(ch), "-ar", str(sr), "-"], x.astype(np.float32).tobytes())
    return np.frombuffer(r.stdout, dtype=np.float32).reshape(-1, ch).copy()


def normalise_integrated(x: np.ndarray, target: float, sr: int = SR) -> tuple[np.ndarray, float]:
    m = measure(x, sr)
    g = target - m["I"]
    return x * db(g), g


def normalise_sfx(x: np.ndarray, group: str, sr: int, extra_db: float = 0.0) -> np.ndarray:
    # pad so sounds shorter than the 400 ms momentary window still get a reading
    m = measure(np.concatenate([x, np.zeros((int(0.5 * sr), x.shape[1]), np.float32)]), sr)
    g = SFX_TARGET[group] + extra_db - m["M"]
    pk = 20 * np.log10(max(1e-9, float(np.abs(x).max())))
    g = min(g, SFX_PEAK_DB - pk)
    return x * db(g)


# ------------------------------------------------------------------------- recipes
MANIFEST: list[dict] = []   # filled below; one dict per output file


def sfx(out: str, group: str, src: str, *, start=None, dur=None, af=None, pitch=None, sr=SR,
        rel_db=-45.0, extra_db=0.0):
    MANIFEST.append(dict(type="sfx", out=out, group=group, src=src, start=start, dur=dur, af=af,
                         pitch=pitch, sr=sr, rel_db=rel_db, extra_db=extra_db))


def sliced(prefix: str, group: str, src: str, n: int, *, start=None, dur=None, af=None, pitch=None,
           sr=SR, extra_db=0.0, **kw):
    MANIFEST.append(dict(type="sliced", out=prefix, group=group, src=src, n=n, start=start, dur=dur, af=af,
                         pitch=pitch, sr=sr, extra_db=extra_db, kw=kw))


def amb(out: str, layers: list[dict], length: float, xfade: float = 4.0):
    MANIFEST.append(dict(type="amb", out=out, layers=layers, length=length, xfade=xfade))


def music(out: str, src: str, *, start=None, dur=None, fade_out=None):
    MANIFEST.append(dict(type="music", out=out, src=src, start=start, dur=dur, fade_out=fade_out))


def L(src, gain=0.0, start=None, dur=None, af=None, stereo_offset=7.0):
    return dict(src=src, gain=gain, start=start, dur=dur, af=af, off=stereo_offset)


# --- ambience beds (loops) ------------------------------------------------------
DIST = "lowpass=f=2600,highpass=f=120"
amb("ambience/amb_village_day", [
    L(BSB + "awakening_birds_s0222.ogg", 0, start=20, dur=80),
    L(BSB + "crowd_of_50_60_people_1_s3515.ogg", -9, start=10, dur=80, af="lowpass=f=1800,highpass=f=150"),
    L(BSB + "wind_in_a_tree_s0659.ogg", -14, start=5, dur=80),
], length=60)
amb("ambience/amb_village_night", [
    L(BSB + "campaign_at_night_4_s1880.ogg", 0, start=30, dur=80),
    L(BSB + "wind_in_a_tree_s0659.ogg", -12, start=40, dur=80, af="lowpass=f=1500"),
], length=60)
amb("ambience/amb_meadow_day", [
    L(BSB + "awakening_birds_s0222.ogg", 0, start=100, dur=70),
    L(BSB + "wind_in_a_tree_s0659.ogg", -8, start=50, dur=65),
], length=55)
amb("ambience/amb_forest_day", [
    L(BSB + "forest_and_stream_1_s2713.ogg", 0, start=60, dur=80),
    L(BSB + "forest_wind_in_the_trees_s0904.ogg", -6, start=30, dur=80),
], length=60)
amb("ambience/amb_forest_night", [
    L(OGA + "ambience/wolfgang_crickets_loop.mp3", -3),
    L(BSB + "forest_wind_in_the_trees_s0904.ogg", -4, start=120, dur=80, af="lowpass=f=1200"),
    L(BSB + "small_stream_s0823.ogg", -14, start=10, dur=80, af="lowpass=f=3000"),
], length=60)
amb("ambience/amb_creek", [
    L(BSB + "small_stream_s0823.ogg", 0, start=5, dur=80),
    L(BSB + "evening_birds_s1859.ogg", -12, start=20, dur=80),
], length=55)
amb("ambience/amb_danger", [
    L(BSB + "strong_wind_and_trees_1_s1450.ogg", 0, start=20, dur=80, af="lowpass=f=900," + pitch_af(0.85)),
    L(BSB + "whistling_of_the_wind_1_s0147.ogg", -8, start=10, dur=80, af="highpass=f=300"),
], length=55)
amb("ambience/amb_camp", [
    L(BSB + "strong_wind_and_trees_1_s1450.ogg", -4, start=60, dur=80, af="lowpass=f=900," + pitch_af(0.85)),
    L(BSB + "fire_foley_s3322.ogg", -3, stereo_offset=5.0),
], length=45)
amb("ambience/amb_tavern", [
    L(BSB + "small_restaurant_conversations_s3542.ogg", 0, start=20, dur=80, af="lowpass=f=3200"),
    L(BSB + "fireplace_2_s0031.ogg", -7, dur=62, stereo_offset=9.0),
], length=50)
amb("ambience/amb_smithy", [
    L(BSB + "big_branching_fire_1_s0987.ogg", 0, af="lowpass=f=2500", stereo_offset=6.0),
    L(BSB + "fireplace_1_s0030.ogg", -6, stereo_offset=11.0),
], length=30, xfade=3.0)
amb("ambience/amb_healer", [
    L(BSB + "fireplace_1_s0030.ogg", 0, stereo_offset=13.0),
    L(BSB + "whistling_of_the_wind_1_s0147.ogg", -12, start=30, dur=70, af="lowpass=f=1500"),
], length=45)
amb("ambience/amb_rain", [L(OGA + "sfx/rain-loopable/3.ogg", 0)], length=41, xfade=3.0)
amb("ambience/amb_storm", [L(BSB + "storm_and_rain_3_s2717.ogg", 0)], length=36, xfade=3.0)
amb("ambience/amb_wind", [
    L(BSB + "strong_wind_in_a_village_s0625.ogg", 0, start=5, dur=80),
], length=55)

# --- ambience spot sounds (sprinkled at random by the director) ------------------
sfx("ambience/spots/owl_01", "spot", BSB + "tawny_owl_1_s1763.ogg", rel_db=-40)
sfx("ambience/spots/owl_02", "spot", BSB + "tawny_owl_2_s1764.ogg", rel_db=-40)
sfx("ambience/spots/owl_03", "spot", BSB + "owls_s0429.ogg", start=0, dur=9, rel_db=-40)
sliced("ambience/spots/dog_distant", "spot", BSB + "barking_dog_s0916.ogg", 3, dur=90,
       af="lowpass=f=1800,aecho=0.8:0.6:180:0.25", sr=32000, min_len=0.1, max_len=1.2, post=0.5)
sfx("ambience/spots/bird_blackbird", "spot", BSB + "common_blackbird_2_s3474.ogg")
sliced("ambience/spots/hammer_distant", "spot", BSB0 + "anvil_blacksmith_1_s3589.ogg", 3,
       af="lowpass=f=3000,aecho=0.8:0.5:90:0.2", min_len=0.03, max_len=0.6, post=0.5, rel_db=-20)
sliced("ambience/spots/well_bucket", "spot", BSB + "metal_bucket_s0543.ogg", 3, min_len=0.25, max_len=3.0,
       post=0.3, gap=0.25)
sfx("ambience/spots/rope_creak", "spot", BSB + "rope_s3417.ogg", start=12, dur=3.5)
sliced("ambience/spots/glass_clink", "spot", BSB + "clink_of_glass_toast_1_s2886.ogg", 2, min_len=0.02,
       max_len=0.8, post=0.4)
sliced("ambience/spots/mug_knock", "spot", RD1 + "dishes_01.ogg", 1, min_len=0.02, max_len=2.0, post=0.3)
sfx("ambience/spots/mug_knock_02", "spot", RD1 + "dishes_03.ogg")
sliced("ambience/spots/page_turn", "spot", BSB + "pages_that_turn_s0493.ogg", 3, min_len=0.15, max_len=1.5,
       post=0.15, gap=0.2)
sfx("ambience/spots/page_turn_04", "spot", BSB + "turned_page_s0164.ogg")
sfx("ambience/spots/wolf_howl_distant", "spot", BSB + "dog_singing_1_s2450.ogg",
    af=pitch_af(0.8) + ",lowpass=f=2200,aecho=0.8:0.7:250|480:0.35|0.2")
sfx("ambience/spots/growl_distant", "spot", BSB + "growling_cat_3_s1887.ogg",
    af=pitch_af(0.55) + ",lowpass=f=1500,aecho=0.8:0.6:200:0.3")
sfx("ambience/spots/thunder", "spot", BSB + "thunder_s2718.ogg", rel_db=-50, extra_db=4)
sfx("ambience/spots/church_bell", "spot", BSB0 + "church_bell_s0135.ogg", rel_db=-50)
# bellows: generated (brown noise through a breathing envelope), no third-party audio
sfx("ambience/spots/bellows", "foley",
    "anoisesrc=color=brown:duration=2.2:sample_rate=44100:amplitude=0.6",
    af="lowpass=f=700,highpass=f=60,volume='if(lt(t,1.0),t/1.0,max(0,1-(t-1.0)/1.1))':eval=frame", rel_db=-60)

# --- footsteps (mono) ------------------------------------------------------------
for i in range(5):
    sfx(f"sfx/footsteps/step_grass_{i+1:02d}", "footstep", KI + f"footstep_grass_{i:03d}.ogg")
    sfx(f"sfx/footsteps/step_wood_{i+1:02d}", "footstep", KI + f"footstep_wood_{i:03d}.ogg")
    sfx(f"sfx/footsteps/step_stone_{i+1:02d}", "footstep", KI + f"footstep_concrete_{i:03d}.ogg", extra_db=-1)
for i in range(6):
    sfx(f"sfx/footsteps/step_dirt_{i+1:02d}", "footstep", KR + f"footstep{i:02d}.ogg")
for i in range(6):
    sfx(f"sfx/footsteps/step_cobble_{i+1:02d}", "footstep", CB + f"gravel/{i}.ogg")
sliced("sfx/footsteps/step_leaves", "footstep", BSB + "feet_in_leaves_2_s2889.ogg", 5, min_len=0.08,
       max_len=0.9, gap=0.08, rel_db=-22, fixed=0.34)

# --- combat ------------------------------------------------------------------------
for i, f in enumerate(["whoosh_1_s1795", "whoosh_3_s1797", "whoosh_5_s1799", "whoosh_7_s1801"]):
    sfx(f"sfx/combat/swing_{i+1:02d}", "combat", BSB0 + f + ".ogg", extra_db=-3)
for i, n in enumerate([1, 4, 7]):
    sfx(f"sfx/combat/swing_heavy_{i+1:02d}", "combat", OGA + f"sfx/sword-attacks-starninjas/sword - StarNinjas/sword.{n}.ogg", extra_db=-2)
sfx("sfx/combat/hit_flesh_01", "combat", BSB0 + "sword_cut_s0127.ogg")
sfx("sfx/combat/hit_flesh_02", "combat", BSB0 + "sword_s0129.ogg")
sfx("sfx/combat/hit_flesh_03", "combat", KI + "impactPunch_heavy_000.ogg")
sfx("sfx/combat/hit_flesh_04", "combat", KI + "impactPunch_heavy_002.ogg")
sfx("sfx/combat/hit_flesh_05", "combat", OGA + "sfx/3-melee-sounds/melee sounds/melee sound.wav")
for i in range(3):
    sfx(f"sfx/combat/hit_wood_{i+1:02d}", "combat", KI + f"impactWood_heavy_{i:03d}.ogg")
    sfx(f"sfx/combat/hit_metal_{i+1:02d}", "combat", KI + f"impactMetal_heavy_{i:03d}.ogg")
for i, n in enumerate([1, 3, 5, 7, 9]):
    sfx(f"sfx/combat/block_{i+1:02d}", "combat", OGA + f"sfx/sword-clashes-starninjas/sword_clash.{n}.ogg")
for i, n in enumerate([2, 5, 9]):
    sfx(f"sfx/combat/dodge_{i+1:02d}", "combat", OGA + f"sfx/swishes-artisticdude/swishes/swish-{n}.wav", extra_db=-4)
sfx("sfx/combat/bow_shot_01", "combat", OGA + "sfx/battle-sfx-ogrebane/battle_sound_effects/Bow.wav")
sfx("sfx/combat/bow_shot_02", "combat", OGA + "sfx/battle-sfx-ogrebane/battle_sound_effects/Bow.wav",
    af=pitch_af(1.08))
sfx("sfx/combat/arrow_hit_01", "combat", KI + "impactWood_light_000.ogg")
sfx("sfx/combat/arrow_hit_02", "combat", KI + "impactWood_light_002.ogg")
sfx("sfx/combat/sword_draw", "combat", ART + "battle/sword-unsheathe2.wav", extra_db=-3)
for i, n in enumerate([0, 3, 6]):
    sfx(f"sfx/combat/player_hurt_{i+1:02d}", "voice", VOX + f"hurt{n}.wav")
sfx("sfx/combat/player_death", "voice", VOX + "death0.wav")
for i, n in enumerate([0, 2, 5]):
    sfx(f"sfx/combat/player_attack_grunt_{i+1:02d}", "voice", VOX + f"attack{n}.wav", extra_db=-3)

# --- creatures (32 kHz mono) ---------------------------------------------------
C = 32000
sfx("sfx/creatures/wolf_howl_01", "creature", BSB + "dog_singing_1_s2450.ogg", af=pitch_af(0.82) + ",aecho=0.8:0.5:120:0.2", sr=C, extra_db=-2)
sfx("sfx/creatures/wolf_howl_02", "creature", RD + "howl.ogg", af=pitch_af(0.85) + ",aecho=0.8:0.5:120:0.2", sr=C, extra_db=-2)
sfx("sfx/creatures/wolf_growl_01", "creature", BSB + "growling_cat_1_s1885.ogg", af=pitch_af(0.6), sr=C)
sfx("sfx/creatures/wolf_growl_02", "creature", BSB + "growling_cat_3_s1887.ogg", af=pitch_af(0.62), sr=C)
sliced("sfx/creatures/wolf_bark", "creature", BSB + "small_dogs_bark_growl_s1060.ogg", 2, af=pitch_af(0.7), sr=C,
       min_len=0.08, max_len=1.0, post=0.15)
sfx("sfx/creatures/wolf_hurt_01", "creature", RD + "hurt_01.ogg", af=pitch_af(0.85), sr=C)
sfx("sfx/creatures/wolf_hurt_02", "creature", RD + "hurt_03.ogg", af=pitch_af(0.8), sr=C)
sfx("sfx/creatures/wolf_death", "creature", RD + "hurt_05.ogg", af=pitch_af(0.7) + ",aecho=0.8:0.4:90:0.25", sr=C)
for i, n in enumerate([0, 2, 4]):
    sfx(f"sfx/creatures/goblin_chatter_{i+1:02d}", "creature", LRSF + f"Goblin_0{n}.mp3", sr=C, extra_db=-2)
sfx("sfx/creatures/goblin_hurt_01", "creature", LRSF + "Goblin_01.mp3", sr=C)
sfx("sfx/creatures/goblin_hurt_02", "creature", LRSF + "Goblin_03.mp3", sr=C)
sfx("sfx/creatures/goblin_death", "creature", RD + "hurt_02.ogg", af=pitch_af(1.25), sr=C)
for i, n in enumerate([2, 3, 4]):
    sfx(f"sfx/creatures/orc_roar_{i+1:02d}", "creature", ART + f"NPC/ogre/ogre{n}.wav", af=pitch_af(0.9), sr=C)
sfx("sfx/creatures/orc_hurt_01", "creature", ART + "NPC/ogre/ogre1.wav", sr=C)
sfx("sfx/creatures/orc_hurt_02", "creature", ART + "NPC/ogre/ogre5.wav", sr=C)
sfx("sfx/creatures/boar_squeal_01", "creature", BSB + "grumpy_pig_1_s1658.ogg", af=pitch_af(1.15), sr=C)
sfx("sfx/creatures/boar_squeal_02", "creature", BSB + "grumpy_pig_2_s1659.ogg", start=0, dur=3.2, af=pitch_af(1.1), sr=C)
sfx("sfx/creatures/boar_grunt", "creature", BSB + "grumpy_pig_2_s1659.ogg", start=3.0, af=pitch_af(0.8), sr=C, extra_db=-3)
sfx("sfx/creatures/bear_roar_01", "creature", BSB + "cat_roar_1_s1881.ogg", af=pitch_af(0.5), sr=C)
sfx("sfx/creatures/bear_roar_02", "creature", BSB + "cat_roar_3_s1883.ogg", af=pitch_af(0.48), sr=C)
sfx("sfx/creatures/bear_growl", "creature", ART + "NPC/giant/giant2.wav", af=pitch_af(0.8), sr=C)
for i, n in enumerate([1, 2, 4]):
    sfx(f"sfx/creatures/spider_hiss_{i+1:02d}", "creature", RD + f"bug_0{n}.ogg", sr=C, extra_db=-2)
sfx("sfx/creatures/spider_hiss_04", "creature",
    "anoisesrc=color=white:duration=0.7:sample_rate=44100:amplitude=0.5",
    af="highpass=f=2500,lowpass=f=9000,tremolo=f=28:d=0.6,volume='if(lt(t,0.06),t/0.06,max(0,1-(t-0.06)/0.64))':eval=frame",
    sr=C, rel_db=-60, extra_db=-4)
sfx("sfx/creatures/wyvern_screech_01", "creature", LRSF + "Dragon_Growl_00.mp3", sr=C)
sfx("sfx/creatures/wyvern_screech_02", "creature", LRSF + "Dragon_Growl_01.mp3", sr=C)
sfx("sfx/creatures/wyvern_screech_03", "creature", BSB + "cat_roar_1_s1881.ogg", af=pitch_af(0.75) + ",aecho=0.8:0.6:140:0.3", sr=C)
sfx("sfx/creatures/monster_hurt", "creature", RD + "monster_03.ogg", sr=C)
sfx("sfx/creatures/monster_death", "creature", RD + "monster_04.ogg", af=pitch_af(0.85), sr=C)

# --- animals (32 kHz mono) -------------------------------------------------------
sfx("sfx/animals/rooster_01", "animal", BSB + "rooster_s0104.ogg", sr=C)
sfx("sfx/animals/rooster_02", "animal", BSB + "song_of_rooster_s0283.ogg", sr=C)
sfx("sfx/animals/chicken_01", "animal", BSB + "annoyed_hen_s0453.ogg", sr=C)
sliced("sfx/animals/chicken_cluck", "animal", BSB + "hen_lays_1_s0975.ogg", 3, sr=C, min_len=0.1, max_len=2.5,
       gap=0.2, post=0.2)
sfx("sfx/animals/chicken_scared", "animal", BSB + "hen_scared_s1040.ogg", sr=C)
for i, s in enumerate(["sheep_1_s2343", "sheep_3_s2345", "sheep_5_s2347"]):
    sfx(f"sfx/animals/sheep_{i+1:02d}", "animal", BSB + s + ".ogg", sr=C)
sfx("sfx/animals/cow_01", "animal", BSB + "cow_moos_2_s2382.ogg", sr=C)
sfx("sfx/animals/cow_02", "animal", BSB + "cow_moos_4_s2384.ogg", sr=C)
sliced("sfx/animals/cow_far", "animal", BSB + "cow_moos_s0546.ogg", 2, sr=C, min_len=0.5, max_len=4.0,
       gap=0.3, post=0.3)
sfx("sfx/animals/pig_01", "animal", BSB + "grumpy_pig_1_s1658.ogg", sr=C)
sfx("sfx/animals/pig_02", "animal", BSB + "grumpy_pig_2_s1659.ogg", start=0, dur=3.2, sr=C)
sfx("sfx/animals/horse_neigh_01", "animal", BSB0 + "horse_neigh_1_s0284.ogg", sr=C)
sfx("sfx/animals/horse_neigh_02", "animal", BSB0 + "horse_neigh_4_s1542.ogg", sr=C)
sfx("sfx/animals/horse_snort", "animal", BSB0 + "horse_breath_s1543.ogg", sr=C, extra_db=-3)
sliced("sfx/animals/dog_bark", "animal", BSB + "barking_dog_2_s2954.ogg", 3, sr=C, min_len=0.08, max_len=1.2,
       post=0.15)
sfx("sfx/animals/goat", "animal", BSB + "goat_1_s1380.ogg", sr=C)
sfx("sfx/animals/donkey", "animal", BSB + "donkey_braying_1_s1549.ogg", start=0, dur=6.5, sr=C)

# --- world foley ------------------------------------------------------------------
sliced("sfx/world/anvil", "foley", BSB0 + "anvil_blacksmith_2_s3590.ogg", 4, min_len=0.03, max_len=0.6,
       post=0.6, rel_db=-20)
sliced("sfx/world/hammer_nail", "foley", BSB + "nail_and_hammer_1_s0005.ogg", 3, min_len=0.02, max_len=0.5,
       post=0.25, rel_db=-20)
sfx("sfx/world/door_open", "foley", KR + "doorOpen_1.ogg")
sfx("sfx/world/door_close", "foley", KR + "doorClose_2.ogg")
sfx("sfx/world/coins", "foley", KR + "handleCoins.ogg")
sfx("sfx/world/coins_02", "foley", KR + "handleCoins2.ogg")
sfx("sfx/world/book_open", "foley", KR + "bookOpen.ogg")
sfx("sfx/world/chop_wood", "foley", KR + "chop.ogg")
sfx("sfx/world/cloth", "foley", KR + "cloth2.ogg", extra_db=-3)
sfx("sfx/world/bell_tower", "foley", BSB0 + "bell_tower_s3446.ogg", rel_db=-50)

# --- UI ------------------------------------------------------------------------------
sfx("ui/tap", "ui", KUA + "click3.ogg", extra_db=-2)
sfx("ui/tap_02", "ui", KU + "click_002.ogg", extra_db=-2)
sfx("ui/open", "ui", KU + "open_002.ogg")
sfx("ui/close", "ui", KU + "close_002.ogg")
sfx("ui/menu_open", "ui", LRSF + "Inventory_Open_00.mp3")
sfx("ui/select", "ui", KU + "select_002.ogg")
sfx("ui/coin", "ui", LRSF + "Pickup_Gold_00.mp3")
sfx("ui/coin_02", "ui", LRSF + "Pickup_Gold_02.mp3")
sfx("ui/error", "ui", KU + "error_004.ogg")
sfx("ui/confirm", "ui", KU + "confirmation_002.ogg")
sfx("ui/level_up", "jingle", LRSF + "Jingle_Achievement_00.mp3", rel_db=-55)
sfx("ui/quest_accepted", "jingle", KJ + "Pizzicato jingles/jingles_PIZZI02.ogg", rel_db=-55)
sfx("ui/quest_complete", "jingle", LRSF + "Jingle_Win_00.mp3", rel_db=-55)
sfx("ui/defeat", "jingle", LRSF + "Jingle_Lose_00.mp3", rel_db=-55)

# --- music -------------------------------------------------------------------------------
M = OGA + "music/"
music("music/mus_village_day", M + "randommind_Market_Day.ogg")
music("music/mus_village_day_02", M + "randommind_Minstrel_Dance_0.ogg")
music("music/mus_tavern", M + "randommind_The_Old_Tower_Inn.ogg")
music("music/mus_explore", M + "randommind_The_Bards_Tale.ogg")
music("music/mus_explore_02", M + "randommind_Kings_Feast_0.ogg")
music("music/mus_explore_03", M + "medieval-theme/medieval_theme_music.ogg")
music("music/mus_night", M + "historic-renaissance-music-from-1597-if-my-complaints-could-passions-move-by-john-dowland/"
      "Of Far Different Nature x John Dowland - If my Complaints Could Passions Move_0.mp3")
music("music/mus_combat", M + "cynicmusic_battleThemeA.mp3")
music("music/mus_combat_stinger", M + "medieval-standoff/medieval_standoff.ogg", dur=7.0, fade_out=2.0)


# --------------------------------------------------------------------------- build
def build_sfx_like(e: dict) -> list[tuple[str, np.ndarray, int]]:
    sr = e["sr"]
    af = e["af"]
    if e.get("pitch"):
        af = pitch_af(e["pitch"]) + ("," + af if af else "")
    x = decode(e["src"], 1, SR, e.get("start"), e.get("dur"), af)
    outs = []
    if e["type"] == "sliced":
        kw = dict(e["kw"])
        parts = slice_events(x, SR, e["n"], **kw)
        for i, p in enumerate(parts):
            outs.append((f"{e['out']}_{i+1:02d}", trim(p, SR, -50)))
    else:
        outs.append((e["out"], trim(x, SR, e["rel_db"])))
    res = []
    for name, y in outs:
        if sr != SR:
            r = run(["ffmpeg", "-v", "error", "-f", "f32le", "-ar", str(SR), "-ac", "1", "-i", "-", "-af",
                     f"aresample={sr}", "-f", "f32le", "-ac", "1", "-ar", str(sr), "-"], y.tobytes())
            y = np.frombuffer(r.stdout, dtype=np.float32).reshape(-1, 1).copy()
        y = normalise_sfx(y, e["group"], sr, e.get("extra_db", 0.0))
        res.append((name, y, sr))
    return res


def build_amb(e: dict) -> np.ndarray:
    need = e["length"] + e["xfade"]
    parts = []
    for ly in e["layers"]:
        x = decode(ly["src"], channels(ly["src"]), SR, ly["start"], ly["dur"], ly["af"])
        st = to_stereo(x, ly["off"])
        parts.append((st, ly["gain"]))
    mix = layer(parts, int(need * SR))
    mix = compress(mix)
    loop = make_loop(mix, e["length"], e["xfade"])
    loop, _ = normalise_integrated(loop, -24.0)
    return loop


def build_music(e: dict) -> np.ndarray:
    x = decode(e["src"], 2, SR, e.get("start"), e.get("dur"))
    if e.get("fade_out"):
        n = int(e["fade_out"] * SR)
        x[-n:] *= np.linspace(1, 0, n)[:, None]
    x, _ = normalise_integrated(x, -18.0)
    return x


def main(prefix: str = "") -> None:
    done = []
    for e in MANIFEST:
        if not e["out"].startswith(prefix):
            continue
        try:
            if e["type"] in ("sfx", "sliced"):
                for name, y, sr in build_sfx_like(e):
                    done.append(encode(y, name, sr, q=4, limit_db=-3.4))
            elif e["type"] == "amb":
                done.append(encode(build_amb(e), e["out"], SR, q=4, limit_db=-3.4))
            else:
                done.append(encode(build_music(e), e["out"], SR, q=4, limit_db=-2.6))
            print("ok ", e["out"], flush=True)
        except Exception as ex:  # keep going, report at the end
            print("ERR", e["out"], ex, flush=True)
    write_table()


def write_table() -> None:
    rows = []
    for p in sorted(OUT.rglob("*.ogg")):
        m = measure_file(p)
        r = run(["ffprobe", "-v", "error", "-show_entries", "format=duration:stream=sample_rate,channels",
                 "-of", "csv=p=0", str(p)])
        vals = r.stdout.decode().split()
        sr_ch = vals[0].split(",") if vals else ["", ""]
        dur = float(vals[-1]) if vals else 0.0
        rows.append([p.relative_to(OUT).as_posix(), sr_ch[0], sr_ch[1], f"{dur:.2f}", f"{p.stat().st_size/1024:.1f}",
                     f"{m['I']:.1f}", f"{m['M']:.1f}", f"{m['TP']:.1f}", f"{m['LRA']:.1f}"])
    with open(OUT / "loudness.csv", "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["file", "rate", "ch", "sec", "kb", "integrated_lufs", "max_momentary_lufs", "true_peak_dbtp", "lra"])
        w.writerows(rows)
    tot = sum(p.stat().st_size for p in OUT.rglob("*.ogg"))
    print(f"{len(rows)} files, {tot/1048576:.2f} MB")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "")
