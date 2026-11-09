-- Spots: the saved veins, which ones are shown, respawn timing and recording.
--
-- A spot (VeinKeeperDB.spots[i]):
--   map, x, y      zone map ID and 0-1 position (used for waypoints)
--   wx, wy, inst   world position in yards and continent (nil when unavailable)
--   ores           node name -> times mined there (0 = only seen on the minimap)
--   lastOre        the node name the pin shows
--   first, last    time() first saved / last mined (last is nil if never mined)
--   seenAt         time() its Find Minerals dot was last hovered
--   visits, taps   separate visits / total mining casts
--   minGap         shortest time between two visits: an upper bound on respawn
--   posN           how many visits are averaged into the position
local _, ns = ...

local MERGE_YARDS = 15   -- spots closer than this are the same spawn point
local MULTITAP_SEC = 120 -- re-mining within this window is the same visit
local AT_SPOT_YARDS = 40 -- "standing at the spot" for /vk next
local floor, sqrt, min, max, time = math.floor, math.sqrt, math.min, math.max, time

---------------------------------------------------------------------------
-- Mining skill (for dimming spots you can't mine yet)
---------------------------------------------------------------------------
local skillRank = 0

local function FindRank(skillName)
	for i = 1, GetNumSkillLines() do
		local name, isHeader, _, rank = GetSkillLineInfo(i)
		if not isHeader and name == skillName then return rank or 0 end
	end
end

-- Collapsed headers hide their skills. Expanding them (and collapsing them
-- again) is only done on the occasions Mining can appear or rise: login,
-- spellbook changes, and after mining. Every other SKILL_LINES_CHANGED (weapon
-- skill-ups fire it constantly) only reads the visible lines.
local function ScanSkill(expand)
	if not GetNumSkillLines then return end
	local skillName = ns:SpellName(2575) or "Mining"
	local rank = FindRank(skillName)
	if not rank and not expand then return end
	if not rank and ExpandSkillHeader and CollapseSkillHeader then
		local collapsed = {}
		for i = GetNumSkillLines(), 1, -1 do -- bottom up: expanding shifts later indices
			local _, isHeader, isExpanded = GetSkillLineInfo(i)
			if isHeader and not isExpanded then
				collapsed[#collapsed + 1] = i
				ExpandSkillHeader(i)
			end
		end
		rank = FindRank(skillName)
		for k = #collapsed, 1, -1 do CollapseSkillHeader(collapsed[k]) end
	end
	rank = rank or 0
	if rank ~= skillRank then
		skillRank = rank
		if ns.db then ns:Restyle() end
	end
end
local function FullScan() ScanSkill(true) end
ns:On("PLAYER_LOGIN", FullScan)
ns:On("SPELLS_CHANGED", FullScan) -- learning Mining (not a combat event)
ns:On("SKILL_LINES_CHANGED", function() ScanSkill(false) end)

function ns:SkillRank() return skillRank end

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

---------------------------------------------------------------------------
-- Ignore list and ore filter. The filter groups nodes by the ore they drop,
-- so "Thorium Ore" covers small, rich, ooze and Hakkari veins.
---------------------------------------------------------------------------
function ns:OreKey(name)
	local n = self.NODES[name]
	return n and n.item or name
end

function ns:OreLabel(key)
	if type(key) ~= "number" then return key end
	local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(key)
	if not name and GetItemInfo then name = GetItemInfo(key) end
	if name then return name end
	-- item not cached yet: name it after the lowest-skill node that drops it
	local best, bestSkill
	for n, info in pairs(self.NODES) do
		if info.item == key and (not bestSkill or info.skill < bestSkill) then best, bestSkill = n, info.skill end
	end
	return best or tostring(key)
end

-- Ores you have spots for, lowest skill first: { { key =, label = }, ... }
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

local function Passes(name)
	if ns.db.ignore[name] then return false end
	local only = ns.db.settings.only
	return not only or ns:OreKey(name) == only
end

-- Hidden when no ore seen at the spot passes the ignore list and filter.
function ns:IsShown(spot)
	if not self.db.settings.only and not next(self.db.ignore) then return true end
	for name in pairs(spot.ores) do
		if Passes(name) then return true end
	end
	return false
end

-- The ore a pin shows: the last one mined, unless it's filtered out.
function ns:DisplayOre(spot)
	if Passes(spot.lastOre) then return spot.lastOre end
	for name in pairs(spot.ores) do
		if Passes(name) then return name end
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

---------------------------------------------------------------------------
-- Respawn timing
---------------------------------------------------------------------------
-- Its dot was seen on the minimap since it was last mined.
local function SeenUp(spot)
	return spot.seenAt ~= nil and (not spot.last or spot.seenAt > spot.last)
end
function ns:SeenUp(spot) return SeenUp(spot) end

-- Seconds until the spot is likely back (<= 0: likely up now). A vein seen
-- on the minimap since it was last mined counts as up.
function ns:Wait(spot)
	if SeenUp(spot) then return 0 end
	return self.db.settings.readyMin * 60 - (time() - spot.last)
end

-- r, g, b, ready. Red right after mining, fading to yellow, then green;
-- blue for a spot only ever seen on the minimap.
function ns:Freshness(spot)
	local wait = self:Wait(spot)
	if wait <= 0 then
		if not spot.last then return 0.35, 0.7, 1, true end
		return 0.2, 1, 0.2, true
	end
	local t = 1 - wait / (self.db.settings.readyMin * 60)
	return 1, 0.25 + 0.65 * t, 0.15, false
end

---------------------------------------------------------------------------
-- Recording
---------------------------------------------------------------------------
-- The saved spot within MERGE_YARDS of a position, if any. Any ore matches,
-- so shared spawn points (Tin/Silver, Mithril/Truesilver) become one spot.
local function Closest(wx, wy, inst, mapID, x, y)
	local best, bestD = nil, MERGE_YARDS
	for _, s in ipairs(ns.db.spots) do
		local d
		if wx and s.wx and s.inst == inst then
			local dx, dy = s.wx - wx, s.wy - wy
			d = sqrt(dx * dx + dy * dy)
		elseif s.map == mapID then
			-- no world coords: assume a small (1000 yd) zone, so distinct veins
			-- aren't merged; the worst case is a duplicate pin
			local dx, dy = (s.x - x) * 1000, (s.y - y) * 1000
			d = sqrt(dx * dx + dy * dy)
		end
		if d and d < bestD then best, bestD = s, d end
	end
	return best
end

local function NewSpot(mapID, x, y, wx, wy, inst, name, mined, now)
	local db = ns.db
	db.spots[#db.spots + 1] = {
		map = mapID, x = x, y = y, wx = wx, wy = wy, inst = inst,
		ores = { [name] = mined and 1 or 0 }, lastOre = name, first = now,
		last = mined and now or nil, seenAt = not mined and now or nil,
		visits = mined and 1 or 0, taps = mined and 1 or 0,
	}
	if mined and not db.seenNote then
		db.seenNote = true
		ns:Print("saved your first vein (%s). Type /vk for options.", name)
	end
end

-- You just mined `name` where you stand.
function ns:Record(name)
	if self.db.ignore[name] then return end
	local mapID, x, y = self:PlayerMapPos()
	if not mapID then return end -- instances have no map position
	local wx, wy, inst = self:MapToWorld(mapID, x, y)
	local now = time()
	local spot = Closest(wx, wy, inst, mapID, x, y)
	if not spot then
		NewSpot(mapID, x, y, wx, wy, inst, name, true, now)
		return self:Changed()
	end

	local gap = now - (spot.last or 0)
	local newVisit = gap > MULTITAP_SEC
	if newVisit then
		spot.visits = spot.visits + 1
		spot.ores[name] = (spot.ores[name] or 0) + 1
		if spot.last then spot.minGap = spot.minGap and min(spot.minGap, gap) or gap end
	elseif not spot.ores[name] then
		spot.ores[name] = 1
	end
	spot.taps = spot.taps + 1
	spot.last = now
	spot.lastOre = name
	-- average the position over the first few visits: you never stand in the same place twice
	if newVisit and spot.map == mapID then
		local n = (spot.posN or 1) + 1
		if n <= 6 then
			spot.posN = n
			spot.x = spot.x + (x - spot.x) / n
			spot.y = spot.y + (y - spot.y) / n
		end
	end
	if spot.map == mapID and (newVisit or not spot.wx) then
		spot.wx, spot.wy, spot.inst = self:MapToWorld(mapID, spot.x, spot.y)
	end
	self:Changed()
end

-- A Find Minerals dot for `name` was hovered at this position: mark the spot
-- there as up, or save a new "seen" spot. Seeing a vein is not a visit.
function ns:RecordSeen(name, wx, wy, inst, mapID, x, y)
	if self.db.ignore[name] then return end
	local now = time()
	local spot = Closest(wx, wy, inst, mapID, x, y)
	if not spot then
		NewSpot(mapID, x, y, wx, wy, inst, name, false, now)
		return self:Changed()
	end
	-- right after mining, the dot can linger a moment: that isn't "up"
	if spot.last and now - spot.last < MULTITAP_SEC then return end
	local wasUp = SeenUp(spot)
	spot.seenAt = now
	if not spot.ores[name] then
		spot.ores[name] = 0
		if not spot.last then spot.lastOre = name end
		return self:Changed()
	end
	if not wasUp then self:Restyle() end
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

-- Remove every spot for which drop(spot) is true; returns how many went.
function ns:RemoveSpots(drop)
	local spots, n, kept = self.db.spots, 0, 0
	for i = 1, #spots do
		local s = spots[i]
		spots[i] = nil
		if drop(s) then
			n = n + 1
		else
			kept = kept + 1
			spots[kept] = s
		end
	end
	if n > 0 then self:Changed() end
	return n
end

---------------------------------------------------------------------------
-- Mining detection: a successful cast of Mining on a named node.
---------------------------------------------------------------------------
local MINING
local pendingCast, pendingTarget

ns:On("PLAYER_LOGIN", function() MINING = ns:SpellName(2575) or "Mining" end)

ns:On("UNIT_SPELLCAST_SENT", function(_, target, castGUID, spellID)
	if not spellID or ns:SpellName(spellID) ~= MINING then return end
	if not target or target == "" then
		-- fallback: the node under the cursor, but only a known node name
		local t = GameTooltip:IsShown() and GameTooltipTextLeft1:GetText()
		target = t and ns.NODES[t] and t or nil
	end
	if target then pendingCast, pendingTarget = castGUID, target end
end, "player")

ns:On("UNIT_SPELLCAST_SUCCEEDED", function(_, castGUID)
	if pendingCast and castGUID == pendingCast then
		local target = pendingTarget
		pendingCast, pendingTarget = nil, nil
		ns:Record(target)
		C_Timer.After(1, FullScan) -- the skill may have gone up
	end
end, "player")

local function CastEnded(_, castGUID)
	if castGUID == pendingCast then pendingCast, pendingTarget = nil, nil end
end
ns:On("UNIT_SPELLCAST_FAILED", CastEnded, "player")
ns:On("UNIT_SPELLCAST_INTERRUPTED", CastEnded, "player")

---------------------------------------------------------------------------
-- Next spot: waypoint to the nearest spot likely back. Asking while standing
-- at a "ready" spot means it wasn't there (else you'd be mining it), so that
-- spot is skipped for one respawn timer.
---------------------------------------------------------------------------
local checked = {} -- spot -> time() found empty, this session only

function ns:Next()
	local wx, wy, inst = self:PlayerWorld()
	if not wx then return self:Print("no position here.") end
	local readySec = self.db.settings.readyMin * 60
	local now = time()
	local best, bestD, soonest
	for _, s in ipairs(self.db.spots) do
		if s.wx and s.inst == inst and self:IsShown(s) and self:CanMine(s) then
			local dx, dy = s.wx - wx, s.wy - wy
			local d = sqrt(dx * dx + dy * dy)
			local wait = self:Wait(s)
			if checked[s] then wait = max(wait, readySec - (now - checked[s])) end
			if wait <= 0 and d < AT_SPOT_YARDS then
				checked[s] = now
				wait = readySec
			end
			if wait <= 0 then
				if not bestD or d < bestD then best, bestD = s, d end
			elseif not soonest or wait < soonest then
				soonest = wait
			end
		end
	end
	if best then
		self:SetWaypoint(best)
		self:Print("next: %s, %d yd.", self:DisplayOre(best), floor(bestD))
	elseif soonest then
		self:Print("nothing likely up yet; the soonest is back in %s.", self:FormatTime(soonest))
	else
		self:Print("no saved spots you can mine on this continent.")
	end
end

---------------------------------------------------------------------------
-- Prune: spots visited at most once and not seen for `days` (positions
-- logged by mistake, one-off spawns).
---------------------------------------------------------------------------
local function Stale(days)
	local cutoff = time() - days * 86400
	return function(s) return s.visits <= 1 and max(s.last or 0, s.seenAt or 0) < cutoff end
end

function ns:Prune(days)
	local stale, n = Stale(days), 0
	for _, s in ipairs(self.db.spots) do
		if stale(s) then n = n + 1 end
	end
	if n == 0 then
		return self:Print("nothing to prune: no single-visit spots older than %d days.", days)
	end
	StaticPopup_Show("VEINKEEPER_PRUNE", n, days, days)
end

StaticPopupDialogs.VEINKEEPER_PRUNE = {
	text = "Delete %d spots you've visited only once, more than %d days ago?",
	button1 = YES, button2 = NO,
	OnAccept = function(_, days) ns:Print("pruned %d spots.", ns:RemoveSpots(Stale(days))) end,
	timeout = 0, whileDead = true, hideOnEscape = true,
}
