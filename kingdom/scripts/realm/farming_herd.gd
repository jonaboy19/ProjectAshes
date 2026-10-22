extends RefCounted
## Livestock (LW-3.2): owned animals with feed, water, shelter, breeding, ageing, sickness and theft.
## NEAR a farm every animal is a record, stepped daily:
##   [sp, age, sex (1 female), hp 0..1, fed 0..1, sick (0/1), due day (-1), lactating until day (-1), last shear day]
## FAR from the player the herd is folded into one cohort per species (collapse) and stepped on its expected values
## (step_far, any dt); coming near again unfolds it (expand). Counts, mean age, sickness, hunger and pregnancies survive the fold.
## A cohort: {n adult females, m adult males, y young, ya mean young age, aa mean adult age, pg pregnant, lc lactating, sk sick share, hp, fed}.

const D := preload("res://scripts/realm/farming_data.gd")

const A_SP := 0
const A_AGE := 1
const A_SEX := 2
const A_HP := 3
const A_FED := 4
const A_SICK := 5
const A_DUE := 6
const A_LACT := 7
const A_SHEAR := 8


static func new_animal(sp: String, age: int, female: bool, day: int, rng: RandomNumberGenerator = null) -> Array:
	var sd: Dictionary = D.ANIMALS[sp]
	var shear := day - (rng.randi_range(0, int(sd["shear"])) if rng != null and int(sd["shear"]) > 0 else 0)
	return [D.SPECIES.find(sp), age, 1 if female else 0, 1.0, 0.8, 0, -1, -1, shear]


static func species_of(a: Array) -> String:
	return D.SPECIES[int(a[A_SP])]


static func is_adult(a: Array) -> bool:
	return int(a[A_AGE]) >= int(D.ANIMALS[species_of(a)]["mat"])


static func space_of(H: Array) -> float:
	var s := 0.0
	for a: Array in H:
		s += float(D.ANIMALS[species_of(a)]["space"])
	return s


static func counts(H: Array) -> Dictionary:
	var out := {}
	for a: Array in H:
		var sp := species_of(a)
		out[sp] = int(out.get(sp, 0)) + 1
	return out


## Meat an animal leaves when it dies or is slaughtered (units of its meat good).
static func carcass(sp: String, age: int) -> int:
	var sd: Dictionary = D.ANIMALS[sp]
	if String(sd["meat"]) == "":
		return 0
	return 1 if age < int(sd["mat"]) else maxi(1, int(round(float(sd["price"]) / 12.0)))


## What the market pays for this animal (before specialisation).
static func value(a: Array) -> int:
	var sd: Dictionary = D.ANIMALS[species_of(a)]
	var base: float = float(sd["price"]) if is_adult(a) else lerpf(float(sd["young"]), float(sd["price"]), clampf(float(a[A_AGE]) / float(sd["mat"]), 0.0, 1.0))
	if int(a[A_AGE]) > int(sd["old"]):
		base *= 0.5
	return maxi(1, int(round(base * (0.4 + 0.6 * float(a[A_HP])) * (0.6 if int(a[A_SICK]) == 1 else 1.0))))


static func _feed(store: Dictionary, items: Array, need: float) -> float:
	var got := 0.0
	for it in items:
		var have: float = float(store.get(it, 0.0))
		if have <= 0.0:
			continue
		var take := minf(have, need - got)
		store[it] = have - take
		got += take
		if got >= need - 0.0001:
			break
	return got


static func _breeds_now(sp: String, season: int) -> bool:
	return season == D.SPRING or (season == D.SUMMER and sp != "horse")


## One day for every animal of the farm. env: {day, season, graze (animal space the pastures carry), water, shelter (space the
## buildings give), spec, treat (somebody tends the sick)}. Products and carcasses go into `store`. Returns the day's report.
static func step_near(H: Array, env: Dictionary, store: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var rep := {"born": 0, "died": 0, "sick": 0, "cured": 0, "milk": 0.0, "wool": 0.0, "egg": 0.0}
	var n := H.size()
	if n == 0:
		return rep
	var day: int = int(env["day"])
	var season: int = int(env["season"])
	var spec: String = String(env.get("spec", ""))
	var mult: float = float(D.SPECS.get(spec, D.SPECS[""])["mult"])
	var space := space_of(H)
	var shelter: float = float(env.get("shelter", D.SHELTER_BASE))
	var crowd := clampf(space / maxf(shelter, 0.1) - 1.0, 0.0, 2.0)
	var exposed := season == D.WINTER and shelter < space
	var graze_cover: float = float(D.GRAZE[season]) * minf(1.0, float(env.get("graze", 0.0)) / maxf(space, 0.1))
	var water: bool = bool(env.get("water", true))
	var treat: bool = bool(env.get("treat", false))
	var males := {}
	var sick_n := 0
	for a: Array in H:
		if int(a[A_SICK]) == 1:
			sick_n += 1
		if int(a[A_SEX]) == 0 and is_adult(a):
			var sp0 := species_of(a)
			males[sp0] = int(males.get(sp0, 0)) + 1
	var sick_frac := float(sick_n) / float(n)
	var born: Array = []
	for i in range(n - 1, -1, -1):
		var a: Array = H[i]
		var sp := species_of(a)
		var sd: Dictionary = D.ANIMALS[sp]
		a[A_AGE] = int(a[A_AGE]) + 1
		var adult := is_adult(a)
		var need: float = float(sd["feed"]) * (1.0 - graze_cover) * (1.0 if adult else 0.5)
		var got := _feed(store, sd["items"], need) if need > 0.0001 else 0.0
		var ratio := 1.0 if need <= 0.0001 else got / need
		a[A_FED] = clampf(float(a[A_FED]) + (ratio - float(a[A_FED])) * 0.3, 0.0, 1.0)
		var hp: float = float(a[A_HP])
		if not water:
			hp -= 0.05
		if float(a[A_FED]) < 0.25:
			hp -= 0.06
		elif float(a[A_FED]) > 0.7:
			hp += 0.03
		if exposed:
			hp -= 0.02
		if int(a[A_SICK]) == 1:
			hp -= 0.05
			if rng.randf() < 0.12 + (0.30 if treat else 0.0):
				a[A_SICK] = 0
				rep["cured"] += 1
		else:
			var pr: float = 0.004 * (1.0 + 2.0 * (1.0 - float(a[A_FED])) + crowd + (0.5 if exposed else 0.0)) + 0.01 * sick_frac
			if rng.randf() < pr:
				a[A_SICK] = 1
				rep["sick"] += 1
		a[A_HP] = clampf(hp, 0.0, 1.0)
		var dead := float(a[A_HP]) <= 0.0 or int(a[A_AGE]) >= int(sd["life"])
		if not dead and int(a[A_AGE]) > int(sd["old"]):
			dead = rng.randf() < 0.004 + 0.001 * float(int(a[A_AGE]) - int(sd["old"])) / 10.0
		if dead:
			var meat := carcass(sp, int(a[A_AGE]))
			if meat > 0 and int(a[A_SICK]) == 0:
				store[String(sd["meat"])] = float(store.get(String(sd["meat"]), 0.0)) + meat
			H.remove_at(i)
			rep["died"] += 1
			continue
		if not adult:
			continue
		if int(a[A_SEX]) == 1:
			var due: int = int(a[A_DUE])
			if due >= 0:
				if day >= due:
					var litter := rng.randi_range(1, int(sd["litter"]))
					for _k in litter:
						born.append(new_animal(sp, 0, rng.randf() < (0.8 if sp == "chicken" else 0.5), day))
					a[A_DUE] = -1
					if int(sd["lact"]) > 0:
						a[A_LACT] = day + int(sd["lact"])
			elif int(males.get(sp, 0)) > 0 and _breeds_now(sp, season) and float(a[A_FED]) > 0.7 and float(a[A_HP]) > 0.6 \
					and rng.randf() < float(sd["br"]) * (mult if spec == "horse" and sp == "horse" else 1.0):
				a[A_DUE] = day + int(sd["gest"])
			if String(sd["prod"]) == "milk" and int(a[A_LACT]) > day:
				var q := float(sd["rate"]) * float(a[A_FED]) * (mult if spec == "dairy" else 1.0)
				store["milk"] = float(store.get("milk", 0.0)) + q
				rep["milk"] += q
			elif String(sd["prod"]) == "egg":
				var qe := float(sd["rate"]) * float(a[A_FED]) * (0.5 if season == D.WINTER else 1.0)
				store["egg"] = float(store.get("egg", 0.0)) + qe
				rep["egg"] += qe
		if String(sd["prod"]) == "wool" and day - int(a[A_SHEAR]) >= int(sd["shear"]):
			var qw := float(sd["rate"]) * (mult if spec == "wool" else 1.0)
			store["wool"] = float(store.get("wool", 0.0)) + qw
			rep["wool"] += qw
			a[A_SHEAR] = day
	for b in born:
		H.append(b)
	rep["born"] = born.size()
	return rep


# ---------------------------------------------------------------- the far herd

static func collapse(H: Array, day: int) -> Dictionary:
	var C := {}
	for a: Array in H:
		var sp := species_of(a)
		var sd: Dictionary = D.ANIMALS[sp]
		if not C.has(sp):
			C[sp] = {"n": 0.0, "m": 0.0, "y": 0.0, "ya": 0.0, "aa": 0.0, "pg": 0.0, "lc": 0.0, "sk": 0.0, "hp": 0.0, "fed": 0.0}
		var c: Dictionary = C[sp]
		if int(a[A_AGE]) < int(sd["mat"]):
			c["y"] += 1.0
			c["ya"] += float(a[A_AGE])
		else:
			c["aa"] += float(a[A_AGE])
			if int(a[A_SEX]) == 1:
				c["n"] += 1.0
				if int(a[A_DUE]) >= 0:
					c["pg"] += 1.0
				if int(a[A_LACT]) > day:
					c["lc"] += 1.0
			else:
				c["m"] += 1.0
		c["sk"] += float(a[A_SICK])
		c["hp"] += float(a[A_HP])
		c["fed"] += float(a[A_FED])
	for sp in C:
		var c2: Dictionary = C[sp]
		var tot: float = float(c2["n"]) + float(c2["m"]) + float(c2["y"])
		var ad: float = float(c2["n"]) + float(c2["m"])
		c2["ya"] = float(c2["ya"]) / maxf(1.0, float(c2["y"]))
		c2["aa"] = float(c2["aa"]) / maxf(1.0, ad)
		c2["sk"] = float(c2["sk"]) / tot
		c2["hp"] = float(c2["hp"]) / tot
		c2["fed"] = float(c2["fed"]) / tot
	return C


static func _round(x: float, rng: RandomNumberGenerator) -> int:
	var f := floorf(x)
	return int(f) + (1 if rng.randf() < x - f else 0)


static func expand(C: Dictionary, day: int, rng: RandomNumberGenerator) -> Array:
	var H: Array = []
	for sp: String in C:
		var c: Dictionary = C[sp]
		var sd: Dictionary = D.ANIMALS[sp]
		var nf := _round(float(c["n"]), rng)
		var nm := _round(float(c["m"]), rng)
		var ny := _round(float(c["y"]), rng)
		var start := H.size()
		for i in nf + nm + ny:
			var young := i >= nf + nm
			var age: int
			if young:
				age = clampi(int(round(float(c["ya"]) + rng.randf_range(-6.0, 6.0))), 0, int(sd["mat"]) - 1)
			else:
				age = maxi(int(sd["mat"]), int(round(float(c["aa"]) * rng.randf_range(0.8, 1.2))))
			var a := new_animal(sp, age, (i < nf) or (young and rng.randf() < 0.5), day, rng)
			a[A_HP] = clampf(float(c["hp"]), 0.05, 1.0)
			a[A_FED] = clampf(float(c["fed"]), 0.0, 1.0)
			a[A_SICK] = 1 if rng.randf() < float(c["sk"]) else 0
			H.append(a)
		var pg := mini(nf, _round(float(c["pg"]), rng))
		var lc := mini(nf, _round(float(c["lc"]), rng))
		for i in nf:
			var a2: Array = H[start + i]
			if i < pg:
				a2[A_DUE] = day + rng.randi_range(1, int(sd["gest"]))
			if i < lc:
				a2[A_LACT] = day + rng.randi_range(1, maxi(1, int(sd["lact"])))
	return H


static func cohort_total(C: Dictionary) -> int:
	var t := 0.0
	for sp in C:
		var c: Dictionary = C[sp]
		t += float(c["n"]) + float(c["m"]) + float(c["y"])
	return int(round(t))


## `dt` days of the whole far herd on expected values. env as step_near. Same rules, no rng.
static func step_far(C: Dictionary, env: Dictionary, store: Dictionary, dt: float) -> Dictionary:
	var rep := {"born": 0.0, "died": 0.0, "milk": 0.0, "wool": 0.0, "egg": 0.0}
	var season: int = int(env["season"])
	var spec: String = String(env.get("spec", ""))
	var mult: float = float(D.SPECS.get(spec, D.SPECS[""])["mult"])
	var space := 0.0
	for sp0: String in C:
		var c0: Dictionary = C[sp0]
		space += (float(c0["n"]) + float(c0["m"]) + float(c0["y"])) * float(D.ANIMALS[sp0]["space"])
	if space <= 0.0:
		return rep
	var shelter: float = float(env.get("shelter", D.SHELTER_BASE))
	var crowd := clampf(space / maxf(shelter, 0.1) - 1.0, 0.0, 2.0)
	var exposed := season == D.WINTER and shelter < space
	var graze_cover: float = float(D.GRAZE[season]) * minf(1.0, float(env.get("graze", 0.0)) / maxf(space, 0.1))
	var water: bool = bool(env.get("water", true))
	var treat: bool = bool(env.get("treat", false))
	var gone: Array = []
	for sp: String in C:
		var c: Dictionary = C[sp]
		var sd: Dictionary = D.ANIMALS[sp]
		var ad: float = float(c["n"]) + float(c["m"])
		var tot: float = ad + float(c["y"])
		if tot < 0.05:
			gone.append(sp)
			continue
		var need: float = float(sd["feed"]) * (1.0 - graze_cover) * (ad + 0.5 * float(c["y"])) * dt
		var got := _feed(store, sd["items"], need) if need > 0.0001 else 0.0
		var ratio := 1.0 if need <= 0.0001 else got / need
		var fed: float = float(c["fed"])
		fed += (ratio - fed) * (1.0 - pow(0.7, dt))
		c["fed"] = clampf(fed, 0.0, 1.0)
		var hp: float = float(c["hp"])
		if not water:
			hp -= 0.05 * dt
		if fed < 0.25:
			hp -= 0.06 * dt
		elif fed > 0.7:
			hp += 0.03 * dt
		if exposed:
			hp -= 0.02 * dt
		c["hp"] = clampf(hp, 0.05, 1.0)
		var sk: float = float(c["sk"])
		var inc: float = 0.004 * (1.0 + 2.0 * (1.0 - fed) + crowd + (0.5 if exposed else 0.0)) + 0.01 * sk
		var rec: float = 0.12 + (0.30 if treat else 0.0)
		sk += (inc * (1.0 - sk) - rec * sk) * dt
		c["sk"] = clampf(sk, 0.0, 1.0)
		# Deaths: sickness, starvation, old age.
		var aa: float = float(c["aa"])
		var old: float = float(sd["old"])
		var d_rate: float = sk * 0.01 * (1.0 + 2.0 * (1.0 - fed))
		if float(c["hp"]) < 0.3:
			d_rate += 0.15
		d_rate += clampf((aa - 0.8 * old) / (0.2 * old + 100.0), 0.0, 1.0) * 0.02
		var dead := tot * (1.0 - pow(1.0 - minf(d_rate, 0.9), dt))
		dead = minf(dead, tot)
		var share := dead / tot
		c["n"] = float(c["n"]) * (1.0 - share)
		c["m"] = float(c["m"]) * (1.0 - share)
		c["y"] = float(c["y"]) * (1.0 - share)
		c["pg"] = float(c["pg"]) * (1.0 - share)
		c["lc"] = float(c["lc"]) * (1.0 - share)
		rep["died"] += dead
		var meat := dead * (1.0 - sk) * float(carcass(sp, int(aa)))
		if meat > 0.0 and String(sd["meat"]) != "":
			store[String(sd["meat"])] = float(store.get(String(sd["meat"]), 0.0)) + meat
		# Breeding, birth, growing up.
		var nf: float = float(c["n"])
		if nf > 0.0 and float(c["m"]) >= 0.5 and _breeds_now(sp, season) and fed > 0.7 and float(c["hp"]) > 0.6:
			var conceive := (nf - float(c["pg"])) * float(sd["br"]) * (mult if spec == "horse" and sp == "horse" else 1.0) * dt
			c["pg"] = minf(nf, float(c["pg"]) + maxf(0.0, conceive))
		var birth_mothers: float = float(c["pg"]) * minf(1.0, dt / float(sd["gest"]))
		var kids: float = birth_mothers * (1.0 + float(sd["litter"])) * 0.5
		c["pg"] = float(c["pg"]) - birth_mothers
		if float(sd["lact"]) > 0.0:
			c["lc"] = minf(nf, float(c["lc"]) + birth_mothers)
			c["lc"] = float(c["lc"]) * pow(1.0 - 1.0 / float(sd["lact"]), dt)
		var y_old: float = float(c["y"])
		c["ya"] = ((float(c["ya"]) + dt) * y_old + dt * 0.5 * kids) / maxf(y_old + kids, 0.0001)
		c["y"] = y_old + kids
		rep["born"] += kids
		var grow := 0.0
		if float(c["ya"]) >= float(sd["mat"]) * 0.5:
			grow = minf(float(c["y"]), float(c["y"]) * minf(1.0, dt / maxf(1.0, float(sd["mat"]) - float(c["ya"]))))
		if grow > 0.0:
			var fem := 0.8 if sp == "chicken" else 0.5
			c["y"] = float(c["y"]) - grow
			var ad2: float = float(c["n"]) + float(c["m"])
			c["aa"] = (float(c["aa"]) * ad2 + float(sd["mat"]) * grow) / maxf(ad2 + grow, 0.0001) + dt
			c["n"] = float(c["n"]) + grow * fem
			c["m"] = float(c["m"]) + grow * (1.0 - fem)
		else:
			c["aa"] = float(c["aa"]) + dt
		# Products.
		var adults: float = float(c["n"]) + float(c["m"])
		if String(sd["prod"]) == "milk":
			var q := float(c["lc"]) * float(sd["rate"]) * fed * (mult if spec == "dairy" else 1.0) * dt
			store["milk"] = float(store.get("milk", 0.0)) + q
			rep["milk"] += q
		elif String(sd["prod"]) == "egg":
			var qe := float(c["n"]) * float(sd["rate"]) * fed * (0.5 if season == D.WINTER else 1.0) * dt
			store["egg"] = float(store.get("egg", 0.0)) + qe
			rep["egg"] += qe
		elif String(sd["prod"]) == "wool":
			var qw := adults * float(sd["rate"]) / float(sd["shear"]) * (mult if spec == "wool" else 1.0) * dt
			store["wool"] = float(store.get("wool", 0.0)) + qw
			rep["wool"] += qw
	for sp1 in gone:
		C.erase(sp1)
	return rep


## One animal stolen from a far herd (the most valuable species first). Returns the species or "".
static func steal_far(C: Dictionary, rng: RandomNumberGenerator) -> String:
	var best := ""
	var best_w := 0.0
	for sp: String in C:
		var c: Dictionary = C[sp]
		var tot: float = float(c["n"]) + float(c["m"]) + float(c["y"])
		if tot < 1.0:
			continue
		var w: float = float(D.ANIMALS[sp]["price"]) * tot * rng.randf_range(0.5, 1.0)
		if w > best_w:
			best_w = w
			best = sp
	if best == "":
		return ""
	var c2: Dictionary = C[best]
	var tot2: float = float(c2["n"]) + float(c2["m"]) + float(c2["y"])
	for k: String in ["n", "m", "y", "pg", "lc"]:
		c2[k] = float(c2[k]) * (1.0 - 1.0 / tot2)
	return best


static func pack_cohort(c: Dictionary) -> Array:
	return [snappedf(float(c["n"]), 0.01), snappedf(float(c["m"]), 0.01), snappedf(float(c["y"]), 0.01), snappedf(float(c["ya"]), 0.1),
		snappedf(float(c["aa"]), 0.1), snappedf(float(c["pg"]), 0.01), snappedf(float(c["lc"]), 0.01), snappedf(float(c["sk"]), 0.01),
		snappedf(float(c["hp"]), 0.01), snappedf(float(c["fed"]), 0.01)]


static func unpack_cohort(a: Array) -> Dictionary:
	return {"n": float(a[0]), "m": float(a[1]), "y": float(a[2]), "ya": float(a[3]), "aa": float(a[4]), "pg": float(a[5]),
		"lc": float(a[6]), "sk": float(a[7]), "hp": float(a[8]), "fed": float(a[9])}
