extends RefCounted
## NPC spawn / LOD QA (--pop-log): PopulationLOD reports every resident's representation once per finished refresh
## (FULL body / VAT instance / SPRITE impostor / NONE). Every change is logged with whether the resident was inside the
## camera frustum (head-height point, slightly shrunk frustum) and its distance; an on-screen change is a visible pop
## unless it is a FULL<->VAT/SPRITE hand-over that the dither fade covers (`faded`). POPLOG_SUM every 10 s and at exit.

enum Rep { NONE, SPRITE, VAT, FULL }
const NAMES := ["none", "sprite", "vat", "full"]

static var enabled := OS.get_cmdline_user_args().has("--pop-log")
static var _state := {}          # id -> Rep
static var _t_sum := 0.0
static var counts := {"changes": 0, "on_screen": 0, "on_screen_faded": 0}
static var by_kind := {}         # "full>none@on" -> n


static func report(cam: Camera3D, focus: Vector3, now_state: Dictionary, pos_of: Callable, faded: Dictionary = {}) -> void:
	if not enabled or cam == null:
		return
	var ids := {}
	for id in now_state:
		ids[id] = true
	for id in _state:
		ids[id] = true
	for id in ids:
		var a: int = _state.get(id, Rep.NONE)
		var b: int = now_state.get(id, Rep.NONE)
		if a == b:
			continue
		var p: Vector3 = pos_of.call(id)
		var on := p != Vector3.INF and cam.is_position_in_frustum(p + Vector3(0, 1.0, 0)) \
			and cam.global_position.distance_to(p) < cam.far * 0.95
		var d := focus.distance_to(p) if p != Vector3.INF else -1.0
		counts["changes"] += 1
		var k := "%s>%s@%s" % [NAMES[a], NAMES[b], "on" if on else "off"]
		if on:
			if faded.has(id):
				counts["on_screen_faded"] += 1
				k += "(faded)"
			else:
				counts["on_screen"] += 1
				print("POPLOG on-screen %s id=%d dist=%.1f" % [k, int(id), d])
		by_kind[k] = int(by_kind.get(k, 0)) + 1
	_state = now_state.duplicate()


static func tick(delta: float) -> void:
	if not enabled:
		return
	_t_sum += delta
	if _t_sum >= 10.0:
		_t_sum = 0.0
		summary()


static func summary() -> void:
	print("POPLOG_SUM changes=%d on_screen=%d on_screen_faded=%d kinds=%s" % [counts["changes"], counts["on_screen"], counts["on_screen_faded"], by_kind])
