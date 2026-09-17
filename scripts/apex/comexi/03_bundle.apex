// 03_bundle.apex — Estructura del bundle T100 + atributos del producto (Comexi)
// Idempotente. Ver build-spec/01-catalogo-atributos.md §5,§6
// Requiere 01_catalog.apex y 02_products.apex.

Map<String, Id> prodBySku = new Map<String, Id>();
for (Product2 p : [SELECT Id, StockKeepingUnit FROM Product2 WHERE StockKeepingUnit LIKE 'T100%']) prodBySku.put(p.StockKeepingUnit, p.Id);
Id t100 = prodBySku.get('T100');
Id relTypeId = [SELECT Id FROM ProductRelationshipType WHERE Name = 'Bundle to Bundle Component Relationship' LIMIT 1].Id;

// ---------- ProductComponentGroup ----------
Map<String, ProductComponentGroup> pcgByCode = new Map<String, ProductComponentGroup>();
for (ProductComponentGroup g : [SELECT Id, Code FROM ProductComponentGroup WHERE ParentProductId = :t100]) pcgByCode.put(g.Code, g);
List<ProductComponentGroup> toInsPcg = new List<ProductComponentGroup>();
if (!pcgByCode.containsKey('T100_CORE'))
    toInsPcg.add(new ProductComponentGroup(Code = 'T100_CORE', Name = 'Actualitzacio base', ParentProductId = t100, MinBundleComponents = 1, MaxBundleComponents = 1, Sequence = 1));
if (!pcgByCode.containsKey('T100_OPTIONS'))
    toInsPcg.add(new ProductComponentGroup(Code = 'T100_OPTIONS', Name = 'Opcionals', ParentProductId = t100, MinBundleComponents = 0, MaxBundleComponents = 5, Sequence = 2));
if (!toInsPcg.isEmpty()) { insert toInsPcg; for (ProductComponentGroup g : toInsPcg) pcgByCode.put(g.Code, g); }

// ---------- ProductRelatedComponent ----------
// child SKU => {group, required, default}
Map<String, String> childGroup = new Map<String, String>{
    'T100-W11' => 'T100_CORE', 'T100-CPU-SIM' => 'T100_OPTIONS', 'T100-CU-SIN' => 'T100_OPTIONS',
    'T100-HMI' => 'T100_OPTIONS', 'T100-SCREEN' => 'T100_OPTIONS', 'T100-CHECKLIST' => 'T100_OPTIONS'
};
Set<String> req = new Set<String>{ 'T100-W11' };
Set<Id> exChild = new Set<Id>();
for (ProductRelatedComponent x : [SELECT ChildProductId FROM ProductRelatedComponent WHERE ParentProductId = :t100]) exChild.add(x.ChildProductId);
List<ProductRelatedComponent> toInsPrc = new List<ProductRelatedComponent>();
Integer prcSeq = 1;
for (String sku : childGroup.keySet()) {
    Id childId = prodBySku.get(sku);
    if (childId == null || exChild.contains(childId)) { prcSeq++; continue; }
    toInsPrc.add(new ProductRelatedComponent(
        ParentProductId = t100, ChildProductId = childId,
        ProductComponentGroupId = pcgByCode.get(childGroup.get(sku)).Id,
        ProductRelationshipTypeId = relTypeId,
        QuoteVisibility = 'Always', Quantity = 1,
        IsComponentRequired = req.contains(sku), IsDefaultComponent = req.contains(sku),
        Sequence = prcSeq));
    prcSeq++;
}
if (!toInsPrc.isEmpty()) insert toInsPrc;

// ---------- ProductAttributeDefinition (T100) ----------
Map<String, Id> adByDev = new Map<String, Id>();
for (AttributeDefinition a : [SELECT Id, DeveloperName FROM AttributeDefinition WHERE DeveloperName IN ('COMEXI_Num_CPU_GL','COMEXI_Num_CU_Total','COMEXI_RetrofitType')]) adByDev.put(a.DeveloperName, a.Id);
Map<Id, Id> pcaByAd = new Map<Id, Id>();
Id classPcId = [SELECT Id FROM ProductClassification WHERE Code = 'PC_RETROFIT_PC' LIMIT 1].Id;
for (ProductClassificationAttr a : [SELECT Id, AttributeDefinitionId FROM ProductClassificationAttr WHERE ProductClassificationId = :classPcId]) pcaByAd.put(a.AttributeDefinitionId, a.Id);
Set<Id> exPad = new Set<Id>();
for (ProductAttributeDefinition x : [SELECT AttributeDefinitionId FROM ProductAttributeDefinition WHERE Product2Id = :t100]) exPad.add(x.AttributeDefinitionId);
List<ProductAttributeDefinition> toInsPad = new List<ProductAttributeDefinition>();
if (!exPad.contains(adByDev.get('COMEXI_Num_CPU_GL')))
    toInsPad.add(new ProductAttributeDefinition(Product2Id = t100, AttributeDefinitionId = adByDev.get('COMEXI_Num_CPU_GL'), ProductClassificationAttributeId = pcaByAd.get(adByDev.get('COMEXI_Num_CPU_GL')), Name = 'N. de CPUs GL', Sequence = 10, IsRequired = true, IsPriceImpacting = false, Status = 'Active'));
if (!exPad.contains(adByDev.get('COMEXI_Num_CU_Total')))
    toInsPad.add(new ProductAttributeDefinition(Product2Id = t100, AttributeDefinitionId = adByDev.get('COMEXI_Num_CU_Total'), ProductClassificationAttributeId = pcaByAd.get(adByDev.get('COMEXI_Num_CU_Total')), Name = 'N. de CUs totals', Sequence = 20, IsRequired = true, IsPriceImpacting = false, Status = 'Active'));
if (!exPad.contains(adByDev.get('COMEXI_RetrofitType')))
    toInsPad.add(new ProductAttributeDefinition(Product2Id = t100, AttributeDefinitionId = adByDev.get('COMEXI_RetrofitType'), ProductClassificationAttributeId = pcaByAd.get(adByDev.get('COMEXI_RetrofitType')), Name = 'Tipus de retrofit', Sequence = 30, IsRequired = false, IsPriceImpacting = true, DisplayType = 'RadioButton', Status = 'Active'));
if (!toInsPad.isEmpty()) insert toInsPad;

System.debug('03_bundle OK. groups=' + pcgByCode.size() + ' newPRC=' + toInsPrc.size() + ' newPAD=' + toInsPad.size());
