#!/usr/bin/env python3
"""Copia las cuatro secciones COMEXI del layout RLM al layout de contrato que la org usa.

El record type ContractLifecycleManagement no usa "RLM Contract Layout" sino el
"Contract Layout" estandar, y la pagina Contract_Record_Page monta su pestana Details
con force:detailPanel, o sea desde el layout asignado. Parchear solo el RLM dejaba los
veinte campos rellenos pero invisibles.

Uso:
    sf project retrieve start -o <org> -m "Layout:Contract-Contract Layout" \
        --target-metadata-dir .tmp_layout --unzip
    python3 scripts/apex/comexi/19_add_comexi_sections_to_contract_layout.py \
        --source .tmp_layout/unpackaged/unpackaged/layouts/Contract-Contract Layout.layout

Reejecutable: si el destino ya tiene las secciones COMEXI, las sustituye en lugar de
duplicarlas.
"""

import argparse
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
DONOR = REPO / "unpackaged/post_comexi/layouts/Contract-RLM Contract Layout.layout-meta.xml"
TARGET = REPO / "unpackaged/post_comexi/layouts/Contract-Contract Layout.layout-meta.xml"

SECTION_RE = re.compile(r"[ \t]*<layoutSections>.*?</layoutSections>\n", re.DOTALL)
ANCHOR_LABEL = "Contract Information"


def sections(xml: str) -> list[str]:
    return SECTION_RE.findall(xml)


def is_comexi(section: str) -> bool:
    return "COMEXI" in section


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--source",
        required=True,
        help="Layout recien recuperado de la org que se va a parchear",
    )
    args = parser.parse_args()

    source = Path(args.source)
    if not source.is_file():
        print(f"No existe el layout de origen: {source}", file=sys.stderr)
        return 1
    if not DONOR.is_file():
        print(f"No existe el layout donante: {DONOR}", file=sys.stderr)
        return 1

    donor_sections = [s for s in sections(DONOR.read_text()) if is_comexi(s)]
    if len(donor_sections) != 4:
        print(
            f"Esperaba 4 secciones COMEXI en el donante y encontre {len(donor_sections)}. "
            "Revisa Contract-RLM Contract Layout antes de seguir.",
            file=sys.stderr,
        )
        return 1

    xml = source.read_text()
    # Se quitan las propias por si el origen ya venia parcheado: asi el script es reejecutable.
    for existing in [s for s in sections(xml) if is_comexi(s)]:
        xml = xml.replace(existing, "")

    anchor = next(
        (s for s in sections(xml) if f"<label>{ANCHOR_LABEL}</label>" in s), None
    )
    if anchor is None:
        print(
            f"No encuentro la seccion '{ANCHOR_LABEL}' en {source.name}; "
            "sin ancla no se sabe donde insertar.",
            file=sys.stderr,
        )
        return 1

    xml = xml.replace(anchor, anchor + "".join(donor_sections), 1)

    TARGET.parent.mkdir(parents=True, exist_ok=True)
    TARGET.write_text(xml)
    print(f"Escrito {TARGET.relative_to(REPO)} con 4 secciones COMEXI tras '{ANCHOR_LABEL}'.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
