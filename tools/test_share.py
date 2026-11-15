"""Tests exporting and importing spots (VeinKeeper/Share.lua) outside the game.

    pip install lupa
    python tools/test_share.py
"""
import re, time

import sandbox

FILES = sandbox.addon_files()


def player(lua):
    """Helpers bound to one player's sandbox."""
    G = lua.globals()

    def at(x, y):
        G.player.x, G.player.y = x / 1000, y / 1000

    def mine(x, y, node="Copper Vein"):
        at(x, y)
        lua.execute("ns:Record(%r)" % node)
        G.clock = G.clock + 600

    def spots():
        out = []
        for s in lua.eval("ns.db.spots").values():
            out.append({
                "x": s.wx, "y": s.wy, "ores": dict(s.ores.items()), "last": s.last,
                "seenAt": s.seenAt, "imported": s.imported, "visits": s.visits, "map": s.map,
            })
        return out

    def export(want="nil"):
        return lua.eval("(function() return ns:Export(%s) end)()" % want)

    def import_(text):
        res = {}
        lua.globals().paste = text
        lua.execute("""
          local list, why = ns:Decode(paste)
          result = { why = why, n = list and #list }
          if list then ns:Import(list, function(new, known, ignored)
            result.new, result.known, result.ignored = new, known, ignored end) end
        """)
        lua.execute("run_afters()")
        r = lua.eval("result")
        return {k: r[k] for k in ("why", "n", "new", "known", "ignored")}

    return G, at, mine, spots, export, import_


def main():
    check = sandbox.Checks()

    # ---- the exporting player -------------------------------------------
    a = sandbox.load(FILES)
    G, at, mine, spots, export, _ = player(a)
    mine(100, 100)                           # copper
    mine(500, 500, "Tin Vein")               # tin, then silver at the same spawn point
    G.clock = G.clock + 3600
    mine(501, 500, "Silver Vein")
    mine(800, 200, "Mithril Deposit")
    # a vein only hovered on the minimap: 6 yd good
    a.execute("ns:RecordSeen('Iron Deposit', 300, 700, 0, 1, 0.3, 0.7, 12, 6)")
    check(len(spots()) == 4, "exporter has 4 spots (Tin and Silver share one)")

    text, n = export()
    check(n == 4, "export: 4 spots (%d)" % n)
    check(re.match(r"^VK1:\w+:@1:", text) is not None, "export: prefix, checksum, zone block: %s..." % text[:24])
    check(len(text) < 120, "export: compact (%d characters for 4 spots)" % len(text))

    # filter: only thorium -> nothing; only tin's ore (Tin Ore) -> 1
    a.execute("ns.db.settings.only = 2771")
    check(export()[1] == 1, "export honours the ore filter")
    a.execute("ns.db.settings.only = false")

    # ---- the importing player -------------------------------------------
    b = sandbox.load(FILES)
    G2, at2, mine2, spots2, export2, imp = player(b)
    mine2(103, 100)  # B already mined that copper vein, 3 yd off A's position
    before = spots2()[0]

    r = imp(text)
    check(r["n"] == 4 and r["new"] == 3 and r["known"] == 1, "import: 3 new, 1 already known (%s)" % r)
    sp = spots2()
    check(len(sp) == 4, "importer now has 4 spots")
    own = [s for s in sp if s["last"]]
    check(len(own) == 1 and abs(own[0]["x"] - before["x"]) < 0.01 and own[0]["visits"] == 1,
          "importer's own mined spot kept its position and visits")
    tin = [s for s in sp if "Tin Vein" in s["ores"]]
    check(len(tin) == 1 and set(tin[0]["ores"]) == {"Tin Vein", "Silver Vein"} and tin[0]["ores"]["Silver Vein"] == 0,
          "shared spawn point arrives as one spot with both ores, mined 0 times")
    check(abs(tin[0]["x"] - 500.5) < 1 and abs(tin[0]["y"] - 500) < 1, "position survives (%.1f, %.1f)" % (tin[0]["x"], tin[0]["y"]))
    imported = [s for s in sp if s["imported"]]
    check(len(imported) == 3 and all(s["last"] is None and s["seenAt"] is None for s in imported),
          "imported spots: flagged, never mined, never seen")
    check(b.eval("ns:Wait(ns.db.spots[2])") == 0, "imported spots count as likely up")
    blue = b.eval("(function() local r, g, bl = ns:Freshness(ns.db.spots[2]) return bl end)()")
    check(blue == 1, "imported spots get the blue ring")
    tip = []
    b.globals().GameTooltip = b.eval("""setmetatable({}, { __index = function(t, k) return function(self, a, b)
        if k == 'AddLine' or k == 'AddDoubleLine' then tip_lines[#tip_lines + 1] = tostring(a) .. ' ' .. tostring(b) end end end })""")
    b.execute("tip_lines = {} ns:ShowTooltip({}, ns.db.spots[2])")
    lines = list(b.eval("tip_lines").values())
    check(any("Imported, not mined or seen yet" in l for l in lines), "tooltip says imported: %s" % lines[:2])

    # again: nothing new
    r = imp(text)
    check(r["new"] == 0 and r["known"] == 4 and len(spots2()) == 4, "importing again adds nothing (%s)" % r)

    # pasting with line breaks and spaces in it still works
    messy = " \n".join(text[i:i + 10] for i in range(0, len(text), 10))
    check(imp(messy)["n"] == 4, "line breaks and spaces in the paste are ignored")

    # bad pastes
    check("incomplete" in (imp(text[:-3])["why"] or ""), "a cut-off paste is caught: %s" % imp(text[:-3])["why"])
    tampered = text[:-1] + ("a" if text[-1] != "a" else "b")
    check("incomplete" in (imp(tampered)["why"] or ""), "a changed paste is caught")
    check("isn't a VeinKeeper export" in (imp("hello there")["why"] or ""), "not an export: explained")
    check("newer" in (imp("VK2:abc:@1:whatever")["why"] or ""), "a newer format: explained")

    # an unknown zone (map 999) and an unknown ore are skipped, the rest imported
    a.execute("ns.db.spots[1].map = 999")
    t2, n2 = export()
    a.execute("ns.db.spots[1].map = 1")
    c = sandbox.load(FILES)
    *_, imp3 = player(c)
    r = imp3(t2)
    check(r["n"] == 3 and r["why"] == 1, "a spot on a map this client lacks is skipped (%s)" % r)

    # ignored ores aren't imported
    c2 = sandbox.load(FILES)
    *_, imp4 = player(c2)
    c2.execute("ns.db.ignore['Copper Vein'] = true")
    r = imp4(text)
    check(r["ignored"] == 1 and r["new"] == 3, "ignored ores are left out (%s)" % r)

    # mining an imported spot makes it yours: no duplicate
    G2.clock = G2.clock + 60
    mine2(800, 202, "Mithril Deposit")
    mith = [s for s in spots2() if "Mithril Deposit" in s["ores"]]
    check(len(mith) == 1 and mith[0]["last"] is not None and mith[0]["visits"] == 1,
          "mining an imported spot joins it")

    # prune leaves fresh imports alone; clear imported removes untouched ones only
    b.execute("StaticPopup_Show = function() popup = true end popup = false ns:Prune(30)")
    check(not b.eval("popup"), "prune leaves fresh imports alone")
    b.execute("SlashCmdList.VEINKEEPER('clear imported')")
    left = spots2()
    check(len(left) == 2 and all(s["last"] for s in left), "clear imported removes the 2 untouched imports, keeps mined ones")

    # a big import is merged in batches, without duplicates
    big = sandbox.load(FILES)
    Gb, atb, mineb, spotsb, exportb, impb = player(big)
    big.execute("""
      for i = 0, 1999 do
        local x, y = (i % 50) * 20 + 5, math.floor(i / 50) * 20 + 5
        ns:RecordSeen('Copper Vein', x, y, 0, 1, x / 1000, y / 1000, 12, 4)
      end
    """)
    tb, nb = exportb()
    check(nb == 2000, "2000-spot export (%d characters)" % len(tb))
    d = sandbox.load(FILES)
    *_, impd = player(d)
    t0 = time.time()
    r = impd(tb)
    secs = time.time() - t0
    check(r["new"] == 2000 and d.eval("#ns.db.spots") == 2000, "2000-spot import: all new, none merged (%s)" % r)
    print("     (%.2f s in Lua 5.1 here)" % secs)

    check.finish()


if __name__ == "__main__":
    main()
