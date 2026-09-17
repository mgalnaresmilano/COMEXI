// 13_machinery_pricing.apex — PricebookEntry (EUR) + CostBookEntry (70%) + margen objetivo
// (30%) para los modelos de Comexi Maquinaria. Idempotente. Requiere 10 y 11.
// Ver build-spec/10 §5. Precios PLACEHOLDER (orientativos): Comexi no publica precios.
//
// MONEDA: como en 04_pricing_data.apex, la org es multicurrency pero la demo cotiza en EUR.
// Se borran los PBE/CBE que no sean EUR de estos productos para que el discovery no elija
// la moneda corporativa y rompa la linea por currency mismatch.
final String CUR = 'EUR';

Id stdPb = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1].Id;
Id stdCb = [SELECT Id FROM CostBook WHERE IsDefault = true LIMIT 1].Id;
Id oneTimeId = [SELECT Id FROM ProductSellingModel WHERE SellingModelType = 'OneTime' AND Name = 'One-Time' LIMIT 1].Id;

// Precio de lista PLACEHOLDER por SKU (EUR). Coste = 70%, margen objetivo 30%.
Map<String, Decimal> price = new Map<String, Decimal>{
    'MAQ-F1-EVO' => 2400000, 'MAQ-F2-ML' => 1600000, 'MAQ-F2-ORIGIN' => 1200000,
    'MAQ-F2-MB' => 1100000, 'MAQ-F4-ORIGIN' => 900000,
    'MAQ-OFFSET-CI-EVO' => 2200000, 'MAQ-DIGIFLEX' => 1800000,
    'MAQ-SL2-MB' => 700000, 'MAQ-SL2-EVO' => 1100000, 'MAQ-ML2-EVO' => 950000, 'MAQ-ML1-EVO' => 600000,
    'MAQ-LASER' => 450000, 'MAQ-S1-DT' => 700000, 'MAQ-S1-DS' => 750000, 'MAQ-S2-DT' => 850000,
    'MAQ-S2-DS' => 800000, 'MAQ-S1-MS' => 600000, 'MAQ-S1-MT' => 650000, 'MAQ-DM1' => 350000,
    'MAQ-S4-ENERGY' => 900000, 'MAQ-S2-ENERGY' => 1200000, 'MAQ-BATTERY-SEP' => 1000000,
    'MAQ-ENERGY-WINDERS' => 700000
};
final Decimal COST_RATIO = 0.70;
final Decimal TARGET_MARGIN = 30;

Map<String, Id> prodBySku = new Map<String, Id>();
for (Product2 p : [SELECT Id, StockKeepingUnit FROM Product2 WHERE StockKeepingUnit IN :price.keySet()]) prodBySku.put(p.StockKeepingUnit, p.Id);

// ---------- Target margin en Product2 ----------
List<Product2> toUpd = new List<Product2>();
for (String sku : prodBySku.keySet()) {
    toUpd.add(new Product2(Id = prodBySku.get(sku), COMEXI_Target_Margin_Pct__c = TARGET_MARGIN));
}
if (!toUpd.isEmpty()) update toUpd;

// ---------- PricebookEntry (Standard, solo EUR) ----------
List<PricebookEntry> wrongCur = [SELECT Id FROM PricebookEntry
    WHERE Pricebook2Id = :stdPb AND Product2Id IN :prodBySku.values() AND CurrencyIsoCode != :CUR];
if (!wrongCur.isEmpty()) delete wrongCur;

Set<Id> exPbe = new Set<Id>();
for (PricebookEntry x : [SELECT Product2Id FROM PricebookEntry WHERE Pricebook2Id = :stdPb AND Product2Id IN :prodBySku.values() AND ProductSellingModelId = :oneTimeId AND CurrencyIsoCode = :CUR]) exPbe.add(x.Product2Id);
List<PricebookEntry> toInsPbe = new List<PricebookEntry>();
for (String sku : prodBySku.keySet()) {
    Id pid = prodBySku.get(sku);
    if (exPbe.contains(pid)) continue;
    toInsPbe.add(new PricebookEntry(Pricebook2Id = stdPb, Product2Id = pid, ProductSellingModelId = oneTimeId,
        CurrencyIsoCode = CUR, UnitPrice = price.get(sku), IsActive = true, UseStandardPrice = false));
}
if (!toInsPbe.isEmpty()) insert toInsPbe;

// ---------- CostBookEntry (Standard Cost Book, solo EUR) ----------
List<CostBookEntry> wrongCbeCur = [SELECT Id FROM CostBookEntry
    WHERE CostBookId = :stdCb AND ProductId IN :prodBySku.values() AND CurrencyIsoCode != :CUR];
if (!wrongCbeCur.isEmpty()) delete wrongCbeCur;

Set<Id> exCbe = new Set<Id>();
for (CostBookEntry x : [SELECT ProductId FROM CostBookEntry WHERE CostBookId = :stdCb AND ProductId IN :prodBySku.values() AND CurrencyIsoCode = :CUR]) exCbe.add(x.ProductId);
List<CostBookEntry> toInsCbe = new List<CostBookEntry>();
for (String sku : prodBySku.keySet()) {
    Id pid = prodBySku.get(sku);
    if (exCbe.contains(pid)) continue;
    Decimal costVal = (price.get(sku) * COST_RATIO).setScale(2);
    toInsCbe.add(new CostBookEntry(CostBookId = stdCb, ProductId = pid, CurrencyIsoCode = CUR,
        Cost = costVal, EffectiveFrom = Date.newInstance(2020, 1, 1)));
}
if (!toInsCbe.isEmpty()) insert toInsCbe;

System.debug('13_machinery_pricing OK (PLACEHOLDER). products=' + prodBySku.size()
    + ' newPBE=' + toInsPbe.size() + ' newCBE=' + toInsCbe.size() + ' targetUpd=' + toUpd.size());
