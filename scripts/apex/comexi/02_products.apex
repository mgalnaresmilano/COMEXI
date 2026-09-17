// 02_products.apex — Product2 observados + categorias + selling model option (Comexi)
// Idempotente por StockKeepingUnit. Ver build-spec/01-catalogo-atributos.md §4,§7
// Requiere 01_catalog.apex ejecutado.

Id catId = [SELECT Id FROM ProductCatalog WHERE Code = 'COMEXI_SERVICE' LIMIT 1].Id;
Map<String, Id> catByCode = new Map<String, Id>();
for (ProductCategory c : [SELECT Id, Code FROM ProductCategory WHERE CatalogId = :catId]) catByCode.put(c.Code, c.Id);
Map<String, Id> classByCode = new Map<String, Id>();
for (ProductClassification c : [SELECT Id, Code FROM ProductClassification WHERE Code LIKE 'PC_%']) classByCode.put(c.Code, c.Id);
Id oneTimeId = [SELECT Id FROM ProductSellingModel WHERE SellingModelType = 'OneTime' AND Name = 'One-Time' LIMIT 1].Id;

// Imagen de catalogo por SKU: static resource zip COMEXI_ProductImages
// (unpackaged/post_comexi, generado por scripts/build_comexi_product_images.py).
final String IMG_BASE = '/resource/COMEXI_ProductImages/';

// def: SKU => {Name, Type, BasedOn(classCode or ''), CategoryCode}
// Encoded as parallel maps for clarity.
Map<String, String> pName = new Map<String, String>();
Map<String, String> pType = new Map<String, String>();
Map<String, String> pClass = new Map<String, String>();
Map<String, String> pCat = new Map<String, String>();
Map<String, Boolean> pConfig = new Map<String, Boolean>();

// Bundle protagonista + add-on
pName.put('T100','T100 - UPDATE PC');           pType.put('T100','Bundle');  pClass.put('T100','PC_RETROFIT_PC'); pCat.put('T100','FAM_T'); pConfig.put('T100', true);
pName.put('T100-TEMP','Control de temperatura de tinta'); pCat.put('T100-TEMP','FAM_T');
// Componentes del bundle
pName.put('T100-W11','Canvi de Windows 10 a Windows 11'); pCat.put('T100-W11','FAM_T');
pName.put('T100-CPU-SIM','Canvi CPU Simotion');   pCat.put('T100-CPU-SIM','FAM_T');
pName.put('T100-CU-SIN','Canvi CU Sinamics');     pCat.put('T100-CU-SIN','FAM_T');
pName.put('T100-HMI','Pupitre HMI');              pCat.put('T100-HMI','FAM_T');
pName.put('T100-SCREEN','Canvi de pantalla');     pCat.put('T100-SCREEN','FAM_T');
pName.put('T100-CHECKLIST','Checklist amb numeros de serie'); pCat.put('T100-CHECKLIST','FAM_T');
// Catalogo de contexto FAM_T
pName.put('T040','Analitzador de Profibus');      pCat.put('T040','FAM_T');
pName.put('T060','Marcador digital de velocitat');pCat.put('T060','FAM_T');
pName.put('T114','Aire condicionat');             pCat.put('T114','FAM_T');
pName.put('T120','Encintadors automatics');       pCat.put('T120','FAM_T');
pName.put('T130','Pisors de rebobinat');          pCat.put('T130','FAM_T');
pName.put('T150','Guiador de banda per talladora');pCat.put('T150','FAM_T');
pName.put('T360','Taula d empalmament');          pCat.put('T360','FAM_T');
// FAM_L
pName.put('L210','Sensors de temperatura d aigua');pCat.put('L210','FAM_L');
pName.put('L220','Tractador corona');             pCat.put('L220','FAM_L');
pName.put('L230','Efecte holografic');            pCat.put('L230','FAM_L');
pName.put('L240','Mesclador dosificador de cola');pCat.put('L240','FAM_L');
pName.put('L250','Migracio de Parker a Sinamics');pCat.put('L250','FAM_L');
// FAM_C
pName.put('C110','Equipament pre-premsa');        pCat.put('C110','FAM_C');
pName.put('C120','Equipament laboratori');        pCat.put('C120','FAM_C');
pName.put('C130','Productivitat flexografia');    pCat.put('C130','FAM_C');
pName.put('C140','Periferics flexografia');       pCat.put('C140','FAM_C');
pName.put('C150','Productivitat laminacio');      pCat.put('C150','FAM_C');
// Servicios (Intervencion)
pName.put('SRV-MEC','Muntatge mecanic (CC/MM)');  pClass.put('SRV-MEC','PC_SERVICE_HOUR'); pCat.put('SRV-MEC','SERVICE');
pName.put('SRV-ELE','Instal.lacio electrica (IE)');pClass.put('SRV-ELE','PC_SERVICE_HOUR'); pCat.put('SRV-ELE','SERVICE');
pName.put('SRV-PME','Posada en marxa software (PME)');pClass.put('SRV-PME','PC_SERVICE_HOUR'); pCat.put('SRV-PME','SERVICE');
pName.put('SRV-PMR','Posada en marxa remota');    pClass.put('SRV-PMR','PC_SERVICE_HOUR'); pCat.put('SRV-PMR','SERVICE');
pName.put('SRV-PI','Proves d aplicacions (PI)');  pClass.put('SRV-PI','PC_SERVICE_HOUR'); pCat.put('SRV-PI','SERVICE');
// Gastos
pName.put('EXP-FLIGHT','Bitllet d avio');          pClass.put('EXP-FLIGHT','PC_EXPENSE'); pCat.put('EXP-FLIGHT','GASTOS');
pName.put('EXP-TAXI','Taxi');                      pClass.put('EXP-TAXI','PC_EXPENSE'); pCat.put('EXP-TAXI','GASTOS');
pName.put('EXP-CAR','Cotxe de lloguer');           pClass.put('EXP-CAR','PC_EXPENSE'); pCat.put('EXP-CAR','GASTOS');
pName.put('EXP-HOTEL','Hotel');                    pClass.put('EXP-HOTEL','PC_EXPENSE'); pCat.put('EXP-HOTEL','GASTOS');
pName.put('EXP-MEAL','Dietes');                    pClass.put('EXP-MEAL','PC_EXPENSE'); pCat.put('EXP-MEAL','GASTOS');
pName.put('EXP-ADMIN','Despeses d administracio'); pClass.put('EXP-ADMIN','PC_EXPENSE'); pCat.put('EXP-ADMIN','GASTOS');

// Existentes
Map<String, Product2> existing = new Map<String, Product2>();
for (Product2 p : [SELECT Id, StockKeepingUnit FROM Product2 WHERE StockKeepingUnit IN :pName.keySet()]) {
    existing.put(p.StockKeepingUnit, p);
}
List<Product2> toIns = new List<Product2>();
for (String sku : pName.keySet()) {
    if (existing.containsKey(sku)) continue;
    Product2 p = new Product2(Name = pName.get(sku), StockKeepingUnit = sku, ProductCode = sku, IsActive = true, IsAssetizable = true, DisplayUrl = IMG_BASE + sku + '.png');
    if (pType.containsKey(sku)) p.Type = pType.get(sku);
    if (pClass.containsKey(sku)) p.BasedOnId = classByCode.get(pClass.get(sku));
    if (pConfig.containsKey(sku) && pConfig.get(sku)) p.ConfigureDuringSale = 'Allowed';
    toIns.add(p);
}
if (!toIns.isEmpty()) insert toIns;

Map<String, Id> prodBySku = new Map<String, Id>();
List<Product2> toUpdImg = new List<Product2>();
for (Product2 p : [SELECT Id, StockKeepingUnit, DisplayUrl FROM Product2 WHERE StockKeepingUnit IN :pName.keySet()]) {
    prodBySku.put(p.StockKeepingUnit, p.Id);
    String wanted = IMG_BASE + p.StockKeepingUnit + '.png';
    if (p.DisplayUrl != wanted) toUpdImg.add(new Product2(Id = p.Id, DisplayUrl = wanted));
}
if (!toUpdImg.isEmpty()) update toUpdImg;

// ProductCategoryProduct
Set<String> exPcp = new Set<String>();
for (ProductCategoryProduct x : [SELECT ProductId, ProductCategoryId FROM ProductCategoryProduct WHERE CatalogId = :catId]) {
    exPcp.add(x.ProductId + '|' + x.ProductCategoryId);
}
List<ProductCategoryProduct> toInsPcp = new List<ProductCategoryProduct>();
for (String sku : pName.keySet()) {
    Id prodId = prodBySku.get(sku);
    Id categId = catByCode.get(pCat.get(sku));
    if (prodId == null || categId == null) continue;
    if (!exPcp.contains(prodId + '|' + categId)) {
        toInsPcp.add(new ProductCategoryProduct(ProductCategoryId = categId, ProductId = prodId, IsPrimaryCategory = true));
    }
}
if (!toInsPcp.isEmpty()) insert toInsPcp;

// ProductSellingModelOption (One-Time)
Set<Id> exPsmo = new Set<Id>();
for (ProductSellingModelOption x : [SELECT Product2Id FROM ProductSellingModelOption WHERE Product2Id IN :prodBySku.values() AND ProductSellingModelId = :oneTimeId]) {
    exPsmo.add(x.Product2Id);
}
List<ProductSellingModelOption> toInsPsmo = new List<ProductSellingModelOption>();
for (Id prodId : prodBySku.values()) {
    if (!exPsmo.contains(prodId)) {
        toInsPsmo.add(new ProductSellingModelOption(Product2Id = prodId, ProductSellingModelId = oneTimeId, IsDefault = true));
    }
}
if (!toInsPsmo.isEmpty()) insert toInsPsmo;

System.debug('02_products OK. products=' + prodBySku.size() + ' newPCP=' + toInsPcp.size() + ' newPSMO=' + toInsPsmo.size() + ' imgFixed=' + toUpdImg.size());
