-- After the locale files: a translation must have the same placeholders
-- (%s, %d, %.1f, %%...) in the same order as its English text, or
-- string.format would fail or show the wrong value. Ones that don't are
-- dropped, so that text stays English instead. tools/locales.py checks
-- the same before a release.
local _, ns = ...

local function Placeholders(s)
	local t = {}
	for p in s:gmatch("%%[%-%+ #0]*%d*%.?%d*[%a%%]") do t[#t + 1] = p end
	return table.concat(t, " ")
end

for key, text in pairs(ns.L) do
	if type(text) ~= "string" or Placeholders(text) ~= Placeholders(key) then ns.L[key] = nil end
end
