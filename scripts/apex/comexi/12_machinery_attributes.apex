// 12_machinery_attributes.apex — ProductAttributeDefinition (fichas tecnicas) para los
// modelos de Comexi Maquinaria. Valores literales de comexi.com en DefaultValue, solo lectura.
// Idempotente por Product2Id|AttributeDefinitionId. Requiere 10 y 11. Ver build-spec/10 §5.

// ---------- Lookups ----------
Map<String, Id> prodBySku = new Map<String, Id>();
Map<String, Id> classByProd = new Map<String, Id>();  // sku -> classificationId (BasedOnId)
for (Product2 p : [SELECT Id, StockKeepingUnit, BasedOnId FROM Product2 WHERE StockKeepingUnit LIKE 'MAQ-%']) {
    prodBySku.put(p.StockKeepingUnit, p.Id);
    if (p.BasedOnId != null) classByProd.put(p.StockKeepingUnit, p.BasedOnId);
}
Map<String, Id> adByDev = new Map<String, Id>();
Map<String, String> adNameByDev = new Map<String, String>();
for (AttributeDefinition a : [SELECT Id, DeveloperName, Name FROM AttributeDefinition WHERE DeveloperName LIKE 'COMEXI_MAQ_%']) {
    adByDev.put(a.DeveloperName, a.Id);
    adNameByDev.put(a.DeveloperName, a.Name);
}

Set<Id> classIds = new Set<Id>(classByProd.values());
Map<String, Id> pcaByKey = new Map<String, Id>();  // classId|adId -> pcaId
for (ProductClassificationAttr a : [SELECT Id, ProductClassificationId, AttributeDefinitionId FROM ProductClassificationAttr WHERE ProductClassificationId IN :classIds]) {
    pcaByKey.put(a.ProductClassificationId + '|' + a.AttributeDefinitionId, a.Id);
}

// ---------- Ficha tecnica: SKU -> (dev -> valor literal de la web) ----------
Map<String, Map<String, String>> spec = new Map<String, Map<String, String>>();
spec.put('MAQ-F1-EVO', new Map<String, String>{
    'COMEXI_MAQ_Colours' => '10/8', 'COMEXI_MAQ_Speed' => '600 m/min',
    'COMEXI_MAQ_WebWidth' => '1320 - 1520 - 1720 mm', 'COMEXI_MAQ_MinRepeat' => '400-450 mm',
    'COMEXI_MAQ_MaxRepeat' => '920 - 1260 mm' });
spec.put('MAQ-F2-ML', new Map<String, String>{
    'COMEXI_MAQ_Colours' => '8 / 10', 'COMEXI_MAQ_Speed' => '400 / 500 m/min',
    'COMEXI_MAQ_PrintingWidth' => '870/1070/1270/1470 mm', 'COMEXI_MAQ_MinRepeat' => '330/350/380/400 mm',
    'COMEXI_MAQ_MaxRepeat' => '1160 mm' });
spec.put('MAQ-F2-ORIGIN', new Map<String, String>{
    'COMEXI_MAQ_Colours' => '8', 'COMEXI_MAQ_Speed' => '400 m/min',
    'COMEXI_MAQ_PrintingWidth' => '870/1070/1270 mm', 'COMEXI_MAQ_MinRepeat' => '330/350/380 mm',
    'COMEXI_MAQ_MaxRepeat' => '800 mm' });
spec.put('MAQ-F2-MB', new Map<String, String>{
    'COMEXI_MAQ_Colours' => '8', 'COMEXI_MAQ_Speed' => '400 m/min', 'COMEXI_MAQ_MaxRepeat' => '800 mm' });
spec.put('MAQ-F4-ORIGIN', new Map<String, String>{
    'COMEXI_MAQ_Colours' => '8', 'COMEXI_MAQ_Speed' => '400 m/min',
    'COMEXI_MAQ_PrintingWidth' => '670/870/1070 mm', 'COMEXI_MAQ_MinRepeat' => 'Starting from 240 mm',
    'COMEXI_MAQ_MaxRepeat' => '600 mm', 'COMEXI_MAQ_Dimensions' => '9.78x5.62x4.28 m' });
spec.put('MAQ-OFFSET-CI-EVO', new Map<String, String>{
    'COMEXI_MAQ_Colours' => '8 (7 Offset EB + 1 Flexo EB)', 'COMEXI_MAQ_Speed' => '300 m/min',
    'COMEXI_MAQ_WebWidth' => '1100 mm', 'COMEXI_MAQ_PrintingWidth' => '1050 mm',
    'COMEXI_MAQ_MinRepeat' => '455 mm', 'COMEXI_MAQ_MaxRepeat' => '930 mm' });
spec.put('MAQ-DIGIFLEX', new Map<String, String>{
    'COMEXI_MAQ_WebWidth' => '1320 mm', 'COMEXI_MAQ_PrintingWidth' => '1250 mm',
    'COMEXI_MAQ_NumberOfLines' => 'From 1 to 12 lanes', 'COMEXI_MAQ_Speed' => 'Up to 220 m/min \u2013 Grade B',
    'COMEXI_MAQ_Inks' => 'UV Low Migration - Black', 'COMEXI_MAQ_Resolution' => 'Up to 1200 x 1200 dpi',
    'COMEXI_MAQ_MaterialThickness' => 'From 12 to 200 \u03bc', 'COMEXI_MAQ_Dimensions' => '6.5 m x 3.7 m x 2.2 m' });
spec.put('MAQ-SL2-MB', new Map<String, String>{
    'COMEXI_MAQ_Adhesive' => 'SL', 'COMEXI_MAQ_Speed' => '400 m/min', 'COMEXI_MAQ_WebWidth' => '1330 mm',
    'COMEXI_MAQ_MaxReelDiameter' => '1000 mm', 'COMEXI_MAQ_MaxReelWeight' => '1000 kg',
    'COMEXI_MAQ_UWWebTension' => '20 - 200 N (Opt 500 N)', 'COMEXI_MAQ_RWWebTension' => '40 - 350 N (Opt 550 N)' });
spec.put('MAQ-SL2-EVO', new Map<String, String>{
    'COMEXI_MAQ_Adhesive' => 'SL', 'COMEXI_MAQ_Speed' => '500 m/min', 'COMEXI_MAQ_WebWidth' => '930/1330/1530 mm',
    'COMEXI_MAQ_MaxReelDiameter' => '1000 - 1200 mm', 'COMEXI_MAQ_MaxReelWeight' => '1000 - 1500 kg',
    'COMEXI_MAQ_UWWebTension' => '20 - 500 N', 'COMEXI_MAQ_RWWebTension' => '40 - 500 N',
    'COMEXI_MAQ_AutReelChange' => 'RW + UW' });
spec.put('MAQ-ML2-EVO', new Map<String, String>{
    'COMEXI_MAQ_Adhesive' => 'SB/SL/WB/UV', 'COMEXI_MAQ_Speed' => '450 m/min', 'COMEXI_MAQ_WebWidth' => '1330/1530 mm',
    'COMEXI_MAQ_MaxReelDiameter' => '1000 mm', 'COMEXI_MAQ_MaxReelWeight' => '1500 kg',
    'COMEXI_MAQ_UWWebTension' => '20 - 500 N', 'COMEXI_MAQ_RWWebTension' => '30 - 500 N',
    'COMEXI_MAQ_AutReelChange' => 'RW + UW' });
spec.put('MAQ-ML1-EVO', new Map<String, String>{
    'COMEXI_MAQ_Adhesive' => 'SB/SL/WB', 'COMEXI_MAQ_Speed' => '450 m/min', 'COMEXI_MAQ_WebWidth' => '1330/1530 mm',
    'COMEXI_MAQ_MaxReelDiameter' => '1000 mm', 'COMEXI_MAQ_MaxReelWeight' => '1250 kg',
    'COMEXI_MAQ_AutReelChange' => 'RW + UW' });
spec.put('MAQ-LASER', new Map<String, String>{
    'COMEXI_MAQ_LaserPower' => '40 / 100 / 300 W', 'COMEXI_MAQ_LaserHeads' => 'from 2 to 10',
    'COMEXI_MAQ_Wavelength' => '10.2 \u03bcm', 'COMEXI_MAQ_SpotSize' => 'from 50 to 500 \u03bcm',
    'COMEXI_MAQ_LaserSource' => 'Co2', 'COMEXI_MAQ_Speed' => '700 m/min', 'COMEXI_MAQ_CoolingSystem' => 'Air / Water' });
spec.put('MAQ-S1-DT', new Map<String, String>{
    'COMEXI_MAQ_Speed' => '800 m/min', 'COMEXI_MAQ_MaterialWidth' => '900 to 1700 mm',
    'COMEXI_MAQ_SlittingWidth' => '20 mm', 'COMEXI_MAQ_RewindingSystem' => 'Double Turret',
    'COMEXI_MAQ_FinishedRollDiameter' => '650 mm', 'COMEXI_MAQ_AccelerationRamps' => '20 sec',
    'COMEXI_MAQ_TurretRotation' => '20 sec', 'COMEXI_MAQ_RewinderSystemType' => 'Bi - ALTS' });
spec.put('MAQ-S1-DS', new Map<String, String>{
    'COMEXI_MAQ_Speed' => '800 m/min', 'COMEXI_MAQ_MaterialWidth' => '900 to 2100 mm',
    'COMEXI_MAQ_ParentRoll' => '1300 (2T) / 1500 (3T) mm', 'COMEXI_MAQ_WebPath' => 'Overhead',
    'COMEXI_MAQ_SlittingWidth' => '20 mm', 'COMEXI_MAQ_RewindingSystem' => 'Duplex',
    'COMEXI_MAQ_FinishedRollDiameter' => '800 mm', 'COMEXI_MAQ_AccelerationRamps' => '20 sec',
    'COMEXI_MAQ_RewinderSystemType' => 'Bi - ALTS' });
spec.put('MAQ-S2-DT', new Map<String, String>{
    'COMEXI_MAQ_Speed' => '500 m/min', 'COMEXI_MAQ_MaterialWidth' => '900 to 1700 mm',
    'COMEXI_MAQ_ParentRoll' => '1000 mm (1T)', 'COMEXI_MAQ_WebPath' => 'Integrate/Compact',
    'COMEXI_MAQ_SlittingWidth' => '40 mm', 'COMEXI_MAQ_RewindingSystem' => 'Turret',
    'COMEXI_MAQ_FinishedRollDiameter' => '610 mm', 'COMEXI_MAQ_AccelerationRamps' => '60 sec',
    'COMEXI_MAQ_TurretRotation' => '35 sec', 'COMEXI_MAQ_RewinderSystemType' => 'Mono - ALTS' });
spec.put('MAQ-S2-DS', new Map<String, String>{
    'COMEXI_MAQ_Speed' => '500 m/min', 'COMEXI_MAQ_MaterialWidth' => '900 to 1700 mm',
    'COMEXI_MAQ_ParentRoll' => '1000 mm (1T)', 'COMEXI_MAQ_WebPath' => 'Integrate/ Compact',
    'COMEXI_MAQ_SlittingWidth' => '40 mm', 'COMEXI_MAQ_RewindingSystem' => 'Duplex',
    'COMEXI_MAQ_FinishedRollDiameter' => '610 mm', 'COMEXI_MAQ_AccelerationRamps' => '60 sec',
    'COMEXI_MAQ_RewinderSystemType' => 'Mono - ALTS' });
spec.put('MAQ-S1-MS', new Map<String, String>{
    'COMEXI_MAQ_Speed' => '600 m/min', 'COMEXI_MAQ_MaterialWidth' => '1400 to 2100 mm',
    'COMEXI_MAQ_ParentRoll' => '1300 (2T) / 1500 (3T) mm', 'COMEXI_MAQ_WebPath' => 'Underneath',
    'COMEXI_MAQ_SlittingWidth' => '50 mm rigid or semirigid & 300 mm elastic material',
    'COMEXI_MAQ_RewindingSystem' => 'Monoshaft', 'COMEXI_MAQ_FinishedRollDiameter' => '1300 mm',
    'COMEXI_MAQ_AccelerationRamps' => '60 sec' });
spec.put('MAQ-S1-MT', new Map<String, String>{
    'COMEXI_MAQ_Speed' => '600 m/min', 'COMEXI_MAQ_MaterialWidth' => '1400 to 2100 mm',
    'COMEXI_MAQ_ParentRoll' => '1300 (2T) / 1500 (3T) mm', 'COMEXI_MAQ_WebPath' => 'Underneath',
    'COMEXI_MAQ_SlittingWidth' => '50 mm rigid or semirigid & 300 mm elastic material',
    'COMEXI_MAQ_RewindingSystem' => 'Turret', 'COMEXI_MAQ_FinishedRollDiameter' => '1000 mm',
    'COMEXI_MAQ_AccelerationRamps' => '60 sec', 'COMEXI_MAQ_TurretRotation' => '35 sec' });
spec.put('MAQ-DM1', new Map<String, String>{
    'COMEXI_MAQ_Speed' => '600 m/min', 'COMEXI_MAQ_WebWidth' => '1700 mm',
    'COMEXI_MAQ_MaxInputReelOD' => '1000 mm', 'COMEXI_MAQ_MaxOutputReelOD' => '1000 mm',
    'COMEXI_MAQ_SpliceTable' => 'Yes', 'COMEXI_MAQ_BothDirRewinding' => 'Yes',
    'COMEXI_MAQ_MaxRewinderWeight' => '1500 kg' });
spec.put('MAQ-S4-ENERGY', new Map<String, String>{
    'COMEXI_MAQ_Speed' => 'from 20 to 150 m/min', 'COMEXI_MAQ_MaxInputReelOD' => '600 mm',
    'COMEXI_MAQ_FoilThickness' => '6 \u2013 15 \u00b5', 'COMEXI_MAQ_CoatingThickness' => '30-110\u00b5 (each side) (continuous or intermittent)',
    'COMEXI_MAQ_RewinderType' => 'Duplex', 'COMEXI_MAQ_MaxOutputReelOD' => '600 mm',
    'COMEXI_MAQ_SlittingMethod' => 'Shear Cutting', 'COMEXI_MAQ_QuickKnives' => 'Yes',
    'COMEXI_MAQ_MaxRewinderWeight' => '2 x 400 kg', 'COMEXI_MAQ_MaxBurrSize' => '<5\u00b5',
    'COMEXI_MAQ_SlittingAlignment' => '0.1 mm' });
spec.put('MAQ-S2-ENERGY', new Map<String, String>{
    'COMEXI_MAQ_Speed' => 'from 20 to 150 m/min', 'COMEXI_MAQ_MaxInputReelOD' => '1000 mm',
    'COMEXI_MAQ_FoilThickness' => '6 \u2013 15 \u00b5', 'COMEXI_MAQ_CoatingThickness' => '30-110\u00b5 (each side) (continuous or intermittent)',
    'COMEXI_MAQ_RewinderType' => 'Duplex', 'COMEXI_MAQ_MaxOutputReelOD' => '800 mm',
    'COMEXI_MAQ_SlittingMethod' => 'Shear Cutting', 'COMEXI_MAQ_QuickKnives' => 'Yes',
    'COMEXI_MAQ_MaxRewinderWeight' => '2 x 400 kg', 'COMEXI_MAQ_MaxBurrSize' => '<5\u00b5',
    'COMEXI_MAQ_SlittingAlignment' => '0.1 mm' });
spec.put('MAQ-ENERGY-WINDERS', new Map<String, String>{
    'COMEXI_MAQ_Speed' => 'up to 600 m/min', 'COMEXI_MAQ_ReelDiameter' => 'up to 1,000 mm',
    'COMEXI_MAQ_MaximumWidth' => 'up to 1,520 mm', 'COMEXI_MAQ_MaxReelWeight' => '1,250 kg',
    'COMEXI_MAQ_InsideCoreDiameter' => '3" and 6"' });

// ---------- Idempotencia: PAD existentes por Product2Id|AttributeDefinitionId ----------
Set<Id> prodIds = new Set<Id>(prodBySku.values());
Map<String, ProductAttributeDefinition> exPad = new Map<String, ProductAttributeDefinition>();
for (ProductAttributeDefinition x : [SELECT Id, Product2Id, AttributeDefinitionId, DefaultValue FROM ProductAttributeDefinition WHERE Product2Id IN :prodIds]) {
    exPad.put(x.Product2Id + '|' + x.AttributeDefinitionId, x);
}

List<ProductAttributeDefinition> toIns = new List<ProductAttributeDefinition>();
List<ProductAttributeDefinition> toUpd = new List<ProductAttributeDefinition>();
Integer skipped = 0;
for (String sku : spec.keySet()) {
    Id prodId = prodBySku.get(sku);
    Id classId = classByProd.get(sku);
    if (prodId == null || classId == null) { skipped++; continue; }
    Integer seq = 10;
    for (String dev : spec.get(sku).keySet()) {
        Id adId = adByDev.get(dev);
        Id pcaId = (adId == null) ? null : pcaByKey.get(classId + '|' + adId);
        String val = spec.get(sku).get(dev);
        if (adId == null || pcaId == null) { skipped++; seq += 10; continue; }
        String key = prodId + '|' + adId;
        if (exPad.containsKey(key)) {
            ProductAttributeDefinition cur = exPad.get(key);
            if (cur.DefaultValue != val) toUpd.add(new ProductAttributeDefinition(Id = cur.Id, DefaultValue = val));
        } else {
            toIns.add(new ProductAttributeDefinition(
                Name = adNameByDev.get(dev), Product2Id = prodId, AttributeDefinitionId = adId,
                ProductClassificationAttributeId = pcaId, DefaultValue = val, IsReadOnly = true,
                IsRequired = false, IsPriceImpacting = false, DisplayType = 'Text', Status = 'Active', Sequence = seq));
        }
        seq += 10;
    }
}
if (!toIns.isEmpty()) insert toIns;
if (!toUpd.isEmpty()) update toUpd;

System.debug('12_machinery_attributes OK. newPAD=' + toIns.size() + ' updPAD=' + toUpd.size() + ' skipped=' + skipped);
