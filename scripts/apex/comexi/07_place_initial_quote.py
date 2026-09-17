#!/usr/bin/env python3
"""07_place_initial_quote.py - Genera la Quote inicial del caso 174535.

Usa Place Sales Transaction (PST), el contrato verificado del repo
(scripts/txn_data_harness/lifecycle.py): POST connect/rev/sales-transaction/
actions/place con pricingPref=System, para que el motor de pricing calcule
netos y consuma el descuento. NUNCA DML directo sobre Quote/QuoteLineItem
(evita el banner naranja "prices aren't up to date").

Estructura (build-spec/04 y 08): 3 QuoteLineGroup - Producto / Intervencion /
Gastos. T100 con 5% de descuento -> objetivo 6.955,32 EUR / margen 27,54%.

Uso:
    python3 scripts/apex/comexi/07_place_initial_quote.py [--target-org comexi]
"""
import argparse
import json
import subprocess
import sys
import urllib.request

API = "67.0"


def org_auth(target: str):
    out = subprocess.run(
        ["sf", "org", "display", "--target-org", target, "--json"],
        capture_output=True, text=True, check=True,
    )
    res = json.loads(out.stdout)["result"]
    return res["accessToken"], res["instanceUrl"]


def rest(token, base, method, path, body=None):
    url = base + path
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", f"Bearer {token}")
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req) as r:
            return json.loads(r.read().decode() or "{}")
    except urllib.error.HTTPError as e:
        return {"_httpError": e.code, "body": e.read().decode()}


def soql(token, base, q):
    import urllib.parse
    path = f"/services/data/v{API}/query/?q={urllib.parse.quote(q)}"
    return rest(token, base, "GET", path).get("records", [])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--target-org", default="comexi")
    args = ap.parse_args()
    token, base = org_auth(args.target_org)

    # --- Resolver ids ---
    skus = ["T100", "T100-TEMP", "SRV-MEC", "SRV-ELE", "SRV-PME",
            "EXP-FLIGHT", "EXP-TAXI", "EXP-HOTEL", "EXP-MEAL"]
    in_clause = ",".join(f"'{s}'" for s in skus)
    prods = soql(token, base,
                 f"SELECT Id, StockKeepingUnit FROM Product2 WHERE StockKeepingUnit IN ({in_clause})")
    pid = {p["StockKeepingUnit"]: p["Id"] for p in prods}
    pbes = soql(token, base,
                "SELECT Id, Product2Id FROM PricebookEntry WHERE Product2Id IN "
                "(" + ",".join(f"'{p['Id']}'" for p in prods) + ") AND Pricebook2.IsStandard = true")
    pbe = {r["Product2Id"]: r["Id"] for r in pbes}
    std_pb = soql(token, base, "SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1")[0]["Id"]
    acc = soql(token, base, "SELECT Id FROM Account WHERE Name = 'Roberts Mart Co Ltd' LIMIT 1")[0]["Id"]
    rt = soql(token, base,
              "SELECT Id FROM RecordType WHERE SobjectType='Opportunity' AND DeveloperName='COMEXI_Retrofitting' LIMIT 1")
    rt_id = rt[0]["Id"] if rt else None

    # --- Opportunity (Retrofitting) ---
    # La Opportunity entra en el contexto de pricing de la Quote: si queda en la
    # moneda corporativa (USD) mientras la Quote va en EUR, el motor busca los PBE
    # en USD, no encuentra ninguno y falla con "Could not find product with ID: ...
    # from product details fetched from ProductDiscovery Service".
    opp_body = {
        "Name": "Roberts Mart - Retrofit T100 (Case 174535)",
        "AccountId": acc,
        "StageName": "Proposal/Quote",
        "CloseDate": "2026-12-31",
        "CurrencyIsoCode": "EUR",
        "Pricebook2Id": std_pb,
    }
    if rt_id:
        opp_body["RecordTypeId"] = rt_id
    existing_opp = soql(token, base,
                        "SELECT Id, CurrencyIsoCode, Pricebook2Id FROM Opportunity "
                        "WHERE Name = 'Roberts Mart - Retrofit T100 (Case 174535)' LIMIT 1")
    if existing_opp:
        opp_id = existing_opp[0]["Id"]
        # Una Opportunity creada antes de alinear la moneda se queda en USD y
        # arrastra la Quote al contexto equivocado, asi que la realineamos.
        if (existing_opp[0].get("CurrencyIsoCode") != "EUR"
                or not existing_opp[0].get("Pricebook2Id")):
            rest(token, base, "PATCH",
                 f"/services/data/v{API}/sobjects/Opportunity/{opp_id}",
                 {"CurrencyIsoCode": "EUR", "Pricebook2Id": std_pb})
            print(f"Opportunity {opp_id} realineada a EUR + Standard Price Book")
    else:
        r = rest(token, base, "POST", f"/services/data/v{API}/sobjects/Opportunity", opp_body)
        opp_id = r.get("id")
        if not opp_id:
            print("WARN: no se pudo crear Opportunity:", r)

    # --- Construir el grafo PST ---
    def line(ref, sku, group_ref, qty=1, discount=None):
        rec = {
            "attributes": {"method": "POST", "type": "QuoteLineItem"},
            "QuoteId": "@{refQuote.id}",
            "QuoteLineGroupId": group_ref,
            "Product2Id": pid[sku],
            "PricebookEntryId": pbe[pid[sku]],
            "Quantity": str(qty),
            "StartDate": "2026-08-14",
        }
        if discount is not None:
            rec["Discount"] = discount
        return {"referenceId": ref, "record": rec}

    def group(ref, name):
        return {"referenceId": ref, "record": {
            "attributes": {"method": "POST", "type": "QuoteLineGroup"},
            "QuoteId": "@{refQuote.id}", "Name": name}}

    # La moneda tiene que ser EUR en toda la cadena (usuario, PBE y quote): el
    # discovery y el pricing corren en la moneda por defecto del usuario, y un
    # desajuste deja la quote sin precio o rompe la linea por currency mismatch.
    quote_record = {
        "attributes": {"method": "POST", "type": "Quote"},
        "Name": "Oferta Retrofit T100 - Roberts Mart (174535)",
        "QuoteAccountId": acc,
        "Pricebook2Id": std_pb,
        "CurrencyIsoCode": "EUR",
        "Description": "Caso 174535 - Actualitzem oferta W11",
    }
    if opp_id:
        quote_record["OpportunityId"] = opp_id

    records = [
        {"referenceId": "refQuote", "record": quote_record},
        group("refGProducto", "Producto"),
        group("refGInterv", "Intervencion"),
        group("refGGastos", "Gastos"),
        # Producto: bundle T100 con 5% de descuento + add-on tinta (linea separada)
        line("refL_T100", "T100", "@{refGProducto.id}", 1, discount=5),
        line("refL_TEMP", "T100-TEMP", "@{refGProducto.id}", 1),
        # Intervencion: horas de servicio
        line("refL_MEC", "SRV-MEC", "@{refGInterv.id}", 16),
        line("refL_ELE", "SRV-ELE", "@{refGInterv.id}", 12),
        line("refL_PME", "SRV-PME", "@{refGInterv.id}", 8),
        # Gastos (a carrec de, total ~2420)
        line("refL_FLIGHT", "EXP-FLIGHT", "@{refGGastos.id}", 1),
        line("refL_TAXI", "EXP-TAXI", "@{refGGastos.id}", 1),
        line("refL_HOTEL", "EXP-HOTEL", "@{refGGastos.id}", 1),
        line("refL_MEAL", "EXP-MEAL", "@{refGGastos.id}", 3),
    ]
    body = {"pricingPref": "System", "taxPref": "Skip",
            "graph": {"graphId": "createQuoteComexi", "records": records}}

    result = rest(token, base, "POST",
                  f"/services/data/v{API}/connect/rev/sales-transaction/actions/place", body)
    print(json.dumps(result, indent=2, ensure_ascii=False))
    if isinstance(result, dict) and result.get("isSuccess"):
        print("\nOK Quote creada:", result.get("salesTransactionId"), "Opp:", opp_id)
    else:
        print("\nPST no isSuccess. Revisa errorResponse arriba.", file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main()
