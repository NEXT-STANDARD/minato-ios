#!/usr/bin/env python3
"""MINATO "Harbor Beacon" app icon generator (pure Pillow, no numpy).

A beacon (灯台) glowing over a calm night harbor, broadcasting concentric
signal rings (mesh / offline reach) — "圏外でもつながる、安全な港".
Palette derives from MinatoTheme (navy night / teal sea / amber beacon).
Rendered supersampled then downscaled for crisp anti-aliasing.
"""
import math
from PIL import Image, ImageDraw

SS = 2
OUT = 1024
S = OUT * SS

NAVY_TOP = (15, 22, 43)
NAVY_BOT = (7, 10, 20)
AMBER    = (224, 146, 46)
AMBER_HOT= (252, 244, 228)
TEAL     = (41, 140, 153)
TEAL_DK  = (18, 74, 86)
TEAL_LT  = (86, 178, 188)

CX, CY = 0.5, 0.40   # beacon centre (normalised)


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def gradient_bg():
    g = Image.new("RGB", (1, S))
    px = g.load()
    for y in range(S):
        px[0, y] = lerp(NAVY_TOP, NAVY_BOT, y / (S - 1))
    return g.resize((S, S))


def radial_mask(cx, cy, r_frac, power, peak, res=420):
    """Low-res L mask of a radial falloff, scaled up smoothly."""
    m = Image.new("L", (res, res), 0)
    px = m.load()
    ccx, ccy = cx * res, cy * res
    R = r_frac * res
    for y in range(res):
        for x in range(res):
            d = math.hypot(x - ccx, y - ccy)
            v = 1.0 - d / R
            px[x, y] = int(max(0.0, v) ** power * peak) if v > 0 else 0
    return m.resize((S, S), Image.LANCZOS)


def composite_color(base, color, mask):
    solid = Image.new("RGB", (S, S), color)
    return Image.composite(solid, base, mask)


def wave_polygon(draw, waterline, amp, freq, phase, color, alpha):
    pts = []
    n = 260
    for i in range(n + 1):
        x = S * i / n
        y = waterline + amp * math.sin(2 * math.pi * freq * (i / n) + phase)
        pts.append((x, y))
    pts += [(S, S), (0, S)]
    draw.polygon(pts, fill=color + (alpha,))


def draw_sea(img):
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    wave_polygon(d, 0.66 * S, 0.018 * S, 2.0, 0.4, TEAL_DK, 235)
    wave_polygon(d, 0.73 * S, 0.022 * S, 1.6, 2.1, lerp(TEAL_DK, TEAL, 0.5), 240)
    wave_polygon(d, 0.80 * S, 0.026 * S, 1.3, 3.7, TEAL, 250)
    for i in range(7):
        x = (0.16 + 0.11 * i) * S
        y = 0.80 * S + 0.026 * S * math.sin(2 * math.pi * 1.3 * (x / S) + 3.7) - 0.004 * S
        w = 0.020 * S
        d.line([(x - w, y), (x + w, y)], fill=TEAL_LT + (150,), width=max(1, int(0.004 * S)))
    img.alpha_composite(layer)


def draw_reflection(img):
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    cx = CX * S
    segs = 16
    for i in range(segs):
        t = i / (segs - 1)
        y = (0.68 + t * 0.27) * S
        half = (0.055 - 0.030 * t) * S * (0.7 + 0.3 * math.sin(i * 1.7))
        a = int(150 * (1 - t) ** 1.3)
        if a <= 0 or half <= 0:
            continue
        d.line([(cx - half, y), (cx + half, y)], fill=AMBER + (a,), width=max(1, int(0.006 * S)))
    img.alpha_composite(layer)


def draw_rings(img):
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    cx, cy = CX * S, CY * S
    w = max(2, int(0.0115 * S))
    for r_frac, a in [(0.165, 175), (0.235, 110), (0.305, 62)]:
        r = r_frac * S
        d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=AMBER + (a,), width=w)
    img.alpha_composite(layer)


def draw_beacon(img):
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    cx, cy = CX * S, CY * S
    r = 0.060 * S
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=AMBER + (255,))
    r2 = 0.032 * S
    d.ellipse([cx - r2, cy - r2, cx + r2, cy + r2], fill=AMBER_HOT + (255,))
    img.alpha_composite(layer)


def render(debug=False):
    base = gradient_bg()
    base = composite_color(base, AMBER, radial_mask(CX, CY, 0.42, 2.4, 216))   # soft glow (~0.85)
    base = composite_color(base, AMBER_HOT, radial_mask(CX, CY, 0.13, 1.8, 255))  # hot bloom
    img = base.convert("RGBA")
    draw_sea(img)
    draw_reflection(img)
    draw_rings(img)
    draw_beacon(img)
    if debug:
        layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        d = ImageDraw.Draw(layer)
        m = 0.17 * S
        d.polygon([(0, 0), (m, 0), (0, m)], fill=TEAL + (255,))
        img.alpha_composite(layer)
    return img.convert("RGB").resize((OUT, OUT), Image.LANCZOS)


if __name__ == "__main__":
    render(False).save("/tmp/minato_icon_release_1024.png")
    render(True).save("/tmp/minato_icon_debug_1024.png")
    # a quick side-by-side contact sheet at home-screen scale for preview
    rel = Image.open("/tmp/minato_icon_release_1024.png")
    sheet = Image.new("RGB", (1024, 1224), (28, 28, 30))
    sheet.paste(rel.resize((1024, 1024), Image.LANCZOS), (0, 0))
    for i, sz in enumerate([180, 120, 80, 60]):
        thumb = rel.resize((sz, sz), Image.LANCZOS)
        sheet.paste(thumb, (40 + i * 230, 1060))
    sheet.save("/tmp/minato_icon_preview.png")
    print("ok")
