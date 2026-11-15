"""A sandbox for testing VeinKeeper's Lua outside the game: Lua 5.1 (lupa)
with stubs for the game API, and the addon's files loaded into it.

Zone map 1 is a 1000 x 1000 yd square at world (0, 0) on continent 0, so map
x, y = world yards / 1000. Globals the tests drive: player.x / player.y, clock
(time()), tickers, printed, waypoints, made (created lines and textures).
"""
import os, sys

try:
    import lupa.lua51 as lupa_lua
except ImportError:
    try:
        import lupa as lupa_lua
    except ImportError:
        sys.exit("needs lupa: pip install lupa")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ADDON = os.path.join(ROOT, "VeinKeeper")

STUBS = r"""
local noop = function() end
local function Obj()
  return setmetatable({}, { __index = function(t, k)
    return function(self, ...)
      if k == "GetSize" then return 1000, 1000 end
      if k == "CreateLine" or k == "CreateTexture" or k == "CreateFontString" then
        local o = Obj(); o.shown = false
        o.Show = function(s) s.shown = true end
        o.Hide = function(s) s.shown = false end
        made = made or {}; made[#made + 1] = o
        return o
      end
      return nil
    end
  end })
end
CreateFrame = function() return Obj() end
clock = 1000000
time = function() return clock end
debugprofilestop = function() return 0 end
printed = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) printed[#printed + 1] = m end }
print = function(m) printed[#printed + 1] = m end
tickers = {}
afters = {}
-- run C_Timer.After callbacks (and the ones they queue) until none are left
function run_afters()
  while #afters > 0 do
    local list = afters; afters = {}
    for _, fn in ipairs(list) do fn() end
  end
end
C_Timer = {
  After = function(_, fn) afters[#afters + 1] = fn end,
  NewTicker = function(_, fn) local t = { fn = fn, Cancel = function(s) s.cancelled = true end }
    tickers[#tickers + 1] = t; return t end,
}
player = { x = 0.5, y = 0.5 }
C_Map = {
  GetBestMapForUnit = function() return 1 end,
  GetPlayerMapPosition = function() return { GetXY = function() return player.x, player.y end } end,
  GetWorldPosFromMapPos = function(id, v) if id == 999 then return nil end return 0, { GetXY = function() return v.x * 1000, v.y * 1000 end } end,
  GetMapInfo = function(id) if id == 999 then return nil end return { name = "Testzone", mapType = 3 } end,
}
CreateVector2D = function(x, y) return { x = x, y = y } end
C_Spell = { GetSpellName = function(id) return id == 2575 and "Mining" or "Other" end }
GetNumSkillLines = function() return 0 end
StaticPopupDialogs = {}
SlashCmdList = {}
YES, NO = "Yes", "No"
UISpecialFrames = {}
tinsert = table.insert
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
GameTooltip = Obj()
waypoints = {}
TomTom = { AddWaypoint = function(_, map, x, y, o) waypoints[#waypoints + 1] = { x = x, y = y }; return #waypoints end,
           RemoveWaypoint = noop }
CreateFromMixins = function(...) local t = {} for _, m in ipairs({...}) do for k, v in pairs(m) do t[k] = v end end return t end
MapCanvasDataProviderMixin = { GetMap = function(self) return self.owningMap end }
MapCanvasPinMixin = {}
WorldMapFrame = {
  shown = true,
  IsShown = function(s) return s.shown end,
  AddDataProvider = function(s, p) p.owningMap = s.map; s.provider = p end,
  EnumeratePinsByTemplate = function() return function() end end,
}
WorldMapFrame.map = {
  GetMapID = function() return 1 end,
  GetCanvas = function() return Obj() end,
  GetCanvasScale = function() return 1 end,
  RemoveAllPinsByTemplate = noop,
}
UnitOnTaxi = function() return false end
Minimap = Obj()
"""



def load(files):
    """A Lua runtime with `files` (from VeinKeeper/) loaded as the addon, past
    ADDON_LOADED and PLAYER_LOGIN; the addon table is the global `ns`."""
    lua = lupa_lua.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(STUBS)
    ns = lua.eval("{}")
    compile_ = lua.execute("return function(src, name) return assert(loadstring(src, name)) end")
    for f in files:
        with open(os.path.join(ADDON, f), encoding="utf-8") as fh:
            compile_(fh.read(), "@" + f)("VeinKeeper", ns)
    lua.globals().ns = ns
    # the stub frame's OnEvent never runs: send the events through ns:Fire
    lua.execute("ns:Fire('ADDON_LOADED', 'VeinKeeper') ns:Fire('PLAYER_LOGIN')")
    return lua


class Checks:
    def __init__(self):
        self.failures = []

    def __call__(self, cond, msg):
        print(("ok   " if cond else "FAIL ") + msg)
        if not cond:
            self.failures.append(msg)

    def finish(self):
        print()
        print("%d failed" % len(self.failures) if self.failures else "all passed")
        sys.exit(1 if self.failures else 0)
