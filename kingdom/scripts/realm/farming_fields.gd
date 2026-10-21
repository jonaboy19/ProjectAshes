extends RefCounted
## One field's life (LW-3.2). A field is a plain Dictionary:
##   c crop id ("" = fallow), g growth days done, s sown day, f fertility 0..1, m moisture 0..1, p pests 0..1,
##   d disease 0..1, w weeds 0..1, st drought stress 0..1, l1 / l2 family of the last two harvests, irr irrigated 0/1.
## step() moves it forward `dt` days: dt = 1 with an rng for a near farm (real rain, real outbreaks), dt = 7 with no rng for a far
## one (the same rules on their expected values). Yield depends on the field only, never on who works it (harvest_yield).

const D := preload("res://scripts/realm/farming_data.gd")


static func new_field(fertility := D.START_FERTILITY) -> Dictionary:
	return {"c": "", "g": 0.0, "s": -1, "f": fertility, "m": 0.5, "p": 0.0, "d": 0.0, "w": 0.1, "st": 0.0, "l1": "", "l2": "", "irr": 0}


## env: {season, clim, irr_ok (the farm has an irrigation ditch)}. rng null = expected values (far farm).
static func step(F: Dictionary, env: Dictionary, dt: float, rng: RandomNumberGenerator) -> void:
	var season: int = int(env["season"])
	var clim: int = int(env["clim"])
	var rain_p: float = float(D.RAIN_P[season]) * float(D.CLIM_RAIN[clim])
	var evap: float = float(D.EVAP[season]) * float(D.CLIM_EVAP[clim])
	var m: float = float(F["m"])
	if rng != null:
		m += (D.RAIN_AMOUNT if rng.randf() < rain_p else 0.0) * dt - evap * dt
	else:
		m += (rain_p * D.RAIN_AMOUNT - evap) * dt
	if int(F["irr"]) == 1 and bool(env.get("irr_ok", false)):
		m = maxf(m, 0.6)
	F["m"] = clampf(m, 0.0, 1.0)
	var crop: String = String(F["c"])
	if crop == "":
		F["f"] = minf(1.0, float(F["f"]) + 0.003 * dt)
		F["p"] = float(F["p"]) * pow(0.96, dt)
		F["d"] = float(F["d"]) * pow(0.96, dt)
		F["w"] = clampf(float(F["w"]) + 0.01 * dt, 0.0, 1.0)
		return
	var cd: Dictionary = D.CROPS[crop]
	F["f"] = minf(1.0, float(F["f"]) + 0.0005 * dt)
	F["w"] = clampf(float(F["w"]) + (0.02 if season != D.WINTER else 0.004) * dt, 0.0, 1.0)
	var wn: float = float(cd["w"])
	var mm: float = float(F["m"])
	var wf: float = 0.5 + 0.5 * minf(1.0, mm / wn)
	F["g"] = float(F["g"]) + D.growth_rate(crop, season, clim) * wf * dt
	if mm < wn:
		F["st"] = minf(1.0, float(F["st"]) + (wn - mm) * 1.8 * dt / float(cd["d"]))
	var mono := String(F["l1"]) == String(cd["fam"])
	# Outbreaks: a pest or a blight starts small and then feeds on itself until somebody treats the field.
	var p0: float = 0.006 * float(D.PEST_SEASON[season]) * (1.5 if mono else 1.0)
	var d0: float = 0.005 * float(D.DIS_SEASON[season]) * (1.5 if mm > 0.6 else 0.7) * (1.5 if mono else 1.0)
	var pest: float = float(F["p"])
	var dis: float = float(F["d"])
	if rng != null:
		if rng.randf() < p0:
			pest = maxf(pest, 0.08)
		if rng.randf() < d0:
			dis = maxf(dis, 0.08)
	else:
		pest += (1.0 - pow(1.0 - p0, dt)) * 0.08
		dis += (1.0 - pow(1.0 - d0, dt)) * 0.08
	pest += pest * 0.06 * (1.0 - pest) * dt
	dis += dis * 0.05 * (1.0 - dis) * dt
	F["p"] = clampf(pest, 0.0, 1.0)
	F["d"] = clampf(dis, 0.0, 1.0)


## Pests and blight leak to the next field along the rows and columns of the farm (cols wide), `dt` days.
static func spread(fields: Array, cols: int, dt: float) -> void:
	var n := fields.size()
	if n < 2:
		return
	var add_p: Array = []
	var add_d: Array = []
	add_p.resize(n)
	add_d.resize(n)
	for i in n:
		add_p[i] = 0.0
		add_d[i] = 0.0
	var any := false
	for i in n:
		var F: Dictionary = fields[i]
		var p: float = float(F["p"])
		var d: float = float(F["d"])
		if p < 0.12 and d < 0.12:
			continue
		any = true
		for j in neighbours(i, n, cols):
			if p >= 0.12:
				add_p[j] += 0.05 * p * dt
			if d >= 0.12:
				add_d[j] += 0.04 * d * dt
	if not any:
		return
	for i in n:
		var G: Dictionary = fields[i]
		if String(G["c"]) == "" and float(add_p[i]) < 0.05:
			continue
		G["p"] = clampf(float(G["p"]) + float(add_p[i]) * (1.0 - float(G["p"])), 0.0, 1.0)
		G["d"] = clampf(float(G["d"]) + float(add_d[i]) * (1.0 - float(G["d"])), 0.0, 1.0)


static func neighbours(i: int, n: int, cols: int) -> Array:
	var out: Array = []
	var cx := i % cols
	if cx > 0:
		out.append(i - 1)
	if cx < cols - 1 and i + 1 < n:
		out.append(i + 1)
	if i - cols >= 0:
		out.append(i - cols)
	if i + cols < n:
		out.append(i + cols)
	return out


static func is_ready(F: Dictionary) -> bool:
	var crop: String = String(F["c"])
	return crop != "" and float(F["g"]) >= float(D.CROPS[crop]["d"])


static func growth(F: Dictionary) -> float:
	var crop: String = String(F["c"])
	if crop == "":
		return 0.0
	return clampf(float(F["g"]) / float(D.CROPS[crop]["d"]), 0.0, 1.0)


## Units a harvest would give right now. Pure function of the field: manual, hired and steward-run harvests all use this.
static func harvest_yield(F: Dictionary, clim: int) -> int:
	var crop: String = String(F["c"])
	if crop == "":
		return 0
	var cd: Dictionary = D.CROPS[crop]
	var f: float = clampf(float(F["f"]), 0.0, 1.0)
	var y: float = float(cd["y"]) * (0.40 + 0.75 * f)
	if String(F["l1"]) == String(cd["fam"]):
		y *= 0.92                                       # the same family again: monoculture
	elif String(F["l1"]) == "legume" or String(F["l1"]) == "fodder":
		y *= 1.04                                       # after a legume
	y *= 1.0 - 0.45 * float(F["st"])
	y *= 1.0 - 0.55 * float(F["p"])
	y *= 1.0 - 0.50 * float(F["d"])
	y *= 1.0 - 0.25 * float(F["w"])
	y *= float((cd["clim"] as Array)[clim])
	return maxi(0, int(round(y * D.YIELD_MULT)))


## Sow `crop` (the caller checked the season, the seed and that the field is fallow).
static func sow(F: Dictionary, crop: String, day: int) -> void:
	F["c"] = crop
	F["g"] = 0.0
	F["s"] = day
	F["st"] = 0.0
	F["w"] = float(F["w"]) * 0.3
	if String(F["l1"]) != String(D.CROPS[crop]["fam"]):
		F["p"] = float(F["p"]) * 0.2           # a different family starves what lived on the last one
		F["d"] = float(F["d"]) * 0.2


## Cut the crop: returns {crop, qty, seed}. The field goes fallow and loses (or regains) fertility.
static func reap(F: Dictionary, clim: int) -> Dictionary:
	var crop: String = String(F["c"])
	var cd: Dictionary = D.CROPS[crop]
	var qty := harvest_yield(F, clim)
	F["f"] = clampf(float(F["f"]) - float(cd["draw"]), 0.05, 1.0)
	F["l2"] = F["l1"]
	F["l1"] = String(cd["fam"])
	F["c"] = ""
	F["g"] = 0.0
	F["s"] = -1
	F["st"] = 0.0
	F["w"] = 0.1
	F["p"] = float(F["p"]) * 0.3
	F["d"] = float(F["d"]) * 0.2
	return {"crop": crop, "qty": qty, "seed": int(ceil(float(cd["seed"]) * 1.25))}


static func treat(F: Dictionary) -> void:
	F["p"] = maxf(0.0, float(F["p"]) - 0.6)
	F["d"] = maxf(0.0, float(F["d"]) - 0.5)


static func weed(F: Dictionary) -> void:
	F["w"] = 0.05


static func water(F: Dictionary) -> void:
	F["m"] = minf(1.0, float(F["m"]) + 0.4)


static func manure(F: Dictionary) -> void:
	F["f"] = minf(1.0, float(F["f"]) + 0.10)


## The crop the rotation wants here: tired soil (fertility under 0.62) gets a legume or fodder crop if one can be sown now; otherwise the
## first crop of the plan that is not the family just harvested (a legume after a legume is fine); then any other family.
static func rotation_pick(F: Dictionary, season: int, plan: Array) -> String:
	var l1: String = String(F["l1"])
	if float(F["f"]) < 0.62:
		for cid in D.CROP_IDS:
			var fam0 := D.family(cid)
			if (fam0 == "legume" or fam0 == "fodder") and D.can_sow(cid, season):
				return cid
	for c in plan:
		var cid1: String = String(c)
		if D.can_sow(cid1, season) and (D.family(cid1) != l1 or l1 == "legume"):
			return cid1
	for cid2 in D.CROP_IDS:
		if D.can_sow(cid2, season) and D.family(cid2) != l1:
			return cid2
	return ""


## Save form: 13 numbers, no keys.
static func pack(F: Dictionary) -> Array:
	return [D.CROP_IDS.find(String(F["c"])), snappedf(float(F["g"]), 0.1), int(F["s"]), snappedf(float(F["f"]), 0.01), snappedf(float(F["m"]), 0.01),
		snappedf(float(F["p"]), 0.01), snappedf(float(F["d"]), 0.01), snappedf(float(F["w"]), 0.01), snappedf(float(F["st"]), 0.01),
		_fam_i(String(F["l1"])), _fam_i(String(F["l2"])), int(F["irr"])]


static func unpack(a: Array) -> Dictionary:
	var ci := int(a[0])
	return {"c": D.CROP_IDS[ci] if ci >= 0 and ci < D.CROP_IDS.size() else "", "g": float(a[1]), "s": int(a[2]), "f": float(a[3]), "m": float(a[4]),
		"p": float(a[5]), "d": float(a[6]), "w": float(a[7]), "st": float(a[8]), "l1": _fam_s(int(a[9])), "l2": _fam_s(int(a[10])), "irr": int(a[11])}


const _FAMS := ["grain", "root", "legume", "veg", "fibre", "hops", "fodder"]


static func _fam_i(f: String) -> int:
	return _FAMS.find(f)


static func _fam_s(i: int) -> String:
	return _FAMS[i] if i >= 0 and i < _FAMS.size() else ""
