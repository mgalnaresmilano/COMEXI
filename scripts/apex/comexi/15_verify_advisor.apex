// 15_verify_advisor.apex — verifica el COMEXI Retrofit Advisor de la escena 02.
// Idempotente: la segunda pasada debe reutilizar la oferta, no duplicarla.

Id caseId = [SELECT Id FROM Case WHERE CaseNumber = '00001003' LIMIT 1].Id;

// --- 1. Briefing ---
COMEXI_RetrofitAdvisorController.CaseBriefing b =
    COMEXI_RetrofitAdvisorController.getCaseBriefing(caseId);
System.debug('BRIEFING caso=' + b.caseNumber + ' | contacto=' + b.contactName
    + ' (' + b.contactTitle + ') | cuenta=' + b.accountName);
if (b.machine == null) {
    System.debug('AVISO: el caso no tiene asset vinculado, el panel de maquina saldra vacio.');
} else {
    System.debug('MAQUINA ' + b.machine.name + ' | ' + b.machine.productName
        + ' (' + b.machine.sku + ') | ano=' + b.machine.installYear
        + ' | antiguedad=' + b.machine.ageYears
        + ' | imagen=' + b.machine.imageUrl
        + ' | componentes=' + b.machine.components.size());
    for (COMEXI_RetrofitAdvisorController.MachineComponent c : b.machine.components) {
        System.debug('  - ' + c.name + ' | ' + c.productName
            + ' | enRiesgo=' + c.atRisk + ' | ' + c.config);
    }
}

// --- 2. Creacion ---
COMEXI_RetrofitAdvisorController.AdvisorResult r1 =
    COMEXI_RetrofitAdvisorController.createRetrofitOpportunityAndQuote(caseId);
System.debug('PASE 1 reutilizada=' + r1.alreadyExisted + ' | ' + r1.message);
System.debug('  quote=' + r1.quoteId + ' "' + r1.quoteName + '"'
    + ' | opp=' + r1.opportunityId
    + ' | total=' + r1.totalPrice + ' ' + r1.currencyCode
    + ' | coste=' + r1.totalCost
    + ' | margen=' + r1.marginPct + '%'
    + ' | descuento=' + r1.discountPct + '%'
    + ' | lineas=' + r1.lineCount
    + ' | calculo=' + r1.calculationStatus);

// --- 3. Idempotencia ---
COMEXI_RetrofitAdvisorController.AdvisorResult r2 =
    COMEXI_RetrofitAdvisorController.createRetrofitOpportunityAndQuote(caseId);
System.debug('PASE 2 reutilizada=' + r2.alreadyExisted + ' | mismaQuote='
    + (r1.quoteId == r2.quoteId) + ' | mismaOpp=' + (r1.opportunityId == r2.opportunityId));

// --- 4. Estructura de la oferta ---
Map<Id, String> groupNames = new Map<Id, String>();
for (QuoteLineGroup g : [SELECT Id, Name FROM QuoteLineGroup WHERE QuoteId = :r1.quoteId]) {
    groupNames.put(g.Id, g.Name);
}
System.debug('GRUPOS: ' + groupNames.values());
for (QuoteLineItem l : [
    SELECT Product2.StockKeepingUnit, Quantity, NetUnitPrice, TotalPrice,
           QuoteLineGroupId, COMEXI_Cost__c, COMEXI_Margin_Pct__c
    FROM QuoteLineItem WHERE QuoteId = :r1.quoteId
    ORDER BY QuoteLineGroupId, Product2.StockKeepingUnit
]) {
    System.debug('  [' + groupNames.get(l.QuoteLineGroupId) + '] '
        + l.Product2.StockKeepingUnit + ' x' + l.Quantity
        + ' | neto=' + l.NetUnitPrice + ' | total=' + l.TotalPrice
        + ' | coste=' + l.COMEXI_Cost__c + ' | margen=' + l.COMEXI_Margin_Pct__c + '%');
}

// --- 5. Sin duplicados ni cabeceras huerfanas ---
System.debug('Ofertas colgando de la oportunidad: '
    + [SELECT COUNT() FROM Quote WHERE OpportunityId = :r1.opportunityId]);
System.debug('Oportunidades vinculadas al caso: '
    + [SELECT COUNT() FROM Opportunity WHERE COMEXI_Source_Case__c = :caseId]);

// --- 6. Campos custom de retrofit de la oportunidad (escena 03) ---
Opportunity opp = [
    SELECT Name, RecordType.DeveloperName, Type, LeadSource, NextStep, StageName,
           Probability, Amount, CurrencyIsoCode,
           COMEXI_Target_Asset__c, COMEXI_Target_Asset__r.Name,
           COMEXI_Machine_Model__c, COMEXI_Machine_Age_Years__c,
           COMEXI_Obsolete_Component__c, COMEXI_Viability_Status__c,
           COMEXI_Needs_Engineering__c, COMEXI_Validated_By__c,
           COMEXI_Advisor_Run_Date__c, COMEXI_Advisor_Confidence__c,
           COMEXI_Retrofit_Type__c, COMEXI_Recommended_SKU__c,
           COMEXI_Intervention_Weeks__c, COMEXI_Planned_Intervention_Date__c,
           COMEXI_Down_Payment_Status__c, COMEXI_Quote_Total_Cost__c,
           COMEXI_Quote_Margin_Pct__c, COMEXI_Approval_Required__c
    FROM Opportunity WHERE Id = :r1.opportunityId
];
System.debug('OPP recordType=' + opp.RecordType.DeveloperName
    + ' | Type=' + opp.Type + ' | LeadSource=' + opp.LeadSource
    + ' | Amount=' + opp.Amount + ' ' + opp.CurrencyIsoCode
    + ' | Prob=' + opp.Probability + '%');
System.debug('  NextStep=' + opp.NextStep);
System.debug('  Maquina objetivo=' + opp.COMEXI_Target_Asset__r.Name
    + ' | modelo=' + opp.COMEXI_Machine_Model__c
    + ' | antiguedad=' + opp.COMEXI_Machine_Age_Years__c + ' anos'
    + ' | componente obsoleto=' + opp.COMEXI_Obsolete_Component__c);
System.debug('  Viabilidad=' + opp.COMEXI_Viability_Status__c
    + ' | ingenieria=' + opp.COMEXI_Needs_Engineering__c
    + ' | validado por=' + opp.COMEXI_Validated_By__c
    + ' | confianza=' + opp.COMEXI_Advisor_Confidence__c + '%'
    + ' | run=' + opp.COMEXI_Advisor_Run_Date__c);
System.debug('  Alcance: tipo=' + opp.COMEXI_Retrofit_Type__c
    + ' | SKU=' + opp.COMEXI_Recommended_SKU__c
    + ' | semanas=' + opp.COMEXI_Intervention_Weeks__c
    + ' | fecha intervencion=' + opp.COMEXI_Planned_Intervention_Date__c
    + ' | anticipo=' + opp.COMEXI_Down_Payment_Status__c);
System.debug('  Economico: coste=' + opp.COMEXI_Quote_Total_Cost__c
    + ' | margen=' + opp.COMEXI_Quote_Margin_Pct__c + '%'
    + ' | requiere aprobacion=' + opp.COMEXI_Approval_Required__c);

// --- 6b. Campos custom de retrofit de la oferta ---
Quote qf = [
    SELECT QuoteNumber, COMEXI_Source_Case__c, COMEXI_Target_Asset__r.Name,
           COMEXI_Machine_Model__c, COMEXI_Retrofit_Type__c, COMEXI_Retrofit_SKU__c,
           COMEXI_Generated_By_Advisor__c, COMEXI_Intervention_Site__c,
           COMEXI_Intervention_Country__c, COMEXI_Intervention_Weeks__c,
           COMEXI_Target_Intervention_Date__c, COMEXI_Intervention_Hours__c,
           COMEXI_Expenses_Owner__c, COMEXI_Warranty_Uplift_Pct__c, COMEXI_RALF_Pct__c,
           COMEXI_Country_Risk_Pct__c, COMEXI_Representative_Commission_Pct__c,
           COMEXI_Representative_Commission_Amount__c, COMEXI_Total_Cost__c,
           COMEXI_Margin_Amount__c, COMEXI_Blended_Margin_Pct__c, COMEXI_Discount_Pct__c,
           COMEXI_Margin_Threshold_Pct__c, COMEXI_Approval_Required__c,
           COMEXI_Down_Payment_Pct__c, COMEXI_Down_Payment_Amount__c,
           COMEXI_Down_Payment_Status__c, COMEXI_Offer_Version__c,
           COMEXI_Document_Language__c
    FROM Quote WHERE Id = :r1.quoteId
];
System.debug('QUOTE ' + qf.QuoteNumber + ' | caso=' + qf.COMEXI_Source_Case__c
    + ' | maquina=' + qf.COMEXI_Target_Asset__r.Name + ' | modelo=' + qf.COMEXI_Machine_Model__c
    + ' | tipo=' + qf.COMEXI_Retrofit_Type__c + ' | SKU=' + qf.COMEXI_Retrofit_SKU__c
    + ' | del Advisor=' + qf.COMEXI_Generated_By_Advisor__c);
System.debug('  Intervencion: ' + qf.COMEXI_Intervention_Site__c + ' ('
    + qf.COMEXI_Intervention_Country__c + ') | semanas=' + qf.COMEXI_Intervention_Weeks__c
    + ' | fecha=' + qf.COMEXI_Target_Intervention_Date__c
    + ' | horas=' + qf.COMEXI_Intervention_Hours__c
    + ' | gastos a cargo de=' + qf.COMEXI_Expenses_Owner__c);
System.debug('  Escandallo: uplift garantia=' + qf.COMEXI_Warranty_Uplift_Pct__c
    + '% | RALF=' + qf.COMEXI_RALF_Pct__c + '% | riesgo pais=' + qf.COMEXI_Country_Risk_Pct__c
    + '% | comision=' + qf.COMEXI_Representative_Commission_Pct__c + '% ('
    + qf.COMEXI_Representative_Commission_Amount__c + ')');
System.debug('  Margen: coste=' + qf.COMEXI_Total_Cost__c + ' | margen='
    + qf.COMEXI_Margin_Amount__c + ' (' + qf.COMEXI_Blended_Margin_Pct__c + '%) | descuento='
    + qf.COMEXI_Discount_Pct__c + '% | umbral=' + qf.COMEXI_Margin_Threshold_Pct__c
    + '% | requiere aprobacion=' + qf.COMEXI_Approval_Required__c);
System.debug('  Cierre: anticipo=' + qf.COMEXI_Down_Payment_Pct__c + '% ('
    + qf.COMEXI_Down_Payment_Amount__c + ') | estado=' + qf.COMEXI_Down_Payment_Status__c
    + ' | version=' + qf.COMEXI_Offer_Version__c
    + ' | idioma=' + qf.COMEXI_Document_Language__c);

// --- 7. Actividad copiada a la oportunidad (Activity) ---
Integer oppTasks = [SELECT COUNT() FROM Task WHERE WhatId = :r1.opportunityId];
Integer oppEvents = [SELECT COUNT() FROM Event WHERE WhatId = :r1.opportunityId];
System.debug('ACTIVITY en la oportunidad: tareas=' + oppTasks + ' | eventos=' + oppEvents);
for (Task t : [SELECT Subject, Status, TaskSubtype FROM Task
        WHERE WhatId = :r1.opportunityId ORDER BY Subject]) {
    System.debug('  TASK [' + t.Status + '] ' + t.Subject);
}
for (Event e : [SELECT Subject, StartDateTime FROM Event
        WHERE WhatId = :r1.opportunityId ORDER BY StartDateTime]) {
    System.debug('  EVENT ' + e.Subject + ' @ ' + e.StartDateTime);
}

// --- 8. La actividad del caso sigue intacta (no se movio, se copio) ---
System.debug('Tareas que siguen colgando del caso: '
    + [SELECT COUNT() FROM Task WHERE WhatId = :caseId]);

// --- 9. Circuito nativo de aprobacion listo para la escena 08 ---
// Los niveles no los decide el descuento mezclado de la oferta: los decide el descuento
// mas alto de una linea, que QuoteLineItem.RLM_Approval_Level_Calc__c traduce a nivel y
// Quote.RLM_Approval_Level__c consolida con MAX.
Quote qa = [
    SELECT QuoteNumber, RLM_Approval_Status__c, RLM_Approval_Level__c,
           RLM_Discount_Percent__c, COMEXI_Max_Line_Discount_Pct__c, RLM_Payment_Terms__c
    FROM Quote WHERE Id = :r1.quoteId
];
System.debug('APROBACION: nivel=' + qa.RLM_Approval_Level__c
    + ' | estado del path=' + qa.RLM_Approval_Status__c
    + ' | descuento mezclado=' + qa.RLM_Discount_Percent__c
    + '% | maximo de linea=' + qa.COMEXI_Max_Line_Discount_Pct__c
    + '% | condiciones de pago=' + qa.RLM_Payment_Terms__c);
if (qa.RLM_Payment_Terms__c != 'Net 30') {
    System.debug('  AVISO: fuera de Net 30 la orquestacion anade un nivel de Finance.');
}

// Sin pertenencia a los grupos publicos el work item se crea pero nadie lo ve en la
// pestana Approvals. Lo siembra 16_seed_approver_groups.apex.
Set<String> myGroups = new Set<String>();
for (GroupMember gm : [
    SELECT Group.DeveloperName FROM GroupMember
    WHERE UserOrGroupId = :UserInfo.getUserId()
      AND Group.DeveloperName IN ('Manager', 'Director', 'VP')
]) {
    myGroups.add(gm.Group.DeveloperName);
}
System.debug('APROBADOR ' + UserInfo.getName() + ' en grupos ' + myGroups
    + (myGroups.size() == 3 ? '' : ' | FALTA: ejecuta 16_seed_approver_groups.apex'));

// Estado tal y como lo va a pintar el banner de la cabecera.
COMEXI_QuoteApprovalController.ApprovalState st =
    COMEXI_QuoteApprovalController.getApprovalState(r1.quoteId);
System.debug('BANNER: estado=' + st.status + ' | niveles que exige=' + st.requiredLevels
    + ' | firmados=' + st.approvedLevels + ' | nivel en curso=' + st.stepLabel
    + ' | pendiente de=' + st.approverName + ' | puede enviar=' + st.canSubmit);

for (FlowOrchestrationWorkItem wi : [
    SELECT Label, Status, AssigneeId FROM FlowOrchestrationWorkItem
    WHERE RelatedRecordId = :r1.quoteId ORDER BY CreatedDate ASC
]) {
    System.debug('  WORK ITEM [' + wi.Status + '] ' + wi.Label + ' -> ' + wi.AssigneeId);
}
