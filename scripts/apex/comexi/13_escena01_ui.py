#!/usr/bin/env python3
"""Escena 01: hace visibles el vinculo Asset<->Case y la ficha tecnica del Asset.

El detalle de un registro puede renderizarse de dos formas y en esta org conviven
las dos, asi que hay que tocar ambas:

  - Page layout, cuando la Lightning page usa force:detailPanel.
  - flexipage:fieldSection con campos fijos, que ignora por completo el layout.

Lee los ficheros recuperados de la org en .verify* y escribe las variantes COMEXI
en unpackaged/post_comexi, que se despliega despues de post_ux y por tanto gana.

Uso:
    sf project retrieve start --metadata "Layout:Case-Case Layout" \
        --metadata "Layout:Asset-Asset Layout" --target-org comexi \
        --target-metadata-dir .verify --unzip
    sf project retrieve start --metadata "FlexiPage:RLM_Asset_Record_Page" \
        --metadata "FlexiPage:RLM_Case_Record_Page" --target-org comexi \
        --target-metadata-dir .verify2 --unzip
    python3 scripts/apex/comexi/13_escena01_ui.py
"""

import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

NS = "http://soap.sforce.com/2006/04/metadata"
REPO = Path(__file__).resolve().parents[3]
LAYOUT_SRC = REPO / ".verify/unpackaged/unpackaged/layouts"
FLEXI_SRC = REPO / ".verify2/unpackaged/unpackaged/flexipages"
LAYOUT_DST = REPO / "unpackaged/post_comexi/layouts"
FLEXI_DST = REPO / "unpackaged/post_comexi/flexipages"

COMEXI_ASSET_SECTION = (
    "COMEXI: Ficha tecnica de la maquina",
    ["COMEXI_Machine_Model__c", "COMEXI_Install_Year__c"],
    ["COMEXI_Line__c", "COMEXI_Installed_Config__c"],
)


def q(tag):
    return f"{{{NS}}}{tag}"


def sub(parent, tag, text=None):
    el = ET.SubElement(parent, q(tag))
    if text is not None:
        el.text = text
    return el


# --------------------------------------------------------------------------- #
# Page layouts
# --------------------------------------------------------------------------- #

def layout_item(field, behavior="Edit"):
    item = ET.Element(q("layoutItems"))
    sub(item, "behavior", behavior)
    sub(item, "field", field)
    return item


def insert_after_field(root, anchor, new_fields):
    """Mete campos justo detras de un campo ancla, en su misma columna."""
    added = []
    existing = {e.text for e in root.iter(q("field"))}
    for column in root.iter(q("layoutColumns")):
        items = list(column)
        for idx, item in enumerate(items):
            fld = item.find(q("field"))
            if fld is None or fld.text != anchor:
                continue
            offset = 1
            for field in new_fields:
                if field in existing:
                    continue
                column.insert(idx + offset, layout_item(field))
                added.append(field)
                offset += 1
            return added
    return added


def append_layout_section(root, label, col1, col2):
    existing = {e.text for e in root.iter(q("field"))}
    col1 = [f for f in col1 if f not in existing]
    col2 = [f for f in col2 if f not in existing]
    if not col1 and not col2:
        return []

    section = ET.Element(q("layoutSections"))
    sub(section, "customLabel", "true")
    sub(section, "detailHeading", "true")
    sub(section, "editHeading", "true")
    sub(section, "label", label)
    for fields in (col1, col2):
        if not fields:
            continue
        column = sub(section, "layoutColumns")
        for field in fields:
            column.append(layout_item(field))
    sub(section, "style", "TwoColumnsTopToBottom" if col2 else "OneColumn")

    children = list(root)
    last = max(i for i, c in enumerate(children) if c.tag == q("layoutSections"))
    root.insert(last + 1, section)
    return col1 + col2


def process_layout(name, mutate):
    src = LAYOUT_SRC / f"{name}.layout"
    if not src.exists():
        sys.exit(f"Falta {src}. Recupera antes el layout de la org.")
    ET.register_namespace("", NS)
    tree = ET.parse(src)
    added = mutate(tree.getroot())
    ET.indent(tree, space="    ")
    LAYOUT_DST.mkdir(parents=True, exist_ok=True)
    tree.write(LAYOUT_DST / f"{name}.layout-meta.xml", encoding="UTF-8", xml_declaration=True)
    print(f"  {name}: {added or 'sin cambios'}")


# --------------------------------------------------------------------------- #
# Flexipages
# --------------------------------------------------------------------------- #

def field_identifier(api_name):
    return "Record" + re.sub(r"[^A-Za-z0-9]", "", api_name) + "Field"


def field_instance(api_name):
    item = ET.Element(q("itemInstances"))
    fi = sub(item, "fieldInstance")
    prop = sub(fi, "fieldInstanceProperties")
    sub(prop, "name", "uiBehavior")
    sub(prop, "value", "none")
    sub(fi, "fieldItem", f"Record.{api_name}")
    sub(fi, "identifier", field_identifier(api_name))
    return item


def flexi_insert_after(root, anchor, new_fields):
    """Inyecta campos en el mismo facet-columna donde ya vive el campo ancla."""
    existing = {e.text for e in root.iter(q("fieldItem"))}
    for region in root.findall(q("flexiPageRegions")):
        items = list(region)
        for idx, item in enumerate(items):
            fld = item.find(f"{q('fieldInstance')}/{q('fieldItem')}")
            if fld is None or fld.text != f"Record.{anchor}":
                continue
            added, offset = [], 1
            for field in new_fields:
                if f"Record.{field}" in existing:
                    continue
                region.insert(idx + offset, field_instance(field))
                added.append(field)
                offset += 1
            return added
    return []


def flexi_add_section(root, label, col1, col2, tag):
    existing = {e.text for e in root.iter(q("fieldItem"))}
    col1 = [f for f in col1 if f"Record.{f}" not in existing]
    col2 = [f for f in col2 if f"Record.{f}" not in existing]
    if not col1 and not col2:
        return []

    def make_region(name, builders):
        region = ET.Element(q("flexiPageRegions"))
        for build in builders:
            region.append(build())
        sub(region, "name", name)
        sub(region, "type", "Facet")
        return region

    def column(body_facet, ident):
        def build():
            item = ET.Element(q("itemInstances"))
            ci = sub(item, "componentInstance")
            prop = sub(ci, "componentInstanceProperties")
            sub(prop, "name", "body")
            sub(prop, "value", body_facet)
            sub(ci, "componentName", "flexipage:column")
            sub(ci, "identifier", ident)
            return item
        return build

    cols_facet = f"Facet-comexi-{tag}-cols"
    new_regions, column_builders = [], []
    for col_idx, fields in enumerate([col1, col2], start=1):
        if not fields:
            continue
        body = f"Facet-comexi-{tag}-c{col_idx}"
        new_regions.append(make_region(body, [(lambda f=f: field_instance(f)) for f in fields]))
        column_builders.append(column(body, f"comexi_column_{tag}_c{col_idx}"))
    new_regions.append(make_region(cols_facet, column_builders))

    # La pestana Detalles es la region que ya contiene los fieldSection.
    detail = None
    for region in root.findall(q("flexiPageRegions")):
        names = region.findall(f"{q('itemInstances')}/{q('componentInstance')}/{q('componentName')}")
        if any(n.text == "flexipage:fieldSection" for n in names):
            detail = region
            break
    if detail is None:
        sys.exit("No se encontro la region con los fieldSection.")

    item = ET.Element(q("itemInstances"))
    ci = sub(item, "componentInstance")
    for k, v in [("columns", cols_facet), ("horizontalAlignment", "false"), ("label", label)]:
        prop = sub(ci, "componentInstanceProperties")
        sub(prop, "name", k)
        sub(prop, "value", v)
    sub(ci, "componentName", "flexipage:fieldSection")
    sub(ci, "identifier", f"comexi_fieldSection_{tag}")

    # Detras del primer fieldSection, para que quede arriba y no bajo System Information.
    pos = 0
    for idx, child in enumerate(list(detail)):
        cn = child.find(f"{q('componentInstance')}/{q('componentName')}")
        if cn is not None and cn.text == "flexipage:fieldSection":
            pos = idx + 1
            break
    detail.insert(pos, item)

    children = list(root)
    last = max(i for i, c in enumerate(children) if c.tag == q("flexiPageRegions"))
    for offset, region in enumerate(new_regions):
        root.insert(last + 1 + offset, region)
    return col1 + col2


def process_flexipage(name, mutate):
    src = FLEXI_SRC / f"{name}.flexipage"
    if not src.exists():
        sys.exit(f"Falta {src}. Recupera antes la flexipage de la org.")
    ET.register_namespace("", NS)
    tree = ET.parse(src)
    added = mutate(tree.getroot())
    ET.indent(tree, space="    ")
    FLEXI_DST.mkdir(parents=True, exist_ok=True)
    tree.write(FLEXI_DST / f"{name}.flexipage-meta.xml", encoding="UTF-8", xml_declaration=True)
    print(f"  {name}: {added or 'sin cambios'}")


def main():
    print("Layouts:")
    process_layout("Case-Case Layout",
                   lambda r: insert_after_field(r, "AccountId", ["AssetId", "ProductId"]))
    process_layout("Asset-Asset Layout",
                   lambda r: insert_after_field(r, "Product2Id", ["ParentId"])
                   + append_layout_section(r, *COMEXI_ASSET_SECTION))

    print("Flexipages:")
    process_flexipage("RLM_Case_Record_Page",
                      lambda r: flexi_insert_after(r, "AccountId", ["AssetId", "ProductId"]))
    process_flexipage("RLM_Asset_Record_Page",
                      lambda r: flexi_insert_after(r, "Product2Id", ["ParentId"])
                      + flexi_add_section(r, *COMEXI_ASSET_SECTION, tag="asset"))


if __name__ == "__main__":
    main()
