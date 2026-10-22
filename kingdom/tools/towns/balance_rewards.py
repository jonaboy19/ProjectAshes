"""Region 1 quest-reward balance pass over the files on disk (package C13, docs/regions/BALANCE_R1.md). Run from `kingdom/`.
The rules live in reward_balance.py (the generator applies the same ones, so a regeneration keeps them); this applies them to every
data/quests/<town>/<quest>.json, the hand-made Thornfield line included, rewriting only files that change (json indent=1, trailing
newline, the generator's format). Idempotent."""
import glob
import json
import os
import statistics
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import reward_balance as RB  # noqa: E402


def main():
    towns = sorted(os.listdir("data/quests"))
    changed = 0
    report = []
    for town in towns:
        files = sorted(glob.glob("data/quests/%s/*.json" % town))
        quests = [json.load(open(f)) for f in files]
        before = RB.town_total(quests, town)
        RB.balance_town(quests, town)
        report.append((town, before, RB.town_total(quests, town)))
        for f, q in zip(files, quests):
            new = json.dumps(q, indent=1, ensure_ascii=False) + "\n"
            if new != open(f).read():
                open(f, "w").write(new)
                changed += 1
    b = [r[1] for r in report]
    a = [r[2] for r in report]
    print("towns: %d, files rewritten: %d" % (len(report), changed))
    print("town honest-path gold total: mean %.1f sd %.1f max %d -> mean %.1f sd %.1f max %d" % (
        statistics.mean(b), statistics.pstdev(b), max(b), statistics.mean(a), statistics.pstdev(a), max(a)))
    for t, x, y in sorted(report, key=lambda r: -r[1])[:6]:
        print("  %-12s %3d -> %3d" % (t, x, y))


if __name__ == "__main__":
    main()
