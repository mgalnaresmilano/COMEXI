/**
 * Reprecifica la oferta para que la plataforma acepte convertirla en pedido.
 *
 * Sin esto, createOrderFromQuote responde "We couldn't create the order because the
 * prices aren't updated. Click Reprice All and try again." y la escena 11 no arranca.
 *
 * El motivo no se ve a simple vista: Quote.CalculationStatus dice CompletedWithTax,
 * asi que parece que los precios estan al dia. El campo que de verdad manda es
 * Quote.ValidationResult, que la plataforma pone en TransactionIncomplete en cuanto
 * alguien toca la cabecera de la oferta. Y en esta demo la cabecera se toca mucho: el
 * advisor sella veinte campos custom, el descuento se recalcula, la aprobacion cambia
 * el estado. Cada uno de esos pasos vuelve a marcar los precios como sucios.
 *
 * La receta de repricing es la misma que ya usa RLM_PreProcessOrderController para los
 * pedidos grandes: un Place Sales Transaction con PATCH de la cabecera, pricing en
 * FORCE y configuracion en SKIP. Ahi esta documentado el mismo mensaje de error.
 *
 * Para una oferta que no es large deal el pricing corre de forma sincrona, asi que al
 * salir de aqui ValidationResult ya esta limpio y el paso siguiente del flow puede
 * crear el pedido.
 */
public with sharing class COMEXI_QuoteRepriceService {

    public class Request {
        @InvocableVariable(required=true label='Oferta a reprecificar')
        public String quoteId;
    }

    public class Result {
        @InvocableVariable(label='Precios listos para generar el pedido')
        public Boolean ready;

        @InvocableVariable(label='Detalle para el log del flow')
        public String message;
    }

    @InvocableMethod(
        label='COMEXI: reprecificar la oferta antes de generar el pedido'
        description='Fuerza el repricing para limpiar Quote.ValidationResult. Sin esto, createOrderFromQuote rechaza la oferta con "the prices aren\'t updated".'
        category='COMEXI Retrofit'
    )
    public static List<Result> reprice(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request r : requests) {
            results.add(repriceOne(r.quoteId));
        }
        return results;
    }

    private static Result repriceOne(String quoteId) {
        Result out = new Result();
        out.ready = false;

        if (String.isBlank(quoteId)) {
            out.message = 'Sin oferta que reprecificar.';
            return out;
        }

        List<Quote> quotes = [
            SELECT Id, ValidationResult FROM Quote WHERE Id = :quoteId WITH USER_MODE LIMIT 1
        ];
        if (quotes.isEmpty()) {
            out.message = 'La oferta ' + quoteId + ' no existe o no es accesible.';
            return out;
        }
        if (String.isBlank(quotes[0].ValidationResult)) {
            // Ya esta limpia: reprecificar de nuevo solo gastaria tiempo en pantalla.
            out.ready = true;
            out.message = 'Los precios ya estaban al dia.';
            return out;
        }

        RevSalesTrxn.RecordResource header =
            new RevSalesTrxn.RecordResource(Quote.getSObjectType(), 'PATCH', quoteId);
        header.fieldValues = new Map<String, Object>();
        List<RevSalesTrxn.RecordWithReferenceRequest> records =
            new List<RevSalesTrxn.RecordWithReferenceRequest>{
                new RevSalesTrxn.RecordWithReferenceRequest('refHeader', header)
            };
        RevSalesTrxn.GraphRequest graph =
            new RevSalesTrxn.GraphRequest('ComexiRetrofitReprice', records);
        // Nulls con tipo para que resuelva la sobrecarga de execute() sin ambiguedad.
        RevSalesTrxn.CatalogRatesPreferenceEnum ratesPref = null;
        RevSalesTrxn.TaxPreferenceEnum taxPref = null;

        try {
            RevSalesTrxn.PlaceSalesTransactionResponse resp =
                RevSalesTrxn.PlaceSalesTransactionExecutor.execute(
                    graph,
                    RevSalesTrxn.PricingPreferenceEnum.FORCE,
                    RevSalesTrxn.ConfigurationExecutionEnum.SKIP,
                    new RevSalesTrxn.ConfigurationOptionsInput(),
                    null,
                    ratesPref,
                    taxPref,
                    null
                );
            if (resp == null || resp.isSuccess != true) {
                out.message = 'El repricing fallo: '
                    + (resp == null ? 'sin respuesta' : String.valueOf(resp.errorResponse));
                System.debug(LoggingLevel.ERROR, out.message);
                return out;
            }
        } catch (Exception e) {
            out.message = 'El repricing lanzo una excepcion: ' + e.getMessage();
            System.debug(LoggingLevel.ERROR, out.message);
            return out;
        }

        out.ready = true;
        out.message = 'Oferta reprecificada, lista para generar el pedido.';
        return out;
    }
}
