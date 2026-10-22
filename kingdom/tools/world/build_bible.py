"""Builds the Valencious world bible data from the live WorldGen dump + canon files.

Inputs  : docs/world/dump_world_map.json (tools_qa/map/dump_world.gd), docs/world/dump_r1_sites.json (tools_qa/region1/world_dump.gd),
          kingdom/data/world/{first_region,regions}.json, kingdom/assets/ui/maps/region1_parchment.json,
          docs/regions/WORLD_R1.md, kingdom/data/world/valencious_regions.json
Outputs : docs/world/valencious_places.json, docs/world/valencious_bible_map.png,
          docs/world/dump_world_{settlements,roads,water}.txt
Run     : py -E -B kingdom/tools/world/build_bible.py   (deterministic)
Note    : `py -I` hides the user site-packages where numpy/Pillow/scipy live on this machine; use -E -B instead.
"""
import json
import math
import os
import re
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import valencious_common as vc  # noqa: E402

DOCS = os.path.join(vc.REPO, "docs", "world")
KD = vc.KINGDOM

# parchment / poster display names -> the name the live dump uses
PARCH_ALIAS_TO_DUMP = {"Royal Ember Academy": "Kingsreach Academy of Arms and Arts", "Greyseam Seam": "Greyseam Elder Stone",
                       "Highwatch": "Highwatch Elder Stone", "Crownstead": "Crownstead Elder Stone", "Elden Road": "Elden Elder Stone"}
DISPLAY = {"Highcliff": "Highwatch Keep", "Oakvale": "Greenhollow", "Ironmarch": "Silverford"}


def slug(s):
    return re.sub(r"[^a-z0-9]+", "_", s.lower()).strip("_")


def build():
    dump = vc.load_json(os.path.join(DOCS, "dump_world_map.json"))
    r1 = vc.load_json(os.path.join(DOCS, "dump_r1_sites.json"))
    fr = vc.load_json(os.path.join(KD, "data", "world", "first_region.json"))
    parch = vc.load_json(os.path.join(KD, "assets", "ui", "maps", "region1_parchment.json"))
    regs = vc.load_json(vc.REGIONS_JSON)
    regions = regs["regions"]
    rows = {}

    def add(pid, name, kind, x, z, src, cat="", extra=None):
        key = (name, round(x), round(z))
        if key in rows:
            if src not in rows[key]["sources"]:
                rows[key]["sources"].append(src)
            return rows[key]
        p = {"id": pid, "name": name, "kind": kind, "x": round(x, 1), "z": round(z, 1), "category": cat, "sources": [src]}
        if extra:
            p.update(extra)
        rows[key] = p
        return p

    def find(name, near=None):
        c = [p for p in rows.values() if p["name"] == name]
        if not c:
            return None
        if near is None:
            return c[0]
        return min(c, key=lambda p: math.hypot(p["x"] - near[0], p["z"] - near[1]))

    # 1. live WorldGen dump: 30 settlements + discovery places
    for s in dump["settlements"]:
        add("settlement:" + s["name"].lower(), s["name"], s["kind"], s["pos"][0], s["pos"][1], "WorldGen.settlements (dump_world.gd)", "settlement",
            {"display_name": DISPLAY.get(s["name"], s["name"]), "radius": s["radius"], "population": s["population"], "settlement_id": s["id"]})
    for pl in dump["places"]:
        if pl["category"] == "settlement":
            continue
        add(pl["id"], pl["name"], pl["kind"], pl["pos"][0], pl["pos"][1], "discovery places (dump_world.gd)", pl["category"],
            {"hostile": bool(pl["hostile"]), "radius": pl.get("radius", 0)})
    for s in r1:
        p = add("site:" + s["r1id"], s["name"], s["kind"], s["pos"][0], s["pos"][1], "region1 sites (world_dump.gd)", "site", {"r1id": s["r1id"]})
        p.setdefault("r1id", s["r1id"])

    # 2. lore file: forests, rivers, elder stones, story places
    for pl in fr["places"]:
        ex = find(pl["name"], pl["pos"])
        if ex and math.hypot(ex["x"] - pl["pos"][0], ex["z"] - pl["pos"][1]) < 400:
            if "first_region.json" not in ex["sources"]:
                ex["sources"].append("first_region.json")
            ex["lore_id"] = pl["id"]
            if math.hypot(ex["x"] - pl["pos"][0], ex["z"] - pl["pos"][1]) > 1.0:
                ex.setdefault("alt_pos", []).append({"src": "first_region.json", "x": pl["pos"][0], "z": pl["pos"][1]})
        else:
            p = add(pl["id"], pl["name"], pl["kind"], pl["pos"][0], pl["pos"][1], "first_region.json", "lore", {"radius": pl.get("radius", 0)})
            p["lore_id"] = pl["id"]

    # 3. parchment features: aliases and the positions that disagree with the live dump
    conflicts = []
    for f in parch["features"]:
        nm = PARCH_ALIAS_TO_DUMP.get(f["id_name"] or f["name"], f["id_name"] or f["name"])
        if f["cat"] == "proposed":
            add("proposed:silverford", "Silverford (parchment proposal)", "town", f["pos_m"][0], f["pos_m"][1],
                "region1_parchment.json proposed_places", "proposed",
                {"aliases": ["Silverford"], "note": "guild town proposed at the Ashrun ford; WorldGen and first_region.json put Silverford at Ironmarch (2092,-2007). OWNER QUESTION Q1."})
            continue
        ex = find(nm, f["pos_m"]) or find(f["name"], f["pos_m"])
        if ex is None:
            ex = add("parchment:" + slug(nm), nm, f["kind"], f["pos_m"][0], f["pos_m"][1], "region1_parchment.json", "parchment")
        else:
            if "region1_parchment.json" not in ex["sources"]:
                ex["sources"].append("region1_parchment.json")
            d = math.hypot(ex["x"] - f["pos_m"][0], ex["z"] - f["pos_m"][1])
            if d > 25:
                ex.setdefault("alt_pos", []).append({"src": "region1_parchment.json", "x": round(f["pos_m"][0], 1), "z": round(f["pos_m"][1], 1)})
                conflicts.append((ex["name"], round(d)))
        if f["name"] != ex["name"] and f["name"] not in ex.get("aliases", []):
            ex.setdefault("aliases", []).append(f["name"])
    for e in parch["elder_stones"]:
        nm = PARCH_ALIAS_TO_DUMP.get(e["name"], e["name"])
        ex = find(nm, e["pos"])
        if ex:
            if e["name"] != ex["name"] and e["name"] not in ex.get("aliases", []):
                ex.setdefault("aliases", []).append(e["name"])
            if math.hypot(ex["x"] - e["pos"][0], ex["z"] - e["pos"][1]) > 25:
                ex.setdefault("alt_pos", []).append({"src": "region1_parchment.json elder_stones", "x": e["pos"][0], "z": e["pos"][1]})
            if "region1_parchment.json" not in ex["sources"]:
                ex["sources"].append("region1_parchment.json")

    # 4. WORLD_R1.md site rows (names + possibly stale positions)
    md = open(os.path.join(vc.REPO, "docs", "regions", "WORLD_R1.md"), encoding="utf8").read()
    for m in re.finditer(r"^\| `([a-z0-9_]+)` \| ([^|]+?) \| ([a-z_]+) \| \((-?\d+), (-?\d+)\) \|", md, re.M):
        rid, nm, x, z = m.group(1), m.group(2).strip(), float(m.group(4)), float(m.group(5))
        ex = find(nm, (x, z))
        if ex is None:
            add("site:" + rid, nm, "site", x, z, "WORLD_R1.md", "site", {"r1id": rid})
        else:
            if "WORLD_R1.md" not in ex["sources"]:
                ex["sources"].append("WORLD_R1.md")
            if math.hypot(ex["x"] - x, ex["z"] - z) > 25:
                ex.setdefault("alt_pos", []).append({"src": "WORLD_R1.md", "x": x, "z": z})

    # 5. exits (regions.json) and map-edge texts
    rj = vc.load_json(os.path.join(KD, "data", "world", "regions.json"))
    exit_pts = {"eastern_gate": ("The Eastern Gate", 3771.9, 480.8), "grimfen_pass": ("Grimfen Pass", 559.5, -3597.8),
                "harrow_arch": ("Harrow Arch", -198.0, 2823.0), "westfen_fen": ("Westfen fen exit", 34.0, 999.0)}
    for e in rj["exits"]:
        nm, x, z = exit_pts[e["id"]]
        p = find(nm, (x, z)) or add("exit:" + e["id"], nm, "exit", x, z, "regions.json exits", "exit")
        p["exit"] = {"direction": e["direction"], "locked": e["locked"], "leads_to": e["leads_to"], "hint": e["hint"]}
        if "regions.json exits" not in p["sources"]:
            p["sources"].append("regions.json exits")
    for nm, (x, z) in {"The Western Reaches": (-6000, 0), "To the Frostcrown Holds": (0, -6050), "To the Aurelis Patriarchate": (6050, 0),
                       "To the Solkar Dominion": (0, 6050)}.items():
        add("edge:" + slug(nm), nm, "map_edge_text", x, z, "parchment edge text / regions.json hints", "edge")

    places = sorted(rows.values(), key=lambda p: (p["category"] != "settlement", p["name"], p["x"]))
    rid = vc.region_of_points(regions, [(p["x"], p["z"]) for p in places], regs)
    rd = {r["id"]: r for r in regions}
    dom = {r["id"]: max(r["biomes"], key=r["biomes"].get) for r in regions}
    kind_biome = {"forest": "forest", "lake": "water", "river": "water", "rift": "rift", "rift_outpost": "rift", "waterfall": "water",
                  "glade": "forest", "mine": "highland", "old_mine": "highland", "elder_stone": "meadow", "keep": "highland", "pass": "snow",
                  "scar_arena": "rift"}
    for p, r in zip(places, rid):
        p["subregion"] = r
        p["biome"] = kind_biome.get(p["kind"], dom[r])
        if p["category"] == "settlement":
            bw = {k: v for k, v in rd[r]["biomes"].items() if k not in ("rift", "marsh", "snow")}
            p["biome"] = "farmland" if bw.get("farmland", 0) >= 0.15 else max(bw, key=bw.get)
        p.setdefault("display_name", p["name"])
        p["file"] = "; ".join(p["sources"])
    seen = set()
    for p in places:
        if p["id"] in seen:
            p["id"] = "%s@%d,%d" % (p["id"], p["x"], p["z"])
        seen.add(p["id"])

    sp = dump["settlements"]
    roads = [{"a": r["a"], "b": r["b"], "a_name": sp[r["a"]]["name"], "b_name": sp[r["b"]]["name"], "tier": r["tier"],
              "length_m": round(math.hypot(sp[r["a"]]["pos"][0] - sp[r["b"]]["pos"][0], sp[r["a"]]["pos"][1] - sp[r["b"]]["pos"][1]))} for r in dump["roads"]]
    out = {"version": 1, "seed": 1066, "half_m": vc.HALF, "coords": "metres from Ashford (0,0); x east, z south (north = -z)",
           "authority": "positions are the live WorldGen/RegionSites output at HEAD (tools_qa/map/dump_world.gd); alt_pos lists other sources that disagree (stale docs / parchment)",
           "canon_names": {"caldrenn": "Kingdom of Valencious", "House Caldrenn": "royal dynasty (King Aldric III)",
                           "solmarch": "Aurelis Patriarchate (Church of the Dawn Throne)", "Highcliff": "Highwatch Keep (town; the keep site stands 250 m NE)",
                           "Oakvale": "Greenhollow", "Ironmarch": "Silverford (display alias; owner question Q1)"},
           "places": places, "roads": roads, "rivers": dump["rivers"],
           "river_names": ["The Ashrun (upper, Hollin Falls to the Mere)", "The Ashrun (lower, Mere to the SW edge)", "The Silverrun"],
           "lake": dump["lake"], "regions_file": "kingdom/data/world/valencious_regions.json"}
    os.makedirs(DOCS, exist_ok=True)
    with open(vc.PLACES_JSON, "w", encoding="utf8") as f:
        json.dump(out, f, indent=1, ensure_ascii=False)
    print("places", len(places), "parchment conflicts", len(conflicts))

    with open(os.path.join(DOCS, "dump_world_settlements.txt"), "w") as f:
        for s in sp:
            f.write("%2d %-12s %-13s (%8.1f, %8.1f) r=%-4d pop=%d\n" % (s["id"], s["name"], s["kind"], s["pos"][0], s["pos"][1], s["radius"], s["population"]))
    with open(os.path.join(DOCS, "dump_world_roads.txt"), "w") as f:
        for r in roads:
            f.write("%2d-%-2d %-12s - %-12s %-8s %5d m\n" % (r["a"], r["b"], r["a_name"], r["b_name"], r["tier"], r["length_m"]))
    with open(os.path.join(DOCS, "dump_world_water.txt"), "w") as f:
        f.write("lake: centre %s radius %s\n" % (dump["lake"]["center"], dump["lake"]["radius"]))
        for i, rv in enumerate(dump["rivers"]):
            f.write("river %d: %d points (x, z, width), every 8th:\n" % (i, len(rv)))
            for j in range(0, len(rv), 8):
                f.write("  %8.1f %8.1f %5.1f\n" % tuple(rv[j]))
            f.write("  %8.1f %8.1f %5.1f (end)\n" % tuple(rv[-1]))
    return out, regs, places, roads, dump


def render_map(regs, places, roads, dump):
    npx = 1024
    regions = regs["regions"]
    c = vc.px_to_m(npx)
    X, Z = np.meshgrid(c, c)
    wx, wz = vc.warp_fields(npx, vc.SEED, regs["border_warp"])
    idx, _ = vc.region_index(regions, X, Z, (wx, wz))
    pal = [(200, 220, 150), (205, 208, 225), (205, 180, 140), (140, 200, 150), (95, 150, 95), (215, 170, 205), (235, 160, 130),
           (170, 215, 205), (120, 150, 190), (160, 190, 120), (190, 175, 215), (235, 215, 140)]
    img = np.zeros((npx, npx, 3), np.uint8)
    for i in range(len(regions)):
        img[idx == i] = pal[i % len(pal)]
    edge = np.zeros(idx.shape, bool)
    edge[:, 1:] |= idx[:, 1:] != idx[:, :-1]
    edge[1:, :] |= idx[1:, :] != idx[:-1, :]
    img[edge] = (70, 60, 50)
    im = Image.fromarray(img)
    d = ImageDraw.Draw(im, "RGBA")
    f_s = ImageFont.truetype("C:/Windows/Fonts/arial.ttf", 11)
    f_m = ImageFont.truetype("C:/Windows/Fonts/arialbd.ttf", 13)
    f_r = ImageFont.truetype("C:/Windows/Fonts/arialbd.ttf", 15)

    def px(x, z):
        return ((x + vc.HALF) / vc.WORLD * npx, (z + vc.HALF) / vc.WORLD * npx)
    for k in range(-6, 7):
        m = k * 1024.0
        d.line([px(m, -vc.HALF), px(m, vc.HALF)], fill=(60, 60, 60, 90), width=1)
        d.line([px(-vc.HALF, m), px(vc.HALF, m)], fill=(60, 60, 60, 90), width=1)
        d.text((px(m, -vc.HALF)[0] + 2, 2), "%d" % m, fill=(40, 40, 40, 255), font=f_s)
        d.text((2, px(-vc.HALF, m)[1] + 2), "%d" % m, fill=(40, 40, 40, 255), font=f_s)
    d.rectangle([px(-vc.HALF + 250, -vc.HALF + 250), px(vc.HALF - 250, vc.HALF - 250)], outline=(120, 60, 60, 160))
    for rv in dump["rivers"]:
        d.line([px(p[0], p[1]) for p in rv[::3]], fill=(40, 110, 200, 255), width=3)
    lc = px(*dump["lake"]["center"])
    rr = max(4.0, dump["lake"]["radius"] / vc.WORLD * npx)
    d.ellipse([lc[0] - rr, lc[1] - rr, lc[0] + rr, lc[1] + rr], fill=(40, 110, 200, 255))
    sp = dump["settlements"]
    for r in roads:
        col = {"kingdom": (150, 60, 30, 230), "rural": (120, 90, 60, 190), "frontier": (120, 100, 80, 140)}[r["tier"]]
        d.line([px(*sp[r["a"]]["pos"]), px(*sp[r["b"]]["pos"])], fill=col, width={"kingdom": 3, "rural": 2, "frontier": 1}[r["tier"]])
    for i, r in enumerate(regions):
        ys, xs = np.nonzero(idx == i)
        cx, cy = float(xs.mean()), float(ys.mean())
        k = int(np.argmin((xs - cx) ** 2 + (ys - cy) ** 2))
        cx, cy = float(xs[k]), float(ys[k])
        txt = r["name"].upper()
        w = d.textlength(txt, font=f_r)
        d.text((cx - w / 2, cy - 16), txt, fill=(40, 30, 20, 200), font=f_r)
    key_kinds = {"rift": (140, 40, 170), "rift_outpost": (140, 40, 170), "elder_stone": (30, 90, 200), "keep": (90, 40, 20), "waterfall": (30, 110, 200),
                 "valley": (30, 110, 60), "mine": (90, 90, 90), "goblin_warren": (30, 120, 30), "orc_village": (30, 120, 30), "border_gate": (160, 20, 20),
                 "pass": (120, 120, 160), "glade": (30, 130, 80), "bones": (120, 110, 90), "forest": (20, 90, 30), "lake": (30, 110, 200),
                 "bandit_camp": (150, 50, 30), "fort": (110, 70, 50), "sunken_chapel": (30, 110, 200), "hollow": (90, 60, 120), "scar_arena": (140, 40, 170),
                 "ruined_shrine": (140, 100, 30)}
    for p in places:
        if p["category"] == "settlement" or p["kind"] not in key_kinds:
            continue
        q = px(p["x"], p["z"])
        col = key_kinds[p["kind"]]
        d.rectangle([q[0] - 2, q[1] - 2, q[0] + 2, q[1] + 2], fill=col + (255,))
        d.text((q[0] + 4, q[1] - 6), p["name"], fill=col + (255,), font=f_s)
    for p in places:
        if p["category"] != "settlement":
            continue
        q = px(p["x"], p["z"])
        rad = {"castle": 6, "town": 5, "frontier_town": 4, "village": 3}.get(p["kind"], 3)
        d.ellipse([q[0] - rad, q[1] - rad, q[0] + rad, q[1] + rad], fill=(200, 30, 30, 255) if p["kind"] == "castle" else (20, 20, 20, 255))
        nm = p["display_name"] + (" (Ironmarch)" if p["name"] == "Ironmarch" else "")
        d.text((q[0] + rad + 2, q[1] - 7), nm, fill=(10, 10, 10, 255), font=f_m)
    d.rectangle([4, npx - 78, 560, npx - 4], fill=(245, 240, 225, 235), outline=(60, 60, 60, 255))
    d.text((10, npx - 74), "Valencious (Region 1) bible map: 12 288 m, grid 1024 m, north up (-z)", fill=(20, 20, 20, 255), font=f_m)
    d.text((10, npx - 56), "Tints = 12 macro sub-regions. Blue = Ashrun, Mere, Silverrun. Brown lines = roads (kingdom thick). Black = settlements.", fill=(20, 20, 20, 255), font=f_s)
    d.text((10, npx - 42), "Squares: purple Rift/Scar, blue Elder Stones/water, green camps/glade/forest, red gate/bandits. Rim box = 250 m edge band.", fill=(20, 20, 20, 255), font=f_s)
    d.text((10, npx - 28), "Positions = live WorldGen dump; values that differ in parchment/WORLD_R1 are alt_pos in valencious_places.json.", fill=(20, 20, 20, 255), font=f_s)
    im.save(os.path.join(DOCS, "valencious_bible_map.png"))


def short_src(sources):
    m = {"WorldGen.settlements (dump_world.gd)": "DUMP", "discovery places (dump_world.gd)": "DUMP", "region1 sites (world_dump.gd)": "R1",
         "first_region.json": "FR", "region1_parchment.json": "PARCH", "WORLD_R1.md": "WR1"}
    out = []
    for s in sources:
        k = m.get(s, s.split(" ")[0])
        if k not in out:
            out.append(k)
    return "+".join(out)


def render_doc(out, regs, places, roads, dump):
    t = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "bible_template.md"), encoding="utf8").read()
    sett = [p for p in places if p["category"] == "settlement"]
    sett.sort(key=lambda p: p["settlement_id"])
    L = ["| id | WorldGen name | display | kind | x | z | radius | pop | sub-region | biome |", "|---|---|---|---|---|---|---|---|---|---|"]
    for p in sett:
        L.append("| %d | %s | %s | %s | %.0f | %.0f | %d | %d | %s | %s |" % (p["settlement_id"], p["name"], p["display_name"], p["kind"], p["x"], p["z"], p["radius"], p["population"], p["subregion"], p["biome"]))
    t = t.replace("{{SETTLEMENTS}}", "\n".join(L))
    W = ["Lake (WorldGen): centre (%.0f, %.0f), radius %.0f m." % (dump["lake"]["center"][0], dump["lake"]["center"][1], dump["lake"]["radius"]), "",
         "| polyline | name | points | start (x, z) | end (x, z) | width start-end (m) |", "|---|---|---|---|---|---|"]
    for i, rv in enumerate(dump["rivers"]):
        W.append("| %d | %s | %d | (%.0f, %.0f) | (%.0f, %.0f) | %.1f - %.1f |" % (i, out["river_names"][i], len(rv), rv[0][0], rv[0][1], rv[-1][0], rv[-1][1], rv[0][2], rv[-1][2]))
    t = t.replace("{{WATER}}", "\n".join(W))
    R = []
    for tier in ("kingdom", "rural", "frontier"):
        rs = [r for r in roads if r["tier"] == tier]
        R.append("**%s** (%d roads, %d m total): " % (tier, len(rs), sum(r["length_m"] for r in rs)) + "; ".join("%d-%d %s - %s (%d m)" % (r["a"], r["b"], r["a_name"], r["b_name"], r["length_m"]) for r in rs))
        R.append("")
    t = t.replace("{{ROADS}}", "\n".join(R))
    G = ["| id | name | lobes (x, z, r) | h_min-h_max (m) | roughness | ridged | biome weights | landmarks inside |", "|---|---|---|---|---|---|---|---|"]
    for r in regs["regions"]:
        inside = [p["display_name"] for p in places if p["subregion"] == r["id"] and p["category"] == "settlement"]
        G.append("| %s | %s | %s | %d-%d | %.2f | %.2f | %s | %s |" % (r["id"], r["name"], " ".join("(%d, %d, %d)" % tuple(l) for l in r["lobes"]), r["h_min"], r["h_max"],
                 r["roughness"], r["ridged"], ", ".join("%s %.2f" % kv for kv in r["biomes"].items()), ", ".join(inside) or "-"))
    G.append("")
    G.append(r["realm_note"] if False else "")
    for r in regs["regions"]:
        G.append("- **%s**: %s." % (r["name"], r["realm_note"]))
    t = t.replace("{{REGIONS}}", "\n".join(G))
    C = ["| place | live (x, z) | other source (x, z) | difference |", "|---|---|---|---|"]
    for p in places:
        for a in p.get("alt_pos", []):
            d = math.hypot(a["x"] - p["x"], a["z"] - p["z"])
            if d > 25:
                C.append("| %s | (%.0f, %.0f) | %s (%.0f, %.0f) | %.0f m |" % (p["name"], p["x"], p["z"], a["src"], a["x"], a["z"], d))
    t = t.replace("{{CONFLICTS}}", "\n".join(C))
    P = ["| id | display name | kind | x | z | sub-region | biome | source |", "|---|---|---|---|---|---|---|---|"]
    for p in places:
        nm = p["display_name"] if p["display_name"] == p["name"] else "%s (%s)" % (p["display_name"], p["name"])
        if p.get("aliases"):
            nm += " [aka %s]" % ", ".join(p["aliases"])
        P.append("| `%s` | %s | %s | %.0f | %.0f | %s | %s | %s |" % (p["id"], nm.replace("|", "/"), p["kind"], p["x"], p["z"], p["subregion"], p["biome"], short_src(p["sources"])))
    t = t.replace("{{PLACES}}", "\n".join(P))
    with open(os.path.join(DOCS, "VALENCIOUS_WORLD.md"), "w", encoding="utf8") as f:
        f.write(t)


if __name__ == "__main__":
    out, regs, places, roads, dump = build()
    render_map(regs, places, roads, dump)
    render_doc(out, regs, places, roads, dump)
    print("map + doc written")
