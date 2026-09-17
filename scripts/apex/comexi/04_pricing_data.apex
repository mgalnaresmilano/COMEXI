// 04_pricing_data.apex — PricebookEntry + CostBookEntry calibrados + target margins (Comexi)
// Idempotente. Ver build-spec/02-pricing-escandallo.md §1-§3, build-spec/08 §5
// Calibracion: T100 lista 7321.39 EUR; -5% = 6955.32 EUR; coste 5039.56 -> margen 27.54% (1915.76 EUR).
//
// MONEDA: la org es multicurrency con corporativa USD, pero la demo cotiza en EUR.
// El discovery de catalogo y el pricing corren en la moneda por defecto del USUARIO,
// no en la de la quote, asi que TODO debe estar en EUR y coherente: usuario (User.
// DefaultCurrencyIsoCode='EUR'), PricebookEntry y Quote. Un PBE en USD "gana" al EUR
// en el discovery y luego rompe la linea por currency mismatch, por eso este script
// borra los PBE que no sean EUR de estos productos.
final String CUR = 'EUR';

Id stdPb = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1].Id;
Id stdCb = [SELECT Id FROM CostBook WHERE IsDefault = true LIMIT 1].Id;
Id oneTimeId = [SELECT Id FROM ProductSellingModel WHERE SellingModelType = 'OneTime' AND Name = 'One-Time' LIMIT 1].Id;

// precio de lista y coste por SKU
Map<String, Decimal> price = new Map<String, Decimal>();
Map<String, Decimal> cost = new Map<String, Decimal>();
Map<String, Decimal> targetMargin = new Map<String, Decimal>();

// --- Producto principal: todo el coste/precio del material en la linea bundle ---
price.put('T100', 7321.39);   cost.put('T100', 5039.56);   targetMargin.put('T100', 42);
price.put('T100-TEMP', 3600.00); cost.put('T100-TEMP', 2520.00); targetMargin.put('T100-TEMP', 30);
// Componentes del bundle: precio y coste 0 (incluidos en la linea bundle)
for (String c : new List<String>{'T100-W11','T100-CPU-SIM','T100-CU-SIN','T100-HMI','T100-SCREEN','T100-CHECKLIST'}) {
    price.put(c, 0); cost.put(c, 0); targetMargin.put(c, 0);
}
// --- Servicios (hora tecnico 56, venta 95 -> ~41%) ---
for (String s : new List<String>{'SRV-MEC','SRV-ELE','SRV-PME','SRV-PMR','SRV-PI'}) {
    price.put(s, 95.00); cost.put(s, 56.00); targetMargin.put(s, 40);
}
// --- Gastos: coste total 2420, margen bajo 10% ---
price.put('EXP-FLIGHT', 990.00); cost.put('EXP-FLIGHT', 900.00);
price.put('EXP-HOTEL', 660.00);  cost.put('EXP-HOTEL', 600.00);
price.put('EXP-TAXI', 132.00);   cost.put('EXP-TAXI', 120.00);
price.put('EXP-CAR', 330.00);    cost.put('EXP-CAR', 300.00);
price.put('EXP-MEAL', 99.00);    cost.put('EXP-MEAL', 90.00);
price.put('EXP-ADMIN', 451.00);  cost.put('EXP-ADMIN', 410.00);
for (String e : new List<String>{'EXP-FLIGHT','EXP-HOTEL','EXP-TAXI','EXP-CAR','EXP-MEAL','EXP-ADMIN'}) targetMargin.put(e, 10);
// --- Catalogo de contexto (precios nominales para que no este vacio) ---
for (String ctx : new List<String>{'T040','T060','T114','T120','T130','T150','T360','L210','L220','L230','L240','L250','C110','C120','C130','C140','C150'}) {
    price.put(ctx, 5000.00); cost.put(ctx, 3000.00); targetMargin.put(ctx, 25);
}

Map<String, Id> prodBySku = new Map<String, Id>();
for (Product2 p : [SELECT Id, StockKeepingUnit FROM Product2 WHERE StockKeepingUnit IN :price.keySet()]) prodBySku.put(p.StockKeepingUnit, p.Id);

// ---------- Target margin en Product2 ----------
List<Product2> toUpd = new List<Product2>();
for (String sku : prodBySku.keySet()) {
    if (targetMargin.get(sku) == null || targetMargin.get(sku) == 0) continue;
    toUpd.add(new Product2(Id = prodBySku.get(sku), COMEXI_Target_Margin_Pct__c = targetMargin.get(sku)));
}
if (!toUpd.isEmpty()) update toUpd;

// ---------- PricebookEntry (Standard, solo EUR) ----------
// Fuera cualquier PBE que no sea EUR: si convive con el EUR, el discovery elige el
// corporativo (USD) y la linea falla con "price book entry currency code is different".
List<PricebookEntry> wrongCur = [SELECT Id FROM PricebookEntry
    WHERE Pricebook2Id = :stdPb AND Product2Id IN :prodBySku.values() AND CurrencyIsoCode != :CUR];
if (!wrongCur.isEmpty()) delete wrongCur;

Set<Id> exPbe = new Set<Id>();
for (PricebookEntry x : [SELECT Product2Id FROM PricebookEntry WHERE Pricebook2Id = :stdPb AND Product2Id IN :prodBySku.values() AND ProductSellingModelId = :oneTimeId AND CurrencyIsoCode = :CUR]) exPbe.add(x.Product2Id);
List<PricebookEntry> toInsPbe = new List<PricebookEntry>();
for (String sku : prodBySku.keySet()) {
    Id pid = prodBySku.get(sku);
    if (exPbe.contains(pid)) continue;
    toInsPbe.add(new PricebookEntry(Pricebook2Id = stdPb, Product2Id = pid, ProductSellingModelId = oneTimeId, CurrencyIsoCode = CUR, UnitPrice = price.get(sku), IsActive = true, UseStandardPrice = false));
}
if (!toInsPbe.isEmpty()) insert toInsPbe;

// ---------- CostBookEntry (Standard Cost Book, solo EUR) ----------
// El coste tiene que estar en la misma moneda que el precio para que el margen del
// escandallo (27,54% en el T100) salga bien.
List<CostBookEntry> wrongCbeCur = [SELECT Id FROM CostBookEntry
    WHERE CostBookId = :stdCb AND ProductId IN :prodBySku.values() AND CurrencyIsoCode != :CUR];
if (!wrongCbeCur.isEmpty()) delete wrongCbeCur;

Set<Id> exCbe = new Set<Id>();
for (CostBookEntry x : [SELECT ProductId FROM CostBookEntry WHERE CostBookId = :stdCb AND ProductId IN :prodBySku.values() AND CurrencyIsoCode = :CUR]) exCbe.add(x.ProductId);
List<CostBookEntry> toInsCbe = new List<CostBookEntry>();
for (String sku : prodBySku.keySet()) {
    Id pid = prodBySku.get(sku);
    if (exCbe.contains(pid)) continue;
    toInsCbe.add(new CostBookEntry(CostBookId = stdCb, ProductId = pid, CurrencyIsoCode = CUR, Cost = cost.get(sku), EffectiveFrom = Date.newInstance(2020, 1, 1)));
}
if (!toInsCbe.isEmpty()) insert toInsCbe;

System.debug('04_pricing OK. products=' + prodBySku.size() + ' newPBE=' + toInsPbe.size() + ' newCBE=' + toInsCbe.size() + ' targetUpd=' + toUpd.size());
