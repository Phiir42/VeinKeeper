-- Yield: what each kind of node gives, from the loot windows you open on it.
--
-- VeinKeeperDB.yield[node name] = {
--   v = visits (one per node: every tap of a multi-tap vein is one visit),
--   t = taps (loot windows),
--   i = { [item ID] = { total quantity, visits it dropped in } },
-- }
-- The node is told by the loot's source GUID (its object ID, so it works in
-- any client language), and a visit by that GUID: a vein keeps its GUID
-- until it despawns, and a respawned one has a new one.
local _, ns = ...
local L = ns.L

local floor, max = math.floor, math.max

local MIN_VISITS = 3      -- fewer is too few to show an average
local SURE = 0.9          -- items in this share of visits show an amount, others a chance
local MIN_SESSION_SEC = 300 -- ore an hour only after this long

local visits, nVisits = {}, 0 -- node GUID -> { [item] = true } this visit, this session
local lastGUID, lastAt        -- the same loot window can be reported twice
local session = { visits = 0, items = {} }

local function Secret(v) return issecretvalue and issecretvalue(v) end

local function ItemName(id)
	local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
	if not name and GetItemInfo then name = GetItemInfo(id) end
	return name or ("item " .. id)
end

local ores = {} -- item IDs some node is mined for
for _, info in pairs(ns.NODES) do
	if info.item then ores[info.item] = true end
end
function ns:IsOre(id) return ores[id] == true end

-- The item a node is mined for: its ore, else (quest nodes) what it gave most.
local function MainItem(name, y)
	local item = ns:NodeInfo(name).item
	if item then return item end
	local best, bestQ
	for id, e in pairs(y.i) do
		if not bestQ or e[1] > bestQ then best, bestQ = id, e[1] end
	end
	return best
end

local function Add(name, guid, items)
	local y = ns.db.yield[name]
	if not y then
		y = { v = 0, t = 0, i = {} }
		ns.db.yield[name] = y
	end
	local visit = visits[guid]
	if not visit then
		if nVisits >= 200 then wipe(visits) nVisits = 0 end -- bounded; only recent nodes matter
		visit = {}
		visits[guid] = visit
		nVisits = nVisits + 1
		y.v = y.v + 1
		session.visits = session.visits + 1
	end
	y.t = y.t + 1
	session.start = session.start or time()
	for item, q in pairs(items) do
		local e = y.i[item]
		if not e then
			e = { 0, 0 }
			y.i[item] = e
		end
		e[1] = e[1] + q
		if not visit[item] then
			visit[item] = true
			e[2] = e[2] + 1
		end
		session.items[item] = (session.items[item] or 0) + q
	end
end

-- Loot from one mining node: count it. Anything else (a mob, a chest, loot
-- from several sources at once) is left alone.
ns:On("LOOT_READY", function()
	if not (GetLootSourceInfo and GetNumLootItems and GetLootSlotLink and GetLootSlotInfo) then return end
	local guid, name, items = nil, nil, {}
	for i = 1, GetNumLootItems() do
		local source = GetLootSourceInfo(i)
		local id = ns:ObjectID(source)
		local node = id and ns.OBJECTS[id]
		if not node or (guid and source ~= guid) then return end
		guid, name = source, node
		local link = GetLootSlotLink(i)
		local _, _, qty = GetLootSlotInfo(i)
		local item = link and not Secret(link) and tonumber(link:match("item:(%d+)"))
		if item and type(qty) == "number" and qty > 0 then items[item] = (items[item] or 0) + qty end
	end
	if not (guid and next(items)) or ns.db.ignore[name] then return end
	local now = GetTime()
	if guid == lastGUID and now - lastAt < 1 then return end
	lastGUID, lastAt = guid, now
	Add(name, guid, items)
end)

---------------------------------------------------------------------------
-- Showing it
---------------------------------------------------------------------------
-- "4.2 Thorium Ore a visit (14 visits)" for a node, or nil until it has
-- MIN_VISITS.
function ns:YieldText(name)
	local y = name and self.db.yield[name]
	if not y or y.v < MIN_VISITS then return end
	local item = MainItem(name, y)
	local e = item and y.i[item]
	if not e then return end
	return L["%.1f %s a visit (%d visits)"]:format(e[1] / y.v, ItemName(item), y.v)
end

-- One item's line: an amount a visit if it nearly always drops, else a chance.
local function ItemPart(id, e, v)
	local share = e[2] / v
	if share >= SURE then return L["%.1f %s"]:format(e[1] / v, ItemName(id)) end
	return L["%s %d%%"]:format(ItemName(id), floor(share * 100 + 0.5))
end

local function Visits(n)
	return n == 1 and L["1 visit"] or L["%d visits"]:format(n)
end

function ns:PrintYield()
	local names = {}
	for name, y in pairs(self.db.yield) do
		if y.v > 0 then names[#names + 1] = name end
	end
	if #names == 0 then
		return self:Print(L["no yield yet: mine a vein and its loot is counted from then on."])
	end
	table.sort(names, function(a, b)
		local sa, sb = self:NodeInfo(a).skill or 0, self:NodeInfo(b).skill or 0
		if sa ~= sb then return sa < sb end
		return a < b
	end)
	self:Print(L["average loot a visit:"])
	for _, name in ipairs(names) do
		local y = self.db.yield[name]
		local ids = {}
		for id in pairs(y.i) do ids[#ids + 1] = id end
		-- the most often dropped first, then the most plentiful
		table.sort(ids, function(a, b)
			local ea, eb = y.i[a], y.i[b]
			if ea[2] ~= eb[2] then return ea[2] > eb[2] end
			if ea[1] ~= eb[1] then return ea[1] > eb[1] end
			return a < b
		end)
		local parts = {}
		for _, id in ipairs(ids) do parts[#parts + 1] = ItemPart(id, y.i[id], y.v) end
		local c = self:NodeInfo(name).color
		print(("  |cff%02x%02x%02x%s|r (%s): %s"):format(floor(c[1] * 255), floor(c[2] * 255), floor(c[3] * 255),
			self:NodeLabel(name), Visits(y.v), table.concat(parts, ", ")))
	end
	if session.start then
		local elapsed = time() - session.start
		local ids = {}
		for id in pairs(session.items) do ids[#ids + 1] = id end
		table.sort(ids, function(a, b) return session.items[a] > session.items[b] end)
		local parts = {}
		for i = 1, math.min(3, #ids) do parts[i] = session.items[ids[i]] .. " " .. ItemName(ids[i]) end
		-- an hour's worth of the ore you got most of
		local ore
		for _, id in ipairs(ids) do
			if self:IsOre(id) then ore = id break end
		end
		local took, got = self:FormatTime(max(elapsed, 1)), table.concat(parts, ", ")
		if elapsed >= MIN_SESSION_SEC and ore then
			print("  " .. L["this session: %s in %s: %s, ~%d %s an hour"]:format(Visits(session.visits), took, got,
				floor(session.items[ore] * 3600 / elapsed + 0.5), ItemName(ore)))
		else
			print("  " .. L["this session: %s in %s: %s"]:format(Visits(session.visits), took, got))
		end
	end
end

StaticPopupDialogs.VEINKEEPER_YIELD_RESET = {
	text = L["Forget all VeinKeeper yield counts?"],
	button1 = YES, button2 = NO,
	OnAccept = function()
		wipe(ns.db.yield)
		ns:Print(L["yield counts cleared."])
	end,
	timeout = 0, whileDead = true, hideOnEscape = true,
}
