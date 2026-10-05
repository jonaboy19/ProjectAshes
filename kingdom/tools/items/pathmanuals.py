"""Path manuals: one item per manual of the power trees (data/powers/*.json) and of cultivation.json up to realm 3
(Region 1). Reading one teaches the manual to the character (power_paths.learn_manual / cultivation.learn_manual).
Sources decide where they turn up: academy and sect_hall manuals are sold (bookseller, sect and academy shops),
teacher manuals are only handed out by the teacher who teaches them (scripts/abilities/path_teachers.gd), dungeon
manuals drop from dungeons, towers and bosses and are written in old script (the reader must know glyphs)."""
import json
import os
from core import add, DATA

F = "misc"
PATHS = ["magic", "bending", "sect", "knight", "beast"]
TINT = {"magic": "#9ec8ff", "bending": "#8fe0d0", "sect": "#f0d48a", "knight": "#cfd6e4", "beast": "#b8e08a"}
PRICE = {1: 90, 2: 420, 3: 1500}
SRC_MULT = {"academy": 1.0, "sect_hall": 1.0, "teacher": 1.4, "dungeon": 1.8, "tower": 2.5}
RARITY = {"academy": 1, "sect_hall": 1, "teacher": 2, "dungeon": 3, "tower": 3}
OLD_GLYPHS = {"dungeon": 3, "tower": 6}
LEVEL_GATE = {1: 1, 2: 10, 3: 30}
MANUALS = []          # item ids


def load(name):
    with open(os.path.join(DATA, name)) as f:
        return json.load(f)


def build():
    cult = load("progression/cultivation.json")
    tech_realm = {t["id"]: (t["realm"], t["stage"]) for t in cult["techniques"]}
    seen = {}
    for m in cult["manuals"]:
        seen[m["id"]] = dict(m)
    techs = {}
    for p in PATHS:
        d = load("powers/%s.json" % p)
        for t in d["techniques"]:
            techs[t["id"]] = t
            tech_realm.setdefault(t["id"], (t["req"]["realm"], t["req"]["stage"]))
        for m in d["manuals"]:
            mm = dict(m)
            mm["path"] = p
            seen[m["id"]] = mm
    for mid, m in seen.items():
        realm = int(m["realm"])
        if realm > 3:
            continue          # Region 2 and later
        path = m["path"]
        src = m.get("source", "academy")
        level = LEVEL_GATE[realm]
        names = []
        for tid in m.get("techniques", []):
            names.append(techs.get(tid, {}).get("name", tid.replace("_", " ")))
            r, s = tech_realm.get(tid, (realm, 1))
            level = max(level, LEVEL_GATE[r] + (8 if r == 1 else 18 if r == 2 else 24) * (s - 1) // 8)
        iid = "pm_" + mid
        add(iid, m["name"], "manual", F, price=int(PRICE[realm] * SRC_MULT.get(src, 1.0)), stack=1, weight=0.5,
            rarity=RARITY.get(src, 1), level=min(level, 56),
            desc=("%s Reading it teaches the %s path's lesson: %s." % (m.get("desc", ""), path, ", ".join(names) if names else "the feel of the aura")).strip(),
            tint=TINT[path], glyph="fam:book", type="path_manual", power_manual=mid, power_path=path, power_source=src,
            power_realm=realm, teaches=m.get("techniques", []) or None, old_script=OLD_GLYPHS.get(src, 0) or None,
            consumable=False, req_level=min(level, 56))
        MANUALS.append(iid)
