-- Settings window (/vk, the minimap button or the world map button) and the
-- ore filter menu. Built on first open; costs nothing until then.
local _, ns = ...
local L = ns.L

local floor = math.floor
local WIDTH, HEIGHT = 600, 418
local LEFT, RIGHT = 16, 312 -- column x offsets
local COL_WIDTH = 272

local panel
local controls = {}
local nameCount = 0

-- Template children get "$parent..." names, so give each control its own name.
local function NextName(kind)
	nameCount = nameCount + 1
	return "VeinKeeperSettings" .. kind .. nameCount
end

local function RefreshControls()
	if not (panel and panel:IsShown()) then return end
	for _, c in ipairs(controls) do c.Refresh() end
end

local function AddTooltip(frame, title, text)
	if not text then return end
	frame:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(title)
		GameTooltip:AddLine(text, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

---------------------------------------------------------------------------
-- Controls
---------------------------------------------------------------------------
local function Header(x, y, text)
	local fs = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	fs:SetPoint("TOPLEFT", x, y)
	fs:SetText(text)
	local line = panel:CreateTexture(nil, "ARTWORK")
	line:SetColorTexture(1, 0.82, 0, 0.25)
	line:SetSize(COL_WIDTH, 1)
	line:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -3)
end

local function Check(x, y, label, key, tip, onChange)
	local cb = CreateFrame("CheckButton", NextName("Check"), panel, "UICheckButtonTemplate")
	cb:SetPoint("TOPLEFT", x - 2, y)
	cb:SetSize(24, 24)
	local text = cb.Text or cb.text
	if not text then
		text = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
	end
	text:SetText(label)
	AddTooltip(cb, label, tip)
	cb:SetScript("OnClick", function(self)
		ns.db.settings[key] = self:GetChecked() and true or false
		if onChange then onChange() end
		ns:Changed()
	end)
	cb.Refresh = function() cb:SetChecked(ns.db.settings[key] and true or false) end
	controls[#controls + 1] = cb
end

-- unit: a format for the value ("%d px"). scale: the stored setting is the
-- slider value / scale (100 for percentages)
local function Slider(x, y, label, key, minV, maxV, step, unit, scale)
	scale = scale or 1
	local name = NextName("Slider")
	local sl = CreateFrame("Slider", name, panel, "OptionsSliderTemplate")
	sl:SetPoint("TOPLEFT", x + 4, y - 16)
	sl:SetWidth(COL_WIDTH - 8)
	sl:SetMinMaxValues(minV, maxV)
	sl:SetValueStep(step)
	if sl.SetObeyStepOnDrag then sl:SetObeyStepOnDrag(true) end
	-- the template's own labels have different keys across client versions
	for _, k in ipairs({ "Low", "High", "Text" }) do
		local fs = sl[k] or _G[name .. k]
		if fs then fs:Hide() end
	end
	local title = sl:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	title:SetPoint("BOTTOMLEFT", sl, "TOPLEFT", 0, 3)
	title:SetText(label)
	local value = sl:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	value:SetPoint("BOTTOMRIGHT", sl, "TOPRIGHT", 0, 3)

	sl:SetScript("OnValueChanged", function(self, v)
		v = floor(v / step + 0.5) * step
		value:SetText(unit:format(v))
		if self.refreshing then return end
		ns.db.settings[key] = v / scale
		ns:Restyle()
	end)
	sl.Refresh = function()
		sl.refreshing = true
		local v = floor(ns.db.settings[key] * scale + 0.5)
		sl:SetValue(v)
		value:SetText(unit:format(v))
		sl.refreshing = false
	end
	controls[#controls + 1] = sl
end

-- A label with a button on the right showing the current choice.
local function Choice(x, y, label, width, getText, onClick, tip)
	local fs = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	fs:SetPoint("TOPLEFT", x, y - 5)
	fs:SetText(label)
	local b = CreateFrame("Button", NextName("Button"), panel, "UIPanelButtonTemplate")
	b:SetSize(width, 22)
	b:SetPoint("TOPLEFT", x + COL_WIDTH - width, y)
	b:SetScript("OnClick", onClick)
	AddTooltip(b, label, tip)
	b.Refresh = function() b:SetText(getText()) end
	controls[#controls + 1] = b
end

---------------------------------------------------------------------------
-- Ore filter menu. Uses the Menu API when the client has it, else UIDropDownMenu.
---------------------------------------------------------------------------
local dropDown

local function MenuEntries(withMapItems)
	local s = ns.db.settings
	local function set(key) s.only = key ns:Changed() end
	local list = { { text = L["All ores"], checked = function() return not s.only end, func = function() set(false) end } }
	for _, c in ipairs(ns:FilterChoices()) do
		list[#list + 1] = { text = c.label, checked = function() return s.only == c.key end, func = function() set(c.key) end }
	end
	if withMapItems then
		list[#list + 1] = { divider = true }
		list[#list + 1] = { text = s.worldPins and L["Hide map pins"] or L["Show map pins"], func = function()
			s.worldPins = not s.worldPins
			ns:Changed()
		end }
		list[#list + 1] = { text = ns:RouteActive() and L["Stop farm route"] or L["Farm route in my zone"],
			func = function() ns:ToggleRoute() end }
		list[#list + 1] = { text = L["Settings"], func = function() ns:ToggleSettings() end }
	end
	return list
end

function ns:ShowFilterMenu(owner, withMapItems)
	local entries = MenuEntries(withMapItems)
	if MenuUtil and MenuUtil.CreateContextMenu then
		MenuUtil.CreateContextMenu(owner, function(_, root)
			root:CreateTitle(L["Show ore"])
			for _, e in ipairs(entries) do
				if e.divider then
					root:CreateDivider()
				elseif e.checked then
					root:CreateRadio(e.text, e.checked, e.func)
				else
					root:CreateButton(e.text, e.func)
				end
			end
		end)
	elseif UIDropDownMenu_Initialize then
		dropDown = dropDown or CreateFrame("Frame", "VeinKeeperFilterMenu", UIParent, "UIDropDownMenuTemplate")
		UIDropDownMenu_Initialize(dropDown, function(_, level)
			local info = UIDropDownMenu_CreateInfo()
			info.text, info.isTitle, info.notCheckable = L["Show ore"], true, true
			UIDropDownMenu_AddButton(info, level)
			for _, e in ipairs(entries) do
				if not e.divider then
					info = UIDropDownMenu_CreateInfo()
					info.text, info.func = e.text, e.func
					if e.checked then info.checked = e.checked() else info.notCheckable = true end
					UIDropDownMenu_AddButton(info, level)
				end
			end
		end, "MENU")
		ToggleDropDownMenu(1, nil, dropDown, owner, 0, 0)
	end
end

---------------------------------------------------------------------------
-- Panel
---------------------------------------------------------------------------
local IN_RANGE = { "ring", "hide", "icon" }
local IN_RANGE_LABEL = { ring = L["Hollow ring"], hide = L["Hidden"], icon = L["Full icon"] }

local function CyclePinsInView()
	local s = ns.db.settings
	for i, mode in ipairs(IN_RANGE) do
		if mode == s.inRange then
			s.inRange = IN_RANGE[i % #IN_RANGE + 1]
			break
		end
	end
	ns:Changed()
end

local function CreatePanel()
	panel = CreateFrame("Frame", "VeinKeeperSettings", UIParent, "BasicFrameTemplateWithInset")
	panel:SetSize(WIDTH, HEIGHT)
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

	local title = panel.TitleText or panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	if not panel.TitleText then title:SetPoint("TOP", 0, -5) end
	title:SetText("VeinKeeper")

	-- left: what pins look like
	Header(LEFT, -36, L["Pins"])
	Check(LEFT, -56, L["World map pins"], "worldPins")
	Check(LEFT, -80, L["Minimap pins"], "minimapPins")
	Check(LEFT, -104, L["Game ore icons"], "gameIcons",
		L["Off: VeinKeeper's own drawn icons. Season of Discovery quest nodes always use drawn icons."])
	Check(LEFT, -128, L["Dim spots above my Mining skill"], "skillDim")
	Slider(LEFT, -162, L["World map opacity"], "worldAlpha", 10, 100, 5, L["%d%%"], 100)
	Slider(LEFT, -204, L["Minimap opacity"], "minimapAlpha", 10, 100, 5, L["%d%%"], 100)
	Slider(LEFT, -246, L["World map icon size"], "worldSize", 8, 32, 1, L["%d px"])
	Slider(LEFT, -288, L["Minimap icon size"], "minimapSize", 8, 24, 1, L["%d px"])

	-- right: respawns and the minimap
	Header(RIGHT, -36, L["Respawns & minimap"])
	Slider(RIGHT, -60, L["Respawn until learned"], "readyMin", 1, 60, 1, L["%d min"])
	Slider(RIGHT, -102, L["Far spots on the minimap rim"], "edgeCount", 0, 10, 1, "%d")
	Slider(RIGHT, -144, L["Rim: hide spots further than"], "edgeMaxYards", 100, 2500, 50, L["%d yd"])
	Check(RIGHT, -186, L["Rim: only spots likely back"], "edgeReadyOnly")
	Check(RIGHT, -210, L["Save veins hovered on the minimap"], "recordSeen",
		L["With Find Minerals on, hovering a vein's yellow dot on the minimap saves it (blue ring) or marks a known spot as up."])
	Choice(RIGHT, -244, L["Spots in view with Find Minerals:"], 100,
		function() return IN_RANGE_LABEL[ns.db.settings.inRange] end, CyclePinsInView,
		L["Addons can't see tracking dots. Hollow ring: the game's yellow dot shows inside the ring when the vein is up."])
	Choice(RIGHT, -274, L["Show only this ore:"], 120,
		function() local only = ns.db.settings.only return only and ns:OreLabel(only) or L["All ores"] end,
		function(self) ns:ShowFilterMenu(self) end)

	-- bottom: buttons
	Header(LEFT, -332, L["Buttons"])
	Header(RIGHT, -332, " ")
	Check(LEFT, -352, L["Minimap button"], "button", nil, function() ns:UpdateMinimapButton() end)
	Check(RIGHT, -352, L["World map button"], "mapButton", nil, function() ns:UpdateMapButton() end)

	local import = CreateFrame("Button", NextName("Button"), panel, "UIPanelButtonTemplate")
	import:SetSize(80, 22)
	import:SetPoint("BOTTOMRIGHT", -16, 10)
	import:SetText(L["Import"])
	import:SetScript("OnClick", function() ns:ShowImport() end)
	AddTooltip(import, L["Import spots"], L["Merge spots someone exported into yours. Your own spots and timers are kept."])
	local export = CreateFrame("Button", NextName("Button"), panel, "UIPanelButtonTemplate")
	export:SetSize(80, 22)
	export:SetPoint("RIGHT", import, "LEFT", -6, 0)
	export:SetText(L["Export"])
	export:SetScript("OnClick", function() ns:ShowExport() end)
	AddTooltip(export, L["Export spots"],
		L["Your spots (those shown, with the ore filter) as text to copy and share. /vk export zone: this zone only."])

	local footer = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	footer:SetPoint("BOTTOMLEFT", LEFT + 2, 12)
	controls[#controls + 1] = {
		Refresh = function() footer:SetText(L["%d spots saved   /vk help for commands"]:format(#ns.db.spots)) end,
	}
end

function ns:ToggleSettings()
	if not panel then CreatePanel() end
	panel:SetShown(not panel:IsShown())
end

ns:On("VK_DATA", RefreshControls)
