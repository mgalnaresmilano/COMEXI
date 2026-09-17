#!/usr/bin/env python3
"""Amplia la UI del Asset: 4 secciones COMEXI y los dos LWC de la escena 01.

Continua lo que empezo 13_escena01_ui.py, que creo la seccion "Ficha tecnica de
la maquina". Aqui se le anaden los 6 campos nuevos y se crean las 3 secciones
restantes (obsolescencia, servicio, retrofit), mas los dos componentes de la
escena 01 en la region principal de la flexipage.

A diferencia de los scripts 11/18/20/21, la fuente es unpackaged/post_comexi, no
post_ux: los ficheros de Asset ya estan parcheados por 13_escena01_ui.py y leer
post_ux borraria la seccion que ese script creo. Por eso origen y destino son el
mismo fichero y todo el script es idempotente: relanzarlo no duplica nada.

El detalle de un registro se renderiza por dos caminos que conviven en esta org y
hay que tocar los dos:

  - Page layout, cuando la Lightning page usa force:detailPanel.
  - flexipage:fieldSection con campos fijos, que ignora por completo el layout.

Uso:
    python3 scripts/apex/comexi/22_add_comexi_asset_sections.py
"""

import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

NS = "http://soap.sforce.com/2006/04/metadata"
REPO = Path(__file__).resolve().parents[3]
LAYOUT = REPO / "unpackaged/post_comexi/layouts/Asset-Asset Layout.layout-meta.xml"
FLEXI = REPO / "unpackaged/post_comexi/flexipages/RLM_Asset_Record_Page.flexipage-meta.xml"

# Seccion que ya existe y a la que solo se le anaden campos.
TECH_LABEL = "COMEXI: Ficha tecnica de la maquina"
TECH_SECTION_IDENTIFIER = "comexi_fieldSection_asset"
TECH_EXTRA_C1 = [
    "COMEXI_Machine_Age_Years__c",
    "COMEXI_Control_System__c",
    "COMEXI_SAP_Equipment_Code__c",
]
TECH_EXTRA_C2 = [
    "COMEXI_Web_Width_mm__c",
    "COMEXI_Stations__c",
    "COMEXI_Max_Speed_Mpm__c",
]

# (tag de facet, etiqueta, columna 1, columna 2). El tag genera los identificadores
# de la flexipage, asi que tiene que ser estable entre ejecuciones.
NEW_SECTIONS = [
    (
        "asset_obs",
        "COMEXI: Obsolescencia y viabilidad",
        [
            "COMEXI_OS_Installed__c",
            "COMEXI_OS_Support_End__c",
            "COMEXI_Obsolete_Component__c",
            "COMEXI_Obsolescence_Risk__c",
        ],
        [
            "COMEXI_Retrofit_Eligible__c",
            "COMEXI_Requires_Engineering__c",
            "COMEXI_Recommended_Retrofit_SKU__c",
        ],
    ),
    (
        "asset_svc",
        "COMEXI: Servicio e historico",
        [
            "COMEXI_Service_Level__c",
            "COMEXI_Last_Intervention_Date__c",
            "COMEXI_Intervention_Count__c",
        ],
        [
            "COMEXI_Operating_Hours__c",
            "COMEXI_Service_Revenue_Lifetime__c",
            "COMEXI_Open_Cases__c",
        ],
    ),
    (
        "asset_rtf",
        "COMEXI: Retrofit y emplazamiento",
        ["COMEXI_Site_Location__c", "COMEXI_Retrofits_Applied__c"],
        ["COMEXI_Last_Retrofit_Date__c", "COMEXI_Retrofit_Potential_Value__c"],
    ),
]

# Las formulas van en Readonly: declararlas editables rompe el despliegue del layout.
READ_ONLY = {"COMEXI_Machine_Age_Years__c"}

# Escena 01, en orden de lectura: primero la alerta del caso abierto, despues la
# ficha visual de la maquina, y solo entonces el tabset con los detalles.
LWC_COMPONENTS = [
    ("comexiAssetCaseAlert", "c_comexiAssetCaseAlert"),
    ("comexiAssetMachineCard", "c_comexiAssetMachineCard"),
]
LWC_ANCHOR_IDENTIFIER = "flexipage_tabset"


def q(tag):
    return f"{{{NS}}}{tag}"


def sub(parent, tag, text=None):
    el = ET.SubElement(parent, q(tag))
    if text is not None:
        el.text = text
    return el


# --------------------------------------------------------------------------- #
# Page layout
# --------------------------------------------------------------------------- #

def layout_item(field):
    item = ET.Element(q("layoutItems"))
    sub(item, "behavior", "Readonly" if field in READ_ONLY else "Edit")
    sub(item, "field", field)
    return item


def build_layout_section(label, col1, col2):
    section = ET.Element(q("layoutSections"))
    sub(section, "customLabel", "true")
    sub(section, "detailHeading", "true")
    sub(section, "editHeading", "true")
    sub(section, "label", label)
    for fields in (col1, col2):
        column = sub(section, "layoutColumns")
        for field in fields:
            column.append(layout_item(field))
    sub(section, "style", "TwoColumnsTopToBottom")
    return section


def patch_layout():
    if not LAYOUT.exists():
        sys.exit(f"No existe {LAYOUT}. Ejecuta antes 13_escena01_ui.py.")

    ET.register_namespace("", NS)
    tree = ET.parse(LAYOUT)
    root = tree.getroot()
    existing_fields = {e.text for e in root.iter(q("field"))}
    changed = False

    # 1. Campos nuevos en la seccion que ya existe.
    tech_pos = None
    for idx, child in enumerate(list(root)):
        if child.tag != q("layoutSections"):
            continue
        label = child.find(q("label"))
        if label is None or label.text != TECH_LABEL:
            continue
        tech_pos = idx
        columns = child.findall(q("layoutColumns"))
        for column, extras in zip(columns, (TECH_EXTRA_C1, TECH_EXTRA_C2)):
            for field in extras:
                if field in existing_fields:
                    continue
                column.append(layout_item(field))
                existing_fields.add(field)
                changed = True
                print(f"  layout · {TECH_LABEL} += {field}")
        break

    if tech_pos is None:
        sys.exit(f"No se encontro la seccion '{TECH_LABEL}' en el layout.")

    # 2. Secciones nuevas, justo detras de la ficha tecnica.
    existing_labels = {
        s.find(q("label")).text
        for s in root.findall(q("layoutSections"))
        if s.find(q("label")) is not None
    }
    offset = 1
    for _tag, label, col1, col2 in NEW_SECTIONS:
        if label in existing_labels:
            print(f"  layout · '{label}' ya presente")
            continue
        c1 = [f for f in col1 if f not in existing_fields]
        c2 = [f for f in col2 if f not in existing_fields]
        if not c1 and not c2:
            print(f"  layout · '{label}': sus campos ya estan en el layout")
            continue
        root.insert(tech_pos + offset, build_layout_section(label, c1, c2))
        existing_fields.update(c1 + c2)
        offset += 1
        changed = True
        print(f"  layout · seccion anadida: {label}")

    if not changed:
        print("  layout · sin cambios")
        return

    ET.indent(tree, space="    ")
    tree.write(LAYOUT, encoding="UTF-8", xml_declaration=True)
    print(f"  layout · escrito {LAYOUT.name}")


# --------------------------------------------------------------------------- #
# Flexipage
# --------------------------------------------------------------------------- #

def field_identifier(api_name):
    return "Record" + re.sub(r"[^A-Za-z0-9]", "", api_name) + "Field"


def field_instance(api_name):
    item = ET.Element(q("itemInstances"))
    fi = sub(item, "fieldInstance")
    prop = sub(fi, "fieldInstanceProperties")
    sub(prop, "name", "uiBehavior")
    sub(prop, "value", "readonly" if api_name in READ_ONLY else "none")
    sub(fi, "fieldItem", f"Record.{api_name}")
    sub(fi, "identifier", field_identifier(api_name))
    return item


def component_instance(component_name, identifier):
    item = ET.Element(q("itemInstances"))
    ci = sub(item, "componentInstance")
    sub(ci, "componentName", component_name)
    sub(ci, "identifier", identifier)
    return item


def make_facet(name, items):
    region = ET.Element(q("flexiPageRegions"))
    for item in items:
        region.append(item)
    sub(region, "name", name)
    sub(region, "type", "Facet")
    return region


def column_instance(body_facet, identifier):
    item = ET.Element(q("itemInstances"))
    ci = sub(item, "componentInstance")
    prop = sub(ci, "componentInstanceProperties")
    sub(prop, "name", "body")
    sub(prop, "value", body_facet)
    sub(ci, "componentName", "flexipage:column")
    sub(ci, "identifier", identifier)
    return item


def field_section_instance(tag, label, cols_facet):
    item = ET.Element(q("itemInstances"))
    ci = sub(item, "componentInstance")
    for key, value in (("columns", cols_facet), ("horizontalAlignment", "false"), ("label", label)):
        prop = sub(ci, "componentInstanceProperties")
        sub(prop, "name", key)
        sub(prop, "value", value)
    sub(ci, "componentName", "flexipage:fieldSection")
    sub(ci, "identifier", f"comexi_fieldSection_{tag}")
    return item


def find_facet(root, name):
    for region in root.findall(q("flexiPageRegions")):
        region_name = region.find(q("name"))
        if region_name is not None and region_name.text == name:
            return region
    return None


def find_region_with_identifier(root, identifier):
    """Devuelve (region, indice del itemInstance) del componente con ese identifier."""
    for region in root.findall(q("flexiPageRegions")):
        for idx, item in enumerate(list(region)):
            ident = item.find(f"{q('componentInstance')}/{q('identifier')}")
            if ident is not None and ident.text == identifier:
                return region, idx
    return None, None


def patch_flexipage():
    if not FLEXI.exists():
        sys.exit(f"No existe {FLEXI}. Ejecuta antes 13_escena01_ui.py.")

    ET.register_namespace("", NS)
    tree = ET.parse(FLEXI)
    root = tree.getroot()
    existing_fields = {e.text for e in root.iter(q("fieldItem"))}
    changed = False

    # 1. Campos nuevos en los dos facets-columna que ya existen.
    for facet_name, extras in (
        ("Facet-comexi-asset-c1", TECH_EXTRA_C1),
        ("Facet-comexi-asset-c2", TECH_EXTRA_C2),
    ):
        facet = find_facet(root, facet_name)
        if facet is None:
            sys.exit(f"No se encontro el facet {facet_name} en la flexipage.")
        # Los itemInstances van antes de <name>/<type>, asi que se insertan por indice.
        insert_at = len([c for c in facet if c.tag == q("itemInstances")])
        for field in extras:
            if f"Record.{field}" in existing_fields:
                continue
            facet.insert(insert_at, field_instance(field))
            existing_fields.add(f"Record.{field}")
            insert_at += 1
            changed = True
            print(f"  flexipage · {facet_name} += {field}")

    # 2. Secciones nuevas detras de la ficha tecnica, en la pestana Detalles.
    detail_region, tech_idx = find_region_with_identifier(root, TECH_SECTION_IDENTIFIER)
    if detail_region is None:
        sys.exit(f"No se encontro el fieldSection '{TECH_SECTION_IDENTIFIER}'.")

    existing_sections = {
        e.text
        for e in root.iter(q("identifier"))
        if e.text and e.text.startswith("comexi_fieldSection_")
    }
    new_facets, offset = [], 1
    for tag, label, col1, col2 in NEW_SECTIONS:
        if f"comexi_fieldSection_{tag}" in existing_sections:
            print(f"  flexipage · '{label}' ya presente")
            continue
        columns = []
        for col_idx, fields in enumerate((col1, col2), start=1):
            pending = [f for f in fields if f"Record.{f}" not in existing_fields]
            if not pending:
                continue
            body = f"Facet-comexi-{tag}-c{col_idx}"
            new_facets.append(make_facet(body, [field_instance(f) for f in pending]))
            columns.append(column_instance(body, f"comexi_column_{tag}_c{col_idx}"))
            existing_fields.update(f"Record.{f}" for f in pending)
        if not columns:
            print(f"  flexipage · '{label}': sus campos ya estan declarados")
            continue
        cols_facet = f"Facet-comexi-{tag}-cols"
        new_facets.append(make_facet(cols_facet, columns))
        detail_region.insert(tech_idx + offset, field_section_instance(tag, label, cols_facet))
        offset += 1
        changed = True
        print(f"  flexipage · seccion anadida: {label}")

    # 3. Los dos LWC de la escena 01, encima del tabset de la region principal.
    main_region, anchor_idx = find_region_with_identifier(root, LWC_ANCHOR_IDENTIFIER)
    if main_region is None:
        sys.exit(f"No se encontro el componente ancla '{LWC_ANCHOR_IDENTIFIER}'.")
    for component_name, identifier in LWC_COMPONENTS:
        if identifier in {e.text for e in root.iter(q("identifier"))}:
            print(f"  flexipage · {component_name} ya presente")
            continue
        # Se inserta siempre en la posicion del ancla y se avanza: asi el orden de
        # LWC_COMPONENTS se respeta y el tabset queda debajo de los dos componentes.
        main_region.insert(anchor_idx, component_instance(component_name, identifier))
        anchor_idx += 1
        changed = True
        print(f"  flexipage · componente anadido: {component_name}")

    if not changed:
        print("  flexipage · sin cambios")
        return

    # Los facets nuevos van detras del ultimo, que es donde la plataforma los espera.
    last = max(i for i, c in enumerate(list(root)) if c.tag == q("flexiPageRegions"))
    for pos, facet in enumerate(new_facets):
        root.insert(last + 1 + pos, facet)

    ET.indent(tree, space="    ")
    tree.write(FLEXI, encoding="UTF-8", xml_declaration=True)
    print(f"  flexipage · escrito {FLEXI.name}")


def main():
    print("Asset-Asset Layout:")
    patch_layout()
    print("RLM_Asset_Record_Page:")
    patch_flexipage()


if __name__ == "__main__":
    main()
