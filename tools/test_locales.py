"""Tests translations: tools/locales.py (new, update, check) and, in the
game's Lua, that a locale file's text is used and a bad one isn't.

Works on a made-up locale, qqQQ, and puts the .toc back afterwards.

    pip install lupa
    python tools/test_locales.py
"""
import os, subprocess, sys

import sandbox

TOOL = os.path.join(sandbox.ROOT, "tools", "locales.py")
LOC = os.path.join(sandbox.ADDON, "Locales", "qqQQ.lua")
TOC = os.path.join(sandbox.ADDON, "VeinKeeper.toc")
FILES = ["Core.lua", "Data.lua", "Spots.lua", "Pins.lua", "Share.lua", "Yield.lua", "Route.lua", "Commands.lua"]


def tool(*args):
    r = subprocess.run([sys.executable, TOOL, *args], capture_output=True, text=True, encoding="utf-8")
    return r.returncode, r.stdout + r.stderr


def main():
    check = sandbox.Checks()
    with open(TOC, encoding="utf-8") as fh:
        toc = fh.read()
    try:
        code, out = tool()
        check(code == 0, "check passes on the shipped locale files: %s" % out.strip().splitlines()[-1])

        code, out = tool("new", "qqQQ")
        check(code == 0 and os.path.exists(LOC), "new makes the file")
        with open(TOC, encoding="utf-8") as fh:
            lines = fh.read().splitlines()
        check(lines.index("Locales\\Locale.lua") < lines.index("Locales\\qqQQ.lua") < lines.index("Locales\\Check.lua"),
              "new adds it to the .toc between Locale.lua and Check.lua")
        with open(LOC, encoding="utf-8") as fh:
            text = fh.read()
        check('--L["Minimap pins"] = ""' in text and "-- Commands.lua" in text, "every English text, commented out, by file")

        # translate three lines, one with its placeholders swapped
        text = text.replace('--L["Minimap pins"] = ""', 'L["Minimap pins"] = "QQ minimap"')
        text = text.replace('--L["%d spots saved"] = ""', 'L["%d spots saved"] = "QQ %d saved"')
        text = text.replace('--L["next: %s, %d yd."] = ""', 'L["next: %s, %d yd."] = "QQ %d yd: %s"')
        with open(LOC, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(text)
        code, out = tool()
        check(code == 1 and "placeholders %d %s should be %s %d" in out, "check catches swapped placeholders")
        check("qqQQ: 3 of" in out, "check counts translations: %s" % [l for l in out.splitlines() if "qqQQ" in l])

        # in the game: good translations used, the bad one stays English
        lua = sandbox.load(FILES, locale="qqQQ")
        check(lua.eval("ns.L['Minimap pins']") == "QQ minimap", "the client's language is used")
        check(lua.eval("ns.L['%d spots saved']:format(4)") == "QQ 4 saved", "with its placeholders")
        check(lua.eval("ns.L['next: %s, %d yd.']") == "next: %s, %d yd.", "a translation with wrong placeholders isn't used")
        check(lua.eval("ns.L['World map pins']") == "World map pins", "untranslated text stays English")
        # vein names: the local name learned when mining, else English
        lua.execute("ns.db.names['QQ Kupferader'] = 'Copper Vein'")
        check(lua.eval("ns:NodeLabel('Copper Vein')") == "QQ Kupferader", "a learned local vein name is shown")
        check(lua.eval("ns:NodeLabel('Tin Vein')") == "Tin Vein", "an unlearned one stays English")
        en = sandbox.load(FILES, locale="enUS")
        check(en.eval("ns.L['Minimap pins']") == "Minimap pins", "other clients don't load it")

        # fix it; a stale translation fails the check, update drops it and keeps the rest
        text = text.replace('"QQ %d yd: %s"', '"QQ %s, %d yd"') + 'L["Text the code no longer has"] = "QQ old"\n'
        with open(LOC, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(text)
        code, out = tool()
        check(code == 1 and "no longer has: Text the code no longer has" in out, "check catches text the code dropped")
        code, out = tool("update")
        check(code == 0 and "dropped 1" in out, "update drops it: %s" % out.strip())
        code, out = tool()
        check(code == 0 and "qqQQ: 3 of" in out, "and keeps the 3 translations")

        # a locale file the .toc doesn't load
        with open(TOC, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(toc)
        code, out = tool()
        check(code == 1 and "doesn't load Locales\\qqQQ.lua" in out, "check catches a file missing from the .toc")
    finally:
        with open(TOC, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(toc)
        if os.path.exists(LOC):
            os.remove(LOC)

    # every shipped language: its text is used, and the main screens run
    for code in shipped():
        lua = sandbox.load(FILES, locale=code)
        G = lua.globals()
        n = lua.eval("(function() local n = 0 for _ in pairs(ns.L) do n = n + 1 end return n end)()")
        try:
            lua.execute(SCREENS)
            ok, err = True, ""
        except Exception as e:  # a Lua error in a translated string
            ok, err = False, str(e).splitlines()[0]
        out = [m for m in G.printed.values()]
        english = [m for m in out if "spots saved. Commands" in m or "route through" in m]
        check(ok and n >= 180 and not english,
              "%s: %d texts; help, tooltip, route, export, yield and settings run%s" % (code, n, (": " + err) if err else ""))
    check.finish()


def shipped():
    loc = os.path.join(sandbox.ADDON, "Locales")
    return sorted(f[:-4] for f in os.listdir(loc) if len(f) == 8 and f.endswith(".lua") and f[:4] != "qqQQ")


# the help, a pin tooltip, a farm route, an export, the yield list, and every
# formatted text of the settings and share windows' code paths
SCREENS = """
GameTooltip = setmetatable({}, { __index = function() return function() end end })
SlashCmdList.VEINKEEPER('help')
for i, p in ipairs({ {100, 100}, {900, 100}, {900, 900} }) do
  player.x, player.y = p[1] / 1000, p[2] / 1000
  ns:Record('Copper Vein')
  clock = clock + 4000
end
ns:ShowTooltip({}, ns.db.spots[1])
SlashCmdList.VEINKEEPER('route')
ns:Next()
SlashCmdList.VEINKEEPER('route off')
SlashCmdList.VEINKEEPER('near')
SlashCmdList.VEINKEEPER('respawn')
SlashCmdList.VEINKEEPER('yield')
SlashCmdList.VEINKEEPER('only copper')
SlashCmdList.VEINKEEPER('only all')
SlashCmdList.VEINKEEPER('ignore Tin Vein')
SlashCmdList.VEINKEEPER('unignore Tin Vein')
SlashCmdList.VEINKEEPER('map')
SlashCmdList.VEINKEEPER('ready 12')
SlashCmdList.VEINKEEPER('inrange hide')
SlashCmdList.VEINKEEPER('prune 1')
SlashCmdList.VEINKEEPER('clear seen')
local text = ns:Export()
ns:Import(ns:Decode(text), function() end) run_afters()
assert(not ns:Decode('hello'))
for _, sec in ipairs({ 5, 300, 7200, 200000 }) do assert(ns:FormatTime(sec)) end
-- every translation formats with sample values of its placeholders' types
for key, text in pairs(ns.L) do
  local args = {}
  for p in key:gmatch("%%[%-%+ #0]*%d*%.?%d*([%a%%])") do
    if p == "s" then args[#args + 1] = "x" elseif p ~= "%" then args[#args + 1] = 1 end
  end
  local ok, err = pcall(string.format, text, unpack(args))
  if not ok then error(key .. ": " .. err) end
end
"""


if __name__ == "__main__":
    main()
