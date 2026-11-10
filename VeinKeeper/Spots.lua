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
--   gx, gy, gN     the average of where you stood to mine, over gN visits
--   hx, hy, hErr   the Find Minerals hover estimate and yards it may be off
--                  (x, y combines the two, weighted by accuracy: see Settle)
local _, ns = ...

local MERGE_YARDS = 15   -- spots closer than this are the same spawn point
local MULTITAP_SEC = 120 -- without node GUIDs: re-mining within this window is the same visit
local OTHER_NODE_SEC = 120 -- another node GUID mined here this soon is a neighbouring
                           -- vein; later it may be this vein respawned (a new GUID)
local AT_SPOT_YARDS = 40 -- "standing at the spot" for /vk next
local SEEN_REACH = 60    -- most two hovers of the same vein can be apart (zoomed out)
local ADOPT_REACH = 40   -- mining takes over a hovered spot of that ore this close
local STAND_YARDS = 4    -- how far from a vein you typically stand to mine it
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
-- The saved spot a position belongs to, if any. Within MERGE_YARDS any ore
-- matches, so shared spawn points (Tin/Silver, Mithril/Truesilver) become one
-- spot. Up to `reach` yards, only spots that have this ore and pass `accept`:
-- hovered positions are rough, so they get a wider net.
local function Closest(wx, wy, inst, mapID, x, y, name, reach, accept, skip)
	local best, bestD = nil, max(MERGE_YARDS, reach or 0)
	for _, s in ipairs(ns.db.spots) do
		local d
		if skip and skip(s) then
			-- ruled out
		elseif wx and s.wx and s.inst == inst then
			local dx, dy = s.wx - wx, s.wy - wy
			d = sqrt(dx * dx + dy * dy)
		elseif s.map == mapID then
			-- no world coords: assume a small (1000 yd) zone, so distinct veins
			-- aren't merged; the worst case is a duplicate pin
			local dx, dy = (s.x - x) * 1000, (s.y - y) * 1000
			d = sqrt(dx * dx + dy * dy)
		end
		if d and d < bestD
			and (d < MERGE_YARDS or (s.ores[name] and (not accept or accept(s)))) then
			best, bestD = s, d
		end
	end
	return best, bestD
end

---------------------------------------------------------------------------
-- Position: two running averages, each closing in on the vein.
--  - Gathers: where you stood, every visit. You come at a vein from
--    different sides, so the average approaches the vein as visits add up.
--  - Hovers: the cursor resting on the vein's Find Minerals dot.
-- The pin sits between them, weighted by how much each has seen.
---------------------------------------------------------------------------
local function Settle(spot)
	local gw = spot.gN and spot.gN / (STAND_YARDS * STAND_YARDS) or 0
	local hw = spot.hErr and 1 / (spot.hErr * spot.hErr) or 0
	if gw + hw == 0 then return end
	spot.x = ((spot.gx or 0) * gw + (spot.hx or 0) * hw) / (gw + hw)
	spot.y = ((spot.gy or 0) * gw + (spot.hy or 0) * hw) / (gw + hw)
	spot.wx, spot.wy, spot.inst = ns:MapToWorld(spot.map, spot.x, spot.y)
end

local function AddGather(spot, x, y)
	local n = (spot.gN or 0) + 1
	spot.gx = spot.gx and spot.gx + (x - spot.gx) / n or x
	spot.gy = spot.gy and spot.gy + (y - spot.gy) / n or y
	spot.gN = n
	Settle(spot)
end

-- A hover at x, y, at most `err` yards off: averaged in, the more precise
-- one counting for more.
local function AddHover(spot, x, y, err)
	err = max(1, err)
	if spot.hErr then
		local a, b = 1 / (spot.hErr * spot.hErr), 1 / (err * err)
		spot.hx = (spot.hx * a + x * b) / (a + b)
		spot.hy = (spot.hy * a + y * b) / (a + b)
		spot.hErr = max(1, 1 / sqrt(a + b))
	else
		spot.hx, spot.hy, spot.hErr = x, y, err
	end
	Settle(spot)
end

local function NeverMined(s) return not s.last end

local function NewSpot(mapID, x, y, wx, wy, inst, name, mined, now)
	local db = ns.db
	db.spots[#db.spots + 1] = {
		map = mapID, x = x, y = y, wx = wx, wy = wy, inst = inst,
		ores = { [name] = mined and 1 or 0 }, lastOre = name, first = now,
		last = mined and now or nil, seenAt = not mined and now or nil,
		visits = mined and 1 or 0, taps = mined and 1 or 0,
		gx = mined and x or nil, gy = mined and y or nil, gN = mined and 1 or nil,
	}
	if mined and not db.seenNote then
		db.seenNote = true
		ns:Print("saved your first vein (%s). Type /vk for options.", name)
	end
end

-- The node GUID last mined at each spot this session. A node keeps its GUID
-- until it despawns, so it tells a multi-tap vein (same GUID) from a
-- neighbouring vein a few yards away (another GUID).
local nodeAt = setmetatable({}, { __mode = "k" })

local function FindNode(guid)
	for spot, g in pairs(nodeAt) do
		if g == guid then return spot end
	end
end

local Absorb -- below

-- You just mined `name` where you stand; `guid` is the node's, if known.
function ns:Record(name, guid)
	if self.db.ignore[name] then return end
	local mapID, x, y = self:PlayerMapPos()
	if not mapID then return end -- instances have no map position
	local wx, wy, inst = self:MapToWorld(mapID, x, y)
	local now = time()
	local spot = guid and FindNode(guid)
	if not spot then
		-- a spot whose node, mined moments ago, had another GUID is a
		-- different vein: that one can't have respawned yet
		local function Other(s)
			return guid and nodeAt[s] and nodeAt[s] ~= guid and now - (s.last or 0) < OTHER_NODE_SEC
		end
		-- a spot only seen on the minimap may be off by its hover error
		spot = Closest(wx, wy, inst, mapID, x, y, name, ADOPT_REACH, NeverMined, Other)
	end
	if not spot then
		NewSpot(mapID, x, y, wx, wy, inst, name, true, now)
		local new = self.db.spots[#self.db.spots]
		if guid then nodeAt[new] = guid end
		Absorb(new, MERGE_YARDS)
		return self:Changed()
	end

	local firstMine = not spot.last
	local gap = now - (spot.last or 0)
	local newVisit
	if guid and nodeAt[spot] then
		newVisit = nodeAt[spot] ~= guid
	else
		newVisit = gap > MULTITAP_SEC
	end
	if guid then nodeAt[spot] = guid end
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
	if firstMine and spot.map ~= mapID then
		-- a hovered spot saved on another zone's map: start over on this one
		spot.map, spot.hx, spot.hy, spot.hErr = mapID, nil, nil, nil
	end
	-- every visit (not every tap of a multi-tap vein) adds to the average
	if spot.map == mapID and (newVisit or firstMine) then AddGather(spot, x, y) end
	-- a rough hover of this vein saved as its own "seen" spot is this one
	Absorb(spot, MERGE_YARDS)
	self:Changed()
end

local function SharesOre(a, b)
	for name in pairs(a.ores) do
		if b.ores[name] then return true end
	end
	return false
end

-- Fold never-mined spot `s` into `into`: its ores, latest sighting and
-- hover estimate.
local function Fold(into, s)
	for name in pairs(s.ores) do into.ores[name] = into.ores[name] or 0 end
	into.seenAt = max(into.seenAt or 0, s.seenAt or 0)
	if into.map == s.map and s.hErr then AddHover(into, s.hx, s.hy, s.hErr) end
end

-- Fold every never-mined spot sharing an ore with `spot` within `reach` into
-- it. Returns true if any went.
function Absorb(spot, reach)
	if not spot.wx then return end
	local gone
	for _, t in ipairs(ns.db.spots) do
		if t ~= spot and not t.last and t.wx and t.inst == spot.inst and SharesOre(t, spot) then
			local dx, dy = t.wx - spot.wx, t.wy - spot.wy
			if dx * dx + dy * dy < reach * reach then
				Fold(spot, t)
				gone = gone or {}
				gone[t] = true
			end
		end
	end
	if gone then
		ns:RemoveSpots(function(s) return gone[s] end)
		return true
	end
end

-- A Find Minerals dot for `name` was hovered around this position, at most
-- `err` yards off; `slop` is how far from the dot its tooltip shows.
-- Marks the spot there as up, or saves a new "seen" spot. Never-mined spots
-- of the same ore within reach are one vein: they average together.
-- Seeing a vein is not a visit.
function ns:RecordSeen(name, wx, wy, inst, mapID, x, y, slop, err)
	if self.db.ignore[name] then return end
	local now = time()
	-- two hovers can each be `slop` off, in opposite directions; zoomed in,
	-- the reach shrinks so close veins stay apart
	local reach = max(MERGE_YARDS, min(SEEN_REACH, 2 * (slop or SEEN_REACH)))
	local spot, d = Closest(wx, wy, inst, mapID, x, y, name, reach)
	if self.hoverDebug then
		self:Print("  merge reach %d yd: %s", reach,
			spot and ("joined a spot %d yd away"):format(d) or "no spot in reach, new spot")
	end
	if not spot then
		NewSpot(mapID, x, y, wx, wy, inst, name, false, now)
		local new = self.db.spots[#self.db.spots]
		AddHover(new, x, y, err or slop or SEEN_REACH)
		Absorb(new, reach)
		return self:Changed()
	end
	local moved
	if spot.map == mapID then
		AddHover(spot, x, y, err or slop or SEEN_REACH)
		moved = true
		if self.hoverDebug then
			self:Print("  hover %.0f yd from the spot: averaged in (hovers now good to ~%.0f yd, %d gathers)",
				d, spot.hErr, spot.gN or 0)
		end
	end
	-- right after mining, the dot can linger a moment: that isn't "up"
	if spot.last and now - spot.last < MULTITAP_SEC then
		if moved then self:Changed() end
		return
	end
	local wasUp = SeenUp(spot)
	spot.seenAt = now
	if not spot.ores[name] then
		spot.ores[name] = 0
		if not spot.last then spot.lastOre = name end
		moved = true
	end
	if Absorb(spot, reach) or moved then
		self:Changed()
	elseif not wasUp then
		self:Restyle()
	end
end

-- At load: fold never-mined spots into a nearby spot with the same ore,
-- mined ones first (cleans up hovers saved before they were merged).
local function MergeSeenDuplicates()
	local present = {}
	for _, s in ipairs(ns.db.spots) do present[s] = true end
	local snapshot = {}
	for i, s in ipairs(ns.db.spots) do snapshot[i] = s end
	local function pass(mined, reach)
		for _, s in ipairs(snapshot) do
			if present[s] and (s.last ~= nil) == mined and Absorb(s, reach) then
				wipe(present)
				for _, t in ipairs(ns.db.spots) do present[t] = true end
			end
		end
	end
	pass(true, ADOPT_REACH)
	pass(false, SEEN_REACH)
end

-- At load: mined spots of the same ore this close are one vein saved twice
-- (a respawn taken for a neighbour): merge their history and averages.
local DUPLICATE_YARDS = 6
local function MergeMinedDuplicates()
	local spots, gone = ns.db.spots, {}
	for i, a in ipairs(spots) do
		for j = i + 1, #spots do
			local b = spots[j]
			if not gone[a] and not gone[b] and a.last and b.last and a.wx and b.wx
				and a.inst == b.inst and a.map == b.map and SharesOre(a, b)
				and (a.wx - b.wx) ^ 2 + (a.wy - b.wy) ^ 2 < DUPLICATE_YARDS * DUPLICATE_YARDS then
				for name, n in pairs(b.ores) do a.ores[name] = (a.ores[name] or 0) + n end
				a.visits, a.taps = a.visits + b.visits, a.taps + b.taps
				a.first, a.last = min(a.first, b.first), max(a.last, b.last)
				a.minGap = (a.minGap and b.minGap) and min(a.minGap, b.minGap) or a.minGap or b.minGap
				a.seenAt = max(a.seenAt or 0, b.seenAt or 0)
				if b.gN then
					local n = (a.gN or 0) + b.gN
					a.gx = ((a.gx or 0) * (a.gN or 0) + b.gx * b.gN) / n
					a.gy = ((a.gy or 0) * (a.gN or 0) + b.gy * b.gN) / n
					a.gN = n
				end
				if b.hErr then AddHover(a, b.hx, b.hy, b.hErr) else Settle(a) end
				gone[b] = true
			end
		end
	end
	if next(gone) then ns:RemoveSpots(function(s) return gone[s] end) end
end

-- Spots saved before the two averages existed: their position counts as
-- the gather average (mined) or one rough hover (never mined).
local function Migrate()
	for _, s in ipairs(ns.db.spots) do
		if not (s.gN or s.hErr) then
			if s.last then
				s.gx, s.gy, s.gN = s.x, s.y, s.posN or 1
			else
				s.hx, s.hy, s.hErr = s.x, s.y, s.fixErr or 10
			end
		end
		s.posN, s.fixErr, s.seenN = nil, nil, nil
	end
end

ns:On("VK_LOADED", function()
	Migrate()
	MergeMinedDuplicates()
	MergeSeenDuplicates()
end)

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
-- Mining detection. A successful Mining cast is recorded once its node is
-- known, best source first: the object ID in the loot window's source GUID,
-- the soft interact target's object ID at the cast (when the game's
-- SoftTargetInteract setting is on), then the name the cast was aimed at.
-- Object IDs work in every client language; the cast's name for that node
-- is learned, so minimap hovers can read it too.
---------------------------------------------------------------------------
local MINING
local LOOT_WAIT = 3 -- seconds to wait for the loot window after a cast
local cast  -- the cast in progress: { guid, shown = name aimed at, softID, node = soft target GUID }
local mined -- a successful cast waiting for its loot window

local function Finish(id, node)
	local m = mined
	mined = nil
	if not m then return end
	local name = ns.OBJECTS[id or m.softID]
	if name then
		local shown = m.shown
		if shown and shown ~= name and not ns.NODES[shown] then ns.db.names[shown] = name end
	else
		name = ns:NodeName(m.shown) or m.shown -- a node VeinKeeper doesn't know is kept by name
	end
	if name then ns:Record(name, node or m.node) end
	C_Timer.After(1, FullScan) -- the skill may have gone up
end

ns:On("PLAYER_LOGIN", function() MINING = ns:SpellName(2575) or "Mining" end)

ns:On("UNIT_SPELLCAST_SENT", function(_, target, castGUID, spellID)
	if not spellID or ns:SpellName(spellID) ~= MINING then return end
	local shown = target ~= "" and target or nil
	if not shown and GameTooltip:IsShown() then
		-- the node under the cursor, but only a name known to be a node
		local t = GameTooltipTextLeft1:GetText()
		shown = ns:NodeName(t) and t or nil
	end
	local soft = UnitGUID and UnitGUID("softinteract")
	local softID = ns:ObjectID(soft)
	if softID and not ns.OBJECTS[softID] then softID = nil end
	if shown or softID then
		cast = { guid = castGUID, shown = shown, softID = softID, node = softID and soft or nil }
	end
end, "player")

ns:On("UNIT_SPELLCAST_SUCCEEDED", function(_, castGUID)
	if not (cast and castGUID == cast.guid) then return end
	if mined then Finish() end -- a previous cast whose loot never came
	local m = cast
	mined, cast = m, nil
	C_Timer.After(LOOT_WAIT, function()
		if mined == m then Finish() end
	end)
end, "player")

ns:On("LOOT_READY", function()
	if not (mined and GetLootSourceInfo) then return end
	for i = 1, GetNumLootItems() do
		local source = GetLootSourceInfo(i)
		local id = ns:ObjectID(source)
		if id and ns.OBJECTS[id] then return Finish(id, source) end
	end
end)

local function CastEnded(_, castGUID)
	if cast and castGUID == cast.guid then cast = nil end
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
