/**
 * Activa el pedido del retrofit, que es lo que arranca de verdad la descomposicion.
 *
 * Va en cola y no en linea con el sellado porque al pasar el pedido a Activated se
 * dispara el flow RLM_Submit_Order_on_Activation, que llama a submitOrder y pone en
 * marcha el motor de DRO: la generacion entera del plan y sus pasos. Meter eso en la
 * misma transaccion que acaba de crear y sellar el pedido junta dos cosas que no
 * tienen por que caerse juntas. Separadas, si la descomposicion se pasa de limites el
 * pedido sigue creado y sellado.
 */
public with sharing class COMEXI_OrderActivationQueueable implements Queueable {

    private final Set<Id> orderIds;

    public COMEXI_OrderActivationQueueable(Set<Id> orderIds) {
        this.orderIds = orderIds;
    }

    public void execute(QueueableContext context) {
        if (orderIds == null || orderIds.isEmpty()) return;

        // Se filtra por Draft porque el pedido rechaza que se reactive lo que ya esta
        // activado, y en la demo esto se reejecuta a menudo.
        List<Order> pending = [
            SELECT Id, Status FROM Order
            WHERE Id IN :orderIds AND Status = 'Draft'
            WITH USER_MODE
        ];
        if (pending.isEmpty()) return;

        for (Order o : pending) {
            o.Status = 'Activated';
        }
        try {
            // Update directo y no activateOrderAction: la accion invocable espera un
            // cartId de contexto de carrito y responde "Invalid input for
            // activeOrCartId" con un pedido creado desde la oferta. El flow
            // RLM_Submit_Order_on_Activation escucha el cambio de Status, asi que
            // este update es lo que arranca submitOrder y la descomposicion.
            update as user pending;
        } catch (DmlException e) {
            System.debug(LoggingLevel.ERROR, 'No se pudieron activar los pedidos '
                + orderIds + ': ' + e.getMessage());
        }
    }
}
