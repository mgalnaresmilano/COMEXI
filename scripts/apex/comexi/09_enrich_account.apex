// 09_enrich_account.apex — ficha completa de Roberts Mart Co Ltd: cuenta, contactos y base instalada
// Idempotente. Ver build-spec/08-seed-data.md.
//
// La cuenta es la pantalla de entrada de la demo (escena 1), asi que necesita
// densidad de dato realista: direccion completa de Leeds, datos de firma, y los
// campos COMEXI_* que alimentan el escandallo (comision del representante, uplift
// de garantia, RALF, riesgo de pais) y la generacion de oferta (idioma).

Account acc = [SELECT Id, Name FROM Account WHERE Name = 'Roberts Mart Co Ltd' LIMIT 1];

// ---------- Ficha de la cuenta ----------
acc.AccountNumber = 'RM-04412';
acc.Type = 'Customer';
acc.Industry = 'Manufacturing';
acc.Rating = 'Hot';
acc.Ownership = 'Private';
acc.AccountSource = 'Referral';
acc.Phone = '+44 113 249 8800';
acc.Fax = '+44 113 249 8801';
acc.Website = 'www.robertsmart.co.uk';
acc.AnnualRevenue = 48200000;
acc.NumberOfEmployees = 214;
acc.Sic = '2671';
acc.TickerSymbol = null;

acc.BillingStreet = 'Unit 7, Cross Green Industrial Estate\nPontefract Road';
acc.BillingCity = 'Leeds';
acc.BillingState = 'West Yorkshire';
acc.BillingPostalCode = 'LS9 0SF';
acc.BillingCountry = 'United Kingdom';
// La planta de entrega es la misma que la de facturacion: el tecnico interviene alli.
acc.ShippingStreet = 'Unit 7, Cross Green Industrial Estate\nPontefract Road';
acc.ShippingCity = 'Leeds';
acc.ShippingState = 'West Yorkshire';
acc.ShippingPostalCode = 'LS9 0SF';
acc.ShippingCountry = 'United Kingdom';

acc.Description =
    'Transformador de envase flexible del norte de Inglaterra, especializado en film para '
  + 'alimentacion y producto de gran consumo. Cliente de Comexi desde 2015, cuando compro la '
  + 'Proslit S2 DS (MSC000600) que hoy es el nucleo de su linea de corte. Conserva ademas una '
  + 'Proslit S1 del ano 2001 (MSC000123) que trabaja a media carga y para la que un retrofit ya '
  + 'no es viable sin ingenieria a medida. Trabaja a tres turnos de lunes a sabado, asi que toda '
  + 'intervencion se planifica en parada programada. La relacion comercial la atiende un '
  + 'representante local, lo que anade la comision del 8% al escandallo de cada oferta.';

// ---------- Campos COMEXI ----------
acc.COMEXI_Has_Representative__c = true;
acc.COMEXI_Representative_Commission_Pct__c = 8;
acc.COMEXI_Representative_Name__c = 'Midland Converting Services Ltd';
acc.COMEXI_SAP_Customer_Code__c = 'SAP-UK-04412';
acc.COMEXI_Machine_Park_Size__c = 2;
acc.COMEXI_Installed_Base_Value__c = 2850000;
acc.COMEXI_Service_Level__c = 'Silver';
acc.COMEXI_Service_Contract_End__c = Date.newInstance(2027, 3, 31);
acc.COMEXI_Offer_Language__c = 'English';
acc.COMEXI_Country_Risk__c = 'Bajo';
acc.COMEXI_Payment_Terms_Days__c = 60;
acc.COMEXI_Down_Payment_Pct__c = 30;
acc.COMEXI_Warranty_Uplift_Pct__c = 2.60;
acc.COMEXI_RALF_Applicable__c = true;
acc.COMEXI_Last_Intervention_Date__c = Date.newInstance(2026, 2, 18);
acc.COMEXI_Technical_Site_Notes__c =
    'Acceso de mercancia por Pontefract Road; el muelle admite camion rigido pero no trailer.\n'
  + 'Tres turnos de lunes a sabado: cualquier parada de la linea de corte se coordina con '
  + 'produccion con dos semanas de antelacion.\n'
  + 'Exigen induccion de seguridad presencial para tecnicos externos (1 hora, primer dia).\n'
  + 'El armario electrico de la Proslit S2 DS esta en sala tecnica separada, a 40 m de la maquina.\n'
  + 'Idioma de trabajo en planta: ingles. La documentacion de la oferta debe ir en ingles.';

update acc;

// ---------- Contactos ----------
// Los dos del caso real mas los interlocutores que la demo necesita: quien decide,
// quien abre las incidencias en planta y quien valida el pago anticipado.
Map<String, Contact> byName = new Map<String, Contact>();
for (Contact c : [SELECT Id, FirstName, LastName FROM Contact WHERE AccountId = :acc.Id]) {
    byName.put(c.FirstName + ' ' + c.LastName, c);
}

List<Contact> toUpsert = new List<Contact>();

Contact david = byName.get('David Prieto');
if (david != null) {
    david.Title = 'Service Manager';
    david.Email = 'david.prieto@robertsmart.co.uk';
    david.Phone = '+44 113 249 8812';
    david.MobilePhone = '+44 7700 118 244';
    david.Department = 'Service & Maintenance';
    david.MailingStreet = 'Unit 7, Cross Green Industrial Estate';
    david.MailingCity = 'Leeds';
    david.MailingState = 'West Yorkshire';
    david.MailingPostalCode = 'LS9 0SF';
    david.MailingCountry = 'United Kingdom';
    david.Description = 'Interlocutor principal de servicio. Es quien reporta la incidencia del '
        + 'PC de la Proslit S2 DS y quien firma la aceptacion de la intervencion.';
    toUpsert.add(david);
}

Contact ramon = byName.get('Ramon Cabrales');
if (ramon != null) {
    ramon.Title = 'Responsable de configuracion';
    ramon.Email = 'ramon.cabrales@robertsmart.co.uk';
    ramon.Phone = '+44 113 249 8818';
    ramon.Department = 'Engineering';
    ramon.MailingCity = 'Leeds';
    ramon.MailingCountry = 'United Kingdom';
    ramon.Description = 'Valida la configuracion tecnica del retrofit antes de aceptar la oferta.';
    toUpsert.add(ramon);
}
if (!toUpsert.isEmpty()) update toUpsert;

List<Contact> nuevos = new List<Contact>();
if (!byName.containsKey('Ian Whitfield')) {
    nuevos.add(new Contact(AccountId = acc.Id, FirstName = 'Ian', LastName = 'Whitfield',
        Title = 'Production Director', Department = 'Operations',
        Email = 'ian.whitfield@robertsmart.co.uk', Phone = '+44 113 249 8805',
        MobilePhone = '+44 7700 118 190', MailingCity = 'Leeds',
        MailingState = 'West Yorkshire', MailingCountry = 'United Kingdom',
        Description = 'Decisor economico del retrofit. Le importa el tiempo de parada de la '
            + 'linea mas que el precio.'));
}
if (!byName.containsKey('Sarah Hollis')) {
    nuevos.add(new Contact(AccountId = acc.Id, FirstName = 'Sarah', LastName = 'Hollis',
        Title = 'Maintenance Supervisor', Department = 'Service & Maintenance',
        Email = 'sarah.hollis@robertsmart.co.uk', Phone = '+44 113 249 8814',
        MailingCity = 'Leeds', MailingCountry = 'United Kingdom',
        Description = 'Abre la mayoria de las incidencias de planta y acompana al tecnico Comexi '
            + 'durante la intervencion.'));
}
if (!byName.containsKey('Paul Nsofor')) {
    nuevos.add(new Contact(AccountId = acc.Id, FirstName = 'Paul', LastName = 'Nsofor',
        Title = 'Financial Controller', Department = 'Finance',
        Email = 'paul.nsofor@robertsmart.co.uk', Phone = '+44 113 249 8830',
        MailingCity = 'Leeds', MailingCountry = 'United Kingdom',
        Description = 'Autoriza el pago anticipado del 30% que condiciona el arranque de ingenieria.'));
}
if (!nuevos.isEmpty()) insert nuevos;

// ---------- Base instalada ----------
// Los Assets se quedaron en la moneda corporativa (USD) mientras la cuenta, la
// oportunidad y la quote van en EUR, y los componentes no tenian numero de serie
// aunque el checklist del retrofit los presupone.
Id davidId = (david != null) ? david.Id : null;
Id proslitS1 = null;
List<Product2> s1 = [SELECT Id FROM Product2 WHERE StockKeepingUnit = 'MACHINE-PROSLIT-S1' LIMIT 1];
if (s1.isEmpty()) {
    Product2 p = new Product2(Name = 'Comexi Proslit S1', StockKeepingUnit = 'MACHINE-PROSLIT-S1',
        ProductCode = 'MACHINE-PROSLIT-S1', IsActive = true, Family = 'Machines',
        Description = 'Talladora Proslit S1, generacion de los anos 2000. Fuera de catalogo; '
            + 'no admite los retrofits estandar de la serie T sin ingenieria a medida.');
    insert p;
    proslitS1 = p.Id;
} else {
    proslitS1 = s1[0].Id;
}

Map<String, String> serialByName = new Map<String, String>{
    'MSC000600-PC' => 'PC-6001-XP',
    'MSC000600-CPU' => 'CPU-SIM-6002',
    'MSC000600-CU' => 'CU-SIN-6003',
    'MSC000600-SCREEN' => 'SCR-6004-15'
};

List<Asset> assets = [SELECT Id, Name, SerialNumber, CurrencyIsoCode, ContactId, Product2Id,
        ParentId, Description FROM Asset WHERE AccountId = :acc.Id];
List<Asset> assetUpd = new List<Asset>();
for (Asset a : assets) {
    a.CurrencyIsoCode = 'EUR';
    if (a.ContactId == null && davidId != null) a.ContactId = davidId;
    if (serialByName.containsKey(a.Name) && a.SerialNumber == null) {
        a.SerialNumber = serialByName.get(a.Name);
    }
    if (a.Name == 'MSC000123' && a.Product2Id == null) {
        a.Product2Id = proslitS1;
        a.Description = 'Proslit S1 instalada en marzo de 2001. Trabaja a media carga. '
            + 'Retrofit no viable sin ingenieria: el bastidor y el armario no admiten la '
            + 'electronica actual.';
    }
    if (a.Name == 'MSC000600' && String.isBlank(a.Description)) {
        a.Description = 'Proslit S2 DS instalada en junio de 2015, nucleo de la linea de corte. '
            + 'Su PC sigue con sistema operativo fuera de soporte, que es el objeto del retrofit T100.';
    }
    assetUpd.add(a);
}
if (!assetUpd.isEmpty()) update assetUpd;

System.debug('09_enrich_account OK. contactos nuevos=' + nuevos.size()
    + ' assets actualizados=' + assetUpd.size());
