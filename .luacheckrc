-- luacheck config (https://github.com/lunarmodules/luacheck), run by the
-- Lint workflow: luacheck VeinKeeper
--
-- WoW runs Lua 5.1 and has no "require": every game function is a global, so
-- each one the addon uses is listed below. A global missing from these lists
-- is usually a typo or a forgotten "local".
std = "lua51"
max_line_length = false -- Data.lua's node table is clearer one node per line
self = false            -- methods that don't use self are fine

-- Globals VeinKeeper creates: saved variables, key bindings, slash commands,
-- the world map pin template's mixin, and the addon compartment callbacks.
globals = {
	"VeinKeeper",
	"VeinKeeperDB",
	"VeinKeeperPinMixin",
	"VeinKeeper_OnCompartmentClick",
	"VeinKeeper_OnCompartmentEnter",
	"VeinKeeper_OnCompartmentLeave",
	"BINDING_HEADER_VEINKEEPER",
	"BINDING_NAME_VEINKEEPER_NEXT",
	"BINDING_NAME_VEINKEEPER_ROUTE",
	"BINDING_NAME_VEINKEEPER_TOGGLE",
	"BINDING_NAME_VEINKEEPER_SETTINGS",
	"SLASH_VEINKEEPER1",
	"SLASH_VEINKEEPER2",
	-- game tables the addon adds entries to
	"SlashCmdList",
	"StaticPopupDialogs",
	"UISpecialFrames",
}

-- The game API and UI the addon reads.
read_globals = {
	-- namespaces
	"C_AddOnProfiler", "C_Item", "C_Map", "C_Minimap", "C_Spell", "C_SuperTrack", "C_Timer", "Enum",
	-- functions
	"CollapseSkillHeader", "CreateFrame", "CreateFromMixins", "CreateVector2D", "debugprofilestop",
	"ExpandSkillHeader", "GetCVar", "GetCursorPosition", "GetItemIcon", "GetItemInfo", "GetLootSourceInfo",
	"GetMinimapShape", "GetNumLootItems", "GetNumSkillLines", "GetPlayerFacing", "GetSkillLineInfo",
	"GetSpellInfo", "GetSpellTexture", "GetTime", "GetTrackingTexture", "IsIndoors", "IsShiftKeyDown",
	"issecretvalue", "StaticPopup_Show", "time", "tinsert", "ToggleDropDownMenu", "UIDropDownMenu_AddButton",
	"UIDropDownMenu_CreateInfo", "UIDropDownMenu_Initialize", "UnitGUID", "UnitOnTaxi", "wipe",
	-- frames, mixins and objects
	"ChatFontNormal", "DEFAULT_CHAT_FRAME", "GameTooltip", "GameTooltipTextLeft1", "MapCanvasDataProviderMixin",
	"MapCanvasPinMixin", "MenuUtil", "Minimap", "UIParent", "UiMapPoint", "WorldMapFrame",
	-- strings
	"CLOSE", "NO", "YES",
	-- other addons
	"TomTom",
}
