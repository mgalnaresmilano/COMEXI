// 01_catalog.apex — Catalogo, categorias, clasificaciones y cadena de atributos (Comexi)
// Idempotente: reejecutable sin duplicar. Ver build-spec/01-catalogo-atributos.md

// ---------- 1. ProductCatalog ----------
ProductCatalog cat;
List<ProductCatalog> exCat = [SELECT Id FROM ProductCatalog WHERE Code = 'COMEXI_SERVICE' LIMIT 1];
if (exCat.isEmpty()) {
    cat = new ProductCatalog(Name = 'Comexi Service & Retrofit', Code = 'COMEXI_SERVICE',
        CatalogType = 'Sales', EffectiveStartDate = Date.newInstance(2020, 1, 1));
    insert cat;
} else {
    cat = exCat[0];
}
System.debug('Catalog: ' + cat.Id);

// ---------- 2. ProductCategory ----------
Map<String, ProductCategory> catByCode = new Map<String, ProductCategory>();
for (ProductCategory pc : [SELECT Id, Code FROM ProductCategory WHERE CatalogId = :cat.Id]) {
    catByCode.put(pc.Code, pc);
}
// roots
Map<String, String> roots = new Map<String, String>{
    'RETROFIT' => 'Retrofit', 'SERVICE' => 'Servicio (packs)', 'GASTOS' => 'Gastos e intervencion'
};
List<ProductCategory> toInsRoot = new List<ProductCategory>();
for (String code : roots.keySet()) {
    if (!catByCode.containsKey(code)) {
        toInsRoot.add(new ProductCategory(CatalogId = cat.Id, Code = code, Name = roots.get(code), IsNavigational = true));
    }
}
if (!toInsRoot.isEmpty()) { insert toInsRoot; for (ProductCategory p : toInsRoot) catByCode.put(p.Code, p); }
// children under RETROFIT
Map<String, String> fams = new Map<String, String>{
    'FAM_T' => 'Tall / Slitting (T0xx-T3xx)', 'FAM_L' => 'Laminacion y Calandras (L2xx-L9xx)',
    'FAM_C' => 'Perifericos CTEC (C1xx)', 'FAM_P' => 'Piezas (P0xx)'
};
Id retrofitId = catByCode.get('RETROFIT').Id;
List<ProductCategory> toInsFam = new List<ProductCategory>();
for (String code : fams.keySet()) {
    if (!catByCode.containsKey(code)) {
        toInsFam.add(new ProductCategory(CatalogId = cat.Id, Code = code, Name = fams.get(code),
            ParentCategoryId = retrofitId, IsNavigational = true));
    }
}
if (!toInsFam.isEmpty()) { insert toInsFam; for (ProductCategory p : toInsFam) catByCode.put(p.Code, p); }

// ---------- 3. ProductClassification ----------
Map<String, String> classes = new Map<String, String>{
    'PC_RETROFIT_PC' => 'Retrofit - Update PC', 'PC_RETROFIT_GENERIC' => 'Retrofit generico',
    'PC_SERVICE_HOUR' => 'Hora de servicio', 'PC_EXPENSE' => 'Gasto'
};
Map<String, ProductClassification> pcByCode = new Map<String, ProductClassification>();
for (ProductClassification p : [SELECT Id, Code FROM ProductClassification WHERE Code IN :classes.keySet()]) {
    pcByCode.put(p.Code, p);
}
List<ProductClassification> toInsPc = new List<ProductClassification>();
for (String code : classes.keySet()) {
    if (!pcByCode.containsKey(code)) {
        toInsPc.add(new ProductClassification(Code = code, Name = classes.get(code), Status = 'Active'));
    }
}
if (!toInsPc.isEmpty()) { insert toInsPc; for (ProductClassification p : toInsPc) pcByCode.put(p.Code, p); }

// ---------- 4. AttributeCategory ----------
Map<String, String> attrCats = new Map<String, String>{ 'CFG_PC' => 'Configuracio PC', 'LOGISTICS' => 'Logistica' };
Map<String, AttributeCategory> acByCode = new Map<String, AttributeCategory>();
for (AttributeCategory a : [SELECT Id, Code FROM AttributeCategory WHERE Code IN :attrCats.keySet()]) {
    acByCode.put(a.Code, a);
}
List<AttributeCategory> toInsAc = new List<AttributeCategory>();
for (String code : attrCats.keySet()) {
    if (!acByCode.containsKey(code)) toInsAc.add(new AttributeCategory(Code = code, Name = attrCats.get(code)));
}
if (!toInsAc.isEmpty()) { insert toInsAc; for (AttributeCategory a : toInsAc) acByCode.put(a.Code, a); }

// ---------- 5. AttributePicklist + values ----------
Map<String, AttributePicklist> plByCode = new Map<String, AttributePicklist>();
for (AttributePicklist p : [SELECT Id, Code FROM AttributePicklist WHERE Code IN ('COMEXI_RetrofitType_PL','COMEXI_ChargedTo_PL')]) {
    plByCode.put(p.Code, p);
}
List<AttributePicklist> toInsPl = new List<AttributePicklist>();
if (!plByCode.containsKey('COMEXI_RetrofitType_PL'))
    toInsPl.add(new AttributePicklist(Name = 'COMEXI Retrofit Type', Code = 'COMEXI_RetrofitType_PL', DataType = 'Text', Status = 'Active'));
if (!plByCode.containsKey('COMEXI_ChargedTo_PL'))
    toInsPl.add(new AttributePicklist(Name = 'COMEXI Charged To', Code = 'COMEXI_ChargedTo_PL', DataType = 'Text', Status = 'Active'));
if (!toInsPl.isEmpty()) { insert toInsPl; for (AttributePicklist p : toInsPl) plByCode.put(p.Code, p); }

Map<String, List<String>> plValues = new Map<String, List<String>>{
    'COMEXI_RetrofitType_PL' => new List<String>{ 'CTEC','RET_NEW_FEATURES','RET_OBS','RET_NEW_DESIGNS','RET_MAINT' },
    'COMEXI_ChargedTo_PL' => new List<String>{ 'Comexi','Client' }
};
Set<Id> plIds = new Set<Id>();
for (AttributePicklist p : plByCode.values()) plIds.add(p.Id);
Set<String> existingVals = new Set<String>();
for (AttributePicklistValue v : [SELECT PicklistId, Code FROM AttributePicklistValue WHERE PicklistId IN :plIds]) {
    existingVals.add(v.PicklistId + '|' + v.Code);
}
List<AttributePicklistValue> toInsVal = new List<AttributePicklistValue>();
for (String plCode : plValues.keySet()) {
    Id pid = plByCode.get(plCode).Id;
    Integer seq = 1;
    for (String val : plValues.get(plCode)) {
        if (!existingVals.contains(pid + '|' + val)) {
            toInsVal.add(new AttributePicklistValue(PicklistId = pid, Code = val, Name = val,
                Value = val, DisplayValue = val, Sequence = seq, Status = 'Active'));
        }
        seq++;
    }
}
if (!toInsVal.isEmpty()) insert toInsVal;

// ---------- 6. AttributeDefinition ----------
Map<String, AttributeDefinition> adByDev = new Map<String, AttributeDefinition>();
for (AttributeDefinition a : [SELECT Id, DeveloperName FROM AttributeDefinition
        WHERE DeveloperName IN ('COMEXI_Num_CPU_GL','COMEXI_Num_CU_Total','COMEXI_RetrofitType','COMEXI_Charged_To')]) {
    adByDev.put(a.DeveloperName, a);
}
List<AttributeDefinition> toInsAd = new List<AttributeDefinition>();
if (!adByDev.containsKey('COMEXI_Num_CPU_GL'))
    toInsAd.add(new AttributeDefinition(Name = 'Num CPU GL', DeveloperName = 'COMEXI_Num_CPU_GL', Label = 'N. de CPUs GL', Code = 'COMEXI_Num_CPU_GL', DataType = 'Number', IsActive = true));
if (!adByDev.containsKey('COMEXI_Num_CU_Total'))
    toInsAd.add(new AttributeDefinition(Name = 'Num CU Total', DeveloperName = 'COMEXI_Num_CU_Total', Label = 'N. de CUs totals', Code = 'COMEXI_Num_CU_Total', DataType = 'Number', IsActive = true));
if (!adByDev.containsKey('COMEXI_RetrofitType'))
    toInsAd.add(new AttributeDefinition(Name = 'Retrofit Type', DeveloperName = 'COMEXI_RetrofitType', Label = 'Tipus de retrofit', Code = 'COMEXI_RetrofitType', DataType = 'Picklist', IsActive = true, PicklistId = plByCode.get('COMEXI_RetrofitType_PL').Id));
if (!adByDev.containsKey('COMEXI_Charged_To'))
    toInsAd.add(new AttributeDefinition(Name = 'Charged To', DeveloperName = 'COMEXI_Charged_To', Label = 'A carrec de', Code = 'COMEXI_Charged_To', DataType = 'Picklist', IsActive = true, PicklistId = plByCode.get('COMEXI_ChargedTo_PL').Id));
if (!toInsAd.isEmpty()) { insert toInsAd; for (AttributeDefinition a : toInsAd) adByDev.put(a.DeveloperName, a); }

// ---------- 7. AttributeCategoryAttribute ----------
Map<String, List<String>> acaMap = new Map<String, List<String>>{
    'CFG_PC' => new List<String>{ 'COMEXI_Num_CPU_GL','COMEXI_Num_CU_Total','COMEXI_RetrofitType' },
    'LOGISTICS' => new List<String>{ 'COMEXI_Charged_To' }
};
Set<String> exAca = new Set<String>();
for (AttributeCategoryAttribute a : [SELECT AttributeCategoryId, AttributeDefinitionId FROM AttributeCategoryAttribute
        WHERE AttributeCategoryId IN :(new List<Id>{ acByCode.get('CFG_PC').Id, acByCode.get('LOGISTICS').Id })]) {
    exAca.add(a.AttributeCategoryId + '|' + a.AttributeDefinitionId);
}
List<AttributeCategoryAttribute> toInsAca = new List<AttributeCategoryAttribute>();
for (String acCode : acaMap.keySet()) {
    Id acId = acByCode.get(acCode).Id;
    for (String dev : acaMap.get(acCode)) {
        Id adId = adByDev.get(dev).Id;
        if (!exAca.contains(acId + '|' + adId)) {
            toInsAca.add(new AttributeCategoryAttribute(AttributeCategoryId = acId, AttributeDefinitionId = adId));
        }
    }
}
if (!toInsAca.isEmpty()) insert toInsAca;

// ---------- 8. ProductClassificationAttr (para PC_RETROFIT_PC) ----------
Id classPcId = pcByCode.get('PC_RETROFIT_PC').Id;
Set<Id> exPcaAttr = new Set<Id>();
for (ProductClassificationAttr a : [SELECT AttributeDefinitionId FROM ProductClassificationAttr WHERE ProductClassificationId = :classPcId]) {
    exPcaAttr.add(a.AttributeDefinitionId);
}
List<ProductClassificationAttr> toInsPca = new List<ProductClassificationAttr>();
if (!exPcaAttr.contains(adByDev.get('COMEXI_Num_CPU_GL').Id))
    toInsPca.add(new ProductClassificationAttr(ProductClassificationId = classPcId, AttributeDefinitionId = adByDev.get('COMEXI_Num_CPU_GL').Id, Name = 'N. de CPUs GL', Sequence = 10, IsRequired = true, IsPriceImpacting = false, Status = 'Active'));
if (!exPcaAttr.contains(adByDev.get('COMEXI_Num_CU_Total').Id))
    toInsPca.add(new ProductClassificationAttr(ProductClassificationId = classPcId, AttributeDefinitionId = adByDev.get('COMEXI_Num_CU_Total').Id, Name = 'N. de CUs totals', Sequence = 20, IsRequired = true, IsPriceImpacting = false, Status = 'Active'));
if (!exPcaAttr.contains(adByDev.get('COMEXI_RetrofitType').Id))
    toInsPca.add(new ProductClassificationAttr(ProductClassificationId = classPcId, AttributeDefinitionId = adByDev.get('COMEXI_RetrofitType').Id, Name = 'Tipus de retrofit', Sequence = 30, IsRequired = false, IsPriceImpacting = false, DisplayType = 'RadioButton', Status = 'Active'));
if (!toInsPca.isEmpty()) insert toInsPca;

System.debug('01_catalog OK. Catalog=' + cat.Id + ' classes=' + pcByCode.size() + ' attrs=' + adByDev.size());
