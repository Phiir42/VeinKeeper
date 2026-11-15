-- /vk probe: what the game lets addons read about minimap dots and mining,
-- for diagnosing hover recording when the game makes values secret (since
-- about 13 Nov 2026 WoW Forever hides minimap dot names from addons).
--
-- It prints the client build and the secret-restriction state, then waits
-- for you to hover a minimap dot and reports every way of reading its
-- tooltip: the text lines, the tooltip data, and what the game's own code
-- passed to the tooltip (hooks). Then it waits for you to mine a vein and
-- reports whether the cast target, soft target and loot source are readable.
--
-- Diagnostic only, English only. Nothing is saved. A secret value is never
-- compared, printed or indexed (that's a Lua error): only tested with
-- issecretvalue and shown as SECRET.
local _, ns = ...

local HOVER_WAIT = 30 -- seconds to wait for a hovered dot
local MINE_WAIT = 90  -- seconds to wait for a mined vein

local function Secret(v)
	return issecretvalue and issecretvalue(v) or false
end

-- A value as text, SECRET if the game hid it.
local function S(v)
	if Secret(v) then return "SECRET" end
	return (tostring(v):gsub("|", "||"))
end

local function Line(fmt, ...)
	print("  " .. fmt:format(...))
end

-- Lists a namespace's functions; calls the argument-less state queries.
local function Namespace(name)
	local t = _G[name]
	if type(t) ~= "table" then return Line("%s: not in this client", name) end
	local keys = {}
	for k in pairs(t) do keys[#keys + 1] = k end
	table.sort(keys)
	for _, k in ipairs(keys) do
		local f = t[k]
		if type(f) == "function" and (k:find("^Has") or k:find("^Should") or k:find("^Is") or k:find("^Get")) then
			local ok, a, b = pcall(f)
			-- (a secret can't even be compared with nil)
			local more = Secret(b) and ", SECRET" or (b ~= nil and ", " .. S(b) or "")
			if ok then Line("%s.%s() = %s%s", name, k, S(a), more)
			else Line("%s.%s(...) needs arguments", name, k) end
		else
			Line("%s.%s", name, k)
		end
	end
end

-- What the game's own code passes to the tooltip, recorded while probing.
local calls
local function Hook(method)
	if not (GameTooltip[method] and hooksecurefunc) then return end
	hooksecurefunc(GameTooltip, method, function(_, a)
		if calls and #calls < 20 then calls[#calls + 1] = method .. "(" .. S(a) .. ")" end
	end)
end
local hooked

local function TooltipData(method)
	if not GameTooltip[method] then return Line("GameTooltip:%s: not in this client", method) end
	local ok, d = pcall(GameTooltip[method], GameTooltip)
	if not ok then return Line("GameTooltip:%s() failed: %s", method, S(d)) end
	if Secret(d) then return Line("GameTooltip:%s() = SECRET", method) end
	if d == nil then return Line("GameTooltip:%s() = nil", method) end
	if (issecrettable and issecrettable(d)) or (canaccesstable and not canaccesstable(d)) then
		return Line("GameTooltip:%s() = a SECRET table", method)
	end
	if type(d) ~= "table" then return Line("GameTooltip:%s() = %s", method, S(d)) end
	ok = pcall(function()
		Line("GameTooltip:%s(): type %s, id %s, guid %s", method, S(d.type), S(d.id), S(d.guid))
		for i, l in ipairs(type(d.lines) == "table" and d.lines or {}) do
			Line("  data line %d: %s (type %s)", i, S(l.leftText), S(l.type))
		end
	end)
	if not ok then Line("GameTooltip:%s(): its fields can't be read", method) end
end

local function ReportTooltip()
	local owner = GameTooltip:GetOwner()
	Line("tooltip owner: %s", owner and S(owner.GetName and owner:GetName() or owner) or "none")
	local n = GameTooltip:NumLines()
	Line("lines: %s", S(n))
	if not Secret(n) then
		for i = 1, n do
			local fs = _G["GameTooltipTextLeft" .. i]
			local t = fs and fs:GetText()
			Line("line %d: %s%s", i, S(t),
				(Secret(t) and canaccessvalue) and (canaccessvalue(t) and " (but accessible)" or " (not accessible)") or "")
		end
	end
	TooltipData("GetTooltipData")
	TooltipData("GetPrimaryTooltipData")
	Line("calls into the tooltip since the probe began: %s", #calls > 0 and table.concat(calls, ", ") or "none")
end

local frame, mineEvents

local function Finish(msg)
	calls = nil
	if frame then frame:UnregisterAllEvents(); frame:SetScript("OnUpdate", nil) end
	ns.probing = nil
	if msg then ns:Print(msg) end
end

local function WatchMining()
	calls = nil
	ns:Print("probe: now mine a vein (within %d s) to check what mining can read.", MINE_WAIT)
	local deadline = GetTime() + MINE_WAIT
	mineEvents = 0
	frame:RegisterEvent("UNIT_SPELLCAST_SENT")
	frame:RegisterEvent("LOOT_READY")
	frame:SetScript("OnEvent", function(_, event, unit, target)
		if event == "UNIT_SPELLCAST_SENT" and unit == "player" then
			local soft = UnitGUID and UnitGUID("softinteract")
			Line("cast aimed at: %s; soft target: %s", S(target), S(soft))
			mineEvents = mineEvents + 1
		elseif event == "LOOT_READY" and GetNumLootItems then
			for i = 1, GetNumLootItems() do
				Line("loot slot %d source: %s", i, S(GetLootSourceInfo and GetLootSourceInfo(i)))
			end
			Finish("probe done. Copy the lines above (or screenshot them) to share.")
		end
	end)
	frame:SetScript("OnUpdate", function()
		if GetTime() > deadline then
			Finish(mineEvents > 0 and "probe done (no loot window seen)." or "probe done (no mining seen).")
		end
	end)
end

function ns:Probe()
	if self.probing then return self:Print("probe already running.") end
	self.probing = true
	self:Print("probe: client and secret restrictions")
	if GetBuildInfo then
		local v, b, d, i = GetBuildInfo()
		Line("client %s build %s (%s), interface %s", S(v), S(b), S(d), S(i))
	end
	Line("in combat: %s; in instance: %s; issecretvalue: %s; canaccessvalue: %s",
		S(UnitAffectingCombat("player")), S(IsInInstance and IsInInstance()),
		issecretvalue and "yes" or "no", canaccessvalue and "yes" or "no")
	Namespace("C_Secrets")
	Namespace("C_RestrictedActions")

	if not hooked then
		hooked = true
		for _, m in ipairs({ "SetText", "AddLine", "AddDoubleLine", "SetOwner", "SetUnit", "SetMinimapMouseover" }) do Hook(m) end
	end
	calls = {}
	frame = frame or CreateFrame("Frame")
	self:Print("probe: hover a minimap dot and hold still (within %d s).", HOVER_WAIT)
	local deadline, since = GetTime() + HOVER_WAIT, nil
	frame:SetScript("OnUpdate", function()
		local shown, over = GameTooltip:IsShown(), Minimap:IsMouseOver()
		if Secret(shown) or Secret(over) then
			Line("tooltip shown: %s; over minimap: %s", S(shown), S(over))
			return WatchMining()
		end
		if shown and over then
			since = since or GetTime()
			if GetTime() - since >= 0.5 then -- let the tooltip settle
				ns:Print("probe: the hovered dot")
				ReportTooltip()
				return WatchMining()
			end
		else
			-- what the game passes to the next tooltip, from when it's hidden
			since, calls = nil, {}
		end
		if GetTime() > deadline then
			Line("no minimap tooltip seen in %d s.", HOVER_WAIT)
			WatchMining()
		end
	end)
end
