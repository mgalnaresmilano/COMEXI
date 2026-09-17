// 08_stamp_margins.apex — sella coste y margen en Quote/QuoteLineItem (Comexi)
// Idempotente. Ver build-spec/02-pricing-escandallo.md §7.
//
// El pricing procedure reutilizado (RLM_DefaultPricingProcedure) no expone margen,
// asi que el escandallo se hace visible en los campos COMEXI_*: coste unitario desde
// CostBookEntry, margen por linea y margen global de la oferta. Esos dos ultimos son
// la base de la deal guidance y del approval COMEXI_Margin_Approval (descuento > 3%
// o margen < 30%).
//
// Solo actualiza campos custom; no crea ni borra lineas, asi que no invalida el
// pricing calculado por PlaceQuote.

Id stdCb = [SELECT Id FROM CostBook WHERE IsDefault = true LIMIT 1].Id;

// Alcance: las quotes de la demo Comexi (las que cuelgan de una Opportunity con
// record type de retrofit, o la del caso 174535).
List<Quote> quotes = [SELECT Id, TotalPrice, CurrencyIsoCode
    FROM Quote
    WHERE Name LIKE '%Retrofit%' OR Name LIKE '%174535%'];
if (quotes.isEmpty()) {
    System.debug('08_stamp_margins: no hay quotes Comexi que sellar.');
    return;
}
Set<Id> quoteIds = new Map<Id, Quote>(quotes).keySet();

List<QuoteLineItem> lines = [SELECT Id, QuoteId, Product2Id, Quantity, ListPrice,
        UnitPrice, NetUnitPrice, TotalPrice
    FROM QuoteLineItem WHERE QuoteId IN :quoteIds];
if (lines.isEmpty()) {
    System.debug('08_stamp_margins: las quotes no tienen lineas.');
    return;
}

// --- Costes y margenes objetivo, en una sola query cada uno (sin SOQL en bucles) ---
Set<Id> prodIds = new Set<Id>();
for (QuoteLineItem l : lines) prodIds.add(l.Product2Id);

Map<Id, Decimal> costByProduct = new Map<Id, Decimal>();
for (CostBookEntry cbe : [SELECT ProductId, Cost FROM CostBookEntry
        WHERE CostBookId = :stdCb AND ProductId IN :prodIds]) {
    costByProduct.put(cbe.ProductId, cbe.Cost);
}
Map<Id, Decimal> targetByProduct = new Map<Id, Decimal>();
for (Product2 p : [SELECT Id, COMEXI_Target_Margin_Pct__c FROM Product2 WHERE Id IN :prodIds]) {
    targetByProduct.put(p.Id, p.COMEXI_Target_Margin_Pct__c);
}

// --- Sellado por linea + acumulados por quote ---
Map<Id, Decimal> costByQuote = new Map<Id, Decimal>();
Map<Id, Decimal> netByQuote = new Map<Id, Decimal>();
Map<Id, Decimal> listByQuote = new Map<Id, Decimal>();
List<QuoteLineItem> toUpdLines = new List<QuoteLineItem>();

for (QuoteLineItem l : lines) {
    Decimal qty = (l.Quantity == null) ? 1 : l.Quantity;
    Decimal unitCost = costByProduct.containsKey(l.Product2Id) ? costByProduct.get(l.Product2Id) : 0;
    // Preferimos el neto (ya lleva el descuento consumido por el motor).
    Decimal netUnit = (l.NetUnitPrice != null) ? l.NetUnitPrice : l.UnitPrice;
    if (netUnit == null) netUnit = 0;

    Decimal marginPct = (netUnit == 0) ? 0
        : ((netUnit - unitCost) / netUnit * 100).setScale(2, System.RoundingMode.HALF_UP);

    toUpdLines.add(new QuoteLineItem(Id = l.Id,
        COMEXI_Cost__c = unitCost,
        COMEXI_Margin_Pct__c = marginPct,
        COMEXI_Target_Margin_Pct__c = targetByProduct.get(l.Product2Id)));

    Decimal extCost = unitCost * qty;
    Decimal extNet = (l.TotalPrice != null) ? l.TotalPrice : netUnit * qty;
    Decimal extList = ((l.ListPrice != null) ? l.ListPrice : netUnit) * qty;

    costByQuote.put(l.QuoteId, (costByQuote.containsKey(l.QuoteId) ? costByQuote.get(l.QuoteId) : 0) + extCost);
    netByQuote.put(l.QuoteId, (netByQuote.containsKey(l.QuoteId) ? netByQuote.get(l.QuoteId) : 0) + extNet);
    listByQuote.put(l.QuoteId, (listByQuote.containsKey(l.QuoteId) ? listByQuote.get(l.QuoteId) : 0) + extList);
}
if (!toUpdLines.isEmpty()) update toUpdLines;

// --- Roll-up al header ---
List<Quote> toUpdQuotes = new List<Quote>();
for (Quote qt : quotes) {
    if (!netByQuote.containsKey(qt.Id)) continue;
    Decimal totalCost = costByQuote.get(qt.Id);
    Decimal totalNet = netByQuote.get(qt.Id);
    Decimal totalList = listByQuote.get(qt.Id);

    Decimal blended = (totalNet == 0) ? 0
        : ((totalNet - totalCost) / totalNet * 100).setScale(2, System.RoundingMode.HALF_UP);
    // Descuento efectivo de la oferta: cuanto se ha cedido sobre precio de lista.
    Decimal discount = (totalList == null || totalList == 0) ? 0
        : ((totalList - totalNet) / totalList * 100).setScale(2, System.RoundingMode.HALF_UP);

    toUpdQuotes.add(new Quote(Id = qt.Id,
        COMEXI_Total_Cost__c = totalCost.setScale(2, System.RoundingMode.HALF_UP),
        COMEXI_Blended_Margin_Pct__c = blended,
        COMEXI_Discount_Pct__c = discount));
    System.debug('Quote ' + qt.Id + ' net=' + totalNet + ' cost=' + totalCost
        + ' margin=' + blended + '% discount=' + discount + '%');
}
if (!toUpdQuotes.isEmpty()) update toUpdQuotes;

System.debug('08_stamp_margins OK. quotes=' + toUpdQuotes.size() + ' lines=' + toUpdLines.size());
