extends RefCounted
## Decision and causal trace service (NI-6, docs/design/NPC_INTELLIGENCE_MAP.md): the data a dev inspector (NI-11) shows. Static and node-free, built on
## what the modules already keep: the near-tier decision ring in minds.gd (trace(), trace_inputs()), the persona and psyche records, the plan, and the
## parent link every chain event carries in events.gd. No text comes from a model: every line is a template over those numbers. Nothing here costs
## anything while it is not asked; the rings it reads are bounded (3 decisions a near character, 2,000 events, 60 person effects).
##
##   Trace.why(hub, ch)          -> why did `ch` do what it did (decision, inputs, persona, mood, memories, plan, chain effects, text)
##   Trace.caused_by(hub, n)     -> what caused event n: the ancestors, nearest first, up to MAX_DEPTH
##   Trace.effects_of(hub, n)    -> what event n caused: its direct children and theirs, up to MAX_DEPTH, with a cap on rows
##   Trace.chain_of(hub, cid)    -> a chain's cause: its trigger event, its parent chain, and the events it wrote

const MAX_DEPTH := 8
const MAX_ROWS := 40
const Persona := preload("res://scripts/realm/persona.gd")
const TRAITS := {"bold": Persona.O_BOLD, "warm": Persona.O_WARM, "disc": Persona.O_DISC, "vol": Persona.O_VOL, "hon": Persona.O_HON, "loy": Persona.O_LOY,
	"amb": Persona.O_AMB, "pri": Persona.O_PRI}


## "Why did X do Y": {ok, ch, day, goal, top: [{goal, score, why}] (best three candidates), inputs: {name: value}, persona: {trait: 0..1} (those that
## moved the decision), mood: {...}, memories: [...], plan: {...}, effects: [chain effects on the person], text}. ok is false for an unknown or far character
## (far characters keep no decision ring: `goal` is still their last choice).
static func why(hub: Variant, ch: String) -> Dictionary:
	var out := {"ok": false, "ch": ch, "day": -1, "goal": "", "top": [], "inputs": {}, "persona": {}, "mood": {}, "memories": [], "plan": {}, "effects": [], "text": ""}
	var mn: Variant = hub.mod("minds") if hub != null else null
	if mn == null or not mn.is_mind(ch):
		out["text"] = "Nobody by that name is being watched."
		return out
	out["goal"] = String(mn.goal_of(ch))
	var tr: Array = mn.trace(ch)
	var lines: Array = []
	if not tr.is_empty():
		var t: Dictionary = tr[0]
		out["ok"] = true
		out["day"] = int(t["day"])
		out["goal"] = String(t["goal"])
		out["top"] = (t["scores"] as Array).slice(0, 3)
		out["inputs"] = mn.trace_inputs(ch)
		var why_in := ""
		for r: Dictionary in out["top"]:
			if String(r["goal"]) == String(t["goal"]):
				why_in = String(r["why"])
		if String(t["goal"]) == "idle":
			lines.append("%s did nothing in particular on day %d: no goal beat %.2f." % [ch, int(t["day"]), float(t["threshold"])])
		else:
			lines.append("%s chose %s on day %d%s." % [ch, String(t["goal"]), int(t["day"]), (", mostly because of %s (%s)" % [why_in, str((out["inputs"] as Dictionary).get(why_in, "-"))]) if why_in != "" else ""])
		var alts: Array = []
		for r2: Dictionary in (out["top"] as Array):
			if String(r2["goal"]) != String(t["goal"]):
				alts.append("%s %.2f" % [r2["goal"], float(r2["score"])])
		if not alts.is_empty():
			lines.append("Also considered: %s." % ", ".join(alts))
	else:
		lines.append("%s last decided %s; no detail is kept for characters away from the focus." % [ch, out["goal"]])
	# persona terms that mattered: the extremes
	var pe: Variant = hub.mod("persona")
	if pe != null and pe.has(ch):
		var o: int = pe.off(ch)
		var pb: PackedByteArray = pe.buf()
		var ps_: Dictionary = {}
		var bits: Array = []
		for k: String in TRAITS:
			var v := float(pb[o + int(TRAITS[k])]) / 255.0
			ps_[k] = snappedf(v, 0.01)
			if v >= 0.7 or v <= 0.3:
				bits.append("%s %s" % ["high" if v >= 0.7 else "low", k])
		out["persona"] = ps_
		if not bits.is_empty():
			lines.append("Temperament: %s." % ", ".join(bits))
	var psy: Variant = hub.mod("psyche")
	if psy != null and psy.has(ch):
		out["mood"] = psy.mood(ch)
		var mem: Array = psy.memories(ch)
		out["memories"] = mem.slice(0, 3)
		for m: Dictionary in out["memories"]:
			lines.append("Remembers %s." % str(m.get("kind", m.get("k", "something"))))
	var em: Variant = hub.mod("emergence")
	if em != null:
		out["effects"] = (em.person_fx(ch) as Array).slice(0, 3)
		for e: Dictionary in out["effects"]:
			lines.append("On day %d a %s event (chain %d) weighed on it." % [int(e["day"]), e["kind"], int(e["chain"])])
	if mn.has_method("plan_of"):
		var pl: Dictionary = mn.plan_of(ch)
		out["plan"] = pl
		if not pl.is_empty():
			lines.append("Following plan %s (commitment %d/255), next: %s." % [pl["id"], int(pl["commit"]), ", ".join(pl["steps"]) if not (pl["steps"] as Array).is_empty() else "nothing left"])
	out["text"] = " ".join(lines)
	return out


## "What caused event n": the chain of parent events, nearest cause first, at most MAX_DEPTH long. {ok, event, causes: [event rows], truncated (a cause has
## left the ring or the depth cap stopped the walk), text}. Cycles cannot form (a parent always has a lower number) but the walk is guarded anyway.
static func caused_by(hub: Variant, n: int) -> Dictionary:
	var ev: Variant = hub.mod("events") if hub != null else null
	var out := {"ok": false, "event": {}, "causes": [], "truncated": false, "text": ""}
	if ev == null:
		return out
	var e: Dictionary = ev.get_event(n)
	if e.is_empty():
		out["text"] = "Event %d is no longer on record." % n
		return out
	out["ok"] = true
	out["event"] = e
	var seen := {n: true}
	var cur := e
	var parts: Array = []
	while out["causes"].size() < MAX_DEPTH:
		var pn := int(cur["parent"])
		if pn <= 0:
			break
		if seen.has(pn):
			break
		seen[pn] = true
		var p: Dictionary = ev.get_event(pn)
		if p.is_empty():
			out["truncated"] = true
			break
		(out["causes"] as Array).append(p)
		parts.append("%s (%s)" % [p["outcome"] if String(p["outcome"]) != "" else p["cause"], p["id"]])
		cur = p
	if int(cur["parent"]) > 0 and (out["causes"] as Array).size() >= MAX_DEPTH:
		out["truncated"] = true
	out["text"] = "%s was caused by %s." % [e["id"], " <- ".join(parts)] if not parts.is_empty() else "%s has no recorded cause." % e["id"]
	return out


## "What did event n lead to": breadth-first over the parent links, depth <= MAX_DEPTH, at most MAX_ROWS rows. Each row is an event row plus "depth".
static func effects_of(hub: Variant, n: int) -> Array:
	var ev: Variant = hub.mod("events") if hub != null else null
	var out: Array = []
	if ev == null:
		return out
	var level: Array = [n]
	var seen := {n: true}
	var depth := 1
	while not level.is_empty() and depth <= MAX_DEPTH and out.size() < MAX_ROWS:
		var next: Array = []
		for p: int in level:
			for c: Dictionary in ev.children_of(p, MAX_ROWS):
				if out.size() >= MAX_ROWS or seen.has(int(c["n"])):
					continue
				seen[int(c["n"])] = true
				c["depth"] = depth
				out.append(c)
				next.append(int(c["n"]))
		level = next
		depth += 1
	return out


## A chain's causes: {ok, kind, town, trigger (event row or {}), parent_chain, events: [rows it wrote], effects (psyche touches)}.
static func chain_of(hub: Variant, cid: int) -> Dictionary:
	var em: Variant = hub.mod("emergence") if hub != null else null
	var ev: Variant = hub.mod("events") if hub != null else null
	var c: Dictionary = em.chain(cid) if em != null else {}
	if c.is_empty():
		return {"ok": false}
	var d: Dictionary = c["data"]
	var trig: Dictionary = ev.get_event(int(d.get("ev", 0))) if ev != null and int(d.get("ev", 0)) > 0 else {}
	var wrote: Array = []
	if ev != null and int(d.get("le", 0)) > 0:
		var walk: Dictionary = caused_by(hub, int(d["le"]))
		wrote = (walk["causes"] as Array).duplicate()
		wrote.push_front(walk["event"])
	return {"ok": true, "kind": c["k"], "town": int(c["sid"]), "trigger": trig, "parent_chain": int(c["par"]), "events": wrote, "people": (d.get("hit", []) as Array).size()}
