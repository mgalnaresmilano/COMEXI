// 05_constraint_assoc.apex — Asociaciones ExpressionSetConstraintObj para COMEXI_T100
// Ver build-spec/03-configurador-cml.md §2
//
// PREREQUISITO: el modelo COMEXI_T100.cml debe estar IMPORTADO (ExpressionSet
// UsageType=Constraint provisionado y su blob compilado). El import del blob es
// un paso del compilador de constraints del org (cci task run import_cml con un
// data_dir exportado, o guardar/activar el modelo en el Product Configurator).
// Este script es idempotente y se salta con un mensaje claro si el ExpressionSet
// aun no existe, de modo que puede ejecutarse tras el import.

List<ExpressionSet> es = [SELECT Id, Name, ApiName FROM ExpressionSet
    WHERE (ApiName = 'COMEXI_T100' OR Name = 'COMEXI_T100') LIMIT 1];
if (es.isEmpty()) {
    System.debug(LoggingLevel.WARN, '05_constraint_assoc: ExpressionSet COMEXI_T100 no encontrado. ' +
        'Importa primero el modelo CML (import_cml / Configurator) y reejecuta este script.');
    return;
}
Id esId = es[0].Id;

// tag CML -> SKU del Product2
Map<String, String> tagToSku = new Map<String, String>{
    'T100UpdatePC'   => 'T100',
    'UpdateBase'     => 'T100-W11',
    'CpuSimotion'    => 'T100-CPU-SIM',
    'CuSinamics'     => 'T100-CU-SIN',
    'PupitreHMI'     => 'T100-HMI',
    'CanviPantalla'  => 'T100-SCREEN',
    'ChecklistSerie' => 'T100-CHECKLIST'
};
Map<String, Id> prodBySku = new Map<String, Id>();
for (Product2 p : [SELECT Id, StockKeepingUnit FROM Product2 WHERE StockKeepingUnit IN :tagToSku.values()]) prodBySku.put(p.StockKeepingUnit, p.Id);

Set<String> exTags = new Set<String>();
for (ExpressionSetConstraintObj x : [SELECT ConstraintModelTag FROM ExpressionSetConstraintObj WHERE ExpressionSetId = :esId]) exTags.add(x.ConstraintModelTag);

List<ExpressionSetConstraintObj> toIns = new List<ExpressionSetConstraintObj>();
for (String tag : tagToSku.keySet()) {
    if (exTags.contains(tag)) continue;
    Id refId = prodBySku.get(tagToSku.get(tag));
    if (refId == null) continue;
    toIns.add(new ExpressionSetConstraintObj(ExpressionSetId = esId, ConstraintModelTag = tag,
        ConstraintModelTagType = 'Type', ReferenceObjectId = refId));
}
if (!toIns.isEmpty()) insert toIns;

System.debug('05_constraint_assoc OK. ExpressionSet=' + esId + ' newESC=' + toIns.size());
