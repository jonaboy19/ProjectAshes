#!/usr/bin/env python3
"""Writes dialogue/thornfield/<id>.json for every bound resident of data/region1/world/thornfield_people.json.
Format: scripts/sim/dialogue_runner.gd. Run from kingdom/:  python3 tools/thornfield/gen_dialogue.py
Wilm Garrow also gets the nodes the quest line needs ("confession", "bribe_paid"); the `has` keys are set by
scripts/world/thornfield/thornfield_talk.gd (ctx["thornfield_confront"], ctx["thornfield_bribe_paid"])."""
import json, os, sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
people = json.load(open(os.path.join(ROOT, "data/region1/world/thornfield_people.json")))["residents"]
by_id = {p["id"]: p for p in people}
OUT = os.path.join(ROOT, "dialogue/thornfield")
os.makedirs(OUT, exist_ok=True)


def first(pid):
    return by_id[pid]["name"].split(" ")[0] if pid in by_id else pid


def q(s):
    return '"%s"' % s


def build(p):
    d = p["dialogue"]
    greet_lines = [
        {"text": "{first} looks you up and down and says nothing at all.", "if": {"tier": "enemy"}, "p": 5},
        {"text": q("You again. Say what you want and be quick about it."), "if": {"tier": "rival"}, "p": 5},
    ]
    for i, g in enumerate(d["greeting"]):
        greet_lines.append({"text": q(g), "if": {"tier_not": ["enemy", "rival"]}, "p": 2})
    if p.get("child"):
        greet_lines.append({"text": q("Hm? Oh. Hello. Does your mother know where you are?"), "if": {"tier": "stranger", "child": False}, "p": 1})
    greet_lines.append({"text": q("{greeting}") + " {first} nods.", "if": {"tier": "stranger"}, "p": 1})
    greet_lines.append({"text": q("Well met, {player}."), "if": {"tier": ["friend", "close_friend"]}, "p": 3})
    greet = {"lines": greet_lines, "choices": [
        {"text": q("Heard any news?"), "goto": "rumour", "if": {"tier_not": ["enemy", "rival"]}},
    ]}
    for oid in d["opinions"]:
        if oid in by_id:
            greet["choices"].append({"text": q("What do you make of %s?" % first(oid)), "goto": "op_" + oid, "if": {"tier_not": ["enemy", "rival"]}})
    if p["id"] == "wilm_garrow":
        greet["choices"].append({"text": q("I saw you at the barn, Wilm. We need to talk."), "goto": "confession", "if": {"has": "thornfield_confront"}})
        greet["choices"].append({"text": q("About the rest of that coin you promised..."), "goto": "bribe_paid", "if": {"has": "thornfield_bribe_paid"}})
    greet["choices"].append({"text": "Offer a gift…", "goto": "", "if": {"has": "has_gift_items"}, "do": [["gift"]]})
    greet["choices"].append({"text": "\"Good day to you.\"", "goto": "@end"})
    nodes = {"greet": greet}
    rum_lines = [{"text": q(r), "p": 2} for r in d["rumour"]]
    rum_lines.append({"text": q("{rumour}"), "if": {"has": "rumour"}, "p": 1})
    rum_lines.append({"text": q("Nothing I would repeat."), "p": 0})
    nodes["rumour"] = {"lines": rum_lines, "choices": [
        {"text": q("Anything else?"), "goto": "rumour"},
        {"text": q("Thanks for telling me."), "goto": "greet", "do": [["opinion", "chat", "Pleasant talk", 2, 5]]},
    ]}
    for oid, line in d["opinions"].items():
        nodes["op_" + oid] = {"lines": [{"text": q(line)}], "choices": [
            {"text": q("Go on."), "goto": "rumour"}, {"text": q("Thanks."), "goto": "greet"}]}
    if p["id"] == "wilm_garrow":
        nodes["confession"] = {"lines": [{"text": "Wilm goes very still, then laughs, thin and tired. " + q(
            "A man could get lonely, keeping that secret. A Kingsreach factor paid me to spoil the top sacks. Vinegar and a little mould. I told myself it was only barley.")}],
            "choices": [{"text": q("Think about what you will do about it."), "goto": "@end"}]}
        nodes["bribe_paid"] = {"lines": [{"text": q("Sixty, as promised. Do not look at me like that. You took it.")}],
                               "choices": [{"text": q("Goodbye, Wilm."), "goto": "@end"}]}
    return {"id": "thornfield/" + p["id"], "start": "greet", "nodes": nodes}


n = 0
for p in people:
    if not p.get("bind", True):
        continue
    json.dump(build(p), open(os.path.join(OUT, p["id"] + ".json"), "w"), indent=1)
    n += 1
print("wrote %d dialogue files" % n)
