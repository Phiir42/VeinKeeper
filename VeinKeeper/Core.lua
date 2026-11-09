local ADDON, ns = ...
_G.VeinKeeper = ns

local MERGE_YARDS = 15   -- two mining spots closer than this are the same spawn point
local MULTITAP_SEC = 120 -- re-hitting a vein within this window is the same visit
local floor, sqrt, min, time = math.floor, math.sqrt, math.min, time

local DEFAULTS = {
	worldPins = true,
	minimapPins = true,
	edgeCount = 3,      -- nearest out-of-range spots pinned to the minimap edge
	readyMin = 10,      -- minutes after mining before a spot is shown as "probably back"
	skillDim = true,    -- dim spots above your Mining skill
	gameIcons = true,   -- use the game's ore item icons (false = VeinKeeper's drawn icons)
	inRange = "ring",   -- minimap spots in range while Find Minerals is on: "ring", "hide" or "icon"
	button = true,
	buttonAngle = 215,
	mapButton = true,   -- settings button on the world map
	worldAlpha = 1,     -- world map pin opacity (0.1 - 1)
	minimapAlpha = 1,   -- minimap pin opacity (0.1 - 1)
	worldSize = 18,     -- world map icon size in pixels (before map zoom scaling)
	minimapSize = 14,   -- minimap icon size in pixels
	edgeReadyOnly = true, -- minimap edge arrows only point at spots likely respawned
	only = false,       -- ore filter: an ore item ID (or node name for nodes without one); false = all
}

BINDING_HEADER_VEINKEEPER = "VeinKeeper"
BINDING_NAME_VEINKEEPER_NEXT = "Waypoint to the next respawned spot"
BINDING_NAME_VEINKEEPER_TOGGLE = "Show / hide all pins"
BINDING_NAME_VEINKEEPER_SETTINGS = "Open settings"

---------------------------------------------------------------------------
-- Utilities
---------------------------------------------------------------------------
function ns:Print(msg, ...)
	DEFAULT_CHAT_FRAME:AddMessage("|cffd9a066VeinKeeper|r: " .. (select("#", ...) > 0 and msg:format(...) or msg))
end

local function SpellName(id)
	if C_Spell and C_Spell.GetSpellName then
		local n = C_Spell.GetSpellName(id)
		if n then return n end
	end
	if GetSpellInfo then return (GetSpellInfo(id)) end
end

function ns:FormatTime(sec)
	sec = floor(sec)
	if sec < 60 then return sec .. "s" end
	if sec < 3600 then return floor(sec / 60) .. "m" end
	if sec < 86400 then return ("%dh %dm"):format(sec / 3600, (sec % 3600) / 60) end
	return floor(sec / 86400) .. "d"
end

---------------------------------------------------------------------------
-- Map <-> world coordinates (world coords are yards, valid across zones)
---------------------------------------------------------------------------
local basisCache = {}

-- For a map, the world position of its top-left corner and the world vectors
-- of its east and south edges. Orientation-agnostic, so no axis guessing.
function ns:Basis(mapID)
	local b = basisCache[mapID]
	if b ~= nil then return b or nil end
	b = false
	if mapID and C_Map.GetWorldPosFromMapPos and CreateVector2D then
		local inst, o = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(0, 0))
		local _, e = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(1, 0))
		local _, s = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(0, 1))
		if inst and o and e and s then
			local ox, oy = o:GetXY()
			local ex, ey = e:GetXY()
			local sx, sy = s:GetXY()
			ex, ey, sx, sy = ex - ox, ey - oy, sx - ox, sy - oy
			local w, h = sqrt(ex * ex + ey * ey), sqrt(sx * sx + sy * sy)
			if w > 0 and h > 0 then
				b = { inst = inst, ox = ox, oy = oy, ex = ex, ey = ey, sx = sx, sy = sy, w = w, h = h }
			end
		end
	end
	basisCache[mapID] = b
	return b or nil
end

function ns:MapToWorld(mapID, x, y)
	local b = self:Basis(mapID)
	if not b then return end
	return b.ox + x * b.ex + y * b.sx, b.oy + x * b.ey + y * b.sy, b.inst
end

function ns:WorldToMap(b, wx, wy)
	local dx, dy = wx - b.ox, wy - b.oy
	return (dx * b.ex + dy * b.ey) / (b.w * b.w), (dx * b.sx + dy * b.sy) / (b.h * b.h)
end

-- Yards east and south from point 1 to point 2, using a map's axes.
function ns:Delta(b, wx1, wy1, wx2, wy2)
	local dx, dy = wx2 - wx1, wy2 - wy1
	return (dx * b.ex + dy * b.ey) / b.w, (dx * b.sx + dy * b.sy) / b.h
end

function ns:PlayerMapPos()
	local mapID = C_Map.GetBestMapForUnit("player")
	if not mapID then return end
	local pos = C_Map.GetPlayerMapPosition(mapID, "player")
	if not pos then return end
	local x, y = pos:GetXY()
	if not x or (x == 0 and y == 0) then return end
	return mapID, x, y
end

function ns:PlayerWorld()
	local mapID, x, y = self:PlayerMapPos()
	if not mapID then return end
	local wx, wy, inst = self:MapToWorld(mapID, x, y)
	if not wx then return end
	return wx, wy, inst, self:Basis(mapID)
end

---------------------------------------------------------------------------
-- Spot state
---------------------------------------------------------------------------
local skillRank = 0

-- Collapsed headers hide their skills from GetSkillLineInfo, so expand them
-- for the scan and collapse them again afterwards.
local selfChangeUntil = 0 -- ignore the SKILL_LINES_CHANGED our own expand/collapse fires

local function FindMining(want)
	for j = 1, GetNumSkillLines() do
		local name, isHeader, _, rank = GetSkillLineInfo(j)
		if not isHeader and name == want then return rank or 0 end
	end
end

local function ScanSkill()
	if not GetNumSkillLines or GetTime() < selfChangeUntil then return end
	local want = SpellName(2575) or "Mining"
	local rank = FindMining(want)
	if not rank and ExpandSkillHeader and CollapseSkillHeader then
		selfChangeUntil = GetTime() + 1
		local collapsed = {}
		for i = GetNumSkillLines(), 1, -1 do -- bottom up: expanding shifts later indices
			local _, isHeader, isExpanded = GetSkillLineInfo(i)
			if isHeader and not isExpanded then
				collapsed[#collapsed + 1] = i
				ExpandSkillHeader(i)
			end
		end
		rank = FindMining(want)
		for k = #collapsed, 1, -1 do -- top down again, restoring the user's layout
			CollapseSkillHeader(collapsed[k])
		end
	end
	skillRank = rank or 0
end

function ns:MinSkill(spot)
	local m
	for name in pairs(spot.ores) do
		local s = self:NodeInfo(name).skill or 0
		if not m or s < m then m = s end
	end
	return m or 0
end

function ns:CanMine(spot)
	return not self.db.settings.skillDim or skillRank == 0 or self:MinSkill(spot) <= skillRank
end

-- The ore filter groups nodes by the ore they drop (all Thorium veins together).
function ns:OreKey(name)
	local n = self.NODES[name]
	return n and n.item or name
end

function ns:OreLabel(key)
	if type(key) ~= "number" then return key end
	local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(key)
	if not name and GetItemInfo then name = GetItemInfo(key) end
	if name then return name end
	-- item not cached yet: fall back to the lowest-skill node that drops it
	local best, bestSkill
	for n, info in pairs(self.NODES) do
		if info.item == key and (not bestSkill or info.skill < bestSkill) then best, bestSkill = n, info.skill end
	end
	return best or tostring(key)
end

-- Ores you have saved spots for, lowest skill first: { {key=, label=}, ... }
function ns:FilterChoices()
	local seen, list = {}, {}
	for _, s in ipairs(self.db.spots) do
		for name in pairs(s.ores) do
			local key = self:OreKey(name)
			if not seen[key] and not self.db.ignore[name] then
				seen[key] = true
				list[#list + 1] = { key = key, label = self:OreLabel(key), skill = self:NodeInfo(name).skill or 0 }
			end
		end
	end
	table.sort(list, function(a, b)
		if a.skill ~= b.skill then return a.skill < b.skill end
		return a.label < b.label
	end)
	return list
end

local function Passes(self, name)
	if self.db.ignore[name] then return false end
	local only = self.db.settings.only
	return not only or self:OreKey(name) == only
end

-- A spot is hidden when no ore seen there passes the ignore list and ore filter.
function ns:IsShown(spot)
	if not self.db.settings.only and not next(self.db.ignore) then return true end
	for name in pairs(spot.ores) do
		if Passes(self, name) then return true end
	end
	return false
end

-- The ore a pin should show: the last one mined, unless it's filtered out.
function ns:DisplayOre(spot)
	if Passes(self, spot.lastOre) then return spot.lastOre end
	for name in pairs(spot.ores) do
		if Passes(self, name) then return name end
	end
	return spot.lastOre
end

-- Case-insensitive lookup of a node name the user typed.
function ns:ResolveNodeName(text)
	local lower = text:lower()
	for name in pairs(self.NODES) do
		if name:lower() == lower then return name end
	end
	for _, s in ipairs(self.db.spots) do
		for name in pairs(s.ores) do
			if name:lower() == lower then return name end
		end
	end
	for name in pairs(self.db.ignore) do
		if name:lower() == lower then return name end
	end
end

-- r, g, b, ready: red right after mining, fading to yellow, green once ready.
function ns:Freshness(spot)
	local elapsed = time() - spot.last
	local ready = self.db.settings.readyMin * 60
	if elapsed >= ready then return 0.2, 1, 0.2, true end
	local t = elapsed / ready
	return 1, 0.25 + 0.65 * t, 0.15, false
end

function ns:Distance(spot)
	if not spot.wx then return end
	local wx, wy, inst = self:PlayerWorld()
	if not wx or inst ~= spot.inst then return end
	local dx, dy = spot.wx - wx, spot.wy - wy
	return sqrt(dx * dx + dy * dy)
end

function ns:ShowTooltip(owner, spot)
	if not spot then return end
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	local info = self:NodeInfo(self:DisplayOre(spot))
	GameTooltip:AddLine(self:DisplayOre(spot), info.color[1], info.color[2], info.color[3])
	local r, g, b, ready = self:Freshness(spot)
	local ago = self:FormatTime(time() - spot.last)
	GameTooltip:AddDoubleLine("Last mined", ago .. " ago", 1, 1, 1, r, g, b)
	if not ready then
		local left = self.db.settings.readyMin * 60 - (time() - spot.last)
		GameTooltip:AddDoubleLine("Likely back in", self:FormatTime(left), 1, 1, 1, r, g, b)
	end
	if spot.minGap then
		GameTooltip:AddDoubleLine("Fastest respawn seen", "<= " ..self:FormatTime(spot.minGap), 1, 1, 1, 0.8, 0.8, 0.8)
	end
	GameTooltip:AddDoubleLine("Visits / taps", spot.visits .. " / " .. spot.taps, 1, 1, 1, 0.8, 0.8, 0.8)
	local d = self:Distance(spot)
	if d then GameTooltip:AddDoubleLine("Distance", floor(d) .. " yd", 1, 1, 1, 0.8, 0.8, 0.8) end
	local n = 0
	for _ in pairs(spot.ores) do n = n + 1 end
	if n > 1 then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("Ores seen here:", 1, 0.82, 0)
		for name, count in pairs(spot.ores) do
			local c = self:NodeInfo(name).color
			GameTooltip:AddDoubleLine(name, count .. "x", c[1], c[2], c[3], 0.8, 0.8, 0.8)
		end
	end
	if not self:CanMine(spot) then
		GameTooltip:AddLine(("Needs Mining %d (you have %d)"):format(self:MinSkill(spot), skillRank), 1, 0.3, 0.3)
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("Shift + right-click: forget this spot", 0.6, 0.6, 0.6)
	GameTooltip:Show()
end

---------------------------------------------------------------------------
-- Change notification (map/minimap modules register listeners)
---------------------------------------------------------------------------
ns.listeners = {}
function ns:Changed()
	for _, fn in ipairs(self.listeners) do fn() end
end

function ns:ToggleAllPins()
	local s = self.db.settings
	local on = not (s.worldPins or s.minimapPins)
	s.worldPins, s.minimapPins = on, on
	self:Print("pins %s.", on and "on" or "off")
	self:Changed()
end

function ns:Forget(spot)
	for i, s in ipairs(self.db.spots) do
		if s == spot then
			table.remove(self.db.spots, i)
			self:Changed()
			return true
		end
	end
end

---------------------------------------------------------------------------
-- Next spot: waypoint to the nearest spot that has likely respawned.
-- Calling it while standing at a "ready" spot means it wasn't there (if it
-- were, you'd mine it), so that spot is skipped for one respawn timer.
---------------------------------------------------------------------------
local checked = {} -- spot -> time() it was found empty this session
local AT_SPOT_YARDS = 40

function ns:Next()
	local wx, wy, inst = self:PlayerWorld()
	if not wx then self:Print("no position here.") return end
	local readySec = self.db.settings.readyMin * 60
	local now = time()
	local best, bestD, soon
	for _, s in ipairs(self.db.spots) do
		if s.wx and s.inst == inst and self:IsShown(s) and self:CanMine(s) then
			local dx, dy = s.wx - wx, s.wy - wy
			local d = sqrt(dx * dx + dy * dy)
			local wait = readySec - (now - s.last)
			if checked[s] then wait = math.max(wait, readySec - (now - checked[s])) end
			if wait <= 0 and d < AT_SPOT_YARDS then
				checked[s] = now -- standing here and it's not up
				wait = readySec
			end
			if wait <= 0 then
				if not bestD or d < bestD then best, bestD = s, d end
			elseif not soon or wait < soon then
				soon = wait
			end
		end
	end
	if best then
		self:SetWaypoint(best)
		self:Print("next: %s, %d yd.", self:DisplayOre(best), floor(bestD))
	elseif soon then
		self:Print("nothing likely up here yet; the soonest is back in %s.", self:FormatTime(soon))
	else
		self:Print("no saved spots you can mine on this continent.")
	end
end

---------------------------------------------------------------------------
-- Prune: drop spots visited only once and not seen for a while (positions
-- logged by mistake, or one-off spawns).
---------------------------------------------------------------------------
local function PruneList(days)
	local cutoff = time() - days * 86400
	local list = {}
	for i, s in ipairs(ns.db.spots) do
		if s.visits <= 1 and s.last < cutoff then list[#list + 1] = i end
	end
	return list
end

function ns:Prune(days)
	local n = #PruneList(days)
	if n == 0 then
		self:Print("nothing to prune: no single-visit spots older than %d days.", days)
		return
	end
	StaticPopup_Show("VEINKEEPER_PRUNE", n, days, { days = days })
end

StaticPopupDialogs["VEINKEEPER_PRUNE"] = {
	text = "Delete %d spots you've visited only once, more than %d days ago?",
	button1 = YES, button2 = NO,
	OnAccept = function(_, data)
		local list = PruneList(data.days)
		for k = #list, 1, -1 do table.remove(ns.db.spots, list[k]) end
		ns:Changed()
		ns:Print("pruned %d spots.", #list)
	end,
	timeout = 0, whileDead = true, hideOnEscape = true,
}

---------------------------------------------------------------------------
-- Recording
---------------------------------------------------------------------------
function ns:Record(name)
	local db = self.db
	if db.ignore[name] then return end
	local mapID, x, y = self:PlayerMapPos()
	if not mapID then return end -- instances have no map position
	local wx, wy, inst = self:MapToWorld(mapID, x, y)
	local now = time()

	-- find the closest existing spot (any ore: shared spawn points like Tin/Silver merge)
	local best, bestD = nil, MERGE_YARDS
	for _, s in ipairs(db.spots) do
		local d
		if wx and s.wx and s.inst == inst then
			local dx, dy = s.wx - wx, s.wy - wy
			d = sqrt(dx * dx + dy * dy)
		elseif s.map == mapID then
			-- rough fallback without world coords: assume a small (1000 yd) zone so
			-- distinct veins aren't merged; worst case is a duplicate pin
			local dx, dy = (s.x - x) * 1000, (s.y - y) * 1000
			d = sqrt(dx * dx + dy * dy)
		end
		if d and d < bestD then best, bestD = s, d end
	end

	if best then
		local gap = now - best.last
		if gap > MULTITAP_SEC then
			best.visits = best.visits + 1
			best.ores[name] = (best.ores[name] or 0) + 1
			best.minGap = best.minGap and min(best.minGap, gap) or gap
		elseif not best.ores[name] then
			best.ores[name] = 1
		end
		best.taps = best.taps + 1
		best.last = now
		best.lastOre = name
		-- average the position over the first few same-map visits: you never stand in the same place twice
		if gap > MULTITAP_SEC and best.map == mapID then
			local n = (best.posN or 1) + 1
			if n <= 6 then
				best.posN = n
				best.x = best.x + (x - best.x) / n
				best.y = best.y + (y - best.y) / n
				best.wx, best.wy, best.inst = self:MapToWorld(mapID, best.x, best.y)
			end
		end
		-- a spot saved without world coords gets them as soon as they're available
		if not best.wx and wx and best.map == mapID then
			best.wx, best.wy, best.inst = self:MapToWorld(mapID, best.x, best.y)
		end
	else
		db.spots[#db.spots + 1] = {
			map = mapID, x = x, y = y, wx = wx, wy = wy, inst = inst,
			ores = { [name] = 1 }, lastOre = name,
			first = now, last = now, visits = 1, taps = 1,
		}
		if not db.seenNote then
			db.seenNote = true
			self:Print("saved your first vein (%s). Type /vk for options.", name)
		end
	end
	self:Changed()
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local MINING
local pendingCast, pendingTarget

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("SKILL_LINES_CHANGED")
f:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
f:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
f:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
f:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")

f:SetScript("OnEvent", function(_, event, ...)
	if event == "ADDON_LOADED" then
		if ... ~= ADDON then return end
		VeinKeeperDB = VeinKeeperDB or {}
		local db = VeinKeeperDB
		db.spots = db.spots or {}
		db.ignore = db.ignore or {}
		db.settings = db.settings or {}
		for k, v in pairs(DEFAULTS) do
			if db.settings[k] == nil then db.settings[k] = v end
		end
		ns.db = db
		-- Create the minimap button now rather than at login: minimap button
		-- collectors (EllesmereUI rescans 0.1s after every ADDON_LOADED) then
		-- find it on their next scan.
		if ns.UpdateMinimapButton then ns:UpdateMinimapButton() end
	elseif event == "PLAYER_LOGIN" then
		MINING = SpellName(2575) or "Mining"
		ScanSkill()
		if ns.OnLogin then ns:OnLogin() end
	elseif event == "SKILL_LINES_CHANGED" then
		ScanSkill()
	elseif event == "UNIT_SPELLCAST_SENT" then
		local _, target, castGUID, spellID = ...
		if spellID and SpellName(spellID) == MINING then
			if not target or target == "" then
				-- fallback: the node under the cursor, but only if it's a known node name
				local t = GameTooltip:IsShown() and GameTooltipTextLeft1 and GameTooltipTextLeft1:GetText()
				target = t and ns.NODES[t] and t or nil
			end
			if target and target ~= "" then
				pendingCast, pendingTarget = castGUID, target
			end
		end
	elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
		local _, castGUID = ...
		if pendingCast and castGUID == pendingCast then
			local target = pendingTarget
			pendingCast, pendingTarget = nil, nil
			ns:Record(target)
		end
	else -- failed / interrupted
		local _, castGUID = ...
		if castGUID == pendingCast then pendingCast, pendingTarget = nil, nil end
	end
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
local function Help()
	local s = ns.db.settings
	local on = function(v) return v and "|cff40ff40on|r" or "|cffff4040off|r" end
	ns:Print("%d spots saved.", #ns.db.spots)
	print("  /vk - open the settings window (also on the minimap and world map buttons)")
	print("  /vk map - world map pins " .. on(s.worldPins))
	print("  /vk minimap - minimap pins " .. on(s.minimapPins))
	print("  /vk edge <0-10> - nearest far spots on minimap edge (" .. s.edgeCount .. ")")
	print("  /vk ready <minutes> - when a spot counts as respawned (" .. s.readyMin .. ")")
	print("  /vk skill - dim spots above your Mining skill " .. on(s.skillDim))
	print("  /vk icons - game ore icons " .. on(s.gameIcons) .. " (off = drawn icons)")
	print("  /vk inrange ring|hide|icon - nearby spots while Find Minerals is on (" .. s.inRange .. ")")
	print("  /vk button - minimap button " .. on(s.button))
	print("  /vk next - waypoint to the nearest spot that's likely back (bind a key: Key Bindings > AddOns)")
	print("  /vk near - list the closest saved spots")
	print("  /vk only <ore or node> | /vk only all - show just one ore (" .. (s.only and ns:OreLabel(s.only) or "all") .. ")")
	print("  /vk ignore <Node Name> | /vk unignore <Node Name> | /vk ignore")
	print("  /vk prune [days] - delete spots visited once, over [30] days ago")
	print("  /vk clear zone | /vk clear all")
end

local function Near()
	local wx, wy, inst = ns:PlayerWorld()
	if not wx then ns:Print("no position here.") return end
	local list = {}
	for _, s in ipairs(ns.db.spots) do
		if s.wx and s.inst == inst and ns:IsShown(s) then
			local dx, dy = s.wx - wx, s.wy - wy
			list[#list + 1] = { s = s, d = sqrt(dx * dx + dy * dy) }
		end
	end
	table.sort(list, function(a, b) return a.d < b.d end)
	if #list == 0 then ns:Print("no saved spots nearby.") return end
	for i = 1, min(5, #list) do
		local s = list[i].s
		local _, _, _, ready = ns:Freshness(s)
		print(("  %s - %d yd - %s"):format(ns:DisplayOre(s), floor(list[i].d),
			ready and "|cff40ff40likely up|r" or ("mined " .. ns:FormatTime(time() - s.last) .. " ago")))
	end
end

SLASH_VEINKEEPER1, SLASH_VEINKEEPER2 = "/vk", "/veinkeeper"
SlashCmdList.VEINKEEPER = function(msg)
	local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
	cmd = cmd:lower()
	local s = ns.db.settings
	if cmd == "" then
		return ns:ToggleSettings()
	elseif cmd == "help" then
		return Help()
	elseif cmd == "map" then
		s.worldPins = not s.worldPins
	elseif cmd == "minimap" then
		s.minimapPins = not s.minimapPins
	elseif cmd == "edge" and tonumber(rest) then
		s.edgeCount = math.max(0, math.min(10, floor(tonumber(rest))))
	elseif cmd == "ready" and tonumber(rest) then
		s.readyMin = math.max(1, math.min(1440, floor(tonumber(rest))))
	elseif cmd == "skill" then
		s.skillDim = not s.skillDim
	elseif cmd == "icons" then
		s.gameIcons = not s.gameIcons
	elseif cmd == "inrange" and (rest == "ring" or rest == "hide" or rest == "icon") then
		s.inRange = rest
	elseif cmd == "button" then
		s.button = not s.button
		ns:UpdateMinimapButton()
	elseif cmd == "near" then
		return Near()
	elseif cmd == "next" then
		return ns:Next()
	elseif cmd == "prune" then
		return ns:Prune(math.max(1, floor(tonumber(rest) or 30)))
	elseif cmd == "only" and rest ~= "" then
		local lower = rest:lower()
		if lower == "all" then
			s.only = false
		else
			local key
			local name = ns:ResolveNodeName(rest)
			if name then key = ns:OreKey(name) end
			for _, c in ipairs(ns:FilterChoices()) do
				if not key and c.label:lower():find(lower, 1, true) then key = c.key end
			end
			if not key then ns:Print("no saved spots for \"%s\".", rest) return end
			s.only = key
		end
		ns:Print("showing %s.", s.only and ns:OreLabel(s.only) or "all ores")
		ns:Changed()
		return
	elseif (cmd == "ignore" or cmd == "unignore") and rest ~= "" then
		-- ignoring is a filter: nothing is deleted, so unignore brings the pins back
		local name = ns:ResolveNodeName(rest)
		if not name then
			ns:Print("unknown node \"%s\". Use the full name, e.g. /vk ignore Copper Vein", rest)
			return
		end
		ns.db.ignore[name] = (cmd == "ignore") or nil
		ns:Print(cmd == "ignore" and "ignoring %s: not recorded, pins hidden." or "showing and recording %s again.", name)
	elseif cmd == "ignore" then
		local names = {}
		for k in pairs(ns.db.ignore) do names[#names + 1] = k end
		table.sort(names)
		ns:Print("ignored: %s", #names > 0 and table.concat(names, ", ") or "none")
		return
	elseif cmd == "clear" and rest == "zone" then
		local mapID = C_Map.GetBestMapForUnit("player")
		local n = 0
		for i = #ns.db.spots, 1, -1 do
			if ns.db.spots[i].map == mapID then table.remove(ns.db.spots, i) n = n + 1 end
		end
		ns:Print("removed %d spots in this zone.", n)
	elseif cmd == "clear" and rest == "all" then
		StaticPopup_Show("VEINKEEPER_CLEAR_ALL")
		return
	else
		return Help()
	end
	ns:Changed()
	if cmd ~= "ignore" and cmd ~= "unignore" and cmd ~= "clear" then Help() end
end

StaticPopupDialogs["VEINKEEPER_CLEAR_ALL"] = {
	text = "Delete all saved VeinKeeper spots?",
	button1 = YES, button2 = NO,
	OnAccept = function()
		wipe(ns.db.spots)
		ns:Changed()
		ns:Print("all spots deleted.")
	end,
	timeout = 0, whileDead = true, hideOnEscape = true,
}
