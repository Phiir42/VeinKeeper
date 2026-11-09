-- Minimap pins: saved spots in view, the nearest far spots on the rim, and
-- saving veins whose Find Minerals dot you hover.
--
-- Cost: a 10 Hz timer (per-frame work only while a dot's tooltip is up, to
-- sample the cursor) that returns at once unless
-- you moved, turned (rotating minimap), zoomed or something changed. Saved spots are only searched again
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
-- The minimap keeps separate outdoor and indoor zoom levels; whichever one it
-- shows tells which scale it uses. IsIndoors() can lag behind the minimap
-- after a zone change, so it's only the fallback for when both are equal.
-- (No probing with Minimap:SetZoom: that fires MINIMAP_UPDATE_ZOOM again.)
local function UpdateIndoors()
	local zoom = Minimap:GetZoom()
	local out, inside = tonumber(GetCVar("minimapZoom")), tonumber(GetCVar("minimapInsideZoom"))
	if out ~= inside then
		indoors = zoom == inside
	else
		indoors = IsIndoors() and true or false
	end
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
-- Pins in use are always pins[1..n], the rest hidden.
local function ShownPins()
	local i = 0
	return function()
		i = i + 1
		local p = pins[i]
		if p and p:IsShown() then return p end
	end
end

local function GetPin(i)
	local p = pins[i]
	if p then return p end
	p = CreateFrame("Frame", nil, Minimap)
	p.isMinimap = true
	p:SetFrameLevel(Minimap:GetFrameLevel() + 5)
	ns:CreatePinTextures(p)
	p.label = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	p.label:SetPoint("TOP", p, "BOTTOM", 0, -1)
	p:SetScript("OnEnter", function(self) ns:ShowTooltip(self, self.spot, ns:Overlapping(self, ShownPins())) end)
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

-- The tooltip shows with the cursor anywhere within ~HOVER_SLOP_PX of the
-- dot, so a single cursor position can be ~30 yd off when zoomed out. While
-- the same tooltip is up, the world positions under the cursor are collected
-- into a box; the box's centre is recorded when the tooltip goes away.
-- Moving the cursor across the dot gives its centre.
local hover -- { names, inst, mapID, b, slop, x0, x1, y0, y1, n }
local hoverNames -- node names in the current tooltip, or false

local sampler -- samples the cursor every frame, only while a dot's tooltip is up

local function Flush()
	local h = hover
	hover = nil
	if sampler then sampler:Hide() end
	if not h then return end
	-- wider than a dot's tooltip reaches, or the scale changed under it:
	-- the tooltip outlived its dot, so this isn't a real hover
	local spread = max(h.x1 - h.x0, h.y1 - h.y0)
	if h.bad or spread > 2 * h.slop then
		if debug then
			ns:Print("  discarded: %s", h.bad or ("%d samples over %.0f yd, too spread out"):format(h.n, spread))
		end
		return
	end
	local wx, wy = (h.x0 + h.x1) / 2, (h.y0 + h.y1) / 2
	local nx, ny = ns:WorldToMap(h.b, wx, wy)
	-- the box's centre is the dot only if the cursor crossed it; otherwise
	-- it's anywhere within slop, too rough to correct a mined spot with
	local crossed = spread >= 0.6 * h.slop
	local err = crossed and h.slop * 0.4 or nil
	if debug then
		ns:Print("  recorded from %d samples over a %.0f x %.0f yd box%s", h.n, h.x1 - h.x0, h.y1 - h.y0,
			crossed and "" or " (didn't cross the dot: position too rough to move a mined spot)")
	end
	for _, name in ipairs(h.names) do ns:RecordSeen(name, wx, wy, h.inst, h.mapID, nx, ny, h.slop, err) end
end

-- Node names in the tooltip if it's the minimap's own tracking-dot tooltip.
-- Forever shows that owned by UIParent; other addons' pins own theirs.
local function ReadTooltip(lines)
	local owner = GameTooltip:GetOwner()
	if debug then
		ns:Print("hover: tooltip owner %s, Find Minerals %s, %d lines:",
			FrameName(owner), tracking and "on" or "off", lines)
		for i = 1, lines do
			print(("  %d: %s"):format(i, (_G["GameTooltipTextLeft" .. i]:GetText() or ""):gsub("|", "||")))
		end
	end
	if owner ~= Minimap and owner ~= UIParent then return false end
	if GameTooltip:GetUnit() or not tracking then return false end
	local names
	for i = 1, lines do
		-- several dots under the cursor are listed one per line, sometimes in one string
		for line in (_G["GameTooltipTextLeft" .. i]:GetText() or ""):gmatch("[^\n]+") do
			local name = ns:NodeName(CleanLine(line))
			if name then
				names = names or {}
				names[#names + 1] = name
			end
		end
	end
	return names or false
end

-- The world position under the cursor on the minimap: hx, hy, inst, the
-- map basis and ID, pixels per yard, and the yards east / north of you.
local function CursorWorld()
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
	local hx, hy = ns:Offset(b, wx, wy, x, -y)
	return hx, hy, inst, b, mapID, scale, x, y
end

-- The saved spots at a Find Minerals dot, in a tooltip of VeinKeeper's own
-- under the game's (which redraws itself, wiping lines added to it).
-- Matched by distance, not by pin: a mined spot is where you stood, a few
-- yards off the dot, which is many pixels on a zoomed-in minimap.
local dotTip
local function Annotate(hx, hy, inst, _, _, scale)
	if not hx then return end
	local reach = max(10, 1.5 * HOVER_SLOP_PX / scale)
	local list
	for _, spot in ipairs(ns.db.spots) do
		if spot.wx and spot.inst == inst and ns:IsShown(spot) then
			local dx, dy = spot.wx - hx, spot.wy - hy
			local d = dx * dx + dy * dy
			if d < reach * reach then
				list = list or {}
				list[#list + 1] = { spot = spot, d = d }
			end
		end
	end
	if debug then ns:Print("  %d saved spots within %.0f yd of the cursor", list and #list or 0, reach) end
	if not list then return end
	table.sort(list, function(a, b) return a.d < b.d end)
	if not dotTip then
		dotTip = CreateFrame("GameTooltip", "VeinKeeperDotTooltip", UIParent, "GameTooltipTemplate")
		GameTooltip:HookScript("OnHide", function() dotTip:Hide() end)
	end
	dotTip:SetOwner(GameTooltip, "ANCHOR_NONE")
	dotTip:ClearAllPoints()
	dotTip:SetPoint("TOPLEFT", GameTooltip, "BOTTOMLEFT", 0, -2)
	dotTip:AddLine("VeinKeeper", 0.85, 0.63, 0.4)
	ns:AddSummaries(dotTip, list)
	dotTip:Show()
end

-- Rings let the mouse through to the game's dot, so they get no OnEnter:
-- find the ring under the cursor by position instead.
local function RingUnderCursor()
	local cx, cy = GetCursorPosition()
	for p in ShownPins() do
		if p.ringOnly then
			local s = p:GetEffectiveScale()
			local x, y = p:GetCenter()
			local r = p:GetWidth() / 2 + 2
			local dx, dy = cx / s - x, cy / s - y
			if dx * dx + dy * dy < r * r then return p end
		end
	end
end

local ringTip -- the ring whose tooltip VeinKeeper is showing

local function CheckHover()
	local over = Minimap:IsMouseOver()
	local ring = over and RingUnderCursor()
	local shown = GameTooltip:IsShown()
	local owner = shown and GameTooltip:GetOwner()
	if ringTip and ring ~= ringTip then
		if owner == ringTip then GameTooltip:Hide(); shown = false end
		ringTip = nil
	end
	-- a ring with no dot showing (the vein is down): VeinKeeper's own tooltip
	if ring and not shown then
		ringTip = ring
		ns:ShowTooltip(ring, ring.spot, ns:Overlapping(ring, ShownPins()), true)
		return
	end
	if not (shown and over) or (ringTip and owner == ringTip) then
		lastTip = nil
		return Flush()
	end
	local first, lines = GameTooltipTextLeft1:GetText(), GameTooltip:NumLines()
	if first ~= lastTip or lines ~= lastTipLines then
		Flush()
		if dotTip then dotTip:Hide() end
		hoverNames = ReadTooltip(lines)
		if hoverNames then Annotate(CursorWorld()) end
		lastTip, lastTipLines = first, lines
	end
	if not (hoverNames and ns.db.settings.recordSeen) then return end

	local hx, hy, inst, b, mapID, scale, x, y = CursorWorld()
	if not hx then return end
	local h = hover
	if not h or h.inst ~= inst then
		Flush()
		if not sampler then
			sampler = CreateFrame("Frame")
			sampler:SetScript("OnUpdate", function()
				local s = hover
				if not s or s.bad or not (GameTooltip:IsShown() and Minimap:IsMouseOver()) then return end
				-- only samples of this same tooltip, at the scale it began at
				if GameTooltipTextLeft1:GetText() ~= s.tip or GameTooltip:NumLines() ~= s.lines then return end
				if Minimap:GetZoom() ~= s.zoom or indoors ~= s.indoors then
					s.bad = "the minimap zoomed during the hover"
					return
				end
				local sx, sy, sinst = CursorWorld()
				if not sx or sinst ~= s.inst then return end
				s.n = s.n + 1
				s.x0, s.x1 = min(s.x0, sx), max(s.x1, sx)
				s.y0, s.y1 = min(s.y0, sy), max(s.y1, sy)
			end)
		end
		sampler:Show()
		hover = {
			names = hoverNames, inst = inst, mapID = mapID, b = b,
			slop = HOVER_SLOP_PX / scale, -- yards the cursor can be off the dot
			x0 = hx, x1 = hx, y0 = hy, y1 = hy, n = 1,
			tip = lastTip, lines = lastTipLines, zoom = Minimap:GetZoom(), indoors = indoors,
		}
		if debug then
			local _, yardR = Scale()
			ns:Print("  cursor %.0f yd east, %.0f yd north of you; minimap %.0f px = %.0f yd (zoom %d)",
				x, y, Minimap:GetWidth(), yardR * 2, Minimap:GetZoom())
		end
	end
end

---------------------------------------------------------------------------
-- Driver: the tick only runs while minimap pins or hover recording are on.
---------------------------------------------------------------------------
local ticker

local function Tick()
	local s, cpu = ns.db.settings, ns.cpu
	if debug or tracking then
		if cpu then ns:Timed("minimap: hover", CheckHover) else CheckHover() end
	end
	if s.minimapPins then
		if cpu then ns:Timed("minimap: pins", Update) else Update() end
	end
end

local function UpdateActive()
	local s = ns.db.settings
	local want = s.minimapPins or debug or (tracking and s.recordSeen)
	if want and not ticker then
		ticker = C_Timer.NewTicker(TICK, Tick)
	elseif not want and ticker then
		ticker:Cancel()
		ticker = nil
	end
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
ns:On("MINIMAP_UPDATE_ZOOM", function()
	UpdateIndoors()
	-- a dot's tooltip can stay up through a zoom while the scale changes
	-- under it: drop that hover, and ignore the tooltip until it changes
	hover, hoverNames = nil, false
	if sampler then sampler:Hide() end
end)
ns:On("ZONE_CHANGED_INDOORS", UpdateIndoors)
ns:On("MINIMAP_UPDATE_TRACKING", UpdateTracking)
ns:On("VK_DATA", function()
	scanStale = true
	if ns.db then UpdateActive() end
end)
ns:On("VK_STYLE", function()
	scanStale, viewStale = true, true -- freshness decides rim pins
end)
