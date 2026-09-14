#!/usr/bin/env python3
"""Draw the converter icon from the palette and write a macOS .icns plus a Windows .ico."""

from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

from PIL import Image, ImageDraw

PAPER = (232, 230, 223, 255)
WELL = (243, 242, 236, 255)
INK = (26, 25, 22, 255)
RULE = (184, 182, 174, 255)
SEAL = (140, 42, 30, 255)

SIZES = (16, 32, 64, 128, 256, 512, 1024)


def paint(size: int) -> Image.Image:
    img = Image.new("RGBA", (size, size), PAPER)
    draw = ImageDraw.Draw(img)
    bezel = max(1, round(size * 0.09))
    well = (bezel, bezel, size - 1 - bezel, size - 1 - bezel)
    draw.rectangle(well, fill=WELL, outline=RULE, width=max(1, size // 256))

    # Card lines: three ink bars, readable down to 16px.
    left = bezel + max(2, size // 8)
    right = size // 2
    top = bezel + max(3, size // 6)
    gap = max(2, size // 10)
    thickness = max(1, size // 18)
    for index in range(3):
        y0 = top + index * (thickness + gap)
        y1 = y0 + thickness
        draw.rectangle((left, y0, right, y1), fill=INK)

    seal = max(5, size // 4)
    margin = bezel + max(2, size // 14)
    x1 = size - margin
    y1 = size - margin
    x0 = x1 - seal
    y0 = y1 - seal
    draw.rectangle((x0, y0, x1, y1), fill=SEAL)
    inset = max(1, seal // 6)
    draw.rectangle(
        (x0 + inset, y0 + inset, x1 - inset, y1 - inset),
        outline=WELL,
        width=max(1, size // 64),
    )
    return img


def main() -> int:
    root = Path(__file__).resolve().parent
    iconset = root / "Kindle-Anki-Import.iconset"
    if iconset.exists():
        shutil.rmtree(iconset)
    iconset.mkdir()
    master = paint(1024)
    master.save(root / "Kindle-Anki-Import-1024.png")
    files = {
        "icon_16x16.png": 16,
        "icon_16x16@2x.png": 32,
        "icon_32x32.png": 32,
        "icon_32x32@2x.png": 64,
        "icon_128x128.png": 128,
        "icon_128x128@2x.png": 256,
        "icon_256x256.png": 256,
        "icon_256x256@2x.png": 512,
        "icon_512x512.png": 512,
        "icon_512x512@2x.png": 1024,
    }
    for name, edge in files.items():
        master.resize((edge, edge), Image.Resampling.LANCZOS).save(iconset / name)
    icns = root / "Kindle-Anki-Import.icns"
    subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(icns)], check=True)
    print(icns)
    ico = root / "Kindle-Anki-Import.ico"
    master.resize((256, 256), Image.Resampling.LANCZOS).save(
        ico,
        sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
    )
    print(ico)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
