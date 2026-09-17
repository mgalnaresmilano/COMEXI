/**
 * Sella los campos COMEXI_* del contrato con lo que ya sabe la oferta de origen.
 *
 * El boton Create Contract de la oferta crea un Contract en Draft con AccountId y
 * SourceQuoteId, y nada mas: ni la maquina, ni el plazo, ni el anticipo, ni el caso
 * del que salio todo. El comercial de COMEXI acaba reescribiendo a mano en el
 * contrato lo mismo que ya escribio en la oferta, que es justo el duplicado que el
 * Discovery describe ("el contrato de viabilidad es un 99% la oferta").
 *
 * Aqui se copia una vez, al nacer el contrato. Nada se inventa: todo sale de la
 * oferta, de su oportunidad o del caso, de forma que si el escandallo cambia, el
 * contrato cuenta lo mismo que la oferta.
 *
 * Las dos formulas del contrato, COMEXI_Machine_Model__c y COMEXI_Down_Payment_Amount__c,
 * no se asignan: las calcula la plataforma. Misma regla que en applyRetrofitQuoteFields.
 */
public with sharing class COMEXI_ContractFromQuoteService {

    /** Meses de garantia que COMEXI ofrece en retrofit, segun el Discovery. */
    private static final Decimal WARRANTY_MONTHS = 6;

    /**
     * La garantia arranca al aceptar la intervencion, no al entregar el material.
     * Es un matiz que hoy solo conoce quien se ha leido la oferta entera.
     */
    private static final String WARRANTY_START_EVENT = 'Aceptacion';

    /**
     * Contratos ya sellados en esta transaccion.
     *
     * El trigger escucha update, y el propio sellado es un update: sin esta marca el
     * segundo paso volveria a entrar. El campo COMEXI_Generated_By_Advisor__c ya corta
     * la reentrada en transacciones posteriores, pero dentro de la misma los registros
     * de Trigger.new todavia llegan con el valor viejo.
     */
    private static Set<Id> stamped = new Set<Id>();

    /** Para que el trigger descarte lo ya hecho antes de montar la lista. */
    public static Boolean alreadyStamped(Id contractId) {
        return stamped.contains(contractId);
    }

    /**
     * Sella los contratos indicados a partir de su oferta de origen.
     *
     * Una sola SOQL para todas las ofertas y un unico update: el trigger es bulk y
     * una demo que se rompa al cargar dos contratos de golpe no vale de nada.
     */
    public static void stampFromQuotes(List<Contract> contracts) {
        Map<Id, Id> quoteIdByContractId = new Map<Id, Id>();
        for (Contract c : contracts) {
            if (c.SourceQuoteId != null && !stamped.contains(c.Id)) {
                quoteIdByContractId.put(c.Id, c.SourceQuoteId);
            }
        }
        if (quoteIdByContractId.isEmpty()) return;

        Map<Id, Quote> quotes = new Map<Id, Quote>([
            SELECT Id, OpportunityId, TotalPrice, RLM_Payment_Terms__c,
                   COMEXI_Source_Case__c, COMEXI_Target_Asset__c,
                   COMEXI_Generated_By_Advisor__c, COMEXI_Retrofit_Type__c,
                   COMEXI_Retrofit_SKU__c, COMEXI_Intervention_Site__c,
                   COMEXI_Intervention_Country__c, COMEXI_Intervention_Weeks__c,
                   COMEXI_Target_Intervention_Date__c, COMEXI_Intervention_Hours__c,
                   COMEXI_Expenses_Owner__c, COMEXI_Down_Payment_Pct__c,
                   Opportunity.COMEXI_Obsolete_Component__c
            FROM Quote
            WHERE Id IN :quoteIdByContractId.values()
            WITH USER_MODE
        ]);
        if (quotes.isEmpty()) return;

        List<Contract> updates = new List<Contract>();
        for (Id contractId : quoteIdByContractId.keySet()) {
            Quote q = quotes.get(quoteIdByContractId.get(contractId));
            // Solo los contratos de la demo. Si la oferta no la genero el advisor,
            // este contrato es de otro flujo y no se toca.
            if (q == null || q.COMEXI_Generated_By_Advisor__c != true) continue;

            Contract upd = new Contract(Id = contractId);

            // Origen: de que caso, de que oportunidad y sobre que maquina va esto.
            upd.COMEXI_Source_Case__c          = q.COMEXI_Source_Case__c;
            upd.COMEXI_Source_Opportunity__c   = q.OpportunityId;
            upd.COMEXI_Target_Asset__c         = q.COMEXI_Target_Asset__c;
            upd.COMEXI_Generated_By_Advisor__c = true;

            // Alcance. El componente obsoleto solo vive en la oportunidad: es donde
            // el advisor dejo escrito por que hay retrofit.
            upd.COMEXI_Retrofit_Type__c       = q.COMEXI_Retrofit_Type__c;
            upd.COMEXI_Retrofit_SKU__c        = q.COMEXI_Retrofit_SKU__c;
            upd.COMEXI_Obsolete_Component__c  = (q.Opportunity != null)
                ? q.Opportunity.COMEXI_Obsolete_Component__c : null;

            // Intervencion: donde, cuando y cuantas horas se comprometen.
            upd.COMEXI_Intervention_Site__c        = q.COMEXI_Intervention_Site__c;
            upd.COMEXI_Intervention_Country__c     = q.COMEXI_Intervention_Country__c;
            upd.COMEXI_Intervention_Weeks__c       = q.COMEXI_Intervention_Weeks__c;
            upd.COMEXI_Target_Intervention_Date__c = q.COMEXI_Target_Intervention_Date__c;
            upd.COMEXI_Intervention_Hours__c       = q.COMEXI_Intervention_Hours__c;
            upd.COMEXI_Expenses_Owner__c           = q.COMEXI_Expenses_Owner__c;

            // Condiciones. Contract no trae importe de cabecera propio, asi que sin
            // COMEXI_Contract_Value__c el contrato no dice cuanto vale.
            upd.COMEXI_Contract_Value__c      = q.TotalPrice;
            upd.COMEXI_Down_Payment_Pct__c    = q.COMEXI_Down_Payment_Pct__c;
            upd.COMEXI_Payment_Terms__c       = q.RLM_Payment_Terms__c;
            upd.COMEXI_Warranty_Months__c     = WARRANTY_MONTHS;
            upd.COMEXI_Warranty_Start_Event__c = WARRANTY_START_EVENT;

            updates.add(upd);
            stamped.add(contractId);
        }

        if (!updates.isEmpty()) {
            update as user updates;
        }
    }
}
