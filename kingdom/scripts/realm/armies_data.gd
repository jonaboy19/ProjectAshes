extends RefCounted
## Static data for the Army entity (LW-7.1 to 7.3, docs/design/LIVING_WORLD_SANDBOX.md section 9). No state.

const CAMP_ARMY_MAX := 64
## Force types. legal: lawful (the crown and its towns), licensed (needs a charter or office), tolerated (small, local, temporary),
## illegal (no legal size at all unless a kingdom has recognised the owner). lim = base size limit at rank 0; scale = +fraction per rank step.
const FORCES := {
	"royal": {"legal": "lawful", "lim": 600, "scale": 1.5, "wage": 1.2, "mo": 0.75, "di": 0.75, "label": "royal army"},
	"garrison": {"legal": "lawful", "lim": 120, "scale": 1.0, "wage": 1.0, "mo": 0.7, "di": 0.7, "label": "garrison"},
	"town_guard": {"legal": "lawful", "lim": 30, "scale": 0.8, "wage": 0.9, "mo": 0.65, "di": 0.6, "label": "town guard"},
	"household": {"legal": "licensed", "lim": 12, "scale": 1.2, "wage": 1.0, "mo": 0.75, "di": 0.7, "label": "household troops"},
	"guild_security": {"legal": "licensed", "lim": 10, "scale": 0.8, "wage": 0.9, "mo": 0.6, "di": 0.6, "label": "guild security"},
	"bodyguard": {"legal": "licensed", "lim": 6, "scale": 0.6, "wage": 1.4, "mo": 0.8, "di": 0.8, "label": "bodyguard"},
	"mercenary": {"legal": "licensed", "lim": 80, "scale": 0.8, "wage": 1.6, "mo": 0.6, "di": 0.5, "label": "mercenary company"},
	"militia": {"legal": "tolerated", "lim": 60, "scale": 1.0, "wage": 0.3, "mo": 0.6, "di": 0.45, "label": "militia"},
	"levy": {"legal": "tolerated", "lim": 0, "scale": 0.0, "wage": 0.2, "mo": 0.5, "di": 0.4, "label": "levy"},
	"adventurer_band": {"legal": "tolerated", "lim": 10, "scale": 0.5, "wage": 0.0, "mo": 0.7, "di": 0.45, "label": "adventurer band"},
	"sect_order": {"legal": "tolerated", "lim": 30, "scale": 0.7, "wage": 0.5, "mo": 0.85, "di": 0.8, "label": "sect order"},
	"independent_legion": {"legal": "illegal", "lim": 0, "scale": 0.0, "wage": 1.1, "mo": 0.7, "di": 0.7, "label": "independent legion"},
	"rebels": {"legal": "illegal", "lim": 0, "scale": 0.0, "wage": 0.2, "mo": 0.65, "di": 0.35, "label": "rebels"},
}
const LEGAL_ORDER := ["lawful", "licensed", "tolerated", "illegal"]
## Raising levies beyond the office limit (stewardship "levy", counted in tens of men).
const LEVY_PER_POINT := 10
## A kingdom that has recognised the owner (diplomacy "recognize") lets an otherwise illegal force stand up to this many men.
const RECOGNISED_LIMIT := 60
const SUSPICION_OVER := 0.35      # suspicion per 100 % over the limit
const SUSPICION_ILLEGAL := 0.004  # per man of an illegal force
const SUSPICION_DECAY := 0.06     # per week

## Unit kinds. wage = gold per man per day at level 0, train = days per man-level per 10 men (min days), cost = gold per man per level, siege = campaign/siege kind.
const UNITS := {
	"spear": {"wage": 1.0, "train": 5, "cost": 6, "siege": "spear", "pw": 1.0},
	"infantry": {"wage": 1.1, "train": 6, "cost": 7, "siege": "infantry", "pw": 1.05},
	"archer": {"wage": 1.3, "train": 8, "cost": 9, "siege": "archer", "pw": 1.1},
	"cavalry": {"wage": 2.4, "train": 10, "cost": 16, "siege": "heavy_cav", "pw": 1.6},
	"scout": {"wage": 1.4, "train": 7, "cost": 8, "siege": "infantry", "pw": 0.6},
	"medic": {"wage": 1.5, "train": 8, "cost": 8, "siege": "infantry", "pw": 0.3},
	"engineer": {"wage": 1.8, "train": 9, "cost": 12, "siege": "infantry", "pw": 0.5},
	"mage": {"wage": 3.0, "train": 12, "cost": 24, "siege": "archer", "pw": 2.0},
}
const MAX_LEVEL := 5
const LEVEL_WAGE := 0.25        # +25 % wage per level
const SPECS := {
	"shield_wall": {"def": 1.2, "atk": 1.0, "days": 8, "units": ["spear", "infantry"]},
	"volley": {"def": 1.0, "atk": 1.15, "days": 8, "units": ["archer"]},
	"charge": {"def": 0.95, "atk": 1.25, "days": 10, "units": ["cavalry"]},
	"skirmish": {"def": 1.0, "atk": 1.08, "days": 6, "units": ["spear", "infantry", "archer", "scout"]},
	"scouting": {"def": 1.0, "atk": 1.0, "days": 6, "units": ["scout", "cavalry"]},
	"sapper": {"def": 1.0, "atk": 1.1, "days": 10, "units": ["engineer"]},
	"field_surgeon": {"def": 1.0, "atk": 1.0, "days": 8, "units": ["medic"]},
}
const RATION := 1.0
const WAGON_CAP := 120.0
const CARRY_PER_MAN := 3.0
const FOOD_PRICE := 0.5          # gold per ration
const DESERT_GRACE := 2          # unpaid days before men start to leave
const ARMY_SPEED := 180.0        # metres per hour (campaign.gd)
const COURIER_SPEED := 540.0
const TRAIN_SPEED := 120.0
const SIGHT_BASE := 140.0
const SIGHT_SCOUT := 320.0
const CONFIRM_HOURS := 6
const STALE_HALF_DAYS := 4.0
const INTEL_MIN := 0.08
const OFFICER_PERS := ["bold", "careful", "greedy", "loyal", "ambitious", "cruel", "honourable"]
const ORDER_KINDS := ["hold", "move", "attack", "retreat", "patrol", "defend", "escort", "forage", "scout"]
const RISKY := {"attack": 0.12, "defend": 0.06, "hold": 0.0, "move": 0.0, "retreat": -0.1, "patrol": 0.0, "escort": 0.03, "forage": 0.0, "scout": 0.05}
## Settlement defence
const WATCH_FULL := 6            # men on watch across the shifts for full cover
const WALL_BONUS := [1.0, 1.15, 1.35, 1.6]
const ATTACK_METHODS := ["assault", "blockade", "bribe_insider", "raid_outskirts", "skip"]
const EVENT_KEEP := 40
