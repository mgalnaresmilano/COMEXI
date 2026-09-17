/**
 * Completa el contrato que nace del boton Create Contract de la oferta.
 *
 * Escucha insert y update a proposito. El boton de la ficha de oferta no deja el
 * contrato terminado en el insert: primero graba la cabecera y despues rellena
 * SourceQuoteId, asi que un trigger solo de after insert ve el campo vacio y se va
 * sin sellar nada (era el sintoma: contrato en Draft, veinte campos en blanco y
 * ningun job en cola). Por REST el mismo action si trae la oferta en el insert, de
 * ahi que en pruebas funcionase y en pantalla no.
 *
 * El disparo real es "SourceQuoteId ya tiene valor y este contrato aun no esta
 * sellado". COMEXI_Generated_By_Advisor__c hace de marca: el sellado lo pone a true,
 * asi que el update que provoca el propio sellado no vuelve a entrar. El Set estatico
 * del servicio cubre ademas varios updates dentro de la misma transaccion.
 *
 * El filtro grueso por SourceQuoteId deja fuera los contratos creados a mano o
 * cargados por datos; el fino (que la oferta la generase el Retrofit Advisor) lo
 * aplica COMEXI_ContractFromQuoteService, que ya tiene las ofertas en memoria.
 *
 * Lo que pasa al FIRMAR no vive aqui: lo lleva el flow COMEXI_Order_From_Signed_Contract.
 * La razon es tecnica y no de gusto: createOrderFromQuote no esta expuesta a Apex, solo
 * a Flow y REST.
 */
trigger COMEXI_ContractTrigger on Contract (after insert, after update) {
    List<Contract> pending = new List<Contract>();
    Set<Id> pendingIds = new Set<Id>();

    for (Contract c : Trigger.new) {
        if (c.SourceQuoteId == null) continue;
        if (c.COMEXI_Generated_By_Advisor__c == true) continue;
        if (COMEXI_ContractFromQuoteService.alreadyStamped(c.Id)) continue;
        pending.add(c);
        pendingIds.add(c.Id);
    }
    if (pending.isEmpty()) return;

    COMEXI_ContractFromQuoteService.stampFromQuotes(pending);

    // La generacion del documento no puede tumbar la creacion del contrato: si falla,
    // queda el contrato sellado y se regenera con Generate Contract.
    if (Limits.getQueueableJobs() < Limits.getLimitQueueableJobs()) {
        System.enqueueJob(new COMEXI_ContractDocQueueable(pendingIds));
    }
}
