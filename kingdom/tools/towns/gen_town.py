#!/usr/bin/env python3
"""Generates a town-kit file for a Region 1 settlement (scripts/world/town_kit/town_data.gd), deterministically.

  python3 tools/towns/gen_town.py Millbrook Redwater          # write data/region1/towns/<id>.json, data/quests/<id>/*.json, dialogue/<id>/*.json
  python3 tools/towns/gen_town.py --all --dry-run             # build every settlement in memory (what the name allocator needs) and print a summary
  python3 tools/towns/gen_town.py Millbrook --check           # exit 1 when the files on disk differ from what the generator makes now
  Run from kingdom/. Options: --seed N (default 1066, the world seed).

Inputs:  data/world/town_identity.json (archetype + flavour per settlement), data/region1/world/settlements.json (trade, landmark,
         named NPC, rumours), data/region1/world/settlement_facts.json (kind, population, radius, house lots: runtime layout facts).
Output per town:
  * a roster of 10-25 named residents (role by archetype, traits, ties, 3-4 dialogue lines each) whose names are unique across the whole
    region (the allocator builds every settlement in id order, so a town's names never depend on which towns were asked for);
  * the required lots by kind (village: tavern, smithy, general shop; town: plus bakery, healer, guard post; a village whose identity says
    bakehouse/herbs/watch gets that lot too);
  * a local threat from the region plan's creature list (scripts/world/town_kit/town_threat.gd SPECIES), a den ring and night probes;
  * a three-quest line from the quest library (TalkTo, GoTo, Collect, Deliver, Investigate, Choose, Kill) the kit can wire by itself:
    kit-placed clues and a stash for the Collect stage, places for the GoTo and Kill stages;
  * dialogue files in dialogue_runner format (scripts/sim/dialogue_runner.gd), one per resident.
Everything is a pure function of (seed, settlement), so re-running changes nothing."""
import argparse
import hashlib
import json
import math
import os
import random
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import town_text as T  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))       # kingdom/
KINDS_TOWN = ("town", "frontier_town", "castle")
MAX_NAMES = 25
CAST_RESERVED = """Maren Coldbrook|Bram Hollis|Idra Vell|Odrin Thale|Rowan Ashby|Envoy Lucan|Harrok Ashmaw|Snikkit|Imra Solvane|Tamsin Reeve|Wren Coldbrook|
Corin Vesk|Gilda Pennick|Aldric""".replace("\n", "").split("|")
LOT_ASSET = {"tavern": "inn", "smithy": "blacksmith", "general_shop": "mhouse_trader", "bakery": "house_town_b", "guard_post": "house_13", "healer": "healer_house"}
LOT_KEEPER = {"tavern": "innkeeper", "smithy": "blacksmith", "general_shop": "shopkeeper", "bakery": "baker", "healer": "herbalist", "guard_post": "guard captain"}
THREAT_COUNT = {"wolf": [2, 3], "ghoul": [1, 2], "bog_toad": [2, 3], "giant_wasp": [3, 4], "corrupted_wolf": [2, 3]}


def jload(rel):
    with open(os.path.join(ROOT, rel)) as f:
        return json.load(f)


def seeded(seed, *parts):
    h = hashlib.sha256((":".join([str(seed)] + [str(p) for p in parts])).encode()).hexdigest()
    return random.Random(int(h[:16], 16))


def slug(s):
    return re.sub(r"[^a-z0-9]+", "_", s.lower()).strip("_")


def first_of(name):
    return name.split(" ")[0]


# ----------------------------------------------------------------------------------------------- inputs

class World:
    def __init__(self):
        self.identity = jload("data/world/town_identity.json")["towns"]
        self.settlements = jload("data/region1/world/settlements.json")["settlements"]
        self.facts = {f["name"]: f for f in jload("data/region1/world/settlement_facts.json")["settlements"]}
        self.by_name = {s["name"]: s for s in self.settlements}
        self.order = [f["name"] for f in sorted(self.facts.values(), key=lambda f: f["id"])]
        self.reserved_names, self.reserved_first, self.reserved_last = self._reserved()

    def _reserved(self):
        full = set(CAST_RESERVED)
        for s in self.settlements:
            full.add(s["npc"]["name"])
        th = jload("data/region1/towns/thornfield.json")
        for r in th["residents"]:
            full.add(r["name"])
        firsts = {first_of(n) for n in full}
        lasts = {n.split(" ")[-1] for n in full if " " in n}
        return full, firsts, lasts


def town_id(name):
    return slug(name)


# ----------------------------------------------------------------------------------------------- names

def alloc_names(world, name, rng, used):
    """25 full names for a town, unique against `used` (every name allocated so far plus the reserved cast); first names and surnames
    are also distinct inside the town and avoid the cast's."""
    arch = world.identity[name]["arch"]
    firsts = [x for x in T.FIRST if x not in world.reserved_first]
    lasts = [x for x in T.SURNAMES if x not in world.reserved_last]
    rng.shuffle(firsts)
    rng.shuffle(lasts)
    local = list(T.ARCH_SURNAMES.get(arch, []))
    rng.shuffle(local)
    lasts = local[:3] + lasts
    out = []
    taken_f = set()
    taken_l = set()
    k = 0
    while len(out) < MAX_NAMES:
        if k > 8000:
            raise RuntimeError("name pool exhausted for " + name)
        f = firsts[k % len(firsts)]
        l = lasts[(k * 5 + k // len(firsts)) % len(lasts)]
        k += 1
        full = "%s %s" % (f, l)
        if full in used or f in taken_f or l in taken_l:
            continue
        taken_f.add(f)
        taken_l.add(l)
        used.add(full)
        out.append(full)
    return out


# ----------------------------------------------------------------------------------------------- roster

def lots_for(world, name):
    f = world.facts[name]
    ident = world.identity[name]
    s = world.by_name[name]
    types = list(["tavern", "smithy", "general_shop"])
    text = (ident.get("flavour", "") + " " + s.get("trade", "")).lower()
    if f["kind"] in KINDS_TOWN:
        types += ["bakery", "healer", "guard_post"]
    else:
        if "bake" in text:
            types.append("bakery")
        if "herb" in text or ident["arch"] == "religious":
            types.append("healer")
        if ident["arch"] == "fortress" or "watch" in text:
            types.append("guard_post")
    return types


def roster_size(f):
    return max(10, min(25, 9 + f["population"] // 30))


def worker_roles(arch, count, rng):
    pool = []
    for role, w in T.ARCHS[arch]["workers"]:
        pool += [role] * w
    out = []
    i = rng.randrange(len(pool))
    while len(out) < count:
        out.append(pool[i % len(pool)])
        i += 1
    return out


def schedule_for(kind, rng, night=False):
    def r(a, b):
        return round(rng.uniform(a, b) * 2) / 2.0
    ev = rng.random()
    evening = []
    if kind == "day":
        a, b = r(5, 7), r(16, 18.5)
        sched = [{"from": a, "to": b, "phase": "work"}]
        if night:
            sched = [{"from": 21, "to": 6, "phase": "work"}]
        elif ev < 0.35:
            evening = [{"from": b, "to": r(19, 20), "phase": "inn"}]
        elif ev < 0.6:
            evening = [{"from": b, "to": r(18.5, 19.5), "phase": "market"}]
        elif ev < 0.8:
            evening = [{"from": b, "to": r(18, 19), "phase": "social"}]
        return sched + evening
    if kind == "dawn":
        a, b = r(4, 5), r(14, 15.5)
        return [{"from": a, "to": b, "phase": "work"}, {"from": b, "to": r(18, 19), "phase": "inn" if ev < 0.5 else "social"}]
    if kind == "early":
        return [{"from": 3.5, "to": 12.5, "phase": "work"}, {"from": 12.5, "to": 14, "phase": "market"}]
    if kind == "shop":
        return [{"from": r(7, 8), "to": r(18, 19), "phase": "work"}]
    if kind == "inn":
        return [{"from": 10, "to": 24, "phase": "work"}, {"from": 0, "to": 10, "phase": "home"}]
    if kind == "reeve":
        return [{"from": 8, "to": 17, "phase": "work"}]
    if kind == "elder":
        return [{"from": 9, "to": 12, "phase": "social"}, {"from": 14, "to": 17, "phase": "temple" if ev < 0.5 else "social"}]
    if kind == "kid":
        return [{"from": 8, "to": 12, "phase": "market" if ev < 0.5 else "social"}, {"from": 14, "to": 18, "phase": "social"}]
    if kind == "temple":
        return [{"from": 6, "to": 9, "phase": "temple"}, {"from": 9, "to": 17, "phase": "work"}, {"from": 17.5, "to": 18.5, "phase": "temple"}]
    return [{"from": 8, "to": 17, "phase": "work"}]


def build_roster(world, name, names, rng, lots, used):
    f = world.facts[name]
    ident = world.identity[name]
    arch = ident["arch"]
    tid = town_id(name)
    n = roster_size(f)
    town = f["kind"] in KINDS_TOWN
    kids = min(f["kid_rows"], 1 if f["population"] < 150 else (2 if f["population"] < 600 else 3))
    elders = 2 if town else 1
    keepers = [LOT_KEEPER[t] for t in lots]
    guards = 2 if "guard_post" in lots else 0
    roles = ["reeve" if T.ARCHS[arch]["authority"] == "reeve" else "reeve"] + keepers + ["guard"] * guards + ["elder"] * elders
    fill = n - len(roles) - kids
    roles += worker_roles(arch, max(fill, 0), rng)
    roles += ["child"] * kids
    roles = roles[:n]
    # work and home assignment
    house_cap = max(2, f["house_lots"] - len(lots) - 1)
    housed_roles = [i for i, r in enumerate(roles) if r not in ("child", "innkeeper", "herbalist", "guard captain")]
    n_homes = min(len(housed_roles), house_cap, 18)
    home_of = {}
    for k, i in enumerate(housed_roles):
        home_of[i] = "%s_house_%d" % (tid, (k % n_homes) + 1)
    residents = []
    work_for = {"innkeeper": "tavern", "blacksmith": "smithy", "shopkeeper": "general_shop", "baker": "bakery", "herbalist": "healer", "guard captain": "guard_post"}
    adults = [i for i, r in enumerate(roles) if r != "child"]
    night_guard_given = False
    name_i = 0
    used_first = set()
    for i, role in enumerate(roles):
        job, kind, greet, rum = T.ROLES[role]
        full = names[name_i]
        name_i += 1
        e = {"id": slug(full), "name": full, "role": role, "job": job}
        e["_kind"] = kind
        if role == "child":
            elig = [x for x in adults if roles[x] not in ("innkeeper", "herbalist", "guard captain", "guard")]
            e["_parent"] = elig[(i * 7 + 3) % len(elig)]
        residents.append(e)
    # children take a parent's surname (and home, below); the full name stays unique region-wide
    for e in residents:
        if e["role"] != "child":
            continue
        last = residents[e["_parent"]]["name"].split(" ")[1]
        fr = first_of(e["name"])
        k = 0
        while "%s %s" % (fr, last) in used:
            fr = T.FIRST[(T.FIRST.index(fr) + 11) % len(T.FIRST)] if fr in T.FIRST else T.FIRST[k]
            k += 1
        used.discard(e["name"])
        e["name"] = "%s %s" % (fr, last)
        used.add(e["name"])
        e["id"] = slug(e["name"])
    for i, e in enumerate(residents):
        role = e["role"]
        if role in work_for and work_for[role] in lots:
            bid = "%s_%s" % (tid, {"tavern": "inn", "smithy": "smithy", "general_shop": "shop", "bakery": "bakery", "healer": "healer", "guard_post": "guard_post"}[work_for[role]])
            e["work"] = bid
            e["home"] = bid if role in ("innkeeper", "herbalist", "guard captain") else home_of.get(i, bid)
        elif role == "child":
            par = residents[e["_parent"]]
            e["home"] = par.get("home") or home_of.get(e["_parent"]) or "%s_house_1" % tid
            e["work"] = e["home"]
        elif role in ("reeve", "elder"):
            e["home"] = home_of.get(i, "%s_house_1" % tid)
            e["work"] = e["home"]
        elif role == "guard":
            e["home"] = home_of.get(i, "%s_house_1" % tid)
            e["work"] = "%s_guard_post" % tid if "guard_post" in lots else "%s_works" % tid
        else:
            e["home"] = home_of.get(i, "%s_house_1" % tid)
            e["work"] = "%s_works" % tid
        if role in work_for and work_for[role] not in lots:
            e["work"] = "%s_works" % tid
            e["home"] = home_of.get(i, "%s_house_1" % tid)
    # homes of children copy the parent's (parents are placed before the loop above finished)
    for e in residents:
        if e["role"] == "child":
            par = residents[e["_parent"]]
            e["home"] = par["home"]
            e["work"] = par["home"]
    for i, e in enumerate(residents):
        role = e["role"]
        job, kind, greet, rum = T.ROLES[role]
        night = False
        if role == "guard" and not night_guard_given:
            night = True
            night_guard_given = True
        e["age"] = rng.randint(7, 12) if role == "child" else (rng.randint(64, 82) if role == "elder" else rng.randint(23, 58))
        tr = rng.sample(T.TRAITS, 3 if rng.random() < 0.5 else 2)
        e["traits"] = [t.replace("-", " ") for t in tr]
        e["schedule"] = schedule_for(kind, rng, night)
        if role == "child":
            e["child"] = True
        e["_greet"] = greet
        e["_rum"] = rum
    return residents


def build_ties(residents, rng):
    """Edges (a, b, kind, value): children to a parent, colleagues, rivals, neighbours. Everyone gets at least one."""
    edges = []
    seen = set()

    def add(a, b, kind, value=None):
        if a == b or (a, b) in seen or (b, a) in seen:
            return
        seen.add((a, b))
        v = T.RELATIONS[kind][0] if value is None else value
        edges.append((a, b, kind, v + rng.choice([-3, 0, 0, 3])))

    by_id = {r["id"]: i for i, r in enumerate(residents)}
    for i, r in enumerate(residents):
        if r["role"] == "child":
            par = residents[r["_parent"]]
            add(r["id"], par["id"], "family")
    for i, r in enumerate(residents):
        same = [o for o in residents if o["id"] != r["id"] and o["work"] == r["work"] and o["role"] != "child"]
        if same and r["role"] != "child":
            add(r["id"], rng.choice(same)["id"], "colleague")
    keepers = [r for r in residents if r["role"] in ("blacksmith", "shopkeeper", "baker", "innkeeper")]
    for a in range(len(keepers) - 1):
        if rng.random() < 0.6:
            add(keepers[a]["id"], keepers[a + 1]["id"], "rival", rng.choice([-5, -4, -8]))
    homed = [r for r in residents if r["role"] != "child"]
    for a in range(len(homed) - 1):
        if homed[a]["home"] != homed[a + 1]["home"] and rng.random() < 0.35:
            add(homed[a]["id"], homed[a + 1]["id"], "neighbour")
    degree = {r["id"]: 0 for r in residents}
    for a, b, _, _ in edges:
        degree[a] += 1
        degree[b] += 1
    ids = [r["id"] for r in residents]
    for r in residents:
        if degree[r["id"]] == 0:
            other = rng.choice([x for x in ids if x != r["id"]])
            add(r["id"], other, "friend")
            degree[r["id"]] += 1
            degree[other] += 1
    return edges


def finish_people(world, name, residents, edges, rng, threat_noun="wolf"):
    s = world.by_name[name]
    town_rumours = list(s.get("rumours", []))
    by_id = {r["id"]: r for r in residents}
    rel = {r["id"]: {} for r in residents}
    for a, b, kind, v in edges:
        rel[a][b] = {"kind": kind, "value": v}
        rel[b][a] = {"kind": kind if kind != "mentor" else "student", "value": v}
    for i, r in enumerate(residents):
        r["relationships"] = {k: rel[r["id"]][k] for k in sorted(rel[r["id"]])}
    people = []
    for i, r in enumerate(residents):
        greet = r.pop("_greet")
        rum = r.pop("_rum")
        r.pop("_kind", None)
        r.pop("_parent", None)
        first_rel = next(iter(r["relationships"]))
        other = by_id[first_rel]
        kind = r["relationships"][first_rel]["kind"]
        pool = T.RELATIONS.get(kind, T.RELATIONS["friend"])[1]
        opinion = pool[(i + len(first_rel)) % len(pool)].format(o=first_of(other["name"]))
        def fill(t):
            return t.replace("{town}", name).replace("{Threat}", threat_noun.capitalize()).replace("{threat}", threat_noun)
        greeting = [fill(greet[(i * 3 + 1) % 2])]
        rumour = [fill(rum[(i + 1) % 2])]
        if r["role"] != "child" and town_rumours:
            rumour.append(town_rumours[i % len(town_rumours)])
        r["dialogue"] = {"greeting": greeting, "rumour": rumour, "opinions": {first_rel: opinion}}
        people.append(r)
    return people


# ----------------------------------------------------------------------------------------------- dialogue (dialogue_runner format)

def build_dialogue(tid, by_id, p):
    d = p["dialogue"]

    def q(x):
        return '"%s"' % x

    def first(pid):
        return by_id[pid]["name"].split(" ")[0] if pid in by_id else pid

    greet_lines = [
        {"text": "{first} looks you up and down and says nothing at all.", "if": {"tier": "enemy"}, "p": 5},
        {"text": q("You again. Say what you want and be quick about it."), "if": {"tier": "rival"}, "p": 5},
    ]
    for g in d["greeting"]:
        greet_lines.append({"text": q(g), "if": {"tier_not": ["enemy", "rival"]}, "p": 2})
    if p.get("child"):
        greet_lines.append({"text": q("Hm? Oh. Hello. Does your mother know where you are?"), "if": {"tier": "stranger", "child": False}, "p": 1})
    greet_lines.append({"text": q("{greeting}") + " {first} nods.", "if": {"tier": "stranger"}, "p": 1})
    greet_lines.append({"text": q("Well met, {player}."), "if": {"tier": ["friend", "close_friend"]}, "p": 3})
    greet = {"lines": greet_lines, "choices": [{"text": q("Heard any news?"), "goto": "rumour", "if": {"tier_not": ["enemy", "rival"]}}]}
    for oid in d["opinions"]:
        if oid in by_id:
            greet["choices"].append({"text": q("What do you make of %s?" % first(oid)), "goto": "op_" + oid, "if": {"tier_not": ["enemy", "rival"]}})
    greet["choices"].append({"text": "Offer a gift…", "goto": "", "if": {"has": "has_gift_items"}, "do": [["gift"]]})
    greet["choices"].append({"text": "\"Good day to you.\"", "goto": "@end"})
    nodes = {"greet": greet}
    rum_lines = [{"text": q(r), "p": 2} for r in d["rumour"]]
    rum_lines.append({"text": q("{rumour}"), "if": {"has": "rumour"}, "p": 1})
    rum_lines.append({"text": q("Nothing I would repeat."), "p": 0})
    nodes["rumour"] = {"lines": rum_lines, "choices": [
        {"text": q("Anything else?"), "goto": "rumour"},
        {"text": q("Thanks for telling me."), "goto": "greet", "do": [["opinion", "chat", "Pleasant talk", 2, 5]]}]}
    for oid, line in d["opinions"].items():
        nodes["op_" + oid] = {"lines": [{"text": q(line)}], "choices": [{"text": q("Go on."), "goto": "rumour"}, {"text": q("Thanks."), "goto": "greet"}]}
    return {"id": "%s/%s" % (tid, p["id"]), "start": "greet", "nodes": nodes}


# ----------------------------------------------------------------------------------------------- places, quests

def landmark_front(world, name):
    lm = world.by_name[name].get("landmark") or {}
    ys = [float(p[2]) for p in lm.get("parts", []) if isinstance(p, list) and len(p) > 2 and not str(p[0]).startswith("r1:")]
    return max(10.0, min(20.0, (max(ys) if ys else 8.0) + 3.0))


def build_town(world, name, names, seed, used):
    rng = seeded(seed, "town", name)
    f = world.facts[name]
    ident = world.identity[name]
    s = world.by_name[name]
    arch = ident["arch"] if ident["arch"] in T.ARCHS else "farming"
    kit = T.ARCHS[arch]
    tid = town_id(name)
    lots = lots_for(world, name)
    th_species = kit["threat"][rng.randrange(len(kit["threat"]))]
    residents = build_roster(world, name, names, rng, lots, used)
    edges = build_ties(residents, rng)
    people = finish_people(world, name, residents, edges, rng, T.THREAT_NAMES[th_species][0])
    by_id = {p["id"]: p for p in people}
    fy = landmark_front(world, name)
    lm_id = "landmark_" + name.lower()
    radius = f["radius"]
    ang = rng.uniform(0, math.tau)
    r_out = round(radius * 1.35)
    out_at = [round(r_out * math.cos(ang)), round(r_out * math.sin(ang))]
    homes = max(int(re.search(r"_house_(\d+)$", p["home"]).group(1)) for p in people if re.search(r"_house_(\d+)$", p["home"]))
    doc = {
        "version": 1,
        "_doc": "Generated by tools/towns/gen_town.py (seed %d) for %s. Edit freely or re-run; format: scripts/world/town_kit/town_data.gd." % (SEED_USED[0], name),
        "id": tid, "settlement": name, "kind": f["kind"], "population": f["population"],
        "dialogue_dir": tid,
        "identity": {"arch": arch, "flavour": ident.get("flavour", ""), "trade": s.get("trade", ""), "tagline": s.get("tagline", "")},
        "residents": people,
        "lots": {"required": [{"btype": t, "asset": LOT_ASSET[t], "bid": "%s_%s" % (tid, {"tavern": "inn", "smithy": "smithy", "general_shop": "shop", "bakery": "bakery", "healer": "healer", "guard_post": "guard_post"}[t])} for t in lots],
                 "homes": homes, "sites": {"%s_works" % tid: s["landmark"]["name"] if s.get("landmark") else name + " works"}},
        "anchors": {"town": {"kind": "settlement"}, "landmark": {"kind": "site", "r1id": lm_id}},
        "doors": {"%s_works" % tid: {"anchor": "landmark", "at": [0.0, round(fy, 1)]}},
        "places": [
            {"id": tid, "anchor": "town", "at": [0, 0], "radius": round(radius * 1.15)},
            {"id": "%s_works" % tid, "anchor": "landmark", "at": [0.0, round(fy - 3.0, 1)], "radius": 26},
            {"id": "%s_outskirts" % tid, "anchor": "town", "at": out_at, "radius": 40, "dry": True},
        ],
        "threat": {"species": th_species, "spawner": tid, "group": "%s_threat" % tid, "den_ring": [round(radius + 60), round(radius + 220)], "night": [22, 5],
                   "probe_chance": 55, "probe_place": "%s_outskirts" % tid, "probe_near": 240, "probe_count": THREAT_COUNT[th_species], "probe_from": 60,
                   "probe_territory": 70, "ambush_from": 22, "ambush_territory": 120},
    }
    lv = livestock_for(arch, radius, ang, rng)
    if lv:
        doc["livestock"] = {"groups": lv, "pens": []}
    quests, clues, stash = build_quests(world, name, tid, arch, kit, people, by_id, doc, th_species, fy, rng)
    doc["clues"] = clues
    doc["stashes"] = [stash]
    doc["quests"] = ["res://data/quests/%s/%s.json" % (tid, q["id"][len(tid) + 1:]) for q in quests]
    return doc, quests


def livestock_for(arch, radius, ang, rng):
    kinds = {"farming": [["cow", 2], ["chicken", 5]], "pastoral": [["sheep", 6], ["sheepdog", 1]], "religious": [["sheep", 3]], "hunting": [["dog", 2]]}.get(arch)
    if not kinds:
        return []
    out = []
    for k, grp in enumerate(kinds):
        a = ang + math.pi * (0.7 + 0.35 * k)
        r = radius * 1.2
        out.append({"anchor": "town", "at": [round(r * math.cos(a)), round(r * math.sin(a))], "kinds": [grp], "radius": 6.0, "tag": "%s" % grp[0]})
    return out


def pick(people, roles, rng, avoid=()):
    c = [p for p in people if p["role"] in roles and p["id"] not in avoid and p["role"] != "child"]
    if not c:
        c = [p for p in people if p["role"] not in ("child", "elder") and p["id"] not in avoid]
    return rng.choice(c)


def build_quests(world, name, tid, arch, kit, people, by_id, doc, species, fy, rng):
    giver = next(p for p in people if p["role"] == "reeve")
    gname = giver["name"]
    gfirst = first_of(gname)
    item, item_name, count = kit["item"]
    receiver = pick(people, [kit["deliver_role"], "shopkeeper", "baker"], rng, (giver["id"],))
    suspect = pick(people, kit["suspect"], rng, (giver["id"], receiver["id"]))
    sing, plur = T.THREAT_NAMES[species]
    works = kit["works"]
    thing = kit["thing"]
    n_kill = 3 if doc["kind"] in KINDS_TOWN else 2
    outskirts = "%s_outskirts" % tid
    reach_works = "%s_works" % tid

    def reward(gold, rep, rel, label, days=60):
        return {"gold": gold, "rep": {tid: rep}, "relationship": [{"npc": giver["id"], "label": label, "value": rel, "days": days}]}

    # --- A: errand (GoTo, Collect, Deliver, TalkTo)
    a_id = "%s_%s" % (tid, slug(kit["a_title"]))
    qa = {
        "id": a_id, "title": kit["a_title"],
        "summary": "%s wants %d %s from %s for %s, and then a word." % (gname, count, item_name, works, receiver["name"]),
        "giver": {"npc": giver["id"], "name": gname, "place": tid},
        "offer_text": "\"%s's short of %s again. The pile at %s is ours to take. Bring it to %s and tell me when it is done.\"" % (name, item_name, works, receiver["name"]),
        "turn_in_text": "\"Good. That is one thing in %s that goes right.\"" % name,
        "stages": [
            {"id": "fetch", "title": "Fetch the %s" % item_name, "mode": "sequence", "objectives": [
                {"id": "reach", "type": "goto", "place": reach_works, "text": "Go to %s" % works},
                {"id": "gather", "type": "collect", "item": item, "count": count, "text": "Take %d %s from the pile" % (count, item_name)}]},
            {"id": "deliver", "title": "Take it to %s" % receiver["name"], "mode": "all", "objectives": [
                {"id": "hand_over", "type": "deliver", "item": item, "count": count, "to": receiver["id"], "text": "Hand the %s to %s" % (item_name, receiver["name"])}]},
            {"id": "report", "title": "Tell %s" % gfirst, "mode": "all", "end": True, "objectives": [
                {"id": "report", "type": "talk_to", "npc": giver["id"], "text": "Tell %s it is done" % gname}]},
        ],
        "rewards": reward(14, 3, 8, "Ran an errand for the town", 45),
    }
    stash = {"id": "%s/stash/%s" % (tid, item), "item": item, "count": count, "anchor": "landmark", "at": [-4.0, round(fy - 4.0, 1)],
             "quest": a_id, "stage": "fetch", "target": kit["stash"][1], "say": kit["stash"][2], "prop": kit["stash"][0]}

    # --- B: investigation (Investigate, TalkTo, Choose)
    b_id = "%s_%s" % (tid, slug(kit["b_title"]))
    props = kit["theft"]
    notes = {
        "sack": "A sack by the door has been slit and sewn back up. It is lighter than it should be.",
        "tracks": "Boot prints, one heel worn down, coming and going. They stop where the lane meets %s." % works,
        "ledger": "Someone has re-inked a line of the count. The ink is newer than the page.",
        "lock": "The hasp was prised off and set back almost straight. The lock only looks shut.",
        "crate": "A crate lid, nailed back crooked. The nails are bright.",
    }
    targets = {"sack": "Slit sack", "tracks": "Muddy prints", "ledger": "Altered count", "lock": "Forced hasp", "crate": "Crooked crate"}
    spots = [("%s_shop" % tid, [1.4, 0.8]), ("%s_smithy" % tid, [-1.4, 0.8]), ("%s_inn" % tid, [1.4, -0.8])]
    lot_bids = {r["bid"] for r in doc["lots"]["required"]}
    spots = [sp for sp in spots if sp[0] in lot_bids]
    while len(spots) < 3:
        spots.append(("%s_house_%d" % (tid, len(spots) + 1), [1.2, 0.8]))
    clues = []
    for k, prop in enumerate(props):
        clues.append({"id": "%s/clue/%s" % (tid, prop), "building": spots[k][0], "at": spots[k][1], "h": 0.0, "target": targets[prop], "note": notes[prop], "prop": prop})
    sfirst = first_of(suspect["name"])
    qb = {
        "id": b_id, "title": kit["b_title"],
        "summary": "%s is gone from the stores of %s. %s wants to know whether it is carelessness or a person." % (thing.capitalize(), name, gname),
        "giver": {"npc": giver["id"], "name": gname, "place": tid}, "requires": [a_id],
        "offer_text": "\"%s is gone from the stores and I have counted twice. Look around the doors in town. Someone was careless, or someone was not.\"" % thing.capitalize(),
        "stages": [
            {"id": "look", "title": "Look for signs", "mode": "all", "objectives": [
                {"id": "clues", "type": "investigate", "text": "Search the doors around town for signs", "clues": [c["id"] for c in clues], "count": 3}]},
            {"id": "question", "title": "Ask %s" % sfirst, "mode": "all", "objectives": [
                {"id": "question", "type": "talk_to", "npc": suspect["id"], "text": "Ask %s what they know" % suspect["name"]}]},
            {"id": "decide", "title": "Decide what to do", "mode": "all", "objectives": [
                {"id": "verdict", "type": "choose", "npc": giver["id"], "options": [
                    {"id": "report", "text": "Tell %s what you found" % gfirst, "say": "%s nods slowly. \"Then it is on the record.\"" % gfirst},
                    {"id": "quiet", "text": "Take %s's quiet word and say nothing" % sfirst, "say": "%s presses a few coins into your hand. \"Good sense.\"" % sfirst}]}],
             "branches": {"report": "reported", "quiet": "hushed"}},
            {"id": "reported", "title": "%s hears it" % gfirst, "mode": "all", "end": True, "objectives": [
                {"id": "told", "type": "talk_to", "npc": giver["id"], "text": "Tell %s who it was" % gname}],
             "rewards": reward(20, 6, 12, "Told the truth about the theft", 90)},
            {"id": "hushed", "title": "Collect the hush money", "mode": "all", "end": True, "objectives": [
                {"id": "quiet", "type": "talk_to", "npc": suspect["id"], "text": "Collect %s's thanks" % sfirst}],
             "rewards": {"gold": 35, "rep": {tid: -6}, "relationship": [{"npc": giver["id"], "label": "Heard you looked the other way", "value": -12, "days": 90}]}},
        ],
    }

    # --- C: the threat (GoTo, Kill, TalkTo)
    c_id = "%s_%s" % (tid, slug(kit["c_title"]))
    qc = {
        "id": c_id, "title": kit["c_title"],
        "summary": "%s sign at the edge of %s has grown bolder. %s wants %d of them dealt with." % (plur.capitalize(), name, gname, n_kill),
        "giver": {"npc": giver["id"], "name": gname, "place": tid}, "requires": [b_id],
        "offer_text": "\"The %s have come closer to %s each night. Go to the edge and thin them out, before someone is hurt.\"" % (plur, name),
        "turn_in_text": "\"Quieter already. I will sleep tonight. A little.\"",
        "stages": [
            {"id": "edge", "title": "Go to the edge of town", "mode": "all", "objectives": [
                {"id": "reach", "type": "goto", "place": outskirts, "text": "Go to where the %s were seen" % plur}]},
            {"id": "hunt", "title": "Thin them out", "mode": "all", "objectives": [
                {"id": "hunt", "type": "kill", "target": species, "place": outskirts, "count": n_kill, "text": "Kill %d %s near %s" % (n_kill, plur, name)}]},
            {"id": "report", "title": "Tell %s" % gfirst, "mode": "all", "end": True, "objectives": [
                {"id": "report", "type": "talk_to", "npc": giver["id"], "text": "Tell %s it is done" % gname}]},
        ],
        "rewards": reward(25, 5, 10, "Kept the %s from the edge" % plur, 60),
    }
    return [qa, qb, qc], clues, stash


# ----------------------------------------------------------------------------------------------- driver

SEED_USED = [1066]


def build_all(world, seed):
    SEED_USED[0] = seed
    used = set(world.reserved_names)
    allocated = {}
    for name in world.order:
        allocated[name] = alloc_names(world, name, seeded(seed, "names", name), used)
    out = {}
    for name in world.order:
        out[name] = build_town(world, name, allocated[name], seed, used)
    return out


def files_for(doc, quests):
    tid = doc["id"]
    files = {}
    files["data/region1/towns/%s.json" % tid] = doc
    for q in quests:
        files["data/quests/%s/%s.json" % (tid, q["id"][len(tid) + 1:])] = q
    by_id = {p["id"]: p for p in doc["residents"]}
    for p in doc["residents"]:
        files["dialogue/%s/%s.json" % (tid, p["id"])] = build_dialogue(tid, by_id, p)
    return files


def stale_files(doc, quests):
    """Files of this town on disk that the generator no longer makes (a resident or quest that was dropped)."""
    tid = doc["id"]
    keep = set(files_for(doc, quests))
    out = []
    for sub in ("dialogue/%s" % tid, "data/quests/%s" % tid):
        d = os.path.join(ROOT, sub)
        if os.path.isdir(d):
            for f in sorted(os.listdir(d)):
                rel = sub + "/" + f
                if f.endswith(".json") and rel not in keep:
                    out.append(rel)
    return out


def dump(obj):
    return json.dumps(obj, indent=1, ensure_ascii=False) + "\n"


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("towns", nargs="*", help="settlement names (Millbrook ...)")
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--seed", type=int, default=1066)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--check", action="store_true")
    a = ap.parse_args()
    world = World()
    built = build_all(world, a.seed)
    want = world.order if a.all else []
    for t in a.towns:
        match = [n for n in world.order if n.lower() == t.lower() or town_id(n) == t.lower()]
        if not match:
            sys.exit("unknown settlement: %s" % t)
        want.append(match[0])
    if not want:
        ap.error("name at least one settlement (or --all)")
    bad = 0
    for name in want:
        if name == "Thornfield" and not a.dry_run:
            sys.exit("Thornfield is the hand-written first user of the kit (data/region1/towns/thornfield.json); the generator never rewrites it")
        doc, quests = built[name]
        files = files_for(doc, quests)
        if a.dry_run:
            print("%-12s %-13s pop %4d  %2d residents, %d lots, threat %s, %d quests, %d dialogue files" % (
                name, doc["kind"], doc["population"], len(doc["residents"]), len(doc["lots"]["required"]), doc["threat"]["species"], len(quests), len(doc["residents"])))
            continue
        for rel, obj in files.items():
            path = os.path.join(ROOT, rel)
            text = dump(obj)
            if a.check:
                if not os.path.exists(path) or open(path, encoding="utf-8").read() != text:
                    print("differs: " + rel)
                    bad += 1
                continue
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "w", encoding="utf-8") as f:
                f.write(text)
        for rel in stale_files(doc, quests):
            if a.check:
                print("stale: " + rel)
                bad += 1
            elif not a.dry_run:
                os.remove(os.path.join(ROOT, rel))
                print("removed stale " + rel)
        if not a.check:
            print("wrote %s: %d residents, %d quests, %d dialogue files" % (name, len(doc["residents"]), len(quests), len(doc["residents"])))
    if a.check:
        print("ok: files match the generator" if bad == 0 else "%d files differ" % bad)
        sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
