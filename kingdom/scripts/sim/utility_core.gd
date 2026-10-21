extends RefCounted
## Shared utility scorer (NI-3, docs/design/NPC_INTELLIGENCE_MAP.md section 5). Static and node-free. Used by
## population/utility_brain.gd (near NPCs: product of response curves with compensation, a Dictionary of inputs) and
## realm/minds.gd (registry characters: gates plus weighted curves over a flat input vector, no allocation per call).
## Both share the same response curves; the combiners differ because the two layers think differently
## (an act that any one consideration vetoes, against a life goal that several needs add up to).

## Response curves (Pennycook's set plus a remap). Every curve is clamped to 0..1, except RAW (a * x + b, unclamped) which the additive
## combiner uses for signed inputs such as noise.
##  BINARY    x >= a ? 1 : b             (b is the floor below the threshold)
##  LINEAR    a * x + b
##  EXP       pow(x, a) + b
##  LOGISTIC  1 / (1 + exp(-a * (x - b)))
##  RANGE     lerp(a, b, x)              (a at x = 0, b at x = 1)
enum Resp { BINARY, LINEAR, EXP, LOGISTIC, RANGE, RAW }

## Gate operators for `gates_ok` (the data files spell them as strings, see OPS).
const OP_GE := 0
const OP_LE := 1
const OP_GT := 2
const OP_LT := 3
const OP_EQ := 4
const OP_NE := 5
## What `evaluate` returns when a gate does not hold (no real score is this low).
const GATE_FAIL := -1.0e9
const OPS := {">=": OP_GE, "<=": OP_LE, ">": OP_GT, "<": OP_LT, "==": OP_EQ, "!=": OP_NE}
const RESP_NAMES := {"binary": Resp.BINARY, "linear": Resp.LINEAR, "exp": Resp.EXP, "logistic": Resp.LOGISTIC, "range": Resp.RANGE, "raw": Resp.RAW}
## Floats per flat row: a gate is [input, op, value]; a term is [input, curve, a, b, weight].
const GATE_W := 3
const TERM_W := 5


static func curve(kind: int, x: float, a: float, b: float) -> float:
	var y := 0.0
	match kind:
		Resp.BINARY: y = 1.0 if x >= a else b
		Resp.LINEAR: y = a * x + b
		Resp.EXP: y = pow(maxf(x, 0.0), a) + b
		Resp.LOGISTIC: y = 1.0 / (1.0 + exp(-a * (x - b)))
		Resp.RANGE: y = lerpf(a, b, clampf(x, 0.0, 1.0))
		Resp.RAW: return a * x + b
	return clampf(y, 0.0, 1.0)


## Multiplicative combiner (the near-NPC brain): `base` x the compensated product of the considerations
## `[[input, curve, a, b], ...]` read from `ctx` (missing inputs read 0). One consideration at 0 vetoes the act.
static func product(base: float, cons: Array, ctx: Dictionary) -> float:
	var total := base
	if cons.is_empty():
		return total
	var mod := 1.0 - 1.0 / float(cons.size())
	for c: Array in cons:
		var s := curve(c[1], float(ctx.get(c[0], 0.0)), c[2], c[3])
		if s <= 0.0:
			return 0.0
		total *= s + (1.0 - s) * mod * s
	return total


## Additive combiner (registry characters): all gates must hold, then base + sum of weight x curve(input).
## `gates` and `terms` are flat PackedFloat32Arrays, `inp` the character's input vector. Returns GATE_FAIL when a gate fails.
static func evaluate(base: float, gates: PackedFloat32Array, terms: PackedFloat32Array, inp: PackedFloat32Array) -> float:
	var i := 0
	var n := gates.size()
	while i < n:
		var x := inp[int(gates[i])]
		var v := gates[i + 2]
		match int(gates[i + 1]):
			OP_GE: if x < v: return GATE_FAIL
			OP_LE: if x > v: return GATE_FAIL
			OP_GT: if x <= v: return GATE_FAIL
			OP_LT: if x >= v: return GATE_FAIL
			OP_EQ: if not is_equal_approx(x, v): return GATE_FAIL
			OP_NE: if is_equal_approx(x, v): return GATE_FAIL
		i += GATE_W
	var total := base
	i = 0
	n = terms.size()
	while i < n:
		total += terms[i + 4] * curve(int(terms[i + 1]), inp[int(terms[i])], terms[i + 2], terms[i + 3])
		i += TERM_W
	return total


## The term that moved the score most (index of its row start, -1 when there are none): the "reason" of a trace line.
static func top_term(terms: PackedFloat32Array, inp: PackedFloat32Array) -> int:
	var best := -1
	var bv := 0.0
	var i := 0
	var n := terms.size()
	while i < n:
		var v := absf(terms[i + 4] * curve(int(terms[i + 1]), inp[int(terms[i])], terms[i + 2], terms[i + 3]))
		if v > bv:
			bv = v
			best = i
		i += TERM_W
	return best


## Packs a data row list `[[input_index, op_or_curve, ...], ...]` (already resolved to numbers) into a flat array.
static func pack(rows: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for r: Array in rows:
		for v: Variant in r:
			out.append(float(v))
	return out


## Generates a GDScript object whose `pick(i: PackedFloat32Array) -> int` runs the same gates and terms as `evaluate` over the goals
## `[[goal index, base, gates, terms], ...]` (file order, strict `>` so the earlier goal wins a tie) and returns the winning goal index, or 0
## when nothing beats `threshold`. Straight-line code runs about three times faster than interpreting the tables; the numbers in it are the
## float32-rounded table values, so both paths agree. Returns null when the tables cannot be compiled (a "!=" gate, or the compiler is
## unavailable): callers then keep using `evaluate`.
static func compile(goals: Array, threshold: float) -> Object:
	var src := "extends RefCounted\nconst Core := preload(\"res://scripts/sim/utility_core.gd\")\n\n\nfunc pick(i: PackedFloat32Array) -> int:\n\tvar best := 0\n\tvar bs := %s\n\tvar u := 0.0\n" % _num(threshold)
	for g: Array in goals:
		var gates: PackedFloat32Array = g[2]
		var terms: PackedFloat32Array = g[3]
		var conds: Array = []
		var k := 0
		while k < gates.size():
			var op := int(gates[k + 1])
			var sym := ""
			match op:
				OP_GE: sym = ">="
				OP_LE: sym = "<="
				OP_GT: sym = ">"
				OP_LT: sym = "<"
				OP_EQ: sym = "=="
				_: return null
			conds.append("i[%d] %s %s" % [int(gates[k]), sym, _num(gates[k + 2])])
			k += GATE_W
		var body := "\t\tu = %s" % _num(float(g[1]))
		k = 0
		while k < terms.size():
			var x := "i[%d]" % int(terms[k])
			var a := _num(terms[k + 2])
			var b := _num(terms[k + 3])
			var w := _num(terms[k + 4])
			match int(terms[k + 1]):
				Resp.RAW: body += " + %s * (%s * %s + %s)" % [w, a, x, b]
				Resp.LINEAR: body += " + %s * clampf(%s * %s + %s, 0.0, 1.0)" % [w, a, x, b]
				_: body += " + %s * Core.curve(%d, %s, %s, %s)" % [w, int(terms[k + 1]), x, a, b]
			k += TERM_W
		src += "\tif %s:\n%s\n\t\tif u > bs:\n\t\t\tbs = u\n\t\t\tbest = %d\n" % [" and ".join(conds) if not conds.is_empty() else "true", body, int(g[0])]
	src += "\treturn best\n"
	var scr := GDScript.new()
	scr.source_code = src
	if scr.reload() != OK:
		return null
	return scr.new()


static func _num(v: float) -> String:
	return "%.17f" % v if v >= 0.0 else "(%.17f)" % v
