#!/usr/bin/env python3
"""Aprovisiona la descomposicion DRO del retrofit COMEXI.

Toda la configuracion de descomposicion es *datos*, no metadata: Product2,
ProductFulfillmentDecompRule, FulfillmentStepDefinitionGroup, FulfillmentStepDefinition,
FulfillmentStepDependencyDef, ProductFulfillmentScenario y FulfillmentWorkspace no se
pueden desplegar con sf project deploy. Se crean por REST y el script es idempotente,
asi que se reejecuta despues de cada build igual que provision_clm_clauses.py.

COMO DESCOMPONE LA PLATAFORMA (el modelo cuesta un rato entenderlo)

  1. El producto vendible lleva DecompositionScope: le dice a la plataforma a que
     nivel descomponer (Bundle o OrderLineItem).
  2. ProductFulfillmentDecompRule mapea producto vendible -> producto de fulfillment.
     El de fulfillment no se vende: existe solo para representar un destino.
  3. ProductFulfillmentScenario cuelga del producto de FULFILLMENT (no del vendible)
     y apunta al grupo de pasos. Aqui es donde se equivoca todo el mundo.
  4. Al activar el pedido, el flow RLM_Submit_Order_on_Activation llama a submitOrder,
     la plataforma resuelve las reglas y genera FulfillmentPlan con sus pasos.

Sin el paso 3 el plan nace vacio y se completa al instante: es exactamente lo que
pasaba en esta org antes de este script.

TRES DESTINOS, UNA DEPENDENCIA QUE MANDA

El pedido del retrofit se rompe en material a SAP, intervencion a operaciones y
anticipo a finanzas. La dependencia que sostiene la escena es que el arranque de
ingenieria depende del cobro del anticipo: es la regla que hoy en COMEXI vive en
correos y aqui la hace cumplir la plataforma.

Detalle deliberado: planificar la intervencion NO depende del cobro. Operaciones
puede reservar la ventana mientras finanzas espera el dinero; lo que no puede
arrancar es ingenieria. Es la diferencia entre bloquear y ordenar.

Uso:
    python3 scripts/comexi/provision_dro_retrofit.py --org comexi
    python3 scripts/comexi/provision_dro_retrofit.py --org comexi --dry-run
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request

API = "v66.0"

# Productos de fulfillment: SKU -> (nombre, grupo de pasos, orden en el workspace)
FULFILLMENT_PRODUCTS = {
    "COMEXI-DRO-MAT": ("Material y codigos a SAP", "COMEXI Material y SAP", 1),
    "COMEXI-DRO-OPS": ("Intervencion en planta", "COMEXI Intervencion en planta", 2),
    "COMEXI-DRO-FIN": ("Anticipo y facturacion", "COMEXI Finanzas", 3),
}

WORKSPACE_NAME = "COMEXI Retrofit"

# Alcance de descomposicion de los productos que se venden. Los EXP-* quedan fuera
# a proposito: un billete de avion no se descompone en nada, se factura.
SOURCE_SCOPES = {
    "T100": "Bundle",
    "T100-W11": "OrderLineItem",
    "T100-TEMP": "OrderLineItem",
    "SRV-MEC": "OrderLineItem",
    "SRV-ELE": "OrderLineItem",
    "SRV-PME": "OrderLineItem",
}

# Reglas de descomposicion: (nombre, SKU vendible, SKU de fulfillment).
# El T100 va a dos destinos porque un retrofit mueve material y dinero a la vez.
DECOMP_RULES = [
    ("Retrofit T100 a material", "T100", "COMEXI-DRO-MAT"),
    ("Retrofit T100 a finanzas", "T100", "COMEXI-DRO-FIN"),
    ("Windows 11 a material", "T100-W11", "COMEXI-DRO-MAT"),
    ("Control de temperatura a material", "T100-TEMP", "COMEXI-DRO-MAT"),
    ("Montaje mecanico a intervencion", "SRV-MEC", "COMEXI-DRO-OPS"),
    ("Instalacion electrica a intervencion", "SRV-ELE", "COMEXI-DRO-OPS"),
    ("Puesta en marcha a intervencion", "SRV-PME", "COMEXI-DRO-OPS"),
]

# Pasos del plan: (nombre, grupo, StepType).
# Ninguno es Callout: la org no tiene endpoint de SAP vivo y un Callout contra un
# endpoint muerto acaba en fallout y arruina la pantalla. El dia que haya endpoint,
# basta cambiar StepType a Callout y poner IntegrationDefinitionNameId.
STEPS = [
    ("Enviar codigos de material a SAP", "COMEXI Material y SAP", "ManualTask"),
    ("Confirmar material en fabrica", "COMEXI Material y SAP", "Milestone"),
    ("Emitir hito de anticipo (30%)", "COMEXI Finanzas", "Milestone"),
    ("Confirmar cobro del anticipo", "COMEXI Finanzas", "ManualTask"),
    ("Facturar el saldo a la aceptacion", "COMEXI Finanzas", "ManualTask"),
    ("Planificar intervencion en planta", "COMEXI Intervencion en planta", "ManualTask"),
    ("Arranque de ingenieria", "COMEXI Intervencion en planta", "ManualTask"),
    ("Montaje mecanico e instalacion electrica", "COMEXI Intervencion en planta", "ManualTask"),
    ("Puesta en marcha y aceptacion", "COMEXI Intervencion en planta", "Milestone"),
]

# Dependencias: (nombre, paso que espera, paso del que depende).
# La segunda es la que sostiene la escena 11.
DEPENDENCIES = [
    ("Material antes de fabrica", "Confirmar material en fabrica", "Enviar codigos de material a SAP"),
    ("Anticipo antes de ingenieria", "Arranque de ingenieria", "Confirmar cobro del anticipo"),
    ("Hito antes del cobro", "Confirmar cobro del anticipo", "Emitir hito de anticipo (30%)"),
    ("Ingenieria antes del montaje", "Montaje mecanico e instalacion electrica", "Arranque de ingenieria"),
    ("Montaje antes de la aceptacion", "Puesta en marcha y aceptacion", "Montaje mecanico e instalacion electrica"),
    ("Aceptacion antes del saldo", "Facturar el saldo a la aceptacion", "Puesta en marcha y aceptacion"),
]

# Codigos de material que viajan a SAP. Salen del catalogo real del retrofit.
SAP_MATERIAL_CODES = {
    "T100": "SAP-T100-UPDPC",
    "T100-W11": "SAP-W11-LIC",
    "T100-TEMP": "SAP-TEMP-TINTA",
    "T100-CPU-SIM": "SAP-CPU-SIMOTION",
    "T100-CU-SIN": "SAP-CU-SINAMICS",
    "T100-HMI": "SAP-PUPITRE-HMI",
    "T100-SCREEN": "SAP-PANTALLA-HMI",
}


class Org:
    """Acceso REST a la org resolviendo el token con el CLI, sin loguearlo."""

    def __init__(self, alias: str, dry_run: bool) -> None:
        proc = subprocess.run(
            ["sf", "org", "display", "--target-org", alias, "--json"],
            capture_output=True,
            text=True,
        )
        if proc.returncode != 0:
            sys.exit(f"No pude leer la org {alias}: {proc.stderr.strip()}")
        result = json.loads(proc.stdout)["result"]
        self.token = result["accessToken"]
        self.url = result["instanceUrl"]
        self.username = result["username"]
        self.dry_run = dry_run

    def _call(self, method: str, path: str, payload=None):
        req = urllib.request.Request(
            f"{self.url}/services/data/{API}{path}",
            data=json.dumps(payload).encode("utf-8") if payload is not None else None,
            method=method,
        )
        req.add_header("Authorization", f"Bearer {self.token}")
        req.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(req) as resp:
                body = resp.read().decode("utf-8")
                return json.loads(body) if body else {}
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode("utf-8")
            raise RuntimeError(f"{method} {path} -> {exc.code}: {detail}") from None

    def query(self, soql: str):
        return self._call("GET", "/query/?q=" + urllib.parse.quote(soql)).get("records", [])

    def create(self, sobject: str, data: dict) -> str:
        if self.dry_run:
            print(f"    [dry-run] CREATE {sobject} {data.get('Name', '')}")
            return "000000000000000AAA"
        return self._call("POST", f"/sobjects/{sobject}", data)["id"]

    def patch(self, sobject: str, record_id: str, data: dict) -> None:
        if self.dry_run:
            print(f"    [dry-run] PATCH {sobject}/{record_id} {data}")
            return
        self._call("PATCH", f"/sobjects/{sobject}/{record_id}", data)


def skus_to_ids(org: Org, skus) -> dict[str, str]:
    quoted = ", ".join(f"'{s}'" for s in skus)
    return {
        r["StockKeepingUnit"]: r["Id"]
        for r in org.query(
            f"SELECT Id, StockKeepingUnit FROM Product2 WHERE StockKeepingUnit IN ({quoted})"
        )
    }


def ensure_fulfillment_products(org: Org) -> dict[str, str]:
    """Los productos de fulfillment representan destinos, no cosas que se venden."""
    print("Productos de fulfillment")
    ids = skus_to_ids(org, FULFILLMENT_PRODUCTS)

    for sku, (name, _group, _order) in FULFILLMENT_PRODUCTS.items():
        if sku in ids:
            print(f"  Ya existe: {sku}")
            continue
        ids[sku] = org.create(
            "Product2",
            {
                "Name": name,
                "StockKeepingUnit": sku,
                # ProductClass no se asigna: la plataforma lo deriva y rechaza el
                # insert si se envia. Sin configuracion de bundle sale Simple, que
                # es lo que necesita un destino de fulfillment.
                "IsActive": True,
                # Order y no Custom: se quiere un destino por pedido, no uno por
                # linea ni por grupo. Custom obligaria a registrar antes un
                # CustomFulfillmentScopeCnfg y falla con "Select a valid Custom
                # Decomposition Scope" si no existe; Order no depende de nada.
                "DecompositionScope": "Order",
                # Obligatorio con scope Order: la plataforma rechaza el insert con
                # "Products with a decomposition scope of Order aren't assetized".
                # Y es lo correcto: estos productos son destinos internos, el activo
                # del cliente es la maquina MSC000600, no un tramite de SAP.
                "IsAssetizable": False,
                "FulfillmentQtyCalcMethod": "AlwaysOne",
                "Family": "Serveis",
            },
        )
        print(f"  Creado: {sku} - {name}")
    return ids


def stamp_source_scopes(org: Org) -> dict[str, str]:
    print("Alcance de descomposicion en los productos vendibles")
    ids = skus_to_ids(org, SOURCE_SCOPES)
    missing = set(SOURCE_SCOPES) - set(ids)
    if missing:
        sys.exit(f"Faltan productos del catalogo COMEXI: {sorted(missing)}")

    quoted = ", ".join(f"'{s}'" for s in SOURCE_SCOPES)
    current = {
        r["StockKeepingUnit"]: r.get("DecompositionScope")
        for r in org.query(
            "SELECT StockKeepingUnit, DecompositionScope FROM Product2 "
            f"WHERE StockKeepingUnit IN ({quoted})"
        )
    }
    for sku, scope in SOURCE_SCOPES.items():
        if current.get(sku) == scope:
            print(f"  Ya marcado {sku}: {scope}")
            continue
        org.patch("Product2", ids[sku], {"DecompositionScope": scope})
        print(f"  {sku} -> {scope}")
    return ids


def stamp_sap_codes(org: Org) -> None:
    """El paso de SAP no dice nada si el material no lleva codigo."""
    print("Codigos de material para SAP")
    ids = skus_to_ids(org, SAP_MATERIAL_CODES)
    for sku, code in SAP_MATERIAL_CODES.items():
        if sku not in ids:
            print(f"  No esta en el catalogo, lo salto: {sku}")
            continue
        org.patch("Product2", ids[sku], {"COMEXI_SAP_Material_Code__c": code})
        print(f"  {sku} -> {code}")


def ensure_groups(org: Org) -> dict[str, str]:
    print("Grupos de pasos")
    names = {group for _n, group, _o in FULFILLMENT_PRODUCTS.values()}
    quoted = ", ".join(f"'{n}'" for n in names)
    ids = {
        r["Name"]: r["Id"]
        for r in org.query(
            f"SELECT Id, Name FROM FulfillmentStepDefinitionGroup WHERE Name IN ({quoted})"
        )
    }
    for name in sorted(names):
        if name in ids:
            print(f"  Ya existe: {name}")
            continue
        ids[name] = org.create(
            "FulfillmentStepDefinitionGroup",
            {"Name": name, "UsageType": "Fulfillment"},
        )
        print(f"  Creado: {name}")
    return ids


def ensure_steps(org: Org, groups: dict[str, str], assigned_to: str) -> dict[str, str]:
    print("Pasos del plan")
    group_ids = ", ".join(f"'{i}'" for i in groups.values())
    ids = {
        r["Name"]: r["Id"]
        for r in org.query(
            "SELECT Id, Name FROM FulfillmentStepDefinition "
            f"WHERE StepDefinitionGroupId IN ({group_ids})"
        )
    }
    for name, group, step_type in STEPS:
        if name in ids:
            print(f"  Ya existe: {name}")
            continue
        ids[name] = org.create(
            "FulfillmentStepDefinition",
            {
                "Name": name,
                "StepDefinitionGroupId": groups[group],
                "StepType": step_type,
                # Plan y no LineItem: se quiere un paso por pedido, no uno por linea.
                # Con LineItem, las tres lineas de intervencion darian tres montajes.
                "Scope": "Plan",
                "UsageType": "Fulfillment",
                "IsSkipBranch": False,
                "ForcePlanFreezeDuringExecution": "Never",
                "AssignedToId": assigned_to,
            },
        )
        print(f"  Creado ({step_type}): {name}")
    return ids


def ensure_dependencies(org: Org, steps: dict[str, str]) -> None:
    print("Dependencias entre pasos")
    step_ids = ", ".join(f"'{i}'" for i in steps.values())
    existing = {
        (r["FulfillmentStepDefinitionId"], r["DependsOnStepDefinitionId"])
        for r in org.query(
            "SELECT FulfillmentStepDefinitionId, DependsOnStepDefinitionId "
            f"FROM FulfillmentStepDependencyDef WHERE FulfillmentStepDefinitionId IN ({step_ids})"
        )
    }
    for name, waiting, depends_on in DEPENDENCIES:
        key = (steps[waiting], steps[depends_on])
        if key in existing:
            print(f"  Ya existe: {name}")
            continue
        org.create(
            "FulfillmentStepDependencyDef",
            {
                "Name": name,
                "FulfillmentStepDefinitionId": steps[waiting],
                "DependsOnStepDefinitionId": steps[depends_on],
                # Plan y no LineItem: asi la dependencia cruza grupos, que es lo que
                # hace falta para que ingenieria (Intervencion) espere a finanzas.
                "DependencyScope": "Plan",
                "IsCompensateInReverse": False,
            },
        )
        print(f"  Creada: {name}")


def ensure_scenarios(org: Org, products: dict[str, str], groups: dict[str, str]) -> None:
    """El escenario cuelga del producto de fulfillment, no del vendible."""
    print("Escenarios de fulfillment")
    product_ids = ", ".join(f"'{i}'" for i in products.values())
    existing = {
        r["ProductId"]
        for r in org.query(
            f"SELECT ProductId FROM ProductFulfillmentScenario WHERE ProductId IN ({product_ids})"
        )
    }
    for sku, (name, group, _order) in FULFILLMENT_PRODUCTS.items():
        if products[sku] in existing:
            print(f"  Ya existe: {sku}")
            continue
        org.create(
            "ProductFulfillmentScenario",
            {
                "Name": f"{name} ({sku})",
                "ProductId": products[sku],
                "FulfillmentStepDefnGroupId": groups[group],
                "Action": "Add;Amend;Renew;No Change;Cancel",
                "UsageType": "Fulfillment",
            },
        )
        print(f"  Creado: {sku} -> {group}")


def ensure_decomp_rules(org: Org, sources: dict[str, str], targets: dict[str, str]) -> None:
    print("Reglas de descomposicion")
    names = ", ".join(f"'{n}'" for n, _s, _d in DECOMP_RULES)
    existing = {
        r["Name"]
        for r in org.query(
            f"SELECT Name FROM ProductFulfillmentDecompRule WHERE Name IN ({names})"
        )
    }
    for name, source_sku, dest_sku in DECOMP_RULES:
        if name in existing:
            print(f"  Ya existe: {name}")
            continue
        org.create(
            "ProductFulfillmentDecompRule",
            {
                "Name": name,
                "SourceProductId": sources[source_sku],
                "DestinationProductId": targets[dest_sku],
            },
        )
        print(f"  Creada: {name}")


def ensure_workspace(org: Org, groups: dict[str, str]) -> None:
    """El workspace es la bandeja donde operaciones ve el trabajo agrupado."""
    print("Workspace de operaciones")
    existing = org.query(
        f"SELECT Id FROM FulfillmentWorkspace WHERE Name = '{WORKSPACE_NAME}'"
    )
    if existing:
        workspace_id = existing[0]["Id"]
        print(f"  Ya existe: {WORKSPACE_NAME}")
    else:
        workspace_id = org.create("FulfillmentWorkspace", {"Name": WORKSPACE_NAME})
        print(f"  Creado: {WORKSPACE_NAME}")

    linked = {
        r["FulfillmentStepDefinitionGroupId"]
        for r in org.query(
            "SELECT FulfillmentStepDefinitionGroupId FROM FulfillmentWorkspaceItem "
            f"WHERE FulfillmentWorkspaceId = '{workspace_id}'"
        )
    }
    for _sku, (_name, group, order) in sorted(
        FULFILLMENT_PRODUCTS.items(), key=lambda kv: kv[1][2]
    ):
        if groups[group] in linked:
            print(f"  Ya enlazado: {group}")
            continue
        org.create(
            "FulfillmentWorkspaceItem",
            {
                "FulfillmentWorkspaceId": workspace_id,
                "FulfillmentStepDefinitionGroupId": groups[group],
                "ShowOrder": order,
            },
        )
        print(f"  Enlazado: {group}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--org", required=True, help="Alias o username de la org")
    parser.add_argument("--dry-run", action="store_true", help="No escribe nada")
    args = parser.parse_args()

    org = Org(args.org, args.dry_run)
    print(f"Org: {org.username}{' (dry-run)' if args.dry_run else ''}\n")

    me = org.query("SELECT Id FROM User WHERE Username = '" + org.username + "'")
    if not me:
        sys.exit("No pude resolver el usuario de la org para asignar los pasos.")
    assigned_to = me[0]["Id"]

    targets = ensure_fulfillment_products(org)
    print()
    sources = stamp_source_scopes(org)
    print()
    stamp_sap_codes(org)
    print()
    groups = ensure_groups(org)
    print()
    steps = ensure_steps(org, groups, assigned_to)
    print()
    ensure_dependencies(org, steps)
    print()
    ensure_scenarios(org, targets, groups)
    print()
    ensure_decomp_rules(org, sources, targets)
    print()
    ensure_workspace(org, groups)

    print(
        f"\nListo: {len(STEPS)} pasos en {len(groups)} grupos, "
        f"{len(DEPENDENCIES)} dependencias y {len(DECOMP_RULES)} reglas."
    )
    print("Ingenieria queda bloqueada hasta completar 'Confirmar cobro del anticipo'.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
