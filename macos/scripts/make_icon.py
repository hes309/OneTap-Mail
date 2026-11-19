#!/usr/bin/env python3
"""Generate the OneClickMail .icns icon with Pillow."""

from __future__ import annotations

import math
import shutil
import subprocess
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "Resources" / "AppIcon.icns"
SIZE = 1024


def lerp(a: tuple[int, int, int], b: tuple[int, int, int], t: float) -> tuple[int, int, int]:
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def gradient(size: int, top_left: tuple[int, int, int], bottom_right: tuple[int, int, int]) -> Image.Image:
    image = Image.new("RGB", (size, size))
    pixels = image.load()
    for y in range(size):
        for x in range(size):
            # diagonal gradient
            t = (x / size * 0.55) + (y / size * 0.45)
            pixels[x, y] = lerp(top_left, bottom_right, min(max(t, 0.0), 1.0))
    return image


def rounded_mask(size: int, inset: int, radius: int) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle(
        (inset, inset, size - inset, size - inset),
        radius=radius,
        fill=255,
    )
    return mask


def main() -> None:
    base = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))

    # Soft drop shadow
    shadow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    shadow_draw.rounded_rectangle((76, 88, 948, 960), radius=205, fill=(5, 15, 42, 95))
    shadow = shadow.filter(ImageFilter.GaussianBlur(30))
    base.alpha_composite(shadow)

    # Squircle background
    inset, radius = 62, 206
    mask = rounded_mask(SIZE, inset, radius)
    bg = gradient(SIZE, (58, 105, 246), (16, 31, 91)).convert("RGBA")
    bg.putalpha(mask)
    base.alpha_composite(bg)

    # Top gloss
    gloss = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    gd = ImageDraw.Draw(gloss)
    gd.ellipse((-170, -430, 900, 470), fill=(255, 255, 255, 28))
    gloss = gloss.filter(ImageFilter.GaussianBlur(24))
    gloss.putalpha(Image.composite(gloss.getchannel("A"), Image.new("L", (SIZE, SIZE), 0), mask))
    base.alpha_composite(gloss)

    draw = ImageDraw.Draw(base, "RGBA")

    # Envelope body
    env = (252, 380, 772, 708)
    draw.rounded_rectangle(env, radius=42, fill=(255, 255, 255, 255))
    # Subtle inner border
    draw.rounded_rectangle(env, radius=42, outline=(218, 228, 250, 255), width=3)

    # Envelope flap
    draw.polygon([(266, 402), (512, 585), (758, 402), (758, 438), (512, 620), (266, 438)], fill=(226, 236, 255, 255))
    # Bottom folds
    draw.line([(286, 680), (472, 548)], fill=(226, 236, 255, 255), width=10)
    draw.line([(738, 680), (552, 548)], fill=(226, 236, 255, 255), width=10)

    # Paper plane
    plane = [(476, 612), (806, 318), (642, 728), (588, 606)]
    draw.polygon(plane, fill=(255, 122, 72, 255))
    draw.polygon([(588, 606), (806, 318), (642, 728)], fill=(242, 92, 42, 255))
    draw.polygon([(476, 612), (588, 606), (642, 728)], fill=(255, 145, 100, 255))
    # Tail / fold highlight
    draw.polygon([(588, 606), (642, 728), (560, 666)], fill=(255, 166, 126, 255))
    # Motion lines
    for offset, length, alpha in ((0, 92, 150), (26, 60, 90)):
        x = 326 + offset
        y = 746 + offset // 2
        draw.rounded_rectangle((x, y, x + length, y + 13), radius=7, fill=(255, 255, 255, alpha))

    # Small white sparkle accents
    draw.ellipse((824, 596, 846, 618), fill=(255, 255, 255, 170))
    draw.ellipse((790, 650, 802, 662), fill=(255, 255, 255, 105))

    base = base.resize((SIZE, SIZE), Image.LANCZOS).convert("RGBA")

    with tempfile.TemporaryDirectory() as tmp:
        iconset = Path(tmp) / "AppIcon.iconset"
        iconset.mkdir()
        specs = [
            ("icon_16x16.png", 16),
            ("icon_16x16@2x.png", 32),
            ("icon_32x32.png", 32),
            ("icon_32x32@2x.png", 64),
            ("icon_128x128.png", 128),
            ("icon_128x128@2x.png", 256),
            ("icon_256x256.png", 256),
            ("icon_256x256@2x.png", 512),
            ("icon_512x512.png", 512),
            ("icon_512x512@2x.png", 1024),
        ]
        for name, size in specs:
            base.resize((size, size), Image.LANCZOS).save(iconset / name)

        OUT.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(OUT)], check=True)

    # Also keep a PNG preview for documentation.
    base.save(ROOT / "Resources" / "AppIcon-1024.png")
    print(f"Wrote {OUT}")


if __name__ == "__main__":
    main()
