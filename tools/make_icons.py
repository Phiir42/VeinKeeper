"""Generates VeinKeeper node icons (64x64 32-bit TGA) plus a preview sheet."""
import math, random, sys, os
from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageChops

OUT = sys.argv[1]          # addon Icons folder
PREVIEW = sys.argv[2]      # preview png path
S = 256                    # draw size, downsampled to 64
os.makedirs(OUT, exist_ok=True)

# key: (label, ore color, highlight color, style, extra)
ORES = {
    "copper":       ("Copper Vein",            (205, 115, 55),  (255, 190, 120), "vein",    {}),
    "tin":          ("Tin Vein",               (150, 165, 175), (225, 235, 240), "vein",    {}),
    "silver":       ("Silver Vein",            (215, 225, 240), (255, 255, 255), "vein",    {"sparkle": 2}),
    "iron":         ("Iron Deposit",           (150, 80, 60),   (215, 140, 110), "deposit", {}),
    "gold":         ("Gold Vein",              (240, 190, 30),  (255, 240, 140), "vein",    {"sparkle": 3}),
    "mithril":      ("Mithril Deposit",        (70, 170, 150),  (170, 240, 220), "deposit", {}),
    "truesilver":   ("Truesilver Deposit",     (175, 140, 240), (235, 220, 255), "deposit", {"sparkle": 3}),
    "darkiron":     ("Dark Iron Deposit",      (110, 30, 30),   (255, 90, 40),   "deposit", {"glow": (255, 80, 20)}),
    "thorium_small":("Small Thorium Vein",     (60, 190, 110),  (170, 255, 200), "vein",    {}),
    "thorium_rich": ("Rich Thorium Vein",      (60, 200, 115),  (180, 255, 210), "rich",    {"sparkle": 3}),
    "thorium_hakkari":("Hakkari Thorium Vein", (60, 190, 110),  (255, 120, 120), "rich",    {"glow": (220, 40, 60)}),
    "incendicite":  ("Incendicite Mineral Vein",     (240, 90, 30),   (255, 210, 80),  "nodule",  {"glow": (255, 120, 30)}),
    "bloodstone":   ("Lesser Bloodstone Deposit",     (190, 25, 45),   (255, 110, 120), "nodule",  {}),
    "indurium":     ("Indurium Mineral Vein",     (95, 95, 190),   (180, 180, 255), "nodule",  {}),
    "obsidian":     ("Small Obsidian Chunk",     (55, 35, 80),    (180, 150, 230), "shard",   {}),
    # WoW Forever additions
    "copper_poor":  ("Poor Copper Vein",       (170, 105, 70),  (215, 160, 120), "poorvein", {}),
    "amber":        ("Chunk of Amber",         (235, 145, 25),  (255, 225, 130), "nodule",  {}),
    "amber_large":  ("Large Chunk of Amber",   (240, 155, 30),  (255, 235, 150), "nodule",  {"glow": (255, 170, 40), "sparkle": 2}),
    "thorium_heavy":("Heavy Thorium Vein",     (30, 115, 75),   (130, 255, 185), "rich",    {"glow": (60, 255, 140)}),
    "obsidian_large":("Large Obsidian Chunk",  (60, 38, 88),    (190, 160, 240), "shard",   {"sparkle": 2}),
    # Season of Discovery quest nodes that are still in Forever's data
    "coldiron":     ("Cold Iron Deposit",      (120, 170, 210), (220, 245, 255), "deposit", {"glow": (140, 200, 255)}),
    "foolsgold":    ("Fool's Gold Vein",       (175, 150, 60),  (225, 205, 120), "poorvein", {}),
    "starsilver":   ("Starsilver Vein",        (190, 210, 255), (255, 255, 255), "vein",    {"sparkle": 4, "glow": (150, 180, 255)}),
    "moonstone":    ("Greater Moonstone Formation",     (180, 200, 235), (250, 252, 255), "nodule",  {"glow": (170, 200, 255)}),
    "unknown":      ("Unknown Node",           (160, 160, 160), (230, 230, 230), "unknown", {}),
}
OOZE = ["silver", "gold", "mithril", "truesilver", "thorium_small", "thorium_rich"]  # matches Wowhead's Ooze Covered nodes


def shade(c, f):
    return tuple(max(0, min(255, int(v * f))) for v in c)


def rock_polygon(rng, cx, cy, r, n=11):
    pts = []
    for i in range(n):
        a = 2 * math.pi * i / n + rng.uniform(-0.15, 0.15)
        rr = r * rng.uniform(0.82, 1.0)
        pts.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr * 0.86 + 6))
    return pts


def crystal(d, cx, cy, size, ang, col, hi):
    # faceted diamond crystal
    ca, sa = math.cos(ang), math.sin(ang)
    def p(x, y):
        return (cx + x * ca - y * sa, cy + x * sa + y * ca)
    tip, left, right, base = p(0, -size), p(-size * 0.45, 0), p(size * 0.45, 0), p(0, size * 0.55)
    d.polygon([tip, left, base], fill=shade(col, 0.75))
    d.polygon([tip, right, base], fill=col)
    d.polygon([tip, p(-size * 0.12, -size * 0.1), p(size * 0.2, -size * 0.15)], fill=hi)
    d.line([tip, base], fill=shade(col, 0.55), width=2)


def sparkle(d, x, y, r):
    d.polygon([(x, y - r), (x + r * 0.22, y - r * 0.22), (x + r, y), (x + r * 0.22, y + r * 0.22),
               (x, y + r), (x - r * 0.22, y + r * 0.22), (x - r, y), (x - r * 0.22, y - r * 0.22)],
              fill=(255, 255, 255, 255))


def draw_icon(key, label, col, hi, style, extra, ooze=False):
    rng = random.Random(key)
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = S / 2

    # dark round backdrop so the icon reads on any map texture
    d.ellipse([6, 6, S - 6, S - 6], fill=(22, 20, 24, 235))

    # optional glow behind the rock
    if "glow" in extra:
        g = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        ImageDraw.Draw(g).ellipse([40, 40, S - 40, S - 40], fill=extra["glow"] + (170,))
        img = Image.alpha_composite(img, g.filter(ImageFilter.GaussianBlur(22)))
        d = ImageDraw.Draw(img)

    # rock body with simple top-left lighting
    poly = rock_polygon(rng, c, c, 92)
    d.polygon(poly, fill=(92, 86, 82))
    light = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(light).ellipse([40, 30, 170, 150], fill=(150, 142, 135, 255))
    light = light.filter(ImageFilter.GaussianBlur(30))
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).polygon(poly, fill=255)
    img.paste(Image.alpha_composite(img, light), (0, 0), mask)
    d = ImageDraw.Draw(img)
    d.line(poly + [poly[0]], fill=(40, 36, 34), width=6)
    # a few cracks
    for _ in range(3):
        x0, y0 = c + rng.uniform(-50, 50), c + rng.uniform(-40, 50)
        d.line([(x0, y0), (x0 + rng.uniform(-25, 25), y0 + rng.uniform(10, 30))], fill=(55, 50, 48), width=3)

    if style in ("vein", "poorvein"):
        # jagged ore streaks running across the rock (a poor vein has just one)
        for i in ([1] if style == "poorvein" else range(3)):
            y = c - 40 + i * 38 + rng.uniform(-6, 6)
            pts = []
            for k in range(6):
                x = c - 70 + k * 28
                pts.append((x, y + rng.uniform(-10, 10) + (k - 2.5) * -6))
            d.line(pts, fill=shade(col, 0.6), width=26, joint="curve")
            d.line(pts, fill=col, width=17, joint="curve")
            d.line([(px, py - 4) for px, py in pts], fill=hi, width=5, joint="curve")
    elif style in ("deposit", "rich"):
        if style == "deposit":
            spots, size = [(-38, 18, -0.45), (2, -8, 0.0), (42, 22, 0.45)], 62
        else:
            spots, size = [(-46, 20, -0.5), (-14, -12, -0.15), (22, -16, 0.2), (48, 24, 0.5), (0, 40, 0.0)], 52
        for (dx, dy, a) in spots:
            crystal(d, c + dx, c + dy + 6, size, a, col, hi)
    elif style == "nodule":
        for (dx, dy, r) in [(-32, -14, 34), (34, -18, 28), (22, 34, 34), (-30, 40, 22)]:
            x, y = c + dx, c + dy + 6
            d.ellipse([x - r, y - r, x + r, y + r], fill=shade(col, 0.65))
            d.ellipse([x - r + 4, y - r + 3, x + r - 6, y + r - 6], fill=col)
            d.ellipse([x - r * 0.5, y - r * 0.6, x - r * 0.05, y - r * 0.2], fill=hi)
    elif style == "shard":
        for (dx, dy, a) in [(-30, 5, -0.4), (10, -20, 0.1), (35, 18, 0.5), (-5, 30, -0.1)]:
            crystal(d, c + dx, c + dy, 60, a, col, hi)
    elif style == "unknown":
        try:
            font = ImageFont.truetype("arialbd.ttf", 130)
        except OSError:
            font = ImageFont.load_default()
        d.text((c, c + 4), "?", fill=(230, 210, 120), font=font, anchor="mm")

    for i in range(extra.get("sparkle", 0)):
        sparkle(d, c + rng.uniform(-60, 60), c + rng.uniform(-60, 40), rng.uniform(14, 20))

    if ooze:
        # green slime dripping over the top
        g = (90, 200, 60)
        d.ellipse([c - 80, c - 85, c + 80, c - 25], fill=g)
        for dx, ln in [(-55, 40), (-15, 60), (30, 35), (62, 50)]:
            d.rounded_rectangle([c + dx - 9, c - 50, c + dx + 9, c - 50 + ln], 9, fill=g)
        d.ellipse([c - 50, c - 78, c - 10, c - 60], fill=(170, 255, 130))

    # clip to the round backdrop
    clip = Image.new("L", (S, S), 0)
    ImageDraw.Draw(clip).ellipse([6, 6, S - 6, S - 6], fill=255)
    a = img.getchannel("A")
    img.putalpha(ImageChops.multiply(a, clip))
    return img.resize((64, 64), Image.LANCZOS)


def ring():
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse([2, 2, S - 2, S - 2], fill=(255, 255, 255, 255))
    d.ellipse([26, 26, S - 26, S - 26], fill=(0, 0, 0, 0))
    return img.resize((64, 64), Image.LANCZOS)


icons = []
for key, (label, col, hi, style, extra) in ORES.items():
    im = draw_icon(key, label, col, hi, style, extra)
    im.save(os.path.join(OUT, key + ".tga"))
    icons.append((label, im))
for key in OOZE:
    label, col, hi, style, extra = ORES[key]
    im = draw_icon(key, label, col, hi, style, extra, ooze=True)
    im.save(os.path.join(OUT, "ooze_" + key + ".tga"))
    icons.append(("Ooze " + label, im))
ring().save(os.path.join(OUT, "ring.tga"))

# preview sheet: each icon big, plus how it looks at pin size with a ring
cols = 7
cell = 150
rows = (len(icons) + cols - 1) // cols
sheet = Image.new("RGBA", (cols * cell, rows * cell), (48, 44, 38, 255))
sd = ImageDraw.Draw(sheet)
try:
    f = ImageFont.truetype("arial.ttf", 13)
except OSError:
    f = ImageFont.load_default()
rimg = ring()
for i, (label, im) in enumerate(icons):
    x, y = (i % cols) * cell, (i // cols) * cell
    sheet.alpha_composite(im.resize((96, 96), Image.LANCZOS), (x + 10, y + 12))
    small = im.resize((20, 20), Image.LANCZOS)
    sheet.alpha_composite(small, (x + 116, y + 30))
    rr = rimg.resize((24, 24), Image.LANCZOS)
    tint = Image.new("RGBA", rr.size, (60, 255, 60, 255))
    tint.putalpha(rr.getchannel("A"))
    sheet.alpha_composite(small, (x + 116, y + 70))
    sheet.alpha_composite(tint, (x + 114, y + 68))
    sd.text((x + cell / 2, y + 128), label, fill=(240, 230, 210), font=f, anchor="mm")
sheet.save(PREVIEW)
print(len(icons), "icons")
