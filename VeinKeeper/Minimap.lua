local _, ns = ...

local sqrt, abs, cos, sin, floor = math.sqrt, math.abs, math.cos, math.sin, math.floor

-- minimap diameter in yards per zoom level
local OUTDOOR = { [0] = 466 + 2 / 3, 400, 333 + 1 / 3, 266 + 2 / 3, 200, 133 + 1 / 3 }
local INDOOR = { [0] = 300, 240, 180, 120, 80, 50 }
local SCAN_YARDS = 2500 -- only spots this close are considered at all

local pins = {}
local candidates = {}
local edge = {}
local lastScan, lastInst = 0, nil
local function ByDistance(a, c) return a.d < c.d end

-- Is the minimap using its indoor zoom table? IsIndoors() can disagree with the
-- minimap right after a zone change, so compare the zoom CVar instead (the
-- approach HereBeDragons-Pins uses).
local indoors = false
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
end

local function GetPin(i)
	local p = pins[i]
	if p then return p end
	p = CreateFrame("Frame", nil, Minimap)
	p.isMinimap = true
	p:SetSize(14, 14)
	p:SetFrameLevel(Minimap:GetFrameLevel() + 5)
	ns:CreatePinTextures(p)
	p.text = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	p.text:SetPoint("TOP", p, "BOTTOM", 0, -1)
	p:EnableMouse(true)
	p:SetScript("OnEnter", function(self) ns:ShowTooltip(self, self.spot) end)
	p:SetScript("OnLeave", function() GameTooltip:Hide() end)
	p:SetScript("OnMouseUp", function(self, button) ns:PinClick(self, button) end)
	pins[i] = p
	return p
end

local function Scan(wx, wy, inst)
	wipe(candidates)
	local r2 = SCAN_YARDS * SCAN_YARDS
	for _, s in ipairs(ns.db.spots) do
		if s.wx and s.inst == inst and ns:IsShown(s) then
			local dx, dy = s.wx - wx, s.wy - wy
			if dx * dx + dy * dy < r2 then candidates[#candidates + 1] = s end
		end
	end
end

-- Is Find Minerals the active tracking? Addons can't see tracking blips, so when
-- it is, in-range pins become hollow rings: if the vein is up, the game's own
-- yellow dot shows inside the ring.
local FIND_MINERALS = 2580
local tracking = false
local function UpdateTracking()
	tracking = false
	if C_Minimap and C_Minimap.GetNumTrackingTypes and C_Minimap.GetTrackingInfo then
		local findName = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(FIND_MINERALS)
			or (GetSpellInfo and GetSpellInfo(FIND_MINERALS))
		for i = 1, C_Minimap.GetNumTrackingTypes() do
			local info = C_Minimap.GetTrackingInfo(i)
			if type(info) == "table" and info.active
				and (info.spellID == FIND_MINERALS or (findName and info.name == findName)) then
				tracking = true
				return
			end
		end
	elseif GetTrackingTexture and GetSpellTexture then
		local tex = GetTrackingTexture()
		tracking = tex ~= nil and tex == GetSpellTexture(FIND_MINERALS)
	end
end

local function Place(p, spot, x, y, label, ringOnly)
	ns:StylePin(p, spot, ringOnly)
	-- a hollow ring is drawn a little larger so the tracking dot fits inside it
	local size = ns.db.settings.minimapSize + (ringOnly and 4 or 0)
	p:SetSize(size, size)
	p:ClearAllPoints()
	p:SetPoint("CENTER", Minimap, "CENTER", x, y)
	p.text:SetText(label or "")
	p:Show()
end

local function Update()
	local used = 0
	local s = ns.db.settings
	if s.minimapPins and Minimap:IsVisible() then
		local wx, wy, inst, b = ns:PlayerWorld()
		if wx then
			local now = GetTime()
			if now - lastScan > 2 or inst ~= lastInst then
				lastScan, lastInst = now, inst
				Scan(wx, wy, inst)
			end

			local sizes = indoors and INDOOR or OUTDOOR
			local yardR = (sizes[Minimap:GetZoom()] or sizes[0]) / 2
			local pxR = Minimap:GetWidth() / 2
			local scale = pxR / yardR
			local square = GetMinimapShape and GetMinimapShape() == "SQUARE"
			local rotate = GetCVar("rotateMinimap") == "1"
			local fc, fs = 1, 0
			if rotate then
				local facing = GetPlayerFacing and GetPlayerFacing()
				if facing then fc, fs = cos(facing), sin(facing) end
			end

			local mode = s.inRange -- "ring", "hide" or "icon"
			local ringOnly = tracking and mode == "ring"
			local hideInRange = tracking and mode == "hide"

			local nEdge = 0
			for _, spot in ipairs(candidates) do
				local east, south = ns:Delta(b, wx, wy, spot.wx, spot.wy)
				local x, y = east, -south -- y up = north
				if rotate then x, y = x * fc + y * fs, -x * fs + y * fc end
				local inside
				if square then
					inside = abs(x) < yardR * 0.94 and abs(y) < yardR * 0.94
				else
					inside = x * x + y * y < (yardR * 0.94) ^ 2
				end
				if inside then
					if not hideInRange then
						used = used + 1
						Place(GetPin(used), spot, x * scale, y * scale, nil, ringOnly)
					end
				else
					nEdge = nEdge + 1
					local e = edge[nEdge] or {}
					edge[nEdge] = e
					e.spot, e.x, e.y, e.d = spot, x, y, sqrt(x * x + y * y)
				end
			end

			if s.edgeCount > 0 and nEdge > 0 then
				for i = #edge, nEdge + 1, -1 do edge[i] = nil end
				table.sort(edge, ByDistance)
				for i = 1, math.min(s.edgeCount, nEdge) do
					local e = edge[i]
					local k
					if square then
						k = (pxR - 7) / math.max(abs(e.x), abs(e.y))
					else
						k = (pxR - 7) / e.d
					end
					used = used + 1
					local p = GetPin(used)
					Place(p, e.spot, e.x * k, e.y * k, floor(e.d) .. "yd")
					p:SetAlpha(p:GetAlpha() * 0.8)
				end
			end
		end
	end
	for i = used + 1, #pins do pins[i]:Hide() end
end

local throttle = 0
local updater = CreateFrame("Frame")
updater:SetScript("OnUpdate", function(_, dt)
	throttle = throttle + dt
	if throttle < 0.1 then return end
	throttle = 0
	if ns.db then Update() end
end)

table.insert(ns.listeners, function() lastScan = 0 end)

local zoomWatch = CreateFrame("Frame")
zoomWatch:RegisterEvent("MINIMAP_UPDATE_ZOOM")
zoomWatch:RegisterEvent("PLAYER_ENTERING_WORLD")
zoomWatch:SetScript("OnEvent", UpdateIndoors)

local trackWatch = CreateFrame("Frame")
trackWatch:RegisterEvent("MINIMAP_UPDATE_TRACKING")
trackWatch:RegisterEvent("PLAYER_ENTERING_WORLD")
trackWatch:SetScript("OnEvent", UpdateTracking)

---------------------------------------------------------------------------
-- Minimap button: left-click opens settings, right-click toggles all pins,
-- drag to move. It's a named Button parented to Minimap, so minimap button
-- collectors (EllesmereUI's flyout, MinimapButtonButton, ...) pick it up.
-- Once a collector has re-parented it, VeinKeeper leaves its position alone.
---------------------------------------------------------------------------
local button

local function OwnedByMinimap()
	return button and button:GetParent() == Minimap
end

local function PlaceButton()
	if not OwnedByMinimap() then return end
	local a = math.rad(ns.db.settings.buttonAngle)
	local r = Minimap:GetWidth() / 2 + 5
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", cos(a) * r, sin(a) * r)
end

local function CreateButton()
	button = CreateFrame("Button", "VeinKeeperMinimapButton", Minimap)
	button:SetSize(31, 31)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(8)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:RegisterForDrag("LeftButton")
	button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	local bg = button:CreateTexture(nil, "BACKGROUND")
	bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	bg:SetSize(20, 20)
	bg:SetPoint("CENTER")
	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetTexture("Interface\\Icons\\Trade_Mining")
	icon:SetSize(18, 18)
	icon:SetPoint("CENTER")
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	button.icon = icon
	local border = button:CreateTexture(nil, "OVERLAY")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetSize(53, 53)
	border:SetPoint("TOPLEFT")

	button:SetScript("OnClick", function(_, btn)
		if btn == "RightButton" then
			ns:ToggleAllPins()
		else
			ns:ToggleSettings()
		end
	end)
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine("VeinKeeper")
		GameTooltip:AddLine(#ns.db.spots .. " spots saved", 1, 1, 1)
		GameTooltip:AddLine("Left-click: settings", 0.7, 0.7, 0.7)
		GameTooltip:AddLine("Right-click: show / hide all pins", 0.7, 0.7, 0.7)
		if OwnedByMinimap() then GameTooltip:AddLine("Drag: move", 0.7, 0.7, 0.7) end
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)
	button:SetScript("OnDragStart", function(self)
		if not OwnedByMinimap() then return end -- a collector owns it now
		self:SetScript("OnUpdate", function()
			local mx, my = Minimap:GetCenter()
			local cx, cy = GetCursorPosition()
			local sc = Minimap:GetEffectiveScale()
			ns.db.settings.buttonAngle = math.deg(math.atan2(cy / sc - my, cx / sc - mx))
			PlaceButton()
		end)
	end)
	button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
	PlaceButton()
end

-- Only called at login and when the "minimap button" setting changes, never on
-- every data change: repeatedly re-showing a collected button upsets collectors.
function ns:UpdateMinimapButton()
	if not self.db then return end
	if self.db.settings.button then
		if not button then CreateButton() end
		if not button:IsShown() then button:Show() end
	elseif button and button:IsShown() then
		button:Hide()
	end
end
