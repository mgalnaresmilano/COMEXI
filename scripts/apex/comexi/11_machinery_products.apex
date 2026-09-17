// 11_machinery_products.apex — 23 modelos + 3 fichas de solucion como Product2 en el
// catalogo Comexi Maquinaria. Idempotente por StockKeepingUnit. Requiere 10_machinery_catalog.apex.
// Ver build-spec/10-catalogo-maquinaria.md §5. Imagenes: static resource COMEXI_MachineryImages.

Id catId = [SELECT Id FROM ProductCatalog WHERE Code = 'COMEXI_MACHINERY' LIMIT 1].Id;
Map<String, Id> catByCode = new Map<String, Id>();
for (ProductCategory c : [SELECT Id, Code FROM ProductCategory WHERE CatalogId = :catId]) catByCode.put(c.Code, c.Id);
Map<String, Id> classByCode = new Map<String, Id>();
for (ProductClassification c : [SELECT Id, Code FROM ProductClassification WHERE Code LIKE 'PC_MAQ_%']) classByCode.put(c.Code, c.Id);
Id oneTimeId = [SELECT Id FROM ProductSellingModel WHERE SellingModelType = 'OneTime' AND Name = 'One-Time' LIMIT 1].Id;

final String IMG_BASE = '/resource/COMEXI_MachineryImages/';

Map<String, String> pName = new Map<String, String>();
Map<String, String> pClass = new Map<String, String>();
Map<String, String> pCat = new Map<String, String>();
Map<String, String> pDesc = new Map<String, String>();
Set<String> noImg = new Set<String>();  // fichas de solucion sin foto

// --- Flexografica ---
pName.put('MAQ-F1-EVO','Comexi F1 Evolution'); pClass.put('MAQ-F1-EVO','PC_MAQ_FLEXO'); pCat.put('MAQ-F1-EVO','MAQ_PRINT_FLEXO');
pDesc.put('MAQ-F1-EVO','Impresora flexografica CI de gama alta para produccion de alto rendimiento.');
pName.put('MAQ-F2-ML','Comexi F2 ML'); pClass.put('MAQ-F2-ML','PC_MAQ_FLEXO'); pCat.put('MAQ-F2-ML','MAQ_PRINT_FLEXO');
pDesc.put('MAQ-F2-ML','Impresora flexografica CI. Variantes: F2 MB / F2 MP / F2 ML. Atributos segun variante ML (base).');
pName.put('MAQ-F2-ORIGIN','Comexi F2 Origin'); pClass.put('MAQ-F2-ORIGIN','PC_MAQ_FLEXO'); pCat.put('MAQ-F2-ORIGIN','MAQ_PRINT_FLEXO');
pDesc.put('MAQ-F2-ORIGIN','Impresora flexografica CI de acceso, robusta y versatil.');
pName.put('MAQ-F2-MB','Comexi F2 MB'); pClass.put('MAQ-F2-MB','PC_MAQ_FLEXO'); pCat.put('MAQ-F2-MB','MAQ_PRINT_FLEXO');
pDesc.put('MAQ-F2-MB','Impresora flexografica CI, configuracion MB. Datos de la tarjeta de categoria.');
pName.put('MAQ-F4-ORIGIN','Comexi F4 Origin'); pClass.put('MAQ-F4-ORIGIN','PC_MAQ_FLEXO'); pCat.put('MAQ-F4-ORIGIN','MAQ_PRINT_FLEXO');
pDesc.put('MAQ-F4-ORIGIN','Impresora flexografica CI compacta de nueva generacion.');

// --- Offset ---
pName.put('MAQ-OFFSET-CI-EVO','Comexi Offset CI Evolution'); pClass.put('MAQ-OFFSET-CI-EVO','PC_MAQ_OFFSET'); pCat.put('MAQ-OFFSET-CI-EVO','MAQ_PRINT_OFFSET');
pDesc.put('MAQ-OFFSET-CI-EVO','Impresora offset de tambor central (CI) con secado EB.');

// --- Digital ---
pName.put('MAQ-DIGIFLEX','Comexi Digiflex'); pClass.put('MAQ-DIGIFLEX','PC_MAQ_DIGITAL'); pCat.put('MAQ-DIGIFLEX','MAQ_PRINT_DIGITAL');
pDesc.put('MAQ-DIGIFLEX','Impresora digital inkjet UV Low Migration para packaging flexible.');

// --- Laminacion ---
pName.put('MAQ-SL2-MB','Comexi SL2 MB'); pClass.put('MAQ-SL2-MB','PC_MAQ_LAMINATOR'); pCat.put('MAQ-SL2-MB','MAQ_LAM');
pDesc.put('MAQ-SL2-MB','Laminadora sin disolvente (solventless).');
pName.put('MAQ-SL2-EVO','Comexi SL2 Evolution'); pClass.put('MAQ-SL2-EVO','PC_MAQ_LAMINATOR'); pCat.put('MAQ-SL2-EVO','MAQ_LAM');
pDesc.put('MAQ-SL2-EVO','Laminadora sin disolvente de alto rendimiento con cambio automatico de bobina.');
pName.put('MAQ-ML2-EVO','Comexi ML2 Evolution'); pClass.put('MAQ-ML2-EVO','PC_MAQ_LAMINATOR'); pCat.put('MAQ-ML2-EVO','MAQ_LAM');
pDesc.put('MAQ-ML2-EVO','Laminadora multitecnologia (SB/SL/WB/UV).');
pName.put('MAQ-ML1-EVO','Comexi ML1 Evolution'); pClass.put('MAQ-ML1-EVO','PC_MAQ_LAMINATOR'); pCat.put('MAQ-ML1-EVO','MAQ_LAM');
pDesc.put('MAQ-ML1-EVO','Laminadora multitecnologia (SB/SL/WB) de acceso.');

// --- Corte y laser ---
pName.put('MAQ-LASER','Comexi Laser'); pClass.put('MAQ-LASER','PC_MAQ_LASER'); pCat.put('MAQ-LASER','MAQ_CUT');
pDesc.put('MAQ-LASER','Sistema laser CO2 modular para microperforado, macroperforado y easy-open.');
pName.put('MAQ-S1-DT','Comexi S1 DT'); pClass.put('MAQ-S1-DT','PC_MAQ_SLITTER'); pCat.put('MAQ-S1-DT','MAQ_CUT');
pDesc.put('MAQ-S1-DT','Cortadora rebobinadora de torreta doble. Variantes: v6 / evo 8 / evo 10. Atributos segun evo 8 (base).');
pName.put('MAQ-S1-DS','Comexi S1 DS'); pClass.put('MAQ-S1-DS','PC_MAQ_SLITTER'); pCat.put('MAQ-S1-DS','MAQ_CUT');
pDesc.put('MAQ-S1-DS','Cortadora rebobinadora duplex. Variantes: V6 / V8 / V10. Atributos segun V8 (base).');
pName.put('MAQ-S2-DT','Comexi S2 DT'); pClass.put('MAQ-S2-DT','PC_MAQ_SLITTER'); pCat.put('MAQ-S2-DT','MAQ_CUT');
pDesc.put('MAQ-S2-DT','Cortadora rebobinadora de torreta compacta.');
pName.put('MAQ-S2-DS','Comexi S2 DS'); pClass.put('MAQ-S2-DS','PC_MAQ_SLITTER'); pCat.put('MAQ-S2-DS','MAQ_CUT');
pDesc.put('MAQ-S2-DS','Cortadora rebobinadora duplex compacta.');
pName.put('MAQ-S1-MS','Comexi S1 MS'); pClass.put('MAQ-S1-MS','PC_MAQ_SLITTER'); pCat.put('MAQ-S1-MS','MAQ_CUT');
pDesc.put('MAQ-S1-MS','Cortadora rebobinadora monoshaft para grandes diametros.');
pName.put('MAQ-S1-MT','Comexi S1 MT'); pClass.put('MAQ-S1-MT','PC_MAQ_SLITTER'); pCat.put('MAQ-S1-MT','MAQ_CUT');
pDesc.put('MAQ-S1-MT','Cortadora rebobinadora de torreta para grandes bobinas madre.');
pName.put('MAQ-DM1','Comexi DM1'); pClass.put('MAQ-DM1','PC_MAQ_SLITTER'); pCat.put('MAQ-DM1','MAQ_CUT');
pDesc.put('MAQ-DM1','Doctor Machine para inspeccion y reembobinado de bobinas.');

// --- Baterias ---
pName.put('MAQ-S4-ENERGY','Comexi S4 Energy'); pClass.put('MAQ-S4-ENERGY','PC_MAQ_BATTERY'); pCat.put('MAQ-S4-ENERGY','MAQ_BATTERY');
pDesc.put('MAQ-S4-ENERGY','Cortadora rebobinadora para electrodos de bateria (foil recubierto).');
pName.put('MAQ-S2-ENERGY','Comexi S2 Energy'); pClass.put('MAQ-S2-ENERGY','PC_MAQ_BATTERY'); pCat.put('MAQ-S2-ENERGY','MAQ_BATTERY');
pDesc.put('MAQ-S2-ENERGY','Cortadora rebobinadora para electrodos de bateria de gran bobina madre.');
pName.put('MAQ-BATTERY-SEP','Separador de baterias Comexi'); pClass.put('MAQ-BATTERY-SEP','PC_MAQ_BATTERY'); pCat.put('MAQ-BATTERY-SEP','MAQ_BATTERY');
pDesc.put('MAQ-BATTERY-SEP','Solucion de corte para separadores de bateria. La web no publica ficha tecnica propia (reutiliza tablas de S4/S2 Energy).');
pName.put('MAQ-ENERGY-WINDERS','Comexi Energy Winders'); pClass.put('MAQ-ENERGY-WINDERS','PC_MAQ_BATTERY'); pCat.put('MAQ-ENERGY-WINDERS','MAQ_BATTERY');
pDesc.put('MAQ-ENERGY-WINDERS','Bobinadoras para produccion de bateria. Variantes: Ewinder 1000 / Ewinder 1350. Atributos segun Ewinder 1000 (base).');

// --- Fichas de solucion (sin foto, clasificacion generica) ---
pName.put('MAQ-COATING-LINE','Lineas de recubrimiento Comexi'); pClass.put('MAQ-COATING-LINE','PC_MAQ_SOLUTION'); pCat.put('MAQ-COATING-LINE','MAQ_COAT');
pDesc.put('MAQ-COATING-LINE','Solucion de ingenieria a medida. Anchos tipicos 1.500-2.500 mm hasta 600 m/min. Films: BOPP, PET, PA, foils, papers, cardboards. Metodos: Gravure (direct/reverse), Flexo, Semiflexo.');
noImg.add('MAQ-COATING-LINE');
pName.put('MAQ-REEL-HANDLING','Manipulacion de bobinas Comexi'); pClass.put('MAQ-REEL-HANDLING','PC_MAQ_SOLUTION'); pCat.put('MAQ-REEL-HANDLING','MAQ_REELHANDLING');
pDesc.put('MAQ-REEL-HANDLING','Solucion modular por fases (extraccion, embolsado, paletizado, enfardado). Diseno personalizable, ROI < 1 ano.');
noImg.add('MAQ-REEL-HANDLING');
pName.put('MAQ-CLOUD','Comexi Cloud'); pClass.put('MAQ-CLOUD','PC_MAQ_SOLUTION'); pCat.put('MAQ-CLOUD','MAQ_CLOUD');
pDesc.put('MAQ-CLOUD','Plataforma de servicios digitales (ciclo PDCA): analisis de produccion, calculo de costes, pedido online, mantenimiento y documentacion tecnica.');
noImg.add('MAQ-CLOUD');

// ---------- Insert Product2 ----------
Map<String, Product2> existing = new Map<String, Product2>();
for (Product2 p : [SELECT Id, StockKeepingUnit FROM Product2 WHERE StockKeepingUnit IN :pName.keySet()]) existing.put(p.StockKeepingUnit, p);
List<Product2> toIns = new List<Product2>();
for (String sku : pName.keySet()) {
    if (existing.containsKey(sku)) continue;
    Product2 p = new Product2(Name = pName.get(sku), StockKeepingUnit = sku, ProductCode = sku,
        IsActive = true, IsAssetizable = true, Description = pDesc.get(sku));
    if (pClass.containsKey(sku)) p.BasedOnId = classByCode.get(pClass.get(sku));
    if (!noImg.contains(sku)) p.DisplayUrl = IMG_BASE + sku + '.jpg';
    toIns.add(p);
}
if (!toIns.isEmpty()) insert toIns;

// ---------- Fix idempotente de DisplayUrl y Description ----------
Map<String, Id> prodBySku = new Map<String, Id>();
List<Product2> toUpd = new List<Product2>();
for (Product2 p : [SELECT Id, StockKeepingUnit, DisplayUrl, Description FROM Product2 WHERE StockKeepingUnit IN :pName.keySet()]) {
    prodBySku.put(p.StockKeepingUnit, p.Id);
    String wantedImg = noImg.contains(p.StockKeepingUnit) ? null : IMG_BASE + p.StockKeepingUnit + '.jpg';
    Boolean changed = false;
    Product2 upd = new Product2(Id = p.Id);
    if (p.DisplayUrl != wantedImg) { upd.DisplayUrl = wantedImg; changed = true; }
    if (p.Description != pDesc.get(p.StockKeepingUnit)) { upd.Description = pDesc.get(p.StockKeepingUnit); changed = true; }
    if (changed) toUpd.add(upd);
}
if (!toUpd.isEmpty()) update toUpd;

// ---------- ProductCategoryProduct ----------
Set<String> exPcp = new Set<String>();
for (ProductCategoryProduct x : [SELECT ProductId, ProductCategoryId FROM ProductCategoryProduct WHERE CatalogId = :catId]) exPcp.add(x.ProductId + '|' + x.ProductCategoryId);
List<ProductCategoryProduct> toInsPcp = new List<ProductCategoryProduct>();
for (String sku : pName.keySet()) {
    Id prodId = prodBySku.get(sku);
    Id categId = catByCode.get(pCat.get(sku));
    if (prodId == null || categId == null) continue;
    if (!exPcp.contains(prodId + '|' + categId))
        toInsPcp.add(new ProductCategoryProduct(ProductCategoryId = categId, ProductId = prodId, IsPrimaryCategory = true));
}
if (!toInsPcp.isEmpty()) insert toInsPcp;

// ---------- ProductSellingModelOption (One-Time) ----------
Set<Id> exPsmo = new Set<Id>();
for (ProductSellingModelOption x : [SELECT Product2Id FROM ProductSellingModelOption WHERE Product2Id IN :prodBySku.values() AND ProductSellingModelId = :oneTimeId]) exPsmo.add(x.Product2Id);
List<ProductSellingModelOption> toInsPsmo = new List<ProductSellingModelOption>();
for (Id prodId : prodBySku.values()) {
    if (!exPsmo.contains(prodId))
        toInsPsmo.add(new ProductSellingModelOption(Product2Id = prodId, ProductSellingModelId = oneTimeId, IsDefault = true));
}
if (!toInsPsmo.isEmpty()) insert toInsPsmo;

System.debug('11_machinery_products OK. products=' + prodBySku.size() + ' newPCP=' + toInsPcp.size()
    + ' newPSMO=' + toInsPsmo.size() + ' upd=' + toUpd.size());
