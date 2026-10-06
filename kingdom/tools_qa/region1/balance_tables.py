#!/usr/bin/env python3
"""Markdown tables for docs/regions/BALANCE_R1.md from two balance_run.gd runs (before / after) and the probe JSON.

  python3 tools_qa/region1/balance_tables.py --dir /tmp/claude-0/balance_r1 --before before3 --after after1 [--probe after1]

Reads <dir>/<tag>_summary_<arch>.json (one per archetype, 3 seeds each) and <dir>/<tag>_<arch>_s<seed>.csv. No dependencies.
"""
import argparse
import csv
import glob
import json
import os
import statistics

ARCHS = ["farmer", "soldier", "wardwright", "merchant", "adventurer"]
TARGETS = {"house_max": 25, "top_rank_min": 60, "soul": (3, 4), "rank": (4, 5), "gear": (2, 2), "level_min": 13, "fed_min": 0.9}


def load(d, tag):
    out = {}
    for a in ARCHS:
        f = os.path.join(d, "%s_summary_%s.json" % (tag, a))
        out[a] = json.load(open(f)) if os.path.exists(f) else []
    return out


def csv_rows(d, tag, a, s):
    f = os.path.join(d, "%s_%s_s%d.csv" % (tag, a, s))
    return list(csv.DictReader(open(f))) if os.path.exists(f) else []


def growth(d, tag, a, seeds):
    g1, g2, g3 = [], [], []
    for s in seeds:
        rows = csv_rows(d, tag, a, s)
        if len(rows) < 100:
            continue
        g = [int(r["gold"]) for r in rows]
        g1.append((g[29] - g[0]) / 29.0)
        g2.append((g[59] - g[29]) / 30.0)
        g3.append((g[99] - g[59]) / 40.0)
    if not g1:
        return (0, 0, 0)
    return (statistics.mean(g1), statistics.mean(g2), statistics.mean(g3))


def mean(xs):
    xs = [x for x in xs if x is not None]
    return statistics.mean(xs) if xs else None


def fmt(x, nd=0):
    if x is None:
        return "-"
    return ("%." + str(nd) + "f") % x


def summarize(runs):
    if not runs:
        return None
    r = {}
    r["gold"] = mean([x["gold"] for x in runs])
    r["house"] = [x["first_day"].get("house") for x in runs]
    r["rank"] = [x["career_rank"] for x in runs]
    r["rank_count"] = runs[0].get("rank_count", 0)
    r["rank_name"] = runs[0].get("career_rank_name", "")
    r["rank_top"] = [x["first_day"].get("rank_top") for x in runs]
    r["soul"] = [x["soul_tier"] for x in runs]
    r["gear"] = [x["gear_tier"] for x in runs]
    r["level"] = [x["level"] for x in runs]
    r["deaths"] = mean([x["deaths"] for x in runs])
    r["fed"] = mean([x["fed_share"] for x in runs])
    inc = {}
    for x in runs:
        for k, v in x["income"].items():
            inc[k] = inc.get(k, 0) + v / float(len(runs))
    r["income"] = inc
    r["peak"] = mean([x["gold_peak"] for x in runs])
    return r


def rng(xs):
    xs = [x for x in xs if x is not None]
    if not xs:
        return "-"
    lo, hi = min(xs), max(xs)
    return str(lo) if lo == hi else "%s-%s" % (lo, hi)


def ok(vals, lo, hi):
    vs = [v for v in vals if v is not None]
    return bool(vs) and all(lo <= v <= hi for v in vs)


def table(d, tag):
    runs = load(d, tag)
    lines = ["| Archetype | First house (day) | Career rank at day 100 | Top rank first reached (day) | Soul tier | Gear tier | Level | Gold at 100 | Earned per day (gross) | Net gold per day (1-30 / 31-60 / 61-100) | Deaths | Fed |",
             "|---|---|---|---|---|---|---|---|---|---|---|---|"]
    for a in ARCHS:
        s = summarize(runs[a])
        if s is None:
            lines.append("| %s | (no run) ||||||||||| " % a)
            continue
        seeds = list(range(1, len(runs[a]) + 1))
        g = growth(d, tag, a, seeds)
        rank = "%s of %d (%s)" % (rng(s["rank"]), s["rank_count"], s["rank_name"]) if s["rank_count"] else "none"
        earned = sum(v for k, v in s["income"].items()) / 100.0
        lines.append("| %s | %s | %s | %s | %s | %s | %s | %s | %s | %s / %s / %s | %s | %s%% |" % (
            a, rng(s["house"]), rank, rng(s["rank_top"]), rng(s["soul"]), rng(s["gear"]), rng(s["level"]), fmt(s["gold"]), fmt(earned),
            fmt(g[0]), fmt(g[1]), fmt(g[2]), fmt(s["deaths"], 1), fmt(100.0 * (s["fed"] or 0))))
    return "\n".join(lines)


def income_table(d, tag):
    runs = load(d, tag)
    lines = ["| Archetype | Gold earned in 100 days by source (mean of the seeds) |", "|---|---|"]
    for a in ARCHS:
        s = summarize(runs[a])
        if s is None:
            continue
        items = sorted(s["income"].items(), key=lambda kv: -kv[1])
        total = sum(v for _, v in items) or 1
        lines.append("| %s | %s (total %d) |" % (a, ", ".join("%s %d" % (k, v) for k, v in items if v >= 0.03 * total), total))
    return "\n".join(lines)


def targets_table(d, tag):
    runs = load(d, tag)
    t = TARGETS
    lines = ["| Target | " + " | ".join(ARCHS) + " |", "|---|" + "---|" * len(ARCHS)]
    rows = {
        "First house within 25 days": lambda s: ok(s["house"], 0, t["house_max"]),
        "Top rank not before day 60": lambda s: all((x is None) or x >= t["top_rank_min"] for x in s["rank_top"]),
        "Soul tier 3-4": lambda s: ok(s["soul"], *t["soul"]),
        "Career rank 4-5": lambda s: ok(s["rank"], *t["rank"]),
        "Gear tier 2": lambda s: ok(s["gear"], *t["gear"]),
        "Level 13+": lambda s: all(x >= t["level_min"] for x in s["level"]),
        "Fed 90%+ of days": lambda s: (s["fed"] or 0) >= t["fed_min"],
    }
    for name, fn in rows.items():
        cells = []
        for a in ARCHS:
            s = summarize(runs[a])
            cells.append("-" if s is None else ("yes" if fn(s) else "NO"))
        lines.append("| %s | %s |" % (name, " | ".join(cells)))
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default="/tmp/claude-0/balance_r1")
    ap.add_argument("--before", default="before3")
    ap.add_argument("--after", default="after1")
    a = ap.parse_args()
    print("### Before (the game as it was, %s)\n" % a.before)
    print(table(a.dir, a.before))
    print("\n" + targets_table(a.dir, a.before))
    print("\n" + income_table(a.dir, a.before))
    print("\n### After (%s)\n" % a.after)
    print(table(a.dir, a.after))
    print("\n" + targets_table(a.dir, a.after))
    print("\n" + income_table(a.dir, a.after))


if __name__ == "__main__":
    main()
