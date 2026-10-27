"""Audio gate for a Movie Maker recording (AAA gate, audio lines): measure, don't guess.

  py tools/qa/audio/audio_gate.py <movie.mp4|avi> <out_dir> [--log game.log] [--start SECONDS] [--fps 30]

Reports (stdout + <out_dir>/audio_gate.txt):
  - the audio stream is present (codec, rate, channels)
  - EBU R128 integrated loudness, LRA, true peak (target for gameplay: -16 .. -18 LUFS, TP <= -1 dBTP)
  - clipped samples (|x| >= 0.999) and the longest silent gap (< -50 dBFS for >= 1 s)
  - short-term loudness every 5 s (where the mix drops out or jumps)
  - footstep alignment: every `STEPFRAME <frame> <surface>` in --log (AUDIO_STEP_LOG=1) becomes t = frame / fps - start;
    the nearest audio onset (200 Hz high-passed envelope rise) within +-120 ms is reported, and stills of 6 steps
    (<out_dir>/step_*.jpg) are written to check the foot is planted on the frame the step sounds.
Needs ffmpeg / ffprobe and numpy.
"""
from __future__ import annotations

import argparse
import re
import subprocess
from pathlib import Path

import numpy as np

SR = 48000


def run(cmd, data=None):
    return subprocess.run(cmd, input=data, capture_output=True, check=False)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("movie")
    ap.add_argument("out")
    ap.add_argument("--log", default="")
    ap.add_argument("--start", type=float, default=0.0, help="seconds cut from the head of the movie (record_slice SS)")
    ap.add_argument("--fps", type=float, default=30.0)
    a = ap.parse_args()
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    lines: list[str] = []

    def say(s: str) -> None:
        print(s)
        lines.append(s)

    pr = run(["ffprobe", "-v", "error", "-select_streams", "a", "-show_entries", "stream=codec_name,sample_rate,channels",
              "-of", "csv=p=0", a.movie]).stdout.decode().strip()
    say(f"audio stream: {pr or 'NONE'}")
    if not pr:
        (out / "audio_gate.txt").write_text("\n".join(lines))
        raise SystemExit(1)
    eb = run(["ffmpeg", "-nostats", "-i", a.movie, "-vn", "-af", "ebur128=peak=true", "-f", "null", "-"]).stderr.decode(errors="ignore")
    summ = eb[eb.rfind("Summary:"):]
    get = lambda rx: (re.search(rx, summ) or [None, "nan"])[1]
    integ, lra, tp = float(get(r"I:\s*(-?[\d.]+|-inf) LUFS")), float(get(r"LRA:\s*(-?[\d.]+) LU")), float(get(r"Peak:\s*(-?[\d.]+|-inf) dBFS"))
    ok_l = -18.5 <= integ <= -15.5
    say(f"integrated {integ:.1f} LUFS ({'PASS' if ok_l else 'FAIL'}: -16..-18), LRA {lra:.1f} LU, true peak {tp:.1f} dBTP "
        f"({'PASS' if tp <= -1.0 else 'FAIL'}: <= -1)")
    st = [(float(t), float(s)) for t, s in re.findall(r"t:\s*([\d.]+).*?S:\s*(-?[\d.]+)", eb)]
    raw = run(["ffmpeg", "-v", "error", "-i", a.movie, "-vn", "-ac", "2", "-ar", str(SR), "-f", "f32le", "-"]).stdout
    x = np.frombuffer(raw, dtype=np.float32).reshape(-1, 2)
    clipped = int((np.abs(x) >= 0.999).sum())
    say(f"clipped samples: {clipped} ({'PASS' if clipped == 0 else 'FAIL'})")
    mono = x.mean(axis=1)
    win = int(0.05 * SR)
    rms = np.sqrt(np.convolve(mono * mono, np.ones(win) / win, mode="same")[::win] + 1e-12)
    quiet = 20 * np.log10(rms) < -50.0
    longest = cur = 0
    for q in quiet:
        cur = cur + 1 if q else 0
        longest = max(longest, cur)
    say(f"longest gap below -50 dBFS: {longest * 0.05:.2f} s ({'PASS' if longest * 0.05 < 1.0 else 'FAIL'}: < 1 s)")
    marks = {}
    for t, v in st:
        marks.setdefault(int(t // 5) * 5, v)
    say("short-term loudness every 5 s (t: LUFS-S): " + ", ".join(f"{t}:{v:.0f}" for t, v in sorted(marks.items())))

    if a.log and Path(a.log).exists():
        steps = [(int(f), s) for f, s in re.findall(r"STEPFRAME (\d+) (\w+)", Path(a.log).read_text(errors="ignore"))]
        # onset envelope: 200 Hz high-pass (drops the ambience bed rumble), 5 ms rms, positive slope
        hp = run(["ffmpeg", "-v", "error", "-i", a.movie, "-vn", "-ac", "1", "-ar", str(SR), "-af", "highpass=f=200",
                  "-f", "f32le", "-"]).stdout
        y = np.frombuffer(hp, dtype=np.float32)
        w5 = int(0.005 * SR)
        env = np.sqrt(np.convolve(y * y, np.ones(w5) / w5, mode="same") + 1e-12)
        rise = np.diff(20 * np.log10(env[::w5]), prepend=-120.0)
        offs = []
        dur = len(y) / SR
        for f, surf in steps:
            t = f / a.fps - a.start
            if t < 0.2 or t > dur - 0.2:
                continue
            i0, i1 = int((t - 0.12) * SR / w5), int((t + 0.12) * SR / w5)
            seg = rise[i0:i1]
            if len(seg) == 0:
                continue
            k = int(np.argmax(seg))
            offs.append(((i0 + k) * w5 / SR - t, t, surf, float(seg[k])))
        if offs:
            d = np.array([o[0] for o in offs]) * 1000.0
            strong = np.array([o[3] for o in offs]) > 3.0
            say(f"footsteps logged {len(steps)}, in movie {len(offs)}; onset found (>3 dB rise) {int(strong.sum())}; "
                f"offset audio-vs-step median {np.median(d[strong]) if strong.any() else float('nan'):.0f} ms, "
                f"p90 |offset| {np.percentile(np.abs(d[strong]), 90) if strong.any() else float('nan'):.0f} ms")
            surfs: dict[str, int] = {}
            for o in offs:
                surfs[o[2]] = surfs.get(o[2], 0) + 1
            say(f"step surfaces: {surfs}")
            for j, o in enumerate(offs[:: max(1, len(offs) // 6)][:6]):
                run(["ffmpeg", "-v", "error", "-y", "-ss", f"{o[1]:.3f}", "-i", a.movie, "-frames:v", "1",
                     "-vf", f"scale=640:-1,drawtext=fontfile='C\\:/Windows/Fonts/arial.ttf':text='step {o[2]} t={o[1]:.2f}s off={o[0]*1000:.0f}ms':x=6:y=6:fontsize=18:fontcolor=yellow:box=1:boxcolor=black@0.6",
                     str(out / f"step_{j}.jpg")])
        else:
            say("footsteps: no STEPFRAME lines inside the movie")
    (out / "audio_gate.txt").write_text("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
