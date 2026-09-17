/**
 * Sella en el pedido recien creado el expediente del retrofit y lo manda a activar.
 *
 * El Discovery describe este salto como doble entrada: hoy alguien reintroduce en SAP
 * lo que ya estaba en la oferta, y la dependencia del anticipo vive en un correo. Aqui
 * el pedido nace de la oferta y se queda con el expediente pegado: de que caso venia,
 * sobre que maquina se interviene, cuantas horas se han comprometido y cuanto dinero
 * hay que ver antes de que ingenieria arranque.
 *
 * Quien crea el pedido es el flow COMEXI_Order_From_Signed_Contract, no esta clase.
 * No es un capricho: createOrderFromQuote existe como accion de Flow y de REST pero
 * no esta expuesta a Apex, y llamarla con Invocable.Action revienta con
 * "createOrderFromQuote isn't a valid action type". El flow la invoca, recoge el
 * orderId y lo pasa aqui.
 *
 * Lo que la plataforma ya da no se duplica. createOrderFromQuote rellena AccountId,
 * QuoteId y ContractId por su cuenta, asi que aqui solo se anade lo que Order no
 * trae: el caso, la oportunidad, la maquina y las condiciones del retrofit.
 *
 * Las tres formulas del pedido (COMEXI_Machine_Model__c, COMEXI_Down_Payment_Amount__c
 * y COMEXI_SAP_Customer_Code__c) no se asignan: las calcula la plataforma.
 */
public with sharing class COMEXI_OrderFromContractService {

    /** Entrada del flow: el contrato que se acaba de firmar y el pedido que nacio. */
    public class Request {
        @InvocableVariable(required=true label='Contrato firmado')
        public String contractId;

        @InvocableVariable(required=true label='Pedido recien creado')
        public String orderId;
    }

    @InvocableMethod(
        label='COMEXI: sellar el pedido del retrofit y activarlo'
        description='Copia al pedido el expediente del caso, la oportunidad y la oferta, y lo encola para activarlo, que es lo que arranca la descomposicion.'
        category='COMEXI Retrofit'
    )
    public static void stampAndActivate(List<Request> requests) {
        Map<Id, Id> orderIdByContractId = new Map<Id, Id>();
        for (Request r : requests) {
            if (String.isBlank(r.contractId) || String.isBlank(r.orderId)) continue;
            orderIdByContractId.put((Id) r.contractId, (Id) r.orderId);
        }
        if (orderIdByContractId.isEmpty()) return;

        Set<Id> stamped = stamp(orderIdByContractId);
        if (stamped.isEmpty()) return;

        if (Limits.getQueueableJobs() < Limits.getLimitQueueableJobs()) {
            System.enqueueJob(new COMEXI_OrderActivationQueueable(stamped));
        } else {
            System.debug(LoggingLevel.WARN, 'Sin hueco para encolar la activacion. Los '
                + 'pedidos ' + stamped + ' quedan en Draft y se activan a mano.');
        }
    }

    /** Copia los datos y devuelve los pedidos que hay que activar. */
    private static Set<Id> stamp(Map<Id, Id> orderIdByContractId) {
        Map<Id, Contract> contracts = new Map<Id, Contract>([
            SELECT Id, SourceQuoteId, COMEXI_Payment_Terms__c
            FROM Contract
            WHERE Id IN :orderIdByContractId.keySet()
            WITH USER_MODE
        ]);

        Set<Id> quoteIds = new Set<Id>();
        for (Contract c : contracts.values()) {
            if (c.SourceQuoteId != null) quoteIds.add(c.SourceQuoteId);
        }
        if (quoteIds.isEmpty()) return new Set<Id>();

        Map<Id, Quote> quotes = new Map<Id, Quote>([
            SELECT Id, OpportunityId,
                   COMEXI_Source_Case__c, COMEXI_Target_Asset__c,
                   COMEXI_Generated_By_Advisor__c, COMEXI_Retrofit_Type__c,
                   COMEXI_Retrofit_SKU__c, COMEXI_Intervention_Site__c,
                   COMEXI_Intervention_Country__c, COMEXI_Intervention_Weeks__c,
                   COMEXI_Target_Intervention_Date__c, COMEXI_Intervention_Hours__c,
                   COMEXI_Expenses_Owner__c, COMEXI_Down_Payment_Pct__c,
                   Opportunity.COMEXI_Obsolete_Component__c
            FROM Quote
            WHERE Id IN :quoteIds
            WITH USER_MODE
        ]);

        List<Order> updates = new List<Order>();
        Set<Id> toActivate = new Set<Id>();

        for (Id contractId : orderIdByContractId.keySet()) {
            Contract c = contracts.get(contractId);
            if (c == null || c.SourceQuoteId == null) continue;

            Quote q = quotes.get(c.SourceQuoteId);
            // Solo la cadena de la demo. Si la oferta no la genero el advisor, este
            // contrato es de otro flujo y no se le toca el pedido.
            if (q == null || q.COMEXI_Generated_By_Advisor__c != true) continue;

            Id orderId = orderIdByContractId.get(contractId);
            toActivate.add(orderId);

            Order upd = new Order(Id = orderId);
            upd.COMEXI_Generated_By_Advisor__c = true;
            upd.COMEXI_Source_Case__c        = q.COMEXI_Source_Case__c;
            upd.COMEXI_Source_Opportunity__c = q.OpportunityId;
            upd.COMEXI_Target_Asset__c       = q.COMEXI_Target_Asset__c;

            upd.COMEXI_Retrofit_Type__c      = q.COMEXI_Retrofit_Type__c;
            upd.COMEXI_Retrofit_SKU__c       = q.COMEXI_Retrofit_SKU__c;
            upd.COMEXI_Obsolete_Component__c = (q.Opportunity != null)
                ? q.Opportunity.COMEXI_Obsolete_Component__c : null;

            upd.COMEXI_Intervention_Site__c        = q.COMEXI_Intervention_Site__c;
            upd.COMEXI_Intervention_Country__c     = q.COMEXI_Intervention_Country__c;
            upd.COMEXI_Intervention_Weeks__c       = q.COMEXI_Intervention_Weeks__c;
            upd.COMEXI_Target_Intervention_Date__c = q.COMEXI_Target_Intervention_Date__c;
            upd.COMEXI_Intervention_Hours__c       = q.COMEXI_Intervention_Hours__c;
            upd.COMEXI_Expenses_Owner__c           = q.COMEXI_Expenses_Owner__c;

            upd.COMEXI_Down_Payment_Pct__c = q.COMEXI_Down_Payment_Pct__c;
            // Las condiciones de pago salen del contrato y no de la oferta: es el
            // contrato el que las fija y el que se ha firmado.
            upd.COMEXI_Payment_Terms__c    = c.COMEXI_Payment_Terms__c;
            // Pendiente y no Cobrado: el pedido nace debiendo el anticipo, y es el
            // paso del plan de fulfillment el que lo pasa a cobrado.
            upd.COMEXI_Down_Payment_Status__c = 'Pendiente';

            updates.add(upd);
        }

        if (!updates.isEmpty()) {
            update as user updates;
        }
        return toActivate;
    }
}
