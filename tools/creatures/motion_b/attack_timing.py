"""Attack timing from metrics json: impact = frame of peak hand speed (the fastest extremity), strike = consecutive frames above
50 % of that peak, anticipation = impact minus first frame where hand height/hips start to move away from the start pose by > 5 % of body height.
usage: python attack_timing.py <creature> <height_m>"""
import json, sys, numpy as np
T = "C:/Users/Jonna/AppData/Local/Temp/cm/"; c = sys.argv[1]; H = float(sys.argv[2])
CLIPS = {"goblin": ["attack"], "orc": ["attack", "attack_charged"], "troll": ["attack", "slam"]}[c]
for tag in ("before", "after"):
    d = json.load(open(T + f"{c}_{tag}.json"))
    for n in CLIPS:
        p = d[n]["pos"]; N = len(p["Hips"])
        sp = {}
        for h in ("RightHand", "LeftHand"):
            a = np.array(p[h]); sp[h] = np.r_[0, np.linalg.norm(np.diff(a, axis=0), axis=1)] * 30
        tot = np.maximum(sp["RightHand"], sp["LeftHand"])
        start = 0
        if n == "attack_charged": start = 103            # skip the untouched kneel + stand-up
        k = start + int(np.argmax(tot[start:])); pk = tot[k]
        s0 = k
        while s0 > start and tot[s0 - 1] > 0.5 * pk: s0 -= 1
        s1 = k
        while s1 < N - 1 and tot[s1 + 1] > 0.5 * pk: s1 += 1
        hz = np.array(p["RightHand"])[:, 2]; hips = np.array(p["Hips"])
        dev = np.linalg.norm(np.array(p["RightHand"]) - np.array(p["RightHand"])[start], axis=1) + np.linalg.norm(hips - hips[start], axis=1)
        a0 = start + int(np.argmax(dev[start:] > 0.05 * H))
        print(f"{c:7s} {tag:6s} {n:15s} dur {(N-1)/30:.2f}s  windup starts {(a0-1)/30:.2f}s  strike {(s0-1)/30:.2f}-{(s1-1)/30:.2f}s ({s1-s0+1} frames >50% peak)  impact(peak hand speed {pk:.1f} m/s) {(k)/30:.2f}s(frame {k+1})  anticipation start->strike {((s0-a0)/30):.2f}s  hips z min {hips[:,2].min():.2f} (start {hips[start,2]:.2f}); hand min z {min(np.array(p['RightHand'])[:,2].min(), np.array(p['LeftHand'])[:,2].min()):.2f}; mesh min z {min(d[n]['minz'][start:]):.3f}")
