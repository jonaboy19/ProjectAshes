class_name AshFakeRaid
extends RefCounted
## A scripted stand-in for a sim raid, used by the Ashsight sandbox, demo and tests: 4 bandits
## and 2 villagers around a runestone at the origin. Ground truth is a smooth curve through
## time-keyed waypoints (plus a little walk sway), evaluated at ANY time, so a recorded and
## replayed path can be compared with what really happened.
##
## Story (26 s): bandits run in from the north-east, two chisel the stone, two go for the
## villagers, who run away south-west; the bandits flee the way they came.

const DURATION := 26.0
const SITE_NAME := "Western Road Stone"
const STONE_POS := Vector2(0.0, 0.0)
const BANDITS := ["b1", "b2", "b3", "b4"]
const VILLAGERS := ["v1", "v2"]
const MARKS := [[0.0, "riders arrive"], [11.0, "chisel"], [12.5, "villagers flee"], [17.0, "bandits flee"]]

# id -> [[t, x, z], ...]
const KNOTS := {
	"b1": [[0, 40, -38], [3, 30, -28], [6, 18, -16], [9, 6, -5], [11, 2, -2], [16, 2.5, -1.5], [18, 6, -6], [21, 20, -22], [24, 38, -40], [26, 46, -47]],
	"b2": [[0, 42, -33], [3, 31, -24], [6, 19, -12], [9, 7, -1], [11, 3, 2], [16, 3.5, 2.5], [18, 8, -2], [21, 22, -18], [24, 40, -36], [26, 48, -43]],
	"b3": [[0, 42, -30], [3, 32, -22], [6, 20, -10], [9, 6, 0], [12, -6, 5], [14, -9, 6], [17, -6, 2], [20, 8, -12], [23, 28, -30], [26, 46, -44]],
	"b4": [[0, 38, -36], [3, 30, -24], [6, 20, -8], [9, 8, 2], [12, -4, 8], [14, -11, 4], [17, -8, -1], [20, 6, -14], [23, 26, -32], [26, 44, -44]],
	"v1": [[0, -8, 6], [4, -9, 7.5], [8, -7.5, 5.5], [10, -8, 6], [12, -14, 6], [15, -24, 4], [18, -36, 0], [21, -50, -6], [24, -64, -10], [26, -72, -12]],
	"v2": [[0, -12, 2], [5, -11, 3.5], [9, -12, 2], [11, -16, -2], [14, -26, -8], [17, -38, -16], [20, -50, -22], [23, -62, -28], [26, -70, -32]],
}


static func role_of(id: String) -> String:
	return "bandit" if id.begins_with("b") else "villager"


## Where actor `id` really is at time `t` (seconds).
static func position_of(id: String, t: float) -> Vector2:
	var k: Array = KNOTS[id]
	var tc := clampf(t, float(k[0][0]), float(k[k.size() - 1][0]))
	var i := 0
	while i < k.size() - 2 and float(k[i + 1][0]) <= tc:
		i += 1
	var t0 := float(k[i][0])
	var t1 := float(k[i + 1][0])
	var p0 := Vector2(float(k[i][1]), float(k[i][2]))
	var p1 := Vector2(float(k[i + 1][1]), float(k[i + 1][2]))
	var pm := p0 if i == 0 else Vector2(float(k[i - 1][1]), float(k[i - 1][2]))
	var tm := t0 if i == 0 else float(k[i - 1][0])
	var pp := p1 if i + 2 >= k.size() else Vector2(float(k[i + 2][1]), float(k[i + 2][2]))
	var tp := t1 if i + 2 >= k.size() else float(k[i + 2][0])
	var h := t1 - t0
	var u := clampf((tc - t0) / h, 0.0, 1.0)
	var m0 := (p1 - pm) / (t1 - tm) * h if tm < t0 else (p1 - p0)
	var m1 := (pp - p0) / (tp - t0) * h if tp > t1 else (p1 - p0)
	var u2 := u * u
	var u3 := u2 * u
	var pos := (2.0 * u3 - 3.0 * u2 + 1.0) * p0 + (u3 - 2.0 * u2 + u) * m0 \
		+ (-2.0 * u3 + 3.0 * u2) * p1 + (u3 - u2) * m1
	# small walk sway so nobody moves on rails
	var ph := float(id.hash() % 100) * 0.13
	return pos + Vector2(sin(t * 2.3 + ph), cos(t * 1.9 + ph * 1.7)) * 0.12


static func alive_at(id: String, t: float) -> bool:
	var k: Array = KNOTS[id]
	return t >= float(k[0][0]) and t <= float(k[k.size() - 1][0])


## Ground truth for everyone: [{id, role, pos}].
static func truth(t: float) -> Array:
	var out: Array = []
	for id: String in KNOTS:
		if alive_at(id, t):
			out.append({"id": id, "role": role_of(id), "pos": position_of(id, t)})
	return out


## Feed a raid into an AshMemory the way the game emitters would: begin at t=0, sample once
## per second of `clock` time, mark the beats, end at the end. `t_offset` shifts the clock so
## tests can prove nothing depends on it starting at zero. Returns the incident id.
static func record_into(mem: AshMemory, t_offset: float = 100.0) -> int:
	mem.flag_site(SITE_NAME, STONE_POS)
	var id := mem.begin_incident(&"raid", STONE_POS, t_offset)
	var next_mark := 0
	var t := 0.0
	while t <= DURATION + 0.0001:
		mem.sample(t_offset + t, truth(t))
		while next_mark < MARKS.size() and float(MARKS[next_mark][0]) <= t:
			mem.mark(id, t_offset + float(MARKS[next_mark][0]), String(MARKS[next_mark][1]))
			next_mark += 1
		t += 1.0
	mem.end_incident(id, t_offset + DURATION)
	return id


## Largest distance between replayed and true positions over the recorded lifetime of each
## actor (sampled every `step` seconds). Returns {max_error, worst_actor, samples}.
static func max_replay_error(mem: AshMemory, id: int, step: float = 0.05) -> Dictionary:
	var worst := 0.0
	var who := ""
	var n := 0
	var info := mem.replay_info(id)
	for a: Dictionary in info.get("actors", []):
		var aid := String(a["id"])
		var t := float(a["first"])
		while t <= float(a["last"]):
			for e: Dictionary in mem.positions_at(id, t):
				if String(e["id"]) == aid:
					var err := (e["pos"] as Vector2).distance_to(position_of(aid, t))
					n += 1
					if err > worst:
						worst = err
						who = aid
			t += step
	return {"max_error": worst, "worst_actor": who, "samples": n}
