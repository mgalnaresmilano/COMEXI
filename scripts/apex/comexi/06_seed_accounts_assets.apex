// 06_seed_accounts_assets.apex — Base instalada Comexi (Account, Contacts, Assets, Case)
// Idempotente. Ver build-spec/08-seed-data.md

// ---------- Producto de la maquina (para el Asset) ----------
Id machineProdId;
List<Product2> exMach = [SELECT Id FROM Product2 WHERE StockKeepingUnit = 'MACHINE-PROSLIT-S2DS' LIMIT 1];
if (exMach.isEmpty()) {
    Product2 mp = new Product2(Name = 'Comexi Proslit S2 DS', StockKeepingUnit = 'MACHINE-PROSLIT-S2DS',
        ProductCode = 'MACHINE-PROSLIT-S2DS', IsActive = true, IsAssetizable = true, Family = 'Machine');
    insert mp; machineProdId = mp.Id;
} else { machineProdId = exMach[0].Id; }

// ---------- Account ----------
Account acc;
List<Account> exAcc = [SELECT Id FROM Account WHERE Name = 'Roberts Mart Co Ltd' LIMIT 1];
if (exAcc.isEmpty()) {
    acc = new Account(Name = 'Roberts Mart Co Ltd', BillingCity = 'Leeds', BillingCountry = 'United Kingdom',
        COMEXI_Has_Representative__c = true, COMEXI_Representative_Commission_Pct__c = 8);
    insert acc;
} else {
    acc = exAcc[0];
    acc.COMEXI_Has_Representative__c = true; acc.COMEXI_Representative_Commission_Pct__c = 8;
    acc.BillingCity = 'Leeds'; acc.BillingCountry = 'United Kingdom';
    update acc;
}

// ---------- Contacts ----------
Map<String, Contact> exCon = new Map<String, Contact>();
for (Contact c : [SELECT Id, LastName FROM Contact WHERE AccountId = :acc.Id AND LastName IN ('Prieto','Cabrales')]) exCon.put(c.LastName, c);
List<Contact> toInsCon = new List<Contact>();
if (!exCon.containsKey('Prieto')) toInsCon.add(new Contact(FirstName = 'David', LastName = 'Prieto', Title = 'Service Manager', AccountId = acc.Id));
if (!exCon.containsKey('Cabrales')) toInsCon.add(new Contact(FirstName = 'Ramon', LastName = 'Cabrales', Title = 'Responsable de configuracion', AccountId = acc.Id));
if (!toInsCon.isEmpty()) insert toInsCon;

// ---------- Asset principal MSC000600 (viable) ----------
Asset main;
List<Asset> exMain = [SELECT Id FROM Asset WHERE SerialNumber = 'MSC000600' LIMIT 1];
if (exMain.isEmpty()) {
    main = new Asset(Name = 'MSC000600', SerialNumber = 'MSC000600', AccountId = acc.Id, Product2Id = machineProdId,
        Status = 'Installed', Quantity = 1, InstallDate = Date.newInstance(2015, 6, 1),
        COMEXI_Machine_Model__c = 'Proslit S2 DS', COMEXI_Line__c = 'T', COMEXI_Install_Year__c = 2015,
        COMEXI_Installed_Config__c = 'PC con Windows 10, CPU GL, CU Sinamics, pantalla');
    insert main;
} else {
    main = exMain[0];
    main.COMEXI_Machine_Model__c = 'Proslit S2 DS'; main.COMEXI_Line__c = 'T'; main.COMEXI_Install_Year__c = 2015;
    main.COMEXI_Installed_Config__c = 'PC con Windows 10, CPU GL, CU Sinamics, pantalla'; main.AccountId = acc.Id;
    update main;
}

// ---------- Assets hijos (componentes de MSC000600) ----------
Map<String, Asset> exChild = new Map<String, Asset>();
for (Asset a : [SELECT Id, Name FROM Asset WHERE ParentId = :main.Id]) exChild.put(a.Name, a);
Map<String, String> childCfg = new Map<String, String>{
    'MSC000600-PC' => 'PC con Windows 10 (obsoleto)', 'MSC000600-CPU' => 'CPU GL',
    'MSC000600-CU' => 'CU Sinamics', 'MSC000600-SCREEN' => 'Pantalla operador'
};
List<Asset> toInsChild = new List<Asset>();
for (String nm : childCfg.keySet()) {
    if (exChild.containsKey(nm)) continue;
    toInsChild.add(new Asset(Name = nm, AccountId = acc.Id, ParentId = main.Id, Status = 'Installed', Quantity = 1,
        COMEXI_Installed_Config__c = childCfg.get(nm)));
}
if (!toInsChild.isEmpty()) insert toInsChild;

// ---------- Segunda maquina antigua (no viable) ----------
List<Asset> exOld = [SELECT Id FROM Asset WHERE SerialNumber = 'MSC000123' LIMIT 1];
if (exOld.isEmpty()) {
    Asset oldM = new Asset(Name = 'MSC000123', SerialNumber = 'MSC000123', AccountId = acc.Id,
        Status = 'Installed', Quantity = 1, InstallDate = Date.newInstance(2001, 3, 1),
        COMEXI_Machine_Model__c = 'Proslit S1 (anys 2000)', COMEXI_Line__c = 'T', COMEXI_Install_Year__c = 2001,
        COMEXI_Installed_Config__c = 'PC industrial antic, sense CPU GL compatible');
    insert oldM;
}

// ---------- Case 174535 (relacionado a la cuenta; el Asset se referencia en el texto) ----------
// NOTA: Case.AssetId no esta habilitado en esta org (feature Assets-on-Case), asi que el
// vinculo al Asset MSC000600 se expresa en Subject/Description.
List<Case> exCase = [SELECT Id FROM Case WHERE AccountId = :acc.Id AND Subject LIKE '%174535%' LIMIT 1];
if (exCase.isEmpty()) {
    Case c = new Case(Subject = '174535 - PC + Win (Asset MSC000600)',
        Description = 'Actualitzem oferta W11 si us plau. Maquina: MSC000600 (Proslit S2 DS).',
        AccountId = acc.Id, Status = 'New', Origin = 'Web');
    insert c;
}

System.debug('06_seed OK. Account=' + acc.Id + ' AssetMain=' + main.Id);
