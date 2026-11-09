local _, ns = ...

local TEMPLATE = "VeinKeeperPinTemplate"

---------------------------------------------------------------------------
-- Shared pin look (used by the minimap too)
---------------------------------------------------------------------------
-- ringOnly: draw just the freshness ring with an empty centre, so a Find
-- Minerals blip underneath shows through it (used on the minimap).
function ns:StylePin(pin, spot, ringOnly)
	pin.spot = spot
	local icon, isItem = self:NodeIcon(self:DisplayOre(spot))
	pin.icon:SetTexture(icon)
	-- item icons have a baked-in border; crop it so the round mask shows only the ore
	if isItem then
		pin.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	else
		pin.icon:SetTexCoord(0, 1, 0, 1)
	end
	pin.icon:SetShown(not ringOnly)
	-- the ring shows freshness: red = just mined, yellow = soon, green = likely back
	local r, g, b = self:Freshness(spot)
	pin.ring:SetVertexColor(r, g, b, 1)
	local ok = self:CanMine(spot)
	pin.icon:SetDesaturated(not ok)
	pin:SetAlpha(ok and 1 or 0.55)
end

function ns:CreatePinTextures(pin)
	pin.icon = pin:CreateTexture(nil, "ARTWORK")
	pin.icon:SetPoint("TOPLEFT", 1, -1)
	pin.icon:SetPoint("BOTTOMRIGHT", -1, 1)
	if pin.CreateMaskTexture then
		local mask = pin:CreateMaskTexture()
		mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		mask:SetAllPoints(pin.icon)
		pin.icon:AddMaskTexture(mask)
	end
	pin.ring = pin:CreateTexture(nil, "OVERLAY")
	pin.ring:SetAllPoints()
	pin.ring:SetTexture(self.RING)
end

local function SetWaypoint(spot)
	local name = ns:DisplayOre(spot)
	if TomTom and TomTom.AddWaypoint then
		TomTom:AddWaypoint(spot.map, spot.x, spot.y, { title = name, persistent = false })
		return
	end
	if C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then
		local ok = pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(spot.map, spot.x, spot.y))
		if ok and C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
			C_SuperTrack.SetSuperTrackedUserWaypoint(true)
		end
		if ok then return end
	end
	ns:Print("waypoint at %s %.1f, %.1f (install TomTom for an arrow).", name, spot.x * 100, spot.y * 100)
end

function ns:PinClick(pin, button)
	local spot = pin.spot
	if not spot then return end
	if button == "RightButton" and IsShiftKeyDown() then
		GameTooltip:Hide()
		self:Forget(spot)
		self:Print("forgot that %s spot.", self:DisplayOre(spot))
	elseif button == "LeftButton" then
		SetWaypoint(spot)
	end
end

---------------------------------------------------------------------------
-- World map pin
---------------------------------------------------------------------------
VeinKeeperPinMixin = CreateFromMixins(MapCanvasPinMixin)

-- MapCanvasMixin:AcquirePin calls OnLoad itself and wires OnEnter/OnLeave/OnMouseUp
-- to the mixin methods below; setting those scripts here trips its assert.
function VeinKeeperPinMixin:OnLoad()
	self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI")
	self:SetScalingLimits(1, 1.0, 1.3)
	ns:CreatePinTextures(self)
end

function VeinKeeperPinMixin:OnMouseEnter()
	ns:ShowTooltip(self, self.spot)
end

function VeinKeeperPinMixin:OnMouseLeave()
	GameTooltip:Hide()
end

function VeinKeeperPinMixin:OnClick(button)
	ns:PinClick(self, button)
end

function VeinKeeperPinMixin:OnAcquired(spot, x, y)
	self:SetPosition(x, y)
	ns:StylePin(self, spot)
end

---------------------------------------------------------------------------
-- Data provider: projects every saved spot onto whatever map is open,
-- so spots show on neighbouring zones near borders and on continent maps.
---------------------------------------------------------------------------
local provider = CreateFromMixins(MapCanvasDataProviderMixin)

function provider:RemoveAllData()
	self:GetMap():RemoveAllPinsByTemplate(TEMPLATE)
end

function provider:RefreshAllData()
	self:RemoveAllData()
	if not ns.db or not ns.db.settings.worldPins then return end
	local map = self:GetMap()
	local mapID = map:GetMapID()
	if not mapID then return end
	local b = ns:Basis(mapID)
	for _, spot in ipairs(ns.db.spots) do
		if ns:IsShown(spot) then
			local x, y
			if b and spot.wx and spot.inst == b.inst then
				x, y = ns:WorldToMap(b, spot.wx, spot.wy)
			elseif spot.map == mapID then
				x, y = spot.x, spot.y
			end
			if x and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
				map:AcquirePin(TEMPLATE, spot, x, y)
			end
		end
	end
end

function provider:OnMapChanged()
	self:RefreshAllData()
end

local function Attach()
	if provider.attached or not WorldMapFrame or not WorldMapFrame.AddDataProvider then return end
	provider.attached = true
	WorldMapFrame:AddDataProvider(provider)
end

local function Refresh()
	if provider.attached and WorldMapFrame:IsShown() then provider:RefreshAllData() end
end
table.insert(ns.listeners, Refresh)

-- freshness colours change over time: recolour the open map's pins every 15s
-- (cheap; the full rebuild only happens on map or data changes)
local elapsed = 0
local ticker = CreateFrame("Frame")
ticker:SetScript("OnUpdate", function(_, dt)
	elapsed = elapsed + dt
	if elapsed < 15 then return end
	elapsed = 0
	if provider.attached and WorldMapFrame:IsShown() then
		for pin in WorldMapFrame:EnumeratePinsByTemplate(TEMPLATE) do
			if pin.spot then ns:StylePin(pin, pin.spot) end
		end
	end
end)

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(_, event, name)
	if event == "PLAYER_LOGIN" or name == "Blizzard_WorldMap" then Attach() end
end)
