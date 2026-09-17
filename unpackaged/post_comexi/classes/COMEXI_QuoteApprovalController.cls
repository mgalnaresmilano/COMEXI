/**
 * Guia previa de aprobacion de descuento de la oferta (escena 08 del guion Comexi).
 *
 * Avisa al vendedor de cuantas firmas va a costar el descuento ANTES de prometerlo, y
 * envia la oferta al circuito nativo de Advanced Approvals. La decision no se toma aqui:
 * se toma en la pestana Approvals del registro, que es donde queda la traza auditable.
 *
 * Quien manda es el framework nativo, no esta clase:
 *   - Los niveles los dicta Quote.RLM_Approval_Level__c, rollup MAX del nivel que cada
 *     linea calcula en QuoteLineItem.RLM_Approval_Level_Calc__c a partir de su descuento.
 *   - El estado lo escribe la orquestacion RLM_Quote_Smart_Approval en
 *     Quote.RLM_Approval_Status__c, que es el campo del path del registro.
 * Esta clase solo lee esos dos campos y arranca la orquestacion.
 */
public with sharing class COMEXI_QuoteApprovalController {

    private static final String ORCHESTRATION = 'RLM_Quote_Smart_Approval';

    /** Un peldano por cada nivel que puede pedir la orquestacion, en su mismo orden. */
    private static final List<String> LEVEL_LABELS = new List<String>{
        'Nivel 1 - Manager',
        'Nivel 2 - Director de Servicio',
        'Nivel 3 - VP'
    };

    /**
     * Pasos de descuento de RLM_Quote_Smart_Approval traducidos a nivel. La rama de
     * condiciones de pago (Payment_Terms) se queda fuera adrede: no es un nivel de
     * descuento y no debe mover la escalera del banner.
     */
    private static final Map<String, Integer> LEVEL_BY_STEP_NAME = new Map<String, Integer>{
        'Manager_Approver'  => 1,
        'Director_Approver' => 2,
        'VP_Approver'       => 3
    };

    public class ApprovalException extends Exception {}

    /** Estado que consume el componente para pintar el banner y decidir si ofrece enviar. */
    public class ApprovalState {
        /** Descuento mezclado de la oferta: el numero que ve el cliente. */
        @AuraEnabled public Decimal discountPct;
        /** Descuento mas alto de una linea: el numero que decide los niveles. */
        @AuraEnabled public Decimal maxLineDiscountPct;
        @AuraEnabled public Decimal marginPct;
        @AuraEnabled public Integer requiredLevels;
        /** NotRequired | NotSubmitted | Pending | Approved | Rejected | Recalled */
        @AuraEnabled public String status;
        @AuraEnabled public Integer approvedLevels;
        @AuraEnabled public Integer currentLevel;
        @AuraEnabled public String stepLabel;
        @AuraEnabled public String approverName;
        @AuraEnabled public Boolean canSubmit;
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // Lectura de estado
    // ─────────────────────────────────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static ApprovalState getApprovalState(Id quoteId) {
        try {
            return buildState(quoteId);
        } catch (Exception e) {
            throw asAura(e);
        }
    }

    private static ApprovalState buildState(Id quoteId) {
        List<Quote> quotes = [
            SELECT Id, RLM_Approval_Status__c, RLM_Approval_Level__c,
                   RLM_Discount_Percent__c, COMEXI_Max_Line_Discount_Pct__c,
                   COMEXI_Blended_Margin_Pct__c
            FROM Quote
            WHERE Id = :quoteId
            WITH USER_MODE
            LIMIT 1
        ];
        if (quotes.isEmpty()) {
            throw new ApprovalException('No se encuentra la oferta ' + quoteId + '.');
        }
        Quote q = quotes[0];

        ApprovalState s = new ApprovalState();
        s.discountPct        = q.RLM_Discount_Percent__c;
        s.maxLineDiscountPct = q.COMEXI_Max_Line_Discount_Pct__c;
        s.marginPct          = q.COMEXI_Blended_Margin_Pct__c;
        s.requiredLevels     = levelsFrom(q.RLM_Approval_Level__c);
        s.approvedLevels     = 0;
        s.canSubmit          = false;
        s.status             = normalizeStatus(q.RLM_Approval_Status__c, s.requiredLevels);

        if (s.status == 'NotSubmitted' || s.status == 'Rejected' || s.status == 'Recalled') {
            s.canSubmit = (s.requiredLevels > 0);
            return s;
        }
        if (s.status != 'Pending') {
            // Aprobada: todas las firmas del circuito estan dadas.
            s.approvedLevels = s.requiredLevels;
            return s;
        }

        applyPendingStep(s, quoteId);
        return s;
    }

    /**
     * Completa el nivel en curso leyendo los pasos de la orquestacion que esta viva.
     *
     * Se acota a la instancia en curso a proposito: una oferta puede acumular intentos
     * anteriores cancelados, y contar sus pasos daria por firmados niveles que nadie ha
     * firmado en esta solicitud. Los pasos se identifican por su nombre en la
     * orquestacion, no por su orden, para que la rama de condiciones de pago no cuente
     * como nivel de descuento.
     *
     * Los objetos de Flow Orchestration son de solo lectura y no admiten USER_MODE: se
     * consultan en modo sistema, y el acceso al registro ya lo ha filtrado la Quote. Si
     * el circuito arranca de forma asincrona y todavia no hay pasos, el banner se queda
     * con el estado Pending del campo, que ya es la verdad para el path.
     */
    private static void applyPendingStep(ApprovalState s, Id quoteId) {
        s.currentLevel = 1;
        s.stepLabel    = levelLabel(1);

        List<FlowOrchestrationStepInstance> steps = [
            SELECT Id, Name, Status, OrchestrationInstanceId
            FROM FlowOrchestrationStepInstance
            WHERE RelatedRecord = :quoteId
        ];
        if (steps.isEmpty()) return;

        Set<Id> instanceIds = new Set<Id>();
        for (FlowOrchestrationStepInstance step : steps) {
            instanceIds.add(step.OrchestrationInstanceId);
        }
        Id liveInstanceId;
        for (FlowOrchestrationInstance instance : [
            SELECT Id
            FROM FlowOrchestrationInstance
            WHERE Id IN :instanceIds AND Status = 'InProgress'
            ORDER BY CreatedDate DESC
            LIMIT 1
        ]) {
            liveInstanceId = instance.Id;
        }
        if (liveInstanceId == null) return;

        Id openStepId;
        Integer openLevel;
        for (FlowOrchestrationStepInstance step : steps) {
            if (step.OrchestrationInstanceId != liveInstanceId) continue;
            Integer level = LEVEL_BY_STEP_NAME.get(step.Name);
            if (level == null) continue;
            if (step.Status == 'Completed') {
                s.approvedLevels++;
            } else if (step.Status == 'InProgress' && openStepId == null) {
                openStepId = step.Id;
                openLevel  = level;
            }
        }

        s.currentLevel = (openLevel != null) ? openLevel : s.approvedLevels + 1;
        s.stepLabel    = levelLabel(s.currentLevel);
        if (openStepId == null) return;

        for (FlowOrchestrationWorkItem item : [
            SELECT AssigneeId
            FROM FlowOrchestrationWorkItem
            WHERE StepInstanceId = :openStepId AND Status = 'Assigned'
            LIMIT 1
        ]) {
            s.approverName = assigneeName(item.AssigneeId);
        }
    }

    /** El rollup puede venir nulo si la oferta no tiene lineas todavia. */
    private static Integer levelsFrom(Decimal approvalLevel) {
        if (approvalLevel == null) return 0;
        Integer levels = approvalLevel.intValue();
        if (levels < 0) return 0;
        return Math.min(levels, LEVEL_LABELS.size());
    }

    private static String levelLabel(Integer level) {
        if (level == null || level < 1 || level > LEVEL_LABELS.size()) return null;
        return LEVEL_LABELS[level - 1];
    }

    private static String normalizeStatus(String approvalStatus, Integer requiredLevels) {
        if (String.isNotBlank(approvalStatus)) return approvalStatus;
        // Sin enviar: si ninguna linea llega al primer tramo, no hace falta pedir nada.
        return (requiredLevels == 0) ? 'NotRequired' : 'NotSubmitted';
    }

    /** AssigneeId es polimorfico: en esta orquestacion los pasos van a grupos publicos. */
    private static String assigneeName(Id assigneeId) {
        if (assigneeId == null) return null;
        if (String.valueOf(assigneeId).startsWith('005')) {
            List<User> users = [SELECT Name FROM User WHERE Id = :assigneeId LIMIT 1];
            return users.isEmpty() ? null : users[0].Name;
        }
        List<Group> groups = [SELECT Name, DeveloperName FROM Group WHERE Id = :assigneeId LIMIT 1];
        if (groups.isEmpty()) return null;
        return String.isBlank(groups[0].Name) ? groups[0].DeveloperName : groups[0].Name;
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // Envio al circuito nativo
    // ─────────────────────────────────────────────────────────────────────────────

    /**
     * Arranca la orquestacion de aprobacion sobre la oferta.
     *
     * Se pasan solo las variables que declara RLM_Quote_Smart_Approval (recordId,
     * submitter y submissionComments). El nivel no se envia: lo vuelve a leer la propia
     * orquestacion del rollup, asi que no puede quedar desfasado si el motor de pricing
     * repreciara entre el envio y la evaluacion.
     */
    @AuraEnabled
    public static ApprovalState submitForApproval(Id quoteId) {
        try {
            ApprovalState current = buildState(quoteId);
            if (current.requiredLevels == 0) {
                throw new ApprovalException(
                    'Ninguna linea llega al umbral de aprobacion, asi que la oferta no necesita firmas.');
            }
            if (current.status == 'Pending') {
                throw new ApprovalException('La oferta ya esta en aprobacion.');
            }
            if (current.status == 'Approved') {
                throw new ApprovalException('La oferta ya esta aprobada.');
            }

            Map<String, Object> inputs = new Map<String, Object>{
                'recordId'           => String.valueOf(quoteId),
                'submitter'          => String.valueOf(UserInfo.getUserId()),
                'submissionComments' => submissionComments(current)
            };
            Flow.Interview.createInterview(ORCHESTRATION, inputs).start();

            ApprovalState after = buildState(quoteId);
            if (after.status == 'NotSubmitted') {
                /* La orquestacion escribe Pending en un paso de fondo que puede resolverse
                   fuera de esta transaccion. El banner se adelanta para no dejar al
                   vendedor mirando "sin enviar" con la solicitud ya en marcha; el wire al
                   registro corrige en cuanto el campo se materializa. */
                after.status     = 'Pending';
                after.canSubmit  = false;
                after.currentLevel = 1;
                after.stepLabel  = levelLabel(1);
            }
            return after;
        } catch (Exception e) {
            throw asAura(e);
        }
    }

    private static String submissionComments(ApprovalState s) {
        return 'Descuento mezclado ' + format(s.discountPct)
            + ', descuento maximo de linea ' + format(s.maxLineDiscountPct)
            + ', margen ' + format(s.marginPct)
            + '. Niveles que exige la oferta: ' + s.requiredLevels + '.';
    }

    private static String format(Decimal pct) {
        return (pct == null) ? 'sin dato' : pct.setScale(2, System.RoundingMode.HALF_UP) + '%';
    }

    private static AuraHandledException asAura(Exception e) {
        if (e instanceof AuraHandledException) return (AuraHandledException) e;
        AuraHandledException ex = new AuraHandledException(e.getMessage());
        ex.setMessage(e.getMessage());
        return ex;
    }
}
