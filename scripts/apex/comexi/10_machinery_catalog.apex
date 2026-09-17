// 10_machinery_catalog.apex — Catalogo "Comexi Maquinaria": catalogo, categorias,
// clasificaciones y cadena de atributos. Idempotente y reejecutable sin duplicar.
// Ver build-spec/10-catalogo-maquinaria.md. Convive con COMEXI_SERVICE sin tocarlo.
// Todo prefijado: MAQ_* (categorias), PC_MAQ_* (clasificaciones), COMEXI_MAQ_* (atributos).

// ---------- 1. ProductCatalog ----------
ProductCatalog cat;
List<ProductCatalog> exCat = [SELECT Id FROM ProductCatalog WHERE Code = 'COMEXI_MACHINERY' LIMIT 1];
if (exCat.isEmpty()) {
    cat = new ProductCatalog(Name = 'Comexi Maquinaria', Code = 'COMEXI_MACHINERY',
        CatalogType = 'Sales', EffectiveStartDate = Date.newInstance(2020, 1, 1));
    insert cat;
} else {
    cat = exCat[0];
}
System.debug('Catalog: ' + cat.Id);

// ---------- 2. ProductCategory (12, jerarquicas) ----------
Map<String, ProductCategory> catByCode = new Map<String, ProductCategory>();
for (ProductCategory pc : [SELECT Id, Code FROM ProductCategory WHERE CatalogId = :cat.Id]) catByCode.put(pc.Code, pc);

// raices
Map<String, String> roots = new Map<String, String>{
    'MAQ_PRINT' => 'Impresion',
    'MAQ_LAMCOAT' => 'Laminacion y recubrimiento',
    'MAQ_SLITTING' => 'Corte, laser y manipulacion de bobinas',
    'MAQ_BATTERY' => 'Soluciones para baterias',
    'MAQ_CLOUD' => 'Comexi Cloud'
};
List<ProductCategory> toInsRoot = new List<ProductCategory>();
for (String code : roots.keySet()) {
    if (!catByCode.containsKey(code))
        toInsRoot.add(new ProductCategory(CatalogId = cat.Id, Code = code, Name = roots.get(code), IsNavigational = true));
}
if (!toInsRoot.isEmpty()) { insert toInsRoot; for (ProductCategory p : toInsRoot) catByCode.put(p.Code, p); }

// hijas: code => {name, parentCode}
Map<String, String> childName = new Map<String, String>{
    'MAQ_PRINT_FLEXO' => 'Maquinas de impresion flexografica',
    'MAQ_PRINT_OFFSET' => 'Maquinas de impresion offset',
    'MAQ_PRINT_DIGITAL' => 'Maquinas de impresion digital',
    'MAQ_LAM' => 'Maquinas de laminacion',
    'MAQ_COAT' => 'Lineas de recubrimiento',
    'MAQ_CUT' => 'Soluciones de corte y laser',
    'MAQ_REELHANDLING' => 'Manipulacion de bobinas'
};
Map<String, String> childParent = new Map<String, String>{
    'MAQ_PRINT_FLEXO' => 'MAQ_PRINT', 'MAQ_PRINT_OFFSET' => 'MAQ_PRINT', 'MAQ_PRINT_DIGITAL' => 'MAQ_PRINT',
    'MAQ_LAM' => 'MAQ_LAMCOAT', 'MAQ_COAT' => 'MAQ_LAMCOAT',
    'MAQ_CUT' => 'MAQ_SLITTING', 'MAQ_REELHANDLING' => 'MAQ_SLITTING'
};
List<ProductCategory> toInsChild = new List<ProductCategory>();
for (String code : childName.keySet()) {
    if (!catByCode.containsKey(code))
        toInsChild.add(new ProductCategory(CatalogId = cat.Id, Code = code, Name = childName.get(code),
            ParentCategoryId = catByCode.get(childParent.get(code)).Id, IsNavigational = true));
}
if (!toInsChild.isEmpty()) { insert toInsChild; for (ProductCategory p : toInsChild) catByCode.put(p.Code, p); }

// ---------- 3. ProductClassification (8) ----------
Map<String, String> classes = new Map<String, String>{
    'PC_MAQ_FLEXO' => 'Impresora flexografica',
    'PC_MAQ_OFFSET' => 'Impresora offset',
    'PC_MAQ_DIGITAL' => 'Impresora digital',
    'PC_MAQ_LAMINATOR' => 'Laminadora',
    'PC_MAQ_SLITTER' => 'Cortadora rebobinadora',
    'PC_MAQ_LASER' => 'Sistema laser',
    'PC_MAQ_BATTERY' => 'Solucion para baterias',
    'PC_MAQ_SOLUTION' => 'Solucion a medida'
};
Map<String, ProductClassification> pcByCode = new Map<String, ProductClassification>();
for (ProductClassification p : [SELECT Id, Code FROM ProductClassification WHERE Code IN :classes.keySet()]) pcByCode.put(p.Code, p);
List<ProductClassification> toInsPc = new List<ProductClassification>();
for (String code : classes.keySet()) {
    if (!pcByCode.containsKey(code))
        toInsPc.add(new ProductClassification(Code = code, Name = classes.get(code), Status = 'Active'));
}
if (!toInsPc.isEmpty()) { insert toInsPc; for (ProductClassification p : toInsPc) pcByCode.put(p.Code, p); }

// ---------- 4. AttributeCategory (5) ----------
Map<String, String> attrCats = new Map<String, String>{
    'MAQ_PRINTING' => 'Impresion', 'MAQ_LAMINATING' => 'Laminacion', 'MAQ_SLITTING' => 'Corte',
    'MAQ_LASER' => 'Laser', 'MAQ_BATTERY' => 'Baterias'
};
Map<String, AttributeCategory> acByCode = new Map<String, AttributeCategory>();
for (AttributeCategory a : [SELECT Id, Code FROM AttributeCategory WHERE Code IN :attrCats.keySet()]) acByCode.put(a.Code, a);
List<AttributeCategory> toInsAc = new List<AttributeCategory>();
for (String code : attrCats.keySet()) {
    if (!acByCode.containsKey(code)) toInsAc.add(new AttributeCategory(Code = code, Name = attrCats.get(code)));
}
if (!toInsAc.isEmpty()) { insert toInsAc; for (AttributeCategory a : toInsAc) acByCode.put(a.Code, a); }

// ---------- 5. AttributeDefinition (~47, DataType Text) ----------
// dev => label
Map<String, String> adLabel = new Map<String, String>{
    'COMEXI_MAQ_Speed' => 'Speed',
    'COMEXI_MAQ_Colours' => 'Colours', 'COMEXI_MAQ_WebWidth' => 'Web width',
    'COMEXI_MAQ_PrintingWidth' => 'Printing width', 'COMEXI_MAQ_MinRepeat' => 'Minimum repeat',
    'COMEXI_MAQ_MaxRepeat' => 'Maximum repeat', 'COMEXI_MAQ_Inks' => 'Inks',
    'COMEXI_MAQ_Resolution' => 'Resolution', 'COMEXI_MAQ_NumberOfLines' => 'Number of lines',
    'COMEXI_MAQ_MaterialThickness' => 'Material thickness', 'COMEXI_MAQ_Dimensions' => 'Dimensions',
    'COMEXI_MAQ_Adhesive' => 'Adhesive', 'COMEXI_MAQ_MaxReelDiameter' => 'Max. reel diameter',
    'COMEXI_MAQ_MaxReelWeight' => 'Max. reel weight', 'COMEXI_MAQ_UWWebTension' => 'UW web tension',
    'COMEXI_MAQ_RWWebTension' => 'RW web tension', 'COMEXI_MAQ_AutReelChange' => 'Aut. reel change',
    'COMEXI_MAQ_MaterialWidth' => 'Material width', 'COMEXI_MAQ_ParentRoll' => 'Parent roll diameter & weight',
    'COMEXI_MAQ_WebPath' => 'Web path', 'COMEXI_MAQ_SlittingWidth' => 'Slitting width',
    'COMEXI_MAQ_RewindingSystem' => 'Rewinding system', 'COMEXI_MAQ_FinishedRollDiameter' => 'Finished roll diameter',
    'COMEXI_MAQ_AccelerationRamps' => 'Acceleration ramps', 'COMEXI_MAQ_TurretRotation' => 'Turret rotation',
    'COMEXI_MAQ_RewinderSystemType' => 'Type of rewinder system', 'COMEXI_MAQ_MaxInputReelOD' => 'Max. input reel OD',
    'COMEXI_MAQ_MaxOutputReelOD' => 'Max. output reel OD', 'COMEXI_MAQ_SpliceTable' => 'Splice table',
    'COMEXI_MAQ_BothDirRewinding' => 'Both directions rewinding', 'COMEXI_MAQ_MaxRewinderWeight' => 'Max. rewinder weight',
    'COMEXI_MAQ_LaserPower' => 'Laser Power', 'COMEXI_MAQ_LaserHeads' => 'Laser heads',
    'COMEXI_MAQ_Wavelength' => 'Wavelength', 'COMEXI_MAQ_SpotSize' => 'Spot Size',
    'COMEXI_MAQ_LaserSource' => 'Laser source', 'COMEXI_MAQ_CoolingSystem' => 'Cooling system',
    'COMEXI_MAQ_FoilThickness' => 'Foil thickness', 'COMEXI_MAQ_CoatingThickness' => 'Coating thickness',
    'COMEXI_MAQ_RewinderType' => 'Rewinder type', 'COMEXI_MAQ_SlittingMethod' => 'Slitting method',
    'COMEXI_MAQ_QuickKnives' => 'Quick knives changeover', 'COMEXI_MAQ_MaxBurrSize' => 'Max. burr size',
    'COMEXI_MAQ_SlittingAlignment' => 'Slitting alignment', 'COMEXI_MAQ_ReelDiameter' => 'Reel diameter',
    'COMEXI_MAQ_MaximumWidth' => 'Maximum width', 'COMEXI_MAQ_InsideCoreDiameter' => 'Inside core diameter'
};
// dev => categoria de atributo (home, para AttributeCategoryAttribute)
Map<String, String> adCat = new Map<String, String>{
    'COMEXI_MAQ_Speed' => 'MAQ_PRINTING',
    'COMEXI_MAQ_Colours' => 'MAQ_PRINTING', 'COMEXI_MAQ_WebWidth' => 'MAQ_PRINTING',
    'COMEXI_MAQ_PrintingWidth' => 'MAQ_PRINTING', 'COMEXI_MAQ_MinRepeat' => 'MAQ_PRINTING',
    'COMEXI_MAQ_MaxRepeat' => 'MAQ_PRINTING', 'COMEXI_MAQ_Inks' => 'MAQ_PRINTING',
    'COMEXI_MAQ_Resolution' => 'MAQ_PRINTING', 'COMEXI_MAQ_NumberOfLines' => 'MAQ_PRINTING',
    'COMEXI_MAQ_MaterialThickness' => 'MAQ_PRINTING', 'COMEXI_MAQ_Dimensions' => 'MAQ_PRINTING',
    'COMEXI_MAQ_Adhesive' => 'MAQ_LAMINATING', 'COMEXI_MAQ_MaxReelDiameter' => 'MAQ_LAMINATING',
    'COMEXI_MAQ_MaxReelWeight' => 'MAQ_LAMINATING', 'COMEXI_MAQ_UWWebTension' => 'MAQ_LAMINATING',
    'COMEXI_MAQ_RWWebTension' => 'MAQ_LAMINATING', 'COMEXI_MAQ_AutReelChange' => 'MAQ_LAMINATING',
    'COMEXI_MAQ_MaterialWidth' => 'MAQ_SLITTING', 'COMEXI_MAQ_ParentRoll' => 'MAQ_SLITTING',
    'COMEXI_MAQ_WebPath' => 'MAQ_SLITTING', 'COMEXI_MAQ_SlittingWidth' => 'MAQ_SLITTING',
    'COMEXI_MAQ_RewindingSystem' => 'MAQ_SLITTING', 'COMEXI_MAQ_FinishedRollDiameter' => 'MAQ_SLITTING',
    'COMEXI_MAQ_AccelerationRamps' => 'MAQ_SLITTING', 'COMEXI_MAQ_TurretRotation' => 'MAQ_SLITTING',
    'COMEXI_MAQ_RewinderSystemType' => 'MAQ_SLITTING', 'COMEXI_MAQ_MaxInputReelOD' => 'MAQ_SLITTING',
    'COMEXI_MAQ_MaxOutputReelOD' => 'MAQ_SLITTING', 'COMEXI_MAQ_SpliceTable' => 'MAQ_SLITTING',
    'COMEXI_MAQ_BothDirRewinding' => 'MAQ_SLITTING', 'COMEXI_MAQ_MaxRewinderWeight' => 'MAQ_SLITTING',
    'COMEXI_MAQ_LaserPower' => 'MAQ_LASER', 'COMEXI_MAQ_LaserHeads' => 'MAQ_LASER',
    'COMEXI_MAQ_Wavelength' => 'MAQ_LASER', 'COMEXI_MAQ_SpotSize' => 'MAQ_LASER',
    'COMEXI_MAQ_LaserSource' => 'MAQ_LASER', 'COMEXI_MAQ_CoolingSystem' => 'MAQ_LASER',
    'COMEXI_MAQ_FoilThickness' => 'MAQ_BATTERY', 'COMEXI_MAQ_CoatingThickness' => 'MAQ_BATTERY',
    'COMEXI_MAQ_RewinderType' => 'MAQ_BATTERY', 'COMEXI_MAQ_SlittingMethod' => 'MAQ_BATTERY',
    'COMEXI_MAQ_QuickKnives' => 'MAQ_BATTERY', 'COMEXI_MAQ_MaxBurrSize' => 'MAQ_BATTERY',
    'COMEXI_MAQ_SlittingAlignment' => 'MAQ_BATTERY', 'COMEXI_MAQ_ReelDiameter' => 'MAQ_BATTERY',
    'COMEXI_MAQ_MaximumWidth' => 'MAQ_BATTERY', 'COMEXI_MAQ_InsideCoreDiameter' => 'MAQ_BATTERY'
};
Map<String, AttributeDefinition> adByDev = new Map<String, AttributeDefinition>();
for (AttributeDefinition a : [SELECT Id, DeveloperName FROM AttributeDefinition WHERE DeveloperName IN :adLabel.keySet()]) adByDev.put(a.DeveloperName, a);
List<AttributeDefinition> toInsAd = new List<AttributeDefinition>();
for (String dev : adLabel.keySet()) {
    if (!adByDev.containsKey(dev))
        toInsAd.add(new AttributeDefinition(Name = adLabel.get(dev), DeveloperName = dev, Label = adLabel.get(dev),
            Code = dev, DataType = 'Text', IsActive = true));
}
if (!toInsAd.isEmpty()) { insert toInsAd; for (AttributeDefinition a : toInsAd) adByDev.put(a.DeveloperName, a); }

// ---------- 6. AttributeCategoryAttribute (dev -> categoria home) ----------
Set<Id> acIds = new Set<Id>();
for (AttributeCategory a : acByCode.values()) acIds.add(a.Id);
Set<String> exAca = new Set<String>();
for (AttributeCategoryAttribute a : [SELECT AttributeCategoryId, AttributeDefinitionId FROM AttributeCategoryAttribute WHERE AttributeCategoryId IN :acIds]) {
    exAca.add(a.AttributeCategoryId + '|' + a.AttributeDefinitionId);
}
List<AttributeCategoryAttribute> toInsAca = new List<AttributeCategoryAttribute>();
for (String dev : adCat.keySet()) {
    Id acId = acByCode.get(adCat.get(dev)).Id;
    Id adId = adByDev.get(dev).Id;
    if (!exAca.contains(acId + '|' + adId))
        toInsAca.add(new AttributeCategoryAttribute(AttributeCategoryId = acId, AttributeDefinitionId = adId));
}
if (!toInsAca.isEmpty()) insert toInsAca;

// ---------- 7. ProductClassificationAttr (union de atributos por familia) ----------
List<String> printingAll = new List<String>{
    'COMEXI_MAQ_Colours','COMEXI_MAQ_Speed','COMEXI_MAQ_WebWidth','COMEXI_MAQ_PrintingWidth',
    'COMEXI_MAQ_MinRepeat','COMEXI_MAQ_MaxRepeat','COMEXI_MAQ_Inks','COMEXI_MAQ_Resolution',
    'COMEXI_MAQ_NumberOfLines','COMEXI_MAQ_MaterialThickness','COMEXI_MAQ_Dimensions'
};
Map<String, List<String>> classAttrs = new Map<String, List<String>>{
    'PC_MAQ_FLEXO' => printingAll,
    'PC_MAQ_OFFSET' => printingAll,
    'PC_MAQ_DIGITAL' => printingAll,
    'PC_MAQ_LAMINATOR' => new List<String>{
        'COMEXI_MAQ_Speed','COMEXI_MAQ_WebWidth','COMEXI_MAQ_Adhesive','COMEXI_MAQ_MaxReelDiameter',
        'COMEXI_MAQ_MaxReelWeight','COMEXI_MAQ_UWWebTension','COMEXI_MAQ_RWWebTension','COMEXI_MAQ_AutReelChange'
    },
    'PC_MAQ_SLITTER' => new List<String>{
        'COMEXI_MAQ_Speed','COMEXI_MAQ_WebWidth','COMEXI_MAQ_MaterialWidth','COMEXI_MAQ_ParentRoll',
        'COMEXI_MAQ_WebPath','COMEXI_MAQ_SlittingWidth','COMEXI_MAQ_RewindingSystem','COMEXI_MAQ_FinishedRollDiameter',
        'COMEXI_MAQ_AccelerationRamps','COMEXI_MAQ_TurretRotation','COMEXI_MAQ_RewinderSystemType',
        'COMEXI_MAQ_MaxInputReelOD','COMEXI_MAQ_MaxOutputReelOD','COMEXI_MAQ_SpliceTable',
        'COMEXI_MAQ_BothDirRewinding','COMEXI_MAQ_MaxRewinderWeight'
    },
    'PC_MAQ_LASER' => new List<String>{
        'COMEXI_MAQ_LaserPower','COMEXI_MAQ_LaserHeads','COMEXI_MAQ_Wavelength','COMEXI_MAQ_SpotSize',
        'COMEXI_MAQ_LaserSource','COMEXI_MAQ_Speed','COMEXI_MAQ_CoolingSystem'
    },
    'PC_MAQ_BATTERY' => new List<String>{
        'COMEXI_MAQ_Speed','COMEXI_MAQ_MaxInputReelOD','COMEXI_MAQ_MaxOutputReelOD','COMEXI_MAQ_MaxRewinderWeight',
        'COMEXI_MAQ_MaxReelWeight','COMEXI_MAQ_FoilThickness','COMEXI_MAQ_CoatingThickness','COMEXI_MAQ_RewinderType',
        'COMEXI_MAQ_SlittingMethod','COMEXI_MAQ_QuickKnives','COMEXI_MAQ_MaxBurrSize','COMEXI_MAQ_SlittingAlignment',
        'COMEXI_MAQ_ReelDiameter','COMEXI_MAQ_MaximumWidth','COMEXI_MAQ_InsideCoreDiameter'
    }
};
Set<Id> classIds = new Set<Id>();
for (String c : classAttrs.keySet()) classIds.add(pcByCode.get(c).Id);
Set<String> exPca = new Set<String>();
for (ProductClassificationAttr a : [SELECT ProductClassificationId, AttributeDefinitionId FROM ProductClassificationAttr WHERE ProductClassificationId IN :classIds]) {
    exPca.add(a.ProductClassificationId + '|' + a.AttributeDefinitionId);
}
List<ProductClassificationAttr> toInsPca = new List<ProductClassificationAttr>();
for (String classCode : classAttrs.keySet()) {
    Id classId = pcByCode.get(classCode).Id;
    Integer seq = 10;
    for (String dev : classAttrs.get(classCode)) {
        Id adId = adByDev.get(dev).Id;
        if (!exPca.contains(classId + '|' + adId)) {
            toInsPca.add(new ProductClassificationAttr(ProductClassificationId = classId, AttributeDefinitionId = adId,
                Name = adLabel.get(dev), Sequence = seq, IsRequired = false, IsPriceImpacting = false,
                DisplayType = 'Text', Status = 'Active'));
        }
        seq += 10;
    }
}
if (!toInsPca.isEmpty()) insert toInsPca;

System.debug('10_machinery_catalog OK. catalog=' + cat.Id + ' categories=' + catByCode.size()
    + ' classes=' + pcByCode.size() + ' attrCats=' + acByCode.size() + ' attrs=' + adByDev.size()
    + ' newACA=' + toInsAca.size() + ' newPCA=' + toInsPca.size());
