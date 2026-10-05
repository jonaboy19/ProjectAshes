extends RefCounted
## Generic typed node pool (F12). Preload, no class_name:
##   const NodePool := preload("res://scripts/core/node_pool.gd")
##   var pool := NodePool.new(func() -> Node: return Wolf.new(), 24)
##   var n := pool.acquire()         # a fresh or recycled node, NOT in the tree: the caller add_child()s it
##   pool.release(n)                 # hooks run, the node leaves the tree and waits for the next acquire
##
## - `cap`: most nodes (live + idle) the pool will ever create. At the cap an acquire steals the OLDEST live
##   node (release hooks run on it first) when `steal_oldest`, else returns null. So memory never grows past cap.
## - `prewarm(n)`: creates idle nodes up front (spread the cost over loading, never mid-fight).
## - Hooks, called with has_method on the pooled node:
##     on_acquire()  just before acquire() hands it out (fresh nodes too, before their first _ready)
##     on_release()  the node is still in the tree; stop timers, tweens, signals
##     reset()       back to the as-new state (health, state, AI, ragdoll...) so an idle node is always clean
##   A fresh node that never entered the tree may be asked to reset(): hooks must tolerate that.
## - Stats for tests and the QA harness: stats().
## - Idle nodes live outside the tree, so they cost nothing per frame; clear() frees them (also run at tree exit).
##
## Static helpers: shared(key, factory, cap) keeps one pool per key; recycle(node) hands a node back to the pool
## that made it (queue_free for anything else); clear_all() frees every shared pool.

const META := "_npool"

static var _shared := {}
static var _hooked := false
## Test / QA switch: false makes shared pools behave like plain new() / queue_free() (the "before" numbers).
static var enabled := true
## Bodies allocated the plain way while `enabled` is false (the "before" run counts these as its allocations).
static var plain_allocs := 0

var factory: Callable
var cap := 32
var steal_oldest := true
var label := ""

var _idle: Array[Node] = []
var _live: Array[Node] = []       # acquire order, oldest first
var _created := 0
var _acquires := 0
var _releases := 0
var _reuses := 0
var _steals := 0
var _peak_live := 0


func _init(make: Callable = Callable(), max_nodes := 32, steal := true, pool_label := "") -> void:
	factory = make
	cap = maxi(1, max_nodes)
	steal_oldest = steal
	label = pool_label


# --- shared registry -----------------------------------------------------------------------------

static func shared(key: String, make: Callable, max_nodes := 32, steal := true):
	if _shared.has(key):
		return _shared[key]
	var p = (load("res://scripts/core/node_pool.gd") as GDScript).new(make, max_nodes, steal, key)
	_shared[key] = p
	_hook_exit()
	return p


static func shared_pools() -> Dictionary:
	return _shared


## Every node ever allocated for pooled kinds: real creations of the shared pools plus the plain ones.
static func total_allocations() -> int:
	var n := plain_allocs
	for k: String in _shared:
		n += int(_shared[k].stats()["created"])
	return n


static func clear_all() -> void:
	for k: String in _shared.keys():
		_shared[k].clear()
	_shared.clear()


## Back to the pool that made `node`; anything else (or the pool switched off) is queue_free()d. True when pooled.
## Safe to call twice and on a node that is already idle.
static func recycle(node: Node) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	if not node.has_meta(META):
		node.queue_free()
		return false
	return node.get_meta(META).release(node)


## Frees the idle nodes of every shared pool beyond `keep` each (a teleport leaves a pool holding the bodies of the place
## it left, which nothing will ask for again). Live nodes are untouched. Returns how many nodes were freed.
static func trim_all(keep := 4) -> int:
	var freed := 0
	for k: String in _shared:
		freed += int(_shared[k].trim_idle(keep))
	return freed


static func _hook_exit() -> void:
	if _hooked:
		return
	var loop := Engine.get_main_loop()
	if loop is SceneTree and (loop as SceneTree).root != null:
		_hooked = true
		(loop as SceneTree).root.tree_exiting.connect(clear_all)


# --- pool ------------------------------------------------------------------------------------------

func prewarm(count: int) -> void:
	_purge()
	while _idle.size() < count and _idle.size() + _live.size() < cap:
		var n := _make()
		if n == null:
			return
		_idle.append(n)


func acquire() -> Node:
	_purge()
	var n: Node = null
	if not _idle.is_empty():
		n = _idle.pop_back()
		_reuses += 1
	elif _idle.size() + _live.size() < cap:
		n = _make()
	elif steal_oldest and not _live.is_empty():
		var oldest: Node = _live[0]
		_steals += 1
		release(oldest)
		n = _idle.pop_back()
		_reuses += 1
	if n == null:
		return null
	_acquires += 1
	_live.append(n)
	_peak_live = maxi(_peak_live, _live.size())
	if n.has_method("on_acquire"):
		n.call("on_acquire")
	return n


## False when `node` is not live in this pool (already idle, foreign or freed).
func release(node: Node) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	var i := _live.find(node)
	if i < 0:
		return false
	_live.remove_at(i)
	_releases += 1
	if node.has_method("on_release"):
		node.call("on_release")
	if node.has_method("reset"):
		node.call("reset")
	var parent := node.get_parent()
	if parent != null:
		parent.remove_child(node)
	_idle.append(node)
	return true


## Frees the oldest idle nodes down to `keep`. Returns how many were freed.
func trim_idle(keep := 0) -> int:
	_purge()
	var n := 0
	while _idle.size() > maxi(keep, 0):
		var node: Node = _idle.pop_front()
		if is_instance_valid(node):
			node.free()
			n += 1
	return n


func release_all() -> void:
	for n in _live.duplicate():
		release(n)


func is_live(node: Node) -> bool:
	return _live.has(node)


func live_count() -> int:
	_purge()
	return _live.size()


func idle_count() -> int:
	return _idle.size()


func total() -> int:
	_purge()
	return _live.size() + _idle.size()


func live_nodes() -> Array[Node]:
	_purge()
	return _live.duplicate()


## Everything tests and the QA harness read. `created` only ever counts real allocations.
func stats() -> Dictionary:
	_purge()
	return {"label": label, "cap": cap, "created": _created, "acquires": _acquires, "releases": _releases,
		"reuses": _reuses, "steals": _steals, "live": _live.size(), "idle": _idle.size(),
		"total": _live.size() + _idle.size(), "peak_live": _peak_live}


## Frees every idle node and forgets the live ones (they stay in the tree and are queue_free()d with their scene).
func clear() -> void:
	for n in _idle:
		if is_instance_valid(n):
			n.free()
	_idle.clear()
	for n in _live:
		if is_instance_valid(n):
			n.remove_meta(META)
	_live.clear()


func _make() -> Node:
	if not factory.is_valid():
		return null
	var n: Node = factory.call()
	if n == null:
		return null
	_created += 1
	n.set_meta(META, self)
	return n


## Forget nodes someone queue_free()d behind our back (a failed _ready, a scene change).
func _purge() -> void:
	for i in range(_live.size() - 1, -1, -1):
		if not is_instance_valid(_live[i]) or _live[i].is_queued_for_deletion():
			_live.remove_at(i)
	for i in range(_idle.size() - 1, -1, -1):
		if not is_instance_valid(_idle[i]):
			_idle.remove_at(i)
