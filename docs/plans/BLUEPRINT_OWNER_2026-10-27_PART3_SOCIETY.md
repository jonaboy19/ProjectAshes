# Rising Ashes — Blueprint Part 3: Meetings, Professions, Leadership & Unscripted Society (owner input, 2026-10-27)

Continuation of Part 2 (sections 17–40). Owner-supplied via ChatGPT (which did not know our code). **Status: recorded only — do not start until current tasks are finished.** Reconcile against existing systems (people sim, careers/ranks, nobility/lordship/council/laws, realm modules, economy/markets, news-by-courier, event log, story, petitions) before building. No magic in this scope. Performance: regular-PC/iGPU min-spec.

## 17. Free participation in meetings
Not 3-option dialogue: interrupt, ask, object, propose alternatives, stay silent, leave, act. Example royal council on a food shortage (treasurer: cut spending/raise revenue; commander: protect garrisons; agriculture minister: secure grain first) — player can back a side, propose releasing reserves, negotiate imports, help farmers, investigate missing supplies, oppose taxes, or bring a new idea; NPCs can change their minds on evidence, attach conditions, or the king may hand the player the task.
Meeting AI: speaking turns (pause/interrupt), topic tracking, private intentions, argument evaluation (evidence, credibility, consequences), authority (who can approve what), etiquette by rank, persuasion without guarantees, disagreement, decision recording in world state, execution as real NPC tasks.
Meetings live in the world: a messenger with an attack report → the general leaves to organise defence, the king postpones, a minister keeps going, an official uses the break to approach the player privately.

## 18. Audiences at every level (player and NPCs)
Access routes: ordinary approach, appointment (servant/secretary/message), professional introduction, formal petition, summons, private invitation, chance encounter. Access depends on availability, health, travel, willingness, rank, relationships, urgency (a farmer with disaster news gets heard), reputation, institutions, trust.

## 19. Rulers receive petitions
When the player leads (king, guild master, governor, village head, crime boss) NPCs bring real issues. Example: farmer asks tax relief after a poor harvest → approve, investigate, negotiate conditions, delegate, deny, ask questions — or anything else (summon the governor, check other villages, visit, reform, appoint the farmer as adviser). Needs an **intent interpreter** mapping free-form orders onto valid world actions ("inspect every village in the region and report who needs help" → regional inspection assignment the administrator organises within authority and resources; infeasible orders are explained, not faked).

## 20–21. Mastery in every ordinary profession
Examples: farmer, merchant, blacksmith, carpenter/builder, healer, scholar, soldier, commander, administrator, politician, hunter, sailor/navigator, criminal, investigator, innkeeper, teacher (and every other career at the same depth). Five separate dimensions: personal skill, practical achievement, professional recognition, institutional influence, legacy. Example "world's greatest farmer": learn soil/weather/irrigation/rotation/tools/labour → better methods, land, workers, apprentices → others copy → councils ask advice → king may ask you to lead reform; you can decline. Expertise raises the weight of your advice but others still weigh their interests (commander wants the land for defence, noble resists reform, administrator worries about cost).

## 22. Criminal mastery
Stages: outsider → associate → member → specialist → lieutenant → leader → regional power → legendary figure; not automatic, positions can be lost, members rebel/leave/split. Mastery = leadership, negotiation, finance, connections, secrecy, recruitment, reading rivals — not body count. Criminal councils (losses, disputes, succession, rivals); lieutenants run assigned operations; leaders delegate and set rules; law, rivals and public react; no immunity.

## 23. Opportunities from real recognition and real demand
Smith → noble commissions, guild asks for expert judgement; farmer → council advice; general → defence assessment; merchant → merger offers; criminal → faction negotiation; carpenter → bridge contract; healer → train practitioners; adventurer → escort a scholar; administrator → run a struggling settlement. Generated only when someone actually needs it (no threshold-triggered spam); NPC experts get invitations too.

## 24. NPCs create organisations themselves
Example: an ambitious unemployed carpenter recruits colleagues, finds financing, equipment, premises, workers → company succeeds or fails (savings lost, back to employment); later it bids on the player's house. Every organisation needs: founders + objectives, permitted activities + structure, resources/financing, membership/hiring, property/location, governance/budget/authority, relations with others, legal recognition, internal dispute resolution, possible success/failure/merger/reform/dissolution. Applies to farms, guilds, trading houses, schools, military companies, settlements, charities, religious bodies, criminal groups.

## 25. Independent rivals and competitors
Bakery example: rival improves recipes, cuts prices, better pay, expands; ex-employee opens a shop; shared suppliers; customers choose by distance, price, quality, relationships, taste. Player responds (quality, equipment, staff, products, partnership, sell). Rivalry ≠ hostility (competitor-friends, guilds cooperating on training while bidding against each other, trading enemies); rivals can need help or quit.

## 26. Economic power changes the world
Simulate production, consumption, stock, transport (caravans, ships, carts, pack animals), prices (supply, demand, transport, local conditions), employment/wages, ownership, finance (savings, loans, debt, investment, insolvency), government (tax, tariffs, spending, regulation), trade agreements, competition, shortages with real social/political effects. Example: the player's estate withholds grain from a neighbour → others raise output, merchants import, government releases reserves, buyers bid up, workers worry; only with real dominance and no alternatives does a severe shortage follow (political pressure, legal action, resentment, migration). Market domination attempts provoke counter-moves (new suppliers, coalitions, government help, new routes, legal challenges). Chain: agriculture → warehousing → transport → government.

## 27. Small professions influence big events
Stable worker notices sick military horses → employer may dismiss it → reputation/credible observations get a vet/official to investigate → disease, bad feed or poor conditions found → military adjusts. Works for every profession.

## 28. World history, not a quest log
Significant events recorded with: what, when, where, true participants, witnesses, remaining evidence, who was told, report reliability, effects on relationships/goals, whether it enters long-term history. Example company timeline (founded in Dunhallow → trades with Ironmarch → shortage losses → senior employee founds rival → cooperation on a contract → founder retires and names successor); knowledge of it varies by person (veteran, distant trader, historian with documents, newcomer). Rumours can be wrong; facts stored separately for consistency.

## 29. Repetition allowed, identical presentation not
Vary by initiator, location, time, participants, knowledge, stakes, resources, emotion, outcome (success, rejection, compromise, delay, failure), follow-up. Needs quality filters/constraints plus strong authored dialogue and animation building blocks so combinations stay believable.

## 30. NPCs may do nothing
Procrastinate, hesitate, wait for evidence, seek reassurance, reprioritise, be busy; delay non-urgent reports to the next meeting; skip risky investments; choose family over promotion; avoid pointless confrontations.

## 31. Layered NPC reasoning
Identity/personality/memory → personal goals (career, family, survival, ambition) + organisational goals (duties, orders, obligations) → evaluation & planning (priorities, methods, risks) → world interaction (work, speak, trade, travel, learn, recruit, build, negotiate) → results/experience/adaptation. Data groups per important NPC: identity, personality, current situation, knowledge, goals, plans, skills, social, institutions, property, communication (appointments, messages, invitations), history, simulation (current behaviour, next evaluation time). Persistent NPCs never respawn as different people.

## 32. NPCs ask for help
Example: appointed governor lacks guards → considers recruiting, re-routing patrols, street lighting, allied help, funding request → escalates beyond authority with a message (Governor Aldren: eastern-district robberies, overstretched guards, options: more budget or transfer western garrison veterans). Player can approve, reject, ask for evidence, replace, send to council, investigate. No reply ≠ freeze: they keep acting within authority.

## 33. Proactive subordinates
Advisers propose things unprompted (warehouses before a surplus, officer training, bridge repair, sponsoring a talented youth). Proposals carry a business case: initiator, issue, action, reason, cost, benefit, risks, authority required, alternative, deadline; delivered at meetings, by message or urgent audience; rejection remembered; being proven right affects confidence and relationship.

## 34. Precise authority
Permission categories: personnel, financial, property, military, administrative, diplomatic, information, succession. Examples: farm manager hires seasonal workers but can't sell the estate; general commands only his forces, can't change laws; city administrator approves routine repairs, council needed for major works; criminal lieutenant manages assigned members, not the whole treasury. Configured via an organisation UI or natural conversation, bounded by law/rules/other authorities; even kings face resistance.

## 35. NPC↔NPC meetings without the player
Three merchants facing high transport costs → one proposes cooperation → others evaluate → meeting at a suitable place → negotiate contributions → maybe found a shared transport company, or fail and go back. Physical continuity when simulated in detail (travel, greet, sit, discuss, documents, leave, react to no-shows); abstract resolution with the same rules when off-screen; the player's presence changes but never replaces others' agency.

## 36. Lasting conversation context
Topics that matter persist (moving towns → friend asks later → helps pack → letters); memory of promises/important statements; who-knows-what; follow-up interest; scheduled future contact; natural forgetting of trivia; strong memory for betrayals, marriages, appointments, major promises.

## 37. Creativity bounded by knowledge and means
Carpenter with contacts repairs his house; poor labourer asks a neighbour, finds temporary housing or saves. Planner combines available actions, estimates success, learns from failure, abandons plans; expensive planning only on meaningful change, never per frame.

## 38. Living World Test Bench
Measure: independent NPC activity, relationship continuity, social coherence (dialogue matches knowledge), economic consistency (traceable goods/money/labour), delegation validity, event diversity, player agency, off-screen continuity. Sample test: one village, 100 simulated days, no player — did people work and get paid, families adapt, jobs change, shops resupply, friendships/rivalries form, shortages get handled — and can every significant event be explained (e.g. why 20 people quit: wages, better jobs, danger, or a bug)? Deterministic and inspectable.

## 39. Optimisation
Nearby: full movement, conversation, gestures, faces, physics, event-driven decisions. Regional: jobs, schedules, relationships, selected group activity, no expensive visuals. Distant: persistent goals, economic decisions, organisations, life events at intervals. Off-screen work computed from skill, tools, supplies, time, conditions; detailed scene loads consistent with that state; nearby NPCs must physically use tools.

## 40. Build order (society foundation)
1 persistent identities, households, relationships → 2 needs, occupations, goal selection → 3 work, production, property, local economy → 4 general action planner with failure/replanning → 5 knowledge, communication, reputation, social context → 6 organisations, ranks, authority, delegation → 7 meetings, invitations, petitions, executable decisions → 8 dynamic opportunity generation → 9 off-screen sim, persistence, profiling → 10 animation/voice/presentation polish.
First playable test: a settlement of 30–50 persistent NPCs with farm, blacksmith, inn, merchant shop, houses, guards and a council; player starts as a resident, works several jobs, builds relationships, hires NPCs, joins an organisation, requests an audience, attends a meeting, eventually runs a business; over simulated time NPCs change jobs, form relationships, start businesses, hit shortages, ask for help and solve some problems alone. Only after this works: scale to cities, kingdoms, armies and dungeon civilisations. (Note: aligns with the MASTER_BACKLOG vertical slice — Ashford + Kingsreach with 24 named NPCs; extend it to 30–50.)

## Central rule
**The world is not waiting for you.** Farmers get rich without you, soldiers get promoted while you're away, merchants build competitors, criminals reform, subordinates can surpass you or found their own organisations, rulers ignore good advice, councils change kingdoms without you, and a child you helped may change the world decades later. Everything else (bigger kingdoms, dungeon civilisations, war, later fantasy systems) builds on this same foundation.
