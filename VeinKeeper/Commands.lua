-- Slash commands: /vk, /veinkeeper.
local _, ns = ...

local floor, sqrt, min, max, time = math.floor, math.sqrt, math.min, math.max, time

local ON, OFF = "|cff40ff40on|r", "|cffff4040off|r"

-- /vk <word> toggles a setting
local TOGGLES = {
	map     = { "worldPins", "World map pins" },
	minimap = { "minimapPins", "Minimap pins" },
	icons   = { "gameIcons", "Game ore icons" },
	skill   = { "skillDim", "Dimming spots above your skill" },
	seen    = { "recordSeen", "Saving veins hovered on the minimap" },
	button  = { "button", "Minimap button", function() ns:UpdateMinimapButton() end },
}

-- /vk <word> <number> sets a number
local NUMBERS = {
	ready = { "readyMin", 1, 1440, "Likely back after %d min" },
	edge  = { "edgeCount", 0, 10, "Far spots on the minimap rim: %d" },
}

local function Help()
	ns:Print("%d spots saved. Commands:", #ns.db.spots)
	for _, line in ipairs({
		"/vk  settings window",
		"/vk next  waypoint to the nearest spot likely back (also a key binding)",
		"/vk near  list the closest spots",
		"/vk only <ore>  show one ore only (/vk only all to reset)",
		"/vk ignore <node> | unignore <node>  stop / resume recording a node type",
		"/vk map | minimap | icons | skill | seen | button  toggle a setting",
		"/vk ready <minutes> | edge <0-10>  respawn timer, rim pin count",
		"/vk inrange ring | hide | icon  spots in view with Find Minerals on",
		"/vk prune [days]  delete single-visit spots older than [30] days",
		"/vk clear zone | all  delete spots",
	}) do
		print("  " .. line)
	end
end

local function Near()
	local wx, wy, inst = ns:PlayerWorld()
	if not wx then return ns:Print("no position here.") end
	local list = {}
	for _, s in ipairs(ns.db.spots) do
		if s.wx and s.inst == inst and ns:IsShown(s) then
			local dx, dy = s.wx - wx, s.wy - wy
			list[#list + 1] = { spot = s, d = sqrt(dx * dx + dy * dy) }
		end
	end
	if #list == 0 then return ns:Print("no saved spots nearby.") end
	table.sort(list, function(a, b) return a.d < b.d end)
	for i = 1, min(5, #list) do
		local s = list[i].spot
		local state
		if ns:Wait(s) <= 0 then
			state = "|cff40ff40likely up|r"
		else
			state = "mined " .. ns:FormatTime(time() - s.last) .. " ago"
		end
		print(("  %s - %d yd - %s"):format(ns:DisplayOre(s), floor(list[i].d), state))
	end
end

local function Only(arg)
	local s = ns.db.settings
	if arg:lower() == "all" then
		s.only = false
	else
		local name = ns:ResolveNodeName(arg)
		local key = name and ns:OreKey(name)
		if not key then
			local lower = arg:lower()
			for _, c in ipairs(ns:FilterChoices()) do
				if c.label:lower():find(lower, 1, true) then key = c.key break end
			end
		end
		if not key then return ns:Print("no saved spots for \"%s\".", arg) end
		s.only = key
	end
	ns:Print("showing %s.", s.only and ns:OreLabel(s.only) or "all ores")
	ns:Changed()
end

local function Ignore(cmd, arg)
	if arg == "" then
		local names = {}
		for k in pairs(ns.db.ignore) do names[#names + 1] = k end
		table.sort(names)
		return ns:Print("ignored: %s", #names > 0 and table.concat(names, ", ") or "none")
	end
	-- ignoring is a filter: nothing is deleted, so unignore brings the pins back
	local name = ns:ResolveNodeName(arg)
	if not name then
		return ns:Print("unknown node \"%s\". Use the full name, e.g. /vk ignore Copper Vein", arg)
	end
	ns.db.ignore[name] = (cmd == "ignore") or nil
	ns:Print(cmd == "ignore" and "ignoring %s: not recorded, pins hidden." or "showing and recording %s again.", name)
	ns:Changed()
end

local function Clear(arg)
	if arg == "all" then return StaticPopup_Show("VEINKEEPER_CLEAR_ALL") end
	if arg ~= "zone" then return Help() end
	local mapID = C_Map.GetBestMapForUnit("player")
	ns:Print("removed %d spots in this zone.", ns:RemoveSpots(function(s) return s.map == mapID end))
end

StaticPopupDialogs.VEINKEEPER_CLEAR_ALL = {
	text = "Delete all saved VeinKeeper spots?",
	button1 = YES, button2 = NO,
	OnAccept = function() ns:Print("deleted %d spots.", ns:RemoveSpots(function() return true end)) end,
	timeout = 0, whileDead = true, hideOnEscape = true,
}

SLASH_VEINKEEPER1, SLASH_VEINKEEPER2 = "/vk", "/veinkeeper"
SlashCmdList.VEINKEEPER = function(msg)
	local cmd, arg = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
	cmd = cmd:lower()
	local s = ns.db.settings
	local toggle, number = TOGGLES[cmd], NUMBERS[cmd]

	if cmd == "" then
		ns:ToggleSettings()
	elseif toggle then
		local key, label, after = toggle[1], toggle[2], toggle[3]
		s[key] = not s[key]
		if after then after() end
		ns:Print("%s %s.", label, s[key] and ON or OFF)
		ns:Changed()
	elseif number and tonumber(arg) then
		local key, lo, hi, fmt = number[1], number[2], number[3], number[4]
		s[key] = max(lo, min(hi, floor(tonumber(arg))))
		ns:Print(fmt, s[key])
		ns:Changed()
	elseif cmd == "inrange" and (arg == "ring" or arg == "hide" or arg == "icon") then
		s.inRange = arg
		ns:Print("spots in view with Find Minerals: %s.", arg)
		ns:Changed()
	elseif cmd == "next" then
		ns:Next()
	elseif cmd == "near" then
		Near()
	elseif cmd == "only" and arg ~= "" then
		Only(arg)
	elseif cmd == "ignore" or cmd == "unignore" then
		Ignore(cmd, arg)
	elseif cmd == "prune" then
		ns:Prune(max(1, floor(tonumber(arg) or 30)))
	elseif cmd == "clear" then
		Clear(arg)
	else
		Help()
	end
end
