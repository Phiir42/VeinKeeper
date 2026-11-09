local _, ns = ...

local floor = math.floor
local panel
local controls = {}
local nameCount = 0

-- Template children are created with "$parent..." names, so give every control
-- a unique global name rather than leaking names like "Text".
local function NextName(kind)
	nameCount = nameCount + 1
	return "VeinKeeperSettings" .. kind .. nameCount
end

local function RefreshControls()
	if not panel or not panel:IsShown() then return end
	for _, c in ipairs(controls) do c.Refresh() end
end

---------------------------------------------------------------------------
-- Controls
---------------------------------------------------------------------------
local function Header(parent, text, y)
	local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	fs:SetPoint("TOPLEFT", 16, y)
	fs:SetText(text)
end

local function Check(parent, label, key, y, onChange)
	local cb = CreateFrame("CheckButton", NextName("Check"), parent, "UICheckButtonTemplate")
	cb:SetPoint("TOPLEFT", 14, y)
	cb:SetSize(24, 24)
	local text = cb.Text or cb.text
	if not text then
		text = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
	end
	text:SetText(label)
	cb:SetScript("OnClick", function(self)
		ns.db.settings[key] = self:GetChecked() and true or false
		if onChange then onChange() end
		ns:Changed()
	end)
	cb.Refresh = function() cb:SetChecked(ns.db.settings[key] and true or false) end
	controls[#controls + 1] = cb
end

-- fmt formats the slider value; toStore/fromStore convert between slider units
-- and the saved setting (e.g. percent <-> 0-1 opacity); apply runs on change.
local function Slider(parent, label, key, y, minV, maxV, step, fmt, toStore, fromStore, apply)
	local name = NextName("Slider")
	local sl = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
	sl:SetPoint("TOPLEFT", 22, y)
	sl:SetWidth(276)
	sl:SetMinMaxValues(minV, maxV)
	sl:SetValueStep(step)
	if sl.SetObeyStepOnDrag then sl:SetObeyStepOnDrag(true) end
	-- hide the template's own labels (their keys differ between client versions)
	for _, k in ipairs({ "Low", "High", "Text" }) do
		local fs = sl[k] or _G[name .. k]
		if fs then fs:SetText("") fs:Hide() end
	end
	local title = sl:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	title:SetPoint("BOTTOMLEFT", sl, "TOPLEFT", 0, 3)
	title:SetText(label)
	local value = sl:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	value:SetPoint("BOTTOMRIGHT", sl, "TOPRIGHT", 0, 3)

	sl:SetScript("OnValueChanged", function(self, v)
		v = floor(v / step + 0.5) * step
		value:SetText(fmt(v))
		if self.refreshing then return end
		ns.db.settings[key] = toStore(v)
		if apply then apply() end
	end)
	sl.Refresh = function()
		sl.refreshing = true
		local v = fromStore(ns.db.settings[key])
		sl:SetValue(v)
		value:SetText(fmt(v))
		sl.refreshing = false
	end
	controls[#controls + 1] = sl
end

local IN_RANGE = { "ring", "hide", "icon" }
local IN_RANGE_LABEL = { ring = "Hollow ring", hide = "Hidden", icon = "Full icon" }

local function InRangeButton(parent, y)
	local label = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	label:SetPoint("TOPLEFT", 22, y)
	label:SetText("Nearby spots while Find Minerals is on:")
	local b = CreateFrame("Button", NextName("Button"), parent, "UIPanelButtonTemplate")
	b:SetSize(110, 22)
	b:SetPoint("TOPRIGHT", -18, y + 5)
	b:SetScript("OnClick", function()
		local cur = ns.db.settings.inRange
		local nextMode = IN_RANGE[1]
		for i, m in ipairs(IN_RANGE) do
			if m == cur then nextMode = IN_RANGE[i % #IN_RANGE + 1] end
		end
		ns.db.settings.inRange = nextMode
		b.Refresh()
	end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine("Find Minerals")
		GameTooltip:AddLine("Addons can't see tracking dots, so VeinKeeper can't tell whether a vein is up.", 1, 1, 1, true)
		GameTooltip:AddLine("Hollow ring: the game's yellow dot shows inside the ring when the vein is there.", 0.8, 0.8, 0.8, true)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	b.Refresh = function() b:SetText(IN_RANGE_LABEL[ns.db.settings.inRange] or ns.db.settings.inRange) end
	controls[#controls + 1] = b
end

---------------------------------------------------------------------------
-- Panel
---------------------------------------------------------------------------
local function pct(v) return v .. "%" end
local function toAlpha(v) return v / 100 end
local function fromAlpha(a) return floor((a or 1) * 100 + 0.5) end
local function same(v) return v end

local function CreatePanel()
	panel = CreateFrame("Frame", "VeinKeeperSettings", UIParent, "BasicFrameTemplateWithInset")
	panel:SetSize(330, 520)
	panel:SetPoint("CENTER")
	panel:SetFrameStrata("DIALOG")
	panel:SetToplevel(true)
	panel:SetClampedToScreen(true)
	panel:SetMovable(true)
	panel:EnableMouse(true)
	panel:RegisterForDrag("LeftButton")
	panel:SetScript("OnDragStart", panel.StartMoving)
	panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
	panel:SetScript("OnShow", RefreshControls)
	panel:Hide()
	tinsert(UISpecialFrames, "VeinKeeperSettings") -- Esc closes it

	local title = panel.TitleText
	if not title then
		title = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		title:SetPoint("TOP", 0, -5)
	end
	title:SetText("VeinKeeper")

	local restyle = function() ns:RestyleWorldPins() end
	local y = -34
	Header(panel, "Pins", y)
	Check(panel, "Show pins on the world map", "worldPins", y - 18)
	Check(panel, "Show pins on the minimap", "minimapPins", y - 42)
	Check(panel, "Use the game's ore icons", "gameIcons", y - 66)
	Check(panel, "Dim spots above my Mining skill", "skillDim", y - 90)

	y = y - 136
	Slider(panel, "World map pin opacity", "worldAlpha", y, 10, 100, 5, pct, toAlpha, fromAlpha, restyle)
	Slider(panel, "Minimap pin opacity", "minimapAlpha", y - 42, 10, 100, 5, pct, toAlpha, fromAlpha)
	Slider(panel, "Respawn timer (ring turns green after)", "readyMin", y - 84, 1, 60, 1,
		function(v) return v .. " min" end, same, same, restyle)
	Slider(panel, "Far spots shown on the minimap edge", "edgeCount", y - 126, 0, 10, 1,
		tostring, same, same)

	y = y - 170
	InRangeButton(panel, y)

	y = y - 34
	Header(panel, "Buttons", y)
	Check(panel, "Minimap button", "button", y - 18, function() ns:UpdateMinimapButton() end)
	Check(panel, "World map button", "mapButton", y - 42, function() ns:UpdateMapButton() end)

	local count = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	count:SetPoint("BOTTOMLEFT", 18, 14)
	controls[#controls + 1] = { Refresh = function() count:SetText(#ns.db.spots .. " spots saved  |  /vk help for commands") end }
end

function ns:ToggleSettings()
	if not panel then CreatePanel() end
	panel:SetShown(not panel:IsShown())
end

table.insert(ns.listeners, RefreshControls)

---------------------------------------------------------------------------
-- World map button (top-right of the map): left-click settings,
-- right-click show/hide world map pins
---------------------------------------------------------------------------
local mapButton

local function CreateMapButton()
	if mapButton or not WorldMapFrame then return end
	local anchor = WorldMapFrame.ScrollContainer or WorldMapFrame
	mapButton = CreateFrame("Button", "VeinKeeperWorldMapButton", WorldMapFrame)
	mapButton:SetSize(31, 31)
	mapButton:SetFrameStrata(WorldMapFrame:GetFrameStrata())
	mapButton:SetFrameLevel(2000) -- above the map canvas and its pins
	mapButton:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", -6, -6)
	mapButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	mapButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	local bg = mapButton:CreateTexture(nil, "BACKGROUND")
	bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	bg:SetSize(20, 20)
	bg:SetPoint("CENTER")
	local icon = mapButton:CreateTexture(nil, "ARTWORK")
	icon:SetTexture("Interface\\Icons\\Trade_Mining")
	icon:SetSize(18, 18)
	icon:SetPoint("CENTER")
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	local border = mapButton:CreateTexture(nil, "OVERLAY")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetSize(53, 53)
	border:SetPoint("TOPLEFT")

	mapButton:SetScript("OnClick", function(_, btn)
		if btn == "RightButton" then
			local s = ns.db.settings
			s.worldPins = not s.worldPins
			ns:Print("world map pins %s.", s.worldPins and "on" or "off")
			ns:Changed()
		else
			ns:ToggleSettings()
		end
	end)
	mapButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine("VeinKeeper")
		GameTooltip:AddLine("Left-click: settings", 0.7, 0.7, 0.7)
		GameTooltip:AddLine("Right-click: show / hide map pins", 0.7, 0.7, 0.7)
		GameTooltip:Show()
	end)
	mapButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

function ns:UpdateMapButton()
	if self.db.settings.mapButton then
		CreateMapButton()
		if mapButton then mapButton:Show() end
	elseif mapButton then
		mapButton:Hide()
	end
end

function ns:OnLogin()
	self:UpdateMinimapButton()
	self:UpdateMapButton()
end
