"""Tests respawn learning (Spots.lua): samples of vein types that share spawn
points are pooled.

    pip install lupa
    python tools/test_respawn.py
"""
import re

import sandbox

FILES = ["Core.lua", "Data.lua", "Spots.lua", "Pins.lua", "Share.lua", "Yield.lua", "Route.lua", "Commands.lua"]


def spot(x, ores, last=None):
    """A saved spot as Lua, at map x (yards / 1000), y 0.5."""
    o = ", ".join('["%s"] = %d' % (k, v) for k, v in ores.items())
    lo = next(iter(ores))
    extra = ("last = %d, visits = 1, taps = 1, gx = %s, gy = 0.5, gN = 1" % (last, x / 1000)) if last else \
        ("seenAt = 1000000, visits = 0, taps = 0, hx = %s, hy = 0.5, hErr = 5, hBest = 5" % (x / 1000))
    return ('{ map = 1, x = %s, y = 0.5, wx = %s, wy = 500, inst = 0, ores = { %s }, lastOre = "%s", first = 900000, %s }'
            % (x / 1000, x, o, lo, extra))


def db(spots, respawn):
    r = ", ".join('["%s"] = { %s }' % (k, ", ".join(str(v) for v in vs)) for k, vs in respawn.items())
    return ("clock = 1000000\nVeinKeeperDB = { respawnSeeded = true, seenNote = true, spots = { %s }, respawn = { %s } }"
            % (", ".join(spots), r))


def main():
    check = sandbox.Checks()
    T, S, C = "Tin Vein", "Silver Vein", "Copper Vein"

    # Tin and Silver seen together at two spots (300 yd apart, so no merging);
    # two samples each: alone neither has 3, pooled they have 4
    lua = sandbox.load(FILES, before=db(
        [spot(100, {T: 2, S: 0}, last=999000), spot(400, {T: 1, S: 1}, last=999000), spot(700, {C: 3}, last=999000)],
        {T: [600, 700], S: [650, 2000], C: [300, 320]}))
    group = list(lua.eval("ns:RespawnGroup('Tin Vein')").values())
    check(group == [S, T], "Tin and Silver, seen together at 2 spots, are one group: %s" % group)
    check(list(lua.eval("ns:RespawnGroup('Copper Vein')").values()) == [C], "Copper stays on its own")
    sec, n = lua.eval("ns:Respawn('Tin Vein')")
    check(n == 4 and sec == 600, "Tin's estimate pools Silver's samples: %ss from %d samples" % (sec, n))
    check(tuple(lua.eval("ns:Respawn('Silver Vein')")) == (600, 4), "Silver gets the same estimate")
    sec, n = lua.eval("ns:Respawn('Copper Vein')")
    check(n == 0 and sec == 600, "Copper, 2 samples alone, still uses the setting (10 min)")

    # /vk respawn lists the group once
    n0 = len(lua.globals().printed)
    lua.execute("SlashCmdList.VEINKEEPER('respawn')")
    out = [re.sub(r"\|c\w{8}|\|r", "", m) for m in list(lua.globals().printed.values())[n0:]]
    print("     " + "\n     ".join(out))
    check(any(l.startswith("  Silver Vein / Tin Vein: ~10m (4 samples)") for l in out), "/vk respawn: one line for the group")
    check(sum("Tin Vein" in l for l in out) == 1, "the group isn't listed twice")
    check(any(l.startswith("  Copper Vein: ~10m (2 sample(s) so far") for l in out), "Copper: its 2 samples so far")

    # the pin tooltip counts the pooled samples
    lua.execute("""
      tip = {}
      GameTooltip = setmetatable({}, { __index = function(_, k) return function(_, a, b)
        if k == 'AddDoubleLine' then tip[#tip + 1] = a .. ': ' .. b end end end })
      ns:ShowTooltip({}, ns.db.spots[1])
    """)
    lines = list(lua.eval("tip").values())
    check("Respawn: ~10m (learned, 4)" in lines, "tooltip: learned from the pooled 4")

    # seen together at only one spot: kept apart (it may be two veins saved as one)
    one = sandbox.load(FILES, before=db(
        [spot(100, {T: 2, S: 1}, last=999000), spot(400, {T: 1}, last=999000)], {T: [600, 700], S: [650, 2000]}))
    check(list(one.eval("ns:RespawnGroup('Tin Vein')").values()) == [T], "together at one spot only: not grouped")
    check(one.eval("ns:Respawn('Tin Vein')")[1] == 0, "so Tin's 2 samples aren't enough yet")

    # a spot gaining an ore later joins the groups (no reload needed)
    lua2 = sandbox.load(FILES, before=db(
        [spot(100, {T: 1, S: 1}, last=999000), spot(400, {T: 1}, last=999000)], {T: [600, 700], S: [650]}))
    check(lua2.eval("ns:Respawn('Tin Vein')")[1] == 0, "before: one spot with both, not grouped")
    lua2.execute("ns:RecordSeen('Silver Vein', 400, 500, 0, 1, 0.4, 0.5, 12, 5)")
    check(list(lua2.eval("ns:RespawnGroup('Tin Vein')").values()) == [S, T], "Silver's dot seen at the second Tin spot: grouped")
    # (seeing the dot 1000 s after the spot was mined is itself a Silver sample)
    check(tuple(lua2.eval("ns:Respawn('Tin Vein')")) == (600, 4), "and the estimate pools all 4 samples, the new one too")

    # three types chained by pairs form one group (Mithril-Truesilver, Truesilver-Thorium)
    M, TS, TH = "Mithril Deposit", "Truesilver Deposit", "Small Thorium Vein"
    lua3 = sandbox.load(FILES, before=db(
        [spot(100, {M: 1, TS: 1}, 999000), spot(300, {M: 1, TS: 0}, 999000),
         spot(500, {TS: 1, TH: 1}, 999000), spot(700, {TS: 0, TH: 1}, 999000)],
        {M: [900], TS: [1000], TH: [1100]}))
    check(list(lua3.eval("ns:RespawnGroup('Mithril Deposit')").values()) == [M, TH, TS], "pairs chain into one group")
    check(lua3.eval("ns:Respawn('Small Thorium Vein')")[1] == 3, "all three pool their samples")

    check.finish()


if __name__ == "__main__":
    main()
