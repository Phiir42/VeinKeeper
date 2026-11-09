-- Buttons: the minimap button, the world map button and the addon
-- compartment entry (the minimap's addon list, which EllesmereUI also shows).
local _, ns = ...

local function RoundButton(name, parent)
	local b = CreateFrame("Button", name, parent)
	b:SetSize(31, 31)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
	local bg = b:CreateTexture(nil, "BACKGROUND")
	bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	bg:SetSize(20, 20)
	bg:SetPoint("CENTER")
	local icon = b:CreateTexture(nil, "ARTWORK")
	icon:SetTexture("Interface\\Icons\\Trade_Mining")
	icon:SetSize(18, 18)
	icon:SetPoint("CENTER")
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	local border = b:CreateTexture(nil, "OVERLAY")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetSize(53, 53)
	border:SetPoint("TOPLEFT")
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return b
end

local function Tooltip(owner, rightClick, extra)
	GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
	GameTooltip:AddLine("VeinKeeper")
	GameTooltip:AddLine(#ns.db.spots .. " spots saved", 1, 1, 1)
	local only = ns.db.settings.only
	if only then GameTooltip:AddLine("Showing only " .. ns:OreLabel(only), 1, 0.82, 0) end
	GameTooltip:AddLine("Left-click: settings", 0.7, 0.7, 0.7)
	GameTooltip:AddLine("Right-click: " .. rightClick, 0.7, 0.7, 0.7)
	if extra then GameTooltip:AddLine(extra, 0.7, 0.7, 0.7) end
	GameTooltip:Show()
end

---------------------------------------------------------------------------
-- Minimap button: a named Button parented to Minimap, so minimap button
-- collectors pick it up. Once a collector re-parents it, VeinKeeper leaves
-- its position alone. Created at ADDON_LOADED so collectors that rescan
-- after every addon load find it.
---------------------------------------------------------------------------
local minimapButton

local function OwnedByMinimap()
	return minimapButton:GetParent() == Minimap
end

local function PlaceMinimapButton()
	if not OwnedByMinimap() then return end
	local a = math.rad(ns.db.settings.buttonAngle)
	local r = Minimap:GetWidth() / 2 + 5
	minimapButton:ClearAllPoints()
	minimapButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

local function DragUpdate()
	local mx, my = Minimap:GetCenter()
	local cx, cy = GetCursorPosition()
	local sc = Minimap:GetEffectiveScale()
	ns.db.settings.buttonAngle = math.deg(math.atan2(cy / sc - my, cx / sc - mx))
	PlaceMinimapButton()
end

local function CreateMinimapButton()
	local b = RoundButton("VeinKeeperMinimapButton", Minimap)
	minimapButton = b
	b:SetFrameStrata("MEDIUM")
	b:SetFrameLevel(8)
	b:RegisterForDrag("LeftButton")
	b:SetScript("OnClick", function(_, button)
		if button == "RightButton" then ns:ToggleAllPins() else ns:ToggleSettings() end
	end)
	b:SetScript("OnEnter", function(self)
		Tooltip(self, "show / hide all pins", OwnedByMinimap() and "Drag: move" or nil)
	end)
	b:SetScript("OnDragStart", function(self)
		if OwnedByMinimap() then self:SetScript("OnUpdate", DragUpdate) end
	end)
	b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
	PlaceMinimapButton()
end

-- Only at load and when the setting changes: repeatedly re-showing a
-- collected button upsets collectors.
function ns:UpdateMinimapButton()
	if self.db.settings.button then
		if not minimapButton then CreateMinimapButton() end
		if not minimapButton:IsShown() then minimapButton:Show() end
	elseif minimapButton and minimapButton:IsShown() then
		minimapButton:Hide()
	end
end

---------------------------------------------------------------------------
-- World map button (top right): left-click settings, right-click the ore
-- filter menu.
---------------------------------------------------------------------------
local mapButton

local function CreateMapButton()
	if not WorldMapFrame then return end
	local b = RoundButton("VeinKeeperWorldMapButton", WorldMapFrame)
	mapButton = b
	b:SetFrameStrata(WorldMapFrame:GetFrameStrata())
	b:SetFrameLevel(2000) -- above the map canvas and its pins
	b:SetPoint("TOPRIGHT", WorldMapFrame.ScrollContainer or WorldMapFrame, "TOPRIGHT", -6, -6)
	b:SetScript("OnClick", function(self, button)
		if button == "RightButton" then
			GameTooltip:Hide()
			ns:ShowFilterMenu(self, true)
		else
			ns:ToggleSettings()
		end
	end)
	b:SetScript("OnEnter", function(self) Tooltip(self, "ore filter, show / hide pins") end)
end

function ns:UpdateMapButton()
	if self.db.settings.mapButton then
		if not mapButton then CreateMapButton() end
		if mapButton then mapButton:Show() end
	elseif mapButton then
		mapButton:Hide()
	end
end

ns:On("VK_LOADED", function() ns:UpdateMinimapButton() end)
ns:On("PLAYER_LOGIN", function() ns:UpdateMapButton() end)

---------------------------------------------------------------------------
-- Addon compartment, registered through the TOC's AddonCompartmentFunc*
-- fields, so these are globals. The first argument is the addon name or the
-- menu entry frame depending on the caller; the mouse button comes second.
---------------------------------------------------------------------------
function VeinKeeper_OnCompartmentClick(_, button)
	if button == "RightButton" then ns:ToggleAllPins() else ns:ToggleSettings() end
end

function VeinKeeper_OnCompartmentEnter(addonOrFrame, frame)
	local owner = type(addonOrFrame) == "table" and addonOrFrame or frame
	if type(owner) == "table" then Tooltip(owner, "show / hide all pins") end
end

function VeinKeeper_OnCompartmentLeave()
	GameTooltip:Hide()
end
