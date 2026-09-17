#!/usr/bin/env python3
"""Descarga y normaliza las fotos reales de las maquinas Comexi.

Descarga las URLs canonicas de comexi.com/wp-content/uploads/, aplana sobre blanco,
encaja cada foto en un lienzo uniforme 640x480 (contain, sin recortar) y guarda un
JPEG q85 por SKU en:
    unpackaged/post_comexi/staticresources/COMEXI_MachineryImages/

Ese directorio se despliega como static resource zip y se referencia desde
Product2.DisplayUrl con la ruta /resource/COMEXI_MachineryImages/<SKU>.jpg
(ver scripts/apex/comexi/11_machinery_products.apex).

Las fotos descargadas se versionan en el repo: la web usa NitroPack y el <src> literal
es un placeholder base64, asi que depender de la descarga en cada build seria fragil.
Si una descarga falla, se genera un placeholder de marca para que el SKU no quede sin foto.

Uso:
    python3 scripts/build_comexi_machinery_images.py [--out DIR] [--force]
"""

from __future__ import annotations

import argparse
import urllib.request
from io import BytesIO
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_OUT = (
    REPO_ROOT / "unpackaged" / "post_comexi" / "staticresources" / "COMEXI_MachineryImages"
)

CANVAS = (640, 480)
WHITE = (255, 255, 255)
COMEXI_RED = (237, 24, 72)
COMEXI_SLATE = (69, 85, 96)

UPLOADS = "https://comexi.com/wp-content/uploads/"

# SKU -> ruta relativa dentro de /wp-content/uploads/ (ver build-spec/10 §6).
PRODUCTS = {
    "MAQ-F1-EVO": "2025/06/Comexi-Flexo-F1-Evolution-1024x576.png",
    "MAQ-F2-ML": "2023/05/Impressores-comexi-printers_F2-ML-1024x604.png",
    "MAQ-F2-ORIGIN": "2026/05/F2Origin-black-1024x498.png",
    "MAQ-F2-MB": "2023/05/F2-MB-1024x535.png",
    "MAQ-F4-ORIGIN": "2025/10/20250701_ComexiF4_014-1-1024x683.png",
    "MAQ-OFFSET-CI-EVO": "2023/05/Impressores-comexi-printers_Offset-CI-1024x604.png",
    "MAQ-DIGIFLEX": "2023/05/Impressores-comexi-printers_Digifelx-1024x604.png",
    "MAQ-SL2-MB": "2023/04/Comexi-SL2-MB-3-1024x709.png",
    "MAQ-SL2-EVO": "2023/05/SL2-Evolution-1024x645.png",
    "MAQ-ML2-EVO": "2023/04/ML2-Evolution_1-1024x805.png",
    "MAQ-ML1-EVO": "2025/06/Comexi_ML1_03_web-1024x819.png",
    "MAQ-LASER": "2023/05/EVO-2-CONJUNTO-DER-e1683268893314-1024x543.png",
    "MAQ-S1-DT": "2023/05/S1DT-1024x604.png",
    "MAQ-S1-DS": "2023/05/S1DS-1024x604.png",
    "MAQ-S2-DT": "2023/05/S2DT-1024x604.png",
    "MAQ-S2-DS": "2023/05/S2DS-1024x604.png",
    "MAQ-S1-MS": "2023/04/S1-MS.png",
    "MAQ-S1-MT": "2023/05/S1MT-1024x604.png",
    "MAQ-DM1": "2023/06/Comexi_DoctorMachine1-04-1-1024x576.png",
    "MAQ-S4-ENERGY": "2024/07/S4_Energy_Comexi-1024x683.png",
    "MAQ-S2-ENERGY": "2024/07/S2_Energy_Comexi_web-1024x683.png",
    "MAQ-BATTERY-SEP": "2024/03/Installation-of-Comexi-S1-DT-Will-Enable-Wipak-UK-to-Expand.jpg",
    "MAQ-ENERGY-WINDERS": "2024/01/DSC00186_editada-1-1-1024x576.png",
}

HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
        "(KHTML, like Gecko) Chrome/124.0 Safari/537.36"
    ),
    "Referer": "https://comexi.com/",
}


def _load_font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    for name in ("Helvetica.ttc", "Arial.ttf", "DejaVuSans.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default()


def _download(url: str) -> Image.Image | None:
    req = urllib.request.Request(url, headers=HEADERS)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = resp.read()
    except Exception as exc:  # noqa: BLE001 - queremos un fallback robusto
        print(f"  ! descarga fallida: {exc}")
        return None
    try:
        return Image.open(BytesIO(data))
    except Exception as exc:  # noqa: BLE001
        print(f"  ! no es imagen valida: {exc}")
        return None


def _flatten(img: Image.Image) -> Image.Image:
    """Aplana transparencia sobre blanco y devuelve RGB."""
    img = img.convert("RGBA")
    bg = Image.new("RGBA", img.size, WHITE + (255,))
    bg.alpha_composite(img)
    return bg.convert("RGB")


def _fit_canvas(img: Image.Image) -> Image.Image:
    """Encaja img dentro de CANVAS (contain) centrada sobre fondo blanco."""
    canvas = Image.new("RGB", CANVAS, WHITE)
    src = img.copy()
    src.thumbnail(CANVAS, Image.LANCZOS)
    x = (CANVAS[0] - src.width) // 2
    y = (CANVAS[1] - src.height) // 2
    canvas.paste(src, (x, y))
    return canvas


def _placeholder(sku: str) -> Image.Image:
    """Baldosa de marca cuando la descarga falla, para no dejar el SKU sin foto."""
    canvas = Image.new("RGB", CANVAS, WHITE)
    draw = ImageDraw.Draw(canvas)
    draw.rectangle([0, 0, CANVAS[0] - 1, 8], fill=COMEXI_RED)
    font_brand = _load_font(40)
    font_sku = _load_font(28)
    draw.text((CANVAS[0] / 2, 200), "COMEXI", font=font_brand, fill=COMEXI_RED, anchor="mm")
    draw.text((CANVAS[0] / 2, 260), sku, font=font_sku, fill=COMEXI_SLATE, anchor="mm")
    return canvas


def build(out_dir: Path, force: bool) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    ok = 0
    placeholders = 0
    for sku, rel in PRODUCTS.items():
        dest = out_dir / f"{sku}.jpg"
        if dest.exists() and not force:
            print(f"= {sku}: ya existe (usa --force para re-descargar)")
            ok += 1
            continue
        url = UPLOADS + rel
        print(f"- {sku}: {url}")
        img = _download(url)
        if img is None:
            canvas = _placeholder(sku)
            placeholders += 1
        else:
            canvas = _fit_canvas(_flatten(img))
            ok += 1
        canvas.save(dest, "JPEG", quality=85, optimize=True)
    print(f"\nHecho. {ok} fotos, {placeholders} placeholders -> {out_dir}")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--out", type=Path, default=DEFAULT_OUT)
    ap.add_argument("--force", action="store_true", help="Re-descarga aunque el JPEG ya exista")
    args = ap.parse_args()
    build(args.out, args.force)


if __name__ == "__main__":
    main()
