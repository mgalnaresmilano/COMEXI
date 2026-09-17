#!/usr/bin/env python3
"""Genera las imagenes de catalogo de los productos Comexi.

Produce un PNG por SKU en unpackaged/post_comexi/staticresources/COMEXI_ProductImages/,
que se despliega como static resource zip y se referencia desde Product2.DisplayUrl
con la ruta /resource/COMEXI_ProductImages/<SKU>.png (ver scripts/apex/comexi/02_products.apex).

Uso:
    python3 scripts/build_comexi_product_images.py [--out DIR] [--size 512]
"""

from __future__ import annotations

import argparse
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

REPO_ROOT = Path(__file__).resolve().parent.parent
LOGO_PATH = REPO_ROOT / "scripts" / "assets" / "comexi" / "Comexi-logo-web.png"
DEFAULT_OUT = (
    REPO_ROOT / "unpackaged" / "post_comexi" / "staticresources" / "COMEXI_ProductImages"
)

# Recortes del logo original (1180x259): el simbolo rojo y el wordmark antracita.
LOGO_SYMBOL_BOX = (30, 70, 392, 202)
LOGO_WORDMARK_BOX = (400, 70, 1136, 202)

# Paleta de marca Comexi, muestreada de Comexi-logo-web.png.
COMEXI_RED = (237, 24, 72)
COMEXI_SLATE = (69, 85, 96)

WHITE = (255, 255, 255)

# Acento por familia de catalogo: rojo para retrofit, antracita para servicio y gastos.
FAMILIES = {
    "FAM_T": (COMEXI_RED, "RETROFIT \u00b7 TALL"),
    "FAM_L": ((176, 17, 54), "RETROFIT \u00b7 LAMINACI\u00d3N"),
    "FAM_C": ((122, 20, 46), "RETROFIT \u00b7 CTEC"),
    "SERVICE": (COMEXI_SLATE, "SERVICIO"),
    "GASTOS": ((108, 123, 136), "GASTOS"),
}

# SKU -> (categoria, glifo). El orden define el orden de generacion.
PRODUCTS = [
    ("T100", "FAM_T", "pc_update"),
    ("T100-TEMP", "FAM_T", "thermometer"),
    ("T100-W11", "FAM_T", "windows"),
    ("T100-CPU-SIM", "FAM_T", "chip"),
    ("T100-CU-SIN", "FAM_T", "drive"),
    ("T100-HMI", "FAM_T", "hmi"),
    ("T100-SCREEN", "FAM_T", "monitor"),
    ("T100-CHECKLIST", "FAM_T", "checklist"),
    ("T040", "FAM_T", "network"),
    ("T060", "FAM_T", "gauge"),
    ("T114", "FAM_T", "snowflake"),
    ("T120", "FAM_T", "tape_roll"),
    ("T130", "FAM_T", "roller"),
    ("T150", "FAM_T", "web_guide"),
    ("T360", "FAM_T", "splice_table"),
    ("L210", "FAM_L", "water_temp"),
    ("L220", "FAM_L", "corona"),
    ("L230", "FAM_L", "hologram"),
    ("L240", "FAM_L", "mixer"),
    ("L250", "FAM_L", "swap"),
    ("C110", "FAM_C", "plate"),
    ("C120", "FAM_C", "microscope"),
    ("C130", "FAM_C", "chart_up"),
    ("C140", "FAM_C", "gear"),
    ("C150", "FAM_C", "laminate"),
    ("SRV-MEC", "SERVICE", "wrench"),
    ("SRV-ELE", "SERVICE", "bolt"),
    ("SRV-PME", "SERVICE", "gear_play"),
    ("SRV-PMR", "SERVICE", "remote"),
    ("SRV-PI", "SERVICE", "flask"),
    ("EXP-FLIGHT", "GASTOS", "plane"),
    ("EXP-HOTEL", "GASTOS", "bed"),
    ("EXP-CAR", "GASTOS", "car"),
    ("EXP-TAXI", "GASTOS", "taxi"),
    ("EXP-MEAL", "GASTOS", "meal"),
    ("EXP-ADMIN", "GASTOS", "doc"),
]

FONT_CANDIDATES = [
    "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
    "/Library/Fonts/Arial Bold.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
]

# Supersampling: PIL no antialiasa lineas, asi que dibujamos a 4x y reducimos.
SS = 4


def load_font(size: int) -> ImageFont.FreeTypeFont:
    for candidate in FONT_CANDIDATES:
        if Path(candidate).exists():
            return ImageFont.truetype(candidate, size)
    return ImageFont.load_default(size)


def blend(color: tuple[int, int, int], other: tuple[int, int, int], ratio: float):
    """Mezcla color sobre other; ratio 0 = other, 1 = color."""
    return tuple(round(c * ratio + o * (1 - ratio)) for c, o in zip(color, other))


class Pen:
    """Envoltorio de ImageDraw que escala coordenadas logicas al lienzo supersampleado."""

    def __init__(self, draw: ImageDraw.ImageDraw):
        self.d = draw

    def _p(self, *vals):
        return [v * SS for v in vals]

    def line(self, x1, y1, x2, y2, fill, width):
        self.d.line(self._p(x1, y1, x2, y2), fill=fill, width=round(width * SS), joint="curve")

    def path(self, points, fill, width, closed=False):
        pts = [(x * SS, y * SS) for x, y in points]
        if closed:
            pts.append(pts[0])
        self.d.line(pts, fill=fill, width=round(width * SS), joint="curve")
        # Redondea los vertices para que las uniones no queden mordidas.
        r = width * SS / 2
        for x, y in pts:
            self.d.ellipse([x - r, y - r, x + r, y + r], fill=fill)

    def polygon(self, points, fill=None, outline=None, width=1):
        pts = [(x * SS, y * SS) for x, y in points]
        if fill:
            self.d.polygon(pts, fill=fill)
        if outline:
            self.path(points, outline, width, closed=True)

    def rect(self, box, fill=None, outline=None, width=1):
        self.d.rectangle(self._p(*box), fill=fill, outline=outline, width=round(width * SS))

    def rrect(self, box, radius, fill=None, outline=None, width=1):
        self.d.rounded_rectangle(
            self._p(*box),
            radius=radius * SS,
            fill=fill,
            outline=outline,
            width=round(width * SS),
        )

    def ellipse(self, box, fill=None, outline=None, width=1):
        self.d.ellipse(self._p(*box), fill=fill, outline=outline, width=round(width * SS))

    def dot(self, cx, cy, r, fill):
        self.d.ellipse(self._p(cx - r, cy - r, cx + r, cy + r), fill=fill)

    def arc(self, box, start, end, fill, width):
        self.d.arc(self._p(*box), start=start, end=end, fill=fill, width=round(width * SS))

    def text(self, xy, text, font, fill, anchor="la", spacing=0.0):
        if spacing <= 0:
            self.d.text([xy[0] * SS, xy[1] * SS], text, font=font, fill=fill, anchor=anchor)
            return
        # Tracking manual: PIL no soporta letter-spacing.
        gap = spacing * SS
        widths = [self.d.textlength(ch, font=font) for ch in text]
        total = sum(widths) + gap * (len(text) - 1)
        x = xy[0] * SS
        if anchor[0] == "m":
            x -= total / 2
        elif anchor[0] == "r":
            x -= total
        for ch, w in zip(text, widths):
            self.d.text([x, xy[1] * SS], ch, font=font, fill=fill, anchor="l" + anchor[1])
            x += w + gap

    def arrow(self, x1, y1, x2, y2, fill, width, head):
        ang = math.atan2(y2 - y1, x2 - x1)
        bx, by = x2 - math.cos(ang) * head * 0.9, y2 - math.sin(ang) * head * 0.9
        self.line(x1, y1, bx, by, fill, width)
        left = (bx + math.cos(ang + math.pi / 2) * head * 0.6, by + math.sin(ang + math.pi / 2) * head * 0.6)
        right = (bx - math.cos(ang + math.pi / 2) * head * 0.6, by - math.sin(ang + math.pi / 2) * head * 0.6)
        self.polygon([(x2, y2), left, right], fill=fill)


# --------------------------------------------------------------------------- #
# Glifos. Cada uno dibuja dentro de un cuadrado de lado 2*s centrado en cx,cy. #
# --------------------------------------------------------------------------- #


def _monitor_body(p: Pen, cx, cy, s, c, w):
    p.rrect((cx - s, cy - 0.85 * s, cx + s, cy + 0.35 * s), 0.14 * s, outline=c, width=w)
    p.line(cx, cy + 0.35 * s, cx, cy + 0.72 * s, c, w)
    p.line(cx - 0.45 * s, cy + 0.72 * s, cx + 0.45 * s, cy + 0.72 * s, c, w)


def g_monitor(p, cx, cy, s, c, w):
    _monitor_body(p, cx, cy, s, c, w)
    p.line(cx - 0.6 * s, cy - 0.5 * s, cx + 0.6 * s, cy - 0.5 * s, c, w * 0.7)
    p.line(cx - 0.6 * s, cy - 0.2 * s, cx + 0.25 * s, cy - 0.2 * s, c, w * 0.7)


def g_pc_update(p, cx, cy, s, c, w):
    _monitor_body(p, cx, cy, s, c, w)
    p.arc((cx - 0.42 * s, cy - 0.68 * s, cx + 0.42 * s, cy + 0.16 * s), 30, 300, c, w)
    p.polygon(
        [
            (cx + 0.42 * s, cy - 0.36 * s),
            (cx + 0.14 * s, cy - 0.44 * s),
            (cx + 0.36 * s, cy - 0.08 * s),
        ],
        fill=c,
    )


def g_windows(p, cx, cy, s, c, w):
    side, gap = 0.72 * s, 0.11 * s
    for dx in (-1, 1):
        for dy in (-1, 1):
            x0 = cx + (gap / 2 if dx > 0 else -gap / 2 - side)
            y0 = cy + (gap / 2 if dy > 0 else -gap / 2 - side)
            p.rrect((x0, y0, x0 + side, y0 + side), 0.1 * s, outline=c, width=w)


def g_chip(p, cx, cy, s, c, w):
    b = 0.66 * s
    p.rrect((cx - b, cy - b, cx + b, cy + b), 0.12 * s, outline=c, width=w)
    p.rrect((cx - 0.3 * s, cy - 0.3 * s, cx + 0.3 * s, cy + 0.3 * s), 0.06 * s, fill=c)
    for k in (-0.36, 0, 0.36):
        off = k * s
        p.line(cx + off, cy - b, cx + off, cy - b - 0.28 * s, c, w)
        p.line(cx + off, cy + b, cx + off, cy + b + 0.28 * s, c, w)
        p.line(cx - b, cy + off, cx - b - 0.28 * s, cy + off, c, w)
        p.line(cx + b, cy + off, cx + b + 0.28 * s, cy + off, c, w)


def g_drive(p, cx, cy, s, c, w):
    p.rrect((cx - 0.58 * s, cy - 0.92 * s, cx + 0.58 * s, cy + 0.92 * s), 0.12 * s, outline=c, width=w)
    p.ellipse((cx - 0.3 * s, cy - 0.62 * s, cx + 0.3 * s, cy - 0.02 * s), outline=c, width=w)
    p.dot(cx, cy - 0.32 * s, 0.08 * s, c)
    for k in (0.28, 0.52, 0.76):
        p.line(cx - 0.32 * s, cy + k * s, cx + 0.32 * s, cy + k * s, c, w * 0.7)


def g_hmi(p, cx, cy, s, c, w):
    p.rrect((cx - s, cy - 0.62 * s, cx + s, cy + 0.62 * s), 0.14 * s, outline=c, width=w)
    p.rrect((cx - 0.78 * s, cy - 0.4 * s, cx + 0.1 * s, cy + 0.18 * s), 0.06 * s, fill=c)
    for k in (-0.18, 0.18):
        p.ellipse(
            (cx + 0.42 * s, cy + k * s - 0.14 * s, cx + 0.7 * s, cy + k * s + 0.14 * s),
            outline=c,
            width=w * 0.8,
        )
    p.line(cx - 0.7 * s, cy + 0.4 * s, cx + 0.1 * s, cy + 0.4 * s, c, w * 0.7)


def g_checklist(p, cx, cy, s, c, w):
    p.rrect((cx - 0.74 * s, cy - 0.92 * s, cx + 0.74 * s, cy + 0.92 * s), 0.12 * s, outline=c, width=w)
    for k in (-0.48, 0.0, 0.48):
        y = cy + k * s
        p.path(
            [(cx - 0.5 * s, y), (cx - 0.34 * s, y + 0.16 * s), (cx - 0.06 * s, y - 0.18 * s)],
            c,
            w * 0.85,
        )
        p.line(cx + 0.12 * s, y, cx + 0.5 * s, y, c, w * 0.7)


def _thermometer(p, cx, cy, s, c, w):
    p.rrect((cx - 0.24 * s, cy - 0.92 * s, cx + 0.24 * s, cy + 0.34 * s), 0.24 * s, outline=c, width=w)
    p.ellipse((cx - 0.4 * s, cy + 0.16 * s, cx + 0.4 * s, cy + 0.96 * s), fill=c)
    p.rrect((cx - 0.09 * s, cy - 0.2 * s, cx + 0.09 * s, cy + 0.3 * s), 0.09 * s, fill=c)


def g_thermometer(p, cx, cy, s, c, w):
    _thermometer(p, cx, cy, s, c, w)
    for k in (-0.62, -0.34, -0.06):
        p.line(cx + 0.34 * s, cy + k * s, cx + 0.66 * s, cy + k * s, c, w * 0.7)


def g_water_temp(p, cx, cy, s, c, w):
    _thermometer(p, cx - 0.3 * s, cy, s * 0.94, c, w)
    dx, dy = cx + 0.6 * s, cy + 0.02 * s
    p.polygon(
        [(dx, dy - 0.62 * s), (dx - 0.3 * s, dy + 0.06 * s), (dx + 0.3 * s, dy + 0.06 * s)],
        fill=c,
    )
    p.dot(dx, dy + 0.06 * s, 0.3 * s, c)


def g_network(p, cx, cy, s, c, w):
    p.dot(cx, cy, 0.24 * s, c)
    for ang in (270, 30, 150):
        rad = math.radians(ang)
        nx, ny = cx + math.cos(rad) * 0.72 * s, cy + math.sin(rad) * 0.72 * s
        p.line(cx, cy, nx, ny, c, w * 0.8)
        p.ellipse((nx - 0.24 * s, ny - 0.24 * s, nx + 0.24 * s, ny + 0.24 * s), outline=c, width=w)


def g_gauge(p, cx, cy, s, c, w):
    p.arc((cx - 0.95 * s, cy - 0.65 * s, cx + 0.95 * s, cy + 1.25 * s), 180, 360, c, w)
    for ang in (200, 240, 300, 340):
        rad = math.radians(ang)
        p.line(
            cx + math.cos(rad) * 0.72 * s,
            cy + 0.3 * s + math.sin(rad) * 0.72 * s,
            cx + math.cos(rad) * 0.92 * s,
            cy + 0.3 * s + math.sin(rad) * 0.92 * s,
            c,
            w * 0.7,
        )
    p.line(cx, cy + 0.3 * s, cx + 0.52 * s, cy - 0.32 * s, c, w)
    p.dot(cx, cy + 0.3 * s, 0.14 * s, c)


def g_snowflake(p, cx, cy, s, c, w):
    for ang in range(0, 360, 60):
        rad = math.radians(ang)
        ex, ey = cx + math.cos(rad) * 0.92 * s, cy + math.sin(rad) * 0.92 * s
        p.line(cx, cy, ex, ey, c, w)
        bx, by = cx + math.cos(rad) * 0.55 * s, cy + math.sin(rad) * 0.55 * s
        for side in (-1, 1):
            brad = rad + side * math.radians(55)
            p.line(bx, by, bx + math.cos(brad) * 0.3 * s, by + math.sin(brad) * 0.3 * s, c, w * 0.8)


def g_tape_roll(p, cx, cy, s, c, w):
    p.ellipse((cx - 0.72 * s, cy - 0.82 * s, cx + 0.72 * s, cy + 0.62 * s), outline=c, width=w)
    p.dot(cx, cy - 0.1 * s, 0.24 * s, c)
    p.path(
        [(cx + 0.7 * s, cy - 0.24 * s), (cx + 0.92 * s, cy + 0.5 * s), (cx + 0.2 * s, cy + 0.88 * s)],
        c,
        w * 0.85,
    )


def g_roller(p, cx, cy, s, c, w):
    p.rrect((cx - 0.9 * s, cy + 0.06 * s, cx + 0.9 * s, cy + 0.7 * s), 0.32 * s, outline=c, width=w)
    for k in (-0.56, 0.56):
        p.line(cx + k * s, cy + 0.12 * s, cx + k * s, cy + 0.64 * s, c, w * 0.7)
    p.arc((cx - 0.46 * s, cy - 0.88 * s, cx + 0.46 * s, cy - 0.2 * s), 190, 345, c, w)
    p.polygon(
        [
            (cx + 0.58 * s, cy - 0.3 * s),
            (cx + 0.24 * s, cy - 0.46 * s),
            (cx + 0.46 * s, cy - 0.72 * s),
        ],
        fill=c,
    )


def g_web_guide(p, cx, cy, s, c, w):
    for k in (-0.3, 0.34):
        p.line(cx - 0.95 * s, cy + k * s, cx + 0.95 * s, cy + k * s, c, w)
    p.arrow(cx - 0.1 * s, cy + 0.78 * s, cx - 0.78 * s, cy + 0.78 * s, c, w * 0.8, 0.24 * s)
    p.arrow(cx + 0.1 * s, cy + 0.78 * s, cx + 0.78 * s, cy + 0.78 * s, c, w * 0.8, 0.24 * s)
    p.line(cx - 0.5 * s, cy - 0.78 * s, cx + 0.5 * s, cy - 0.78 * s, c, w * 0.7)
    p.line(cx - 0.5 * s, cy - 0.78 * s, cx - 0.5 * s, cy - 0.3 * s, c, w * 0.7)
    p.line(cx + 0.5 * s, cy - 0.78 * s, cx + 0.5 * s, cy - 0.3 * s, c, w * 0.7)


def g_splice_table(p, cx, cy, s, c, w):
    p.line(cx - 0.95 * s, cy + 0.1 * s, cx + 0.95 * s, cy + 0.1 * s, c, w * 1.3)
    for k in (-0.7, 0.7):
        p.line(cx + k * s, cy + 0.1 * s, cx + k * s, cy + 0.86 * s, c, w)
    p.line(cx - 0.72 * s, cy - 0.5 * s, cx + 0.2 * s, cy - 0.5 * s, c, w)
    p.line(cx - 0.2 * s, cy - 0.24 * s, cx + 0.72 * s, cy - 0.24 * s, c, w)
    p.line(cx - 0.2 * s, cy - 0.62 * s, cx + 0.2 * s, cy - 0.12 * s, c, w * 0.8)


def g_corona(p, cx, cy, s, c, w):
    p.rrect((cx - 0.82 * s, cy - 0.9 * s, cx + 0.82 * s, cy - 0.56 * s), 0.1 * s, fill=c)
    p.line(cx - 0.92 * s, cy + 0.74 * s, cx + 0.92 * s, cy + 0.74 * s, c, w * 1.2)
    for k in (-0.52, 0.0, 0.52):
        x = cx + k * s
        p.path(
            [
                (x, cy - 0.5 * s),
                (x - 0.16 * s, cy - 0.1 * s),
                (x + 0.14 * s, cy + 0.16 * s),
                (x - 0.04 * s, cy + 0.66 * s),
            ],
            c,
            w * 0.8,
        )


def g_hologram(p, cx, cy, s, c, w):
    p.polygon(
        [(cx - 0.34 * s, cy + 0.62 * s), (cx + 0.42 * s, cy + 0.62 * s), (cx + 0.04 * s, cy - 0.58 * s)],
        outline=c,
        width=w,
    )
    p.line(cx - 0.95 * s, cy - 0.12 * s, cx - 0.16 * s, cy + 0.2 * s, c, w * 0.8)
    for k in (-0.34, 0.0, 0.34):
        p.line(cx + 0.2 * s, cy + 0.2 * s, cx + 0.92 * s, cy + 0.2 * s + k * s, c, w * 0.7)


def g_mixer(p, cx, cy, s, c, w):
    p.polygon(
        [
            (cx - 0.82 * s, cy - 0.42 * s),
            (cx + 0.82 * s, cy - 0.42 * s),
            (cx + 0.16 * s, cy + 0.34 * s),
            (cx + 0.16 * s, cy + 0.86 * s),
            (cx - 0.16 * s, cy + 0.86 * s),
            (cx - 0.16 * s, cy + 0.34 * s),
        ],
        outline=c,
        width=w,
    )
    p.dot(cx, cy - 0.76 * s, 0.19 * s, c)
    p.line(cx - 0.5 * s, cy - 0.16 * s, cx + 0.5 * s, cy - 0.16 * s, c, w * 0.7)


def g_swap(p, cx, cy, s, c, w):
    p.arrow(cx - 0.8 * s, cy - 0.34 * s, cx + 0.8 * s, cy - 0.34 * s, c, w, 0.28 * s)
    p.arrow(cx + 0.8 * s, cy + 0.34 * s, cx - 0.8 * s, cy + 0.34 * s, c, w, 0.28 * s)


def g_plate(p, cx, cy, s, c, w):
    p.rrect((cx - 0.88 * s, cy - 0.88 * s, cx + 0.88 * s, cy + 0.88 * s), 0.12 * s, outline=c, width=w)
    for i, gy in enumerate((-0.44, 0.0, 0.44)):
        for j, gx in enumerate((-0.44, 0.0, 0.44)):
            p.dot(cx + gx * s, cy + gy * s, (0.07 + 0.035 * (i + j)) * s, c)


def g_microscope(p, cx, cy, s, c, w):
    p.line(cx - 0.7 * s, cy + 0.88 * s, cx + 0.7 * s, cy + 0.88 * s, c, w * 1.2)
    p.line(cx - 0.12 * s, cy + 0.88 * s, cx - 0.12 * s, cy - 0.14 * s, c, w)
    p.line(cx - 0.6 * s, cy + 0.34 * s, cx + 0.52 * s, cy + 0.34 * s, c, w)
    p.line(cx - 0.12 * s, cy - 0.14 * s, cx + 0.44 * s, cy - 0.72 * s, c, w * 1.4)
    p.ellipse((cx + 0.34 * s, cy - 0.92 * s, cx + 0.76 * s, cy - 0.5 * s), outline=c, width=w * 0.8)


def g_chart_up(p, cx, cy, s, c, w):
    for i, k in enumerate((-0.88, -0.42, 0.04)):
        h = (0.2 + 0.28 * i) * s
        p.rrect((cx + k * s, cy + 0.82 * s - h, cx + (k + 0.34) * s, cy + 0.82 * s), 0.05 * s, fill=c)
    p.arrow(cx - 0.86 * s, cy + 0.12 * s, cx + 0.82 * s, cy - 0.7 * s, c, w, 0.3 * s)


def _gear(p, cx, cy, s, c, w):
    p.ellipse((cx - 0.58 * s, cy - 0.58 * s, cx + 0.58 * s, cy + 0.58 * s), outline=c, width=w)
    for ang in range(0, 360, 45):
        rad = math.radians(ang)
        p.line(
            cx + math.cos(rad) * 0.54 * s,
            cy + math.sin(rad) * 0.54 * s,
            cx + math.cos(rad) * 0.92 * s,
            cy + math.sin(rad) * 0.92 * s,
            c,
            w * 1.1,
        )


def g_gear(p, cx, cy, s, c, w):
    _gear(p, cx, cy, s, c, w)
    p.ellipse((cx - 0.22 * s, cy - 0.22 * s, cx + 0.22 * s, cy + 0.22 * s), outline=c, width=w * 0.8)


def g_gear_play(p, cx, cy, s, c, w):
    _gear(p, cx, cy, s, c, w)
    p.polygon(
        [(cx - 0.16 * s, cy - 0.28 * s), (cx + 0.26 * s, cy), (cx - 0.16 * s, cy + 0.28 * s)],
        fill=c,
    )


def g_laminate(p, cx, cy, s, c, w):
    for k in (-0.62, -0.16):
        p.rrect((cx - 0.9 * s, cy + k * s, cx + 0.9 * s, cy + (k + 0.3) * s), 0.14 * s, outline=c, width=w)
    p.rrect((cx - 0.9 * s, cy + 0.3 * s, cx + 0.9 * s, cy + 0.6 * s), 0.14 * s, fill=c)
    p.arrow(cx - 0.3 * s, cy + 0.88 * s, cx + 0.4 * s, cy + 0.88 * s, c, w * 0.8, 0.24 * s)


def g_wrench(p, cx, cy, s, c, w):
    p.line(cx - 0.62 * s, cy + 0.7 * s, cx + 0.28 * s, cy - 0.2 * s, c, w * 1.8)
    p.arc((cx + 0.12 * s, cy - 0.94 * s, cx + 0.92 * s, cy - 0.14 * s), 50, 330, c, w * 1.6)


def g_bolt(p, cx, cy, s, c, w):
    p.polygon(
        [
            (cx + 0.34 * s, cy - 0.95 * s),
            (cx - 0.62 * s, cy + 0.12 * s),
            (cx - 0.06 * s, cy + 0.12 * s),
            (cx - 0.3 * s, cy + 0.95 * s),
            (cx + 0.64 * s, cy - 0.14 * s),
            (cx + 0.08 * s, cy - 0.14 * s),
        ],
        fill=c,
    )


def g_remote(p, cx, cy, s, c, w):
    p.dot(cx, cy + 0.34 * s, 0.15 * s, c)
    for i, r in enumerate((0.4, 0.66, 0.92)):
        p.arc(
            (cx - r * s, cy + 0.34 * s - r * s, cx + r * s, cy + 0.34 * s + r * s),
            205,
            335,
            c,
            w * (1.0 - 0.1 * i),
        )
    p.rrect((cx - 0.34 * s, cy + 0.58 * s, cx + 0.34 * s, cy + 0.94 * s), 0.08 * s, outline=c, width=w * 0.8)


def g_flask(p, cx, cy, s, c, w):
    p.polygon(
        [
            (cx - 0.26 * s, cy - 0.9 * s),
            (cx + 0.26 * s, cy - 0.9 * s),
            (cx + 0.26 * s, cy - 0.34 * s),
            (cx + 0.8 * s, cy + 0.84 * s),
            (cx - 0.8 * s, cy + 0.84 * s),
            (cx - 0.26 * s, cy - 0.34 * s),
        ],
        outline=c,
        width=w,
    )
    p.line(cx - 0.34 * s, cy - 0.9 * s, cx + 0.34 * s, cy - 0.9 * s, c, w)
    p.polygon(
        [
            (cx - 0.55 * s, cy + 0.32 * s),
            (cx + 0.55 * s, cy + 0.32 * s),
            (cx + 0.72 * s, cy + 0.68 * s),
            (cx - 0.72 * s, cy + 0.68 * s),
        ],
        fill=c,
    )


def g_plane(p, cx, cy, s, c, w):
    half = [
        (0.0, -0.98),
        (0.13, -0.52),
        (0.95, 0.1),
        (0.95, 0.32),
        (0.13, 0.06),
        (0.11, 0.6),
        (0.42, 0.86),
        (0.42, 0.98),
        (0.0, 0.82),
    ]
    pts = [(cx + x * s, cy + y * s) for x, y in half]
    pts += [(cx - x * s, cy + y * s) for x, y in reversed(half)]
    p.polygon(pts, fill=c)


def g_bed(p, cx, cy, s, c, w):
    p.rrect((cx - 0.95 * s, cy - 0.58 * s, cx - 0.66 * s, cy + 0.6 * s), 0.08 * s, fill=c)
    p.rrect((cx - 0.7 * s, cy - 0.06 * s, cx + 0.95 * s, cy + 0.42 * s), 0.1 * s, outline=c, width=w)
    p.rrect((cx - 0.58 * s, cy - 0.44 * s, cx - 0.06 * s, cy - 0.1 * s), 0.1 * s, fill=c)
    p.line(cx + 0.82 * s, cy + 0.42 * s, cx + 0.82 * s, cy + 0.72 * s, c, w)


def _car_body(p, cx, cy, s, c, w):
    p.polygon(
        [
            (cx - 0.95 * s, cy + 0.28 * s),
            (cx - 0.82 * s, cy - 0.1 * s),
            (cx - 0.44 * s, cy - 0.54 * s),
            (cx + 0.34 * s, cy - 0.54 * s),
            (cx + 0.7 * s, cy - 0.1 * s),
            (cx + 0.95 * s, cy + 0.04 * s),
            (cx + 0.95 * s, cy + 0.28 * s),
        ],
        outline=c,
        width=w,
    )
    p.line(cx - 0.72 * s, cy - 0.1 * s, cx + 0.6 * s, cy - 0.1 * s, c, w * 0.7)
    p.dot(cx - 0.48 * s, cy + 0.36 * s, 0.2 * s, c)
    p.dot(cx + 0.48 * s, cy + 0.36 * s, 0.2 * s, c)


def g_car(p, cx, cy, s, c, w):
    _car_body(p, cx, cy, s, c, w)


def g_taxi(p, cx, cy, s, c, w):
    _car_body(p, cx, cy + 0.14 * s, s * 0.94, c, w)
    p.rrect((cx - 0.24 * s, cy - 0.86 * s, cx + 0.24 * s, cy - 0.56 * s), 0.06 * s, fill=c)


def g_meal(p, cx, cy, s, c, w):
    for k in (-0.62, -0.4, -0.18):
        p.line(cx + k * s, cy - 0.9 * s, cx + k * s, cy - 0.34 * s, c, w * 0.8)
    p.line(cx - 0.62 * s, cy - 0.34 * s, cx - 0.18 * s, cy - 0.34 * s, c, w * 0.8)
    p.line(cx - 0.4 * s, cy - 0.34 * s, cx - 0.4 * s, cy + 0.9 * s, c, w)
    p.polygon(
        [
            (cx + 0.3 * s, cy - 0.9 * s),
            (cx + 0.56 * s, cy - 0.62 * s),
            (cx + 0.44 * s, cy - 0.1 * s),
            (cx + 0.3 * s, cy - 0.1 * s),
        ],
        fill=c,
    )
    p.line(cx + 0.37 * s, cy - 0.1 * s, cx + 0.37 * s, cy + 0.9 * s, c, w)


def g_doc(p, cx, cy, s, c, w):
    p.polygon(
        [
            (cx - 0.68 * s, cy - 0.92 * s),
            (cx + 0.28 * s, cy - 0.92 * s),
            (cx + 0.68 * s, cy - 0.52 * s),
            (cx + 0.68 * s, cy + 0.92 * s),
            (cx - 0.68 * s, cy + 0.92 * s),
        ],
        outline=c,
        width=w,
    )
    p.path([(cx + 0.28 * s, cy - 0.92 * s), (cx + 0.28 * s, cy - 0.52 * s), (cx + 0.68 * s, cy - 0.52 * s)], c, w * 0.8)
    for k in (-0.16, 0.16, 0.48):
        p.line(cx - 0.42 * s, cy + k * s, cx + 0.42 * s, cy + k * s, c, w * 0.7)


GLYPHS = {name[2:]: fn for name, fn in list(globals().items()) if name.startswith("g_")}


def render_tile(sku: str, family: str, glyph: str, size: int, logo: Image.Image) -> Image.Image:
    accent, label = FAMILIES[family]
    margin = round(size * 0.039)
    panel = size - 2 * margin
    header = round(panel * 0.27)

    img = Image.new("RGB", (panel * SS, panel * SS), blend(accent, WHITE, 0.05))
    p = Pen(ImageDraw.Draw(img))

    p.rect((0, 0, panel, header), fill=accent)

    # Simbolo Comexi en blanco, alineado a la derecha del cabecero.
    symbol = logo.crop(LOGO_SYMBOL_BOX)
    sym_h = round(header * 0.42) * SS
    sym_w = round(sym_h * symbol.width / symbol.height)
    symbol = symbol.resize((sym_w, sym_h), Image.LANCZOS)
    white_symbol = Image.new("RGBA", symbol.size, WHITE + (255,))
    img.paste(white_symbol, (panel * SS - sym_w - round(panel * 0.06) * SS, (header * SS - sym_h) // 2), symbol)

    sku_x = panel * 0.062
    sku_max = (panel * SS - sym_w - round(panel * 0.06) * SS) - (sku_x + panel * 0.03) * SS
    sku_font = load_font(round(panel * 0.115 * SS))
    while p.d.textlength(sku, font=sku_font) > sku_max and sku_font.size > 8 * SS:
        sku_font = load_font(sku_font.size - SS)
    p.text((sku_x, header * 0.36), sku, sku_font, WHITE, anchor="lm")
    p.text(
        (panel * 0.065, header * 0.73),
        label,
        load_font(round(panel * 0.042 * SS)),
        blend(WHITE, accent, 0.78),
        anchor="lm",
        spacing=panel * 0.012,
    )

    glyph_cy = header + (panel * 0.865 - header) / 2
    GLYPHS[glyph](p, panel / 2, glyph_cy, panel * 0.185, accent, panel * 0.024)

    # Wordmark COMEXI centrado en el pie.
    wordmark = logo.crop(LOGO_WORDMARK_BOX)
    wm_w = round(panel * 0.46) * SS
    wm_h = round(wm_w * wordmark.height / wordmark.width)
    wordmark = wordmark.resize((wm_w, wm_h), Image.LANCZOS)
    wm_y = round(panel * 0.905) * SS - wm_h // 2
    img.paste(Image.new("RGBA", wordmark.size, COMEXI_SLATE + (255,)), ((panel * SS - wm_w) // 2, wm_y), wordmark)

    mask = Image.new("L", (panel * SS, panel * SS), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, panel * SS - 1, panel * SS - 1], radius=round(panel * 0.055) * SS, fill=255
    )
    panel_img = Image.new("RGB", (panel, panel), WHITE)
    panel_img.paste(img.resize((panel, panel), Image.LANCZOS), (0, 0), mask.resize((panel, panel), Image.LANCZOS))

    tile = Image.new("RGB", (size, size), WHITE)
    tile.paste(panel_img, (margin, margin))
    return tile


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--out", type=Path, default=DEFAULT_OUT, help="Directorio de salida")
    ap.add_argument("--size", type=int, default=512, help="Lado del PNG en px")
    args = ap.parse_args()

    if not LOGO_PATH.exists():
        raise SystemExit(f"No se encuentra el logo Comexi en {LOGO_PATH}")

    logo = Image.open(LOGO_PATH).convert("RGBA")
    args.out.mkdir(parents=True, exist_ok=True)

    missing = sorted({g for _, _, g in PRODUCTS} - GLYPHS.keys())
    if missing:
        raise SystemExit(f"Glifos no implementados: {', '.join(missing)}")

    for sku, family, glyph in PRODUCTS:
        path = args.out / f"{sku}.png"
        render_tile(sku, family, glyph, args.size, logo).save(path, "PNG", optimize=True)
        print(f"  {path.name:22s} {family:8s} {glyph}")

    total = sum(f.stat().st_size for f in args.out.glob("*.png"))
    print(f"\n{len(PRODUCTS)} imagenes en {args.out} ({total / 1024:.0f} KB)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
