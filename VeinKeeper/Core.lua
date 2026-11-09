-- VeinKeeper core: saved data, events, change notification and coordinates.
local ADDON, ns = ...
VeinKeeper = ns -- Bindings.xml calls into this

local sqrt = math.sqrt
local DB_VERSION = 2

ns.DEFAULTS = {
	-- pins
	worldPins = true,
	minimapPins = true,
	gameIcons = true,     -- the game's ore item icons (false = VeinKeeper's drawn icons)
	skillDim = true,      -- dim spots above your Mining skill
	worldAlpha = 1,       -- 0.1 - 1
	minimapAlpha = 1,
	worldSize = 18,       -- px, before map zoom scaling
	minimapSize = 14,     -- px
	-- respawns and the minimap
	readyMin = 10,        -- minutes after mining before a spot counts as likely back
	edgeCount = 3,        -- nearest out-of-view spots pinned to the minimap rim
	edgeMaxYards = 500,   -- no rim pin for spots further than this
	edgeReadyOnly = true, -- rim pins only for spots likely back
	inRange = "ring",     -- spots in view while Find Minerals is on: "ring", "hide" or "icon"
	recordSeen = true,    -- save veins whose Find Minerals dot you hover on the minimap
	only = false,         -- ore filter: an ore item ID (or node name for nodes without one); false = all
	-- buttons
	button = true,
	buttonAngle = 215,
	mapButton = true,
}

BINDING_HEADER_VEINKEEPER = "VeinKeeper"
BINDING_NAME_VEINKEEPER_NEXT = "Waypoint to the next respawned spot"
BINDING_NAME_VEINKEEPER_TOGGLE = "Show / hide all pins"
BINDING_NAME_VEINKEEPER_SETTINGS = "Open settings"

---------------------------------------------------------------------------
-- Events: one frame for the whole addon. ns:On("EVENT", fn [, unit]).
-- Names starting with VK_ are internal messages sent with ns:Fire:
--   VK_LOADED  saved variables are ready
--   VK_DATA    spots, filters or settings changed: rebuild pins
--   VK_STYLE   only the look changed (opacity, size, freshness): restyle pins
---------------------------------------------------------------------------
local handlers = {}
local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(_, event, ...)
	if ns.cpu then return ns:Timed(event, handlers[event], ...) end
	for _, fn in ipairs(handlers[event]) do fn(...) end
end)

---------------------------------------------------------------------------
-- /vk cpu: time every event handler and the minimap tick for 30 seconds.
-- Costs nothing while off (one nil check per event).
---------------------------------------------------------------------------
function ns:Timed(key, list, ...)
	local t = debugprofilestop()
	if type(list) == "function" then list(...) else for _, fn in ipairs(list) do fn(...) end end
	local e = self.cpu[key]
	if not e then e = { 0, 0 }; self.cpu[key] = e end
	e[1], e[2] = e[1] + debugprofilestop() - t, e[2] + 1
end

function ns:MeasureCPU()
	if self.cpu then return self:Print("already measuring.") end
	local P = C_AddOnProfiler
	local metric = Enum and Enum.AddOnProfilerMetric
	-- the game's own figure for the last few seconds (its session average
	-- includes everything since login, also before a /reload)
	local function Game()
		if not (P and metric and P.GetAddOnMetric) then return end
		local ok, v = pcall(P.GetAddOnMetric, ADDON, metric.RecentAverageTime)
		return ok and v or nil
	end
	self.cpu = {}
	self:Print("measuring CPU for 30 s; play normally (move around, mine).")
	C_Timer.After(30, function()
		local cpu = self.cpu
		self.cpu = nil
		local rows, total = {}, 0
		for k, e in pairs(cpu) do rows[#rows + 1] = { k, e[1], e[2] }; total = total + e[1] end
		table.sort(rows, function(a, b) return a[2] > b[2] end)
		self:Print("%.2f ms per second in VeinKeeper's own code:", total / 30)
		for i = 1, math.min(8, #rows) do
			local r = rows[i]
			print(("  %-28s %7.3f ms/s  %5d calls  %.3f ms each"):format(r[1], r[2] / 30, r[3], r[2] / r[3]))
		end
		local recent = Game()
		if recent then print(("  game profiler, recent average: %.4f ms"):format(recent)) end
	end)
end

function ns:On(event, fn, unit)
	local list = handlers[event]
	if not list then
		list = {}
		handlers[event] = list
		-- pcall: registering an event this client doesn't have throws, which
		-- would abort loading the rest of the calling file
		if event:sub(1, 3) ~= "VK_" then
			if unit then
				pcall(frame.RegisterUnitEvent, frame, event, unit)
			else
				pcall(frame.RegisterEvent, frame, event)
			end
		end
	end
	list[#list + 1] = fn
end

function ns:Fire(event, ...)
	local list = handlers[event]
	if list then
		for _, fn in ipairs(list) do fn(...) end
	end
end

-- Bumped on every change; pins compare it to skip redundant restyling.
ns.version = 0

function ns:Changed()
	self.version = self.version + 1
	self:Fire("VK_DATA")
end

function ns:Restyle()
	self.version = self.version + 1
	self:Fire("VK_STYLE")
end

ns:On("ADDON_LOADED", function(name)
	if name ~= ADDON then return end
	VeinKeeperDB = VeinKeeperDB or {}
	local db = VeinKeeperDB
	db.spots = db.spots or {}
	db.ignore = db.ignore or {}
	db.names = db.names or {} -- node names in the client's language -> English (learned when mining)
	db.settings = db.settings or {}
	for k in pairs(db.settings) do
		if ns.DEFAULTS[k] == nil then db.settings[k] = nil end -- drop retired settings
	end
	for k, v in pairs(ns.DEFAULTS) do
		if db.settings[k] == nil then db.settings[k] = v end
	end
	db.version = DB_VERSION
	ns.db = db
	ns:Fire("VK_LOADED")
end)

-- freshness rings change colour over time
ns:On("PLAYER_LOGIN", function()
	C_Timer.NewTicker(15, function()
		if ns.cpu then ns:Timed("restyle (every 15 s)", ns.Restyle, ns) else ns:Restyle() end
	end)
end)

---------------------------------------------------------------------------
-- Utilities
---------------------------------------------------------------------------
function ns:Print(msg, ...)
	DEFAULT_CHAT_FRAME:AddMessage("|cffd9a066VeinKeeper|r: " .. (select("#", ...) > 0 and msg:format(...) or msg))
end

function ns:SpellName(id)
	local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
	if not name and GetSpellInfo then name = GetSpellInfo(id) end
	return name
end

function ns:FormatTime(sec)
	sec = math.floor(sec)
	if sec < 60 then return sec .. "s" end
	if sec < 3600 then return math.floor(sec / 60) .. "m" end
	if sec < 86400 then return ("%dh %dm"):format(sec / 3600, (sec % 3600) / 60) end
	return math.floor(sec / 86400) .. "d"
end

function ns:ToggleAllPins()
	local s = self.db.settings
	local on = not (s.worldPins or s.minimapPins)
	s.worldPins, s.minimapPins = on, on
	self:Print("pins %s.", on and "on" or "off")
	self:Changed()
end

---------------------------------------------------------------------------
-- Coordinates. World positions are in yards and valid across zones of the
-- same continent ("instance"), so spots show on neighbouring zone maps.
---------------------------------------------------------------------------
local basisCache = {}

-- A map's world origin (top-left corner) and the world vectors of its east
-- and south edges. Orientation-agnostic, so no axis conventions to get wrong.
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

-- Yards east and south from point 1 to point 2, along a map's axes.
function ns:Delta(b, wx1, wy1, wx2, wy2)
	local dx, dy = wx2 - wx1, wy2 - wy1
	return (dx * b.ex + dy * b.ey) / b.w, (dx * b.sx + dy * b.sy) / b.h
end

-- The inverse of Delta: the world point east/south yards from wx, wy.
function ns:Offset(b, wx, wy, east, south)
	return wx + east * b.ex / b.w + south * b.sx / b.h, wy + east * b.ey / b.w + south * b.sy / b.h
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

function ns:Distance(spot)
	if not spot.wx then return end
	local wx, wy, inst = self:PlayerWorld()
	if not wx or inst ~= spot.inst then return end
	local dx, dy = spot.wx - wx, spot.wy - wy
	return sqrt(dx * dx + dy * dy)
end
