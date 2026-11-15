-- Do veins come back where they were? Classic-style servers may respawn a
-- mined vein at another spawn point of a zone-wide pool instead, and WoW
-- Forever documents neither. This measures it from your own play.
--
-- A visit: coming within ARRIVE_YARDS of a saved spot you can mine. It
-- counts as "likely back" or "not back yet" by VeinKeeper's timer then, and
-- ends as a hit (you mine it) or a miss (you go LEAVE_YARDS away without
-- mining it). Visits in combat, on a flight path or while dead aren't
-- counted; neither is finding a new vein (that's not a saved spot yet).
--
-- VeinKeeperDB.visits[node name] = { up hits, up visits, early hits, early visits }
--
-- If veins come back where they were, likely-back spots nearly always have
-- one and not-back-yet spots rarely do. If they come back across a pool, the
-- two rates are close: a spot's own timer hardly matters.
--
-- Cost: a twice-a-second check that returns at once while you stand still.
local _, ns = ...
local L = ns.L

local floor, abs = math.floor, math.abs

local ARRIVE_YARDS = 12 -- close enough to see whether a vein is there
local LEAVE_YARDS = 30
local TICK = 0.5
local MIN_CHANCE_VISITS = 10 -- before this, no chance in tooltips
local VERDICT_UP, VERDICT_EARLY = 20, 10 -- visits needed for /vk pool's verdict

local visiting = {} -- spot -> "up" or "early", while you're at it
local cooling = {}  -- spots whose visit ended: not visited again until you've left
local lastX, lastY

local function Counts(name)
	local c = ns.db.visits[name]
	if not c then
		c = { 0, 0, 0, 0 }
		ns.db.visits[name] = c
	end
	return c
end

local function Finish(spot, hit)
	local state = visiting[spot]
	visiting[spot], cooling[spot] = nil, true
	local c = Counts(spot.lastOre)
	if state == "up" then
		c[2] = c[2] + 1
		if hit then c[1] = c[1] + 1 end
	else
		c[4] = c[4] + 1
		if hit then c[3] = c[3] + 1 end
	end
end

-- testing hook: the state a visit to `spot` is in, if any
function ns:VisitState(spot) return visiting[spot] end

local function Busy()
	return UnitOnTaxi("player") or (UnitAffectingCombat and UnitAffectingCombat("player"))
		or (UnitIsDeadOrGhost and UnitIsDeadOrGhost("player"))
end

local function Tick()
	local wx, wy, inst = ns:PlayerWorld()
	if not wx or Busy() then return end
	if wx == lastX and wy == lastY then return end
	lastX, lastY = wx, wy
	-- walked away from a spot without mining it
	for spot in pairs(visiting) do
		local d = ns:Distance(spot)
		if not d or d > LEAVE_YARDS then Finish(spot, false) end
	end
	for spot in pairs(cooling) do
		local d = ns:Distance(spot)
		if not d or d > LEAVE_YARDS then cooling[spot] = nil end
	end
	for _, spot in ipairs(ns:SpotsNear(wx, wy, inst, ARRIVE_YARDS)) do
		if not visiting[spot] and not cooling[spot] and ns:CanMine(spot) then
			visiting[spot] = ns:Wait(spot) <= 0 and "up" or "early"
		end
	end
end

ns:On("PLAYER_LOGIN", function()
	C_Timer.NewTicker(TICK, function()
		if ns.cpu then ns:Timed("visits (twice a second)", Tick) else Tick() end
	end)
end)

-- Mining a spot you're visiting: there was a vein. (Every tap of a multi-tap
-- vein lands here; only the first finds a visit.)
ns:On("VK_MINED", function(spot)
	if visiting[spot] then Finish(spot, true) end
end)

-- Spots that went away (forgotten, merged) end their visit uncounted.
ns:On("VK_DATA", function()
	if not (next(visiting) or next(cooling)) then return end
	local present = {}
	for _, s in ipairs(ns.db.spots) do present[s] = true end
	for spot in pairs(visiting) do
		if not present[spot] then visiting[spot] = nil end
	end
	for spot in pairs(cooling) do
		if not present[spot] then cooling[spot] = nil end
	end
end)

---------------------------------------------------------------------------
-- Results
---------------------------------------------------------------------------
-- Summed over a vein type's respawn group (types sharing spawn points):
-- up hits, up visits, early hits, early visits.
local function GroupCounts(name)
	local t = { 0, 0, 0, 0 }
	for _, n in ipairs(ns:RespawnGroup(name)) do
		local c = ns.db.visits[n]
		if c then
			for i = 1, 4 do t[i] = t[i] + c[i] end
		end
	end
	return t
end

local function Pct(hits, n) return n > 0 and floor(hits / n * 100 + 0.5) or 0 end

-- The measured chance a vein is at this spot now, by whether it's likely
-- back, and the visits behind it; nil until there are MIN_CHANCE_VISITS.
function ns:UpChance(spot)
	local c = GroupCounts(spot.lastOre)
	local hits, n
	if self:Wait(spot) <= 0 then hits, n = c[1], c[2] else hits, n = c[3], c[4] end
	if n < MIN_CHANCE_VISITS then return end
	return Pct(hits, n), n
end

-- The verdict, from all types together: which way the counts lean.
local function Verdict(up, upN, early, earlyN)
	if upN < VERDICT_UP or earlyN < VERDICT_EARLY then
		return L["not enough visits yet to tell (%d to likely-back spots, %d to others); keep mining and check again."]
			:format(upN, earlyN)
	end
	local u, e = up / upN, early / earlyN
	if u >= 0.75 and e <= 0.2 then
		return L["veins mostly come back where they were: spot timers can be trusted."]
	elseif abs(u - e) < 0.2 then
		return L["a spot's timer hardly changes the odds: veins come back across a shared pool, so check every spot you pass."]
	end
	return L["somewhere in between: timers help, but veins also come back elsewhere."]
end

function ns:PrintPool()
	local names = {}
	for name, c in pairs(self.db.visits) do
		if c[2] + c[4] > 0 then names[#names + 1] = name end
	end
	if #names == 0 then
		return self:Print(L["no visits recorded yet: VeinKeeper counts what you find each time you come within %d yd of a saved spot."],
			ARRIVE_YARDS)
	end
	table.sort(names, function(a, b)
		local sa, sb = self:NodeInfo(a).skill or 0, self:NodeInfo(b).skill or 0
		if sa ~= sb then return sa < sb end
		return a < b
	end)
	self:Print(L["what you found at saved spots (a visit counts once you come within %d yd):"], ARRIVE_YARDS)
	local listed, total = {}, { 0, 0, 0, 0 }
	for _, name in ipairs(names) do
		local group = self:RespawnGroup(name)
		if not listed[group[1]] then
			listed[group[1]] = true
			local c = GroupCounts(name)
			for i = 1, 4 do total[i] = total[i] + c[i] end
			local labels = {}
			for i, n in ipairs(group) do labels[i] = self:NodeLabel(n) end
			print(("  %s: %s; %s"):format(table.concat(labels, " / "),
				L["likely back: %d of %d had a vein (%d%%)"]:format(c[1], c[2], Pct(c[1], c[2])),
				L["not back yet: %d of %d (%d%%)"]:format(c[3], c[4], Pct(c[3], c[4]))))
		end
	end
	self:Print(Verdict(total[1], total[2], total[3], total[4]))
end

StaticPopupDialogs.VEINKEEPER_POOL_RESET = {
	text = L["Forget all VeinKeeper visit counts?"],
	button1 = YES, button2 = NO,
	OnAccept = function()
		wipe(ns.db.visits)
		ns:Print(L["visit counts cleared."])
	end,
	timeout = 0, whileDead = true, hideOnEscape = true,
}
