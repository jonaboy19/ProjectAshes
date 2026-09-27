"""Writes kingdom/assets/audio/README.md from the build manifest and loudness.csv.
Run after build_audio.py:  py tools/audio/write_readme.py"""
from __future__ import annotations

import csv
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import build_audio as b  # noqa: E402

OUT = b.OUT

LICENCES = [  # (source path prefix, short name, licence, url)
    (b.BSB, "BigSoundBank (Joseph Sardin)", "CC0", "https://bigsoundbank.com/droit.html"),
    (b.BSB0, "BigSoundBank (Joseph Sardin)", "CC0", "https://bigsoundbank.com/droit.html"),
    (b.RD, "rubberduck, 80 CC0 creature SFX", "CC0", "https://opengameart.org/content/80-cc0-creature-sfx"),
    (b.RD1, "rubberduck, 100 CC0 SFX", "CC0", "https://opengameart.org/content/100-cc0-sfx"),
    (b.ART, "artisticdude, RPG Sound Pack", "CC0", "https://opengameart.org/content/rpg-sound-pack"),
    (b.LRSF, "Little Robot Sound Factory, Fantasy Sound Effects Library", "**CC-BY 3.0**",
     "https://opengameart.org/content/fantasy-sound-effects-library"),
    (b.KI, "Kenney, Impact Sounds", "CC0", "https://kenney.nl/assets/impact-sounds"),
    (b.KR, "Kenney, RPG Audio", "CC0", "https://kenney.nl/assets/rpg-audio"),
    (b.KU, "Kenney, Interface Sounds", "CC0", "https://kenney.nl/assets/interface-sounds"),
    (b.KUA, "Kenney, UI Audio", "CC0", "https://kenney.nl/assets/ui-audio"),
    (b.KJ, "Kenney, Music Jingles", "CC0", "https://kenney.nl/assets/music-jingles"),
    (b.VOX, "wolfwoot, Voice Clip Pack Male Adventurer", "CC0",
     "https://opengameart.org/content/voice-clip-pack-male-adventurer-rpg"),
    (b.CB, "congusbongus, Footsteps on different surfaces", "**CC-BY 3.0**",
     "https://opengameart.org/content/footsteps-on-different-surfaces"),
    (b.OGA + "sfx/sword-attacks-starninjas", "StarNinjas, 20 Sword Sound Effects", "CC0",
     "https://opengameart.org/content/20-sword-sound-effects-attacks-and-clashes"),
    (b.OGA + "sfx/sword-clashes-starninjas", "StarNinjas, 20 Sword Sound Effects", "CC0",
     "https://opengameart.org/content/20-sword-sound-effects-attacks-and-clashes"),
    (b.OGA + "sfx/swishes-artisticdude", "artisticdude, Swishes Sound Pack", "CC0",
     "https://opengameart.org/content/swishes-sound-pack"),
    (b.OGA + "sfx/battle-sfx-ogrebane", "Ogrebane, Battle Sound Effects (CC0 option)", "CC0",
     "https://opengameart.org/content/battle-sound-effects"),
    (b.OGA + "sfx/3-melee-sounds", "remaxim, 3 Melee sounds", "CC0", "https://opengameart.org/content/3-melee-sounds"),
    (b.OGA + "sfx/rain-loopable", "Ylmir, Rain (loopable)", "CC0", "https://opengameart.org/content/rain-loopable"),
    (b.OGA + "ambience/wolfgang", "Wolfgang_, Crickets Ambient Noise (loopable)", "CC0",
     "https://opengameart.org/content/crickets-ambient-noise-loopable"),
    (b.OGA + "music/randommind_Market", "RandomMind, Medieval: Market Day", "CC0", "https://opengameart.org/content/medieval-market-day"),
    (b.OGA + "music/randommind_Minstrel", "RandomMind, Medieval: Minstrel Dance", "CC0", "https://opengameart.org/content/medieval-minstrel-dance"),
    (b.OGA + "music/randommind_The_Old", "RandomMind, Medieval: The Old Tower Inn", "CC0", "https://opengameart.org/content/medieval-the-old-tower-inn"),
    (b.OGA + "music/randommind_The_Bards", "RandomMind, Medieval: The Bard's Tale", "CC0", "https://opengameart.org/content/medieval-the-bards-tale"),
    (b.OGA + "music/randommind_Kings", "RandomMind, Medieval: King's Feast", "CC0", "https://opengameart.org/content/medieval-kings-feast"),
    (b.OGA + "music/medieval-theme", "Umplix, Medieval Theme", "CC0", "https://opengameart.org/content/medieval-theme"),
    (b.OGA + "music/medieval-standoff", "Umplix, Medieval Standoff (first 7 s)", "CC0", "https://opengameart.org/content/medieval-standoff"),
    (b.OGA + "music/historic", "Of Far Different Nature, Dowland 1597", "CC0",
     "https://opengameart.org/content/historic-renaissance-music-from-1597-if-my-complaints-could-passions-move-by-john-dowland"),
    (b.OGA + "music/cynicmusic", "cynicmusic, Battle Theme A", "CC0", "https://opengameart.org/content/battle-theme-a"),
    ("anoisesrc", "generated for the game (filtered noise)", "own work", ""),
]


def lic_of(src: str) -> tuple[str, str, str]:
    for pre, name, lic, url in LICENCES:
        if src.startswith(pre):
            return name, lic, url
    return "?", "?", ""


def srcs_of(e: dict) -> list[str]:
    if e["type"] == "amb":
        return [ly["src"] for ly in e["layers"]]
    return [e["src"]]


def bsb_url(src: str) -> str:
    import re
    m = re.search(r"_s(\d{4})\.ogg$", src)
    if not m:
        return ""
    lic = (b.IN / "audio/bigsoundbank/LICENSE.txt")
    for line in lic.read_text(encoding="utf-8").splitlines():
        if f"s{m.group(1)}.html" in line:
            return line.split("|")[1].split()[0]
    return f"https://bigsoundbank.com (sound {m.group(1)})"


def main() -> None:
    rows = {r["file"]: r for r in csv.DictReader(open(OUT / "loudness.csv", encoding="utf-8"))}
    info: dict[str, tuple[list[str], dict]] = {}
    for e in b.MANIFEST:
        info[e["out"]] = (srcs_of(e), e)
    total = sum(p.stat().st_size for p in OUT.rglob("*.ogg"))
    cats: dict[str, list[str]] = {}
    for f in rows:
        cat = f.rsplit("/", 1)[0]
        cats.setdefault(cat, []).append(f)

    L = []
    L.append("# Rising Ashes: game audio\n")
    L.append("Game-ready sound set, built by `tools/audio/build_audio.py` from licence-checked sources in "
             "`assets/incoming/` and played by `scripts/audio/audio_director.gd` (the `Audio` autoload). "
             f"**{len(rows)} files, {total/1048576:.1f} MB** (OGG Vorbis).\n")
    L.append("## Processing\n")
    L.append("| Kind | Format | Loudness | Other |\n|---|---|---|---|")
    L.append("| Music (`music/`) | stereo 44.1 kHz, Vorbis q4 | integrated **-18 LUFS**, true peak <= -1 dBTP (limiter at -2.6 dBFS to absorb Vorbis overshoot) | RandomMind tracks are the authors' seamless loops; the combat stinger is the first 7 s of *Medieval Standoff* with a 2 s fade |")
    L.append("| Ambience beds (`ambience/amb_*`) | stereo 44.1 kHz, q4 | integrated **-24 LUFS**, gentle 3:1 bed compression, peak <= -3.4 dBFS | layered from 1-3 recordings, mono sources widened (right channel read 5-13 s later), **seamless loop**: the tail after the loop length is equal-power crossfaded into the head (3-4 s), so sample N-1 flows into sample 0 |")
    L.append("| One-shots (`sfx/`, `ui/`, `ambience/spots/`) | mono, 44.1 kHz (creatures and animals 32 kHz), q4 | matched on **max momentary loudness** per group (combat/creature -14, voice -16, animal -17, foley -18, UI -19, spot -20, footstep -21 LUFS) and capped at **-3 dBFS peak** (limiter at -3.4 dBFS) | leading/trailing silence trimmed (-45 dB rel.), 3 ms fade-in, 30-40 ms fade-out; multi-event takes auto-sliced into single events |")
    L.append("\nVery short transients (clicks, footsteps, metal hits) hit the -3 dBFS peak cap before the loudness target, so they measure quieter in LUFS "
             "than longer sounds; that's expected (perceived loudness of a 100 ms click is lower). The director applies a per-call volume on top.\n")
    L.append("`smithy` measures -27.5 LUFS because fire crackle peaks hit the limiter; the director plays it +3 dB.\n")
    L.append("## Loop points\n")
    L.append("Every `ambience/amb_*.ogg` loops over the whole file (loop start 0, loop end = file length, listed below). "
             "`AudioDirector` sets `AudioStreamOggVorbis.loop = true` at load, beds start at a random offset. "
             "Music: `mus_tavern` and `mus_combat` loop; other tracks play once, then a 20-90 s pause. Seam check "
             "(|first - last sample|) is within the normal sample-to-sample step for every bed.\n")
    L.append("## Sound list\n")
    L.append("Columns: duration (s), size (KB), integrated LUFS, max momentary LUFS, true peak (dBTP), source and licence.\n")
    order = ["music", "ambience", "ambience/spots", "sfx/footsteps", "sfx/combat", "sfx/creatures", "sfx/animals", "sfx/world", "ui"]
    for cat in order + [c for c in cats if c not in order]:
        if cat not in cats:
            continue
        L.append(f"\n### {cat}/\n")
        L.append("| File | s | KB | LUFS-I | LUFS-M max | dBTP | Source | Licence |\n|---|---|---|---|---|---|---|---|")
        for f in sorted(cats[cat]):
            r = rows[f]
            stem = f[:-4]
            base = stem
            if base not in info:
                base = stem.rsplit("_", 1)[0]
            srcs, e = info.get(base, ([], {}))
            parts, lics = [], set()
            for s in srcs:
                name, lic, url = lic_of(s)
                lics.add(lic)
                fname = Path(s).name if not s.startswith("anoisesrc") else "noise"
                u = bsb_url(s) if "bigsoundbank" in s else url
                parts.append(f"[{fname}]({u})" if u else fname)
            L.append(f"| `{f}` | {r['sec']} | {r['kb']} | {r['integrated_lufs']} | {r['max_momentary_lufs']} | "
                     f"{r['true_peak_dbtp']} | {'<br>'.join(parts)} | {', '.join(sorted(lics))} |")
    L.append("\n## Sources and licences\n")
    L.append("| Source | Licence | Where | Verified |\n|---|---|---|---|")
    seen = set()
    for pre, name, lic, url in LICENCES:
        if name in seen:
            continue
        seen.add(name)
        L.append(f"| {name} | {lic} | {url or '-'} | 2026-09-27, source page |")
    L.append("\nCC-BY credits are in `kingdom/CREDITS.md` (shown in the in-game Credits screen). New BigSoundBank downloads and "
             "their per-sound page URLs: `assets/incoming/audio/bigsoundbank/LICENSE.txt` (folder has a `.gdignore`; only the "
             "processed files here ship).\n")
    L.append("## Rebuild\n")
    L.append("```bash\npy tools/audio/build_audio.py            # all (about 5 min), or a prefix: sfx/combat, ambience/amb_tavern\n"
             "py tools/audio/write_readme.py            # this file\n```\nNeeds ffmpeg/ffprobe and Python 3 + numpy. "
             "`loudness.csv` is rewritten by every build (ffmpeg `ebur128`, 0.6 s padding so short sounds get a reading).\n")
    L.append("## Naming for the director\n")
    L.append("`<name>_NN.ogg` variants are picked at random by `Audio.play_sfx(\"<name>\", pos)`; `Audio.play_sfx(\"<name>_NN\")` plays one exact file. "
             "Footsteps: `step_<surface>` with surface grass, dirt, cobble, stone, wood, leaves.\n")
    (OUT / "README.md").write_text("\n".join(L) + "\n", encoding="utf-8")
    print("README written,", len(rows), "files")


if __name__ == "__main__":
    main()
