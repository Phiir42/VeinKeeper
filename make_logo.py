"""Builds the VeinKeeper logo files from art/logo-source.png (the icon art:
square, on a flat dark background).

    python make_logo.py   # needs Pillow; writes
      .github/icon.png             256 px, for the README
      .github/social-preview.png   1280x640, upload under the repo's Settings >
                                   General > Social preview (the WowUp Hub uses it)
      VeinKeeper/Icons/logo.tga    64 px, the in-game addon list / compartment icon
"""
import os
from PIL import Image, ImageChops

ROOT = os.path.dirname(os.path.abspath(__file__))
MARGIN = 0.84  # the art fills this much of each square, the rest is background


def background(img):
    w, h = img.size
    corners = [img.getpixel(p) for p in [(3, 3), (w - 4, 3), (3, h - 4), (w - 4, h - 4)]]
    return tuple(sum(c[i] for c in corners) // len(corners) for i in range(3))


def flatten(src, bg, tolerance=14):
    """Snap near-background pixels to the exact background colour, so the art
    has no faint square around it when placed on a wider background."""
    flat = Image.new("RGB", src.size, bg)
    r, g, b = ImageChops.difference(src, flat).split()
    near = ImageChops.lighter(ImageChops.lighter(r, g), b).point(lambda v: 255 if v < tolerance else 0)
    src = src.copy()
    src.paste(flat, mask=near)
    return src


def square(src, bg, size):
    """The art centred on a background square, with margin."""
    out = Image.new("RGB", (size, size), bg)
    s = int(size * MARGIN)
    out.paste(src.resize((s, s), Image.LANCZOS), ((size - s) // 2, (size - s) // 2))
    return out


def main():
    src = Image.open(os.path.join(ROOT, "art", "logo-source.png")).convert("RGB")
    bg = background(src)
    src = flatten(src, bg)

    square(src, bg, 256).save(os.path.join(ROOT, ".github", "icon.png"), optimize=True)

    preview = Image.new("RGB", (1280, 640), bg)
    preview.paste(square(src, bg, 640), (320, 0))
    preview.save(os.path.join(ROOT, ".github", "social-preview.png"), optimize=True)

    # 64x64 uncompressed TGA with alpha, as the game expects
    square(src, bg, 64).convert("RGBA").save(
        os.path.join(ROOT, "VeinKeeper", "Icons", "logo.tga"), compression=None)
    print("wrote .github/icon.png, .github/social-preview.png, VeinKeeper/Icons/logo.tga")


if __name__ == "__main__":
    main()
