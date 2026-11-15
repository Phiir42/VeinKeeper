-- Translations. The code writes its English text as L["..."]; a locale file
-- for the client's language (Locales\deDE.lua and so on, loaded after this)
-- sets its own text for some or all of those keys, and the rest stay English.
-- Check.lua, loaded after the locale files, drops any translation whose
-- %s / %d placeholders don't match its English text.
--
-- Slash commands and their arguments (/vk route, off, zone...) stay English
-- in every language, as do /vk debug and /vk cpu, which are for bug reports.
local _, ns = ...

local L = setmetatable({}, { __index = function(_, key) return key end })
ns.L = L

-- The table to fill when the client runs in `code` (as GetLocale() names it),
-- else nil:
--   local L = select(2, ...).Locale("deDE")
--   if not L then return end
--   L["Minimap pins"] = "Minikartenpunkte"
function ns.Locale(code)
	if GetLocale() == code then return L end
end
