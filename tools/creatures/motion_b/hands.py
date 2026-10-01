import json, sys
d = json.load(open(sys.argv[1])); c = d[sys.argv[2]]; s = float(sys.argv[3]) if len(sys.argv) > 3 else 1
for i, (r, l, h) in enumerate(zip(c["pos"]["RightHand"], c["pos"]["LeftHand"], c["pos"]["Hips"])):
    if i % 3 == 0 or (len(sys.argv) > 4 and int(sys.argv[4]) <= i <= int(sys.argv[5])): print(i + 1, "t=%.2f" % (i / 30), "Rhand z %.2f  Lhand z %.2f  hips z %.2f  minz %.3f" % (r[2], l[2], h[2], c["minz"][i]))
