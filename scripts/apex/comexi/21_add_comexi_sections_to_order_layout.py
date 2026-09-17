#!/usr/bin/env python3
"""Añade las secciones COMEXI al page layout activo del pedido.

Cinturón y tirantes. Los campos ya se declaran en la flexipage
(`20_add_comexi_fields_to_order_flexipage.py`), que es lo que renderiza hoy la
pestaña Detalles del pedido. Pero la lección del contrato fue justamente esta: la
página que creíamos activa no era la que la org usaba, y los campos quedaron
invisibles. Aquí se comprobó con la UI API que el layout activo es
`00hbm00000W6JSGAA3` = "RLM Order Layout", así que se parchea también. Si alguien
cambia la asignación de página, los campos siguen apareciendo.

Lee de unpackaged/post_ux (salida ensamblada) y escribe en unpackaged/post_comexi,
que se despliega después y por tanto gana.
"""

import sys
import xml.etree.ElementTree as ET
from pathlib import Path

NS = "http://soap.sforce.com/2006/04/metadata"
REPO = Path(__file__).resolve().parents[3]
NAME = "Order-RLM Order Layout.layout-meta.xml"
SRC = REPO / "unpackaged/post_ux/layouts" / NAME
DST = REPO / "unpackaged/post_comexi/layouts" / NAME

# Detrás de Order Information, para que las secciones COMEXI queden arriba.
ANCHOR_LABEL = "Order Information"

# (etiqueta, columna 1, columna 2). Las formulas van en Readonly: declararlas
# editables rompe el despliegue del layout.
READ_ONLY = {
    "COMEXI_Machine_Model__c",
    "COMEXI_Down_Payment_Amount__c",
    "COMEXI_SAP_Customer_Code__c",
}

SECTIONS = [
    (
        "COMEXI: Origen del pedido",
        ["COMEXI_Source_Case__c", "COMEXI_Source_Opportunity__c", "COMEXI_Generated_By_Advisor__c"],
        ["COMEXI_Target_Asset__c", "COMEXI_Machine_Model__c"],
    ),
    (
        "COMEXI: Alcance del retrofit",
        ["COMEXI_Retrofit_Type__c", "COMEXI_Retrofit_SKU__c"],
        ["COMEXI_Obsolete_Component__c"],
    ),
    (
        "COMEXI: Intervencion",
        [
            "COMEXI_Intervention_Site__c",
            "COMEXI_Intervention_Country__c",
            "COMEXI_Intervention_Weeks__c",
        ],
        [
            "COMEXI_Target_Intervention_Date__c",
            "COMEXI_Intervention_Hours__c",
            "COMEXI_Expenses_Owner__c",
        ],
    ),
    (
        "COMEXI: Anticipo y salida a SAP",
        [
            "COMEXI_Down_Payment_Pct__c",
            "COMEXI_Down_Payment_Amount__c",
            "COMEXI_Down_Payment_Status__c",
        ],
        ["COMEXI_Payment_Terms__c", "COMEXI_SAP_Customer_Code__c"],
    ),
]


def q(tag):
    return f"{{{NS}}}{tag}"


def sub(parent, tag, text=None):
    el = ET.SubElement(parent, q(tag))
    if text is not None:
        el.text = text
    return el


def build_section(label, col1, col2):
    section = ET.Element(q("layoutSections"))
    sub(section, "customLabel", "true")
    sub(section, "detailHeading", "true")
    sub(section, "editHeading", "true")
    sub(section, "label", label)
    for fields in (col1, col2):
        column = sub(section, "layoutColumns")
        for f in fields:
            item = sub(column, "layoutItems")
            sub(item, "behavior", "Readonly" if f in READ_ONLY else "Edit")
            sub(item, "field", f)
    sub(section, "style", "TwoColumnsTopToBottom")
    return section


def main():
    if not SRC.exists():
        sys.exit(f"No existe {SRC}. Ejecuta antes el retrieve del layout.")

    ET.register_namespace("", NS)
    tree = ET.parse(SRC)
    root = tree.getroot()

    existing_labels = {
        s.find(q("label")).text
        for s in root.findall(q("layoutSections"))
        if s.find(q("label")) is not None
    }
    existing_fields = {e.text for e in root.iter(q("field"))}

    children = list(root)
    anchor_pos = None
    for i, child in enumerate(children):
        if child.tag != q("layoutSections"):
            continue
        label = child.find(q("label"))
        if label is not None and label.text == ANCHOR_LABEL:
            anchor_pos = i + 1
    if anchor_pos is None:
        sys.exit(f"No se encontró la sección ancla '{ANCHOR_LABEL}'.")

    added = 0
    for label, col1, col2 in SECTIONS:
        if label in existing_labels:
            print(f"Sección '{label}' ya presente, se omite.")
            continue
        c1 = [f for f in col1 if f not in existing_fields]
        c2 = [f for f in col2 if f not in existing_fields]
        if not c1 and not c2:
            print(f"Sección '{label}': todos sus campos ya están en el layout.")
            continue
        root.insert(anchor_pos + added, build_section(label, c1, c2))
        added += 1
        print(f"Sección añadida: {label}")

    if not added:
        print("Nada que añadir.")
        return

    ET.indent(tree, space="    ")
    DST.parent.mkdir(parents=True, exist_ok=True)
    tree.write(DST, encoding="UTF-8", xml_declaration=True)
    print(f"Escrito {DST}")


if __name__ == "__main__":
    main()
