// Activa la ultima version de las plantillas Doc Gen que despliega este repositorio,
// y desactiva cualquier otra plantilla COMEXI_ que quede viva en la org.
//
// Las DocumentTemplate llegan siempre inactivas desde el despliegue, por mucho que el
// .dt-meta.xml diga isActive true. Y el desplegable Document Template del modal Create
// Proposal filtra por IsActive = true y UsageType = Revenue_Lifecycle_Management: sin
// este paso la plantilla existe en la org pero no hay forma de elegirla.
//
// Son dos plantillas y no comparten usageType. COMEXI_Propuesta_Retrofit es la oferta y
// va con Revenue_Lifecycle_Management (modal Create Proposal / Generate Quote Document
// de la Quote). COMEXI_Contrato_Retrofit es el contrato de viabilidad y va con
// Contract_Lifecycle_Management, que es lo que ofrece el modal Generate Contract y lo
// que busca COMEXI_ContractDocQueueable al generar el documento automaticamente.
//
// El script equivalente de la base, scripts/apex/activateDocgenTemplates.apex, filtra
// WHERE Name LIKE 'RLM_%', asi que no toca las de COMEXI. De ahi este gemelo.
//
// La lista es explicita a proposito. Un LIKE 'COMEXI_%' resucita plantillas retiradas
// que siguen en la org y las devuelve al desplegable: COMEXI_RetrofitOffer, que era una
// copia de RLM_QuoteProposal sin adaptar, entro asi.
//
// Idempotente: si el estado ya es el correcto no hace DML.

Map<String, String> shipped = new Map<String, String>{
    'COMEXI_Propuesta_Retrofit' => 'Revenue_Lifecycle_Management',
    'COMEXI_Contrato_Retrofit'  => 'Contract_Lifecycle_Management'
};

Map<String, DocumentTemplate> latestByName = new Map<String, DocumentTemplate>();
List<DocumentTemplate> retired = new List<DocumentTemplate>();
for (DocumentTemplate t : [
    SELECT Id, Name, VersionNumber, IsActive, Status, UsageType
    FROM DocumentTemplate
    WHERE Name LIKE 'COMEXI_%'
    ORDER BY Name ASC, VersionNumber ASC
]) {
    if (shipped.containsKey(t.Name)) {
        // Gana la ultima escritura, o sea la version mas alta. Las versiones previas de
        // una plantilla viva se archivan mas abajo: cada despliegue crea una version
        // nueva y dos activas con el mismo nombre duplican la entrada del desplegable.
        DocumentTemplate previous = latestByName.put(t.Name, t);
        if (previous != null && previous.IsActive) {
            retired.add(previous);
        }
    } else if (t.IsActive) {
        retired.add(t);
    }
}

if (latestByName.isEmpty()) {
    System.debug('No hay ninguna de ' + shipped.keySet() + ' en la org. Despliega primero '
        + 'unpackaged/post_comexi/documentTemplates.');
    return;
}

List<DocumentTemplate> toUpdate = new List<DocumentTemplate>();
for (DocumentTemplate t : latestByName.values()) {
    String expected = shipped.get(t.Name);
    if (t.UsageType != expected) {
        System.debug('AVISO: ' + t.Name + ' tiene usageType ' + t.UsageType
            + ' y se esperaba ' + expected + '. No saldra en su desplegable.');
    }
    if (!t.IsActive || t.Status != 'Active') {
        t.IsActive = true;
        t.Status   = 'Active';
        toUpdate.add(t);
        System.debug('Activando ' + t.Name + ' v' + t.VersionNumber);
    }
}
// IsActive y Status van de la mano: la plataforma rechaza un update que baje IsActive
// sin dejar Status en Draft o Archived. Se archiva, no se pasa a Draft, para no perder
// el historial de documentos generados con ella.
for (DocumentTemplate t : retired) {
    t.IsActive = false;
    t.Status   = 'Archived';
    toUpdate.add(t);
    System.debug('Archivando plantilla retirada ' + t.Name + ' v' + t.VersionNumber);
}

if (toUpdate.isEmpty()) {
    System.debug('Nada que cambiar: el estado de las plantillas COMEXI_ ya es el correcto.');
} else {
    update toUpdate;
}

for (DocumentTemplate t : [
    SELECT Name, VersionNumber, IsActive, Status, UsageType
    FROM DocumentTemplate
    WHERE Name LIKE 'COMEXI_%'
    ORDER BY Name ASC, VersionNumber ASC
]) {
    System.debug(t.Name + ' v' + t.VersionNumber + ' | activa=' + t.IsActive
        + ' | estado=' + t.Status + ' | uso=' + t.UsageType);
}
