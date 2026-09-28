# Convert the Cat souls-like template's CC0 SoundFX (48 kHz stereo WAV) to the
# repo's one-shot format (assets/audio/README.md): mono, 44.1 kHz, Ogg Vorbis
# ~q4, leading/trailing silence trimmed at -45 dB relative, 3 ms fade-in,
# 35 ms fade-out, peak normalised to -3 dBFS. (Loudness matching per group is
# left to the audio pipeline; peaks are capped here.)
# usage: python convert_souls_sfx.py <SoundFX dir> <out dir>
# needs: numpy, scipy, soundfile (libsndfile >= 1.0.29 for Vorbis)
import sys, os, json
import numpy as np
import soundfile as sf
from scipy.signal import resample_poly

SRC, OUT = sys.argv[1], sys.argv[2]
# category -> (files, output prefix, use)
PICK = {
    "clang":   ("clang_*",     "clang",      "metal-on-metal weapon clash, parry, shield block"),
    "clack":   ("clack_*",     "clack",      "wood clack: staff/stick hits, wooden shield, training dummy"),
    "swish":   ("swish_*",     "swish",      "light weapon / fist swing"),
    "swoosh":  ("swoosh_*",    "swoosh",     "heavy swing, roll, cloak, magic whoosh"),
    "hit":     ("hit_blunt_*", "hit_blunt",  "blunt impact: fist, club, shield bash, body fall"),
    "cloth":   ("cloth_*",     "cloth",      "armour/cloth rustle on dodge, guard, equip, stand up"),
    "creak":   ("creak_*",     "creak",      "door / gate / chest hinge creak"),
    "ratchet": ("ratchet_*",   "ratchet",    "lever pull, winch, portcullis"),
    "cork":    ("cork_*",      "cork",       "potion uncork"),
    "slosh":   ("slosh_*",     "slosh",      "potion drink / liquid"),
}
os.makedirs(OUT, exist_ok=True)
rows = []
import glob
for cat, (pat, prefix, use) in PICK.items():
    files = sorted(glob.glob(os.path.join(SRC, cat, pat + ".wav")))
    for i, f in enumerate(files, 1):
        x, sr = sf.read(f, always_2d=True)
        x = x.mean(axis=1)
        if sr != 44100:
            x = resample_poly(x, 441, sr // 100)
            sr = 44100
        a = np.abs(x)
        pk = a.max() if len(a) else 0
        if pk <= 0:
            continue
        thr = pk * 10 ** (-45 / 20)
        idx = np.where(a > thr)[0]
        x = x[max(0, idx[0] - int(0.002 * sr)): idx[-1] + int(0.01 * sr)]
        fi, fo = int(0.003 * sr), min(int(0.035 * sr), len(x) // 3)
        x[:fi] *= np.linspace(0, 1, fi)
        x[-fo:] *= np.linspace(1, 0, fo)
        x *= (10 ** (-3 / 20)) / np.abs(x).max()
        name = "%s_%02d.ogg" % (prefix, i)
        sf.write(os.path.join(OUT, name), x.astype(np.float32), sr, format="OGG", subtype="VORBIS",
                 compression_level=0.6)
        rows.append({"file": name, "seconds": round(len(x) / sr, 2), "source": "%s/%s" % (cat, os.path.basename(f)), "use": use})
        print(name, rows[-1]["seconds"], "s <-", rows[-1]["source"])
json.dump(rows, open(os.path.join(OUT, "_list.json"), "w"), indent=0)
