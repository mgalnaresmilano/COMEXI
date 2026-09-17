/**
 * Controlador del LWC comexiCaseRetrofitAdvisor (escena 02 del guion Comexi).
 *
 * El agente Agentforce "COMEXI Retrofit Advisor" todavia no existe en la org, asi que
 * el LWC simula su razonamiento. Lo que no se simula es el desenlace: este controlador
 * crea de verdad la Oportunidad de retrofit y su Oferta con el motor de pricing de
 * Revenue Cloud, de modo que las escenas 04 a 08 puedan continuar sobre esos registros.
 *
 * Reglas que condicionan el diseno:
 *
 *  - La Oferta se crea con Place Sales Transaction, nunca con DML directo sobre
 *    Quote / QuoteLineItem. El DML directo deja la oferta con el banner de precios
 *    desactualizados y sin netos calculados.
 *  - Toda la cadena va en EUR. Si la Oportunidad se queda en la moneda corporativa
 *    el discovery busca los PricebookEntry en esa moneda, no encuentra ninguno y PST
 *    falla con "Could not find product with ID ... from ProductDiscovery Service".
 *  - PST no revierte la cabecera de la Quote si fallan las lineas, asi que la guarda
 *    de idempotencia tiene que contemplar cabeceras sin lineas.
 *  - PST tampoco rellena los campos COMEXI_* de coste y margen: se sellan aqui con la
 *    misma logica que scripts/apex/comexi/08_stamp_margins.apex.
 */
public with sharing class COMEXI_RetrofitAdvisorController {

    private static final String CURRENCY_CODE = 'EUR';
    private static final String OPPORTUNITY_STAGE = 'Proposal/Quote';
    private static final String RETROFIT_RECORD_TYPE = 'COMEXI_Retrofitting';

    // Valores narrativos con los que el Advisor "sella" la oportunidad de retrofit.
    // Son deterministas para que la escena 03 salga siempre igual en la demo.
    private static final String OPP_TYPE            = 'Retrofit';
    private static final String OPP_LEAD_SOURCE     = 'Caso de servicio';
    private static final String OPP_NEXT_STEP       = 'Validar ventana de parada y lanzar aprobación de margen';
    private static final String VIABILITY_STATUS    = 'Viable sin ingenieria';
    private static final String RETROFIT_TYPE       = 'RET_OBS';
    private static final String DOWN_PAYMENT_STATUS = 'Pendiente';
    private static final String ADVISOR_VALIDATOR   = 'COMEXI Retrofit Advisor (Agentforce)';
    private static final Decimal ADVISOR_CONFIDENCE = 92;
    private static final Integer INTERVENTION_WEEKS = 6;
    // Umbral de aprobación por margen del guion: por debajo salta la escena 08.
    private static final Decimal MARGIN_APPROVAL_THRESHOLD = 30;
    private static final String RECOMMENDED_SKU = 'T100';

    // Valores con los que el Advisor sella la oferta. El escandallo no se inventa: se
    // hereda de la cuenta (uplift, RALF, riesgo país, comisión, anticipo, idioma), que es
    // donde COMEXI mantiene esas condiciones. Estas constantes solo cubren el caso en que
    // la cuenta venga sin condiciones cargadas, para que la oferta nunca salga vacía.
    private static final String EXPENSES_OWNER               = 'Comexi';
    private static final Decimal RALF_PCT                    = 3.00;
    private static final Decimal FALLBACK_WARRANTY_UPLIFT_PCT = 2.60;
    private static final Decimal FALLBACK_COMMISSION_PCT      = 8.00;
    private static final Decimal FALLBACK_DOWN_PAYMENT_PCT    = 30.00;
    private static final Integer OFFER_VERSION                = 1;

    /** Tramo de cobro estandar. Salirse de aqui anade un nivel de Finance a la aprobacion. */
    private static final String STANDARD_PAYMENT_TERMS = 'Net 30';

    /** Riesgo país de la cuenta traducido al porcentaje que carga la procedura de precios. */
    private static final Map<String, Decimal> COUNTRY_RISK_PCT_BY_LEVEL =
        new Map<String, Decimal>{ 'Bajo' => 1.00, 'Medio' => 2.50, 'Alto' => 5.00 };

    /** Idioma de oferta de la cuenta traducido al código de la plantilla documental. */
    private static final Map<String, String> DOC_LANGUAGE_BY_LABEL = new Map<String, String>{
        'English' => 'en_US', 'Castellano' => 'es', 'Català' => 'ca',
        'Français' => 'fr',   'Deutsch'    => 'de', 'Italiano' => 'it'
    };

    /** Las 9 referencias del retrofit del caso 174535, en el orden del guion. */
    private static final List<String> RETROFIT_SKUS = new List<String>{
        'T100', 'T100-TEMP', 'SRV-MEC', 'SRV-ELE', 'SRV-PME',
        'EXP-FLIGHT', 'EXP-TAXI', 'EXP-HOTEL', 'EXP-MEAL'
    };

    // ─────────────────────────────────────────────────────────────────────────────
    // Briefing del caso
    // ─────────────────────────────────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static CaseBriefing getCaseBriefing(Id caseId) {
        try {
            List<Case> cases = [
                SELECT Id, CaseNumber, Subject, Status, Priority, Origin, Type,
                       Description, CreatedDate, AccountId, Account.Name,
                       ContactId, Contact.Name, Contact.Title, Contact.Phone, Contact.Email,
                       AssetId
                FROM Case
                WHERE Id = :caseId
                WITH USER_MODE
                LIMIT 1
            ];
            if (cases.isEmpty()) {
                throw new AdvisorException('No se encuentra el caso ' + caseId + '.');
            }
            Case c = cases[0];

            CaseBriefing b = new CaseBriefing();
            b.caseId        = c.Id;
            b.caseNumber    = c.CaseNumber;
            b.subject       = c.Subject;
            b.status        = c.Status;
            b.priority      = c.Priority;
            b.origin        = c.Origin;
            b.caseType      = c.Type;
            b.description   = c.Description;
            b.createdDate   = c.CreatedDate;
            b.accountId     = c.AccountId;
            b.accountName   = (c.Account != null) ? c.Account.Name : null;
            b.contactId     = c.ContactId;
            b.contactName   = (c.Contact != null) ? c.Contact.Name : null;
            b.contactTitle  = (c.Contact != null) ? c.Contact.Title : null;
            b.contactPhone  = (c.Contact != null) ? c.Contact.Phone : null;
            b.contactEmail  = (c.Contact != null) ? c.Contact.Email : null;
            b.machine       = loadMachine(c.AssetId);

            // Si la escena ya se ha ejecutado antes, el LWC arranca directamente en el
            // estado final en vez de ofrecer crear un duplicado.
            for (Opportunity opp : [
                SELECT Id, Name FROM Opportunity
                WHERE COMEXI_Source_Case__c = :c.Id
                WITH USER_MODE
                ORDER BY CreatedDate
                LIMIT 1
            ]) {
                b.existingOpportunityId = opp.Id;
                for (Quote q : [
                    SELECT Id, Name FROM Quote
                    WHERE OpportunityId = :opp.Id
                    WITH USER_MODE
                    ORDER BY CreatedDate
                    LIMIT 1
                ]) {
                    b.existingQuoteId = q.Id;
                }
            }
            return b;
        } catch (Exception e) {
            throw asAura(e);
        }
    }

    private static Machine loadMachine(Id assetId) {
        if (assetId == null) return null;

        List<Asset> assets = [
            SELECT Id, Name, SerialNumber, Status, InstallDate,
                   COMEXI_Machine_Model__c, COMEXI_Install_Year__c,
                   COMEXI_Line__c, COMEXI_Installed_Config__c,
                   Product2Id, Product2.Name, Product2.StockKeepingUnit, Product2.DisplayUrl
            FROM Asset
            WHERE Id = :assetId OR ParentId = :assetId
            WITH USER_MODE
            ORDER BY Name
        ];
        if (assets.isEmpty()) return null;

        Machine m = null;
        List<MachineComponent> components = new List<MachineComponent>();
        for (Asset a : assets) {
            if (a.Id == assetId) {
                m = new Machine();
                m.id              = a.Id;
                m.name            = a.Name;
                m.serialNumber    = a.SerialNumber;
                m.status          = a.Status;
                m.model           = a.COMEXI_Machine_Model__c;
                m.line            = a.COMEXI_Line__c;
                m.installedConfig = a.COMEXI_Installed_Config__c;
                m.installYear     = (a.COMEXI_Install_Year__c != null)
                    ? Integer.valueOf(a.COMEXI_Install_Year__c) : null;
                m.ageYears        = (m.installYear != null)
                    ? Date.today().year() - m.installYear : null;
                m.productName     = (a.Product2 != null) ? a.Product2.Name : null;
                m.sku             = (a.Product2 != null) ? a.Product2.StockKeepingUnit : null;
                m.imageUrl        = (a.Product2 != null) ? a.Product2.DisplayUrl : null;
            } else {
                MachineComponent mc = new MachineComponent();
                mc.id           = a.Id;
                mc.name         = a.Name;
                mc.serialNumber = a.SerialNumber;
                mc.config       = a.COMEXI_Installed_Config__c;
                mc.productName  = (a.Product2 != null) ? a.Product2.Name : null;
                mc.sku          = (a.Product2 != null) ? a.Product2.StockKeepingUnit : null;
                // El componente en riesgo es el que corre el sistema operativo fuera de
                // soporte: es el que justifica el retrofit y el que el LWC resalta.
                mc.atRisk = (mc.config != null && mc.config.containsIgnoreCase('Windows'));
                components.add(mc);
            }
        }
        if (m == null) return null;
        m.components = components;
        return m;
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // Creacion real de Oportunidad + Oferta
    // ─────────────────────────────────────────────────────────────────────────────

    @AuraEnabled
    public static AdvisorResult createRetrofitOpportunityAndQuote(Id caseId) {
        try {
            List<Case> cases = [
                SELECT Id, CaseNumber, Subject, Status, Priority, Description, CreatedDate,
                       AccountId, Account.Name, ContactId, Contact.Name, AssetId,
                       Account.BillingCity, Account.BillingCountry,
                       Account.COMEXI_Has_Representative__c,
                       Account.COMEXI_Representative_Commission_Pct__c,
                       Account.COMEXI_Warranty_Uplift_Pct__c,
                       Account.COMEXI_RALF_Applicable__c,
                       Account.COMEXI_Country_Risk__c,
                       Account.COMEXI_Down_Payment_Pct__c,
                       Account.COMEXI_Offer_Language__c
                FROM Case
                WHERE Id = :caseId
                WITH USER_MODE
                LIMIT 1
            ];
            if (cases.isEmpty()) {
                throw new AdvisorException('No se encuentra el caso ' + caseId + '.');
            }
            Case c = cases[0];
            if (c.AccountId == null) {
                throw new AdvisorException(
                    'El caso no tiene cuenta asociada, y la oferta necesita una cuenta facturable.');
            }

            List<Pricebook2> stdPbs = [
                SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1
            ];
            if (stdPbs.isEmpty()) {
                throw new AdvisorException('No hay price book estandar en la org.');
            }
            Id stdPbId = stdPbs[0].Id;

            Opportunity opp = findOrCreateOpportunity(c, stdPbId);
            // Sella los campos custom de retrofit (viabilidad, maquina, alcance) y los
            // estandar (Type, LeadSource, NextStep, Description) con la narrativa del Advisor.
            applyRetrofitFields(opp, c);

            // Idempotencia. Si ya hay una oferta con lineas, se reutiliza: pulsar el
            // boton dos veces durante la demo no debe dejar ofertas duplicadas.
            List<Quote> existing = [
                SELECT Id, Name, TotalPrice, CurrencyIsoCode, CalculationStatus,
                       COMEXI_Total_Cost__c, COMEXI_Blended_Margin_Pct__c,
                       (SELECT Id FROM QuoteLineItems)
                FROM Quote
                WHERE OpportunityId = :opp.Id
                WITH USER_MODE
                ORDER BY CreatedDate
            ];
            List<Quote> emptyHeaders = new List<Quote>();
            for (Quote q : existing) {
                if (!q.QuoteLineItems.isEmpty()) {
                    // Aun reutilizando la oferta, se refrescan el snapshot economico y la
                    // actividad, por si el link se acaba de sellar en este mismo pase.
                    stampOpportunityEconomics(opp.Id, q.Id);
                    applyRetrofitQuoteFields(q.Id, c);
                    copyCaseActivityToOpportunity(c, opp.Id);
                    return buildResult(q.Id, opp.Id, true,
                        'La oferta ya existia. Se reutiliza en vez de duplicarla.');
                }
                emptyHeaders.add(q);
            }
            // PST commitea la cabecera antes que las lineas y no la revierte si las
            // lineas fallan, asi que un intento previo fallido deja una Quote vacia.
            if (!emptyHeaders.isEmpty() && Schema.SObjectType.Quote.isDeletable()) {
                delete emptyHeaders;
            }

            Id quoteId = placeRetrofitQuote(c, opp, stdPbId);
            stampMargins(new Set<Id>{ quoteId });
            // Copia el escandallo de la oferta a los campos snapshot de la oportunidad y
            // registra en su Activity todo lo que venia del caso.
            stampOpportunityEconomics(opp.Id, quoteId);
            applyRetrofitQuoteFields(quoteId, c);
            copyCaseActivityToOpportunity(c, opp.Id);

            return buildResult(quoteId, opp.Id, false,
                'Oportunidad y oferta creadas con el motor de pricing de Revenue Cloud.');
        } catch (Exception e) {
            throw asAura(e);
        }
    }

    /**
     * Vuelve a sellar coste y margen. El pricing de PST puede seguir corriendo cuando
     * la llamada ya ha devuelto, asi que el LWC puede pedir un segundo sellado.
     */
    @AuraEnabled
    public static AdvisorResult refreshQuoteMargins(Id quoteId) {
        try {
            stampMargins(new Set<Id>{ quoteId });
            // Un descuento nuevo puede cruzar el umbral, asi que la bandera de aprobacion
            // se recalcula con el margen recien sellado.
            stampQuoteApprovalFlag(quoteId);
            Id oppId = null;
            for (Quote q : [SELECT OpportunityId FROM Quote WHERE Id = :quoteId WITH USER_MODE LIMIT 1]) {
                oppId = q.OpportunityId;
            }
            return buildResult(quoteId, oppId, true, 'Margenes recalculados.');
        } catch (Exception e) {
            throw asAura(e);
        }
    }

    /**
     * Deshace la escena: borra las ofertas y las oportunidades que el asesor creo para
     * este caso, para poder repetir la demo desde cero. Borra primero las Quote y luego
     * las Opportunity, en ese orden, porque la oferta cuelga de la oportunidad.
     */
    @AuraEnabled
    public static AdvisorResult resetDemoState(Id caseId) {
        try {
            List<Opportunity> opps = [
                SELECT Id FROM Opportunity
                WHERE COMEXI_Source_Case__c = :caseId
                WITH USER_MODE
            ];

            List<Quote> quotes = new List<Quote>();
            List<Task> tasks = new List<Task>();
            List<Event> events = new List<Event>();
            if (!opps.isEmpty()) {
                quotes = [
                    SELECT Id FROM Quote
                    WHERE OpportunityId IN :opps
                    WITH USER_MODE
                ];
                // La actividad que el Advisor copio a la oportunidad se borra tambien,
                // para que el ciclo de la demo quede limpio. La del caso y la cuenta no
                // se tocan: solo se elimina lo que cuelga de las oportunidades.
                tasks = [SELECT Id FROM Task WHERE WhatId IN :opps WITH USER_MODE];
                events = [SELECT Id FROM Event WHERE WhatId IN :opps WITH USER_MODE];
            }

            // El contrato que nace de Create Contract bloquea el borrado de su oferta,
            // y sus versiones de documento bloquean el del contrato. Sin limpiar esta
            // cadena, la demo solo se puede pasar una vez por org.
            List<Contract> contracts = new List<Contract>();
            List<ContractDocumentVersion> versions = new List<ContractDocumentVersion>();
            if (!quotes.isEmpty()) {
                contracts = [
                    SELECT Id FROM Contract
                    WHERE SourceQuoteId IN :quotes
                    WITH USER_MODE
                ];
                if (!contracts.isEmpty()) {
                    versions = [
                        SELECT Id FROM ContractDocumentVersion
                        WHERE ContractId IN :contracts
                        WITH USER_MODE
                    ];
                }
            }

            // Y si la demo llego a la firma, cuelga toda la cadena de fulfillment del
            // pedido. El orden de borrado no es el intuitivo y se descubrio a golpes:
            //
            //   1. FulfillmentLineSourceRel, que es la trazabilidad linea a linea. Sin
            //      quitarla, el pedido responde "associated with the following
            //      fulfillment line source rels".
            //   2. El pedido, pero antes hay que devolverlo a Draft: un pedido activado
            //      no se borra ("unable to modify activated or superseded order").
            //   3. El plan, que arrastra sus pasos. Los pasos NO se borran a mano:
            //      hacerlo en lote falla con INVALID_QUERY_FILTER_OPERATOR porque la
            //      propia plataforma consulta por dentro FulfillmentStepDependency con
            //      ids de 15 caracteres.
            List<Order> orders = new List<Order>();
            List<FulfillmentLineSourceRel> lineRels = new List<FulfillmentLineSourceRel>();
            List<FulfillmentPlan> plans = new List<FulfillmentPlan>();
            if (!quotes.isEmpty()) {
                // Order.QuoteId no admite el filtro != null, asi que se pide por la
                // marca del advisor, que es lo que de verdad identifica estos pedidos.
                Set<Id> quoteIds = new Map<Id, Quote>(quotes).keySet();
                Set<Id> planIds = new Set<Id>();
                for (Order o : [
                    SELECT Id, QuoteId, Status, RLM_FulfillmentPlanIdText__c
                    FROM Order
                    WHERE COMEXI_Generated_By_Advisor__c = true
                    WITH USER_MODE
                ]) {
                    if (!quoteIds.contains(o.QuoteId)) continue;
                    orders.add(new Order(Id = o.Id, Status = 'Draft'));
                    if (String.isNotBlank(o.RLM_FulfillmentPlanIdText__c)) {
                        planIds.add((Id) o.RLM_FulfillmentPlanIdText__c);
                    }
                }
                if (!orders.isEmpty()) {
                    lineRels = [
                        SELECT Id FROM FulfillmentLineSourceRel
                        WHERE SourceLineItemId IN (
                            SELECT Id FROM OrderItem WHERE OrderId IN :orders
                        )
                        WITH USER_MODE
                    ];
                }
                if (!planIds.isEmpty()) {
                    plans = [
                        SELECT Id FROM FulfillmentPlan WHERE Id IN :planIds WITH USER_MODE
                    ];
                }
            }

            Integer deletedQuotes = quotes.size();
            Integer deletedOpps = opps.size();
            Integer deletedActivity = tasks.size() + events.size();
            Integer deletedContracts = contracts.size();
            Integer deletedOrders = orders.size();

            if (!tasks.isEmpty()) delete as user tasks;
            if (!events.isEmpty()) delete as user events;
            if (!lineRels.isEmpty()) delete as user lineRels;
            if (!orders.isEmpty()) {
                update as user orders;   // de vuelta a Draft para poder borrarlos
                delete as user orders;
            }
            if (!plans.isEmpty()) delete as user plans;
            if (!versions.isEmpty()) delete as user versions;
            if (!contracts.isEmpty()) delete as user contracts;
            if (!quotes.isEmpty()) delete as user quotes;
            if (!opps.isEmpty()) delete as user opps;

            AdvisorResult r = new AdvisorResult();
            r.success        = true;
            r.alreadyExisted = false;
            r.message        = (deletedOpps == 0 && deletedQuotes == 0)
                ? 'No habia nada que reiniciar.'
                : 'Demo reiniciada: ' + deletedQuotes + ' oferta(s), '
                    + deletedContracts + ' contrato(s), '
                    + deletedOrders + ' pedido(s), '
                    + deletedOpps + ' oportunidad(es) y ' + deletedActivity
                    + ' actividad(es) eliminadas.';
            return r;
        } catch (DmlException e) {
            // La cadena entera (actividad, trazabilidad de lineas, pedido, plan,
            // documento, contrato, oferta y oportunidad) se borra aqui. Si aun asi
            // algo bloquea, la demo necesita ver el motivo y no un error generico.
            throw asAura(new AdvisorException(
                'No se pudo reiniciar la demo. Detalle: ' + e.getDmlMessage(0)));
        } catch (Exception e) {
            throw asAura(e);
        }
    }

    private static Opportunity findOrCreateOpportunity(Case c, Id stdPbId) {
        List<Opportunity> byCase = [
            SELECT Id, Name, CurrencyIsoCode, Pricebook2Id, COMEXI_Source_Case__c
            FROM Opportunity
            WHERE COMEXI_Source_Case__c = :c.Id
            WITH USER_MODE
            ORDER BY CreatedDate
            LIMIT 1
        ];
        if (!byCase.isEmpty()) return realign(byCase[0], c, stdPbId);

        // La oportunidad del guion pudo crearse antes de que existiera el campo de
        // vinculo (la genero el script 07). Se adopta en vez de crear una gemela.
        List<Opportunity> adoptable = [
            SELECT Id, Name, CurrencyIsoCode, Pricebook2Id, COMEXI_Source_Case__c
            FROM Opportunity
            WHERE AccountId = :c.AccountId
              AND COMEXI_Source_Case__c = NULL
              AND Name LIKE '%Retrofit T100%'
            WITH USER_MODE
            ORDER BY CreatedDate
            LIMIT 1
        ];
        if (!adoptable.isEmpty()) return realign(adoptable[0], c, stdPbId);

        Opportunity opp = new Opportunity(
            Name                  = buildOpportunityName(c),
            AccountId             = c.AccountId,
            StageName             = OPPORTUNITY_STAGE,
            CloseDate             = Date.today().addDays(60),
            CurrencyIsoCode       = CURRENCY_CODE,
            Pricebook2Id          = stdPbId,
            COMEXI_Source_Case__c = c.Id
        );
        Id rtId = retrofitRecordTypeId();
        if (rtId != null) opp.RecordTypeId = rtId;
        insert as user opp;
        return opp;
    }

    /** Realinea moneda, price book y vinculo al caso sin tocar nada mas. */
    private static Opportunity realign(Opportunity opp, Case c, Id stdPbId) {
        Boolean dirty = false;
        if (opp.CurrencyIsoCode != CURRENCY_CODE) {
            opp.CurrencyIsoCode = CURRENCY_CODE;
            dirty = true;
        }
        if (opp.Pricebook2Id == null) {
            opp.Pricebook2Id = stdPbId;
            dirty = true;
        }
        if (opp.COMEXI_Source_Case__c != c.Id) {
            opp.COMEXI_Source_Case__c = c.Id;
            dirty = true;
        }
        if (dirty) update as user opp;
        return opp;
    }

    private static String buildOpportunityName(Case c) {
        String account = (c.Account != null && c.Account.Name != null) ? c.Account.Name : 'Cliente';
        return account + ' - Retrofit T100 (Case ' + narrativeRef(c) + ')';
    }

    /**
     * Numero narrativo del guion. El asunto del caso empieza por la referencia que usa
     * todo el guion (p.ej. "174535 - PC + Win (Asset MSC000600)"), que no coincide con el
     * CaseNumber interno (00001003). Sin esto, la oferta recreada tras un reinicio pasaria
     * a llamarse por el CaseNumber y romperia la continuidad del relato entre escenas.
     */
    private static String narrativeRef(Case c) {
        if (c.Subject != null) {
            Matcher m = Pattern.compile('^\\s*(\\d{4,})').matcher(c.Subject);
            if (m.find()) return m.group(1);
        }
        return c.CaseNumber;
    }

    private static Id retrofitRecordTypeId() {
        Schema.RecordTypeInfo rt = Opportunity.SObjectType.getDescribe()
            .getRecordTypeInfosByDeveloperName().get(RETROFIT_RECORD_TYPE);
        return (rt != null && rt.isAvailable()) ? rt.getRecordTypeId() : null;
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // Sellado de los campos custom de retrofit en la oportunidad
    // ─────────────────────────────────────────────────────────────────────────────

    /**
     * Rellena los 18 campos custom del retrofit y los estandar reutilizados (Type,
     * LeadSource, NextStep, Description, Probability) con la narrativa del Advisor.
     * Es determinista e idempotente: siempre reescribe los mismos valores para que la
     * escena 03 se vea igual aunque la demo se reinicie y se vuelva a lanzar.
     */
    private static void applyRetrofitFields(Opportunity opp, Case c) {
        Machine m = loadMachine(c.AssetId);
        String model    = (m != null) ? m.model : null;
        Integer ageYears = (m != null) ? m.ageYears : null;
        String obsolete = obsoleteComponentLabel(m);

        // Se asigna sin leer opp.RecordTypeId: la oportunidad puede venir de una SOQL
        // que no lo selecciono (ruta de realineado), y leerlo lanzaria SObjectException.
        // Una oportunidad de retrofit siempre debe llevar el record type Retrofitting.
        Id rtId = retrofitRecordTypeId();
        if (rtId != null) opp.RecordTypeId = rtId;
        opp.Type        = OPP_TYPE;
        opp.LeadSource  = OPP_LEAD_SOURCE;
        opp.NextStep    = OPP_NEXT_STEP;
        opp.Probability = 75;
        opp.Description = buildOpportunityDescription(c, model, obsolete);

        opp.COMEXI_Target_Asset__c              = c.AssetId;
        opp.COMEXI_Obsolete_Component__c        = obsolete;
        opp.COMEXI_Viability_Status__c          = VIABILITY_STATUS;
        opp.COMEXI_Needs_Engineering__c         = false;
        opp.COMEXI_Viability_Rationale__c       = buildViabilityRationale(model, ageYears, obsolete);
        opp.COMEXI_Validated_By__c              = ADVISOR_VALIDATOR;
        opp.COMEXI_Advisor_Run_Date__c          = System.now();
        opp.COMEXI_Advisor_Confidence__c        = ADVISOR_CONFIDENCE;
        opp.COMEXI_Retrofit_Type__c             = RETROFIT_TYPE;
        opp.COMEXI_Recommended_SKU__c           = RECOMMENDED_SKU;
        opp.COMEXI_Intervention_Weeks__c        = INTERVENTION_WEEKS;
        opp.COMEXI_Planned_Intervention_Date__c = Date.today().addDays(INTERVENTION_WEEKS * 7);
        opp.COMEXI_Down_Payment_Status__c       = DOWN_PAYMENT_STATUS;

        update as user opp;
    }

    /** El componente en riesgo (el que corre el SO fuera de soporte), como etiqueta legible. */
    private static String obsoleteComponentLabel(Machine m) {
        if (m == null || m.components == null) return null;
        for (MachineComponent mc : m.components) {
            if (mc.atRisk == true) {
                String label = mc.name;
                if (String.isNotBlank(mc.config)) {
                    label += ' · ' + mc.config;
                } else if (String.isNotBlank(mc.productName)) {
                    label += ' · ' + mc.productName;
                }
                return (label != null && label.length() > 255) ? label.substring(0, 255) : label;
            }
        }
        return null;
    }

    private static String buildOpportunityDescription(Case c, String model, String obsolete) {
        String maquina = String.isNotBlank(model) ? model : 'la máquina instalada';
        String comp    = String.isNotBlank(obsolete) ? obsolete : 'un componente fuera de soporte';
        return 'Retrofit T100 (UPDATE PC) sobre ' + maquina + '. Origen: caso '
            + narrativeRef(c) + ' — ' + comp + '. Migración a Windows 11 sin sustituir la '
            + 'máquina. Oferta con 5% de descuento pendiente de aprobación de margen.';
    }

    private static String buildViabilityRationale(String model, Integer ageYears, String obsolete) {
        String maquina = String.isNotBlank(model) ? model : 'la máquina';
        String comp    = String.isNotBlank(obsolete) ? obsolete : 'el PC industrial';
        String edad    = (ageYears != null) ? (' (antigüedad ' + ageYears + ' años)') : '';
        return 'Veredicto del COMEXI Retrofit Advisor: VIABLE SIN INGENIERÍA.\n\n'
            + '• Problema: ' + comp + ' de ' + maquina + edad + ' corre un sistema operativo '
            + 'fuera de soporte. Es un riesgo de continuidad y de auditoría, no un fallo mecánico.\n'
            + '• Solución: retrofit T100 - UPDATE PC. Migra el PC de la línea a Windows 11 '
            + 'reutilizando la máquina; no requiere rediseño ni ingeniería a medida.\n'
            + '• Encaje: entra en el 80% de retrofits que no necesitan ingeniería. Se puede '
            + 'cotizar directamente sin escalar al comité técnico.\n'
            + '• Confianza del análisis: ' + ADVISOR_CONFIDENCE + '%.';
    }

    /**
     * Copia el snapshot economico de la oferta a la oportunidad: importe, coste total,
     * margen y bandera de aprobacion. Asi la escena 03 muestra el numero sin abrir la oferta.
     */
    private static void stampOpportunityEconomics(Id oppId, Id quoteId) {
        List<Quote> qs = [
            SELECT Id, TotalPrice, COMEXI_Total_Cost__c, COMEXI_Blended_Margin_Pct__c
            FROM Quote WHERE Id = :quoteId WITH USER_MODE LIMIT 1
        ];
        if (qs.isEmpty()) return;
        Quote q = qs[0];
        Decimal margin = q.COMEXI_Blended_Margin_Pct__c;

        update as user new Opportunity(
            Id                          = oppId,
            Amount                      = q.TotalPrice,
            COMEXI_Quote_Total_Cost__c  = q.COMEXI_Total_Cost__c,
            COMEXI_Quote_Margin_Pct__c  = margin,
            COMEXI_Approval_Required__c = (margin != null && margin < MARGIN_APPROVAL_THRESHOLD)
        );
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // Sellado de los campos custom de retrofit en la oferta
    // ─────────────────────────────────────────────────────────────────────────────

    /**
     * Rellena los campos de retrofit de la oferta. El escandallo (uplift de garantía,
     * RALF, riesgo país, comisión, anticipo, idioma) se hereda de las condiciones que la
     * cuenta ya tiene cargadas, no de literales: así la escena 06 demuestra que el
     * escandallo es configuración. Si la cuenta viniera sin condiciones se aplican los
     * valores por defecto del guion, para que la oferta nunca se muestre vacía.
     *
     * Debe llamarse despues de stampMargins, porque la bandera de aprobación depende del
     * margen ya calculado. Es idempotente: reescribe siempre los mismos valores.
     */
    private static void applyRetrofitQuoteFields(Id quoteId, Case c) {
        List<Quote> qs = [
            SELECT Id, COMEXI_Blended_Margin_Pct__c
            FROM Quote WHERE Id = :quoteId WITH USER_MODE LIMIT 1
        ];
        if (qs.isEmpty()) return;

        Account a = c.Account;
        Decimal margin = qs[0].COMEXI_Blended_Margin_Pct__c;

        Quote upd = new Quote(Id = quoteId);

        // Contexto: de qué caso y sobre qué máquina va esta oferta.
        upd.COMEXI_Source_Case__c          = c.Id;
        upd.COMEXI_Target_Asset__c         = c.AssetId;
        upd.COMEXI_Retrofit_Type__c        = RETROFIT_TYPE;
        upd.COMEXI_Retrofit_SKU__c         = RECOMMENDED_SKU;
        upd.COMEXI_Generated_By_Advisor__c = true;

        // Intervención: destino, plazo y horas realmente ofertadas.
        upd.COMEXI_Intervention_Site__c        = interventionSite(a);
        upd.COMEXI_Intervention_Country__c     = (a != null) ? a.BillingCountry : null;
        upd.COMEXI_Intervention_Weeks__c       = INTERVENTION_WEEKS;
        upd.COMEXI_Target_Intervention_Date__c = Date.today().addDays(INTERVENTION_WEEKS * 7);
        upd.COMEXI_Intervention_Hours__c       = serviceHours(quoteId);
        upd.COMEXI_Expenses_Owner__c           = EXPENSES_OWNER;

        // Escandallo heredado de las condiciones de la cuenta.
        upd.COMEXI_Warranty_Uplift_Pct__c = (a != null && a.COMEXI_Warranty_Uplift_Pct__c != null)
            ? a.COMEXI_Warranty_Uplift_Pct__c : FALLBACK_WARRANTY_UPLIFT_PCT;
        upd.COMEXI_RALF_Pct__c = (a != null && a.COMEXI_RALF_Applicable__c == false)
            ? 0 : RALF_PCT;
        upd.COMEXI_Country_Risk_Pct__c = countryRiskPct(a);
        upd.COMEXI_Representative_Commission_Pct__c = commissionPct(a);

        // Margen y aprobación: el umbral que dispara la escena 08.
        upd.COMEXI_Margin_Threshold_Pct__c = MARGIN_APPROVAL_THRESHOLD;
        upd.COMEXI_Approval_Required__c    =
            (margin != null && margin < MARGIN_APPROVAL_THRESHOLD);

        /* El circuito nativo de aprobación arranca de cero en cada realineado, y las
           condiciones de pago se fijan en el tramo estándar: la orquestación
           RLM_Quote_Smart_Approval añade un nivel de Finance en cuanto no son Net 30, y
           esta demo habla de descuento, no de cobro. */
        upd.RLM_Approval_Status__c = null;
        upd.RLM_Payment_Terms__c   = STANDARD_PAYMENT_TERMS;

        // Anticipo y documento.
        upd.COMEXI_Down_Payment_Pct__c    = (a != null && a.COMEXI_Down_Payment_Pct__c != null)
            ? a.COMEXI_Down_Payment_Pct__c : FALLBACK_DOWN_PAYMENT_PCT;
        upd.COMEXI_Down_Payment_Status__c = DOWN_PAYMENT_STATUS;
        upd.COMEXI_Offer_Version__c       = OFFER_VERSION;
        upd.COMEXI_Document_Language__c   = documentLanguage(a);

        update as user upd;

        cancelInFlightApprovals(quoteId);
    }

    /**
     * Cierra las orquestaciones de aprobación que sigan vivas sobre la oferta.
     *
     * Limpiar el campo del path no basta: la solicitud anterior seguiría en curso y su
     * work item seguiría apareciendo en la pestaña Approvals, así que al repetir la demo
     * habría dos aprobaciones compitiendo por la misma oferta. Los objetos de Flow
     * Orchestration no admiten USER_MODE. Solo se toca el estado de la instancia:
     * cancelarla cierra sus work items sin borrar la traza.
     */
    private static void cancelInFlightApprovals(Id quoteId) {
        Set<Id> instanceIds = new Set<Id>();
        for (FlowOrchestrationStepInstance step : [
            SELECT OrchestrationInstanceId
            FROM FlowOrchestrationStepInstance
            WHERE RelatedRecord = :quoteId
        ]) {
            instanceIds.add(step.OrchestrationInstanceId);
        }
        if (instanceIds.isEmpty()) return;

        List<FlowOrchestrationInstance> live = [
            SELECT Id, Status
            FROM FlowOrchestrationInstance
            WHERE Id IN :instanceIds
              AND Status IN ('NotStarted', 'InProgress', 'Suspended', 'Error')
        ];
        if (live.isEmpty()) return;

        for (FlowOrchestrationInstance instance : live) {
            instance.Status = 'Canceled';
        }
        update live;
    }

    /** Recalcula solo la bandera de aprobación de la oferta contra el margen ya sellado. */
    private static void stampQuoteApprovalFlag(Id quoteId) {
        List<Quote> qs = [
            SELECT Id, COMEXI_Blended_Margin_Pct__c
            FROM Quote WHERE Id = :quoteId WITH USER_MODE LIMIT 1
        ];
        if (qs.isEmpty()) return;
        Decimal margin = qs[0].COMEXI_Blended_Margin_Pct__c;
        update as user new Quote(
            Id                             = quoteId,
            COMEXI_Margin_Threshold_Pct__c = MARGIN_APPROVAL_THRESHOLD,
            COMEXI_Approval_Required__c    = (margin != null && margin < MARGIN_APPROVAL_THRESHOLD)
        );
    }

    /** Planta donde se interviene: la ciudad de facturación, y si no, el nombre de la cuenta. */
    private static String interventionSite(Account a) {
        if (a == null) return null;
        return String.isNotBlank(a.BillingCity) ? a.BillingCity : a.Name;
    }

    /** Horas de intervención realmente ofertadas: suma de las líneas de servicio SRV-*. */
    private static Decimal serviceHours(Id quoteId) {
        Decimal hours = 0;
        for (QuoteLineItem l : [
            SELECT Quantity
            FROM QuoteLineItem
            WHERE QuoteId = :quoteId AND Product2.StockKeepingUnit LIKE 'SRV-%'
            WITH USER_MODE
        ]) {
            if (l.Quantity != null) hours += l.Quantity;
        }
        return (hours > 0) ? hours : null;
    }

    private static Decimal countryRiskPct(Account a) {
        if (a == null || String.isBlank(a.COMEXI_Country_Risk__c)) {
            return COUNTRY_RISK_PCT_BY_LEVEL.get('Bajo');
        }
        Decimal pct = COUNTRY_RISK_PCT_BY_LEVEL.get(a.COMEXI_Country_Risk__c);
        return (pct != null) ? pct : COUNTRY_RISK_PCT_BY_LEVEL.get('Bajo');
    }

    /** Sin representante no hay comisión; con representante, la que tenga pactada la cuenta. */
    private static Decimal commissionPct(Account a) {
        if (a == null) return FALLBACK_COMMISSION_PCT;
        if (a.COMEXI_Has_Representative__c == false) return 0;
        return (a.COMEXI_Representative_Commission_Pct__c != null)
            ? a.COMEXI_Representative_Commission_Pct__c : FALLBACK_COMMISSION_PCT;
    }

    private static String documentLanguage(Account a) {
        if (a == null || String.isBlank(a.COMEXI_Offer_Language__c)) return 'en_US';
        String code = DOC_LANGUAGE_BY_LABEL.get(a.COMEXI_Offer_Language__c);
        return (code != null) ? code : 'en_US';
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // Actividad: del caso a la oportunidad
    // ─────────────────────────────────────────────────────────────────────────────

    /** Asuntos del ciclo de retrofit que 10_account_activity.apex siembra en la cuenta. */
    private static final Set<String> RETROFIT_ACTIVITY_SUBJECTS = new Set<String>{
        'Send retrofit quote v1 to customer',
        'Follow up on retrofit quote',
        'Confirm line shutdown window with production',
        'Request 30% down payment approval',
        'Present retrofit proposal to Production Director',
        'On-site intervention: T100 retrofit'
    };

    /**
     * Registra en la Activity de la oportunidad todo lo que venia del caso: clona las
     * Task y Event del caso y las del ciclo de retrofit de la cuenta, y anade dos
     * registros propios (el resumen del caso de origen y la traza del Advisor). Los
     * originales del caso y de la cuenta se dejan intactos. Idempotente: si la
     * oportunidad ya tiene actividad, no hace nada.
     */
    private static void copyCaseActivityToOpportunity(Case c, Id oppId) {
        // Guarda de idempotencia: solo se siembra una vez por oportunidad.
        Integer existingTasks = [SELECT COUNT() FROM Task WHERE WhatId = :oppId WITH USER_MODE];
        Integer existingEvents = [SELECT COUNT() FROM Event WHERE WhatId = :oppId WITH USER_MODE];
        if (existingTasks > 0 || existingEvents > 0) return;

        List<Task> newTasks = new List<Task>();
        List<Event> newEvents = new List<Event>();

        // 1) Tareas: la propia del caso + las del ciclo de retrofit en la cuenta.
        for (Task t : [
            SELECT Subject, Status, Priority, TaskSubtype, ActivityDate, WhoId, Description
            FROM Task
            WHERE WhatId = :c.Id
               OR (AccountId = :c.AccountId AND Subject IN :RETROFIT_ACTIVITY_SUBJECTS)
            WITH USER_MODE
        ]) {
            newTasks.add(new Task(
                WhatId       = oppId,
                WhoId        = t.WhoId,
                Subject      = t.Subject,
                Status       = t.Status,
                Priority     = t.Priority,
                TaskSubtype  = t.TaskSubtype,
                ActivityDate = t.ActivityDate,
                Description  = t.Description
            ));
        }

        // 2) Eventos del ciclo de retrofit en la cuenta. Event.Type no existe en esta org.
        for (Event e : [
            SELECT Subject, StartDateTime, EndDateTime, Location, WhoId, Description
            FROM Event
            WHERE AccountId = :c.AccountId AND Subject IN :RETROFIT_ACTIVITY_SUBJECTS
            WITH USER_MODE
        ]) {
            newEvents.add(new Event(
                WhatId        = oppId,
                WhoId         = e.WhoId,
                Subject       = e.Subject,
                StartDateTime = e.StartDateTime,
                EndDateTime   = e.EndDateTime,
                Location      = e.Location,
                Description   = e.Description
            ));
        }

        // 3) Resumen del caso de origen, para que la oportunidad cuente su historia.
        String caseDesc = String.isNotBlank(c.Description)
            ? c.Description
            : 'Caso de servicio que origina el retrofit.';
        newTasks.add(new Task(
            WhatId       = oppId,
            WhoId        = c.ContactId,
            Subject      = 'Caso de origen ' + narrativeRef(c) + ' — ' + safeSubject(c.Subject),
            Status       = 'Completed',
            Priority     = (c.Priority != null) ? c.Priority : 'Normal',
            TaskSubtype  = 'Task',
            ActivityDate = (c.CreatedDate != null) ? c.CreatedDate.date() : Date.today(),
            Description  = caseDesc
        ));

        // 4) Traza del Advisor: deja registrada la recomendacion como actividad completada.
        newTasks.add(new Task(
            WhatId       = oppId,
            WhoId        = c.ContactId,
            Subject      = 'COMEXI Retrofit Advisor · Análisis de viabilidad',
            Status       = 'Completed',
            Priority     = 'High',
            TaskSubtype  = 'Task',
            ActivityDate = Date.today(),
            Description  = 'Recomendación T100 - UPDATE PC. Viable sin ingeniería. '
                + 'Confianza ' + ADVISOR_CONFIDENCE + '%. Ver la justificación completa en el '
                + 'campo "Justificación de viabilidad" de la oportunidad.'
        ));

        if (!newTasks.isEmpty()) insert as user newTasks;
        if (!newEvents.isEmpty()) insert as user newEvents;
    }

    private static String safeSubject(String subject) {
        if (String.isBlank(subject)) return 'Caso de servicio';
        return (subject.length() > 120) ? subject.substring(0, 120) : subject;
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // Place Sales Transaction
    // ─────────────────────────────────────────────────────────────────────────────

    /**
     * Replica el grafo de scripts/apex/comexi/07_place_initial_quote.py: tres grupos
     * de linea (Producto, Intervencion y Gastos) y las 10 lineas del caso.
     */
    private static Id placeRetrofitQuote(Case c, Opportunity opp, Id stdPbId) {
        Map<String, Id> productBySku = new Map<String, Id>();
        Set<Id> productIds = new Set<Id>();
        for (Product2 p : [
            SELECT Id, StockKeepingUnit FROM Product2
            WHERE StockKeepingUnit IN :RETROFIT_SKUS
            WITH USER_MODE
        ]) {
            productBySku.put(p.StockKeepingUnit, p.Id);
            productIds.add(p.Id);
        }
        for (String sku : RETROFIT_SKUS) {
            if (!productBySku.containsKey(sku)) {
                // Guardrail del guion: el asesor solo puede recomendar SKUs que existen.
                throw new AdvisorException(
                    'El catalogo no tiene el producto ' + sku + '. Cargalo antes de generar la oferta.');
            }
        }

        Map<Id, Id> pbeByProduct = new Map<Id, Id>();
        for (PricebookEntry pbe : [
            SELECT Id, Product2Id FROM PricebookEntry
            WHERE Product2Id IN :productIds AND Pricebook2Id = :stdPbId
            WITH USER_MODE
        ]) {
            pbeByProduct.put(pbe.Product2Id, pbe.Id);
        }
        for (String sku : RETROFIT_SKUS) {
            if (!pbeByProduct.containsKey(productBySku.get(sku))) {
                throw new AdvisorException(
                    'El producto ' + sku + ' no tiene entrada en el price book estandar.');
            }
        }

        // La fecha de inicio ancla la oferta al caso, que es lo que cuenta el guion.
        String startDate = String.valueOf(c.CreatedDate.date());

        RevSalesTrxn.RecordResource quoteRecord =
            new RevSalesTrxn.RecordResource(Quote.getSobjectType(), 'POST');
        Map<String, Object> quoteFields = new Map<String, Object>{
            'Name'            => 'Oferta Retrofit T100 - ' + narrativeRef(c),
            'QuoteAccountId'  => c.AccountId,
            'OpportunityId'   => opp.Id,
            'Pricebook2Id'    => stdPbId,
            'CurrencyIsoCode' => CURRENCY_CODE,
            'Description'     => 'Generada por COMEXI Retrofit Advisor desde el caso ' + c.CaseNumber + '.'
        };
        if (c.ContactId != null) {
            quoteFields.put('ContactId', c.ContactId);
        }
        quoteRecord.fieldValues = quoteFields;

        List<RevSalesTrxn.RecordWithReferenceRequest> records =
            new List<RevSalesTrxn.RecordWithReferenceRequest>{
                new RevSalesTrxn.RecordWithReferenceRequest('refQuote', quoteRecord)
            };
        records.add(groupRequest('refGProducto', 'Producto'));
        records.add(groupRequest('refGInterv', 'Intervencion'));
        records.add(groupRequest('refGGastos', 'Gastos'));

        // Producto: bundle T100 con el 5% de descuento del guion, mas el add-on de tinta
        // como linea independiente para poder ensenar "precio basico + 3.600 EUR".
        records.add(lineRequest('refL_T100', productBySku, pbeByProduct, 'T100',
            '@{refGProducto.id}', 1, 5, startDate));
        records.add(lineRequest('refL_TEMP', productBySku, pbeByProduct, 'T100-TEMP',
            '@{refGProducto.id}', 1, null, startDate));
        // Intervencion: horas de montaje mecanico, instalacion electrica y puesta en marcha.
        records.add(lineRequest('refL_MEC', productBySku, pbeByProduct, 'SRV-MEC',
            '@{refGInterv.id}', 16, null, startDate));
        records.add(lineRequest('refL_ELE', productBySku, pbeByProduct, 'SRV-ELE',
            '@{refGInterv.id}', 12, null, startDate));
        records.add(lineRequest('refL_PME', productBySku, pbeByProduct, 'SRV-PME',
            '@{refGInterv.id}', 8, null, startDate));
        // Gastos del desplazamiento a Leeds.
        records.add(lineRequest('refL_FLIGHT', productBySku, pbeByProduct, 'EXP-FLIGHT',
            '@{refGGastos.id}', 1, null, startDate));
        records.add(lineRequest('refL_TAXI', productBySku, pbeByProduct, 'EXP-TAXI',
            '@{refGGastos.id}', 1, null, startDate));
        records.add(lineRequest('refL_HOTEL', productBySku, pbeByProduct, 'EXP-HOTEL',
            '@{refGGastos.id}', 1, null, startDate));
        records.add(lineRequest('refL_MEAL', productBySku, pbeByProduct, 'EXP-MEAL',
            '@{refGGastos.id}', 3, null, startDate));

        RevSalesTrxn.ConfigurationOptionsInput configOptions = new RevSalesTrxn.ConfigurationOptionsInput();
        configOptions.validateProductCatalog    = false;
        configOptions.validateAmendRenewCancel  = false;
        configOptions.executeConfigurationRules = false;
        configOptions.addDefaultConfiguration   = true;

        RevSalesTrxn.PlaceSalesTransactionResponse resp =
            RevSalesTrxn.PlaceSalesTransactionExecutor.execute(
                new RevSalesTrxn.GraphRequest('comexiRetrofitAdvisorGraph', records),
                RevSalesTrxn.PricingPreferenceEnum.SYSTEM,
                // El grafo solo declara el bundle T100, no su componente requerido
                // T100-W11. Con SKIP (el valor por defecto de PST) la oferta sale sin la
                // linea de Windows 11, que es justo el retrofit que se esta vendiendo.
                // SYSTEM deja que el configurador expanda el bundle.
                RevSalesTrxn.ConfigurationExecutionEnum.SYSTEM,
                configOptions,
                null
            );

        if (resp == null || !resp.isSuccess) {
            String detail = (resp != null && resp.errorResponse != null)
                ? String.valueOf(resp.errorResponse)
                : 'Place Sales Transaction no devolvio resultado.';
            throw new AdvisorException('No se pudo crear la oferta: ' + detail);
        }
        return (Id) resp.salesTransactionId;
    }

    private static RevSalesTrxn.RecordWithReferenceRequest groupRequest(String ref, String name) {
        RevSalesTrxn.RecordResource rec =
            new RevSalesTrxn.RecordResource(QuoteLineGroup.getSobjectType(), 'POST');
        rec.fieldValues = new Map<String, Object>{
            'QuoteId' => '@{refQuote.id}',
            'Name'    => name
        };
        return new RevSalesTrxn.RecordWithReferenceRequest(ref, rec);
    }

    private static RevSalesTrxn.RecordWithReferenceRequest lineRequest(
        String ref, Map<String, Id> productBySku, Map<Id, Id> pbeByProduct,
        String sku, String groupRef, Integer quantity, Decimal discount, String startDate
    ) {
        Id productId = productBySku.get(sku);
        RevSalesTrxn.RecordResource rec =
            new RevSalesTrxn.RecordResource(QuoteLineItem.getSobjectType(), 'POST');
        Map<String, Object> fields = new Map<String, Object>{
            'QuoteId'          => '@{refQuote.id}',
            'QuoteLineGroupId' => groupRef,
            'Product2Id'       => productId,
            'PricebookEntryId' => pbeByProduct.get(productId),
            'Quantity'         => String.valueOf(quantity),
            'StartDate'        => startDate
        };
        if (discount != null) {
            fields.put('Discount', discount);
        }
        rec.fieldValues = fields;
        return new RevSalesTrxn.RecordWithReferenceRequest(ref, rec);
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // Sellado de coste y margen
    // ─────────────────────────────────────────────────────────────────────────────

    /**
     * Misma logica que scripts/apex/comexi/08_stamp_margins.apex, acotada a las ofertas
     * indicadas. El pricing procedure reutilizado no expone margen, asi que el escandallo
     * se hace visible en los campos COMEXI_*, que son la base de la deal guidance y del
     * proceso de aprobacion por margen.
     */
    private static void stampMargins(Set<Id> quoteIds) {
        List<Quote> quotes = [
            SELECT Id FROM Quote WHERE Id IN :quoteIds WITH USER_MODE
        ];
        if (quotes.isEmpty()) return;

        List<QuoteLineItem> lines = [
            SELECT Id, QuoteId, Product2Id, Quantity, ListPrice, UnitPrice,
                   NetUnitPrice, TotalPrice
            FROM QuoteLineItem
            WHERE QuoteId IN :quoteIds
            WITH USER_MODE
        ];
        if (lines.isEmpty()) return;

        Set<Id> productIds = new Set<Id>();
        for (QuoteLineItem l : lines) productIds.add(l.Product2Id);

        Map<Id, Decimal> costByProduct = new Map<Id, Decimal>();
        List<CostBook> defaultBooks = [SELECT Id FROM CostBook WHERE IsDefault = true LIMIT 1];
        if (!defaultBooks.isEmpty()) {
            Id costBookId = defaultBooks[0].Id;
            for (CostBookEntry cbe : [
                SELECT ProductId, Cost FROM CostBookEntry
                WHERE CostBookId = :costBookId AND ProductId IN :productIds
                WITH USER_MODE
            ]) {
                costByProduct.put(cbe.ProductId, cbe.Cost);
            }
        }

        Map<Id, Decimal> targetByProduct = new Map<Id, Decimal>();
        for (Product2 p : [
            SELECT Id, COMEXI_Target_Margin_Pct__c FROM Product2
            WHERE Id IN :productIds
            WITH USER_MODE
        ]) {
            targetByProduct.put(p.Id, p.COMEXI_Target_Margin_Pct__c);
        }

        Map<Id, Decimal> costByQuote = new Map<Id, Decimal>();
        Map<Id, Decimal> netByQuote = new Map<Id, Decimal>();
        Map<Id, Decimal> listByQuote = new Map<Id, Decimal>();
        List<QuoteLineItem> lineUpdates = new List<QuoteLineItem>();

        for (QuoteLineItem l : lines) {
            Decimal qty = (l.Quantity == null) ? 1 : l.Quantity;
            Decimal unitCost = costByProduct.containsKey(l.Product2Id)
                ? costByProduct.get(l.Product2Id) : 0;
            // El neto ya lleva el descuento consumido por el motor de pricing.
            Decimal netUnit = (l.NetUnitPrice != null) ? l.NetUnitPrice : l.UnitPrice;
            if (netUnit == null) netUnit = 0;

            Decimal marginPct = (netUnit == 0) ? 0
                : ((netUnit - unitCost) / netUnit * 100).setScale(2, System.RoundingMode.HALF_UP);

            lineUpdates.add(new QuoteLineItem(
                Id                          = l.Id,
                COMEXI_Cost__c              = unitCost,
                COMEXI_Margin_Pct__c        = marginPct,
                COMEXI_Target_Margin_Pct__c = targetByProduct.get(l.Product2Id)
            ));

            Decimal extNet  = (l.TotalPrice != null) ? l.TotalPrice : netUnit * qty;
            Decimal extList = ((l.ListPrice != null) ? l.ListPrice : netUnit) * qty;
            accumulate(costByQuote, l.QuoteId, unitCost * qty);
            accumulate(netByQuote, l.QuoteId, extNet);
            accumulate(listByQuote, l.QuoteId, extList);
        }
        if (!lineUpdates.isEmpty()) update as user lineUpdates;

        List<Quote> quoteUpdates = new List<Quote>();
        for (Quote q : quotes) {
            if (!netByQuote.containsKey(q.Id)) continue;
            Decimal totalCost = costByQuote.get(q.Id);
            Decimal totalNet  = netByQuote.get(q.Id);
            Decimal totalList = listByQuote.get(q.Id);

            Decimal blended = (totalNet == 0) ? 0
                : ((totalNet - totalCost) / totalNet * 100).setScale(2, System.RoundingMode.HALF_UP);
            // Descuento efectivo: cuanto se ha cedido sobre el precio de lista.
            Decimal discount = (totalList == null || totalList == 0) ? 0
                : ((totalList - totalNet) / totalList * 100).setScale(2, System.RoundingMode.HALF_UP);

            quoteUpdates.add(new Quote(
                Id                          = q.Id,
                COMEXI_Total_Cost__c        = totalCost.setScale(2, System.RoundingMode.HALF_UP),
                COMEXI_Blended_Margin_Pct__c = blended,
                COMEXI_Discount_Pct__c      = discount
            ));
        }
        if (!quoteUpdates.isEmpty()) update as user quoteUpdates;
    }

    private static void accumulate(Map<Id, Decimal> target, Id key, Decimal value) {
        Decimal current = target.containsKey(key) ? target.get(key) : 0;
        target.put(key, current + value);
    }

    private static AdvisorResult buildResult(Id quoteId, Id opportunityId,
                                             Boolean alreadyExisted, String message) {
        AdvisorResult r = new AdvisorResult();
        r.success        = true;
        r.alreadyExisted = alreadyExisted;
        r.opportunityId  = opportunityId;
        r.quoteId        = quoteId;
        r.message        = message;

        for (Quote q : [
            SELECT Id, Name, TotalPrice, CurrencyIsoCode, CalculationStatus,
                   COMEXI_Total_Cost__c, COMEXI_Blended_Margin_Pct__c, COMEXI_Discount_Pct__c
            FROM Quote WHERE Id = :quoteId WITH USER_MODE LIMIT 1
        ]) {
            r.quoteName         = q.Name;
            r.totalPrice        = q.TotalPrice;
            r.currencyCode      = q.CurrencyIsoCode;
            r.calculationStatus = q.CalculationStatus;
            r.totalCost         = q.COMEXI_Total_Cost__c;
            r.marginPct         = q.COMEXI_Blended_Margin_Pct__c;
            r.discountPct       = q.COMEXI_Discount_Pct__c;
        }
        r.lineCount = [
            SELECT COUNT() FROM QuoteLineItem WHERE QuoteId = :quoteId WITH USER_MODE
        ];
        return r;
    }

    /**
     * AuraHandledException oculta el mensaje real si no se fija a mano, y sin el mensaje
     * la demo se queda con un "An internal server error has occurred" inservible.
     */
    private static AuraHandledException asAura(Exception e) {
        if (e instanceof AuraHandledException) return (AuraHandledException) e;
        AuraHandledException aura = new AuraHandledException(e.getMessage());
        aura.setMessage(e.getMessage());
        return aura;
    }

    public class AdvisorException extends Exception {}

    // ─────────────────────────────────────────────────────────────────────────────
    // Wrappers
    // ─────────────────────────────────────────────────────────────────────────────

    public class CaseBriefing {
        @AuraEnabled public String caseId;
        @AuraEnabled public String caseNumber;
        @AuraEnabled public String subject;
        @AuraEnabled public String status;
        @AuraEnabled public String priority;
        @AuraEnabled public String origin;
        @AuraEnabled public String caseType;
        @AuraEnabled public String description;
        @AuraEnabled public Datetime createdDate;
        @AuraEnabled public String accountId;
        @AuraEnabled public String accountName;
        @AuraEnabled public String contactId;
        @AuraEnabled public String contactName;
        @AuraEnabled public String contactTitle;
        @AuraEnabled public String contactPhone;
        @AuraEnabled public String contactEmail;
        @AuraEnabled public Machine machine;
        @AuraEnabled public String existingOpportunityId;
        @AuraEnabled public String existingQuoteId;
    }

    public class Machine {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String serialNumber;
        @AuraEnabled public String status;
        @AuraEnabled public String model;
        @AuraEnabled public String line;
        @AuraEnabled public String installedConfig;
        @AuraEnabled public Integer installYear;
        @AuraEnabled public Integer ageYears;
        @AuraEnabled public String productName;
        @AuraEnabled public String sku;
        @AuraEnabled public String imageUrl;
        @AuraEnabled public List<MachineComponent> components;
    }

    public class MachineComponent {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String serialNumber;
        @AuraEnabled public String productName;
        @AuraEnabled public String sku;
        @AuraEnabled public String config;
        @AuraEnabled public Boolean atRisk;
    }

    public class AdvisorResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public Boolean alreadyExisted;
        @AuraEnabled public String opportunityId;
        @AuraEnabled public String quoteId;
        @AuraEnabled public String quoteName;
        @AuraEnabled public String currencyCode;
        @AuraEnabled public String calculationStatus;
        @AuraEnabled public Decimal totalPrice;
        @AuraEnabled public Decimal totalCost;
        @AuraEnabled public Decimal marginPct;
        @AuraEnabled public Decimal discountPct;
        @AuraEnabled public Integer lineCount;
        @AuraEnabled public String message;
    }
}
