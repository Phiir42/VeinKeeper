-- Minimap pins: saved spots in view, the nearest far spots on the rim, and
-- saving veins whose Find Minerals dot you hover.
--
-- Cost: a 10 Hz tick that returns at once unless you moved, turned (rotating
-- minimap), zoomed or something changed. Saved spots are only searched again
-- after moving RESCAN_YARDS or a data change; pins are only restyled when
-- their spot or the style version changes.
local _, ns = ...

local sqrt, abs, cos, sin, floor, min, max = math.sqrt, math.abs, math.cos, math.sin, math.floor, math.min, math.max

local TICK = 0.1
local RESCAN_YARDS = 100
local VIEW_YARDS = 300   -- more than the widest minimap radius (~233 yd)
local RIM_INSET = 7      -- px between a rim pin's centre and the minimap edge
local HOVER_SLOP_PX = 12 -- a dot's tooltip shows with the cursor this far away
local FIND_MINERALS = 2580
-- minimap diameter in yards per zoom level (the values HereBeDragons uses)
local OUTDOOR = { [0] = 466 + 2 / 3, 400, 333 + 1 / 3, 266 + 2 / 3, 200, 133 + 1 / 3 }
local INDOOR = { [0] = 300, 240, 180, 120, 80, 50 }

local pins = {}
local cand, candReady, nCand = {}, {}, 0 -- spots near enough to matter, from the last scan
local rim = {}                            -- reused records for rim pin candidates
local scanX, scanY, scanInst
local scanStale, viewStale = true, true
local lastMap, lastX, lastY, lastFacing, lastZoom
local indoors, tracking = false, false

---------------------------------------------------------------------------
-- Minimap state
---------------------------------------------------------------------------
-- IsIndoors() can disagree with the minimap right after a zone change, so
-- compare the zoom CVars instead (as HereBeDragons-Pins does).
local checkingZoom = false
local function UpdateIndoors()
	if checkingZoom then return end
	checkingZoom = true
	local zoom = Minimap:GetZoom()
	if GetCVar("minimapZoom") == GetCVar("minimapInsideZoom") then
		Minimap:SetZoom(zoom < 2 and zoom + 1 or zoom - 1)
	end
	indoors = tonumber(GetCVar("minimapZoom")) ~= Minimap:GetZoom()
	Minimap:SetZoom(zoom)
	checkingZoom = false
	viewStale = true
end

-- Is Find Minerals the active tracking?
local function FindMineralsActive()
	if C_Minimap and C_Minimap.GetNumTrackingTypes and C_Minimap.GetTrackingInfo then
		local findName = ns:SpellName(FIND_MINERALS)
		for i = 1, C_Minimap.GetNumTrackingTypes() do
			-- a table on newer clients; name, texture, active, category, nested, spellID on older ones
			local name, _, active, _, _, spellID = C_Minimap.GetTrackingInfo(i)
			if type(name) == "table" then
				name, active, spellID = name.name, name.active, name.spellID
			end
			if active and (spellID == FIND_MINERALS or (findName and name == findName)) then
				return true
			end
		end
	end
	if GetTrackingTexture and GetSpellTexture then
		local tex = GetTrackingTexture()
		return tex ~= nil and tex == GetSpellTexture(FIND_MINERALS)
	end
	return false
end

-- Pixels per yard and the yard radius of the minimap at its current zoom.
local function Scale()
	local sizes = indoors and INDOOR or OUTDOOR
	local yardR = (sizes[Minimap:GetZoom()] or sizes[0]) / 2
	return Minimap:GetWidth() / 2 / yardR, yardR
end

local function Rotating()
	return GetCVar("rotateMinimap") == "1"
end

---------------------------------------------------------------------------
-- Pins
---------------------------------------------------------------------------
local function GetPin(i)
	local p = pins[i]
	if p then return p end
	p = CreateFrame("Frame", nil, Minimap)
	p.isMinimap = true
	p:SetFrameLevel(Minimap:GetFrameLevel() + 5)
	ns:CreatePinTextures(p)
	p.label = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	p.label:SetPoint("TOP", p, "BOTTOM", 0, -1)
	p:SetScript("OnEnter", function(self) ns:ShowTooltip(self, self.spot) end)
	p:SetScript("OnLeave", function() GameTooltip:Hide() end)
	p:SetScript("OnMouseUp", function(self, button) ns:PinClick(self, button) end)
	pins[i] = p
	return p
end

-- dist: yards to show under a rim pin (nil for pins in view)
local function Place(i, spot, x, y, ringOnly, dist)
	local p = GetPin(i)
	local rimPin = dist ~= nil
	if p.spot ~= spot or p.styled ~= ns.version or p.ringOnly ~= ringOnly or p.rimPin ~= rimPin then
		ns:StylePin(p, spot, ringOnly, rimPin and 0.8 or 1)
		-- a hollow ring is drawn larger so the tracking dot fits inside it
		local size = ns.db.settings.minimapSize + (ringOnly and 4 or 0)
		p:SetSize(size, size)
		-- a ring sits over the game's dot: let the mouse through so the dot's
		-- own tooltip shows (and hover recording sees it)
		p:EnableMouse(not ringOnly)
		p.styled, p.ringOnly, p.rimPin = ns.version, ringOnly, rimPin
	end
	p:SetPoint("CENTER", Minimap, "CENTER", x, y)
	local yd = dist and floor(dist)
	if p.yd ~= yd then
		p.label:SetText(yd and yd .. " yd" or "")
		p.yd = yd
	end
	p:Show()
end

local function HidePins(from)
	for i = from, #pins do pins[i]:Hide() end
end

local function Scan(wx, wy, inst)
	local s = ns.db.settings
	local r = (s.edgeCount > 0 and max(s.edgeMaxYards, VIEW_YARDS) or VIEW_YARDS) + RESCAN_YARDS
	local r2 = r * r
	nCand = 0
	for _, spot in ipairs(ns.db.spots) do
		if spot.wx and spot.inst == inst and ns:IsShown(spot) then
			local dx, dy = spot.wx - wx, spot.wy - wy
			if dx * dx + dy * dy < r2 then
				nCand = nCand + 1
				cand[nCand] = spot
				candReady[nCand] = select(4, ns:Freshness(spot))
			end
		end
	end
	for i = nCand + 1, #cand do cand[i], candReady[i] = nil, nil end
	scanX, scanY, scanInst, scanStale = wx, wy, inst, false
end

local function ByDistance(a, b) return a.d < b.d end

local function Update()
	if not Minimap:IsVisible() then return end
	local mapID, px, py = ns:PlayerMapPos()
	local rotate = Rotating()
	local facing = rotate and GetPlayerFacing and GetPlayerFacing() or 0
	local zoom = Minimap:GetZoom()
	if not viewStale and mapID == lastMap and px == lastX and py == lastY
		and facing == lastFacing and zoom == lastZoom then
		return
	end
	viewStale = false
	lastMap, lastX, lastY, lastFacing, lastZoom = mapID, px, py, facing, zoom

	local b = mapID and ns:Basis(mapID)
	if not b then return HidePins(1) end
	local wx, wy, inst = ns:MapToWorld(mapID, px, py)
	if scanStale or inst ~= scanInst
		or (wx - scanX) ^ 2 + (wy - scanY) ^ 2 > RESCAN_YARDS * RESCAN_YARDS then
		Scan(wx, wy, inst)
	end

	local s = ns.db.settings
	local scale, yardR = Scale()
	local pxR = Minimap:GetWidth() / 2
	local square = GetMinimapShape and GetMinimapShape() == "SQUARE"
	local fc, fs = cos(facing), sin(facing)
	local viewR = yardR * 0.94
	local ringOnly = tracking and s.inRange == "ring"
	local hideInView = tracking and s.inRange == "hide"
	local maxRim = s.edgeCount > 0 and s.edgeMaxYards or -1

	local used, nRim = 0, 0
	for i = 1, nCand do
		local spot = cand[i]
		local east, south = ns:Delta(b, wx, wy, spot.wx, spot.wy)
		local x, y = east, -south -- y up = north
		if rotate then x, y = x * fc + y * fs, -x * fs + y * fc end
		local inView
		if square then
			inView = abs(x) < viewR and abs(y) < viewR
		else
			inView = x * x + y * y < viewR * viewR
		end
		if inView then
			if not hideInView then
				used = used + 1
				Place(used, spot, x * scale, y * scale, ringOnly)
			end
		elseif candReady[i] or not s.edgeReadyOnly then
			local d = sqrt(x * x + y * y)
			if d <= maxRim then
				nRim = nRim + 1
				local e = rim[nRim] or {}
				rim[nRim] = e
				e.spot, e.x, e.y, e.d = spot, x, y, d
			end
		end
	end

	if nRim > 0 then
		for i = #rim, nRim + 1, -1 do rim[i] = nil end
		table.sort(rim, ByDistance)
		for i = 1, min(s.edgeCount, nRim) do
			local e = rim[i]
			local k = (pxR - RIM_INSET) / (square and max(abs(e.x), abs(e.y)) or e.d)
			used = used + 1
			Place(used, e.spot, e.x * k, e.y * k, false, e.d)
		end
	end
	HidePins(used + 1)
end

---------------------------------------------------------------------------
-- Hover recording: a hovered Find Minerals dot shows the node name in the
-- tooltip, and the cursor's offset from the minimap centre is where the vein
-- is relative to you (a minimap pixel is 2-3 yards).
---------------------------------------------------------------------------
local lastTip, lastTipLines

local function CleanLine(t)
	t = t:gsub("|T.-|t", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	return t:match("^%s*(.-)%s*$")
end

local debug = false -- /vk debug: print what hover recording sees

local function FrameName(f)
	if not f then return "none" end
	return (f.GetName and f:GetName()) or tostring(f)
end

local function CheckHover()
	if not (GameTooltip:IsShown() and Minimap:IsMouseOver()) then
		lastTip = nil
		return
	end
	local first, lines = GameTooltipTextLeft1:GetText(), GameTooltip:NumLines()
	if first == lastTip and lines == lastTipLines then return end
	lastTip, lastTipLines = first, lines
	local owner = GameTooltip:GetOwner()
	if debug then
		ns:Print("hover: tooltip owner %s (parent %s), Find Minerals %s, %d lines:",
			FrameName(owner), FrameName(owner and owner.GetParent and owner:GetParent()),
			tracking and "on" or "off", lines)
		for i = 1, lines do
			print(("  %d: %s"):format(i, (_G["GameTooltipTextLeft" .. i]:GetText() or ""):gsub("|", "||")))
		end
	end
	-- Only the minimap's own tooltip for tracking dots. Forever shows it owned
	-- by UIParent; other addons' minimap pins own their tooltips themselves.
	if owner ~= Minimap and owner ~= UIParent then return end
	if GameTooltip:GetUnit() or not (tracking and ns.db.settings.recordSeen) then return end

	local names
	for i = 1, lines do
		local text = _G["GameTooltipTextLeft" .. i]:GetText()
		-- several dots under the cursor are listed one per line, sometimes in one string
		for line in (text or ""):gmatch("[^\n]+") do
			local name = CleanLine(line)
			if ns.NODES[name] then
				names = names or {}
				names[#names + 1] = name
			end
		end
	end
	if not names then return end

	local mapID, px, py = ns:PlayerMapPos()
	local b = mapID and ns:Basis(mapID)
	if not b then return end
	local wx, wy, inst = ns:MapToWorld(mapID, px, py)
	local cx, cy = GetCursorPosition()
	local es = Minimap:GetEffectiveScale()
	local mx, my = Minimap:GetCenter()
	local scale = Scale()
	local x, y = (cx / es - mx) / scale, (cy / es - my) / scale -- yards, screen right / up
	if Rotating() then
		local f = GetPlayerFacing and GetPlayerFacing() or 0
		local fc, fs = cos(f), sin(f)
		x, y = x * fc - y * fs, x * fs + y * fc -- undo the minimap rotation
	end
	local nwx, nwy = ns:Offset(b, wx, wy, x, -y)
	local nx, ny = ns:WorldToMap(b, nwx, nwy)
	local slop = HOVER_SLOP_PX / scale -- yards the cursor can be off the dot
	if debug then
		local _, yardR = Scale()
		ns:Print("  cursor %.0f yd east, %.0f yd north of you; minimap %.0f px wide = %.0f yd (%s, zoom %d)",
			x, y, Minimap:GetWidth(), yardR * 2, indoors and "indoor" or "outdoor", Minimap:GetZoom())
	end
	for _, name in ipairs(names) do ns:RecordSeen(name, nwx, nwy, inst, mapID, nx, ny, slop) end
end

---------------------------------------------------------------------------
-- Driver: the tick only runs while minimap pins or hover recording are on.
---------------------------------------------------------------------------
local ticker = CreateFrame("Frame")
ticker:Hide()
local elapsed = 0
ticker:SetScript("OnUpdate", function(_, dt)
	elapsed = elapsed + dt
	if elapsed < TICK then return end
	elapsed = 0
	local s = ns.db.settings
	if debug or (tracking and s.recordSeen) then CheckHover() end
	if s.minimapPins then Update() end
end)

local function UpdateActive()
	local s = ns.db.settings
	ticker:SetShown(s.minimapPins or debug or (tracking and s.recordSeen))
	if not s.minimapPins then HidePins(1) end
	viewStale = true
end

local function UpdateTracking()
	tracking = FindMineralsActive()
	UpdateActive()
end

function ns:ToggleHoverDebug()
	debug = not debug
	self.hoverDebug = debug
	UpdateTracking()
	if not debug then return self:Print("hover debug off.") end
	self:Print("hover debug on: hover minimap dots and their tooltips print here. /vk debug again to stop.")
	self:Print("Find Minerals detected: %s. Minimap frame: %s.", tracking and "yes" or "no", FrameName(Minimap))
	if C_Minimap and C_Minimap.GetNumTrackingTypes and C_Minimap.GetTrackingInfo then
		for i = 1, C_Minimap.GetNumTrackingTypes() do
			local name, _, active, _, _, spellID = C_Minimap.GetTrackingInfo(i)
			if type(name) == "table" then name, active, spellID = name.name, name.active, name.spellID end
			if active then print(("  active tracking: %s (spell %s)"):format(tostring(name), tostring(spellID))) end
		end
	elseif GetTrackingTexture then
		print("  tracking texture: " .. tostring(GetTrackingTexture()))
	end
end

ns:On("PLAYER_ENTERING_WORLD", function()
	UpdateIndoors()
	UpdateTracking()
end)
ns:On("MINIMAP_UPDATE_ZOOM", UpdateIndoors)
ns:On("MINIMAP_UPDATE_TRACKING", UpdateTracking)
ns:On("VK_DATA", function()
	scanStale = true
	if ns.db then UpdateActive() end
end)
ns:On("VK_STYLE", function()
	scanStale, viewStale = true, true -- freshness decides rim pins
end)
