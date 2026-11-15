"""Tests yield tracking (VeinKeeper/Yield.lua) outside the game, with stubbed
loot windows.

    pip install lupa
    python tools/test_yield.py
"""
import re

import sandbox

FILES = sandbox.addon_files()

LOOT = """
now = 100
GetTime = function() return now end
loot = {}
GetNumLootItems = function() return #loot end
GetLootSourceInfo = function(i) return loot[i].guid, loot[i].qty end
GetLootSlotLink = function(i) return loot[i].link end
GetLootSlotInfo = function(i) return 'icon', 'name', loot[i].qty end
local names = { [2770] = 'Copper Ore', [2835] = 'Rough Stone', [818] = 'Tigerseye', [774] = 'Malachite',
  [10620] = 'Thorium Ore', [12365] = 'Dense Stone', [7910] = 'Star Ruby' }
C_Item = { GetItemNameByID = function(id) return names[id] end }
"""

# object IDs: Copper Vein 1731, Rich Thorium Vein 175404
def guid(obj, spawn):
    return "GameObject-0-4372-0-17-%d-%08X" % (obj, spawn)


def main():
    check = sandbox.Checks()
    lua = sandbox.load(FILES, before=LOOT)
    G = lua.globals()

    def open_loot(source, items, t=4):
        """One loot window: items = [(item ID, quantity)], from `source`
        (a GUID, or a list of GUIDs one per item)."""
        G.now = G.now + t
        rows = []
        for k, (item, qty) in enumerate(items):
            src = source[k] if isinstance(source, list) else source
            rows.append(lua.table_from({"guid": src, "qty": qty,
                                        "link": "|cffffffff|Hitem:%d::::::::60:::::|h[x]|h|r" % item}))
        G.loot = lua.table_from(rows)
        lua.execute("ns:Fire('LOOT_READY')")

    def y(name):
        t = lua.eval("ns.db.yield[%r]" % name)
        if t is None:
            return None
        return {"v": t.v, "t": t.t, "i": {k: (e[1], e[2]) for k, e in t.i.items()}}

    def printed_since(n):
        return [re.sub(r"\|c\w{8}|\|r", "", m) for m in list(G.printed.values())[n:]]

    # a multi-tap copper vein: three loot windows, one visit
    copper = guid(1731, 1)
    open_loot(copper, [(2770, 2), (2835, 1)])
    open_loot(copper, [(2770, 1)])
    open_loot(copper, [(2770, 2), (818, 1)])
    c = y("Copper Vein")
    check(c["v"] == 1 and c["t"] == 3, "multi-tap vein: 1 visit, 3 taps (%s)" % c)
    check(c["i"][2770] == (5, 1) and c["i"][2835] == (1, 1) and c["i"][818] == (1, 1), "items summed over the taps")

    # the same loot window reported twice
    open_loot(copper, [(2770, 2)], t=0.2)
    check(y("Copper Vein")["t"] == 3, "the same loot window twice counts once")

    # two more copper veins (new GUIDs)
    open_loot(guid(1731, 2), [(2770, 3), (2835, 2)])
    open_loot(guid(1731, 3), [(2770, 2), (774, 1)])
    c = y("Copper Vein")
    check(c["v"] == 3 and c["i"][2770] == (10, 3), "new GUIDs are new visits (%s)" % c)

    # not counted: a mob, loot from a vein and a mob at once, an ignored node
    open_loot("Creature-0-4372-0-17-1234-0000000001", [(2770, 5)])
    open_loot([guid(1731, 4), "Creature-0-1-0-1-99-0000000002"], [(2770, 2), (2770, 1)])
    lua.execute("ns.db.ignore['Copper Vein'] = true")
    open_loot(guid(1731, 5), [(2770, 2)])
    lua.execute("ns.db.ignore['Copper Vein'] = nil")
    check(y("Copper Vein")["v"] == 3, "mob loot, mixed loot and ignored nodes aren't counted")

    # tooltip text: "3.3 Copper Ore a visit (3 visits)"
    text = lua.eval("ns:YieldText('Copper Vein')")
    check(text == "3.3 Copper Ore a visit (3 visits)", "tooltip yield: %s" % text)
    check(lua.eval("ns:YieldText('Rich Thorium Vein')") is None, "no yield line before 3 visits")

    # in the pin tooltip
    lua.execute("""
      tip_lines = {}
      GameTooltip = setmetatable({}, { __index = function(t, k) return function(self, a, b)
        if k == 'AddDoubleLine' then tip_lines[#tip_lines + 1] = tostring(a) .. ': ' .. tostring(b) end end end })
      ns.db.spots[1] = { map = 1, x = 0.5, y = 0.5, ores = { ['Copper Vein'] = 2 }, lastOre = 'Copper Vein',
        first = clock, last = clock, visits = 2, taps = 2 }
      ns:ShowTooltip({}, ns.db.spots[1])
    """)
    lines = list(lua.eval("tip_lines").values())
    check("Yield: 3.3 Copper Ore a visit (3 visits)" in lines, "pin tooltip shows the yield")

    # a few thorium visits, then /vk yield
    for k in range(4):
        open_loot(guid(175404, 10 + k), [(10620, 4 + k % 2), (12365, 1)] + ([(7910, 1)] if k == 0 else []), t=120)
    G.clock = G.clock + 30 * 60
    n = len(G.printed)
    lua.execute("SlashCmdList.VEINKEEPER('yield')")
    out = printed_since(n)
    print("     " + "\n     ".join(out))
    check(any(l.startswith("  Copper Vein (3 visits): 3.3 Copper Ore, Rough Stone 67%") for l in out),
          "copper line: the ore as an amount, stone (2 of 3 visits) as a chance")
    check(any("Tigerseye 33%" in l and "Malachite 33%" in l for l in out), "rare items as a chance a visit")
    thor = [l for l in out if l.startswith("  Rich Thorium Vein")]
    check(thor and "4.5 Thorium Ore" in thor[0] and "Star Ruby 25%" in thor[0], "thorium line: %s" % thor)
    check(out.index([l for l in out if l.startswith("  Copper")][0]) < out.index(thor[0]), "lowest skill first")
    sess = [l for l in out if "this session" in l]
    check(sess and sess[0].startswith("  this session: 7 visits in 30m:") and "Thorium Ore an hour" in sess[0],
          "session line with ore an hour: %s" % sess)
    rate = int(re.search(r"~(\d+) Thorium Ore an hour", sess[0]).group(1))
    check(rate == 36, "18 Thorium Ore in 30 min is 36 an hour (%d)" % rate)

    # reset asks first, then clears
    lua.execute("StaticPopup_Show = function(which) popup = which end")
    lua.execute("SlashCmdList.VEINKEEPER('yield reset')")
    check(G.popup == "VEINKEEPER_YIELD_RESET", "yield reset asks first")
    lua.execute("StaticPopupDialogs.VEINKEEPER_YIELD_RESET.OnAccept()")
    check(y("Copper Vein") is None, "yield reset clears the counts")
    n = len(G.printed)
    lua.execute("SlashCmdList.VEINKEEPER('yield')")
    check("no yield yet" in printed_since(n)[0], "empty: says how it fills")

    check.finish()


if __name__ == "__main__":
    main()
