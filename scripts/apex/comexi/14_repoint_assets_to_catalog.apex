// Repunta la base instalada a los productos reales del catalogo Comexi Maquinaria.
//
// MACHINE-PROSLIT-S2DS y MACHINE-PROSLIT-S1 eran placeholders creados solo para que
// el Asset no saliera sin producto: sin DisplayUrl, sin atributos y fuera de catalogo.
// El catalogo de maquinaria ya tiene la misma maquina bien modelada:
//   MAQ-S2-DS  Comexi S2 DS  - cortadora rebobinadora duplex compacta, 9 atributos
//   MAQ-S1-DS  Comexi S1 DS  - cortadora rebobinadora duplex, 9 atributos
// No se usa MAQ-F1-EVO porque es una impresora flexografica, no una talladora, y
// contradiria el caso 174535, la linea T y el retrofit T100.

Map<String, String> assetToSku = new Map<String, String>{
    'MSC000600' => 'MAQ-S2-DS',
    'MSC000123' => 'MAQ-S1-DS'
};
Map<String, String> assetToModel = new Map<String, String>{
    'MSC000600' => 'S2 DS (antic Proslit S2 DS)',
    'MSC000123' => 'S1 DS (antic Proslit S1)'
};

Map<String, Id> prodBySku = new Map<String, Id>();
for (Product2 p : [SELECT Id, StockKeepingUnit FROM Product2
                   WHERE StockKeepingUnit IN :assetToSku.values()]) {
    prodBySku.put(p.StockKeepingUnit, p.Id);
}
for (String sku : assetToSku.values()) {
    if (!prodBySku.containsKey(sku)) {
        throw new IllegalArgumentException('Falta el producto de catalogo ' + sku);
    }
}

List<Asset> toUpd = new List<Asset>();
for (Asset a : [SELECT Id, Name, Product2Id, COMEXI_Machine_Model__c FROM Asset
                WHERE Name IN :assetToSku.keySet()]) {
    Id target = prodBySku.get(assetToSku.get(a.Name));
    if (a.Product2Id == target) continue;
    a.Product2Id = target;
    a.COMEXI_Machine_Model__c = assetToModel.get(a.Name);
    toUpd.add(a);
}
if (!toUpd.isEmpty()) update toUpd;
System.debug('Assets repuntats: ' + toUpd.size());

// Los placeholders ya no los referencia nadie mas que estos assets.
List<Product2> orphans = [SELECT Id, StockKeepingUnit FROM Product2
                          WHERE StockKeepingUnit IN ('MACHINE-PROSLIT-S2DS', 'MACHINE-PROSLIT-S1')];
if (!orphans.isEmpty()) {
    delete orphans;
    System.debug('Placeholders esborrats: ' + orphans.size());
}
