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

BORDERED: frame() below shrinks the portrait into an ink-ringed medallion on warm paper,
so the foreground layer is the ring, not the transparent plate described above. A launcher
mask cuts the outer edge of an adaptive icon, and the ring has to sit inside what is left.
"""
from __future__ import annotations

import pathlib

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

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


#: The portrait sits as a medallion inside an ink ring, on the suite's warm paper. A launcher
#: mask cuts the 108 dp canvas to its central 72 dp, so the app cannot draw on the true
#: outer edge; a ring inside that safe area is the border. Sizes are in dp: the disk is
#: 64, the ring's outer edge 68 and its stroke 2, so the ring's inner edge meets the disk.
#: The ring lives in the foreground layer, which ic_launcher.xml insets 16% (73.44 dp).
PAPER_TONE = (0xE9, 0xD8, 0xB4, 255)
BORDER_INK = (0x2B, 0x22, 0x1C, 255)
DISK_DP, RING_DP, STROKE_DP = 64, 68, 2
CANVAS_DP, WINDOW_DP, FOREGROUND_DP, SUPER, CORNER = 108, 72, 108 * 0.68, 4, 0.18


def _circle_mask(px: int) -> Image.Image:
    big = Image.new("L", (px * SUPER, px * SUPER), 0)
    ImageDraw.Draw(big).ellipse([0, 0, px * SUPER - 1, px * SUPER - 1], fill=255)
    return big.resize((px, px), Image.LANCZOS)


def _ring(span_dp: float) -> Image.Image:
    s = SIZE * SUPER
    outer, stroke = round(s * RING_DP / span_dp), round(s * STROKE_DP / span_dp)
    lo = (s - outer) // 2
    ring = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    ImageDraw.Draw(ring).ellipse([lo, lo, lo + outer, lo + outer], outline=BORDER_INK, width=stroke)
    return ring.resize((SIZE, SIZE), Image.LANCZOS)


def _medallion(window: Image.Image, span_dp: float) -> Image.Image:
    base = Image.new("RGBA", (SIZE, SIZE), PAPER_TONE)
    d = round(SIZE * DISK_DP / span_dp)
    base.paste(window.resize((d, d), Image.LANCZOS), ((SIZE - d) // 2,) * 2, _circle_mask(d))
    return base


def frame(assets: pathlib.Path) -> None:
    window = Image.open(assets / "app_icon.png").convert("RGB")
    _medallion(window, CANVAS_DP).save(assets / "app_icon_background.png")
    _ring(FOREGROUND_DP).save(assets / "app_icon_foreground.png")
    legacy = _medallion(window, WINDOW_DP)
    legacy.alpha_composite(_ring(WINDOW_DP))
    big = Image.new("L", (SIZE * SUPER,) * 2, 0)
    ImageDraw.Draw(big).rounded_rectangle([0, 0, SIZE * SUPER - 1, SIZE * SUPER - 1],
                                          radius=round(SIZE * SUPER * CORNER), fill=255)
    legacy.putalpha(big.resize((SIZE, SIZE), Image.LANCZOS))
    legacy.save(assets / "app_icon.png")


def main() -> int:
    background, legacy = plate()
    background.save(ASSETS / "app_icon_background.png")
    legacy.save(ASSETS / "app_icon.png")
    Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0)).save(ASSETS / "app_icon_foreground.png")
    frame(ASSETS)
    print(f"wrote app_icon.png (visible window), app_icon_background.png (padded plate) "
          f"and the border ring as the foreground from {SOURCE.name}")
    print("now: dart run flutter_launcher_icons")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
