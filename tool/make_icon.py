#!/usr/bin/env python3
"""Cut the Lu Ji launcher icon from a portrait of 陸機 Lu Ji, reproducibly.

    python3 tool/make_icon.py && dart pub global run flutter_launcher_icons   # needs Pillow + numpy

Every app in the suite frames its figure the same way (Eric, 2026-09-26: "I want
icons for all my apps to match that layout"), from Guiguzi's and Shen Buhai's
generators in xiaohe: the painting as the adaptive BACKGROUND layer, a
transparent foreground, and the face framed as Guiguzi's plate shows it through
a launcher mask -- nose on the centre line, eyes about 36% down the visible
window, the face filling the circle. The poet Lu Ji (261-303), whose calligraphy this app already carries (ASSET_ATTRIBUTION.md).

The visible window lies wholly inside the painting; any padding outside it is
only ever what a mask discards. The legacy square icon is the visible window.
"""
from __future__ import annotations

import pathlib

import numpy as np
from PIL import Image, ImageFilter

HERE = pathlib.Path(__file__).resolve().parent.parent
ASSETS = HERE / "assets/icon"
SOURCE = ASSETS / "source" / "luji-portrait.jpg"

SIZE = 1024

#: Measured off the source (3000 x 2259): eyes at y~470, the nose at x~2020-2030, the face from the near cheek at x~1945 to the ear at x~2145. Centred on the nose.
EYES_Y = 470
FACE_CX = 2025

#: The plate's side, in source pixels: the face fills the circle as the other
#: apps' faces do, checked by rendering them side by side through a round mask.
PLATE = 515

#: Where the eyes sit in the visible window, from the top. Guiguzi's sit at ~0.36.
EYES_IN_WINDOW = 0.36

#: An adaptive icon shows at most the central 72 of its 108 dp.
VISIBLE = 72 / 108


def plate() -> tuple[Image.Image, Image.Image]:
    src = np.asarray(Image.open(SOURCE).convert("RGB"))
    h, w, _ = src.shape
    win = PLATE * VISIBLE
    margin = (PLATE - win) / 2
    left = round(FACE_CX - PLATE / 2)
    top = round(EYES_Y - margin - EYES_IN_WINDOW * win)
    # The whole visible window must be painting, never padding.
    wl, wt = left + margin, top + margin
    assert 0 <= wl and wl + win <= w and 0 <= wt and wt + win <= h, (wl, wt, win, w, h)

    pad_l, pad_t = max(0, -left), max(0, -top)
    pad_r, pad_b = max(0, left + PLATE - w), max(0, top + PLATE - h)
    padded = np.pad(src, ((pad_t, pad_b), (pad_l, pad_r), (0, 0)), mode="edge")
    x0, y0 = left + pad_l, top + pad_t
    full = Image.fromarray(padded[y0:y0 + PLATE, x0:x0 + PLATE])

    # Scaled, so a light unsharp mask restores the brush edges LANCZOS
    # softens. Nothing else is changed: the colour and contrast are the painting's.
    def up(img: Image.Image) -> Image.Image:
        big = img.resize((SIZE, SIZE), Image.LANCZOS)
        return big.filter(ImageFilter.UnsharpMask(radius=2, percent=60, threshold=2))

    window = full.crop((round(margin), round(margin), round(margin + win), round(margin + win)))
    return up(full), up(window)


def main() -> int:
    background, legacy = plate()
    background.save(ASSETS / "app_icon_background.png")
    legacy.save(ASSETS / "app_icon.png")
    Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0)).save(ASSETS / "app_icon_foreground.png")
    print(f"wrote app_icon.png (visible window), app_icon_background.png (padded plate) "
          f"and a transparent foreground from {SOURCE.name}")
    print("now: dart run flutter_launcher_icons")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
