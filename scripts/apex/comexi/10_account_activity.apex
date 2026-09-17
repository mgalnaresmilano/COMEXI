// 10_account_activity.apex — casos, oportunidades, actividad, notas y pagos de Roberts Mart
// Idempotente (se salta lo que ya existe por asunto/nombre). Ver build-spec/08-seed-data.md.
//
// Sin esto la cuenta se abre vacia: un solo caso, una sola oportunidad sin importe y
// cero actividad. La demo necesita que se vea una relacion de servicio viva, con
// historico cerrado y con cosas pendientes.

Account acc = [SELECT Id, Name FROM Account WHERE Name = 'Roberts Mart Co Ltd' LIMIT 1];

Map<String, Id> contactByName = new Map<String, Id>();
for (Contact c : [SELECT Id, FirstName, LastName FROM Contact WHERE AccountId = :acc.Id]) {
    contactByName.put(c.FirstName + ' ' + c.LastName, c.Id);
}
Id cDavid = contactByName.get('David Prieto');
Id cSarah = contactByName.get('Sarah Hollis');
Id cIan = contactByName.get('Ian Whitfield');
Id cPaul = contactByName.get('Paul Nsofor');

Map<String, Id> assetByName = new Map<String, Id>();
for (Asset a : [SELECT Id, Name FROM Asset WHERE AccountId = :acc.Id]) {
    assetByName.put(a.Name, a.Id);
}

Map<String, Id> oppRt = new Map<String, Id>();
for (RecordType rt : [SELECT Id, DeveloperName FROM RecordType WHERE SobjectType = 'Opportunity']) {
    oppRt.put(rt.DeveloperName, rt.Id);
}

// ============ CASOS ============
Set<String> caseSubjects = new Set<String>();
for (Case c : [SELECT Subject FROM Case WHERE AccountId = :acc.Id]) caseSubjects.add(c.Subject);

List<Case> newCases = new List<Case>();
if (!caseSubjects.contains('Web guiding fault on rewinder - Proslit S2 DS')) {
    newCases.add(new Case(AccountId = acc.Id, ContactId = cSarah,
        Subject = 'Web guiding fault on rewinder - Proslit S2 DS',
        Description = 'Reel drifting approx. 4 mm to the operator side above 300 m/min. '
            + 'Two shifts affected, scrap rate up. Needs a technician on site.',
        Status = 'Escalated', Priority = 'High', Origin = 'Phone', Type = 'Problem',
        Reason = 'Existing problem'));
}
if (!caseSubjects.contains('Glue temperature sensor replacement')) {
    newCases.add(new Case(AccountId = acc.Id, ContactId = cDavid,
        Subject = 'Glue temperature sensor replacement',
        Description = 'Sensor replaced under warranty during the February visit. '
            + 'Readings stable since. Closing the case.',
        Status = 'Closed', Priority = 'Medium', Origin = 'Email', Type = 'Problem',
        Reason = 'Existing problem'));
}
if (!caseSubjects.contains('Spare parts request - slitting knives')) {
    newCases.add(new Case(AccountId = acc.Id, ContactId = cSarah,
        Subject = 'Spare parts request - slitting knives',
        Description = 'Requesting a set of 12 slitting knives for the S2 DS. '
            + 'Please quote with the next intervention to save a shipment.',
        Status = 'New', Priority = 'Low', Origin = 'Web', Type = 'Question'));
}
if (!caseSubjects.contains('Annual preventive service - Proslit S2 DS')) {
    newCases.add(new Case(AccountId = acc.Id, ContactId = cDavid,
        Subject = 'Annual preventive service - Proslit S2 DS',
        Description = 'Scheduling the annual preventive service. Waiting for production to '
            + 'confirm a slot in the shutdown week.',
        Status = 'On Hold', Priority = 'Medium', Origin = 'Phone', Type = 'Question'));
}
if (!caseSubjects.contains('OS end of support - what are our options?')) {
    newCases.add(new Case(AccountId = acc.Id, ContactId = cIan,
        Subject = 'OS end of support - what are our options?',
        Description = 'IT flagged that the line PC runs an operating system out of support. '
            + 'Asking Comexi what the upgrade path is before the next audit.',
        Status = 'Closed', Priority = 'Medium', Origin = 'Email', Type = 'Question'));
}
if (!newCases.isEmpty()) insert newCases;

// Enriquecer el caso original: no tenia contacto ni tipo, y llegaba por Web
// cuando la narrativa dice que lo reporta el Service Manager.
List<Case> orig = [SELECT Id, ContactId, Origin, Type, Priority FROM Case
    WHERE AccountId = :acc.Id AND Subject LIKE '%174535%' LIMIT 1];
if (!orig.isEmpty()) {
    orig[0].ContactId = cDavid;
    orig[0].Origin = 'Email';
    orig[0].Type = 'Question';
    orig[0].Priority = 'High';
    update orig;
}

// ============ OPORTUNIDADES ============
Set<String> oppNames = new Set<String>();
Id retrofitOppId = null;
for (Opportunity o : [SELECT Id, Name FROM Opportunity WHERE AccountId = :acc.Id]) {
    oppNames.add(o.Name);
    if (o.Name.contains('174535')) retrofitOppId = o.Id;
}

List<Opportunity> newOpps = new List<Opportunity>();
if (!oppNames.contains('Roberts Mart - Retrofit T120 automatic taping')) {
    newOpps.add(new Opportunity(AccountId = acc.Id, RecordTypeId = oppRt.get('COMEXI_Retrofitting'),
        Name = 'Roberts Mart - Retrofit T120 automatic taping', StageName = 'Qualification',
        Amount = 12500, CloseDate = Date.newInstance(2026, 11, 30), CurrencyIsoCode = 'EUR',
        Type = 'Add-On Business', LeadSource = 'Referral', Probability = 20,
        Description = 'Surgio en la visita anual: quieren automatizar el encintado para reducir '
            + 'el tiempo de cambio de bobina.'));
}
if (!oppNames.contains('Roberts Mart - Gold service contract 2027')) {
    newOpps.add(new Opportunity(AccountId = acc.Id, RecordTypeId = oppRt.get('COMEXI_Servicio'),
        Name = 'Roberts Mart - Gold service contract 2027', StageName = 'Negotiation',
        Amount = 34000, CloseDate = Date.newInstance(2026, 10, 15), CurrencyIsoCode = 'EUR',
        Type = 'Existing Business', LeadSource = 'Referral', Probability = 70,
        Description = 'Upgrade de Silver a Gold aprovechando que el contrato vence en marzo de 2027. '
            + 'Incluye tiempo de respuesta de 24 h y dos revisiones preventivas al ano.'));
}
if (!oppNames.contains('Roberts Mart - Comexi Proslit S3 (new line)')) {
    newOpps.add(new Opportunity(AccountId = acc.Id, RecordTypeId = oppRt.get('COMEXI_Comercial'),
        Name = 'Roberts Mart - Comexi Proslit S3 (new line)', StageName = 'Discovery',
        Amount = 780000, CloseDate = Date.newInstance(2027, 6, 30), CurrencyIsoCode = 'EUR',
        Type = 'New Business', LeadSource = 'Referral', Probability = 15,
        Description = 'Maquina nueva para sustituir la Proslit S1 del ano 2001, que ya no admite '
            + 'retrofit. Es la conversacion que abre el veredicto de no viabilidad.'));
}
if (!oppNames.contains('Roberts Mart - Retrofit L250 Parker to Sinamics')) {
    newOpps.add(new Opportunity(AccountId = acc.Id, RecordTypeId = oppRt.get('COMEXI_Retrofitting'),
        Name = 'Roberts Mart - Retrofit L250 Parker to Sinamics', StageName = 'Closed Won',
        Amount = 18400, CloseDate = Date.newInstance(2026, 1, 20), CurrencyIsoCode = 'EUR',
        Type = 'Add-On Business', LeadSource = 'Referral',
        Description = 'Migracion de accionamientos ejecutada en enero de 2026. Referencia de que '
            + 'el cliente ya compra retrofits y paga el anticipo del 30% sin friccion.'));
}
if (!oppNames.contains('Roberts Mart - Retrofit C130 flexo productivity')) {
    newOpps.add(new Opportunity(AccountId = acc.Id, RecordTypeId = oppRt.get('COMEXI_Retrofitting'),
        Name = 'Roberts Mart - Retrofit C130 flexo productivity', StageName = 'Closed Lost',
        Amount = 9200, CloseDate = Date.newInstance(2025, 11, 14), CurrencyIsoCode = 'EUR',
        Type = 'Add-On Business', LeadSource = 'Referral',
        Description = 'Perdida por plazo: la oferta tardo tres semanas en salir y el cliente '
            + 'compro el equipo a un tercero. Es el coste real del cuello de botella actual.'));
}
if (!newOpps.isEmpty()) insert newOpps;

// La oportunidad del caso no tenia importe, asi que en el pipeline salia a cero.
if (retrofitOppId != null) {
    update new Opportunity(Id = retrofitOppId, Amount = 16054.32, Probability = 60,
        Type = 'Add-On Business', LeadSource = 'Referral',
        Description = 'Retrofit T100 - UPDATE PC sobre la Proslit S2 DS (MSC000600), con el add-on '
            + 'de control de temperatura de tinta. Oferta con 5% de descuento pendiente de aprobacion '
            + 'de margen.');
}

// ============ ACTIVIDAD ============
Set<String> actSubjects = new Set<String>();
for (Task t : [SELECT Subject FROM Task WHERE AccountId = :acc.Id]) actSubjects.add(t.Subject);
for (Event e : [SELECT Subject FROM Event WHERE AccountId = :acc.Id]) actSubjects.add(e.Subject);

Id caseId = orig.isEmpty() ? null : orig[0].Id;
List<Task> tasks = new List<Task>();
if (!actSubjects.contains('Incoming call: line PC out of support')) {
    tasks.add(new Task(WhatId = caseId != null ? caseId : acc.Id, WhoId = cDavid,
        Subject = 'Incoming call: line PC out of support', Status = 'Completed',
        Priority = 'High', TaskSubtype = 'Call',
        ActivityDate = Date.newInstance(2026, 8, 10),
        Description = 'David reporta que IT les ha marcado el PC de la linea. Pide oferta de '
            + 'actualizacion a Windows 11. Se abre el caso 174535.'));
}
if (!actSubjects.contains('Send retrofit quote v1 to customer')) {
    tasks.add(new Task(WhatId = acc.Id, WhoId = cDavid,
        Subject = 'Send retrofit quote v1 to customer', Status = 'Completed',
        Priority = 'Normal', TaskSubtype = 'Email',
        ActivityDate = Date.newInstance(2026, 8, 14),
        Description = 'Enviada la oferta del T100 con el add-on de temperatura de tinta, en ingles.'));
}
if (!actSubjects.contains('Follow up on retrofit quote')) {
    tasks.add(new Task(WhatId = acc.Id, WhoId = cIan,
        Subject = 'Follow up on retrofit quote', Status = 'Not Started',
        Priority = 'High', TaskSubtype = 'Call',
        ActivityDate = Date.today().addDays(3),
        Description = 'Llamar a Ian para cerrar el descuento del 5% y confirmar la semana de parada.'));
}
if (!actSubjects.contains('Confirm line shutdown window with production')) {
    tasks.add(new Task(WhatId = acc.Id, WhoId = cSarah,
        Subject = 'Confirm line shutdown window with production', Status = 'In Progress',
        Priority = 'Normal', TaskSubtype = 'Task',
        ActivityDate = Date.today().addDays(7),
        Description = 'Necesitamos dos semanas de antelacion. Sarah consulta con produccion.'));
}
if (!actSubjects.contains('Request 30% down payment approval')) {
    tasks.add(new Task(WhatId = acc.Id, WhoId = cPaul,
        Subject = 'Request 30% down payment approval', Status = 'Not Started',
        Priority = 'Normal', TaskSubtype = 'Email',
        ActivityDate = Date.today().addDays(10),
        Description = 'Ingenieria no arranca hasta confirmar el cobro del anticipo.'));
}
if (!tasks.isEmpty()) insert tasks;

List<Event> events = new List<Event>();
if (!actSubjects.contains('Annual installed base review - Leeds')) {
    events.add(new Event(WhatId = acc.Id, WhoId = cDavid,
        Subject = 'Annual installed base review - Leeds',
        StartDateTime = DateTime.newInstance(2026, 2, 18, 9, 0, 0),
        EndDateTime = DateTime.newInstance(2026, 2, 18, 12, 0, 0),
        Location = 'Cross Green Industrial Estate, Leeds',
        Description = 'Revision del parque: se detecta el PC fuera de soporte en la S2 DS y se '
            + 'confirma que la S1 del 2001 ya no admite retrofit estandar.'));
}
if (!actSubjects.contains('Present retrofit proposal to Production Director')) {
    events.add(new Event(WhatId = acc.Id, WhoId = cIan,
        Subject = 'Present retrofit proposal to Production Director',
        StartDateTime = DateTime.now().addDays(5).addHours(1),
        EndDateTime = DateTime.now().addDays(5).addHours(2),
        Location = 'Microsoft Teams',
        Description = 'Presentar la oferta y el impacto en tiempo de parada de la linea.'));
}
if (!actSubjects.contains('On-site intervention: T100 retrofit')) {
    events.add(new Event(WhatId = acc.Id, WhoId = cSarah,
        Subject = 'On-site intervention: T100 retrofit',
        StartDateTime = DateTime.now().addDays(35).addHours(8),
        EndDateTime = DateTime.now().addDays(38).addHours(17),
        Location = 'Cross Green Industrial Estate, Leeds',
        Description = 'Intervencion prevista: 36 h de tecnico (mecanica, electrica y puesta en '
            + 'marcha) en parada programada. Induccion de seguridad el primer dia.'));
}
if (!events.isEmpty()) insert events;

// ============ NOTAS ============
Set<String> noteTitles = new Set<String>();
for (ContentDocumentLink l : [SELECT ContentDocument.Title FROM ContentDocumentLink
        WHERE LinkedEntityId = :acc.Id]) {
    noteTitles.add(l.ContentDocument.Title);
}

Map<String, String> notas = new Map<String, String>();
notas.put('Contexto de la cuenta y del parque instalado',
    '<p>Cliente de Comexi desde 2015. Dos maquinas instaladas:</p>'
  + '<p>1) <b>MSC000600</b> Proslit S2 DS (2015), nucleo de la linea de corte. Su PC sigue con '
  + 'sistema operativo fuera de soporte: es el objeto del retrofit T100.</p>'
  + '<p>2) <b>MSC000123</b> Proslit S1 (2001), a media carga. Retrofit no viable sin ingenieria; '
  + 'la conversacion natural aqui es maquina nueva.</p>'
  + '<p>Atendida por representante local (Midland Converting Services Ltd), lo que anade la '
  + 'comision del 8% al escandallo. Contrato de servicio Silver hasta marzo de 2027.</p>');
notas.put('Condiciones comerciales acordadas',
    '<p>Pago a <b>60 dias</b>. Anticipo del <b>30%</b> a la firma, que condiciona el arranque de '
  + 'ingenieria.</p><p>Uplift de garantia del 2,60% (6 meses desde la aceptacion) y RALF del 3,00% '
  + 'aplicables. Riesgo de pais bajo.</p><p>Toda la documentacion de oferta y contrato debe '
  + 'emitirse en <b>ingles</b>.</p>');
notas.put('Restricciones de la planta para intervenciones',
    '<p>Tres turnos de lunes a sabado: cualquier parada se coordina con dos semanas de antelacion.</p>'
  + '<p>Acceso de mercancia por Pontefract Road, solo camion rigido.</p>'
  + '<p>Induccion de seguridad presencial obligatoria para tecnicos externos (1 h el primer dia).</p>'
  + '<p>El armario electrico de la S2 DS esta en sala tecnica separada, a 40 m de la maquina.</p>');
notas.put('Historico: oferta perdida por plazo (C130)',
    '<p>En noviembre de 2025 perdimos el retrofit C130 (9.200 EUR) porque la oferta tardo '
  + '<b>tres semanas</b> en salir y el cliente compro a un tercero.</p>'
  + '<p>Es el argumento mas fuerte del caso de negocio: el cuello de botella del back-office tiene '
  + 'un coste medible en pedidos perdidos.</p>');

List<ContentNote> newNotes = new List<ContentNote>();
for (String t : notas.keySet()) {
    if (noteTitles.contains(t)) continue;
    newNotes.add(new ContentNote(Title = t, Content = Blob.valueOf(notas.get(t))));
}
if (!newNotes.isEmpty()) {
    insert newNotes;
    List<ContentDocumentLink> links = new List<ContentDocumentLink>();
    for (ContentNote n : newNotes) {
        links.add(new ContentDocumentLink(ContentDocumentId = n.Id, LinkedEntityId = acc.Id,
            ShareType = 'V', Visibility = 'AllUsers'));
    }
    insert links;
}

// ============ PAGOS ============
// El anticipo del retrofit L250 ya cobrado, como evidencia de que el cliente paga
// el 30% sin friccion. Invoice no se puede insertar por API (createable = false):
// la genera el motor de billing desde el Order, que es la escena 11.
List<Payment> pays = new List<Payment>();
if ([SELECT COUNT() FROM Payment WHERE AccountId = :acc.Id] == 0) {
    pays.add(new Payment(AccountId = acc.Id, Amount = 5520, Status = 'Processed',
        Type = 'Sale', ProcessingMode = 'External', CurrencyIsoCode = 'EUR',
        Comments = 'Anticipo del 30% del retrofit L250 (Parker a Sinamics). Transferencia '
            + 'recibida, ingenieria autorizada a arrancar.'));
    pays.add(new Payment(AccountId = acc.Id, Amount = 12880, Status = 'Processed',
        Type = 'Sale', ProcessingMode = 'External', CurrencyIsoCode = 'EUR',
        Comments = 'Liquidacion del 70% restante del retrofit L250 tras la aceptacion.'));
    pays.add(new Payment(AccountId = acc.Id, Amount = 4816.30, Status = 'Pending',
        Type = 'Sale', ProcessingMode = 'External', CurrencyIsoCode = 'EUR',
        Comments = 'Anticipo del 30% del retrofit T100 (caso 174535). Pendiente: bloquea el '
            + 'arranque de ingenieria.'));
}
Integer paysOk = 0;
if (!pays.isEmpty()) {
    List<Database.SaveResult> srs = Database.insert(pays, false);
    for (Integer i = 0; i < srs.size(); i++) {
        if (srs[i].isSuccess()) {
            paysOk++;
        } else {
            System.debug('Payment fallido: ' + srs[i].getErrors()[0].getMessage());
        }
    }
}

System.debug('10_account_activity OK. casos=' + newCases.size() + ' opps=' + newOpps.size()
    + ' tasks=' + tasks.size() + ' events=' + events.size() + ' notas=' + newNotes.size()
    + ' pagos=' + paysOk);
