#!/usr/bin/env python3
"""Añade las secciones COMEXI a la pestaña Detalles de RLM_Account_Record_Page.

La Lightning Record Page de Account no usa el componente de detalle del page
layout: construye la pestaña Detalles con `flexipage:fieldSection` de campos
fijos. Por eso tocar el Layout no hace visibles los campos nuevos y hay que
inyectarlos aquí.

Lee la flexipage de unpackaged/post_ux (salida ensamblada, refrescada con
retrieve) y escribe la variante COMEXI en unpackaged/post_comexi, que se
despliega después y por tanto gana.
"""

import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

NS = "http://soap.sforce.com/2006/04/metadata"
REPO = Path(__file__).resolve().parents[3]
SRC = REPO / "unpackaged/post_ux/flexipages/RLM_Account_Record_Page.flexipage-meta.xml"
DST = REPO / "unpackaged/post_comexi/flexipages/RLM_Account_Record_Page.flexipage-meta.xml"

# La pestaña Detalles es el facet `feedTabContent` (lo referencia el tab con
# identifier `detailTab`); `detailTabContent` cuelga del sidebar de Slack.
DETAIL_REGION = "feedTabContent"
# Insertamos justo detrás de Additional Information para que las secciones
# COMEXI queden arriba, no enterradas bajo System Information.
ANCHOR_IDENTIFIER = "flexipage_fieldSection2"

SECTIONS = [
    (
        "COMEXI: Cliente y canal de venta",
        ["COMEXI_SAP_Customer_Code__c", "COMEXI_Offer_Language__c", "COMEXI_Country_Risk__c"],
        [
            "COMEXI_Has_Representative__c",
            "COMEXI_Representative_Name__c",
            "COMEXI_Representative_Commission_Pct__c",
        ],
    ),
    (
        "COMEXI: Condiciones economicas",
        ["COMEXI_Payment_Terms_Days__c", "COMEXI_Down_Payment_Pct__c"],
        ["COMEXI_Warranty_Uplift_Pct__c", "COMEXI_RALF_Applicable__c"],
    ),
    (
        "COMEXI: Parque instalado y servicio",
        [
            "COMEXI_Machine_Park_Size__c",
            "COMEXI_Installed_Base_Value__c",
            "COMEXI_Service_Level__c",
        ],
        ["COMEXI_Service_Contract_End__c", "COMEXI_Last_Intervention_Date__c"],
    ),
    (
        "COMEXI: Notas tecnicas de planta",
        ["COMEXI_Technical_Site_Notes__c"],
        [],
    ),
]


def q(tag):
    return f"{{{NS}}}{tag}"


def sub(parent, tag, text=None):
    el = ET.SubElement(parent, q(tag))
    if text is not None:
        el.text = text
    return el


def field_identifier(api_name):
    return "Record" + re.sub(r"[^A-Za-z0-9]", "", api_name) + "Field"


def make_region(name, item_builders):
    """flexiPageRegions exige el orden itemInstances* -> mode? -> name -> type."""
    region = ET.Element(q("flexiPageRegions"))
    for build in item_builders:
        build(sub(region, "itemInstances"))
    sub(region, "name", name)
    sub(region, "type", "Facet")
    return region


def component_builder(component_name, identifier, props):
    def build(item):
        ci = sub(item, "componentInstance")
        for k, v in props:
            p = sub(ci, "componentInstanceProperties")
            sub(p, "name", k)
            sub(p, "value", v)
        sub(ci, "componentName", component_name)
        sub(ci, "identifier", identifier)

    return build


def field_builder(api_name):
    def build(item):
        fi = sub(item, "fieldInstance")
        p = sub(fi, "fieldInstanceProperties")
        sub(p, "name", "uiBehavior")
        sub(p, "value", "none")
        sub(fi, "fieldItem", f"Record.{api_name}")
        sub(fi, "identifier", field_identifier(api_name))

    return build


def main():
    if not SRC.exists():
        sys.exit(f"No existe {SRC}. Ejecuta antes el retrieve de la flexipage.")

    ET.register_namespace("", NS)
    tree = ET.parse(SRC)
    root = tree.getroot()

    regions = root.findall(q("flexiPageRegions"))
    detail = next(
        (r for r in regions if (r.find(q("name")) is not None and r.find(q("name")).text == DETAIL_REGION)),
        None,
    )
    if detail is None:
        sys.exit(f"No se encontró la región {DETAIL_REGION}.")

    existing_fields = {e.text for e in root.iter(q("fieldItem"))}
    new_regions = []
    section_items = []

    for idx, (label, col1, col2) in enumerate(SECTIONS, start=1):
        col1 = [f for f in col1 if f"Record.{f}" not in existing_fields]
        col2 = [f for f in col2 if f"Record.{f}" not in existing_fields]
        if not col1 and not col2:
            print(f"Sección '{label}' ya presente, se omite.")
            continue

        cols_facet = f"Facet-comexi-s{idx}-cols"
        column_builders = []
        for col_idx, fields in enumerate([col1, col2], start=1):
            if not fields:
                continue
            body_facet = f"Facet-comexi-s{idx}-c{col_idx}"
            new_regions.append(make_region(body_facet, [field_builder(f) for f in fields]))
            column_builders.append(
                component_builder(
                    "flexipage:column",
                    f"comexi_column_s{idx}_c{col_idx}",
                    [("body", body_facet)],
                )
            )

        new_regions.append(make_region(cols_facet, column_builders))
        section_items.append(
            component_builder(
                "flexipage:fieldSection",
                f"comexi_fieldSection{idx}",
                [("columns", cols_facet), ("horizontalAlignment", "false"), ("label", label)],
            )
        )

    if not section_items:
        print("Nada que añadir: todos los campos COMEXI ya están en la flexipage.")
        return

    # Insertar los fieldSection detrás del ancla dentro de la pestaña Detalles.
    children = list(detail)
    anchor_pos = 0
    for i, child in enumerate(children):
        ident = child.find(f"{q('componentInstance')}/{q('identifier')}")
        if ident is not None and ident.text == ANCHOR_IDENTIFIER:
            anchor_pos = i + 1
    for offset, build in enumerate(section_items):
        item = ET.Element(q("itemInstances"))
        build(item)
        detail.insert(anchor_pos + offset, item)

    # Los flexiPageRegions deben ir todos juntos, antes de masterLabel.
    last_region_pos = max(i for i, c in enumerate(list(root)) if c.tag == q("flexiPageRegions"))
    for offset, region in enumerate(new_regions):
        root.insert(last_region_pos + 1 + offset, region)

    ET.indent(tree, space="    ")
    DST.parent.mkdir(parents=True, exist_ok=True)
    tree.write(DST, encoding="UTF-8", xml_declaration=True)
    print(f"Escrito {DST}")
    print(f"Secciones añadidas: {len(section_items)} | facets nuevos: {len(new_regions)}")


if __name__ == "__main__":
    main()
