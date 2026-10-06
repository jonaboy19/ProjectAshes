#!/usr/bin/env python3
"""Generates a town-kit file for a Region 1 settlement (scripts/world/town_kit/town_data.gd), deterministically.

  python3 tools/towns/gen_town.py Millbrook Redwater          # write data/region1/towns/<id>.json, data/quests/<id>/*.json, dialogue/<id>/*.json
  python3 tools/towns/gen_town.py --all                       # every settlement but Thornfield (hand-made, never rewritten)
  python3 tools/towns/gen_town.py --all --dry-run             # build every settlement in memory (what the name allocator needs) and print a summary
  python3 tools/towns/gen_town.py --all --check               # exit 1 when the files on disk differ from what the generator makes now
  python3 tools/towns/gen_town.py --all --report              # a readable sample per town: roles, a line of dialogue, the quest line
  Run from kingdom/. Options: --seed N (default 1066, the world seed).

Inputs:  data/world/town_identity.json (archetype, flavour, trade kits, terrain per settlement), data/region1/world/settlements.json (trade,
         landmark, named NPC, rumours), data/region1/world/settlement_facts.json (kind, population, radius, house lots: runtime layout facts).
Modules: town_text.py (names, roles, archetype tables), town_roles.py (more roles: authorities, trade kits, the capital's court),
         town_lines.py (archetype and town-specific dialogue), town_quests.py (the quest templates).
Output per town:
  * a roster of 10-25 named residents whose names are unique across the whole region (the allocator builds every settlement in id
    order, so a town's names never depend on which towns were asked for). Roles come from the archetype (workers), the identity's trade
    kits (one of each, up to four), the authority of that archetype (reeve, yard-boss, huntmaster, harbourmaster, chamberlain ...) and
    the lots the town has (keepers). Kingsreach gets the court: marshal, knights, court scribe, falconer, master of horse, courtiers,
    cook, treasury clerk, and a chamberlain as its authority (no steward, no lord: those belong to the keep and the nobility system);
  * the required lots by kind (village: tavern, smithy, general shop; town: plus bakery, healer, guard post; a village whose identity
    says bakehouse/herbs/watch gets that lot too);
  * a local threat that fits the place (toads at the mere and the marsh, wasps at the hives and the crater, ghouls on the moor and in the
    deep workings, wolves elsewhere), a den ring and night probes (scripts/world/town_kit/town_threat.gd);
  * livestock the archetype keeps and, for farming, pastoral, religious, mining, fortress, merchant, fishing and craft places, rail-fence
    pens laid on the settlement frame around them;
  * a three-quest chain drawn from fifteen templates (town_quests.py) with only objective types the kit wires by itself;
  * dialogue files in dialogue_runner format (scripts/sim/dialogue_runner.gd), one per resident, whose lines are drawn without repeating
    a line inside a town: role lines, archetype lines, lines about the town itself, time-of-day and rain remarks, what a friend hears.
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
import town_lines as L  # noqa: E402
import town_quests as Q  # noqa: E402

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
        self.rank = {}                       # settlement -> its index among the settlements of its archetype (in id order, Thornfield counts)
        seen = {}
        for n in self.order:
            a = self.identity[n]["arch"]
            self.rank[n] = seen.get(a, 0)
            seen[a] = seen.get(a, 0) + 1
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


COURT = ["tourney marshal", "household knight", "court scribe", "falconer", "courtier", "master of horse", "royal cook", "treasury clerk", "courtier"]


def signature_roles(ident, arch, count):
    """The roles that make this town this town: the capital's court, or one of each role of the identity's trade kits."""
    if count <= 0:
        return []
    out = []
    if arch == "royal":
        out = list(COURT)
    else:
        for kit in ident.get("kits") or []:
            for r in T.KIT_ROLES.get(kit, []):
                if r not in out:
                    out.append(r)
        out = out[:4]
    return out[:count]


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
    if kind == "night":
        return [{"from": 21, "to": 5, "phase": "work"}, {"from": 7, "to": 11, "phase": "home"}, {"from": 17, "to": 21, "phase": "social" if ev < 0.5 else "inn"}]
    if kind == "early":
        return [{"from": 3.5, "to": 12.5, "phase": "work"}, {"from": 12.5, "to": 14, "phase": "market"}]
    if kind == "shop":
        return [{"from": r(7, 8), "to": r(18, 19), "phase": "work"}]
    if kind == "inn":
        return [{"from": 10, "to": 24, "phase": "work"}, {"from": 0, "to": 10, "phase": "home"}]
    if kind == "reeve":
        # the authority is the town's first quest giver: after the morning's business they hold audience in the market square
        return [{"from": 8, "to": 11, "phase": "work"}, {"from": 11, "to": 14, "phase": "market"}, {"from": 14, "to": 17, "phase": "work"}]
    if kind == "audience_temple":
        return [{"from": 6, "to": 8, "phase": "temple"}, {"from": 8, "to": 11, "phase": "work"}, {"from": 11, "to": 14, "phase": "market"},
                {"from": 14, "to": 17.5, "phase": "work"}, {"from": 17.5, "to": 18.5, "phase": "temple"}]
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
    authority = T.ARCHS[arch]["authority"]
    roles = [authority] + keepers + ["guard"] * guards + ["elder"] * elders
    fill = n - len(roles) - kids
    sig = signature_roles(ident, arch, fill)
    roles += sig
    roles += worker_roles(arch, max(fill - len(sig), 0), rng)
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
        elif (role == authority and arch != "royal") or role == "elder":
            e["home"] = home_of.get(i, "%s_house_1" % tid)
            e["work"] = e["home"]
        elif role == "guard":
            e["home"] = home_of.get(i, "%s_house_1" % tid)
            e["work"] = "%s_guard_post" % tid if "guard_post" in lots else "%s_works" % tid
        else:
            e["home"] = home_of.get(i, "%s_house_1" % tid)
            e["work"] = "%s_works" % tid
            if T.ROLE_WORK.get(role) == "keep" and arch == "royal":
                e["work"] = "%s_keep" % tid
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
        if i == 0:
            kind = "audience_temple" if role == "chaplain" else "reeve"      # the authority holds audience in the market at midday
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


class LineBank:
    """Draws lines for one town without repeating one while a fresh line is left (pools are shuffled by the town's own rng)."""

    def __init__(self, rng):
        self.rng = rng
        self.used = set()

    def take(self, pool):
        pool = [x for x in pool if x]
        fresh = [x for x in pool if x not in self.used]
        pick = self.rng.choice(fresh if fresh else pool)
        self.used.add(pick)
        return pick

    def fresh(self, pool):
        """A line nobody in the town says yet, or "" when the pool is used up."""
        fresh = [x for x in pool if x and x not in self.used]
        if not fresh:
            return ""
        pick = self.rng.choice(fresh)
        self.used.add(pick)
        return pick


def finish_people(world, name, residents, edges, rng, threat_noun="wolf"):
    s = world.by_name[name]
    arch = world.identity[name]["arch"]
    ident = world.identity[name]
    al = L.ARCH_LINES[arch]
    landmark = (s.get("landmark") or {}).get("name", name + " works")
    fmt = {"town": name, "landmark": landmark, "flavour": ident.get("flavour", "its trade"), "tagline": (s.get("tagline") or "a place of its own").lower()}
    town_greets = [t.format(**fmt) for t in L.TOWN_GREETS]
    town_rumours = list(s.get("rumours", [])) + [t.format(**fmt) for t in L.TOWN_RUMOURS]
    own = len(s.get("rumours", []))
    bank = LineBank(rng)
    by_id = {r["id"]: r for r in residents}
    rel = {r["id"]: {} for r in residents}
    for a, b, kind, v in edges:
        rel[a][b] = {"kind": kind, "value": v}
        rel[b][a] = {"kind": kind if kind != "mentor" else "student", "value": v}
    for i, r in enumerate(residents):
        r["relationships"] = {k: rel[r["id"]][k] for k in sorted(rel[r["id"]])}
    slots = ["morning", "evening", "night", "rain"]
    people = []

    def fill(t):
        return t.replace("{town}", name).replace("{Threat}", threat_noun.capitalize()).replace("{threat}", threat_noun)

    for i, r in enumerate(residents):
        greet = r.pop("_greet")
        rum = r.pop("_rum")
        r.pop("_kind", None)
        r.pop("_parent", None)
        ties = list(r["relationships"])
        opinions = {}
        for k, other_id in enumerate(ties[:2]):
            kind = r["relationships"][other_id]["kind"]
            pool = T.RELATIONS.get(kind, T.RELATIONS["friend"])[1]
            opinions[other_id] = pool[(i + len(ties[0]) + k) % len(pool)].format(o=first_of(by_id[other_id]["name"]))
        child = r["role"] == "child"
        g1 = bank.fresh([fill(x) for x in greet])
        greeting = [g1 or fill(bank.take(greet))]
        g2 = bank.fresh(al["greets"] if child else al["greets"] + town_greets)
        if g2:
            greeting.append(g2)
        rumour = []
        for pool in ([fill(x) for x in rum], al["rumours"], [] if child else (town_rumours[:own] if (own and i % 2 == 0) else town_rumours)):
            r1 = bank.fresh(pool)
            if r1 and (len(rumour) < 2 or i % 3 != 2):
                rumour.append(r1)
        while len(rumour) < 2:
            rumour.append(bank.take(al["rumours"] if child else al["rumours"] + town_rumours))
        ka = L.KEEPER_ARCH.get(r["role"], {}).get(arch)
        if ka:
            rumour.insert(0, ka)
            bank.used.add(ka)
        aside = "" if child else next((L.TRAIT_ASIDES[t.replace(" ", "-")] for t in r["traits"] if t.replace(" ", "-") in L.TRAIT_ASIDES), "")
        slot = slots[i % 4]
        r["dialogue"] = {"greeting": greeting, "rumour": rumour, "opinions": opinions, "time": {} if child else {slot: al[slot]}, "aside": aside}
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
    for slot, line in (d.get("time") or {}).items():
        if slot == "rain":
            greet_lines.append({"text": q(line), "if": {"weather": "rain", "tier_not": ["enemy", "rival"]}, "p": 3})
        else:
            greet_lines.append({"text": q(line), "if": {"time": slot, "tier_not": ["enemy", "rival"]}, "p": 2})
    if p.get("child"):
        greet_lines.append({"text": q("Hm? Oh. Hello. Does your mother know where you are?"), "if": {"tier": "stranger", "child": False}, "p": 1})
    greet_lines.append({"text": q("{greeting}") + " {first} nods.", "if": {"tier": "stranger"}, "p": 1})
    if d.get("aside"):
        greet_lines.append({"text": q(d["aside"]), "if": {"tier": ["friend", "close_friend"]}, "p": 4})
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


# ----------------------------------------------------------------------------------------------- places, species, livestock

def landmark_front(world, name):
    lm = world.by_name[name].get("landmark") or {}
    ys = [float(p[2]) for p in lm.get("parts", []) if isinstance(p, list) and len(p) > 2 and not str(p[0]).startswith("r1:")]
    return max(10.0, min(20.0, (max(ys) if ys else 8.0) + 3.0))


def pick_species(ident):
    """The local threat that fits the place: toads where it is wet, wasps at the hives and the warm crater, ghouls on the moor and in the
    deep workings, wolves everywhere else (the forests, the downs, the passes)."""
    hint = set(ident.get("hint") or [])
    terr = set(ident.get("terrain") or [])
    kits = set(ident.get("kits") or [])
    arch = ident["arch"]
    if "crater" in terr or "bees" in kits or "candles" in kits:
        return "giant_wasp"
    if arch == "craft" and "river" in hint:
        return "giant_wasp"
    if arch == "fishing" or (hint & {"mere", "marsh", "coast"} and arch not in ("hunting", "fortress")):
        return "bog_toad"
    if arch == "mining" and terr & {"moor", "hill"}:
        return "ghoul"
    return "wolf"


def works_label(ident, arch):
    for kit in ident.get("kits") or []:
        if kit in T.WORKS_BY_KIT:
            return T.WORKS_BY_KIT[kit]
    return T.ARCHS[arch]["works"]


# archetype -> [(kind, count, tag, pen?)]; a pen is a rail-fence yard around the group on the settlement frame
LIVESTOCK = {
    "farming": [("cow", 3, "cows", True), ("chicken", 5, "hens", True), ("pig", 2, "pigs", True)],
    "pastoral": [("sheep", 6, "sheep", True), ("sheepdog", 1, "dog", False)],
    "religious": [("sheep", 3, "sheep", True), ("chicken", 4, "hens", True)],
    "hunting": [("dog", 2, "hounds", False)],
    "craft": [("chicken", 4, "hens", True)],
    "mining": [("donkey", 2, "ponies", True), ("goat", 2, "goats", False)],
    "fortress": [("horse_grey", 2, "horses", True)],
    "merchant": [("donkey", 2, "pack animals", True)],
    "fishing": [("goat", 2, "goats", True), ("chicken", 3, "hens", False)],
    "scholarly": [("cat", 1, "cat", False)],
    "criminal": [("dog", 1, "dog", False)],
    "royal": [("dog", 2, "hounds", False)],
}
PEN_SIZE = {"cow": [16, 12], "chicken": [8, 6], "pig": [9, 7], "sheep": [16, 12], "donkey": [11, 8], "horse_grey": [14, 10], "goat": [9, 7]}


def livestock_for(ident, arch, radius, ang, rng):
    """Groups and pens on the settlement frame: a ring around the town at 1.2 x its radius, each group a pen facing the town."""
    spec = list(LIVESTOCK.get(arch, []))
    if "dairy" in (ident.get("kits") or []) and arch == "pastoral":
        spec.append(("cow", 3, "cows", True))
    if not spec:
        return None
    groups, pens = [], []
    r = radius * 1.2
    for k, (kind, n, tag, pen) in enumerate(spec):
        a = ang + math.tau * k / max(3, len(spec)) + 0.35 * k
        at = [round(r * math.cos(a)), round(r * math.sin(a))]
        kinds = [[kind, n]]
        if kind == "chicken":
            kinds.append(["rooster", 1])
        groups.append({"anchor": "town", "at": at, "kinds": kinds, "radius": 4.0 if kind in ("chicken", "pig", "goat") else 6.0, "tag": tag})
        if pen:
            size = PEN_SIZE.get(kind, [12, 9])
            pens.append({"anchor": "town", "at": at, "size": list(size), "yaw": round(math.atan2(-at[0], -at[1]), 3)})
    return {"groups": groups, "pens": pens}


def build_town(world, name, names, seed, used):
    rng = seeded(seed, "town", name)
    f = world.facts[name]
    ident = world.identity[name]
    s = world.by_name[name]
    arch = ident["arch"] if ident["arch"] in T.ARCHS else "farming"
    kit = dict(T.ARCHS[arch])
    kit["works"] = works_label(ident, arch)
    tid = town_id(name)
    lots = lots_for(world, name)
    th_species = pick_species(ident)
    residents = build_roster(world, name, names, rng, lots, used)
    edges = build_ties(residents, rng)
    people = finish_people(world, name, residents, edges, rng, T.THREAT_NAMES[th_species][0])
    fy = landmark_front(world, name)
    radius = f["radius"]
    ang = rng.uniform(0, math.tau)
    r_out = round(radius * 1.35)
    out_at = [round(r_out * math.cos(ang)), round(r_out * math.sin(ang))]
    homes = max(int(re.search(r"_house_(\d+)$", p["home"]).group(1)) for p in people if re.search(r"_house_(\d+)$", p["home"]))
    lot_bid = {"tavern": "inn", "smithy": "smithy", "general_shop": "shop", "bakery": "bakery", "healer": "healer", "guard_post": "guard_post"}
    doors = {"%s_works" % tid: {"anchor": "landmark", "at": [0.0, round(fy, 1)]}}
    anchors = {"town": {"kind": "settlement"}, "landmark": {"kind": "site", "r1id": "landmark_" + name.lower()}}
    if arch == "royal":
        # the keep gate: the capital's castle is a plan landmark, its court lives and works behind it
        anchors["keep"] = {"kind": "landmark", "asset": "castle"}
        doors["%s_keep" % tid] = {"anchor": "keep", "at": [0.0, 14.5]}
    kind = f["kind"]
    probe_chance = 65 if kind == "frontier_town" else (25 if arch == "royal" else (35 if arch == "fortress" else 55))
    doc = {
        "version": 1,
        "_doc": "Generated by tools/towns/gen_town.py (seed %d) for %s. Edit freely or re-run; format: scripts/world/town_kit/town_data.gd." % (SEED_USED[0], name),
        "id": tid, "settlement": name, "kind": kind, "population": f["population"],
        "dialogue_dir": tid, "outdoor_work": True,
        "identity": {"arch": arch, "flavour": ident.get("flavour", ""), "trade": s.get("trade", ""), "tagline": s.get("tagline", ""), "kits": ident.get("kits") or [], "terrain": ident.get("terrain") or [], "hint": ident.get("hint") or []},
        "residents": people,
        "lots": {"required": [{"btype": t, "asset": LOT_ASSET[t], "bid": "%s_%s" % (tid, lot_bid[t])} for t in lots],
                 "homes": homes, "sites": {"%s_works" % tid: s["landmark"]["name"] if s.get("landmark") else name + " works"}},
        "anchors": anchors,
        "doors": doors,
        "places": [
            {"id": tid, "anchor": "town", "at": [0, 0], "radius": round(radius * 1.15)},
            {"id": "%s_works" % tid, "anchor": "landmark", "at": [0.0, round(fy - 3.0, 1)], "radius": 26},
            {"id": "%s_outskirts" % tid, "anchor": "town", "at": out_at, "radius": 40, "dry": True},
        ],
        "threat": {"species": th_species, "spawner": tid, "group": "%s_threat" % tid, "den_ring": [round(radius + 60), round(radius + 220)], "night": [22, 5],
                   "probe_chance": probe_chance, "probe_place": "%s_outskirts" % tid, "probe_near": 240, "probe_count": THREAT_COUNT[th_species], "probe_from": 60,
                   "probe_territory": 70, "ambush_from": 22, "ambush_territory": 120},
    }
    lv = livestock_for(ident, arch, radius, ang, rng)
    if lv:
        doc["livestock"] = lv
    rank = world.rank[name]
    ctx = Q.Ctx(tid, name, arch, kit, kind, people, doc, th_species, fy, rng, rank, T.ARCHS[arch]["authority"],
                (s.get("landmark") or {}).get("name", name), {"village": 1.0, "frontier_town": 1.25, "town": 1.3, "castle": 1.6}.get(kind, 1.0))
    quests, clues, stashes, picks = Q.build_line(ctx)
    doc["clues"] = clues
    doc["stashes"] = stashes
    doc["quests"] = ["res://data/quests/%s/%s.json" % (tid, q["id"][len(tid) + 1:]) for q in quests]
    doc["identity"]["quest_templates"] = picks
    return doc, quests


# ----------------------------------------------------------------------------------------------- driver

SEED_USED = [1066]


def sanity(doc, quests):
    """The invariants the kit relies on, checked at generation time (the gdUnit test checks them again in the engine)."""
    tid = doc["id"]
    people = {p["id"]: p for p in doc["residents"]}
    homes = {"%s_house_%d" % (tid, k + 1) for k in range(doc["lots"]["homes"])}
    doors = set(doc["doors"])
    bids = {r["bid"] for r in doc["lots"]["required"]} | homes | doors
    places = {p["id"] for p in doc["places"]}
    clues = {c["id"] for c in doc["clues"]}
    qids = {q["id"] for q in quests}
    assert len(qids) == len(quests), tid + ": duplicate quest ids"
    assert len(clues) == len(doc["clues"]), tid + ": duplicate clue ids"
    for e in doc["residents"]:
        assert e["home"] in bids or e["home"] in doc.get("default_spots", []), "%s: %s home %s" % (tid, e["id"], e["home"])
        assert e["work"] in bids, "%s: %s work %s" % (tid, e["id"], e["work"])
    for c in doc["clues"] + doc["stashes"]:
        assert ("building" in c and c["building"] in bids) or c.get("anchor") in doc["anchors"], "%s: %s has no location (%s)" % (tid, c["id"], c)
    stash_for = {}
    for st in doc["stashes"]:
        assert st["quest"] in qids, "%s: stash %s names quest %s" % (tid, st["id"], st["quest"])
        q = next(q for q in quests if q["id"] == st["quest"])
        assert st["stage"] in [s["id"] for s in q["stages"]], "%s: stash %s stage %s" % (tid, st["id"], st["stage"])
        stash_for[(st["quest"], st["item"])] = st
    for q in quests:
        assert q["giver"]["npc"] in people, "%s: giver of %s" % (tid, q["id"])
        for st in q["stages"]:
            for o in st["objectives"]:
                t = o["type"]
                if t in ("talk_to", "choose") and o.get("npc"):
                    assert o["npc"] in people, "%s: %s npc %s" % (tid, q["id"], o["npc"])
                if t == "deliver":
                    assert o["to"] in people, "%s: %s deliver to %s" % (tid, q["id"], o["to"])
                if t == "goto" or t == "kill":
                    assert o["place"] in places, "%s: %s place %s" % (tid, q["id"], o["place"])
                if t == "investigate":
                    assert all(c in clues for c in o["clues"]) and o["count"] <= len(o["clues"]), "%s: %s clues" % (tid, q["id"])
                if t == "collect":
                    sx = stash_for.get((q["id"], o["item"]))
                    assert sx is not None and sx["stage"] == st["id"] and sx["count"] == o["count"], "%s: %s collect %s has no stash on its stage" % (tid, q["id"], o["item"])
            for b in (st.get("branches") or {}).values():
                assert b in [x["id"] for x in q["stages"]], "%s: %s branch %s" % (tid, q["id"], b)
    names = [p["name"] for p in doc["residents"]]
    assert len(set(names)) == len(names), tid + ": duplicate names"


def build_all(world, seed):
    SEED_USED[0] = seed
    used = set(world.reserved_names)
    allocated = {}
    for name in world.order:
        allocated[name] = alloc_names(world, name, seeded(seed, "names", name), used)
    out = {}
    for name in world.order:
        out[name] = build_town(world, name, allocated[name], seed, used)
        sanity(*out[name])
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


def report(doc, quests):
    """A readable sample of one town: identity, roles, a few lines, the quest line."""
    print("=== %s (%s, %s, pop %d) arch=%s threat=%s templates=%s" % (doc["settlement"], doc["kind"], ",".join(doc["identity"]["kits"]) or "-", doc["population"],
                                                               doc["identity"]["arch"], doc["threat"]["species"], doc["identity"]["quest_templates"]))
    roles = {}
    for p in doc["residents"]:
        roles[p["role"]] = roles.get(p["role"], 0) + 1
    print("  roles: " + ", ".join("%s%s" % (r, " x%d" % n if n > 1 else "") for r, n in sorted(roles.items())))
    for p in doc["residents"][:2]:
        print("  %s (%s): \"%s\" / \"%s\"" % (p["name"], p["role"], p["dialogue"]["greeting"][0], p["dialogue"]["rumour"][0]))
    lv = doc.get("livestock")
    if lv:
        print("  livestock: %s; %d pens" % (", ".join("%s x%d" % (g["kinds"][0][0], g["kinds"][0][1]) for g in lv["groups"]), len(lv["pens"])))
    for q in quests:
        types = []
        for st in q["stages"]:
            types.append("/".join(o["type"] for o in st["objectives"]))
        print("  quest %s [giver %s]: %s" % (q["title"], q["giver"]["name"], " > ".join(types)))
        print("      %s" % q["summary"])


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("towns", nargs="*", help="settlement names (Millbrook ...)")
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--seed", type=int, default=1066)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--report", action="store_true")
    a = ap.parse_args()
    world = World()
    built = build_all(world, a.seed)
    want = [n for n in world.order if n != "Thornfield"] if a.all else []
    for t in a.towns:
        match = [n for n in world.order if n.lower() == t.lower() or town_id(n) == t.lower()]
        if not match:
            sys.exit("unknown settlement: %s" % t)
        want.append(match[0])
    if not want:
        ap.error("name at least one settlement (or --all)")
    bad = 0
    for name in want:
        if name == "Thornfield" and not (a.dry_run or a.report or a.check):
            sys.exit("Thornfield is the hand-written first user of the kit (data/region1/towns/thornfield.json); the generator never rewrites it")
        if name == "Thornfield" and a.check:
            continue
        doc, quests = built[name]
        files = files_for(doc, quests)
        if a.report:
            report(doc, quests)
            continue
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
            else:
                os.remove(os.path.join(ROOT, rel))
                print("removed stale " + rel)
        if not a.check:
            print("wrote %s: %d residents, %d quests, %d dialogue files" % (name, len(doc["residents"]), len(quests), len(doc["residents"])))
    if a.check:
        print("ok: files match the generator" if bad == 0 else "%d files differ" % bad)
        sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
