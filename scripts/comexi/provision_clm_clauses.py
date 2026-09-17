#!/usr/bin/env python3
"""Aprovisiona la biblioteca de clausulas CLM de la demo COMEXI.

DocumentClauseSet, DocumentClause y DocumentAuthoredContent son *datos*, no
metadata: no hay forma de desplegarlos con sf project deploy. Este script los
crea por REST y es idempotente, asi que se puede reejecutar tras cada build.

Orden obligatorio (guia CLM de Revenue Cloud):
  ClauseCatgConfiguration  -> metadata, va en unpackaged/post_comexi
  DocumentClauseSet        -> aqui
  DocumentClause           -> aqui, siempre en Draft y luego Active
  DocumentAuthoredContent  -> aqui, es lo que alimenta "Associated Clauses"

Dos trampas que cuestan una tarde si se olvidan:

  * `DocumentClauseSet.Category` es un picklist restringido cuyos valores son
    IDs de ClauseCatgConfiguration de **15 caracteres**. Con el ID de 18 falla
    con "bad value for restricted picklist".
  * `DefaultLanguage` es obligatorio de facto: la pestana Document Clause Sets
    agrupa por Category x DefaultLanguage y **oculta en silencio** los sets sin
    idioma. Ademas Salesforce bloquea el UPDATE de Status y DefaultLanguage una
    vez creado el set, asi que arreglarlo obliga a borrar y recrear.

Las seis clausulas salen del Discovery de COMEXI (Reverse Demo del 4 ago 2026).
No hay propiedad intelectual, fuerza mayor ni jurisdiccion porque el Discovery
no las menciona y no se inventan clausulas legales para una demo.

Uso:
    python3 scripts/comexi/provision_clm_clauses.py --org comexi
    python3 scripts/comexi/provision_clm_clauses.py --org comexi --dry-run
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

API = "v66.0"

CATEGORY_DEVELOPER_NAME = "COMEXI_Retrofit"
CLAUSE_SET_NAME = "Condiciones Retrofit"
LANGUAGE = "es"
TEMPLATE_NAME = "COMEXI_Contrato_Retrofit"

# Cifras del escenario: oferta 00000049 de Roberts Mart Co Ltd.
# Si el advisor regenera la oferta con otros importes hay que actualizarlas
# aqui y volver a ejecutar, igual que con build_comexi_retrofit_proposal.py.
TOTAL = "15.322,18 EUR"
DOWN_PAYMENT = "4.596,65 EUR"
BALANCE = "10.725,53 EUR"

CLAUSES = [
    (
        "Precio y exclusiones",
        [
            f"El precio del presente contrato asciende a {TOTAL}, impuestos no incluidos, "
            "y comprende exclusivamente el alcance descrito en el apartado de alcance de la "
            "intervencion.",
            "Quedan expresamente excluidos y a cargo del comprador la obra civil y las "
            "adaptaciones de la instalacion existente, los suministros electricos y neumaticos "
            "hasta el punto de conexion, la retirada y gestion de los elementos sustituidos y "
            "los medios de elevacion en planta.",
            "Cualquier ampliacion del alcance solicitada por el comprador con posterioridad a "
            "la firma sera objeto de oferta independiente.",
        ],
    ),
    (
        "Condiciones de pago",
        [
            f"El comprador abonara un anticipo del 30% del precio del contrato, equivalente a "
            f"{DOWN_PAYMENT}, a la firma del presente documento.",
            f"El saldo restante, {BALANCE}, se abonara a 30 dias fecha factura una vez emitida "
            "el acta de aceptacion de la intervencion.",
            "La recepcion del anticipo es condicion para el arranque de los trabajos de "
            "ingenieria y para la reserva de materiales. Comexi no iniciara el diseno "
            "definitivo ni la compra de componentes hasta la confirmacion del cobro.",
        ],
    ),
    (
        "Garantia",
        [
            "Comexi garantiza los componentes suministrados y los trabajos ejecutados durante "
            "un periodo de seis meses.",
            "El computo de la garantia se inicia en la fecha de aceptacion de la intervencion, "
            "no en la fecha de entrega del material ni en la de firma del presente contrato.",
            "La garantia cubre la sustitucion de los componentes defectuosos y la mano de obra "
            "necesaria para su reemplazo. No cubre los danos derivados de un uso distinto del "
            "previsto, de modificaciones realizadas por terceros sin autorizacion de Comexi o "
            "de la falta de mantenimiento preventivo.",
        ],
    ),
    (
        "Instalacion y puesta en marcha",
        [
            "La intervencion se ejecutara en la planta del comprador en Leeds (United Kingdom) "
            "sobre la maquina MSC000600 y comprende 36 horas de trabajo: 16 de montaje "
            "mecanico, 12 de instalacion electrica y 8 de puesta en marcha de software, con "
            "las pruebas de aplicacion correspondientes.",
            "Los gastos de desplazamiento y estancia del personal tecnico de Comexi van a "
            "cargo de Comexi.",
            "El comprador pondra la maquina a disposicion de Comexi, libre de produccion, "
            "durante toda la ventana de intervencion acordada, y facilitara el acceso a la "
            "instalacion y los medios de elevacion necesarios.",
        ],
    ),
    (
        "Plazo de entrega",
        [
            "La ventana de intervencion comprometida es de seis semanas desde la confirmacion "
            "del anticipo, con fecha objetivo de intervencion el 26 de octubre de 2026.",
            "El plazo queda condicionado a la recepcion del anticipo y a la disponibilidad de "
            "la maquina en la fecha acordada.",
            "Cualquier reprogramacion solicitada por el comprador con menos de quince dias de "
            "antelacion podra desplazar la fecha de intervencion en funcion de la ocupacion "
            "del calendario de operaciones de Comexi.",
        ],
    ),
    (
        "Confidencialidad",
        [
            "Las partes se obligan a mantener la confidencialidad de toda la informacion "
            "tecnica, comercial y de proceso a la que accedan con ocasion del presente "
            "contrato.",
            "La obligacion alcanza a los planos, esquemas electricos, parametros de proceso y "
            "configuraciones de software intercambiados durante la intervencion, y subsiste "
            "durante los dos anos siguientes a la finalizacion de los trabajos.",
            "Ninguna de las partes podra difundir el contenido economico del presente contrato "
            "sin autorizacion escrita de la otra.",
        ],
    ),
]


def clause_html(paragraphs: list[str]) -> str:
    return "".join(f"<p>{p}</p>" for p in paragraphs)


def clause_text(paragraphs: list[str]) -> str:
    return "\n".join(paragraphs)


class Org:
    def __init__(self, alias: str, dry_run: bool = False):
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
        path = "/query/?q=" + urllib.parse.quote(soql)
        return self._call("GET", path).get("records", [])

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


def ensure_clause_set(org: Org) -> str:
    categories = org.query(
        "SELECT Id FROM ClauseCatgConfiguration "
        f"WHERE DeveloperName = '{CATEGORY_DEVELOPER_NAME}'"
    )
    if not categories:
        sys.exit(
            f"Falta la categoria {CATEGORY_DEVELOPER_NAME}. Despliega antes "
            "unpackaged/post_comexi/clauseCatgConfigurations."
        )
    # Restricted picklist: exige el ID de 15 caracteres, no el de 18.
    category_15 = categories[0]["Id"][:15]

    existing = org.query(
        f"SELECT Id, DefaultLanguage FROM DocumentClauseSet WHERE Name = '{CLAUSE_SET_NAME}'"
    )
    if existing:
        record = existing[0]
        if record["DefaultLanguage"] != LANGUAGE:
            sys.exit(
                f"El clause set '{CLAUSE_SET_NAME}' existe con idioma "
                f"{record['DefaultLanguage']}. Salesforce no deja cambiarlo: borralo "
                "junto con sus clausulas y vuelve a ejecutar."
            )
        print(f"  Clause set ya existe: {record['Id']}")
        return record["Id"]

    set_id = org.create(
        "DocumentClauseSet",
        {
            "Name": CLAUSE_SET_NAME,
            "Category": category_15,
            "DefaultLanguage": LANGUAGE,
        },
    )
    print(f"  Clause set creado: {set_id}")
    return set_id


def ensure_clauses(org: Org, set_id: str) -> dict[str, str]:
    existing = {
        r["Name"]: r
        for r in org.query(
            "SELECT Id, Name, Status FROM DocumentClause "
            f"WHERE DocumentClauseSetId = '{set_id}'"
        )
    }
    ids: dict[str, str] = {}

    for name, paragraphs in CLAUSES:
        if name in existing:
            record = existing[name]
            ids[name] = record["Id"]
            print(f"  Clausula ya existe ({record['Status']}): {name}")
            continue

        clause_id = org.create(
            "DocumentClause",
            {
                "Name": name,
                "Content": clause_html(paragraphs),
                "Format": "Rich_Text",
                "DocumentClauseSetId": set_id,
                "Status": "Draft",  # solo se puede crear en Draft
                "Version": 1,
                "Language": LANGUAGE,
            },
        )
        org.patch("DocumentClause", clause_id, {"Status": "Active"})
        ids[name] = clause_id
        print(f"  Clausula creada y activada: {name}")
        time.sleep(0.2)

    return ids


def ensure_authored_content(org: Org, clause_ids: dict[str, str]) -> None:
    templates = org.query(
        "SELECT Id FROM DocumentTemplate "
        f"WHERE Name = '{TEMPLATE_NAME}' AND IsActive = true LIMIT 1"
    )
    if not templates:
        print(
            f"  AVISO: no hay ningun {TEMPLATE_NAME} activo. Despliega el template y "
            "ejecuta activate_comexi_docgen_template antes de asociar las clausulas."
        )
        return
    template_id = templates[0]["Id"]

    linked = {
        r["StandardContentObjectId"]
        for r in org.query(
            "SELECT StandardContentObjectId FROM DocumentAuthoredContent "
            f"WHERE ReferenceObjectId = '{template_id}'"
        )
    }

    for name, clause_id in clause_ids.items():
        if clause_id in linked:
            print(f"  Ya asociada al template: {name}")
            continue
        org.create(
            "DocumentAuthoredContent",
            {
                "ReferenceObjectId": template_id,
                "ReferenceObjectRecordType": "DocumentTemplate",
                "ContentType": "StandardDocumentClause",
                "StandardContentObjectType": "DocumentClause",
                "StandardContentObjectId": clause_id,
                "DocAuthoredContentIdentifier": f"{int(time.time() * 1000)}-{clause_id[-6:]}",
                "ContentGenerationSource": "StandardContent",
                "IsReviewed": False,
                "IsLibraryAdditionRequested": False,
            },
        )
        print(f"  Asociada al template: {name}")
        time.sleep(0.2)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--org", default="comexi", help="Alias de la org (default: comexi)")
    parser.add_argument("--dry-run", action="store_true", help="No escribe nada")
    args = parser.parse_args()

    org = Org(args.org, dry_run=args.dry_run)

    print("Clause set")
    set_id = ensure_clause_set(org)
    print("Clausulas")
    clause_ids = ensure_clauses(org, set_id)
    print("Associated Clauses del template")
    ensure_authored_content(org, clause_ids)
    print(f"\nListo: {len(clause_ids)} clausulas en '{CLAUSE_SET_NAME}'.")


if __name__ == "__main__":
    main()
