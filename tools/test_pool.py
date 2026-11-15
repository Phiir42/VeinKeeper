"""Tests visit tracking (VeinKeeper/Pool.lua): do veins come back where they
were? Walks a player past saved spots, mines some, and checks the counts,
/vk pool's verdicts and the tooltip chance.

    pip install lupa
    python tools/test_pool.py
"""
import re

import sandbox

FILES = sandbox.addon_files()


def main():
    check = sandbox.Checks()
    lua = sandbox.load(FILES, before="combat = false UnitAffectingCombat = function() return combat end")
    G = lua.globals()

    def at(x, y):
        G.player.x, G.player.y = x / 1000, y / 1000
        for t in list(G.tickers.values()):
            if not t.cancelled:
                t.fn()

    def mine(x, y, node="Copper Vein"):
        G.player.x, G.player.y = x / 1000, y / 1000
        lua.execute("ns:Record(%r)" % node)

    def counts(node="Copper Vein"):
        c = lua.eval("ns.db.visits[%r]" % node)
        return tuple(c[i] for i in range(1, 5)) if c else (0, 0, 0, 0)

    def state(i):
        return lua.eval("ns:VisitState(ns.db.spots[%d])" % i)

    # two copper spots, mined long ago
    mine(100, 100)
    mine(600, 100)
    G.clock = G.clock + 7200
    check(counts() == (0, 0, 0, 0), "finding new veins isn't a visit")

    # walk up to the first: a "likely back" visit; mine it: a hit
    at(300, 100)
    at(108, 100)
    check(state(1) == "up", "within 12 yd of a likely-back spot: a likely-back visit")
    mine(102, 100)
    check(counts() == (1, 1, 0, 0), "mining it: a hit (%s)" % (counts(),))
    mine(102, 100)  # second tap
    at(104, 100)
    check(counts() == (1, 1, 0, 0) and state(1) is None, "more taps and standing there: still one visit")

    # leave and come straight back: now "not back yet"; leave without mining: a miss
    at(140, 100)
    at(106, 100)
    check(state(1) == "early", "back at the spot just mined: a not-back-yet visit")
    at(150, 100)
    check(counts() == (1, 1, 0, 1), "walked away without mining: a miss (%s)" % (counts(),))

    # passing 20 yd away isn't a visit; in combat or on a flight path neither
    at(620, 100 + 20)
    check(state(2) is None, "20 yd away: not a visit")
    G.combat = True
    at(605, 100)
    check(state(2) is None, "in combat: not counted")
    G.combat = False
    lua.execute("UnitOnTaxi = function() return true end")
    at(603, 100)
    check(state(2) is None, "on a flight path: not counted")
    lua.execute("UnitOnTaxi = function() return false end")
    at(601, 100)
    check(state(2) == "up", "out of combat, on foot: counted")
    # the spot's forgotten mid-visit: dropped, not a miss
    lua.execute("ns:Forget(ns.db.spots[2])")
    at(900, 900)
    check(counts() == (1, 1, 0, 1), "a forgotten spot's visit isn't counted")

    # /vk pool: verdicts from the counts
    def pool(visits):
        lua.execute("ns.db.visits = %s" % visits)
        n = len(G.printed)
        lua.execute("SlashCmdList.VEINKEEPER('pool')")
        return [re.sub(r"\|c\w{8}|\|r", "", m) for m in list(G.printed.values())[n:]]

    out = pool("{}")
    check("no visits recorded yet" in out[0], "nothing yet: says how it's counted")
    out = pool("{ ['Copper Vein'] = { 5, 8, 1, 3 } }")
    check(any("not enough visits yet to tell (8 to likely-back spots, 3 to others)" in l for l in out), "too few to tell")
    out = pool("{ ['Copper Vein'] = { 18, 20, 1, 10 } }")
    print("     " + "\n     ".join(out))
    check(any(l.startswith("  Copper Vein: likely back: 18 of 20 had a vein (90%); not back yet: 1 of 10 (10%)") for l in out),
          "the counts line")
    check("come back where they were" in out[-1], "90% vs 10%: timers per spot hold")
    out = pool("{ ['Copper Vein'] = { 9, 20, 4, 10 } }")
    check("shared pool" in out[-1], "45% vs 40%: a shared pool")
    out = pool("{ ['Copper Vein'] = { 16, 20, 4, 10 } }")
    check("somewhere in between" in out[-1], "80% vs 40%: in between")

    # types sharing spawn points are counted together
    lua.execute("""
      ns.db.spots = {}
      for i, x in ipairs({ 0.1, 0.4 }) do
        ns.db.spots[i] = { map = 1, x = x, y = 0.5, wx = x * 1000, wy = 500, inst = 0, lastOre = 'Tin Vein',
          ores = { ['Tin Vein'] = 1, ['Silver Vein'] = 1 }, first = clock, last = clock - 9000, visits = 2, taps = 2 }
      end
      ns:Changed()
    """)
    out = pool("{ ['Tin Vein'] = { 8, 10, 2, 6 }, ['Silver Vein'] = { 4, 6, 1, 4 } }")
    group = [l for l in out if "Silver Vein / Tin Vein" in l]
    check(len(group) == 1 and "12 of 16 had a vein (75%)" in group[0] and "3 of 10 (30%)" in group[0],
          "Tin and Silver summed on one line: %s" % group)

    # the tooltip shows the measured chance once there are 10 visits
    lua.execute("""
      tip = {}
      GameTooltip = setmetatable({}, { __index = function(_, k) return function(_, a, b)
        if k == 'AddDoubleLine' then tip[#tip + 1] = a .. ': ' .. b end end end })
      ns:ShowTooltip({}, ns.db.spots[1])
    """)
    lines = list(lua.eval("tip").values())
    check("Chance it's up: ~75% (16 visits)" in lines, "tooltip: chance for a likely-back spot: %s" % [l for l in lines if "Chance" in l])
    lua.execute("ns.db.spots[1].last = clock  tip = {}  ns:ShowTooltip({}, ns.db.spots[1])")
    lines = list(lua.eval("tip").values())
    check("Chance it's up: ~30% (10 visits)" in lines, "tooltip: chance for a just-mined spot")
    lua.execute("ns.db.visits = { ['Tin Vein'] = { 3, 4, 0, 2 } }  tip = {}  ns:ShowTooltip({}, ns.db.spots[1])")
    check(not any("Chance" in l for l in lua.eval("tip").values()), "no chance shown before 10 visits")

    # reset asks, then clears
    lua.execute("StaticPopup_Show = function(w) popup = w end  SlashCmdList.VEINKEEPER('pool reset')")
    check(G.popup == "VEINKEEPER_POOL_RESET", "pool reset asks first")
    lua.execute("StaticPopupDialogs.VEINKEEPER_POOL_RESET.OnAccept()")
    check(lua.eval("next(ns.db.visits)") is None, "and clears the counts")

    check.finish()


if __name__ == "__main__":
    main()
