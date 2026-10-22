extends RefCounted
## Small helpers the realm modules share to write saves as columns instead of dictionaries (docs/design/LIVING_WORLD_SANDBOX.md Part E).
## Nothing here holds state. Every result is plain numbers, strings and arrays, so it survives JSON.stringify and parse_string.
##
##   ids:     "ch:51" -> 51 (a plain int); anything that is not "<prefix>:<canonical int>" stays a string.
##   id list: the gap from the one before; a run of three or more consecutive ids is [run length] after its first.
##   column:  null (every value is the default: not written), a scalar (every value equal), or [most common, gap, value, gap, value ...].

## "ch:51" with prefix "ch" -> 51; a string that is not that shape (or a number with a sign or leading zeros) stays as it is.
static func enc_id(id: String, prefix: String) -> Variant:
	if id.begins_with(prefix) and id.length() > prefix.length() + 1 and id[prefix.length()] == ":":
		var tail := id.substr(prefix.length() + 1)
		if tail.is_valid_int() and str(int(tail)) == tail:
			return int(tail)
	return id


static func dec_id(v: Variant, prefix: String) -> String:
	if v is String:
		return v
	return "%s:%d" % [prefix, int(v)]


static func enc_ids(ids: Array, prefix: String) -> Array:
	var codes: Array = []
	for id: String in ids:
		codes.append(enc_id(id, prefix))
	var out: Array = []
	var base := 0
	var i := 0
	var n := codes.size()
	while i < n:
		var c: Variant = codes[i]
		if c is int:
			out.append(int(c) - base)
			base = int(c)
			var run := 0
			while i + 1 + run < n and codes[i + 1 + run] is int and int(codes[i + 1 + run]) == base + run + 1:
				run += 1
			if run >= 3:
				out.append([run])
				base += run
				i += run
		else:
			out.append(c)
		i += 1
	return out


static func dec_ids(v: Array, prefix: String) -> Array:
	var out: Array = []
	var base := 0
	for x: Variant in v:
		if x is String:
			out.append(x)
		elif x is Array:
			for k in int((x as Array)[0]):
				base += 1
				out.append("%s:%d" % [prefix, base])
		else:
			base += int(x)
			out.append("%s:%d" % [prefix, base])
	return out


## Equal and of the same type (a column that mixes numbers and strings cannot be compared with == in GDScript).
static func same(a: Variant, b: Variant) -> bool:
	return typeof(a) == typeof(b) and a == b


## One column of values -> null (all equal to `dflt`), a scalar (all equal), or [most common, gap, value, gap, value ...].
static func col(vals: Array, dflt: Variant) -> Variant:
	var n := vals.size()
	if n == 0:
		return null
	var cnt := {}
	var best: Variant = vals[0]
	var bc := 0
	for v: Variant in vals:
		var c := int(cnt.get(v, 0)) + 1
		cnt[v] = c
		if c > bc:
			bc = c
			best = v
	if bc == n:
		return null if same(best, dflt) else best
	var out: Array = [best]
	var last := 0
	for i in n:
		if not same(vals[i], best):
			out.append(i - last)
			out.append(vals[i])
			last = i
	return out


static func uncol(v: Variant, n: int, dflt: Variant) -> Array:
	var out: Array = []
	out.resize(n)
	if v == null:
		out.fill(dflt)
	elif v is Array:
		var a: Array = v
		out.fill(a[0])
		var i := 1
		var at := 0
		while i + 1 < a.size():
			at += int(a[i])
			if at >= 0 and at < n:
				out[at] = a[i + 1]
			i += 2
	else:
		out.fill(v)
	return out


## A float rounded to `step`, written as an int when it is a whole number (JSON prints 5.0 as "5.0", 5 as "5").
static func num(v: float, step: float) -> Variant:
	var r := snappedf(v, step)
	return int(r) if r == floorf(r) and absf(r) < 1.0e15 else r
