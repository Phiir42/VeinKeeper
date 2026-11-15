-- Farm route: a loop through every saved spot in your zone you can mine (and
-- that passes the ore filter), drawn on the world map, with a waypoint that
-- moves on as you go:
--  - mining a stop sends you on to the next stop likely back;
--  - reaching a stop that isn't back yet sends you on at once;
--  - walking on from a "likely back" stop without mining it marks it empty
--    (skipped for one respawn timer, as /vk next does).
-- Veins you find in the zone while it runs join the loop where they add the
-- least distance. Session only: /vk route builds it again in a moment.
--
-- Cost: a 1 Hz timer while a route runs; nothing otherwise.
local _, ns = ...
local L = ns.L

local sqrt, floor, min = math.sqrt, math.floor, math.min

local ARRIVE_YARDS = 25 -- at a stop
local LEAVE_YARDS = 50  -- walked on from a stop you'd reached
local TICK = 1
local MAX_PASSES = 50   -- 2-opt passes (each one O(n^2); a few usually settle it)

local route  -- { map, inst, stops = { spot, ... }, target = spot, arrived = bool }
local ticker

---------------------------------------------------------------------------
-- Ordering: nearest neighbour from the player, then 2-opt (undo any two
-- crossing legs) until no swap shortens the loop.
---------------------------------------------------------------------------
local function D(a, b)
	local dx, dy = a.wx - b.wx, a.wy - b.wy
	return sqrt(dx * dx + dy * dy)
end

-- Points with wx, wy -> a new list in loop order, starting nearest px, py.
local function OrderLoop(points, px, py)
	local left, order = {}, {}
	for i, p in ipairs(points) do left[i] = p end
	local cx, cy = px, py
	while #left > 0 do
		local bi, bd
		for i, p in ipairs(left) do
			local dx, dy = p.wx - cx, p.wy - cy
			local d = dx * dx + dy * dy
			if not bd or d < bd then bi, bd = i, d end
		end
		local p = table.remove(left, bi)
		order[#order + 1] = p
		cx, cy = p.wx, p.wy
	end
	local n = #order
	if n < 4 then return order end
	for _ = 1, MAX_PASSES do
		local improved = false
		for i = 1, n - 2 do
			local a, b = order[i], order[i + 1]
			-- legs a-b and c-d; with i = 1 the last leg (n -> 1) touches a
			for j = i + 2, i == 1 and n - 1 or n do
				local c, d = order[j], order[j % n + 1]
				if D(a, c) + D(b, d) < D(a, b) + D(c, d) - 0.01 then
					local lo, hi = i + 1, j
					while lo < hi do
						order[lo], order[hi] = order[hi], order[lo]
						lo, hi = lo + 1, hi - 1
					end
					b = order[i + 1]
					improved = true
				end
			end
		end
		if not improved then break end
	end
	return order
end
ns.OrderLoop = OrderLoop -- for tools/test_route.py

local function LoopLength(stops)
	local len, n = 0, #stops
	for i = 1, n do len = len + D(stops[i], stops[i % n + 1]) end
	return len
end

---------------------------------------------------------------------------
-- Route state
---------------------------------------------------------------------------
local function Eligible(s, mapID, inst)
	return s.map == mapID and s.wx and s.inst == inst and ns:IsShown(s) and ns:CanMine(s)
end

local function IndexOf(spot)
	if not (route and spot) then return end
	for i, s in ipairs(route.stops) do
		if s == spot then return i end
	end
end

-- The first stop from index i on (wrapping round) that's likely back; if
-- none is, stop i itself and the seconds until the soonest is back.
local function FromHere(i)
	local stops, n = route.stops, #route.stops
	local soonest
	for k = 0, n - 1 do
		local s = stops[(i - 1 + k) % n + 1]
		local wait = ns:WaitChecked(s)
		if wait <= 0 then return s end
		soonest = soonest and min(soonest, wait) or wait
	end
	return stops[(i - 1) % n + 1], soonest
end

local function Go(spot, soonest)
	if spot == route.target then return end
	route.target, route.arrived = spot, false
	ns:SetWaypoint(spot)
	local d = ns:Distance(spot)
	local ore = ns:NodeLabel(ns:DisplayOre(spot))
	if d then
		ns:Print(L["route %d/%d: %s, %d yd."], IndexOf(spot), #route.stops, ore, d)
	else
		ns:Print(L["route %d/%d: %s."], IndexOf(spot), #route.stops, ore)
	end
	if soonest then ns:Print(L["nothing likely back yet; the soonest is in %s."], ns:FormatTime(soonest)) end
	ns:Fire("VK_ROUTE")
end

-- On from stop i to the next one likely back.
local function Advance(i)
	Go(FromHere((i or IndexOf(route.target) or 0) + 1))
end

-- A spot joins the loop where it adds the least distance.
local function Insert(spot)
	local stops, n = route.stops, #route.stops
	local best, bestCost = n + 1, nil
	for i = 1, n do
		local a, b = stops[i], stops[i % n + 1]
		local cost = D(a, spot) + D(spot, b) - D(a, b)
		if not bestCost or cost < bestCost then best, bestCost = i + 1, cost end
	end
	table.insert(stops, best, spot)
end

local function StopTicker()
	if ticker then ticker:Cancel() ticker = nil end
end

local function Tick()
	local t = route and route.target
	if not t then return end
	local d = ns:Distance(t)
	if not d then return end -- in an instance, or on another continent
	if not route.arrived then
		if d < ARRIVE_YARDS then
			route.arrived = true
			if ns:WaitChecked(t) > 0 then Advance() end -- not back yet: on to the next
		end
	elseif d > LEAVE_YARDS then
		ns:MarkEmpty(t) -- walked on without mining it: it wasn't there
		Advance()
	end
end

function ns:RouteActive() return route ~= nil end

function ns:StopRoute(quiet)
	if not route then return end
	route = nil
	StopTicker()
	if not quiet then self:Print(L["route stopped."]) end
	self:Fire("VK_ROUTE")
end

function ns:StartRoute()
	local mapID = C_Map.GetBestMapForUnit("player")
	local wx, wy, inst = self:PlayerWorld()
	if not (mapID and wx) then return self:Print(L["no position here."]) end
	local points = {}
	for _, s in ipairs(self.db.spots) do
		if Eligible(s, mapID, inst) then points[#points + 1] = s end
	end
	if #points < 2 then
		return self:Print(L["a route needs 2 or more saved spots you can mine in this zone; it has %d."], #points)
	end
	self:StopRoute(true)
	local stops = OrderLoop(points, wx, wy)
	route = { map = mapID, inst = inst, stops = stops }
	local info = C_Map.GetMapInfo(mapID)
	local only = self.db.settings.only
	local zone, lap = info and info.name or L["this zone"], floor(LoopLength(stops))
	if only then
		self:Print(L["route through %d spots of %s in %s, %d yd a lap. /vk next skips a stop, /vk route off stops it."],
			#stops, self:OreLabel(only), zone, lap)
	else
		self:Print(L["route through %d spots in %s, %d yd a lap. /vk next skips a stop, /vk route off stops it."],
			#stops, zone, lap)
	end
	Go(FromHere(1))
	ticker = C_Timer.NewTicker(TICK, function()
		if ns.cpu then ns:Timed("route (every 1 s)", Tick) else Tick() end
	end)
end

function ns:ToggleRoute()
	if route then self:StopRoute() else self:StartRoute() end
end

-- On to the next stop likely back; if that's this one again (the only one
-- back), simply the next stop in the loop.
function ns:RouteSkip()
	if not route then return end
	local i = IndexOf(route.target) or 0
	local spot, soonest = FromHere(i + 1)
	if spot == route.target then spot, soonest = route.stops[i % #route.stops + 1], nil end
	Go(spot, soonest)
end

-- stop index, stop count and whether it's the next stop; nil if not on the route
function ns:RouteStop(spot)
	local i = IndexOf(spot)
	if i then return i, #route.stops, spot == route.target end
end

-- Spots forgotten, merged or filtered out leave the loop; new ones in the
-- zone join it.
ns:On("VK_DATA", function()
	if not route then return end
	local present, inRoute = {}, {}
	for _, s in ipairs(ns.db.spots) do present[s] = true end
	local stops, kept, lostTarget = route.stops, {}, nil
	for _, s in ipairs(stops) do
		if present[s] and Eligible(s, route.map, route.inst) then
			kept[#kept + 1] = s
			inRoute[s] = true
		elseif s == route.target then
			lostTarget = #kept -- the stop before it, in the new list
		end
	end
	route.stops = kept
	for _, s in ipairs(ns.db.spots) do
		if not inRoute[s] and Eligible(s, route.map, route.inst) then Insert(s) end
	end
	if #route.stops < 2 then
		ns:StopRoute(true)
		return ns:Print(L["route stopped: fewer than 2 spots left in it."])
	end
	if lostTarget then
		route.target = nil
		Advance(lostTarget)
	else
		ns:Fire("VK_ROUTE")
	end
end)

-- Mining a stop (any stop: you may cut the loop short) moves the route on.
-- Every tap of a multi-tap vein lands here; Go ignores the repeats.
ns:On("VK_MINED", function(spot)
	if not route then return end
	local i = IndexOf(spot)
	if i then Advance(i) end
end)

---------------------------------------------------------------------------
-- World map: the loop as lines under the pins, the leg to the next stop
-- brighter.
---------------------------------------------------------------------------
local provider = CreateFromMixins(MapCanvasDataProviderMixin)
local layer
local lines, nLines = {}, 0
local THICK, THICK_NEXT = 2, 3.5 -- px at any zoom

local function Thickness()
	local map = provider:GetMap()
	local scale = map and map.GetCanvasScale and map:GetCanvasScale() or 1
	if not scale or scale <= 0 then scale = 1 end
	for i = 1, nLines do
		local l = lines[i]
		l:SetThickness((l.next and THICK_NEXT or THICK) / scale)
	end
end

local function Layer(map)
	local canvas = map:GetCanvas()
	if not layer then
		layer = CreateFrame("Frame", nil, canvas)
		layer:SetAllPoints(canvas)
	end
	-- just under VeinKeeper's pins (and other area POIs), over the map itself
	local levels = map.GetPinFrameLevelsManager and map:GetPinFrameLevelsManager()
	if levels and levels.GetValidFrameLevel then
		local ok, level = pcall(levels.GetValidFrameLevel, levels, "PIN_FRAME_LEVEL_AREA_POI")
		if ok and type(level) == "number" and level > 1 then layer:SetFrameLevel(level - 1) end
	end
	return layer
end

function provider:RemoveAllData()
	for i = 1, nLines do lines[i]:Hide() end
	nLines = 0
end

local function Inside(x, y) return x >= 0 and x <= 1 and y >= 0 and y <= 1 end

local MapType = Enum and Enum.UIMapType or {}
local WORLD = MapType.World or 1

function provider:RefreshAllData()
	self:RemoveAllData()
	if not route then return end
	local map = self:GetMap()
	local mapID = map:GetMapID()
	local info = mapID and C_Map.GetMapInfo(mapID)
	if not mapID or mapID == 947 or (info and info.mapType and info.mapType <= WORLD) then return end
	local b = ns:Basis(mapID)
	if not b or b.inst ~= route.inst then return end
	local layerFrame = Layer(map)
	local w, h = map:GetCanvas():GetSize()
	if not (w and w > 0 and h and h > 0) then return end
	local stops, n = route.stops, #route.stops
	local xs, ys = {}, {}
	for i, s in ipairs(stops) do xs[i], ys[i] = ns:WorldToMap(b, s.wx, s.wy) end
	local target = IndexOf(route.target)
	for i = 1, n do
		local j = i % n + 1
		if Inside(xs[i], ys[i]) or Inside(xs[j], ys[j]) then
			nLines = nLines + 1
			local l = lines[nLines]
			if not l then
				l = layerFrame:CreateLine(nil, "ARTWORK")
				lines[nLines] = l
			end
			l.next = j == target
			if l.next then l:SetColorTexture(1, 0.82, 0, 0.95) else l:SetColorTexture(1, 0.82, 0, 0.5) end
			l:SetStartPoint("TOPLEFT", layerFrame, xs[i] * w, -ys[i] * h)
			l:SetEndPoint("TOPLEFT", layerFrame, xs[j] * w, -ys[j] * h)
			l:Show()
		end
	end
	Thickness()
end

function provider:OnMapChanged() self:RefreshAllData() end
function provider:OnCanvasScaleChanged() Thickness() end

local function Attach()
	if provider:GetMap() or not (WorldMapFrame and WorldMapFrame.AddDataProvider) then return end
	WorldMapFrame:AddDataProvider(provider)
end

ns:On("PLAYER_LOGIN", Attach)
ns:On("ADDON_LOADED", function(name)
	if name == "Blizzard_WorldMap" then Attach() end
end)

ns:On("VK_ROUTE", function()
	-- the map redraws its providers when it opens, so only an open map needs it
	if provider:GetMap() and WorldMapFrame:IsShown() then provider:RefreshAllData() end
end)
