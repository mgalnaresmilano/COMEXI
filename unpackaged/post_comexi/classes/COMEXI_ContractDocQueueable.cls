/**
 * Genera el documento del contrato y le engancha las clausulas de la biblioteca.
 *
 * Sin esto, el usuario tendria que pulsar Generate Contract, elegir la plantilla y
 * esperar. Funciona, pero en la demo interrumpe el relato justo en el momento en el
 * que se quiere ensenar que el contrato nace completo. Asi, al volver de Create
 * Contract el documento ya esta en la pestana Documents.
 *
 * Va en cola y no en el trigger porque createContractDocumentVersion es una accion
 * invocable estandar que dispara un job de generacion: llamarla en linea alargaria
 * la transaccion del insert y ataria el exito del contrato al exito del documento.
 * Si la generacion falla, el contrato sigue creado y solo se pierde el documento.
 *
 * Las clausulas se copian del template al ContractDocumentVersion. No se heredan
 * solas: las que cuelgan del template son la plantilla de la biblioteca, y las que
 * se ven en Associated Clauses del documento son otras, apuntando al CDV.
 */
public with sharing class COMEXI_ContractDocQueueable implements Queueable, Database.AllowsCallouts {

    private static final String TEMPLATE_NAME = 'COMEXI_Contrato_Retrofit';

    private final Set<Id> contractIds;

    public COMEXI_ContractDocQueueable(Set<Id> contractIds) {
        this.contractIds = contractIds;
    }

    public void execute(QueueableContext context) {
        if (contractIds == null || contractIds.isEmpty()) return;

        Id templateId = activeTemplateId();
        if (templateId == null) {
            // Sin plantilla activa no hay nada que generar. El contrato ya esta
            // creado y sellado, asi que se avisa y se sale sin romper nada.
            System.debug(LoggingLevel.WARN, 'No hay ' + TEMPLATE_NAME + ' activa. '
                + 'Ejecuta activate_comexi_docgen_template y vuelve a pulsar Generate Contract.');
            return;
        }

        // createContractDocumentVersion rechaza el contrato que ya tiene una version
        // viva con DOCUMENT_VERSION_EXISTS, asi que se consultan antes y de una vez.
        Set<Id> alreadyGenerated = new Set<Id>();
        for (ContractDocumentVersion existing : [
            SELECT ContractId FROM ContractDocumentVersion
            WHERE ContractId IN :contractIds
        ]) {
            alreadyGenerated.add(existing.ContractId);
        }

        for (Id contractId : contractIds) {
            if (alreadyGenerated.contains(contractId)) continue;
            generate(contractId, templateId);
        }

        // Se enganchan las clausulas a todas las versiones del lote, tambien a las
        // que no ha generado esta clase: el boton Create Contract sabe crear el
        // documento por su cuenta (createClmContract con isCreateContractDocument),
        // y en ese caso el documento existiria sin clausulas.
        attachClauses(new List<Id>(contractIds), templateId);
    }

    /** Ultima version activa de la plantilla de contrato desplegada por el repo. */
    private static Id activeTemplateId() {
        List<DocumentTemplate> templates = [
            SELECT Id FROM DocumentTemplate
            WHERE Name = :TEMPLATE_NAME
              AND IsActive = true
              AND UsageType = 'Contract_Lifecycle_Management'
            ORDER BY VersionNumber DESC
            LIMIT 1
        ];
        return templates.isEmpty() ? null : templates[0].Id;
    }

    private static Boolean generate(Id contractId, Id templateId) {
        try {
            Invocable.Action action =
                Invocable.Action.createStandardAction('createContractDocumentVersion');
            // Los dos parametros van como String. Pasando el Id tal cual, la accion
            // responde INVALID_ARGUMENT_TYPE "expected String" y no genera nada.
            action.setInvocationParameter('contractId', String.valueOf(contractId));
            action.setInvocationParameter('templateId', String.valueOf(templateId));

            for (Invocable.Action.Result result : action.invoke()) {
                if (!result.isSuccess()) {
                    System.debug(LoggingLevel.ERROR,
                        'No se pudo generar el documento del contrato ' + contractId
                        + ': ' + result.getErrors());
                    return false;
                }
            }
            return true;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Fallo generando el documento del contrato '
                + contractId + ': ' + e.getMessage());
            return false;
        }
    }

    /**
     * Copia a los documentos del contrato las clausulas asociadas a la plantilla.
     *
     * Idempotente: se consultan las asociaciones que ya existen y solo se crean las
     * que faltan, de forma que regenerar el documento no duplica el articulado.
     */
    private static void attachClauses(List<Id> contractIds, Id templateId) {
        List<Id> clauseIds = new List<Id>();
        for (DocumentAuthoredContent fromTemplate : [
            SELECT StandardContentObjectId
            FROM DocumentAuthoredContent
            WHERE ReferenceObjectId = :templateId
              AND ContentType = 'StandardDocumentClause'
        ]) {
            clauseIds.add(fromTemplate.StandardContentObjectId);
        }
        if (clauseIds.isEmpty()) {
            System.debug(LoggingLevel.WARN, 'La plantilla no tiene clausulas asociadas. '
                + 'Ejecuta scripts/comexi/provision_clm_clauses.py.');
            return;
        }

        List<Id> versionIds = new List<Id>();
        for (ContractDocumentVersion version : [
            SELECT Id FROM ContractDocumentVersion
            WHERE ContractId IN :contractIds
        ]) {
            versionIds.add(version.Id);
        }
        if (versionIds.isEmpty()) return;

        Set<String> existing = new Set<String>();
        for (DocumentAuthoredContent linked : [
            SELECT ReferenceObjectId, StandardContentObjectId
            FROM DocumentAuthoredContent
            WHERE ReferenceObjectId IN :versionIds
              AND ContentType = 'StandardDocumentClause'
        ]) {
            existing.add(linked.ReferenceObjectId + '|' + linked.StandardContentObjectId);
        }

        List<DocumentAuthoredContent> links = new List<DocumentAuthoredContent>();
        for (Id versionId : versionIds) {
            for (Id clauseId : clauseIds) {
                if (existing.contains(versionId + '|' + clauseId)) continue;
                links.add(new DocumentAuthoredContent(
                    ReferenceObjectId           = versionId,
                    ReferenceObjectRecordType   = 'ContractDocumentVersion',
                    ContentType                 = 'StandardDocumentClause',
                    StandardContentObjectType   = 'DocumentClause',
                    StandardContentObjectId     = clauseId,
                    DocAuthoredContentIdentifier = String.valueOf(versionId).left(15)
                        + '-' + String.valueOf(clauseId).left(15),
                    ContentGenerationSource     = 'StandardContent',
                    IsReviewed                  = false,
                    IsLibraryAdditionRequested  = false
                ));
            }
        }
        if (links.isEmpty()) return;

        List<Database.SaveResult> results = Database.insert(links, false);
        for (Integer i = 0; i < results.size(); i++) {
            if (!results[i].isSuccess()) {
                System.debug(LoggingLevel.WARN, 'No se pudo asociar una clausula: '
                    + results[i].getErrors());
            }
        }
    }
}
