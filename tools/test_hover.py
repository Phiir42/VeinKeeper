"""Tests hover recording (VeinKeeper/Minimap.lua): a hovered Find Minerals
dot saves its vein, and when the game makes the tooltip's text secret
VeinKeeper says so once instead of failing silently.

    pip install lupa
    python tools/test_hover.py
"""
import re

import sandbox

FILES = sandbox.addon_files() + ["Minimap.lua"]

STUBS = """
SECRET = setmetatable({}, { __tostring = function() return 'SECRET' end })
issecretvalue = function(v) return v == SECRET end
now = 100
GetTime = function() return now end
GetCVar = function() return '0' end
IsIndoors = function() return false end
GetCursorPosition = function() return cursor.x, cursor.y end
cursor = { x = 0, y = 0 }
tipText, tipShown = nil, false
GameTooltipTextLeft1 = { GetText = function() return tipText end }
GameTooltipTextLeft2 = GameTooltipTextLeft1
GameTooltip = setmetatable({
  IsShown = function() return tipShown end,
  GetOwner = function() return UIParent end,
  NumLines = function() return 1 end,
  GetUnit = function() return nil end,
}, { __index = function() return function() end end })
UIParent = {}
Minimap = setmetatable({
  GetZoom = function() return 0 end,
  GetWidth = function() return 140 end,
  GetCenter = function() return 0, 0 end,
  GetEffectiveScale = function() return 1 end,
  IsMouseOver = function() return true end,
}, { __index = function() return function() end end })
C_Minimap = {
  GetNumTrackingTypes = function() return 1 end,
  GetTrackingInfo = function() return { name = 'Find Minerals', active = true, spellID = 2580 } end,
}
"""


def main():
    check = sandbox.Checks()
    lua = sandbox.load(FILES, before=STUBS + "VeinKeeperDB = { settings = { minimapPins = false } }")
    G = lua.globals()
    lua.execute("ns:Fire('PLAYER_ENTERING_WORLD')")

    def tick():
        for t in list(G.tickers.values()):
            if not t.cancelled:
                t.fn()

    def hover(text, secs=2):
        """Show a dot's tooltip with `text` (None: secret) for `secs` seconds, then hide it."""
        n = len(G.printed)
        lua.execute("tipText = %s  tipShown = true" % ("SECRET" if text is None else repr(text)))
        tick()
        G.now = G.now + secs
        tick()
        lua.execute("tipShown = false")
        tick()
        return [re.sub(r"\|c\w{8}|\|r", "", m) for m in list(G.printed.values())[n:]]

    def spots():
        return lua.eval("#ns.db.spots")

    # a readable tooltip: the vein is saved
    hover("Truesilver Deposit")
    check(spots() == 1 and lua.eval("ns.db.spots[1].lastOre") == "Truesilver Deposit",
          "a readable dot tooltip saves the vein")

    # a secret one: nothing saved, and one notice
    out = hover(None)
    check(spots() == 1, "a secret tooltip saves nothing")
    check(any("hides minimap dot names" in l for l in out), "and says why: %s" % out)
    out = hover(None)
    check(not any("hides minimap dot names" in l for l in out), "only once a session")

    # /vk debug reads every hover afresh, even identical secret ones
    lua.execute("SlashCmdList.VEINKEEPER('debug')")
    first = hover(None)
    second = hover(None)
    print("     " + "\n     ".join(first))
    check(any("(secret: the game hides this text from addons)" in l for l in first),
          "debug shows the line is secret")
    check(any(l.startswith("hover: tooltip owner") or "hover: tooltip owner" in l for l in second),
          "the next identical tooltip is read again (not skipped as unchanged)")

    # the notice isn't shown with hover saving turned off
    lua2 = sandbox.load(FILES, before=STUBS + "VeinKeeperDB = { settings = { minimapPins = false, recordSeen = false } }")
    lua2.execute("ns:Fire('PLAYER_ENTERING_WORLD') SlashCmdList.VEINKEEPER('debug') SlashCmdList.VEINKEEPER('debug')")
    G2 = lua2.globals()
    n = len(G2.printed)
    lua2.execute("tipText = SECRET  tipShown = true")
    for t in list(G2.tickers.values()):
        t.fn()
    check(not any("hides minimap" in m for m in list(G2.printed.values())[n:]), "no notice with hover saving off")

    nameless(check)
    probe(check)
    check.finish()


def nameless(check):
    """A dot whose name the game hid only confirms a saved spot."""
    lua = sandbox.load(FILES, before=STUBS + "VeinKeeperDB = { settings = { minimapPins = false } }")
    G = lua.globals()
    lua.execute("ns:Fire('PLAYER_ENTERING_WORLD') SlashCmdList.VEINKEEPER('debug')")

    def hover_at(x, lines=1, secs=2):
        """Hover a secret dot under the cursor, the player (and so the cursor) at map x yards, y 500."""
        G.player.x = x / 1000
        n = len(G.printed)
        lua.execute("tipText = SECRET  tipShown = true  GameTooltip.NumLines = function() return %d end" % lines)
        for t in list(G.tickers.values()):
            t.fn()
        G.now = G.now + secs
        for t in list(G.tickers.values()):
            t.fn()
        lua.execute("tipShown = false")
        for t in list(G.tickers.values()):
            t.fn()
        return [l for l in (re.sub(r"\|c\w{8}|\|r", "", m) for m in list(G.printed.values())[n:]) if "name hidden" in l]

    G.player.x = 0.5
    lua.execute("ns:Record('Copper Vein')")
    G.clock = G.clock + 900
    out = hover_at(500)
    print("     " + "\n     ".join(out))
    check(lua.eval("ns.db.spots[1].seenAt") == G.clock, "a hidden-name dot on a saved spot marks it up")
    check(list(lua.eval("ns.db.respawn['Copper Vein']").values())[-1] == 900, "and the time since mining is a respawn sample")
    check(lua.eval("#ns.db.spots") == 1, "no spot added or moved: %s" % out)

    out = hover_at(900)
    check(lua.eval("#ns.db.spots") == 1 and any("no saved spot in reach" in l for l in out),
          "away from saved spots: nothing saved (%s)" % out)

    out = hover_at(500, lines=2)
    check(not out, "two lines (several dots, one maybe not a vein): ignored")

    # two saved spots in reach of one hover: can't tell which
    G.player.x = 0.52
    lua.execute("ns:Record('Copper Vein')")
    G.clock = G.clock + 900
    before = (lua.eval("ns.db.spots[1].seenAt"), lua.eval("ns.db.spots[2].seenAt"))
    out = hover_at(510)
    check(any("two saved spots in reach" in l for l in out)
          and (lua.eval("ns.db.spots[1].seenAt"), lua.eval("ns.db.spots[2].seenAt")) == before,
          "two saved spots in reach: neither is marked (%s)" % out)

    # a spot with ores that don't share a timer: up, but no respawn sample
    lua.execute("ns.db.spots[2].ores['Iron Deposit'] = 1  ns.db.spots[2].last = clock - 900")
    n = len(list(lua.eval("ns.db.respawn['Copper Vein']").values()))
    G.clock = G.clock + 1
    out = hover_at(530)
    check(any("marked a saved" in l and "sample" not in l for l in out)
          and len(list(lua.eval("ns.db.respawn['Copper Vein']").values())) == n,
          "mixed ores: marked up without a sample (%s)" % out)


PROBE_STUBS = """
GetBuildInfo = function() return '1.60.1', '70888', 'Nov 10 2026', 16001 end
IsInInstance = function() return false end
UnitAffectingCombat = function() return false end
canaccessvalue = function() return false end
C_Secrets = { HasSecretRestrictions = function() return true end,
  ShouldUnitBeSecret = function(unit) assert(unit) end }
GameTooltip.GetTooltipData = function() return { type = 0, lines = { { leftText = SECRET, type = 0 } } } end
GameTooltip.SetText = function() end
hooksecurefunc = function(t, m, post) local orig = t[m]
  t[m] = function(...) local r = orig(...) post(...) return r end end
frames = {}
local orig = CreateFrame
CreateFrame = function(...) local f = orig(...)
  f.scripts = {}
  f.SetScript = function(s, k, fn) s.scripts[k] = fn end
  frames[#frames + 1] = f
  return f end
GetNumLootItems = function() return 1 end
GetLootSourceInfo = function() return 'GameObject-0-1-2-3-2047-0000000001' end
"""


def probe(check):
    """/vk probe: reports what's readable without erroring on secrets."""
    lua = sandbox.load(FILES, before=STUBS + PROBE_STUBS + "VeinKeeperDB = { settings = { minimapPins = false } }")
    G = lua.globals()

    def out(n):
        return [re.sub(r"\|c\w{8}|\|r", "", m) for m in list(G.printed.values())[n:]]

    lua.execute("SlashCmdList.VEINKEEPER('probe')")
    lines = out(0)
    check(any("client 1.60.1 build 70888" in l for l in lines), "probe: the client build")
    check(any("C_Secrets.HasSecretRestrictions() = true" in l for l in lines), "probe: restriction state")
    check(any("C_Secrets.ShouldUnitBeSecret(...) needs arguments" in l for l in lines), "probe: queries needing arguments")
    f = "frames[#frames]"
    # the game's minimap code sets the dot's tooltip, then it's shown under the cursor
    n = len(G.printed)
    lua.execute("""
      %s.scripts.OnUpdate()
      GameTooltip:SetText(SECRET)
      tipText, tipShown = SECRET, true
      %s.scripts.OnUpdate() now = now + 1 %s.scripts.OnUpdate()
    """ % (f, f, f))
    lines = out(n)
    print("     " + "\n     ".join(lines))
    check(any("line 1: SECRET (not accessible)" in l for l in lines), "probe: the tooltip line is secret")
    check(any("data line 1: SECRET" in l for l in lines), "probe: tooltip data read safely")
    check(any("SetText(SECRET)" in l for l in lines), "probe: what the game passed to the tooltip")
    check(any("now mine a vein" in l for l in lines), "then asks for a mined vein")
    n = len(G.printed)
    lua.execute("%s.scripts.OnEvent(nil, 'UNIT_SPELLCAST_SENT', 'player', SECRET)" % f)
    lua.execute("%s.scripts.OnEvent(nil, 'LOOT_READY')" % f)
    lines = out(n)
    print("     " + "\n     ".join(lines))
    check(any("cast aimed at: SECRET" in l for l in lines), "probe: the cast target")
    check(any("source: GameObject-0-1-2-3-2047" in l for l in lines) and any("probe done" in l for l in lines),
          "probe: the loot source, then done")
    check(not lua.eval("ns.probing"), "and it can run again")


if __name__ == "__main__":
    main()
