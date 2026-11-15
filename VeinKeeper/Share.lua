-- Sharing spots: /vk export makes a text string of your spots to copy, and
-- /vk import merges someone's string into yours.
--
-- Only positions and ores travel; mining times, visits and learned respawns
-- stay yours. Imported spots are never-mined spots (blue rings, counted as
-- likely up) until you mine or see them; a spot you already have gains the
-- ores it lacks. /vk clear imported removes imported spots you haven't been to.
--
-- Format (whitespace ignored, so line breaks from pasting don't matter):
--   VK1:<checksum>:<block>\n<block>...
--   block = "@" <zone map ID> ":" <spot> ("," <spot>)*
--   spot  = <x:3><y:3><err:1><ore> ("." <ore>)*
-- all numbers in base 36: x and y in 1/10000ths of the zone map, err in
-- yards (1-35), ores as the node's first object ID in Data.lua (the same in
-- every client language). The checksum (Adler-32) catches cut-off pastes.
local _, ns = ...

local floor, max, min = math.floor, math.max, math.min
local byte, sub = string.byte, string.sub

local PREFIX = "VK1"
local BATCH = 250 -- spots merged per frame on import, so big imports don't freeze the game

---------------------------------------------------------------------------
-- Encoding
---------------------------------------------------------------------------
local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"

local function B36(n, width)
	n = floor(n)
	local t = {}
	repeat
		local d = n % 36
		t[#t + 1] = sub(DIGITS, d + 1, d + 1)
		n = (n - d) / 36
	until n == 0
	local s = string.reverse(table.concat(t))
	if width and #s < width then s = string.rep("0", width - #s) .. s end
	return s
end

local function Checksum(s)
	local a, b = 1, 0
	for i = 1, #s do
		a = (a + byte(s, i)) % 65521
		b = (b + a) % 65521
	end
	return B36(b * 65536 + a)
end

-- node name -> the ID it travels as, and back
local codeOf, nameOf = {}, {}
for name, info in pairs(ns.NODES) do
	local id = info.ids and info.ids[1]
	if id then codeOf[name], nameOf[id] = B36(id), name end
end

-- The export string for the spots that pass `want` (default: those shown),
-- and how many went in.
function ns:Export(want)
	want = want or function(s) return self:IsShown(s) end
	local byMap, maps, n = {}, {}, 0
	for _, s in ipairs(self.db.spots) do
		if s.map and s.x and want(s) then
			local ores = {}
			-- the ore the pin shows first: an importer's pin shows it too
			local shown = self:DisplayOre(s)
			if codeOf[shown] and not self.db.ignore[shown] then ores[1] = codeOf[shown] end
			for name in pairs(s.ores) do
				if name ~= shown and codeOf[name] and not self.db.ignore[name] then ores[#ores + 1] = codeOf[name] end
			end
			if #ores > 0 then
				local list = byMap[s.map]
				if not list then
					list = {}
					byMap[s.map] = list
					maps[#maps + 1] = s.map
				end
				local x = min(9999, max(0, floor(s.x * 10000 + 0.5)))
				local y = min(9999, max(0, floor(s.y * 10000 + 0.5)))
				local err = min(35, max(1, floor(self:SpotErr(s) + 0.5)))
				list[#list + 1] = B36(x, 3) .. B36(y, 3) .. B36(err) .. table.concat(ores, ".")
				n = n + 1
			end
		end
	end
	table.sort(maps)
	local blocks = {}
	for i, m in ipairs(maps) do blocks[i] = "@" .. B36(m) .. ":" .. table.concat(byMap[m], ",") end
	local payload = table.concat(blocks, "\n")
	return PREFIX .. ":" .. Checksum((payload:gsub("%s", ""))) .. ":" .. payload, n
end

-- text -> a list of { map, x, y, err, names }, or nil and why not.
function ns:Decode(text)
	text = (text or ""):gsub("%s", "")
	local version, sum, payload = text:match("^(VK%d+):(%w+):(.*)$")
	if not version then return nil, "that isn't a VeinKeeper export" end
	if version ~= PREFIX then return nil, "it's from a newer VeinKeeper (" .. version .. "); update to import it" end
	if Checksum(payload) ~= sum then return nil, "it's incomplete or changed (copy the whole text again)" end
	local list, bad = {}, 0
	for mapCode, spots in payload:gmatch("@(%w+):([^@]*)") do
		local map = tonumber(mapCode, 36)
		local valid = map and C_Map.GetMapInfo(map) and self:Basis(map)
		for spot in spots:gmatch("[^,]+") do
			local x, y, err, ores = spot:match("^(%w%w%w)(%w%w%w)(%w)([%w%.]+)$")
			local names = {}
			if x and valid then
				for code in ores:gmatch("[^%.]+") do
					local name = nameOf[tonumber(code, 36)]
					if name then names[#names + 1] = name end
				end
				x, y = tonumber(x, 36), tonumber(y, 36)
			end
			if #names > 0 and x <= 9999 and y <= 9999 then
				list[#list + 1] = { map = map, x = x / 10000, y = y / 10000, err = max(1, tonumber(err, 36)), names = names }
			else
				bad = bad + 1
			end
		end
	end
	if #list == 0 then return nil, "it has no spots this client knows" end
	return list, bad
end

-- Merges a decoded list, BATCH spots a frame; done(new, known, ignored) after.
local importing
function ns:Import(list, done)
	if importing then return self:Print("still importing the last one.") end
	importing = true
	local now, i, new, known, ignored = time(), 0, 0, 0, 0
	local function Step()
		for _ = 1, BATCH do
			i = i + 1
			local e = list[i]
			if not e then
				importing = false
				if new + known > 0 then self:Changed() end
				return done and done(new, known, ignored)
			end
			local names = {}
			for _, n in ipairs(e.names) do
				if not self.db.ignore[n] then names[#names + 1] = n end
			end
			if #names == 0 then
				ignored = ignored + 1
			elseif self:ImportSpot(e.map, e.x, e.y, e.err, names, now) then
				new = new + 1
			else
				known = known + 1
			end
		end
		C_Timer.After(0, Step)
	end
	Step()
end

---------------------------------------------------------------------------
-- Window: one text box, for copying an export out or pasting one in.
---------------------------------------------------------------------------
local win

local function Window()
	if win then return win end
	win = CreateFrame("Frame", "VeinKeeperShare", UIParent, "BasicFrameTemplateWithInset")
	win:SetSize(480, 340)
	win:SetPoint("CENTER")
	win:SetFrameStrata("DIALOG")
	win:SetToplevel(true)
	win:SetClampedToScreen(true)
	win:SetMovable(true)
	win:EnableMouse(true)
	win:RegisterForDrag("LeftButton")
	win:SetScript("OnDragStart", win.StartMoving)
	win:SetScript("OnDragStop", win.StopMovingOrSizing)
	win:Hide()
	tinsert(UISpecialFrames, "VeinKeeperShare")

	win.title = win.TitleText or win:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	if not win.TitleText then win.title:SetPoint("TOP", 0, -5) end

	win.hint = win:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	win.hint:SetPoint("TOPLEFT", 16, -32)
	win.hint:SetPoint("RIGHT", -16, 0)
	win.hint:SetJustifyH("LEFT")

	local scroll = CreateFrame("ScrollFrame", "VeinKeeperShareScroll", win, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 14, -54)
	scroll:SetPoint("BOTTOMRIGHT", -34, 44)
	local edit = CreateFrame("EditBox", nil, scroll)
	edit:SetMultiLine(true)
	edit:SetAutoFocus(false)
	edit:SetMaxLetters(0)
	edit:SetFontObject(ChatFontNormal)
	edit:SetWidth(420)
	edit:SetScript("OnEscapePressed", function() win:Hide() end)
	scroll:SetScrollChild(edit)
	scroll:EnableMouse(true)
	scroll:SetScript("OnMouseDown", function() edit:SetFocus() end)
	win.edit = edit

	win.status = win:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	win.status:SetPoint("BOTTOMLEFT", 18, 18)
	win.status:SetPoint("RIGHT", -130, 0)
	win.status:SetJustifyH("LEFT")

	local button = CreateFrame("Button", "VeinKeeperShareButton", win, "UIPanelButtonTemplate")
	button:SetSize(100, 22)
	button:SetPoint("BOTTOMRIGHT", -14, 12)
	win.button = button
	return win
end

function ns:ShowExport(zoneOnly)
	local mapID = zoneOnly and C_Map.GetBestMapForUnit("player")
	if zoneOnly and not mapID then return self:Print("no zone here.") end
	local text, n = self:Export(function(s)
		return self:IsShown(s) and (not mapID or s.map == mapID)
	end)
	if n == 0 then return self:Print("no spots to export%s.", mapID and " in this zone" or "") end
	local w = Window()
	local only = self.db.settings.only
	w.title:SetText("VeinKeeper: export")
	w.hint:SetText("Press Ctrl+C to copy, then paste it anywhere. Others import it with /vk import.")
	w.status:SetText(("%d spots%s%s, %d characters"):format(n, only and (" of " .. self:OreLabel(only)) or "",
		mapID and " in this zone" or "", #text))
	w.edit:SetScript("OnTextChanged", function(edit, user)
		if user then edit:SetText(text) edit:HighlightText() end -- read-only
	end)
	w.edit:SetScript("OnEditFocusGained", function(edit) edit:HighlightText() end)
	w.edit:SetText(text)
	w.button:SetText(CLOSE or "Close")
	w.button:SetScript("OnClick", function() w:Hide() end)
	w:Show()
	w.edit:SetFocus()
	w.edit:HighlightText()
end

function ns:ShowImport()
	local w = Window()
	w.title:SetText("VeinKeeper: import")
	w.hint:SetText("Paste a VeinKeeper export (Ctrl+V), then press Import.")
	w.status:SetText("Your own spots and timers are kept; new spots show as blue rings.")
	w.edit:SetScript("OnTextChanged", nil)
	w.edit:SetScript("OnEditFocusGained", nil)
	w.edit:SetText("")
	w.button:SetText("Import")
	w.button:SetScript("OnClick", function()
		local list, why = self:Decode(w.edit:GetText())
		if not list then
			w.status:SetText("|cffff6060Can't import: " .. why .. ".|r")
			return
		end
		local bad = why
		w.status:SetText(("Importing %d spots..."):format(#list))
		self:Import(list, function(new, known, ignored)
			local extra = {}
			if known > 0 then extra[#extra + 1] = known .. " you already had" end
			if ignored > 0 then extra[#extra + 1] = ignored .. " of ignored ores" end
			if bad > 0 then extra[#extra + 1] = bad .. " unreadable" end
			self:Print("imported %d new spots%s.", new, #extra > 0 and (" (" .. table.concat(extra, ", ") .. ")") or "")
			w:Hide()
		end)
	end)
	w:Show()
	w.edit:SetFocus()
end
