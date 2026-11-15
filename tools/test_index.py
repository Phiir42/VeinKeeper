"""Tests the spatial index in Spots.lua against VeinKeeper 1.2.10, which
looked at every saved spot.

Both versions load the same random saved spots (duplicates for the login
merges included), then get the same random mining, minimap hovers, imports
and forgets; their saved spots must match exactly at every step. Then it
times login and a big import in both.

    pip install lupa
    python tools/test_index.py [reference tag, default v1.2.10]
"""
import random, subprocess, sys, time

import sandbox

FILES = ["Core.lua", "Data.lua", "Spots.lua", "Pins.lua", "Share.lua", "Yield.lua", "Route.lua", "Commands.lua"]
NODES = ["Copper Vein", "Tin Vein", "Silver Vein"]

# zone k is the 1000 x 1000 yd square at world x (k - 1) * 1000 (zone 999 has
# no world position at all)
WORLD = """
C_Map.GetWorldPosFromMapPos = function(id, v)
  if id == 999 then return nil end
  return 0, { GetXY = function() return v.x * 1000 + (id - 1) * 1000, v.y * 1000 end }
end
"""


def g(v):
    return "%.17g" % v


def saved_spots(rnd, n, zones):
    """VeinKeeperDB as Lua source: n spots over `zones` zones, with near
    duplicates of mined spots and hovers near them."""
    spots = []
    now = 1000000

    def spot(m, x, y, mined, name):
        s = {"map": m, "x": x, "y": y, "ores": {name: rnd.randint(1, 4) if mined else 0}, "lastOre": name,
             "first": now - rnd.randint(10000, 900000), "visits": 0, "taps": 0}
        if m != 999:
            s.update(wx=x * 1000 + (m - 1) * 1000, wy=y * 1000, inst=0)
        if mined:
            s.update(last=now - rnd.randint(0, 90000), visits=rnd.randint(1, 5), gx=x, gy=y, gN=rnd.randint(1, 6))
            s["taps"] = s["visits"] + rnd.randint(0, 3)
            if rnd.random() < 0.3:
                s["minGap"] = rnd.randint(200, 3000)
            if rnd.random() < 0.2:
                s["seenAt"] = now - rnd.randint(0, 50000)
        else:
            err = rnd.uniform(1, 25)
            s.update(seenAt=now - rnd.randint(0, 90000), hx=x, hy=y, hErr=err, hBest=max(err, rnd.uniform(1, 25)))
        return s

    while len(spots) < n:
        m = 999 if rnd.random() < 0.01 else rnd.randint(1, zones)
        x, y = rnd.random(), rnd.random()
        name = rnd.choice(NODES)
        mined = rnd.random() < 0.7
        spots.append(spot(m, x, y, mined, name))
        r = rnd.random()
        if mined and r < 0.15:   # the same vein saved twice
            spots.append(spot(m, x + rnd.uniform(-0.007, 0.007), y + rnd.uniform(-0.007, 0.007), True, name))
        elif r < 0.45:          # a hover of it, or of a neighbour
            spots.append(spot(m, x + rnd.uniform(-0.03, 0.03), y + rnd.uniform(-0.03, 0.03), False,
                              name if rnd.random() < 0.8 else rnd.choice(NODES)))
    rnd.shuffle(spots)

    def lua(v):
        if isinstance(v, dict):
            return "{" + ",".join("[%s]=%s" % (lua(k), lua(x)) for k, x in v.items()) + "}"
        if isinstance(v, str):
            return '"%s"' % v
        if isinstance(v, float):
            return g(v)
        return str(v)
    return "clock = %d\nVeinKeeperDB = { respawnSeeded = true, seenNote = true, spots = {%s} }" % (
        now, ",\n".join(lua(s) for s in spots))


FIELDS = ["map", "x", "y", "wx", "wy", "last", "seenAt", "imported", "visits", "taps", "minGap",
          "gx", "gy", "gN", "hx", "hy", "hErr", "hBest", "lastOre", "first"]
DUMP = "return function() local out = {} for i, s in ipairs(ns.db.spots) do local r = {} " + \
       " ".join("r[%d] = s.%s;" % (i + 1, f) for i, f in enumerate(FIELDS)) + \
       " local o = {} for k, v in pairs(s.ores) do o[#o + 1] = k .. '=' .. v end table.sort(o) r[%d] = table.concat(o, ',')" % (len(FIELDS) + 1) + \
       " out[i] = r end return out end"


def dump(lua):
    rows = []
    for r in lua.execute(DUMP)().values():
        row = []
        for i in range(1, len(FIELDS) + 2):
            v = r[i]
            row.append(round(v, 9) if isinstance(v, float) else v)
        rows.append(tuple(row))
    return rows


def ops(rnd, n, zones):
    """Random events, as Lua."""
    out = []
    for _ in range(n):
        r = rnd.random()
        m = rnd.randint(1, zones)
        x, y = rnd.random(), rnd.random()
        name = rnd.choice(NODES)
        if r < 0.35:
            out.append("player.x, player.y = %s, %s  C_Map.GetBestMapForUnit = function() return %d end  ns:Record(%r)" % (g(x), g(y), m, name))
        elif r < 0.7:
            wx = x * 1000 + (m - 1) * 1000
            out.append("ns:RecordSeen(%r, %s, %s, 0, %d, %s, %s, 12, %s)" % (name, g(wx), g(y * 1000), m, g(x), g(y), g(rnd.uniform(1, 30))))
        elif r < 0.9:
            out.append("ns:ImportSpot(%d, %s, %s, %s, { %r }, clock)" % (m, g(x), g(y), g(rnd.uniform(1, 20)), name))
        else:
            out.append("local i = %d %% math.max(1, #ns.db.spots) + 1 if ns.db.spots[i] then ns:Forget(ns.db.spots[i]) end" % rnd.randint(0, 10 ** 6))
        out.append("clock = clock + %d" % rnd.choice([5, 60, 200, 4000]))
    return out


def main():
    ref = sys.argv[1] if len(sys.argv) > 1 else "v1.2.10"
    old_spots = subprocess.run(["git", "show", ref + ":VeinKeeper/Spots.lua"], capture_output=True, text=True,
                               encoding="utf-8", check=True, cwd=sandbox.ROOT).stdout
    check = sandbox.Checks()

    # ---- the same results ---------------------------------------------------
    for seed, n, zones in [(1, 300, 2), (2, 1200, 6), (3, 800, 1), (4, 2000, 15)]:
        rnd = random.Random(seed)
        db = WORLD + saved_spots(rnd, n, zones)
        old = sandbox.load(FILES, {"Spots.lua": old_spots}, db)
        new = sandbox.load(FILES, None, db)
        a, b = dump(old), dump(new)
        check(a == b, "seed %d, %d saved spots over %d zones: same after the login merges (%d -> %d spots)"
              % (seed, n, zones, n, len(b)))
        script = ops(rnd, 600, zones)
        same = True
        for i, line in enumerate(script):
            old.execute(line)
            new.execute(line)
            if i % 50 == 0 or i == len(script) - 1:
                a, b = dump(old), dump(new)
                if a != b:
                    same = False
                    for k, (ra, rb) in enumerate(zip(a, b)):
                        if ra != rb:
                            print("     first difference after op %d, spot %d:\n     old %s\n     new %s" % (i, k + 1, ra, rb))
                            break
                    else:
                        print("     after op %d: %d vs %d spots" % (i, len(a), len(b)))
                    break
        check(same, "seed %d: same through 600 random mines, hovers, imports and forgets (%d spots now)" % (seed, len(b)))

    # ---- speed -----------------------------------------------------------------
    print()
    rnd = random.Random(9)
    big = WORLD + saved_spots(rnd, 6000, 60)
    times = {}
    for label, src in (("1.2.10", {"Spots.lua": old_spots}), ("index", None)):
        t0 = time.perf_counter()
        lua = sandbox.load(FILES, src, big)
        t_login = time.perf_counter() - t0
        # someone else's 3000 spots over the same zones
        other = sandbox.load(FILES, None, WORLD + saved_spots(random.Random(10), 3000, 60))
        text = other.eval("(ns:Export(function() return true end))")
        lua.globals().paste = text
        t0 = time.perf_counter()
        lua.execute("local list = ns:Decode(paste) ns:Import(list, function() end) run_afters()")
        t_import = time.perf_counter() - t0
        times[label] = (t_login, t_import)
        print("     %-7s login with 6000 spots %6.0f ms, importing 3000 %6.0f ms (Lua 5.1 here)" % (label, t_login * 1000, t_import * 1000))
    check(times["index"][0] * 3 < times["1.2.10"][0], "login merges at least 3x faster")
    check(times["index"][1] * 3 < times["1.2.10"][1], "import at least 3x faster")

    check.finish()


if __name__ == "__main__":
    main()
