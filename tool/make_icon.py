#!/usr/bin/env python3
"""Generate the ScobySense app icon procedurally.

A dark glass rounded square with a soft teal→cyan gradient wash, a subtle
inner highlight, and a stylised "S" (double-curve motif, evoking a SCOBY
spiral + a jar silhouette) on top. Produces the five mipmap PNGs the
Android launcher expects, plus a splash variant.
"""

from __future__ import annotations
import math
import os
import sys
from PIL import Image, ImageDraw, ImageFilter


# Theme colours (matches lib/theme.dart glass palette).
BG0 = (4, 7, 10, 255)         # near-black background
BG1 = (14, 22, 32, 255)       # dark slate
ACCENT = (46, 212, 191, 255)  # teal
ACCENT2 = (34, 211, 238, 255) # cyan
GOLD = (240, 180, 110, 255)   # warm scoby accent


def rounded_rect_mask(size: int, radius: float) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(mask)
    d.rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=255)
    return mask


def lerp(a, b, t):
    return a + (b - a) * t


def lerp_colour(c0, c1, t):
    return tuple(int(round(lerp(c0[i], c1[i], t))) for i in range(4))


def diagonal_gradient(size: int, c0, c1) -> Image.Image:
    img = Image.new("RGBA", (size, size), c0)
    px = img.load()
    inv = 1.0 / (2.0 * (size - 1))
    for y in range(size):
        for x in range(size):
            t = (x + y) * inv
            px[x, y] = lerp_colour(c0, c1, t)
    return img


def radial_glow(size: int, cx: float, cy: float, radius: float, colour) -> Image.Image:
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    px = img.load()
    r2 = radius * radius
    for y in range(size):
        for x in range(size):
            dx = x - cx
            dy = y - cy
            d2 = dx * dx + dy * dy
            if d2 >= r2:
                continue
            t = 1.0 - math.sqrt(d2) / radius
            a = int(round(colour[3] * (t ** 2)))
            if a <= 0:
                continue
            px[x, y] = (colour[0], colour[1], colour[2], a)
    return img


def draw_s_motif(size: int) -> Image.Image:
    """Stylised "S" / spiral motif painted onto a transparent canvas."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cx, cy = size / 2, size / 2
    r_outer = size * 0.30
    r_inner = size * 0.17
    thick = max(2, int(size * 0.07))

    # Top curve (teal) — ~180° arc on the top-left side.
    bbox_top = [cx - r_outer, cy - r_outer, cx + r_outer, cy + r_outer]
    d.arc(bbox_top, start=200, end=20, fill=ACCENT, width=thick)

    # Bottom curve (gold) — ~180° arc mirrored.
    bbox_bot = [cx - r_inner * 1.6, cy - r_inner * 1.6,
                cx + r_inner * 1.6, cy + r_inner * 1.6]
    d.arc(bbox_bot, start=20, end=200, fill=GOLD, width=max(2, thick - 2))

    # Centre dot — the "scoby" eye.
    rd = max(2, int(size * 0.045))
    d.ellipse([cx - rd, cy - rd, cx + rd, cy + rd], fill=ACCENT2)

    return img


def compose_icon(size: int) -> Image.Image:
    base = diagonal_gradient(size, BG0, BG1)

    # Inner glow on the top-left.
    glow = radial_glow(size, size * 0.3, size * 0.25, size * 0.9,
                       (ACCENT[0], ACCENT[1], ACCENT[2], 90))
    base = Image.alpha_composite(base, glow)

    # Second cyan accent on the bottom-right for depth.
    glow2 = radial_glow(size, size * 0.75, size * 0.8, size * 0.7,
                        (ACCENT2[0], ACCENT2[1], ACCENT2[2], 60))
    base = Image.alpha_composite(base, glow2)

    # Motif.
    motif = draw_s_motif(size)
    # Soft shadow underneath the motif.
    shadow = motif.filter(ImageFilter.GaussianBlur(size * 0.015))
    base = Image.alpha_composite(base, shadow)
    base = Image.alpha_composite(base, motif)

    # Border highlight (1px bright, inside the rounded rect).
    outline = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    od = ImageDraw.Draw(outline)
    od.rounded_rectangle(
        [1, 1, size - 2, size - 2],
        radius=size * 0.22,
        outline=(255, 255, 255, 35),
        width=max(1, size // 128),
    )
    base = Image.alpha_composite(base, outline)

    # Apply rounded-rect mask so the whole thing is a squircle.
    mask = rounded_rect_mask(size, size * 0.22)
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.paste(base, (0, 0), mask)
    return out


def make_splash(width: int, height: int, icon_pct: float = 0.35) -> Image.Image:
    bg = Image.new("RGBA", (width, height), BG0)
    icon_size = int(min(width, height) * icon_pct)
    icon = compose_icon(icon_size)
    x = (width - icon_size) // 2
    y = (height - icon_size) // 2
    bg.alpha_composite(icon, (x, y))
    return bg


DENSITIES = {
    "mdpi": 48,
    "hdpi": 72,
    "xhdpi": 96,
    "xxhdpi": 144,
    "xxxhdpi": 192,
}


def main() -> int:
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    res_dir = os.path.join(root, "android", "app", "src", "main", "res")

    # Render once at the biggest size then downsample for crispness.
    master = compose_icon(512)
    master_path = os.path.join(root, "assets", "icon_master.png")
    os.makedirs(os.path.dirname(master_path), exist_ok=True)
    master.save(master_path)
    print(f"wrote {master_path}")

    for density, size in DENSITIES.items():
        out_dir = os.path.join(res_dir, f"mipmap-{density}")
        os.makedirs(out_dir, exist_ok=True)
        im = master.resize((size, size), Image.LANCZOS)
        p = os.path.join(out_dir, "ic_launcher.png")
        im.save(p)
        print(f"wrote {p} ({size}x{size})")

    # Splash: a 1024x1024 that the launch_background drawable can centre.
    splash = make_splash(1024, 1024, 0.42)
    splash_path = os.path.join(root, "assets", "splash.png")
    splash.save(splash_path)
    print(f"wrote {splash_path}")

    # Also drop a drawable for the launch background to reference.
    for density, size in [("mdpi", 160), ("hdpi", 240), ("xhdpi", 320),
                          ("xxhdpi", 480), ("xxxhdpi", 640)]:
        d = os.path.join(res_dir, f"drawable-{density}")
        os.makedirs(d, exist_ok=True)
        im = compose_icon(size)
        p = os.path.join(d, "ic_splash.png")
        im.save(p)
        print(f"wrote {p} ({size}x{size})")

    return 0


if __name__ == "__main__":
    sys.exit(main())
