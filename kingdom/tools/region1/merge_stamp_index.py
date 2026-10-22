"""Folds the `STAMP_INDEX {...}` lines printed by tools_qa/region1/bake_stamps.gd (and bake_valley.gd) into data/region1/terrain_stamps.json.
   py -I kingdom/tools/region1/merge_stamp_index.py <bake log> [<bake log> ...]
An entry with the same id is replaced, new ids are appended; trails and every other key are kept as they are.
"""
import json, os, sys

PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "data", "region1", "terrain_stamps.json")


def main(logs):
    with open(PATH, encoding="utf-8") as f:
        raw = f.read()
    doc = json.loads(raw)
    by_id = {s["id"]: i for i, s in enumerate(doc["stamps"])}
    n = 0
    for log in logs:
        with open(log, encoding="utf-8", errors="replace") as f:
            for line in f:
                if "STAMP_INDEX " not in line:
                    continue
                e = json.loads(line.split("STAMP_INDEX ", 1)[1])
                if e["id"] in by_id:
                    doc["stamps"][by_id[e["id"]]] = e
                else:
                    by_id[e["id"]] = len(doc["stamps"])
                    doc["stamps"].append(e)
                n += 1
    with open(PATH, "w", encoding="utf-8", newline="\n") as f:
        json.dump(doc, f, indent="\t")
    print("merged", n, "entries ->", os.path.normpath(PATH))


if __name__ == "__main__":
    main(sys.argv[1:])
