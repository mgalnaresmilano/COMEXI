// Escena 01: deja navegable el salto Asset <-> Case y completa la base instalada.
//
// 1. Crea los 4 productos que representan componentes YA INSTALADOS. No se meten en
//    ningun ProductCatalog ni llevan PricebookEntry, asi que no aparecen en el
//    configurador ni en product discovery de las escenas 04 y 07.
// 2. Completa los 4 assets hijos, que estaban sin producto, sin fecha de instalacion
//    y sin modelo/anyo/linea.
// 3. Coherencia del parque: MSC000123 (2001) es la maquina con Windows XP y
//    MSC000600 (2015) la de Windows 10. La serie PC-6001-XP contradecia esto.
// 4. Rellena Case.AssetId en los casos cuyo asunto identifica la maquina.

final String CUR = 'EUR';

Map<String, String> compProducts = new Map<String, String>{
    'COMP-PC-IND'    => 'PC industrial (base instal.lada)',
    'COMP-CPU-GL'    => 'CPU GL (base instal.lada)',
    'COMP-CU-SIN'    => 'CU Sinamics (base instal.lada)',
    'COMP-SCREEN-15' => 'Pantalla operador 15 polzades (base instal.lada)'
};

// ---------- Productos de componente instalado ----------
Map<String, Id> prodBySku = new Map<String, Id>();
for (Product2 p : [SELECT Id, StockKeepingUnit FROM Product2
                   WHERE StockKeepingUnit IN :compProducts.keySet()]) {
    prodBySku.put(p.StockKeepingUnit, p.Id);
}

List<Product2> newProds = new List<Product2>();
for (String sku : compProducts.keySet()) {
    if (prodBySku.containsKey(sku)) continue;
    newProds.add(new Product2(
        Name = compProducts.get(sku),
        StockKeepingUnit = sku,
        ProductCode = sku,
        Description = 'Component de la base instal.lada. No es ven: existeix per donar '
            + 'entitat als assets de components i poder tracar el retrofit.',
        IsActive = true));
}
if (!newProds.isEmpty()) {
    insert newProds;
    for (Product2 p : newProds) prodBySku.put(p.StockKeepingUnit, p.Id);
}
System.debug('Productes de component: ' + prodBySku.size());

// ---------- Assets ----------
Map<String, Asset> assetByName = new Map<String, Asset>();
for (Asset a : [SELECT Id, Name, SerialNumber, Product2Id, InstallDate, ParentId,
                       COMEXI_Machine_Model__c, COMEXI_Install_Year__c,
                       COMEXI_Line__c, COMEXI_Installed_Config__c
                FROM Asset]) {
    assetByName.put(a.Name, a);
}

// Config del componente hijo: producto, texto y serie coherente.
Map<String, List<String>> childSpec = new Map<String, List<String>>{
    'MSC000600-PC'     => new List<String>{'COMP-PC-IND',    'PC industrial amb Windows 10 (fi de suport)', 'PC-6001-W10'},
    'MSC000600-CPU'    => new List<String>{'COMP-CPU-GL',    'CPU GL Simotion',                             'CPU-SIM-6002'},
    'MSC000600-CU'     => new List<String>{'COMP-CU-SIN',    'CU Sinamics',                                 'CU-SIN-6003'},
    'MSC000600-SCREEN' => new List<String>{'COMP-SCREEN-15', 'Pantalla operador 15 polzades',               'SCR-6004-15'}
};

List<Asset> toUpd = new List<Asset>();

Asset parent = assetByName.get('MSC000600');
if (parent != null) {
    parent.COMEXI_Installed_Config__c =
        'PC amb Windows 10, CPU GL Simotion, CU Sinamics i pantalla operador 15 polzades';
    toUpd.add(parent);
}

Asset old1 = assetByName.get('MSC000123');
if (old1 != null) {
    old1.COMEXI_Installed_Config__c =
        'PC industrial amb Windows XP, sense CPU GL compatible amb el retrofit T100';
    old1.COMEXI_Machine_Model__c = 'Proslit S1 (anys 2000)';
    toUpd.add(old1);
}

for (String childName : childSpec.keySet()) {
    Asset a = assetByName.get(childName);
    if (a == null) continue;
    List<String> spec = childSpec.get(childName);
    a.Product2Id = prodBySku.get(spec[0]);
    a.COMEXI_Installed_Config__c = spec[1];
    a.SerialNumber = spec[2];
    // Los componentes se instalaron con la maquina: sin esto la related list de
    // assets de la cuenta sale con la columna de fecha vacia en 4 de 6 filas.
    a.InstallDate = (parent != null) ? parent.InstallDate : Date.newInstance(2015, 6, 1);
    a.COMEXI_Machine_Model__c = 'Proslit S2 DS';
    a.COMEXI_Install_Year__c = 2015;
    a.COMEXI_Line__c = 'T';
    toUpd.add(a);
}

if (!toUpd.isEmpty()) update toUpd;
System.debug('Assets actualitzats: ' + toUpd.size());

// ---------- Case.AssetId ----------
// Solo los casos cuyo asunto identifica la maquina. El de la sonda de cola se queda
// sin asset a proposito: no todos los casos nacen contra una maquina concreta.
Map<String, String> caseToAsset = new Map<String, String>{
    '00001003' => 'MSC000600',
    '00001004' => 'MSC000600',
    '00001006' => 'MSC000123',
    '00001007' => 'MSC000600',
    '00001008' => 'MSC000123'
};

List<Case> caseUpd = new List<Case>();
for (Case c : [SELECT Id, CaseNumber, AssetId FROM Case
               WHERE CaseNumber IN :caseToAsset.keySet()]) {
    Asset target = assetByName.get(caseToAsset.get(c.CaseNumber));
    if (target == null || c.AssetId == target.Id) continue;
    caseUpd.add(new Case(Id = c.Id, AssetId = target.Id));
}
if (!caseUpd.isEmpty()) update caseUpd;
System.debug('Casos enllacats a asset: ' + caseUpd.size());
