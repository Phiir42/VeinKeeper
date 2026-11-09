local _, ns = ...

-- node name -> { skill = required Mining skill, item = ore item whose game icon the pin uses
--   (verified against Wowhead Forever loot data), tex = drawn fallback icon in Icons\, color = tooltip colour }
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
-- Forever is Classic-based: there are no TBC ores. ids = Wowhead object IDs, which
-- identify a mined node in any client language (from the loot window's GUID).
ns.NODES = {
	-- new in Forever
	["Poor Copper Vein"]                = { skill = 1,   item = 2770, tex = "copper_poor",      color = C.copper, ids = { 562111 } },   -- starter zones
	["Chunk of Amber"]                  = { skill = 1,   item = 2770, tex = "amber",            color = C.amber, ids = { 656332 } },    -- Teldrassil
	["Large Chunk of Amber"]            = { skill = 1,   item = 2770, tex = "amber_large",      color = C.amber, ids = { 656333 } },    -- Teldrassil
	["Heavy Thorium Vein"]              = { skill = 300, item = 248815, tex = "thorium_heavy",    color = C.heavy, ids = { 566779 } },    -- no location on Wowhead yet

	-- Classic nodes
	["Copper Vein"]                     = { skill = 1,   item = 2770, tex = "copper",           color = C.copper, ids = { 1731, 103713, 3763, 2055 } },
	["Tin Vein"]                        = { skill = 65,  item = 2771, tex = "tin",              color = C.tin, ids = { 1732, 2054, 3764, 103711 } },
	["Incendicite Mineral Vein"]        = { skill = 65,  item = 3340, tex = "incendicite",      color = C.fire, ids = { 1610, 1667 } },  -- Wetlands
	["Silver Vein"]                     = { skill = 75,  item = 2775, tex = "silver",           color = C.silver, ids = { 1733, 105569 } },
	["Ooze Covered Silver Vein"]        = { skill = 75,  item = 2775, tex = "ooze_silver",      color = C.silver, ids = { 73940 } },
	["Lesser Bloodstone Deposit"]       = { skill = 75,  item = 4278, tex = "bloodstone",       color = C.blood, ids = { 2653 } },    -- Arathi Highlands
	["Iron Deposit"]                    = { skill = 125, item = 2772, tex = "iron",             color = C.iron, ids = { 1735 } },
	["Indurium Mineral Vein"]           = { skill = 150, item = 5833, tex = "indurium",         color = C.indurium, ids = { 19903 } }, -- Uldaman
	["Gold Vein"]                       = { skill = 155, item = 2776, tex = "gold",             color = C.gold, ids = { 1734, 150080, 181109 } },
	["Ooze Covered Gold Vein"]          = { skill = 155, item = 2776, tex = "ooze_gold",        color = C.gold, ids = { 73941 } },
	["Mithril Deposit"]                 = { skill = 175, item = 3858, tex = "mithril",          color = C.mithril, ids = { 2040, 150079, 176645 } },
	["Ooze Covered Mithril Deposit"]    = { skill = 175, item = 3858, tex = "ooze_mithril",     color = C.mithril, ids = { 123310 } },
	["Truesilver Deposit"]              = { skill = 230, item = 7911, tex = "truesilver",       color = C.truesil, ids = { 2047, 150081, 181108 } },
	["Ooze Covered Truesilver Deposit"] = { skill = 230, item = 7911, tex = "ooze_truesilver",  color = C.truesil, ids = { 123309 } },
	["Dark Iron Deposit"]               = { skill = 230, item = 11370, tex = "darkiron",         color = C.darkiron, ids = { 165658 } },
	["Small Thorium Vein"]              = { skill = 245, item = 10620, tex = "thorium_small",    color = C.thorium, ids = { 324, 150082, 176643 } },
	["Ooze Covered Thorium Vein"]       = { skill = 245, item = 10620, tex = "ooze_thorium_small", color = C.thorium, ids = { 123848 } },
	["Rich Thorium Vein"]               = { skill = 275, item = 10620, tex = "thorium_rich",     color = C.thorium, ids = { 175404 } },
	["Ooze Covered Rich Thorium Vein"]  = { skill = 275, item = 10620, tex = "ooze_thorium_rich", color = C.thorium, ids = { 177388 } },
	["Hakkari Thorium Vein"]            = { skill = 275, item = 10620, tex = "thorium_hakkari",  color = C.thorium, ids = { 180215 } },  -- Zul'Gurub
	["Small Obsidian Chunk"]            = { skill = 305, item = 22202, tex = "obsidian",         color = C.obsidian, ids = { 181068 } }, -- Silithus / AQ
	["Large Obsidian Chunk"]            = { skill = 305, item = 22203, tex = "obsidian_large",   color = C.obsidian, ids = { 181069 } }, -- Silithus / AQ

	-- Season of Discovery quest nodes still in Forever's data (need a quest key item to mine)
	["Cold Iron Deposit"]               = { skill = 125, tex = "coldiron",         color = C.coldiron, ids = { 439558 } }, -- Duskwood
	["Fool's Gold Vein"]                = { skill = 175, tex = "foolsgold",        color = C.gold, ids = { 439628 } },     -- Ashenvale
	["Starsilver Vein"]                 = { skill = 245, tex = "starsilver",       color = C.silver, ids = { 439778 } },   -- The Hinterlands
	["Greater Moonstone Formation"]     = { skill = 245, tex = "moonstone",        color = C.moon, ids = { 439815 } },     -- Feralas
}

local GENERIC = { skill = 0, tex = "unknown", color = { 0.8, 0.8, 0.8 } }
local PATH = "Interface\\AddOns\\VeinKeeper\\Icons\\"

-- object ID -> node name
ns.OBJECTS = {}
for name, info in pairs(ns.NODES) do
	for _, id in ipairs(info.ids) do ns.OBJECTS[id] = name end
end

function ns:NodeInfo(name)
	return name and self.NODES[name] or GENERIC
end

-- The node name for a name as the game shows it: the English names directly,
-- other client languages through names learned when mining (the loot
-- window's object ID gives the node, the cast its local name). nil if unknown.
function ns:NodeName(shown)
	if not shown then return nil end
	if self.NODES[shown] then return shown end
	return self.db and self.db.names[shown]
end

-- The object ID in a "GameObject-0-...-<id>-<spawn>" GUID. Only that field
-- is read: the server and spawn fields around it may be obfuscated.
function ns:ObjectID(guid)
	if type(guid) ~= "string" or (issecretvalue and issecretvalue(guid)) then return nil end
	return tonumber(guid:match("^GameObject%-[^-]*%-[^-]*%-[^-]*%-[^-]*%-(%d+)%-"))
end

-- The game's own ore item icon when there is one (and /vk icons is on),
-- otherwise the drawn icon. Season of Discovery quest nodes have no ore item.
local itemIcons = {}
function ns:NodeIcon(name)
	local info = self:NodeInfo(name)
	if info.item and (not self.db or self.db.settings.gameIcons) then
		local icon = itemIcons[info.item]
		if not icon then
			icon = (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(info.item))
				or (GetItemIcon and GetItemIcon(info.item))
			itemIcons[info.item] = icon
		end
		if icon then return icon, true end
	end
	return PATH .. info.tex, false
end

ns.RING = PATH .. "ring"
