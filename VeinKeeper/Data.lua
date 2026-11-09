local _, ns = ...

-- node name -> { skill = required Mining skill, tex = icon file in Icons\, color = tooltip colour }
-- Unknown node names are still recorded; they just get a "?" icon.
local C = {
	copper   = { 0.85, 0.50, 0.30 },
	tin      = { 0.70, 0.75, 0.75 },
	silver   = { 0.85, 0.90, 1.00 },
	iron     = { 0.65, 0.45, 0.40 },
	gold     = { 1.00, 0.82, 0.20 },
	mithril  = { 0.40, 0.80, 0.65 },
	truesil  = { 0.75, 0.60, 1.00 },
	darkiron = { 0.70, 0.20, 0.20 },
	thorium  = { 0.30, 0.90, 0.55 },
	fire     = { 1.00, 0.45, 0.20 },
	blood    = { 0.90, 0.20, 0.30 },
	indurium = { 0.55, 0.55, 0.85 },
	obsidian = { 0.45, 0.30, 0.65 },
	amber    = { 1.00, 0.65, 0.15 },
	heavy    = { 0.20, 0.75, 0.45 },
	coldiron = { 0.60, 0.80, 0.95 },
	moon     = { 0.75, 0.85, 1.00 },
}

-- Every mining node in WoW Forever (1.60.1), taken from Wowhead's Forever
-- object database (wowhead.com/forever/objects/mineral-veins, 46 objects,
-- checked 2026-11-08). Names must match the in-game object name exactly.
-- Forever is Classic-based: there are no TBC ores. Comment = Wowhead object ID(s).
ns.NODES = {
	-- new in Forever
	["Poor Copper Vein"]                = { skill = 1,   tex = "copper_poor",      color = C.copper },   -- 562111, starter zones
	["Chunk of Amber"]                  = { skill = 1,   tex = "amber",            color = C.amber },    -- 656332, Teldrassil
	["Large Chunk of Amber"]            = { skill = 1,   tex = "amber_large",      color = C.amber },    -- 656333, Teldrassil
	["Heavy Thorium Vein"]              = { skill = 300, tex = "thorium_heavy",    color = C.heavy },    -- 566779, no location on Wowhead yet

	-- Classic nodes
	["Copper Vein"]                     = { skill = 1,   tex = "copper",           color = C.copper },   -- 1731, 103713, 3763, 2055
	["Tin Vein"]                        = { skill = 65,  tex = "tin",              color = C.tin },      -- 1732, 2054, 3764, 103711
	["Incendicite Mineral Vein"]        = { skill = 65,  tex = "incendicite",      color = C.fire },     -- 1610, 1667, Wetlands
	["Silver Vein"]                     = { skill = 75,  tex = "silver",           color = C.silver },   -- 1733, 105569
	["Ooze Covered Silver Vein"]        = { skill = 75,  tex = "ooze_silver",      color = C.silver },   -- 73940
	["Lesser Bloodstone Deposit"]       = { skill = 75,  tex = "bloodstone",       color = C.blood },    -- 2653, Arathi Highlands
	["Iron Deposit"]                    = { skill = 125, tex = "iron",             color = C.iron },     -- 1735
	["Indurium Mineral Vein"]           = { skill = 150, tex = "indurium",         color = C.indurium }, -- 19903, Uldaman
	["Gold Vein"]                       = { skill = 155, tex = "gold",             color = C.gold },     -- 1734, 150080, 181109
	["Ooze Covered Gold Vein"]          = { skill = 155, tex = "ooze_gold",        color = C.gold },     -- 73941
	["Mithril Deposit"]                 = { skill = 175, tex = "mithril",          color = C.mithril },  -- 2040, 150079, 176645
	["Ooze Covered Mithril Deposit"]    = { skill = 175, tex = "ooze_mithril",     color = C.mithril },  -- 123310
	["Truesilver Deposit"]              = { skill = 230, tex = "truesilver",       color = C.truesil },  -- 2047, 150081, 181108
	["Ooze Covered Truesilver Deposit"] = { skill = 230, tex = "ooze_truesilver",  color = C.truesil },  -- 123309
	["Dark Iron Deposit"]               = { skill = 230, tex = "darkiron",         color = C.darkiron }, -- 165658
	["Small Thorium Vein"]              = { skill = 245, tex = "thorium_small",    color = C.thorium },  -- 324, 150082, 176643
	["Ooze Covered Thorium Vein"]       = { skill = 245, tex = "ooze_thorium_small", color = C.thorium }, -- 123848
	["Rich Thorium Vein"]               = { skill = 275, tex = "thorium_rich",     color = C.thorium },  -- 175404
	["Ooze Covered Rich Thorium Vein"]  = { skill = 275, tex = "ooze_thorium_rich", color = C.thorium }, -- 177388
	["Hakkari Thorium Vein"]            = { skill = 275, tex = "thorium_hakkari",  color = C.thorium },  -- 180215, Zul'Gurub
	["Small Obsidian Chunk"]            = { skill = 305, tex = "obsidian",         color = C.obsidian }, -- 181068, Silithus / AQ
	["Large Obsidian Chunk"]            = { skill = 305, tex = "obsidian_large",   color = C.obsidian }, -- 181069, Silithus / AQ

	-- Season of Discovery quest nodes still in Forever's data (need a quest key item to mine)
	["Cold Iron Deposit"]               = { skill = 125, tex = "coldiron",         color = C.coldiron }, -- 439558, Duskwood
	["Fool's Gold Vein"]                = { skill = 175, tex = "foolsgold",        color = C.gold },     -- 439628, Ashenvale
	["Starsilver Vein"]                 = { skill = 245, tex = "starsilver",       color = C.silver },   -- 439778, The Hinterlands
	["Greater Moonstone Formation"]     = { skill = 245, tex = "moonstone",        color = C.moon },     -- 439815, Feralas
}

local GENERIC = { skill = 0, tex = "unknown", color = { 0.8, 0.8, 0.8 } }
local PATH = "Interface\\AddOns\\VeinKeeper\\Icons\\"

function ns:NodeInfo(name)
	return name and self.NODES[name] or GENERIC
end

function ns:NodeIcon(name)
	return PATH .. self:NodeInfo(name).tex
end

ns.RING = PATH .. "ring"
