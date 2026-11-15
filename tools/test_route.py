"""Tests the farm route (VeinKeeper/Route.lua) outside the game.

Loads the addon's Lua files into Lua 5.1 with stubs for the game API, then
checks the loop ordering and how the route moves on as you mine and walk.

    pip install lupa
    python tools/test_route.py
"""
import math, random
from itertools import permutations

import sandbox

FILES = ["Core.lua", "Data.lua", "Spots.lua", "Pins.lua", "Route.lua", "Commands.lua"]


def main():
    lua = sandbox.load(FILES)
    G = lua.globals()
    check = sandbox.Checks()
    failures = check.failures

    # ---- ordering -------------------------------------------------------
    order_loop = lua.eval("function(pts, px, py) local t = {} for i, p in ipairs(pts) do t[i] = { wx = p[1], wy = p[2], id = i } end "
                          "local o = ns.OrderLoop(t, px, py) local r = {} for i, p in ipairs(o) do r[i] = p.id end return r end")

    def to_lua(pts):
        return lua.table_from([lua.table_from(p) for p in pts])

    def loop_len(pts, order):
        return sum(math.dist(pts[order[i] - 1], pts[order[(i + 1) % len(order)] - 1]) for i in range(len(order)))

    # points on a circle, shuffled: the best loop is the circle itself
    rnd = random.Random(1)
    circle = [(500 + 300 * math.cos(a), 500 + 300 * math.sin(a)) for a in [i * 2 * math.pi / 20 for i in range(20)]]
    rnd.shuffle(circle)
    o = list(order_loop(to_lua(circle), 500, 500).values())
    perimeter = 20 * 2 * 300 * math.sin(math.pi / 20)
    check(sorted(o) == list(range(1, 21)), "circle: every point once")
    check(abs(loop_len(circle, o) - perimeter) < 1, "circle: loop is the circle (%.0f vs %.0f yd)" % (loop_len(circle, o), perimeter))

    # random zones: no 2-opt move left, never worse than nearest neighbour,
    # and close to optimal on small sets (brute force)
    for trial in range(30):
        n = rnd.choice([2, 3, 5, 7, 8, 25, 60])
        pts = [(rnd.uniform(0, 1000), rnd.uniform(0, 1000)) for _ in range(n)]
        start = (rnd.uniform(0, 1000), rnd.uniform(0, 1000))
        o = list(order_loop(to_lua(pts), *start).values())
        if sorted(o) != list(range(1, n + 1)):
            check(False, "random %d: permutation" % trial)
            continue
        first_nearest = min(range(n), key=lambda i: math.dist(pts[i], start)) + 1
        if o[0] != first_nearest:
            check(False, "random %d: starts at the stop nearest the player" % trial)
        if 4 <= n <= 8:
            best = min(loop_len(pts, [1] + list(p)) for p in permutations(range(2, n + 1)))
            ratio = loop_len(pts, o) / best
            if ratio > 1.15:
                check(False, "random %d (n=%d): %.2fx optimal" % (trial, n, ratio))
    check(not any(f.startswith("random") for f in failures), "random zones: permutations, nearest start, near-optimal")

    # ---- following the route --------------------------------------------
    def at(x, y):
        G.player.x, G.player.y = x / 1000, y / 1000

    def tick():
        for t in list(G.tickers.values()):
            if not t.cancelled:
                t.fn()

    def mine(x, y):
        at(x, y)
        lua.execute("ns:Record('Copper Vein')")

    def target():
        return lua.eval("(function() for i = 1, #ns.db.spots do local a, n, nx = ns:RouteStop(ns.db.spots[i]) "
                        "if nx then local s = ns.db.spots[i] return math.floor(s.wx + 0.5), math.floor(s.wy + 0.5) end end end)()")

    # four veins on a square, mined an hour ago (all likely back)
    square = [(100, 100), (900, 100), (900, 900), (100, 900)]
    for p in square:
        mine(*p)
    G.clock = G.clock + 3600
    check(lua.eval("#ns.db.spots") == 4, "4 spots saved")

    at(150, 120)
    lua.execute("ns:StartRoute()")
    check(lua.eval("ns:RouteActive()"), "route started")
    check(target() == (100, 100), "first stop is the nearest: %s" % (target(),))
    first_msgs = [m for m in G.printed.values() if "route through" in m]
    check(bool(first_msgs) and "4 spots" in first_msgs[-1] and "3200 yd" in first_msgs[-1],
          "start message: %s" % (first_msgs[-1] if first_msgs else None))

    # mine it: on to a neighbour on the square (not the diagonal)
    mine(100, 100)
    t1 = target()
    check(t1 in [(900, 100), (100, 900)], "after mining, a neighbouring corner: %s" % (t1,))
    check(G.waypoints[len(G.waypoints)].x * 1000 == t1[0], "waypoint follows the route")

    # a second tap of the same vein doesn't move it on again
    n_wp = len(G.waypoints)
    mine(100, 100)
    check(target() == t1 and len(G.waypoints) == n_wp, "multi-tap: no second advance")

    # walk to the next stop, don't mine it, walk on: marked empty, moves on
    at(*t1); tick()
    at(t1[0], 500); tick()
    t2 = target()
    check(t2 == (900, 900), "walked past an empty stop: on to %s" % (t2,))

    # arrive at a stop that isn't back yet: moved on at once
    G.clock = G.clock + 1
    mine(*t2)  # mined: now red
    t3 = target()
    at(*t3)
    lua.execute("ns:MarkEmpty((function() for _, s in ipairs(ns.db.spots) do local _, _, nx = ns:RouteStop(s) if nx then return s end end end)())")
    tick()
    t4 = target()
    check(t4 != t3, "arrived at a stop not back yet: moved on (%s -> %s)" % (t3, t4))

    # a new vein mined in the zone joins the loop between its neighbours
    mine(500, 80)
    check(lua.eval("(select(2, ns:RouteStop(ns.db.spots[#ns.db.spots])))") == 5, "new vein joins the loop (5 stops)")
    idx = lambda x, y: lua.eval("(function() for _, s in ipairs(ns.db.spots) do if math.abs(s.wx - %d) < 1 and math.abs(s.wy - %d) < 1 then return (ns:RouteStop(s)) end end end)()" % (x, y))
    a, b, c = idx(100, 100), idx(500, 80), idx(900, 100)
    adjacent = lambda i, j: (i - j) % 5 in (1, 4)
    check(adjacent(a, b) and adjacent(b, c), "inserted between (100,100) and (900,100): stops %d, %d, %d" % (a, b, c))

    # skip with /vk next
    before = target()
    lua.execute("ns:Next()")
    check(target() != before, "/vk next skips a stop on a route")

    # forgetting the next stop moves the route on
    before = target()
    lua.execute("(function() for _, s in ipairs(ns.db.spots) do local _, _, nx = ns:RouteStop(s) if nx then ns:Forget(s) return end end end)()")
    check(target() is not None and target() != before, "forgot the next stop: moved on to %s" % (target(),))

    # world map: one line per leg of the loop
    n_stops = lua.eval("(select(2, ns:RouteStop(ns.db.spots[1])))")
    shown = lua.eval("function() local n = 0 for _, o in ipairs(made or {}) do if o.shown then n = n + 1 end end return n, #(made or {}) end")
    lua.execute("WorldMapFrame.provider:RefreshAllData()")
    vis, total = shown()
    check(vis == n_stops, "world map draws one line per leg (%d lines, %d stops)" % (vis, n_stops))
    lua.execute("WorldMapFrame.provider:RefreshAllData()")
    check(shown()[1] == total, "redrawing reuses its lines")

    # stop
    lua.execute("ns:StopRoute()")
    check(not lua.eval("ns:RouteActive()"), "route stopped")
    check(shown()[0] == 0, "stopping clears the lines")
    lua.execute("ns:Next()")  # back to plain /vk next without error
    lua.execute("SlashCmdList.VEINKEEPER('route')")
    check(lua.eval("ns:RouteActive()"), "/vk route starts it")
    lua.execute("SlashCmdList.VEINKEEPER('route off')")
    check(not lua.eval("ns:RouteActive()"), "/vk route off stops it")

    # too few spots
    lua.execute("ns.db.spots = {} ns:Changed() ns:StartRoute()")
    check("needs 2 or more" in G.printed[len(G.printed)], "empty zone: explains why")

    check.finish()


if __name__ == "__main__":
    main()
