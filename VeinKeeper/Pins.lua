-- Pins: the look, tooltip and clicks shared by world map and minimap pins.
local _, ns = ...

local floor, time = math.floor, time
local GREY = 0.8

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

-- ringOnly: just the freshness ring with an empty centre, so a Find Minerals
-- dot underneath shows through it. alphaMul: extra fade (minimap rim pins).
function ns:StylePin(pin, spot, ringOnly, alphaMul)
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
	local r, g, b = self:Freshness(spot)
	pin.ring:SetVertexColor(r, g, b)
	local ok = self:CanMine(spot)
	pin.icon:SetDesaturated(not ok)
	local s = self.db.settings
	pin:SetAlpha((pin.isMinimap and s.minimapAlpha or s.worldAlpha) * (ok and 1 or 0.55) * (alphaMul or 1))
end

-- Other pins over or touching `owner` (from the pins `...` iterates),
-- nearest first: on a zoomed-out map they're too close to hover one by one.
function ns:Overlapping(owner, ...)
	local ox, oy = owner:GetCenter()
	if not ox then return end
	local scale = owner:GetEffectiveScale()
	local reach = owner:GetWidth() * scale * 1.25
	ox, oy = ox * scale, oy * scale
	local list
	for p in ... do
		if p ~= owner and p.spot and not p.rimPin and p:IsShown() then
			local x, y = p:GetCenter()
			if x then
				local s = p:GetEffectiveScale()
				local dx, dy = x * s - ox, y * s - oy
				local d = dx * dx + dy * dy
				if d < reach * reach then
					list = list or {}
					list[#list + 1] = { spot = p.spot, d = d }
				end
			end
		end
	end
	if list then table.sort(list, function(a, b) return a.d < b.d end) end
	return list
end

-- One line per spot: its ore and state, coloured by freshness.
local MAX_LISTED = 8
function ns:AddSummaries(tt, list)
	for i, e in ipairs(list) do
		if i > MAX_LISTED then
			tt:AddLine(("+ %d more"):format(#list - MAX_LISTED), GREY, GREY, GREY)
			break
		end
		local spot = e.spot
		local ore = self:DisplayOre(spot)
		local c = self:NodeInfo(ore).color
		local r, g, b, ready = self:Freshness(spot)
		local state
		if self:SeenUp(spot) then
			state = "seen up " .. self:FormatTime(time() - spot.seenAt) .. " ago"
		elseif not spot.last then
			state = "seen, not mined"
		elseif ready then
			state = "likely back"
		else
			state = "back in " .. self:FormatTime(self:Wait(spot))
		end
		tt:AddDoubleLine(ore, state, c[1], c[2], c[3], r, g, b)
	end
end

-- nearby: Overlapping()'s list, listed under the spot. noClick: the pin lets
-- clicks through (a minimap ring), so no click hint.
function ns:ShowTooltip(owner, spot, nearby, noClick)
	if not spot then return end
	local tt = GameTooltip
	tt:SetOwner(owner, "ANCHOR_RIGHT")
	local ore = self:DisplayOre(spot)
	local c = self:NodeInfo(ore).color
	tt:AddLine(ore, c[1], c[2], c[3])

	local r, g, b, ready = self:Freshness(spot)
	if spot.last then
		tt:AddDoubleLine("Last mined", self:FormatTime(time() - spot.last) .. " ago", 1, 1, 1, r, g, b)
	else
		tt:AddLine("Seen on the minimap, not mined yet", r, g, b)
	end
	if self:SeenUp(spot) then
		tt:AddDoubleLine("Seen up", self:FormatTime(time() - spot.seenAt) .. " ago", 1, 1, 1, r, g, b)
	elseif not ready then
		tt:AddDoubleLine("Likely back in", self:FormatTime(self:Wait(spot)), 1, 1, 1, r, g, b)
	end
	if spot.minGap then
		tt:AddDoubleLine("Fastest respawn seen", "<= " .. self:FormatTime(spot.minGap), 1, 1, 1, GREY, GREY, GREY)
	end
	if spot.visits > 0 then
		tt:AddDoubleLine("Visits / taps", spot.visits .. " / " .. spot.taps, 1, 1, 1, GREY, GREY, GREY)
	end
	local d = self:Distance(spot)
	if d then tt:AddDoubleLine("Distance", floor(d) .. " yd", 1, 1, 1, GREY, GREY, GREY) end

	if next(spot.ores, next(spot.ores)) then -- more than one ore
		tt:AddLine(" ")
		tt:AddLine("Ores seen here:", 1, 0.82, 0)
		for name, count in pairs(spot.ores) do
			local oc = self:NodeInfo(name).color
			tt:AddDoubleLine(name, count > 0 and count .. "x" or "seen", oc[1], oc[2], oc[3], GREY, GREY, GREY)
		end
	end
	if not self:CanMine(spot) then
		tt:AddLine(("Needs Mining %d (you have %d)"):format(self:MinSkill(spot), self:SkillRank()), 1, 0.3, 0.3)
	end
	if nearby then
		tt:AddLine(" ")
		tt:AddLine("Also here:", 1, 0.82, 0)
		self:AddSummaries(tt, nearby)
	end
	if not noClick then
		tt:AddLine(" ")
		tt:AddLine("Click: waypoint   Shift + right-click: forget", 0.6, 0.6, 0.6)
	end
	tt:Show()
end

-- One VeinKeeper waypoint at a time: a new one replaces the last.
local tomtomUID
function ns:SetWaypoint(spot)
	local name = self:DisplayOre(spot)
	if TomTom and TomTom.AddWaypoint then
		if tomtomUID and TomTom.RemoveWaypoint then pcall(TomTom.RemoveWaypoint, TomTom, tomtomUID) end
		tomtomUID = TomTom:AddWaypoint(spot.map, spot.x, spot.y, { title = name, persistent = false })
		return
	end
	if C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then
		local ok = pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(spot.map, spot.x, spot.y))
		if ok then
			if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
			return
		end
	end
	self:Print("%s at %.1f, %.1f (install TomTom for an arrow).", name, spot.x * 100, spot.y * 100)
end

function ns:PinClick(pin, button)
	local spot = pin.spot
	if not spot then return end
	if button == "RightButton" and IsShiftKeyDown() then
		GameTooltip:Hide()
		self:Forget(spot)
		self:Print("forgot that %s spot.", self:DisplayOre(spot))
	elseif button == "LeftButton" then
		self:SetWaypoint(spot)
	end
end
