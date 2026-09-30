# Region 1 item set (levels 1-60)

The complete item set for Region 1 (Ashford Vale): 1,100+ new items on top of the 77 original ids, 687 recipes, salvage,
34 shops, 19 loot themes and 20 monster drop tables, equipment visuals, icons, and a test suite. Everything is data;
old ids, old prices and old stats are untouched. The game goes to level 500; this covers the first 60.

## Where things live

| what | where |
|---|---|
| Generator (edit this, then run it) | `kingdom/tools/items/*.py`, run `python3 tools/items/build.py` from `kingdom/` |
| Items by category | `data/items/{materials,weapons,armour,tools,food,alchemy,misc,uniques}.json`, listed in `data/items/index.json` |
| Fields added to old ids (level, tint, spoilage ...) | `data/items/legacy_patch.json` (only fills keys the old entry lacks) |
| Recipes by skill, new skills and stations, salvage | `data/recipes/*.json`, `data/recipes/meta.json`, `data/recipes/salvage.json` |
| Shops, settlements, loot, sets, crops, visuals | `data/items/{shops,loot,sets,crops,visuals}.json` |
| Loader and API | `scripts/sim/items_db.gd` (no autoload, pure static) |
| Icons | `assets/ui/icons/items/<id>.svg`, one per item, game-icons.net glyphs recoloured by material (CC BY 3.0) |
| Models | `assets/items/weapons` (KayKit, CC0), `assets/items/armor` (see `assets/items/CREDITS.md`) |
| Shop UI | `scripts/ui/shop_screen.gd` |
| Tests | `tests/test_items_db.gd` (31 tests) |
| Screenshots | `tools_qa/items/items_shots.gd` (xvfb), sheet at `/tmp/claude-0/shots/items_sheet.png` |

`data/items.json` is still the GLoot protoset. The new entries are merged into the same database:
`Crafting.item_db()` calls `ItemsDB.merge_into()`, and `ItemsDB.register(Life)` (called from `gathering_items.gd register()`, which Life
already calls at boot) adds them to the live GLoot prototree. `Crafting.item_info / item_name / item_exists`, `Life.item_prop`, inventory
saves and every existing call site work for old and new ids alike.

## Item fields

Common: `name, category, price, max_stack_size, weight, rarity (0 common .. 4 legendary), level (1-60), description, tint, type`.
Categories keep the old vocabulary where the UI depends on it (`food, healing, material, ore, gear, tool, tack, quest`) and add
`ammo, manual, lore, key, furniture, seed, feed`; `type` is the fine class (`sword, body_armour, dish, herb, pill, trade_good ...`).

Gear: `slot, armour, damage, speed, durability, req_level, weapon_type, dmg_type (slash/pierce/blunt/magic), reach, two_handed, ranged, ammo,
magic, block, resist, crit, qi_regen, max_health, max_stamina, armour_pierce, armour_class (robe/light/medium/heavy), armour_load (0-1, for
power_paths.gd), set, material, tier (0-6), affinity (skill trees), path (soul paths)`.
Food: `nutrition, heal, buff_name/stat/value/hours, spoil_hours, spoils_into, raw, cooked, preserved, drink, region`.
Alchemy: `heal, cures (injury type), qi_restore, cultivation_realm / cultivation_xp / breakthrough_bonus / permanent_stat (pills),
coating, coating_damage, thrown, repair_fraction`.
Tools: `tool (skill), tool_tier, tool_power`. Manuals: `manual_tree, path, realm, realm_level, teaches[]`. Seeds: `plants`.

## Tiers (materials) and levels

| tier | weapons/armour | level window | rarity | mastery (recipe) level |
|---|---|---|---|---|
| 0 | wood, flint, padded hide, linen | 1-8 | common | 1-2 |
| 1 | bronze, leather | 6-16 | common | 2-4 |
| 2 | iron (the old iron_sword, iron_helm ...) | 12-26 | uncommon | 3-5 |
| 3 | steel | 24-38 | uncommon | 5-7 |
| 4 | fine steel | 34-47 | rare | 7-8 |
| 5 | spirit-iron | 44-55 | epic | 9 |
| 6 | rift-crystal | 52-60 | epic | 10 |

Above that: 12 named epics (Region 1 uniques) and 11 legendaries (Oathblade of Caldrenn, Emberglass Longbow, Wyrmbane, Staff of the Quiet Star,
Gauntlets of the Iron Lotus, Aegis of Ashford, Mantle of Ash, Crown of Embers, Ring of the First Flame, Amulet of the Sleeping Ward, Rift-Warden's
Breastplate, Seer's Shroud). Uniques are loot and boss rewards only: never sold, never crafted.

## Catalogue

- **Weapons (133 + shields, ammo):** dagger, sword, sabre, greatsword, axe, battleaxe, mace, warhammer, spear, halberd, fist weapons (martial arts), shortbow,
  longbow, crossbow, staff, wand, in every tier they suit; 23 shields (buckler, round, kite, tower); arrows (7 tiers), bolts (6), arrowheads.
  Bows and staves are named for their wood (Ash, Elm, Yew, Ironwood, Steelbound, Spiritwood) with focus gems on the magic ones.
- **Armour (275):** light (Padded Hide, Leather, Hardened, Studded, Bearhide, Wyvernscale, Rift-Stalker), medium (Bronze Scale, Iron Mail, Steel Mail,
  Fine Steel Lamellar, Spirit-Iron Scale, Rift-Crystal Scale), heavy (Bronze Cuirass, Iron Plate, Steel Plate, Knight's Plate, Spirit-Iron Plate,
  Rift-Crystal Plate) and mage robes (Peasant Linen, Acolyte Wool, Adept, Enchanter's Spidersilk, Sage's Silk, Spirit-Silk, Riftweave), each with head,
  body, hands, legs, feet and cloak: 26 sets. 11 sects x 3 ranks of sect robes plus sashes. Rings and amulets (7 stat themes x 4 tiers), 16 talismans,
  4 belts/pouches. Set bonuses at 3 / 5 / 6 pieces (`data/items/sets.json`, applied by `Equipment.stats()`).
- **Tools (65):** felling axes, pickaxes, smithing hammers, sickles, shovels, saws, chisels, skinning knives (flint to spirit-iron), fishing rods, mortars,
  plus adventuring kit (torch, lantern, tinderbox, waterskin, bedroll, tent, compass, spyglass, lockpicks, bait, cooking pot, ink and quill).
- **Materials (158):** ores, gems, spirit stones, 8 ingots, timber, hides and leathers, cloth and thread, dyes, 24 herbs, monster parts, beast cores and
  elemental essences, construction goods, craft aids.
- **Food and drink (152):** raw produce, raw meat and fish, 47 cooked dishes, 21 baked goods, 10 preserved foods, 23 drinks (ales, mead, cider, wine, tea,
  spirits), regional dishes for Caldrenn, Shenlu, Seirune, Veylwood, Solmarch, the Ongur steppe and Hollowdeep. Buffs, healing, spoil times.
- **Alchemy (71):** 5 healing potions, stamina and qi draughts, injury cures (one per `RAInjuries` type), antidotes, 10 buff potions, 7 long elixirs,
  10 cultivation pills (xp and breakthrough, per realm) and 4 body-tempering pills, weapon coatings, bombs, repair kits.
- **Manuals and scrolls (79):** a manual for every technique tier of every skill tree (13 trees, realm-gated), the 5 existing manuals as items, 16 scrolls.
- **Lore, keys, quest items, trade goods, furniture, seeds, feed, tack:** 12 books, 11 keys, 19 quest items, 26 trade goods (every enterprise good is now an
  item), 36 furniture pieces with comfort values, 24 seed packets, 7 feeds, 16 tack and mount items.

## Crafting

687 recipes (old ones untouched). New skills: baking, brewing, tailoring, jewelry, fletching, masonry. New stations: oven, brew vat, loom, jeweller's
bench; every recipe also works at a station that already exists (hearth, anvil, workbench, alchemy table), so nothing is locked behind missing buildings.
`recipe.level` (1-10) is the mastery gate; quality odds follow the existing Rough / Fine / Masterwork roll. Prices of crafted goods are derived from
their inputs (markup by skill), so crafting never prints money. **Salvage:** `Crafting.salvage(id, inv, kinds)` breaks crafted gear into about 45% of its
materials (331 items). `Crafting.tool_bonus()` gives the tool xp bonus for any tool of the right kind, rising with tier.

## Shops and markets

Every shop has three tiers (village, town, city); higher tiers add goods and never remove any. Goods are capped by level (14 / 34 / 56) and rarity
(rare / epic never in ordinary shops). Shops: general store, grocer, butcher, fishmonger, baker, tavern (meals and rooms), blacksmith, armourer, bowyer and
fletcher, tailor, leatherworker, alchemist, herbalist, jeweller, carpenter, mason, miners' supply, stable, farm supply, bookseller, temple, adventurers'
outfitter, back-alley fence and 11 sect hall shops. `ItemsDB.shops_for_settlement(kind, population, idents)` picks the shops; `ItemsDB.stock_settlement()`
fills an RAMarket (a random share of each shelf, 10 staples always, so neighbouring towns differ). Restocking is the market's own: made-per-day for
food and materials, import wagons (slowed by road danger) for gear. `economy.gd _build_market` stocks every regional market; Ashford's market is stocked
by `ItemsDB.register`. Merchant menus in `village_services.gd` open the shop UI.

## Loot API (for dungeons, towers, exploration)

```gdscript
const ItemsDB := preload("res://scripts/sim/items_db.gd")
var t := ItemsDB.loot_table(tier, theme)                      # {tier, theme, rolls, gold, entries: [[item, weight, min, max]]}
var r := ItemsDB.roll_loot(tier, theme, rng, bonus_rolls)     # {items: [{item, count}], gold}
var d := ItemsDB.monster_drops("wolf", rng, extra_rolls)      # [{item, count}]
```
Danger tiers 1-5 (levels 1-14, 8-26, 20-40, 34-52, 46-60; max rarity rare, rare, rare, epic, epic). Themes: `beast, humanoid, undead, rift, chest_common,
chest_military, chest_arcane, chest_treasure, dungeon_crypt, dungeon_cave, dungeon_ruin, dungeon_warren, tower, boss, bandit_camp, orc_camp, ore_vein,
herb_patch, village_home`. `boss` and `tower` at tiers 4-5 include the named uniques. Species: wolf, corrupted_wolf, boar, bear, troll, wyvern, goblin,
goblin_chief, orc, orc_chief, bandit, bandit_leader, skeleton, ash_ghost, giant_spider, scar_beast, rift_creature, rabbit, deer, fox.

## Visuals

`data/items/visuals.json` maps 337 items to models: weapon families to the KayKit set (dagger A/B, sword A-E, axe A-C, hammer A-C, halberd, spear, bows,
staves, wand, fist weapons, shields), armour sets to Knights Character Kit / Anglo-Saxon / Quaternius pieces, robes to hats and capes with a colour tint.
`ItemsDB.visual(id)` gives `{model, model_l, mirror_l, attach (bone), scale, tint}`; `ItemsDB.visual_node(id, left)` returns a tinted Node3D ready to parent
to a `BoneAttachment3D`. Robes and some legs have `tint_only` (recolour the character's own outfit).

## Integration hooks (not done here: other agents own these files)

- **Equipment visuals on the player/NPC rig:** connect `Life.equipment.changed(slot, id)` and attach `ItemsDB.visual_node(id)`; bones per `visual(id).attach`
  (`hand_r, hand_l, lowerarm_l, head, spine_03, pelvis, hand, calf, foot`; `hand/calf/foot` take `_l` / `_r`).
- **Requirements:** `req_level` is data only; `Equipment.meets_requirements(id, level)` exists but `equip()` does not block.
- **Pills, scrolls, coatings, recall:** `Equipment.consume` calls `Life.apply_item_effect(id, info) -> String` when Life has it (cultivation agent).
  Without it those items are refused, not wasted.
- **Spoilage:** `ItemsDB.spoil_hours / spoiled_into` exist; nothing ages inventory stacks yet.
- **Seeds:** `plant()` does not consume seeds yet (`ItemsDB.crop_of_seed`).
- **Dungeons/towers/monsters:** call `ItemsDB.roll_loot` / `monster_drops` (above).
- **Settlement idents:** pass a settlement's identity tags as `s["idents"]` to `economy._build_market` and they add shops (smithy, temple, library ...).
