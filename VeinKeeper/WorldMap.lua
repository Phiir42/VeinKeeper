-- World map pins: a MapCanvas data provider that projects every saved spot
-- onto whatever map is open (so spots near a border show on both zones, and
-- on continent maps too).
local _, ns = ...

local TEMPLATE = "VeinKeeperPinTemplate"

local function Style(pin, spot)
	ns:StylePin(pin, spot)
	local size = ns.db.settings.worldSize
	pin:SetSize(size, size)
end

---------------------------------------------------------------------------
-- Pin mixin. MapCanvasMixin:AcquirePin calls OnLoad itself and routes mouse
-- scripts to the OnMouse*/OnClick methods; setting those scripts directly
-- trips its assert.
---------------------------------------------------------------------------
VeinKeeperPinMixin = CreateFromMixins(MapCanvasPinMixin)

function VeinKeeperPinMixin:OnLoad()
	self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI")
	self:SetScalingLimits(1, 1.0, 1.3)
	ns:CreatePinTextures(self)
end

function VeinKeeperPinMixin:OnAcquired(spot, x, y)
	self:SetPosition(x, y)
	Style(self, spot)
end

function VeinKeeperPinMixin:OnMouseEnter()
	ns:ShowTooltip(self, self.spot, ns:Overlapping(self, self:GetMap():EnumeratePinsByTemplate(TEMPLATE)))
end
function VeinKeeperPinMixin:OnMouseLeave() GameTooltip:Hide() end
function VeinKeeperPinMixin:OnClick(button)
	-- pins swallow clicks, so keep the map's right-click zoom-out working
	if button == "RightButton" and not IsShiftKeyDown() then
		local map = self:GetMap()
		if map and map.NavigateToParentMap then map:NavigateToParentMap() end
		return
	end
	ns:PinClick(self, button)
end

-- AcquirePin calls CheckMouseButtonPassthrough, which calls the protected
-- Frame:SetPassThroughButtons (ADDON_ACTION_BLOCKED from addon code). These
-- pins don't need pass-through, so shadow both (as HandyNotes does).
function VeinKeeperPinMixin:SetPassThroughButtons() end
function VeinKeeperPinMixin:CheckMouseButtonPassthrough() end

---------------------------------------------------------------------------
-- Data provider
---------------------------------------------------------------------------
local provider = CreateFromMixins(MapCanvasDataProviderMixin)
local stale = true -- data changed while the map was closed

local function Restyle()
	for pin in WorldMapFrame:EnumeratePinsByTemplate(TEMPLATE) do
		if pin.spot then Style(pin, pin.spot) end
	end
end

function provider:RemoveAllData()
	self:GetMap():RemoveAllPinsByTemplate(TEMPLATE)
end

local MapType = Enum and Enum.UIMapType or {}
local WORLD, CONTINENT = MapType.World or 1, MapType.Continent or 2

-- The continent map a zone map is on (cached; false if none).
local continentOf = {}
local function ContinentOf(mapID)
	local c = continentOf[mapID]
	if c == nil then
		c = false
		local id = mapID
		while id and id > 0 do
			local info = C_Map.GetMapInfo(id)
			if not info then break end
			if info.mapType == CONTINENT then c = id break end
			id = info.parentMapID
		end
		continentOf[mapID] = c
	end
	return c or nil
end

-- The World map shows each continent at its own scale, so no single
-- projection fits: place each spot on its continent's map, then put that
-- map where the World map draws the continent.
local function WorldPins(map, worldID)
	if not C_Map.GetMapRectOnMap then return end
	local rects = {}
	for _, spot in ipairs(ns.db.spots) do
		local cont = spot.wx and ns:IsShown(spot) and ContinentOf(spot.map)
		local b = cont and ns:Basis(cont)
		if b and b.inst == spot.inst then
			local r = rects[cont]
			if r == nil then
				local minX, maxX, minY, maxY = C_Map.GetMapRectOnMap(cont, worldID)
				r = minX and maxX > minX and maxY > minY and { minX, maxX, minY, maxY } or false
				rects[cont] = r
			end
			if r then
				local cx, cy = ns:WorldToMap(b, spot.wx, spot.wy)
				if cx >= 0 and cx <= 1 and cy >= 0 and cy <= 1 then
					map:AcquirePin(TEMPLATE, spot, r[1] + cx * (r[2] - r[1]), r[3] + cy * (r[4] - r[3]))
				end
			end
		end
	end
end

-- MapCanvas calls this with fromOnShow = true every time the map opens; if
-- nothing changed while it was closed, recolouring the pins is enough.
function provider:RefreshAllData(fromOnShow)
	if fromOnShow and not stale then return Restyle() end
	stale = false
	self:RemoveAllData()
	if not ns.db.settings.worldPins then return end
	local map = self:GetMap()
	local mapID = map:GetMapID()
	if not mapID then return end
	local info = C_Map.GetMapInfo(mapID)
	if mapID == 947 or (info and info.mapType and info.mapType <= WORLD) then
		return WorldPins(map, mapID)
	end
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
	if provider:GetMap() or not (WorldMapFrame and WorldMapFrame.AddDataProvider) then return end
	WorldMapFrame:AddDataProvider(provider)
end

ns:On("PLAYER_LOGIN", Attach)
ns:On("ADDON_LOADED", function(name)
	if name == "Blizzard_WorldMap" then Attach() end
end)

ns:On("VK_DATA", function()
	if provider:GetMap() and WorldMapFrame:IsShown() then provider:RefreshAllData() else stale = true end
end)

ns:On("VK_STYLE", function()
	if provider:GetMap() and WorldMapFrame:IsShown() then Restyle() end
end)
