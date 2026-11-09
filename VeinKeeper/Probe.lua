-- /vk probe: temporary diagnostics for what identifies a node on this client
-- (object IDs in GUIDs from loot, soft interact and tooltip data). Prints to
-- chat while on; does nothing while off.
local _, ns = ...

local on, hooked = false, false
local frame = CreateFrame("Frame")
local lastObjTip, lastMiniTip

local function S(v)
	if issecretvalue and issecretvalue(v) then return "<secret>" end
	return tostring(v)
end

local function ObjectID(guid)
	if type(guid) ~= "string" or (issecretvalue and issecretvalue(guid)) then return nil end
	return guid:match("^GameObject%-[^-]*%-[^-]*%-[^-]*%-[^-]*%-(%d+)%-")
end

-- the top-level fields of a tooltip data table, one line
local function Fields(t)
	local out = {}
	for k, v in pairs(t) do
		if type(v) == "table" then
			out[#out + 1] = tostring(k) .. "={" .. #v .. "}"
		else
			out[#out + 1] = tostring(k) .. "=" .. S(v)
		end
	end
	table.sort(out)
	return table.concat(out, ", ")
end

frame:SetScript("OnEvent", function(_, event, ...)
	if event == "LOOT_READY" then
		for i = 1, GetNumLootItems() do
			local guid = GetLootSourceInfo and GetLootSourceInfo(i)
			ns:Print("probe: loot slot %d from %s -> object ID %s", i, S(guid), S(ObjectID(guid)))
		end
	elseif event == "PLAYER_SOFT_INTERACT_CHANGED" then
		local _, new = ...
		if new then ns:Print("probe: soft interact %s -> object ID %s", S(new), S(ObjectID(new))) end
	elseif event == "UNIT_SPELLCAST_SENT" then
		local _, target, _, spellID = ...
		local soft = UnitGUID("softinteract")
		ns:Print("probe: cast %s on \"%s\", soft interact %s -> object ID %s",
			S(spellID), S(target), S(soft), S(ObjectID(soft)))
	end
end)

local function Hook()
	if hooked or not (TooltipDataProcessor and Enum and Enum.TooltipDataType) then return end
	hooked = true
	local T = Enum.TooltipDataType
	if T.Object then
		TooltipDataProcessor.AddTooltipPostCall(T.Object, function(tt, data)
			if not on or tt ~= GameTooltip or not data then return end
			local title = data.lines and data.lines[1] and data.lines[1].leftText
			if title == lastObjTip then return end
			lastObjTip = title
			ns:Print("probe: world object tooltip \"%s\": %s", S(title), Fields(data))
		end)
	end
	if T.MinimapMouseover then
		TooltipDataProcessor.AddTooltipPostCall(T.MinimapMouseover, function(tt, data)
			if not on or tt ~= GameTooltip or not data then return end
			local title = data.lines and data.lines[1] and data.lines[1].leftText
			if title == lastMiniTip then return end
			lastMiniTip = title
			ns:Print("probe: minimap tooltip \"%s\": %s", S(title), Fields(data))
		end)
	end
end

function ns:ToggleProbe()
	on = not on
	if not on then
		frame:UnregisterAllEvents()
		return self:Print("probe off.")
	end
	Hook()
	lastObjTip, lastMiniTip = nil, nil
	for _, e in ipairs({ "LOOT_READY", "PLAYER_SOFT_INTERACT_CHANGED" }) do pcall(frame.RegisterEvent, frame, e) end
	pcall(frame.RegisterUnitEvent, frame, "UNIT_SPELLCAST_SENT", "player")
	self:Print("probe on. Mine a vein, hover a vein in the world and a dot on the minimap. /vk probe to stop.")
	self:Print("probe: client %s, GetLootSourceInfo %s, tooltip data %s, SoftTargetInteract = %s",
		(GetBuildInfo()), GetLootSourceInfo and "yes" or "no", TooltipDataProcessor and "yes" or "no",
		S(GetCVar("SoftTargetInteract")))
end
