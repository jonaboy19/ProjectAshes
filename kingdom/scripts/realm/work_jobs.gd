extends RefCounted
## Data for the job-work layer (scripts/realm/work.gd): what a shift IS for every job.
##
## job = {title, discipline, wage (day pay when freelancing), shift [from, to), edge (workplace
##        sits outside the walls), spots [{kind, label, r?}], seq (Array of task ids) or
##        by_season {season: [ids]}, tasks {id: task}, problems [problem], orders [text templates],
##        say {great|ok|poor: [lines with %s = employer]}}
## task = {id, label, spot (spot kind), widget "timing"|"hold"|"choice", hours (game hours the
##         task takes; routine work speeds time up), diff 0..1, text, options (choice only)}
## option = {text, q 0..1, tip (gold), regard (city reputation delta)}
## problem = {id, text, weight, options [{text, q, tip, regard, injure (days), callup (template id),
##            story (society log_failure kind)}], callup (default template if the fix fails), story}
## Problems are the non-routine beats: the game runs at normal speed while they are open.

static var _cache: Dictionary = {}


static func data() -> Dictionary:
	if _cache.is_empty():
		_cache = _build()
	return _cache


static func _t(id: String, label: String, spot: String, widget: String, hours: float, diff: float, text: String, options: Array = []) -> Dictionary:
	return {"id": id, "label": label, "spot": spot, "widget": widget, "hours": hours, "diff": diff, "text": text, "options": options}


static func _o(text: String, q: float, tip := 0, regard := 0.0) -> Dictionary:
	return {"text": text, "q": q, "tip": tip, "regard": regard}


static func _p(id: String, text: String, weight: float, options: Array, callup := "", story := "") -> Dictionary:
	return {"id": id, "text": text, "weight": weight, "options": options, "callup": callup, "story": story}


static func _po(text: String, q: float, extra: Dictionary = {}) -> Dictionary:
	var d := {"text": text, "q": q}
	d.merge(extra)
	return d


static func _job(title: String, disc: String, wage: int, shift: Array, edge: bool, spots: Array, tasks: Array,
		seq: Array, problems: Array, orders: Array, say: Dictionary, by_season: Dictionary = {}) -> Dictionary:
	var tm := {}
	for t: Dictionary in tasks:
		tm[t["id"]] = t
	return {"title": title, "discipline": disc, "wage": wage, "shift": shift, "edge": edge, "spots": spots, "tasks": tm,
		"seq": seq, "by_season": by_season, "problems": problems, "orders": orders, "say": say}


static func _s(kind: String, label: String, r := 6.0) -> Dictionary:
	return {"kind": kind, "label": label, "r": r}


static func _build() -> Dictionary:
	var d := {}

	# ---- farmer: the work follows the season (till > sow > water > harvest)
	d["farmer"] = _job("Farmer", "farming", 6, [6, 16], true,
		[_s("field", "Field"), _s("well", "Well"), _s("barn", "Barn")],
		[_t("till", "Till the soil", "field", "timing", 1.0, 0.35, "Drive the plough in a straight furrow."),
		_t("sow", "Sow the seed", "field", "hold", 1.0, 0.4, "Scatter evenly; hold while you walk the row, release at the end."),
		_t("water", "Water the rows", "well", "timing", 0.5, 0.3, "Draw the bucket when it swings level."),
		_t("weed", "Weed the rows", "field", "choice", 1.0, 0.3, "The weeds are thick.", [_o("Pull each by hand", 0.85), _o("Hoe quickly", 0.6), _o("Skip the back rows", 0.25)]),
		_t("harvest", "Reap the harvest", "field", "timing", 1.5, 0.5, "Swing the scythe on the beat."),
		_t("bundle", "Bind the sheaves", "barn", "hold", 0.75, 0.4, "Pull the cord tight, not too tight."),
		_t("store", "Store the crop", "barn", "choice", 0.5, 0.3, "Where does it go?", [_o("Dry loft, sealed", 0.9), _o("Cellar", 0.65), _o("Leave in the cart", 0.2)]),
		_t("mend", "Mend the fence", "barn", "timing", 1.0, 0.35, "Drive the stake home."),
		_t("thresh", "Thresh the grain", "barn", "timing", 1.0, 0.45, "Keep the flail rhythm."),
		_t("feed", "Feed the stock", "barn", "choice", 0.5, 0.2, "Winter feed is short.", [_o("Full ration", 0.9), _o("Half ration", 0.6), _o("Feed the strong only", 0.35)])],
		["water", "weed", "water"],
		[_p("sick_animal", "A ewe is listless and off her feed; two others are coughing.", 1.0,
			[_po("Isolate the flock and dose them", 0.85, {"tip": -3}), _po("Send for the herbwife", 0.65, {"tip": -6}), _po("Do nothing; it will pass", 0.15, {"callup": "sick_herd", "story": "farm_blight"})], "sick_herd", "farm_blight"),
		_p("crows", "Crows are stripping the sown rows.", 0.9,
			[_po("Rig a scarecrow line", 0.8), _po("Chase them off yourself", 0.55), _po("Ignore them", 0.2)]),
		_p("wolf_sign", "Fresh wolf tracks circle the fold.", 0.5,
			[_po("Stand watch tonight", 0.8, {"callup": "wolves_at_farm"}), _po("Pen the flock and hope", 0.4), _po("Tell the reeve", 0.6, {"regard": 0.5})])],
		["Sow %d rows of barley for the reeve (pays %dg)", "Bring %d sheaves to the mill (pays %dg)", "Mend %d rods of fence (pays %dg)"],
		{"great": ["%s: \"Straight furrows. The land likes you.\"", "%s: \"That is how it's done.\""], "ok": ["%s: \"It will do.\"", "%s: \"Fair work.\""],
		"poor": ["%s: \"Half the seed is in the path. Do it again tomorrow.\"", "%s: \"The crows did better work.\""]},
		{"spring": ["till", "sow", "water"], "summer": ["water", "weed", "water"], "autumn": ["harvest", "bundle", "store"], "winter": ["mend", "thresh", "feed"]})

	# ---- blacksmith: forge > quench > grind
	d["blacksmith"] = _job("Blacksmith", "smithing", 10, [7, 15], false,
		[_s("forge", "Forge"), _s("quench", "Quench barrel"), _s("grinder", "Grindstone"), _s("ore_pile", "Ore pile")],
		[_t("sort_ore", "Sort the ore", "ore_pile", "choice", 0.5, 0.3, "A shipment came in. Some of it looks poor.", [_o("Keep only the good lumps", 0.9), _o("Use it all", 0.5), _o("Grab the first ones", 0.3)]),
		_t("forge", "Work the forge", "forge", "timing", 1.0, 0.5, "Strike while the iron glows cherry red."),
		_t("quench", "Quench the blade", "quench", "hold", 0.5, 0.55, "Hold it in the water; release at the hiss."),
		_t("grind", "Grind the edge", "grinder", "timing", 1.0, 0.45, "Steady pressure. Do not burn the temper.")],
		["forge", "quench", "grind"],
		[_p("bad_ore", "Half the ore is brittle, full of slag. The blade will not hold an edge.", 1.0,
			[_po("Smelt it out slowly", 0.8, {"tip": -2}), _po("Use it and hide the flaw", 0.3, {"story": "shoddy_work", "regard": -1.0}), _po("Report it to the merchant", 0.7, {"callup": "stolen_ore"})], "stolen_ore"),
		_p("broken_tool", "Your hammer head flies off the haft mid-swing.", 0.9,
			[_po("Rehaft it now", 0.75), _po("Borrow the master's hammer", 0.5, {"regard": -0.5}), _po("Work with the pliers", 0.3)]),
		_p("rush_order", "The garrison sent a rush order: twelve arrowheads by dusk.", 0.8,
			[_po("Stay late and do it", 0.9, {"tip": 8, "callup": "forge_rush"}), _po("Split it with the apprentice", 0.65), _po("Say it cannot be done", 0.2, {"regard": -1.0})], "forge_rush")],
		["Forge %d horseshoes for the stables (pays %dg)", "Grind %d scythe blades (pays %dg)", "Draw %d nails for the carpenter (pays %dg)"],
		{"great": ["%s: \"You have a smith's hands.\"", "%s: \"That edge could shave a wolf.\""], "ok": ["%s: \"Passable. Keep at it.\"", "%s: \"Acceptable.\""],
		"poor": ["%s: \"You wasted good iron. Watch me and learn.\"", "%s: \"That is scrap. Into the pile.\""]})

	# ---- merchant / stall keeper: open stall > haggle > restock
	d["merchant"] = _job("Stall Keeper", "trading", 5, [8, 16], false,
		[_s("stall", "Stall"), _s("crate", "Crates"), _s("counter", "Counter")],
		[_t("open_stall", "Open the stall", "stall", "timing", 0.5, 0.25, "Raise the awning and lay out the goods before the crowd."),
		_t("haggle_a", "Haggle with a customer", "counter", "choice", 0.5, 0.4, "A weaver eyes your cloth. \"Two silver for that? Robbery.\"",
			[_o("Hold firm on the price", 0.85, 4, -0.8), _o("Split the difference", 0.65, 2, 0.3), _o("Give her a friend's price", 0.4, -1, 1.2)]),
		_t("haggle_b", "Haggle with a customer", "counter", "choice", 0.5, 0.5, "A soldier wants three loaves for the price of two.",
			[_o("Hold firm on the price", 0.85, 3, -0.8), _o("Toss in a loaf for a friend's smile", 0.6, 0, 1.0), _o("Sell it cheap to be rid of him", 0.3, -2, 0.2)]),
		_t("restock", "Restock from the crates", "crate", "timing", 0.75, 0.35, "Fill the gaps before the noon rush.")],
		["open_stall", "haggle_a", "haggle_b", "restock"],
		[_p("thief_at_stall", "A ragged boy grabs an apple and bolts through the crowd.", 1.0,
			[_po("Give chase", 0.7, {"callup": "stall_thief"}), _po("Shout for the guard", 0.6, {"regard": 0.5}), _po("Let him go; hunger is hunger", 0.35, {"regard": 0.8, "tip": -1})], "stall_thief", "stall_theft"),
		_p("bad_scale", "A customer swears your scale is crooked.", 0.8,
			[_po("Weigh it again in front of him", 0.85, {"regard": 0.5}), _po("Bluster and refuse", 0.3, {"regard": -1.5}), _po("Give him the difference", 0.6, {"tip": -3})]),
		_p("spoilage", "The fish is turning. The crowd is sniffing.", 0.7,
			[_po("Mark it down fast", 0.7, {"tip": -2}), _po("Bury it under fresh ice", 0.5), _po("Sell it as fresh", 0.25, {"regard": -2.0, "story": "bad_goods"})])],
		["Move %d loaves before the bell (pays %dg)", "Sell out %d crates of apples (pays %dg)", "Take an order of %d bolts of cloth (pays %dg)"],
		{"great": ["%s: \"The crowd came to you. Good business.\"", "%s: \"You could sell sand to a camel.\""], "ok": ["%s: \"A fair day at the till.\"", "%s: \"The coin box is not empty.\""],
		"poor": ["%s: \"You gave the goods away. The till is light.\"", "%s: \"Customers left with their coin. That is not selling.\""]})

	# ---- guard: patrol checkpoints > incidents
	d["guard"] = _job("Guard", "soldiering", 9, [7, 19], false,
		[_s("gate", "Gate post", 8), _s("market_watch", "Market watch", 12), _s("wall", "Wall walk", 12), _s("barracks", "Barracks", 6)],
		[_t("check_gate", "Check the gate", "gate", "choice", 0.5, 0.3, "A cart with sealed barrels rolls in.", [_o("Inspect it properly", 0.9), _o("Wave it through", 0.35), _o("Demand a toll", 0.4, 3, -1.5)]),
		_t("walk_market", "Patrol the market", "market_watch", "timing", 1.0, 0.3, "Keep step; be seen; look for pickpockets."),
		_t("walk_wall", "Walk the wall", "wall", "timing", 1.0, 0.25, "Scan the fields; stay awake."),
		_t("report", "Report to the sergeant", "barracks", "choice", 0.25, 0.2, "What did you see?", [_o("Full, honest report", 0.9), _o("Only the important parts", 0.65), _o("Nothing to report", 0.3)])],
		["check_gate", "walk_market", "walk_wall", "report"],
		[_p("theft", "A woman screams: someone slit her purse and is running for the alley.", 1.0,
			[_po("Give chase", 0.8, {"regard": 1.0}), _po("Cut them off with a whistle for the wall", 0.65), _po("Stay at your post", 0.3, {"regard": -1.0, "story": "guard_lapse"})], "stall_thief"),
		_p("brawl", "Two drunks are fighting outside the tavern; a crowd is forming.", 1.0,
			[_po("Wade in and separate them", 0.8, {"regard": 0.5}), _po("Talk them down", 0.7, {"regard": 1.0}), _po("Let them tire out", 0.3, {"regard": -0.8})], "tavern_brawl"),
		_p("smuggler", "A merchant's wagon rides low: too low for its cargo.", 0.6,
			[_po("Search the wagon", 0.85, {"callup": "smugglers"}), _po("Take a coin and look away", 0.2, {"tip": 6, "story": "guard_bribed", "regard": -2.0}), _po("Report it up the chain", 0.7)], "smugglers")],
		["Walk %d night rounds (pays %dg)", "Escort %d tax carts to the keep (pays %dg)", "Man the gate for %d bells (pays %dg)"],
		{"great": ["%s: \"Eyes sharp. The town sleeps easier.\"", "%s: \"That is a guard I trust.\""], "ok": ["%s: \"Adequate. Stay alert.\"", "%s: \"Nothing burned. Good.\""],
		"poor": ["%s: \"You slept on the wall. Do it again and you walk home.\"", "%s: \"The thieves thank you for your patience.\""]})

	# ---- laborer: haul > dig > stack
	d["laborer"] = _job("Day Labourer", "mining", 3, [7, 15], false,
		[_s("cart", "Cart"), _s("ditch", "Ditch"), _s("stack", "Stack yard")],
		[_t("haul", "Haul the load", "cart", "hold", 1.0, 0.4, "Pull hard; ease off before the slope."),
		_t("dig", "Dig the trench", "ditch", "timing", 1.5, 0.35, "Sink the spade with the rhythm."),
		_t("stack", "Stack the stones", "stack", "choice", 0.75, 0.3, "How do you build the pile?", [_o("Carefully, big ones at the bottom", 0.9), _o("Quickly", 0.55), _o("Toss them up", 0.25)])],
		["haul", "dig", "stack"],
		[_p("overweight", "The foreman piles on a load twice what was agreed.", 1.0,
			[_po("Refuse politely", 0.55, {"regard": 0.3}), _po("Take it and strain", 0.75, {"injure": 1}), _po("Get a partner to share it", 0.85, {"regard": 0.3})]),
		_p("wage_skim", "The gang boss is docking pay for a day you worked.", 0.7,
			[_po("Demand it back", 0.5, {"regard": 0.2, "tip": 2}), _po("Say nothing", 0.6), _po("Quietly note it for the reeve", 0.7, {"regard": 0.6})]),
		_p("collapse", "The trench wall groans and slumps.", 0.5,
			[_po("Drag a mate out", 0.85, {"regard": 1.5}), _po("Shout a warning", 0.6), _po("Run", 0.15, {"story": "coward_labour"})], "cave_in")],
		["Dig %d cubits of drain (pays %dg)", "Stack %d loads of quarry stone (pays %dg)", "Haul %d barrels to the docks (pays %dg)"],
		{"great": ["%s: \"Strong back and a good head.\"", "%s: \"I'd hire you tomorrow.\""], "ok": ["%s: \"Pay is pay. Come back.\"", "%s: \"You'll do.\""],
		"poor": ["%s: \"You dropped more than you carried.\"", "%s: \"I've seen ponies do more.\""]})

	# ---- woodcutter: chop > haul
	d["woodcutter"] = _job("Woodcutter", "carpentry", 7, [6, 16], true,
		[_s("tree", "Felling site"), _s("log_pile", "Log pile"), _s("sled", "Haul sled")],
		[_t("fell", "Fell the tree", "tree", "timing", 1.0, 0.45, "Bite the axe into the notch; three clean blows."),
		_t("limb", "Limb the trunk", "tree", "timing", 0.75, 0.3, "Chop the branches flush."),
		_t("haul_logs", "Haul the logs", "sled", "hold", 1.0, 0.4, "Drag steady; slow down at the ford."),
		_t("stack_logs", "Stack the pile", "log_pile", "choice", 0.5, 0.25, "Sorting the cut.", [_o("By length, squared", 0.9), _o("Just stack", 0.55), _o("Pile for later", 0.3)])],
		["fell", "limb", "haul_logs", "stack_logs"],
		[_p("widowmaker", "A dead branch cracks loose overhead as you swing.", 1.0,
			[_po("Dive clear", 0.75), _po("Shout and hold your ground", 0.5), _po("Ignore it", 0.15, {"injure": 2})]),
		_p("dull_axe", "Your axe is chipped; every blow skips.", 0.9,
			[_po("Stop and sharpen", 0.8), _po("Push on", 0.4), _po("Borrow the foreman's", 0.55, {"regard": -0.3})]),
		_p("poachers", "Strangers are hauling away cut timber from the pile.", 0.6,
			[_po("Confront them", 0.65, {"callup": "timber_theft"}), _po("Fetch the foreman", 0.7), _po("Look away", 0.2, {"story": "timber_theft"})], "timber_theft")],
		["Fell %d oaks for the shipwright (pays %dg)", "Cut %d cords of firewood (pays %dg)", "Deliver %d beams to the sawpit (pays %dg)"],
		{"great": ["%s: \"Clean cuts. Not a splinter wasted.\"", "%s: \"The forest keeps its best for you.\""], "ok": ["%s: \"Steady work.\"", "%s: \"The pile is straight.\""],
		"poor": ["%s: \"You felled it onto the road.\"", "%s: \"Ruined timber. Mind the grain.\""]})

	# ---- miner
	d["miner"] = _job("Miner", "mining", 8, [6, 15], true,
		[_s("vein", "Ore vein"), _s("prop", "Shaft prop"), _s("ore_cart", "Ore cart")],
		[_t("chip", "Chip the vein", "vein", "timing", 1.0, 0.5, "Ring the pick on the seam."),
		_t("prop", "Set a prop", "prop", "choice", 0.5, 0.35, "The ceiling weeps dust.", [_o("Set two props, wedge tight", 0.9), _o("One prop", 0.55), _o("Skip it; you are nearly done", 0.15)]),
		_t("load_cart", "Load the cart", "ore_cart", "hold", 0.75, 0.35, "Shovel steady; do not overfill."),
		_t("sort", "Sort the ore", "ore_cart", "choice", 0.5, 0.3, "Which lumps are ore?", [_o("Only the bright seams", 0.9), _o("Everything heavy", 0.55), _o("All of it", 0.3)])],
		["chip", "prop", "load_cart", "sort"],
		[_p("bad_seam", "The seam thins to grey rock; foul air pools at the face.", 1.0,
			[_po("Withdraw and report", 0.75, {"regard": 0.5}), _po("Push on", 0.35, {"injure": 2}), _po("Test the air with a candle", 0.6)], "cave_in"),
		_p("cave_in_sign", "Pebbles patter from the roof; the props creak.", 0.7,
			[_po("Call everyone out", 0.85, {"regard": 1.0}), _po("Set a prop fast", 0.6), _po("Keep digging", 0.2, {"callup": "cave_in", "story": "mine_collapse"})], "cave_in", "mine_collapse"),
		_p("broken_pick", "Your pick snaps at the head.", 0.9,
			[_po("Swap for the spare", 0.75), _po("Wedge it and go on", 0.4), _po("Take a break while you fix it", 0.6)])],
		["Bring up %d carts of ore (pays %dg)", "Set %d new props (pays %dg)", "Open a new drift of %d paces (pays %dg)"],
		{"great": ["%s: \"You have a nose for good stone.\"", "%s: \"The mine is safer for you being in it.\""], "ok": ["%s: \"A cart is a cart.\"", "%s: \"Keep your lamp lit.\""],
		"poor": ["%s: \"You mixed the slag in with the ore.\"", "%s: \"Careless. Careless kills.\""]})

	# ---- hunter
	d["hunter"] = _job("Hunter", "hunting", 7, [5, 15], true,
		[_s("trail", "Game trail"), _s("blind", "Hunting blind"), _s("rack", "Drying rack")],
		[_t("track", "Read the tracks", "trail", "choice", 0.75, 0.4, "Fresh prints in the mud.", [_o("Follow the deep prints (heavy, slow)", 0.85), _o("Follow the fast ones", 0.55), _o("Guess", 0.3)]),
		_t("aim", "Loose the arrow", "blind", "hold", 0.5, 0.6, "Draw and hold; release when the breath settles."),
		_t("skin", "Skin the kill", "rack", "timing", 1.0, 0.4, "Run the knife clean, keep the pelt whole."),
		_t("dry", "Salt and rack the meat", "rack", "choice", 0.5, 0.25, "Handling the haul.", [_o("Salt thoroughly", 0.9), _o("Hang it as is", 0.5), _o("Leave in the sun", 0.2)])],
		["track", "aim", "skin", "dry"],
		[_p("wounded_beast", "Your shot only wounds the boar; it crashes into the brush.", 1.0,
			[_po("Track it and finish it", 0.75, {"callup": "wolves_near_village"}), _po("Leave it to die", 0.3), _po("Fetch the pack dogs", 0.6)], "wolves_near_village"),
		_p("poacher", "You find a snare line on the lord's land.", 0.6,
			[_po("Cut the snares and report", 0.7, {"regard": 0.8}), _po("Take the catch", 0.4, {"tip": 4, "regard": -1.0}), _po("Leave it", 0.3)]),
		_p("spoiled_pelt", "A pelt you skinned late is already rotting.", 0.7,
			[_po("Scrape and re-salt it", 0.65), _po("Sell it anyway", 0.3, {"regard": -0.8}), _po("Bury it", 0.45)])],
		["Bring %d pelts to the tanner (pays %dg)", "Deliver %d haunches to the inn (pays %dg)", "Thin the wolves near %d farms (pays %dg)"],
		{"great": ["%s: \"Clean kills. Nothing wasted.\"", "%s: \"The forest fears you a little. Good.\""], "ok": ["%s: \"Enough to eat.\"", "%s: \"Middling pelts.\""],
		"poor": ["%s: \"You spooked everything within a league.\"", "%s: \"That hide is all holes.\""]})

	# ---- fisher
	d["fisher"] = _job("Fisher", "fishing", 5, [5, 14], true,
		[_s("shore", "Shoreline"), _s("net_rack", "Net rack"), _s("gut_table", "Gutting table")],
		[_t("cast", "Cast the net", "shore", "hold", 0.75, 0.4, "Swing and hold; let it fly at the top of the arc."),
		_t("reel", "Haul in the catch", "shore", "timing", 1.0, 0.45, "Pull with the swell, not against it."),
		_t("gut", "Gut and scale", "gut_table", "timing", 0.75, 0.3, "Quick and clean cuts."),
		_t("mend_net", "Mend the net", "net_rack", "choice", 0.5, 0.25, "Holes in the mesh.", [_o("Stitch every tear", 0.9), _o("Patch the big ones", 0.55), _o("Tie it and hope", 0.25)])],
		["cast", "reel", "gut", "mend_net"],
		[_p("net_tangle", "A snag: the net is wound round a sunk log.", 1.0,
			[_po("Wade in and cut it free", 0.7), _po("Pull hard", 0.3, {"tip": -3}), _po("Wait for the tide", 0.55)]),
		_p("squall", "Dark cloud on the water. The boats are bobbing.", 0.8,
			[_po("Head in now", 0.8), _po("Fish one more cast", 0.45, {"tip": 3}), _po("Help the boy get his skiff in", 0.75, {"regard": 1.2})]),
		_p("bad_catch", "The catch smells wrong; the water is foul upstream.", 0.6,
			[_po("Throw it back and tell the reeve", 0.7, {"regard": 0.8}), _po("Sell it far away", 0.2, {"story": "bad_goods", "regard": -2.0}), _po("Salt it heavily", 0.5)])],
		["Bring %d baskets of perch (pays %dg)", "Land %d eels for the inn (pays %dg)", "Mend %d nets for the fleet (pays %dg)"],
		{"great": ["%s: \"A full net! The gulls hate you.\"", "%s: \"Silver in your hands.\""], "ok": ["%s: \"We eat tonight.\"", "%s: \"Good enough.\""],
		"poor": ["%s: \"You fed the fish, not us.\"", "%s: \"Half the mesh is missing.\""]})

	# ---- baker / cook
	d["baker"] = _job("Baker", "cooking", 6, [4, 12], false,
		[_s("trough", "Dough trough"), _s("oven", "Oven"), _s("counter", "Shop counter")],
		[_t("knead", "Knead the dough", "trough", "timing", 0.75, 0.3, "Fold with the rhythm; not too long."),
		_t("bake", "Mind the oven", "oven", "hold", 1.0, 0.5, "Hold the door open; pull the loaves at the golden crust."),
		_t("sell_bread", "Serve the morning queue", "counter", "choice", 0.75, 0.3, "A crowd wants bread.", [_o("Serve each with a word", 0.85, 2, 0.8), _o("Serve fast", 0.6, 3), _o("Keep the best for regulars", 0.5, 2, -0.5)])],
		["knead", "bake", "sell_bread"],
		[_p("spoiled_flour", "The flour sack has weevils. Half a day's dough is at stake.", 1.0,
			[_po("Sift and use the clean half", 0.65), _po("Throw it all out", 0.7, {"tip": -4}), _po("Use it anyway", 0.15, {"story": "bad_goods", "regard": -1.5})]),
		_p("oven_fire", "The chimney flue catches; sparks are landing on the thatch.", 0.5,
			[_po("Smother it with wet sacks", 0.8), _po("Raise the alarm", 0.7, {"callup": "fire_alarm"}), _po("Panic", 0.1, {"callup": "fire_alarm", "story": "bakery_fire"})], "fire_alarm", "bakery_fire"),
		_p("burnt_batch", "You look up: the loaves are black.", 0.9,
			[_po("Scrape and sell as toast", 0.5), _po("Start again", 0.7, {"tip": -2}), _po("Blame the apprentice", 0.2, {"regard": -1.0})])],
		["Bake %d loaves for the garrison (pays %dg)", "Fill %d pie orders for the feast (pays %dg)", "Bake %d loaves for the poor (pays %dg)"],
		{"great": ["%s: \"Golden crusts. The queue was out the door.\"", "%s: \"The smell alone sells them.\""], "ok": ["%s: \"Fine loaves.\"", "%s: \"Not bad.\""],
		"poor": ["%s: \"Bricks. The dogs won't eat them.\"", "%s: \"Half burned, half raw.\""]})

	# ---- healer
	d["healer"] = _job("Healer", "healing", 9, [8, 17], false,
		[_s("ward", "Sick beds"), _s("herb_table", "Herb table"), _s("dispensary", "Dispensary")],
		[_t("examine", "Examine a patient", "ward", "choice", 0.75, 0.5, "A farmhand with fever and a swollen leg.", [_o("Lance and clean the wound, fever tea", 0.9), _o("Bind it and wait", 0.55), _o("Prescribe rest only", 0.3)]),
		_t("brew", "Brew the remedy", "herb_table", "timing", 1.0, 0.5, "Stir when the steam turns green."),
		_t("bandage", "Dress the wound", "ward", "hold", 0.5, 0.4, "Wrap firm; hold until it sets."),
		_t("log_cases", "Note the cases", "dispensary", "choice", 0.25, 0.2, "For the ledger.", [_o("Full notes with symptoms", 0.9), _o("Names only", 0.55), _o("Skip", 0.2)])],
		["examine", "brew", "bandage", "log_cases"],
		[_p("plague_suspect", "A child with a rash spreading over the neck; two others in the row have it too.", 0.8,
			[_po("Quarantine the row and alert the reeve", 0.85, {"callup": "plague_ward", "regard": 1.0}), _po("Treat quietly", 0.5), _po("Say it's just heat", 0.15, {"story": "plague_unchecked"})], "plague_ward", "plague_unchecked"),
		_p("haemorrhage", "A woodcutter is carried in, gushing from a cut thigh.", 1.0,
			[_po("Tourniquet and press", 0.9), _po("Send for the master healer", 0.55), _po("Wash the wound first", 0.3)]),
		_p("herb_shortage", "The willow-bark jar is empty; the fever cases keep coming.", 0.9,
			[_po("Substitute meadowsweet", 0.65), _po("Fetch fresh bark from the grove", 0.8, {"tip": -2}), _po("Turn patients away", 0.2, {"regard": -1.0})])],
		["Treat %d fever cases (pays %dg)", "Brew %d doses of salve (pays %dg)", "Set %d broken bones (pays %dg)"],
		{"great": ["%s: \"You saved him. I could not have.\"", "%s: \"A healer's gift.\""], "ok": ["%s: \"Competent.\"", "%s: \"He will live.\""],
		"poor": ["%s: \"You missed the infection. We lost him.\"", "%s: \"Do not guess. Ask.\""]})

	# ---- carpenter
	d["carpenter"] = _job("Carpenter", "carpentry", 8, [7, 16], false,
		[_s("bench", "Workbench"), _s("saw_pit", "Saw pit"), _s("frame", "Frame")],
		[_t("measure", "Measure twice", "bench", "choice", 0.5, 0.3, "The order calls for a door of exact width.", [_o("Measure twice, mark once", 0.9), _o("Measure once", 0.6), _o("Eyeball it", 0.25)]),
		_t("saw", "Saw the plank", "saw_pit", "timing", 1.0, 0.45, "Long steady strokes."),
		_t("join", "Join the frame", "frame", "hold", 0.75, 0.5, "Press the joint home; hold until the peg seats.")],
		["measure", "saw", "join"],
		[_p("rotten_beam", "The beam you were given has a soft heart of rot.", 1.0,
			[_po("Refuse it and fetch another", 0.8, {"tip": -2}), _po("Cut around it", 0.5), _po("Fit it anyway", 0.15, {"story": "shoddy_work", "regard": -1.5})]),
		_p("rush_carpentry", "The captain wants a gate bar by dusk.", 0.8,
			[_po("Work through lunch", 0.85, {"tip": 5}), _po("Ask for help", 0.65), _po("Say it will be tomorrow", 0.4, {"regard": -0.6})]),
		_p("split_plank", "The plank splits along the grain right at the cut.", 0.9,
			[_po("Salvage it for a shorter piece", 0.7), _po("Glue and clamp", 0.55), _po("Start over", 0.75, {"tip": -3})])],
		["Build %d stools for the tavern (pays %dg)", "Frame %d doors for the new houses (pays %dg)", "Repair %d cart wheels (pays %dg)"],
		{"great": ["%s: \"Tight joints. No nails, no gaps.\"", "%s: \"That door will outlive us.\""], "ok": ["%s: \"Sturdy enough.\"", "%s: \"Square, near enough.\""],
		"poor": ["%s: \"This will not hold a hinge.\"", "%s: \"You cut it short. Again.\""]})

	# ---- scribe / clerk
	d["scribe"] = _job("Scribe", "scholarship", 12, [9, 17], false,
		[_s("desk", "Writing desk"), _s("seal_table", "Seal table"), _s("archive", "Archive shelves")],
		[_t("copy", "Copy the page", "desk", "timing", 1.0, 0.5, "Keep the pen level; no blots."),
		_t("seal", "Seal the letter", "seal_table", "hold", 0.5, 0.4, "Press the wax; lift when it sets."),
		_t("file", "File the record", "archive", "choice", 0.5, 0.25, "Where does the deed go?", [_o("By date and sender in the index", 0.9), _o("On the top shelf", 0.5), _o("In the pile", 0.2)]),
		_t("tally", "Tally the ledger", "desk", "choice", 0.5, 0.4, "The columns will not agree.", [_o("Recount every line", 0.9), _o("Trust the total", 0.5), _o("Adjust one number", 0.15, 0, -1.0)])],
		["copy", "seal", "file", "tally"],
		[_p("forged_letter", "A letter in the pile carries a seal you know is wrong.", 0.9,
			[_po("Report it to the steward", 0.85, {"regard": 1.0, "callup": "escort_message"}), _po("Quietly set it aside", 0.55), _po("Copy it and say nothing", 0.15, {"story": "forged_deed"})], "escort_message", "forged_deed"),
		_p("ink_spill", "Your elbow knocks the inkpot across a finished page.", 1.0,
			[_po("Blot and start the page again", 0.7), _po("Cover it with sand", 0.45), _po("Hide it in the pile", 0.2, {"regard": -0.8})]),
		_p("gossip", "A steward asks you what the lord's letters said.", 0.6,
			[_po("Refuse politely", 0.85, {"regard": 0.4}), _po("Give a hint for a coin", 0.35, {"tip": 5, "regard": -1.5, "story": "leaked_letter"}), _po("Pretend not to hear", 0.6)])],
		["Copy %d contracts for the guild (pays %dg)", "Draft %d letters for the steward (pays %dg)", "Audit %d ledgers (pays %dg)"],
		{"great": ["%s: \"Not a blot. A hand worth hiring.\"", "%s: \"Your letters are art.\""], "ok": ["%s: \"Legible.\"", "%s: \"It will pass inspection.\""],
		"poor": ["%s: \"This deed is smeared beyond use.\"", "%s: \"Do you call that writing?\""]})

	# ---- innkeeper / tavern worker
	d["innkeeper"] = _job("Tavern Hand", "cooking", 5, [11, 23], false,
		[_s("tables", "Tables"), _s("bar", "Bar"), _s("kitchen", "Kitchen door")],
		[_t("pour", "Pour the ale", "bar", "hold", 0.5, 0.4, "Hold the tap; release at the foam line."),
		_t("serve", "Serve the tables", "tables", "timing", 1.0, 0.4, "Weave through with full trays."),
		_t("bill", "Settle a bill", "bar", "choice", 0.5, 0.3, "A traveller counts coins slowly.", [_o("Round it down for a smile", 0.7, 0, 0.8), _o("Charge it exactly", 0.8, 2), _o("Add a service fee", 0.5, 4, -1.0)]),
		_t("clear", "Clear the tables", "tables", "timing", 0.75, 0.25, "Stack the mugs; do not break them.")],
		["pour", "serve", "bill", "clear"],
		[_p("brawl", "Two men are shouting over a dice game; a stool is lifted.", 1.0,
			[_po("Step between them", 0.7, {"callup": "tavern_brawl", "injure": 1}), _po("Call the guard", 0.75, {"regard": 0.3}), _po("Duck behind the bar", 0.25, {"callup": "tavern_brawl", "story": "tavern_wreck"})], "tavern_brawl", "tavern_wreck"),
		_p("drunk_guest", "A guest is loud, rude and refuses to leave.", 0.9,
			[_po("Steer him kindly to the door", 0.85), _po("Water down his ale", 0.55), _po("Insult him back", 0.2, {"regard": -1.0})]),
		_p("dropped_tray", "You trip; a tray of mugs shatters at a noble's feet.", 0.8,
			[_po("Apologise and clean up", 0.75), _po("Blame the floor", 0.4), _po("Pay for it yourself", 0.6, {"tip": -4, "regard": 0.6})])],
		["Serve %d tables at the feast (pays %dg)", "Keg up %d barrels (pays %dg)", "Turn %d rooms for the caravan (pays %dg)"],
		{"great": ["%s: \"The regulars ask for you now.\"", "%s: \"The tap never ran dry.\""], "ok": ["%s: \"Everyone is fed.\"", "%s: \"Fine, fine.\""],
		"poor": ["%s: \"You served the wrong table twice.\"", "%s: \"Foam everywhere. Clean it up.\""]})

	# ---- stable hand
	d["stable_hand"] = _job("Stable Hand", "beast_lore", 5, [6, 15], false,
		[_s("stalls", "Stalls"), _s("hay_loft", "Hay loft"), _s("paddock", "Paddock")],
		[_t("muck", "Muck out the stalls", "stalls", "timing", 1.0, 0.25, "Fork and toss with the beat."),
		_t("feed_horses", "Feed the horses", "hay_loft", "choice", 0.5, 0.3, "The bay is thin; the grey is greedy.", [_o("Measure by need", 0.9), _o("Same for all", 0.55), _o("Scoop and go", 0.3)]),
		_t("groom", "Groom a horse", "paddock", "hold", 0.75, 0.4, "Brush in long strokes; hold the halter still."),
		_t("check_hooves", "Check the hooves", "stalls", "timing", 0.5, 0.45, "Lift, pick, look; a stone bruise is a lame horse.")],
		["muck", "feed_horses", "groom", "check_hooves"],
		[_p("sick_horse", "The chestnut mare stands with her head low and will not eat.", 1.0,
			[_po("Walk her and call the farrier", 0.8, {"tip": -2}), _po("Give her a warm mash", 0.6), _po("Leave her to rest", 0.25, {"callup": "sick_herd", "story": "sick_animal"})], "sick_herd", "sick_animal"),
		_p("spooked_horse", "A stallion rears at a thrown bucket and bolts for the gate.", 0.8,
			[_po("Step in front and calm him", 0.8, {"injure": 1}), _po("Shut the gate", 0.7), _po("Run", 0.2)]),
		_p("hay_fire", "Someone left a pipe in the hay loft; smoke curls from the bales.", 0.4,
			[_po("Beat it out with a blanket", 0.8), _po("Raise the alarm", 0.7, {"callup": "fire_alarm"}), _po("Lead the horses out first", 0.9, {"regard": 1.0})], "fire_alarm")],
		["Shoe %d horses for the courier (pays %dg)", "Break in %d colts (pays %dg)", "Clean %d stalls before the fair (pays %dg)"],
		{"great": ["%s: \"The horses like you. That says more than I can.\"", "%s: \"Not a sore hoof in the row.\""], "ok": ["%s: \"Clean enough.\"", "%s: \"They are fed.\""],
		"poor": ["%s: \"The mare is lame. Because of you.\"", "%s: \"Mind what you feed.\""]})

	return d
