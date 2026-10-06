"""Region 1 quest-reward limits (package C13, docs/regions/BALANCE_R1.md), one rule set for the generator and the data pass.

  1. The honest path of a quest pays at most HONEST_CAP gold (stage reward + quest reward together).
  2. A corrupt path (the bribe, the hush money) pays at most CORRUPT_PREMIUM x the honest path and at most CORRUPT_CAP: crime pays a
     little better, never 3x better (Thornfield's culprit paid 60 against 20).
  3. A town's honest paths add up to at most TOWN_CAP (80) gold, so no town is a gold mine (Ironmarch, Saltwick, Kingsreach and Thornfield
     were two sigma above the other 26).
`balance_town(quests, town)` edits a town's quest dictionaries in place and is idempotent. gen_town.py applies it to every generated
town; balance_rewards.py applies it to the files on disk (the hand-made Thornfield line included).
"""

HONEST_CAP = 32
CORRUPT_PREMIUM = 1.35
CORRUPT_CAP = 42
TOWN_CAP = 80


def end_stages(q):
    ends = [s for s in q["stages"] if s.get("end")]
    return ends if ends else [q["stages"][-1]]


def own_rep(st, town):
    return int((st.get("rewards") or {}).get("rep", {}).get(town, 0))


def path_gold(q, st):
    return int((q.get("rewards") or {}).get("gold", 0)) + int((st.get("rewards") or {}).get("gold", 0))


def honest_end(q, town):
    return max(end_stages(q), key=lambda s: own_rep(s, town))


def set_gold(q, st, total):
    """Make the path pay `total` by scaling its two components (quest-level and stage-level) together (never raises a reward)."""
    qg = int((q.get("rewards") or {}).get("gold", 0))
    sg = int((st.get("rewards") or {}).get("gold", 0))
    cur = qg + sg
    if cur <= 0 or total >= cur:
        return
    if qg:
        q["rewards"]["gold"] = max(1, int(round(qg * total / cur)))
    if sg:
        st["rewards"]["gold"] = max(1, int(round(sg * total / cur)))
        if qg == 0:
            st["rewards"]["gold"] = total


def town_total(quests, town):
    return sum(path_gold(q, honest_end(q, town)) for q in quests)


def _clamp_corrupt(q, town):
    hon = honest_end(q, town)
    h = path_gold(q, hon)
    for st in end_stages(q):
        if st is hon:
            continue
        limit = min(int(h * CORRUPT_PREMIUM), CORRUPT_CAP)
        if path_gold(q, st) > limit:
            set_gold(q, st, limit)


def balance_town(quests, town):
    for q in quests:
        hon = honest_end(q, town)
        if path_gold(q, hon) > HONEST_CAP:
            set_gold(q, hon, HONEST_CAP)
        _clamp_corrupt(q, town)
    total = town_total(quests, town)
    if total > TOWN_CAP:
        k = TOWN_CAP / float(total)
        for q in quests:
            if (q.get("rewards") or {}).get("gold"):
                q["rewards"]["gold"] = max(1, int(round(q["rewards"]["gold"] * k)))
            for st in q["stages"]:
                if (st.get("rewards") or {}).get("gold"):
                    st["rewards"]["gold"] = max(1, int(round(st["rewards"]["gold"] * k)))
        for q in quests:
            _clamp_corrupt(q, town)            # the scaling rounds each path on its own: keep the corrupt premium at its limit
    return quests
